import flet as ft
from app.services import database, sensors

def get_indoor_content(page: ft.Page, lang: str):
    points_layer = ft.Stack(width=320, height=450)

    # Volvemos al ContainerTapEvent que SÍ tiene local_x garantizado
    def handle_tap(e: ft.ContainerTapEvent):
        try:
            x = e.local_x
            y = e.local_y
            
            rssi = sensors.get_wifi_signal()
            color = ft.Colors.GREEN if rssi > -60 else (ft.Colors.ORANGE if rssi > -80 else ft.Colors.RED)
            
            dot = ft.Container(
                width=16, height=16, bgcolor=color, border_radius=8, 
                left=x - 8, top=y - 8
            )
            points_layer.controls.append(dot)
            database.add_scan("Indoor", "Plano Touch", rssi, "color")
            
            page.overlay.append(ft.SnackBar(ft.Text(f"✅ Punto en X:{int(x)} Y:{int(y)}"), open=True, bgcolor=color))
            page.update()
        except Exception as ex:
            page.overlay.append(ft.SnackBar(ft.Text(f"Error: {str(ex)}"), open=True, bgcolor=ft.Colors.RED))
            page.update()

    return ft.Column([
        ft.Text("Indoor (Touch Fix)", size=24, weight="bold", color=ft.Colors.BLUE),
        ft.Stack([
            ft.Image(src="plano_real.jpg", width=320, height=450, fit="contain"),
            points_layer,
            # Contenedor transparente: es infalible para leer el toque
            ft.Container(width=320, height=450, bgcolor=ft.Colors.TRANSPARENT, on_click=handle_tap)
        ], width=320, height=450)
    ], horizontal_alignment="center")
