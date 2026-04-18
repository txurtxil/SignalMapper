import flet as ft
from app.services import database, sensors
from app.services.logger import Logger

def get_indoor_content(page: ft.Page, lang: str):
    Logger.log("Intentando cargar Indoor...")
    
    # Creamos un contenedor base que SIEMPRE se vea
    canvas = ft.Stack(width=320, height=450)
    
    # Intentamos poner la imagen
    try:
        img = ft.Image(src="plano_real.jpg", width=320, height=450, fit="contain")
        canvas.controls.append(img)
    except:
        canvas.controls.append(ft.Text("Error: Imagen no encontrada", color="red"))

    def handle_tap(e: ft.ContainerTapEvent):
        Logger.log(f"Toque en {e.local_x}, {e.local_y}")
        rssi = sensors.get_wifi_signal()
        dot_color = ft.Colors.GREEN if rssi > -60 else ft.Colors.RED
        
        canvas.controls.append(
            ft.Container(
                width=16, height=16, bgcolor=dot_color, border_radius=8,
                left=e.local_x - 8, top=e.local_y - 8
            )
        )
        database.add_scan("Indoor", "Plano", rssi, "color")
        page.update()

    # Capa táctil sólida
    touch_layer = ft.Container(
        width=320, height=450, 
        bgcolor=ft.Colors.with_opacity(0.01, ft.Colors.WHITE), # Casi invisible pero sólido
        on_click=handle_tap
    )
    canvas.controls.append(touch_layer)

    return ft.Column([
        ft.Text("SignalMapper - Indoor", size=20, weight="bold"),
        canvas
    ], horizontal_alignment="center")
