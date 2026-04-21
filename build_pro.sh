#!/bin/bash
# 1. Asegurar estructura
mkdir -p app_nativa/lib app_nativa/android/app/src/main
cd app_nativa

# 2. Añadir dependencias
flutter pub add geolocator flutter_map latlong2 permission_handler telephony

# 3. Inyectar Permisos de Android
cat << 'XML' > android/app/src/main/AndroidManifest.xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.READ_PHONE_STATE" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <uses-permission android:name="android.permission.INTERNET" />
    <application android:label="SignalMapper Pro" android:icon="@mipmap/ic_launcher">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
XML

# 4. Crear el código fuente principal
cat << 'DART' > lib/main.dart
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:telephony/telephony.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const MaterialApp(home: OutdoorScreen(), debugShowCheckedModeBanner: false));

class OutdoorScreen extends StatefulWidget {
  const OutdoorScreen({super.key});
  @override
  State<OutdoorScreen> createState() => _OutdoorScreenState();
}

class _OutdoorScreenState extends State<OutdoorScreen> {
  final Telephony telephony = Telephony.instance;
  String status = "Iniciando sensores...";
  LatLng? pos;
  int currentDbm = -100;
  final List<CircleMarker> _signalPoints = [];

  @override
  void initState() {
    super.initState();
    _iniciarSensores();
  }

  Future<void> _iniciarSensores() async {
    await [Permission.phone, Permission.location].request();
    telephony.listenSignalStrength(onSignalStrengthChanged: (int dbm) {
      if (mounted) setState(() => currentDbm = dbm);
    });
    if (mounted) setState(() => status = "Listo para mapear");
  }

  Future<void> _ubicar() async {
    Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    if (mounted) setState(() => pos = LatLng(position.latitude, position.longitude));
  }

  void _registrarSenal() {
    if (pos == null) return;
    Color signalColor = (currentDbm > -70) ? Colors.green : (currentDbm > -90) ? Colors.orange : Colors.red;
    setState(() {
      _signalPoints.add(CircleMarker(point: pos!, color: signalColor.withOpacity(0.6), radius: 15));
      status = "💾 Registrado: $currentDbm dBm";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Signal 4G/5G: $currentDbm dBm")),
      body: Column(
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            ElevatedButton(onPressed: _ubicar, child: Text("Ubicar")),
            SizedBox(width: 20),
            ElevatedButton(onPressed: _registrarSenal, child: Text("Guardar Señal")),
          ]),
          Expanded(child: FlutterMap(
            options: MapOptions(initialCenter: pos ?? LatLng(43.29, -2.98), initialZoom: 17),
            children: [
              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.signalmapper.pro'),
              CircleLayer(circles: _signalPoints),
            ],
          )),
        ],
      ),
    );
  }
}
DART

# 5. Compilar
flutter build apk --release
echo "✅ APK Compilado en: app_nativa/build/app/outputs/flutter-apk/app-release.apk"
