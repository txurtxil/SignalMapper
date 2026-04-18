import datetime

class Logger:
    logs = []

    @classmethod
    def log(cls, message):
        timestamp = datetime.datetime.now().strftime("%H:%M:%S")
        entry = f"[{timestamp}] {message}"
        cls.logs.append(entry)
        print(entry) # También a la consola por si acaso

    @classmethod
    def get_logs(cls):
        return "\n".join(cls.logs[::-1]) # Lo más nuevo arriba
