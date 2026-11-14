#!/usr/bin/env bash
# rotate-cockpit.sh RUN_DIR start [--carry NAME]... [--cwd DIR] [--wait SECONDS]
#                           [-- NATIVE AGENT ARGS...]
# rotate-cockpit.sh RUN_DIR adopt | abort | status
# Hand a run's overseer role to a fresh session with no step left to the
# human. Herdr TUI only; any other flavor, or no Herdr session, exits 3 (the
# manual path is in implementation-orchestration SKILL.md §Context discipline).
#
# start — run by the overseer; when it returns, the handover is either
#   complete (exit 0: this session is retired and its pane closes) or
#   withdrawn (any other exit: this session is still the overseer and the
#   successor is gone). Refuses unless the caller's pane is the recorded
#   overseer pane and holds <prefix>-overseer, RUN_DIR/continuation.md is
#   non-empty and newer than ROTATE_CONTINUATION_MAX_MIN minutes (30), no
#   handover is in progress, and every other agent row with state=open is
#   named with --carry and is running: finished agents are closed first, and
#   an agent crosses a handover only by decision. Then: a
#   <prefix>·cockpit-next tab, a successor <prefix>-overseer-next of the
#   caller's kind in the caller's pane cwd (--cwd overrides) with the args
#   after --, its agent row, and one prompt telling it to read the
#   continuation and run adopt. --wait (100) is the budget in seconds for all
#   of it; the offer expires with it, so a successor that comes late cannot
#   take the run. The prompt is re-sent while the successor still reads idle
#   after ROTATE_RESEND_AFTER seconds (15), twice at most.
# adopt — run by the successor, in its own pane only. Under a lock: renames
#   the old agent to <prefix>-overseer-retired and itself to
#   <prefix>-overseer. Herdr has no atomic swap, so the name is unheld for
#   the milliseconds between the two renames; a failure or signal there
#   gives the name back, and after a kill the old session's start (when its
#   wait ends), an abort, or a second adopt restores a holder. Then waits up to
#   ROTATE_RETIRE_WAIT seconds (60) for the old session to stop working,
#   closes the old board and the old cockpit pane, runs run-cockpit.sh (tab
#   label, board, overseer row, metadata), closes the successor row, appends
#   a ledger entry, and prints each carried agent with its live status. Every
#   step after the renames is repeatable: run adopt again after an
#   interruption. On a withdrawn or expired offer it closes its own pane.
# abort — run by the overseer before adoption: withdraws the offer (a start
#   still running notices at its next step and stops) and closes the
#   successor's pane and row. Exits 1 while that pane will not close; a
#   successor that outlives a withdrawn offer closes itself when it tries to
#   adopt. Repeatable.
# A withdrawal closes only the pane its own offer recorded, never a tab found
# by label.
# status — one line: state=… from=… to=….
#
# State is RUN_DIR/rotation.json, written only here; state is one of
# preparing, started, adopted, closed, aborted, expired. Transitions between
# sessions are serialized by the lock directory RUN_DIR/.rotation.lock, held
# for milliseconds, waited on for ROTATE_LOCK_TRIES (100) tenths of a second,
# and taken over at once from an owner process that is gone. Taking,
# taking over and releasing all happen inside a second mkdir mutex
# (.rotation.lock.guard) that is never taken over; if a kill ever leaves it
# behind, the commands fail closed and name it. ROTATE_POLL (2) is the poll interval
# in seconds; STATUS_NOW overrides the timestamp clock as
# in status-set.sh and ROTATE_NOW_EPOCH the expiry clock (tests).
# Exit: 0 done, 1 refusal or runtime failure, 2 usage, 3 unsupported flavor,
# 4 start: the successor did not adopt in time and the offer was withdrawn,
# 5 start: undecided — a live successor was in the middle of taking the run
# when start had to stop; nothing was changed, and status tells the outcome.
set -euo pipefail
usage() {
  echo "usage: rotate-cockpit.sh RUN_DIR start [--carry NAME]... [--cwd DIR] [--wait SECONDS] [-- NATIVE AGENT ARGS...]" >&2
  echo "       rotate-cockpit.sh RUN_DIR adopt|abort|status" >&2
  exit 2
}
fail() { echo "ERROR: $*" >&2; exit 1; }
[ $# -ge 2 ] || usage
run=$1; command=$2; shift 2
case $command in start|adopt|abort|status) ;; *) usage ;; esac
here=$(cd "$(dirname "$0")" && pwd)
backend=$here/herdr-backend.sh
io=$here/../../implementation-orchestration/bin
setter=$io/status-set.sh
[ -x "$setter" ] || fail "status-set.sh unavailable: $setter"
run=$(cd "$run" 2>/dev/null && pwd) || fail "run directory unavailable"
status=$run/status.json; state_file=$run/rotation.json; lock=$run/.rotation.lock
[ -f "$status" ] || fail "no status.json in $run"
manual='hand over by the manual path (implementation-orchestration SKILL.md §Context discipline)'
if [ "${HERDR_ENV:-}" != 1 ] && [ -z "${HC_TERMINAL_ID:-}" ]; then
  echo "rotate-cockpit: not inside a Herdr session — $manual" >&2; exit 3
fi
export HERDR_BACKEND_RUN_DIR=$run
flavor=$("$backend" flavor "$run") || exit 1
if [ "$flavor" != tui ]; then
  echo "rotate-cockpit: not automated in the $flavor flavor — $manual" >&2; exit 3
fi
prefix=$(jq -er '.prefix | strings | select(length > 0)' "$status") || fail "status.json prefix missing"
overseer=$prefix-overseer; next=$overseer-next
poll=${ROTATE_POLL:-2}
now() { echo "${STATUS_NOW:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"; }
epoch() { echo "${ROTATE_NOW_EPOCH:-$(date +%s)}"; }
rot() { if [ -f "$state_file" ]; then jq -r "$1 // \"\"" "$state_file"; fi; }
write_state() { # jq args; the filter's input is the current state, or null
  local tmp=$state_file.tmp.$$
  if [ -f "$state_file" ]; then jq "$@" "$state_file" >"$tmp"; else jq -n "$@" >"$tmp"; fi
  mv "$tmp" "$state_file"
}
held=0; guard=$lock.guard
# Every change to the lock — taking it, taking it over from a dead owner, releasing it —
# happens inside the guard, a plain mkdir mutex held for a few file operations and never
# taken over. So the look at the owner and the takeover cannot be split by another process.
guard_in() { # TRIES
  local n=0
  until mkdir "$guard" 2>/dev/null; do
    n=$((n + 1)); [ "$n" -lt "$1" ] || return 1
    sleep 0.05
  done
}
guard_out() { rmdir "$guard" 2>/dev/null || true; }
acquire() { # [soft [TRIES]] — exit 1 when the lock stays busy; soft returns 1 instead
  local tries=0 max=${2:-${ROTATE_LOCK_TRIES:-100}} owner
  while :; do
    if guard_in $((max * 2)); then
      if mkdir "$lock" 2>/dev/null; then echo $$ >"$lock/pid"; guard_out; held=1; return 0; fi
      owner=$(cat "$lock/pid" 2>/dev/null) || owner=''
      # An owner process that is gone died holding the lock (a lock without an owner: after a minute).
      if { [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; } ||
         { [ -z "$owner" ] && [ -n "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ]; }; then
        echo $$ >"$lock/pid"; guard_out; held=1; return 0
      fi
      guard_out
    fi
    tries=$((tries + 1))
    if [ "$tries" -ge "$max" ]; then
      [ "${1:-}" = soft ] && return 1
      fail "handover lock busy: $lock (if no rotate-cockpit.sh command is running, remove $guard)"
    fi
    sleep 0.1
  done
}
release() { # only a lock this process still owns
  if [ "$held" = 1 ]; then
    held=0
    if guard_in 200; then
      if [ "$(cat "$lock/pid" 2>/dev/null)" = "$$" ]; then rm -f "$lock/pid"; rmdir "$lock" 2>/dev/null || true; fi
      guard_out
    fi
  fi
}
trap release EXIT
note() { # one ledger entry, when the ledger helper is installed
  [ ! -x "$io/ledger-append.sh" ] || "$io/ledger-append.sh" "$run/ledger.md" "$1" >/dev/null 2>&1 || true
}
agent_field() { # PANE FIELD — from $agents
  jq -r --arg p "$1" --arg f "$2" '[.[] | select(.pane == $p)][0][$f] // ""' <<<"$agents"
}
pane_live() { jq -e --arg p "$1" 'any(.[]; .id == $p)' <<<"$panes" >/dev/null; }
close_next_row() { # PANE NOTE — only the row of the pane being cleaned
  if [ -n "$1" ] && jq -e --arg n "$next" --arg p "$1" 'any(.agents[]; .name == $n and .state == "open" and .pane == $p)' "$status" >/dev/null; then
    "$setter" "$run" agent "$next" state=closed "note=$2" >/dev/null
  fi
}
close_successor() { # PANE NOTE — close an offer's pane and row; fails while the pane is still there
  if [ -n "$1" ]; then
    panes=$("$backend" panes) || return 1
    if pane_live "$1" && [ "$1" != "$self_pane" ]; then
      "$backend" close "$1" >/dev/null 2>&1 || true
      panes=$("$backend" panes) || return 1
    fi
    ! pane_live "$1" || return 1
  fi
  close_next_row "$1" "$2"
}
keep_name() { # the caller is the overseer again: make sure it holds the name
  agents=$("$backend" agents) || return 1
  [ "$(agent_field "$self_pane" name)" = "$overseer" ] || "$backend" rename-self "$overseer"
}
if [ "$command" = status ]; then
  [ $# -eq 0 ] || usage
  if [ -f "$state_file" ]; then
    echo "state=$(rot .state) from=$(rot .from_pane) to=$(rot .to_pane)"
  else echo "state=none"; fi
  exit 0
fi
self_pane=$("$backend" self | jq -r '.pane // ""')
[ -n "$self_pane" ] || fail "caller pane unknown: run from the session's own shell"

case $command in
start)
  wait_s=100; cwd=''; carry=(); agent_args=()
  while [ $# -gt 0 ]; do
    case $1 in
      --) shift; agent_args=("$@"); break ;;
      --carry) [ $# -ge 2 ] && [ -n "$2" ] || usage; carry+=("$2"); shift 2 ;;
      --cwd) [ $# -ge 2 ] && [ -n "$2" ] || usage; cwd=$2; shift 2 ;;
      --wait) [ $# -ge 2 ] || usage; case $2 in ''|*[!0-9]*) usage ;; esac; wait_s=$2; shift 2 ;;
      *) usage ;;
    esac
  done
  deadline=$((SECONDS + wait_s)); expires=$(($(epoch) + wait_s))
  recorded=$(jq -r '.herdr.overseer_pane // ""' "$status")
  [ -n "$recorded" ] || fail "no cockpit recorded: run run-cockpit.sh first"
  [ "$recorded" = "$self_pane" ] ||
    fail "only the run's overseer (pane $recorded) starts a handover; caller is pane $self_pane"
  agents=$("$backend" agents) || fail "agent list failed"
  panes=$("$backend" panes) || fail "pane list failed"
  [ "$(agent_field "$self_pane" name)" = "$overseer" ] ||
    fail "caller does not hold the name $overseer"
  continuation=$run/continuation.md
  [ -s "$continuation" ] || fail "write $continuation first: the successor resumes from it"
  max_min=${ROTATE_CONTINUATION_MAX_MIN:-30}
  [ -n "$(find "$continuation" -mmin "-$max_min" 2>/dev/null)" ] ||
    fail "$continuation is older than $max_min minutes: rewrite it with the current state"
  # Every open agent is either closed first or carried by name, and a carried agent is running.
  carried_json=$(printf '%s\n' ${carry[@]+"${carry[@]}"} | jq -Rnc '[inputs | select(length > 0)]')
  problems=$(jq -r --arg o "$overseer" --arg n "$next" --argjson carry "$carried_json" --argjson live "$agents" '
    [.agents[] | select(.state == "open" and .name != $o and .name != $n) | .name] as $open |
    ([$open[] | select(. as $a | $carry | index($a) | not)]
      | map("open and not carried: " + . + " (close its pane and row, or pass --carry " + . + ")")) +
    ([$carry[] | select(. as $a | $open | index($a) | not)]
      | map("carried but has no open row: " + .)) +
    ([$carry[] | select(. as $a | ($open | index($a)) and ([$live[] | select(.name == $a)] | length == 0))]
      | map("carried but not running: " + . + " (close its row)")) | .[]' "$status")
  [ -z "$problems" ] || fail "the run is not ready to hand over:"$'\n'"$problems"
  kind=$(agent_field "$self_pane" kind)
  [ -n "$kind" ] || fail "caller's agent kind unknown"
  [ -n "$cwd" ] || cwd=$(jq -r --arg p "$self_pane" '[.[] | select(.id == $p)][0].cwd // ""' <<<"$panes")
  [ -n "$cwd" ] || cwd=$PWD
  [ -d "$cwd" ] || fail "successor cwd is not a directory: $cwd"
  if [ ${#agent_args[@]} -eq 0 ]; then
    echo "warning: no native agent args — the successor starts on '$kind' config defaults, not an explicit model pin (see environment.md)" >&2
  fi
  attempt=$$-$RANDOM; settled=0; undecided=0; to_pane=''; to_tab=''
  acquire
  case $(rot .state) in
    preparing|started)
      expires_at=$(rot .expires_at)
      [ "$(epoch)" -ge "${expires_at:-0}" ] ||
        fail "a handover is already in progress (successor pane $(rot .to_pane)): wait for it, or run 'rotate-cockpit.sh RUN_DIR abort'" ;;
    adopted) fail "the successor in pane $(rot .to_pane) holds the run; this session is retired" ;;
  esac
  case $(rot .state) in
    preparing|started|aborted|expired)
      # The record of an earlier offer is replaced only once its successor is gone.
      stale=$(rot .to_pane)
      close_successor "$stale" "earlier handover offer withdrawn" ||
        fail "the pane $stale of an earlier offer did not close: close it ('herdr-backend.sh close $stale') and start again" ;;
  esac
  write_state --arg id "$attempt" --arg from "$self_pane" --arg from_tab "$(jq -r '.herdr.cockpit_tab // ""' "$status")" \
    --arg board "$(jq -r '.herdr.board_pane // ""' "$status")" --argjson carried "$carried_json" \
    --arg at "$(now)" --argjson expires "$expires" \
    '{id:$id, state:"preparing", from_pane:$from, from_tab:$from_tab, from_board:$board, to_pane:"", to_tab:"", carried:$carried, started_at:$at, expires_at:$expires}'
  release
  succeeded() {
    settled=1
    echo "handover complete: $overseer is now pane $(rot .to_pane). End your turn now with one line to the human and do nothing further in this session, whatever arrives; this pane closes within a minute."
    exit 0
  }
  withdraw_work() { # REASON — take the offer back, unless the successor adopted meanwhile
    settled=1
    # A lock that stays busy has a live owner: the successor is mid-adoption, and only it can
    # say how that ends. Nothing is withdrawn or closed under it.
    if ! acquire soft "${ROTATE_WITHDRAW_LOCK_TRIES:-600}"; then
      undecided=1
      echo "handover undecided: the successor in pane ${to_pane:-?} is in the middle of taking the run. Do not act as $overseer yet. Run 'rotate-cockpit.sh RUN_DIR status' until it reads closed (you are retired: end your turn); if it stays started, run 'rotate-cockpit.sh RUN_DIR abort'." >&2
      return 0
    fi
    if [ "$(rot .id)" = "$attempt" ]; then
      case $(rot .state) in
        adopted|closed) release; succeeded ;;
        preparing|started) write_state --arg at "$(now)" '.state = "aborted" | .aborted_at = $at' ;;
      esac
    fi
    release
    left=''
    close_successor "$to_pane" "handover withdrawn: $1" || left=$to_pane
    keep_name || echo "ERROR: could not confirm this session holds the name $overseer: run 'rotate-cockpit.sh RUN_DIR abort'" >&2
    note "HANDOVER withdrawn ($1); pane $self_pane remains $overseer."
    if [ -z "$left" ]; then
      echo "handover withdrawn: $1. This session is still $overseer and the successor is closed. Carry on, and start a handover again at the next quiet point." >&2
    else
      echo "handover withdrawn: $1. This session is still $overseer and the successor can no longer adopt, but its pane $left did not close: close it ('herdr-backend.sh close $left') before carrying on." >&2
    fi
  }
  withdraw() { withdraw_work "$1"; [ "$undecided" = 0 ] || exit 5; exit "$2"; } # REASON EXIT
  # From here on every exit that is not a completed handover withdraws the offer.
  # shellcheck disable=SC2329 # invoked by the EXIT trap
  on_exit() {
    rc=$?; set +e; trap - EXIT INT TERM HUP
    release # a failure inside a locked step must not block its own recovery
    if [ "$settled" = 0 ]; then withdraw_work "start failed or was interrupted"; [ "$rc" != 0 ] || rc=1; fi
    [ "$undecided" = 0 ] || rc=5
    release; exit "$rc"
  }
  trap on_exit EXIT; trap 'exit 1' INT TERM HUP
  advance() { # jq args — write this attempt's next step, unless the offer was aborted meanwhile
    acquire
    if [ "$(rot .id)" != "$attempt" ]; then release; withdraw "another handover replaced this one" 1; fi
    case $(rot .state) in
      preparing|started) write_state "$@"; release ;;
      adopted|closed) release ;;
      *) release; withdraw "the offer was aborted" 1 ;;
    esac
  }
  created=$("$here/run-tab.sh" "$run" cockpit-next "$cwd") || withdraw "could not open the successor's tab" 1
  to_tab=${created%% pane=*}; to_tab=${to_tab#tab=}; to_pane=${created##*pane=}
  if [ -z "$to_tab" ] || [ -z "$to_pane" ] || [ "$to_pane" = "$created" ]; then
    to_pane=''; withdraw "run-tab.sh returned no tab and pane" 1
  fi
  advance --arg to "$to_pane" --arg to_tab "$to_tab" '.to_pane = $to | .to_tab = $to_tab'
  start_timeout=60; [ "$wait_s" -ge 60 ] || start_timeout=$wait_s; [ "$start_timeout" -gt 0 ] || start_timeout=1
  started=0
  for attempt_no in 1 2 3 4 5; do
    # A freshly created pane reads busy until its shell is up; the start is retried.
    if "$backend" start "$next" "$kind" "$cwd" --pane "$to_pane" --timeout "$start_timeout" -- ${agent_args[@]+"${agent_args[@]}"} >/dev/null; then
      started=1; break
    fi
    [ "$attempt_no" != 5 ] && [ "$SECONDS" -lt "$deadline" ] || break
    sleep 3
  done
  [ "$started" = 1 ] || withdraw "the successor did not start in pane $to_pane" 1
  "$setter" "$run" agent "$next" role=overseer transport=direct "pane=$to_pane" "tab=$to_tab" state=open \
    "note=successor; takes the overseer name at adoption" >/dev/null
  advance '.state = "started"'
  printf -v adopt_cmd '%q %q adopt' "$here/rotate-cockpit.sh" "$run"
  prompt="You are taking over as the orchestrator of run $(jq -r '.run_id // ""' "$status") from the session in pane $self_pane, whose context grew too large. This is a handover, not a task brief, and you are not a worker: from now on you hold the run's design authority, review, verification and landing. Do these three things in order. 1. Read $continuation in full. 2. Run this command: $adopt_cmd  (it gives you the name $overseer and closes the old session; if it says the offer was withdrawn, stop). 3. Load the implementation-orchestration skill, tell the human in two or three lines that you have taken over and what happens next, and resume the run from the continuation file."
  "$backend" prompt "$next" "$prompt" >/dev/null || withdraw "could not prompt the successor" 1
  note "HANDOVER started: successor in pane $to_pane (tab $to_tab), old cockpit pane $self_pane; carried agents: $(jq -r 'if length == 0 then "none" else join(", ") end' <<<"$carried_json")."
  resend_after=${ROTATE_RESEND_AFTER:-15}; next_resend=$((SECONDS + resend_after)); resends=0
  while :; do
    case $(rot .state) in
      adopted|closed) succeeded ;;
      aborted|expired) withdraw "the offer was aborted" 1 ;;
    esac
    [ "$SECONDS" -lt "$deadline" ] || break
    if [ "$resends" -lt 2 ] && [ "$SECONDS" -ge "$next_resend" ]; then
      resends=$((resends + 1)); next_resend=$((SECONDS + 2 * resend_after))
      # A first prompt after a start is sometimes dropped (herdr-delegates §Starting an agent).
      agents=$("$backend" agents) || agents='[]'
      if [ "$(agent_field "$to_pane" status)" = idle ]; then
        "$backend" prompt "$next" "$prompt" >/dev/null || true
      fi
    fi
    sleep "$poll"
  done
  withdraw "the successor did not adopt within ${wait_s}s" 4 ;;

adopt)
  [ $# -eq 0 ] || usage
  to_pane=$(rot .to_pane); from_pane=$(rot .from_pane)
  from_tab=$(rot .from_tab); from_board=$(rot .from_board); to_tab=$(rot .to_tab)
  [ -n "$(rot .state)" ] || fail "no handover was started for this run"
  [ "$to_pane" = "$self_pane" ] ||
    fail "only the successor in pane $to_pane adopts; caller is pane $self_pane"
  step_down() { # the offer is gone: this session never became the overseer
    close_next_row "$self_pane" "handover offer $1"
    echo "The handover offer was $1: the old session remains $overseer. Stop here; this pane closes now." >&2
    "$backend" close "$self_pane" >/dev/null 2>&1 || true
    exit 1
  }
  agents=$("$backend" agents) || fail "agent list failed"
  acquire
  case $(rot .state) in
    closed) release; echo "already adopted: $overseer is pane $self_pane"; exit 0 ;;
    adopted) release ;;
    aborted|expired) state=$(rot .state); release; step_down "$state" ;;
    started)
      expires_at=$(rot .expires_at)
      if [ "$(epoch)" -ge "${expires_at:-0}" ]; then
        write_state --arg at "$(now)" '.state = "expired" | .expired_at = $at'
        release; step_down expired
      fi
      # Never leave the name unheld: a failure or signal between the two renames gives it back.
      give_back() { # by what the names are now, not by how far this got
        agents=$("$backend" agents) || agents='[]'
        [ "$(agent_field "$self_pane" name)" != "$overseer" ] || return 0
        [ "$(agent_field "$from_pane" name)" != "$overseer" ] || return 0
        "$backend" rename "$from_pane" "$overseer" 2>/dev/null ||
          { echo "ERROR: nobody holds the name $overseer now: run adopt again, or 'rotate-cockpit.sh RUN_DIR abort' from the old session" >&2; return 1; }
      }
      trap 'give_back; exit 1' INT TERM HUP
      old_name=$(agent_field "$from_pane" name)
      if [ "$old_name" = "$overseer" ]; then
        retired=$overseer-retired
        "$backend" rename "$from_pane" "$retired" 2>/dev/null || {
          retired=$retired-$(date +%H%M%S)
          "$backend" rename "$from_pane" "$retired" || fail "could not retire the old overseer's name"
        }
      fi
      if [ "$(agent_field "$self_pane" name)" != "$overseer" ] && ! "$backend" rename-self "$overseer"; then
        give_back || exit 1
        fail "could not take the name $overseer; the old session keeps it"
      fi
      write_state --arg at "$(now)" '.state = "adopted" | .adopted_at = $at'
      release; trap - INT TERM HUP ;;
    *) fail "the handover is $(rot .state); nothing to adopt" ;;
  esac
  # The run is this session's from here; everything below is repeatable.
  trap 'rc=$?; release; [ "$rc" = 0 ] || echo "adopt did not finish (exit $rc): run it again" >&2' EXIT
  # The old session ends its turn once it sees the adoption; give it time, then close it regardless.
  retire_wait=${ROTATE_RETIRE_WAIT:-60}; deadline=$((SECONDS + retire_wait)); old_state=stopped
  while :; do
    agents=$("$backend" agents) || break
    [ "$(agent_field "$from_pane" status)" = working ] || break
    if [ "$SECONDS" -ge "$deadline" ]; then old_state='still working'; break; fi
    sleep "$poll"
  done
  panes=$("$backend" panes) || fail "pane list failed"
  refocus=false
  if [ -n "$from_tab" ]; then refocus=$("$backend" tab-focused "$from_tab" 2>/dev/null) || refocus=false; fi
  if [ -n "$from_board" ] && [ "$from_board" != "$self_pane" ] &&
     jq -e --arg p "$from_board" --arg t "$from_tab" 'any(.[]; .id == $p and .tab == $t)' <<<"$panes" >/dev/null; then
    "$backend" close "$from_board" >/dev/null 2>&1 || true
  fi
  if [ "$from_pane" != "$self_pane" ] && pane_live "$from_pane"; then
    "$backend" close "$from_pane" >/dev/null 2>&1 || true
  fi
  panes=$("$backend" panes) || fail "pane list failed"
  ! pane_live "$from_pane" || fail "the old cockpit pane $from_pane did not close; run adopt again"
  # A tab that outlives its cockpit (it held an agent pane) gives up the cockpit label.
  tabs=$("$backend" tabs) || fail "tab list failed"
  if [ -n "$from_tab" ] && jq -e --arg t "$from_tab" --arg l "${prefix}·cockpit" 'any(.[]; .id == $t and .label == $l)' <<<"$tabs" >/dev/null; then
    "$backend" rename-tab "$from_tab" "${prefix}·cockpit-was-${from_pane##*:}" || fail "could not rename the old cockpit tab $from_tab; run adopt again"
  fi
  "$here/run-cockpit.sh" "$run" >/dev/null || fail "run-cockpit.sh failed in the successor's pane; run adopt again"
  close_next_row "$self_pane" "adopted as $overseer"
  if [ "$refocus" = true ] && [ -n "$to_tab" ]; then "$backend" focus-tab "$to_tab" >/dev/null 2>&1 || true; fi
  agents=$("$backend" agents) || agents='[]'
  carried=$(jq -r --argjson live "$agents" '.carried[]? as $n |
    ([$live[] | select(.name == $n)][0]) as $a |
    "carried: \($n) pane=\($a.pane // "gone") status=\($a.status // "gone")"' "$state_file")
  if [ "$(rot .ledger)" != adopted ]; then
    note "HANDOVER adopted: $overseer moved from pane $from_pane to pane $self_pane (tab $to_tab); the old cockpit pane and its board are closed (old session $old_state at close); carried agents: $(jq -r '.carried // [] | if length == 0 then "none" else join(", ") end' "$state_file")."
    write_state '.ledger = "adopted"'
  fi
  write_state --arg at "$(now)" '.state = "closed" | .closed_at = $at'
  echo "adopted: you are $overseer in pane $self_pane; the old cockpit pane $from_pane is closed (old session $old_state at close)."
  if [ -n "$carried" ]; then
    echo "$carried"
    echo "A carried agent that reads idle or done may have called back to the old session: read its report or questions file now."
  fi
  echo "Watchers ended with the old session: start a background wait for each working agent, and the CI watchers the continuation file lists."
  ;;

abort)
  [ $# -eq 0 ] || usage
  [ -n "$(rot .state)" ] || fail "no handover was started for this run"
  [ "$(rot .from_pane)" = "$self_pane" ] ||
    fail "only the overseer that started the handover (pane $(rot .from_pane)) aborts; caller is pane $self_pane"
  acquire
  case $(rot .state) in
    preparing|started) write_state --arg at "$(now)" '.state = "aborted" | .aborted_at = $at' ;;
    aborted|expired) ;;
    *) fail "the handover is $(rot .state); only an offer the successor has not adopted is aborted" ;;
  esac
  release
  to_pane=$(rot .to_pane)
  close_successor "$to_pane" "handover aborted" ||
    fail "the offer is withdrawn and the successor can no longer adopt, but its pane $to_pane did not close: close it ('herdr-backend.sh close $to_pane') and run abort again"
  keep_name || fail "could not take the name $overseer back: run abort again"
  note "HANDOVER aborted: successor pane ${to_pane:-none} closed; pane $self_pane remains $overseer."
  echo "handover aborted: the successor is closed; you remain $overseer"
  ;;
esac
