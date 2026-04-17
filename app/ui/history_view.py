import flet as ft
from app.services import database
from app.localization.strings import get_text

def get_history_content(page: ft.Page, lang: str):
    history = database.get_history()
    
    def handle_export(e):
        path = database.export_to_csv()
        # ✅ URL CORRECTA: Flet sirve los assets en /assets/
        download_url = f"http://localhost:8090/assets/{path}"
        
        page.overlay.append(ft.SnackBar(
            ft.Text(f"✅ CSV Exportado: {path}"), 
            open=True, 
            action="ABRIR",
            on_action=lambda _: page.launch_url(download_url)
        ))
        page.update()

    rows = []
    for item in history:
        rows.append(ft.DataRow(cells=[
            ft.DataCell(ft.Text(item[0])),                    # Modo
            ft.DataCell(ft.Text(item[1])),                    # Ubicación
            ft.DataCell(ft.Text(str(item[2]))),               # RSSI
            ft.DataCell(ft.Text(item[3][5:16])),              # Fecha/Hora
        ]))

    return ft.Column([
        ft.Row([
            ft.Text(get_text(lang, "history_title"), size=28, weight="bold"),
            ft.IconButton(
                icon=ft.Icons.FILE_DOWNLOAD, 
                on_click=handle_export, 
                icon_color="green", 
                tooltip="Exportar CSV"
            )
        ], alignment="spaceBetween"),
        ft.DataTable(
            columns=[
                ft.DataColumn(ft.Text("Modo")),
                ft.DataColumn(ft.Text("Loc")),
                ft.DataColumn(ft.Text("dBm")),
                ft.DataColumn(ft.Text("Fecha")),
            ],
            rows=rows,
            heading_row_color=ft.Colors.BLUE_GREY_900
        )
    ], scroll="auto", horizontal_alignment="center")
