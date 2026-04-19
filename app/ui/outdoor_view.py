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
        status.value = "⏳ Triangulando (Nuevos servidores)..."
        status.color = "orange"
        page.update()
        
        def task():
            try:
                # Bypass SSL
                ctx = ssl.create_default_context()
                ctx.check_hostname = False
                ctx.verify_mode = ssl.CERT_NONE
                
                # 🔥 MEJORA 1: DOBLE MOTOR DE TRIANGULACIÓN ANTIFALLOS
                lat, lon = None, None
                try:
                    # Intento 1: Servidor principal (Ultrarrápido)
                    with urllib.request.urlopen("http://ip-api.com/json/", timeout=4, context=ctx) as r:
                        data = json.loads(r.read().decode())
                        lat, lon = str(data['lat']), str(data['lon'])
                except:
                    # Intento 2: Servidor de respaldo
                    with urllib.request.urlopen("https://ipinfo.io/json", timeout=4, context=ctx) as r:
                        data = json.loads(r.read().decode())
                        lat, lon = data['loc'].split(',')
                    
                # Guardar en base de datos
                rssi = sensors.get_wifi_signal()
                database.add_scan("Outdoor", f"{lat[:7]},{lon[:7]}", rssi)
                
                # 🔥 MEJORA 2: SERVIDOR DE MAPAS TOPOGRÁFICO ARCGIS (Irrompible)
                # Calculamos una "caja" alrededor de tu ubicación para el zoom
                lat_f = float(lat)
                lon_f = float(lon)
                bbox = f"{lon_f-0.005},{lat_f-0.005},{lon_f+0.005},{lat_f+0.005}"
                url_mapa = f"https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/export?bbox={bbox}&bboxSR=4326&imageSR=4326&size=320,300&f=image"
                
                # Inyectamos directamente la imagen URL (ArcGIS no bloquea)
                map_img.src_base64 = None 
                map_img.src = url_mapa
                
                status.value = f"✅ OK: {lat[:7]}, {lon[:7]}\n💾 Guardado en historial"
                status.color = "green"
                page.update()
                
            except Exception as ex:
                status.value = f"❌ Error de red externa. Intenta de nuevo."
                status.color = "red"
                page.update()

        threading.Thread(target=task, daemon=True).start()

    return ft.Column([
        ft.Text("Mapeo Outdoor", size=24, weight="bold", color="green"),
        ft.ElevatedButton("ESCANEAR RED/IP", icon="wifi", on_click=ubicar, bgcolor="blue", color="white"),
        status,
        ft.Container(content=map_img, border=ft.border.all(2, "white"), border_radius=10)
    ], horizontal_alignment="center", spacing=15)
