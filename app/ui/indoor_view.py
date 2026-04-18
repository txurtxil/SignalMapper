import flet as ft
from app.services import sensors

def get_indoor_content(page: ft.Page, lang: str):
    # Capa para los puntos de señal
    points_layer = ft.Stack(width=320, height=450)

    # Imagen del plano con fallback potente
    map_image = ft.Image(
        src="plano_real.jpg",
        error_content=ft.Image(
            src="https://dummyimage.com/320x450/263238/ffffff.png&text=Falta+plano_real.jpg+en+assets",
            fit="contain"
        ),
        width=320,
        height=450,
        fit="contain"
    )

    def handle_tap(e: ft.ContainerTapEvent):
        try:
            x, y = e.local_x, e.local_y
            rssi = sensors.get_wifi_signal()
            color = ft.Colors.GREEN if rssi > -60 else ft.Colors.RED

            dot = ft.Container(
                width=16, height=16,
                bgcolor=color,
                border_radius=8,
                left=x - 8,
                top=y - 8
            )
            points_layer.controls.append(dot)
            page.update()
        except:
            pass

    return ft.Column([
        ft.Text("Mapeo Indoor", size=26, weight="bold", color=ft.Colors.BLUE),
        ft.Stack([
            map_image,
            points_layer,
            # Contenedor transparente para capturar taps
            ft.Container(
                width=320,
                height=450,
                bgcolor=ft.Colors.TRANSPARENT,
                on_click=handle_tap
            )
        ], width=320, height=450)
    ], horizontal_alignment="center", spacing=10)
