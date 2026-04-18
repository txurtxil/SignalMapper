import flet as ft
from app.services import database, sensors

def get_indoor_content(page: ft.Page, lang: str):
    points_layer = ft.Stack(width=320, height=450)
    
    # Imagen con sistema de emergencia
    map_image = ft.Image(
        src="plano_real.jpg",
        width=320, height=450,
        fit="contain",
        error_content=ft.Container(
            content=ft.Text("⚠️ plano_real.jpg no encontrado en assets", color="white"),
            bgcolor="red", alignment=ft.alignment.center
        )
    )

    def handle_tap(e: ft.ContainerTapEvent):
        try:
            # Detección de coordenadas compatible con todas las versiones
            x = getattr(e, 'local_x', 160)
            y = getattr(e, 'local_y', 225)
            
            rssi = sensors.get_wifi_signal()
            dot_color = ft.Colors.GREEN if rssi > -60 else ft.Colors.RED
            
            dot = ft.Container(
                width=16, height=16, bgcolor=dot_color, 
                border_radius=8, left=x-8, top=y-8
            )
            points_layer.controls.append(dot)
            page.update()
        except:
            pass

    return ft.Column([
        ft.Text("Mapeo Indoor", size=24, weight="bold"),
        ft.Stack([
            map_image,
            points_layer,
            ft.Container(width=320, height=450, bgcolor=ft.Colors.TRANSPARENT, on_click=handle_tap)
        ], width=320, height=450)
    ], horizontal_alignment="center")
