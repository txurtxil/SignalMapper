import flet as ft
import urllib.request
import json
import threading
import ssl
import traceback
from app.services import database, sensors

def get_outdoor_content(page: ft.Page, lang: str):
    error_container = ft.Column()

    try:
        status = ft.Text("Listo para escanear", color="grey")
        
        map_img = ft.Image(
            src="https://dummyimage.com/320x300/263238/ffffff.png&text=Pulsa+Boton", 
            width=320, 
            height=300, 
            border_radius=10
        )
        
        # 🔥 SOLUCIÓN INDESTRUCTIBLE: Posición absoluta matemática 🔥
        # Centro X = (320 - 45) / 2 = 137.5
        # Centro Y = (300 - 45) / 2 = 127.5
        pin_icon = ft.Container(
            content=ft.Icon("location_on", color="red", size=45),
            left=137,
            top=127,
            visible=False
        )

        map_stack = ft.Stack(
            controls=[map_img, pin_icon],
            width=320,
            height=300
        )

        def ubicar(e):
            status.value = "⏳ Triangulando..."
            status.color = "orange"
            pin_icon.visible = False
            page.update()
            
            def task():
                try:
                    ctx = ssl.create_default_context()
                    ctx.check_hostname = False
                    ctx.verify_mode = ssl.CERT_NONE
                    
                    with urllib.request.urlopen("http://ip-api.com/json/", timeout=5, context=ctx) as r:
                        data = json.loads(r.read().decode())
                        lat, lon = str(data['lat']), str(data['lon'])
                        
                    rssi = sensors.get_wifi_signal()
                    database.add_scan("Outdoor", f"{lat[:7]},{lon[:7]}", rssi)
                    
                    lat_f, lon_f = float(lat), float(lon)
                    bbox = f"{lon_f-0.005},{lat_f-0.005},{lon_f+0.005},{lat_f+0.005}"
                    url_mapa = f"https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/export?bbox={bbox}&bboxSR=4326&imageSR=4326&size=320,300&f=image"
                    
                    map_img.src = url_mapa
                    pin_icon.visible = True
                    status.value = f"✅ OK: {lat[:7]}, {lon[:7]}"
                    status.color = "green"
                    page.update()
                    
                except Exception as ex:
                    status.value = f"❌ Error: Red lenta o bloqueada"
                    status.color = "red"
                    page.update()

            threading.Thread(target=task, daemon=True).start()

        return ft.Column([
            ft.Text("Mapeo Outdoor", size=24, weight="bold", color="green"),
            ft.ElevatedButton("ESCANEAR RED/IP", icon="wifi", on_click=ubicar, bgcolor="blue", color="white"),
            status,
            ft.Container(content=map_stack, border=ft.border.all(2, "white"), border_radius=10)
        ], horizontal_alignment="center", spacing=15)

    except Exception as e:
        return ft.Column([
            ft.Text("Fallo al cargar Outdoor", size=20, color="red"),
            ft.Text(f"Error: {str(e)}", color="orange"),
            ft.Text(traceback.format_exc(), size=10, color="grey")
        ])
