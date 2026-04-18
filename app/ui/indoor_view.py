import flet as ft
from app.services import database, sensors
from app.services.logger import Logger

def get_indoor_content(page: ft.Page, lang: str):
    Logger.log("Cargando vista Indoor...")
    
    # Capas
    map_image = ft.Image(src="plano_real.jpg", width=320, height=450, fit="contain")
    points_layer = ft.Stack(width=320, height=450)
    
    def handle_click(e: ft.ContainerTapEvent):
        Logger.log(f"Toque detectado en X:{e.local_x} Y:{e.local_y}")
        try:
            val_rssi = sensors.get_wifi_signal()
            Logger.log(f"Señal obtenida: {val_rssi} dBm")
            
            ft_color = ft.Colors.GREEN if val_rssi > -60 else (ft.Colors.ORANGE if val_rssi > -80 else ft.Colors.RED)
            
            dot = ft.Container(width=20, height=20, bgcolor=ft_color, border_radius=10, left=e.local_x-10, top=e.local_y-10)
            points_layer.controls.append(dot)
            database.add_scan("Indoor", "Plano", val_rssi, "color")
            page.update()
        except Exception as ex:
            Logger.log(f"ERROR en toque: {str(ex)}")

    touch_layer = ft.Container(width=320, height=450, bgcolor=ft.Colors.TRANSPARENT, on_click=handle_click)
    
    return ft.Column([
        ft.Text("Modo Indoor", size=24, weight="bold"),
        ft.Stack([map_image, points_layer, touch_layer], width=320, height=450)
    ], horizontal_alignment="center")
