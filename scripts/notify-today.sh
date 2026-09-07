#!/usr/bin/env bash
# Avisa por notificación si hoy hay notas apuntadas en el calendario.
#
#   notify-today.sh          espera al demonio de notificaciones y avisa
#   notify-today.sh --now    avisa ya, sin esperar (para probar a mano)
#
# Pensado para lanzarse al iniciar sesión: al arrancar, el demonio (swaync,
# dunst, mako…) todavía no suele estar en el bus, así que por defecto se le
# espera un rato antes de rendirse.

DIR=$(cd "$(dirname "$0")/.." && pwd)
NOTES="$DIR/notes.json"

ICONO="x-office-calendar"
ESPERA=60          # segundos como mucho esperando al demonio

# ¿Hay ya alguien escuchando notificaciones en el bus de sesión?
hay_demonio() {
    gdbus call --session \
        --dest org.freedesktop.DBus \
        --object-path /org/freedesktop/DBus \
        --method org.freedesktop.DBus.NameHasOwner org.freedesktop.Notifications \
        2>/dev/null | grep -q true
}

# Notas de hoy, una por línea y con su hora delante. Nada si no hay ninguna.
notas_de_hoy() {
    python3 - "$DIR/scripts" "$NOTES" <<'PY'
import datetime, sys

sys.path.insert(0, sys.argv[1])
import notesdb

dia = notesdb.cargar(sys.argv[2]).get(datetime.date.today().isoformat())
for nota in (dia or {}).get("notes", []):
    print(f"{nota['time']}  {nota['text']}" if nota["time"] else nota["text"])
PY
}

notas=$(notas_de_hoy)
[ -n "$notas" ] || exit 0
cuantas=$(printf '%s\n' "$notas" | wc -l)

if [ "${1:-}" != "--now" ]; then
    for _ in $(seq "$ESPERA"); do
        hay_demonio && break
        sleep 1
    done
    hay_demonio || exit 1
fi

# Fecha larga de hoy, la misma que luce la cabecera del calendario.
fecha=$("$DIR/scripts/date-full.sh")

notify-send \
    --app-name="Calendario" \
    --icon="$ICONO" \
    --urgency=normal \
    --expire-time=15000 \
    "$( [ "$cuantas" -gt 1 ] && echo "$cuantas notas para hoy" || echo "Nota para hoy" )" \
    "$fecha
$notas"
