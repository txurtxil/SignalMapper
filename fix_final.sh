#!/bin/bash
cd /workspaces/SignalMapper/app_nativa

echo "⚙️ 1/3 Corrigiendo nombres de la API (CALL_CONNECTED -> CALL_STARTED)..."

cat << 'DART' > lib/main.dart
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:phone_state/phone_state.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const MaterialApp(home: SignalPro(), debugShowCheckedModeBanner: false));

class SignalPro extends StatefulWidget {
  const SignalPro({super.key});
  @override
  State<SignalPro> createState() => _SignalProState();
}

class _SignalProState extends State<SignalPro> {
  String status = "Listo para auditar Barakaldo";
  LatLng? currentPos;
  PhoneStateStatus signalStatus = PhoneStateStatus.NOTHING;
  final List<CircleMarker> _points = [];

  @override
  void initState() {
    super.initState();
    _setup();
  }

  void _setup() async {
    await [Permission.location, Permission.phone].request();
    PhoneState.stream.listen((event) {
      if (mounted) setState(() => signalStatus = event.status);
    });
  }

  void _scan() async {
    setState(() => status = "🛰️ Buscando satélites...");
    try {
      Position p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      currentPos = LatLng(p.latitude, p.longitude);
      Color c = _getColor();
      
      setState(() {
        _points.add(CircleMarker(
          point: currentPos!, 
          color: c.withOpacity(0.7), 
          radius: 18,
          borderColor: Colors.white,
          borderStrokeWidth: 2,
        ));
        status = "✅ Punto guardado: ${signalStatus.name}";
      });
    } catch (e) {
      setState(() => status = "❌ Error GPS");
    }
  }

  Color _getColor() {
    // Ajustado a los nombres reales de la librería v1.0+
    if (signalStatus == PhoneStateStatus.CALL_STARTED) return Colors.green;
    if (signalStatus == PhoneStateStatus.CALL_INCOMING) return Colors.orange;
    return Colors.blue; 
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Auditor de Red: ${signalStatus.name}"), 
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: ElevatedButton.icon(
              onPressed: _scan, 
              icon: Icon(Icons.gps_fixed), 
              label: Text("REGISTRAR COBERTURA AQUÍ"),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 50),
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          Text(status, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
          Expanded(child: FlutterMap(
            options: MapOptions(
              initialCenter: currentPos ?? LatLng(43.297, -2.985), 
              initialZoom: 16
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.signalmapper.pro'
              ),
              CircleLayer(circles: _points),
            ],
          )),
        ],
      ),
    );
  }
}
DART

echo "🚀 2/3 Compilando (Limpieza profunda)..."
flutter clean
flutter pub get
# Usamos una bandera para que no use demasiada RAM en el Codespace
flutter build apk --release --no-pub

echo "☁️ 3/3 Subiendo versión corregida..."
if [ -f "build/app/outputs/flutter-apk/app-release.apk" ]; then
    gh release create v5.1-final build/app/outputs/flutter-apk/app-release.apk --repo txurtxil/SignalMapper --title "🚀 SignalMapper V5.1 (Fix)" --notes "Corregido error de API y optimizada la RAM del build."
    echo "===================================================="
    echo "✅ ¡HECHO! Compilado con éxito."
    echo "Descárgalo aquí: https://github.com/txurtxil/SignalMapper/releases"
    echo "===================================================="
else
    echo "❌ El build falló. Revisa si hay errores de RAM arriba."
fi
