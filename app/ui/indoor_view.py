import flet as ft
from app.services import database, sensors
from app.localization.strings import get_text

def get_indoor_content(page: ft.Page, lang: str):
    # 1. La imagen nativa estática
    map_image = ft.Image(src="plano_real.jpg", width=320, height=450, fit="contain")
    
    # 2. Capa transparente (Garantiza que puedas tocar toda la pantalla aunque la imagen falle)
    touch_catcher = ft.Container(width=320, height=450, bgcolor=ft.Colors.TRANSPARENT)
    
    # 3. El Stack: Abajo la imagen, encima el atrapa-toques. Los puntos irán encima de esto.
    heatmap_stack = ft.Stack(controls=[map_image, touch_catcher], width=320, height=450)

    def handle_tap(e: ft.TapEvent):
        val_rssi = sensors.get_wifi_signal()
        color_str = sensors.get_signal_color(val_rssi)
        ft_color = ft.Colors.GREEN if color_str == "green" else (ft.Colors.ORANGE if color_str == "orange" else ft.Colors.RED)
        
        # Coordenadas exactas nativas
        pos_x = e.local_x - 10
        pos_y = e.local_y - 10
        
        dot = ft.Container(
            width=20, height=20,
            bgcolor=ft_color, border_radius=10,
            left=pos_x, top=pos_y
        )
        
        heatmap_stack.controls.append(dot)
        database.add_scan("Indoor", "Plano Real", val_rssi, ft_color)
        
        page.overlay.append(ft.SnackBar(ft.Text(f"✅ Punto guardado: {val_rssi} dBm"), open=True, bgcolor=ft_color))
        page.update()

    return ft.Column([
        ft.Text(get_text(lang, "indoor_title"), size=28, weight="bold", color=ft.Colors.BLUE),
        ft.Text("Mi Plano Real", size=16, color=ft.Colors.GREY_400),
        ft.GestureDetector(
            on_tap_down=handle_tap,
            content=heatmap_stack
        )
    ], horizontal_alignment="center", expand=True)
