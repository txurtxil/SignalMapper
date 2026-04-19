import flet as ft
import traceback

def get_history_content(page: ft.Page, lang: str):
    lista_registros = ft.ListView(expand=1, spacing=10, padding=10, auto_scroll=True)
    debug_text = ft.Text("", color=ft.colors.RED_ACCENT, size=12)

    def cargar_historial():
        lista_registros.controls.clear()
        debug_text.value = ""
        try:
            from app.services.database import get_all_scans
            scans = get_all_scans()
            
            if not scans:
                lista_registros.controls.append(ft.Text("Historial vacío. ¡Haz escaneos!", italic=True, color=ft.colors.GREY_500, text_align="center"))
            else:
                for scan in scans:
                    try:
                        tipo = str(scan[1])
                        coords = str(scan[2])
                        rssi = int(scan[3])
                        fecha = str(scan[4]) if len(scan) > 4 else "Sin fecha"
                        
                        # 🔥 SOLUCIÓN: Usar "colors" e "icons" en minúscula 🔥
                        icono_color = ft.colors.GREEN if rssi > -60 else (ft.colors.ORANGE if rssi > -80 else ft.colors.RED)
                        
                        tarjeta = ft.Card(
                            content=ft.ListTile(
                                leading=ft.Icon(ft.icons.WIFI, color=icono_color, size=30),
                                title=ft.Text(f"{tipo} | Señal: {rssi} dBm", weight="bold"),
                                subtitle=ft.Text(f"Ubicación: {coords}\nFecha: {fecha}"),
                            ),
                            color=ft.colors.BLUE_GREY_900
                        )
                        lista_registros.controls.append(tarjeta)
                    except Exception as fila_err:
                        lista_registros.controls.append(ft.Text(f"Dato corrupto: {str(scan)} | Error: {fila_err}", color="red"))
        
        except Exception as e:
            debug_text.value = f"❌ Fallo Interno: {e}"
        
        page.update()

    def borrar_todo():
        try:
            from app.services.database import clear_scans
            clear_scans()
            cargar_historial()
            page.overlay.append(ft.SnackBar(ft.Text("Historial eliminado 🗑️"), open=True))
        except Exception as e:
            debug_text.value = f"❌ Error al borrar: {e}"
        page.update()

    btn_refrescar = ft.ElevatedButton("ACTUALIZAR", icon=ft.icons.REFRESH, on_click=lambda e: cargar_historial(), bgcolor=ft.colors.BLUE_900, color=ft.colors.WHITE)
    btn_borrar = ft.ElevatedButton("BORRAR", icon=ft.icons.DELETE, on_click=lambda e: borrar_todo(), bgcolor=ft.colors.RED_900, color=ft.colors.WHITE)

    cargar_historial()

    return ft.Column([
        ft.Text("Historial de Escaneos", size=26, weight="bold", color=ft.colors.BLUE_400),
        debug_text,
        ft.Row([btn_refrescar, btn_borrar], alignment=ft.MainAxisAlignment.CENTER),
        ft.Container(
            content=lista_registros,
            expand=True,
            border_radius=10,
            border=ft.border.all(1, ft.colors.GREY_800),
            padding=5,
            height=400
        )
    ], horizontal_alignment="center", spacing=15)
