import subprocess
import json
import random

def get_wifi_signal():
    """
    Intenta obtener el RSSI real vía Termux:API.
    Si falla, devuelve un valor simulado para desarrollo.
    """
    try:
        # Comando de Termux:API para info de red
        res = subprocess.run(['termux-wifi-connectioninfo'], capture_output=True, text=True, timeout=2)
        if res.returncode == 0:
            data = json.loads(res.stdout)
            rssi = data.get("rssi")
            if rssi is not None:
                return int(rssi)
    except:
        pass
    
    # Si no estamos en Android/Termux, simulamos para no romper la UI
    return random.randint(-90, -30)

def get_signal_color(rssi):
    if rssi > -60: return "green"
    if rssi > -80: return "orange"
    return "red"
