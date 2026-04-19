import flet as ft
import urllib.parse
import base64
from app.services import database, sensors

# 🔥 TU CÓDIGO HTML INCRUSTADO DIRECTAMENTE 🔥
HTML_GPS = """
<!DOCTYPE html>
<html>
<head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>GPS Nativo</title>
    <style>
        body { font-family: sans-serif; text-align: center; padding: 20px; background: #1e1e1e; color: white; }
        #status { margin-top: 20px; font-size: 16px; color: #4fc3f7; }
        button { padding: 15px 30px; font-size: 16px; background: #007bff; color: white; border: none; border-radius: 8px; cursor: pointer; margin-top: 30px;}
    </style>
</head>
<body>
    <h2>📍 Radar GPS Satelital</h2>
    <p style="font-size:12px; color:grey;">(Acepta los permisos de tu navegador si los pide)</p>
    <button onclick="getLocation()">ACTIVAR ANTENA</button>
    <div id="status"></div>

    <script>
        function getLocation() {
            const status = document.getElementById('status');
            status.innerHTML = "⏳ Solicitando GPS a Android...";

            if (!navigator.geolocation) {
                status.innerHTML = "❌ Tu navegador no soporta GPS.";
                return;
            }

            navigator.geolocation.getCurrentPosition(
                function(position) {
                    const lat = position.coords.latitude;
                    const lon = position.coords.longitude;
                    status.innerHTML = "✅ Ubicación capturada.<br>Transfiriendo a SignalMapper...";
                    // 🚀 La trampa: cambiamos la URL para que Flet la intercepte
                    window.location.href = "https://flet-gps-catch.com/?lat=" + lat + "&lon=" + lon;
                },
                function(error) {
                    status.innerHTML = "❌ Error: " + error.message;
                },
                { enableHighAccuracy: true, timeout: 10000 }
            );
        }
    </script>
</body>
</html>
"""

def get_outdoor_content(page: ft.Page, lang: str):
    status = ft.Text("Listo para escanear", color="grey")
    map_img = ft.Image(src="https://dummyimage.com/320x300/263238/ffffff.png&text=Esperando...", width=320, height=300, border_radius=10, fit=ft.ImageFit.COVER)
    pin_emoji = ft.Container(content=ft.Text("📍", size=45), left=137, top=110)
    map_stack = ft.Stack(controls=[map_img, pin_emoji], width=320, height=300)

    # Convertimos tu HTML a Base64 para saltarnos el bloqueo de archivos locales de Android
    html_b64 = base64.b64encode(HTML_GPS.encode('utf-8')).decode('utf-8')
    data_uri = f"data:text/html;base64,{html_b64}"

    # 📡 ESTE ES EL RECEPTOR DE TU TRAMPA DE URL
    def on_webview_load(e):
        url = str(e.data)
        if "flet-gps-catch.com" in url and "lat=" in url:
            parsed = urllib.parse.urlparse(url)
            params = urllib.parse.parse_qs(parsed.query)
            lat = params.get('lat', [None])[0]
            lon = params.get('lon', [None])[0]

            if lat and lon:
                # 1. Cerramos el Popup
                dialog.open = False
                
                # 2. Actualizamos la pantalla principal
                status.value = f"✅ Satélite GPS: {lat[:7]}, {lon[:7]}\n💾 Guardado"
                status.color = "green"
                page.update()

                # 3. Guardamos en el historial
                try:
                    rssi = sensors.get_wifi_signal()
                    database.add_scan("Outdoor (GPS Real)", f"{lat[:7]},{lon[:7]}", rssi)
                except:
                    pass

                # 4. Cargamos el mapa de ArcGIS
                lat_f, lon_f = float(lat), float(lon)
                offset = 0.0015
                bbox = f"{lon_f-offset},{lat_f-offset},{lon_f+offset},{lat_f+offset}"
                url_mapa = f"https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/export?bbox={bbox}&bboxSR=4326&imageSR=4326&size=320,300&f=image"
                map_img.src = url_mapa
                page.update()

    # El navegador incrustado que carga tu HTML
    gps_webview = ft.WebView(
        url=data_uri,
        width=300,
        height=350,
        on_page_started=on_webview_load
    )

    # Metemos el navegador en una ventana flotante
    dialog = ft.AlertDialog(content=gps_webview, content_padding=0)

    def abrir_gps(e):
        if dialog not in page.overlay:
            page.overlay.append(dialog)
        gps_webview.url = data_uri # Refrescar
        dialog.open = True
        page.update()

    return ft.Column([
        ft.Text("Mapeo Outdoor", size=24, weight="bold", color="green"),
        ft.ElevatedButton("ABRIR RADAR GPS", icon="gps_fixed", on_click=abrir_gps, bgcolor="blue", color="white"),
        status,
        ft.Container(content=map_stack, border=ft.border.all(2, "grey"), border_radius=10)
    ], horizontal_alignment="center", spacing=15)
