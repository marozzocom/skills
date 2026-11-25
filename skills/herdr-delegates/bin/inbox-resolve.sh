#!/usr/bin/env bash
# inbox-resolve.sh [--allow-unwatched] [--runs-dir DIR] TARGET
# Resolves another run's inbox for a cross-run message; prints its absolute
# RUN_DIR on stdout. No Herdr calls; needs no HERDR_ENV. Bash 3.2, BSD or GNU.
# TARGET with a `/` is a path to the run directory. Without one it is never a
# path (a bare `inbox` or `docs` is not looked up in the working directory):
# it must match [A-Za-z0-9][A-Za-z0-9._-]* and is, in order, a run_id
# (RUNS/<TARGET>/status.json) or a run prefix, optionally with `-overseer`
# (every RUNS/*/status.json whose .prefix matches). Among prefix matches,
# exactly one with a live watcher wins; two or more live is ambiguous (address
# by run_id); with none live, --allow-unwatched takes the single non-app match
# that has an open overseer row.
# RUNS: --runs-dir, else ORCHESTRATION_RUNS_DIR, else
# ${XDG_STATE_HOME:-$HOME/.local/state}/implementation-orchestration/runs.
# Live watcher: RUN_DIR/inbox/.watch (written by inbox-watch.sh every poll)
# has a numeric epoch no older than max(30, ceil(3 x interval)) seconds (nor
# more than 10 s ahead), a missing or nonnegative numeric interval, and a
# pid that still exists, or "rearm": true (a --once watcher that delivered an
# event and is about to be re-armed: its pid has exited). A target without one is refused unless
# --allow-unwatched (the message then waits in new/ for the next watcher).
# A run whose status.json .herdr.flavor is "app" has no inbox watcher and is
# always refused (exit 3), and so is a closed run (overseer rows, none open;
# exit 1), even with --allow-unwatched or a lingering heartbeat.
# INBOX_NOW=UTC-ISO fixes the clock for tests.
# Exit: 0 resolved, 1 not found / unwatched / ambiguous, 2 usage, 3 app flavor.
set -uo pipefail
usage() { echo "usage: inbox-resolve.sh [--allow-unwatched] [--runs-dir DIR] TARGET" >&2; exit 2; }
allow=0; runs_opt=''
while [ $# -gt 0 ]; do
  case $1 in
    --allow-unwatched) allow=1; shift ;;
    --runs-dir) [ $# -ge 2 ] && [ -n "$2" ] || usage; runs_opt=$2; shift 2 ;;
    --) shift; break ;;
    -*) usage ;;
    *) break ;;
  esac
done
[ $# -eq 1 ] && [ -n "$1" ] || usage
target=$1
runs=${runs_opt:-${ORCHESTRATION_RUNS_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/implementation-orchestration/runs}}
fixed=''
if [ -n "${INBOX_NOW:-}" ]; then
  fixed=$(jq -n --arg s "$INBOX_NOW" '$s|fromdateiso8601' 2>/dev/null) || usage
fi
now() { if [ -n "$fixed" ]; then echo "$fixed"; else date -u +%s; fi; }
safe_id() { local LC_ALL=C; [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; }
watch_live() { # RUN_DIR: 0 when its watcher heartbeat is fresh and its pid exists (or rearm)
  local f=$1/inbox/.watch pid
  [ -f "$f" ] || return 1
  pid=$(jq -r --argjson now "$(now)" '
    if (.pid | type) == "number" and .pid >= 1 and (.pid | floor) == .pid and (.epoch | type) == "number"
      and (.interval == null or ((.interval | type) == "number" and .interval >= 0))
      and ($now - .epoch) >= -10
      and ($now - .epoch) <= ([30, ((.interval // 0) * 3 | ceil)] | max)
    then (if .rearm == true then "rearm" else (.pid | floor) end) else empty end' "$f" 2>/dev/null) || return 1
  [ -n "$pid" ] || return 1
  [ "$pid" = rearm ] || kill -0 "$pid" 2>/dev/null || ps -p "$pid" >/dev/null 2>&1
}
flavor() { jq -r '.herdr.flavor // ""' "$1/status.json" 2>/dev/null; }
is_closed() { # RUN_DIR: has overseer rows and none open
  [ -f "$1/status.json" ] && jq -e 'any(.agents[]?; .role == "overseer") and
    (any(.agents[]?; .role == "overseer" and .state == "open") | not)' "$1/status.json" >/dev/null 2>&1
}
check_run() { # DIR LABEL: app refusal, then the watcher requirement; prints DIR
  if [ -f "$1/status.json" ] && [ "$(flavor "$1")" = app ]; then
    echo "inbox-resolve: target run $2 uses app flavor; no inbox watcher" >&2; exit 3
  fi
  if is_closed "$1"; then echo "inbox-resolve: target run $2 is closed" >&2; exit 1; fi
  if [ "$allow" = 0 ] && ! watch_live "$1"; then
    echo "inbox-resolve: $3 has no live inbox watcher (pass --allow-unwatched to queue anyway)" >&2; exit 1
  fi
  printf '%s\n' "$1"; exit 0
}

case $target in
  */*)
    [ -d "$target" ] || { echo "inbox-resolve: no run directory: $target" >&2; exit 1; }
    dir=$(CDPATH='' cd -P -- "$target" >/dev/null && pwd -P) || exit 1
    check_run "$dir" "${dir##*/}" "target $dir" ;;
esac
safe_id "$target" || { echo "inbox-resolve: TARGET must be a path with / or match [A-Za-z0-9][A-Za-z0-9._-]*: $target" >&2; exit 2; }
if [ -d "$runs" ]; then runs=$(CDPATH='' cd -P -- "$runs" >/dev/null && pwd -P) || exit 1; fi
if [ -f "$runs/$target/status.json" ]; then check_run "$runs/$target" "$target" "run $target"; fi

p=${target%-overseer}
[ -n "$p" ] || { echo "inbox-resolve: empty prefix in $target" >&2; exit 2; }
live=''; unwatched=''; open=''; apps=''; closed=''
for s in "$runs"/*/status.json; do
  [ -f "$s" ] || continue
  d=${s%/status.json}; id=${d##*/}
  safe_id "$id" || continue
  row=$(jq -r --arg p "$p" '. as $s | select(.prefix == $p) |
    "\(.herdr.flavor // "")|\(any($s.agents[]?; .state == "open" and .role == "overseer"))|\(any($s.agents[]?; .role == "overseer"))"' "$s" 2>/dev/null) || continue
  [ -n "$row" ] || continue
  rest=${row#*|}
  if [ "${row%%|*}" = app ]; then apps="$apps $id"
  elif [ "$rest" = 'false|true' ]; then closed="$closed $id"
  elif watch_live "$d"; then live="$live $id"
  else
    unwatched="$unwatched $id"
    [ "${rest%%|*}" = true ] && open="$open $id"
  fi
done
# shellcheck disable=SC2086 # ids are safe_id words: split on spaces, no globs
count() { set -- $1; echo $#; }
n_live=$(count "$live")
if [ "$n_live" = 1 ]; then printf '%s\n' "$runs/${live# }"; exit 0; fi
if [ "$n_live" -gt 1 ]; then
  echo "inbox-resolve: ambiguous target $target: multiple live runs match:$live — address by run_id" >&2; exit 1
fi
if [ "$allow" = 1 ] && [ "$(count "$open")" = 1 ]; then printf '%s\n' "$runs/${open# }"; exit 0; fi
if [ -n "$apps" ] && [ -z "$unwatched" ] && [ -z "$closed" ]; then
  echo "inbox-resolve: target run${apps} uses app flavor; no inbox watcher" >&2; exit 3
fi
if [ -n "$unwatched" ]; then
  echo "inbox-resolve: no live run matching $target ($(count "$unwatched") unwatched match(es):$unwatched; open overseer:${open:- none}; address by run_id with --allow-unwatched to queue anyway)" >&2
elif [ -n "$closed" ]; then
  echo "inbox-resolve: no live run matching $target (closed:$closed)" >&2
else
  echo "inbox-resolve: no live run matching $target" >&2
fi
exit 1
