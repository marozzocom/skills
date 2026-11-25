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
# shellcheck disable=SC2012 # fixed fixture names; ls -A shows the dotfile
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
# Heartbeat: written on start and every poll, removed on a signal or handover
# exit only while it is this watcher's; a --once event exit leaves a rearm
# heartbeat that inbox-resolve.sh counts as live while fresh.
RES=$BIN_DIR/inbox-resolve.sh
E=$(jq -n --arg s "$NOW" '$s|fromdateiso8601')
h=$SCRATCH/hb; mkdir -p "$h/inbox/new"
jq -n '{prefix:"hb",herdr:{overseer_pane:"w5:p1"},agents:[{name:"hb-overseer",role:"overseer",state:"open"}]}' >"$h/status.json"
wait_file() { local i=0; while [ ! -f "$1" ] && [ "$i" -lt 60 ]; do sleep 0.05; i=$((i + 1)); done; [ -f "$1" ]; }
start_watch "$SCRATCH/hb.out" "$h"; wait_file "$h/inbox/.watch"
assert_eq hb-content "{\"pid\":$WPID,\"pane\":\"w5:p1\",\"ts\":\"$NOW\",\"epoch\":$E,\"interval\":0.05}" "$(cat "$h/inbox/.watch")"
assert_eq hb-live "$(cd "$h" && pwd -P)" "$(INBOX_NOW=$NOW "$RES" "$h")"
rm "$h/inbox/.watch"; wait_file "$h/inbox/.watch"; assert_eq hb-rewritten yes "$([ -f "$h/inbox/.watch" ] && echo yes)"
stop_watch
assert_eq hb-removed-on-signal no "$([ -e "$h/inbox/.watch" ] && echo yes || echo no)"
INBOX_NOW=$NOW "$RES" "$h" >/dev/null 2>&1; assert_eq hb-gone-unwatched 1 "$?"
assert_eq hb-no-temp '' "$(find "$h/inbox" -maxdepth 1 -name '.watch.tmp*')"
# A newer watcher's heartbeat survives this one's exit (handover here).
INBOX_NOW=$NOW "$W" "$h" --interval 1 >"$SCRATCH/hb2.out" 2>&1 & WPID=$!
wait_file "$h/inbox/.watch"; sleep 0.3
foreign='{"pid":999999,"pane":"w5:p2","ts":"x","epoch":1,"interval":2}'
echo "$foreign" >"$h/inbox/.watch"
jq '.herdr.overseer_pane = "w5:p2"' "$h/status.json" >"$SCRATCH/s" && mv "$SCRATCH/s" "$h/status.json"
wait "$WPID"; assert_eq hb-handover-exit 0 "$?"
assert_eq hb-foreign-kept "$foreign" "$(cat "$h/inbox/.watch")"
# Its own heartbeat is removed at a handover.
rm "$h/inbox/.watch"
assert_eq hb-handover 'inbox: watcher stopped (handover)' "$(HERDR_PANE_ID=w5:p1 once "$h")"
assert_eq hb-removed-on-handover no "$([ -e "$h/inbox/.watch" ] && echo yes || echo no)"
# --once event exit: rearm heartbeat, live for max(30, 3 x interval) s.
printf 'kind: note\nping\n' >"$h/inbox/new/hb-overseer--p.md"; touch -t 202001010000 "$h/inbox/new/hb-overseer--p.md"
assert_eq hb-once-delivers 'inbox: hb-overseer note: ping [cur/hb-overseer--p.md]' "$(HERDR_PANE_ID=w5:p2 once "$h")"
assert_eq hb-rearm 'true|0.05' "$(jq -r '"\(.rearm)|\(.interval)"' "$h/inbox/.watch")"
assert_eq hb-rearm-live "$(cd "$h" && pwd -P)" "$(INBOX_NOW=2030-01-01T01:00:30Z "$RES" "$h")"
INBOX_NOW=2030-01-01T01:00:31Z "$RES" "$h" >/dev/null 2>&1; assert_eq hb-rearm-expired 1 "$?"
# A re-armed watcher replaces the rearm heartbeat with a plain one.
start_watch "$SCRATCH/hb3.out" "$h"; sleep 0.2
assert_eq hb-rearm-replaced "$WPID|null" "$(jq -r '"\(.pid)|\(.rearm)"' "$h/inbox/.watch")"
stop_watch

# Cross-run headers and peer attribution. Peers live beside this run
# (dirname RUN_DIR) unless ORCHESTRATION_RUNS_DIR says otherwise.
xr=$SCRATCH/xr; own=$xr/own; mkdir -p "$own/inbox/new"
jq -n '{prefix:"ow",herdr:{overseer_pane:"w9:p1"},agents:[{name:"ow-overseer",role:"overseer",state:"open"},{name:"ow-impl",state:"open"}]}' >"$own/status.json"
peer() { # DIR OVERSEER-STATE PANE: a peer run whose overseer is pa-overseer, with a live heartbeat
  mkdir -p "$1/inbox"
  jq -n --arg st "$2" --arg p "$3" '{prefix:"pa",herdr:{overseer_pane:$p},agents:[{name:"pa-overseer",role:"overseer",state:$st}]}' >"$1/status.json"
  echo "{\"pid\":$$,\"pane\":\"$3\",\"epoch\":$E,\"interval\":2}" >"$1/inbox/.watch"
}
peer "$xr/peer-a" open w2:p1; peer "$xr/peer-b" closed w2:p1
peer "$SCRATCH/x" open w2:p1 # what from-run: ../x would reach if it were joined
xonce() { local n=$1 c=$2; printf '%b' "$c" >"$own/inbox/new/$n"; touch -t 202001010000 "$own/inbox/new/$n"; once "$own"; }
assert_eq peer-live 'inbox: pa-overseer note [peer:peer-a]: hello [cur/pa-overseer--1.md]' \
  "$(xonce pa-overseer--1.md 'kind: note\nfrom-run: peer-a\nfrom-pane: w2:p1\nhello\n')"
assert_eq peer-live-log "{\"event\":\"delivered\",\"ts\":\"$NOW\",\"id\":\"pa-overseer--1.md\",\"from\":\"pa-overseer\",\"kind\":\"note\",\"verified\":false,\"peer_run\":\"peer-a\",\"peer\":\"live\",\"from_pane\":\"w2:p1\",\"bytes\":51,\"flags\":[]}" "$(tail -n1 "$own/inbox/log.jsonl")"
assert_eq peer-order 'inbox: pa-overseer report [peer:peer-a]: body [cur/pa-overseer--2.md]' \
  "$(xonce pa-overseer--2.md 'from-pane: w2:p1\nFrom-Run: peer-a\nKind: Report\nbody\n')"
assert_eq peer-no-kind 'inbox: pa-overseer note [peer:peer-a]: hi [cur/pa-overseer--3.md] [no-kind]' \
  "$(xonce pa-overseer--3.md 'from-run: peer-a\nfrom-pane: w2:p1\nhi\n')"
assert_eq peer-no-kind-log 'note|no-kind' "$(tail -n1 "$own/inbox/log.jsonl" | jq -r '"\(.kind)|\(.flags|join(","))"')"
assert_eq peer-repeat-ends-headers 'inbox: pa-overseer note [peer:peer-a]: kind: report x [cur/pa-overseer--3b.md]' \
  "$(xonce pa-overseer--3b.md 'kind: note\nfrom-run: peer-a\nfrom-pane: w2:p1\nkind: report\nx\n')"
assert_eq peer-retired 'inbox: pa-overseer note unverified [peer-stale:peer-a]: old pane [cur/pa-overseer--4.md]' \
  "$(xonce pa-overseer--4.md 'kind: note\nfrom-run: peer-a\nfrom-pane: w2:p0\nold pane\n')"
assert_eq peer-no-pane 'inbox: pa-overseer note unverified [peer-stale:peer-a]: no pane [cur/pa-overseer--5.md]' \
  "$(xonce pa-overseer--5.md 'kind: note\nfrom-run: peer-a\nno pane\n')"
assert_eq peer-stale-log 'false|peer-a|stale|null' "$(tail -n1 "$own/inbox/log.jsonl" | jq -r '"\(.verified)|\(.peer_run)|\(.peer)|\(.from_pane)"')"
echo "{\"pid\":$$,\"epoch\":$((E - 31)),\"interval\":2}" >"$xr/peer-a/inbox/.watch"
assert_eq peer-expired-watch 'inbox: pa-overseer note unverified [peer-stale:peer-a]: expired [cur/pa-overseer--6.md]' \
  "$(xonce pa-overseer--6.md 'kind: note\nfrom-run: peer-a\nfrom-pane: w2:p1\nexpired\n')"
sleep 0 & dead=$!; wait "$dead"
echo "{\"pid\":$dead,\"epoch\":$E,\"interval\":2}" >"$xr/peer-a/inbox/.watch"
assert_eq peer-dead-watcher 'inbox: pa-overseer note unverified [peer-stale:peer-a]: dead [cur/pa-overseer--7.md]' \
  "$(xonce pa-overseer--7.md 'kind: note\nfrom-run: peer-a\nfrom-pane: w2:p1\ndead\n')"
peer "$xr/peer-a" open w2:p1
assert_eq peer-closed 'inbox: pa-overseer note unverified [peer-closed:peer-b]: bye [cur/pa-overseer--8.md]' \
  "$(xonce pa-overseer--8.md 'kind: note\nfrom-run: peer-b\nfrom-pane: w2:p1\nbye\n')"
assert_eq peer-missing 'inbox: pa-overseer note unverified [peer-unknown:nope]: ? [cur/pa-overseer--9.md]' \
  "$(xonce pa-overseer--9.md 'kind: note\nfrom-run: nope\nfrom-pane: w2:p1\n?\n')"
assert_eq peer-traversal 'inbox: pa-overseer note unverified [peer-unknown:../x]: up [cur/pa-overseer--10.md]' \
  "$(xonce pa-overseer--10.md 'kind: note\nfrom-run: ../x\nfrom-pane: w2:p1\nup\n')"
assert_eq peer-traversal-log '../x|unknown' "$(tail -n1 "$own/inbox/log.jsonl" | jq -r '"\(.peer_run)|\(.peer)"')"
for bad in . ..; do
  assert_contains "peer-dot-$bad" "unverified [peer-unknown:$bad]" "$(xonce "pa-overseer--d$bad.md" "kind: note\nfrom-run: $bad\nfrom-pane: w2:p1\nd\n")"
done
assert_eq peer-not-overseer 'inbox: pa-impl note unverified [peer-unknown:peer-a]: me [cur/pa-impl--11.md]' \
  "$(xonce pa-impl--11.md 'kind: note\nfrom-run: peer-a\nfrom-pane: w2:p1\nme\n')"
# from-run always means a peer message, even from a name that is an open agent here.
assert_eq own-name-with-from-run 'inbox: ow-impl report unverified [peer-unknown:peer-a]: mine [cur/ow-impl--12.md]' \
  "$(xonce ow-impl--12.md 'kind: report\nfrom-run: peer-a\nmine\n')"
assert_eq own-name-log 'false|peer-a|unknown' "$(tail -n1 "$own/inbox/log.jsonl" | jq -r '"\(.verified)|\(.peer_run)|\(.peer)"')"
assert_eq own-no-from-run-log-shape 'event,ts,id,from,kind,verified,bytes,flags' \
  "$(xonce ow-impl--12b.md 'kind: report\nplain\n' >/dev/null; tail -n1 "$own/inbox/log.jsonl" | jq -r '"\(keys_unsorted|join(","))"')"
assert_eq own-no-from-run-verified true "$(tail -n1 "$own/inbox/log.jsonl" | jq -r .verified)"
# Same prefix, another run: a retired ow-overseer of run ow-old is a peer, not this run's open ow-overseer.
mkdir -p "$xr/ow-old/inbox"
jq -n '{prefix:"ow",herdr:{overseer_pane:"w2:p5"},agents:[{name:"ow-overseer",role:"overseer",state:"open"}]}' >"$xr/ow-old/status.json"
echo "{\"pid\":$$,\"epoch\":$E,\"interval\":2}" >"$xr/ow-old/inbox/.watch"
assert_eq same-prefix-peer 'inbox: ow-overseer note [peer:ow-old]: hi [cur/ow-overseer--s1.md]' \
  "$(xonce ow-overseer--s1.md 'kind: note\nfrom-run: ow-old\nfrom-pane: w2:p5\nhi\n')"
assert_eq same-prefix-retired 'inbox: ow-overseer note unverified [peer-stale:ow-old]: hi [cur/ow-overseer--s2.md]' \
  "$(xonce ow-overseer--s2.md 'kind: note\nfrom-run: ow-old\nfrom-pane: w9:p1\nhi\n')"
# This run naming itself is not a peer, even with its own live heartbeat and pane.
echo "{\"pid\":$$,\"epoch\":$E,\"interval\":2}" >"$own/inbox/.watch"
assert_eq self-run 'inbox: ow-overseer note unverified [peer-unknown:own]: me [cur/ow-overseer--s3.md]' \
  "$(xonce ow-overseer--s3.md 'kind: note\nfrom-run: own\nfrom-pane: w9:p1\nme\n')"
rm "$own/inbox/.watch"
# from-pane alone is stripped and changes nothing else.
assert_eq pane-only 'inbox: zz-who note unverified: x [cur/zz-who--13.md]' "$(xonce zz-who--13.md 'kind: note\nfrom-pane: w1:p1\nx\n')"
assert_eq pane-only-log 'event,ts,id,from,kind,verified,bytes,flags' "$(tail -n1 "$own/inbox/log.jsonl" | jq -r 'keys_unsorted|join(",")')"
# Headers do not count toward oversize.
y4000=$(head -c 4000 /dev/zero | tr '\0' 'y')
assert_not_contains headers-not-counted '[oversize]' "$(xonce pa-overseer--14.md "kind: note\nfrom-run: peer-a\nfrom-pane: w2:p1\n$y4000\n")"
assert_contains over-limit '[oversize]' "$(xonce pa-overseer--15.md "kind: note\nfrom-run: peer-a\nfrom-pane: w2:p1\n${y4000}y\n")"
# ORCHESTRATION_RUNS_DIR overrides the sibling lookup.
alt=$SCRATCH/alt; peer "$alt/peer-a" closed w2:p1
assert_eq peer-runs-env 'inbox: pa-overseer note unverified [peer-closed:peer-a]: alt [cur/pa-overseer--16.md]' \
  "$(printf 'kind: note\nfrom-run: peer-a\nfrom-pane: w2:p1\nalt\n' >"$own/inbox/new/pa-overseer--16.md"; touch -t 202001010000 "$own/inbox/new/pa-overseer--16.md"; ORCHESTRATION_RUNS_DIR=$alt once "$own")"
# Fix round 1 edge cases.
# The peer's heartbeat may be a fresh rearm (its --once watcher exited), not an expired one.
echo "{\"pid\":999999,\"epoch\":$((E - 20)),\"interval\":2,\"rearm\":true}" >"$xr/peer-a/inbox/.watch"
assert_eq peer-rearm-fresh 'inbox: pa-overseer note [peer:peer-a]: r [cur/pa-overseer--r1.md]' \
  "$(xonce pa-overseer--r1.md 'kind: note\nfrom-run: peer-a\nfrom-pane: w2:p1\nr\n')"
echo "{\"pid\":999999,\"epoch\":$((E - 31)),\"interval\":2,\"rearm\":true}" >"$xr/peer-a/inbox/.watch"
assert_eq peer-rearm-expired 'inbox: pa-overseer note unverified [peer-stale:peer-a]: r [cur/pa-overseer--r2.md]' \
  "$(xonce pa-overseer--r2.md 'kind: note\nfrom-run: peer-a\nfrom-pane: w2:p1\nr\n')"
echo "{\"pid\":$$,\"epoch\":$((E + 11)),\"interval\":2}" >"$xr/peer-a/inbox/.watch"
assert_eq peer-future-epoch 'inbox: pa-overseer note unverified [peer-stale:peer-a]: f [cur/pa-overseer--r3.md]' \
  "$(xonce pa-overseer--r3.md 'kind: note\nfrom-run: peer-a\nfrom-pane: w2:p1\nf\n')"
echo 'not json' >"$xr/peer-a/inbox/.watch"
assert_eq peer-malformed-watch 'inbox: pa-overseer note unverified [peer-stale:peer-a]: m [cur/pa-overseer--r4.md]' \
  "$(xonce pa-overseer--r4.md 'kind: note\nfrom-run: peer-a\nfrom-pane: w2:p1\nm\n')"
peer "$xr/peer-a" open w2:p1
peer "$xr/peer-bad" open w2:p1; echo '{broken' >"$xr/peer-bad/status.json"
assert_eq peer-malformed-status 'inbox: pa-overseer note unverified [peer-unknown:peer-bad]: m [cur/pa-overseer--r5.md]' \
  "$(xonce pa-overseer--r5.md 'kind: note\nfrom-run: peer-bad\nfrom-pane: w2:p1\nm\n')"
# Dotfile and leading-dash run ids are never joined, even when such a directory is a live peer.
peer "$xr/.hidden" open w2:p1; peer "$xr/-dash" open w2:p1
for bad in .hidden -dash; do
  assert_contains "peer-unsafe-$bad" "unverified [peer-unknown:$bad]: u [cur/" "$(xonce "pa-overseer--u$bad.md" "kind: note\nfrom-run: $bad\nfrom-pane: w2:p1\nu\n")"
done
# The run id in the tag is flattened and capped at 64 characters.
a70=$(printf 'a%.0s' $(seq 1 70))
assert_eq peer-run-capped "inbox: pa-overseer note unverified [peer-unknown:$(printf 'a%.0s' $(seq 1 64))…]: c [cur/pa-overseer--c1.md]" \
  "$(xonce pa-overseer--c1.md "kind: note\nfrom-run: $a70\nc\n")"
assert_eq peer-run-log-full "$a70" "$(tail -n1 "$own/inbox/log.jsonl" | jq -r .peer_run)"
assert_eq peer-run-ansi 'inbox: pa-overseer note unverified [peer-unknown:abcd]: c [cur/pa-overseer--c2.md]' \
  "$(xonce pa-overseer--c2.md 'kind: note\nfrom-run: ab\033[31mcd\nc\n')"
assert_eq peer-run-control 'inbox: pa-overseer note unverified [peer-unknown:ab cd]: c [cur/pa-overseer--c3.md]' \
  "$(xonce pa-overseer--c3.md 'kind: note\nfrom-run: ab\001cd\nc\n')"
# A from-run line after the first body line is body text.
assert_eq body-from-run 'inbox: zz-who note unverified: text from-run: peer-a [cur/zz-who--b1.md]' \
  "$(xonce zz-who--b1.md 'kind: note\ntext\nfrom-run: peer-a\n')"
assert_eq body-from-run-log 'null' "$(tail -n1 "$own/inbox/log.jsonl" | jq -r .peer_run)"
# A retiring watcher (handover at start) leaves its successor's heartbeat untouched.
jq '.herdr.overseer_pane = "w5:p2"' "$h/status.json" >"$SCRATCH/s" && mv "$SCRATCH/s" "$h/status.json"
rm -f "$h/rotation.json"
succ="{\"pid\":$$,\"pane\":\"w5:p2\",\"ts\":\"$NOW\",\"epoch\":$E,\"interval\":2}"
echo "$succ" >"$h/inbox/.watch"; touch -t 202001010000 "$h/inbox/.watch"
assert_eq retiring-handover 'inbox: watcher stopped (handover)' "$(HERDR_PANE_ID=w5:p1 once "$h")"
assert_eq retiring-keeps-successor "$succ" "$(cat "$h/inbox/.watch")"
assert_eq retiring-no-touch 202001010000 "$(date -r "$h/inbox/.watch" +%Y%m%d%H%M 2>/dev/null || date -d "@$(stat -c %Y "$h/inbox/.watch")" +%Y%m%d%H%M)"
# CDPATH never redirects a relative RUN_DIR.
cdp=$SCRATCH/cdp; mkdir -p "$cdp/real/rel/inbox/new" "$cdp/decoy/rel/inbox/new"
echo '{"agents":[]}' >"$cdp/real/rel/status.json"
printf 'kind: note\nreal\n' >"$cdp/real/rel/inbox/new/zz-who--cd.md"; touch -t 202001010000 "$cdp/real/rel/inbox/new/zz-who--cd.md"
assert_eq cdpath-watch 'inbox: zz-who note unverified: real [cur/zz-who--cd.md]' "$(cd "$cdp/real" && CDPATH=$cdp/decoy once rel)"
assert_eq cdpath-decoy-untouched '' "$(find "$cdp/decoy" -type f)"
assert_not_contains peer-no-prompt 'agent prompt' "$(cat "$MOCK_LOG")"
finish
