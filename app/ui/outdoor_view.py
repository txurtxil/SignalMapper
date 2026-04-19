import flet as ft
import urllib.request
import json
import threading
import ssl
from app.services import database, sensors

def get_outdoor_content(page: ft.Page, lang: str):
    try:
        status = ft.Text("Listo para escanear", color="grey")
        
        # Corrección: Usar ft.BoxFit en lugar de ft.ImageFit
        map_img = ft.Image(
            src="https://dummyimage.com/320x300/263238/ffffff.png&text=Esperando...", 
            width=320, height=300, border_radius=10, fit=ft.BoxFit.COVER
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
            status.value = "⏳ Solicitando ubicación precisa..."
            status.color = "orange"
            status.update() 
            
            def task():
                lat, lon = None, None
                
                # Intentamos primero con Geolocalización JS (Precisión)
                try:
                    js_code = """
                        navigator.geolocation.getCurrentPosition(
                            pos => JSON.stringify({lat: pos.coords.latitude, lon: pos.coords.longitude}),
                            err => JSON.stringify({error: err.message}),
                            { enableHighAccuracy: true, maximumAge: 0, timeout: 10000 }
                        );
                    """
                    raw_result = page.run_javascript(js_code)
                    res = json.loads(raw_result)
                    
                    if 'error' in res:
                        raise Exception(f"GPS Error: {res['error']}")
                    
                    lat = str(res['lat'])
                    lon = str(res['lon'])
                except Exception:
                    # Respaldo: Si falla el GPS, usamos IP
                    try:
                        ctx = ssl.create_default_context()
                        ctx.check_hostname = False
                        ctx.verify_mode = ssl.CERT_NONE
                        headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x6)'}
                        
                        req = urllib.request.Request("https://ipinfo.io/json", headers=headers)
                        with urllib.request.urlopen(req, timeout=3, context=ctx) as r:
                            data = json.loads(r.read().decode())
                            lat, lon = data['loc'].split(',')
                    except:
                        status.value = "❌ No se pudo obtener ubicación"
                        status.color = "red"
                        status.update()
                        return

                if not lat or not lon:
                    status.value = "❌ Ubicación no disponible"
                    status.color = "red"
                    status.update()
                    return

                # Guardamos en la base de datos
                rssi = sensors.get_wifi_signal()
                database.add_scan("Outdoor", f"{lat[:7]},{lon[:7]}", rssi)
                
                # Mapa Zoom X3
                lat_f, lon_f = float(lat), float(lon)
                offset = 0.0015 
                bbox = f"{lon_f-offset},{lat_f-offset},{lon_f+offset},{lat_f+offset}"
                url_mapa = f"https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/export?bbox={bbox}&bboxSR=4326&imageSR=4326&size=320,300&f=image"
                
                map_img.src = url_mapa
                map_img.update()
                
                status.value = f"✅ Coordenadas: {lat}, {lon}\n💾 Guardado"
                status.color = "green"
                status.update()

            threading.Thread(target=task, daemon=True).start()

        return ft.Column([
            ft.Text("Mapeo Outdoor (Precisión)", size=24, weight="bold", color="green"),
            ft.ElevatedButton("ESCANEAR UBICACIÓN EXACTA", icon="wifi", on_click=ubicar, bgcolor="blue", color="white"),
            status,
            ft.Container(content=map_stack, border=ft.border.all(2, "grey"), border_radius=10)
        ], horizontal_alignment="center", spacing=15)

    except Exception as e:
        return ft.Text(f"Fallo grave: {str(e)}", color="red")
