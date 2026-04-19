import sqlite3
import os

# Forzamos una ruta donde Android siempre deja escribir
DB_PATH = os.path.join(os.getcwd(), "signal_v3.db")

def init_db():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS scans 
                 (id INTEGER PRIMARY KEY AUTOINCREMENT, zona TEXT, coords TEXT, rssi INTEGER, fecha TEXT)''')
    conn.commit()
    conn.close()

def add_scan(zona, coords, rssi):
    try:
        init_db()
        import datetime
        ahora = datetime.datetime.now().strftime("%H:%M:%S")
        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()
        c.execute("INSERT INTO scans (zona, coords, rssi, fecha) VALUES (?, ?, ?, ?)", 
                  (str(zona), str(coords), int(rssi), ahora))
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"Error DB: {e}")

def get_all_scans():
    try:
        init_db()
        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()
        c.execute("SELECT zona, coords, rssi, fecha FROM scans ORDER BY id DESC LIMIT 20")
        data = c.fetchall()
        conn.close()
        return data
    except:
        return []

def clear_db():
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.cursor().execute("DELETE FROM scans")
        conn.commit()
        conn.close()
    except:
        pass
