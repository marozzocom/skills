#!/usr/bin/env bash
# tests/lib.sh — sourced by every test: assertions, a scratch dir, and the
# mock `gh` / `herdr` binaries. Bash 3.2 compatible (no mapfile, no
# associative arrays, no ${var,,}).
set -u
unset BASH_ENV ENV HERDR_FLAVOR HERDR_BACKEND_RUN_DIR
while IFS= read -r hc_var; do unset "$hc_var"; done < <(compgen -v HC_)
export HERDR_ENV=1
# Scratch run dirs live under TMPDIR; status-set.sh init refuses that outside tests.
export STATUS_ALLOW_TMP=1

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC2034  # used by the sourcing tests
BIN_DIR=$(cd "$TESTS_DIR/../bin" && pwd)
SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/di-tests.XXXXXX")
SCRATCH=$(cd "$SCRATCH" && pwd)
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
# Verify the actual child-shell lookup, not merely this shell's PATH.
assert_child_resolves() { # <command> <expected path>
  local actual
  # shellcheck disable=SC2016 # Expand positional arguments in the child shell.
  actual=$("$BASH" --noprofile --norc -c 'command -v "$1"' _ "$1")
  assert_eq "child-resolves-$1" "$2" "$actual"
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
#   $HERDR_SCENARIO/layout.json → `herdr pane layout` output
#   tabs.json / workspaces.json → list output (empty defaults)
#   split.json / create.json → optional mutation responses; renames/creates
#     update the list fixtures, split updates layout, run captures its command.
#   $HERDR_SCENARIO/pane.txt    → full pane text; `agent read --lines N`
#                                 returns its last N lines. A read without
#                                 --lines is logged as UNBOUNDED.
HERDR_SCENARIO="$SCRATCH/herdr-scenario"
mkdir -p "$HERDR_SCENARIO"
printf '{"result":{"tabs":[]}}\n' >"$HERDR_SCENARIO/tabs.json"
printf '{"result":{"workspaces":[]}}\n' >"$HERDR_SCENARIO/workspaces.json"
cat >"$MOCK_BIN/herdr" <<'MOCK'
#!/usr/bin/env bash
set -u
S=${HERDR_SCENARIO:?}
printf 'herdr %s\n' "$*" >>"${MOCK_LOG:?}"
if [ -f "$S/$1-$2.exit" ]; then exit "$(cat "$S/$1-$2.exit")"; fi
case "$1 $2" in
  "agent list") cat "$S/agents.json" ;;
  "pane list") cat "$S/panes.json" ;;
  "agent get")
    jq -ce --arg id "$3" '.result.agents[]|select(.pane_id==$id or .name==$id)' "$S/agents.json" ;;
  "agent start") echo '{"result":{"agent":{"pane_id":"w1:p2","agent_status":"idle"}}}' ;;
  "agent prompt") echo '{"result":{"started":true}}' ;;
  "agent wait") echo '{"result":{"agent":{"agent_status":"done"}}}' ;;
  "agent send-keys"|"pane close") echo '{}' ;;
  "pane get") cat "$S/pane-get.json" ;;
  "tab list") cat "$S/tabs.json" ;;
  "workspace list") cat "$S/workspaces.json" ;;
  "pane layout") cat "$S/layout.json" ;;
  "agent rename")
    jq --arg p "$3" --arg n "$4" '.result.agents |= map(if .pane_id == $p then .name=$n else . end)' "$S/agents.json" >"$S/agents.tmp"
    mv "$S/agents.tmp" "$S/agents.json"; echo '{}' ;;
  "tab rename")
    jq --arg t "$3" --arg l "$4" '.result.tabs |= map(if .tab_id == $t then .label=$l else . end)' "$S/tabs.json" >"$S/tabs.tmp"
    mv "$S/tabs.tmp" "$S/tabs.json"; echo '{}' ;;
  "workspace rename")
    jq --arg w "$3" --arg l "$4" '.result.workspaces |= map(if .workspace_id == $w then .label=$l else . end)' "$S/workspaces.json" >"$S/workspaces.tmp"
    mv "$S/workspaces.tmp" "$S/workspaces.json"; echo '{}' ;;
  "tab create")
    ws=''; label=''; cwd=''
    shift 2
    while [ $# -gt 0 ]; do
      case $1 in --workspace) ws=$2; shift 2 ;; --label) label=$2; shift 2 ;; --cwd) cwd=$2; shift 2 ;; *) shift ;; esac
    done
    [ -f "$S/create.json" ] || printf '{"result":{"tab":{"tab_id":"w1:tnew"},"root_pane":{"pane_id":"w1:pnew"}}}\n' >"$S/create.json"
    tab=$(jq -r '.result.tab.tab_id' "$S/create.json")
    jq --arg w "$ws" --arg l "$label" --arg t "$tab" --arg cwd "$cwd" \
      '.result.tabs += [{workspace_id:$w,label:$l,tab_id:$t,cwd:$cwd}]' "$S/tabs.json" >"$S/tabs.tmp"
    mv "$S/tabs.tmp" "$S/tabs.json"; cat "$S/create.json" ;;
  "pane split")
    [ -f "$S/split.json" ] || printf '{"result":{"pane":{"pane_id":"w1:pboard"}}}\n' >"$S/split.json"
    pane=$(jq -r '.result.pane.pane_id' "$S/split.json")
    jq --arg p "$pane" '.result.layout.panes += [{pane_id:$p,rect:{width:158,height:24}}]' "$S/layout.json" >"$S/layout.tmp"
    mv "$S/layout.tmp" "$S/layout.json"; cat "$S/split.json" ;;
  "pane run") printf '%s' "$4" >"$S/run-command.txt"; echo '{}' ;;
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
assert_child_resolves gh "$MOCK_BIN/gh"
assert_child_resolves herdr "$MOCK_BIN/herdr"

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

# App/core fixtures from scout B1-B8 and probe P1-P10. Every call is logged.
HC_SCENARIO=$SCRATCH/hc-scenario
APP_SCENARIO=$SCRATCH/app-scenario
mkdir -p "$HC_SCENARIO" "$APP_SCENARIO"
export HC_SCENARIO APP_SCENARIO
cat >"$MOCK_BIN/hc" <<'MOCK'
#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
s=Path(os.environ['HC_SCENARIO']); a=Path(os.environ['APP_SCENARIO'])
args=sys.argv[1:]
with open(os.environ['MOCK_LOG'],'a') as f: f.write('hc '+' '.join(args)+'\n')
def read(p,default=None): return json.loads(p.read_text()) if p.exists() else default
def write(p,d): p.write_text(json.dumps(d))
def opt(k,default=None): return args[args.index(k)+1] if k in args else default
def out(d): print(json.dumps(d))
def locate(target):
 for t in terms:
  if t['address']==target or t.get('name')==target: return t
 print(json.dumps({'error':{'kind':'not_found','message':'unknown terminal '+target}}),file=sys.stderr); sys.exit(3)
try:
 terms=read(s/'terminals.json',[]); ui=read(a/'ls.json',{'spaces':[],'recent':[]})
 cmd=args[0]
 if (s/(cmd+'.exit')).exists(): sys.exit(int((s/(cmd+'.exit')).read_text()))
 if (s/(cmd+'.response.json')).exists(): out(read(s/(cmd+'.response.json'))); sys.exit(0)
 if cmd=='ls':
  out({'hidden_finished':0,'terminals':[dict({k:v for k,v in t.items() if k in ['address','agent','cwd','name','parent','state','turn']},
   **({'status':t['status']['state']} if isinstance(t.get('status'),dict) else {})) for t in terms if '--all' in args or t.get('state')!='finished']})
 elif cmd=='get':
  rc=read(s/'get-errors.json',{}).get(args[1],0)
  if rc:
   print(json.dumps({'error':{'kind':'not_found' if rc==3 else 'runtime','message':'fixture get failure'}}),file=sys.stderr); sys.exit(rc)
  t=locate(args[1]); out(t)
 elif cmd=='run':
  if opt('--name') and any(t.get('name')==opt('--name') and t.get('state')=='live' for t in terms):
   print(json.dumps({'error':{'kind':'name_taken','message':'a live terminal is already named '+opt('--name')}}),file=sys.stderr); sys.exit(1)
  n=read(s/'counter.json',0)+1; write(s/'counter.json',n); ident='tnew'+str(n)
  status=read(s/'run-status.json',{'app':'fixture','state':'idle'})
  argv=args[args.index('--')+1:]; labels={}
  for i,v in enumerate(args):
   if v=='--label':
    k,val=args[i+1].split('=',1); labels[k]=val
  t={'address':ident,'agent':argv[0],'argv':argv,'cwd':opt('--cwd'),'name':opt('--name'),
    'parent':os.environ.get('HC_TERMINAL_ID'),'state':'live','turn':0,'labels':labels,
    'cols':200,'rows':120,'reported':status is not None,'status':status,'title':'fixture-title','status_ms':None}
  terms.append(t)
  if (s/'delay-adoption').exists(): write(a/'pending.json',t)
  elif not (s/'no-adoption').exists():
   for space in ui['spaces']:
    for tab in space['tabs']:
     if space['id']==labels.get('herdr.space') and tab['id']==labels.get('herdr.tab'):
      tab['terminals'].append({'terminal':ident,'pane':'p'+ident,'status':status['state'] if status else None,'app':argv[0],'name':t['name'],'sub_agents':[]})
   write(a/'ls.json',ui)
  out({k:t[k] for k in ['address','agent','cwd','name','parent','state','turn']})
 elif cmd=='label':
  t=locate(args[1])
  for pair in args[2:]:
   k,v=pair.split('=',1); t.setdefault('labels',{})[k]=v
  out(t)
 elif cmd=='send': out(read(s/'send.json',{'started':True,'status':'idle','turn':1}))
 elif cmd=='wait':
  if (s/'wait.json').exists(): out(read(s/'wait.json'))
  else:
   t=locate(args[1])
   if (s/'wait-promote.json').exists():
    t['status']=read(s/'wait-promote.json'); t['reported']=True
   state=(t.get('status') or {}).get('state')
   if state is None: __import__('time').sleep(float(opt('--timeout','0')))
   out({'ended':state is not None,'reason':'status' if state else 'timeout','status':state,'turn':t.get('turn',0)})
 elif cmd=='read': out({'complete':True,'how':'screen','text':(s/'pane.txt').read_text()})
 elif cmd=='keys': out({'status':None,'turn':0})
 elif cmd in ['kill','rm']:
  t=locate(args[1]); ident=t['address']; t['state']='finished'; t['status']=None
  if cmd=='rm': terms.remove(t)
  for space in ui['spaces']:
   for tab in space['tabs']: tab['terminals']=[v for v in tab['terminals'] if v['terminal']!=ident]
  write(a/'ls.json',ui); out({'removed':ident} if cmd=='rm' else t)
 else: raise ValueError('unhandled '+str(args))
 write(s/'terminals.json',terms)
except Exception as e:
 print(str(e),file=sys.stderr); sys.exit(1)
MOCK
cat >"$MOCK_BIN/herdr-app" <<'MOCK'
#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
s=Path(os.environ['APP_SCENARIO']); core=Path(os.environ['HC_SCENARIO']); args=sys.argv[1:]
with open(os.environ['MOCK_LOG'],'a') as f: f.write('herdr-app '+' '.join(args)+'\n')
def opt(k): return args[args.index(k)+1]
def write(p,d): p.write_text(json.dumps(d))
try:
 ui=json.loads((s/'ls.json').read_text())
 if args==['ls']:
  if (s/'pending.json').exists():
   t=json.loads((s/'pending.json').read_text()); (s/'pending.json').unlink()
   for sp in ui['spaces']:
    for tab in sp['tabs']:
     if sp['id']==t['labels']['herdr.space'] and tab['id']==t['labels']['herdr.tab']:
      tab['terminals'].append({'terminal':t['address'],'pane':'p'+t['address'],'status':None,'app':t['agent'],'name':t['name'],'sub_agents':[]})
   write(s/'ls.json',ui)
   print(json.dumps({'spaces':[],'recent':[]})); sys.exit(0)
  print(json.dumps(ui)); sys.exit(0)
 cmd=args[1]; result={'ok':True}
 if (s/(cmd+'.exit')).exists(): sys.exit(int((s/(cmd+'.exit')).read_text()))
 if (s/(cmd+'.response.json')).exists(): print((s/(cmd+'.response.json')).read_text()); sys.exit(0)
 if cmd in ['tab.rename','space.rename']:
  for space in ui['spaces']:
   if cmd=='space.rename' and space['id']==opt('--id'): space['name']=opt('--name')
   for tab in space['tabs']:
    if cmd=='tab.rename' and tab['id']==opt('--id'): tab['name']=opt('--name')
 elif cmd=='tab.new':
  space=next(v for v in ui['spaces'] if v['id']==opt('--space'))
  ident='tbnew'+str(len(space['tabs'])); root='root'+ident
  space['tabs'].append({'id':ident,'name':opt('--name'),'active':True,'settled':False,
   'terminals':[{'terminal':root,'pane':'p'+root,'status':None,'app':None,'name':None,'sub_agents':[]}]})
  terms=json.loads((core/'terminals.json').read_text()); terms.append({'address':root,'argv':['/bin/zsh','-l'],
   'name':None,'parent':None,'cols':120,'rows':40,'state':'live','reported':False,'status':None})
  write(core/'terminals.json',terms); result={'space':space['id'],'tab':ident,'terminal':root}
 elif cmd=='pane.split':
  write(s/'pane-split-argv.json',json.loads(opt('--argv')))
  tab=next(t for sp in ui['spaces'] for t in sp['tabs'] if any(p['pane']==opt('--pane') for p in t['terminals']))
  tab['terminals'].append({'terminal':'tboard','pane':'pboard','status':None,'app':None,'name':None,'sub_agents':[]})
  terms=json.loads((core/'terminals.json').read_text()); terms.append({'address':'tboard','name':None,'parent':None,'cols':120,'rows':40,'status':None,'reported':False})
  write(core/'terminals.json',terms); result={'pane':'pboard','terminal':'tboard'}
 elif cmd=='terminal.park':
  for space in ui['spaces']:
   for tab in space['tabs']: tab['terminals']=[t for t in tab['terminals'] if t['terminal']!=opt('--terminal')]
  result={'pending':True,'terminal':opt('--terminal')}
 else: raise ValueError('unhandled '+str(args))
 write(s/'ls.json',ui); print(json.dumps(result))
except Exception as e:
 print(str(e),file=sys.stderr); sys.exit(1)
MOCK
chmod +x "$MOCK_BIN/hc" "$MOCK_BIN/herdr-app"
assert_child_resolves hc "$MOCK_BIN/hc"
assert_child_resolves herdr-app "$MOCK_BIN/herdr-app"
app_fixture() {
  unset HERDR_ENV HERDR_FLAVOR HERDR_BACKEND_RUN_DIR
  export HC_TERMINAL_ID=t1
  rm -f "$HC_SCENARIO"/* "$APP_SCENARIO"/*
  cat >"$HC_SCENARIO/terminals.json" <<'JSON'
[{"address":"t1","agent":"fixture","argv":["fixture"],"name":null,"parent":null,"state":"live","cols":114,"rows":31,"reported":true,"status":{"app":"fixture","state":"idle"},"status_ms":null,"title":"Own terminal","cwd":"/tmp/own-worktree","labels":{},"turn":0}]
JSON
  cat >"$APP_SCENARIO/ls.json" <<'JSON'
{"spaces":[{"id":"sp1","name":"old space","folder":"/tmp","active":true,"tabs":[{"id":"tb1","name":"old tab","active":true,"settled":false,"terminals":[{"terminal":"t1","pane":"pa1","status":"idle","app":"fixture","name":null,"sub_agents":[]}]}]}],"recent":[]}
JSON
  printf 'line 1\nline 2\nlast real line\n\n   \n' >"$HC_SCENARIO/pane.txt"
  : >"$MOCK_LOG"
}
