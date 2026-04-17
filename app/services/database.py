import sqlite3
import csv
import os
import tempfile

# En Android buscamos una carpeta temporal que sí tenga permisos de escritura
try:
    writable_dir = os.environ.get("TMPDIR", tempfile.gettempdir())
    DB_PATH = os.path.join(writable_dir, "scans.db")
except:
    DB_PATH = ":memory:" # Salvavidas: si falla, usa la RAM para que la app no crashee

def init_db():
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS scans (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                mode TEXT,
                location TEXT,
                rssi INTEGER,
                color TEXT,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        conn.commit()
        conn.close()
    except Exception as e:
        print("Error BD:", e)

def add_scan(mode, location, rssi, color):
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("INSERT INTO scans (mode, location, rssi, color) VALUES (?, ?, ?, ?)", 
                       (mode, location, rssi, color))
        conn.commit()
        conn.close()
    except:
        pass

def get_history():
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("SELECT mode, location, rssi, timestamp FROM scans ORDER BY timestamp DESC")
        data = cursor.fetchall()
        conn.close()
        return data
    except:
        return []

def export_to_csv():
    try:
        filename = os.path.join(writable_dir, "signal_data.csv")
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM scans")
        rows = cursor.fetchall()
        
        with open(filename, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['ID', 'Modo', 'Ubicación/Plano', 'RSSI (dBm)', 'Color', 'Fecha/Hora'])
            writer.writerows(rows)
        
        conn.close()
        return filename
    except:
        return "Error al exportar"
