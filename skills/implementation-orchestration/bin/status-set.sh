#!/usr/bin/env bash
# status-set.sh RUN_DIR init RUN_ID PREFIX "GOAL"
# status-set.sh RUN_DIR milestone|node|agent ID k=v...
# status-set.sh RUN_DIR meta workspace=ID cockpit_tab=ID overseer_pane=ID board_pane=ID
# status-set.sh RUN_DIR human add ID "ACTION" | human clear ID|--all
#
# Atomic, mkdir-locked status.json writer; refreshes a marked ledger matrix.
# init creates a ledger and markers, or inserts markers after its first line.
# Keys split at the first '='; quote an entire argument containing spaces.
# STATUS_NOW=UTC-ISO overrides the clock for deterministic callers/tests.
# STATUS_LOCK_WAIT=seconds overrides the 5 s lock wait (nonnegative decimal).
# Exit: 0 one confirmation line, 1 I/O/lock failure, 2 usage or invalid field.
set -euo pipefail
trap 'exit 1' ERR
usage() { echo "usage: status-set.sh RUN_DIR init|milestone|node|agent|human|meta ..." >&2; exit 2; }
fail() { echo "ERROR: $*" >&2; exit 1; }
[ $# -ge 2 ] || usage
run=$1; command=$2; shift 2
stamp=${STATUS_NOW:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}
jq -en --arg s "$stamp" '$s | fromdateiso8601' >/dev/null 2>&1 || usage
lock_wait=${STATUS_LOCK_WAIT:-5}
[[ $lock_wait =~ ^[0-9]+([.][0-9]+)?$ ]] || usage
lock_tries=$(jq -nr --arg s "$lock_wait" '$s|tonumber|. * 10|ceil')
fields='{}'; id=''; action=''; text=''; collection=''
case $command in
  init) [ $# -eq 3 ] || usage ;;
  meta)
    [ $# -ge 1 ] || usage
    for pair in "$@"; do
      case $pair in *=*) key=${pair%%=*}; value=${pair#*=} ;; *) usage ;; esac
      case $key in workspace|cockpit_tab|overseer_pane|board_pane) ;; *) usage ;; esac
      fields=$(jq -cn --argjson f "$fields" --arg k "$key" --arg v "$value" '$f + {($k):$v}')
    done ;;
  milestone|node|agent)
    [ $# -ge 2 ] || usage
    id=$1; shift; [ -n "$id" ] || usage
    case $command in milestone) collection=milestones ;; node) collection=nodes ;; agent) collection=agents ;; esac
    for pair in "$@"; do
      case $pair in *=*) key=${pair%%=*}; value=${pair#*=} ;; *) usage ;; esac
      case "$command:$key" in
        milestone:title|node:title|node:proof|node:tab|agent:role|agent:node|agent:tab|agent:pane|agent:pin|agent:transport|agent:note) ;;
        milestone:state) case $value in pending|active|done|skipped) ;; *) usage ;; esac ;;
        node:state) case $value in planned|briefed|implementing|review|fix|staged|merged|dropped|blocked) ;; *) usage ;; esac ;;
        agent:state) case $value in open|closed) ;; *) usage ;; esac ;;
        node:ci) case $value in none|pending|pass|fail) ;; *) usage ;; esac ;;
        node:pr) case $value in *[!0-9]*) usage ;; esac ;;
        *) usage ;;
      esac
      fields=$(jq -cn --argjson f "$fields" --arg k "$key" --arg v "$value" \
        '$f + {($k): (if $k == "pr" then (if $v == "" then null else ($v|tonumber) end) else $v end)}')
    done ;;
  human)
    [ $# -ge 2 ] || usage
    action=$1; id=$2
    [ -n "$id" ] || usage
    case $action in add) [ $# -eq 3 ] && [ "$id" != --all ] || usage; text=$3 ;; clear) [ $# -eq 2 ] || usage ;; *) usage ;; esac ;;
  *) usage ;;
esac
[ -d "$run" ] || fail "missing run directory: $run"
lock=$run/.status.lock
locked=0; tmp=''; ledger_tmp=''; ledger_seed=''
cleanup() {
  [ -z "$tmp" ] || rm -f "$tmp"
  [ -z "$ledger_tmp" ] || rm -f "$ledger_tmp"
  [ -z "$ledger_seed" ] || rm -f "$ledger_seed"
  if [ "$locked" = 1 ]; then rmdir "$lock" 2>/dev/null || true; fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
tries=0
until mkdir "$lock" 2>/dev/null; do
  tries=$((tries + 1))
  [ "$tries" -lt "$lock_tries" ] || fail "status lock held for $lock_wait s — another writer may be running; if none is, remove $lock"
  sleep 0.1
done
locked=1
rm -f "$run"/.status.?????? "$run"/.ledger.?????? "$run"/.ledger-seed.??????
tmp=$(mktemp "$run/.status.XXXXXX")
if [ "$command" = init ]; then
  [ ! -e "$run/status.json" ] || fail "status.json already exists"
  jq -n --arg run "$1" --arg prefix "$2" --arg goal "$3" --arg now "$stamp" \
    '{run_id:$run,prefix:$prefix,goal:$goal,updated:$now,herdr:{},waiting_on_human:[],milestones:[],nodes:[],agents:[]}' >"$tmp"
else
  [ -f "$run/status.json" ] || fail "status.json missing; use init first"
  jq --arg cmd "$command" --arg col "$collection" --arg id "$id" \
    --arg action "$action" --arg text "$text" --arg now "$stamp" --argjson fields "$fields" '
    .updated = $now |
    if $cmd == "meta" then .herdr = ((.herdr // {}) + $fields)
    elif $cmd == "human" then
      if $action == "clear" then
        .waiting_on_human |= map(select($id != "--all" and .id != $id))
      elif any(.waiting_on_human[]; .id == $id) then
        .waiting_on_human |= map(if .id == $id then .action = $text else . end)
      else .waiting_on_human += [{id:$id,action:$text,since:$now}] end
    else
      (if $cmd == "agent" then "name" else "id" end) as $key |
      (if $cmd == "milestone" then {title:"",state:"pending"}
       elif $cmd == "node" then {title:"",state:"planned",proof:"",pr:null,ci:"none",tab:""}
       else {role:"",node:"",tab:"",pane:"",pin:"",transport:"",note:"",state:"open"} end) as $defaults |
      if any(.[$col][]; .[$key] == $id) then
        .[$col] |= map(if .[$key] == $id then
          . as $old | . + $fields | if .state != $old.state then .since = $now else . end
        else . end)
      else .[$col] += [$defaults + $fields + {($key):$id,since:$now}] end
    end' "$run/status.json" >"$tmp"
fi
ledger_source=$run/ledger.md
if [ -f "$ledger_source" ]; then
  # macOS iconv can reject valid UTF-8; compare jq's decoded bytes instead.
  jq -jn --rawfile l "$ledger_source" '$l' | cmp -s - "$ledger_source" ||
    fail "ledger.md is not valid UTF-8; fix it before the matrix is re-rendered"
fi
if [ "$command" = init ]; then
  if [ ! -f "$ledger_source" ]; then
    ledger_seed=$(mktemp "$run/.ledger-seed.XXXXXX")
    printf '# Ledger — %s\n\n<!-- status-matrix:begin -->\n<!-- status-matrix:end -->\n\n## Entries\n' "$1" >"$ledger_seed"
    ledger_source=$ledger_seed
  elif ! grep -q '<!-- status-matrix:begin -->' "$ledger_source" ||
       ! grep -q '<!-- status-matrix:end -->' "$ledger_source"; then
    ledger_seed=$(mktemp "$run/.ledger-seed.XXXXXX")
    jq -jn --rawfile l "$ledger_source" '
      "\n<!-- status-matrix:begin -->\n<!-- status-matrix:end -->\n\n" as $markers |
      ($l|explode|index([10])) as $end |
      if $end == null then $l, "\n", $markers
      else $l[:($end+1)], $markers, $l[($end+1):] end' >"$ledger_seed"
    ledger_source=$ledger_seed
  fi
fi
# jq raw slurping/output preserves every byte outside the marker interior,
# including a missing final newline. Markdown cells escape pipes/newlines.
if [ -f "$ledger_source" ] && grep -q '<!-- status-matrix:begin -->' "$ledger_source" &&
   grep -q '<!-- status-matrix:end -->' "$ledger_source"; then
  ledger_tmp=$(mktemp "$run/.ledger.XXXXXX")
  jq -jn --slurpfile s "$tmp" --rawfile ledger "$ledger_source" '
    def cell: tostring | gsub("<!--"; "<!- -") | gsub("\\|"; "\\|") | gsub("[\r\n]"; " ");
    def row: "| " + (map(cell) | join(" | ")) + " |";
    "<!-- status-matrix:begin -->" as $b | "<!-- status-matrix:end -->" as $e |
    # jq string index reports byte offsets on some supported versions;
    # array indices and string slices both count codepoints.
    ($ledger|explode|index($b|explode)) as $start | ($start + ($b|length)) as $from |
    ($ledger[$from:]|explode|index($e|explode)) as $end |
    if $end == null then error("ledger matrix markers out of order") else
      $ledger[:$from], "\n\n",
      (if ($s[0].herdr // {} | length) > 0 then
        "Herdr: " + ($s[0].herdr | to_entries | map(.key + "=" + (.value|cell)) | join(" · ")) + "\n\n"
       else "" end),
      ([ ["agent","role","transport","pin","node","tab","state","note"],
         ["---","---","---","---","---","---","---","---"],
         ($s[0].agents[] | [.name,.role,.transport,.pin,.node,.tab,.state,.note]) ] | map(row)|join("\n")),
      "\n\n",
      ([ ["node","title","state","PR","CI"], ["---","---","---","---","---"],
         ($s[0].nodes[] | [.id,.title,.state,(.pr // ""),.ci]) ] | map(row)|join("\n")),
      "\n\n", $ledger[($from + $end):]
    end' >"$ledger_tmp"
fi
mode_of() {
  if [ -e "$1" ]; then stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1"
  else echo 644; fi
}
chmod "$(mode_of "$run/status.json")" "$tmp"
if [ -n "$ledger_tmp" ]; then chmod "$(mode_of "$run/ledger.md")" "$ledger_tmp"; fi
mv "$tmp" "$run/status.json"; tmp=''
if [ -n "$ledger_tmp" ]; then mv "$ledger_tmp" "$run/ledger.md"; ledger_tmp=''; fi
printf 'status updated: %s %s\n' "$command" "$run/status.json"
