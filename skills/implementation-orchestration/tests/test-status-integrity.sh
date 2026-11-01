#!/usr/bin/env bash
# Invalid encodings fail closed; literal markers cannot become delimiters.
# File modes, stale temporary cleanup and nullable PR values survive writes.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
S="$BIN_DIR/status-set.sh"
mode_of() { stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1"; }
run=$SCRATCH/run; mkdir "$run"
(umask 077; "$S" "$run" init integrity int 'Preserve ledger bytes' >/dev/null)
assert_eq new-status-mode-077 600 "$(mode_of "$run/status.json")"
assert_eq new-ledger-mode-077 600 "$(mode_of "$run/ledger.md")"
public=$SCRATCH/public; mkdir "$public"
(umask 022; "$S" "$public" init public pub 'Default file modes' >/dev/null)
assert_eq new-status-mode-022 644 "$(mode_of "$public/status.json")"
assert_eq new-ledger-mode-022 644 "$(mode_of "$public/ledger.md")"
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

# Both init and later writes reject a directory without replacing any state.
nonfile=$SCRATCH/nonfile; mkdir -p "$nonfile/ledger.md"
: >"$nonfile/ledger.md/keep"
out=$("$S" "$nonfile" init nonfile nf 'Directory ledger' 2>&1); assert_eq directory-init-exit 1 "$?"
assert_contains directory-init-message 'ledger.md is not a regular file' "$out"
absent=no; if [ ! -e "$nonfile/status.json" ]; then absent=yes; fi
assert_eq directory-init-no-status yes "$absent"
cp "$run/status.json" "$nonfile/status.json"
out=$("$S" "$nonfile" node N1 state=dropped 2>&1); assert_eq directory-node-exit 1 "$?"
assert_contains directory-node-message 'ledger.md is not a regular file' "$out"
cmp -s "$run/status.json" "$nonfile/status.json"; assert_eq directory-keeps-status 0 "$?"
assert_eq directory-contents-kept keep "$(ls -A "$nonfile/ledger.md")"
assert_eq directory-no-temps 0 "$(find "$nonfile" -name '*.tmp.??????' | wc -l | tr -d ' ')"
released=no; if [ ! -d "$nonfile/.status.lock" ]; then released=yes; fi
assert_eq directory-lock-released yes "$released"

# Reject links before init or update can replace them or change their targets.
for name in status.json ledger.md; do
  for kind in regular dangling; do
    for operation in init node; do
      linked=$SCRATCH/link-$name-$kind-$operation; mkdir -p "$linked/real"
      cp "$run/status.json" "$linked/real/status.json"
      cp "$run/ledger.md" "$linked/real/ledger.md"
      cp "$run/status.json" "$linked/status.json"
      cp "$run/ledger.md" "$linked/ledger.md"
      rm "$linked/$name"
      target=real/$name; if [ "$kind" = dangling ]; then target=real/missing; fi
      ln -s "$target" "$linked/$name"
      if [ "$operation" = init ]; then
        if [ "$name" = ledger.md ]; then rm "$linked/status.json"; fi
        out=$("$S" "$linked" init links link 'Reject links' 2>&1); rc=$?
      else
        out=$("$S" "$linked" node N1 state=dropped 2>&1); rc=$?
      fi
      label=$name-$kind-$operation
      assert_eq "$label-exit" 1 "$rc"
      assert_contains "$label-message" "$name is not a regular file" "$out"
      assert_eq "$label-link-kept" "$target" "$(readlink "$linked/$name")"
      for original in status.json ledger.md; do
        cmp -s "$run/$original" "$linked/real/$original"; assert_eq "$label-target-$original-kept" 0 "$?"
        if [ "$original" != "$name" ]; then
          if [ "$operation:$original" = init:status.json ]; then
            absent=no; if [ ! -e "$linked/status.json" ]; then absent=yes; fi
            assert_eq "$label-no-status-created" yes "$absent"
          else
            cmp -s "$run/$original" "$linked/$original"; assert_eq "$label-$original-kept" 0 "$?"
          fi
        fi
      done
      released=no; if [ ! -d "$linked/.status.lock" ]; then released=yes; fi
      assert_eq "$label-lock-released" yes "$released"
      assert_eq "$label-no-temps" 0 "$(find "$linked" -name '*.tmp.??????' | wc -l | tr -d ' ')"
    done
  done
done

# Root can read chmod 000 files, so the permission case applies to non-root.
if [ "$(id -u)" != 0 ]; then
  cp "$run/status.json" "$SCRATCH/before-unreadable-status"
  cp "$run/ledger.md" "$SCRATCH/before-unreadable-ledger"
  chmod 000 "$run/ledger.md"
  out=$("$S" "$run" node N1 state=dropped 2>&1); assert_eq unreadable-exit 1 "$?"
  chmod 664 "$run/ledger.md"
  assert_contains unreadable-message 'ledger.md is unreadable or not valid UTF-8; fix it before the matrix is re-rendered' "$out"
  cmp -s "$SCRATCH/before-unreadable-status" "$run/status.json"; assert_eq unreadable-keeps-status 0 "$?"
  cmp -s "$SCRATCH/before-unreadable-ledger" "$run/ledger.md"; assert_eq unreadable-keeps-ledger 0 "$?"
fi

# Only the first begin and the first end after it delimit the replacement.
printf 'prefix 界\r\n<!-- status-matrix:end -->\000' >"$SCRATCH/repeated-prefix"
printf '<!-- status-matrix:end -->suffix\r\n<!-- status-matrix:begin -->unchanged<!-- status-matrix:end -->' >"$SCRATCH/repeated-suffix"
{ cat "$SCRATCH/repeated-prefix"; printf '<!-- status-matrix:begin -->old<!-- status-matrix:begin -->interior'; cat "$SCRATCH/repeated-suffix"; } >"$run/ledger.md"
"$S" "$run" node N1 title=Replacement >/dev/null
{ cat "$SCRATCH/repeated-prefix"; printf '<!-- status-matrix:begin -->\n\n'; } >"$SCRATCH/expected-prefix"
prefix_size=$(wc -c <"$SCRATCH/expected-prefix" | tr -d ' ')
head -c "$prefix_size" "$run/ledger.md" >"$SCRATCH/actual-prefix"
cmp -s "$SCRATCH/expected-prefix" "$SCRATCH/actual-prefix"; assert_eq first-begin-prefix-kept 0 "$?"
suffix_size=$(wc -c <"$SCRATCH/repeated-suffix" | tr -d ' ')
tail -c "$suffix_size" "$run/ledger.md" >"$SCRATCH/actual-suffix"
cmp -s "$SCRATCH/repeated-suffix" "$SCRATCH/actual-suffix"; assert_eq first-end-suffix-kept 0 "$?"
assert_not_contains repeated-begin-interior-removed '>interior' "$(cat "$run/ledger.md")"

printf 'caf\xe9 latin1\n' >>"$run/ledger.md"
cp "$run/status.json" "$SCRATCH/before-status"
cp "$run/ledger.md" "$SCRATCH/before-ledger"
out=$("$S" "$run" node N1 state=dropped 2>&1); assert_eq invalid-utf8-exit 1 "$?"
assert_contains invalid-utf8-message 'ledger.md is unreadable or not valid UTF-8; fix it before the matrix is re-rendered' "$out"
cmp -s "$SCRATCH/before-status" "$run/status.json"; assert_eq invalid-utf8-keeps-status 0 "$?"
cmp -s "$SCRATCH/before-ledger" "$run/ledger.md"; assert_eq invalid-utf8-keeps-ledger 0 "$?"
other=$SCRATCH/unmarked; mkdir "$other"
printf '# Ledger\ncaf\xe9 latin1\n' >"$other/ledger.md"
cp "$other/ledger.md" "$SCRATCH/before-unmarked"
out=$("$S" "$other" init bad bad 'Invalid unmarked ledger' 2>&1); assert_eq invalid-init-exit 1 "$?"
assert_contains invalid-init-message 'ledger.md is unreadable or not valid UTF-8; fix it before the matrix is re-rendered' "$out"
absent=no; if [ ! -e "$other/status.json" ]; then absent=yes; fi
assert_eq invalid-init-no-status yes "$absent"
cmp -s "$SCRATCH/before-unmarked" "$other/ledger.md"; assert_eq invalid-init-keeps-ledger 0 "$?"

# Only a process that acquired the shared lock may remove stale temp files.
rm "$run/ledger.md"
for stem in .status-set.tmp .ledger.tmp .ledger-seed.tmp; do : >"$run/$stem.abcdef"; done
: >"$run/.status.keep"
for name in .status.backup .ledger.mirror .status-set.tmp.short .ledger.tmp.toolong; do : >"$run/$name"; done
mkdir "$run/.status.lock"
out=$(STATUS_LOCK_WAIT=0.2 "$S" "$run" node N1 ci=pass 2>&1); assert_eq wait-override-exit 1 "$?"
assert_contains wait-override-message 'status lock held for 0.2 s' "$out"
assert_eq foreign-temp-kept 3 "$(find "$run" -name '*.abcdef' | wc -l | tr -d ' ')"
rmdir "$run/.status.lock"
"$S" "$run" node N1 ci=pass >/dev/null
assert_eq stale-temps-removed 0 "$(find "$run" -name '*.abcdef' | wc -l | tr -d ' ')"
kept=no; if [ -f "$run/.status.keep" ]; then kept=yes; fi
assert_eq unrelated-file-kept yes "$kept"
for name in .status.backup .ledger.mirror .status-set.tmp.short .ledger.tmp.toolong; do
  kept=no; if [ -f "$run/$name" ]; then kept=yes; fi
  assert_eq "unrelated-$name-kept" yes "$kept"
done
mkdir "$run/.ledger.tmp.dirdir"
out=$("$S" "$run" node N1 ci=pass 2>&1); assert_eq temp-directory-write-exit 0 "$?"
assert_contains temp-directory-write-confirmed 'status updated: node' "$out"
assert_not_contains temp-directory-no-cleanup-noise 'rm:' "$out"
kept=no; if [ -d "$run/.ledger.tmp.dirdir" ]; then kept=yes; fi
assert_eq temp-directory-kept yes "$kept"
STATUS_LOCK_WAIT=bad "$S" "$run" node N1 ci=pass >/dev/null 2>&1; assert_eq bad-wait-usage 2 "$?"
finish
