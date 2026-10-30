#!/usr/bin/env bash
# Builds the optional fcitx5-im-watch helper into ~/.local/bin (or $BIN_DIR).
#
# Without it the widget still works: it just checks fcitx5 every 1.5 s instead of
# every 100 ms. Needs a C compiler (Arch: pacman -S base-devel). Safe to re-run.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$HERE/helper/fcitx5-im-watch.c"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
OUT="$BIN_DIR/fcitx5-im-watch"
CC_BIN="${CC:-cc}"

if ! command -v "$CC_BIN" >/dev/null 2>&1; then
  echo "No C compiler ($CC_BIN) found; skipping. The widget keeps working with slower updates." >&2
  echo "Install one with: sudo pacman -S base-devel" >&2
  exit 1
fi

mkdir -p "$BIN_DIR"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

# Prefer a static binary; fall back to a dynamic one if static libc isn't available.
if "$CC_BIN" -O2 -s -static -o "$tmp" "$SRC" 2>/dev/null || "$CC_BIN" -O2 -s -o "$tmp" "$SRC"; then
  install -m 755 "$tmp" "$OUT"
  echo "Built $OUT"
  echo "Load it with: omarchy restart shell"
else
  echo "Build failed; the widget keeps working with slower updates." >&2
  exit 1
fi
