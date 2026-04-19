import flet as ft
from app.services import database

def get_history_content(page: ft.Page, lang: str):
    lv = ft.ListView(expand=1, spacing=10, padding=10)

    def refrescar(e=None):
        lv.controls.clear()
        datos = database.get_all_scans()
        if not datos:
            lv.controls.append(ft.Text("No hay datos aún", italic=True, color="grey"))
        for zona, coords, rssi, fecha in datos:
            color = ft.colors.GREEN if rssi > -60 else ft.colors.RED
            lv.controls.append(
                ft.Card(ft.ListTile(
                    leading=ft.Icon(ft.icons.WIFI, color=color),
                    title=ft.Text(f"{zona} | {rssi} dBm"),
                    subtitle=ft.Text(f"{coords} | {fecha}")
                ))
            )
        page.update()

    return ft.Column([
        ft.Text("Historial", size=24, weight="bold", color=ft.colors.BLUE),
        ft.Row([
            ft.IconButton(ft.icons.REFRESH, on_click=refrescar),
            ft.IconButton(ft.icons.DELETE_FOREVER, on_click=lambda _: [database.clear_db(), refrescar()])
        ], alignment="center"),
        ft.Container(content=lv, expand=True)
    ], horizontal_alignment="center")
