#!/usr/bin/env bash
# ledger-append.sh <ledger-file> <entry text...>
#
# Timestamped, append-only ledger write — a chronological entry costs one
# command instead of a read-modify-write of the whole file. Echoes the
# appended line back as confirmation. The orchestrator remains the ledger's
# only writer; structural edits (the status matrix, rewriting a section)
# still go through a normal editor.
set -euo pipefail

ledger=${1:?usage: ledger-append.sh <ledger-file> <entry text...>}
shift
[ $# -ge 1 ] || { echo "usage: ledger-append.sh <ledger-file> <entry text...>" >&2; exit 2; }

printf -- '- %s — %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >>"$ledger"
tail -n 1 "$ledger"
