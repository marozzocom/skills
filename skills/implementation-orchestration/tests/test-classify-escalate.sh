#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
C="$BIN_DIR/classify-escalate.sh"
export CLASSIFY_BODY="$SCRATCH/body" CLASSIFY_CALLS="$SCRATCH/calls" CLASSIFY_RC=0
export CLASSIFY_REQUEST="$SCRATCH/received-request" CLASSIFY_ARGS="$SCRATCH/received-args"
T="$SCRATCH/transport"
cat >"$T" <<'MOCK'
#!/bin/bash
printf 'call\n' >>"$CLASSIFY_CALLS"
printf '%s\n' "$@" >"$CLASSIFY_ARGS"
while [ "$#" -gt 1 ]; do shift; done
cp "$1" "$CLASSIFY_REQUEST"
if read -r unexpected; then echo 'stdin was not empty' >&2; exit 99; fi
cat "$CLASSIFY_BODY"
echo 'mock diagnostic' >&2
exit "$CLASSIFY_RC"
MOCK
chmod +x "$T"
cat >"$SCRATCH/noul.json" <<'JSON'
{"set":"screen","revision":"r1","questions":{"risk":{"type":"noul","instructions":"Does this need review?","escalate":{"at_or_above":0.5}}}}
JSON
cat >"$SCRATCH/choice.json" <<'JSON'
{"set":"choice","revision":"r1","calibration":"uncalibrated","questions":{"choice_q":{"type":"choice","instructions":{"nested":["first",{"detail":"second"}]},"criteria":{"a":{"details":["x",{"y":1}]},"b":[{"nested":true}],"none":null},"escalate":{"on":["none"],"below_confidence":0.5}}}}
JSON
cat >"$SCRATCH/score.json" <<'JSON'
{"set":"score","revision":"r1","questions":{"severity":{"type":"score","instructions":["first",{"nested":["second"]}],"criteria":[{"level":0},["level",1],"level 2"],"escalate":{"at_or_above":1.5,"below_confidence":0.4}}}}
JSON
jq -s '.[0] * {questions:(.[0].questions + .[1].questions + .[2].questions)}' "$SCRATCH/noul.json" "$SCRATCH/choice.json" "$SCRATCH/score.json" >"$SCRATCH/all.json"
printf '{"nested":[{"body":[1,true,null]},"text"]}\n' >"$SCRATCH/state.json"
SET="$SCRATCH/noul.json"; STATE="$SCRATCH/state.json"; serial=0
invariant() {
  if [[ $rc != 0 ]]; then assert_contains "$1-nonzero-escalates" $'ESCALATE\t' "$out"; fi
}
run_case() { # label expected-exit expected-output [options...]
  local label=$1 expected=$2 needle=$3
  shift 3
  serial=$((serial + 1)); diag="$SCRATCH/diag-$serial"
  : >"$CLASSIFY_CALLS"
  out=$("$BASH" "$C" --diag-dir "$diag" "$@" "$SET" "$STATE" -- "$T" 'literal argument with spaces' 2>"$SCRATCH/stderr"); rc=$?
  assert_eq "$label-exit" "$expected" "$rc"
  assert_contains "$label-output" "$needle" "$out"
  assert_eq "$label-one-call" 1 "$(wc -l <"$CLASSIFY_CALLS" | tr -d ' ')"
  assert_eq "$label-transport-argument" 'literal argument with spaces' "$(head -n1 "$CLASSIFY_ARGS")"
  invariant "$label"
}
body() { printf '%s' "$1" >"$CLASSIFY_BODY"; }
body '{"answers":{"risk":{"type":"noul","noul":0.123456789012345}},"model":"mock","usage":{"input_tokens":11,"output_tokens":7}}'
run_case noul-below 0 $'NO-SIGNAL\trisk\tnoul\tp=0.123456789012345\trule=at_or_above:0.5'
assert_contains valid-trailer 'calibration=unstated model=mock in=11 out=7' "$out"
body '{"answers":{"risk":{"noul":0.1}},"model":"mock\n\tmodel"}'
run_case trailer-one-line 0 'model=mock\n\tmodel'
assert_eq trailer-line-count 2 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
body '{"answers":{"risk":{"noul":0.5}}}'
run_case noul-equal-and-optional-type 1 $'ESCALATE\trisk\tnoul\tp=0.5'
body '{"answers":{"risk":{"noul":0.9}}}'
run_case noul-above 1 $'ESCALATE\trisk\tnoul\tp=0.9'
body ''
run_case empty 3 'empty response'
body '{broken'
run_case invalid-json 3 'invalid response JSON'
body '{"answers":{"risk":{"noul":0}}}{"answers":{"risk":{"noul":0}}}'
run_case concatenated-json 3 'exactly one JSON value'
body '{"answers":{"risk":{"noul":0}}} trailing'
run_case trailing-garbage 3 'invalid response JSON'
body '{"answers":{}}'
run_case missing-answer 3 'missing answer: risk'
body '{"answers":{"risk":{"noul":0},"extra":{"noul":0}}}'
run_case extra-answer 3 'extra answer: extra'
for value in '"0.2"' null true false NaN; do
  body "{\"answers\":{\"risk\":{\"noul\":$value}}}"
  run_case "noul-type-$value" 3 'noul is not a number: risk'
done
for value in 1.1 -0.1; do
  body "{\"answers\":{\"risk\":{\"noul\":$value}}}"
  run_case "noul-range-$value" 3 'noul out of range: risk'
done
body '{"answers":{"risk":{"type":"score","noul":0}}}'
run_case type-mismatch 3 'type mismatch: risk'
body '{"answers":{"risk":{"noul":0,"surprise":1}}}'
run_case unexpected-key 3 'unexpected answer key: risk'
for value in null '[]' 3; do
  body "{\"answers\":$value}"
  run_case "answers-object-$value" 3 'answers is not an object'
done
body '{"answers":{"risk":{"noul":0}},"error":null}'
run_case error-key 3 'response has error key'
body '{"answers":{"risk":{"noul":0}},"model":3}'
run_case model-type 3 'model is not a string'
body '{"answers":{"risk":{"noul":0}},"usage":[]}'
run_case usage-type 3 'usage is not an object'
body '[]'
run_case response-object 3 'response is not an object'
body '{"answers":{"risk":0}}'
run_case answer-object 3 'answer is not an object: risk'
body '{"answers":{"risk":{}}}'
run_case missing-noul 3 'noul is not a number: risk'
body 'failed raw bytes'
CLASSIFY_RC=7
run_case transport-failure 3 'transport exit 7' --raw-out "$SCRATCH/failure.raw"
assert_eq transport-raw-exact 0 "$(cmp -s "$CLASSIFY_BODY" "$SCRATCH/failure.raw"; echo $?)"
assert_contains transport-stderr-path "transport stderr: $diag/transport.stderr" "$(cat "$SCRATCH/stderr")"
assert_eq transport-stderr-retained 'mock diagnostic' "$(cat "$diag/transport.stderr")"
assert_eq transport-exit-retained 7 "$(cat "$diag/transport.exit")"
assert_eq private-directory "$diag" "$(find "$diag" -prune -perm 700)"
assert_eq private-files '' "$(find "$diag" -type f ! -perm 600)"
assert_contains invalid-trailer 'model=unknown in=? out=?' "$out"
CLASSIFY_RC=0
# Reject transports before creating a request; every question escalates.
cp "$T" "$SCRATCH/non-executable"
chmod 600 "$SCRATCH/non-executable"
for unavailable in "$SCRATCH/missing-transport" "$SCRATCH/non-executable" classifier_missing_transport_test "$SCRATCH"; do
  : >"$CLASSIFY_CALLS"
  out=$("$BASH" "$C" --diag-dir "$SCRATCH/unavailable" "$SCRATCH/all.json" "$STATE" -- "$unavailable" 2>"$SCRATCH/stderr"); rc=$?
  assert_eq transport-unavailable 3 "$rc"
  assert_contains transport-unavailable-reason "transport not found or not executable: $unavailable" "$out"
  assert_eq unavailable-every-question 3 "$(printf '%s\n' "$out" | grep -c '^ESCALATE')"
  assert_eq unavailable-no-call '' "$(cat "$CLASSIFY_CALLS")"
  assert_eq unavailable-no-request no "$([ -e "$SCRATCH/unavailable/request.json" ] && echo yes || echo no)"
  assert_contains unavailable-stderr-path 'transport stderr:' "$(cat "$SCRATCH/stderr")"
  invariant unavailable
done
body '{"answers":{"risk":{"noul":0.1}}}'
mkdir -m 700 "$SCRATCH/existing-private"
run_case existing-private-dir 0 NO-SIGNAL --diag-dir "$SCRATCH/existing-private"
assert_eq existing-private-mode "$SCRATCH/existing-private" "$(find "$SCRATCH/existing-private" -prune -perm 700)"
mkdir -m 755 "$SCRATCH/shared"
: >"$CLASSIFY_CALLS"
out=$("$BASH" "$C" --diag-dir "$SCRATCH/shared" "$SET" "$STATE" -- "$T" 2>&1); rc=$?
assert_eq shared-directory-refused 2 "$rc"
assert_contains shared-directory-path "$SCRATCH/shared" "$out"
assert_contains shared-directory-wildcard $'ESCALATE\t*\tfail-closed:' "$out"
assert_eq shared-directory-mode-preserved "$SCRATCH/shared" "$(find "$SCRATCH/shared" -prune -perm 755)"
assert_eq shared-directory-no-call '' "$(cat "$CLASSIFY_CALLS")"
assert_eq shared-directory-no-files '' "$(find "$SCRATCH/shared" -type f)"
invariant shared-directory
SET="$SCRATCH/choice.json"
body '{"answers":{"choice_q":{"choice":"none","confidence":0.9}}}'
run_case choice-on 1 $'choice=none\tconfidence=0.9\trule=on'
body '{"answers":{"choice_q":{"choice":"a","confidence":0.9,"probabilities":{}}}}'
run_case choice-high 0 $'choice=a\tconfidence=0.9\trule=none'
body '{"answers":{"choice_q":{"choice":"a","confidence":0.5}}}'
run_case choice-confidence-equal 0 'rule=none'
body '{"answers":{"choice_q":{"choice":"a","confidence":0.49}}}'
run_case choice-low 1 'rule=below_confidence:0.5'
body '{"answers":{"choice_q":{"choice":"none","confidence":0.49}}}'
run_case choice-both 1 'rule=on|below_confidence:0.5'
body '{"answers":{"choice_q":{"choice":"other","confidence":0.9}}}'
run_case choice-unknown 3 'unknown choice: choice_q'
body '{"answers":{"choice_q":{"choice":null,"confidence":0.9}}}'
run_case choice-type 3 'choice is not a string: choice_q'
for value in null '"0.9"' true -0.1 1.1; do
  body "{\"answers\":{\"choice_q\":{\"choice\":\"a\",\"confidence\":$value}}}"
  run_case "confidence-$value" 3 'invalid confidence: choice_q'
done
body '{"answers":{"choice_q":{"choice":"a","confidence":0.9,"probabilities":[]}}}'
run_case probabilities-type 3 'probabilities is not an object: choice_q'
SET="$SCRATCH/score.json"
body '{"answers":{"severity":{"score":1.5,"confidence":0.9}}}'
run_case score-equal 1 'rule=at_or_above:1.5'
body '{"answers":{"severity":{"score":1,"confidence":0.4,"legend":{},"probabilities":{}}}}'
run_case score-low 0 $'NO-SIGNAL\tseverity\tscore\tscore=1\tconfidence=0.4\trule=none'
body '{"answers":{"severity":{"score":1,"confidence":0.3}}}'
run_case score-confidence 1 'rule=below_confidence:0.4'
for value in -1 3; do
  body "{\"answers\":{\"severity\":{\"score\":$value,\"confidence\":0.9}}}"
  run_case "score-range-$value" 3 'score out of range: severity'
done
body '{"answers":{"severity":{"score":"1","confidence":0.9}}}'
run_case score-type 3 'score is not a number: severity'
body '{"answers":{"severity":{"score":1,"confidence":0.9,"legend":[]}}}'
run_case legend-type 3 'legend is not an object: severity'
SET="$SCRATCH/all.json"
body '{"answers":{"severity":{"score":1,"confidence":0.9},"choice_q":{"choice":"a","confidence":0.9},"risk":{"noul":0.1}}}'
run_case structured-request 0 $'NO-SIGNAL\trisk'
jq -n --slurpfile set "$SET" --slurpfile state "$STATE" '{state:$state[0],questions:($set[0].questions|with_entries(.value|=del(.escalate)))}' >"$SCRATCH/expected-request"
assert_eq request-structure "$(jq -S . "$SCRATCH/expected-request")" "$(jq -S . "$CLASSIFY_REQUEST")"
assert_eq question-order 'risk choice_q severity ' "$(printf '%s\n' "$out" | awk -F '\t' '/^NO-SIGNAL/{printf "%s ",$2}')"
body '{"answers":{"risk":{"noul":0.1}}}'
run_case all-fail-closed 3 'missing answer: choice_q'
assert_eq all-questions-escalate 3 "$(printf '%s\n' "$out" | grep -c '^ESCALATE')"
SET="$SCRATCH/noul.json"
body '{"answers":{"risk":{"noul":0.1}}}'
run_case raw-valid 0 'NO-SIGNAL' --raw-out "$SCRATCH/raw-copy"
assert_eq raw-valid-exact 0 "$(cmp -s "$CLASSIFY_BODY" "$SCRATCH/raw-copy"; echo $?)"
printf '\377invalid\000body\n\n' >"$CLASSIFY_BODY"
run_case raw-invalid 3 'invalid response JSON' --raw-out "$SCRATCH/raw-copy"
assert_eq raw-invalid-exact 0 "$(cmp -s "$CLASSIFY_BODY" "$SCRATCH/raw-copy"; echo $?)"
body '{"answers":{"risk":{"noul":0.1}}}'
STATE=-
run_case state-stdin 0 NO-SIGNAL <"$SCRATCH/state.json"
STATE="$SCRATCH/state.json"
for state in null 1 true '""' '{}' '[]' '{} {}' '{broken'; do
  printf '%s' "$state" >"$SCRATCH/bad-state"
  : >"$CLASSIFY_CALLS"
  out=$("$BASH" "$C" "$SET" "$SCRATCH/bad-state" -- "$T" 2>&1); rc=$?
  assert_eq "state-$state-exit" 2 "$rc"
  assert_eq "state-$state-no-call" '' "$(cat "$CLASSIFY_CALLS")"
  invariant "state-$state"
done
for state in '"text"' '[1]'; do
  printf '%s' "$state" >"$STATE"
  run_case "state-valid-$state" 0 NO-SIGNAL
done
: >"$CLASSIFY_CALLS"
out=$("$BASH" "$C" --check "$SCRATCH/all.json" "$SET" 2>&1); rc=$?
assert_eq check-valid-exit 0 "$rc"
assert_contains check-valid-output "ok $SET set=screen@r1 questions=1" "$out"
assert_eq check-no-call '' "$(cat "$CLASSIFY_CALLS")"
invalid_set() { # label jq mutation of the complete fixture
  local label=$1 filter=$2 mode
  jq "$filter" "$SCRATCH/all.json" >"$SCRATCH/invalid-set.json"
  for mode in check invoke; do
    : >"$CLASSIFY_CALLS"
    if [[ $mode == check ]]; then
      out=$("$BASH" "$C" --check "$SCRATCH/invalid-set.json" 2>&1); rc=$?
    else
      out=$("$BASH" "$C" "$SCRATCH/invalid-set.json" "$STATE" -- "$T" 2>&1); rc=$?
    fi
    assert_eq "$label-$mode-exit" 2 "$rc"
    assert_eq "$label-$mode-no-call" '' "$(cat "$CLASSIFY_CALLS")"
    invariant "$label-$mode"
  done
}
invalid_set top-type '[]'
invalid_set top-extra '.extra=1'
invalid_set set-missing 'del(.set)'
invalid_set set-empty '.set=""'
invalid_set set-type '.set=1'
invalid_set revision-empty '.revision=""'
invalid_set revision-type '.revision=null'
invalid_set calibration-empty '.calibration=""'
invalid_set calibration-type '.calibration=[]'
invalid_set questions-empty '.questions={}'
invalid_set questions-type '.questions=[]'
invalid_set question-id '.questions.Bad=.questions.risk | del(.questions.risk)'
invalid_set question-type '.questions.risk=[]'
invalid_set question-key '.questions.risk.extra=1'
invalid_set unknown-type '.questions.risk.type="boolean"'
invalid_set instructions-missing 'del(.questions.risk.instructions)'
invalid_set instructions-blank '.questions.risk.instructions=" \n\t"'
invalid_set instructions-object-empty '.questions.risk.instructions={}'
invalid_set instructions-array-empty '.questions.risk.instructions=[]'
invalid_set instructions-type '.questions.risk.instructions=true'
invalid_set policy-missing 'del(.questions.risk.escalate)'
invalid_set policy-type '.questions.risk.escalate=[]'
invalid_set noul-criteria '.questions.risk.criteria=[]'
invalid_set noul-policy-empty '.questions.risk.escalate={}'
invalid_set noul-policy-extra '.questions.risk.escalate.on=["a"]'
invalid_set noul-threshold-low '.questions.risk.escalate.at_or_above=-0.1'
invalid_set noul-threshold-high '.questions.risk.escalate.at_or_above=1.1'
invalid_set noul-threshold-type '.questions.risk.escalate.at_or_above="0.5"'
invalid_set choice-criteria-missing 'del(.questions.choice_q.criteria)'
invalid_set choice-criteria-type '.questions.choice_q.criteria=[]'
invalid_set choice-criteria-empty '.questions.choice_q.criteria={}'
invalid_set choice-criteria-many '.questions.choice_q.criteria=([range(256)|{key:tostring,value:null}]|from_entries)'
invalid_set choice-criteria-value '.questions.choice_q.criteria.a=1'
invalid_set choice-policy-empty '.questions.choice_q.escalate={}'
invalid_set choice-policy-extra '.questions.choice_q.escalate.extra=1'
invalid_set on-type '.questions.choice_q.escalate.on="none"'
invalid_set on-empty '.questions.choice_q.escalate.on=[]'
invalid_set on-duplicate '.questions.choice_q.escalate.on=["none","none"]'
invalid_set on-non-string '.questions.choice_q.escalate.on=[null]'
invalid_set on-unknown '.questions.choice_q.escalate.on=["unknown"]'
invalid_set choice-confidence-low '.questions.choice_q.escalate.below_confidence=-1'
invalid_set choice-confidence-high '.questions.choice_q.escalate.below_confidence=2'
invalid_set choice-confidence-type '.questions.choice_q.escalate.below_confidence=null'
invalid_set score-criteria-missing 'del(.questions.severity.criteria)'
invalid_set score-criteria-type '.questions.severity.criteria={}'
invalid_set score-criteria-few '.questions.severity.criteria=[0]'
invalid_set score-criteria-many '.questions.severity.criteria=[range(11)]'
invalid_set score-policy-empty '.questions.severity.escalate={}'
invalid_set score-policy-extra '.questions.severity.escalate.on=["a"]'
invalid_set score-threshold-low '.questions.severity.escalate.at_or_above=-1'
invalid_set score-threshold-high '.questions.severity.escalate.at_or_above=3'
invalid_set score-threshold-type '.questions.severity.escalate.at_or_above=true'
invalid_set score-confidence-low '.questions.severity.escalate.below_confidence=-1'
invalid_set score-confidence-high '.questions.severity.escalate.below_confidence=2'
invalid_set score-confidence-type '.questions.severity.escalate.below_confidence="0.5"'
# Policies containing only one of the optional keys are valid.
for filter in 'del(.questions.choice_q.escalate.on)' 'del(.questions.choice_q.escalate.below_confidence)' 'del(.questions.severity.escalate.at_or_above)' 'del(.questions.severity.escalate.below_confidence)'; do
  jq "$filter" "$SCRATCH/all.json" >"$SCRATCH/optional-policy"
  out=$("$BASH" "$C" --check "$SCRATCH/optional-policy" 2>&1); rc=$?
  assert_eq optional-policy 0 "$rc"
done
for malformed in '' '{bad' '{} {}'; do
  printf '%s' "$malformed" >"$SCRATCH/malformed"
  out=$("$BASH" "$C" --check "$SCRATCH/malformed" 2>&1); rc=$?
  assert_eq malformed-set 2 "$rc"
  invariant malformed-set
done
for arg in '' --check --unknown --raw-out --diag-dir; do
  out=$("$BASH" "$C" "$arg" 2>&1); rc=$?
  assert_eq usage-exit 2 "$rc"
  invariant usage
done
mkdir "$SCRATCH/no-tools"
out=$(PATH="$SCRATCH/no-tools" "$BASH" "$C" --check "$SET" 2>&1); rc=$?
assert_eq missing-jq-exit 3 "$rc"
assert_contains missing-jq-message 'missing dependency: jq' "$out"
invariant missing-jq
ln -s "$(command -v jq)" "$SCRATCH/no-tools/jq"
out=$(PATH="$SCRATCH/no-tools" "$BASH" "$C" --check "$SET" 2>&1); rc=$?
assert_eq missing-mktemp-exit 3 "$rc"
assert_contains missing-mktemp-message 'missing dependency: mktemp' "$out"
invariant missing-mktemp
finish
