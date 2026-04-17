import flet as ft
from app.services import database, sensors
from app.localization.strings import get_text

def get_outdoor_content(page: ft.Page, lang: str):
    # ✅ CORREGIDO: alignment.center no existe en esta versión de Flet
    # Usamos la forma oficial: ft.alignment.Alignment(0, 0)
    map_placeholder = ft.Container(
        content=ft.Icon(ft.Icons.MAP_OUTLINED, size=100, color=ft.Colors.GREY_700),
        width=320, 
        height=450, 
        bgcolor=ft.Colors.BLUE_GREY_900, 
        border_radius=10,
        alignment=ft.alignment.Alignment(0, 0)   # ← centro perfecto
    )

    def handle_scan(e):
        val_rssi = sensors.get_wifi_signal()
        color_str = sensors.get_signal_color(val_rssi)
        ft_color = ft.Colors.GREEN if color_str == "green" else (ft.Colors.ORANGE if color_str == "orange" else ft.Colors.RED)
        
        # Guardamos como "Outdoor" en la calle
        database.add_scan("Outdoor", "Calle/GPS", val_rssi, ft_color)
        
        page.overlay.append(ft.SnackBar(
            ft.Text(f"Escaneo Exterior: {val_rssi} dBm"), 
            open=True, 
            bgcolor=ft_color
        ))
        page.update()

    return ft.Column([
        ft.Text(get_text(lang, "outdoor_title"), size=28, weight="bold", color=ft.Colors.GREEN),
        ft.ElevatedButton(
            get_text(lang, "scan_saved") if lang == "en" else "Escanear Aquí", 
            icon=ft.Icons.GPS_FIXED, 
            on_click=handle_scan
        ),
        map_placeholder,
        ft.Text("El mapa cargará las coordenadas reales en el APK final.", size=12, italic=True)
    ], horizontal_alignment="center")
