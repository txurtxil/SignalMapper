import flet as ft
from app.services import database, sensors
from app.services.logger import Logger

def get_outdoor_content(page: ft.Page, lang: str):
    Logger.log("Cargando Outdoor...")
    
    log_display = ft.Text("Esperando acción...", size=12, color=ft.Colors.GREY_400)
    
    # Localizador nativo
    gl = ft.Geolocator(
        on_position=lambda e: Logger.log(f"GPS: {e.latitude}, {e.longitude}"),
        on_error=lambda e: Logger.log(f"Error GPS: {e.data}")
    )
    if gl not in page.overlay: page.overlay.append(gl)

    def start_scan(e):
        try:
            Logger.log("Pidiendo permiso GPS...")
            gl.request_permission()
            gl.get_current_position()
            log_display.value = Logger.get_all()
            page.update()
        except Exception as ex:
            Logger.log(f"Error Scan: {str(ex)}")
            log_display.value = Logger.get_all()
            page.update()

    return ft.Column([
        ft.Text("Modo Outdoor", size=24, weight="bold", color=ft.Colors.GREEN),
        ft.ElevatedButton("Pedir Permisos / Escanear", icon=ft.Icons.GPS_FIXED, on_click=start_scan),
        ft.Container(
            content=ft.Column([
                ft.Text("DEBUG LOGS", weight="bold", size=10),
                log_display
            ], scroll="auto"),
            width=320, height=350, bgcolor=ft.Colors.BLACK, border_radius=10, padding=10,
            alignment=ft.alignment.Alignment(0, 0) # ✅ Fix de alignment
        )
    ], horizontal_alignment="center")
