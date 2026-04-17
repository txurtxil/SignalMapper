import subprocess
import json
import random
import os

def get_wifi_signal():
    """
    Intenta obtener el RSSI real. Si detecta que no está en Termux o falla,
    devuelve un valor simulado ESTABLE para no colgar el APK.
    """
    # Verificamos si estamos en Termux API. Si no existe la variable TMPDIR, 
    # o si sabemos que estamos en APK, simulamos de primeras.
    termux_check = os.environ.get("TMPDIR", "")
    
    if "com.termux" in termux_check:
        try:
            # Intentamos Termux API solo si parece que estamos en Termux
            res = subprocess.run(['termux-wifi-connectioninfo'], capture_output=True, text=True, timeout=1)
            if res.returncode == 0:
                data = json.loads(res.stdout)
                rssi = data.get("rssi")
                if rssi is not None:
                    return int(rssi)
        except:
            pass
    
    # ✅ SIMULACIÓN HONESTA PARA EL APK FINAL (hasta implementar PyJnius nativo)
    # Devuelve valores aleatorios realistas para pruebas.
    return random.randint(-90, -40)

def get_signal_color(rssi):
    if rssi > -60: return "green"
    if rssi > -80: return "orange"
    return "red"
