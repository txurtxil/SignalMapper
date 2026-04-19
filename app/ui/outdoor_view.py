import flet as ft
import urllib.request
import json
import threading
import ssl
from app.services import database, sensors

def get_outdoor_content(page: ft.Page, lang: str):
    status = ft.Text("Listo", color=ft.colors.GREY_400)
    map_img = ft.Image(src="https://dummyimage.com/320x300/263238/ffffff.png&text=Pulsa+Boton", width=320, height=300, border_radius=10)

    def ubicar(e):
        status.value = "⏳ Conectando..."
        page.update()
        
        def task():
            try:
                # Bypass de SSL para que Android no bloquee la conexión
                ctx = ssl.create_default_context()
                ctx.check_hostname = False
                ctx.verify_mode = ssl.CERT_NONE
                
                with urllib.request.urlopen("https://ipinfo.io/json", timeout=7, context=ctx) as r:
                    data = json.loads(r.read().decode())
                    lat, lon = data['loc'].split(',')
                    
                rssi = sensors.get_wifi_signal()
                database.add_scan("Outdoor", f"{lat[:7]},{lon[:7]}", rssi)
                
                # Actualizar UI
                status.value = f"✅ OK: {lat[:7]}, {lon[:7]}"
                status.color = ft.colors.GREEN
                map_img.src = f"https://staticmap.openstreetmap.de/staticmap.php?center={lat},{lon}&zoom=15&size=320x300&markers={lat},{lon},red"
                page.update()
            except Exception as ex:
                status.value = f"❌ Error: {str(ex)[:30]}"
                status.color = ft.colors.RED
                page.update()

        threading.Thread(target=task, daemon=True).start()

    return ft.Column([
        ft.Text("Outdoor", size=24, weight="bold", color=ft.colors.GREEN),
        ft.ElevatedButton("ESCANEAR RED/IP", icon=ft.icons.WIFI, on_click=ubicar),
        status,
        ft.Container(content=map_img, border=ft.border.all(1, "white"), border_radius=10)
    ], horizontal_alignment="center")
