import flet as ft
import threading
from app.services import database, sensors

def get_outdoor_content(page: ft.Page, lang: str):
    try:
        status = ft.Text("Listo para escanear", color="grey")
        
        map_img = ft.Image(
            src="https://dummyimage.com/320x300/263238/ffffff.png&text=Esperando...", 
            width=320, height=300, border_radius=10, fit=ft.ImageFit.COVER
        )
        
        # Emoji de chincheta ajustado milimétricamente
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
            status.value = "⏳ Solicitando permiso de GPS preciso..."
            status.color = "orange"
            status.update() 
            
            def task():
                try:
                    lat, lon = None, None
                    
                    # 🔥 SOLUCIÓN DE PRECISIÓN: Usamos HTML5 Geolocation nativo del dispositivo
                    # Esto obliga al dispositivo a activar el chip GPS/WiFi triangulación fina
                    js_code = """
                        navigator.geolocation.getCurrentPosition(
                            pos => JSON.stringify({lat: pos.coords.latitude, lon: pos.coords.longitude}),
                            err => JSON.stringify({error: err.message}),
                            { enableHighAccuracy: true, maximumAge: 0, timeout: 10000 }
                        );
                    """

                    # Ejecutamos JS y esperamos respuesta sincronizada en el bucle de Flet
                    raw_result = page.run_javascript(js_code)
                    import json
                    res = json.loads(raw_result)

                    if 'error' in res:
                        raise Exception(f"Error de GPS: {res['error']}")
                    
                    lat = str(res['lat'])
                    lon = str(res['lon'])
                    
                    # Verificar que tenemos datos válidos
                    if not lat or not lon:
                        raise Exception("No se pudieron obtener coordenadas.")

                    # Guardamos en la base de datos de forma invisible
                    rssi = sensors.get_wifi_signal()
                    database.add_scan("Outdoor", f"{lat[:7]},{lon[:7]}", rssi)
                    
                    # Mapa Zoom X3 (Lógica idéntica previa)
                    lat_f, lon_f = float(lat), float(lon)
                    offset = 0.0015 
                    bbox = f"{lon_f-offset},{lat_f-offset},{lon_f+offset},{lat_f+offset}"
                    url_mapa = f"https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/export?bbox={bbox}&bboxSR=4326&imageSR=4326&size=320,300&f=image"
                    
                    map_img.src = url_mapa
                    map_img.update()
                    
                    status.value = f"✅ Precisión: {lat}, {lon}\n💾 Guardado en historial"
                    status.color = "green"
                    status.update()
                    
                except Exception as ex:
                    status.value = f"❌ Error: {str(ex)}\n(Asegúrate de dar permisos de ubicación)"
                    status.color = "red"
                    status.update()

            threading.Thread(target=task, daemon=True).start()

        return ft.Column([
            ft.Text("Mapeo Outdoor (Precisión)", size=24, weight="bold", color="green"),
            ft.ElevatedButton("ESCANEAR UBICACIÓN EXACTA", icon="wifi", on_click=ubicar, bgcolor="blue", color="white"),
            status,
            ft.Container(content=map_stack, border=ft.border.all(2, "grey"), border_radius=10)
        ], horizontal_alignment="center", spacing=15)

    except Exception as e:
        return ft.Text(f"Fallo grave: {str(e)}", color="red")
