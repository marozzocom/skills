#!/usr/bin/env bash
# run-cockpit.sh RUN_DIR [--board-ratio R=0.65] [--no-board]
# Run in the overseer's shell with HERDR_PANE_ID/TAB_ID/WORKSPACE_ID. Names
# its agent/tab, names an exclusively owned workspace, opens a board below,
# and registers the overseer and Herdr metadata through status-set.sh.
# A live recorded board is reused. No-op reruns leave status timestamps alone.
# Exit: 0 one line per action (or unchanged), 1 setup failure, 2 usage.
set -euo pipefail
trap 'exit 1' ERR
usage() { echo "usage: run-cockpit.sh RUN_DIR [--board-ratio R] [--no-board]" >&2; exit 2; }
fail() { echo "ERROR: $*" >&2; exit 1; }
[ $# -ge 1 ] || usage
run=$1; shift; ratio=0.65; no_board=0
while [ $# -gt 0 ]; do
  case $1 in
    --no-board) no_board=1; shift ;;
    --board-ratio) [ $# -ge 2 ] || usage; ratio=$2; shift 2 ;;
    *) usage ;;
  esac
done
jq -en --arg r "$ratio" '$r|tonumber|select(. > 0 and . < 1)' >/dev/null 2>&1 || usage
[ -n "${HERDR_PANE_ID:-}" ] && [ -n "${HERDR_TAB_ID:-}" ] && [ -n "${HERDR_WORKSPACE_ID:-}" ] ||
  fail "run from the overseer shell with HERDR_PANE_ID, HERDR_TAB_ID and HERDR_WORKSPACE_ID"
here=$(cd "$(dirname "$0")" && pwd)
setter=$here/../../implementation-orchestration/bin/status-set.sh
[ -x "$setter" ] || fail "status-set.sh unavailable: $setter"
run=$(cd "$run" && pwd) || fail "run directory unavailable"
status=$run/status.json
prefix=$(jq -er '.prefix | strings | select(length > 0)' "$status") || fail "status.json prefix missing"
recorded_workspace=$(jq -r '.herdr.workspace // ""' "$status")
[ -z "$recorded_workspace" ] || [ "$recorded_workspace" = "$HERDR_WORKSPACE_ID" ] ||
  fail "run is in workspace $recorded_workspace, caller is in $HERDR_WORKSPACE_ID"
agents=$(herdr agent list) || fail "herdr agent list failed"
tabs=$(herdr tab list) || fail "herdr tab list failed"
workspaces=$(herdr workspace list) || fail "herdr workspace list failed"
jq -e --arg tab "$HERDR_TAB_ID" --arg ws "$HERDR_WORKSPACE_ID" \
  'any(.result.tabs[]; .tab_id == $tab and .workspace_id == $ws)' <<<"$tabs" >/dev/null || fail "caller tab not in caller workspace"
name=$prefix-overseer; label=${prefix}·cockpit; changed=0
current_name=$(jq -r --arg p "$HERDR_PANE_ID" '[.result.agents[]|select(.pane_id == $p)][0].name // ""' <<<"$agents")
if [ "$current_name" != "$name" ]; then
  herdr agent rename "$HERDR_PANE_ID" "$name" >/dev/null || fail "agent rename failed"
  echo "agent named $name"; changed=1
fi
current_label=$(jq -r --arg t "$HERDR_TAB_ID" '[.result.tabs[]|select(.tab_id == $t)][0].label // ""' <<<"$tabs")
if [ "$current_label" != "$label" ]; then
  herdr tab rename "$HERDR_TAB_ID" "$label" >/dev/null || fail "tab rename failed"
  echo "tab named $label"; changed=1
fi
own=$(jq -r --arg t "$HERDR_TAB_ID" --arg ws "$HERDR_WORKSPACE_ID" --arg ns "${prefix}·" '
  [.result.tabs[]|select(.workspace_id == $ws)] |
  all(.[]; .tab_id == $t or ((.label // "")|startswith($ns)))' <<<"$tabs")
workspace_label=$(jq -r --arg w "$HERDR_WORKSPACE_ID" '[.result.workspaces[]|select(.workspace_id == $w)][0].label // ""' <<<"$workspaces")
if [ "$own" = true ]; then
  if [ "$workspace_label" != "$prefix" ]; then
    herdr workspace rename "$HERDR_WORKSPACE_ID" "$prefix" >/dev/null || fail "workspace rename failed"
    echo "workspace named $prefix (was $workspace_label)"; changed=1
  fi
else echo "workspace unchanged: shared with other runs"; fi
board=$(jq -r '.herdr.board_pane // ""' "$status")
if [ "$no_board" = 0 ]; then
  live=false
  if [ -n "$board" ]; then
    layout=$(herdr pane layout --pane "$board" 2>/dev/null) || layout='{}'
    if jq -e --arg p "$board" 'any(.result.layout.panes[]?; .pane_id == $p)' <<<"$layout" >/dev/null; then live=true; fi
  fi
  if [ "$live" = false ]; then
    split=$(herdr pane split "$HERDR_PANE_ID" --direction down --ratio "$ratio" --cwd "$run" --no-focus) || fail "board split failed"
    board=$(jq -er '.result.pane.pane_id | strings | select(length > 0)' <<<"$split") || fail "split did not return pane_id"
    # Record a successful split immediately so a later failure cannot cause
    # a duplicate board pane on retry. Both command operands cross a shell.
    "$setter" "$run" meta "board_pane=$board" >/dev/null
    printf -v board_command '%q %q' "$here/run-board.sh" "$run"
    herdr pane run "$board" "$board_command" >/dev/null || fail "board command failed"
    echo "board opened in $board"; changed=1
  else echo "board reused in $board"; fi
fi
if ! jq -e --arg name "$name" --arg pane "$HERDR_PANE_ID" --arg tab "$HERDR_TAB_ID" '
  any(.agents[]; .name == $name and .role == "overseer" and .transport == "direct" and .pane == $pane and .tab == $tab and .state == "open")' "$status" >/dev/null; then
  "$setter" "$run" agent "$name" role=overseer transport=direct "pane=$HERDR_PANE_ID" "tab=$HERDR_TAB_ID" state=open >/dev/null
  echo "overseer registered: $name"; changed=1
fi
if ! jq -e --arg ws "$HERDR_WORKSPACE_ID" --arg tab "$HERDR_TAB_ID" --arg pane "$HERDR_PANE_ID" --arg board "$board" '
  .herdr.workspace == $ws and .herdr.cockpit_tab == $tab and .herdr.overseer_pane == $pane and .herdr.board_pane == $board' "$status" >/dev/null; then
  "$setter" "$run" meta "workspace=$HERDR_WORKSPACE_ID" "cockpit_tab=$HERDR_TAB_ID" "overseer_pane=$HERDR_PANE_ID" "board_pane=$board" >/dev/null
  echo "run metadata recorded"; changed=1
fi
if [ "$changed" = 0 ]; then echo "cockpit unchanged"; fi
