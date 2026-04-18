import flet as ft

def get_outdoor_content(page: ft.Page, lang: str):
    return ft.Column([
        ft.Text("Outdoor (Estable)", size=24, weight="bold", color=ft.Colors.GREEN),
        ft.Text("¡La navegación ha vuelto a la vida!", text_align=ft.TextAlign.CENTER),
        ft.Icon(ft.Icons.CHECK_CIRCLE, color=ft.Colors.GREEN, size=100)
    ], horizontal_alignment="center")
