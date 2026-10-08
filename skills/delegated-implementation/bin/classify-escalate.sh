#!/usr/bin/env bash
# classify-escalate.sh [--raw-out FILE] [--diag-dir DIR] SET STATE -- TRANSPORT [ARGS...]
# classify-escalate.sh --check SET [...]
# Offline, vendor-neutral policy wrapper: the transport receives one request
# path, emits raw JSON, and exits nonzero on failure. Incomplete or invalid
# responses escalate every question; a classifier can only add scrutiny.
# noul is probability of "yes"; choice/score confidence is the service's
# certainty in its own answer. These are distinct quantities and policy keys.
# STATE is a file containing one non-empty JSON string/object/array; - reads
# it from stdin. --check validates sets without invoking any transport.
# Per-question stdout is tab-separated, in set order (V = ESCALATE|NO-SIGNAL):
#   V <id> noul p=<value> rule=at_or_above:<threshold>
#   V <id> choice choice=<value> confidence=<value> rule=<matched rules|none>
#   V <id> score score=<value> confidence=<value> rule=<matched rules|none>
# Matched rules are on, at_or_above:<threshold>, below_confidence:<threshold>,
# joined with | when both apply. Failures print for every question:
#   ESCALATE <id> <type> fail-closed: <reason>
# Usage/set/state/dependency errors print ESCALATE * fail-closed: <reason>.
# The last stdout line is:
#   # set=<set>@<revision> calibration=<c|unstated> model=<model|unknown> in=<n|?> out=<n|?> diag=<dir>
# Token counts use usage.input_tokens/output_tokens; invalid responses use
# unknown/?. Control characters are TSV-escaped; numbers are not rounded.
# Diagnostics are never deleted: request.json, response.raw, transport.stderr,
# transport.exit, response.json (normalized), decisions.tsv. A missing transport
# is rejected before request.json is written; transport.exit records 127.
# New directories are private (700), files 600. Existing directories must be
# owned by the current user with no group/other permissions; their mode is
# never changed. --raw-out additionally copies response.raw byte-for-byte.
# Transport failure also prints transport stderr: <diag>/transport.stderr
# on stderr. Only exit 0 is a valid all-NO-SIGNAL result: 1 valid/escalation,
# 2 usage/set/state error, 3 transport/response/dependency failure.
set -Eeuo pipefail
umask 077

fatal() {
  local code=$1; shift
  printf 'classify-escalate.sh: %s\n' "$*" >&2
  printf 'ESCALATE\t*\tfail-closed: %s\n' "$*"
  exit "$code"
}
trap 'fatal 3 "local operation failed at line $LINENO (exit $?)"' ERR
for dependency in jq mktemp; do
  command -v "$dependency" >/dev/null 2>&1 || fatal 3 "missing dependency: $dependency (required to validate classifier responses)"
done

# Return the first structural violation. Guards precede all type-dependent
# operations so malformed input yields a concrete reason, never a jq crash.
# shellcheck disable=SC2016 # jq variables and interpolation belong to jq, not bash.
set_filter='
def keys_in($allowed): (keys - $allowed | length) == 0;
def unit: type == "number" and . >= 0 and . <= 1;
def nonempty_string: type == "string" and length > 0;
def instructions_ok:
  if type == "string" then test("\\S")
  elif type == "object" or type == "array" then length > 0
  else false end;
def question_error($id):
  if type != "object" then "question is not an object: \($id)"
  elif (keys_in(["type","instructions","criteria","escalate"]) | not) then "unknown question key: \($id)"
  else . as $q |
    if (["noul","choice","score"] | index($q.type)) == null then "invalid question type: \($id)"
    elif (.instructions | instructions_ok | not) then "invalid instructions: \($id)"
    elif (.escalate | type) != "object" then "invalid escalate policy: \($id)"
    elif .type == "noul" then
      if has("criteria") and (.criteria | type) != "object" then "invalid noul criteria: \($id)"
      elif (.escalate | keys) != ["at_or_above"] then "invalid noul policy keys: \($id)"
      elif (.escalate.at_or_above | unit | not) then "invalid noul threshold: \($id)"
      else empty end
    elif .type == "choice" then
      if (.criteria | type) != "object" then "invalid choice criteria: \($id)"
      elif (.criteria | length) < 1 or (.criteria | length) > 255 then "invalid choice criteria count: \($id)"
      elif any(.criteria[]; type as $t | (["string","object","array","null"] | index($t)) == null) then "invalid choice criteria value: \($id)"
      elif (.escalate | keys_in(["on","below_confidence"]) | not) or (.escalate | length) == 0 then "invalid choice policy keys: \($id)"
      elif (.escalate | has("on")) then
        if (.escalate.on | type) != "array" then "invalid on policy: \($id)"
        elif (.escalate.on | length) == 0 or (.escalate.on | unique | length) != (.escalate.on | length) then "empty or duplicate on policy: \($id)"
        elif any(.escalate.on[]; type != "string") then "non-string on policy: \($id)"
        elif any(.escalate.on[]; . as $c | $q.criteria | has($c) | not) then "unknown on choice: \($id)"
        elif (.escalate | has("below_confidence")) and (.escalate.below_confidence | unit | not) then "invalid confidence threshold: \($id)"
        else empty end
      elif (.escalate.below_confidence | unit | not) then "invalid confidence threshold: \($id)"
      else empty end
    else
      if (.criteria | type) != "array" then "invalid score criteria: \($id)"
      elif (.criteria | length) < 2 or (.criteria | length) > 10 then "invalid score criteria count: \($id)"
      elif (.escalate | keys_in(["at_or_above","below_confidence"]) | not) or (.escalate | length) == 0 then "invalid score policy keys: \($id)"
      elif (.escalate | has("at_or_above")) and
        ((.escalate.at_or_above | type) != "number" or .escalate.at_or_above < 0 or .escalate.at_or_above > (.criteria | length) - 1) then "invalid score threshold: \($id)"
      elif (.escalate | has("below_confidence")) and (.escalate.below_confidence | unit | not) then "invalid confidence threshold: \($id)"
      else empty end
    end
  end;
if length != 1 then "question set must contain exactly one JSON value"
else .[0] |
  if type != "object" then "question set is not an object"
  elif (keys_in(["set","revision","calibration","description","questions"]) | not) then "unknown question-set key"
  elif (.set | nonempty_string | not) then "invalid set name"
  elif (.revision | nonempty_string | not) then "invalid revision"
  elif has("calibration") and (.calibration | nonempty_string | not) then "invalid calibration"
  elif (.questions | type) != "object" then "questions is not an object"
  elif (.questions | length) == 0 then "empty questions"
  else first(.questions | to_entries[] |
    if (.key | test("^[a-z][a-z0-9_]*$") | not) then "invalid question id: \(.key)"
    else .key as $id | .value | question_error($id) end) // ""
  end
end'

validate_set() {
  local file=$1 reason
  [[ -f $file && -r $file ]] || { printf 'unreadable question set: %s' "$file"; return; }
  if reason=$(jq -rs "$set_filter" -- "$file" 2>/dev/null); then
    printf '%s' "$reason"
  else
    printf 'invalid question-set JSON: %s' "$file"
  fi
}
if [[ ${1-} == --check ]]; then
  shift
  [[ $# -gt 0 ]] || fatal 2 '--check requires at least one question set'
  status=0
  for file in "$@"; do
    reason=$(validate_set "$file")
    if [[ -n $reason ]]; then
      printf 'ESCALATE\t*\tfail-closed: %s\n' "$reason"
      printf 'classify-escalate.sh: %s: %s\n' "$file" "$reason" >&2
      status=2
    else
      jq -r --arg file "$file" '"ok \($file) set=\(.set)@\(.revision) questions=\(.questions|length)"' -- "$file"
    fi
  done
  exit "$status"
fi
raw_out=''; diag=''
while [[ $# -gt 0 ]]; do
  case $1 in
    --raw-out|--diag-dir)
      [[ $# -ge 2 && -n $2 ]] || fatal 2 "$1 requires a path"
      if [[ $1 == --raw-out ]]; then raw_out=$2; else diag=$2; fi
      shift 2 ;;
    --*) fatal 2 "unknown option: $1" ;;
    *) break ;;
  esac
done
[[ $# -ge 4 && $3 == -- ]] || fatal 2 'usage: SET STATE -- TRANSPORT [ARGS...]'
set_file=$1; state_file=$2; shift 3
reason=$(validate_set "$set_file")
[[ -z $reason ]] || fatal 2 "$reason"
set_json=$(jq -c . -- "$set_file")
if ! state_json=$(jq -cs 'if length == 1 and (.[0] | (type == "string" or type == "object" or type == "array") and length > 0) then .[0] else error("invalid state") end' -- "$state_file" 2>/dev/null); then
  fatal 2 'invalid state: expected exactly one non-empty JSON string, object, or array'
fi
if [[ -z $diag ]]; then diag=$(mktemp -d "${TMPDIR:-/tmp}/classify-escalate.XXXXXX"); fi
# umask 077 gives every newly created component mode 700.
if [[ ! -e $diag ]]; then mkdir -p -- "$diag"; fi
[[ -d $diag && -O $diag ]] || fatal 2 "diagnostic directory is not owned by the current user: $diag"
# BSD and GNU stat spell the octal mode query differently. Do not chmod an
# existing directory: even a successful call could revoke someone else's access.
if ! diag_mode=$(stat -L -f '%Lp' "$diag" 2>/dev/null); then
  diag_mode=$(stat -L -c '%a' "$diag")
fi
case $diag_mode in ''|*[!0-7]*) fatal 2 "cannot read diagnostic directory mode: $diag" ;; esac
(( (8#$diag_mode & 077) == 0 )) || fatal 2 "diagnostic directory allows group or other access: $diag"
diag=$(cd "$diag" && pwd)
init_diag_file() {
  local file=$1
  [[ ! -L $diag/$file && ( ! -e $diag/$file || -f $diag/$file ) ]] || fatal 2 "unsafe diagnostic file: $diag/$file"
  : >"$diag/$file"
  chmod 600 "$diag/$file"
}
for file in response.raw transport.stderr transport.exit response.json decisions.tsv; do
  init_diag_file "$file"
done

trailer() {
  local valid=$1
  jq -nr --argjson set "$set_json" --arg diag "$diag" --argjson valid "$valid" --slurpfile response "$diag/response.json" '
    def field: [tostring] | @tsv;
    (if $valid then $response[0] else {} end) as $r |
    "# set=\($set.set|field)@\($set.revision|field) calibration=\(($set.calibration // "unstated")|field) model=\(($r.model // "unknown")|field) in=\(($r.usage.input_tokens // "?")|field) out=\(($r.usage.output_tokens // "?")|field) diag=\($diag|field)"'
}
closed() {
  jq -nr --argjson set "$set_json" --arg reason "$1" \
    '$set.questions | to_entries[] | ["ESCALATE", .key, .value.type, "fail-closed: " + $reason] | @tsv'
  trailer false
  exit 3
}
if ! command -v "$1" >/dev/null 2>&1 || { [[ $1 == */* ]] && [[ ! -f $1 || ! -x $1 ]]; }; then
  reason="transport not found or not executable: $1"
  printf '%s\n' "$reason" >"$diag/transport.stderr"
  printf '127\n' >"$diag/transport.exit"
  if [[ -n $raw_out && ! $raw_out -ef $diag/response.raw ]]; then cp "$diag/response.raw" "$raw_out"; fi
  printf 'transport stderr: %s/transport.stderr\n' "$diag" >&2
  closed "$reason"
fi
init_diag_file request.json
jq -n --argjson set "$set_json" --argjson state "$state_json" \
  '{state:$state, questions:($set.questions | with_entries(.value |= del(.escalate)))}' >"$diag/request.json"
# Do not evaluate a command string: preserve the transport argument vector.
rc=0
"$@" "$diag/request.json" </dev/null >"$diag/response.raw" 2>"$diag/transport.stderr" || rc=$?
printf '%s\n' "$rc" >"$diag/transport.exit"
if [[ -n $raw_out ]]; then
  if [[ ! $raw_out -ef $diag/response.raw ]]; then cp "$diag/response.raw" "$raw_out"; fi
fi
if [[ $rc != 0 ]]; then
  printf 'transport stderr: %s/transport.stderr\n' "$diag" >&2
  closed "transport exit $rc"
fi
[[ -s $diag/response.raw ]] || closed 'empty response'
if ! jq -s 'if length == 1 then .[0] else error("expected exactly one JSON value") end' "$diag/response.raw" >"$diag/response.json" 2>/dev/null; then
  : >"$diag/response.json"
  closed 'invalid response JSON: expected exactly one JSON value'
fi
reason=$(jq -r --argjson set "$set_json" '
  def unit: type == "number" and . >= 0 and . <= 1;
  def answer_error($id; $q):
    if type != "object" then "answer is not an object: \($id)"
    elif (keys - (if $q.type == "noul" then ["type","noul"] elif $q.type == "choice" then ["type","choice","confidence","probabilities"] else ["type","score","confidence","legend","probabilities"] end) | length) > 0 then "unexpected answer key: \($id)"
    elif has("type") and .type != $q.type then "type mismatch: \($id)"
    elif has("probabilities") and (.probabilities | type) != "object" then "probabilities is not an object: \($id)"
    elif has("legend") and (.legend | type) != "object" then "legend is not an object: \($id)"
    elif $q.type == "noul" then
      if (.noul | type) != "number" then "noul is not a number: \($id)"
      elif (.noul | unit | not) then "noul out of range: \($id)" else empty end
    elif $q.type == "choice" and (.choice | type) != "string" then "choice is not a string: \($id)"
    elif $q.type == "choice" and (.choice as $c | $q.criteria | has($c) | not) then "unknown choice: \($id)"
    elif $q.type == "score" and (.score | type) != "number" then "score is not a number: \($id)"
    elif $q.type == "score" and (.score < 0 or .score > ($q.criteria|length) - 1) then "score out of range: \($id)"
    elif (.confidence | unit | not) then "invalid confidence: \($id)"
    else empty end;
  if type != "object" then "response is not an object"
  elif has("error") then "response has error key"
  elif (.answers | type) != "object" then "answers is not an object"
  elif has("model") and (.model | type) != "string" then "model is not a string"
  elif has("usage") and (.usage | type) != "object" then "usage is not an object"
  else . as $r |
    first(($set.questions | keys_unsorted[]) as $id | select($r.answers | has($id) | not) | "missing answer: \($id)") //
    first((.answers | keys_unsorted[]) as $id | select($set.questions | has($id) | not) | "extra answer: \($id)") //
    first($set.questions | to_entries[] | . as $q | $r.answers[$q.key] | answer_error($q.key; $q.value)) // ""
  end' "$diag/response.json")
[[ -z $reason ]] || closed "$reason"
jq -r --argjson set "$set_json" '
  .answers as $answers | $set.questions | to_entries[] |
  .key as $id | .value as $q | $q.escalate as $p | $answers[$id] as $a |
  (if $q.type == "noul" then $a.noul >= $p.at_or_above
   elif $q.type == "choice" then (($p.on // [] | index($a.choice)) != null) or (($p | has("below_confidence")) and $a.confidence < $p.below_confidence)
   else (($p | has("at_or_above")) and $a.score >= $p.at_or_above) or (($p | has("below_confidence")) and $a.confidence < $p.below_confidence) end) as $escalate |
  [(if $escalate then "ESCALATE" else "NO-SIGNAL" end), $id, $q.type] +
  (if $q.type == "noul" then ["p=\($a.noul)", "rule=at_or_above:\($p.at_or_above)"]
   else [(if $q.type == "choice" then "choice=\($a.choice)" else "score=\($a.score)" end), "confidence=\($a.confidence)",
     "rule=" + ([
       (if $q.type == "choice" and (($p.on // [] | index($a.choice)) != null) then "on" else empty end),
       (if $q.type == "score" and ($p | has("at_or_above")) and $a.score >= $p.at_or_above then "at_or_above:\($p.at_or_above)" else empty end),
       (if ($p | has("below_confidence")) and $a.confidence < $p.below_confidence then "below_confidence:\($p.below_confidence)" else empty end)
     ] | if length == 0 then "none" else join("|") end)] end) | @tsv' "$diag/response.json" >"$diag/decisions.tsv"
cat "$diag/decisions.tsv"
trailer true
if grep -q '^ESCALATE' "$diag/decisions.tsv"; then exit 1; fi
exit 0
