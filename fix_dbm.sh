#!/bin/bash
cd /workspaces/SignalMapper/app_nativa

echo "📦 1/4 Descargando paquetes..."
flutter pub get

echo "🛠️ 2/4 Parcheando la librería signal_strength (Fixing Namespace)..."
# Buscamos el archivo build.gradle de la librería en la caché de Flutter
GRADLE_FILE=$(find $HOME/.pub-cache/hosted/pub.dev -name "build.gradle" | grep "signal_strength")

if [ -f "$GRADLE_FILE" ]; then
    echo "Archivo encontrado en: $GRADLE_FILE"
    # Inyectamos el namespace justo después de 'android {'
    sed -i '/android {/a \    namespace "com.example.signal_strength"' "$GRADLE_FILE"
    echo "✅ Parche aplicado con éxito."
else
    echo "❌ No se encontró el archivo de la librería. Reintentando..."
fi

echo "🧠 3/4 Inyectando código v7.1 (Estabilizado)..."
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
  final SignalStrength _signalManager = SignalStrength();
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
      List<int>? signals = await _signalManager.getSignalStrength();
      int dbm = (signals != null && signals.isNotEmpty) ? signals.first : -110;
      Position p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      LatLng pos = LatLng(p.latitude, p.longitude);

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
        title: Text(isTracking ? "Potencia: $currentDbm dBm" : "Auditor de Red Pro"),
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}
DART

echo "🚀 4/4 Compilando v7.1 Parcheada..."
flutter build apk --release --no-pub

if [ -f "build/app/outputs/flutter-apk/app-release.apk" ]; then
    gh release create v7.1-fixed build/app/outputs/flutter-apk/app-release.apk --repo txurtxil/SignalMapper --title "🚀 SignalMapper V7.1 (Fixed Patcher)" --notes "Parcheado el error de Namespace de la librería signal_strength."
    echo "===================================================="
    echo "✅ ¡LO CONSEGUIMOS! Descarga el APK parcheado en GitHub."
    echo "===================================================="
else
    echo "❌ Error en el build. Revisa los logs arriba."
fi
