#!/usr/bin/env bash
# Desinstala lo que instaló install.sh. No borra credenciales de emparejamiento
# ni el log; se indican al final por si quieres eliminarlos a mano.
set -euo pipefail

BINDIR="${PREFIX:-$HOME/.local}/bin"
UUID="tv-share@edgar.local"
GEXT="$HOME/.local/share/gnome-shell/extensions/$UUID"

if command -v gnome-extensions >/dev/null 2>&1; then
  gnome-extensions disable "$UUID" 2>/dev/null || true
fi

rm -f "$BINDIR/compartir-tv" "$BINDIR/check-tv-share.sh" \
      "$BINDIR/doubletake" "$BINDIR/doubletake-ctl"
rm -rf "$GEXT"
rm -f "$HOME/.local/share/applications/compartir-tv.desktop"

echo "Desinstalado. Siguen en disco (bórralos si ya no los quieres):"
echo "  ~/.config/doubletake/    credenciales de la TV"
echo "  ~/.cache/compartir-tv.log"
echo "Si el botón sigue en el menú, cierra y vuelve a abrir la sesión."
