#!/usr/bin/env bash
# Notas cortas por día del calendario. Hasta 5 por día (notesdb.MAXIMO).
#
#   notes.sh open YYYY-MM-DD   click izquierdo: lista las notas del día, o
#                              abre el campo si no hay ninguna (y al repetir
#                              click sobre el mismo día, pliega el panel)
#   notes.sh menu YYYY-MM-DD   click derecho: ofrece borrar notas del día
#   notes.sh add               escribe una nota nueva en el día seleccionado
#   notes.sh edit N            edita la nota N del día seleccionado
#   notes.sh save ISO IDX COLOR HH MM ON
#                              guarda; IDX -1 añade, si no reemplaza. El texto
#                              llega por la entrada estándar (vacío = borrar)
#   notes.sh del ISO N         borra la nota N de ese día
#   notes.sh draft             refresca el borrador mientras se teclea
#   notes.sh clear             vacía el campo de un tirón
#   notes.sh time-clear        deja la nota sin hora
#   notes.sh color             color del día que se está editando
#   notes.sh color-reset       ese día vuelve al color por defecto
#   notes.sh color-default     color por defecto de todos los días con nota
#   notes.sh close             pliega el panel
#
# El texto siempre viaja por stdin (heredoc desde el .yuck), nunca como
# argumento: así comillas, $ o acentos no se le escapan a la shell.
#
# Almacén: notes.json y prefs.json junto al widget (ver scripts/notesdb.py).
#
# Estado del panel, en la variable `cal_sel` de eww:
#   {"mode":"none|view|edit|del", "date":"2026-09-07",
#    "label":"Lunes, 7 de Septiembre de 2026", "color":"", "idx":-1,
#    "full":false, "notes":[{"i":0,"text":"…","time":"14:30"}]}

EWW=$(command -v eww || echo "$HOME/.local/bin/eww")

DIR=$(cd "$(dirname "$0")/.." && pwd)
NOTES="$DIR/notes.json"
PREFS="$DIR/prefs.json"
LIB="$DIR/scripts"
CAL="$DIR/scripts/calendar.sh"

VACIO='{"mode":"none","date":"","label":"","color":"","idx":-1,"full":false,"notes":[]}'

# Calcula el nuevo `cal_sel`. Recibe la acción, el día, el índice de la nota y
# la selección actual; devuelve el JSON del panel por stdout.
select_day() {
    python3 - "$LIB" "$NOTES" "$1" "$2" "$3" "$4" <<'PY'
import datetime, json, sys

sys.path.insert(0, sys.argv[1])
import notesdb

DIAS  = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"]
MESES = ["Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio",
         "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"]

ruta, accion, iso, idx_arg, previo = (sys.argv[2], sys.argv[3], sys.argv[4],
                                      sys.argv[5], sys.argv[6])

dias = notesdb.cargar(ruta)

try:
    sel = json.loads(previo)
    if not isinstance(sel, dict):
        sel = {}
except Exception:
    sel = {}

vacio = {"mode": "none", "date": "", "label": "", "color": "",
         "idx": -1, "full": False, "notes": []}

def fin(datos):
    print(json.dumps(datos, ensure_ascii=False))
    raise SystemExit

# `add` y `edit` no traen día: trabajan sobre el que ya estaba seleccionado.
if accion in ("add", "edit"):
    iso = sel.get("date", "")
if not iso:
    fin(vacio)

dia = dias.get(iso, {"color": "", "notes": []})
notas = dia["notes"]

try:
    idx = int(idx_arg)
except ValueError:
    idx = -1

if accion == "open":
    # Segundo click sobre el día ya abierto: se pliega el panel.
    if sel.get("date") == iso and sel.get("mode", "none") != "none":
        fin(vacio)
    modo, idx = ("view", -1) if notas else ("edit", -1)
elif accion == "menu":
    # Click derecho: sólo tiene sentido si hay algo que borrar.
    if not notas:
        fin(vacio)
    modo, idx = "del", -1
elif accion == "view":
    # Después de guardar o borrar: vuelve a la lista, o cierra si se vació.
    if not notas:
        fin(vacio)
    modo, idx = "view", -1
elif accion == "add":
    if len(notas) >= notesdb.MAXIMO:
        modo, idx = "view", -1
    else:
        modo, idx = "edit", -1
else:                                    # edit
    modo = "edit"
    if not (0 <= idx < len(notas)):
        idx = -1

d = datetime.date.fromisoformat(iso)
etiqueta = f"{DIAS[d.weekday()]}, {d.day} de {MESES[d.month - 1]} de {d.year}"

fin({"mode": modo,
     "date": iso,
     "label": etiqueta,
     "color": dia["color"],
     "idx": idx,
     "full": len(notas) >= notesdb.MAXIMO,
     "notes": [{"i": i, "text": n["text"], "time": n["time"]}
               for i, n in enumerate(notas)]})
PY
}

# Publica el panel y precarga el campo, la hora y el color con lo que tuviera
# la nota que se va a editar.
publish() {
    local sel="$1" h m on color texto

    # Una línea con separadores 0x1f: el texto va el último porque es el único
    # que puede llevar espacios. El separador no es un espacio en blanco a
    # propósito: con tabuladores, bash colapsa dos seguidos en uno y un color
    # vacío desplazaría el texto a su campo.
    # (el JSON va por argv: python3 - ya usa stdin para leerse a sí mismo)
    IFS=$'\x1f' read -r h m on color texto < <(
        python3 - "$LIB" "$sel" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[1])
import notesdb

try:
    sel = json.loads(sys.argv[2])
except Exception:
    sel = {}
notas = sel.get("notes", [])
idx = sel.get("idx", -1)
nota = notas[idx] if 0 <= idx < len(notas) else {}

h, m, puesta = notesdb.parte_hora(nota.get("time", ""))
texto = " ".join(str(nota.get("text", "")).split())
print("\x1f".join([str(h), str(m), "true" if puesta else "false",
                   sel.get("color", "") or "", texto]))
PY
    )

    "$EWW" update cal_sel="$sel" \
                  note_seed="$texto" note_draft="$texto" \
                  color_draft="$color" \
                  hour_draft="$h" min_draft="$m" time_on="$on"
}

# Guarda (o borra) una nota. Devuelve el texto que quedó.
store() {
    python3 - "$LIB" "$NOTES" "$1" "$2" "$3" "$4" "$5" "$6" "$7" <<'PY'
import sys

sys.path.insert(0, sys.argv[1])
import notesdb

ruta, iso, idx, color, hh, mm, on, texto = (sys.argv[2], sys.argv[3], sys.argv[4],
                                            sys.argv[5], sys.argv[6], sys.argv[7],
                                            sys.argv[8], sys.argv[9])

# El campo de eww es de una sola línea; se normaliza por si acaso.
texto = " ".join(texto.split())
try:
    idx = int(idx)
except ValueError:
    idx = -1

dias = notesdb.cargar(ruta)
dia = dias.get(iso, {"color": "", "notes": []})
notas = dia["notes"]

if not texto:
    # Guardar en blanco borra la nota que se estaba editando; si era nueva,
    # no hay nada que hacer.
    if 0 <= idx < len(notas):
        notas.pop(idx)
elif 0 <= idx < len(notas):
    notas[idx] = {"text": texto, "time": notesdb.hora(hh, mm, on == "true")}
elif len(notas) < notesdb.MAXIMO:
    notas.append({"text": texto, "time": notesdb.hora(hh, mm, on == "true")})

if notas:
    dias[iso] = {"color": notesdb.normaliza(color), "notes": notas}
else:
    dias.pop(iso, None)
notesdb.guardar(ruta, dias)

print(texto)
PY
}

# Abre el selector de color del sistema y devuelve lo elegido en #rrggbb
# (nada si se cancela).
#
# La ventana del calendario vive en la capa superior de Wayland, por encima de
# las ventanas normales, así que el diálogo saldría tapado. En vez de cerrarla
# se repliega el revealer mientras eliges: la ventana encoge hasta desaparecer
# y el diálogo se ve entero, pero el día seleccionado y el mes que estuvieras
# mirando siguen intactos, así que al volver todo está donde lo dejaste.
pick() {
    local actual="$1" elegido
    "$EWW" update cal_show=false
    sleep 0.3
    elegido=$(zenity --color-selection --show-palette \
                     --title="Color de las notas" --color="$actual" 2>/dev/null)
    "$EWW" update cal_show=true
    python3 - "$LIB" "$elegido" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import notesdb
print(notesdb.desde_zenity(sys.argv[2]))
PY
}

sel_actual() { "$EWW" get cal_sel 2>/dev/null; }

case "${1:-close}" in
    open|menu)
        publish "$(select_day "$1" "${2:-}" -1 "$(sel_actual)")"
        ;;
    add)
        publish "$(select_day add "" -1 "$(sel_actual)")"
        ;;
    edit)
        publish "$(select_day edit "" "${2:--1}" "$(sel_actual)")"
        ;;
    save)
        iso="${2:-}"
        [ -n "$iso" ] || exit 0
        # La nota llega por stdin (heredoc desde el .yuck).
        store "$iso" "${3:--1}" "${4:-}" "${5:-0}" "${6:-0}" "${7:-false}" "$(cat)" >/dev/null
        "$CAL" refresh
        publish "$(select_day view "$iso" -1 '{}')"
        ;;
    del)
        iso="${2:-}"
        idx="${3:--1}"
        [ -n "$iso" ] || exit 0
        # Borrar = guardar esa nota en blanco.
        store "$iso" "$idx" "" 0 0 false "" >/dev/null
        "$CAL" refresh
        publish "$(select_day view "$iso" -1 '{}')"
        ;;
    draft)
        # Cada pulsación del campo: sólo refresca el borrador que guardará
        # el botón «Aceptar». Sin python, que esto corre en cada tecla.
        "$EWW" update note_draft="$(cat)"
        ;;
    clear)
        # La «✕» de la izquierda del campo: lo deja vacío sin tocar lo guardado.
        # En dos pasos a propósito: tras vaciarlo una vez, `note_seed` ya vale
        # "" aunque el usuario haya vuelto a escribir, y no hay garantía de que
        # eww reescriba el campo si le asignas el mismo valor que ya tenía. El
        # espacio intermedio fuerza el cambio y no llega a verse.
        "$EWW" update note_seed=" "
        "$EWW" update note_seed="" note_draft=""
        ;;
    time-clear)
        "$EWW" update time_on=false
        ;;
    color)
        # Color del día que se está editando. Se queda en el borrador: no se
        # guarda hasta que le des a «Aceptar».
        actual=$("$EWW" get color_draft 2>/dev/null)
        [ -n "$actual" ] || actual=$("$EWW" get note_color 2>/dev/null)
        nuevo=$(pick "$actual")
        [ -n "$nuevo" ] && "$EWW" update color_draft="$nuevo"
        ;;
    color-reset)
        # Este día vuelve a seguir al color por defecto.
        "$EWW" update color_draft=""
        ;;
    color-default)
        # Color por defecto: esto sí se guarda al momento, y repinta de golpe
        # los días que no tengan un color propio.
        nuevo=$(pick "$("$EWW" get note_color 2>/dev/null)")
        if [ -n "$nuevo" ]; then
            python3 - "$LIB" "$PREFS" "$nuevo" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import notesdb
notesdb.pon_color_defecto(sys.argv[2], sys.argv[3])
PY
            "$CAL" refresh
        fi
        ;;
    close)
        "$EWW" update cal_sel="$VACIO" note_seed="" note_draft="" color_draft=""
        ;;
esac
