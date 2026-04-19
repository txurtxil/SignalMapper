import flet as ft
from app.services import database

def get_history_content(page: ft.Page, lang: str):
    # Contenedor para la lista de registros
    lista_registros = ft.ListView(expand=1, spacing=10, padding=10, auto_scroll=True)

    def cargar_historial():
        lista_registros.controls.clear()
        try:
            # Intentamos leer la base de datos (adaptable a cómo la tengas creada)
            # Asumimos que tienes una función parecida a get_all_scans()
            if hasattr(database, "get_all_scans"):
                scans = database.get_all_scans()
            else:
                # Si no existe la función, devolvemos un mensaje de aviso
                scans = []
                lista_registros.controls.append(
                    ft.Text("⚠️ Módulo de base de datos no configurado para lectura.", color=ft.Colors.AMBER)
                )

            if not scans and hasattr(database, "get_all_scans"):
                lista_registros.controls.append(
                    ft.Text("El historial está vacío. ¡Haz algunos escaneos!", italic=True, color=ft.Colors.GREY_500, text_align="center")
                )
            
            # Recorremos los escaneos y los pintamos en tarjetas
            for scan in scans:
                # Asumimos un formato genérico tipo: (id, tipo_zona, coordenadas, señal_rssi, fecha)
                try:
                    tipo = str(scan[1])
                    coords = str(scan[2])
                    rssi = int(scan[3])
                    fecha = str(scan[4]) if len(scan) > 4 else "Sin fecha"
                    
                    # Colores según la intensidad
                    icono_color = ft.Colors.GREEN if rssi > -60 else (ft.Colors.ORANGE if rssi > -80 else ft.Colors.RED)
                    
                    tarjeta = ft.Card(
                        content=ft.ListTile(
                            leading=ft.Icon(ft.Icons.WIFI, color=icono_color, size=30),
                            title=ft.Text(f"{tipo} | Señal: {rssi} dBm", weight="bold"),
                            subtitle=ft.Text(f"Ubicación: {coords}\nFecha: {fecha}"),
                        ),
                        color=ft.Colors.BLUE_GREY_900
                    )
                    lista_registros.controls.append(tarjeta)
                except:
                    # Si el formato no coincide, mostramos los datos en crudo para no crashear
                    lista_registros.controls.append(ft.Text(f"Registro: {str(scan)}"))

        except Exception as e:
            lista_registros.controls.append(ft.Text(f"❌ Error al cargar BD: {str(e)}", color=ft.Colors.RED))
        
        page.update()

    # Botón para refrescar
    btn_refrescar = ft.ElevatedButton(
        "ACTUALIZAR HISTORIAL", 
        icon=ft.Icons.REFRESH, 
        on_click=lambda e: cargar_historial(),
        bgcolor=ft.Colors.BLUE_900,
        color=ft.Colors.WHITE
    )

    # Cargamos los datos por primera vez al abrir la pestaña
    cargar_historial()

    return ft.Column([
        ft.Text("Historial de Escaneos", size=28, weight="bold", color=ft.Colors.BLUE_400),
        btn_refrescar,
        ft.Container(
            content=lista_registros,
            expand=True,
            border_radius=10,
            border=ft.border.all(1, ft.Colors.GREY_800),
            padding=5,
            height=400 # Altura fija para asegurar el scroll
        )
    ], horizontal_alignment="center", spacing=20)
