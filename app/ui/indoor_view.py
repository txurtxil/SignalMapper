import flet as ft
from app.services import database, sensors
from app.services.logger import Logger

def get_indoor_content(page: ft.Page, lang: str):
    Logger.log("Cargando Indoor...")
    
    # Capas: Fondo -> Puntos -> Capa táctil
    points_layer = ft.Stack(width=320, height=450)
    
    def handle_tap(e: ft.ContainerTapEvent):
        try:
            Logger.log(f"Tap en: {e.local_x}, {e.local_y}")
            val_rssi = sensors.get_wifi_signal()
            color = ft.Colors.GREEN if val_rssi > -60 else (ft.Colors.ORANGE if val_rssi > -80 else ft.Colors.RED)
            
            dot = ft.Container(
                width=16, height=16, bgcolor=color, border_radius=8,
                left=e.local_x - 8, top=e.local_y - 8
            )
            points_layer.controls.append(dot)
            database.add_scan("Indoor", "Plano Real", val_rssi, "color")
            page.update()
        except Exception as ex:
            Logger.log(f"Error Tap: {str(ex)}")

    return ft.Column([
        ft.Text("Modo Indoor", size=24, weight="bold"),
        ft.Stack([
            ft.Image(src="plano_real.jpg", width=320, height=450, fit="contain"),
            points_layer,
            ft.Container(width=320, height=450, bgcolor=ft.Colors.TRANSPARENT, on_click=handle_tap)
        ], width=320, height=450)
    ], horizontal_alignment="center")
