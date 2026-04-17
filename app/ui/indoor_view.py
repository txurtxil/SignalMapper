import flet as ft
from app.services import database, sensors
from app.localization.strings import get_text

def get_indoor_content(page: ft.Page, lang: str):
    map_bg = ft.Container(width=320, height=450, bgcolor=ft.Colors.BLUE_GREY_900, border_radius=10)
    heatmap_stack = ft.Stack(width=320, height=450)
    heatmap_stack.controls.append(map_bg)

    # ✅ RUTA CORRECTA PARA APK (solo el nombre)
    planos = {
        "Mi Plano Real": "plano_real.jpg",
        "Casa / Home": "https://dummyimage.com/320x450/263238/4fc3f7.png&text=Plano+Casa",
        "Oficina / Office": "https://dummyimage.com/320x450/37474f/81c784.png&text=Plano+Oficina"
    }

    def on_plano_change(e):
        seleccion = planos.get(dropdown_planos.value, "")
        if seleccion:
            map_image = ft.Image(src=seleccion, width=320, height=450, fit="contain")
            heatmap_stack.controls[0] = map_image
            page.update()

    dropdown_planos = ft.Dropdown(
        label=get_text(lang, "indoor_title"),
        options=[ft.dropdown.Option(n) for n in planos.keys()],
        value="Mi Plano Real",
        on_change=on_plano_change
    )

    def handle_tap(e: ft.TapEvent):
        val_rssi = sensors.get_wifi_signal()
        color_str = sensors.get_signal_color(val_rssi)
        ft_color = ft.Colors.GREEN if color_str == "green" else (ft.Colors.ORANGE if color_str == "orange" else ft.Colors.RED)
        
        # Coordenadas precisas en APK
        pos_x = e.local_x - 10 if hasattr(e, 'local_x') else 150
        pos_y = e.local_y - 10 if hasattr(e, 'local_y') else 225
        
        dot = ft.Container(
            width=20, height=20, 
            bgcolor=ft_color, 
            border_radius=10, 
            left=pos_x, 
            top=pos_y
        )
        
        heatmap_stack.controls.append(dot)
        database.add_scan("Indoor", dropdown_planos.value, val_rssi, ft_color)
        
        # Feedback visual inmediato
        page.overlay.append(ft.SnackBar(ft.Text(f"✅ Punto añadido - RSSI: {val_rssi} dBm"), open=True, bgcolor=ft_color))
        page.update()

    # Carga automática de tu plano real
    on_plano_change(None)

    return ft.Column([
        ft.Text(get_text(lang, "indoor_title"), size=28, weight="bold", color=ft.Colors.BLUE),
        dropdown_planos,
        ft.GestureDetector(
            on_tap_down=handle_tap,
            content=heatmap_stack
        )
    ], horizontal_alignment="center")
