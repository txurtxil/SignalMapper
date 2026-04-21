#!/bin/bash
cd /workspaces/SignalMapper/app_nativa

echo "☠️ 1/2 Inyectando Algoritmos de Detección de Caída de Llamadas..."
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

// ================= BASE DE DATOS =================
class DatabasePro {
  static late Database db;
  static Future<void> init() async {
    db = await openDatabase(p.join(await getDatabasesPath(), 'signal_v21.db'),
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
    final path = p.join(directory.path, "Export_${type}_$sessionId.csv");
    await File(path).writeAsString(csv);
    return path;
  }
}

// ================= TRADUCTOR DE CORTES DE VOZ =================
bool isCellular(String techOrType) {
  String t = techOrType.toLowerCase();
  return t.contains('4g') || t.contains('5g') || t.contains('lte') || t.contains('nr') || t.contains('cell') || t.contains('móvil') || t.contains('outdoor');
}

String interpretSignal(int dbm, String tech) {
  if (isCellular(tech)) {
    // UMBRALES RED MÓVIL (Llamadas de Voz)
    if (dbm >= -85) return "✅ Excelente (Llamadas HD)";
    if (dbm >= -100) return "🟡 Buena (Audio claro)";
    if (dbm >= -110) return "🟠 Regular (Voz metálica / Cortes leves)";
    return "☠️ ZONA MUERTA (Cortes de llamada seguros)";
  } else {
    // UMBRALES WIFI
    if (dbm >= -65) return "✅ Excelente (Streaming 4K)";
    if (dbm >= -75) return "🟡 Buena (Videollamadas OK)";
    if (dbm >= -85) return "🟠 Regular (Carga lenta)";
    return "🔴 Crítica (Desconexiones WiFi)";
  }
}

Color getGodColor(int dbm, String tech) {
  if (isCellular(tech)) {
    if (dbm >= -85) return Colors.greenAccent;
    if (dbm >= -100) return Colors.yellowAccent;
    if (dbm >= -110) return Colors.orangeAccent;
    return Colors.purpleAccent; // COLOR ESPECIAL PARA ZONAS MUERTAS DE VOZ
  } else {
    if (dbm >= -65) return Colors.greenAccent;
    if (dbm >= -75) return Colors.yellowAccent;
    if (dbm >= -85) return Colors.orangeAccent;
    return Colors.redAccent;
  }
}

// ================= NAVEGACIÓN Y PERMISOS =================
class PowerProNavigation extends StatefulWidget { const PowerProNavigation({super.key}); @override State<PowerProNavigation> createState() => _PowerProNavigationState(); }
class _PowerProNavigationState extends State<PowerProNavigation> {
  int _currentIndex = 0;
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
        backgroundColor: Colors.black, selectedItemColor: Colors.cyanAccent, unselectedItemColor: Colors.white30,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Indoor"),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: "Outdoor"),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: "Historial"),
        ],
      ),
    );
  }
}

// ================= OUTDOOR =================
class OutdoorPro extends StatefulWidget { const OutdoorPro({super.key}); @override State<OutdoorPro> createState() => _OutdoorProState(); }
class _OutdoorProState extends State<OutdoorPro> {
  static const platform = MethodChannel('com.signalmapper/power_pro');
  LatLng? currentPos; Map<String, dynamic> currentAudit = {'dbm': 0, 'tech': 'Iniciando...', 'operator': '-', 'cell_id': '-'};
  String currentStreet = "Esperando GPS...";
  final List<CircleMarker> _points = []; final List<LatLng> _routeLine = [];
  String sessionId = ""; bool isTracking = false; Timer? timer; final MapController _mapController = MapController();

  void _toggleTracking() async { 
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("❌ ERROR: GPS desactivado."), backgroundColor: Colors.red));
      return;
    }
    setState(() { 
      isTracking = !isTracking; 
      if (isTracking) {
        sessionId = "Ruta_${DateTime.now().millisecondsSinceEpoch}";
        _routeLine.clear(); _points.clear(); currentStreet = "Buscando satélites...";
        timer = Timer.periodic(const Duration(seconds: 4), (t) => _recordData()); 
        _recordData();
      } else { timer?.cancel(); }
    }); 
  }

  Future<void> _recordData() async {
    try {
      final nativeAudit = await platform.invokeMethod('getCellularAudit');
      final audit = Map<String, dynamic>.from(nativeAudit);
      Position? p;
      try { p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 3)); } 
      catch (e) { p = await Geolocator.getLastKnownPosition(); }
      if (p == null) return;

      LatLng pos = LatLng(p.latitude, p.longitude);
      await DatabasePro.insertAudit({
        'session_id': sessionId, 'type': 'outdoor', 'dbm': audit['dbm'], 'tech': audit['tech'], 'lat': p.latitude, 'lng': p.longitude, 'timestamp': DateTime.now().toIso8601String()
      });
      HapticFeedback.lightImpact();
      if (mounted) setState(() {
        currentPos = pos; currentAudit = audit; currentStreet = "Ubicación fijada";
        _routeLine.add(pos); 
        _points.add(CircleMarker(point: pos, color: getGodColor(audit['dbm'] ?? -120, 'cell'), radius: 10));
      });
      _mapController.move(pos, 17.5);
    } catch (e) {}
  }

  Future<void> _importCSV() async {
    try {
      const fs.XTypeGroup typeGroup = fs.XTypeGroup(label: 'Archivos CSV', extensions: ['csv']);
      final fs.XFile? file = await fs.openFile(acceptedTypeGroups: [typeGroup]);
      if (file != null) {
        File f = File(file.path);
        List<String> lines = await f.readAsLines();
        setState(() { _routeLine.clear(); _points.clear(); });
        for (int i = 1; i < lines.length; i++) {
          List<String> cols = lines[i].split(',');
          if (cols.length > 8 && cols[2] == "outdoor") {
            int dbm = int.parse(cols[3]);
            LatLng pos = LatLng(double.parse(cols[6]), double.parse(cols[7]));
            setState(() { _routeLine.add(pos); _points.add(CircleMarker(point: pos, color: getGodColor(dbm, 'cell'), radius: 10)); });
            if (i == 1) _mapController.move(pos, 17.0);
          }
        }
      }
    } catch (e) {}
  }

  @override Widget build(BuildContext context) {
    int dbm = currentAudit['dbm'] ?? 0;
    bool isDeadZone = dbm < -110 && dbm != 0;

    return Scaffold(
      appBar: AppBar(title: const Text("Outdoor Pro"), backgroundColor: Colors.black, actions: [IconButton(icon: const Icon(Icons.file_open), onPressed: _importCSV)]),
      body: Stack(children: [
        FlutterMap(mapController: _mapController, options: MapOptions(initialCenter: LatLng(43.297, -2.985), initialZoom: 17), children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.app_nativa'),
          PolylineLayer(polylines: [Polyline(points: _routeLine, color: Colors.blueAccent, strokeWidth: 4)]),
          CircleLayer(circles: _points),
          if (currentPos != null) MarkerLayer(markers: [Marker(point: currentPos!, child: const Icon(Icons.my_location, color: Colors.blueAccent, size: 35))]),
        ]),
        
        // HUD CON ALERTA DE CORTES
        Positioned(top: 10, left: 10, right: 10, child: Card(
          color: isDeadZone ? Colors.purple[900] : Colors.black87, // El HUD se vuelve morado si se caen las llamadas
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: getGodColor(dbm, 'cell'), width: 2)),
          child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
            Text(interpretSignal(dbm, 'cell'), style: TextStyle(color: isDeadZone ? Colors.white : getGodColor(dbm, 'cell'), fontSize: 16, fontWeight: FontWeight.bold)),
            Text("${currentAudit['dbm']} dBm | ${currentAudit['tech']}", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            Text("Op: ${currentAudit['operator'] ?? '-'} | CID: ${currentAudit['cell_id'] ?? '-'}", style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]))
        )),

        Positioned(bottom: 20, left: 20, right: 20, child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!isTracking && _points.isNotEmpty) ElevatedButton.icon(onPressed: () async {
            String p = await DatabasePro.exportSessionCSV(sessionId, "Outdoor");
            await Share.shareXFiles([XFile(p)]);
          }, icon: const Icon(Icons.share, color: Colors.black), label: const Text("EXPORTAR RUTA", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), style: ElevatedButton.styleFrom(backgroundColor: Colors.amberAccent, minimumSize: const Size(double.infinity, 50))),
          ElevatedButton(onPressed: _toggleTracking, style: ElevatedButton.styleFrom(backgroundColor: isTracking ? Colors.redAccent : Colors.cyanAccent, minimumSize: const Size(double.infinity, 60)), child: Text(isTracking ? "PARAR" : "INICIAR RUTA", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold))),
        ]))
      ]),
    );
  }
}

// ================= INDOOR =================
class IndoorPro extends StatefulWidget { const IndoorPro({super.key}); @override State<IndoorPro> createState() => _IndoorProState(); }
class _IndoorProState extends State<IndoorPro> {
  static const platform = MethodChannel('com.signalmapper/power_pro');
  File? floorPlan; List<Map<String, dynamic>> indoorPoints = [];
  String sessionId = "Casa_${DateTime.now().millisecondsSinceEpoch}";
  Map<String, dynamic> liveAudit = {'dbm': 0, 'ssid': 'Buscando...', 'source': 'none'};
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
      
      if (hasWifi) {
        wifi['source'] = 'wifi';
        if (mounted) setState(() => liveAudit = wifi);
      } else {
        final cell = Map<String, dynamic>.from(await platform.invokeMethod('getCellularAudit'));
        cell['source'] = 'cell';
        cell['ssid'] = cell['tech'] ?? 'Red Móvil'; 
        if (mounted) setState(() => liveAudit = cell);
      }
    } catch (e) {}
  }

  Future<void> _importIndoorCSV() async {
    try {
      const fs.XTypeGroup typeGroup = fs.XTypeGroup(label: 'Archivos CSV', extensions: ['csv']);
      final fs.XFile? file = await fs.openFile(acceptedTypeGroups: [typeGroup]);
      if (file != null) {
        File f = File(file.path);
        List<String> lines = await f.readAsLines();
        setState(() { indoorPoints.clear(); });
        for (int i = 1; i < lines.length; i++) {
          List<String> cols = lines[i].split(',');
          if (cols.length > 9 && cols[2] == "indoor") {
            setState(() { indoorPoints.add({'x': double.parse(cols[8]), 'y': double.parse(cols[9]), 'dbm': int.parse(cols[3]), 'source': isCellular(cols[4]) ? 'cell' : 'wifi'}); });
          }
        }
      }
    } catch (e) {}
  }

  void _addPoint(TapDownDetails details) async {
    if (floorPlan == null) return;
    HapticFeedback.mediumImpact();
    final Offset local = details.localPosition; 
    int dbm = liveAudit['dbm'] ?? -120;
    String tech = liveAudit['ssid'] ?? 'Unknown';

    await DatabasePro.insertAudit({
      'session_id': sessionId, 'type': 'indoor', 'dbm': dbm, 'tech': tech, 'x': local.dx, 'y': local.dy, 'timestamp': DateTime.now().toIso8601String()
    });
    setState(() { indoorPoints.add({'x': local.dx, 'y': local.dy, 'dbm': dbm, 'source': liveAudit['source']}); });
  }

  @override Widget build(BuildContext context) {
    int dbm = liveAudit['dbm'] ?? 0;
    String src = liveAudit['source'] ?? 'wifi';
    bool isDeadZone = src == 'cell' && dbm < -110 && dbm != 0;

    return Scaffold(
      appBar: AppBar(title: const Text("Indoor Pro"), backgroundColor: Colors.black, actions: [
        IconButton(icon: const Icon(Icons.file_open), onPressed: _importIndoorCSV),
        IconButton(icon: const Icon(Icons.add_photo_alternate), onPressed: () async {
          final p = await ImagePicker().pickImage(source: ImageSource.gallery);
          if (p != null) setState(() => floorPlan = File(p.path));
        })
      ]),
      backgroundColor: const Color(0xFF1E1E1E),
      body: floorPlan == null ? const Center(child: Text("Sube un plano en el icono de la foto", style: TextStyle(color: Colors.white70))) : Stack(children: [
        InteractiveViewer(
          maxScale: 6.0,
          child: Center(
            child: GestureDetector(
              onTapDown: _addPoint, 
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Image.file(floorPlan!, fit: BoxFit.contain),
                  ...indoorPoints.map((p) => Positioned(
                    left: p['x'] - 12, top: p['y'] - 12, 
                    child: Container(width: 24, height: 24, decoration: BoxDecoration(color: getGodColor(p['dbm'], p['source'] ?? 'wifi'), shape: BoxShape.circle, border: Border.all(color: Colors.black, width: 2)))
                  ))
                ]
              )
            )
          )
        ),
        
        // HUD CON ALERTA INDOOR
        Positioned(top: 10, left: 10, right: 10, child: Card(
          color: isDeadZone ? Colors.purple[900] : Colors.black87,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: getGodColor(dbm, src), width: 2)),
          child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
            Text(interpretSignal(dbm, src), style: TextStyle(color: isDeadZone ? Colors.white : getGodColor(dbm, src), fontSize: 16, fontWeight: FontWeight.bold)),
            Text("${liveAudit['dbm']} dBm | ${liveAudit['ssid']}", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            Text(src == 'cell' ? "📡 Antena Móvil (Evaluando Voz)" : "📶 Sensor WiFi", style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.bold)),
          ]))
        )),

        if (indoorPoints.isNotEmpty) Positioned(bottom: 20, left: 20, right: 20, child: ElevatedButton.icon(onPressed: () async {
          String p = await DatabasePro.exportSessionCSV(sessionId, "Indoor");
          await Share.shareXFiles([XFile(p)]);
        }, icon: const Icon(Icons.save_alt, color: Colors.black), label: const Text("FINALIZAR Y EXPORTAR", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), style: ElevatedButton.styleFrom(backgroundColor: Colors.amberAccent, minimumSize: const Size(double.infinity, 50))))
      ]),
    );
  }
}

// ================= HISTORIAL =================
class DatabaseProView extends StatelessWidget {
  const DatabaseProView({super.key});
  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Historial"), backgroundColor: Colors.black),
      backgroundColor: const Color(0xFF1E1E1E),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: DatabasePro.getAudits(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          return ListView.builder(itemCount: snapshot.data!.length, itemBuilder: (context, index) {
            final a = snapshot.data![index];
            return ListTile(
              leading: CircleAvatar(backgroundColor: getGodColor(a['dbm'], a['tech']), child: Icon(a['type'] == 'indoor' ? Icons.home : Icons.map, color: Colors.black, size: 18)),
              title: Text("${a['dbm']} dBm | ${a['type']}", style: const TextStyle(color: Colors.white)), 
              subtitle: Text("${a['tech']}\n${a['timestamp'].toString().substring(0,16)}", style: const TextStyle(color: Colors.white70))
            );
          });
        },
      ),
    );
  }
}
DART

echo "🚀 2/2 Compilando v21 Blackspots..."
flutter build apk --profile

if [ -f "build/app/outputs/flutter-apk/app-profile.apk" ]; then
    gh release create v21.0-blackspots build/app/outputs/flutter-apk/app-profile.apk --repo txurtxil/SignalMapper --title "🔥 SignalMapper V21 BLACKSPOT DETECTOR" --notes "Sistema de alertas para caídas de llamadas (<-110 dBm). Distinción lógica entre WiFi y 4G/5G con colores y textos dedicados."
    echo "===================================================="
    echo "✅ ¡COMPILADO! Listo para cazar puntos negros."
    echo "===================================================="
else
    echo "❌ Error al compilar."
fi
