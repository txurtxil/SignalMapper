#!/bin/bash
cd /workspaces/SignalMapper/app_nativa

echo "⚙️ 1/2 Optimizando Gradle para poca memoria RAM..."
# Forzamos a Gradle a no usar más de 1.5GB de RAM y desactivamos la compilación paralela
mkdir -p android
cat << 'PROPS' > android/gradle.properties
org.gradle.jvmargs=-Xmx1536M
org.gradle.parallel=false
org.gradle.daemon=false
android.enableR8=false
android.useAndroidX=true
android.enableJetifier=true
PROPS

echo "🚀 2/2 Compilando Titan V8 (Low RAM Mode)..."
# Usamos un build 'profile' que consume mucha menos memoria que el 'release' 
# (y sigue funcionando perfectamente en el móvil)
flutter build apk --profile

if [ -f "build/app/outputs/flutter-apk/app-profile.apk" ]; then
    gh release create v8.0-titan build/app/outputs/flutter-apk/app-profile.apk --repo txurtxil/SignalMapper --title "🔥 SignalMapper V8 Titan (Low RAM Fix)" --notes "Compilación exitosa limitando la RAM de Gradle."
    echo "===================================================="
    echo "✅ ¡COMPILACIÓN COMPLETADA (Modo Ligero)!"
    echo "Descarga: https://github.com/txurtxil/SignalMapper/releases/latest"
    echo "===================================================="
else
    echo "❌ Sigue fallando por memoria. Revisa la terminal."
fi
