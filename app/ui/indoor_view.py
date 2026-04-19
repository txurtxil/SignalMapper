import flet as ft
import json
from app.services import database, sensors

def get_indoor_content(page: ft.Page, lang: str):
    points_layer = ft.Stack(width=320, height=450)
    debug_text = ft.Text("Toca el plano para mapear", color=ft.Colors.GREEN, size=12)

    def handle_tap(e):
        x, y = 160, 225 # Coordenada central por si acaso
        try:
            # EL TRUCO DEFINITIVO: Flet guarda los datos del toque en e.data como JSON
            if e.data:
                data = json.loads(e.data)
                x = float(data.get("local_x", 160))
                y = float(data.get("local_y", 225))
                debug_text.value = f"✅ Coordenada extraída: X:{int(x)} Y:{int(y)}"
            else:
                debug_text.value = "⚠️ No hay datos JSON en el toque"
        except Exception as ex:
            debug_text.value = f"⚠️ Fallo de lectura JSON: {str(ex)}"
        
        # Dibujamos el punto
        rssi = sensors.get_wifi_signal()
        dot_color = ft.Colors.GREEN if rssi > -60 else ft.Colors.RED
        
        dot = ft.Container(
            width=16, height=16, bgcolor=dot_color, 
            border_radius=8, left=x-8, top=y-8
        )
        points_layer.controls.append(dot)
        page.update()

    # El GestureDetector envolviendo un contenedor transparente
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
