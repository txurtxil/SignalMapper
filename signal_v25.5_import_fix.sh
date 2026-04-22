#!/bin/bash
cd /workspaces/SignalMapper/app_nativa

echo "🧩 1/2 Devolviendo la librería 'dart:ui' perdida a su sitio..."
cat << 'DART' > lib/main.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui'; // 🔥 LA LIBRERÍA PERDIDA HA VUELTO 🔥
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
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabasePro.init();
  await initializeService();
  runApp(const MaterialApp(home: PowerProNavigation(), debugShowCheckedModeBanner: false, themeMode: ThemeMode.dark));
}

// ================= MOTOR BACKGROUND BLINDADO =================
Future<void> initializeService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'audit_service',
      initialNotificationTitle: 'SM AUDIT: ACTIVE',
      initialNotificationContent: 'Auditoría en segundo plano',
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
        service.invoke('update');
      }
    }
  });
}

// ================= BBDD FORENSE =================
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

// ================= UTILIDADES FORENSES =================
bool isCellular(String techOrType) {
  String t = techOrType.toLowerCase();
  return t.contains('4g') || t.contains('5g') || t.contains('lte') || t.contains('nr') || t.contains('cell') || t.contains('móvil') || t.contains('outdoor');
}

Color getGodColor(int dbm, String tech) {
  if (isCellular(tech)) {
    if (dbm >= -85) return Colors.greenAccent;
    if (dbm >= -100) return Colors.yellowAccent;
    if (dbm >= -110) return Colors.orangeAccent;
    return Colors.purpleAccent; 
  } else {
    if (dbm >= -65) return Colors.greenAccent;
    if (dbm >= -75) return Colors.yellowAccent;
    if (dbm >= -85) return Colors.orangeAccent;
    return Colors.redAccent;
  }
}

String sanitizeRF(dynamic value) {
  if (value == null) return '-';
  String strVal = value.toString();
  if (strVal == '2147483647' || strVal == '2147483647.0') return '[HIDDEN]';
  return strVal;
}

// ================= NAVEGACIÓN Y PERMISOS SEGUROS =================
class PowerProNavigation extends StatefulWidget { const PowerProNavigation({super.key}); @override State<PowerProNavigation> createState() => _PowerProNavigationState(); }
class _PowerProNavigationState extends State<PowerProNavigation> {
  int _currentIndex = 1;
  final List<Widget> _screens = [const IndoorPro(), const OutdoorPro(), const DatabaseProView()];

  @override void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await [Permission.location, Permission.phone, Permission.notification].request();
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) await Geolocator.requestPermission();
    if (await Permission.location.isGranted) {
      await Permission.locationAlways.request();
    }
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex, onTap: (i) => setState(() => _currentIndex = i),
        backgroundColor: Colors.black, selectedItemColor: Colors.greenAccent, unselectedItemColor: Colors.white30,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Indoor"),
          BottomNavigationBarItem(icon: Icon(Icons.radar), label: "Audit Out"),
          BottomNavigationBarItem(icon: Icon(Icons.memory), label: "Logs"),
        ],
      ),
    );
  }
}

// ================= OUTDOOR PRO =================
class OutdoorPro extends StatefulWidget { const OutdoorPro({super.key}); @override State<OutdoorPro> createState() => _OutdoorProState(); }
class _OutdoorProState extends State<OutdoorPro> {
  static const platform = MethodChannel('com.signalmapper/power_pro');
  LatLng? currentPos; 
  Map<String, dynamic> currentAudit = {'dbm': 0, 'tech': 'ESPERANDO...', 'operator': '-', 'cell_id': '-', 'rsrq': 0, 'snr': 0};
  String currentStreet = "NO FIX";
  
  int _latency = 0;
  String _lastCellId = "";
  String _anomalyAlert = "";
  
  final List<CircleMarker> _livePoints = []; final List<LatLng> _liveRoute = [];
  final List<CircleMarker> _forensicPoints = []; final List<LatLng> _forensicRoute = [];

  String sessionId = ""; bool isTracking = false; final MapController _mapController = MapController();
  StreamSubscription? _bgSubscription;

  @override
  void initState() {
    super.initState();
    _bgSubscription = FlutterBackgroundService().on('update').listen((event) {
      if (isTracking && mounted) _recordData();
    });
  }

  @override
  void dispose() {
    _bgSubscription?.cancel();
    super.dispose();
  }

  void _toggleTracking() async { 
    final service = FlutterBackgroundService();
    bool isRunning = await service.isRunning();
    
    setState(() { 
      isTracking = !isTracking; 
      if (isTracking) {
        sessionId = "Audit_${DateTime.now().millisecondsSinceEpoch}";
        _liveRoute.clear(); _livePoints.clear(); 
        _lastCellId = ""; _anomalyAlert = "";
        currentStreet = "INICIANDO MOTOR...";
        
        try {
          if (!isRunning) service.startService();
        } catch (e) {
          debugPrint("Error arrancando servicio: $e");
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error al lanzar servicio de fondo"), backgroundColor: Colors.red));
        }
        
        _recordData();

      } else {
        try { service.invoke("stopService"); } catch (e) {}
      }
    }); 
  }

  Future<void> _recordData() async {
    try {
      final stopwatch = Stopwatch()..start();
      bool hasInternet = false;
      try {
        final result = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 2));
        hasInternet = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      } catch (_) {}
      stopwatch.stop();
      int latency = hasInternet ? stopwatch.elapsedMilliseconds : 999;

      final nativeAudit = await platform.invokeMethod('getCellularAudit');
      final audit = Map<String, dynamic>.from(nativeAudit);
      int dbm = audit['dbm'] ?? -120;
      
      String sanitizedCID = sanitizeRF(audit['cell_id']);
      String sanitizedSNR = sanitizeRF(audit['snr']);
      String sanitizedRSRQ = sanitizeRF(audit['rsrq']);
      
      audit['cell_id'] = sanitizedCID; audit['snr'] = sanitizedSNR; audit['rsrq'] = sanitizedRSRQ;

      String tempAlert = "";
      if (_lastCellId != "" && sanitizedCID != "[HIDDEN]" && sanitizedCID != "-" && _lastCellId != sanitizedCID) {
        tempAlert = "⚠️ HANDOVER DETECTADO: CAMBIO DE TORRE";
        HapticFeedback.heavyImpact(); 
      }
      if (sanitizedCID != "[HIDDEN]" && sanitizedCID != "-") _lastCellId = sanitizedCID;
      if (latency > 300) tempAlert = "🔥 ALERTA DE LATENCIA: $latency ms";

      Position? p;
      try { p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 3)); } 
      catch (e) { p = await Geolocator.getLastKnownPosition(); }
      if (p == null) return;

      LatLng pos = LatLng(p.latitude, p.longitude);
      String streetName = "TRACKING...";
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(p.latitude, p.longitude);
        if (placemarks.isNotEmpty) streetName = "${placemarks.first.thoroughfare}".toUpperCase();
      } catch (e) {}

      await DatabasePro.insertAudit({
        'session_id': sessionId, 'type': 'outdoor', 'dbm': dbm, 'tech': audit['tech'], 'address': streetName,
        'extra_data': "Op: ${audit['operator']} | CID: $sanitizedCID | RSRQ: $sanitizedRSRQ | SNR: $sanitizedSNR | LAT: $latency ms",
        'lat': p.latitude, 'lng': p.longitude, 'timestamp': DateTime.now().toIso8601String()
      });
      
      if (tempAlert.isEmpty) HapticFeedback.lightImpact();

      if (mounted) setState(() {
        currentPos = pos; currentAudit = audit; currentStreet = streetName; _latency = latency;
        if (tempAlert.isNotEmpty) _anomalyAlert = tempAlert; 
        _liveRoute.add(pos); 
        _livePoints.add(CircleMarker(point: pos, color: getGodColor(dbm, 'cell'), radius: 10, borderColor: latency > 300 ? Colors.red : Colors.black, borderStrokeWidth: 2));
      });
      _mapController.move(pos, 17.5);
      
      if (tempAlert.isNotEmpty) {
        Future.delayed(const Duration(seconds: 3), () { if (mounted) setState(() => _anomalyAlert = ""); });
      }
    } catch (e) {}
  }

  Future<void> _importForensicCSV() async {
    try {
      const fs.XTypeGroup typeGroup = fs.XTypeGroup(label: 'Archivos CSV', extensions: ['csv']);
      final fs.XFile? file = await fs.openFile(acceptedTypeGroups: [typeGroup]);
      if (file != null) {
        File f = File(file.path);
        List<String> lines = await f.readAsLines();
        setState(() { _forensicRoute.clear(); _forensicPoints.clear(); });
        
        for (int i = 1; i < lines.length; i++) {
          List<String> cols = lines[i].split(',');
          if (cols.length > 8 && cols[2] == "outdoor") {
            int dbm = int.parse(cols[3]);
            LatLng pos = LatLng(double.parse(cols[6]), double.parse(cols[7]));
            setState(() { 
              _forensicRoute.add(pos); 
              _forensicPoints.add(CircleMarker(point: pos, color: getGodColor(dbm, 'cell').withOpacity(0.4), radius: 14)); 
            });
            if (i == 1) _mapController.move(pos, 17.0);
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("DATOS FORENSES CARGADOS"), backgroundColor: Colors.green[900]));
      }
    } catch (e) {}
  }

  void _clearForensics() { setState(() { _forensicRoute.clear(); _forensicPoints.clear(); }); }

  @override Widget build(BuildContext context) {
    int dbm = currentAudit['dbm'] ?? 0;
    bool isDeadZone = dbm < -110 && dbm != 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text("AUDIT OUTDOOR", style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', color: Colors.greenAccent)), 
        backgroundColor: const Color(0xFF121212), 
        actions: [
          if (_forensicPoints.isNotEmpty) IconButton(icon: const Icon(Icons.layers_clear, color: Colors.redAccent), onPressed: _clearForensics),
          IconButton(icon: const Icon(Icons.manage_search, color: Colors.greenAccent), onPressed: _importForensicCSV)
        ]
      ),
      body: Stack(children: [
        FlutterMap(mapController: _mapController, options: MapOptions(initialCenter: LatLng(43.297, -2.985), initialZoom: 17), children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.txurtxil.smaudit'),
          PolylineLayer(polylines: [Polyline(points: _forensicRoute, color: Colors.grey.withOpacity(0.5), strokeWidth: 8.0, pattern: StrokePattern.dashed(segments: [10.0, 10.0]))]),
          CircleLayer(circles: _forensicPoints),
          PolylineLayer(polylines: [Polyline(points: _liveRoute, color: Colors.blueAccent, strokeWidth: 4.0)]),
          CircleLayer(circles: _livePoints),
          if (currentPos != null) MarkerLayer(markers: [Marker(point: currentPos!, child: const Icon(Icons.my_location, color: Colors.blueAccent, size: 30))]),
        ]),
        
        Positioned(top: 10, left: 10, right: 10, child: Card(
          color: isDeadZone ? Colors.purple[900]?.withOpacity(0.9) : Colors.black.withOpacity(0.85),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5), side: BorderSide(color: isDeadZone ? Colors.purpleAccent : Colors.greenAccent, width: 1)),
          child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text("[ ${currentAudit['tech']} ]", style: TextStyle(color: isDeadZone ? Colors.white : Colors.greenAccent, fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 16)),
              Text("Ping: ${_latency}ms", style: TextStyle(color: _latency > 300 ? Colors.redAccent : Colors.amberAccent, fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 14)),
              Text("$dbm dBm", style: TextStyle(color: getGodColor(dbm, 'cell'), fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
            ]),
            const Divider(color: Colors.greenAccent, thickness: 0.5),
            Text("LOC: $currentStreet", style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 12)),
            Text("OPR: ${currentAudit['operator'] ?? '-'} | CID: ${currentAudit['cell_id'] ?? '-'}", style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12)),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text("RSRQ (Quality): ${currentAudit['rsrq'] ?? '-'}", style: const TextStyle(color: Colors.yellowAccent, fontFamily: 'monospace', fontSize: 12)),
              Text("SNR (Noise): ${currentAudit['snr'] ?? '-'}", style: const TextStyle(color: Colors.cyanAccent, fontFamily: 'monospace', fontSize: 12)),
            ]),
            if (isDeadZone) Padding(padding: const EdgeInsets.only(top: 5), child: const Text("WARNING: PACKET DROP EMINENT (DEAD ZONE)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, backgroundColor: Colors.red, fontFamily: 'monospace', fontSize: 11))),
            if (_anomalyAlert.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 5), child: Text(_anomalyAlert, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, backgroundColor: Colors.yellowAccent, fontFamily: 'monospace', fontSize: 11))),
          ]))
        )),

        Positioned(bottom: 20, left: 20, right: 20, child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!isTracking && _livePoints.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: ElevatedButton.icon(
            onPressed: () async {
              String p = await DatabasePro.exportSessionCSV(sessionId, "Outdoor");
              await Share.shareXFiles([XFile(p)], text: "Auditoría RF Finalizada");
            }, 
            icon: const Icon(Icons.download, color: Colors.black), label: const Text("EXPORTAR AUDITORÍA", style: TextStyle(color: Colors.black, fontFamily: 'monospace', fontWeight: FontWeight.bold)), 
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white, minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)))
          )),
          ElevatedButton(
            onPressed: _toggleTracking, 
            style: ElevatedButton.styleFrom(backgroundColor: isTracking ? Colors.redAccent : Colors.greenAccent, minimumSize: const Size(double.infinity, 60), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5))), 
            child: Text(isTracking ? "ABORTAR CAPTURA (BG ACTIVO)" : "INICIAR AUDITORÍA", style: const TextStyle(color: Colors.black, fontSize: 16, fontFamily: 'monospace', fontWeight: FontWeight.bold))
          ),
        ]))
      ]),
    );
  }
}

// ================= INDOOR PRO & LOGS =================
class IndoorPro extends StatelessWidget { const IndoorPro({super.key}); @override Widget build(BuildContext context) { return const Scaffold(backgroundColor: Color(0xFF1E1E1E), body: Center(child: Text("INDOOR ACTIVE", style: TextStyle(color: Colors.greenAccent, fontFamily: 'monospace')))); } }
class DatabaseProView extends StatelessWidget { const DatabaseProView({super.key}); @override Widget build(BuildContext context) { return const Scaffold(backgroundColor: Color(0xFF1E1E1E), body: Center(child: Text("LOGS ACTIVE", style: TextStyle(color: Colors.greenAccent, fontFamily: 'monospace')))); } }
DART

echo "🚀 2/2 Compilando V25.5 (El Import Perdido)..."
flutter build apk --profile

if [ -f "build/app/outputs/flutter-apk/app-profile.apk" ]; then
    gh release create v25.5-import-fix build/app/outputs/flutter-apk/app-profile.apk --repo txurtxil/SignalMapper --title "🛡️ SM AUDIT V25.5: Final Fix" --notes "Añadida la importación de dart:ui requerida por el background_service."
    echo "===================================================="
    echo "✅ ¡COMPILADO AL 100% Y LISTO!"
    echo "===================================================="
else
    echo "❌ Error al compilar."
fi
