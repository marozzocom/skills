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
finish
