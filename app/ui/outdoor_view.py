import flet as ft
import urllib.request
import json
import ssl
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

        def iniciar_escaneo(e):
            status.value = "🌐 Conectando a servidores de red..."
            status.color = "orange"
            page.update()

            def task_ip():
                try:
                    ctx = ssl.create_default_context()
                    ctx.check_hostname = False
                    ctx.verify_mode = ssl.CERT_NONE
                    
                    headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'}
                    lat, lon = None, None
                    
                    # 🔥 TRIPLE MOTOR DE TRIANGULACIÓN (Anti-Cuelgues) 🔥
                    try:
                        # Intento 1: IPAPI (El mejor para Bizkaia)
                        req = urllib.request.Request("https://ipapi.co/json/", headers=headers)
                        with urllib.request.urlopen(req, timeout=3, context=ctx) as r:
                            data = json.loads(r.read().decode())
                            lat, lon = str(data['latitude']), str(data['longitude'])
                    except:
                        try:
                            # Intento 2: FreeIPAPI (Respaldo rápido)
                            req = urllib.request.Request("https://freeipapi.com/api/json", headers=headers)
                            with urllib.request.urlopen(req, timeout=3, context=ctx) as r:
                                data = json.loads(r.read().decode())
                                lat, lon = str(data['latitude']), str(data['longitude'])
                        except:
                            # Intento 3: IPINFO (El clásico)
                            req = urllib.request.Request("https://ipinfo.io/json", headers=headers)
                            with urllib.request.urlopen(req, timeout=3, context=ctx) as r:
                                data = json.loads(r.read().decode())
                                lat, lon = data['loc'].split(',')

                    # 1. Guardar en BD
                    rssi = sensors.get_wifi_signal()
                    database.add_scan("Outdoor (Red IP)", f"{lat[:7]},{lon[:7]}", rssi)
                    
                    # 2. Generar Mapa ArcGIS con Zoom x3
                    lat_f, lon_f = float(lat), float(lon)
                    offset = 0.0015 
                    bbox = f"{lon_f-offset},{lat_f-offset},{lon_f+offset},{lat_f+offset}"
                    url_mapa = f"https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/export?bbox={bbox}&bboxSR=4326&imageSR=4326&size=320,300&f=image"
                    
                    # 3. Actualizar Pantalla (Flet lo maneja seguro desde este hilo)
                    map_img.src = url_mapa
                    status.value = f"✅ Ubicación: {lat[:7]}, {lon[:7]}\n💾 Guardado"
                    status.color = "green"
                    page.update()
                    
                except Exception as ex:
                    status.value = f"❌ Error de Red: Revisa tu conexión"
                    status.color = "red"
                    page.update()

            # Lanzamos el hilo puro de Python (sin chocar con Flet)
            threading.Thread(target=task_ip, daemon=True).start()

        return ft.Column([
            ft.Text("Mapeo Outdoor", size=24, weight="bold", color="green"),
            ft.ElevatedButton("ESCANEAR UBICACIÓN", icon="gps_fixed", on_click=iniciar_escaneo, bgcolor="blue", color="white"),
            status,
            ft.Container(content=map_stack, border=ft.border.all(2, "grey"), border_radius=10)
        ], horizontal_alignment="center", spacing=15)

    except Exception as e:
        return ft.Text(f"Fallo grave: {str(e)}", color="red")
