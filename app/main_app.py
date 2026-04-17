import flet as ft
from app.ui.indoor_view import get_indoor_content
from app.ui.outdoor_view import get_outdoor_content
from app.ui.history_view import get_history_content
from app.services import database
from app.localization.strings import get_text

def main(page: ft.Page):
    page.title = "SignalMapper"
    page.theme_mode = ft.ThemeMode.DARK
    
    # === PERMISOS ANDROID (Ubicación + WiFi) ===
    # Se piden al abrir la app en APK
    ph = ft.PermissionHandler()
    page.overlay.append(ph)
    ph.request_permission([
        ft.PermissionType.ACCESS_FINE_LOCATION,
        ft.PermissionType.ACCESS_COARSE_LOCATION,
        ft.PermissionType.ACCESS_WIFI_STATE
    ])
    # ===========================================

    if not hasattr(page, "lang"): 
        page.lang = "es"
    if not hasattr(page, "selected_idx"): 
        page.selected_idx = 0
    
    database.init_db()
    body_container = ft.Container(expand=True)

    def update_ui():
        page.appbar.title.value = get_text(page.lang, "title")
        
        btn_lang = page.appbar.actions[0]
        btn_lang.text = get_text(page.lang, "lang_toggle")
        btn_lang.style = ft.ButtonStyle(color=ft.Colors.WHITE, bgcolor=ft.Colors.BLUE_700)
        
        for i, dest in enumerate(page.navigation_bar.destinations):
            keys = ["nav_indoor", "nav_outdoor", "nav_history"]
            dest.label = get_text(page.lang, keys[i])
        
        idx = page.selected_idx
        if idx == 0: 
            body_container.content = get_indoor_content(page, page.lang)
        elif idx == 1: 
            body_container.content = get_outdoor_content(page, page.lang)
        elif idx == 2: 
            body_container.content = get_history_content(page, page.lang)
        
        page.update()

    def on_lang_click(e):
        page.lang = "en" if page.lang == "es" else "es"
        update_ui()

    def on_nav_change(e):
        page.selected_idx = e.control.selected_index
        update_ui()

    page.appbar = ft.AppBar(
        title=ft.Text(""),
        actions=[ft.TextButton("IDIOMA", on_click=on_lang_click)],
        bgcolor=ft.Colors.BLUE_GREY_800
    )
    
    page.navigation_bar = ft.NavigationBar(
        destinations=[
            ft.NavigationBarDestination(icon=ft.Icons.WIFI),
            ft.NavigationBarDestination(icon=ft.Icons.MAP),
            ft.NavigationBarDestination(icon=ft.Icons.HISTORY),
        ],
        on_change=on_nav_change
    )
    
    page.add(body_container)
    update_ui()

if __name__ == "__main__":
    ft.app(target=main)
