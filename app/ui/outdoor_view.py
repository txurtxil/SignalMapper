import flet as ft
from app.services import database, sensors

def get_outdoor_content(page: ft.Page, lang: str):
    # Textos de estado
    status_text = ft.Text("GPS: Esperando activación...", size=16, weight="bold", color=ft.Colors.GREY_400)
    coords_text = ft.Text("Lat: --- \nLon: ---", size=14, text_align=ft.TextAlign.CENTER)
    
    # Mapa placeholder (se actualizará con las coordenadas reales)
    map_image = ft.Image(
        src="https://dummyimage.com/320x300/263238/4fc3f7.png&text=Esperando+GPS...", 
        width=320, height=300, fit="cover", border_radius=10
    )

    # Función que se ejecuta cuando el GPS consigue señal
    def on_position_change(e):
        lat = e.latitude
        lon = e.longitude
        status_text.value = "✅ GPS Conectado y Mapeando"
        status_text.color = ft.Colors.GREEN
        coords_text.value = f"Lat: {lat:.5f} | Lon: {lon:.5f}"
        
        # 🚀 MAGIA: Usamos OpenStreetMap para generar un mapa real con tu ubicación
        map_url = f"https://staticmap.openstreetmap.de/staticmap.php?center={lat},{lon}&zoom=17&size=320x300&maptype=mapnik&markers={lat},{lon},red-pushpin"
        map_image.src = map_url
        
        # Opcional: Guardar automáticamente el escaneo
        rssi = sensors.get_wifi_signal()
        color = ft.Colors.GREEN if rssi > -60 else (ft.Colors.ORANGE if rssi > -80 else ft.Colors.RED)
        database.add_scan("Outdoor", f"{lat:.4f}, {lon:.4f}", rssi, "color")
        
        page.update()

    def on_error(e):
        status_text.value = f"❌ Error GPS: {e.data}"
        status_text.color = ft.Colors.RED
        page.update()

    # Inyectar Geolocator de forma segura (solo si no existe ya)
    if not any(isinstance(c, ft.Geolocator) for c in page.overlay):
        geolocator = ft.Geolocator(on_position=on_position_change, on_error=on_error)
        page.overlay.append(geolocator)
    else:
        geolocator = next(c for c in page.overlay if isinstance(c, ft.Geolocator))

    def handle_activate(e):
        status_text.value = "⏳ Pidiendo permisos a Android..."
        status_text.color = ft.Colors.AMBER
        page.update()
        try:
            geolocator.request_permission()
            # Leemos la ubicación actual
            geolocator.get_current_position()
        except Exception as ex:
            status_text.value = f"❌ Fallo: {str(ex)}"
            status_text.color = ft.Colors.RED
            page.update()

    return ft.Column([
        ft.Text("Modo Outdoor", size=28, weight="bold", color=ft.Colors.GREEN),
        ft.ElevatedButton("Activar GPS y Mapear", icon=ft.Icons.MAP, on_click=handle_activate, bgcolor=ft.Colors.BLUE_900, color=ft.Colors.WHITE),
        status_text,
        coords_text,
        ft.Container(
            content=map_image, 
            border_radius=10, 
            border=ft.border.all(2, ft.Colors.BLUE_GREY_800),
            padding=2
        )
    ], horizontal_alignment="center")
