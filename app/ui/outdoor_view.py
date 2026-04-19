import flet as ft
import urllib.request
import json
import threading
import ssl
from app.services import database, sensors

def get_outdoor_content(page: ft.Page, lang: str):
    status = ft.Text("Listo", color="grey")
    map_img = ft.Image(src="https://dummyimage.com/320x300/263238/ffffff.png&text=Pulsa+Boton", width=320, height=300, border_radius=10)

    def ubicar(e):
        status.value = "⏳ Conectando..."
        page.update()
        
        def task():
            try:
                # Bypass de seguridad SSL para Android
                ctx = ssl.create_default_context()
                ctx.check_hostname = False
                ctx.verify_mode = ssl.CERT_NONE
                
                with urllib.request.urlopen("https://ipinfo.io/json", timeout=7, context=ctx) as r:
                    data = json.loads(r.read().decode())
                    lat, lon = data['loc'].split(',')
                    
                rssi = sensors.get_wifi_signal()
                database.add_scan("Outdoor", f"{lat[:7]},{lon[:7]}", rssi)
                
                # Actualizar pantalla con el mapa real
                status.value = f"✅ OK: {lat[:7]}, {lon[:7]}"
                status.color = "green"
                map_img.src = f"https://staticmap.openstreetmap.de/staticmap.php?center={lat},{lon}&zoom=16&size=320x300&markers={lat},{lon},red"
                page.update()
            except Exception as ex:
                status.value = f"❌ Error: {str(ex)[:30]}"
                status.color = "red"
                page.update()

        threading.Thread(target=task, daemon=True).start()

    return ft.Column([
        ft.Text("Mapeo Outdoor", size=24, weight="bold", color="green"),
        ft.ElevatedButton("ESCANEAR RED/IP", icon="wifi", on_click=ubicar, bgcolor="blue", color="white"),
        status,
        ft.Container(content=map_img, border=ft.border.all(2, "white"), border_radius=10)
    ], horizontal_alignment="center", spacing=15)
