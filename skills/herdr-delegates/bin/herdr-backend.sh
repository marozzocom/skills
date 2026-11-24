#!/usr/bin/env bash
# herdr-backend.sh VERB [ARGS] — sole Herdr CLI boundary; bash 3.2.
# stdout contract (mutators are silent unless specified):
# flavor [RUN_DIR]: tui|app; marker-only, HERDR_ENV=1 wins; HERDR_FLAVOR
# selects only a present marker. RUN_DIR (or HERDR_BACKEND_RUN_DIR) rejects
# a recorded flavor mismatch. self: {flavor,id,pane,tab,space}; null app
# membership means not in the window, never the focused pane.
# agents: [{name,id,pane,tab,space,kind,status,status_age_s,title}]; missing
# agents/prefixes skip addresses lost to not_found during inventory.
# status stays null. tabs: [{id,label,space}]; spaces: [{id,label}].
# panes: [{id,tab,space,terminal,agent,status,cwd}] (cwd may be null).
# prefixes: [string] app run.prefix labels; tui [] without CLI calls.
# geometry [ID]: "cols rows", app never-drawn 200x120/120x40 => unknown.
# rename-self NAME: TUI rename; app run.name/run.role/run.prefix labels.
# rename TARGET NAME: TUI only; names another pane's agent (TARGET is a pane
# id or a name). A held name fails; the CLI's error goes to stderr.
# rename-tab ID LABEL / rename-space ID LABEL: silent.
# tab-focused ID: true|false, whether ID is its workspace's active tab; and
# focus-tab ID: silent. Both TUI only.
# tab-new SPACE LABEL CWD: tab=<id> pane=<id> (await app adoption).
# open-board RUN_DIR RATIO: pane id; app argv down split ignores ratio.
# start NAME KIND CWD (--pane P|--tab T [--space S]) [--timeout SECONDS]
#   -- ARGS: id, only after reported idle/done; KIND is executable in app.
#   App awaits adoption, then kill+removes an eligible idle sole root shell;
#   it creates no hidden parked root for teardown to discover.
# prompt NAME TEXT: started=true|false|null; wait NAME SECONDS: final status.
# App wait: ended => status/exit 0; otherwise reason (timeout/message/
# not_started) on stdout and exit 1.
# read-tail NAME N: <=N lines (app screen read locally tailed); keys NAME KEY…;
# close PANE_ID: silent (TUI pane close; app kill+rm of its terminal, also by name/address).
# callback-line PREFIX [AGENT]: TUI with AGENT and a run dir
# (HERDR_BACKEND_RUN_DIR): the file-drop instruction for RUN_DIR/inbox/new/
# (read by inbox-watch.sh); TUI otherwise: push line; app: PULL brief wording.
# tell NAME TEXT: prompt NAME with TEXT, a blank line and NAME's callback
# instruction (TUI needs a run dir); stdout as prompt. With a run dir it
# writes the UTC time to RUN_DIR/inbox/sent/NAME. NAME: [a-z][a-z0-9_-]{0,31},
# never an overseer.
# rotate NAME PANE CWD KIND -- ARGS: TUI original start JSON and unchanged
# quit/get/cwd/run/start sequence; app resolves NAME, ignores PANE, prints
# the new address; same name/tab/space, physical resolved CWD and supplied pin.
# App cockpit stores address in herdr.overseer_id; overseer_pane is physical.
# TUI start/rotate refuse a pane that already holds an agent (exit 1). When the
# agent stops at a startup dialog it is classified from a 40-line visible
# tail as folder_trust, model_banner, update_prompt or unknown_dialog. An
# unnamed agent of KIND in the pane is named NAME. folder_trust is confirmed
# only with verified keys for a cwd under a root in the human-owned
# ${XDG_CONFIG_HOME:-~/.config}/implementation-orchestration/trust-roots
# (regular file, owned, no group/other write); model_banner gets esc; at most
# two dialogs are cleared. Anything else exits 4 with empty stdout, one
# "start: dialog=..." stderr line plus tail lines, and with a run dir a
# kind: blocker file in RUN_DIR/inbox/new/. rotate never retries after 4.
# Exit: 0 success, 1 runtime/session/readiness failure, 2 usage, 3 unsupported
# verb in this flavor, 4 startup dialog blocking readiness (pane kept named
# when safe; diagnostic on stderr). Diagnostics on stderr. No
# vendor-to-executable table.
set -Eeuo pipefail
trap 'exit 1' ERR
usage() { echo "usage: herdr-backend.sh VERB [ARGS]" >&2; exit 2; }
fail() { echo "$*" >&2; exit 1; }
[ $# -gt 0 ] || usage
verb=$1; shift
here=$(cd "$(dirname "$0")" && pwd)
flavor=''
case ${HERDR_FLAVOR:-} in
  tui) if [ "${HERDR_ENV:-}" = 1 ]; then flavor=tui; fi ;;
  app) if [ -n "${HC_TERMINAL_ID:-}" ]; then flavor=app; fi ;;
  '') if [ "${HERDR_ENV:-}" = 1 ]; then flavor=tui
      elif [ -n "${HC_TERMINAL_ID:-}" ]; then flavor=app; fi ;;
  *) fail "invalid HERDR_FLAVOR: $HERDR_FLAVOR" ;;
esac
[ -n "$flavor" ] || fail "not inside a Herdr session"
run=${HERDR_BACKEND_RUN_DIR:-}
if [ "$verb" = flavor ]; then [ $# -le 1 ] || usage; run=${1:-$run}; fi
if [ -n "$run" ] && [ -f "$run/status.json" ]; then
  recorded=$(jq -r '.herdr.flavor // ""' "$run/status.json")
  [ -z "$recorded" ] || [ "$recorded" = "$flavor" ] || fail "Herdr flavor mismatch: run=$recorded caller=$flavor"
fi
app_panes() {
  local core; core=$(hc ls --json) || return 1
  herdr-app ls | jq -ce --argjson core "$core" '[.spaces[] as $s | $s.tabs[] as $t | $t.terminals[] |
    {id:.pane,tab:$t.id,space:$s.id,terminal:.terminal,agent:.app,status:.status,
     cwd:(.terminal as $id|[$core.terminals[]|select(.address==$id)][0].cwd)}]'
}
self() {
  if [ "$flavor" = tui ]; then
    jq -cn --arg id "${HERDR_PANE_ID:-}" --arg tab "${HERDR_TAB_ID:-}" --arg space "${HERDR_WORKSPACE_ID:-}" \
      '{flavor:"tui",id:$id,pane:$id,tab:$tab,space:$space}'
  else
    app_panes | jq -c --arg id "$HC_TERMINAL_ID" '[.[]|select(.terminal==$id)][0] |
      {flavor:"app",id:$id,pane:.id,tab:.tab,space:.space}'
  fi
}
# --- TUI start with startup-dialog handling (start and rotate) ---------------
# Every probe below is guarded (if/||) so that a failed probe can never turn
# the exit-4 path into the ERR trap's exit 1.
sd_tmp=''
sd_cleanup() { [ -z "$sd_tmp" ] || rm -rf "$sd_tmp"; }
sd_strip() { # stdin -> stdout without ANSI/OSC sequences and control bytes
  LC_ALL=C sed -e $'s/\x1b\\[[0-9;?<=>]*[ -/]*[@-~]//g' -e $'s/\x1b][^\x07\x1b]*\x07//g' \
    -e $'s/\x1b][^\x1b]*\x1b\\\\//g' -e $'s/\x1b[()][A-Za-z0-9]//g' -e $'s/\x1b[=>]//g' |
    LC_ALL=C tr -d '\000-\010\013\014\015\016-\037\177'
}
sd_agent() { # PANE -> the agent JSON object in PANE, or nothing
  local out=''
  if out=$(herdr agent get "$1" 2>/dev/null) &&
     out=$(jq -ce --arg p "$1" '(if has("result") then (.result.agent // .result) else . end)
       | objects | select((.pane_id // $p) == $p and (.agent // "") != "")' <<<"$out" 2>/dev/null); then
    printf '%s\n' "$out"; return 0
  fi
  if out=$(herdr agent list 2>/dev/null) &&
     out=$(jq -ce --arg p "$1" '[.result.agents[]|select(.pane_id==$p)][0] // empty' <<<"$out" 2>/dev/null); then
    printf '%s\n' "$out"
  fi
  return 0
}
sd_field() { jq -r --arg f "$1" '.[$f] // "" | tostring' <<<"$2" 2>/dev/null || true; } # FIELD JSON
sd_phys() { CDPATH='' cd -P -- "$1" 2>/dev/null && pwd -P; } # DIR -> its physical path, or fail
sd_cwd() { # PANE AGENT_JSON -> the pane's physical foreground cwd, or the raw value, or nothing
  local c='' out='' get='' p
  [ -z "$2" ] || c=$(jq -r '.foreground_cwd // ""' <<<"$2" 2>/dev/null) || c=''
  get=$(herdr pane get "$1" 2>/dev/null) || get=''
  [ -n "$c" ] || [ -z "$get" ] || c=$(jq -r '(.result.pane // .result // {}) | .foreground_cwd // ""' <<<"$get" 2>/dev/null) || c=''
  [ -n "$c" ] || [ -z "$2" ] || c=$(jq -r '.cwd // ""' <<<"$2" 2>/dev/null) || c=''
  [ -n "$c" ] || [ -z "$get" ] || c=$(jq -r '(.result.pane // .result // {}) | .cwd // ""' <<<"$get" 2>/dev/null) || c=''
  if [ -z "$c" ] && out=$(herdr pane list 2>/dev/null); then
    c=$(jq -r --arg p "$1" '[.result.panes[]|select(.pane_id==$p)][0] | .foreground_cwd // .cwd // ""' <<<"$out" 2>/dev/null) || c=''
  fi
  case $c in /*) if p=$(sd_phys "$c"); then c=$p; fi ;; esac
  printf '%s\n' "$c"
}
sd_tail() { # PANE -> a bounded, sanitized visible tail (empty when unreadable)
  local out=''
  out=$(herdr agent read "$1" --source visible --lines 40 2>/dev/null) ||
    out=$(herdr pane read "$1" --source visible --lines 40 2>/dev/null) || out=''
  printf '%s\n' "$out" | sd_strip || true
}
sd_has() { grep -qiE -- "$1" <<<"$2"; } # ERE TEXT
sd_trim() { local s=$1; s=${s#"${s%%[![:space:]]*}"}; printf '%s' "${s%"${s##*[![:space:]]}"}"; }
sd_classify() { # TAIL -> folder_trust|update_prompt|model_banner|unknown_dialog
  local t=$1
  if sd_has 'do you trust|trust this (folder|workspace|project|directory)|quick safety check|trust the (contents|files|authors)' "$t" ||
     { sd_has 'yes, proceed' "$t" && sd_has 'trust|safety' "$t" && sd_has 'folder|workspace|project|directory' "$t"; }; then
    echo folder_trust
  elif sd_has 'update available|new version (is )?available|update now' "$t"; then echo update_prompt
  elif sd_has "press esc|esc to (dismiss|close|continue)|what'?s new|new model|introducing" "$t" &&
       ! sd_has 'trust|approv|permission|allow|safety' "$t"; then echo model_banner
  else echo unknown_dialog; fi
}
sd_trusted_cwd() { # CWD -> 0 when CWD resolves at or under a root in the human-owned allowlist (sd_phys_cwd set)
  local f line root perm
  sd_phys_cwd=''
  case ${XDG_CONFIG_HOME:-} in ''|/*) ;; *) sd_why='XDG_CONFIG_HOME must be an absolute path'; return 1 ;; esac
  f=${XDG_CONFIG_HOME:-$HOME/.config}/implementation-orchestration/trust-roots
  case $f in /*) ;; *) sd_why="allowlist path $f is not absolute"; return 1 ;; esac
  sd_why="no allowlist at $f"
  [ -f "$f" ] && [ ! -L "$f" ] || { [ ! -L "$f" ] || sd_why="allowlist $f is a symlink"; return 1; }
  [ -O "$f" ] || { sd_why="allowlist $f is not owned by the current user"; return 1; }
  perm=$(find "$f" -prune \( -perm -020 -o -perm -002 \) -print 2>/dev/null) || { sd_why='could not check allowlist permissions'; return 1; }
  [ -z "$perm" ] || { sd_why="allowlist $f is group- or world-writable"; return 1; }
  case $1 in /*) ;; *) sd_why="cwd ${1:-unknown} is not an absolute path"; return 1 ;; esac
  sd_phys_cwd=$(sd_phys "$1") || { sd_why="cwd $1 cannot be resolved"; return 1; }
  sd_why="cwd $sd_phys_cwd is not under a root in $f"
  while IFS= read -r line || [ -n "$line" ]; do
    line=$(sd_trim "${line%%#*}")
    case $line in /*) ;; *) continue ;; esac # absolute paths only
    root=$(sd_phys "$line") || continue
    root=${root%/}
    if [ "$sd_phys_cwd" = "$root" ] || [[ $sd_phys_cwd == "$root"/* ]]; then return 0; fi
  done <"$f"
  return 1
}
sd_shown_paths() { # TAIL -> every path the dialog shows, one per line; 1 when a workspace header has none
  local line s want=0
  while IFS= read -r line; do
    s=$(sd_trim "$line")
    if [ "$want" = 1 ]; then [ -n "$s" ] || continue; printf '%s\n' "$s"; want=0; continue; fi
    if sd_has 'accessing workspace:' "$s"; then
      s=$(sd_trim "${s#*[Ww][Oo][Rr][Kk][Ss][Pp][Aa][Cc][Ee]:}")
      if [ -n "$s" ]; then printf '%s\n' "$s"; else want=1; fi
      continue
    fi
    # shellcheck disable=SC2088 # a literal ~/ prefix in dialog text
    case $s in /*|'~/'*) printf '%s\n' "$s" ;; esac
  done <<<"$1"
  [ "$want" = 0 ]
}
sd_trust_keys() { # TAIL CWD -> 0 with the verified key sequence in sd_keys, or 1 with sd_why
  local t=$1 cwd=$2 paths shown p sel n=0 marked='' next='' affirm
  affirm='^([0-9]+\.[[:space:]]*)?yes, (i trust this (folder|workspace|project|directory)|proceed)[[:space:]]*$'
  sd_trusted_cwd "$cwd" || return 1
  paths=$(sd_shown_paths "$t") || { sd_why='the dialog names a workspace but no path follows'; return 1; }
  while IFS= read -r shown; do
    [ -n "$shown" ] || continue
    # shellcheck disable=SC2088 # a literal ~/ prefix, expanded by hand
    case $shown in '~/'*) shown=$HOME/${shown#'~/'} ;; esac
    case $shown in /*) ;; *) sd_why="dialog workspace $shown is not an absolute path"; return 1 ;; esac
    p=$(sd_phys "$shown") || { sd_why="dialog workspace $shown cannot be resolved"; return 1; }
    [ "$p" = "$sd_phys_cwd" ] || { sd_why="dialog workspace $p is not the pane cwd $sd_phys_cwd"; return 1; }
  done <<<"$paths"
  while IFS= read -r sel; do
    if [ -n "$marked" ] && [ -z "$next" ]; then next=$sel; fi
    case $sel in [[:space:]]*'>'*|'>'*|[[:space:]]*'❯'*|'❯'*) ;; *) continue ;; esac
    sel=$(sd_trim "$sel")
    case $sel in '>'*) sel=${sel#>} ;; '❯'*) sel=${sel#❯} ;; *) continue ;; esac
    n=$((n + 1)); marked=$(sd_trim "$sel"); next=''
  done <<<"$t"
  next=$(sd_trim "$next")
  [ "$n" = 1 ] || { sd_why="$n highlighted choices; layout not recognized"; return 1; }
  if grep -qiE "$affirm" <<<"$marked"; then sd_keys=enter; return 0; fi
  if grep -qiE '^([0-9]+\.[[:space:]]*)?no, exit[[:space:]]*$' <<<"$marked" && grep -qiE "$affirm" <<<"$next"; then
    sd_keys='down enter'; return 0
  fi
  sd_why="highlighted choice '$marked' not recognized"; return 1
}
sd_blocked() { # CLASS NAME PANE CWD REASON TAIL ACTION — report a blocking dialog and exit 4
  local cls=$1 nm=$2 pn=$3 cw=$4 why=$5 t=$6 act=$7 lines inbox file
  lines=$(printf '%s\n' "$t" | grep -v '^[[:space:]]*$' | tail -n 6 || true)
  {
    echo "start: dialog=$cls agent=$nm pane=$pn cwd=${cw:-unknown} action=$act — $why"
    [ -z "$lines" ] || printf '%s\n' "$lines" | sed 's/^/  | /'
  } >&2
  if [ -n "$run" ] && [ -d "$run" ] && [[ $nm =~ ^[a-z][a-z0-9_-]{0,31}$ ]]; then
    inbox=$run/inbox/new
    file=$nm--start-dialog-$(date -u +%Y%m%dT%H%M%SZ)-$$.md
    if mkdir -p "$inbox" 2>/dev/null &&
       printf 'kind: blocker\nstart of %s in pane %s is held by a startup dialog (%s, action=%s): %s; cwd %s. Inspect: herdr agent read %s --source visible --lines 40\n' \
         "$nm" "$pn" "$cls" "$act" "$why" "${cw:-unknown}" "$pn" >"$inbox/.$file.tmp" 2>/dev/null; then
      mv "$inbox/.$file.tmp" "$inbox/$file" 2>/dev/null || rm -f "$inbox/.$file.tmp" 2>/dev/null || true
    fi
  fi
  exit 4
}
# sd_wait_ready PANE LIMIT_S PREV_TAIL -> 0 ready (idle/done, no trust prompt
# left), 1 a new known dialog (sd_tail_now), 2 neither within LIMIT_S. A
# screen that changes into something unrecognized (a loading frame) is waited on.
sd_wait_ready() {
  local pn=$1 limit=$2 prev=$3 end a st cls
  end=$((SECONDS + limit)); sd_tail_now=$prev
  sleep 0.3 # let multi-key sequences and the repaint land before the first sample
  while :; do
    a=$(sd_agent "$pn"); st=$(sd_field agent_status "$a")
    sd_tail_now=$(sd_tail "$pn"); cls=unknown_dialog
    [ -z "$sd_tail_now" ] || cls=$(sd_classify "$sd_tail_now")
    case $st in
      idle|done) [ "$cls" = folder_trust ] || return 0 ;;
      *) if [ "$sd_tail_now" != "$prev" ]; then
           case $cls in folder_trust|model_banner|update_prompt) return 1 ;; esac
         fi ;;
    esac
    [ "$SECONDS" -lt "$end" ] || return 2
    sleep 1
  done
}
sd_limit() { # LIMIT DEADLINE -> LIMIT, capped by the time left but never below 5 s
  local remaining=$(($2 - SECONDS)) cap
  if [ "$remaining" -gt 0 ]; then
    cap=$remaining; [ "$cap" -ge 5 ] || cap=5
    [ "$1" -le "$cap" ] || { echo "$cap"; return 0; }
  fi
  echo "$1"
}
sd_handle() { # NAME KIND PANE DEADLINE TAIL — clear at most two dialogs, or exit 4
  local nm=$1 kd=$2 pn=$3 deadline=$4 t=$5 a cwd cls keys handled=0 settled=0 limit act=none wr
  while :; do
    a=$(sd_agent "$pn"); cwd=$(sd_cwd "$pn" "$a"); cls=$(sd_classify "$t")
    if [ "$(sd_field agent "$a")" != "$kd" ] || { [ -n "$(sd_field name "$a")" ] && [ "$(sd_field name "$a")" != "$nm" ]; }; then
      sd_blocked "$cls" "$nm" "$pn" "$cwd" "the agent in the pane is not $nm ($kd); no keys sent" "$t" "$act"
    fi
    case $cls in
      folder_trust)
        sd_why=''; sd_keys=''
        sd_trust_keys "$t" "$cwd" || sd_blocked "$cls" "$nm" "$pn" "$cwd" "not confirmed: $sd_why; no keys sent" "$t" "$act"
        keys=$sd_keys; limit=15 ;;
      model_banner) keys=esc; limit=10 ;;
      update_prompt) sd_blocked "$cls" "$nm" "$pn" "$cwd" 'an update prompt needs a human decision' "$t" "$act" ;;
      *)
        # An unrecognized screen may be a loading frame: wait, without keys, for a known one.
        if [ "$settled" -lt 2 ]; then
          settled=$((settled + 1))
          wr=0; sd_wait_ready "$pn" "$(sd_limit 3 "$deadline")" "" || wr=$?
          [ "$wr" != 0 ] || return 0
          t=$sd_tail_now; [ "$wr" = 2 ] || continue
        fi
        sd_blocked unknown_dialog "$nm" "$pn" "$cwd" 'unrecognized startup dialog' "$t" "$act" ;;
    esac
    # shellcheck disable=SC2086 # keys is a verified, space-separated key list
    herdr agent send-keys "$pn" $keys >/dev/null 2>&1 ||
      sd_blocked "$cls" "$nm" "$pn" "$cwd" "sending '$keys' failed" "$t" "$act"
    handled=$((handled + 1)); act="sent:${keys// /+}"
    limit=$(sd_limit "$limit" "$deadline")
    wr=0; sd_wait_ready "$pn" "$limit" "$t" || wr=$?
    [ "$wr" != 0 ] || return 0
    # A screen that did not turn into a new known dialog gets no second key.
    [ "$wr" = 1 ] || sd_blocked "$cls" "$nm" "$pn" "$cwd" "not ready within ${limit}s of the keys; nothing more sent" "$sd_tail_now" "$act"
    t=$sd_tail_now
    [ "$handled" -lt 2 ] ||
      sd_blocked "$(sd_classify "$t")" "$nm" "$pn" "$cwd" 'still not ready after two dialog transitions' "$t" "$act"
  done
}
sd_ready_check() { # NAME KIND PANE DEADLINE — an agent that reports ready: only a trust prompt is acted on
  local t='' cls=''
  t=$(sd_tail "$3")
  [ -z "$t" ] || cls=$(sd_classify "$t")
  case $cls in
    folder_trust) sd_handle "$1" "$2" "$3" "$4" "$t" ;;
    update_prompt) echo "start: warning: $1 shows an update notice; it reported ready, continuing" >&2 ;;
  esac
}
# tui_start NAME KIND PANE TIMEOUT_S [ARGS...]: sets start_outcome=ok with
# start_json (herdr's start JSON, or one built from the agent) or
# start_outcome=fail after copying herdr's output to stderr; a blocking
# startup dialog exits 4 from here.
tui_start() {
  local name=$1 kind=$2 pane=$3 timeout=$4; shift 4
  local cmd=(herdr agent start "$name" --kind "$kind" --pane "$pane" --timeout "$((timeout * 1000))")
  local rc=0 code='' a='' list deadline
  if [ $# -gt 0 ]; then cmd+=(-- "$@"); fi
  start_outcome=fail; start_json=''
  list=$(herdr agent list) || { echo "start: could not list agents to check pane $pane" >&2; return 0; }
  jq -e '.result.agents | type == "array"' <<<"$list" >/dev/null 2>&1 ||
    { echo "start: the agent list is malformed; not starting $name in pane $pane" >&2; return 0; }
  if jq -e --arg p "$pane" 'any(.result.agents[]; .pane_id == $p)' <<<"$list" >/dev/null; then
    echo "start: pane $pane already holds an agent ($(jq -r --arg p "$pane" '[.result.agents[]|select(.pane_id==$p)][0]|"\(.name // "unnamed") \(.agent // "")"' <<<"$list")); not starting $name there" >&2
    return 0
  fi
  if [ -z "$sd_tmp" ]; then sd_tmp=$(mktemp -d "${TMPDIR:-/tmp}/herdr-start.XXXXXX"); trap sd_cleanup EXIT; fi
  deadline=$((SECONDS + timeout))
  "${cmd[@]}" >"$sd_tmp/out" 2>"$sd_tmp/err" || rc=$?
  if [ "$rc" = 0 ]; then
    start_json=$(cat "$sd_tmp/out")
    sd_ready_check "$name" "$kind" "$pane" "$deadline"
    start_outcome=ok; return 0
  fi
  for f in out err; do
    [ -n "$code" ] || code=$(jq -r '.error.code // empty' "$sd_tmp/$f" 2>/dev/null) ||
      code=$(sed -n 's/.*"code"[[:space:]]*:[[:space:]]*"\([A-Za-z0-9_]*\)".*/\1/p' "$sd_tmp/$f" | head -n 1) || code=''
  done
  a=$(sd_agent "$pane")
  if [ -z "$a" ] || [ "$code" = agent_pane_busy ]; then
    cat "$sd_tmp/out" "$sd_tmp/err" >&2 || true; return 0
  fi
  case $code in agent_not_ready|timeout|'') ;; *) cat "$sd_tmp/out" "$sd_tmp/err" >&2 || true; return 0 ;; esac
  if [ "$(sd_field agent "$a")" != "$kind" ] || { [ -n "$(sd_field name "$a")" ] && [ "$(sd_field name "$a")" != "$name" ]; }; then
    cat "$sd_tmp/out" "$sd_tmp/err" >&2 || true
    echo "start: pane $pane now holds another agent ($(sd_field name "$a") $(sd_field agent "$a")); not adopting it" >&2
    return 0
  fi
  if [ -z "$(sd_field name "$a")" ]; then
    herdr agent rename "$pane" "$name" >/dev/null 2>&1 || echo "start: could not name the agent in pane $pane $name" >&2
  fi
  a=$(sd_agent "$pane")
  case $(sd_field agent_status "$a") in
    idle|done) sd_ready_check "$name" "$kind" "$pane" "$deadline" ;;
    *) sd_handle "$name" "$kind" "$pane" "$deadline" "$(sd_tail "$pane")" ;;
  esac
  a=$(sd_agent "$pane")
  # Ready is not enough: the agent must hold NAME, or later prompts by name go nowhere.
  if [ "$(sd_field name "$a")" != "$name" ]; then
    if [ -z "$(sd_field name "$a")" ] && [ "$(sd_field agent "$a")" = "$kind" ]; then
      herdr agent rename "$pane" "$name" >/dev/null 2>&1 || true
      a=$(sd_agent "$pane")
    fi
    if [ "$(sd_field name "$a")" != "$name" ]; then
      echo "start: the agent in pane $pane is ready but does not hold the name $name; prompts by name would miss it" >&2
      return 0
    fi
  fi
  start_json=$(jq -cn --arg p "$pane" --argjson a "$a" '{result:{agent:($a + {pane_id:$p})}}' 2>/dev/null) ||
    start_json=$(jq -cn --arg p "$pane" '{result:{agent:{pane_id:$p}}}')
  start_outcome=ok
}
abort_start() {
  local id=$1; shift
  hc kill "$id" >/dev/null 2>&1 || true
  hc rm "$id" >/dev/null 2>&1 || true
  fail "$*"
}
start_app() {
  local name=$1 kind=$2 cwd=$3 pane=$4 tab=$5 space=$6 timeout=$7; shift 7
  local inventory root='' before detail created id deadline state remaining adopted
  inventory=$(app_panes)
  if [ -n "$pane" ]; then
    before=$(jq -ce --arg p "$pane" '[.[]|select(.id==$p)][0] // error("pane not in window")' <<<"$inventory")
    tab=$(jq -r .tab <<<"$before"); space=$(jq -r .space <<<"$before")
  elif [ -z "$space" ]; then
    before=$(herdr-app ls | jq -ce --arg t "$tab" --arg s "$space" \
      '[.spaces[]|select($s=="" or .id==$s)|. as $s|.tabs[]|select(.id==$t)|{space:$s.id}][0] // error("tab not in window")')
    space=$(jq -r .space <<<"$before")
  fi
  before=$(jq -c --arg t "$tab" '[.[]|select(.tab==$t)]' <<<"$inventory")
  if [ "$(jq length <<<"$before")" = 1 ]; then
    root=$(jq -r '.[0].terminal' <<<"$before")
  fi
  created=$(hc run --bg --name "$name" --cwd "$cwd" --label "herdr.space=$space" --label "herdr.tab=$tab" -- "$kind" "$@")
  id=$(jq -er '.address|strings|select(length>0)' <<<"$created")
  deadline=$((SECONDS + timeout))
  while :; do
    detail=$(hc get "$id" --json) || abort_start "$id" "$name readiness query failed"
    state=$(jq -r 'if (.status|type)=="object" then .status.state else .status end // "unreported"' <<<"$detail") || abort_start "$id" "$name invalid readiness response"
    if jq -e '.reported==true and (.status.state=="idle" or .status.state=="done")' <<<"$detail" >/dev/null; then break; fi
    case $state in blocked|error) abort_start "$id" "$name not ready: $state" ;; esac
    [ "$(jq -r .state <<<"$detail")" != finished ] || abort_start "$id" "$name exited before readiness"
    remaining=$((deadline - SECONDS)); [ "$remaining" -gt 0 ] || abort_start "$id" "$name readiness timed out ($state)"
    hc wait "$id" --timeout "$remaining" >/dev/null || abort_start "$id" "$name readiness wait failed"
    [ "$SECONDS" -lt "$deadline" ] || abort_start "$id" "$name readiness timed out ($state)"
  done
  while :; do
    inventory=$(app_panes) || abort_start "$id" "$name adoption query failed"
    adopted=$(jq -r --arg id "$id" --arg t "$tab" --arg s "$space" 'any(.[];.terminal==$id and .tab==$t and .space==$s)' <<<"$inventory") || abort_start "$id" "$name invalid adoption response"
    [ "$adopted" != true ] || break
    [ "$SECONDS" -lt "$deadline" ] || abort_start "$id" "$name not adopted into tab $tab"
    sleep 0.1
  done
  if [ -n "$root" ] && jq -e --arg t "$tab" --arg r "$root" \
    '[.[]|select(.tab==$t)]|length==2 and any(.[];.terminal==$r)' <<<"$inventory" >/dev/null; then
    # Recheck after adoption: the user may have used the root during startup.
    detail=$(hc get "$root" --json)
    if jq -e '.state=="live" and .name==null and .reported!=true and .status==null and
      (.argv[0]|split("/")|last|test("^(sh|bash|zsh|fish|dash|ksh)$")) and
      (.foreground!=null) and (.foreground==null or (.foreground.name|test("^(sh|bash|zsh|fish|dash|ksh)$")))' <<<"$detail" >/dev/null; then
      hc kill "$root" >/dev/null
      hc rm "$root" >/dev/null
    fi
  fi
  printf '%s\n' "$id"
}
callback_text() { # PREFIX [AGENT]
  local dir
  if [ "$flavor" = tui ] && [ -n "${2:-}" ] && [ -n "$run" ]; then
    dir=$(cd "$run" && pwd)/inbox/new/
    printf 'To message the overseer, write a new file in %s named %s--<short-topic>.md. Its first line is kind: report, kind: question, kind: blocker or kind: note; the rest is your message (one line; put anything longer in a file and give its path). Use your file-writing tool; no shell command needed. Use a new file name for every message.\n' "$dir" "$2"
  elif [ "$flavor" = tui ]; then printf 'herdr agent prompt %s-overseer "<message>"\n' "$1"
  else echo 'Write the report/questions file named in the brief, then end your turn. The overseer is watching your turn state.'; fi
}
case $verb in
  flavor) echo "$flavor" ;;
  self) [ $# -eq 0 ] || usage; self ;;
  prefixes)
    [ $# -eq 0 ] || usage
    if [ "$flavor" = tui ]; then echo '[]'
    else
      list=$(hc ls --json); labels='[]'
      jq -e ' .terminals|type=="array"' <<<"$list" >/dev/null
      while IFS= read -r id; do
        if detail=$(hc get "$id" --json); then :
        else rc=$?; [ "$rc" -eq 3 ] && continue; exit 1; fi
        labels=$(jq -cn --argjson a "$labels" --argjson d "$detail" '$a + [$d.labels["run.prefix"]|strings]')
      done < <(jq -r '.terminals[].address' <<<"$list")
      echo "$labels"
    fi ;;
  agents)
    [ $# -eq 0 ] || usage
    if [ "$flavor" = tui ]; then
      herdr agent list | jq -ce '[.result.agents[]|{name,id:.pane_id,pane:.pane_id,tab:.tab_id,space:.workspace_id,
        kind:.agent,status:.agent_status,status_age_s:.status_age_s,title:.terminal_title_stripped}]'
    else
      list=$(hc ls --json); inventory=$(app_panes); agents='[]'
      jq -e '.terminals|type=="array"' <<<"$list" >/dev/null
      while IFS= read -r id; do
        if detail=$(hc get "$id" --json); then :
        else rc=$?; [ "$rc" -eq 3 ] && continue; exit 1; fi
        agents=$(jq -cn --argjson a "$agents" --argjson d "$detail" --argjson ls "$list" --argjson p "$inventory" '
          ($ls.terminals[]|select(.address==$d.address)) as $l |
          ([$p[]|select(.terminal==$d.address)][0]) as $p |
          $a + [{name:($d.name // $d.labels["run.name"] // $l.name),id:$d.address,pane:$p.id,tab:$p.tab,space:$p.space,
            kind:($d.agent // $l.agent),status:(if ($d.status|type)=="object" then $d.status.state else $d.status end),
            status_age_s:(if $d.status_ms then ([0,(now-$d.status_ms/1000)]|max) else null end),title:$d.title}]')
      done < <(jq -r '.terminals[].address' <<<"$list")
      echo "$agents"
    fi ;;
  tabs|spaces|panes)
    [ $# -eq 0 ] || usage
    if [ "$flavor" = app ]; then
      case $verb in
        tabs) herdr-app ls | jq -ce '[.spaces[] as $s|$s.tabs[]|{id,label:.name,space:$s.id}]' ;;
        spaces) herdr-app ls | jq -ce '[.spaces[]|{id,label:.name}]' ;;
        panes) app_panes ;;
      esac
    else
      case $verb in
        tabs) herdr tab list | jq -ce '[.result.tabs[]|{id:.tab_id,label,space:.workspace_id}]' ;;
        spaces) herdr workspace list | jq -ce '[.result.workspaces[]|{id:.workspace_id,label}]' ;;
        panes) herdr pane list | jq -ce '[.result.panes[]|{id:.pane_id,tab:.tab_id,space:.workspace_id,terminal:.pane_id,agent,status:.agent_status,cwd}]' ;;
      esac
    fi ;;
  geometry)
    [ $# -le 1 ] || usage; id=${1:-}
    if [ "$flavor" = tui ]; then
      if [ -n "$id" ]; then layout=$(herdr pane layout --pane "$id"); else layout=$(herdr pane layout --current); fi
      jq -er --arg p "${id:-${HERDR_PANE_ID:-}}" '.result.layout|. as $l|
        (if $p!="" then $p else ($l.pane_id // $l.focused_pane_id) end) as $p |
        [.panes[]|select(.pane_id==$p)][0].rect // error("pane rect not found") | "\(.width) \(.height)"' <<<"$layout"
    else
      if [ -z "$id" ]; then id=$HC_TERMINAL_ID
      else inventory=$(app_panes); id=$(jq -r --arg id "$id" '[.[]|select(.id==$id)][0].terminal // $id' <<<"$inventory"); fi
      hc get "$id" --json | jq -er 'if (.cols==200 and .rows==120) or (.cols==120 and .rows==40) then "unknown"
        elif (.cols|type)=="number" and (.rows|type)=="number" then "\(.cols) \(.rows)" else error("geometry unavailable") end'
    fi ;;
  rename-self)
    [ $# -eq 1 ] || usage
    if [ "$flavor" = tui ]; then herdr agent rename "${HERDR_PANE_ID:?}" "$1" >/dev/null
    else hc label "$HC_TERMINAL_ID" "run.name=$1" "run.prefix=${1%-overseer}" run.role=overseer >/dev/null; fi ;;
  rename)
    [ $# -eq 2 ] && [ -n "$1" ] && [ -n "$2" ] || usage
    [ "$flavor" = tui ] || { echo "unsupported verb in $flavor: $verb" >&2; exit 3; }
    out=$(herdr agent rename "$1" "$2") || { [ -z "$out" ] || echo "$out" >&2; exit 1; } ;;
  tab-focused|focus-tab)
    [ $# -eq 1 ] && [ -n "$1" ] || usage
    [ "$flavor" = tui ] || { echo "unsupported verb in $flavor: $verb" >&2; exit 3; }
    if [ "$verb" = focus-tab ]; then herdr tab focus "$1" >/dev/null
    else herdr tab list | jq -r --arg t "$1" '[.result.tabs[]|select(.tab_id==$t)][0].focused == true'; fi ;;
  rename-tab|rename-space)
    [ $# -eq 2 ] || usage
    if [ "$flavor" = app ]; then
      case $verb in rename-tab) object=tab ;; *) object=space ;; esac
      herdr-app 'do' "$object.rename" --id "$1" --name "$2" >/dev/null
    elif [ "$verb" = rename-tab ]; then herdr tab rename "$1" "$2" >/dev/null
    else herdr workspace rename "$1" "$2" >/dev/null; fi ;;
  tab-new)
    [ $# -eq 3 ] || usage
    if [ "$flavor" = tui ]; then
      created=$(herdr tab create --workspace "$1" --cwd "$3" --label "$2" --no-focus) || fail "ERROR: tab create failed"
      jq -er '.result|select((.tab.tab_id|type)=="string" and (.root_pane.pane_id|type)=="string")|"tab=\(.tab.tab_id) pane=\(.root_pane.pane_id)"' <<<"$created" || fail "ERROR: tab create returned no tab/pane IDs"
    else
      created=$(herdr-app 'do' tab.new --space "$1" --folder "$3" --name "$2")
      tab=$(jq -er '.tab|strings' <<<"$created"); id=$(jq -er '.terminal|strings' <<<"$created"); deadline=$((SECONDS+10))
      while :; do
        inventory=$(app_panes); pane=$(jq -r --arg id "$id" '[.[]|select(.terminal==$id)][0].id // ""' <<<"$inventory")
        [ -z "$pane" ] || break
        [ "$SECONDS" -lt "$deadline" ] || fail "tab root not adopted"; sleep 0.1
      done
      echo "tab=$tab pane=$pane"
    fi ;;
  open-board)
    [ $# -eq 2 ] || usage; run=$1; ratio=$2; caller=$(self); pane=$(jq -er '.pane|strings|select(length>0)' <<<"$caller")
    if [ "$flavor" = tui ]; then
      split=$(herdr pane split "$pane" --direction down --ratio "$ratio" --cwd "$run" --no-focus) || fail "ERROR: board split failed"
      board=$(jq -er '.result.pane.pane_id|strings|select(length>0)' <<<"$split") || fail "ERROR: split did not return pane_id"
      "$here/../../implementation-orchestration/bin/status-set.sh" "$run" meta "board_pane=$board" >/dev/null
      printf -v command '%q %q' "$here/run-board.sh" "$run"
      herdr pane run "$board" "$command" >/dev/null || fail "ERROR: board command failed"
    else
      argv=$(jq -cn --arg s "$here/run-board.sh" --arg r "$run" '[$s,$r]')
      split=$(herdr-app 'do' pane.split --direction down --pane "$pane" --argv "$argv")
      board=$(jq -er '.pane|strings|select(length>0)' <<<"$split")
    fi
    echo "$board" ;;
  start)
    [ $# -ge 5 ] || usage; name=$1; kind=$2; cwd=$3; shift 3; pane=''; tab=''; space=''; timeout=30
    while [ $# -gt 0 ]; do
      case $1 in --) shift; break ;; --pane|--tab|--space|--timeout)
        [ $# -ge 2 ] || usage
        case $1 in --pane) pane=$2 ;; --tab) tab=$2 ;; --space) space=$2 ;; --timeout) timeout=$2 ;; esac; shift 2 ;; *) usage ;; esac
    done
    [ -n "$name" ] && [ -n "$kind" ] && [ -n "$cwd" ] || usage
    case $timeout in ''|*[!0-9]*) usage ;; esac
    [ "$timeout" -gt 0 ] || usage
    { [ -n "$pane" ] && [ -z "$tab" ] && [ -z "$space" ]; } || { [ -n "$tab" ] && [ -z "$pane" ]; } || usage
    if [ "$flavor" = app ]; then start_app "$name" "$kind" "$cwd" "$pane" "$tab" "$space" "$timeout" "$@"
    else
      if [ -z "$pane" ]; then
        pane=$(herdr pane list | jq -r --arg t "$tab" '[.result.panes[]|select(.tab_id==$t and .agent==null)][0].pane_id // empty')
        [ -n "$pane" ] || { echo "start: tab $tab has no pane without an agent; create a tab with run-tab.sh and pass --pane" >&2; exit 1; }
      fi
      tui_start "$name" "$kind" "$pane" "$timeout" "$@"
      [ "$start_outcome" = ok ] || exit 1
      jq -er '.result.agent.pane_id // .result.pane_id // error("start returned no id")' <<<"$start_json"
    fi ;;
  prompt|tell)
    [ $# -eq 2 ] || usage; text=$2
    if [ "$verb" = tell ]; then
      [[ $1 =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || usage
      case $1 in *-overseer) echo "tell: delegates message the overseer through its inbox" >&2; exit 2 ;; esac
      [ "$flavor" = app ] || [ -n "$run" ] || { echo "tell: set HERDR_BACKEND_RUN_DIR; the callback names the run's inbox" >&2; exit 2; }
      text="$text"$'\n\n'$(callback_text '' "$1")
    fi
    if [ "$flavor" = tui ]; then result=$(herdr agent prompt "$1" "$text"); else result=$(hc send "$1" "$text"); fi
    if [ "$verb" = tell ] && [ -n "$run" ]; then
      mkdir -p "$run/inbox/sent" "$run/inbox/new"
      date -u +%Y-%m-%dT%H:%M:%SZ >"$run/inbox/sent/.$1.$$"
      mv "$run/inbox/sent/.$1.$$" "$run/inbox/sent/$1"
    fi
    jq -r '(if has("result") then .result else . end)|"started=\(if .started==true then "true" elif .started==false then "false" else "null" end)"' <<<"$result" ;;
  wait)
    [ $# -eq 2 ] || usage; case $2 in ''|*[!0-9]*) usage ;; esac
    if [ "$flavor" = tui ]; then herdr agent wait "$1" --timeout "$(($2*1000))" | jq -er '.result.agent.agent_status // .result.agent_status // .result.status'
    else
      result=$(hc wait "$1" --timeout "$2")
      jq -r 'if .ended==true then .status // .reason else .reason end' <<<"$result"
      jq -e '.ended==true' <<<"$result" >/dev/null || exit 1
    fi ;;
  read-tail)
    [ $# -eq 2 ] || usage; case $2 in ''|*[!0-9]*) usage ;; esac; [ "$2" -gt 0 ] || usage
    if [ "$flavor" = tui ]; then herdr agent read "$1" --source visible --lines "$2"
    else hc read "$1" --lines 0 --json | jq -j '.text' | tail -n "$2"; fi ;;
  keys)
    [ $# -ge 2 ] || usage
    if [ "$flavor" = tui ]; then herdr agent send-keys "$@" >/dev/null
    else name=$1; shift; keys=(); for key in "$@"; do keys+=("${key/ctrl-c/ctrl+c}"); done; hc keys "$name" "${keys[@]}" >/dev/null; fi ;;
  close)
    [ $# -eq 1 ] || usage
    if [ "$flavor" = tui ]; then herdr pane close "$1" >/dev/null
    else inventory=$(app_panes); id=$(jq -r --arg id "$1" '[.[]|select(.id==$id)][0].terminal // $id' <<<"$inventory")
      id=$(hc get "$id" --json | jq -er .address); hc kill "$id" >/dev/null; hc rm "$id" >/dev/null; fi ;;
  rotate)
    [ $# -ge 5 ] || usage; name=$1; pane=$2; dir=$3; kind=$4; shift 4
    [ "${1:-}" = -- ] || usage; shift; agent_args=("$@")
    target=$(cd "$dir" && pwd -P)
    if [ ${#agent_args[@]} -eq 0 ]; then
      echo "warning: no native agent args — '$kind' will start on its config" \
           "default, not an explicit model pin (see environment.md)" >&2
    fi
    if [ "$flavor" = app ]; then
      detail=$(hc get "$name" --json); id=$(jq -er .address <<<"$detail")
      inventory=$(app_panes)
      location=$(jq -ce --arg id "$id" '[.[]|select(.terminal==$id)][0] // error("agent not in window")' <<<"$inventory")
      tab=$(jq -r .tab <<<"$location"); space=$(jq -r .space <<<"$location")
      hc kill "$id" >/dev/null; hc rm "$id" >/dev/null
      if [ ${#agent_args[@]} -eq 0 ]; then start_app "$name" "$kind" "$target" '' "$tab" "$space" 60
      else start_app "$name" "$kind" "$target" '' "$tab" "$space" 60 "${agent_args[@]}"; fi
    else
      pane_has_agent() { herdr agent get "$pane" >/dev/null 2>&1; }
      await_agent_gone() {
        local deadline=$((SECONDS + $1))
        while pane_has_agent; do
          [ "$SECONDS" -ge "$deadline" ] && return 1
          sleep 1
        done
        return 0
      }
      if pane_has_agent; then
        primary='/quit'
        secondary='/exit'
        if [ -n "${ROTATE_QUIT_CMD:-}" ]; then
          secondary=$primary
          primary=$ROTATE_QUIT_CMD
        fi
        wait_each=${ROTATE_QUIT_WAIT:-8}
        ladder=(
          "prompt:$primary"
          "prompt:$primary"
          "keys:esc|prompt:$primary"
          "prompt:$secondary"
          "keys:ctrl-c|prompt:$secondary"
        )
        quit_ok=0
        for round in "${ladder[@]}"; do
          IFS='|' read -r -a steps <<<"$round"
          for step in "${steps[@]}"; do
            case "$step" in
              keys:*)
                herdr agent send-keys "$pane" "${step#keys:}" >/dev/null 2>&1 || true
                sleep 1
                ;;
              prompt:*)
                herdr agent prompt "$pane" "${step#prompt:}" >/dev/null 2>&1 || true
                ;;
            esac
          done
          if await_agent_gone "$wait_each"; then quit_ok=1; break; fi
          echo "quit attempt did not take ($round) — escalating" >&2
        done
        if [ "$quit_ok" != 1 ]; then
          echo "agent in pane $pane survived every quit attempt — not proceeding" >&2
          echo "(inspect with: herdr agent read $pane --source visible)" >&2
          exit 1
        fi
        sleep 1
      fi
      pane_foreground_cwd() {
        herdr pane get "$pane" | python3 -c 'import json,sys; d=json.load(sys.stdin)["result"]; p=d.get("pane") or d; print(p.get("foreground_cwd") or p.get("cwd") or "")'
      }
      herdr pane run "$pane" "cd '$dir'" >/dev/null
      deadline=$((SECONDS + 10))
      while [ "$(pane_foreground_cwd)" != "$target" ]; do
        if [ "$SECONDS" -ge "$deadline" ]; then
          echo "pane $pane did not reach cwd $target within 10s — not proceeding" >&2
          exit 1
        fi
        sleep 1
      done
      # A dialog exits 4 from tui_start; only a plain failure is retried once.
      tui_start "$name" "$kind" "$pane" 60 ${agent_args[@]+"${agent_args[@]}"}
      if [ "$start_outcome" != ok ]; then
        sleep 3
        tui_start "$name" "$kind" "$pane" 60 ${agent_args[@]+"${agent_args[@]}"}
        [ "$start_outcome" = ok ] || exit 1
      fi
      printf '%s\n' "$start_json"
    fi ;;
  callback-line)
    [ $# -eq 1 ] || [ $# -eq 2 ] || usage
    [ $# -eq 1 ] || [[ $2 =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || usage
    callback_text "$@" ;;
  *) echo "unsupported verb in $flavor: $verb" >&2; exit 3 ;;
esac
