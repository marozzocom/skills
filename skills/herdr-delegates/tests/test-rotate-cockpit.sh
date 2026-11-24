#!/usr/bin/env bash
# rotate-cockpit.sh against a stateful mock herdr: start's refusals, the
# handover sequence and its order, a withdrawn or expired offer, an
# interrupted adoption, abort, and the backend verbs it adds.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
R="$BIN_DIR/rotate-cockpit.sh"
H="$BIN_DIR/herdr-backend.sh"
C="$BIN_DIR/run-cockpit.sh"
S="$BIN_DIR/../../implementation-orchestration/bin/status-set.sh"
export ROTATE_POLL=0 ROTATE_RETIRE_WAIT=0

# A herdr whose lists are files and whose mutations edit them: a closed pane
# leaves the lists (its agent and an emptied tab with it), a held name is
# refused, and a created tab gets the next free number.
cat >"$MOCK_BIN/herdr" <<'MOCK'
#!/usr/bin/env bash
set -u
S=${HERDR_SCENARIO:?}
printf 'herdr %s\n' "$*" >>"${MOCK_LOG:?}"
edit() { local f=$1; shift; jq "$@" "$S/$f" >"$S/$f.tmp" && mv "$S/$f.tmp" "$S/$f"; }
case "$1 $2" in
  "agent list")
    # dialog-clears-after: on the Nth agent list after a dialog start, its blocked agent
    # reads idle and the dialog leaves the screen (with dialog-exit: the agent is gone;
    # with keep-pane: the screen stays).
    if [ -f "$S/dialog-clears-after" ]; then
      n=$(($(cat "$S/dialog-clears-after") - 1)); echo "$n" >"$S/dialog-clears-after"
      if [ "$n" -le 0 ]; then
        rm "$S/dialog-clears-after"
        if [ -f "$S/dialog-exit" ]; then edit agents.json '.result.agents |= map(select(.agent_status != "blocked"))'
        else edit agents.json '.result.agents |= map(if .agent_status == "blocked" then .agent_status = "idle" else . end)'; fi
        [ -f "$S/keep-pane" ] || rm -f "$S/pane.txt"
      fi
    fi
    cat "$S/agents.json" ;;
  "pane list") cat "$S/panes.json" ;;
  "agent read")
    # pane.txt is the visible screen; pane-clears-after: the Nth read finds it cleared.
    if [ -f "$S/pane-clears-after" ]; then
      n=$(($(cat "$S/pane-clears-after") - 1)); echo "$n" >"$S/pane-clears-after"
      [ "$n" -gt 0 ] || rm -f "$S/pane-clears-after" "$S/pane.txt"
    fi
    [ -f "$S/pane.txt" ] || exit 1
    cat "$S/pane.txt" ;;
  "tab list") cat "$S/tabs.json" ;;
  "workspace list") cat "$S/workspaces.json" ;;
  "pane layout")
    id=''; [ "${3:-}" != --pane ] || id=$4
    if [ -n "$id" ] && ! jq -e --arg p "$id" 'any(.result.panes[]; .pane_id == $p)' "$S/panes.json" >/dev/null; then exit 1; fi
    jq -c --arg p "$id" '{result:{layout:{focused_pane_id:$p,panes:[.result.panes[]|{pane_id,rect:{width:158,height:46}}]}}}' "$S/panes.json" ;;
  "agent rename")
    # rename-fail: one refused "TARGET NAME" pair per line.
    if [ -f "$S/rename-fail" ] && grep -qxF "$3 $4" "$S/rename-fail"; then echo '{"error":{"code":"mock_refused"}}'; exit 1; fi
    if jq -e --arg n "$4" 'any(.result.agents[]; .name == $n)' "$S/agents.json" >/dev/null; then
      echo '{"error":{"code":"agent_name_taken"}}'; exit 1; fi
    jq -e --arg t "$3" 'any(.result.agents[]; .pane_id == $t or .name == $t)' "$S/agents.json" >/dev/null ||
      { echo '{"error":{"code":"agent_not_found"}}'; exit 1; }
    edit agents.json --arg t "$3" --arg n "$4" '.result.agents |= map(if .pane_id == $t or .name == $t then .name = $n else . end)'
    # term-on-rename: after applying a rename to this name, signal the script that asked for it.
    if [ -f "$S/term-on-rename" ] && [ "$4" = "$(cat "$S/term-on-rename")" ]; then
      kill -TERM "$(ps -o ppid= -p "$PPID" | tr -d ' ')"
    fi
    echo '{}' ;;
  "agent start")
    [ ! -f "$S/start-fail" ] || { echo '{"error":{"code":"agent_pane_busy"}}'; exit 1; }
    name=$3; kind=''; pane=''; shift 3
    while [ $# -gt 0 ]; do
      case $1 in --kind) kind=$2; shift 2 ;; --pane) pane=$2; shift 2 ;; --) break ;; *) shift ;; esac
    done
    tab=$(jq -r --arg p "$pane" '[.result.panes[]|select(.pane_id==$p)][0].tab_id' "$S/panes.json")
    st=idle; [ ! -f "$S/start-dialog" ] || st=blocked
    edit agents.json --arg n "$name" --arg k "$kind" --arg p "$pane" --arg t "$tab" --arg st "$st" \
      '.result.agents += [{name:$n,pane_id:$p,tab_id:$t,workspace_id:"w1",agent:$k,agent_status:$st}]'
    # start-dialog: Herdr 0.9.5's blocked start (exit 1, empty stdout, JSON on stderr).
    if [ -f "$S/start-dialog" ]; then
      printf '{"error":{"code":"agent_not_ready","message":"agent %s is blocked during startup and is not ready for prompts"},"id":"cli:agent:start"}\n' "$name" >&2; exit 1
    fi
    jq -cn --arg p "$pane" '{result:{agent:{pane_id:$p,agent_status:"idle"}}}' ;;
  "agent prompt")
    printf '%s' "$4" >"$S/prompt.txt"
    [ ! -f "$S/on-prompt.sh" ] || bash "$S/on-prompt.sh"
    echo '{"result":{"started":true}}' ;;
  "tab create")
    label=''; cwd=''; shift 2
    while [ $# -gt 0 ]; do
      case $1 in --label) label=$2; shift 2 ;; --cwd) cwd=$2; shift 2 ;; --workspace) shift 2 ;; *) shift ;; esac
    done
    n=$(cat "$S/counter"); echo $((n + 1)) >"$S/counter"
    edit tabs.json --arg t "w1:t$n" --arg l "$label" '.result.tabs += [{tab_id:$t,workspace_id:"w1",label:$l,focused:false}]'
    edit panes.json --arg t "w1:t$n" --arg p "w1:p$n" --arg c "$cwd" '.result.panes += [{pane_id:$p,tab_id:$t,workspace_id:"w1",agent:null,agent_status:"unknown",cwd:$c}]'
    [ ! -f "$S/on-tab-create.sh" ] || bash "$S/on-tab-create.sh"
    # break-state-write: make the calling start's next state write fail (its temp path becomes a directory).
    if [ -f "$S/break-state-write" ]; then
      p=$PPID; p=$(ps -o ppid= -p "$p" | tr -d ' '); p=$(ps -o ppid= -p "$p" | tr -d ' ')
      mkdir "$(cat "$S/break-state-write").tmp.$p"
    fi
    jq -cn --arg t "w1:t$n" --arg p "w1:p$n" '{result:{tab:{tab_id:$t},root_pane:{pane_id:$p}}}' ;;
  "tab rename") edit tabs.json --arg t "$3" --arg l "$4" '.result.tabs |= map(if .tab_id == $t then .label = $l else . end)'; echo '{}' ;;
  "tab focus") edit tabs.json --arg t "$3" '.result.tabs |= map(.focused = (.tab_id == $t))'; echo '{}' ;;
  "workspace rename") echo '{}' ;;
  "pane split")
    n=$(cat "$S/counter"); echo $((n + 1)) >"$S/counter"
    tab=$(jq -r --arg p "$3" '[.result.panes[]|select(.pane_id==$p)][0].tab_id' "$S/panes.json")
    edit panes.json --arg t "$tab" --arg p "w1:b$n" '.result.panes += [{pane_id:$p,tab_id:$t,workspace_id:"w1",agent:null,agent_status:"unknown",cwd:"/"}]'
    jq -cn --arg p "w1:b$n" '{result:{pane:{pane_id:$p}}}' ;;
  "pane run") echo '{}' ;;
  "pane close")
    [ ! -f "$S/close-fail" ] || [ "$3" != "$(cat "$S/close-fail")" ] || exit 1
    tab=$(jq -r --arg p "$3" '[.result.panes[]|select(.pane_id==$p)][0].tab_id // ""' "$S/panes.json")
    [ -n "$tab" ] || exit 1
    edit panes.json --arg p "$3" '.result.panes |= map(select(.pane_id != $p))'
    edit agents.json --arg p "$3" '.result.agents |= map(select(.pane_id != $p))'
    jq -e --arg t "$tab" 'any(.result.panes[]; .tab_id == $t)' "$S/panes.json" >/dev/null ||
      edit tabs.json --arg t "$tab" '.result.tabs |= map(select(.tab_id != $t))'
    echo '{}' ;;
  *) echo "mock herdr: unhandled: $*" >&2; exit 1 ;;
esac
MOCK
chmod +x "$MOCK_BIN/herdr"

as_old() { HERDR_WORKSPACE_ID=w1 HERDR_TAB_ID=w1:t1 HERDR_PANE_ID=w1:p1 "$@"; }
as_new() { HERDR_WORKSPACE_ID=w1 HERDR_TAB_ID=w1:t10 HERDR_PANE_ID=w1:p10 "$@"; }
agent_name() { jq -r --arg p "$1" '[.result.agents[]|select(.pane_id==$p)][0].name // ""' "$HERDR_SCENARIO/agents.json"; }
pane_exists() { jq -r --arg p "$1" 'any(.result.panes[]; .pane_id == $p)' "$HERDR_SCENARIO/panes.json"; }
tab_label() { jq -r --arg t "$1" '[.result.tabs[]|select(.tab_id==$t)][0].label // ""' "$HERDR_SCENARIO/tabs.json"; }
row() { jq -r --arg n "$1" '[.agents[]|select(.name==$n)][0]|[.pane,.tab,.state]|join("|")' "$run/status.json"; }
state() { jq -r .state "$run/rotation.json"; }
# A run with a cockpit in w1:p1 (tab w1:t1, focused), its board, and one
# working delegate fixture-n1-impl in w1:p5 (tab w1:t2).
fixture() {
  run=$SCRATCH/$1; mkdir "$run"
  rm -f "$HERDR_SCENARIO"/on-prompt.sh "$HERDR_SCENARIO"/on-tab-create.sh "$HERDR_SCENARIO"/rename-fail \
    "$HERDR_SCENARIO"/term-on-rename "$HERDR_SCENARIO"/start-fail "$HERDR_SCENARIO"/close-fail \
    "$HERDR_SCENARIO"/break-state-write "$HERDR_SCENARIO"/start-dialog "$HERDR_SCENARIO"/dialog-clears-after \
    "$HERDR_SCENARIO"/dialog-exit "$HERDR_SCENARIO"/keep-pane "$HERDR_SCENARIO"/pane-clears-after "$HERDR_SCENARIO"/pane.txt
  echo 10 >"$HERDR_SCENARIO/counter"
  echo '{"result":{"agents":[{"name":"","pane_id":"w1:p1","tab_id":"w1:t1","workspace_id":"w1","agent":"claude","agent_status":"working"},
    {"name":"fixture-n1-impl","pane_id":"w1:p5","tab_id":"w1:t2","workspace_id":"w1","agent":"codex","agent_status":"working"}]}}' >"$HERDR_SCENARIO/agents.json"
  jq -n --arg c "$SCRATCH" '{result:{panes:[{pane_id:"w1:p1",tab_id:"w1:t1",workspace_id:"w1",agent:"claude",agent_status:"working",cwd:$c},
    {pane_id:"w1:p5",tab_id:"w1:t2",workspace_id:"w1",agent:"codex",agent_status:"working",cwd:$c}]}}' >"$HERDR_SCENARIO/panes.json"
  echo '{"result":{"tabs":[{"tab_id":"w1:t1","workspace_id":"w1","label":"shell","focused":true},{"tab_id":"w1:t2","workspace_id":"w1","label":"fixture·N1","focused":false}]}}' >"$HERDR_SCENARIO/tabs.json"
  echo '{"result":{"workspaces":[{"workspace_id":"w1","label":"fixture"}]}}' >"$HERDR_SCENARIO/workspaces.json"
  "$S" "$run" init 2026-11-01-fixture fixture 'Hand over' >/dev/null
  as_old "$C" "$run" >/dev/null || echo "fixture cockpit failed" >&2
  "$S" "$run" agent fixture-n1-impl role=implementer pane=w1:p5 tab=w1:t2 state=open >/dev/null
  echo 'resume from here' >"$run/continuation.md"
  old_board=$(jq -r .herdr.board_pane "$run/status.json")
  echo 10 >"$HERDR_SCENARIO/counter" # the next tab is w1:t10 with pane w1:p10
  : >"$MOCK_LOG"
}
# The successor's side of the handover, run by the mock when it is prompted.
adopt_on_prompt() {
  cat >"$HERDR_SCENARIO/on-prompt.sh" <<HOOK
HERDR_WORKSPACE_ID=w1 HERDR_TAB_ID=w1:t10 HERDR_PANE_ID=w1:p10 "$R" "$run" adopt >"$SCRATCH/adopt.out" 2>&1
echo \$? >"$SCRATCH/adopt.rc"
HOOK
}
# An offer the successor has not answered: tab, pane, agent, row, state.
offer() { # EXPIRES_AT
  herdr tab create --workspace w1 --cwd "$SCRATCH" --label 'fixture·cockpit-next' --no-focus >/dev/null
  herdr agent start fixture-overseer-next --kind claude --pane w1:p10 >/dev/null
  "$S" "$run" agent fixture-overseer-next role=overseer pane=w1:p10 tab=w1:t10 state=open >/dev/null
  jq -n --arg b "$old_board" --argjson e "$1" '{state:"started",from_pane:"w1:p1",from_tab:"w1:t1",from_board:$b,to_pane:"w1:p10",to_tab:"w1:t10",carried:["fixture-n1-impl"],expires_at:$e}' >"$run/rotation.json"
  : >"$MOCK_LOG"
}
future=$(($(date +%s) + 600))

# --- start refuses a run that is not ready ---------------------------------
fixture refusals
out=$(HERDR_WORKSPACE_ID=w1 HERDR_TAB_ID=w1:t2 HERDR_PANE_ID=w1:p5 "$R" "$run" start 2>&1); assert_eq wrong-pane-exit 1 "$?"
assert_contains wrong-pane "only the run's overseer (pane w1:p1)" "$out"
out=$(as_old "$R" "$run" start 2>&1); assert_eq uncarried-exit 1 "$?"
assert_contains uncarried 'open and not carried: fixture-n1-impl' "$out"
out=$(as_old "$R" "$run" start --carry fixture-n1-impl --carry fixture-ghost 2>&1); assert_eq ghost-exit 1 "$?"
assert_contains ghost 'carried but has no open row: fixture-ghost' "$out"
jq '.result.agents |= map(select(.name != "fixture-n1-impl"))' "$HERDR_SCENARIO/agents.json" >"$SCRATCH/a" && mv "$SCRATCH/a" "$HERDR_SCENARIO/agents.json"
out=$(as_old "$R" "$run" start --carry fixture-n1-impl 2>&1); assert_eq dead-exit 1 "$?"
assert_contains dead 'carried but not running: fixture-n1-impl' "$out"
"$S" "$run" agent fixture-n1-impl state=closed >/dev/null
touch -t 202001010000 "$run/continuation.md"
out=$(as_old "$R" "$run" start 2>&1); assert_eq stale-continuation-exit 1 "$?"
assert_contains stale-continuation 'older than 30 minutes' "$out"
rm "$run/continuation.md"
out=$(as_old "$R" "$run" start 2>&1); assert_eq no-continuation-exit 1 "$?"
assert_contains no-continuation 'continuation.md first' "$out"
assert_eq refusals-create-nothing 0 "$(grep -Ec 'tab create|agent start|agent rename|pane close' "$MOCK_LOG")"
assert_eq refusals-leave-no-state false "$([ -f "$run/rotation.json" ] && echo true || echo false)"
out=$(HERDR_ENV='' "$R" "$run" start 2>&1); assert_eq no-herdr-exit 3 "$?"
assert_contains no-herdr 'manual path' "$out"
out=$(as_old "$R" "$run" status); assert_eq status-none 'state=none' "$out"

# --- the handover: old starts, successor adopts, old pane and tab are gone ---
fixture handover
adopt_on_prompt
out=$(as_old "$R" "$run" start --wait 30 --carry fixture-n1-impl -- --model pinned --permission-mode auto 2>&1); assert_eq handover-exit 0 "$?"
assert_contains handover-says-stop 'handover complete: fixture-overseer is now pane w1:p10' "$out"
assert_eq adopt-exit 0 "$(cat "$SCRATCH/adopt.rc")"
log=$(cat "$MOCK_LOG")
assert_contains successor-start 'agent start fixture-overseer-next --kind claude --pane w1:p10 --timeout 30000 -- --model pinned --permission-mode auto' "$log"
assert_contains successor-tab 'tab create --workspace w1 --cwd '"$SCRATCH"' --label fixture·cockpit-next' "$log"
prompt=$(cat "$HERDR_SCENARIO/prompt.txt")
assert_contains prompt-continuation "Read $run/continuation.md in full" "$prompt"
assert_contains prompt-adopt "rotate-cockpit.sh $run adopt" "$prompt"
assert_contains prompt-role 'not a task brief, and you are not a worker' "$prompt"
retire_line=$(grep -n 'agent rename w1:p1 fixture-overseer-retired' "$MOCK_LOG" | cut -d: -f1)
take_line=$(grep -n 'agent rename w1:p10 fixture-overseer$' "$MOCK_LOG" | cut -d: -f1)
close_line=$(grep -n 'pane close w1:p1$' "$MOCK_LOG" | cut -d: -f1)
assert_eq old-retired-before-name-taken true "$([ "${retire_line:-0}" -gt 0 ] && [ "$retire_line" -lt "${take_line:-0}" ] && echo true)"
assert_eq name-taken-before-old-closed true "$([ "${take_line:-0}" -gt 0 ] && [ "$take_line" -lt "${close_line:-0}" ] && echo true)"
assert_eq successor-holds-name fixture-overseer "$(agent_name w1:p10)"
assert_eq old-pane-gone false "$(pane_exists w1:p1)"
assert_eq old-board-gone false "$(pane_exists "$old_board")"
assert_eq old-tab-gone '' "$(tab_label w1:t1)"
assert_eq successor-tab-label 'fixture·cockpit' "$(tab_label w1:t10)"
assert_eq delegate-untouched true "$(pane_exists w1:p5)"
new_board=$(jq -r .herdr.board_pane "$run/status.json")
assert_eq new-board-live true "$(pane_exists "$new_board")"
assert_eq meta "w1:p10|w1:t10" "$(jq -r '.herdr|[.overseer_pane,.cockpit_tab]|join("|")' "$run/status.json")"
assert_eq overseer-row 'w1:p10|w1:t10|open' "$(row fixture-overseer)"
assert_eq one-overseer-row 1 "$(jq '[.agents[]|select(.name=="fixture-overseer")]|length' "$run/status.json")"
assert_eq next-row-closed 'w1:p10|w1:t10|closed' "$(row fixture-overseer-next)"
assert_eq delegate-row-open 'w1:p5|w1:t2|open' "$(row fixture-n1-impl)"
assert_eq state-closed closed "$(state)"
assert_contains follows-the-human 'tab focus w1:t10' "$log"
adopt_out=$(cat "$SCRATCH/adopt.out")
assert_contains carried-listed 'carried: fixture-n1-impl pane=w1:p5 status=working' "$adopt_out"
assert_contains carried-reconcile 'may have called back to the old session' "$adopt_out"
assert_contains watchers 'Watchers ended with the old session' "$adopt_out"
assert_contains old-killed-working 'old session still working at close' "$adopt_out"
assert_eq ledger-adopted-once 1 "$(grep -c 'HANDOVER adopted: fixture-overseer moved from pane w1:p1 to pane w1:p10' "$run/ledger.md")"
out=$(as_new "$R" "$run" adopt); assert_eq readopt-exit 0 "$?"
assert_eq readopt 'already adopted: fixture-overseer is pane w1:p10' "$out"
out=$(as_old "$R" "$run" status); assert_eq status-closed 'state=closed from=w1:p1 to=w1:p10' "$out"
# The retired pane can neither start again nor abort.
out=$(as_old "$R" "$run" start 2>&1); assert_eq retired-start-exit 1 "$?"
out=$(as_old "$R" "$run" abort 2>&1); assert_eq retired-abort-exit 1 "$?"
assert_contains retired-abort 'only an offer the successor has not adopted' "$out"
# A second handover from the new cockpit works from the closed state.
echo 11 >"$HERDR_SCENARIO/counter"
cat >"$HERDR_SCENARIO/on-prompt.sh" <<HOOK
HERDR_WORKSPACE_ID=w1 HERDR_TAB_ID=w1:t11 HERDR_PANE_ID=w1:p11 "$R" "$run" adopt >"$SCRATCH/adopt2.out" 2>&1
HOOK
out=$(as_new "$R" "$run" start --wait 30 --carry fixture-n1-impl 2>&1); assert_eq second-handover-exit 0 "$?"
assert_contains unpinned-warning 'no native agent args' "$out"
assert_eq second-holder fixture-overseer "$(agent_name w1:p11)"
assert_eq second-old-gone false "$(pane_exists w1:p10)"
assert_eq second-ledger 2 "$(grep -c 'HANDOVER adopted' "$run/ledger.md")"

# --- a successor that never answers: the offer is withdrawn, old stays -----
fixture withdrawn
"$S" "$run" agent fixture-n1-impl state=closed >/dev/null
out=$(as_old "$R" "$run" start --wait 0 -- --model pinned 2>&1); assert_eq withdrawn-exit 4 "$?"
assert_contains withdrawn-msg 'This session is still fixture-overseer' "$out"
assert_eq withdrawn-state aborted "$(state)"
assert_eq withdrawn-pane-closed false "$(pane_exists w1:p10)"
assert_eq withdrawn-tab-closed '' "$(tab_label w1:t10)"
assert_eq withdrawn-row 'w1:p10|w1:t10|closed' "$(row fixture-overseer-next)"
assert_eq withdrawn-old-keeps-name fixture-overseer "$(agent_name w1:p1)"
assert_eq withdrawn-old-alive true "$(pane_exists w1:p1)"
assert_eq withdrawn-meta w1:p1 "$(jq -r .herdr.overseer_pane "$run/status.json")"
# The prompt is re-sent while the successor still reads idle.
fixture resend
"$S" "$run" agent fixture-n1-impl state=closed >/dev/null
out=$(as_old env ROTATE_RESEND_AFTER=0 ROTATE_POLL=1 "$R" "$run" start --wait 8 2>&1); assert_eq resend-exit 4 "$?"
assert_eq resend-count true "$([ "$(grep -c 'agent prompt fixture-overseer-next' "$MOCK_LOG")" -ge 2 ] && echo true)"
# A successor that cannot start leaves nothing behind.
fixture nostart
"$S" "$run" agent fixture-n1-impl state=closed >/dev/null
touch "$HERDR_SCENARIO/start-fail"
out=$(as_old "$R" "$run" start --wait 0 2>&1); assert_eq nostart-exit 1 "$?"
assert_contains nostart-msg 'did not start in pane w1:p10' "$out"
assert_eq nostart-pane-closed false "$(pane_exists w1:p10)"
assert_eq nostart-state aborted "$(state)"
# A startup dialog (backend exit 4): never started again; the handover waits for it to clear.
fixture dialog-clears
"$S" "$run" agent fixture-n1-impl state=closed >/dev/null
trust_screen() { printf 'Accessing workspace:\n\n%s\n\nDo you trust the contents of this project?\n> Yes, I trust this folder\n  No, exit\n' "$SCRATCH" >"$HERDR_SCENARIO/pane.txt"; }
touch "$HERDR_SCENARIO/start-dialog"; echo 6 >"$HERDR_SCENARIO/dialog-clears-after"; trust_screen
adopt_on_prompt
out=$(as_old "$R" "$run" start --wait 30 -- --model pinned 2>&1); assert_eq dialog-clears-exit 0 "$?"
assert_contains dialog-clears-diagnostic 'start: dialog=folder_trust agent=fixture-overseer-next pane=w1:p10' "$out"
assert_contains dialog-clears-waits 'hb start exit 4' "$out"
assert_eq dialog-clears-one-start 1 "$(grep -c 'agent start' "$MOCK_LOG")"
assert_eq dialog-clears-no-keys 0 "$(grep -c 'send-keys' "$MOCK_LOG")"
assert_eq dialog-clears-adopted 0 "$(cat "$SCRATCH/adopt.rc")"
assert_eq dialog-clears-holds-name fixture-overseer "$(agent_name w1:p10)"
assert_eq dialog-clears-state closed "$(state)"
fixture dialog-stays
"$S" "$run" agent fixture-n1-impl state=closed >/dev/null
touch "$HERDR_SCENARIO/start-dialog"
out=$(as_old "$R" "$run" start --wait 0 2>&1); assert_eq dialog-stays-exit 1 "$?"
assert_contains dialog-stays-msg 'handover withdrawn: startup dialog on successor pane w1:p10' "$out"
assert_eq dialog-stays-one-start 1 "$(grep -c 'agent start' "$MOCK_LOG")"
assert_eq dialog-stays-pane-closed false "$(pane_exists w1:p10)"
assert_eq dialog-stays-state aborted "$(state)"
assert_eq dialog-stays-old-keeps-name fixture-overseer "$(agent_name w1:p1)"
# The human leaves the dialog (No, exit): the offer is withdrawn at once, not at the deadline.
fixture dialog-exited
"$S" "$run" agent fixture-n1-impl state=closed >/dev/null
touch "$HERDR_SCENARIO/start-dialog" "$HERDR_SCENARIO/dialog-exit"; echo 6 >"$HERDR_SCENARIO/dialog-clears-after"; trust_screen
began=$SECONDS
out=$(as_old "$R" "$run" start --wait 60 2>&1); assert_eq dialog-exited-exit 1 "$?"
assert_contains dialog-exited-msg 'startup dialog exited in pane w1:p10' "$out"
assert_eq dialog-exited-prompt true "$([ $((SECONDS - began)) -lt 30 ] && echo true)"
assert_eq dialog-exited-pane-closed false "$(pane_exists w1:p10)"
assert_eq dialog-exited-one-start 1 "$(grep -c 'agent start' "$MOCK_LOG")"
# Reads idle with the trust prompt still on screen: the wait goes on until the screen clears.
fixture idle-trust
"$S" "$run" agent fixture-n1-impl state=closed >/dev/null
touch "$HERDR_SCENARIO/start-dialog" "$HERDR_SCENARIO/keep-pane"; echo 6 >"$HERDR_SCENARIO/dialog-clears-after"; trust_screen
echo 4 >"$HERDR_SCENARIO/pane-clears-after"
adopt_on_prompt
out=$(as_old "$R" "$run" start --wait 30 2>&1); assert_eq idle-trust-exit 0 "$?"
reads_before_clear=$(grep -c 'agent read' "$MOCK_LOG")
assert_eq idle-trust-waited-on-screen true "$([ "$reads_before_clear" -ge 3 ] && echo true)"
assert_eq idle-trust-adopted 0 "$(cat "$SCRATCH/adopt.rc")"

# --- adopt: only the successor, only a live offer ---------------------------
fixture offers
out=$(as_new "$R" "$run" adopt 2>&1); assert_eq no-offer-exit 1 "$?"
assert_contains no-offer 'no handover was started' "$out"
offer "$future"
out=$(HERDR_WORKSPACE_ID=w1 HERDR_TAB_ID=w1:t2 HERDR_PANE_ID=w1:p5 "$R" "$run" adopt 2>&1); assert_eq stranger-adopt-exit 1 "$?"
assert_contains stranger-adopt 'only the successor in pane w1:p10' "$out"
assert_eq stranger-renamed-nothing 0 "$(grep -c 'agent rename' "$MOCK_LOG")"
out=$(as_old "$R" "$run" start --carry fixture-n1-impl 2>&1); assert_eq busy-start-exit 1 "$?"
assert_contains busy-start 'already in progress' "$out"
# An expired offer: the successor steps down and closes itself; names stay.
jq '.expires_at = 1' "$run/rotation.json" >"$SCRATCH/r" && mv "$SCRATCH/r" "$run/rotation.json"
out=$(as_new "$R" "$run" adopt 2>&1); assert_eq expired-exit 1 "$?"
assert_contains expired-msg 'offer was expired: the old session remains fixture-overseer' "$out"
assert_eq expired-state expired "$(state)"
assert_eq expired-no-rename 0 "$(grep -c 'agent rename' "$MOCK_LOG")"
assert_eq expired-self-closed false "$(pane_exists w1:p10)"
assert_eq expired-old-keeps-name fixture-overseer "$(agent_name w1:p1)"
assert_eq expired-row closed "$(jq -r '[.agents[]|select(.name=="fixture-overseer-next")][0].state' "$run/status.json")"
# A stale offer (its clock ran out, successor still there) is cleaned by the next start.
fixture stale
offer 1
out=$(as_old "$R" "$run" start --carry fixture-n1-impl --wait 0 2>&1); assert_eq stale-start-exit 4 "$?"
assert_contains stale-cleaned 'pane close w1:p10' "$(cat "$MOCK_LOG")"
assert_eq stale-new-offer-withdrawn false "$(pane_exists w1:p11)"

# --- adopt survives an interruption and a failed rename ---------------------
fixture resume
offer "$future"
echo 'w1:p10 fixture-overseer' >"$HERDR_SCENARIO/rename-fail"
out=$(as_new "$R" "$run" adopt 2>&1); assert_eq rename-fail-exit 1 "$?"
assert_contains rename-fail-msg 'the old session keeps it' "$out"
assert_eq rename-fail-state started "$(state)"
assert_eq rename-fail-old-holds-name fixture-overseer "$(agent_name w1:p1)"
assert_eq rename-fail-lock-released false "$([ -d "$run/.rotation.lock" ] && echo true || echo false)"
rm "$HERDR_SCENARIO/rename-fail"
jq '.result.agents |= map(if .pane_id == "w1:p1" then .agent_status = "idle" else . end)' "$HERDR_SCENARIO/agents.json" >"$SCRATCH/a" && mv "$SCRATCH/a" "$HERDR_SCENARIO/agents.json"
echo w1:p1 >"$HERDR_SCENARIO/close-fail"
out=$(as_new "$R" "$run" adopt 2>&1); assert_eq close-fail-exit 1 "$?"
assert_contains close-fail-msg 'did not close; run adopt again' "$out"
assert_eq close-fail-state adopted "$(state)"
assert_eq close-fail-holder fixture-overseer "$(agent_name w1:p10)"
out=$(as_old "$R" "$run" abort 2>&1); assert_eq abort-after-adopt-exit 1 "$?"
rm "$HERDR_SCENARIO/close-fail"
out=$(as_new "$R" "$run" adopt 2>&1); assert_eq resumed-exit 0 "$?"
assert_contains resumed-old-stopped 'old session stopped at close' "$out"
assert_eq resumed-state closed "$(state)"
assert_eq resumed-old-gone false "$(pane_exists w1:p1)"
assert_eq resumed-row 'w1:p10|w1:t10|open' "$(row fixture-overseer)"
assert_eq resumed-ledger-once 1 "$(grep -c 'HANDOVER adopted' "$run/ledger.md")"
# When giving the name back fails too, the script says so; a second adopt repairs it.
fixture rollback
offer "$future"
printf 'w1:p10 fixture-overseer\nw1:p1 fixture-overseer\n' >"$HERDR_SCENARIO/rename-fail"
out=$(as_new "$R" "$run" adopt 2>&1); assert_eq rollback-fail-exit 1 "$?"
assert_contains rollback-fail-msg 'nobody holds the name fixture-overseer now' "$out"
assert_not_contains rollback-fail-no-false-claim 'the old session keeps it' "$out"
rm "$HERDR_SCENARIO/rename-fail"
out=$(as_new "$R" "$run" adopt 2>&1); assert_eq rollback-readopt-exit 0 "$?"
assert_eq rollback-readopt-holder fixture-overseer "$(agent_name w1:p10)"
# ... or the old session's abort repairs it.
fixture rollback-abort
offer "$future"
printf 'w1:p10 fixture-overseer\nw1:p1 fixture-overseer\n' >"$HERDR_SCENARIO/rename-fail"
as_new "$R" "$run" adopt >/dev/null 2>&1
rm "$HERDR_SCENARIO/rename-fail"
out=$(as_old "$R" "$run" abort 2>&1); assert_eq rollback-abort-exit 0 "$?"
assert_eq rollback-abort-holder fixture-overseer "$(agent_name w1:p1)"
# A signal between the two renames gives the name back.
fixture signal
offer "$future"
echo fixture-overseer-retired >"$HERDR_SCENARIO/term-on-rename"
out=$(as_new "$R" "$run" adopt 2>&1); assert_eq signal-exit 1 "$?"
assert_eq signal-old-holds-name fixture-overseer "$(agent_name w1:p1)"
assert_eq signal-successor-name fixture-overseer-next "$(agent_name w1:p10)"
assert_eq signal-state started "$(state)"
assert_eq signal-lock-released false "$([ -d "$run/.rotation.lock" ] && echo true || echo false)"
rm "$HERDR_SCENARIO/term-on-rename"
out=$(as_new "$R" "$run" adopt 2>&1); assert_eq signal-readopt-exit 0 "$?"
# An abort while start is still setting up stops that start; nothing is prompted or left.
fixture abort-during-start
cat >"$HERDR_SCENARIO/on-tab-create.sh" <<HOOK
HERDR_WORKSPACE_ID=w1 HERDR_TAB_ID=w1:t1 HERDR_PANE_ID=w1:p1 "$R" "$run" abort >"$SCRATCH/abort.out" 2>&1
echo \$? >"$SCRATCH/abort.rc"
HOOK
out=$(as_old "$R" "$run" start --wait 30 --carry fixture-n1-impl 2>&1); assert_eq aborted-start-exit 1 "$?"
assert_eq aborted-start-abort-rc 0 "$(cat "$SCRATCH/abort.rc")"
assert_contains aborted-start-msg 'the offer was aborted' "$out"
assert_eq aborted-start-state aborted "$(state)"
assert_eq aborted-start-no-prompt 0 "$(grep -c 'agent prompt' "$MOCK_LOG")"
assert_eq aborted-start-no-agent 0 "$(grep -c 'agent start' "$MOCK_LOG")"
assert_eq aborted-start-pane-closed false "$(pane_exists w1:p10)"
assert_eq aborted-start-old-holds-name fixture-overseer "$(agent_name w1:p1)"
# A tab that already carries the successor's label is never closed by a withdrawal.
fixture collision
jq '.result.tabs |= map(if .tab_id == "w1:t2" then .label = "fixture·cockpit-next" else . end)' "$HERDR_SCENARIO/tabs.json" >"$SCRATCH/t" && mv "$SCRATCH/t" "$HERDR_SCENARIO/tabs.json"
out=$(as_old "$R" "$run" start --wait 30 --carry fixture-n1-impl 2>&1); assert_eq collision-exit 1 "$?"
assert_contains collision-msg "could not open the successor's tab" "$out"
assert_eq collision-delegate-alive true "$(pane_exists w1:p5)"
assert_eq collision-no-close 0 "$(grep -c 'pane close' "$MOCK_LOG")"
# A failing status write after the successor exists withdraws the offer and closes it.
fixture setter-failure
mkdir "$run/.status.lock"
out=$(as_old env STATUS_LOCK_WAIT=0 "$R" "$run" start --wait 30 --carry fixture-n1-impl 2>&1); assert_eq setter-failure-exit 1 "$?"
rmdir "$run/.status.lock"
assert_contains setter-failure-msg 'handover withdrawn: start failed or was interrupted' "$out"
assert_eq setter-failure-pane-closed false "$(pane_exists w1:p10)"
assert_eq setter-failure-state aborted "$(state)"
assert_eq setter-failure-old-holds-name fixture-overseer "$(agent_name w1:p1)"
# A successor pane that will not close is reported, never claimed closed.
fixture stuck-successor
offer "$future"
echo w1:p10 >"$HERDR_SCENARIO/close-fail"
out=$(as_old "$R" "$run" abort 2>&1); assert_eq stuck-abort-exit 1 "$?"
assert_contains stuck-abort-msg 'its pane w1:p10 did not close' "$out"
assert_not_contains stuck-abort-no-false-claim 'the successor is closed' "$out"
assert_eq stuck-abort-row-open open "$(jq -r '[.agents[]|select(.name=="fixture-overseer-next")][0].state' "$run/status.json")"
assert_eq stuck-abort-state aborted "$(state)"
rm "$HERDR_SCENARIO/close-fail"
out=$(as_old "$R" "$run" abort 2>&1); assert_eq stuck-abort-retry-exit 0 "$?"
assert_eq stuck-abort-retry-row closed "$(jq -r '[.agents[]|select(.name=="fixture-overseer-next")][0].state' "$run/status.json")"
fixture stuck-withdrawn
"$S" "$run" agent fixture-n1-impl state=closed >/dev/null
echo w1:p10 >"$HERDR_SCENARIO/close-fail"
out=$(as_old "$R" "$run" start --wait 0 2>&1); assert_eq stuck-withdrawn-exit 4 "$?"
assert_contains stuck-withdrawn-msg 'its pane w1:p10 did not close' "$out"
assert_not_contains stuck-withdrawn-no-false-claim 'the successor is closed' "$out"
assert_eq stuck-withdrawn-row-open open "$(jq -r '[.agents[]|select(.name=="fixture-overseer-next")][0].state' "$run/status.json")"
# The successor of a withdrawn offer closes itself when it tries to adopt.
rm "$HERDR_SCENARIO/close-fail"
out=$(as_new "$R" "$run" adopt 2>&1); assert_eq stuck-withdrawn-late-adopt-exit 1 "$?"
assert_eq stuck-withdrawn-self-closed false "$(pane_exists w1:p10)"
assert_eq stuck-withdrawn-old-holds-name fixture-overseer "$(agent_name w1:p1)"
# A transition waits for the lock another session holds, and steals a dead one.
fixture lock
offer "$future"
mkdir "$run/.rotation.lock"
out=$(as_new env ROTATE_LOCK_TRIES=2 "$R" "$run" adopt 2>&1); assert_eq lock-held-exit 1 "$?"
assert_contains lock-held-msg 'handover lock busy' "$out"
assert_eq lock-held-renamed-nothing 0 "$(grep -c 'agent rename' "$MOCK_LOG")"
assert_eq lock-held-state started "$(state)"
out=$(as_old env ROTATE_LOCK_TRIES=2 "$R" "$run" abort 2>&1); assert_eq lock-held-abort-exit 1 "$?"
assert_eq lock-held-successor-alive true "$(pane_exists w1:p10)"
touch -t 202001010000 "$run/.rotation.lock"
out=$(as_new env ROTATE_LOCK_TRIES=2 "$R" "$run" adopt 2>&1); assert_eq dead-lock-stolen-exit 0 "$?"
assert_eq lock-released false "$([ -d "$run/.rotation.lock" ] && echo true || echo false)"
# A lock whose owner process is gone is taken at once: an adopter killed between
# its two renames must not block the old session's recovery.
fixture killed-adopter
offer "$future"
herdr agent rename w1:p1 fixture-overseer-retired >/dev/null
mkdir "$run/.rotation.lock"; (exit 0) & wait $!; echo $! >"$run/.rotation.lock/pid"
out=$(as_old env ROTATE_LOCK_TRIES=2 "$R" "$run" abort 2>&1); assert_eq killed-adopter-abort-exit 0 "$?"
assert_eq killed-adopter-old-holds-name fixture-overseer "$(agent_name w1:p1)"
assert_eq killed-adopter-successor-closed false "$(pane_exists w1:p10)"
assert_eq killed-adopter-lock-released false "$([ -d "$run/.rotation.lock" ] && echo true || echo false)"
# A dead owner's lock is taken over only inside the guard, and the guard is never taken over.
fixture guard
offer "$future"
mkdir "$run/.rotation.lock"; (exit 0) & wait $!; echo $! >"$run/.rotation.lock/pid"
dead_owner=$(cat "$run/.rotation.lock/pid")
mkdir "$run/.rotation.lock.guard"; touch -t 202001010000 "$run/.rotation.lock.guard"
out=$(as_new env ROTATE_LOCK_TRIES=2 "$R" "$run" adopt 2>&1); assert_eq guard-held-exit 1 "$?"
assert_contains guard-held-msg 'handover lock busy' "$out"
assert_contains guard-held-names-guard '.rotation.lock.guard' "$out"
assert_eq guard-held-lock-untouched "$dead_owner" "$(cat "$run/.rotation.lock/pid")"
assert_eq guard-held-guard-kept true "$([ -d "$run/.rotation.lock.guard" ] && echo true || echo false)"
assert_eq guard-held-renamed-nothing 0 "$(grep -c 'agent rename' "$MOCK_LOG")"
rmdir "$run/.rotation.lock.guard"
out=$(as_new env ROTATE_LOCK_TRIES=2 "$R" "$run" adopt 2>&1); assert_eq guard-free-exit 0 "$?"
assert_eq guard-released false "$([ -d "$run/.rotation.lock.guard" ] && echo true || echo false)"
assert_eq guard-lock-released false "$([ -d "$run/.rotation.lock" ] && echo true || echo false)"
# A start that has to stop while a live successor is mid-adoption decides nothing.
fixture undecided
"$S" "$run" agent fixture-n1-impl state=closed >/dev/null
cat >"$HERDR_SCENARIO/on-prompt.sh" <<HOOK
mkdir "$run/.rotation.lock"; echo $$ >"$run/.rotation.lock/pid"
HOOK
out=$(as_old env ROTATE_WITHDRAW_LOCK_TRIES=2 "$R" "$run" start --wait 0 2>&1); assert_eq undecided-exit 5 "$?"
assert_contains undecided-msg 'handover undecided' "$out"
assert_not_contains undecided-no-claim 'This session is still fixture-overseer' "$out"
assert_eq undecided-state started "$(state)"
assert_eq undecided-successor-alive true "$(pane_exists w1:p10)"
assert_eq undecided-no-close 0 "$(grep -c 'pane close' "$MOCK_LOG")"
assert_eq undecided-lock-kept true "$([ -d "$run/.rotation.lock" ] && echo true || echo false)"
rm -r "$run/.rotation.lock"
# A live owner keeps its lock.
fixture live-lock
offer "$future"
mkdir "$run/.rotation.lock"; echo $$ >"$run/.rotation.lock/pid"
out=$(as_new env ROTATE_LOCK_TRIES=2 "$R" "$run" adopt 2>&1); assert_eq live-lock-exit 1 "$?"
assert_contains live-lock-msg 'handover lock busy' "$out"
rm -r "$run/.rotation.lock"
# A state write that fails inside a locked step still withdraws: no leaked lock, no successor.
fixture locked-write-failure
"$S" "$run" agent fixture-n1-impl state=closed >/dev/null
echo "$run/rotation.json" >"$HERDR_SCENARIO/break-state-write"
out=$(as_old env ROTATE_LOCK_TRIES=2 "$R" "$run" start --wait 30 2>&1); assert_eq locked-write-exit 1 "$?"
assert_eq locked-write-lock-released false "$([ -d "$run/.rotation.lock" ] && echo true || echo false)"
assert_eq locked-write-successor-closed false "$(pane_exists w1:p10)"
assert_eq locked-write-old-holds-name fixture-overseer "$(agent_name w1:p1)"
assert_eq locked-write-no-prompt 0 "$(grep -c 'agent prompt' "$MOCK_LOG")"
# A start after an abort that could not close its successor: refused while the pane
# stays, with the record kept; once it can close, the old successor goes first.
fixture restart-stuck
offer "$future"
echo w1:p10 >"$HERDR_SCENARIO/close-fail"
as_old "$R" "$run" abort >/dev/null 2>&1
out=$(as_old "$R" "$run" start --wait 0 --carry fixture-n1-impl 2>&1); assert_eq restart-stuck-exit 1 "$?"
assert_contains restart-stuck-msg 'the pane w1:p10 of an earlier offer did not close' "$out"
assert_eq restart-stuck-record-kept w1:p10 "$(jq -r .to_pane "$run/rotation.json")"
assert_eq restart-stuck-row-open open "$(jq -r '[.agents[]|select(.name=="fixture-overseer-next")][0].state' "$run/status.json")"
assert_eq restart-stuck-no-new-tab 0 "$(grep -c 'tab create' "$MOCK_LOG")"
rm "$HERDR_SCENARIO/close-fail"
out=$(as_old "$R" "$run" start --wait 0 --carry fixture-n1-impl 2>&1); assert_eq restart-unstuck-exit 4 "$?"
assert_eq restart-unstuck-old-successor-closed false "$(pane_exists w1:p10)"
assert_eq restart-unstuck-new-successor-closed false "$(pane_exists w1:p11)"
assert_eq restart-unstuck-old-holds-name fixture-overseer "$(agent_name w1:p1)"
# A withdrawal that created no pane leaves another offer's row alone.
fixture foreign-row
"$S" "$run" agent fixture-overseer-next role=overseer pane=w1:p77 tab=w1:t77 state=open >/dev/null
jq '.result.tabs |= map(if .tab_id == "w1:t2" then .label = "fixture·cockpit-next" else . end)' "$HERDR_SCENARIO/tabs.json" >"$SCRATCH/t" && mv "$SCRATCH/t" "$HERDR_SCENARIO/tabs.json"
out=$(as_old "$R" "$run" start --wait 30 --carry fixture-n1-impl 2>&1); assert_eq foreign-row-exit 1 "$?"
assert_eq foreign-row-untouched open "$(jq -r '[.agents[]|select(.name=="fixture-overseer-next")][0].state' "$run/status.json")"
# A cockpit tab that held an agent pane survives without the cockpit label.
fixture shared-tab
jq '.result.panes += [{pane_id:"w1:p6",tab_id:"w1:t1",workspace_id:"w1",agent:"codex",agent_status:"working",cwd:"/"}]' "$HERDR_SCENARIO/panes.json" >"$SCRATCH/p" && mv "$SCRATCH/p" "$HERDR_SCENARIO/panes.json"
offer "$future"
out=$(as_new "$R" "$run" adopt 2>&1); assert_eq shared-tab-exit 0 "$?"
assert_eq shared-tab-old-label 'fixture·cockpit-was-p1' "$(tab_label w1:t1)"
assert_eq shared-tab-new-label 'fixture·cockpit' "$(tab_label w1:t10)"
assert_eq shared-tab-agent-kept true "$(pane_exists w1:p6)"

# --- abort -------------------------------------------------------------------
fixture abort
out=$(as_old "$R" "$run" abort 2>&1); assert_eq abort-nothing-exit 1 "$?"
offer "$future"
out=$(as_new "$R" "$run" abort 2>&1); assert_eq abort-stranger-exit 1 "$?"
assert_contains abort-stranger 'only the overseer that started the handover (pane w1:p1)' "$out"
out=$(as_old "$R" "$run" abort 2>&1); assert_eq abort-exit 0 "$?"
assert_eq abort-state aborted "$(state)"
assert_eq abort-successor-closed false "$(pane_exists w1:p10)"
assert_eq abort-row closed "$(jq -r '[.agents[]|select(.name=="fixture-overseer-next")][0].state' "$run/status.json")"
assert_eq abort-keeps-name fixture-overseer "$(agent_name w1:p1)"
out=$(as_old "$R" "$run" abort 2>&1); assert_eq abort-again-exit 0 "$?"
# An abort that lost the name to a half-finished adoption takes it back.
fixture abort-name
offer "$future"
herdr agent rename w1:p1 fixture-overseer-retired >/dev/null
out=$(as_old "$R" "$run" abort 2>&1); assert_eq abort-name-exit 0 "$?"
assert_eq abort-name-restored fixture-overseer "$(agent_name w1:p1)"
# After an abort the successor's late adopt is refused.
fixture abort-late
offer "$future"
jq '.state = "aborted"' "$run/rotation.json" >"$SCRATCH/r" && mv "$SCRATCH/r" "$run/rotation.json"
out=$(as_new "$R" "$run" adopt 2>&1); assert_eq late-adopt-exit 1 "$?"
assert_eq late-adopt-no-rename 0 "$(grep -c 'agent rename' "$MOCK_LOG")"
assert_eq late-adopt-old-keeps-name fixture-overseer "$(agent_name w1:p1)"

# --- backend verbs -------------------------------------------------------------
fixture verbs
as_old "$H" rename w1:p5 fixture-n1-impl-2; assert_eq rename-exit 0 "$?"
assert_eq rename-applied fixture-n1-impl-2 "$(agent_name w1:p5)"
out=$(as_old "$H" rename w1:p5 fixture-overseer 2>&1); assert_eq rename-taken-exit 1 "$?"
assert_contains rename-taken-msg agent_name_taken "$out"
assert_eq tab-focused true "$(as_old "$H" tab-focused w1:t1)"
assert_eq tab-not-focused false "$(as_old "$H" tab-focused w1:t2)"
as_old "$H" focus-tab w1:t2; assert_eq focus-exit 0 "$?"
assert_eq focus-applied true "$(as_old "$H" tab-focused w1:t2)"
app_fixture
"$H" rename tb1 x >/dev/null 2>&1; assert_eq app-rename-unsupported 3 "$?"
"$H" focus-tab tb1 >/dev/null 2>&1; assert_eq app-focus-unsupported 3 "$?"
finish
