#!/usr/bin/env bash
# Guard-contract suite for the Playwright MCP browser lifetime (feat-one-shot-playwright-mcp-stability).
#
# The defect: a plugin Stop hook SIGTERMed every Playwright Chrome on the host at the end of
# EVERY assistant turn (Stop fires per turn, not per session), and the project .mcp.json
# launch string pkill -9'd the proxy, the server and Chrome of every sibling session. The
# fix removes both killers and replaces the launch-time reaper with a kernel flock slot
# lease (scripts/playwright-mcp-profile-slot.sh). This suite pins the properties:
#
#   Guard 1 -- no hook registered in plugins/soleur/hooks/hooks.json or .claude/settings.json and no
#              MCP launch string names a browser with a PID-selecting tool (population derived by
#              parsing the registries at test time, plus one hop of sourced scripts), and the
#              plugin hook scripts, executed under a pgrep/pkill PATH shim, leave a live decoy alone.
#              This is a text-and-shim property of THIS tree's registries: other plugins, older
#              checkouts, the installed plugin copy and tools the shim does not cover are outside it.
#              Project hooks (.claude/hooks) are scanned, never executed: running them is not safe;
#   Guard 2 -- a launch claims a slot no live launch holds and kills nothing (the real
#              launch string, executed under a scratch HOME with an npx shim);
#   Guard 3 -- both registrations carry the ping-timeout setting (an INERT latent-hazard
#              guard on stdio, not the fix) and the plugin registration carries
#              --chromium-fallback.
#
# Verification hygiene (mirrors playwright-mcp-redact-proxy.test.sh): ok/bad helpers, an
# instrument self-test and a helper control that must REJECT (for every verdict-owning helper,
# including the inline verdicts of the mutant helpers), mutants asserted to have LANDED against a
# pristine copy, an anti-vacuity floor bound adjacent to the floor block and reported with printf +
# exit (never through the helpers it backstops).
#
# SAFETY. No row here terminates a process this suite did not start. Every decoy, holder
# and sleeper is recorded in $OWN when it is spawned and only those pids are ever signalled.
# The old hook text is executed ONLY under a scratch PATH whose pgrep/pidof print the decoy
# pid and nothing else, and whose pkill/killall signal the decoy and nothing else (ps, fuser and lsof
# print nothing). Every mutated pkill pattern embeds the unique scratch HOME, so it cannot select a
# real process. The slot script only ever runs with HOME pointed at a scratch directory.
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
# reap_list <file of pids>: signal each recorded pid that is a direct child of this shell
reap_list() {
  local p pp
  while read -r p; do
    [[ -n "$p" ]] || continue
    pp="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ' || true)"
    if [[ "$pp" == "$$" ]]; then kill -KILL "$p" 2>/dev/null || true; fi
  done < "$1"
}
reap_own() {
  local p a
  reap_list "$OWN"
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
lock_free() { if [[ -e "$1" ]] && flock -n "$1" true; then return 0; fi; return 1; }
# landed <pristine> <mutated>: the mutation changed the tree
landed() { ! diff -rq "$1" "$2" >/dev/null 2>&1; }
now_ms() { printf '%s' "$(( ${EPOCHREALTIME/./} / 1000 ))"; }
# Spawned in the CURRENT shell (a $(...) subshell would orphan them, and reap_own only signals direct children); the pid
# lands in SPAWNED. A decoy's argv looks like the Chrome a pattern-reaper would select.
SPAWNED=""
start_decoy() { exec_a="$1"; ( exec -a "$exec_a" sleep 300 ) >/dev/null 2>&1 & SPAWNED=$!; own "$SPAWNED"; disown "$SPAWNED"; }
start_sleeper() { sleep 300 >/dev/null 2>&1 & SPAWNED=$!; own "$SPAWNED"; disown "$SPAWNED"; }
# a decoy that holds <file> open (fd 7) and carries <argv>: the shape a file-handle-selecting killer targets
start_holder() { local a="$1" f="$2"; ( exec 7> "$f"; exec -a "$a" sleep 300 ) >/dev/null 2>&1 & SPAWNED=$!; own "$SPAWNED"; disown "$SPAWNED"; }
# a process whose comm really is "chrome" (a symlink to sleep): the only way a pid probe reads a Chrome-like comm
CHROMEBIN="$WORK/chromebin"; mkdir -p "$CHROMEBIN"; ln -sf "$(command -v sleep)" "$CHROMEBIN/chrome"
start_chrome_owner() { "$CHROMEBIN/chrome" 300 >/dev/null 2>&1 & SPAWNED=$!; own "$SPAWNED"; disown "$SPAWNED"; }
# hold_lock <profile-dir> <seconds> [owner-pid]: a holder (own child, no-fork flock) on <dir>/.pwslot.lock; the owner file records [owner-pid]
hold_lock() {
  local d="$1" secs="$2" i
  assert_fixture_dir "$d"
  mkdir -p "$d"; : > "$d/$LOCKNAME"
  if [[ -n "${3:-}" ]]; then printf '%s\n' "$3" > "$d/.pwslot.owner"; fi
  flock -F "$d/$LOCKNAME" sleep "$secs" >/dev/null 2>&1 & SPAWNED=$!; own "$SPAWNED"; disown "$SPAWNED"
  for i in $(seq 1 50); do if lock_held "$d/$LOCKNAME"; then break; fi; sleep 0.1; done
}
HOST_NOW="$(uname -n)"

# ---------------------------------------------------------------------------
# Guard 1 scanner (python, written once). Population is DERIVED by parsing the
# files at test time: every command of every event of plugins/soleur/hooks/hooks.json and of
# .claude/settings.json, the script file each one invokes, one hop of scripts those scripts
# source or run, the args of .mcp.json and plugins/soleur/.mcp.json, and every script those launch
# strings source.
#   rc 0 clean | 1 a browser/MCP kill by name or pattern was found | 3 population below a floor
# Modes: scan (default) | list-exec (the scripts the dynamic rows execute under the shim)
# ---------------------------------------------------------------------------
HELP="$WORK/helpers"; mkdir -p "$HELP"
cat > "$HELP/g1_scan.py" <<'PY'
import json, os, re, sys

root = sys.argv[1]
floor_vals = [int(x) for x in sys.argv[2:6]]
mode = sys.argv[6] if len(sys.argv) > 6 else "scan"
FLOOR_NAMES = [("commands", "G1_FLOOR_CMDS"), ("scripts", "G1_FLOOR_SCRIPTS"), ("mcp", "G1_FLOOR_MCP"), ("sourced", "G1_FLOOR_SOURCED")]
BROWSER = re.compile(r"chrom|playwright|mcp|remote-debugging|user-data-dir|headless_shell", re.I)
SELECTORS = re.compile(r"\b(pkill|killall|pgrep|pidof)\b")
KILLISH = re.compile(r"(?<![\w-])kill(?![\w-])")
SCRIPT_TOKEN = re.compile(r"[^\s\"']+\.(?:sh|py|js|mjs|cjs|ts)\b")
HOP_TOKEN = re.compile(r"(?:^|[;&|(\s])(?:\.|source|bash|sh|exec)\s+[\"']?([^\s;&|\"'<>)]+\.(?:sh|py))")


def reasons_for(text):
    """(tool, segment) pairs where a process is selected by a browser/MCP name or pattern and killed."""
    found = []
    text = re.sub(r"\\\n[ \t]*", " ", text)  # a backslash-continued command is one command
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


def code_of(path):
    return "\n".join(l for l in open(path, errors="replace").read().splitlines() if not l.lstrip().startswith("#"))


plugin_root = os.path.join(root, "plugins/soleur")
VARS = [
    ('"$CLAUDE_PROJECT_DIR"', root), ('"${CLAUDE_PROJECT_DIR}"', root), ("${CLAUDE_PROJECT_DIR}", root), ("$CLAUDE_PROJECT_DIR", root),
    ('"${CLAUDE_PLUGIN_ROOT}"', plugin_root), ("${CLAUDE_PLUGIN_ROOT}", plugin_root), ("$CLAUDE_PLUGIN_ROOT", plugin_root),
]


def expand(s):
    for k, v in VARS:
        s = s.replace(k, v)
    return s


def commands_of(path):
    out = []
    for event, groups in (load_json(path).get("hooks") or {}).items():
        for g in groups or []:
            for h in g.get("hooks", []):
                if h.get("type") == "command" and isinstance(h.get("command"), str):
                    out.append((event, h["command"]))
    return out


def scripts_of(commands):
    found = {}
    for _event, cmd in commands:
        for tok in SCRIPT_TOKEN.findall(expand(cmd)):
            p = tok if os.path.isabs(tok) else os.path.join(root, tok)
            if os.path.isfile(p):
                found[os.path.realpath(p)] = p
    return found


def resolve_hop(tok, script):
    sdir = os.path.dirname(script)
    names = {"SCRIPT_DIR": sdir, "HOOK_DIR": sdir, "HOOKS_DIR": sdir, "HERE": sdir, "DIR": sdir,
             "PLUGIN_ROOT": plugin_root, "CLAUDE_PLUGIN_ROOT": plugin_root,
             "CLAUDE_PROJECT_DIR": root, "REPO_ROOT": root, "PROJECT_ROOT": root, "GIT_ROOT": root}
    t = re.sub(r"\$\(dirname[^)]*\)", sdir, tok)
    t = re.sub(r"\$\{?(\w+)\}?", lambda m: names.get(m.group(1), m.group(0)), t)
    if "$" in t:
        tail = re.split(r"\$\{?\w+\}?", t)[-1].lstrip("/")
        cands = [os.path.join(b, tail) for b in (sdir, os.path.join(sdir, ".."), plugin_root, root)]
    else:
        cands = [t if os.path.isabs(t) else os.path.join(sdir, t), t if os.path.isabs(t) else os.path.join(root, t)]
    for c in cands:
        c = os.path.normpath(c)
        if os.path.isfile(c):
            return c
    return None


def hops_of(files):
    found = {}
    for p in files:
        for tok in HOP_TOKEN.findall(code_of(p)):
            r = resolve_hop(tok, p)
            if r:
                found[os.path.realpath(r)] = r
    return found


commands = commands_of(os.path.join(plugin_root, "hooks/hooks.json"))
settings_commands = commands_of(os.path.join(root, ".claude/settings.json"))
scripts = scripts_of(commands)
settings_scripts = scripts_of(settings_commands)
units = []  # (label, text)
for event, cmd in commands:
    units.append((f"hooks.json {event} command", cmd))
for event, cmd in settings_commands:
    units.append((f"settings.json {event} command", cmd))
mcp_strings = 0
sourced = {}
for rel in (".mcp.json", "plugins/soleur/.mcp.json"):
    for name, srv in (load_json(os.path.join(root, rel)).get("mcpServers") or {}).items():
        text = " ".join([str(srv.get("command", ""))] + [str(a) for a in srv.get("args", [])])
        mcp_strings += 1
        units.append((f"{rel}:{name}", text))
        for tok in re.findall(r"(?:^|[;&|(\s])(?:\.|source)\s+([^\s;&|\"'<>]+\.sh)\b", text):
            p = tok.replace("${CLAUDE_PLUGIN_ROOT}", plugin_root)
            p = p if os.path.isabs(p) else os.path.join(root, p)
            if os.path.isfile(p):
                sourced[os.path.realpath(p)] = p
plugin_side = {**scripts, **sourced}
hops_plugin = {k: v for k, v in hops_of(plugin_side.values()).items() if k not in plugin_side}
hops_settings = {k: v for k, v in hops_of(settings_scripts.values()).items() if k not in settings_scripts and k not in plugin_side}
everything = {**plugin_side, **settings_scripts, **hops_plugin, **hops_settings}
for real, p in everything.items():
    units.append((os.path.relpath(p, root), code_of(p)))

flagged = []
for label, text in units:
    for tool, seg in reasons_for(text):
        flagged.append((label, tool, seg))

pop = {"commands": len(commands), "scripts": len(scripts), "mcp": mcp_strings, "sourced": len(sourced)}
print(f"POP commands={len(commands)} scripts={len(scripts)} mcp={mcp_strings} sourced={len(sourced)} "
      f"settings={len(settings_commands)} settings_scripts={len(settings_scripts)} hops={len(hops_plugin) + len(hops_settings)}")
if mode == "list-exec":
    # Plugin hook scripts and what they pull in, plus the scripts the launch strings source. Project hooks are NOT executed.
    for p in scripts.values():
        print(("RUN\t" if p.endswith((".sh", ".py")) else "STATIC\t") + p)
    for p in list(sourced.values()) + list(hops_plugin.values()):
        print(("SRC\t" if p.endswith(".sh") else "STATIC\t") + p)
    sys.exit(0)
for label, tool, seg in flagged:
    print(f"FLAG {label} [{tool}] {seg}")
low = [f"{key}={pop[key]} < {name}={floor}" for (key, name), floor in zip(FLOOR_NAMES, floor_vals) if pop[key] < floor]
if low:
    print("VACUOUS population below the floor: " + ", ".join(low)
          + "; lower the named constant in playwright-mcp-lifetime.test.sh only when hooks or registrations were legitimately removed")
    sys.exit(3)
sys.exit(1 if flagged else 0)
PY
# g1 <root> [floor-cmds] [floor-scripts] [floor-mcp] [floor-sourced] -> sets G1_RC and G1_OUT
# The two hook floors are SLACK on purpose (proof the scan ran, not a pin of someone else's registry); the planted-fixture
# rows below are the real positive control. When one fires the message names the constant to lower.
G1_FLOOR_CMDS=6
G1_FLOOR_SCRIPTS=5
G1_FLOOR_MCP=2        # .mcp.json plus plugins/soleur/.mcp.json
G1_FLOOR_SOURCED=1    # the slot script, sourced by the project launch string
G1_FLOOR_RUN=5        # population scripts the dynamic rows must have executed under the shim
G1_RC=0; G1_OUT=""
g1() {
  G1_RC=0
  G1_OUT="$(python3 "$HELP/g1_scan.py" "$1" "${2:-$G1_FLOOR_CMDS}" "${3:-$G1_FLOOR_SCRIPTS}" "${4:-$G1_FLOOR_MCP}" "${5:-$G1_FLOOR_SOURCED}" 2>&1)" || G1_RC=$?
}
g1_rc_is() { [[ "$G1_RC" == "$1" ]]; }

# mkroot1 <dir>: the Guard 1 surface of a tree (both hook registries and their scripts, both registrations, the slot script) under the same relative paths
mkroot1() {
  local d="$1"
  assert_fixture_dir "$d"
  mkdir -p "$d/plugins/soleur" "$d/$SKILL_REL/scripts" "$d/.claude" "$d/scripts"
  cp -R "$REPO_ROOT/plugins/soleur/hooks" "$d/plugins/soleur/"
  cp -R "$REPO_ROOT/plugins/soleur/scripts" "$d/plugins/soleur/"
  cp -R "$REPO_ROOT/.claude/hooks" "$d/.claude/"
  cp "$REPO_ROOT/.claude/settings.json" "$d/.claude/settings.json"
  cp "$REPO_ROOT/scripts/ensure-kb-index.sh" "$d/scripts/ensure-kb-index.sh"
  cp "$REPO_ROOT/.mcp.json" "$d/.mcp.json"
  cp "$REPO_ROOT/plugins/soleur/.mcp.json" "$d/plugins/soleur/.mcp.json"
  if [[ -f "$REPO_ROOT/$SLOT_REL" ]]; then cp "$REPO_ROOT/$SLOT_REL" "$d/$SLOT_REL"; fi
}

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

# Python helper that edits a Guard 1 scratch root. <root> <mutation> <old-hook>
# Mutations that plant a killer body: vocab-<word> | killall-chrome | pidof-chrome | ps-grep-kill | continuation | indirection | split-word
cat > "$HELP/g1_mut.py" <<'PY'
import json, os, shutil, sys

root, mutation, old_hook = sys.argv[1:4]
if mutation == "noop":
    sys.exit(0)
hj = os.path.join(root, "plugins/soleur/hooks/hooks.json")
d = json.load(open(hj))
KILLER = '#!/usr/bin/env bash\nset -euo pipefail\npkill -9 -f "chrome.*--remote-debugging-pipe" 2>/dev/null || true\nexit 0\n'
BODIES = {
    "killall-chrome": 'killall -9 chrome 2>/dev/null || true',
    "pidof-chrome": 'kill $(pidof chrome) 2>/dev/null || true',
    "ps-grep-kill": "ps aux | grep chrome | awk '{print $2}' | xargs kill 2>/dev/null || true",
    "continuation": 'pkill -9 -f \\\n  "chrome.*--remote-debugging-pipe" 2>/dev/null || true',
    "indirection": 'PAT="chrome.*--remote-debugging-pipe"\npkill -9 -f "$PAT" 2>/dev/null || true',
    "split-word": 'pkill -9 -f "chr""ome" 2>/dev/null || true',
}


def add_group(event, command):
    d["hooks"].setdefault(event, []).append({"hooks": [{"type": "command", "command": command}]})


def write(path, text, mode=0o755):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").write(text)
    os.chmod(path, mode)


def plant(body):
    write(os.path.join(root, "plugins/soleur/hooks/zz-killer.sh"), "#!/usr/bin/env bash\n" + body + "\nexit 0\n")
    add_group("Stop", "${CLAUDE_PLUGIN_ROOT}/hooks/zz-killer.sh")


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
elif mutation == "second-in-group":
    open(os.path.join(root, "plugins/soleur/hooks/zz-killer.sh"), "w").write(KILLER)
    d["hooks"]["Stop"][0]["hooks"].append({"type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/zz-killer.sh"})
elif mutation == "empty-commands":
    d["hooks"] = {}
elif mutation == "mcp-pkill":
    p = os.path.join(root, ".mcp.json")
    m = json.load(open(p))
    a = m["mcpServers"]["playwright"]["args"]
    a[1] = 'pkill -9 -f "[c]hrome.*$prof" 2>/dev/null || true; ' + a[1]
    json.dump(m, open(p, "w"))
elif mutation == "plugin-mcp-pkill":
    p = os.path.join(root, "plugins/soleur/.mcp.json")
    m = json.load(open(p))
    m["mcpServers"]["reaper"] = {"command": "bash", "args": ["-c", "pkill -9 -f chrome; exec true"]}
    json.dump(m, open(p, "w"))
elif mutation == "drop-plugin-mcp":
    p = os.path.join(root, "plugins/soleur/.mcp.json")
    json.dump({"mcpServers": {}}, open(p, "w"))
elif mutation == "drop-sourced":
    p = os.path.join(root, ".mcp.json")
    m = json.load(open(p))
    a = m["mcpServers"]["playwright"]["args"]
    a[1] = a[1].replace(". plugins/soleur/skills/agent-browser/scripts/playwright-mcp-profile-slot.sh || exit 1;", "prof=$HOME/.cache/playwright-mcp-profile;")
    json.dump(m, open(p, "w"))
elif mutation == "sourced-killer":
    p = os.path.join(root, "plugins/soleur/skills/agent-browser/scripts/playwright-mcp-profile-slot.sh")
    open(p, "a").write('\npkill -9 -f "chrome.*$prof" 2>/dev/null || true\n')
elif mutation == "settings-killer":
    write(os.path.join(root, ".claude/hooks/zz-killer.sh"), KILLER)
    sp = os.path.join(root, ".claude/settings.json")
    s = json.load(open(sp))
    s["hooks"].setdefault("PreToolUse", []).append({"matcher": "Bash", "hooks": [{"type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/zz-killer.sh"}]})
    json.dump(s, open(sp, "w"))
elif mutation == "hop-killer":
    write(os.path.join(root, "plugins/soleur/hooks/lib/zz-helper.sh"), KILLER, 0o644)
    write(os.path.join(root, "plugins/soleur/hooks/zz-hook.sh"),
          '#!/usr/bin/env bash\nSCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\nsource "$SCRIPT_DIR/lib/zz-helper.sh"\nexit 0\n')
    add_group("Stop", "${CLAUDE_PLUGIN_ROOT}/hooks/zz-hook.sh")
elif mutation.startswith("vocab-"):
    plant("pkill -9 -f " + mutation[len("vocab-"):] + " 2>/dev/null || true")
elif mutation in BODIES:
    plant(BODIES[mutation])
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
# Guard 1 dynamic harness: a scratch PATH whose pgrep/pidof print ONLY the decoy pid and whose pkill/killall signal ONLY the
# decoy; ps, fuser and lsof print nothing (so a ps|grep|kill pipeline selects nothing real).
# ---------------------------------------------------------------------------
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
printf '#!/usr/bin/env bash\nexit 0\n' > "$SHIM/ps"
cp "$SHIM/ps" "$SHIM/fuser"; cp "$SHIM/ps" "$SHIM/lsof"
chmod +x "$SHIM"/pgrep "$SHIM"/pidof "$SHIM"/pkill "$SHIM"/killall "$SHIM"/ps "$SHIM"/fuser "$SHIM"/lsof
DYN="$WORK/dyn"; mkdir -p "$DYN/home" "$DYN/proj" "$DYN/tmp"
# run_under_shim <script> <pid-the-shim-targets|""> <pid-to-watch> -> 0 when the watched pid is still alive afterwards
run_under_shim() {
  local script="$1" target="$2" watch="$3"
  printf '%s' "$target" > "$SHIM/decoy.pid"
  ( cd "$WORK" && PATH="$SHIM:$PATH" CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/soleur" bash "$script" </dev/null >/dev/null 2>&1 ) || true
  wait_dead "$watch" 1 || true
  alive "$watch"
}
# dyn_run <RUN|SRC> <path> <plugin-root>: one population script, executed (RUN) or sourced (SRC) under the shim, with a scratch
# HOME, cwd and project dir, a scrubbed environment, no stdin and a time bound
dyn_run() {
  local kind="$1" path="$2" pr="$3"
  local -a runner
  case "$kind:$path" in
    RUN:*.py) runner=(python3 "$path") ;;
    RUN:*)    runner=(bash "$path") ;;
    *)        runner=(bash -c '. "$1"' _ "$path") ;;
  esac
  ( cd "$DYN" && exec env -i PATH="$SHIM:/usr/bin:/bin" HOME="$DYN/home" TMPDIR="$DYN/tmp" CLAUDE_PLUGIN_ROOT="$pr" CLAUDE_PROJECT_DIR="$DYN/proj" timeout 20 "${runner[@]}" </dev/null >/dev/null 2>&1 ) || true
}
# g1_dynamic <root> <decoy-pid>: every executable population script of <root> run under the shim; sets DYN_RAN and DYN_ALIVE
DYN_RAN=0; DYN_ALIVE=1
g1_dynamic() {
  local root="$1" decoy="$2" kind path
  DYN_RAN=0
  printf '%s' "$decoy" > "$SHIM/decoy.pid"
  while IFS=$'\t' read -r kind path; do
    case "$kind" in RUN|SRC) : ;; *) continue ;; esac
    dyn_run "$kind" "$path" "$root/plugins/soleur"
    DYN_RAN=$((DYN_RAN + 1))
  done < <(python3 "$HELP/g1_scan.py" "$root" 0 0 0 0 list-exec)
  wait_dead "$decoy" 1 || true
  if alive "$decoy"; then DYN_ALIVE=1; else DYN_ALIVE=0; fi
}

# ---------------------------------------------------------------------------
# Verdict helpers of the mutation matrices (defined before the helper control so the control can drive them)
# ---------------------------------------------------------------------------
G1="$WORK/g1"; mkdir -p "$G1"
G2="$WORK/g2"; mkdir -p "$G2/bin"
# g1_mutant <name> <mutation> <expected-rc> <label> [<flag-substring>]: static verdict; the FLAG line must name the planted unit
g1_mutant() {
  local name="$1" mutation="$2" want="$3" label="$4" flag="${5:-}"
  cases=$((cases + 1)); mutants_declared=$((mutants_declared + 1))
  mkroot1 "$G1/m-$name"
  python3 "$HELP/g1_mut.py" "$G1/m-$name" "$mutation" "$OLD_HOOK"
  if ! landed "$G1/real" "$G1/m-$name"; then bad "Guard 1 mutant $name did NOT land"; return 0; fi
  ok "Guard 1 mutant $name landed"
  g1 "$G1/m-$name"
  cases=$((cases + 1)); red_rows=$((red_rows + 1))
  if [[ "$G1_RC" == "$want" && ( -z "$flag" || "$G1_OUT" == *"FLAG"*"$flag"* ) ]]; then ok "$label"; else bad "$label — mutant survived (scanner rc $G1_RC, expected $want${flag:+, FLAG naming $flag})"; fi
}
# g1_dyn_mutant <name> <mutation> <label>: dynamic verdict — the planted tree's scripts, executed under the shim, kill the decoy
g1_dyn_mutant() {
  local name="$1" mutation="$2" label="$3" d
  cases=$((cases + 1)); mutants_declared=$((mutants_declared + 1))
  mkroot1 "$G1/m-$name"
  python3 "$HELP/g1_mut.py" "$G1/m-$name" "$mutation" "$OLD_HOOK"
  if ! landed "$G1/real" "$G1/m-$name"; then bad "Guard 1 mutant $name did NOT land"; return 0; fi
  ok "Guard 1 mutant $name landed"
  start_decoy "chrome --remote-debugging-pipe --user-data-dir=/synthetic/decoy-$name"; d=$SPAWNED
  g1_dynamic "$G1/m-$name" "$d"
  cases=$((cases + 1)); red_rows=$((red_rows + 1))
  if [[ "$DYN_ALIVE" -eq 0 && "$DYN_RAN" -ge "$G1_FLOOR_RUN" ]]; then ok "$label"; else bad "$label — mutant survived (decoy alive=$DYN_ALIVE after $DYN_RAN scripts)"; fi
}
mkroot() {  # <dir>: a scratch tree holding the launch string's file dependencies
  local d="$1"
  assert_fixture_dir "$d"
  mkdir -p "$d/$SKILL_REL/scripts" "$d/.claude"
  cp "$REPO_ROOT/$PROXY_REL_PATH" "$d/$SKILL_REL/scripts/"
  cp "$REPO_ROOT/$REDACTOR_REL" "$d/$SKILL_REL/scripts/"
  cp "$REPO_ROOT/.claude/playwright-mcp.config.json" "$d/.claude/"
  if [[ -f "$REPO_ROOT/$SLOT_REL" ]]; then cp "$REPO_ROOT/$SLOT_REL" "$d/$SLOT_REL"; fi
}
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

# ---------------------------------------------------------------------------
# Helper control: every verdict-owning helper driven with an input it MUST reject.
# Counters are unwound afterwards; the suite refuses to continue unless all rejected. The controls
# report with printf + exit, never through the helper under test.
# ---------------------------------------------------------------------------
hc_broken() { printf 'HELPER CONTROL BROKEN: %s\n' "$1" >&2; exit 1; }
_helper_control() {
  local _p=$pass _f=$fail _c=$cases _r=$red_rows _m=$mutants_declared
  local planted="$WORK/hc-planted"; mkroot1 "$planted"
  python3 "$HELP/g1_mut.py" "$planted" killer-under-sessionstart "$OLD_HOOK"
  assert_true 'helper control: assert_true must REJECT false (EXPECTED)' false
  red 'helper control: red must REJECT an unobservable defect (EXPECTED)' false
  g1 "$planted" 1 1 0 0
  assert_true 'helper control: a planted killer must make the scanner rc 1, so rc 0 is REJECTED (EXPECTED)' g1_rc_is 0
  g1 "$planted" 999 999 0 0
  assert_true 'helper control: a population below the floor must be rc 3, so rc 1 is REJECTED (EXPECTED)' g1_rc_is 1
  assert_true 'helper control: lock_held must be FALSE on a missing lock file (EXPECTED)' lock_held "$WORK/no-such.lock"
  assert_true 'helper control: alive must be FALSE on a pid that does not exist (EXPECTED)' alive 2147483646
  if [[ $fail -ne $((_f + 6)) ]]; then
    hc_broken "expected 6 rejections, fail $_f->$fail"
  fi
  # lock_held / lock_free: an existing UNLOCKED file and a LOCKED one, both ways
  local unlocked="$WORK/hc-unlocked.lock" locked="$WORK/hc-locked.lock" hp i rc
  : > "$unlocked"; : > "$locked"
  flock -F "$locked" sleep 30 >/dev/null 2>&1 & hp=$!; own "$hp"; disown "$hp"
  for i in $(seq 1 50); do rc=0; flock -n -E 75 "$locked" true || rc=$?; if [[ $rc -eq 75 ]]; then break; fi; sleep 0.1; done
  if lock_held "$unlocked"; then hc_broken "lock_held accepted an existing but UNLOCKED file"; fi
  if ! lock_held "$locked"; then hc_broken "lock_held rejected a LOCKED file"; fi
  if lock_free "$locked"; then hc_broken "lock_free accepted a LOCKED file"; fi
  if ! lock_free "$unlocked"; then hc_broken "lock_free rejected an UNLOCKED file"; fi
  kill -KILL "$hp" 2>/dev/null || true
  # landed: identical trees are not a landing, differing trees are
  mkdir -p "$WORK/hc-l1" "$WORK/hc-l2"; : > "$WORK/hc-l1/a"; : > "$WORK/hc-l2/a"
  if landed "$WORK/hc-l1" "$WORK/hc-l2"; then hc_broken "landed accepted identical trees"; fi
  : > "$WORK/hc-l2/b"
  if ! landed "$WORK/hc-l1" "$WORK/hc-l2"; then hc_broken "landed rejected differing trees"; fi
  # g1_mutant: a no-op mutation must be reported as not landed; a landed mutant the scanner does not flag must be reported as surviving
  local f0=$fail p0=$pass r0=$red_rows
  g1_mutant ctl-noop noop 1 'helper control: no-op' >/dev/null
  if [[ $fail -ne $((f0 + 1)) || $red_rows -ne $r0 ]]; then hc_broken "g1_mutant accepted a no-op mutation"; fi
  f0=$fail; p0=$pass
  g1_mutant ctl-survive pkill-non-browser 1 'helper control: unflagged mutant' >/dev/null
  if [[ $fail -ne $((f0 + 1)) || $pass -ne $((p0 + 1)) ]]; then hc_broken "g1_mutant passed a landed mutant the scanner does not flag"; fi
  f0=$fail; p0=$pass
  g1_mutant ctl-flag second-killer-same-event 1 'helper control: wrong unit named' 'no-such-unit' >/dev/null
  if [[ $fail -ne $((f0 + 1)) ]]; then hc_broken "g1_mutant passed a mutant flagged for the wrong unit"; fi
  # g1_dyn_mutant: a no-op is not a landing, and a landed tree whose scripts kill nothing under the shim is a surviving mutant
  f0=$fail
  g1_dyn_mutant ctl-dyn-noop noop 'helper control: dynamic no-op' >/dev/null
  if [[ $fail -ne $((f0 + 1)) ]]; then hc_broken "g1_dyn_mutant accepted a no-op mutation"; fi
  f0=$fail; p0=$pass
  g1_dyn_mutant ctl-dyn-survive kill-own-child-only 'helper control: dynamic survivor' >/dev/null
  if [[ $fail -ne $((f0 + 1)) || $pass -ne $((p0 + 1)) ]]; then hc_broken "g1_dyn_mutant passed a landed tree that kills nothing"; fi
  # reg_mutant
  f0=$fail; r0=$red_rows
  reg_mutant 'helper control: reg no-op' "$PROJECT_MCP" project 'pass' >/dev/null
  if [[ $fail -ne $((f0 + 1)) || $red_rows -ne $r0 ]]; then hc_broken "reg_mutant accepted a no-op mutation"; fi
  f0=$fail; p0=$pass
  reg_mutant 'helper control: reg benign' "$PROJECT_MCP" project 'e["note"] = "benign"' >/dev/null
  if [[ $fail -ne $((f0 + 1)) || $pass -ne $((p0 + 1)) ]]; then hc_broken "reg_mutant passed a landed mutant reg_ok does not reject"; fi
  # slot_mutant: an edit that changes nothing is not a landing
  f0=$fail
  slot_mutant ctl-noop '_pwslot_max=32' '_pwslot_max=32' >/dev/null
  if [[ $fail -ne $((f0 + 1)) || -n "$MROOT" ]]; then hc_broken "slot_mutant accepted an edit that changes nothing"; fi
  f0=$fail
  slot_mutant ctl-absent 'no such text in the script' 'x' >/dev/null 2>&1
  if [[ $fail -ne $((f0 + 1)) || -n "$MROOT" ]]; then hc_broken "slot_mutant accepted an edit whose target is absent"; fi
  pass=$_p; fail=$_f; cases=$_c; red_rows=$_r; mutants_declared=$_m
}

# ===========================================================================
# Guard 1 — no registered hook or launch command names a browser with a PID-selecting tool
# ===========================================================================
mkroot1 "$G1/real"
_helper_control
g1 "$G1/real"
assert_true 'Guard 1: the real tree has no hook or launch string that kills a browser or MCP process by name or pattern' g1_rc_is 0
pop_reported() { [[ "$G1_OUT" == *"POP commands="* && "$G1_OUT" != *VACUOUS* ]]; }
assert_true 'Guard 1: the scan examined a population at or above every floor (not vacuous)' pop_reported
pop_axes_covered() {
  if [[ "$G1_OUT" =~ settings=([0-9]+)\ settings_scripts=([0-9]+)\ hops=([0-9]+) ]] && [[ "${BASH_REMATCH[1]}" -ge 10 && "${BASH_REMATCH[2]}" -ge 10 && "${BASH_REMATCH[3]}" -ge 1 ]]; then return 0; fi
  return 1
}
assert_true 'Guard 1: the population includes the .claude/settings.json hooks and scripts sourced one hop from hook scripts' pop_axes_covered
assert_true 'Guard 1: hooks.json still parses and keeps stop-hook.sh and unkept-promise-hook.sh (positive proof the Stop event was scanned)' python3 - "$REPO_ROOT/plugins/soleur/hooks/hooks.json" <<'PY'
import json, sys
cmds = [h["command"] for g in json.load(open(sys.argv[1]))["hooks"]["Stop"] for h in g["hooks"]]
sys.exit(0 if any(c.endswith("/stop-hook.sh") for c in cmds) and any(c.endswith("/unkept-promise-hook.sh") for c in cmds) and not any("browser-cleanup" in c for c in cmds) else 1)
PY
assert_true 'Guard 1: plugins/soleur/hooks/browser-cleanup-hook.sh is absent' test ! -e "$REPO_ROOT/plugins/soleur/hooks/browser-cleanup-hook.sh"

# Must-PASS non-canonical inputs (static scan only: the shim kills the decoy for ANY pkill, so these are never executed):
# a hook that kills only a pid it spawned, and pkill on a non-browser name.
mkroot1 "$G1/ok-own"; python3 "$HELP/g1_mut.py" "$G1/ok-own" kill-own-child-only "$OLD_HOOK"
g1 "$G1/ok-own"
assert_true 'Guard 1 must-PASS: a hook that backgrounds and kills its own child (kill "$!") passes the static scan (the scan does not distinguish own from foreign pids; the shim rows do not run it)' g1_rc_is 0
mkroot1 "$G1/ok-other"; python3 "$HELP/g1_mut.py" "$G1/ok-other" pkill-non-browser "$OLD_HOOK"
g1 "$G1/ok-other"
assert_true 'Guard 1 must-PASS: pkill on a non-browser name passes' g1_rc_is 0

# Positive proof the scanner can see a killer at all: the synthesized old hook, planted under Stop.
mkroot1 "$G1/planted"; python3 "$HELP/g1_mut.py" "$G1/planted" restore-old-hook "$OLD_HOOK"
g1 "$G1/planted"
assert_true 'Guard 1 positive control: the scanner flags the old hook text registered under Stop (and names pgrep)' bash -c '[[ "$1" == 1 && "$2" == *"FLAG"*"[pgrep]"* ]]' _ "$G1_RC" "$G1_OUT"

# --- live decoy: the old hook text, executed under the shim, DOES kill a pattern-matched Chrome ---
start_decoy 'chrome --remote-debugging-pipe --user-data-dir=/synthetic/decoy-profile'; DECOY=$SPAWNED
printf '%s' "$DECOY" > "$SHIM/decoy.pid"
shim_resolves() { local out; out="$(PATH="$SHIM:$PATH" pgrep anything)"; [[ "$(PATH="$SHIM:$PATH" command -v pgrep)" == "$SHIM/pgrep" && "$out" == "$DECOY" ]]; }
assert_true 'Guard 1 harness: under the scratch PATH pgrep resolves to the shim and prints only the decoy pid' shim_resolves
assert_true 'Guard 1 harness: the decoy is a live process before any hook runs' alive "$DECOY"
cases=$((cases + 1))
if run_under_shim "$OLD_HOOK" "$DECOY" "$DECOY"; then bad 'Guard 1 positive control: the old hook text killed the decoy'; else ok 'Guard 1 positive control: the old hook text killed the decoy (the decoy is a real target)'; fi
# EVERY executable population script of the real tree (plugin hook scripts, the sourced slot script, one hop of sourced libs) is run under
# the shim; the decoy must survive each, and the loop must have run (not zero iterations)
start_decoy 'chrome --remote-debugging-pipe --user-data-dir=/synthetic/decoy-profile-2'; DECOY=$SPAWNED
g1_dynamic "$G1/real" "$DECOY"
assert_true 'Guard 1 live: every executable population script of the real tree ran under the shim (at least the floor), not zero iterations' test "$DYN_RAN" -ge "$G1_FLOOR_RUN"
assert_true 'Guard 1 live: the decoy survived every population script of the real tree (the positive control above proves the decoy is killable)' test "$DYN_ALIVE" -eq 1

# --- Guard 1 mutation matrix: each mutated copy must be flagged (or hit a vacuity floor, or kill the decoy under the shim) ---
g1_mutant 1-restore-old-hook restore-old-hook 1 'Guard 1 mutant 1: the old hook and its Stop registration restored → RED' 'browser-cleanup-hook.sh'
g1_mutant 2-other-event killer-under-sessionstart 1 'Guard 1 mutant 2: a pattern-killing script registered under SessionStart → RED' 'zz-killer.sh'
g1_mutant 3-second-killer second-killer-same-event 1 'Guard 1 mutant 3: a second killing hook after the compliant ones in the same Stop array → RED' 'zz-killer.sh'
g1_mutant 4-mcp-pkill mcp-pkill 1 'Guard 1 mutant 4: pkill -9 -f "[c]hrome.*$prof" back in the .mcp.json launch string → RED' ' .mcp.json:playwright'
g1_mutant 5-empty-population empty-commands 3 'Guard 1 mutant 5: hooks.json command population emptied → RED (vacuity floor)'
g1_mutant 6-second-in-group second-in-group 1 'Guard 1 mutant 6: a killer as the SECOND hook inside one hooks.json group → RED' 'zz-killer.sh'
g1_mutant 7-plugin-mcp plugin-mcp-pkill 1 'Guard 1 mutant 7: a pkill in plugins/soleur/.mcp.json → RED' 'plugins/soleur/.mcp.json:reaper'
g1_mutant 8-sourced-killer sourced-killer 1 'Guard 1 mutant 8: a pattern kill appended to the sourced slot script → RED' 'playwright-mcp-profile-slot.sh'
g1_mutant 9-settings-killer settings-killer 1 'Guard 1 mutant 9: a killer script registered in .claude/settings.json → RED' '.claude/hooks/zz-killer.sh'
g1_mutant 10-hop-killer hop-killer 1 'Guard 1 mutant 10: a killer in a lib sourced one hop from a registered hook → RED' 'hooks/lib/zz-helper.sh'
for _w in headless_shell playwright remote-debugging user-data-dir mcp; do
  g1_mutant "11-vocab-$_w" "vocab-$_w" 1 "Guard 1 mutant 11: pkill -f $_w (browser vocabulary without the word chrome) → RED" 'zz-killer.sh'
done
g1_mutant 12-killall killall-chrome 1 'Guard 1 mutant 12: killall -9 chrome → RED' 'zz-killer.sh'
g1_mutant 13-pidof pidof-chrome 1 'Guard 1 mutant 13: kill $(pidof chrome) → RED' 'zz-killer.sh'
g1_mutant 14-ps-grep-kill ps-grep-kill 1 'Guard 1 mutant 14: ps | grep chrome | xargs kill (the grep branch) → RED' 'zz-killer.sh'
g1_mutant 15-continuation continuation 1 'Guard 1 mutant 15: a backslash-continued pkill -f \<newline> "chrome..." → RED' 'zz-killer.sh'
g1_mutant 16-drop-plugin-mcp drop-plugin-mcp 3 'Guard 1 mutant 16: plugins/soleur/.mcp.json emptied → RED (mcp floor)'
g1_mutant 17-drop-sourced drop-sourced 3 'Guard 1 mutant 17: the launch string no longer sources the slot script → RED (sourced floor)'
# the shim run catches what the static text scan cannot see: indirection, split words, and (as a known positive) the old hook
g1_dyn_mutant 18-dyn-old-hook restore-old-hook 'Guard 1 mutant 18 (dynamic): the old hook, registered under Stop, kills the decoy when the population is executed under the shim → RED'
g1_dyn_mutant 19-dyn-indirection indirection 'Guard 1 mutant 19 (dynamic): pkill -f "$PAT" with the pattern in a variable (invisible to the static scan) kills the decoy → RED'
g1_dyn_mutant 20-dyn-split-word split-word 'Guard 1 mutant 20 (dynamic): pkill -f "chr""ome" (split word, invisible to the static scan) kills the decoy → RED'
# Mutation (harness): the shim prints nothing, so the old hook kills nothing — the positive control must then FAIL
start_decoy 'chrome --remote-debugging-pipe --user-data-dir=/synthetic/decoy-profile-3'; DECOY=$SPAWNED
red 'Guard 1 mutant (harness): a pgrep shim that prints nothing → the old hook kills nothing, so the positive control would fail (the decoy is what makes it bite)' run_under_shim "$OLD_HOOK" "" "$DECOY"

# ===========================================================================
# Guard 2 — a launch claims a slot no live launch holds, and kills nothing
# ===========================================================================
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
assert_true 'Guard 2: the launch string sources the slot script, then execs env and the proxy with --user-data-dir="$prof" (quoted, once), --config and exactly one pin, and carries no unreachable [ -n "$prof" ] clause' python3 - "$MCP_ARGS" "$SLOT_REL" "$PROXY_REL_PATH" <<'PY'
import re, sys
s, slot, proxy = sys.argv[1:]
ok = (
    s.startswith(". " + slot + " || exit 1; exec env ")
    and proxy in s
    and s.count('--user-data-dir="$prof"') == 1
    and "--user-data-dir=$prof" not in s
    and s.count("--config=.claude/playwright-mcp.config.json") == 1
    and len(re.findall(r"@playwright/mcp@[0-9.]+", s)) == 1
    and '[ -n "$prof"' not in s
)
sys.exit(0 if ok else 1)
PY
assert_true 'Guard 2: the slot script exists, uses return (never exit), sets no errexit/nounset, never removes recursively, assigns prof, and holds fd 9' python3 - "$REPO_ROOT/$SLOT_REL" <<'PY'
import re, sys
try:
    src = open(sys.argv[1]).read()
except OSError:
    sys.exit(1)
code = "\n".join(l for l in src.splitlines() if not l.lstrip().startswith("#"))
sys.exit(0 if (
    re.search(r"^\s*exit\b", code, re.M) is None
    and re.search(r"\bset\s+-[a-zA-Z]*[eu]", code) is None
    and re.search(r"\brm\s+(-[a-zA-Z]*[rR]|--recursive)", code) is None
    and re.search(r"\breturn\b", code)
    and re.search(r"\bprof=", code)
    and re.search(r"9>", code)
) else 1)
PY
# default_wait_is <slot-script> <n>: the ${PW_PROFILE_SLOT0_WAIT_S:-N} default, read from CODE (comment lines and trailing comments stripped)
default_wait_is() {
  python3 - "$1" "$2" <<'PY'
import re, sys
code = "\n".join(re.sub(r"\s#.*$", "", l) for l in open(sys.argv[1]).read().splitlines() if not l.lstrip().startswith("#"))
sys.exit(0 if re.findall(r"PW_PROFILE_SLOT0_WAIT_S:-([0-9.]+)\}", code) == [sys.argv[2]] else 1)
PY
}
# wait_pairs_grace <slot-script> <proxy>: the slot-0 wait covers the proxy teardown (GRACE_S + STDIN_CLOSE_WAIT_S) with at least a second to spare
wait_pairs_grace() {
  python3 - "$1" "$2" <<'PY'
import re, sys
slot = "\n".join(re.sub(r"\s#.*$", "", l) for l in open(sys.argv[1]).read().splitlines() if not l.lstrip().startswith("#"))
proxy = open(sys.argv[2]).read()
w = float(re.findall(r"PW_PROFILE_SLOT0_WAIT_S:-([0-9.]+)\}", slot)[0])
g = float(re.search(r"^GRACE_S = ([0-9.]+)", proxy, re.M).group(1))
s = float(re.search(r"^STDIN_CLOSE_WAIT_S = ([0-9.]+)", proxy, re.M).group(1))
sys.exit(0 if w >= g + s + 1 else 1)
PY
}
assert_true 'Guard 2: the slot-0 reconnect wait defaults to 7 seconds (read from code, comments stripped)' default_wait_is "$REPO_ROOT/$SLOT_REL" 7
assert_true 'Guard 2: the slot-0 default wait covers the proxy teardown: >= GRACE_S + STDIN_CLOSE_WAIT_S + 1, both read from the proxy' wait_pairs_grace "$REPO_ROOT/$SLOT_REL" "$REPO_ROOT/$PROXY_REL_PATH"

# launch <tag> <root> <home> <cmd> [VAR=val...] — the launch string under bash -c, stdin held open by a sleeper
# (LAUNCH_PATH, when set, replaces the PATH the launch runs under)
launch() {
  local tag="$1" root="$2" home="$3" cmd="$4"; shift 4
  local fifo="$G2/$tag.fifo"
  : > "$G2/$tag.jsonl"; rm -f "$G2/$tag.jsonl.pid" "$fifo"
  mkdir -p "$home"; mkfifo "$fifo"
  sleep 600 > "$fifo" &
  printf '%s' "$!" > "$G2/$tag.sleeper"; own "$!"; disown "$!"
  ( cd "$root" && exec env "$@" SHIM_OUT="$G2/$tag.jsonl" HOME="$home" PATH="${LAUNCH_PATH:-$G2/bin:$PATH}" bash -c "$cmd" ) < "$fifo" > /dev/null 2> "$G2/$tag.err" &
  printf '%s' "$!" > "$G2/$tag.pid"; own "$!"; disown "$!"
}
# wait_ready <tag> — 0 when the shim ran (its argv is recorded), 1 when the launch died first. A launch that is STILL RUNNING
# after 30 s without reaching the shim is UNRESOLVED (a loaded host, not a verdict on any guard): the suite stops with that
# message instead of letting the row read as "mutant survived".
wait_ready() {
  local tag="$1" i=0
  while [[ ! -s "$G2/$tag.jsonl" && $i -lt 300 ]]; do
    if ! alive "$(cat "$G2/$tag.pid")"; then break; fi
    sleep 0.1; i=$((i + 1))
  done
  if [[ -s "$G2/$tag.jsonl" ]]; then return 0; fi
  if alive "$(cat "$G2/$tag.pid")"; then
    printf 'UNRESOLVED: launch %s was still running after 30 s without reaching the server shim; the host is too loaded to judge this row, rerun when it is idle\n' "$tag" >&2
    exit 2
  fi
  return 1
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
# sets RN_PROFS (one per line), RN_RAN (shims that ran), RN_OVERLAP (every launch alive AND every distinct profile's lock held at one instant),
# RN_MS (milliseconds from starting the first launch until its server shim ran)
RN_PROFS=""; RN_RAN=0; RN_OVERLAP=0; RN_MS=0
run_n() {
  local pfx="$1" root="$2" home="$3" cmd="$4" n="$5" mode="$6" i tag p t0; shift 6
  RN_PROFS=""; RN_RAN=0; RN_OVERLAP=1; RN_MS=0
  for ((i = 1; i <= n; i++)); do
    tag="$pfx-$i"
    t0="$(now_ms)"
    launch "$tag" "$root" "$home" "$cmd" "$@"
    if wait_ready "$tag"; then RN_RAN=$((RN_RAN + 1)); RN_PROFS+="$(prof_of "$tag")"$'\n'; else RN_OVERLAP=0; fi
    if [[ $i -eq 1 ]]; then RN_MS=$(( $(now_ms) - t0 )); fi
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
# one launch ran and landed on <profile>
prof_is() { [[ "$RN_RAN" -eq 1 && "$(head -n1 <<< "$RN_PROFS")" == "$1" ]]; }
# <profile-dir>/SingletonLock is a symlink naming <target>
link_is() { [[ -L "$1/SingletonLock" && "$(readlink "$1/SingletonLock")" == "$2" ]]; }
no_link() { [[ ! -e "$1/SingletonLock" && ! -L "$1/SingletonLock" ]]; }
mode_is() { [[ "$(stat -c %a "$1" 2>/dev/null)" == "$2" ]]; }

# --- real tree: overlapped launches ---
H="$G2/h-two"
run_n real2 "$REPO_ROOT" "$H" "$MCP_ARGS" 2 overlap "$FAST"
assert_true 'Guard 2: two overlapped launches under one HOME both ran the server and resolve DISTINCT --user-data-dir values' rn_distinct 2
assert_true 'Guard 2: the first launch took the persistent slot 0 profile' bash -c '[[ "$(head -n1 <<< "$1")" == "$2" ]]' _ "$RN_PROFS" "$(prof0 "$H")"
assert_true 'Guard 2: overlap proven — both launches were alive and both slot locks were held at the same instant' rn_overlap
assert_true 'Guard 2: the slot-0 lease wrote its owner file (the launcher PPID) with mode 600 and the slot directory is mode 700' bash -c '[[ "$(stat -c %a "$1/.pwslot.owner")" == 600 && "$(stat -c %a "$1")" == 700 && "$(cat "$1/.pwslot.owner")" == "$2" ]]' _ "$(prof0 "$H")" "$$"
H="$G2/h-three"
run_n real3 "$REPO_ROOT" "$H" "$MCP_ARGS" 3 overlap "$FAST"
assert_true 'Guard 2: a third concurrent launch also gets its own directory (three distinct)' rn_distinct 3
assert_true 'Guard 2: overlap proven for three launches' rn_overlap
assert_true 'Guard 2: after every launch exited, slot 0 is free again (the kernel released the lock)' lock_free "$(prof0 "$H")/$LOCKNAME"

# --- the lease belongs to the proxy process: fd 9 is held by it and is NOT inherited by the server child ---
H="$G2/h-fd"
launch fd1 "$REPO_ROOT" "$H" "$MCP_ARGS" "$FAST"
fd_ready=0; if wait_ready fd1; then fd_ready=1; fi
fd_proxy="$(cat "$G2/fd1.pid")"; fd_child="$(head -n1 "$G2/fd1.jsonl.pid" 2>/dev/null || true)"
lease_in_proxy_only() { [[ "$fd_ready" -eq 1 && -n "$fd_child" && "$(readlink "/proc/$fd_proxy/fd/9" 2>/dev/null)" == *"/$LOCKNAME" && ! -e "/proc/$fd_child/fd/9" ]]; }
assert_true 'Guard 2: the lease (fd 9 on the slot lock) is held by the proxy process and is not inherited by the server child, so it dies with the proxy' lease_in_proxy_only
end_launch fd1

# --- SIGKILL of the proxy under lease: the kernel releases the lock (the server child does not hold it) ---
H="$G2/h-kill"
launch kill1 "$REPO_ROOT" "$H" "$MCP_ARGS" "$FAST"
kill_ready=0; if wait_ready kill1; then kill_ready=1; fi
kill_held=0; if lock_held "$(prof0 "$H")/$LOCKNAME"; then kill_held=1; fi
kill_proxy="$(cat "$G2/kill1.pid")"
kill -KILL "$kill_proxy" 2>/dev/null || true
wait_dead "$kill_proxy" 3 || true
sigkill_released() { if [[ "$kill_ready" -eq 1 && "$kill_held" -eq 1 ]] && ! alive "$kill_proxy" && lock_free "$(prof0 "$H")/$LOCKNAME"; then return 0; fi; return 1; }
assert_true 'Guard 2: the lock was held while the proxy ran, and a SIGKILL of the proxy released it (the lease dies with the proxy)' sigkill_released
end_launch kill1

# --- a launch kills nothing: four decoy shapes, each a different selector, all survive the launch and its teardown ---
# D_SLOT0: chrome on the claimed slot's profile (the old reaper's own pattern)  D_OTHER: chrome on ANOTHER slot's profile
# D_SRV: a sibling playwright-mcp server (node .../bin/playwright-mcp --user-data-dir=<other slot>)  D_FD: a Chrome holding a file open inside the claimed slot
D_SLOT0=0; D_OTHER=0; D_SRV=0; D_FD=0
spawn_decoys() {  # <home>
  mkdir -p "$(prof0 "$1")"
  start_decoy "chrome --user-data-dir=$(prof0 "$1")"; D_SLOT0=$SPAWNED
  start_decoy "chrome --user-data-dir=$(prof0 "$1")-1"; D_OTHER=$SPAWNED
  start_decoy "node /synthetic/node_modules/@playwright/mcp/bin/playwright-mcp --user-data-dir=$(prof0 "$1")-2"; D_SRV=$SPAWNED
  start_holder "chrome --type=renderer" "$(prof0 "$1")/Cookies"; D_FD=$SPAWNED
}
H="$G2/h-decoy"
spawn_decoys "$H"
assert_true 'Guard 2 harness: the slot-0 decoy argv matches the pattern the old reaper used (chrome.*<slot0>), read from /proc, nothing signalled' python3 - "$D_SLOT0" "$(prof0 "$H")" <<'PY'
import re, sys
cmd = open(f"/proc/{sys.argv[1]}/cmdline", "rb").read().replace(b"\0", b" ").decode()
sys.exit(0 if re.search(r"chrome.*" + re.escape(sys.argv[2]), cmd) else 1)
PY
fd_holder_holds() { [[ "$(readlink "/proc/$D_FD/fd/7" 2>/dev/null)" == "$(prof0 "$H")/Cookies" ]]; }
assert_true 'Guard 2 harness: the file-holder decoy really holds a file open inside the claimed slot (fd 7 -> <slot0>/Cookies)' fd_holder_holds
run_n decoy "$REPO_ROOT" "$H" "$MCP_ARGS" 1 overlap "$FAST"
assert_true 'Guard 2: the launch ran (the shim recorded its argv)' test "$RN_RAN" -eq 1
assert_true 'Guard 2: the decoy Chrome on the claimed profile is still alive after the launch and its teardown' alive "$D_SLOT0"
assert_true 'Guard 2: a decoy Chrome on ANOTHER slot'"'"'s profile is still alive after the launch and its teardown' alive "$D_OTHER"
assert_true 'Guard 2: a decoy sibling playwright-mcp server (node .../bin/playwright-mcp --user-data-dir=<other slot>) is still alive after the launch and its teardown' alive "$D_SRV"
assert_true 'Guard 2: a decoy holding a file open inside the claimed slot is still alive after the launch and its teardown' alive "$D_FD"

# --- stale SingletonLock (dead owner) is cleared and slot 0 reused ---
H="$G2/h-stale"; mkdir -p "$(prof0 "$H")"
sleep 0 & dead=$!; wait "$dead" || true
if alive "$dead"; then dead=2147483646; fi
ln -s "$HOST_NOW-$dead" "$(prof0 "$H")/SingletonLock"; : > "$(prof0 "$H")/SingletonCookie"; : > "$(prof0 "$H")/SingletonSocket"
run_n stale "$REPO_ROOT" "$H" "$MCP_ARGS" 1 overlap "$FAST"
stale_state() { prof_is "$(prof0 "$H")" && no_link "$(prof0 "$H")" && [[ ! -e "$(prof0 "$H")/SingletonCookie" && ! -e "$(prof0 "$H")/SingletonSocket" ]]; }
assert_true 'Guard 2 must-PASS: a stale SingletonLock naming a dead pid on this host is cleared (lock, cookie, socket) and slot 0 is reused' stale_state

# --- a live CHROME owner with a FREE flock (proxy gone, Chrome alive): the slot is skipped, the lock left alone ---
H="$G2/h-owner"; mkdir -p "$(prof0 "$H")"
start_chrome_owner; OWNER=$SPAWNED
ln -s "$HOST_NOW-$OWNER" "$(prof0 "$H")/SingletonLock"
run_n owner "$REPO_ROOT" "$H" "$MCP_ARGS" 1 overlap "$FAST"
owner_skipped() { prof_is "$(prof0 "$H")-1"; }
owner_lock_kept() { link_is "$(prof0 "$H")" "$HOST_NOW-$OWNER" && alive "$OWNER"; }
assert_true 'Guard 2 must-PASS: a free lock but a live-Chrome-owner SingletonLock skips the slot (the launch lands on slot 1)' owner_skipped
assert_true 'Guard 2 must-PASS: the live owner'"'"'s SingletonLock was left in place and its owner was not touched' owner_lock_kept
assert_true 'Guard 2: skipping slot 0 prints exactly ONE stderr line, naming the live Chrome and that the persistent profile'"'"'s logins are not available in this session' bash -c '[[ "$(grep -c "^playwright-mcp-profile-slot:" "$1")" == 1 && "$(grep "^playwright-mcp-profile-slot:" "$1")" == *"live Chrome"*"logins are not available in this session"* ]]' _ "$G2/owner-1.err"

# --- a recycled pid: the lock names a live pid that is NOT a Chrome -> stale, cleared, slot 0 reused ---
H="$G2/h-recycled"; mkdir -p "$(prof0 "$H")"
start_sleeper; RECYCLED=$SPAWNED
ln -s "$HOST_NOW-$RECYCLED" "$(prof0 "$H")/SingletonLock"
run_n recycled "$REPO_ROOT" "$H" "$MCP_ARGS" 1 overlap "$FAST"
recycled_state() { prof_is "$(prof0 "$H")" && no_link "$(prof0 "$H")" && alive "$RECYCLED"; }
assert_true 'Guard 2 must-PASS: a SingletonLock naming a live pid whose comm is not Chrome (a recycled pid) is stale: cleared, slot 0 reused, the unrelated process untouched' recycled_state

# --- a lock naming ANOTHER HOST is never removed, whatever the local pid says ---
H="$G2/h-foreign"; mkdir -p "$(prof0 "$H")"
ln -s "otherhost-$dead" "$(prof0 "$H")/SingletonLock"
run_n foreign "$REPO_ROOT" "$H" "$MCP_ARGS" 1 overlap "$FAST"
foreign_state() { prof_is "$(prof0 "$H")-1" && link_is "$(prof0 "$H")" "otherhost-$dead"; }
assert_true 'Guard 2 must-PASS: a SingletonLock naming another host (even with a pid that is dead here) is kept and the slot skipped' foreign_state

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
assert_true 'Guard 2 must-PASS: a reconnect — the old holder (same launcher) leaves within the wait — reacquires slot 0, not slot 1' test "$rc_got:$rc_prof" = "1:$(prof0 "$H")"

# --- owner-aware wait: the same session's predecessor is waited for, a DIFFERENT session's lock is not, an unknown owner is ---
OTHER_SESSION=2147483646
H="$G2/h-same"; hold_lock "$(prof0 "$H")" 2 "$$"
run_n same "$REPO_ROOT" "$H" "$MCP_ARGS" 1 overlap PW_PROFILE_SLOT0_WAIT_S=4
same_waits() { prof_is "$(prof0 "$H")" && [[ "$RN_MS" -ge 1200 ]]; }
assert_true 'Guard 2: slot 0 held by this session'"'"'s own launcher (owner file == $PPID) is waited for and reacquired when the holder leaves' same_waits
H="$G2/h-other"; hold_lock "$(prof0 "$H")" 9 "$OTHER_SESSION"
run_n other "$REPO_ROOT" "$H" "$MCP_ARGS" 1 overlap PW_PROFILE_SLOT0_WAIT_S=4
other_no_wait() { prof_is "$(prof0 "$H")-1" && [[ "$RN_MS" -lt 2500 ]]; }
assert_true 'Guard 2: slot 0 held by a DIFFERENT session is skipped at once, without the wait (slot 1 in under 2.5 s with a 4 s budget)' other_no_wait
assert_true 'Guard 2: that skip printed exactly ONE stderr line saying slot 0 was skipped and its logins are not available' bash -c '[[ "$(grep -c "^playwright-mcp-profile-slot:" "$1")" == 1 && "$(grep "^playwright-mcp-profile-slot:" "$1")" == *"slot 0"*"was skipped"*"logins are not available in this session"* ]]' _ "$G2/other-1.err"
H="$G2/h-unknown"; hold_lock "$(prof0 "$H")" 2
run_n unknown "$REPO_ROOT" "$H" "$MCP_ARGS" 1 overlap PW_PROFILE_SLOT0_WAIT_S=4
unknown_waits() { prof_is "$(prof0 "$H")" && [[ "$RN_MS" -ge 1200 ]]; }
assert_true 'Guard 2: slot 0 held with NO owner file (unknown owner) is waited for (fails toward the persistent profile)' unknown_waits
# a live-Chrome SingletonLock whose Chrome exits within the wait: same session -> slot 0 is reacquired after the recheck
H="$G2/h-chromeexit"; mkdir -p "$(prof0 "$H")"; printf '%s\n' "$$" > "$(prof0 "$H")/.pwslot.owner"
start_chrome_owner; CEXIT=$SPAWNED
ln -s "$HOST_NOW-$CEXIT" "$(prof0 "$H")/SingletonLock"
( sleep 1.2; kill -KILL "$CEXIT" 2>/dev/null || true ) >/dev/null 2>&1 & disown "$!"
run_n chromeexit "$REPO_ROOT" "$H" "$MCP_ARGS" 1 overlap PW_PROFILE_SLOT0_WAIT_S=4
chromeexit_rechecks() { prof_is "$(prof0 "$H")" && no_link "$(prof0 "$H")" && [[ "$RN_MS" -ge 900 ]]; }
assert_true 'Guard 2: a live-Chrome SingletonLock on slot 0 gets the same wait-then-recheck: the Chrome exits within the wait and slot 0 is reacquired' chromeexit_rechecks

# --- a non-numeric PW_PROFILE_SLOT0_WAIT_S is noted and replaced by the default; it never degrades the lease ---
H="$G2/h-badwait"; hold_lock "$(prof0 "$H")" 2 "$$"
run_n badwait "$REPO_ROOT" "$H" "$MCP_ARGS" 1 overlap PW_PROFILE_SLOT0_WAIT_S=abc
badwait_state() { prof_is "$(prof0 "$H")" && grep -q "ignored PW_PROFILE_SLOT0_WAIT_S='abc'" "$G2/badwait-1.err"; }
assert_true 'Guard 2: PW_PROFILE_SLOT0_WAIT_S=abc is noted on stderr and the 7 s default applies (the launch still reacquires slot 0)' badwait_state

# --- an unusable middle slot does not end the search: slot 1 is a regular file, the launch continues to slot 2 ---
H="$G2/h-mid"; hold_lock "$(prof0 "$H")" 30 "$OTHER_SESSION"; : > "$(prof0 "$H")-1"
run_n mid "$REPO_ROOT" "$H" "$MCP_ARGS" 1 overlap "$FAST"
assert_true 'Guard 2: slot 0 busy and slot 1 unusable (a regular file) -> the launch continues to slot 2 instead of the unique fallback' prof_is "$(prof0 "$H")-2"

# --- restricted PATHs: no flock, and no ps ---
mkbin() {  # <dir> [extra tool...]: the tools the launch string needs, plus the npx shim, and nothing else
  local d="$1" t tp; shift
  assert_fixture_dir "$d"
  mkdir -p "$d"
  for t in bash env python3 mkdir rm readlink sleep cat dirname basename head sed grep tr ls uname "$@"; do
    tp="$(command -v "$t" 2>/dev/null || true)"
    if [[ -n "$tp" ]]; then ln -sf "$tp" "$d/$t"; fi
  done
  cp "$G2/bin/npx" "$d/npx"
}
NOFLOCK="$G2/noflock-bin"; mkbin "$NOFLOCK" ps
NOPS="$G2/nops-bin"; mkbin "$NOPS" flock
no_flock_on_path() { ! PATH="$NOFLOCK" command -v flock >/dev/null 2>&1; }
assert_true 'Guard 2 harness: flock really was absent from the restricted PATH' no_flock_on_path
no_ps_on_path() { ! PATH="$NOPS" command -v ps >/dev/null 2>&1 && PATH="$NOPS" command -v flock >/dev/null 2>&1; }
assert_true 'Guard 2 harness: ps really was absent (and flock present) on the second restricted PATH' no_ps_on_path

# no flock: the FIRST session still gets the persistent profile (slot 0 claimed without a lease) and says so
H="$G2/h-noflock"
LAUNCH_PATH="$NOFLOCK" run_n nf1 "$REPO_ROOT" "$H" "$MCP_ARGS" 1 overlap
assert_true 'Guard 2 must-PASS: with no flock on PATH the first launch starts on the persistent slot 0 profile (claimed without a lease)' prof_is "$(prof0 "$H")"
assert_true 'Guard 2: that no-flock launch noted on stderr that it runs without a lease' grep -q 'without a lease' "$G2/nf1-1.err"
# no flock and slot 0 owned by a live Chrome: the unique fallback $base-p<pid>, created mode 700
start_chrome_owner; NFOWNER=$SPAWNED
ln -s "$HOST_NOW-$NFOWNER" "$(prof0 "$H")/SingletonLock"
LAUNCH_PATH="$NOFLOCK" run_n nf2 "$REPO_ROOT" "$H" "$MCP_ARGS" 1 overlap
nf2_state() { local pid; pid="$(cat "$G2/nf2-1.pid")"; prof_is "$(prof0 "$H")-p$pid" && mode_is "$(prof0 "$H")-p$pid" 700 && link_is "$(prof0 "$H")" "$HOST_NOW-$NFOWNER"; }
assert_true 'Guard 2 must-PASS: with no flock and a live-Chrome-owned slot 0 the launch uses a unique $base-p<pid> directory (mode 700) and leaves the lock alone' nf2_state

# no ps: a live Chrome-owned lock is KEPT (the probe never needs ps), and a dead owner's lock is still cleared
H="$G2/h-nops"; mkdir -p "$(prof0 "$H")"
start_chrome_owner; NPOWNER=$SPAWNED
ln -s "$HOST_NOW-$NPOWNER" "$(prof0 "$H")/SingletonLock"
LAUNCH_PATH="$NOPS" run_n nops "$REPO_ROOT" "$H" "$MCP_ARGS" 1 overlap "$FAST"
nops_kept() { prof_is "$(prof0 "$H")-1" && link_is "$(prof0 "$H")" "$HOST_NOW-$NPOWNER" && alive "$NPOWNER"; }
assert_true 'Guard 2 must-PASS: with ps absent a live Chrome-owned SingletonLock is kept and the slot skipped (an unprobeable owner is never treated as stale)' nops_kept
H="$G2/h-nops-dead"; mkdir -p "$(prof0 "$H")"
ln -s "$HOST_NOW-$dead" "$(prof0 "$H")/SingletonLock"
LAUNCH_PATH="$NOPS" run_n nopsd "$REPO_ROOT" "$H" "$MCP_ARGS" 1 overlap "$FAST"
nopsd_cleared() { prof_is "$(prof0 "$H")" && no_link "$(prof0 "$H")"; }
assert_true 'Guard 2 must-PASS: with ps absent a dead owner'"'"'s lock is still cleared (/proc and kill -0 answer without ps)' nopsd_cleared

# --- launches released at the SAME instant (a barrier): the flock capability probe must not make them contend ---
# The rows above start their launches one after another, which is why a probe that locked one shared inode (/dev/null) and
# read a lost race as "no usable flock" stayed green: concurrent launches then took the no-lease branch and shared slot 0.
# bar_launch <tag> <home> <go-microsecond-epoch> <script> [VAR=val...]: sources <script>, records $prof, holds fd 9 (exec sleep) like the proxy
BAR_PIDS="$WORK/bar-pids"; : > "$BAR_PIDS"
bar_launch() {
  local tag="$1" home="$2" go="$3" script="$4"; shift 4
  rm -f "$G2/$tag.prof" "$G2/$tag.err"
  mkdir -p "$home"
  ( cd "$REPO_ROOT" && exec env "$@" HOME="$home" PW_PROFILE_SLOT0_WAIT_S=0.3 bash -c 'r=$(( ($1 - ${EPOCHREALTIME/./}) / 1000 - 150 )); if [ "$r" -gt 0 ]; then printf -v s "%d.%03d" $((r / 1000)) $((r % 1000)); sleep "$s"; fi; while [ "${EPOCHREALTIME/./}" -lt "$1" ]; do :; done; . "$2" || exit 1; printf "%s\n" "$prof" > "$3"; exec sleep 12' _ "$go" "$script" "$G2/$tag.prof" ) > /dev/null 2> "$G2/$tag.err" &
  printf '%s\n' "$!" >> "$BAR_PIDS"; own "$!"; disown "$!"
}
# barrier_run <pfx> <home> <n> <script> [VAR=val...]: n launches released together; sets BAR_RAN (profiles recorded), BAR_DISTINCT, BAR_NOTES ("no usable flock" notes)
# A launch that never records a profile is UNRESOLVED (a loaded host), never a verdict: the suite stops with that message.
BAR_RAN=0; BAR_DISTINCT=0; BAR_NOTES=0
barrier_run() {
  local pfx="$1" home="$2" n="$3" script="$4" i t=0 go; shift 4
  : > "$BAR_PIDS"; BAR_RAN=0; BAR_DISTINCT=0; BAR_NOTES=0
  go=$(( ${EPOCHREALTIME/./} + 2500000 ))
  for ((i = 1; i <= n; i++)); do bar_launch "$pfx-$i" "$home" "$go" "$script" "$@"; done
  while [[ $t -lt 600 ]]; do
    BAR_RAN=0; for ((i = 1; i <= n; i++)); do if [[ -s "$G2/$pfx-$i.prof" ]]; then BAR_RAN=$((BAR_RAN + 1)); fi; done
    if [[ $BAR_RAN -eq $n ]]; then break; fi
    sleep 0.1; t=$((t + 1))
  done
  if [[ $BAR_RAN -ne $n ]]; then printf 'UNRESOLVED: only %d of %d barrier launches (%s) recorded a profile within 60 s; the host is too loaded to judge this row, rerun when it is idle\n' "$BAR_RAN" "$n" "$pfx" >&2; exit 2; fi
  BAR_DISTINCT="$(cat "$G2/$pfx"-*.prof | sort -u | grep -c . || true)"
  BAR_NOTES="$(cat "$G2/$pfx"-*.err | grep -c 'no usable flock' || true)"
  reap_list "$BAR_PIDS"
}
BAR_N=12
barrier_run bar "$G2/h-bar" "$BAR_N" "$REPO_ROOT/$SLOT_REL"
assert_true "Guard 2: $BAR_N launches released at the same instant under one HOME resolve $BAR_N DISTINCT profiles (no two share a slot)" test "$BAR_RAN:$BAR_DISTINCT" = "$BAR_N:$BAR_N"
assert_true 'Guard 2: those simultaneous launches printed ZERO "no usable flock" notes (flock is present, so a lost probe race must not take the no-lease branch)' test "$BAR_NOTES" -eq 0
# the probe's own contention, made deterministic: a flock whose capability probe (-E 75 -w 0 8) answers 75, as util-linux does when another launch holds /dev/null
PROBEBUSY="$G2/probe-busy-bin"; mkdir -p "$PROBEBUSY"
printf '#!/usr/bin/env bash\nif [[ "$*" == "-E 75 -w 0 8" ]]; then exit 75; fi\nexec %q "$@"\n' "$(command -v flock)" > "$PROBEBUSY/flock"; chmod +x "$PROBEBUSY/flock"
probe_busy_state() { [[ "$(PATH="$PROBEBUSY:$PATH" flock -E 75 -w 0 8 8< /dev/null; echo $?)" == 75 && "$(PATH="$PROBEBUSY:$PATH" flock -n -E 75 "$G2/hc-unlocked-probe" true; echo $?)" == 0 ]]; }
: > "$G2/hc-unlocked-probe"
assert_true 'Guard 2 harness: the probe-busy flock answers 75 to the capability probe only and runs every other flock call for real' probe_busy_state
barrier_run pb "$G2/h-pb" 2 "$REPO_ROOT/$SLOT_REL" "PATH=$PROBEBUSY:$PATH"
assert_true 'Guard 2: a capability probe that answers 75 (a concurrent probe held the lock) still means flock works: two launches get two leased profiles and no "no usable flock" note' test "$BAR_RAN:$BAR_DISTINCT:$BAR_NOTES" = "2:2:0"

# --- all 32 slots busy: the launch falls back to a unique directory, never blocking, never killing ---
H="$G2/h-full"; mkdir -p "$H/.cache"
cat > "$HELP/holdn.py" <<'PY'
import fcntl, os, sys, time
base, lockname, ready, n = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
fds = []
for i in range(n):
    d = base if i == 0 else f"{base}-{i}"
    os.makedirs(d, exist_ok=True)
    fd = os.open(os.path.join(d, lockname), os.O_RDWR | os.O_CREAT, 0o644)
    fcntl.flock(fd, fcntl.LOCK_EX)
    fds.append(fd)
open(ready, "w").write("ready")
time.sleep(300)
PY
# hold_slots <home> <n> <ready-file>: a lock holder (own child) on slots 0..n-1 of <home>
hold_slots() {
  mkdir -p "$1/.cache"
  python3 "$HELP/holdn.py" "$(prof0 "$1")" "$LOCKNAME" "$3" "$2" >/dev/null 2>&1 &
  own "$!"; disown "$!"
  local _i; for _i in $(seq 1 50); do if [[ -e "$3" ]]; then break; fi; sleep 0.1; done
}
hold_slots "$H" 32 "$G2/hold32.ready"
run_n full "$REPO_ROOT" "$H" "$MCP_ARGS" 1 overlap "$FAST"
full_state() { local p b; p="$(head -n1 <<< "$RN_PROFS")"; b="$(prof0 "$H")"; if [[ "$RN_RAN" -eq 1 && "$p" =~ ^"$b"-p[0-9]+$ ]] && mode_is "$p" 700 && grep -q 'all 32 slots are busy' "$G2/full-1.err"; then return 0; fi; return 1; }
assert_true 'Guard 2 must-PASS: with all 32 slots busy the launch starts on a unique $base-p<pid> directory (non-numeric infix, mode 700, note naming the cause)' full_state
# slots >= 1 never wait: 8 busy slots with a 0.3 s slot-0 budget -> slot 8 in well under the 31 x 0.3 s a waiting loop would take
H="$G2/h-timing"
hold_slots "$H" 8 "$G2/hold8.ready"
run_n timing "$REPO_ROOT" "$H" "$MCP_ARGS" 1 overlap "$FAST"
timing_ok() { prof_is "$(prof0 "$H")-8" && [[ "$RN_MS" -lt 1500 ]]; }
assert_true 'Guard 2: slots 1+ never wait — eight busy slots resolve to slot 8 in under 1.5 s (a loop that waited on each slot would take over 2.7 s)' timing_ok

# --- sourced-script hygiene: nothing leaks into the exec'd shell, no errexit/nounset, fd 9 stays open ---
H="$G2/h-hygiene"; mkdir -p "$H" "$G2/hyg"
( cd "$REPO_ROOT" && HOME="$H" PW_PROFILE_SLOT0_WAIT_S=0.3 bash -c ': | :; compgen -v | sort > "$1/v0"; declare -F | sort > "$1/f0"; export -p | grep -v "^declare -x _=" | sort > "$1/e0"; . "$2" || exit 1; compgen -v | sort > "$1/v1"; declare -F | sort > "$1/f1"; export -p | grep -v "^declare -x _=" | sort > "$1/e1"; printf "flags=%s fd9=%s\n" "$-" "$([ -e /proc/self/fd/9 ] && echo open || echo closed)"' _ "$G2/hyg" "$SLOT_REL" ) > "$G2/hyg/out" 2>&1 || true
hyg_flags() { if [[ "$(cat "$G2/hyg/out")" =~ ^flags=([a-zA-Z]*)\ fd9=open$ ]] && [[ "${BASH_REMATCH[1]}" != *e* && "${BASH_REMATCH[1]}" != *u* ]]; then return 0; fi; return 1; }
assert_true 'Guard 2: after sourcing, errexit/nounset are off and fd 9 (the lease) is open in the surviving shell' hyg_flags
assert_true 'Guard 2: sourcing adds no shell function (declare -F before and after are identical)' cmp -s "$G2/hyg/f0" "$G2/hyg/f1"
assert_true 'Guard 2: sourcing exports nothing (export -p before and after are identical)' cmp -s "$G2/hyg/e0" "$G2/hyg/e1"
only_prof_new() { [[ "$(comm -13 "$G2/hyg/v0" "$G2/hyg/v1")" == "prof" && -z "$(comm -23 "$G2/hyg/v0" "$G2/hyg/v1")" ]]; }
assert_true 'Guard 2: sourcing adds exactly one shell variable, prof (compgen -v before and after differ by that name only)' only_prof_new

# --- Guard 2 mutation matrix (every edit lands exactly once in the pristine script; each row has a pristine counterpart above) ---
A_END='for _pwslot_v in $(compgen -A function _pwslot_); do unset -f "$_pwslot_v"; done'
# 1 — the contention flock deleted: every launch lands on slot 0
slot_mutant 1-no-flock 'flock -E 75 -n 9' 'true'
if [[ -n "$MROOT" ]]; then
  run_n g2m1 "$MROOT" "$G2/h-m1" "$MCP_ARGS" 2 overlap "$FAST"
  m1_shared() { if [[ "$RN_RAN" -eq 2 ]] && ! rn_distinct 2; then return 0; fi; return 1; }
  red 'Guard 2 mutant 1: the flock deleted → two launches share one --user-data-dir' m1_shared
fi
# 2 — a pattern kill of the decoy re-added at the end of the script
slot_mutant 2-pkill-decoy "$A_END" 'pkill -9 -f "[c]hrome.*$prof" 2>/dev/null || true; '"$A_END"
if [[ -n "$MROOT" ]]; then
  H="$G2/h-m2"; spawn_decoys "$H"
  run_n g2m2 "$MROOT" "$H" "$MCP_ARGS" 1 overlap "$FAST"
  m2_decoy_dead() { if [[ "$RN_RAN" -eq 1 ]] && wait_dead "$D_SLOT0" 3; then return 0; fi; return 1; }
  red 'Guard 2 mutant 2: a pkill of chrome.*<slot0> re-added → the decoy dies' m2_decoy_dead
fi
# 3 — a live-owner SingletonLock treated as stale (the owner-alive test inverted): the lock is removed
slot_mutant 3-live-owner-stale 'if [ "$_pwslot_alive" -eq 0 ]; then return 1; fi' 'if [ "$_pwslot_alive" -ne 0 ]; then return 1; fi'
if [[ -n "$MROOT" ]]; then
  H="$G2/h-m3"; mkdir -p "$(prof0 "$H")"; start_chrome_owner; OWNER=$SPAWNED; ln -s "$HOST_NOW-$OWNER" "$(prof0 "$H")/SingletonLock"
  run_n g2m3 "$MROOT" "$H" "$MCP_ARGS" 1 overlap "$FAST"
  m3_lock_gone() { if [[ "$RN_RAN" -eq 1 ]] && no_link "$(prof0 "$H")"; then return 0; fi; return 1; }
  red 'Guard 2 mutant 3: a live-owner SingletonLock treated as stale → the lock file is removed' m3_lock_gone
fi
# 4 — exhaustion made non-unique (two slots, then slot 0 is reused): a third concurrent launch collides
slot_mutant 4-third-collides '_pwslot_max=32' '_pwslot_max=2' '_pwslot_fallback="$_pwslot_base-p$$"' '_pwslot_fallback="$_pwslot_base"'
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
print(re.sub(r"\.\s+" + re.escape(slot) + r"\s*\|\|\s*exit 1;", "prof=$HOME/.cache/playwright-mcp-profile;", s))
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
slot_mutant 7-no-owner-check 'elif ! _pwslot_owner_busy "$_pwslot_tg"; then' 'elif true; then'
if [[ -n "$MROOT" ]]; then
  H="$G2/h-m7"; mkdir -p "$(prof0 "$H")"; start_chrome_owner; OWNER=$SPAWNED; ln -s "$HOST_NOW-$OWNER" "$(prof0 "$H")/SingletonLock"
  run_n g2m7 "$MROOT" "$H" "$MCP_ARGS" 1 overlap "$FAST"
  red 'Guard 2 mutant 7: a free lock but a live-owner SingletonLock reuses the slot → the launch lands on the owned profile' prof_is "$(prof0 "$H")"
fi
# 8 — kills every OTHER slot's Chrome (a pattern held in a variable, so Guard 1's text scan cannot see it)
slot_mutant 8-kill-other-slot "$A_END" '_pwslot_pat="chrome.*$_pwslot_base-[0-9]"; pkill -9 -f "$_pwslot_pat"; '"$A_END"
if [[ -n "$MROOT" ]]; then
  H="$G2/h-m8"; spawn_decoys "$H"
  run_n g2m8 "$MROOT" "$H" "$MCP_ARGS" 1 overlap "$FAST"
  m8_other_dead() { if [[ "$RN_RAN" -eq 1 ]] && wait_dead "$D_OTHER" 3; then return 0; fi; return 1; }
  red 'Guard 2 mutant 8: a pkill of every other slot'"'"'s Chrome → the other-slot decoy dies' m8_other_dead
fi
# 9 — kills sibling Playwright servers
slot_mutant 9-kill-sibling-server "$A_END" 'pkill -9 -f "bin/playwright-mcp.*$HOME"; '"$A_END"
if [[ -n "$MROOT" ]]; then
  H="$G2/h-m9"; spawn_decoys "$H"
  run_n g2m9 "$MROOT" "$H" "$MCP_ARGS" 1 overlap "$FAST"
  m9_srv_dead() { if [[ "$RN_RAN" -eq 1 ]] && wait_dead "$D_SRV" 3; then return 0; fi; return 1; }
  red 'Guard 2 mutant 9: a pkill of bin/playwright-mcp servers → the sibling-server decoy dies' m9_srv_dead
fi
# 10 — kills whatever holds a file open inside the claimed profile (one bounded /proc fd selector: no pkill, no pgrep, no process name;
#      a per-process readlink walk costs ~18 s at ~600 host processes and outlasts the launch window, so the selector must not scale with the host)
slot_mutant 10-kill-fd-holders "$A_END" 'for _pwslot_h in $(find /proc/[0-9]*/fd -maxdepth 1 -lname "$prof/*" 2>/dev/null | cut -d/ -f3); do if [ "$_pwslot_h" != "$$" ]; then kill -9 "$_pwslot_h"; fi; done; '"$A_END"
if [[ -n "$MROOT" ]]; then
  H="$G2/h-m10"; spawn_decoys "$H"
  run_n g2m10 "$MROOT" "$H" "$MCP_ARGS" 1 overlap "$FAST"
  m10_fd_dead() { if [[ "$RN_RAN" -eq 1 ]] && wait_dead "$D_FD" 3; then return 0; fi; return 1; }
  red 'Guard 2 mutant 10: a kill of every process holding a file open in the claimed slot → the file-holding decoy dies' m10_fd_dead
fi
# 11 — the hostname field ignored: a lock naming another host is judged by the local pid alone
slot_mutant 11-foreign-host 'if [ -z "$_pwslot_me" ] || [ "${_pwslot_t%-*}" != "$_pwslot_me" ]; then' 'if false; then'
if [[ -n "$MROOT" ]]; then
  H="$G2/h-m11"; mkdir -p "$(prof0 "$H")"; ln -s "otherhost-$dead" "$(prof0 "$H")/SingletonLock"
  run_n g2m11 "$MROOT" "$H" "$MCP_ARGS" 1 overlap "$FAST"
  m11_removed() { if [[ "$RN_RAN" -eq 1 ]] && no_link "$(prof0 "$H")"; then return 0; fi; return 1; }
  red 'Guard 2 mutant 11: the hostname ignored → a foreign host'"'"'s lock with a locally dead pid is removed' m11_removed
fi
# 12 — any live pid counts as a Chrome owner (the pre-review behaviour): a recycled pid blocks slot 0
slot_mutant 12-any-live-pid "*[Cc]hrom* | *headless_shell* | '')" '*)'
if [[ -n "$MROOT" ]]; then
  H="$G2/h-m12"; mkdir -p "$(prof0 "$H")"; start_sleeper; RECYCLED=$SPAWNED; ln -s "$HOST_NOW-$RECYCLED" "$(prof0 "$H")/SingletonLock"
  run_n g2m12 "$MROOT" "$H" "$MCP_ARGS" 1 overlap "$FAST"
  red 'Guard 2 mutant 12: every live pid counts as a Chrome owner → a recycled non-Chrome pid pushes the launch off slot 0' prof_is "$(prof0 "$H")-1"
fi
# 13 — liveness by ps alone (the fail-OPEN probe the review found): with ps absent every owner is judged dead
slot_mutant 13-ps-fails-open $'  _pwslot_alive=1\n  if ! [ -d "/proc/$_pwslot_p" ]; then' $'  _pwslot_alive=0\n  if ps -p "$_pwslot_p" >/dev/null 2>&1; then _pwslot_alive=1; fi\n  if false; then'
if [[ -n "$MROOT" ]]; then
  H="$G2/h-m13"; mkdir -p "$(prof0 "$H")"; start_chrome_owner; OWNER=$SPAWNED; ln -s "$HOST_NOW-$OWNER" "$(prof0 "$H")/SingletonLock"
  LAUNCH_PATH="$NOPS" run_n g2m13 "$MROOT" "$H" "$MCP_ARGS" 1 overlap "$FAST"
  m13_removed() { if [[ "$RN_RAN" -eq 1 ]] && no_link "$(prof0 "$H")"; then return 0; fi; return 1; }
  red 'Guard 2 mutant 13: liveness decided by ps alone, ps absent → a live Chrome'"'"'s lock is removed (the fail-open defect)' m13_removed
fi
# 14 — the owner file ignored: every contended slot-0 launch waits, whoever holds it
slot_mutant 14-owner-ignored '[ "$_pwslot_ow" = "$_pwslot_self" ]' 'true'
if [[ -n "$MROOT" ]]; then
  H="$G2/h-m14"; hold_lock "$(prof0 "$H")" 9 "$OTHER_SESSION"
  run_n g2m14 "$MROOT" "$H" "$MCP_ARGS" 1 overlap PW_PROFILE_SLOT0_WAIT_S=4
  m14_waited() { [[ "$RN_RAN" -eq 1 && "$RN_MS" -ge 2500 ]]; }
  red 'Guard 2 mutant 14: the owner file ignored → a different session'"'"'s lock is waited for the full budget' m14_waited
fi
# 15 — slots >= 1 wait too
slot_mutant 15-slots-wait 'if [ "$_pwslot_n" -eq 0 ] && _pwslot_owner_wait "$_pwslot_d"; then' 'if _pwslot_owner_wait "$_pwslot_d"; then'
if [[ -n "$MROOT" ]]; then
  H="$G2/h-m15"
  hold_slots "$H" 8 "$G2/hold8m.ready"
  run_n g2m15 "$MROOT" "$H" "$MCP_ARGS" 1 overlap "$FAST"
  m15_slow() { [[ "$RN_RAN" -eq 1 && "$RN_MS" -ge 1500 ]]; }
  red 'Guard 2 mutant 15: slots 1+ wait on their locks → the eight-busy launch takes 1.5 s or more' m15_slow
fi
# 16 — one unusable slot aborts the whole search
slot_mutant 16-rc2-aborts 'if [ "$_pwslot_i" -eq 0 ] || [ "$_pwslot_flockbad" -eq 1 ]; then break; fi' 'break'
if [[ -n "$MROOT" ]]; then
  H="$G2/h-m16"; hold_lock "$(prof0 "$H")" 30 "$OTHER_SESSION"; : > "$(prof0 "$H")-1"
  run_n g2m16 "$MROOT" "$H" "$MCP_ARGS" 1 overlap "$FAST"
  m16_fallback() { [[ "$RN_RAN" -eq 1 && "$(head -n1 <<< "$RN_PROFS")" =~ ^"$(prof0 "$H")"-p[0-9]+$ ]]; }
  red 'Guard 2 mutant 16: an unusable slot ends the search → the launch lands on the unique fallback instead of slot 2' m16_fallback
fi
# 17 — PW_PROFILE_SLOT0_WAIT_S not validated: a typo reaches flock and degrades the lease
slot_mutant 17-wait-unvalidated "'' | . | *[!0-9.]* | *.*.*)" '__never__)'
if [[ -n "$MROOT" ]]; then
  H="$G2/h-m17"; hold_lock "$(prof0 "$H")" 2 "$$"
  run_n g2m17 "$MROOT" "$H" "$MCP_ARGS" 1 overlap PW_PROFILE_SLOT0_WAIT_S=abc
  m17_degraded() { [[ "$RN_RAN" -eq 1 && "$(head -n1 <<< "$RN_PROFS")" =~ ^"$(prof0 "$H")"-p[0-9]+$ ]]; }
  red 'Guard 2 mutant 17: the wait not validated → a non-numeric value sends the launch to the unique fallback' m17_degraded
fi
# 18 — the no-flock host loses the persistent profile (the pre-review behaviour)
slot_mutant 18-noflock-no-slot0 $'if [ -z "$_pwslot_skip0" ]; then\n      rm -f' $'if false; then\n      rm -f'
if [[ -n "$MROOT" ]]; then
  H="$G2/h-m18"
  LAUNCH_PATH="$NOFLOCK" run_n g2m18 "$MROOT" "$H" "$MCP_ARGS" 1 overlap
  m18_lost() { [[ "$RN_RAN" -eq 1 && "$(head -n1 <<< "$RN_PROFS")" =~ ^"$(prof0 "$H")"-p[0-9]+$ ]]; }
  red 'Guard 2 mutant 18: no slot-0 claim without flock → the first session on a no-flock host gets a unique empty profile' m18_lost
fi
# 19 — the fallback name aliases a slot directory
slot_mutant 19-fallback-aliases '_pwslot_fallback="$_pwslot_base-p$$"' '_pwslot_fallback="$_pwslot_base-$$"'
if [[ -n "$MROOT" ]]; then
  H="$G2/h-m19"
  hold_slots "$H" 32 "$G2/hold32m.ready"
  run_n g2m19 "$MROOT" "$H" "$MCP_ARGS" 1 overlap "$FAST"
  m19_numeric() { [[ "$RN_RAN" -eq 1 && "$(head -n1 <<< "$RN_PROFS")" =~ ^"$(prof0 "$H")"-[0-9]+$ ]]; }
  red 'Guard 2 mutant 19: the fallback named $base-$$ → its name is a number a slot could also have' m19_numeric
fi
# 20 — the lease leaks into a child (a lingering process holding fd 9): a SIGKILL of the proxy no longer frees the slot
slot_mutant 20-lease-leaks "$A_END" 'sleep 3 9>&9 & '"$A_END"
if [[ -n "$MROOT" ]]; then
  H="$G2/h-m20"
  launch g2m20 "$MROOT" "$H" "$MCP_ARGS" "$FAST"
  m20_ready=0; if wait_ready g2m20; then m20_ready=1; fi
  m20_proxy="$(cat "$G2/g2m20.pid")"
  kill -KILL "$m20_proxy" 2>/dev/null || true
  wait_dead "$m20_proxy" 3 || true
  m20_still_held() { if [[ "$m20_ready" -eq 1 ]] && lock_held "$(prof0 "$H")/$LOCKNAME"; then return 0; fi; return 1; }
  red 'Guard 2 mutant 20: a child inherits the lease → after a SIGKILL of the proxy the slot lock is still held' m20_still_held
  end_launch g2m20
  sleep 3.2   # the leaked holder is a 3 s sleep the mutated script started; let it expire
fi
# 21 — the default wait lowered, the old token kept in a trailing comment (a grep over the whole file still finds it)
slot_mutant 21-default-3 'PW_PROFILE_SLOT0_WAIT_S:-7}"' 'PW_PROFILE_SLOT0_WAIT_S:-3}" # PW_PROFILE_SLOT0_WAIT_S:-7}'
if [[ -n "$MROOT" ]]; then
  m21_default_gone() { ! default_wait_is "$MROOT/$SLOT_REL" 7; }
  red 'Guard 2 mutant 21: the default lowered to 3 with the old token left in a comment → the comment-stripped default row fails' m21_default_gone
  m21_pair_broken() { ! wait_pairs_grace "$MROOT/$SLOT_REL" "$REPO_ROOT/$PROXY_REL_PATH"; }
  red 'Guard 2 mutant 21: the same lowered default no longer covers the proxy teardown → the pairing row fails' m21_pair_broken
fi
# 22 — the capability probe read strictly (rc 0 only): a probe that loses the shared /dev/null lock (rc 75) means "no usable flock"
slot_mutant 22-probe-strict $'    0 | 75) return 0 ;;' $'    0) return 0 ;;'
if [[ -n "$MROOT" ]]; then
  barrier_run g2m22 "$G2/h-m22" "$BAR_N" "$MROOT/$SLOT_REL"
  m22_real_race() { [[ "$BAR_NOTES" -ge 1 || "$BAR_DISTINCT" -lt "$BAR_N" ]]; }
  red "Guard 2 mutant 22: the strict rc-0 probe → among $BAR_N simultaneous launches some print the false \"no usable flock\" note or share a profile" m22_real_race
  barrier_run g2m22b "$G2/h-m22b" 2 "$MROOT/$SLOT_REL" "PATH=$PROBEBUSY:$PATH"
  m22_probe_busy() { [[ "$BAR_NOTES" -ge 1 ]]; }
  red 'Guard 2 mutant 22: the strict rc-0 probe, a probe answering 75 → "no usable flock" is printed and the launch takes the no-lease branch (the deterministic form)' m22_probe_busy
fi

# ===========================================================================
# Guard 3 — the registrations
# ===========================================================================
assert_true 'Guard 3: .mcp.json carries "env": {"PLAYWRIGHT_MCP_PING_TIMEOUT_MS": "0"} (a guard for future pin bumps: inert on stdio in 0.0.78/0.0.83)' reg_ok "$PROJECT_MCP" project
assert_true 'Guard 3: plugins/soleur/.mcp.json carries the same env and a single --chromium-fallback before the -- separator' reg_ok "$PLUGIN_MCP" plugin
reg_mutant 'Guard 3 mutant 1: the project registration loses its env' "$PROJECT_MCP" project 'e.pop("env", None)'
reg_mutant 'Guard 3 mutant 2: the project env value drifts from 0' "$PROJECT_MCP" project 'e["env"] = {"PLAYWRIGHT_MCP_PING_TIMEOUT_MS": "30000"}'
reg_mutant 'Guard 3 mutant 3: the plugin registration loses its env' "$PLUGIN_MCP" plugin 'e.pop("env", None)'
reg_mutant 'Guard 3 mutant 4: the plugin env key is misspelled' "$PLUGIN_MCP" plugin 'e["env"] = {"PLAYWRIGHT_MCP_PING_TIMEOUT": "0"}'
reg_mutant 'Guard 3 mutant 5: the plugin registration loses --chromium-fallback' "$PLUGIN_MCP" plugin 'e["args"].remove("--chromium-fallback")'

# ---------------------------------------------------------------------------
# Harness hygiene: every process this suite started is gone after reap_own, and the hygiene predicate can tell
# ---------------------------------------------------------------------------
reap_own
# own_all_dead <file of pids>: none of the recorded pids is alive
own_all_dead() { local p; while read -r p; do if [[ -n "$p" ]] && alive "$p"; then return 1; fi; done < "$1"; return 0; }
npx_pids_dead() { local p; while read -r p; do if [[ -n "$p" ]] && alive "$p"; then return 1; fi; done < <(cat "$WORK"/g2/*.jsonl.pid 2>/dev/null || true); return 0; }
assert_true 'Hygiene: every pid this suite recorded is dead after reap_own' own_all_dead "$OWN"
assert_true 'Hygiene: every npx-shim server pid this suite started is dead after reap_own' npx_pids_dead
# mutation (harness): a neutered reaper leaves the recorded pid alive, so the predicate above is false — it can tell
leak_observed() {
  local f="$WORK/hc-leak-own" pid
  : > "$f"
  sleep 300 >/dev/null 2>&1 & pid=$!; printf '%s\n' "$pid" >> "$f"; disown "$pid"
  # the neutered reaper does nothing here
  if own_all_dead "$f"; then kill -KILL "$pid" 2>/dev/null || true; return 1; fi
  reap_list "$f"
  wait_dead "$pid" 3 || true
  own_all_dead "$f"
}
red 'Hygiene mutant (harness): a neutered reap_own leaves a recorded pid alive, so own_all_dead is false; the real reaper then clears it' leak_observed

# ---------------------------------------------------------------------------
# Verdict. Reported with printf + exit, never through ok()/bad() (ADR-193).
# ---------------------------------------------------------------------------
printf '\n%d passed, %d failed, %d cases (%d mutants, %d mutation rows)\n' "$pass" "$fail" "$cases" "$mutants_declared" "$red_rows"

if [[ $((pass + fail)) -ne $cases ]]; then
  printf '[FATAL] vacuity accounting: pass+fail (%d) != cases (%d) — a row did not report\n' "$((pass + fail))" "$cases" >&2
  exit 1
fi
EXPECTED_MUTANTS=50   # Guard 1: 21 static + 3 dynamic mutants; Guard 2: mutants 1-5 and 7-22 (6 is a harness row); Guard 3: mutants 1-5
EXPECTED_RED_ROWS=55   # the 50 mutants, one extra row each for Guard 2 mutants 21 and 22, plus the three harness rows (Guard 1, Guard 2 #6, Hygiene)
if [[ $mutants_declared -ne $EXPECTED_MUTANTS || $red_rows -ne $EXPECTED_RED_ROWS ]]; then
  printf '[FATAL] mutation matrix: %d mutants / %d mutation rows ran, expected %d / %d — a row vanished\n' "$mutants_declared" "$red_rows" "$EXPECTED_MUTANTS" "$EXPECTED_RED_ROWS" >&2
  exit 1
fi
MIN_ASSERTIONS=175
if [[ $cases -lt $MIN_ASSERTIONS ]]; then
  printf '[FATAL] vacuity floor: only %d cases executed, expected at least %d\n' "$cases" "$MIN_ASSERTIONS" >&2
  exit 1
fi
[[ $fail -eq 0 ]] || exit 1
exit 0
