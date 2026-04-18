import flet as ft
import urllib.request
import json
import threading
import time

def get_outdoor_content(page: ft.Page, lang: str):
    status_text = ft.Text("Estado: Esperando comando", size=14, color=ft.Colors.GREY_400)
    map_image = ft.Image(
        src="https://dummyimage.com/320x300/263238/ffffff.png&text=Mapa+en+espera",
        width=320, height=300, fit="cover", border_radius=10
    )

    btn = ft.ElevatedButton(
        text="OBTENER UBICACIÓN REAL",
        icon=ft.Icons.GPS_FIXED,
        bgcolor=ft.Colors.BLUE_900,
        color=ft.Colors.WHITE,
    )

    def update_ui_map(lat: float, lon: float, metodo: str):
        status_text.value = f"✅ Ubicación por {metodo}\nLat: {lat:.4f} | Lon: {lon:.4f}"
        status_text.color = ft.Colors.GREEN
        map_image.src = f"https://staticmap.openstreetmap.de/staticmap.php?center={lat},{lon}&zoom=16&size=320x300&maptype=mapnik&markers={lat},{lon},red-pushpin"
        page.update()

    def get_ip_location():
        try:
            status_text.value = "⚠️ GPS lento... usando red móvil"
            status_text.color = ft.Colors.AMBER
            page.update()
            with urllib.request.urlopen("https://ipinfo.io/json", timeout=5) as response:
                data = json.loads(response.read().decode())
            lat, lon = map(float, data['loc'].split(','))
            update_ui_map(lat, lon, "Red/IP")
        except Exception as e:
            status_text.value = f"❌ Error de conexión: {str(e)}"
            status_text.color = ft.Colors.RED
            page.update()

    # Geolocator (solo una vez)
    if not hasattr(page, "outdoor_geolocator"):
        try:
            geo = ft.Geolocator(
                on_position=lambda e: update_ui_map(e.latitude, e.longitude, "GPS Satélite"),
                on_error=lambda e: get_ip_location()
            )
            page.outdoor_geolocator = geo
            if geo not in page.overlay:
                page.overlay.append(geo)
        except Exception as e:
            status_text.value = "❌ Error: flet-geolocator no instalado o bug APK"
            status_text.color = ft.Colors.RED
            page.outdoor_geolocator = None
            page.update()          # ← CRÍTICO: ahora sí ves el error en pantalla
    else:
        print("ℹ️ Geolocator reutilizado")

    def handle_click(e):
        btn.text = "CONECTANDO..."
        btn.bgcolor = ft.Colors.AMBER_900
        status_text.value = "⏳ Buscando señal GPS..."
        status_text.color = ft.Colors.AMBER
        page.update()

        def task():
            try:
                geo = getattr(page, "outdoor_geolocator", None)
                if geo:
                    geo.request_permission()
                    geo.get_current_position()
                    time.sleep(5)
                    if "GPS Satélite" not in (status_text.value or ""):
                        get_ip_location()
                else:
                    get_ip_location()
            except Exception as ex:
                get_ip_location()
            finally:
                btn.text = "OBTENER UBICACIÓN REAL"
                btn.bgcolor = ft.Colors.BLUE_900
                page.update()

        threading.Thread(target=task, daemon=True).start()

    btn.on_click = handle_click

    return ft.Column([
        ft.Text("Mapeo Outdoor", size=26, weight="bold", color=ft.Colors.GREEN),
        btn,
        status_text,
        ft.Container(content=map_image, border_radius=12, border=ft.border.all(2, ft.Colors.GREY_800), padding=2)
    ], horizontal_alignment="center", spacing=20)
