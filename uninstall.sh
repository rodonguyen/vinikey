#!/usr/bin/env bash
# Removes what install.sh added for Vinikey itself:
#   - the bar widget (through `omarchy plugin remove`, which asks first; --yes skips that)
#   - the fcitx5-im-watch helper and its state file
# Your typing setup is left alone: fcitx5, Bamboo, your input method and its options
# keep working without Vinikey. The end of the output says how to remove those too.
set -euo pipefail

PLUGIN_ID="rodonguyen.vinikey"
HELPER_BIN="${BIN_DIR:-$HOME/.local/bin}/fcitx5-im-watch"
STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/fcitx5-im-watch"
BACKUPS="${XDG_STATE_HOME:-$HOME/.local/state}/vinikey"

say() { echo "[vinikey] $*"; }

yes=()
case "${1:-}" in
  --yes | -y) yes=(--yes) ;;
  "") ;;
  *) echo "Usage: uninstall.sh [--yes]" >&2; exit 2 ;;
esac

# The helper dies with the shell that runs it; the restart below ends it. Removing the
# binary first keeps the widget, if still loaded, from starting it again.
rm -f "$HELPER_BIN" "$STATE_FILE" "$STATE_FILE.lock"
say "removed the fcitx5-im-watch helper"

# Last, since this script may live inside the folder being removed (bash has it open).
if command -v omarchy >/dev/null 2>&1 &&
   omarchy plugin list --json 2>/dev/null | grep -q "\"$PLUGIN_ID\""; then
  omarchy plugin remove "$PLUGIN_ID" "${yes[@]}"
  omarchy restart shell >/dev/null 2>&1 || true
  say "removed the bar widget"
else
  say "the bar widget is not installed"
fi

say "done. Vietnamese typing itself still works (Ctrl+Space)."
[ -d "$BACKUPS" ] && say "fcitx5 config backups from install.sh are in $BACKUPS"
say "to remove Bamboo as well: sudo pacman -Rns fcitx5-bamboo"
