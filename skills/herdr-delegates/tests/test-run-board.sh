#!/usr/bin/env bash
# Plain snapshots, scoped joins, warnings, width and compact board height.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
B="$BIN_DIR/run-board.sh"
run="$SCRATCH/run"; mkdir "$run"
export STATUS_NOW=2026-11-01T12:00:00Z
jq -n '{run_id:"fixture",prefix:"fixture",goal:"Ship the board",updated:"2026-11-01T11:00:00Z",
 waiting_on_human:[{id:"H1",action:"Approve PR",since:"2026-11-01T11:30:00Z"}],
 milestones:([range(1;6)|{id:("M"+tostring),title:"Finished",state:"done",since:"2026-11-01T10:00:00Z"}] +
 [{id:"M6",title:"Build",state:"active",since:"2026-11-01T11:00:00Z"},
 {id:"M7",title:"Land",state:"pending",since:"2026-11-01T11:00:00Z"},
 {id:"M8",title:"Later",state:"pending",since:"2026-11-01T11:00:00Z"}]),
 nodes:[{id:"N1",title:"Helper scripts",state:"review",since:"2026-11-01T11:00:00Z",pr:42,ci:"pass"}],
 agents:[{name:"fixture-impl",state:"open",since:"2026-11-01T11:45:00Z",tab:"recorded-tab"},
 {name:"fixture-gone",state:"open",since:"2026-11-01T11:00:00Z",tab:"gone-tab"},
 {name:"fixture-closed",state:"closed",since:"2026-11-01T11:00:00Z"}]}' >"$run/status.json"
jq -n '{result:{agents:[
 {name:"fixture-impl",agent_status:"working",tab_id:"live-tab",terminal_title_stripped:("\u001b[31mImplementing \u001b[0m" + ("界é⌚" * 100))},
 {name:"fixture-overseer",agent_status:"blocked",tab_id:"cockpit",terminal_title_stripped:"Permission required"},
 {name:"other-run-impl",agent_status:"blocked",terminal_title_stripped:"OUTSIDER"},
 {agent_status:"blocked",terminal_title_stripped:"UNNAMED"},
 {name:"fixture-closed",agent_status:"done",terminal_title_stripped:"CLOSED"}]}}' >"$HERDR_SCENARIO/agents.json"
{ echo '# Ledger'; for i in $(seq 1 10); do printf -- '- 2026-11-01T10:00:00Z entry-%02d\n' "$i"; done; echo 'not an entry'; } >"$run/ledger.md"
touch -t 202601010000 "$run/ledger.md"
out=$("$B" "$run" --once --width 80); rc=$?
assert_eq once-exit 0 "$rc"
assert_contains header 'RUN fixture | Ship the board' "$out"
assert_contains ledger-age 'ledger written' "$out"
assert_contains human-banner 'WAITING ON YOU' "$out"
assert_contains human-age 'H1: Approve PR (30m)' "$out"
assert_contains overseer-banner 'fixture-overseer: herdr:blocked (60m)' "$out"
assert_contains active-glyph '◐ M6 Build' "$out"
assert_contains done-glyph '✓ M1 Finished' "$out"
assert_contains nodes '◐ N1 Helper scripts [review] 60m PR #42 CI:pass' "$out"
assert_contains joined-agent 'fixture-impl herdr:working 15m tab:live-tab Implementing' "$out"
assert_contains gone-agent 'fixture-gone herdr:gone 60m tab:gone-tab' "$out"
assert_not_contains other-run 'OUTSIDER' "$out"
assert_not_contains other-run-name 'other-run-impl' "$out"
assert_not_contains unnamed-agent UNNAMED "$out"
assert_not_contains closed-agent fixture-closed "$out"
assert_not_contains no-escape $'\033' "$out"
assert_contains stale 'STALE:' "$out"
assert_contains tail-first entry-03 "$out"
assert_contains tail-last entry-10 "$out"
assert_not_contains tail-limit entry-02 "$out"
assert_not_contains non-entry 'not an entry' "$out"
# Independent width calculation: CJK/watch=2, combining acute=0.
printf '%s\n' "$out" | jq -Rs -e 'split("\n")|all(.[];
  (explode|map(if . == 30028 or . == 8986 then 2 elif . == 769 then 0 else 1 end)|add // 0) <= 80)' >/dev/null
assert_eq display-columns-80 0 "$?"
assert_eq only-allowed-lists $'herdr agent list\nherdr tab list\nherdr workspace list' "$(sort -u "$MOCK_LOG")"
# A single waiter leaves room for the compact milestone heading at 14 rows.
cp "$HERDR_SCENARIO/agents.json" "$SCRATCH/full-agents"
jq '.result.agents[1].agent_status="idle"' "$HERDR_SCENARIO/agents.json" >"$SCRATCH/compact-agents"
mv "$SCRATCH/compact-agents" "$HERDR_SCENARIO/agents.json"
compact=$("$B" "$run" --once --width 80 --height 14)
cp "$SCRATCH/full-agents" "$HERDR_SCENARIO/agents.json"
lines=$(printf '%s\n' "$compact" | wc -l | tr -d ' ')
fits=no; if [ "$lines" -le 14 ]; then fits=yes; fi
assert_eq compact-height yes "$fits"
for needle in 'RUN fixture' 'WAITING ON YOU' 'H1: Approve PR' 'MILESTONES' 'N1 Helper scripts' 'fixture-impl' 'fixture-gone' 'STALE:' 'M6 Build' 'M7 Land' '+5 done'; do
  assert_contains "compact-$needle" "$needle" "$compact"
done
assert_not_contains compact-later-milestone 'M8 Later' "$compact"
assert_not_contains compact-ledger entry- "$compact"
# Before milestone shortening, remove only the oldest ledger lines needed.
full_lines=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
trimmed=$("$B" "$run" --once --width 80 --height "$((full_lines - 2))")
assert_not_contains oldest-first entry-03 "$trimmed"
assert_not_contains second-oldest entry-04 "$trimmed"
assert_contains newest-kept entry-10 "$trimmed"
assert_contains milestones-not-yet-trimmed 'M8 Later' "$trimmed"
overflow=$("$B" "$run" --once --width 80 --height 3)
overflow_lines=$(printf '%s\n' "$overflow" | wc -l | tr -d ' ')
assert_eq overflow-indicator "($((overflow_lines - 3)) lines over height)" "$(printf '%s\n' "$overflow" | tail -n1)"
assert_contains overflow-protects-agent fixture-gone "$overflow"
jq '.herdr={workspace:"w1",cockpit_tab:"w1:t1"}' "$run/status.json" >"$SCRATCH/new-status"
mv "$SCRATCH/new-status" "$run/status.json"
echo '{"result":{"tabs":[{"tab_id":"w1:t1","label":"fixture·cockpit","workspace_id":"w1"}]}}' >"$HERDR_SCENARIO/tabs.json"
echo '{"result":{"workspaces":[{"workspace_id":"w1","label":"Fixture workspace"}]}}' >"$HERDR_SCENARIO/workspaces.json"
jq '.result.agents |= map(if .name == "fixture-impl" then .workspace_id="w2" else .workspace_id="w1" end)' "$HERDR_SCENARIO/agents.json" >"$SCRATCH/new-agents"
mv "$SCRATCH/new-agents" "$HERDR_SCENARIO/agents.json"
out=$("$B" "$run" --once --width 100)
assert_contains workspace-header 'workspace: Fixture workspace (w1)' "$out"
assert_contains cockpit-header 'cockpit: fixture·cockpit (w1:t1)' "$out"
assert_contains drift-banner 'fixture-impl is in workspace w2, run is in w1' "$out"
assert_not_contains correct-workspace-no-drift 'fixture-overseer is in workspace' "$out"
jq '.result.agents[0].agent_status="blocked"' "$HERDR_SCENARIO/agents.json" >"$SCRATCH/new-agents"
mv "$SCRATCH/new-agents" "$HERDR_SCENARIO/agents.json"
blocked=$("$B" "$run" --once --width 80)
assert_contains blocked-run-agent 'fixture-impl: herdr:blocked (15m)' "$blocked"
assert_not_contains no-working-no-stale 'STALE:' "$blocked"
rm "$HERDR_SCENARIO/agents.json"
out=$("$B" "$run" --once --width 80); assert_eq unavailable-exit 0 "$?"
assert_contains unavailable 'herdr unavailable' "$out"
assert_contains unavailable-still-renders 'N1 Helper scripts' "$out"
out=$("$B" "$SCRATCH/missing" --once --width 80); assert_eq missing-exit 0 "$?"
assert_contains missing-hint 'No status.json' "$out"
assert_eq missing-one-line 1 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
assert_eq tiny-width 5 "$("$B" "$SCRATCH/missing" --once --width 5 | tr -d '\n' | wc -c | tr -d ' ')"
assert_eq columns-env-width 7 "$(COLUMNS=7 "$B" "$SCRATCH/missing" --once | tr -d '\n' | wc -c | tr -d ' ')"
assert_eq explicit-width-wins 9 "$(COLUMNS=7 "$B" "$SCRATCH/missing" --once --width 9 | tr -d '\n' | wc -c | tr -d ' ')"
# Give stdout a real terminal while stdin remains /dev/null. BSD and GNU
# script have different command syntax; neither requires an interactive tty.
if command -v script >/dev/null && { [ "$(uname -s)" = Darwin ] || [ "$(uname -s)" = Linux ]; }; then
  BOARD_PTY_PROBE=$SCRATCH/board-pty.sh
  BOARD_PTY_BIN=$B
  export BOARD_PTY_PROBE BOARD_PTY_BIN
  cat >"$BOARD_PTY_PROBE" <<'PROBE'
#!/usr/bin/env bash
unset COLUMNS
stty rows 12 cols 37 0<&1 || exit 1
if [ -n "$BOARD_PTY_COLUMNS" ]; then export COLUMNS=$BOARD_PTY_COLUMNS; fi
set -- "$BOARD_PTY_BIN" "$BOARD_PTY_RUN" --once
if [ -n "$BOARD_PTY_WIDTH" ]; then set -- "$@" --width "$BOARD_PTY_WIDTH"; fi
if [ -n "$BOARD_PTY_HEIGHT" ]; then set -- "$@" --height "$BOARD_PTY_HEIGHT"; fi
exec "$@" </dev/null
PROBE
  pty_snapshot() {
    BOARD_PTY_RUN=$1; BOARD_PTY_COLUMNS=$2; BOARD_PTY_WIDTH=$3; BOARD_PTY_HEIGHT=$4
    export BOARD_PTY_RUN BOARD_PTY_COLUMNS BOARD_PTY_WIDTH BOARD_PTY_HEIGHT
    if [ "$(uname -s)" = Darwin ]; then
      script -q "$SCRATCH/pty.out" /bin/bash "$BOARD_PTY_PROBE" </dev/null >/dev/null 2>&1
    else
      # shellcheck disable=SC2016 # Expanded by the shell script launches.
      script -q -c '/bin/bash "$BOARD_PTY_PROBE"' "$SCRATCH/pty.out" </dev/null >/dev/null 2>&1
    fi
    # script can echo an input EOF as ^D followed by backspaces on macOS.
    tr -d '\r' <"$SCRATCH/pty.out" | sed $'s/.*\b\b//'
  }
  snapshot=$(pty_snapshot "$SCRATCH/missing" '' '' '')
  line=$(printf '%s\n' "$snapshot" | grep '^No status.json')
  assert_eq stdout-tty-measured-width 37 "${#line}"
  snapshot=$(pty_snapshot "$SCRATCH/missing" 33 '' '')
  line=$(printf '%s\n' "$snapshot" | grep '^No status.json')
  assert_eq columns-over-tty-width 33 "${#line}"
  snapshot=$(pty_snapshot "$SCRATCH/missing" 33 45 '')
  line=$(printf '%s\n' "$snapshot" | grep '^No status.json')
  assert_eq explicit-over-columns-and-tty 45 "${#line}"
  # The full fixture exceeds 12 protected rows, making measured height visible.
  snapshot=$(pty_snapshot "$run" '' '' '')
  assert_contains stdout-tty-measured-height 'lines over height)' "$snapshot"
  snapshot=$(pty_snapshot "$run" '' 80 100)
  assert_not_contains explicit-height-over-tty 'lines over height)' "$snapshot"
fi
for args in '--width 0' '--width nope' '--interval 0' '--height -1' '--stale-minutes nope' '--unknown'; do
  # shellcheck disable=SC2086
  "$B" "$run" --once $args >/dev/null 2>&1; assert_eq "usage-$args" 2 "$?"
done
app_fixture
jq '.herdr={flavor:"app",workspace:"sp1",cockpit_tab:"tb1",overseer_pane:"pa1",overseer_id:"t1"}|
 .agents += [{name:"fixture-overseer",role:"overseer",state:"open",since:"2026-11-01T11:00:00Z",pane:"pa1",tab:"tb1"}]' "$run/status.json" >"$SCRATCH/status"
mv "$SCRATCH/status" "$run/status.json"
jq '.[0].name="different-hc-name"|.[0].status={app:"fixture",state:"blocked"}|.[0].title="REAL OVERSEER"|
 . + [{address:"tspoof",agent:"fixture",name:"fixture-overseer",state:"live",reported:true,status:{app:"fixture",state:"working"},title:"SPOOF",labels:{}}]' "$HC_SCENARIO/terminals.json" >"$SCRATCH/core"
mv "$SCRATCH/core" "$HC_SCENARIO/terminals.json"
out=$("$B" "$run" --once --width 120)
assert_eq app-board-exit 0 "$?"
assert_contains app-overseer-by-id 'fixture-overseer: herdr:blocked' "$out"
assert_contains app-live-title 'REAL OVERSEER' "$out"
assert_not_contains app-impostor-excluded 'SPOOF' "$out"
assert_not_contains app-impostor-no-stale 'STALE:' "$out"
assert_contains app-space-header 'workspace: old space (sp1)' "$out"
assert_not_contains app-no-transcript 'hc read ' "$(cat "$MOCK_LOG")"
finish
