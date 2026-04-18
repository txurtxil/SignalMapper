import flet as ft
from app.services import database, sensors

def get_outdoor_content(page: ft.Page, lang: str):
    try:
        gps_data = ft.Text("GPS Simulado (Modo Seguro)", text_align=ft.TextAlign.CENTER)
        map_box = ft.Container(content=gps_data, width=320, height=450, bgcolor=ft.Colors.BLUE_GREY_900, border_radius=10, alignment=ft.alignment.center)

        def handle_scan(e):
            try:
                val_rssi = sensors.get_wifi_signal()
                color_str = sensors.get_signal_color(val_rssi)
                ft_color = ft.Colors.GREEN if color_str == "green" else (ft.Colors.ORANGE if color_str == "orange" else ft.Colors.RED)
                
                database.add_scan("Outdoor", "GPS Seguro", val_rssi, ft_color)
                page.overlay.append(ft.SnackBar(ft.Text(f"✅ RSSI: {val_rssi} dBm Guardado"), open=True, bgcolor=ft_color))
                page.update()
            except Exception as ex:
                page.overlay.append(ft.SnackBar(ft.Text(f"❌ Error Outdoor: {str(ex)}"), open=True, bgcolor=ft.Colors.RED))
                page.update()

        return ft.Column([
            ft.Text("Modo Outdoor", size=28, weight="bold", color=ft.Colors.GREEN),
            ft.ElevatedButton("Escanear Seguro", icon=ft.Icons.GPS_FIXED, on_click=handle_scan),
            map_box
        ], horizontal_alignment="center")

    except Exception as fatal_error:
        # EL ESCUDO OUTDOOR
        return ft.Column([
            ft.Text("CRASH FATAL OUTDOOR", color=ft.Colors.RED, size=24, weight="bold"),
            ft.Text(str(fatal_error), color=ft.Colors.WHITE)
        ], horizontal_alignment="center")
