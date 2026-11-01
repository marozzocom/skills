#!/usr/bin/env bash
# run-board.sh RUN_DIR [--once] [--interval S=15] [--stale-minutes M=20]
#                     [--width N] [--height N]
# Reads status.json, ledger.md, herdr agent/tab/workspace list; jq renders each
# frame. Width: --width, COLUMNS, tty columns, 100. Height: --height, tty rows,
# otherwise unlimited. Tty size is measured per frame with stty size.
# Trim oldest ledger entries, then summarize milestones;
# protected sections can exceed a height too small to contain them.
# STATUS_NOW=UTC-ISO overrides the clock for deterministic snapshots/tests.
# --once emits plain text (no escapes). Looping tty output hides/restores
# the cursor and redraws with cursor-home, per-line erase, and erase-to-end.
# Exit: 0 --once, 1 render/read failure, 2 usage.
set -euo pipefail
trap 'exit 1' ERR
usage() { echo "usage: run-board.sh RUN_DIR [--once] [--interval S] [--stale-minutes M] [--width N] [--height N]" >&2; exit 2; }
[ $# -ge 1 ] || usage
run=$1; shift
once=0; interval=15; stale=20; width=100; height=0; width_set=0; height_set=0
while [ $# -gt 0 ]; do
  case $1 in
    --once) once=1; shift ;;
    --interval|--stale-minutes|--width|--height)
      [ $# -ge 2 ] || usage
      case $1 in --interval) interval=$2 ;; --stale-minutes) stale=$2 ;; --width) width=$2; width_set=1 ;; --height) height=$2; height_set=1 ;; esac
      shift 2 ;;
    *) usage ;;
  esac
done
for n in "$width" "$height" "$stale"; do case $n in ''|*[!0-9]*) usage ;; esac; done
[ "$width" -gt 0 ] || usage
[[ $interval =~ ^[0-9]+([.][0-9]+)?$ ]] || usage
jq -en --arg s "$interval" '$s|tonumber|select(. > 0)' >/dev/null || usage
if [ -n "${STATUS_NOW:-}" ]; then
  jq -en --arg s "$STATUS_NOW" '$s|fromdateiso8601' >/dev/null 2>&1 || usage
fi
tty_loop=0
if [ "$once" = 0 ] && [ -t 1 ]; then tty_loop=1; printf '\033[?25l'; fi
cleanup() { if [ "$tty_loop" = 1 ]; then printf '\033[0m\033[?25h'; fi; }
trap cleanup EXIT
trap 'exit 0' HUP INT TERM
measure_size() {
  local size rows=0 cols=100
  if [ -t 1 ]; then
    size=$(stty size 2>/dev/null </dev/tty) || size=''
    if [[ $size =~ ^[[:space:]]*([0-9]+)[[:space:]]+([0-9]+)[[:space:]]*$ ]]; then
      rows=${BASH_REMATCH[1]}; cols=${BASH_REMATCH[2]}
      [ "$cols" -gt 0 ] || cols=100
    fi
  fi
  if [ "$width_set" = 0 ]; then width=${COLUMNS:-$cols}; fi
  if [ "$height_set" = 0 ]; then height=$rows; fi
  for n in "$width" "$height"; do case $n in ''|*[!0-9]*) usage ;; esac; done
  [ "$width" -gt 0 ] || usage
}
frame() {
  local agents available ledger mtime tabs workspaces
  if [ ! -f "$run/status.json" ]; then
    jq -nr --argjson w "$width" \
      '"No status.json; use status-set.sh RUN_DIR init RUN_ID PREFIX GOAL" | .[:$w]'
    return
  fi
  available=true
  agents=$(herdr agent list 2>/dev/null) || available=false
  if ! printf '%s' "$agents" | jq -e '.result.agents | type == "array"' >/dev/null 2>&1; then
    available=false
  fi
  # Keep a valid empty response even when herdr is absent or malformed.
  if [ "$available" = false ]; then agents='{"result":{"agents":[]}}'; fi
  tabs=$(herdr tab list 2>/dev/null) || tabs='{}'
  workspaces=$(herdr workspace list 2>/dev/null) || workspaces='{}'
  printf '%s' "$tabs" | jq -e '.result.tabs|type == "array"' >/dev/null 2>&1 || tabs='{"result":{"tabs":[]}}'
  printf '%s' "$workspaces" | jq -e '.result.workspaces|type == "array"' >/dev/null 2>&1 || workspaces='{"result":{"workspaces":[]}}'
  ledger=/dev/null; mtime=0
  if [ -f "$run/ledger.md" ]; then
    ledger=$run/ledger.md
    mtime=$(stat -f %m "$ledger" 2>/dev/null) || mtime=$(stat -c %Y "$ledger")
  fi
  jq -r --argjson live "$agents" --argjson available "$available" --argjson tabs "$tabs" --argjson workspaces "$workspaces" \
    --rawfile ledger "$ledger" --argjson mtime "$mtime" --argjson w "$width" \
    --argjson h "$height" --argjson stale "$stale" --arg clock "${STATUS_NOW:-}" '
    # Sanitize terminal controls (including embedded ANSI), then measure
    # codepoints in display columns: combining marks zero, wide glyphs two.
    def clean: tostring | gsub("\u001b\\[[0-?]*[ -/]*[@-~]"; "") |
      gsub("[\u0000-\u001f\u007f-\u009f]"; " ");
    def columns:
      if (. >= 768 and . <= 879) or (. >= 6832 and . <= 6911) or
         (. >= 7616 and . <= 7679) or (. >= 8400 and . <= 8447) or
         (. >= 65024 and . <= 65039) or (. >= 65056 and . <= 65071) or
         (. >= 917760 and . <= 917999) or . == 8203 or . == 8204 or . == 8205 then 0
      elif (. >= 4352 and . <= 4447) or (. >= 8986 and . <= 8987) or
         . == 9001 or . == 9002 or (. >= 9193 and . <= 9196) or
         . == 9200 or . == 9203 or (. >= 9725 and . <= 9726) or
         (. >= 9748 and . <= 9749) or (. >= 9800 and . <= 9811) or
         . == 9855 or . == 9875 or . == 9889 or (. >= 9898 and . <= 9899) or
         (. >= 9917 and . <= 9918) or (. >= 9924 and . <= 9925) or
         . == 9934 or . == 9940 or . == 9962 or (. >= 9970 and . <= 9971) or
         . == 9973 or . == 9978 or . == 9981 or . == 9989 or
         (. >= 9994 and . <= 9995) or . == 10024 or . == 10060 or . == 10062 or
         (. >= 10067 and . <= 10069) or . == 10071 or
         (. >= 10133 and . <= 10135) or . == 10160 or . == 10175 or
         (. >= 11035 and . <= 11036) or . == 11088 or . == 11093 or
         (. >= 11904 and . <= 42191 and . != 12351) or
         (. >= 44032 and . <= 55203) or (. >= 63744 and . <= 64255) or
         (. >= 65040 and . <= 65049) or (. >= 65072 and . <= 65131) or
         (. >= 65281 and . <= 65376) or (. >= 65504 and . <= 65510) or
         . == 127004 or . == 127183 or (. >= 127232 and . <= 127569) or
         (. >= 127744 and . <= 129791) or (. >= 131072 and . <= 262141) then 2
      else 1 end;
    def cut:
      clean | explode | reduce .[] as $cp ({text:[],cols:0,full:false};
        ($cp|columns) as $cw |
        if .full or .cols + $cw > $w then .full = true
        else .text += [$cp] | .cols += $cw end) | .text | implode;
    (if $clock == "" then now else ($clock|fromdateiso8601) end) as $now |
    def age($stamp): ([0, (($now - (try ($stamp|fromdateiso8601) catch $now))/60|floor)]|max|tostring) + "m";
    def glyph:
      if . == "done" or . == "merged" then "✓"
      elif . == "active" or . == "implementing" or . == "review" or . == "fix" or . == "briefed" then "◐"
      elif . == "dropped" or . == "skipped" then "✗"
      elif . == "blocked" then "!" elif . == "staged" then "◉" else "○" end;
    def milestone: "\(.state|glyph) \(.id) \(.title) [\(.state)]";
    . as $s |
    ($s.agents // []) as $agents |
    ([$live.result.agents[] | select((.name // "") != "")]) as $live |
    ([$live[] | . as $a | select(.name == ($s.prefix + "-overseer") or any($agents[]; .name == $a.name))]) as $scoped |
    ([$s.waiting_on_human[]? | "! \(.id): \(.action) (\(age(.since)))"] +
     [$scoped[] | select(.agent_status == "blocked") | . as $a |
      ([$agents[] | select(.name == $a.name)][0].since // $s.updated) as $since |
      "! \(.name): herdr:blocked (\(age($since)))"] +
     [$scoped[] | select(($s.herdr.workspace // "") != "" and .workspace_id != $s.herdr.workspace) |
      "! \(.name) is in workspace \(.workspace_id // "unknown"), run is in \($s.herdr.workspace)"]) as $wait |
    ([$agents[] | select(.state == "open") | . as $a |
      ([$live[] | select(.name == $a.name)][0]) as $l |
      "\(.name) herdr:\(if $available then ($l.agent_status // "gone") else "unavailable" end) \(age(.since)) tab:\($l.tab_id // .tab // "-") \($l.terminal_title_stripped // "")"]) as $agentlines |
    {header:(["RUN \($s.run_id) | \($s.goal)", "\($now|todateiso8601) | ledger written \(if $mtime == 0 then "never" else age($mtime|todateiso8601) + " ago" end)"] +
      (if ($s.herdr.workspace // "") != "" then
        ["workspace: \([$workspaces.result.workspaces[] | select(.workspace_id == $s.herdr.workspace)][0].label // "unknown") (\($s.herdr.workspace)) | cockpit: \([$tabs.result.tabs[] | select(.tab_id == $s.herdr.cockpit_tab)][0].label // "unknown") (\($s.herdr.cockpit_tab // "unknown"))"]
       else [] end)),
     waiting:(if ($wait|length) > 0 then ["WAITING ON YOU"] + $wait else [] end),
     milestones:(["MILESTONES"] + [$s.milestones[]? | milestone]),
     nodes:(["NODES"] + [$s.nodes[]? | "\(.state|glyph) \(.id) \(.title) [\(.state)] \(age(.since))\(if .pr != null then " PR #\(.pr)" else "" end) CI:\(.ci // "none")"]),
     agents:(["AGENTS"] + (if $available then $agentlines else ["herdr unavailable"] + $agentlines end)),
     stale:(if any($scoped[]; .agent_status == "working") and ($mtime == 0 or $now - $mtime >= $stale * 60)
       then ["STALE: ledger has not been written for \(if $mtime == 0 then "an unknown time" else age($mtime|todateiso8601) end) while a run agent is working"] else [] end),
     ledger:($ledger|split("\n")|map(select(startswith("- 20")))|.[-8:])} |
    def lines: .header + .waiting + .milestones + .nodes + .agents + .stale +
      (if (.ledger|length) > 0 then ["RECENT LEDGER"] + .ledger else [] end);
    if $h > 0 then
      until ((lines|length) <= $h or (.ledger|length) == 0; .ledger |= .[1:]) |
      if (lines|length) > $h then
        .milestones = (["MILESTONES"] + [$s.milestones[]? | select(.state == "active") | milestone] +
          ([$s.milestones[]? | select(.state == "pending") | milestone]|.[:1]) +
          ([$s.milestones[]? | select(.state == "done")]|length|if . > 0 then ["+\(.) done"] else [] end))
      else . end
    else . end | lines |
    if $h > 0 and length > $h then . + ["(\(length + 1 - $h) lines over height)"] else . end |
    .[] | cut' "$run/status.json"
}
while :; do
  measure_size
  output=$(frame)
  if [ "$tty_loop" = 1 ]; then
    printf '\033[H'
    first=1
    while IFS= read -r line; do
      if [ "$first" = 0 ]; then printf '\n'; fi
      first=0
      case $line in 'WAITING ON YOU'|'! '*) printf '\033[1;7m%s\033[0m\033[K' "$line" ;; *) printf '%s\033[K' "$line" ;; esac
    done <<<"$output"
    printf '\033[J'
  else printf '%s\n' "$output"; fi
  [ "$once" = 0 ] || exit 0
  sleep "$interval"
done
