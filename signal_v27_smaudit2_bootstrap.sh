#!/bin/bash
cd /workspaces/SignalMapper/app_nativa

echo "🧬 1/3 Clonando y mutando ADN a SM Audit 2..."
flutter pub global activate rename
export PATH="$PATH":"$HOME/.pub-cache/bin"

rename setAppName --targets android --value "SM Audit 2"
rename setBundleId --targets android --value "com.txurtxil.smaudit2"

flutter clean
flutter pub get

echo "🗼 2/3 Inyectando Motor Cazador de Torres (Tower Estimator)..."
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
    String csv = "ID,Sesion,Tipo,DBM,Tecnologia,Extra,Lat,Lng,X,Y,Direccion,Fecha\n";
    for(var row in data) {
      csv += "${row['id']},${row['session_id']},${row['type']},${row['dbm']},${row['tech']},\"${row['extra_data']}\",${row['lat'] ?? ''},${row['lng'] ?? ''},${row['x'] ?? ''},${row['y'] ?? ''},\"${row['address']}\",${row['timestamp']}\n";
    }
    final directory = await getApplicationDocumentsDirectory();
    final path = p.join(directory.path, "Audit2_${type}_$sessionId.csv");
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

// ================= CLASE PARA ESTIMACIÓN DE TORRES =================
class TowerEstimate {
  String cellId;
  int bestDbm;
  LatLng estimatedPosition;
  TowerEstimate({required this.cellId, required this.bestDbm, required this.estimatedPosition});
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
          BottomNavigationBarItem(icon: Icon(Icons.radar), label: "Cazador"),
          BottomNavigationBarItem(icon: Icon(Icons.memory), label: "Logs"),
        ],
      ),
    );
  }
}

// ================= OUTDOOR PRO (TOWER HUNTER) =================
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
  
  // DICCIONARIO DE TORRES ESTIMADAS
  final Map<String, TowerEstimate> _discoveredTowers = {};

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
        _liveRoute.clear(); _livePoints.clear(); 
        _discoveredTowers.clear(); // Limpiamos las torres de la sesión anterior
        _lastCellId = ""; _anomalyAlert = "";
        currentStreet = "GPS LISTO (Motor Nativo)";
      });
      
      late LocationSettings locationSettings;
      if (Platform.isAndroid) {
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 2,
          forceLocationManager: false,
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationText: "Cazador de Torres Activo. Puedes bloquear la pantalla.",
            notificationTitle: "SM Audit 2",
            enableWakeLock: true,
            notificationIcon: AndroidResource(name: 'ic_bg_service_small', defType: 'drawable'),
          ),
        );
      } else {
        locationSettings = const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 2);
      }

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

      // ALGORITMO CAZADOR DE TORRES
      if (sanitizedCID != "[HIDDEN]" && sanitizedCID != "-") {
        if (_discoveredTowers.containsKey(sanitizedCID)) {
          // Si ya la conocemos, comprobamos si este nuevo punto es MEJOR que el anterior
          if (dbm > _discoveredTowers[sanitizedCID]!.bestDbm) {
            _discoveredTowers[sanitizedCID]!.bestDbm = dbm;
            _discoveredTowers[sanitizedCID]!.estimatedPosition = pos; // Actualizamos la estimación al nuevo punto más cercano
          }
        } else {
          // Torre nueva descubierta, la añadimos al mapa
          _discoveredTowers[sanitizedCID] = TowerEstimate(cellId: sanitizedCID, bestDbm: dbm, estimatedPosition: pos);
        }
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

    // Generamos los marcadores de las torres descubiertas
    List<Marker> towerMarkers = _discoveredTowers.values.map((tower) {
      return Marker(
        point: tower.estimatedPosition,
        width: 60,
        height: 60,
        child: Column(
          children: [
            const Icon(Icons.cell_tower, color: Colors.redAccent, size: 30),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.8), borderRadius: BorderRadius.circular(4)),
              child: Text("CID:${tower.cellId}", style: const TextStyle(color: Colors.white, fontSize: 8, fontFamily: 'monospace')),
            )
          ],
        ),
      );
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("CAZADOR DE TORRES", style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', color: Colors.greenAccent)), 
        backgroundColor: const Color(0xFF121212), 
        actions: [
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
          CircleLayer(circles: _livePoints),
          // AÑADIMOS LAS TORRES AL MAPA (Capa superior)
          MarkerLayer(markers: towerMarkers),
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
              Text("Torres detectadas: ${_discoveredTowers.length}", style: const TextStyle(color: Colors.yellowAccent, fontFamily: 'monospace', fontSize: 12)),
              Text("SNR: ${currentAudit['snr'] ?? '-'}", style: const TextStyle(color: Colors.cyanAccent, fontFamily: 'monospace', fontSize: 12)),
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
            child: Text(isTracking ? "ABORTAR CACERÍA" : "INICIAR CAZADOR DE TORRES", style: const TextStyle(color: Colors.black, fontSize: 16, fontFamily: 'monospace', fontWeight: FontWeight.bold))
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

echo "🚀 3/3 Compilando SM Audit 2 (V27 Cazador de Torres)..."
flutter build apk --profile

if [ -f "build/app/outputs/flutter-apk/app-profile.apk" ]; then
    gh release create v27.0-smaudit2 build/app/outputs/flutter-apk/app-profile.apk --repo txurtxil/SignalMapper --title "🗼 SM AUDIT 2 (V27): Cazador de Torres" --notes "Lanzamiento de SM Audit 2. Nueva función de Triangulación Visual. Los iconos de antenas rojas se colocan dinámicamente en el mapa buscando la coordenada de mayor potencia para cada Cell ID."
    echo "===================================================="
    echo "✅ ¡SM AUDIT 2 HA NACIDO!"
    echo "Ya tienes el APK disponible en GitHub."
    echo "===================================================="
else
    echo "❌ Error al compilar."
fi
