import flet as ft
from app.services import database, sensors

def get_indoor_content(page: ft.Page, lang: str):
    points_layer = ft.Stack(width=320, height=450)
    error_text = ft.Text("", color=ft.Colors.RED, size=12)

    def handle_tap(e):
        try:
            # MAGIA NEGRA DEFENSIVA: Extrae coordenadas sin importar la versión de Flet
            # Si no existe local_x, busca x. Si falla todo, lo pone en el centro (160, 225).
            x = float(getattr(e, 'local_x', getattr(e, 'x', 160)))
            y = float(getattr(e, 'local_y', getattr(e, 'y', 225)))

            rssi = sensors.get_wifi_signal()
            color = ft.Colors.GREEN if rssi > -60 else (ft.Colors.ORANGE if rssi > -80 else ft.Colors.RED)
            
            dot = ft.Container(
                width=16, height=16, bgcolor=color, border_radius=8,
                left=x - 8, top=y - 8
            )
            points_layer.controls.append(dot)
            page.update()
        except Exception as ex:
            error_text.value = f"Fallback activado: {str(ex)}"
            page.update()

    # Contenedor base que fuerza la lectura táctil en Android
    touch_area = ft.Container(
        width=320, height=450, 
        bgcolor=ft.Colors.with_opacity(0.01, ft.Colors.WHITE), 
        on_click=handle_tap
    )

    return ft.Column([
        ft.Text("Indoor (Titanio)", size=24, weight="bold", color=ft.Colors.BLUE),
        error_text,
        ft.Stack([
            ft.Image(src="plano_real.jpg", width=320, height=450, fit="contain"),
            points_layer,
            touch_area
        ], width=320, height=450)
    ], horizontal_alignment="center")
