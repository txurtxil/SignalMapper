import flet as ft
from app.services import sensors
import urllib.request
import json
import threading
import time

def get_outdoor_content(page: ft.Page, lang: str):
    # Componentes de la interfaz
    status_text = ft.Text("Estado: Esperando comando", size=14, color=ft.Colors.GREY_400)
    map_image = ft.Image(
        src="https://dummyimage.com/320x300/263238/ffffff.png&text=Mapa+en+espera", 
        width=320, height=300, fit="cover", border_radius=10
    )
    
    # El botón ahora nace con una referencia clara
    btn = ft.ElevatedButton(
        text="OBTENER UBICACIÓN REAL",
        icon=ft.Icons.GPS_FIXED,
        bgcolor=ft.Colors.BLUE_900,
        color=ft.Colors.WHITE,
    )

    def update_ui_map(lat, lon, metodo):
        try:
            status_text.value = f"✅ Ubicación por {metodo}\nLat: {lat:.4f} | Lon: {lon:.4f}"
            status_text.color = ft.Colors.GREEN
            map_image.src = f"https://staticmap.openstreetmap.de/staticmap.php?center={lat},{lon}&zoom=16&size=320x300&maptype=mapnik&markers={lat},{lon},red-pushpin"
            page.update()
        except:
            pass

    # PLAN B: Ubicación por IP (No falla si tienes datos/WiFi)
    def get_ip_location():
        try:
            status_text.value = "⚠️ GPS lento... usando red móvil"
            page.update()
            url = "https://ipinfo.io/json"
            response = urllib.request.urlopen(url, timeout=5)
            data = json.loads(response.read().decode())
            lat, lon = map(float, data['loc'].split(','))
            update_ui_map(lat, lon, "Red/IP")
        except Exception as e:
            status_text.value = f"❌ Error de conexión: {str(e)}"
            page.update()

    # GEOLOCATOR NATIVO
    geolocator = ft.Geolocator(
        on_position=lambda e: update_ui_map(e.latitude, e.longitude, "GPS Satélite"),
        on_error=lambda e: get_ip_location()
    )
    
    if geolocator not in page.overlay:
        page.overlay.append(geolocator)

    # El manejador del botón
    def handle_click(e):
        # 1. Feedback visual inmediato (Prueba de vida)
        btn.text = "CONECTANDO..."
        btn.bgcolor = ft.Colors.AMBER_900
        status_text.value = "⏳ Buscando señal GPS..."
        page.update()

        # 2. Ejecutar lógica en un hilo separado para no bloquear la app
        def task():
            try:
                # Intentar despertar el GPS real
                geolocator.request_permission()
                geolocator.get_current_position()
                
                # Darle 5 segundos de cortesía al GPS, si no, saltar a IP
                time.sleep(5)
                if "GPS Satélite" not in status_text.value:
                    get_ip_location()
            except:
                get_ip_location()
            
            # Resetear botón
            btn.text = "OBTENER UBICACIÓN REAL"
            btn.bgcolor = ft.Colors.BLUE_900
            page.update()

        threading.Thread(target=task, daemon=True).start()

    btn.on_click = handle_click

    return ft.Column([
        ft.Text("Mapeo Outdoor", size=26, weight="bold", color=ft.Colors.GREEN),
        btn,
        status_text,
        ft.Container(
            content=map_image, 
            border_radius=12, 
            border=ft.border.all(2, ft.Colors.GREY_800),
            padding=2
        )
    ], horizontal_alignment="center")
