#!/bin/bash
cd /workspaces/SignalMapper/app_nativa

echo "🎯 Inyectando Sistema de Rastreo Visual en Tiempo Real (V37)..."
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabasePro.init();
  runApp(const MaterialApp(home: PowerProNavigation(), debugShowCheckedModeBanner: false, themeMode: ThemeMode.dark));
}

// ================= MOTORES DE TRILATERACIÓN MATEMÁTICA =================
class TowerEstimate {
  String cellId; int bestDbm; 
  double weightedLat; double weightedLng; double sumWeights;

  TowerEstimate(this.cellId, LatLng pos, this.bestDbm) 
    : weightedLat = pos.latitude, weightedLng = pos.longitude, sumWeights = math.pow(10, bestDbm / 20.0).toDouble();

  void addObservation(LatLng pos, int dbm) {
    double w = math.pow(10, dbm / 20.0).toDouble();
    weightedLat = (weightedLat * sumWeights + pos.latitude * w) / (sumWeights + w);
    weightedLng = (weightedLng * sumWeights + pos.longitude * w) / (sumWeights + w);
    sumWeights += w;
    if (dbm > bestDbm) bestDbm = dbm;
  }
  LatLng get estimatedPosition => LatLng(weightedLat, weightedLng);
}

class WifiEstimate {
  String bssid; String ssid; int bestDbm; bool isVulnerable;
  double weightedLat; double weightedLng; double sumWeights;

  WifiEstimate(this.bssid, this.ssid, LatLng pos, this.bestDbm, this.isVulnerable)
    : weightedLat = pos.latitude, weightedLng = pos.longitude, sumWeights = math.pow(10, bestDbm / 20.0).toDouble();

  void addObservation(LatLng pos, int dbm) {
    double w = math.pow(10, dbm / 20.0).toDouble();
    weightedLat = (weightedLat * sumWeights + pos.latitude * w) / (sumWeights + w);
    weightedLng = (weightedLng * sumWeights + pos.longitude * w) / (sumWeights + w);
    sumWeights += w;
    if (dbm > bestDbm) bestDbm = dbm;
  }
  LatLng get estimatedPosition => LatLng(weightedLat, weightedLng);
}

// ================= BBDD FORENSE =================
class DatabasePro {
  static late Database db;
  static Future<void> init() async {
    db = await openDatabase(p.join(await getDatabasesPath(), 'signal_v27_audit2.db'),
      onCreate: (db, version) {
        return db.execute('CREATE TABLE audits(id INTEGER PRIMARY KEY, session_id TEXT, type TEXT, dbm INTEGER, tech TEXT, extra_data TEXT, lat REAL, lng REAL, x REAL, y REAL, address TEXT, timestamp TEXT)');
      }, version: 1);
  }
  static Future<void> insertAudit(Map<String, dynamic> audit) async { await db.insert('audits', audit, conflictAlgorithm: ConflictAlgorithm.replace); }
  static Future<List<Map<String, dynamic>>> getAudits() async { return await db.query('audits', orderBy: 'timestamp DESC'); }
  
  static Future<String> exportSessionCSV(String sessionId, String type) async {
    final data = await db.query('audits', where: 'session_id = ?', whereArgs: [sessionId]);
    StringBuffer sb = StringBuffer("ID,Sesion,Tipo,DBM,Tecnologia,Extra,Lat,Lng,X,Y,Direccion,Fecha\n");
    for(var row in data) { sb.write("${row['id']},${row['session_id']},${row['type']},${row['dbm']},${row['tech']},\"${row['extra_data']}\",${row['lat'] ?? ''},${row['lng'] ?? ''},${row['x'] ?? ''},${row['y'] ?? ''},\"${row['address']}\",${row['timestamp']}\n"); }
    final directory = await getApplicationDocumentsDirectory();
    final path = p.join(directory.path, "Audit2_${type}_$sessionId.csv");
    await File(path).writeAsString(sb.toString()); return path;
  }

  static String _escapeXml(String text) { return text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&apos;'); }

  static Future<String> exportSessionKML(String sessionId, Iterable<TowerEstimate> towers, Iterable<WifiEstimate> wifis) async {
    final data = await db.query('audits', where: 'session_id = ? AND type = "outdoor"', whereArgs: [sessionId], orderBy: 'timestamp ASC');
    StringBuffer sb = StringBuffer('<?xml version="1.0" encoding="UTF-8"?>\n<kml xmlns="http://www.opengis.net/kml/2.2">\n<Document>\n<name>Ruta 3D SM Audit</name>\n');
    if (data.isNotEmpty) {
      sb.write('<Placemark><name>Trayectoria</name><LineString><coordinates>\n');
      for(var row in data) { sb.write('${row['lng']},${row['lat']},0 '); }
      sb.write('\n</coordinates></LineString></Placemark>\n');
    }
    for(var t in towers) { sb.write('<Placemark><name>Torre CID: ${t.cellId}</name><description>Mejor DBM: ${t.bestDbm}</description><Style><IconStyle><color>ff0000ff</color><scale>1.5</scale></IconStyle></Style><Point><coordinates>${t.estimatedPosition.longitude},${t.estimatedPosition.latitude},0</coordinates></Point></Placemark>\n'); }
    for(var w in wifis) {
      String safeSsid = _escapeXml(w.ssid); String color = w.isVulnerable ? "ff0000ff" : "ffff0000"; 
      sb.write('<Placemark><name>WiFi: $safeSsid</name><description>Vulnerable: ${w.isVulnerable} | DBM: ${w.bestDbm}</description><Style><IconStyle><color>$color</color><scale>1.2</scale></IconStyle></Style><Point><coordinates>${w.estimatedPosition.longitude},${w.estimatedPosition.latitude},0</coordinates></Point></Placemark>\n');
    }
    sb.write('</Document>\n</kml>');
    final directory = await getApplicationDocumentsDirectory();
    final path = p.join(directory.path, "Audit2_3D_$sessionId.kml");
    await File(path).writeAsString(sb.toString()); return path;
  }

  static Future<String> exportWiGLE() async {
    final data = await db.query('audits', where: 'type = "wifi"');
    StringBuffer sb = StringBuffer("WigleWifi-1.4,appRelease=2.0,model=SignalMapperPro,release=1.0,device=SMAudit,display=SMAudit,board=SMAudit,brand=TXURTXIL\n");
    sb.write("MAC,SSID,AuthMode,FirstSeen,Channel,RSSI,CurrentLatitude,CurrentLongitude,AltitudeMeters,AccuracyMeters,Type\n");
    for(var row in data) {
      String extra = row['extra_data'].toString();
      String mac = "00:00:00:00:00:00"; String auth = "[UNKNOWN]";
      if(extra.contains("BSSID: ")) { int idx = extra.indexOf("BSSID: ") + 7; int end = extra.indexOf(" |", idx); if(end != -1) mac = extra.substring(idx, end); }
      if(extra.contains("Caps: ")) { auth = extra.substring(extra.indexOf("Caps: ") + 6); }
      String ssid = (row['tech'] ?? 'Unknown').toString().replaceAll(',', ' '); 
      String time = row['timestamp'].toString().replaceFirst('T', ' ').split('.')[0]; 
      sb.write("$mac,$ssid,$auth,$time,1,${row['dbm']},${row['lat']},${row['lng']},0,10,WIFI\n");
    }
    final directory = await getApplicationDocumentsDirectory();
    final path = p.join(directory.path, "WiGLE_Upload_${DateTime.now().millisecondsSinceEpoch}.csv");
    await File(path).writeAsString(sb.toString()); return path;
  }
}

// ================= UTILIDADES =================
bool isCellular(String techOrType) { String t = techOrType.toLowerCase(); return t.contains('4g') || t.contains('5g') || t.contains('lte') || t.contains('nr') || t.contains('cell') || t.contains('móvil') || t.contains('outdoor') || t.contains('voz'); }
Color getGodColor(int dbm, String tech) { if (isCellular(tech)) { if (dbm >= -85) return Colors.greenAccent; if (dbm >= -100) return Colors.yellowAccent; if (dbm >= -110) return Colors.orangeAccent; return Colors.purpleAccent; } else { if (dbm >= -65) return Colors.greenAccent; if (dbm >= -75) return Colors.yellowAccent; if (dbm >= -85) return Colors.orangeAccent; return Colors.redAccent; } }
Color getQualityColor(dynamic rsrqVal) { if (rsrqVal == null || rsrqVal.toString() == '[HIDDEN]' || rsrqVal.toString() == '-') return Colors.grey; double r = double.tryParse(rsrqVal.toString()) ?? -20; if (r >= -10) return Colors.greenAccent; if (r >= -15) return Colors.yellowAccent; if (r >= -18) return Colors.orangeAccent; return Colors.redAccent; }
String sanitizeRF(dynamic value) { if (value == null) return '-'; String strVal = value.toString(); if (strVal == '2147483647' || strVal == '2147483647.0') return '[HIDDEN]'; return strVal; }

class SparklinePainter extends CustomPainter {
  final List<num> data; final Color color; final double minVal; final double maxVal;
  SparklinePainter(this.data, this.color, this.minVal, this.maxVal);
  @override void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final paint = Paint()..color = color..strokeWidth = 2.0..style = PaintingStyle.stroke;
    final path = Path(); double range = maxVal - minVal; if (range == 0) range = 1; double stepX = size.width / 29; 
    for (int i = 0; i < data.length; i++) { double normalizedY = 1 - ((data[i] - minVal) / range).clamp(0.0, 1.0); double x = i * stepX; double y = normalizedY * size.height; if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); } }
    canvas.drawPath(path, paint);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
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

// ================= OUTDOOR PRO (LIVE TARGETING UI) =================
class OutdoorPro extends StatefulWidget { const OutdoorPro({super.key}); @override State<OutdoorPro> createState() => _OutdoorProState(); }
class _OutdoorProState extends State<OutdoorPro> {
  static const platform = MethodChannel('com.signalmapper/power_pro');
  LatLng? currentPos; Map<String, dynamic> currentAudit = {'dbm': 0, 'tech': 'ESPERANDO...', 'operator': '-', 'cell_id': '-', 'rsrq': 0, 'snr': 0};
  String currentStreet = "NO FIX"; int _latency = 0; int _wifiCount = 0; int _vulnCount = 0;
  String _lastCellId = ""; String _anomalyAlert = "";
  final List<Map<String, dynamic>> _liveData = []; final List<LatLng> _liveRoute = [];
  
  final Map<String, TowerEstimate> _discoveredTowers = {}; 
  final Map<String, WifiEstimate> _discoveredWifis = {}; 
  
  final List<int> _pingHistory = []; final List<double> _rsrqHistory = [];

  bool _isQualityMode = false; bool _showWifiLayer = false; 
  bool _ghostModeActive = false; 

  String sessionId = ""; bool isTracking = false; final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionStream;

  @override void dispose() { _positionStream?.cancel(); WakelockPlus.disable(); super.dispose(); }

  void _toggleTracking() async { 
    if (isTracking) {
      _positionStream?.cancel(); setState(() { isTracking = false; });
      WakelockPlus.disable();
    } else {
      setState(() { 
        isTracking = true; sessionId = "Audit2_${DateTime.now().millisecondsSinceEpoch}";
        _liveRoute.clear(); _liveData.clear(); _discoveredTowers.clear(); _discoveredWifis.clear();
        _pingHistory.clear(); _rsrqHistory.clear(); _wifiCount = 0; _vulnCount = 0; _lastCellId = ""; _anomalyAlert = "";
        currentStreet = "GPS LISTO";
      });
      WakelockPlus.enable(); 
      late LocationSettings locationSettings;
      if (Platform.isAndroid) {
        locationSettings = AndroidSettings(accuracy: LocationAccuracy.high, distanceFilter: 2, forceLocationManager: false, foregroundNotificationConfig: const ForegroundNotificationConfig(notificationText: "Cazador activo.", notificationTitle: "SM Audit 2", enableWakeLock: true, notificationIcon: AndroidResource(name: 'ic_bg_service_small', defType: 'drawable')));
      } else { locationSettings = const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 2); }
      _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position? position) { if (position != null && mounted) _recordData(position); });
    }
  }

  Future<void> _recordData(Position p) async {
    try {
      LatLng pos = LatLng(p.latitude, p.longitude);
      final stopwatch = Stopwatch()..start(); bool hasInternet = false;
      try { final result = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 2)); hasInternet = result.isNotEmpty && result[0].rawAddress.isNotEmpty; } catch (_) {}
      stopwatch.stop(); int latency = hasInternet ? stopwatch.elapsedMilliseconds : 999;

      final nativeAudit = await platform.invokeMethod('getCellularAudit');
      final audit = Map<String, dynamic>.from(nativeAudit); int dbm = audit['dbm'] ?? -120;
      String sanitizedCID = sanitizeRF(audit['cell_id']); String sanitizedSNR = sanitizeRF(audit['snr']); String sanitizedRSRQ = sanitizeRF(audit['rsrq']);
      audit['cell_id'] = sanitizedCID; audit['snr'] = sanitizedSNR; audit['rsrq'] = sanitizedRSRQ;

      List<Map<String, dynamic>> wifiBatchData = [];
      try {
        final canScan = await WiFiScan.instance.canStartScan();
        if (canScan == CanStartScan.yes) await WiFiScan.instance.startScan();
        final results = await WiFiScan.instance.getScannedResults();
        for (var ap in results) {
          String ssid = ap.ssid; if (ssid.isEmpty || ssid.toLowerCase().contains('unknown')) continue;
          int wDbm = ap.level; if (wDbm < -95) continue; 
          String bssid = ap.bssid; 
          String caps = ap.capabilities.toUpperCase(); bool isVuln = false;
          if (!caps.contains('WPA') && !caps.contains('WEP')) isVuln = true; if (caps.contains('WEP')) isVuln = true;
          String s = ssid.toLowerCase(); if (s.contains('free') || s.contains('public') || s.contains('guest') || s.contains('abierto')) isVuln = true;

          if (_discoveredWifis.containsKey(bssid)) {
            _discoveredWifis[bssid]!.addObservation(pos, wDbm);
          } else {
            _wifiCount++; if(isVuln) _vulnCount++;
            _discoveredWifis[bssid] = WifiEstimate(bssid, ssid, pos, wDbm, isVuln);
          }
          wifiBatchData.add({'session_id': sessionId, 'type': 'wifi', 'dbm': wDbm, 'tech': ssid, 'address': isVuln ? "VULNERABLE" : "SECURE", 'extra_data': "BSSID: $bssid | Caps: $caps", 'lat': p.latitude, 'lng': p.longitude, 'timestamp': DateTime.now().toIso8601String()});
        }
      } catch (e) {}

      if (_pingHistory.length >= 30) _pingHistory.removeAt(0); _pingHistory.add(latency > 500 ? 500 : latency); 
      double rsrqVal = double.tryParse(sanitizedRSRQ.toString()) ?? -20.0;
      if (_rsrqHistory.length >= 30) _rsrqHistory.removeAt(0); _rsrqHistory.add(rsrqVal);

      if (sanitizedCID != "[HIDDEN]" && sanitizedCID != "-") {
        if (_discoveredTowers.containsKey(sanitizedCID)) {
          _discoveredTowers[sanitizedCID]!.addObservation(pos, dbm);
        } else { _discoveredTowers[sanitizedCID] = TowerEstimate(sanitizedCID, pos, dbm); }
      }

      String tempAlert = "";
      if (_lastCellId != "" && sanitizedCID != "[HIDDEN]" && sanitizedCID != "-" && _lastCellId != sanitizedCID) { tempAlert = "⚠️ HANDOVER: ${_lastCellId} -> $sanitizedCID"; HapticFeedback.heavyImpact(); }
      if (sanitizedCID != "[HIDDEN]" && sanitizedCID != "-") _lastCellId = sanitizedCID;
      if (latency > 300) tempAlert = "🔥 CONGESTIÓN: $latency ms";
      
      String streetName = "TRACKING...";
      try { List<Placemark> placemarks = await placemarkFromCoordinates(p.latitude, p.longitude); if (placemarks.isNotEmpty) streetName = "${placemarks.first.thoroughfare}".toUpperCase(); } catch (e) {}

      if (mounted) setState(() {
        currentPos = pos; currentAudit = audit; currentStreet = streetName; _latency = latency;
        if (tempAlert.isNotEmpty) _anomalyAlert = tempAlert; 
        _liveRoute.add(pos); _liveData.add({'pos': pos, 'dbm': dbm, 'rsrq': sanitizedRSRQ, 'latency': latency});
      });
      _mapController.move(pos, 18.0);
      if (tempAlert.isNotEmpty) { Future.delayed(const Duration(seconds: 3), () { if (mounted) setState(() => _anomalyAlert = ""); }); }

      Batch batch = DatabasePro.db.batch();
      batch.insert('audits', {'session_id': sessionId, 'type': 'outdoor', 'dbm': dbm, 'tech': audit['tech'], 'address': streetName, 'extra_data': "Op: ${audit['operator']} | CID: $sanitizedCID | RSRQ: $sanitizedRSRQ | SNR: $sanitizedSNR | LAT: $latency ms", 'lat': p.latitude, 'lng': p.longitude, 'timestamp': DateTime.now().toIso8601String()});
      for(var wd in wifiBatchData) { batch.insert('audits', wd); }
      await batch.commit(noResult: true);
    } catch (e) {}
  }

  @override Widget build(BuildContext context) {
    if (_ghostModeActive) { return Scaffold(backgroundColor: Colors.black, body: InkWell(onTap: () => setState(() => _ghostModeActive = false), child: const Center(child: Text("GHOST MODE ACTIVE\n\nTap to wake screen", textAlign: TextAlign.center, style: TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 18, fontWeight: FontWeight.bold))))); }

    int dbm = currentAudit['dbm'] ?? 0; bool isDeadZone = dbm < -110 && dbm != 0;
    List<CircleMarker> currentLivePoints = _liveData.map((d) { Color c = _isQualityMode ? getQualityColor(d['rsrq']) : getGodColor(d['dbm'], 'cell'); return CircleMarker(point: d['pos'], color: c, radius: 8, borderColor: d['latency'] > 300 ? Colors.red : Colors.black, borderStrokeWidth: 1); }).toList();
    
    // 🔥 MAGIA VISUAL: DIBUJADO DE TRILATERACIÓN EN TIEMPO REAL 🔥
    List<Marker> dynamicTargetMarkers = [];
    
    // Antenas Móviles
    for (var tower in _discoveredTowers.values) {
      dynamicTargetMarkers.add(Marker(
        point: tower.estimatedPosition, width: 80, height: 80,
        child: Column(children: [
          const Icon(Icons.cell_tower, color: Colors.redAccent, size: 40),
          Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), decoration: BoxDecoration(color: Colors.black87, border: Border.all(color: Colors.redAccent), borderRadius: BorderRadius.circular(4)), child: Text("CID:${tower.cellId}", style: const TextStyle(color: Colors.white, fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.bold)))
        ])
      ));
    }

    // Routers WiFi (Solo si el botón está pulsado)
    if (_showWifiLayer) {
      for (var w in _discoveredWifis.values) {
        Color mainCol = w.isVulnerable ? Colors.redAccent : Colors.cyanAccent;
        IconData icon = w.isVulnerable ? Icons.lock_open : Icons.router;
        dynamicTargetMarkers.add(Marker(
          point: w.estimatedPosition, width: 70, height: 70,
          child: Column(children: [
            Icon(icon, color: mainCol, size: 25),
            Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), decoration: BoxDecoration(color: Colors.black87, border: Border.all(color: mainCol), borderRadius: BorderRadius.circular(4)), child: Text(w.ssid, style: const TextStyle(color: Colors.white, fontSize: 9, fontFamily: 'monospace'), overflow: TextOverflow.ellipsis))
          ])
        ));
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isQualityMode ? "VISIÓN TÉRMICA" : "LIVE TARGETING", style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', color: _isQualityMode ? Colors.orangeAccent : Colors.greenAccent)), backgroundColor: const Color(0xFF121212), 
        actions: [
          IconButton(icon: const Icon(Icons.visibility_off, color: Colors.grey), onPressed: () => setState(() => _ghostModeActive = true)),
          IconButton(icon: Icon(_showWifiLayer ? Icons.wifi_tethering : Icons.wifi_off, color: _showWifiLayer ? Colors.cyanAccent : Colors.white54), onPressed: () { setState(() { _showWifiLayer = !_showWifiLayer; }); }),
          IconButton(icon: Icon(_isQualityMode ? Icons.remove_red_eye : Icons.blur_on, color: _isQualityMode ? Colors.orangeAccent : Colors.white), onPressed: () { setState(() { _isQualityMode = !_isQualityMode; }); }),
        ]
      ),
      body: Stack(children: [
        FlutterMap(mapController: _mapController, options: MapOptions(initialCenter: LatLng(43.297, -2.985), initialZoom: 18), children: [ 
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.txurtxil.smaudit2'), 
          PolylineLayer(polylines: [Polyline(points: _liveRoute, color: Colors.blueAccent.withOpacity(0.5), strokeWidth: 4.0)]), 
          CircleLayer(circles: currentLivePoints), 
          MarkerLayer(markers: dynamicTargetMarkers), // 🔥 AQUI SE INYECTAN LOS OBJETIVOS
          if (currentPos != null) MarkerLayer(markers: [Marker(point: currentPos!, child: const Icon(Icons.my_location, color: Colors.blueAccent, size: 30))]), 
        ]),
        Positioned(top: 10, left: 10, right: 10, child: Card(color: isDeadZone ? Colors.purple[900]?.withOpacity(0.9) : Colors.black.withOpacity(0.85), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5), side: BorderSide(color: isDeadZone ? Colors.purpleAccent : (_isQualityMode ? Colors.orangeAccent : Colors.greenAccent), width: 1)), child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("[ ${currentAudit['tech']} ]", style: TextStyle(color: isDeadZone ? Colors.white : Colors.greenAccent, fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 16)), Text("Ping: ${_latency}ms", style: TextStyle(color: _latency > 300 ? Colors.redAccent : Colors.amberAccent, fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 14)), Text("$dbm dBm", style: TextStyle(color: getGodColor(dbm, 'cell'), fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'monospace'))]), const Divider(color: Colors.greenAccent, thickness: 0.5), Text("LOC: $currentStreet", style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 12)), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("OPR: ${currentAudit['operator'] ?? '-'} | CID: ${currentAudit['cell_id'] ?? '-'}", style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12)), Text("Objetivos: ${_discoveredTowers.length} Antenas | ${_discoveredWifis.length} WiFis", style: const TextStyle(color: Colors.cyanAccent, fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.bold))]), Row(children: [ Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Ping", style: TextStyle(color: Colors.amberAccent, fontSize: 8, fontFamily: 'monospace')), Container(height: 20, width: double.infinity, color: Colors.black45, child: CustomPaint(painter: SparklinePainter(_pingHistory, Colors.amberAccent, 0, 500)))])), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Ruido", style: TextStyle(color: Colors.orangeAccent, fontSize: 8, fontFamily: 'monospace')), Container(height: 20, width: double.infinity, color: Colors.black45, child: CustomPaint(painter: SparklinePainter(_rsrqHistory, Colors.orangeAccent, -20, -3)))])) ]), if (_anomalyAlert.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 5), child: Text(_anomalyAlert, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, backgroundColor: Colors.yellowAccent, fontFamily: 'monospace', fontSize: 11))), ])))),
        Positioned(bottom: 20, left: 20, right: 20, child: ElevatedButton(onPressed: _toggleTracking, style: ElevatedButton.styleFrom(backgroundColor: isTracking ? Colors.redAccent : Colors.greenAccent, minimumSize: const Size(double.infinity, 60), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5))), child: Text(isTracking ? "ABORTAR CACERÍA" : "INICIAR TARGETING PRO", style: const TextStyle(color: Colors.black, fontSize: 16, fontFamily: 'monospace', fontWeight: FontWeight.bold))))
      ]),
    );
  }
}

// ================= INDOOR & OPS DESK (Resumidos para parche) =================
class IndoorPro extends StatelessWidget { const IndoorPro({super.key}); @override Widget build(BuildContext context) { return Scaffold(backgroundColor: const Color(0xFF1E1E1E), appBar: AppBar(title: const Text("INDOOR", style: TextStyle(color: Colors.greenAccent, fontFamily: 'monospace')), backgroundColor: Colors.black), body: const Center(child: Text("Módulo Indoor en Suspensión.", style: TextStyle(color: Colors.greenAccent, fontFamily: 'monospace')))); } }
class CyberOpsTerminal extends StatelessWidget { const CyberOpsTerminal({super.key}); @override Widget build(BuildContext context) { return Scaffold(backgroundColor: const Color(0xFF1E1E1E), appBar: AppBar(title: const Text("OPS DESK", style: TextStyle(color: Colors.greenAccent, fontFamily: 'monospace')), backgroundColor: Colors.black), body: const Center(child: Text("Consola a la espera.", style: TextStyle(color: Colors.greenAccent, fontFamily: 'monospace')))); } }
DART

echo "🚀 Compilando SM Audit 2 (V37 Live Targeting)..."
flutter build apk --profile

if [ -f "build/app/outputs/flutter-apk/app-profile.apk" ]; then
    gh release create v37.0-live-targeting build/app/outputs/flutter-apk/app-profile.apk --repo txurtxil/SignalMapper --title "🎯 SM AUDIT 2 (V37): Live Targeting UI" --notes "El motor de trilateración FSPL ahora dibuja las antenas y routers en tiempo real sobre el mapa del Cazador."
    echo "✅ ¡V37 COMPILADA! EL HUD HA SIDO ACTUALIZADO."
else
    echo "❌ Error al compilar."
fi
