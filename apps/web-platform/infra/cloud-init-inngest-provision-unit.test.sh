#!/usr/bin/env bash
# Guard suite for #8562: the dedicated inngest host provisions through a LATCHED, RETRYING systemd
# unit (soleur-inngest-provision.service + .timer), not through a once-per-instance runcmd item.
#
# WHAT IS GUARDED. The plan's `## Guard Contract` (8 guards, 59 rows: 51 RED + 8 must-PASS),
# knowledge-base/project/plans/2026-09-28-fix-inngest-bootstrap-pull-retrying-unit-plan.md, plus 24
# rows from the PR #9159 review (widened detectors, degraded success, the wider FSM quiesce):
# 83 rows, 74 RED + 9 must-PASS.
#   G1 single login + pull site, inside the script the unit executes (never runcmd)
#   G2 every failure arm retries, none latches, one EXIT trap reports it
#   G3 latch identity and position
#   G4 every doppler call gets an exported token (the #6985 class)
#   G5 first-boot ordering, a single trigger, no back-edge
#   G6 bounded rate, unbounded persistence, runcmd-equivalent environment
#   G7 no implicit shared-shell state (runtime, under `dash -u`)
#   G8 isolation is re-proven on every attempt
#
# EVERYTHING READS THE TERRAFORM RENDER. The input is the bytes that reach the host:
# inngest-userdata-budget.sh renders cloud-init-inngest.yml through terraform's own templatefile
# + local.inngest_rationale_strip (its stub table is SHARED, not copied), so a missed `$${` or
# `%%{` escape is a render error here, not a surprise on the host.
#
# THREE LAYERS.
#   static  Guards 1, 5, 6, 8 plus the static detectors of 2, 3, 4 (section-aware unit parser,
#           spelling-normalized pull/login/latch census).
#   Tier A  the rendered script, path-rewritten into a fixture root, run under `dash -u` with
#           `env -i` + a fixture produced by EXECUTING the rendered /etc/default/inngest-doppler
#           write + the unit's own Environment= lines. Stubs for docker/doppler/timeout/sleep/
#           systemctl/sync/ip/dpkg, the NIC wait and the three emitters. NEVER skips. Exact return
#           codes; rc 127, or rc 2 without `parameter not set`, is an INSTRUMENT FAULT and fails
#           loudly. After EVERY scenario: the latch exists iff rc==0 and the success was not
#           degraded.
#   Tier B  systemd 255 as PID 1 in the pinned ubuntu:24.04 image: the real retry, latch, timer,
#           TimeoutStartSec kill and EnvironmentFile parsing (T6, T9, T10, T11, T12, T15) in one
#           logged run. Skips only with a named reason: docker absent off-CI, the ADR-188 apt
#           archive arm_skip, or an unbootable systemd container off-CI (under CI the last is a
#           FAIL). What a skipped Tier B loses, stated precisely: no ROW (every row in the matrix is
#           scored by the static or Tier A layer), but the real-systemd EVIDENCE — that systemd 255
#           actually parses EnvironmentFile=, delivers SIGTERM on TimeoutStartSec, merges a timer
#           start into an auto-restart wait, honours ConditionPathExists= across a reboot, and
#           fires an elapsed OnBootSec timer. The static layer pins the DIRECTIVES those behaviours
#           depend on, not systemd's behaviour; T15's quiesce logic is also covered in Tier A
#           (Q1-Q5).
#
# ROWS. Every row mutates a pristine copy of the RENDER (the guard's input), asserts the mutation
# LANDED, runs the whole guard over it, and requires (RED) a FAIL line naming its assertion with
# no instrument fault, or (must-PASS) a clean run. Rows are reported by ID (G<n>-r<m>) and only
# EXECUTED rows are counted; the suite fails if the executed count is not the matrix total.
# A control row (C0) runs the pristine render first; nothing is scored if it is not clean.
#
# Usage: bash apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh
#   PU_TIERB=0   skip Tier B locally (reported as a named skip; refused under CI)
set -uo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The pin is owned by git-data-runcmd-rehearsal.test.sh (rule-audit.yml watches that copy); read it
# from there so a bump cannot leave Tier B on a stale image. Read at setup so a bad pin fails early.
UBUNTU_BASE="$(sed -nE "s/^UBUNTU_BASE='(ubuntu:24\.04@sha256:[0-9a-f]{64})'\$/\1/p" "${SCRIPT_DIR}/git-data-runcmd-rehearsal.test.sh" 2>/dev/null | head -1)"
[ -n "$UBUNTU_BASE" ] || { echo "FAIL SETUP: no UBUNTU_BASE pin readable from git-data-runcmd-rehearsal.test.sh" >&2; exit 1; }
BUDGET="$SCRIPT_DIR/inngest-userdata-budget.sh"
EXPECTED_ROWS=83
EXPECTED_RED=74
EXPECTED_MUSTPASS=9

die() { printf 'INSTRUMENT FAULT: %s\n' "$*" >&2; exit 2; }

# Refuses an empty, relative, `..`-bearing, synthetic-fs or root directory before any write or
# `rm -rf` is pointed at it. Copied BYTE-IDENTICALLY from scripts/ensure-kb-index.test.sh, the
# canonical body the fixture-dir scanners compare against (plugins/soleur/test/lib/fixture-scan.py).
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

for _t in python3 terraform dash jq sha256sum; do
  command -v "$_t" >/dev/null 2>&1 || die "$_t is required (Tier A never skips; the render needs terraform)"
done
python3 -c 'import yaml' 2>/dev/null || die "python3 yaml module is required"
DASH="$(command -v dash)"

W="$(mktemp -d -t provision-unit-XXXXXX)" || die "mktemp -d failed"
case "$W" in /*/provision-unit-*) : ;; *) die "scratch dir $W is not an absolute mktemp path" ;; esac
TIERB_CTR=""
cleanup() {
  [ -n "$TIERB_CTR" ] && docker rm -f "$TIERB_CTR" "$TIERB_CTR-build" >/dev/null 2>&1
  if [ -n "${PU_KEEP_WORK:-}" ]; then echo "(kept $W)" >&2; else rm -rf "$W"; fi
}
trap cleanup EXIT

# =================================================================================================
# Phase 0.2 — render through terraform's own pipeline and gate the payload.
# =================================================================================================
PRISTINE="$W/pristine.yml"
BUDGET_LOG="$W/budget.log"
bash "$BUDGET" "$PRISTINE" > "$BUDGET_LOG" 2>&1
BUDGET_RC=$?
echo "=== cloud-init-inngest provision unit (#8562) ==="
echo "--- Phase 0.2: terraform render (templatefile -> strip -> base64gzip) ---"
sed 's/^/  /' "$BUDGET_LOG"
[ "$BUDGET_RC" -eq 0 ] || { echo "  FAIL: render/budget gate rc=$BUDGET_RC (a missed \$\${ or %%{ escape, or an over-cap payload)"; exit 1; }
[ -s "$PRISTINE" ] || die "the budget script produced no stripped render"
[ "$(head -1 "$PRISTINE")" = '#cloud-config' ] || { echo "  FAIL: the stripped render does not start with #cloud-config"; exit 1; }
STORED_BYTES="$(sed -n 's/^  stored (b64gzip): \([0-9]*\) B$/\1/p' "$BUDGET_LOG")"
[ -n "$STORED_BYTES" ] && [ "$STORED_BYTES" -le 32768 ] || { echo "  FAIL: stored payload ${STORED_BYTES:-unknown} B is not <= 32768"; exit 1; }
echo "  PASS: render starts with #cloud-config and stores ${STORED_BYTES} B <= 32768 B"

# =================================================================================================
# The python half: extraction, rewrite, and the static guards. One file, subcommands.
# =================================================================================================
PY="$W/pu.py"
cat > "$PY" <<'PYEOF'
import hashlib, json, os, posixpath, re, sys, yaml

SCRIPT_PATH = "/usr/local/bin/soleur-inngest-provision"
SVC_PATH = "/etc/systemd/system/soleur-inngest-provision.service"
TMR_PATH = "/etc/systemd/system/soleur-inngest-provision.timer"
STATE_DIR = "/var/lib/soleur-inngest-provision"
LATCH = STATE_DIR + "/done"
ENVFILE = "/etc/default/inngest-doppler"
IID_CORE = re.compile(r"\(cat (/\S+) 2>/dev/null \|\| hostname\) \| LC_ALL=C tr -cd '([^']*)'")

# Every spelling that reaches the docker CLI: a bare `docker`, a quoted "docker", an absolute
# /usr/bin/docker or /usr/local/bin/docker. normalize() folds them to `docker` before matching.
DOCKER_WORD = re.compile(r'(?:"docker"|\'docker\'|(?:/usr(?:/local)?)?/bin/docker)(?=[\s;|&)]|$)')
PULL = re.compile(r"(^|[\s;|&(`])docker\s+(--config\s+\S+\s+)?(image\s+|container\s+)?pull(\s|$)")
ZREF_FETCH = re.compile(r"(^|[\s;|&(`])docker\s+(--config\s+\S+\s+)?(container\s+)?(run|create)\b[^\n]*\"\$ZIREF\"")
LOGIN = re.compile(r"(^|[\s;|&(`])docker\s+(--config\s+\S+\s+)?login(\s|$)")
BOOT_INVOKE = re.compile(r"(^|[\s;|&(`])(bash|sh|dash|exec|source|\.)\s+\"?[^\s\"]*inngest-bootstrap\.sh\b|(^|[\s;|&(`])\"?/[^\s\"]*inngest-bootstrap\.sh\"?(\s|$)")
XTRACE = re.compile(r"(^|[\s;|&(`])set\s+(-[A-Za-z]*[xv][A-Za-z]*|-o\s+(xtrace|verbose))(\s|;|$)|(^|[\s;|&(`])(ba|da)?sh\s+-[A-Za-z]*[xv]")
HEREDOC = re.compile(r"<<-?\s*'?\"?([A-Za-z_][A-Za-z0-9_]*)'?\"?")

def normalize(line):
    return DOCKER_WORD.sub("docker", line)

def is_pull(line):
    n = normalize(line)
    return bool(PULL.search(n) or ZREF_FETCH.search(n))

def is_login(line):
    return bool(LOGIN.search(normalize(line)))

def npath(p):
    return posixpath.normpath(re.sub(r"/+", "/", str(p)))

def load(p):
    raw = open(p, "rb").read()
    try:
        d = yaml.safe_load(raw) or {}
    except Exception:
        d = {}
    if not isinstance(d, dict):
        d = {}
    return raw, d

def wf_list(d):
    return [w for w in (d.get("write_files") or []) if isinstance(w, dict) and w.get("path")]

def wf_map(d):
    """Grouped by the NORMALIZED path, so `/usr/local/bin//x` and `/usr/local/bin/./x` are the same
    entry (an alias that would otherwise shadow or be shadowed by the checked one)."""
    out = {}
    for w in wf_list(d):
        out.setdefault(npath(w["path"]), []).append(w)
    return out

def items(d, key="runcmd"):
    rc = d.get(key) or []
    return [(" ".join(str(y) for y in x) if isinstance(x, list) else str(x)) for x in rc]

def _code_part(s):
    """The line with arithmetic `$(( … ))` spans and a trailing comment removed — so a `<<` in a
    comment or in shell arithmetic never opens a phantom heredoc."""
    s = re.sub(r"\$\(\([^)]*\)\)", " ", s)
    s = re.sub(r"(^|\s)#.*$", "", s)
    return s

def joined(text):
    """(first_lineno, logical_line) with backslash-newline continuations joined."""
    out, buf, start = [], "", None
    for i, l in enumerate(text.split("\n")):
        if start is None:
            start = i
        if l.endswith("\\") and not l.strip().startswith("#"):
            buf += l[:-1] + " "
            continue
        out.append((start, buf + l))
        buf, start = "", None
    if buf:
        out.append((start, buf))
    return out

def code_lines(text):
    """(lineno, stripped) for shell code lines: comments dropped, heredoc BODIES dropped,
    backslash-continued lines joined."""
    out, hd = [], None
    for i, l in joined(text):
        s = l.strip()
        if hd is not None:
            if s == hd:
                hd = None
            continue
        if not s or (s.startswith("#") and not s.startswith("#!")):
            continue
        out.append((i, s))
        m = HEREDOC.search(_code_part(s))
        if m:
            hd = m.group(1)
    return out

def all_lines(text):
    """(lineno, stripped) for EVERY non-comment line, heredoc bodies INCLUDED (the xtrace scan)."""
    return [(i, l.strip()) for i, l in joined(text) if l.strip() and not l.strip().startswith("#")]

def heredocs(text):
    """[(start_lineno, opener_line, body_text)]"""
    res = []
    lines = text.split("\n")
    i = 0
    while i < len(lines):
        s = lines[i].strip()
        m = HEREDOC.search(_code_part(s)) if not s.startswith("#") else None
        if m:
            tag = m.group(1); body = []; j = i + 1
            while j < len(lines) and lines[j].strip() != tag:
                body.append(lines[j]); j += 1
            res.append((i, s, "\n".join(body)))
            i = j + 1
            continue
        i += 1
    return res

def unit_parse(text):
    """{section: [(key, value)]} — section-aware, comments dropped."""
    secs, cur = {}, None
    for l in text.split("\n"):
        s = l.strip()
        if not s or s.startswith("#") or s.startswith(";"):
            continue
        m = re.match(r"^\[([^\]]+)\]$", s)
        if m:
            cur = m.group(1); secs.setdefault(cur, []); continue
        if "=" in s and cur is not None:
            k, v = s.split("=", 1)
            secs[cur].append((k.strip(), v.strip()))
    return secs

def vals(secs, sec, key):
    return [v for k, v in secs.get(sec, []) if k == key]

UNITS = {"us": 1e-6, "usec": 1e-6, "ms": 1e-3, "msec": 1e-3, "s": 1, "sec": 1, "second": 1, "seconds": 1,
         "m": 60, "min": 60, "minute": 60, "minutes": 60, "h": 3600, "hr": 3600, "hour": 3600, "hours": 3600,
         "d": 86400, "day": 86400, "days": 86400}
def span(v):
    v = v.strip()
    if not v or v == "infinity":
        return None
    if re.fullmatch(r"\d+(\.\d+)?", v):
        return float(v)
    tot, pos = 0.0, 0
    for m in re.finditer(r"\s*(\d+(?:\.\d+)?)\s*([a-z]+)", v):
        if m.start() != pos or m.group(2) not in UNITS:
            return None
        tot += float(m.group(1)) * UNITS[m.group(2)]; pos = m.end()
    return tot if pos == len(v) else None

def resolve_vars(lines):
    env = {}
    for _, s in lines:
        m = re.fullmatch(r'([A-Z_][A-Z0-9_]*)=("?)([^"\s$]*|\$\{?[A-Z_]+\}?/[^"\s]*)\2', s)
        if m:
            env[m.group(1)] = m.group(3)
    for _ in range(5):
        for k, v in list(env.items()):
            env[k] = re.sub(r"\$\{?([A-Z_][A-Z0-9_]*)\}?", lambda mm: env.get(mm.group(1), mm.group(0)), v)
    return env

def expand(s, env):
    s = re.sub(r'"\$\{?([A-Z_][A-Z0-9_]*)\}?"', lambda m: env.get(m.group(1), m.group(0)), s)
    return re.sub(r"\$\{?([A-Z_][A-Z0-9_]*)\}?", lambda m: env.get(m.group(1), m.group(0)), s)

def write_targets(s, env):
    """Every path a line can CREATE, in any spelling: `>`/`>>` (also `N>`, `&>`, `exec N>`), tee,
    touch, install, cp, mv, ln, mkdir, dd of=. Quoting is dropped and variables expanded, so
    `"$STATE"/done`, `"$LATCH"` and the literal all resolve to one path."""
    t = []
    for part in re.split(r"\|\||&&|;|\|", s):
        p = expand(part, env).replace('"', "").replace("'", "")
        for m in re.finditer(r"(?:\d|&)?>>?\s*([^\s;&|)]+)", p):
            t.append(m.group(1))
        toks = p.split()
        while toks and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=\S*|exec|sudo|command|builtin", toks[0]):
            toks = toks[1:]
        if toks and toks[0] in ("touch", "install", "cp", "mv", "ln", "mkdir", "tee") and len(toks) >= 2:
            args = [x for x in toks[1:] if not x.startswith("-") and not re.fullmatch(r"[0-7]{3,4}", x)]
            if toks[0] in ("touch", "mkdir", "tee"):
                t.extend(args)
            elif args:
                t.append(args[-1])
        for m in re.finditer(r"\bof=(\S+)", p):
            t.append(m.group(1))
    return [npath(x) for x in t if x.startswith("/")]

def facts(render):
    raw, d = load(render)
    wf = wf_map(d)
    f = {"sha": hashlib.sha256(raw).hexdigest(), "raw": raw, "doc": d, "wf": wf, "wfl": wf_list(d),
         "items": items(d), "boot": items(d, "bootcmd")}
    f["script"] = str(wf[SCRIPT_PATH][0].get("content", "")) if len(wf.get(SCRIPT_PATH, [])) == 1 else ""
    f["svc"] = str(wf[SVC_PATH][0].get("content", "")) if len(wf.get(SVC_PATH, [])) == 1 else ""
    f["tmr"] = str(wf[TMR_PATH][0].get("content", "")) if len(wf.get(TMR_PATH, [])) == 1 else ""
    return f

def cmd_extract(render, out):
    f = facts(render)
    open(os.path.join(out, "script.sh"), "w").write(f["script"])
    open(os.path.join(out, "unit.service"), "w").write(f["svc"])
    open(os.path.join(out, "unit.timer"), "w").write(f["tmr"])
    env_items = [x for x in f["items"] if re.search(r">\s*" + re.escape(ENVFILE) + r"\s*$", x.strip())]
    open(os.path.join(out, "envwrite.sh"), "w").write(env_items[0] + "\n" if len(env_items) == 1 else "")
    zr = [x for x in f["items"] if "/etc/default/soleur-zot-read" in x and "printf" in x]
    open(os.path.join(out, "zotwrite.sh"), "w").write(zr[0] + "\n" if len(zr) == 1 else "")
    secs = unit_parse(f["svc"])
    open(os.path.join(out, "unit.env"), "w").write("\n".join(vals(secs, "Service", "Environment")) + "\n")
    arm = [x for x in f["items"] if "soleur-inngest-provision" in x]
    open(os.path.join(out, "arming.sh"), "w").write("\n".join(arm) + "\n")
    print("READ_SHA=%s" % f["sha"])
    print("SCRIPT_CODE_LINES=%d" % len(code_lines(f["script"])))
    print("ENVWRITE_ITEMS=%d" % len(env_items))

def cmd_rewrite(src, fx, dst, pairs_json):
    body = open(src).read()
    pairs = json.loads(pairs_json)
    table = {a: b.replace("@FX@", fx) for a, b in pairs}
    hits = {a: 0 for a in table}
    # ONE simultaneous pass: a sequential replace would rewrite inside an already-substituted
    # fixture path (the /tmp/ pair matching /var/tmp/<fx>/...), which is a corrupted instrument.
    rx = re.compile("|".join(re.escape(a) for a in sorted(table, key=len, reverse=True)))
    def sub(m):
        hits[m.group(0)] += 1
        return table[m.group(0)]
    body = rx.sub(sub, body)
    bad = [a for a, n in hits.items() if n == 0]
    open(dst, "w").write(body)
    for a in bad:
        print("UNMATCHED=%s" % a)

SVC_FORBIDDEN = ("TimeoutSec", "StartLimitInterval", "StartLimitBurst", "RestartPreventExitStatus",
                 "SuccessExitStatus", "UnsetEnvironment", "KillSignal", "KillMode", "OnFailure",
                 "OnSuccess", "RestartForceExitStatus", "TimeoutStopSec", "FinalKillSignal")
SANDBOX = ("PrivateTmp", "ProtectSystem", "ProtectHome", "NoNewPrivileges", "PrivateDevices",
           "ProtectKernelTunables", "ReadOnlyPaths", "DynamicUser")

def cmd_static(render):
    f = facts(render)
    R = []
    def chk(name, ok, detail=""):
        R.append(("PASS" if ok else "FAIL", name + ((" [" + detail + "]") if detail else "")))
    d, wf, its, sc, svc, tmr = f["doc"], f["wf"], f["items"], f["script"], f["svc"], f["tmr"]
    boot = f["boot"]
    print("READ_SHA=%s" % f["sha"])
    L = code_lines(sc)
    env = resolve_vars(L)
    ssec, tsec = unit_parse(svc), unit_parse(tmr)
    others = [(p, str(w.get("content", ""))) for p, ws in wf.items() if p != SCRIPT_PATH for w in ws]

    # ---- dispatch -------------------------------------------------------------------------------
    chk("dispatch: runcmd has items", len(its) > 0, "items=%d" % len(its))
    chk("dispatch: the provision script is delivered once in write_files, 0755, root:root",
        len(wf.get(SCRIPT_PATH, [])) == 1 and str(wf[SCRIPT_PATH][0].get("permissions")) == "0755"
        and str(wf[SCRIPT_PATH][0].get("owner")) == "root:root" and len(L) >= 40, "code lines=%d" % len(L))
    chk("dispatch: the unit exists (soleur-inngest-provision.service in write_files, 0644)",
        len(wf.get(SVC_PATH, [])) == 1 and str(wf[SVC_PATH][0].get("permissions")) == "0644" and bool(ssec))
    chk("dispatch: the timer exists (soleur-inngest-provision.timer in write_files, 0644)",
        len(wf.get(TMR_PATH, [])) == 1 and str(wf[TMR_PATH][0].get("permissions")) == "0644" and bool(tsec))
    raw_paths = [str(w["path"]) for w in f["wfl"]]
    aliases = sorted(p for p in raw_paths if p != npath(p))
    dup = sorted(p for p in set(npath(x) for x in raw_paths) if [npath(x) for x in raw_paths].count(p) > 1)
    chk("G1: every write_files path is canonical and unique (no // or ./ alias that could shadow the checked entry)",
        not aliases and not dup, "aliases=%s dup=%s" % (aliases, dup))

    # ---- G1 -------------------------------------------------------------------------------------
    early = its + boot
    rc_pull = sum(1 for x in early for _, s in code_lines(x) if is_pull(s))
    rc_login = sum(1 for x in early for _, s in code_lines(x) if is_login(s))
    chk("G1: no runcmd or bootcmd item pulls an image, in any docker spelling", rc_pull == 0, "found %d" % rc_pull)
    chk("G1: no runcmd or bootcmd item runs docker login", rc_login == 0, "found %d" % rc_login)
    other = sum(1 for _, c in others for _, s in code_lines(c) if is_pull(s) or is_login(s))
    chk("G1: no other write_files entry pulls or logs in", other == 0, "found %d" % other)
    s_pull = [s for _, s in L if is_pull(s)]
    s_login = [s for _, s in L if is_login(s)]
    chk("G1: the provision script carries exactly ONE image pull (any spelling, a create/run of the zot ref included) and it pulls \"$ZIREF\"",
        len(s_pull) == 1 and re.search(r'docker pull "\$ZIREF"', normalize(s_pull[0])) is not None, "pulls=%d" % len(s_pull))
    chk("G1: the pull is bounded by exactly `timeout 180`",
        len(s_pull) == 1 and re.search(r'(^|\s)timeout 180 docker pull "\$ZIREF"', normalize(s_pull[0])) is not None,
        s_pull[0][:80] if s_pull else "")
    chk("G1: the provision script carries exactly ONE docker login, to \"$ZOT_EP\"",
        len(s_login) == 1 and 'docker login "$ZOT_EP"' in normalize(s_login[0]), "logins=%d" % len(s_login))
    es = vals(ssec, "Service", "ExecStart")
    chk("G1: the unit's ExecStart binds to the write_files provision script path",
        len(es) == 1 and es[0].split()[0] == SCRIPT_PATH if es else False, "ExecStart=%s" % es)
    b_in = sum(1 for _, s in L if BOOT_INVOKE.search(s))
    b_out = sum(1 for x in early for _, s in code_lines(x) if BOOT_INVOKE.search(s)) + \
        sum(1 for _, c in others for _, s in code_lines(c) if BOOT_INVOKE.search(s))
    chk("G1: inngest-bootstrap.sh is invoked exactly once, by the provision script, and nowhere else",
        b_in == 1 and b_out == 0, "script=%d elsewhere=%d" % (b_in, b_out))

    # ---- G2 (static half) ------------------------------------------------------------------------
    chk("G2: Restart=on-failure in [Service]", vals(ssec, "Service", "Restart") == ["on-failure"],
        "got %s" % vals(ssec, "Service", "Restart"))
    traps_exit = [(i, s) for i, s in L if re.match(r"^trap\s", s) and re.search(r"\bEXIT\b", s)]
    chk("G2: exactly one EXIT trap in the script, and it is not a reset",
        len(traps_exit) == 1 and not re.match(r"^trap\s+-\s", traps_exit[0][1]), "found %d" % len(traps_exit))
    term = [s for _, s in L if re.match(r"^trap\s+'.*exit 143'\s+(TERM\s+INT|INT\s+TERM|TERM)$", s)]
    chk("G2: a TERM/INT trap exits 143 (dash runs no EXIT trap on an untrapped SIGTERM)", len(term) == 1,
        "found %d" % len(term))
    top, infn = [], False
    for i, s in L:  # top-level statements only: a function BODY runs when called, not where defined
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*\(\)\s*\{$", s):
            infn = True; continue
        if infn:
            if s == "}":
                infn = False
            continue
        top.append((i, s))
    first_fallible = min([i for i, s in top if re.search(r"\bdocker\b|\bdoppler\b|inngest-boot-phone-home|\bmkdir\b|soleur-inngest-nic-wait", s)] or [10**9])
    chk("G2: the EXIT trap is installed before the first fallible command (docker/doppler/mkdir/emit/nic-wait)",
        len(traps_exit) == 1 and traps_exit[0][0] < first_fallible, "trap line %s, first fallible %s" % (traps_exit[0][0] if traps_exit else None, first_fallible))
    cores = [m.groups() for m in IID_CORE.finditer(sc)]
    emit_body = str(wf["/usr/local/bin/soleur-boot-emit"][0].get("content", "")) if len(wf.get("/usr/local/bin/soleur-boot-emit", [])) == 1 else ""
    cores += [m.groups() for m in IID_CORE.finditer(emit_body)]
    cores += [m.groups() for x in its if "provision-unit-armed" in x for m in IID_CORE.finditer(x)]
    chk("G2: the iid derivation is byte-identical in soleur-boot-emit, the provision script and the arming item",
        len(cores) == 3 and len(set(cores)) == 1, "sites=%d distinct=%d" % (len(cores), len(set(cores))))

    # ---- G3 -------------------------------------------------------------------------------------
    cond = vals(ssec, "Unit", "ConditionPathExists")
    cpath = npath(cond[0][1:]) if len(cond) == 1 and cond[0].startswith("!") else ""
    writes = []
    for i, s in L:
        for t in write_targets(s, env):
            if cpath and t == cpath:
                writes.append(i)
    chk("G3: the unit's ConditionPathExists=! path is the path the script writes as its latch",
        bool(cpath) and len(writes) >= 1, "condition=%s writes=%d" % (cond, len(writes)))
    chk("G3: exactly one latch write site (spellings normalized: : >, >, N>, &>, exec N>, tee, touch, install, cp, mv, ln, mkdir, dd of=, $VAR and \"$VAR\"/x)",
        len(writes) == 1, "found %d" % len(writes))
    sd = vals(ssec, "Service", "StateDirectory")
    chk("G3: StateDirectory=soleur-inngest-provision (root disk, survives a reboot)", sd == ["soleur-inngest-provision"], "got %s" % sd)
    chk("G3: the latch path sits under /var/lib/soleur-inngest-provision/ (not tmpfs)", cpath.startswith(STATE_DIR + "/"), cpath)
    chk("G3: the script ends with an explicit exit 0", bool(L) and L[-1][1] == "exit 0", L[-1][1] if L else "")

    # ---- G4 -------------------------------------------------------------------------------------
    ef = vals(ssec, "Service", "EnvironmentFile")
    chk("G4: EnvironmentFile=/etc/default/inngest-doppler, exactly once, no '-' tolerance prefix", ef == [ENVFILE], "got %s" % ef)
    envw = [x for x in its if re.search(r">\s*" + re.escape(ENVFILE) + r"\s*$", x.strip())]
    home_ok = "HOME=/root" in vals(ssec, "Service", "Environment") or (len(envw) == 1 and "HOME=/root" in envw[0])
    chk("G4: HOME=/root reaches the unit environment (Environment= or the inngest-doppler write)", home_ok)
    dop = [s for _, s in L if re.search(r"(^|[\s;|&(`])doppler\s", s)]
    bad = [s for s in dop if re.search(r"\benv\s+(-i|--ignore-environment|-u\s*(DOPPLER_TOKEN|HOME))\b|\bunset\s+(DOPPLER_TOKEN|HOME)", s)]
    chk("G4: no doppler call clears or strips its environment (env -i / env -u / unset)", len(dop) >= 2 and not bad,
        "doppler calls=%d bad=%d" % (len(dop), len(bad)))
    chk("G4: the script never bare-sources /etc/default/inngest-doppler (the unit supplies it)",
        not any(re.match(r"^(\.|source)\s+/etc/default/inngest-doppler", s) or "; . /etc/default/inngest-doppler" in s for _, s in L))
    envblk = [s for _, s in L if re.match(r'^env\s+"INNGEST_CLI_VERSION=', s)]
    chk("G4: the bootstrap env list passes the literal \"DOPPLER_PROJECT=soleur-inngest\"",
        any(re.search(r'(^|\s)"DOPPLER_PROJECT=soleur-inngest"(\s|$)', s) for s in envblk), "env lines=%d" % len(envblk))
    # #9175: on the RENDER (what this suite reads) the template arg has already resolved, so the
    # prod-render invariant is "DOPPLER_CONFIG=prd" — the rehearsal render carries its scratch name.
    chk("G4: the bootstrap env list passes the resolved \"DOPPLER_CONFIG=prd\" (#9175 — prod renders prd; rehearsal renders rehearsal_<runid>)",
        any(re.search(r'(^|\s)"DOPPLER_CONFIG=prd"(\s|$)', s) for s in envblk), "env lines=%d" % len(envblk))
    guards = [x for x in its if "WRITE_GUARD_EOV" in x and "[!A-Za-z0-9._:/-]" in x and re.search(r"\bexit 1\b", x)]
    chk("G4: both credential files are charset-guarded before they are written (inngest-doppler, soleur-zot-read)",
        len(guards) == 2 and any("zot-read-write-REFUSED" in g for g in guards)
        and any("inngest-doppler-write-REFUSED" in g for g in guards), "guards=%d" % len(guards))

    # ---- G5 -------------------------------------------------------------------------------------
    def pos(pred):
        return [n for n, x in enumerate(its) if any(pred(s) for _, s in code_lines(x))]
    UNIT_RX = r"soleur-inngest-provision(\.service)?(?![.\w-])"
    nic = pos(lambda s: re.search(r"(^|[\s;&|(])(/usr/local/bin/)?soleur-inngest-nic-wait(\s|$)", s) is not None)
    starts_svc = pos(lambda s: re.search(r"\bsystemctl\b.*\b(start|restart|try-restart|reload-or-restart|add-wants|add-requires)\b.*" + UNIT_RX, s) is not None)
    can_start = pos(lambda s: re.search(r"\bsystemctl\b.*\b(start|restart|try-restart|reload-or-restart|add-wants|add-requires)\b.*soleur-inngest-provision", s) is not None
                    or re.search(r"\bsystemctl\b.*\benable\b.*--now.*soleur-inngest-provision|\bsystemctl\b.*--now\b.*\benable\b.*soleur-inngest-provision", s) is not None)
    tenable = pos(lambda s: re.search(r"\bsystemctl\b.*\benable\b.*soleur-inngest-provision\.timer", s) is not None)
    tenable_now = pos(lambda s: re.search(r"\bsystemctl\b.*\benable\b.*soleur-inngest-provision\.timer", s) is not None and "--now" in s)
    noblock = pos(lambda s: re.search(r"\bsystemctl\b.*\bstart\b.*--no-block.*" + UNIT_RX + r"|\bsystemctl\b.*--no-block.*\bstart\b.*" + UNIT_RX, s) is not None)
    boot_starts = sum(1 for x in boot for _, s in code_lines(x) if "soleur-inngest-provision" in s)
    chk("G5 dispatch: runcmd has items and exactly one NIC-wait call", len(its) > 0 and len(nic) == 1, "items=%d nic=%d" % (len(its), len(nic)))
    chk("G5: exactly one runcmd item starts the provision service (suffix optional, add-wants counted), and it is --no-block; bootcmd never touches it",
        len(starts_svc) == 1 and starts_svc == noblock and boot_starts == 0, "starts=%s noblock=%s bootcmd=%d" % (starts_svc, noblock, boot_starts))
    chk("G5: the timer is enabled exactly once and WITHOUT --now (an elapsed OnBootSec would fire at once)",
        len(tenable) == 1 and not tenable_now, "enable=%s now=%s" % (tenable, tenable_now))
    chk("G5: the NIC wait precedes every item that can start the unit (start/restart/enable --now/add-wants)",
        len(nic) == 1 and bool(can_start) and all(nic[0] < p for p in can_start), "nic=%s starters=%s" % (nic, can_start))
    prereq = pos(lambda s: "/etc/default/inngest-server" in s and "printf" in s) + pos(lambda s: s.startswith("useradd") or "useradd -m" in s) + pos(lambda s: "/etc/default/inngest-probe" in s)
    chk("G5: the arming items follow the prerequisites only runcmd writes (inngest-server env, deploy user, probe credential)",
        len(prereq) >= 3 and bool(can_start) and bool(tenable) and max(prereq) < min(can_start + tenable), "prereq=%s" % prereq)
    back = []
    for p, ws in wf.items():
        if p in (SVC_PATH, TMR_PATH) or not re.match(r"^/etc/systemd/system/[^/]+\.(service|timer|target|socket|path|mount)$", p):
            continue
        for w in ws:
            for sec, kvs in unit_parse(str(w.get("content", ""))).items():
                for k, v in kvs:
                    if k in ("After", "Requires", "Wants", "BindsTo", "Requisite", "PartOf", "Upholds") and "soleur-inngest-provision" in v:
                        back.append("%s:%s" % (p, k))
    chk("G5: nothing but its timer orders after, requires or wants the provision unit (no back-edge)", not back, ",".join(back))

    # ---- G6 -------------------------------------------------------------------------------------
    chk("G6: [Unit] StartLimitIntervalSec=0 (unlimited restarts; section-aware)",
        vals(ssec, "Unit", "StartLimitIntervalSec") == ["0"] and not vals(ssec, "Service", "StartLimitIntervalSec"),
        "unit=%s service=%s" % (vals(ssec, "Unit", "StartLimitIntervalSec"), vals(ssec, "Service", "StartLimitIntervalSec")))
    forb = sorted(set(k for kv in ssec.values() for k, _ in kv if k in SVC_FORBIDDEN))
    chk("G6: the service sets none of the directives that would bound, silence or redirect a failed attempt (TimeoutSec, StartLimitInterval/Burst, RestartPreventExitStatus, SuccessExitStatus, UnsetEnvironment, KillSignal, KillMode, OnFailure, OnSuccess, ...)",
        not forb, ",".join(forb))
    rs = vals(ssec, "Service", "RestartSec")
    rsv = span(rs[0]) if len(rs) == 1 else None
    chk("G6: RestartSec is set once and >= 60s (bounded retry rate)", rsv is not None and rsv >= 60, "got %s" % rs)
    rst, rmd = vals(ssec, "Service", "RestartSteps"), vals(ssec, "Service", "RestartMaxDelaySec")
    rmdv = span(rmd[0]) if len(rmd) == 1 else None
    chk("G6: the restart delay backs off (RestartSteps >= 1, RestartMaxDelaySec between RestartSec and 30min)",
        len(rst) == 1 and rst[0].isdigit() and int(rst[0]) >= 1 and rmdv is not None and rsv is not None and rsv <= rmdv <= 1800,
        "steps=%s maxdelay=%s" % (rst, rmd))
    ts = vals(ssec, "Service", "TimeoutStartSec")
    tsv = span(ts[0]) if len(ts) == 1 else None
    chk("G6: TimeoutStartSec is set once, finite, >= 20min and <= 2h (a oneshot's default is infinity)",
        tsv is not None and 1200 <= tsv <= 7200, "got %s" % ts)
    chk("G6: Type=oneshot and RemainAfterExit=yes", vals(ssec, "Service", "Type") == ["oneshot"] and vals(ssec, "Service", "RemainAfterExit") == ["yes"])
    chk("G6: the service has no [Install] section (a target would wait on a oneshot that retries for hours)", "Install" not in ssec)
    sandbox = [k for kv in ssec.values() for k, v in kv if k in SANDBOX]
    chk("G6: no sandboxing directive changes the environment the moved block ran in", not sandbox, ",".join(sandbox))
    chk("G6: UMask=0022 (runcmd's umask)", vals(ssec, "Service", "UMask") == ["0022"])
    ob = vals(tsec, "Timer", "OnBootSec")
    chk("G6: the timer re-enters on boot (OnBootSec= set) and is WantedBy=timers.target",
        len(ob) == 1 and span(ob[0]) is not None and vals(tsec, "Install", "WantedBy") == ["timers.target"], "OnBootSec=%s" % ob)
    tu = vals(tsec, "Timer", "Unit")
    chk("G6: the timer triggers the provision service (Unit= absent or exactly soleur-inngest-provision.service)",
        tu == [] or tu == ["soleur-inngest-provision.service"], "Unit=%s" % tu)
    acc = vals(tsec, "Timer", "AccuracySec")
    chk("G6: the timer's AccuracySec is <= 5s (the default 1min window delays the re-entry)",
        len(acc) == 1 and span(acc[0]) is not None and span(acc[0]) <= 5, "AccuracySec=%s" % acc)
    shadow = [p for p in raw_paths if re.search(r"soleur-inngest-provision\.(service|timer)\.d(/|$)", npath(p))
              or (re.search(r"/soleur-inngest-provision\.(service|timer)$", npath(p)) and npath(p) not in (SVC_PATH, TMR_PATH))]
    shadow += ["runcmd:%d" % n for n, x in enumerate(early) for _, s in code_lines(x)
               if re.search(r"soleur-inngest-provision\.(service|timer)\.d\b|systemctl\s+(edit|set-property)\b.*soleur-inngest-provision", s)]
    chk("G6: no drop-in, shadow copy or runtime edit of the provision unit or timer (write_files, runcmd, bootcmd)", not shadow, ",".join(shadow))
    first = [s for _, s in L if not s.startswith("#!")]
    chk("G6: the script refuses xtrace (case \"$-\" in *x*) ... exit 78) before any other command",
        bool(first) and first[0].startswith('case "$-" in *x*)') and "exit 78" in first[0])
    xt = [s for _, s in all_lines(sc) if XTRACE.search(_code_part(s))]
    chk("G6: nothing in the script turns xtrace/verbose on (set -x/-v/-o xtrace|verbose, sh -x), heredoc bodies included",
        not xt, " | ".join(x[:40] for x in xt))
    chk("G6: ExecStart is the bare script path (no interpreter, no flags)", es == [SCRIPT_PATH], "got %s" % es)

    # ---- G8 -------------------------------------------------------------------------------------
    iso = [(i, op) for i, op, body in heredocs(sc) if "doppler run" in op and "n_total" in body and "n_inngest" in body]
    chk("G8 dispatch: exactly one isolation self-check site in the script", len(iso) == 1, "found %d" % len(iso))
    first_pull = min([i for i, s in L if is_pull(s)] or [10**9])
    chk("G8: the isolation check precedes the first image pull", len(iso) == 1 and iso[0][0] < first_pull,
        "iso=%s pull=%s" % (iso[0][0] if iso else None, first_pull))
    chk("G8: no reference to the retired /run/soleur-inngest-doppler.ok sentinel anywhere in the render",
        b"soleur-inngest-doppler.ok" not in f["raw"])
    paths = set()
    for _, s in L:
        e = expand(s, env)
        paths.update(re.findall(re.escape(STATE_DIR) + r"/[A-Za-z0-9_.-]+", e))
        paths.update("RUN:" + x for x in re.findall(r"(?<![A-Za-z0-9_])/run/[A-Za-z0-9_./-]+", e))
    extra = sorted(p for p in paths if p not in (LATCH, STATE_DIR + "/attempts", "RUN:/run/inngest-bs-logs-token"))
    chk("G8: the script keeps no verdict state (only done + attempts under the StateDirectory, only the bs-token under /run)",
        not extra, ",".join(extra))
    anchor = any("HEARTBEAT_URL)|BETTERSTACK_LOGS_TOKEN)" in body for _, op, body in heredocs(sc) if "doppler run" in op)
    chk("G8: the isolation regex keeps BETTERSTACK_LOGS_TOKEN a top-level sibling (HEARTBEAT_URL)|BETTERSTACK_LOGS_TOKEN) anchor)", anchor)

    for st, name in R:
        print("  %s: %s" % (st, name))

if __name__ == "__main__":
    c = sys.argv[1]
    if c == "extract":
        cmd_extract(sys.argv[2], sys.argv[3])
    elif c == "static":
        cmd_static(sys.argv[2])
    elif c == "rewrite":
        cmd_rewrite(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
    else:
        sys.exit(2)
PYEOF

# The Tier A path-rewrite table: the proven G4 table of cloud-init-inngest-bootstrap.test.sh
# (/usr/local/bin/, /etc/default/, /var/log/, /run/) extended with /var/lib/, /tmp/, /var/lock/
# (the flip FSM's host state slot) and /etc/systemd/system/ (the installed inngest-server unit the
# degraded-success check reads). EVERY pair must match the rendered script at least once — a pair
# that matches nothing is an instrument fault, never a pass. (/root/ is not in the table: the
# script names no /root/ path, so the pair would be a guaranteed fault; HOME=/root reaches the
# script through the environment instead.)
REWRITE_PAIRS='[["/usr/local/bin/","@FX@/bin/"],["/etc/default/","@FX@/etc/"],["/var/log/","@FX@/log/"],["/run/","@FX@/run/"],["/var/lib/","@FX@/lib/"],["/tmp/","@FX@/tmp/"],["/var/lock/","@FX@/lock/"],["/etc/systemd/system/","@FX@/systemd/"]]'

# =================================================================================================
# Tier A stubs. Every stub appends one line to $FX/calls.log; scenario knobs are FILES under
# $FX/ctl (never environment: the script's environment is built only from the unit's sources).
# =================================================================================================
make_stubs() {
  local fx="$1" b="$1/bin"
  assert_fixture_dir "$fx"
  assert_fixture_dir "$b"
  mkdir -p "$b"
  cat > "$b/docker" <<STUB
#!/bin/sh
FX='$fx'
printf 'docker %s\n' "\$*" >> "\$FX/calls.log"
[ "\$1" = --config ] && shift 2
case "\$1" in image|container) shift ;; esac
ctl() { cat "\$FX/ctl/\$1" 2>/dev/null || printf '%s' "\$2"; }
case "\$1" in
  info) exit 0 ;;
  login) exit "\$(ctl login_rc 0)" ;;
  rm) exit "\$(ctl rm_rc 0)" ;;
  pull)
    n=\$(cat "\$FX/pulls.n" 2>/dev/null || echo 0); n=\$((n + 1)); echo "\$n" > "\$FX/pulls.n"
    i=0; r=0
    for r in \$(ctl pull_rc 0); do i=\$((i + 1)); [ "\$i" -ge "\$n" ] && break; done
    exit "\$r" ;;
  create) printf '%s\n' "\$(ctl cid cid0123abcd)"; exit "\$(ctl create_rc 0)" ;;
  cp)
    src="\$2"; dst="\$3"; base="\${src##*:/}"
    if [ "\$base" = inngest-bootstrap.sh ]; then
      rc=\$(ctl cp_boot_rc 0); [ "\$rc" -eq 0 ] || exit "\$rc"
      cat > "\$dst" <<'BOOT'
#!/bin/bash
FX=@FXDIR@
p=absent; [ -e "\$FX/tmp/inngest-cutover-flip.sh" ] && p=\$(cat "\$FX/tmp/inngest-cutover-flip.sh")
printf 'bootstrap start DOPPLER_PROJECT=%s planted=%s\n' "\${DOPPLER_PROJECT-unset}" "\$p" >> "\$FX/calls.log"
# The real bootstrap writes the inngest-server unit: the durable ExecStart carries the
# --postgres-max-open-conns sentinel, the SQLite-only fail-safe does not.
mkdir -p "\$FX/systemd"
if [ -f "\$FX/ctl/boot_degraded" ]; then
  printf '[Service]\nExecStart=/usr/local/bin/inngest start --sqlite-dir /var/lib/inngest\n' > "\$FX/systemd/inngest-server.service"
else
  printf '[Service]\nExecStart=/usr/local/bin/inngest start --postgres-max-open-conns 5\n' > "\$FX/systemd/inngest-server.service"
fi
exit "\$(cat "\$FX/ctl/boot_rc" 2>/dev/null || echo 0)"
BOOT
      sed -i "s#@FXDIR@#\$FX#" "\$dst"
      exit 0
    fi
    if grep -qxF "\$base" "\$FX/ctl/cp_fail" 2>/dev/null; then exit 1; fi
    printf 'asset:%s\n' "\$base" > "\$dst"; exit 0 ;;
  inspect) printf 'INNGEST_CLI_VERSION=1.2.3\nVECTOR_CLI_VERSION=0.40.0\n'; exit 0 ;;
esac
exit 0
STUB
  # Re-asserted here: the docker stub's heredoc above defines a function (`ctl() {`), which the
  # fixture scanner reads as a new function window.
  assert_fixture_dir "$b"
  cat > "$b/doppler" <<STUB
#!/bin/sh
FX='$fx'
printf 'doppler %s TOKEN=%s HOME=%s\n' "\$*" "\${DOPPLER_TOKEN:+set}" "\${HOME-unset}" >> "\$FX/calls.log"
case "\$1" in
  run) while [ "\$#" -gt 0 ] && [ "\$1" != -- ]; do shift; done; shift; exec "\$@" ;;
  secrets)
    case "\$2" in
      --only-names) cat "\$FX/ctl/names" 2>/dev/null || printf '{"INNGEST_SIGNING_KEY":{},"INNGEST_EVENT_KEY":{},"INNGEST_REDIS_PASSWORD":{},"INNGEST_POSTGRES_URI":{},"BETTERSTACK_LOGS_TOKEN":{},"DOPPLER_PROJECT":{}}\n' ;;
      download) printf '{}\n' ;;
      get) [ "\$3" = INNGEST_DIAGNOSTIC_BOOT ] && cat "\$FX/ctl/diag" 2>/dev/null ;;
    esac ;;
esac
exit 0
STUB
  cat > "$b/timeout" <<STUB
#!/bin/sh
FX='$fx'
shift
if [ "\$1 \$2" = "docker pull" ] && [ -f "\$FX/ctl/pull_timeout" ]; then
  printf 'docker pull %s (timeout 124)\n' "\$3" >> "\$FX/calls.log"; exit 124
fi
exec "\$@"
STUB
  # systemctl: `is-active [--quiet] U...` answers per unit from ctl/is_active_<unit> (default:
  # inngest-redis.service active, everything else inactive); --quiet turns it into an exit code.
  cat > "$b/systemctl" <<STUB
#!/bin/sh
FX='$fx'
printf 'systemctl %s\n' "\$*" >> "\$FX/calls.log"
case "\$1" in
  is-active)
    shift; q=0; all=0
    for u in "\$@"; do
      [ "\$u" = --quiet ] && { q=1; continue; }
      d=inactive; [ "\$u" = inngest-redis.service ] && d=active
      st=\$(cat "\$FX/ctl/is_active_\$u" 2>/dev/null || echo "\$d")
      [ "\$st" = active ] || all=3
      [ "\$q" = 1 ] || echo "\$st"
    done
    exit "\$all" ;;
  is-enabled) echo enabled ;;
esac
exit 0
STUB
  local s
  for s in sleep sync journalctl ss nft curl dpkg; do
    cat > "$b/$s" <<STUB
#!/bin/sh
FX='$fx'
printf '$s %s\n' "\$*" >> "\$FX/calls.log"
case "$s" in curl) printf '000' ;; esac
exit 0
STUB
  done
  cat > "$b/ip" <<STUB
#!/bin/sh
FX='$fx'
printf 'ip %s\n' "\$*" >> "\$FX/calls.log"
[ -f "\$FX/ctl/nic_absent" ] && exit 0
printf '1: lo    inet 127.0.0.1/8 scope host lo\n3: enp7s0    inet 10.0.1.40/32 brd 10.0.1.40 scope global dynamic enp7s0\n'
exit 0
STUB
  cat > "$b/soleur-inngest-nic-wait" <<STUB
#!/bin/sh
FX='$fx'
printf 'nic-wait %s\n' "\$*" >> "\$FX/calls.log"
exit 0
STUB
  cat > "$b/inngest-boot-phone-home.sh" <<STUB
#!/bin/sh
FX='$fx'
printf 'phone %s\n' "\$*" >> "\$FX/calls.log"
[ -f "\$FX/ctl/ph_fail_\$1" ] && exit 3
exit 0
STUB
  cat > "$b/soleur-boot-emit" <<STUB
#!/bin/sh
FX='$fx'
printf 'emit %s\n' "\$*" >> "\$FX/calls.log"
exit 0
STUB
  cat > "$b/inngest-bs-token-restage.sh" <<STUB
#!/bin/sh
FX='$fx'
printf 'restage\n' >> "\$FX/calls.log"
printf 'restaged-token' > "\$FX/run/inngest-bs-logs-token"
exit 0
STUB
  printf '#!/bin/sh\ncat\n' > "$b/inngest-redact.sh"
  chmod +x "$b"/*
}

# =================================================================================================
# guard_all <render> <workdir> — every static + Tier A assertion over ONE render. Prints
# `  PASS:`/`  FAIL:`/`  FAULT:` lines and READ_SHA=. rc 0 clean, 1 assertion failures, 2 fault.
# Harness knob (the G7-r2 row mutates the HARNESS, not the render): PU_DASH_FLAGS (default -u).
# =================================================================================================
guard_all() {
  local render="$1" gw="$2"
  local dflags="${PU_DASH_FLAGS--u}"
  local fx="$gw/fx" nfault=0
  assert_fixture_dir "$gw"
  assert_fixture_dir "$fx"
  rm -rf "$gw"; mkdir -p "$gw" "$fx" || { echo "  FAULT: could not create $gw"; return 2; }

  local static_out
  static_out="$(python3 "$PY" static "$render" 2>"$gw/static.err")" || { echo "  FAULT: static checker crashed"; sed 's/^/    /' "$gw/static.err"; return 2; }
  printf '%s\n' "$static_out"
  python3 "$PY" extract "$render" "$gw" > "$gw/extract.out" 2>"$gw/extract.err" || { echo "  FAULT: extractor crashed"; sed 's/^/    /' "$gw/extract.err"; return 2; }
  local code_lines envw
  code_lines="$(sed -n 's/^SCRIPT_CODE_LINES=//p' "$gw/extract.out")"
  envw="$(sed -n 's/^ENVWRITE_ITEMS=//p' "$gw/extract.out")"

  _ta() { # _ta <ok 0|1> <name>
    if [ "$1" -eq 0 ]; then echo "  PASS: $2"; else echo "  FAIL: $2"; fi
  }
  assert_fixture_dir "$gw"
  assert_fixture_dir "$fx"
  # ---- Tier A dispatch: a render with no substantive script or no env write cannot run Tier A;
  # that is a FAILED property of the render, not an instrument fault.
  if [ "${code_lines:-0}" -lt 40 ] || [ "${envw:-0}" -ne 1 ] || [ ! -s "$gw/zotwrite.sh" ]; then
    _ta 1 "TA dispatch: the provision script (>=40 code lines, found ${code_lines:-0}), the inngest-doppler write (found ${envw:-0}) and the zot creds bake were extracted"
    return 1
  fi
  _ta 0 "TA dispatch: the provision script, the inngest-doppler write and the zot creds bake were extracted"

  # ---- the rewrite, every pair asserted ---------------------------------------------------------
  python3 "$PY" rewrite "$gw/script.sh" "$fx" "$fx/script.sh" "$REWRITE_PAIRS" > "$gw/rewrite.out" || { echo "  FAULT: rewrite crashed"; return 2; }
  if grep -q '^UNMATCHED=' "$gw/rewrite.out"; then
    echo "  FAULT: TA rewrite pair(s) matched nothing: $(sed -n 's/^UNMATCHED=//p' "$gw/rewrite.out" | tr '\n' ' ')"
    return 2
  fi
  echo "  PASS: TA rewrite: every path-rewrite pair matched at least once"
  make_stubs "$fx"

  # ---- the environment: executed inngest-doppler write + the unit's Environment= lines ----------
  mkdir -p "$fx/etc"
  sed "s#/etc/default/#$fx/etc/#g" "$gw/envwrite.sh" > "$gw/envwrite.fx.sh"
  env -i PATH=/usr/bin:/bin sh "$gw/envwrite.fx.sh" || { echo "  FAULT: executing the rendered inngest-doppler write failed"; return 2; }
  [ -s "$fx/etc/inngest-doppler" ] || { echo "  FAULT: the executed inngest-doppler write produced nothing"; return 2; }
  cp "$fx/etc/inngest-doppler" "$gw/inngest-doppler.fixture"
  local -a ENVKV=()
  local kv unit_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  while IFS= read -r kv; do
    [ -n "$kv" ] || continue
    case "$kv" in PATH=*) unit_path="${kv#PATH=}" ;; *) ENVKV+=("$kv") ;; esac
  done < "$gw/unit.env"
  while IFS= read -r kv; do
    case "$kv" in PWD=*|SHLVL=*|_=*|OLDPWD=*|PATH=*|"") ;; *) ENVKV+=("$kv") ;; esac
  done < <(env -i /bin/sh -c 'set -a; . "$1"; exec env' sh "$gw/inngest-doppler.fixture")
  ENVKV+=("PATH=$fx/bin:$unit_path")

  # ---- scenario runner ---------------------------------------------------------------------------
  reset_fx() { # full reset (fresh host) unless $1 = keep
    assert_fixture_dir "$fx"
    assert_fixture_dir "$gw"
    if [ "${1:-}" != keep ]; then
      rm -rf "${fx:?}/lib" "${fx:?}/run" "${fx:?}/tmp" "${fx:?}/log" "${fx:?}/ctl" "${fx:?}/lock" "${fx:?}/calls.log"
      mkdir -p "$fx/lib/cloud/data" "$fx/lib/soleur-inngest-provision" "$fx/run" "$fx/tmp" "$fx/log" "$fx/ctl" "$fx/lock"
      printf 'i-fixture\n' > "$fx/lib/cloud/data/instance-id"
      printf 'bs-token' > "$fx/run/inngest-bs-logs-token"
      sed "s#/etc/default/#$fx/etc/#g" "$gw/zotwrite.sh" | env -i PATH=/usr/bin:/bin sh || true
    fi
    rm -rf "${fx:?}/ctl" "${fx:?}/pulls.n" "${fx:?}/systemd"; mkdir -p "$fx/ctl"
    rm -f "$fx/etc/soleur-inngest-image"
  }
  local SC_RC SC_START
  run_sc() { # run_sc <scenario> [dash flags override]
    assert_fixture_dir "$fx"
    assert_fixture_dir "$gw"
    local sc="$1" fl="${2-$dflags}"
    SC_START=$(( $(wc -l < "$fx/calls.log" 2>/dev/null || echo 0) + 1 ))
    printf '== %s\n' "$sc" >> "$fx/calls.log"
    # shellcheck disable=SC2086
    ( cd "$fx" && env -i "${ENVKV[@]}" "$DASH" $fl "$fx/script.sh" ) > "$gw/$sc.out" 2> "$gw/$sc.err"
    SC_RC=$?
    sed -n "$((SC_START + 1)),\$p" "$fx/calls.log" > "$gw/$sc.log"
    if [ "$SC_RC" -eq 127 ] || { [ "$SC_RC" -eq 2 ] && ! grep -q 'parameter not set' "$gw/$sc.err"; }; then
      echo "  FAULT: TA $sc rc=$SC_RC is an instrument fault (127 = a stub or tool missing; 2 without 'parameter not set' = a parse error). stderr: $(head -c 300 "$gw/$sc.err" | tr '\n' '|')"
      nfault=$((nfault + 1))
    fi
  }
  has() { grep -qE "$2" "$gw/$1.log"; }
  cnt() { grep -cE "$2" "$gw/$1.log" || true; }
  at() { local _o; _o="$(grep -nE "$2" "$gw/$1.log")" || true; _o="${_o%%$'\n'*}"; printf '%s' "${_o%%:*}"; }
  # THE LATCH INVARIANT, asserted after EVERY scenario: the latch exists iff the attempt exited 0
  # AND was not a degraded success. One assertion per scenario, so a latch written by any arm on
  # any path — on a failure, on a timeout, on a degraded success — reds the scenario it happened in.
  latch_iff() { # latch_iff <scenario>
    local want=absent got=absent
    { [ "$SC_RC" = 0 ] && ! has "$1" '^phone bootstrap-done-DEGRADED '; } && want=present
    [ -e "$LATCHF" ] && got=present
    _ta "$([ "$want" = "$got" ] && echo 0 || echo 1)" "TA $1: the latch exists iff rc==0 and not degraded (rc=$SC_RC, latch $got, expected $want)"
  }
  common() { # common <scenario> <expected rc>
    _ta "$([ "$SC_RC" = "$2" ] && echo 0 || echo 1)" "TA $1: exits $2 (rc=$SC_RC)"
    _ta "$(grep -q 'parameter not set' "$gw/$1.err" && echo 1 || echo 0)" "TA $1: no 'parameter not set' in stderr (the script reads nothing it does not set, G7)"
    latch_iff "$1"
  }
  assert_fixture_dir "$fx"
  assert_fixture_dir "$gw"
  local PULL_RE='^docker (--config [^ ]+ )?(image |container )?pull '
  local LATCHF="$fx/lib/soleur-inngest-provision/done"
  local _o

  # -u probe (G7 own dispatch): the invocation must abort on a guaranteed-unset read.
  printf 'echo "$PU_GUARANTEED_UNSET_SENTINEL"\n' > "$fx/probe.sh"
  # shellcheck disable=SC2086
  ( env -i "${ENVKV[@]}" "$DASH" $dflags "$fx/probe.sh" ) > /dev/null 2> "$gw/probe.err"
  local prc=$?
  _ta "$( [ "$prc" -eq 2 ] && grep -q 'parameter not set' "$gw/probe.err" && echo 0 || echo 1)" "G7 dispatch: -u is in effect in the Tier A invocation (probe rc=$prc)"

  # X — xtrace refusal: exit 78 before ANY stub call.
  reset_fx; run_sc X "-x $dflags"
  _ta "$( [ "$SC_RC" = 78 ] && [ "$(grep -vc '^== ' "$gw/X.log")" = 0 ] && echo 0 || echo 1)" "TA X: under dash -x the script exits 78 before any emit or call (rc=$SC_RC, calls=$(grep -vc '^== ' "$gw/X.log"))"
  latch_iff X

  # T1 — miss: every pull fails.
  reset_fx; echo 1 > "$fx/ctl/pull_rc"; run_sc T1; common T1 1
  local t1_fatal t1_exit t1_lastnamed t1_after
  t1_fatal="$(at T1 '^phone inngest_pull_fatal .*attempt=1 iid=i-fixture ')"; t1_exit="$(at T1 '^phone provision-attempt-exit-1 ')"
  _o="$(grep -E '^phone ' "$gw/T1.log")" || true
  _o="$(grep -vE '^phone provision-attempt-exit-' <<<"$_o")" || true
  t1_lastnamed="$(tail -1 <<<"$_o" | awk '{print $2}')"
  t1_after="$(awk -v f="${t1_fatal:-999999}" 'NR > f && /^docker (create|cp) /' "$gw/T1.log")"
  _ta "$( [ "$(cnt T1 "$PULL_RE")" = 3 ] && echo 0 || echo 1)" "TA T1: exactly 3 zot pulls (pulls=$(cnt T1 "$PULL_RE"))"
  _ta "$( [ -n "$t1_fatal" ] && has T1 '^emit inngest_pull_fatal fatal rc=1$' && echo 0 || echo 1)" "TA T1: inngest_pull_fatal attempt=1 iid= on both channels"
  _ta "$( [ -z "$t1_after" ] && echo 0 || echo 1)" "TA T1: no docker create/cp after the miss"
  _ta "$( [ "$t1_lastnamed" = inngest_pull_fatal ] && [ -n "$t1_exit" ] && echo 0 || echo 1)" "TA T1: inngest_pull_fatal is the last named-stage emit before provision-attempt-exit-1 (last=$t1_lastnamed)"
  _ta "$( has T1 '^emit provision_attempt_failed warning rc=1\.attempt=1\.why=inngest_pull_fatal\.iid=i-fixture$' && echo 0 || echo 1)" "TA T1: provision_attempt_failed names why=inngest_pull_fatal"

  # T2 — recover: attempt 2 on the same host; the extract container's rm FAILS inside the trap.
  reset_fx keep; echo 0 > "$fx/ctl/pull_rc"; echo 1 > "$fx/ctl/rm_rc"; : > "$fx/ctl/ph_fail_net-health"; run_sc T2; common T2 0
  _ta "$( [ -e "$LATCHF" ] && [ ! -s "$LATCHF" ] && echo 0 || echo 1)" "TA T2: the empty latch exists after a successful attempt"
  _ta "$( [ "$(tr -cd 0-9 < "$fx/lib/soleur-inngest-provision/attempts")" = 2 ] && echo 0 || echo 1)" "TA T2: the attempt counter reads 2"
  _ta "$( has T2 '^phone bootstrap-done attempt=2 iid=i-fixture$' && ! has T2 '^phone provision-attempt-exit' && echo 0 || echo 1)" "TA T2: bootstrap-done carries iid and no provision-attempt-exit is emitted"
  _ta "$( [ -n "$(at T2 '^sync ')" ] && echo 0 || echo 1)" "TA T2: the latch write is synced"
  _ta "$( has T2 '^phone provision-attempt-start attempt=2 iid=i-fixture' && echo 0 || echo 1)" "TA T2: provision-attempt-start attempt=2 iid=i-fixture"
  _ta "$( ! has T2 '^nic-wait ' && has T2 '^timeout 300 dpkg --configure -a$|^dpkg --configure -a$' && echo 0 || echo 1)" "TA T2: with the private address present the NIC wait is NOT re-run, and dpkg recovery runs before the bootstrap"

  # T3 — isolation FATAL, AFTER a passing attempt in the same fixture (no verdict may carry over).
  reset_fx; echo 0 > "$fx/ctl/pull_rc"; run_sc T3a; common T3a 0
  rm -f "$LATCHF"; reset_fx keep
  printf '{"INNGEST_SIGNING_KEY":{},"INNGEST_EVENT_KEY":{},"INNGEST_REDIS_PASSWORD":{},"INNGEST_POSTGRES_URI":{},"BETTERSTACK_LOGS_TOKEN":{},"SUPABASE_SERVICE_ROLE_KEY":{}}\n' > "$fx/ctl/names"
  run_sc T3; common T3 1
  _ta "$( has T3 '^phone isolation-check-FAILED attempt=2 iid=i-fixture' && [ "$(cnt T3 "$PULL_RE")" = 0 ] && echo 0 || echo 1)" "TA T3: isolation-check-FAILED (with iid), zero pulls (pulls=$(cnt T3 "$PULL_RE"))"
  _ta "$( [ "$(grep -cE '^phone isolation-check-passed attempt=1 iid=i-fixture' "$gw/T3a.log")" = 1 ] && echo 0 || echo 1)" "TA T3: the prior attempt did pass isolation (the carry-over probe is live)"

  # T4 — bootstrap fails; the LUKS timer was active before the quiesce, so it is started again.
  reset_fx; echo 0 > "$fx/ctl/pull_rc"; echo 1 > "$fx/ctl/boot_rc"; echo active > "$fx/ctl/is_active_inngest-luks-cutover.timer"; run_sc T4; common T4 1
  local t4_x t4_j t4_q t4_b t4_r
  t4_x="$(at T4 '^phone bootstrap-exit-1 attempt=1 iid=i-fixture tail=')"; t4_j="$(at T4 '^phone bootstrap-failure-journal rc=1 attempt=1 iid=i-fixture ')"
  t4_q="$(at T4 '^systemctl stop inngest-cutover-flip\.timer inngest-luks-cutover\.timer')"; t4_b="$(at T4 '^bootstrap start ')"
  t4_r="$(at T4 '^systemctl start inngest-luks-cutover\.timer$')"
  _ta "$( [ -n "$t4_x" ] && [ -n "$t4_j" ] && [ "$t4_x" -lt "$t4_j" ] && echo 0 || echo 1)" "TA T4: bootstrap-exit-1 then bootstrap-failure-journal (both with iid)"
  _ta "$( [ -n "$t4_q" ] && [ -n "$t4_b" ] && [ "$t4_q" -lt "$t4_b" ] && echo 0 || echo 1)" "TA T4: the cutover-FSM quiesce (systemctl stop of both timers) precedes the bootstrap run (stop=$t4_q boot=$t4_b)"
  _ta "$( has T4 '^bootstrap start DOPPLER_PROJECT=soleur-inngest ' && has T4 '^phone pre-bootstrap-run attempt=1 iid=i-fixture$' && echo 0 || echo 1)" "TA T4: the bootstrap sees DOPPLER_PROJECT=soleur-inngest; pre-bootstrap-run carries iid"
  _ta "$( [ -n "$t4_r" ] && [ "$t4_r" -gt "$t4_b" ] && ! has T4 '^systemctl start inngest-cutover-flip\.timer$' && echo 0 || echo 1)" "TA T4: the failed attempt restarts exactly the timer that was active before the quiesce (luks restarted, flip not)"

  # T5 — stale container: pre-clean by name, then everything addresses the returned ID.
  reset_fx; echo 0 > "$fx/ctl/pull_rc"; echo newcid42 > "$fx/ctl/cid"; run_sc T5; common T5 0
  local t5_rm t5_cr
  t5_rm="$(at T5 '^docker rm -f soleur-inngest-bootstrap-extract$')"; t5_cr="$(at T5 '^docker create ')"
  _ta "$( [ -n "$t5_rm" ] && [ -n "$t5_cr" ] && [ "$t5_rm" -lt "$t5_cr" ] && echo 0 || echo 1)" "TA T5: the stale-name pre-clean precedes docker create"
  _ta "$( [ "$(cnt T5 '^docker cp ')" -ge 13 ] && [ "$(cnt T5 '^docker cp newcid42:/')" = "$(cnt T5 '^docker cp ')" ] && echo 0 || echo 1)" "TA T5: every docker cp (the bootstrap + the 12 STAGED assets) addresses the ID docker create returned ($(cnt T5 '^docker cp newcid42:/')/$(cnt T5 '^docker cp '))"

  # T7 — an unnamed arm (the fatal docker cp of the bootstrap script) is still reported, FIRST.
  reset_fx; echo 0 > "$fx/ctl/pull_rc"; echo 1 > "$fx/ctl/cp_boot_rc"; run_sc T7; common T7 1
  local t7_e t7_rm
  t7_e="$(at T7 '^emit provision_attempt_failed warning rc=1\.attempt=1\.why=inngest_zot\.iid=i-fixture$')"; t7_rm="$(at T7 '^timeout 15 docker rm -f cid0123abcd$|^docker rm -f cid0123abcd$')"
  _ta "$( has T7 '^phone provision-attempt-exit-1 attempt=1 why=inngest_zot iid=i-fixture$' && [ -n "$t7_e" ] && echo 0 || echo 1)" "TA T7: the EXIT trap emits provision-attempt-exit-1 and provision_attempt_failed with why= the last stage"
  _ta "$( [ -n "$t7_e" ] && [ -n "$t7_rm" ] && [ "$t7_e" -lt "$t7_rm" ] && echo 0 || echo 1)" "TA T7: the report is sent BEFORE the (bounded) container cleanup (emit=$t7_e rm=$t7_rm)"

  # T8 — timeout: one pull, no inner retry, exit 124.
  reset_fx; : > "$fx/ctl/pull_timeout"; run_sc T8; common T8 124
  _ta "$( [ "$(cnt T8 "$PULL_RE")" = 1 ] && has T8 '^phone inngest_pull_fatal .*rc=124 .*attempt=1 iid=i-fixture ' && echo 0 || echo 1)" "TA T8: exactly one pull and inngest_pull_fatal rc=124 attempt=1 iid="

  # T14 — a garbled counter never aborts the attempt.
  reset_fx; printf 'ab\001c#' > "$fx/lib/soleur-inngest-provision/attempts"; echo 1 > "$fx/ctl/pull_rc"; run_sc T14; common T14 1
  _ta "$( has T14 '^phone provision-attempt-start attempt=1 ' && echo 0 || echo 1)" "TA T14: a garbled counter reads as attempt=1"

  # T16 — a stale staged asset from a prior attempt is gone before the bootstrap runs.
  reset_fx; echo 0 > "$fx/ctl/pull_rc"; printf 'PLANTED' > "$fx/tmp/inngest-cutover-flip.sh"; echo inngest-cutover-flip.sh > "$fx/ctl/cp_fail"; run_sc T16; common T16 0
  _ta "$( has T16 '^bootstrap start .* planted=absent$' && echo 0 || echo 1)" "TA T16: the planted /tmp asset is absent when the bootstrap runs"

  # T17 — the Better Stack channel is re-armed at attempt start when the token file is empty.
  reset_fx; : > "$fx/run/inngest-bs-logs-token"; echo 0 > "$fx/ctl/pull_rc"; run_sc T17; common T17 0
  local t17_r t17_s
  t17_r="$(at T17 '^restage$')"; t17_s="$(at T17 '^phone provision-attempt-start ')"
  _ta "$( [ "$(cnt T17 '^restage$')" = 1 ] && [ -n "$t17_s" ] && [ "$t17_r" -lt "$t17_s" ] && echo 0 || echo 1)" "TA T17: the restage runs once, before provision-attempt-start"

  # TN — the reboot path: the private address is absent, the bounded NIC wait runs, and a still-
  # absent address fails the attempt before any registry call.
  reset_fx; : > "$fx/ctl/nic_absent"; run_sc TN; common TN 1
  _ta "$( [ "$(cnt TN '^nic-wait 10\.0\.1\.40$')" = 1 ] && has TN '^phone provision-nic-ABSENT ip=10\.0\.1\.40 attempt=1 iid=i-fixture$' && ! has TN '^docker (login|pull) ' && echo 0 || echo 1)" "TA TN: an absent private address runs the NIC wait once, then provision-nic-ABSENT and exit 1 with no registry call"

  # TD — degraded success: the bootstrap exited 0 but the durable shape is missing.
  reset_fx; echo 0 > "$fx/ctl/pull_rc"; echo inactive > "$fx/ctl/is_active_inngest-redis.service"; run_sc TD1; common TD1 0
  _ta "$( has TD1 '^phone bootstrap-done-DEGRADED why=\.redis-inactive attempt=1 iid=i-fixture$' && has TD1 '^emit bootstrap_done_degraded warning ' && ! has TD1 '^phone bootstrap-done attempt' && echo 0 || echo 1)" "TA TD1: redis inactive after a 0 exit -> bootstrap-done-DEGRADED, no bootstrap-done, no latch"
  reset_fx; echo 0 > "$fx/ctl/pull_rc"; : > "$fx/ctl/boot_degraded"; run_sc TD2; common TD2 0
  _ta "$( has TD2 '^phone bootstrap-done-DEGRADED why=\.no-durable-execstart attempt=1 iid=i-fixture$' && ! has TD2 '^phone bootstrap-done attempt' && echo 0 || echo 1)" "TA TD2: an installed server unit without the durable sentinel -> bootstrap-done-DEGRADED, no latch"
  reset_fx; echo 0 > "$fx/ctl/pull_rc"; : > "$fx/ctl/boot_degraded"; echo inactive > "$fx/ctl/is_active_inngest-redis.service"; printf ' true\n' > "$fx/ctl/diag"; run_sc TD3; common TD3 0
  _ta "$( has TD3 '^phone bootstrap-done attempt=1 iid=i-fixture$' && ! has TD3 'DEGRADED' && echo 0 || echo 1)" "TA TD3: a REQUESTED diagnostic boot (INNGEST_DIAGNOSTIC_BOOT=true) is exempt: bootstrap-done and the latch"

  # TQ — the cutover-FSM quiesce: each busy signal holds the bootstrap off and fails the attempt.
  local q qn
  for q in Q1 Q2 Q3 Q4; do
    reset_fx; echo 0 > "$fx/ctl/pull_rc"; echo active > "$fx/ctl/is_active_inngest-cutover-flip.timer"
    case "$q" in
      Q1) echo activating > "$fx/ctl/is_active_inngest-cutover-flip.service"; qn=".inngest-cutover-flip.service" ;;
      Q2) echo activating > "$fx/ctl/is_active_inngest-luks-cutover.service"; qn=".inngest-luks-cutover.service" ;;
      Q3) mkdir -p "$fx/lib/inngest-luks-cutover"; echo 12345678 > "$fx/lib/inngest-luks-cutover/frozen-active"; qn=".luks-frozen-active" ;;
      Q4) printf '{"exit_code":0,"dbsize":"0","reason":"x","flag":"flipping","start_ts":"t","guard":"g"}\n' > "$fx/lock/inngest-cutover-flip.state"; qn=".flip-flag-flipping" ;;
    esac
    run_sc "$q"; common "$q" 1
    _ta "$( has "$q" "^phone provision-fsm-busy units=\[${qn//./\\.}\] waited_s=300 attempt=1 iid=i-fixture$" && ! has "$q" '^bootstrap start ' && echo 0 || echo 1)" "TA $q: busy ($qn) past the bound -> provision-fsm-busy, exit 1, the bootstrap never runs"
    _ta "$( has "$q" '^systemctl start inngest-cutover-flip\.timer$' && ! has "$q" '^systemctl start inngest-luks-cutover\.timer$' && echo 0 || echo 1)" "TA $q: the failed attempt restarts the flip timer it stopped (and only that one)"
  done
  # Q5 — the NOT-busy shapes must not hold anything off: an empty frozen-active, a settled flag.
  reset_fx; echo 0 > "$fx/ctl/pull_rc"; mkdir -p "$fx/lib/inngest-luks-cutover"; : > "$fx/lib/inngest-luks-cutover/frozen-active"
  printf '{"exit_code":0,"dbsize":"0","reason":"x","flag":"done","start_ts":"t","guard":"g"}\n' > "$fx/lock/inngest-cutover-flip.state"
  run_sc Q5; common Q5 0
  _ta "$( ! has Q5 'provision-fsm-busy' && has Q5 '^bootstrap start ' && echo 0 || echo 1)" "TA Q5: an EMPTY frozen-active and a settled flip flag are not busy"

  # T6-A — every doppler call saw the token and HOME=/root (Tier B re-proves it through systemd).
  local t6_d t6_bad
  t6_d="$(grep '^doppler ' "$gw/T2.log")" || t6_d=""
  t6_bad="$(grep -v 'TOKEN=set HOME=/root$' <<<"$t6_d")" || t6_bad=""
  _ta "$( [ "$(grep -c '^doppler ' "$gw/T2.log")" -ge 2 ] && [ -z "$t6_bad" ] && echo 0 || echo 1)" "TA T6: every doppler call carries DOPPLER_TOKEN and HOME=/root"

  [ "$nfault" -eq 0 ] || return 2
  return 0
}

# score <log> -> 0 clean, 1 fails, 2 fault
score() {
  if grep -q '^  FAULT:' "$1"; then return 2; fi
  if grep -q '^  FAIL:' "$1"; then return 1; fi
  return 0
}

# =================================================================================================
# C0 — the control row: the pristine render must be CLEAN before anything is scored.
# =================================================================================================
echo ""
echo "--- C0: control row (pristine render, every static + Tier A assertion) ---"
C0_LOG="$W/c0.log"
guard_all "$PRISTINE" "$W/c0" > "$C0_LOG" 2>&1
score "$C0_LOG"; C0_RC=$?
cat "$C0_LOG" | grep -vE '^READ_SHA='
C0_PASS=$(grep -c '^  PASS:' "$C0_LOG" || true)
C0_FAIL=$(grep -c '^  FAIL:' "$C0_LOG" || true)
if [ "$C0_RC" -ne 0 ]; then
  echo ""
  echo "=== C0 RED: $C0_FAIL failing assertion(s), fault=$([ "$C0_RC" = 2 ] && echo yes || echo no). No row is scored against a dirty control. ==="
  exit 1
fi
echo "  C0: $C0_PASS assertions, all PASS"
# EXACT, not a floor with slack: the control's assertion inventory is fixed by this file, so a
# count that drifts (an assertion deleted, a scenario silently not run) is itself a RED. Bump it in
# the same edit that adds an assertion.
C0_EXPECTED=161
[ "$C0_PASS" -eq "$C0_EXPECTED" ] || { echo "  FAIL: C0 anti-vacuity — $C0_PASS assertions ran, the inventory is exactly $C0_EXPECTED"; exit 1; }

# =================================================================================================
# systemd-analyze verify over the extracted .service + .timer (Y1 precedent).
# =================================================================================================
echo ""
echo "--- systemd-analyze verify (extracted unit + timer) ---"
if command -v systemd-analyze >/dev/null 2>&1 && [ -d /usr/lib/systemd/system ]; then
  VR="$W/verify-root"
  mkdir -p "$VR/etc/systemd/system" "$VR/usr/local/bin" "$VR/usr/lib/systemd" "$VR/etc/default"
  cp -a /usr/lib/systemd/system "$VR/usr/lib/systemd/" 2>/dev/null
  cp "$W/c0/unit.service" "$VR/etc/systemd/system/soleur-inngest-provision.service"
  cp "$W/c0/unit.timer" "$VR/etc/systemd/system/soleur-inngest-provision.timer"
  cp "$W/c0/script.sh" "$VR/usr/local/bin/soleur-inngest-provision"; chmod 0755 "$VR/usr/local/bin/soleur-inngest-provision"
  cp "$W/c0/inngest-doppler.fixture" "$VR/etc/default/inngest-doppler"
  VOUT="$(systemd-analyze verify --root="$VR" soleur-inngest-provision.service soleur-inngest-provision.timer 2>&1)"; VRC=$?
  if [ "$VRC" -eq 0 ] && [ -z "$VOUT" ]; then
    echo "  PASS: systemd-analyze verify is clean ($(systemd-analyze --version | head -1))"
    VERIFY_RESULT="clean"
  else
    echo "  FAIL: systemd-analyze verify (rc=$VRC):"; printf '%s\n' "$VOUT" | sed 's/^/    /'
    exit 1
  fi
else
  echo "  SKIP: systemd-analyze not available on this host"
  VERIFY_RESULT="skipped (no systemd-analyze)"
fi

# =================================================================================================
# The row matrix. Mutators edit a COPY of the render; every anchor must match exactly once.
# =================================================================================================
MUT_PRELUDE='
import re, sys
p = sys.argv[1]; s = open(p).read()
def lines(): return s.split("\n")
def idx(stripped, after=0):
    ls = lines(); hits = [i for i, l in enumerate(ls) if i >= after and l.strip() == stripped]
    assert hits, "anchor not found: %r" % stripped
    return hits
def one(stripped, after=0):
    h = idx(stripped, after)
    assert len(h) == 1 or after, "anchor not unique (%d): %r" % (len(h), stripped)
    return h[0]
def ind(i): l = lines()[i]; return l[: len(l) - len(l.lstrip())]
def put(ls):
    global s; s = "\n".join(ls)
def rep_line(stripped, new, after=0):
    ls = lines(); i = one(stripped, after); ls[i] = ind(i) + new; put(ls)
def del_line(stripped, after=0):
    ls = lines(); i = one(stripped, after); del ls[i]; put(ls)
def ins_after(stripped, new_lines, after=0, same_indent=True):
    ls = lines(); i = one(stripped, after); pre = ind(i) if same_indent else ""
    ls[i + 1:i + 1] = [pre + x for x in new_lines]; put(ls)
def ins_before(stripped, new_lines, after=0, same_indent=True):
    ls = lines(); i = one(stripped, after); pre = ind(i) if same_indent else ""
    ls[i:i] = [pre + x for x in new_lines]; put(ls)
def raw_rep(a, b):
    global s
    assert s.count(a) == 1, "raw anchor not found exactly once: %r" % a
    s = s.replace(a, b, 1)
def block(start, end, after=0):
    ls = lines(); a = one(start, after); b = one(end, a)
    return a, b
def move_block(start, end, after_anchor, after_after=0):
    ls = lines(); a, b = block(start, end); blk = ls[a:b + 1]; del ls[a:b + 1]; put(ls)
    ls = lines(); i = one(after_anchor, after_after); ls[i + 1:i + 1] = blk; put(ls)
def save(): open(p, "w").write(s)
ISO_OPEN = "if doppler run --project soleur-inngest --config prd -- bash -s <<\x27CHKEOF\x27"
BOOT_CALL = "bash \"$EXTRACT_DIR/inngest-bootstrap.sh\" > /var/log/inngest-bootstrap.log 2>&1 &"
Q_OPEN = "systemctl stop inngest-cutover-flip.timer inngest-luks-cutover.timer >/dev/null 2>&1 || true"
Q_CLOSE = "/usr/local/bin/inngest-boot-phone-home.sh provision-fsm-busy \"units=[$_busy] waited_s=$_q attempt=$attempt iid=$IID\" || true"
ISO_FAILED = "/usr/local/bin/inngest-boot-phone-home.sh isolation-check-FAILED \"attempt=$attempt iid=$IID\" || true"
ISO_PASSED = "/usr/local/bin/inngest-boot-phone-home.sh isolation-check-passed \"attempt=$attempt iid=$IID\" || true"
'


ROWS_DIR="$W/rows"; mkdir -p "$ROWS_DIR"
declare -a ROW_IDS=()

# row <id> <RED|PASS> <expected FAIL substring, or - for PASS> <mutator python> [harness]
# harness: misdirect (G1-r6: the guard is pointed at a file other than the mutated one)
#          nou       (G7-r2: the Tier A invocation drops -u)
row_exec() {
  local id="$1" kind="$2" expect="$3" mut="$4" harness="${5:-}"
  local d="$ROWS_DIR/$id" res="$ROWS_DIR/$id.res"
  mkdir -p "$d"
  cp "$PRISTINE" "$d/render.yml"
  if [ "$harness" = nou ] || [ "$harness" = misdirect ]; then
    : # harness rows mutate the harness, not the render
  else
    if ! python3 -c "$MUT_PRELUDE$mut" "$d/render.yml" > "$d/mut.err" 2>&1; then
      echo "ABORT $id mutator failed to apply: $(tail -1 "$d/mut.err")" > "$res"; return
    fi
    if cmp -s "$PRISTINE" "$d/render.yml"; then echo "ABORT $id mutation did not change the render" > "$res"; return; fi
  fi
  local read_target="$d/render.yml" want_sha
  if [ "$harness" = misdirect ]; then
    # The mutation lands in render.yml; the guard is (wrongly) pointed at a pristine copy.
    python3 -c "$MUT_PRELUDE"'
rep_line("RestartSec=120", "RestartSec=1"); save()' "$d/render.yml" || { echo "ABORT $id harness mutation failed" > "$res"; return; }
    cp "$PRISTINE" "$d/other.yml"; read_target="$d/other.yml"
  fi
  want_sha="$(sha256sum "$d/render.yml" | cut -d' ' -f1)"
  if [ "$harness" = nou ]; then
    PU_DASH_FLAGS="" guard_all "$read_target" "$d/g" > "$d/guard.log" 2>&1
  else
    guard_all "$read_target" "$d/g" > "$d/guard.log" 2>&1
  fi
  # HARNESS SENTINEL: the guard must have read the mutated bytes.
  local got_sha; got_sha="$(sed -n 's/^READ_SHA=//p' "$d/guard.log" | sort -u)"
  if [ "$got_sha" != "$want_sha" ]; then
    echo "  FAIL: harness sentinel: the guard read the mutated render (want ${want_sha:0:12}, read ${got_sha:0:12})" >> "$d/guard.log"
  fi
  score "$d/guard.log"; local rc=$?
  if [ "$kind" = PASS ]; then
    if [ "$rc" -eq 0 ]; then echo "HELD $id" > "$res"
    else echo "BROKE $id rc=$rc :: $(grep -m3 -E '^  (FAIL|FAULT):' "$d/guard.log" | sed 's/^  //' | tr '\n' '|')" > "$res"; fi
    return
  fi
  if [ "$rc" -eq 2 ]; then echo "UNRESOLVED $id instrument fault :: $(grep -m2 '^  FAULT:' "$d/guard.log" | tr '\n' '|')" > "$res"; return; fi
  if [ "$rc" -eq 0 ]; then echo "SURVIVED $id" > "$res"; return; fi
  local fl; fl="$(grep '^  FAIL:' "$d/guard.log")"
  if [[ "$fl" == *"$expect"* ]]; then echo "KILLED $id :: $expect" > "$res"
  else echo "MISROUTED $id expected '$expect' :: $(printf '%s\n' "$fl" | head -3 | sed 's/^  //' | tr '\n' '|')" > "$res"; fi
}
row() { ROW_IDS+=("$1"); ROW_KIND[$1]="$2"; ROW_EXPECT[$1]="$3"; ROW_MUT[$1]="$4"; ROW_HARN[$1]="${5:-}"; }
declare -A ROW_KIND=() ROW_EXPECT=() ROW_MUT=() ROW_HARN=()

# ---- G1 --------------------------------------------------------------------------------------
row G1-r1 RED "G1: no runcmd or bootcmd item pulls an image" '
s = s.rstrip("\n") + "\n  - timeout 180 docker pull \"$ZIREF\"\n"; save()'
row G1-r2 RED "dispatch: runcmd has items" '
s = "#cloud-config\nruncmd: []\nwrite_files: []\n"; save()'
row G1-r3 RED "G1: the provision script carries exactly ONE image pull" '
ins_after("printf \x27INNGEST_BOOTSTRAP_IMAGE=%s\\n\x27 \"$IREF\" > /etc/default/soleur-inngest-image", ["docker pull \"$IREF\" >/dev/null 2>&1 || true"]); save()'
row G1-r4 RED "G1: the unit's ExecStart binds to the write_files provision script path" '
rep_line("ExecStart=/usr/local/bin/soleur-inngest-provision", "ExecStart=/usr/local/bin/soleur-inngest-provision2"); save()'
row G1-r5 RED "G1: no runcmd or bootcmd item runs docker login" '
ins_after("- /usr/local/bin/soleur-inngest-nic-wait 10.0.1.40 || true", ["- printf %s \"$ZOT_PULL_TOKEN\" | docker login \"$ZOT_EP\" -u \"$ZOT_PULL_USER\" --password-stdin || true"]); save()'
row G1-r6 RED "harness sentinel" '' misdirect
row G1-r7 RED "G1: the provision script carries exactly ONE image pull" '
ins_after("IREF=\"$ZIREF\"", ["docker image pull \"$ZIREF\" >/dev/null 2>&1 || true"]); save()'
row G1-r8 PASS - '
ins_before("- path: /usr/local/bin/soleur-inngest-provision", ["- path: /etc/soleur-unrelated.conf", "  content: |", "    unrelated=1", "  owner: root:root", "  permissions: \x270644\x27", ""])
ins_after("STATE=/var/lib/soleur-inngest-provision", ["", ""]); save()'

# ---- G2 --------------------------------------------------------------------------------------
row G2-r1 RED "TA T1: exits 1" '
rep_line("exit \"$zot_rc\"", "exit 0"); save()'
row G2-r2 RED "TA T1: exits 1" '
rep_line("exit \"$zot_rc\"", "( exit \"$zot_rc\" )"); save()'
row G2-r3 RED "TA T4: exits 1" '
b = one(BOOT_CALL); rep_line("wait \"$child\"", "wait \"$child\" || true", after=b); save()'
row G2-r4 RED "G2: Restart=on-failure in [Service]" '
rep_line("Restart=on-failure", "Restart=no"); save()'
row G2-r5 RED "TA T3: exits 1" '
f = one(ISO_FAILED); rep_line("exit 1", "exit 0", after=f); save()'
row G2-r6 RED "G2: a TERM/INT trap exits 143" '
del_line("trap \x27[ -z \"$child\" ] || kill \"$child\" 2>/dev/null; exit 143\x27 TERM INT"); save()'
row G2-r7 RED "G2: exactly one EXIT trap in the script" '
ins_after("trap on_exit EXIT", ["cleanup() { docker rm -f soleur-inngest-bootstrap-extract >/dev/null 2>&1 || true; }", "trap cleanup EXIT"]); save()'
row G2-r8 RED "TA T2: exits 0" '
a = one("on_exit() {"); del_line("set +e", after=a); save()'
row G2-r9 RED "G2: the EXIT trap is installed before the first fallible command" '
del_line("trap on_exit EXIT"); f = one("ZOT_EP=\"$ZOT_REGISTRY_ENDPOINT\""); ins_after("set -e", ["trap on_exit EXIT"], after=f); save()'
row G2-r10 RED "TA T4: the cutover-FSM quiesce" '
ls = lines(); a = one(Q_OPEN); b = one(Q_CLOSE); e = one("fi", after=b)
blk = ls[a:e + 1]; del ls[a:e + 1]; put(ls)
c = one(BOOT_CALL); ls = lines(); w = one("child=\"\"", after=c); ls[w + 1:w + 1] = blk; put(ls); save()'
row G2-r11 PASS - '
del_line("UMask=0022"); ins_after("StateDirectory=soleur-inngest-provision", ["UMask=0022"])
w = one("- path: /etc/systemd/system/soleur-inngest-provision.service")
del_line("Type=oneshot", after=w); ins_after("RemainAfterExit=yes", ["Type=oneshot"], after=w)
z = one("if [ \"$zot_rc\" -eq 0 ]; then"); e = one("else", after=z); ls = lines(); ls[e:e] = [ind(e) + "# arm divider (a comment between the arms)"]; put(ls); save()'

# ---- G3 --------------------------------------------------------------------------------------
row G3-r1 RED "G3: the unit's ConditionPathExists=! path is the path the script writes" '
rep_line("ConditionPathExists=!/var/lib/soleur-inngest-provision/done", "ConditionPathExists=!/var/lib/soleur-inngest-provision/ok"); save()'
row G3-r2 RED "TA T4: the latch exists iff rc==0 and not degraded" '
del_line(": > \"$LATCH\""); ins_before(Q_OPEN, [": > \"$LATCH\""]); save()'
row G3-r3 RED "G3: exactly one latch write site" '
ins_before("exit \"$boot_rc\"", [": > \"$LATCH\""]); save()'
row G3-r4 RED "G3: exactly one latch write site" '
del_line(": > \"$LATCH\""); save()'
row G3-r5 RED "TA T2: exits 0" '
ls = lines(); i = max(k for k, l in enumerate(ls) if l.strip() == "exit 0"); del ls[i]; put(ls)
ls = lines(); j = [k for k, l in enumerate(ls) if "inngest-boot-phone-home.sh net-health" in l]; assert len(j) == 1
ls[j[0]] = ls[j[0]].replace(" || true", ""); put(ls); save()'
row G3-r6 RED "G3: the latch path sits under /var/lib/soleur-inngest-provision/" '
rep_line("ConditionPathExists=!/var/lib/soleur-inngest-provision/done", "ConditionPathExists=!/run/soleur-inngest-provision/done")
rep_line("LATCH=\"$STATE/done\"", "LATCH=/run/soleur-inngest-provision/done")
ins_after("mkdir -p \"$STATE\"", ["mkdir -p /run/soleur-inngest-provision"]); save()'
row G3-r7 RED "G3: exactly one latch write site" '
ins_before("exit \"$boot_rc\"", ["install -m 0644 /dev/null \"$LATCH\""]); save()'
row G3-r8 PASS - '
rep_line(": > \"$LATCH\"", "touch \"$LATCH\""); save()'

# ---- G4 --------------------------------------------------------------------------------------
row G4-r1 RED "G4: EnvironmentFile=/etc/default/inngest-doppler" '
w = one("- path: /etc/systemd/system/soleur-inngest-provision.service"); del_line("EnvironmentFile=/etc/default/inngest-doppler", after=w); save()'
row G4-r2 RED "G4: EnvironmentFile=/etc/default/inngest-doppler" '
w = one("- path: /etc/systemd/system/soleur-inngest-provision.service"); rep_line("EnvironmentFile=/etc/default/inngest-doppler", "EnvironmentFile=-/etc/default/inngest-doppler-typo", after=w); save()'
row G4-r3 RED "G4: no doppler call clears or strips its environment" '
d = [k for k, l in enumerate(lines()) if l.strip().startswith("DIAG_BOOT=")]; assert len(d) == 1
ls = lines(); ls[d[0] + 1:d[0] + 1] = [ind(d[0]) + "DIAG2=\"$(env -i doppler secrets get INNGEST_DIAGNOSTIC_BOOT --plain 2>/dev/null || true)\""]; put(ls); save()'
row G4-r4 RED "G4: HOME=/root reaches the unit environment" '
del_line("Environment=HOME=/root"); raw_rep("printf \x27HOME=/root\\nDOPPLER_TOKEN=", "printf \x27DOPPLER_TOKEN="); save()'
row G4-r5 RED "G4: the bootstrap env list passes the literal" '
rep_line("\"DOPPLER_PROJECT=soleur-inngest\" \"DOPPLER_CONFIG=prd\" \\", "\"DOPPLER_PROJECT=soleur\" \"DOPPLER_CONFIG=prd\" \\"); save()'
row G4-r6 PASS - '
ins_after("Environment=HOME=/root", ["Environment=DOPPLER_ENABLE_VERSION_CHECK=false"]); save()'

# ---- G5 --------------------------------------------------------------------------------------
row G5-r1 RED "G5: the NIC wait precedes every item that can start the unit" '
del_line("- systemctl start --no-block soleur-inngest-provision.service")
ins_before("- /usr/local/bin/soleur-inngest-nic-wait 10.0.1.40 || true", ["- systemctl start --no-block soleur-inngest-provision.service"]); save()'
row G5-r2 RED "G5: the timer is enabled exactly once and WITHOUT --now" '
rep_line("- systemctl enable soleur-inngest-provision.timer", "- systemctl enable --now soleur-inngest-provision.timer"); save()'
row G5-r3 RED "G5: exactly one runcmd item starts the provision service" '
ins_before("- groupadd -f docker", ["- systemctl start soleur-inngest-provision.service"]); save()'
row G5-r4 RED "G5 dispatch: runcmd has items" '
ls = lines(); i = one("runcmd:"); ls = ls[:i] + ["runcmd: []"]; put(ls); save()'
row G5-r5 RED "G5: nothing but its timer orders after" '
w = one("- path: /etc/systemd/system/inngest-bs-token-restage.service"); ins_after("Before=inngest-server.service", ["After=soleur-inngest-provision.service"], after=w); save()'
row G5-r6 PASS - '
ins_after("- /usr/local/bin/soleur-inngest-nic-wait 10.0.1.40 || true", ["", "- echo unrelated-one", "", "- echo unrelated-two", ""]); save()'

# ---- G6 --------------------------------------------------------------------------------------
row G6-r1 RED "G6: [Unit] StartLimitIntervalSec=0" '
rep_line("StartLimitIntervalSec=0", "StartLimitIntervalSec=1h"); ins_after("StartLimitIntervalSec=1h", ["StartLimitBurst=5"]); save()'
row G6-r2 RED "G6: RestartSec is set once and >= 60s" '
rep_line("RestartSec=120", "RestartSec=1"); save()'
row G6-r3 RED "G6: TimeoutStartSec is set once" '
ls = lines(); j = [k for k, l in enumerate(ls) if l.strip().startswith("TimeoutStartSec=") and k > one("- path: /etc/systemd/system/soleur-inngest-provision.service")]; assert j
del ls[j[0]]; put(ls); save()'
row G6-r4 RED "G6: the service has no [Install] section" '
ins_after("ExecStart=/usr/local/bin/soleur-inngest-provision", ["", "[Install]", "WantedBy=multi-user.target"]); save()'
row G6-r5 RED "G6: no sandboxing directive" '
w = one("- path: /etc/systemd/system/soleur-inngest-provision.service"); ins_after("Type=oneshot", ["PrivateTmp=yes"], after=w); save()'
row G6-r6 RED "G6: the timer re-enters on boot" '
del_line("OnBootSec=90s"); save()'
row G6-r7 RED "G6: [Unit] StartLimitIntervalSec=0" '
del_line("StartLimitIntervalSec=0"); w = one("- path: /etc/systemd/system/soleur-inngest-provision.service"); ins_after("Type=oneshot", ["StartLimitIntervalSec=0"], after=w); save()'
row G6-r8 RED "G6: the script refuses xtrace" '
ls = lines(); j = [k for k, l in enumerate(ls) if l.strip().startswith("case \"$-\" in *x*)")]; assert len(j) == 1; del ls[j[0]]; put(ls); save()'
row G6-r9 RED "G6: ExecStart is the bare script path" '
rep_line("ExecStart=/usr/local/bin/soleur-inngest-provision", "ExecStart=/bin/sh -x /usr/local/bin/soleur-inngest-provision"); save()'
row G6-r10 PASS - '
rep_line("RestartSec=120", "RestartSec=2min"); save()'

# ---- G7 --------------------------------------------------------------------------------------
row G7-r1 RED "no 'parameter not set' in stderr" '
ins_before("ZOT_REGISTRY_ENDPOINT=\"\"", ["echo \"$ZOT_EP\" >/dev/null"]); save()'
row G7-r2 RED "G7 dispatch: -u is in effect" '' nou
row G7-r3 RED "no 'parameter not set' in stderr" '
f = one(ISO_PASSED); e = one("fi", after=f)
ls = lines(); ls[e + 1:e + 1] = [ind(e) + "echo \"$DOPPLER_PROJECT_OVERRIDE\" >/dev/null"]; put(ls); save()'
row G7-r4 RED "TA T2: exits 0" '
raw_rep("DOPPLER_TOKEN=%s\\nDOPPLER_CONFIG_DIR=/tmp/.doppler\\nDOPPLER_ENABLE_VERSION_CHECK=false\\nDOPPLER_CONFIG=prd\\n\x27 \x27", "DOPPLER_TOKEN=%s\\nDOPPLER_ENABLE_VERSION_CHECK=false\\n\x27 \x27"); save()'
row G7-r5 PASS - '
ins_after("attempt=0", [": \"${SOLEUR_PU_UNSET_OK:-default}\""]); save()'

# ---- G8 --------------------------------------------------------------------------------------
row G8-r1 RED "G8: no reference to the retired /run/soleur-inngest-doppler.ok sentinel" '
ls = lines(); a = one(ISO_OPEN); f = one(ISO_FAILED); e = one("fi", after=f)
ls[a:e + 1] = [ind(a) + "test -f /run/soleur-inngest-doppler.ok || exit 1"]; put(ls); save()'
row G8-r2 RED "TA T3: isolation-check-FAILED (with iid), zero pulls" '
ls = lines(); a = one(ISO_OPEN); f = one(ISO_FAILED); e = one("fi", after=f)
blk = ls[a:e + 1]; del ls[a:e + 1]; put(ls)
ft = one("for zot_try in 1 2 3; do"); ls = lines(); dn = one("done", after=ft); ls[dn + 1:dn + 1] = blk; put(ls); save()'
row G8-r3 RED "G8 dispatch: exactly one isolation self-check site" '
ls = lines(); a = one("- path: /usr/local/bin/soleur-inngest-provision"); c = a + 1; assert ls[c].strip() == "content: |"
e = c + 1
while e < len(ls) and (ls[e].startswith("      ") or ls[e].strip() == ""): e += 1
ls[c + 1:e] = ["      #!/bin/sh", "      exit 0"]; put(ls); save()'
row G8-r4 RED "G8: the script keeps no verdict state" '
rep_line(ISO_OPEN, "if [ -f \"$STATE/iso.ok\" ] || doppler run --project soleur-inngest --config prd -- bash -s <<\x27CHKEOF\x27")
ins_after(ISO_PASSED, [": > \"$STATE/iso.ok\""]); save()'
row G8-r5 PASS - '
raw_rep("LUKS_ACTIVE_VOLUME_ID|HEARTBEAT_URL)|BETTERSTACK_LOGS_TOKEN)", "LUKS_ACTIVE_VOLUME_ID|NEW_ADMITTED_NAME|HEARTBEAT_URL)|BETTERSTACK_LOGS_TOKEN)"); save()'

# ---- review batch (PR #9159): widened detectors, each proven by a row --------------------------
row G1-r9 RED "G1: no runcmd or bootcmd item pulls an image" '
s = s.rstrip("\n") + "\n  - /usr/bin/docker pull \"$ZIREF\" || true\n"; save()'
row G1-r10 RED "G1: the pull is bounded by exactly \`timeout 180\`" '
rep_line("timeout 180 docker pull \"$ZIREF\" > /var/log/inngest-zot-pull.log 2>&1 &", "timeout 1800 docker pull \"$ZIREF\" > /var/log/inngest-zot-pull.log 2>&1 &"); save()'
row G1-r11 RED "G1: inngest-bootstrap.sh is invoked exactly once" '
b = one(BOOT_CALL); ins_after("boot_rc=$?", ["bash \"$EXTRACT_DIR/inngest-bootstrap.sh\" >/dev/null 2>&1 || true"], after=b); save()'
row G1-r12 RED "G1: the provision script carries exactly ONE image pull" '
ins_after("IREF=\"$ZIREF\"", ["docker create \"$ZIREF\" >/dev/null 2>&1 || true"]); save()'
row G1-r13 RED "G1: every write_files path is canonical and unique" '
ins_before("- path: /usr/local/bin/soleur-inngest-provision", ["- path: /usr/local/bin//soleur-inngest-provision", "  content: |", "    #!/bin/sh", "    exit 0", "  owner: root:root", "  permissions: \x270755\x27"]); save()'
row G2-r12 RED "TA Q1: busy" '
rep_line("[ \"$(systemctl is-active \"$_u\" 2>/dev/null)\" = activating ] && _busy=\"$_busy.$_u\"", "[ \"$(systemctl is-active \"$_u\" 2>/dev/null)\" = activatingX ] && _busy=\"$_busy.$_u\""); save()'
row G2-r13 RED "TA Q1: exits 1" '
f = one(Q_CLOSE); del_line("exit 1", after=f); save()'
row G2-r14 RED "TA Q2: busy" '
rep_line("for _u in inngest-cutover-flip.service inngest-luks-cutover.service; do", "for _u in inngest-cutover-flip.service; do"); save()'
row G2-r15 RED "TA Q1: the failed attempt restarts the flip timer" '
del_line("for _t in $_fsm_timers_stopped; do systemctl start \"$_t\" >/dev/null 2>&1; done"); save()'
row G2-r16 RED "G2: the iid derivation is byte-identical" '
raw_rep("IID=\"$( (cat /var/lib/cloud/data/instance-id 2>/dev/null || hostname) | LC_ALL=C tr -cd \x27A-Za-z0-9._-\x27)\"", "IID=\"$( (cat /var/lib/cloud/data/instance-id 2>/dev/null || hostname) | LC_ALL=C tr -cd \x27A-Za-z0-9._\x27)\""); save()'
row G3-r9 RED "G3: exactly one latch write site" '
a = one("on_exit() {"); ins_after("set +e", ["[ \"$rc\" -eq 124 ] && : | tee \"$LATCH\""], after=a); save()'
row G3-r10 RED "G3: exactly one latch write site" '
ins_after("/usr/local/bin/inngest-boot-phone-home.sh bootstrap-done-DEGRADED \"why=$_degraded attempt=$attempt iid=$IID\" || true", [": > \"$LATCH\""]); save()'
row G3-r11 RED "G3: exactly one latch write site" '
ins_before("exit \"$boot_rc\"", ["exec 3>\"$STATE\"/done"]); save()'
row G3-r12 RED "G3: exactly one latch write site" '
ins_before("exit \"$boot_rc\"", ["mkdir -p \"$LATCH\""]); save()'
row G3-r13 RED "G3: exactly one latch write site" '
ins_before("exit \"$boot_rc\"", ["true 2> \"$STATE/done\""]); save()'
row G5-r7 RED "G5: exactly one runcmd item starts the provision service" '
ins_before("- groupadd -f docker", ["- systemctl start soleur-inngest-provision"]); save()'
row G5-r8 RED "G5: exactly one runcmd item starts the provision service" '
ins_before("- groupadd -f docker", ["- systemctl add-wants multi-user.target soleur-inngest-provision.service"]); save()'
row G6-r11 RED "G6: no drop-in, shadow copy or runtime edit" '
ins_before("- path: /etc/systemd/system/soleur-inngest-provision.service", ["- path: /etc/systemd/system/soleur-inngest-provision.service.d/override.conf", "  content: |", "    [Service]", "    Restart=no", "  owner: root:root", "  permissions: \x270644\x27"]); save()'
row G6-r12 RED "G6: nothing in the script turns xtrace/verbose on" '
ls = lines(); j = [k for k, l in enumerate(ls) if l.strip().startswith("case \"$-\" in *x*)")]; assert len(j) == 1
ls[j[0] + 1:j[0] + 1] = [ind(j[0]) + "set -x"]; put(ls); save()'
row G6-r13 RED "G6: the service sets none of the directives" '
w = one("- path: /etc/systemd/system/soleur-inngest-provision.service"); ins_after("Type=oneshot", ["TimeoutSec=infinity"], after=w); save()'
row G6-r14 RED "G6: the timer triggers the provision service" '
ins_after("OnBootSec=90s", ["Unit=soleur-something-else.service"]); save()'
row G6-r15 RED "G6: nothing in the script turns xtrace/verbose on" '
a = one(ISO_OPEN); ins_after("set -euo pipefail", ["set -x"], after=a); save()'
row G6-r16 RED "G6: the restart delay backs off" '
del_line("RestartSteps=4"); save()'
row G8-r6 PASS - '
ins_after("attempt=0", [": $(( 1 << 2 ))", ": # a trailing comment that names <<NOTAHEREDOC"]); save()'

# ---- execute (bounded parallelism; each row owns its directory) --------------------------------
echo ""
echo "--- Guard Contract rows (${#ROW_IDS[@]} defined) ---"
JOBS="$(nproc 2>/dev/null || echo 4)"; [ "$JOBS" -gt 8 ] && JOBS=8
for id in "${ROW_IDS[@]}"; do
  while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do wait -n 2>/dev/null || true; done
  row_exec "$id" "${ROW_KIND[$id]}" "${ROW_EXPECT[$id]}" "${ROW_MUT[$id]}" "${ROW_HARN[$id]}" &
done
wait

EXEC=0; NRED=0; NPASS=0; BAD=()
for id in "${ROW_IDS[@]}"; do
  res="$ROWS_DIR/$id.res"
  if [ ! -s "$res" ]; then echo "  NOT EXECUTED: $id"; BAD+=("$id"); continue; fi
  line="$(cat "$res")"
  case "$line" in
    ABORT*) echo "  HARNESS ABORT: ${line#ABORT }"; BAD+=("$id"); continue ;;
  esac
  EXEC=$((EXEC + 1))
  [ "${ROW_KIND[$id]}" = RED ] && NRED=$((NRED + 1)) || NPASS=$((NPASS + 1))
  case "$line" in
    KILLED*|HELD*) echo "  ${line%% *}: ${line#* }" ;;
    *) echo "  ${line%% *}: ${line#* }"; BAD+=("$id")
       sed -n '/^  \(FAIL\|FAULT\):/p' "$ROWS_DIR/$id/guard.log" 2>/dev/null | head -5 | sed 's/^/      /' ;;
  esac
done
echo ""
echo "  ROWS executed=$EXEC (RED $NRED, must-PASS $NPASS) of matrix $EXPECTED_ROWS ($EXPECTED_RED RED, $EXPECTED_MUSTPASS must-PASS)"
ROWS_OK=1
if [ "$EXEC" -ne "$EXPECTED_ROWS" ] || [ "$NRED" -ne "$EXPECTED_RED" ] || [ "$NPASS" -ne "$EXPECTED_MUSTPASS" ]; then
  echo "  FAIL: executed row count does not equal the Guard Contract matrix (a row was skipped, deleted or aborted)"
  ROWS_OK=0
fi
if [ "${#BAD[@]}" -gt 0 ]; then
  echo "  FAIL: ${#BAD[@]} row(s) not KILLED/HELD: ${BAD[*]}"
  ROWS_OK=0
fi

# =================================================================================================
# Tier B — systemd 255 as PID 1 (T6, T9, T10, T11, T12, T15 in one logged run).
# =================================================================================================
echo ""
echo "--- Tier B: systemd as PID 1 in the pinned ubuntu:24.04 image ---"
TIERB_RESULT=""
TB_FAIL=0
tb_skip() { echo "  SKIP (Tier B): $1"; TIERB_RESULT="skipped: $1"; }
# An unbootable systemd container is a named SKIP on a developer machine and a FAIL under CI: the
# runner is contracted to supply docker that can boot systemd, and a silent skip there would drop
# the only real-systemd evidence. (The apt archive decline stays an ADR-188 arm_skip in both.)
tb_unbootable() {
  if [ -n "${CI:-}" ]; then echo "  FAIL: Tier B: unbootable systemd container under CI: $1"; TB_FAIL=$((TB_FAIL + 1)); TIERB_RESULT="FAIL: unbootable: $1"
  else tb_skip "unbootable systemd container: $1"; fi
}
tb_ok() { if [ "$1" -eq 0 ]; then echo "  PASS: $2"; else echo "  FAIL: $2"; TB_FAIL=$((TB_FAIL + 1)); fi; }
# Bounded apt (#9395): the image build shares lib/apt-bounded.sh with the git-data suites (one budget of apt
# seconds, expiry routed to FIXTURE_APT_FAILED + exit 100). Healthy cost measured in the pinned image on
# 2026-10-08: update 8 s + install 12 s = 20 s; 150 s fits one 90 s-capped stall plus a healthy retry.
APT_LIB="${SCRIPT_DIR}/lib/apt-bounded.sh"
APT_BUDGET_S=150
[ -r "$APT_LIB" ] || die "${APT_LIB} is missing — the Tier B apt cycle could not be bounded"
# shellcheck source=lib/apt-bounded.sh
. "$APT_LIB"
# Verdict for the image-build `docker run`: ok | skip | fail. Only the apt decline (the marker WITH the helper's
# own rc 100) or docker failing to create the container (125) is the ADR-188 skip; 97/98/124/126/127/137 are
# harness defects and must never read as the decline. Executed below as an instrument check, docker or not.
tb_build_verdict() {
  local rc="$1" log="$2"
  if [ "$rc" -eq 0 ]; then echo ok
  elif [ "$rc" -eq 100 ] && grep -qx FIXTURE_APT_FAILED "$log"; then echo skip
  elif [ "$rc" -eq 125 ]; then echo skip
  else echo fail; fi
}
_vm="$W/verdict-marker.log"; _ve="$W/verdict-empty.log"
printf 'FIXTURE_APT_CAUSE: x\nFIXTURE_APT_FAILED\n' > "$_vm"; : > "$_ve"
_vchk() { [ "$(tb_build_verdict "$1" "$2")" = "$3" ] || die "tb_build_verdict $1 $(basename "$2") != $3"; }
_vchk 0 "$_vm" ok;    _vchk 0 "$_ve" ok;     _vchk 100 "$_vm" skip; _vchk 125 "$_ve" skip
_vchk 137 "$_vm" fail; _vchk 97 "$_vm" fail;  _vchk 100 "$_ve" fail; _vchk 124 "$_ve" fail
_vchk 98 "$_ve" fail;  _vchk 126 "$_ve" fail; _vchk 127 "$_ve" fail

tierb() {
  local img_tag ctr="pu-tierb-$$" x rc
  if [ "${PU_TIERB:-1}" = 0 ]; then
    [ -n "${CI:-}" ] && { echo "  FAIL: PU_TIERB=0 is refused under CI"; TB_FAIL=1; return; }
    tb_skip "PU_TIERB=0 (operator opt-out, local only)"; return
  fi
  if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    if [ -n "${CI:-}" ]; then echo "  FAIL: docker is absent under CI (the runner is contracted to supply it)"; TB_FAIL=1; return; fi
    tb_skip "docker absent or unreachable (local host)"; return
  fi
  img_tag="soleur-pu-tierb:$(printf '%s systemd systemd-sysv dbus jq v1' "$UBUNTU_BASE" | sha256sum | cut -c1-12)"
  TIERB_CTR="$ctr"
  if ! docker image inspect "$img_tag" >/dev/null 2>&1; then
    docker rm -f "$ctr-build" >/dev/null 2>&1
    gd_apt_state_arm "$W/aptstate" "$APT_BUDGET_S" || { echo "FIXTURE-FAIL: the shared apt budget could not be armed" >&2; exit 2; }
    # shellcheck disable=SC2016  # single-quoted on purpose: the script expands inside the container
    docker run --name "$ctr-build" -v "$GD_APT_STATE:/work/apt" "$UBUNTU_BASE" bash -c '
      export DEBIAN_FRONTEND=noninteractive
      . /work/apt/apt-bounded.sh || exit 97
      gd_apt_install_bounded --no-install-recommends systemd systemd-sysv dbus jq || exit $?
    ' > "$W/tierb-apt.log" 2>&1
    rc=$?
    gd_apt_state_summary
    if [ "$rc" -ne 0 ]; then
      docker rm -f "$ctr-build" >/dev/null 2>&1
      if [ "$(tb_build_verdict "$rc" "$W/tierb-apt.log")" = skip ]; then
        if [ "$rc" -eq 125 ]; then
          tb_skip "ADR-188 arm_skip: docker could not create the image-build container (rc=125: $(tail -n 2 "$W/tierb-apt.log" | tr '\n' ' ' | head -c 200))"
        else
          tb_skip "ADR-188 arm_skip: the ubuntu apt archive did not serve systemd/jq ($(grep -a FIXTURE_APT_CAUSE "$W/tierb-apt.log" | tail -1 | head -c 200))"
        fi
        return
      fi
      echo "  FAIL: Tier B: image build failed rc=$rc, not the apt decline ($(tail -n 2 "$W/tierb-apt.log" | tr '\n' ' ' | head -c 300))"
      TB_FAIL=$((TB_FAIL + 1)); TIERB_RESULT="FAIL: image build rc=$rc"; return
    fi
    docker commit "$ctr-build" "$img_tag" >/dev/null && docker rm "$ctr-build" >/dev/null
  fi
  TIERB_CTR="$ctr"
  docker run -d --name "$ctr" --privileged --cgroupns=private --cgroup-parent=docker.slice \
    --tmpfs /run --tmpfs /run/lock --tmpfs /tmp "$img_tag" /lib/systemd/systemd > /dev/null 2>"$W/tierb-run.err" \
    || { tb_unbootable "docker run failed ($(head -c 160 "$W/tierb-run.err"))"; return; }
  X() { docker exec "$ctr" "$@"; }
  XS() { docker exec "$ctr" sh -c "$1"; }
  wait_boot() {
    local s
    for _ in $(seq 1 60); do
      s="$(X systemctl is-active multi-user.target 2>/dev/null)"; [ "$s" = active ] && return 0; sleep 1
    done
    return 1
  }
  wait_boot || { tb_unbootable "multi-user.target not active within 60s"; return; }
  echo "  booted: $(X systemctl --version | head -1) as PID 1 ($(X cat /proc/1/comm))"
  X systemctl mask --now systemd-resolved.service getty@.service console-getty.service >/dev/null 2>&1

  # ---- install: the RENDERED unit, timer and script; stubs; the executed-write fixtures ---------
  docker cp "$W/c0/unit.service" "$ctr:/etc/systemd/system/soleur-inngest-provision.service"
  docker cp "$W/c0/unit.timer" "$ctr:/etc/systemd/system/soleur-inngest-provision.timer"
  docker cp "$W/c0/script.sh" "$ctr:/usr/local/bin/soleur-inngest-provision"
  docker cp "$W/c0/inngest-doppler.fixture" "$ctr:/etc/default/inngest-doppler"
  docker cp "$W/c0/fx/etc/soleur-zot-read" "$ctr:/etc/default/soleur-zot-read"
  X chmod 0755 /usr/local/bin/soleur-inngest-provision
  XS 'mkdir -p /var/lib/tierb/ctl /var/lib/cloud/data /etc/systemd/system/soleur-inngest-provision.service.d /etc/systemd/system/soleur-inngest-provision.timer.d && echo i-tierb > /var/lib/cloud/data/instance-id && chmod 600 /etc/default/inngest-doppler /etc/default/soleur-zot-read'
  local stub
  for stub in docker doppler inngest-boot-phone-home.sh soleur-boot-emit inngest-redact.sh inngest-bs-token-restage.sh ip soleur-inngest-nic-wait; do
    case "$stub" in
      docker) cat > "$W/tb-$stub" <<'STUB'
#!/bin/sh
L=/var/lib/tierb/calls.log; C=/var/lib/tierb/ctl
printf '%s docker %s\n' "$(date +%s.%N)" "$*" >> "$L"
case "$1" in
  info|login|rm) exit 0 ;;
  pull)
    n=$(cat "$C/pulls.n" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$C/pulls.n"
    i=0; r=0; for r in $(cat "$C/pull_rc" 2>/dev/null || echo 0); do i=$((i + 1)); [ "$i" -ge "$n" ] && break; done
    [ -f "$C/t15" ] && systemctl start --no-block inngest-cutover-flip.service
    exit "$r" ;;
  create) echo tierbcid; exit 0 ;;
  cp)
    case "$2" in
      *:/inngest-bootstrap.sh) cat > "$3" <<'BOOT'
#!/bin/bash
L=/var/lib/tierb/calls.log
printf '%s bootstrap start\n' "$(date +%s.%N)" >> "$L"
printf '[Unit]\nDescription=Tier B stand-in\n[Service]\nExecStart=/bin/true --postgres-max-open-conns 5\n' > /etc/systemd/system/inngest-server.service
s=$(cat /var/lib/tierb/ctl/boot_sleep 2>/dev/null || echo 0); [ "$s" -gt 0 ] && /bin/sleep "$s"
printf '%s bootstrap end\n' "$(date +%s.%N)" >> "$L"
exit 0
BOOT
        exit 0 ;;
      *) printf 'asset\n' > "$3"; exit 0 ;;
    esac ;;
  inspect) printf 'INNGEST_CLI_VERSION=1.2.3\n'; exit 0 ;;
esac
exit 0
STUB
      ;;
      doppler) cat > "$W/tb-$stub" <<'STUB'
#!/bin/sh
L=/var/lib/tierb/calls.log
printf '%s doppler %s TOKEN=%s HOME=%s\n' "$(date +%s.%N)" "$1" "${DOPPLER_TOKEN:-unset}" "${HOME:-unset}" >> "$L"
case "$1" in
  run) while [ "$#" -gt 0 ] && [ "$1" != -- ]; do shift; done; shift; exec "$@" ;;
  secrets) [ "$2" = --only-names ] && printf '{"INNGEST_SIGNING_KEY":{},"INNGEST_EVENT_KEY":{},"INNGEST_REDIS_PASSWORD":{},"INNGEST_POSTGRES_URI":{},"BETTERSTACK_LOGS_TOKEN":{}}\n' ;;
esac
exit 0
STUB
      ;;
      inngest-boot-phone-home.sh) printf '#!/bin/sh\nprintf "%%s phone %%s\\n" "$(date +%%s.%%N)" "$*" >> /var/lib/tierb/calls.log\nexit 0\n' > "$W/tb-$stub" ;;
      soleur-boot-emit) printf '#!/bin/sh\nprintf "%%s emit %%s\\n" "$(date +%%s.%%N)" "$*" >> /var/lib/tierb/calls.log\nexit 0\n' > "$W/tb-$stub" ;;
      inngest-redact.sh) printf '#!/bin/sh\ncat\n' > "$W/tb-$stub" ;;
      ip) printf '#!/bin/sh\nprintf "3: enp7s0    inet 10.0.1.40/32 scope global enp7s0\\n"\n' > "$W/tb-$stub" ;;
      soleur-inngest-nic-wait) printf '#!/bin/sh\nexit 0\n' > "$W/tb-$stub" ;;
      inngest-bs-token-restage.sh) printf '#!/bin/sh\nprintf tok > /run/inngest-bs-logs-token\nexit 0\n' > "$W/tb-$stub" ;;
    esac
    docker cp "$W/tb-$stub" "$ctr:/usr/local/bin/$stub"; X chmod 0755 "/usr/local/bin/$stub"
  done
  printf '#!/bin/sh\nprintf "%%s flip-start\\n" "$(date +%%s.%%N)" >> /var/lib/tierb/calls.log\n/bin/sleep 20\nprintf "%%s flip-end\\n" "$(date +%%s.%%N)" >> /var/lib/tierb/calls.log\n' > "$W/tb-flip"
  docker cp "$W/tb-flip" "$ctr:/usr/local/sbin/tierb-flip-stub"; X chmod 0755 /usr/local/sbin/tierb-flip-stub
  printf '[Unit]\nDescription=Tier B stand-in for the cutover flip FSM step\n[Service]\nType=oneshot\nExecStart=/usr/local/sbin/tierb-flip-stub\n' > "$W/tb-flip.service"
  docker cp "$W/tb-flip.service" "$ctr:/etc/systemd/system/inngest-cutover-flip.service"
  # A stand-in inngest-redis.service, ENABLED so it is active after every reboot: the script's
  # degraded-success check requires Redis active before it latches.
  printf '[Unit]\nDescription=Tier B stand-in for inngest-redis\n[Service]\nType=oneshot\nRemainAfterExit=yes\nExecStart=/bin/true\n[Install]\nWantedBy=multi-user.target\n' > "$W/tb-redis.service"
  docker cp "$W/tb-redis.service" "$ctr:/etc/systemd/system/inngest-redis.service"
  # Test-only drop-ins: `sh -u` (G7 under real systemd), a short RestartSec with the back-off
  # disabled (RestartSteps=0, so every retry is 2 s — the production 120 s -> 15 min ladder is
  # pinned statically by G6), and a short timer OnBootSec.
  printf '[Service]\nExecStart=\nExecStart=/bin/sh -u /usr/local/bin/soleur-inngest-provision\nRestartSec=2s\nRestartSteps=0\n' > "$W/tb-10.conf"
  docker cp "$W/tb-10.conf" "$ctr:/etc/systemd/system/soleur-inngest-provision.service.d/10-tierb.conf"
  printf '[Timer]\nOnBootSec=\nOnBootSec=2s\n' > "$W/tb-t.conf"
  docker cp "$W/tb-t.conf" "$ctr:/etc/systemd/system/soleur-inngest-provision.timer.d/10-tierb.conf"
  XS 'printf tok > /run/inngest-bs-logs-token; : > /var/lib/tierb/calls.log'
  X systemctl daemon-reload
  X systemctl enable --now inngest-redis.service >/dev/null 2>&1

  LOGF=/var/lib/tierb/calls.log
  mark() { XS "echo \"\$(date +%s.%N) PHASE $1\" >> $LOGF"; }
  lines_from() { XS "awk -v m='PHASE $1' 'f; \$2 == \"PHASE\" && \$0 ~ m\"\$\" {f=1}' $LOGF"; }
  poll() { # poll <seconds> <shell condition run in container>
    local _; for _ in $(seq 1 $(( $1 * 2 ))); do XS "$2" >/dev/null 2>&1 && return 0; sleep 0.5; done; return 1
  }
  reset_state() { X systemctl stop soleur-inngest-provision.service soleur-inngest-provision.timer >/dev/null 2>&1; X systemctl reset-failed soleur-inngest-provision.service >/dev/null 2>&1; XS 'rm -f /var/lib/soleur-inngest-provision/done /var/lib/soleur-inngest-provision/attempts /var/lib/tierb/ctl/*'; }

  # ---- T12 + T6: the rendered arming items run after the timer's OnBootSec has elapsed ---------
  # The timer's (drop-in) OnBootSec=2s must already have ELAPSED when the arming runs: that is the
  # case where `enable --now` would be a hidden second trigger. (docker cp cannot write into the
  # tmpfs mounts, so every file handed to the container goes under /var/lib/tierb or /etc.)
  poll 30 'awk "{exit !(\$1 >= 6)}" /proc/uptime'
  mark T12
  printf '%s\n' "set +e" > "$W/tb-arm.sh"; cat "$W/c0/arming.sh" >> "$W/tb-arm.sh"
  docker cp "$W/tb-arm.sh" "$ctr:/var/lib/tierb/arm.sh"
  XS 'echo 0 > /var/lib/tierb/ctl/pull_rc; sh /var/lib/tierb/arm.sh >/var/lib/tierb/arm.out 2>&1'
  poll 40 '[ "$(systemctl show -p SubState --value soleur-inngest-provision.service)" = exited ]'
  sleep 2
  x="$(lines_from T12)"
  tb_ok "$( [ "$(grep -c ' phone provision-attempt-start attempt=1 ' <<<"$x")" = 1 ] && [ "$(grep -c ' phone provision-attempt-start ' <<<"$x")" = 1 ] && echo 0 || echo 1)" "T12: exactly one provision-attempt-start attempt=1 after arming (a single first-boot trigger)"
  tb_ok "$( [ "$(X systemctl is-active soleur-inngest-provision.timer)" = inactive ] && [ "$(X systemctl is-enabled soleur-inngest-provision.timer)" = enabled ] && echo 0 || echo 1)" "T12: the timer is enabled but NOT active (armed without --now)"
  tb_ok "$(grep -q ' phone provision-unit-armed ' <<<"$x" && echo 0 || echo 1)" "T12: provision-unit-armed is emitted by the rendered arming items"
  tb_ok "$( [ "$(grep -c ' doppler ' <<<"$x")" -ge 2 ] && ! grep -vq "TOKEN=$(sed -n 's/^DOPPLER_TOKEN=//p' "$W/c0/inngest-doppler.fixture") HOME=/root$" < <(grep ' doppler ' <<<"$x") && echo 0 || echo 1)" "T6: every doppler call received DOPPLER_TOKEN and HOME=/root through real EnvironmentFile= parsing"
  tb_ok "$(X test -e /var/lib/soleur-inngest-provision/done && echo 0 || echo 1)" "T12: the attempt latched"

  # ---- T9: TimeoutStartSec kill -> the TERM trap reports before SIGKILL, then attempt N+1 ------
  reset_state; mark T9
  printf '[Service]\nTimeoutStartSec=5s\n' > "$W/tb-20.conf"; docker cp "$W/tb-20.conf" "$ctr:/etc/systemd/system/soleur-inngest-provision.service.d/20-t9.conf"
  X systemctl daemon-reload
  XS 'echo 0 > /var/lib/tierb/ctl/pull_rc; echo 60 > /var/lib/tierb/ctl/boot_sleep'
  X systemctl start --no-block soleur-inngest-provision.service
  # Restart witness: any attempt>=2 row on either channel, or a SECOND bootstrap
  # start (provision-attempt-start is phone-only — the same loss-prone channel as
  # the exit evidence — so a lost start row must not stall the wait while the
  # restart's own bootstrap/exit rows are already in the log). Phase-scoped.
  poll 90 "awk 'f; \$2==\"PHASE\" && \$3==\"T9\" {f=1}' $LOGF | awk '\$2==\"bootstrap\" && \$3==\"start\" {b++} \$2==\"phone\" && \$3 ~ /^provision-attempt-(start|exit)-[0-9]+\$/ && \$4 ~ /^attempt=[0-9]+\$/ && \$4 != \"attempt=1\" {n=1} \$2==\"emit\" && \$3==\"provision_attempt_failed\" && \$5 ~ /attempt=[0-9]+\./ && \$5 !~ /attempt=1\./ {n=1} END {exit !(n || b >= 2)}'"
  x="$(lines_from T9)"
  # The kill report travels on TWO channels out of on_exit(): the phone row
  # (provision-attempt-exit-143) and the emit row (provision_attempt_failed, whose
  # $5 is the fixed-shape `rc=…` detail). Under runner load either single row can
  # be lost, so the assertions read whichever attempt=1 evidence landed — and still
  # red when NEITHER did. Matchers anchor on attempt=1 because exit-143 rows appear
  # again for attempt>=2 (its own 5s kill, or a later phase's teardown).
  local t9_via t9_pos t9_x t9_b t9_bk t9_s t9_sk
  {
    IFS= read -r t9_via; IFS= read -r t9_pos; IFS= read -r t9_x
    IFS= read -r t9_b;  IFS= read -r t9_bk
    IFS= read -r t9_s;  IFS= read -r t9_sk
  } <<< "$(awk '
    $2 == "bootstrap" && $3 == "start"                                                  { bs = $1 }
    $2 == "phone" && $3 == "provision-attempt-start" && $4 == "attempt=1" && t1 == ""   { t1 = $1 }
    $2 == "phone" && $3 == "provision-attempt-start" && $4 ~ /^attempt=[0-9]+$/ && $4 != "attempt=1" && s == "" { s = NR }
    $2 == "phone" && $3 == "provision-attempt-exit-143" && $4 == "attempt=1"            { if (e == "") { e = NR; t = $1; fb = bs } ph = 1 }
    $2 == "emit"  && $3 == "provision_attempt_failed" && $5 ~ /^rc=143\.attempt=1\./    { if (e == "") { e = NR; t = $1; fb = bs } em = 1 }
    e != "" && NR > e && s2 == "" && $2 == "bootstrap" && $3 == "start"                 { s2 = NR }
    e != "" && NR > e && s2 == "" && $2 == "phone" && $3 ~ /^provision-attempt-(start|exit)-[0-9]+$/ && $4 ~ /^attempt=[0-9]+$/ && $4 != "attempt=1" { s2 = NR }
    e != "" && NR > e && s2 == "" && $2 == "emit" && $3 == "provision_attempt_failed" && $5 ~ /attempt=[0-9]+\./ && $5 !~ /attempt=1\./ { s2 = NR }
    END {
      print (ph && em ? "both" : ph ? "phone" : em ? "emit" : "none")
      print e
      print t
      print (t1 != "" ? t1 : (e != "" && fb != "" ? fb : ""))
      print (t1 != "" ? "attempt-start" : (e != "" && fb != "" ? "bootstrap" : ""))
      print (s != "" ? s : s2)
      print (s != "" ? "attempt-start" : (s2 != "" ? "restart-evidence" : ""))
    }' <<<"$x")"
  tb_ok "$( [ -n "$t9_b" ] && [ -n "$t9_x" ] && awk -v b="$t9_b" -v e="$t9_x" 'BEGIN { d = e - b; exit !(d >= 0 && d <= 15) }' && echo 0 || echo 1)" "T9: the start-timeout kill reports rc=143 for attempt=1 within 15s of the attempt's start (via=$t9_via, anchor=${t9_bk:-none}@${t9_b:-none}, evidence=${t9_x:-none}) — well before the 90s SIGKILL"
  tb_ok "$( [ -n "$t9_pos" ] && [ -n "$t9_s" ] && [ "$t9_pos" -lt "$t9_s" ] && echo 0 || echo 1)" "T9: the attempt=1 exit evidence precedes the next attempt's evidence (via=$t9_via, evidence_row=${t9_pos:-none}, restart_row=${t9_s:-none}/${t9_sk:-none})"
  X rm -f /etc/systemd/system/soleur-inngest-provision.service.d/20-t9.conf; X systemctl daemon-reload

  # ---- T15: the cutover-FSM quiesce waits for an in-flight flip step; a bounded wait gives up --
  reset_state; mark T15
  XS 'echo 0 > /var/lib/tierb/ctl/pull_rc; : > /var/lib/tierb/ctl/t15'
  X systemctl start --no-block soleur-inngest-provision.service
  poll 60 '[ "$(systemctl show -p SubState --value soleur-inngest-provision.service)" = exited ]'
  x="$(lines_from T15)"
  tb_ok "$(awk '$2 == "flip-end" {f=NR} $2 == "bootstrap" && $3 == "start" {b=NR} END {exit !(f && b && f < b)}' <<<"$x" && echo 0 || echo 1)" "T15: the bootstrap starts only after the activating flip step finishes"
  reset_state; X systemctl stop inngest-cutover-flip.service >/dev/null 2>&1; mark T15b
  printf '#!/bin/sh\nexec /bin/sleep 0.05\n' > "$W/tb-fastsleep"; docker cp "$W/tb-fastsleep" "$ctr:/usr/local/bin/sleep"; X chmod 0755 /usr/local/bin/sleep
  XS 'echo 0 > /var/lib/tierb/ctl/pull_rc; : > /var/lib/tierb/ctl/t15'
  X systemctl start --no-block soleur-inngest-provision.service
  poll 40 "grep -q ' phone provision-attempt-exit-1 ' $LOGF"
  x="$(lines_from T15b)"
  tb_ok "$(grep -q ' phone provision-fsm-busy ' <<<"$x" && grep -q ' phone provision-attempt-exit-1 ' <<<"$x" && ! grep -q ' bootstrap start' <<<"$x" && echo 0 || echo 1)" "T15: with the wait bound shortened, the attempt exits 1 with provision-fsm-busy and never starts the bootstrap"
  X rm -f /usr/local/bin/sleep; reset_state; X systemctl stop inngest-cutover-flip.service >/dev/null 2>&1

  # ---- T11a: reboot with NO latch — the timer re-enters, multi-user.target does not wait --------
  mark T11a
  XS 'echo 1 > /var/lib/tierb/ctl/pull_rc'
  docker restart "$ctr" >/dev/null
  wait_boot || { echo "  FAIL: T11 container did not come back"; TB_FAIL=$((TB_FAIL + 1)); return; }
  local t11_up; t11_up="$(date +%s.%N)"
  XS 'printf tok > /run/inngest-bs-logs-token'
  poll 20 "grep -q ' phone provision-attempt-exit-1 ' < <(awk 'f; \$2 == \"PHASE\" && \$3 == \"T11a\" {f=1}' $LOGF)"
  x="$(lines_from T11a)"
  local t11_s; t11_s="$(awk '$2 == "phone" && $3 == "provision-attempt-start" {print $1; exit}' <<<"$x")"
  tb_ok "$( [ -n "$t11_s" ] && awk -v s="$t11_s" -v u="$t11_up" 'BEGIN { exit !((s - u) <= 15) }' && echo 0 || echo 1)" "T11: after a reboot with no latch the timer starts the unit within 15s of multi-user.target (up $t11_up, start ${t11_s:-none})"
  if ! grep -q ' phone provision-attempt-start ' <<<"$x"; then
    { X systemctl list-jobs --no-pager; X systemctl status --no-pager -n 30 soleur-inngest-provision.service soleur-inngest-provision.timer; X systemd-analyze blame --no-pager 2>/dev/null | head -5; } 2>&1 | sed 's/^/    diag| /'
  fi
  local st; st="$(X systemctl show -p ActiveState -p SubState --value soleur-inngest-provision.service | tr '\n' ' ')"
  tb_ok "$( [ "$(X systemctl is-active multi-user.target)" = active ] && case "$st" in *activating*|*auto-restart*|*failed*) true ;; *) false ;; esac && echo 0 || echo 1)" "T11: multi-user.target is active while the unit is still retrying (unit: $st) — no [Install] ordering"
  reset_state

  # ---- T10: the ladder — two misses then a hit; an injected timer start adds no attempt --------
  mark T10
  # Pull outcomes are per `docker pull` CALL and one attempt makes up to 3 tries, so "two failed
  # attempts, then a success" is six failing pulls and then a served one.
  XS 'echo "1 1 1 1 1 1 0" > /var/lib/tierb/ctl/pull_rc'
  X systemctl start --no-block soleur-inngest-provision.service
  poll 40 "grep -q ' phone provision-attempt-exit-1 ' < <(awk 'f; \$2 == \"PHASE\" && \$3 == \"T10\" {f=1}' $LOGF)"
  X systemctl start soleur-inngest-provision.timer >/dev/null 2>&1
  poll 90 '[ "$(systemctl show -p SubState --value soleur-inngest-provision.service)" = exited ]'
  x="$(lines_from T10)"
  local nr; nr="$(X systemctl show -p NRestarts --value soleur-inngest-provision.service)"
  tb_ok "$( [ "$nr" = 2 ] && [ "$(X systemctl show -p ActiveState --value soleur-inngest-provision.service)" = active ] && echo 0 || echo 1)" "T10: NRestarts=2 and active (exited) after two misses (NRestarts=$nr)"
  tb_ok "$( [ "$(grep -c ' phone provision-attempt-start ' <<<"$x")" = 3 ] && echo 0 || echo 1)" "T10: exactly 3 attempts — the timer start injected during the restart wait added none ($(grep -c ' phone provision-attempt-start ' <<<"$x"))"
  tb_ok "$(X test -e /var/lib/soleur-inngest-provision/done && echo 0 || echo 1)" "T10: the latch is present after the ladder"
  X systemctl stop soleur-inngest-provision.timer >/dev/null 2>&1

  # ---- T11b: reboot WITH the latch T10 wrote — condition-skipped, zero attempts ---------------
  mark T11b
  docker restart "$ctr" >/dev/null
  wait_boot || { echo "  FAIL: T11b container did not come back"; TB_FAIL=$((TB_FAIL + 1)); return; }
  sleep 12
  x="$(lines_from T11b)"
  tb_ok "$( [ "$(grep -c ' phone provision-attempt-start ' <<<"$x")" = 0 ] && [ "$(X systemctl show -p ConditionResult --value soleur-inngest-provision.service)" = no ] && echo 0 || echo 1)" "T11: after a reboot WITH the latch the unit is condition-skipped and emits zero attempts (ConditionResult=$(X systemctl show -p ConditionResult --value soleur-inngest-provision.service))"

  echo "  --- Tier B call log (timestamped) ---"
  XS "cat $LOGF" | sed 's/^/    /'
  if [ "$TB_FAIL" -eq 0 ]; then TIERB_RESULT="ran: T6 T9 T10 T11 T12 T15 all PASS"; else TIERB_RESULT="ran: $TB_FAIL FAIL"; fi
}
tierb
[ -n "$TIERB_RESULT" ] || TIERB_RESULT="ran: $TB_FAIL FAIL"

# =================================================================================================
echo ""
echo "=== Summary ==="
echo "  render: ${STORED_BYTES} B stored (cap 32768)"
echo "  C0: $C0_PASS assertions PASS"
echo "  systemd-analyze verify: $VERIFY_RESULT"
echo "  rows: executed=$EXEC/$EXPECTED_ROWS (RED $NRED/$EXPECTED_RED, must-PASS $NPASS/$EXPECTED_MUSTPASS), bad=${#BAD[@]}"
echo "  Tier B: $TIERB_RESULT"
if [ "$ROWS_OK" -ne 1 ] || [ "$TB_FAIL" -ne 0 ]; then
  echo "FAIL"
  exit 1
fi
echo "PROVISION_UNIT_SUITE_OK rows=$EXEC tierb=$([ "${TIERB_RESULT#ran}" != "$TIERB_RESULT" ] && echo ran || echo skipped)"
