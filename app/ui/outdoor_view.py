import flet as ft
import urllib.request
import json
import ssl
from app.services import database, sensors

def get_outdoor_content(page: ft.Page, lang: str):
    try:
        status = ft.Text("Listo para escanear", color="grey")
        
        # Corrección: ft.BoxFit en lugar de ft.ImageFit
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

        def ubicar_con_gps_nativo(e):
            """
            Intentamos usar ft.Location (API Nativa) primero.
            Si falla o no existe, usamos el fallback de IP.
            """
            status.value = "⏳ Activando GPS Nativo..."
            status.color = "orange"
            status.update()

            # Verificamos si ft.Location está disponible (Flet 0.8+)
            if hasattr(ft, 'Location'):
                location = ft.Location()
                
                def on_change(e: ft.LocationChangeEvent):
                    if e.latitude and e.longitude:
                        procesar_ubicacion(str(e.latitude), str(e.longitude), "GPS Nativo")
                        location.stop_updates()
                    else:
                        status.value = "❌ Esperando señal GPS..."
                        status.update()

                def on_error(e: ft.LocationPermissionError):
                    status.value = "❌ Permiso denegado. Activa el GPS en Ajustes."
                    status.color = "red"
                    status.update()
                    # Fallback a IP si falla el permiso
                    obtener_por_ip()

                location.on_change = on_change
                location.on_permission_error = on_error
                
                try:
                    location.request_permission()
                    location.start_updates()
                except Exception as ex:
                    status.value = f"❌ Error iniciando GPS: {ex}"
                    status.color = "red"
                    status.update()
                    obtener_por_ip()
            else:
                # Si la versión de Flet es antigua, usamos IP directamente
                status.value = "⚠️ Versión Flet antigua. Usando ubicación por Red."
                status.color = "yellow"
                status.update()
                obtener_por_ip()

        def obtener_por_ip():
            """Fallback rápido si el GPS falla"""
            status.value = "🌐 Obteniendo ubicación por Red (IP)..."
            status.update()
            
            def task_ip():
                try:
                    ctx = ssl.create_default_context()
                    ctx.check_hostname = False
                    ctx.verify_mode = ssl.CERT_NONE
                    
                    # Usamos ipapi.co que suele ser más preciso que ipinfo para lat/lon directos
                    req = urllib.request.Request("https://ipapi.co/json/", headers={'User-Agent': 'Mozilla/5.0'})
                    with urllib.request.urlopen(req, timeout=5, context=ctx) as r:
                        data = json.loads(r.read().decode())
                        lat = str(data['latitude'])
                        lon = str(data['longitude'])
                        
                        page.run_thread(lambda: procesar_ubicacion(lat, lon, "Red (IP)"))
                        
                except Exception as ex:
                    page.run_thread(lambda: mostrar_error(f"Fallo de Red: {str(ex)}"))

            import threading
            threading.Thread(target=task_ip, daemon=True).start()

        def procesar_ubicacion(lat, lon, fuente):
            """Actualiza UI y Mapa"""
            try:
                # Guardar en BD
                rssi = sensors.get_wifi_signal()
                database.add_scan(f"Outdoor ({fuente})", f"{lat[:7]},{lon[:7]}", rssi)
                
                # Calcular BBox para Zoom
                lat_f, lon_f = float(lat), float(lon)
                offset = 0.0015 
                bbox = f"{lon_f-offset},{lat_f-offset},{lon_f+offset},{lat_f+offset}"
                url_mapa = f"https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/export?bbox={bbox}&bboxSR=4326&imageSR=4326&size=320,300&f=image"
                
                map_img.src = url_mapa
                status.value = f"✅ Ubicación ({fuente}): {lat[:7]}, {lon[:7]}\n💾 Guardado"
                status.color = "green"
                page.update()
                
            except Exception as ex:
                mostrar_error(f"Error al procesar: {str(ex)}")

        def mostrar_error(msg):
            status.value = f"❌ {msg}"
            status.color = "red"
            status.update()

        return ft.Column([
            ft.Text("Mapeo Outdoor (Precisión)", size=24, weight="bold", color="green"),
            ft.ElevatedButton("ESCANEAR UBICACIÓN EXACTA", icon="gps_fixed", on_click=ubicar_con_gps_nativo, bgcolor="blue", color="white"),
            status,
            ft.Container(content=map_stack, border=ft.border.all(2, "grey"), border_radius=10)
        ], horizontal_alignment="center", spacing=15)

    except Exception as e:
        return ft.Text(f"Fallo grave: {str(e)}", color="red")
