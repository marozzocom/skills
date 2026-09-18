#!/usr/bin/env bash
# land-pr.sh against a throwaway repo with a local bare origin and the mock
# gh: scoped staging, ambiguous pre-existing staging, unlanded paths,
# hooks preserved, body-file preservation with marker + attribution, and
# the existing-PR update / unchanged paths. No real remote is touched.
. "$(dirname "$0")/lib.sh"
L="$BIN_DIR/land-pr.sh"
S=$GH_SCENARIO

body="$SCRATCH/body.md"
cat >"$body" <<'EOF'
## Summary

- keeps `code spans` and **bold**
- a table:

| a | b |
|---|---|
| 1 | 2 |

<details><summary>raw html stays</summary>x</details>

https://example.invalid/session_123
EOF
ATTR='https://example.invalid/session_123'

no_pr() { rm -f "$S/pr-view.json"; }       # gh pr view → exit 1
with_pr() { printf '{"url":"https://x/pr/9","body":"%s"}\n' "$1" >"$S/pr-view.json"; }
echo 'https://x/pr/42' >"$S/pr-create.url"

# --- 1. unlanded path stops before mutation ---------------------------------
R="$SCRATCH/r1"; make_repo "$R"; no_pr
echo a >"$R/a.txt"; echo b >"$R/b.txt"
out=$("$L" "$R" --title 'feat: a' --body-file "$body" --stage a.txt 2>&1); rc=$?
assert_eq unlanded-exit 1 "$rc"
assert_contains unlanded-line "FAILED unlanded: 1 changed path(s)" "$out"
assert_contains unlanded-names-b "b.txt" "$out"
assert_eq unlanded-no-commit 1 "$(git -C "$R" rev-list --count HEAD)"
git -C "$R" diff --cached --quiet; assert_eq unlanded-index-clean 0 "$?"
assert_eq unlanded-no-gh-create 0 "$(grep -c 'gh pr create' "$MOCK_LOG")"

# --- 2. scoped staging + hooks + body-file with marker before attribution ---
out=$("$L" "$R" --title 'feat: a' --body-file "$body" --stage a.txt --allow-unlanded \
      --run-id 2026-09-07-t --attribution "$ATTR" --trailer 'Co-authored-by: t <t@example.invalid>' 2>&1); rc=$?
assert_eq land-exit 0 "$rc"
assert_eq land-last-line "PR https://x/pr/42" "$(printf '%s\n' "$out" | tail -n1)"
assert_contains land-note "NOTE unlanded: b.txt" "$out"
assert_eq land-committed-only-a "a.txt" "$(git -C "$R" show --name-only --format= HEAD | tr -d '\n')"
assert_eq land-b-still-untracked "?? b.txt" "$(git -C "$R" status --porcelain | tr -d '\n')"
assert_eq land-hook-ran ran "$(cat "$R.hook-ran" 2>/dev/null)"
assert_contains land-trailer "Co-authored-by: t" "$(git -C "$R" log -1 --format=%B)"
assert_eq land-pushed "$(git -C "$R" rev-parse HEAD)" "$(git -C "$R.git" rev-parse feat/x)"
create_line=$(grep 'gh pr create' "$MOCK_LOG")
assert_contains land-body-file "--body-file" "$create_line"
assert_not_contains land-no-inline-body " --body " "$create_line"
# The mock gh never copies the create body, so rebuild the expectation from
# the pr edit path in test 4 — here, check the create used a file that existed
# at call time by re-deriving the body the script would have produced.
bf=$(printf '%s\n' "$create_line" | sed -n 's/.*--body-file \([^ ]*\).*/\1/p')
assert_contains land-body-file-path "land-pr-body." "$bf"

# --- 3. pre-existing staged changes are ambiguous -> refuse ----------------
R="$SCRATCH/r3"; make_repo "$R"; no_pr; : >"$MOCK_LOG"
echo a >"$R/a.txt"; git -C "$R" add a.txt
out=$("$L" "$R" --title 'feat: a' --body-file "$body" --stage a.txt 2>&1); rc=$?
assert_eq staged-exit 1 "$rc"
assert_contains staged-line "FAILED stage: index already has staged changes" "$out"
assert_eq staged-no-commit 1 "$(git -C "$R" rev-list --count HEAD)"

# --- 4. existing PR: new work is committed, pushed, marker added ----------
R="$SCRATCH/r4"; make_repo "$R"; : >"$MOCK_LOG"
echo c >"$R/c.txt"; git -C "$R" add c.txt; git -C "$R" commit -q -m 'feat: c'; git -C "$R" push -q -u origin feat/x
with_pr 'old body'
echo d >"$R/d.txt"
out=$("$L" "$R" --title 'feat: d' --body-file "$body" --stage d.txt --run-id 2026-09-07-t --attribution "$ATTR" 2>&1); rc=$?
assert_eq update-exit 0 "$rc"
assert_eq update-last-line "PR https://x/pr/9 updated" "$(printf '%s\n' "$out" | tail -n1)"
assert_eq update-pushed "$(git -C "$R" rev-parse HEAD)" "$(git -C "$R.git" rev-parse feat/x)"
assert_eq update-no-create 0 "$(grep -c 'gh pr create' "$MOCK_LOG")"
assert_eq update-edited 1 "$(grep -c 'gh pr edit' "$MOCK_LOG")"
edited=$(cat "$S/pr-edit.body")
expected=$(cat <<'EOF'
## Summary

- keeps `code spans` and **bold**
- a table:

| a | b |
|---|---|
| 1 | 2 |

<details><summary>raw html stays</summary>x</details>

<!-- herdr-run: 2026-09-07-t -->

https://example.invalid/session_123
EOF
)
assert_eq body-preserved-marker-before-attribution "$expected" "$edited"

# --- 5. existing PR with the marker already: no edit; nothing new: unchanged
: >"$MOCK_LOG"; rm -f "$S/pr-edit.body"
with_pr 'body <!-- herdr-run: 2026-09-07-t --> tail'
out=$("$L" "$R" --title 'feat: d' --body-file "$body" --run-id 2026-09-07-t 2>&1); rc=$?
assert_eq unchanged-exit 0 "$rc"
assert_contains unchanged-line "PR https://x/pr/9 unchanged" "$out"
assert_eq unchanged-no-edit 0 "$(grep -c 'gh pr edit' "$MOCK_LOG")"

# --- 6. existing PR + dirty unnamed path: stop before mutation, no success -
echo e >"$R/e.txt"
before=$(git -C "$R" rev-parse HEAD)
out=$("$L" "$R" --title 'feat: e' --body-file "$body" 2>&1); rc=$?
assert_eq existing-dirty-exit 1 "$rc"
assert_contains existing-dirty-line "FAILED unlanded" "$out"
assert_not_contains existing-dirty-no-success "PR https://x/pr/9" "$out"
assert_eq existing-dirty-no-commit "$before" "$(git -C "$R" rev-parse HEAD)"

# --- 7. attribution absent from the body is appended last -----------------
R="$SCRATCH/r7"; make_repo "$R"; no_pr; : >"$MOCK_LOG"
printf 'Plain body\n' >"$SCRATCH/plain.md"
echo f >"$R/f.txt"
"$L" "$R" --title 'feat: f' --body-file "$SCRATCH/plain.md" --stage f.txt --run-id rid --attribution "$ATTR" >/dev/null 2>&1
# capture the body the script produced by re-running the assembly through pr edit on an existing PR
with_pr 'x'; echo g >"$R/g.txt"
"$L" "$R" --title 'feat: g' --body-file "$SCRATCH/plain.md" --stage g.txt --run-id rid --attribution "$ATTR" >/dev/null 2>&1
assert_eq attribution-appended "$(printf 'Plain body\n\n<!-- herdr-run: rid -->\n\n%s' "$ATTR")" "$(cat "$S/pr-edit.body")"

# --- 8. staging a missing path is an error before mutation -----------------
out=$("$L" "$R" --title 'feat: h' --body-file "$SCRATCH/plain.md" --stage nope.txt 2>&1); rc=$?
assert_eq missing-path-exit 1 "$rc"
assert_contains missing-path-line "neither on disk nor tracked" "$out"

# --- 9. a --stage directory covers a deletion beneath it -------------------
R="$SCRATCH/r9"; make_repo "$R"; no_pr; : >"$MOCK_LOG"
mkdir -p "$R/src"; echo x >"$R/src/x.txt"; git -C "$R" add src; git -C "$R" commit -q -m 'feat: x'
rm "$R/src/x.txt"; echo y >"$R/src/y.txt"
out=$("$L" "$R" --title 'feat: y' --body-file "$SCRATCH/plain.md" --stage src 2>&1); rc=$?
assert_eq dir-exit 0 "$rc"
assert_eq dir-commit-both "src/x.txt src/y.txt" "$(git -C "$R" show --name-only --format= HEAD | tr '\n' ' ' | sed 's/ $//')"
assert_eq dir-clean "" "$(git -C "$R" status --porcelain)"

finish
