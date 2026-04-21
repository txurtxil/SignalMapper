#!/bin/bash
cd /workspaces/SignalMapper/app_nativa

echo "🛠️ 1/3 Aplicando parche de seguridad..."
TARGET_FILE="/home/codespace/.pub-cache/hosted/pub.dev/signal_strength-0.0.5/android/build.gradle"
if [ -f "$TARGET_FILE" ]; then
    sed -i '/namespace "/d' "$TARGET_FILE"
    sed -i '/android {/a \    namespace "com.example.signal_strength"' "$TARGET_FILE"
fi

echo "📝 2/3 Corrigiendo API (Static Getter: getSignalStrength)..."
cat << 'DART' > lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:signal_strength/signal_strength.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const MaterialApp(home: SignalMapperReal(), debugShowCheckedModeBanner: false));

class SignalMapperReal extends StatefulWidget {
  const SignalMapperReal({super.key});
  @override
  State<SignalMapperReal> createState() => _SignalMapperRealState();
}

class _SignalMapperRealState extends State<SignalMapperReal> {
  LatLng? currentPos;
  int currentDbm = -110;
  final List<CircleMarker> _points = [];
  bool isTracking = false;
  Timer? timer;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() async {
    await [Permission.location, Permission.phone].request();
  }

  void _toggleTracking() {
    setState(() {
      isTracking = !isTracking;
      if (isTracking) {
        timer = Timer.periodic(const Duration(seconds: 5), (t) => _recordData());
      } else {
        timer?.cancel();
      }
    });
  }

  Future<void> _recordData() async {
    try {
      // API v0.0.5: Es un GETTER ESTÁTICO (Sin paréntesis y directo de la clase)
      List<int>? signals = await SignalStrength.getSignalStrength;
      int dbm = (signals != null && signals.isNotEmpty) ? signals.first : -110;
      
      Position p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      LatLng pos = LatLng(p.latitude, p.longitude);

      if (mounted) {
        setState(() {
          currentPos = pos;
          currentDbm = dbm;
          _points.add(CircleMarker(
            point: pos,
            color: _getSignalColor(dbm).withOpacity(0.7),
            radius: 18,
            borderColor: Colors.white,
            borderStrokeWidth: 2,
          ));
        });
        _mapController.move(pos, 17.0);
      }
    } catch (e) {
      debugPrint("Error: $e");
    }
  }

  Color _getSignalColor(int dbm) {
    if (dbm >= -80) return Colors.green;
    if (dbm >= -95) return Colors.yellow[700]!;
    if (dbm >= -105) return Colors.orange[800]!;
    return Colors.red[900]!;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isTracking ? "Potencia: $currentDbm dBm" : "SignalMapper v7.4"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: LatLng(43.297, -2.985), initialZoom: 16),
            children: [
              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
              CircleLayer(circles: _points),
              if (currentPos != null)
                MarkerLayer(markers: [
                  Marker(point: currentPos!, child: const Icon(Icons.my_location, color: Colors.blue, size: 35)),
                ]),
            ],
          ),
          Positioned(
            bottom: 30, left: 20, right: 20,
            child: ElevatedButton.icon(
              onPressed: _toggleTracking,
              icon: Icon(isTracking ? Icons.stop : Icons.play_arrow),
              label: Text(isTracking ? "DETENER" : "INICIAR MAPA DE CALOR"),
              style: ElevatedButton.styleFrom(
                backgroundColor: isTracking ? Colors.red : Colors.indigo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 20),
                textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
              ),
            ),
          ),
        ],
      ),
    );
  }
}
DART

echo "🚀 3/3 Compilando v7.4 (Versión Estabilizada)..."
flutter build apk --release --no-pub

if [ -f "build/app/outputs/flutter-apk/app-release.apk" ]; then
    gh release create v7.4-final build/app/outputs/flutter-apk/app-release.apk --repo txurtxil/SignalMapper --title "🚀 SignalMapper V7.4 (Fix Final)" --notes "Arreglada la API de SignalStrength y parcheado el build."
    echo "===================================================="
    echo "✅ ¡BINGO! APK listo para descargar en GitHub."
    echo "URL: https://github.com/txurtxil/SignalMapper/releases/latest"
    echo "===================================================="
else
    echo "❌ Fallo en la compilación. Revisa el log."
fi
