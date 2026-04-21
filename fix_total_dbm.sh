#!/bin/bash
cd /workspaces/SignalMapper/app_nativa

echo "📦 1/4 Descargando paquetes para asegurar la caché..."
flutter pub get

echo "🔧 2/4 Aplicando cirugía a la librería signal_strength..."
# Usamos la ruta exacta que nos dio el error de sistema
TARGET_FILE="/home/codespace/.pub-cache/hosted/pub.dev/signal_strength-0.0.5/android/build.gradle"

if [ -f "$TARGET_FILE" ]; then
    # Borramos cualquier intento de parche previo y ponemos uno limpio
    sed -i '/namespace "/d' "$TARGET_FILE"
    sed -i '/android {/a \    namespace "com.example.signal_strength"' "$TARGET_FILE"
    echo "✅ Archivo parcheado en: $TARGET_FILE"
else
    echo "❌ No se encontró el archivo en la ruta estándar. Probando búsqueda profunda..."
    REAL_PATH=$(find /home/codespace/.pub-cache -name "build.gradle" | grep "signal_strength")
    if [ -n "$REAL_PATH" ]; then
        sed -i '/android {/a \    namespace "com.example.signal_strength"' "$REAL_PATH"
        echo "✅ Encontrado y parcheado en: $REAL_PATH"
    else
        echo "⚠️ Error crítico: No se encuentra la librería. ¿Has hecho flutter pub get?"
        exit 1
    fi
fi

echo "🚀 3/4 Compilando v7.2 (Sin errores de Namespace)..."
flutter build apk --release --no-pub

if [ -f "build/app/outputs/flutter-apk/app-release.apk" ]; then
    echo "📦 4/4 Subiendo a GitHub..."
    gh release create v7.2-final build/app/outputs/flutter-apk/app-release.apk --repo txurtxil/SignalMapper --title "🚀 SignalMapper V7.2 (Fix Final)" --notes "Parche de Namespace aplicado por fuerza bruta."
    echo "===================================================="
    echo "✅ ¡ESTA VEZ SÍ! Descarga el APK aquí:"
    echo "https://github.com/txurtxil/SignalMapper/releases/latest"
    echo "===================================================="
else
    echo "❌ La compilación falló de nuevo. Mira el error de arriba."
fi
