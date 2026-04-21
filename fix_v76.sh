#!/bin/bash
cd /workspaces/SignalMapper/app_nativa

echo "🔧 1/3 Re-parcheando Namespace de Telephony..."
# Forzamos que la ruta sea la correcta para este Codespace
TELEPHONY_GRADLE="/home/codespace/.pub-cache/hosted/pub.dev/telephony-0.2.0/android/build.gradle"
if [ -f "$TELEPHONY_GRADLE" ]; then
    sed -i '/namespace "/d' "$TELEPHONY_GRADLE"
    sed -i '/android {/a \    namespace "com.shounakmulay.telephony"' "$TELEPHONY_GRADLE"
    echo "✅ Parche aplicado con éxito."
fi

echo "📝 2/3 Inyectando código compatible (Polling Manual)..."
cat << 'DART' > lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:telephony/telephony.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const MaterialApp(home: SignalMapperReal(), debugShowCheckedModeBanner: false));

class SignalMapperReal extends StatefulWidget {
  const SignalMapperReal({super.key});
  @override
  State<SignalMapperReal> createState() => _SignalMapperRealState();
}

class _SignalMapperRealState extends State<SignalMapperReal> {
  final Telephony telephony = Telephony.instance;
  LatLng? currentPos;
  int currentDbm = -100;
  final List<CircleMarker> _points = [];
  bool isTracking = false;
  Timer? timer;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _requestPerms();
  }

  void _requestPerms() async {
    await [Permission.location, Permission.phone].request();
  }

  void _toggleTracking() {
    setState(() {
      isTracking = !isTracking;
      if (isTracking) {
        // Pedimos datos cada 5 segundos
        timer = Timer.periodic(const Duration(seconds: 5), (t) => _recordData());
      } else {
        timer?.cancel();
      }
    });
  }

  Future<void> _recordData() async {
    try {
      // 1. Obtener señal (Telephony v0.2.0 usa getter manual)
      List<SignalStrength> strengths = await telephony.signalStrengths;
      int dbm = -100;
      
      if (strengths.isNotEmpty) {
        var s = strengths.first;
        // Prioridad: 4G (lteRsrp) -> GSM (convertido de ASU)
        dbm = s.lteRsrp ?? (s.gsmSignalStrength != null ? (2 * s.gsmSignalStrength! - 113) : -100);
      }

      // 2. Obtener GPS
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
    if (dbm >= -80) return Colors.green;        // Excelente
    if (dbm >= -95) return Colors.yellow[700]!; // Media
    if (dbm >= -105) return Colors.orange[800]!; // Mala
    return Colors.red[900]!;                    // Sombra
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isTracking ? "Señal: $currentDbm dBm" : "SignalMapper v7.6"),
        backgroundColor: isTracking ? Colors.green[800] : Colors.indigo,
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
              label: Text(isTracking ? "DETENER" : "INICIAR RASTREO"),
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

echo "🚀 3/3 Compilando v7.6 (La definitiva)..."
flutter build apk --release --no-pub

if [ -f "build/app/outputs/flutter-apk/app-release.apk" ]; then
    gh release create v7.6-final build/app/outputs/flutter-apk/app-release.apk --repo txurtxil/SignalMapper --title "🚀 SignalMapper V7.6 (Polling Real)" --notes "Código ajustado a la API real de Telephony 0.2.0."
    echo "===================================================="
    echo "✅ ¡POR FIN! Descarga el APK funcional en GitHub."
    echo "URL: https://github.com/txurtxil/SignalMapper/releases/latest"
    echo "===================================================="
else
    echo "❌ Fallo en el build. Revisa los logs."
fi
