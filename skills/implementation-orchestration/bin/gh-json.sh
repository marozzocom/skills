#!/usr/bin/env bash
# gh-json.sh — sourced helper: run a `gh` command that returns JSON and
# print the JSON to stdout, whether the gh in PATH is the native CLI (which
# prints the JSON inline) or a wrapper that writes the JSON to a file and
# prints the file's path instead.
#
#   . "$(dirname "$0")/gh-json.sh"
#   json=$(gh_json pr view 12 --repo o/r --json statusCheckRollup) || ...
#
# Exit: 0 with JSON on stdout when the command succeeded and produced JSON
# (inline or via a readable file path); 1 otherwise — the caller decides
# whether that is a transport failure to retry or a "no such object" answer.
# `GH` overrides the binary (tests point it at a mock).

gh_json() {
  local out rc
  out=$("${GH:-gh}" "$@" 2>/dev/null); rc=$?
  [ "$rc" -eq 0 ] || return 1
  gh_json_normalize "$out"
}

# Normalize one gh result: inline JSON is echoed as-is; a single line naming
# an existing readable file is replaced by that file's content. Anything
# else is a failure (an empty result, a wrapper's error text, an unreadable
# path) so the caller never parses prose as JSON.
gh_json_normalize() {
  local out=$1 trimmed
  trimmed=${out#"${out%%[![:space:]]*}"}
  case $trimmed in
    '') return 1 ;;
    '{'*|'['*) printf '%s\n' "$out"; return 0 ;;
  esac
  case $out in
    *$'\n'*) return 1 ;;
  esac
  [ -r "$out" ] || return 1
  cat "$out"
}
