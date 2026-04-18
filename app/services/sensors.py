import random
def get_wifi_signal():
    return random.randint(-90, -40)
def get_signal_color(rssi):
    if rssi > -60: return "green"
    if rssi > -80: return "orange"
    return "red"
