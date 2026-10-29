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
#            outside the loader) and AC7b (the state-bucket writers are Tier B, their backend
#            credentials come from `TF_STATE_AWS_*` first, and every local `.sh` state-writer
#            sources its ambient `AWS_*` pair from a Tier-B name too — limb 3, G1k, #10990).
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
# `apps/*/infra` and `infra/` for the environment and backend models, plus every `*.sh` under the
# repo root for the local state-writer limb (AC7b limb 3 — the same filesystem-walk convention).
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
# ref whose `*.tf` are the base for the deleted-resource-block row; default the merge-base of
# HEAD and refs/remotes/origin/main — the tree the diff under test actually diverged from —
# falling back to the refs/remotes/origin/main tip when no merge base resolves).
#
# Run: bash tests/scripts/test-infra-privileged-tier-census.sh

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
GHDIR="${IPT_GITHUB_DIR:-$ROOT/.github}"
REPODIR="${IPT_REPO_ROOT:-$ROOT}"
STATE_LIST="${IPT_STATE_LIST:-}"

# resolve_base_ref <repodir> — the ref whose `*.tf` are the G4c base. `IPT_BASE_REF` verbatim;
# else `git merge-base HEAD refs/remotes/origin/main` — the tree the diff under test actually
# diverged from, so a resource block added on main after the fork point is not attributed to
# the diff as a deletion (#9956: the tip diff reported the six egress blocks #9529 ADDED on
# main as orphans on a stale `pull/N/merge` checkout); else the refs/remotes/origin/main tip,
# the pre-#9956 semantics, when no merge base resolves (no origin/main, shallow clone, orphan
# branch). The `env -u` scrub is the repo convention for git calls in hook-reachable code
# (scripts/test-all.sh › _aff_rd_diff) — an inherited GIT_DIR/GIT_INDEX_FILE overrides `git -C`
# and would resolve the merge-base against the caller's repository.
# The resolution contract: `IPT_BASE_REF` verbatim; else `git merge-base HEAD
# refs/remotes/origin/main`; else the refs/remotes/origin/main tip. Prints the chosen ref on
# stdout and names the arm on stderr via IPT_G4C_BASE_ARM=<override|merge-base|fallback> — the
# silent-fallback arm silently restored the #9956 false-red class, so it must be observable.
# `assert_fixture_dir` is defined below and resolved at call time.
resolve_base_ref() {
  local _mb="" _rs
  # `git -C ""` widens to the CALLER's repository — an empty operand here would resolve the
  # merge-base against the wrong repo and materialize a plausible-looking base from it.
  assert_fixture_dir "${1-}"
  if [ -n "${IPT_BASE_REF:-}" ]; then
    # The ref string is scrubbed before hitting a log line — it is operator-controlled and
    # could otherwise splice a forged `FAIL <row>` into the merged suite stream a sibling
    # suite greps. [[:cntrl:]] is load-bearing: $'\x00' cannot embed a NUL in a bash word, so
    # a $'\x00-\x1f\x7f' class expands empty and scrubs nothing (measured).
    _rs="${IPT_BASE_REF//[[:cntrl:]$'\u2028\u2029']/?}"
    printf 'IPT_G4C_BASE_ARM=override ref=%s\n' "$_rs" >&2
    printf '%s' "$IPT_BASE_REF"
    return 0
  fi
  # The full ref name: a `refs/heads/origin/main` or tag can shadow the remote-tracking ref in
  # the DWIM order and rebind every operand below to a different commit. merge-base without
  # --all prints ONE best common ancestor; on criss-cross histories a different best exists —
  # accepted residual (a linear PR history is the norm in this repo).
  _mb="$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE \
    git -C "$1" merge-base HEAD refs/remotes/origin/main 2>/dev/null)" || _mb=""
  if [ -n "$_mb" ]; then
    printf 'IPT_G4C_BASE_ARM=merge-base ref=%s\n' "$_mb" >&2
    printf '%s' "$_mb"
  else
    # Tip fallback restores pre-#9956 semantics — the failure direction is a false RED on
    # post-fork main-side additions, never a hidden green, and the marker makes it visible.
    printf 'IPT_G4C_BASE_ARM=fallback ref=refs/remotes/origin/main\n' >&2
    printf '%s' "refs/remotes/origin/main"
  fi
}

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

# (#9956) THE FIXTURE GIT ENVIRONMENT, sourced BEFORE any fixture is created. The G4c base legs
# below build this suite's first `git init` fixture (a synthetic repo exercising the production
# resolve_base_ref/materialize_base_dir path), so this file MUST go through the #7849 chokepoint:
# sourcing it ARMS the tripwire that refuses an inherited GIT_DIR — in a linked worktree git
# exports GIT_DIR/GIT_INDEX_FILE to every hook as absolute paths, and they override `git -C`, so
# an un-scrubbed `git init` would initialise nothing and its commits would land on the caller's
# live branch (#7833). `git_fixture_env` then exports the ceiling ($T's parent), a synthesized
# identity, and config hermeticity into THIS shell, so every `git -C` fixture call is contained.
# The suite's own `git -C "$REPODIR"` reads are unaffected: REPODIR is itself the repo root, so
# discovery finds its .git without ever climbing to the ceiling.
# shellcheck source=../../plugins/soleur/test/lib/git-fixture-env.sh
source "${ROOT}/plugins/soleur/test/lib/git-fixture-env.sh" \
  || { printf 'FAIL SETUP: could not source the fixture git environment\n' >&2; exit 1; }

T="$(mktemp -d "${TMPDIR}/infra-privileged-tier-census.XXXXXX")" || { printf 'FAIL SETUP: mktemp\n' >&2; exit 1; }
_REACHED_VERDICT=""; _rc=0
trap '_rc=$?; rm -rf "$T"; if [ "$_rc" -eq 0 ] && [ -z "$_REACHED_VERDICT" ]; then printf "FAIL: suite exited 0 before its verdict\n" >&2; exit 1; fi' EXIT
assert_fixture_dir "$T"
git_fixture_env "$T" || { printf 'FAIL SETUP: git_fixture_env refused the fixture root %s\n' "$T" >&2; exit 1; }
mkdir -p "$T/mut" || { printf 'FAIL SETUP: mkdir %s/mut\n' "$T" >&2; exit 1; }

printf '\n=== infra-privileged tier census (Guards 1, 2 and 4; #8209, ADR-241) ===\n\n'

cat > "$T/ipt.py" <<'PY'
import sys, os, re, json, yaml, subprocess, glob, posixpath, tempfile

GHDIR, REPO = sys.argv[1], sys.argv[2]
STATE_LIST = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] else ""
BASE_ROOT = sys.argv[4] if len(sys.argv) > 4 and sys.argv[4] else ""
CHECK_GIT = (os.path.abspath(GHDIR) == os.path.abspath(os.path.join(REPO, ".github"))
             and os.path.exists(os.path.join(REPO, ".git")))

# ── constants (plan Phase 1 item 1) ────────────────────────────────────────────────
ENV_SECRETS = ["DOPPLER_TOKEN_INFRA_PRIVILEGED", "DOPPLER_TOKEN_WRITE", "DOPPLER_TOKEN_GIT_DATA_ROOT", "DOPPLER_TOKEN_INFRA_APP"]
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
        # (#9755) `==`/`!=` comparison operands are predicate literals, never environment names
        # the value can resolve to: `inputs.op == 'backup'` names an OP, `github.ref ==
        # 'refs/heads/main'` names a REF. The cutover job's environment ternary carries one such
        # comparison per gated op; reading them as arms would red G1c/G1j on 'arm', 'backup', ...
        # which are not environments. Strip each comparison's quoted operand on either side
        # before collecting RESULT literals — a result literal (the `&&`/`||` side) is still an
        # arm, which is what g1-2 pins.
        s = re.sub(r"'[^']*'\s*(?:==|!=)", "", s)
        s = re.sub(r'"[^"]*"\s*(?:==|!=)', "", s)
        s = re.sub(r"(?:==|!=)\s*'[^']*'", "", s)
        s = re.sub(r'(?:==|!=)\s*"[^"]*"', "", s)
        # The `|| ''` / `|| ""` false arm needs no extra collection: the findall below already
        # captures the empty quoted literal (the earlier `\|\|\s*''` append only duplicated it).
        # Residual blind spots, named with the direction EACH fails — an earlier version of
        # this comment claimed all of them fail LOUD, and it was wrong in both directions:
        #   * a FUNCTION predicate keeps its argument literal as a collected arm — and when
        #     that literal is IN the set it fails GREEN: `contains(x, 'inngest-cutover')` reads
        #     as an in-set arm while binding nothing as an environment name (only an
        #     out-of-set function literal still reds G1c — the in-set case blinds);
        #   * `cond && 'env'` with NO `||` arm yields a single in-set literal and fails GREEN
        #     the same way, even though a falsy `cond` resolves to NO environment on that
        #     dispatch — an unbound dispatch the `''`-arm clauses below cannot see either;
        #   * `'a' == 'b'` strips 'a' but leaves 'b' collectible — that one DOES surface as a
        #     NON-TIER-B arm, never a missed gate.
        arms = re.findall(r"'([^']*)'", s) + re.findall(r'"([^"]*)"', s)
        # An expression yielding NO quoted literal is UNPARSEABLE, not an empty arm: the `[""]`
        # fallback used to land here, and G1c's `''` exemption would read a fully-dynamic or
        # literal-free `environment:` GREEN where the pre-#9755 code went red. The sentinel is
        # outside TIER_B_ENVIRONMENTS, so it stays red wherever arms are membership-checked —
        # G1c owns the red, and G1h/G1j/G6a refuse it through their own `all(a in
        # TIER_B_ENVIRONMENTS)` gates (G1d deliberately EXCLUDES it from the declared set —
        # demanding a deployment policy for a sentinel would only duplicate the red);
        # arms_maybe_tier_b maps it onto `''`, the refusing direction for ITS ban.
        return arms if arms else ["__UNPARSEABLE__"]
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
# #6604 step 7 widened it to `state rm|mv|push`: the single-use workspaces-plaintext-forget.yml (retired in
# #6604 PR B) wrote this state with `terraform state rm` and no apply at all, which must classify exactly
# like an apply (G1h). The widening stays for any future state-write-only job.
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
    anchored at line start, optional indentation allowed for the removed/moved openers). Returns (match, body)."""
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
# `removed`/`moved` may be INDENTED (HCL ignores indentation), so the openers allow leading blanks; the scan runs on
# hcl_code_only(text) so a `removed {` inside a comment or a heredoc body is not a block.
REMOVED_OPEN = re.compile(r'^[ \t]*removed\s*\{', re.M)
MOVED_OPEN = re.compile(r'^[ \t]*moved\s*\{', re.M)
_HCL_HEREDOC = re.compile(r"<<-?[ \t]*([A-Za-z_][A-Za-z0-9_]*)[ \t]*\r?$", re.M)
def hcl_code_only(text):
    """`text` with every `#` / `//` comment, `/* */` comment and heredoc body overwritten by spaces (newlines kept, so
    offsets and line starts are unchanged). Quoted strings are tracked (a `//` inside "https://x" is not a comment);
    HCL strings never span lines, so a newline closes one. FAIL-OPEN direction, stated plainly: an unterminated
    heredoc or block comment blanks to end of file, and hiding a `removed`/`moved` block turns G4h green. Two things
    bound that: terraform rejects an unterminated heredoc or comment, so such a file cannot reach apply; and G4h4 pins
    the LIVE removed/moved counts to the unscrubbed count, so a real block blanked on a real file reds it. The G4h
    probe strings below only cover the shapes written into them, not an arbitrary real file."""
    out, i, n, in_str = [], 0, len(text), False
    blank = lambda seg: re.sub(r"[^\n]", " ", seg)
    while i < n:
        c = text[i]
        if in_str:
            if c == "\\" and i + 1 < n:
                out.append(text[i:i + 2]); i += 2; continue
            if c in '"\n':
                in_str = False
            out.append(c); i += 1; continue
        if c == '"':
            in_str = True; out.append(c); i += 1; continue
        if c == "#" or text.startswith("//", i):
            j = text.find("\n", i); j = n if j < 0 else j
            out.append(blank(text[i:j])); i = j; continue
        if text.startswith("/*", i):
            j = text.find("*/", i + 2); j = n if j < 0 else j + 2
            out.append(blank(text[i:j])); i = j; continue
        hm = _HCL_HEREDOC.match(text, i) if text.startswith("<<", i) else None
        if hm:
            em = re.compile(r"^[ \t]*" + re.escape(hm.group(1)) + r"[ \t]*\r?$", re.M).search(text, hm.end())
            k = em.end() if em else n
            out.append(text[i:hm.end()]); out.append(blank(text[hm.end():k])); i = k; continue
        out.append(c); i += 1
    return "".join(out)
def read_tf(path):
    """The ONE reader of a `.tf` file for Guard 4: the file's text with comments and heredoc bodies blanked
    (hcl_code_only). Every Guard 4 reader (the removed/moved collectors, declared_addrs, base_declared) goes through
    it, so a resource wrapped in a comment is not "declared" and a `removed {` in a comment is not a block."""
    return hcl_code_only(open(path, encoding="utf-8", errors="replace").read())
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

# (#9755) An EMPTY arm (`|| ''` / `|| ""`) is a resolvable outcome but not an environment NAME:
# it binds no environment, so no ENV-scoped secret resolves on it — a Tier-B job that lands on
# it gets empty environment inputs. REPO-scoped secrets still resolve on that dispatch, so `''`
# is safe ONLY because every path that could still deliver privileged credentials on the
# unbound dispatch is separately banned: a prd_terraform read of a tier_b_names entry (G1g), a
# state write against the privileged bucket (G1h), a loader call carrying a
# `doppler-token-legacy` fallback (the first G1j `''`-arm clause), and an unconditional
# step-level or job-level reference to the repo-scoped privileged names DOPPLER_TOKEN_WRITE /
# DOPPLER_TOKEN_GIT_DATA_ROOT / DOPPLER_TOKEN_INNGEST_ARM (the sibling clauses). The bad arms
# this row collects are the NON-EMPTY
# result literals outside the set — comparison operands have already been stripped by
# env_arms. G1h and G6a keep `all(a in TIER_B_ENVIRONMENTS)` with NO `''` exemption —
# intentional divergence: a state writer or a read-token job stays red on an unbound `''`
# dispatch, where a loader job's `''` is instead policed by the G1j clauses.
bad_arm = sorted({"%s -> %r" % (j.id, a) for j in tierb if j.arms for a in j.arms if a and a not in TIER_B_ENVIRONMENTS})
check("G1c: every non-empty arm of every Tier-B job's `environment:` is in tier_b_environments "
      "(scalar, mapping and ${{ }} forms; ${{ }} ==/!= predicate operands are not environment "
      "names; an empty `||` arm resolves to no environment — env-scoped secrets are unreachable "
      "on it, and the repo-scoped paths that still resolve are banned by G1g/G1h and the "
      "G1j `''`-arm clauses)", not bad_arm, bad_arm[:8])

# __UNPARSEABLE__ is a sentinel, not a declared environment — G1c owns it; demanding a
# deployment policy for it here would only duplicate the red under a second row.
declared = {a for j in tierb if j.arms for a in j.arms if a and a != "__UNPARSEABLE__"}
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
# (#9927 item 8b) THERE IS NO SANCTIONED READ ANY MORE. This row used to carry a read-only-first
# ALLOWANCE (`RO_FIRST`): a Tier-A job could read `HCLOUD_TOKEN` as the second arm of a
# `HCLOUD_TOKEN_READONLY`-first read in the same step, a before-state fallback that lasted until
# operator step O5/O10. Both are done (measured 2026-10-20: the read-only name is listed in
# prd_terraform, the read/write name is gone), so the allowance has no live member left: its
# only user, the workspaces-luks-cutover volume lookup, now reads the read-only name alone. A
# read-only reader that can fall back to the destroy-capable token silently stops being
# read-only the moment the read-only secret goes missing, so the allowance is deleted rather
# than kept "for later": any read of a tier_b_names entry from prd_terraform outside the
# loader is RED, whichever name it reads first.
#
# The config can be named TWO ways, and both are the same read. `-c prd_terraform` on the
# command line, or a step (or job, or workflow) `env:` that sets `DOPPLER_CONFIG: prd_terraform`
# and lets `doppler` pick it up. The second form is how the infra-validation PR-plan step reads
# its Hetzner value, and the command-line-only form never saw it.
def _cfg_env_is_prd_terraform(j, st):
    for env in (st.get("env"), j.body.get("env"), (docs[j.rel][0].get("env") if isinstance(docs[j.rel][0], dict) else None)):
        if isinstance(env, dict) and str(env.get("DOPPLER_CONFIG", "")).strip() == "prd_terraform":
            return True
    return False

for rel, (doc, text) in sorted(docs.items()):
    if rel == LOADER_REL:
        continue
    for j in [x for x in jobs if x.rel == rel]:
        for st in j.steps:
            body = str(st.get("run") or "")
            cfg_env = _cfg_env_is_prd_terraform(j, st)
            for line, m in cmd_sites(body, DOPPLER_SECRETS_GET):
                name = m.group(1)
                if name not in TIER_B_NAMES:
                    continue
                if not (PRD_TF.search(line[m.end():]) or cfg_env):
                    continue
                ac3.append("%s [%s]" % (j.id, name))
check("G1g: no workflow step reads a tier_b_names entry from `prd_terraform` (`-c prd_terraform` or a "
      "DOPPLER_CONFIG env) outside the loader (%s), and there is no read-only-first allowance [AC3, #9927 8b]"
      % os.path.join(".github", LOADER_REL), not ac3, sorted(set(ac3))[:8])

# (#9927 item 8b) G1j -- the CALLER INVARIANT that replaces the committed caller-audit file. Every
# job that calls the loader declares a Tier-B `environment:`, so it takes the Tier-B arm on main and
# cannot be in the loader's legacy arm. The legacy arm no longer exports a Hetzner token at all, so a
# loader job without the environment would silently lose it; this row is what makes that a RED in
# review instead of a surprise in an incident. The count is cross-checked against an independent raw
# scan of the same files (a `uses:` line, comments excluded by the anchor), so a parse that drops a
# workflow cannot shrink the population quietly, and a tree with ZERO loader jobs is a RED, not a
# vacuous green.
G1J_USES = re.compile(r"^[ \t]*-?[ \t]*uses:[ \t]*\./\.github/actions/infra-credentials/?[ \t]*(?:#.*)?$", re.M)
# (#9755 review, fix round 2) REPO-scoped privileged names resolve on EVERY dispatch —
# including the unbound `|| ''` one that binds no environment, where ENV-scoped secrets are
# unreachable but these three are not. The name set: DOPPLER_TOKEN_WRITE and
# DOPPLER_TOKEN_GIT_DATA_ROOT, plus DOPPLER_TOKEN_INNGEST_ARM — a third repo-scoped read/write
# Doppler token (github_actions_secret, inngest-arm-write-token.tf). Case-insensitive: the
# secrets context resolves `secrets.doppler_token_write` as happily as the canonical spelling.
REPO_SCOPED_PRIV = re.compile(
    r"(?<![A-Za-z0-9_])(?:DOPPLER_TOKEN_WRITE|DOPPLER_TOKEN_GIT_DATA_ROOT|DOPPLER_TOKEN_INNGEST_ARM)(?![A-Za-z0-9_])",
    re.I)
g1j_jobs, g1j_bad = [], []
for j in jobs:
    lsteps = [st for st in j.steps
              if isinstance(st.get("uses"), str) and re.match(r"^\./\.github/actions/infra-credentials/?$", st["uses"].strip())]
    if lsteps:
        g1j_jobs.append(j.id)
        if not (j.has_env_key and j.arms and all(a == "" or a in TIER_B_ENVIRONMENTS for a in j.arms)):
            g1j_bad.append("%s -> %r" % (j.id, j.arms))
        # (#9755) The empty `||` arm is safe ONLY while the loader call carries no Tier-A
        # fallback: on an unbound dispatch the Tier-B input resolves empty and the loader fails
        # closed — unless a `doppler-token-legacy` is passed, in which case the legacy arm
        # supplies credentials UNGATED on that dispatch.
        elif "" in j.arms and any(str((st.get("with") or {}).get("doppler-token-legacy") or "") != ""
                                  for st in lsteps):
            g1j_bad.append("%s -> empty `||` arm while a doppler-token-legacy fallback is passed" % j.id)
    # (#9755 review, fix round 2) The sibling `''`-arm clause, for EVERY `''`-armed job (loader
    # or not — the exposure is the unbound dispatch, not the loader call): an UNCONDITIONAL
    # reference to a repo-scoped privileged name re-arms the ungated run, wherever it sits.
    #   STEP level — the WHOLE step dump, not only env:/with:: a `run:`-inline
    #     `${{ secrets.* }}` interpolates the same secret at step start, and a step `name:`
    #     carrying the token name is flagged with it (fail-loud either way). A step `if:`
    #     scopes its own reference to a condition this census cannot evaluate, so only the
    #     unconditional form is banned — the named blind spot stands (an `if:` that does not
    #     actually confine to a gated arm reads green).
    #   JOB level — the job's merged env: (j.env, the G6a jdump approach — a workflow-level
    #     env: reaches the job the same way) and a caller job's with:/secrets: blocks, where
    #     `secrets: inherit` hands EVERY repo secret — the privileged names included — to the
    #     reusable workflow. Job-level blocks carry NO `if:` exemption: a job `if:` can confine
    #     dispatches, but the live cutover job's own `if: github.event_name ==
    #     'workflow_dispatch'` shows it usually gates the EVENT, not the arm — the fail-loud
    #     direction wins, and the confined path that stays green is delivery through
    #     `if:`-gated steps.
    if j.arms and "" in j.arms:
        if any(not st.get("if") and REPO_SCOPED_PRIV.search(jdump(st)) for st in j.steps):
            g1j_bad.append("%s -> empty `||` arm while an unconditional step names a repo-scoped privileged secret" % j.id)
        if (REPO_SCOPED_PRIV.search(jdump({"env": j.env, "with": j.body.get("with"),
                                          "secrets": j.body.get("secrets")}))
                or str(j.body.get("secrets") or "").strip() == "inherit"):
            g1j_bad.append("%s -> empty `||` arm while job-level env:/with:/secrets: names a repo-scoped privileged secret (or inherits them all)" % j.id)
g1j_raw = sum(len(G1J_USES.findall(text)) for rel, (doc, text) in docs.items()
              if rel.startswith("workflows" + os.sep))
g1j_steps = sum(1 for j in jobs for st in j.steps
                if isinstance(st.get("uses"), str) and re.match(r"^\./\.github/actions/infra-credentials/?$", st["uses"].strip()))
check("G1j: every job that calls the infra-credentials loader declares a Tier-B `environment:` "
      "[%d loader jobs; %d loader steps; %d raw `uses:` lines; floor > 0 and steps == raw]"
      % (len(g1j_jobs), g1j_steps, g1j_raw),
      len(g1j_jobs) > 0 and g1j_steps == g1j_raw and not g1j_bad,
      "bad=%s jobs=%d steps=%d raw=%d" % (g1j_bad[:8], len(g1j_jobs), g1j_steps, g1j_raw))

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

# AC7b limb 3 — local .sh state-writers (#10990). The workflow limbs above cover terraform
# invoked from a `run:` step; bootstrap and rehearsal scripts invoke terraform OUTSIDE any
# workflow, so this limb walks every `.sh` under the repo root — a filesystem walk, fail closed,
# so an untracked script is censused too.
#
# A file is a STATE-WRITER when a `terraform` word on a code line is followed, inside its own
# command, by a write verb — `apply`, `import`, `taint`, `untaint`, `destroy`, `refresh`,
# `state push|mv|rm|replace-provider`, or `workspace new|delete`; a file whose only terraform
# verbs are plan/init/state pull is a read and exempt. `terraform` is matched wherever an argv
# word can sit — command position, the `doppler run --` target, or a wrapper's argument
# (`tf_env terraform apply`, the cla-evidence bootstrap's shape). Comments, heredoc bodies and
# echo/printf arguments are data, not invocations (the same carve-out as cmd_sites); every other
# quoting context counts — `sh -c 'terraform apply'` IS an invocation.
#
# Scope (the contract's stated limits, honestly): the limb asserts over writers carrying a
# Doppler leg that can supply the backend pair — a `doppler secrets get`/`export` naming a
# backend AWS name (the bare `AWS_*` pair or either Tier-B pair), a `doppler secrets download`
# resolving to `prd_terraform`, or a `doppler run` leg resolving to `prd_terraform` without
# `--name-transformer` (which env-injects the bare pair into the state-writing terraform it
# wraps). Out of scope, by construction: a writer sourcing `AWS_*` purely from caller env with
# no Doppler leg at all, and invocation indirection the literal-token classifier cannot see
# (`terraform "$@"`, `TF=terraform; $TF apply`) — both are residual windows the verb sets below
# cannot close. For each in-scope writer: BOTH ambient legs must come from a Tier-B name
# (`TF_STATE_AWS_*` or `GIT_DATA_ROOT_STATE_AWS_*` for each half — all-or-none: a half-set pair
# authenticates as nobody), and nothing may feed terraform the read-only `prd_terraform` `AWS_*`
# pair (`-c`/`--config` on the leg — in EITHER position — or a `DOPPLER_CONFIG` the file sets):
# that pair is read-only since O5b and 403s the apply's state PutObject mid-run.
#
# The population floor is the two known armed files, verbatim — both must land in the checked
# set on every tree this census runs on, so a "0 checked" run can never exit green.
SH_TF = re.compile(r"(?<![\w./-])terraform(?![\w-])")
# The write-verb set is the limb's WINDOW and must name every invocation that lands a PutObject
# on the state bucket: `destroy` is apply-shaped (the rehearsal workflows run it against a Tier-B
# root for exactly that reason), `untaint` un-marks in state, `refresh` writes refreshed state,
# and the `state`/`workspace` sub-verbs below each rewrite or replace a remote object. A verb left
# out is a `.sh` writer the census never sees — the guarded set must equal the property's set.
SH_WRITE_VERBS = {"apply", "import", "taint", "untaint", "destroy", "refresh"}
SH_STATE_WRITE_VERBS = {"push", "mv", "rm", "replace-provider"}
SH_WS_WRITE_VERBS = {"new", "delete"}  # `workspace select` writes only .terraform/environment — local
SH_BARE_AWS = re.compile(r"\bAWS_(?:ACCESS_KEY_ID|SECRET_ACCESS_KEY)\b")
# The two Tier-B pairs are TIER_B_NAMES members (the cross-pinned names): `TF_STATE_AWS_*` for the
# shared `soleur-terraform-state` roots, `GIT_DATA_ROOT_STATE_AWS_*` for the root-key root.
SH_TIERB_AWS = {"ACCESS_KEY_ID": ("TF_STATE_AWS_ACCESS_KEY_ID", "GIT_DATA_ROOT_STATE_AWS_ACCESS_KEY_ID"),
                "SECRET_ACCESS_KEY": ("TF_STATE_AWS_SECRET_ACCESS_KEY", "GIT_DATA_ROOT_STATE_AWS_SECRET_ACCESS_KEY")}
SH_GET = re.compile(r"doppler\s+(?:[^\s;|&)]+\s+)*?secrets\s+(?:get|export)\b")
SH_CFG_PRD = re.compile(r"\bDOPPLER_CONFIG\s*=\s*[\"']?prd_terraform\b")
# Reads of the pair that are NOT `secrets get`: a `doppler run` leg resolving to prd_terraform
# WITHOUT --name-transformer env-injects the bare pair into its child (a state-writing terraform
# wrapped in it gets the read-only pair with no get leg to find), and `doppler secrets download`
# of prd_terraform emits the whole config — the pair included.
SH_RUN = re.compile(r"doppler\s+run\b")
SH_DOWNLOAD = re.compile(r"doppler\s+(?:[^\s;|&)]+\s+)*?secrets\s+download\b")
SH_KNOWN_WRITERS = (os.path.join("apps", "cla-evidence", "infra", "bootstrap.sh"),
                    os.path.join("apps", "web-platform", "scripts", "bootstrap-live-verify.sh"))
SH_SKIP_DIRS = {".git", ".worktrees", ".terraform", "node_modules"}

def sh_code_lines(body):
    """Non-comment, non-heredoc-body lines of a shell script, continuations joined — the same
    line stream cmd_sites reads, WITHOUT the command-position filter: a state-writing terraform
    can also be an argv word (`tf_env terraform apply`, `doppler run -- terraform apply`)."""
    pending = None
    for line in CONT.sub(" ", body).split("\n"):
        if pending is not None:
            if line.strip() == pending:
                pending = None
            continue
        if line.lstrip().startswith("#"):
            continue
        h = HEREDOC_OPEN.search(line)
        yield line
        if h:
            pending = h.group(1)

def _sh_tf_write_after(text, end):
    """True when the words after a `terraform` token ending at `end` carry a state-write verb —
    a bare write verb, `state <write>`, or `workspace <new|delete>`."""
    words = [w.strip("\"'") for w in
             re.split(r"[;|&)]", text[end:], maxsplit=1)[0].split()]
    if any(w in SH_WRITE_VERBS for w in words):
        return True
    return any(words[i] in ("state", "workspace") and i + 1 < len(words)
               and words[i + 1] in (SH_STATE_WRITE_VERBS if words[i] == "state"
                                    else SH_WS_WRITE_VERBS)
               for i in range(len(words) - 1))


def sh_tf_write_text(text):
    """The write-verb check over a bare command segment (e.g. a `doppler run`'s `--` payload)."""
    return any(_sh_tf_write_after(text, m.end()) for m in SH_TF.finditer(text))


def sh_is_state_writer(body):
    for line in sh_code_lines(body):
        printing = PRINTS.match(line.lstrip()) is not None
        for m in SH_TF.finditer(line):
            # The echo/printf carve-out, same as cmd_sites: a quoted `terraform apply` in a print
            # argument is a string being printed, not a command being run.
            if printing and in_quotes(line, m.start()):
                continue
            if _sh_tf_write_after(line, m.end()):
                return True
    return False

sh_scanned, sh_writers, sh_scoped, sh_bad = 0, [], [], []
for dp, dn, fn in os.walk(REPO):
    dn[:] = [d for d in dn if d not in SH_SKIP_DIRS]
    for f in fn:
        if not f.endswith(".sh"):
            continue
        p = os.path.join(dp, f)
        sh_scanned += 1
        body = open(p, encoding="utf-8", errors="replace").read()
        if not sh_is_state_writer(body):
            continue
        rel = os.path.relpath(p, REPO)
        sh_writers.append(rel)
        cfg_prd = any(SH_CFG_PRD.search(cl) for cl in sh_code_lines(body))
        get_sites = list(cmd_sites(body, SH_GET))
        tails = [re.split(r"[;|&)]", line[m.end():], maxsplit=1)[0] for line, m in get_sites]
        aws_names = SH_TIERB_AWS["ACCESS_KEY_ID"] + SH_TIERB_AWS["SECRET_ACCESS_KEY"]

        def _prd_tf_resolve(seg):
            """A doppler leg's flag segment resolves to prd_terraform when its own -c/--config
            says so (BEFORE or AFTER the subcommand — the config flag can sit inside the SH_GET
            match itself, where a post-match tail never sees it) or, with no config flag at all,
            when the file's ambient DOPPLER_CONFIG is prd_terraform."""
            return bool(PRD_TF.search(seg)) or \
                (cfg_prd and not re.search(r"(?:-c|--config)[= ]\s*\S+", seg))

        # `doppler run` legs are judged per invocation: the flag segment is everything up to the
        # standalone `--` separator token, the wrapped payload after it. The split must key on
        # the WORD `--` — a substring partition finds the leading dashes of `--name-transformer`
        # or `--preserve-env` first and reads a transformed leg as transformer-less. Nested
        # loaders evaluate leg-by-leg — the outer leg's flags never decide the inner's risk.
        bad_run = bad_dl = False
        for line, m in cmd_sites(body, SH_RUN):
            seg = re.split(r"[;|&)]", line[m.end():], maxsplit=1)[0]
            msep = re.search(r"(?<!\S)--(?!\S)", seg)
            flags, wrapped = (seg[:msep.start()], seg[msep.end():]) if msep else (seg, "")
            if (msep and _prd_tf_resolve(flags) and "--name-transformer" not in flags
                    and sh_tf_write_text(wrapped)):
                bad_run = True
        for line, m in cmd_sites(body, SH_DOWNLOAD):
            if _prd_tf_resolve(re.split(r"[;|&)]", line[m.start():], maxsplit=1)[0]):
                bad_dl = True
        if not (any(SH_BARE_AWS.search(t) or any(n in t for n in aws_names) for t in tails)
                or bad_run or bad_dl):
            continue  # stated limit: AWS_* from caller env / a clean loader — out of scope
        sh_scoped.append(rel)
        for half, names in SH_TIERB_AWS.items():
            if not any(any(n in t for n in names) for t in tails):
                sh_bad.append("%s: no Tier-B leg for AWS_%s" % (rel, half))
        if bad_run:
            sh_bad.append("%s: `doppler run` resolving to prd_terraform without "
                          "--name-transformer env-injects the read-only AWS_* pair into a "
                          "state-writing terraform" % rel)
        if bad_dl:
            sh_bad.append("%s: `doppler secrets download` of prd_terraform emits the read-only "
                          "AWS_* pair wholesale" % rel)
        for (line, m), tail in zip(get_sites, tails):
            if (SH_BARE_AWS.search(tail)
                    and _prd_tf_resolve(re.split(r"[;|&)]", line[m.start():], maxsplit=1)[0])):
                sh_bad.append("%s: reads the read-only prd_terraform AWS_* pair" % rel)
sh_floor = [k for k in SH_KNOWN_WRITERS if k not in sh_scoped]
check("G1k: every `.sh` terraform state-writer that reads its backend AWS_* pair from Doppler "
      "sources BOTH legs from a Tier-B name (TF_STATE_AWS_* or GIT_DATA_ROOT_STATE_AWS_*), and "
      "none feeds terraform the read-only prd_terraform AWS_* pair — by `secrets get`/`export`, "
      "a `secrets download`, or a transformer-less `doppler run` leg [AC7b; %d .sh scanned, "
      "%d writers, %d checked]" % (sh_scanned, len(sh_writers), len(sh_scoped)),
      not sh_floor and not sh_bad,
      "floor_missing=%s bad=%s" % (sh_floor, sorted(set(sh_bad))[:8]))

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
# `moved` blocks get their OWN collector (G4h, #9879): `removed_blocks` also feeds G4a/G4b/G4c, which demand a `from`
# and `lifecycle { destroy = false }` of every entry, so a `moved` block put there would false-RED them.
moved_blocks = []
MOVED_ATTR = re.compile(r"(?:^|[\s{;])(from|to)\s*=\s*([A-Za-z0-9_.\[\]\"-]+)")
def moved_collect(text, rel, root):
    out = []
    for _m, b in block_bodies(text, MOVED_OPEN):
        attrs = {}
        for ln in b.splitlines():
            if ln.lstrip().startswith(("#", "//")):
                continue
            for k, v in MOVED_ATTR.findall(ln):
                attrs.setdefault(k, v)
        out.append((root, rel, attrs.get("from", ""), attrs.get("to", "")))
    return out
for r in GUARD4_ROOTS:
    for p in tf_files(r):
        g4_files += 1
        t = read_tf(p)
        for _m, b in block_bodies(t, REMOVED_OPEN):
            fr = re.search(r"^\s*from\s*=\s*([A-Za-z0-9_.\[\]\"-]+)\s*$", b, re.M)
            lif = [lb for _lm, lb in block_bodies(b, re.compile(r"^\s*lifecycle\s*\{", re.M))]
            guarded = any(re.search(r"^\s*destroy\s*=\s*false\s*$", lb, re.M) for lb in lif)
            removed_blocks.append((r, os.path.relpath(p, REPO), fr.group(1) if fr else "", guarded))
        moved_blocks.extend(moved_collect(t, os.path.relpath(p, REPO), r))
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

# EVERY `-target`/`-replace` operand in ANY step of ANY job (plan steps included). `root_targets` above reads only
# `terraform apply` bodies, but the dispatch jobs name their addresses on a `terraform plan -out=` step and apply the
# saved plan, so an apply-body scan is blind to them. RETIRED_STATE_ABSENT consults this broader set.
ANY_TARGET = re.compile(r"-(?:target|replace)(?:=|\s+)[\"']?([A-Za-z0-9_]+\.[A-Za-z0-9_]+)")
any_targeted = set()
for j in jobs:
    for s_ in j.steps:
        any_targeted.update(ANY_TARGET.findall(CONT.sub(" ", str(s_.get("run") or ""))))

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

def declared_in(text):
    """The `type.name` addresses of the resource blocks in `text` (already read through read_tf)."""
    return {"%s.%s" % (m.group(1), m.group(2)) for m, _b in block_bodies(text, RES_OPEN)}
# Reader probe (G4c): a real .tf FILE holding one resource inside a multi-line comment and one real resource must read
# as exactly the real one. It drives read_tf itself (a path in, not a text), so a reader that stops scrubbing reds it.
with tempfile.TemporaryDirectory() as _td:
    _tp = os.path.join(_td, "probe.tf")
    with open(_tp, "w", encoding="utf-8") as _fh:
        _fh.write('/*\nresource "x_y" "commented" {\n  a = 1\n}\n*/\n# resource "x_y" "hashed" {\n'
                  'resource "x_y" "real" {\n  a = 1\n}\n')
    g4c_probe_ok = declared_in(read_tf(_tp)) == {"x_y.real"}
declared_addrs, forgotten_addrs = {}, {}
for r in GUARD4_ROOTS:
    declared_addrs[r] = set()
    for p in tf_files(r):
        declared_addrs[r] |= declared_in(read_tf(p))
    forgotten_addrs[r] = {a for rr, _f, a, _g in removed_blocks if rr == r and a}

# Row 3: a resource block deleted with NO `removed` block. The only sound signal is the BASE
# tree — the repo carries pre-existing `-target=` lines for addresses no resource block declares,
# so "targeted but undeclared" is not it. $BASE_ROOT is the merge-base's copy of the touched
# roots (the tree the diff under test actually diverged from — #9956), materialised by the
# suite; an unreadable base FAILS CLOSED rather than passing vacuously.
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
            base_declared[r] |= declared_in(read_tf(os.path.join(d, f)))
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
# RETIRED, STATE-ABSENT. A resource block deleted because its resource was already gone: a count-gated throwaway
# whose own teardown destroyed it, so state holds no entry and there is nothing for a `-target` to destroy or a
# `removed` block to forget. Honoured only when NO job still targets the address (a leftover target would be a
# stale line, not a deletion), and never for the App identity (G4f). Each entry names the evidence; a new entry
# is a claim about live state and belongs in the PR that deletes the block. The two entries below leave when #9786's
# next-replace removal list lands (G4g refuses a re-declared one).
# SOLEUR-DEBT: remove both entries once #9786's next-replace removal list lands; nothing here expires them mechanically.
RETIRED_STATE_ABSENT = {
    "apps/web-platform/infra": {
        "hcloud_server.inngest_backstop_wipe": "#8285 PR B: throwaway wipe host destroyed by the wipe dispatch teardown 2026-10-09 (run 37955244979); Hetzner lists no such server",
        "hcloud_volume_attachment.inngest_backstop_wipe": "#8285 PR B: destroyed by the same teardown; the volume itself was destroyed 2026-10-09 (run 37958051426)",
    },
}
# Never destroyable and never "retired": the App identity (forget-only) and the SOLE-COPY live stores (the Inngest LUKS
# volume, its attachment, passphrase and key secret, web-1's workspaces LUKS volume and its attachment, and the two
# Inngest Doppler parents doppler_project.inngest and doppler_environment.inngest_prd, #9879). A later PR that lists one of these
# in INTENDED_DESTROYS or RETIRED_STATE_ABSENT trips G4f instead of silently masking its destroy (#8285 PR B review).
G4_PROTECTED = {
    "doppler_secret.github_app_id", "doppler_secret.github_app_private_key",
    "hcloud_volume.inngest_redis_luks", "hcloud_volume_attachment.inngest_redis_luks",
    "random_password.inngest_redis_luks", "doppler_secret.inngest_redis_luks_key",
    "hcloud_volume.workspaces_luks", "hcloud_volume_attachment.workspaces_luks",
    # #9879: the Inngest Doppler parents. Replacing either strands the LUKS passphrase secret above it (the sole copy of
    # the key). One address per line: the mutation row deletes exactly one.
    "doppler_project.inngest",
    "doppler_environment.inngest_prd",
}
# The two App-identity entries are the ONLY protected addresses with legitimate `removed` blocks (forget-only, in
# github-app.tf). G4H_SOLE_COPY is DERIVED from the single list above, never a second hand-written list.
G4_APP_IDENTITY = frozenset({"doppler_secret.github_app_id", "doppler_secret.github_app_private_key"})
G4H_SOLE_COPY = frozenset(G4_PROTECTED) - G4_APP_IDENTITY
orphans = []
for r in GUARD4_ROOTS:
    for a in sorted(base_declared.get(r, set())):
        if a not in declared_addrs[r] and a not in forgotten_addrs[r]:
            if (a in INTENDED_DESTROYS.get(r, {}) and a not in G4_PROTECTED
                    and a in root_targets.get(r, set())):
                continue
            if (a in RETIRED_STATE_ABSENT.get(r, {}) and a not in G4_PROTECTED
                    and a not in any_targeted):
                continue
            orphans.append("%s %s" % (r, a))
check("G4c: every `resource` block the base ref declares and HEAD no longer declares is claimed by a "
      "`removed` block — a deleted resource block with none leaves the resource managed with no HCL, "
      "and the next apply plans a plain DESTROY [base .tf files: %d]" % n_base,
      bool(BASE_ROOT) and n_base >= 1 and g4c_probe_ok and not orphans,
      ("base unavailable" if not BASE_ROOT else "declared-reader probe failed (a commented-out resource read as declared, or a real one did not)" if not g4c_probe_ok else "orphans=%s" % orphans[:8]))
bad_intended = sorted({a for _r, d in list(INTENDED_DESTROYS.items()) + list(RETIRED_STATE_ABSENT.items()) for a in d if a in G4_PROTECTED})
check("G4f: no INTENDED_DESTROYS or RETIRED_STATE_ABSENT entry names a protected address (the App identity, which "
      "may only ever be FORGOTTEN, or a sole-copy live store: %s)" % ", ".join(sorted(G4_PROTECTED)), not bad_intended, bad_intended)
# G4g: a RETIRED_STATE_ABSENT entry is a claim that the address is GONE. If HEAD declares it again the claim is
# false and a later deletion of that new block would ride the allowance with no `removed` block (re-declare, apply,
# delete). Entries are removed when #9786's next-replace work lands or at the first census edit after merge.
redeclared = sorted("%s %s" % (r, a) for r, d in RETIRED_STATE_ABSENT.items() for a in d if a in declared_addrs.get(r, set()))
check("G4g: no RETIRED_STATE_ABSENT address is declared at HEAD (the allowance is only for an address that is "
      "gone; a re-declared one must go through `removed` or INTENDED_DESTROYS)", not redeclared, redeclared)

# ── G4h (#9879, ADR-282): no `removed {}` or `moved {}` over a sole-copy address ─────────────────────────────
# A `removed` block (forget) or a `moved` block (rename) naming one of these addresses detaches or renames the object
# the `prevent_destroy` / `delete_protection` pins are written against, so the pins stop applying while the object
# lives on unprotected (or, with `destroy = true`, is deleted). Both attributes, both block kinds, every `.tf` under
# every GUARD4_ROOTS entry. An index suffix (`x["k"]`) is stripped before comparing.
def _g4h_addr(a):
    return re.sub(r"\[.*$", "", a.strip().strip('"'))
# Dispatch non-vacuity: the `moved` collector must read a known block out of a synthetic probe. A collector that
# silently reads zero blocks (a broken opener regex) would leave every `moved` clause below vacuously green.
_probe = moved_collect('moved {\n  from = hcloud_volume.p\n  to   = hcloud_volume.q["k"]\n}\n', "probe.tf", "probe")
g4h_probe_ok = _probe == [("probe", "probe.tf", "hcloud_volume.p", 'hcloud_volume.q["k"]')]
# Second probe: an INDENTED `moved`/`removed` is read, and a commented or heredoc one is not (hcl_code_only).
_p2 = hcl_code_only('# moved { from = a.b }\n  moved {\n    from = a.b\n    to = a.c\n  }\n'
                    'x = <<EOT\n  removed {\n  from = a.d\n  }\nEOT\n/* moved {\n from = a.e\n} */\n  removed {\n    from = a.f\n  }\n')
g4h_probe_ok = (g4h_probe_ok
                and [(a, b) for _r, _f, a, b in moved_collect(_p2, "probe2.tf", "probe")] == [("a.b", "a.c")]
                and [fr.group(1) for _m, bb in block_bodies(_p2, REMOVED_OPEN)
                     for fr in [re.search(r"^\s*from\s*=\s*(\S+)\s*$", bb, re.M)]] == ["a.f"])
# Third probe: the scrubber's comment/string lexing. Each shape sits AHEAD of an indented `removed {` that must STILL be
# read; a scrubber that mis-lexes the shape blanks that block (a `/*` opens a block comment to EOF, a `<<EOF` opens a
# heredoc to EOF). Shapes: `#` line comment holding `/*`; `//` line comment holding `/*`; a quoted string holding `/*`
# (string tracking); a trailing `#` comment holding a heredoc opener. Neutering the `#`/`//` branch or the string
# tracking turns this red (checker-copy mutants g4h-9 and g4h-10).
_p3 = hcl_code_only('# glob /mnt/*\n  removed {\n    from = a.g\n  }\n'
                    '// glob /mnt/*\n  removed {\n    from = a.h\n  }\n'
                    'x = "/mnt/*"\n  removed {\n    from = a.i\n  }\n'
                    'x = 1 # see <<EOF\n  removed {\n    from = a.j\n  }\n')
g4h_probe_ok = (g4h_probe_ok
                and [fr.group(1) for _m, bb in block_bodies(_p3, REMOVED_OPEN)
                     for fr in [re.search(r"^\s*from\s*=\s*(\S+)\s*$", bb, re.M)]] == ["a.g", "a.h", "a.i", "a.j"])
g4h_hits = []
for _r, f, a, _g in removed_blocks:
    if a and _g4h_addr(a) in G4H_SOLE_COPY:
        g4h_hits.append("removed from=%s (%s)" % (a, f))
for _r, f, a, b_ in moved_blocks:
    for k, v in (("from", a), ("to", b_)):
        if v and _g4h_addr(v) in G4H_SOLE_COPY:
            g4h_hits.append("moved %s=%s (%s)" % (k, v, f))
print("IPT_G4H=removed:%d moved:%d probe:%d hits:%d" % (len(removed_blocks), len(moved_blocks), int(g4h_probe_ok), len(g4h_hits)), file=sys.stderr)
check("G4h: no `removed` or `moved` block names a sole-copy address (G4H_SOLE_COPY, %d addresses) as `from` or `to` "
      "[%d removed + %d moved blocks over %d .tf files; %d hits]"
      % (len(G4H_SOLE_COPY), len(removed_blocks), len(moved_blocks), g4_files, len(g4h_hits)),
      g4_files >= 1 and g4h_probe_ok and not g4h_hits,
      ("moved collector probe failed" if not g4h_probe_ok else sorted(g4h_hits)[:8]))
# G4h2: the exact-set pin. G4H_SOLE_COPY is derived from G4_PROTECTED, so deleting an entry from G4_PROTECTED would
# silently shrink what G4h guards. The literal below is the second side of that comparison; a reviewer reads both when
# either changes (lifting protection is a reviewed two-step change, ADR-282).
G4H_EXPECTED = frozenset({
        "hcloud_volume.inngest_redis_luks", "hcloud_volume_attachment.inngest_redis_luks",
        "random_password.inngest_redis_luks", "doppler_secret.inngest_redis_luks_key",
        "hcloud_volume.workspaces_luks", "hcloud_volume_attachment.workspaces_luks",
        "doppler_project.inngest", "doppler_environment.inngest_prd",
})
g4h_drift = sorted((G4H_SOLE_COPY ^ G4H_EXPECTED)) + sorted(G4_APP_IDENTITY - G4_PROTECTED)
check("G4h2: G4H_SOLE_COPY (G4_PROTECTED minus the two App-identity entries) equals the pinned sole-copy set "
      "[%d addresses] and both App-identity entries stay protected" % len(G4H_EXPECTED), not g4h_drift, g4h_drift)

# G4h4: the LIVE collectors read every real `removed`/`moved` block. G4h reads its blocks through hcl_code_only, which
# fails OPEN (an unterminated heredoc or comment blanks to EOF and a hidden block cannot trip G4h), and its probe strings
# only cover the shapes written into them. So the live counts are pinned to the UNSCRUBBED opener count over the same
# files: a scrubber regression that blanks a real block on a real file reads as a count mismatch here, not as zero
# blocks and a green G4h. Derived, never hardcoded. A heredoc body or block comment that merely LOOKS like a block makes
# the raw count exceed the scrubbed one; that is a reviewed case (M-g4h-8 drives it), not a silent pass.
raw_removed = raw_moved = 0
for r in GUARD4_ROOTS:
    for p in tf_files(r):
        _raw = open(p, encoding="utf-8", errors="replace").read()
        raw_removed += len(REMOVED_OPEN.findall(_raw))
        raw_moved += len(MOVED_OPEN.findall(_raw))
print("IPT_G4H4=raw_removed:%d raw_moved:%d scrubbed_removed:%d scrubbed_moved:%d" % (raw_removed, raw_moved, len(removed_blocks), len(moved_blocks)), file=sys.stderr)
check("G4h4: the scrubbed removed/moved collectors read exactly as many blocks as an unscrubbed grep of the same files "
      "(no real block blanked by hcl_code_only) [%d removed + %d moved scrubbed vs %d + %d raw]"
      % (len(removed_blocks), len(moved_blocks), raw_removed, raw_moved),
      g4_files >= 1 and raw_removed + raw_moved >= 1
      and raw_removed == len(removed_blocks) and raw_moved == len(moved_blocks),
      "scrubbed removed=%d moved=%d, raw removed=%d moved=%d" % (len(removed_blocks), len(moved_blocks), raw_removed, raw_moved))

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
    a literal ("" -- a mapping with no name -- or the __UNPARSEABLE__ sentinel an expression
    with no quoted literal now yields, #9755 review) counts as maybe Tier B: this is a ban,
    so the unknown direction is the refusing one."""
    arms = env_arms(raw)
    if arms is None:
        return False
    tier_b = {e.lower() for e in TIER_B_ENVIRONMENTS}
    return any(a in ("", "__UNPARSEABLE__") or a.lower() in tier_b for a in arms)

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

# G7 (#9321, ADR-241 D11) -- the soleur-infra-app project (the two App values the inngest-bootstrap
# release jobs read) stays a bare container in Terraform, and its read token is never minted in CI
# nor stored anywhere branch-reachable. Same state-readability argument as G6c: a Tier-A key reads
# this root's state, so a secret, a token or a reader declared here would put the App key back
# where the project removes it from.
#
# WHAT THIS GUARD IS NOT. It is a census of spelled patterns over the roots, workflows, composite
# actions, one-level scripts and bootstrap scripts the repo has today. It cannot prove the property
# for every possible HCL or shell spelling (a `local-exec` provisioner, a `data "external"`, a
# remote module, an out-of-tree root, an inline `sh -c` mint). The boundary that holds for those is
# the one ADR-241 D2/D11 state: the main-only environment policy plus review of main.
G7_LIT = re.compile(r'"soleur-infra-app"')
# Doppler resource types that hold a value, mint a credential, grant a reader or copy values out. The
# G6 set (which also fails a stateful resource with NO project) plus the types that only matter when
# they name this project.
G7_EXTRA = re.compile(r"^doppler_(?:rotated_secret_[a-z_]+|service_account(?:_identity)?|group_member(?:s)?|"
                      r"config_inheritance|project_role|trusted_ips)$")
# A stateful resource's `project` is a plain literal or a reference to a Doppler resource that is NOT
# derived from soleur-infra-app. A variable, a local or a module output cannot be shown NOT to be
# soleur-infra-app, so it is flagged instead of trusted.
G7_PLAIN_PROJECT = re.compile(r'^(?:"[A-Za-z0-9_-]+"|doppler_(?:project|config|environment)\.[A-Za-z0-9_]+\.(?:name|project))$')
g7_bad_c = []
g7_blocks = []
for rel, t in g6_tf:
    t = re.sub(r"/\*.*?\*/", "", t, flags=re.S)  # block comments are not HCL; g6_code strips whole-line # and // only
    for m, b in block_bodies(t, RES_OPEN) + block_bodies(t, DATA_OPEN):
        g7_blocks.append((rel, "data" if m.group(0).startswith("data") else "resource", m.group(1), m.group(2), b))
g7_tainted = {"doppler_project.%s" % nm for _r, kind, typ, nm, b in g7_blocks
              if kind == "resource" and typ == "doppler_project"
              and re.search(r'^\s*name\s*=\s*"soleur-infra-app"\s*(?:(?:#|//).*)?$', b, re.M)}
g7_declared = bool(g7_tainted)
# The tainted address set is derived from the declaring block, so a renamed label or an environment/config
# aliasing the project does not leave a reference the guard cannot see.
while True:
    grown = set()
    for _r, kind, typ, nm, b in g7_blocks:
        addr = "doppler_%s.%s" % (typ[len("doppler_"):], nm)
        if kind == "resource" and typ in ("doppler_environment", "doppler_config") and addr not in g7_tainted \
           and (G7_LIT.search(b) or re.search(r"\b(?:%s)\b" % "|".join(re.escape(a) for a in g7_tainted), b)):
            grown.add(addr)
    if not grown:
        break
    g7_tainted |= grown
g7_addr = re.compile(r"\b(?:%s)\b" % "|".join(re.escape(a) for a in sorted(g7_tainted))) if g7_tainted else None
for rel, kind, typ, nm, b in g7_blocks:
    if not (G6_STATEFUL.match(typ) or G7_EXTRA.match(typ)):
        continue
    if G7_LIT.search(b) or (g7_addr and g7_addr.search(b)):
        g7_bad_c.append("%s %s %s.%s on the project" % (rel, kind, typ, nm))
        continue
    if not G6_STATEFUL.match(typ):
        continue
    pm = re.search(r"^\s*project\s*=\s*(.+?)\s*(?:(?:#|//).*)?$", b, re.M)
    if not pm or not G7_PLAIN_PROJECT.match(pm.group(1)):
        g7_bad_c.append("%s %s %s.%s project is not a literal or a Doppler resource reference" % (rel, kind, typ, nm))
# `.tf.json` is not read by tf_files (and terraform fmt ignores it): refuse any that names the project.
for r in sorted(tf_root_files):
    for f in sorted(os.listdir(os.path.join(REPO, r))):
        if f.endswith(".tf.json") and "soleur-infra-app" in open(os.path.join(REPO, r, f), encoding="utf-8", errors="replace").read():
            g7_bad_c.append("%s/%s names the project" % (r, f))
check("G7c: soleur-infra-app is declared (project, name soleur-infra-app) and no root declares a stateful "
      "doppler_* resource on it, through any alias of its project/environment/config (or one whose project "
      "cannot be shown to be another project) [%d .tf files, declared=%s, %d tainted addresses]"
      % (len(g6_tf), g7_declared, len(g7_tainted)),
      len(g6_tf) >= 1 and g7_declared and not g7_bad_c, "tf=%d bad=%s" % (len(g6_tf), g7_bad_c[:5]))

G7_MINT = re.compile(r"\bdoppler\b[^\n]*?\b(?:configs[ \t]+tokens|service-tokens)\b[^\n]*?\bcreate\b")
G7_REST_MINT = re.compile(r"api\.doppler\.com/v3/configs/config/tokens")
g7_bad_d = []
for where, b in g6_bodies:
    for line in CONT.sub(" ", b).split("\n"):
        if re.match(r"\s*#", line):
            continue
        if G7_REST_MINT.search(line) and "soleur-infra-app" in line:
            g7_bad_d.append(where)
        if G7_MINT.search(line):
            # a literal project (quoted or not, on either side of the verb), or a project the guard cannot name
            vals = re.findall(r"(?:^|\s)(?:-p|--project)(?:[= ]+|(?=\S))[\"']?([^\s\"']+)", line) \
                + re.findall(r"DOPPLER_PROJECT=[\"']?([^\s\"']+)", line)
            if "soleur-infra-app" in line or any(v.startswith("$") for v in vals):
                g7_bad_d.append(where)
# The bootstrap script that mints the read token is the one place a token is stored. It must store
# it only at ENVIRONMENT level: a repository-level secret is reachable from any branch's workflow. Scripts are
# found by their literal (archived ones included: archiving the spec directory must not retire the guard).
g7_scripts = [f for f in sorted(glob.glob(os.path.join(REPO, "knowledge-base", "project", "specs", "**", "bootstrap.sh"), recursive=True))
              if "soleur-infra-app" in open(f, encoding="utf-8", errors="replace").read()]
G7_STORE = re.compile(r"\bgh\s+secret\s+set\b")
G7_ENV_OK = re.compile(r"(?:^|\s)(?:--env|-e)[ =]+[\"']?(?:infra-privileged|\$\{?GH_ENVIRONMENT\}?)[\"']?(?:\s|$)")
G7_OTHER_STORE = re.compile(r"\bsoleur_op_gh_secret_set\b|\bgh\s+variable\s+set\b|\bgh\s+api\b[^\n]*(?:-X|--method)[ =]+PUT\b[^\n]*(?:actions|dependabot)/secrets")
for f in g7_scripts:
    src = open(f, encoding="utf-8", errors="replace").read()
    rel = os.path.relpath(f, REPO)
    for i, line in enumerate(CONT.sub(" ", src).split("\n"), 1):
        code = re.sub(r"\s#.*$", "", line)  # a trailing comment is not an argument
        if re.match(r"\s*#", code):
            continue
        if G7_STORE.search(code) and not G7_ENV_OK.search(code):
            g7_bad_d.append("%s:%d gh secret set without --env infra-privileged" % (rel, i))
        if G7_OTHER_STORE.search(code):
            g7_bad_d.append("%s:%d a store that is not an environment-level `gh secret set --env`" % (rel, i))
    if re.search(r"\$\{?GH_ENVIRONMENT\}?", src) and not re.search(r'^GH_ENVIRONMENT="infra-privileged"\s*$', src, re.M):
        g7_bad_d.append("%s: GH_ENVIRONMENT is not pinned to infra-privileged" % rel)
check("G7d: no workflow, action or reachable script mints a Doppler token on soleur-infra-app (a quoted, "
      "variable or flag-first project included), and the bootstrap script stores it only with "
      "`gh secret set --env infra-privileged` [%d bootstrap script(s)]" % len(g7_scripts),
      not g7_bad_d and (len(g7_scripts) >= 1 or not CHECK_GIT), "scripts=%d bad=%s" % (len(g7_scripts), sorted(set(g7_bad_d))[:5]))

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

# G7e -- no Doppler cross-project reference to the soleur-infra-app project (`${soleur-infra-app.prd.X}`): a reference
# resolves with the READER's permissions, which would copy the App key into a project a branch-reachable token reads.
G7_XREF = re.compile(r"\$\$?\{\s*soleur-infra-app\.")
g7_bad_e = sorted({rel for rel, t in g6_scan if G7_XREF.search(t)})
check("G7e: no workflow, action, reachable script, .tf, .tmpl or cloud-init file carries a Doppler reference "
      "`${soleur-infra-app.` [%d files scanned]" % len(g6_scan), not g7_bad_e, g7_bad_e[:5])

# G7f (#9321, ADR-241 D11) -- every call of the App-token composite is exactly ONE of two source shapes, and the
# composite itself offers nothing else:
#   narrow  no `doppler-project` input; `doppler-token` is secrets.DOPPLER_TOKEN_INFRA_APP (the release jobs and,
#           since #9454, the weekly digest job);
#   broad   `doppler-project: soleur-infra-privileged` and secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED, and only in
#           a job that also calls the infra-credentials loader (it already holds the whole Tier-B project).
# The composite's `doppler-project` default is the narrow project, its allow-list is exactly the two project
# literals, and it makes exactly two `doppler secrets get` calls (the App id and key, project from the validated
# variable, config prd); no command-position read of an App value exists anywhere else.
#
# POPULATION is derived, never listed: (a) every workflow-job step whose `uses` resolves to the composite, in the
# local `./.github/actions/<dir>`, the remote `owner/repo/.github/actions/<dir>@ref` and the `..`-spelled forms
# (the two non-canonical spellings are themselves refused, clause `spelling`), plus every composite action that
# wraps the composite in its own `runs.steps` (refused, clause `wrapper`); (b) the composite file the same
# resolution finds, parsed for the input default, the DOPPLER_SOURCE env mapping, the validation `case` literals
# and EVERY command-position `doppler secrets get|download` / `doppler run` in it (so a third read of ANOTHER name
# is seen, which the App-value regex of (c) cannot do); (c) every command-position `doppler secrets get` of an App
# value in any workflow or action `run:` body, so a second reader or a second composite cannot escape by living in
# a new file. Command position (cmd_sites) means a comment, an echo argument or a heredoc body is not a read. Token
# references match in the dotted and the whitespace spellings (the bracket spelling is refused repo-wide by G1e, and
# refused here as an unnamed token). Each failure carries a `[clause]` tag and the row detail lists the clauses that
# fired, so a red row says which clause caught it. "Release job" is a job that calls the composite and not the
# loader: a release job that later adds the loader escapes the broad-shape restriction; the per-suite
# no-broad-tier-b rows pin the two named jobs.
# The live tree has exactly four callers (a fifth is a deliberate, dated edit here); a fixture needs >= 1.
# 3 -> 4 (2026-10-11, #9454 item 4, ADR-285): weakness-miner.yml::open-pr, the third narrow-shape caller
# (the fourth overall; apply-github-infra.yml is the broad one). Unlike the two release jobs it
# authors the weekly digest PR as the App.
G7F_COMP_REL = "actions/mint-infra-app-token/action.yml"
G7F_NARROW, G7F_BROAD = "soleur-infra-app", "soleur-infra-privileged"
G7F_NARROW_TOK, G7F_BROAD_TOK = "DOPPLER_TOKEN_INFRA_APP", "DOPPLER_TOKEN_INFRA_PRIVILEGED"
G7F_APP_READ = re.compile(r"\bdoppler\b[^\n]*?\bsecrets\s+get\b[^\n]*?\bGITHUB_INFRA_APP_(?:ID|PRIVATE_KEY)\b")
# `run` is anchored to the subcommand position (only whitespace-separated words, none of them a shell operator,
# between `doppler` and `run`), so the English word in `doppler --version ... || { echo "...run the install step"; }`
# is not a read, while a flag value that contains a space (`--token "$(cat f)" run`) still is.
G7F_ANY_READ = re.compile(r"\bdoppler\b(?:[^\n]*?\bsecrets\s+(?:get|download)\b|(?:\s+[^\s|&;<>]+)*?\s+run\b)")
G7F_SECRET = re.compile(r"^\$\{\{\s*secrets\s*\.\s*([A-Za-z0-9_]+)\s*\}\}$", re.I)
G7F_LOADER = re.compile(r"^\./\.github/actions/infra-credentials/?$")
G7F_CANON = re.compile(r"^\./\.github/actions/mint-infra-app-token/?$")
def g7f_target(uses):
    """The `.github`-relative path a `uses` string names, or None: the local `./.github/...` form, the remote
    `owner/repo/.github/...@ref` form, and a `..`-spelled path all normalise to the same target."""
    u = str(uses or "").strip().split("@", 1)[0]
    if u.startswith("./"):
        pth = u[2:]
    else:
        rm = re.match(r"^[^/\s]+/[^/\s]+/(\.github/.*)$", u)
        if not rm:
            return None
        pth = rm.group(1)
    pth = posixpath.normpath(pth)
    return pth[len(".github/"):] if pth.startswith(".github/") else None
def g7f_is_comp(uses):
    t = g7f_target(uses)
    return t is not None and (t + "/action.yml" == G7F_COMP_REL or t == G7F_COMP_REL)
g7f_bad, g7f_callers = [], []
# Every failure is tagged with the clause that fired, so a red row names its cause and the mutation rows can
# pin ONE clause each (a mutant two clauses both catch hides a clause that was deleted).
def g7f_fail(tag, msg):
    g7f_bad.append("[%s] %s" % (tag, msg))
for rel, (doc, text) in sorted(docs.items()):
    # (iii) a composite that wraps the mint composite: the token/project pairing cannot be proven statically
    # through an `inputs.*` pass-through, so a wrapper is refused outright (the composite itself is exempt).
    runs_ = doc.get("runs")
    if rel != G7F_COMP_REL and isinstance(runs_, dict):
        for st in (runs_.get("steps") or []):
            if isinstance(st, dict) and g7f_is_comp(st.get("uses")):
                g7f_fail("wrapper", "%s wraps the mint composite inside another composite action" % rel)
    for jn, jb in (doc.get("jobs") or {}).items():
        if not isinstance(jb, dict):
            continue
        steps_ = [st for st in (jb.get("steps") or []) if isinstance(st, dict)]
        has_loader = any(G7F_LOADER.match(str(st.get("uses") or "")) for st in steps_)
        for st in steps_:
            if not g7f_is_comp(st.get("uses")):
                continue
            who = "%s::%s" % (rel, jn)
            g7f_callers.append(who)
            # (i)/(ii) the remote and `..` spellings name the same composite but escape every other census
            # mapping (`./.github/actions/<dir>`); only the one local spelling is admitted.
            if not G7F_CANON.match(str(st.get("uses") or "")):
                g7f_fail("spelling", "%s names the composite as %r, not ./.github/actions/mint-infra-app-token" % (who, st.get("uses")))
            w = st.get("with") or {}
            tm = G7F_SECRET.match(str(w.get("doppler-token", "")).strip())
            tok = tm.group(1).upper() if tm else None   # secret names are case-insensitive at GitHub
            if "doppler-project" not in w:
                if tok != G7F_NARROW_TOK:
                    g7f_fail("caller-shape", "%s: no doppler-project (narrow source) but doppler-token is %r, not secrets.%s" % (who, w.get("doppler-token"), G7F_NARROW_TOK))
            elif str(w.get("doppler-project")) == G7F_BROAD:
                if tok != G7F_BROAD_TOK:
                    g7f_fail("caller-shape", "%s: doppler-project %s but doppler-token is %r, not secrets.%s" % (who, G7F_BROAD, w.get("doppler-token"), G7F_BROAD_TOK))
                if not has_loader:
                    g7f_fail("loader", "%s: the broad source in a job that does not call the infra-credentials loader" % who)
            else:
                g7f_fail("caller-shape", "%s: doppler-project %r is neither absent nor %s" % (who, w.get("doppler-project"), G7F_BROAD))
g7f_comp = docs.get(G7F_COMP_REL)
if g7f_comp is None:
    g7f_fail("composite-missing", "the composite %s was not found" % G7F_COMP_REL)
else:
    cdoc = g7f_comp[0]
    dflt = (((cdoc.get("inputs") or {}).get("doppler-project")) or {}).get("default")
    if dflt != G7F_NARROW:
        g7f_fail("default", "composite doppler-project default is %r, not %s" % (dflt, G7F_NARROW))
    # the env mapping that feeds every read: DOPPLER_SOURCE is the validated input and nothing else
    csrc = [(st.get("env") or {}).get("DOPPLER_SOURCE") for st in ((cdoc.get("runs") or {}).get("steps") or [])
            if isinstance(st, dict) and "DOPPLER_SOURCE" in (st.get("env") or {})]
    if csrc != ["${{ inputs.doppler-project }}"]:
        g7f_fail("env-map", "composite DOPPLER_SOURCE env is %r, not exactly one ${{ inputs.doppler-project }}" % (csrc,))
    cbody = "\n".join(str(b) for b in step_bodies(cdoc))
    allowed = set()
    for alts in re.findall(r"^\s*([A-Za-z0-9_-]+(?:\|[A-Za-z0-9_-]+)*)\)\s*:\s*;;", cbody, re.M):
        allowed |= set(alts.split("|"))
    if allowed != {G7F_NARROW, G7F_BROAD}:
        g7f_fail("allow-list", "composite allow-list is %s, not exactly {%s, %s}" % (sorted(allowed), G7F_NARROW, G7F_BROAD))
    csites = [line for line, _m in cmd_sites(cbody, G7F_ANY_READ)]
    cnames = sorted(re.findall(r"\bsecrets\s+get\s+(?:\S+\s+)*?(GITHUB_INFRA_APP_(?:ID|PRIVATE_KEY))\b", " ".join(csites)))
    if len(csites) != 2 or cnames != ["GITHUB_INFRA_APP_ID", "GITHUB_INFRA_APP_PRIVATE_KEY"]:
        g7f_fail("read-count", "composite makes %d Doppler read/run call(s) naming %s, not exactly the two App-value reads" % (len(csites), cnames))
    for line in csites:
        if not (re.search(r'--project\s+"\$DOPPLER_SOURCE"', line) and re.search(r"--config\s+prd\b", line)):
            g7f_fail("read-argv", "composite read without --project \"$DOPPLER_SOURCE\" --config prd: %s" % line.strip()[:80])
for rel, (doc, text) in sorted(docs.items()):
    if rel == G7F_COMP_REL:
        continue
    for _job, body in step_sites(doc):
        if any(True for _l, _m in cmd_sites(body, G7F_APP_READ)):
            g7f_fail("outside-read", "%s reads an App value with doppler secrets get outside the composite" % rel)
g7f_n = len(g7f_callers)
if CHECK_GIT and g7f_n != 4:
    g7f_fail("caller-count", "%d callers, the live tree has exactly 4 (a fifth is a deliberate, dated edit here)" % g7f_n)
elif g7f_n < 1:
    g7f_fail("caller-count", "no caller of the composite was scanned")
check("G7f: every mint-infra-app-token call is the narrow shape (no doppler-project, secrets.%s) or the loader-job broad "
      "shape (doppler-project %s, secrets.%s), the composite defaults to %s with a two-literal allow-list and exactly "
      "two pinned reads, and no other workflow or action run body reads an App value [%d callers, composite %s]"
      % (G7F_NARROW_TOK, G7F_BROAD, G7F_BROAD_TOK, G7F_NARROW, g7f_n, "found" if g7f_comp is not None else "missing"),
      not g7f_bad,
      "clauses=%s callers=%s bad=%s" % (sorted({b[1:b.index("]")] for b in g7f_bad}), sorted(g7f_callers), sorted(set(g7f_bad))[:4]))

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
CENSUS_ROWS=48  # 47 -> 48 (#10990): +1 row, G1k (AC7b limb 3 — local .sh state-writers source their ambient AWS_* pair from a Tier-B name). Previously: # 46 -> 47 (#9927 8b): +1 row, G1j (every loader job declares a Tier-B environment). Previously: # 43 -> 45 (#9879): +2 rows, G4h (no removed/moved over a sole-copy address) and G4h2 (the exact sole-copy set); main carries 43 live rows against a floor of 42 (the floor sat one below the live count), and the floor is now exactly the live count. 45 -> 46 (#9879 round 2): +1 row, G4h4 (the live removed/moved counts equal the unscrubbed count). 22 -> 23 (#9215): G1i-rk, the root-key extract-precedence row. 23 -> 34 (#8609): Guard 6, G6a..G6l.
# 41 -> 42 (#9321 PR-2, 2026-10-03): G7f, the App-token composite and callers source-shape row.
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
# census crashed on a fixture) returns 0, so a mutant can never read as RED for the wrong reason. A TSV that
# is MISSING or EMPTY (a fixcensus line deleted, so awk had nothing to read) is UNRESOLVED: rc 2 and a stderr
# note, never 1, so it cannot read as RED either (review #9453: awk exits 2 on a missing file and every caller
# used to take any non-zero rc as RED).
# shellcheck disable=SC2317  # invoked indirectly through mutant_red
wf_row() {
  [ -s "$1" ] || { printf 'UNRESOLVED: census TSV %s is missing or empty\n' "$1" >&2; return 2; }
  awk -F'\t' -v p="$2" 'index($2, p) == 1 { found = 1; if ($1 != "ok") bad = 1 } END { exit (found && bad) ? 1 : 0 }' "$1"
}
# wf_red <tsv> <name-prefix> — true ONLY on the verdict "present and not ok" (rc exactly 1), never on UNRESOLVED.
wf_red() { local rc=0; wf_row "$@" || rc=$?; [ "$rc" -eq 1 ]; }
# wf_clause <tsv> <name-prefix> <clause> [<clause that must NOT fire>] — as wf_row, but the row must be red
# BECAUSE the named G7f clause fired (its detail lists `clauses=['...']`), and optionally not because of a
# second one. This is how a mutant pins ONE clause: a mutant two clauses both catch hides a deleted clause.
# shellcheck disable=SC2317  # invoked indirectly through mutant_red
wf_clause() {
  [ -s "$1" ] || { printf 'UNRESOLVED: census TSV %s is missing or empty\n' "$1" >&2; return 2; }
  awk -F'\t' -v p="$2" -v w="'$3'" -v a="${4:+'$4'}" '
    index($2, p) == 1 { found = 1; if ($1 != "ok") { bad = 1; if (match($3, /clauses=\[[^]]*\]/)) cl = substr($3, RSTART, RLENGTH) } }
    END { exit (found && bad && index(cl, w) > 0 && (a == "" || index(cl, a) == 0)) ? 1 : 0 }' "$1"
}

# ── the base tree for the deleted-resource-block row (Guard 4 row 3) ─────────────────
# `git show <ref>:<path>` per file rather than a worktree checkout: this suite must never touch
# the caller's index or working tree.
# materialize_base_dir <repodir> <ref> <destdir> — copy <ref>'s *.tf under GUARD4_ROOTS into
# <destdir>. Extracted so the G4c base legs below drive the PRODUCTION path (a fixture that
# re-implements the materialization proves the fixture, not the guard).
materialize_base_dir() {
  local _rd="$1" _ref="$2" _dest="$3" _rc=0 _lst _f _r="" _n _why=""
  assert_fixture_dir "$_rd"
  assert_fixture_dir "$_dest"
  mkdir -p "$_dest/apps/web-platform/infra/git-data-root-key" || { _rc=1; _why="mkdir"; }
  if [ "$_rc" -eq 0 ]; then
    for _r in apps/web-platform/infra apps/web-platform/infra/git-data-root-key; do
      _lst="$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE \
        git -C "$_rd" ls-tree -r --name-only "$_ref" -- "$_r" 2>/dev/null)" || { _why="ls-tree"; _rc=1; break; }
      [ -n "$_lst" ] || { _why="empty-listing"; _rc=1; break; }
      _n=0
      while IFS= read -r _f; do
        case "$_f" in *.tf) ;; *) continue ;; esac
        [ "${_f%/*}" = "$_r" ] || continue
        env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE \
          git -C "$_rd" show "$_ref:$_f" > "$_dest/$_f" 2>/dev/null || { _rc=1; _why="show"; }
        _n=$((_n + 1))
      done <<< "$_lst"
      # Per-root floor: a root whose listing holds only non-.tf or nested files contributes
      # zero materialized files — without this its base_declared reads {} and that root's
      # deletions blind-green (the file floor in ipt.py is global across both roots).
      # Fail-closed by direction: a branch forked before a root's first .tf reds 'base
      # unavailable', which the IPT_BASE_REF seam covers — the blind-green alternative is worse.
      [ "$_n" -ge 1 ] || { _rc=1; _why="floor"; }
      # `show`/`floor` do not break inside the while — break HERE, while `_r` still names the
      # failing root, so the root= field cannot mis-attribute a root-1 failure to root 2.
      [ "$_rc" -eq 0 ] || break
    done
  fi
  if [ "$_rc" -ne 0 ]; then
    printf 'IPT_G4C_BASE_MATERIALIZE=fail step=%s root=%s ref=%s\n' \
      "${_why:-unknown}" "${_r:-pre-roots}" "${_ref//[[:cntrl:]$'\u2028\u2029']/?}" >&2
  fi
  [ "$_rc" -eq 0 ]
}
BASEDIR="$T/base"; assert_fixture_dir "$BASEDIR"
BASE_REF="$(resolve_base_ref "$REPODIR")"
materialize_base_dir "$REPODIR" "$BASE_REF" "$BASEDIR" || BASEDIR=""

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
         "$FIX/tree/.github/actions/mint-infra-app-token" \
         "$FIX/tree/scripts" "$FIX/tree/apps/web-platform/infra/git-data-root-key" \
         "$FIX/tree/apps/web-platform/scripts" "$FIX/tree/apps/cla-evidence/infra" \
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

# (#9755) The `${{ }}` environment form the live cutover job carries: a disjunction of
# `inputs.op == '<name>'` PREDICATE literals guarding the gated ops, an `&&` result literal that
# is a Tier-B environment, and a `|| ''` false arm resolving to NO environment for the ungated
# ops. env_arms must read the predicate literals as comparisons (never environment names) and
# the empty arm as "no environment" — on it no env-scoped secret resolves, the loader call is
# if:-gated and, with no doppler-token-legacy, would fail closed even ungated. The whole shape
# must stay GREEN: reading 'a'/'b' as environment names would red G1c/G1j, and it is the
# control-side proof that the comparison-operand strip is in place.
cat > "$FIX/tree/.github/workflows/tierb-conditional.yml" <<'EOF'
name: fixture tier-b conditional env
on:
  workflow_dispatch:
    inputs:
      op:
        type: choice
        options: [a, b, c]
jobs:
  run:
    runs-on: ubuntu-24.04
    environment: ${{ (inputs.op == 'a' || inputs.op == 'b') && 'infra-privileged' || '' }}
    steps:
      - name: Load Tier-B credentials (fixture)
        if: inputs.op == 'a'
        uses: ./.github/actions/infra-credentials
        with:
          doppler-token-infra-privileged: ${{ (inputs.op == 'a') && secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED || '' }}
      - run: echo done
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

# G7f (#9321): the compliant App-token composite and its two call shapes. The composite's default is
# the narrow project, its allow-list is exactly the two named projects, and it makes exactly the two
# pinned reads. The release-shaped caller (narrow: no project input, the narrow token) and the
# loader-calling caller (broad: the explicit project input, the broad token) are the two shapes the
# live tree has. Without them the G7f row could only ever show its empty-population branch, and the
# control would be red.
cat > "$FIX/tree/.github/actions/mint-infra-app-token/action.yml" <<'EOF'
name: "Mint App token (fixture)"
description: "fixture composite"
inputs:
  doppler-token:
    required: true
  doppler-project:
    required: false
    default: soleur-infra-app
  installation-id:
    required: true
runs:
  using: composite
  steps:
    - name: Mint
      id: mint
      shell: bash
      env:
        DOPPLER_SOURCE: ${{ inputs.doppler-project }}
      run: |
        set -euo pipefail
        case "${DOPPLER_SOURCE:-}" in
          soleur-infra-app|soleur-infra-privileged) : ;;
          *) echo "::error::doppler-project must be one of the two named projects"; exit 1 ;;
        esac
        APP_ID=$(doppler secrets get GITHUB_INFRA_APP_ID --plain --project "$DOPPLER_SOURCE" --config prd 2>/dev/null)
        PEM=$(doppler secrets get GITHUB_INFRA_APP_PRIVATE_KEY --plain --project "$DOPPLER_SOURCE" --config prd 2>/dev/null)
        echo "::add-mask::$APP_ID" > /dev/null
        echo "$PEM" > /dev/null
EOF

cat > "$FIX/tree/.github/workflows/release.yml" <<'EOF'
name: fixture release job (narrow source)
on: workflow_dispatch
jobs:
  release:
    runs-on: ubuntu-24.04
    environment: infra-privileged
    steps:
      - name: Verify DOPPLER_TOKEN_INFRA_APP present
        env:
          DOPPLER_TOKEN_CHECK: ${{ secrets.DOPPLER_TOKEN_INFRA_APP }}
        run: |
          set -euo pipefail
          test -n "$DOPPLER_TOKEN_CHECK"
      - name: Mint
        uses: ./.github/actions/mint-infra-app-token
        with:
          doppler-token: ${{ secrets.DOPPLER_TOKEN_INFRA_APP }}
          installation-id: "166065653"
EOF

cat > "$FIX/tree/.github/workflows/marketplace-verify.yml" <<'EOF'
name: fixture marketplace verify (broad source, loader job)
on: workflow_dispatch
jobs:
  verify:
    runs-on: ubuntu-24.04
    environment: infra-privileged
    steps:
      - uses: ./.github/actions/infra-credentials
        with:
          doppler-token-infra-privileged: ${{ secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED }}
      - name: Mint
        uses: ./.github/actions/mint-infra-app-token
        with:
          doppler-token: ${{ secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED }}
          doppler-project: soleur-infra-privileged
          installation-id: "166065653"
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

# AC7b limb 3 (#10990): the two armed local state-writers, at their real rel paths so the G1k
# population floor reads them verbatim (the ci-deploy.sh precedent below does the same for G6s).
# Both source BOTH ambient AWS_* legs from the Tier-B TF_STATE_AWS_* pair — the compliant shape.
cat > "$FIX/tree/apps/cla-evidence/infra/bootstrap.sh" <<'EOF'
#!/usr/bin/env bash
# Fixture: a local terraform state-writer whose backend pair rides a wrapper's env (the live
# cla-evidence bootstrap's shape).
set -euo pipefail
STATE_KEY=$(doppler secrets get TF_STATE_AWS_ACCESS_KEY_ID    -p soleur-infra-privileged -c prd --plain)
STATE_SEC=$(doppler secrets get TF_STATE_AWS_SECRET_ACCESS_KEY -p soleur-infra-privileged -c prd --plain)
tf_env() { AWS_ACCESS_KEY_ID="$STATE_KEY" AWS_SECRET_ACCESS_KEY="$STATE_SEC" "$@"; }
tf_env terraform apply -auto-approve -input=false
EOF

cat > "$FIX/tree/apps/web-platform/scripts/bootstrap-live-verify.sh" <<'EOF'
#!/usr/bin/env bash
# Fixture: a local terraform state-writer exporting the bare backend pair from the Tier-B
# TF_STATE_AWS_* legs before a wrapped apply (the live script's shape).
set -euo pipefail
export AWS_ACCESS_KEY_ID="$(doppler secrets get TF_STATE_AWS_ACCESS_KEY_ID --plain -p soleur-infra-privileged -c prd)"
export AWS_SECRET_ACCESS_KEY="$(doppler secrets get TF_STATE_AWS_SECRET_ACCESS_KEY --plain -p soleur-infra-privileged -c prd)"
doppler run -p soleur -c prd_terraform --name-transformer tf-var --preserve-env -- \
  terraform -chdir=apps/web-platform/infra apply -input=false -auto-approve
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

# G4h (#9879): a benign `moved` block between UNPROTECTED addresses (the shape placement-group.tf has live). The control
# must stay green on it, and the harness reads the collector's count of it back (IPT_G4H moved:1) as its non-vacuity.
cat > "$FIX/tree/apps/web-platform/infra/placement-group.tf" <<'EOF'
moved {
  from = hcloud_server.web
  to   = hcloud_server.web["web-1"]
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

cat > "$FIX/tree/apps/web-platform/infra/infra-app-project.tf" <<'EOF'
resource "doppler_project" "infra_app" {
  name        = "soleur-infra-app"
  description = "fixture"
}
resource "doppler_environment" "infra_app_prd" {
  project = doppler_project.infra_app.name
  slug    = "prd"
  name    = "Production"
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
if grep -q '^IPT_G4_FILES=0$' "$T/empty-tf.tsv.err" && wf_red "$T/empty-tf.tsv" "G4a:"; then
  pass "H5: Guard 4's instrument self-test — an empty \`.tf\` set reports 0 files and reds G4a"
else
  fail "H5: an empty .tf set did not red Guard 4" "$(grep -E 'IPT_G4_FILES|G4a' "$T/empty-tf.tsv.err" "$T/empty-tf.tsv" | cut -c1-200)"
fi
_EMPTYGH="$T/empty-gh"; assert_fixture_dir "$_EMPTYGH"
mkdir -p "$_EMPTYGH/tree/.github/workflows" "$_EMPTYGH/tree/.github/actions" "$_EMPTYGH/base" \
  || { printf 'FAIL SETUP: empty-gh fixture\n' >&2; exit 1; }
fixcensus "$_EMPTYGH" "$T/empty-gh.tsv" ""
if grep -q '^IPT_FILES_SCANNED=0$' "$T/empty-gh.tsv.err" && wf_red "$T/empty-gh.tsv" "G1a:"; then
  pass "H6: the dispatch self-test — an empty input tree reports '0 files scanned' and reds G1a (the suite's own SCAN FLOOR then exits non-zero)"
else
  fail "H6: an empty input tree did not report 0 files scanned" "$(head -2 "$T/empty-gh.tsv.err")"
fi
# G6g / G6g2 — Guard 6's own dispatch self-tests, over the same two empty trees. Without them an
# empty tree reds only G1a/G4a, and a Guard 6 that had stopped scanning would still read green.
if wf_red "$T/empty-gh.tsv" "G6a:"; then
  pass "G6g: an empty workflow tree reds a G6 row (G6a: 0 files, 0 referencing jobs), not only G1a"
else
  fail "G6g: an empty workflow tree left G6a green" "$(grep -F 'G6a:' "$T/empty-gh.tsv" | cut -c1-200)"
fi
if grep -qE "^FAIL$(printf '\t')G6c: .*\[0 \.tf files" "$T/empty-tf.tsv"; then
  pass "G6g2: an empty .tf set makes G6c report 0 files and red"
else
  fail "G6g2: an empty .tf set did not red G6c with a 0-file count" "$(grep -F 'G6c:' "$T/empty-tf.tsv" | cut -c1-200)"
fi

if grep -qE "^FAIL$(printf '\t')G7c: .*\[0 \.tf files" "$T/empty-tf.tsv"; then
  pass "G7g: an empty .tf set makes G7c report 0 files and red"
else
  fail "G7g: an empty .tf set did not red G7c with a 0-file count" "$(grep -F 'G7c:' "$T/empty-tf.tsv" | cut -c1-200)"
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
mutant_red() { # <name> <case-fn> [args...] — the named case must go RED (rc exactly 1); rc 2 is UNRESOLVED
  local name="$1" rc=0; shift
  "$@" || rc=$?
  case "$rc" in
    0) fail "M-$name: the named census row stayed GREEN against the mutant" ;;
    1) pass "M-$name: the named census row goes RED against the mutant" ;;
    *) fail "M-$name: UNRESOLVED (the case returned rc=$rc: a missing or empty census TSV is not a verdict)" ;;
  esac
}
# mutant_red self-test (ADR-193), both directions, in a subshell so the counters roll back.
_mr="$( (mutant_red st-green true >/dev/null; printf '%s,%s ' "$passes" "$fails"; mutant_red st-red false >/dev/null; printf '%s,%s' "$passes" "$fails") )"
if [ "$_mr" != "$passes,$((fails + 1)) $((passes + 1)),$((fails + 1))" ]; then
  printf 'FAIL INSTRUMENT: mutant_red self-test read "%s" (from %s,%s) — a GREEN case must fail, a RED case must pass\n' "$_mr" "$passes" "$fails" >&2; exit 1
fi
# The third direction (review #9453): a case that cannot reach a verdict (a deleted fixcensus leaves its TSV
# missing; an emptied one leaves it empty) must FAIL the row, not pass it as RED. Driven through the real
# wf_row / wf_clause / presence helpers, in subshells so the counters roll back.
: > "$T/st-empty.tsv"
for _st in "wf_row $T/st-missing.tsv G7f:" "wf_row $T/st-empty.tsv G7f:" "wf_clause $T/st-missing.tsv G7f: spelling" \
           "wf_clause $T/st-empty.tsv G7f: spelling"; do
  # shellcheck disable=SC2086  # the helper name and its arguments are split on purpose
  _mr="$( (mutant_red st-unresolved $_st >/dev/null 2>&1; printf '%s,%s' "$passes" "$fails") )"
  if [ "$_mr" != "$passes,$((fails + 1))" ]; then
    printf 'FAIL INSTRUMENT: mutant_red read a missing/empty TSV as RED for [%s] (got "%s" from %s,%s)\n' "$_st" "$_mr" "$passes" "$fails" >&2; exit 1
  fi
done
pass "H7: a mutant row whose census TSV is missing or empty (a deleted fixcensus) is UNRESOLVED and fails, never RED (wf_row, wf_clause, 4 drives)"
# H7b (review #9453, pass 2): the verdict helpers' OWN logic, driven with hand-written one-line TSVs and an exact rc
# each (printf + exit, never through the helpers it backstops). Without these, wf_clause could accept any red, or
# ignore its exclusion, wf_red could read UNRESOLVED as RED, and the empty-TSV guards could be dropped, with every
# mutant row above still green: their verdicts happen to coincide today.
printf 'bad\tG7f: demo\tclauses=[%s]\n' "'spelling'" > "$T/st-one.tsv"
printf 'bad\tG7f: demo\tclauses=[%s, %s]\n' "'spelling'" "'wrapper'" > "$T/st-two.tsv"
printf 'ok\tG7f: demo\t\n' > "$T/st-ok.tsv"
_h7b() { # <exact rc wanted> <helper> [args...]
  local want="$1" rc=0; shift
  "$@" >/dev/null 2>&1 || rc=$?
  [ "$rc" = "$want" ] || { printf 'FAIL INSTRUMENT: H7b [%s] returned rc %s, wanted %s\n' "$*" "$rc" "$want" >&2; exit 1; }
}
_h7b 1 wf_clause "$T/st-one.tsv" G7f: spelling             # the named clause fired: RED (1)
_h7b 0 wf_clause "$T/st-one.tsv" G7f: wrapper              # a DIFFERENT clause fired: not this row's clause (0)
_h7b 0 wf_clause "$T/st-two.tsv" G7f: spelling wrapper     # the excluded clause fired too: not isolated (0)
_h7b 1 wf_clause "$T/st-two.tsv" G7f: spelling             # two clauses fired, none excluded: RED (1)
_h7b 0 wf_clause "$T/st-ok.tsv" G7f: spelling              # an ok row is never RED (0)
_h7b 1 wf_row "$T/st-one.tsv" G7f:                         # a present, not-ok row: 1
_h7b 0 wf_row "$T/st-ok.tsv" G7f:                          # a present, ok row: 0
_h7b 2 wf_row "$T/st-empty.tsv" G7f:                       # an EMPTY TSV is UNRESOLVED, exactly 2 (awk alone says 0)
_h7b 2 wf_row "$T/st-missing.tsv" G7f:
_h7b 2 wf_clause "$T/st-empty.tsv" G7f: spelling
_h7b 2 wf_clause "$T/st-missing.tsv" G7f: spelling
_h7b 0 wf_red "$T/st-one.tsv" G7f:                         # wf_red is true on a RED row ...
_h7b 1 wf_red "$T/st-ok.tsv" G7f:                          # ... false on an ok row ...
_h7b 1 wf_red "$T/st-missing.tsv" G7f:                     # ... and false on a missing or an empty TSV (not a verdict)
_h7b 1 wf_red "$T/st-empty.tsv" G7f:
# An ABSENT row on a NON-empty TSV (the census crashed on a fixture, so the named row is not there) is 0, never RED:
# flipping wf_row's `(found && bad)` to `(!found || bad)` would read every absent row as RED.
_h7b 0 wf_row "$T/st-one.tsv" NoSuchRow:
_h7b 0 wf_clause "$T/st-one.tsv" NoSuchRow: spelling
_h7b 1 wf_red "$T/st-one.tsv" NoSuchRow:
# _h7b's OWN logic, in both directions, in subshells (it exits 1 on a mismatch): a drive with a deliberately wrong
# wanted rc must make _h7b exit 1. Neutering _h7b (`true || {`) would leave all 18 drives above vacuous.
for _w in "0 wf_row $T/st-one.tsv G7f:" "1 wf_row $T/st-ok.tsv G7f:" "2 wf_clause $T/st-one.tsv G7f: spelling"; do
  _hrc=0; ( _h7b $_w ) >/dev/null 2>&1 || _hrc=$?
  [ "$_hrc" = 1 ] || { printf 'FAIL INSTRUMENT: H7b self-test: _h7b accepted a WRONG wanted rc [%s] (subshell rc %s, wanted 1)\n' "$_w" "$_hrc" >&2; exit 1; }
done
pass "H7b: wf_row, wf_clause and wf_red return their exact verdicts on hand-written TSVs (named clause, other clause, excluded clause, ok, empty, missing, absent row; 18 drives) and _h7b itself rejects a wrong wanted rc (3 self-test drives)"

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
# `environment:` expression resolves a NON-TIER-B result literal. The predicate operand
# (`github.ref == 'refs/heads/main'`) is not an environment name — env_arms strips it — but
# `not-a-tier-b-env` is a RESULT literal the expression can resolve to, and it is outside the
# set. The scan must not stop at the compliant job, and the operand strip must not degenerate
# into ignoring every quoted literal. (#9755: the empty `||` arm alone is no longer this row's
# bad arm — it resolves to no environment, where env-scoped secrets are unreachable and the
# remaining ungated paths are policed by G1g, G1h and the G1j clauses pinned by rows g1-2b and
# g1-2c below — so the literal this row pins is the non-Tier-B RESULT.)
MUTDIR="$(fixcopy g1-2)"; assert_fixture_dir "$MUTDIR"
if mutate g1-2-second-job-non-tierb-arm "$MUTDIR/tree/.github/workflows/tierb-apply.yml" 7 '$a\  second:\n    runs-on: ubuntu-24.04\n    environment: ${{ github.ref == '"'"'refs/heads/main'"'"' \&\& '"'"'not-a-tier-b-env'"'"' || '"''"' }}\n    steps:\n      - run: echo x\n        env:\n          T: ${{ secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED }}'; then
  fixcensus "$MUTDIR" "$T/mut/g1-2.tsv" ""
  mutant_red g1-2-second-job-non-tierb-arm wf_row "$T/mut/g1-2.tsv" "G1c:"
fi
# Row 2b — the empty `||` arm PLUS a legacy fallback is the ungated-Tier-A combination: on a
# dispatch that resolves to no environment the loader's Tier-B input is empty and it would take
# the legacy arm. Omitting `doppler-token-legacy` (the tierb-conditional fixture's shape, and the
# live cutover job's #9755 shape) is what makes the empty arm fail-closed.
MUTDIR="$(fixcopy g1-2b)"; assert_fixture_dir "$MUTDIR"
if mutate g1-2b-empty-arm-legacy-fallback "$MUTDIR/tree/.github/workflows/tierb-conditional.yml" 1 '/doppler-token-infra-privileged:/a\          doppler-token-legacy: ${{ secrets.DOPPLER_TOKEN }}'; then
  fixcensus "$MUTDIR" "$T/mut/g1-2b.tsv" ""
  mutant_red g1-2b-empty-arm-legacy-fallback wf_row "$T/mut/g1-2b.tsv" "G1j:"
fi
# Row 2c (#9755 review) — the empty `||` arm PLUS an UNCONDITIONAL step env: naming a
# REPO-scoped privileged secret. GitHub resolves `secrets.DOPPLER_TOKEN_WRITE` on every
# dispatch — the unbound `''` one included — so this job is credentialed with no gate; the
# second `''`-arm G1j clause is the row that must red it.
MUTDIR="$(fixcopy g1-2c)"; assert_fixture_dir "$MUTDIR"
if mutate g1-2c-empty-arm-repo-scoped-secret "$MUTDIR/tree/.github/workflows/tierb-conditional.yml" 4 '/- run: echo done/a\      - name: Privileged noop\n        env:\n          X: ${{ secrets.DOPPLER_TOKEN_WRITE }}\n        run: echo x'; then
  fixcensus "$MUTDIR" "$T/mut/g1-2c.tsv" ""
  mutant_red g1-2c-empty-arm-repo-scoped-secret wf_row "$T/mut/g1-2c.tsv" "G1j:"
fi
# Row 2d (#9755 review round 2, NEW-F1) — a literal-FREE `environment:` expression
# (`${{ inputs.target }}`, no quoted literal anywhere) must stay RED. env_arms yields the
# __UNPARSEABLE__ sentinel, which G1c reads as a non-empty arm outside the set; a `[""]`
# fallback revert would read the same job as the exempt empty arm and this row would go
# green. The same job also reds G1j (it is a loader job whose arms fail the `all(...)`
# gate) — asserted on G1c because one mutant pins one named row.
MUTDIR="$(fixcopy g1-2d)"; assert_fixture_dir "$MUTDIR"
if mutate g1-2d-unparseable-environment "$MUTDIR/tree/.github/workflows/tierb-conditional.yml" 2 's|^    environment: .*$|    environment: ${{ inputs.target }}|'; then
  fixcensus "$MUTDIR" "$T/mut/g1-2d.tsv" ""
  mutant_red g1-2d-unparseable-environment wf_row "$T/mut/g1-2d.tsv" "G1c:"
fi
# Row 2e (#9755 review round 2) — the `''`-arm ban scans the WHOLE step dump, so a
# `run:`-inline `${{ secrets.* }}` interpolation reds exactly like an env: reference: the
# secret resolves at step start on every dispatch, the unbound one included.
MUTDIR="$(fixcopy g1-2e)"; assert_fixture_dir "$MUTDIR"
if mutate g1-2e-empty-arm-run-interpolation "$MUTDIR/tree/.github/workflows/tierb-conditional.yml" 1 '/- run: echo done/a\      - run: echo "${{ secrets.DOPPLER_TOKEN_WRITE }}"'; then
  fixcensus "$MUTDIR" "$T/mut/g1-2e.tsv" ""
  mutant_red g1-2e-empty-arm-run-interpolation wf_row "$T/mut/g1-2e.tsv" "G1j:"
fi
# Row 2f — JOB-level `env:` on the `''`-armed job: a workflow/job env: value naming the
# repo-scoped secret delivers it to every step on every dispatch — the jdump(j.env) limb
# (the G6a approach) is the one that sees it; a step-only scan reads green.
MUTDIR="$(fixcopy g1-2f)"; assert_fixture_dir "$MUTDIR"
if mutate g1-2f-empty-arm-job-env "$MUTDIR/tree/.github/workflows/tierb-conditional.yml" 2 '/^    environment:/a\    env:\n      X: ${{ secrets.DOPPLER_TOKEN_WRITE }}'; then
  fixcensus "$MUTDIR" "$T/mut/g1-2f.tsv" ""
  mutant_red g1-2f-empty-arm-job-env wf_row "$T/mut/g1-2f.tsv" "G1j:"
fi
# Row 2g — a reusable-workflow CALLER job (`uses:` at job level) that passes a named
# repo-scoped secret through its `secrets:` block: there are no steps to scan, so only the
# j.body secrets:/with: limb can red it.
MUTDIR="$(fixcopy g1-2g)"; assert_fixture_dir "$MUTDIR"
if mutate g1-2g-empty-arm-uses-secrets "$MUTDIR/tree/.github/workflows/tierb-conditional.yml" 5 '$a\  callee:\n    uses: ./.github/workflows/tierb-apply.yml\n    environment: ${{ (inputs.op == '"'"'a'"'"') \&\& '"'"'infra-privileged'"'"' || '"''"' }}\n    secrets:\n      T: ${{ secrets.DOPPLER_TOKEN_GIT_DATA_ROOT }}'; then
  fixcensus "$MUTDIR" "$T/mut/g1-2g.tsv" ""
  mutant_red g1-2g-empty-arm-uses-secrets wf_row "$T/mut/g1-2g.tsv" "G1j:"
fi
# Row 2h — `secrets: inherit` on a `''`-armed caller job: no name is spelled, so the regex
# cannot see it — it hands EVERY repo secret, the privileged names included, to the called
# workflow on the unbound dispatch. The explicit `inherit` check is the limb that reds it.
MUTDIR="$(fixcopy g1-2h)"; assert_fixture_dir "$MUTDIR"
if mutate g1-2h-empty-arm-uses-secrets-inherit "$MUTDIR/tree/.github/workflows/tierb-conditional.yml" 4 '$a\  callee:\n    uses: ./.github/workflows/tierb-apply.yml\n    environment: ${{ (inputs.op == '"'"'a'"'"') \&\& '"'"'infra-privileged'"'"' || '"''"' }}\n    secrets: inherit'; then
  fixcensus "$MUTDIR" "$T/mut/g1-2h.tsv" ""
  mutant_red g1-2h-empty-arm-uses-secrets-inherit wf_row "$T/mut/g1-2h.tsv" "G1j:"
fi
# Row 2i — the secrets context is CASE-INSENSITIVE (`secrets.doppler_token_write` resolves),
# so the ban's name match must be too; a lowercase-only spelling of the same escape reds it.
MUTDIR="$(fixcopy g1-2i)"; assert_fixture_dir "$MUTDIR"
if mutate g1-2i-empty-arm-lowercase-secret "$MUTDIR/tree/.github/workflows/tierb-conditional.yml" 4 '/- run: echo done/a\      - name: Privileged noop\n        env:\n          X: ${{ secrets.doppler_token_write }}\n        run: echo x'; then
  fixcensus "$MUTDIR" "$T/mut/g1-2i.tsv" ""
  mutant_red g1-2i-empty-arm-lowercase-secret wf_row "$T/mut/g1-2i.tsv" "G1j:"
fi
# Row 2j — DOPPLER_TOKEN_INNGEST_ARM is the third repo-scoped read/write Doppler token
# (github_actions_secret, inngest-arm-write-token.tf): it belongs to the same ban set, and a
# name set that forgot it would read this job green.
MUTDIR="$(fixcopy g1-2j)"; assert_fixture_dir "$MUTDIR"
if mutate g1-2j-empty-arm-inngest-arm-token "$MUTDIR/tree/.github/workflows/tierb-conditional.yml" 4 '/- run: echo done/a\      - name: Privileged noop\n        env:\n          X: ${{ secrets.DOPPLER_TOKEN_INNGEST_ARM }}\n        run: echo x'; then
  fixcensus "$MUTDIR" "$T/mut/g1-2j.tsv" ""
  mutant_red g1-2j-empty-arm-inngest-arm-token wf_row "$T/mut/g1-2j.tsv" "G1j:"
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
# job scored Tier A and G1h never saw it (workspaces-plaintext-forget.yml was the instance, retired in #6604 PR B).
MUTDIR="$(fixcopy g1-11)"; assert_fixture_dir "$MUTDIR"
printf 'name: zz\non: workflow_dispatch\nenv:\n  INFRA_DIR: apps/web-platform/infra\njobs:\n  forget:\n    runs-on: ubuntu-24.04\n    steps:\n      - uses: ./.github/actions/infra-credentials\n        with:\n          doppler-token-legacy: ${{ secrets.DOPPLER_TOKEN }}\n      - name: Forget\n        working-directory: ${{ env.INFRA_DIR }}\n        run: |\n          set -euo pipefail\n          terraform state rm \x27hcloud_volume.workspaces["web-1"]\x27\n' > "$MUTDIR/tree/.github/workflows/zz-forget.yml"
if fixture_written g1-11-state-rm-only-no-environment "$MUTDIR/tree/.github/workflows/zz-forget.yml"; then
  fixcensus "$MUTDIR" "$T/mut/g1-11.tsv" ""
  mutant_red g1-11-state-rm-only-no-environment wf_row "$T/mut/g1-11.tsv" "G1h:"
fi

# ── G1g: the read-only-first allowance must not be launderable by a comment ──────────
# (The allowance itself was removed in #9927 item 8b; this mutant stays as the proof that a comment naming the safe form still
# legalises nothing.) It was 1-of-1 on the live tree (`workspaces-luks-cutover::cutover`), so anything
# that satisfies it cheaply removes the row's only teeth. `_first` is a raw scan, so a single
# comment NAMING the read-only read above a bare privileged read used to make that read legal
# -- and "mention the safe form in a comment" is what a reader does when a lint complains.
MUTDIR="$(fixcopy g1-g1)"; assert_fixture_dir "$MUTDIR"
if mutate g1-g1-comment-laundered "$MUTDIR/tree/.github/workflows/tiera.yml" 2 \
     '$a\          # the read-only path is `doppler secrets get HCLOUD_TOKEN_READONLY --plain`\n          HCLOUD_TOKEN=$(doppler secrets get HCLOUD_TOKEN -p soleur -c prd_terraform --plain)'; then
  fixcensus "$MUTDIR" "$T/mut/g1-g1.tsv" ""
  mutant_red g1-g1-comment-laundered wf_row "$T/mut/g1-g1.tsv" "G1g:"
fi
# (#9927 item 8b) The allowance is DELETED, so what used to be this row's POSITIVE control is now
# its NEGATIVE one: a genuine read-only-first read followed by a bare read/write fallback is RED.
# Keeping the fixture byte-identical to the old positive control is the point -- it proves the
# row went RED because the allowance is gone, not because the fixture changed.
MUTDIR="$(fixcopy g1-g2)"; assert_fixture_dir "$MUTDIR"
if mutate g1-g2-ro-first-fallback-now-red "$MUTDIR/tree/.github/workflows/tiera.yml" 2 \
     '$a\          RO=$(doppler secrets get HCLOUD_TOKEN_READONLY -p soleur -c prd_terraform --plain)\n          HCLOUD_TOKEN=${RO:-$(doppler secrets get HCLOUD_TOKEN -p soleur -c prd_terraform --plain)}'; then
  fixcensus "$MUTDIR" "$T/mut/g1-g2.tsv" ""
  mutant_red g1-g2-ro-first-fallback-now-red wf_row "$T/mut/g1-g2.tsv" "G1g:"
fi

# (#9927 item 8b) SITE B shape: the config is named by a step `env:` (`DOPPLER_CONFIG: prd_terraform`),
# not by `-c`, which is how the infra-validation PR-plan step reads its Hetzner value. The
# command-line-only detection never saw it, so the fallback sat there unscanned.
MUTDIR="$(fixcopy g1-g3)"; assert_fixture_dir "$MUTDIR"
if mutate g1-g3-env-config-read "$MUTDIR/tree/.github/workflows/tiera.yml" 5 \
     '$a\      - name: Read\n        env:\n          DOPPLER_CONFIG: prd_terraform\n        run: |\n          HCLOUD_TOKEN=$(doppler secrets get HCLOUD_TOKEN --plain)'; then
  fixcensus "$MUTDIR" "$T/mut/g1-g3.tsv" ""
  mutant_red g1-g3-env-config-read wf_row "$T/mut/g1-g3.tsv" "G1g:"
fi

# (#9927 item 8b) G1j: drop the `environment:` key from ONE loader job. The loader's legacy arm
# exports only the read-only Hetzner token (or nothing), and no read/write token exists in Tier A, so a loader job with no Tier-B
# environment loses the privileged token silently. (G1j proves the environment is DECLARED; whether a job takes the Tier-B arm depends on the secret.)
MUTDIR="$(fixcopy g1-j1)"; assert_fixture_dir "$MUTDIR"
if mutate g1-j1-loader-job-without-environment "$MUTDIR/tree/.github/workflows/tierb-apply.yml" 1 \
     '0,/^    environment: infra-privileged$/{/^    environment: infra-privileged$/d}'; then
  fixcensus "$MUTDIR" "$T/mut/g1-j1.tsv" ""
  mutant_red g1-j1-loader-job-without-environment wf_row "$T/mut/g1-j1.tsv" "G1j:"
fi
# ...and the FLOOR: a tree whose workflows call the loader zero times is a RED, not a vacuous
# green (the population is what the row quantifies over).
MUTDIR="$(fixcopy g1-j2)"; assert_fixture_dir "$MUTDIR"
_j2n=0
for _f in "$MUTDIR"/tree/.github/workflows/*.yml; do
  _before="$(grep -cE '^[[:space:]]*-?[[:space:]]*uses:[[:space:]]*\./\.github/actions/infra-credentials[[:space:]]*$' "$_f" || true)"
  [ "${_before:-0}" -gt 0 ] || continue
  sed -E -i 's#^([[:space:]]*-?[[:space:]]*uses:[[:space:]]*)\./\.github/actions/infra-credentials[[:space:]]*$#\1./.github/actions/zz-not-the-loader#' "$_f"
  _j2n=$((_j2n + _before))
done
if [ "$_j2n" -gt 0 ]; then
  MUTANTS_RUN=$((MUTANTS_RUN + 1)); pass "M-g1-j2-zero-loader-jobs: removed $_j2n loader call(s) from a pristine copy"
  fixcensus "$MUTDIR" "$T/mut/g1-j2.tsv" ""
  mutant_red g1-j2-zero-loader-jobs wf_row "$T/mut/g1-j2.tsv" "G1j:"
else
  fail "M-g1-j2-zero-loader-jobs: found no loader call in the fixture workflows to remove"
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

# ── AC7b limb 3 / G1k (#10990): local .sh state-writers ────────────────────────────────
# Each row also asserts its CAUSE on the detail line where the contract names one (the
# g4e_cause convention): a later fixture edit that reds the row for a different reason would
# otherwise keep it "RED" while testing nothing it names.
g1k_cause() { # <name> <tsv> <detail substring>
  local d; d="$(awk -F'\t' 'index($2, "G1k:") == 1 { print $3 }' "$2")"
  case "$d" in
    *"$3"*) pass "M-$1: G1k reds for its named cause ($3)" ;;
    *) fail "M-$1: G1k's detail does not carry its named cause" "want [$3] got [${d:0:200}]" ;;
  esac
}
# Row k1 — a `.sh` state-writer sourcing the ambient backend pair from prd_terraform: the exact
# buggy shape the runbook's §Local Terraform invocation warns against (the read-only pair 403s
# the apply's state PutObject mid-run). The row must name the file.
MUTDIR="$(fixcopy g1-k1)"; assert_fixture_dir "$MUTDIR"
printf '#!/usr/bin/env bash\nset -euo pipefail\nexport AWS_ACCESS_KEY_ID="$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)"\nexport AWS_SECRET_ACCESS_KEY="$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)"\nterraform apply -input=false -auto-approve\n' > "$MUTDIR/tree/scripts/zz-prd-writer.sh"
if fixture_written g1-k1-prd-terraform-pair "$MUTDIR/tree/scripts/zz-prd-writer.sh"; then
  fixcensus "$MUTDIR" "$T/mut/g1-k1.tsv" ""
  mutant_red g1-k1-prd-terraform-pair wf_row "$T/mut/g1-k1.tsv" "G1k:"
  g1k_cause g1-k1-prd-terraform-pair "$T/mut/g1-k1.tsv" "scripts/zz-prd-writer.sh"
fi
# Row k2 — DISPATCH/ANTI-VACUITY: the guard's write-token set dropped (a fixture `apply` now reads
# as read-only), so no `.sh` classifies as a state-writer and the population floor goes unmet.
MUTDIR="$(fixcopy g1-k2)"; assert_fixture_dir "$MUTDIR"
cp "$T/ipt.py" "$T/ipt-g1-k2.py" || { printf 'FAIL SETUP: g1-k2 checker copy\n' >&2; exit 1; }
if mutate g1-k2-write-token-set-dropped "$T/ipt-g1-k2.py" 2 's/^SH_WRITE_VERBS = .*/SH_WRITE_VERBS = set()/'; then
  python3 "$T/ipt-g1-k2.py" "$MUTDIR/tree/.github" "$MUTDIR/tree" "" "$MUTDIR/base" > "$T/mut/g1-k2.tsv" 2> "$T/mut/g1-k2.tsv.err"
  mutant_red g1-k2-write-token-set-dropped wf_row "$T/mut/g1-k2.tsv" "G1k:"
fi
# Row k3 — SECOND MEMBER: the compliant scripts stay; a SECOND `.sh` state-writer carries the
# prd_terraform pair. A census that stops at the first member stays green here.
MUTDIR="$(fixcopy g1-k3)"; assert_fixture_dir "$MUTDIR"
printf '#!/usr/bin/env bash\nset -euo pipefail\nAWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)\nAWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)\nexport AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY\nterraform import hcloud_server.web 12345\n' > "$MUTDIR/tree/apps/cla-evidence/infra/zz-second.sh"
if fixture_written g1-k3-second-member-prd-pair "$MUTDIR/tree/apps/cla-evidence/infra/zz-second.sh"; then
  fixcensus "$MUTDIR" "$T/mut/g1-k3.tsv" ""
  mutant_red g1-k3-second-member-prd-pair wf_row "$T/mut/g1-k3.tsv" "G1k:"
  g1k_cause g1-k3-second-member-prd-pair "$T/mut/g1-k3.tsv" "apps/cla-evidence/infra/zz-second.sh"
fi
# Row k4 — HALF-SET: the compliant writer keeps only its ACCESS_KEY_ID leg (the secret leg
# deleted). The pair assertion is all-or-none — a half-set pair authenticates as nobody.
MUTDIR="$(fixcopy g1-k4)"; assert_fixture_dir "$MUTDIR"
if mutate g1-k4-half-set-pair "$MUTDIR/tree/apps/web-platform/scripts/bootstrap-live-verify.sh" 1 '/doppler secrets get TF_STATE_AWS_SECRET_ACCESS_KEY/d'; then
  fixcensus "$MUTDIR" "$T/mut/g1-k4.tsv" ""
  mutant_red g1-k4-half-set-pair wf_row "$T/mut/g1-k4.tsv" "G1k:"
  g1k_cause g1-k4-half-set-pair "$T/mut/g1-k4.tsv" "no Tier-B leg for AWS_SECRET_ACCESS_KEY"
fi
# Row k5 — HARNESS: the limb's classification key (the `terraform` invocation token) removed from
# a copy of the checker. Nothing classifies, the floor assertion on the two known files fails.
MUTDIR="$(fixcopy g1-k5)"; assert_fixture_dir "$MUTDIR"
cp "$T/ipt.py" "$T/ipt-g1-k5.py" || { printf 'FAIL SETUP: g1-k5 checker copy\n' >&2; exit 1; }
if mutate g1-k5-classification-key-removed "$T/ipt-g1-k5.py" 2 's/^SH_TF = re\.compile.*$/SH_TF = re.compile(r"NOSUCHTOKEN")/'; then
  python3 "$T/ipt-g1-k5.py" "$MUTDIR/tree/.github" "$MUTDIR/tree" "" "$MUTDIR/base" > "$T/mut/g1-k5.tsv" 2> "$T/mut/g1-k5.tsv.err"
  mutant_red g1-k5-classification-key-removed wf_row "$T/mut/g1-k5.tsv" "G1k:"
fi
# Row k6 — READ-ONLY CONTROL: a `.sh` reading the bare AWS_* pair from prd_terraform but whose
# only terraform verb is a READ (`plan`). The exemption is load-bearing: without it the pair
# check would red every read-only script.
MUTDIR="$(fixcopy g1-k6)"; assert_fixture_dir "$MUTDIR"
printf '#!/usr/bin/env bash\nset -euo pipefail\nAWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)\nAWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)\nexport AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY\nterraform plan -refresh=false -input=false\n' > "$MUTDIR/tree/scripts/zz-readonly.sh"
if fixture_written g1-k6-read-only-terraform "$MUTDIR/tree/scripts/zz-readonly.sh"; then
  fixcensus "$MUTDIR" "$T/mut/g1-k6.tsv" ""
  if grep -q "^ok$(printf '\t')G1k: " "$T/mut/g1-k6.tsv"; then
    pass "M-g1-k6-read-only-exempt: a .sh with a prd_terraform AWS_* read but only a READ terraform verb (plan) is EXEMPT — the exemption is load-bearing"
  else
    fail "M-g1-k6-read-only-exempt: a read-only .sh was censused as a state-writer" "$(grep G1k "$T/mut/g1-k6.tsv" | cut -c1-240)"
  fi
fi
# Row k7 — COMPLIANT CONTROL: the fixture's two `.sh` state-writers (both TF_STATE_AWS_* legs +
# terraform apply) stay GREEN on the unmutated control.
if grep -q "^ok$(printf '\t')G1k: " "$T/control.tsv"; then
  pass "M-g1-k7-compliant-writers: both fixture .sh state-writers (TF_STATE_AWS_* legs + terraform apply) are ACCEPTED by G1k"
else
  fail "M-g1-k7-compliant-writers: G1k refused the compliant fixture scripts" "$(grep G1k "$T/control.tsv" | cut -c1-240)"
fi
# Row k8 — VERB-SET WINDOW: the same buggy pair shape but the write invocation is
# `terraform destroy` — a state write (the rehearsal workflows run destroy against a Tier-B root
# for exactly that reason) that a verb set of apply/import/taint does not classify.
MUTDIR="$(fixcopy g1-k8)"; assert_fixture_dir "$MUTDIR"
printf '#!/usr/bin/env bash\nset -euo pipefail\nexport AWS_ACCESS_KEY_ID="$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)"\nexport AWS_SECRET_ACCESS_KEY="$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)"\nterraform destroy -auto-approve -input=false\n' > "$MUTDIR/tree/scripts/zz-destroy.sh"
if fixture_written g1-k8-destroy-verb "$MUTDIR/tree/scripts/zz-destroy.sh"; then
  fixcensus "$MUTDIR" "$T/mut/g1-k8.tsv" ""
  mutant_red g1-k8-destroy-verb wf_row "$T/mut/g1-k8.tsv" "G1k:"
  g1k_cause g1-k8-destroy-verb "$T/mut/g1-k8.tsv" "scripts/zz-destroy.sh"
fi
# Row k9 — RUN-INJECTION: the pair never touches a `secrets get`; a `doppler run` leg resolving
# to prd_terraform with no --name-transformer env-injects the bare read-only pair into the
# state-writing terraform it wraps.
MUTDIR="$(fixcopy g1-k9)"; assert_fixture_dir "$MUTDIR"
printf '#!/usr/bin/env bash\nset -euo pipefail\ndoppler run -p soleur -c prd_terraform -- terraform apply -input=false -auto-approve\n' > "$MUTDIR/tree/scripts/zz-run-inject.sh"
if fixture_written g1-k9-run-inject-prd-tf "$MUTDIR/tree/scripts/zz-run-inject.sh"; then
  fixcensus "$MUTDIR" "$T/mut/g1-k9.tsv" ""
  mutant_red g1-k9-run-inject-prd-tf wf_row "$T/mut/g1-k9.tsv" "G1k:"
  g1k_cause g1-k9-run-inject-prd-tf "$T/mut/g1-k9.tsv" "env-injects the read-only"
fi
# Row k10 — DOWNLOAD: `doppler secrets download` emits the whole config — pair included — into a
# file the writer then sources; no per-name `secrets get` leg exists for the name check to see.
MUTDIR="$(fixcopy g1-k10)"; assert_fixture_dir "$MUTDIR"
printf '#!/usr/bin/env bash\nset -euo pipefail\ndoppler secrets download -p soleur -c prd_terraform --format env > .tfenv\nset -a; . ./.tfenv; set +a\nterraform apply -input=false -auto-approve\n' > "$MUTDIR/tree/scripts/zz-download.sh"
if fixture_written g1-k10-secrets-download "$MUTDIR/tree/scripts/zz-download.sh"; then
  fixcensus "$MUTDIR" "$T/mut/g1-k10.tsv" ""
  mutant_red g1-k10-secrets-download wf_row "$T/mut/g1-k10.tsv" "G1k:"
  g1k_cause g1-k10-secrets-download "$T/mut/g1-k10.tsv" "emits the read-only"
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

# Row 8 — ACCEPT arm of the retired-state-absent allowance (#8285 PR B): the base declares a listed address, HEAD deletes
# it, and no job targets it. G4c must stay GREEN, or deleting a count-gated throwaway whose teardown already destroyed it
# has no sanctioned path. Its REFUSAL arm is row 3 (an unlisted deletion with no `removed` block stays RED).
MUTDIR="$(fixcopy g4-8)"; assert_fixture_dir "$MUTDIR"
if mutate g4-8-retired-absent-base "$MUTDIR/base/apps/web-platform/infra/github-app.tf" 3 '$a\resource "hcloud_server" "inngest_backstop_wipe" {\n  name = "x"\n}'; then
  fixcensus "$MUTDIR" "$T/mut/g4-8.tsv" ""
  if wf_row "$T/mut/g4-8.tsv" "G4c:"; then pass "M-g4-8-retired-state-absent: a listed, untargeted deletion is ACCEPTED by G4c"
  else fail "M-g4-8-retired-state-absent: G4c refused a listed, untargeted deletion" "$(grep G4c "$T/mut/g4-8.tsv" | cut -c1-240)"; fi
fi

# Row 9 — REFUSAL arm of the retired-state-absent allowance: the same listed deletion, but a PLAN step still
# `-target`s the address (the dispatch jobs target on a plan step and apply the saved plan, which an apply-body scan
# cannot see). The allowance must not be honoured, so G4c goes RED.
MUTDIR="$(fixcopy g4-9)"; assert_fixture_dir "$MUTDIR"
if mutate g4-9-retired-absent-base "$MUTDIR/base/apps/web-platform/infra/github-app.tf" 3 '$a\resource "hcloud_server" "inngest_backstop_wipe" {\n  name = "x"\n}' \
   && mutate g4-9-plan-step-target "$MUTDIR/tree/.github/workflows/tierb-apply.yml" 3 '/^          bash scripts\/tierb-helper\.sh$/a\      - name: Terraform plan\n        run: |\n          terraform plan -input=false -out=tfplan -target=hcloud_server.inngest_backstop_wipe'; then
  fixcensus "$MUTDIR" "$T/mut/g4-9.tsv" ""
  mutant_red g4-9-listed-but-targeted-on-a-plan-step wf_row "$T/mut/g4-9.tsv" "G4c:"
fi
# Row 10 — a PROTECTED address placed in RETIRED_STATE_ABSENT trips G4f. The allowance lives in the checker, so the
# mutant is a copy of the checker with the App identity added to the dict.
MUTDIR="$(fixcopy g4-10)"; assert_fixture_dir "$MUTDIR"
cp "$T/ipt.py" "$T/ipt-g4-10.py" || { printf 'FAIL SETUP: g4-10 checker copy\n' >&2; exit 1; }
if mutate g4-10-protected-in-allowance "$T/ipt-g4-10.py" 1 's/^(        )("hcloud_server\.inngest_backstop_wipe": ".*)$/\1"doppler_secret.github_app_id": "x",\n\1\2/'; then
  python3 "$T/ipt-g4-10.py" "$MUTDIR/tree/.github" "$MUTDIR/tree" "" "$MUTDIR/base" > "$T/mut/g4-10.tsv" 2> "$T/mut/g4-10.tsv.err"
  mutant_red g4-10-protected-in-allowance wf_row "$T/mut/g4-10.tsv" "G4f:"
fi
# Row 12 — a SOLE-COPY live store (the Inngest LUKS volume) placed in the allowance trips G4f, like the App identity.
MUTDIR="$(fixcopy g4-12)"; assert_fixture_dir "$MUTDIR"
cp "$T/ipt.py" "$T/ipt-g4-12.py" || { printf 'FAIL SETUP: g4-12 checker copy\n' >&2; exit 1; }
if mutate g4-12-live-store-in-allowance "$T/ipt-g4-12.py" 1 's/^(        )("hcloud_server\.inngest_backstop_wipe": ".*)$/\1"hcloud_volume.inngest_redis_luks": "x",\n\1\2/'; then
  python3 "$T/ipt-g4-12.py" "$MUTDIR/tree/.github" "$MUTDIR/tree" "" "$MUTDIR/base" > "$T/mut/g4-12.tsv" 2> "$T/mut/g4-12.tsv.err"
  mutant_red g4-12-live-store-in-allowance wf_row "$T/mut/g4-12.tsv" "G4f:"
fi
# Rows 13 and 14 — the two other spellings ANY_TARGET reads on a plan step: the space form `-target ADDR` and `-replace=ADDR`.
# Row 9 drives only `-target=`; dropping either alternative from the regex left the suite green.
for _spelling in "13:-target hcloud_server.inngest_backstop_wipe" "14:-replace=hcloud_server.inngest_backstop_wipe"; do
  _n="${_spelling%%:*}"; _arg="${_spelling#*:}"
  MUTDIR="$(fixcopy g4-$_n)"; assert_fixture_dir "$MUTDIR"
  if mutate g4-$_n-retired-absent-base "$MUTDIR/base/apps/web-platform/infra/github-app.tf" 3 '$a\resource "hcloud_server" "inngest_backstop_wipe" {\n  name = "x"\n}' \
     && mutate g4-$_n-plan-step-spelling "$MUTDIR/tree/.github/workflows/tierb-apply.yml" 3 '/^          bash scripts\/tierb-helper\.sh$/a\      - name: Terraform plan\n        run: |\n          terraform plan -input=false -out=tfplan '"$_arg"; then
    fixcensus "$MUTDIR" "$T/mut/g4-$_n.tsv" ""
    mutant_red g4-$_n-listed-but-targeted-by-spelling wf_row "$T/mut/g4-$_n.tsv" "G4c:"
  fi
done
# Row 11 — an allowance entry that HEAD declares again (re-declare, then delete, would ride it): G4g RED.
MUTDIR="$(fixcopy g4-11)"; assert_fixture_dir "$MUTDIR"
if mutate g4-11-redeclared "$MUTDIR/tree/apps/web-platform/infra/github-app.tf" 3 '$a\resource "hcloud_server" "inngest_backstop_wipe" {\n  name = "x"\n}'; then
  fixcensus "$MUTDIR" "$T/mut/g4-11.tsv" ""
  mutant_red g4-11-allowance-entry-redeclared wf_row "$T/mut/g4-11.tsv" "G4g:"
fi

# ── G4h (#9879): no `removed` / `moved` block over a sole-copy address ───────────────────────────────────────────────
# MUST-PASS arm first: the compliant fixture carries the two App-identity forget-only `removed` blocks (github-app.tf)
# and a benign `moved` block (placement-group.tf), and G4h and G4h2 stay green on all of them.
_g4h_ctl="$(sed -n 's/^IPT_G4H=//p' "$T/control.tsv.err" | tail -1)"
if grep -q 'from = doppler_secret.github_app_id' "$FIX/tree/apps/web-platform/infra/github-app.tf" \
   && grep -q 'from = doppler_secret.github_app_private_key' "$FIX/tree/apps/web-platform/infra/github-app.tf" \
   && wf_row "$T/control.tsv" "G4h:" && wf_row "$T/control.tsv" "G4h2:" \
   && grep -q "^ok$(printf '\t')G4h: " "$T/control.tsv" && grep -q "^ok$(printf '\t')G4h2: " "$T/control.tsv" \
   && case "$_g4h_ctl" in "removed:6 moved:1 probe:1 hits:0") true ;; *) false ;; esac; then
  pass "M-g4h-must-pass: the App-identity forget-only removed blocks and a benign moved block stay green on G4h and G4h2 ($_g4h_ctl)"
else
  fail "M-g4h-must-pass: G4h/G4h2 refused the App-identity forget-only blocks or a benign moved block, or the collector counts drifted" "ipt=$_g4h_ctl $(grep -E 'G4h' "$T/control.tsv" | cut -c1-200)"
fi
# Row 1 — a `removed` block forgetting the Inngest LUKS volume: its pins stop applying and the volume lives on unprotected.
MUTDIR="$(fixcopy g4h-1)"; assert_fixture_dir "$MUTDIR"
if mutate g4h-1-removed-sole-copy "$MUTDIR/tree/apps/web-platform/infra/github-app.tf" 6 '$a\removed {\n  from = hcloud_volume.inngest_redis_luks\n  lifecycle {\n    destroy = false\n  }\n}'; then
  fixcensus "$MUTDIR" "$T/mut/g4h-1.tsv" ""
  mutant_red g4h-1-removed-sole-copy wf_row "$T/mut/g4h-1.tsv" "G4h:"
fi
# Row 2 — a `moved` block renaming the volume (state-only): the address the pins name no longer exists.
MUTDIR="$(fixcopy g4h-2)"; assert_fixture_dir "$MUTDIR"
if mutate g4h-2-moved-from-sole-copy "$MUTDIR/tree/apps/web-platform/infra/placement-group.tf" 4 '$a\moved {\n  from = hcloud_volume.inngest_redis_luks\n  to   = hcloud_volume.renamed\n}'; then
  fixcensus "$MUTDIR" "$T/mut/g4h-2.tsv" ""
  mutant_red g4h-2-moved-from-sole-copy wf_row "$T/mut/g4h-2.tsv" "G4h:"
fi
# Row 2b — the same through `to`, and through an indexed address: neither attribute nor an index suffix may hide it.
MUTDIR="$(fixcopy g4h-2b)"; assert_fixture_dir "$MUTDIR"
if mutate g4h-2b-moved-to-sole-copy-indexed "$MUTDIR/tree/apps/web-platform/infra/placement-group.tf" 4 '$a\moved {\n  from = hcloud_volume.elsewhere\n  to   = hcloud_volume.workspaces_luks["web-1"]\n}'; then
  fixcensus "$MUTDIR" "$T/mut/g4h-2b.tsv" ""
  mutant_red g4h-2b-moved-to-sole-copy-indexed wf_row "$T/mut/g4h-2b.tsv" "G4h:"
fi
# Row 3 — SECOND-MEMBER: a compliant `removed` block for an UNPROTECTED address first, then a second one for a Doppler
# parent. A scan that stopped at the first compliant block would stay green.
MUTDIR="$(fixcopy g4h-3)"; assert_fixture_dir "$MUTDIR"
if mutate g4h-3-second-member-doppler-parent "$MUTDIR/tree/apps/web-platform/infra/github-app.tf" 12 '$a\removed {\n  from = doppler_service_token.unrelated\n  lifecycle {\n    destroy = false\n  }\n}\nremoved {\n  from = doppler_environment.inngest_prd\n  lifecycle {\n    destroy = false\n  }\n}'; then
  fixcensus "$MUTDIR" "$T/mut/g4h-3.tsv" ""
  mutant_red g4h-3-second-member-doppler-parent wf_row "$T/mut/g4h-3.tsv" "G4h:"
fi
# Must-pass — a `removed` block for an UNPROTECTED address with `lifecycle { destroy = false }` (the G4a shape) is green.
MUTDIR="$(fixcopy g4h-mp)"; assert_fixture_dir "$MUTDIR"
if mutate g4h-mp-unprotected-removed "$MUTDIR/tree/apps/web-platform/infra/github-app.tf" 6 '$a\removed {\n  from = doppler_service_token.unrelated\n  lifecycle {\n    destroy = false\n  }\n}'; then
  fixcensus "$MUTDIR" "$T/mut/g4h-mp.tsv" ""
  if wf_row "$T/mut/g4h-mp.tsv" "G4h:" && grep -q "^ok$(printf '\t')G4h: " "$T/mut/g4h-mp.tsv" \
     && grep -q '^IPT_G4H=removed:7 moved:1 probe:1 hits:0$' "$T/mut/g4h-mp.tsv.err"; then
    pass "M-g4h-mp-unprotected-removed: a compliant removed block for an unprotected address is ACCEPTED by G4h"
  else
    fail "M-g4h-mp-unprotected-removed: G4h refused a compliant removed block for an unprotected address" "$(grep G4h "$T/mut/g4h-mp.tsv" | cut -c1-240)"
  fi
fi
# Row 4 — `doppler_environment.inngest_prd` deleted from G4_PROTECTED while its `removed` block stays. G4h itself goes green
# (the address left the set), so the EXACT-SET row (G4h2) is what must red; the mutant is a copy of the checker.
MUTDIR="$(fixcopy g4h-4)"; assert_fixture_dir "$MUTDIR"
cp "$T/ipt.py" "$T/ipt-g4h-4.py" || { printf 'FAIL SETUP: g4h-4 checker copy\n' >&2; exit 1; }
if mutate g4h-4-removed-block-stays "$MUTDIR/tree/apps/web-platform/infra/github-app.tf" 6 '$a\removed {\n  from = doppler_environment.inngest_prd\n  lifecycle {\n    destroy = false\n  }\n}' \
   && mutate g4h-4-protected-entry-deleted "$T/ipt-g4h-4.py" 1 '/^    "doppler_environment\.inngest_prd",$/d'; then
  python3 "$T/ipt-g4h-4.py" "$MUTDIR/tree/.github" "$MUTDIR/tree" "" "$MUTDIR/base" > "$T/mut/g4h-4.tsv" 2> "$T/mut/g4h-4.tsv.err"
  mutant_red g4h-4-protected-entry-deleted wf_row "$T/mut/g4h-4.tsv" "G4h2:"
fi
# Row 5 — DISPATCH NON-VACUITY: the `moved` collector reads zero blocks (opener regex broken) on a fixture that holds a
# `moved` block over a sole-copy address. The collector probe must fail G4h; without it the moved clause is vacuously green.
MUTDIR="$(fixcopy g4h-5)"; assert_fixture_dir "$MUTDIR"
cp "$T/ipt.py" "$T/ipt-g4h-5.py" || { printf 'FAIL SETUP: g4h-5 checker copy\n' >&2; exit 1; }
if mutate g4h-5-moved-in-fixture "$MUTDIR/tree/apps/web-platform/infra/placement-group.tf" 4 '$a\moved {\n  from = hcloud_volume.inngest_redis_luks\n  to   = hcloud_volume.renamed\n}' \
   && mutate g4h-5-collector-blind "$T/ipt-g4h-5.py" 2 "/^MOVED_OPEN = /s/moved/movedX/"; then
  python3 "$T/ipt-g4h-5.py" "$MUTDIR/tree/.github" "$MUTDIR/tree" "" "$MUTDIR/base" > "$T/mut/g4h-5.tsv" 2> "$T/mut/g4h-5.tsv.err"
  if grep -q '^IPT_G4H=.* moved:0 probe:0 ' "$T/mut/g4h-5.tsv.err"; then
    mutant_red g4h-5-collector-blind wf_row "$T/mut/g4h-5.tsv" "G4h:"
  else
    fail "M-g4h-5-collector-blind: the blinded collector did not read zero moved blocks" "$(grep IPT_G4H "$T/mut/g4h-5.tsv.err")"
  fi
fi
# Row 6 — an INDENTED `moved` block over the volume. HCL ignores indentation; an opener anchored at column 0 read zero
# blocks here and left G4h and G4h2 green.
MUTDIR="$(fixcopy g4h-6)"; assert_fixture_dir "$MUTDIR"
if mutate g4h-6-indented-moved-sole-copy "$MUTDIR/tree/apps/web-platform/infra/placement-group.tf" 4 '$a\  moved {\n    from = hcloud_volume.inngest_redis_luks\n    to   = hcloud_volume.renamed\n  }'; then
  fixcensus "$MUTDIR" "$T/mut/g4h-6.tsv" ""
  mutant_red g4h-6-indented-moved-sole-copy wf_row "$T/mut/g4h-6.tsv" "G4h:"
fi
# Row 7 — an INDENTED `removed` block over a Doppler parent, compliant in every other respect (from + destroy = false).
MUTDIR="$(fixcopy g4h-7)"; assert_fixture_dir "$MUTDIR"
if mutate g4h-7-indented-removed-doppler-parent "$MUTDIR/tree/apps/web-platform/infra/github-app.tf" 6 '$a\  removed {\n    from = doppler_environment.inngest_prd\n    lifecycle {\n      destroy = false\n    }\n  }'; then
  fixcensus "$MUTDIR" "$T/mut/g4h-7.tsv" ""
  mutant_red g4h-7-indented-removed-doppler-parent wf_row "$T/mut/g4h-7.tsv" "G4h:"
fi
# Must-pass — a `removed` / `moved` look-alike that is NOT a block: a line comment, a heredoc body (indented, as a shell
# or JSON payload would carry it) and a block comment, all naming sole-copy addresses. The scan runs on comment- and
# heredoc-blanked text, so G4h stays green and the collector counts are the control's.
MUTDIR="$(fixcopy g4h-8)"; assert_fixture_dir "$MUTDIR"
if mutate g4h-8-lookalikes-in-comment-and-heredoc "$MUTDIR/tree/apps/web-platform/infra/github-app.tf" 19 '$a\# removed {\n#   from = hcloud_volume.inngest_redis_luks\n# }\nlocals {\n  g4h_note = <<-EOT\n    moved {\n      from = hcloud_volume.inngest_redis_luks\n      to   = hcloud_volume.renamed\n    }\n    removed {\n      from = doppler_environment.inngest_prd\n    }\n  EOT\n}\n/*\n  moved {\n    from = hcloud_volume.inngest_redis_luks\n  }\n*/'; then
  fixcensus "$MUTDIR" "$T/mut/g4h-8.tsv" ""
  if wf_row "$T/mut/g4h-8.tsv" "G4h:" && grep -q "^ok$(printf '\t')G4h: " "$T/mut/g4h-8.tsv" && grep -q "^ok$(printf '\t')G4h2: " "$T/mut/g4h-8.tsv" \
     && grep -q '^IPT_G4H=removed:6 moved:1 probe:1 hits:0$' "$T/mut/g4h-8.tsv.err" \
     && grep -q '^IPT_G4H4=raw_removed:7 raw_moved:3 scrubbed_removed:6 scrubbed_moved:1$' "$T/mut/g4h-8.tsv.err" && wf_red "$T/mut/g4h-8.tsv" "G4h4:"; then
    pass "M-g4h-8-lookalikes: a removed/moved look-alike in a comment, a heredoc body and a block comment is NOT read as a block (G4h stays green, counts unchanged; G4h4 reds on the 3 look-alikes the raw grep sees, by design)"
  else
    fail "M-g4h-8-lookalikes: G4h read a comment or heredoc look-alike as a block, or the collector counts drifted" "$(grep -E 'G4h' "$T/mut/g4h-8.tsv" | cut -c1-240) $(grep IPT_G4H "$T/mut/g4h-8.tsv.err")"
  fi
fi
# Rows g4h-9 / g4h-10 — the hcl_code_only scrubber's lexing, pinned by the third probe (_p3): each is a COPY of the checker
# with one branch neutered, run over the unmutated fixture. Neutering the `#`/`//` comment branch (g4h-9) or the string
# tracking (g4h-10) lets a `/*` or `<<EOF` inside a comment or string open a block comment / heredoc to EOF, which
# blanks a real `removed {` that follows; the probe reads fewer blocks and G4h reds ("moved collector probe failed").
MUTDIR="$(fixcopy g4h-9)"; assert_fixture_dir "$MUTDIR"
cp "$T/ipt.py" "$T/ipt-g4h-9.py" || { printf 'FAIL SETUP: g4h-9 checker copy\n' >&2; exit 1; }
if mutate g4h-9-line-comment-branch-neutered "$T/ipt-g4h-9.py" 2 '/^        if c == "#" or text\.startswith\("\/\/", i\):$/s/.*/        if False:/'; then
  python3 "$T/ipt-g4h-9.py" "$MUTDIR/tree/.github" "$MUTDIR/tree" "" "$MUTDIR/base" > "$T/mut/g4h-9.tsv" 2> "$T/mut/g4h-9.tsv.err"
  mutant_red g4h-9-line-comment-branch-neutered wf_row "$T/mut/g4h-9.tsv" "G4h:"
fi
MUTDIR="$(fixcopy g4h-10)"; assert_fixture_dir "$MUTDIR"
cp "$T/ipt.py" "$T/ipt-g4h-10.py" || { printf 'FAIL SETUP: g4h-10 checker copy\n' >&2; exit 1; }
if mutate g4h-10-string-tracking-neutered "$T/ipt-g4h-10.py" 2 "/^        if c == '\"':\$/s/.*/        if False:/"; then
  python3 "$T/ipt-g4h-10.py" "$MUTDIR/tree/.github" "$MUTDIR/tree" "" "$MUTDIR/base" > "$T/mut/g4h-10.tsv" 2> "$T/mut/g4h-10.tsv.err"
  mutant_red g4h-10-string-tracking-neutered wf_row "$T/mut/g4h-10.tsv" "G4h:"
fi
# Row g4h-11 — the LIVE-count pin (G4h4). An unterminated heredoc at the top of the file that holds the fixture's
# `removed` blocks makes hcl_code_only blank them to EOF: G4h itself stays green (a hidden block cannot be a hit; the
# fail-open case), so the count pin is the only row that can see it. Asserted both ways: G4h green, G4h4 red.
MUTDIR="$(fixcopy g4h-11)"; assert_fixture_dir "$MUTDIR"
if mutate g4h-11-unterminated-heredoc-hides-removed "$MUTDIR/tree/apps/web-platform/infra/github-app.tf" 1 '1i\x = <<EOT'; then
  fixcensus "$MUTDIR" "$T/mut/g4h-11.tsv" ""
  if grep -q "^ok$(printf '\t')G4h: " "$T/mut/g4h-11.tsv"; then
    mutant_red g4h-11-unterminated-heredoc-hides-removed wf_row "$T/mut/g4h-11.tsv" "G4h4:"
  else
    fail "M-g4h-11-unterminated-heredoc-hides-removed: G4h was not green, so the fixture does not model the fail-open case" "$(grep -E 'G4h' "$T/mut/g4h-11.tsv" | cut -c1-240)"
  fi
fi
# Row g4c-read-tf — Guard 4's declared-address reader must scrub. A copy of the checker whose read_tf returns the raw file
# reads a resource wrapped in a multi-line comment as declared; the G4c reader probe reds.
MUTDIR="$(fixcopy g4c-read-tf)"; assert_fixture_dir "$MUTDIR"
cp "$T/ipt.py" "$T/ipt-g4c-read-tf.py" || { printf 'FAIL SETUP: g4c-read-tf checker copy\n' >&2; exit 1; }
if mutate g4c-read-tf-unscrubbed "$T/ipt-g4c-read-tf.py" 2 '/^    return hcl_code_only\(open\(path, /s/.*/    return open(path, encoding="utf-8", errors="replace").read()/'; then
  python3 "$T/ipt-g4c-read-tf.py" "$MUTDIR/tree/.github" "$MUTDIR/tree" "" "$MUTDIR/base" > "$T/mut/g4c-read-tf.tsv" 2> "$T/mut/g4c-read-tf.tsv.err"
  mutant_red g4c-read-tf-unscrubbed wf_row "$T/mut/g4c-read-tf.tsv" "G4c:"
fi
# Row presence — G4 row PRESENCE (a count floor cannot tell a renamed or dropped row from a duplicated one), as G6h2/G7h2
# do for their guards: the pin must RED when G4h is removed from a copy of the control TSV.
G4_ROW_IDS="G4a G4b G4c G4d G4e G4f G4g G4h G4h2 G4h4"
# rows_present <tsv> <ids> — shared by g4_present/g6_present/g7_present (one idiom, three row-id lists): rc 0 = every id present, 1 = one absent, 2 = UNRESOLVED (TSV missing or empty).
rows_present() { [ -s "$1" ] || { printf 'UNRESOLVED: census TSV %s is missing or empty\n' "$1" >&2; return 2; }; local id; for id in $2; do awk -F'\t' -v p="$id: " 'index($2, p) == 1 { f = 1 } END { exit f ? 0 : 1 }' "$1" || return 1; done; }
g4_present() { rows_present "$1" "$G4_ROW_IDS"; }
if g4_present "$T/live.tsv" && g4_present "$T/control.tsv"; then
  pass "G4h3: every named G4 row id ($G4_ROW_IDS) is present in the live and the control census"
else
  fail "G4h3: a named G4 row id is missing from the live or the control census"
fi
grep -v "$(printf '\tG4h: ')" "$T/control.tsv" > "$T/mut/g4h-presence.tsv"
if [ "$(grep -c . "$T/mut/g4h-presence.tsv")" -eq "$(( $(grep -c . "$T/control.tsv") - 1 ))" ]; then
  MUTANTS_RUN=$((MUTANTS_RUN + 1)); pass "M-g4h-presence-row-missing: exactly one G4 row (G4h) removed from a copy of the control TSV"
  mutant_red g4h-presence-row-missing g4_present "$T/mut/g4h-presence.tsv"
else
  fail "M-g4h-presence-row-missing: the removal did not land on exactly one line"
fi

# ── G4c base-resolution legs (#9956): the PRODUCTION resolve_base_ref + materialize_base_dir
# path over a synthetic git repo. The compliant fixture's static `$FIX/base` tree cannot reach
# these semantics — the base there is handed to ipt.py already materialized. Here the base is
# RESOLVED from git history: M0 declares A, B, B2, RK; refs/remotes/origin/main is M1 = M0 plus
# terraform_data.main_c, the stand-in for a resource block main adds after the fork point (the
# #9956/#8904 false-red class: a stale checkout diffed against the moving tip reports it as an
# orphan). HEAD variants differ per leg; merge-base(HEAD, origin/main) is M0 for every leg
# except b8's orphan HEAD (which exercises the fallback arm). Only the
# G4c TSV row is read — unrelated fixture-row verdicts are out of scope by convention.
G4GIT="$T/g4git"; assert_fixture_dir "$G4GIT"
mkdir -p "$G4GIT/repo/apps/web-platform/infra/git-data-root-key" "$G4GIT/repo/.github" \
  || { printf 'FAIL SETUP: g4git mkdir\n' >&2; exit 1; }
cp -r "$FIX/tree/.github/." "$G4GIT/repo/.github/" \
  || { printf 'FAIL SETUP: g4git .github copy\n' >&2; exit 1; }
cat > "$G4GIT/repo/apps/web-platform/infra/main.tf" <<'EOF'
resource "terraform_data" "base_a" {}
resource "terraform_data" "base_b" {}
resource "terraform_data" "base_b2" {}
EOF
cat > "$G4GIT/repo/apps/web-platform/infra/git-data-root-key/main.tf" <<'EOF'
resource "terraform_data" "base_rk" {}
EOF
# _g4git — git against the fixture repo under the env -u scrub convention (hook-reachable code).
_g4git() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -C "$G4GIT/repo" "$@"; }
_g4git init -q -b main \
  && _g4git add -A && _g4git commit -qm "M0: base declares A B B2 RK" \
  || { printf 'FAIL SETUP: g4git M0\n' >&2; exit 1; }
G4_M0="$(_g4git rev-parse HEAD)"
printf 'resource "terraform_data" "main_c" {}\n' >> "$G4GIT/repo/apps/web-platform/infra/main.tf"
_g4git add -A && _g4git commit -qm "M1: main adds C post-fork" \
  || { printf 'FAIL SETUP: g4git M1\n' >&2; exit 1; }
G4_M1="$(_g4git rev-parse HEAD)"
_g4git update-ref refs/remotes/origin/main "$G4_M1" || { printf 'FAIL SETUP: g4git origin/main\n' >&2; exit 1; }
# M2 — a ref whose git-data-root-key dir holds only non-.tf content, the driver for b9's
# per-root floor arm (a root that lists but contributes zero .tf).
_g4git rm -q apps/web-platform/infra/git-data-root-key/main.tf \
  && mkdir -p "$G4GIT/repo/apps/web-platform/infra/git-data-root-key" \
  && printf 'placeholder\n' > "$G4GIT/repo/apps/web-platform/infra/git-data-root-key/README" \
  && _g4git add -A && _g4git commit -qm "M2: root-key holds no .tf" \
  || { printf 'FAIL SETUP: g4git M2\n' >&2; exit 1; }
G4_M2="$(_g4git rev-parse HEAD)"

# g4git_row <out-tsv> [<ref>] — resolve the base over the fixture repo, materialize it through
# the production helper, run the census on the repo's working tree. The IPT_BASE_REF scrub is
# load-bearing: it is a documented operator seam for the LIVE arm, and an ambient export must
# not silently change which resolution arm a fixture leg exercises. It is spelled `unset` inside
# the substitution — `env -u` cannot exec a shell FUNCTION (measured: ref="" → every leg
# 'base unavailable'). When <ref> is passed it is materialized verbatim (the override legs
# resolve it themselves first).
g4git_row() {
  local out="$1" dest ref
  dest="$T/g4base/$(basename "$out" .tsv)"
  assert_fixture_dir "$out"
  if [ "${2+set}" = set ]; then
    ref="$2"
  else
    # Helper markers are appended to the leg's .err so the per-leg artifact carries the
    # resolution+materialization story (and the deliberate failures in b7/b8d/b9 don't print
    # untagged `=fail` lines to the suite's merged stderr).
    ref="$(unset IPT_BASE_REF; resolve_base_ref "$G4GIT/repo" 2>>"$out.err")"
  fi
  assert_fixture_dir "$dest"
  materialize_base_dir "$G4GIT/repo" "$ref" "$dest" 2>>"$out.err" || dest=""
  python3 "$T/ipt.py" "$G4GIT/repo/.github" "$G4GIT/repo" "" "$dest" > "$out" 2>>"$out.err"
}
# g4c_detail <tsv> — the G4c row's detail field (orphans list / "base unavailable").
g4c_detail() { awk -F'\t' 'index($2, "G4c:") == 1 { print $3; exit }' "$1"; }

# b1 — resolution sanity: with HEAD at M0 the resolved base IS M0, not the M1 tip — and the
# merge-base arm announces itself on stderr. Both direct resolves are `unset`-scrubbed like
# g4git_row: without it an ambient IPT_BASE_REF reroutes the leg to the override arm (red via
# the marker clause — and a value-only assertion would have passed it silently).
_g4git checkout -q -B feat "$G4_M0" || { printf 'FAIL SETUP: g4git feat checkout\n' >&2; exit 1; }
_r1="$(unset IPT_BASE_REF; resolve_base_ref "$G4GIT/repo" 2>"$T/g4b1-resolve.err")"
if [ "$_r1" = "$G4_M0" ] && grep -q '^IPT_G4C_BASE_ARM=merge-base' "$T/g4b1-resolve.err"; then
  pass "G4c-b1: resolve_base_ref returns the merge-base (${G4_M0:0:10}), not the origin/main tip"
else
  fail "G4c-b1: resolve_base_ref did not return the merge-base" "want $G4_M0 got $(unset IPT_BASE_REF; resolve_base_ref "$G4GIT/repo" 2>/dev/null)"
fi

# b2 — the #9956 regression: HEAD == M0 while origin/main carries the post-fork addition C.
# The tip diff reported C as an orphan; the merge-base diff must not (GREEN row present+ok —
# grep, not wf_row, so an ABSENT row cannot read as green). The checkout is restated: every
# mutating leg re-anchors its own HEAD, so a leg order change can never silently lose this
# arm's precondition.
_g4git checkout -q -B feat "$G4_M0" || { printf 'FAIL SETUP: g4git feat checkout\n' >&2; exit 1; }
g4git_row "$T/g4b2-fork.tsv"
if grep -q "^ok$(printf '\t')G4c:" "$T/g4b2-fork.tsv"; then
  pass "G4c-b2: a resource origin/main adds after the fork point is not attributed to the diff as a deletion"
else
  fail "G4c-b2: a post-fork main-side addition read as an orphan (tip-diff regression)" "$(g4c_detail "$T/g4b2-fork.tsv")"
fi

# b3 — a real unclaimed deletion still reds: HEAD deletes base_b with no `removed` block; the
# orphan list names base_b and never main_c.
_g4git checkout -q -B feat "$G4_M0" || { printf 'FAIL SETUP: g4git feat reset\n' >&2; exit 1; }
cat > "$G4GIT/repo/apps/web-platform/infra/main.tf" <<'EOF'
resource "terraform_data" "base_a" {}
resource "terraform_data" "base_b2" {}
EOF
_g4git add -A && _g4git commit -qm "del base_b unclaimed" || { printf 'FAIL SETUP: g4git del-b\n' >&2; exit 1; }
g4git_row "$T/g4b3-del.tsv"
if wf_red "$T/g4b3-del.tsv" "G4c:"; then
  pass "G4c-b3: an unclaimed resource-block deletion at HEAD turns G4c RED under the merge-base"
else
  fail "G4c-b3: a real deletion stayed GREEN — the guard lost its true-positive arm" "$(g4c_detail "$T/g4b3-del.tsv")"
fi
_d="$(g4c_detail "$T/g4b3-del.tsv")"
if [[ "$_d" == *"terraform_data.base_b'"* && "$_d" != *"main_c"* ]]; then
  pass "G4c-b3d: the orphan list names base_b and not the post-fork main_c"
else
  fail "G4c-b3d: the orphan list does not isolate base_b" "$_d"
fi

# b4 — second-member-after-compliant-first: HEAD deletes only base_b2 of {A, B, B2}; orphans
# names base_b2 and not base_b (quote-terminated: 'base_b2' must not satisfy a 'base_b' match).
_g4git checkout -q -B feat "$G4_M0" || { printf 'FAIL SETUP: g4git feat reset\n' >&2; exit 1; }
cat > "$G4GIT/repo/apps/web-platform/infra/main.tf" <<'EOF'
resource "terraform_data" "base_a" {}
resource "terraform_data" "base_b" {}
EOF
_g4git add -A && _g4git commit -qm "del base_b2 unclaimed" || { printf 'FAIL SETUP: g4git del-b2\n' >&2; exit 1; }
g4git_row "$T/g4b4-del2.tsv"
if wf_red "$T/g4b4-del2.tsv" "G4c:"; then
  pass "G4c-b4: deleting the second of two base-declared resources turns G4c RED"
else
  fail "G4c-b4: the second-member deletion stayed GREEN" "$(g4c_detail "$T/g4b4-del2.tsv")"
fi
_d="$(g4c_detail "$T/g4b4-del2.tsv")"
if [[ "$_d" == *"terraform_data.base_b2'"* && "$_d" != *"terraform_data.base_b'"* ]]; then
  pass "G4c-b4d: the orphan list names base_b2 and not base_b"
else
  fail "G4c-b4d: the orphan list does not isolate base_b2" "$_d"
fi

# b5 — the claim path is intact under the new base: HEAD deletes base_b but carries
# `removed { from = terraform_data.base_b; lifecycle { destroy = false } }` → forgotten_addrs
# covers it → GREEN.
_g4git checkout -q -B feat "$G4_M0" || { printf 'FAIL SETUP: g4git feat reset\n' >&2; exit 1; }
cat > "$G4GIT/repo/apps/web-platform/infra/main.tf" <<'EOF'
resource "terraform_data" "base_a" {}
resource "terraform_data" "base_b2" {}
removed {
  from = terraform_data.base_b

  lifecycle {
    destroy = false
  }
}
EOF
_g4git add -A && _g4git commit -qm "del base_b claimed" || { printf 'FAIL SETUP: g4git del-claimed\n' >&2; exit 1; }
g4git_row "$T/g4b5-claimed.tsv"
if grep -q "^ok$(printf '\t')G4c:" "$T/g4b5-claimed.tsv"; then
  pass "G4c-b5: a deletion claimed by a removed{destroy=false} block stays GREEN under the merge-base"
else
  fail "G4c-b5: a claimed deletion went RED — the claim path broke under the new base" "$(g4c_detail "$T/g4b5-claimed.tsv")"
fi

# b6 — the override is honored verbatim: IPT_BASE_REF=<M1 tip> on the same HEAD==M0 fixture
# reproduces the pre-#9956 tip semantics (C reads as an orphan), proving the fixture
# discriminates old vs new rather than passing under both. The env-prefix runs inside the
# command substitution's own subshell, so the override cannot leak into the later legs — and
# g4git_row's `unset` scrub is bypassed by passing the resolved ref explicitly.
_g4git checkout -q -B feat "$G4_M0" || { printf 'FAIL SETUP: g4git feat reset\n' >&2; exit 1; }
_r6="$(IPT_BASE_REF="$G4_M1" resolve_base_ref "$G4GIT/repo" 2>"$T/g4b6-resolve.err")"
if [ "$_r6" = "$G4_M1" ] && grep -q '^IPT_G4C_BASE_ARM=override' "$T/g4b6-resolve.err"; then
  g4git_row "$T/g4b6-override.tsv" "$_r6"
  _d="$(g4c_detail "$T/g4b6-override.tsv")"
  if wf_red "$T/g4b6-override.tsv" "G4c:" && [[ "$_d" == *"terraform_data.main_c'"* ]]; then
    pass "G4c-b6: IPT_BASE_REF=<tip> materializes the tip verbatim and C reads as an orphan (the fixture discriminates old vs new semantics)"
  else
    fail "G4c-b6: the override arm did not reproduce tip semantics" "$(g4c_detail "$T/g4b6-override.tsv")"
  fi
else
  fail "G4c-b6: resolve_base_ref did not honor the IPT_BASE_REF override verbatim" "want $G4_M1 got $_r6"
fi

# b8 — merge-base-fails-with-tip-resolvable arm: an orphan-history HEAD shares no ancestor with
# origin/main, so resolution must return the fallback literal AND announce the arm on stderr —
# a silent fallback restores the #9956 false-red class with nothing observable. The materialized
# base then exercises tip semantics: main_c reads as an orphan, exactly as pre-#9956.
_g4git checkout -q --orphan g4-orphan || { printf 'FAIL SETUP: g4git orphan checkout\n' >&2; exit 1; }
_g4git add -A && _g4git commit -qm "orphan HEAD, no common ancestor" || { printf 'FAIL SETUP: g4git orphan commit\n' >&2; exit 1; }
_r8="$(unset IPT_BASE_REF; resolve_base_ref "$G4GIT/repo" 2>"$T/g4b8-resolve.err")"
if [ "$_r8" = "refs/remotes/origin/main" ] && grep -q '^IPT_G4C_BASE_ARM=fallback' "$T/g4b8-resolve.err"; then
  pass "G4c-b8: merge-base failure with a resolvable tip falls back AND announces the arm on stderr"
else
  fail "G4c-b8: the fallback arm did not engage or did not announce" "ref=$_r8 err=$(head -2 "$T/g4b8-resolve.err")"
fi
g4git_row "$T/g4b8-fallback.tsv"
_d="$(g4c_detail "$T/g4b8-fallback.tsv")"
if wf_red "$T/g4b8-fallback.tsv" "G4c:" && [[ "$_d" == *"terraform_data.main_c'"* ]]; then
  pass "G4c-b8d: the fallback arm exercises tip semantics — main_c reads as an orphan"
else
  fail "G4c-b8d: the fallback arm did not reproduce tip semantics" "$(g4c_detail "$T/g4b8-fallback.tsv")"
fi

# b7 — fail-closed preserved: with origin/main deleted and IPT_BASE_REF unset, resolution
# returns the fallback literal, the materialization cannot list it, and the row reports
# "base unavailable". The update-ref -d is safe because the ref is restored immediately after
# this leg — the restore, not leg order, is what keeps later legs on the full fixture.
_g4git update-ref -d refs/remotes/origin/main || { printf 'FAIL SETUP: g4git delete origin/main\n' >&2; exit 1; }
g4git_row "$T/g4b7-nobase.tsv"
_d="$(g4c_detail "$T/g4b7-nobase.tsv")"
if wf_red "$T/g4b7-nobase.tsv" "G4c:" && [ "$_d" = "base unavailable" ]; then
  pass "G4c-b7: no origin/main and no IPT_BASE_REF fails closed as 'base unavailable'"
else
  fail "G4c-b7: the unresolvable-base arm did not fail closed" "$(g4c_detail "$T/g4b7-nobase.tsv")"
fi
# Restore the ref so a later-appended leg starts from the full fixture state, not b7's deletion.
_g4git update-ref refs/remotes/origin/main "$G4_M1" || { printf 'FAIL SETUP: g4git restore origin/main\n' >&2; exit 1; }

# b9 — the per-root floor arm: a base ref whose root-key dir lists only non-.tf content fails
# materialization (the root would read base_declared={}, blind-greening its deletions), the
# materialize step names itself on stderr, and the census row reports 'base unavailable'.
_d9="$T/g4base/b9mat"; assert_fixture_dir "$_d9"
materialize_base_dir "$G4GIT/repo" "$G4_M2" "$_d9" 2>"$T/g4b9-mat.err" || _d9=""
if [ -z "$_d9" ] && grep -q '^IPT_G4C_BASE_MATERIALIZE=fail step=floor root=apps/web-platform/infra/git-data-root-key' "$T/g4b9-mat.err"; then
  pass "G4c-b9: a base ref whose root contributes zero .tf fails materialization and names the floor step"
else
  fail "G4c-b9: the per-root floor arm did not fire or did not announce" "err=$(head -2 "$T/g4b9-mat.err")"
fi
g4git_row "$T/g4b9-floor.tsv" "$G4_M2"
_d="$(g4c_detail "$T/g4b9-floor.tsv")"
if wf_red "$T/g4b9-floor.tsv" "G4c:" && [ "$_d" = "base unavailable" ]; then
  pass "G4c-b9d: the floor arm reaches the census row as 'base unavailable', never vacuous green"
else
  fail "G4c-b9d: the floor arm did not fail closed at the row" "$(g4c_detail "$T/g4b9-floor.tsv")"
fi

# parity — the bash materialization root list and ipt.py's GUARD4_ROOTS must enumerate the same
# set: a root added to ONE side alone leaves that root censused at HEAD with no materialized
# base (or materialized but never scanned), and its deletions slip silently. Extract both lists
# by their literal anchors and compare as sets. The py side takes the LAST assignment (python
# binds last); the sh side anchors on the code shape (an indented `for _r in apps/`, which a
# comment line or a differently-rooted loop cannot satisfy). Residual: a column-0
# `GUARD4_ROOTS +=`/`append` or an indented rebind escapes the py anchor, and a second
# `for _r in apps/` above the function would shadow the sh side — accepted grep-parity limits.
_g4_py_roots="$(grep -E '^GUARD4_ROOTS *=' "$T/ipt.py" | tail -1 | grep -oE '"apps/[^"]+"' | tr -d '"' | sort)"
_g4_sh_roots="$(grep -m1 '^[[:space:]]*for _r in apps/' "${BASH_SOURCE[0]}" | grep -oE 'apps/[a-z0-9_/-]+' | sort)"
if [ -n "$_g4_py_roots" ] && [ "$_g4_py_roots" = "$_g4_sh_roots" ]; then
  pass "G4c-parity: materialize_base_dir's root list equals ipt.py's GUARD4_ROOTS"
else
  fail "G4c-parity: the bash and python root lists diverged" "bash={$_g4_sh_roots} python={$_g4_py_roots}"
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
# ── Guard 7 (#9321): the soleur-infra-app container stays bare, its token stays operator-minted ──
# Row c — a stateful resource on the project in a NEW file; the same in a SECOND root (a check that
# stops at the first root is itself the defect); a project the guard cannot name (a variable); and
# the project's own declaration renamed (the declared limb).
MUTDIR="$(fixcopy g7c-secret)"; assert_fixture_dir "$MUTDIR"
printf 'resource "doppler_secret" "leak" {\n  project = doppler_project.infra_app.name\n  config  = "prd"\n  name    = "GITHUB_INFRA_APP_PRIVATE_KEY"\n  value   = "x"\n}\n' > "$MUTDIR/tree/apps/web-platform/infra/zz-g7.tf"
if fixture_written g7c-secret-on-project "$MUTDIR/tree/apps/web-platform/infra/zz-g7.tf"; then
  fixcensus "$MUTDIR" "$T/mut/g7c-secret.tsv" ""
  mutant_red g7c-secret-on-project wf_row "$T/mut/g7c-secret.tsv" "G7c:"
fi
MUTDIR="$(fixcopy g7c-root2)"; assert_fixture_dir "$MUTDIR"
printf 'resource "doppler_service_token" "leak" {\n  project = "soleur-infra-app"\n  config  = "prd"\n  name    = "t"\n  access  = "read"\n}\n' > "$MUTDIR/tree/apps/web-platform/infra/git-data-root-key/zz-g7.tf"
if fixture_written g7c-token-in-second-root "$MUTDIR/tree/apps/web-platform/infra/git-data-root-key/zz-g7.tf"; then
  fixcensus "$MUTDIR" "$T/mut/g7c-root2.tsv" ""
  mutant_red g7c-token-in-second-root wf_row "$T/mut/g7c-root2.tsv" "G7c:"
fi
MUTDIR="$(fixcopy g7c-var)"; assert_fixture_dir "$MUTDIR"
printf 'variable "p" {\n  type = string\n}\nresource "doppler_secret" "leak" {\n  project = var.p\n  config  = "prd"\n  name    = "X"\n  value   = "x"\n}\n' > "$MUTDIR/tree/apps/web-platform/infra/zz-g7.tf"
if fixture_written g7c-project-is-a-variable "$MUTDIR/tree/apps/web-platform/infra/zz-g7.tf"; then
  fixcensus "$MUTDIR" "$T/mut/g7c-var.tsv" ""
  mutant_red g7c-project-is-a-variable wf_row "$T/mut/g7c-var.tsv" "G7c:"
fi
MUTDIR="$(fixcopy g7c-rename)"; assert_fixture_dir "$MUTDIR"
if mutate g7c-project-renamed "$MUTDIR/tree/apps/web-platform/infra/infra-app-project.tf" 2 's/soleur-infra-app/soleur-infra-app2/'; then
  fixcensus "$MUTDIR" "$T/mut/g7c-rename.tsv" ""
  mutant_red g7c-project-renamed wf_row "$T/mut/g7c-rename.tsv" "G7c:"
fi
# Row d — a CI mint on the project; and the bootstrap script storing the token at REPOSITORY level.
MUTDIR="$(fixcopy g7d-mint)"; assert_fixture_dir "$MUTDIR"
if mutate g7d-token-mint "$MUTDIR/tree/.github/workflows/tierb-apply.yml" 1 '/^          bash scripts\/tierb-helper\.sh$/a\          doppler configs tokens create g7-leak -p soleur-infra-app -c prd --plain > /dev/null'; then
  fixcensus "$MUTDIR" "$T/mut/g7d-mint.tsv" ""
  mutant_red g7d-token-mint wf_row "$T/mut/g7d-mint.tsv" "G7d:"
fi
MUTDIR="$(fixcopy g7d-repo-level)"; assert_fixture_dir "$MUTDIR"
mkdir -p "$MUTDIR/tree/knowledge-base/project/specs/feat-g7" || { printf 'FAIL SETUP: g7d fixture dir\n' >&2; exit 1; }
printf '#!/usr/bin/env bash\n# stores the token for soleur-infra-app\nprintf %%s "$T" | gh secret set DOPPLER_TOKEN_INFRA_APP -R jikig-ai/soleur\n' > "$MUTDIR/tree/knowledge-base/project/specs/feat-g7/bootstrap.sh"
if fixture_written g7d-repo-level-secret "$MUTDIR/tree/knowledge-base/project/specs/feat-g7/bootstrap.sh"; then
  fixcensus "$MUTDIR" "$T/mut/g7d-repo.tsv" ""
  mutant_red g7d-repo-level-secret wf_row "$T/mut/g7d-repo.tsv" "G7d:"
fi

# Row c, second tranche (review panel) -- the escapes a pristine guard let through, fed to the pristine guard: the project's
# Terraform LABEL renamed (the address the regex used to hard-code), an environment/config ALIAS of the project, a data
# source and a project-less stateful resource, and a declaration that exists only inside a block comment.
MUTDIR="$(fixcopy g7c-label)"; assert_fixture_dir "$MUTDIR"
printf 'resource "doppler_secret" "leak" {\n  project = doppler_project.iapp.name\n  config  = "prd"\n  name    = "K"\n  value   = "x"\n}\n' > "$MUTDIR/tree/apps/web-platform/infra/zz-g7.tf"
if mutate g7c-project-label-renamed "$MUTDIR/tree/apps/web-platform/infra/infra-app-project.tf" 4 's/infra_app\b/iapp/g' \
   && fixture_written g7c-secret-on-renamed-label "$MUTDIR/tree/apps/web-platform/infra/zz-g7.tf"; then
  fixcensus "$MUTDIR" "$T/mut/g7c-label.tsv" ""
  mutant_red g7c-project-label-renamed wf_row "$T/mut/g7c-label.tsv" "G7c:"
fi
MUTDIR="$(fixcopy g7c-alias)"; assert_fixture_dir "$MUTDIR"
printf 'resource "doppler_environment" "stg" {\n  project = doppler_project.infra_app.name\n  slug    = "stg"\n  name    = "Staging"\n}\nresource "doppler_secret" "leak" {\n  project = doppler_environment.stg.project\n  config  = "stg"\n  name    = "K"\n  value   = "x"\n}\n' > "$MUTDIR/tree/apps/web-platform/infra/zz-g7.tf"
if fixture_written g7c-secret-through-an-environment-alias "$MUTDIR/tree/apps/web-platform/infra/zz-g7.tf"; then
  fixcensus "$MUTDIR" "$T/mut/g7c-alias.tsv" ""
  mutant_red g7c-secret-through-an-environment-alias wf_row "$T/mut/g7c-alias.tsv" "G7c:"
fi
MUTDIR="$(fixcopy g7c-data)"; assert_fixture_dir "$MUTDIR"
printf 'data "doppler_secrets" "leak" {\n  project = "soleur-infra-app"\n  config  = "prd"\n}\nresource "doppler_service_token" "noproject" {\n  config = "prd"\n  name   = "t"\n  access = "read"\n}\n' > "$MUTDIR/tree/apps/web-platform/infra/zz-g7.tf"
if fixture_written g7c-data-source-and-projectless-token "$MUTDIR/tree/apps/web-platform/infra/zz-g7.tf"; then
  fixcensus "$MUTDIR" "$T/mut/g7c-data.tsv" ""
  mutant_red g7c-data-source-and-projectless-token wf_row "$T/mut/g7c-data.tsv" "G7c:"
fi
MUTDIR="$(fixcopy g7c-comment)"; assert_fixture_dir "$MUTDIR"
if mutate g7c-declaration-in-block-comment "$MUTDIR/tree/apps/web-platform/infra/infra-app-project.tf" 4 '1s|^|/* |; $s|$| */|' ; then
  fixcensus "$MUTDIR" "$T/mut/g7c-comment.tsv" ""
  mutant_red g7c-declaration-in-block-comment wf_row "$T/mut/g7c-comment.tsv" "G7c:"
fi
# ENV_SECRETS: a Tier-A job (no Tier-B environment) that names the new token secret reds the environment-declaration rows.
MUTDIR="$(fixcopy g7-env-secret)"; assert_fixture_dir "$MUTDIR"
if mutate g7-token-secret-in-a-tier-a-job "$MUTDIR/tree/.github/workflows/tiera.yml" 1 '$a\          T: ${{ secrets.DOPPLER_TOKEN_INFRA_APP }}'; then
  fixcensus "$MUTDIR" "$T/mut/g7-envsecret.tsv" ""
  mutant_red g7-token-secret-in-a-tier-a-job wf_row "$T/mut/g7-envsecret.tsv" "G1b:"
fi
# Row e -- a cross-project reference to the project (it resolves with the reader's permissions).
MUTDIR="$(fixcopy g7e-xref)"; assert_fixture_dir "$MUTDIR"
if mutate g7e-cross-project-reference "$MUTDIR/tree/.github/workflows/tiera.yml" 1 '$a\          doppler secrets set K='"'"'${soleur-infra-app.prd.GITHUB_INFRA_APP_PRIVATE_KEY}'"'"' -p soleur -c prd_terraform --silent'; then
  fixcensus "$MUTDIR" "$T/mut/g7e-xref.tsv" ""
  mutant_red g7e-cross-project-reference wf_row "$T/mut/g7e-xref.tsv" "G7e:"
fi
# Row d, second tranche -- a mint with the project QUOTED, one inside a composite action, and the three stores a one-line
# `gh secret set --env` grep did not see (a trailing comment carrying `--env`, the library's repository-level helper, a REST PUT).
MUTDIR="$(fixcopy g7d-quoted)"; assert_fixture_dir "$MUTDIR"
if mutate g7d-mint-quoted-project "$MUTDIR/tree/.github/workflows/tierb-apply.yml" 1 '/^          bash scripts\/tierb-helper\.sh$/a\          doppler configs tokens create g7-leak -p "soleur-infra-app" -c prd --plain > /dev/null'; then
  fixcensus "$MUTDIR" "$T/mut/g7d-quoted.tsv" ""
  mutant_red g7d-mint-quoted-project wf_row "$T/mut/g7d-quoted.tsv" "G7d:"
fi
MUTDIR="$(fixcopy g7d-action)"; assert_fixture_dir "$MUTDIR"
mkdir -p "$MUTDIR/tree/.github/actions/zz-g7" || { printf 'FAIL SETUP: g7d action dir\n' >&2; exit 1; }
printf 'name: zz\ndescription: zz\nruns:\n  using: composite\n  steps:\n    - shell: bash\n      run: doppler --no-check-version configs tokens create g7-leak -p soleur-infra-app -c prd --plain > /dev/null\n' > "$MUTDIR/tree/.github/actions/zz-g7/action.yml"
if fixture_written g7d-mint-in-composite-action "$MUTDIR/tree/.github/actions/zz-g7/action.yml"; then
  fixcensus "$MUTDIR" "$T/mut/g7d-action.tsv" ""
  mutant_red g7d-mint-in-composite-action wf_row "$T/mut/g7d-action.tsv" "G7d:"
fi
g7_script() { # <dir> <name> <body> — a bootstrap script naming the project, in the tracked spec location
  mkdir -p "$1/tree/knowledge-base/project/specs/$2" || { printf 'FAIL SETUP: g7 spec dir\n' >&2; exit 1; }
  printf '#!/usr/bin/env bash\n# stores the token for soleur-infra-app\nGH_ENVIRONMENT="infra-privileged"\n%s\n' "$3" > "$1/tree/knowledge-base/project/specs/$2/bootstrap.sh"
}
MUTDIR="$(fixcopy g7d-comment)"; assert_fixture_dir "$MUTDIR"
g7_script "$MUTDIR" feat-g7 'printf %s "$T" | gh secret set DOPPLER_TOKEN_INFRA_APP -R jikig-ai/soleur # --env infra-privileged'
if fixture_written g7d-env-only-in-a-trailing-comment "$MUTDIR/tree/knowledge-base/project/specs/feat-g7/bootstrap.sh"; then
  fixcensus "$MUTDIR" "$T/mut/g7d-comment.tsv" ""
  mutant_red g7d-env-only-in-a-trailing-comment wf_row "$T/mut/g7d-comment.tsv" "G7d:"
fi
MUTDIR="$(fixcopy g7d-helper)"; assert_fixture_dir "$MUTDIR"
g7_script "$MUTDIR" feat-g7 'soleur_op_gh_secret_set "$REPO" DOPPLER_TOKEN_INFRA_APP "$T"'
if fixture_written g7d-library-repository-level-helper "$MUTDIR/tree/knowledge-base/project/specs/feat-g7/bootstrap.sh"; then
  fixcensus "$MUTDIR" "$T/mut/g7d-helper.tsv" ""
  mutant_red g7d-library-repository-level-helper wf_row "$T/mut/g7d-helper.tsv" "G7d:"
fi
MUTDIR="$(fixcopy g7d-put)"; assert_fixture_dir "$MUTDIR"
g7_script "$MUTDIR" feat-g7 'gh api -X PUT repos/jikig-ai/soleur/actions/secrets/DOPPLER_TOKEN_INFRA_APP -f encrypted_value="$T"'
if fixture_written g7d-rest-put-repository-secret "$MUTDIR/tree/knowledge-base/project/specs/feat-g7/bootstrap.sh"; then
  fixcensus "$MUTDIR" "$T/mut/g7d-put.tsv" ""
  mutant_red g7d-rest-put-repository-secret wf_row "$T/mut/g7d-put.tsv" "G7d:"
fi
MUTDIR="$(fixcopy g7d-env-pin)"; assert_fixture_dir "$MUTDIR"
g7_script "$MUTDIR" feat-g7 'printf %s "$T" | gh secret set DOPPLER_TOKEN_INFRA_APP --env "$GH_ENVIRONMENT" -R jikig-ai/soleur'
if mutate g7d-environment-variable-repointed "$MUTDIR/tree/knowledge-base/project/specs/feat-g7/bootstrap.sh" 2 's/^GH_ENVIRONMENT="infra-privileged"/GH_ENVIRONMENT="github-pages"/'; then
  fixcensus "$MUTDIR" "$T/mut/g7d-envpin.tsv" ""
  mutant_red g7d-environment-variable-repointed wf_row "$T/mut/g7d-envpin.tsv" "G7d:"
fi
# MUST-PASS direction (a guard that rejects everything also reds every row above): an archived compliant script with the
# `-e` short flag and a continuation line, plus an unrelated stateful resource whose text and comments mention the project.
MUTDIR="$(fixcopy g7-must-pass)"; assert_fixture_dir "$MUTDIR"
g7_script "$MUTDIR" archive/20260101-feat-g7 'printf %s "$T" | gh secret set DOPPLER_TOKEN_INFRA_APP \
  -e infra-privileged -R jikig-ai/soleur'
printf '# soleur-infra-app is documented here\n/* resource "doppler_secret" "x" { project = "soleur-infra-app" } */\nresource "doppler_secret" "ok" {\n  project = "soleur"  // not soleur-infra-app\n  config  = "prd"\n  name    = "K"\n  value   = "mentions soleur-infra-app only in a value"\n}\n' > "$MUTDIR/tree/apps/web-platform/infra/zz-g7-ok.tf"
fixcensus "$MUTDIR" "$T/mut/g7-pass.tsv" ""
if awk -F'\t' 'index($2, "G7c:") == 1 && $1 == "ok" { c = 1 } index($2, "G7d:") == 1 && $1 == "ok" && index($2, "[1 bootstrap script(s)]") { d = 1 } END { exit (c && d) ? 0 : 1 }' "$T/mut/g7-pass.tsv"; then
  pass "M-g7-must-pass: G7c and G7d stay GREEN on an archived compliant script (-e, continuation line) and an unrelated stateful resource that only mentions the project"
else
  fail "M-g7-must-pass: a G7 row reds a compliant input" "$(grep -E '^(FAIL)' "$T/mut/g7-pass.tsv" | cut -c1-240)"
fi
# ── G7f (#9321): every App-token call and the composite use only the two permitted source shapes ──
# Each row is written against the compliant control (a release-shaped caller on the narrow source, a
# loader-calling caller on the broad one, the composite with a narrow default, a two-literal allow-list and
# exactly two pinned reads). M1 flips the composite default; M2 widens its allow-list; M2b adds a third read of
# ANOTHER name (the App-value regex of clause (c) cannot see it); M3 appends a SECOND caller job in the
# same file after a compliant first one (a check that stops at the first member is the defect); M4 a Tier-A token;
# M5 the broad token in bracket spelling with the narrow default; M6 a NEW workflow that reads an App value
# inline; M7 an empty tree (a population of zero must not pass).
G7F_COMP='tree/.github/actions/mint-infra-app-token/action.yml'
MUTDIR="$(fixcopy g7f-m1)"; assert_fixture_dir "$MUTDIR"
if mutate g7f-m1-composite-default-flipped "$MUTDIR/$G7F_COMP" 2 's/^    default: soleur-infra-app$/    default: soleur-infra-privileged/'; then
  fixcensus "$MUTDIR" "$T/mut/g7f-m1.tsv" ""
  mutant_red g7f-m1-composite-default-flipped wf_row "$T/mut/g7f-m1.tsv" "G7f:"
fi
MUTDIR="$(fixcopy g7f-m2)"; assert_fixture_dir "$MUTDIR"
if mutate g7f-m2-allow-list-widened "$MUTDIR/$G7F_COMP" 2 's/soleur-infra-app\|soleur-infra-privileged\)/soleur-infra-app|soleur-infra-privileged|soleur)/'; then
  fixcensus "$MUTDIR" "$T/mut/g7f-m2.tsv" ""
  mutant_red g7f-m2-allow-list-widened wf_row "$T/mut/g7f-m2.tsv" "G7f:"
fi
MUTDIR="$(fixcopy g7f-m2b)"; assert_fixture_dir "$MUTDIR"
if mutate g7f-m2b-third-read-of-another-name "$MUTDIR/$G7F_COMP" 1 '/^        PEM=\$\(/a\        X=$(doppler secrets get HCLOUD_TOKEN --plain --project soleur-infra-app --config prd 2>/dev/null)'; then
  fixcensus "$MUTDIR" "$T/mut/g7f-m2b.tsv" ""
  mutant_red g7f-m2b-third-read-of-another-name wf_row "$T/mut/g7f-m2b.tsv" "G7f:"
fi
MUTDIR="$(fixcopy g7f-m3)"; assert_fixture_dir "$MUTDIR"
if mutate g7f-m3-second-caller-broad-no-loader "$MUTDIR/tree/.github/workflows/release.yml" 10 '$a\  second:\n    runs-on: ubuntu-24.04\n    environment: infra-privileged\n    steps:\n      - name: Mint again\n        uses: ./.github/actions/mint-infra-app-token\n        with:\n          doppler-token: ${{ secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED }}\n          doppler-project: soleur-infra-privileged\n          installation-id: "166065653"'; then
  fixcensus "$MUTDIR" "$T/mut/g7f-m3.tsv" ""
  mutant_red g7f-m3-second-caller-broad-no-loader wf_row "$T/mut/g7f-m3.tsv" "G7f:"
fi
MUTDIR="$(fixcopy g7f-m4)"; assert_fixture_dir "$MUTDIR"
if mutate g7f-m4-tier-a-token "$MUTDIR/tree/.github/workflows/release.yml" 2 's/^          doppler-token: \$\{\{ secrets\.DOPPLER_TOKEN_INFRA_APP \}\}$/          doppler-token: ${{ secrets.DOPPLER_TOKEN }}/'; then
  fixcensus "$MUTDIR" "$T/mut/g7f-m4.tsv" ""
  mutant_red g7f-m4-tier-a-token wf_row "$T/mut/g7f-m4.tsv" "G7f:"
fi
MUTDIR="$(fixcopy g7f-m5)"; assert_fixture_dir "$MUTDIR"
if mutate g7f-m5-broad-token-bracket-spelling-narrow-default "$MUTDIR/tree/.github/workflows/release.yml" 2 "s/^          doppler-token: \\$\\{\\{ secrets\\.DOPPLER_TOKEN_INFRA_APP \\}\\}\$/          doppler-token: \\$\\{\\{ secrets['DOPPLER_TOKEN_INFRA_PRIVILEGED'] \\}\\}/"; then
  fixcensus "$MUTDIR" "$T/mut/g7f-m5.tsv" ""
  mutant_red g7f-m5-broad-token-bracket-spelling-narrow-default wf_row "$T/mut/g7f-m5.tsv" "G7f:"
fi
MUTDIR="$(fixcopy g7f-m6)"; assert_fixture_dir "$MUTDIR"
if mutate g7f-m6-inline-app-key-read "$MUTDIR/tree/.github/workflows/tiera.yml" 1 '$a\          PEM=$(doppler secrets get GITHUB_INFRA_APP_PRIVATE_KEY --plain --project soleur-infra-app --config prd)'; then
  fixcensus "$MUTDIR" "$T/mut/g7f-m6.tsv" ""
  mutant_red g7f-m6-inline-app-key-read wf_row "$T/mut/g7f-m6.tsv" "G7f:"
fi
# ── clause-isolated rows (review #9453): each pins ONE G7f clause through the `clauses=[...]` the row detail
# lists, and a clause a second one could also catch is told apart by naming the one that must NOT fire. Every
# mutant below keeps the rest of the tree compliant, so only its own clause is available to catch it.
# M2b' -- a third read of another name whose project IS "$DOPPLER_SOURCE": only the read-COUNT clause sees it
# (M2b hard-codes the project, so the per-read argv clause catches that one too and hides a deleted count clause).
MUTDIR="$(fixcopy g7f-m2bp)"; assert_fixture_dir "$MUTDIR"
if mutate g7f-m2bp-third-read-via-source-variable "$MUTDIR/$G7F_COMP" 1 '/^        PEM=\$\(/a\        X=$(doppler secrets get HCLOUD_TOKEN --plain --project "$DOPPLER_SOURCE" --config prd 2>/dev/null)'; then
  fixcensus "$MUTDIR" "$T/mut/g7f-m2bp.tsv" ""
  mutant_red g7f-m2bp-third-read-via-source-variable wf_clause "$T/mut/g7f-m2bp.tsv" "G7f:" read-count read-argv
fi
# M2c -- exactly two App-value reads, but the project is hard-coded: only the per-read argv clause sees it.
MUTDIR="$(fixcopy g7f-m2c)"; assert_fixture_dir "$MUTDIR"
if mutate g7f-m2c-two-reads-hard-coded-project "$MUTDIR/$G7F_COMP" 4 's/--project "\$DOPPLER_SOURCE"/--project soleur-infra-app/'; then
  fixcensus "$MUTDIR" "$T/mut/g7f-m2c.tsv" ""
  mutant_red g7f-m2c-two-reads-hard-coded-project wf_clause "$T/mut/g7f-m2c.tsv" "G7f:" read-argv read-count
fi
# M-run -- a `doppler run` (not `secrets get`) line in the composite: the `|run` alternative of the read regex.
MUTDIR="$(fixcopy g7f-mrun)"; assert_fixture_dir "$MUTDIR"
if mutate g7f-mrun-doppler-run-in-composite "$MUTDIR/$G7F_COMP" 1 '/^        PEM=\$\(/a\        doppler run --project "$DOPPLER_SOURCE" --config prd -- true'; then
  fixcensus "$MUTDIR" "$T/mut/g7f-mrun.tsv" ""
  mutant_red g7f-mrun-doppler-run-in-composite wf_clause "$T/mut/g7f-mrun.tsv" "G7f:" read-count read-argv
fi
# M-run2 -- the same read with global flags before the subcommand (`doppler --project ... run`): the anchored
# `run` still sees it, so narrowing the regex to `doppler run` alone cannot pass.
MUTDIR="$(fixcopy g7f-mrun2)"; assert_fixture_dir "$MUTDIR"
if mutate g7f-mrun2-doppler-flags-then-run "$MUTDIR/$G7F_COMP" 1 '/^        PEM=\$\(/a\        doppler --project "$DOPPLER_SOURCE" --config prd run -- true'; then
  fixcensus "$MUTDIR" "$T/mut/g7f-mrun2.tsv" ""
  mutant_red g7f-mrun2-doppler-flags-then-run wf_clause "$T/mut/g7f-mrun2.tsv" "G7f:" read-count read-argv
fi
# M-run3 -- the same read with a global flag whose quoted value contains a space (`--token "$(cat f)" run`): the
# old one-word-per-flag anchor missed it, so a third, unpinned read went unseen.
MUTDIR="$(fixcopy g7f-mrun3)"; assert_fixture_dir "$MUTDIR"
if mutate g7f-mrun3-doppler-spaced-flag-value-then-run "$MUTDIR/$G7F_COMP" 1 '/^        PEM=\$\(/a\        doppler --token "$(cat /dev/null)" --project "$DOPPLER_SOURCE" --config prd run -- true'; then
  fixcensus "$MUTDIR" "$T/mut/g7f-mrun3.tsv" ""
  mutant_red g7f-mrun3-doppler-spaced-flag-value-then-run wf_clause "$T/mut/g7f-mrun3.tsv" "G7f:" read-count read-argv
fi
# M-env -- the DOPPLER_SOURCE env mapping hard-wired to the broad literal: default, allow-list and both reads
# still look compliant, so only the env-map clause sees it.
MUTDIR="$(fixcopy g7f-menv)"; assert_fixture_dir "$MUTDIR"
if mutate g7f-menv-source-env-hard-wired "$MUTDIR/$G7F_COMP" 2 's/^        DOPPLER_SOURCE: \$\{\{ inputs\.doppler-project \}\}$/        DOPPLER_SOURCE: soleur-infra-privileged/'; then
  fixcensus "$MUTDIR" "$T/mut/g7f-menv.tsv" ""
  mutant_red g7f-menv-source-env-hard-wired wf_clause "$T/mut/g7f-menv.tsv" "G7f:" env-map read-argv
fi
# M-wrongtok -- the broad shape (explicit broad project, in the loader job) with the NARROW token.
MUTDIR="$(fixcopy g7f-mwrongtok)"; assert_fixture_dir "$MUTDIR"
if mutate g7f-mwrongtok-broad-project-narrow-token "$MUTDIR/tree/.github/workflows/marketplace-verify.yml" 2 's/^          doppler-token: \$\{\{ secrets\.DOPPLER_TOKEN_INFRA_PRIVILEGED \}\}$/          doppler-token: ${{ secrets.DOPPLER_TOKEN_INFRA_APP }}/'; then
  fixcensus "$MUTDIR" "$T/mut/g7f-mwrongtok.tsv" ""
  mutant_red g7f-mwrongtok-broad-project-narrow-token wf_clause "$T/mut/g7f-mwrongtok.tsv" "G7f:" caller-shape loader
fi
# M-remote / M-dotdot -- the compliant narrow caller, with the composite named by its remote spelling and by a
# `..` path: neither matches the `./.github/actions/<dir>` mapping the other census rows use, so only the
# spelling clause (G7f resolves both to the composite and refuses a non-canonical form) sees them.
MUTDIR="$(fixcopy g7f-mremote)"; assert_fixture_dir "$MUTDIR"
if mutate g7f-mremote-remote-spelling "$MUTDIR/tree/.github/workflows/release.yml" 2 's#^        uses: \./\.github/actions/mint-infra-app-token$#        uses: jikig-ai/soleur/.github/actions/mint-infra-app-token@main#'; then
  fixcensus "$MUTDIR" "$T/mut/g7f-mremote.tsv" ""
  mutant_red g7f-mremote-remote-spelling wf_clause "$T/mut/g7f-mremote.tsv" "G7f:" spelling caller-shape
fi
MUTDIR="$(fixcopy g7f-mdotdot)"; assert_fixture_dir "$MUTDIR"
if mutate g7f-mdotdot-dot-dot-spelling "$MUTDIR/tree/.github/workflows/release.yml" 2 's#^        uses: \./\.github/actions/mint-infra-app-token$#        uses: ./.github/actions/../actions/mint-infra-app-token#'; then
  fixcensus "$MUTDIR" "$T/mut/g7f-mdotdot.tsv" ""
  mutant_red g7f-mdotdot-dot-dot-spelling wf_clause "$T/mut/g7f-mdotdot.tsv" "G7f:" spelling caller-shape
fi
# M-wrapper -- a NEW composite action whose own `runs.steps` call the mint composite (the caller loop used to
# walk only `jobs.*.steps`, so a wrapper forwarding the broad project and an `inputs.*` token was invisible).
MUTDIR="$(fixcopy g7f-mwrapper)"; assert_fixture_dir "$MUTDIR"
mkdir -p "$MUTDIR/tree/.github/actions/zz-wrap" || { printf 'FAIL SETUP: g7f-mwrapper dir\n' >&2; exit 1; }
cat > "$MUTDIR/tree/.github/actions/zz-wrap/action.yml" <<'EOF'
name: "Wrapper (fixture)"
description: "fixture composite that wraps the mint composite"
inputs:
  tok:
    required: true
runs:
  using: composite
  steps:
    - name: Mint through the wrapper
      uses: ./.github/actions/mint-infra-app-token
      with:
        doppler-token: ${{ inputs.tok }}
        doppler-project: soleur-infra-privileged
        installation-id: "166065653"
EOF
if fixture_written g7f-mwrapper-composite-wraps-the-mint "$MUTDIR/tree/.github/actions/zz-wrap/action.yml"; then
  fixcensus "$MUTDIR" "$T/mut/g7f-mwrapper.tsv" ""
  mutant_red g7f-mwrapper-composite-wraps-the-mint wf_clause "$T/mut/g7f-mwrapper.tsv" "G7f:" wrapper spelling
fi
# M7 -- the empty tree (no caller, no composite): "0 scanned" must not pass. It reds through the
# composite-missing clause AND the caller-count clause; it does not measure the live-tree 3-caller pin.
MUTANTS_RUN=$((MUTANTS_RUN + 1))
mutant_red g7f-m7-empty-tree wf_row "$T/empty-gh.tsv" "G7f:"
# H2 (must-PASS, non-canonical): the composite mentions the broad project and a would-be extra read ONLY in
# comments; the loader-calling caller lists its `with:` keys in a different order and spells the broad token
# with whitespace around the dot; the release caller spells the narrow token the same way. (The bracket
# spelling is not usable here: G1e bans `secrets[...]` repo-wide, so a bracket-spelled caller reds that row.)
# All of it is compliant, so G7f AND every other census row must stay GREEN (a guard that rejects
# everything also reds every mutant above).
MUTDIR="$(fixcopy g7f-h2)"; assert_fixture_dir "$MUTDIR"
python3 - "$MUTDIR/$G7F_COMP" <<'PY' || { printf 'FAIL SETUP: g7f-h2 composite\n' >&2; exit 1; }
import sys
p = sys.argv[1]
s = open(p).read()
old = '        set -euo pipefail\n'
assert s.count(old) == 1
cmt = ('        # the broad project soleur-infra-privileged is the second allowed source\n'
       '        # doppler secrets get HCLOUD_TOKEN --plain --project soleur-infra-privileged --config prd\n')
open(p, "w").write(s.replace(old, old + cmt, 1))
PY
printf 'name: fixture marketplace verify (reordered keys, spaced spelling)\non: workflow_dispatch\njobs:\n  verify:\n    runs-on: ubuntu-24.04\n    environment: infra-privileged\n    steps:\n      - name: Mint\n        uses: ./.github/actions/mint-infra-app-token\n        with:\n          installation-id: "166065653"\n          doppler-project: soleur-infra-privileged\n          doppler-token: ${{ secrets . DOPPLER_TOKEN_INFRA_PRIVILEGED }}\n      - uses: ./.github/actions/infra-credentials\n        with:\n          doppler-token-infra-privileged: ${{ secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED }}\n' > "$MUTDIR/tree/.github/workflows/marketplace-verify.yml"
sed -i -E "s/^          doppler-token: \\$\\{\\{ secrets\\.DOPPLER_TOKEN_INFRA_APP \\}\\}\$/          doppler-token: \\$\\{\\{ secrets . DOPPLER_TOKEN_INFRA_APP \\}\\}/" "$MUTDIR/tree/.github/workflows/release.yml"
fixcensus "$MUTDIR" "$T/mut/g7f-h2.tsv" ""
if grep -q 'secrets \. DOPPLER_TOKEN_INFRA_APP' "$MUTDIR/tree/.github/workflows/release.yml" \
   && grep -q '^ok	G7f:' "$T/mut/g7f-h2.tsv" && [ -z "$(awk -F'\t' '$1 != "ok"' "$T/mut/g7f-h2.tsv")" ]; then
  pass "M-g7f-h2-must-pass: G7f and every other census row stay GREEN on a compliant tree with comment-only mentions, reordered with: keys and spaced spellings"
else
  fail "M-g7f-h2-must-pass: a compliant non-canonical tree reds a census row" "$(awk -F'\t' '$1 != "ok"' "$T/mut/g7f-h2.tsv" | cut -c1-240)"
fi
# H3 (must-PASS): prose that merely contains the English word "run" on a line starting with `doppler` is not a
# read. The composite gets a CLI-presence check whose message says "run the install step"; the read regex used to
# match the bare word and red read-count and read-argv on it. The real `doppler run` rows (M-run, M-run2) still red.
MUTDIR="$(fixcopy g7f-h3)"; assert_fixture_dir "$MUTDIR"
if mutate g7f-h3-prose-run-in-composite "$MUTDIR/$G7F_COMP" 1 '/^        set -euo pipefail$/a\        doppler --version >/dev/null 2>\&1 || { echo "::error::doppler CLI missing; run the install step"; exit 1; }'; then
  fixcensus "$MUTDIR" "$T/mut/g7f-h3.tsv" ""
  if grep -q '^        doppler --version' "$MUTDIR/$G7F_COMP" && grep -q '^ok	G7f:' "$T/mut/g7f-h3.tsv" \
     && [ -z "$(awk -F'\t' '$1 != "ok"' "$T/mut/g7f-h3.tsv")" ]; then
    pass "M-g7f-h3-must-pass: G7f and every other census row stay GREEN when the composite carries prose containing the word run on a doppler line"
  else
    fail "M-g7f-h3-must-pass: prose containing the word run reds a census row" "$(awk -F'\t' '$1 != "ok"' "$T/mut/g7f-h3.tsv" | cut -c1-240)"
  fi
fi
# H4 (must-PASS): a release caller that spells the narrow token in lowercase names the same secret (secret names
# are case-insensitive at GitHub), so G7f accepts it; it used to refuse it as an unnamed token.
MUTDIR="$(fixcopy g7f-h4)"; assert_fixture_dir "$MUTDIR"
if mutate g7f-h4-lowercase-narrow-token "$MUTDIR/tree/.github/workflows/release.yml" 2 's/^          doppler-token: \$\{\{ secrets\.DOPPLER_TOKEN_INFRA_APP \}\}$/          doppler-token: ${{ secrets.doppler_token_infra_app }}/'; then
  fixcensus "$MUTDIR" "$T/mut/g7f-h4.tsv" ""
  if grep -q 'secrets\.doppler_token_infra_app' "$MUTDIR/tree/.github/workflows/release.yml" && grep -q '^ok	G7f:' "$T/mut/g7f-h4.tsv"; then
    pass "M-g7f-h4-must-pass: G7f accepts the narrow token spelled in lowercase (secret names are case-insensitive)"
  else
    fail "M-g7f-h4-must-pass: G7f refuses the lowercase narrow token" "$(awk -F'\t' '$1 != "ok"' "$T/mut/g7f-h4.tsv" | cut -c1-240)"
  fi
fi
# G7 row PRESENCE (a count floor cannot tell a renamed or dropped row from a duplicated one), as G6h2 does for Guard 6.
G7_ROW_IDS="G7c G7d G7e G7f"
g7_present() { rows_present "$1" "$G7_ROW_IDS"; }
if g7_present "$T/live.tsv" && g7_present "$T/control.tsv"; then
  pass "G7h2: every named G7 row id ($G7_ROW_IDS) is present in the live and the control census"
else
  fail "G7h2: a named G7 row id is missing from the live or the control census"
fi
grep -v "$(printf '\tG7d: ')" "$T/control.tsv" > "$T/mut/g7h2.tsv"
if [ "$(grep -c . "$T/mut/g7h2.tsv")" -eq "$(( $(grep -c . "$T/control.tsv") - 1 ))" ]; then
  MUTANTS_RUN=$((MUTANTS_RUN + 1)); pass "M-g7h2-row-missing: exactly one G7 row (G7d) removed from a copy of the control TSV"
  mutant_red g7h2-row-missing g7_present "$T/mut/g7h2.tsv"
else
  fail "M-g7h2-row-missing: the removal did not land on exactly one line"
fi

# H1 (#9321): the same presence check, with G7f removed from a copy of the control TSV.
grep -v "$(printf '\tG7f: ')" "$T/control.tsv" > "$T/mut/g7h2-f.tsv"
if [ "$(grep -c . "$T/mut/g7h2-f.tsv")" -eq "$(( $(grep -c . "$T/control.tsv") - 1 ))" ]; then
  MUTANTS_RUN=$((MUTANTS_RUN + 1)); pass "M-g7h2-g7f-row-missing: exactly one G7 row (G7f) removed from a copy of the control TSV"
  mutant_red g7h2-g7f-row-missing g7_present "$T/mut/g7h2-f.tsv"
else
  fail "M-g7h2-g7f-row-missing: the removal did not land on exactly one line"
fi

# G6h2 — PRESENCE of every named G6 row (a count floor cannot tell a renamed or dropped row from
# a duplicated one). Positive on the live and control TSVs, negative on a control with one removed.
G6_ROW_IDS="G6a G6a2 G6a3 G6b G6c G6c2 G6d G6e G6m G6n G6l G6o G6q G6s G6u"
g6_present() { rows_present "$1" "$G6_ROW_IDS"; }
# The presence helpers get the same third direction as wf_row (a missing or empty TSV is UNRESOLVED, rc 2, never the
# "a row is absent" verdict that mutant_red reads as RED); subshells roll the counters back, printf + exit on a miss.
for _st in "g7_present $T/st-missing.tsv" "g7_present $T/st-empty.tsv" "g6_present $T/st-missing.tsv" "g6_present $T/st-empty.tsv" \
           "g4_present $T/st-missing.tsv" "g4_present $T/st-empty.tsv"; do
  # shellcheck disable=SC2086  # the helper name and its arguments are split on purpose
  _mr="$( (mutant_red st-unresolved-presence $_st >/dev/null 2>&1; printf '%s,%s' "$passes" "$fails") )"
  if [ "$_mr" != "$passes,$((fails + 1))" ]; then
    printf 'FAIL INSTRUMENT: mutant_red read a missing/empty TSV as RED for [%s] (got "%s" from %s,%s)\n' "$_st" "$_mr" "$passes" "$fails" >&2; exit 1
  fi
done
pass "H8: the G4/G6/G7 presence helpers read a missing or empty census TSV as UNRESOLVED, never as an absent row that reads RED (6 drives)"
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

# ── D8 row for the Inngest link flag actuator (#10136, CTO G1) ───────────────────────
# `apply-web-platform-infra.yml::inngest_link_flag` writes the prd_terraform source key with the write-scoped Doppler
# token and applies a prd secret, so it is a Tier-B job by every rule above: it must declare a Tier-B environment, its `doppler run` must keep `--preserve-env`, and the runbook inventory
# must carry its row. G1b/G1c already census it generically
# (they are keyed on what a job references); this row pins the NAMED job so a rename or a dropped `environment:` cannot
# slip through as "the job no longer exists", and the self-check proves the predicate can see a missing environment.
d8_flag_job_ok() {
  python3 - "$1" "$2" <<'PYD'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
job = (wf.get("jobs") or {}).get("inngest_link_flag")
if not job:
    sys.exit(1)
if job.get("environment") not in ("infra-privileged", "web-platform-infra-apply", "inngest-cutover", "workspaces-luks-cutover"):
    sys.exit(1)
text = yaml.safe_dump(job)
# The job writes the source key in prd_terraform (set / delete) with the write-scoped token before it plans:
# prd_terraform does not inherit a Terraform-written prd key (measured 2026-10-19), so untargeted plans need it.
if "secrets.DOPPLER_TOKEN_WRITE" not in text:
    sys.exit(1)
runs = [l for s in job.get("steps", []) for l in str(s.get("run", "")).splitlines() if "doppler run" in l and not l.lstrip().startswith("#")]
if len(runs) < 2 or any("--preserve-env" not in l for l in runs):
    sys.exit(1)
doc = open(sys.argv[2]).read()
sys.exit(0 if "inngest_link_flag" in doc else 1)
PYD
}
_d8_wf="$GHDIR/workflows/apply-web-platform-infra.yml"
_d8_doc="$REPODIR/knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md"
if d8_flag_job_ok "$_d8_wf" "$_d8_doc"; then
  pass "D8-flag: inngest_link_flag declares a Tier-B environment, holds DOPPLER_TOKEN_WRITE under --preserve-env, and has its runbook inventory row"
else
  fail "D8-flag: inngest_link_flag is missing, not on a Tier-B environment, drops DOPPLER_TOKEN_WRITE, drops --preserve-env, or has no row in infra-credential-tiers-8209.md"
fi
mkdir -p "$T/mut"
sed '/^  inngest_link_flag:/,/^    if:/ s/^    environment: infra-privileged$/    # environment removed/' "$_d8_wf" > "$T/mut/d8-noenv.yml"
if cmp -s "$T/mut/d8-noenv.yml" "$_d8_wf"; then
  fail "D8-flag-m1: the environment-removal mutation matched nothing; the job header shape drifted"
elif d8_flag_job_ok "$T/mut/d8-noenv.yml" "$_d8_doc"; then
  fail "D8-flag-m1: a flag job without an environment still passes the D8 predicate (vacuous)"
else
  pass "D8-flag-m1: removing the flag job's environment turns the D8 predicate RED"
fi
sed 's/--preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- \\$/-p soleur -c prd_terraform --name-transformer tf-var -- \\/' "$_d8_wf" > "$T/mut/d8-nopreserve.yml"
if cmp -s "$T/mut/d8-nopreserve.yml" "$_d8_wf"; then
  fail "D8-flag-m2: the --preserve-env removal matched nothing"
elif d8_flag_job_ok "$T/mut/d8-nopreserve.yml" "$_d8_doc"; then
  fail "D8-flag-m2: a flag job whose doppler run drops --preserve-env still passes the D8 predicate (vacuous)"
else
  pass "D8-flag-m2: dropping --preserve-env from the flag job's doppler run turns the D8 predicate RED"
fi
sed '/^  inngest_link_flag:/,/^  vector_redeliver:/ s/secrets\.DOPPLER_TOKEN_WRITE/secrets.DOPPLER_TOKEN/' "$_d8_wf" > "$T/mut/d8-writetoken.yml"
if cmp -s "$T/mut/d8-writetoken.yml" "$_d8_wf"; then
  fail "D8-flag-m3: the write-token removal matched nothing"
elif d8_flag_job_ok "$T/mut/d8-writetoken.yml" "$_d8_doc"; then
  fail "D8-flag-m3: a flag job without DOPPLER_TOKEN_WRITE still passes the D8 predicate (vacuous)"
else
  pass "D8-flag-m3: taking the write-scoped Doppler token off the flag job (it could no longer write the source key) turns the D8 predicate RED"
fi

# ── FLOOR + LEDGER (ADR-193: printf + exit, never through pass()/fail()) ─────────────
# 26 -> 27 (review W1): M-g1-10-destroy-only-no-environment.
# 27 -> 30 (#8714): M-g4-6 (two landings) and M-g4-7, the intended-destroy allowance rows.
# 30 -> 32 (#9215): M-g1-i3 and M-g1-i4, the root-key extract-precedence mutants (drop + reorder).
# 32 -> 52 (#8609): Guard 6 — 19 fixture landings (g6a..g6l, g6p) + the g6h2 TSV truncation.
# 52 -> 53 (merge with #6604 step 7): M-g1-11, which main added without raising this floor.
# 53 -> 64 (#8609 review): g6b-host, g6c-2hop, g6o x3, g6q x2, g6s x3, g6u (11 landings).
# 64 -> 74 (#9360): G4e rows e3, e3b, e3c, e4, e4m, e4x, e4c, e5, e6 (+ e6's composite fixture).
# 74 -> 80 (#9321): Guard 7 — g7c x4 (secret, second root, variable project, renamed declaration), g7d x2 (CI mint, repository-level store).
# 80 -> 94 (#9321 review): g7c x4 (renamed label, environment alias, data source plus projectless token, declaration in a block comment; the label row lands twice), g7e x1, g7d x6 (quoted mint, composite-action mint, trailing-comment store, library helper, REST PUT, repointed GH_ENVIRONMENT) and the G7h2 row removal.
# EXACT, split into a `-lt` floor and a `-gt` ceiling (no slack). The ceiling replaces the nested
# G6h self-run (review: simplicity P2, patterns P3-4): with equality enforced here, deleting ANY
# mutant trips this line by construction, not only the one G6h deleted; and a mutant added without
# raising the number names its real cause instead of reding G6h.
# 94 -> 103 (#9321 PR-2, 2026-10-03): G7f M1, M2, M2b, M3, M4, M5, M6 (7 landings), M7 (the empty tree) and the G7f presence-row removal (H1).
# 103 -> 111 (#9321 PR-2 review, 2026-10-04): G7f M2b', M2c, M-run, M-env, M-wrongtok, M-remote, M-dotdot, M-wrapper (8 landings).
# 111 -> 114 (#9321 PR-2 review pass 2, 2026-10-04): G7f M-run2, H3, H4 (3 landings).
# 114 -> 115 (#9321 PR-2 final pass, 2026-10-04): G7f M-run3 (spaced flag value before run; 1 landing). Measured: 115 ran.
# 115 -> 116 (#8285 PR B): g4-8 (the retired-state-absent ACCEPT arm; 1 landing). Measured: 116 ran.
# 116 -> 120 (#8285 PR B review): g4-9 (listed address still targeted on a PLAN step; 2 landings), g4-10 (App identity in the
#   allowance; 1 landing), g4-11 (allowance entry re-declared at HEAD; 1 landing). Measured: 120 ran.
# 120 -> 125 (#8285 PR B fix round): g4-12 (live store in the allowance; 1 landing), g4-13/g4-14 (space-form `-target ADDR` and
#   `-replace=ADDR` on a plan step; 2 landings each). Measured: 125 ran.
# 125 -> 135 (#9879, G4h): g4h-1, g4h-2, g4h-2b, g4h-3, g4h-mp (1 landing each), g4h-4 and g4h-5 (2 landings each: a tree edit
#   and a checker edit), and the G4h presence-row removal (1). Measured: 135 ran.
# 135 -> 138 (#9879 review): g4h-6 (indented `moved` over the volume), g4h-7 (indented `removed` over a Doppler parent) and g4h-8
#   (comment / heredoc / block-comment look-alikes stay green); 1 landing each. Measured: 138 ran.
# 138 -> 142 (#9879 round 2): g4h-9 (scrubber `#`/`//` branch neutered), g4h-10 (string tracking neutered), g4h-11 (unterminated
#   heredoc hides the fixture's removed blocks; only the G4h4 count pin sees it) and g4c-read-tf (Guard 4 reader unscrubbed); 1 landing each. Measured: 142 ran.
# 142 -> 145 (#9927 8b): g1-g2 inverted (the read-only-first allowance is deleted; still 1 landing, same fixture), g1-g3 (a step
#   `env:` DOPPLER_CONFIG read, 1 landing), g1-j1 (drop a loader job's environment key, 1 landing) and g1-j2 (zero loader jobs,
#   one landing per removed call, counted once). Measured: 145 ran.
# 151 -> 154 (#10990 review): g1-k8 (destroy-verb fixture writer, 1), g1-k9 (doppler-run env
#   injection fixture, 1), g1-k10 (secrets-download fixture, 1). Measured: 154 ran.
# 145 -> 151 (#10990, AC7b limb 3): g1-k1 (fixture .sh writer, 1), g1-k2 (checker write-token set, 1),
#   g1-k3 (second-member fixture .sh writer, 1), g1-k4 (half-set pair, 1), g1-k5 (checker
#   classification key, 1), g1-k6 (read-only fixture .sh, 1). Measured: 151 ran.
# 154 -> 155 (#9755): g1-2b (empty `||` arm plus a doppler-token-legacy loader input on the
#   conditional fixture, 1 landing). Measured: 155 ran.
# 155 -> 156 (#9755 review): g1-2c (empty `||` arm plus an unconditional step env: naming a
#   repo-scoped privileged secret, 1 landing). Measured: 156 ran.
# 156 -> 163 (#9755 review round 2): g1-2d (literal-free environment: -> __UNPARSEABLE__
#   sentinel), g1-2e (run:-inline secrets interpolation), g1-2f (job-level env:), g1-2g
#   (caller-job secrets: block), g1-2h (secrets: inherit), g1-2i (lowercase spelling),
#   g1-2j (DOPPLER_TOKEN_INNGEST_ARM name); 1 landing each. Measured: 163 ran.
MUTANT_FLOOR=163
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
# 205 -> 220 (#9321): live G7c/G7d (2), G7g (1), 6 landings + 6 verdicts. Measured: 220 ran (this branch alone: 175 -> 190).
# 220 -> 250 (#9321 review): live G7e, G7h2 presence, the must-pass row and 14 new mutant rows. Measured: 250 ran.
# 250 -> 269 (#9321 PR-2, 2026-10-03): live G7f (1), G7f M1/M2/M2b/M3/M4/M5/M6 (7 landings + 7 verdicts), M7 (1 verdict), the G7f must-pass row (1), the G7f presence-row removal (1 landing + 1 verdict). Measured: 269 ran.
# 269 -> 287 (#9321 PR-2 review, 2026-10-04): 8 clause-isolated G7f mutants (8 landings + 8 verdicts) and the H7 and H8 unresolved-TSV controls (2). Measured: 287 ran.
# 287 -> 294 (#9321 PR-2 review pass 2, 2026-10-04): G7f M-run2, H3 (prose "run") and H4 (lowercase token) (3 landings + 3 verdicts) and the H7b exact-verdict drives (1). Measured: 294 ran.
# 294 -> 296 (#9321 PR-2 final pass, 2026-10-04): G7f M-run3 (1 landing + 1 verdict); the H7b absent-row and _h7b self-test drives add no assertion (inside the one H7b pass). Measured: 296 ran.
# 296 -> 298 (#8285 PR B): g4-8 landing + verdict. Measured: 298 ran.
# 298 -> 306 (#8285 PR B review): live G4g (1), g4-9 (2 landings + 1 verdict), g4-10 (1 + 1), g4-11 (1 + 1). Measured: 306 ran.
# 306 -> 314 (#8285 PR B fix round): g4-12 (1 landing + 1 verdict), g4-13 and g4-14 (2 landings + 1 verdict each). Measured: 314 ran.
# 314 -> 336 (#9879, G4h): live G4h and G4h2 (2), the must-pass control row (1), g4h-1/2/2b/3 (1 landing + 1 verdict each), g4h-mp (1 + 1),
#   g4h-4 and g4h-5 (2 landings + 1 verdict each), the G4 presence row (1), the presence-row removal (1 + 1). Measured: 336 ran.
# 336 -> 342 (#9879 review): g4h-6 and g4h-7 (1 landing + 1 verdict each), g4h-8 (1 landing + 1 must-pass verdict). Measured: 342 ran.
# 342 -> 351 (#9879 round 2): live G4h4 (1), g4h-9 / g4h-10 / g4h-11 / g4c-read-tf (1 landing + 1 verdict each); g4h-8 gains clauses inside its one must-pass verdict (0). Measured: 351 ran.
# 351 -> 360 (#9956): G4c-b1..b7 base-resolution legs over the synthetic git repo — resolution sanity (1),
#   post-fork addition invisible (1), unclaimed deletion RED + detail (2), second-member RED + detail (2),
#   removed{} claim GREEN (1), IPT_BASE_REF override discriminates tip semantics (1), no-base fail-closed (1).
#   Measured: 360 ran.
# 360 -> 363 (#9956 review): G4c-b8 + b8d fallback-arm provenance (merge-base fails, tip resolvable —
#   falls back AND announces), G4c-parity bash↔python GUARD4_ROOTS set check. Measured: 363 ran.
# 363 -> 364 (#9956 review round 2): G4c-b9 per-root floor arm driver (M2's root-key holds no .tf).
#   Measured: 364 ran.
# 364 -> 365 (#9956 review round 2 fixes): G4c-b9d — the floor arm reaches the row as
#   'base unavailable' end-to-end. Measured: 365 ran.
# 365 -> 368 (#10136): D8-flag (live) and D8-flag-m1/m2 (environment and --preserve-env mutants; 1 verdict each). Measured: 368 ran.
# 368 -> 369 (#10136 round 4): D8-flag-m3 (the flag job without its write-scoped Doppler token). Measured: 369 ran.
# 393 -> 402 (#10990 review): g1-k8/k9/k10 (3 landings + 3 verdicts + 3 named-cause checks).
#   Measured: 402 ran.
# 376 -> 393 (#10990, AC7b limb 3): live G1k (1), g1-k1..k6 (6 landings + 6 verdicts), the three
#   named-cause checks on k1/k3/k4 (3), the read-only and compliant controls (2). The pre-change
#   suite measured 376 on this branch — the recorded 369 above is stale by 7 (the floor asserts
#   only `-lt`, so upward drift never trips it). Measured: 393 ran.
# 402 -> 404 (#9755): g1-2b (1 landing + 1 verdict). Measured: 404 ran.
# 404 -> 406 (#9755 review): g1-2c (1 landing + 1 verdict). Measured: 406 ran.
# 406 -> 420 (#9755 review round 2): g1-2d..g1-2j (7 landings + 7 verdicts). Measured: 420 ran.
FLOOR=420
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
