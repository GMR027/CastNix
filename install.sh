#!/usr/bin/env bash
# Instalador de una sola pasada para "Compartir pantalla a la TV".
#
#   ./install.sh                 # instala todo y guía el emparejamiento
#   ./install.sh --with-cast     # además instala Google Cast (GNOME Network Displays)
#   ./install.sh --yes           # sin preguntas (no empareja ni prueba)
#
# Opciones:
#   --target IP        IP o nombre de la TV (si no, se busca por mDNS)
#   --pair             fuerza un emparejamiento nuevo aunque ya haya credenciales
#   --no-pair          no emparejar
#   --test             hace una prueba de 20 s al terminar
#   --with-cast        instala GNOME Network Displays por Flatpak
#   --no-deps          no toca el gestor de paquetes
#   --yes, -y          modo no interactivo
#   --help, -h         esta ayuda
#
# Variables:
#   PREFIX      destino de los binarios (por defecto ~/.local)
#   REPO_URL    si ejecutas este archivo suelto, repositorio a clonar
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"
BINDIR="$PREFIX/bin"
UUID="tv-share@edgar.local"
GEXT="$HOME/.local/share/gnome-shell/extensions/$UUID"
APPS="$HOME/.local/share/applications"
CREDS="$HOME/.config/doubletake/credentials.json"
TV_CONF="$HOME/.config/compartir-tv.conf"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"
LOG="$CACHE/compartir-tv-install.log"

TARGET=""
FORCE_PAIR=0
NO_PAIR=0
RUN_TEST=0
WITH_CAST=0
NO_DEPS=0
ASSUME_YES=0
IP=""
TV_NAME=""

usage() { sed -n '2,24p' "${BASH_SOURCE[0]}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --target)
      [ $# -ge 2 ] || { echo "Falta la IP tras --target" >&2; exit 1; }
      TARGET="$2"; shift 2 ;;
    --target=*)  TARGET="${1#*=}"; shift ;;
    --pair)      FORCE_PAIR=1; shift ;;
    --no-pair)   NO_PAIR=1; shift ;;
    --test)      RUN_TEST=1; shift ;;
    --with-cast) WITH_CAST=1; shift ;;
    --no-deps)   NO_DEPS=1; shift ;;
    -y|--yes)    ASSUME_YES=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "Opción desconocida: $1 (usa --help)" >&2; exit 1 ;;
  esac
done

mkdir -p "$CACHE"
COOL=0
[ -t 1 ] && COOL=1
if [ "$COOL" = 1 ]; then
  B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; N=$'\033[0m'
else
  B=""; G=""; Y=""; R=""; N=""
fi

exec > >(tee -a "$LOG") 2>&1
trap 'printf "\n%sERROR%s en la línea %s. Registro completo: %s\n" "$R" "$N" "$LINENO" "$LOG" >&2' ERR

step() { printf '\n%s== %s ==%s\n' "$B" "$*" "$N"; }
ok()   { printf '%s  ✔%s %s\n' "$G" "$N" "$*"; }
warn() { printf '%s  ! %s%s\n' "$Y" "$*" "$N"; }
die()  { printf '\n%s  ✘ %s%s\n' "$R" "$*" "$N" >&2; exit 1; }
echo "== $(date '+%F %T') instalación (registro: $LOG) =="

have_tty() { [ -r /dev/tty ] && [ -w /dev/tty ]; }

ask() { # pregunta, por defecto "s"
  local q="$1" def="${2:-s}" ans
  [ "$ASSUME_YES" = 1 ] && return 0
  have_tty || return 1
  read -r -p "$q " ans </dev/tty || ans=""
  ans="${ans:-$def}"
  [[ "$ans" =~ ^[sSyY] ]]
}

ask_value() { # pregunta, valor por defecto
  local q="$1" def="${2:-}" ans
  have_tty || { echo "$def"; return; }
  read -r -p "$q " ans </dev/tty || ans=""
  echo "${ans:-$def}"
}

# --------------------------------------------------------------------------
# Repositorio: permite ejecutar el script descargado suelto (REPO_URL=...)
# --------------------------------------------------------------------------
if [ ! -d "$HERE/doubletake-src" ]; then
  [ -n "${REPO_URL:-}" ] ||
    die "Ejecuta este script desde el repositorio clonado, o define REPO_URL=<url del repo>."
  command -v git >/dev/null || die "Necesito git para descargar el repositorio."
  step "Descargando el repositorio"
  TMPREPO="$(mktemp -d)"
  trap 'rm -rf "$TMPREPO"' EXIT
  git clone --depth 1 "$REPO_URL" "$TMPREPO/repo"
  HERE="$TMPREPO/repo"
  ok "Descargado en $HERE"
fi

# --------------------------------------------------------------------------
# Comprobaciones del sistema
# --------------------------------------------------------------------------
step "Sistema"
[ "$(id -u)" -ne 0 ] || die "No ejecutes el instalador como root: instala en tu \$HOME."
command -v gnome-shell >/dev/null ||
  die "No encuentro GNOME Shell. Este paquete usa el menú rápido de GNOME."
GS_VER="$(gnome-shell --version | awk '{print $3}' | cut -d. -f1)"
ok "GNOME Shell $GS_VER · binarios en $BINDIR"
if [ "${XDG_CURRENT_DESKTOP:-}" ] && [[ "${XDG_CURRENT_DESKTOP}" != *GNOME* ]]; then
  warn "la sesión actual no parece GNOME (${XDG_CURRENT_DESKTOP}); el botón no aparecerá hasta entrar en GNOME"
fi
if [ "${XDG_SESSION_TYPE:-}" = "wayland" ]; then
  if ! command -v gst-inspect-1.0 >/dev/null || ! gst-inspect-1.0 pipewiresrc >/dev/null 2>&1; then
    warn "falta el plugin de captura PipeWire para GStreamer; se instalará con las dependencias"
  fi
fi
command -v sudo >/dev/null || [ "$NO_DEPS" = 1 ] ||
  die "Necesito sudo para instalar dependencias (o usa --no-deps)."

# --------------------------------------------------------------------------
# Dependencias
# --------------------------------------------------------------------------
step "Dependencias (GStreamer con x264enc y PipeWire)"
if [ "$NO_DEPS" = 1 ]; then
  ok "omitidas (--no-deps)"
elif command -v dnf >/dev/null 2>&1; then
  FEDORA="$(rpm -E %fedora 2>/dev/null || true)"
  if ! gst-inspect-1.0 x264enc >/dev/null 2>&1; then
    if ! dnf repolist --enabled 2>/dev/null | grep -qi rpmfusion-free; then
      printf 'Habilitando RPM Fusion (x264enc no está en los repos de Fedora)...\n'
      sudo dnf install -y \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA}.noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA}.noarch.rpm"
      sudo dnf makecache -y
    fi
    sudo dnf install -y gstreamer1-plugins-ugly x264-libs
  fi
  sudo dnf install -y golang make gstreamer1-plugins-base gstreamer1-plugins-good \
    gstreamer1-plugins-bad-free gstreamer1-plugin-libav pipewire-gstreamer \
    avahi-tools xdg-desktop-portal-gnome
elif command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y golang-go make libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
    gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly gstreamer1.0-libav avahi-utils python3 \
    xdg-desktop-portal-gnome
  # En Debian/Ubuntu el plugin de PipeWire es un paquete aparte.
  sudo apt-get install -y gstreamer1.0-pipewire ||
    warn "no pude instalar gstreamer1.0-pipewire; instálalo a mano si la captura falla"
elif command -v pacman >/dev/null 2>&1; then
  sudo pacman -S --needed --noconfirm base-devel go gstreamer gst-plugins-base \
    gst-plugins-good gst-plugins-bad gst-plugins-ugly gst-plugin-pipewire \
    avahi xdg-desktop-portal-gnome
else
  warn "gestor de paquetes no reconocido; instala a mano Go, make y los plugins de GStreamer"
fi

for g in x264enc videoscale pipewiresrc; do
  if gst-inspect-1.0 "$g" >/dev/null 2>&1; then
    ok "GStreamer: $g"
  else
    warn "falta el elemento GStreamer '$g'"
  fi
done

# --------------------------------------------------------------------------
# Compilación
# --------------------------------------------------------------------------
step "Compilando doubletake (con el parche Wayland + I420)"
command -v go >/dev/null || die "No encuentro Go. Instálalo y vuelve a ejecutar."
GO_VER="$(go env GOVERSION 2>/dev/null | sed 's/^go//')"
if [ -n "$GO_VER" ] && ! printf '1.25.0\n%s\n' "$GO_VER" | sort -V -C; then
  warn "Go $GO_VER es anterior a 1.25; se intentará descargar el toolchain (necesita red)"
fi
[ -f "$HERE/doubletake-src/go.mod" ] || die "Falta doubletake-src/ en el repositorio."
(
  cd "$HERE/doubletake-src"
  make doubletake doubletake-ctl
)
install -d "$BINDIR"
install -m 755 "$HERE/doubletake-src/bin/doubletake" "$BINDIR/doubletake"
install -m 755 "$HERE/doubletake-src/bin/doubletake-ctl" "$BINDIR/doubletake-ctl"
ok "doubletake y doubletake-ctl instalados"

# --------------------------------------------------------------------------
# Scripts, extensión y lanzador
# --------------------------------------------------------------------------
step "Instalando script, diagnóstico, extensión y lanzador"
install -m 755 "$HERE/bin/compartir-tv" "$BINDIR/compartir-tv"
install -m 755 "$HERE/bin/check-tv-share.sh" "$BINDIR/check-tv-share.sh"

install -d "$GEXT"
install -m 644 "$HERE/extension/$UUID/extension.js" "$GEXT/extension.js"
install -m 644 "$HERE/extension/$UUID/metadata.json" "$GEXT/metadata.json"
command -v python3 >/dev/null || die "Necesito python3 para ajustar la extensión."
python3 - "$GEXT/metadata.json" "$GS_VER" <<'PY'
import json, sys
path, version = sys.argv[1], sys.argv[2]
with open(path) as fh:
    meta = json.load(fh)
meta["shell-version"] = [version]
with open(path, "w") as fh:
    json.dump(meta, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
PY

install -d "$APPS"
sed "s|@BIN@|$BINDIR/compartir-tv|" "$HERE/applications/compartir-tv.desktop.in" \
  > "$APPS/compartir-tv.desktop"
ok "archivos instalados"

enable_extension() {
  if command -v gnome-extensions >/dev/null 2>&1 &&
     gnome-extensions list 2>/dev/null | grep -qx "$UUID"; then
    if gnome-extensions enable "$UUID" 2>/dev/null; then
      ok "extensión habilitada en esta sesión"
      return 0
    fi
  fi
  local cur new
  cur="$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || echo "@as []")"
  if [[ "$cur" == *"'$UUID'"* ]]; then
    ok "extensión ya habilitada"
  else
    if [ "$cur" = "@as []" ] || [ "$cur" = "[]" ]; then
      new="['$UUID']"
    else
      new="${cur%]}, '$UUID']"
    fi
    if gsettings set org.gnome.shell enabled-extensions "$new" 2>/dev/null; then
      ok "extensión añadida a las habilitadas"
    else
      warn "no pude habilitar la extensión automáticamente; actívala con: gnome-extensions enable $UUID"
    fi
  fi
  log_out_hint=1
}
log_out_hint=0
enable_extension

# --------------------------------------------------------------------------
# Buscar la TV y comprobar que AirPlay está encendido
# --------------------------------------------------------------------------
port_open() { timeout 2 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null; }

discover_tvs() {
  local out="$1" svc
  : >"$out"
  for svc in _airplay._tcp _googlecast._tcp; do
    { timeout 3 avahi-browse -rtp "$svc" 2>/dev/null || true; } |
      awk -F';' '/^=;/ && $3=="IPv4" && $8!="" {print $8 "\t" $4}' >>"$out"
  done
  awk -F'\t' '!seen[$1]++' "$out" >"$out.uniq" && mv "$out.uniq" "$out"
}

step "Buscando la TV en la red"
if [ -n "$TARGET" ]; then
  IP="$TARGET"
  ok "TV indicada a mano: $IP"
else
  TVLIST="$(mktemp)"
  discover_tvs "$TVLIST"
  TVNUM="$(wc -l <"$TVLIST" | tr -d ' ')"
  if [ "$TVNUM" -eq 0 ]; then
    warn "no encontré ninguna TV por mDNS"
    if have_tty && [ "$ASSUME_YES" = 0 ]; then
      IP="$(ask_value 'Escribe la IP de la TV (Enter para omitir):')"
    fi
  elif [ "$TVNUM" -eq 1 ]; then
    IP="$(cut -f1 "$TVLIST")"
    TV_NAME="$(cut -f2 "$TVLIST")"
    ok "TV: $TV_NAME ($IP)"
  else
    printf 'TVs encontradas:\n'
    awk -F'\t' '{printf "  %d) %s (%s)\n", NR, $2, $1}' "$TVLIST"
    if have_tty && [ "$ASSUME_YES" = 0 ]; then
      CHOICE="$(ask_value 'Elige una, o escribe una IP:')"
      if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "$TVNUM" ]; then
        IP="$(sed -n "${CHOICE}p" "$TVLIST" | cut -f1)"
        TV_NAME="$(sed -n "${CHOICE}p" "$TVLIST" | cut -f2)"
      else
        IP="${CHOICE// /}"
      fi
    else
      IP="$(head -1 "$TVLIST" | cut -f1)"
      TV_NAME="$(head -1 "$TVLIST" | cut -f2)"
      warn "varias TVs: uso la primera ($TV_NAME)"
    fi
  fi
  rm -f "$TVLIST"
  [ -n "$IP" ] || warn "sin TV: se instalará todo, pero el botón necesitará TV_SHARE_TARGET"
fi

WAIT_AIRPLAY=0
if [ -n "$IP" ]; then
  if port_open "$IP" 7000; then
    ok "AirPlay activo en la TV (puerto 7000 abierto)"
  else
    WAIT_AIRPLAY=1
    warn "la TV responde, pero AirPlay está APAGADO (puerto 7000 cerrado)"
    if timeout 2 ping -c 1 -W 1 "$IP" >/dev/null 2>&1; then
      printf '  Actívalo en la TV: Inicio → Panel de inicio → AirPlay → AirPlay y HomeKit → Activado\n'
    else
      printf '  La TV no responde en %s: comprueba que está encendida y en la misma Wi-Fi.\n' "$IP"
    fi
    if have_tty && [ "$ASSUME_YES" = 0 ]; then
      while true; do
        ANSWER="$(ask_value 'Cuando lo hayas activado, pulsa Enter para reintentar (n para omitir):')"
        [ "$ANSWER" = "n" ] && break
        if port_open "$IP" 7000; then
          WAIT_AIRPLAY=0
          ok "AirPlay activo en la TV"
          break
        fi
        warn "sigue cerrado; revisa la ruta en el menú de la TV"
      done
    fi
  fi
fi

# --------------------------------------------------------------------------
# Emparejamiento (solo si hay AirPlay y no hay credenciales)
# --------------------------------------------------------------------------
pair_tv() {
  local ip="$1" pid wd
  printf 'Se mostrará un PIN de 4 dígitos en la TV. Escríbelo aquí y pulsa Enter.\n'
  ( for _ in $(seq 1 180); do
      [ -f "$CREDS" ] && break
      sleep 1
    done
    sleep 3
    pkill -INT -f "doubletake -target ${ip}" 2>/dev/null || true ) &
  wd=$!
  "$BINDIR/doubletake" -target "$ip" -pair || true
  kill "$wd" 2>/dev/null || true
  wait "$wd" 2>/dev/null || true
}

if [ -n "$IP" ] && [ "$WAIT_AIRPLAY" = 0 ] && [ "$NO_PAIR" = 0 ]; then
  step "Emparejamiento con la TV"
  if [ -f "$CREDS" ] && [ "$FORCE_PAIR" = 0 ]; then
    ok "ya hay credenciales guardadas en $CREDS"
    printf '  (usa --pair si quieres emparejar de nuevo)\n'
  elif ask "¿Emparejar este equipo con la TV ahora? [S/n]" s; then
    pair_tv "$IP"
    if [ -f "$CREDS" ]; then
      ok "credenciales guardadas en $CREDS"
    else
      warn "no se guardaron credenciales; puedes reintentar con: $BINDIR/doubletake -target $IP -pair"
    fi
  else
    warn "emparejamiento omitido"
  fi
elif [ -n "$IP" ] && [ "$WAIT_AIRPLAY" = 1 ] && [ "$NO_PAIR" = 0 ]; then
  warn "sin emparejar: AirPlay está apagado en la TV"
fi

# Recordar la TV elegida para que el botón no dependa de mDNS.
if [ -n "$IP" ] && [ "$TARGET" != "" ]; then
  install -d "$(dirname "$TV_CONF")"
  printf 'TV_SHARE_TARGET=%s\n' "$IP" >"$TV_CONF"
  ok "TV fijada en $TV_CONF"
fi

# --------------------------------------------------------------------------
# Google Cast opcional
# --------------------------------------------------------------------------
if [ "$WITH_CAST" = 1 ]; then
  step "Google Cast (GNOME Network Displays)"
  if command -v flatpak >/dev/null 2>&1; then
    flatpak remote-add --user --if-not-exists flathub \
      https://flathub.org/repo/flathub.flatpakrepo || true
    flatpak install --user -y flathub org.gnome.NetworkDisplays
    ok "GNOME Network Displays instalado"
  else
    warn "instala flatpak y vuelve a ejecutar con --with-cast"
  fi
fi

# --------------------------------------------------------------------------
# Prueba
# --------------------------------------------------------------------------
if [ "$RUN_TEST" = 0 ] && [ "$ASSUME_YES" = 0 ] && [ -n "$IP" ] &&
   [ "$WAIT_AIRPLAY" = 0 ] && [ -f "$CREDS" ] && have_tty; then
  ask "¿Hacer una prueba de 20 s enviando la pantalla a la TV? [s/N]" n && RUN_TEST=1
fi
if [ "$RUN_TEST" = 1 ]; then
  step "Prueba de 20 segundos"
  printf 'Acepta el diálogo de GNOME para compartir la pantalla si aparece.\n'
  timeout 20 "$BINDIR/compartir-tv" || true
  if [ -f "$CACHE/compartir-tv.log" ]; then
    tail -3 "$CACHE/compartir-tv.log" | sed 's/^/  /'
  fi
fi

# --------------------------------------------------------------------------
# Resumen
# --------------------------------------------------------------------------
step "Listo"
printf '  Botón:        menú rápido de GNOME → "Compartir TV" → AirPlay\n'
printf '  Terminal:     %s\n' "$BINDIR/compartir-tv"
printf '  Diagnóstico:  %s\n' "$BINDIR/check-tv-share.sh"
printf '  Registro:     %s\n' "$LOG"
if [ "$log_out_hint" = 1 ]; then
  printf '\n  %sCierra sesión y vuelve a entrar%s para que aparezca el botón.\n' "$B" "$N"
else
  printf '\n  Si el botón no aparece, cierra sesión y vuelve a entrar.\n'
fi
if [ -z "$IP" ]; then
  printf '\n  No se detectó la TV. Puedes fijarla con:\n'
  printf '    TV_SHARE_TARGET=<ip> %s\n' "$BINDIR/compartir-tv"
fi
