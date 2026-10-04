#!/usr/bin/env bash
# Guard-contract suite for the Playwright MCP browser lifetime (feat-one-shot-playwright-mcp-stability).
#
# The defect: a plugin Stop hook SIGTERMed every Playwright Chrome on the host at the end of
# EVERY assistant turn (Stop fires per turn, not per session), and the project .mcp.json
# launch string pkill -9'd the proxy, the server and Chrome of every sibling session. The
# fix removes both killers and replaces the launch-time reaper with a kernel flock slot
# lease (scripts/playwright-mcp-profile-slot.sh). This suite pins the properties:
#
#   Guard 1 -- no registered hook and no MCP launch string terminates a browser it did not
#              launch (population derived by parsing hooks.json and both .mcp.json at test
#              time; a planted fixture proves the scan ran; a live decoy proves the old
#              hook text really kills);
#   Guard 2 -- a launch claims a slot no live launch holds and kills nothing (the real
#              launch string, executed under a scratch HOME with an npx shim);
#   Guard 3 -- both registrations carry the ping-timeout setting (an INERT latent-hazard
#              guard on stdio, not the fix) and the plugin registration carries
#              --chromium-fallback.
#
# Verification hygiene (mirrors playwright-mcp-redact-proxy.test.sh): ok/bad helpers, an
# instrument self-test and a helper control that must REJECT, mutants asserted to have
# LANDED against a pristine copy, an anti-vacuity floor bound adjacent to the floor block
# and reported with printf + exit (never through the helpers it backstops).
#
# SAFETY. No row here terminates a process this suite did not start. Every decoy, holder
# and sleeper is recorded in $OWN when it is spawned and only those pids are ever signalled.
# The old hook text is executed ONLY under a scratch PATH whose pgrep/pidof print the decoy
# pid and nothing else, and whose pkill/killall signal the decoy and nothing else. Every
# mutated pkill pattern embeds the unique scratch HOME, so it cannot select a real process.
set -Eeuo pipefail
trap 'printf "[ABORT] line %s: %s (rc=%s)\n" "$LINENO" "$BASH_COMMAND" "$?" >&2' ERR
export TMPDIR="${TMPDIR:-/var/tmp}"
export PLAYWRIGHT_MCP_PROXY_GRACE_S=1

# Refuses an empty, relative, root or synthetic-fs fixture dir (byte-identical copy; the
# fixture-dir-operand-assert suite pins every tracked copy).
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
assert_fixture_dir "$REPO_ROOT"
SKILL_REL=plugins/soleur/skills/agent-browser
SLOT_REL="$SKILL_REL/scripts/playwright-mcp-profile-slot.sh"
PROXY_REL_PATH="$SKILL_REL/scripts/playwright-mcp-redact-proxy.py"
REDACTOR_REL="$SKILL_REL/scripts/redact-a11y-snapshot.py"
LOCKNAME=.pwslot.lock
WORK="$(mktemp -d -t lifetime-suite.XXXXXXXX)"
assert_fixture_dir "$WORK"
OWN="$WORK/own-pids"; : > "$OWN"
own() { printf '%s\n' "$1" >> "$OWN"; }
# Only pids this suite spawned are ever recorded in $OWN, and each is re-verified before the signal: a direct child
# of this shell, or (the npx shim's `sleep 300`) a process whose argv is exactly that and whose pid file lives in $WORK.
reap_own() {
  local p pp a
  while read -r p; do
    [[ -n "$p" ]] || continue
    pp="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ' || true)"
    if [[ "$pp" == "$$" ]]; then kill -KILL "$p" 2>/dev/null || true; fi
  done < "$OWN"
  while read -r p; do
    [[ -n "$p" ]] || continue
    a="$(ps -o args= -p "$p" 2>/dev/null || true)"
    if [[ "$a" == "sleep 300" ]]; then kill -KILL "$p" 2>/dev/null || true; fi
  done < <(cat "$WORK"/g2/*.jsonl.pid 2>/dev/null || true)
}
trap 'reap_own; rm -rf "$WORK"' EXIT

pass=0; fail=0; cases=0; mutants_declared=0; red_rows=0
ok()  { printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL - %s\n' "$1"; fail=$((fail + 1)); }

# ---------------------------------------------------------------------------
# Instrument self-test (runs BEFORE any real row): both verdict helpers must
# move their counters or the suite refuses to continue.
# ---------------------------------------------------------------------------
_p0=$pass; _f0=$fail
ok  "instrument self-test: ok() increments"
bad "instrument self-test: bad() increments (EXPECTED, not a real failure)"
if [[ $pass -ne $((_p0 + 1)) || $fail -ne $((_f0 + 1)) ]]; then
  printf 'INSTRUMENT BROKEN: ok()/bad() did not both move\n' >&2; exit 1
fi
pass=0; fail=0; cases=0

# assert_true <label> <shell-test...> — one observable, one verdict
assert_true() {
  local label="$1"; shift
  cases=$((cases + 1))
  if "$@"; then ok "$label"; else bad "$label"; fi
}
# red <label> <shell-test...> — a mutation row is ok when the DEFECT is observable
red() { local label="$1"; shift; cases=$((cases + 1)); red_rows=$((red_rows + 1)); if "$@"; then ok "$label"; else bad "$label — mutant survived"; fi; }

# ---------------------------------------------------------------------------
# Process helpers (every pid they touch was spawned by this suite)
# ---------------------------------------------------------------------------
# alive <pid>: exists and is not a zombie
alive() { local s; s="$(ps -o stat= -p "${1:-0}" 2>/dev/null || true)"; [[ -n "$s" && "$s" != Z* ]]; }
wait_dead() {  # <pid> <seconds>
  local i=0
  while alive "$1" && [[ $i -lt $(( $2 * 10 )) ]]; do sleep 0.1; i=$((i + 1)); done
  if alive "$1"; then return 1; fi
  return 0
}
# lock_held <lockfile>: a DIFFERENT open file description cannot take the lock (rc 75 = conflict)
lock_held() {
  local rc=0
  [[ -e "$1" ]] || return 1
  flock -n -E 75 "$1" true || rc=$?
  [[ $rc -eq 75 ]]
}
# Spawned in the CURRENT shell (a $(...) subshell would orphan them, and reap_own only signals direct children); the pid
# lands in SPAWNED. A decoy's argv looks like the Chrome a pattern-reaper would select.
SPAWNED=""
start_decoy() { exec_a="$1"; ( exec -a "$exec_a" sleep 300 ) >/dev/null 2>&1 & SPAWNED=$!; own "$SPAWNED"; disown "$SPAWNED"; }
start_sleeper() { sleep 300 >/dev/null 2>&1 & SPAWNED=$!; own "$SPAWNED"; disown "$SPAWNED"; }

# ---------------------------------------------------------------------------
# Guard 1 scanner (python, written once). Population is DERIVED by parsing the
# files at test time: every command of every event of hooks.json, the script file
# each one invokes, the args of .mcp.json and plugins/soleur/.mcp.json, and every
# script those launch strings source.
#   rc 0 clean | 1 a browser/MCP kill by name or pattern was found | 3 population below the floor
# ---------------------------------------------------------------------------
HELP="$WORK/helpers"; mkdir -p "$HELP"
cat > "$HELP/g1_scan.py" <<'PY'
import json, os, re, sys

root, floor_cmds, floor_scripts = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
mode = sys.argv[4] if len(sys.argv) > 4 else "scan"
BROWSER = re.compile(r"chrom|playwright|mcp|remote-debugging|user-data-dir", re.I)
SELECTORS = re.compile(r"\b(pkill|killall|pgrep|pidof)\b")
KILLISH = re.compile(r"(?<![\w-])kill(?![\w-])")


def reasons_for(text):
    """(tool, segment) pairs where a process is selected by a browser/MCP name or pattern and killed."""
    found = []
    has_kill = bool(KILLISH.search(text))
    for seg in re.split(r"[;\n]|&&|\|\||\|", text):
        norm = re.sub(r"\[(\w)\]", r"\1", seg)  # the [c]hrome self-match trick hides the name
        if not BROWSER.search(norm):
            continue
        m = SELECTORS.search(norm)
        if m and (m.group(1) in ("pkill", "killall") or has_kill):
            found.append((m.group(1), norm.strip()[:90]))
        elif re.search(r"\bgrep\b", norm) and has_kill:
            found.append(("grep", norm.strip()[:90]))
    return found


def load_json(path):
    try:
        return json.load(open(path))
    except Exception:
        return {}


plugin_root = os.path.join(root, "plugins/soleur")
commands = []
for event, groups in (load_json(os.path.join(plugin_root, "hooks/hooks.json")).get("hooks") or {}).items():
    for g in groups or []:
        for h in g.get("hooks", []):
            if h.get("type") == "command" and isinstance(h.get("command"), str):
                commands.append((event, h["command"]))
units = []  # (label, path-or-None, text)
scripts = {}
for event, cmd in commands:
    units.append((f"hooks.json {event} command", None, cmd))
    expanded = cmd.replace("${CLAUDE_PLUGIN_ROOT}", plugin_root)
    for tok in re.findall(r"[^\s\"']+\.(?:sh|py|js|mjs)\b", expanded):
        p = tok if os.path.isabs(tok) else os.path.join(root, tok)
        if os.path.isfile(p):
            scripts[os.path.realpath(p)] = p
mcp_strings = 0
sourced = {}
for rel in (".mcp.json", "plugins/soleur/.mcp.json"):
    for name, srv in (load_json(os.path.join(root, rel)).get("mcpServers") or {}).items():
        text = " ".join([str(srv.get("command", ""))] + [str(a) for a in srv.get("args", [])])
        mcp_strings += 1
        units.append((f"{rel}:{name}", None, text))
        for tok in re.findall(r"(?:^|[;&|(\s])(?:\.|source)\s+([^\s;&|\"'<>]+\.sh)\b", text):
            p = tok.replace("${CLAUDE_PLUGIN_ROOT}", plugin_root)
            p = p if os.path.isabs(p) else os.path.join(root, p)
            if os.path.isfile(p):
                sourced[os.path.realpath(p)] = p
for real, p in {**scripts, **sourced}.items():
    text = "\n".join(l for l in open(p, errors="replace").read().splitlines() if not l.lstrip().startswith("#"))
    units.append((os.path.relpath(p, root), p, text))

flagged = []
for label, path, text in units:
    for tool, seg in reasons_for(text):
        flagged.append((label, path, tool, seg, text))

print(f"POP commands={len(commands)} scripts={len(scripts)} mcp={mcp_strings} sourced={len(sourced)}")
if mode == "list-exec":
    # Only scripts whose kill goes through a PATH-resolved pgrep/pkill are ever executed (under the shim).
    for label, path, tool, seg, text in flagged:
        absolute = re.search(r"/\s*(pkill|pgrep|killall|pidof)\b|\b(command|env|exec)\s+(pkill|pgrep|killall|pidof)\b", text)
        if path and tool in ("pgrep", "pkill") and not absolute:
            print(path)
    sys.exit(0)
for label, path, tool, seg, text in flagged:
    print(f"FLAG {label} [{tool}] {seg}")
if len(commands) < floor_cmds or len(scripts) < floor_scripts:
    print("VACUOUS population below the floor")
    sys.exit(3)
sys.exit(1 if flagged else 0)
PY
# g1 <root> [floor-cmds] [floor-scripts] -> sets G1_RC and G1_OUT
G1_FLOOR_CMDS=9      # hooks.json commands at authoring time (4 events), measured on the fixed tree
G1_FLOOR_SCRIPTS=8   # distinct hook scripts those commands invoke, measured on the fixed tree
G1_RC=0; G1_OUT=""
g1() {
  G1_RC=0
  G1_OUT="$(python3 "$HELP/g1_scan.py" "$1" "${2:-$G1_FLOOR_CMDS}" "${3:-$G1_FLOOR_SCRIPTS}" 2>&1)" || G1_RC=$?
}
g1_rc_is() { [[ "$G1_RC" == "$1" ]]; }

# mkroot1 <dir>: the Guard 1 surface of a tree (hooks, both registrations, the slot script) under the same relative paths
mkroot1() {
  local d="$1"
  mkdir -p "$d/plugins/soleur" "$d/$SKILL_REL/scripts"
  cp -R "$REPO_ROOT/plugins/soleur/hooks" "$d/plugins/soleur/"
  cp "$REPO_ROOT/.mcp.json" "$d/.mcp.json"
  cp "$REPO_ROOT/plugins/soleur/.mcp.json" "$d/plugins/soleur/.mcp.json"
  if [[ -f "$REPO_ROOT/$SLOT_REL" ]]; then cp "$REPO_ROOT/$SLOT_REL" "$d/$SLOT_REL"; fi
}
# landed <pristine> <mutated>: the mutation changed the tree
landed() { ! diff -rq "$1" "$2" >/dev/null 2>&1; }

# A synthesized stand-in for the removed hook (cq-test-fixtures-synthesized-only): pattern-select every
# remote-debugging Chrome on the host and signal each, with no regard to who launched it.
OLD_HOOK="$HELP/old-stop-hook.sh"
cat > "$OLD_HOOK" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
cat > /dev/null
PIDS=$(pgrep -f 'chrome.*--remote-debugging-pipe' 2>/dev/null || true)
if [[ -n "$PIDS" ]]; then
  for pid in $PIDS; do kill "$pid" 2>/dev/null || true; done
fi
exit 0
HOOK
chmod +x "$OLD_HOOK"

# Python helper that edits a Guard 1 scratch root. <root> <mutation>
cat > "$HELP/g1_mut.py" <<'PY'
import json, os, shutil, sys

root, mutation, old_hook = sys.argv[1:4]
hj = os.path.join(root, "plugins/soleur/hooks/hooks.json")
d = json.load(open(hj))
KILLER = '#!/usr/bin/env bash\nset -euo pipefail\npkill -9 -f "chrome.*--remote-debugging-pipe" 2>/dev/null || true\nexit 0\n'


def add_group(event, command):
    d["hooks"].setdefault(event, []).append({"hooks": [{"type": "command", "command": command}]})


if mutation == "restore-old-hook":
    shutil.copy(old_hook, os.path.join(root, "plugins/soleur/hooks/browser-cleanup-hook.sh"))
    cmds = [h["command"] for g in d["hooks"].get("Stop", []) for h in g["hooks"]]
    if not any("browser-cleanup-hook.sh" in c for c in cmds):
        add_group("Stop", "${CLAUDE_PLUGIN_ROOT}/hooks/browser-cleanup-hook.sh")
elif mutation == "killer-under-sessionstart":
    open(os.path.join(root, "plugins/soleur/hooks/zz-killer.sh"), "w").write(KILLER)
    add_group("SessionStart", "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/zz-killer.sh\"")
elif mutation == "second-killer-same-event":
    open(os.path.join(root, "plugins/soleur/hooks/zz-killer.sh"), "w").write(KILLER)
    add_group("Stop", "${CLAUDE_PLUGIN_ROOT}/hooks/zz-killer.sh")
elif mutation == "empty-commands":
    d["hooks"] = {}
elif mutation == "mcp-pkill":
    p = os.path.join(root, ".mcp.json")
    m = json.load(open(p))
    a = m["mcpServers"]["playwright"]["args"]
    a[1] = 'pkill -9 -f "[c]hrome.*$prof" 2>/dev/null || true; ' + a[1]
    json.dump(m, open(p, "w"))
elif mutation == "kill-own-child-only":
    open(os.path.join(root, "plugins/soleur/hooks/zz-own.sh"), "w").write('#!/usr/bin/env bash\nsleep 1 &\nkill "$!"\n')
    add_group("Stop", "${CLAUDE_PLUGIN_ROOT}/hooks/zz-own.sh")
elif mutation == "pkill-non-browser":
    open(os.path.join(root, "plugins/soleur/hooks/zz-other.sh"), "w").write('#!/usr/bin/env bash\npkill -f my-unrelated-daemon 2>/dev/null || true\n')
    add_group("Stop", "${CLAUDE_PLUGIN_ROOT}/hooks/zz-other.sh")
else:
    sys.exit(9)
json.dump(d, open(hj, "w"))
PY

# ---------------------------------------------------------------------------
# Helper control: every verdict-owning helper driven with an input it MUST reject.
# Counters are unwound afterwards; the suite refuses to continue unless all rejected.
# ---------------------------------------------------------------------------
_helper_control() {
  local _p=$pass _f=$fail _c=$cases _r=$red_rows _m=$mutants_declared
  local planted="$WORK/hc-planted"; mkroot1 "$planted"
  python3 "$HELP/g1_mut.py" "$planted" killer-under-sessionstart "$OLD_HOOK"
  assert_true 'helper control: assert_true must REJECT false (EXPECTED)' false
  red 'helper control: red must REJECT an unobservable defect (EXPECTED)' false
  g1 "$planted" 1 1
  assert_true 'helper control: a planted killer must make the scanner rc 1, so rc 0 is REJECTED (EXPECTED)' g1_rc_is 0
  g1 "$planted" 999 999
  assert_true 'helper control: a population below the floor must be rc 3, so rc 1 is REJECTED (EXPECTED)' g1_rc_is 1
  assert_true 'helper control: lock_held must be FALSE on a missing lock file (EXPECTED)' lock_held "$WORK/no-such.lock"
  assert_true 'helper control: alive must be FALSE on a pid that does not exist (EXPECTED)' alive 2147483646
  if [[ $fail -ne $((_f + 6)) ]]; then
    printf 'HELPER CONTROL BROKEN: expected 6 rejections, fail %d->%d\n' "$_f" "$fail" >&2; exit 1
  fi
  pass=$_p; fail=$_f; cases=$_c; red_rows=$_r; mutants_declared=$_m
}
_helper_control

# ===========================================================================
# Guard 1 — no registered hook or launch command terminates a browser it did not launch
# ===========================================================================
G1="$WORK/g1"; mkdir -p "$G1"
mkroot1 "$G1/real"
g1 "$G1/real"
assert_true 'Guard 1: the real tree has no hook or launch string that kills a browser or MCP process by name or pattern' g1_rc_is 0
pop_reported() { [[ "$G1_OUT" == *"POP commands="* && "$G1_OUT" != *VACUOUS* ]]; }
assert_true 'Guard 1: the scan examined a population at or above its floor (not vacuous)' pop_reported
assert_true 'Guard 1: hooks.json still parses and keeps stop-hook.sh and unkept-promise-hook.sh (positive proof the Stop event was scanned)' python3 - "$REPO_ROOT/plugins/soleur/hooks/hooks.json" <<'PY'
import json, sys
cmds = [h["command"] for g in json.load(open(sys.argv[1]))["hooks"]["Stop"] for h in g["hooks"]]
sys.exit(0 if any(c.endswith("/stop-hook.sh") for c in cmds) and any(c.endswith("/unkept-promise-hook.sh") for c in cmds) and not any("browser-cleanup" in c for c in cmds) else 1)
PY
assert_true 'Guard 1: plugins/soleur/hooks/browser-cleanup-hook.sh is absent' test ! -e "$REPO_ROOT/plugins/soleur/hooks/browser-cleanup-hook.sh"

# Must-PASS non-canonical inputs: killing only a pid the hook spawned, and pkill on a non-browser name.
mkroot1 "$G1/ok-own"; python3 "$HELP/g1_mut.py" "$G1/ok-own" kill-own-child-only "$OLD_HOOK"
g1 "$G1/ok-own"
assert_true 'Guard 1 must-PASS: a hook that kills only a pid it spawned itself (kill "$!") passes' g1_rc_is 0
mkroot1 "$G1/ok-other"; python3 "$HELP/g1_mut.py" "$G1/ok-other" pkill-non-browser "$OLD_HOOK"
g1 "$G1/ok-other"
assert_true 'Guard 1 must-PASS: pkill on a non-browser name passes' g1_rc_is 0

# Positive proof the scanner can see a killer at all: the synthesized old hook, planted under Stop.
mkroot1 "$G1/planted"; python3 "$HELP/g1_mut.py" "$G1/planted" restore-old-hook "$OLD_HOOK"
g1 "$G1/planted"
assert_true 'Guard 1 positive control: the scanner flags the old hook text registered under Stop (and names pgrep)' bash -c '[[ "$1" == 1 && "$2" == *"FLAG"*"[pgrep]"* ]]' _ "$G1_RC" "$G1_OUT"

# --- live decoy: the old hook text, executed under a scratch PATH, DOES kill a pattern-matched Chrome ---
SHIM="$WORK/shim"; mkdir -p "$SHIM"
cat > "$SHIM/pgrep" <<'SHIMSRC'
#!/usr/bin/env bash
# prints ONLY the decoy pid (or nothing when decoy.pid is empty)
d="$(cat "$(dirname "$0")/decoy.pid")"
if [[ -n "$d" ]]; then printf '%s\n' "$d"; fi
exit 0
SHIMSRC
cp "$SHIM/pgrep" "$SHIM/pidof"
cat > "$SHIM/pkill" <<'SHIMSRC'
#!/usr/bin/env bash
# signals ONLY the decoy, whatever pattern it was handed
d="$(cat "$(dirname "$0")/decoy.pid")"
if [[ -n "$d" ]]; then kill "$d" 2>/dev/null || true; fi
exit 0
SHIMSRC
cp "$SHIM/pkill" "$SHIM/killall"
chmod +x "$SHIM"/pgrep "$SHIM"/pidof "$SHIM"/pkill "$SHIM"/killall
# run_under_shim <script> <pid-the-shim-targets|""> <pid-to-watch> -> 0 when the watched pid is still alive afterwards
run_under_shim() {
  local script="$1" target="$2" watch="$3"
  printf '%s' "$target" > "$SHIM/decoy.pid"
  ( cd "$WORK" && PATH="$SHIM:$PATH" CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/soleur" bash "$script" </dev/null >/dev/null 2>&1 ) || true
  wait_dead "$watch" 1 || true
  alive "$watch"
}
start_decoy 'chrome --remote-debugging-pipe --user-data-dir=/synthetic/decoy-profile'; DECOY=$SPAWNED
printf '%s' "$DECOY" > "$SHIM/decoy.pid"
shim_resolves() { local out; out="$(PATH="$SHIM:$PATH" pgrep anything)"; [[ "$(PATH="$SHIM:$PATH" command -v pgrep)" == "$SHIM/pgrep" && "$out" == "$DECOY" ]]; }
assert_true 'Guard 1 harness: under the scratch PATH pgrep resolves to the shim and prints only the decoy pid' shim_resolves
assert_true 'Guard 1 harness: the decoy is a live process before any hook runs' alive "$DECOY"
cases=$((cases + 1))
if run_under_shim "$OLD_HOOK" "$DECOY" "$DECOY"; then bad 'Guard 1 positive control: the old hook text killed the decoy'; else ok 'Guard 1 positive control: the old hook text killed the decoy (the decoy is a real target)'; fi
# every script the scanner flags on the REAL tree is executed under the shim; the decoy must survive each
start_decoy 'chrome --remote-debugging-pipe --user-data-dir=/synthetic/decoy-profile-2'; DECOY=$SPAWNED
g1_exec_list="$(python3 "$HELP/g1_scan.py" "$REPO_ROOT" "$G1_FLOOR_CMDS" "$G1_FLOOR_SCRIPTS" list-exec)"
live_ok=1
while read -r s; do
  case "$s" in /*) if ! run_under_shim "$s" "$DECOY" "$DECOY"; then live_ok=0; fi ;; esac
done <<< "$g1_exec_list"
assert_true 'Guard 1 live: the decoy survives every flagged script of the real tree, each executed under the shim (the positive control above proves the decoy is killable)' test "$live_ok" = 1
assert_true 'Guard 1 live: the decoy is still alive after the real-tree scripts ran' alive "$DECOY"

# --- Guard 1 mutation matrix: each mutated copy must be flagged (or hit the vacuity floor) ---
g1_mutant() {  # <name> <mutation> <expected-rc> <label>
  local name="$1" mutation="$2" want="$3" label="$4"
  cases=$((cases + 1)); mutants_declared=$((mutants_declared + 1))
  mkroot1 "$G1/m-$name"
  python3 "$HELP/g1_mut.py" "$G1/m-$name" "$mutation" "$OLD_HOOK"
  if ! landed "$G1/real" "$G1/m-$name"; then bad "Guard 1 mutant $name did NOT land"; return 0; fi
  ok "Guard 1 mutant $name landed"
  g1 "$G1/m-$name"
  cases=$((cases + 1)); red_rows=$((red_rows + 1))
  if [[ "$G1_RC" == "$want" ]]; then ok "$label"; else bad "$label — mutant survived (scanner rc $G1_RC, expected $want)"; fi
}
g1_mutant 1-restore-old-hook restore-old-hook 1 'Guard 1 mutant 1: the old hook and its Stop registration restored → RED'
g1_mutant 2-other-event killer-under-sessionstart 1 'Guard 1 mutant 2: a pattern-killing script registered under SessionStart → RED'
g1_mutant 3-second-killer second-killer-same-event 1 'Guard 1 mutant 3: a second killing hook after the compliant ones in the same Stop array → RED'
g1_mutant 4-mcp-pkill mcp-pkill 1 'Guard 1 mutant 4: pkill -9 -f "[c]hrome.*$prof" back in the .mcp.json launch string → RED'
g1_mutant 5-empty-population empty-commands 3 'Guard 1 mutant 5: hooks.json command population emptied → RED (vacuity floor)'
# Mutation 6 (harness): the shim prints nothing, so the old hook kills nothing — the positive control must then FAIL
start_decoy 'chrome --remote-debugging-pipe --user-data-dir=/synthetic/decoy-profile-3'; DECOY=$SPAWNED
red 'Guard 1 mutant 6 (harness): a pgrep shim that prints nothing → the old hook kills nothing, so the positive control would fail (the decoy is what makes it bite)' run_under_shim "$OLD_HOOK" "" "$DECOY"

# ===========================================================================
# Guard 2 — a launch claims a slot no live launch holds, and kills nothing
# ===========================================================================
G2="$WORK/g2"; mkdir -p "$G2/bin"
MCP_ARGS="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['mcpServers']['playwright']['args'][1])" "$REPO_ROOT/.mcp.json")"
MCP_ARG0="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['mcpServers']['playwright']['args'][0])" "$REPO_ROOT/.mcp.json")"
# The npx shim records its argv (one JSON line), records its own pid, and STAYS ALIVE until the proxy ends it.
cat > "$G2/bin/npx" <<'SHIMSRC'
#!/usr/bin/env bash
python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$@" >> "$SHIM_OUT"
echo $$ >> "$SHIM_OUT.pid"
exec sleep 300
SHIMSRC
chmod +x "$G2/bin/npx"

assert_true 'Guard 2: .mcp.json playwright command is bash -c <string>' test "$MCP_ARG0" = "-c"
assert_true 'Guard 2: the launch string carries no pkill, killall or pgrep (no pattern kill anywhere)' bash -c '! grep -Eq "pkill|killall|pgrep" <<< "$1"' _ "$MCP_ARGS"
assert_true 'Guard 2: the launch string sources the slot script and still carries exec env, the proxy, --user-data-dir=$prof, --config and exactly one pin' python3 - "$MCP_ARGS" "$SLOT_REL" "$PROXY_REL_PATH" <<'PY'
import re, sys
s, slot, proxy = sys.argv[1:]
ok = (
    re.search(r"(?:^|;\s*)\.\s+" + re.escape(slot) + r"\s*\|\|\s*exit 1", s) is not None
    and 'exec env' in s and proxy in s
    and s.count("--user-data-dir=$prof") == 1
    and s.count("--config=.claude/playwright-mcp.config.json") == 1
    and len(re.findall(r"@playwright/mcp@[0-9.]+", s)) == 1
    and '[ -n "$prof" ] || exit 1' in s
)
sys.exit(0 if ok else 1)
PY
assert_true 'Guard 2: the slot script exists, uses return (never exit), sets no errexit/nounset, assigns prof, and holds fd 9' python3 - "$REPO_ROOT/$SLOT_REL" <<'PY'
import re, sys
try:
    src = open(sys.argv[1]).read()
except OSError:
    sys.exit(1)
code = "\n".join(l for l in src.splitlines() if not l.lstrip().startswith("#"))
sys.exit(0 if (
    re.search(r"^\s*exit\b", code, re.M) is None
    and re.search(r"\bset\s+-[a-zA-Z]*[eu]", code) is None
    and re.search(r"\breturn\b", code)
    and re.search(r"\bprof=", code)
    and re.search(r"9>", code)
) else 1)
PY
assert_true 'Guard 2: the slot-0 reconnect wait defaults to 7 seconds' bash -c 'grep -Eq "PW_PROFILE_SLOT0_WAIT_S:-7\b" "$1"' _ "$REPO_ROOT/$SLOT_REL"

# mkroot <dir> [slot-script]: a scratch tree holding the launch string's file dependencies
mkroot() {
  local d="$1" slot="${2:-$REPO_ROOT/$SLOT_REL}"
  mkdir -p "$d/$SKILL_REL/scripts" "$d/.claude"
  cp "$REPO_ROOT/$PROXY_REL_PATH" "$REPO_ROOT/$REDACTOR_REL" "$d/$SKILL_REL/scripts/"
  cp "$REPO_ROOT/.claude/playwright-mcp.config.json" "$d/.claude/"
  if [[ -f "$slot" ]]; then cp "$slot" "$d/$SLOT_REL"; fi
}
# launch <tag> <root> <home> <cmd> [VAR=val...] — the launch string under bash -c, stdin held open by a sleeper
launch() {
  local tag="$1" root="$2" home="$3" cmd="$4"; shift 4
  local fifo="$G2/$tag.fifo"
  : > "$G2/$tag.jsonl"; rm -f "$G2/$tag.jsonl.pid" "$fifo"
  mkdir -p "$home"; mkfifo "$fifo"
  sleep 600 > "$fifo" &
  printf '%s' "$!" > "$G2/$tag.sleeper"; own "$!"; disown "$!"
  ( cd "$root" && exec env "$@" SHIM_OUT="$G2/$tag.jsonl" HOME="$home" PATH="$G2/bin:$PATH" bash -c "$cmd" ) < "$fifo" > /dev/null 2> "$G2/$tag.err" &
  printf '%s' "$!" > "$G2/$tag.pid"; own "$!"; disown "$!"
}
wait_ready() {  # <tag> — the shim ran (its argv is recorded) or the launch died first
  local tag="$1" i=0
  while [[ ! -s "$G2/$tag.jsonl" && $i -lt 150 ]]; do
    if ! alive "$(cat "$G2/$tag.pid")"; then break; fi
    sleep 0.1; i=$((i + 1))
  done
  [[ -s "$G2/$tag.jsonl" ]]
}
end_launch() {  # <tag> — close the launch's stdin (kill its sleeper), wait for it to exit
  local tag="$1" s
  s="$(cat "$G2/$tag.sleeper" 2>/dev/null || true)"
  if [[ -n "$s" ]]; then kill "$s" 2>/dev/null || true; fi
  wait_dead "$(cat "$G2/$tag.pid")" 8 || true
}
prof_of() {  # <tag> — the --user-data-dir the server was launched with
  python3 -c 'import json,sys
for l in open(sys.argv[1]):
    for a in json.loads(l):
        if a.startswith("--user-data-dir="): print(a.split("=", 1)[1]); sys.exit(0)' "$G2/$1.jsonl"
}
# run_n <pfx> <root> <home> <cmd> <n> <overlap|sequential> [VAR=val...]
# sets RN_PROFS (one per line), RN_RAN (shims that ran), RN_OVERLAP (every launch alive AND every distinct profile's lock held at one instant)
RN_PROFS=""; RN_RAN=0; RN_OVERLAP=0
run_n() {
  local pfx="$1" root="$2" home="$3" cmd="$4" n="$5" mode="$6" i tag p; shift 6
  RN_PROFS=""; RN_RAN=0; RN_OVERLAP=1
  for ((i = 1; i <= n; i++)); do
    tag="$pfx-$i"
    launch "$tag" "$root" "$home" "$cmd" "$@"
    if wait_ready "$tag"; then RN_RAN=$((RN_RAN + 1)); RN_PROFS+="$(prof_of "$tag")"$'\n'; else RN_OVERLAP=0; fi
    if [[ "$mode" == sequential ]]; then end_launch "$tag"; fi
  done
  for ((i = 1; i <= n; i++)); do
    if ! alive "$(cat "$G2/$pfx-$i.pid")"; then RN_OVERLAP=0; fi
  done
  while read -r p; do
    if [[ -n "$p" ]] && ! lock_held "$p/$LOCKNAME"; then RN_OVERLAP=0; fi
  done <<< "$RN_PROFS"
  for ((i = 1; i <= n; i++)); do end_launch "$pfx-$i"; done
}
rn_distinct() { [[ "$RN_RAN" -eq "$1" && "$(sort -u <<< "$RN_PROFS" | grep -c . || true)" -eq "$1" ]]; }
rn_overlap() { [[ "$RN_OVERLAP" -eq 1 ]]; }
prof0() { printf '%s/.cache/playwright-mcp-profile' "$1"; }
FAST=PW_PROFILE_SLOT0_WAIT_S=0.3

# --- real tree: overlapped launches ---
H="$G2/h-two"
run_n real2 "$REPO_ROOT" "$H" "$MCP_ARGS" 2 overlap "$FAST"
assert_true 'Guard 2: two overlapped launches under one HOME both ran the server and resolve DISTINCT --user-data-dir values' rn_distinct 2
assert_true 'Guard 2: the first launch took the persistent slot 0 profile' bash -c '[[ "$(head -n1 <<< "$1")" == "$2" ]]' _ "$RN_PROFS" "$(prof0 "$H")"
assert_true 'Guard 2: overlap proven — both launches were alive and both slot locks were held at the same instant' rn_overlap
H="$G2/h-three"
run_n real3 "$REPO_ROOT" "$H" "$MCP_ARGS" 3 overlap "$FAST"
assert_true 'Guard 2: a third concurrent launch also gets its own directory (three distinct)' rn_distinct 3
assert_true 'Guard 2: overlap proven for three launches' rn_overlap
lock_free() { if [[ -e "$1" ]] && flock -n "$1" true; then return 0; fi; return 1; }
assert_true 'Guard 2: after every launch exited, slot 0 is free again (the kernel released the lock)' lock_free "$(prof0 "$H")/$LOCKNAME"

# --- the lease belongs to the proxy process: fd 9 is held by it and is NOT inherited by the server child ---
H="$G2/h-fd"
launch fd1 "$REPO_ROOT" "$H" "$MCP_ARGS" "$FAST"
fd_ready=0; if wait_ready fd1; then fd_ready=1; fi
fd_proxy="$(cat "$G2/fd1.pid")"; fd_child="$(head -n1 "$G2/fd1.jsonl.pid" 2>/dev/null || true)"
lease_in_proxy_only() { [[ "$fd_ready" -eq 1 && -n "$fd_child" && "$(readlink "/proc/$fd_proxy/fd/9" 2>/dev/null)" == *"/$LOCKNAME" && ! -e "/proc/$fd_child/fd/9" ]]; }
assert_true 'Guard 2: the lease (fd 9 on the slot lock) is held by the proxy process and is not inherited by the server child, so it dies with the proxy' lease_in_proxy_only
end_launch fd1

# --- a launch kills nothing: a decoy whose argv is `chrome --user-data-dir=<slot0>` survives ---
H="$G2/h-decoy"; mkdir -p "$(prof0 "$H")"
start_decoy "chrome --user-data-dir=$(prof0 "$H")"; DECOY=$SPAWNED
assert_true 'Guard 2 harness: the decoy argv matches the pattern the old reaper used (chrome.*<slot0>), read from /proc, nothing signalled' python3 - "$DECOY" "$(prof0 "$H")" <<'PY'
import re, sys
cmd = open(f"/proc/{sys.argv[1]}/cmdline", "rb").read().replace(b"\0", b" ").decode()
sys.exit(0 if re.search(r"chrome.*" + re.escape(sys.argv[2]), cmd) else 1)
PY
run_n decoy "$REPO_ROOT" "$H" "$MCP_ARGS" 1 overlap "$FAST"
assert_true 'Guard 2: the launch ran (the shim recorded its argv)' test "$RN_RAN" -eq 1
assert_true 'Guard 2: the decoy Chrome is still alive after the launch and its teardown' alive "$DECOY"

# --- stale SingletonLock (dead owner) is cleared and slot 0 reused ---
H="$G2/h-stale"; mkdir -p "$(prof0 "$H")"
sleep 0 & dead=$!; wait "$dead" || true
if alive "$dead"; then dead=2147483646; fi
ln -s "somehost-$dead" "$(prof0 "$H")/SingletonLock"; : > "$(prof0 "$H")/SingletonCookie"; : > "$(prof0 "$H")/SingletonSocket"
run_n stale "$REPO_ROOT" "$H" "$MCP_ARGS" 1 overlap "$FAST"
stale_state() { [[ "$RN_RAN" -eq 1 && "$(head -n1 <<< "$RN_PROFS")" == "$(prof0 "$H")" && ! -e "$(prof0 "$H")/SingletonLock" && ! -L "$(prof0 "$H")/SingletonLock" && ! -e "$(prof0 "$H")/SingletonCookie" && ! -e "$(prof0 "$H")/SingletonSocket" ]]; }
assert_true 'Guard 2 must-PASS: a stale SingletonLock naming a dead pid is cleared (lock, cookie, socket) and slot 0 is reused' stale_state

# --- a live-owner SingletonLock with a FREE flock (proxy gone, Chrome alive): the slot is skipped, the lock left alone ---
H="$G2/h-owner"; mkdir -p "$(prof0 "$H")"
start_sleeper; OWNER=$SPAWNED
ln -s "somehost-$OWNER" "$(prof0 "$H")/SingletonLock"
run_n owner "$REPO_ROOT" "$H" "$MCP_ARGS" 1 overlap "$FAST"
owner_skipped() { [[ "$RN_RAN" -eq 1 && "$(head -n1 <<< "$RN_PROFS")" == "$(prof0 "$H")-1" ]]; }
owner_lock_kept() { if [[ -L "$(prof0 "$H")/SingletonLock" && "$(readlink "$(prof0 "$H")/SingletonLock")" == "somehost-$OWNER" ]] && alive "$OWNER"; then return 0; fi; return 1; }
assert_true 'Guard 2 must-PASS: a free lock but a live-owner SingletonLock skips the slot (the launch lands on slot 1)' owner_skipped
assert_true 'Guard 2 must-PASS: the live owner'"'"'s SingletonLock was left in place and its owner was not touched' owner_lock_kept

# --- a reconnect (the old holder exits within the 7 s wait) reacquires slot 0 rather than moving to slot 1 ---
H="$G2/h-reconnect"
launch rc-old "$REPO_ROOT" "$H" "$MCP_ARGS"
wait_ready rc-old || true
launch rc-new "$REPO_ROOT" "$H" "$MCP_ARGS"
sleep 1
end_launch rc-old
rc_got=0; if wait_ready rc-new; then rc_got=1; fi
rc_prof="$(if [[ $rc_got -eq 1 ]]; then prof_of rc-new; fi)"
end_launch rc-new
assert_true 'Guard 2 must-PASS: a reconnect — the old holder leaves within the wait — reacquires slot 0, not slot 1' test "$rc_got:$rc_prof" = "1:$(prof0 "$H")"

# --- no flock binary: a unique $base-$$ directory, and the server still starts ---
NOFLOCK="$G2/noflock-bin"; mkdir -p "$NOFLOCK"
for t in bash env python3 mkdir rm readlink ps sleep cat dirname basename head sed grep tr ls; do
  tp="$(command -v "$t" 2>/dev/null || true)"; if [[ -n "$tp" && "$t" != flock ]]; then ln -sf "$tp" "$NOFLOCK/$t"; fi
done
cp "$G2/bin/npx" "$NOFLOCK/npx"
H="$G2/h-noflock"; mkdir -p "$H"
: > "$G2/nf.jsonl"; rm -f "$G2/nf.jsonl.pid" "$G2/nf.fifo"; mkfifo "$G2/nf.fifo"
sleep 600 > "$G2/nf.fifo" & printf '%s' "$!" > "$G2/nf.sleeper"; own "$!"; disown "$!"
( cd "$REPO_ROOT" && exec env SHIM_OUT="$G2/nf.jsonl" HOME="$H" PATH="$NOFLOCK" bash -c "$MCP_ARGS" ) < "$G2/nf.fifo" > /dev/null 2> "$G2/nf.err" &
printf '%s' "$!" > "$G2/nf.pid"; own "$!"; disown "$!"
nf_ran=0; if wait_ready nf; then nf_ran=1; fi
nf_prof="$(if [[ $nf_ran -eq 1 ]]; then prof_of nf; fi)"
nf_pid="$(cat "$G2/nf.pid")"
end_launch nf
assert_true 'Guard 2 must-PASS: with no flock on PATH the launch still starts and uses a unique $base-<pid> directory' test "$nf_ran:$nf_prof" = "1:$(prof0 "$H")-$nf_pid"
no_flock_on_path() { ! PATH="$NOFLOCK" command -v flock >/dev/null 2>&1; }
assert_true 'Guard 2 harness: flock really was absent from the restricted PATH' no_flock_on_path

# --- all 32 slots busy: the launch falls back to a unique directory, never blocking, never killing ---
H="$G2/h-full"; mkdir -p "$H/.cache"
cat > "$HELP/hold32.py" <<'PY'
import fcntl, os, sys, time
base, lockname, ready = sys.argv[1:4]
fds = []
for i in range(32):
    d = base if i == 0 else f"{base}-{i}"
    os.makedirs(d, exist_ok=True)
    fd = os.open(os.path.join(d, lockname), os.O_RDWR | os.O_CREAT, 0o644)
    fcntl.flock(fd, fcntl.LOCK_EX)
    fds.append(fd)
open(ready, "w").write("ready")
time.sleep(300)
PY
python3 "$HELP/hold32.py" "$(prof0 "$H")" "$LOCKNAME" "$G2/hold32.ready" >/dev/null 2>&1 &
own "$!"; disown "$!"
for _ in $(seq 1 50); do [[ -e "$G2/hold32.ready" ]] && break; sleep 0.1; done
run_n full "$REPO_ROOT" "$H" "$MCP_ARGS" 1 overlap "$FAST"
full_state() { local p b; p="$(head -n1 <<< "$RN_PROFS")"; b="$(prof0 "$H")"; [[ "$RN_RAN" -eq 1 && "$p" =~ ^"$b"-[0-9]+$ && "${p##*-}" -ge 32 ]]; }
assert_true 'Guard 2 must-PASS: with all 32 slots busy the launch starts on a unique $base-<pid> directory outside the slot range' full_state

# --- sourced-script hygiene: no helper function or _pwslot_ variable leaks into the exec'd shell, no errexit/nounset ---
H="$G2/h-hygiene"; mkdir -p "$H"
hyg="$(cd "$REPO_ROOT" && HOME="$H" PW_PROFILE_SLOT0_WAIT_S=0.3 bash -c '. '"$SLOT_REL"' || exit 1; [ -n "$prof" ] || exit 1; printf "fns=%s vars=%s flags=%s fd9=%s\n" "$(declare -F | grep -c _pwslot || true)" "$(compgen -v | grep -c "^_pwslot" || true)" "$-" "$([ -e /proc/self/fd/9 ] && echo open || echo closed)"' 2>&1 || true)"
hyg_ok() { [[ "$hyg" =~ ^fns=0\ vars=0\ flags=([a-zA-Z]*)\ fd9=open$ ]] && [[ "${BASH_REMATCH[1]}" != *e* && "${BASH_REMATCH[1]}" != *u* ]]; }
assert_true 'Guard 2: after sourcing, no _pwslot_ function or variable remains, errexit/nounset are off, and fd 9 (the lease) is open in the surviving shell' hyg_ok

# --- Guard 2 mutation matrix ---
# slot_mutant <name> <old> <new> [<old2> <new2>] — an edited COPY of the slot script in a scratch tree; every edit must
# occur exactly once in the pristine script and the copy must differ (landed). Sets MROOT (empty when it did not land).
MROOT=""
slot_mutant() {
  local name="$1"; shift
  cases=$((cases + 1)); mutants_declared=$((mutants_declared + 1)); MROOT=""
  local root="$G2/mut-$name"
  mkroot "$root"
  if python3 - "$REPO_ROOT/$SLOT_REL" "$root/$SLOT_REL" "$@" <<'PY'
import sys
src_path, out_path, *edits = sys.argv[1:]
try:
    src = open(src_path).read()
except OSError:
    sys.exit(2)
out = src
for old, new in zip(edits[0::2], edits[1::2]):
    if out.count(old) != 1:
        sys.stderr.write(f"edit target occurs {out.count(old)} times: {old!r}\n"); sys.exit(3)
    out = out.replace(old, new)
if out == src:
    sys.exit(4)
open(out_path, "w").write(out)
PY
  then ok "Guard 2 mutant $name landed"; MROOT="$root"; else bad "Guard 2 mutant $name did NOT land"; fi
}
FLOCK_N='flock -E 75 -w "$_pwslot_wait" 9'
# 1 — the flock deleted: every launch lands on slot 0
slot_mutant 1-no-flock "$FLOCK_N" 'true'
if [[ -n "$MROOT" ]]; then
  run_n g2m1 "$MROOT" "$G2/h-m1" "$MCP_ARGS" 2 overlap "$FAST"
  m1_shared() { if [[ "$RN_RAN" -eq 2 ]] && ! rn_distinct 2; then return 0; fi; return 1; }
  red 'Guard 2 mutant 1: the flock deleted → two launches share one --user-data-dir' m1_shared
fi
# 2 — a pattern kill of the decoy re-added at the end of the script
slot_mutant 2-pkill-decoy 'unset -f _pwslot_claim' 'pkill -9 -f "[c]hrome.*$prof" 2>/dev/null || true; unset -f _pwslot_claim'
if [[ -n "$MROOT" ]]; then
  H="$G2/h-m2"; mkdir -p "$(prof0 "$H")"; start_decoy "chrome --user-data-dir=$(prof0 "$H")"; DECOY=$SPAWNED
  run_n g2m2 "$MROOT" "$H" "$MCP_ARGS" 1 overlap "$FAST"
  m2_decoy_dead() { if [[ "$RN_RAN" -eq 1 ]] && wait_dead "$DECOY" 3; then return 0; fi; return 1; }
  red 'Guard 2 mutant 2: a pkill of chrome.*<slot0> re-added → the decoy dies' m2_decoy_dead
fi
# 3 — a live-owner SingletonLock treated as stale (the owner-alive test inverted): the lock is removed
slot_mutant 3-live-owner-stale 'if ps -p "$_pwslot_pid" >/dev/null 2>&1; then' 'if ! ps -p "$_pwslot_pid" >/dev/null 2>&1; then'
if [[ -n "$MROOT" ]]; then
  H="$G2/h-m3"; mkdir -p "$(prof0 "$H")"; start_sleeper; OWNER=$SPAWNED; ln -s "somehost-$OWNER" "$(prof0 "$H")/SingletonLock"
  run_n g2m3 "$MROOT" "$H" "$MCP_ARGS" 1 overlap "$FAST"
  m3_lock_gone() { if [[ "$RN_RAN" -eq 1 ]] && ! [[ -L "$(prof0 "$H")/SingletonLock" ]]; then return 0; fi; return 1; }
  red 'Guard 2 mutant 3: a live-owner SingletonLock treated as stale → the lock file is removed' m3_lock_gone
fi
# 4 — exhaustion made non-unique (two slots, then slot 0 is reused): a third concurrent launch collides
slot_mutant 4-third-collides '_pwslot_max=32' '_pwslot_max=2' '_pwslot_fallback="$_pwslot_base-$$"' '_pwslot_fallback="$_pwslot_base"'
if [[ -n "$MROOT" ]]; then
  run_n g2m4 "$MROOT" "$G2/h-m4" "$MCP_ARGS" 3 overlap "$FAST"
  m4_collides() { if [[ "$RN_RAN" -eq 3 ]] && ! rn_distinct 3; then return 0; fi; return 1; }
  red 'Guard 2 mutant 4: the third concurrent launch collides after two compliant ones → fewer than three distinct directories' m4_collides
fi
# 5 — dispatch: the slot script is not sourced (the string reduced to the old literal profile)
cases=$((cases + 1)); mutants_declared=$((mutants_declared + 1))
M5_ARGS="$(python3 - "$MCP_ARGS" "$SLOT_REL" <<'PY'
import re, sys
s, slot = sys.argv[1:]
print(re.sub(r"\.\s+" + re.escape(slot) + r"\s*\|\|\s*exit 1;\s*\[ -n \"\$prof\" \]\s*\|\|\s*exit 1;", "prof=$HOME/.cache/playwright-mcp-profile;", s))
PY
)"
if [[ "$M5_ARGS" != "$MCP_ARGS" && "$M5_ARGS" == *'prof=$HOME/.cache/playwright-mcp-profile;'* ]]; then
  ok 'Guard 2 mutant 5-no-source landed'
  H="$G2/h-m5"
  run_n g2m5 "$REPO_ROOT" "$H" "$M5_ARGS" 2 overlap "$FAST"
  m5_unslotted() { if [[ "$RN_RAN" -eq 2 ]] && ! rn_distinct 2 && ! [[ -e "$(prof0 "$H")/$LOCKNAME" ]]; then return 0; fi; return 1; }
  red 'Guard 2 mutant 5: the slot script not sourced → both launches share the profile and no slot lock exists' m5_unslotted
else
  bad 'Guard 2 mutant 5-no-source did NOT land'
fi
# 6 (harness) — the two launches run sequentially: the overlap proof must be FALSE, proving it can tell the difference
run_n g2m6 "$REPO_ROOT" "$G2/h-m6" "$MCP_ARGS" 2 sequential "$FAST"
m6_no_overlap() { if [[ "$RN_RAN" -eq 2 ]] && ! rn_overlap; then return 0; fi; return 1; }
red 'Guard 2 mutant 6 (harness): launches run sequentially instead of overlapped → the overlap proof fails (it observes liveness and held locks)' m6_no_overlap
# 7 — the owner-alive check deleted: a free lock with a live-owner SingletonLock reuses the slot
slot_mutant 7-no-owner-check 'if ps -p "$_pwslot_pid" >/dev/null 2>&1; then' 'if false; then'
if [[ -n "$MROOT" ]]; then
  H="$G2/h-m7"; mkdir -p "$(prof0 "$H")"; start_sleeper; OWNER=$SPAWNED; ln -s "somehost-$OWNER" "$(prof0 "$H")/SingletonLock"
  run_n g2m7 "$MROOT" "$H" "$MCP_ARGS" 1 overlap "$FAST"
  m7_reused() { [[ "$RN_RAN" -eq 1 && "$(head -n1 <<< "$RN_PROFS")" == "$(prof0 "$H")" ]]; }
  red 'Guard 2 mutant 7: a free lock but a live-owner SingletonLock reuses the slot → the launch lands on the owned profile' m7_reused
fi

# ===========================================================================
# Guard 3 — the registrations
# ===========================================================================
PLUGIN_MCP="$REPO_ROOT/plugins/soleur/.mcp.json"
PROJECT_MCP="$REPO_ROOT/.mcp.json"
# reg_ok <file> <project|plugin>: the ping-timeout env is "0" (an inert stdio guard; see the ADR), and the plugin carries --chromium-fallback
reg_ok() {
  python3 - "$1" "$2" <<'PY'
import json, sys
path, kind = sys.argv[1:]
e = json.load(open(path))["mcpServers"]["playwright"]
ok = e.get("env") == {"PLAYWRIGHT_MCP_PING_TIMEOUT_MS": "0"}
if kind == "plugin":
    ok = ok and e["args"].count("--chromium-fallback") == 1 and e["args"].index("--chromium-fallback") < e["args"].index("--")
sys.exit(0 if ok else 1)
PY
}
assert_true 'Guard 3: .mcp.json carries "env": {"PLAYWRIGHT_MCP_PING_TIMEOUT_MS": "0"} (a guard for future pin bumps: inert on stdio in 0.0.78/0.0.83)' reg_ok "$PROJECT_MCP" project
assert_true 'Guard 3: plugins/soleur/.mcp.json carries the same env and a single --chromium-fallback before the -- separator' reg_ok "$PLUGIN_MCP" plugin
reg_mutant() {  # <label> <file> <kind> <python-mutation-src>
  cases=$((cases + 1)); mutants_declared=$((mutants_declared + 1))
  local f="$WORK/reg-mut.json"
  if ! MUTATION="$4" python3 - "$2" "$f" 2>/dev/null <<'PY'
import json, os, sys
d = json.load(open(sys.argv[1]))
e = d["mcpServers"]["playwright"]
exec(os.environ["MUTATION"])
json.dump(d, open(sys.argv[2], "w"))
PY
  then bad "$1 did NOT land (the edit target is absent)"; return 0; fi
  if cmp -s "$2" "$f" || diff -q <(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])), sort_keys=True))' "$2") <(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])), sort_keys=True))' "$f") >/dev/null; then
    bad "$1 did NOT land"; return 0
  fi
  ok "$1 landed"
  cases=$((cases + 1)); red_rows=$((red_rows + 1))
  if reg_ok "$f" "$3"; then bad "$1 — mutant survived"; else ok "$1 → RED"; fi
}
reg_mutant 'Guard 3 mutant 1: the project registration loses its env' "$PROJECT_MCP" project 'e.pop("env", None)'
reg_mutant 'Guard 3 mutant 2: the project env value drifts from 0' "$PROJECT_MCP" project 'e["env"] = {"PLAYWRIGHT_MCP_PING_TIMEOUT_MS": "30000"}'
reg_mutant 'Guard 3 mutant 3: the plugin registration loses its env' "$PLUGIN_MCP" plugin 'e.pop("env", None)'
reg_mutant 'Guard 3 mutant 4: the plugin env key is misspelled' "$PLUGIN_MCP" plugin 'e["env"] = {"PLAYWRIGHT_MCP_PING_TIMEOUT": "0"}'
reg_mutant 'Guard 3 mutant 5: the plugin registration loses --chromium-fallback' "$PLUGIN_MCP" plugin 'e["args"].remove("--chromium-fallback")'

reap_own

# ---------------------------------------------------------------------------
# Verdict. Reported with printf + exit, never through ok()/bad() (ADR-193).
# ---------------------------------------------------------------------------
printf '\n%d passed, %d failed, %d cases (%d mutants, %d mutation rows)\n' "$pass" "$fail" "$cases" "$mutants_declared" "$red_rows"

if [[ $((pass + fail)) -ne $cases ]]; then
  printf '[FATAL] vacuity accounting: pass+fail (%d) != cases (%d) — a row did not report\n' "$((pass + fail))" "$cases" >&2
  exit 1
fi
EXPECTED_MUTANTS=16   # Guard 1 mutants 1-5 (6 is a harness row), Guard 2 mutants 1-5 and 7 (6 is a harness row), Guard 3 mutants 1-5
EXPECTED_RED_ROWS=18   # the 16 mutants plus the two harness rows (Guard 1 #6, Guard 2 #6)
if [[ $mutants_declared -ne $EXPECTED_MUTANTS || $red_rows -ne $EXPECTED_RED_ROWS ]]; then
  printf '[FATAL] mutation matrix: %d mutants / %d mutation rows ran, expected %d / %d — a row vanished\n' "$mutants_declared" "$red_rows" "$EXPECTED_MUTANTS" "$EXPECTED_RED_ROWS" >&2
  exit 1
fi
MIN_ASSERTIONS=71
if [[ $cases -lt $MIN_ASSERTIONS ]]; then
  printf '[FATAL] vacuity floor: only %d cases executed, expected at least %d\n' "$cases" "$MIN_ASSERTIONS" >&2
  exit 1
fi
[[ $fail -eq 0 ]] || exit 1
exit 0
