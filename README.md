# Calendario para eww

Calendario desplegable con notas por día, para [eww](https://github.com/elkowar/eww).
Se abre bajo el reloj de la barra, navega por meses, y cada día admite hasta
cinco notas cortas con hora y un color propio.

<!-- Aquí queda bien una captura: docs/captura.png -->

- **Notas por día**, hasta cinco, una debajo de otra.
- **Hora opcional** por nota, con dos barras de 0-23 y 0-59.
- **Color por día**, con el selector de color del sistema, más un color por
  defecto para todos los días que no tengan uno propio.
- **Aviso al iniciar sesión** si hoy tienes algo apuntado.
- Los días con nota se pintan de su color, y el número del día se dibuja en
  claro u oscuro según lo que se lea mejor encima.

## Requisitos

| | |
|---|---|
| `eww` | 0.6.0 o superior (usa `input`, `scale`, `onrightclick` y `:style`) |
| `python3` | Sin dependencias externas, sólo la biblioteca estándar |
| `jq` | |
| `zenity` | Sólo para el selector de color |
| Un demonio de notificaciones | Sólo para el aviso al arrancar (`swaync`, `dunst`, `mako`…) |

Probado en Debian 13 con Hyprland (Wayland) y swaync. En X11 debería
funcionar cambiando `:focusable "ondemand"` por `:focusable true` en
`calendar.yuck`.

## Instalación

**1.** Copia esta carpeta a `~/.config/eww/widgets/calendar`.

Si la pones en otra ruta, cambia la variable `cal_dir` del principio de
`calendar.yuck` y la ruta literal del `defpoll date_full` justo debajo (esa no
puede ir por variable: un `defpoll` se evalúa fuera de todo ámbito).

**2.** Inclúyelo en tu configuración:

```lisp
;; ~/.config/eww/eww.yuck
(include "widgets/calendar/calendar.yuck")
```

```scss
// ~/.config/eww/eww.scss
@import "widgets/calendar/calendar.scss";
```

**3.** Engánchalo a algo que lo abra: un click en el reloj de tu barra, o un
atajo del compositor.

```lisp
(button :onclick "~/.config/eww/widgets/calendar/scripts/calendar.sh toggle"
        hora)
```

`calendar.sh` entiende `toggle`, `close`, `shift N` (saltar N meses) y
`refresh` (redibujar el mes).

**4.** Opcional, para que te avise al iniciar sesión si hoy hay notas:

```conf
# ~/.config/hypr/hyprland.conf
exec-once = ~/.config/eww/widgets/calendar/scripts/notify-today.sh
```

El script espera hasta 60 s a que el demonio de notificaciones aparezca en el
bus, porque al arrancar todavía no suele estar listo. Para probarlo a mano,
sin esperas: `notify-today.sh --now`.

## Uso

| Acción | Qué hace |
|---|---|
| **Click izquierdo** en un día | Lista sus notas, o abre el campo si no tiene ninguna |
| **Click izquierdo** otra vez | Pliega el panel |
| **Click derecho** en un día con notas | Ofrece borrarlas, una por una |
| **✎** | Edita esa nota |
| **+ Añadir nota** | Otra nota más (desaparece al llegar a cinco) |

Escribiendo una nota:

| | |
|---|---|
| **✕** a la izquierda del campo | Vacía el campo sin tocar lo guardado |
| **Aceptar** o <kbd>Enter</kbd> | Guarda. En blanco, borra la nota |
| **Barras `h` y `m`** | Le ponen hora; la **✕** de esa fila se la quita |
| **Color** | Color de este día |
| **↺** | Este día vuelve al color por defecto |
| **Por defecto** | Color de todos los días que no tengan uno propio |

Al elegir color, el calendario se repliega un momento: su ventana vive en la
capa superior de Wayland y taparía el diálogo. Vuelve solo, con el día y el
mes donde los dejaste.

## Ficheros

```
calendar.yuck          widgets y ventana
calendar.scss          estilos (se importa desde eww.scss)
scripts/
  calendar.sh          rejilla del mes, abrir/cerrar, navegación
  notes.sh             notas: crear, editar, borrar, color, hora
  notesdb.py           almacén compartido: formato, migración, escritura
  date-full.sh         fecha larga de la cabecera
  notify-today.sh      aviso al iniciar sesión
notes.json             tus notas          (se crea solo, no se versiona)
prefs.json             color por defecto  (se crea solo, no se versiona)
```

Los dos JSON se crean con permisos `600` la primera vez que guardas algo. Si
no existen, el calendario funciona igual: sin marcas y con el color de fábrica.

## Dónde se guardan las notas

```json
{
  "2026-09-07": {
    "color": "#e2807f",
    "notes": [
      { "text": "Dentista",    "time": "14:30" },
      { "text": "Comprar pan", "time": "" }
    ]
  }
}
```

`color` vacío significa «usa el de por defecto», así que cambiar el global
repinta de golpe todos los días que no tengan uno propio. El color es del día
entero, no de cada nota.

## Personalización

- **Colores del calendario**: las variables `$cal-*` del principio de
  `calendar.scss`. Si cambias `$cal-card` o `$cal-fg`, cambia también
  `FG_OSCURO` y `FG_CLARO` en `notesdb.py`, que son los que deciden si el
  número de un día se dibuja claro u oscuro sobre su color.
- **Cuántas notas caben en un día**: `MAXIMO` en `notesdb.py`.
- **Color de fábrica**: `COLOR_INICIAL` en `notesdb.py`.
- **Reloj de la cabecera**: `calendar.yuck` define su propio `cal_hour` para
  no depender de nada externo. Si tu barra ya tiene una variable con la hora,
  puedes borrar ese `defpoll` y apuntar la etiqueta `now-hour` a la tuya.

## Detalles de implementación

Cosas que costaron más de lo que parece, por si tocas el código:

- **El texto de las notas viaja por la entrada estándar**, en un heredoc con
  el delimitador entrecomillado, nunca como argumento. eww sustituye `{}` en
  el comando sin escapar nada, así que comillas, `$` o `;` en una nota se los
  comería la shell.
- **Los widgets llevan `:timeout` largo.** Por defecto eww mata el comando a
  los 200 ms y deja escrito en `~/.cache/eww/*.log` el comando entero, que
  aquí lleva dentro el texto de la nota.
- **El atributo `:visible` no sirve** para alternar entre modos: no se aplica
  la primera vez que se abre la ventana, porque se evalúa antes de que GTK
  mapee el widget. Cada modo va en su propio `revealer`.
- **Un `revealer` con transición `crossfade` no encoge a su hijo**, sólo lo
  desvanece: deja el hueco ocupado. Por eso todos usan `slidedown`.
- **El `for` de eww añade sus hijos al final del contenedor**, así que cada
  bucle vive en su propia caja o lo que venga detrás acaba dibujándose encima.
- **Las barras de la hora van a `:max 24` y `:max 60`.** El `GtkAdjustment`
  reserva un `page_size` al final del recorrido, así que el valor máximo
  alcanzable es `max - 1`.
