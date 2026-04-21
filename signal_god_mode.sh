#!/bin/bash
cd /workspaces/SignalMapper/app_nativa

echo "🍺 1/3 Activando GOD MODE en el motor Nativo (Kotlin)..."
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
        
        audit["operator"] = tm.networkOperatorName ?: "Unknown"
        audit["is_roaming"] = tm.isNetworkRoaming
        audit["dbm"] = -120
        audit["tech"] = "Buscando..."
        audit["cell_id"] = -1
        audit["pci"] = -1
        audit["tac"] = -1
        audit["rsrq"] = 0
        audit["snr"] = 0

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val cellInfoList = tm.allCellInfo
                if (!cellInfoList.isNullOrEmpty()) {
                    val info = cellInfoList[0]
                    if (info is CellInfoLte) {
                        audit["tech"] = "4G (LTE)"
                        audit["cell_id"] = info.cellIdentity.ci
                        audit["pci"] = info.cellIdentity.pci
                        audit["tac"] = info.cellIdentity.tac
                        audit["dbm"] = info.cellSignalStrength.dbm
                        audit["rsrq"] = info.cellSignalStrength.rsrq
                        audit["snr"] = info.cellSignalStrength.rssnr
                    } else if (info is CellInfoNr) {
                        audit["tech"] = "5G (NR)"
                        audit["pci"] = info.cellIdentity.pci
                        audit["tac"] = info.cellIdentity.tac
                        audit["dbm"] = info.cellSignalStrength.dbm
                        audit["rsrq"] = info.cellSignalStrength.csiRsrq
                        audit["snr"] = info.cellSignalStrength.csiSinr
                    }
                }
            } catch (e: Exception) {
                audit["tech"] = "Error reading sensor"
            }
        }
        return audit
    }

    private fun getWifiAudit(): Map<String, Any> {
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val info = wifiManager.connectionInfo
        val audit = mutableMapOf<String, Any>()
        
        audit["dbm"] = info.rssi
        audit["ssid"] = info.ssid.replace("\"", "")
        audit["bssid"] = info.bssid ?: "Unknown"
        audit["link_speed"] = info.linkSpeed
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            val freq = info.frequency
            audit["freq_mhz"] = freq
            audit["band"] = if (freq in 2400..2500) "2.4 GHz" else if (freq in 5000..6000) "5 GHz" else "Unknown"
        }
        return audit
    }
}
KOTLIN

echo "🛰️ 2/3 Reconstruyendo HUD de la App (Dart)..."
cat << 'DART' > lib/main.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
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

class DatabasePro {
  static late Database db;
  static Future<void> init() async {
    db = await openDatabase(
      join(await getDatabasesPath(), 'signal_god_mode.db'), // Nueva BD para evitar conflictos de esquema
      onCreate: (db, version) {
        return db.execute(
          'CREATE TABLE audits(id INTEGER PRIMARY KEY, type TEXT, dbm INTEGER, tech TEXT, cell_id INTEGER, extra_data TEXT, lat REAL, lng REAL, x REAL, y REAL, image_path TEXT, timestamp TEXT)',
        );
      },
      version: 1,
    );
  }
  static Future<void> insertAudit(Map<String, dynamic> audit) async {
    await db.insert('audits', audit, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  static Future<List<Map<String, dynamic>>> getAudits() async {
    return await db.query('audits', orderBy: 'timestamp DESC');
  }
}

class PowerProNavigation extends StatefulWidget {
  const PowerProNavigation({super.key});
  @override
  State<PowerProNavigation> createState() => _PowerProNavigationState();
}
class _PowerProNavigationState extends State<PowerProNavigation> {
  int _currentIndex = 1;
  final List<Widget> _screens = [const IndoorPro(), const OutdoorPro(), const DatabaseProView()];
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        backgroundColor: Colors.black, selectedItemColor: Colors.greenAccent, unselectedItemColor: Colors.white30,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.router), label: "WiFi HUD"),
          BottomNavigationBarItem(icon: Icon(Icons.cell_tower), label: "Cell HUD"),
          BottomNavigationBarItem(icon: Icon(Icons.data_object), label: "Logs"),
        ],
      ),
    );
  }
}

Color getGodColor(int dbm) {
  if (dbm >= -65) return Colors.greenAccent;
  if (dbm >= -85) return Colors.yellowAccent;
  if (dbm >= -105) return Colors.orangeAccent;
  return Colors.redAccent;
}

// ================= OUTDOOR GOD MODE =================
class OutdoorPro extends StatefulWidget {
  const OutdoorPro({super.key});
  @override
  State<OutdoorPro> createState() => _OutdoorProState();
}
class _OutdoorProState extends State<OutdoorPro> {
  static const platform = MethodChannel('com.signalmapper/power_pro');
  LatLng? currentPos;
  Map<String, dynamic> currentAudit = {};
  final List<CircleMarker> _points = [];
  bool isTracking = false;
  Timer? timer;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    [Permission.location, Permission.phone].request();
  }

  void _toggleTracking() {
    setState(() {
      isTracking = !isTracking;
      if (isTracking) timer = Timer.periodic(const Duration(seconds: 3), (t) => _recordData());
      else timer?.cancel();
    });
  }

  Future<void> _recordData() async {
    try {
      final Map<dynamic, dynamic> nativeAudit = await platform.invokeMethod('getCellularAudit');
      final Map<String, dynamic> audit = Map<String, dynamic>.from(nativeAudit);
      int dbm = audit['dbm'] ?? -120;
      Position p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      LatLng pos = LatLng(p.latitude, p.longitude);

      await DatabasePro.insertAudit({
        'type': 'outdoor', 'dbm': dbm, 'tech': audit['tech'], 'cell_id': audit['cell_id'],
        'extra_data': "Op: ${audit['operator']} | PCI: ${audit['pci']} | TAC: ${audit['tac']} | SNR: ${audit['snr']}",
        'lat': p.latitude, 'lng': p.longitude, 'timestamp': DateTime.now().toIso8601String()
      });

      if (mounted) {
        setState(() {
          currentPos = pos; currentAudit = audit;
          _points.add(CircleMarker(point: pos, color: getGodColor(dbm).withOpacity(0.6), radius: 12));
        });
        _mapController.move(pos, 18.0);
      }
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    String tech = currentAudit['tech'] ?? 'STANDBY';
    int dbm = currentAudit['dbm'] ?? 0;
    
    return Scaffold(
      appBar: AppBar(title: Text("Net: $tech | $dbm dBm", style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace')), backgroundColor: Colors.black, foregroundColor: getGodColor(dbm)),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController, options: MapOptions(initialCenter: LatLng(43.297, -2.985), initialZoom: 17),
            children: [
              TileLayer(urlTemplate: 'https://cartodb-basemaps-{s}.global.ssl.fastly.net/dark_all/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.app_nativa'), // MAPA OSCURO HACKER
              CircleLayer(circles: _points),
              if (currentPos != null) MarkerLayer(markers: [Marker(point: currentPos!, child: const Icon(Icons.my_location, color: Colors.greenAccent, size: 25))]),
            ],
          ),
          // HUD OVERLAY
          Positioned(
            top: 10, left: 10, right: 10,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.black87, border: Border.all(color: Colors.greenAccent), borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("OPERATOR: ${currentAudit['operator'] ?? '-'}", style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace')),
                  Text("CELL ID: ${currentAudit['cell_id'] ?? '-'} | PCI: ${currentAudit['pci'] ?? '-'}", style: const TextStyle(color: Colors.white70, fontFamily: 'monospace')),
                  Text("TAC: ${currentAudit['tac'] ?? '-'} | ROAMING: ${currentAudit['is_roaming'] ?? false}", style: const TextStyle(color: Colors.white70, fontFamily: 'monospace')),
                  Text("RSRQ: ${currentAudit['rsrq'] ?? 0} | SNR: ${currentAudit['snr'] ?? 0}", style: const TextStyle(color: Colors.white70, fontFamily: 'monospace')),
                ],
              ),
            )
          ),
          Positioned(bottom: 20, left: 20, right: 20, child: ElevatedButton(
            onPressed: _toggleTracking,
            style: ElevatedButton.styleFrom(backgroundColor: isTracking ? Colors.red : Colors.black, side: BorderSide(color: isTracking ? Colors.redAccent : Colors.greenAccent), padding: const EdgeInsets.all(18)),
            child: Text(isTracking ? "KILL PROCESS" : "START AUDIT", style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 18, fontWeight: FontWeight.bold)),
          )),
        ],
      ),
    );
  }
}

// ================= INDOOR GOD MODE =================
class IndoorPro extends StatefulWidget {
  const IndoorPro({super.key});
  @override
  State<IndoorPro> createState() => _IndoorProState();
}
class _IndoorProState extends State<IndoorPro> {
  static const platform = MethodChannel('com.signalmapper/power_pro');
  File? floorPlan;
  List<Map<String, dynamic>> indoorPoints = [];
  Map<String, dynamic> lastAudit = {};

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
      final RenderBox box = context.findRenderObject() as RenderBox;
      final Offset local = box.globalToLocal(details.globalPosition);

      await DatabasePro.insertAudit({
        'type': 'indoor', 'dbm': dbm, 'tech': audit['ssid'],
        'extra_data': "BSSID: ${audit['bssid']} | Freq: ${audit['freq_mhz']} MHz | Speed: ${audit['link_speed']} Mbps",
        'x': local.dx, 'y': local.dy, 'image_path': floorPlan!.path, 'timestamp': DateTime.now().toIso8601String()
      });

      setState(() {
        lastAudit = audit;
        indoorPoints.add({'x': local.dx, 'y': local.dy, 'dbm': dbm});
      });
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("WiFi Scanner", style: TextStyle(fontFamily: 'monospace')), backgroundColor: Colors.black, foregroundColor: Colors.greenAccent, actions: [IconButton(icon: const Icon(Icons.folder_open), onPressed: _pickImage)]),
      backgroundColor: const Color(0xFF0F0F0F),
      body: floorPlan == null ? const Center(child: Text("LOAD BLUEPRINT...", style: TextStyle(color: Colors.greenAccent, fontFamily: 'monospace'))) : Stack(
        children: [
          InteractiveViewer(
            maxScale: 6.0,
            child: GestureDetector(
              onTapDown: (details) => _addPoint(details, context),
              child: Stack(
                children: [
                  Image.file(floorPlan!, fit: BoxFit.contain, width: double.infinity, height: double.infinity),
                  ...indoorPoints.map((p) => Positioned(left: p['x'] - 10, top: p['y'] - 10, child: Container(width: 20, height: 20, decoration: BoxDecoration(color: getGodColor(p['dbm']).withOpacity(0.9), shape: BoxShape.circle, border: Border.all(color: Colors.black, width: 2)))))
                ],
              ),
            ),
          ),
          if (lastAudit.isNotEmpty) Positioned(top: 10, left: 10, right: 10, child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.black87, border: Border.all(color: Colors.greenAccent)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("SSID: ${lastAudit['ssid']} (${lastAudit['band']})", style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace')),
            Text("BSSID: ${lastAudit['bssid']}", style: const TextStyle(color: Colors.white70, fontFamily: 'monospace')),
            Text("LINK SPEED: ${lastAudit['link_speed']} Mbps | DBM: ${lastAudit['dbm']}", style: const TextStyle(color: Colors.white70, fontFamily: 'monospace')),
          ])))
        ],
      ),
    );
  }
}

// ================= LOGS GOD MODE =================
class DatabaseProView extends StatelessWidget {
  const DatabaseProView({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("System Logs", style: TextStyle(fontFamily: 'monospace')), backgroundColor: Colors.black, foregroundColor: Colors.greenAccent),
      backgroundColor: const Color(0xFF0F0F0F),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: DatabasePro.getAudits(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Colors.greenAccent));
          final audits = snapshot.data!;
          return ListView.builder(
            itemCount: audits.length,
            itemBuilder: (context, index) {
              final a = audits[index];
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(border: Border(left: BorderSide(color: getGodColor(a['dbm']), width: 4)), color: Colors.black87),
                child: ListTile(
                  title: Text("[${a['dbm']}] ${a['tech']}", style: TextStyle(color: getGodColor(a['dbm']), fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                  subtitle: Text("${a['extra_data']}\n${a['timestamp'].toString().substring(11, 19)}", style: const TextStyle(color: Colors.white54, fontFamily: 'monospace', fontSize: 11)),
                  isThreeLine: true,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
DART

echo "🚀 3/3 Compilando God Mode (Low RAM)..."
flutter build apk --profile

if [ -f "build/app/outputs/flutter-apk/app-profile.apk" ]; then
    gh release create v10.0-godmode build/app/outputs/flutter-apk/app-profile.apk --repo txurtxil/SignalMapper --title "🔥 SignalMapper V10 GOD MODE" --notes "Extracción máxima de hardware. UI Hacker. Arreglado bug de variables. PCI, TAC, SNR, BSSID, Link Speed."
    echo "===================================================="
    echo "✅ ¡MODO DIOS INSTALADO!"
    echo "Descarga rápido y vete a pagar la cuenta: https://github.com/txurtxil/SignalMapper/releases/latest"
    echo "===================================================="
else
    echo "❌ Revisa la terminal."
fi
