import flet as ft
from app.services import database, sensors

def get_indoor_content(page: ft.Page, lang: str):
    try:
        map_image = ft.Image(src="plano_real.jpg", width=320, height=450, fit="contain")
        heatmap_stack = ft.Stack(controls=[map_image], width=320, height=450)

        # Quitamos el tipado estricto (e: ft.ContainerTapEvent) que a veces crashea Android
        def handle_tap(e):
            try:
                val_rssi = sensors.get_wifi_signal()
                color_str = sensors.get_signal_color(val_rssi)
                ft_color = ft.Colors.GREEN if color_str == "green" else (ft.Colors.ORANGE if color_str == "orange" else ft.Colors.RED)
                
                # Lectura segura a prueba de fallos
                pos_x = getattr(e, 'local_x', 160) - 10
                pos_y = getattr(e, 'local_y', 225) - 10
                
                dot = ft.Container(width=20, height=20, bgcolor=ft_color, border_radius=10, left=pos_x, top=pos_y)
                heatmap_stack.controls.append(dot)
                database.add_scan("Indoor", "Plano Real", val_rssi, ft_color)
                
                page.overlay.append(ft.SnackBar(ft.Text(f"✅ Punto: {val_rssi} dBm"), open=True, bgcolor=ft_color))
                page.update()
            except Exception as ex:
                page.overlay.append(ft.SnackBar(ft.Text(f"Error Tap: {str(ex)}"), open=True, bgcolor=ft.Colors.RED))
                page.update()

        touch_catcher = ft.Container(width=320, height=450, bgcolor=ft.Colors.TRANSPARENT, on_click=handle_tap)
        heatmap_stack.controls.append(touch_catcher)

        return ft.Column([
            ft.Text("Modo Indoor", size=28, weight="bold", color=ft.Colors.BLUE),
            heatmap_stack
        ], horizontal_alignment="center", expand=True)

    except Exception as fatal_error:
        # EL ESCUDO: Si algo colapsa, mostramos letras rojas en vez de pantalla negra
        return ft.Column([
            ft.Text("CRASH FATAL INDOOR", color=ft.Colors.RED, size=24, weight="bold"),
            ft.Text(str(fatal_error), color=ft.Colors.WHITE)
        ], horizontal_alignment="center")
