#!/bin/bash
cd /workspaces/SignalMapper/app_nativa

echo "🔐 1/2 Inyectando Llave Maestra en el núcleo de Android (Manifest)..."
cat << 'PY' > fix_manifest.py
import re
import os

manifest_path = 'android/app/src/main/AndroidManifest.xml'
try:
    with open(manifest_path, 'r') as f:
        content = f.read()

    permissions = """
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
    
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
    
    <uses-permission android:name="android.permission.READ_PHONE_STATE" />
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
    <uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    """

    # Si no están los permisos, los forzamos
    if "ACCESS_FINE_LOCATION" not in content:
        content = content.replace('<application', permissions + '\n    <application')
        with open(manifest_path, 'w') as f:
            f.write(content)
        print("✅ ROOT OVERRIDE: Permisos inyectados a fuego en el Manifest.")
    else:
        print("⚡ El Manifest ya estaba preparado. Procediendo a compilar...")
except Exception as e:
    print(f"Error al modificar el Manifest: {e}")
PY
python3 fix_manifest.py

echo "🚀 2/2 Recompilando SM Audit 2 (V37.1) con autorización completa..."
flutter build apk --profile

if [ -f "build/app/outputs/flutter-apk/app-profile.apk" ]; then
    gh release create v37.1-auth-override build/app/outputs/flutter-apk/app-profile.apk --repo txurtxil/SignalMapper --title "🔓 SM AUDIT 2 (V37.1): Auth Override" --notes "Parche de emergencia. Fuerza la inyección de permisos de lectura de módem y GPS en la compilación del Live Targeting."
    echo "===================================================="
    echo "✅ ¡V37.1 COMPILADA! INSTALA Y VERIFICA EL RADAR."
    echo "===================================================="
else
    echo "❌ Error al compilar."
fi
