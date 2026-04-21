#!/bin/bash
cd /workspaces/SignalMapper/app_nativa

echo "⚙️ 1/2 Reconstruyendo los cimientos (pub get)..."
flutter pub get

echo "🚀 2/2 Compilando V8 Titan..."
flutter build apk --release

if [ -f "build/app/outputs/flutter-apk/app-release.apk" ]; then
    gh release create v8.0-titan build/app/outputs/flutter-apk/app-release.apk --repo txurtxil/SignalMapper --title "🔥 SignalMapper V8 Titan" --notes "Fusión total. Arreglado OSM. Mapeo Indoor WiFi táctil + BD."
    echo "===================================================="
    echo "✅ ¡AHORA SÍ! La Super App está lista."
    echo "Descarga: https://github.com/txurtxil/SignalMapper/releases/latest"
    echo "===================================================="
else
    echo "❌ Fallo en compilación."
fi
