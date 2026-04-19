import flet as ft
import urllib.request
import json

def get_outdoor_content(page: ft.Page, lang: str):
    status_text = ft.Text("Estado: Listo para escanear", size=14, color=ft.Colors.GREY_400)
    
    # Imagen placeholder que 100% funciona
    map_image = ft.Image(
        src="https://dummyimage.com/320x300/263238/ffffff.png&text=Esperando+Coordenadas",
        width=320, height=300, fit="cover", border_radius=10
    )

    if not hasattr(page, "geo_fix"):
        try:
            geo = ft.Geolocator(
                on_position=lambda e: update_map(e.latitude, e.longitude, "GPS Satélite"),
                on_error=lambda e: get_ip_fallback(str(e.data))
            )
            page.overlay.append(geo)
            page.geo_fix = geo
        except:
            page.geo_fix = None

    def update_map(lat, lon, source):
        status_text.value = f"✅ Ubicación ({source}):\nLat: {lat:.4f} | Lon: {lon:.4f}"
        status_text.color = ft.Colors.GREEN
        # Generamos una imagen dinámica con tus coordenadas para asegurar que carga
        map_image.src = f"https://dummyimage.com/320x300/263238/4fc3f7.png&text={source}:+{lat:.2f},+{lon:.2f}"
        page.update()

    def get_ip_fallback(err=""):
        try:
            status_text.value = "⚠️ Buscando por Red Móvil/WiFi..."
            page.update()
            with urllib.request.urlopen("https://ipinfo.io/json", timeout=5) as resp:
                data = json.loads(resp.read().decode())
                lat, lon = map(float, data['loc'].split(','))
                update_map(lat, lon, "Red IP")
        except:
            status_text.value = f"❌ Error total: {err}"
            page.update()

    # BOTÓN 1: Solo pedir permiso
    def btn_permiso(e):
        if page.geo_fix:
            page.geo_fix.request_permission()
            status_text.value = "⏳ Revisa la pantalla: ¿Te pide permiso?"
            status_text.color = ft.Colors.AMBER
            page.update()

    # BOTÓN 2: Solo leer coordenadas
    def btn_leer(e):
        if page.geo_fix:
            status_text.value = "⏳ Buscando satélites..."
            status_text.color = ft.Colors.AMBER
            page.update()
            page.geo_fix.get_current_position()
        else:
            get_ip_fallback("Geolocator roto")

    return ft.Column([
        ft.Text("Mapeo Outdoor", size=24, weight="bold", color=ft.Colors.GREEN),
        ft.Row([
            ft.ElevatedButton("1. PERMISOS", on_click=btn_permiso, bgcolor=ft.Colors.BLUE_900, color=ft.Colors.WHITE),
            ft.ElevatedButton("2. LEER GPS", on_click=btn_leer, bgcolor=ft.Colors.GREEN_900, color=ft.Colors.WHITE),
        ], alignment=ft.MainAxisAlignment.CENTER),
        status_text,
        ft.Container(content=map_image, border_radius=10, border=ft.border.all(2, "white"))
    ], horizontal_alignment="center")
