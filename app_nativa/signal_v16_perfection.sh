#!/bin/bash
cd /workspaces/SignalMapper/app_nativa

echo "⚙️ 1/3 Inyectando Permisos Críticos en el cerebro de Android..."
cat << 'XML' > android/app/src/main/AndroidManifest.xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <uses-permission android:name="android.permission.READ_PHONE_STATE" />
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.INTERNET" />

    <application
        android:label="SignalMapper"
        android:icon="@mipmap/ic_launcher"
        android:requestLegacyExternalStorage="true">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <meta-data android:name="flutterEmbedding" android:value="2" />
    </application>
</manifest>
XML

echo "📱 2/3 Compilando el Motor Visual y Haptic (Dart)..."
cat << 'DART' > lib/main.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Para HapticFeedback (Vibración)
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

// ================= BASE DE DATOS =================
class DatabasePro {
  static late Database db;
  static Future<void> init() async {
    db = await openDatabase(p.join(await getDatabasesPath(), 'signal_v16.db'),
      onCreate: (db, version) {
        return db.execute('CREATE TABLE audits(id INTEGER PRIMARY KEY, session_id TEXT, type TEXT, dbm INTEGER, tech TEXT, extra_data TEXT, lat REAL, lng REAL, x REAL, y REAL, address TEXT, timestamp TEXT)');
      }, version: 1);
  }
  static Future<void> insertAudit(Map<String, dynamic> audit) async { await db.insert('audits', audit, conflictAlgorithm: ConflictAlgorithm.replace); }
  static Future<List<Map<String, dynamic>>> getAudits() async { return await db.query('audits', orderBy: 'timestamp DESC'); }
  
  static Future<String> exportGlobalCSV() async {
    final data = await getAudits();
    return _generateCSV(data, "SignalMapper_Backup_Global");
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

// ================= LÓGICA DE COLORES Y TRADUCCIÓN =================
String interpretSignal(int dbm) {
  if (dbm >= -75) return "✅ Excelente (Streaming 4K / Juegos)";
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

  @override void initState() {
    super.initState();
    _forcePermissions();
  }

  // FORZAR PERMISOS AL ABRIR LA APP
  Future<void> _forcePermissions() async {
    await [
      Permission.locationWhenInUse,
      Permission.locationAlways,
      Permission.phone,
    ].request();
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex, onTap: (i) => setState(() => _currentIndex = i),
        backgroundColor: const Color(0xFF121212), selectedItemColor: Colors.cyanAccent, unselectedItemColor: Colors.white30,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Indoor"),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: "Outdoor"),
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: "Historial"),
        ],
      ),
    );
  }
}

// ================= OUTDOOR (MAPA DÍA + BOTÓN EXPORTAR FIJO) =================
class OutdoorPro extends StatefulWidget { const OutdoorPro({super.key}); @override State<OutdoorPro> createState() => _OutdoorProState(); }
class _OutdoorProState extends State<OutdoorPro> {
  static const platform = MethodChannel('com.signalmapper/power_pro');
  LatLng? currentPos; Map<String, dynamic> currentAudit = {};
  String currentStreet = "Esperando GPS...";
  final List<CircleMarker> _points = []; 
  final List<LatLng> _routeLine = [];
  String currentSessionId = "";
  bool isTracking = false; 
  bool hasSessionData = false; // Controla el botón de exportar
  Timer? timer; final MapController _mapController = MapController();

  void _toggleTracking() { 
    setState(() { 
      isTracking = !isTracking; 
      if (isTracking) {
        currentSessionId = "Ruta_${DateTime.now().millisecondsSinceEpoch}";
        _routeLine.clear(); _points.clear(); hasSessionData = true;
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

      // Vibración táctica al guardar
      HapticFeedback.lightImpact();

      if (mounted) {
        setState(() {
          currentPos = pos; currentAudit = audit; currentStreet = street;
          _routeLine.add(pos);
          _points.add(CircleMarker(point: pos, color: getGodColor(audit['dbm'] ?? -120), radius: 12, borderColor: Colors.black, borderStrokeWidth: 2));
        });
        _mapController.move(pos, 17.5);
      }
    } catch (e) {}
  }

  void _exportCurrentRoute() async {
    String path = await DatabasePro.exportSessionCSV(currentSessionId, "Outdoor");
    await Share.shareXFiles([XFile(path)], text: "Ruta Outdoor finalizada en $currentStreet 📡");
    setState(() { _routeLine.clear(); _points.clear(); currentSessionId = ""; hasSessionData = false; });
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Mapeo 4G/5G", style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF121212), foregroundColor: Colors.cyanAccent),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController, options: MapOptions(initialCenter: LatLng(43.297, -2.985), initialZoom: 17),
            children: [
              // MAPA DE DÍA (OpenStreetMap Clásico)
              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.app_nativa'),
              PolylineLayer(polylines: [Polyline(points: _routeLine, color: Colors.blueAccent, strokeWidth: 5.0)]),
              CircleLayer(circles: _points),
              if (currentPos != null) MarkerLayer(markers: [Marker(point: currentPos!, child: const Icon(Icons.my_location, color: Colors.blueAccent, size: 35))]),
            ],
          ),
          
          // BOTÓN DE EXPORTAR (SIEMPRE VISIBLE SI HAY DATOS)
          if (hasSessionData && !isTracking)
            Positioned(top: 20, left: 20, right: 20, child: ElevatedButton.icon(
              onPressed: _exportCurrentRoute, icon: const Icon(Icons.share, color: Colors.black),
              label: const Text("FINALIZAR Y EXPORTAR RUTA", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amberAccent, padding: const EdgeInsets.all(15), elevation: 10),
            )),

          if (currentAudit.isNotEmpty) Positioned(top: hasSessionData && !isTracking ? 90 : 20, left: 10, right: 10, child: Card(color: Colors.black87, child: Padding(padding: const EdgeInsets.all(12), child: Text("$currentStreet\n${currentAudit['dbm']} dBm | ${currentAudit['tech']}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.center)))),
          
          Positioned(bottom: 20, left: 20, right: 20, child: ElevatedButton(
            onPressed: _toggleTracking, 
            style: ElevatedButton.styleFrom(backgroundColor: isTracking ? Colors.redAccent : Colors.cyanAccent, padding: const EdgeInsets.all(20), elevation: 10), 
            child: Text(isTracking ? "⏸️ PAUSAR RASTREO" : "▶️ INICIAR RASTREO", style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold))
          )),
        ],
      ),
    );
  }
}

// ================= INDOOR (VIBRACIÓN Y BOTÓN FIJO) =================
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
    HapticFeedback.mediumImpact(); // VIBRACIÓN AL TOCAR EL PLANO

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
      appBar: AppBar(title: const Text("Mapeo WiFi Local", style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF121212), foregroundColor: Colors.cyanAccent, actions: [IconButton(icon: const Icon(Icons.add_photo_alternate), onPressed: _pickImage)]),
      backgroundColor: const Color(0xFF1E1E1E),
      body: floorPlan == null ? const Center(child: Text("Carga un plano (Arriba a la derecha)", style: TextStyle(color: Colors.white70, fontSize: 16))) : Stack(children: [
        InteractiveViewer(child: GestureDetector(onTapDown: (details) => _addPoint(details, context), child: Stack(children: [
          Image.file(floorPlan!, fit: BoxFit.contain, width: double.infinity, height: double.infinity),
          ...indoorPoints.map((p) => Positioned(left: p['x'] - 12, top: p['y'] - 12, child: Container(width: 24, height: 24, decoration: BoxDecoration(color: getGodColor(p['dbm']).withOpacity(0.9), shape: BoxShape.circle, border: Border.all(color: Colors.black, width: 2)))))
        ]))),
        
        if (lastAudit.isNotEmpty) Positioned(top: 10, left: 10, right: 10, child: Card(color: Colors.black87, child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
          Text("Red: ${lastAudit['ssid']}", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          Text("${lastAudit['dbm']} dBm", style: TextStyle(color: getGodColor(lastAudit['dbm'] ?? -120), fontSize: 26, fontWeight: FontWeight.bold)),
        ])))),

        // BOTÓN EXPORTAR FIJO ABAJO EN INDOOR
        if (indoorPoints.isNotEmpty) Positioned(bottom: 20, left: 20, right: 20, child: ElevatedButton.icon(
          onPressed: _exportIndoor, icon: const Icon(Icons.save_alt, color: Colors.black), 
          label: const Text("FINALIZAR Y EXPORTAR TEST", style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)), 
          style: ElevatedButton.styleFrom(backgroundColor: Colors.amberAccent, padding: const EdgeInsets.all(18), elevation: 10)
        ))
      ]),
    );
  }
}

// ================= HISTORIAL Y EXPORTACIÓN GLOBAL =================
class DatabaseProView extends StatelessWidget {
  const DatabaseProView({super.key});
  
  void _exportData(BuildContext context) async {
    try {
      String path = await DatabasePro.exportGlobalCSV();
      await Share.shareXFiles([XFile(path)], text: "Backup Global de SignalMapper 📡");
    } catch (e) {}
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Registros Guardados"), backgroundColor: const Color(0xFF121212), foregroundColor: Colors.cyanAccent),
      backgroundColor: const Color(0xFF1E1E1E),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: DatabasePro.getAudits(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          if (snapshot.data!.isEmpty) return const Center(child: Text("Aún no hay datos guardados.", style: TextStyle(color: Colors.white70)));
          return ListView.builder(itemCount: snapshot.data!.length, itemBuilder: (context, index) {
            final a = snapshot.data![index];
            return Card(color: const Color(0xFF2C2C2C), margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: ListTile(
                leading: CircleAvatar(backgroundColor: getGodColor(a['dbm']), child: Icon(a['type'] == 'indoor' ? Icons.wifi : Icons.cell_tower, color: Colors.black)),
                title: Text("${a['dbm']} dBm | ${a['type'] == 'indoor' ? 'Indoor' : a['address']}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text("Ruta: ${a['session_id']?.split('_').last ?? 'N/A'}\n${a['tech']}", style: const TextStyle(color: Colors.white70)),
                trailing: Text(a['timestamp'].toString().substring(5, 16).replaceAll("T", " "), style: const TextStyle(color: Colors.white38)),
                isThreeLine: true,
              )
            );
          });
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _exportData(context), icon: const Icon(Icons.share, color: Colors.black), 
        label: const Text("BACKUP TOTAL", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), backgroundColor: Colors.cyanAccent,
      ),
    );
  }
}
DART

echo "🚀 3/3 Compilando y Subiendo a GitHub..."
flutter build apk --profile

if [ -f "build/app/outputs/flutter-apk/app-profile.apk" ]; then
    gh release create v16.0-perfection build/app/outputs/flutter-apk/app-profile.apk --repo txurtxil/SignalMapper --title "🔥 SignalMapper V16 PERFECTION" --notes "Permisos de sistema forzados. Haptic Feedback. Mapa de día en Outdoor. Botones de exportación corregidos y visibles."
    echo "===================================================="
    echo "✅ ¡SISTEMA ACTUALIZADO! Vete a GitHub a descargar:"
    echo "https://github.com/txurtxil/SignalMapper/releases/latest"
    echo "===================================================="
else
    echo "❌ Fallo en compilación."
fi
