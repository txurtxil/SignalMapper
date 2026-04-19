import sqlite3

# Usamos un archivo de base de datos nuevo por si el anterior se quedó corrupto
DB_PATH = "signalmapper_v2.db"

def init_db():
    try:
        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()
        c.execute('''
            CREATE TABLE IF NOT EXISTS scans (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                tipo TEXT,
                coordenadas TEXT,
                rssi INTEGER,
                fecha TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        conn.commit()
        conn.close()
    except Exception as e:
        print("Error BD init:", e)

def add_scan(tipo, coordenadas, rssi, color=""):
    try:
        init_db()
        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()
        c.execute("INSERT INTO scans (tipo, coordenadas, rssi) VALUES (?, ?, ?)", 
                  (str(tipo), str(coordenadas), int(rssi)))
        conn.commit()
        conn.close()
    except Exception as e:
        print("Error BD add:", e)

def get_all_scans():
    try:
        init_db()
        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()
        c.execute("SELECT id, tipo, coordenadas, rssi, datetime(fecha, 'localtime') FROM scans ORDER BY id DESC")
        rows = c.fetchall()
        conn.close()
        return rows
    except Exception as e:
        # Si la consulta falla, devuelve el error como si fuera un escaneo para que lo leamos
        return [(0, "ERROR", str(e), 0, "Fallo Base Datos")]

def clear_scans():
    try:
        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()
        c.execute("DELETE FROM scans")
        conn.commit()
        conn.close()
    except:
        pass
