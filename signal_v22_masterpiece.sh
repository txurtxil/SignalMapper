#!/bin/bash
cd /workspaces/SignalMapper/app_nativa

echo "👑 1/2 Forjando la Versión Maestra V22 (Todo Incluido)..."
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

// ================= BBDD =================
class DatabasePro {
  static late Database db;
  static Future<void> init() async {
    db = await openDatabase(p.join(await getDatabasesPath(), 'signal_v22.db'),
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

// ================= TRADUCTOR Y ZONAS MUERTAS =================
bool isCellular(String techOrType) {
  String t = techOrType.toLowerCase();
  return t.contains('4g') || t.contains('5g') || t.contains('lte') || t.contains('nr') || t.contains('cell') || t.contains('móvil') || t.contains('outdoor');
}

String interpretSignal(int dbm, String tech) {
  if (isCellular(tech)) {
    if (dbm >= -85) return "✅ Excelente (Llamadas HD / 4K)";
    if (dbm >= -100) return "🟡 Buena (Audio claro / Redes)";
    if (dbm >= -110) return "🟠 Regular (Cortes leves / Solo textos)";
    return "☠️ ZONA MUERTA (Cortes de llamada seguros)";
  } else {
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
    return Colors.purpleAccent; // MORADO PARA ZONAS MUERTAS
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
        backgroundColor: Colors.black, selectedItemColor: Colors.cyanAccent, unselectedItemColor: Colors.white30,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Indoor Pro"),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: "Outdoor Pro"),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: "Historial"),
        ],
      ),
    );
  }
}

// ================= OUTDOOR PRO (MAPA BLANCO, IMPORT/EXPORT, DATOS FULL) =================
class OutdoorPro extends StatefulWidget { const OutdoorPro({super.key}); @override State<OutdoorPro> createState() => _OutdoorProState(); }
class _OutdoorProState extends State<OutdoorPro> {
  static const platform = MethodChannel('com.signalmapper/power_pro');
  LatLng? currentPos; Map<String, dynamic> currentAudit = {'dbm': 0, 'tech': 'Buscando...', 'operator': '-', 'cell_id': '-', 'rsrq': 0, 'snr': 0};
  String currentStreet = "Esperando satélites...";
  int bestDbm = -200; String bestSpot = "Aún no encontrado";
  final List<CircleMarker> _points = []; final List<LatLng> _routeLine = [];
  String sessionId = ""; bool isTracking = false; Timer? timer; final MapController _mapController = MapController();

  void _toggleTracking() async { 
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("❌ GPS desactivado en el móvil."), backgroundColor: Colors.red));
      return;
    }
    setState(() { 
      isTracking = !isTracking; 
      if (isTracking) {
        sessionId = "Ruta_${DateTime.now().millisecondsSinceEpoch}";
        _routeLine.clear(); _points.clear(); bestDbm = -200; bestSpot = "Aún no encontrado";
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
      String streetName = "Ruta en curso";
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(p.latitude, p.longitude);
        if (placemarks.isNotEmpty) streetName = "\${placemarks.first.thoroughfare}, \${placemarks.first.subLocality}";
      } catch (e) {}

      if (dbm > bestDbm && dbm < 0) { bestDbm = dbm; bestSpot = streetName; }

      await DatabasePro.insertAudit({
        'session_id': sessionId, 'type': 'outdoor', 'dbm': dbm, 'tech': audit['tech'], 'address': streetName,
        'extra_data': "Op: \${audit['operator']} | CID: \${audit['cell_id']} | RSRQ: \${audit['rsrq']} | SNR: \${audit['snr']}",
        'lat': p.latitude, 'lng': p.longitude, 'timestamp': DateTime.now().toIso8601String()
      });
      HapticFeedback.lightImpact();

      if (mounted) setState(() {
        currentPos = pos; currentAudit = audit; currentStreet = streetName;
        _routeLine.add(pos); 
        _points.add(CircleMarker(point: pos, color: getGodColor(dbm, 'cell').withOpacity(0.9), radius: 12, borderColor: Colors.black, borderStrokeWidth: 2));
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
            setState(() { _routeLine.add(pos); _points.add(CircleMarker(point: pos, color: getGodColor(dbm, 'cell'), radius: 12, borderColor: Colors.black, borderStrokeWidth: 2)); });
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
      appBar: AppBar(title: const Text("Mapeo Outdoor", style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.black, actions: [
        IconButton(icon: const Icon(Icons.file_open, color: Colors.cyanAccent), onPressed: _importCSV, tooltip: "Importar Ruta")
      ]),
      body: Stack(children: [
        FlutterMap(mapController: _mapController, options: MapOptions(initialCenter: LatLng(43.297, -2.985), initialZoom: 17), children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.app_nativa'), // MAPA BLANCO DE DÍA
          PolylineLayer(polylines: [Polyline(points: _routeLine, color: Colors.blueAccent.withOpacity(0.7), strokeWidth: 5.0)]),
          CircleLayer(circles: _points),
          if (currentPos != null) MarkerLayer(markers: [Marker(point: currentPos!, child: const Icon(Icons.my_location, color: Colors.blueAccent, size: 30))]),
        ]),
        
        // HUD CON TODOS TUS DATOS FAVORITOS RESTAURADOS
        Positioned(top: 10, left: 10, right: 10, child: Card(
          color: isDeadZone ? Colors.purple[900] : Colors.black87,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: getGodColor(dbm, 'cell'), width: 2)),
          child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
            Text(currentStreet, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            Text("\$dbm dBm | \${currentAudit['tech']}", style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
            Text(interpretSignal(dbm, 'cell'), style: TextStyle(color: isDeadZone ? Colors.white : getGodColor(dbm, 'cell'), fontSize: 14, fontWeight: FontWeight.bold)),
            const Divider(color: Colors.white24),
            Text("Operador: \${currentAudit['operator'] ?? '-'} | Cell ID: \${currentAudit['cell_id'] ?? '-'}", style: const TextStyle(color: Colors.cyanAccent, fontSize: 12, fontFamily: 'monospace')),
            Text("Calidad (RSRQ): \${currentAudit['rsrq'] ?? '-'} | Ruido (SNR): \${currentAudit['snr'] ?? '-'}", style: const TextStyle(color: Colors.cyanAccent, fontSize: 12, fontFamily: 'monospace')),
            const Divider(color: Colors.white24),
            Text("🏆 Mejor punto: \$bestSpot (\$bestDbm dBm)", style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.bold)),
          ]))
        )),

        Positioned(bottom: 20, left: 20, right: 20, child: Column(mainAxisSize: MainAxisSize.min, children: [
          // BOTÓN DE EXPORTAR VISIBLE SI HAY RUTA
          if (!isTracking && _points.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: ElevatedButton.icon(
            onPressed: () async {
              String p = await DatabasePro.exportSessionCSV(sessionId, "Outdoor");
              await Share.shareXFiles([XFile(p)], text: "Ruta 4G/5G finalizada 📡");
            }, 
            icon: const Icon(Icons.share, color: Colors.black), 
            label: const Text("EXPORTAR RUTA ACTUAL", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), 
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amberAccent, minimumSize: const Size(double.infinity, 50))
          )),
          ElevatedButton(
            onPressed: _toggleTracking, 
            style: ElevatedButton.styleFrom(backgroundColor: isTracking ? Colors.redAccent : Colors.cyanAccent, minimumSize: const Size(double.infinity, 60)), 
            child: Text(isTracking ? "PAUSAR MAPEO" : "INICIAR NUEVA RUTA", style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold))
          ),
        ]))
      ]),
    );
  }
}

// ================= INDOOR PRO (MODO HÍBRIDO, IMPORT/EXPORT) =================
class IndoorPro extends StatefulWidget { const IndoorPro({super.key}); @override State<IndoorPro> createState() => _IndoorProState(); }
class _IndoorProState extends State<IndoorPro> {
  static const platform = MethodChannel('com.signalmapper/power_pro');
  File? floorPlan; List<Map<String, dynamic>> indoorPoints = [];
  String sessionId = "Casa_\${DateTime.now().millisecondsSinceEpoch}";
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
      appBar: AppBar(title: const Text("Mapeo Indoor", style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.black, actions: [
        IconButton(icon: const Icon(Icons.file_open, color: Colors.cyanAccent), onPressed: _importIndoorCSV, tooltip: "Importar CSV"),
        IconButton(icon: const Icon(Icons.add_photo_alternate, color: Colors.cyanAccent), onPressed: () async {
          final p = await ImagePicker().pickImage(source: ImageSource.gallery);
          if (p != null) setState(() => floorPlan = File(p.path));
        }, tooltip: "Subir Plano")
      ]),
      backgroundColor: const Color(0xFF1E1E1E),
      body: floorPlan == null ? const Center(child: Text("Sube un plano en el icono de la cámara arriba a la derecha", style: TextStyle(color: Colors.white70))) : Stack(children: [
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
        
        Positioned(top: 10, left: 10, right: 10, child: Card(
          color: isDeadZone ? Colors.purple[900] : Colors.black87,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: getGodColor(dbm, src), width: 2)),
          child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
            Text(interpretSignal(dbm, src), style: TextStyle(color: isDeadZone ? Colors.white : getGodColor(dbm, src), fontSize: 16, fontWeight: FontWeight.bold)),
            Text("\$dbm dBm | \${liveAudit['ssid']}", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            Text(src == 'cell' ? "📡 Usando Antena Móvil (Evaluando Voz)" : "📶 Usando Sensor WiFi", style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.bold)),
          ]))
        )),

        if (indoorPoints.isNotEmpty) Positioned(bottom: 20, left: 20, right: 20, child: ElevatedButton.icon(onPressed: () async {
          String p = await DatabasePro.exportSessionCSV(sessionId, "Indoor");
          await Share.shareXFiles([XFile(p)], text: "Prueba Indoor Finalizada 📡");
        }, icon: const Icon(Icons.save_alt, color: Colors.black), label: const Text("FINALIZAR Y EXPORTAR PLANO", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)), style: ElevatedButton.styleFrom(backgroundColor: Colors.amberAccent, minimumSize: const Size(double.infinity, 50))))
      ]),
    );
  }
}

// ================= HISTORIAL =================
class DatabaseProView extends StatelessWidget {
  const DatabaseProView({super.key});
  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Historial de Mapeos"), backgroundColor: Colors.black),
      backgroundColor: const Color(0xFF1E1E1E),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: DatabasePro.getAudits(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          if (snapshot.data!.isEmpty) return const Center(child: Text("No hay datos guardados aún.", style: TextStyle(color: Colors.white70)));
          return ListView.builder(itemCount: snapshot.data!.length, itemBuilder: (context, index) {
            final a = snapshot.data![index];
            return ListTile(
              leading: CircleAvatar(backgroundColor: getGodColor(a['dbm'], a['tech']), child: Icon(a['type'] == 'indoor' ? Icons.home : Icons.map, color: Colors.black, size: 18)),
              title: Text("\${a['dbm']} dBm | \${a['type']}", style: const TextStyle(color: Colors.white)), 
              subtitle: Text("\${a['tech']}\n\${a['timestamp'].toString().substring(0,16)}", style: const TextStyle(color: Colors.white70))
            );
          });
        },
      ),
    );
  }
}
DART

echo "🚀 2/2 Compilando la Versión Definitiva V22..."
flutter build apk --profile

if [ -f "build/app/outputs/flutter-apk/app-profile.apk" ]; then
    gh release create v22.0-masterpiece build/app/outputs/flutter-apk/app-profile.apk --repo txurtxil/SignalMapper --title "🔥 SignalMapper V22 THE MASTERPIECE" --notes "Fusión final: Mapa de Día, Importar/Exportar, Zonas Muertas (-110dBm Morado), Precisión Indoor Híbrida y todos los datos técnicos profundos (SNR/RSRQ)."
    echo "===================================================="
    echo "✅ ¡COMPILADO AL 100%! La obra de arte está lista."
    echo "Descárgala en: https://github.com/txurtxil/SignalMapper/releases/latest"
    echo "===================================================="
else
    echo "❌ Error al compilar."
fi
