#!/usr/bin/env bash
#
# (#9294 G1, ADR-241 D1 amendment, PR-0) Guard 1a: the deploy-channel trio NAME-REFERENCE census, a
# regression ratchet. It is NOT a reachability proof.
#
# PROPERTY. The three deploy-channel credentials -- WEBHOOK_DEPLOY_SECRET and the Cloudflare Access
# client pair (CF_ACCESS_CLIENT_ID, CF_ACCESS_CLIENT_SECRET), plus every name in their token family
# (WEBHOOK_DEPLOY_SECRET_NEXT, TF_VAR_ spellings, lower-case tfvars spellings) -- are named, in code,
# only by (file, name) keys that have a row in tests/scripts/trio-baseline.tsv, and that file only
# ratchets forward. Together the three authenticate /hooks/infra-config on web-1 (a path that can
# replace ci-deploy.sh and read the host credential file), so a consumer nobody reviewed is the
# defect: P5 of the plan.
#
# WHAT THIS DOES NOT SEE (Known blind spots, also recorded in the baseline header and ADR-241). Reach
# WITHOUT naming is closed by deleting the Tier-A and repo-secret copies and by the main-only
# environment policy (sibling census G1b-G1d, G1h), not by this census: `doppler run -c prd_terraform`
# that injects the whole project, `secrets: inherit`, `toJSON(secrets)`, computed names
# (`secrets[format(...)]`), callers of a baselined script that fetches the trio itself, and host-side
# readers of the rendered hooks.json. Acceptance criterion 1 is therefore "zero tier-a rows plus the
# owner-run deletion postcondition", not "the census is green".
#
# WHY A SEPARATE SUITE rather than rows in the sibling Tier-B census (tests/scripts/test-infra-privileged-tier-census). That census derives
# Tier-B-ness from reads of TIER_B_NAMES through ONE read shape (`doppler secrets get <name> ...
# prd_terraform`); the `secrets.X` and env-passthrough shapes go through ENV_SECRETS. Adding the trio
# to TIER_B_NAMES turns its row G1g red on the live tree, and the repo-secret reads are not
# classified at all. The trio moves into TIER_B_NAMES in the PRs that migrate those consumers. This
# suite does single-source the Tier-B ENVIRONMENT set from that census (E1).
#
# POPULATION (F-A). `git ls-files -z --cached --others --exclude-standard` (a git failure is FAIL
# SETUP), minus the top-level prefixes knowledge-base/ and docs/, binaries (a NUL in the first 8 KiB),
# symlinks, and this suite's own two files by exact path. `.md` outside those prefixes IS scanned (the
# ship/postmerge/qa skill docs read the trio from Tier A). Whole-line `#` and `//` comments are
# filtered for code and NOT for `.md`. A scanned file that exists but cannot be read is a hard FAIL
# (T8). A structural test class is exempt from the name rule and still needs a row if it holds a
# direct-store read shape: a directory segment in {test, tests, __tests__, fixtures}, a `.test.<ext>`
# or `.spec.<ext>` suffix, or `.tftest.hcl`. Nothing under .github/ is ever exempt.
#
# NAMES (F-A3). Token family, case-insensitive:
#   (?<![A-Za-z0-9_])(?:TF_VAR_)?(STEM)(?:_[A-Za-z0-9]+)*(?![A-Za-z0-9_])
# over STEMS = WEBHOOK_DEPLOY_SECRET, CF_ACCESS_CLIENT_ID, CF_ACCESS_CLIENT_SECRET. The row name is the
# upper-cased token with TF_VAR_ stripped. ALIAS:ACCESS_SERVICE_TOKEN_CLIENT_ID|SECRET rows cover the
# Terraform spellings of the Access token (and `terraform output -raw`); FALLBACK:<NAME> rows cover a
# `|| doppler secrets get <other credential>` on a logical (continuation-joined) line that names the
# trio. The stems are pinned by the `@stems` record in the baseline (T6).
#
# CLASSES (F-C). Every row carries a class the scanner COMPUTES and the baseline must agree with (T5c):
#   tier-a  a file with a direct-store read shape (`${{ secrets.<NAME> }}`, `doppler secrets get|download
#           ... <NAME>`, `doppler run` against prd_terraform, `terraform output -raw
#           access_service_token_client_*`), or a workflow naming the trio in a job without a Tier-B
#           environment, or any composite action (no job to prove an environment), FALLBACK:*, ALIAS:*.
#           Expiry required; TERMINAL: the end state is zero tier-a rows.
#   tier-b  a workflow with no read shape where EVERY job naming the trio declares an `environment:`
#           whose arms are all in the Tier-B set. Expiry `-`.
#   sink    a non-workflow file with no read shape (variables.tf, server.tf, hooks.json.tmpl, ...).
#           Expiry `-`.
#
# RATCHET (F-B, T4). Against the base copy of the baseline: tag fixed; class forward-only (tier-a ->
# tier-b|sink); expiry never later (re-date path: ADR-241 line `Re-date: <date> ... Ruled by <owner>` in a
# baseline/ADR/plan-only diff); a NEW (file, name) key is admitted only by an `@allow` line that exists at
# the base and is deleted by the same diff; renames (>= 90%) carry their rows. The base FAILS CLOSED: an
# unresolved ref, or a baseline absent at a base where this suite exists, is RED. The introduction arm is
# legitimate only while this suite is absent at the base.
#
# EXPIRY (F-D). Tier-a rows: strict ISO date, at most MAX_EXPIRY, compared as dates. Hard RED only on a
# blocking event that touches a row's file, the baseline, ADR-241 or the plan; on a main push, schedule,
# merge-queue gate or dispatch-on-main it is a non-blocking T3m annotation (ci_not_green must not stop
# tenant deploys). Within 21 days: a non-failing T3w row and a ::warning::.
#
# Seams: TRIO_REPO_ROOT (the tree the scan reads), TRIO_BASELINE, TRIO_BASE_REF (the ref merged-base'd
# against; default refs/remotes/origin/main), TRIO_TODAY (default today, UTC), TRIO_ALLOW_NO_BASE=1
# (local only, loud banner). All four seams MUST be unset under GITHUB_ACTIONS=true (FAIL SETUP).
#
# Harness conventions (ADR-193): the instrument self-test drives both helpers once; every mutation
# copies a PRISTINE fixture (a git-init'd copy of a synthetic tree, never the live tree), asserts the edit
# LANDED, then requires the NAMED row RED (a crash or a missing row is UNRESOLVED, not a kill); the
# control run is asserted all-green first; the mutant runner itself is proven by a no-op mutant that it
# must score FAIL; floors report with printf + exit, never through the helpers they backstop.
#
# Run: bash tests/scripts/test-trio-baseline-census.sh [--emit-baseline | --seams-check]

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
SUITE="$DIR/$(basename "${BASH_SOURCE[0]}")"
REPODIR="${TRIO_REPO_ROOT:-$ROOT}"
BASELINE="${TRIO_BASELINE:-$ROOT/tests/scripts/trio-baseline.tsv}"
TODAY="${TRIO_TODAY:-$(date -u +%F)}"
SUITE_REL="tests/scripts/test-trio-baseline-census.sh"
BASELINE_REL="tests/scripts/trio-baseline.tsv"
# Spelled in two parts on purpose: this suite extracts ONE constant from the sibling census and never runs it or
# inherits its reads, and the dropped-consumer ratchet follows a literal script path one hop into that script.
SIBLING_REL="tests/scripts/test-infra-privileged-tier-census"".sh"
ADR_REL="knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md"
PLAN_REL="knowledge-base/project/plans/2026-10-15-feat-g1-webhook-trio-tier-b-plan.md"

passes=0; fails=0; MUTANTS_RUN=0
FAILURES=()
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAILURES+=("$1"); fails=$((fails + 1)); printf '  FAIL %s\n       %s\n' "$1" "${2:-}"; }

# Instrument self-test (ADR-193): both helpers must move their counters, or nothing below is
# evidence of anything. Declared AFTER the helpers and BEFORE the first real row.
_st="$( (pass x >/dev/null; fail y >/dev/null; printf '%s %s %s' "$passes" "$fails" "${#FAILURES[@]}") )"
if [ "$_st" != "1 1 1" ]; then
  printf 'FAIL INSTRUMENT: pass()/fail() self-test read "%s", expected "1 1 1"\n' "$_st" >&2; exit 1
fi

python3 -c 'import re, os, sys, datetime, subprocess, ast, json, yaml' 2>/dev/null || { printf 'FAIL SETUP: python3 (with the yaml module) unavailable\n' >&2; exit 1; }

# F-B: the seams are test hooks. In CI they must be unset, or a workflow-level env edit could disarm the guard.
if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
  for _seam in TRIO_TODAY TRIO_BASE_REF TRIO_BASELINE TRIO_REPO_ROOT; do
    if [ -n "${!_seam+x}" ]; then
      printf 'FAIL SETUP: %s is set under GITHUB_ACTIONS=true; the TRIO_* seams are local test hooks and must be unset in CI\n' "$_seam" >&2
      exit 1
    fi
  done
fi
if [ "${1:-}" = "--seams-check" ]; then printf 'SEAMS OK\n'; exit 0; fi

# Canonical copy of plugins/soleur/test/test-helpers.sh's guard (the fixture-dir-operand-assert
# suite pins every tracked copy byte-identical).
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

T="$(mktemp -d "${TMPDIR}/trio-baseline-census.XXXXXX")" || { printf 'FAIL SETUP: mktemp\n' >&2; exit 1; }
_REACHED_VERDICT=""; _rc=0
trap '_rc=$?; rm -rf "$T"; if [ "$_rc" -eq 0 ] && [ -z "$_REACHED_VERDICT" ]; then printf "FAIL: suite exited 0 before its verdict\n" >&2; exit 1; fi' EXIT
assert_fixture_dir "$T"
mkdir -p "$T/mut" || { printf 'FAIL SETUP: mkdir %s/mut\n' "$T" >&2; exit 1; }


cat > "$T/trio.py" <<'PY'
import sys, os, re, datetime, argparse, subprocess, json, ast
try:
    import yaml
except Exception:
    sys.stderr.write("FAIL SETUP: python3 yaml module unavailable\n")
    sys.exit(3)

ap = argparse.ArgumentParser()
ap.add_argument("--repo", required=True)
ap.add_argument("--baseline", required=True)
ap.add_argument("--base-dir", default="")    # the shell's base-resolution record; "" = no ratchet record at all
ap.add_argument("--today", required=True)
ap.add_argument("--mode", default="check")   # check | emit
ap.add_argument("--event-name", default="")  # GITHUB_EVENT_NAME ("" = local)
ap.add_argument("--event-ref", default="")   # GITHUB_REF
ap.add_argument("--envs", default="")        # a comma list overriding the Tier-B environment set (fixtures)
ap.add_argument("--sibling", default="")     # the sibling census file the Tier-B environment set is extracted from
ap.add_argument("--ann", default="")         # file receiving ::warning:: / ::error:: annotations
a = ap.parse_args()
REPO = a.repo

# ── constants ────────────────────────────────────────────────────────────────────────────
STEMS = ["WEBHOOK_DEPLOY_SECRET", "CF_ACCESS_CLIENT_ID", "CF_ACCESS_CLIENT_SECRET"]
PENDING_ENVS = {"deploy-channel", "inngest-cutover"}
MAX_EXPIRY = datetime.date(2027, 3, 31)
ROW_EXPIRY = "2026-11-30"
WARN_DAYS = 21
SUITE_REL = "tests/scripts/test-trio-baseline-census.sh"
BASELINE_REL = "tests/scripts/trio-baseline.tsv"
ADR_REL = "knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md"
PLAN_REL = "knowledge-base/project/plans/2026-10-15-feat-g1-webhook-trio-tier-b-plan.md"
ROOTS = [".github/workflows", ".github/actions", ".github/scripts", "scripts", "plugins", "apps/web-platform"]
# The knowledge base is excluded from the scan and never read (the two governed files this suite diffs by path are
# ADR_REL and PLAN_REL below); the prefix is spelled in two parts so the dropped-consumer ratchet, which tokenises
# the directory name as a read, sees only the real, declared reads.
EXCLUDED_PREFIXES = ("knowledge" + "-base/", "docs/")
EXEMPT_DIRS = {"test", "tests", "__tests__", "fixtures"}
# The consumer groups of the plan (single-sourced there; this map labels rows and keys T5/T7).
PR3 = {".github/workflows/web-platform-release.yml", ".github/workflows/canary-status.yml"}
PR4_PREFIX = (".github/workflows/cutover-inngest.yml", ".github/workflows/deploy-inngest-image.yml",
              ".github/workflows/restart-inngest-server.yml", ".github/workflows/scheduled-inngest-health.yml",
              ".github/workflows/scheduled-followthrough-sweeper.yml", "scripts/followthroughs/",
              "apps/web-platform/scripts/github-app-key-status.sh")

def group_of(rel):
    if rel in PR3:
        return "PR-3"
    if rel.startswith(PR4_PREFIX):
        return "PR-4"
    return "PR-2"

ISO = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}")
def parse_iso(s):
    if not ISO.fullmatch(s):
        return None
    try:
        return datetime.date.fromisoformat(s)
    except ValueError:
        return None

TODAY = parse_iso(a.today)
if TODAY is None:
    sys.stderr.write("FAIL SETUP: --today %r is not a strict ISO date\n" % a.today)
    sys.exit(3)

out = []
def check(name, cond, detail=""):
    out.append("%s\t%s\t%s" % ("ok" if cond else "FAIL", name.replace("\t", " ").replace("\n", " "),
                              str(detail)[:700].replace("\t", " ").replace("\n", " ")))
anns = []

# ── the name family ──────────────────────────────────────────────────────────────────────
STEM_ALT = "|".join(re.escape(s) for s in sorted(STEMS, key=len, reverse=True))
FAM_CORE = r"(?:TF_VAR_)?(?:" + STEM_ALT + r")(?:_[A-Za-z0-9]+)*(?![A-Za-z0-9_])"
FAM = re.compile(r"(?<![A-Za-z0-9_])" + FAM_CORE, re.I)
FAM_FULL = re.compile(FAM_CORE, re.I)
ROWNAME = re.compile(r"(?:" + STEM_ALT + r")(?:_[A-Z0-9]+)*")
def row_name(tok):
    n = tok.upper()
    return n[len("TF_VAR_"):] if n.startswith("TF_VAR_") else n
ALIAS_A = re.compile(r"access_service_token_client_(id|secret)", re.I)
ALIAS_B = re.compile(r"cloudflare_zero_trust_access_service_token\.[A-Za-z0-9_]+\.client_(id|secret)", re.I)
ALIAS_NAMES = {"ALIAS:ACCESS_SERVICE_TOKEN_CLIENT_ID", "ALIAS:ACCESS_SERVICE_TOKEN_CLIENT_SECRET"}
FALLBACK = re.compile(r"\|\|\s*doppler\s+secrets\s+get\s+([A-Za-z_][A-Za-z0-9_]*)")
HCLOUD = re.compile(r"(?<![A-Za-z0-9_])HCLOUD_TOKEN(?![A-Za-z0-9_])", re.I)
CONT = re.compile(r"\\[ \t]*\n[ \t]*")

# direct-store read shapes (F-A2 / F-C)
R_SECRETS = re.compile(r"secrets\s*(?:\.\s*|\[\s*['\"])(" + FAM_CORE + ")", re.I)
R_GET_HEAD = re.compile(r"doppler[ \t]+(?:[^\s;|&)]+[ \t]+)*?secrets[ \t]+(?:get|download)\b", re.I)
R_RUN = re.compile(r"doppler\b[^\n]*?\brun\b[^\n]*?prd_terraform", re.I)
R_TFOUT = re.compile(r"terraform\b[^\n]*?\boutput\b[^\n]*?-raw\s+[\"']?access_service_token_client_(id|secret)", re.I)

def code_text(rel, text):
    if rel.lower().endswith(".md"):
        return text
    keep = []
    for ln in text.split("\n"):
        s = ln.lstrip()
        if s.startswith("#") or s.startswith("//"):
            continue
        keep.append(ln)
    return "\n".join(keep)

def is_exempt(rel):
    if rel.startswith(".github/"):
        return False
    parts = rel.split("/")
    if any(p in EXEMPT_DIRS for p in parts[:-1]):
        return True
    base = parts[-1]
    return bool(re.search(r"\.(test|spec)\.[A-Za-z0-9]+$", base)) or base.endswith(".tftest.hcl")

def excluded_path(rel):
    return rel in (SUITE_REL, BASELINE_REL) or rel.startswith(EXCLUDED_PREFIXES) or is_exempt(rel)

PREFILTER = [x.lower() for x in STEMS] + ["access_service_token_client_", "cloudflare_zero_trust_access_service_token"]
def analyze(rel, text):
    low = text.lower()
    if not any(x in low for x in PREFILTER):
        return {"names": set(), "aliases": set(), "reads": set(), "gen_read": False, "alias_reads": set(),
                "fallbacks": set(), "hcloud": False}
    code = code_text(rel, text)
    joined = CONT.sub(" ", code)
    an = {"names": set(), "aliases": set(), "reads": set(), "gen_read": False, "alias_reads": set(),
          "fallbacks": set(), "hcloud": bool(HCLOUD.search(code))}
    for m in FAM.finditer(code):
        an["names"].add(row_name(m.group(0)))
    for m in ALIAS_A.finditer(code):
        an["aliases"].add("ALIAS:ACCESS_SERVICE_TOKEN_CLIENT_" + m.group(1).upper())
    for m in ALIAS_B.finditer(code):
        an["aliases"].add("ALIAS:ACCESS_SERVICE_TOKEN_CLIENT_" + m.group(1).upper())
    for m in R_SECRETS.finditer(joined):
        an["reads"].add(row_name(m.group(1)))
    for m in R_GET_HEAD.finditer(joined):
        tail = re.split(r"[;|&)\n]", joined[m.end():], maxsplit=1)[0]
        for t in FAM.finditer(tail):
            an["reads"].add(row_name(t.group(0)))
    an["gen_read"] = bool(R_RUN.search(joined))
    for m in R_TFOUT.finditer(joined):
        an["alias_reads"].add("ALIAS:ACCESS_SERVICE_TOKEN_CLIENT_" + m.group(1).upper())
    for ln in joined.split("\n"):
        if FAM.search(ln):
            for m in FALLBACK.finditer(ln):
                if not FAM_FULL.fullmatch(m.group(1)):
                    an["fallbacks"].add("FALLBACK:" + m.group(1).upper())
    return an

def keys_of(rel, an, exempt):
    if not exempt:
        return {(rel, n) for n in an["names"]} | {(rel, n) for n in an["fallbacks"]} | {(rel, n) for n in an["aliases"]}
    ks = {(rel, n) for n in an["reads"]} | {(rel, n) for n in an["alias_reads"]}
    if an["gen_read"]:
        ks |= {(rel, n) for n in an["names"]}
    return ks

def has_read(an):
    return bool(an["reads"] or an["gen_read"] or an["alias_reads"])

# ── the Tier-B environment set ───────────────────────────────────────────────────────────
SIB = None
if a.sibling:
    try:
        _st = open(a.sibling, encoding="utf-8", errors="replace").read()
        _m = re.search(r"^TIER_B_ENVIRONMENTS = (\{[^}\n]*\})$", _st, re.M)
        SIB = set(ast.literal_eval(_m.group(1))) if _m else None
    except Exception:
        SIB = None
if a.envs:
    ENVS = {x for x in a.envs.split(",") if x}
elif SIB:
    ENVS = SIB | PENDING_ENVS
else:
    ENVS = set(PENDING_ENVS)

def env_arms(raw):
    """Every value `environment:` can resolve to. Scalar, mapping form, or a ${{ }} expression."""
    if raw is None:
        return None
    if isinstance(raw, dict):
        raw = raw.get("name")
        if raw is None:
            return [""]
    s = str(raw)
    if "${{" in s:
        arms = re.findall(r"'([^']*)'", s) + re.findall(r'"([^"]*)"', s)
        if re.search(r"\|\|\s*''", s) or re.search(r'\|\|\s*""', s):
            arms.append("")
        return arms if arms else [""]
    return [s]

WF = re.compile(r"\.github/workflows/[^/]+\.ya?ml")
def tierb_ok(rel, text):
    """True when every job naming the trio declares an `environment:` whose arms are all Tier-B."""
    try:
        doc = yaml.safe_load(text)
    except Exception:
        return False
    if not isinstance(doc, dict) or not isinstance(doc.get("jobs"), dict):
        return False
    wl = bool(FAM.search(json.dumps(doc.get("env") or {}, default=str)))
    naming = [(jn, b) for jn, b in doc["jobs"].items() if isinstance(b, dict) and (wl or FAM.search(json.dumps(b, default=str)))]
    if not naming:
        return False
    for _jn, b in naming:
        arms = env_arms(b.get("environment")) if "environment" in b else None
        if not arms or not all(x and x in ENVS for x in arms):
            return False
    return True

def file_class(rel, text, an, exempt):
    if exempt or has_read(an):
        return "tier-a"
    if WF.fullmatch(rel):
        return "tier-b" if tierb_ok(rel, text) else "tier-a"
    return "sink"

# ── 1. the population (F-A1) ─────────────────────────────────────────────────────────────
genv = {k: v for k, v in os.environ.items() if k not in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE")}
def git(*args):
    return subprocess.run(["git", "-C", REPO] + list(args), capture_output=True, env=genv)

_r = git("ls-files", "-z", "--cached", "--others", "--exclude-standard")
if _r.returncode != 0:
    sys.stderr.write("FAIL SETUP: git ls-files failed in %s: %s\n" % (REPO, _r.stderr.decode("utf-8", "replace")[:200]))
    sys.exit(3)
paths = sorted({os.fsdecode(p) for p in _r.stdout.split(b"\0") if p})

stat = {"excluded": 0, "exempt": 0, "binary": 0, "symlinks": 0, "gone": 0, "hits": 0}
unreadable = []
scanned = []
need = {}
hcloud_files = set()
key_files = set()
tf_texts = {}
for rel in paths:
    if rel in (SUITE_REL, BASELINE_REL) or rel.startswith(EXCLUDED_PREFIXES):
        stat["excluded"] += 1
        continue
    full = os.path.join(REPO, rel)
    if os.path.islink(full):
        stat["symlinks"] += 1
        continue
    if not os.path.lexists(full):
        stat["gone"] += 1
        continue
    if os.path.isdir(full):
        continue
    try:
        with open(full, "rb") as fh:
            raw = fh.read()
    except OSError as e:
        unreadable.append("%s (%s)" % (rel, e.__class__.__name__))
        continue
    if b"\0" in raw[:8192]:
        stat["binary"] += 1
        continue
    text = raw.decode("utf-8", errors="replace")
    ex = is_exempt(rel)
    scanned.append(rel)
    if ex:
        stat["exempt"] += 1
    an = analyze(rel, text)
    if has_read(an):
        stat["hits"] += 1
    ks = keys_of(rel, an, ex)
    if ks:
        fcls = file_class(rel, text, an, ex)
        key_files.add(rel)
        for (f, n) in ks:
            need[(f, n)] = "tier-a" if n.startswith(("FALLBACK:", "ALIAS:")) else fcls
    if an["hcloud"] and not ex:
        hcloud_files.add(rel)
    if re.fullmatch(r"apps/web-platform/infra/[^/]+\.tf", rel):
        tf_texts[rel] = text

pairs = {k for k in need if not k[1].startswith(("FALLBACK:", "ALIAS:"))}
fallbacks = {k for k in need if k[1].startswith("FALLBACK:")}
aliases = {k for k in need if k[1].startswith("ALIAS:")}

# ── 2. the baseline ──────────────────────────────────────────────────────────────────────
def read_baseline(path):
    rec = {"exists": os.path.isfile(path), "rows": [], "bad": [], "dup": [], "stems": [], "allows": []}
    if not rec["exists"]:
        rec["bad"].append("missing file")
        return rec
    seen, seen_allow = set(), set()
    for i, ln in enumerate(open(path, encoding="utf-8").read().split("\n"), 1):
        if not ln.strip() or ln.startswith("#"):
            continue
        if ln.startswith("@stems"):
            m = re.fullmatch(r"@stems[ \t]+([A-Z0-9_,]+)", ln)
            if m:
                rec["stems"].append(m.group(1))
            else:
                rec["bad"].append("line %d: malformed @stems record" % i)
            continue
        if ln.startswith("@allow"):
            c = ln.split("\t")
            if len(c) != 5 or not all(x.strip() for x in c[1:]):
                rec["bad"].append("line %d: @allow needs 5 non-empty tab-separated fields" % i); continue
            _t, f, n, mx, tg = c
            if not (ROWNAME.fullmatch(n)):
                rec["bad"].append("line %d: @allow name %r is not a trio-family name" % (i, n))
            if mx != "-" and parse_iso(mx) is None:
                rec["bad"].append("line %d: @allow max-expiry %r is not '-' or a strict ISO date" % (i, mx))
            if not re.fullmatch(r"#9294:PR-[1-4]", tg):
                rec["bad"].append("line %d: @allow tag %r is not #9294:PR-1..4" % (i, tg))
            if (f, n) in seen_allow:
                rec["dup"].append("@allow %s %s" % (f, n))
            seen_allow.add((f, n))
            rec["allows"].append((f, n, mx, tg))
            continue
        if ln.startswith("@"):
            rec["bad"].append("line %d: unknown record %r" % (i, ln.split("\t")[0][:20])); continue
        c = ln.split("\t")
        if len(c) != 5 or not all(x.strip() for x in c):
            rec["bad"].append("line %d: need 5 non-empty tab-separated columns (file, name, class, expires, tag)" % i); continue
        f, n, cls, exp, tag = c
        if cls not in ("tier-a", "tier-b", "sink"):
            rec["bad"].append("line %d: class %r is not tier-a|tier-b|sink" % (i, cls))
        if cls == "tier-a":
            d = parse_iso(exp)
            if d is None:
                rec["bad"].append("line %d: tier-a expiry %r is not a strict YYYY-MM-DD date" % (i, exp))
            elif d > MAX_EXPIRY:
                rec["bad"].append("line %d: tier-a expiry %s is later than MAX_EXPIRY %s" % (i, exp, MAX_EXPIRY.isoformat()))
        elif exp != "-":
            rec["bad"].append("line %d: a %s row needs expiry '-', got %r" % (i, cls, exp))
        if not (ROWNAME.fullmatch(n) or re.fullmatch(r"FALLBACK:[A-Z_][A-Z0-9_]*", n) or n in ALIAS_NAMES):
            rec["bad"].append("line %d: name %r is not a trio-family, FALLBACK:* or ALIAS:* name" % (i, n))
        if n.startswith(("FALLBACK:", "ALIAS:")) and cls != "tier-a":
            rec["bad"].append("line %d: %s must be tier-a" % (i, n))
        if not re.fullmatch(r"#9294:PR-[1-4]", tag):
            rec["bad"].append("line %d: tag %r is not #9294:PR-1..4" % (i, tag))
        elif cls == "tier-a" and tag != "#9294:" + group_of(f):
            rec["bad"].append("line %d: tier-a tag %s is not the computed group #9294:%s of %s" % (i, tag, group_of(f), f))
        if (f, n) in seen:
            rec["dup"].append("%s %s" % (f, n))
        seen.add((f, n))
        rec["rows"].append((f, n, cls, exp, tag))
    return rec

if a.mode == "emit":
    prev = read_baseline(a.baseline) if os.path.isfile(a.baseline) else {"allows": []}
    print("@stems " + ",".join(STEMS))
    for f, n, mx, tg in prev["allows"]:
        if (f, n) not in need:
            print("@allow\t%s\t%s\t%s\t%s" % (f, n, mx, tg))
    for (f, n) in sorted(need):
        c = need[(f, n)]
        print("%s\t%s\t%s\t%s\t#9294:%s" % (f, n, c, ROW_EXPIRY if c == "tier-a" else "-", group_of(f)))
    sys.exit(0)

rec = read_baseline(a.baseline)
brs = rec["rows"]
bkeys = {(f, n) for f, n, _c, _e, _t in brs}
bcls = {(f, n): (c, e, t) for f, n, c, e, t in brs}

# ── 3. the base record (shell-resolved) ──────────────────────────────────────────────────
def slurp(name):
    try:
        return open(os.path.join(a.base_dir, name), "rb").read()
    except OSError:
        return b""
def slurp_s(name):
    return slurp(name).decode("utf-8", "replace").strip()

b_status = slurp_s("status") if a.base_dir else "none"
b_arm = slurp_s("arm")
b_ref = slurp_s("ref")
b_msg = slurp_s("msg")
b_shallow = slurp_s("shallow") == "true"
base_rec = read_baseline(os.path.join(a.base_dir, "base.tsv")) if b_status == "ok" else None

changed, renames = set(), []
if b_status == "ok":
    toks = [os.fsdecode(t) for t in slurp("changed.z").split(b"\0")]
    i = 0
    while i < len(toks):
        s = toks[i]
        if not s:
            i += 1; continue
        if s[0] in "RC" and i + 2 < len(toks):
            changed.update((toks[i + 1], toks[i + 2]))
            if s[0] == "R":
                renames.append((toks[i + 1], toks[i + 2]))
            i += 3
        elif i + 1 < len(toks):
            changed.add(toks[i + 1]); i += 2
        else:
            i += 1
    changed.update(os.fsdecode(t) for t in slurp("untracked.z").split(b"\0") if t)

# ── 4. the rows ──────────────────────────────────────────────────────────────────────────
check("T0: the population is git-derived and non-empty (%d scanned: %d exempt by structure, %d read-shape files; %d binary, %d symlink, %d excluded prefix/own skipped)"
      % (len(scanned), stat["exempt"], stat["hits"], stat["binary"], stat["symlinks"], stat["excluded"]),
      len(scanned) >= 1, "scanned=%d" % len(scanned))

problems = rec["bad"] + ["duplicate %s" % d for d in rec["dup"]]
if len(rec["stems"]) != 1:
    problems.append("expected exactly one @stems record, found %d" % len(rec["stems"]))
check("T5: the baseline is well-formed: 5 columns, a computed-class vocabulary, a family/FALLBACK/ALIAS name, a strict ISO expiry on tier-a (<= MAX_EXPIRY) and '-' elsewhere, a #9294:PR-n tag equal to the computed group on tier-a, valid @allow lines, no duplicate key",
      rec["exists"] and not problems, "; ".join(problems[:6]))

mism = sorted("%s %s (baseline %s, computed %s)" % (f, n, bcls[(f, n)][0], need[(f, n)]) for (f, n) in bkeys & set(need) if bcls[(f, n)][0] != need[(f, n)])
check("T5c: every row's class agrees with the class the scanner computes (tier-b needs every naming job on a Tier-B environment; a read shape is tier-a)",
      not mism, "; ".join(mism[:6]))

stems_head = rec["stems"][0] if len(rec["stems"]) == 1 else None
stems_bad = []
if stems_head != ",".join(STEMS):
    stems_bad.append("baseline @stems %r != the scanner's STEMS %r" % (stems_head, ",".join(STEMS)))
if base_rec is not None:
    stems_base = base_rec["stems"][0] if len(base_rec["stems"]) == 1 else None
    if stems_base is None:
        stems_bad.append("the base copy has no single @stems record")
    elif stems_base != stems_head:
        stems_bad.append("baseline @stems %r != the base copy's %r" % (stems_head, stems_base))
check("T6: the stem set is pinned: the baseline @stems record equals the scanner's STEMS constant and the base copy's record (dropping a stem with its rows is RED)",
      not stems_bad, "; ".join(stems_bad))

if a.sibling:
    extra = sorted((PENDING_ENVS - (SIB or set())) - {"deploy-channel"})
    check("E1: the Tier-B environment set is single-sourced from %s (TIER_B_ENVIRONMENTS, %d names) plus only the pending name deploy-channel"
          % (os.path.basename(a.sibling), len(SIB or ())), bool(SIB) and not extra,
          "sibling set %s; pending names the sibling lacks beyond deploy-channel: %s" % (sorted(SIB or ()), extra))
else:
    check("E1: the Tier-B environment set is the fixture set (no sibling given)", True, "envs=%s" % sorted(ENVS))

check("T8: no scanned file was unreadable (a silent skip is a hole in the population) [%d unreadable]" % len(unreadable),
      not unreadable, "; ".join(unreadable[:6]))

unbased = sorted("%s %s" % k for k in need if k not in bkeys)
check("T1: every (file, name) that names a trio credential in code has a baseline row [%d name pairs, %d FALLBACK, %d ALIAS]"
      % (len(pairs), len(fallbacks), len(aliases)), not unbased, "; ".join(unbased[:8]))
stale = sorted("%s %s" % k for k in bkeys if k not in need)
check("T2: every baseline row has a live (file, name) read (a consumer that moved must delete its row)", not stale, "; ".join(stale[:8]))

# T3 / T3w / T3m (F-D)
def is_main_event(ev, ref):
    if ev in ("schedule", "merge_group"):
        return True
    return ev in ("push", "workflow_dispatch") and ref == "refs/heads/main"
main_event = is_main_event(a.event_name, a.event_ref)
tier_a = [(f, n, parse_iso(e)) for f, n, c, e, _t in brs if c == "tier-a" and parse_iso(e) is not None]
expired = sorted((f, n, d) for f, n, d in tier_a if d < TODAY)
soon = sorted((f, n, d) for f, n, d in tier_a if 0 <= (d - TODAY).days <= WARN_DAYS)
if b_status == "ok":
    touched = bool({f for f, _n, _d in tier_a} & changed) or bool({BASELINE_REL, ADR_REL, PLAN_REL} & changed)
else:
    touched = True
hard = bool(expired) and not main_event and touched
check("T3: no tier-a row is past its expiry on a blocking event that touches a row's file, the baseline, ADR-241 or the plan (today %s, event %s%s)"
      % (a.today, a.event_name or "local", "" if main_event else " [blocking]"), not hard,
      "; ".join("%s %s (%s)" % (f, n, d.isoformat()) for f, n, d in ([r for r in expired if r[0] in changed] or expired)[:8]))
warn = []
if soon:
    warn.append("%d of %d tier-a rows expire within %d days (earliest %s)" % (len(soon), len(tier_a), WARN_DAYS, min(d for _f, _n, d in soon).isoformat()))
if expired and not hard and not main_event:
    warn.append("%d of %d tier-a rows are past expiry but this change touches none of their files, the baseline, ADR-241 or the plan" % (len(expired), len(tier_a)))
check("T3w: " + ("; ".join(warn) if warn else "no tier-a row expires within %d days" % WARN_DAYS), True, "")
if warn:
    anns.append("::warning::%s; %d tier-a rows remain" % ("; ".join(warn), len(tier_a)))
if expired and main_event:
    check("T3m: %d tier-a rows are past expiry (non-blocking on main by ruling)" % len(expired), True, "")
    anns.append("::error::T3m: %d tier-a trio-baseline rows are past expiry on a main-class event; non-blocking by ruling, re-date or migrate them" % len(expired))
else:
    check("T3m: no tier-a row is past expiry on a main-class event", True, "")

# T4: the ratchet (F-B)
v = []
if b_status == "unresolved":
    v.append("T4 RED: base unresolved (ref %s, arm %s)%s%s" % (b_ref, b_arm,
             " [shallow clone: fetch the base ref, e.g. actions/checkout fetch-depth: 0]" if b_shallow else "",
             (": " + b_msg) if b_msg else ""))
elif b_status == "ok" and base_rec is not None:
    base_by = {(f, n): (c, e, t) for f, n, c, e, t in base_rec["rows"]}
    base_allow = {(f, n): (mx, tg) for f, n, mx, tg in base_rec["allows"]}
    head_allow = {(f, n) for f, n, _mx, _tg in rec["allows"]}
    added_allow = set()
    for ln in slurp_s("addhist.txt").split("\n"):
        c = ln.split("\t")
        if len(c) >= 3 and c[0] == "+@allow":
            added_allow.add((c[1], c[2]))
    ren_new_old = {new: old for old, new in renames}
    extended = []
    def compare(k, old_k, hrow):
        b = base_by[old_k]
        h = hrow
        if h[2] != b[2]:
            v.append("T4: tag of %s %s changed vs base (%s -> %s)" % (k[0], k[1], b[2], h[2]))
        if not (h[0] == b[0] or (b[0] == "tier-a" and h[0] in ("tier-b", "sink"))):
            v.append("T4: class of %s %s moved backwards or sideways (%s -> %s); only tier-a -> tier-b|sink is forward" % (k[0], k[1], b[0], h[0]))
        bd, hd = parse_iso(b[1]), parse_iso(h[1])
        if bd is not None and hd is not None and hd > bd:
            extended.append((k, b[1], h[1]))
        if old_k != k and (h[0] != b[0] or h[1] != b[1]):
            v.append("T4: renamed row %s -> %s changed class/expiry" % (old_k[0], k[0]))
    for (f, n, c, e, t) in brs:
        k = (f, n)
        if k in base_by:
            compare(k, k, (c, e, t))
            continue
        old = ren_new_old.get(f)
        if old is not None and (old, n) in base_by:
            compare(k, (old, n), (c, e, t))
            continue
        if k in base_allow:
            mx, tg = base_allow[k]
            if k in head_allow:
                v.append("T4: @allow %s %s was not deleted by the diff that spends it" % k)
            if t != tg:
                v.append("T4: row %s %s tag %s differs from its @allow tag %s" % (f, n, t, tg))
            md, ed = parse_iso(mx), parse_iso(e)
            if (mx == "-" and e != "-") or (md is not None and (ed is None or ed > md)):
                v.append("T4: row %s %s expiry %s exceeds its @allow max-expiry %s" % (f, n, e, mx))
        elif k in added_allow:
            v.append("T4: @allow %s %s was added in the same diff that spends it" % k)
        else:
            v.append("T4: new (file,name) %s %s has no @allow at the merge-base; land a reviewed @allow-only PR first" % k)
    if extended:
        redate_ok = changed <= {BASELINE_REL, ADR_REL, PLAN_REL}
        adr_dates = set()
        for ln in slurp_s("adr.diff").split("\n"):
            m = re.match(r"\+(?!\+).*?Re-date:\s+([0-9]{4}-[0-9]{2}-[0-9]{2})\b.*\bRuled by\s+\S", ln)
            if m:
                adr_dates.add(m.group(1))
        if not (redate_ok and all(h in adr_dates for _k, _b, h in extended)):
            v.append("T4: expiry extension needs an ADR-241 line 'Re-date: <date> ... Ruled by <owner>' in a baseline/ADR-only change [%s]"
                     % ", ".join("%s %s %s -> %s" % (k[0], k[1], bb, hh) for k, bb, hh in extended[:4]))
    for old, new in renames:
        old_names = {n for (f, n) in base_by if f == old}
        if old_names and excluded_path(new):
            fp = os.path.join(REPO, new)
            if os.path.isfile(fp) and not os.path.islink(fp):
                an2 = analyze(new, open(fp, encoding="utf-8", errors="replace").read())
                still = old_names & (an2["names"] | an2["aliases"] | an2["fallbacks"])
                if still:
                    v.append("T4: %s was renamed into the exempt/excluded path %s and still names %s" % (old, new, sorted(still)))
if b_status == "ok":
    t4_detail = "; ".join(v[:6])
elif b_status == "introduction":
    t4_detail = "introduction: the suite is absent at the base; the ratchet starts with the next change"
elif b_status == "skipped":
    t4_detail = "SKIPPED via TRIO_ALLOW_NO_BASE=1 (local only)"
else:
    t4_detail = "; ".join(v[:6])
check("T4: the baseline is a forward-only ratchet against its base copy (arm %s; tag fixed, class forward-only, expiry never later, new keys only via a spent @allow, renames carry rows)" % (b_arm or "none"),
      b_status in ("introduction", "skipped") or (b_status == "ok" and not v), t4_detail)

creep = sorted(f for f in hcloud_files if group_of(f) in ("PR-3", "PR-4") and f in key_files)
check("T7: no file in the PR-3/PR-4 groups (computed from its path, not the tag column) names HCLOUD_TOKEN (the narrow carrier must not drag the host-destroy credential in)", not creep, "; ".join(creep[:8]))

# ── 5. the HMAC stays out of Terraform state (plan Guard 1, assembly of the state attributes) ─
def tf_text(rel):
    return "\n".join(code_lines(tf_texts[rel]))

def code_lines(text):
    for ln in text.split("\n"):
        s = ln.lstrip()
        if s.startswith("#") or s.startswith("//"):
            continue
        yield ln

def balanced(text, i):
    """index just past the bracket group opening at text[i]"""
    pair = {"(": ")", "[": "]", "{": "}"}
    stack, k = [], i
    while k < len(text):
        c = text[k]
        if c in pair:
            stack.append(pair[c])
        elif stack and c == stack[-1]:
            stack.pop()
            if not stack:
                return k + 1
        k += 1
    return len(text)

SECRETISH = re.compile(r"webhook_deploy_secret|hooks_json", re.I)
tf_rels = sorted(tf_texts)
h1, h2, h3 = [], [], []
for rel in tf_rels:
    t = tf_text(rel)
    for m in re.finditer(r"triggers_replace\s*=\s*", t):
        s = m.end()
        j = re.search(r"[\(\[\{]", t[s:])
        if not j:
            continue
        e = balanced(t, s + j.start())
        expr = t[s:e]
        if SECRETISH.search(expr) and not re.match(r"\s*sha256\(", expr):
            h1.append("%s:%d" % (rel, t.count("\n", 0, m.start()) + 1))
    for m in re.finditer(r'^\s*output\s+"[^"]+"\s*\{', t, re.M):
        e = balanced(t, m.end() - 1)
        if SECRETISH.search(t[m.end():e]):
            h2.append("%s:%d" % (rel, t.count("\n", 0, m.start()) + 1))
    for m in re.finditer(r'^\s*resource\s+"terraform_data"\s+"[^"]+"\s*\{', t, re.M):
        e = balanced(t, m.end() - 1)
        body = t[m.end():e]
        for im in re.finditer(r"^\s*input\s*=\s*", body, re.M):
            k = re.search(r"[\(\[\{\"']", body[im.end():])
            ee = balanced(body, im.end() + k.start()) if k and body[im.end() + k.start()] in "([{" else body.find("\n", im.end())
            if SECRETISH.search(body[im.end():ee]):
                h3.append("%s:%d" % (rel, t.count("\n", 0, m.start()) + 1))
check("H1: every triggers_replace that references the webhook secret or the rendered hooks.json is wrapped in sha256( (the state keeps the hash, not the value) [%d .tf files]" % len(tf_rels),
      not h1, "; ".join(h1[:6]))
check("H2: no output block references the webhook secret or the rendered hooks.json (outputs sit in state in plaintext)", not h2, "; ".join(h2[:6]))
check("H3: no terraform_data input references the webhook secret or the rendered hooks.json (input is stored in state)", not h3, "; ".join(h3[:6]))

for l in out:
    print(l)
if a.ann:
    with open(a.ann, "w", encoding="utf-8") as fh:
        for l in anns:
            fh.write(l + "\n")
print("TRIO_FILES_SCANNED=%d" % len(scanned), file=sys.stderr)
print("TRIO_EXEMPT=%d" % stat["exempt"], file=sys.stderr)
print("TRIO_READSHAPE_HITS=%d" % stat["hits"], file=sys.stderr)
print("TRIO_SKIPPED_UNREADABLE=%d" % len(unreadable), file=sys.stderr)
print("TRIO_BINARY=%d" % stat["binary"], file=sys.stderr)
print("TRIO_SYMLINKS=%d" % stat["symlinks"], file=sys.stderr)
print("TRIO_EXCLUDED=%d" % stat["excluded"], file=sys.stderr)
print("TRIO_PAIRS=%d FALLBACKS=%d ALIASES=%d" % (len(pairs), len(fallbacks), len(aliases)), file=sys.stderr)
for _root in ROOTS:
    print("TRIO_ROOT_COUNT %s %d" % (_root, sum(1 for r in scanned if r.startswith(_root + "/"))), file=sys.stderr)
PY

GITQ() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git "$@"; }
# gc: git for fixture repos (identity and hooks pinned; fixtures never inherit the operator's config)
gc() { GITQ -c user.name=fx -c user.email=fx@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }

# resolve_base <repo> <dir> <ref>  — the FAIL-CLOSED base resolution (F-B). Writes into <dir>:
#   status (ok|introduction|unresolved|skipped), arm (merge-base|head1|introduction), ref, msg, shallow,
#   base.tsv (the base copy), changed.z/untracked.z (name-status -M90% -z vs the base, plus untracked paths),
#   adr.diff (the ADR-241 diff vs the base), addhist.txt (every `@allow` line added to the baseline since the base).
resolve_base() {
  local repo="$1" d="$2" ref="$3" head mb base="" arm="merge-base" status="ok" msg="" shallow=false
  mkdir -p "$d"
  if [ "$(GITQ -C "$repo" rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then shallow=true; fi
  head="$(GITQ -C "$repo" rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null)" || head=""
  mb="$(GITQ -C "$repo" merge-base HEAD "$ref" 2>/dev/null)" || mb=""
  if [ -z "$head" ] || [ -z "$mb" ]; then
    status=unresolved; msg="no merge-base of HEAD and $ref"
  elif [ "$mb" = "$head" ]; then
    arm=head1
    base="$(GITQ -C "$repo" rev-parse --verify -q 'HEAD^1^{commit}' 2>/dev/null)" || base=""
    if [ -z "$base" ]; then status=unresolved; msg="HEAD is $ref and has no first parent"; fi
  else
    base="$mb"
  fi
  if [ "$status" = ok ]; then
    if GITQ -C "$repo" cat-file -e "$base:$SUITE_REL" 2>/dev/null; then
      if ! GITQ -C "$repo" show "$base:$BASELINE_REL" > "$d/base.tsv" 2>/dev/null; then
        status=unresolved; msg="$BASELINE_REL is absent at a base where $SUITE_REL exists"
      fi
    else
      arm=introduction; status=introduction
    fi
  fi
  if [ "$status" = unresolved ] && [ "${TRIO_ALLOW_NO_BASE:-}" = "1" ] && [ "${GITHUB_ACTIONS:-}" != "true" ]; then
    status=skipped
    printf '################################################################################\n# WARNING: TRIO_ALLOW_NO_BASE=1 -- the T4 ratchet is DISABLED for this run (local only). #\n################################################################################\n' >&2
  fi
  if [ "$status" = ok ]; then
    GITQ -C "$repo" diff -M90% --name-status -z "$base" > "$d/changed.z" 2>/dev/null
    GITQ -C "$repo" ls-files -z --others --exclude-standard > "$d/untracked.z" 2>/dev/null
    GITQ -C "$repo" diff --unified=0 "$base" -- "$ADR_REL" > "$d/adr.diff" 2>/dev/null
    { GITQ -C "$repo" log -p --format= "$base..HEAD" -- "$BASELINE_REL" 2>/dev/null; GITQ -C "$repo" diff "$base" -- "$BASELINE_REL" 2>/dev/null; } | awk '/^\+@allow\t/' > "$d/addhist.txt"
  fi
  printf '%s' "$status" > "$d/status"; printf '%s' "$arm" > "$d/arm"; printf '%s' "$ref" > "$d/ref"
  printf '%s' "$msg" > "$d/msg"; printf '%s' "$shallow" > "$d/shallow"
}

# --emit-baseline: print the DERIVED baseline records for the live tree (never hand-written). The prose header
# of tests/scripts/trio-baseline.tsv is kept by hand; this prints everything below it.
if [ "${1:-}" = "--emit-baseline" ]; then
  python3 "$T/trio.py" --repo "$REPODIR" --baseline "$BASELINE" --today "$TODAY" --mode emit --sibling "$REPODIR/$SIBLING_REL"
  _emit_rc=$?
  _REACHED_VERDICT=1
  exit "$_emit_rc"
fi

printf '\n=== deploy-channel trio census, Guard 1a (G1, PR-0; #9294, ADR-241) ===\n\n'

NROWS=16
FIXTODAY="2026-10-15"
FIXENVS="infra-privileged,deploy-channel"
# run_full <repo> <baseline> <out>  — resolve the base, run the scanner, write the TSV rows to <out>.
# Knobs (set in a subshell by the caller): RF_REF RF_TODAY RF_EVENT RF_EVENTREF RF_ENVS RF_SIB RF_PY
run_full() {
  local repo="$1" bl="$2" out="$3"
  rm -rf "$out.bd"
  resolve_base "$repo" "$out.bd" "${RF_REF-refs/remotes/origin/main}" 2> "$out.bd.err"
  python3 "${RF_PY:-$T/trio.py}" --repo "$repo" --baseline "$bl" --base-dir "$out.bd" --today "${RF_TODAY-$FIXTODAY}" \
    --event-name "${RF_EVENT-}" --event-ref "${RF_EVENTREF-}" --envs "${RF_ENVS-$FIXENVS}" --sibling "${RF_SIB-}" --ann "$out.ann" > "$out" 2> "$out.err"
  return $?
}
# row_state <out> <ROWID>  — prints ok|FAIL|MISSING for the row whose name starts with "<ROWID>:"
row_state() {
  local s
  s="$(awk -F'\t' -v id="$2" 'index($2, id ":") == 1 {print $1; exit}' "$1")"
  printf '%s' "${s:-MISSING}"
}
# row_line <out> <ROWID>  — the whole "<name> <detail>" text of that row
row_line() { awk -F'\t' -v id="$2" 'index($2, id ":") == 1 {print $2 " | " $3; exit}' "$1"; }
# all_ok <out>  — true when every row in <out> is ok and at least one row exists
all_ok() {
  [ -s "$1" ] && ! awk -F'\t' '$1 != "ok" {bad=1} END {exit bad ? 0 : 1}' "$1"
}
nrows() { awk 'END {print NR}' "$1"; }
has_text() { [ -n "$(awk -F'\t' -v s="$2" 'index($0, s) > 0 {print "y"; exit}' "$1")" ]; }
# roots_below_floor <errfile> "<root>:<n> ..."  — prints the roots whose scanned-file count is below its floor
roots_below_floor() {
  local spec rt fl got
  for spec in $2; do
    rt="${spec%:*}"; fl="${spec##*:}"
    got="$(awk -v r="$rt" '$1 == "TRIO_ROOT_COUNT" && $2 == r {print $3}' "$1")"
    if [ "${got:-0}" -lt "$fl" ]; then printf '%s(%s<%s) ' "$rt" "${got:-0}" "$fl"; fi
  done
}

# ── A. the live tree ─────────────────────────────────────────────────────────────────────
assert_fixture_dir "$REPODIR"
_live_ref="${TRIO_BASE_REF:-refs/remotes/origin/main}"
_live_sib="$REPODIR/$SIBLING_REL"
[ -f "$_live_sib" ] || _live_sib="$ROOT/$SIBLING_REL"
(
  RF_REF="$_live_ref"; RF_TODAY="$TODAY"; RF_EVENT="${GITHUB_EVENT_NAME:-}"; RF_EVENTREF="${GITHUB_REF:-}"; RF_ENVS=""; RF_SIB="$_live_sib"
  run_full "$REPODIR" "$BASELINE" "$T/live.tsv"
); _live_rc=$?
cat "$T/live.tsv.bd.err" >&2 2>/dev/null
printf 'TRIO_BASE_ARM=%s ref=%s status=%s\n' "$(cat "$T/live.tsv.bd/arm" 2>/dev/null)" "$(cat "$T/live.tsv.bd/ref" 2>/dev/null | tr -d '[:cntrl:]')" "$(cat "$T/live.tsv.bd/status" 2>/dev/null)" >&2
cat "$T/live.tsv.ann" 2>/dev/null
cat "$T/live.tsv.err" >&2 2>/dev/null
if [ "$_live_rc" -eq 3 ]; then
  printf 'FAIL SETUP: the scanner could not assemble its population: %s\n' "$(head -c 300 "$T/live.tsv.err")" >&2
  exit 1
fi
if [ "$_live_rc" -ne 0 ]; then
  fail "A0: the scanner ran on the live tree" "rc=$_live_rc: $(head -c 300 "$T/live.tsv.err")"
else
  pass "A0: the scanner ran on the live tree"
fi
while IFS=$'\t' read -r _st _nm _dt; do
  [ -n "${_st:-}" ] || continue
  if [ "$_st" = "ok" ]; then pass "live $_nm"; else fail "live $_nm" "$_dt"; fi
done < "$T/live.tsv"
_nlive="$(nrows "$T/live.tsv")"
if [ "$_nlive" -eq "$NROWS" ]; then pass "A1: the live run produced all $NROWS rows ($_nlive)"; else fail "A1: the live run produced all $NROWS rows" "got $_nlive"; fi
# A2: per-root floors (F-A1), each within ~10% of the measured count at the time they were set.
LIVE_ROOT_FLOORS=".github/workflows:81 .github/actions:12 .github/scripts:26 scripts:755 plugins:1515 apps/web-platform:2990"
_below="$(roots_below_floor "$T/live.tsv.err" "$LIVE_ROOT_FLOORS")"
if [ -z "$_below" ]; then pass "A2: every scan root meets its minimum file floor ($LIVE_ROOT_FLOORS)"; else fail "A2: every scan root meets its minimum file floor" "below: $_below"; fi

# ── B. the synthetic fixture (a git repo: the smallest fully compliant tree, with a base history) ─
FX="$T/fx"
assert_fixture_dir "$FX"
mkdir -p "$FX/.github/workflows" "$FX/.github/actions/keep" "$FX/.github/scripts" "$FX/scripts/followthroughs" \
  "$FX/apps/web-platform/infra" "$FX/apps/web-platform/server" "$FX/apps/web-platform/test" "$FX/plugins/soleur/skills/ship" \
  "$FX/tests/scripts" "$FX/knowledge-base/engineering/architecture/decisions" "$FX/knowledge-base/project/plans" "$FX/docs" \
  || { printf 'FAIL SETUP: mkdir fixture\n' >&2; exit 1; }
cat > "$FX/.github/workflows/web-platform-release.yml" <<'EOF'
name: rel
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - run: echo "deploy"
        env:
          WEBHOOK_DEPLOY_SECRET: ${{ secrets.WEBHOOK_DEPLOY_SECRET }}
EOF
cat > "$FX/.github/workflows/canary-status.yml" <<'EOF'
name: canary
jobs:
  probe:
    runs-on: ubuntu-latest
    steps:
      - run: |
          id="$(doppler secrets get CF_ACCESS_CLIENT_ID --plain -c prd_terraform)"
EOF
cat > "$FX/.github/workflows/cutover-inngest.yml" <<'EOF'
name: cutover
jobs:
  c:
    runs-on: ubuntu-latest
    env:
      S: ${{ secrets.CF_ACCESS_CLIENT_SECRET }}
    steps:
      - run: echo c
EOF
cat > "$FX/.github/workflows/deploy-chan.yml" <<'EOF'
name: dc
jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: deploy-channel
    steps:
      - run: |
          curl -H "X-Sig: $WEBHOOK_DEPLOY_SECRET" https://example.invalid
EOF
# non-canonical on purpose: 4-space indent, odd step keys, mapping and quoted environment forms, two jobs
cat > "$FX/.github/workflows/deploy-chan2.yml" <<'EOF'
name:   dc2
jobs:
    one:
        runs-on: x
        environment:
            name: "deploy-channel"
        steps:
            - name: whatever differently named
              run: |
                  echo "${CF_ACCESS_CLIENT_ID}"
    two:
        environment: 'infra-privileged'
        runs-on: x
        steps:
            - uses: foo/bar@v1
              with:
                  token: ${{ env.CF_ACCESS_CLIENT_ID }}
EOF
cat > "$FX/.github/workflows/migrate.yml" <<'EOF'
name: migrate
jobs:
  m:
    runs-on: ubuntu-latest
    steps:
      - run: echo "$X"
        env:
          X: ${{ secrets.CF_ACCESS_CLIENT_ID }}
EOF
printf 'name: keep\nruns:\n  using: composite\n  steps: []\n' > "$FX/.github/actions/keep/action.yml"
printf '#!/usr/bin/env bash\necho clean\n' > "$FX/.github/scripts/clean.sh"
cat > "$FX/scripts/probe.sh" <<'EOF'
#!/usr/bin/env bash
# a comment that names CF_ACCESS_CLIENT_SECRET must not create a row
id="$(doppler secrets get CF_ACCESS_CLIENT_ID --plain \
  || doppler secrets get CI_SSH_ACCESS_TOKEN_ID --plain)"
EOF
printf '#!/usr/bin/env bash\ndoppler secrets get WEBHOOK_DEPLOY_SECRET --plain\n' > "$FX/scripts/followthroughs/soak.sh"
printf '#!/usr/bin/env bash\nexport H="$HCLOUD_TOKEN"\necho "using ${WEBHOOK_DEPLOY_SECRET}"\n' > "$FX/scripts/host-user.sh"
printf 'a\0WEBHOOK_DEPLOY_SECRET\n' > "$FX/scripts/blob.bin"
ln -s probe.sh "$FX/scripts/link.sh"
cat > "$FX/apps/web-platform/infra/server.tf" <<'EOF'
locals {
  hooks_json = templatefile("${path.module}/hooks.json.tmpl", {
    webhook_deploy_secret = var.webhook_deploy_secret
  })
}
resource "terraform_data" "deploy_pipeline_fix" {
  triggers_replace = sha256(join(",", [file("${path.module}/a.sh"), local.hooks_json]))
}
EOF
printf 'variable "webhook_deploy_secret" {\n  type      = string\n  sensitive = true\n}\n' > "$FX/apps/web-platform/infra/variables.tf"
printf '{"secret": ${jsonencode(webhook_deploy_secret)}}\n' > "$FX/apps/web-platform/infra/hooks.json.tmpl"
cat > "$FX/apps/web-platform/infra/tunnel.tf" <<'EOF'
output "access_service_token_client_secret" {
  value     = cloudflare_zero_trust_access_service_token.deploy.client_secret
  sensitive = true
}
output "access_service_token_client_id" {
  value = cloudflare_zero_trust_access_service_token.deploy.client_id
}
EOF
printf 'export const clean = 1;\n' > "$FX/apps/web-platform/server/clean.ts"
printf 'const n = "CF_ACCESS_CLIENT_SECRET";\n' > "$FX/apps/web-platform/test/y.ts"
mkdir -p "$FX/apps/web-platform/fixtures" "$FX/plugins/soleur/skills/__tests__"
printf '{"n": "WEBHOOK_DEPLOY_SECRET"}\n' > "$FX/apps/web-platform/fixtures/f.json"
printf 'export const n = "CF_ACCESS_CLIENT_ID";\n' > "$FX/plugins/soleur/skills/__tests__/z.ts"
printf 'it("x", () => { expect("WEBHOOK_DEPLOY_SECRET").toBe(1) });\n' > "$FX/apps/web-platform/server/a.spec.ts"
printf 'run "x" {\n  variables = { n = "CF_ACCESS_CLIENT_SECRET" }\n}\n' > "$FX/apps/web-platform/infra/m.tftest.hcl"
cat > "$FX/plugins/soleur/skills/ship/SKILL.md" <<'EOF'
# Deploy with CF_ACCESS_CLIENT_ID

```bash
doppler secrets get WEBHOOK_DEPLOY_SECRET -c prd_terraform --plain
```
EOF
printf '#!/usr/bin/env bash\n# mentions WEBHOOK_DEPLOY_SECRET and CF_ACCESS_CLIENT_ID only\necho "$WEBHOOK_DEPLOY_SECRET"\n' > "$FX/tests/x.test.sh"
printf 'secrets.WEBHOOK_DEPLOY_SECRET in a kb note\n' > "$FX/knowledge-base/kb.md"
printf 'secrets.CF_ACCESS_CLIENT_ID in a doc\n' > "$FX/docs/d.md"
printf 'ADR-241 fixture\n' > "$FX/$ADR_REL"
printf 'plan fixture\n' > "$FX/$PLAN_REL"
{ GITQ init -q -b fxmain "$FX" && gc -C "$FX" add -A && gc -C "$FX" commit -q -m c0; } || { printf 'FAIL SETUP: fixture git init\n' >&2; exit 1; }
gc -C "$FX" update-ref refs/remotes/origin/pre HEAD
printf '#!/usr/bin/env bash\n# the suite placeholder: secrets.CF_ACCESS_CLIENT_ID\n' > "$FX/$SUITE_REL"
gc -C "$FX" add -A && gc -C "$FX" commit -q -m c0b && gc -C "$FX" update-ref refs/remotes/origin/nobl HEAD
TAB=$'\t'
cat > "$T/fx-baseline.tsv" <<EOF
# fixture baseline
@stems WEBHOOK_DEPLOY_SECRET,CF_ACCESS_CLIENT_ID,CF_ACCESS_CLIENT_SECRET
@allow${TAB}apps/web-platform/infra/hooks.json.tmpl${TAB}WEBHOOK_DEPLOY_SECRET_NEXT${TAB}-${TAB}#9294:PR-1
@allow${TAB}apps/web-platform/infra/server.tf${TAB}WEBHOOK_DEPLOY_SECRET_NEXT${TAB}-${TAB}#9294:PR-1
@allow${TAB}apps/web-platform/infra/variables.tf${TAB}WEBHOOK_DEPLOY_SECRET_NEXT${TAB}-${TAB}#9294:PR-1
.github/workflows/canary-status.yml${TAB}CF_ACCESS_CLIENT_ID${TAB}tier-a${TAB}2026-11-30${TAB}#9294:PR-3
.github/workflows/cutover-inngest.yml${TAB}CF_ACCESS_CLIENT_SECRET${TAB}tier-a${TAB}2026-11-30${TAB}#9294:PR-4
.github/workflows/deploy-chan.yml${TAB}WEBHOOK_DEPLOY_SECRET${TAB}tier-b${TAB}-${TAB}#9294:PR-2
.github/workflows/deploy-chan2.yml${TAB}CF_ACCESS_CLIENT_ID${TAB}tier-b${TAB}-${TAB}#9294:PR-2
.github/workflows/migrate.yml${TAB}CF_ACCESS_CLIENT_ID${TAB}tier-a${TAB}2026-11-30${TAB}#9294:PR-2
.github/workflows/web-platform-release.yml${TAB}WEBHOOK_DEPLOY_SECRET${TAB}tier-a${TAB}2026-11-30${TAB}#9294:PR-3
apps/web-platform/infra/hooks.json.tmpl${TAB}WEBHOOK_DEPLOY_SECRET${TAB}sink${TAB}-${TAB}#9294:PR-2
apps/web-platform/infra/server.tf${TAB}WEBHOOK_DEPLOY_SECRET${TAB}sink${TAB}-${TAB}#9294:PR-2
apps/web-platform/infra/tunnel.tf${TAB}ALIAS:ACCESS_SERVICE_TOKEN_CLIENT_ID${TAB}tier-a${TAB}2026-11-30${TAB}#9294:PR-2
apps/web-platform/infra/tunnel.tf${TAB}ALIAS:ACCESS_SERVICE_TOKEN_CLIENT_SECRET${TAB}tier-a${TAB}2026-11-30${TAB}#9294:PR-2
apps/web-platform/infra/variables.tf${TAB}WEBHOOK_DEPLOY_SECRET${TAB}sink${TAB}-${TAB}#9294:PR-2
plugins/soleur/skills/ship/SKILL.md${TAB}CF_ACCESS_CLIENT_ID${TAB}tier-a${TAB}2026-11-30${TAB}#9294:PR-2
plugins/soleur/skills/ship/SKILL.md${TAB}WEBHOOK_DEPLOY_SECRET${TAB}tier-a${TAB}2026-11-30${TAB}#9294:PR-2
scripts/followthroughs/soak.sh${TAB}WEBHOOK_DEPLOY_SECRET${TAB}tier-a${TAB}2026-11-30${TAB}#9294:PR-4
scripts/host-user.sh${TAB}WEBHOOK_DEPLOY_SECRET${TAB}sink${TAB}-${TAB}#9294:PR-2
scripts/probe.sh${TAB}CF_ACCESS_CLIENT_ID${TAB}tier-a${TAB}2026-11-30${TAB}#9294:PR-2
scripts/probe.sh${TAB}FALLBACK:CI_SSH_ACCESS_TOKEN_ID${TAB}tier-a${TAB}2026-11-30${TAB}#9294:PR-2
EOF
cp "$T/fx-baseline.tsv" "$FX/$BASELINE_REL"
gc -C "$FX" add -A && gc -C "$FX" commit -q -m c1 && gc -C "$FX" update-ref refs/remotes/origin/main HEAD
gc -C "$FX" commit -q --allow-empty -m head && gc -C "$FX" update-ref refs/remotes/origin/head HEAD
FXHEAD="$(GITQ -C "$FX" rev-parse HEAD)"
FX_TIER_A_ROWS="$(awk -F'\t' '$3 == "tier-a" {n++} END {print n + 0}' "$T/fx-baseline.tsv")"

(run_full "$FX" "$FX/$BASELINE_REL" "$T/ctl.tsv")
if all_ok "$T/ctl.tsv" && [ "$(nrows "$T/ctl.tsv")" -eq "$NROWS" ]; then pass "B0: the control run on the compliant fixture is all green with $NROWS rows (a red control voids every mutant)"
else fail "B0: the control run on the compliant fixture is all green with $NROWS rows" "$(grep -v '^ok' "$T/ctl.tsv" | head -c 600) $(head -c 200 "$T/ctl.tsv.err")"; fi
if [ "$(cat "$T/ctl.tsv.bd/arm" 2>/dev/null)" = "merge-base" ]; then pass "B0a: the control resolved its base through the merge-base arm (TRIO_BASE_ARM=merge-base)"
else fail "B0a: the control resolved its base through the merge-base arm" "arm=$(cat "$T/ctl.tsv.bd/arm" 2>/dev/null) status=$(cat "$T/ctl.tsv.bd/status" 2>/dev/null)"; fi
# B1: the baseline is derived, and the fixture's classes are what the hand-written list says (not a tautology: the list is the input).
python3 "$T/trio.py" --repo "$FX" --baseline "$FX/$BASELINE_REL" --today "$FIXTODAY" --mode emit --envs "$FIXENVS" > "$T/emit.tsv" 2> "$T/emit.err"
if diff <(grep -v '^#' "$T/fx-baseline.tsv") "$T/emit.tsv" > "$T/emit.diff"; then pass "B1: --emit-baseline on the fixture reproduces the hand-written baseline records (class, tag, expiry, @stems, @allow) exactly"
else fail "B1: --emit-baseline on the fixture reproduces the hand-written baseline records exactly" "$(head -c 500 "$T/emit.diff")"; fi
# B2: population facts: 6 exempt by structure (a tests/ dir with .test.sh, a test/ dir, a fixtures/ dir, a __tests__/ dir, .spec.ts, .tftest.hcl),
# 1 binary, 1 symlink, 6 excluded (kb x3, docs, the suite and the baseline by exact path)
if grep -qx 'TRIO_EXEMPT=6' "$T/ctl.tsv.err" && grep -qx 'TRIO_BINARY=1' "$T/ctl.tsv.err" && grep -qx 'TRIO_SYMLINKS=1' "$T/ctl.tsv.err" && grep -qx 'TRIO_EXCLUDED=6' "$T/ctl.tsv.err" && grep -qx 'TRIO_READSHAPE_HITS=7' "$T/ctl.tsv.err"; then
  pass "B2: the fixture population reports 6 exempt (every structural class), 1 binary, 1 symlink, 6 excluded (kb/docs/own files) and 7 read-shape files on stderr"
else fail "B2: the fixture population reports its exempt/binary/symlink/excluded/read-shape counts" "$(tr '\n' ' ' < "$T/ctl.tsv.err" | head -c 400)"; fi

# Mutation machinery ----------------------------------------------------------------------------
# prep <id>  — fresh git-init'd copy of the PRISTINE fixture at $D/fx; sets D
prep() {
  D="$T/mut/$1"
  assert_fixture_dir "$D"
  rm -rf "$D"; mkdir -p "$D" || { printf 'FAIL SETUP: mkdir %s\n' "$D" >&2; exit 1; }
  cp -a "$FX" "$D/fx" || { printf 'FAIL SETUP: copy fixture for %s\n' "$1" >&2; exit 1; }
  BL="$D/fx/$BASELINE_REL"
}
# commit_all  — commit the copy's current state on its branch (a PR commit on top of the base)
commit_all() { gc -C "$D/fx" add -A && gc -C "$D/fx" commit -q -m "mut" ; }
# edit <file> <old> <new>  — exact-once replacement (exit 1 when <old> is not unique: the edit then did not land)
edit() {
  python3 - "$1" "$2" "$3" <<'PYE'
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
if s.count(old) != 1:
    sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PYE
}
# bl_set <file> <name> <colno> <value>  — rewrite one column of one baseline row
bl_set() {
  awk -F'\t' -v OFS='\t' -v f="$1" -v n="$2" -v c="$3" -v val="$4" '$1 == f && $2 == n {$c = val} {print}' "$BL" > "$BL.new" && mv "$BL.new" "$BL"
}
bl_add() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >> "$BL"; }
bl_del() { awk -F'\t' -v f="$1" -v n="$2" '!($1 == f && $2 == n)' "$BL" > "$BL.new" && mv "$BL.new" "$BL"; }
# landed_dir  — "landed" when the copy's tree, history or scanner differs from the pristine fixture
landed_dir() {
  local ch=0
  diff -r -q --exclude=.git "$FX" "$D/fx" >/dev/null 2>&1 || ch=1
  if [ -f "$D/trio.py" ] && ! cmp -s "$T/trio.py" "$D/trio.py"; then ch=1; fi
  if [ "$(GITQ -C "$D/fx" rev-parse HEAD)" != "$FXHEAD" ]; then ch=1; fi
  if [ "$ch" -eq 1 ]; then printf 'landed' > "$D/landed"; else printf 'unchanged' > "$D/landed"; fi
}
# knobs <text>  — shell assignments for run_full (RF_*), sourced in a subshell
knobs() { printf '%s\n' "$1" > "$D/menv"; }
# run_in <dir>  — run the scanner on $D/fx honouring $D/menv; output $D/out
run_in() {
  local d="$1"
  (
    if [ -f "$d/menv" ]; then . "$d/menv"; fi
    run_full "$d/fx" "$d/fx/$BASELINE_REL" "$d/out"
  )
}
# mutant <id> <row> <desc> [substr] [arm]
#   expects $D/landed. The kill is attributed to the NAMED row: a scanner crash or a missing row is UNRESOLVED
#   (FAIL), never a kill; the optional substring must appear in that row, the optional arm in TRIO_BASE_ARM.
mutant() {
  local id="$1" row="$2" desc="$3" want="${4:-}" arm="${5:-}" d="$T/mut/$1" rc n st line
  MUTANTS_RUN=$((MUTANTS_RUN + 1))
  if [ "$(cat "$d/landed" 2>/dev/null)" = "landed" ]; then pass "$id lands: $desc"; else fail "$id lands: $desc" "the edit did not change the pristine copy"; return; fi
  run_in "$d"; rc=$?
  n="$(nrows "$d/out")"
  if [ "$rc" -ne 0 ] || [ "$n" -ne "$NROWS" ]; then
    fail "$id: $row is RED" "UNRESOLVED (a crash is not a kill): scanner rc=$rc rows=$n/$NROWS: $(head -c 200 "$d/out.err")"; return
  fi
  st="$(row_state "$d/out" "$row")"; line="$(row_line "$d/out" "$row")"
  if [ "$st" != "FAIL" ]; then fail "$id: $row is RED" "state=$st; $(head -c 200 "$d/out")"; return; fi
  if [ -n "$want" ] && [ "${line#*"$want"}" = "$line" ]; then fail "$id: $row is RED" "red, but not for the named reason: wanted '$want' in: ${line:0:300}"; return; fi
  if [ -n "$arm" ] && [ "$(cat "$d/out.bd/arm" 2>/dev/null)" != "$arm" ]; then fail "$id: $row is RED" "red, but TRIO_BASE_ARM=$(cat "$d/out.bd/arm" 2>/dev/null), wanted $arm"; return; fi
  pass "$id: $row is RED${want:+ ($want)}"
}
# green <id> <desc> [substr] [arm]  — a must-stay-green fixture: every row ok, all rows present
green() {
  local id="$1" desc="$2" want="${3:-}" arm="${4:-}" d="$T/mut/$1" rc
  if [ "$(cat "$d/landed" 2>/dev/null)" != "landed" ]; then fail "$id: $desc" "the edit did not change the pristine copy"; return; fi
  run_in "$d"; rc=$?
  if [ "$rc" -ne 0 ] || [ "$(nrows "$d/out")" -ne "$NROWS" ] || ! all_ok "$d/out"; then fail "$id: $desc" "rc=$rc $(grep -v '^ok' "$d/out" | head -c 400)"; return; fi
  if [ -n "$want" ] && ! has_text "$d/out" "$want"; then fail "$id: $desc" "green, but '$want' is not in the output: $(head -c 300 "$d/out")"; return; fi
  if [ -n "$arm" ] && [ "$(cat "$d/out.bd/arm" 2>/dev/null)" != "$arm" ]; then fail "$id: $desc" "TRIO_BASE_ARM=$(cat "$d/out.bd/arm" 2>/dev/null), wanted $arm"; return; fi
  pass "$id: $desc"
}
NEWYML=$'name: new\njobs:\n  j:\n    runs-on: x\n    steps:\n      - run: echo "$WEBHOOK_DEPLOY_SECRET"\n'

# ── M. the original matrix (M1-M13), now on a git fixture ───────────────────────────────────
prep m1
printf 'name: new\njobs:\n  j:\n    runs-on: x\n    env:\n      S: ${{ secrets.WEBHOOK_DEPLOY_SECRET }}\n' > "$D/fx/.github/workflows/new.yml"
landed_dir; mutant m1 T1 "a new consumer with no baseline row" ".github/workflows/new.yml WEBHOOK_DEPLOY_SECRET"

# M2 — a new key whose row IS in the baseline but has no @allow at the base (real merge-base arm)
prep m2
printf '  more: ${{ secrets.CF_ACCESS_CLIENT_SECRET }}\n' >> "$D/fx/.github/workflows/canary-status.yml"
bl_add .github/workflows/canary-status.yml CF_ACCESS_CLIENT_SECRET tier-a 2026-11-30 '#9294:PR-3'
commit_all; landed_dir; mutant m2 T4 "a baseline row (and its read) with no @allow at the merge-base copy" "has no @allow at the merge-base" merge-base

# M3 — a stale row: the consumer no longer reads the name
prep m3
bl_add scripts/gone.sh WEBHOOK_DEPLOY_SECRET tier-a 2026-11-30 '#9294:PR-2'
landed_dir; mutant m3 T2 "a baseline row whose consumer no longer reads the name" "scripts/gone.sh WEBHOOK_DEPLOY_SECRET"

# M4 — a past expiry on a blocking event that touches a row's file
prep m4
printf '# touched\n' >> "$D/fx/scripts/probe.sh"
knobs 'RF_TODAY=2027-01-01'
landed_dir; mutant m4 T3 "every tier-a row past its expiry on a PR that touches a row's file"

# M5 — the narrow carrier must not drag the host-destroy credential in: HCLOUD_TOKEN in a PR-3 file, a PR-4 file, and (computed group) after a re-tag
prep m5
printf 'env2:\n  H: ${{ secrets.HCLOUD_TOKEN }}\n' >> "$D/fx/.github/workflows/web-platform-release.yml"
landed_dir; mutant m5 T7 "HCLOUD_TOKEN named in an already-baselined PR-3 file"
prep m5b
printf 'export H="$HCLOUD_TOKEN"\n' >> "$D/fx/scripts/followthroughs/soak.sh"
landed_dir; mutant m5b T7 "HCLOUD_TOKEN named in an already-baselined PR-4 file"
prep m5c
printf 'env2:\n  H: ${{ secrets.HCLOUD_TOKEN }}\n' >> "$D/fx/.github/workflows/web-platform-release.yml"
bl_set .github/workflows/web-platform-release.yml WEBHOOK_DEPLOY_SECRET 5 '#9294:PR-2'
landed_dir; mutant m5c T7 "HCLOUD_TOKEN in a PR-3 file whose baseline tag was edited to PR-2 (T7 keys on the computed group)"

# M6 — the scan walks nothing (the empty file set: every scanned file is gone from the worktree)
prep m6
rm -rf "$D/fx/.github" "$D/fx/scripts" "$D/fx/apps" "$D/fx/plugins" "$D/fx/tests/x.test.sh"
landed_dir; mutant m6 T0 "an empty scan set"

# M7 — a file that already has one compliant baselined read gains a second trio name
prep m7
printf '  more: ${{ secrets.CF_ACCESS_CLIENT_SECRET }}\n' >> "$D/fx/.github/workflows/web-platform-release.yml"
landed_dir; mutant m7 T1 "a second trio name added to a baselined file (keyed by (file, name), not file)" "web-platform-release.yml CF_ACCESS_CLIENT_SECRET"

# M8 — a silent fallback to another credential on a logical line that reads a trio name
prep m8
printf 'x="$(doppler secrets get CF_ACCESS_CLIENT_ID --plain || doppler secrets get CI_SSH_ACCESS_TOKEN_SECRET --plain)"\n' >> "$D/fx/scripts/probe.sh"
landed_dir; mutant m8 T1 "a fallback pair with no baseline row" "FALLBACK:CI_SSH_ACCESS_TOKEN_SECRET"

# M9 — a triggers_replace that carries the rendered hooks.json unhashed
prep m9
edit "$D/fx/apps/web-platform/infra/server.tf" 'triggers_replace = sha256(join(",", [file("${path.module}/a.sh"), local.hooks_json]))' 'triggers_replace = join(",", [file("${path.module}/a.sh"), local.hooks_json])'
landed_dir; mutant m9 H1 "triggers_replace not wrapped in sha256("

# M10 — an output block that exposes the webhook secret
prep m10
printf 'output "leak" {\n  value = var.webhook_deploy_secret\n}\n' >> "$D/fx/apps/web-platform/infra/server.tf"
landed_dir; mutant m10 H2 "an output that references the webhook secret"

# M11 — a terraform_data input that stores the rendered hooks.json
prep m11
printf 'resource "terraform_data" "bad" {\n  input = local.hooks_json\n}\n' >> "$D/fx/apps/web-platform/infra/server.tf"
landed_dir; mutant m11 H3 "a terraform_data input that references the rendered hooks.json"

# M12 — a duplicate baseline row
prep m12
bl_add .github/workflows/web-platform-release.yml WEBHOOK_DEPLOY_SECRET tier-a 2026-11-30 '#9294:PR-3'
landed_dir; mutant m12 T5 "a duplicate (file, name) baseline row" "duplicate"

# M13 — an issue tag outside the four groups
prep m13
bl_set .github/workflows/canary-status.yml CF_ACCESS_CLIENT_ID 5 '#9294:PR-9'
landed_dir; mutant m13 T5 "a baseline row tagged outside PR-1..PR-4" "PR-9"

# ── R1-R4 (F-A2): the structural test class replaces the name-based exemption ─────────────────────
prep m14
printf '%s' "$NEWYML" > "$D/fx/.github/workflows/test-x.yml"
landed_dir; mutant m14 T1 "R1: a test-named workflow naming the trio (nothing under .github/ is exempt)" ".github/workflows/test-x.yml"
prep m14b
mkdir -p "$D/fx/.github/scripts/tests"; printf '#!/usr/bin/env bash\necho "$WEBHOOK_DEPLOY_SECRET"\n' > "$D/fx/.github/scripts/tests/foo.test.sh"
landed_dir; mutant m14b T1 "R1: .github/scripts/tests/foo.test.sh (a tests/ directory AND a .test. suffix) is still scanned: nothing under .github/ is exempt" ".github/scripts/tests/foo.test.sh"
prep m15
mkdir -p "$D/fx/scripts/lib"; printf '#!/usr/bin/env bash\necho "$CF_ACCESS_CLIENT_ID"\n' > "$D/fx/scripts/lib/test-x.sh"
landed_dir; mutant m15 T1 "R2: scripts/lib/test-x.sh naming the trio (the /test- name is no longer an exemption)" "scripts/lib/test-x.sh"
prep m16
printf '#!/usr/bin/env bash\nS="${{ secrets.WEBHOOK_DEPLOY_SECRET }}"\n' > "$D/fx/scripts/foo.test.sh"
landed_dir; mutant m16 T1 "R3: scripts/foo.test.sh holding a secrets.WEBHOOK_DEPLOY_SECRET read (exempt by shape, still needs a row)" "scripts/foo.test.sh WEBHOOK_DEPLOY_SECRET"
prep m16b
printf '#!/usr/bin/env bash\ndoppler secrets get CF_ACCESS_CLIENT_SECRET --plain\n' > "$D/fx/apps/web-platform/test/z.sh"
landed_dir; mutant m16b T1 "R3: a doppler secrets get read inside a tests directory (second read shape, second exempt class)" "apps/web-platform/test/z.sh CF_ACCESS_CLIENT_SECRET"
prep m17
printf '#!/usr/bin/env bash\necho "$CF_ACCESS_CLIENT_SECRET"\n' > "$D/fx/.github/scripts/new.sh"
landed_dir; mutant m17 T1 "R4: a new .github/scripts/new.sh naming the trio" ".github/scripts/new.sh"
prep m18
mkdir -p "$D/fx/plugins/soleur/skills/z"; printf '#!/usr/bin/env bash\necho "$CF_ACCESS_CLIENT_SECRET"\n' > "$D/fx/plugins/soleur/skills/z/new.sh"
landed_dir; mutant m18 T1 "R4: a new plugins/soleur/skills/z/new.sh naming the trio" "plugins/soleur/skills/z/new.sh"
prep m19
printf 'const s = process.env.CF_ACCESS_CLIENT_SECRET;\n' > "$D/fx/apps/web-platform/server/new.ts"
landed_dir; mutant m19 T1 "R4: a new apps/web-platform/server/new.ts naming the trio" "apps/web-platform/server/new.ts"
prep m19b
printf 'The CF_ACCESS_CLIENT_ID pair authenticates the tunnel.\n' > "$D/fx/plugins/soleur/skills/ship/NOTES.md"
landed_dir; mutant m19b T1 "R4: a .md outside the knowledge base and docs that merely names the trio is scanned" "plugins/soleur/skills/ship/NOTES.md"

# ── R5 (F-A3): the token family ───────────────────────────────────────────────────────────────────
prep m20
printf '#!/usr/bin/env bash\nexport TF_VAR_WEBHOOK_DEPLOY_SECRET="$X"\n' > "$D/fx/scripts/v1.sh"
landed_dir; mutant m20 T1 "R5: TF_VAR_WEBHOOK_DEPLOY_SECRET is the trio (row name WEBHOOK_DEPLOY_SECRET)" "scripts/v1.sh WEBHOOK_DEPLOY_SECRET"
prep m21
printf '#!/usr/bin/env bash\necho "$WEBHOOK_DEPLOY_SECRET_OLD"\n' > "$D/fx/scripts/v2.sh"
landed_dir; mutant m21 T1 "R5: WEBHOOK_DEPLOY_SECRET_OLD is its own key" "scripts/v2.sh WEBHOOK_DEPLOY_SECRET_OLD"
prep m22
printf 'variable "webhook_deploy_secret_prev" {}\n' > "$D/fx/apps/web-platform/infra/prev.tf"
landed_dir; mutant m22 T1 "R5: lower-case webhook_deploy_secret_prev merges into the upper-case family key" "prev.tf WEBHOOK_DEPLOY_SECRET_PREV"
prep m22b
printf '#!/usr/bin/env bash\nexport TF_VAR_cf_access_client_id="$X"\n' > "$D/fx/scripts/v3.sh"
landed_dir; mutant m22b T1 "R5: TF_VAR_cf_access_client_id is CF_ACCESS_CLIENT_ID" "scripts/v3.sh CF_ACCESS_CLIENT_ID"

# ── R6: the Access token under its Terraform spellings (ALIAS) ────────────────────────────────────
prep m23
printf '#!/usr/bin/env bash\nX="$(terraform output -raw access_service_token_client_secret)"\n' > "$D/fx/scripts/tf-out.sh"
landed_dir; mutant m23 T1 "R6: terraform output -raw access_service_token_client_secret in a new script (ALIAS)" "scripts/tf-out.sh ALIAS:ACCESS_SERVICE_TOKEN_CLIENT_SECRET"
prep m23b
printf 'locals { i = cloudflare_zero_trust_access_service_token.other.client_id }\n' > "$D/fx/apps/web-platform/infra/other.tf"
landed_dir; mutant m23b T1 "R6: the cloudflare_zero_trust_access_service_token.<r>.client_id attribute in a new .tf (ALIAS)" "other.tf ALIAS:ACCESS_SERVICE_TOKEN_CLIENT_ID"

# ── R7-R9 (F-B): tag, expiry, class ───────────────────────────────────────────────────────────────
prep m24
bl_set apps/web-platform/infra/variables.tf WEBHOOK_DEPLOY_SECRET 5 '#9294:PR-3'
commit_all; landed_dir; mutant m24 T4 "R7: the tag of a sink row changed vs the base copy" "tag of apps/web-platform/infra/variables.tf WEBHOOK_DEPLOY_SECRET changed"
prep m25
bl_set .github/workflows/canary-status.yml CF_ACCESS_CLIENT_ID 4 2026-12-15
commit_all; landed_dir; mutant m25 T4 "R8: a tier-a expiry later than the base copy's with no ADR line" "Re-date"
prep c25
bl_set .github/workflows/canary-status.yml CF_ACCESS_CLIENT_ID 4 2026-12-15
printf 'Re-date: 2026-12-15 the git-data rehearsal slipped a week. Ruled by CTO\n' >> "$D/fx/$ADR_REL"
commit_all; landed_dir; green c25 "R8: the same extension is green with the ADR-241 Re-date line in a baseline/ADR-only diff"
prep m26
bl_set .github/workflows/canary-status.yml CF_ACCESS_CLIENT_ID 4 2026-12-15
printf 'Re-date: 2026-12-15 the git-data rehearsal slipped a week. Ruled by CTO\n' >> "$D/fx/$ADR_REL"
printf '# touched\n' >> "$D/fx/scripts/host-user.sh"
commit_all; landed_dir; mutant m26 T4 "R8: the Re-date line with a code file in the same diff is not a baseline-only change" "Re-date"
prep m27
bl_set .github/workflows/canary-status.yml CF_ACCESS_CLIENT_ID 4 2026-12-15
printf 'Re-date: 2026-12-16 the git-data rehearsal slipped a week. Ruled by CTO\n' >> "$D/fx/$ADR_REL"
commit_all; landed_dir; mutant m27 T4 "R8: a Re-date line whose date is not the new expiry" "Re-date"
prep m28
bl_set .github/workflows/deploy-chan.yml WEBHOOK_DEPLOY_SECRET 3 tier-a
bl_set .github/workflows/deploy-chan.yml WEBHOOK_DEPLOY_SECRET 4 2026-11-30
commit_all; landed_dir; mutant m28 T4 "R9: class tier-b -> tier-a moves backwards" "moved backwards or sideways"
prep m29
bl_set .github/workflows/migrate.yml CF_ACCESS_CLIENT_ID 3 tier-b
bl_set .github/workflows/migrate.yml CF_ACCESS_CLIENT_ID 4 -
landed_dir; mutant m29 T5c "R9: tier-a -> tier-b with no environment in the job fails the class recompute" ".github/workflows/migrate.yml CF_ACCESS_CLIENT_ID (baseline tier-b, computed tier-a)"
prep c29
printf 'name: migrate\njobs:\n  m:\n    runs-on: ubuntu-latest\n    environment: deploy-channel\n    steps:\n      - run: echo "$CF_ACCESS_CLIENT_ID"\n' > "$D/fx/.github/workflows/migrate.yml"
bl_set .github/workflows/migrate.yml CF_ACCESS_CLIENT_ID 3 tier-b
bl_set .github/workflows/migrate.yml CF_ACCESS_CLIENT_ID 4 -
commit_all; landed_dir; green c29 "R9: a migration PR (read shape -> loader env on a Tier-B environment, tier-a -> tier-b) is green"
prep m28b
printf 'doppler run -p soleur -c prd_terraform -- true\n' >> "$D/fx/scripts/host-user.sh"
bl_set scripts/host-user.sh WEBHOOK_DEPLOY_SECRET 3 tier-a
bl_set scripts/host-user.sh WEBHOOK_DEPLOY_SECRET 4 2026-11-30
commit_all; landed_dir; mutant m28b T4 "R9: class sink -> tier-a (the file now holds a doppler run on prd_terraform) moves backwards" "moved backwards or sideways"
prep m28c
printf 'doppler run -p soleur -c prd_terraform -- true\n' >> "$D/fx/scripts/host-user.sh"
landed_dir; mutant m28c T5c "R9: a doppler run on prd_terraform makes a sink file tier-a (the read shape is detected)" "scripts/host-user.sh WEBHOOK_DEPLOY_SECRET (baseline sink, computed tier-a)"

# ── R10 (F-B): renames ────────────────────────────────────────────────────────────────────────────
prep c30
gc -C "$D/fx" mv scripts/followthroughs/soak.sh scripts/followthroughs/soak2.sh
bl_del scripts/followthroughs/soak.sh WEBHOOK_DEPLOY_SECRET
bl_add scripts/followthroughs/soak2.sh WEBHOOK_DEPLOY_SECRET tier-a 2026-11-30 '#9294:PR-4'
commit_all; landed_dir; green c30 "R10: a renamed consumer carrying its row (same name, class, tag, expiry) is not a new key"
prep c30b
gc -C "$D/fx" mv apps/web-platform/infra/variables.tf apps/web-platform/infra/vars.tf
bl_del apps/web-platform/infra/variables.tf WEBHOOK_DEPLOY_SECRET
bl_add apps/web-platform/infra/vars.tf WEBHOOK_DEPLOY_SECRET sink - '#9294:PR-2'
commit_all; landed_dir; green c30b "R10: a renamed sink carrying its row is not a new key either"
prep m30
gc -C "$D/fx" mv apps/web-platform/infra/variables.tf apps/web-platform/infra/vars.tf
bl_del apps/web-platform/infra/variables.tf WEBHOOK_DEPLOY_SECRET
bl_add apps/web-platform/infra/vars.tf WEBHOOK_DEPLOY_SECRET sink - '#9294:PR-3'
commit_all; landed_dir; mutant m30 T4 "R10: a rename that carries its row with a CHANGED tag" "tag of apps/web-platform/infra/vars.tf WEBHOOK_DEPLOY_SECRET changed"
prep m31
mkdir -p "$D/fx/apps/web-platform/infra/tests"
gc -C "$D/fx" mv apps/web-platform/infra/variables.tf apps/web-platform/infra/tests/variables.tf
bl_del apps/web-platform/infra/variables.tf WEBHOOK_DEPLOY_SECRET
commit_all; landed_dir; mutant m31 T4 "R10: a rename INTO an exempt path (tests/) with the row dropped while the file still names the trio" "renamed into the exempt/excluded path"
prep m31b
_fixture_kbdir="knowledge-base/x"
mkdir -p "$D/fx/$_fixture_kbdir"
gc -C "$D/fx" mv scripts/host-user.sh "$_fixture_kbdir/host-user.sh"
bl_del scripts/host-user.sh WEBHOOK_DEPLOY_SECRET
commit_all; landed_dir; mutant m31b T4 "R10: a rename INTO the knowledge base with the row dropped (the other excluded prefix)" "renamed into the exempt/excluded path"

# ── R11-R12 (F-B): the base fails closed; the introduction arm is legitimate only while the suite is absent at the base ──
prep m33
knobs 'RF_REF=refs/remotes/origin/does-not-exist'
landed_dir
if GITQ -C "$D/fx" rev-parse --verify -q refs/remotes/origin/does-not-exist >/dev/null 2>&1; then printf 'unchanged' > "$D/landed"; else printf 'landed' > "$D/landed"; fi
mutant m33 T4 "R11: an unresolved base ref" "base unresolved (ref refs/remotes/origin/does-not-exist, arm merge-base)"
prep m33b
rm -rf "$D/fx"; GITQ clone -q --depth 1 "file://$FX" "$D/fx" 2>/dev/null
if [ "$(GITQ -C "$D/fx" rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then printf 'landed' > "$D/landed"; else printf 'unchanged' > "$D/landed"; fi
mutant m33b T4 "R11: a shallow clone without the base ref says so" "shallow clone"
prep m34
knobs 'RF_REF=refs/remotes/origin/nobl'
printf 'landed' > "$D/landed"
mutant m34 T4 "R12: the suite exists at the base but the baseline does not (not an introduction)" "base unresolved"
prep c34
knobs 'RF_REF=refs/remotes/origin/pre'
printf 'landed' > "$D/landed"
green c34 "R12: the introduction arm is green while the suite is absent at the base (TRIO_BASE_ARM=introduction)" "introduction: the suite is absent at the base" introduction
prep c34b
knobs 'RF_REF=refs/remotes/origin/head'
printf 'landed' > "$D/landed"
green c34b "R11: a push to main (HEAD is the ref) compares against HEAD^1 (TRIO_BASE_ARM=head1)" "" head1
prep m35
printf '  more: ${{ secrets.CF_ACCESS_CLIENT_SECRET }}\n' >> "$D/fx/.github/workflows/canary-status.yml"
bl_add .github/workflows/canary-status.yml CF_ACCESS_CLIENT_SECRET tier-a 2026-11-30 '#9294:PR-3'
commit_all; gc -C "$D/fx" update-ref refs/remotes/origin/head HEAD
knobs 'RF_REF=refs/remotes/origin/head'
landed_dir; mutant m35 T4 "R11: growth in the HEAD commit on the head1 arm" "has no @allow" head1
prep c35
knobs 'RF_REF=refs/remotes/origin/does-not-exist; TRIO_ALLOW_NO_BASE=1; GITHUB_ACTIONS=false'
printf 'landed' > "$D/landed"
green c35 "R11: TRIO_ALLOW_NO_BASE=1 outside CI skips T4 loudly (and only there)" "SKIPPED via TRIO_ALLOW_NO_BASE=1"
prep m35b
knobs 'RF_REF=refs/remotes/origin/does-not-exist; TRIO_ALLOW_NO_BASE=1; GITHUB_ACTIONS=true'
printf 'landed' > "$D/landed"
mutant m35b T4 "R11: TRIO_ALLOW_NO_BASE=1 is ignored under GITHUB_ACTIONS=true" "base unresolved"

# ── R13 (F-B): @allow ─────────────────────────────────────────────────────────────────────────────
prep m36
printf 'echo "$WEBHOOK_DEPLOY_SECRET_NEXT"\n' >> "$D/fx/scripts/host-user.sh"
bl_add scripts/host-user.sh WEBHOOK_DEPLOY_SECRET_NEXT sink - '#9294:PR-1'
commit_all; landed_dir; mutant m36 T4 "R13: a new key with no @allow at the base" "has no @allow at the merge-base"
prep c36
printf 'variable "webhook_deploy_secret_next" {}\n' >> "$D/fx/apps/web-platform/infra/variables.tf"
bl_add apps/web-platform/infra/variables.tf WEBHOOK_DEPLOY_SECRET_NEXT sink - '#9294:PR-1'
awk -F'\t' '!($1 == "@allow" && $2 == "apps/web-platform/infra/variables.tf")' "$BL" > "$BL.new" && mv "$BL.new" "$BL"
commit_all; landed_dir; green c36 "R13: a new key that spends an @allow present at the base (and deletes it) is green"
prep c36b
printf 'locals { n = var.webhook_deploy_secret_next }\n' >> "$D/fx/apps/web-platform/infra/server.tf"
bl_add apps/web-platform/infra/server.tf WEBHOOK_DEPLOY_SECRET_NEXT sink - '#9294:PR-1'
awk -F'\t' '!($1 == "@allow" && $2 == "apps/web-platform/infra/server.tf")' "$BL" > "$BL.new" && mv "$BL.new" "$BL"
commit_all; landed_dir; green c36b "R13: the second @allow member (server.tf) spends the same way"
prep m37
printf 'echo "$WEBHOOK_DEPLOY_SECRET_NEXT"\n' >> "$D/fx/scripts/host-user.sh"
printf '@allow\tscripts/host-user.sh\tWEBHOOK_DEPLOY_SECRET_NEXT\t-\t#9294:PR-1\n' >> "$BL"
commit_all
awk -F'\t' '!($1 == "@allow" && $2 == "scripts/host-user.sh")' "$BL" > "$BL.new" && mv "$BL.new" "$BL"
bl_add scripts/host-user.sh WEBHOOK_DEPLOY_SECRET_NEXT sink - '#9294:PR-1'
commit_all; landed_dir; mutant m37 T4 "R13: an @allow added and spent in one diff (two commits of one PR)" "was added in the same diff that spends it"
prep m38
printf 'variable "webhook_deploy_secret_next" {}\n' >> "$D/fx/apps/web-platform/infra/variables.tf"
bl_add apps/web-platform/infra/variables.tf WEBHOOK_DEPLOY_SECRET_NEXT sink - '#9294:PR-1'
commit_all; landed_dir; mutant m38 T4 "R13: the row is added but the @allow it spends is not deleted" "was not deleted by the diff that spends it"

# ── R14 (F-D): expiry formats and the boundary ────────────────────────────────────────────────────
prep m39
bl_set .github/workflows/canary-status.yml CF_ACCESS_CLIENT_ID 4 20261130
landed_dir; mutant m39 T5 "R14: expiry 20261130 (basic ISO accepted by fromisoformat) is rejected" "20261130"
prep m40
bl_set .github/workflows/canary-status.yml CF_ACCESS_CLIENT_ID 4 2026-W40-1
landed_dir; mutant m40 T5 "R14: expiry 2026-W40-1 (ISO week date) is rejected" "2026-W40-1"
prep m41
bl_set .github/workflows/canary-status.yml CF_ACCESS_CLIENT_ID 4 -
landed_dir; mutant m41 T5 "R14: a tier-a row with expiry '-'" "tier-a expiry '-'"
prep m42
bl_set .github/workflows/canary-status.yml CF_ACCESS_CLIENT_ID 4 2026-02-30
landed_dir; mutant m42 T5 "R14: an impossible calendar date" "2026-02-30"
prep m43
bl_set .github/workflows/canary-status.yml CF_ACCESS_CLIENT_ID 4 2027-04-01
landed_dir; mutant m43 T5 "R14: a tier-a expiry beyond MAX_EXPIRY (2027-03-31)" "MAX_EXPIRY"
prep m43b
bl_set apps/web-platform/infra/variables.tf WEBHOOK_DEPLOY_SECRET 4 2026-11-30
landed_dir; mutant m43b T5 "R14: a sink row must carry expiry '-'" "a sink row needs expiry '-'"
prep c44
printf '# touched\n' >> "$D/fx/scripts/probe.sh"
knobs 'RF_TODAY=2026-11-30'
landed_dir; green c44 "R14: today == expiry on a blocking PR that touches a row's file is green (the expiry day itself)" "T3w:"
prep c44a
knobs 'RF_TODAY=2026-11-09'
printf 'landed' > "$D/landed"
green c44a "R14: 21 days before expiry is green with a T3w warning" "expire within 21 days"
if has_text "$D/out.ann" '::warning::'; then pass "c44a: the T3w row emits a ::warning:: annotation naming the remaining tier-a count"; else fail "c44a: the T3w row emits a ::warning:: annotation naming the remaining tier-a count" "ann: $(head -c 200 "$D/out.ann" 2>/dev/null)"; fi
prep c44b
knobs 'RF_TODAY=2026-11-08'
printf 'landed' > "$D/landed"
green c44b "R14: 22 days before expiry is green with no warning" "T3w: no tier-a row expires within 21 days"
prep m44
printf '# touched\n' >> "$D/fx/scripts/probe.sh"
knobs 'RF_TODAY=2026-12-01'
landed_dir; mutant m44 T3 "R14: expiry + 1 day on a blocking PR that touches a row's file"

# ── R15 (F-D): the event table (all rows past expiry: today 2027-01-01) ───────────────────────────
prep c45
printf '# touched\n' >> "$D/fx/scripts/probe.sh"
knobs 'RF_TODAY=2027-01-01; RF_EVENT=push; RF_EVENTREF=refs/heads/main'
landed_dir; green c45 "R15: expired + push to main touching a row's file is green with T3m" "T3m: $FX_TIER_A_ROWS tier-a rows are past expiry (non-blocking on main by ruling)"
if has_text "$D/out.ann" '::error::T3m'; then pass "c45: the main-class expiry emits an ::error:: annotation yet exits green"; else fail "c45: the main-class expiry emits an ::error:: annotation yet exits green" "ann: $(head -c 200 "$D/out.ann" 2>/dev/null)"; fi
prep c45b
knobs 'RF_TODAY=2027-01-01; RF_EVENT=schedule; RF_EVENTREF=refs/heads/main'
printf '# touched\n' >> "$D/fx/scripts/probe.sh"
landed_dir; green c45b "R15: expired + schedule is green with T3m" "T3m: $FX_TIER_A_ROWS tier-a rows are past expiry"
prep c45c
knobs 'RF_TODAY=2027-01-01; RF_EVENT=workflow_dispatch; RF_EVENTREF=refs/heads/main'
printf '# touched\n' >> "$D/fx/scripts/probe.sh"
landed_dir; green c45c "R15: expired + workflow_dispatch on main is green with T3m" "T3m: $FX_TIER_A_ROWS tier-a rows are past expiry"
prep c45d
knobs 'RF_TODAY=2027-01-01; RF_EVENT=merge_group; RF_EVENTREF=refs/heads/gh-readonly-queue/main/pr-1'
printf '# touched\n' >> "$D/fx/scripts/probe.sh"
landed_dir; green c45d "R15: expired + a merge-queue gate is green with T3m" "T3m: $FX_TIER_A_ROWS tier-a rows are past expiry"
prep c46
knobs 'RF_TODAY=2027-01-01; RF_EVENT=pull_request; RF_EVENTREF=refs/pull/1/merge'
printf 'unrelated\n' > "$D/fx/README.md"
landed_dir; green c46 "R15: expired + a PR that touches no row's file is green with T3w" "none of their files"
prep m46
knobs 'RF_TODAY=2027-01-01; RF_EVENT=pull_request; RF_EVENTREF=refs/pull/1/merge'
printf '# touched\n' >> "$D/fx/scripts/probe.sh"
landed_dir; mutant m46 T3 "R15: expired + a PR that touches a row's file is RED" "scripts/probe.sh"
prep m47
knobs 'RF_TODAY=2027-01-01; RF_EVENT=workflow_dispatch; RF_EVENTREF=refs/heads/feat-x'
printf '# touched\n' >> "$D/fx/scripts/probe.sh"
landed_dir; mutant m47 T3 "R15: expired + a dispatch on a non-main ref is blocking"
prep m47b
knobs 'RF_TODAY=2027-01-01; RF_EVENT=pull_request; RF_EVENTREF=refs/pull/1/merge'
printf 'plan fixture, edited\n' >> "$D/fx/$PLAN_REL"
landed_dir; mutant m47b T3 "R15: expired + a PR that touches only the plan is blocking (the plan is a governed file)"
prep m47c
knobs 'RF_TODAY=2027-01-01'
printf '# touched\n' >> "$D/fx/scripts/probe.sh"
landed_dir; mutant m47c T3 "R15: expired + no event at all (a local run) defaults to PR-like and blocks"

# ── R16 (F-A3): the stems are pinned ──────────────────────────────────────────────────────────────
prep m50
cp "$T/trio.py" "$D/trio.py"
edit "$D/trio.py" 'STEMS = ["WEBHOOK_DEPLOY_SECRET", "CF_ACCESS_CLIENT_ID", "CF_ACCESS_CLIENT_SECRET"]' 'STEMS = ["WEBHOOK_DEPLOY_SECRET", "CF_ACCESS_CLIENT_ID"]'
knobs "RF_PY=$D/trio.py"
landed_dir; mutant m50 T6 "R16: a stem dropped from the scanner constant" "STEMS"
prep m51
edit "$BL" '@stems WEBHOOK_DEPLOY_SECRET,CF_ACCESS_CLIENT_ID,CF_ACCESS_CLIENT_SECRET' '@stems WEBHOOK_DEPLOY_SECRET,CF_ACCESS_CLIENT_ID'
landed_dir; mutant m51 T6 "R16: a stem dropped from the baseline header" "STEMS"
prep m52
cp "$T/trio.py" "$D/trio.py"
edit "$D/trio.py" 'STEMS = ["WEBHOOK_DEPLOY_SECRET", "CF_ACCESS_CLIENT_ID", "CF_ACCESS_CLIENT_SECRET"]' 'STEMS = ["WEBHOOK_DEPLOY_SECRET", "CF_ACCESS_CLIENT_ID"]'
edit "$BL" '@stems WEBHOOK_DEPLOY_SECRET,CF_ACCESS_CLIENT_ID,CF_ACCESS_CLIENT_SECRET' '@stems WEBHOOK_DEPLOY_SECRET,CF_ACCESS_CLIENT_ID'
bl_del .github/workflows/cutover-inngest.yml CF_ACCESS_CLIENT_SECRET
knobs "RF_PY=$D/trio.py"
commit_all; landed_dir; mutant m52 T6 "R16: constant, header AND the dropped stem's rows removed together still differ from the base copy" "base copy"

# ── R17 (F-A1): an unreadable scanned file ────────────────────────────────────────────────────────
prep m53
chmod 000 "$D/fx/scripts/probe.sh"
if [ ! -r "$D/fx/scripts/probe.sh" ]; then printf 'landed' > "$D/landed"; else printf 'unchanged' > "$D/landed"; fi
mutant m53 T8 "R17: a scanned file that exists but cannot be read" "scripts/probe.sh"
chmod 644 "$D/fx/scripts/probe.sh"

# ── R18 (F-C): the Tier-B environment proof, against a FIXTURE environment set ────────────────────
# The control's deploy-chan.yml (scalar) and deploy-chan2.yml (mapping form, quoted, 4-space indent, odd step keys,
# one job on deploy-channel and one on infra-privileged) are tier-b under the set {infra-privileged, deploy-channel}.
prep m54
knobs 'RF_ENVS=infra-privileged'
printf 'landed' > "$D/landed"
mutant m54 T5c "R18: deploy-channel removed from the fixture environment set: the jobs naming the trio are no longer Tier-B" "deploy-chan.yml WEBHOOK_DEPLOY_SECRET (baseline tier-b, computed tier-a)"
prep m54b
edit "$D/fx/.github/workflows/deploy-chan2.yml" "        environment: 'infra-privileged'" "        timeout-minutes: 5"
landed_dir; mutant m54b T5c "R18: one of two jobs naming the trio loses its environment: the file is no longer tier-b" "deploy-chan2.yml CF_ACCESS_CLIENT_ID (baseline tier-b, computed tier-a)"
prep m54c
edit "$D/fx/.github/workflows/deploy-chan.yml" 'curl -H "X-Sig: $WEBHOOK_DEPLOY_SECRET" https://example.invalid' 'curl -H "X-Sig: ${{ secrets.WEBHOOK_DEPLOY_SECRET }}" https://example.invalid'
landed_dir; mutant m54c T5c 'R18: a ${{ secrets.X }} read inside a Tier-B-environment job is still a direct-store read shape (tier-a)' "deploy-chan.yml WEBHOOK_DEPLOY_SECRET (baseline tier-b, computed tier-a)"
prep m54e
edit "$D/fx/.github/workflows/deploy-chan.yml" 'curl -H "X-Sig: $WEBHOOK_DEPLOY_SECRET" https://example.invalid' 'doppler secrets get WEBHOOK_DEPLOY_SECRET -c prd_terraform --plain'
landed_dir; mutant m54e T5c "R18: a doppler secrets get on prd_terraform inside a Tier-B-environment job is tier-a whatever the environment" "deploy-chan.yml WEBHOOK_DEPLOY_SECRET (baseline tier-b, computed tier-a)"
prep c54
knobs 'RF_ENVS=; RF_SIB='"$ROOT/$SIBLING_REL"
printf 'landed' > "$D/landed"
green c54 "E1: with the environment set single-sourced from the sibling census (plus the pending deploy-channel) the fixture is all green" "E1: the Tier-B environment set is single-sourced from"
prep m54d
cp "$T/trio.py" "$D/trio.py"
edit "$D/trio.py" 'PENDING_ENVS = {"deploy-channel", "inngest-cutover"}' 'PENDING_ENVS = {"deploy-channel", "inngest-cutover", "not-a-real-environment"}'
knobs "RF_PY=$D/trio.py; RF_ENVS=; RF_SIB=$ROOT/$SIBLING_REL"
landed_dir; mutant m54d E1 "R18: a pending environment name the sibling census does not hold is not accepted" "not-a-real-environment"

# ── R19 (F-B): the seams are refused under GITHUB_ACTIONS=true ────────────────────────────────────
_seam_probe() { # <seam> <ci:true|false> -> prints "<rc>|<stderr first line>"
  local out rc
  out="$(env -u GITHUB_ACTIONS -u TRIO_TODAY -u TRIO_BASE_REF -u TRIO_BASELINE -u TRIO_REPO_ROOT GITHUB_ACTIONS="$2" "$1=x" bash "$SUITE" --seams-check 2>&1 >/dev/null)"; rc=$?
  printf '%s|%s' "$rc" "${out%%$'\n'*}"
}
MUTANTS_RUN=$((MUTANTS_RUN + 1))
pass "m55 lands: the four seams are probed under GITHUB_ACTIONS=true and under a local shell"
_m55_bad=""
for _sm in TRIO_TODAY TRIO_BASE_REF TRIO_BASELINE TRIO_REPO_ROOT; do
  _r="$(_seam_probe "$_sm" true)"
  case "$_r" in 1\|"FAIL SETUP: $_sm is set under GITHUB_ACTIONS=true"*) : ;; *) _m55_bad="$_m55_bad $_sm(${_r:0:80})" ;; esac
done
if [ -z "$_m55_bad" ]; then pass "m55: FAIL SETUP for each of the four seams under GITHUB_ACTIONS=true"; else fail "m55: FAIL SETUP for each of the four seams under GITHUB_ACTIONS=true" "not refused:$_m55_bad"; fi
_c55_bad=""
for _sm in TRIO_TODAY TRIO_BASE_REF TRIO_BASELINE TRIO_REPO_ROOT; do
  _r="$(env -u GITHUB_ACTIONS "$_sm=x" bash "$SUITE" --seams-check 2>&1)"; _rc=$?
  [ "$_rc" -eq 0 ] && [ "$_r" = "SEAMS OK" ] || _c55_bad="$_c55_bad $_sm"
done
_r="$(env -u TRIO_TODAY -u TRIO_BASE_REF -u TRIO_BASELINE -u TRIO_REPO_ROOT GITHUB_ACTIONS=true bash "$SUITE" --seams-check 2>&1)"; _rc=$?
[ "$_rc" -eq 0 ] && [ "$_r" = "SEAMS OK" ] || _c55_bad="$_c55_bad ci-without-seams"
if [ -z "$_c55_bad" ]; then pass "c55: the seams are honoured locally, and CI without seams is fine"; else fail "c55: the seams are honoured locally, and CI without seams is fine" "refused:$_c55_bad"; fi

# ── Other must-stay-green fixtures and harness rows ───────────────────────────────────────────────
# (1) A must-PASS input that is NOT the canonical: different indentation, a comment-only mention, the family look-alikes.
prep c2
printf '        # CF_ACCESS_CLIENT_SECRET named only in a comment\n      - run: echo "a   trio:   WEBHOOK_DEPLOY_SECRET   is baselined"\n' >> "$D/fx/.github/workflows/web-platform-release.yml"
printf '#!/usr/bin/env bash\nFOO_WEBHOOK_DEPLOY_SECRETX=1\nWEBHOOK_DEPLOY_SECRETX=2\nXCF_ACCESS_CLIENT_ID=3\n// CF_ACCESS_CLIENT_ID in a slash comment\n' > "$D/fx/scripts/lookalike.sh"
printf 'The CF_ACCESS_CLIENT_ID is mentioned in a knowledge-base note.\n' > "$D/fx/knowledge-base/n.md"
landed_dir; green c2 "a comment-only mention, a re-indented baselined read, look-alike names (FOO_..._SECRETX) and a kb note stay green"
# (2) The name match is a WHOLE token: WEBHOOK_DEPLOY_SECRET_NEXT is its own name, not a hit on the base name.
prep c3
printf 'S: ${{ secrets.WEBHOOK_DEPLOY_SECRET_NEXT }}\n' > "$D/fx/scripts/nxt.sh"
landed_dir; run_in "$D"
if [ "$(row_state "$D/out" T1)" = "FAIL" ] && awk -F'\t' '$2 ~ /^T1:/ {n = split($3, a, "; "); for (i = 1; i <= n; i++) {if (a[i] == "scripts/nxt.sh WEBHOOK_DEPLOY_SECRET") bad = 1; if (a[i] == "scripts/nxt.sh WEBHOOK_DEPLOY_SECRET_NEXT") ok = 1}} END {exit !(ok && !bad)}' "$D/out"; then pass "C3: the rotation next-secret is its own name (the base-name pair is NOT reported for nxt.sh)"
else fail "C3: the rotation next-secret is its own name (the base-name pair is NOT reported for nxt.sh)" "$(head -c 300 "$D/out")"; fi
# (3) The comment filter is whole-line only: a trailing comment after a real read does not hide it (far side of C2).
prep m56
printf '#!/usr/bin/env bash\necho "$CF_ACCESS_CLIENT_SECRET" # why\n' > "$D/fx/scripts/trailing.sh"
landed_dir; mutant m56 T1 "a read followed by a trailing comment is still a read" "scripts/trailing.sh CF_ACCESS_CLIENT_SECRET"
# (4) Per-root floors trip in the fail direction and stay quiet in the pass direction.
_fl_hi="$(roots_below_floor "$T/ctl.tsv.err" ".github/workflows:99 .github/actions:1 .github/scripts:1 scripts:3 plugins:2 apps/web-platform:9")"
_fl_ok="$(roots_below_floor "$T/ctl.tsv.err" ".github/workflows:6 .github/actions:1 .github/scripts:1 scripts:3 plugins:2 apps/web-platform:9")"
if [ -n "$_fl_hi" ] && [ -z "$_fl_ok" ]; then pass "C5: the per-root floor check reds a root below its floor (.github/workflows 6<99) and is quiet at the measured counts"
else fail "C5: the per-root floor check reds a root below its floor and is quiet at the measured counts" "hi='$_fl_hi' ok='$_fl_ok'"; fi
# (4b) A population that git cannot enumerate is FAIL SETUP (rc 3), never an empty scan.
mkdir -p "$T/nogit"; printf 'x' > "$T/nogit/a"
GIT_CEILING_DIRECTORIES="$T" python3 "$T/trio.py" --repo "$T/nogit" --baseline "$FX/$BASELINE_REL" --today "$FIXTODAY" --envs "$FIXENVS" > /dev/null 2> "$T/nogit.err"; _ng=$?
if [ "$_ng" -eq 3 ] && grep -q '^FAIL SETUP: git ls-files failed' "$T/nogit.err"; then pass "C6: a repo git cannot enumerate is FAIL SETUP (rc 3), not an empty green scan"
else fail "C6: a repo git cannot enumerate is FAIL SETUP (rc 3), not an empty green scan" "rc=$_ng $(head -c 200 "$T/nogit.err")"; fi
# (5) A mutation that did not land is detected (the landed check itself is live).
prep c4
landed_dir
if [ "$(cat "$D/landed")" = "unchanged" ]; then pass "C4: an unedited fixture copy reads as 'unchanged' (the landed check can fail)"
else fail "C4: an unedited fixture copy reads as 'unchanged' (the landed check can fail)" "read: $(cat "$D/landed")"; fi
# (6) R20: the mutant runner must score a no-op edit FAIL (a runner that always passed would make every row above vacuous).
prep m60
landed_dir   # unchanged: the landing gate must fire
_p0=$passes; _f0=$fails
_nop1="$( (MUTANTS_RUN=0; mutant m60 T1 "no-op" >/dev/null 2>&1; printf '%s %s %s' "$passes" "$fails" "${FAILURES[${#FAILURES[@]}-1]:-}") )"
printf 'landed' > "$D/landed"   # forced past the landing gate: nothing was edited, so the named row cannot be RED
_nop2="$( (MUTANTS_RUN=0; mutant m60 T1 "no-op" >/dev/null 2>&1; printf '%s %s %s' "$passes" "$fails" "${FAILURES[${#FAILURES[@]}-1]:-}") )"
MUTANTS_RUN=$((MUTANTS_RUN + 1))
case "$_nop1" in "$_p0 $((_f0 + 1)) m60 lands: no-op") pass "m60 lands: the runner scores an UNCHANGED copy as FAIL at the landing gate" ;; *) fail "m60 lands: the runner scores an UNCHANGED copy as FAIL at the landing gate" "read: $_nop1" ;; esac
case "$_nop2" in "$((_p0 + 1)) $((_f0 + 1)) m60: T1 is RED") pass "m60: the runner scores a no-op edit as FAIL at the verdict gate (the named row stayed ok)" ;; *) fail "m60: the runner scores a no-op edit as FAIL at the verdict gate" "read: $_nop2" ;; esac

# Floors. MUTANT_FLOOR is exact.
MUTANT_FLOOR=72
if [ "$MUTANTS_RUN" -lt "$MUTANT_FLOOR" ]; then
  printf 'FAIL MUTANT FLOOR: only %s mutants executed, floor is %s -- a matrix row did not land or was deleted.\n' "$MUTANTS_RUN" "$MUTANT_FLOOR" >&2
  exit 1
fi
if [ "$MUTANTS_RUN" -gt "$MUTANT_FLOOR" ]; then
  printf 'FAIL MUTANT FLOOR: %s mutants executed but MUTANT_FLOOR is %s -- it is exact; raise it to %s.\n' "$MUTANTS_RUN" "$MUTANT_FLOOR" "$MUTANTS_RUN" >&2
  exit 1
fi
# Assertion FLOOR (exact), equal to the number of assertions this suite makes.
_ran=$((passes + fails))
FLOOR=193
if [ "$_ran" -lt "$FLOOR" ]; then
  printf 'FAIL ANTI-VACUITY: only %s assertions ran, floor is %s -- cases were deleted or the suite exited early.\n' "$_ran" "$FLOOR" >&2
  exit 1
fi
if [ "$_ran" -gt "$FLOOR" ]; then
  printf 'FAIL ANTI-VACUITY: %s assertions ran but FLOOR is %s -- it is exact; raise it to %s.\n' "$_ran" "$FLOOR" "$_ran" >&2
  exit 1
fi
if [ "${#FAILURES[@]}" -ne "$fails" ]; then
  printf 'FAIL LEDGER: %s failures counted but %s recorded\n' "$fails" "${#FAILURES[@]}" >&2; exit 1
fi
printf '\n=== trio-baseline-census: %d passed, %d failed ===\n\n' "$passes" "$fails"
_REACHED_VERDICT=1
exit $(( ${#FAILURES[@]} > 0 ))
