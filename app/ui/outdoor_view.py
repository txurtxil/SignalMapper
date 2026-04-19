import flet as ft
import urllib.request
import json
import threading
import ssl
from app.services import database, sensors

def get_outdoor_content(page: ft.Page, lang: str):
    try:
        status = ft.Text("Listo para escanear", color="grey")
        
        map_img = ft.Image(
            src="https://dummyimage.com/320x300/263238/ffffff.png&text=Esperando...", 
            width=320, height=300, border_radius=10
        )
        
        # 🔥 EL PIN INDESTRUCTIBLE: Un Emoji gigante siempre visible 🔥
        pin_emoji = ft.Container(
            content=ft.Text("📍", size=40),
            left=140, # Centrado horizontal
            top=110,  # Centrado vertical apuntando al medio
        )

        map_stack = ft.Stack(
            controls=[map_img, pin_emoji],
            width=320, height=300
        )

        def ubicar(e):
            status.value = "⏳ Conectando..."
            status.color = "orange"
            status.update() # Forzamos a la pantalla a mostrar esto YA
            
            def task():
                try:
                    ctx = ssl.create_default_context()
                    ctx.check_hostname = False
                    ctx.verify_mode = ssl.CERT_NONE
                    
                    lat, lon = None, None
                    
                    # 🚀 Intento 1: Servidor HTTPS ultrarrápido
                    try:
                        with urllib.request.urlopen("https://ipinfo.io/json", timeout=3, context=ctx) as r:
                            data = json.loads(r.read().decode())
                            lat, lon = data['loc'].split(',')
                    except:
                        # 🚀 Intento 2: Respaldo HTTPS
                        with urllib.request.urlopen("https://freeipapi.com/api/json", timeout=3, context=ctx) as r:
                            data = json.loads(r.read().decode())
                            lat, lon = str(data['latitude']), str(data['longitude'])
                            
                    # Guardamos en BD
                    rssi = sensors.get_wifi_signal()
                    database.add_scan("Outdoor", f"{lat[:7]},{lon[:7]}", rssi)
                    
                    # Generamos el mapa de Ontígola/tu zona
                    lat_f, lon_f = float(lat), float(lon)
                    bbox = f"{lon_f-0.005},{lat_f-0.005},{lon_f+0.005},{lat_f+0.005}"
                    url_mapa = f"https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/export?bbox={bbox}&bboxSR=4326&imageSR=4326&size=320,300&f=image"
                    
                    # Actualizamos cada pieza por separado para evitar cuelgues
                    map_img.src = url_mapa
                    map_img.update()
                    
                    status.value = f"✅ Coordenadas: {lat[:7]}, {lon[:7]}\n💾 Guardado en historial"
                    status.color = "green"
                    status.update()
                    
                except Exception as ex:
                    status.value = f"❌ Error: Falló la conexión de red"
                    status.color = "red"
                    status.update()

            threading.Thread(target=task, daemon=True).start()

        return ft.Column([
            ft.Text("Mapeo Outdoor", size=24, weight="bold", color="green"),
            ft.ElevatedButton("ESCANEAR RED/IP", icon="wifi", on_click=ubicar, bgcolor="blue", color="white"),
            status,
            ft.Container(content=map_stack, border=ft.border.all(2, "grey"), border_radius=10)
        ], horizontal_alignment="center", spacing=15)

    except Exception as e:
        return ft.Text(f"Fallo grave: {str(e)}", color="red")
