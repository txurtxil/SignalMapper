import re
import os

manifest_path = 'android/app/src/main/AndroidManifest.xml'
try:
    with open(manifest_path, 'r') as f:
        content = f.read()

    queries_block = """
    <queries>
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="https" />
        </intent>
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="geo" />
        </intent>
    </queries>
    """

    if "<queries>" not in content:
        content = content.replace('<application', queries_block + '\n    <application')
        with open(manifest_path, 'w') as f:
            f.write(content)
        print("✅ Enrutador de Apps instalado en el núcleo.")
    else:
        print("⚡ El Enrutador ya estaba instalado.")
except Exception as e:
    print(f"Error al modificar el Manifest: {e}")
