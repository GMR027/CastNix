#!/usr/bin/env bash
# Diagnóstico de la extensión "Compartir pantalla a la TV" (tv-share@edgar.local)
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
IP="$(timeout 1 avahi-resolve -4 -n LGwebOSTV.local 2>/dev/null | awk '{print $2}')"
[ -n "${IP:-}" ] || IP="$(timeout 3 avahi-browse -rtp _googlecast._tcp 2>/dev/null |
                               awk -F';' '/^=;/{print $8; exit}')"
[ -n "${IP:-}" ] || IP="192.168.1.108"
echo "IP: $IP"
if timeout 2 bash -c "exec 3<>/dev/tcp/$IP/7000" 2>/dev/null; then
  echo "AirPlay: ACTIVADO (puerto 7000 abierto)"
else
  echo "AirPlay: APAGADO en la TV (puerto 7000 cerrado)"
  echo "  Actívalo en la TV: Inicio → Panel de inicio → AirPlay → AirPlay y HomeKit → Activado"
fi

echo
echo "== archivos =="
ls -l "$HOME/.local/share/gnome-shell/extensions/$UUID/"
