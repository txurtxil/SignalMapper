import flet as ft
from app.services import database, sensors

def get_indoor_content(page: ft.Page, lang: str):
    # Capas: 1. Imagen fondo, 2. Puntos, 3. Atrapa-toques transparente
    map_image = ft.Image(src="plano_real.jpg", width=320, height=450, fit="contain")
    points_layer = ft.Stack(width=320, height=450)
    
    heatmap_stack = ft.Stack(
        controls=[map_image, points_layer], 
        width=320, height=450
    )

    def handle_click(e: ft.ContainerTapEvent):
        val_rssi = sensors.get_wifi_signal()
        color_str = sensors.get_signal_color(val_rssi)
        ft_color = ft.Colors.GREEN if color_str == "green" else (ft.Colors.ORANGE if color_str == "orange" else ft.Colors.RED)
        
        # Coordenadas locales del toque
        x = e.local_x - 10
        y = e.local_y - 10
        
        dot = ft.Container(width=20, height=20, bgcolor=ft_color, border_radius=10, left=x, top=y)
        points_layer.controls.append(dot)
        database.add_scan("Indoor", "Plano Real", val_rssi, ft_color)
        
        page.overlay.append(ft.SnackBar(ft.Text(f"Punto: {val_rssi} dBm"), open=True, bgcolor=ft_color))
        page.update()

    # Este contenedor es invisible pero captura todos los clics
    touch_layer = ft.Container(
        width=320, height=450, 
        bgcolor=ft.Colors.TRANSPARENT, 
        on_click=handle_click
    )
    heatmap_stack.controls.append(touch_layer)

    return ft.Column([
        ft.Text("Modo Indoor", size=28, weight="bold", color=ft.Colors.BLUE),
        heatmap_stack
    ], horizontal_alignment="center")
