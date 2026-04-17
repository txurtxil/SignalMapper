TRANSLATIONS = {
    "es": {
        "title": "SignalMapper",
        "nav_indoor": "Indoor",
        "nav_outdoor": "Outdoor",
        "nav_history": "Historial",
        "indoor_title": "Modo Indoor",
        "indoor_subtitle": "Toca el plano para escanear:",
        "outdoor_title": "Modo Outdoor",
        "outdoor_subtitle": "Mapa interactivo (OSM):",
        "history_title": "Escaneos Guardados",
        "history_empty": "Sin datos. ¡Escanea algo!",
        "scan_saved": "Guardado",
        "lang_toggle": "EN"
    },
    "en": {
        "title": "SignalMapper",
        "nav_indoor": "Indoor",
        "nav_outdoor": "Outdoor",
        "nav_history": "History",
        "indoor_title": "Indoor Mode",
        "indoor_subtitle": "Tap the floorplan to scan:",
        "outdoor_title": "Outdoor Mode",
        "outdoor_subtitle": "Interactive Map (OSM):",
        "history_title": "Saved Scans",
        "history_empty": "No data. Go scan something!",
        "scan_saved": "Saved",
        "lang_toggle": "ES"
    }
}

def get_text(lang, key):
    # Función de utilidad para obtener traducciones
    if lang not in TRANSLATIONS:
        lang = "en"
    return TRANSLATIONS[lang].get(key, key)
