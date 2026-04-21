#!/bin/bash
cd /workspaces/SignalMapper/app_nativa

echo "🛠️ 1/2 Integrando Exportación de Rutas en Outdoor..."
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
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabasePro.init();
  runApp(const MaterialApp(home: PowerProNavigation(), debugShowCheckedModeBanner: false, themeMode: ThemeMode.dark));
}

// ================= BBDD V15 =================
class DatabasePro {
  static late Database db;
  static Future<void> init() async {
    db = await openDatabase(p.join(await getDatabasesPath(), 'signal_v15.db'),
      onCreate: (db, version) {
        return db.execute('CREATE TABLE audits(id INTEGER PRIMARY KEY, session_id TEXT, type TEXT, dbm INTEGER, tech TEXT, extra_data TEXT, lat REAL, lng REAL, x REAL, y REAL, address TEXT, timestamp TEXT)');
      }, version: 1);
  }
  static Future<void> insertAudit(Map<String, dynamic> audit) async { await db.insert('audits', audit, conflictAlgorithm: ConflictAlgorithm.replace); }
  static Future<List<Map<String, dynamic>>> getAudits() async { return await db.query('audits', orderBy: 'timestamp DESC'); }
  
  static Future<String> exportCSV() async {
    final data = await getAudits();
    return _generateCSV(data, "SignalMapper_Global");
  }

  static Future<String> exportSessionCSV(String sessionId, String type) async {
    final data = await db.query('audits', where: 'session_id = ?', whereArgs: [sessionId]);
    return _generateCSV(data, "Reporte_${type}_$sessionId");
  }

  static Future<String> _generateCSV(List<Map<String, dynamic>> data, String fileName) async {
    String csv = "ID,Sesion,Tipo,DBM,Tecnologia,Extra,Lat,Lng,X,Y,Direccion,Fecha\n";
    for(var row in data) {
      csv += "${row['id']},${row['session_id']},${row['type']},${row['dbm']},${row['tech']},\"${row['extra_data']}\",${row['lat'] ?? ''},${row['lng'] ?? ''},${row['x'] ?? ''},${row['y'] ?? ''},\"${row['address']}\",${row['timestamp']}\n";
    }
    final directory = await getApplicationDocumentsDirectory();
    final path = p.join(directory.path, "$fileName.csv");
    await File(path).writeAsString(csv);
    return path;
  }
}

// Colores y utilidades
Color getGodColor(int dbm) {
  if (dbm >= -75) return Colors.greenAccent;
  if (dbm >= -90) return Colors.yellowAccent;
  if (dbm >= -105) return Colors.orangeAccent;
  return Colors.redAccent;
}

class PowerProNavigation extends StatefulWidget { const PowerProNavigation({super.key}); @override State<PowerProNavigation> createState() => _PowerProNavigationState(); }
class _PowerProNavigationState extends State<PowerProNavigation> {
  int _currentIndex = 1;
  final List<Widget> _screens = [const IndoorPro(), const OutdoorPro(), const DatabaseProView()];
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

// ================= OUTDOOR (CALLE + EXPORTAR SESIÓN) =================
class OutdoorPro extends StatefulWidget { const OutdoorPro({super.key}); @override State<OutdoorPro> createState() => _OutdoorProState(); }
class _OutdoorProState extends State<OutdoorPro> {
  static const platform = MethodChannel('com.signalmapper/power_pro');
  LatLng? currentPos; Map<String, dynamic> currentAudit = {};
  String currentStreet = "Localizando...";
  final List<CircleMarker> _points = []; 
  final List<LatLng> _routeLine = [];
  String currentSessionId = "";
  bool isTracking = false; Timer? timer; final MapController _mapController = MapController();

  void _toggleTracking() { 
    setState(() { 
      isTracking = !isTracking; 
      if (isTracking) {
        currentSessionId = "Ruta_${DateTime.now().millisecondsSinceEpoch}";
        _routeLine.clear(); _points.clear();
        timer = Timer.periodic(const Duration(seconds: 4), (t) => _recordData()); 
      } else { timer?.cancel(); }
    }); 
  }

  Future<void> _recordData() async {
    try {
      final Map<dynamic, dynamic> nativeAudit = await platform.invokeMethod('getCellularAudit');
      final Map<String, dynamic> audit = Map<String, dynamic>.from(nativeAudit);
      Position p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      LatLng pos = LatLng(p.latitude, p.longitude);
      String street = "Calle desconocida";
      try {
        List<Placemark> pm = await placemarkFromCoordinates(p.latitude, p.longitude);
        if (pm.isNotEmpty) street = "${pm.first.thoroughfare}, ${pm.first.subLocality}";
      } catch (e) {}

      await DatabasePro.insertAudit({
        'session_id': currentSessionId, 'type': 'outdoor', 'dbm': audit['dbm'], 'tech': audit['tech'], 'address': street,
        'extra_data': "Op: ${audit['operator']} | CID: ${audit['cell_id']}", 'lat': p.latitude, 'lng': p.longitude, 'timestamp': DateTime.now().toIso8601String()
      });

      if (mounted) {
        setState(() {
          currentPos = pos; currentAudit = audit; currentStreet = street;
          _routeLine.add(pos);
          _points.add(CircleMarker(point: pos, color: getGodColor(audit['dbm'] ?? -120), radius: 10, borderColor: Colors.black, borderStrokeWidth: 1));
        });
        _mapController.move(pos, 17.5);
      }
    } catch (e) {}
  }

  void _exportCurrentRoute() async {
    String path = await DatabasePro.exportSessionCSV(currentSessionId, "Outdoor");
    await Share.shareXFiles([XFile(path)], text: "Ruta Outdoor finalizada en $currentStreet 📡");
    setState(() { _routeLine.clear(); _points.clear(); currentSessionId = ""; });
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Mapeo Outdoor Pro"), backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController, options: MapOptions(initialCenter: LatLng(43.297, -2.985), initialZoom: 17),
            children: [
              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.app_nativa'),
              PolylineLayer(polylines: [Polyline(points: _routeLine, color: Colors.blueAccent.withOpacity(0.6), strokeWidth: 4.0)]),
              CircleLayer(circles: _points),
            ],
          ),
          if (currentAudit.isNotEmpty) Positioned(top: 10, left: 10, right: 10, child: Card(color: Colors.black87, child: Padding(padding: const EdgeInsets.all(12), child: Text("$currentStreet\n${currentAudit['dbm']} dBm | ${currentAudit['tech']}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), textAlign: TextAlign.center)))),
          Positioned(bottom: 20, left: 20, right: 20, child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (!isTracking && _routeLine.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: ElevatedButton.icon(onPressed: _exportCurrentRoute, icon: const Icon(Icons.share), label: const Text("EXPORTAR ESTA RUTA"), style: ElevatedButton.styleFrom(backgroundColor: Colors.amberAccent, foregroundColor: Colors.black, minimumSize: const Size(double.infinity, 50)))),
            ElevatedButton(onPressed: _toggleTracking, style: ElevatedButton.styleFrom(backgroundColor: isTracking ? Colors.redAccent : Colors.cyanAccent, minimumSize: const Size(double.infinity, 60)), child: Text(isTracking ? "DETENER RASTREO" : "INICIAR NUEVA RUTA", style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold))),
          ])),
        ],
      ),
    );
  }
}

// ================= INDOOR (CON BOTÓN DE EXPORTAR) =================
class IndoorPro extends StatefulWidget { const IndoorPro({super.key}); @override State<IndoorPro> createState() => _IndoorProState(); }
class _IndoorProState extends State<IndoorPro> {
  static const platform = MethodChannel('com.signalmapper/power_pro');
  File? floorPlan; List<Map<String, dynamic>> indoorPoints = [];
  Map<String, dynamic> lastAudit = {}; String sessionId = "Casa_${DateTime.now().millisecondsSinceEpoch}";

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (pickedFile != null) setState(() => floorPlan = File(pickedFile.path));
  }

  void _addPoint(TapDownDetails details, BuildContext context) async {
    if (floorPlan == null) return;
    final Map<dynamic, dynamic> nativeAudit = await platform.invokeMethod('getWifiAudit');
    final Map<String, dynamic> audit = Map<String, dynamic>.from(nativeAudit);
    final RenderBox box = context.findRenderObject() as RenderBox;
    final Offset local = box.globalToLocal(details.globalPosition);

    await DatabasePro.insertAudit({
      'session_id': sessionId, 'type': 'indoor', 'dbm': audit['dbm'], 'tech': audit['ssid'], 'x': local.dx, 'y': local.dy, 'timestamp': DateTime.now().toIso8601String()
    });
    setState(() { lastAudit = audit; indoorPoints.add({'x': local.dx, 'y': local.dy, 'dbm': audit['dbm']}); });
  }

  void _exportIndoor() async {
    String path = await DatabasePro.exportSessionCSV(sessionId, "Indoor");
    await Share.shareXFiles([XFile(path)], text: "Prueba Indoor finalizada 📡");
    setState(() { indoorPoints.clear(); sessionId = "Casa_${DateTime.now().millisecondsSinceEpoch}"; });
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Mapeo Indoor"), backgroundColor: Colors.black, actions: [IconButton(icon: const Icon(Icons.add_photo_alternate), onPressed: _pickImage)]),
      body: floorPlan == null ? const Center(child: Text("Carga un plano")) : Stack(children: [
        InteractiveViewer(child: GestureDetector(onTapDown: (details) => _addPoint(details, context), child: Stack(children: [
          Image.file(floorPlan!, fit: BoxFit.contain, width: double.infinity, height: double.infinity),
          ...indoorPoints.map((p) => Positioned(left: p['x'] - 10, top: p['y'] - 10, child: Container(width: 20, height: 20, decoration: BoxDecoration(color: getGodColor(p['dbm']), shape: BoxShape.circle))))
        ]))),
        if (indoorPoints.isNotEmpty) Positioned(bottom: 20, left: 20, right: 20, child: ElevatedButton.icon(onPressed: _exportIndoor, icon: const Icon(Icons.save), label: const Text("FINALIZAR Y EXPORTAR"), style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, foregroundColor: Colors.black, minimumSize: const Size(double.infinity, 50))))
      ]),
    );
  }
}

// ================= HISTORIAL =================
class DatabaseProView extends StatelessWidget {
  const DatabaseProView({super.key});
  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Historial Completo"), backgroundColor: Colors.black),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: DatabasePro.getAudits(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          return ListView.builder(itemCount: snapshot.data!.length, itemBuilder: (context, index) {
            final a = snapshot.data![index];
            return ListTile(title: Text("${a['dbm']} dBm | ${a['type']}"), subtitle: Text(a['timestamp']));
          });
        },
      ),
    );
  }
}
DART

echo "🚀 2/2 Compilando V15.0..."
flutter build apk --profile

if [ -f "build/app/outputs/flutter-apk/app-profile.apk" ]; then
    cd /workspaces/SignalMapper/app_nativa
    gh release create v15.0-full build/app/outputs/flutter-apk/app-profile.apk --repo txurtxil/SignalMapper --title "🔥 SignalMapper V15.0 FULL AUDIT" --notes "Exportación individual de rutas Outdoor e Indoor. Mapa en modo día. Sesiones independientes."
    echo "===================================================="
    echo "✅ ¡LISTO! Todo integrado y subido a GitHub."
    echo "===================================================="
else
    echo "❌ Fallo en el build."
fi
