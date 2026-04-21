#!/bin/bash
cd /workspaces/SignalMapper/app_nativa

echo "🤖 1/3 Inyectando Lógica de Rastreo Automático..."

cat << 'DART' > lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:phone_state/phone_state.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const MaterialApp(home: SignalMapperAuto(), debugShowCheckedModeBanner: false));

class SignalMapperAuto extends StatefulWidget {
  const SignalMapperAuto({super.key});
  @override
  State<SignalMapperAuto> createState() => _SignalMapperAutoState();
}

class _SignalMapperAutoState extends State<SignalMapperAuto> {
  LatLng? currentPos;
  PhoneStateStatus signalStatus = PhoneStateStatus.NOTHING;
  final List<CircleMarker> _points = [];
  bool isTracking = false;
  Timer? timer;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  void _checkPermissions() async {
    await [Permission.location, Permission.phone].request();
    PhoneState.stream.listen((event) {
      if (mounted) setState(() => signalStatus = event.status);
    });
  }

  // Inicia o detiene el rastreo automático
  void _toggleTracking() {
    setState(() {
      isTracking = !isTracking;
      if (isTracking) {
        // Registra un punto cada 10 segundos automáticamente
        timer = Timer.periodic(Duration(seconds: 10), (t) => _autoRecord());
      } else {
        timer?.cancel();
      }
    });
  }

  Future<void> _autoRecord() async {
    try {
      Position p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      LatLng newPos = LatLng(p.latitude, p.longitude);
      
      setState(() {
        currentPos = newPos;
        // Color dinámico según estado de red
        Color pointColor = (signalStatus != PhoneStateStatus.NOTHING) ? Colors.green : Colors.blue;
        
        _points.add(CircleMarker(
          point: newPos,
          color: pointColor.withOpacity(0.7),
          radius: 12,
          borderColor: Colors.white,
          borderStrokeWidth: 2,
        ));
      });
      
      // Mueve el mapa para seguirte
      _mapController.move(newPos, 17.0);
    } catch (e) {
      print("Error en auto-registro: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Rastreo: ${isTracking ? 'ACTIVO' : 'PAUSADO'}"),
        backgroundColor: isTracking ? Colors.green[800] : Colors.red[800],
        actions: [
          Center(child: Padding(
            padding: const EdgeInsets.only(right: 15),
            child: Text(signalStatus.name, style: TextStyle(fontWeight: FontWeight.bold)),
          ))
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LatLng(43.297, -2.985), 
              initialZoom: 16
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.signalmapper.pro'
              ),
              CircleLayer(circles: _points),
              if (currentPos != null)
                MarkerLayer(markers: [
                  Marker(
                    point: currentPos!,
                    child: Icon(Icons.my_location, color: Colors.blue, size: 30),
                  )
                ]),
            ],
          ),
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: ElevatedButton.icon(
              onPressed: _toggleTracking,
              icon: Icon(isTracking ? Icons.stop : Icons.play_arrow),
              label: Text(isTracking ? "DETENER MAPEO" : "INICIAR RASTREO AUTOMÁTICO"),
              style: ElevatedButton.styleFrom(
                backgroundColor: isTracking ? Colors.red : Colors.green,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 20),
                textStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
              ),
            ),
          ),
        ],
      ),
    );
  }
}
DART

echo "🚀 2/3 Compilando APK con Auto-Rastreo..."
flutter build apk --release --no-pub

echo "☁️ 3/3 Subiendo Versión 6.0 Automática..."
if [ -f "build/app/outputs/flutter-apk/app-release.apk" ]; then
    gh release create v6.0-auto build/app/outputs/flutter-apk/app-release.apk --repo txurtxil/SignalMapper --title "🚀 SignalMapper V6.0 (Auto-Tracking)" --notes "Rastreo automático cada 10 segundos. Movimiento de mapa corregido."
    echo "===================================================="
    echo "✅ ¡TERMINADO! Baja el APK desde tus Releases de GitHub."
    echo "===================================================="
else
    echo "❌ Error en el build."
fi
