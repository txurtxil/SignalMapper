import flet as ft
import urllib.request
import json
import threading
import ssl
import base64
from app.services import database, sensors

def get_outdoor_content(page: ft.Page, lang: str):
    status = ft.Text("Listo", color="grey")
    map_img = ft.Image(src="https://dummyimage.com/320x300/263238/ffffff.png&text=Pulsa+Boton", width=320, height=300, border_radius=10)

    def ubicar(e):
        status.value = "⏳ Triangulando y generando mapa..."
        status.color = "orange"
        page.update()
        
        def task():
            try:
                # 1. Bypass SSL para que Python pueda navegar
                ctx = ssl.create_default_context()
                ctx.check_hostname = False
                ctx.verify_mode = ssl.CERT_NONE
                
                # 2. Sacamos las coordenadas de la Red
                with urllib.request.urlopen("https://ipinfo.io/json", timeout=7, context=ctx) as r:
                    data = json.loads(r.read().decode())
                    lat, lon = data['loc'].split(',')
                    
                rssi = sensors.get_wifi_signal()
                database.add_scan("Outdoor", f"{lat[:7]},{lon[:7]}", rssi)
                
                # 3. EL CABALLO DE TROYA: Descargamos el mapa en Python
                url_mapa = f"https://staticmap.openstreetmap.de/staticmap.php?center={lat},{lon}&zoom=16&size=320x300&markers={lat},{lon},red"
                
                # Nos hacemos pasar por Firefox para que el servidor no nos bloquee
                req = urllib.request.Request(url_mapa, headers={'User-Agent': 'Mozilla/5.0'})
                
                try:
                    with urllib.request.urlopen(req, timeout=10, context=ctx) as response:
                        img_data = response.read()
                        # Convertimos la imagen a texto puro
                        img_b64 = base64.b64encode(img_data).decode('utf-8')
                        map_img.src = None # Quitamos la url directa
                        map_img.src_base64 = img_b64 # Le inyectamos los píxeles a la fuerza
                except Exception as e_img:
                    # Si el servidor de mapas está caído, ponemos una imagen de emergencia
                    map_img.src_base64 = None
                    map_img.src = f"https://dummyimage.com/320x300/263238/4fc3f7.png&text=Red:+{lat[:7]},+{lon[:7]}"

                # 4. Actualizamos pantalla
                status.value = f"✅ OK: {lat[:7]}, {lon[:7]}\n💾 Guardado en historial"
                status.color = "green"
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
