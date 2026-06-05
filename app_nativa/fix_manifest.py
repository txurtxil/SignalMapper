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
