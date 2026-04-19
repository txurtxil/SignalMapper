import flet as ft
import urllib.request
import json
import threading
import ssl
from app.services import database, sensors

def get_outdoor_content(page: ft.Page, lang: str):
    status = ft.Text("Listo", color="grey")
    map_img = ft.Image(src="https://dummyimage.com/320x300/263238/ffffff.png&text=Pulsa+Boton", width=320, height=300, border_radius=10)
    
    # 🔥 EL HACK MAESTRO: Un pin rojo nativo flotando en el centro del mapa
    pin_icon = ft.Container(
        content=ft.Icon("location_on", color="red", size=45),
        alignment=ft.alignment.center, # Se centra automáticamente en la caja
        width=320, height=300,
        visible=False # Lo mantenemos invisible hasta que acabe el escaneo
    )

    # Superponemos la imagen del mapa y el pin
    map_stack = ft.Stack(
        controls=[map_img, pin_icon],
        width=320, height=300
    )

    def ubicar(e):
        status.value = "⏳ Triangulando (ArcGIS)..."
        status.color = "orange"
        pin_icon.visible = False # Escondemos el pin viejo
        page.update()
        
        def task():
            try:
                ctx = ssl.create_default_context()
                ctx.check_hostname = False
                ctx.verify_mode = ssl.CERT_NONE
                
                lat, lon = None, None
                try:
                    with urllib.request.urlopen("http://ip-api.com/json/", timeout=5, context=ctx) as r:
                        data = json.loads(r.read().decode())
                        lat, lon = str(data['lat']), str(data['lon'])
                except:
                    with urllib.request.urlopen("https://ipinfo.io/json", timeout=5, context=ctx) as r:
                        data = json.loads(r.read().decode())
                        lat, lon = data['loc'].split(',')
                    
                rssi = sensors.get_wifi_signal()
                database.add_scan("Outdoor", f"{lat[:7]},{lon[:7]}", rssi)
                
                # Generar mapa ArcGIS
                lat_f, lon_f = float(lat), float(lon)
                bbox = f"{lon_f-0.005},{lat_f-0.005},{lon_f+0.005},{lat_f+0.005}"
                url_mapa = f"https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/export?bbox={bbox}&bboxSR=4326&imageSR=4326&size=320,300&f=image"
                
                map_img.src = url_mapa
                pin_icon.visible = True # ¡Encendemos el pin flotante!
                
                status.value = f"✅ OK: {lat[:7]}, {lon[:7]}\n💾 Guardado en historial"
                status.color = "green"
                page.update()
                
            except Exception as ex:
                status.value = f"❌ Error: Falló la conexión"
                status.color = "red"
                page.update()

        threading.Thread(target=task, daemon=True).start()

    return ft.Column([
        ft.Text("Mapeo Outdoor", size=24, weight="bold", color="green"),
        ft.ElevatedButton("ESCANEAR RED/IP", icon="wifi", on_click=ubicar, bgcolor="blue", color="white"),
        status,
        ft.Container(content=map_stack, border=ft.border.all(2, "white"), border_radius=10)
    ], horizontal_alignment="center", spacing=15)
