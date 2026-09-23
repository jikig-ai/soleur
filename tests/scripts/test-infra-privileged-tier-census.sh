#!/usr/bin/env bash
#
# (#8209 Guard 1/2/4, ADR-239) The Tier-B privileged-credential census.
#
# PROPERTY. A credential that writes infrastructure, reads another tier's secrets, or reaches a
# third-party installation is reachable ONLY from `main`. The boundary is a GitHub environment
# secret on an environment whose deployment-branch policy is `main` only (ADR-239 D2), so the
# property decomposes into four things a static census can settle on every PR:
#
#   Guard 1  every job that can hold a Tier-B credential declares an `environment:`, every arm of
#            that declaration is in `tier_b_environments`, and every one of those environments has
#            a Terraform-declared `github_repository_environment_deployment_policy` with
#            `branch_pattern = "main"`. Plus AC3 (no `-c prd_terraform` read of a Tier-B name
#            outside the loader) and AC7b (the state-bucket writers are Tier B, and their backend
#            credentials come from `TF_STATE_AWS_*` first).
#   Guard 2  every `doppler run` reachable from a Tier-B job carries `--preserve-env`, so a value
#            the loader exported is never replaced by a same-named value from a Tier-A-writable
#            Doppler config (ADR-239 D6). `DOPPLER_TOKEN_WRITE` has read/write on `prd_terraform`
#            until operator step O11, so until then a branch actor can still plant a value there;
#            `--preserve-env` makes a planted value inert BY CONSTRUCTION rather than by trusting
#            that nobody plants one.
#   Guard 4  THE HIGHEST-SEVERITY GUARD IN THIS FILE. Every `removed { from = … }` block in
#            `apps/web-platform/infra/*.tf` and `apps/web-platform/infra/git-data-root-key/*.tf`
#            carries `lifecycle { destroy = false }` and is reached by the apply that owns its
#            root. `doppler_secret.github_app_id` and `doppler_secret.github_app_private_key` pin
#            `config = "prd"` — they are the soleur-ai App's LIVE RUNTIME IDENTITY, the key the web
#            app mints every connected user's installation token from, not a Terraform bookkeeping
#            copy. A `removed` block that destroys instead of forgetting is not a failed apply: it
#            is EVERY CONNECTED USER DISCONNECTED. Three ways to get there, and this file has a row
#            for each: a misspelled `from` address (Terraform then plans a plain DESTROY of the
#            orphan, because no `removed` block claims it); the right address with no `-target=`
#            line (the forget is never planned, the resource stays managed with no HCL, and the
#            next untargeted apply destroys it); and `lifecycle { destroy = false }` omitted, which
#            turns the forget into a delete outright.
#
# WHY ONE SUITE OVER EVERY WORKFLOW. The census is keyed on what a job REFERENCES, never on a
# hand-kept list of jobs, so a new Tier-B job cannot escape the rule by omission. Assembly is
# every file matched by `git ls-files '.github/workflows/*.yml' '.github/workflows/*.yaml'
# '.github/actions/**/action.yml'`, with totality checked against `git ls-files` (the walk is the
# filesystem, so an UNTRACKED new workflow is censused too — fail closed), plus every `*.tf` under
# `apps/*/infra` and `infra/` for the environment and backend models.
#
# WHAT IS NOT HERE, and why. The `terraform state list` limb of AC2c is an O0 operator
# precondition, not a CI gate: CI holds no state credential at PR time. It runs here only when
# IPT_STATE_LIST names a pasted list, and the fixture rows below prove the limb works. The
# `--preserve-env` SENTINEL row (Guard 2 row 5) belongs to
# `.github/actions/infra-credentials/infra-credentials.test.sh` (AC4), which runs the real Doppler
# CLI; a static census cannot observe an environment override. Guard 3 is
# `tests/scripts/test-git-data-root-token-census.sh` and Guard 5 is the `plan_only` shape guard.
#
# Harness conventions (plan › Guard Contract; ADR-193): the instrument self-test drives both
# helpers once each; mutation rows copy a PRISTINE fixture, assert the edit LANDED (md5 change
# plus an exact diff-line count), then require the NAMED census row RED; floors and the self-tests
# report with printf + exit, never through the helpers they backstop.
#
# WHY THE MUTATION MATRIX RUNS ON A SYNTHETIC FIXTURE rather than on a copy of the live tree. A
# mutant is only evidence when its named row was GREEN before the edit. The live tree is mid-
# migration — the workflow limb of #8209 lands after this guard, which is the point of writing the
# guard first (plan Phase 1 item 2: "It must go red … that red output is the inventory") — so a
# row that is already red on the live tree would score every mutant KILLED for the wrong reason.
# The fixture is the smallest fully-COMPLIANT tree the contract admits, its control run is
# asserted all-green, and every mutation is applied to a copy of it.
#
# Seams: IPT_GITHUB_DIR (the workflow/action input tree; default <repo>/.github), IPT_REPO_ROOT
# (the tree the `*.tf` model and `bash <repo-path>` resolution read; default <repo>),
# IPT_STATE_LIST (an operator-pasted `terraform state list`; default unset), IPT_BASE_REF (the
# ref whose `*.tf` are the base for the deleted-resource-block row; default origin/main).
#
# Run: bash tests/scripts/test-infra-privileged-tier-census.sh

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
GHDIR="${IPT_GITHUB_DIR:-$ROOT/.github}"
REPODIR="${IPT_REPO_ROOT:-$ROOT}"
STATE_LIST="${IPT_STATE_LIST:-}"
BASE_REF="${IPT_BASE_REF:-origin/main}"

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

for d in "$GHDIR/workflows" "$GHDIR/actions"; do
  [ -d "$d" ] || { printf 'FAIL SETUP: %s not found\n' "$d" >&2; exit 1; }
done
python3 -c 'import yaml' 2>/dev/null || { printf 'FAIL SETUP: python3 yaml module unavailable\n' >&2; exit 1; }

# Canonical copy of plugins/soleur/test/test-helpers.sh's guard (the fixture-dir-operand-assert
# suite pins every tracked copy byte-identical). Executed as a statement before writes under a
# caller-supplied root so the P1b relative-operand ratchet can see the operand is absolute.
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

T="$(mktemp -d "${TMPDIR}/infra-privileged-tier-census.XXXXXX")" || { printf 'FAIL SETUP: mktemp\n' >&2; exit 1; }
_REACHED_VERDICT=""; _rc=0
trap '_rc=$?; rm -rf "$T"; if [ "$_rc" -eq 0 ] && [ -z "$_REACHED_VERDICT" ]; then printf "FAIL: suite exited 0 before its verdict\n" >&2; exit 1; fi' EXIT
assert_fixture_dir "$T"
mkdir -p "$T/mut" || { printf 'FAIL SETUP: mkdir %s/mut\n' "$T" >&2; exit 1; }

printf '\n=== infra-privileged tier census (Guards 1, 2 and 4; #8209, ADR-239) ===\n\n'

cat > "$T/ipt.py" <<'PY'
import sys, os, re, json, yaml, subprocess

GHDIR, REPO = sys.argv[1], sys.argv[2]
STATE_LIST = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] else ""
BASE_ROOT = sys.argv[4] if len(sys.argv) > 4 and sys.argv[4] else ""
CHECK_GIT = (os.path.abspath(GHDIR) == os.path.abspath(os.path.join(REPO, ".github"))
             and os.path.exists(os.path.join(REPO, ".git")))

# ── constants (plan Phase 1 item 1) ────────────────────────────────────────────────
ENV_SECRETS = ["DOPPLER_TOKEN_INFRA_PRIVILEGED", "DOPPLER_TOKEN_WRITE", "DOPPLER_TOKEN_GIT_DATA_ROOT"]
TIER_B_NAMES = ["DOPPLER_TOKEN_TF", "HCLOUD_TOKEN", "CF_API_TOKEN_R2",
                "GITHUB_INFRA_APP_ID", "GITHUB_INFRA_APP_INSTALLATION_ID", "GITHUB_INFRA_APP_PRIVATE_KEY",
                "TF_STATE_AWS_ACCESS_KEY_ID", "TF_STATE_AWS_SECRET_ACCESS_KEY",
                "GIT_DATA_ROOT_STATE_AWS_ACCESS_KEY_ID", "GIT_DATA_ROOT_STATE_AWS_SECRET_ACCESS_KEY"]
TIER_B_ENVIRONMENTS = {"infra-privileged", "web-platform-infra-apply", "inngest-cutover", "workspaces-luks-cutover"}
PRIV_STATE_BUCKET = "soleur-terraform-state"
LOADER_REL = os.path.join("actions", "infra-credentials", "action.yml")
GUARD4_ROOTS = ["apps/web-platform/infra", "apps/web-platform/infra/git-data-root-key"]

out = []
def check(name, cond, detail=""):
    out.append("%s\t%s\t%s" % ("ok" if cond else "FAIL", name,
                               str(detail)[:400].replace("\t", " ").replace("\n", " ")))

SEC_REF = re.compile(r"secrets\s*\.\s*(" + "|".join(ENV_SECRETS) + r")(?![A-Za-z0-9_])", re.I)
DYNAMIC = re.compile(r"tojson\s*\(\s*secrets\s*\)|secrets\s*\[", re.I)
ENV_EXPR = re.compile(r"\$\{\{\s*env\.([A-Za-z_][A-Za-z0-9_]*)\s*\}\}")
CONT = re.compile(r"\\\n\s*")

def jdump(v):
    return json.dumps(v, default=str)

# ── 1. the input tree ──────────────────────────────────────────────────────────────
files = []
for sub in ("workflows", "actions"):
    for dp, _dn, fn in os.walk(os.path.join(GHDIR, sub)):
        for f in fn:
            if f.endswith((".yml", ".yaml")):
                files.append(os.path.join(dp, f))
files.sort()
tracked = []
if CHECK_GIT:
    r = subprocess.run(["git", "-C", REPO, "ls-files",
                        ".github/workflows/*.yml", ".github/workflows/*.yaml",
                        ".github/actions/**/action.yml"], capture_output=True, text=True)
    tracked = [l for l in r.stdout.split() if l]
seen = {os.path.realpath(p) for p in files}
missing = [t for t in tracked if os.path.realpath(os.path.join(REPO, t)) not in seen]
check("G1a: the census scanned the workflow/composite-action set (%d files scanned, %d tracked)"
      % (len(files), len(tracked)), len(files) >= 1 and not missing,
      "files=%d tracked=%d missing=%s" % (len(files), len(tracked), missing[:5]))
print("IPT_FILES_SCANNED=%d" % len(files), file=sys.stderr)

docs, parse_err = {}, []
for p in files:
    rel = os.path.relpath(p, GHDIR)
    text = open(p, encoding="utf-8", errors="replace").read()
    try:
        doc = yaml.safe_load(text)
    except Exception:
        parse_err.append(rel); continue
    docs[rel] = (doc if isinstance(doc, dict) else {}, text)

# ── 2. job model ───────────────────────────────────────────────────────────────────
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
        # an expression with a `||` fallback and no literal on that side falls through to empty
        if re.search(r"\|\|\s*''", s) or re.search(r'\|\|\s*""', s):
            arms.append("")
        return arms if arms else [""]
    return [s]

class Job(object):
    pass

jobs = []
for rel, (doc, text) in sorted(docs.items()):
    wenv = {k: str(v) for k, v in (doc.get("env") or {}).items()}
    for jn, body in (doc.get("jobs") or {}).items():
        if not isinstance(body, dict):
            continue
        j = Job()
        j.rel, j.name, j.body, j.wtext = rel, jn, body, text
        j.id = "%s::%s" % (rel, jn)
        j.env = dict(wenv); j.env.update({k: str(v) for k, v in (body.get("env") or {}).items()})
        j.has_env_key = "environment" in body
        j.arms = env_arms(body.get("environment"))
        j.steps = [s for s in (body.get("steps") or []) if isinstance(s, dict)]
        j.dump = jdump(body)
        j.triggers = list((doc.get("on") or doc.get(True) or {}).keys()) if isinstance(doc.get("on") or doc.get(True), dict) else []
        jobs.append(j)

def resolve(j, s):
    return ENV_EXPR.sub(lambda m: j.env.get(m.group(1), "\x00UNRESOLVED:%s\x00" % m.group(1)), str(s or ""))

def step_wd(j, s):
    wd = s.get("working-directory") or ((j.body.get("defaults") or {}).get("run") or {}).get("working-directory") or ""
    return resolve(j, wd).strip().rstrip("/")

APPLY = re.compile(r"(?<![-\w])terraform\s+apply(?![-\w])")
def apply_steps(j):
    for s in j.steps:
        if APPLY.search(str(s.get("run") or "")):
            yield s

# ── 3. Terraform model ─────────────────────────────────────────────────────────────
def tf_files(root):
    res = []
    d = os.path.join(REPO, root)
    if os.path.isdir(d):
        for f in sorted(os.listdir(d)):
            if f.endswith(".tf"):
                res.append(os.path.join(d, f))
    return res

def tf_roots():
    """Every directory under apps/*/infra or infra/ that holds at least one .tf file."""
    roots = set()
    for base in [os.path.join(REPO, "infra")] + \
                [os.path.join(REPO, "apps", a, "infra") for a in
                 (sorted(os.listdir(os.path.join(REPO, "apps"))) if os.path.isdir(os.path.join(REPO, "apps")) else [])]:
        if not os.path.isdir(base):
            continue
        for dp, _dn, fn in os.walk(base):
            if any(f.endswith(".tf") for f in fn):
                roots.add(os.path.relpath(dp, REPO))
    return sorted(roots)

def block_bodies(text, opener):
    """Brace-counted bodies of every block whose opening line matches `opener` (a compiled regex
    anchored at column 0). Returns (match, body)."""
    res = []
    for m in opener.finditer(text):
        i = text.index("{", m.end() - 1) if "{" not in m.group(0) else m.start() + m.group(0).index("{")
        depth, k = 0, i
        while k < len(text):
            if text[k] == "{":
                depth += 1
            elif text[k] == "}":
                depth -= 1
                if depth == 0:
                    break
            k += 1
        res.append((m, text[i + 1:k]))
    return res

RES_OPEN = re.compile(r'^resource\s+"([A-Za-z0-9_]+)"\s+"([A-Za-z0-9_]+)"\s*\{', re.M)
REMOVED_OPEN = re.compile(r'^removed\s*\{', re.M)
BACKEND_OPEN = re.compile(r'^\s*backend\s+"s3"\s*\{', re.M)

tf_root_files = {r: tf_files(r) for r in tf_roots()}
n_tf = sum(len(v) for v in tf_root_files.values())
print("IPT_TF_SCANNED=%d" % n_tf, file=sys.stderr)

# environment name map + main policies
env_name_of, main_policy_envs = {}, set()
policy_bodies = []
for r, fl in tf_root_files.items():
    for p in fl:
        t = open(p, encoding="utf-8", errors="replace").read()
        for m, b in block_bodies(t, RES_OPEN):
            typ, nm = m.group(1), m.group(2)
            if typ == "github_repository_environment":
                lit = re.search(r'^\s*environment\s*=\s*"([^"]+)"', b, re.M)
                if lit:
                    env_name_of[nm] = lit.group(1)
            elif typ == "github_repository_environment_deployment_policy":
                policy_bodies.append(b)
for b in policy_bodies:
    if not re.search(r'^\s*branch_pattern\s*=\s*"main"\s*$', b, re.M):
        continue
    lit = re.search(r'^\s*environment\s*=\s*"([^"]+)"', b, re.M)
    if lit:
        main_policy_envs.add(lit.group(1)); continue
    ref = re.search(r'^\s*environment\s*=\s*github_repository_environment\.([A-Za-z0-9_]+)\.environment', b, re.M)
    if ref and ref.group(1) in env_name_of:
        main_policy_envs.add(env_name_of[ref.group(1)])

# backend bucket per root
root_bucket = {}
for r, fl in tf_root_files.items():
    for p in fl:
        t = open(p, encoding="utf-8", errors="replace").read()
        for _m, b in block_bodies(t, BACKEND_OPEN):
            lit = re.search(r'^\s*bucket\s*=\s*"([^"]+)"', b, re.M)
            root_bucket[r] = lit.group(1) if lit else ""
state_roots = {r for r, b in root_bucket.items() if b == PRIV_STATE_BUCKET}

# ── 4. Tier-B classification ───────────────────────────────────────────────────────
for j in jobs:
    j.names_env_secret = bool(SEC_REF.search(j.dump))
    j.applies_state_root = any(step_wd(j, s) in state_roots for s in apply_steps(j))
    j.tier_b = j.names_env_secret or j.applies_state_root
tierb = [j for j in jobs if j.tier_b]
print("IPT_TIERB=%s" % " ".join(sorted(j.id for j in tierb)), file=sys.stderr)

# ── Guard 1 ────────────────────────────────────────────────────────────────────────
no_env = [j.id for j in tierb if not j.has_env_key]
check("G1b: every Tier-B job declares an `environment:` key (AC2b; a Tier-B job with none reads no "
      "environment secret and fails closed the moment the legacy fallback goes) [%d Tier-B jobs]" % len(tierb),
      not no_env, no_env[:8])

bad_arm = sorted({"%s -> %r" % (j.id, a) for j in tierb if j.arms for a in j.arms if a not in TIER_B_ENVIRONMENTS})
check("G1c: every arm of every Tier-B job's `environment:` is in tier_b_environments (scalar and "
      "mapping forms both accepted; an empty `||` arm is an arm)", not bad_arm, bad_arm[:8])

declared = {a for j in tierb if j.arms for a in j.arms if a}
want_policy = sorted(TIER_B_ENVIRONMENTS | declared)
no_policy = [e for e in want_policy if e not in main_policy_envs]
check("G1d: every tier_b_environment, and every environment a Tier-B job declares, has a Terraform "
      "`github_repository_environment_deployment_policy` with branch_pattern = \"main\" [%d .tf files]" % n_tf,
      n_tf >= 1 and not no_policy, "missing=%s scanned_tf=%d" % (no_policy[:8], n_tf))

dyn = sorted({rel for rel, (doc, _t) in docs.items() if DYNAMIC.search(jdump(doc))})
check("G1e: no toJSON(secrets) / secrets[...] dynamic secret access anywhere (it would hand every "
      "secret, the Tier-B ones included, to a job the name census cannot see)", not dyn, dyn[:8])

prt = []
for j in tierb:
    if "pull_request_target" not in j.triggers:
        continue
    if re.search(r"github\s*\.\s*event\s*\.\s*pull_request\s*\.\s*head\s*\.\s*(sha|ref)", jdump(j.body)):
        prt.append(j.id)
check("G1f: no `pull_request_target` Tier-B job checks out the pull request's own head ref",
      not prt, prt)

# AC3 — a tier_b_names read from prd_terraform outside the loader's legacy arm
PRD_TF = re.compile(r"(?:-c|--config)[= ]+prd_terraform\b")
ac3 = []
for rel, (doc, text) in sorted(docs.items()):
    if rel == LOADER_REL:
        continue
    for j in [x for x in jobs if x.rel == rel]:
        for s in j.steps:
            body = CONT.sub(" ", str(s.get("run") or ""))
            for m in re.finditer(r"doppler\s+secrets\s+get\s+([A-Za-z_][A-Za-z0-9_]*)([^\n]*)", body):
                if m.group(1) in TIER_B_NAMES and PRD_TF.search(m.group(2)):
                    ac3.append("%s [%s]" % (j.id, m.group(1)))
check("G1g: no workflow step reads a tier_b_names entry with `-c prd_terraform` outside the loader "
      "(%s) [AC3]" % os.path.join(".github", LOADER_REL), not ac3, sorted(set(ac3))[:8])

# AC7b limb 2 — every writer of the shared state bucket is Tier B
writers = []
for j in jobs:
    for s in apply_steps(j):
        wd = step_wd(j, s)
        if wd in state_roots and not (j.arms and all(a in TIER_B_ENVIRONMENTS for a in j.arms) and j.has_env_key):
            writers.append("%s [%s]" % (j.id, wd or "<repo root>"))
check("G1h: every job applying against a `%s`-backed root declares a Tier-B environment [AC7b; "
      "%d such roots]" % (PRIV_STATE_BUCKET, len(state_roots)), not writers, sorted(set(writers))[:8])

# AC7b limb 1 — the backend-credential steps read TF_STATE_AWS_* first
EXTRACT = re.compile(r"extract\s+(r2\s+)?backend\s+credentials", re.I)
bad_extract, n_extract = [], 0
for j in tierb:
    for s in j.steps:
        body = CONT.sub(" ", str(s.get("run") or ""))
        if not (EXTRACT.search(str(s.get("name") or "")) or
                re.search(r"AWS_(ACCESS_KEY_ID|SECRET_ACCESS_KEY)\s*=", body)):
            continue
        n_extract += 1
        i_tf = min([body.index(x) for x in ("${TF_STATE_AWS_ACCESS_KEY_ID", "$TF_STATE_AWS_ACCESS_KEY_ID")
                    if x in body] or [len(body) + 1])
        i_legacy = min([m.start() for m in re.finditer(r"doppler\s+secrets\s+get\s+AWS_ACCESS_KEY_ID", body)] or [len(body) + 2])
        if i_tf > i_legacy:
            bad_extract.append("%s [%s]" % (j.id, (s.get("name") or "<unnamed>")))
check("G1i: every \"Extract backend credentials\"-shaped step in a Tier-B job reads TF_STATE_AWS_* "
      "before any prd_terraform AWS_* fallback [AC7b; %d such steps]" % n_extract,
      not bad_extract, sorted(set(bad_extract))[:8])

# ── Guard 2 ────────────────────────────────────────────────────────────────────────
DOPPLER_RUN = re.compile(r"doppler\s+run\b")
BASH_CALL = re.compile(r"(?<![\w/-])bash\s+(?!-)([\"']?)([^\s\"';|&)]+)\1")

def invocations(body):
    """Each `doppler run` invocation's own argument text: up to the ` -- ` separator or the end of
    its (continuation-joined) line. `[^\\n]` is a bracket expression, not "any char but newline",
    so the slice is taken by index rather than by a negated class."""
    flat = CONT.sub(" ", body)
    for m in DOPPLER_RUN.finditer(flat):
        rest = flat[m.end():]
        cut = len(rest)
        for pat in (" -- ", "\n"):
            k = rest.find(pat)
            if k != -1:
                cut = min(cut, k)
        yield flat[m.start():m.end() + cut]

def script_targets(body):
    flat = CONT.sub(" ", body)
    for m in BASH_CALL.finditer(flat):
        raw = m.group(2)
        p = raw.replace("${GITHUB_WORKSPACE}/", "").replace("$GITHUB_WORKSPACE/", "")
        if not p.endswith(".sh"):
            continue
        yield raw, p

missing_flag, unresolved, n_runs, n_scripts = [], [], 0, 0
for j in tierb:
    for s in j.steps:
        body = str(s.get("run") or "")
        for inv in invocations(body):
            n_runs += 1
            if "--preserve-env" not in inv:
                missing_flag.append("%s inline: %s" % (j.id, inv.strip()[:70]))
        for raw, p in script_targets(body):
            if "$" in p:
                # A runner-local temp script is WRITTEN by a heredoc in this same run body, which
                # the inline scan above already read, so it is resolved, not skipped. Any other
                # unexpandable path fails closed.
                if not re.search(r"\$\{?(RUNNER_TEMP|TMPDIR|TMP)\b", raw):
                    unresolved.append("%s -> %s (unexpandable path)" % (j.id, raw))
                continue
            full = os.path.join(REPO, p)
            if not os.path.isfile(full):
                unresolved.append("%s -> %s (no such file)" % (j.id, raw)); continue
            n_scripts += 1
            sbody = open(full, encoding="utf-8", errors="replace").read()
            for inv in invocations(sbody):
                n_runs += 1
                if "--preserve-env" not in inv:
                    missing_flag.append("%s via %s: %s" % (j.id, p, inv.strip()[:60]))
check("G2a: every `doppler run` reachable from a Tier-B job carries --preserve-env, inline or through "
      "one level of `bash <repo-path>` [%d invocations, %d scripts resolved]" % (n_runs, n_scripts),
      not missing_flag, sorted(set(missing_flag))[:8])
check("G2b: every `bash <repo-path>` a Tier-B job invokes resolves to a tracked script (fail closed)",
      not unresolved, sorted(set(unresolved))[:8])

LOADER_USES = re.compile(r"\./\.github/actions/infra-credentials\b")
order_bad, n_loader = [], 0
for j in tierb:
    idx = [i for i, s in enumerate(j.steps) if LOADER_USES.search(str(s.get("uses") or ""))]
    if not idx:
        continue
    n_loader += 1
    first_use = [i for i, s in enumerate(j.steps)
                 if DOPPLER_RUN.search(str(s.get("run") or "")) or re.search(r"(?<![-\w])terraform\s+(plan|apply|import)(?![-\w])", str(s.get("run") or ""))]
    if first_use and min(first_use) < min(idx):
        order_bad.append("%s loader@%d first-consumer@%d" % (j.id, min(idx), min(first_use)))
check("G2c: the loader step precedes every `doppler run` and every terraform step in each Tier-B job "
      "that uses it [%d such jobs]" % n_loader, not order_bad, order_bad[:8])

# ── Guard 4 ────────────────────────────────────────────────────────────────────────
#
# THE HIGHEST-SEVERITY GUARD IN THIS FILE. `doppler_secret.github_app_id` and
# `doppler_secret.github_app_private_key` pin `config = "prd"` and hold the LIVE GitHub App
# runtime identity — the key the web app mints every connected user's installation token from.
# A `removed` block that destroys instead of forgetting disconnects every connected user.
removed_blocks, g4_files = [], 0
for r in GUARD4_ROOTS:
    for p in tf_files(r):
        g4_files += 1
        t = open(p, encoding="utf-8", errors="replace").read()
        for _m, b in block_bodies(t, REMOVED_OPEN):
            fr = re.search(r"^\s*from\s*=\s*([A-Za-z0-9_.\[\]\"-]+)\s*$", b, re.M)
            lif = [lb for _lm, lb in block_bodies(b, re.compile(r"^\s*lifecycle\s*\{", re.M))]
            guarded = any(re.search(r"^\s*destroy\s*=\s*false\s*$", lb, re.M) for lb in lif)
            removed_blocks.append((r, os.path.relpath(p, REPO), fr.group(1) if fr else "", guarded))
print("IPT_G4_FILES=%d" % g4_files, file=sys.stderr)

ungrd = ["%s %s" % (f, a or "<no from>") for _r, f, a, g in removed_blocks if not (g and a)]
check("G4a: every `removed` block under the touched roots carries `lifecycle { destroy = false }` and "
      "a `from` address — without it `removed` is a DELETE [%d blocks over %d .tf files]"
      % (len(removed_blocks), g4_files), g4_files >= 1 and not ungrd, ungrd[:8])

# which workflow applies which root, and with what -target list
TARGET = re.compile(r"-target=([A-Za-z0-9_]+\.[A-Za-z0-9_]+)(?![\w.\[\"])")
root_targets, root_targeted = {}, {}
for j in jobs:
    for s in apply_steps(j):
        wd = step_wd(j, s)
        body = CONT.sub(" ", str(s.get("run") or ""))
        root_targets.setdefault(wd, set()).update(TARGET.findall(body))
        root_targeted[wd] = root_targeted.get(wd, False) or ("-target=" in body)

unreached = []
for r, f, a, _g in removed_blocks:
    if not a:
        continue
    if root_targeted.get(r) and a not in root_targets.get(r, set()):
        unreached.append("%s %s (root %s is applied with -target=)" % (f, a, r))
check("G4b: every `removed` address is reached by its root's apply — in the `-target=` list when the "
      "root is applied targeted, else by an untargeted apply. An untargeted address is never planned, "
      "so the forget never happens and the resource is orphaned under management",
      not unreached, unreached[:8])

declared_addrs, forgotten_addrs = {}, {}
for r in GUARD4_ROOTS:
    declared_addrs[r] = set()
    for p in tf_files(r):
        t = open(p, encoding="utf-8", errors="replace").read()
        for m, _b in block_bodies(t, RES_OPEN):
            declared_addrs[r].add("%s.%s" % (m.group(1), m.group(2)))
    forgotten_addrs[r] = {a for rr, _f, a, _g in removed_blocks if rr == r and a}

# Row 3: a resource block deleted with NO `removed` block. The only sound signal is the BASE
# tree — the repo carries pre-existing `-target=` lines for addresses no resource block declares,
# so "targeted but undeclared" is not it. $BASE_ROOT is the base ref's copy of the touched roots,
# materialised by the suite; an unreadable base FAILS CLOSED rather than passing vacuously.
base_declared, n_base = {}, 0
if BASE_ROOT:
    for r in GUARD4_ROOTS:
        base_declared[r] = set()
        d = os.path.join(BASE_ROOT, r)
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d)):
            if not f.endswith(".tf"):
                continue
            n_base += 1
            t = open(os.path.join(d, f), encoding="utf-8", errors="replace").read()
            for m, _b in block_bodies(t, RES_OPEN):
                base_declared[r].add("%s.%s" % (m.group(1), m.group(2)))
orphans = []
for r in GUARD4_ROOTS:
    for a in sorted(base_declared.get(r, set())):
        if a not in declared_addrs[r] and a not in forgotten_addrs[r]:
            orphans.append("%s %s" % (r, a))
check("G4c: every `resource` block the base ref declares and HEAD no longer declares is claimed by a "
      "`removed` block — a deleted resource block with none leaves the resource managed with no HCL, "
      "and the next apply plans a plain DESTROY [base .tf files: %d]" % n_base,
      bool(BASE_ROOT) and n_base >= 1 and not orphans,
      ("base unavailable" if not BASE_ROOT else "orphans=%s" % orphans[:8]))

if STATE_LIST:
    live = set(open(STATE_LIST, encoding="utf-8", errors="replace").read().split())
    absent = sorted({a for _r, _f, a, _g in removed_blocks if a and a not in live})
    check("G4d: every `removed` address appears verbatim in the operator's pasted `terraform state "
          "list` [AC2c state limb; %d live addresses]" % len(live), bool(live) and not absent, absent[:8])
else:
    check("G4d: the `terraform state list` limb is the O0 operator precondition (AC2c) and is not a CI "
          "gate — CI holds no state credential at PR time. Pass IPT_STATE_LIST to check it.", True,
          "not checked in CI by design")

print("\n".join(out))
PY
CENSUS_ROWS=16

# census_rows <tsv> <err> — reports every row of one census run through pass()/fail().
census_rows() {
  local n=0 v name detail
  while IFS=$'\t' read -r v name detail; do
    [ -n "$v" ] || continue
    n=$((n + 1))
    if [ "$v" = ok ]; then pass "$name"; else fail "$name" "$detail"; fi
  done < "$1"
  [ "$n" -ge "$CENSUS_ROWS" ] || fail "G0: only $n census verdicts were produced (expected $CENSUS_ROWS) — the census crashed" "$(head -c 300 "$2")"
}

# wf_row <tsv> <name-prefix> — 1 only when the named row is PRESENT and not ok. An ABSENT row (the
# census crashed on a fixture) returns 0, so a mutant can never read as RED for the wrong reason.
# shellcheck disable=SC2317  # invoked indirectly through mutant_red
wf_row() { awk -F'\t' -v p="$2" 'index($2, p) == 1 { found = 1; if ($1 != "ok") bad = 1 } END { exit (found && bad) ? 1 : 0 }' "$1"; }

# ── the base tree for the deleted-resource-block row (Guard 4 row 3) ─────────────────
# `git show <ref>:<path>` per file rather than a worktree checkout: this suite must never touch
# the caller's index or working tree.
BASEDIR="$T/base"; assert_fixture_dir "$BASEDIR"
base_rc=0
mkdir -p "$BASEDIR/apps/web-platform/infra/git-data-root-key" || base_rc=1
for r in apps/web-platform/infra apps/web-platform/infra/git-data-root-key; do
  [ "$base_rc" -eq 0 ] || break
  rc=0; lst="$(git -C "$REPODIR" ls-tree -r --name-only "$BASE_REF" -- "$r" 2>/dev/null)" || rc=$?
  [ "$rc" -eq 0 ] && [ -n "$lst" ] || { base_rc=1; break; }
  while IFS= read -r f; do
    case "$f" in *.tf) ;; *) continue ;; esac
    [ "${f%/*}" = "$r" ] || continue
    git -C "$REPODIR" show "$BASE_REF:$f" > "$BASEDIR/$f" 2>/dev/null || base_rc=1
  done <<< "$lst"
done
[ "$base_rc" -eq 0 ] || BASEDIR=""

# ── the live census (this is the guard) ──────────────────────────────────────────────
python3 "$T/ipt.py" "$GHDIR" "$REPODIR" "$STATE_LIST" "$BASEDIR" > "$T/live.tsv" 2> "$T/live.err"
census_rows "$T/live.tsv" "$T/live.err"

# FILE-SCAN FLOOR (ADR-193: printf + exit, never through the helpers it backstops). A census over
# zero files reports every row green and proves nothing; the dispatch self-test drives this.
SCANNED="$(sed -n 's/^IPT_FILES_SCANNED=//p' "$T/live.err" | tail -1)"
printf 'scanned: %s workflow/composite-action files, %s terraform files under the touched roots\n' \
  "${SCANNED:-0}" "$(sed -n 's/^IPT_G4_FILES=//p' "$T/live.err" | tail -1)"
FILE_SCAN_FLOOR=1
if [ "${SCANNED:-0}" -lt "$FILE_SCAN_FLOOR" ]; then
  printf 'FAIL SCAN FLOOR: the census scanned %s files, floor is %s — an empty input tree makes every row vacuously green.\n' "${SCANNED:-0}" "$FILE_SCAN_FLOOR" >&2
  exit 1
fi

# ── the compliant fixture ────────────────────────────────────────────────────────────
# The smallest tree the contract admits, built so that EVERY census row is green. It is the
# control the mutation matrix is measured against; see the header for why the live tree is not.
FIX="$T/fix"; assert_fixture_dir "$FIX"
mkdir -p "$FIX/tree/.github/workflows" "$FIX/tree/.github/actions/infra-credentials" \
         "$FIX/tree/scripts" "$FIX/tree/apps/web-platform/infra/git-data-root-key" \
         "$FIX/base/apps/web-platform/infra/git-data-root-key" \
  || { printf 'FAIL SETUP: fixture mkdir\n' >&2; exit 1; }

# shellcheck disable=SC2016  # every heredoc below is DATA: ${{ }} and $VAR are fixture text
{
cat > "$FIX/tree/.github/actions/infra-credentials/action.yml" <<'EOF'
name: "Infra credentials (tiered)"
description: "fixture loader"
inputs:
  doppler-token-infra-privileged:
    required: false
    default: ""
runs:
  using: composite
  steps:
    - shell: bash
      run: echo loader
EOF

cat > "$FIX/tree/.github/workflows/tierb-apply.yml" <<'EOF'
name: fixture tier-b apply
on:
  push:
    branches: [main]
env:
  INFRA_DIR: apps/web-platform/infra
jobs:
  apply:
    runs-on: ubuntu-24.04
    environment: infra-privileged
    steps:
      - uses: ./.github/actions/infra-credentials
        with:
          doppler-token-infra-privileged: ${{ secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED }}
      - name: Extract backend credentials
        run: |
          set -euo pipefail
          KEY_ID="${TF_STATE_AWS_ACCESS_KEY_ID:-$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)}"
          SECRET="${TF_STATE_AWS_SECRET_ACCESS_KEY:-$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)}"
          printf 'AWS_ACCESS_KEY_ID=%s\n' "$KEY_ID" >> "$GITHUB_ENV"
          printf 'AWS_SECRET_ACCESS_KEY=%s\n' "$SECRET" >> "$GITHUB_ENV"
      - name: Terraform apply
        working-directory: ${{ env.INFRA_DIR }}
        run: |
          set -euo pipefail
          doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- \
            terraform apply -input=false -auto-approve \
              -target=doppler_secret.github_app_id \
              -target=doppler_secret.github_app_private_key \
              -target=doppler_service_token.write \
              -target=github_actions_secret.doppler_token_write
          bash scripts/tierb-helper.sh
EOF

cat > "$FIX/tree/.github/workflows/tierb-mapping.yml" <<'EOF'
name: fixture tier-b mapping form
on: workflow_dispatch
jobs:
  sync:
    runs-on: ubuntu-24.04
    environment:
      name: web-platform-infra-apply
    steps:
      - uses: ./.github/actions/infra-credentials
      - name: Sync
        env:
          DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN_WRITE }}
        run: |
          set -euo pipefail
          doppler run --preserve-env -p soleur -c prd_terraform -- echo sync
EOF

cat > "$FIX/tree/.github/workflows/rootkey.yml" <<'EOF'
name: fixture root key apply
on: workflow_dispatch
env:
  ROOT_KEY_DIR: apps/web-platform/infra/git-data-root-key
jobs:
  apply:
    runs-on: ubuntu-24.04
    environment: web-platform-infra-apply
    steps:
      - uses: ./.github/actions/infra-credentials
      - name: Apply the root key root
        working-directory: ${{ env.ROOT_KEY_DIR }}
        env:
          DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN_GIT_DATA_ROOT }}
        run: |
          set -euo pipefail
          doppler run --preserve-env -p soleur -c prd -- terraform apply -input=false -auto-approve
EOF

cat > "$FIX/tree/.github/workflows/tiera.yml" <<'EOF'
name: fixture tier-a plan
on: pull_request
jobs:
  plan:
    runs-on: ubuntu-24.04
    steps:
      - name: Plan
        env:
          DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN }}
        run: |
          set -euo pipefail
          doppler run -p soleur -c prd_terraform -- terraform plan -refresh=false
EOF

cat > "$FIX/tree/scripts/tierb-helper.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
doppler run --preserve-env=TF_VAR_hcloud_token -p soleur -c prd_terraform -- terraform output -json
EOF

cat > "$FIX/tree/apps/web-platform/infra/main.tf" <<'EOF'
terraform {
  backend "s3" {
    bucket = "soleur-terraform-state"
    key    = "web-platform/terraform.tfstate"
  }
}
EOF

cat > "$FIX/tree/apps/web-platform/infra/environments.tf" <<'EOF'
resource "github_repository_environment" "infra_privileged" {
  repository  = "soleur"
  environment = "infra-privileged"
}
resource "github_repository_environment_deployment_policy" "infra_privileged_main" {
  repository     = "soleur"
  environment    = github_repository_environment.infra_privileged.environment
  branch_pattern = "main"
}
resource "github_repository_environment" "web_platform_infra_apply" {
  repository  = "soleur"
  environment = "web-platform-infra-apply"
}
resource "github_repository_environment_deployment_policy" "web_platform_infra_apply_main" {
  repository     = "soleur"
  environment    = github_repository_environment.web_platform_infra_apply.environment
  branch_pattern = "main"
}
resource "github_repository_environment" "inngest_cutover" {
  repository  = "soleur"
  environment = "inngest-cutover"
}
resource "github_repository_environment_deployment_policy" "inngest_cutover_main" {
  repository     = "soleur"
  environment    = github_repository_environment.inngest_cutover.environment
  branch_pattern = "main"
}
resource "github_repository_environment" "workspaces_luks_cutover" {
  repository  = "soleur"
  environment = "workspaces-luks-cutover"
}
resource "github_repository_environment_deployment_policy" "workspaces_luks_cutover_main" {
  repository     = "soleur"
  environment    = github_repository_environment.workspaces_luks_cutover.environment
  branch_pattern = "main"
}
EOF

cat > "$FIX/tree/apps/web-platform/infra/github-app.tf" <<'EOF'
removed {
  from = doppler_secret.github_app_id

  lifecycle {
    destroy = false
  }
}
removed {
  from = doppler_secret.github_app_private_key

  lifecycle {
    destroy = false
  }
}
removed {
  from = doppler_service_token.write

  lifecycle {
    destroy = false
  }
}
removed {
  from = github_actions_secret.doppler_token_write

  lifecycle {
    destroy = false
  }
}
EOF

cat > "$FIX/tree/apps/web-platform/infra/git-data-root-key/main.tf" <<'EOF'
terraform {
  backend "s3" {
    key = "git-data-root-key/terraform.tfstate"
  }
}
EOF

cat > "$FIX/tree/apps/web-platform/infra/git-data-root-key/access.tf" <<'EOF'
removed {
  from = doppler_service_token.git_data_root_read

  lifecycle {
    destroy = false
  }
}
removed {
  from = github_actions_secret.doppler_token_git_data_root

  lifecycle {
    destroy = false
  }
}
EOF

cat > "$FIX/base/apps/web-platform/infra/github-app.tf" <<'EOF'
resource "doppler_secret" "github_app_id" {
  project = "soleur"
  config  = "prd"
  name    = "GITHUB_APP_ID"
}
resource "doppler_secret" "github_app_private_key" {
  project = "soleur"
  config  = "prd"
  name    = "GITHUB_APP_PRIVATE_KEY"
}
resource "doppler_service_token" "write" {
  project = "soleur"
  config  = "prd_terraform"
}
resource "github_actions_secret" "doppler_token_write" {
  repository  = "soleur"
  secret_name = "DOPPLER_TOKEN_WRITE"
}
EOF

cat > "$FIX/base/apps/web-platform/infra/git-data-root-key/access.tf" <<'EOF'
resource "doppler_service_token" "git_data_root_read" {
  project = "soleur-git-data-root"
  config  = "prd"
}
resource "github_actions_secret" "doppler_token_git_data_root" {
  repository  = "soleur"
  secret_name = "DOPPLER_TOKEN_GIT_DATA_ROOT"
}
EOF

printf 'doppler_secret.github_app_id\ndoppler_secret.github_app_private_key\ndoppler_service_token.write\ngithub_actions_secret.doppler_token_write\ndoppler_service_token.git_data_root_read\ngithub_actions_secret.doppler_token_git_data_root\n' > "$FIX/state-list-complete.txt"
}

# fixcensus <dir> <out-tsv> [state-list] — the census over one fixture copy.
fixcensus() {
  python3 "$T/ipt.py" "$1/tree/.github" "$1/tree" "${3:-}" "$1/base" > "$2" 2> "$2.err"
}

# ── the unmutated CONTROL: every row of the compliant fixture must be green ──────────
echo; echo "--- control (the compliant fixture; every mutation below is measured against it)"
fixcensus "$FIX" "$T/control.tsv" ""
_ctl_bad="$(awk -F'\t' '$1 != "ok" { print $2 }' "$T/control.tsv")"
_ctl_n="$(grep -c . "$T/control.tsv")"
if [ -z "$_ctl_bad" ] && [ "$_ctl_n" -ge "$CENSUS_ROWS" ]; then
  pass "H0: the compliant fixture is GREEN on all $_ctl_n census rows (the mutation control)"
else
  fail "H0: the control fixture is not green — every mutation row below is void" "rows=$_ctl_n bad=$(printf '%s' "$_ctl_bad" | tr '\n' ' ' | cut -c1-260)"
fi

_tierb="$(sed -n 's/^IPT_TIERB=//p' "$T/control.tsv.err" | tail -1)"
case " $_tierb " in
  *" workflows/tierb-mapping.yml::sync "*)
    pass "H1: the mapping form \`environment: { name: … }\` is censused as a Tier-B declaration (the contract permits both forms)" ;;
  *) fail "H1: the mapping-form job was not classified Tier B" "$_tierb" ;;
esac
case " $_tierb " in
  *" workflows/tiera.yml::plan "*)
    fail "H2: a Tier-A job was classified Tier B — its flagless \`doppler run\` is out of Guard 2's scope" "$_tierb" ;;
  *) pass "H2: a Tier-A job's \`doppler run\` without --preserve-env is out of scope and does not red" ;;
esac
if grep -qE -- '--preserve-env=TF_VAR_hcloud_token' "$FIX/tree/scripts/tierb-helper.sh" && wf_row "$T/control.tsv" "G2a:"; then
  pass "H3: the explicit-list form \`--preserve-env=<name>\` is accepted (the contract permits it)"
else
  fail "H3: the explicit-list --preserve-env form was rejected" "$(grep G2a "$T/control.tsv" | cut -c1-200)"
fi
fixcensus "$FIX" "$T/statelist-ok.tsv" "$FIX/state-list-complete.txt"
if wf_row "$T/statelist-ok.tsv" "G4d:" && grep -qE '^ok	G4d: every .removed. address appears' "$T/statelist-ok.tsv"; then
  pass "H4: a complete operator \`terraform state list\` satisfies the AC2c state limb"
else
  fail "H4: a complete state list did not satisfy the state limb" "$(grep G4d "$T/statelist-ok.tsv" | cut -c1-200)"
fi
_EMPTYTF="$T/empty-tf"; assert_fixture_dir "$_EMPTYTF"
mkdir -p "$_EMPTYTF/tree/.github" "$_EMPTYTF/base" || { printf 'FAIL SETUP: empty-tf fixture\n' >&2; exit 1; }
cp -r "$FIX/tree/.github/workflows" "$FIX/tree/.github/actions" "$_EMPTYTF/tree/.github/" \
  || { printf 'FAIL SETUP: empty-tf copy\n' >&2; exit 1; }
fixcensus "$_EMPTYTF" "$T/empty-tf.tsv" ""
if grep -q '^IPT_G4_FILES=0$' "$T/empty-tf.tsv.err" && ! wf_row "$T/empty-tf.tsv" "G4a:"; then
  pass "H5: Guard 4's instrument self-test — an empty \`.tf\` set reports 0 files and reds G4a"
else
  fail "H5: an empty .tf set did not red Guard 4" "$(grep -E 'IPT_G4_FILES|G4a' "$T/empty-tf.tsv.err" "$T/empty-tf.tsv" | cut -c1-200)"
fi
_EMPTYGH="$T/empty-gh"; assert_fixture_dir "$_EMPTYGH"
mkdir -p "$_EMPTYGH/tree/.github/workflows" "$_EMPTYGH/tree/.github/actions" "$_EMPTYGH/base" \
  || { printf 'FAIL SETUP: empty-gh fixture\n' >&2; exit 1; }
fixcensus "$_EMPTYGH" "$T/empty-gh.tsv" ""
if grep -q '^IPT_FILES_SCANNED=0$' "$T/empty-gh.tsv.err" && ! wf_row "$T/empty-gh.tsv" "G1a:"; then
  pass "H6: the dispatch self-test — an empty input tree reports '0 files scanned' and reds G1a (the suite's own SCAN FLOOR then exits non-zero)"
else
  fail "H6: an empty input tree did not report 0 files scanned" "$(head -2 "$T/empty-gh.tsv.err")"
fi

# ── mutation matrix ──────────────────────────────────────────────────────────────────
echo; echo "--- mutation matrix (each row must turn its NAMED census row RED against the control)"
MUTANT=""; MUTDIR=""
fixcopy() { # <name> — a pristine copy of the compliant fixture; prints its path
  local d="$T/mut/$1"
  assert_fixture_dir "$d"; assert_fixture_dir "$FIX"
  rm -rf "$d"
  mkdir -p "$d" || { printf 'FAIL SETUP: fixture mkdir %s\n' "$1" >&2; exit 1; }
  cp -r "$FIX/tree" "$FIX/base" "$d/" || { printf 'FAIL SETUP: fixture copy %s\n' "$1" >&2; exit 1; }
  printf '%s' "$d"
}
mutate() { # <name> <file> <expected-diff-lines> <sed -E program>
  local name="$1" src="$2" want="$3" expr="$4" got before after
  MUTANT="$T/mut/$name.orig"
  cp "$src" "$MUTANT" || { printf 'FAIL SETUP: mutation copy %s\n' "$name" >&2; exit 1; }
  before="$(md5sum < "$MUTANT" | cut -d' ' -f1)"
  if ! sed -E -i "$expr" "$src" 2>"$T/mut/$name.sed.err"; then
    fail "M-$name: mutation sed failed" "$(head -1 "$T/mut/$name.sed.err")"; return 1
  fi
  after="$(md5sum < "$src" | cut -d' ' -f1)"
  got="$(diff "$MUTANT" "$src" | grep -cE '^[<>]')"
  if [ "$before" = "$after" ] || [ "$got" != "$want" ]; then
    fail "M-$name: mutation landed on $got diff line(s), expected $want (md5 $before -> $after)" "sed -E [$expr]"; return 1
  fi
  MUTANTS_RUN=$((MUTANTS_RUN + 1))
  pass "M-$name: mutation landed on exactly $want diff line(s) of a pristine copy (md5 ${before:0:8} -> ${after:0:8})"
}
fixture_written() { # <name> <file>
  if [ -s "$2" ]; then MUTANTS_RUN=$((MUTANTS_RUN + 1)); pass "M-$1: fixture $(basename "$2") written ($(md5sum < "$2" | cut -c1-8))"; return 0; fi
  fail "M-$1: fixture not written"; return 1
}
mutant_red() { # <name> <case-fn> [args...] — the named case must go RED
  local name="$1"; shift
  if "$@"; then fail "M-$name: the named census row stayed GREEN against the mutant"
  else pass "M-$name: the named census row goes RED against the mutant"; fi
}
# mutant_red self-test (ADR-193), both directions, in a subshell so the counters roll back.
_mr="$( (mutant_red st-green true >/dev/null; printf '%s,%s ' "$passes" "$fails"; mutant_red st-red false >/dev/null; printf '%s,%s' "$passes" "$fails") )"
if [ "$_mr" != "$passes,$((fails + 1)) $((passes + 1)),$((fails + 1))" ]; then
  printf 'FAIL INSTRUMENT: mutant_red self-test read "%s" (from %s,%s) — a GREEN case must fail, a RED case must pass\n' "$_mr" "$passes" "$fails" >&2; exit 1
fi

# shellcheck disable=SC2016  # sed programs and fixture YAML are data
{
# ── Guard 1 ──────────────────────────────────────────────────────────────────────────
# Row 1 — a lower-case `secrets.doppler_token_infra_privileged` in a job with no `environment:`.
MUTDIR="$(fixcopy g1-1)"; assert_fixture_dir "$MUTDIR"
printf 'name: zz\non: workflow_dispatch\njobs:\n  a:\n    runs-on: ubuntu-24.04\n    steps:\n      - run: echo x\n        env:\n          T: ${{ secrets.doppler_token_infra_privileged }}\n' > "$MUTDIR/tree/.github/workflows/zz-noenv.yml"
if fixture_written g1-1-lowercase-no-environment "$MUTDIR/tree/.github/workflows/zz-noenv.yml"; then
  fixcensus "$MUTDIR" "$T/mut/g1-1.tsv" ""
  mutant_red g1-1-lowercase-no-environment wf_row "$T/mut/g1-1.tsv" "G1b:"
fi
# Row 2 — REORDER: a compliant first job, then a SECOND job in the same workflow whose
# `environment:` expression carries an EMPTY arm. The scan must not stop at the compliant one.
MUTDIR="$(fixcopy g1-2)"; assert_fixture_dir "$MUTDIR"
if mutate g1-2-second-job-empty-arm "$MUTDIR/tree/.github/workflows/tierb-apply.yml" 7 '$a\  second:\n    runs-on: ubuntu-24.04\n    environment: ${{ github.ref == '"'"'refs/heads/main'"'"' \&\& '"'"'infra-privileged'"'"' || '"''"' }}\n    steps:\n      - run: echo x\n        env:\n          T: ${{ secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED }}'; then
  fixcensus "$MUTDIR" "$T/mut/g1-2.tsv" ""
  mutant_red g1-2-second-job-empty-arm wf_row "$T/mut/g1-2.tsv" "G1c:"
fi
# Row 3 — delete the `workspaces_luks_cutover_main` policy while the environment stays in the set.
MUTDIR="$(fixcopy g1-3)"; assert_fixture_dir "$MUTDIR"
if mutate g1-3-policy-deleted "$MUTDIR/tree/apps/web-platform/infra/environments.tf" 5 '/^resource "github_repository_environment_deployment_policy" "workspaces_luks_cutover_main"/,/^\}/d'; then
  fixcensus "$MUTDIR" "$T/mut/g1-3.tsv" ""
  mutant_red g1-3-policy-deleted wf_row "$T/mut/g1-3.tsv" "G1d:"
fi
# Row 4 — a `-c prd_terraform` read of a tier_b_names entry in a step outside the loader (AC3).
MUTDIR="$(fixcopy g1-4)"; assert_fixture_dir "$MUTDIR"
if mutate g1-4-prd-terraform-read "$MUTDIR/tree/.github/workflows/tiera.yml" 1 '$a\          HCLOUD_TOKEN=$(doppler secrets get HCLOUD_TOKEN -p soleur -c prd_terraform --plain)'; then
  fixcensus "$MUTDIR" "$T/mut/g1-4.tsv" ""
  mutant_red g1-4-prd-terraform-read wf_row "$T/mut/g1-4.tsv" "G1g:"
fi
# Row 5 — toJSON(secrets) in a Tier-B job: every secret, the Tier-B ones included.
MUTDIR="$(fixcopy g1-5)"; assert_fixture_dir "$MUTDIR"
if mutate g1-5-tojson-secrets "$MUTDIR/tree/.github/workflows/tierb-mapping.yml" 1 '$a\          ALL: ${{ TOJSON( Secrets ) }}'; then
  fixcensus "$MUTDIR" "$T/mut/g1-5.tsv" ""
  mutant_red g1-5-tojson-secrets wf_row "$T/mut/g1-5.tsv" "G1e:"
fi
# Row 7 — a `pull_request_target` job in a Tier-B environment that checks out the PR's own head.
MUTDIR="$(fixcopy g1-7)"; assert_fixture_dir "$MUTDIR"
printf 'name: zz\non:\n  pull_request_target:\n    types: [opened]\njobs:\n  a:\n    runs-on: ubuntu-24.04\n    environment: infra-privileged\n    steps:\n      - uses: actions/checkout@v4\n        with:\n          ref: ${{ github.event.pull_request.head.sha }}\n      - run: echo x\n        env:\n          T: ${{ secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED }}\n' > "$MUTDIR/tree/.github/workflows/zz-prt.yml"
if fixture_written g1-7-pull-request-target "$MUTDIR/tree/.github/workflows/zz-prt.yml"; then
  fixcensus "$MUTDIR" "$T/mut/g1-7.tsv" ""
  mutant_red g1-7-pull-request-target wf_row "$T/mut/g1-7.tsv" "G1f:"
fi
# Row 8 (U5) — delete the `environment:` line from a Tier-B job that keeps its loader step. This is
# `git_data_host_replace` as it exists today: it shipped with no environment ON PURPOSE, so the row
# must red on that job plus a loader, not only on a synthetic one.
MUTDIR="$(fixcopy g1-8)"; assert_fixture_dir "$MUTDIR"
if mutate g1-8-environment-deleted "$MUTDIR/tree/.github/workflows/rootkey.yml" 1 '/^    environment: web-platform-infra-apply$/d'; then
  fixcensus "$MUTDIR" "$T/mut/g1-8.tsv" ""
  mutant_red g1-8-environment-deleted wf_row "$T/mut/g1-8.tsv" "G1b:"
fi
# Row 9 (U5) — an environment OUTSIDE tier_b_environments: a name O3 never seeds, so GitHub
# auto-creates it with no branch policy at all.
MUTDIR="$(fixcopy g1-9)"; assert_fixture_dir "$MUTDIR"
if mutate g1-9-environment-outside-set "$MUTDIR/tree/.github/workflows/tierb-apply.yml" 2 's/^    environment: infra-privileged$/    environment: web-platform-infra-apply-2/'; then
  fixcensus "$MUTDIR" "$T/mut/g1-9.tsv" ""
  mutant_red g1-9-environment-outside-set wf_row "$T/mut/g1-9.tsv" "G1c:"
fi

# ── Guard 2 ──────────────────────────────────────────────────────────────────────────
# Row 1 — remove --preserve-env from the tf-var `doppler run` in the Tier-B apply job.
MUTDIR="$(fixcopy g2-1)"; assert_fixture_dir "$MUTDIR"
if mutate g2-1-flag-removed "$MUTDIR/tree/.github/workflows/tierb-apply.yml" 2 's/doppler run --preserve-env -p soleur -c prd_terraform --name-transformer/doppler run -p soleur -c prd_terraform --name-transformer/'; then
  fixcensus "$MUTDIR" "$T/mut/g2-1.tsv" ""
  mutant_red g2-1-flag-removed wf_row "$T/mut/g2-1.tsv" "G2a:"
fi
# Row 2 — a compliant first `doppler run`, then a SECOND one in the SAME step without the flag.
MUTDIR="$(fixcopy g2-2)"; assert_fixture_dir "$MUTDIR"
if mutate g2-2-second-run-no-flag "$MUTDIR/tree/.github/workflows/tierb-apply.yml" 1 '/^          bash scripts\/tierb-helper\.sh$/a\          doppler run -p soleur -c prd_terraform -- terraform output -raw x'; then
  fixcensus "$MUTDIR" "$T/mut/g2-2.tsv" ""
  mutant_red g2-2-second-run-no-flag wf_row "$T/mut/g2-2.tsv" "G2a:"
fi
# Row 3 — the flag removed from a `doppler run` inside the script a Tier-B job invokes by
# `bash scripts/<x>.sh`. A census that skips script indirection stays green here.
MUTDIR="$(fixcopy g2-3)"; assert_fixture_dir "$MUTDIR"
if mutate g2-3-script-indirection "$MUTDIR/tree/scripts/tierb-helper.sh" 2 's/doppler run --preserve-env=TF_VAR_hcloud_token /doppler run /'; then
  fixcensus "$MUTDIR" "$T/mut/g2-3.tsv" ""
  mutant_red g2-3-script-indirection wf_row "$T/mut/g2-3.tsv" "G2a:"
fi
# Row 4 — REORDER: the loader step moved AFTER the first Terraform step. Its exports then land in
# $GITHUB_ENV for steps that have already run, and the Terraform step reads Tier-A values.
MUTDIR="$(fixcopy g2-4)"; assert_fixture_dir "$MUTDIR"
python3 - "$MUTDIR/tree/.github/workflows/tierb-apply.yml" <<'PYMUT'
import sys, re
p = sys.argv[1]
t = open(p).read()
m = re.search(r"      - uses: \./\.github/actions/infra-credentials\n(?:        .*\n)+", t)
block = m.group(0)
open(p, "w").write(t.replace(block, "") + block)
PYMUT
_g24_moved=0
if ! diff -q "$FIX/tree/.github/workflows/tierb-apply.yml" "$MUTDIR/tree/.github/workflows/tierb-apply.yml" >/dev/null 2>&1; then
  _g24_moved=1; MUTANTS_RUN=$((MUTANTS_RUN + 1))
  pass "M-g2-4-loader-after-terraform: the loader step moved to the end of the job (md5 $(md5sum < "$MUTDIR/tree/.github/workflows/tierb-apply.yml" | cut -c1-8))"
else
  fail "M-g2-4-loader-after-terraform: the reorder did not land"
fi
if [ "$_g24_moved" -eq 1 ]; then
  fixcensus "$MUTDIR" "$T/mut/g2-4.tsv" ""
  mutant_red g2-4-loader-after-terraform wf_row "$T/mut/g2-4.tsv" "G2c:"
fi

# ── Guard 4 — the U1 guard. See the header: these two addresses are the LIVE App identity. ──
# Row 1 — a misspelled `from` address. Terraform then plans a plain DESTROY of the real resource,
# because the resource block is gone and no `removed` block claims it.
MUTDIR="$(fixcopy g4-1)"; assert_fixture_dir "$MUTDIR"
if mutate g4-1-misspelled-from "$MUTDIR/tree/apps/web-platform/infra/github-app.tf" 2 's/from = doppler_secret\.github_app_private_key$/from = doppler_secret.github_app_privatekey/'; then
  fixcensus "$MUTDIR" "$T/mut/g4-1.tsv" ""
  mutant_red g4-1-misspelled-from wf_row "$T/mut/g4-1.tsv" "G4c:"
fi
# Row 2 — `lifecycle { destroy = false }` dropped from one `removed` block: the forget becomes a
# DELETE outright.
MUTDIR="$(fixcopy g4-2)"; assert_fixture_dir "$MUTDIR"
if mutate g4-2-destroy-guard-dropped "$MUTDIR/tree/apps/web-platform/infra/git-data-root-key/access.tf" 1 '0,/^    destroy = false$/{/^    destroy = false$/d}'; then
  fixcensus "$MUTDIR" "$T/mut/g4-2.tsv" ""
  mutant_red g4-2-destroy-guard-dropped wf_row "$T/mut/g4-2.tsv" "G4a:"
fi
# Row 3 — a resource block the BASE ref declares, deleted at HEAD with no `removed` block added.
MUTDIR="$(fixcopy g4-3)"; assert_fixture_dir "$MUTDIR"
if mutate g4-3-resource-deleted-unclaimed "$MUTDIR/base/apps/web-platform/infra/github-app.tf" 5 '$a\resource "doppler_secret" "github_app_webhook_secret" {\n  project = "soleur"\n  config  = "prd"\n  name    = "GITHUB_APP_WEBHOOK_SECRET"\n}'; then
  fixcensus "$MUTDIR" "$T/mut/g4-3.tsv" ""
  mutant_red g4-3-resource-deleted-unclaimed wf_row "$T/mut/g4-3.tsv" "G4c:"
fi
# Row 4 — the `-target=` line deleted while the `removed` block stays. A `removed` block is planned
# ONLY when its address is targeted, so the forget never applies and the resource is orphaned
# under management — the next untargeted apply destroys it.
MUTDIR="$(fixcopy g4-4)"; assert_fixture_dir "$MUTDIR"
if mutate g4-4-target-line-deleted "$MUTDIR/tree/.github/workflows/tierb-apply.yml" 1 '/^              -target=doppler_secret\.github_app_private_key \\$/d'; then
  fixcensus "$MUTDIR" "$T/mut/g4-4.tsv" ""
  mutant_red g4-4-target-line-deleted wf_row "$T/mut/g4-4.tsv" "G4b:"
fi
# Row 5 — a `removed` address absent from the operator's pasted `terraform state list` (AC2c).
MUTDIR="$(fixcopy g4-5)"; assert_fixture_dir "$MUTDIR"
grep -v '^doppler_secret\.github_app_private_key$' "$FIX/state-list-complete.txt" > "$MUTDIR/state-list-short.txt"
if fixture_written g4-5-address-absent-from-state "$MUTDIR/state-list-short.txt"; then
  fixcensus "$MUTDIR" "$T/mut/g4-5.tsv" "$MUTDIR/state-list-short.txt"
  mutant_red g4-5-address-absent-from-state wf_row "$T/mut/g4-5.tsv" "G4d:"
fi
}

# ── FLOOR + LEDGER (ADR-193: printf + exit, never through pass()/fail()) ─────────────
MUTANT_FLOOR=17
if [ "$MUTANTS_RUN" -lt "$MUTANT_FLOOR" ]; then
  printf 'FAIL MUTANT FLOOR: only %s mutants executed, floor is %s — a matrix row did not land or was deleted.\n' "$MUTANTS_RUN" "$MUTANT_FLOOR" >&2
  exit 1
fi
# Assertion FLOOR: live census 16 + harness 7 + mutants 17 x 2 = 57 (exact).
_ran=$((passes + fails))
FLOOR=57
if [ "$_ran" -lt "$FLOOR" ]; then
  printf 'FAIL ANTI-VACUITY: only %s assertions ran, floor is %s — cases were deleted or the suite exited early.\n' "$_ran" "$FLOOR" >&2
  exit 1
fi
if [ "${#FAILURES[@]}" -ne "$fails" ]; then
  printf 'FAIL LEDGER: %s failures counted but %s recorded\n' "$fails" "${#FAILURES[@]}" >&2; exit 1
fi
printf '\n=== infra-privileged-tier-census: %d passed, %d failed ===\n\n' "$passes" "$fails"
_REACHED_VERDICT=1
exit $(( ${#FAILURES[@]} > 0 ))
