#!/usr/bin/env bash
# Locked writes, state clocks, argument validation and lossless ledger refresh.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
S="$BIN_DIR/status-set.sh"
run="$SCRATCH/run with spaces"; mkdir "$run"
export STATUS_NOW=2026-11-01T10:00:00Z
out=$("$S" "$run" init example ex "A goal with spaces"); rc=$?
assert_eq init-exit 0 "$rc"
assert_eq confirmation-lines 1 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
assert_eq init-goal 'A goal with spaces' "$(jq -r .goal "$run/status.json")"
assert_eq init-arrays '[[],[],[],[]]' "$(jq -c '[.waiting_on_human,.milestones,.nodes,.agents]' "$run/status.json")"
assert_contains init-ledger-heading '# Ledger — example' "$(cat "$run/ledger.md")"
assert_contains init-ledger-markers '<!-- status-matrix:begin -->' "$(cat "$run/ledger.md")"
assert_contains init-ledger-rendered '| node | title | state | PR | CI |' "$(cat "$run/ledger.md")"
assert_contains init-ledger-entries '## Entries' "$(cat "$run/ledger.md")"
cp "$run/status.json" "$SCRATCH/original"
"$S" "$run" init other no overwrite >/dev/null 2>&1
assert_eq init-refuses-overwrite 1 "$?"
cmp -s "$run/status.json" "$SCRATCH/original"; assert_eq overwrite-unchanged 0 "$?"
"$S" "$run" milestone M1 'title=Frame and agree' state=active >/dev/null
"$S" "$run" node N1 'title=Build helper' state=briefed pr=42 ci=pending 'proof=https://x/?a=b=c' tab=w1:t2 >/dev/null
"$S" "$run" agent ex-impl role=implementer node=N1 tab=w1:t2 pane=w1:p2 'pin=model high' transport=delegate 'note=one=two three' state=open >/dev/null
assert_eq milestone-state active "$(jq -r '.milestones[0].state' "$run/status.json")"
assert_eq numeric-pr number "$(jq -r '.nodes[0].pr|type' "$run/status.json")"
assert_eq first-equals 'https://x/?a=b=c' "$(jq -r '.nodes[0].proof' "$run/status.json")"
assert_eq agent-fields 'implementer|N1|w1:t2|w1:p2|model high|delegate|one=two three' "$(jq -r '.agents[0]|[.role,.node,.tab,.pane,.pin,.transport,.note]|join("|")' "$run/status.json")"
assert_eq new-state-since "$STATUS_NOW" "$(jq -r '.agents[0].since' "$run/status.json")"
export STATUS_NOW=2026-11-01T10:05:00Z
"$S" "$run" node N1 'title=New title' state=briefed ci=pass >/dev/null
"$S" "$run" agent ex-impl 'note=Edited note' >/dev/null
"$S" "$run" milestone M1 'title=Edited milestone' >/dev/null
assert_eq updated-every-write "$STATUS_NOW" "$(jq -r .updated "$run/status.json")"
for col in nodes agents milestones; do
  assert_eq "same-state-since-$col" 2026-11-01T10:00:00Z "$(jq -r ".${col}[0].since" "$run/status.json")"
done
"$S" "$run" node N1 state=implementing >/dev/null
"$S" "$run" agent ex-impl state=closed >/dev/null
"$S" "$run" milestone M1 state=done >/dev/null
for col in nodes agents milestones; do
  assert_eq "changed-state-since-$col" "$STATUS_NOW" "$(jq -r ".${col}[0].since" "$run/status.json")"
done
cp "$run/status.json" "$SCRATCH/valid"
for args in 'milestone M1 state=review' 'node N1 state=active' 'agent ex-impl state=working' 'node N1 ci=green' 'node N1 pr=https://x' 'node N1 unknown=x' 'agent ex-impl since=x' 'node N1 nosplit'; do
  # Intentional word splitting: these invalid fixtures contain no spaces.
  # shellcheck disable=SC2086
  "$S" "$run" $args >/dev/null 2>&1
  assert_eq "reject-$args" 2 "$?"
done
cmp -s "$run/status.json" "$SCRATCH/valid"; assert_eq invalid-does-not-write 0 "$?"
"$S" "$run" human add H1 'Approve deploy = yes' >/dev/null
"$S" "$run" human add H2 'Review PR' >/dev/null
assert_eq human-two 2 "$(jq '.waiting_on_human|length' "$run/status.json")"
export STATUS_NOW=2026-11-01T10:10:00Z
"$S" "$run" human add H1 'Approve new deploy' >/dev/null
assert_eq human-update-age 2026-11-01T10:05:00Z "$(jq -r '.waiting_on_human[0].since' "$run/status.json")"
assert_eq human-update-action 'Approve new deploy' "$(jq -r '.waiting_on_human[0].action' "$run/status.json")"
"$S" "$run" human clear H1 >/dev/null
assert_eq human-clear-one H2 "$(jq -r '.waiting_on_human[].id' "$run/status.json")"
"$S" "$run" human clear --all >/dev/null
assert_eq human-clear-all 0 "$(jq '.waiting_on_human|length' "$run/status.json")"
"$S" "$run" meta workspace=w1 cockpit_tab=w1:t1 overseer_pane=w1:p1 board_pane=w1:p2 >/dev/null
assert_eq meta-recorded '{"workspace":"w1","cockpit_tab":"w1:t1","overseer_pane":"w1:p1","board_pane":"w1:p2"}' "$(jq -c .herdr "$run/status.json")"
assert_contains meta-in-ledger 'Herdr: workspace=w1' "$(cat "$run/ledger.md")"
"$S" "$run" meta 'board_pane=a=b c' >/dev/null
assert_eq meta-first-equals 'a=b c' "$(jq -r .herdr.board_pane "$run/status.json")"
"$S" "$run" meta unknown=x >/dev/null 2>&1; assert_eq meta-unknown-key 2 "$?"
"$S" "$run" meta >/dev/null 2>&1; assert_eq meta-no-fields 2 "$?"
"$S" "$run" milestone M2 'title=Default state' >/dev/null
assert_eq default-state pending "$(jq -r '.milestones[1].state' "$run/status.json")"
# Include CRLF and no final newline to catch line-oriented rewrites.
printf 'prefix — 界\r\nunchanged\n<!-- status-matrix:begin -->old\n<!-- status-matrix:end -->\nsuffix\r\nno final newline' >"$run/ledger.md"
cp "$run/ledger.md" "$SCRATCH/before-ledger"
"$S" "$run" node N1 state=review >/dev/null
assert_contains matrix-header '| agent | role | transport | pin | node | tab | state | note |' "$(cat "$run/ledger.md")"
assert_contains nodes-matrix '| N1 | New title | review | 42 | pass |' "$(cat "$run/ledger.md")"
for which in before after; do
  path=$SCRATCH/before-ledger; [ "$which" = before ] || path=$run/ledger.md
  jq -jRs 'split("<!-- status-matrix:begin -->")[0]' "$path" >"$SCRATCH/$which-prefix"
  jq -jRs 'split("<!-- status-matrix:end -->")[1]' "$path" >"$SCRATCH/$which-suffix"
done
cmp -s "$SCRATCH/before-prefix" "$SCRATCH/after-prefix"; assert_eq prefix-byte-identical 0 "$?"
cmp -s "$SCRATCH/before-suffix" "$SCRATCH/after-suffix"; assert_eq suffix-byte-identical 0 "$?"
cp "$run/ledger.md" "$SCRATCH/rendered"
"$S" "$run" node N1 state=review >/dev/null
cmp -s "$SCRATCH/rendered" "$run/ledger.md"; assert_eq matrix-idempotent 0 "$?"
cp "$run/status.json" "$SCRATCH/before-error"
printf '<!-- status-matrix:end -->\n<!-- status-matrix:begin -->\n' >"$run/ledger.md"
"$S" "$run" node N1 state=merged >/dev/null 2>&1; assert_eq render-failure-exit 1 "$?"
cmp -s "$SCRATCH/before-error" "$run/status.json"; assert_eq render-failure-keeps-status 0 "$?"
printf 'no markers\nunchanged' >"$run/ledger.md"
"$S" "$run" node N1 ci=fail >/dev/null
assert_eq unmarked-untouched $'no markers\nunchanged' "$(cat "$run/ledger.md")"
mkdir "$run/.status.lock"
SECONDS=0
out=$("$S" "$run" node N1 ci=pass 2>&1); rc=$?; elapsed=$SECONDS
assert_eq held-lock-exit 1 "$rc"
assert_contains lock-recovery "status lock held for 5 s — another writer may be running; if none is, remove $run/.status.lock" "$out"
bounded=no; if [ "$elapsed" -ge 4 ] && [ "$elapsed" -le 8 ]; then bounded=yes; fi
assert_eq lock-bounded yes "$bounded"
held=no; if [ -d "$run/.status.lock" ]; then held=yes; fi
assert_eq foreign-lock-preserved yes "$held"
rmdir "$run/.status.lock"
"$S" "$run" milestone M3 state=pending >/dev/null & p1=$!
"$S" "$run" milestone M4 state=pending >/dev/null & p2=$!
wait "$p1"; assert_eq concurrent-first 0 "$?"
wait "$p2"; assert_eq concurrent-second 0 "$?"
assert_eq no-lost-update 4 "$(jq '.milestones|length' "$run/status.json")"
released=no; if [ ! -d "$run/.status.lock" ]; then released=yes; fi
assert_eq own-lock-released yes "$released"
# init inserts a matrix after the first line of an existing unmarked ledger.
other=$SCRATCH/old-ledger; mkdir "$other"
printf '# Existing — notes\r\nkeep this body\r\nno final newline' >"$other/ledger.md"
"$S" "$other" init old old 'Keep old entries' >/dev/null
assert_eq inserted-after-first-line '# Existing — notes' "$(head -n1 "$other/ledger.md" | tr -d '\r')"
assert_contains inserted-markers '<!-- status-matrix:begin -->' "$(cat "$other/ledger.md")"
assert_contains inserted-body $'keep this body\r\nno final newline' "$(cat "$other/ledger.md")"
# init of an already marked ledger changes only the marker interior.
marked=$SCRATCH/marked-ledger; mkdir "$marked"
cp "$SCRATCH/before-ledger" "$marked/ledger.md"
"$S" "$marked" init marked mark 'Existing markers' >/dev/null
jq -jRs 'split("<!-- status-matrix:begin -->")[0]' "$marked/ledger.md" >"$SCRATCH/init-prefix"
jq -jRs 'split("<!-- status-matrix:end -->")[1]' "$marked/ledger.md" >"$SCRATCH/init-suffix"
cmp -s "$SCRATCH/before-prefix" "$SCRATCH/init-prefix"; assert_eq init-prefix-identical 0 "$?"
cmp -s "$SCRATCH/before-suffix" "$SCRATCH/init-suffix"; assert_eq init-suffix-identical 0 "$?"
# Captured valid UTF-8 that macOS iconv rejects: preserve both outer slices
# through init and a later matrix rewrite, using the fixture's exact bytes.
repro=$SCRATCH/utf8-reproducer; mkdir "$repro"
cp "$TESTS_DIR/fixtures/utf8-valid-iconv-false-reject.md" "$repro/ledger.md"
for part in prefix suffix; do
  filter='split("<!-- status-matrix:begin -->")[0]'
  [ "$part" != suffix ] || filter='split("<!-- status-matrix:end -->")[1]'
  jq -jRs "$filter" "$repro/ledger.md" >"$SCRATCH/repro-$part"
done
"$S" "$repro" init repro repro 'Valid UTF-8 regression' >/dev/null
assert_eq utf8-reproducer-init 0 "$?"
for phase in init node; do
  if [ "$phase" = node ]; then
    "$S" "$repro" node N1 'title=Rewritten matrix' state=review >/dev/null
    assert_eq utf8-reproducer-node 0 "$?"
  fi
  for part in prefix suffix; do
    filter='split("<!-- status-matrix:begin -->")[0]'
    [ "$part" != suffix ] || filter='split("<!-- status-matrix:end -->")[1]'
    jq -jRs "$filter" "$repro/ledger.md" >"$SCRATCH/repro-current-$part"
    cmp -s "$SCRATCH/repro-$part" "$SCRATCH/repro-current-$part"
    assert_eq "utf8-$phase-$part-byte-identical" 0 "$?"
  done
done
empty=$SCRATCH/empty-ledger; mkdir "$empty"
: >"$empty/ledger.md"
"$S" "$empty" init empty empty 'Empty ledger' >/dev/null
assert_eq empty-ledger-init 0 "$?"
"$S" "$empty" node N1 state=planned >/dev/null
assert_eq empty-ledger-node 0 "$?"
assert_eq empty-ledger-markers 1 "$(grep -c '^<!-- status-matrix:end -->$' "$empty/ledger.md")"
# App identity and flavor metadata keep the physical pane separate.
"$S" "$empty" meta flavor=app overseer_id=t1 overseer_pane=pa1 >/dev/null
assert_eq app-flavor app "$(jq -r .herdr.flavor "$empty/status.json")"
assert_eq app-distinct-id 't1|pa1' "$(jq -r '.herdr|[.overseer_id,.overseer_pane]|join("|")' "$empty/status.json")"
"$S" "$empty" meta flavor=other >/dev/null 2>&1; assert_eq app-invalid-flavor 2 "$?"
finish
