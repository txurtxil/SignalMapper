import flet as ft
import urllib.request
import json
import threading

def get_outdoor_content(page: ft.Page, lang: str):
    status_text = ft.Text("Selecciona método", size=14, color=ft.Colors.GREY_400)
    map_image = ft.Image(src="https://dummyimage.com/320x300/263238/ffffff.png&text=Esperando+Coordenadas", width=320, height=300, fit="cover", border_radius=10)

    if not hasattr(page, "geo_fix"):
        try:
            geo = ft.Geolocator(
                on_position=lambda e: update_map(e.latitude, e.longitude, "Satélite"),
                on_error=lambda e: status_text.update()
            )
            page.overlay.append(geo)
            page.geo_fix = geo
        except:
            page.geo_fix = None

    def update_map(lat, lon, source):
        status_text.value = f"✅ Ubicación ({source}):\nLat: {lat:.4f} | Lon: {lon:.4f}"
        status_text.color = ft.Colors.GREEN
        map_image.src = f"https://dummyimage.com/320x300/263238/4fc3f7.png&text={source}:+{lat:.2f},+{lon:.2f}"
        page.update()

    def btn_usar_red(e):
        status_text.value = "⏳ Triangulando..."
        status_text.color = ft.Colors.AMBER
        page.update()
        def task():
            try:
                with urllib.request.urlopen("https://ipinfo.io/json", timeout=5) as resp:
                    data = json.loads(resp.read().decode())
                    lat, lon = map(float, data['loc'].split(','))
                    update_map(lat, lon, "Red IP")
            except:
                status_text.value = "❌ Falló la conexión a Internet"
                status_text.color = ft.Colors.RED
                page.update()
        threading.Thread(target=task, daemon=True).start()

    def btn_usar_gps(e):
        status_text.value = "⏳ Forzando permisos en Android..."
        status_text.color = ft.Colors.AMBER
        page.update()
        if page.geo_fix:
            try:
                # 🔥 FORZAMOS NATIVAMENTE LA VENTANA DE PERMISOS
                page.geo_fix.request_permission()
                page.geo_fix.get_current_position()
            except Exception as ex:
                status_text.value = f"❌ Error GPS: {str(ex)}"
                status_text.color = ft.Colors.RED
                page.update()

    return ft.Column([
        ft.Text("Mapeo Outdoor", size=24, weight="bold", color=ft.Colors.GREEN),
        ft.Row([
            ft.ElevatedButton("ANTENA / RED", icon=ft.Icons.WIFI, on_click=btn_usar_red, bgcolor=ft.Colors.BLUE_900, color=ft.Colors.WHITE),
            ft.ElevatedButton("SATÉLITE GPS", icon=ft.Icons.GPS_FIXED, on_click=btn_usar_gps, bgcolor=ft.Colors.GREEN_900, color=ft.Colors.WHITE),
        ], alignment=ft.MainAxisAlignment.CENTER),
        status_text,
        ft.Container(content=map_image, border_radius=10, border=ft.border.all(2, "white"))
    ], horizontal_alignment="center")
