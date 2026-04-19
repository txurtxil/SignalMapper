import flet as ft
from app.services import database

def get_history_content(page: ft.Page, lang: str):
    lv = ft.ListView(expand=1, spacing=10, padding=10)

    def refrescar(e=None):
        lv.controls.clear()
        datos = database.get_all_scans()
        
        if not datos:
            lv.controls.append(ft.Text("El historial está vacío.", italic=True, color="grey", text_align="center"))
        else:
            for fila in datos:
                try:
                    zona, coords, rssi, fecha = fila
                    # Usamos strings en vez de variables para asegurar la compatibilidad
                    color_icono = "green" if int(rssi) > -60 else ("orange" if int(rssi) > -80 else "red")
                    
                    lv.controls.append(
                        ft.Card(
                            content=ft.ListTile(
                                leading=ft.Icon("wifi", color=color_icono, size=30),
                                title=ft.Text(f"{zona} | Señal: {rssi} dBm", weight="bold"),
                                subtitle=ft.Text(f"Ubicación: {coords}\nFecha: {fecha}")
                            ),
                            color="#1E293B" # Color gris azulado oscuro para el fondo de la tarjeta
                        )
                    )
                except Exception as err:
                    lv.controls.append(ft.Text(f"Fila corrupta: {fila}", color="red"))
        page.update()

    # Cargar los datos nada más abrir la pestaña
    refrescar()

    return ft.Column([
        ft.Text("Historial de Escaneos", size=26, weight="bold", color="blue"),
        ft.Row([
            ft.ElevatedButton("ACTUALIZAR", icon="refresh", on_click=refrescar, bgcolor="blue", color="white"),
            ft.ElevatedButton("BORRAR", icon="delete", on_click=lambda _: [database.clear_db(), refrescar()], bgcolor="red", color="white")
        ], alignment="center"),
        ft.Container(content=lv, expand=True, border_radius=10, border=ft.border.all(1, "grey"))
    ], horizontal_alignment="center", spacing=15)
