#!/usr/bin/env bash
# Fecha larga en español para la cabecera del calendario:
#   "Sábado, día 6 de Septiembre del 2026"
# Nombres propios en vez de locale: así coincide con los meses de calendar.sh.
python3 - <<'PY'
import datetime

DIAS  = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"]
MESES = ["Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio",
         "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"]

hoy = datetime.date.today()
print(f"{DIAS[hoy.weekday()]}, día {hoy.day} de {MESES[hoy.month - 1]} del {hoy.year}")
PY
