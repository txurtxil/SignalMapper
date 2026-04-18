import flet as ft
from app.services.logger import Logger

def get_outdoor_content(page: ft.Page, lang: str):
    Logger.log("Vista Outdoor lista.")
    
    log_box = ft.Text("--- LOGS DE SISTEMA ---\n", size=10, font_family="monospace")
    
    def on_gps_error(e):
        Logger.log(f"GPS ERROR: {e.data}")
        log_box.value = Logger.get_all()
        page.update()

    def on_gps_pos(e):
        Logger.log(f"GPS OK: {e.latitude}, {e.longitude}")
        log_box.value = Logger.get_all()
        page.update()

    # Botón para activar el sistema nativo
    def activate_native(e):
        try:
            Logger.log("Iniciando Geolocator nativo...")
            gl = ft.Geolocator(on_position=on_gps_pos, on_error=on_gps_error)
            page.overlay.append(gl)
            page.update()
            
            Logger.log("Solicitando permisos a Android...")
            gl.request_permission()
        except Exception as ex:
            Logger.log(f"Fallo crítico: {str(ex)}")
        
        log_box.value = Logger.get_all()
        page.update()

    return ft.Column([
        ft.Text("Modo Outdoor", size=24, color=ft.Colors.GREEN),
        ft.ElevatedButton("1. ACTIVAR PERMISOS", icon=ft.Icons.LOCK_OPEN, on_click=activate_native),
        ft.Container(
            content=log_box,
            width=320, height=300, bgcolor=ft.Colors.BLACK,
            padding=10, border_radius=5
        )
    ], horizontal_alignment="center")
