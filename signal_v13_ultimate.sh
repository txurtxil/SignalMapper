#!/bin/bash
cd /workspaces/SignalMapper/app_nativa

echo "📦 1/3 Instalando Motor de Exportación y Rutas..."
flutter pub add share_plus path_provider
flutter pub get

echo "🧠 2/3 Reconstruyendo el Cerebro Dart (V13 Ultimate)..."
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

// ================= BBDD V13 (CON RUTAS, X, Y) =================
class DatabasePro {
  static late Database db;
  static Future<void> init() async {
    db = await openDatabase(p.join(await getDatabasesPath(), 'signal_v13.db'),
      onCreate: (db, version) {
        // Añadimos session_id, x, e y para que el Indoor no falle NUNCA MÁS
        return db.execute('CREATE TABLE audits(id INTEGER PRIMARY KEY, session_id TEXT, type TEXT, dbm INTEGER, tech TEXT, extra_data TEXT, lat REAL, lng REAL, x REAL, y REAL, address TEXT, timestamp TEXT)');
      }, version: 1);
  }
  static Future<void> insertAudit(Map<String, dynamic> audit) async { await db.insert('audits', audit, conflictAlgorithm: ConflictAlgorithm.replace); }
  static Future<List<Map<String, dynamic>>> getAudits() async { return await db.query('audits', orderBy: 'timestamp DESC'); }
  
  // EXPORTAR A CSV
  static Future<String> exportCSV() async {
    final data = await getAudits();
    String csv = "ID,Session_ID,Tipo,DBM,Tecnologia,Extra,Lat,Lng,X,Y,Direccion,Fecha_Hora\n";
    for(var row in data) {
      csv += "${row['id']},${row['session_id']},${row['type']},${row['dbm']},${row['tech']},\"${row['extra_data']}\",${row['lat'] ?? ''},${row['lng'] ?? ''},${row['x'] ?? ''},${row['y'] ?? ''},\"${row['address']}\",${row['timestamp']}\n";
    }
    final directory = await getApplicationDocumentsDirectory();
    final path = p.join(directory.path, "SignalMapper_Export_${DateTime.now().millisecondsSinceEpoch}.csv");
    File file = File(path);
    await file.writeAsString(csv);
    return path;
  }
}

// Lógica de colores y texto humano
String interpretSignal(int dbm) {
  if (dbm >= -75) return "✅ Excelente (Streaming 4K)";
  if (dbm >= -90) return "🟡 Buena (YouTube / Redes)";
  if (dbm >= -105) return "🟠 Regular (Solo Textos)";
  return "🔴 Crítica (Posibles Cortes)";
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
        backgroundColor: const Color(0xFF0F0F0F), selectedItemColor: Colors.cyanAccent, unselectedItemColor: Colors.white30,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Indoor"),
          BottomNavigationBarItem(icon: Icon(Icons.satellite_alt), label: "Rutas Outdoor"),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: "Exportar"),
        ],
      ),
    );
  }
}

// ================= OUTDOOR (RUTAS CON LÍNEAS) =================
class OutdoorPro extends StatefulWidget { const OutdoorPro({super.key}); @override State<OutdoorPro> createState() => _OutdoorProState(); }
class _OutdoorProState extends State<OutdoorPro> {
  static const platform = MethodChannel('com.signalmapper/power_pro');
  LatLng? currentPos; Map<String, dynamic> currentAudit = {};
  String currentStreet = "Buscando satélites...";
  int bestDbm = -200; String bestSpot = "Aún no encontrado";
  
  final List<CircleMarker> _points = []; 
  final List<LatLng> _routeLine = []; // NUEVO: Para dibujar la ruta continua
  String currentSessionId = "";
  
  bool isTracking = false; Timer? timer; final MapController _mapController = MapController();

  @override void initState() { super.initState(); [Permission.location, Permission.phone].request(); }
  
  void _toggleTracking() { 
    setState(() { 
      isTracking = !isTracking; 
      if (isTracking) {
        currentSessionId = "Ruta_${DateTime.now().millisecondsSinceEpoch}"; // ID único para este paseo
        _routeLine.clear();
        _points.clear();
        timer = Timer.periodic(const Duration(seconds: 4), (t) => _recordData()); 
      } else {
        timer?.cancel(); 
      }
    }); 
  }

  Future<void> _recordData() async {
    try {
      final Map<dynamic, dynamic> nativeAudit = await platform.invokeMethod('getCellularAudit');
      final Map<String, dynamic> audit = Map<String, dynamic>.from(nativeAudit);
      int dbm = audit['dbm'] ?? -120;
      Position p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      LatLng pos = LatLng(p.latitude, p.longitude);
      
      String streetName = "Calle desconocida";
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(p.latitude, p.longitude);
        if (placemarks.isNotEmpty) streetName = "${placemarks.first.thoroughfare}, ${placemarks.first.subLocality}";
      } catch (e) {}

      if (dbm > bestDbm && dbm < 0) { bestDbm = dbm; bestSpot = streetName; }

      await DatabasePro.insertAudit({
        'session_id': currentSessionId,
        'type': 'outdoor', 'dbm': dbm, 'tech': audit['tech'], 'address': streetName,
        'extra_data': "Op: ${audit['operator']} | CID: ${audit['cell_id']} | SNR: ${audit['snr']}",
        'lat': p.latitude, 'lng': p.longitude, 'timestamp': DateTime.now().toIso8601String()
      });

      if (mounted) {
        setState(() {
          currentPos = pos; currentAudit = audit; currentStreet = streetName;
          _routeLine.add(pos); // Añadimos a la línea de ruta
          _points.add(CircleMarker(point: pos, color: getGodColor(dbm).withOpacity(0.8), radius: 10, borderColor: Colors.black, borderStrokeWidth: 2));
        });
        _mapController.move(pos, 18.0);
      }
    } catch (e) {}
  }

  @override Widget build(BuildContext context) {
    int dbm = currentAudit['dbm'] ?? 0;
    return Scaffold(
      appBar: AppBar(title: Text(isTracking ? "GRABANDO RUTA..." : "Rutas 4G/5G", style: const TextStyle(fontWeight: FontWeight.bold)), backgroundColor: isTracking ? Colors.red[900] : const Color(0xFF121212), foregroundColor: Colors.white),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController, options: MapOptions(initialCenter: LatLng(43.297, -2.985), initialZoom: 17),
            children: [
              TileLayer(urlTemplate: 'https://cartodb-basemaps-{s}.global.ssl.fastly.net/dark_all/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.app_nativa'),
              PolylineLayer(polylines: [Polyline(points: _routeLine, color: Colors.cyanAccent.withOpacity(0.5), strokeWidth: 4.0)]), // LA LÍNEA DEL TRACKER
              CircleLayer(circles: _points),
              if (currentPos != null) MarkerLayer(markers: [Marker(point: currentPos!, child: const Icon(Icons.my_location, color: Colors.cyanAccent, size: 25))]),
            ],
          ),
          Positioned(top: 10, left: 10, right: 10, child: Card(color: Colors.black87, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: getGodColor(dbm), width: 2)),
            child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
              Text(currentStreet, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const SizedBox(height: 5),
              Text("$dbm dBm | ${currentAudit['tech'] ?? '-'}", style: TextStyle(color: getGodColor(dbm), fontSize: 26, fontWeight: FontWeight.bold)),
              Text(interpretSignal(dbm), style: const TextStyle(color: Colors.white70, fontSize: 14), textAlign: TextAlign.center),
            ]))
          )),
          Positioned(bottom: 20, left: 20, right: 20, child: ElevatedButton(
            onPressed: _toggleTracking,
            style: ElevatedButton.styleFrom(backgroundColor: isTracking ? Colors.white : Colors.cyanAccent, padding: const EdgeInsets.all(18)),
            child: Text(isTracking ? "GUARDAR RUTA Y PARAR" : "NUEVA RUTA DE MAPEO", style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
          )),
        ],
      ),
    );
  }
}

// ================= INDOOR (FIXED X, Y BUGS) =================
class IndoorPro extends StatefulWidget { const IndoorPro({super.key}); @override State<IndoorPro> createState() => _IndoorProState(); }
class _IndoorProState extends State<IndoorPro> {
  static const platform = MethodChannel('com.signalmapper/power_pro');
  File? floorPlan; List<Map<String, dynamic>> indoorPoints = [];
  Map<String, dynamic> lastAudit = {}; int bestDbm = -200;
  String sessionId = "Casa_${DateTime.now().millisecondsSinceEpoch}";

  @override void initState() { super.initState(); [Permission.location].request(); }

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (pickedFile != null) setState(() => floorPlan = File(pickedFile.path));
  }

  void _addPoint(TapDownDetails details, BuildContext context) async {
    if (floorPlan == null) return;
    try {
      final Map<dynamic, dynamic> nativeAudit = await platform.invokeMethod('getWifiAudit');
      final Map<String, dynamic> audit = Map<String, dynamic>.from(nativeAudit);
      int dbm = audit['dbm'] ?? -127;
      if (dbm > bestDbm && dbm < 0) bestDbm = dbm;

      final RenderBox box = context.findRenderObject() as RenderBox;
      final Offset local = box.globalToLocal(details.globalPosition);

      // AHORA SÍ GUARDARÁ PORQUE LAS COLUMNAS X,Y EXISTEN EN V13
      await DatabasePro.insertAudit({
        'session_id': sessionId,
        'type': 'indoor', 'dbm': dbm, 'tech': audit['ssid'], 'address': "Plano Local",
        'extra_data': "Vel: ${audit['link_speed']} Mbps | MAC: ${audit['bssid']}",
        'x': local.dx, 'y': local.dy, 'timestamp': DateTime.now().toIso8601String()
      });

      setState(() { lastAudit = audit; indoorPoints.add({'x': local.dx, 'y': local.dy, 'dbm': dbm}); });
      
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Punto guardado: $dbm dBm"), backgroundColor: Colors.green, duration: Duration(milliseconds: 500)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al guardar: $e")));
    }
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Mapeo WiFi Local", style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF121212), foregroundColor: Colors.cyanAccent, actions: [IconButton(icon: const Icon(Icons.add_photo_alternate), onPressed: _pickImage)]),
      backgroundColor: const Color(0xFF1E1E1E),
      body: floorPlan == null ? const Center(child: Text("Sube el plano de tu casa/local", style: TextStyle(color: Colors.white70, fontSize: 16))) : Stack(
        children: [
          InteractiveViewer(maxScale: 6.0, child: GestureDetector(onTapDown: (details) => _addPoint(details, context), child: Stack(children: [
            Image.file(floorPlan!, fit: BoxFit.contain, width: double.infinity, height: double.infinity),
            ...indoorPoints.map((p) => Positioned(left: p['x'] - 12, top: p['y'] - 12, child: Container(width: 24, height: 24, decoration: BoxDecoration(color: getGodColor(p['dbm']).withOpacity(0.9), shape: BoxShape.circle, border: Border.all(color: Colors.black, width: 2)))))
          ]))),
          if (lastAudit.isNotEmpty) Positioned(top: 10, left: 10, right: 10, child: Card(color: Colors.black87, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
              Text("Red: ${lastAudit['ssid']}", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              Text("${lastAudit['dbm']} dBm", style: TextStyle(color: getGodColor(lastAudit['dbm'] ?? -120), fontSize: 26, fontWeight: FontWeight.bold)),
            ]))
          ))
        ],
      ),
    );
  }
}

// ================= HISTORIAL Y EXPORTACIÓN =================
class DatabaseProView extends StatelessWidget {
  const DatabaseProView({super.key});
  
  void _exportData(BuildContext context) async {
    try {
      String filePath = await DatabasePro.exportCSV();
      await Share.shareXFiles([XFile(filePath)], text: "Aquí tienes mi auditoría de red de SignalMapper 📡");
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error al exportar.")));
    }
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Base de Datos"), backgroundColor: const Color(0xFF121212), foregroundColor: Colors.cyanAccent),
      backgroundColor: const Color(0xFF1E1E1E),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: DatabasePro.getAudits(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final audits = snapshot.data!;
          if (audits.isEmpty) return const Center(child: Text("No hay datos.", style: TextStyle(color: Colors.white)));
          
          return ListView.builder(itemCount: audits.length, itemBuilder: (context, index) {
            final a = audits[index];
            return Card(color: const Color(0xFF2C2C2C), margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: ListTile(
                leading: CircleAvatar(backgroundColor: getGodColor(a['dbm']), child: Icon(a['type'] == 'indoor' ? Icons.wifi : Icons.cell_tower, color: Colors.black)),
                title: Text("${a['dbm']} dBm | ${a['type'] == 'indoor' ? 'Indoor' : a['address']}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text("ID Ruta: ${a['session_id']?.split('_')[1] ?? 'N/A'}\n${a['tech']}", style: const TextStyle(color: Colors.white70)),
                trailing: Text(a['timestamp'].toString().substring(5, 16).replaceAll("T", " "), style: const TextStyle(color: Colors.white38)),
                isThreeLine: true,
              )
            );
          });
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _exportData(context),
        icon: const Icon(Icons.share, color: Colors.black),
        label: const Text("EXPORTAR EXCEL", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.cyanAccent,
      ),
    );
  }
}
DART

echo "🚀 3/3 Compilando la Suite de Rastreo Definitiva..."
flutter build apk --profile

if [ -f "build/app/outputs/flutter-apk/app-profile.apk" ]; then
    gh release create v13.0-tracker build/app/outputs/flutter-apk/app-profile.apk --repo txurtxil/SignalMapper --title "🔥 SignalMapper V13 TRACKER SUITE" --notes "Indoor arreglado (con snacker y DB nueva). Exportación a CSV. Rutas con líneas (Polylines) en outdoor. Sistema de IDs de sesión."
    echo "===================================================="
    echo "✅ ¡HECHO! La App Definitiva está compilada."
    echo "Descarga: https://github.com/txurtxil/SignalMapper/releases/latest"
    echo "===================================================="
else
    echo "❌ Error al compilar."
fi
