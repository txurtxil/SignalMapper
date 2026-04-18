import flet as ft
from app.services import database, sensors

def get_indoor_content(page: ft.Page, lang: str):
    # Capa para guardar los puntitos
    points_layer = ft.Stack(width=320, height=450)

    # Solo el GestureDetector nos da las coordenadas exactas de Android sin colgar la app
    def handle_tap(e: ft.TapEvent):
        try:
            x = e.local_x
            y = e.local_y
            
            rssi = sensors.get_wifi_signal()
            dot_color = ft.Colors.GREEN if rssi > -60 else ft.Colors.RED
            
            dot = ft.Container(
                width=16, height=16, bgcolor=dot_color, border_radius=8,
                left=x - 8, top=y - 8
            )
            points_layer.controls.append(dot)
            page.update()
        except Exception as ex:
            print(f"Error silencioso evitado: {ex}")

    # Envolvemos un contenedor transparente en el GestureDetector
    touch_area = ft.GestureDetector(
        on_tap_down=handle_tap,
        content=ft.Container(width=320, height=450, bgcolor=ft.Colors.TRANSPARENT)
    )

    return ft.Column([
        ft.Text("Modo Indoor", size=24, weight="bold", color=ft.Colors.BLUE),
        ft.Stack([
            ft.Image(src="plano_real.jpg", width=320, height=450, fit="contain"),
            points_layer,
            touch_area
        ], width=320, height=450)
    ], horizontal_alignment="center")
