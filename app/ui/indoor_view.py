import flet as ft
import json
from app.services import database, sensors
from app.localization.strings import get_text

def get_indoor_content(page: ft.Page, lang: str):
    map_bg = ft.Container(width=320, height=450, bgcolor=ft.Colors.BLUE_GREY_900, border_radius=10)
    heatmap_stack = ft.Stack(controls=[map_bg], width=320, height=450)

    # ✅ RUTA CORRECTA (según documentación oficial de Flet)
    planos = {
        "Mi Plano Real": "plano_real.jpg",
        "Casa / Home": "https://dummyimage.com/320x450/263238/4fc3f7.png&text=Plano+Casa",
        "Oficina / Office": "https://dummyimage.com/320x450/37474f/81c784.png&text=Plano+Oficina"
    }

    def on_plano_change(e):
        # Siempre usamos el valor actual del dropdown (funciona en cambio y en carga inicial)
        seleccion = planos.get(dropdown_planos.value, "")
        heatmap_stack.controls = [map_bg]

        if seleccion:
            nueva_imagen = ft.Image(src=seleccion, width=320, height=450, fit="contain")
            heatmap_stack.controls.append(nueva_imagen)
            map_bg.bgcolor = ft.Colors.TRANSPARENT
        else:
            map_bg.bgcolor = ft.Colors.BLUE_GREY_900
            
        page.update()

    dropdown_planos = ft.Dropdown(
        label=get_text(lang, "indoor_title"),
        options=[ft.dropdown.Option(n) for n in planos.keys()],
        width=250
    )
    dropdown_planos.on_change = on_plano_change

    # ✅ Carga automática del plano real al abrir la pantalla
    dropdown_planos.value = "Mi Plano Real"
    on_plano_change(None)   # fuerza la imagen desde el principio

    def handle_tap(e):
        val_rssi = sensors.get_wifi_signal()
        color_str = sensors.get_signal_color(val_rssi)
        ft_color = ft.Colors.GREEN if color_str == "green" else (ft.Colors.ORANGE if color_str == "orange" else ft.Colors.RED)
        
        x, y = 160, 225
        try:
            if e.data:
                d = json.loads(e.data)
                x = d.get("local_x", 160)
                y = d.get("local_y", 225)
        except: pass
        
        plano_actual = dropdown_planos.value if dropdown_planos.value else "Indoor"
        point_container = ft.Container(width=20, height=20, bgcolor=ft_color, border_radius=10, left=x-10, top=y-10)
        heatmap_stack.controls.append(point_container)
        
        database.add_scan("Indoor", plano_actual, val_rssi, ft_color)
        page.overlay.append(ft.SnackBar(ft.Text(f"RSSI: {val_rssi} dBm"), open=True, bgcolor=ft_color))
        page.update()

    return ft.Column([
        ft.Text(get_text(lang, "indoor_title"), size=28, weight="bold", color=ft.Colors.BLUE),
        dropdown_planos,
        ft.Text(get_text(lang, "indoor_subtitle"), size=14),
        ft.GestureDetector(on_tap_down=handle_tap, content=heatmap_stack)
    ], horizontal_alignment="center")
