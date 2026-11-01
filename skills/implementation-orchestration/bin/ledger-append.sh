#!/usr/bin/env bash
# ledger-append.sh <ledger-file> <entry text...>
#
# Timestamped, append-only ledger write — a chronological entry costs one
# command instead of a read-modify-write of the whole file. Echoes the
# appended line back as confirmation. The orchestrator remains the ledger's
# only writer. The status matrix at the ledger head is rendered by
# status-set.sh and never hand-edited; other structural edits (rewriting a
# section) still go through a normal editor.
# STATUS_LOCK_WAIT=seconds overrides the 5 s lock wait (nonnegative decimal).
set -euo pipefail

ledger=${1:?usage: ledger-append.sh <ledger-file> <entry text...>}
shift
[ $# -ge 1 ] || { echo "usage: ledger-append.sh <ledger-file> <entry text...>" >&2; exit 2; }

run=$(dirname "$ledger")
[ -d "$run" ] || { echo "ERROR: no such directory: $run" >&2; exit 1; }
lock_wait=${STATUS_LOCK_WAIT:-5}
[[ $lock_wait =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo "usage: STATUS_LOCK_WAIT must be nonnegative seconds" >&2; exit 2; }
lock_tries=$(jq -nr --arg s "$lock_wait" '$s|tonumber|. * 10|ceil')
lock=$run/.status.lock
locked=0
cleanup() {
  if [ "$locked" = 1 ]; then rmdir "$lock" 2>/dev/null || true; fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
tries=0
until mkdir "$lock" 2>/dev/null; do
  tries=$((tries + 1))
  if [ "$tries" -ge "$lock_tries" ]; then
    echo "ERROR: status lock held for $lock_wait s — another writer may be running; if none is, remove $lock" >&2
    exit 1
  fi
  sleep 0.1
done
locked=1
if [ -L "$ledger" ] || { [ -e "$ledger" ] && [ ! -f "$ledger" ]; }; then
  echo "ERROR: ledger is not a regular file" >&2
  exit 1
fi
rm -f "$run"/.status-set.tmp.?????? "$run"/.ledger.tmp.?????? "$run"/.ledger-seed.tmp.?????? 2>/dev/null || true
printf -- '- %s — %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >>"$ledger"
tail -n 1 "$ledger"
