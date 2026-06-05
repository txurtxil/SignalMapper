#!/bin/bash
cd /workspaces/SignalMapper/app_nativa

echo "🛠️ 1/2 Resolviendo colisión de nombres (Path) y preparando V29.1..."
cat << 'DART' > lib/main.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_map/flutter_map.dart';
// 🔥 AQUÍ ESTÁ EL ARREGLO: Escondemos el 'Path' geográfico para usar el 'Path' de dibujo 🔥
import 'package:latlong2/latlong.dart' hide Path;
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_selector/file_selector.dart' as fs;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabasePro.init();
  runApp(const MaterialApp(home: PowerProNavigation(), debugShowCheckedModeBanner: false, themeMode: ThemeMode.dark));
}

// ================= BBDD FORENSE Y KML 3D =================
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
    String csv = "ID,Sesion,Tipo,DBM,Tecnologia,Extra,Lat,Lng,X,Y,Direccion,Fecha\n";
    for(var row in data) {
      csv += "${row['id']},${row['session_id']},${row['type']},${row['dbm']},${row['tech']},\"${row['extra_data']}\",${row['lat'] ?? ''},${row['lng'] ?? ''},${row['x'] ?? ''},${row['y'] ?? ''},\"${row['address']}\",${row['timestamp']}\n";
    }
    final directory = await getApplicationDocumentsDirectory();
    final path = p.join(directory.path, "Audit2_${type}_$sessionId.csv");
    await File(path).writeAsString(csv);
    return path;
  }

  static Future<String> exportSessionKML(String sessionId) async {
    final data = await db.query('audits', where: 'session_id = ? AND type = "outdoor"', orderBy: 'timestamp ASC');
    String kml = '<?xml version="1.0" encoding="UTF-8"?>\n<kml xmlns="http://www.opengis.net/kml/2.2">\n<Document>\n<name>Ruta 3D SM Audit</name>\n';
    kml += '<Placemark><name>Trayectoria</name><LineString><coordinates>\n';
    for(var row in data) { kml += '${row['lng']},${row['lat']},0 '; }
    kml += '\n</coordinates></LineString></Placemark>\n';
    
    for(var row in data) {
      int dbm = row['dbm'] as int;
      int alt = (140 + dbm) * 6; 
      if (alt < 0) alt = 10;
      kml += '<Placemark><name>${row['dbm']} dBm</name><description>${row['tech']} | ${row['extra_data']}</description><Point><extrude>1</extrude><altitudeMode>relativeToGround</altitudeMode><coordinates>${row['lng']},${row['lat']},$alt</coordinates></Point></Placemark>\n';
    }
    kml += '</Document>\n</kml>';
    final directory = await getApplicationDocumentsDirectory();
    final path = p.join(directory.path, "Audit2_3D_$sessionId.kml");
    await File(path).writeAsString(kml);
    return path;
  }
}

// ================= UTILIDADES DE VISIÓN =================
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

Color getQualityColor(dynamic rsrqVal) {
  if (rsrqVal == null || rsrqVal.toString() == '[HIDDEN]' || rsrqVal.toString() == '-') return Colors.grey;
  double r = double.tryParse(rsrqVal.toString()) ?? -20;
  if (r >= -10) return Colors.greenAccent; 
  if (r >= -15) return Colors.yellowAccent; 
  if (r >= -18) return Colors.orangeAccent; 
  return Colors.redAccent; 
}

String sanitizeRF(dynamic value) {
  if (value == null) return '-';
  String strVal = value.toString();
  if (strVal == '2147483647' || strVal == '2147483647.0') return '[HIDDEN]';
  return strVal;
}

class TowerEstimate {
  String cellId;
  int bestDbm;
  LatLng estimatedPosition;
  TowerEstimate({required this.cellId, required this.bestDbm, required this.estimatedPosition});
}

// ================= MOTOR DE OSCILOSCOPIO NATIVO =================
class SparklinePainter extends CustomPainter {
  final List<num> data;
  final Color color;
  final double minVal;
  final double maxVal;

  SparklinePainter(this.data, this.color, this.minVal, this.maxVal);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
      
    final path = Path(); // ¡Ahora sí usa el Path de dibujo nativo!
    double range = maxVal - minVal;
    if (range == 0) range = 1;
    double stepX = size.width / 29; 
    
    for (int i = 0; i < data.length; i++) {
      double normalizedY = 1 - ((data[i] - minVal) / range).clamp(0.0, 1.0);
      double x = i * stepX;
      double y = normalizedY * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ================= NAVEGACIÓN =================
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
          BottomNavigationBarItem(icon: Icon(Icons.radar), label: "Cazador 3D"),
          BottomNavigationBarItem(icon: Icon(Icons.memory), label: "Logs"),
        ],
      ),
    );
  }
}

// ================= OUTDOOR PRO (V29 CYBER-SIGHT) =================
class OutdoorPro extends StatefulWidget { const OutdoorPro({super.key}); @override State<OutdoorPro> createState() => _OutdoorProState(); }
class _OutdoorProState extends State<OutdoorPro> {
  static const platform = MethodChannel('com.signalmapper/power_pro');
  LatLng? currentPos; 
  Map<String, dynamic> currentAudit = {'dbm': 0, 'tech': 'ESPERANDO...', 'operator': '-', 'cell_id': '-', 'rsrq': 0, 'snr': 0};
  String currentStreet = "NO FIX";
  
  int _latency = 0;
  int _wifiCount = 0; 
  String _lastCellId = "";
  String _anomalyAlert = "";
  
  final List<Map<String, dynamic>> _liveData = []; 
  final List<LatLng> _liveRoute = [];
  final List<CircleMarker> _forensicPoints = []; 
  final List<LatLng> _forensicRoute = [];
  final Map<String, TowerEstimate> _discoveredTowers = {};
  
  final Map<String, LatLng> _discoveredWifis = {};
  final List<int> _pingHistory = [];
  final List<double> _rsrqHistory = [];

  bool _isQualityMode = false; 
  bool _showWifiLayer = false; 

  String sessionId = ""; bool isTracking = false; final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionStream;

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  void _toggleTracking() async { 
    if (isTracking) {
      _positionStream?.cancel();
      setState(() { isTracking = false; });
    } else {
      setState(() { 
        isTracking = true; 
        sessionId = "Audit2_${DateTime.now().millisecondsSinceEpoch}";
        _liveRoute.clear(); _liveData.clear(); 
        _discoveredTowers.clear(); _discoveredWifis.clear();
        _pingHistory.clear(); _rsrqHistory.clear();
        _wifiCount = 0; _lastCellId = ""; _anomalyAlert = "";
        currentStreet = "GPS LISTO (Motor Nativo)";
      });
      
      late LocationSettings locationSettings;
      if (Platform.isAndroid) {
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.high, distanceFilter: 2, forceLocationManager: false,
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationText: "Cazador activo: Celular + WiFi. Puedes apagar la pantalla.",
            notificationTitle: "SM Audit 2 Pro", enableWakeLock: true, notificationIcon: AndroidResource(name: 'ic_bg_service_small', defType: 'drawable'),
          ),
        );
      } else { locationSettings = const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 2); }

      _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position? position) {
        if (position != null && mounted) _recordData(position);
      });
    }
  }

  Future<void> _recordData(Position p) async {
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
      
      LatLng pos = LatLng(p.latitude, p.longitude);

      try {
        final wifiAudit = Map<String, dynamic>.from(await platform.invokeMethod('getWifiAudit'));
        int wDbm = wifiAudit['dbm'] ?? -120;
        String ssid = wifiAudit['ssid']?.toString() ?? 'Unknown';
        if (wDbm > -100 && !ssid.toLowerCase().contains('unknown') && ssid.isNotEmpty) {
          if (!_discoveredWifis.containsKey(ssid)) {
            _wifiCount++;
            _discoveredWifis[ssid] = pos; 
          }
          await DatabasePro.insertAudit({
            'session_id': sessionId, 'type': 'wifi', 'dbm': wDbm, 'tech': ssid, 'address': "Wardriving",
            'extra_data': "WIFI HUNTER", 'lat': p.latitude, 'lng': p.longitude, 'timestamp': DateTime.now().toIso8601String()
          });
        }
      } catch (e) {}

      if (_pingHistory.length >= 30) _pingHistory.removeAt(0);
      _pingHistory.add(latency > 500 ? 500 : latency); 

      double rsrqVal = double.tryParse(sanitizedRSRQ.toString()) ?? -20.0;
      if (_rsrqHistory.length >= 30) _rsrqHistory.removeAt(0);
      _rsrqHistory.add(rsrqVal);

      if (sanitizedCID != "[HIDDEN]" && sanitizedCID != "-") {
        if (_discoveredTowers.containsKey(sanitizedCID)) {
          if (dbm > _discoveredTowers[sanitizedCID]!.bestDbm) {
            _discoveredTowers[sanitizedCID]!.bestDbm = dbm;
            _discoveredTowers[sanitizedCID]!.estimatedPosition = pos; 
          }
        } else { _discoveredTowers[sanitizedCID] = TowerEstimate(cellId: sanitizedCID, bestDbm: dbm, estimatedPosition: pos); }
      }

      String tempAlert = "";
      if (_lastCellId != "" && sanitizedCID != "[HIDDEN]" && sanitizedCID != "-" && _lastCellId != sanitizedCID) {
        tempAlert = "⚠️ HANDOVER: ${_lastCellId} -> $sanitizedCID";
        HapticFeedback.heavyImpact(); 
      }
      if (sanitizedCID != "[HIDDEN]" && sanitizedCID != "-") _lastCellId = sanitizedCID;
      if (latency > 300) tempAlert = "🔥 CONGESTIÓN: $latency ms";

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
        _liveData.add({'pos': pos, 'dbm': dbm, 'rsrq': sanitizedRSRQ, 'latency': latency});
      });
      _mapController.move(pos, 17.5);
      
      if (tempAlert.isNotEmpty) {
        Future.delayed(const Duration(seconds: 3), () { if (mounted) setState(() => _anomalyAlert = ""); });
      }
    } catch (e) {}
  }

  void _showExportOptions() {
    showModalBottomSheet(context: context, backgroundColor: Colors.black87, builder: (BuildContext context) {
      return Wrap(children: [
        ListTile(
          leading: const Icon(Icons.table_chart, color: Colors.greenAccent), title: const Text('Exportar como CSV (Excel)', style: TextStyle(color: Colors.white)),
          onTap: () async {
            Navigator.pop(context);
            String p = await DatabasePro.exportSessionCSV(sessionId, "Outdoor");
            await Share.shareXFiles([XFile(p)], text: "Auditoría RF Finalizada");
          },
        ),
        ListTile(
          leading: const Icon(Icons.public, color: Colors.blueAccent), title: const Text('Exportar KML (Google Earth 3D)', style: TextStyle(color: Colors.white)),
          onTap: () async {
            Navigator.pop(context);
            String p = await DatabasePro.exportSessionKML(sessionId);
            await Share.shareXFiles([XFile(p)], text: "Mapeo 3D Google Earth");
          },
        ),
      ]);
    });
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

    List<CircleMarker> currentLivePoints = _liveData.map((d) {
      Color c = _isQualityMode ? getQualityColor(d['rsrq']) : getGodColor(d['dbm'], 'cell');
      return CircleMarker(point: d['pos'], color: c, radius: 10, borderColor: d['latency'] > 300 ? Colors.red : Colors.black, borderStrokeWidth: 2);
    }).toList();

    List<Marker> towerMarkers = _discoveredTowers.values.map((tower) {
      return Marker(
        point: tower.estimatedPosition, width: 60, height: 60,
        child: Column(children: [
          const Icon(Icons.cell_tower, color: Colors.redAccent, size: 30),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), decoration: BoxDecoration(color: Colors.black.withOpacity(0.8), borderRadius: BorderRadius.circular(4)),
            child: Text("CID:${tower.cellId}", style: const TextStyle(color: Colors.white, fontSize: 8, fontFamily: 'monospace')),
          )
        ]),
      );
    }).toList();

    List<Marker> wifiMarkers = _showWifiLayer ? _discoveredWifis.entries.map((w) {
      return Marker(
        point: w.value, width: 40, height: 40,
        child: const Icon(Icons.router, color: Colors.blueAccent, size: 20),
      );
    }).toList() : [];

    return Scaffold(
      appBar: AppBar(
        title: Text(_isQualityMode ? "VISIÓN TÉRMICA" : "CAZADOR PRO", style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', color: _isQualityMode ? Colors.orangeAccent : Colors.greenAccent)), 
        backgroundColor: const Color(0xFF121212), 
        actions: [
          IconButton(
            icon: Icon(_showWifiLayer ? Icons.wifi_tethering : Icons.wifi_off, color: _showWifiLayer ? Colors.blueAccent : Colors.white54), 
            onPressed: () { setState(() { _showWifiLayer = !_showWifiLayer; }); }, tooltip: "Radar WiFi"
          ),
          IconButton(
            icon: Icon(_isQualityMode ? Icons.remove_red_eye : Icons.blur_on, color: _isQualityMode ? Colors.orangeAccent : Colors.white), 
            onPressed: () { setState(() { _isQualityMode = !_isQualityMode; }); }, tooltip: "Visión Térmica"
          ),
          if (_forensicPoints.isNotEmpty) IconButton(icon: const Icon(Icons.layers_clear, color: Colors.redAccent), onPressed: _clearForensics),
          IconButton(icon: const Icon(Icons.manage_search, color: Colors.greenAccent), onPressed: _importForensicCSV)
        ]
      ),
      body: Stack(children: [
        FlutterMap(mapController: _mapController, options: MapOptions(initialCenter: LatLng(43.297, -2.985), initialZoom: 17), children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.txurtxil.smaudit2'),
          PolylineLayer(polylines: [Polyline(points: _forensicRoute, color: Colors.grey.withOpacity(0.5), strokeWidth: 8.0, pattern: StrokePattern.dashed(segments: [10.0, 10.0]))]),
          CircleLayer(circles: _forensicPoints),
          PolylineLayer(polylines: [Polyline(points: _liveRoute, color: Colors.blueAccent, strokeWidth: 4.0)]),
          CircleLayer(circles: currentLivePoints), 
          MarkerLayer(markers: wifiMarkers), 
          MarkerLayer(markers: towerMarkers),
          if (currentPos != null) MarkerLayer(markers: [Marker(point: currentPos!, child: const Icon(Icons.my_location, color: Colors.blueAccent, size: 30))]),
        ]),
        
        Positioned(top: 10, left: 10, right: 10, child: Card(
          color: isDeadZone ? Colors.purple[900]?.withOpacity(0.9) : Colors.black.withOpacity(0.85),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5), side: BorderSide(color: isDeadZone ? Colors.purpleAccent : (_isQualityMode ? Colors.orangeAccent : Colors.greenAccent), width: 1)),
          child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text("[ ${currentAudit['tech']} ]", style: TextStyle(color: isDeadZone ? Colors.white : Colors.greenAccent, fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 16)),
              Text("Ping: ${_latency}ms", style: TextStyle(color: _latency > 300 ? Colors.redAccent : Colors.amberAccent, fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 14)),
              Text("$dbm dBm", style: TextStyle(color: getGodColor(dbm, 'cell'), fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
            ]),
            const Divider(color: Colors.greenAccent, thickness: 0.5),
            Text("LOC: $currentStreet", style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 12)),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text("OPR: ${currentAudit['operator'] ?? '-'} | CID: ${currentAudit['cell_id'] ?? '-'}", style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12)),
              Text("WiFi's: $_wifiCount", style: const TextStyle(color: Colors.blueAccent, fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.bold)),
            ]),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text("Torres: ${_discoveredTowers.length}", style: const TextStyle(color: Colors.yellowAccent, fontFamily: 'monospace', fontSize: 12)),
              Text("RSRQ: ${currentAudit['rsrq'] ?? '-'}", style: TextStyle(color: _isQualityMode ? Colors.orangeAccent : Colors.white, fontFamily: 'monospace', fontSize: 12, fontWeight: _isQualityMode ? FontWeight.bold : FontWeight.normal)),
              Text("SNR: ${currentAudit['snr'] ?? '-'}", style: const TextStyle(color: Colors.cyanAccent, fontFamily: 'monospace', fontSize: 12)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text("Latencia (Ping)", style: TextStyle(color: Colors.amberAccent, fontSize: 8, fontFamily: 'monospace')),
                Container(height: 25, width: double.infinity, color: Colors.black45, child: CustomPaint(painter: SparklinePainter(_pingHistory, Colors.amberAccent, 0, 500))),
              ])),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text("Ruido (RSRQ)", style: TextStyle(color: Colors.orangeAccent, fontSize: 8, fontFamily: 'monospace')),
                Container(height: 25, width: double.infinity, color: Colors.black45, child: CustomPaint(painter: SparklinePainter(_rsrqHistory, Colors.orangeAccent, -20, -3))),
              ])),
            ]),
            if (isDeadZone) Padding(padding: const EdgeInsets.only(top: 5), child: const Text("WARNING: PACKET DROP EMINENT (DEAD ZONE)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, backgroundColor: Colors.red, fontFamily: 'monospace', fontSize: 11))),
            if (_anomalyAlert.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 5), child: Text(_anomalyAlert, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, backgroundColor: Colors.yellowAccent, fontFamily: 'monospace', fontSize: 11))),
          ]))
        )),

        Positioned(bottom: 20, left: 20, right: 20, child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!isTracking && _liveData.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: ElevatedButton.icon(
            onPressed: _showExportOptions, 
            icon: const Icon(Icons.download, color: Colors.black), label: const Text("EXPORTAR", style: TextStyle(color: Colors.black, fontFamily: 'monospace', fontWeight: FontWeight.bold)), 
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white, minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)))
          )),
          ElevatedButton(
            onPressed: _toggleTracking, 
            style: ElevatedButton.styleFrom(backgroundColor: isTracking ? Colors.redAccent : Colors.greenAccent, minimumSize: const Size(double.infinity, 60), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5))), 
            child: Text(isTracking ? "ABORTAR CACERÍA" : "INICIAR CAZADOR PRO", style: const TextStyle(color: Colors.black, fontSize: 16, fontFamily: 'monospace', fontWeight: FontWeight.bold))
          ),
        ]))
      ]),
    );
  }
}

// ================= INDOOR PRO & LOGS =================
class IndoorPro extends StatelessWidget { const IndoorPro({super.key}); @override Widget build(BuildContext context) { return const Scaffold(backgroundColor: Color(0xFF1E1E1E), body: Center(child: Text("INDOOR EN ESPERA PARA SM2", style: TextStyle(color: Colors.greenAccent, fontFamily: 'monospace')))); } }
class DatabaseProView extends StatelessWidget { const DatabaseProView({super.key}); @override Widget build(BuildContext context) { return const Scaffold(backgroundColor: Color(0xFF1E1E1E), body: Center(child: Text("LOGS SM2", style: TextStyle(color: Colors.greenAccent, fontFamily: 'monospace')))); } }
DART

echo "🚀 2/2 Compilando SM Audit 2 (V29.1 Fix)..."
flutter build apk --profile

if [ -f "build/app/outputs/flutter-apk/app-profile.apk" ]; then
    gh release create v29.1-cybersight-fix build/app/outputs/flutter-apk/app-profile.apk --repo txurtxil/SignalMapper --title "📊 SM AUDIT 2 (V29.1): Cyber-Sight Fix" --notes "Arreglada colisión de librerías Path. Incluye Osciloscopio HUD en tiempo real y Radar Wardriving Visual."
    echo "===================================================="
    echo "✅ ¡COMPILACIÓN LIMPIA Y PERFECTA!"
    echo "¡A disfrutar del osciloscopio en vivo!"
    echo "===================================================="
else
    echo "❌ Error al compilar."
fi
