# Shared helpers for the shell tests. Source it, call check/skip, end with finish.
FAILED=0
PASSED=0

ok()   { PASSED=$((PASSED + 1)); echo "ok   - $1"; }
nok()  { FAILED=$((FAILED + 1)); echo "FAIL - $1"; }
skip() { echo "skip - $1"; }
check() { if eval "$2"; then ok "$1"; else nok "$1"; fi; }

# wait_for <tenths of a second> <condition>: true as soon as the condition holds.
wait_for() {
  local n="$1"; shift
  while [ "$n" -gt 0 ]; do
    eval "$@" && return 0
    sleep 0.1
    n=$((n - 1))
  done
  eval "$@"
}

finish() {
  echo "$(basename "$0"): passed $PASSED, failed $FAILED"
  [ "$FAILED" = 0 ]
}
