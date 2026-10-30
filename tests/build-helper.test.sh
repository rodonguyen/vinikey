#!/usr/bin/env bash
# scripts/build-helper.sh: installs into BIN_DIR, fails cleanly without a compiler.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
SCRIPT="$HERE/../scripts/build-helper.sh"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

if command -v cc >/dev/null 2>&1; then
  out="$(BIN_DIR="$T/bin" bash "$SCRIPT" 2>&1)"; rc=$?
  check "builds into BIN_DIR" '[ $rc = 0 ] && [ -x "$T/bin/fcitx5-im-watch" ]'
  check "leaves only the binary behind" '[ "$(ls -A "$T/bin")" = fcitx5-im-watch ]'
  check "tells how to load it" 'grep -q "omarchy restart shell" <<<"$out"'
else
  skip "build: no cc"
fi

out="$(CC=no-such-compiler BIN_DIR="$T/none" bash "$SCRIPT" 2>&1)"; rc=$?
check "no compiler: exits 1 and says how to get one" '[ $rc = 1 ] && grep -q "base-devel" <<<"$out"'
check "no compiler: installs nothing" '[ ! -e "$T/none" ]'

printf '#!/bin/sh\necho "boom" >&2\nexit 1\n' >"$T/badcc"; chmod +x "$T/badcc"
out="$(CC="$T/badcc" BIN_DIR="$T/bad" bash "$SCRIPT" 2>&1)"; rc=$?
check "compiler error: exits 1, shows the error, installs nothing" \
  '[ $rc = 1 ] && grep -q boom <<<"$out" && [ ! -e "$T/bad/fcitx5-im-watch" ]'

finish
