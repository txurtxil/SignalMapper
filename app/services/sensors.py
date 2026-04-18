import random

def get_wifi_signal():
    # ¡CERO SUBPROCESS! Android no nos matará la app.
    return random.randint(-90, -40)

def get_signal_color(rssi):
    if rssi > -60: return "green"
    if rssi > -80: return "orange"
    return "red"
