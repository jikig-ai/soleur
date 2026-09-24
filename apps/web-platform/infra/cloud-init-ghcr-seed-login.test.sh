#!/usr/bin/env bash
set -euo pipefail
# A pipe into `grep -q` SIGPIPEs its producer on an early match and pipefail reads it as
# FALSE (#7024); _qgrep reads all of its input instead.
_qgrep() { grep "$@" >/dev/null; }

# Regression guard for the fresh-boot seed pull, and (since #8036 item 1d / ADR-096 5.3b-i) the
# host-side GHCR boot residual-zero census (plan 2026-09-24-chore-retire-host-boot-ghcr-legs,
# Guard 1).
#
# HISTORY (why this file exists). The seed image became a PRIVATE GHCR package (#6005/#6011) and
# the seed pull ran ANONYMOUSLY, so every fresh boot 401'd at stage=pull; the fatal emit sourced
# its DSN from doppler, so the failure was invisible too. The fix baked a GHCR login ahead of the
# pull. #8651 made the pull zot-first by bake. #8036 1d then DELETED every GHCR arm: the read PAT
# is revoked (AP-016), so no GHCR login or pull could succeed. zot is the only boot read path.
#
# Asserts:
#   1. (INVERTED by #8036 1d) the zot login precedes the seed pull, and NO `docker login ghcr.io`
#      is left anywhere in cloud-init.yml code.
#   2. the seed-block fatal emit (on_err) prefers the BAKED ${sentry_dsn}.
#   3. server.tf passes sentry_dsn into the cloud-init templatefile AND variables.tf declares it.
#   4. (INVERTED by #8036 1d) the seed pull is ONE bounded zot pull, gated on the zot login; the
#      login-gated GHCR pull arm is gone.
#   G1. Guard 1 census over a DERIVED file set — every cloud-init*.yml a templatefile() call renders
#      (+ soleur-host-bootstrap.sh) and each rendering map: no GHCR credential presented, no
#      pull/create/run (any global flags, `image`/`container` verbs) of anything but a zot-derived
#      ref ($REF with every REF= zot-derived, $ZIREF, the /run/soleur-image-ref sentinel — written
#      only from "$REF" — $IMAGE_REF only after IMAGE_REF="$REF"; $IREF only as a `docker create`
#      after IREF="$ZIREF", never pulled), and no endpoint/registry map value naming ghcr.io. Runs
#      on SOURCE bytes with comment lines stripped (in rendered bytes, IMAGE_REF='${image_name}'
#      becomes a ghcr.io literal, so it is a named exemption, like the IREF= pin carrier; the
#      registry host's run of the upstream '${zot_image}' is the one other, value-bound exemption).
#      A narrower literal rule covers every local.host_script_files member + inngest-bootstrap.sh:
#      no `docker login ghcr.io`, no pull/create/run of a ghcr.io/jikig-ai/ literal.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI="$DIR/cloud-init.yml"
SRV="$DIR/server.tf"
VARS="$DIR/variables.tf"
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "[ok] $1"; }
no() { fail=$((fail + 1)); echo "[FAIL] $1" >&2; }
# Instrument self-test: both helpers must move their counters, or every verdict below is void.
ok "instrument self-test (pass arm)" >/dev/null; no "instrument self-test (fail arm)" 2>/dev/null
[ "$pass" -eq 1 ] && [ "$fail" -eq 1 ] || { printf 'instrument self-test broken\n'; exit 2; }
pass=0; fail=0
code() { grep -vE '^[[:space:]]*#' "$1"; }

# 1. zot login before the seed pull; no GHCR login at all.
# shellcheck disable=SC2016  # intentional: grep for the LITERAL $ZEP/$REF in the YAML.
login_ln=$(grep -nE 'timeout 60 docker login "\$ZEP"' "$CI" | head -1 | cut -d: -f1 || true)
# shellcheck disable=SC2016
pull_ln=$(grep -nE 'timeout 180 docker pull "\$REF"' "$CI" | head -1 | cut -d: -f1 || true)
if [ -n "$login_ln" ] && [ -n "$pull_ln" ] && [ "$login_ln" -lt "$pull_ln" ]; then
  ok "zot docker login (line $login_ln) precedes the seed pull (line $pull_ln)"
else
  no "the zot login must precede the seed pull — login='$login_ln' pull='$pull_ln' (zot has no anonymous read)"
fi
if code "$CI" | _qgrep -E 'docker[[:space:]]+login[^|;&]*ghcr\.io'; then
  no "a 'docker login ghcr.io' is back in cloud-init.yml code (#8036 1d: no host presents a GHCR credential at boot)"
else
  ok "no 'docker login ghcr.io' in cloud-init.yml code (#8036 1d)"
fi

# 1b. RETIRED by #8651 and asserted ABSENT: the seed login must NOT read GHCR_READ_* from doppler
# (tokenless by construction above the terminal `set -a` source, #6985).
if code "$CI" | _qgrep -E 'doppler secrets get GHCR_READ_(USER|TOKEN)'; then
  no "seed login must not fetch GHCR_READ_{USER,TOKEN} via doppler (tokenless by construction, #6985/#8651)"
else
  ok "seed login reads no GHCR_READ_* from doppler (#8651)"
fi

# 2. the fatal emit prefers the baked DSN.
if grep -qE "DSN='\\\$\{sentry_dsn\}'" "$CI"; then
  ok "on_err fatal emit prefers baked \${sentry_dsn} (fires without doppler)"
else
  no "on_err must prefer baked \${sentry_dsn} so the failure signal survives a broken doppler stage"
fi

# 3. templatefile var wired end-to-end (referenced ⟹ must be passed ⟹ must be declared).
if grep -qE '\$\{sentry_dsn\}' "$CI"; then ok "cloud-init.yml references \${sentry_dsn}"; else no "cloud-init.yml must reference \${sentry_dsn}"; fi
if grep -qE '^\s*sentry_dsn\s*=\s*var\.sentry_dsn' "$SRV"; then ok "server.tf passes sentry_dsn to the templatefile"; else no "server.tf must pass sentry_dsn = var.sentry_dsn (else templatefile() fails)"; fi
if grep -qE 'variable "sentry_dsn"' "$VARS"; then ok "variables.tf declares variable \"sentry_dsn\""; else no "variables.tf must declare variable \"sentry_dsn\""; fi

# 4. §1A RETIRED by #8651 and asserted ABSENT.
if code "$CI" | _qgrep -E 'ghcr_login_ok_refetch|until R[UT]=.*doppler'; then
  no "the dead §1A Doppler re-fetch arm is back (tokenless by construction, #6985/#8651)"
else
  ok "no §1A Doppler re-fetch arm (retired by #8651)"
fi
# INVERTED by #8036 1d: exactly ONE seed pull (the zot leg), gated on the zot login; the
# `"$GL" = ok` GHCR arm and its second `timeout 180 docker pull "$REF"` are gone.
npull=$(code "$CI" | grep -cE 'timeout 180 docker pull "\$REF"' || true)
if [ "$npull" = 1 ] && code "$CI" | _qgrep -E '\[ -n "\$REF" \] && \[ \$ZL = ok \] && while .*timeout 180 docker pull "\$REF"' \
   && ! code "$CI" | _qgrep -E '"\$GL"'; then
  ok "the seed pull is one zot pull gated on the zot login; no login-gated GHCR arm (#8036 1d)"
else
  no "the seed pull must be exactly one 'timeout 180 docker pull \"\$REF\"', gated on [ -n \"\$REF\" ] && [ \$ZL = ok ], with no \"\$GL\" GHCR arm (pulls=$npull)"
fi


# ── G1: host-side GHCR boot residual-zero census (Guard 1) ─────────────────────────────────────
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

WORK="$(mktemp -d "${TMPDIR:-/var/tmp}/ghcr-census.XXXXXX")"
assert_fixture_dir "$WORK"
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/census.py" <<'CENSUS_PY'
"""Guard 1 census. argv: <root> <extra boot files, comma-sep> <extra host-literal files, comma-sep>.

The file set is DERIVED, never listed (templatefile-bare-dollar-guard.test.sh's move):
  DERIVED <tpl>             every cloud-init*.yml a templatefile() call in any .tf under <root>
                            renders (path resolved against the calling .tf's directory)
  DERIVED_MAP <tf>:<tpl>    each of those call sites
  HDERIVED <n>              server.tf local.host_script_files entries + the extra host-literal files
Prints one line per finding:
  SCANNED <file> | SCANNED <tf>:<tpl> | HSCANNED <file>   a file / map that was actually read
  LOGINS <n> / PULLS <n> / WRITERS <n> / MAPS <n>        call sites seen (non-vacuity)
  VIOL <file> <rule> <detail>   a violation (content-keyed, never line-numbered, so a mutation's
                                NEW violation is a multiset difference)
Comment lines (first non-blank char '#') are stripped before any rule reads a line; backslash-
continued lines are joined before the docker rules read them (a `docker run -d \\` spans lines).
"""
import os, re, sys

root = sys.argv[1]
extras = [f for f in sys.argv[2].split(",") if f]
hextras = [f for f in sys.argv[3].split(",") if f]
out = []

def strip_hcl_comments(t):
    # Drop # and // line comments and /* */ blocks outside double-quoted strings (the
    # templatefile-bare-dollar-guard.test.sh stripper), so prose is neither a call site nor a key.
    res, i, n, q = [], 0, len(t), False
    while i < n:
        c = t[i]
        if q:
            res.append(c)
            if c == "\\" and i + 1 < n:
                res.append(t[i + 1]); i += 2; continue
            if c == '"':
                q = False
            i += 1; continue
        if c == '"':
            q = True; res.append(c); i += 1; continue
        if c == "#" or t.startswith("//", i):
            j = t.find("\n", i); i = n if j < 0 else j; continue
        if t.startswith("/*", i):
            j = t.find("*/", i + 2); i = n if j < 0 else j + 2; continue
        res.append(c); i += 1
    return "".join(res)

def readable(p):
    return os.path.isfile(p) and os.path.getsize(p) > 0

def code_lines(path):
    return [l.rstrip("\n") for l in open(path, encoding="utf-8", errors="replace")
            if not l.lstrip().startswith("#")]

def logical(lines):
    res, buf = [], ""
    for l in lines:
        r = l.rstrip()
        if r.endswith("\\"):
            buf += r[:-1] + " "
        else:
            res.append(buf + l); buf = ""
    if buf:
        res.append(buf)
    return res

# ── docker call-site parsing ──────────────────────────────────────────────────────────────────
# Global flags may precede the subcommand (`docker --config /tmp/c pull`), and the management
# verbs (`docker image pull`, `docker container create|run`) are the same call.
GLOBAL = r"(?:--?[a-z-]+(?:[= ]\S+)?\s+)*"
LOGIN_RE = re.compile(r"(?<![\w-])docker\s+" + GLOBAL + r"login(?![\w-])")
PULL_RE = re.compile(r"(?<![\w-])docker\s+" + GLOBAL + r"(?:image\s+|container\s+)?(pull|create|run)(?![\w-])")
TOK = re.compile(r"""[ \t]*("[^"]*"|'[^']*'|[^\s;|&)<>]+)""")
BOOL = {"-d", "--detach", "--rm", "-i", "--interactive", "-t", "--tty", "--init", "--read-only",
        "--privileged", "-P", "--publish-all", "-q", "--quiet", "-a", "--all-tags",
        "--disable-content-trust", "--no-healthcheck", "--oom-kill-disable", "--password-stdin"}
LOGIN_VALUE_OPTS = {"-u", "--username", "-p", "--password"}

def operand(line, pos, kind):
    """The first non-option operand after <pos> (the image, or the login registry); None if the
    command has none. An unknown option is assumed to take a value, so a mis-guess can only move
    the pick onto a LATER token — which then must itself pass the zot rules (fail-closed)."""
    toks = []
    while True:
        m = TOK.match(line, pos)
        if not m:
            break
        toks.append(m.group(1)); pos = m.end()
    i = 0
    while i < len(toks):
        t = toks[i]
        if t.startswith("-") and len(t) > 1:
            if "=" in t or t in BOOL or re.fullmatch(r"-[dirtPqa]{2,}", t):
                i += 1
            elif kind == "login":
                i += 2 if t in LOGIN_VALUE_OPTS else 1
            else:
                i += 2
            continue
        return t
    return None

# ── templatefile() maps, derived from every .tf under root ───────────────────────────────────
TF_CALL = re.compile(r'templatefile\(\s*"\$\{path\.module\}/([^"]+)"\s*,\s*\{')
def maps(tfsrc):
    """Yield (template path as written, body) for every templatefile("${path.module}/…", { … })."""
    src = strip_hcl_comments(tfsrc)
    for m in TF_CALL.finditer(src):
        i, depth = m.end(), 1
        while i < len(src) and depth:
            depth += {"{": 1, "}": -1}.get(src[i], 0); i += 1
        yield m.group(1), src[m.end():i - 1]

tfs = []
for d, dirs, files in os.walk(root):
    dirs[:] = sorted(x for x in dirs if x != ".terraform")
    for fn in sorted(files):
        if fn.endswith(".tf"):
            tfs.append(os.path.relpath(os.path.join(d, fn), root))

_defs = {}
def dir_defs(reldir):
    """name -> [rhs, …] for every single-line `name = rhs` in the .tf files of one module dir."""
    if reldir not in _defs:
        acc = {}
        for tf in tfs:
            if os.path.dirname(tf) == reldir:
                for m in re.finditer(r"^\s*(\w+)\s*=\s*(.+?)\s*$", strip_hcl_comments(open(os.path.join(root, tf)).read()), re.M):
                    acc.setdefault(m.group(1), []).append(m.group(2))
        _defs[reldir] = acc
    return _defs[reldir]

def resolve(text, defs, seen, depth=0):
    """<text> plus every local.X it reaches (over-approximated: all same-named assignments)."""
    acc = text
    if depth > 5:
        return acc
    for name in re.findall(r"\blocal\.(\w+)", text):
        if name in seen:
            continue
        seen.add(name)
        for rhs in defs.get(name, []):
            acc += " " + resolve(rhs, defs, seen, depth + 1)
    return acc

KEY_RE = re.compile(r"^\s*(ghcr_read_\w+)\s*=", re.M)
ENTRY_RE = re.compile(r"^\s*(\w+)\s*=\s*(.+?)\s*$", re.M)
derived, dmaps, nmaps = [], [], 0
zot_image_ok = {}
for tf in tfs:
    for rel, body in maps(open(os.path.join(root, tf)).read()):
        nmaps += 1
        tpl = os.path.normpath(os.path.join(os.path.dirname(tf), rel))
        for k in KEY_RE.findall(body):
            out.append("VIOL %s sweep-key[%s->%s]" % (tf, k, tpl))
        if not re.fullmatch(r"cloud-init[^/]*\.yml", tpl):
            continue
        if tpl not in derived:
            derived.append(tpl)
        dmaps.append((tf, tpl))
        out.append("SCANNED %s:%s" % (tf, tpl))  # an empty map ({}, grok-dogfood) has no keys to check
        defs = dir_defs(os.path.dirname(tf))
        for key, val in ENTRY_RE.findall(body):
            # (M1) a registry / endpoint value never names GHCR (literal, or through a local)
            if re.search(r"endpoint|registry", key) and "ghcr.io" in resolve(val, defs, set()):
                out.append("VIOL %s tf-endpoint[%s->%s] %s" % (tf, key, tpl, val))
            if key == "zot_image":
                r = resolve(val, defs, set())
                zot_image_ok[tpl] = "jikig-ai" not in r and "ghcr.io/" in r
out += ["DERIVED " + t for t in derived] + ["DERIVED_MAP %s:%s" % p for p in dmaps]

FORBIDDEN = ["ghcr_read_", "soleur-ghcr-read", "app_ghcr_", "inngest_ghcr_fallback", "echo '${image_name}'"]
ASSIGN_RE = re.compile(r"(?<![A-Za-z0-9_$])(IREF|IMAGE_REF|ZIREF|REF)=(\"[^\"]*\"|'[^']*'|[^\s;]*)")
PIN_RE = re.compile(r"^\s*IREF=ghcr\.io/jikig-ai/soleur-inngest-bootstrap:v\d+\.\d+\.\d+@sha256:[0-9a-f]{64}\s*(#.*)?$")
IMAGE_NAME_OK = re.compile(r"^\s*IMAGE_REF='\$\{image_name\}'\s*$")
GHCR_OK_TOKENS = ("in ghcr.io/*@sha256:*)", "IMAGE_REF#ghcr.io/}")
ZOT_REF_VALUES = re.compile(r'^("\$ZEP/.*|)$')
ZOT_ZIREF_VALUES = re.compile(r'^"\$(ZURL|ZOT_EP)/.*')
WRITER_RE = re.compile(r"(?:>>?|\btee\s+(?:-a\s+)?)\s*/run/soleur-image-ref(?![\w.-])")
WRITER_OK = re.compile(r"""^\s*printf '%s' "\$REF" > /run/soleur-image-ref\s*$""")

logins = pulls = writers = 0
for f in derived + extras:
    p = os.path.join(root, f)
    if not readable(p):
        continue
    out.append("SCANNED " + f)
    last = {}  # last assignment value seen for IREF / IMAGE_REF / REF / ZIREF, in file order
    pins = fwriters = 0
    for line in code_lines(p):
        s = line.strip()
        # (1) forbidden tokens
        for tok in FORBIDDEN:
            if tok in line:
                out.append("VIOL %s forbidden[%s] %s" % (f, tok, s))
        # (4) ${image_name} only as the IMAGE_REF='${image_name}' seed input
        if "${image_name}" in line and not IMAGE_NAME_OK.match(line):
            out.append("VIOL %s image_name %s" % (f, s))
        # (5) ghcr.io on a code line only as the IREF= pin carrier or the seed case pattern
        if PIN_RE.match(line):
            pins += 1
        else:
            rest = line
            for t in GHCR_OK_TOKENS:
                rest = rest.replace(t, "")
            if "ghcr.io" in rest:
                out.append("VIOL %s ghcr.io %s" % (f, s))
        # (7) the sentinel is written from the zot-rewritten $REF, and nothing else
        for _ in WRITER_RE.finditer(line):
            writers += 1; fwriters += 1
            if not WRITER_OK.match(line):
                out.append("VIOL %s image-ref-writer %s" % (f, s))
    for line in logical(code_lines(p)):
        s = " ".join(line.split())
        # (2) every docker login presents a zot credential, never a GHCR one
        for m in LOGIN_RE.finditer(line):
            logins += 1
            a = operand(line, m.end(), "login")
            if a not in ('"$ZEP"', '"$ZOT_EP"'):
                out.append("VIOL %s login-arg[%s] %s" % (f, a, s))
        # (3) pull/create/run sources + assignments, in column order within the line
        events = [(m.start(), "assign", m) for m in ASSIGN_RE.finditer(line)]
        events += [(m.start(), "pull", m) for m in PULL_RE.finditer(line)]
        for _, kind, m in sorted(events, key=lambda e: e[0]):
            if kind == "assign":
                var, val = m.group(1), m.group(2)
                last[var] = val
                if var == "REF" and not ZOT_REF_VALUES.match(val):
                    out.append("VIOL %s ref-assign[%s] %s" % (f, val, s))
                if var == "ZIREF" and not ZOT_ZIREF_VALUES.match(val):
                    out.append("VIOL %s ziref-assign[%s] %s" % (f, val, s))
                continue
            pulls += 1
            verb = m.group(1)
            a = operand(line, m.end(), verb)
            if a in ('"$REF"', '"$ZIREF"', '"$(cat /run/soleur-image-ref)"'):
                continue
            # $IREF is consumed (create) only after IREF="$ZIREF"; it is never PULLED — the only
            # bootstrap pull is of $ZIREF, and a pull of $IREF is how a GHCR-seeded ref (the pin
            # carrier, or a branch that skipped the reassign) reaches the registry.
            if a == '"$IREF"' and verb == "create" and last.get("IREF") == '"$ZIREF"':
                continue
            if a == '"$IMAGE_REF"' and last.get("IMAGE_REF") == '"$REF"':
                continue
            # NAMED EXEMPTION: the registry host cannot pull zot from zot. Its `docker run` of the
            # upstream zot image is allowed only while that map value resolves to a digest-pinned
            # third-party GHCR ref and never to a jikig-ai one.
            if a == "'${zot_image}'" and verb == "run" and zot_image_ok.get(f):
                continue
            out.append("VIOL %s pull-src[%s:%s] %s" % (f, verb, a, s))
    # (6) the bump bot's contract: an inngest-bearing template carries exactly 2 refs (whole file,
    # comments included — a comment quoting a full ref would make the bot refuse) and 1 carrier
    text = open(p).read()
    if "soleur-inngest-bootstrap:v" in text or f in ("cloud-init.yml", "cloud-init-inngest.yml"):
        n = len(re.findall(r"jikig-ai/soleur-inngest-bootstrap:v[0-9]", text))
        if n != 2:
            out.append("VIOL %s bootstrap-ref-count[%d!=2]" % (f, n))
        if pins != 1:
            out.append("VIOL %s pin-carrier-count[%d!=1]" % (f, pins))
    # (7b) a file that reads the sentinel writes it exactly once
    if re.search(r"^(?!\s*#).*cat /run/soleur-image-ref", text, re.M) and fwriters != 1:
        out.append("VIOL %s image-ref-writer-count[%d!=1]" % (f, fwriters))

# ── host-literal rule: every baked host script (server.tf local.host_script_files) + extras ──
hs = []
srv = os.path.join(root, "server.tf")
if readable(srv):
    m = re.search(r"\bhost_script_files\s*=\s*\[(.*?)\]", strip_hcl_comments(open(srv).read()), re.S)
    if m:
        hs = re.findall(r'"([^"]+)"', m.group(1))
out.append("HDERIVED %d" % (len(hs) + len(hextras)))
for f in hs + hextras:
    p = os.path.join(root, f)
    if not readable(p):
        continue
    out.append("HSCANNED " + f)
    for line in logical(code_lines(p)):
        s = " ".join(line.split())
        for m in LOGIN_RE.finditer(line):
            a = (operand(line, m.end(), "login") or "").strip("\"'")
            if a.startswith("ghcr.io"):
                out.append("VIOL %s host-login-ghcr %s" % (f, s))
        for m in PULL_RE.finditer(line):
            a = operand(line, m.end(), m.group(1)) or ""
            seg = re.split(r"[;|&]", line[m.end():], maxsplit=1)[0]
            if "ghcr.io/jikig-ai/" in a or "ghcr.io/jikig-ai/" in seg:
                out.append("VIOL %s host-pull-ghcr[%s] %s" % (f, m.group(1), s))

out += ["LOGINS %d" % logins, "PULLS %d" % pulls, "WRITERS %d" % writers, "MAPS %d" % nmaps]
print("\n".join(out))
CENSUS_PY

EXTRA_BOOT="soleur-host-bootstrap.sh"   # baked, run by the seed block; not a templatefile render
EXTRA_HOST="inngest-bootstrap.sh"       # extracted from the inngest image and run as root at boot
MIN_DERIVED=5                           # cloud-init{,-inngest,-registry,-git-data,-grok-dogfood}.yml
MIN_HOST=45                             # local.host_script_files has 49 entries (+1 extra) today
census() { python3 "$WORK/census.py" "$1" "${2-$EXTRA_BOOT}" "${3-$EXTRA_HOST}"; }
viols() { grep '^VIOL ' || true; }

# dispatch_ok <census output>: scanned EXACTLY the derived set (every cloud-init*.yml a
# templatefile() renders + the baked bootstrap + each rendering map) and every derived host script,
# and found real call sites — never "0 scanned, 0 found" (a misspelled path, a vanished file or an
# empty list must go RED, not green).
dispatch_ok() {
  local c="$1" der exp sc nd hd hs lg pl wr mp
  der=$(sed -n 's/^DERIVED //p' <<<"$c" | sort)
  exp=$( { printf '%s\n' "$der" "$EXTRA_BOOT"; sed -n 's/^DERIVED_MAP //p' <<<"$c"; } | { grep -v '^$' || true; } | sort)
  sc=$(sed -n 's/^SCANNED //p' <<<"$c" | sort)
  nd=$(grep -c . <<<"$der" || true)
  hd=$(sed -n 's/^HDERIVED //p' <<<"$c"); hs=$(grep -c '^HSCANNED ' <<<"$c" || true)
  lg=$(sed -n 's/^LOGINS //p' <<<"$c"); pl=$(sed -n 's/^PULLS //p' <<<"$c")
  wr=$(sed -n 's/^WRITERS //p' <<<"$c"); mp=$(sed -n 's/^MAPS //p' <<<"$c")
  DWHY="derived=$nd scanned=$(grep -c . <<<"$sc" || true)/expected=$(grep -c . <<<"$exp" || true) host=${hs}/${hd:-?} logins=${lg:-?} pulls=${pl:-?} writers=${wr:-?} maps=${mp:-?}"
  [ -n "$sc" ] && [ "$sc" = "$exp" ] && [ "$nd" -ge "$MIN_DERIVED" ] \
    && grep -qx cloud-init.yml <<<"$der" && grep -qx cloud-init-inngest.yml <<<"$der" \
    && [ "${hd:-0}" -ge "$MIN_HOST" ] && [ "$hs" = "${hd:-x}" ] \
    && [ "${lg:-0}" -ge 1 ] && [ "${pl:-0}" -ge 1 ] && [ "${wr:-0}" -ge 1 ] && [ "${mp:-0}" -ge 4 ]
}

C=$(census "$DIR")
if dispatch_ok "$C"; then ok "G1 dispatch: census scanned exactly the derived boot set + maps + host scripts ($DWHY)"
else no "G1 dispatch: census must scan exactly the derived cloud-init*.yml renders + $EXTRA_BOOT + their maps, every host script, and find >=1 login/pull/writer, >=4 maps ($DWHY)"; fi
# One row per scanned boot file and per rendering .tf (derived, so a new template gets its own row).
for f in $(sed -n 's/^DERIVED //p' <<<"$C") "$EXTRA_BOOT" $(sed -n 's/^DERIVED_MAP \([^:]*\):.*/\1/p' <<<"$C" | sort -u); do
  v=$(viols <<<"$C" | grep -F "VIOL $f " || true)
  if [ -z "$v" ]; then ok "G1: $f — 0 host-side GHCR boot residuals (login args zot-only, pull/create/run sources zot-derived, endpoints GHCR-free)"
  else no "G1: $f carries host-side GHCR boot residuals:"; printf '        %s\n' "$v" >&2; fi
done
v=$(viols <<<"$C" | grep -E '^VIOL \S+ host-(login|pull)-ghcr' || true)
if [ -z "$v" ]; then ok "G1: no baked host script (local.host_script_files + $EXTRA_HOST) logs in to ghcr.io or pulls/creates/runs a ghcr.io/jikig-ai/ literal"
else no "G1: a baked host script reaches GHCR:"; printf '        %s\n' "$v" >&2; fi
v=$(viols <<<"$C" | grep -F ' sweep-key[' || true)
if [ -z "$v" ]; then ok "G1: no templatefile() map anywhere in the infra root passes a ghcr_read_* key"
else no "G1: a templatefile() map passes a GHCR credential:"; printf '        %s\n' "$v" >&2; fi

# ── G1 mutation matrix (plan Guard 1). Each row mutates a SANDBOX copy and must add at least one
# NEW violation (multiset difference against the unmutated census) — so a row stays meaningful
# even while another file's baseline is red. Row 6 is the must-PASS harness row.
SB="$WORK/sb"
assert_fixture_dir "$SB"
# The sandbox holds everything the census reads: every top-level non-test file + every .tf.
sandbox() {
  assert_fixture_dir "$SB"
  assert_fixture_dir "$DIR"
  rm -rf "$SB"; mkdir -p "$SB"
  find "$DIR" -maxdepth 1 -type f ! -name '*.test.*' -exec cp -t "$SB/" {} +
  (cd "$DIR" && find . -name '*.tf' -not -path '*/.terraform/*' -print0 | xargs -0 -I{} cp --parents {} "$SB/")
}
sandbox
BASE=$(census "$SB" | viols | sort)
[ "$BASE" = "$(census "$DIR" | viols | sort)" ] || { echo "[HARNESS] the sandbox census differs from the live census — the sandbox is missing an input" >&2; exit 2; }
new_viols() { comm -13 <(printf '%s\n' "$BASE") <(census "$SB" | viols | sort) | grep -v '^$' || true; }
# landed <file> : the mutation actually changed the sandbox file (else the row is a harness fault)
landed() { if cmp -s "$DIR/$1" "$SB/$1"; then echo "[HARNESS] mutation did not land in $1" >&2; exit 2; fi; }
mrow() {  # <label> <file>
  landed "$2"
  local n s; n=$(new_viols)
  # Show the mutated file's own new violation first when it has one (a local.* over-approximation
  # can also flag a sibling .tf that reads the same name).
  s=$(grep -F "VIOL $2 " <<<"$n" | head -1 || true); [ -n "$s" ] || s=$(head -1 <<<"$n")
  if [ -n "$n" ]; then ok "G1 mutation RED: $1 — $(cut -c1-110 <<<"$s")"
  else no "G1 mutation SURVIVED: $1"; fi
  sandbox
}
py_edit() {  # <file> <python expr over s>; an anchor that is not there is a HARNESS fault (exit 2)
  python3 - "$SB/$1" "$2" <<'PY' || { echo "[HARNESS] mutation anchor not found in $1" >&2; exit 2; }
import sys
p, expr = sys.argv[1], sys.argv[2]
s = open(p).read()
o = eval(expr, {"s": s, "chr": chr})
open(p, "w").write(o)
PY
}
py_sub() {  # <file> <old> <new> : literal, first occurrence; a missing anchor is a HARNESS fault
  python3 - "$SB/$1" "$2" "$3" <<'PY' || { echo "[HARNESS] mutation anchor not found in $1" >&2; exit 2; }
import sys
p, a, b = sys.argv[1:4]
s = open(p).read()
if a not in s:
    sys.exit(3)
open(p, "w").write(s.replace(a, b, 1))
PY
}
assert_fixture_dir "$SB"
# 1: a GHCR login restored in the inngest template (after a compliant web file)
printf "    printf '%%s' \"\$T\" | docker login ghcr.io -u \"\$U\" --password-stdin\n" >> "$SB/cloud-init-inngest.yml"
mrow "1 docker login ghcr.io restored in cloud-init-inngest.yml" cloud-init-inngest.yml
# 2: || echo '${image_name}' restored on ONE of the three sentinel reads (the second member)
py_edit cloud-init.yml "(lambda k: s[:k] + s[k:].replace('\"\$(cat /run/soleur-image-ref)\"', '\"\$(cat /run/soleur-image-ref 2>/dev/null || echo ' + chr(39) + '\${image_name}' + chr(39) + ')\"', 1))(s.index('\"\$(cat /run/soleur-image-ref)\"') + 1)"
mrow "2 || echo '\${image_name}' restored on the 2nd of 3 sentinel reads" cloud-init.yml
# 3: ghcr_read_token back in inngest-host.tf's templatefile map only
py_edit inngest-host.tf "s.replace('templatefile(\"\${path.module}/cloud-init-inngest.yml\", {\n', 'templatefile(\"\${path.module}/cloud-init-inngest.yml\", {\n    ghcr_read_token = var.ghcr_read_token\n', 1)"
mrow "3 ghcr_read_token restored in inngest-host.tf's templatefile map" inngest-host.tf
# 4: the GHCR fallback put back as a pull of the pin carrier BEFORE IREF=\"\$ZIREF\" (web colocated block)
py_edit cloud-init.yml "(lambda i: s[:s.index(chr(10), i) + 1] + '    if ! docker pull \"\$ZIREF\"; then docker pull \"\$IREF\"; fi' + chr(10) + s[s.index(chr(10), i) + 1:])(s.index('    IREF=ghcr.io/'))"
mrow "4 pull of the IREF pin carrier before IREF=\"\$ZIREF\" (web colocated block)" cloud-init.yml
# 4b: same, second site: the dedicated inngest template
py_edit cloud-init-inngest.yml "(lambda i: s[:s.index(chr(10), i) + 1] + '    if ! docker pull \"\$ZIREF\"; then docker pull \"\$IREF\"; fi' + chr(10) + s[s.index(chr(10), i) + 1:])(s.index('    IREF=ghcr.io/'))"
mrow "4b pull of the IREF pin carrier before IREF=\"\$ZIREF\" (dedicated inngest template)" cloud-init-inngest.yml
# 5: dispatch rows — a misspelled path, a vanished input, and an empty root must never read as
# "0 found, green"
sandbox
if dispatch_ok "$(census "$SB" "soleur-host-bootstrp.sh")"; then no "G1 mutation SURVIVED: 5 misspelled extra boot-file path"
else ok "G1 mutation RED: 5 misspelled extra boot-file path ($DWHY)"; fi
mkdir -p "$WORK/empty"; assert_fixture_dir "$WORK/empty"
if dispatch_ok "$(census "$WORK/empty" "" "")"; then no "G1 mutation SURVIVED: 5b empty root and empty file lists"
else ok "G1 mutation RED: 5b empty root and empty file lists ($DWHY)"; fi
py_sub zot-registry.tf 'templatefile("${path.module}/cloud-init-registry.yml"' 'templatefile("${path.module}/cloud-init-regsitry.yml"'
landed zot-registry.tf
if dispatch_ok "$(census "$SB")"; then no "G1 mutation SURVIVED: 5c a templatefile() call naming a template that does not exist"
else ok "G1 mutation RED: 5c a templatefile() call naming a template that does not exist ($DWHY)"; fi
sandbox
rm -f "$SB/ci-deploy.sh"
if dispatch_ok "$(census "$SB")"; then no "G1 mutation SURVIVED: 5d a host_script_files entry that is not on disk"
else ok "G1 mutation RED: 5d a host_script_files entry that is not on disk ($DWHY)"; fi
sandbox
# 6 (must-PASS harness row): a comment naming the retired call form is not a call
printf '    # docker login ghcr.io was removed by #8036 1d\n' >> "$SB/cloud-init.yml"
landed cloud-init.yml
n=$(new_viols)
if [ -z "$n" ]; then ok "G1 harness PASS: 6 a comment line naming 'docker login ghcr.io' is stripped before the census"
else no "G1 harness: 6 a comment line was counted as code: $n"; fi
sandbox
# 7: a ghcr.io occurrence that is neither the pin carrier nor the seed case pattern
printf '    echo "fallback: ghcr.io/jikig-ai/soleur-web-platform"\n' >> "$SB/soleur-host-bootstrap.sh"
mrow "7 a stray ghcr.io code line in soleur-host-bootstrap.sh" soleur-host-bootstrap.sh
# 8: a third soleur-inngest-bootstrap ref (a re-homed comment quoting the full ref) breaks the bump bot
printf '  # was ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.1.37\n' >> "$SB/cloud-init.yml"
mrow "8 a comment quoting a 3rd full soleur-inngest-bootstrap ref (bump bot expects exactly 2)" cloud-init.yml
# 9-11: the GHCR-seeded $IMAGE_REF (IMAGE_REF='${image_name}' is the ghcr.io ref once rendered)
# pulled through a call form the pre-review census did not parse: a management verb, `run`, and
# a global flag before the subcommand. None carries a ghcr.io literal, so only the pull rule sees it.
IMG_ANCHOR="    IMAGE_REF='\${image_name}'
"
py_sub cloud-init.yml "$IMG_ANCHOR" "$IMG_ANCHOR    docker image pull \"\$IMAGE_REF\"
"
mrow "9 docker image pull \"\$IMAGE_REF\" after IMAGE_REF='\${image_name}'" cloud-init.yml
py_sub cloud-init.yml "$IMG_ANCHOR" "$IMG_ANCHOR    docker run --rm \"\$IMAGE_REF\" true
"
mrow "10 docker run --rm \"\$IMAGE_REF\" true after IMAGE_REF='\${image_name}'" cloud-init.yml
py_sub cloud-init.yml "$IMG_ANCHOR" "$IMG_ANCHOR    docker --config /tmp/c pull \"\$IMAGE_REF\"
"
mrow "11 docker --config /tmp/c pull \"\$IMAGE_REF\" (global flag before the verb)" cloud-init.yml
# 12: the sentinel writer records the un-rewritten GHCR ref instead of the zot $REF
py_sub cloud-init.yml "printf '%s' \"\$REF\" > /run/soleur-image-ref" "printf '%s' \"\$IMAGE_REF\" > /run/soleur-image-ref"
mrow "12 the /run/soleur-image-ref writer records \"\$IMAGE_REF\" instead of \"\$REF\"" cloud-init.yml
# 13: a registry endpoint value in a rendering map set to GHCR (literal)
py_sub server.tf "    registry_endpoint = local.registry_endpoint
" "    registry_endpoint = \"ghcr.io\"
"
mrow "13 server.tf's templatefile map sets registry_endpoint = \"ghcr.io\"" server.tf
# 13b: the same through the local it reads (zot_registry_endpoint = local.registry_endpoint)
py_sub zot-registry.tf '  registry_endpoint = "${local.registry_private_ip}:5000"' '  registry_endpoint = "ghcr.io"'
mrow "13b local.registry_endpoint (read by inngest-host.tf's zot_registry_endpoint) set to \"ghcr.io\"" zot-registry.tf
# 14: a GHCR login in a DERIVED-only template (cloud-init-registry.yml was never in the old list)
printf "    printf '%%s' \"\$T\" | docker login ghcr.io -u \"\$U\" --password-stdin\n" >> "$SB/cloud-init-registry.yml"
mrow "14 docker login ghcr.io added to cloud-init-registry.yml (a derived, previously unlisted template)" cloud-init-registry.yml
# 15: a GHCR login in a baked host script (the narrower host-literal rule; not a boot file)
printf 'printf %%s "$T" | docker login ghcr.io -u "$U" --password-stdin\n' >> "$SB/ci-deploy.sh"
mrow "15 docker login ghcr.io added to ci-deploy.sh (a local.host_script_files member)" ci-deploy.sh
# 15b: a pull of a ghcr.io/jikig-ai/ literal in a host script, behind a global flag
printf 'docker --config /tmp/c pull ghcr.io/jikig-ai/soleur-web-platform:latest\n' >> "$SB/disk-monitor.sh"
mrow "15b docker --config … pull ghcr.io/jikig-ai/… added to disk-monitor.sh" disk-monitor.sh
# 16: the registry host's zot-image exemption is value-bound, not name-bound
py_sub zot-registry.tf '    zot_image     = local.zot_image' '    zot_image     = "ghcr.io/jikig-ai/soleur-web-platform:latest"'
mrow "16 the registry map's zot_image repointed at a ghcr.io/jikig-ai/ ref (exemption revoked)" zot-registry.tf

# Floor at the MEASURED count (45, PR #8708 review; the suite had 26 rows and no floor before): rows are derived from the file set, so a
# derivation that silently matched less would also shrink the row count. Reported with printf +
# exit DIRECTLY, never through ok()/no() -- the floor polices those.
MIN_ASSERTIONS=45
if (( pass + fail < MIN_ASSERTIONS )); then
  printf '[FATAL] only %d assertions ran; floor is %d -- the suite was gutted\n' "$((pass + fail))" "$MIN_ASSERTIONS" >&2
  exit 1
fi
echo "=== cloud-init-ghcr-seed-login: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
