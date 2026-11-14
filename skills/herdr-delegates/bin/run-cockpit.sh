#!/usr/bin/env bash
# run-cockpit.sh RUN_DIR [--board-ratio R=0.65] [--no-board]
# Run in the overseer's shell with HERDR_PANE_ID/TAB_ID/WORKSPACE_ID. Names
# its agent/tab, names an exclusively owned workspace, opens a board below,
# and registers the overseer and Herdr metadata through status-set.sh.
# The workspace is named for the human: the run id without its leading
# YYYY-MM-DD- (the prefix when that leaves nothing). Agents and tabs keep
# the short prefix.
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
here=$(cd "$(dirname "$0")" && pwd)
backend=$here/herdr-backend.sh
export HERDR_BACKEND_RUN_DIR=$run
flavor=$("$backend" flavor "$run") || exit 1
caller=$("$backend" self) || fail "caller unavailable"
caller_id=$(jq -r .id <<<"$caller")
caller_pane=$(jq -r '.pane // ""' <<<"$caller")
caller_tab=$(jq -r '.tab // ""' <<<"$caller")
caller_space=$(jq -r '.space // ""' <<<"$caller")
[ -n "$caller_id" ] && [ -n "$caller_tab" ] && [ -n "$caller_space" ] ||
  { if [ "$flavor" = tui ]; then fail "run from the overseer shell with HERDR_PANE_ID, HERDR_TAB_ID and HERDR_WORKSPACE_ID"
    else fail "run from the overseer shell with a caller tab and workspace"; fi; }
setter=$here/../../implementation-orchestration/bin/status-set.sh
[ -x "$setter" ] || fail "status-set.sh unavailable: $setter"
run=$(cd "$run" && pwd) || fail "run directory unavailable"
status=$run/status.json
prefix=$(jq -er '.prefix | strings | select(length > 0)' "$status") || fail "status.json prefix missing"
space_label=$(jq -r '.run_id // "" | sub("^[0-9]{4}-[0-9]{2}-[0-9]{2}-"; "")' "$status")
[ -n "$space_label" ] || space_label=$prefix
recorded_workspace=$(jq -r '.herdr.workspace // ""' "$status")
[ -z "$recorded_workspace" ] || [ "$recorded_workspace" = "$caller_space" ] ||
  fail "run is in workspace $recorded_workspace, caller is in $caller_space"
agents=$("$backend" agents) || fail "herdr agent list failed"
tabs=$("$backend" tabs) || fail "herdr tab list failed"
workspaces=$("$backend" spaces) || fail "herdr workspace list failed"
jq -e --arg tab "$caller_tab" --arg ws "$caller_space" \
  'any(.[]; .id == $tab and .space == $ws)' <<<"$tabs" >/dev/null || fail "caller tab not in caller workspace"
name=$prefix-overseer; label=${prefix}·cockpit; changed=0
current_name=$(jq -r --arg p "$caller_pane" '[.[]|select(.pane == $p)][0].name // ""' <<<"$agents")
# hc names are immutable; an existing app registration proves our label setup.
if [ "$flavor" = app ] && [ "$(jq -r '.herdr.overseer_id // ""' "$status")" = "$caller_id" ]; then current_name=$name; fi
if [ "$current_name" != "$name" ]; then
  "$backend" rename-self "$name" >/dev/null || fail "agent rename failed"
  echo "agent named $name"; changed=1
fi
current_label=$(jq -r --arg t "$caller_tab" '[.[]|select(.id == $t)][0].label // ""' <<<"$tabs")
if [ "$current_label" != "$label" ]; then
  "$backend" rename-tab "$caller_tab" "$label" >/dev/null || fail "tab rename failed"
  echo "tab named $label"; changed=1
fi
own=$(jq -r --arg t "$caller_tab" --arg ws "$caller_space" --arg ns "${prefix}·" '
  [.[]|select(.space == $ws)] |
  all(.[]; .id == $t or ((.label // "")|startswith($ns)))' <<<"$tabs")
workspace_label=$(jq -r --arg w "$caller_space" '[.[]|select(.id == $w)][0].label // ""' <<<"$workspaces")
if [ "$own" = true ]; then
  if [ "$workspace_label" != "$space_label" ]; then
    "$backend" rename-space "$caller_space" "$space_label" >/dev/null || fail "workspace rename failed"
    echo "workspace named $space_label (was $workspace_label)"; changed=1
  fi
else echo "workspace unchanged: shared with other runs"; fi
board=$(jq -r '.herdr.board_pane // ""' "$status")
if [ "$no_board" = 0 ]; then
  live=false
  if [ -n "$board" ]; then
    if "$backend" geometry "$board" >/dev/null 2>&1; then live=true; fi
  fi
  if [ "$live" = false ]; then
    board=$("$backend" open-board "$run" "$ratio") || exit 1
    if [ "$flavor" = app ]; then "$setter" "$run" meta "board_pane=$board" >/dev/null; fi
    echo "board opened in $board"; changed=1
  else echo "board reused in $board"; fi
fi
if ! jq -e --arg name "$name" --arg pane "$caller_pane" --arg tab "$caller_tab" '
  any(.agents[]; .name == $name and .role == "overseer" and .transport == "direct" and .pane == $pane and .tab == $tab and .state == "open")' "$status" >/dev/null; then
  "$setter" "$run" agent "$name" role=overseer transport=direct "pane=$caller_pane" "tab=$caller_tab" state=open >/dev/null
  echo "overseer registered: $name"; changed=1
fi
if ! jq -e --arg ws "$caller_space" --arg tab "$caller_tab" --arg pane "$caller_pane" --arg board "$board" --arg flavor "$flavor" '
  .herdr.workspace == $ws and .herdr.cockpit_tab == $tab and .herdr.overseer_pane == $pane and .herdr.board_pane == $board and .herdr.flavor == $flavor' "$status" >/dev/null; then
  "$setter" "$run" meta "workspace=$caller_space" "cockpit_tab=$caller_tab" "overseer_pane=$caller_pane" "board_pane=$board" "flavor=$flavor" >/dev/null
  echo "run metadata recorded"; changed=1
fi
if [ "$flavor" = app ] && [ "$(jq -r '.herdr.overseer_id // ""' "$status")" != "$caller_id" ]; then
  "$setter" "$run" meta "overseer_id=$caller_id" >/dev/null
  changed=1
fi
if [ "$changed" = 0 ]; then echo "cockpit unchanged"; fi
