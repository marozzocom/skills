#!/usr/bin/env bash
# tests/lib.sh — sourced by every test: assertions, a scratch dir, and the
# mock `gh` / `herdr` binaries. Bash 3.2 compatible (no mapfile, no
# associative arrays, no ${var,,}).
set -u

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC2034  # used by the sourcing tests
BIN_DIR=$(cd "$TESTS_DIR/../bin" && pwd)
SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/di-tests.XXXXXX")
MOCK_BIN="$SCRATCH/mockbin"
MOCK_LOG="$SCRATCH/mock.log"
mkdir -p "$MOCK_BIN"
: >"$MOCK_LOG"
trap 'rm -rf "$SCRATCH"' EXIT

_failures=0
_checks=0
assert_eq() { # <label> <expected> <actual>
  _checks=$((_checks + 1))
  if [ "$2" = "$3" ]; then return 0; fi
  _failures=$((_failures + 1))
  printf 'ASSERT %s: expected %q, got %q\n' "$1" "$2" "$3" >&2
  return 1
}
assert_contains() { # <label> <needle> <haystack>
  _checks=$((_checks + 1))
  case $3 in *"$2"*) return 0 ;; esac
  _failures=$((_failures + 1))
  printf 'ASSERT %s: %q not found in:\n%s\n' "$1" "$2" "$3" >&2
  return 1
}
assert_not_contains() { # <label> <needle> <haystack>
  _checks=$((_checks + 1))
  case $3 in *"$2"*)
    _failures=$((_failures + 1))
    printf 'ASSERT %s: %q unexpectedly found in:\n%s\n' "$1" "$2" "$3" >&2
    return 1 ;;
  esac
  return 0
}
finish() {
  if [ "$_failures" = 0 ]; then echo "$_checks checks ok"; exit 0; fi
  echo "$_failures of $_checks checks failed" >&2; exit 1
}

# --- mock gh ---------------------------------------------------------------
# Scenario-driven: the test writes response files into $GH_SCENARIO and the
# mock answers from them, logging every invocation to $MOCK_LOG.
#   $GH_SCENARIO/pr-view.json      → `gh pr view ... --json ...` body
#   $GH_SCENARIO/pr-view.exit      → exit code for pr view (default 0)
#   $GH_SCENARIO/pr-view.sequence  → one file name per line; each pr view
#                                    call consumes the next line (a rolling
#                                    cursor lives in pr-view.cursor)
#   $GH_SCENARIO/mode              → "inline" (default) | "file" | "file-quiet"
#     file       = print the JSON's file path instead of the JSON
#     file-quiet = like file, but print nothing at all on a non-zero exit
#   $GH_SCENARIO/pr-create.url     → url printed by `gh pr create`
GH_SCENARIO="$SCRATCH/gh-scenario"
mkdir -p "$GH_SCENARIO"
cat >"$MOCK_BIN/gh" <<'MOCK'
#!/usr/bin/env bash
set -u
S=${GH_SCENARIO:?}
printf 'gh %s\n' "$*" >>"${MOCK_LOG:?}"
mode=inline; [ -f "$S/mode" ] && mode=$(cat "$S/mode")
emit_json() { # <file> <exit>
  local f=$1 rc=$2
  if [ "$mode" = inline ]; then
    [ "$rc" = 0 ] && cat "$f"
  elif [ "$mode" = file ]; then
    printf '%s\n' "$f"
  elif [ "$mode" = file-quiet ]; then
    [ "$rc" = 0 ] && printf '%s\n' "$f"
  fi
  exit "$rc"
}
case "$1 $2" in
  "pr view")
    f="$S/pr-view.json"
    if [ -f "$S/pr-view.sequence" ]; then
      cur=0; [ -f "$S/pr-view.cursor" ] && cur=$(cat "$S/pr-view.cursor")
      total=$(wc -l <"$S/pr-view.sequence" | tr -d ' ')
      idx=$((cur + 1)); [ "$idx" -gt "$total" ] && idx=$total
      echo "$idx" >"$S/pr-view.cursor"
      name=$(sed -n "${idx}p" "$S/pr-view.sequence")
      f="$S/$name"
    fi
    rc=0; [ -f "${f%.json}.exit" ] && rc=$(cat "${f%.json}.exit")
    [ -f "$f" ] || rc=1
    emit_json "$f" "$rc" ;;
  "pr create")
    if [ -f "$S/pr-create.url" ]; then cat "$S/pr-create.url"; exit 0; fi
    echo "mock gh: pr create not configured" >&2; exit 1 ;;
  "pr edit")
    # record the body file's content so the test can inspect it
    while [ $# -gt 0 ]; do
      if [ "$1" = --body-file ]; then cp "$2" "$S/pr-edit.body"; fi
      shift
    done
    exit 0 ;;
  "pr merge") exit 0 ;;
  *) echo "mock gh: unhandled: $*" >&2; exit 1 ;;
esac
MOCK
chmod +x "$MOCK_BIN/gh"

# --- mock herdr --------------------------------------------------------------
#   $HERDR_SCENARIO/agents.json → `herdr agent list` output
#   $HERDR_SCENARIO/pane.txt    → full pane text; `agent read --lines N`
#                                 returns its last N lines. A read without
#                                 --lines is logged as UNBOUNDED.
HERDR_SCENARIO="$SCRATCH/herdr-scenario"
mkdir -p "$HERDR_SCENARIO"
cat >"$MOCK_BIN/herdr" <<'MOCK'
#!/usr/bin/env bash
set -u
S=${HERDR_SCENARIO:?}
printf 'herdr %s\n' "$*" >>"${MOCK_LOG:?}"
case "$1 $2" in
  "agent list") cat "$S/agents.json" ;;
  "agent read")
    lines=''
    while [ $# -gt 0 ]; do
      if [ "$1" = --lines ]; then lines=$2; fi
      shift
    done
    if [ -z "$lines" ]; then echo "UNBOUNDED read" >>"${MOCK_LOG:?}"; cat "$S/pane.txt"; exit 0; fi
    tail -n "$lines" "$S/pane.txt" ;;
  *) echo "mock herdr: unhandled: $*" >&2; exit 1 ;;
esac
MOCK
chmod +x "$MOCK_BIN/herdr"

export PATH="$MOCK_BIN:$PATH" GH_SCENARIO HERDR_SCENARIO MOCK_LOG

# --- git fixture -------------------------------------------------------------
# make_repo <dir>: a repo on branch feat/x with one commit, tracking a
# local bare origin whose HEAD is main. Hooks: a pre-commit that records it
# ran, so tests can prove hooks were preserved.
make_repo() {
  local dir=$1 bare="$1.git"
  git init -q -b main "$dir" 2>/dev/null || { git init -q "$dir" && git -C "$dir" checkout -q -b main; }
  git -C "$dir" config user.email t@example.invalid
  git -C "$dir" config user.name tests
  git -C "$dir" config commit.gpgsign false
  echo base >"$dir/README.md"
  git -C "$dir" add README.md
  git -C "$dir" commit -q -m "chore: base"
  git init -q --bare "$bare"
  git -C "$dir" remote add origin "$bare"
  git -C "$dir" push -q -u origin main
  git -C "$bare" symbolic-ref HEAD refs/heads/main
  git -C "$dir" remote set-head origin main
  git -C "$dir" checkout -q -b feat/x
  mkdir -p "$dir/.git/hooks"
  cat >"$dir/.git/hooks/pre-commit" <<H
#!/bin/sh
echo ran >>"$dir.hook-ran"
exit 0
H
  chmod +x "$dir/.git/hooks/pre-commit"
}
