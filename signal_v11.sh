#!/bin/bash
cd /workspaces/SignalMapper/app_nativa

echo "🌍 1/3 Instalando Traductor de Calles (Geocoding)..."
flutter pub add geocoding
flutter pub get

echo "🧠 2/3 Manteniendo el Motor Nativo (Kotlin) estable..."
cat << 'KOTLIN' > android/app/src/main/kotlin/com/example/app_nativa/MainActivity.kt
package com.example.app_nativa
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Context
import android.telephony.*
import android.net.wifi.WifiManager
import android.os.Build

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.signalmapper/power_pro"
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCellularAudit" -> result.success(getCellularAudit())
                "getWifiAudit" -> result.success(getWifiAudit())
                else -> result.notImplemented()
            }
        }
    }
    private fun getCellularAudit(): Map<String, Any> {
        val tm = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        val audit = mutableMapOf<String, Any>()
        audit["operator"] = tm.networkOperatorName ?: "Desconocido"
        audit["is_roaming"] = tm.isNetworkRoaming
        audit["dbm"] = -120
        audit["tech"] = "Buscando..."
        audit["cell_id"] = -1; audit["pci"] = -1; audit["tac"] = -1; audit["rsrq"] = 0; audit["snr"] = 0

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val cellInfoList = tm.allCellInfo
                if (!cellInfoList.isNullOrEmpty()) {
                    val info = cellInfoList[0]
                    if (info is CellInfoLte) {
                        audit["tech"] = "4G (LTE)"
                        audit["cell_id"] = info.cellIdentity.ci; audit["pci"] = info.cellIdentity.pci; audit["tac"] = info.cellIdentity.tac
                        audit["dbm"] = info.cellSignalStrength.dbm; audit["rsrq"] = info.cellSignalStrength.rsrq; audit["snr"] = info.cellSignalStrength.rssnr
                    } else if (info is CellInfoNr) {
                        audit["tech"] = "5G (NR)"
                        val idNr = info.cellIdentity as? CellIdentityNr
                        val strNr = info.cellSignalStrength as? CellSignalStrengthNr
                        audit["pci"] = idNr?.pci ?: -1; audit["tac"] = idNr?.tac ?: -1
                        audit["dbm"] = strNr?.dbm ?: -120; audit["rsrq"] = strNr?.csiRsrq ?: 0; audit["snr"] = strNr?.csiSinr ?: 0
                    }
                }
            } catch (e: Exception) { audit["tech"] = "Sensor Bloqueado" }
        }
        return audit
    }
    private fun getWifiAudit(): Map<String, Any> {
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val info = wifiManager.connectionInfo
        val audit = mutableMapOf<String, Any>()
        audit["dbm"] = info.rssi
        val ssid = info.ssid.replace("\"", "")
        audit["ssid"] = if (ssid == "<unknown ssid>") "¡Enciende el GPS para ver el nombre!" else ssid
        audit["bssid"] = info.bssid ?: "Unknown"
        audit["link_speed"] = info.linkSpeed
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            val freq = info.frequency
            audit["freq_mhz"] = freq
            audit["band"] = if (freq in 2400..2500) "2.4 GHz (Lejos)" else if (freq in 5000..6000) "5 GHz (Rápido)" else "Desconocido"
        }
        return audit
    }
}
KOTLIN

echo "📱 3/3 Reconstruyendo HUD para Humanos (Dart)..."
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
import 'package:path/path.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabasePro.init();
  runApp(const MaterialApp(home: PowerProNavigation(), debugShowCheckedModeBanner: false, themeMode: ThemeMode.dark));
}

// BBDD
class DatabasePro {
  static late Database db;
  static Future<void> init() async {
    db = await openDatabase(join(await getDatabasesPath(), 'signal_v11.db'),
      onCreate: (db, version) {
        return db.execute('CREATE TABLE audits(id INTEGER PRIMARY KEY, type TEXT, dbm INTEGER, tech TEXT, extra_data TEXT, lat REAL, lng REAL, address TEXT, timestamp TEXT)');
      }, version: 1);
  }
  static Future<void> insertAudit(Map<String, dynamic> audit) async { await db.insert('audits', audit, conflictAlgorithm: ConflictAlgorithm.replace); }
  static Future<List<Map<String, dynamic>>> getAudits() async { return await db.query('audits', orderBy: 'timestamp DESC'); }
}

// HUMAN TRANSLATOR
String interpretSignal(int dbm) {
  if (dbm >= -75) return "✅ Excelente (Streaming 4K, Juegos Online)";
  if (dbm >= -90) return "🟡 Buena (YouTube, Redes Sociales, Spotify)";
  if (dbm >= -105) return "🟠 Regular (Solo WhatsApp o Textos)";
  return "🔴 Crítica (Cortes en llamadas, sin internet)";
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
        backgroundColor: const Color(0xFF121212), selectedItemColor: Colors.cyanAccent, unselectedItemColor: Colors.white30,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Casa (WiFi)"),
          BottomNavigationBarItem(icon: Icon(Icons.satellite_alt), label: "Calle (4G/5G)"),
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: "Historial"),
        ],
      ),
    );
  }
}

// ================= OUTDOOR (CALLE) =================
class OutdoorPro extends StatefulWidget { const OutdoorPro({super.key}); @override State<OutdoorPro> createState() => _OutdoorProState(); }
class _OutdoorProState extends State<OutdoorPro> {
  static const platform = MethodChannel('com.signalmapper/power_pro');
  LatLng? currentPos; Map<String, dynamic> currentAudit = {};
  String currentStreet = "Buscando calle...";
  int bestDbm = -200; String bestSpot = "Aún no encontrado";
  final List<CircleMarker> _points = []; bool isTracking = false; Timer? timer; final MapController _mapController = MapController();

  @override void initState() { super.initState(); [Permission.location, Permission.phone].request(); }
  void _toggleTracking() { setState(() { isTracking = !isTracking; if (isTracking) timer = Timer.periodic(const Duration(seconds: 4), (t) => _recordData()); else timer?.cancel(); }); }

  Future<void> _recordData() async {
    try {
      final Map<dynamic, dynamic> nativeAudit = await platform.invokeMethod('getCellularAudit');
      final Map<String, dynamic> audit = Map<String, dynamic>.from(nativeAudit);
      int dbm = audit['dbm'] ?? -120;
      Position p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      LatLng pos = LatLng(p.latitude, p.longitude);
      
      // Obtener nombre de la calle
      String streetName = "Calle desconocida";
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(p.latitude, p.longitude);
        if (placemarks.isNotEmpty) streetName = "\${placemarks.first.thoroughfare}, \${placemarks.first.subLocality}";
      } catch (e) {}

      // Punto de Oro
      if (dbm > bestDbm && dbm < 0) { bestDbm = dbm; bestSpot = streetName; }

      await DatabasePro.insertAudit({
        'type': 'outdoor', 'dbm': dbm, 'tech': audit['tech'], 'address': streetName,
        'extra_data': "Op: \${audit['operator']} | Calidad: \${interpretSignal(dbm)}",
        'lat': p.latitude, 'lng': p.longitude, 'timestamp': DateTime.now().toIso8601String()
      });

      if (mounted) {
        setState(() {
          currentPos = pos; currentAudit = audit; currentStreet = streetName;
          _points.add(CircleMarker(point: pos, color: getGodColor(dbm).withOpacity(0.6), radius: 14));
        });
        _mapController.move(pos, 17.5);
      }
    } catch (e) {}
  }

  @override Widget build(BuildContext context) {
    int dbm = currentAudit['dbm'] ?? 0;
    return Scaffold(
      appBar: AppBar(title: Text("Mapeo 4G/5G", style: const TextStyle(fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF121212), foregroundColor: Colors.cyanAccent),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController, options: MapOptions(initialCenter: LatLng(43.297, -2.985), initialZoom: 17),
            children: [
              TileLayer(urlTemplate: 'https://cartodb-basemaps-{s}.global.ssl.fastly.net/dark_all/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.app_nativa'),
              CircleLayer(circles: _points),
              if (currentPos != null) MarkerLayer(markers: [Marker(point: currentPos!, child: const Icon(Icons.my_location, color: Colors.cyanAccent, size: 25))]),
            ],
          ),
          Positioned(top: 10, left: 10, right: 10, child: Card(color: Colors.black87, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: getGodColor(dbm), width: 2)),
            child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
              Text(currentStreet, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const SizedBox(height: 5),
              Text("\$dbm dBm | \${currentAudit['tech'] ?? '-'}", style: TextStyle(color: getGodColor(dbm), fontSize: 24, fontWeight: FontWeight.bold)),
              Text(interpretSignal(dbm), style: const TextStyle(color: Colors.white70, fontSize: 14), textAlign: TextAlign.center),
              const Divider(color: Colors.white24),
              Text("🏆 Mejor punto: \$bestSpot (\$bestDbm dBm)", style: const TextStyle(color: Colors.amberAccent, fontSize: 13, fontWeight: FontWeight.bold)),
            ]))
          )),
          Positioned(bottom: 20, left: 20, right: 20, child: ElevatedButton(
            onPressed: _toggleTracking,
            style: ElevatedButton.styleFrom(backgroundColor: isTracking ? Colors.redAccent : Colors.cyanAccent, padding: const EdgeInsets.all(18)),
            child: Text(isTracking ? "PAUSAR MAPEO" : "INICIAR RUTA", style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
          )),
        ],
      ),
    );
  }
}

// ================= INDOOR (CASA) =================
class IndoorPro extends StatefulWidget { const IndoorPro({super.key}); @override State<IndoorPro> createState() => _IndoorProState(); }
class _IndoorProState extends State<IndoorPro> {
  static const platform = MethodChannel('com.signalmapper/power_pro');
  File? floorPlan; List<Map<String, dynamic>> indoorPoints = [];
  Map<String, dynamic> lastAudit = {}; int bestDbm = -200;

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

      await DatabasePro.insertAudit({
        'type': 'indoor', 'dbm': dbm, 'tech': audit['ssid'], 'address': "Plano Casa",
        'extra_data': "Velocidad: \${audit['link_speed']} Mbps | \${interpretSignal(dbm)}",
        'x': local.dx, 'y': local.dy, 'timestamp': DateTime.now().toIso8601String()
      });

      setState(() { lastAudit = audit; indoorPoints.add({'x': local.dx, 'y': local.dy, 'dbm': dbm}); });
    } catch (e) {}
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Mapeo WiFi Casa", style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF121212), foregroundColor: Colors.cyanAccent, actions: [IconButton(icon: const Icon(Icons.add_photo_alternate), onPressed: _pickImage)]),
      backgroundColor: const Color(0xFF1E1E1E),
      body: floorPlan == null ? const Center(child: Text("Sube el plano de tu casa para empezar\n\n⚠️ RECUERDA: Activa el GPS del móvil\npara poder ver el nombre de tu WiFi.", style: TextStyle(color: Colors.white70, fontSize: 16), textAlign: TextAlign.center)) : Stack(
        children: [
          InteractiveViewer(maxScale: 6.0, child: GestureDetector(onTapDown: (details) => _addPoint(details, context), child: Stack(children: [
            Image.file(floorPlan!, fit: BoxFit.contain, width: double.infinity, height: double.infinity),
            ...indoorPoints.map((p) => Positioned(left: p['x'] - 12, top: p['y'] - 12, child: Container(width: 24, height: 24, decoration: BoxDecoration(color: getGodColor(p['dbm']).withOpacity(0.9), shape: BoxShape.circle, border: Border.all(color: Colors.black, width: 2)))))
          ]))),
          if (lastAudit.isNotEmpty) Positioned(top: 10, left: 10, right: 10, child: Card(color: Colors.black87, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: getGodColor(lastAudit['dbm'] ?? -120), width: 2)),
            child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
              Text("Red: \${lastAudit['ssid']} (\${lastAudit['band']})", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              Text("\${lastAudit['dbm']} dBm", style: TextStyle(color: getGodColor(lastAudit['dbm'] ?? -120), fontSize: 24, fontWeight: FontWeight.bold)),
              Text(interpretSignal(lastAudit['dbm'] ?? -120), style: const TextStyle(color: Colors.white70, fontSize: 14), textAlign: TextAlign.center),
              const Divider(color: Colors.white24),
              Text("🏆 Tu mejor rincón tiene: \$bestDbm dBm", style: const TextStyle(color: Colors.amberAccent, fontSize: 13, fontWeight: FontWeight.bold)),
            ]))
          ))
        ],
      ),
    );
  }
}

// ================= HISTORIAL =================
class DatabaseProView extends StatelessWidget {
  const DatabaseProView({super.key});
  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Registros Guardados"), backgroundColor: const Color(0xFF121212), foregroundColor: Colors.cyanAccent),
      backgroundColor: const Color(0xFF1E1E1E),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: DatabasePro.getAudits(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final audits = snapshot.data!;
          return ListView.builder(itemCount: audits.length, itemBuilder: (context, index) {
            final a = audits[index];
            return Card(color: const Color(0xFF2C2C2C), margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: ListTile(
                leading: CircleAvatar(backgroundColor: getGodColor(a['dbm']), child: Icon(a['type'] == 'indoor' ? Icons.wifi : Icons.cell_tower, color: Colors.black)),
                title: Text("\${a['dbm']} dBm | \${a['address']}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text("\${a['tech']}\n\${a['extra_data']}", style: const TextStyle(color: Colors.white70)),
                trailing: Text(a['timestamp'].toString().substring(5, 16).replaceAll("T", " "), style: const TextStyle(color: Colors.white38)),
                isThreeLine: true,
              )
            );
          });
        },
      ),
    );
  }
}
DART

echo "🚀 4/4 Compilando V11 (Low RAM Mode)..."
flutter build apk --profile

if [ -f "build/app/outputs/flutter-apk/app-profile.apk" ]; then
    gh release create v11.0-friendly build/app/outputs/flutter-apk/app-profile.apk --repo txurtxil/SignalMapper --title "🔥 SignalMapper V11 FUSION" --notes "Fusión de Datos Profesionales con Interfaz para Humanos. Traductor de calles. Mejor Punto. Arreglo SSID."
    echo "===================================================="
    echo "✅ ¡HECHO! La App Total."
    echo "Descarga: https://github.com/txurtxil/SignalMapper/releases/latest"
    echo "===================================================="
else
    echo "❌ Revisa errores de compilación."
fi
