import flet as ft
import urllib.request
import json
import threading
from app.services import database, sensors

def get_outdoor_content(page: ft.Page, lang: str):
    status_text = ft.Text("Modo de escaneo por Red/Antena listo", size=14, color=ft.colors.GREY_400)
    
    # Imagen placeholder inicial
    map_image = ft.Image(
        src="https://dummyimage.com/320x300/263238/ffffff.png&text=Esperando+Coordenadas", 
        width=320, height=300, fit="cover", border_radius=10
    )

    def update_map(lat, lon, source):
        status_text.value = f"✅ Ubicación ({source}):\nLat: {lat:.4f} | Lon: {lon:.4f}"
        status_text.color = ft.colors.GREEN
        
        # 🔥 EL MAPA REAL DE CALLES HA VUELTO 🔥
        map_image.src = f"https://staticmap.openstreetmap.de/staticmap.php?center={lat},{lon}&zoom=17&size=320x300&maptype=mapnik&markers={lat},{lon},red-pushpin"
        
        try:
            rssi = sensors.get_wifi_signal()
            database.add_scan(f"Outdoor ({source})", f"{lat:.4f}, {lon:.4f}", rssi)
            status_text.value += "\n💾 Añadido al Historial"
        except Exception as ex:
            status_text.value += f"\n❌ Fallo BD: {ex}"

        page.update()

    def btn_usar_red(e):
        status_text.value = "⏳ Triangulando con Red Móvil/WiFi..."
        status_text.color = ft.colors.AMBER
        page.update()
        def task():
            try:
                with urllib.request.urlopen("https://ipinfo.io/json", timeout=5) as resp:
                    data = json.loads(resp.read().decode())
                    lat, lon = map(float, data['loc'].split(','))
                    update_map(lat, lon, "Red IP")
            except:
                status_text.value = "❌ Falló la conexión a Internet"
                status_text.color = ft.colors.RED
                page.update()
        threading.Thread(target=task, daemon=True).start()

    return ft.Column([
        ft.Text("Mapeo Outdoor", size=24, weight="bold", color=ft.colors.GREEN),
        ft.Text("⚠️ Solo usa el botón. El mapa no es táctil aquí.", color=ft.colors.ORANGE, size=11, text_align=ft.TextAlign.CENTER),
        ft.ElevatedButton("UBICAR POR ANTENA / RED", icon=ft.icons.WIFI_TETHERING, on_click=btn_usar_red, bgcolor=ft.colors.BLUE_900, color=ft.colors.WHITE),
        status_text,
        ft.Container(content=map_image, border_radius=10, border=ft.border.all(2, ft.colors.WHITE))
    ], horizontal_alignment="center", spacing=15)
