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
            width=320, height=300, border_radius=10, fit=ft.ImageFit.COVER
        )
        
        # Emoji de chincheta ajustado milimétricamente
        pin_emoji = ft.Container(
            content=ft.Text("📍", size=45),
            left=137, 
            top=110,  
        )

        map_stack = ft.Stack(
            controls=[map_img, pin_emoji],
            width=320, height=300
        )

        def ubicar(e):
            status.value = "⏳ Conectando al radar..."
            status.color = "orange"
            status.update() 
            
            def task():
                try:
                    ctx = ssl.create_default_context()
                    ctx.check_hostname = False
                    ctx.verify_mode = ssl.CERT_NONE
                    
                    lat, lon = None, None
                    
                    # 🔥 HACK DE VELOCIDAD: El disfraz de Google Chrome 🔥
                    # Con esto el servidor nos da acceso VIP instantáneo
                    headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'}
                    
                    try:
                        req = urllib.request.Request("https://ipinfo.io/json", headers=headers)
                        with urllib.request.urlopen(req, timeout=3, context=ctx) as r:
                            data = json.loads(r.read().decode())
                            lat, lon = data['loc'].split(',')
                    except:
                        req = urllib.request.Request("https://freeipapi.com/api/json", headers=headers)
                        with urllib.request.urlopen(req, timeout=3, context=ctx) as r:
                            data = json.loads(r.read().decode())
                            lat, lon = str(data['latitude']), str(data['longitude'])
                            
                    # Guardamos en la base de datos de forma invisible
                    rssi = sensors.get_wifi_signal()
                    database.add_scan("Outdoor", f"{lat[:7]},{lon[:7]}", rssi)
                    
                    # 🔥 HACK DE ZOOM: Reducimos la caja matemática para acercar el mapa 🔥
                    lat_f, lon_f = float(lat), float(lon)
                    offset = 0.0015 # Antes era 0.005. Al hacerlo más pequeño, hacemos ZOOM IN.
                    bbox = f"{lon_f-offset},{lat_f-offset},{lon_f+offset},{lat_f+offset}"
                    url_mapa = f"https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/export?bbox={bbox}&bboxSR=4326&imageSR=4326&size=320,300&f=image"
                    
                    map_img.src = url_mapa
                    map_img.update()
                    
                    status.value = f"✅ Coordenadas: {lat[:7]}, {lon[:7]}\n💾 Guardado en historial"
                    status.color = "green"
                    status.update()
                    
                except Exception as ex:
                    status.value = f"❌ Error: Falló la red de internet"
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
