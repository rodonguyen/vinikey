#!/usr/bin/env bash
# install.sh, one function at a time, in a throwaway HOME. fcitx5, systemd and the
# omarchy CLI are all stubbed, so nothing here can touch the running desktop.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
source "$HERE/lib.sh"
RESULTS="$(mktemp)"   # cases run in subshells, so results are counted through a file
trap 'rm -f "$RESULTS"' EXIT
ok()  { echo ok >>"$RESULTS"; echo "ok   - $1"; }
nok() { echo FAIL >>"$RESULTS"; echo "FAIL - $1"; }

# Sets up a sandbox and sources install.sh with every outside effect stubbed.
#   $1 = compiler stub: ok | fail | static-fails | none
sandbox() {
  SANDBOX="$(mktemp -d)"
  export HOME="$SANDBOX/home" XDG_STATE_HOME="$SANDBOX/state"
  export FCITX5_CONFIG_DIR="$SANDBOX/fcitx5" OMARCHY_PLUGINS_DIR="$SANDBOX/plugins"
  export OMARCHY_SHELL_JSON="$SANDBOX/shell.json" BIN_DIR="$SANDBOX/bin"
  unset WAYLAND_DISPLAY DISPLAY CC
  mkdir -p "$HOME" "$SANDBOX/fake"
  # A fake omarchy CLI that logs its calls; `plugin list` reports nothing enabled.
  OMARCHY_LOG="$SANDBOX/omarchy.log"
  printf '#!/bin/sh\necho "$*" >>"%s"\n[ "$1 $2" = "plugin list" ] && echo "[]"\nexit 0\n' "$OMARCHY_LOG" >"$SANDBOX/fake/omarchy"
  printf '#!/bin/sh\nexit 0\n' >"$SANDBOX/fake/omarchy-shell"
  chmod +x "$SANDBOX/fake/"*
  export PATH="$SANDBOX/fake:$PATH"
  CC_LOG="$SANDBOX/cc.log"
  STUB="$SANDBOX/cc"
  case "$1" in
    ok)           printf '#!/bin/sh\necho "$@" >>"%s"\nwhile [ "$1" != -o ]; do shift; done\necho "#!/bin/sh" >"$2"\n' "$CC_LOG" >"$STUB" ;;
    fail)         printf '#!/bin/sh\necho "$@" >>"%s"\necho "boom: cannot compile" >&2\nexit 1\n' "$CC_LOG" >"$STUB" ;;
    static-fails) printf '#!/bin/sh\necho "$@" >>"%s"\ncase "$*" in *-static*) echo "no libc.a" >&2; exit 1;; esac\nwhile [ "$1" != -o ]; do shift; done\necho "#!/bin/sh" >"$2"\n' "$CC_LOG" >"$STUB" ;;
  esac
  chmod +x "$STUB" 2>/dev/null || true
  # shellcheck source=../install.sh
  source "$REPO/install.sh"
  set +e; trap - ERR
  halt_fcitx() { :; }; start_fcitx() { :; }; fcitx_unit() { return 1; }; fcitx_running() { return 1; }
  if [ "$1" = none ]; then find_cc() { return 1; }; else find_cc() { echo "$STUB"; }; fi
}

# ---- build_helper
(
  sandbox ok
  OUT="$(build_helper 2>&1)"; RC=$?
  check "helper: builds and installs"            '[ $RC = 0 ] && [ -x "$HELPER_BIN" ]'
  check "helper: tries a static build first"     'grep -q -- -static "$CC_LOG"'
  check "helper: leaves no temp files"           '[ "$(ls "$BIN_DIR")" = fcitx5-im-watch ]'
  : >"$CC_LOG"; OUT2="$(build_helper 2>&1)"
  check "helper: second run does not rebuild"    '[ ! -s "$CC_LOG" ] && grep -q "up to date" <<<"$OUT2"'
  cp "$HELPER_SRC" "$SANDBOX/src.c"; touch -d "+1 minute" "$SANDBOX/src.c"
  HELPER_SRC="$SANDBOX/src.c"; build_helper >/dev/null 2>&1
  check "helper: newer source triggers a rebuild" '[ -s "$CC_LOG" ]'
  rm -rf "$SANDBOX"
)
(
  sandbox fail
  OUT="$(build_helper 2>&1)"; RC=$?
  check "helper: compile error warns, returns 0, installs nothing" \
    '[ $RC = 0 ] && grep -q boom <<<"$OUT" && [ -z "$(ls -A "$BIN_DIR" 2>/dev/null)" ]'
  rm -rf "$SANDBOX"
)
(
  sandbox static-fails
  build_helper >/dev/null 2>&1; RC=$?
  check "helper: falls back to a dynamic build"  '[ $RC = 0 ] && [ -x "$HELPER_BIN" ] && [ "$(wc -l <"$CC_LOG")" = 2 ]'
  rm -rf "$SANDBOX"
)
(
  sandbox none
  OUT="$(build_helper 2>&1)"; RC=$?
  check "helper: no compiler warns, returns 0"   '[ $RC = 0 ] && grep -q base-devel <<<"$OUT" && [ ! -e "$HELPER_BIN" ]'
  rm -rf "$SANDBOX"
)

# ---- fcitx5 config
(
  sandbox none
  write_config
  check "config: fresh profile has keyboard then bamboo, DefaultIM=bamboo" \
    'grep -qx "Name=keyboard-us" "$PROFILE" && grep -qx "Name=bamboo" "$PROFILE" && grep -qx "DefaultIM=bamboo" "$PROFILE"'
  check "config: fresh install uses Telex"       'grep -qx "InputMethod=Telex" "$BAMBOO_CONF"'
  check "config: nothing left to do afterwards"  '! config_needed'
  rm -rf "$SANDBOX"
)
(
  sandbox none
  mkdir -p "$FCITX5_CONFIG_DIR/conf"
  printf '[Groups/0]\nName=Default\nDefault Layout=de\nDefaultIM=keyboard-de\n\n[Groups/0/Items/0]\nName=keyboard-de\nLayout=\n\n[Groups/0/Items/1]\nName=mozc\nLayout=\n\n[GroupOrder]\n0=Default\n' >"$PROFILE"
  printf 'InputMethod=VNI\nModernStyle=True\n' >"$BAMBOO_CONF"
  check "config: a profile without bamboo needs setup" 'config_needed'
  write_config
  check "config: bamboo added as the next item, others kept" \
    'grep -qx "\[Groups/0/Items/2\]" "$PROFILE" && grep -qx "Name=mozc" "$PROFILE" && grep -qx "Name=bamboo" "$PROFILE"'
  check "config: a non-US DefaultIM someone chose is kept" 'grep -qx "DefaultIM=keyboard-de" "$PROFILE"'
  check "config: an existing method (VNI) and options are kept" \
    '[ "$(cat "$BAMBOO_CONF")" = "$(printf "InputMethod=VNI\nModernStyle=True")" ]'
  rm -rf "$SANDBOX"
)
(
  sandbox none
  mkdir -p "$FCITX5_CONFIG_DIR"
  printf '[Groups/0]\nDefaultIM=keyboard-us\n\n[Groups/0/Items/0]\nName=keyboard-us\n\n[Groups/0/Items/1]\nName=bamboo\n\n[GroupOrder]\n0=Default\n' >"$PROFILE"
  check "config: DefaultIM=keyboard-us (Ctrl+Space does nothing) needs setup" 'config_needed'
  write_config
  check "config: DefaultIM fixed to bamboo"      'grep -qx "DefaultIM=bamboo" "$PROFILE"'
  rm -rf "$SANDBOX"
)
(
  sandbox none
  mkdir -p "$FCITX5_CONFIG_DIR"
  printf 'garbage\n' >"$PROFILE"
  cp "$PROFILE" "$SANDBOX/before"
  install_packages() { :; }; install_plugin() { :; }; build_helper() { :; }; restart_shell() { :; }
  OUT="$( (set -e; main) 2>&1)"; RC=$?
  check "config: an unknown profile format fails and is restored" \
    '[ $RC != 0 ] && grep -q "Restoring previous state" <<<"$OUT" && cmp -s "$PROFILE" "$SANDBOX/before"'
  rm -rf "$SANDBOX"
)

# ---- main: optional steps never fail the install
(
  sandbox fail
  install_packages() { :; }; restart_shell() { :; }
  OUT="$( (set -e; main) 2>&1)"; RC=$?
  check "main: helper and widget problems keep the install successful" \
    '[ $RC = 0 ] && ! grep -q "Restoring previous state" <<<"$OUT" && [ -f "$PROFILE" ]'
  rm -rf "$SANDBOX"
)

# ---- plugin placement
(
  sandbox none
  install_plugin >/dev/null 2>&1
  check "plugin: copied into the plugins folder"  '[ -f "$PLUGIN_DEST/manifest.json" ] && [ -f "$PLUGIN_DEST/BarWidget.qml" ]'
  check "plugin: enabled"                          'grep -qx "plugin enable $PLUGIN_ID" "$OMARCHY_LOG"'
  check "plugin: shell restart requested"          '[ "$NEEDS_RESTART" = 1 ]'
  rm -rf "$SANDBOX"
)
(
  sandbox none
  mkdir -p "$PLUGIN_DEST/.git"; echo "local work" >"$PLUGIN_DEST/mine.txt"
  OUT="$(install_plugin 2>&1)"
  check "plugin: an installed git clone is never overwritten" \
    '[ -f "$PLUGIN_DEST/mine.txt" ] && grep -q "omarchy plugin update" <<<"$OUT"'
  rm -rf "$SANDBOX"
)
(
  sandbox none
  mkdir -p "$PLUGINS_DIR"
  cp -a "$REPO" "$PLUGIN_DEST"
  REPO_DIR="$PLUGIN_DEST"
  NEEDS_RESTART=0
  install_plugin >/dev/null 2>&1
  check "plugin: run from the installed folder, nothing is copied or deleted" \
    '[ -f "$PLUGIN_DEST/install.sh" ] && [ "$NEEDS_RESTART" = 0 ]'
  rm -rf "$SANDBOX"
)
(
  sandbox none
  mkdir -p "$PLUGINS_DIR/vinikey"
  printf '%s\n' '{"bar":{"layout":{"right":[{"id":"omarchy.clock"},{"id":"vinikey","language":"en"}]}}}' >"$SHELL_JSON"
  chmod 600 "$SHELL_JSON"
  install_plugin >/dev/null 2>&1
  if command -v jq >/dev/null 2>&1; then
    check "plugin: old bar entry renamed in place, settings kept" \
      '[ "$(jq -c ".bar.layout.right[1]" "$SHELL_JSON")" = "{\"id\":\"$PLUGIN_ID\",\"language\":\"en\"}" ]'
    check "plugin: shell.json keeps its mode"      '[ "$(stat -c %a "$SHELL_JSON")" = 600 ]'
  else
    skip "plugin: entry rename (jq not installed)"
  fi
  check "plugin: old plugin folder removed"        '[ ! -e "$PLUGINS_DIR/vinikey" ]'
  rm -rf "$SANDBOX"
)
if command -v jq >/dev/null 2>&1; then
  (
    sandbox none
    printf '%s\n' '{"bar":{"layout":{"right":[{"id":"vinikey"},{"id":"rodonguyen.vinikey"}]}}}' >"$SHELL_JSON"
    rename_shell_entry vinikey "$PLUGIN_ID"; RC=$?
    check "plugin: no duplicate entry when the new id is already there" \
      '[ $RC = 1 ] && [ "$(jq -r ".bar.layout.right[0].id" "$SHELL_JSON")" = vinikey ]'
    rm -rf "$SANDBOX"
  )
fi

# ---- uninstall.sh
(
  sandbox none
  export XDG_RUNTIME_DIR="$SANDBOX/run"; mkdir -p "$BIN_DIR" "$XDG_RUNTIME_DIR"
  touch "$HELPER_BIN" "$XDG_RUNTIME_DIR/fcitx5-im-watch" "$XDG_RUNTIME_DIR/fcitx5-im-watch.lock"
  # This fake omarchy reports the widget as installed.
  printf '#!/bin/sh\necho "$*" >>"%s"\n[ "$1 $2" = "plugin list" ] && echo "[{\\"id\\":\\"rodonguyen.vinikey\\"}]"\nexit 0\n' "$OMARCHY_LOG" >"$SANDBOX/fake/omarchy"
  OUT="$(bash "$REPO/uninstall.sh" --yes 2>&1)"; RC=$?
  check "uninstall: removes the helper and its state file" \
    '[ $RC = 0 ] && [ ! -e "$HELPER_BIN" ] && [ -z "$(ls -A "$XDG_RUNTIME_DIR")" ]'
  check "uninstall: removes the widget through omarchy, passing --yes" \
    'grep -qx "plugin remove rodonguyen.vinikey --yes" "$OMARCHY_LOG"'
  check "uninstall: leaves the fcitx5 setup alone" '[ ! -e "$FCITX5_CONFIG_DIR" ] && grep -q "pacman -Rns fcitx5-bamboo" <<<"$OUT"'
  OUT="$(bash "$REPO/uninstall.sh" --bogus 2>&1)"; RC=$?
  check "uninstall: unknown option exits 2 without removing anything" '[ $RC = 2 ]'
  rm -rf "$SANDBOX"
)

PASSED=$(grep -c '^ok$' "$RESULTS"); FAILED=$(grep -c '^FAIL$' "$RESULTS")
finish
