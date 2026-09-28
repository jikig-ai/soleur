#!/usr/bin/env bash
# Guard suite for #8562: the dedicated inngest host provisions through a LATCHED, RETRYING systemd
# unit (soleur-inngest-provision.service + .timer), not through a once-per-instance runcmd item.
#
# WHAT IS GUARDED. The plan's `## Guard Contract` (8 guards, 59 rows: 51 RED + 8 must-PASS),
# knowledge-base/project/plans/2026-09-28-fix-inngest-bootstrap-pull-retrying-unit-plan.md.
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
#           systemctl/sync and the three emitters. NEVER skips. Exact return codes; rc 127, or
#           rc 2 without `parameter not set`, is an INSTRUMENT FAULT and fails loudly.
#   Tier B  systemd 255 as PID 1 in the pinned ubuntu:24.04 image: the real retry, latch, timer,
#           TimeoutStartSec kill and EnvironmentFile parsing (T6, T9, T10, T11, T12, T15) in one
#           logged run. Skips only with a named reason (docker absent off-CI, the apt archive,
#           an unbootable systemd container). Every Tier B property ALSO has a static or Tier A
#           detector in the row matrix, so a skipped Tier B loses no RED row.
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
SRC="$SCRIPT_DIR/cloud-init-inngest.yml"
BUDGET="$SCRIPT_DIR/inngest-userdata-budget.sh"
EXPECTED_ROWS=59
EXPECTED_RED=51
EXPECTED_MUSTPASS=8

die() { printf 'INSTRUMENT FAULT: %s\n' "$*" >&2; exit 2; }

for _t in python3 terraform dash jq sha256sum; do
  command -v "$_t" >/dev/null 2>&1 || die "$_t is required (Tier A never skips; the render needs terraform)"
done
python3 -c 'import yaml' 2>/dev/null || die "python3 yaml module is required"
DASH="$(command -v dash)"

W="$(mktemp -d -t provision-unit-XXXXXX)" || die "mktemp -d failed"
case "$W" in /*/provision-unit-*) : ;; *) die "scratch dir $W is not an absolute mktemp path" ;; esac
TIERB_CTR=""
cleanup() {
  [ -n "$TIERB_CTR" ] && docker rm -f "$TIERB_CTR" >/dev/null 2>&1
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
head -1 "$PRISTINE" | grep -qx '#cloud-config' || { echo "  FAIL: the stripped render does not start with #cloud-config"; exit 1; }
STORED_BYTES="$(sed -n 's/^  stored (b64gzip): \([0-9]*\) B$/\1/p' "$BUDGET_LOG")"
[ -n "$STORED_BYTES" ] && [ "$STORED_BYTES" -le 32768 ] || { echo "  FAIL: stored payload ${STORED_BYTES:-unknown} B is not <= 32768"; exit 1; }
echo "  PASS: render starts with #cloud-config and stores ${STORED_BYTES} B <= 32768 B"

# =================================================================================================
# The python half: extraction, rewrite, and the static guards. One file, subcommands.
# =================================================================================================
PY="$W/pu.py"
cat > "$PY" <<'PYEOF'
import hashlib, json, os, re, sys, yaml

SCRIPT_PATH = "/usr/local/bin/soleur-inngest-provision"
SVC_PATH = "/etc/systemd/system/soleur-inngest-provision.service"
TMR_PATH = "/etc/systemd/system/soleur-inngest-provision.timer"
STATE_DIR = "/var/lib/soleur-inngest-provision"
LATCH = STATE_DIR + "/done"
ENVFILE = "/etc/default/inngest-doppler"
PULL = re.compile(r"(^|[\s;|&(`])docker\s+(--config\s+\S+\s+)?(image\s+|container\s+)?pull(\s|$)")
LOGIN = re.compile(r"(^|[\s;|&(`])docker\s+(--config\s+\S+\s+)?login(\s|$)")

def load(p):
    raw = open(p, "rb").read()
    try:
        d = yaml.safe_load(raw) or {}
    except Exception:
        d = {}
    if not isinstance(d, dict):
        d = {}
    return raw, d

def wf_map(d):
    out = {}
    for w in d.get("write_files") or []:
        if isinstance(w, dict) and w.get("path"):
            out.setdefault(str(w["path"]), []).append(w)
    return out

def items(d):
    rc = d.get("runcmd") or []
    return [(" ".join(str(y) for y in x) if isinstance(x, list) else str(x)) for x in rc]

def code_lines(text):
    """(lineno, stripped) for shell code lines: comments dropped, heredoc bodies dropped."""
    out, hd = [], None
    for i, l in enumerate(text.split("\n")):
        s = l.strip()
        if hd is not None:
            if s == hd:
                hd = None
            continue
        if not s or (s.startswith("#") and not s.startswith("#!")):
            continue
        out.append((i, s))
        m = re.search(r"<<-?\s*'?\"?([A-Za-z_][A-Za-z0-9_]*)'?\"?", s)
        if m:
            hd = m.group(1)
    return out

def heredocs(text):
    """[(start_lineno, opener_line, body_text)]"""
    res, cur = [], None
    lines = text.split("\n")
    i = 0
    while i < len(lines):
        s = lines[i].strip()
        m = re.search(r"<<-?\s*'?\"?([A-Za-z_][A-Za-z0-9_]*)'?\"?", s)
        if m and not s.startswith("#"):
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
    return re.sub(r"\$\{?([A-Z_][A-Z0-9_]*)\}?", lambda m: env.get(m.group(1), m.group(0)), s)

def write_targets(s, env):
    t = []
    seg = re.split(r"\|\||&&|;", s)
    for part in seg:
        p = expand(part, env)
        for m in re.finditer(r"(?<![0-9&])>>?\s*\"?([^\"\s;&|)]+)\"?", p):
            t.append(m.group(1))
        toks = [x.strip("\"'") for x in p.split()]
        if toks and toks[0] in ("touch", "install", "cp", "mv", "ln") and len(toks) >= 2:
            t.append(toks[-1])
    return t

def facts(render):
    raw, d = load(render)
    wf = wf_map(d)
    f = {"sha": hashlib.sha256(raw).hexdigest(), "doc": d, "wf": wf, "items": items(d)}
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
    arm = []
    for x in f["items"]:
        if "soleur-inngest-provision" in x:
            arm.append(x)
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

def cmd_static(render):
    f = facts(render)
    R = []
    def chk(name, ok, detail=""):
        R.append(("PASS" if ok else "FAIL", name + ((" [" + detail + "]") if detail else "")))
    d, wf, its, sc, svc, tmr = f["doc"], f["wf"], f["items"], f["script"], f["svc"], f["tmr"]
    print("READ_SHA=%s" % f["sha"])
    L = code_lines(sc)
    env = resolve_vars(L)
    ssec, tsec = unit_parse(svc), unit_parse(tmr)

    # ---- dispatch -------------------------------------------------------------------------------
    chk("dispatch: runcmd has items", len(its) > 0, "items=%d" % len(its))
    chk("dispatch: the provision script is delivered once in write_files, 0755, root:root",
        len(wf.get(SCRIPT_PATH, [])) == 1 and str(wf[SCRIPT_PATH][0].get("permissions")) == "0755"
        and str(wf[SCRIPT_PATH][0].get("owner")) == "root:root" and len(L) >= 40, "code lines=%d" % len(L))
    chk("dispatch: the unit exists (soleur-inngest-provision.service in write_files, 0644)",
        len(wf.get(SVC_PATH, [])) == 1 and str(wf[SVC_PATH][0].get("permissions")) == "0644" and bool(ssec))
    chk("dispatch: the timer exists (soleur-inngest-provision.timer in write_files, 0644)",
        len(wf.get(TMR_PATH, [])) == 1 and str(wf[TMR_PATH][0].get("permissions")) == "0644" and bool(tsec))

    # ---- G1 -------------------------------------------------------------------------------------
    rc_pull = sum(1 for x in its for _, s in code_lines(x) if PULL.search(s))
    rc_login = sum(1 for x in its for _, s in code_lines(x) if LOGIN.search(s))
    chk("G1: no runcmd item pulls an image, in any docker spelling", rc_pull == 0, "found %d" % rc_pull)
    chk("G1: no runcmd item runs docker login", rc_login == 0, "found %d" % rc_login)
    other = 0
    for p, ws in wf.items():
        if p == SCRIPT_PATH:
            continue
        for w in ws:
            other += sum(1 for _, s in code_lines(str(w.get("content", ""))) if PULL.search(s) or LOGIN.search(s))
    chk("G1: no other write_files entry pulls or logs in", other == 0, "found %d" % other)
    s_pull = [s for _, s in L if PULL.search(s)]
    s_login = [s for _, s in L if LOGIN.search(s)]
    chk("G1: the provision script carries exactly ONE image pull (any spelling) and it pulls \"$ZIREF\"",
        len(s_pull) == 1 and re.search(r'docker pull "\$ZIREF"', s_pull[0]) is not None, "pulls=%d" % len(s_pull))
    chk("G1: the provision script carries exactly ONE docker login, to \"$ZOT_EP\"",
        len(s_login) == 1 and 'docker login "$ZOT_EP"' in s_login[0], "logins=%d" % len(s_login))
    es = vals(ssec, "Service", "ExecStart")
    chk("G1: the unit's ExecStart binds to the write_files provision script path",
        len(es) == 1 and es[0].split()[0] == SCRIPT_PATH if es else False, "ExecStart=%s" % es)

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
    first_fallible = min([i for i, s in top if re.search(r"\bdocker\b|\bdoppler\b|inngest-boot-phone-home|\bmkdir\b", s)] or [10**9])
    chk("G2: the EXIT trap is installed before the first fallible command (docker/doppler/mkdir/emit)",
        len(traps_exit) == 1 and traps_exit[0][0] < first_fallible, "trap line %s, first fallible %s" % (traps_exit[0][0] if traps_exit else None, first_fallible))

    # ---- G3 -------------------------------------------------------------------------------------
    cond = vals(ssec, "Unit", "ConditionPathExists")
    cpath = cond[0][1:] if len(cond) == 1 and cond[0].startswith("!") else ""
    writes = []
    for i, s in L:
        for t in write_targets(s, env):
            if cpath and t == cpath:
                writes.append(i)
    chk("G3: the unit's ConditionPathExists=! path is the path the script writes as its latch",
        bool(cpath) and len(writes) >= 1, "condition=%s writes=%d" % (cond, len(writes)))
    chk("G3: exactly one latch write site (spellings normalized: : >, >, touch, install, cp, printf >, $VAR)",
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
    envblk, grab = [], False
    for _, s in L:
        if re.match(r'^env\s+"INNGEST_CLI_VERSION=', s):
            grab = True
        if grab:
            envblk.append(s)
            if "inngest-bootstrap.sh" in s:
                break
    chk("G4: the bootstrap env list passes the literal \"DOPPLER_PROJECT=soleur-inngest\"",
        any(re.search(r'(^|\s)"DOPPLER_PROJECT=soleur-inngest"(\s|$)', s) for s in envblk), "env lines=%d" % len(envblk))

    # ---- G5 -------------------------------------------------------------------------------------
    def pos(pred):
        return [n for n, x in enumerate(its) if any(pred(s) for _, s in code_lines(x))]
    nic = pos(lambda s: re.search(r"(^|[\s;&|(])(/usr/local/bin/)?soleur-inngest-nic-wait(\s|$)", s) is not None)
    starts_svc = pos(lambda s: re.search(r"\bsystemctl\b.*\b(start|restart|try-restart|reload-or-restart)\b.*soleur-inngest-provision\.service", s) is not None)
    can_start = pos(lambda s: re.search(r"\bsystemctl\b.*\b(start|restart|try-restart|reload-or-restart)\b.*soleur-inngest-provision\.(service|timer)", s) is not None
                    or re.search(r"\bsystemctl\b.*\benable\b.*--now.*soleur-inngest-provision|\bsystemctl\b.*--now\b.*\benable\b.*soleur-inngest-provision", s) is not None)
    tenable = pos(lambda s: re.search(r"\bsystemctl\b.*\benable\b.*soleur-inngest-provision\.timer", s) is not None)
    tenable_now = pos(lambda s: re.search(r"\bsystemctl\b.*\benable\b.*soleur-inngest-provision\.timer", s) is not None and "--now" in s)
    noblock = pos(lambda s: re.search(r"\bsystemctl\b.*\bstart\b.*--no-block.*soleur-inngest-provision\.service|\bsystemctl\b.*--no-block.*\bstart\b.*soleur-inngest-provision\.service", s) is not None)
    chk("G5 dispatch: runcmd has items and exactly one NIC-wait call", len(its) > 0 and len(nic) == 1, "items=%d nic=%d" % (len(its), len(nic)))
    chk("G5: exactly one runcmd item starts the provision service, and it is --no-block",
        len(starts_svc) == 1 and starts_svc == noblock, "starts=%s noblock=%s" % (starts_svc, noblock))
    chk("G5: the timer is enabled exactly once and WITHOUT --now (an elapsed OnBootSec would fire at once)",
        len(tenable) == 1 and not tenable_now, "enable=%s now=%s" % (tenable, tenable_now))
    chk("G5: the NIC wait precedes every item that can start the unit (start/restart/enable --now)",
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
    chk("G6: no StartLimitBurst in any section", not any(k == "StartLimitBurst" for kv in ssec.values() for k, _ in kv))
    rs = vals(ssec, "Service", "RestartSec")
    rsv = span(rs[0]) if len(rs) == 1 else None
    chk("G6: RestartSec is set once and >= 60s (bounded retry rate)", rsv is not None and rsv >= 60, "got %s" % rs)
    ts = vals(ssec, "Service", "TimeoutStartSec")
    tsv = span(ts[0]) if len(ts) == 1 else None
    chk("G6: TimeoutStartSec is set once, finite, >= 20min and <= 2h (a oneshot's default is infinity)",
        tsv is not None and 1200 <= tsv <= 7200, "got %s" % ts)
    chk("G6: Type=oneshot and RemainAfterExit=yes", vals(ssec, "Service", "Type") == ["oneshot"] and vals(ssec, "Service", "RemainAfterExit") == ["yes"])
    chk("G6: the service has no [Install] section (a target would wait on a oneshot that retries for hours)", "Install" not in ssec)
    sandbox = [k for kv in ssec.values() for k, v in kv if k in ("PrivateTmp", "ProtectSystem", "ProtectHome", "NoNewPrivileges", "PrivateDevices", "ProtectKernelTunables", "ReadOnlyPaths", "DynamicUser")
               or (k == "KillMode" and v != "control-group")]
    chk("G6: no sandboxing directive changes the environment the moved block ran in", not sandbox, ",".join(sandbox))
    chk("G6: UMask=0022 (runcmd's umask)", vals(ssec, "Service", "UMask") == ["0022"])
    ob = vals(tsec, "Timer", "OnBootSec")
    chk("G6: the timer re-enters on boot (OnBootSec= set) and is WantedBy=timers.target",
        len(ob) == 1 and span(ob[0]) is not None and vals(tsec, "Install", "WantedBy") == ["timers.target"], "OnBootSec=%s" % ob)
    first = [s for _, s in L if not s.startswith("#!")]
    chk("G6: the script refuses xtrace (case \"$-\" in *x*) ... exit 78) before any other command",
        bool(first) and first[0].startswith('case "$-" in *x*)') and "exit 78" in first[0])
    chk("G6: ExecStart is the bare script path (no interpreter, no flags)", es == [SCRIPT_PATH], "got %s" % es)

    # ---- G8 -------------------------------------------------------------------------------------
    iso = [(i, op) for i, op, body in heredocs(sc) if "doppler run" in op and "n_total" in body and "n_inngest" in body]
    chk("G8 dispatch: exactly one isolation self-check site in the script", len(iso) == 1, "found %d" % len(iso))
    first_pull = min([i for i, s in L if PULL.search(s)] or [10**9])
    chk("G8: the isolation check precedes the first image pull", len(iso) == 1 and iso[0][0] < first_pull,
        "iso=%s pull=%s" % (iso[0][0] if iso else None, first_pull))
    chk("G8: no reference to the retired /run/soleur-inngest-doppler.ok sentinel anywhere in the render",
        b"soleur-inngest-doppler.ok" not in open(render, "rb").read())
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
# (/usr/local/bin/, /etc/default/, /var/log/, /run/) extended with /var/lib/ and /tmp/. EVERY pair
# must match the rendered script at least once — a pair that matches nothing is an instrument
# fault, never a pass. (/root/ is not in the table: the script names no /root/ path, so the pair
# would be a guaranteed fault; HOME=/root reaches the script through the environment instead.)
REWRITE_PAIRS='[["/usr/local/bin/","@FX@/bin/"],["/etc/default/","@FX@/etc/"],["/var/log/","@FX@/log/"],["/run/","@FX@/run/"],["/var/lib/","@FX@/lib/"],["/tmp/","@FX@/tmp/"]]'

# =================================================================================================
# Tier A stubs. Every stub appends one line to $FX/calls.log; scenario knobs are FILES under
# $FX/ctl (never environment: the script's environment is built only from the unit's sources).
# =================================================================================================
make_stubs() {
  local fx="$1" b="$1/bin"
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
  local s
  for s in sleep systemctl sync journalctl ip ss nft curl; do
    cat > "$b/$s" <<STUB
#!/bin/sh
FX='$fx'
printf '$s %s\n' "\$*" >> "\$FX/calls.log"
case "$s \$1" in
  "systemctl is-active") cat "\$FX/ctl/is_active" 2>/dev/null || echo inactive ;;
  "systemctl is-enabled") echo enabled ;;
  "curl "*) printf '000' ;;
esac
exit 0
STUB
  done
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
  local fx="$gw/fx" nfail=0 nfault=0
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
  # ---- Tier A dispatch: a render with no substantive script or no env write cannot run Tier A;
  # that is a FAILED property of the render, not an instrument fault.
  if [ "${code_lines:-0}" -lt 40 ] || [ "${envw:-0}" -ne 1 ] || [ ! -s "$gw/zotwrite.sh" ]; then
    _ta 1 "TA dispatch: the provision script (>=40 code lines, found ${code_lines:-0}), the inngest-doppler write (found ${envw:-0}) and the zot creds bake were extracted"
    printf '%s\n' "$static_out" | grep -q '^  FAIL' && return 1
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
    if [ "${1:-}" != keep ]; then
      rm -rf "${fx:?}/lib" "${fx:?}/run" "${fx:?}/tmp" "${fx:?}/log" "${fx:?}/ctl" "${fx:?}/calls.log"
      mkdir -p "$fx/lib/cloud/data" "$fx/lib/soleur-inngest-provision" "$fx/run" "$fx/tmp" "$fx/log" "$fx/ctl"
      printf 'i-fixture\n' > "$fx/lib/cloud/data/instance-id"
      printf 'bs-token' > "$fx/run/inngest-bs-logs-token"
      sed "s#/etc/default/#$fx/etc/#g" "$gw/zotwrite.sh" | env -i PATH=/usr/bin:/bin sh || true
    fi
    rm -rf "${fx:?}/ctl" "${fx:?}/pulls.n"; mkdir -p "$fx/ctl"
    rm -f "$fx/etc/soleur-inngest-image"
  }
  local SC_RC SC_START
  run_sc() { # run_sc <scenario> [dash flags override]
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
  at() { grep -nE "$2" "$gw/$1.log" | sed -n '1p' | cut -d: -f1; }
  last() { grep -nE "$2" "$gw/$1.log" | tail -1 | cut -d: -f1; }
  common() { # common <scenario> <expected rc>
    _ta "$([ "$SC_RC" = "$2" ] && echo 0 || echo 1)" "TA $1: exits $2 (rc=$SC_RC)"
    _ta "$(grep -q 'parameter not set' "$gw/$1.err" && echo 1 || echo 0)" "TA $1: no 'parameter not set' in stderr (the script reads nothing it does not set, G7)"
  }
  local PULL_RE='^docker (--config [^ ]+ )?(image |container )?pull '
  local LATCHF="$fx/lib/soleur-inngest-provision/done"

  # -u probe (G7 own dispatch): the invocation must abort on a guaranteed-unset read.
  printf 'echo "$PU_GUARANTEED_UNSET_SENTINEL"\n' > "$fx/probe.sh"
  # shellcheck disable=SC2086
  ( env -i "${ENVKV[@]}" "$DASH" $dflags "$fx/probe.sh" ) > /dev/null 2> "$gw/probe.err"
  local prc=$?
  _ta "$( [ "$prc" -eq 2 ] && grep -q 'parameter not set' "$gw/probe.err" && echo 0 || echo 1)" "G7 dispatch: -u is in effect in the Tier A invocation (probe rc=$prc)"

  # X — xtrace refusal: exit 78 before ANY stub call.
  reset_fx; run_sc X "-x $dflags"
  _ta "$( [ "$SC_RC" = 78 ] && [ "$(grep -vc '^== ' "$gw/X.log")" = 0 ] && echo 0 || echo 1)" "TA X: under dash -x the script exits 78 before any emit or call (rc=$SC_RC, calls=$(grep -vc '^== ' "$gw/X.log"))"

  # T1 — miss: every pull fails.
  reset_fx; echo 1 > "$fx/ctl/pull_rc"; run_sc T1; common T1 1
  local t1_fatal t1_exit t1_lastnamed
  t1_fatal="$(at T1 '^phone inngest_pull_fatal .*attempt=1')"; t1_exit="$(at T1 '^phone provision-attempt-exit-1 ')"
  t1_lastnamed="$(grep -E '^phone ' "$gw/T1.log" | grep -vE '^phone provision-attempt-exit-' | tail -1 | awk '{print $2}')"
  _ta "$( [ ! -e "$LATCHF" ] && echo 0 || echo 1)" "TA T1: no latch after a missed attempt"
  _ta "$( [ "$(cnt T1 "$PULL_RE")" = 3 ] && echo 0 || echo 1)" "TA T1: exactly 3 zot pulls (pulls=$(cnt T1 "$PULL_RE"))"
  _ta "$( [ -n "$t1_fatal" ] && has T1 '^emit inngest_pull_fatal fatal rc=1$' && echo 0 || echo 1)" "TA T1: inngest_pull_fatal attempt=1 on both channels"
  _ta "$( ! awk -v f="${t1_fatal:-999999}" 'NR > f && /^docker (create|cp) /' "$gw/T1.log" | grep -q . && echo 0 || echo 1)" "TA T1: no docker create/cp after the miss"
  _ta "$( [ "$t1_lastnamed" = inngest_pull_fatal ] && [ -n "$t1_exit" ] && echo 0 || echo 1)" "TA T1: inngest_pull_fatal is the last named-stage emit before provision-attempt-exit-1 (last=$t1_lastnamed)"

  # T2 — recover: attempt 2 on the same host; the extract container's rm FAILS inside the trap.
  reset_fx keep; echo 0 > "$fx/ctl/pull_rc"; echo 1 > "$fx/ctl/rm_rc"; : > "$fx/ctl/ph_fail_net-health"; run_sc T2; common T2 0
  _ta "$( [ -e "$LATCHF" ] && [ ! -s "$LATCHF" ] && echo 0 || echo 1)" "TA T2: the empty latch exists after a successful attempt"
  _ta "$( [ "$(tr -cd 0-9 < "$fx/lib/soleur-inngest-provision/attempts")" = 2 ] && echo 0 || echo 1)" "TA T2: the attempt counter reads 2"
  _ta "$( has T2 '^phone bootstrap-done .*iid=i-fixture' && ! has T2 '^phone provision-attempt-exit' && echo 0 || echo 1)" "TA T2: bootstrap-done carries iid and no provision-attempt-exit is emitted"
  _ta "$( [ -n "$(at T2 '^sync ')" ] && echo 0 || echo 1)" "TA T2: the latch write is synced"
  _ta "$( has T2 '^phone provision-attempt-start attempt=2 iid=i-fixture' && echo 0 || echo 1)" "TA T2: provision-attempt-start attempt=2 iid=i-fixture"

  # T3 — isolation FATAL, AFTER a passing attempt in the same fixture (no verdict may carry over).
  reset_fx; echo 0 > "$fx/ctl/pull_rc"; run_sc T3a
  rm -f "$LATCHF"; reset_fx keep
  printf '{"INNGEST_SIGNING_KEY":{},"INNGEST_EVENT_KEY":{},"INNGEST_REDIS_PASSWORD":{},"INNGEST_POSTGRES_URI":{},"BETTERSTACK_LOGS_TOKEN":{},"SUPABASE_SERVICE_ROLE_KEY":{}}\n' > "$fx/ctl/names"
  run_sc T3; common T3 1
  _ta "$( has T3 '^phone isolation-check-FAILED' && [ "$(cnt T3 "$PULL_RE")" = 0 ] && [ ! -e "$LATCHF" ] && echo 0 || echo 1)" "TA T3: isolation-check-FAILED, zero pulls, no latch (pulls=$(cnt T3 "$PULL_RE"))"
  _ta "$( [ "$(grep -cE '^phone isolation-check-passed' "$gw/T3a.log")" = 1 ] && echo 0 || echo 1)" "TA T3: the prior attempt did pass isolation (the carry-over probe is live)"

  # T4 — bootstrap fails.
  reset_fx; echo 0 > "$fx/ctl/pull_rc"; echo 1 > "$fx/ctl/boot_rc"; run_sc T4; common T4 1
  local t4_x t4_j t4_q t4_b
  t4_x="$(at T4 '^phone bootstrap-exit-1 ')"; t4_j="$(at T4 '^phone bootstrap-failure-journal ')"
  t4_q="$(at T4 '^systemctl stop inngest-cutover-flip\.timer inngest-luks-cutover\.timer')"; t4_b="$(at T4 '^bootstrap start ')"
  _ta "$( [ -n "$t4_x" ] && [ -n "$t4_j" ] && [ "$t4_x" -lt "$t4_j" ] && echo 0 || echo 1)" "TA T4: bootstrap-exit-1 then bootstrap-failure-journal"
  _ta "$( [ ! -e "$LATCHF" ] && echo 0 || echo 1)" "TA T4: no latch after a failed bootstrap"
  _ta "$( [ -n "$t4_q" ] && [ -n "$t4_b" ] && [ "$t4_q" -lt "$t4_b" ] && echo 0 || echo 1)" "TA T4: the cutover-FSM quiesce (systemctl stop of both timers) precedes the bootstrap run (stop=$t4_q boot=$t4_b)"
  _ta "$( has T4 '^bootstrap start DOPPLER_PROJECT=soleur-inngest ' && echo 0 || echo 1)" "TA T4: the bootstrap sees DOPPLER_PROJECT=soleur-inngest"

  # T5 — stale container: pre-clean by name, then everything addresses the returned ID.
  reset_fx; echo 0 > "$fx/ctl/pull_rc"; echo newcid42 > "$fx/ctl/cid"; run_sc T5; common T5 0
  local t5_rm t5_cr
  t5_rm="$(at T5 '^docker rm -f soleur-inngest-bootstrap-extract$')"; t5_cr="$(at T5 '^docker create ')"
  _ta "$( [ -n "$t5_rm" ] && [ -n "$t5_cr" ] && [ "$t5_rm" -lt "$t5_cr" ] && echo 0 || echo 1)" "TA T5: the stale-name pre-clean precedes docker create"
  _ta "$( [ "$(cnt T5 '^docker cp ')" -ge 5 ] && [ "$(cnt T5 '^docker cp newcid42:/')" = "$(cnt T5 '^docker cp ')" ] && echo 0 || echo 1)" "TA T5: every docker cp addresses the ID docker create returned ($(cnt T5 '^docker cp newcid42:/')/$(cnt T5 '^docker cp '))"

  # T7 — an unnamed arm (the fatal docker cp of the bootstrap script) is still reported.
  reset_fx; echo 0 > "$fx/ctl/pull_rc"; echo 1 > "$fx/ctl/cp_boot_rc"; run_sc T7; common T7 1
  _ta "$( has T7 '^phone provision-attempt-exit-1 attempt=1 iid=i-fixture' && has T7 '^emit provision_attempt_failed warning rc=1\.attempt=1\.iid=i-fixture$' && echo 0 || echo 1)" "TA T7: the EXIT trap emits provision-attempt-exit-1 and provision_attempt_failed"

  # T8 — timeout: one pull, no inner retry, exit 124.
  reset_fx; : > "$fx/ctl/pull_timeout"; run_sc T8; common T8 124
  _ta "$( [ "$(cnt T8 "$PULL_RE")" = 1 ] && has T8 '^phone inngest_pull_fatal .*rc=124 .*attempt=1' && echo 0 || echo 1)" "TA T8: exactly one pull and inngest_pull_fatal rc=124 attempt=1"

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

  # T6-A — every doppler call saw the token and HOME=/root (Tier B re-proves it through systemd).
  _ta "$( [ "$(cat "$gw"/T2.log | grep -c '^doppler ')" -ge 2 ] && ! grep -h '^doppler ' "$gw/T2.log" | grep -vq 'TOKEN=set HOME=/root$' && echo 0 || echo 1)" "TA T6: every doppler call carries DOPPLER_TOKEN and HOME=/root"

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
C0_EXPECTED=94
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
ISO_FAILED = "/usr/local/bin/inngest-boot-phone-home.sh isolation-check-FAILED \"attempt=$attempt\" || true"
ISO_PASSED = "/usr/local/bin/inngest-boot-phone-home.sh isolation-check-passed \"attempt=$attempt\" || true"
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
row G1-r1 RED "G1: no runcmd item pulls an image" '
s = s.rstrip("\n") + "\n  - timeout 180 docker pull \"$ZIREF\"\n"; save()'
row G1-r2 RED "dispatch: runcmd has items" '
s = "#cloud-config\nruncmd: []\nwrite_files: []\n"; save()'
row G1-r3 RED "G1: the provision script carries exactly ONE image pull" '
ins_after("printf \x27INNGEST_BOOTSTRAP_IMAGE=%s\\n\x27 \"$IREF\" > /etc/default/soleur-inngest-image", ["docker pull \"$IREF\" >/dev/null 2>&1 || true"]); save()'
row G1-r4 RED "G1: the unit's ExecStart binds to the write_files provision script path" '
rep_line("ExecStart=/usr/local/bin/soleur-inngest-provision", "ExecStart=/usr/local/bin/soleur-inngest-provision2"); save()'
row G1-r5 RED "G1: no runcmd item runs docker login" '
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
row G3-r2 RED "TA T4: no latch after a failed bootstrap" '
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
rep_line("\"DOPPLER_PROJECT=soleur-inngest\" \\", "\"DOPPLER_PROJECT=soleur\" \\"); save()'
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
raw_rep("DOPPLER_TOKEN=%s\\nDOPPLER_CONFIG_DIR=/tmp/.doppler\\nDOPPLER_ENABLE_VERSION_CHECK=false\\n\x27 \x27", "DOPPLER_TOKEN=%s\\nDOPPLER_ENABLE_VERSION_CHECK=false\\n\x27 \x27"); save()'
row G7-r5 PASS - '
ins_after("attempt=0", [": \"${SOLEUR_PU_UNSET_OK:-default}\""]); save()'

# ---- G8 --------------------------------------------------------------------------------------
row G8-r1 RED "G8: no reference to the retired /run/soleur-inngest-doppler.ok sentinel" '
ls = lines(); a = one(ISO_OPEN); f = one(ISO_FAILED); e = one("fi", after=f)
ls[a:e + 1] = [ind(a) + "test -f /run/soleur-inngest-doppler.ok || exit 1"]; put(ls); save()'
row G8-r2 RED "TA T3: isolation-check-FAILED, zero pulls" '
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
UBUNTU_BASE='ubuntu:24.04@sha256:33ceb71981b602c1a7443a53469e4dba065f7503eab3078a2d7a57a2ab987517'
TIERB_RESULT=""
TB_FAIL=0
tb_skip() { echo "  SKIP (Tier B): $1"; TIERB_RESULT="skipped: $1"; }
tb_ok() { if [ "$1" -eq 0 ]; then echo "  PASS: $2"; else echo "  FAIL: $2"; TB_FAIL=$((TB_FAIL + 1)); fi; }

tierb() {
  local img_tag ctr="pu-tierb-$$" x
  if [ "${PU_TIERB:-1}" = 0 ]; then
    [ -n "${CI:-}" ] && { echo "  FAIL: PU_TIERB=0 is refused under CI"; TB_FAIL=1; return; }
    tb_skip "PU_TIERB=0 (operator opt-out, local only)"; return
  fi
  if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    if [ -n "${CI:-}" ]; then echo "  FAIL: docker is absent under CI (the runner is contracted to supply it)"; TB_FAIL=1; return; fi
    tb_skip "docker absent or unreachable (local host)"; return
  fi
  img_tag="soleur-pu-tierb:$(printf '%s systemd systemd-sysv dbus jq v1' "$UBUNTU_BASE" | sha256sum | cut -c1-12)"
  if ! docker image inspect "$img_tag" >/dev/null 2>&1; then
    docker rm -f "$ctr-build" >/dev/null 2>&1
    if ! docker run --name "$ctr-build" "$UBUNTU_BASE" sh -c 'export DEBIAN_FRONTEND=noninteractive; for i in 1 2 3; do apt-get update -qq -o Acquire::Retries=5 && apt-get install -y -qq --no-install-recommends -o Acquire::Retries=5 systemd systemd-sysv dbus jq && exit 0; sleep 5; done; exit 100' > "$W/tierb-apt.log" 2>&1; then
      docker rm -f "$ctr-build" >/dev/null 2>&1
      tb_skip "ADR-188 arm_skip: the ubuntu apt archive did not serve systemd/jq ($(tail -1 "$W/tierb-apt.log" | head -c 160))"; return
    fi
    docker commit "$ctr-build" "$img_tag" >/dev/null && docker rm "$ctr-build" >/dev/null
  fi
  TIERB_CTR="$ctr"
  docker run -d --name "$ctr" --privileged --cgroupns=private --cgroup-parent=docker.slice \
    --tmpfs /run --tmpfs /run/lock --tmpfs /tmp "$img_tag" /lib/systemd/systemd > /dev/null 2>"$W/tierb-run.err" \
    || { tb_skip "unbootable systemd container: docker run failed ($(head -c 160 "$W/tierb-run.err"))"; return; }
  X() { docker exec "$ctr" "$@"; }
  XS() { docker exec "$ctr" sh -c "$1"; }
  wait_boot() {
    local i s
    for i in $(seq 1 60); do
      s="$(X systemctl is-active multi-user.target 2>/dev/null)"; [ "$s" = active ] && return 0; sleep 1
    done
    return 1
  }
  wait_boot || { tb_skip "unbootable systemd container: multi-user.target not active within 60s"; return; }
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
  for stub in docker doppler inngest-boot-phone-home.sh soleur-boot-emit inngest-redact.sh inngest-bs-token-restage.sh; do
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
      inngest-bs-token-restage.sh) printf '#!/bin/sh\nprintf tok > /run/inngest-bs-logs-token\nexit 0\n' > "$W/tb-$stub" ;;
    esac
    docker cp "$W/tb-$stub" "$ctr:/usr/local/bin/$stub"; X chmod 0755 "/usr/local/bin/$stub"
  done
  printf '#!/bin/sh\nprintf "%%s flip-start\\n" "$(date +%%s.%%N)" >> /var/lib/tierb/calls.log\n/bin/sleep 20\nprintf "%%s flip-end\\n" "$(date +%%s.%%N)" >> /var/lib/tierb/calls.log\n' > "$W/tb-flip"
  docker cp "$W/tb-flip" "$ctr:/usr/local/sbin/tierb-flip-stub"; X chmod 0755 /usr/local/sbin/tierb-flip-stub
  printf '[Unit]\nDescription=Tier B stand-in for the cutover flip FSM step\n[Service]\nType=oneshot\nExecStart=/usr/local/sbin/tierb-flip-stub\n' > "$W/tb-flip.service"
  docker cp "$W/tb-flip.service" "$ctr:/etc/systemd/system/inngest-cutover-flip.service"
  # Test-only drop-ins: `sh -u` (G7 under real systemd) and a short RestartSec; timer OnBootSec short.
  printf '[Service]\nExecStart=\nExecStart=/bin/sh -u /usr/local/bin/soleur-inngest-provision\nRestartSec=2s\n' > "$W/tb-10.conf"
  docker cp "$W/tb-10.conf" "$ctr:/etc/systemd/system/soleur-inngest-provision.service.d/10-tierb.conf"
  printf '[Timer]\nOnBootSec=\nOnBootSec=2s\n' > "$W/tb-t.conf"
  docker cp "$W/tb-t.conf" "$ctr:/etc/systemd/system/soleur-inngest-provision.timer.d/10-tierb.conf"
  XS 'printf tok > /run/inngest-bs-logs-token; : > /var/lib/tierb/calls.log'
  X systemctl daemon-reload

  LOGF=/var/lib/tierb/calls.log
  mark() { XS "echo \"\$(date +%s.%N) PHASE $1\" >> $LOGF"; }
  lines_from() { XS "awk -v m='PHASE $1' 'f; \$2 == \"PHASE\" && \$0 ~ m\"\$\" {f=1}' $LOGF"; }
  poll() { # poll <seconds> <shell condition run in container>
    local i; for i in $(seq 1 $(( $1 * 2 ))); do XS "$2" >/dev/null 2>&1 && return 0; sleep 0.5; done; return 1
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
  tb_ok "$( [ "$(printf '%s\n' "$x" | grep -c ' phone provision-attempt-start attempt=1 ')" = 1 ] && [ "$(printf '%s\n' "$x" | grep -c ' phone provision-attempt-start ')" = 1 ] && echo 0 || echo 1)" "T12: exactly one provision-attempt-start attempt=1 after arming (a single first-boot trigger)"
  tb_ok "$( [ "$(X systemctl is-active soleur-inngest-provision.timer)" = inactive ] && [ "$(X systemctl is-enabled soleur-inngest-provision.timer)" = enabled ] && echo 0 || echo 1)" "T12: the timer is enabled but NOT active (armed without --now)"
  tb_ok "$(printf '%s\n' "$x" | grep -q ' phone provision-unit-armed ' && echo 0 || echo 1)" "T12: provision-unit-armed is emitted by the rendered arming items"
  tb_ok "$( [ "$(printf '%s\n' "$x" | grep -c ' doppler ')" -ge 2 ] && ! printf '%s\n' "$x" | grep ' doppler ' | grep -vq "TOKEN=$(sed -n 's/^DOPPLER_TOKEN=//p' "$W/c0/inngest-doppler.fixture") HOME=/root$" && echo 0 || echo 1)" "T6: every doppler call received DOPPLER_TOKEN and HOME=/root through real EnvironmentFile= parsing"
  tb_ok "$(X test -e /var/lib/soleur-inngest-provision/done && echo 0 || echo 1)" "T12: the attempt latched"

  # ---- T9: TimeoutStartSec kill -> the TERM trap reports before SIGKILL, then attempt N+1 ------
  reset_state; mark T9
  printf '[Service]\nTimeoutStartSec=5s\n' > "$W/tb-20.conf"; docker cp "$W/tb-20.conf" "$ctr:/etc/systemd/system/soleur-inngest-provision.service.d/20-t9.conf"
  X systemctl daemon-reload
  XS 'echo 0 > /var/lib/tierb/ctl/pull_rc; echo 60 > /var/lib/tierb/ctl/boot_sleep'
  X systemctl start --no-block soleur-inngest-provision.service
  poll 40 "grep -q ' phone provision-attempt-start attempt=2 ' $LOGF"
  x="$(lines_from T9)"
  local t9_b t9_x
  t9_b="$(printf '%s\n' "$x" | awk '$2 == "bootstrap" && $3 == "start" {print $1; exit}')"
  t9_x="$(printf '%s\n' "$x" | awk '$2 == "phone" && $3 ~ /^provision-attempt-exit-143$/ {print $1; exit}')"
  tb_ok "$( [ -n "$t9_b" ] && [ -n "$t9_x" ] && awk -v b="$t9_b" -v e="$t9_x" 'BEGIN { exit !((e - b) <= 15) }' && echo 0 || echo 1)" "T9: provision-attempt-exit-143 lands within 10s of the 5s timeout (bootstrap start $t9_b, exit-143 $t9_x) — well before the 90s SIGKILL"
  tb_ok "$(printf '%s\n' "$x" | awk '$3 ~ /^provision-attempt-exit-143$/ {e=NR} $3 == "provision-attempt-start" && $4 == "attempt=2" {s=NR} END {exit !(e && s && e < s)}' && echo 0 || echo 1)" "T9: the next attempt's provision-attempt-start attempt=2 follows the exit-143"
  X rm -f /etc/systemd/system/soleur-inngest-provision.service.d/20-t9.conf; X systemctl daemon-reload

  # ---- T15: the cutover-FSM quiesce waits for an in-flight flip step; a bounded wait gives up --
  reset_state; mark T15
  XS 'echo 0 > /var/lib/tierb/ctl/pull_rc; : > /var/lib/tierb/ctl/t15'
  X systemctl start --no-block soleur-inngest-provision.service
  poll 60 '[ "$(systemctl show -p SubState --value soleur-inngest-provision.service)" = exited ]'
  x="$(lines_from T15)"
  tb_ok "$(printf '%s\n' "$x" | awk '$2 == "flip-end" {f=NR} $2 == "bootstrap" && $3 == "start" {b=NR} END {exit !(f && b && f < b)}' && echo 0 || echo 1)" "T15: the bootstrap starts only after the activating flip step finishes"
  reset_state; X systemctl stop inngest-cutover-flip.service >/dev/null 2>&1; mark T15b
  printf '#!/bin/sh\nexec /bin/sleep 0.05\n' > "$W/tb-fastsleep"; docker cp "$W/tb-fastsleep" "$ctr:/usr/local/bin/sleep"; X chmod 0755 /usr/local/bin/sleep
  XS 'echo 0 > /var/lib/tierb/ctl/pull_rc; : > /var/lib/tierb/ctl/t15'
  X systemctl start --no-block soleur-inngest-provision.service
  poll 40 "grep -q ' phone provision-attempt-exit-1 ' $LOGF"
  x="$(lines_from T15b)"
  tb_ok "$(printf '%s\n' "$x" | grep -q ' phone provision-fsm-busy ' && printf '%s\n' "$x" | grep -q ' phone provision-attempt-exit-1 ' && ! printf '%s\n' "$x" | grep -q ' bootstrap start' && echo 0 || echo 1)" "T15: with the wait bound shortened, the attempt exits 1 with provision-fsm-busy and never starts the bootstrap"
  X rm -f /usr/local/bin/sleep; reset_state; X systemctl stop inngest-cutover-flip.service >/dev/null 2>&1

  # ---- T11a: reboot with NO latch — the timer re-enters, multi-user.target does not wait --------
  mark T11a
  XS 'echo 1 > /var/lib/tierb/ctl/pull_rc'
  docker restart "$ctr" >/dev/null
  wait_boot || { echo "  FAIL: T11 container did not come back"; TB_FAIL=$((TB_FAIL + 1)); return; }
  local t11_up; t11_up="$(date +%s.%N)"
  XS 'printf tok > /run/inngest-bs-logs-token'
  poll 20 "awk 'f; \$2 == \"PHASE\" && \$3 == \"T11a\" {f=1}' $LOGF | grep -q ' phone provision-attempt-exit-1 '"
  x="$(lines_from T11a)"
  local t11_s; t11_s="$(printf '%s\n' "$x" | awk '$2 == "phone" && $3 == "provision-attempt-start" {print $1; exit}')"
  tb_ok "$( [ -n "$t11_s" ] && awk -v s="$t11_s" -v u="$t11_up" 'BEGIN { exit !((s - u) <= 15) }' && echo 0 || echo 1)" "T11: after a reboot with no latch the timer starts the unit within 15s of multi-user.target (up $t11_up, start ${t11_s:-none})"
  if ! printf '%s\n' "$x" | grep -q ' phone provision-attempt-start '; then
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
  poll 40 "awk 'f; \$2 == \"PHASE\" && \$3 == \"T10\" {f=1}' $LOGF | grep -q ' phone provision-attempt-exit-1 '"
  X systemctl start soleur-inngest-provision.timer >/dev/null 2>&1
  poll 90 '[ "$(systemctl show -p SubState --value soleur-inngest-provision.service)" = exited ]'
  x="$(lines_from T10)"
  local nr; nr="$(X systemctl show -p NRestarts --value soleur-inngest-provision.service)"
  tb_ok "$( [ "$nr" = 2 ] && [ "$(X systemctl show -p ActiveState --value soleur-inngest-provision.service)" = active ] && echo 0 || echo 1)" "T10: NRestarts=2 and active (exited) after two misses (NRestarts=$nr)"
  tb_ok "$( [ "$(printf '%s\n' "$x" | grep -c ' phone provision-attempt-start ')" = 3 ] && echo 0 || echo 1)" "T10: exactly 3 attempts — the timer start injected during the restart wait added none ($(printf '%s\n' "$x" | grep -c ' phone provision-attempt-start '))"
  tb_ok "$(X test -e /var/lib/soleur-inngest-provision/done && echo 0 || echo 1)" "T10: the latch is present after the ladder"
  X systemctl stop soleur-inngest-provision.timer >/dev/null 2>&1

  # ---- T11b: reboot WITH the latch T10 wrote — condition-skipped, zero attempts ---------------
  mark T11b
  docker restart "$ctr" >/dev/null
  wait_boot || { echo "  FAIL: T11b container did not come back"; TB_FAIL=$((TB_FAIL + 1)); return; }
  sleep 12
  x="$(lines_from T11b)"
  tb_ok "$( [ "$(printf '%s\n' "$x" | grep -c ' phone provision-attempt-start ')" = 0 ] && [ "$(X systemctl show -p ConditionResult --value soleur-inngest-provision.service)" = no ] && echo 0 || echo 1)" "T11: after a reboot WITH the latch the unit is condition-skipped and emits zero attempts (ConditionResult=$(X systemctl show -p ConditionResult --value soleur-inngest-provision.service))"

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
