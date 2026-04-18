import datetime

class Logger:
    logs = []

    @classmethod
    def log(cls, message):
        now = datetime.datetime.now().strftime("%H:%M:%S")
        entry = f"[{now}] {message}"
        cls.logs.append(entry)
        # Limitar a los últimos 50 logs
        if len(cls.logs) > 50: cls.logs.pop(0)

    @classmethod
    def get_all(cls):
        return "\n".join(cls.logs[::-1])
