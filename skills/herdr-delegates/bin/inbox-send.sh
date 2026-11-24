#!/usr/bin/env bash
# inbox-send.sh RUN_DIR FROM KIND MESSAGE — optional sender for shells that
# can write under RUN_DIR (an agent's file-writing tool is the primary path).
# Writes a dotfile in RUN_DIR/inbox, then renames it into
# inbox/new/FROM--<UTC>-<pid>-<rand>.md, so inbox-watch.sh never sees a
# partial file. FROM: [a-z][a-z0-9_-]{0,31}; KIND: report|question|blocker|
# note; MESSAGE: at most 4,000 bytes. No Herdr calls; needs no HERDR_ENV.
# stdout: the new file's path. Exit: 0 sent, 1 write failure, 2 usage.
set -uo pipefail
usage() { echo "usage: inbox-send.sh RUN_DIR FROM KIND MESSAGE" >&2; exit 2; }
[ $# -eq 4 ] || usage
run=$1; from=$2; kind=$3; message=$4
[ -d "$run" ] || { echo "inbox-send: no run directory: $run" >&2; exit 2; }
[[ $from =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || { echo "inbox-send: FROM must match [a-z][a-z0-9_-]{0,31}: $from" >&2; exit 2; }
case $kind in report|question|blocker|note) ;; *) echo "inbox-send: KIND must be report, question, blocker or note: $kind" >&2; exit 2 ;; esac
[ -n "$message" ] || usage
bytes=$(printf '%s' "$message" | LC_ALL=C wc -c | tr -d ' ')
if [ "$bytes" -gt 4000 ]; then
  echo "inbox-send: message is $bytes bytes (limit 4000); write a file and send its path" >&2
  exit 2
fi
inbox=$run/inbox
mkdir -p "$inbox/new" || exit 1
tmp=$inbox/.send.$$.$RANDOM
target=$inbox/new/$from--$(date -u +%Y%m%dT%H%M%SZ)-$$-$RANDOM.md
if printf 'kind: %s\n%s\n' "$kind" "$message" >"$tmp" && mv "$tmp" "$target"; then
  printf '%s\n' "$target"
else
  rm -f "$tmp"; echo "inbox-send: could not write $target" >&2; exit 1
fi
