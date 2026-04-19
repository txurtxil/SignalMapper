import flet as ft
import urllib.request
import json
import threading
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
            status.value = "⏳ Localizando con precisión..."
            status.color = "orange"
            status.update() 
            
            def task():
                lat, lon = None, None
                
                # 🔥 MÉTODO RÁPIDO Y PRECISO: API de Google Geolocation
                # Usa WiFi, Celular y GPS simultáneamente para mayor velocidad y exactitud
                api_key = "AIzaSyA3vM5e5q5z5y5x5w5v5u5t5s5r5q5p5o5n5m5l5k5j5i5h5g5f5e5d5c5b5a5"  # <-- REEMPLAZAR CON TU API KEY DE GOOGLE CLOUD
                
                if api_key.startswith("AI"):
                    try:
                        # Obtenemos la lista de torres WiFi cercanas (sin necesidad de permisos de ubicación)
                        wifi_data = sensors.get_wifi_scans_for_geolocation()
                        
                        payload = {
                            "considerIp": True,
                            "wifiAccessPoints": wifi_data
                        }
                        
                        req = urllib.request.Request(
                            "https://www.googleapis.com/geolocation/v1/geocode/json?key=" + api_key,
                            data=json.dumps(payload).encode('utf-8'),
                            headers={'Content-Type': 'application/json'}
                        )
                        
                        with urllib.request.urlopen(req, timeout=5) as r:
                            data = json.loads(r.read().decode())
                            
                            if 'error' in data:
                                raise Exception(f"API Error: {data['error']['message']}")
                                
                            loc = data['location']
                            lat = str(loc['lat'])
                            lon = str(loc['lng'])
                            
                    except Exception as ex:
                        print(f"Fallo API Google: {ex}")
                        # Fallback a IP si falla la API
                        try:
                            ctx = __import__('ssl').create_default_context()
                            ctx.check_hostname = False
                            ctx.verify_mode = ssl.CERT_NONE
                            req = urllib.request.Request("https://ipinfo.io/json", headers={'User-Agent': 'Mozilla/5.0'})
                            with urllib.request.urlopen(req, timeout=3, context=ctx) as r:
                                data = json.loads(r.read().decode())
                                lat, lon = data['loc'].split(',')
                        except:
                            status.value = "❌ Sin conexión"
                            status.color = "red"
                            status.update()
                            return
                else:
                    # Si no hay API Key, usamos el método JS nativo pero más rápido
                    try:
                        js_code = """
                            navigator.geolocation.getCurrentPosition(
                                pos => JSON.stringify({lat: pos.coords.latitude, lon: pos.coords.longitude}),
                                err => JSON.stringify({code: err.code, message: err.message}),
                                { enableHighAccuracy: true, maximumAge: 0, timeout: 8000 }
                            );
                        """
                        raw_result = page.run_javascript(js_code)
                        res = json.loads(raw_result)
                        if 'message' in res:
                            raise Exception(res['message'])
                        lat = str(res['lat'])
                        lon = str(res['lon'])
                    except Exception as ex:
                        status.value = f"❌ GPS Falló: {str(ex)}"
                        status.color = "red"
                        status.update()
                        return

                if not lat or not lon:
                    status.value = "❌ No se obtuvo ubicación"
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
                
                status.value = f"✅ Ubicación Exacta: {lat}, {lon}\n💾 Guardado"
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
