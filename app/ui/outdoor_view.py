import flet as ft
from app.services import database, sensors
from app.localization.strings import get_text

def get_outdoor_content(page: ft.Page, lang: str):
    # En el APK usamos una WebView o una imagen de mapa dinámica
    # Para esta fase, usaremos una imagen de mapa que responda a la ubicación
    map_display = ft.Image(
        src="https://maps.googleapis.com/maps/api/staticmap?center=40.4167,-3.7037&zoom=15&size=600x600&key=YOUR_KEY_OPTIONAL",
        width=320, height=450, fit="cover", border_radius=10
    )

    def handle_scan(e):
        val_rssi = sensors.get_wifi_signal()
        color_str = sensors.get_signal_color(val_rssi)
        ft_color = ft.Colors.GREEN if color_str == "green" else (ft.Colors.ORANGE if color_str == "orange" else ft.Colors.RED)
        
        database.add_scan("Outdoor", "GPS Scan", val_rssi, ft_color)
        page.overlay.append(ft.SnackBar(ft.Text(f"RSSI: {val_rssi} dBm"), open=True, bgcolor=ft_color))
        page.update()

    return ft.Column([
        ft.Text(get_text(lang, "outdoor_title"), size=28, weight="bold", color=ft.Colors.GREEN),
        ft.ElevatedButton("Escanear GPS/WiFi", icon=ft.Icons.GPS_FIXED, on_click=handle_scan),
        ft.Container(content=map_display, border=ft.border.all(1, ft.Colors.BLUE_GREY_700), border_radius=10)
    ], horizontal_alignment="center")
