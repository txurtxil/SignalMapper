import flet as ft
import urllib.request
import json
import threading
import ssl
import traceback
from app.services import database, sensors

def get_outdoor_content(page: ft.Page, lang: str):
    # Creamos un contenedor vacío para el error
    error_container = ft.Column()

    try:
        # 1. ELEMENTOS DE LA PANTALLA
        status = ft.Text("Listo para escanear", color="grey")
        
        # Imagen del mapa
        map_img = ft.Image(
            src="https://dummyimage.com/320x300/263238/ffffff.png&text=Pulsa+Boton", 
            width=320, 
            height=300, 
            border_radius=10
        )
        
        # Pin rojo flotante
        pin_icon = ft.Container(
            content=ft.Icon("location_on", color="red", size=45),
            alignment=ft.alignment.center,
            width=320,
            height=300,
            visible=False
        )

        map_stack = ft.Stack(
            controls=[map_img, pin_icon],
            width=320,
            height=300
        )

        # 2. FUNCIÓN DE UBICACIÓN
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
                    
                    # Intentamos obtener IP
                    with urllib.request.urlopen("http://ip-api.com/json/", timeout=5, context=ctx) as r:
                        data = json.loads(r.read().decode())
                        lat, lon = str(data['lat']), str(data['lon'])
                        
                    # Guardar en base de datos
                    rssi = sensors.get_wifi_signal()
                    database.add_scan("Outdoor", f"{lat[:7]},{lon[:7]}", rssi)
                    
                    # Cargar mapa de ArcGIS
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

        # 3. CONSTRUCCIÓN DE LA VISTA
        return ft.Column([
            ft.Text("Mapeo Outdoor", size=24, weight="bold", color="green"),
            ft.ElevatedButton("ESCANEAR RED/IP", icon="wifi", on_click=ubicar, bgcolor="blue", color="white"),
            status,
            ft.Container(content=map_stack, border=ft.border.all(2, "white"), border_radius=10)
        ], horizontal_alignment="center", spacing=15)

    except Exception as e:
        # SI ALGO FALLA AL ABRIR, MOSTRAR EL ERROR EN PANTALLA
        return ft.Column([
            ft.Text("Fallo al cargar Outdoor", size=20, color="red"),
            ft.Text(f"Error: {str(e)}", color="orange"),
            ft.Text(traceback.format_exc(), size=10, color="grey")
        ])

