import flet as ft
from app.services import database, sensors
from app.localization.strings import get_text

def get_outdoor_content(page: ft.Page, lang: str):
    # ✅ Imagen pública fiable (carga sin clave API)
    map_display = ft.Image(
        src="https://picsum.photos/id/1015/320/450",
        width=320, 
        height=450, 
        fit="cover", 
        border_radius=10
    )

    def handle_scan(e):
        val_rssi = sensors.get_wifi_signal()
        color_str = sensors.get_signal_color(val_rssi)
        ft_color = ft.Colors.GREEN if color_str == "green" else (ft.Colors.ORANGE if color_str == "orange" else ft.Colors.RED)
        
        database.add_scan("Outdoor", "GPS Scan", val_rssi, ft_color)
        page.overlay.append(ft.SnackBar(ft.Text(f"Escaneo Exterior: {val_rssi} dBm"), open=True, bgcolor=ft_color))
        page.update()

    return ft.Column([
        ft.Text(get_text(lang, "outdoor_title"), size=28, weight="bold", color=ft.Colors.GREEN),
        ft.ElevatedButton("Escanear GPS/WiFi", icon=ft.Icons.GPS_FIXED, on_click=handle_scan),
        map_display,
        ft.Text("Toca para escanear señal real", size=12, italic=True)
    ], horizontal_alignment="center")
