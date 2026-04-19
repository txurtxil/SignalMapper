import flet as ft
import urllib.request
import json
import threading
import ssl
import time
from app.services import database, sensors

def get_outdoor_content(page: ft.Page, lang: str):
    try:
        status = ft.Text("Listo para escanear", color="grey")
        
        map_img = ft.Image(
            src="https://dummyimage.com/320x300/263238/ffffff.png&text=Esperando...", 
            width=320, height=300, border_radius=10, fit=ft.BoxFit.COVER
        )
        
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
            status.value = "⏳ Iniciando localización..."
            status.color = "orange"
            status.update() 
            
            def task():
                lat, lon = None, None
                start_time = time.time()
                
                # 1. Intento prioritario: Geolocalización JS (Precisión)
                try:
                    js_code = """
                        navigator.geolocation.getCurrentPosition(
                            pos => JSON.stringify({lat: pos.coords.latitude, lon: pos.coords.longitude}),
                            err => JSON.stringify({code: err.code, message: err.message}),
                            { enableHighAccuracy: true, maximumAge: 0, timeout: 5000 }
                        );
                    """
                    
                    raw_result = page.run_javascript(js_code)
                    res = json.loads(raw_result) if raw_result else {}
                    
                    if 'message' in res:
                        raise Exception(f"Error GPS: {res['message']}")
                    
                    lat = str(res.get('lat'))
                    lon = str(res.get('lon'))
                    
                except Exception as gps_err:
                    print(f"GPS Falló: {gps_err}")
                    # 2. Fallback inmediato a IP si falla el GPS
                    try:
                        ctx = ssl.create_default_context()
                        ctx.check_hostname = False
                        ctx.verify_mode = ssl.CERT_NONE
                        headers = {'User-Agent': 'Mozilla/5.0'}
                        
                        req = urllib.request.Request("https://ipinfo.io/json", headers=headers)
                        with urllib.request.urlopen(req, timeout=3, context=ctx) as r:
                            data = json.loads(r.read().decode())
                            lat, lon = data['loc'].split(',')
                            status.value += "\n⚠️ Usando ubicación aproximada (IP)"
                    except Exception as ip_err:
                        status.value = f"❌ Fallo total: {str(ip_err)}"
                        status.color = "red"
                        status.update()
                        return

                # Verificación final de coordenadas
                if not lat or not lon or lat == 'None':
                    status.value = "❌ No se pudo obtener ninguna ubicación"
                    status.color = "red"
                    status.update()
                    return

                # Guardamos en la base de datos
                try:
                    rssi = sensors.get_wifi_signal()
                    database.add_scan("Outdoor", f"{lat[:7]},{lon[:7]}", rssi)
                except:
                    pass # Ignoramos errores de DB para no bloquear el mapa

                # Mapa Zoom X3
                try:
                    lat_f, lon_f = float(lat), float(lon)
                    offset = 0.0015 
                    bbox = f"{lon_f-offset},{lat_f-offset},{lon_f+offset},{lat_f+offset}"
                    url_mapa = f"https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/export?bbox={bbox}&bboxSR=4326&imageSR=4326&size=320,300&f=image"
                    
                    map_img.src = url_mapa
                    map_img.update()
                    
                    elapsed = time.time() - start_time
                    status.value = f"✅ Ubicación: {lat}, {lon}\n⏱️ Tiempo: {elapsed:.1f}s\n💾 Guardado"
                    status.color = "green"
                    status.update()
                except Exception as map_err:
                    status.value = f"❌ Error al cargar mapa: {str(map_err)}"
                    status.color = "red"
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
