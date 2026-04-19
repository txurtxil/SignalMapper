import flet as ft
from app.services import database, sensors

def get_outdoor_content(page: ft.Page, lang: str):
    try:
        status = ft.Text("Listo para escanear", color="grey")
        
        map_img = ft.Image(
            src="https://dummyimage.com/320x300/263238/ffffff.png&text=Esperando...", 
            width=320, height=300, border_radius=10, fit=ft.BoxFit.COVER
        )
        
        pin_emoji = ft.Container(
            content=ft.Text("📍", size=45),
            left=137, 
            top=110,  
        )

        map_stack = ft.Stack(
            controls=[map_img, pin_emoji],
            width=320, height=300
        )

        def ubicar(e):
            status.value = "⏳ Solicitando permiso de ubicación..."
            status.color = "orange"
            status.update() 
            
            # 🔥 SOLUCIÓN DEFINITIVA: Usamos ft.Location de Flet (API nativa del SO)
            location = ft.Location()
            
            def on_location_change(e: ft.LocationChangeEvent):
                if e.latitude and e.longitude:
                    lat = str(e.latitude)
                    lon = str(e.longitude)
                    
                    # Guardamos en la base de datos
                    try:
                        rssi = sensors.get_wifi_signal()
                        database.add_scan("Outdoor", f"{lat[:7]},{lon[:7]}", rssi)
                    except:
                        pass
                    
                    # Mapa Zoom X3
                    lat_f, lon_f = float(lat), float(lon)
                    offset = 0.0015 
                    bbox = f"{lon_f-offset},{lat_f-offset},{lon_f+offset},{lat_f+offset}"
                    url_mapa = f"https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/export?bbox={bbox}&bboxSR=4326&imageSR=4326&size=320,300&f=image"
                    
                    map_img.src = url_mapa
                    map_img.update()
                    
                    status.value = f"✅ Ubicación GPS: {lat}, {lon}\n💾 Guardado"
                    status.color = "green"
                    status.update()
                    
                    # Detenemos la actualización continua después de obtener la primera lectura
                    location.stop_updates()
                else:
                    status.value = "❌ No se pudo obtener ubicación GPS"
                    status.color = "red"
                    status.update()
                    location.stop_updates()

            def on_permission_error(e: ft.LocationPermissionError):
                status.value = "❌ Permiso de ubicación denegado. Actívalo en Ajustes."
                status.color = "red"
                status.update()

            # Registramos los callbacks
            location.on_change = on_location_change
            location.on_permission_error = on_permission_error
            
            # Solicitamos permisos y comenzamos la actualización
            try:
                location.request_permission()
                location.start_updates()
            except Exception as ex:
                status.value = f"❌ Error al iniciar GPS: {str(ex)}"
                status.color = "red"
                status.update()

        return ft.Column([
            ft.Text("Mapeo Outdoor (GPS Real)", size=24, weight="bold", color="green"),
            ft.ElevatedButton("ESCANEAR UBICACIÓN EXACTA", icon="wifi", on_click=ubicar, bgcolor="blue", color="white"),
            status,
            ft.Container(content=map_stack, border=ft.border.all(2, "grey"), border_radius=10)
        ], horizontal_alignment="center", spacing=15)

    except Exception as e:
        return ft.Text(f"Fallo grave: {str(e)}", color="red")
