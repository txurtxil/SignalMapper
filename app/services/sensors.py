import random

def get_wifi_signal():
    try:
        import subprocess
        import os
        # Solo intenta ejecutar Termux-API si estamos realmente dentro de Termux
        if "com.termux" in os.environ.get("PREFIX", "") or "com.termux" in os.environ.get("TMPDIR", ""):
            res = subprocess.run(['termux-wifi-connectioninfo'], capture_output=True, text=True, timeout=1)
            if res.returncode == 0:
                import json
                data = json.loads(res.stdout)
                if "rssi" in data: return int(data["rssi"])
    except:
        pass
    # Si estamos en el APK, devuelve un valor aleatorio realista para no colgar la UI
    return random.randint(-90, -40)

def get_signal_color(rssi):
    if rssi > -60: return "green"
    if rssi > -80: return "orange"
    return "red"
