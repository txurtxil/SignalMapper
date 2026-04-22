#!/bin/bash
cd /workspaces/SignalMapper/app_nativa

echo "🔧 1/2 Aplicando parche a la línea punteada forense..."
cat << 'DART' > lib/main.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_selector/file_selector.dart' as fs;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabasePro.init();
  runApp(const MaterialApp(home: PowerProNavigation(), debugShowCheckedModeBanner: false, themeMode: ThemeMode.dark));
}

// ================= BBDD FORENSE =================
class DatabasePro {
  static late Database db;
  static Future<void> init() async {
    db = await openDatabase(p.join(await getDatabasesPath(), 'signal_v24_audit.db'),
      onCreate: (db, version) {
        return db.execute('CREATE TABLE audits(id INTEGER PRIMARY KEY, session_id TEXT, type TEXT, dbm INTEGER, tech TEXT, extra_data TEXT, lat REAL, lng REAL, x REAL, y REAL, address TEXT, timestamp TEXT)');
      }, version: 1);
  }
  static Future<void> insertAudit(Map<String, dynamic> audit) async { await db.insert('audits', audit, conflictAlgorithm: ConflictAlgorithm.replace); }
  static Future<List<Map<String, dynamic>>> getAudits() async { return await db.query('audits', orderBy: 'timestamp DESC'); }
  
  static Future<String> exportSessionCSV(String sessionId, String type) async {
    final data = await db.query('audits', where: 'session_id = ?', whereArgs: [sessionId]);
    String csv = "ID,Sesion,Tipo,DBM,Tecnologia,Extra,Lat,Lng,X,Y,Direccion,Fecha\n";
    for(var row in data) {
      csv += "${row['id']},${row['session_id']},${row['type']},${row['dbm']},${row['tech']},\"${row['extra_data']}\",${row['lat'] ?? ''},${row['lng'] ?? ''},${row['x'] ?? ''},${row['y'] ?? ''},\"${row['address']}\",${row['timestamp']}\n";
    }
    final directory = await getApplicationDocumentsDirectory();
    final path = p.join(directory.path, "Audit_${type}_$sessionId.csv");
    await File(path).writeAsString(csv);
    return path;
  }
}

// ================= TRADUCTOR RF =================
bool isCellular(String techOrType) {
  String t = techOrType.toLowerCase();
  return t.contains('4g') || t.contains('5g') || t.contains('lte') || t.contains('nr') || t.contains('cell') || t.contains('móvil') || t.contains('outdoor');
}

Color getGodColor(int dbm, String tech) {
  if (isCellular(tech)) {
    if (dbm >= -85) return Colors.greenAccent;
    if (dbm >= -100) return Colors.yellowAccent;
    if (dbm >= -110) return Colors.orangeAccent;
    return Colors.purpleAccent; // ZONA MUERTA
  } else {
    if (dbm >= -65) return Colors.greenAccent;
    if (dbm >= -75) return Colors.yellowAccent;
    if (dbm >= -85) return Colors.orangeAccent;
    return Colors.redAccent;
  }
}

// ================= NAVEGACIÓN =================
class PowerProNavigation extends StatefulWidget { const PowerProNavigation({super.key}); @override State<PowerProNavigation> createState() => _PowerProNavigationState(); }
class _PowerProNavigationState extends State<PowerProNavigation> {
  int _currentIndex = 1;
  final List<Widget> _screens = [const IndoorPro(), const OutdoorPro(), const DatabaseProView()];

  @override void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await [Permission.location, Permission.phone].request();
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) await Geolocator.requestPermission();
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex, onTap: (i) => setState(() => _currentIndex = i),
        backgroundColor: Colors.black, selectedItemColor: Colors.greenAccent, unselectedItemColor: Colors.white30,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Indoor"),
          BottomNavigationBarItem(icon: Icon(Icons.radar), label: "Audit Out"),
          BottomNavigationBarItem(icon: Icon(Icons.memory), label: "Logs"),
        ],
      ),
    );
  }
}

// ================= OUTDOOR PRO (MODO FORENSE) =================
class OutdoorPro extends StatefulWidget { const OutdoorPro({super.key}); @override State<OutdoorPro> createState() => _OutdoorProState(); }
class _OutdoorProState extends State<OutdoorPro> {
  static const platform = MethodChannel('com.signalmapper/power_pro');
  LatLng? currentPos; 
  Map<String, dynamic> currentAudit = {'dbm': 0, 'tech': 'ESPERANDO TELEMETRÍA...', 'operator': '-', 'cell_id': '-', 'rsrq': 0, 'snr': 0};
  String currentStreet = "NO FIX";
  
  // CAPAS SEPARADAS PARA EN VIVO Y FORENSE
  final List<CircleMarker> _livePoints = []; 
  final List<LatLng> _liveRoute = [];
  
  final List<CircleMarker> _forensicPoints = []; 
  final List<LatLng> _forensicRoute = [];

  String sessionId = ""; bool isTracking = false; Timer? timer; final MapController _mapController = MapController();

  void _toggleTracking() async { 
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("CRITICAL: GPS OFFLINE"), backgroundColor: Colors.red));
      return;
    }
    setState(() { 
      isTracking = !isTracking; 
      if (isTracking) {
        sessionId = "Audit_${DateTime.now().millisecondsSinceEpoch}";
        _liveRoute.clear(); _livePoints.clear(); currentStreet = "BUSCANDO SATÉLITES...";
        timer = Timer.periodic(const Duration(seconds: 4), (t) => _recordData()); 
        _recordData();
      } else { timer?.cancel(); }
    }); 
  }

  Future<void> _recordData() async {
    try {
      final nativeAudit = await platform.invokeMethod('getCellularAudit');
      final audit = Map<String, dynamic>.from(nativeAudit);
      int dbm = audit['dbm'] ?? -120;

      Position? p;
      try { p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 3)); } 
      catch (e) { p = await Geolocator.getLastKnownPosition(); }
      if (p == null) return;

      LatLng pos = LatLng(p.latitude, p.longitude);
      String streetName = "TRACKING...";
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(p.latitude, p.longitude);
        if (placemarks.isNotEmpty) streetName = "${placemarks.first.thoroughfare}".toUpperCase();
      } catch (e) {}

      await DatabasePro.insertAudit({
        'session_id': sessionId, 'type': 'outdoor', 'dbm': dbm, 'tech': audit['tech'], 'address': streetName,
        'extra_data': "Op: ${audit['operator']} | CID: ${audit['cell_id']} | RSRQ: ${audit['rsrq']} | SNR: ${audit['snr']}",
        'lat': p.latitude, 'lng': p.longitude, 'timestamp': DateTime.now().toIso8601String()
      });
      HapticFeedback.lightImpact();

      if (mounted) setState(() {
        currentPos = pos; currentAudit = audit; currentStreet = streetName;
        _liveRoute.add(pos); 
        _livePoints.add(CircleMarker(point: pos, color: getGodColor(dbm, 'cell'), radius: 10, borderColor: Colors.black, borderStrokeWidth: 2));
      });
      _mapController.move(pos, 17.5);
    } catch (e) {}
  }

  // IMPORTACIÓN FORENSE
  Future<void> _importForensicCSV() async {
    try {
      const fs.XTypeGroup typeGroup = fs.XTypeGroup(label: 'Archivos CSV', extensions: ['csv']);
      final fs.XFile? file = await fs.openFile(acceptedTypeGroups: [typeGroup]);
      if (file != null) {
        File f = File(file.path);
        List<String> lines = await f.readAsLines();
        setState(() { _forensicRoute.clear(); _forensicPoints.clear(); });
        
        for (int i = 1; i < lines.length; i++) {
          List<String> cols = lines[i].split(',');
          if (cols.length > 8 && cols[2] == "outdoor") {
            int dbm = int.parse(cols[3]);
            LatLng pos = LatLng(double.parse(cols[6]), double.parse(cols[7]));
            setState(() { 
              _forensicRoute.add(pos); 
              _forensicPoints.add(CircleMarker(point: pos, color: getGodColor(dbm, 'cell').withOpacity(0.4), radius: 14)); 
            });
            if (i == 1) _mapController.move(pos, 17.0);
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("DATOS FORENSES CARGADOS: ${_forensicPoints.length} puntos"), backgroundColor: Colors.green[900]));
      }
    } catch (e) {}
  }

  void _clearForensics() {
    setState(() { _forensicRoute.clear(); _forensicPoints.clear(); });
  }

  @override Widget build(BuildContext context) {
    int dbm = currentAudit['dbm'] ?? 0;
    bool isDeadZone = dbm < -110 && dbm != 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text("AUDIT OUTDOOR", style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', color: Colors.greenAccent)), 
        backgroundColor: const Color(0xFF121212), 
        actions: [
          if (_forensicPoints.isNotEmpty) IconButton(icon: const Icon(Icons.layers_clear, color: Colors.redAccent), onPressed: _clearForensics, tooltip: "Limpiar Forense"),
          IconButton(icon: const Icon(Icons.manage_search, color: Colors.greenAccent), onPressed: _importForensicCSV, tooltip: "Cargar Ruta Forense")
        ]
      ),
      body: Stack(children: [
        FlutterMap(mapController: _mapController, options: MapOptions(initialCenter: LatLng(43.297, -2.985), initialZoom: 17), children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.app_nativa'),
          // CAPA FORENSE (Fondo) - ERROR DE 'CONST' ARREGLADO AQUÍ ABAJO
          PolylineLayer(polylines: [Polyline(points: _forensicRoute, color: Colors.grey.withOpacity(0.5), strokeWidth: 8.0, pattern: StrokePattern.dashed(segments: [10.0, 10.0]))]),
          CircleLayer(circles: _forensicPoints),
          // CAPA EN VIVO (Encima)
          PolylineLayer(polylines: [Polyline(points: _liveRoute, color: Colors.blueAccent, strokeWidth: 4.0)]),
          CircleLayer(circles: _livePoints),
          if (currentPos != null) MarkerLayer(markers: [Marker(point: currentPos!, child: const Icon(Icons.my_location, color: Colors.blueAccent, size: 30))]),
        ]),
        
        // HUD TERMINAL AUDIT
        Positioned(top: 10, left: 10, right: 10, child: Card(
          color: isDeadZone ? Colors.purple[900]?.withOpacity(0.9) : Colors.black.withOpacity(0.85),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5), side: BorderSide(color: isDeadZone ? Colors.purpleAccent : Colors.greenAccent, width: 1)),
          child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text("[ ${currentAudit['tech']} ]", style: TextStyle(color: isDeadZone ? Colors.white : Colors.greenAccent, fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 16)),
              Text("$dbm dBm", style: TextStyle(color: getGodColor(dbm, 'cell'), fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
            ]),
            const Divider(color: Colors.greenAccent, thickness: 0.5),
            Text("LOC: $currentStreet", style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 12)),
            Text("OPR: ${currentAudit['operator'] ?? '-'} | CID: ${currentAudit['cell_id'] ?? '-'}", style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12)),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text("RSRQ (Quality): ${currentAudit['rsrq'] ?? '-'}", style: const TextStyle(color: Colors.yellowAccent, fontFamily: 'monospace', fontSize: 12)),
              Text("SNR (Noise): ${currentAudit['snr'] ?? '-'}", style: const TextStyle(color: Colors.cyanAccent, fontFamily: 'monospace', fontSize: 12)),
            ]),
            if (isDeadZone) Padding(padding: const EdgeInsets.only(top: 5), child: const Text("WARNING: PACKET DROP EMINENT (DEAD ZONE)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, backgroundColor: Colors.red, fontFamily: 'monospace', fontSize: 11))),
            if (_forensicPoints.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 5), child: const Text("FORENSIC LAYER: ACTIVE", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, backgroundColor: Colors.greenAccent, fontFamily: 'monospace', fontSize: 11))),
          ]))
        )),

        Positioned(bottom: 20, left: 20, right: 20, child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!isTracking && _livePoints.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: ElevatedButton.icon(
            onPressed: () async {
              String p = await DatabasePro.exportSessionCSV(sessionId, "Outdoor");
              await Share.shareXFiles([XFile(p)], text: "Auditoría RF Finalizada");
            }, 
            icon: const Icon(Icons.download, color: Colors.black), label: const Text("EXPORTAR AUDITORÍA", style: TextStyle(color: Colors.black, fontFamily: 'monospace', fontWeight: FontWeight.bold)), 
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white, minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)))
          )),
          ElevatedButton(
            onPressed: _toggleTracking, 
            style: ElevatedButton.styleFrom(backgroundColor: isTracking ? Colors.redAccent : Colors.greenAccent, minimumSize: const Size(double.infinity, 60), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5))), 
            child: Text(isTracking ? "ABORTAR CAPTURA" : "INICIAR AUDITORÍA", style: const TextStyle(color: Colors.black, fontSize: 18, fontFamily: 'monospace', fontWeight: FontWeight.bold))
          ),
        ]))
      ]),
    );
  }
}

// ================= INDOOR PRO (MINIMAL) =================
class IndoorPro extends StatefulWidget { const IndoorPro({super.key}); @override State<IndoorPro> createState() => _IndoorProState(); }
class _IndoorProState extends State<IndoorPro> {
  static const platform = MethodChannel('com.signalmapper/power_pro');
  File? floorPlan; List<Map<String, dynamic>> indoorPoints = [];
  String sessionId = "AuditIn_${DateTime.now().millisecondsSinceEpoch}";
  Map<String, dynamic> liveAudit = {'dbm': 0, 'ssid': 'ESCANEO...', 'source': 'none'};
  Timer? timer;

  @override void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 2), (t) => _updateLiveSignal());
  }

  @override void dispose() { timer?.cancel(); super.dispose(); }

  Future<void> _updateLiveSignal() async {
    try {
      final wifi = Map<String, dynamic>.from(await platform.invokeMethod('getWifiAudit'));
      bool hasWifi = wifi['dbm'] > -110 && !wifi['ssid'].toString().toLowerCase().contains('unknown');
      if (hasWifi) { wifi['source'] = 'wifi'; if (mounted) setState(() => liveAudit = wifi); } 
      else {
        final cell = Map<String, dynamic>.from(await platform.invokeMethod('getCellularAudit'));
        cell['source'] = 'cell'; cell['ssid'] = cell['tech'] ?? 'Red Móvil'; 
        if (mounted) setState(() => liveAudit = cell);
      }
    } catch (e) {}
  }

  void _addPoint(TapDownDetails details) async {
    if (floorPlan == null) return;
    HapticFeedback.mediumImpact();
    final Offset local = details.localPosition; 
    int dbm = liveAudit['dbm'] ?? -120;
    await DatabasePro.insertAudit({'session_id': sessionId, 'type': 'indoor', 'dbm': dbm, 'tech': liveAudit['ssid'] ?? 'Unknown', 'x': local.dx, 'y': local.dy, 'timestamp': DateTime.now().toIso8601String()});
    setState(() { indoorPoints.add({'x': local.dx, 'y': local.dy, 'dbm': dbm, 'source': liveAudit['source']}); });
  }

  @override Widget build(BuildContext context) {
    int dbm = liveAudit['dbm'] ?? 0;
    String src = liveAudit['source'] ?? 'wifi';
    return Scaffold(
      appBar: AppBar(title: const Text("AUDIT INDOOR", style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', color: Colors.greenAccent)), backgroundColor: const Color(0xFF121212), actions: [
        IconButton(icon: const Icon(Icons.add_photo_alternate, color: Colors.greenAccent), onPressed: () async {
          final p = await ImagePicker().pickImage(source: ImageSource.gallery);
          if (p != null) setState(() => floorPlan = File(p.path));
        })
      ]),
      backgroundColor: const Color(0xFF1E1E1E),
      body: floorPlan == null ? const Center(child: Text("CARGAR PLANO PARA INICIAR", style: TextStyle(color: Colors.greenAccent, fontFamily: 'monospace'))) : Stack(children: [
        InteractiveViewer(maxScale: 6.0, child: Center(child: GestureDetector(onTapDown: _addPoint, child: Stack(clipBehavior: Clip.none, children: [
          Image.file(floorPlan!, fit: BoxFit.contain),
          ...indoorPoints.map((p) => Positioned(left: p['x'] - 12, top: p['y'] - 12, child: Container(width: 24, height: 24, decoration: BoxDecoration(color: getGodColor(p['dbm'], p['source'] ?? 'wifi'), shape: BoxShape.circle, border: Border.all(color: Colors.black, width: 2)))))
        ])))),
        Positioned(top: 10, left: 10, right: 10, child: Card(color: Colors.black.withOpacity(0.85), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5), side: BorderSide(color: Colors.greenAccent, width: 1)), child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
          Text("$dbm dBm | ${liveAudit['ssid']}", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
          Text(src == 'cell' ? "[ CELLULAR FALLBACK ]" : "[ WIFI SCANNER ]", style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontFamily: 'monospace')),
        ])))),
        if (indoorPoints.isNotEmpty) Positioned(bottom: 20, left: 20, right: 20, child: ElevatedButton.icon(onPressed: () async {
          String p = await DatabasePro.exportSessionCSV(sessionId, "Indoor");
          await Share.shareXFiles([XFile(p)], text: "Auditoría Indoor Finalizada");
        }, icon: const Icon(Icons.download, color: Colors.black), label: const Text("EXPORTAR AUDITORÍA", style: TextStyle(color: Colors.black, fontFamily: 'monospace', fontWeight: FontWeight.bold)), style: ElevatedButton.styleFrom(backgroundColor: Colors.white, minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)))))
      ]),
    );
  }
}

// ================= HISTORIAL =================
class DatabaseProView extends StatelessWidget {
  const DatabaseProView({super.key});
  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("MEMORY LOGS", style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', color: Colors.greenAccent)), backgroundColor: const Color(0xFF121212)),
      backgroundColor: const Color(0xFF1E1E1E),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: DatabasePro.getAudits(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          if (snapshot.data!.isEmpty) return const Center(child: Text("NO DATA FOUND", style: TextStyle(color: Colors.greenAccent, fontFamily: 'monospace')));
          return ListView.builder(itemCount: snapshot.data!.length, itemBuilder: (context, index) {
            final a = snapshot.data![index];
            return ListTile(
              leading: CircleAvatar(backgroundColor: getGodColor(a['dbm'], a['tech']), child: Icon(a['type'] == 'indoor' ? Icons.home : Icons.radar, color: Colors.black, size: 18)),
              title: Text("${a['dbm']} dBm | ${a['type']}", style: const TextStyle(color: Colors.white, fontFamily: 'monospace')), 
              subtitle: Text("${a['tech']}\n${a['timestamp'].toString().substring(0,16)}", style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace'))
            );
          });
        },
      ),
    );
  }
}
DART

echo "🚀 2/2 Compilando SM Audit (V24.1)..."
flutter build apk --profile

if [ -f "build/app/outputs/flutter-apk/app-profile.apk" ]; then
    gh release create v24.1-audit-fix build/app/outputs/flutter-apk/app-profile.apk --repo txurtxil/SignalMapper --title "🕵️ SM AUDIT V24.1: Forensic Fix" --notes "Parcheado el error de compilación del StrokePattern. El ADN de SM Audit está activo."
    echo "===================================================="
    echo "✅ ¡COMPILADO AL FIN! La versión Hacking Tool está lista."
    echo "Instala el APK desde GitHub, búscalo como 'SM Audit'."
    echo "===================================================="
else
    echo "❌ Error al compilar."
fi
