#!/usr/bin/env bash
# Diagnóstico de la extensión "Compartir pantalla a la TV" (tv-share@edgar.local)
# y del estado de AirPlay de la TV.
UUID="tv-share@edgar.local"

echo "== ¿la ve el shell? =="
gdbus call --session --dest org.gnome.Shell.Extensions \
  --object-path /org/gnome/Shell/Extensions \
  --method org.gnome.Shell.Extensions.GetExtensionInfo "$UUID" 2>&1 | head -3

echo
echo "== estado =="
gnome-extensions info "$UUID" 2>&1 | head -8

echo
echo "== errores de la extensión (si hay) =="
gdbus call --session --dest org.gnome.Shell.Extensions \
  --object-path /org/gnome/Shell/Extensions \
  --method org.gnome.Shell.Extensions.GetExtensionErrors "$UUID" 2>&1 | head -5

echo
echo "== errores JS en el journal de esta sesión =="
journalctl --user -b --no-pager 2>/dev/null | grep -i "tv-share" | tail -10

echo
echo "== TV: ¿AirPlay disponible? =="
# Misma resolución que compartir-tv: config, nombre .local y mDNS.
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/compartir-tv.conf"
CFG_TARGET=""; CFG_NAME=""; CFG_HOST=""
if [ -r "$CONF" ]; then
  while IFS='=' read -r key value; do
    case "$key" in
      TV_SHARE_TARGET) CFG_TARGET="$value" ;;
      TV_SHARE_NAME)   CFG_NAME="$value" ;;
      TV_SHARE_HOST)   CFG_HOST="$value" ;;
    esac
  done < "$CONF"
fi

mdns_ip() {
  timeout 3 avahi-browse -rtp "$1" 2>/dev/null |
    awk -F';' -v want="${CFG_NAME}" \
      '/^=;/ && (want == "" || index(tolower($4), tolower(want))) {print $8; exit}'
}

IP="${TV_SHARE_TARGET:-$CFG_TARGET}"
if [ -z "$IP" ]; then
  IP="$(timeout 1 avahi-resolve -4 -n "${TV_SHARE_HOST:-${CFG_HOST:-LGwebOSTV.local}}" 2>/dev/null | awk '{print $2}')"
fi
[ -n "$IP" ] || IP="$(mdns_ip _airplay._tcp)"
[ -n "$IP" ] || IP="$(mdns_ip _googlecast._tcp)"

if [ -z "$IP" ]; then
  echo "IP: no se encontró ninguna TV por mDNS"
  echo "  Fíjala con: TV_SHARE_TARGET=<ip> ~/.local/bin/compartir-tv"
else
  echo "IP: $IP"
  if timeout 2 bash -c "exec 3<>/dev/tcp/$IP/7000" 2>/dev/null; then
    echo "AirPlay: ACTIVADO (puerto 7000 abierto)"
  else
    if timeout 2 ping -c 1 -W 1 "$IP" >/dev/null 2>&1; then
      echo "AirPlay: APAGADO en la TV (puerto 7000 cerrado)"
      echo "  Actívalo en la TV: Inicio → Panel de inicio → AirPlay → AirPlay y HomeKit → Activado"
    else
      echo "La TV no responde en $IP (¿apagada o en otra red?)"
    fi
  fi
fi

echo
echo "== archivos =="
ls -l "$HOME/.local/share/gnome-shell/extensions/$UUID/"

echo
echo "== último intento de transmisión =="
tail -5 "${XDG_CACHE_HOME:-$HOME/.cache}/compartir-tv.log" 2>/dev/null || echo "(sin registro todavía)"
