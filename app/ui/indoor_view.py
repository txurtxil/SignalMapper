import flet as ft
from app.services import database, sensors

def get_indoor_content(page: ft.Page, lang: str):
    points_layer = ft.Stack(width=320, height=450)

    def handle_tap(e):
        rssi = sensors.get_wifi_signal()
        color = ft.Colors.GREEN if rssi > -60 else (ft.Colors.ORANGE if rssi > -80 else ft.Colors.RED)
        
        # Leemos las coordenadas del clic de forma segura
        x = e.local_x if e.local_x else 160
        y = e.local_y if e.local_y else 225
        
        dot = ft.Container(width=16, height=16, bgcolor=color, border_radius=8, left=x-8, top=y-8)
        points_layer.controls.append(dot)
        database.add_scan("Indoor", "Plano APK", rssi, "color")
        
        page.overlay.append(ft.SnackBar(ft.Text(f"✅ Punto: {rssi} dBm"), open=True, bgcolor=color))
        page.update()

    return ft.Column([
        ft.Text("Indoor (Estable)", size=24, weight="bold", color=ft.Colors.BLUE),
        ft.Stack([
            ft.Image(src="plano_real.jpg", width=320, height=450, fit="contain"),
            points_layer,
            ft.Container(width=320, height=450, bgcolor=ft.Colors.TRANSPARENT, on_click=handle_tap)
        ], width=320, height=450)
    ], horizontal_alignment="center")
