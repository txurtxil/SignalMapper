import flet as ft

def get_outdoor_content(page: ft.Page, lang: str):
    log_box = ft.Text("--- LOGS EN VIVO ---\n", size=12, color=ft.Colors.GREENAccent)

    def add_log(msg):
        log_box.value += f"{msg}\n"
        page.update()

    # 1. Asegurar que el Geolocator existe ANTES de hacer nada
    existing_gl = [c for c in page.overlay if isinstance(c, ft.Geolocator)]
    if not existing_gl:
        gl = ft.Geolocator(
            on_position=lambda e: add_log(f"📍 GPS OK: Lat {e.latitude:.4f}, Lon {e.longitude:.4f}"),
            on_error=lambda e: add_log(f"⚠️ Error GPS: {e.data}")
        )
        page.overlay.append(gl)
    else:
        gl = existing_gl[0]

    # 2. Petición separada para que Android respire
    def request_gps(e):
        add_log("⏳ Solicitando permiso a Android...")
        try:
            gl.request_permission()
            gl.get_current_position()
        except Exception as ex:
            add_log(f"❌ Fallo crítico evitado: {str(ex)}")

    return ft.Column([
        ft.Text("Modo Outdoor", size=24, weight="bold", color=ft.Colors.GREEN),
        ft.ElevatedButton("PEDIR PERMISOS Y ESCANEAR", icon=ft.Icons.GPS_FIXED, on_click=request_gps),
        ft.Container(
            content=ft.Column([log_box], scroll="auto"),
            width=320, height=300, bgcolor=ft.Colors.BLACK, border_radius=10, padding=10
        )
    ], horizontal_alignment="center")
