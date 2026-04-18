import flet as ft
from app.services import sensors
import urllib.request
import json

def get_outdoor_content(page: ft.Page, lang: str):
    status_text = ft.Text("Listo para mapear", size=14, color=ft.Colors.BLUE)
    map_image = ft.Image(src="https://dummyimage.com/320x300/263238/ffffff.png&text=Pulsa+Mapear", width=320, height=300, fit="cover", border_radius=10)

    def draw_map(lat, lon, source):
        status_text.value = f"✅ Ubicación obtenida ({source})\nLat: {lat:.4f} | Lon: {lon:.4f}"
        status_text.color = ft.Colors.GREEN
        map_image.src = f"https://staticmap.openstreetmap.de/staticmap.php?center={lat},{lon}&zoom=16&size=320x300&maptype=mapnik&markers={lat},{lon},red-pushpin"
        page.update()

    # SISTEMA 1: Respaldo por IP (Infallible, no requiere permisos de Android)
    def fallback_ip_location():
        try:
            req = urllib.request.Request("https://ipinfo.io/json", headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req, timeout=5) as response:
                data = json.loads(response.read().decode())
                lat, lon = map(float, data['loc'].split(','))
                draw_map(lat, lon, "Red Móvil/WiFi")
        except Exception as e:
            status_text.value = "❌ Fallo total de red y GPS."
            page.update()

    # SISTEMA 2: Flet Native GPS (Intenta usar el satélite)
    if not any(isinstance(c, ft.Geolocator) for c in page.overlay):
        gl = ft.Geolocator(
            on_position=lambda e: draw_map(e.latitude, e.longitude, "Satélite GPS"),
            on_error=lambda e: fallback_ip_location() # Si falla el satélite, usa la antena móvil automáticamente
        )
        page.overlay.append(gl)
    else:
        gl = next(c for c in page.overlay if isinstance(c, ft.Geolocator))

    def btn_mapear(e):
        status_text.value = "Buscando satélites..."
        status_text.color = ft.Colors.AMBER
        page.update()
        try:
            gl.get_current_position()
        except:
            fallback_ip_location() # Si explota el permiso de Android, entra el respaldo

    return ft.Column([
        ft.Text("Outdoor (Titanio)", size=26, weight="bold", color=ft.Colors.GREEN),
        ft.ElevatedButton("MAPEAR MI POSICIÓN", icon=ft.Icons.MAP, on_click=btn_mapear, bgcolor=ft.Colors.BLUE_900, color=ft.Colors.WHITE),
        status_text,
        ft.Container(content=map_image, border_radius=10, border=ft.border.all(2, ft.Colors.GREY_800))
    ], horizontal_alignment="center")
