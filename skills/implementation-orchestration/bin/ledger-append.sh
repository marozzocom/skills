#!/usr/bin/env bash
# ledger-append.sh <ledger-file> <entry text...>
#
# Timestamped, append-only ledger write — a chronological entry costs one
# command instead of a read-modify-write of the whole file. Echoes the
# appended line back as confirmation. The orchestrator remains the ledger's
# only writer. The status matrix at the ledger head is rendered by
# status-set.sh and never hand-edited; other structural edits (rewriting a
# section) still go through a normal editor.
set -euo pipefail

ledger=${1:?usage: ledger-append.sh <ledger-file> <entry text...>}
shift
[ $# -ge 1 ] || { echo "usage: ledger-append.sh <ledger-file> <entry text...>" >&2; exit 2; }

lock=$(dirname "$ledger")/.status.lock
locked=0
cleanup() {
  if [ "$locked" = 1 ]; then rmdir "$lock"; fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
tries=0
until mkdir "$lock" 2>/dev/null; do
  tries=$((tries + 1))
  if [ "$tries" -ge 50 ]; then
    echo "ERROR: status lock unavailable after 5 seconds; if no writer is running, remove $lock" >&2
    exit 1
  fi
  sleep 0.1
done
locked=1
printf -- '- %s — %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >>"$ledger"
tail -n 1 "$ledger"
