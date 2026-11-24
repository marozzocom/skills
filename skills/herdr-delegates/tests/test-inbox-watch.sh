#!/usr/bin/env bash
# Inbox delivery (order, readiness, attribution, flags, flattening, move and
# log), backlog across restarts, --once, handover exits and stall rules.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
W=$BIN_DIR/inbox-watch.sh
unset HERDR_PANE_ID
NOW=2030-01-01T01:00:00Z
WPID=''
start_watch() { # OUT RUN_DIR [ARGS...]: stream in the background
  local out=$1; shift
  INBOX_NOW=${CLOCK:-$NOW} "$W" "$@" --interval 0.05 >"$out" 2>"$out.err" &
  WPID=$!
}
wait_lines() { # FILE N: up to ~3 s for FILE to hold N lines
  local i=0
  while [ "$i" -lt 60 ]; do
    [ "$(wc -l <"$1" | tr -d ' ')" -ge "$2" ] && return 0
    sleep 0.05; i=$((i + 1))
  done
  return 1
}
stop_watch() { kill "$WPID" 2>/dev/null; wait "$WPID" 2>/dev/null; }
once() { # a --once run, killed after ~3 s so a regression fails instead of hanging
  local out=$SCRATCH/once.out i=0
  INBOX_NOW=${CLOCK:-$NOW} "$W" "$@" --once --interval 0.05 >"$out" 2>/dev/null &
  local pid=$!
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 60 ]; do sleep 0.05; i=$((i + 1)); done
  if kill -0 "$pid" 2>/dev/null; then kill -9 "$pid"; wait "$pid" 2>/dev/null; cat "$out"; return 124; fi
  wait "$pid"; local rc=$?
  cat "$out"; return "$rc"
}

m=$SCRATCH/m; mkdir -p "$m/inbox/new"
jq -n '{prefix:"fx",herdr:{overseer_pane:"w1:p1"},agents:[
  {name:"fx-overseer",role:"overseer",state:"open"},{name:"fx-impl",state:"open"},{name:"fx-closed",state:"closed"}]}' >"$m/status.json"
echo '{"result":{"agents":[]}}' >"$HERDR_SCENARIO/agents.json"
new=$m/inbox/new
printf 'kind: report\nline1\n\033[31mred\033[0m\tline2\n' >"$new/fx-impl--b.md"
printf 'kind: question\nwho are you\n' >"$new/fx-stranger--a.md"
printf 'hello, no kind line\n' >"$new/fx-closed--c.md"
printf 'kind: bogus\nbody\n' >"$new/fx-impl--d.md"
{ echo 'kind: note'; head -c 5000 /dev/zero | tr '\0' 'x'; } >"$new/fx-impl--e.md"
for f in .fx-impl--hidden.md notes.md Bad--x.md fx-impl--x.md.tmp; do echo 'kind: note' >"$new/$f"; done
touch -t 202001010000 "$new/fx-impl--b.md"; touch -t 202001010001 "$new/fx-stranger--a.md"
touch -t 202001010002 "$new/fx-closed--c.md"; touch -t 202001010003 "$new/fx-impl--d.md"
touch -t 202001010004 "$new/fx-impl--e.md"
# --once delivers only the oldest message and leaves the rest as backlog.
out=$(once "$m"); assert_eq once-exit 0 "$?"
assert_eq once-first 'inbox: fx-impl report: line1 red line2 [cur/fx-impl--b.md]' "$out"
assert_eq once-moved yes "$([ -f "$m/inbox/cur/fx-impl--b.md" ] && [ ! -e "$new/fx-impl--b.md" ] && echo yes)"
assert_eq once-backlog-kept 8 "$(find "$new" -type f | wc -l | tr -d ' ')"
# A restarted watcher delivers the backlog oldest first.
# Stop only once the log also holds all 5 delivered lines (print, mv, then log).
start_watch "$SCRATCH/batch" "$m"; wait_lines "$SCRATCH/batch" 4; wait_lines "$m/inbox/log.jsonl" 5; stop_watch
out=$(cat "$SCRATCH/batch")
assert_eq batch-count 4 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
assert_eq order 'fx-stranger fx-closed fx-impl fx-impl' "$(printf '%s\n' "$out" | awk '{print $2}' | xargs)"
assert_contains unverified 'inbox: fx-stranger question unverified: who are you [cur/fx-stranger--a.md]' "$out"
assert_contains closed-unverified-nokind 'inbox: fx-closed note unverified: hello, no kind line [cur/fx-closed--c.md] [no-kind]' "$out"
assert_contains invalid-kind 'inbox: fx-impl note: body [cur/fx-impl--d.md] [no-kind]' "$out"
oversize=$(printf '%s\n' "$out" | grep 'fx-impl--e.md')
assert_contains oversize-flag '[cur/fx-impl--e.md] [oversize]' "$oversize"
assert_contains oversize-cut "$(printf 'x%.0s' $(seq 1 200))… [cur" "$oversize"
assert_not_contains oversize-cut-only "$(printf 'x%.0s' $(seq 1 201))" "$oversize"
assert_eq ignored-left '.fx-impl--hidden.md Bad--x.md fx-impl--x.md.tmp notes.md' "$(cd "$new" && ls -A | sort | xargs)"
assert_eq cur-count 5 "$(find "$m/inbox/cur" -type f | wc -l | tr -d ' ')"
log=$m/inbox/log.jsonl
assert_eq log-ids 'fx-impl--b.md fx-stranger--a.md fx-closed--c.md fx-impl--d.md fx-impl--e.md' "$(jq -r .id "$log" | xargs)"
assert_eq log-first '{"event":"delivered","ts":"2030-01-01T01:00:00Z","id":"fx-impl--b.md","from":"fx-impl","kind":"report","verified":true,"bytes":38,"flags":[]}' "$(head -n1 "$log")"
assert_eq log-flags 'false|no-kind true|no-kind true|oversize' "$(jq -r 'select(.from != "fx-impl" or .kind == "note") | select(.id != "fx-stranger--a.md") | "\(.verified)|\(.flags|join(","))"' "$log" | xargs)"
# Readiness: a file still growing is not delivered until it settles.
printf 'kind: note\n' >"$new/fx-impl--grow.md"
( i=0; while [ "$i" -lt 25 ]; do printf 'chunk%s ' "$i" >>"$new/fx-impl--grow.md"; sleep 0.02; i=$((i + 1)); done ) &
grower=$!
start_watch "$SCRATCH/grow" "$m"
wait "$grower"
assert_eq not-while-growing 0 "$(wc -l <"$SCRATCH/grow" | tr -d ' ')"
wait_lines "$SCRATCH/grow" 1; stop_watch
assert_contains settled-whole 'chunk0 chunk1' "$(cat "$SCRATCH/grow")"
assert_contains settled-last 'chunk24 [cur/fx-impl--grow.md]' "$(cat "$SCRATCH/grow")"
# Real time: a file written under a second ago waits for quiet.
printf 'kind: note\nfresh\n' >"$new/fx-impl--fresh.md"
CLOCK=$(date -u +%Y-%m-%dT%H:%M:%SZ) start_watch "$SCRATCH/fresh" "$m"; sleep 0.3; stop_watch
assert_eq fresh-waits '' "$(cat "$SCRATCH/fresh")"
assert_eq fresh-kept yes "$([ -f "$new/fx-impl--fresh.md" ] && echo yes)"
assert_eq duplicate-target 'cur/fx-impl--b.' "$(cp "$m/inbox/cur/fx-impl--b.md" "$new/" && touch -t 202001010000 "$new/fx-impl--b.md" && once "$m" | sed -n 's/.*\[\(cur\/fx-impl--b\.\).*/\1/p')"
assert_eq duplicate-kept 2 "$(find "$m/inbox/cur" -name 'fx-impl--b*' | wc -l | tr -d ' ')"
assert_eq fresh-later 'inbox: fx-impl note: fresh [cur/fx-impl--fresh.md]' "$(once "$m")"

# Handover: overseer_pane change, a different starting pane, rotation states.
start_watch "$SCRATCH/hand" "$m"; sleep 0.15
jq '.herdr.overseer_pane = "w1:p9"' "$m/status.json" >"$SCRATCH/s" && mv "$SCRATCH/s" "$m/status.json"
wait_lines "$SCRATCH/hand" 1; wait "$WPID"; rc=$?
assert_eq pane-change-exit 0 "$rc"
assert_eq pane-change-line 'inbox: watcher stopped (handover)' "$(cat "$SCRATCH/hand")"
assert_eq other-pane 'inbox: watcher stopped (handover)' "$(HERDR_PANE_ID=w1:p1 once "$m")"
printf 'kind: note\nstill here\n' >"$new/fx-impl--same.md"
assert_eq same-pane-no-stop 'inbox: fx-impl note: still here [cur/fx-impl--same.md]' "$(HERDR_PANE_ID=w1:p9 once "$m")"
# Rotation stops only the retiring overseer's watcher (base = from_pane).
for state in preparing started adopted; do
  echo "{\"state\":\"$state\",\"from_pane\":\"w1:p9\",\"to_pane\":\"w1:p7\"}" >"$m/rotation.json"
  assert_eq "rotation-$state" 'inbox: watcher stopped (handover)' "$(once "$m")"
done
echo '{"state":"adopted","from_pane":"w1:p1","to_pane":"w1:p9"}' >"$m/rotation.json"
printf 'kind: note\nto the successor\n' >"$new/fx-impl--succ.md"
assert_eq successor-keeps-running 'inbox: fx-impl note: to the successor [cur/fx-impl--succ.md]' "$(once "$m")"
echo '{"state":"preparing","from_pane":"w1:p9","to_pane":""}' >"$m/rotation.json"
assert_eq retiring-stops-preparing 'inbox: watcher stopped (handover)' "$(HERDR_PANE_ID=w1:p9 once "$m")"
echo '{"state":"closed"}' >"$m/rotation.json"
start_watch "$SCRATCH/closed" "$m"; sleep 0.2; stop_watch
assert_eq rotation-closed '' "$(cat "$SCRATCH/closed")"
# An empty or missing overseer_pane is not a pane change.
r=$SCRATCH/r-run; mkdir -p "$r/inbox/new"; echo '{"agents":[]}' >"$r/status.json"
printf 'kind: note\nno pane recorded\n' >"$r/inbox/new/fx-impl--np.md"
assert_eq empty-pane-keeps-running 'inbox: fx-impl note unverified: no pane recorded [cur/fx-impl--np.md]' "$(HERDR_PANE_ID=w1:p1 once "$r")"
# An empty file is delivered (kind note) and moved, not retried forever.
: >"$r/inbox/new/fx-impl--empty.md"; touch -t 202001010000 "$r/inbox/new/fx-impl--empty.md"
assert_eq empty-file 'inbox: fx-impl note unverified:  [cur/fx-impl--empty.md] [no-kind]' "$(once "$r")"
assert_eq empty-file-moved yes "$([ -f "$r/inbox/cur/fx-impl--empty.md" ] && [ ! -e "$r/inbox/new/fx-impl--empty.md" ] && echo yes)"
# GNU stat: -c is asked first, so -f (GNU: file-system info on stdout) never runs.
g=$SCRATCH/gnu; mkdir -p "$g"; real_stat=$(command -v stat)
cat >"$g/stat" <<SHIM
#!/bin/bash
echo "stat \$1" >>"$g/calls"
case \$1 in
  -f) printf '  File: "%s"\n    ID: 0 Namelen: 255\n' "\$3"; exit 1 ;;
  -c) if "$real_stat" -c %Y "\$3" >/dev/null 2>&1; then exec "$real_stat" -c "\$2" "\$3"; else exec "$real_stat" -f '%m	%z' "\$3"; fi ;;
esac
SHIM
chmod +x "$g/stat"
printf 'kind: note\ngnu\n' >"$r/inbox/new/fx-impl--gnu.md"; touch -t 202001010000 "$r/inbox/new/fx-impl--gnu.md"
assert_eq gnu-stat-delivers 'inbox: fx-impl note unverified: gnu [cur/fx-impl--gnu.md]' "$(PATH=$g:$PATH once "$r")"
assert_eq gnu-stat-no-fs-query '' "$(grep -x 'stat -f' "$g/calls")"
# The watcher never prompts anyone.
assert_not_contains no-prompt 'agent prompt' "$(cat "$MOCK_LOG")"

# Stalls: clock 01:00; stamps relative to it.
s=$SCRATCH/s-run; mkdir -p "$s/inbox/sent"
jq -n '{prefix:"fx",herdr:{overseer_pane:"w1:p1"},agents:([
  "fx-overseer","fx-nostamp","fx-idle","fx-fresh","fx-block","fx-blk2","fx-work","fx-work2","fx-gone","fx-msg","fx-unk","fx-shut","fx-empty"]
  | map({name:., state:(if . == "fx-shut" then "closed" else "open" end)}) | .[0].role = "overseer")}' >"$s/status.json"
jq -n '{result:{agents:[
  {name:"fx-overseer",agent_status:"idle",status_age_s:9999},{name:"fx-nostamp",agent_status:"idle",status_age_s:9999},
  {name:"fx-idle",agent_status:"idle",status_age_s:3600},{name:"fx-fresh",agent_status:"done",status_age_s:3600},
  {name:"fx-block",agent_status:"blocked",status_age_s:180},{name:"fx-blk2",agent_status:"blocked",status_age_s:60},
  {name:"fx-work",agent_status:"working",status_age_s:2800},{name:"fx-work2",agent_status:"working",status_age_s:600},
  {name:"fx-msg",agent_status:"idle",status_age_s:3600},{name:"fx-unk",agent_status:null,status_age_s:1200},
  {name:"fx-shut",agent_status:"idle",status_age_s:9999},{name:"fx-empty",agent_status:"blocked",status_age_s:600}]}}' >"$HERDR_SCENARIO/agents.json"
stamp() { echo "$2" >"$s/inbox/sent/$1"; }
for n in fx-overseer fx-msg fx-shut; do stamp "$n" 2030-01-01T00:30:00Z; done
stamp fx-idle 2030-01-01T00:45:00Z; stamp fx-fresh 2030-01-01T00:55:00Z; stamp fx-block 2030-01-01T00:30:00Z
stamp fx-blk2 2030-01-01T00:30:00Z; stamp fx-work 2030-01-01T00:00:00Z; stamp fx-work2 2030-01-01T00:00:00Z
stamp fx-gone 2030-01-01T00:59:00Z; stamp fx-unk 2030-01-01T00:40:00Z
: >"$s/inbox/sent/fx-empty" # an empty stamp is no stamp, even with an older message
# fx-msg answered at 00:35, over STALL_MIN before 01:00: it waits on the overseer, no stall.
for n in fx-msg fx-nostamp fx-empty; do
  echo "{\"event\":\"delivered\",\"ts\":\"2030-01-01T00:$( [ $n = fx-msg ] && echo 35 || echo 10 ):00Z\",\"id\":\"$n--r.md\",\"from\":\"$n\",\"kind\":\"report\",\"verified\":true,\"bytes\":9}"
done >"$s/inbox/log.jsonl"
echo 123 >>"$s/inbox/log.jsonl" # valid JSON, not an object: ignored
out=$(once "$s"); assert_eq stall-once-exit 0 "$?"
assert_eq stall-once 'stall: fx-idle idle 15m' "$out"
start_watch "$SCRATCH/stall" "$s"; wait_lines "$SCRATCH/stall" 4; sleep 0.1; stop_watch
out=$(cat "$SCRATCH/stall")
assert_eq stall-lines $'stall: fx-block blocked 3m\nstall: fx-work working 46m\nstall: fx-gone gone 1m\nstall: fx-unk unknown 20m' "$out"
assert_eq stall-log 5 "$(jq -r 'select(type == "object" and .event == "stall") | .name' "$s/inbox/log.jsonl" | wc -l | tr -d ' ')"
assert_eq stall-log-line '{"event":"stall","ts":"2030-01-01T01:00:00Z","name":"fx-idle","status":"idle","minutes":15}' "$(sed -n 5p "$s/inbox/log.jsonl")"
# Once per episode, across restarts; a message from a blocked or working agent
# does not start a new one; a new stamp or status does.
mkdir -p "$s/inbox/new"
for n in fx-work fx-block; do
  printf 'kind: note\nstill on it\n' >"$s/inbox/new/$n--prog.md"; touch -t 202001010000 "$s/inbox/new/$n--prog.md"
done
start_watch "$SCRATCH/again" "$s"; wait_lines "$SCRATCH/again" 2; sleep 0.3; stop_watch
assert_eq once-per-episode $'inbox: fx-block note: still on it [cur/fx-block--prog.md]\ninbox: fx-work note: still on it [cur/fx-work--prog.md]' "$(cat "$SCRATCH/again")"
stamp fx-idle 2030-01-01T00:48:00Z; stamp fx-msg 2030-01-01T00:40:00Z
jq '(.result.agents[] | select(.name == "fx-block")) |= (.agent_status = "working" | .status_age_s = 2800)' "$HERDR_SCENARIO/agents.json" >"$SCRATCH/a" && mv "$SCRATCH/a" "$HERDR_SCENARIO/agents.json"
start_watch "$SCRATCH/reset" "$s"; wait_lines "$SCRATCH/reset" 3; sleep 0.1; stop_watch
assert_eq episode-reset $'stall: fx-idle idle 12m\nstall: fx-block working 46m\nstall: fx-msg idle 20m' "$(cat "$SCRATCH/reset")"
# A failed agents call skips the poll without stopping the watcher.
rm "$s/inbox/stall.json"; echo 1 >"$HERDR_SCENARIO/agent-list.exit"
start_watch "$SCRATCH/fail" "$s"; sleep 0.3
assert_eq survives-failure yes "$(kill -0 "$WPID" 2>/dev/null && echo yes)"
stop_watch; rm "$HERDR_SCENARIO/agent-list.exit"
assert_eq failure-silent '' "$(cat "$SCRATCH/fail" "$SCRATCH/fail.err")"
assert_not_contains stall-no-prompt 'agent prompt' "$(cat "$MOCK_LOG")"
"$W" "$s" --interval 0 >/dev/null 2>&1; assert_eq bad-interval 2 "$?"
"$W" "$s" --stall-min x >/dev/null 2>&1; assert_eq bad-stall-min 2 "$?"
finish
