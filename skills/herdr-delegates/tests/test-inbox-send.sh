#!/usr/bin/env bash
# inbox-send.sh: no Herdr environment needed, atomic drop, validation, and a
# watcher picks the file up.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
S=$BIN_DIR/inbox-send.sh
unset HERDR_ENV HERDR_PANE_ID
run=$SCRATCH/run; mkdir -p "$run"
echo '{"prefix":"fx","herdr":{},"agents":[{"name":"fx-impl","state":"open"}]}' >"$run/status.json"
path=$("$S" "$run" fx-impl report 'done: see /tmp/report.md'); assert_eq send-exit 0 "$?"
case ${path#"$run"/inbox/new/} in fx-impl--[0-9]*T[0-9]*Z-[0-9]*-[0-9]*.md) shape=ok ;; *) shape=$path ;; esac
assert_eq send-name ok "$shape"
assert_eq send-content $'kind: report\ndone: see /tmp/report.md' "$(cat "$path")"
assert_eq no-temp-left '' "$(find "$run/inbox" -name '.*' -type f)"
assert_eq no-herdr-calls '' "$(cat "$MOCK_LOG")"
max=$(head -c 4000 /dev/zero | tr '\0' 'y')
"$S" "$run" fx-impl note "$max" >/dev/null; assert_eq at-limit 0 "$?"
err=$("$S" "$run" fx-impl note "${max}y" 2>&1 >/dev/null); assert_eq oversize-exit 2 "$?"
assert_contains oversize-hint 'write a file and send its path' "$err"
for bad in Fx-impl 9fx '' fx.impl "$(printf 'a%.0s' $(seq 1 33))"; do
  "$S" "$run" "$bad" note hi >/dev/null 2>&1; assert_eq "bad-from-$bad" 2 "$?"
done
"$S" "$run" "$(printf 'a%.0s' $(seq 1 32))" note hi >/dev/null; assert_eq from-32 0 "$?"
for bad in Report urgent ''; do
  "$S" "$run" fx-impl "$bad" hi >/dev/null 2>&1; assert_eq "bad-kind-$bad" 2 "$?"
done
"$S" "$run" fx-impl note >/dev/null 2>&1; assert_eq arg-count 2 "$?"
"$S" "$SCRATCH/missing" fx-impl note hi >/dev/null 2>&1; assert_eq missing-run 2 "$?"
assert_eq sent-count 3 "$(find "$run/inbox/new" -type f | wc -l | tr -d ' ')"
# The watcher delivers what the sender wrote.
run2=$SCRATCH/run2; mkdir -p "$run2"; cp "$run/status.json" "$run2/"
path=$("$S" "$run2" fx-impl question 'which base?')
out=$(HERDR_ENV=1 INBOX_NOW=2030-01-01T00:00:00Z "$BIN_DIR/inbox-watch.sh" "$run2" --once --interval 0.05)
assert_eq watcher-delivers "inbox: fx-impl question: which base? [cur/${path##*/}]" "$out"
# A message at the sender's limit is not oversize to the watcher.
run3=$SCRATCH/run3; mkdir -p "$run3"; cp "$run/status.json" "$run3/"
path=$("$S" "$run3" fx-impl note "$max")
out=$(INBOX_NOW=2030-01-01T00:00:00Z "$BIN_DIR/inbox-watch.sh" "$run3" --once --interval 0.05)
assert_eq at-limit-delivered " [cur/${path##*/}]" "${out##*…}"
# Cross-run: TARGET by run_id or <prefix>-overseer through inbox-resolve.sh,
# from-run/from-pane headers, refusals, and still no Herdr environment.
export INBOX_NOW=2030-01-01T00:00:00Z
E=$(jq -n --arg s "$INBOX_NOW" '$s|fromdateiso8601')
runs=$SCRATCH/runs; mkdir -p "$runs"; runs=$(cd "$runs" && pwd -P)
mkrun() { # ID PREFIX [FLAVOR]
  mkdir -p "$runs/$1/inbox/new"
  jq -n --arg p "$2" --arg f "${3:-}" '{prefix:$p,herdr:({overseer_pane:"w1:p1"} + (if $f == "" then {} else {flavor:$f} end)),
    agents:[{name:($p + "-overseer"),role:"overseer",state:"open"}]}' >"$runs/$1/status.json"
}
live() { echo "{\"pid\":$$,\"pane\":\"w1:p1\",\"epoch\":$E,\"interval\":2}" >"$runs/$1/inbox/.watch"; }
mkrun t-run tg; live t-run; mkrun t-zombie tg
X() { "$S" --runs-dir "$runs" "$@"; }
path=$(X --from-run src-run --from-pane w2:p1 tg-overseer src-overseer question 'which base?'); assert_eq x-prefix 0 "$?"
assert_eq x-prefix-dir "$runs/t-run/inbox/new" "${path%/*}"
assert_eq x-headers $'kind: question\nfrom-run: src-run\nfrom-pane: w2:p1\nwhich base?' "$(cat "$path")"
path=$(HERDR_PANE_ID=w3:p4 X --from-run src-run t-run src-overseer note hi)
assert_eq x-auto-pane $'kind: note\nfrom-run: src-run\nfrom-pane: w3:p4\nhi' "$(cat "$path")"
path=$(HERDR_PANE_ID='bad pane' X --from-run src-run t-run src-overseer note hi)
assert_eq x-bad-env-pane-skipped $'kind: note\nfrom-run: src-run\nhi' "$(cat "$path")"
path=$(HERDR_PANE_ID=w3:p4 "$S" "$run" fx-impl note same-run)
assert_eq same-run-no-auto-pane $'kind: note\nsame-run' "$(cat "$path")"
path=$(X --from-run src-run "$runs/t-run" src-overseer note by-path); assert_eq x-path 0 "$?"
assert_eq x-path-dir "$runs/t-run/inbox/new" "${path%/*}"
path=$(X --from-run src-run --from-pane w2:p1 t-run src-overseer note "$max"); assert_eq x-at-limit 0 "$?"
X --from-run src-run t-run src-overseer note "${max}y" >/dev/null 2>&1; assert_eq x-oversize 2 "$?"
mkrun a-run ap app; live a-run
before=$(find "$runs" -type f | sort)
err=$(X --from-run src-run t-zombie src-overseer note hi 2>&1 >/dev/null); assert_eq x-unwatched 1 "$?"
assert_contains x-unwatched-msg 'no live inbox watcher' "$err"
X --from-run src-run "$runs/t-zombie" src-overseer note hi >/dev/null 2>&1; assert_eq x-unwatched-path 1 "$?"
X --from-run src-run a-run src-overseer note hi >/dev/null 2>&1; assert_eq x-app 3 "$?"
X --allow-unwatched --from-run src-run ap-overseer src-overseer note hi >/dev/null 2>&1; assert_eq x-app-allow 3 "$?"
X --from-run src-run "$runs/a-run" src-overseer note hi >/dev/null 2>&1; assert_eq x-app-path 3 "$?"
X --from-run src-run nosuch src-overseer note hi >/dev/null 2>&1; assert_eq x-missing 1 "$?"
for bad in ../x . .. 'a b' ''; do
  X --from-run "$bad" t-run src-overseer note hi >/dev/null 2>&1; assert_eq "x-bad-from-run-$bad" 2 "$?"
done
for bad in 'w1 p1' 'w1/p1' "$(printf 'w1\np1')"; do
  X --from-run src-run --from-pane "$bad" t-run src-overseer note hi >/dev/null 2>&1; assert_eq "x-bad-pane-$bad" 2 "$?"
done
X --bogus t-run src-overseer note hi >/dev/null 2>&1; assert_eq x-bad-flag 2 "$?"
X --from-run >/dev/null 2>&1; assert_eq x-flag-no-value 2 "$?"
X t-run src-overseer note >/dev/null 2>&1; assert_eq x-arg-count 2 "$?"
assert_eq x-refusals-write-nothing "$before" "$(find "$runs" -type f | sort)"
path=$(X --allow-unwatched --from-run src-run t-zombie src-overseer note queued); assert_eq x-allow-unwatched 0 "$?"
assert_eq x-allow-dir "$runs/t-zombie/inbox/new" "${path%/*}"
# A bare TARGET is never a cwd path, even when a directory of that name exists.
cwd=$SCRATCH/cwd; mkdir -p "$cwd/inbox/new" "$cwd/docs"
for name in inbox docs; do
  (cd "$cwd" && X --allow-unwatched "$name" src-overseer note hi) >/dev/null 2>&1; assert_eq "x-bare-$name" 1 "$?"
done
assert_eq x-bare-untouched '' "$(find "$cwd" -type f)"
(cd "$cwd" && "$S" ./docs fx-impl note hi) >/dev/null; assert_eq x-dot-slash-path 0 "$?"
# Fix round 1: empty option values, single-dash flags, unsafe run ids, CDPATH.
X --runs-dir '' --from-run src-run t-run src-overseer note hi >/dev/null 2>&1; assert_eq x-empty-runs-dir 2 "$?"
HERDR_PANE_ID=w3:p4 X --from-run src-run --from-pane '' t-run src-overseer note hi >/dev/null 2>&1; assert_eq x-empty-pane 2 "$?"
err=$(X -a src-overseer note hi 2>&1 >/dev/null); assert_eq x-single-dash 2 "$?"
assert_contains x-single-dash-usage 'usage: inbox-send.sh' "$err"
for bad in .hidden -dash; do
  X --from-run "$bad" t-run src-overseer note hi >/dev/null 2>&1; assert_eq "x-unsafe-from-run-$bad" 2 "$?"
  X --allow-unwatched -- "$bad" src-overseer note hi >/dev/null 2>&1; assert_eq "x-unsafe-target-$bad" 2 "$?"
done
X --allow-unwatched -- -overseer src-overseer note hi >/dev/null 2>&1; assert_eq x-unsafe-target-overseer 2 "$?"
cdp=$SCRATCH/cdp; mkdir -p "$cdp/real" "$cdp/decoy/bin"; ln -s "$BIN_DIR" "$cdp/real/bin"
printf '#!/bin/bash\necho DECOY >>"%s"\necho /nonexistent\n' "$cdp/decoy.log" >"$cdp/decoy/bin/inbox-resolve.sh"; chmod +x "$cdp/decoy/bin/inbox-resolve.sh"
path=$(cd "$cdp/real" && CDPATH=$cdp/decoy bin/inbox-send.sh --runs-dir "$runs" --from-run src-run t-run src-overseer note cdpath); assert_eq x-cdpath 0 "$?"
assert_eq x-cdpath-dir "$runs/t-run/inbox/new" "${path%/*}"
assert_eq x-cdpath-no-decoy no "$([ -e "$cdp/decoy.log" ] && echo yes || echo no)"
# The watcher on the target run sees the header, not the body.
out=$(env -u ORCHESTRATION_RUNS_DIR "$BIN_DIR/inbox-watch.sh" "$runs/t-zombie" --once --interval 0.05)
assert_contains x-watcher-strips 'unverified [peer-unknown:src-run]: queued [cur/' "$out"
assert_eq x-no-herdr-calls '' "$(cat "$MOCK_LOG")"
finish
