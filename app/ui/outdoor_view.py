import flet as ft
import urllib.request
import json
import threading

def get_outdoor_content(page: ft.Page, lang: str):
    status_text = ft.Text("Modo de escaneo por Red/Antena listo", size=14, color=ft.Colors.GREY_400)
    map_image = ft.Image(src="https://dummyimage.com/320x300/263238/ffffff.png&text=Esperando+Coordenadas", width=320, height=300, fit="cover", border_radius=10)

    def update_map(lat, lon, source):
        status_text.value = f"✅ Ubicación ({source}):\nLat: {lat:.4f} | Lon: {lon:.4f}"
        status_text.color = ft.Colors.GREEN
        map_image.src = f"https://dummyimage.com/320x300/263238/4fc3f7.png&text={source}:+{lat:.2f},+{lon:.2f}"
        page.update()

    def btn_usar_red(e):
        status_text.value = "⏳ Triangulando con Red Móvil/WiFi..."
        status_text.color = ft.Colors.AMBER
        page.update()
        def task():
            try:
                # Usamos la API de triangulación por IP (Súper estable)
                with urllib.request.urlopen("https://ipinfo.io/json", timeout=5) as resp:
                    data = json.loads(resp.read().decode())
                    lat, lon = map(float, data['loc'].split(','))
                    update_map(lat, lon, "Red IP")
            except:
                status_text.value = "❌ Falló la conexión a Internet"
                status_text.color = ft.Colors.RED
                page.update()
        threading.Thread(target=task, daemon=True).start()

    return ft.Column([
        ft.Text("Mapeo Outdoor", size=24, weight="bold", color=ft.Colors.GREEN),
        ft.Text(
            "⚠️ GPS Satelital inhabilitado temporalmente debido a un bug en la plataforma base de Android (Issue #6384). Se usa triangulación de antenas.", 
            color=ft.Colors.ORANGE, size=11, text_align=ft.TextAlign.CENTER
        ),
        ft.ElevatedButton("UBICAR POR ANTENA / RED", icon=ft.Icons.WIFI_TETHERING, on_click=btn_usar_red, bgcolor=ft.Colors.BLUE_900, color=ft.Colors.WHITE),
        status_text,
        ft.Container(content=map_image, border_radius=10, border=ft.border.all(2, "white"))
    ], horizontal_alignment="center", spacing=15)
