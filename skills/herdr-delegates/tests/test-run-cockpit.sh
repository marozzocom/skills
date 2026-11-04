#!/usr/bin/env bash
# Mock-only setup, ownership naming, board reuse and shell-quoted paths.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
C="$BIN_DIR/run-cockpit.sh"
S="$BIN_DIR/../../implementation-orchestration/bin/status-set.sh"
export HERDR_WORKSPACE_ID=w1 HERDR_TAB_ID=w1:t1 HERDR_PANE_ID=w1:p1
export STATUS_NOW=2026-11-01T10:00:00Z
fixture() {
  run=$SCRATCH/$1; mkdir "$run"
  "$S" "$run" init fixture fixture 'Make cockpit' >/dev/null
  echo '{"result":{"agents":[{"pane_id":"w1:p1","workspace_id":"w1","tab_id":"w1:t1"}]}}' >"$HERDR_SCENARIO/agents.json"
  echo '{"result":{"tabs":[{"tab_id":"w1:t1","workspace_id":"w1","label":"old"},{"tab_id":"w2:t1","workspace_id":"w2","label":"unrelated"}]}}' >"$HERDR_SCENARIO/tabs.json"
  echo '{"result":{"workspaces":[{"workspace_id":"w1","label":"old workspace"}]}}' >"$HERDR_SCENARIO/workspaces.json"
  echo '{"result":{"layout":{"focused_pane_id":"w1:p1","panes":[{"pane_id":"w1:p1","rect":{"width":158,"height":71}}]}}}' >"$HERDR_SCENARIO/layout.json"
  : >"$MOCK_LOG"
}
fixture 'run with spaces'
# Copy the helpers to a space-containing installation path as well.
tools=$SCRATCH/tools\ with\ spaces
mkdir -p "$tools/herdr-delegates/bin" "$tools/implementation-orchestration/bin"
cp "$C" "$BIN_DIR/run-board.sh" "$BIN_DIR/herdr-backend.sh" "$tools/herdr-delegates/bin/"
cp "$S" "$tools/implementation-orchestration/bin/"
C=$tools/herdr-delegates/bin/run-cockpit.sh
out=$("$C" "$run"); assert_eq setup-exit 0 "$?"
assert_contains agent-action 'agent named fixture-overseer' "$out"
assert_contains tab-action 'tab named fixture·cockpit' "$out"
assert_contains workspace-action 'workspace named fixture (was old workspace)' "$out"
assert_contains board-action 'board opened in w1:pboard' "$out"
assert_contains no-focus 'pane split w1:p1 --direction down --ratio 0.65' "$(cat "$MOCK_LOG")"
assert_contains no-focus-flag --no-focus "$(cat "$MOCK_LOG")"
assert_eq meta '{"board_pane":"w1:pboard","workspace":"w1","cockpit_tab":"w1:t1","overseer_pane":"w1:p1","flavor":"tui"}' "$(jq -c .herdr "$run/status.json")"
assert_eq overseer-registration 'fixture-overseer|overseer|direct|w1:p1|w1:t1|open' "$(jq -r '.agents[0]|[.name,.role,.transport,.pane,.tab,.state]|join("|")' "$run/status.json")"
command=$(cat "$HERDR_SCENARIO/run-command.txt")
# Parse the second shell exactly as pane run does, without running the board.
eval "set -- $command"
assert_eq quoted-operands 2 "$#"
assert_eq quoted-script "$tools/herdr-delegates/bin/run-board.sh" "$1"
assert_eq quoted-run "$run" "$2"
cp "$run/status.json" "$SCRATCH/first-status"
cp "$run/ledger.md" "$SCRATCH/first-ledger"
: >"$MOCK_LOG"
export STATUS_NOW=2026-11-01T11:00:00Z
out=$("$C" "$run"); assert_eq rerun-exit 0 "$?"
assert_eq rerun-noop $'board reused in w1:pboard\ncockpit unchanged' "$out"
cmp -s "$SCRATCH/first-status" "$run/status.json"; assert_eq no-status-write-on-rerun 0 "$?"
cmp -s "$SCRATCH/first-ledger" "$run/ledger.md"; assert_eq no-ledger-write-on-rerun 0 "$?"
assert_eq no-rerun-mutations 0 "$(grep -Ec 'rename|split|pane run' "$MOCK_LOG")"
assert_eq exactly-one-overseer 1 "$(jq '[.agents[]|select(.name=="fixture-overseer")]|length' "$run/status.json")"
# --no-board sets up a cockpit without asking for layout/split/run.
fixture own-only
jq '.result.tabs += [{tab_id:"w1:t2",workspace_id:"w1",label:"fixture·N1"}]' "$HERDR_SCENARIO/tabs.json" >"$SCRATCH/tabs"
mv "$SCRATCH/tabs" "$HERDR_SCENARIO/tabs.json"
out=$("$C" "$run" --no-board)
assert_contains own-only-renames 'workspace named fixture' "$out"
assert_eq no-board-empty '' "$(jq -r .herdr.board_pane "$run/status.json")"
assert_eq no-board-calls 0 "$(grep -Ec 'pane layout|pane split|pane run' "$MOCK_LOG")"
assert_eq no-board-overseer open "$(jq -r '.agents[0].state' "$run/status.json")"
fixture shared
jq '.result.tabs += [{tab_id:"w1:t2",workspace_id:"w1",label:"another-run·N1"}]' "$HERDR_SCENARIO/tabs.json" >"$SCRATCH/tabs"
mv "$SCRATCH/tabs" "$HERDR_SCENARIO/tabs.json"
out=$("$C" "$run" --no-board)
assert_contains shared-message 'workspace unchanged: shared with other runs' "$out"
assert_eq shared-name-preserved 'old workspace' "$(jq -r '.result.workspaces[0].label' "$HERDR_SCENARIO/workspaces.json")"
assert_eq no-shared-rename 0 "$(grep -c 'workspace rename' "$MOCK_LOG")"
# A recorded but closed board is replaced; a live one was reused above.
fixture recreate
"$S" "$run" meta board_pane=w1:pclosed >/dev/null
out=$("$C" "$run" --board-ratio 0.7)
assert_contains board-replaced 'board opened in w1:pboard' "$out"
assert_contains custom-ratio '--ratio 0.7' "$(cat "$MOCK_LOG")"
HERDR_PANE_ID='' "$C" "$run" --no-board >/dev/null 2>&1; assert_eq missing-env 1 "$?"
HERDR_WORKSPACE_ID=w2 "$C" "$run" --no-board >/dev/null 2>&1; assert_eq wrong-workspace 1 "$?"
for args in '--board-ratio 0' '--board-ratio 1' '--board-ratio bad' '--unknown'; do
  # shellcheck disable=SC2086
  "$C" "$run" $args >/dev/null 2>&1; assert_eq "usage-$args" 2 "$?"
done
app_fixture
C=$BIN_DIR/run-cockpit.sh
run=$SCRATCH/app-run; mkdir "$run"
"$S" "$run" init app-run fixture 'App cockpit' >/dev/null
out=$("$C" "$run"); assert_eq app-setup 0 "$?"
assert_contains app-board-opened 'board opened in pboard' "$out"
assert_eq app-meta 'app|t1|pa1|tb1|sp1|pboard' "$(jq -r '.herdr|[.flavor,.overseer_id,.overseer_pane,.cockpit_tab,.workspace,.board_pane]|join("|")' "$run/status.json")"
assert_contains app-label 'hc label t1 run.name=fixture-overseer run.prefix=fixture run.role=overseer' "$(cat "$MOCK_LOG")"
cp "$run/status.json" "$SCRATCH/app-first-status"
: >"$MOCK_LOG"
out=$("$C" "$run"); assert_eq app-rerun 0 "$?"
assert_eq app-unchanged $'board reused in pboard\ncockpit unchanged' "$out"
cmp -s "$run/status.json" "$SCRATCH/app-first-status"; assert_eq app-no-status-write 0 "$?"
assert_eq app-no-rerun-mutations 0 "$(grep -Ec 'do |hc label|hc run ' "$MOCK_LOG")"
assert_not_contains app-no-tui 'herdr agent' "$(cat "$MOCK_LOG")"
finish
