"""Genera la familia de sonidos de Ride en assets/sonidos/*.wav.

Un solo timbre (marimba) y un motivo de 3 notas (sol-si-re):
  nueva_solicitud  el motivo con remate arriba (sol-si-re-sol)  ~1,4 s
  estado_viaje     el motivo subiendo                           ~1,4 s
  viaje_cancelado  el motivo bajando, en menor (re-sib-sol)      ~1,6 s
  mensaje          las dos primeras notas, suave                ~0,9 s

Uso: python3 tool/generar_sonidos.py  (y luego convertir, ver assets/sonidos/LEEME.md)
"""
import math, os, struct, wave

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sonidos")
F = {"G5": 783.99, "Bb5": 932.33, "B5": 987.77, "D6": 1174.66, "G6": 1567.98}
MARIMBA = [(1, 1.0), (4, 0.18), (10, 0.04)]


def frase(notas, paso, decay):
    return [(F[x], i * paso, decay) for i, x in enumerate(notas)]


def render(nombre, notas, total, pico=0.85):
    n = int(total * SR)
    buf = [0.0] * n
    for f, t0, decay in notas:
        i0 = int(t0 * SR)
        for k in range(min(n - i0, int(SR * 6 / decay))):
            t = k / SR
            env = math.exp(-decay * t) * (1 - math.exp(-t * 300))
            buf[i0 + k] += env * sum(a * math.sin(2 * math.pi * f * h * t) for h, a in MARIMBA)
    fade = int(0.25 * SR)
    for k in range(fade):
        buf[n - 1 - k] *= k / fade
    m = max(abs(x) for x in buf) or 1
    with wave.open(os.path.join(OUT, nombre + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(x / m * pico * 32767)) for x in buf))


motivo = ["G5", "B5", "D6"]
render("nueva_solicitud", frase(motivo + ["G6"], 0.11, 4), 1.4)
render("estado_viaje", frase(motivo, 0.14, 6), 1.4)
render("viaje_cancelado", frase(["D6", "Bb5", "G5"], 0.2, 4.5), 1.6)
render("mensaje", frase(["G5", "B5"], 0.1, 7), 0.9, pico=0.42)  # ~6 dB más suave
