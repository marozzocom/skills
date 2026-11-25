#!/usr/bin/env bash
# inbox-send.sh [OPTIONS] TARGET FROM KIND MESSAGE — optional sender for
# shells that can write under the target run (an agent's file-writing tool is
# the primary path).
# Writes a dotfile in RUN_DIR/inbox, then renames it into
# inbox/new/FROM--<UTC>-<pid>-<rand>.md, so inbox-watch.sh never sees a
# partial file. FROM: [a-z][a-z0-9_-]{0,31}; KIND: report|question|blocker|
# note; MESSAGE: at most 4,000 bytes (header lines are not counted). No Herdr
# calls; needs no HERDR_ENV.
# TARGET with a `/` is the RUN_DIR itself: without --from-run it only has to
# exist (same-run senders). Any other TARGET (run_id, prefix or
# <prefix>-overseer) and any --from-run send go through inbox-resolve.sh,
# which refuses an app-flavor run (exit 3) and, unless --allow-unwatched, a
# run without a live inbox watcher (exit 1).
# OPTIONS:
#   --from-run RUN_ID   the sender's own run ([A-Za-z0-9][A-Za-z0-9._-]*);
#                       writes `from-run: RUN_ID` after the kind line
#   --from-pane PANE    the sender's pane ([A-Za-z0-9:._-]+); writes
#                       `from-pane: PANE`; with --from-run it defaults to a
#                       valid HERDR_PANE_ID
#   --allow-unwatched, --runs-dir DIR   passed to inbox-resolve.sh
# stdout: the new file's path. Exit: 0 sent, 1 write failure or unresolved
# target, 2 usage, 3 app-flavor target.
set -uo pipefail
usage() { echo "usage: inbox-send.sh [--from-run RUN_ID] [--from-pane PANE] [--allow-unwatched] [--runs-dir DIR] TARGET FROM KIND MESSAGE" >&2; exit 2; }
from_run=''; from_pane=''; allow=0; runs_dir=''; has_run=0
while [ $# -gt 0 ]; do
  case $1 in
    --from-run|--from-pane|--runs-dir)
      [ $# -ge 2 ] || usage
      [ -n "$2" ] || usage
      case $1 in --from-run) from_run=$2; has_run=1 ;; --from-pane) from_pane=$2 ;; *) runs_dir=$2 ;; esac
      shift 2 ;;
    --allow-unwatched) allow=1; shift ;;
    --) shift; break ;;
    -*) usage ;;
    *) break ;;
  esac
done
[ $# -eq 4 ] || usage
run=$1; from=$2; kind=$3; message=$4
case $run in
  */*) resolve=$has_run ;;
  '') usage ;;
  *) resolve=1 ;;
esac
if [ "$resolve" = 0 ]; then [ -d "$run" ] || { echo "inbox-send: no run directory: $run" >&2; exit 2; }; fi
pane_re='^[A-Za-z0-9:._-]+$'
safe_run() { local LC_ALL=C; [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; }
safe_pane() { local LC_ALL=C; [[ $1 =~ $pane_re ]]; }
if [ "$has_run" = 1 ]; then
  safe_run "$from_run" ||
    { echo "inbox-send: --from-run must match [A-Za-z0-9][A-Za-z0-9._-]*: $from_run" >&2; exit 2; }
  if [ -z "$from_pane" ] && safe_pane "${HERDR_PANE_ID:-}"; then from_pane=$HERDR_PANE_ID; fi
fi
if [ -n "$from_pane" ] && ! safe_pane "$from_pane"; then
  echo "inbox-send: --from-pane must match [A-Za-z0-9:._-]+: $from_pane" >&2; exit 2
fi
[[ $from =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || { echo "inbox-send: FROM must match [a-z][a-z0-9_-]{0,31}: $from" >&2; exit 2; }
case $kind in report|question|blocker|note) ;; *) echo "inbox-send: KIND must be report, question, blocker or note: $kind" >&2; exit 2 ;; esac
[ -n "$message" ] || usage
bytes=$(printf '%s' "$message" | LC_ALL=C wc -c | tr -d ' ')
if [ "$bytes" -gt 4000 ]; then
  echo "inbox-send: message is $bytes bytes (limit 4000); write a file and send its path" >&2
  exit 2
fi
if [ "$resolve" = 1 ]; then
  set --
  [ "$allow" = 1 ] && set -- --allow-unwatched
  [ -n "$runs_dir" ] && set -- "$@" --runs-dir "$runs_dir"
  here=$(CDPATH='' cd -P -- "$(dirname "$0")" >/dev/null && pwd -P) || exit 1
  run=$("$here/inbox-resolve.sh" "$@" -- "$run") || exit $?
fi
header="kind: $kind"$'\n'
[ "$has_run" = 1 ] && header="${header}from-run: $from_run"$'\n'
[ -n "$from_pane" ] && header="${header}from-pane: $from_pane"$'\n'
inbox=$run/inbox
mkdir -p "$inbox/new" || exit 1
tmp=$inbox/.send.$$.$RANDOM
target=$inbox/new/$from--$(date -u +%Y%m%dT%H%M%SZ)-$$-$RANDOM.md
if printf '%s%s\n' "$header" "$message" >"$tmp" && mv "$tmp" "$target"; then
  printf '%s\n' "$target"
else
  rm -f "$tmp"; echo "inbox-send: could not write $target" >&2; exit 1
fi
