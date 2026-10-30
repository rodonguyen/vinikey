#!/usr/bin/env bash
# Installs everything Vinikey needs, in one go:
#   1. fcitx5, fcitx5-bamboo and fcitx5-configtool (pacman asks for your password)
#   2. Bamboo as an fcitx5 input method (Telex unless you already picked another)
#   3. the bar widget, enabled (an older vn-keyboard/vinikey copy is moved over)
#   4. the fast fcitx5-im-watch helper, if a C compiler is available
#   5. a shell restart, so the widget loads
# Run it from a clone of the repo, or from the installed plugin folder. Safe to re-run.
# If a step fails, the fcitx5 config it changed is restored and it exits 1.
set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FCITX_DIR="${FCITX5_CONFIG_DIR:-$HOME/.config/fcitx5}"
PLUGIN_ID="rodonguyen.vinikey"
LEGACY_PLUGIN_IDS=("rodo.vietnamese-input" "vn-keyboard" "vinikey")   # earlier ids; migrated on upgrade
PLUGINS_DIR="${OMARCHY_PLUGINS_DIR:-$HOME/.config/omarchy/plugins}"
SHELL_JSON="${OMARCHY_SHELL_JSON:-$HOME/.config/omarchy/shell.json}"
PLUGIN_DEST="$PLUGINS_DIR/$PLUGIN_ID"
PROFILE="$FCITX_DIR/profile"
BAMBOO_CONF="$FCITX_DIR/conf/bamboo.conf"
BACKUP_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/vinikey/backup-$(date +%Y%m%d_%H%M%S)"
HELPER_SRC="$REPO_DIR/helper/fcitx5-im-watch.c"
HELPER_BIN="${BIN_DIR:-$HOME/.local/bin}/fcitx5-im-watch"

STEP="starting"
STOPPED_FCITX=0
PROFILE_EXISTED=0
CONF_EXISTED=0
PLUGIN_INSTALLED=0
BACKED_UP=0
NEEDS_RESTART=0

say()  { echo "[vinikey] $*"; }
warn() { echo "[vinikey] WARN: $*" >&2; }

has_display() { [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${DISPLAY:-}" ]; }
fcitx_running() { pgrep -x fcitx5 >/dev/null 2>&1; }

# Omarchy runs fcitx5 as a user service with Restart=always. Starting or killing it
# behind the service's back makes the two fight over the D-Bus name and loop, so
# go through the service when it exists.
fcitx_unit() { systemctl --user cat omarchy-fcitx5.service >/dev/null 2>&1; }

# SIGTERM, not `fcitx5-remote -e`: that call D-Bus-starts a fcitx5 just to quit it.
# Returns 0 once no fcitx5 is left.
halt_fcitx() {
  fcitx_unit && systemctl --user stop omarchy-fcitx5.service >/dev/null 2>&1 || true
  fcitx_running && pkill -x fcitx5 >/dev/null 2>&1 || true
  for _ in $(seq 1 20); do fcitx_running || return 0; sleep 0.5; done
  return 1
}

start_fcitx() {
  has_display || return 0
  fcitx_running && return 0
  if fcitx_unit; then
    systemctl --user start omarchy-fcitx5.service >/dev/null 2>&1 || true
  elif command -v fcitx5 >/dev/null 2>&1; then
    setsid -f fcitx5 --disable notificationitem >/dev/null 2>&1 || true
  fi
}

rollback() {
  warn "failed during: $STEP. Restoring previous state."
  # fcitx5 must be stopped while its files are restored, or it rewrites them on exit.
  [ "$STOPPED_FCITX" = 1 ] && { halt_fcitx || true; }
  if [ "$BACKED_UP" = 1 ]; then
    if [ "$PROFILE_EXISTED" = 1 ] && [ -f "$BACKUP_DIR/profile" ]; then cp -f "$BACKUP_DIR/profile" "$PROFILE" || true
    elif [ "$PROFILE_EXISTED" = 0 ]; then rm -f "$PROFILE"; fi
    if [ "$CONF_EXISTED" = 1 ] && [ -f "$BACKUP_DIR/bamboo.conf" ]; then cp -f "$BACKUP_DIR/bamboo.conf" "$BAMBOO_CONF" || true
    elif [ "$CONF_EXISTED" = 0 ]; then rm -f "$BAMBOO_CONF"; fi
    warn "backups are in $BACKUP_DIR"
  fi
  [ "$PLUGIN_INSTALLED" = 1 ] && rm -rf "$PLUGIN_DEST"
  [ "$STOPPED_FCITX" = 1 ] && start_fcitx
  return 0
}

on_error() {
  local code=$?
  trap - ERR
  rollback
  exit "$code"
}

step() { STEP="$1"; say "$1"; }

install_packages() {
  local pkgs=(fcitx5 fcitx5-bamboo fcitx5-configtool)
  if pacman -Q "${pkgs[@]}" >/dev/null 2>&1; then
    say "packages already installed"
    return 0
  fi
  command -v pacman >/dev/null 2>&1 || { warn "pacman not found; Vinikey is for Omarchy (Arch)"; return 1; }
  # Fail early with a clear message instead of a long pacman timeout.
  if ! curl -fsS --max-time 8 -o /dev/null https://archlinux.org 2>/dev/null; then
    warn "no network; cannot install ${pkgs[*]}"
    return 1
  fi
  if command -v omarchy >/dev/null 2>&1; then
    omarchy pkg add "${pkgs[@]}"
  else
    sudo pacman -S --needed --noconfirm "${pkgs[@]}"
  fi
}

# Bamboo already in the profile and Ctrl+Space pointing at it? Then fcitx5 is left
# running untouched. (A missing bamboo.conf is fine: Bamboo defaults to Telex.)
config_needed() {
  ! { [ -f "$PROFILE" ] && grep -qx 'Name=bamboo' "$PROFILE" &&
      ! grep -qx 'DefaultIM=keyboard-us' "$PROFILE"; }
}

backup_config() {
  mkdir -p "$BACKUP_DIR"
  BACKED_UP=1
  if [ -f "$PROFILE" ]; then PROFILE_EXISTED=1; cp -p "$PROFILE" "$BACKUP_DIR/profile"; fi
  if [ -f "$BAMBOO_CONF" ]; then CONF_EXISTED=1; cp -p "$BAMBOO_CONF" "$BACKUP_DIR/bamboo.conf"; fi
}

stop_fcitx() {
  STOPPED_FCITX=1
  halt_fcitx && return 0
  warn "fcitx5 did not exit; refusing to edit config while it runs"
  return 1
}

# Ctrl+Space toggles between the first method (plain keyboard) and DefaultIM. If
# DefaultIM is still the plain keyboard the toggle has nothing to switch to, so
# point it at bamboo. A DefaultIM the user chose (another method) is left alone.
ensure_default_im() {
  local file="$1" tmp
  grep -qx 'DefaultIM=keyboard-us' "$file" || return 0
  tmp="$(mktemp)"
  sed 's/^DefaultIM=keyboard-us$/DefaultIM=bamboo/' "$file" > "$tmp"
  mv "$tmp" "$file"
}

# Add a bamboo entry to an existing profile without touching other input methods.
merge_profile() {
  local file="$1" tmp next
  if grep -qx 'Name=bamboo' "$file"; then
    ensure_default_im "$file"
    return 0
  fi
  grep -q '^\[GroupOrder\]' "$file" || { warn "unexpected profile format in $file"; return 1; }
  next=$(( $(grep -o '^\[Groups/0/Items/[0-9]*\]' "$file" | grep -o '[0-9]*' | sort -n | tail -1) + 1 ))
  tmp="$(mktemp)"
  awk -v n="$next" '
    /^\[GroupOrder\]/ && !done {
      printf "[Groups/0/Items/%s]\n# Name\nName=bamboo\n# Layout\nLayout=\n\n", n
      done = 1
    }
    { print }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
  ensure_default_im "$file"
}

# No profile yet: US keyboard first (typing as usual), Bamboo as the Ctrl+Space method.
write_default_profile() {
  cat >"$1" <<'EOF'
[Groups/0]
# Group Name
Name=Default
# Layout
Default Layout=us
# Default Input Method
DefaultIM=bamboo

[Groups/0/Items/0]
# Name
Name=keyboard-us
# Layout
Layout=

[Groups/0/Items/1]
# Name
Name=bamboo
# Layout
Layout=

[GroupOrder]
0=Default
EOF
}

# Telex is the default for new installs. A method someone already chose (VNI,
# VIQR, ...) is theirs, so only fill in InputMethod when it is missing.
ensure_input_method() {
  local file="$1"
  if [ ! -s "$file" ]; then
    printf 'InputMethod=Telex\n' > "$file"
  elif ! grep -q '^InputMethod=' "$file"; then
    printf 'InputMethod=Telex\n' >> "$file"
  fi
}

write_config() {
  mkdir -p "$FCITX_DIR/conf"
  if [ -f "$PROFILE" ]; then
    merge_profile "$PROFILE"
  else
    write_default_profile "$PROFILE"
  fi
  ensure_input_method "$BAMBOO_CONF"
}

verify_fcitx() {
  has_display || { say "no graphical session; skipping live check"; return 0; }
  command -v fcitx5-remote >/dev/null 2>&1 || { warn "fcitx5-remote missing"; return 1; }
  for _ in $(seq 1 20); do fcitx_running && fcitx5-remote >/dev/null 2>&1 && break; sleep 0.5; done
  fcitx_running || { warn "fcitx5 did not start"; return 1; }
  fcitx5-remote -s bamboo >/dev/null 2>&1 || true
  sleep 0.5
  if [ "$(fcitx5-remote -n 2>/dev/null || true)" != "bamboo" ]; then
    warn "fcitx5 could not switch to bamboo"
    return 1
  fi
  # Leave fcitx5 inactive (plain keyboard), as a fresh login would. Do not use
  # `-s keyboard-us`: that selects the keyboard as the *active* method, and then
  # Ctrl+Space toggles between two identical keyboards and appears broken.
  fcitx5-remote -c >/dev/null 2>&1 || true
  say "bamboo loads and switches OK"
}

setup_fcitx() {
  if ! config_needed; then
    say "Bamboo already set up; leaving your fcitx5 config as it is"
    return 0
  fi
  step "backing up fcitx5 config";   backup_config
  step "stopping fcitx5";            stop_fcitx
  step "writing fcitx5 config";      write_config
  step "starting fcitx5";            start_fcitx
  step "checking Bamboo";            verify_fcitx
}

# Rename the bar/plugin entry with id $1 to $2 in shell.json, keeping its position and
# settings. Returns 1 (and changes nothing) when there is no $1 entry, when a $2 entry
# already exists, or when jq is missing. Writes in place to keep the file's mode.
rename_shell_entry() {
  local old="$1" new="$2" tmp
  [ -f "$SHELL_JSON" ] && command -v jq >/dev/null 2>&1 || return 1
  jq -e --arg old "$old" --arg new "$new" \
    '[.. | objects | select(has("id")) | .id] | index($old) != null and index($new) == null' \
    "$SHELL_JSON" >/dev/null 2>&1 || return 1
  tmp="$(mktemp)"
  if jq --arg old "$old" --arg new "$new" \
       'walk(if type == "object" and .id == $old then .id = $new else . end)' "$SHELL_JSON" >"$tmp"; then
    cat "$tmp" >"$SHELL_JSON"
    rm -f "$tmp"
    return 0
  fi
  rm -f "$tmp"
  return 1
}

# Puts this repo at $PLUGIN_DEST. Run from there already (`omarchy plugin add`), it
# has nothing to copy. A git clone that is already installed is left alone, so local
# work is never overwritten; `omarchy plugin update` updates it.
place_plugin() {
  local src dest
  src="$(cd "$REPO_DIR" && pwd -P)"
  dest="$( [ -d "$PLUGIN_DEST" ] && cd "$PLUGIN_DEST" && pwd -P || true)"
  if [ "$src" = "$dest" ]; then
    return 0
  fi
  if [ -d "$PLUGIN_DEST/.git" ]; then
    say "already installed at $PLUGIN_DEST; update it with: omarchy plugin update $PLUGIN_ID"
    return 0
  fi
  mkdir -p "$PLUGINS_DIR"
  rm -rf "$PLUGIN_DEST"
  cp -a "$REPO_DIR" "$PLUGIN_DEST"
  PLUGIN_INSTALLED=1
  NEEDS_RESTART=1
  say "copied the widget to $PLUGIN_DEST"
}

# The widget is optional: a problem here warns but never fails the whole install.
install_plugin() {
  command -v omarchy >/dev/null 2>&1 || { warn "omarchy CLI not found; skipping the bar widget"; return 0; }
  if ! omarchy plugin validate "$REPO_DIR" >/dev/null 2>&1; then
    warn "plugin failed validation; skipping the bar widget"
    return 0
  fi
  place_plugin
  # Upgrade from earlier ids. The shell must know the new id before its bar entry
  # is renamed, so the entry keeps its place and settings (e.g. the panel language).
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  local legacy
  for legacy in "${LEGACY_PLUGIN_IDS[@]}"; do
    if rename_shell_entry "$legacy" "$PLUGIN_ID"; then
      NEEDS_RESTART=1
      say "moved bar entry $legacy to $PLUGIN_ID"
    elif [ -d "$PLUGINS_DIR/$legacy" ]; then
      omarchy plugin disable "$legacy" >/dev/null 2>&1 || true
    fi
    if [ -d "$PLUGINS_DIR/$legacy" ]; then
      rm -rf "${PLUGINS_DIR:?}/$legacy"
      say "removed old widget $legacy"
    fi
  done
  if command -v jq >/dev/null 2>&1 &&
     omarchy plugin list --json 2>/dev/null | jq -e --arg id "$PLUGIN_ID" '.[] | select(.id == $id and .enabled)' >/dev/null 2>&1; then
    say "bar widget already enabled"
  elif omarchy plugin enable "$PLUGIN_ID" >/dev/null 2>&1; then
    say "bar widget enabled"
  else
    warn "could not enable the bar widget; run: omarchy plugin enable $PLUGIN_ID"
  fi
  # Past this point a failure should not delete a working plugin.
  PLUGIN_INSTALLED=0
  return 0
}

find_cc() { command -v "${CC:-cc}" || command -v gcc || command -v clang; }

# Builds the fcitx5-im-watch helper (label updates within 100 ms). Optional like the
# widget: any problem warns and returns 0, and the widget then checks every 1.5 s.
# Rebuilds only when the source is newer than the binary. The new binary replaces the
# old one by rename, so a running helper keeps working until the shell restarts.
build_helper() {
  [ -f "$HELPER_SRC" ] || { warn "helper source missing: $HELPER_SRC"; return 0; }
  if [ -x "$HELPER_BIN" ] && ! [ "$HELPER_SRC" -nt "$HELPER_BIN" ]; then
    say "fcitx5-im-watch helper up to date"
    return 0
  fi
  local cc tmp log
  if ! cc="$(find_cc)" || [ -z "$cc" ]; then
    warn "no C compiler; the EN/VI label will update every 1.5 s instead of within 100 ms."
    warn "for the fast helper: sudo pacman -S base-devel, then run this again"
    return 0
  fi
  if ! mkdir -p "$(dirname "$HELPER_BIN")" ||
     ! tmp="$(mktemp "$HELPER_BIN.XXXXXX" 2>/dev/null)" ||
     ! log="$(mktemp 2>/dev/null)"; then
    [ -n "${tmp:-}" ] && rm -f "$tmp"
    warn "cannot write $HELPER_BIN; the EN/VI label will update every 1.5 s"
    return 0
  fi
  # Static if the toolchain allows (smallest memory footprint), else dynamic (libc only).
  if "$cc" -O2 -s -static -o "$tmp" "$HELPER_SRC" >"$log" 2>&1 ||
     "$cc" -O2 -s -o "$tmp" "$HELPER_SRC" >"$log" 2>&1; then
    chmod 755 "$tmp" && mv -f "$tmp" "$HELPER_BIN" && rm -f "$log" && {
      NEEDS_RESTART=1
      say "built the fcitx5-im-watch helper ($HELPER_BIN)"
      return 0
    }
  fi
  warn "building fcitx5-im-watch failed; the EN/VI label will update every 1.5 s. Compiler output:"
  sed 's/^/    /' "$log" >&2 || true
  rm -f "$tmp" "$log"
  return 0
}

# The shell keeps running the widget code it already loaded.
restart_shell() {
  [ "$NEEDS_RESTART" = 1 ] || return 0
  if has_display && command -v omarchy >/dev/null 2>&1; then
    omarchy restart shell >/dev/null 2>&1 && { say "restarted the shell to load the widget"; return 0; }
  fi
  say "run 'omarchy restart shell' to load the widget"
}

main() {
  trap on_error ERR
  step "installing packages";        install_packages
  setup_fcitx
  step "installing the bar widget";  install_plugin
  step "building the fast helper";   build_helper
  trap - ERR
  restart_shell
  say "done. Press Ctrl+Space to switch between English and Vietnamese."
}

# Allow `source`-ing for tests without running anything.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
