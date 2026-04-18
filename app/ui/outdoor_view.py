import flet as ft
from app.services import database, sensors
from app.services.logger import Logger

def get_outdoor_content(page: ft.Page, lang: str):
    Logger.log("Cargando vista Outdoor...")
    status_text = ft.Text("Estado GPS: Esperando comando", size=14)

    gl = ft.Geolocator(
        on_position=lambda e: Logger.log(f"GPS Actualizado: {e.latitude}, {e.longitude}"),
        on_error=lambda e: Logger.log(f"ERROR GPS NATIVO: {e.data}")
    )
    page.overlay.append(gl)

    def start_geo(e):
        Logger.log("Solicitando permisos de ubicación a Android...")
        try:
            gl.request_permission()
            gl.get_current_position()
            status_text.value = "✅ Solicitud enviada"
            page.update()
        except Exception as ex:
            Logger.log(f"Fallo al solicitar permisos: {str(ex)}")

    # BOTÓN DE LOGS (Para ver qué está pasando)
    def show_logs(e):
        Logger.log("Abriendo visor de logs...")
        page.dialog = ft.AlertDialog(
            title=ft.Text("Debug Logs"),
            content=ft.Text(Logger.get_logs(), size=10, font_family="monospace"),
            scrollable=True
        )
        page.dialog.open = True
        page.update()

    return ft.Column([
        ft.Text("Modo Outdoor", size=24, weight="bold", color=ft.Colors.GREEN),
        ft.ElevatedButton("Pedir Permisos / Escanear", icon=ft.Icons.GPS_FIXED, on_click=start_geo),
        ft.ElevatedButton("Ver LOGS del Sistema", icon=ft.Icons.TERMINAL, on_click=show_logs, bgcolor=ft.Colors.BLUE_GREY_900),
        status_text,
    ], horizontal_alignment="center")
