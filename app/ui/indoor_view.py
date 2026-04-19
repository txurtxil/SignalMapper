import flet as ft
from app.services import database, sensors

def get_indoor_content(page: ft.Page, lang: str):
    points_layer = ft.Stack(width=320, height=450)
    debug_text = ft.Text("Toca el plano para ver los datos", color=ft.Colors.AMBER, size=12)

    def handle_tap(e):
        # 1. Modo Forense: Escupir todo lo que tiene el evento "e"
        try:
            vars_evento = str(dir(e))
            debug_text.value = f"Detectado: {vars_evento[:100]}..."
            page.update()
        except:
            pass

        # 2. Intentar dibujar
        try:
            x = getattr(e, 'local_x', getattr(e, 'x', 160))
            y = getattr(e, 'local_y', getattr(e, 'y', 225))
            
            rssi = sensors.get_wifi_signal()
            dot_color = ft.Colors.GREEN if rssi > -60 else ft.Colors.RED
            
            dot = ft.Container(
                width=16, height=16, bgcolor=dot_color, 
                border_radius=8, left=x-8, top=y-8
            )
            points_layer.controls.append(dot)
            page.update()
        except Exception as ex:
            debug_text.value = f"Fallo al dibujar: {str(ex)}"
            page.update()

    touch_area = ft.GestureDetector(
        on_tap_down=handle_tap,
        content=ft.Container(width=320, height=450, bgcolor=ft.Colors.TRANSPARENT)
    )

    return ft.Column([
        ft.Text("Mapeo Indoor", size=24, weight="bold", color=ft.Colors.BLUE),
        debug_text,
        ft.Stack([
            ft.Image(src="plano_real.jpg", width=320, height=450, fit="contain"),
            points_layer,
            touch_area
        ], width=320, height=450)
    ], horizontal_alignment="center")
