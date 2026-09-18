#!/usr/bin/env bash
# tests/run.sh — run every tests/test-*.sh under the system bash (3.2 on
# macOS) and report. Each test file is independent, uses mocks on PATH for
# `gh` and `herdr`, and throwaway git repos with a local bare "origin"; no
# test reaches a real remote, PR, or review thread.
set -u
here=$(cd "$(dirname "$0")" && pwd)
bash=${TEST_BASH:-/bin/bash}
[ -x "$bash" ] || bash=bash
fail=0; n=0
for t in "$here"/test-*.sh; do
  n=$((n + 1))
  if out=$("$bash" "$t" 2>&1); then
    echo "PASS $(basename "$t")"
  else
    fail=1
    echo "FAIL $(basename "$t")"
    printf '%s\n' "$out" | sed 's/^/  | /'
  fi
done
echo "$n test file(s), $([ "$fail" = 0 ] && echo all passed || echo FAILURES)"
exit "$fail"
