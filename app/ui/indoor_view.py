import flet as ft
import re
from app.services import database, sensors

def get_indoor_content(page: ft.Page, lang: str):
    points_layer = ft.Stack(width=320, height=450)
    debug_text = ft.Text("Toca el plano para mapear", color=ft.Colors.GREEN, size=12)

    def handle_tap(e):
        x, y = 160, 225
        try:
            # 🔥 EL HACK: Pasamos el evento a texto bruto y buscamos los números
            s = str(e)
            match_x = re.search(r'x=([0-9.]+)', s)
            match_y = re.search(r'y=([0-9.]+)', s)
            
            if match_x and match_y:
                x = float(match_x.group(1))
                y = float(match_y.group(1))
                debug_text.value = f"✅ Regex Extractor: X:{int(x)} Y:{int(y)}"
            else:
                debug_text.value = f"⚠️ Fallo Regex en texto: {s[:50]}..."
        except Exception as ex:
            debug_text.value = f"⚠️ Error: {str(ex)}"
        
        rssi = sensors.get_wifi_signal()
        dot_color = ft.Colors.GREEN if rssi > -60 else ft.Colors.RED
        
        dot = ft.Container(
            width=16, height=16, bgcolor=dot_color, 
            border_radius=8, left=x-8, top=y-8
        )
        points_layer.controls.append(dot)
        page.update()

    # Añadimos on_pan_start (deslizamiento corto) que a veces reporta mejor las coordenadas en Android
    touch_area = ft.GestureDetector(
        on_tap_down=handle_tap,
        on_pan_start=handle_tap,
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
