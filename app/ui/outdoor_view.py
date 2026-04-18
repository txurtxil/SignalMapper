import flet as ft
from app.services import database, sensors

def get_outdoor_content(page: ft.Page, lang: str):
    gps_data = ft.Text("GPS inactivo.\nPulsa Escanear para pedir permisos.", text_align=ft.TextAlign.CENTER)
    map_box = ft.Container(content=gps_data, width=320, height=450, bgcolor=ft.Colors.BLUE_GREY_900, border_radius=10, alignment=ft.alignment.center)

    # Buscar si ya existe el geolocator para no duplicarlo al cambiar de pestañas
    geolocators = [c for c in page.overlay if isinstance(c, ft.Geolocator)]
    if not geolocators:
        geolocator = ft.Geolocator(
            on_position=lambda e: update_gps(e),
            on_error=lambda e: error_gps(e)
        )
        page.overlay.append(geolocator)
        page.update()  # ⚠️ CLAVE: Obliga a Android a montar el componente ANTES de pedir permisos
    else:
        geolocator = geolocators[0]

    def update_gps(e):
        gps_data.value = f"✅ GPS Activo\nLat: {e.latitude:.5f}\nLon: {e.longitude:.5f}"
        page.update()

    def error_gps(e):
        page.overlay.append(ft.SnackBar(ft.Text(f"⚠️ Error GPS: Permiso denegado o GPS apagado"), open=True, bgcolor=ft.Colors.RED))
        page.update()

    def handle_scan(e):
        try:
            # 1. Pide permisos de sistema
            geolocator.request_permission()
            # 2. Lee coordenadas
            geolocator.get_current_position()
            
            val_rssi = sensors.get_wifi_signal()
            color_str = sensors.get_signal_color(val_rssi)
            ft_color = ft.Colors.GREEN if color_str == "green" else (ft.Colors.ORANGE if color_str == "orange" else ft.Colors.RED)
            
            database.add_scan("Outdoor", "GPS Nativo", val_rssi, ft_color)
            page.overlay.append(ft.SnackBar(ft.Text(f"✅ RSSI: {val_rssi} dBm Guardado"), open=True, bgcolor=ft_color))
            page.update()
        except Exception as ex:
            page.overlay.append(ft.SnackBar(ft.Text(f"❌ Error Outdoor: {str(ex)}"), open=True, bgcolor=ft.Colors.RED))
            page.update()

    return ft.Column([
        ft.Text("Modo Outdoor", size=28, weight="bold", color=ft.Colors.GREEN),
        ft.ElevatedButton("Conectar GPS y Escanear", icon=ft.Icons.GPS_FIXED, on_click=handle_scan),
        map_box
    ], horizontal_alignment="center")
