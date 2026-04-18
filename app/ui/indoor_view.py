import flet as ft
from app.services import database, sensors

def get_indoor_content(page: ft.Page, lang: str):
    # Capa exclusiva para almacenar los puntos dibujados
    points_layer = ft.Stack(width=320, height=450)

    # Función a prueba de bombas
    def handle_tap(e: ft.TapEvent):
        try:
            # 1. Obtenemos datos
            rssi = sensors.get_wifi_signal()
            color = ft.Colors.GREEN if rssi > -60 else (ft.Colors.ORANGE if rssi > -80 else ft.Colors.RED)
            
            # 2. Coordenadas garantizadas por GestureDetector
            x = e.local_x
            y = e.local_y
            
            # 3. Dibujamos el punto
            dot = ft.Container(
                width=16, height=16, 
                bgcolor=color, border_radius=8, 
                left=x - 8, top=y - 8
            )
            points_layer.controls.append(dot)
            
            # 4. Guardado en Base de Datos (protegido por si la BD está bloqueada)
            try:
                database.add_scan("Indoor", "Plano", rssi, "color")
            except Exception as db_err:
                print("Ignorando error DB:", db_err)
            
            # 5. Mostramos éxito
            page.overlay.append(ft.SnackBar(ft.Text(f"✅ Punto dibujado: {rssi} dBm"), open=True, bgcolor=color))
            page.update()
            
        except Exception as ex:
            # Si algo explota, lo mostramos pero NO COLGAMOS LA APP
            page.overlay.append(ft.SnackBar(ft.Text(f"❌ Error interno: {str(ex)}"), open=True, bgcolor=ft.Colors.RED))
            page.update()

    # El detector táctil nativo
    touch_area = ft.GestureDetector(
        on_tap_down=handle_tap,
        content=ft.Container(width=320, height=450, bgcolor=ft.Colors.TRANSPARENT)
    )

    return ft.Column([
        ft.Text("Indoor (Blindado)", size=24, weight="bold", color=ft.Colors.BLUE),
        ft.Stack([
            # Fondo de la casa
            ft.Image(src="plano_real.jpg", width=320, height=450, fit="contain"),
            # Puntos
            points_layer,
            # Detector táctil transparente encima de todo
            touch_area
        ], width=320, height=450)
    ], horizontal_alignment="center")
