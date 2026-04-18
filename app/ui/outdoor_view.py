import flet as ft
from app.services import database, sensors
from app.localization.strings import get_text

def get_outdoor_content(page: ft.Page, lang: str):
    # Texto que mostrará los datos del GPS
    gps_data = ft.Text("GPS inactivo.\nPulsa Escanear para pedir permisos.", text_align=ft.TextAlign.CENTER)
    
    map_box = ft.Container(
        content=gps_data,
        width=320, height=450, 
        bgcolor=ft.Colors.BLUE_GREY_900, 
        border_radius=10, 
        alignment=ft.alignment.center
    )

    # 🚀 MAGIA NATIVA: El componente Geolocator de Flet
    geolocator = ft.Geolocator(
        on_position=lambda e: update_gps(e),
        on_error=lambda e: print("GPS Error:", e)
    )
    # Lo inyectamos en la app para que funcione
    page.overlay.append(geolocator)

    def update_gps(e):
        gps_data.value = f"✅ GPS Activo\nLat: {e.latitude:.5f}\nLon: {e.longitude:.5f}\nPrecisión: {e.accuracy}m"
        page.update()

    def handle_scan(e):
        # 1. Obligamos a Android a sacar el popup de permisos
        geolocator.request_permission()
        # 2. Leemos la ubicación real
        geolocator.get_current_position()
        
        val_rssi = sensors.get_wifi_signal()
        color_str = sensors.get_signal_color(val_rssi)
        ft_color = ft.Colors.GREEN if color_str == "green" else (ft.Colors.ORANGE if color_str == "orange" else ft.Colors.RED)
        
        database.add_scan("Outdoor", "GPS Nativo", val_rssi, ft_color)
        page.overlay.append(ft.SnackBar(ft.Text(f"Escaneo Guardado: {val_rssi} dBm"), open=True, bgcolor=ft_color))
        page.update()

    return ft.Column([
        ft.Text(get_text(lang, "outdoor_title"), size=28, weight="bold", color=ft.Colors.GREEN),
        ft.ElevatedButton("Conectar GPS y Escanear", icon=ft.Icons.GPS_FIXED, on_click=handle_scan),
        map_box
    ], horizontal_alignment="center")
