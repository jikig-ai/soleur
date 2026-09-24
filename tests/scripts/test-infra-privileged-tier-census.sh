#!/usr/bin/env bash
#
# (#8209 Guard 1/2/4, ADR-241) The Tier-B privileged-credential census.
#
# PROPERTY. A credential that writes infrastructure, reads another tier's secrets, or reaches a
# third-party installation is reachable ONLY from `main`. The boundary is a GitHub environment
# secret on an environment whose deployment-branch policy is `main` only (ADR-241 D2), so the
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
#            Doppler config (ADR-241 D6). `DOPPLER_TOKEN_WRITE` has read/write on `prd_terraform`
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
# `tests/scripts/test-git-data-root-token-census.sh`. Guard 5 -- the `plan_only` shape guard --
# is rows G5a/G5b/G5c below, with fixture `replace.yml` and mutants g5-a/g5-b/g5-c. (This line
# previously CLAIMED Guard 5 existed while nothing implemented it; it was the only hit in the
# whole repo for `plan_only` outside .yml and knowledge-base/.)
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

printf '\n=== infra-privileged tier census (Guards 1, 2 and 4; #8209, ADR-241) ===\n\n'

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

DOPPLER_RUN = re.compile(r"doppler\s+run\b")
# COMMAND POSITION. `doppler run` and `doppler secrets get` appear in this repo's workflows far
# more often inside COMMENTS and inside `::error::` prose than as commands — "without this read the
# `doppler run` wrapper fail-closes" is a sentence, not an invocation. A census anchored on the bare
# token scores every one of those, so the anchor is SYNTACTIC: the token must sit where a command
# can start (line start, or after `|`, `;`, `&&`, `||`, `(`, `$(`, `{`, `!`, `then`, `do`, `else`,
# optionally behind VAR=value prefixes), on a line that is not a shell comment.
CMD_POS = re.compile(r"(?:^|[|;&({!]|\$\(|&&|\|\||\bthen\b|\bdo\b|\belse\b)\s*"
                     r"(?:[A-Za-z_][A-Za-z0-9_]*=[^\s]*\s+)*$")

HEREDOC_OPEN = re.compile(r"<<-?\s*[\"\']?([A-Za-z_][A-Za-z0-9_]*)[\"\']?")

# The line's first command token is echo/printf, so its arguments are data.
PRINTS = re.compile(r"(?:echo|printf)\b")

def in_quotes(line, idx):
    """True when `idx` falls inside a single- or double-quoted span of `line`.

    One pass with two flags, which is what a shell does. A backslash escape consumes the
    next character so a `\\"` inside a double-quoted string does not close it -- the
    workflows use that form in nearly every `::error::` body.
    """
    sq = dq = False
    i = 0
    while i < idx and i < len(line):
        c = line[i]
        if c == "\\":
            i += 2
            continue
        if c == "'" and not dq:
            sq = not sq
        elif c == '"' and not sq:
            dq = not dq
        i += 1
    return sq or dq

def cmd_sites(body, pat):
    """(line, match) for every `pat` hit that sits in command position on a non-comment,
    non-HEREDOC line.

    The heredoc skip is load-bearing, not tidiness. This repo's workflows print operator
    instructions out of heredocs and `echo` bodies -- "re-run wrapped in `doppler run -p
    soleur -c prd_terraform -- ...`" -- and those lines are DATA, not invocations. Counting
    them produced findings against files whose only offence was documenting a command, and
    the remedy a reader would reach for is to edit the message, which changes what an
    operator is told to paste while fixing nothing. A shell does not execute a heredoc
    body; neither does this census.

    Only the CLOSING delimiter ends the region, matching shell semantics, and an
    unterminated heredoc swallows the rest of the body -- which is the fail-closed
    direction: a missed invocation is a FAIL this row cannot raise, never a pass it
    wrongly grants, because the enclosing guard is "no site lacks the flag".
    """
    pending = None
    for line in CONT.sub(" ", body).split("\n"):
        if pending is not None:
            if line.strip() == pending:
                pending = None
            continue
        stripped = line.lstrip()
        if stripped.startswith("#"):
            continue
        h = HEREDOC_OPEN.search(line)
        printing = PRINTS.match(stripped) is not None
        for m in pat.finditer(line):
            # A hit AFTER a `<<EOF` on the same line is already inside the body.
            if h and m.start() > h.start():
                continue
            # A hit inside the ARGUMENT of `echo`/`printf` is a string being PRINTED, not
            # a command being run. CMD_POS cannot tell the difference, because a boundary
            # token inside the quoted text (`... && doppler run ...`, or
            # `TOKEN="$(doppler secrets get ...)"`) looks exactly like a real one. This
            # repo prints operator instructions constantly, so without this the row
            # reports the workflow that DOCUMENTS a command, and the reader's natural fix
            # is to edit the message -- changing what an operator is told to paste while
            # fixing nothing.
            #
            # Scoped to echo/printf deliberately, NOT to "inside any quotes": a real
            # `sh -c 'exec doppler run ...'` IS an invocation and this repo has several
            # (systemd units, cloud-init runcmd). A blanket quote skip would blind the
            # census to exactly those.
            if printing and in_quotes(line, m.start()):
                continue
            if CMD_POS.search(line[:m.start()]):
                yield line, m
        if h:
            pending = h.group(1)

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
# The read, and the refusal. Both are matched in COMMAND POSITION via cmd_sites, so neither
# is satisfiable by a comment, a heredoc body or an `echo` argument.
APP_PEM_READ = re.compile(r"doppler\s+secrets\s+get\s+(GITHUB_APP_PRIVATE_KEY)\b")
# Anchored on the `if`, not on the `[[`: cmd_sites tests what precedes the MATCH START for a
# command boundary, and a bare `[[` is preceded by `if ` -- which is a keyword, not a boundary
# token, so the match was rejected at all four live sites. Starting at `if` puts the match at
# line start, where the boundary is unambiguous.
SENTINEL_TEST = re.compile(r'if\s+\[\[\s*"\$PEM"\s*==\s*EVICTED_SEE_ADR_241\s*\]\]')

def step_bodies(doc):
    """Every `run:` body in a workflow OR a composite action.

    Composite actions keep their steps under `runs.steps`, not `jobs.*.steps` -- the job
    model above iterates `doc["jobs"]` and therefore contributes ZERO steps for them, so a
    row built on that model would silently exempt `.github/actions/**`. One of the four
    sites this row exists for is a composite action.
    """
    if not isinstance(doc, dict):
        return
    for j in (doc.get("jobs") or {}).values():
        if isinstance(j, dict):
            for st in (j.get("steps") or []):
                if isinstance(st, dict) and st.get("run"):
                    yield str(st["run"])
    runs = doc.get("runs")
    if isinstance(runs, dict):
        for st in (runs.get("steps") or []):
            if isinstance(st, dict) and st.get("run"):
                yield str(st["run"])

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

# A STATE WRITE is `apply` OR `destroy`. The Tier-B classifier and G1h used `apply_steps` alone, so
# a job whose only Terraform verb was `terraform destroy` against a `soleur-terraform-state` root
# was Tier A: git-data-rung2-rehearsal.yml::teardown shipped with no `environment:` and the legacy
# loader only, and once O10 evicts HCLOUD_TOKEN/DOPPLER_TOKEN_TF from prd_terraform its destroy
# would run credential-less and strand a paid host. A destroy needs the same credentials as the
# apply and writes the same state object. G4b and G5 keep `apply_steps`: they reason about -target
# lists and plan_only guards, which a teardown carries neither of.
STATE_WRITE = re.compile(r"(?<![-\w])terraform\s+(apply|destroy)(?![-\w])")
def state_write_steps(j):
    for s in j.steps:
        if STATE_WRITE.search(str(s.get("run") or "")):
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
    j.applies_state_root = any(step_wd(j, s) in state_roots for s in state_write_steps(j))
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
DOPPLER_SECRETS_GET = re.compile(r"doppler\s+secrets\s+get\s+([A-Za-z_][A-Za-z0-9_]*)")
ac3 = []
# THE ONE SANCTIONED READ: a Tier-A job may read `HCLOUD_TOKEN` as the SECOND arm of a
# `HCLOUD_TOKEN_READONLY`-first read in the SAME step (ADR-241 D4). That is the before-state
# fallback -- `workspaces-luks-cutover::cutover` only READS a Hetzner volume id, so it takes
# the read-permission token, and the fallback keeps it working until the operator mints one at
# step O5. It disappears with the name at O10.
#
# The allowance is ORDER-ANCHORED, not a name allowlist: the read-only name must appear
# EARLIER in the step body than the privileged one, so the privileged read is genuinely
# unreachable while the read-only name resolves. A bare `HCLOUD_TOKEN` read with no preceding
# read-only read is still RED, which is the mutation row below.
def _first(body, name):
    """Index of the first `doppler secrets get <name>` where <name> is the WHOLE token."""
    mm = re.search(r"doppler\s+secrets\s+get\s+" + re.escape(name) + r"(?![A-Za-z0-9_])", body)
    return mm.start() if mm else -1

RO_FIRST = {"HCLOUD_TOKEN": "HCLOUD_TOKEN_READONLY"}
for rel, (doc, text) in sorted(docs.items()):
    if rel == LOADER_REL:
        continue
    for j in [x for x in jobs if x.rel == rel]:
        for st in j.steps:
            body = str(st.get("run") or "")
            for line, m in cmd_sites(body, DOPPLER_SECRETS_GET):
                name = m.group(1)
                if name not in TIER_B_NAMES or not PRD_TF.search(line[m.end():]):
                    continue
                ro = RO_FIRST.get(name)
                if ro:
                    # WORD-BOUNDED, both sides. `HCLOUD_TOKEN` is a PREFIX of
                    # `HCLOUD_TOKEN_READONLY`, so a bare `.find()` for the privileged name
                    # matches the read-only occurrence and the two indices come back EQUAL
                    # -- the ordering test then reads "not earlier" and the allowance never
                    # applies. Same bare-token trap this file's own header warns about.
                    # COMMAND POSITION for the read-only read, not a raw scan. `_first` is
                    # a bare `re.search` over the whole step body, so it saw comments,
                    # heredoc bodies and `echo` arguments -- and a single comment line
                    #
                    #   # NOTE: the read-only path would be `doppler secrets get
                    #   # HCLOUD_TOKEN_READONLY --plain`,
                    #
                    # above a bare privileged read made that read LEGAL. The allowance is
                    # 1-of-1 on the live tree, so laundering it costs one comment and
                    # removes the row's only teeth.
                    ro_re = re.compile(r"doppler\s+secrets\s+get\s+" + re.escape(ro) + r"\b")
                    ro_pos = [_l for _l, _mm in cmd_sites(body, ro_re)]
                    i_ro = _first(body, ro) if ro_pos else -1
                    i_priv = _first(body, name)
                    if i_ro != -1 and i_priv != -1 and i_ro < i_priv:
                        continue
                ac3.append("%s [%s]" % (j.id, name))
check("G1g: no workflow step reads a tier_b_names entry with `-c prd_terraform` outside the loader "
      "(%s) [AC3]" % os.path.join(".github", LOADER_REL), not ac3, sorted(set(ac3))[:8])

# AC7b limb 2 — every writer of the shared state bucket is Tier B
writers = []
for j in jobs:
    for s in state_write_steps(j):
        wd = step_wd(j, s)
        if wd in state_roots and not (j.arms and all(a in TIER_B_ENVIRONMENTS for a in j.arms) and j.has_env_key):
            writers.append("%s [%s]" % (j.id, wd or "<repo root>"))
check("G1h: every job applying OR destroying against a `%s`-backed root declares a Tier-B environment [AC7b; "
      "%d such roots]" % (PRIV_STATE_BUCKET, len(state_roots)), not writers, sorted(set(writers))[:8])

# AC7b limb 1 — the backend-credential steps read TF_STATE_AWS_* first
# Does the LOADER alias the Tier-B state pair onto the plain backend names? This is what
# licenses the `${AWS_ACCESS_KEY_ID:-...}` form below. Read from the loader action, so the
# licence disappears the moment the alias does.
# Read in COMMAND POSITION, not as raw substrings. Two bare `in` tests over the whole text
# of action.yml were satisfiable by a single COMMENT line naming both tokens: replacing the
# two real alias `printf`s with `:` and leaving a comment behind kept `loader_aliases` True,
# G1i green, and 21 of the 22 live extract steps depending on an alias that no longer
# existed. That is the worst shape a composition check can take -- it licenses an exemption
# somewhere else, so the damage is not local to the line that is wrong.
_loader_doc, _loader_text = docs.get(LOADER_REL, ({}, ""))
_loader_runs = "\n".join(step_bodies(_loader_doc))
ALIAS_EXPORT = re.compile(r"printf\s+'AWS_(ACCESS_KEY_ID|SECRET_ACCESS_KEY)<<")
_alias_hits = {m.group(1) for _l, m in cmd_sites(_loader_runs, ALIAS_EXPORT)}
# Second clause: the aliased value must be SOURCED from the Tier-B name. The alias is
# `printf 'AWS_ACCESS_KEY_ID<<...' "$adelim" "$tf_id"`, and `$tf_id` is filled by a jq read
# of `.TF_STATE_AWS_ACCESS_KEY_ID` -- which is a jq FILTER, not a command, so cmd_sites
# correctly does not see it. Match it in the shell source with comments stripped instead:
# an alias that exports the plain names from something OTHER than the Tier-B pair is the R7
# defect, and would satisfy the first clause alone.
_loader_code = "\n".join(
    ln for ln in _loader_runs.split("\n") if not ln.lstrip().startswith("#")
)
loader_aliases = (
    _alias_hits == {"ACCESS_KEY_ID", "SECRET_ACCESS_KEY"}
    and "TF_STATE_AWS_ACCESS_KEY_ID" in _loader_code
    and "TF_STATE_AWS_SECRET_ACCESS_KEY" in _loader_code
)
# And the licence is worth its own verdict rather than only a silent input to G1i: when it
# is False, every `${AWS_ACCESS_KEY_ID:-...}` site below loses its exemption at once, and a
# reader needs to know that happened HERE rather than inferring it from 22 downstream rows.
check("G1i-pre: the loader exports BOTH backend aliases in command position, so the "
      "`${AWS_ACCESS_KEY_ID:-<legacy>}` form the extract steps use is genuinely backed "
      "[aliases found: %s]" % (sorted(_alias_hits) or "none"),
      loader_aliases, "alias_hits=%s" % sorted(_alias_hits))

EXTRACT = re.compile(r"extract\s+(r2\s+)?backend\s+credentials", re.I)
bad_extract, n_extract = [], 0
for j in tierb:
    for s in j.steps:
        body = CONT.sub(" ", str(s.get("run") or ""))
        if not (EXTRACT.search(str(s.get("name") or "")) or
                re.search(r"AWS_(ACCESS_KEY_ID|SECRET_ACCESS_KEY)\s*=", body)):
            continue
        n_extract += 1
        # Either Tier-B backend pair counts: `TF_STATE_AWS_*` for the shared
        # `soleur-terraform-state` roots, `GIT_DATA_ROOT_STATE_AWS_*` for the root-key root, whose
        # state moved to `soleur-terraform-state-privileged` (ADR-241 D3/D7). Both are loader
        # exports; what the row forbids is reading the `prd_terraform` pair FIRST.
        # A THIRD accepted form, and it is the one the implementation actually uses:
        # `${AWS_ACCESS_KEY_ID:-<legacy read>}`, where the plain name is supplied by the
        # LOADER, which aliases the Tier-B TF_STATE_AWS_* pair onto it.
        #
        # AC7b's literal wording says the STEP must name TF_STATE_AWS_*. Aliasing in the
        # loader satisfies the same PROPERTY -- the Tier-B read/write key is preferred and
        # the prd_terraform pair is only the fallback -- and satisfies it more completely,
        # because it also reaches extract steps nobody edited. Pinning the literal wording
        # would be pinning one implementation of the property.
        #
        # The teeth are preserved by COMPOSITION, not by trust: `loader_aliases` below is
        # read from the loader action itself, so deleting the alias there makes every site
        # using this form red at once. Without that check this limb would be an
        # unconditional exemption.
        alias_forms = ("${AWS_ACCESS_KEY_ID:-", "${AWS_SECRET_ACCESS_KEY:-") if loader_aliases else ()
        i_tf = min([body.index(x) for x in ("${TF_STATE_AWS_ACCESS_KEY_ID", "$TF_STATE_AWS_ACCESS_KEY_ID",
                                            "${GIT_DATA_ROOT_STATE_AWS_ACCESS_KEY_ID", "$GIT_DATA_ROOT_STATE_AWS_ACCESS_KEY_ID")
                                           + alias_forms
                    if x in body] or [len(body) + 1])
        i_legacy = min([m.start() for m in re.finditer(r"doppler\s+secrets\s+get\s+AWS_ACCESS_KEY_ID", body)] or [len(body) + 2])
        if i_tf > i_legacy:
            bad_extract.append("%s [%s]" % (j.id, (s.get("name") or "<unnamed>")))
check("G1i: every \"Extract backend credentials\"-shaped step in a Tier-B job reads its Tier-B "
      "backend pair (TF_STATE_AWS_*, or GIT_DATA_ROOT_STATE_AWS_* for the root-key root) before any "
      "prd_terraform AWS_* fallback [AC7b; %d such steps]" % n_extract,
      not bad_extract, sorted(set(bad_extract))[:8])

# ── Guard 2 ────────────────────────────────────────────────────────────────────────
BASH_CALL = re.compile(r"(?<![\w/-])bash\s+(?!-)([\"']?)([^\s\"';|&)]+)\1")

def invocations(body):
    """Each `doppler run` invocation's own argument text: from the token up to the ` -- ` separator
    or the end of its (continuation-joined) line. `[^\\n]` in an ERE is a bracket expression
    excluding backslash and the letter n, not "any char but newline", so the slice is taken by
    index rather than by a negated class."""
    for line, m in cmd_sites(body, DOPPLER_RUN):
        rest = line[m.end():]
        k = rest.find(" -- ")
        yield line[m.start():m.end() + (k if k != -1 else len(rest))]

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

# ── G4e: the eviction sentinel is refused BY NAME, everywhere the key is read ────────
#
# After operator step O10, Doppler `prd_terraform` holds the literal `EVICTED_SEE_ADR_241`
# under GITHUB_APP_PRIVATE_KEY instead of a key. The eviction HAS to be an override rather
# than a delete -- the value is inherited from `prd`, and a branch config cannot delete an
# inherited name -- so `doppler secrets get` SUCCEEDS and returns a non-empty string, which
# every check around it was written to treat as a key.
#
# `openssl rsa -check` rejects it downstream, so this row is not the difference between
# working and broken. It is the difference between an operator reading
# `verdict=legacy_app_key_evicted` and reading "not a valid RSA PEM" -- and the remedy that
# second message suggests is to paste a fresh key into `prd_terraform`, which UNDOES the
# eviction, on a config every branch of this public repository can read.
#
# ADR-241 D5, the plan and the #8209 runbook all promised this verdict. Nothing implemented
# it. This row is what keeps a fifth consumer from being added without it.
app_key_sites, app_key_missing = [], []
for rel, (doc, text) in sorted(docs.items()):
    for stepbody in step_bodies(doc):
        if not any(True for _l, _m in cmd_sites(stepbody, APP_PEM_READ)):
            continue
        app_key_sites.append(rel)
        # Command position, not raw text: the sentinel name appears in COMMENTS at three of
        # these sites (the rationale pointer), so a raw `in` test passes on a site whose
        # refusal was deleted and whose comment was left behind -- which is the single most
        # likely way this regresses.
        has_guard = any(True for _l, _m in cmd_sites(stepbody, SENTINEL_TEST))
        has_verdict = "verdict=legacy_app_key_evicted" in stepbody
        if not (has_guard and has_verdict):
            app_key_missing.append("%s guard=%s verdict=%s" % (rel, has_guard, has_verdict))
check("G4e: every step that reads GITHUB_APP_PRIVATE_KEY from Doppler refuses the "
      "EVICTED_SEE_ADR_241 sentinel by name and emits verdict=legacy_app_key_evicted "
      "[%d reading steps]" % len(app_key_sites),
      # The floor is on the LIVE tree only. The mutation fixtures below are synthetic
      # workflow trees that contain none of these consumers, and a floor of 4 applied to
      # them would make every mutant red for a reason unrelated to what it mutates -- which
      # reads as coverage and is the opposite of it. On a synthetic tree the row asserts the
      # implication only: any site that DOES read the key carries the refusal.
      (len(app_key_sites) >= (4 if CHECK_GIT else 0)) and not app_key_missing,
      "sites=%d live=%s missing=%s" % (len(app_key_sites), CHECK_GIT, app_key_missing[:5]))

# ── Guard 5: `plan_only` only ever SUBTRACTS ────────────────────────────────────────
#
# ADR-241 D-Guard-5 declares this and NOTHING implemented it: `git grep plan_only` over every
# non-yml, non-knowledge-base file returned one hit, and it was the comment at the top of THIS
# file claiming the guard exists. Seven `if: inputs.plan_only != true` keys across two recovery
# jobs were pinned by nothing -- deleting any one of them, or inverting one to `== true`, was
# caught by no test.
#
# It is not cosmetic. `plan_only` is operator step O4b: a REHEARSAL of both host-replace paths
# from `main`, run before O10 removes the legacy credential fallback, precisely because those
# paths fail closed on a recovery route during the incident they exist to fix. A rehearsal that
# silently performs the apply is worse than no rehearsal -- it destroys a live host while the
# operator believes they are dry-running.
#
# Three properties, from the ADR's own wording: every MUTATING step carries the guard, no step
# is ENABLED by it, and the input-validation / interlock / typo-guard steps stay UNCONDITIONAL.
PLAN_ONLY_JOBS = {"web_host_replace", "git_data_host_replace"}
# The apply is wrapped (`doppler run ... -- terraform apply`), so `terraform apply` is NOT at
# a command boundary and cmd_sites correctly refuses it. Reuse the census's own APPLY matcher
# -- the same one G1h derives the state-writer set from -- and add host contact on top.
HOST_CONTACT = re.compile(r"(^|[|;&(]\s*)(ssh|scp)\s", re.M)
GATE_NAME = re.compile(r"interlock|validate\s+dispatch|verify\s+required|preflight", re.I)
GUARD = re.compile(r"inputs\.plan_only\s*!=\s*true")
ENABLED_BY = re.compile(r"inputs\.plan_only\s*==\s*true|!\s*\(?\s*inputs\.plan_only\s*!=\s*true")

p5_jobs, p5_unguarded, p5_enabled, p5_cond_gates, n_mut, n_gate = set(), [], [], [], 0, 0
for j in jobs:
    if j.name not in PLAN_ONLY_JOBS:
        continue
    p5_jobs.add(j.name)
    for st in j.steps:
        nm = str(st.get("name") or st.get("uses") or "")
        cond = str(st.get("if") or "")
        body = str(st.get("run") or "")
        if ENABLED_BY.search(cond):
            p5_enabled.append("%s / %s" % (j.name, nm[:50]))
        # MUTATING -> must carry the guard. Command position, so a `terraform apply` named in
        # an `echo` of operator instructions (this repo prints those constantly) is not a step
        # that applies anything.
        if APPLY.search(body) or any(True for _l, _m in cmd_sites(body, HOST_CONTACT)):
            n_mut += 1
            if not GUARD.search(cond):
                p5_unguarded.append("%s / %s [if=%s]" % (j.name, nm[:40], cond[:40] or "<none>"))
        # GATE -> must be unconditional. A gate that acquires ANY `if:` is a gate an operator
        # can arrange to skip, which is the opposite of what these steps are for.
        if GATE_NAME.search(nm):
            n_gate += 1
            if cond.strip():
                p5_cond_gates.append("%s / %s [if=%s]" % (j.name, nm[:40], cond[:40]))

check("G5a: every mutating step in the plan_only recovery jobs carries `inputs.plan_only != true` "
      "[%d jobs, %d mutating steps]" % (len(p5_jobs), n_mut),
      # Population floors on the LIVE tree only; on a synthetic fixture the rows assert the
      # implication (whatever IS there obeys the rule), so a mutant reds for what it mutates.
      (not CHECK_GIT or (len(p5_jobs) == len(PLAN_ONLY_JOBS) and n_mut >= 2)) and not p5_unguarded,
      "jobs=%s mutating=%d unguarded=%s" % (sorted(p5_jobs), n_mut, p5_unguarded[:5]))
check("G5b: no step in those jobs is ENABLED by plan_only — the input only ever SUBTRACTS "
      "[%d jobs]" % len(p5_jobs),
      (not CHECK_GIT or len(p5_jobs) == len(PLAN_ONLY_JOBS)) and not p5_enabled,
      "enabled=%s" % p5_enabled[:5])
check("G5c: the input-validation, interlock and typo-guard steps stay UNCONDITIONAL "
      "[%d gate steps]" % n_gate,
      (not CHECK_GIT or (len(p5_jobs) == len(PLAN_ONLY_JOBS) and n_gate >= 4)) and not p5_cond_gates,
      "gates=%d conditional=%s" % (n_gate, p5_cond_gates[:5]))

print("\n".join(out))
PY
CENSUS_ROWS=20

# census_rows <tsv> <err> — reports every row of one census run through pass()/fail().
census_rows() {
  local n=0 v name detail
  while IFS=$'\t' read -r v name detail; do
    [ -n "$v" ] || continue
    n=$((n + 1))
    if [ "$v" = ok ]; then pass "$name"; else fail "$name" "$detail"; fi
  done < "$1"
  # printf + exit, NEVER through fail(): this floor exists to catch a census that crashed
  # part-way, and fail() is one of the two helpers such a failure (or a launder) disarms.
  # ADR-193, and this file's own header says so 700 lines up.
  if [ "$n" -lt "$CENSUS_ROWS" ]; then
    printf 'G0 FLOOR: only %s census verdicts were produced, expected %s — the census crashed part-way and every row it never reached is silently absent.\n%s\n' \
      "$n" "$CENSUS_ROWS" "$(head -c 300 "$2")" >&2
    exit 1
  fi
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
      run: |
        set -euo pipefail
        # The fixture loader must actually ALIAS, because G1i's `${AWS_ACCESS_KEY_ID:-...}`
        # exemption is LICENSED by `loader_aliases` reading this file. With `run: echo loader`
        # here, that licence was False in the control and in every mutant -- so the branch 21
        # of the 22 live extract steps depend on was never exercised in either direction, and
        # the two mutation rows below (which delete the alias) had nothing to delete.
        tf_id="$(printf '%s' "$payload" | jq -r '.TF_STATE_AWS_ACCESS_KEY_ID // ""')"
        tf_secret="$(printf '%s' "$payload" | jq -r '.TF_STATE_AWS_SECRET_ACCESS_KEY // ""')"
        adelim="SOLEUR_EOF_$(openssl rand -hex 12)"
        {
          printf 'AWS_ACCESS_KEY_ID<<%s\n%s\n%s\n' "$adelim" "$tf_id" "$adelim"
          printf 'AWS_SECRET_ACCESS_KEY<<%s\n%s\n%s\n' "$adelim" "$tf_secret" "$adelim"
        } >> "$GITHUB_ENV"
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

# A compliant App-key consumer for G4e. Tier A on purpose: board-status-sync is
# fork-triggerable and stays Tier A by design (ADR-241 D5), so the row must hold on a job
# that is NOT Tier B -- a row that only ever sees Tier-B jobs would exempt the one consumer
# most exposed to an attacker.
cat > "$FIX/tree/.github/workflows/appkey.yml" <<'EOF'
name: fixture app key consumer
on: pull_request
jobs:
  mint:
    runs-on: ubuntu-24.04
    steps:
      - name: Mint
        env:
          DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN }}
        run: |
          set -euo pipefail
          PEM=$(doppler secrets get GITHUB_APP_PRIVATE_KEY --plain -p soleur -c prd_terraform)
          # Rationale: the #8209 eviction sentinel.
          if [[ "$PEM" == EVICTED_SEE_ADR_241 ]]; then
            echo "::error::verdict=legacy_app_key_evicted the key was evicted; do not re-set it."
            exit 1
          fi
          echo "$PEM" > /dev/null
EOF

# The two plan_only recovery jobs, in fixture form. Guard 5's rows can only ever demonstrate
# their PASS branch against the live tree -- every mutating step there already carries the
# guard -- so without this the three rows would be green whether the checks worked or were
# deleted outright.
cat > "$FIX/tree/.github/workflows/replace.yml" <<'EOF'
name: fixture replace paths
on:
  workflow_dispatch:
    inputs:
      plan_only:
        type: boolean
        default: false
jobs:
  web_host_replace:
    runs-on: ubuntu-24.04
    environment: infra-privileged
    steps:
      - name: Validate dispatch inputs
        run: |
          set -euo pipefail
          test -n "${CONFIRM:-x}"
      - name: Verify required secrets present
        run: |
          set -euo pipefail
          test -n "${T:-x}"
      - name: Terraform plan
        run: |
          set -euo pipefail
          doppler run --preserve-env -p soleur -c prd_terraform -- terraform plan
        env:
          T: ${{ secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED }}
      - name: Terraform apply (web-host replace)
        if: inputs.plan_only != true
        run: |
          set -euo pipefail
          doppler run --preserve-env -p soleur -c prd_terraform -- terraform apply -auto-approve
        env:
          T: ${{ secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED }}
  git_data_host_replace:
    runs-on: ubuntu-24.04
    environment: infra-privileged
    steps:
      - name: Rung-2 rehearsal interlock
        run: |
          set -euo pipefail
          test -n "${R:-x}"
      - name: Authorization-map interlock
        run: |
          set -euo pipefail
          test -n "${A:-x}"
      - name: Coherence preflight
        run: |
          set -euo pipefail
          test -n "${C:-x}"
      - name: Terraform apply (git-data-host -replace)
        if: inputs.plan_only != true
        run: |
          set -euo pipefail
          doppler run --preserve-env -p soleur -c prd_terraform -- terraform apply -auto-approve
        env:
          T: ${{ secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED }}
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
# Row 10 (review W1) — a DESTROY-ONLY job against the privileged-state root, no `environment:`,
# legacy loader only. This is git-data-rung2-rehearsal.yml::teardown as it shipped: it names no
# environment secret and runs no `terraform apply`, so the classifier scored it Tier A and G1h —
# "every state writer is Tier B" — never saw it. A destroy writes the same state object.
MUTDIR="$(fixcopy g1-10)"; assert_fixture_dir "$MUTDIR"
printf 'name: zz\non: workflow_dispatch\nenv:\n  INFRA_DIR: apps/web-platform/infra\njobs:\n  teardown:\n    runs-on: ubuntu-24.04\n    steps:\n      - uses: ./.github/actions/infra-credentials\n        with:\n          doppler-token-legacy: ${{ secrets.DOPPLER_TOKEN }}\n      - name: Teardown\n        working-directory: ${{ env.INFRA_DIR }}\n        env:\n          DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN }}\n        run: |\n          set -euo pipefail\n          doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- \\\n            terraform destroy -auto-approve -input=false\n' > "$MUTDIR/tree/.github/workflows/zz-destroy.yml"
if fixture_written g1-10-destroy-only-no-environment "$MUTDIR/tree/.github/workflows/zz-destroy.yml"; then
  fixcensus "$MUTDIR" "$T/mut/g1-10.tsv" ""
  mutant_red g1-10-destroy-only-no-environment wf_row "$T/mut/g1-10.tsv" "G1h:"
fi

# ── G1g: the read-only-first allowance must not be launderable by a comment ──────────
# The allowance is 1-of-1 on the live tree (`workspaces-luks-cutover::cutover`), so anything
# that satisfies it cheaply removes the row's only teeth. `_first` is a raw scan, so a single
# comment NAMING the read-only read above a bare privileged read used to make that read legal
# -- and "mention the safe form in a comment" is what a reader does when a lint complains.
MUTDIR="$(fixcopy g1-g1)"; assert_fixture_dir "$MUTDIR"
if mutate g1-g1-comment-laundered "$MUTDIR/tree/.github/workflows/tiera.yml" 2 \
     '$a\          # the read-only path is `doppler secrets get HCLOUD_TOKEN_READONLY --plain`\n          HCLOUD_TOKEN=$(doppler secrets get HCLOUD_TOKEN -p soleur -c prd_terraform --plain)'; then
  fixcensus "$MUTDIR" "$T/mut/g1-g1.tsv" ""
  mutant_red g1-g1-comment-laundered wf_row "$T/mut/g1-g1.tsv" "G1g:"
fi
# CONTROL for the allowance's POSITIVE branch: a genuine read-only-first read in the same
# step must still be ACCEPTED, or the fix above would be "delete the allowance" wearing a
# mutation row's clothes.
MUTDIR="$(fixcopy g1-g2)"; assert_fixture_dir "$MUTDIR"
if mutate g1-g2-genuine-ro-first "$MUTDIR/tree/.github/workflows/tiera.yml" 2 \
     '$a\          RO=$(doppler secrets get HCLOUD_TOKEN_READONLY -p soleur -c prd_terraform --plain)\n          HCLOUD_TOKEN=${RO:-$(doppler secrets get HCLOUD_TOKEN -p soleur -c prd_terraform --plain)}'; then
  fixcensus "$MUTDIR" "$T/mut/g1-g2.tsv" ""
  if wf_row "$T/mut/g1-g2.tsv" "G1g:"; then
    pass "M-g1-g2-genuine-ro-first: a real read-only-first read is still ALLOWED (the allowance was not simply deleted)"
  else
    fail "M-g1-g2-genuine-ro-first: the allowance no longer accepts a genuine read-only-first read" "$(grep G1g "$T/mut/g1-g2.tsv" | cut -c1-200)"
  fi
fi

# ── Guard 5 ─────────────────────────────────────────────────────────────────────────
# Row 5a — drop the guard from ONE apply step. This is the edit nothing caught: seven of
# these keys shipped pinned by no test, and an O4b rehearsal that silently applies destroys a
# live host while the operator believes they are dry-running.
MUTDIR="$(fixcopy g5-a)"; assert_fixture_dir "$MUTDIR"
if mutate g5-a-guard-dropped "$MUTDIR/tree/.github/workflows/replace.yml" 1 \
     '0,/^        if: inputs.plan_only != true$/{/^        if: inputs.plan_only != true$/d}'; then
  fixcensus "$MUTDIR" "$T/mut/g5-a.tsv" ""
  mutant_red g5-a-guard-dropped wf_row "$T/mut/g5-a.tsv" "G5a:"
fi
# Row 5b — INVERT one guard so the step is ENABLED by plan_only. The rehearsal then does the
# one thing it exists not to do, and G5a alone stays green because the guard is still there.
MUTDIR="$(fixcopy g5-b)"; assert_fixture_dir "$MUTDIR"
if mutate g5-b-guard-inverted "$MUTDIR/tree/.github/workflows/replace.yml" 4 \
     's/^        if: inputs.plan_only != true$/        if: inputs.plan_only == true/'; then
  fixcensus "$MUTDIR" "$T/mut/g5-b.tsv" ""
  mutant_red g5-b-guard-inverted wf_row "$T/mut/g5-b.tsv" "G5b:"
fi
# Row 5c — give an INTERLOCK an `if:`. A gate an operator can arrange to skip is the opposite
# of a gate, and this is the shape a "make the rehearsal quieter" edit naturally takes.
MUTDIR="$(fixcopy g5-c)"; assert_fixture_dir "$MUTDIR"
if mutate g5-c-gate-conditional "$MUTDIR/tree/.github/workflows/replace.yml" 1 \
     '/^      - name: Authorization-map interlock$/a\        if: inputs.plan_only != true'; then
  fixcensus "$MUTDIR" "$T/mut/g5-c.tsv" ""
  mutant_red g5-c-gate-conditional wf_row "$T/mut/g5-c.tsv" "G5c:"
fi

# ── G1i-pre: the alias LICENCE, in both directions ───────────────────────────────────
# Row i1 — replace the two real alias exports with a COMMENT naming both tokens. A raw
# substring test over action.yml's text reads True here, licenses the
# `${AWS_ACCESS_KEY_ID:-...}` exemption at every extract step, and the loader exports
# nothing. This is the mutant that measured GREEN before the command-position fix.
MUTDIR="$(fixcopy g1-i1)"; assert_fixture_dir "$MUTDIR"
if mutate g1-i1-alias-commented "$MUTDIR/tree/.github/actions/infra-credentials/action.yml" 4 \
     's/^(\s*)printf .AWS_(ACCESS_KEY_ID|SECRET_ACCESS_KEY)<<.*$/\1# AWS_\2<< via TF_STATE_AWS_ACCESS_KEY_ID/'; then
  fixcensus "$MUTDIR" "$T/mut/g1-i1.tsv" ""
  mutant_red g1-i1-alias-commented wf_row "$T/mut/g1-i1.tsv" "G1i-pre:"
fi
# Row i2 — keep both exports, but source them from somewhere that is NOT the Tier-B pair.
# The first clause alone is satisfied; this is the R7 defect with the appearance of the fix.
MUTDIR="$(fixcopy g1-i2)"; assert_fixture_dir "$MUTDIR"
if mutate g1-i2-alias-wrong-source "$MUTDIR/tree/.github/actions/infra-credentials/action.yml" 4 \
     's/TF_STATE_AWS_(ACCESS_KEY_ID|SECRET_ACCESS_KEY)/LEGACY_AWS_\1/'; then
  fixcensus "$MUTDIR" "$T/mut/g1-i2.tsv" ""
  mutant_red g1-i2-alias-wrong-source wf_row "$T/mut/g1-i2.tsv" "G1i-pre:"
fi

# ── Guard 4 row e ────────────────────────────────────────────────────────────────────
# Row e1 — DELETE the sentinel guard, leave the rationale comment behind. This is the
# realistic regression: someone removes the `if`, the comment above it survives the edit,
# and a raw-text census reads the sentinel name out of the COMMENT and stays green.
MUTDIR="$(fixcopy g4-e1)"; assert_fixture_dir "$MUTDIR"
if mutate g4-e1-guard-deleted "$MUTDIR/tree/.github/workflows/appkey.yml" 1 '/^          if \[\[ "\$PEM" == EVICTED_SEE_ADR_241 \]\]; then$/d'; then
  fixcensus "$MUTDIR" "$T/mut/g4-e1.tsv" ""
  mutant_red g4-e1-guard-deleted wf_row "$T/mut/g4-e1.tsv" "G4e:"
fi
# Row e2 — keep the guard, drop the VERDICT word from the message. The job still fails
# closed, so nothing breaks; the operator just gets a message they cannot grep for, which is
# the whole reason this refusal exists rather than relying on `openssl rsa -check`.
MUTDIR="$(fixcopy g4-e2)"; assert_fixture_dir "$MUTDIR"
if mutate g4-e2-verdict-dropped "$MUTDIR/tree/.github/workflows/appkey.yml" 2 's/verdict=legacy_app_key_evicted the key/the key/'; then
  fixcensus "$MUTDIR" "$T/mut/g4-e2.tsv" ""
  mutant_red g4-e2-verdict-dropped wf_row "$T/mut/g4-e2.tsv" "G4e:"
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
# 26 -> 27 (review W1): M-g1-10-destroy-only-no-environment.
MUTANT_FLOOR=27
if [ "$MUTANTS_RUN" -lt "$MUTANT_FLOOR" ]; then
  printf 'FAIL MUTANT FLOOR: only %s mutants executed, floor is %s — a matrix row did not land or was deleted.\n' "$MUTANTS_RUN" "$MUTANT_FLOOR" >&2
  exit 1
fi
# Assertion FLOOR: live census 16 + harness 7 + mutants 17 x 2 = 57 (exact).
_ran=$((passes + fails))
# 80 -> 82 (review W1): M-g1-10's fixture-written row and its RED row. Measured: 82 ran.
FLOOR=82
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
