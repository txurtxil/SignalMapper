# SignalMapper 📡

Mapeador de cobertura de senal movil para Android. Dos modos:
**Indoor** (toca un plano para registrar RSSI por punto) y
**Outdoor** (wardriving con GPS real, mapa OSM, estimacion de antenas,
zonas muertas y exportacion). Incluye auditoria de red, terminal de
operaciones y base de datos local SQLite.

## Estado

- **Nativa (canon):** `app_nativa/` — Flutter. Codigo curado **V43**,
  la ultima iteracion estable del ciclo de desarrollo 2026.
  `flutter build apk --release` compila directo; el workflow de CI
  construye la version Flet (ver abajo).
- **Flet (prototipo):** `app/` + `main.py` — version temprana usada
  para validar UI/BD. Sensor simulado (RSS aleatorio) y geoloc por IP.
  Se mantiene como referencia y es lo que compila el CI actual.

> Decision pendiente (ver ROADMAP): unificar en la nativa y retirar
> el prototipo Flet, o mantener ambas.

## Estructura

```
app_nativa/            App Flutter (CANON)
  lib/main.dart        V43: PermissionGate, OutdoorPro (GPS+OSM+antenas),
                       IndoorPro (plano interactivo), CyberOpsTerminal
  android/...          Manifest con permisos de localizacion, wifi,
                       foreground service y notificaciones
  pubspec.yaml         Deps: geolocator, flutter_map, sqflite, wifi_scan...
app/                   Prototipo Flet (python)
  main_app.py          Nav indoor/outdoor/historial + i18n es/en
  ui/                  indoor_view, outdoor_view, history_view
  services/            database.py (SQLite), sensors.py, logger.py
  localization/        strings.py (es/en)
  models/ utils/       (reservados)
main.py                Launcher Flet
assets/plano_real.jpg  Plano usado por el modo indoor (Flet)
assets/exports/        Ejemplo de exportacion CSV
.github/workflows/     CI: build APK Flet
```

## Desarrollo

Requisitos: Flutter 3.24+ (stable), Python 3.11+ (solo prototipo).

```bash
# App nativa (canon)
cd app_nativa
flutter pub get
flutter build apk --release

# Prototipo Flet (escritorio)
pip install -r requirements.txt
python main.py

# Build APK Flet (mismo comando que el CI)
flet build apk --permissions location --clear-cache
```

## Historial / versionado

Ciclo 2026 (abril-junio): desarrollo iterativo por scripts de
inyeccion (`signal_vN_*.sh`, no incluidos en el canon). El codigo
vivo se consolido en **v43-syntax-fixed**. Todo el historial
completo sigue disponible en el git log.

## Licencia

Ver [LICENSE](LICENSE) (GPL).
