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
# Global flags before `secrets`, flags before the name, and a quoted name are all the same
# read (#9360 review): `doppler -p soleur secrets get --plain "GITHUB_APP_PRIVATE_KEY"`. The
# argument runs stop at a shell separator, so a later command on the line is not absorbed.
APP_PEM_READ = re.compile(r"doppler\s+(?:[^\s;|&)]+\s+)*?secrets\s+get\s+(?:[^\s;|&)]+\s+)*?[\"']?(GITHUB_APP_PRIVATE_KEY)\b")
# Anchored on the `if`, not on the `[[`: cmd_sites tests what precedes the MATCH START for a
# command boundary, and a bare `[[` is preceded by `if ` -- which is a keyword, not a boundary
# token, so the match was rejected at all four live sites. Starting at `if` puts the match at
# line start, where the boundary is unambiguous.
SENTINEL_TEST = re.compile(r'if\s+\[\[\s*"\$PEM"\s*==\s*EVICTED_SEE_ADR_241\s*\]\]')

def step_sites(doc):
    """(job, run body) for every `run:` step in a workflow OR a composite action.

    `job` is `(name, body)` for a workflow step and None for a composite step. Composite
    actions keep their steps under `runs.steps`, not `jobs.*.steps` -- the job model above
    iterates `doc["jobs"]` and therefore contributes ZERO steps for them, so a row built on
    that model would silently exempt `.github/actions/**`.
    """
    if not isinstance(doc, dict):
        return
    for jn, j in (doc.get("jobs") or {}).items():
        if isinstance(j, dict):
            for st in (j.get("steps") or []):
                if isinstance(st, dict) and st.get("run"):
                    yield (jn, j), str(st["run"])
    runs = doc.get("runs")
    if isinstance(runs, dict):
        for st in (runs.get("steps") or []):
            if isinstance(st, dict) and st.get("run"):
                yield None, str(st["run"])

def step_bodies(doc):
    """Every `run:` body in a workflow OR a composite action (step_sites without the job)."""
    for _job, body in step_sites(doc):
        yield body

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
# #6604 step 7 widened it to `state rm|mv|push`: workspaces-plaintext-forget.yml writes this state with
# `terraform state rm` and no apply at all, which must classify exactly like an apply (G1h).
STATE_WRITE = re.compile(r"(?<![-\w])terraform\s+(apply|destroy|state\s+(rm|mv|push))(?![-\w])")
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

# Root-specificity pin (measured gap, O8 migration run): G1i's alias exemption verifies a Tier-B
# pair beats prd_terraform, but it cannot see WHICH Tier-B pair a root needs. The root-key root's
# backend bucket is `soleur-terraform-state-privileged`, which answers only to the loader's
# GIT_DATA_ROOT_STATE_* pair — the generic AWS_* alias (the TF_STATE_* pair, scoped to the legacy
# bucket) gets 403 on it. The workflow's extract step must therefore name the root-key pair first;
# an `${AWS_ACCESS_KEY_ID:-...}`-first form satisfies G1i while routing the wrong credential.
_rk_doc, _rk_text = docs.get(os.path.join("workflows", "apply-git-data-root-key.yml"), ({}, ""))
# Comments stripped before matching — the same laundering class g1-g1 was hardened for: a
# `# prefers ${GIT_DATA_ROOT_STATE_*}` line above a non-compliant body must not satisfy it.
_rk_extract = [
    "\n".join(ln for ln in b.split("\n") if not ln.lstrip().startswith("#"))
    for b in step_bodies(_rk_doc)
]
_rk_extract = [b for b in _rk_extract if "doppler secrets get AWS_ACCESS_KEY_ID" in b]
def _pos(body, needle):
    # +inf when absent: the ordering chain then fails closed rather than raising ValueError
    # out of the census entirely (measured: the dropped-pair mutant killed the script before
    # the row printed, and mutant_red read the dead run as "stayed green").
    return body.index(needle) if needle in body else 1 << 30
_rk_order_ok = all(
    _pos(b, "${GIT_DATA_ROOT_STATE_AWS_ACCESS_KEY_ID") < _pos(b, "${AWS_ACCESS_KEY_ID")
    < _pos(b, "doppler secrets get AWS_ACCESS_KEY_ID")
    and _pos(b, "${GIT_DATA_ROOT_STATE_AWS_SECRET_ACCESS_KEY") < _pos(b, "${AWS_SECRET_ACCESS_KEY")
    < _pos(b, "doppler secrets get AWS_SECRET_ACCESS_KEY")
    for b in _rk_extract
)
check("G1i-rk: apply-git-data-root-key.yml's extract step reads GIT_DATA_ROOT_STATE_AWS_* before "
      "the AWS_*/prd_terraform fallback (the privileged bucket answers only to that pair) "
      "[%d extract steps]" % len(_rk_extract),
      len(_rk_extract) == 1 and _rk_order_ok,
      "extract_steps=%d order_ok=%s" % (len(_rk_extract), _rk_order_ok))

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
# INTENDED DESTROYS. A resource block deleted ON PURPOSE so the per-merge apply destroys it: a bare
# `-target=` on an address with no configuration plans its delete (the #9062 precedent). An entry
# is honoured only when its root's apply still targets it bare (else the delete is never planned
# and the address orphans under management), and never for the App identity this guard protects
# (G4f). Entries go stale once the destroy has applied and main no longer declares the address;
# the follow-up that removes the `-target=` lines removes them here too.
INTENDED_DESTROYS = {
    "apps/web-platform/infra": {
        "doppler_secret.ghcr_read_user": "#8714 ADR-096 5.4",
        "doppler_secret.ghcr_read_token": "#8714 ADR-096 5.4",
        "doppler_service_token.ghcr_minter": "#8714 ADR-096 5.4",
        "doppler_secret.ghcr_minter_doppler_token": "#8714 ADR-096 5.4",
    },
}
G4_PROTECTED = {"doppler_secret.github_app_id", "doppler_secret.github_app_private_key"}
orphans = []
for r in GUARD4_ROOTS:
    for a in sorted(base_declared.get(r, set())):
        if a not in declared_addrs[r] and a not in forgotten_addrs[r]:
            if (a in INTENDED_DESTROYS.get(r, {}) and a not in G4_PROTECTED
                    and a in root_targets.get(r, set())):
                continue
            orphans.append("%s %s" % (r, a))
check("G4c: every `resource` block the base ref declares and HEAD no longer declares is claimed by a "
      "`removed` block — a deleted resource block with none leaves the resource managed with no HCL, "
      "and the next apply plans a plain DESTROY [base .tf files: %d]" % n_base,
      bool(BASE_ROOT) and n_base >= 1 and not orphans,
      ("base unavailable" if not BASE_ROOT else "orphans=%s" % orphans[:8]))
bad_intended = sorted({a for _r, d in INTENDED_DESTROYS.items() for a in d if a in G4_PROTECTED})
check("G4f: no INTENDED_DESTROYS entry names the App identity (%s) — that pair may only ever be "
      "FORGOTTEN, never destroyed" % ", ".join(sorted(G4_PROTECTED)), not bad_intended, bad_intended)

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
# it. This row is what keeps a new consumer from being added without it.
#
# Floor 4 -> 3 (#9262): the mint composite (.github/actions/mint-infra-app-token) no
# longer reads GITHUB_APP_PRIVATE_KEY; it mints the Tier-B soleur-infra identity from the
# fixed Tier-B project soleur-infra-privileged, so it left this population. The property
# is unchanged over the three remaining inline readers.
#
# Floor 3 -> exact 1 (#9360, 2026-10-01): apply-github-infra and
# apply-web-platform-infra::entrypoint_audit no longer read GITHUB_APP_PRIVATE_KEY. The
# first mints the Tier-B soleur-infra token through the composite; the second posts with
# its own github.token. The one remaining reader is board-status-sync's legacy arm. The pin
# is EXACT and holds on the fixture tree too (its one reader is appkey.yml), so a second
# reader is a deliberate census edit with a dated rationale, never a silent pass because it
# carries the refusal; and a tree with ZERO readers reds as well, which makes the pin the
# row's own anti-vacuity floor.
#
# Tier clause (#9360): no reading site may sit in a job bound to a Tier-B environment. After
# O10 such a read can only ever return the sentinel, which is exactly the #9360 incident
# (apply-github-infra ran under environment infra-privileged and still read prd_terraform).
# A composite has no job of its own, so it takes its callers' environments.
#
# Sunset: the row retires once board-status-sync's legacy arm and the Doppler name
# GITHUB_APP_PRIVATE_KEY are deleted.
#
# SCOPE, stated (#9360 review): the row counts `doppler secrets get` FETCHES of the name, in
# command position. It does not see `doppler run` injecting a whole config into a child's
# env: every Terraform step over prd_terraform still receives the name (the sentinel, after
# O10) as TF_VAR_github_app_private_key, inert there because the provider selector prefers
# the infra key (ADR-241 D5). Nor does it see a script a step invokes, or a heredoc.
def arms_maybe_tier_b(raw):
    """True when an `environment:` value can resolve to a Tier-B environment. Names compare
    case-insensitively (GitHub environment names do), and an arm env_arms cannot resolve to
    a literal ("" -- an expression with no literal, a mapping with no name) counts as maybe
    Tier B: this is a ban, so the unknown direction is the refusing one."""
    arms = env_arms(raw)
    if arms is None:
        return False
    tier_b = {e.lower() for e in TIER_B_ENVIRONMENTS}
    return any(a == "" or a.lower() in tier_b for a in arms)

# A composite runs in each CALLER's job, so its Tier-B status is its callers'. Resolve
# `uses: ./.github/actions/<dir>` to the composite's file.
composite_callers = {}
for rel, (doc, text) in sorted(docs.items()):
    for jn, jb in (doc.get("jobs") or {}).items():
        if not isinstance(jb, dict):
            continue
        for st in (jb.get("steps") or []):
            u = str(st.get("uses") or "") if isinstance(st, dict) else ""
            m = re.match(r"\./\.github/(actions/[^@\s]+?)/?$", u)
            if m:
                for leaf in ("action.yml", "action.yaml"):
                    composite_callers.setdefault("%s/%s" % (m.group(1), leaf), []).append(
                        ("%s::%s" % (rel, jn), jb.get("environment")))

app_key_sites, app_key_missing, app_key_tierb = [], [], []
for rel, (doc, text) in sorted(docs.items()):
    for job, stepbody in step_sites(doc):
        reads = [1 for _l, _m in cmd_sites(stepbody, APP_PEM_READ)]
        if not reads:
            continue
        # Count READS, not reading steps: a second fetch inside one guarded step is a second
        # member of the population the pin bounds.
        app_key_sites.extend([rel] * len(reads))
        if job is not None:
            if arms_maybe_tier_b(job[1].get("environment")):
                app_key_tierb.append("%s::%s" % (rel, job[0]))
        else:
            for caller, env in composite_callers.get(rel, []):
                if arms_maybe_tier_b(env):
                    app_key_tierb.append("%s via %s" % (rel, caller))
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
      "[%d reads], exactly 1, none in a Tier-B job" % len(app_key_sites),
      len(app_key_sites) == 1 and not app_key_missing and not app_key_tierb and not parse_err,
      "sites=%d missing=%s tierb=%s unparsed=%s" % (len(app_key_sites), app_key_missing[:5], app_key_tierb[:5], parse_err[:5]))

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

# ── Guard 6 (#8609, ADR-241 D10): the runtime App key's read token stays in Tier B ─────────
#
# PROPERTY. No branch-reachable surface -- a Tier-A job (directly, through a script it runs, or
# through another job's outputs), a repository-secret Doppler config, Terraform state or a plan
# artifact -- can carry the `soleur-github-app` read token, mint one, or read the project. The
# token is the only thing between a branch and the soleur-ai runtime App key, which holds
# `administration:write` on this repo and write access on every connected user's installation.
# The loader's RUNTIME export (the name is always defined, empty unless the job opted in) is not
# statically observable; it is Guard 8, .github/actions/infra-credentials/infra-credentials.test.sh.
# Every spelling of the one credential: the CI/Tier-B names (GITHUB_APP_RUNTIME_DOPPLER_TOKEN,
# TF_VAR_github_app_runtime_doppler_token, the loader input github-app-runtime-token) AND the
# host-side ones (GITHUB_APP_DOPPLER_TOKEN in the credential file, github_app_doppler_token in the
# template). Not bare `github_app_token`: that is the minted-installation-token family.
G6_NAME = re.compile(r"github[_-]app[_-](?:runtime[_-](?:doppler[_-])?|doppler[_-])token", re.I)
G6_PROJECT_LIT = re.compile(r'"soleur-github-app"')
G6_PROJECT_ADDR = re.compile(r"\bdoppler_(?:project\.github_app_runtime|environment\.github_app_runtime_prd|config\.github_app_runtime_[A-Za-z0-9_]+)\b")
G6_VAR = "var.github_app_runtime_doppler_token"
# The state-residency fact (plan Phase 0.3) is a property of THIS provider version: 1.63.0 stores
# hcloud_server.user_data as a hash (internal/server.userDataHashSum). The token rides in web
# user_data, so a provider bump that stored the value would put it in Tier-A-readable state.
# Re-measure the binary before moving this pin (G6l).
G6_HCLOUD_PIN = "1.63.0"
G6_LOCK_REL = os.path.join("apps", "web-platform", "infra", ".terraform.lock.hcl")
G6_PR_TRIGGERS = {"pull_request", "pull_request_target"}

def g6_triggers(doc):
    on = doc.get("on") if "on" in doc else doc.get(True)
    if isinstance(on, str):
        return {on}
    if isinstance(on, list):
        return {str(x) for x in on}
    if isinstance(on, dict):
        return {str(k) for k in on}
    return set()

def g6_tier_b(j):
    """Main-only by construction: every `environment:` arm is a main-policied Tier-B environment
    (G1d proves the policy), and no pull-request trigger can start the job from a branch."""
    return (j.has_env_key and bool(j.arms) and all(a in TIER_B_ENVIRONMENTS for a in j.arms)
            and not (g6_triggers(docs[j.rel][0]) & G6_PR_TRIGGERS))

def g6_code(text):
    return "\n".join(l for l in text.split("\n") if not re.match(r"\s*(#|//)", l))

# The scripts every job reaches through one level of `bash <repo-path>` (same resolution as G2a).
g6_scripts = {}
for j in jobs:
    for s in j.steps:
        for raw, p in script_targets(str(s.get("run") or "")):
            full = os.path.join(REPO, p)
            if "$" not in p and os.path.isfile(full):
                g6_scripts.setdefault(j.id, []).append((p, open(full, encoding="utf-8", errors="replace").read()))

# G6a -- every job that names the token (or opts in to it) is main-only.
g6_refs, g6_bad_a = [], []
for j in jobs:
    if not G6_NAME.search(j.dump + jdump(j.env)):
        continue
    g6_refs.append(j.id)
    if not g6_tier_b(j):
        g6_bad_a.append("%s arms=%s triggers=%s" % (j.id, j.arms, sorted(g6_triggers(docs[j.rel][0]))))
check("G6a: every job that names the soleur-github-app read token or opts in to it declares a Tier-B "
      "environment and has no pull_request trigger [%d files scanned, %d referencing jobs]"
      % (len(files), len(g6_refs)),
      len(files) >= 1 and len(g6_refs) >= 1 and not g6_bad_a,
      "files=%d refs=%d bad=%s" % (len(files), len(g6_refs), g6_bad_a[:5]))

# G6a2 -- ...including through a script a non-Tier-B job runs.
g6_bad_a2, g6_n_scr = [], 0
for j in jobs:
    if g6_tier_b(j):
        continue
    for p, sbody in g6_scripts.get(j.id, []):
        g6_n_scr += 1
        if G6_NAME.search(sbody):
            g6_bad_a2.append("%s -> %s" % (j.id, p))
check("G6a2: no non-Tier-B job reaches the token name through a `bash <repo-path>` script "
      "[%d scripts resolved]" % g6_n_scr, not g6_bad_a2, sorted(set(g6_bad_a2))[:5])

# G6a3 -- ...or through another job's outputs.
g6_tainted_out = {}
for j in jobs:
    outs = j.body.get("outputs") or {}
    if not isinstance(outs, dict):
        continue
    by_id = {str(s.get("id")): s for s in j.steps if s.get("id")}
    for on, ov in outs.items():
        ov = str(ov)
        hit = bool(G6_NAME.search(ov))
        for sm in re.finditer(r"steps\.([A-Za-z0-9_-]+)\.outputs", ov):
            st = by_id.get(sm.group(1)) or {}
            srun = str(st.get("run") or "")
            if "GITHUB_OUTPUT" in srun and G6_NAME.search(srun + jdump(st.get("env") or {})):
                hit = True
        if hit:
            g6_tainted_out.setdefault((j.rel, j.name), set()).add(str(on))
g6_flow = []
for j in jobs:
    if g6_tier_b(j):
        continue
    for m in re.finditer(r"needs\.([A-Za-z0-9_-]+)\.outputs\.([A-Za-z0-9_-]+)", j.dump):
        if m.group(2) in g6_tainted_out.get((j.rel, m.group(1)), set()):
            g6_flow.append("%s <- %s.%s" % (j.id, m.group(1), m.group(2)))
check("G6a3: no job output carrying the token is read by a non-Tier-B job through needs.<job>.outputs "
      "[%d tainted outputs]" % sum(len(v) for v in g6_tainted_out.values()), not g6_flow, sorted(set(g6_flow))[:5])

# Every executable body the census can see: workflow and composite-action `run:` blocks, plus the
# one-level scripts of every job.
g6_bodies = []
for rel, (doc, _t) in sorted(docs.items()):
    for b in step_bodies(doc):
        g6_bodies.append((rel, b))
for jid, lst in sorted(g6_scripts.items()):
    for p, sbody in lst:
        g6_bodies.append(("%s via %s" % (jid, p), sbody))

# G6b -- the token name is only ever WRITTEN into the Tier-B project.
G6_SET = re.compile(r"doppler\s+secrets\s+set\b")
G6_PROJ_ARG = re.compile(r"(?:-p|--project)[= ]+([A-Za-z0-9_-]+)")
g6_bad_b = []
for where, b in g6_bodies:
    for line, m in cmd_sites(b, G6_SET):
        rest = line[m.end():]
        if not G6_NAME.search(rest):
            continue
        pm = G6_PROJ_ARG.search(rest)
        if not pm or pm.group(1) != "soleur-infra-privileged":
            g6_bad_b.append("%s: -p %s" % (where, pm.group(1) if pm else "<none>"))
check("G6b: no workflow, action or reachable script writes the token name into any Doppler project but "
      "soleur-infra-privileged (a `soleur` config is readable from every branch)", not g6_bad_b, g6_bad_b[:5])

# G6c / G6c2 -- Terraform never puts the token, or a way to read the project, into state.
LOCALS_OPEN = re.compile(r"^locals\s*\{", re.M)
DATA_OPEN = re.compile(r'^data\s+"([A-Za-z0-9_]+)"\s+"([A-Za-z0-9_]+)"\s*\{', re.M)
OUTPUT_OPEN = re.compile(r'^output\s+"([A-Za-z0-9_-]+)"\s*\{', re.M)
# Types that store a secret value, mint a credential, grant a reader, or copy values out. The plan
# names the first four; the rest are the same exposure through a different resource.
G6_STATEFUL = re.compile(r"^doppler_(?:service_token|secret|secrets|service_account_token|webhook|"
                         r"secrets_sync_[a-z_]+|integration_[a-z_]+|project_member_[a-z_]+)$")

def g6_close(text, open_idx):
    depth = 0
    for k in range(open_idx, len(text)):
        if text[k] == "(":
            depth += 1
        elif text[k] == ")":
            depth -= 1
            if depth == 0:
                return k
    return len(text)

def g6_attrs(body):
    """(name, expr) for each top-level attribute of an HCL block body (comments stripped). HCL
    continues an expression across lines only inside brackets, so an attribute ends on the line
    where its brackets balance -- which also keeps a following nested block (a provisioner's
    `environment`) out of it."""
    res, cur, buf, depth = [], None, [], 0
    for line in body.split("\n"):
        m = re.match(r"\s*([A-Za-z_][A-Za-z0-9_]*)\s*=(?!=)(.*)$", line) if depth == 0 else None
        if m:
            cur, buf = m.group(1), [m.group(2)]
        elif cur:
            buf.append(line)
        depth += sum(line.count(c) for c in "({[") - sum(line.count(c) for c in ")}]")
        if depth == 0 and cur:
            res.append((cur, "\n".join(buf)))
            cur, buf = None, []
    if cur:
        res.append((cur, "\n".join(buf)))
    return res

def g6_refs_any(expr, names):
    return any(re.search(r"(?<![\w.])" + re.escape(n) + r"(?!\w)", expr) for n in names)

def g6_admitted(expr):
    """`nonsensitive(can(regex(...)))` -- a boolean about the token, never the token."""
    e = expr.strip()
    m = re.match(r"nonsensitive\s*\(", e)
    return bool(m) and g6_close(e, m.end() - 1) == len(e) - 1 and \
        re.match(r"\s*can\s*\(\s*regex\s*\(", e[m.end():]) is not None

g6_tf = []
for r, fl in sorted(tf_root_files.items()):
    for p in fl:
        g6_tf.append((os.path.relpath(p, REPO), g6_code(open(p, encoding="utf-8", errors="replace").read())))
g6_locals = []
for rel, t in g6_tf:
    for _m, b in block_bodies(t, LOCALS_OPEN):
        g6_locals.extend(g6_attrs(b))
tainted = {G6_VAR}
while True:
    grown = {"local." + n for n, e in g6_locals
             if "local." + n not in tainted and not g6_admitted(e) and g6_refs_any(e, tainted)}
    if not grown:
        break
    tainted |= grown

g6_project_declared, g6_bad_c, g6_bad_c2 = False, [], []
for rel, t in g6_tf:
    for m, b in block_bodies(t, RES_OPEN) + block_bodies(t, DATA_OPEN):
        typ, nm = m.group(1), m.group(2)
        kind = "data" if m.group(0).startswith("data") else "resource"
        if kind == "resource" and typ == "doppler_project" and re.search(r'^\s*name\s*=\s*"soleur-github-app"\s*$', b, re.M):
            g6_project_declared = True
        if G6_STATEFUL.match(typ) and (G6_PROJECT_LIT.search(b) or G6_PROJECT_ADDR.search(b)):
            g6_bad_c.append("%s %s %s.%s on the project" % (rel, kind, typ, nm))
        if kind == "resource" and typ == "terraform_data":
            for an, ae in g6_attrs(b):
                if an == "input" and g6_refs_any(ae, tainted):
                    g6_bad_c2.append("%s terraform_data.%s input" % (rel, nm))
                if an == "triggers_replace":
                    rest, k = ae, 0
                    while True:
                        sm = re.search(r"\bsha256\s*\(", rest[k:])
                        if not sm:
                            break
                        s0 = k + sm.start()
                        rest = rest[:s0] + rest[g6_close(rest, k + sm.end() - 1) + 1:]
                        k = s0
                    if g6_refs_any(rest, tainted):
                        g6_bad_c2.append("%s terraform_data.%s triggers_replace (unhashed)" % (rel, nm))
    for m, b in block_bodies(t, OUTPUT_OPEN):
        if g6_refs_any(b, tainted):
            g6_bad_c.append("%s output.%s" % (rel, m.group(1)))
    for m in re.finditer(r"\bnonsensitive\s*\(", t):
        arg = t[m.end():g6_close(t, m.end() - 1)]
        if g6_refs_any(arg, tainted) and not re.match(r"\s*can\s*\(\s*regex\s*\(", arg):
            g6_bad_c.append("%s nonsensitive(%s)" % (rel, " ".join(arg.split())[:50]))
check("G6c: no root declares a doppler_secret / doppler_service_token / data doppler_secret(s) (or a "
      "sync, webhook, member or integration) on soleur-github-app, and no output or nonsensitive() "
      "exposes the token (only nonsensitive(can(regex(...))) is admitted) [%d .tf files, %d tainted names, "
      "project declared=%s]" % (len(g6_tf), len(tainted), g6_project_declared),
      len(g6_tf) >= 1 and g6_project_declared and not g6_bad_c,
      "tf=%d bad=%s" % (len(g6_tf), g6_bad_c[:5]))
check("G6c2: no terraform_data stores the token -- no `input` naming it and no `triggers_replace` "
      "naming it outside sha256(...)", not g6_bad_c2, g6_bad_c2[:5])

# G6d -- nothing in CI mints a token on the project (runbook R2 is the one, operator-run, mint).
G6_MINT = re.compile(r"doppler\s+(?:configs\s+tokens|service-tokens)\s+create\b")
g6_bad_d = []
for where, b in g6_bodies:
    for line, m in cmd_sites(b, G6_MINT):
        pm = G6_PROJ_ARG.search(line[m.end():])
        if pm and pm.group(1) == "soleur-github-app":
            g6_bad_d.append(where)
check("G6d: no workflow, action or reachable script mints a Doppler token on soleur-github-app",
      not g6_bad_d, sorted(set(g6_bad_d))[:5])

# G6e / G6m -- a Tier-B job's plan and its logs stay private. The saved plan carries every variable
# value in cleartext; TF_LOG trace output carries provisioner environments (SOLEUR_DOPPLER_TOKEN_B64).
g6_tb = [j for j in jobs if j.tier_b or g6_tier_b(j)]
g6_bad_e, g6_n_up = [], 0
for j in g6_tb:
    for s in j.steps:
        if not re.search(r"actions/upload-artifact\b", str(s.get("uses") or "")):
            continue
        g6_n_up += 1
        for pth in str((s.get("with") or {}).get("path") or "").split("\n"):
            pth = resolve(j, pth).strip()
            if pth and (re.search(r"tfplan|tfstate|\*", pth, re.I) or pth.rstrip("/") in tf_root_files):
                g6_bad_e.append("%s: %s" % (j.id, pth[:60]))
check("G6e: no Tier-B job uploads a saved plan, a state file, a terraform root or a glob as an artifact "
      "[%d upload steps in %d Tier-B jobs]" % (g6_n_up, len(g6_tb)), not g6_bad_e, g6_bad_e[:5])
g6_bad_m = []
for j in g6_tb:
    wenv = docs[j.rel][0].get("env") or {}
    keys = list(wenv) + list(j.body.get("env") or {}) + [k for s in j.steps for k in (s.get("env") or {})]
    if any(re.match(r"TF_LOG", str(k)) for k in keys):
        g6_bad_m.append("%s (env key)" % j.id)
    for s in j.steps:
        if re.search(r"(?<![\w$])TF_LOG\w*\s*=", g6_code(str(s.get("run") or ""))):
            g6_bad_m.append("%s (run body)" % j.id)
check("G6m: no Tier-B job sets TF_LOG (trace logs carry provisioner environments) [%d Tier-B jobs]" % len(g6_tb),
      not g6_bad_m, sorted(set(g6_bad_m))[:5])

# G6n -- no Doppler cross-project reference to the new project is written anywhere CI or a host
# renders from. Doppler may resolve such a reference, and then a `prd` writer could re-export the key
# into a branch-readable config. This is the static half; the live half is the operator bootstrap's
# xproj_ref_count (every `soleur` config, counted at R1 and again at R6), which replaced the
# dropped R0c scratch-project probe.
G6_XREF = re.compile(r"\$\$?\{\s*soleur-github-app\.")
g6_scan = [(rel, g6_code(t)) for rel, (_d, t) in sorted(docs.items())] + g6_tf + \
          [(w, g6_code(b)) for w, b in g6_bodies]
for base in [os.path.join(REPO, "apps", a, "infra") for a in
             (sorted(os.listdir(os.path.join(REPO, "apps"))) if os.path.isdir(os.path.join(REPO, "apps")) else [])]:
    if os.path.isdir(base):
        for f in sorted(os.listdir(base)):
            if f.endswith(".tmpl") or (f.startswith("cloud-init") and f.endswith(".yml")):
                g6_scan.append((os.path.relpath(os.path.join(base, f), REPO),
                                open(os.path.join(base, f), encoding="utf-8", errors="replace").read()))
g6_bad_n = sorted({rel for rel, t in g6_scan if G6_XREF.search(t)})
check("G6n: no workflow, action, reachable script, .tf, .tmpl or cloud-init file carries a Doppler "
      "reference `${soleur-github-app.` [%d files scanned]" % len(g6_scan), not g6_bad_n, g6_bad_n[:5])

# G6l -- the provider fact the state-residency argument rests on.
g6_lock = os.path.join(REPO, G6_LOCK_REL)
g6_ver = ""
if os.path.isfile(g6_lock):
    lm = re.search(r'provider\s+"registry\.terraform\.io/hetznercloud/hcloud"\s*\{\s*version\s*=\s*"([^"]+)"',
                   open(g6_lock, encoding="utf-8", errors="replace").read())
    g6_ver = lm.group(1) if lm else ""
check("G6l: the locked hcloud provider is %s, the version measured to store user_data as a hash "
      "(the token rides in web user_data) [locked: %s]" % (G6_HCLOUD_PIN, g6_ver or "<unreadable>"),
      g6_ver == G6_HCLOUD_PIN, "lock=%s" % g6_ver)

# G6o -- every plan context computes the same plan: no plan-visible attribute depends on an input
# that differs between the opted-in jobs and every other one (the token, which is "" outside the
# three opt-in jobs, and the delivering-job flag). Otherwise the Tier-A PR plan, the drift job and
# the push apply plan a change the opted-in apply undoes -- after R3, a deploy_pipeline_fix replace
# on every drift run (user-impact P1). A context-varying input may appear only in a lifecycle block
# (a precondition), a provisioner (not in the plan), or an attribute the resource ignore_changes.
# Unlike G6c's state taint, NOTHING is admitted here: a boolean about the token varies too.
G6_CTX_SEEDS = {G6_VAR, "var.github_app_runtime_token_delivered"}
MODULE_OPEN = re.compile(r'^module\s+"([A-Za-z0-9_-]+)"\s*\{', re.M)
g6_ctx = set(G6_CTX_SEEDS)
while True:
    grown = {"local." + n for n, e in g6_locals if "local." + n not in g6_ctx and g6_refs_any(e, g6_ctx)}
    if not grown:
        break
    g6_ctx |= grown
g6_bad_o, g6_n_ign = [], 0
for rel, t in g6_tf:
    blocks = [("resource", m, b) for m, b in block_bodies(t, RES_OPEN)] + \
             [("data", m, b) for m, b in block_bodies(t, DATA_OPEN)] + \
             [("module", m, b) for m, b in block_bodies(t, MODULE_OPEN)]
    for kind, m, b in blocks:
        addr = "%s.%s" % (m.group(1), m.group(2)) if kind != "module" else "module.%s" % m.group(1)
        ign = set()
        if kind == "resource":
            for im in re.finditer(r"\bignore_changes\s*=\s*\[([^\]]*)\]", b):
                ign |= {x.strip() for x in im.group(1).split(",") if x.strip()}
        for an, ae in g6_attrs(b):
            if not g6_refs_any(ae, g6_ctx):
                continue
            if an in ign:
                g6_n_ign += 1
                continue
            g6_bad_o.append("%s %s %s.%s" % (rel, kind, addr, an))
check("G6o: no plan-visible attribute (resource, data or module) depends on the token or the delivering-job "
      "flag, so every plan context (Tier-A PR plan, drift job, push apply, opted-in apply) computes the same "
      "deploy_pipeline_fix trigger [%d context-varying names, %d ignore_changes-exempt uses]" % (len(g6_ctx), g6_n_ign),
      len(g6_tf) >= 1 and not g6_bad_o, sorted(set(g6_bad_o))[:5])

# G6q -- the EXACT set of jobs that opt in to the token. G6a's population check is `>= 1`, so a
# dropped opt-in (web-1 would render the line empty forever) or a fourth one stayed green.
G6_OPTIN_EXPECTED = ({"workflows/apply-deploy-pipeline-fix.yml::apply",
                      "workflows/apply-web-platform-infra.yml::web_host_create",
                      "workflows/apply-web-platform-infra.yml::web_host_replace"}
                     if CHECK_GIT else {"workflows/tierb-apply.yml::apply"})
g6_optin = set()
for j in jobs:
    for s in j.steps:
        if "infra-credentials" in str(s.get("uses") or "") and \
           str((s.get("with") or {}).get("github-app-runtime-token", "")).strip().lower() == "true":
            g6_optin.add(j.id)
check("G6q: exactly the delivering jobs opt in to the token (github-app-runtime-token: true) [%d opted in, %d expected]"
      % (len(g6_optin), len(G6_OPTIN_EXPECTED)), g6_optin == G6_OPTIN_EXPECTED,
      "missing=%s extra=%s" % (sorted(G6_OPTIN_EXPECTED - g6_optin), sorted(g6_optin - G6_OPTIN_EXPECTED)))

# G6s -- the verifier-side identity pin on the verify whose rc 0 hands out the key (CTO ruling (b)).
# Every cosign verify inside ci-deploy.sh's verify_image_signature carries
# --certificate-github-workflow-ref=refs/heads/main and --certificate-github-workflow-repository=
# jikig-ai/soleur (the CALLER's run, which a branch cannot forge), and its identity regexp has no
# `refs/tags` arm. `"$NAME"` operands resolve to the file's single assignment of NAME.
G6S_REL = os.path.join("apps", "web-platform", "infra", "ci-deploy.sh")
G6S_WANT = {"--certificate-github-workflow-ref": "refs/heads/main",
            "--certificate-github-workflow-repository": "jikig-ai/soleur"}
g6s_path = os.path.join(REPO, G6S_REL)
g6s_bad, g6s_calls = [], 0
if os.path.isfile(g6s_path):
    g6s_text = open(g6s_path, encoding="utf-8", errors="replace").read()
    g6s_fm = re.search(r"^verify_image_signature\(\)\s*\{\n(.*?)^\}", g6s_text, re.M | re.S)
    def g6s_val(raw):
        v = raw.strip()
        if len(v) >= 2 and v[0] == v[-1] and v[0] in "'\"":
            v = v[1:-1]
        vm = re.fullmatch(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?", v)
        if not vm:
            return v
        defs = re.findall(r"^\s*(?:readonly\s+|local\s+|declare\s+-r\s+)?%s=(\S+)" % vm.group(1), g6s_text, re.M)
        if len(defs) != 1:
            return "\x00%d assignments of %s\x00" % (len(defs), vm.group(1))
        return g6s_val(defs[0])
    if not g6s_fm:
        g6s_bad.append("no verify_image_signature() function")
    else:
        for ln in g6s_fm.group(1).replace("\\\n", " ").split("\n"):
            if "#" in ln.split("--certificate", 1)[0] or "--certificate-identity" not in ln:
                continue
            g6s_calls += 1
            flags = {fm.group(1): g6s_val(fm.group(2)) for fm in
                     re.finditer(r"(--certificate-[a-z-]+)=(\"[^\"]*\"|'[^']*'|\S+)", ln)}
            for f, want in G6S_WANT.items():
                if flags.get(f) != want:
                    g6s_bad.append("%s=%r (want %s)" % (f, flags.get(f), want))
            idv = flags.get("--certificate-identity-regexp", flags.get("--certificate-identity", ""))
            if not idv or "refs/tags" in idv or "\x00" in idv:
                g6s_bad.append("identity=%r (must resolve, with no refs/tags arm)" % idv[:120])
else:
    g6s_bad.append("%s not found" % G6S_REL)
check("G6s: every cosign verify in ci-deploy.sh verify_image_signature (the key decision) pins the caller's "
      "workflow ref to refs/heads/main and the repository to jikig-ai/soleur, with no refs/tags identity arm "
      "[%d verify calls]" % g6s_calls, g6s_calls >= 1 and not g6s_bad, g6s_bad[:5])

# G6u -- every systemd unit or drop-in that loads the web host's credential file unsets the
# key-read name (CTO ruling (f)). `UnsetEnvironment=` applies after EnvironmentFile=, so inngest,
# redis, vector and the monitors keep DOPPLER_TOKEN and never hold GITHUB_APP_DOPPLER_TOKEN. Only
# ci-deploy.sh (webhook.service loads no such file; it parses it) and the boot download need it.
G6U_LOAD = re.compile(r"^\s*EnvironmentFile=-?/etc/default/soleur-doppler-token\s*$", re.M)
G6U_UNSET = re.compile(r"^\s*UnsetEnvironment=(?:.*\s)?GITHUB_APP_DOPPLER_TOKEN(?:\s.*)?$", re.M)
g6u_loaders, g6u_bad = [], []
for base in [os.path.join(REPO, "apps", a, "infra") for a in
             (sorted(os.listdir(os.path.join(REPO, "apps"))) if os.path.isdir(os.path.join(REPO, "apps")) else [])]:
    if not os.path.isdir(base):
        continue
    for f in sorted(os.listdir(base)):
        fp = os.path.join(base, f)
        if not os.path.isfile(fp) or ".test." in f or f.endswith((".md", ".awk")):
            continue
        body = open(fp, encoding="utf-8", errors="replace").read()
        if G6U_LOAD.search(body):
            g6u_loaders.append(f)
            if not G6U_UNSET.search(body):
                g6u_bad.append(f)
check("G6u: every unit or drop-in that loads /etc/default/soleur-doppler-token also has "
      "UnsetEnvironment=GITHUB_APP_DOPPLER_TOKEN [%d loaders]" % len(g6u_loaders),
      (len(g6u_loaders) >= (8 if CHECK_GIT else 1)) and not g6u_bad, "loaders=%d missing=%s" % (len(g6u_loaders), g6u_bad[:8]))

print("\n".join(out))
PY
CENSUS_ROWS=38  # 22 -> 23 (#9215): G1i-rk, the root-key extract-precedence row. 23 -> 34 (#8609): Guard 6, G6a..G6l.
# 34 -> 38 (#8609 review): G6o (plan-context invariance), G6q (exact opt-in set), G6s (cosign
# caller-ref pin), G6u (UnsetEnvironment sweep).

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
          github-app-runtime-token: true
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

cat > "$FIX/tree/.github/workflows/apply-git-data-root-key.yml" <<'EOF'
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
      - name: Extract R2 backend credentials
        env:
          DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN }}
        run: |
          set -euo pipefail
          KEY_ID="${GIT_DATA_ROOT_STATE_AWS_ACCESS_KEY_ID:-${AWS_ACCESS_KEY_ID:-$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)}}"
          SECRET="${GIT_DATA_ROOT_STATE_AWS_SECRET_ACCESS_KEY:-${AWS_SECRET_ACCESS_KEY:-$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)}}"
          printf 'AWS_ACCESS_KEY_ID=%s\n' "$KEY_ID" >> "$GITHUB_ENV"
          printf 'AWS_SECRET_ACCESS_KEY=%s\n' "$SECRET" >> "$GITHUB_ENV"
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

# Guard 6 (#8609): the isolated project, the render that carries its read token (shape gate keyed
# on the delivering-job flag, a trigger over the KEYLESS render + the committed generation, an
# ignore_changes'd user_data, the keyless-push guard: the post-review server.tf shape), the key
# decision's cosign verify, one credential-file loader, and the provider lock the state-residency
# fact rests on. Without these the G6 rows could only ever show their empty-population branch.
cat > "$FIX/tree/apps/web-platform/infra/github-app-runtime-project.tf" <<'EOF'
resource "doppler_project" "github_app_runtime" {
  name        = "soleur-github-app"
  description = "fixture"
}
resource "doppler_environment" "github_app_runtime_prd" {
  project = doppler_project.github_app_runtime.name
  slug    = "prd"
  name    = "Production"
}
resource "doppler_config" "github_app_runtime_prd_retired" {
  project     = doppler_project.github_app_runtime.name
  environment = doppler_environment.github_app_runtime_prd.slug
  name        = "prd_retired"
}
EOF

cat > "$FIX/tree/apps/web-platform/infra/server.tf" <<'EOF'
variable "github_app_runtime_doppler_token" {
  type      = string
  sensitive = true
  default   = ""
}
variable "github_app_runtime_token_delivered" {
  type    = bool
  default = false
}
locals {
  github_app_key_isolated = false
  github_app_token_shape_ok = nonsensitive(can(regex(
    local.github_app_key_isolated && var.github_app_runtime_token_delivered ? "^dp\\.st\\.[A-Za-z0-9._-]{20,}$" : "^(dp\\.st\\.[A-Za-z0-9._-]{20,})?$",
    var.github_app_runtime_doppler_token,
  )))
  webhook_doppler_token_env_keyless = templatefile("${path.module}/soleur-doppler-token.tmpl", {
    github_app_doppler_token = ""
  })
  webhook_doppler_token_env = templatefile("${path.module}/soleur-doppler-token.tmpl", {
    github_app_doppler_token = var.github_app_runtime_doppler_token
  })
  github_app_render_keyed = nonsensitive(can(regex("(?m)^GITHUB_APP_DOPPLER_TOKEN=.", local.webhook_doppler_token_env)))
}
resource "hcloud_server" "web" {
  name      = "web-1"
  user_data = base64encode(local.webhook_doppler_token_env)
  lifecycle {
    ignore_changes = [user_data, ssh_keys]
    precondition {
      condition     = local.github_app_token_shape_ok
      error_message = "the value is not shown"
    }
  }
}
resource "terraform_data" "deploy_pipeline_fix" {
  lifecycle {
    precondition {
      condition     = local.github_app_token_shape_ok
      error_message = "the value is not shown"
    }
  }
  triggers_replace = sha256(join(",", [
    local.webhook_doppler_token_env_keyless,
    "github_app_runtime_token_generation=0",
  ]))
  provisioner "local-exec" {
    command = local.github_app_key_isolated && !local.github_app_render_keyed ? "exit 1" : "true"
  }
  provisioner "local-exec" {
    command = "true"
    environment = {
      SOLEUR_DOPPLER_TOKEN_B64 = base64encode(local.webhook_doppler_token_env)
    }
  }
}
EOF

# G6s: the key decision's cosign verify, pinned on the caller's run (post-review ci-deploy.sh shape).
cat > "$FIX/tree/apps/web-platform/infra/ci-deploy.sh" <<'EOF'
#!/usr/bin/env bash
readonly COSIGN_IDENTITY_REGEXP='^https://github\.com/jikig-ai/soleur/\.github/workflows/reusable-release\.yml@refs/heads/main$'
readonly COSIGN_WORKFLOW_REF="refs/heads/main"
readonly COSIGN_WORKFLOW_REPOSITORY="jikig-ai/soleur"
verify_image_signature() {
  if docker run --rm "$COSIGN_IMAGE" verify --offline \
       --certificate-identity-regexp="$COSIGN_IDENTITY_REGEXP" \
       --certificate-github-workflow-ref="$COSIGN_WORKFLOW_REF" \
       --certificate-github-workflow-repository="$COSIGN_WORKFLOW_REPOSITORY" \
       --certificate-oidc-issuer="$COSIGN_OIDC_ISSUER" \
       "$repo_digest" >/dev/null; then
    printf '%s' "$repo_digest"
    return 0
  fi
  return 3
}
EOF

# G6u: one unit that loads the web host's credential file, and unsets the key-read name.
cat > "$FIX/tree/apps/web-platform/infra/10-vector-doppler-token.conf" <<'EOF'
[Service]
EnvironmentFile=-/etc/default/soleur-doppler-token
UnsetEnvironment=GITHUB_APP_DOPPLER_TOKEN
EOF

cat > "$FIX/tree/apps/web-platform/infra/.terraform.lock.hcl" <<'EOF'
provider "registry.terraform.io/hetznercloud/hcloud" {
  version     = "1.63.0"
  constraints = "~> 1.49"
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
# G6g / G6g2 — Guard 6's own dispatch self-tests, over the same two empty trees. Without them an
# empty tree reds only G1a/G4a, and a Guard 6 that had stopped scanning would still read green.
if ! wf_row "$T/empty-gh.tsv" "G6a:"; then
  pass "G6g: an empty workflow tree reds a G6 row (G6a: 0 files, 0 referencing jobs), not only G1a"
else
  fail "G6g: an empty workflow tree left G6a green" "$(grep -F 'G6a:' "$T/empty-gh.tsv" | cut -c1-200)"
fi
if grep -qE "^FAIL$(printf '\t')G6c: .*\[0 \.tf files" "$T/empty-tf.tsv"; then
  pass "G6g2: an empty .tf set makes G6c report 0 files and red"
else
  fail "G6g2: an empty .tf set did not red G6c with a 0-file count" "$(grep -F 'G6c:' "$T/empty-tf.tsv" | cut -c1-200)"
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
if mutate g1-8-environment-deleted "$MUTDIR/tree/.github/workflows/apply-git-data-root-key.yml" 1 '/^    environment: web-platform-infra-apply$/d'; then
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

# Row 11 (#6604 step 7) — a STATE-RM-ONLY job against the privileged-state root, no `environment:`.
# `terraform state rm` writes the same state object an apply does; before the STATE_WRITE widening this
# job scored Tier A and G1h never saw it (workspaces-plaintext-forget.yml is the live instance).
MUTDIR="$(fixcopy g1-11)"; assert_fixture_dir "$MUTDIR"
printf 'name: zz\non: workflow_dispatch\nenv:\n  INFRA_DIR: apps/web-platform/infra\njobs:\n  forget:\n    runs-on: ubuntu-24.04\n    steps:\n      - uses: ./.github/actions/infra-credentials\n        with:\n          doppler-token-legacy: ${{ secrets.DOPPLER_TOKEN }}\n      - name: Forget\n        working-directory: ${{ env.INFRA_DIR }}\n        run: |\n          set -euo pipefail\n          terraform state rm \x27hcloud_volume.workspaces["web-1"]\x27\n' > "$MUTDIR/tree/.github/workflows/zz-forget.yml"
if fixture_written g1-11-state-rm-only-no-environment "$MUTDIR/tree/.github/workflows/zz-forget.yml"; then
  fixcensus "$MUTDIR" "$T/mut/g1-11.tsv" ""
  mutant_red g1-11-state-rm-only-no-environment wf_row "$T/mut/g1-11.tsv" "G1h:"
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
# Row i3 — the measured O8 regression shape: the root-key root's extract step prefers the
# GENERIC AWS_* alias (the legacy-bucket pair) over GIT_DATA_ROOT_STATE_AWS_*. G1i alone stays
# green on this — it counts the alias form as compliant; only the root-specificity row sees it.
MUTDIR="$(fixcopy g1-i3)"; assert_fixture_dir "$MUTDIR"
if mutate g1-i3-rootkey-pair-dropped "$MUTDIR/tree/.github/workflows/apply-git-data-root-key.yml" 4 \
     's/\$\{GIT_DATA_ROOT_STATE_AWS_(ACCESS_KEY_ID|SECRET_ACCESS_KEY):-//g'; then
  fixcensus "$MUTDIR" "$T/mut/g1-i3.tsv" ""
  mutant_red g1-i3-rootkey-pair-dropped wf_row "$T/mut/g1-i3.tsv" "G1i-rk:"
fi
# Row i4 — the REORDER shape review named: the GIT_DATA pair still appears (satisfying presence
# and the doppler-order limb) but the generic alias wins precedence — the exact O8 defect.
MUTDIR="$(fixcopy g1-i4)"; assert_fixture_dir "$MUTDIR"
if mutate g1-i4-rootkey-pair-reordered "$MUTDIR/tree/.github/workflows/apply-git-data-root-key.yml" 4 \
     's/\$\{GIT_DATA_ROOT_STATE_AWS_(\w+):-\$\{AWS_\1/\$\{AWS_\1:-\$\{GIT_DATA_ROOT_STATE_AWS_\1/g'; then
  fixcensus "$MUTDIR" "$T/mut/g1-i4.tsv" ""
  mutant_red g1-i4-rootkey-pair-reordered wf_row "$T/mut/g1-i4.tsv" "G1i-rk:"
fi

# Each G4e row also asserts its CAUSE on the detail line (#9360 review): a later fixture edit
# that reds the row for a different reason (YAML that no longer parses, a deleted read) would
# otherwise keep the row "RED" while testing nothing it names.
g4e_cause() { # <name> <tsv> <detail substring>
  local d; d="$(awk -F'\t' 'index($2, "G4e:") == 1 { print $3 }' "$2")"
  case "$d" in
    *"$3"*) pass "M-$1: G4e reds for its named cause ($3)" ;;
    *) fail "M-$1: G4e's detail does not carry its named cause" "want [$3] got [${d:0:200}]" ;;
  esac
}
g4e_row() { # <name> <expected-diff-lines> <sed -E program> <cause substring>
  MUTDIR="$(fixcopy "$1")"; assert_fixture_dir "$MUTDIR"
  if mutate "$1" "$MUTDIR/tree/.github/workflows/appkey.yml" "$2" "$3"; then
    fixcensus "$MUTDIR" "$T/mut/$1.tsv" ""
    mutant_red "$1" wf_row "$T/mut/$1.tsv" "G4e:"
    g4e_cause "$1" "$T/mut/$1.tsv" "$4"
  fi
}
# ── Guard 4 row e ────────────────────────────────────────────────────────────────────
# Row e1 — DELETE the sentinel guard, leave the rationale comment behind. This is the
# realistic regression: someone removes the `if`, the comment above it survives the edit,
# and a raw-text census reads the sentinel name out of the COMMENT and stays green.
MUTDIR="$(fixcopy g4-e1)"; assert_fixture_dir "$MUTDIR"
if mutate g4-e1-guard-deleted "$MUTDIR/tree/.github/workflows/appkey.yml" 1 '/^          if \[\[ "\$PEM" == EVICTED_SEE_ADR_241 \]\]; then$/d'; then
  fixcensus "$MUTDIR" "$T/mut/g4-e1.tsv" ""
  mutant_red g4-e1-guard-deleted wf_row "$T/mut/g4-e1.tsv" "G4e:"
  g4e_cause g4-e1-guard-deleted "$T/mut/g4-e1.tsv" "guard=False verdict=True"
fi
# Row e2 — keep the guard, drop the VERDICT word from the message. The job still fails
# closed, so nothing breaks; the operator just gets a message they cannot grep for, which is
# the whole reason this refusal exists rather than relying on `openssl rsa -check`.
MUTDIR="$(fixcopy g4-e2)"; assert_fixture_dir "$MUTDIR"
if mutate g4-e2-verdict-dropped "$MUTDIR/tree/.github/workflows/appkey.yml" 2 's/verdict=legacy_app_key_evicted the key/the key/'; then
  fixcensus "$MUTDIR" "$T/mut/g4-e2.tsv" ""
  mutant_red g4-e2-verdict-dropped wf_row "$T/mut/g4-e2.tsv" "G4e:"
  g4e_cause g4-e2-verdict-dropped "$T/mut/g4-e2.tsv" "guard=True verdict=False"
fi
# e3 — a SECOND compliant reader, refusal included: only the exact pin (2 != 1) can red it.
g4e_row g4-e3-second-reader 1 '$a\      - run: PEM=$(doppler secrets get GITHUB_APP_PRIVATE_KEY --plain); if [[ "$PEM" == EVICTED_SEE_ADR_241 ]]; then echo "::error::verdict=legacy_app_key_evicted"; exit 1; fi' "sites=2 missing=[] tierb=[]"
# e3b — a second fetch INSIDE the one guarded step: the pin counts reads, not steps.
g4e_row g4-e3b-second-read-same-step 1 '/^          echo "\$PEM" > \/dev\/null$/a\          PEM2=$(doppler secrets get GITHUB_APP_PRIVATE_KEY --plain)' "sites=2 missing=[] tierb=[]"
# e3c — a second reader spelled flag-first with a quoted name: the widened matcher sees it.
g4e_row g4-e3c-flag-first-quoted 1 '$a\      - run: PEM=$(doppler -p soleur secrets get --plain "GITHUB_APP_PRIVATE_KEY"); if [[ "$PEM" == EVICTED_SEE_ADR_241 ]]; then echo "::error::verdict=legacy_app_key_evicted"; exit 1; fi' "sites=2 missing=[]"
# e4 family — the one compliant reader moves into a Tier-B job; count and refusal unchanged, so
# only the tier clause can red it. One row per form `environment:` can take.
g4e_row g4-e4-tier-b-reader 1 '/^    runs-on: ubuntu-24.04$/a\    environment: infra-privileged' "sites=1 missing=[] tierb=['workflows/appkey.yml::mint']"
g4e_row g4-e4m-mapping-form 2 '/^    runs-on: ubuntu-24.04$/a\    environment:\n      name: infra-privileged' "sites=1 missing=[] tierb=['workflows/appkey.yml::mint']"
g4e_row g4-e4x-unresolvable-expression 1 '/^    runs-on: ubuntu-24.04$/a\    environment: ${{ inputs.target }}' "sites=1 missing=[] tierb=['workflows/appkey.yml::mint']"
g4e_row g4-e4c-case-variant 1 '/^    runs-on: ubuntu-24.04$/a\    environment: Infra-Privileged' "sites=1 missing=[] tierb=['workflows/appkey.yml::mint']"
# e5 — the row's own dispatch: delete the only read, so it examines 0 sites. The exact pin is
# the anti-vacuity floor (0 != 1).
g4e_row g4-e5-no-reader 1 '/^          PEM=\$\(doppler secrets get GITHUB_APP_PRIVATE_KEY/d' "sites=0"
# e6 — the one read moves into a COMPOSITE called from a Tier-B job: the composite takes its
# caller's environment.
MUTDIR="$(fixcopy g4-e6)"; assert_fixture_dir "$MUTDIR"
mkdir -p "$MUTDIR/tree/.github/actions/appkey-mint" || { printf 'FAIL SETUP: g4-e6 mkdir\n' >&2; exit 1; }
cat > "$MUTDIR/tree/.github/actions/appkey-mint/action.yml" <<'YAML'
name: fixture app key composite
runs:
  using: composite
  steps:
    - shell: bash
      run: |
        PEM=$(doppler secrets get GITHUB_APP_PRIVATE_KEY --plain -p soleur -c prd_terraform)
        if [[ "$PEM" == EVICTED_SEE_ADR_241 ]]; then
          echo "::error::verdict=legacy_app_key_evicted the key was evicted"
          exit 1
        fi
YAML
if fixture_written g4-e6-composite "$MUTDIR/tree/.github/actions/appkey-mint/action.yml" \
   && mutate g4-e6-composite-from-tier-b "$MUTDIR/tree/.github/workflows/appkey.yml" 4 \
        's/^          PEM=\$\(doppler secrets get GITHUB_APP_PRIVATE_KEY.*$/          PEM=unused/; /^    runs-on: ubuntu-24.04$/a\    environment: infra-privileged
/^    steps:$/a\      - uses: ./.github/actions/appkey-mint'; then
  fixcensus "$MUTDIR" "$T/mut/g4-e6.tsv" ""
  mutant_red g4-e6-composite-from-tier-b wf_row "$T/mut/g4-e6.tsv" "G4e:"
  g4e_cause g4-e6-composite-from-tier-b "$T/mut/g4-e6.tsv" "via workflows/appkey.yml::mint"
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
# Row 6 — ACCEPT arm of the intended-destroy allowance (#8714): the base declares a listed address,
# HEAD deletes it, and the apply still targets it bare. G4c must stay GREEN, or the allowance is
# unusable and the only way through is a `removed { destroy = false }` that leaves the value live.
MUTDIR="$(fixcopy g4-6)"; assert_fixture_dir "$MUTDIR"
if mutate g4-6-intended-destroy-base "$MUTDIR/base/apps/web-platform/infra/github-app.tf" 5 '$a\resource "doppler_secret" "ghcr_read_token" {\n  project = "soleur"\n  config  = "prd"\n  name    = "GHCR_READ_TOKEN"\n}' \
   && mutate g4-6-intended-destroy-target "$MUTDIR/tree/.github/workflows/tierb-apply.yml" 1 '/^              -target=doppler_secret\.github_app_private_key \\$/a\              -target=doppler_secret.ghcr_read_token \\'; then
  fixcensus "$MUTDIR" "$T/mut/g4-6.tsv" ""
  if wf_row "$T/mut/g4-6.tsv" "G4c:"; then pass "M-g4-6-intended-destroy-targeted: a listed, bare-targeted deletion is ACCEPTED by G4c"
  else fail "M-g4-6-intended-destroy-targeted: G4c refused a listed, bare-targeted deletion" "$(grep G4c "$T/mut/g4-6.tsv" | cut -c1-240)"; fi
fi
# Row 7 — the same listed deletion with NO `-target=` line: the delete is never planned, so G4c RED.
MUTDIR="$(fixcopy g4-7)"; assert_fixture_dir "$MUTDIR"
if mutate g4-7-intended-destroy-untargeted "$MUTDIR/base/apps/web-platform/infra/github-app.tf" 5 '$a\resource "doppler_secret" "ghcr_read_token" {\n  project = "soleur"\n  config  = "prd"\n  name    = "GHCR_READ_TOKEN"\n}'; then
  fixcensus "$MUTDIR" "$T/mut/g4-7.tsv" ""
  mutant_red g4-7-intended-destroy-untargeted wf_row "$T/mut/g4-7.tsv" "G4c:"
fi

# ── Guard 6 (#8609): the soleur-github-app read token stays in Tier B ───────────────────
# Row a — REORDER: after the compliant Tier-B job, a SECOND job with no `environment:` reads the
# token. The scan must not stop at the first (compliant) referencing job.
MUTDIR="$(fixcopy g6a)"; assert_fixture_dir "$MUTDIR"
if mutate g6a-second-job-no-environment "$MUTDIR/tree/.github/workflows/tierb-apply.yml" 6 '$a\  leak:\n    runs-on: ubuntu-24.04\n    steps:\n      - run: echo "$T" > /dev/null\n        env:\n          T: ${{ env.TF_VAR_github_app_runtime_doppler_token }}'; then
  fixcensus "$MUTDIR" "$T/mut/g6a.tsv" ""
  mutant_red g6a-second-job-no-environment wf_row "$T/mut/g6a.tsv" "G6a:"
fi
# Row a, second arm — a Tier-B environment on a `pull_request` workflow: the environment
# check alone would pass it, and a pull request is exactly a branch.
MUTDIR="$(fixcopy g6a-pr)"; assert_fixture_dir "$MUTDIR"
printf 'name: zz\non: pull_request\njobs:\n  a:\n    runs-on: ubuntu-24.04\n    environment: infra-privileged\n    steps:\n      - run: echo x\n        env:\n          T: ${{ env.TF_VAR_github_app_runtime_doppler_token }}\n' > "$MUTDIR/tree/.github/workflows/zz-g6pr.yml"
if fixture_written g6a-pull-request "$MUTDIR/tree/.github/workflows/zz-g6pr.yml"; then
  fixcensus "$MUTDIR" "$T/mut/g6a-pr.tsv" ""
  mutant_red g6a-pull-request wf_row "$T/mut/g6a-pr.tsv" "G6a:"
fi
# Row a2 — a Tier-A job runs `bash scripts/x.sh`, and the SCRIPT names the token.
MUTDIR="$(fixcopy g6a2)"; assert_fixture_dir "$MUTDIR"
printf '#!/usr/bin/env bash\necho "${GITHUB_APP_RUNTIME_DOPPLER_TOKEN:-}" > /dev/null\n' > "$MUTDIR/tree/scripts/g6-leak.sh"
if fixture_written g6a2-script-names-token "$MUTDIR/tree/scripts/g6-leak.sh" \
   && mutate g6a2-tier-a-runs-it "$MUTDIR/tree/.github/workflows/tiera.yml" 1 '$a\          bash scripts/g6-leak.sh'; then
  fixcensus "$MUTDIR" "$T/mut/g6a2.tsv" ""
  mutant_red g6a2-script-indirection wf_row "$T/mut/g6a2.tsv" "G6a2:"
fi
# Row a3 — a Tier-B job exports the token as a job output; a Tier-A job reads it via needs.
# The output name carries no token name, so G6a alone cannot see the flow.
MUTDIR="$(fixcopy g6a3)"; assert_fixture_dir "$MUTDIR"
printf 'name: zz\non:\n  push:\n    branches: [main]\njobs:\n  mint:\n    runs-on: ubuntu-24.04\n    environment: infra-privileged\n    outputs:\n      blob: ${{ steps.s.outputs.v }}\n    steps:\n      - id: s\n        run: echo "v=$TF_VAR_github_app_runtime_doppler_token" >> "$GITHUB_OUTPUT"\n  use:\n    runs-on: ubuntu-24.04\n    needs: mint\n    steps:\n      - run: echo "${{ needs.mint.outputs.blob }}" > /dev/null\n' > "$MUTDIR/tree/.github/workflows/zz-g6out.yml"
if fixture_written g6a3-outputs-flow "$MUTDIR/tree/.github/workflows/zz-g6out.yml"; then
  fixcensus "$MUTDIR" "$T/mut/g6a3.tsv" ""
  mutant_red g6a3-outputs-flow wf_row "$T/mut/g6a3.tsv" "G6a3:"
fi
# Row b — the token written into a `soleur` config, which every branch-reachable token reads.
MUTDIR="$(fixcopy g6b)"; assert_fixture_dir "$MUTDIR"
if mutate g6b-write-into-soleur "$MUTDIR/tree/.github/workflows/tierb-apply.yml" 1 '/^          bash scripts\/tierb-helper\.sh$/a\          printf %s "$V" | doppler secrets set GITHUB_APP_RUNTIME_DOPPLER_TOKEN -p soleur -c prd_terraform --silent >/dev/null'; then
  fixcensus "$MUTDIR" "$T/mut/g6b.tsv" ""
  mutant_red g6b-write-into-soleur wf_row "$T/mut/g6b.tsv" "G6b:"
fi
# Row c — four shapes that put the key, the token or a reader into Tier-A-readable state.
MUTDIR="$(fixcopy g6c-secret)"; assert_fixture_dir "$MUTDIR"
printf 'resource "doppler_secret" "leak" {\n  project = doppler_project.github_app_runtime.name\n  config  = "prd"\n  name    = "GITHUB_APP_PRIVATE_KEY"\n  value   = "x"\n}\n' > "$MUTDIR/tree/apps/web-platform/infra/zz-g6.tf"
if fixture_written g6c-secret-on-project "$MUTDIR/tree/apps/web-platform/infra/zz-g6.tf"; then
  fixcensus "$MUTDIR" "$T/mut/g6c-secret.tsv" ""
  mutant_red g6c-secret-on-project wf_row "$T/mut/g6c-secret.tsv" "G6c:"
fi
MUTDIR="$(fixcopy g6c-data)"; assert_fixture_dir "$MUTDIR"
printf 'data "doppler_secrets" "leak" {\n  project = "soleur-github-app"\n  config  = "prd"\n}\n' > "$MUTDIR/tree/apps/web-platform/infra/zz-g6.tf"
if fixture_written g6c-data-source "$MUTDIR/tree/apps/web-platform/infra/zz-g6.tf"; then
  fixcensus "$MUTDIR" "$T/mut/g6c-data.tsv" ""
  mutant_red g6c-data-source wf_row "$T/mut/g6c-data.tsv" "G6c:"
fi
# Through the LOCAL, not the variable: the render embeds the token, so taint must propagate.
MUTDIR="$(fixcopy g6c-output)"; assert_fixture_dir "$MUTDIR"
printf 'output "leak" {\n  value     = local.webhook_doppler_token_env\n  sensitive = true\n}\n' > "$MUTDIR/tree/apps/web-platform/infra/zz-g6.tf"
if fixture_written g6c-output-of-render "$MUTDIR/tree/apps/web-platform/infra/zz-g6.tf"; then
  fixcensus "$MUTDIR" "$T/mut/g6c-output.tsv" ""
  mutant_red g6c-output-of-render wf_row "$T/mut/g6c-output.tsv" "G6c:"
fi
MUTDIR="$(fixcopy g6c-ns)"; assert_fixture_dir "$MUTDIR"
if mutate g6c-nonsensitive-value "$MUTDIR/tree/apps/web-platform/infra/server.tf" 1 '/^  github_app_key_isolated = false$/a\  leak = nonsensitive(var.github_app_runtime_doppler_token)'; then
  fixcensus "$MUTDIR" "$T/mut/g6c-ns.tsv" ""
  mutant_red g6c-nonsensitive-value wf_row "$T/mut/g6c-ns.tsv" "G6c:"
fi
# Row c2 — terraform_data stores `input` and an unhashed `triggers_replace` in state verbatim.
MUTDIR="$(fixcopy g6c2-input)"; assert_fixture_dir "$MUTDIR"
if mutate g6c2-input "$MUTDIR/tree/apps/web-platform/infra/server.tf" 1 '/^resource "terraform_data" "deploy_pipeline_fix" \{$/a\  input = var.github_app_runtime_doppler_token'; then
  fixcensus "$MUTDIR" "$T/mut/g6c2-input.tsv" ""
  mutant_red g6c2-input wf_row "$T/mut/g6c2-input.tsv" "G6c2:"
fi
MUTDIR="$(fixcopy g6c2-trig)"; assert_fixture_dir "$MUTDIR"
# (The compliant trigger hashes the KEYLESS render, so the mutant also swaps in the delivered one:
# unhashing a trigger that never names the token stores nothing -- G6o covers the hashed form.)
if mutate g6c2-unhashed-trigger "$MUTDIR/tree/apps/web-platform/infra/server.tf" 4 's/^  triggers_replace = sha256\(join/  triggers_replace = (join/; s/^    local\.webhook_doppler_token_env_keyless,$/    local.webhook_doppler_token_env,/'; then
  fixcensus "$MUTDIR" "$T/mut/g6c2-trig.tsv" ""
  mutant_red g6c2-unhashed-trigger wf_row "$T/mut/g6c2-trig.tsv" "G6c2:"
fi
# Row d — a CI mint of a token on the project (R2 is the one mint, operator-run, into Tier B).
MUTDIR="$(fixcopy g6d)"; assert_fixture_dir "$MUTDIR"
if mutate g6d-token-mint "$MUTDIR/tree/.github/workflows/tierb-apply.yml" 1 '/^          bash scripts\/tierb-helper\.sh$/a\          doppler configs tokens create g6-leak -p soleur-github-app -c prd --plain > /dev/null'; then
  fixcensus "$MUTDIR" "$T/mut/g6d.tsv" ""
  mutant_red g6d-token-mint wf_row "$T/mut/g6d.tsv" "G6d:"
fi
# Row e — the saved plan (every variable in cleartext) as an artifact: as a SECOND path, and
# through a glob that covers it.
MUTDIR="$(fixcopy g6e)"; assert_fixture_dir "$MUTDIR"
if mutate g6e-tfplan-second-path "$MUTDIR/tree/.github/workflows/tierb-apply.yml" 6 '$a\      - uses: actions/upload-artifact@v4\n        with:\n          name: plans\n          path: |\n            plan.log\n            tfplan'; then
  fixcensus "$MUTDIR" "$T/mut/g6e.tsv" ""
  mutant_red g6e-tfplan-second-path wf_row "$T/mut/g6e.tsv" "G6e:"
fi
MUTDIR="$(fixcopy g6e-glob)"; assert_fixture_dir "$MUTDIR"
if mutate g6e-glob "$MUTDIR/tree/.github/workflows/tierb-apply.yml" 4 '$a\      - uses: actions/upload-artifact@v4\n        with:\n          name: everything\n          path: apps/web-platform/infra/**'; then
  fixcensus "$MUTDIR" "$T/mut/g6e-glob.tsv" ""
  mutant_red g6e-glob wf_row "$T/mut/g6e-glob.tsv" "G6e:"
fi
# Row m — TF_LOG on a Tier-B job.
MUTDIR="$(fixcopy g6m)"; assert_fixture_dir "$MUTDIR"
if mutate g6m-tf-log "$MUTDIR/tree/.github/workflows/tierb-apply.yml" 2 '/^    environment: infra-privileged$/a\    env:\n      TF_LOG: TRACE'; then
  fixcensus "$MUTDIR" "$T/mut/g6m.tsv" ""
  mutant_red g6m-tf-log wf_row "$T/mut/g6m.tsv" "G6m:"
fi
# Row n — a Doppler cross-project reference to the new project.
MUTDIR="$(fixcopy g6n)"; assert_fixture_dir "$MUTDIR"
if mutate g6n-cross-project-reference "$MUTDIR/tree/.github/workflows/tiera.yml" 1 '$a\          doppler secrets set K='"'"'${soleur-github-app.prd.GITHUB_APP_PRIVATE_KEY}'"'"' -p soleur -c prd_terraform --silent >/dev/null'; then
  fixcensus "$MUTDIR" "$T/mut/g6n.tsv" ""
  mutant_red g6n-cross-project-reference wf_row "$T/mut/g6n.tsv" "G6n:"
fi
# Row l — the hcloud provider moved off the measured version without the census pin moving.
MUTDIR="$(fixcopy g6l)"; assert_fixture_dir "$MUTDIR"
if mutate g6l-provider-bump "$MUTDIR/tree/apps/web-platform/infra/.terraform.lock.hcl" 2 's/^  version     = "1\.63\.0"$/  version     = "1.64.0"/'; then
  fixcensus "$MUTDIR" "$T/mut/g6l.tsv" ""
  mutant_red g6l-provider-bump wf_row "$T/mut/g6l.tsv" "G6l:"
fi
# Row b, host spelling (test-design F9) — the same write under the name the HOST file uses. The
# pre-review G6_NAME matched only the CI spellings, so this stayed green.
MUTDIR="$(fixcopy g6b-host)"; assert_fixture_dir "$MUTDIR"
if mutate g6b-host-spelling "$MUTDIR/tree/.github/workflows/tiera.yml" 1 '$a\          printf %s "$V" | doppler secrets set GITHUB_APP_DOPPLER_TOKEN -p soleur -c prd --silent >/dev/null'; then
  fixcensus "$MUTDIR" "$T/mut/g6b-host.tsv" ""
  mutant_red g6b-host-spelling wf_row "$T/mut/g6b-host.tsv" "G6b:"
fi
# Row c, TWO hops (test-design F15) — a local of a local of the variable, then an output. A taint
# pass cut to one iteration taints the render but not this alias, and the row stays green.
MUTDIR="$(fixcopy g6c-2hop)"; assert_fixture_dir "$MUTDIR"
printf 'locals {\n  g6_hop = local.webhook_doppler_token_env\n}\noutput "leak" {\n  value     = local.g6_hop\n  sensitive = true\n}\n' > "$MUTDIR/tree/apps/web-platform/infra/zz-g6.tf"
if fixture_written g6c-two-hop-output "$MUTDIR/tree/apps/web-platform/infra/zz-g6.tf"; then
  fixcensus "$MUTDIR" "$T/mut/g6c-2hop.tsv" ""
  mutant_red g6c-two-hop-output wf_row "$T/mut/g6c-2hop.tsv" "G6c:"
fi
# Row o — the pre-review trigger: the DELIVERED render, hashed. G6c2 admits it (sha256-wrapped, so
# no token in state), but the value differs between the opted-in apply and every other plan.
MUTDIR="$(fixcopy g6o-render)"; assert_fixture_dir "$MUTDIR"
if mutate g6o-trigger-hashes-delivered-render "$MUTDIR/tree/apps/web-platform/infra/server.tf" 2 's/^    local\.webhook_doppler_token_env_keyless,$/    local.webhook_doppler_token_env,/'; then
  fixcensus "$MUTDIR" "$T/mut/g6o-render.tsv" ""
  mutant_red g6o-trigger-hashes-delivered-render wf_row "$T/mut/g6o-render.tsv" "G6o:"
  if wf_row "$T/mut/g6o-render.tsv" "G6c2:"; then
    pass "M-g6o-trigger-hashes-delivered-render: G6c2 stays green on it (so G6o is the only row that sees it)"
  else
    fail "M-g6o-trigger-hashes-delivered-render: G6c2 also red — the G6o row is not what this mutant measures"
  fi
fi
# Row o — the non-secret delivering flag is context-varying too.
MUTDIR="$(fixcopy g6o-flag)"; assert_fixture_dir "$MUTDIR"
if mutate g6o-trigger-reads-delivered-flag "$MUTDIR/tree/apps/web-platform/infra/server.tf" 1 '/^    local\.webhook_doppler_token_env_keyless,$/a\    tostring(var.github_app_runtime_token_delivered),'; then
  fixcensus "$MUTDIR" "$T/mut/g6o-flag.tsv" ""
  mutant_red g6o-trigger-reads-delivered-flag wf_row "$T/mut/g6o-flag.tsv" "G6o:"
fi
# Row o — the ignore_changes exemption is per attribute: drop user_data from it and the render
# plans a user_data change on every host in every non-opted-in plan.
MUTDIR="$(fixcopy g6o-ign)"; assert_fixture_dir "$MUTDIR"
if mutate g6o-ignore-changes-dropped "$MUTDIR/tree/apps/web-platform/infra/server.tf" 2 's/^    ignore_changes = \[user_data, ssh_keys\]$/    ignore_changes = [ssh_keys]/'; then
  fixcensus "$MUTDIR" "$T/mut/g6o-ign.tsv" ""
  mutant_red g6o-ignore-changes-dropped wf_row "$T/mut/g6o-ign.tsv" "G6o:"
fi
# Row q — the delivering job loses its opt-in (web-1 would render the line empty forever), and a
# fourth job gains one.
MUTDIR="$(fixcopy g6q-drop)"; assert_fixture_dir "$MUTDIR"
if mutate g6q-opt-in-dropped "$MUTDIR/tree/.github/workflows/tierb-apply.yml" 1 '/^          github-app-runtime-token: true$/d'; then
  fixcensus "$MUTDIR" "$T/mut/g6q-drop.tsv" ""
  mutant_red g6q-opt-in-dropped wf_row "$T/mut/g6q-drop.tsv" "G6q:"
fi
MUTDIR="$(fixcopy g6q-extra)"; assert_fixture_dir "$MUTDIR"
printf 'name: zz\non: workflow_dispatch\njobs:\n  extra:\n    runs-on: ubuntu-24.04\n    environment: infra-privileged\n    steps:\n      - uses: ./.github/actions/infra-credentials\n        with:\n          doppler-token-infra-privileged: ${{ secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED }}\n          github-app-runtime-token: true\n' > "$MUTDIR/tree/.github/workflows/zz-g6q.yml"
if fixture_written g6q-fourth-opt-in "$MUTDIR/tree/.github/workflows/zz-g6q.yml"; then
  fixcensus "$MUTDIR" "$T/mut/g6q-extra.tsv" ""
  mutant_red g6q-fourth-opt-in wf_row "$T/mut/g6q-extra.tsv" "G6q:"
fi
# Row s — the caller-ref pin dropped; the tag arm restored; the repository value resolved and wrong.
MUTDIR="$(fixcopy g6s-ref)"; assert_fixture_dir "$MUTDIR"
if mutate g6s-workflow-ref-flag-dropped "$MUTDIR/tree/apps/web-platform/infra/ci-deploy.sh" 1 '/--certificate-github-workflow-ref=/d'; then
  fixcensus "$MUTDIR" "$T/mut/g6s-ref.tsv" ""
  mutant_red g6s-workflow-ref-flag-dropped wf_row "$T/mut/g6s-ref.tsv" "G6s:"
fi
MUTDIR="$(fixcopy g6s-tag)"; assert_fixture_dir "$MUTDIR"
if mutate g6s-identity-tag-arm "$MUTDIR/tree/apps/web-platform/infra/ci-deploy.sh" 2 "s/@refs\\/heads\\/main\\$'\$/@(refs\\/heads\\/main|refs\\/tags\\/v[0-9].+)\$'/"; then
  fixcensus "$MUTDIR" "$T/mut/g6s-tag.tsv" ""
  mutant_red g6s-identity-tag-arm wf_row "$T/mut/g6s-tag.tsv" "G6s:"
fi
MUTDIR="$(fixcopy g6s-repo)"; assert_fixture_dir "$MUTDIR"
if mutate g6s-repository-value "$MUTDIR/tree/apps/web-platform/infra/ci-deploy.sh" 2 's/^readonly COSIGN_WORKFLOW_REPOSITORY="jikig-ai\/soleur"$/readonly COSIGN_WORKFLOW_REPOSITORY="jikig-ai\/soleur-fork"/'; then
  fixcensus "$MUTDIR" "$T/mut/g6s-repo.tsv" ""
  mutant_red g6s-repository-value wf_row "$T/mut/g6s-repo.tsv" "G6s:"
fi
# Row u — a credential-file loader without the unset.
MUTDIR="$(fixcopy g6u)"; assert_fixture_dir "$MUTDIR"
if mutate g6u-unset-dropped "$MUTDIR/tree/apps/web-platform/infra/10-vector-doppler-token.conf" 1 '/^UnsetEnvironment=/d'; then
  fixcensus "$MUTDIR" "$T/mut/g6u.tsv" ""
  mutant_red g6u-unset-dropped wf_row "$T/mut/g6u.tsv" "G6u:"
fi
# Row p — MUST-PASS: the delivering Tier-B job with its steps reordered from the canonical (the
# two steps after the loader swapped, the opt-in key first). A census keyed on step position
# or on key order would red a correct job here.
MUTDIR="$(fixcopy g6p)"; assert_fixture_dir "$MUTDIR"
python3 - "$MUTDIR/tree/.github/workflows/tierb-apply.yml" <<'PYMUT'
import sys, re
p = sys.argv[1]
t = open(p).read()
ex = re.search(r"      - name: Extract backend credentials\n(?:        .*\n)+", t).group(0)
tf = re.search(r"      - name: Terraform apply\n(?:        .*\n)+", t).group(0)
t = t.replace(ex + tf, tf + ex)
t = t.replace("          doppler-token-infra-privileged: ${{ secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED }}\n          github-app-runtime-token: true\n",
              "          github-app-runtime-token: true\n          doppler-token-infra-privileged: ${{ secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED }}\n")
open(p, "w").write(t)
PYMUT
if ! diff -q "$FIX/tree/.github/workflows/tierb-apply.yml" "$MUTDIR/tree/.github/workflows/tierb-apply.yml" >/dev/null 2>&1; then
  MUTANTS_RUN=$((MUTANTS_RUN + 1))
  pass "M-g6p-reordered: the delivering job's steps and loader keys reordered (md5 $(md5sum < "$MUTDIR/tree/.github/workflows/tierb-apply.yml" | cut -c1-8))"
  fixcensus "$MUTDIR" "$T/mut/g6p.tsv" ""
  if awk -F'\t' 'index($2, "G6") == 1 { n++; if ($1 != "ok") bad = 1 } END { exit (n >= 15 && !bad) ? 0 : 1 }' "$T/mut/g6p.tsv"; then
    pass "M-g6p-reordered: every G6 row stays GREEN on a correct job in a non-canonical order"
  else
    fail "M-g6p-reordered: a G6 row reds a compliant reordered job" "$(awk -F'\t' 'index($2, "G6") == 1 && $1 != "ok"' "$T/mut/g6p.tsv" | cut -c1-240)"
  fi
else
  fail "M-g6p-reordered: the reorder did not land"
fi
# G6h2 — PRESENCE of every named G6 row (a count floor cannot tell a renamed or dropped row from
# a duplicated one). Positive on the live and control TSVs, negative on a control with one removed.
G6_ROW_IDS="G6a G6a2 G6a3 G6b G6c G6c2 G6d G6e G6m G6n G6l G6o G6q G6s G6u"
g6_present() { local id; for id in $G6_ROW_IDS; do awk -F'\t' -v p="$id: " 'index($2, p) == 1 { f = 1 } END { exit f ? 0 : 1 }' "$1" || return 1; done; }
if g6_present "$T/live.tsv" && g6_present "$T/control.tsv"; then
  pass "G6h2: every named G6 row id ($G6_ROW_IDS) is present in the live and the control census"
else
  fail "G6h2: a named G6 row id is missing from the live or the control census"
fi
grep -v "$(printf '\tG6n: ')" "$T/control.tsv" > "$T/mut/g6h2.tsv"
if [ "$(grep -c . "$T/mut/g6h2.tsv")" -eq "$(( $(grep -c . "$T/control.tsv") - 1 ))" ]; then
  MUTANTS_RUN=$((MUTANTS_RUN + 1)); pass "M-g6h2-row-missing: exactly one G6 row (G6n) removed from a copy of the control TSV"
  mutant_red g6h2-row-missing g6_present "$T/mut/g6h2.tsv"
else
  fail "M-g6h2-row-missing: the removal did not land on exactly one line"
fi
}

# ── FLOOR + LEDGER (ADR-193: printf + exit, never through pass()/fail()) ─────────────
# 26 -> 27 (review W1): M-g1-10-destroy-only-no-environment.
# 27 -> 30 (#8714): M-g4-6 (two landings) and M-g4-7, the intended-destroy allowance rows.
# 30 -> 32 (#9215): M-g1-i3 and M-g1-i4, the root-key extract-precedence mutants (drop + reorder).
# 32 -> 52 (#8609): Guard 6 — 19 fixture landings (g6a..g6l, g6p) + the g6h2 TSV truncation.
# 52 -> 53 (merge with #6604 step 7): M-g1-11, which main added without raising this floor.
# 53 -> 64 (#8609 review): g6b-host, g6c-2hop, g6o x3, g6q x2, g6s x3, g6u (11 landings).
# 64 -> 74 (#9360): G4e rows e3, e3b, e3c, e4, e4m, e4x, e4c, e5, e6 (+ e6's composite fixture).
# EXACT, split into a `-lt` floor and a `-gt` ceiling (no slack). The ceiling replaces the nested
# G6h self-run (review: simplicity P2, patterns P3-4): with equality enforced here, deleting ANY
# mutant trips this line by construction, not only the one G6h deleted; and a mutant added without
# raising the number names its real cause instead of reding G6h.
MUTANT_FLOOR=74
if [ "$MUTANTS_RUN" -lt "$MUTANT_FLOOR" ]; then
  printf 'FAIL MUTANT FLOOR: only %s mutants executed, floor is %s — a matrix row did not land or was deleted.\n' "$MUTANTS_RUN" "$MUTANT_FLOOR" >&2
  exit 1
fi
if [ "$MUTANTS_RUN" -gt "$MUTANT_FLOOR" ]; then
  printf 'FAIL MUTANT FLOOR: %s mutants executed but MUTANT_FLOOR is %s — it is exact; raise it to %s.\n' "$MUTANTS_RUN" "$MUTANT_FLOOR" "$MUTANTS_RUN" >&2
  exit 1
fi
# Assertion FLOOR: live census 16 + harness 7 + mutants 17 x 2 = 57 (exact).
_ran=$((passes + fails))
# 80 -> 82 (review W1): M-g1-10's fixture-written row and its RED row. Measured: 82 ran.
# 82 -> 88 (#8714): live G4f, and M-g4-6/M-g4-7 (3 landings + 2 verdicts). Measured: 88 ran.
# 88 -> 93 (#9215): live G1i-rk, and M-g1-i3/M-g1-i4 (2 landings + 2 verdicts). Measured: 93 ran.
# 93 -> 95 (#6604 step 7): M-g1-11, the state-rm-only writer (1 landing + 1 verdict). Measured: 95 ran.
# 95 -> 150 (#8609): live G6a..G6l (11), G6g/G6g2 (2), 20 G6 landings + 18 G6 verdicts + G6p's
# must-pass (1), G6h2 presence (1), G6h (2). Measured: 150 ran.
# 150 -> 175 (#8609 review): live G6o/G6q/G6s/G6u (4), 11 landings + 11 verdicts, the g6o-render
# G6c2-stays-green control (1), minus the deleted G6h (2). Measured: 175 ran.
# 175 -> 205 (#9360): nine G4e rows x (landing + verdict + cause) = 27, e6's composite
# fixture (1), and the cause checks added to e1/e2 (2). Measured: 205 ran.
FLOOR=205
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
