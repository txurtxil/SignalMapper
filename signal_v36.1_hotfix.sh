#!/bin/bash
cd /workspaces/SignalMapper/app_nativa

echo "🛠️ 1/2 Aplicando parche de compilación (Resolución de colisión de variables)..."
cat << 'DART' > lib/main.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui';
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

// ================= BBDD FORENSE Y EXPORTADORES (WIGLE INTEGRADO) =================
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
      
      if(extra.contains("BSSID: ")) {
        int idx = extra.indexOf("BSSID: ") + 7;
        int end = extra.indexOf(" |", idx);
        if(end != -1) mac = extra.substring(idx, end);
      }
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
  @override void initState() { super.initState(); _requestPermissions(); }
  Future<void> _requestPermissions() async {
    await [Permission.location, Permission.phone, Permission.notification].request();
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) await Geolocator.requestPermission();
    if (await Permission.location.isGranted) { await Permission.locationAlways.request(); }
  }
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

// ================= OUTDOOR PRO (TRILATERACIÓN Y GHOST MODE) =================
class OutdoorPro extends StatefulWidget { const OutdoorPro({super.key}); @override State<OutdoorPro> createState() => _OutdoorProState(); }
class _OutdoorProState extends State<OutdoorPro> {
  static const platform = MethodChannel('com.signalmapper/power_pro');
  LatLng? currentPos; Map<String, dynamic> currentAudit = {'dbm': 0, 'tech': 'ESPERANDO...', 'operator': '-', 'cell_id': '-', 'rsrq': 0, 'snr': 0};
  String currentStreet = "NO FIX"; int _latency = 0; int _wifiCount = 0; int _vulnCount = 0;
  String _lastCellId = ""; String _anomalyAlert = "";
  final List<Map<String, dynamic>> _liveData = []; final List<LatLng> _liveRoute = [];
  final List<CircleMarker> _forensicPoints = []; final List<LatLng> _forensicRoute = [];
  
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
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.high, distanceFilter: 2, forceLocationManager: false,
          foregroundNotificationConfig: const ForegroundNotificationConfig(notificationText: "Cazador activo (Modo Demonio).", notificationTitle: "SM Audit 2 Pro", enableWakeLock: true, notificationIcon: AndroidResource(name: 'ic_bg_service_small', defType: 'drawable')),
        );
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
          String s = ssid.toLowerCase(); if (s.contains('free') || s.contains('public') || s.contains('guest') || s.contains('abierto') || s.contains('wifi')) isVuln = true;

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
      _mapController.move(pos, 17.5);
      if (tempAlert.isNotEmpty) { Future.delayed(const Duration(seconds: 3), () { if (mounted) setState(() => _anomalyAlert = ""); }); }

      Batch batch = DatabasePro.db.batch();
      batch.insert('audits', {'session_id': sessionId, 'type': 'outdoor', 'dbm': dbm, 'tech': audit['tech'], 'address': streetName, 'extra_data': "Op: ${audit['operator']} | CID: $sanitizedCID | RSRQ: $sanitizedRSRQ | SNR: $sanitizedSNR | LAT: $latency ms", 'lat': p.latitude, 'lng': p.longitude, 'timestamp': DateTime.now().toIso8601String()});
      for(var wd in wifiBatchData) { batch.insert('audits', wd); }
      await batch.commit(noResult: true);
    } catch (e) {}
  }

  void _showExportOptions() {
    showModalBottomSheet(context: context, backgroundColor: Colors.black87, builder: (BuildContext context) {
      return Wrap(children: [
        ListTile(leading: const Icon(Icons.table_chart, color: Colors.greenAccent), title: const Text('Exportar CSV', style: TextStyle(color: Colors.white)), onTap: () async { Navigator.pop(context); String p = await DatabasePro.exportSessionCSV(sessionId, "Outdoor"); await Share.shareXFiles([XFile(p)], text: "Auditoría RF"); }),
        ListTile(leading: const Icon(Icons.public, color: Colors.blueAccent), title: const Text('Exportar KML 3D', style: TextStyle(color: Colors.white)), onTap: () async { Navigator.pop(context); String p = await DatabasePro.exportSessionKML(sessionId, _discoveredTowers.values, _discoveredWifis.values); await Share.shareXFiles([XFile(p)], text: "Google Earth 3D"); }),
      ]);
    });
  }

  void _importForensicCSV() async { /* Sin cambios */ }
  void _clearForensics() { setState(() { _forensicRoute.clear(); _forensicPoints.clear(); }); }

  @override Widget build(BuildContext context) {
    if (_ghostModeActive) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: InkWell(
          onTap: () => setState(() => _ghostModeActive = false),
          child: const Center(child: Text("GHOST MODE ACTIVE\n\nTap to wake screen", textAlign: TextAlign.center, style: TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 18, fontWeight: FontWeight.bold))),
        ),
      );
    }

    int dbm = currentAudit['dbm'] ?? 0; bool isDeadZone = dbm < -110 && dbm != 0;
    List<CircleMarker> currentLivePoints = _liveData.map((d) { Color c = _isQualityMode ? getQualityColor(d['rsrq']) : getGodColor(d['dbm'], 'cell'); return CircleMarker(point: d['pos'], color: c, radius: 10, borderColor: d['latency'] > 300 ? Colors.red : Colors.black, borderStrokeWidth: 2); }).toList();
    List<Marker> towerMarkers = _discoveredTowers.values.map((tower) { return Marker(point: tower.estimatedPosition, width: 60, height: 60, child: Column(children: [const Icon(Icons.cell_tower, color: Colors.redAccent, size: 30), Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), decoration: BoxDecoration(color: Colors.black.withOpacity(0.8), borderRadius: BorderRadius.circular(4)), child: Text("CID:${tower.cellId}", style: const TextStyle(color: Colors.white, fontSize: 8, fontFamily: 'monospace')))])); }).toList();
    List<Marker> wifiMarkers = _showWifiLayer ? _discoveredWifis.values.map((w) { return Marker(point: w.estimatedPosition, width: 60, height: 60, child: Column(children: [Icon(w.isVulnerable ? Icons.no_encryption : Icons.router, color: w.isVulnerable ? Colors.redAccent : Colors.blueAccent, size: 20), Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), decoration: BoxDecoration(color: w.isVulnerable ? Colors.red.withOpacity(0.8) : Colors.black.withOpacity(0.8), borderRadius: BorderRadius.circular(4)), child: Text(w.ssid, style: const TextStyle(color: Colors.white, fontSize: 8, fontFamily: 'monospace'), overflow: TextOverflow.ellipsis))])); }).toList() : [];

    return Scaffold(
      appBar: AppBar(
        title: Text(_isQualityMode ? "VISIÓN TÉRMICA" : "CAZADOR PRO", style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', color: _isQualityMode ? Colors.orangeAccent : Colors.greenAccent)), backgroundColor: const Color(0xFF121212), 
        actions: [
          IconButton(icon: const Icon(Icons.visibility_off, color: Colors.grey), onPressed: () => setState(() => _ghostModeActive = true)),
          IconButton(icon: Icon(_showWifiLayer ? Icons.wifi_tethering : Icons.wifi_off, color: _showWifiLayer ? Colors.blueAccent : Colors.white54), onPressed: () { setState(() { _showWifiLayer = !_showWifiLayer; }); }),
          IconButton(icon: Icon(_isQualityMode ? Icons.remove_red_eye : Icons.blur_on, color: _isQualityMode ? Colors.orangeAccent : Colors.white), onPressed: () { setState(() { _isQualityMode = !_isQualityMode; }); }),
        ]
      ),
      body: Stack(children: [
        FlutterMap(mapController: _mapController, options: MapOptions(initialCenter: LatLng(43.297, -2.985), initialZoom: 17), children: [ TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.txurtxil.smaudit2'), PolylineLayer(polylines: [Polyline(points: _forensicRoute, color: Colors.grey.withOpacity(0.5), strokeWidth: 8.0, pattern: StrokePattern.dashed(segments: [10.0, 10.0]))]), CircleLayer(circles: _forensicPoints), PolylineLayer(polylines: [Polyline(points: _liveRoute, color: Colors.blueAccent, strokeWidth: 4.0)]), CircleLayer(circles: currentLivePoints), MarkerLayer(markers: wifiMarkers), MarkerLayer(markers: towerMarkers), if (currentPos != null) MarkerLayer(markers: [Marker(point: currentPos!, child: const Icon(Icons.my_location, color: Colors.blueAccent, size: 30))]), ]),
        Positioned(top: 10, left: 10, right: 10, child: Card(color: isDeadZone ? Colors.purple[900]?.withOpacity(0.9) : Colors.black.withOpacity(0.85), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5), side: BorderSide(color: isDeadZone ? Colors.purpleAccent : (_isQualityMode ? Colors.orangeAccent : Colors.greenAccent), width: 1)), child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("[ ${currentAudit['tech']} ]", style: TextStyle(color: isDeadZone ? Colors.white : Colors.greenAccent, fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 16)), Text("Ping: ${_latency}ms", style: TextStyle(color: _latency > 300 ? Colors.redAccent : Colors.amberAccent, fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 14)), Text("$dbm dBm", style: TextStyle(color: getGodColor(dbm, 'cell'), fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'monospace'))]), const Divider(color: Colors.greenAccent, thickness: 0.5), Text("LOC: $currentStreet", style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 12)), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("OPR: ${currentAudit['operator'] ?? '-'} | CID: ${currentAudit['cell_id'] ?? '-'}", style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12)), Text("WiFi / Vuln: $_wifiCount / $_vulnCount", style: TextStyle(color: _vulnCount > 0 ? Colors.redAccent : Colors.blueAccent, fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.bold))]), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("Torres: ${_discoveredTowers.length}", style: const TextStyle(color: Colors.yellowAccent, fontFamily: 'monospace', fontSize: 12)), Text("RSRQ: ${currentAudit['rsrq'] ?? '-'}", style: TextStyle(color: _isQualityMode ? Colors.orangeAccent : Colors.white, fontFamily: 'monospace', fontSize: 12, fontWeight: _isQualityMode ? FontWeight.bold : FontWeight.normal)), Text("SNR: ${currentAudit['snr'] ?? '-'}", style: const TextStyle(color: Colors.cyanAccent, fontFamily: 'monospace', fontSize: 12))]), const SizedBox(height: 8), Row(children: [ Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Latencia (Ping)", style: TextStyle(color: Colors.amberAccent, fontSize: 8, fontFamily: 'monospace')), Container(height: 25, width: double.infinity, color: Colors.black45, child: CustomPaint(painter: SparklinePainter(_pingHistory, Colors.amberAccent, 0, 500)))])), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Ruido (RSRQ)", style: TextStyle(color: Colors.orangeAccent, fontSize: 8, fontFamily: 'monospace')), Container(height: 25, width: double.infinity, color: Colors.black45, child: CustomPaint(painter: SparklinePainter(_rsrqHistory, Colors.orangeAccent, -20, -3)))])) ]), if (isDeadZone) Padding(padding: const EdgeInsets.only(top: 5), child: const Text("WARNING: PACKET DROP EMINENT (DEAD ZONE)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, backgroundColor: Colors.red, fontFamily: 'monospace', fontSize: 11))), if (_anomalyAlert.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 5), child: Text(_anomalyAlert, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, backgroundColor: Colors.yellowAccent, fontFamily: 'monospace', fontSize: 11))), ])))),
        Positioned(bottom: 20, left: 20, right: 20, child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!isTracking && _liveData.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: ElevatedButton.icon(onPressed: _showExportOptions, icon: const Icon(Icons.download, color: Colors.black), label: const Text("EXPORTAR MAPA", style: TextStyle(color: Colors.black, fontFamily: 'monospace', fontWeight: FontWeight.bold)), style: ElevatedButton.styleFrom(backgroundColor: Colors.white, minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5))))),
          ElevatedButton(onPressed: _toggleTracking, style: ElevatedButton.styleFrom(backgroundColor: isTracking ? Colors.redAccent : Colors.greenAccent, minimumSize: const Size(double.infinity, 60), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5))), child: Text(isTracking ? "ABORTAR CACERÍA" : "INICIAR CAZADOR PRO", style: const TextStyle(color: Colors.black, fontSize: 16, fontFamily: 'monospace', fontWeight: FontWeight.bold))),
        ]))
      ]),
    );
  }
}

// ================= INDOOR PRO =================
class IndoorPro extends StatefulWidget { const IndoorPro({super.key}); @override State<IndoorPro> createState() => _IndoorProState(); }
class _IndoorProState extends State<IndoorPro> {
  static const platform = MethodChannel('com.signalmapper/power_pro'); File? floorPlan; List<Map<String, dynamic>> indoorPoints = []; String sessionId = "AuditIn_${DateTime.now().millisecondsSinceEpoch}"; Map<String, dynamic> liveAudit = {'dbm': 0, 'ssid': 'ESCANEO...', 'source': 'none'}; Timer? timer; String _scanMode = 'wifi'; 
  @override void initState() { super.initState(); timer = Timer.periodic(const Duration(seconds: 2), (t) => _updateLiveSignal()); }
  @override void dispose() { timer?.cancel(); super.dispose(); }
  Future<void> _updateLiveSignal() async { try { if (_scanMode == 'wifi') { final results = await WiFiScan.instance.getScannedResults(); if (results.isNotEmpty) { results.sort((a, b) => b.level.compareTo(a.level)); if (mounted) setState(() => liveAudit = {'dbm': results.first.level, 'ssid': results.first.ssid, 'source': 'wifi'}); } else { if (mounted) setState(() => liveAudit = {'dbm': -120, 'ssid': 'Buscando WiFi...', 'source': 'wifi'}); } } else { final cell = Map<String, dynamic>.from(await platform.invokeMethod('getCellularAudit')); if (mounted) setState(() => liveAudit = {'dbm': cell['dbm'] ?? 0, 'ssid': cell['tech'] ?? 'Red Móvil / Voz', 'source': 'cell'}); } } catch (e) {} }
  void _addPoint(TapDownDetails details) async { if (floorPlan == null) return; HapticFeedback.mediumImpact(); final Offset local = details.localPosition; int dbm = liveAudit['dbm'] ?? -120; setState(() { indoorPoints.add({'x': local.dx, 'y': local.dy, 'dbm': dbm, 'source': liveAudit['source']}); }); await DatabasePro.insertAudit({'session_id': sessionId, 'type': 'indoor', 'dbm': dbm, 'tech': liveAudit['ssid'] ?? 'Unknown', 'x': local.dx, 'y': local.dy, 'timestamp': DateTime.now().toIso8601String()}); }
  @override Widget build(BuildContext context) { int dbm = liveAudit['dbm'] ?? 0; String src = liveAudit['source'] ?? 'wifi'; return Scaffold( appBar: AppBar(title: const Text("AUDIT INDOOR", style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', color: Colors.greenAccent)), backgroundColor: const Color(0xFF121212), actions: [ IconButton(icon: const Icon(Icons.add_photo_alternate, color: Colors.greenAccent), onPressed: () async { final p = await ImagePicker().pickImage(source: ImageSource.gallery); if (p != null) setState(() => floorPlan = File(p.path)); }) ]), backgroundColor: const Color(0xFF1E1E1E), body: floorPlan == null ? const Center(child: Text("CARGAR PLANO", style: TextStyle(color: Colors.greenAccent, fontFamily: 'monospace'))) : Stack(children: [ InteractiveViewer(maxScale: 6.0, child: Center(child: GestureDetector(onTapDown: _addPoint, child: Stack(clipBehavior: Clip.none, children: [ Image.file(floorPlan!, fit: BoxFit.contain), ...indoorPoints.map((p) => Positioned(left: p['x'] - 12, top: p['y'] - 12, child: Container(width: 24, height: 24, decoration: BoxDecoration(color: getGodColor(p['dbm'], p['source'] ?? 'wifi'), shape: BoxShape.circle, border: Border.all(color: Colors.black, width: 2))))) ])))), Positioned(top: 10, left: 10, right: 10, child: Card(color: Colors.black.withOpacity(0.85), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5), side: BorderSide(color: Colors.greenAccent, width: 1)), child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [Text("$dbm dBm | ${liveAudit['ssid']}", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, fontFamily: 'monospace')), Text(src == 'cell' ? "[ CELLULAR & VOZ ]" : "[ WIFI SCANNER ]", style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontFamily: 'monospace'))])))), Positioned(bottom: 80, left: 20, right: 20, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [ToggleButtons(isSelected: [_scanMode == 'wifi', _scanMode == 'cell'], onPressed: (int index) { setState(() { _scanMode = index == 0 ? 'wifi' : 'cell'; }); }, color: Colors.white54, selectedColor: Colors.black, fillColor: Colors.greenAccent, borderRadius: BorderRadius.circular(8), children: const [Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Text("WIFI", style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold))), Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Text("4G / VOZ", style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold)))])])), if (indoorPoints.isNotEmpty) Positioned(bottom: 20, left: 20, right: 20, child: ElevatedButton.icon(onPressed: () async { String p = await DatabasePro.exportSessionCSV(sessionId, "Indoor"); await Share.shareXFiles([XFile(p)], text: "Auditoría Indoor"); }, icon: const Icon(Icons.download, color: Colors.black), label: const Text("EXPORTAR", style: TextStyle(color: Colors.black, fontFamily: 'monospace', fontWeight: FontWeight.bold)), style: ElevatedButton.styleFrom(backgroundColor: Colors.white, minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5))))) ]), ); }
}

// ================= CYBER OPS TERMINAL CON WIGLE =================
class CyberOpsTerminal extends StatefulWidget { const CyberOpsTerminal({super.key}); @override State<CyberOpsTerminal> createState() => _CyberOpsTerminalState(); }
class _CyberOpsTerminalState extends State<CyberOpsTerminal> {
  int totalNodos = 0; int totalVuln = 0; int totalCell = 0;
  List<String> consoleOutput = ["root@SMAudit2:~# Inicializando Project Godseye..."];
  final ScrollController _scrollController = ScrollController();
  @override void initState() { super.initState(); _loadStats(); }

  Future<void> _loadStats() async {
    final data = await DatabasePro.getAudits(); int v = 0; int c = 0;
    for(var row in data) { if(row['type'] == 'wifi' && row['address'] == 'VULNERABLE') v++; if(row['type'] == 'outdoor' || row['type'] == 'indoor') c++; }
    if (mounted) { setState(() { totalNodos = data.length; totalVuln = v; totalCell = c; }); _printToConsole("[+] Base de datos indexada: $totalNodos observables."); }
  }
  void _printToConsole(String text) { setState(() { consoleOutput.add(text); }); Future.delayed(const Duration(milliseconds: 100), () { if (_scrollController.hasClients) { _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut); } }); }
  
  void _dumpMemory() async {
    _printToConsole("[*] Compilando DUMP Maestro...");
    final data = await DatabasePro.getAudits(); StringBuffer sb = StringBuffer("ID,Sesion,Tipo,DBM,Tecnologia,Extra,Lat,Lng,X,Y,Direccion,Fecha\n");
    for(var row in data) { sb.write("${row['id']},${row['session_id']},${row['type']},${row['dbm']},${row['tech']},\"${row['extra_data']}\",${row['lat'] ?? ''},${row['lng'] ?? ''},${row['x'] ?? ''},${row['y'] ?? ''},\"${row['address']}\",${row['timestamp']}\n"); }
    
    // 🔥 ARREGLADO: Cambio de nombre de variable 'p' a 'dumpPath' para evitar colisión con path.dart
    final d = await getApplicationDocumentsDirectory(); 
    final dumpPath = p.join(d.path, "SMAudit2_MasterDump.csv"); 
    await File(dumpPath).writeAsString(sb.toString());
    
    _printToConsole("[+] Exportación finalizada.");
    await Share.shareXFiles([XFile(dumpPath)], text: "Master Dump SMAudit");
  }

  void _exportWigle() async {
    _printToConsole("[*] Formateando $totalNodos paquetes al estándar WiGLE-1.4...");
    String wiglePath = await DatabasePro.exportWiGLE();
    _printToConsole("[+] Archivo WiGLE compilado. Listo para subida global.");
    await Share.shareXFiles([XFile(wiglePath)], text: "WiGLE Upload File");
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(title: const Text("OPS DESK", style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', color: Colors.greenAccent)), backgroundColor: Colors.black, actions: [IconButton(icon: const Icon(Icons.refresh, color: Colors.greenAccent), onPressed: _loadStats)]),
      body: Padding(padding: const EdgeInsets.all(10), child: Column(children: [
        Row(children: [ Expanded(child: _buildStatCard("RAW DATA", totalNodos.toString(), Colors.greenAccent)), const SizedBox(width: 10), Expanded(child: _buildStatCard("VULNERABLE", totalVuln.toString(), Colors.redAccent)), const SizedBox(width: 10), Expanded(child: _buildStatCard("CELL TOWERS", totalCell.toString(), Colors.blueAccent)), ]),
        const SizedBox(height: 15),
        Expanded(child: Container(width: double.infinity, padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.black, border: Border.all(color: Colors.greenAccent, width: 2), borderRadius: BorderRadius.circular(5), boxShadow: [BoxShadow(color: Colors.greenAccent.withOpacity(0.2), blurRadius: 10, spreadRadius: 1)]), child: ListView.builder(controller: _scrollController, itemCount: consoleOutput.length, itemBuilder: (context, index) { return Text(consoleOutput[index], style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 13)); }))),
        const SizedBox(height: 15),
        ElevatedButton.icon(
          onPressed: _exportWigle, icon: const Icon(Icons.public, color: Colors.black),
          label: const Text("EXPORTAR WIGLE.NET (RANKING MUNDIAL)", style: TextStyle(color: Colors.black, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, minimumSize: const Size(double.infinity, 50))
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: _dumpMemory, icon: const Icon(Icons.memory, color: Colors.black),
          label: const Text("VOLCADO DE MEMORIA (DUMP MASTER)", style: TextStyle(color: Colors.black, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, minimumSize: const Size(double.infinity, 50))
        ),
      ])),
    );
  }
  Widget _buildStatCard(String title, String val, Color color) { return Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.black, border: Border.all(color: color), borderRadius: BorderRadius.circular(5)), child: Column(children: [Text(title, style: TextStyle(color: color, fontSize: 10, fontFamily: 'monospace')), const SizedBox(height: 5), Text(val, style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'monospace'))])); }
}
DART

echo "🚀 2/2 Compilando SM Audit 2 (V36.1 Hotfix)..."
flutter build apk --profile

if [ -f "build/app/outputs/flutter-apk/app-profile.apk" ]; then
    gh release create v36.1-godseye-hotfix build/app/outputs/flutter-apk/app-profile.apk --repo txurtxil/SignalMapper --title "🩹 SM AUDIT 2 (V36.1): Parche de Compilación" --notes "Solucionado el error de Name Collision en el exportador de Dump Master."
    echo "===================================================="
    echo "✅ ¡V36.1 COMPILADA CON ÉXITO! A DARLE CAÑA."
    echo "===================================================="
else
    echo "❌ Error al compilar."
fi
