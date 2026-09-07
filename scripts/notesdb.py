"""Almacén de las notas del calendario.

    notes.json
    {
      "2026-09-07": {
        "color": "#e2807f",
        "notes": [{"text": "Dentista", "time": "14:30"},
                  {"text": "Comprar pan", "time": ""}]
      }
    }

    prefs.json   {"note_color": "#e8b04b"}

Cada día admite hasta MAXIMO notas, en el orden en que se escribieron. El
color es del día entero, no de cada nota: es el que pinta su bloque en la
rejilla, y `color` vacío significa «usa el de por defecto», así que cambiar el
global repinta de golpe todos los días que no tengan uno propio.

Los dos formatos anteriores se migran al vuelo al leer, así que las notas que
ya tuvieras siguen ahí sin tener que tocar el fichero:

    {"2026-09-07": "Dentista"}                        (sólo texto)
    {"2026-09-07": {"text": "Dentista", "color": ""}}  (texto y color)

Se importa desde los heredocs de python de los scripts, que le pasan la
carpeta scripts/ por argv.
"""

import json
import os
import re
import tempfile

# Cuántas notas caben en un día.
MAXIMO = 5

# El ámbar de siempre: lo que se usa mientras no elijas otro por defecto.
COLOR_INICIAL = "#e8b04b"

# Contraste del número del día sobre su color. Son $cal-card y $cal-fg de
# calendar.scss; si allí cambia la paleta, aquí también.
FG_OSCURO = "#333c48"
FG_CLARO = "#e6edf5"

_HEX = re.compile(r"^#[0-9a-fA-F]{6}$")


def _leer(ruta):
    """Diccionario del fichero, o vacío si no existe o está corrupto."""
    try:
        with open(ruta, encoding="utf-8") as f:
            datos = json.load(f)
        return datos if isinstance(datos, dict) else {}
    except Exception:
        return {}


def _escribir(ruta, datos):
    """Escritura atómica: un corte a medias no deja el fichero a medias."""
    carpeta = os.path.dirname(ruta) or "."
    fd, tmp = tempfile.mkstemp(dir=carpeta, prefix=".tmp-", suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(datos, f, ensure_ascii=False, indent=2, sort_keys=True)
            f.write("\n")
        os.replace(tmp, ruta)
    except Exception:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def normaliza(color):
    """Deja el color en #rrggbb, o cadena vacía si no vale."""
    if isinstance(color, str):
        c = color.strip().lower()
        if _HEX.match(c):
            return c
    return ""


def hora(h, m, puesta=True):
    """Formatea una hora en HH:MM, o cadena vacía si la nota no lleva hora."""
    if not puesta:
        return ""
    try:
        h = int(float(h)) % 24
        m = int(float(m)) % 60
    except (TypeError, ValueError):
        return ""
    return f"{h:02d}:{m:02d}"


def parte_hora(texto):
    """De 'HH:MM' saca (hora, minuto, puesta). Sin hora → (9, 0, False)."""
    if isinstance(texto, str):
        m = re.match(r"^\s*(\d{1,2}):(\d{2})\s*$", texto)
        if m:
            return int(m.group(1)) % 24, int(m.group(2)) % 60, True
    return 9, 0, False


def desde_zenity(salida):
    """Traduce lo que devuelve zenity: rgb(232,176,75), #e8b04b o #e8e8b0b04b4b."""
    if not isinstance(salida, str):
        return ""
    s = salida.strip().lower()

    m = re.match(r"^rgba?\(([^)]*)\)$", s)
    if m:
        partes = [p.strip() for p in m.group(1).split(",")]
        if len(partes) >= 3:
            try:
                r, g, b = (max(0, min(255, int(round(float(p))))) for p in partes[:3])
                return f"#{r:02x}{g:02x}{b:02x}"
            except ValueError:
                return ""
        return ""

    # GTK a veces da 16 bits por canal: #rrrrggggbbbb.
    m = re.match(r"^#([0-9a-f]{12})$", s)
    if m:
        d = m.group(1)
        return f"#{d[0:2]}{d[4:6]}{d[8:10]}"

    return normaliza(s)


def _una_nota(valor):
    """Normaliza una entrada de la lista; None si no hay nada aprovechable."""
    if isinstance(valor, str):
        texto, t = valor, ""
    elif isinstance(valor, dict):
        texto, t = valor.get("text", ""), valor.get("time", "")
    else:
        return None
    if not isinstance(texto, str) or not texto.strip():
        return None
    h, m, puesta = parte_hora(t)
    return {"text": texto.strip(), "time": hora(h, m, puesta)}


def _un_dia(valor):
    """Normaliza un día venga en el formato que venga. None si queda vacío."""
    color, lista = "", []

    if isinstance(valor, str):                       # formato 1: sólo texto
        lista = [valor]
    elif isinstance(valor, list):                    # lista suelta de notas
        lista = valor
    elif isinstance(valor, dict):
        if isinstance(valor.get("notes"), list):     # formato actual
            color = valor.get("color", "")
            lista = valor["notes"]
        else:                                        # formato 2: texto y color
            color = valor.get("color", "")
            lista = [valor]
    else:
        return None

    notas = [n for n in (_una_nota(v) for v in lista) if n][:MAXIMO]
    if not notas:
        return None
    return {"color": normaliza(color), "notes": notas}


def cargar(ruta):
    """Notas del fichero, migrando formatos viejos y tirando la basura."""
    dias = {}
    for iso, valor in _leer(ruta).items():
        dia = _un_dia(valor)
        if dia:
            dias[iso] = dia
    return dias


def guardar(ruta, dias):
    _escribir(ruta, dias)


def color_defecto(ruta_prefs):
    return normaliza(_leer(ruta_prefs).get("note_color", "")) or COLOR_INICIAL


def pon_color_defecto(ruta_prefs, color):
    prefs = _leer(ruta_prefs)
    prefs["note_color"] = normaliza(color) or COLOR_INICIAL
    _escribir(ruta_prefs, prefs)


def color_de(dia, defecto):
    """Color con el que se pinta un día: el suyo, o el global."""
    return (dia.get("color") or "") or defecto


def estilo(color):
    """CSS en línea para el bloque de un día: fondo y número legible encima."""
    r, g, b = (int(color[i:i + 2], 16) for i in (1, 3, 5))
    luz = (0.299 * r + 0.587 * g + 0.114 * b) / 255
    return f"background-color: {color}; color: {FG_OSCURO if luz > 0.55 else FG_CLARO};"
