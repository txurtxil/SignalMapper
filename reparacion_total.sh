#!/bin/bash
# 1. Entrar en la zona de combate
cd /workspaces/SignalMapper/app_nativa

echo "🛠️ 1/3 Reparando configuración de Android (Forzando v2)..."

# Reconstruimos el Manifest con la estructura moderna correcta
cat << 'XML' > android/app/src/main/AndroidManifest.xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.READ_PHONE_STATE" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <uses-permission android:name="android.permission.INTERNET" />
    <application
        android:label="SignalMapper Pro"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <meta-data
                android:name="io.flutter.embedding.android.NormalTheme"
                android:resource="@style/NormalTheme" />
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
</manifest>
XML

# Aseguramos que la Activity sea compatible con Flutter moderno
mkdir -p android/app/src/main/kotlin/com/example/app_nativa
cat << 'KOTLIN' > android/app/src/main/kotlin/com/example/app_nativa/MainActivity.kt
package com.example.app_nativa
import io.flutter.embedding.android.FlutterActivity
class MainActivity: FlutterActivity() {
}
KOTLIN

echo "🚀 2/3 Compilando APK Pro..."
flutter clean
flutter pub get
flutter build apk --release

echo "☁️ 3/3 Subiendo versión corregida a GitHub..."
if [ -f "build/app/outputs/flutter-apk/app-release.apk" ]; then
    gh release create v4.0-pro build/app/outputs/flutter-apk/app-release.apk --repo txurtxil/SignalMapper --title "🚀 SignalMapper Pro (Real 4G/5G)" --notes "Versión con sensor de telefonía real y fix de embedding."
    echo "===================================================="
    echo "✅ ¡HECHO! Descárgalo en: https://github.com/txurtxil/SignalMapper/releases"
    echo "===================================================="
else
    echo "❌ El build ha vuelto a fallar. El plugin 'telephony' es demasiado viejo para este Flutter."
fi
