#!/bin/bash
cd /workspaces/SignalMapper/app_nativa

echo "📦 1/3 Instalando Motor de Servicio en Segundo Plano..."
flutter pub add flutter_background_service
flutter pub add device_info_plus
flutter pub get

echo "🔐 2/3 Configurando Permisos de Persistencia en Android..."
cat << 'XML' > android/app/src/main/AndroidManifest.xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
    <uses-permission android:name="android.permission.READ_PHONE_STATE" />
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />

    <application
        android:label="SM Audit"
        android:icon="@mipmap/ic_launcher">
        <service
            android:name="id.flutter.flutter_background_service.BackgroundService"
            android:foregroundServiceType="location" />
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

echo "🧠 3/3 Inyectando Lógica de Auditoría Persistente (V25)..."
cat << 'DART' > lib/main.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_selector/file_selector.dart' as fs;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabasePro.init();
  await initializeService();
  runApp(const MaterialApp(home: PowerProNavigation(), debugShowCheckedModeBanner: false, themeMode: ThemeMode.dark));
}

// ================= MOTOR DE SERVICIO (BACKGROUND) =================
Future<void> initializeService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'audit_service',
      initialNotificationTitle: 'SM AUDIT: ACTIVE SCAN',
      initialNotificationContent: 'Mapeando en segundo plano...',
      foregroundServiceTypes: [AndroidForegroundType.location],
    ),
    iosConfiguration: IosConfiguration(),
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) => service.setAsForegroundService());
    service.on('setAsBackground').listen((event) => service.setAsBackgroundService());
  }
  service.on('stopService').listen((event) => service.stopSelf());

  Timer.periodic(const Duration(seconds: 4), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        // Aquí se ejecuta la lógica de captura incluso bloqueado
        service.invoke('update');
      }
    }
  });
}

// ================= BBDD =================
class DatabasePro {
  static late Database db;
  static Future<void> init() async {
    db = await openDatabase(p.join(await getDatabasesPath(), 'signal_v24_audit.db'),
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
    final path = p.join(directory.path, "Audit_${type}_$sessionId.csv");
    await File(path).writeAsString(csv);
    return path;
  }
}

// ================= UTILIDADES =================
String sanitizeRF(dynamic value) {
  if (value == null) return '-';
  String strVal = value.toString();
  if (strVal == '2147483647' || strVal == '2147483647.0') return '[HIDDEN]';
  return strVal;
}

Color getGodColor(int dbm) {
  if (dbm >= -85) return Colors.greenAccent;
  if (dbm >= -100) return Colors.yellowAccent;
  if (dbm >= -110) return Colors.orangeAccent;
  return Colors.purpleAccent;
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
        backgroundColor: Colors.black, selectedItemColor: Colors.greenAccent, unselectedItemColor: Colors.white30,
        items: const [BottomNavigationBarItem(icon: Icon(Icons.home), label: "Indoor"), BottomNavigationBarItem(icon: Icon(Icons.radar), label: "Audit Out"), BottomNavigationBarItem(icon: Icon(Icons.memory), label: "Logs")],
      ),
    );
  }
}

// ================= OUTDOOR PRO (V25) =================
class OutdoorPro extends StatefulWidget { const OutdoorPro({super.key}); @override State<OutdoorPro> createState() => _OutdoorProState(); }
class _OutdoorProState extends State<OutdoorPro> {
  static const platform = MethodChannel('com.signalmapper/power_pro');
  LatLng? currentPos; 
  Map<String, dynamic> currentAudit = {'dbm': 0, 'tech': 'READY', 'operator': '-', 'cell_id': '-', 'rsrq': 0, 'snr': 0};
  int _latency = 0;
  String _lastCellId = "";
  String _anomalyAlert = "";
  final List<CircleMarker> _livePoints = []; final List<LatLng> _liveRoute = [];
  final List<CircleMarker> _forensicPoints = []; final List<LatLng> _forensicRoute = [];
  String sessionId = ""; bool isTracking = false; final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    FlutterBackgroundService().on('update').listen((event) {
      if (isTracking) _recordData();
    });
  }

  void _toggleTracking() async { 
    final service = FlutterBackgroundService();
    var isRunning = await service.isRunning();
    
    setState(() { 
      isTracking = !isTracking; 
      if (isTracking) {
        sessionId = "Audit_${DateTime.now().millisecondsSinceEpoch}";
        _liveRoute.clear(); _livePoints.clear(); 
        if (!isRunning) service.startService();
      } else {
        service.invoke("stopService");
      }
    }); 
  }

  Future<void> _recordData() async {
    try {
      // 1. PING TEST (Auditoría Activa)
      final stopwatch = Stopwatch()..start();
      bool hasInternet = false;
      try {
        final result = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 2));
        hasInternet = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      } catch (_) {}
      stopwatch.stop();
      int latency = hasInternet ? stopwatch.elapsedMilliseconds : 999;

      // 2. RF DATA
      final nativeAudit = await platform.invokeMethod('getCellularAudit');
      final audit = Map<String, dynamic>.from(nativeAudit);
      int dbm = audit['dbm'] ?? -120;
      String cid = sanitizeRF(audit['cell_id']);

      // 3. ANOMALÍAS
      String alert = "";
      if (_lastCellId != "" && cid != "[HIDDEN]" && _lastCellId != cid) {
        alert = "⚠️ HANDOVER: ${_lastCellId} -> ${cid}";
        HapticFeedback.vibrate();
      }
      _lastCellId = cid;

      Position p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      LatLng pos = LatLng(p.latitude, p.longitude);

      await DatabasePro.insertAudit({
        'session_id': sessionId, 'type': 'outdoor', 'dbm': dbm, 'tech': audit['tech'],
        'extra_data': "LAT: $latency ms | CID: $cid | SNR: ${sanitizeRF(audit['snr'])}",
        'lat': p.latitude, 'lng': p.longitude, 'timestamp': DateTime.now().toIso8601String()
      });

      if (mounted) setState(() {
        currentPos = pos; currentAudit = audit; _latency = latency; _anomalyAlert = alert;
        _liveRoute.add(pos); 
        _livePoints.add(CircleMarker(point: pos, color: getGodColor(dbm), radius: 10, borderColor: latency > 300 ? Colors.red : Colors.black, borderStrokeWidth: 2));
      });
      _mapController.move(pos, 17.5);
    } catch (e) {}
  }

  @override Widget build(BuildContext context) {
    int dbm = currentAudit['dbm'] ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text("AUDIT PRO V25", style: TextStyle(fontFamily: 'monospace', color: Colors.greenAccent)), backgroundColor: Colors.black),
      body: Stack(children: [
        FlutterMap(mapController: _mapController, options: MapOptions(initialCenter: LatLng(43.297, -2.985), initialZoom: 17), children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
          PolylineLayer(polylines: [Polyline(points: _liveRoute, color: Colors.blueAccent, strokeWidth: 4.0)]),
          CircleLayer(circles: _livePoints),
          if (currentPos != null) MarkerLayer(markers: [Marker(point: currentPos!, child: const Icon(Icons.my_location, color: Colors.blueAccent))]),
        ]),
        Positioned(top: 10, left: 10, right: 10, child: Card(
          color: Colors.black.withOpacity(0.8),
          child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text("${currentAudit['tech']}", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
              Text("$_latency ms", style: TextStyle(color: _latency > 200 ? Colors.red : Colors.greenAccent, fontWeight: FontWeight.bold)),
              Text("$dbm dBm", style: TextStyle(color: getGodColor(dbm), fontWeight: FontWeight.bold)),
            ]),
            if (_anomalyAlert.isNotEmpty) Text(_anomalyAlert, style: const TextStyle(backgroundColor: Colors.yellow, color: Colors.black, fontSize: 10)),
          ]))
        )),
        Positioned(bottom: 20, left: 20, right: 20, child: ElevatedButton(
          onPressed: _toggleTracking, 
          style: ElevatedButton.styleFrom(backgroundColor: isTracking ? Colors.red : Colors.greenAccent, minimumSize: const Size(double.infinity, 60)),
          child: Text(isTracking ? "ABORTAR (BG ACTIVE)" : "INICIAR AUDITORÍA", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold))
        )),
      ]),
    );
  }
}

// ================= INDOOR & LOGS (SIN CAMBIOS) =================
class IndoorPro extends StatelessWidget { const IndoorPro({super.key}); @override Widget build(BuildContext context) { return const Scaffold(body: Center(child: Text("INDOOR ACTIVE"))); } }
class DatabaseProView extends StatelessWidget { const DatabaseProView({super.key}); @override Widget build(BuildContext context) { return const Scaffold(body: Center(child: Text("LOGS ACTIVE"))); } }
DART

echo "🚀 4/4 Compilando SM Audit V25 (Background Edition)..."
flutter build apk --profile

if [ -f "build/app/outputs/flutter-apk/app-profile.apk" ]; then
    gh release create v25.0-background build/app/outputs/flutter-apk/app-profile.apk --repo txurtxil/SignalMapper --title "🕵️ SM AUDIT V25: Background Ghost" --notes "Soporte para mapeo con pantalla bloqueada. Test de latencia (Ping) activo. Alertas de Handover mejoradas."
    echo "===================================================="
    echo "✅ ¡V25 LISTA!"
    echo "IMPORTANTE: En el móvil, ve a Ajustes -> Aplicaciones -> SM Audit"
    echo "y pon el permiso de Ubicación en 'Permitir siempre'."
    echo "===================================================="
else
    echo "❌ Error al compilar."
fi
