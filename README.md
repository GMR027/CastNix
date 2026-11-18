# CastNix

Espeja el escritorio de Linux a una TV por **AirPlay** (doubletake) y añade un
botón **"Compartir TV"** al menú rápido de GNOME, con interruptor de AirPlay y
acceso a **Google Cast** (GNOME Network Displays).

Pensado para GNOME en Wayland, probado en Fedora 42 (Apple Silicon) con una LG
webOS, pero el instalador también cubre Debian/Ubuntu y Arch.

## Instalación en un comando

```bash
git clone https://github.com/GMR027/CastNix.git
cd CastNix
./install.sh
```

`install.sh` hace todo de una pasada:

1. Instala las dependencias (Go, GStreamer, `x264enc`, PipeWire, Avahi,
   xdg-desktop-portal; RPM Fusion en Fedora si hace falta).
2. Compila `doubletake` y `doubletake-ctl` desde `doubletake-src/`
   (dependencias vendorizadas: no necesita red para compilar).
3. Instala el script, el diagnóstico, la extensión y el lanzador en `~/.local`.
4. Ajusta la extensión a la versión de GNOME del equipo.
5. Busca la TV por mDNS (AirPlay o Google Cast) y comprueba el puerto 7000.
6. Si AirPlay está apagado en la TV, explica cómo activarlo y ofrece reintentar.
7. Empareja con la TV (pide el PIN de 4 dígitos que sale en pantalla).
8. Opcionalmente instala Google Cast y hace una prueba de 20 segundos.

Al terminar, **cierra sesión y vuelve a entrar** si el botón aún no aparece.

### Opciones

```bash
./install.sh --with-cast          # además Google Cast por Flatpak
./install.sh --target 192.168.1.50
./install.sh --pair               # emparejar de nuevo
./install.sh --no-pair            # no emparejar
./install.sh --test               # prueba de 20 s al terminar
./install.sh --no-deps            # no tocar paquetes
./install.sh --yes                # sin preguntas (no empareja ni prueba)
```

También se puede ejecutar el script sin clonar el repo:

```bash
REPO_URL=https://github.com/GMR027/CastNix.git bash <(curl -fsSL \
  https://raw.githubusercontent.com/GMR027/CastNix/main/install.sh)
```

Desinstalar: `./uninstall.sh`.

## Qué se instala

| Ruta | Qué es |
|---|---|
| `~/.local/bin/doubletake{,-ctl}` | Emisor AirPlay 2 (compilado con el parche Wayland/I420) |
| `~/.local/bin/compartir-tv` | Wrapper: elige TV por mDNS, reconstruye `WAYLAND_DISPLAY`, comprueba el puerto 7000 y registra en `~/.cache/compartir-tv.log` |
| `~/.local/bin/check-tv-share.sh` | Diagnóstico de la extensión y del AirPlay de la TV |
| `~/.local/share/gnome-shell/extensions/tv-share@edgar.local/` | Extensión del menú rápido |
| `~/.local/share/applications/compartir-tv.desktop` | Lanzador del menú de aplicaciones |
| `~/.config/doubletake/credentials.json` | Credenciales de emparejamiento (600) |
| `~/.config/compartir-tv.conf` | TV elegida, si se indicó con `--target` |

## Uso diario

- **Menú rápido de GNOME** → "Compartir TV":
  - interruptor **AirPlay**: encender/apagar la transmisión,
  - **Abrir Google Cast**: lanza GNOME Network Displays,
  - el subtítulo indica si está transmitiendo.
- Terminal: `~/.local/bin/compartir-tv` (Ctrl+C para parar).
- Diagnóstico: `~/.local/bin/check-tv-share.sh`.
- Log: `~/.cache/compartir-tv.log`.

## Activar AirPlay en la TV (solo la primera vez)

Inicio → **Panel de inicio** (Home Dashboard) → **AirPlay** → **AirPlay y
HomeKit** → **AirPlay: Activado**.

Si el puerto 7000 está cerrado, la TV responde al ping pero rechaza la conexión
(`connection refused`). El instalador y `compartir-tv` detectan ese caso y lo
explican en lugar de fallar en silencio.

## Si algo no funciona

```bash
~/.local/bin/check-tv-share.sh       # estado de extensión y de AirPlay
tail -30 ~/.cache/compartir-tv.log   # motivo del último intento
gst-inspect-1.0 x264enc              # debe existir
```

| Síntoma | Causa habitual |
|---|---|
| El botón enciende y se apaga solo | AirPlay apagado en la TV (puerto 7000 cerrado) |
| `connection refused` | Igual que arriba |
| Pantalla negra en la TV | Falta el parche I420; recompila desde `doubletake-src/` |
| No aparece el botón | Cierra sesión y vuelve a entrar |
| No encuentra la TV | `TV_SHARE_TARGET=<ip> ~/.local/bin/compartir-tv` |
| Tirones | `compartir-tv -width 1280 -height 720 -bitrate 3000` |

## Notas técnicas

- Wayland captura por el portal de escritorio (`pipewiresrc`); la primera vez
  GNOME pide permiso para compartir pantalla.
- El parche de `doubletake-src/` escala a la resolución negociada (1080p) y
  fuerza `I420`, porque la captura llega en RGB y `x264enc` elegía High 4:4:4,
  que la TV LG no decodifica (pantalla negra).
- `x264enc` es software: ~60 % de un núcleo a 1080p30. Para bajarlo, usa
  720p y 3000 kbps.
- Usa AirPlay **o** Cast, no ambos a la vez.
- En `doubletake-src/` las dependencias Go están vendorizadas para compilar sin
  red. Para actualizar el parche: `git -C doubletake-src diff` sobre upstream.

## Estructura

```
CastNix/
├── install.sh                 # instalación de una pasada
├── uninstall.sh
├── Makefile                   # make install / uninstall / dist
├── bin/
│   ├── compartir-tv
│   └── check-tv-share.sh
├── extension/tv-share@edgar.local/
│   ├── extension.js
│   └── metadata.json
├── applications/compartir-tv.desktop.in
└── doubletake-src/            # doubletake + parche local + vendor/
```

## Licencia

GPL-3.0. `doubletake-src/` conserva su licencia original (GPL-3.0, ver
`doubletake-src/LICENSE`); el resto del proyecto se distribuye bajo los mismos
términos para que el conjunto sea coherente.
