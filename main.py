import flet as ft
from app.main_app import main

# Al quitar WEB_BROWSER, Flet usará su motor nativo en el APK
if __name__ == "__main__":
    ft.app(target=main, assets_dir="assets")
