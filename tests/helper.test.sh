#!/usr/bin/env bash
# fcitx5-im-watch against a private D-Bus daemon: it never D-Bus-starts fcitx5, it
# reports input method changes, and the shared state-file mode hands over cleanly.
# Never touches the real session bus: the address and XDG_RUNTIME_DIR point into a
# temp dir before anything runs.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

for tool in cc dbus-daemon dbus-send; do
  command -v "$tool" >/dev/null 2>&1 || { skip "helper tests: $tool not installed"; finish; exit; }
done

T="$(mktemp -d)"
PIDS=()
cleanup() {
  for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null; done
  [ -n "${BUS_PID:-}" ] && kill "$BUS_PID" 2>/dev/null
  rm -rf "$T"
}
trap cleanup EXIT

mkdir -p "$T/run" "$T/services" "$T/bus"
export XDG_RUNTIME_DIR="$T/run"

# A service file that would activate "fcitx5" by touching a marker, so an
# auto-start shows up as that file.
printf '#!/bin/sh\ntouch "%s/activated"\n' "$T" >"$T/activate.sh"
chmod +x "$T/activate.sh"
printf '[D-BUS Service]\nName=org.fcitx.Fcitx5\nExec=%s/activate.sh\n' "$T" >"$T/services/org.fcitx.Fcitx5.service"

# unix:dir= gives a path socket; the helper doesn't speak abstract sockets.
cat >"$T/bus.conf" <<EOF
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:dir=$T/bus</listen>
  <servicedir>$T/services</servicedir>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
EOF

{ read -r DBUS_SESSION_BUS_ADDRESS; read -r BUS_PID; } < <(dbus-daemon --config-file="$T/bus.conf" --fork --print-address=1 --print-pid=1)
export DBUS_SESSION_BUS_ADDRESS
case "$DBUS_SESSION_BUS_ADDRESS" in
  unix:path=$T/*) ;;
  *) nok "private bus did not start at a path socket ($DBUS_SESSION_BUS_ADDRESS)"; finish; exit ;;
esac

HELPER="$T/fcitx5-im-watch"
cc -O2 -Wall -Wextra -Werror -o "$HELPER" "$HERE/../helper/fcitx5-im-watch.c" || { nok "helper compiles"; finish; exit; }
ok "helper compiles with -Wall -Wextra -Werror"

# ---- No fcitx5 on the bus.
first="$(timeout 1 "$HELPER" 50 | head -n 1)"
check "no fcitx5: reports -" '[ "$first" = "-" ]'
check "no fcitx5: never D-Bus-starts it (NO_AUTO_START)" '[ ! -e "$T/activated" ]'
# Proves the service file above really would activate, so the check above means something.
dbus-send --session --print-reply --dest=org.fcitx.Fcitx5 /controller org.fcitx.Fcitx.Controller1.CurrentInputMethod >/dev/null 2>&1
check "test setup: a normal call does activate the service file" 'wait_for 20 "[ -e \"$T/activated\" ]"'

PY="${PYTHON:-python3}"
if ! "$PY" -c 'from gi.repository import Gio' >/dev/null 2>&1; then
  skip "mock fcitx5 tests: PyGObject not available for $PY"
  finish
  exit
fi

has_name() {
  dbus-send --session --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus \
    org.freedesktop.DBus.NameHasOwner string:org.fcitx.Fcitx5 2>/dev/null | grep -q true
}
start_mock() {
  "$PY" -I "$HERE/mock_fcitx5.py" "$T/im" &
  MOCK=$!
  PIDS+=("$MOCK")
  wait_for 50 has_name
}

# ---- Changes are reported, once each.
echo keyboard-us >"$T/im"
start_mock || nok "mock fcitx5 starts"
"$HELPER" 30 >"$T/out" &
PIDS+=($!)
lines() { tr '\n' ' ' <"$T/out"; }
check "reports the current method" 'wait_for 20 "[ \"\$(lines)\" = \"keyboard-us \" ]"'
echo bamboo >"$T/im"
check "reports a change" 'wait_for 20 "[ \"\$(lines)\" = \"keyboard-us bamboo \" ]"'
: >"$T/im"
check "no focused input context reports -" 'wait_for 20 "[ \"\$(lines)\" = \"keyboard-us bamboo - \" ]"'
echo bamboo >"$T/im"
sleep 0.3
kill "$MOCK"; wait "$MOCK" 2>/dev/null
check "fcitx5 leaving the bus reports -" 'wait_for 20 "[ \"\$(lines)\" = \"keyboard-us bamboo - bamboo - \" ]"'
check "fcitx5 gone: still no auto-start of a second one" '! has_name'

# ---- Shared state-file mode: one active helper, others wait and take over.
echo bamboo >"$T/im"
start_mock || nok "mock fcitx5 restarts"
"$HELPER" 30 "$T/state" >"$T/a.out" &
A=$!; PIDS+=("$A")
check "state file: active helper announces itself" 'wait_for 20 "grep -qx active \"$T/a.out\""'
check "state file: one 32-byte record" '[ "$(stat -c %s "$T/state")" = 32 ] && [ "$(head -c 6 "$T/state")" = bamboo ]'
"$HELPER" 30 "$T/state" >"$T/b.out" &
B=$!; PIDS+=("$B")
sleep 0.5
check "state file: second helper waits as a standby" 'kill -0 "$B" && [ ! -s "$T/b.out" ]'
echo keyboard-us >"$T/im"
check "state file: record updated in place" 'wait_for 20 "[ \"\$(head -c 11 \"$T/state\")\" = keyboard-us ] && [ \"\$(stat -c %s \"$T/state\")\" = 32 ]"'
kill "$A"
check "state file: standby takes over when the active one dies" 'wait_for 20 "grep -qx active \"$T/b.out\""'

finish
