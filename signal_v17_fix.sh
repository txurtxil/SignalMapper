#!/bin/bash
cd /workspaces/SignalMapper/app_nativa

echo "🧹 1/3 Limpiando caché y forzando File Picker moderno..."
flutter clean
flutter pub remove file_picker
# Forzamos una versión 6.0.0 o superior donde 'platform' sí existe
flutter pub add "file_picker:>=6.0.0"
flutter pub get

echo "🧠 2/3 Reescribiendo el código de importación blindado..."
cat << 'DART' > lib/main.dart
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart' as fp; // BLINDADO CON NAMESPACE
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabasePro.init();
  runApp(const MaterialApp(home: PowerProNavigation(), debugShowCheckedModeBanner: false, themeMode: ThemeMode.dark));
}

// ================= BASE DE DATOS PRO =================
class DatabasePro {
  static late Database db;
  static Future<void> init() async {
    db = await openDatabase(p.join(await getDatabasesPath(), 'signal_v17.db'),
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

// ================= OUTDOOR (CON IMPORTACIÓN) =================
class OutdoorPro extends StatefulWidget { const OutdoorPro({super.key}); @override State<OutdoorPro> createState() => _OutdoorProState(); }
class _OutdoorProState extends State<OutdoorPro> {
  static const platform = MethodChannel('com.signalmapper/power_pro');
  LatLng? currentPos; Map<String, dynamic> currentAudit = {};
  final List<CircleMarker> _points = []; 
  final List<LatLng> _routeLine = [];
  String sessionId = ""; bool isTracking = false; Timer? timer; final MapController _mapController = MapController();

  void _toggleTracking() { 
    setState(() { 
      isTracking = !isTracking; 
      if (isTracking) {
        sessionId = "Ruta_${DateTime.now().millisecondsSinceEpoch}";
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
      
      await DatabasePro.insertAudit({
        'session_id': sessionId, 'type': 'outdoor', 'dbm': audit['dbm'], 'tech': audit['tech'], 'lat': p.latitude, 'lng': p.longitude, 'timestamp': DateTime.now().toIso8601String()
      });
      HapticFeedback.lightImpact();
      if (mounted) setState(() {
        currentPos = pos; currentAudit = audit; _routeLine.add(pos);
        _points.add(CircleMarker(point: pos, color: getGodColor(audit['dbm'] ?? -120), radius: 10));
      });
    } catch (e) {}
  }

  // IMPORTAR CSV OUTDOOR (Blindado con fp.)
  Future<void> _importCSV() async {
    try {
      fp.FilePickerResult? result = await fp.FilePicker.platform.pickFiles(type: fp.FileType.custom, allowedExtensions: ['csv']);
      if (result != null && result.files.single.path != null) {
        File file = File(result.files.single.path!);
        List<String> lines = await file.readAsLines();
        setState(() { _routeLine.clear(); _points.clear(); });
        
        for (int i = 1; i < lines.length; i++) {
          List<String> cols = lines[i].split(',');
          if (cols.length > 8 && cols[2] == "outdoor") {
            double lat = double.parse(cols[6]);
            double lng = double.parse(cols[7]);
            int dbm = int.parse(cols[3]);
            LatLng pos = LatLng(lat, lng);
            setState(() {
              _routeLine.add(pos);
              _points.add(CircleMarker(point: pos, color: getGodColor(dbm), radius: 10));
            });
            if (i == 1) _mapController.move(pos, 17.0);
          }
        }
      }
    } catch (e) {
      debugPrint("Error al importar: \$e");
    }
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Outdoor Pro"), backgroundColor: Colors.black, actions: [IconButton(icon: const Icon(Icons.file_open), onPressed: _importCSV)]),
      body: Stack(children: [
        FlutterMap(mapController: _mapController, options: MapOptions(initialCenter: LatLng(43.297, -2.985), initialZoom: 17), children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.app_nativa'),
          PolylineLayer(polylines: [Polyline(points: _routeLine, color: Colors.blueAccent, strokeWidth: 4)]),
          CircleLayer(circles: _points),
          if (currentPos != null) MarkerLayer(markers: [Marker(point: currentPos!, child: const Icon(Icons.my_location, color: Colors.blueAccent, size: 35))]),
        ]),
        Positioned(bottom: 20, left: 20, right: 20, child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!isTracking && _points.isNotEmpty) ElevatedButton.icon(onPressed: () async {
            String p = await DatabasePro.exportSessionCSV(sessionId, "Outdoor");
            await Share.shareXFiles([XFile(p)]);
          }, icon: const Icon(Icons.share, color: Colors.black), label: const Text("EXPORTAR RUTA", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), style: ElevatedButton.styleFrom(backgroundColor: Colors.amberAccent, minimumSize: const Size(double.infinity, 50))),
          ElevatedButton(onPressed: _toggleTracking, style: ElevatedButton.styleFrom(backgroundColor: isTracking ? Colors.redAccent : Colors.cyanAccent, minimumSize: const Size(double.infinity, 60)), child: Text(isTracking ? "PARAR" : "NUEVA RUTA", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold))),
        ]))
      ]),
    );
  }
}

// ================= INDOOR (CON IMPORTACIÓN) =================
class IndoorPro extends StatefulWidget { const IndoorPro({super.key}); @override State<IndoorPro> createState() => _IndoorProState(); }
class _IndoorProState extends State<IndoorPro> {
  static const platform = MethodChannel('com.signalmapper/power_pro');
  File? floorPlan; List<Map<String, dynamic>> indoorPoints = [];
  String sessionId = "Casa_${DateTime.now().millisecondsSinceEpoch}";

  Future<void> _importIndoorCSV() async {
    try {
      fp.FilePickerResult? result = await fp.FilePicker.platform.pickFiles(type: fp.FileType.custom, allowedExtensions: ['csv']);
      if (result != null && result.files.single.path != null) {
        File file = File(result.files.single.path!);
        List<String> lines = await file.readAsLines();
        setState(() { indoorPoints.clear(); });
        for (int i = 1; i < lines.length; i++) {
          List<String> cols = lines[i].split(',');
          if (cols.length > 9 && cols[2] == "indoor") {
            setState(() {
              indoorPoints.add({'x': double.parse(cols[8]), 'y': double.parse(cols[9]), 'dbm': int.parse(cols[3])});
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Error al importar: \$e");
    }
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Indoor Pro"), backgroundColor: Colors.black, actions: [
        IconButton(icon: const Icon(Icons.file_open), onPressed: _importIndoorCSV),
        IconButton(icon: const Icon(Icons.add_photo_alternate), onPressed: () async {
          final p = await ImagePicker().pickImage(source: ImageSource.gallery);
          if (p != null) setState(() => floorPlan = File(p.path));
        })
      ]),
      backgroundColor: const Color(0xFF1E1E1E),
      body: floorPlan == null ? const Center(child: Text("Carga un plano", style: TextStyle(color: Colors.white70))) : Stack(children: [
        InteractiveViewer(child: GestureDetector(onTapDown: (details) async {
          HapticFeedback.mediumImpact();
          final Map<dynamic, dynamic> nativeAudit = await platform.invokeMethod('getWifiAudit');
          final RenderBox box = context.findRenderObject() as RenderBox;
          final Offset local = box.globalToLocal(details.globalPosition);
          await DatabasePro.insertAudit({
            'session_id': sessionId, 'type': 'indoor', 'dbm': nativeAudit['dbm'], 'x': local.dx, 'y': local.dy, 'timestamp': DateTime.now().toIso8601String()
          });
          setState(() { indoorPoints.add({'x': local.dx, 'y': local.dy, 'dbm': nativeAudit['dbm']}); });
        }, child: Stack(children: [
          Image.file(floorPlan!, fit: BoxFit.contain, width: double.infinity, height: double.infinity),
          ...indoorPoints.map((p) => Positioned(left: p['x'] - 12, top: p['y'] - 12, child: Container(width: 24, height: 24, decoration: BoxDecoration(color: getGodColor(p['dbm']), shape: BoxShape.circle, border: Border.all(color: Colors.black, width: 2)))))
        ]))),
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
            return ListTile(title: Text("${a['dbm']} dBm | ${a['type']}", style: const TextStyle(color: Colors.white)), subtitle: Text(a['timestamp'], style: const TextStyle(color: Colors.white70)));
          });
        },
      ),
    );
  }
}
DART

echo "🚀 3/3 Compilando la versión con Importador reparado..."
flutter build apk --profile

if [ -f "build/app/outputs/flutter-apk/app-profile.apk" ]; then
    gh release create v17.1-import-fix build/app/outputs/flutter-apk/app-profile.apk --repo txurtxil/SignalMapper --title "🔥 SignalMapper V17.1 IMPORT FIX" --notes "Arreglado el error de FilePicker para permitir carga y pintado de mapas CSV antiguos."
    echo "===================================================="
    echo "✅ ¡COMPILADO CON ÉXITO! Descarga desde GitHub."
    echo "===================================================="
else
    echo "❌ Fallo al compilar. Revisa la terminal."
fi
