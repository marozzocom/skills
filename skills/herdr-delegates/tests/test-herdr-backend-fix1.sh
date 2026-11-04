#!/usr/bin/env bash
# Adjudicated regressions; N2_FIX_CASE selects a group for mutation checks.
# The historical parking group now tests the same guards for root disposal.
. "$(dirname "$0")/lib.sh"
H=$BIN_DIR/herdr-backend.sh
rewrite_core() { jq "$1" "$HC_SCENARIO/terminals.json" >"$SCRATCH/core"; mv "$SCRATCH/core" "$HC_SCENARIO/terminals.json"; }
rotation() {
  app_fixture
  rewrite_core '.[0].name="worker"'
  mkdir -p "$SCRATCH/physical worktree"
  ln -s "$SCRATCH/physical worktree" "$SCRATCH/worktree-link"
  out=$(cd "$SCRATCH" && "$H" rotate worker stale-pane worktree-link tool -- --model pinned --effort high)
  assert_eq rotate-by-name-exit 0 "$?"
  assert_eq rotate-new-address tnew1 "$out"
  assert_eq rotate-physical-cwd "$(cd "$SCRATCH/physical worktree" && pwd -P)" "$(jq -r '.[]|select(.address=="tnew1")|.cwd' "$HC_SCENARIO/terminals.json")"
  assert_eq rotate-same-name worker "$(jq -r '.[]|select(.address=="tnew1")|.name' "$HC_SCENARIO/terminals.json")"
  assert_contains rotate-pin '--label herdr.space=sp1 --label herdr.tab=tb1 -- tool --model pinned --effort high' "$(cat "$MOCK_LOG")"
  assert_eq rotate-retires-old 'tnew1' "$(jq -r '.[].address' "$HC_SCENARIO/terminals.json")"
  # The core fixture independently rejects a live duplicate and frees a killed name.
  hc run --bg --name worker --cwd "$SCRATCH" -- tool >"$SCRATCH/out" 2>"$SCRATCH/err"
  assert_eq stub-live-name-unique 1 "$?"
  assert_eq stub-name-taken-json name_taken "$(jq -r '.error.kind' "$SCRATCH/err")"
  hc kill tnew1 >/dev/null; hc rm tnew1 >/dev/null
  hc run --bg --name worker --cwd "$SCRATCH" -- tool >/dev/null
  assert_eq stub-name-freed 0 "$?"
}
board_argv() {
  app_fixture
  run=$SCRATCH/board\ run; mkdir "$run"
  out=$("$H" open-board "$run" 0.65)
  assert_eq board-created pboard "$out"
  expected=$(jq -cn --arg s "$BIN_DIR/run-board.sh" --arg r "$run" '[$s,$r]')
  assert_eq board-exact-argv "$expected" "$(jq -c . "$APP_SCENARIO/pane-split-argv.json")"
}
board_gate() {
  app_fixture
  run=$SCRATCH/board-gate; mkdir "$run"
  echo '{"run_id":"fixture","prefix":"fixture","goal":"Gate","herdr":{"flavor":"tui"},"agents":[],"waiting_on_human":[],"nodes":[],"milestones":[]}' >"$run/status.json"
  out=$("$BIN_DIR/run-board.sh" "$run" --once 2>"$SCRATCH/err")
  assert_eq board-startup-mismatch 1 "$?"
  assert_eq board-mismatch-no-frame '' "$out"
  assert_contains board-mismatch-reason 'Herdr flavor mismatch' "$(cat "$SCRATCH/err")"
  assert_eq board-mismatch-no-cli '' "$(cat "$MOCK_LOG")"
}
close_pane() {
  app_fixture
  "$H" close pa1 2>"$SCRATCH/err"
  assert_eq close-by-pane-exit 0 "$?"
  assert_eq close-by-pane-removed '[]' "$(jq -c . "$HC_SCENARIO/terminals.json")"
  assert_contains close-pane-resolved-kill 'hc kill t1' "$(cat "$MOCK_LOG")"
  assert_contains close-pane-resolved-rm 'hc rm t1' "$(cat "$MOCK_LOG")"
}
parking_case() {
  local guard=$1 filter=$2 expected=$3
  if [ -n "${N2_PARK_GUARD:-}" ] && [ "$N2_PARK_GUARD" != "$guard" ]; then return; fi
  app_fixture
  "$H" tab-new sp1 parking "$SCRATCH" >/dev/null
  rewrite_core '.[1].foreground={name:"zsh",argv:["/bin/zsh","-l"]}'
  rewrite_core ".[1] |= ($filter)"
  out=$("$H" start worker tool "$SCRATCH" --tab tbnew1 --space sp1 --timeout 2 --)
  assert_eq "parking-$guard-start" 0 "$?"
  assert_eq "parking-$guard-address" tnew1 "$out"
  assert_eq "parking-$guard-guard" "$expected" "$(grep -c '^hc kill roottbnew1$' "$MOCK_LOG")"
}
parking() {
  parking_case positive '.' 1
  parking_case state '.state="finished"' 0
  parking_case name '.name="named-root"' 0
  parking_case reported '.reported=true' 0
  parking_case status '.status={app:"fixture",state:"idle"}' 0
  parking_case argv '.argv=["python3","job.py"]' 0
  parking_case foreground-present 'del(.foreground)' 0
  parking_case foreground-shell '.foreground.name="python3"' 0
}
exit_codes() {
  app_fixture
  echo 3 >"$HC_SCENARIO/run.exit"
  "$H" start worker tool "$SCRATCH" --tab tb1 --space sp1 --timeout 1 -- >/dev/null 2>&1
  assert_eq runtime-in-start-function-is-one 1 "$?"
  rm "$HC_SCENARIO/run.exit"
  echo 3 >"$HC_SCENARIO/get.exit"
  "$H" geometry >/dev/null 2>&1; assert_eq runtime-get-code-is-one 1 "$?"
  rm "$HC_SCENARIO/get.exit"
  echo 'bad json' >"$APP_SCENARIO/ls.json"
  "$H" self >/dev/null 2>&1; assert_eq runtime-jq-in-function-is-one 1 "$?"
}
cleanup_case() {
  local label=$1 mode=$2
  app_fixture
  case $mode in
    silent) echo null >"$HC_SCENARIO/run-status.json" ;;
    blocked|error) printf '{"app":"fixture","state":"%s"}\n' "$mode" >"$HC_SCENARIO/run-status.json" ;;
    adoption) touch "$HC_SCENARIO/no-adoption" ;;
    get-failure) echo '{"tnew1":3}' >"$HC_SCENARIO/get-errors.json" ;;
  esac
  out=$("$H" start worker tool "$SCRATCH" --tab tb1 --space sp1 --timeout 1 -- 2>"$SCRATCH/err")
  assert_eq "cleanup-$label-failure" 1 "$?"
  assert_eq "cleanup-$label-no-id" '' "$out"
  assert_contains "cleanup-$label-kill" 'hc kill tnew1' "$(cat "$MOCK_LOG")"
  assert_contains "cleanup-$label-rm" 'hc rm tnew1' "$(cat "$MOCK_LOG")"
  assert_eq "cleanup-$label-only-new-terminal" t1 "$(jq -r '.[].address' "$HC_SCENARIO/terminals.json")"
  assert_contains "cleanup-$label-reason" worker "$(cat "$SCRATCH/err")"
}
cleanup() {
  cleanup_case unreported silent
  cleanup_case blocked blocked
  cleanup_case error error
  cleanup_case adoption adoption
  cleanup_case runtime get-failure
}
listing_races() {
  app_fixture
  rewrite_core '.[0].labels["run.prefix"]="survivor" | . + [{address:"vanished",name:"gone",agent:"fixture",state:"live",labels:{"run.prefix":"stale"},reported:true,status:{app:"fixture",state:"idle"}}]'
  echo '{"vanished":3}' >"$HC_SCENARIO/get-errors.json"
  out=$("$H" agents 2>"$SCRATCH/err"); assert_eq agents-not-found-skipped 0 "$?"
  assert_eq agents-survivor-only '["t1"]' "$(jq -c '[.[].id]' <<<"$out")"
  out=$("$H" prefixes 2>"$SCRATCH/err"); assert_eq prefixes-not-found-skipped 0 "$?"
  assert_eq prefixes-survivor-only '["survivor"]' "$out"
  echo '{"vanished":4}' >"$HC_SCENARIO/get-errors.json"
  "$H" agents >/dev/null 2>&1; assert_eq agents-other-error-fatal 1 "$?"
  "$H" prefixes >/dev/null 2>&1; assert_eq prefixes-other-error-fatal 1 "$?"
  assert_eq panes-cwd-from-core /tmp/own-worktree "$("$H" panes | jq -r '.[0].cwd')"
}
wait_reasons() {
  app_fixture
  for reason in timeout message not_started; do
    jq -n --arg reason "$reason" '{ended:false,reason:$reason,status:"idle",turn:1}' >"$HC_SCENARIO/wait.json"
    out=$("$H" wait t1 1)
    assert_eq "wait-$reason-exit" 1 "$?"
    assert_eq "wait-$reason-stdout" "$reason" "$out"
  done
  echo '{"ended":true,"reason":"status","status":"done","turn":1}' >"$HC_SCENARIO/wait.json"
  out=$("$H" wait t1 1); assert_eq wait-ended-exit 0 "$?"
  assert_eq wait-ended-status done "$out"
}
tui_messages() {
  export HERDR_ENV=1 HERDR_PANE_ID=w1:p1 HERDR_TAB_ID=w1:t1 HERDR_WORKSPACE_ID=w1
  unset HC_TERMINAL_ID HERDR_BACKEND_RUN_DIR
  run=$SCRATCH/tui-messages; mkdir "$run"
  echo '{"prefix":"fixture","herdr":{},"agents":[]}' >"$run/status.json"
  echo '{"result":{"agents":[{"name":"fixture-overseer","pane_id":"w1:p1"}]}}' >"$HERDR_SCENARIO/agents.json"
  echo '{"result":{"tabs":[{"tab_id":"w1:t1","workspace_id":"w1","label":"fixture·cockpit"}]}}' >"$HERDR_SCENARIO/tabs.json"
  echo '{"result":{"workspaces":[{"workspace_id":"w1","label":"fixture"}]}}' >"$HERDR_SCENARIO/workspaces.json"
  out=$(HERDR_PANE_ID='' "$BIN_DIR/run-cockpit.sh" "$run" 2>&1)
  assert_eq tui-missing-env-original 'ERROR: run from the overseer shell with HERDR_PANE_ID, HERDR_TAB_ID and HERDR_WORKSPACE_ID' "$out"
  echo 1 >"$HERDR_SCENARIO/tab-create.exit"
  # Setup first so this reaches the create failure, not a missing workspace.
  "$BIN_DIR/../../implementation-orchestration/bin/status-set.sh" "$run" meta workspace=w1 >/dev/null
  out=$("$BIN_DIR/run-tab.sh" "$run" N1 "$SCRATCH" 2>&1)
  assert_eq tui-tab-create-original 'ERROR: tab create failed' "$out"
  rm "$HERDR_SCENARIO/tab-create.exit"
  echo 1 >"$HERDR_SCENARIO/pane-split.exit"
  out=$("$BIN_DIR/run-cockpit.sh" "$run" 2>&1)
  assert_eq tui-board-split-original 'ERROR: board split failed' "$out"
  rm "$HERDR_SCENARIO/pane-split.exit"
  echo '{}' >"$HERDR_SCENARIO/split.json"
  echo '{"result":{"layout":{"panes":[]}}}' >"$HERDR_SCENARIO/layout.json"
  out=$("$BIN_DIR/run-cockpit.sh" "$run" 2>&1)
  assert_eq tui-board-id-original 'ERROR: split did not return pane_id' "$out"
  echo '{"result":{"pane":{"pane_id":"w1:pboard"}}}' >"$HERDR_SCENARIO/split.json"
  echo 1 >"$HERDR_SCENARIO/pane-run.exit"
  out=$("$BIN_DIR/run-cockpit.sh" "$run" 2>&1)
  assert_eq tui-board-run-original 'ERROR: board command failed' "$out"
}
warning_once() {
  app_fixture
  rewrite_core '.[0].name="worker"'
  "$H" rotate worker ignored "$SCRATCH" tool -- >/dev/null 2>"$SCRATCH/err"
  assert_eq app-one-no-pin-warning 1 "$(grep -c '^warning: no native agent args' "$SCRATCH/err")"
  export HERDR_ENV=1
  echo '{"result":{"agents":[]}}' >"$HERDR_SCENARIO/agents.json"
  jq -n --arg cwd "$(cd "$SCRATCH" && pwd -P)" '{result:{pane:{foreground_cwd:$cwd}}}' >"$HERDR_SCENARIO/pane-get.json"
  "$H" rotate worker w1:p1 "$SCRATCH" tool -- >/dev/null 2>"$SCRATCH/err"
  assert_eq tui-one-no-pin-warning 1 "$(grep -c '^warning: no native agent args' "$SCRATCH/err")"
}
for group in rotation board_argv board_gate close_pane parking exit_codes cleanup listing_races wait_reasons tui_messages warning_once; do
  if [ -z "${N2_FIX_CASE:-}" ] || [ "$N2_FIX_CASE" = "$group" ]; then "$group"; fi
done
finish
