#!/bin/bash
cd /workspaces/SignalMapper/app_nativa

echo "🔐 1/2 Abriendo el núcleo de Android (AndroidManifest.xml)..."
cat << 'PY' > fix_manifest.py
import re
import os

manifest_path = 'android/app/src/main/AndroidManifest.xml'
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

# Si no están los permisos, los inyectamos justo antes de <application>
if "ACCESS_FINE_LOCATION" not in content:
    content = content.replace('<application', permissions + '\n    <application')
    with open(manifest_path, 'w') as f:
        f.write(content)
    print("✅ Permisos inyectados con éxito en el núcleo de Android.")
else:
    print("⚠️ Los permisos ya estaban en el Manifest. Asegurando la compilación...")
PY
python3 fix_manifest.py

echo "🚀 2/2 Recompilando SM Audit 2 con Autorización de Hardware..."
flutter build apk --profile

if [ -f "build/app/outputs/flutter-apk/app-profile.apk" ]; then
    gh release create v36.2-core-auth build/app/outputs/flutter-apk/app-profile.apk --repo txurtxil/SignalMapper --title "🔓 SM AUDIT 2 (V36.2): Core Auth Patch" --notes "Se inyectan los permisos de hardware profundos en el AndroidManifest.xml. La app ahora sí pedirá acceso al GPS, Teléfono y WiFi al abrirse."
    echo "===================================================="
    echo "✅ ¡V36.2 COMPILADA! INSTALA Y PREPÁRATE PARA CAZAR."
    echo "===================================================="
else
    echo "❌ Error al compilar."
fi
