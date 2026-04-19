import flet as ft
import urllib.request
import json
import threading
from app.services import database, sensors # Importamos las herramientas de datos

def get_outdoor_content(page: ft.Page, lang: str):
    status_text = ft.Text("Modo de escaneo por Red/Antena listo", size=14, color=ft.Colors.GREY_400)
    map_image = ft.Image(src="https://dummyimage.com/320x300/263238/ffffff.png&text=Esperando+Coordenadas", width=320, height=300, fit="cover", border_radius=10)

    def update_map(lat, lon, source):
        status_text.value = f"✅ Ubicación ({source}):\nLat: {lat:.4f} | Lon: {lon:.4f}"
        status_text.color = ft.Colors.GREEN
        map_image.src = f"https://dummyimage.com/320x300/263238/4fc3f7.png&text={source}:+{lat:.2f},+{lon:.2f}"
        
        # 🔥 EL ESLABÓN PERDIDO: GUARDAMOS EN LA BASE DE DATOS 🔥
        try:
            rssi = sensors.get_wifi_signal()
            database.add_scan(f"Outdoor ({source})", f"{lat:.4f}, {lon:.4f}", rssi)
            status_text.value += "\n💾 Añadido al Historial"
        except Exception as ex:
            status_text.value += f"\n❌ Fallo BD: {ex}"

        page.update()

    def btn_usar_red(e):
        status_text.value = "⏳ Triangulando con Red Móvil/WiFi..."
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

    return ft.Column([
        ft.Text("Mapeo Outdoor", size=24, weight="bold", color=ft.Colors.GREEN),
        ft.Text(
            "⚠️ GPS Satelital inhabilitado temporalmente debido a bug nativo de Android. Se usa triangulación.", 
            color=ft.Colors.ORANGE, size=11, text_align=ft.TextAlign.CENTER
        ),
        ft.ElevatedButton("UBICAR POR ANTENA / RED", icon=ft.Icons.WIFI_TETHERING, on_click=btn_usar_red, bgcolor=ft.Colors.BLUE_900, color=ft.Colors.WHITE),
        status_text,
        ft.Container(content=map_image, border_radius=10, border=ft.border.all(2, "white"))
    ], horizontal_alignment="center", spacing=15)
