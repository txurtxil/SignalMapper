import flet as ft
from app.main_app import main

if __name__ == "__main__":
    # En APK, solo la palabra "assets" es necesaria
    ft.app(target=main, assets_dir="assets")
