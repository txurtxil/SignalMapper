#!/bin/bash
cd /workspaces/SignalMapper/app_nativa

echo "⚙️ 1/2 Limpiando configuración de Gradle (Fuera enableR8)..."
cat << 'PROPS' > android/gradle.properties
org.gradle.jvmargs=-Xmx1536M
org.gradle.parallel=false
org.gradle.daemon=false
android.useAndroidX=true
android.enableJetifier=true
PROPS

echo "🚀 2/2 Compilando Titan V8 (Ahora sí, sin bloqueos)..."
flutter build apk --profile

if [ -f "build/app/outputs/flutter-apk/app-profile.apk" ]; then
    gh release create v8.1-titan build/app/outputs/flutter-apk/app-profile.apk --repo txurtxil/SignalMapper --title "🔥 SignalMapper V8.1 Titan" --notes "Fusión total. Arreglado OSM. Mapeo Indoor táctil + BBDD. Gradle optimizado."
    echo "===================================================="
    echo "✅ ¡COMPILACIÓN COMPLETADA CON ÉXITO!"
    echo "Descárgalo aquí: https://github.com/txurtxil/SignalMapper/releases/latest"
    echo "===================================================="
else
    echo "❌ Revisa la terminal, a ver qué se queja ahora."
fi
