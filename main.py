import flet as ft
from app.main_app import main

if __name__ == "__main__":
    # Arrancamos sin florituras para máxima compatibilidad
    ft.app(target=main, assets_dir="assets")
