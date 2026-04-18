import flet as ft
import urllib.request
import json
import threading
import time

def get_outdoor_content(page: ft.Page, lang: str):
    status_text = ft.Text("Estado: Listo", size=14, color=ft.Colors.GREY_400)
    map_image = ft.Image(
        src="https://dummyimage.com/320x300/263238/ffffff.png&text=Esperando+Ubicación",
        width=320, height=300, fit="cover", border_radius=10
    )

    # Evitamos el crash de inicialización duplicada
    if not hasattr(page, "geo_fix"):
        try:
            geo = ft.Geolocator(
                on_position=lambda e: update_map(e.latitude, e.longitude),
                on_error=lambda e: get_ip_fallback()
            )
            page.overlay.append(geo)
            page.geo_fix = geo
        except:
            page.geo_fix = None

    def update_map(lat, lon):
        status_text.value = f"✅ GPS: {lat:.4f}, {lon:.4f}"
        status_text.color = ft.Colors.GREEN
        map_image.src = f"https://staticmap.openstreetmap.de/staticmap.php?center={lat},{lon}&zoom=16&size=320x300&markers={lat},{lon},red"
        page.update()

    def get_ip_fallback():
        try:
            with urllib.request.urlopen("https://ipinfo.io/json", timeout=5) as resp:
                data = json.loads(resp.read().decode())
                lat, lon = map(float, data['loc'].split(','))
                update_map(lat, lon)
        except:
            status_text.value = "❌ Error total de ubicación"
            page.update()

    def handle_click(e):
        status_text.value = "⏳ Conectando..."
        page.update()
        if page.geo_fix:
            page.geo_fix.request_permission()
            page.geo_fix.get_current_position()
        else:
            get_ip_fallback()

    return ft.Column([
        ft.Text("Modo Outdoor", size=24, weight="bold", color=ft.Colors.GREEN),
        ft.ElevatedButton("OBTENER POSICIÓN", icon=ft.Icons.GPS_FIXED, on_click=handle_click),
        status_text,
        ft.Container(content=map_image, border_radius=10, border=ft.border.all(1, "white"))
    ], horizontal_alignment="center")
