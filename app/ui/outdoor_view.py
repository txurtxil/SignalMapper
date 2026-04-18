import flet as ft
from app.services import sensors
import urllib.request
import json
import threading
import time

def get_outdoor_content(page: ft.Page, lang: str):
    # Elementos visuales
    status_text = ft.Text("Estado: Esperando pulsación", size=14, color=ft.Colors.GREY_400)
    map_image = ft.Image(
        src="https://dummyimage.com/320x300/263238/ffffff.png&text=Mapa+en+espera", 
        width=320, height=300, fit="cover", border_radius=10
    )
    btn = ft.ElevatedButton(
        "OBTENER UBICACIÓN (GPS/RED)", 
        icon=ft.Icons.LOCATION_ON, 
        bgcolor=ft.Colors.BLUE_900, 
        color=ft.Colors.WHITE
    )

    def draw_map(lat, lon, fuente):
        try:
            status_text.value = f"✅ Encontrado por {fuente}\nLat: {lat:.4f} | Lon: {lon:.4f}"
            status_text.color = ft.Colors.GREEN
            map_image.src = f"https://staticmap.openstreetmap.de/staticmap.php?center={lat},{lon}&zoom=17&size=320x300&maptype=mapnik&markers={lat},{lon},red-pushpin"
            page.update()
        except:
            pass

    # FUNCIÓN FALLBACK (RED/IP) - Esta es la que salva la app si el GPS falla
    def use_ip_location():
        try:
            status_text.value = "⚠️ GPS lento. Usando Red Móvil..."
            page.update()
            req = urllib.request.Request("https://ipinfo.io/json", headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req, timeout=4) as response:
                data = json.loads(response.read().decode())
                lat, lon = map(float, data['loc'].split(','))
                draw_map(lat, lon, "Red")
        except Exception as e:
            status_text.value = f"❌ Error de conexión: {str(e)}"
            page.update()

    # GEOLOCATOR NATIVO
    geolocator = ft.Geolocator(
        on_position=lambda e: draw_map(e.latitude, e.longitude, "Satélite"),
        on_error=lambda e: use_ip_location()
    )
    if geolocator not in page.overlay:
        page.overlay.append(geolocator)

    def on_click_handler(e):
        # 1. Feedback visual inmediato (Si esto no cambia, el problema es el evento on_click)
        btn.text = "PROCESANDO..."
        btn.bgcolor = ft.Colors.AMBER_900
        status_text.value = "⏳ Iniciando búsqueda..."
        page.update()

        # 2. Ejecutar búsqueda en un hilo separado para no congelar el botón
        def search_process():
            try:
                # Intentamos GPS real
                geolocator.request_permission()
                geolocator.get_current_position()
                
                # Esperamos 4 segundos al satélite, si no hay respuesta, usamos IP
                time.sleep(4)
                if "Satélite" not in status_text.value:
                    use_ip_location()
            except:
                use_ip_location()
            
            # Restaurar botón
            btn.text = "OBTENER UBICACIÓN (GPS/RED)"
            btn.bgcolor = ft.Colors.BLUE_900
            page.update()

        threading.Thread(target=search_process, daemon=True).start()

    btn.on_click = on_click_handler

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
