#!/usr/bin/env bash
# inbox-watch.sh RUN_DIR [--once] [--interval S=2] [--stall-min M=10]
# Delivers delegate messages to the overseer as stdout lines, for a harness
# monitor (streaming) or a background shell (--once: exit 0 after the first
# event). Bash 3.2, BSD or GNU tools.
# Message: RUN_DIR/inbox/new/<from>--<anything>.md, <from> matching
# [a-z][a-z0-9_-]{0,31}; first line `kind: report|question|blocker|note`
# (missing/invalid: kind note, flagged [no-kind]); the rest is the body.
# Dotfiles and other names are ignored. A file is ready when its size and
# mtime match the previous poll and its mtime is at least 2 s old (whole-
# second mtimes: at least 1 s of quiet). Ready files go oldest first:
#   inbox: <from> <kind>[ unverified]: <flat body, ANSI stripped, ~200 chars> [cur/<file>][ [oversize]][ [no-kind]]
# then the file moves to inbox/cur/ and a `delivered` line goes to
# inbox/log.jsonl. A restart redelivers anything still in new/ (backlog);
# nothing is deleted. verified: <from> is an open agent row in status.json.
# Handover: prints `inbox: watcher stopped (handover)` and exits 0 when
# status.json .herdr.overseer_pane differs from the pane it started under
# (HERDR_PANE_ID, else the value at start), or rotation.json .state is
# preparing|started|adopted with .from_pane equal to that pane (the retiring
# overseer); a successor's watcher (.to_pane) ignores rotation state.
# Stalls (advisory; every 60 s, from the second poll): open agents except the
# overseer that have a readable inbox/sent/<name> stamp. idle/done/unknown:
# only with no delivered message since the stamp (after one, the agent waits
# on the overseer until the next stamp), when min(status age, now - stamp)
# >= M min; blocked >= 2 min; working >= 45 min (status age); missing from
# `herdr-backend.sh agents`: at once. Prints `stall: <name> <status> <N>m`
# once per episode (a status or stamp change starts a new one; episodes
# persist in inbox/stall.json) and logs `stall`.
# A failed agents call skips that stall poll.
# This script is the only writer of inbox/log.jsonl and the only mover of
# new/ -> cur/. INBOX_NOW=UTC-ISO fixes the clock for tests.
# Exit: 0 --once event or handover, 1 setup failure, 2 usage.
# The body is one main() called on the last line, so bash has parsed the whole
# file before it runs anything and an in-place edit cannot change a live watcher.
main() {
set -uo pipefail
usage() { echo "usage: inbox-watch.sh RUN_DIR [--once] [--interval S] [--stall-min M]" >&2; exit 2; }
[ $# -ge 1 ] || usage
run=$1; shift
once=0; interval=2; stall_min=10
while [ $# -gt 0 ]; do
  case $1 in
    --once) once=1; shift ;;
    --interval|--stall-min)
      [ $# -ge 2 ] || usage
      case $1 in --interval) interval=$2 ;; *) stall_min=$2 ;; esac
      shift 2 ;;
    *) usage ;;
  esac
done
case $stall_min in ''|*[!0-9]*) usage ;; esac
[[ $interval =~ ^[0-9]+([.][0-9]+)?$ ]] || usage
jq -en --arg s "$interval" '$s|tonumber|select(. > 0)' >/dev/null || usage
[ -d "$run" ] || { echo "inbox-watch: no run directory: $run" >&2; exit 1; }
fixed=''
if [ -n "${INBOX_NOW:-}" ]; then
  fixed=$(jq -n --arg s "$INBOX_NOW" '$s|fromdateiso8601' 2>/dev/null) || usage
fi
now() { if [ -n "$fixed" ]; then echo "$fixed"; else date -u +%s; fi; }
run=$(cd "$run" && pwd)
here=$(cd "$(dirname "$0")" && pwd)
backend=$here/herdr-backend.sh
inbox=$run/inbox; status=$run/status.json; log=$inbox/log.jsonl; episodes=$inbox/stall.json
mkdir -p "$inbox/new" "$inbox/cur" "$inbox/sent" || exit 1
export HERDR_BACKEND_RUN_DIR=$run
trap 'exit 0' HUP INT TERM
name_re='^[a-z][a-z0-9_-]{0,31}$'
overseer_pane() { [ -f "$status" ] && jq -r '.herdr.overseer_pane // ""' "$status" 2>/dev/null; }
start_pane=$(overseer_pane) || start_pane=''
base=${HERDR_PANE_ID:-$start_pane}

handover() {
  local cur rot
  if [ -n "$base" ] && cur=$(overseer_pane) && [ -n "$cur" ]; then [ "$cur" = "$base" ] || return 0; fi
  [ -n "$base" ] || return 1
  rot=$(jq -r --arg p "$base" 'if .from_pane == $p then .state // "" else "" end' "$run/rotation.json" 2>/dev/null) || rot=''
  case $rot in preparing|started|adopted) return 0 ;; esac
  return 1
}

# One "mtime<TAB>size<TAB>name" line per candidate, oldest first.
scan() {
  local f b sig
  for f in "$inbox/new"/*--*.md; do
    [ -f "$f" ] || continue
    b=${f##*/}
    case $b in .*|*$'\n'*|*$'\t'*) continue ;; esac
    [[ ${b%%--*} =~ $name_re ]] || continue
    sig=$(stat -c '%Y	%s' "$f" 2>/dev/null || stat -f '%m	%z' "$f" 2>/dev/null) || continue
    printf '%s\t%s\n' "$sig" "$b"
  done | sort -t "$(printf '\t')" -k1,1n -k3,3
}

deliver() { # FILE BYTES; 0 when delivered
  local file=$1 bytes=$2 from=${1%%--*} target=$1 verified=false out line json
  if [ -e "$inbox/cur/$target" ]; then target=${file%.md}.$(now)-$$-$RANDOM.md; fi
  if [ -f "$status" ] && jq -e --arg n "$from" 'any(.agents[]?; .name == $n and .state == "open")' "$status" >/dev/null 2>&1; then
    verified=true
  fi
  out=$(jq -nr --rawfile raw "$inbox/new/$file" --arg from "$from" --arg file "$file" --arg target "$target" \
    --argjson verified "$verified" --argjson bytes "$bytes" --argjson now "$(now)" '
    def flat: gsub("\u001b\\][^\u0007\u001b]*(\u0007|\u001b\\\\)?"; "") | gsub("\u001b\\[[0-?]*[ -/]*[@-~]"; "") |
      gsub("\u001b."; "") | gsub("[\u0000-\u001f\u007f-\u009f]"; " ") | gsub("  +"; " ") | sub("^ "; "") | sub(" $"; "");
    ($raw | split("\n")) as $l |
    ([($l[0] // "") | capture("^[Kk]ind:[ \t]*(?<k>[A-Za-z]*)[ \t\r]*$") | .k | ascii_downcase][0]) as $k |
    (($k // "") as $k | ["report","question","blocker","note"] | index($k) != null) as $valid |
    (if $k == null then $raw else $l[1:] | join("\n") end) as $body |
    ($body | sub("\r?\n$"; "") | utf8bytelength > 4000) as $oversize |
    ($body | flat | if length > 200 then .[:200] + "…" else . end) as $short |
    (if $valid then $k else "note" end) as $kind |
    "inbox: \($from) \($kind)\(if $verified then "" else " unverified" end): \($short) [cur/\($target | flat)]" +
      (if $oversize then " [oversize]" else "" end) + (if $valid then "" else " [no-kind]" end),
    ({event: "delivered", ts: ($now | todateiso8601), id: $file, from: $from, kind: $kind, verified: $verified,
      bytes: $bytes, flags: ([if $oversize then "oversize" else empty end, if $valid then empty else "no-kind" end])} | tojson)') || return 1
  { IFS= read -r line; IFS= read -r json; } <<<"$out"
  printf '%s\n' "$line"
  mv "$inbox/new/$file" "$inbox/cur/$target" || return 1
  printf '%s\n' "$json" >>"$log"
}

prev=$'\n'
poll_messages() {
  local listing t mtime size file
  listing=$(scan); t=$(now)
  while IFS=$'\t' read -r mtime size file; do
    [ -n "$file" ] || continue
    case $prev in *$'\n'"$mtime"$'\t'"$size"$'\t'"$file"$'\n'*) ;; *) continue ;; esac
    [ $((t - mtime)) -ge 2 ] || continue
    if deliver "$file" "$size" && [ "$once" = 1 ]; then exit 0; fi
  done <<<"$listing"
  prev=$'\n'"$listing"$'\n'
}

stall_poll() {
  local live stamps f state='{}' logtext=/dev/null out
  [ -f "$status" ] || return 0
  live=$("$backend" agents 2>/dev/null) || return 0
  jq -e 'type == "array"' <<<"$live" >/dev/null 2>&1 || return 0
  stamps=$(for f in "$inbox/sent"/*; do
      [ -f "$f" ] && printf '%s\t%s\n' "${f##*/}" "$(head -n1 "$f")"
    done | jq -Rsc '[split("\n")[] | select(length > 0) | split("\t") | {key: .[0], value: .[1]}] | from_entries') || return 0
  if [ -f "$episodes" ] && jq -e 'type == "object"' "$episodes" >/dev/null 2>&1; then state=$(cat "$episodes"); fi
  [ -f "$log" ] && logtext=$log
  out=$(jq -c -n --slurpfile s "$status" --argjson live "$live" --argjson stamps "$stamps" --argjson st "$state" \
    --rawfile log "$logtext" --argjson now "$(now)" --argjson min "$stall_min" --argjson once "$once" '
    def ep: try (sub("\\.[0-9]+"; "") | fromdateiso8601) catch null;
    def clean: tostring | gsub("[\u0000-\u001f\u007f-\u009f]"; " ");
    $s[0] as $s |
    ([$log | split("\n")[] | fromjson? | select(type == "object" and .event == "delivered")] | group_by(.from) |
      map({key: .[0].from, value: (map(.ts | ep) | max)}) | from_entries) as $msgs |
    reduce ($s.agents[]? | select(.state == "open" and .role != "overseer" and .name != (($s.prefix // "") + "-overseer"))) as $a
      ({out: [], st: $st, fired: false};
      ($stamps[$a.name] // null | if . == null then null else ep end) as $sent |
      ([$live[] | select(.name == $a.name)][0]) as $l |
      (if $l == null then "gone" else ($l.status // "unknown") | if IN("idle", "done", "blocked", "working") then . else "unknown" end end) as $status |
      if $sent == null or (IN($status; "idle", "done", "unknown") and ($msgs[$a.name] // null) != null and $msgs[$a.name] >= $sent)
      then . else
      ([0, $now - $sent] | max) as $since |
      ($l.status_age_s // null) as $age |
      (if $status == "gone" then [true, $since]
       elif $status == "blocked" then [($age // $since) >= 120, ($age // $since)]
       elif $status == "working" then [($age // $since) >= 2700, ($age // $since)]
       else ([$age // $since, $since] | min) as $q | [$q >= $min * 60, $q] end) as [$hit, $secs] |
      "\($status)|\($sent)" as $key |
      (if .st[$a.name].key != $key then .st[$a.name] = {key: $key, fired: false} else . end) |
      if $hit and (.st[$a.name].fired | not) and (($once == 1 and .fired) | not) then
        ($secs / 60 | floor) as $m |
        .st[$a.name].fired = true | .fired = true |
        .out += [{line: "stall: \($a.name | clean) \($status) \($m)m",
          log: {event: "stall", ts: ($now | todateiso8601), name: $a.name, status: $status, minutes: $m}}]
      else . end end) | {out, st}') || return 0
  jq -r '.out[].line' <<<"$out"
  jq -c '.st' <<<"$out" >"$episodes.tmp.$$" && mv "$episodes.tmp.$$" "$episodes"
  jq -c '.out[].log' <<<"$out" >>"$log"
  if [ "$once" = 1 ] && [ "$(jq '.out | length' <<<"$out")" -gt 0 ]; then exit 0; fi
}

polls=0; last_stall=''
while :; do
  if handover; then echo 'inbox: watcher stopped (handover)'; exit 0; fi
  poll_messages
  polls=$((polls + 1)); t=$(now)
  if [ "$polls" -ge 2 ] && { [ -z "$last_stall" ] || [ $((t - last_stall)) -ge 60 ]; }; then
    last_stall=$t; stall_poll
  fi
  sleep "$interval"
done
}
main "$@"; exit $?
