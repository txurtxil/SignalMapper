import flet as ft
from app.main_app import main

if __name__ == "__main__":
    ft.run(main, view=ft.AppView.WEB_BROWSER, port=8090, assets_dir="assets")
