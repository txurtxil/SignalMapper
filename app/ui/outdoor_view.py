import flet as ft
from app.services import database, sensors

def get_outdoor_content(page: ft.Page, lang: str):
    status_text = ft.Text("GPS: Esperando...", size=16, weight="bold", color=ft.Colors.GREY_400)
    coords_text = ft.Text("Lat: --- \nLon: ---", size=14, text_align=ft.TextAlign.CENTER)
    
    map_image = ft.Image(
        src="https://dummyimage.com/320x300/263238/4fc3f7.png&text=Mapa+Pendiente", 
        width=320, height=300, fit="cover", border_radius=10
    )

    # Solo añadimos el Geolocator si no está ya en la pantalla
    if not any(isinstance(c, ft.Geolocator) for c in page.overlay):
        geolocator = ft.Geolocator(
            on_position=lambda e: update_map(e.latitude, e.longitude),
            on_error=lambda e: show_error(f"Error GPS: {e.data}")
        )
        page.overlay.append(geolocator)
    else:
        geolocator = next(c for c in page.overlay if isinstance(c, ft.Geolocator))

    def update_map(lat, lon):
        status_text.value = "✅ GPS Conectado"
        status_text.color = ft.Colors.GREEN
        coords_text.value = f"Lat: {lat:.5f} | Lon: {lon:.5f}"
        # Descarga el mapa de OpenStreetMap
        map_image.src = f"https://staticmap.openstreetmap.de/staticmap.php?center={lat},{lon}&zoom=17&size=320x300&maptype=mapnik&markers={lat},{lon},red-pushpin"
        
        rssi = sensors.get_wifi_signal()
        color = ft.Colors.GREEN if rssi > -60 else ft.Colors.RED
        database.add_scan("Outdoor", f"{lat:.4f}, {lon:.4f}", rssi, "color")
        page.update()

    def show_error(msg):
        status_text.value = msg
        status_text.color = ft.Colors.RED
        page.update()

    def handle_real_gps(e):
        status_text.value = "⏳ Buscando satélites..."
        status_text.color = ft.Colors.AMBER
        page.update()
        try:
            # Pedir directamente la posición dispara el permiso automáticamente en Flet
            geolocator.get_current_position()
        except Exception as ex:
            show_error(str(ex))

    def handle_fake_gps(e):
        # Simula estar en el centro de Madrid para que veas el mapa funcionar
        update_map(40.4168, -3.7038)

    return ft.Column([
        ft.Text("Outdoor (Map Fix)", size=28, weight="bold", color=ft.Colors.GREEN),
        ft.Row([
            ft.ElevatedButton("Usar GPS Real", icon=ft.Icons.GPS_FIXED, on_click=handle_real_gps, bgcolor=ft.Colors.BLUE_900, color=ft.Colors.WHITE),
            ft.ElevatedButton("Simular Mapa", icon=ft.Icons.MAP, on_click=handle_fake_gps)
        ], alignment=ft.MainAxisAlignment.CENTER),
        status_text,
        coords_text,
        ft.Container(content=map_image, border_radius=10, border=ft.border.all(2, ft.Colors.BLUE_GREY_800), padding=2)
    ], horizontal_alignment="center")
