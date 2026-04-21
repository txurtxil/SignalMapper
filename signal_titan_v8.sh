#!/bin/bash
cd /workspaces/SignalMapper/app_nativa

echo "📦 1/4 Añadiendo superpoderes (BBDD, Galería y Mapa)..."
flutter pub add sqflite path image_picker

echo "🛡️ 2/4 Configurando Permisos Android (Añadiendo WiFi)..."
cat << 'XML' > android/app/src/main/AndroidManifest.xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.READ_PHONE_STATE" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <application android:label="SignalTitan" android:icon="@mipmap/ic_launcher" android:requestLegacyExternalStorage="true">
        <activity android:name=".MainActivity" android:exported="true" android:launchMode="singleTop" android:theme="@style/LaunchTheme" android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode" android:hardwareAccelerated="true" android:windowSoftInputMode="adjustResize">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <meta-data android:name="flutterEmbedding" android:value="2" />
    </application>
</manifest>
XML

echo "🧠 3/4 Ampliando Motor Nativo Kotlin (4G/5G + WiFi)..."
cat << 'KOTLIN' > android/app/src/main/kotlin/com/example/app_nativa/MainActivity.kt
package com.example.app_nativa

import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Context
import android.telephony.TelephonyManager
import android.net.wifi.WifiManager

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.signalmapper/signal"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
            call, result ->
            if (call.method == "getSignalDbm") {
                result.success(getCellularDbm())
            } else if (call.method == "getWifiDbm") {
                result.success(getWifiDbm())
            } else {
                result.notImplemented()
            }
        }
    }

    private fun getCellularDbm(): Int {
        val telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        var dbm = -110
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
            val signalStrength = telephonyManager.signalStrength
            if (signalStrength != null) {
                val cellSignalStrengths = signalStrength.cellSignalStrengths
                if (cellSignalStrengths.isNotEmpty()) {
                    dbm = cellSignalStrengths[0].dbm
                }
            }
        }
        return dbm
    }

    private fun getWifiDbm(): Int {
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        return wifiManager.connectionInfo.rssi
    }
}
KOTLIN

echo "🏗️ 4/4 Construyendo la Super App Dart (Indoor + Outdoor + BD)..."
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
  await DatabaseHelper.init();
  runApp(const MaterialApp(home: MainNavigation(), debugShowCheckedModeBanner: false));
}

// ================= BBDD SQLITE =================
class DatabaseHelper {
  static late Database db;
  static Future<void> init() async {
    db = await openDatabase(
      join(await getDatabasesPath(), 'signal_titan.db'),
      onCreate: (db, version) {
        return db.execute(
          'CREATE TABLE scans(id INTEGER PRIMARY KEY, type TEXT, dbm INTEGER, lat REAL, lng REAL, x REAL, y REAL, image_path TEXT, timestamp TEXT)',
        );
      },
      version: 1,
    );
  }
  static Future<void> insertScan(Map<String, dynamic> scan) async {
    await db.insert('scans', scan, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  static Future<List<Map<String, dynamic>>> getScans() async {
    return await db.query('scans', orderBy: 'timestamp DESC');
  }
}

// ================= NAVEGACIÓN =================
class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});
  @override
  State<MainNavigation> createState() => _MainNavigationState();
}
class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 1;
  final List<Widget> _screens = [const IndoorScreen(), const OutdoorScreen(), const HistoryScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        backgroundColor: Colors.blueGrey[900],
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.white54,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.wifi), label: "Indoor"),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: "Outdoor"),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: "Historial"),
        ],
      ),
    );
  }
}

// ================= COLOR LOGIC =================
Color getSignalColor(int dbm) {
  if (dbm >= -70) return Colors.green;
  if (dbm >= -90) return Colors.yellow;
  if (dbm >= -105) return Colors.orange;
  return Colors.red;
}

// ================= 1. OUTDOOR SCREEN (4G/5G) =================
class OutdoorScreen extends StatefulWidget {
  const OutdoorScreen({super.key});
  @override
  State<OutdoorScreen> createState() => _OutdoorScreenState();
}
class _OutdoorScreenState extends State<OutdoorScreen> {
  static const platform = MethodChannel('com.signalmapper/signal');
  LatLng? currentPos;
  int currentDbm = -100;
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
      if (isTracking) timer = Timer.periodic(const Duration(seconds: 5), (t) => _recordData());
      else timer?.cancel();
    });
  }

  Future<void> _recordData() async {
    try {
      final int dbm = await platform.invokeMethod('getSignalDbm');
      Position p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      LatLng pos = LatLng(p.latitude, p.longitude);

      await DatabaseHelper.insertScan({
        'type': 'outdoor', 'dbm': dbm, 'lat': p.latitude, 'lng': p.longitude, 'timestamp': DateTime.now().toIso8601String()
      });

      if (mounted) {
        setState(() {
          currentPos = pos;
          currentDbm = dbm;
          _points.add(CircleMarker(point: pos, color: getSignalColor(dbm).withOpacity(0.7), radius: 15));
        });
        _mapController.move(pos, 17.0);
      }
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Mapeo Outdoor: \$currentDbm dBm"), backgroundColor: Colors.blueGrey[900], foregroundColor: Colors.white),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: LatLng(43.297, -2.985), initialZoom: 16),
            children: [
              // ARREGLADO EL ERROR 403 DE OSM (AÑADIDO USER AGENT)
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.app_nativa'
              ),
              CircleLayer(circles: _points),
              if (currentPos != null) MarkerLayer(markers: [Marker(point: currentPos!, child: const Icon(Icons.my_location, color: Colors.blue, size: 30))]),
            ],
          ),
          Positioned(bottom: 20, left: 20, right: 20, child: ElevatedButton(
            onPressed: _toggleTracking,
            style: ElevatedButton.styleFrom(backgroundColor: isTracking ? Colors.red : Colors.blueAccent, padding: const EdgeInsets.all(15)),
            child: Text(isTracking ? "DETENER" : "INICIAR RASTREO 4G/5G", style: const TextStyle(color: Colors.white, fontSize: 18)),
          )),
        ],
      ),
    );
  }
}

// ================= 2. INDOOR SCREEN (WiFi) =================
class IndoorScreen extends StatefulWidget {
  const IndoorScreen({super.key});
  @override
  State<IndoorScreen> createState() => _IndoorScreenState();
}
class _IndoorScreenState extends State<IndoorScreen> {
  static const platform = MethodChannel('com.signalmapper/signal');
  File? floorPlan;
  List<Map<String, dynamic>> indoorPoints = [];

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (pickedFile != null) setState(() => floorPlan = File(pickedFile.path));
  }

  void _addPoint(TapDownDetails details, BuildContext context) async {
    final int dbm = await platform.invokeMethod('getWifiDbm');
    final RenderBox box = context.findRenderObject() as RenderBox;
    final Offset localOffset = box.globalToLocal(details.globalPosition);
    
    await DatabaseHelper.insertScan({
      'type': 'indoor', 'dbm': dbm, 'x': localOffset.dx, 'y': localOffset.dy, 'image_path': floorPlan!.path, 'timestamp': DateTime.now().toIso8601String()
    });

    setState(() {
      indoorPoints.add({'x': localOffset.dx, 'y': localOffset.dy, 'dbm': dbm});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Mapeo Indoor (WiFi)"), backgroundColor: Colors.blueGrey[900], foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.upload_file), onPressed: _pickImage)],
      ),
      backgroundColor: Colors.black,
      body: floorPlan == null
          ? const Center(child: Text("Sube un plano de tu galería", style: TextStyle(color: Colors.white)))
          : InteractiveViewer(
              maxScale: 5.0,
              child: GestureDetector(
                onTapDown: (details) => _addPoint(details, context),
                child: Stack(
                  children: [
                    Image.file(floorPlan!, fit: BoxFit.contain, width: double.infinity, height: double.infinity),
                    ...indoorPoints.map((p) => Positioned(
                      left: p['x'] - 10, top: p['y'] - 10,
                      child: Container(
                        width: 20, height: 20,
                        decoration: BoxDecoration(color: getSignalColor(p['dbm']), shape: BoxShape.circle, border: Border.all(color: Colors.white)),
                      ),
                    ))
                  ],
                ),
              ),
            ),
    );
  }
}

// ================= 3. HISTORY SCREEN (BBDD) =================
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Base de Datos"), backgroundColor: Colors.blueGrey[900], foregroundColor: Colors.white),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: DatabaseHelper.getScans(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final scans = snapshot.data!;
          return ListView.builder(
            itemCount: scans.length,
            itemBuilder: (context, index) {
              final s = scans[index];
              return ListTile(
                leading: Icon(s['type'] == 'indoor' ? Icons.wifi : Icons.map, color: getSignalColor(s['dbm'])),
                title: Text("${s['dbm']} dBm (${s['type']})"),
                subtitle: Text(s['type'] == 'indoor' ? "X: \${s['x']?.toStringAsFixed(1)} Y: \${s['y']?.toStringAsFixed(1)}" : "Lat: \${s['lat']?.toStringAsFixed(4)} Lng: \${s['lng']?.toStringAsFixed(4)}"),
                trailing: Text(s['timestamp'].toString().substring(0, 16)),
              );
            },
          );
        },
      ),
    );
  }
}
DART

echo "🚀 Compilando Titan V8 (Indoor + Outdoor + BD)..."
flutter clean
flutter build apk --release --no-pub

if [ -f "build/app/outputs/flutter-apk/app-release.apk" ]; then
    gh release create v8.0-titan build/app/outputs/flutter-apk/app-release.apk --repo txurtxil/SignalMapper --title "🔥 SignalMapper V8 Titan" --notes "Fusión total. Arreglado OSM. Añadido Mapeo Indoor WiFi táctil. Añadida Base de Datos."
    echo "===================================================="
    echo "✅ ¡SISTEMA COMPLETADO CON ÉXITO!"
    echo "Descarga: https://github.com/txurtxil/SignalMapper/releases/latest"
    echo "===================================================="
else
    echo "❌ Revisa los logs. Algo falló en la compilación."
fi
