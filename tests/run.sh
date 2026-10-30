#!/usr/bin/env bash
# Runs every test. Needs node (18+); the shell tests need cc and dbus, and the mock
# fcitx5 needs PyGObject. Missing tools make those tests skip, not fail.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

status=0
if command -v node >/dev/null 2>&1; then
  node --test tests/*.test.mjs || status=1
else
  echo "skip - JavaScript tests: node not installed"
fi
for t in tests/*.test.sh; do
  echo "== $t"
  bash "$t" || status=1
done
exit "$status"
