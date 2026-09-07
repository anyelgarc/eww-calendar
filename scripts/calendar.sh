#!/usr/bin/env bash
# Genera la rejilla del calendario y la publica en la variable `cal` de eww.
#
#   calendar.sh toggle      abre/cierra la ventana (mes actual)
#   calendar.sh shift  N    salta N meses (±1 mes, ±12 año) sin cerrar
#   calendar.sh refresh     redibuja el mes actual (tras tocar una nota)
#   calendar.sh close       cierra si está abierta
#
# Formato de `cal`:
#   {"offset":0,"title":"Septiembre 2026",
#    "weeks":[[{"d":"1","iso":"2026-09-01","cls":"...","style":"..."},...],...]}
#
# `style` es el CSS en línea del bloque de un día con nota: su color y el
# número en el tono que mejor se lea encima. Vacío si el día no tiene nota.

# Ruta absoluta: al lanzarse desde el compositor el PATH puede no incluir
# ~/.local/bin, que es donde vive eww.
EWW=$(command -v eww || echo "$HOME/.local/bin/eww")

# Las notas viven junto al widget (ver scripts/notes.sh).
DIR=$(cd "$(dirname "$0")/.." && pwd)
NOTES="$DIR/notes.json"
PREFS="$DIR/prefs.json"

# Panel de notas plegado y sin día seleccionado.
SEL_NONE='{"mode":"none","date":"","label":"","color":"","idx":-1,"full":false,"notes":[]}'

build() {
    python3 - "$DIR/scripts" "$1" "$NOTES" "$PREFS" <<'PY'
import calendar, datetime, json, sys

sys.path.insert(0, sys.argv[1])
import notesdb

MESES = ["Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio",
         "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"]

off = int(sys.argv[2])

# Si el fichero de notas aún no existe o se corrompe, el calendario se dibuja
# igual, simplemente sin marcas.
notas = notesdb.cargar(sys.argv[3])
defecto = notesdb.color_defecto(sys.argv[4])

hoy = datetime.date.today()

# Desplazamiento en meses sobre el mes actual.
total = (hoy.year * 12 + hoy.month - 1) + off
year, month = divmod(total, 12)
month += 1

weeks = []
for semana in calendar.Calendar(firstweekday=0).monthdatescalendar(year, month):
    fila = []
    for d in semana:
        iso = d.isoformat()
        cls = []
        if d.month != month:
            cls.append("out")
        elif d.weekday() >= 5:
            cls.append("weekend")
        # El día de hoy sólo se marca en su propio mes, no en los bordes.
        if d == hoy and d.month == month:
            cls.append("today")
        # Día con nota: bloque del color de la nota (el suyo, o el global).
        estilo = ""
        if iso in notas:
            cls.append("has-note")
            estilo = notesdb.estilo(notesdb.color_de(notas[iso], defecto))
        fila.append({"d": str(d.day), "iso": iso,
                     "cls": " ".join(cls), "style": estilo})
    weeks.append(fila)

print(json.dumps({"offset": off,
                  "title": f"{MESES[month - 1]} {year}",
                  "weeks": weeks},
                 ensure_ascii=False))
PY
}

# Color por defecto de las notas, para publicarlo junto a la rejilla.
defecto() {
    python3 - "$DIR/scripts" "$PREFS" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import notesdb
print(notesdb.color_defecto(sys.argv[2]))
PY
}

# Mes que se está mostrando ahora mismo (0 = mes actual).
offset() {
    "$EWW" get cal 2>/dev/null \
        | python3 -c 'import json,sys; print(json.load(sys.stdin).get("offset",0))' 2>/dev/null \
        || echo 0
}

# Repliega el calendario y espera a que termine la animación (250ms en
# eww.scss) antes de cerrar la ventana, para que no desaparezca de golpe.
hide() {
    "$EWW" update cal_show=false
    sleep 0.3
    "$EWW" close calendar
    # Deja el panel de notas cerrado para la próxima apertura.
    "$EWW" update cal_sel="$SEL_NONE" note_seed="" note_draft="" color_draft="" time_on=false
}

case "${1:-toggle}" in
    shift)
        cur=$(offset)
        # Al cambiar de mes la selección deja de tener sentido: se pliega.
        "$EWW" update cal="$(build "$(( ${cur:-0} + ${2:-0} ))")" \
                      cal_sel="$SEL_NONE" note_seed="" note_draft="" color_draft="" time_on=false
        ;;
    refresh)
        cur=$(offset)
        "$EWW" update cal="$(build "${cur:-0}")" note_color="$(defecto)"
        ;;
    toggle)
        if "$EWW" active-windows 2>/dev/null | grep -q '^calendar'; then
            hide
        else
            # La ventana se abre con el revealer plegado y se despliega justo
            # después: hace falta que GTK la haya mapeado antes de animar.
            "$EWW" update cal="$(build 0)" cal_show=false note_color="$(defecto)" \
                          cal_sel="$SEL_NONE" note_seed="" note_draft="" color_draft="" time_on=false
            # El reloj y la fecha se refrescan por intervalo; al abrir se
            # fuerza una lectura para que no se vea la de hace unos segundos.
            "$EWW" poll cal_hour date_full 2>/dev/null || true
            "$EWW" open calendar
            sleep 0.1
            "$EWW" update cal_show=true
        fi
        ;;
    close)
        # Sólo cierra si está abierta: es seguro llamarlo a ciegas desde
        # un atajo de teclado del compositor.
        if "$EWW" active-windows 2>/dev/null | grep -q '^calendar'; then
            hide
        fi
        ;;
esac
