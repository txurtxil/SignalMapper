#!/bin/bash
cd /workspaces/SignalMapper/app_nativa

echo "🗑️ 1/4 Limpiando plugins conflictivos..."
flutter pub remove signal_strength
flutter pub add telephony geolocator flutter_map latlong2 permission_handler

echo "🔧 2/4 Parcheando Namespace de Telephony (Cirugía Pro)..."
# Forzamos la descarga del paquete
flutter pub get

# Buscamos el archivo build.gradle de telephony
TELEPHONY_GRADLE="/home/codespace/.pub-cache/hosted/pub.dev/telephony-0.2.0/android/build.gradle"

if [ -f "$TELEPHONY_GRADLE" ]; then
    # Eliminamos cualquier namespace previo e inyectamos el correcto
    sed -i '/namespace "/d' "$TELEPHONY_GRADLE"
    sed -i '/android {/a \    namespace "com.shounakmulay.telephony"' "$TELEPHONY_GRADLE"
    echo "✅ Parche aplicado a Telephony."
else
    echo "❌ No se encontró Telephony en la caché. Intentando búsqueda..."
    REAL_PATH=$(find /home/codespace/.pub-cache -name "build.gradle" | grep "telephony")
    if [ -n "$REAL_PATH" ]; then
        sed -i '/android {/a \    namespace "com.shounakmulay.telephony"' "$REAL_PATH"
        echo "✅ Parche aplicado en: $REAL_PATH"
    fi
fi

echo "📝 3/4 Inyectando código v7.5 (Telephony Stable)..."
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
    _init();
  }

  void _init() async {
    await [Permission.location, Permission.phone].request();
    // Escuchador de señal en tiempo real
    telephony.listenSignalStrength(
      onSignalStrengthChanged: (SignalStrength strength) {
        if (mounted) {
          // Buscamos el valor dBm en los diferentes tipos de red
          int val = -100;
          if (strength.dbm != null) val = strength.dbm!;
          setState(() => currentDbm = val);
        }
      }
    );
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
      Position p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      LatLng pos = LatLng(p.latitude, p.longitude);

      if (mounted) {
        setState(() {
          currentPos = pos;
          _points.add(CircleMarker(
            point: pos,
            color: _getSignalColor(currentDbm).withOpacity(0.7),
            radius: 18,
            borderColor: Colors.white,
            borderStrokeWidth: 2,
          ));
        });
        _mapController.move(pos, 17.0);
      }
    } catch (e) {
      debugPrint("Error GPS: $e");
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
        title: Text(isTracking ? "Señal: $currentDbm dBm" : "SignalMapper v7.5"),
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

echo "🚀 4/4 Compilando v7.5 (Barakaldo Edition)..."
flutter build apk --release --no-pub

if [ -f "build/app/outputs/flutter-apk/app-release.apk" ]; then
    gh release create v7.5-final build/app/outputs/flutter-apk/app-release.apk --repo txurtxil/SignalMapper --title "🚀 SignalMapper V7.5 (Telephony Fix)" --notes "Uso de Telephony con parche de Namespace y lectura dBm real."
    echo "===================================================="
    echo "✅ ¡ESTE ES EL BUENO! Descarga el APK en GitHub."
    echo "URL: https://github.com/txurtxil/SignalMapper/releases/latest"
    echo "===================================================="
else
    echo "❌ Error en el build. Revisa los logs arriba."
fi
