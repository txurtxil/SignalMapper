import flet as ft
from app.services import database, sensors

def get_outdoor_content(page: ft.Page, lang: str):
    gps_text = ft.Text("GPS: Esperando señal...", size=16, weight="bold", text_align=ft.TextAlign.CENTER)
    coords_text = ft.Text("Lat: 0.0, Lon: 0.0", size=14, italic=True)
    
    # Caja de visualización
    map_box = ft.Container(
        content=ft.Column([gps_text, coords_text], alignment=ft.MainAxisAlignment.CENTER, horizontal_alignment=ft.CrossAxisAlignment.CENTER),
        width=320, height=450, 
        bgcolor=ft.Colors.BLUE_GREY_900, 
        border_radius=10, 
        alignment=ft.alignment.Alignment(0, 0)
    )

    # El componente nativo de GPS
    gl = ft.Geolocator(
        on_position=lambda e: update_ui(e),
        on_error=lambda e: page.overlay.append(ft.SnackBar(ft.Text(f"Error GPS: {e.data}"), open=True))
    )
    page.overlay.append(gl)

    def update_ui(e):
        gps_text.value = "✅ Señal GPS Activa"
        coords_text.value = f"Lat: {e.latitude:.5f}\nLon: {e.longitude:.5f}"
        page.update()

    def handle_scan(e):
        try:
            # Pedimos permiso y activamos el GPS
            gl.request_permission()
            gl.get_current_position()
            
            val_rssi = sensors.get_wifi_signal()
            color_str = sensors.get_signal_color(val_rssi)
            ft_color = ft.Colors.GREEN if color_str == "green" else (ft.Colors.ORANGE if color_str == "orange" else ft.Colors.RED)
            
            # Guardamos con coordenadas reales si están disponibles
            loc_label = f"GPS: {coords_text.value.replace('\n', ' ')}"
            database.add_scan("Outdoor", loc_label, val_rssi, ft_color)
            
            page.overlay.append(ft.SnackBar(ft.Text(f"Escaneo Guardado: {val_rssi} dBm"), open=True, bgcolor=ft_color))
            page.update()
        except Exception as ex:
            page.overlay.append(ft.SnackBar(ft.Text(f"Error: {str(ex)}"), open=True, bgcolor=ft.Colors.RED))

    return ft.Column([
        ft.Text("Modo Outdoor", size=28, weight="bold", color=ft.Colors.GREEN),
        ft.ElevatedButton("Activar GPS y Escanear", icon=ft.Icons.GPS_FIXED, on_click=handle_scan),
        map_box
    ], horizontal_alignment="center")
