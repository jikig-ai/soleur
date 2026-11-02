#!/usr/bin/env bash
# Guard suite for the Inngest flip-token split (ADR-282 addendum 2026-10-30, #9927 item 4).
#
# WHAT IS BUILT. The dedicated Inngest host carries TWO Doppler credentials on the isolated
# soleur-inngest/prd config: the read-only BOOT token (both on-host copies, /etc/default/inngest-doppler
# and /etc/default/inngest-server) and a read/write FLIP token in a new root-only 0600 file,
# /etc/default/inngest-flip, consumed as an EnvironmentFile only by inngest-cutover-flip.service (the redactor also
# reads it by value), through a cloud-init `write_files` drop-in whose later EnvironmentFile= overrides DOPPLER_TOKEN.
#
# WHAT IS GUARDED (the plan's `## Guard Contract`, Guards 1 and 2; Guard 3, the plan-time gates, lives in
# tests/scripts/test-inngest-host-{replace,shape}-gate.sh and plugins/soleur/test/terraform-target-parity.test.ts).
#   R  effective-environment resolver: a systemd-parser MODEL over the whole unit population (the baked
#      units, every heredoc unit inngest-bootstrap.sh writes, every write_files unit and drop-in in the
#      RENDER). The flip unit's list ends with the flip file and its DOPPLER_TOKEN comes from it; no other
#      unit's list contains it; every other token reader resolves a read-only boot file.
#   X  cross-check against systemd itself. X1 (here): `systemd-analyze verify --root=` flags a misplaced
#      directive in the real unit + the rendered drop-in. X2 (ordering and last-wins in REAL systemd) lives
#      in the Tier B systemd-container harness of cloud-init-inngest-provision-unit.test.sh, which already
#      boots systemd as PID 1 and swaps the real flip unit and the rendered drop-in in after its T-rows.
#      `systemctl --root cat` is REFUSED by systemd ("Verb 'cat' cannot be used with --root=", measured
#      2026-11-01) and is deliberately not used.
#   W  write guard behaviour: the rendered guard runcmd item EXECUTED under dash with synthetic values.
#   O  order and mode: the rendered flip-write item EXECUTED in a temp dir (mode 600), `|| exit 1` live,
#      written before the item that arms soleur-inngest-provision.
#   S  path-occurrence census: /etc/default/inngest-flip appears only in the drop-in, the flip printf and
#      the redactor sed; no other reader or sourcer exists anywhere in the infra scripts.
#   (The former T text tripwire over inngest-cutover-flip.sh was DELETED, R14: a heuristic denylist produced a fresh
#      bypass in two consecutive review rounds. Its job is done at RUNTIME by the canary scan in
#      inngest-cutover-flip.test.sh: a synthetic DOPPLER_TOKEN is exported to every case, every runner's output is
#      captured, and teardown_case fails if the canary appears anywhere in a case's work directory.)
#
# THE RENDER IS THE ARTIFACT. Everything reads the terraform render (inngest-userdata-budget.sh renders
# cloud-init-inngest.yml through templatefile + the comment strip; its stub table is SHARED, not copied), so a
# missed `$${` escape is a render error here, not a surprise on the host. The render is made ONCE; every
# mutation row mutates a COPY, asserts the mutation landed, and requires a FAIL line naming its assertion.
#
# ROWS. A pristine control runs first; nothing is scored if it is not clean, and its PASS-line count is pinned
# (C0_EXPECTED, raised with every assertion added). Rows are pinned by EXPECTED_ROWS / EXPECTED_RED /
# EXPECTED_MUSTPASS; only EXECUTED rows are counted. The guard is PER-LINE by design (CTO N10): a row DOCUMENTS
# that limit rather than asserting a refusal.
#
# ADDED IN THE REVIEW ROUND (CTO R7-R11 and the K7 findings): R-g pins the drop-in as ONLY [Service] plus the one
# EnvironmentFile= line, root:root 0644; W-otherkeys extends the by-value token census to EVERY other cloud-config key
# (final_message, bootcmd, power_state, ...); S-glob refuses a glob EnvironmentFile= or a glob path under /etc/default
# in the render, the bootstrap, every infra script and every parsed unit (the compared token of a `==`/`!=`/`=~`
# test is exempt PER TOKEN, never the whole line); R-g also requires the flip unit's drop-in directories to hold
# exactly ONE write_files entry (a sibling `20-x.conf` carrying ExecStart= is refused);
# the previously un-rowed headline checks (R-c, R-d, O-content, O-nochown, S-scripts, W-flip-empty, W-punct) each have
# a killing row.
#
# ACCEPTED LIMITS (do not chase; recorded in the PR ledger):
#   * Everything here is TEXT over the REPO copies. The signed config-bundle copy of inngest-cutover-flip.sh and the
#     runtime `*.service.d` drop-ins reachable through infra-config-install (DEST_SPEC admits four on this host, and
#     the content gate permits any EnvironmentFile=<path>) are not seen: they are residuals under #11816.
#   * The runtime canary scan in inngest-cutover-flip.test.sh replaces the deleted text tripwire (R14). It proves no
#     leak on the paths that suite exercises. It cannot see a branch no case reaches, the config-bundle copy of the
#     flip script, or children of `doppler run` (they receive the token by design).
#   * Computed paths (`/etc/default/inngest-$n`, brace forms) evade S-glob's literal glob match.
#   * The write guard checks each token line against [A-Za-z0-9._:/-] only (R8 as amended by R12): an extra clean
#     bare-word line passes. The flip file is read by systemd and the redactor's sed and is NEVER sourced, so an
#     extra line there is inert; /etc/default/inngest-doppler IS `.`-sourced as root, so there it would execute.
#     Reachable only through a hostile Doppler API response; not new in this PR.
#   * A `chmod 0644 /etc/default/inngest-*` runcmd item is seen only in its glob or literal-path form (S-glob, S-render,
#     O-nochown); a chmod through a variable, `find -exec` or `install` with a computed path is an accepted gap.
#   * A subshell source of the flip file inside the redactor (`( . /etc/default/inngest-flip )` in place of its
#     `sed -n` read) is an accepted gap: S-render classifies by line shape.
#
# Usage: bash apps/web-platform/infra/inngest-flip-token.test.sh
set -uo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUDGET="$SCRIPT_DIR/inngest-userdata-budget.sh"
BOOTSTRAP="$SCRIPT_DIR/inngest-bootstrap.sh"
FLIPSH="$SCRIPT_DIR/inngest-cutover-flip.sh"
FLIP_UNIT="$SCRIPT_DIR/inngest-cutover-flip.service"
EXPECTED_ROWS=40
EXPECTED_RED=37
EXPECTED_MUSTPASS=3
# The pristine control's assertion inventory is EXACT (like C0_EXPECTED in cloud-init-inngest-provision-unit.test.sh):
# a check deleted or turned into a no-op emit leaves every mutation row green, so the PASS-line count is pinned.
# RAISE it in the same edit that adds an assertion.
C0_EXPECTED=29

die() { printf 'INSTRUMENT FAULT: %s\n' "$*" >&2; exit 2; }

for _t in python3 terraform dash; do
  command -v "$_t" >/dev/null 2>&1 || die "$_t is required (terraform absent is a die, never a skip: the render is the artifact)"
done
python3 -c 'import yaml' 2>/dev/null || die "python3 yaml module is required"
[ -r "$BOOTSTRAP" ] && [ -r "$FLIPSH" ] && [ -r "$FLIP_UNIT" ] || die "an infra input is unreadable"

W="$(mktemp -d -t flip-token-XXXXXX)" || die "mktemp -d failed"
case "$W" in /*/flip-token-*) : ;; *) die "scratch dir $W is not an absolute mktemp path" ;; esac
cleanup() { if [ -n "${FT_KEEP_WORK:-}" ]; then echo "(kept $W)" >&2; else rm -rf "${W:?}"; fi; }
trap cleanup EXIT

# =================================================================================================
# Render once, through terraform's own pipeline, and gate the payload.
# =================================================================================================
PRISTINE="$W/pristine.yml"
BUDGET_LOG="$W/budget.log"
bash "$BUDGET" "$PRISTINE" > "$BUDGET_LOG" 2>&1
BUDGET_RC=$?
echo "=== Inngest flip-token split (ADR-282 addendum 2026-10-30) ==="
echo "--- render (templatefile -> strip -> base64gzip) ---"
sed 's/^/  /' "$BUDGET_LOG"
[ "$BUDGET_RC" -eq 0 ] || { echo "  FAIL: render/budget gate rc=$BUDGET_RC (a missed \$\${ or %%{ escape, an over-cap payload, or a template variable the budget script does not stub)"; exit 1; }
[ -s "$PRISTINE" ] || die "the budget script produced no stripped render"
[ "$(head -1 "$PRISTINE")" = '#cloud-config' ] || { echo "  FAIL: the stripped render does not start with #cloud-config"; exit 1; }

# =================================================================================================
# The python half: the unit-population resolver, the executed items, the censuses, and the mutator.
# =================================================================================================
PY="$W/ft.py"
cat > "$PY" <<'PYEOF'
import json, os, re, shutil, stat, subprocess, sys, tempfile, yaml

FLIP = "/etc/default/inngest-flip"
READ_FILES = {"/etc/default/inngest-server", "/etc/default/inngest-doppler"}
FLIP_UNIT = "inngest-cutover-flip.service"
SYSD = "/etc/systemd/system/"
PHONE_HOME = "/usr/local/bin/inngest-boot-phone-home.sh"
# The census floor: units the resolver MUST have parsed (a parser that finds nothing cannot pass).
KNOWN_UNITS = ["inngest-cutover-flip.service", "inngest-redis.service", "inngest-server.service",
               "inngest-heartbeat.service", "inngest-server-probe.service", "inngest-trace-retention.service",
               "vector.service", "inngest-luks-open.service", "soleur-inngest-provision.service",
               "inngest-config-refresh.service"]
HARNESS_IGNORE_DROPINS = os.environ.get("FLIPTEST_HARNESS_IGNORE_DROPINS") == "1"
DASH = shutil.which("dash") or "/bin/sh"
# The C loader/dumper when libyaml is present (a wall-time lever only: same parse, same output).
LOADER = getattr(yaml, "CSafeLoader", yaml.SafeLoader)
DUMPER = getattr(yaml, "CSafeDumper", yaml.SafeDumper)

# ----------------------------------------------------------------------------------------------
# loading
# ----------------------------------------------------------------------------------------------
def load(p):
    d = yaml.load(open(p, encoding="utf-8").read(), Loader=LOADER) or {}
    if not isinstance(d, dict):
        raise SystemExit("INSTRUMENT FAULT: %s is not a cloud-config mapping" % p)
    return d

def items(doc):
    rc = doc.get("runcmd") or []
    return [(" ".join(str(y) for y in x) if isinstance(x, list) else str(x)) for x in rc]

def wf_list(doc):
    return [w for w in (doc.get("write_files") or []) if isinstance(w, dict) and w.get("path")]

def code_lines(text):
    return [l for l in text.split("\n") if l.strip() and not l.lstrip().startswith("#")]

# ----------------------------------------------------------------------------------------------
# a systemd-parser MODEL (learnings/test-failures/2026-10-11: model the parser, not the file's bytes)
# ----------------------------------------------------------------------------------------------
def directives(text):
    """(section, key, value) in file order. Leading/trailing whitespace is stripped (indented directives
    are valid), blank lines and #/; comment lines are skipped, a trailing backslash joins the next line, a
    key outside the section it belongs to is NOT attributed to another section."""
    out, sec, buf = [], None, ""
    for raw in text.split("\n"):
        line = raw.strip()
        if buf:
            line = buf + " " + line
            buf = ""
        if line.endswith("\\") and not line.startswith(("#", ";")):
            buf = line[:-1].rstrip()
            continue
        if not line or line[0] in "#;":
            continue
        m = re.match(r"^\[([^\]]+)\]$", line)
        if m:
            sec = m.group(1)
            continue
        if "=" in line:
            k, v = line.split("=", 1)
            out.append((sec, k.strip(), v.strip()))
    return out

def env_files(texts):
    """The ordered EnvironmentFile= list after systemd's accumulation: a bare/blank assignment RESETS it, a
    leading '-' marks the file optional. Only [Service] counts (the same key under [Unit] is an inert
    'Unknown key')."""
    lst = []
    for t in texts:
        for sec, k, v in directives(t):
            if sec == "Service" and k == "EnvironmentFile":
                if v == "":
                    lst = []
                else:
                    opt = v.startswith("-")
                    lst.append((opt, (v[1:] if opt else v).strip()))
    return lst

def dropin_dirs(unit):
    """Drop-in directories that apply to `unit`, most specific first: <unit>.d, each <prefix>-.<type>.d
    (a/b/c.service -> a-b-.service.d, a-.service.d), then <type>.d."""
    stem, typ = unit.rsplit(".", 1)
    parts = stem.split("-")
    dirs = [unit + ".d"]
    for i in range(len(parts) - 1, 0, -1):
        dirs.append("-".join(parts[:i]) + "-." + typ + ".d")
    dirs.append(typ + ".d")
    return dirs

def effective_texts(unit, body, dropins):
    """The unit body followed by its drop-ins ordered by FILENAME across all applicable directories; a file
    of the same name in a more specific directory masks the less specific one."""
    if HARNESS_IGNORE_DROPINS:
        return [body]
    dirs = dropin_dirs(unit)
    chosen = {}
    for d in dirs:  # most specific first wins on a filename clash
        for (dn, fn, txt) in dropins:
            if dn == d and fn not in chosen:
                chosen[fn] = txt
    return [body] + [chosen[f] for f in sorted(chosen)]

# ----------------------------------------------------------------------------------------------
# the unit population
# ----------------------------------------------------------------------------------------------
def bootstrap_units(text):
    """Heredoc-authored *.service units in inngest-bootstrap.sh: `cat > <target> <<'DELIM'` where the
    target is a literal /etc/systemd/system/*.service path or a variable assigned to one."""
    var = {}
    for m in re.finditer(r'^[ \t]*(?:readonly[ \t]+)?([A-Za-z_][A-Za-z0-9_]*)="(/etc/systemd/system/[^"]+\.service)"', text, re.M):
        var[m.group(1)] = m.group(2)
    units, lines, i = [], text.split("\n"), 0
    while i < len(lines):
        m = re.match(r"""^[ \t]*cat[ \t]*>[ \t]*(\S+)[ \t]+<<-?['"]?([A-Za-z_][A-Za-z0-9_]*)['"]?[ \t]*$""", lines[i])
        if m:
            tgt = m.group(1).strip('"').replace("${", "").replace("}", "").lstrip("$")
            path = var.get(tgt, tgt)
            delim, j, body = m.group(2), i + 1, []
            while j < len(lines) and lines[j].strip() != delim:
                body.append(lines[j])
                j += 1
            if path.endswith(".service") and path.startswith("/etc/systemd/system/"):
                units.append((os.path.basename(path), "\n".join(body)))
            i = j
        i += 1
    return units

def population(doc, bootstrap_text, infra):
    """-> (units: [(name, origin, body)], dropins: [(dirname, filename, text)])"""
    units, dropins = [], []
    for fn in ("inngest-cutover-flip.service", "inngest-redis.service"):
        p = os.path.join(infra, fn)
        if os.path.exists(p):
            units.append((fn, "baked:" + fn, open(p, encoding="utf-8").read()))
    for (n, body) in bootstrap_units(bootstrap_text):
        units.append((n, "bootstrap:" + n, body))
    for w in wf_list(doc):
        p, c = str(w["path"]), str(w.get("content", ""))
        if not p.startswith(SYSD):
            continue
        rel = p[len(SYSD):]
        if "/" not in rel and rel.endswith(".service"):
            units.append((rel, "write_files:" + rel, c))
        elif rel.count("/") == 1 and rel.split("/")[0].endswith(".d"):
            d, f = rel.split("/")
            if f.endswith(".conf"):
                dropins.append((d, f, c))
    return units, dropins

def env_defs(doc, bootstrap_text):
    """path -> set of variable names the host writes there (printf format strings in runcmd, write_files
    contents, and the bootstrap's cat-heredoc fallback for the server file)."""
    m = {}
    def add(path, names):
        m.setdefault(path, set()).update(names)
    for it in items(doc):
        for line in it.split("\n"):
            mm = re.search(r"printf[ \t]+'([^']*)'.*>[ \t]*(/etc/default/[A-Za-z0-9._-]+)", line)
            if mm:
                add(mm.group(2), re.findall(r"(?:^|\\n)([A-Z_][A-Z0-9_]*)=", mm.group(1)))
    for w in wf_list(doc):
        if str(w["path"]).startswith("/etc/default/"):
            add(str(w["path"]), re.findall(r"^([A-Z_][A-Z0-9_]*)=", str(w.get("content", "")), re.M))
    for mm in re.finditer(r"cat > (/etc/default/inngest-server) <<'?DOPPLEREOF'?\n(.*?)\nDOPPLEREOF", bootstrap_text, re.S):
        add(mm.group(1), re.findall(r"^[ \t]*([A-Z_][A-Z0-9_]*)=", mm.group(2), re.M))
    return m

def token_source(files, defs):
    src = None
    for (_opt, p) in files:
        if "DOPPLER_TOKEN" in defs.get(p, set()):
            src = p
    return src

# ----------------------------------------------------------------------------------------------
# runcmd item selectors
# ----------------------------------------------------------------------------------------------
def pick(its, pred):
    return [n for n, x in enumerate(its) if pred(x)]

def sel_guard(its):
    return pick(its, lambda x: "SOLEUR_WRITE_GUARD_EOV" in x and "inngest-doppler-write-REFUSED" in x)
def sel_doppler_write(its):
    return pick(its, lambda x: re.search(r"printf .*>\s*/etc/default/inngest-doppler\s*$", x.strip(), re.M) is not None)
def sel_server_write(its):
    return pick(its, lambda x: re.search(r"printf .*>\s*/etc/default/inngest-server\b", x) is not None)
def sel_flip_write(its):
    return pick(its, lambda x: re.search(r"printf .*>\s*" + re.escape(FLIP) + r"\b", x) is not None)
def sel_arm(its):
    def arm(x):
        for l in code_lines(x):
            if re.search(r"\bsystemctl\b.*\b(start|enable)\b.*soleur-inngest-provision", l):
                return True
        return False
    return pick(its, arm)

def printf_value(item, path):
    """The single-quoted token argument of the printf that writes `path`."""
    for line in item.split("\n"):
        if re.search(r">\s*" + re.escape(path) + r"\b", line):
            args = re.findall(r"'([^']*)'", line)
            if len(args) >= 2:
                return args[1]
    return None

GUARD_RE = re.compile(r"(<<'SOLEUR_WRITE_GUARD_EOV'[^\n]*\n)(.*?)(\nSOLEUR_WRITE_GUARD_EOV)", re.S)

def guard_values(item):
    m = GUARD_RE.search(item)
    return None if not m else [l for l in m.group(2).split("\n")]

def with_guard_values(item, vals):
    return GUARD_RE.sub(lambda m: m.group(1) + "\n".join(vals) + m.group(3), item, count=1)

# ----------------------------------------------------------------------------------------------
# executing rendered items
# ----------------------------------------------------------------------------------------------
def run_item(text, tmp, extra_env=None):
    p = os.path.join(tmp, "item.sh")
    open(p, "w").write(text if text.endswith("\n") else text + "\n")
    env = {"PATH": "/usr/bin:/bin"}
    if extra_env:
        env.update(extra_env)
    r = subprocess.run([DASH, p], capture_output=True, text=True, timeout=30, env=env, cwd=tmp)
    return r.returncode

def phone_stub(tmp):
    stub, log = os.path.join(tmp, "ph.sh"), os.path.join(tmp, "ph.log")
    open(stub, "w").write('#!/bin/sh\nprintf \'%s\\n\' "$*" >> ' + log + '\nexit 0\n')
    os.chmod(stub, 0o755)
    open(log, "w").close()
    return stub, log

# ----------------------------------------------------------------------------------------------
# the checks
# ----------------------------------------------------------------------------------------------
class Out:
    def __init__(self):
        self.fails = 0
    def chk(self, cid, desc, ok, detail=""):
        if ok:
            print("PASS %s: %s" % (cid, desc))
        else:
            self.fails += 1
            print("FAIL %s: %s%s" % (cid, desc, (" [" + detail + "]") if detail else ""))
    def fault(self, msg):
        print("INSTRUMENT FAULT: " + msg)

def check(render, bootstrap, flipsh, infra):
    o = Out()
    doc = load(render)
    its = items(doc)
    # The SEMANTIC text of the render: every runcmd item and every write_files content, as the host sees
    # them. Censuses read this, never the raw file, so the YAML dump of a mutated copy (which may fold a
    # multi-line scalar onto one escaped line) cannot change what is counted.
    text = "\n".join(its + [str(w.get("content", "")) for w in wf_list(doc)])
    btext = open(bootstrap, encoding="utf-8").read()
    units, dropins = population(doc, btext, infra)
    defs = env_defs(doc, btext)

    # ---- R: the effective-environment resolver ------------------------------------------------
    by_name = {}
    for (n, origin, body) in units:
        by_name.setdefault(n, []).append((origin, body))
    resolved = {}  # (name, origin) -> (files, src)
    for n, lst in by_name.items():
        for (origin, body) in lst:
            files = env_files(effective_texts(n, body, dropins))
            resolved[(n, origin)] = (files, token_source(files, defs))

    missing = [u for u in KNOWN_UNITS if u not in by_name]
    o.chk("R-f", "census floor: the resolver parsed every known unit and at least one drop-in (a parser that finds nothing cannot pass)",
          not missing and len(dropins) >= 1 and len(units) >= len(KNOWN_UNITS),
          "missing=%s units=%d dropins=%d" % (missing, len(units), len(dropins)))

    flip_insts = [(k, v) for k, v in resolved.items() if k[0] == FLIP_UNIT]
    def flip_ok(v):
        files, src = v
        return bool(files) and files[-1] == (False, FLIP) and [p for (_o, p) in files].count(FLIP) == 1 and src == FLIP
    o.chk("R-a", "the flip unit's final EnvironmentFile list ends with an unprefixed /etc/default/inngest-flip, once, and its effective DOPPLER_TOKEN source is that file",
          bool(flip_insts) and all(flip_ok(v) for _k, v in flip_insts),
          "; ".join("%s=%s src=%s" % (k[1], v[0], v[1]) for k, v in flip_insts))

    others = [(k, v) for k, v in resolved.items() if k[0] != FLIP_UNIT]
    leak = [k[0] for k, v in others if any(p == FLIP for (_o, p) in v[0])]
    o.chk("R-b", "no unit other than the flip unit lists /etc/default/inngest-flip in its effective EnvironmentFile list",
          not leak, ",".join(sorted(set(leak))))

    bad_src = [k[0] for k, v in others if v[1] is not None and v[1] not in READ_FILES]
    # every other unit that can reach a Doppler credential through an env file reads the boot token
    consumers = [k[0] for k, v in others if v[1] is not None]
    o.chk("R-c", "every other unit that resolves DOPPLER_TOKEN resolves it from inngest-server or inngest-doppler (the read-only boot token), and at least three such units exist",
          not bad_src and len(set(consumers)) >= 3, "bad=%s consumers=%d" % (sorted(set(bad_src)), len(set(consumers))))

    fv = defs.get(FLIP, set())
    o.chk("R-d", "the flip file defines exactly one variable, DOPPLER_TOKEN (project, config and config-dir still come from the baked server file)",
          fv == {"DOPPLER_TOKEN"}, "defs=%s" % sorted(fv))

    # the drop-in's shape
    flip_dropins = [(d, f, t) for (d, f, t) in dropins if d in dropin_dirs(FLIP_UNIT) and any(p == FLIP for (_o, p) in env_files([t]))]
    shape_ok = bool(flip_dropins)
    for (_d, _f, t) in flip_dropins:
        svc = [(k, v) for (s, k, v) in directives(t) if s == "Service" and k == "EnvironmentFile"]
        shape_ok = shape_ok and (("EnvironmentFile", FLIP) in svc)
    cond = []
    for (_n, _o2, body) in units:
        cond += [v for (_s, k, v) in directives(body) if k == "ConditionPathExists" and "inngest-flip" in v]
    for (_d, _f, t) in dropins:
        cond += [v for (_s, k, v) in directives(t) if k == "ConditionPathExists" and "inngest-flip" in v]
    o.chk("R-e", "the drop-in carries an unprefixed EnvironmentFile=/etc/default/inngest-flip under [Service] and NO ConditionPathExists names the flip file anywhere (a missing file must fail loud, CTO N1)",
          shape_ok and not cond, "dropins=%d cond=%s" % (len(flip_dropins), cond))

    # R-g: the drop-in is EXACTLY `[Service]` + the single EnvironmentFile= line, root:root, mode 0644. R-a..R-e
    # only prove the line is present and unprefixed; an added ExecStart= (a replacement command running under the
    # read/write token), UnsetEnvironment=, Environment= or an unrelated Condition, or a mode 0666, leaves them green.
    g_ok = bool(flip_dropins)
    g_detail = []
    for (d, f, t) in flip_dropins:
        ds = directives(t)
        ent = [w for w in wf_list(doc) if str(w["path"]) == SYSD + d + "/" + f]
        this_ok = (ds == [("Service", "EnvironmentFile", FLIP)] and len(ent) == 1
                   and str(ent[0].get("permissions")) == "0644" and str(ent[0].get("owner")) == "root:root")
        g_ok = g_ok and this_ok
        g_detail.append("%s/%s directives=%s perm=%s owner=%s" % (d, f, ds, [str(e.get("permissions")) for e in ent], [str(e.get("owner")) for e in ent]))
    # closed set: EVERY write_files entry under ANY drop-in directory that applies to the flip unit (<unit>.d, the
    # <prefix>-.service.d forms, service.d) must be the one flip drop-in. A sibling `20-x.conf` with ExecStart= or
    # UnsetEnvironment= would otherwise run under, or strip, the read/write token with R-a..R-g green.
    sib = [str(w["path"]) for w in wf_list(doc) if any(str(w["path"]).startswith(SYSD + d2 + "/") for d2 in dropin_dirs(FLIP_UNIT))]
    g_ok = g_ok and len(sib) == 1
    g_detail.append("drop-ins under the flip unit's directories=%s" % sib)
    o.chk("R-g", "the flip drop-in is ONLY [Service] plus the single EnvironmentFile=/etc/default/inngest-flip line (no ExecStart=, UnsetEnvironment=, Environment= or Condition), owner root:root, mode 0644, and it is the ONLY write_files entry under any drop-in directory of the flip unit",
          g_ok, "; ".join(g_detail))

    # ---- locate the runcmd items ----------------------------------------------------------------
    gi, dw, sw, fw, arm = sel_guard(its), sel_doppler_write(its), sel_server_write(its), sel_flip_write(its), sel_arm(its)
    sites_ok = len(gi) == 1 and len(dw) == 1 and len(sw) == 1 and len(fw) == 1 and len(arm) >= 1
    o.chk("I-items", "the runcmd carries exactly one Doppler guard item and one write item each for inngest-doppler, inngest-server and inngest-flip, plus the arming items",
          sites_ok, "guard=%s doppler=%s server=%s flip=%s arm=%s" % (gi, dw, sw, fw, arm))
    boot_val = printf_value(its[dw[0]], "/etc/default/inngest-doppler") if len(dw) == 1 else None
    flip_val = printf_value(its[fw[0]], FLIP) if len(fw) == 1 else None
    vals_ok = bool(boot_val) and bool(flip_val) and boot_val != flip_val and len(boot_val) >= 20 and len(flip_val) >= 20
    o.chk("I-vals", "the boot and flip token values were recovered from their printf writes, are distinct, and are long enough to census by value",
          vals_ok, "boot=%s flip=%s" % (bool(boot_val), bool(flip_val)))

    # ---- W: the write guard ---------------------------------------------------------------------
    if len(gi) == 1 and vals_ok:
        g = its[gi[0]]
        gv = guard_values(g)
        o.chk("W-heredoc", "the guard heredoc carries exactly the boot token value and the flip token value, one per line",
              gv is not None and sorted(gv) == sorted([boot_val, flip_val]) and len(gv) == 2, "lines=%s" % (None if gv is None else len(gv)))
        o.chk("W-sites", "a loop (not a single read): the guard item reads every heredoc line",
              re.search(r"while\s+IFS=\s+read\s+-r\s+_wv", g) is not None)

        def guard_run(vals):
            tmp = tempfile.mkdtemp(prefix="g-", dir=os.environ.get("FT_TMP"))
            stub, log = phone_stub(tmp)
            body = with_guard_values(g, vals)
            body2 = body.replace(PHONE_HOME, stub)
            rewrote = body.count(PHONE_HOME)
            rc = run_item(body2, tmp)
            rec = open(log).read()
            shutil.rmtree(tmp, ignore_errors=True)
            return rc, rec, rewrote
        rc, rec, rw = guard_run([boot_val, flip_val])
        o.chk("W-rewrite", "the guard item hard-codes the phone-home path and the rewrite to the recording stub matched at least once",
              rw >= 1, "matches=%d" % rw)
        o.chk("W-clean", "a clean boot+flip pair exits 0 and records no refusal", rc == 0 and rec == "", "rc=%s rec=%r" % (rc, rec[:80]))
        rc, rec, _ = guard_run([boot_val, "bad;value"])
        o.chk("W-flip-unsafe", "an unsafe flip token (';') on the SECOND heredoc line exits 1 and records inngest-doppler-write-REFUSED",
              rc == 1 and "inngest-doppler-write-REFUSED" in rec, "rc=%s" % rc)
        rc, rec, _ = guard_run(["bad value", flip_val])
        o.chk("W-boot-unsafe", "an unsafe boot token (a space) on the FIRST heredoc line exits 1 and records inngest-doppler-write-REFUSED",
              rc == 1 and "inngest-doppler-write-REFUSED" in rec, "rc=%s" % rc)
        rc, rec, _ = guard_run([boot_val, ""])
        o.chk("W-flip-empty", "an empty flip token exits 1 and records inngest-doppler-write-REFUSED",
              rc == 1 and "inngest-doppler-write-REFUSED" in rec, "rc=%s" % rc)
        rc, rec, _ = guard_run(["a.b_c:d/e-f", "A.B_C:D/E-F"])
        o.chk("W-punct", "every allowed punctuation class (. _ : / -) passes",
              rc == 0 and rec == "", "rc=%s" % rc)
        rc, rec, _ = guard_run([boot_val, flip_val, "extra-clean-line"])
        o.chk("W-perline", "DOCUMENTED LIMIT (CTO N10): the guard is PER-LINE, so an extra individually-clean heredoc line is not refused. Reachable only through a hostile Doppler API response; the charset excludes '=', space, quotes, '$' and ';' so a clean extra line is a bare word; the FLIP file is read by systemd and sed and never sourced (inert), but /etc/default/inngest-doppler IS sourced as root (R12 accepted residual)",
              rc == 0, "rc=%s" % rc)
    else:
        for cid in ("W-heredoc", "W-sites", "W-rewrite", "W-clean", "W-flip-unsafe", "W-boot-unsafe", "W-flip-empty", "W-punct", "W-perline"):
            o.chk(cid, "guard item and token values were located", False, "skipped: guard/vals not found")

    # census by VALUE over the whole render: every site of either token value is the guard heredoc or one of
    # exactly three printf writes, and the guard precedes all three
    if vals_ok and sites_ok:
        allowed = {gi[0]: {"b": 1, "f": 1}, dw[0]: {"b": 1}, sw[0]: {"b": 1}, fw[0]: {"f": 1}}
        stray, tb, tf = [], text.count(boot_val), text.count(flip_val)
        for n, x in enumerate(its):
            cb, cf = x.count(boot_val), x.count(flip_val)
            if cb or cf:
                a = allowed.get(n)
                if a is None or cb != a.get("b", 0) or cf != a.get("f", 0):
                    stray.append(n)
        o.chk("W-census", "every substitution site of the boot and flip token values is the guard heredoc or one of exactly three printf writes (inngest-doppler, inngest-server, inngest-flip); no fourth site, nothing outside runcmd",
              not stray and tb == 3 and tf == 2, "stray_items=%s boot_sites=%d flip_sites=%d" % (stray, tb, tf))
        o.chk("W-order", "the guard item precedes all three token writes",
              gi[0] < min(dw[0], sw[0], fw[0]), "guard=%s writes=%s" % (gi[0], [dw[0], sw[0], fw[0]]))
        # EVERY other key of the rendered cloud-config (final_message, bootcmd, power_state.message, phone_home,
        # packages ...) plus the non-content fields of each write_files entry: cloud-init prints some of these to
        # the console and /var/log/cloud-init-output.log. The census above reads only runcmd + write_files content.
        rest = {k: v for k, v in doc.items() if k not in ("runcmd", "write_files")}
        meta = [{k: v for k, v in w.items() if k != "content"} for w in wf_list(doc)]
        blob = json.dumps({"rest": rest, "wf_meta": meta}, sort_keys=True)
        o.chk("W-otherkeys", "neither token value appears under ANY other cloud-config key (final_message, bootcmd, power_state, ...) or in a write_files path/owner/permissions field",
              blob.count(boot_val) == 0 and blob.count(flip_val) == 0 and len(rest) >= 4,
              "boot=%d flip=%d other_keys=%d" % (blob.count(boot_val), blob.count(flip_val), len(rest)))
    else:
        o.chk("W-census", "token value census", False, "skipped: items/values not found")
        o.chk("W-order", "guard precedes writes", False, "skipped: items/values not found")
        o.chk("W-otherkeys", "token values under other cloud-config keys", False, "skipped: items/values not found")

    # ---- O: order and mode ----------------------------------------------------------------------
    if len(fw) == 1 and vals_ok:
        f = its[fw[0]]
        tmp = tempfile.mkdtemp(prefix="o-", dir=os.environ.get("FT_TMP"))
        target = os.path.join(tmp, "flip")
        rw = f.count(FLIP)
        rc = run_item(f.replace(FLIP, target), tmp)
        mode = None
        content = None
        if os.path.exists(target):
            mode = stat.S_IMODE(os.stat(target).st_mode)
            content = open(target).read()
        o.chk("O-mode", "the EXECUTED flip-write item yields mode 600 (umask 0177 in the item itself, not a text pin)",
              rc == 0 and mode == 0o600 and rw >= 1, "rc=%s mode=%s rewrote=%d" % (rc, oct(mode) if mode is not None else None, rw))
        o.chk("O-content", "the flip file is exactly one DOPPLER_TOKEN=<value> line",
              content == "DOPPLER_TOKEN=%s\n" % flip_val, "bytes=%s" % (None if content is None else len(content)))
        nodir = os.path.join(tmp, "no-such-dir", "flip")
        rc2 = run_item(f.replace(FLIP, nodir), tmp)
        o.chk("O-abort", "a failed flip write aborts the item with exit 1 (control: the redirect points at a NON-EXISTENT parent directory; root ignores directory permissions, so an unwritable one proves nothing)",
              rc2 == 1, "rc=%s" % rc2)
        shutil.rmtree(tmp, ignore_errors=True)
    else:
        for cid in ("O-mode", "O-content", "O-abort"):
            o.chk(cid, "flip write item located", False, "skipped: item/values not found")
    o.chk("O-order", "the flip write precedes every item that arms soleur-inngest-provision (the item that also runs the bootstrap)",
          len(fw) == 1 and bool(arm) and fw[0] < min(arm), "flip=%s arm=%s" % (fw, arm))
    chown = [n for n, x in enumerate(its) if any(re.search(r"\b(chown|chgrp|chmod|install)\b", l) and "inngest-flip" in l for l in code_lines(x))]
    o.chk("O-nochown", "no chown, chgrp, chmod or install names the flip file, so it stays root:root mode 0600 (a non-root runner cannot observe ownership; this is the text census)",
          not chown, str(chown))

    # ---- S: path-occurrence census --------------------------------------------------------------
    hits = [l for l in text.split("\n") if FLIP in l and not l.lstrip().startswith("#")]
    kinds = {"dropin": 0, "printf": 0, "redact": 0, "other": 0}
    for l in hits:
        if re.match(r"^\s*EnvironmentFile=" + re.escape(FLIP) + r"\s*$", l):
            kinds["dropin"] += 1
        elif "printf" in l and ">" in l:
            kinds["printf"] += 1
        elif "sed -n" in l and "DOPPLER_TOKEN" in l:
            kinds["redact"] += 1
        else:
            kinds["other"] += 1
    o.chk("S-render", "in the render the flip path appears only in the drop-in (one EnvironmentFile= line), the flip printf and the redactor sed",
          kinds == {"dropin": 1, "printf": 1, "redact": 1, "other": 0}, str(kinds))
    stray_files = []
    for fn in sorted(os.listdir(infra)):
        p = os.path.join(infra, fn)
        if not os.path.isfile(p) or fn == "cloud-init-inngest.yml" or fn.endswith((".test.sh", ".md", ".tf", ".json", ".txt")):
            continue
        try:
            for l in open(p, encoding="utf-8", errors="replace").read().split("\n"):
                if FLIP in l and not l.lstrip().startswith("#"):
                    stray_files.append(fn)
                    break
        except OSError:
            pass
    o.chk("S-scripts", "no infra script, unit or timer outside the template references the flip path in code (any other reader or sourcer reds)",
          not stray_files, ",".join(stray_files))

    # S-glob: the literal-path censuses above cannot see a glob. systemd expands wildcards in EnvironmentFile=, and a
    # shell `for f in /etc/default/inngest-*; do . "$f"; done` or `cat /etc/default/inngest-*` reaches the flip file
    # without naming it. Refused anywhere in the render, the bootstrap, every infra script and every parsed unit.
    GLOB = re.compile(r"/etc/default/[A-Za-z0-9._-]*[*?\[]")
    glob_hits = []
    # a `[[ $x == /etc/default/* ]]` / `case` pattern COMPARISON names the glob without reading it, so it is not a hit.
    # The exemption is PER TOKEN (R14): only the compared operand is removed before the glob match, so a comparison
    # elsewhere on the line cannot hide a reading glob (`[[ $x == /etc/default/y ]] && for f in /etc/default/inngest-*`).
    CMP = re.compile(r"(==|!=|=~)\s*\S*/etc/default/\S*")
    def glob_hit(l):
        return GLOB.search(CMP.sub("", l)) is not None
    for label, blob in (("render", text), ("bootstrap", btext)):
        for l in code_lines(blob):
            if glob_hit(l):
                glob_hits.append("%s: %s" % (label, l.strip()[:60]))
    for fn in sorted(os.listdir(infra)):
        p = os.path.join(infra, fn)
        if not os.path.isfile(p) or fn == "cloud-init-inngest.yml" or fn.endswith((".test.sh", ".md", ".tf", ".json", ".txt")):
            continue
        try:
            for l in code_lines(open(p, encoding="utf-8", errors="replace").read()):
                if glob_hit(l):
                    glob_hits.append("%s: %s" % (fn, l.strip()[:60]))
                    break
        except OSError:
            pass
    for (n, _o2, body) in units + [(d + "/" + f, "dropin", t) for (d, f, t) in dropins]:
        for (_s, k, v) in directives(body):
            if k == "EnvironmentFile" and re.search(r"[*?\[]", v):
                glob_hits.append("unit %s: EnvironmentFile=%s" % (n, v))
    o.chk("S-glob", "no glob EnvironmentFile= and no glob path under /etc/default anywhere in the render, the bootstrap, the infra scripts or any parsed unit",
          not glob_hits, "; ".join(glob_hits[:3]))

    return o.fails

# ----------------------------------------------------------------------------------------------
# the mutator: structural edits to a COPY of the render (yaml load/dump), exit 3 when nothing changed
# ----------------------------------------------------------------------------------------------
def mutate(src, dst, ops):
    doc = load(src)
    before = yaml.dump(doc, Dumper=DUMPER, width=10**9, allow_unicode=True, default_flow_style=False)
    its = doc.get("runcmd") or []
    def sel(name):
        s = {"guard": sel_guard, "doppler": sel_doppler_write, "server": sel_server_write, "flip": sel_flip_write, "arm": sel_arm}[name](items(doc))
        if not s:
            raise SystemExit("INSTRUMENT FAULT: selector %s found nothing" % name)
        return s[0]
    def dropin_entry():
        for w in wf_list(doc):
            if str(w["path"]).endswith("/10-flip-token.conf"):
                return w
        raise SystemExit("INSTRUMENT FAULT: no 10-flip-token.conf drop-in in the render")
    def u(x):
        return x.replace("\\n", "\n")
    i = 0
    while i < len(ops):
        op = ops[i]
        if op == "identity":
            i += 1
        elif op == "dropin_sub":
            w = dropin_entry(); w["content"] = str(w["content"]).replace(ops[i + 1], u(ops[i + 2])); i += 3
        elif op == "guard_drop":
            n = sel("guard"); g = str(its[n]); vals = guard_values(g)
            del vals[int(ops[i + 1])]
            its[n] = with_guard_values(g, vals); i += 2
        elif op == "guard_single_read":
            n = sel("guard"); g = str(its[n]); vals = guard_values(g)
            arm = re.search(r"^[ \t]*(''\|\*\[!A-Za-z0-9\._:/-\]\*\).*;;)[ \t]*$", g, re.M)
            if not arm:
                raise SystemExit("INSTRUMENT FAULT: no case arm in the guard item")
            its[n] = ("IFS= read -r _wv <<'SOLEUR_WRITE_GUARD_EOV'\n" + "\n".join(vals) + "\nSOLEUR_WRITE_GUARD_EOV\n"
                      "case \"$_wv\" in\n  " + arm.group(1) + "\nesac\nunset _wv")
            i += 1
        elif op == "dup_flip_write_front":
            fv = printf_value(items(doc)[sel("flip")], FLIP)
            its.insert(0, "printf 'DOPPLER_TOKEN=%s\\n' '" + fv + "' > /tmp/x"); i += 1
        elif op == "dropin_set":
            w = dropin_entry(); w["content"] = u(ops[i + 1]); i += 2
        elif op == "dropin_path":
            w = dropin_entry(); w["path"] = ops[i + 1]; i += 2
        elif op == "item_sub":
            n = sel(ops[i + 1]); its[n] = str(its[n]).replace(ops[i + 2], u(ops[i + 3])); i += 4
        elif op == "item_move_after":
            n, m = sel(ops[i + 1]), sel(ops[i + 2]); x = its.pop(n)
            m = m - 1 if n < m else m
            its.insert(m + 1, x); i += 3
        elif op == "item_move_to_end":
            n = sel(ops[i + 1]); its.append(its.pop(n)); i += 2
        elif op == "append_item":
            its.append(u(ops[i + 1])); i += 2
        elif op == "item_sub_raw":
            n = sel(ops[i + 1]); its[n] = str(its[n]).replace(ops[i + 2], ops[i + 3]); i += 4
        elif op == "dropin_perm":
            w = dropin_entry(); w["permissions"] = ops[i + 1]; i += 2
        elif op == "add_wf":
            doc.setdefault("write_files", []).append({"path": ops[i + 1], "content": u(ops[i + 2]), "owner": "root:root", "permissions": "0644"}); i += 3
        elif op == "doc_key":
            fv = printf_value(items(doc)[sel("flip")], FLIP)
            doc[ops[i + 1]] = ops[i + 2].replace("@FLIP@", fv); i += 3
        else:
            raise SystemExit("INSTRUMENT FAULT: unknown mutation op " + op)
    after = yaml.dump(doc, Dumper=DUMPER, width=10**9, allow_unicode=True, default_flow_style=False)
    open(dst, "w", encoding="utf-8").write("#cloud-config\n" + after)
    if ops == ["identity"]:
        return 0
    return 3 if before == after else 0

def main(a):
    if a[0] == "check":
        render, bootstrap, flipsh, infra = a[1:5]
        check(render, bootstrap, flipsh, infra)
        return 0
    if a[0] == "mut":
        return mutate(a[1], a[2], a[3:])
    if a[0] == "dropin":
        for w in wf_list(load(a[1])):
            if str(w["path"]).endswith("/10-flip-token.conf"):
                sys.stdout.write(str(w["content"]))
                return 0
        return 4
    return 2

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
PYEOF
python3 -I -c "import ast,sys; ast.parse(open('$PY').read())" || die "ft.py does not parse"

# =================================================================================================
# The scored battery.
# =================================================================================================
run_check() { # <render> <bootstrap> <flipsh>  -> stdout of ft.py check; sets CHK_RC
  FT_TMP="$W" python3 -I "$PY" check "$1" "$2" "$3" "$SCRIPT_DIR" 2>"$W/check.err"
  CHK_RC=$?
}
FAULT=0
ROWS=0; RED_ROWS=0; PASS_ROWS=0; ROW_FAIL=0

echo "--- C0: pristine control (nothing below is scored unless this is clean) ---"
run_check "$PRISTINE" "$BOOTSTRAP" "$FLIPSH" > "$W/c0.out"
sed 's/^/  /' "$W/c0.out"
if [ "$CHK_RC" -ne 0 ] || grep -q '^INSTRUMENT FAULT' "$W/c0.out"; then
  echo "  FAIL: the check driver faulted on the pristine render (rc=$CHK_RC): $(head -c 300 "$W/check.err")"
  exit 1
fi
C0_PASS="$(grep -c '^PASS ' "$W/c0.out" || true)"
if [ "$C0_PASS" -ne "$C0_EXPECTED" ]; then
  echo "  FAIL: C0 anti-vacuity — $C0_PASS assertions passed, the inventory is exactly $C0_EXPECTED (an assertion was deleted, silenced or added without re-pinning)"
  ROW_FAIL=1
  PRISTINE_DIRTY=1
fi
C0_FAILS="$(grep -c '^FAIL ' "$W/c0.out" || true)"
if [ "$C0_FAILS" -ne 0 ]; then
  echo "  FAIL: C0 pristine control is not clean ($C0_FAILS failing assertion(s)) — the mutation battery is not scored"
  ROW_FAIL=1
  PRISTINE_DIRTY=1
fi

# row <ID> <RED|PASS> <needle|-> <label> <mutation-kind> <args...>
#   mutation-kind: yml <ft.py ops...> | boot <sed-script> | infra <file> <sed-script> | env <VAR=1> yml <ops...>
MUTDIR="$W/mut"; mkdir -p "$MUTDIR"
row() {
  local id="$1" kind="$2" needle="$3" label="$4" mk="$5"; shift 5
  local render="$PRISTINE" boot="$BOOTSTRAP" flip="$FLIPSH" idir="$SCRIPT_DIR" envv="" out="$MUTDIR/$id.out" mrc=0
  ROWS=$((ROWS + 1)); [ "$kind" = RED ] && RED_ROWS=$((RED_ROWS + 1)) || PASS_ROWS=$((PASS_ROWS + 1))
  case "$mk" in
    env) envv="$1"; shift; mk="$1"; shift ;;
  esac
  case "$mk" in
    yml)  render="$MUTDIR/$id.yml"; python3 -I "$PY" mut "$PRISTINE" "$render" "$@" || mrc=$? ;;
    boot) boot="${MUTDIR:?}/$id.boot.sh"; sed -e "$1" "$BOOTSTRAP" > "${boot:?}"; cmp -s "$BOOTSTRAP" "$boot" && mrc=3 ;;
    infra) # <file> <sed-script>: a symlinked copy of the infra dir with ONE file replaced by its sed-edited copy
      idir="${MUTDIR:?}/$id.infra"; mkdir -p "$idir"
      for _f in "$SCRIPT_DIR"/*; do [ -f "$_f" ] && ln -s "$_f" "$idir/"; done
      rm -f "${idir:?}/$1"; sed -e "$2" "$SCRIPT_DIR/$1" > "${idir:?}/$1"; cmp -s "$SCRIPT_DIR/$1" "$idir/$1" && mrc=3 ;;
    none) ;;
  esac
  if [ "$mrc" -ne 0 ]; then
    echo "  FAIL: $id — $label — HARNESS ABORT: the mutation did not land (rc=$mrc)"; ROW_FAIL=1; return
  fi
  if [ -n "$envv" ]; then env "$envv" FT_TMP="$W" python3 -I "$PY" check "$render" "$boot" "$flip" "$idir" > "$out" 2>"$W/check.err"; else
    FT_TMP="$W" python3 -I "$PY" check "$render" "$boot" "$flip" "$idir" > "$out" 2>"$W/check.err"; fi
  local rc=$?
  if [ "$rc" -ne 0 ] || grep -q '^INSTRUMENT FAULT' "$out"; then
    echo "  FAIL: $id — $label — INSTRUMENT FAULT (rc=$rc): $(head -c 200 "$W/check.err") $(grep '^INSTRUMENT FAULT' "$out" | head -1)"; FAULT=1; ROW_FAIL=1; return
  fi
  if [ "$kind" = RED ]; then
    if grep -q "^FAIL ${needle}" "$out"; then echo "  PASS: $id — $label — mutant killed (FAIL ${needle})"
    else echo "  FAIL: $id — $label — mutant SURVIVED or died on the wrong assertion (wanted FAIL ${needle}; got: $(grep '^FAIL ' "$out" | cut -c1-60 | tr '\n' '|'))"; ROW_FAIL=1; fi
  else
    if grep -q '^FAIL ' "$out"; then echo "  FAIL: $id — $label — must-PASS row failed: $(grep '^FAIL ' "$out" | cut -c1-120 | tr '\n' '|')"; ROW_FAIL=1
    else echo "  PASS: $id — $label — non-canonical shape accepted"; fi
  fi
}

if [ -z "${PRISTINE_DIRTY:-}" ]; then
echo "--- Guard 1: the effective-environment resolver (mutation matrix) ---"
row G1-r0  PASS - "identity round-trip of the render through the mutator (instrument fidelity)" yml identity
row G1-r1  RED  "R-a" "delete the EnvironmentFile= line from the drop-in" yml dropin_sub "EnvironmentFile=/etc/default/inngest-flip" "# gone"
row G1-r2  RED  "R-a" "prefix it with '-' (optional file: a missing file would silently fall back)" yml dropin_sub "EnvironmentFile=/etc/default/inngest-flip" "EnvironmentFile=-/etc/default/inngest-flip"
row G1-r3  RED  "R-a" "move it under [Unit] (inert 'Unknown key' in systemd)" yml dropin_sub "[Service]" "[Unit]"
row G1-r4  RED  "R-a" "add a bare EnvironmentFile= reset line AFTER the flip line" yml dropin_sub "EnvironmentFile=/etc/default/inngest-flip" "EnvironmentFile=/etc/default/inngest-flip\nEnvironmentFile="
row G1-r5  RED  "R-b" "list the flip file as a SECOND EnvironmentFile= in a heredoc unit of inngest-bootstrap.sh (after a compliant first)" boot '0,/^EnvironmentFile=\/etc\/default\/inngest-server$/{//a EnvironmentFile=/etc/default/inngest-flip
}'
row G1-r6  RED  "R-a" "typo the path in the drop-in only (printf and drop-in disagree)" yml dropin_sub "/etc/default/inngest-flip" "/etc/default/inngest-flp"
row G1-r7  RED  "R-a" "rename the drop-in directory to inngest-cutover-flip.servce.d" yml dropin_path "/etc/systemd/system/inngest-cutover-flip.servce.d/10-flip-token.conf"
row G1-r8  RED  "R-a" "gut the body but keep both keywords in comment lines" yml dropin_set "# [Service]\n# EnvironmentFile=/etc/default/inngest-flip\n"
row G1-r9  RED  "R-e" "add ConditionPathExists=/etc/default/inngest-flip to the drop-in (a silent skip)" yml dropin_set "[Unit]\nConditionPathExists=/etc/default/inngest-flip\n[Service]\nEnvironmentFile=/etc/default/inngest-flip\n"
row G1-r10 RED  "O-order" "REORDER: move the flip printf after the item that arms soleur-inngest-provision" yml item_move_to_end flip
row G1-r11 RED  "O-mode" "umask 0177 -> 0137 on the flip write (the executed item yields mode 640)" yml item_sub flip "umask 0177" "umask 0137"
row G1-r11b RED "O-abort" "remove '|| exit 1' from the flip write item" yml item_sub flip ") || exit 1" ")"
row G1-r12 RED  "S-render" "add a shell reader of the flip file (a '. /etc/default/inngest-flip' runcmd item)" yml append_item ". /etc/default/inngest-flip"
row G1-rH1 RED  "R-a" "harness: the resolver ignores drop-in directories (also proves the dispatch is not vacuous)" env FLIPTEST_HARNESS_IGNORE_DROPINS=1 yml identity
row G1-rH2 PASS -       "non-canonical: drop-in renamed 20-whatever.conf, 4-space-indented directives and a trailing comment" yml dropin_set "    [Service]\n    EnvironmentFile=/etc/default/inngest-flip\n    # trailing comment\n" dropin_path "/etc/systemd/system/inngest-cutover-flip.service.d/20-whatever.conf"
row G1-rH3 PASS -       "non-canonical: the same drop-in delivered through a <prefix>-.service.d directory" yml dropin_path "/etc/systemd/system/inngest-cutover-.service.d/10-flip-token.conf"
row G1-rC  RED  "R-c" "a third unit resolves DOPPLER_TOKEN from a new, non-boot env file (write_files unit + file)" yml add_wf /etc/systemd/system/inngest-third.service "[Service]\nEnvironmentFile=/etc/default/inngest-third\n" add_wf /etc/default/inngest-third "DOPPLER_TOKEN=thirdvalue\n"
row G1-rD  RED  "R-d" "the flip printf gains a second variable (EXTRA=1)" yml item_sub_raw flip 'DOPPLER_TOKEN=%s\n' 'DOPPLER_TOKEN=%s\nEXTRA=1\n'
row G1-rO  RED  "O-content" "the flip printf loses its trailing newline" yml item_sub_raw flip 'DOPPLER_TOKEN=%s\n' 'DOPPLER_TOKEN=%s'
row G1-rN  RED  "O-nochown" "append a runcmd item that chowns the flip file to deploy" yml append_item "chown root:deploy /etc/default/inngest-flip"
row G1-rS  RED  "S-scripts" "a COPY of an infra script gains a reader of the flip file (. /etc/default/inngest-flip)" infra inngest-consumer-probe.sh '$a . /etc/default/inngest-flip'
row G1-rG1 RED  "S-glob" "append a shell glob source: for f in /etc/default/inngest-*; do . \"\$f\"; done" yml append_item 'for f in /etc/default/inngest-*; do . "$f"; done'
row G1-rG3 RED  "S-glob" "a comparison elsewhere on the line must not exempt a reading glob: [[ \$x == /etc/default/inngest-server ]] && for f in /etc/default/inngest-*" yml append_item '[[ "$f" == /etc/default/inngest-server ]] && for f in /etc/default/inngest-*; do . "$f"; done'
row G1-rG2 RED  "S-glob" "add a write_files unit with a glob EnvironmentFile=-/etc/default/inngest-f*" yml add_wf /etc/systemd/system/inngest-glob.service "[Service]\nEnvironmentFile=-/etc/default/inngest-f*\n"
row G1-rE1 RED  "R-g" "drop-in gains ExecStart=/bin/true (a replacement command under the read/write token)" yml dropin_set "[Service]\nEnvironmentFile=/etc/default/inngest-flip\nExecStart=/bin/true\n"
row G1-rE2 RED  "R-g" "drop-in gains UnsetEnvironment=DOPPLER_TOKEN" yml dropin_set "[Service]\nEnvironmentFile=/etc/default/inngest-flip\nUnsetEnvironment=DOPPLER_TOKEN\n"
row G1-rE3 RED  "R-g" "drop-in gains a literal Environment=" yml dropin_set "[Service]\nEnvironmentFile=/etc/default/inngest-flip\nEnvironment=X=1\n"
row G1-rE4 RED  "R-g" "drop-in gains an unrelated [Unit] Condition (R-e only names the flip file)" yml dropin_set "[Unit]\nConditionPathExists=/run/x\n[Service]\nEnvironmentFile=/etc/default/inngest-flip\n"
row G1-rE5 RED  "R-g" "drop-in write_files permissions 0644 -> 0666" yml dropin_perm 0666
row G1-rE6 RED  "R-g" "a SIBLING drop-in 20-x.conf in the flip unit's directory carries ExecStart= (closed-set check)" yml add_wf /etc/systemd/system/inngest-cutover-flip.service.d/20-x.conf "[Service]\nExecStart=\nExecStart=/bin/true\n"

echo "--- Guard 2: the write-time charset guard covers both Doppler tokens ---"
row G2-r1  RED  "W-heredoc" "remove the flip token from the guard heredoc" yml guard_drop 1
row G2-r4  RED  "W-census" "add a fourth printf write of the flip token with no guard before it" yml dup_flip_write_front
row G2-r5  RED  "W-order" "move the guard after the inngest-server write" yml item_move_after guard server
row G2-r6  RED  "W-flip-unsafe" "drop 'exit 1' from the guard case arm" yml item_sub guard "exit 1 ;;" ";;"
row G2-r8  RED  "W-flip-unsafe" "replace the while-read loop with a single read (checks only the first heredoc line)" yml guard_single_read
row G2-r9  RED  "W-flip-empty" "delete the empty-string arm (''|) from the guard case" yml item_sub_raw guard "''|" ""
row G2-r10 RED  "W-punct" "drop ':' from the guard's allowed class" yml item_sub_raw guard "._:/-" "._/-"
row G2-r11 RED  "W-otherkeys" "put the flip token in a top-level final_message key (printed to the console log)" yml doc_key final_message "@FLIP@"
row G2-rH1 RED  "W-flip-unsafe" "suite edit: the guard's phone-home call replaced by 'true' (the REFUSED call must be recorded)" yml item_sub guard "/usr/local/bin/inngest-boot-phone-home.sh inngest-doppler-write-REFUSED" "true inngest-doppler-write-REFUSED"
fi

echo ""
echo "--- Section X1: systemd-analyze verify --root= over the REAL unit + the rendered drop-in ---"
X_EXECUTED=0; X_FAIL=0; X_SKIPPED=0
x_skip() {
  if [ -n "${CI:-}${GITHUB_ACTIONS:-}" ]; then echo "  FAIL: X1 skipped under CI ($1) — a skipped cross-check against systemd itself is a FAIL"; X_FAIL=$((X_FAIL + 1))
  else echo "  SKIP (loud, counted): X1 — $1"; X_SKIPPED=$((X_SKIPPED + 1)); fi
}
if ! command -v systemd-analyze >/dev/null 2>&1; then
  x_skip "systemd-analyze is not on PATH"
else
  XR="$W/xroot"; mkdir -p "$XR/etc/systemd/system/inngest-cutover-flip.service.d" "$XR/usr/bin" "$XR/usr/local/bin" "$XR/etc/default"
  cp "$FLIP_UNIT" "$XR/etc/systemd/system/inngest-cutover-flip.service"
  # stub executables so a missing-binary warning cannot be mistaken for (or mask) a directive warning
  printf '#!/bin/sh\nexit 0\n' > "$XR/usr/bin/doppler"; cp "$XR/usr/bin/doppler" "$XR/usr/local/bin/inngest-cutover-flip.sh"
  chmod +x "$XR/usr/bin/doppler" "$XR/usr/local/bin/inngest-cutover-flip.sh"
  UNIT_IN_ROOT="$XR/etc/systemd/system/inngest-cutover-flip.service"
  # control FIRST: the misplaced directive (EnvironmentFile under [Unit]) must be flagged, else this leg proves nothing
  if ! python3 -I "$PY" dropin "$PRISTINE" > /dev/null; then
    echo "  FAIL: X1 — the render carries no 10-flip-token.conf drop-in, so there is nothing to verify against systemd"; X_FAIL=$((X_FAIL + 1))
  else
  python3 -I "$PY" mut "$PRISTINE" "$W/x-mis.yml" dropin_sub "[Service]" "[Unit]" || die "X1 control mutation did not land"
  python3 -I "$PY" dropin "$W/x-mis.yml" > "$XR/etc/systemd/system/inngest-cutover-flip.service.d/10-flip-token.conf"
  X_MIS="$(systemd-analyze verify --root="$XR" "$UNIT_IN_ROOT" 2>&1)"
  # systemd wording differs by version: "Unknown key 'X' in section [Unit]" vs "Unknown key name 'X' in section 'Unit'"
  if ! grep -qE "Unknown key( name)? 'EnvironmentFile' in section (\[Unit\]|'Unit')" <<<"$X_MIS"; then
    x_skip "this systemd-analyze did not flag a misplaced EnvironmentFile= (control failed): $(head -c 160 <<<"$X_MIS" | tr '\n' ' ')"
  else
    python3 -I "$PY" dropin "$PRISTINE" > "$XR/etc/systemd/system/inngest-cutover-flip.service.d/10-flip-token.conf"
    X_OK="$(systemd-analyze verify --root="$XR" "$UNIT_IN_ROOT" 2>&1)"
    X_EXECUTED=$((X_EXECUTED + 1))
    if grep -qiE "Unknown (key|section)|Failed to|Invalid" <<<"$X_OK"; then
      echo "  FAIL: X1 — systemd-analyze verify flags the real unit + rendered drop-in: $(head -c 300 <<<"$X_OK" | tr '\n' ' ')"; X_FAIL=$((X_FAIL + 1))
    else
      echo "  PASS: X1 — the real unit + the rendered drop-in verify with no Unknown-key/section warning (control: a misplaced directive IS flagged)"
    fi
    # discovery print only (a text merge: it proves discovery and order of files, not last-wins)
    systemd-analyze --root="$XR" cat-config systemd/system/inngest-cutover-flip.service 2>/dev/null \
      | grep -E '^(# /|EnvironmentFile=)' | sed 's/^/    cat-config: /'
  fi
  fi
fi

echo ""
echo "=== summary ==="
echo "  rows executed: $ROWS (RED $RED_ROWS, must-PASS $PASS_ROWS); expected $EXPECTED_ROWS (RED $EXPECTED_RED, must-PASS $EXPECTED_MUSTPASS)"
echo "  X_EXECUTED=$X_EXECUTED X_SKIPPED=$X_SKIPPED X_FAIL=$X_FAIL"
RC=0
[ "$ROW_FAIL" -eq 0 ] || RC=1
[ "$FAULT" -eq 0 ] || RC=1
[ "$X_FAIL" -eq 0 ] || RC=1
if [ -z "${PRISTINE_DIRTY:-}" ]; then
  if [ "$ROWS" -ne "$EXPECTED_ROWS" ] || [ "$RED_ROWS" -ne "$EXPECTED_RED" ] || [ "$PASS_ROWS" -ne "$EXPECTED_MUSTPASS" ]; then
    echo "  FAIL: executed row counts differ from the pinned matrix (a row was dropped or added without re-pinning)"; RC=1
  fi
fi
if [ -n "${CI:-}${GITHUB_ACTIONS:-}" ] && [ "$X_EXECUTED" -lt 1 ]; then
  echo "  FAIL: under CI the X1 leg must execute at least once (X_EXECUTED >= 1)"; RC=1
fi
[ "$RC" -eq 0 ] && echo "OK inngest-flip-token: all assertions passed" || echo "FAIL inngest-flip-token"
exit "$RC"
