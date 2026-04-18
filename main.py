import flet as ft
from app.main_app import main
from app.services.logger import Logger

if __name__ == "__main__":
    Logger.log("Iniciando App SignalMapper...")
    ft.app(target=main, assets_dir="assets")
