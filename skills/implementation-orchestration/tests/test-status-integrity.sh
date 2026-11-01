#!/usr/bin/env bash
# Invalid encodings fail closed; literal markers cannot become delimiters.
# File modes, stale temporary cleanup and nullable PR values survive writes.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
S="$BIN_DIR/status-set.sh"
mode_of() { stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1"; }
run=$SCRATCH/run; mkdir "$run"
(umask 077; "$S" "$run" init integrity int 'Preserve ledger bytes' >/dev/null)
assert_eq new-status-mode 644 "$(mode_of "$run/status.json")"
assert_eq new-ledger-mode 644 "$(mode_of "$run/ledger.md")"
chmod 640 "$run/status.json"; chmod 664 "$run/ledger.md"
"$S" "$run" node N1 title=Initial pr=42 >/dev/null
assert_eq status-mode-preserved 640 "$(mode_of "$run/status.json")"
assert_eq ledger-mode-preserved 664 "$(mode_of "$run/ledger.md")"
"$S" "$run" node N1 pr= >/dev/null; assert_eq clear-pr-exit 0 "$?"
assert_eq clear-pr-null null "$(jq -r '.nodes[0].pr|type' "$run/status.json")"
"$S" "$run" human add --all 'Reserved ID' >/dev/null 2>&1; assert_eq reserved-human-id 2 "$?"
assert_eq no-reserved-human-item 0 "$(jq '.waiting_on_human|length' "$run/status.json")"

title='latest <!-- status-matrix:end --> fragment'
"$S" "$run" node N1 "title=$title" >/dev/null
"$S" "$run" agent int-impl 'note=<!-- status-matrix:begin -->' state=open >/dev/null
"$S" "$run" meta 'workspace=<!-- status-matrix:end -->' >/dev/null
for state in implementing review fix staged review merged; do
  "$S" "$run" node N1 "state=$state" >/dev/null
done
assert_eq original-title-stored "$title" "$(jq -r '.nodes[0].title' "$run/status.json")"
assert_eq one-begin-marker 1 "$(grep -o '<!-- status-matrix:begin -->' "$run/ledger.md" | wc -l | tr -d ' ')"
assert_eq one-end-marker 1 "$(grep -o '<!-- status-matrix:end -->' "$run/ledger.md" | wc -l | tr -d ' ')"
assert_eq no-stale-node-fragments 1 "$(grep -c '^| N1 |' "$run/ledger.md")"
assert_contains cell-marker-neutralized 'latest <!- - status-matrix:end --> fragment' "$(cat "$run/ledger.md")"
assert_contains meta-marker-neutralized 'Herdr: workspace=<!- - status-matrix:end -->' "$(cat "$run/ledger.md")"

printf 'caf\xe9 latin1\n' >>"$run/ledger.md"
cp "$run/status.json" "$SCRATCH/before-status"
cp "$run/ledger.md" "$SCRATCH/before-ledger"
out=$("$S" "$run" node N1 state=dropped 2>&1); assert_eq invalid-utf8-exit 1 "$?"
assert_contains invalid-utf8-message 'ledger.md is not valid UTF-8' "$out"
cmp -s "$SCRATCH/before-status" "$run/status.json"; assert_eq invalid-utf8-keeps-status 0 "$?"
cmp -s "$SCRATCH/before-ledger" "$run/ledger.md"; assert_eq invalid-utf8-keeps-ledger 0 "$?"
other=$SCRATCH/unmarked; mkdir "$other"
printf '# Ledger\ncaf\xe9 latin1\n' >"$other/ledger.md"
cp "$other/ledger.md" "$SCRATCH/before-unmarked"
out=$("$S" "$other" init bad bad 'Invalid unmarked ledger' 2>&1); assert_eq invalid-init-exit 1 "$?"
assert_contains invalid-init-message 'ledger.md is not valid UTF-8' "$out"
absent=no; if [ ! -e "$other/status.json" ]; then absent=yes; fi
assert_eq invalid-init-no-status yes "$absent"
cmp -s "$SCRATCH/before-unmarked" "$other/ledger.md"; assert_eq invalid-init-keeps-ledger 0 "$?"

# Only a process that acquired the shared lock may remove stale temp files.
rm "$run/ledger.md"
for stem in .status .ledger .ledger-seed; do : >"$run/$stem.abcdef"; done
: >"$run/.status.keep"
mkdir "$run/.status.lock"
out=$(STATUS_LOCK_WAIT=0.2 "$S" "$run" node N1 ci=pass 2>&1); assert_eq wait-override-exit 1 "$?"
assert_contains wait-override-message 'status lock held for 0.2 s' "$out"
assert_eq foreign-temp-kept 3 "$(find "$run" -name '*.abcdef' | wc -l | tr -d ' ')"
rmdir "$run/.status.lock"
"$S" "$run" node N1 ci=pass >/dev/null
assert_eq stale-temps-removed 0 "$(find "$run" -name '*.abcdef' | wc -l | tr -d ' ')"
kept=no; if [ -f "$run/.status.keep" ]; then kept=yes; fi
assert_eq unrelated-file-kept yes "$kept"
STATUS_LOCK_WAIT=bad "$S" "$run" node N1 ci=pass >/dev/null 2>&1; assert_eq bad-wait-usage 2 "$?"
finish
