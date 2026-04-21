#!/bin/bash
cd /workspaces/SignalMapper/app_nativa

echo "⚙️ 1/4 Preparando el entorno para Potencia Máxima..."
# Aseguramos dependencias modernas
flutter pub add sqflite path image_picker geolocator flutter_map latlong2 permission_handler flutter_svg
flutter pub get

echo "🧪 2/4 Inyectando Motor Nativo Kotlin (Auditoría Profunda)..."
# Reconstruimos MainActivity con acceso directo a Telephony y WiFi Managers
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
        audit["dbm"] = -120 // Valor por defecto
        audit["tech"] = "Unknown"
        audit["cell_id"] = -1
        audit["rsrp"] = -140

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val cellInfoList = tm.allCellInfo
            if (!cellInfoList.isNullOrEmpty()) {
                val info = cellInfoList[0] // Cogemos la celda principal
                if (info is CellInfoLte) {
                    audit["tech"] = "4G (LTE)"
                    audit["cell_id"] = info.cellIdentity.ci
                    audit["dbm"] = info.cellSignalStrength.dbm
                    audit["rsrp"] = info.cellSignalStrength.rsrp
                } else if (info is CellInfoNr && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    audit["tech"] = "5G (NR)"
                    // En algunas versiones NrCsiRsrp es más preciso
                    audit["dbm"] = info.cellSignalStrength.dbm
                    // audit["cell_id"] = info.cellIdentity.nci // Requiere API superior a veces
                } else if (info is CellInfoGsm) {
                    audit["tech"] = "2G (GSM)"
                    audit["dbm"] = info.cellSignalStrength.dbm
                }
            }
        }
        return audit
    }

    private fun getWifiAudit(): Map<String, Any> {
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val info = wifiManager.connectionInfo
        val audit = mutableMapOf<String, Any>()
        
        audit["dbm"] = info.rssi
        audit["ssid"] = info.ssid.replace("\"", "") // Quitamos comillas si existen
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            val freq = info.frequency
            audit["freq_mhz"] = freq
            audit["band"] = if (freq in 2400..2500) "2.4 GHz" else if (freq in 5000..6000) "5 GHz" else "Unknown"
        } else {
            audit["band"] = "Unknown"
        }
        return audit
    }
}
KOTLIN

echo "🏗️ 3/4 Reconstruyendo Super App Dart (Interfaz Power Pro)..."
# Reemplazamos lib/main.dart con el nuevo diseño y lógica profunda
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
  runApp(const MaterialApp(
    home: PowerProNavigation(),
    debugShowCheckedModeBanner: false,
  ));
}

// ================= BBDD PRO =================
class DatabasePro {
  static late Database db;
  static Future<void> init() async {
    db = await openDatabase(
      join(await getDatabasesPath(), 'signal_power_pro.db'),
      onCreate: (db, version) {
        return db.execute(
          'CREATE TABLE audits(id INTEGER PRIMARY KEY, type TEXT, dbm INTEGER, tech TEXT, cell_id INTEGER, ssid TEXT, band TEXT, lat REAL, lng REAL, x REAL, y REAL, image_path TEXT, timestamp TEXT)',
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

// ================= NAVEGACIÓN PRO =================
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
        backgroundColor: const Color(0xFF1A1A2E),
        selectedItemColor: Colors.cyanAccent,
        unselectedItemColor: Colors.white54,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.wifi_tethering), label: "Indoor Pro"),
          BottomNavigationBarItem(icon: Icon(Icons.radar), label: "Outdoor Pro"),
          BottomNavigationBarItem(icon: Icon(Icons.storage), label: "BBDD"),
        ],
      ),
    );
  }
}

// ================= COLOR LOGIC PRO =================
Color getProColor(int dbm) {
  // Ajustado para ser más estricto (profesional)
  if (dbm >= -65) return Colors.greenAccent; // Excelente
  if (dbm >= -85) return Colors.limeAccent;   // Buena
  if (dbm >= -100) return Colors.orangeAccent; // Regular
  return Colors.redAccent;                    // Crítica
}

// ================= 1. OUTDOOR PRO (4G/5G Profundo) =================
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
    _requestPerms();
  }

  void _requestPerms() async {
    await [Permission.location, Permission.phone].request();
  }

  void _toggleTracking() {
    setState(() {
      isTracking = !isTracking;
      if (isTracking) {
        timer = Timer.periodic(const Duration(seconds: 4), (t) => _recordData());
      } else {
        timer?.cancel();
      }
    });
  }

  Future<void> _recordData() async {
    try {
      // 1. Auditoría profunda nativa
      final Map<dynamic, dynamic> nativeAudit = await platform.invokeMethod('getCellularAudit');
      final Map<String, dynamic> audit = Map<String, dynamic>.from(nativeAudit);
      int dbm = audit['dbm'] ?? -120;

      // 2. Posición GPS alta precisión
      Position p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      LatLng pos = LatLng(p.latitude, p.longitude);

      // 3. Insertar en BBDD Pro
      await DatabasePro.insertAudit({
        'type': 'outdoor',
        'dbm': dbm,
        'tech': audit['tech'],
        'cell_id': audit['cell_id'],
        'lat': p.latitude,
        'lng': p.longitude,
        'timestamp': DateTime.now().toIso8601String()
      });

      if (mounted) {
        setState(() {
          currentPos = pos;
          currentAudit = audit;
          _points.add(CircleMarker(
            point: pos,
            color: getProColor(dbm).withOpacity(0.8),
            radius: 16,
            borderColor: Colors.white,
            borderStrokeWidth: 2,
          ));
        });
        _mapController.move(pos, 17.5);
      }
    } catch (e) {
      debugPrint("Error Outdoor Pro: \$e");
    }
  }

  @override
  Widget build(BuildContext context) {
    String tech = currentAudit['tech'] ?? 'Unknown';
    int dbm = currentAudit['dbm'] ?? -120;
    int cellId = currentAudit['cell_id'] ?? -1;

    return Scaffold(
      appBar: AppBar(
        title: Text("Out: \$tech | \$dbm dBm"),
        backgroundColor: const Color(0xFF16213E),
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
                initialCenter: LatLng(43.297, -2.985), // Barakaldo
                initialZoom: 16),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.app_nativa',
              ),
              CircleLayer(circles: _points),
              if (currentPos != null)
                MarkerLayer(markers: [
                  Marker(
                      point: currentPos!,
                      child: const Icon(Icons.location_history,
                          color: Colors.cyanAccent, size: 35)),
                ]),
            ],
          ),
          Positioned(
              top: 10,
              left: 10,
              right: 10,
              child: Card(
                color: const Color(0xFF1A1A2E).withOpacity(0.8),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text("Tech: \$tech | CID: \$cellId",
                      style: const TextStyle(
                          color: Colors.cyanAccent, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center),
                ),
              )),
          Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: ElevatedButton(
                onPressed: _toggleTracking,
                style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isTracking ? Colors.redAccent : Colors.cyanAccent,
                    padding: const EdgeInsets.all(18)),
                child: Text(isTracking ? "DETENER" : "INICIAR AUDITORÍA PRO",
                    style: const TextStyle(
                        color: Color(0xFF1A1A2E),
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
              )),
        ],
      ),
    );
  }
}

// ================= 2. INDOOR PRO (WiFi Táctil Profundo) =================
class IndoorPro extends StatefulWidget {
  const IndoorPro({super.key});
  @override
  State<IndoorPro> createState() => _IndoorProState();
}
class _IndoorProState extends State<IndoorPro> {
  static const platform = MethodChannel('com.signalmapper/power_pro');
  File? floorPlan;
  List<Map<String, dynamic>> indoorPoints = [];

  Future<void> _pickImage() async {
    final pickedFile =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (pickedFile != null) setState(() => floorPlan = File(pickedFile.path));
  }

  void _addPoint(TapDownDetails details, BuildContext context) async {
    if (floorPlan == null) return;
    try {
      // 1. Auditoría WiFi nativa instantly
      final Map<dynamic, dynamic> nativeAudit =
          await platform.invokeMethod('getWifiAudit');
      final Map<String, dynamic> audit = Map<String, dynamic>.from(nativeAudit);
      int dbm = audit['dbm'] ?? -127;

      // 2. Calcular coordenadas en el plano
      final RenderBox box = context.findRenderObject() as RenderBox;
      final Offset localOffset = box.globalToLocal(details.globalPosition);

      // 3. Insertar en BBDD Pro
      await DatabasePro.insertAudit({
        'type': 'indoor',
        'dbm': dbm,
        'ssid': audit['ssid'],
        'band': audit['band'],
        'x': localOffset.dx,
        'y': localOffset.dy,
        'image_path': floorPlan!.path,
        'timestamp': DateTime.now().toIso8601String()
      });

      setState(() {
        indoorPoints
            .add({'x': localOffset.dx, 'y': localOffset.dy, 'dbm': dbm});
      });
    } catch (e) {
      debugPrint("Error Indoor Pro: \$e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Mapeo WiFi Táctil Pro"),
        backgroundColor: const Color(0xFF16213E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
              icon: const Icon(Icons.add_photo_alternate),
              onPressed: _pickImage)
        ],
      ),
      backgroundColor: Colors.black,
      body: floorPlan == null
          ? const Center(
              child: Text("Sube un plano desde tu galería\n[Icono superior]",
                  style: TextStyle(color: Colors.white54),
                  textAlign: TextAlign.center))
          : InteractiveViewer(
              maxScale: 6.0,
              child: GestureDetector(
                onTapDown: (details) => _addPoint(details, context),
                child: Stack(
                  children: [
                    Image.file(floorPlan!,
                        fit: BoxFit.contain,
                        width: double.infinity,
                        height: double.infinity),
                    ...indoorPoints.map((p) => Positioned(
                          left: p['x'] - 12, // Centrar el punto
                          top: p['y'] - 12,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                                color: getProColor(p['dbm']).withOpacity(0.9),
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.white, width: 2),
                                boxShadow: const [
                                  BoxShadow(
                                      color: Colors.black26, blurRadius: 4)
                                ]),
                          ),
                        ))
                  ],
                ),
              ),
            ),
    );
  }
}

// ================= 3. DATABASE PRO VIEW =================
class DatabaseProView extends StatelessWidget {
  const DatabaseProView({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Auditoría Histórica Pro"),
        backgroundColor: const Color(0xFF16213E),
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: DatabasePro.getAudits(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final audits = snapshot.data!;
          return ListView.builder(
            itemCount: audits.length,
            itemBuilder: (context, index) {
              final a = audits[index];
              bool isIndoor = a['type'] == 'indoor';
              
              // Corrección de los errores de formato en la BBDD anterior
              String infoSubtitle = isIndoor
                  ? "WiFi: ${a['ssid']} | Band: ${a['band']}\nLoc: (${a['x']?.toStringAsFixed(0)}, ${a['y']?.toStringAsFixed(0)})"
                  : "Tech: ${a['tech']} | CID: ${a['cell_id']}\nLat: ${a['lat']?.toStringAsFixed(5)} | Lng: ${a['lng']?.toStringAsFixed(5)}";

              return Card(
                color: isIndoor ? const Color(0xFF112B3C) : const Color(0xFF251D3A),
                margin: const EdgeInsets.all(6),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: getProColor(a['dbm']),
                    child: Text("${a['dbm']}", style: const TextStyle(color: Color(0xFF1A1A2E), fontWeight: FontWeight.bold)),
                  ),
                  title: Text(isIndoor ? "Indoor Audit (WiFi)" : "Outdoor Audit (Cell)"),
                  subtitle: Text(infoSubtitle, style: const TextStyle(color: Colors.white70)),
                  trailing: Text(a['timestamp'].toString().substring(5, 16).replaceAll("T", " "), style: const TextStyle(color: Colors.white38, fontSize: 11)),
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

echo "🚀 Compilando v9.0 Titan Power Pro..."
# Forzamos una compilación limpia para evitar residuos de memoria en el servidor
flutter clean
flutter pub get
flutter build apk --profile

if [ -f "build/app/outputs/flutter-apk/app-profile.apk" ]; then
    gh release create v9.0-pro build/app/outputs/flutter-apk/app-profile.apk --repo txurtxil/SignalMapper --title "🔥 SignalMapper V9.0 POWER PRO" --notes "Fusión Titan. Mapeo profundo Kotlin (4G/5G/WiFi). Mapeo Indoor táctil y Outdoor automatizado. BBDD SQLite Pro integrada."
    echo "===================================================="
    echo "✅ ¡ESTE ES EL BUENO! Tienes la Potencia Máxima."
    echo "URL: https://github.com/txurtxil/SignalMapper/releases/latest"
    echo "===================================================="
else
    echo "❌ Revisa errores de compilación arriba."
fi
