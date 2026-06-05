#!/bin/bash
cd /workspaces/SignalMapper/app_nativa

echo "📦 1/3 Instalando lanzador de URLs tácticas..."
flutter pub add url_launcher

echo "🧬 2/3 Inyectando Interfaz de Reconocimiento Visual (V40)..."
cat << 'DART' > lib/main.dart
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_selector/file_selector.dart' as fs;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:url_launcher/url_launcher.dart'; // 🔥 NUEVO: LANZADOR DE MAPAS EXTERN0S

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabasePro.init();
  runApp(const MaterialApp(home: PermissionGate(), debugShowCheckedModeBanner: false, themeMode: ThemeMode.dark));
}

// ================= GATEKEEPER =================
class PermissionGate extends StatefulWidget { const PermissionGate({super.key}); @override State<PermissionGate> createState() => _PermissionGateState(); }
class _PermissionGateState extends State<PermissionGate> {
  String statusText = "AUDITANDO SISTEMA..."; bool needsManualSettings = false;
  @override void initState() { super.initState(); _checkAndRequestPermissions(); }
  Future<void> _checkAndRequestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [Permission.location, Permission.phone, Permission.notification, Permission.locationAlways].request();
    bool allGranted = true; statuses.forEach((permission, status) { if (!status.isGranted) allGranted = false; });
    bool isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
    if (allGranted && isLocationServiceEnabled) { if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PowerProNavigation())); }
    else { setState(() { statusText = "PERMISOS REQUERIDOS"; needsManualSettings = true; }); }
  }
  @override Widget build(BuildContext context) { return Scaffold(backgroundColor: Colors.black, body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [ const Icon(Icons.security, color: Colors.redAccent, size: 80), const SizedBox(height: 20), Text(statusText, style: const TextStyle(color: Colors.white, fontFamily: 'monospace')), if (needsManualSettings) ElevatedButton(onPressed: () => openAppSettings(), child: const Text("ABRIR AJUSTES")) ]))); }
}

// ================= MOTORES DE TRILATERACIÓN =================
class TowerEstimate { String cellId; int bestDbm; double weightedLat; double weightedLng; double sumWeights; TowerEstimate(this.cellId, LatLng pos, this.bestDbm) : weightedLat = pos.latitude, weightedLng = pos.longitude, sumWeights = math.pow(10, bestDbm / 20.0).toDouble(); void addObservation(LatLng pos, int dbm) { double w = math.pow(10, dbm / 20.0).toDouble(); weightedLat = (weightedLat * sumWeights + pos.latitude * w) / (sumWeights + w); weightedLng = (weightedLng * sumWeights + pos.longitude * w) / (sumWeights + w); sumWeights += w; if (dbm > bestDbm) bestDbm = dbm; } LatLng get estimatedPosition => LatLng(weightedLat, weightedLng); }
class WifiEstimate { String bssid; String ssid; int bestDbm; bool isVulnerable; double weightedLat; double weightedLng; double sumWeights; WifiEstimate(this.bssid, this.ssid, LatLng pos, this.bestDbm, this.isVulnerable) : weightedLat = pos.latitude, weightedLng = pos.longitude, sumWeights = math.pow(10, bestDbm / 20.0).toDouble(); void addObservation(LatLng pos, int dbm) { double w = math.pow(10, dbm / 20.0).toDouble(); weightedLat = (weightedLat * sumWeights + pos.latitude * w) / (sumWeights + w); weightedLng = (weightedLng * sumWeights + pos.longitude * w) / (sumWeights + w); sumWeights += w; if (dbm > bestDbm) bestDbm = dbm; } LatLng get estimatedPosition => LatLng(weightedLat, weightedLng); }

// ================= BBDD FORENSE =================
class DatabasePro {
  static late Database db;
  static Future<void> init() async { db = await openDatabase(p.join(await getDatabasesPath(), 'signal_v27_audit2.db'), onCreate: (db, version) { return db.execute('CREATE TABLE audits(id INTEGER PRIMARY KEY, session_id TEXT, type TEXT, dbm INTEGER, tech TEXT, extra_data TEXT, lat REAL, lng REAL, x REAL, y REAL, address TEXT, timestamp TEXT)'); }, version: 1); }
  static Future<void> insertAudit(Map<String, dynamic> audit) async { await db.insert('audits', audit, conflictAlgorithm: ConflictAlgorithm.replace); }
  static Future<List<Map<String, dynamic>>> getAudits() async { return await db.query('audits', orderBy: 'timestamp DESC'); }
  static Future<String> exportSessionCSV(String sessionId, String type) async { final data = await db.query('audits', where: 'session_id = ?', whereArgs: [sessionId]); StringBuffer sb = StringBuffer("ID,Sesion,Tipo,DBM,Tecnologia,Extra,Lat,Lng,X,Y,Direccion,Fecha\n"); for(var row in data) { sb.write("${row['id']},${row['session_id']},${row['type']},${row['dbm']},${row['tech']},\"${row['extra_data']}\",${row['lat'] ?? ''},${row['lng'] ?? ''},${row['x'] ?? ''},${row['y'] ?? ''},\"${row['address']}\",${row['timestamp']}\n"); } final directory = await getApplicationDocumentsDirectory(); final path = p.join(directory.path, "Audit2_${type}_$sessionId.csv"); await File(path).writeAsString(sb.toString()); return path; }
}

// ================= HYPERVISOR =================
class PowerProNavigation extends StatefulWidget { const PowerProNavigation({super.key}); @override State<PowerProNavigation> createState() => _PowerProNavigationState(); }
class _PowerProNavigationState extends State<PowerProNavigation> {
  int _currentIndex = 1;
  final List<Widget> _screens = [const IndoorPro(), const OutdoorPro(), const CyberOpsTerminal()];
  @override Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex, onTap: (i) => setState(() => _currentIndex = i),
        backgroundColor: Colors.black, selectedItemColor: Colors.greenAccent, unselectedItemColor: Colors.white30,
        items: const [BottomNavigationBarItem(icon: Icon(Icons.home), label: "Indoor"), BottomNavigationBarItem(icon: Icon(Icons.radar), label: "Cazador"), BottomNavigationBarItem(icon: Icon(Icons.terminal), label: "Ops Desk")],
      ),
    );
  }
}

// ================= OUTDOOR PRO (RECON VISUAL) =================
class OutdoorPro extends StatefulWidget { const OutdoorPro({super.key}); @override State<OutdoorPro> createState() => _OutdoorProState(); }
class _OutdoorProState extends State<OutdoorPro> {
  static const platform = MethodChannel('com.signalmapper/power_pro');
  LatLng? currentPos; Map<String, dynamic> currentAudit = {'dbm': 0, 'tech': 'ESPERANDO...', 'operator': '-', 'cell_id': '-', 'rsrq': 0, 'snr': 0};
  String currentStreet = "NO FIX"; int _latency = 0; int _wifiCount = 0; int _vulnCount = 0;
  final List<Map<String, dynamic>> _liveData = []; final List<LatLng> _liveRoute = [];
  final Map<String, TowerEstimate> _discoveredTowers = {}; final Map<String, WifiEstimate> _discoveredWifis = {}; 
  bool _isQualityMode = false; bool _showWifiLayer = false; bool _ghostModeActive = false; 
  String sessionId = ""; bool isTracking = false; final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionStream;

  // 🔥 NUEVO: TARGET SELECCIONADO PARA RECONOCIMIENTO
  dynamic selectedTarget; 

  @override void dispose() { _positionStream?.cancel(); WakelockPlus.disable(); super.dispose(); }

  void _toggleTracking() async { 
    if (isTracking) { _positionStream?.cancel(); setState(() { isTracking = false; }); WakelockPlus.disable(); } else {
      setState(() { isTracking = true; sessionId = "Audit2_${DateTime.now().millisecondsSinceEpoch}"; _liveRoute.clear(); _liveData.clear(); _discoveredTowers.clear(); _discoveredWifis.clear(); _wifiCount = 0; _vulnCount = 0; });
      WakelockPlus.enable(); 
      late LocationSettings locationSettings = const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 2);
      _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position? position) { if (position != null && mounted) _recordData(position); });
    }
  }

  Future<void> _recordData(Position p) async {
    LatLng pos = LatLng(p.latitude, p.longitude);
    final nativeAudit = await platform.invokeMethod('getCellularAudit');
    final audit = Map<String, dynamic>.from(nativeAudit); int dbm = audit['dbm'] ?? -120;
    String sanitizedCID = sanitizeRF(audit['cell_id']);
    
    // TRILATERACIÓN MÓVIL
    if (sanitizedCID != "[HIDDEN]" && sanitizedCID != "-") {
      if (_discoveredTowers.containsKey(sanitizedCID)) { _discoveredTowers[sanitizedCID]!.addObservation(pos, dbm); }
      else { _discoveredTowers[sanitizedCID] = TowerEstimate(sanitizedCID, pos, dbm); }
    }

    // WARDRIVING WIFI
    try {
      final results = await WiFiScan.instance.getScannedResults();
      for (var ap in results) {
        if (ap.ssid.isEmpty) continue;
        bool isVuln = !ap.capabilities.toUpperCase().contains('WPA');
        if (_discoveredWifis.containsKey(ap.bssid)) { _discoveredWifis[ap.bssid]!.addObservation(pos, ap.level); }
        else { _wifiCount++; if(isVuln) _vulnCount++; _discoveredWifis[ap.bssid] = WifiEstimate(ap.bssid, ap.ssid, pos, ap.level, isVuln); }
      }
    } catch (e) {}

    if (mounted) setState(() { currentPos = pos; currentAudit = audit; _liveRoute.add(pos); _liveData.add({'pos': pos, 'dbm': dbm, 'rsrq': audit['rsrq']}); });
    _mapController.move(pos, 18.0);
  }

  // 🔥 FUNCIÓN DE SALTO A GOOGLE MAPS / STREET VIEW
  void _launchVisualRecon(String type, LatLng pos) async {
    String url = "";
    if (type == 'maps') {
      url = "https://www.google.com/maps/search/?api=1&query=${pos.latitude},${pos.longitude}";
    } else {
      url = "https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=${pos.latitude},${pos.longitude}";
    }
    if (await canLaunchUrl(Uri.parse(url))) { await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication); }
  }

  @override Widget build(BuildContext context) {
    if (_ghostModeActive) { return Scaffold(backgroundColor: Colors.black, body: InkWell(onTap: () => setState(() => _ghostModeActive = false), child: const Center(child: Text("MODO FANTASMA ACTIVO", style: TextStyle(color: Colors.greenAccent, fontFamily: 'monospace'))))); }

    List<Marker> targetMarkers = [];
    _discoveredTowers.forEach((id, tower) {
      targetMarkers.add(Marker(
        point: tower.estimatedPosition, width: 60, height: 60,
        child: GestureDetector(
          onTap: () => setState(() => selectedTarget = tower),
          child: const Icon(Icons.cell_tower, color: Colors.redAccent, size: 40),
        )
      ));
    });

    if (_showWifiLayer) {
      _discoveredWifis.forEach((bssid, wifi) {
        targetMarkers.add(Marker(
          point: wifi.estimatedPosition, width: 40, height: 40,
          child: GestureDetector(
            onTap: () => setState(() => selectedTarget = wifi),
            child: Icon(wifi.isVulnerable ? Icons.lock_open : Icons.router, color: wifi.isVulnerable ? Colors.orangeAccent : Colors.cyanAccent, size: 25),
          )
        ));
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text("LIVE TARGETING", style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', color: Colors.greenAccent)), backgroundColor: Colors.black, actions: [
        IconButton(icon: Icon(_showWifiLayer ? Icons.wifi_tethering : Icons.wifi_off, color: _showWifiLayer ? Colors.cyanAccent : Colors.white54), onPressed: () => setState(() => _showWifiLayer = !_showWifiLayer)),
        IconButton(icon: const Icon(Icons.visibility_off, color: Colors.grey), onPressed: () => setState(() => _ghostModeActive = true)),
      ]),
      body: Stack(children: [
        FlutterMap(mapController: _mapController, options: MapOptions(initialCenter: LatLng(43.297, -2.985), initialZoom: 18), children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
          PolylineLayer(polylines: [Polyline(points: _liveRoute, color: Colors.blueAccent.withOpacity(0.5), strokeWidth: 4.0)]),
          MarkerLayer(markers: targetMarkers),
          if (currentPos != null) MarkerLayer(markers: [Marker(point: currentPos!, child: const Icon(Icons.my_location, color: Colors.blueAccent, size: 25))]),
        ]),

        // 🔥 PANEL DE RECONOCIMIENTO VISUAL (SE ACTIVA AL TOCAR UNA ANTENA)
        if (selectedTarget != null) Positioned(bottom: 100, left: 10, right: 10, child: Card(
          color: Colors.black.withOpacity(0.9), borderOnForeground: true, shape: RoundedRectangleBorder(side: const BorderSide(color: Colors.greenAccent, width: 2), borderRadius: BorderRadius.circular(10)),
          child: Padding(padding: const EdgeInsets.all(15), child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(selectedTarget is TowerEstimate ? "ANTENA DETECTADA" : "ROUTER DETECTADO", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
            const SizedBox(height: 5),
            Text(selectedTarget is TowerEstimate ? "CID: ${selectedTarget.cellId}" : "SSID: ${selectedTarget.ssid}", style: const TextStyle(color: Colors.white, fontSize: 16, fontFamily: 'monospace')),
            const Divider(color: Colors.greenAccent),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              ElevatedButton.icon(onPressed: () => _launchVisualRecon('maps', selectedTarget.estimatedPosition), icon: const Icon(Icons.directions), label: const Text("MAPS"), style: ElevatedButton.styleFrom(backgroundColor: Colors.white12)),
              ElevatedButton.icon(onPressed: () => _launchVisualRecon('street', selectedTarget.estimatedPosition), icon: const Icon(Icons.streetview), label: const Text("STREET VIEW"), style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent.withOpacity(0.3))),
              IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => setState(() => selectedTarget = null))
            ])
          ]))
        )),

        Positioned(bottom: 20, left: 20, right: 20, child: ElevatedButton(onPressed: _toggleTracking, style: ElevatedButton.styleFrom(backgroundColor: isTracking ? Colors.redAccent : Colors.greenAccent, minimumSize: const Size(double.infinity, 60)), child: Text(isTracking ? "ABORTAR" : "INICIAR TARGETING", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold))))
      ]),
    );
  }
}

String sanitizeRF(dynamic value) { if (value == null) return '-'; String strVal = value.toString(); if (strVal == '2147483647' || strVal == '2147483647.0') return '[HIDDEN]'; return strVal; }
class IndoorPro extends StatelessWidget { const IndoorPro({super.key}); @override Widget build(BuildContext context) { return const Scaffold(backgroundColor: Colors.black, body: Center(child: Text("Módulo Indoor Activo", style: TextStyle(color: Colors.greenAccent)))); } }
class CyberOpsTerminal extends StatelessWidget { const CyberOpsTerminal({super.key}); @override Widget build(BuildContext context) { return const Scaffold(backgroundColor: Colors.black, body: Center(child: Text("Ops Desk Activo", style: TextStyle(color: Colors.greenAccent)))); } }
class SparklinePainter extends CustomPainter { final List<num> data; final Color color; final double minVal; final double maxVal; SparklinePainter(this.data, this.color, this.minVal, this.maxVal); @override void paint(Canvas canvas, Size size) { if (data.isEmpty) return; final paint = Paint()..color = color..strokeWidth = 2.0..style = PaintingStyle.stroke; final path = Path(); double range = maxVal - minVal; if (range == 0) range = 1; double stepX = size.width / 29; for (int i = 0; i < data.length; i++) { double normalizedY = 1 - ((data[i] - minVal) / range).clamp(0.0, 1.0); double x = i * stepX; double y = normalizedY * size.height; if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); } } canvas.drawPath(path, paint); } @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true; }
DART

echo "🚀 Compilando SM Audit 2 (V40 Visual Recon)..."
flutter build apk --profile

if [ -f "build/app/outputs/flutter-apk/app-profile.apk" ]; then
    gh release create v40.0-visual-recon build/app/outputs/flutter-apk/app-profile.apk --repo txurtxil/SignalMapper --title "👁️ SM AUDIT 2 (V40): Visual Recon" --notes "Se ha inyectado la capacidad de interactuar con las antenas en el mapa. Selecciona un objetivo para abrir Google Maps o Street View y localizar físicamente el hardware."
    echo "✅ ¡V40 LISTA PARA EL RECONOCIMIENTO FÍSICO!"
else
    echo "❌ Error al compilar."
fi
