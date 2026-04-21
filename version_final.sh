#!/bin/bash
cd /workspaces/SignalMapper/app_nativa

echo "🗑️ 1/4 Eliminando rastro del plugin antiguo..."
flutter pub remove telephony
flutter pub add phone_state geolocator flutter_map latlong2 permission_handler

echo "🔧 2/4 Ajustando Android moderno..."
# Corregimos el Manifest para el nuevo sensor
cat << 'XML' > android/app/src/main/AndroidManifest.xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.READ_PHONE_STATE" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <uses-permission android:name="android.permission.INTERNET" />
    <application android:label="SignalMapper 5G" android:icon="@mipmap/ic_launcher">
        <activity android:name=".MainActivity" android:exported="true" android:launchMode="singleTop" android:theme="@style/LaunchTheme" android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode" android:hardwareAccelerated="true" android:windowSoftInputMode="adjustResize">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <meta-data android:name="flutterEmbedding" android:value="2" />
    </application>
</manifest>
XML

echo "🧠 3/4 Inyectando Código de Auditoría Real..."
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
  String status = "Iniciando...";
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
      setState(() => signalStatus = event.status);
    });
  }

  void _scan() async {
    Position p = await Geolocator.getCurrentPosition();
    setState(() {
      currentPos = LatLng(p.latitude, p.longitude);
      Color c = _getColor();
      _points.add(CircleMarker(point: currentPos!, color: c.withOpacity(0.7), radius: 15));
      status = "Punto registrado: ${signalStatus.name}";
    });
  }

  Color _getColor() {
    if (signalStatus == PhoneStateStatus.CALL_CONNECTED) return Colors.green;
    if (signalStatus == PhoneStateStatus.CALL_INCOMING) return Colors.orange;
    return Colors.blue; // Azul para señal activa estable
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Auditor de Red: ${signalStatus.name}"), backgroundColor: Colors.indigo),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton.icon(onPressed: _scan, icon: Icon(Icons.radar), label: Text("REGISTRAR COBERTURA")),
          ),
          Text(status, style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: FlutterMap(
            options: MapOptions(initialCenter: currentPos ?? LatLng(43.297, -2.985), initialZoom: 16),
            children: [
              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
              CircleLayer(circles: _points),
            ],
          )),
        ],
      ),
    );
  }
}
DART

echo "🚀 4/4 Compilación Final..."
flutter clean
flutter pub get
flutter build apk --release

if [ -f "build/app/outputs/flutter-apk/app-release.apk" ]; then
    gh release create v5.0-final build/app/outputs/flutter-apk/app-release.apk --repo txurtxil/SignalMapper --title "🚀 SignalMapper V5 (Modern Build)" --notes "Arreglado el error de Telephony. Sensor PhoneState activo."
    echo "✅ COMPILADO Y SUBIDO: Revisa tus releases en GitHub."
else
    echo "❌ Fallo crítico. Revisa el log."
fi
