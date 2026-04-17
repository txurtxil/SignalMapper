import sqlite3
import csv
import os

DB_PATH = "scans.db"

def init_db():
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

def add_scan(mode, location, rssi, color):
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("INSERT INTO scans (mode, location, rssi, color) VALUES (?, ?, ?, ?)", 
                   (mode, location, rssi, color))
    conn.commit()
    conn.close()

def get_history():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT mode, location, rssi, timestamp FROM scans ORDER BY timestamp DESC")
    data = cursor.fetchall()
    conn.close()
    return data

def export_to_csv():
    """Genera un CSV en la carpeta assets/exports/"""
    os.makedirs("assets/exports", exist_ok=True)
    filename = "assets/exports/signal_data.csv"
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM scans")
    rows = cursor.fetchall()
    
    with open(filename, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['ID', 'Modo', 'Ubicación/Plano', 'RSSI (dBm)', 'Color', 'Fecha/Hora'])
        writer.writerows(rows)
    
    conn.close()
    return "exports/signal_data.csv"
