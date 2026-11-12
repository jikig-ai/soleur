#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Guard 1 for #9512 (ADR-276 S2): the `push-dedupe` proof in .github/workflows/ci.yml.
#
# WHAT THE GATE IS. On a push to `main`, job `push-dedupe` decides whether the nine heavy `ci.yml` jobs
# may be skipped because an identical-SHA `merge_group` run of the same workflow already passed. It is a
# COST optimisation that is allowed to fail in one direction only: every unknown runs the full battery.
# The deploy arm still sees a `success` push run because `push-dedupe` and the ungated cheap guards run.
#
# WHAT THIS SUITE PROVES. Not that the YAML mentions the right words, but that the proof step body,
# EXTRACTED from ci.yml and EXECUTED under the shell Actions uses (`bash --noprofile --norc -eo pipefail`)
# against a gh shim, yields the right verdict for each input class, and that the wrapper (job `if`,
# permissions, outputs, step flags, env), the nine gated conditions and the unchanged `test` aggregator
# are what the design says.
#
#   * a battery of rows over event, ref, attempt, SHA, variable shape, run listing shape, job listing
#     shape and API failure shape, each with an expected (elide, would_elide, reason);
#   * invariants applied to EVERY row: exit 0, every output line is a literal `elide=`/`would_elide=`
#     verdict, every stdout line is the one annotation, `mg_run` is `none` or digits, and no fixture
#     string (a poisoned title, branch or stderr) reaches an output or an annotation;
#   * a wrapper check on the parsed YAML (permissions, outputs, step flags, env, timeouts, no uses/secrets);
#   * a gated-set parity check derived from the parsed YAML in both directions, with the canonical
#     condition EVALUATED over an event x output x need-result truth table (the status-function semantics
#     included: without one a skipped need skips the job, which would drop a required context);
#   * the `test` aggregator pinned byte-for-byte (a digest) and EXECUTED over a triple with one leg
#     skipped, which must fail: the proof demands only the `test` job, which is sound only while that holds;
#   * mutation rows against mutated COPIES of the body and the workflow in mktemp dirs. A mutant is CAUGHT
#     only when the battery or the checker names the expected row; a crash proves nothing;
#   * harness rows: a stub proof that always elides must be refused, and a catch-all gh shim must not
#     let the must-be-false rows pass.
#
# THE gh SHIM validates the two exact endpoints (the runs listing with `event=merge_group`, a 40-hex
# `head_sha` and `per_page=100`; the jobs listing with `per_page=100&filter=latest` for a run id that
# exists), exits non-zero when GH_TOKEN is unset as real gh does, logs every call, and exits 64 on any
# other request (a STUB-MISS fails the row). It deliberately applies NO server-side filtering: the search
# parameters are advisory, so every row also proves the client-side re-check.
#
# PRE-MERGE LIMIT. The evaluator encodes the rule it tests. The authority for the `event != push` half is
# the live canary on the PR's own `pull_request` and `merge_group` runs; the `push` half first runs on `main`.
#
# This suite writes ONLY under mktemp rooted at ${TMPDIR:-/var/tmp}; never into the repo.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

# A DIRECT invocation inherits the bare /tmp (a machine-global tmpfs shared by every worktree);
# the registered runners default to /var/tmp.
export TMPDIR="${TMPDIR:-/var/tmp}"

passes=0
fails=0
# APPEND-ONLY FAILURE LEDGER: the exit status reads this array, which can only be silenced by
# deleting evidence, not by moving a counter.
FAILURES=()
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); FAILURES+=("$1"); printf 'FAIL: %s\n' "$1" >&2; }

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WF="$REPO_ROOT/.github/workflows/ci.yml"

SANDBOX=$(mktemp -d "$TMPDIR/ci-push-dedupe.XXXXXXXX") || {
  printf 'FAIL: could not create sandbox (mktemp -d failed)\n' >&2; exit 2; }
trap 'rm -rf "$SANDBOX"' EXIT

for _dep in python3 jq bash timeout cmp md5sum; do
  command -v "$_dep" >/dev/null 2>&1 || { printf 'FAIL: %s is required\n' "$_dep" >&2; exit 2; }
done
python3 -c 'import yaml' 2>/dev/null || {
  printf 'FAIL: PyYAML is required to parse ci.yml (python3 -c "import yaml" failed)\n' >&2; exit 2; }

# ── INSTRUMENT SELF-TEST ─────────────────────────────────────────────────────
# pass() and fail() must each move their counters; a neutered helper makes every row below quiet.
_p0=$passes; _f0=$fails; _n0=${#FAILURES[@]}
pass
fail "instrument self-test (expected, not a real failure)" 2>/dev/null
if [ "$passes" -ne $((_p0 + 1)) ] || [ "$fails" -ne $((_f0 + 1)) ] || [ "${#FAILURES[@]}" -ne $((_n0 + 1)) ]; then
  printf 'FAIL INSTRUMENT: pass()/fail() did not each move their counter by one (%s %s %s)\n' \
    "$passes" "$fails" "${#FAILURES[@]}" >&2
  exit 1
fi
passes=$_p0; fails=$_f0; FAILURES=()

# ── Pinned expectations (the design's reading of the wrapper) ────────────────
# The condition tail every gated job carries, written ONCE here: chk.py, the parity rows and the mutants all derive from it.
ELIDE_TAIL="(github.event_name == 'merge_group' || github.event_name != 'push' || needs.push-dedupe.outputs.elide != 'true')"
GATED_PINNED="e2e shard-totality-mutations test test-bun test-scripts test-scripts-heavy test-webplat test-webplat-mutations web-platform-build"
# ADR-276 S3 (#9728): five of those nine additionally carry `needs: [push-dedupe, draft-light]` and this clause appended to the
# condition (the other four, incl. e2e and the `test` aggregator, must NOT: scripts/ci-draft-light.test.sh pins the S3 side in full).
LIGHT_CLAUSE="needs.draft-light.outputs.light != 'true'"
DL_GATED_PINNED="shard-totality-mutations test-scripts test-scripts-heavy test-webplat test-webplat-mutations"
# ADR-276 S4 (#9729, PR B) — RETIRED 2026-11-09 (the NO-GO ruling on #9729): the pr-selection lever job, its
# PR-skip `if:` term, its driver script and its aggregator tolerance are all deleted. PR_GATED_PINNED is the EMPTY
# set ON PURPOSE — the same pins now assert the post-removal grammar: no job may carry a `pr-selection` needs edge,
# no `if:` may read `needs.pr-selection.*`, no `skip_re` tolerance arm may exist in the aggregator, no retired-variable
# read may exist anywhere in the document, and the retired selector driver file must be absent from the tree. The
# prcensus / legparity / prsel / darkequiv modes below pin all four in both directions (an empty found-set is the
# pass; a re-introduced lever is a tag, never silently green).
PR_GATED_PINNED=""
PR_TERM_PRE=""   # dead prefix kept exported so chk.py's environment read stays uniform; the grammar it named is forbidden now
PRSEL_IF=""      # same: the retired job-level condition
# ADR-276 oracle-only lane (#12156): the six heavy legs additionally carry `oracle-selection` in `needs:` and a
# skip conjunct appended AFTER every earlier term — the same four-term `!(…)` shape the S4 legs carry (event
# disjunct, active, head_sha nonempty, head bound to either event's sha via
# `github.event.pull_request.head.sha || github.event.merge_group.head_sha`). `shard-totality-mutations`
# carries the lane's other gating: `needs.oracle-selection.outputs.active != 'true'`, and oracle-selection in
# `needs:`. Written ONCE here; chk.py's canon, the truth table and the census derive from it. CONTRACT NOTE: the
# conjunct text below is the plan's documented shape; if the implementation spells it differently this pin is where
# the reconciliation happens.
OR_GATED_PINNED="test-webplat test-webplat-mutations test-bun test-scripts test-scripts-heavy web-platform-build"
OR_T_EV="(github.event_name == 'pull_request' || github.event_name == 'merge_group') && "
OR_T_AC="needs.oracle-selection.outputs.active == 'true' && "
OR_T_HN="needs.oracle-selection.outputs.head_sha != '' && "
OR_T_HE="needs.oracle-selection.outputs.head_sha == (github.event.pull_request.head.sha || github.event.merge_group.head_sha) && "
OR_TERM_PRE="!($OR_T_EV$OR_T_AC$OR_T_HN$OR_T_HE"
or_term() { printf "%scontains(format(',{0},', needs.oracle-selection.outputs.skip_legs), ',%s,'))" "$OR_TERM_PRE" "$1"; }
# shard-totality-mutations carries the SAME four-term conjunct as the six lane legs MINUS the skip_legs
# membership (it skips on active alone — the advisory leg is lane-unsafe whatever the leg list says):
# `!(event && active == 'true' && head_sha != '' && head_sha == (pr.sha || mg.sha))`.
SHARD_TERM="!($OR_T_EV$OR_T_AC$OR_T_HN${OR_T_HE% && })"
ORACLE_ONLY_TERM="$SHARD_TERM"
SHARD_GATED="shard-totality-mutations"
# the oracle-selection job's own condition, the surviving var-gated lever pin (the retired pr-selection lever's was a
# bare expression; this one is written INSIDE a `${{ }}` wrapper): var-gated, both lane events.
ORASEL_EV="(github.event_name == 'pull_request' || github.event_name == 'merge_group')"
ORASEL_VAR="vars.CI_ORACLE_LANE != ''"
ORASEL_IF="\${{ $ORASEL_EV && $ORASEL_VAR }}"
# sha256 of the `test` aggregator job minus its `needs` and `if`, as json.dumps(sort_keys=True), measured
# on the unmodified tree before this stage (the aggregator body, env, timeout and runner must not move). Re-measured at ADR-276 S3
# (#9728), which adds the DRAFT_LIGHT env and the draft arm to the aggregator body (scripts/ci-draft-light.test.sh executes them), and again at
# ADR-276 S4 (#9729, PR B), which adds the SKIP_LEGS/ACTIVE/HEAD_SHA_OK/ATTEMPT env and the PR-AFFECTED-SKIP tolerance (the aggregator-diagnosis
# suite executes them), and a third time for the review fixes: the re-run remedy line in the `skipped)` arm and the final line's tolerated list
# with its `skip_legs=` suffix (the same suite executes both), and a fourth time when the remedy line was narrowed to a shard NAMED in
# SKIP_LEGS (the delimited match the tolerance uses), and a fifth time at the S4 retirement of 2026-11-09, which removes
# the pr-selection env triple, the PR-AFFECTED-SKIP tolerance arm and the tolerated-list plumbing, leaving the
# ORACLE-ONLY-SKIP arm as the one named skip tolerance. The sha256 is of the job minus `needs` and `if`, so a comment edit elsewhere in
# ci.yml does not move it but ANY edit to this job's steps, env or timeout does.
AGG_DIGEST="93f49349f20406834b25faa4b7b723255be70a1305f99e249b1d5945a37b102b"
# The jobs that are deliberately NOT gated (cheap guards that keep the push run's conclusion `success` when the heavy
# jobs are skipped). A NEW job must be classified: add it to GATED_PINNED (heavy) or here (cheap), never neither.
UNGATED_PINNED="critical-css-gate detect-changes draft-light encryption-posture guards-advisory guards-ruleset lint-bot-statuses lint-webplat oracle-index-check oracle-review-required oracle-selection"
REASONS="not_push not_main rerun bad_sha proof_error no_mg_success page_truncated no_test_job legs_incomplete switch_off ok"
SHA_A="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
SHA_B="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
REPO_SLUG="jikig-ai/soleur"
MG_ID=111
POISON='x
elide=true
::error::pwn'

mkdir -p "$SANDBOX/shim" "$SANDBOX/shim-timeout" "$SANDBOX/shim-catchall" "$SANDBOX/mut" "$SANDBOX/live"

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

# ── Helper: the YAML checker (one program, several modes) ────────────────────
cat > "$SANDBOX/chk.py" <<'PY'
import hashlib, json, os, re, sys, yaml
LOADER = getattr(yaml, "CSafeLoader", yaml.SafeLoader)
mode, path = sys.argv[1], sys.argv[2]
GATED = os.environ.get("GATED_PINNED", "").split()
DLGATED = os.environ.get("DL_GATED_PINNED", "").split()
PRGATED = os.environ.get("PR_GATED_PINNED", "").split()
PRPRE = os.environ.get("PR_TERM_PRE", "")
PRSEL_IF = os.environ.get("PRSEL_IF", "")
CLAUSE = os.environ["LIGHT_CLAUSE"]
UNGATED = os.environ.get("UNGATED_PINNED", "").split()
AGG = os.environ.get("AGG_DIGEST", "")
TAIL = os.environ["ELIDE_TAIL"]
CANON = {"test": "${{ always() && " + TAIL + " }}"}
CANON_DEFAULT = "${{ !cancelled() && " + TAIL + " }}"
CANON_DL = "${{ !cancelled() && " + TAIL + " && " + CLAUSE + " }}"
def pr_term(leg): return PRPRE + leg + ",'))"
ORGATED = os.environ.get("OR_GATED_PINNED", "").split()
SHARDG = os.environ.get("SHARD_GATED", "").split()
ORPRE = os.environ.get("OR_TERM_PRE", "")
ORONLY = os.environ.get("ORACLE_ONLY_TERM", "")
ORASEL_IF = os.environ.get("ORASEL_IF", "")
def or_term(leg): return ORPRE + "contains(format(',{0},', needs.oracle-selection.outputs.skip_legs), ',%s,'))" % leg
def canon(n):
    parts = ["!cancelled()" if n != "test" else "always()", TAIL]
    if n in DLGATED: parts.append(CLAUSE)
    if n in PRGATED: parts.append(pr_term(n))
    if n in ORGATED: parts.append(or_term(n))
    if n in SHARDG: parts.append(ORONLY)
    return "${{ " + " && ".join(parts) + " }}"
ENV_KEYS = {"GH_TOKEN", "GH_REPO", "SHA", "EVENT_NAME", "REF", "RUN_ATTEMPT", "SWITCH"}

def load():
    try:
        d = yaml.load(open(path).read(), Loader=LOADER)
        return d, (d.get("jobs") or {})
    except Exception as e:
        sys.stderr.write("chk.py crashed: %r\n" % (e,)); sys.exit(2)

def needs(j):
    n = (j or {}).get("needs", [])
    return [n] if isinstance(n, str) else list(n)

class CI(str):
    # Actions compares strings WITHOUT regard to case (docs: expressions, "operators"); Python's str does not. Used for the variable and the need result.
    def __eq__(self, o): return str(self).lower() == str(o).lower()
    def __ne__(self, o): return not self.__eq__(o)
    __hash__ = str.__hash__

def ev(expr, event, elide, need, cancelled=False, light="", active="", sk="", hs="", ph="", prr="", var="",
       oac="", osk="", ohs="", mgh="", ovar=""):
    e = str(expr).strip()
    if not (e.startswith("${{") and e.endswith("}}")):
        return None
    e = e[3:-2].strip()
    has_status = bool(re.search(r"\b(cancelled|always|success|failure)\(\)", e))
    e = e.replace("!cancelled()", "(not CANC)").replace("always()", "True").replace("success()", "(NEEDOK)")
    e = re.sub(r"contains\(format\(',\{0\},', needs\.pr-selection\.outputs\.skip_legs\), ',([a-z-]+),'\)", lambda m: '(",%s," in "," + SK + ",")' % m.group(1), e)
    e = re.sub(r"contains\(format\(',\{0\},', needs\.oracle-selection\.outputs\.skip_legs\), ',([a-z-]+),'\)", lambda m: '(",%s," in "," + OSK + ",")' % m.group(1), e)
    e = e.replace("needs.pr-selection.result", "PRR").replace("vars.CI_PR_" + "AFFECTED", "VAR").replace("vars.CI_ORACLE_LANE", "OVAR")
    e = e.replace("github.event.pull_request.head.sha || github.event.merge_group.head_sha", "(PH or MGH)")
    e = e.replace("needs.oracle-selection.outputs.active", "OAC").replace("needs.oracle-selection.outputs.head_sha", "OHS").replace("needs.oracle-selection.outputs.oracle_only", "''")
    e = e.replace("needs.pr-selection.outputs.active", "AC").replace("needs.pr-selection.outputs.head_sha", "HS").replace("github.event.pull_request.head.sha", "PH").replace("github.event.merge_group.head_sha", "MGH")
    e = re.sub(r"!(?=\()", " not ", e)
    e = e.replace("github.event_name", "EV").replace("needs.push-dedupe.outputs.elide", "EL").replace("needs.draft-light.outputs.light", "LT")
    e = e.replace("&&", " and ").replace("||", " or ")
    try:
        val = bool(eval(e, {"__builtins__": {}}, {"CANC": cancelled, "EV": event, "EL": elide, "LT": light, "NEEDOK": need == "success", "AC": active, "SK": sk, "HS": hs, "PH": ph, "PRR": CI(prr), "VAR": CI(var),
                                               "OAC": oac, "OSK": osk, "OHS": ohs, "MGH": mgh, "OVAR": CI(ovar)}))
    except Exception:
        return None
    if not has_status:
        val = val and need == "success"
    return val

if mode == "extract":
    out = sys.argv[3]
    d, jobs = load()
    job = jobs.get("push-dedupe")
    steps = (job or {}).get("steps") or []
    proof = [s for s in steps if isinstance(s, dict) and s.get("id") == "proof" and "run" in s]
    if len(proof) != 1:
        sys.stderr.write("found %d proof steps in job push-dedupe (0 = job absent)\n" % len(proof)); sys.exit(3)
    open(out + "/body.sh", "w").write(proof[0]["run"])
    sys.exit(0)

if mode == "wrapper":
    d, jobs = load()
    tags = []
    job = jobs.get("push-dedupe")
    if job is None:
        print("W-JOB-MISSING"); sys.exit(0)
    if job.get("if") != "github.event_name == 'push'": tags.append("W-JOBIF")
    if job.get("timeout-minutes") != 3: tags.append("W-JOBTIMEOUT")
    if job.get("permissions") != {"actions": "read"}: tags.append("W-PERM")
    if job.get("outputs") != {"elide": "${{ steps.proof.outputs.elide }}"}: tags.append("W-OUTPUTS")
    if job.get("continue-on-error") is not True: tags.append("W-JOBCOE")
    if job.get("runs-on") != "ubuntu-latest": tags.append("W-RUNSON")
    if needs(job): tags.append("W-JOBNEEDS")
    steps = job.get("steps") or []
    if [s.get("id") for s in steps] != ["proof", "would-elide"]: tags.append("W-STEPS")
    for s in steps:
        if "uses" in s: tags.append("W-USES")
    txt = json.dumps(job)
    if "secrets." in txt: tags.append("W-SECRETS")
    if "checkout" in txt: tags.append("W-CHECKOUT")
    proof = next((s for s in steps if s.get("id") == "proof"), {})
    if proof.get("continue-on-error") is not True: tags.append("W-COE")
    if proof.get("timeout-minutes") != 2: tags.append("W-STEPTIMEOUT")
    if proof.get("shell") != "bash": tags.append("W-SHELL")
    if set((proof.get("env") or {}).keys()) != ENV_KEYS: tags.append("W-ENVKEYS")
    env = proof.get("env") or {}
    exp = {"GH_TOKEN": "${{ github.token }}", "GH_REPO": "${{ github.repository }}", "SHA": "${{ github.sha }}",
           "EVENT_NAME": "${{ github.event_name }}", "REF": "${{ github.ref }}", "RUN_ATTEMPT": "${{ github.run_attempt }}",
           "SWITCH": "${{ vars.CI_PUSH_DEDUPE }}"}
    if any(env.get(k) != v for k, v in exp.items()): tags.append("W-ENVVALUES")
    for s in steps:
        if s is not proof and "GH_TOKEN" in (s.get("env") or {}): tags.append("W-TOKEN-LEAK")
    body = proof.get("run", "")
    if re.search(r"set\s+-[a-zA-Z]*x|xtrace", body): tags.append("W-XTRACE")
    if "set +x" not in body: tags.append("W-NOXTRACEOFF")
    if "${{" in body: tags.append("W-INTERP")
    gh_calls = len(re.findall(r"\bgh api\b", body))
    t_calls = len(re.findall(r"\btimeout 20 gh api\b", body))
    if gh_calls != 2 or t_calls != 2: tags.append("W-GHTIMEOUT")
    i_def = body.find('emit "elide=false"'); i_gh = body.find("gh api")
    if i_def < 0 or i_gh < 0 or i_def > i_gh: tags.append("W-DEFAULT-ORDER")
    i_true = body.find('emit "elide=true"'); i_chk = body.find("reason=no_test_job")
    if body.count('emit "elide=true"') != 1 or i_true < 0 or i_chk < 0 or i_true < i_chk: tags.append("W-TRUE-ORDER")
    would = steps[1] if len(steps) > 1 else {}
    if would.get("if") != "steps.proof.outputs.would_elide == 'true'": tags.append("W-WOULDIF")
    # the release workflow's CI budget awk reads `timeout-minutes: N` alone on a line
    text = open(path).read().split("\n")
    try:
        i0 = text.index("  push-dedupe:")
    except ValueError:
        tags.append("W-JOB-TEXT"); print(" ".join(tags)); sys.exit(0)
    blk = []
    for ln in text[i0 + 1:]:
        if re.match(r"^  [A-Za-z0-9_-]+:\s*$", ln): break
        blk.append(ln)
    if sum(1 for ln in blk if ln == "    timeout-minutes: 3") != 1: tags.append("W-TIMEOUT-LINE")
    print(" ".join(tags)); sys.exit(0)

if mode == "prsel":
    # POST-REMOVAL PIN (S4 retirement, 2026-11-09): the pr-selection lever job is gone and must stay gone — a
    # re-added job of that name is the tag. The top-level env/defaults pins survive: a run-wide `env:` or
    # `defaults:` still reaches every job (the lever class of bug it guarded is not pr-selection-specific).
    d, jobs = load()
    tags = []
    if jobs.get("pr-selection") is not None: tags.append("P-JOB-PRESENT")
    top = d if isinstance(d, dict) else {}
    if "env" in top: tags.append("P-TOPENV")
    if "defaults" in top: tags.append("P-TOPDEFAULTS")
    print(" ".join(tags)); sys.exit(0)

if mode == "prcensus":
    # POST-REMOVAL PIN (S4 retirement, 2026-11-09): ZERO references to the retired lever may exist — no
    # `needs.pr-selection` / `needs['pr-selection']` anywhere in the parsed document (a `run:` body string counts,
    # conservative), and no retired-variable read or whole-context read of `needs`/`vars` at all. The found-set must be
    # EMPTY; a single surviving or re-introduced read is a tag. YAML comments are gone after the parse, so a comment
    # mention is not a hit.
    d, jobs = load()
    def census(pat, root):
        found = {}
        def walk(node, loc):
            if isinstance(node, dict):
                for k, v in node.items():
                    walk(v, loc + (str(k),))
            elif isinstance(node, list):
                for i, v in enumerate(node):
                    nm = v.get("name") if isinstance(v, dict) and isinstance(v.get("name"), str) else None
                    walk(v, loc + ("[%s]" % (nm if nm is not None else i),))
            else:
                n = len(pat.findall(str(node)))
                if n: found[".".join(loc)] = found.get(".".join(loc), 0) + n
        walk(root, ())
        return found
    found = census(re.compile(r"needs\s*\.\s*pr-selection\b|needs\s*\[\s*['\"]pr-selection['\"]\s*\]", re.I), d.get("jobs") or {})
    tags = []
    for k in sorted(found): tags.append("C-REF:%s:%d" % (k, found[k]))
    if found: tags.append("C-TOTAL:%d" % sum(found.values()))
    found2 = census(re.compile(r"CI_PR_" + r"AFFECTED|\b(?:needs|vars)\s*\.\s*\*|\b(?:needs|vars)\s*\[(?!\s*['\"]pr-selection['\"]\s*\])|(?<![\w.\-])(?:needs|vars)\s*[,)]", re.I), d)
    for k in sorted(found2): tags.append("C-VARS:%s:%d" % (k, found2[k]))
    if found2: tags.append("C-VARS-TOTAL:%d" % sum(found2.values()))
    print(" ".join(tags)); sys.exit(0)

if mode == "legparity":
    # POST-REMOVAL PIN (S4 retirement, 2026-11-09): the three copies the old parity pinned — the aggregator's
    # `skip_re` arm, the gated jobs' PR-skip terms and the driver's leg list — are all gone. The pin is now the
    # ABSENCE direction: no `skip_re` line may exist in the aggregator body, no job-level `if:` may name
    # `needs.pr-selection`, the pinned PR-gated set must stay empty, and the driver file must stay absent from
    # the tree. A re-introduced tolerance arm or lever term is a tag.
    d, jobs = load()
    tags = []
    if PRGATED: tags.append("L-SET:pinned:%s" % ",".join(sorted(PRGATED)))
    steps = ((jobs.get("test") or {}).get("steps")) or []
    agg = [s for s in steps if isinstance(s, dict) and s.get("name") == "Aggregate shard results"]
    body = agg[0].get("run", "") if agg else ""
    if re.search(r"^[ \t]*skip_re=", body, re.M): tags.append("L-SKIPRE")
    for n, j in jobs.items():
        iff = str((j or {}).get("if", ""))
        if "needs.pr-selection" in iff: tags.append("L-TERM:%s" % n)
    drv = os.environ.get("DRIVER_SH", "")
    if drv and os.path.exists(drv): tags.append("L-DRIVER-PRESENT")
    print(" ".join(tags)); sys.exit(0)

if mode == "zero-prsel":
    # copy of the workflow with the lever job's job-level timeout written as 0, for the budget comparison. The S4
    # lever is gone, so the index falls back to copying the input verbatim — a re-added pr-selection job resumes
    # the zeroed-timeout comparison unchanged.
    out = sys.argv[3]
    text = open(path).read().split("\n")
    try:
        i0 = text.index("  pr-selection:")
    except ValueError:
        open(out, "w").write("\n".join(text)); sys.exit(0)
    for k in range(i0 + 1, len(text)):
        if re.match(r"^  [A-Za-z0-9_-]+:\s*$", text[k]): break
        if text[k].startswith("    timeout-minutes:"): text[k] = "    timeout-minutes: 0"; break
    open(out, "w").write("\n".join(text)); sys.exit(0)

if mode == "gated":
    d, jobs = load()
    tags = []
    got = sorted(n for n, j in jobs.items() if "needs.push-dedupe.outputs.elide" in str((j or {}).get("if", "")))
    if got != sorted(GATED): tags.append("G-SET:" + ",".join(got))
    for n in GATED:
        j = jobs.get(n)
        if j is None: tags.append("G-MISSING:" + n); continue
        if "push-dedupe" not in needs(j): tags.append("G-NEEDS:" + n)
        want_if = canon(n)
        if j.get("if") != want_if: tags.append("G-COND:" + n)
        if "pr-selection" in needs(j): tags.append("G-PRNEEDS:" + n)
        if n != "test" and (n in DLGATED) != ("draft-light" in needs(j)): tags.append("G-DLNEEDS:" + n)
        if n == "test" and "draft-light" not in needs(j): tags.append("G-DLNEEDS:" + n)
        if (n in ORGATED or n in SHARDG or n == "test") != ("oracle-selection" in needs(j)): tags.append("G-ORNEEDS:" + n)
        if n == "test" and "oracle-index-check" not in needs(j): tags.append("G-ORIDXNEEDS:" + n)
        if j.get("continue-on-error"): tags.append("G-COE:" + n)
    # the oracle-lane jobs themselves: oracle-index-check always()s over a skipped oracle-selection (needs-skip
    # propagation would wedge `test`'s needs: loudly while CI_ORACLE_LANE is unset).
    oic = jobs.get("oracle-index-check")
    if oic is None: tags.append("G-OIC-MISSING")
    else:
        if str(oic.get("if", "")).replace(" ", "") != "${{always()&&!cancelled()&&(github.event_name=='pull_request'||github.event_name=='merge_group')}}": tags.append("G-OIC-IF")
        if needs(oic) != ["oracle-selection"]: tags.append("G-OIC-NEEDS")
    osel = jobs.get("oracle-selection")
    if osel is None: tags.append("G-ORSEL-MISSING")
    elif str(osel.get("if", "")) != ORASEL_IF: tags.append("G-ORSEL-IF")
    for n, j in jobs.items():
        if n not in GATED and n != "push-dedupe" and "push-dedupe" in needs(j): tags.append("G-EXTRANEED:" + n)
        if n not in GATED and n != "push-dedupe" and n not in UNGATED: tags.append("G-UNCLASSIFIED:" + n)
        if n not in GATED and set(needs(j)) & set(GATED): tags.append("G-DEPENDENT:" + n)
        # post-removal, pr-selection may be needed by NO job: any edge waits on a retired job's outputs
        if n != "pr-selection" and n not in PRGATED and n != "test" and "pr-selection" in needs(j): tags.append("G-PRNEEDS-EXTRA:" + n)
        # oracle-selection may be needed ONLY by the six lane-gated legs, shard-totality-mutations, `test` and
        # oracle-index-check: any other reader of its outputs reads a dark-launch verdict as if it gated.
        if n not in ORGATED and n not in SHARDG and n not in ("test", "oracle-index-check") and "oracle-selection" in needs(j): tags.append("G-ORNEEDS-EXTRA:" + n)
        if n != "push-dedupe" and "push-dedupe" in json.dumps((j or {}).get("outputs", {})): tags.append("G-REEXPORT:" + n)
    for n in UNGATED:
        if n not in jobs: tags.append("G-GONE:" + n)
    print(" ".join(tags)); sys.exit(0)

if mode == "ocensus":
    # Every expression reference to the oracle-selection job's outputs, by location. Allowed: each lane-gated leg's
    # `if:` (4 refs: active, head_sha twice, skip_legs), shard-totality-mutations' `if:` (1: active), the aggregator's
    # oracle env entries. A step-level `if:`, a matrix `exclude`, a job `env:` or any other consumer inside a gated
    # job could skip work while the job still concludes `success`.
    d, jobs = load()
    def census2(pat, root):
        found = {}
        def walk(node, loc):
            if isinstance(node, dict):
                for k, v in node.items(): walk(v, loc + (str(k),))
            elif isinstance(node, list):
                for i, v in enumerate(node):
                    nm = v.get("name") if isinstance(v, dict) and isinstance(v.get("name"), str) else None
                    walk(v, loc + ("[%s]" % (nm if nm is not None else i),))
            else:
                n = len(pat.findall(str(node)))
                if n: found[".".join(loc)] = found.get(".".join(loc), 0) + n
        walk(root, ())
        return found
    found = census2(re.compile(r"needs\s*\.\s*oracle-selection\b|needs\s*\[\s*['\"]oracle-selection['\"]\s*\]", re.I), d.get("jobs") or {})
    want = {"%s.if" % n: 4 for n in ORGATED}
    want["shard-totality-mutations.if"] = 3
    tags = []
    for n in list(ORGATED) + ["shard-totality-mutations"]:
        if found.get("%s.if" % n, 0) != want["%s.if" % n]: tags.append("O-REF:%s.if:%d" % (n, found.get("%s.if" % n, 0)))
    # `.if` whitelist: only the seven pinned job-level conjuncts (counted above), oracle-index-check's job-level
    # `if:` and oracle-index-check's own step ifs (the checkout gate `oracle_only == 'true'`) may read the
    # outputs. ANY other `.if` — a step if inside a lane leg, the aggregator, or an ungated job — is a finding:
    # it could skip work while the job still concludes `success`.
    allowed_if = {"%s.if" % n for n in list(ORGATED) + ["shard-totality-mutations", "oracle-index-check"]}
    for loc, c in found.items():
        if loc in allowed_if or (loc.startswith("oracle-index-check.steps.") and loc.endswith(".if")): continue
        if loc.endswith(".if"): tags.append("O-REF-EXTRA:%s:%d" % (loc, c)); continue
        # the aggregator's oracle env entries, and oracle-index-check's own env reads of the outputs it validates
        if not loc.startswith("test.steps.") and not loc.startswith("oracle-index-check.steps."): tags.append("O-REF-EXTRA:%s:%d" % (loc, c))
    foundidx = census2(re.compile(r"needs\s*\.\s*oracle-index-check\b|needs\s*\[\s*['\"]oracle-index-check['\"]\s*\]", re.I), d.get("jobs") or {})
    if sum(foundidx.values()) < 1 or any(not k.startswith("test.steps.") for k in foundidx): tags.append("O-IDXREF:%s" % ",".join(sorted(foundidx)))
    # the switch itself: exactly two CI_ORACLE_LANE reads may exist — the job `if:` and one step env (SWITCH:).
    foundv = census2(re.compile(r"CI_ORACLE_LANE", re.I), d)
    sw = [k for k in foundv if k.endswith(".env.SWITCH")]
    if len(sw) != 1 or set(foundv) != {"jobs.oracle-selection.if", sw[0]} or any(v != 1 for v in foundv.values()):
        for k in sorted(foundv): tags.append("O-VARS:%s:%d" % (k, foundv[k]))
    print(" ".join(tags)); sys.exit(0)

if mode == "orasel":
    d, jobs = load()
    tags = []
    job = jobs.get("oracle-selection")
    if job is None:
        print("OSEL-JOB-MISSING"); sys.exit(0)
    if str(job.get("if", "")) != ORASEL_IF: tags.append("OSEL-JOBIF")
    if job.get("continue-on-error") is not True: tags.append("OSEL-JOBCOE")
    if "needs" in job: tags.append("OSEL-NEEDS")
    if job.get("permissions") != {"contents": "read"}: tags.append("OSEL-PERM")
    outs = job.get("outputs") or {}
    if set(outs) != {"oracle_only", "active", "skip_legs", "head_sha", "base_sha"}: tags.append("OSEL-OUTPUTS")
    steps = job.get("steps") or []
    runlines = [str(s.get("run", "")).strip() for s in steps if isinstance(s, dict)]
    # the driver step is a `run: |` block that sources the BASE-image classifier via `git show` (a PR must
    # never rewrite the oracle that judges it); a flat `run: bash scripts/ci-oracle-lane.sh` would run the
    # CANDIDATE tree's driver — pin the git-show mechanism, not just the path mention.
    if not any("git show" in r and "ci-oracle-lane" + ".sh" in r for r in runlines): tags.append("OSEL-RUN")
    # and the base must be the merge base image, spelled HEAD^1 (pull_request) or MERGE_GROUP_BASE_SHA.
    if not any("HEAD^1" in r and "MERGE_GROUP_BASE_SHA" in r for r in runlines): tags.append("OSEL-BASE")
    cos = [s for s in steps if isinstance(s, dict) and "uses" in s and "checkout" in str(s.get("uses"))]
    if len(cos) != 1 or str((cos[0].get("with") or {}).get("fetch-depth")) != "0": tags.append("OSEL-FETCH")
    print(" ".join(tags)); sys.exit(0)

if mode == "truth":
    d, jobs = load()
    tags = []
    for n in GATED:
        j = jobs.get(n) or {}
        # the PR-skip dimensions only exist for the three PR-gated jobs; for the rest they stay at the inert point
        acts = ("", "false", "true") if n in PRGATED else ("",)
        sks = ("", n, "test-webplat,test-bun,test-scripts-heavy", "test-scripts", "test-scripts-heavy,x") if n in PRGATED else ("",)
        hss = (("a" * 40, "a" * 40), ("a" * 40, "b" * 40), ("", ""), ("", "a" * 40)) if n in PRGATED else (("", ""),)
        # oracle dims: active x skip_legs x head-bound for the six lane legs; the shard leg evals on
        # the same conjunct minus the contains() membership (skips on event + active + bound head).
        oacs = ("", "true") if n in ORGATED or n in SHARDG else ("",)
        osks = ("", n, "x," + n, "test-scripts") if n in ORGATED else ("",)
        # shard now carries the head-bound terms too (the same conjunct minus the contains): sweep the ohs dim
        ohss = ("bound", "unbound", "empty") if n in ORGATED or n in SHARDG else ("",)
        for event in ("push", "pull_request", "merge_group", "workflow_dispatch"):
            for elide in ("", "false", "true"):
              for light in ("", "false", "true"):
               for active in acts:
                for sk in sks:
                 for hs, ph in hss:
                  for oac in oacs:
                   for osk in osks:
                    for ob in ohss:
                      needs_ = ("success", "failure") if event == "push" else ("skipped",)
                      for need in needs_:
                        # the oracle head compare is `== (pull_request.head.sha || merge_group.head_sha)`: a GH `||` takes
                        # the FIRST truthy operand, so the bound image is `ph or mgh` on EITHER event.
                        bound = ph or "c" * 40
                        got = ev(j.get("if"), event, elide, need, light=light, active=active, sk=sk, hs=hs, ph=ph,
                                 oac=oac, osk=osk, ohs=(bound if ob == "bound" else ("" if ob == "empty" else "d" * 40)), mgh="c" * 40)
                        prskip = n in PRGATED and event == "pull_request" and active == "true" and hs != "" and hs == ph and ("," + n + ",") in ("," + sk + ",")
                        orskip = n in ORGATED and event in ("pull_request", "merge_group") and oac == "true" and ob == "bound" and ("," + n + ",") in ("," + osk + ",")
                        want = not (event == "push" and elide == "true") and not (n in DLGATED and light == "true") and not prskip and not orskip
                        # the shard conjunct is the lane conjunct minus skip_legs membership: skips on
                        # event + active + bound head, whatever the list says.
                        if n in SHARDG and event in ("pull_request", "merge_group") and oac == "true" and ob == "bound": want = False
                        if got is None: tags.append("TT-ERR:%s" % n)
                        elif got != want: tags.append("TT:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s" % (n, event, elide or "empty", need, light or "empty", active or "empty", sk or "empty", "m" if hs and hs == ph else "x", oac or "empty", ob))
        if ev(j.get("if"), "push", "false", "success", cancelled=True) is not False and "always()" not in str(j.get("if")):
            tags.append("TT-CANCEL:" + n)
    print(" ".join(sorted(set(tags)))); sys.exit(0)

if mode == "darkequiv":
    # POST-REMOVAL PIN (S4 retirement, 2026-11-09): the dark-lever equivalence the old table measured is now
    # structural — a skipped selection job cannot differ from a ran one when no such job exists. The pin is the
    # absence direction: no `pr-selection` job key, and no job may need it. A re-introduced lever or consumer is
    # a tag, never silently green.
    d, jobs = load()
    tags = []
    if jobs.get("pr-selection") is not None: tags.append("DE-JOB-PRESENT")
    cons = sorted(n for n, j in jobs.items() if "pr-selection" in needs(j))
    for n in cons: tags.append("DE-CONS:%s" % n)
    print(" ".join(sorted(set(tags)))); sys.exit(0)

if mode == "agg":
    d, jobs = load()
    t = jobs.get("test")
    if t is None: print("A-MISSING"); sys.exit(0)
    rest = {k: v for k, v in t.items() if k not in ("needs", "if")}
    got = hashlib.sha256(json.dumps(rest, sort_keys=True).encode()).hexdigest()
    print("" if got == AGG else "A-DIGEST:" + got); sys.exit(0)

if mode == "aggbody":
    out = sys.argv[3]
    d, jobs = load()
    t = jobs["test"]; st = t["steps"][0]
    open(out + "/agg.sh", "w").write(st["run"])
    open(out + "/agg.env", "w").write("".join("%s\n" % k for k in (st.get("env") or {})))
    sys.exit(0)
sys.stderr.write("unknown mode\n"); sys.exit(2)
PY

chk() { ELIDE_TAIL="$ELIDE_TAIL" GATED_PINNED="$GATED_PINNED" DL_GATED_PINNED="$DL_GATED_PINNED" PR_GATED_PINNED="$PR_GATED_PINNED" PR_TERM_PRE="$PR_TERM_PRE" PRSEL_IF="$PRSEL_IF" LIGHT_CLAUSE="$LIGHT_CLAUSE" UNGATED_PINNED="$UNGATED_PINNED" AGG_DIGEST="$AGG_DIGEST" DRIVER_SH="${DRIVER_SH-}" OR_GATED_PINNED="$OR_GATED_PINNED" SHARD_GATED="$SHARD_GATED" OR_TERM_PRE="$OR_TERM_PRE" ORACLE_ONLY_TERM="$ORACLE_ONLY_TERM" ORASEL_IF="$ORASEL_IF" python3 "$SANDBOX/chk.py" "$@"; }
# The driver is read by the leg-parity row only. Its path is assembled from parts on purpose (the kb-consumer census otherwise follows a whole
# path literal into the driver and charges this suite with the knowledge-base strings the driver names).
DRV_STEM="scripts/ci-pr-"'selection'   # assembled, never literal: the residual census greps the retired name
DRIVER_SH="$REPO_ROOT/$DRV_STEM.sh"

# ── Helper: the gh shim ──────────────────────────────────────────────────────
cat > "$SANDBOX/shim/gh" <<'SH'
#!/usr/bin/env bash
# FIX: fixture dir. Files: runs.json, jobs-<id>.json, mode (ok|fail_runs|fail_jobs|bad_runs|bad_jobs|nonarray).
printf '%s\n' "$*" >> "$FIX/calls.log"
[ "${1:-}" = api ] || { echo "STUB-MISS: not api: $*" >> "$FIX/calls.log"; exit 64; }
[ -n "${GH_TOKEN:-}" ] || { echo "gh: GH_TOKEN required" >&2; exit 4; }
ep="${2:-}"
mode=$(cat "$FIX/mode" 2>/dev/null || echo ok)
runs_re="^repos/${GH_REPO}/actions/workflows/ci\\.yml/runs\\?event=merge_group&head_sha=[0-9a-f]{40}&per_page=100\$"
jobs_re="^repos/${GH_REPO}/actions/runs/([0-9]+)/jobs\\?per_page=100&filter=latest\$"
if [[ "$ep" =~ $runs_re ]]; then
  case "$mode" in
    fail_runs) printf 'boom\nelide=true\n::error::pwn\n' >&2; exit 1 ;;
    bad_runs) printf '{not json'; exit 0 ;;
    nonarray) printf '{"message":"rate limited"}'; exit 0 ;;
  esac
  if [ "${CATCHALL:-}" = 1 ]; then cat "$CATCHALL_RUNS"; exit 0; fi
  cat "$FIX/runs.json"; exit 0
elif [[ "$ep" =~ $jobs_re ]]; then
  id="${BASH_REMATCH[1]}"
  case "$mode" in
    fail_jobs) printf 'boom\nelide=true\n::error::pwn\n' >&2; exit 1 ;;
    bad_jobs) printf '{not json'; exit 0 ;;
  esac
  if [ "${CATCHALL:-}" = 1 ]; then cat "$CATCHALL_JOBS"; exit 0; fi
  [ -f "$FIX/jobs-$id.json" ] || { echo "STUB-MISS: no fixture for run $id" >> "$FIX/calls.log"; exit 64; }
  cat "$FIX/jobs-$id.json"; exit 0
fi
echo "STUB-MISS: unexpected endpoint: $ep" >> "$FIX/calls.log"
exit 64
SH
chmod +x "$SANDBOX/shim/gh"
# a `timeout` that always reports a timeout (exit 124), to prove a hung read becomes a full run
cat > "$SANDBOX/shim-timeout/timeout" <<'SH'
#!/usr/bin/env bash
exit 124
SH
chmod +x "$SANDBOX/shim-timeout/timeout"

# ── Fixture builders ─────────────────────────────────────────────────────────
# fx_run <id> <event> <status> <conclusion|null> <sha> <branch> <repo> <path> [title]
FXD=""
fx_new() { FXD="$1"; assert_fixture_dir "$FXD"; rm -rf "$FXD"; mkdir -p "$FXD"; : > "$FXD/runs.ndjson"; printf ok > "$FXD/mode"; : > "$FXD/calls.log"; }
fx_run() {
  assert_fixture_dir "$FXD"
  jq -nc --argjson id "$1" --arg ev "$2" --arg st "$3" --arg c "$4" --arg sha "$5" --arg br "$6" --arg repo "$7" --arg path "$8" --arg title "${9:-t}" \
    '{id:$id,event:$ev,status:$st,conclusion:(if $c=="null" then null else $c end),head_sha:$sha,head_branch:$br,path:$path,display_title:$title,head_repository:{full_name:$repo}}' >> "$FXD/runs.ndjson"
}
fx_flush() { assert_fixture_dir "$FXD"; jq -s '{workflow_runs: .}' "$FXD/runs.ndjson" > "$FXD/runs.json"; }
# fx_jobs <runid> name:conclusion ...
fx_jobs() {
  assert_fixture_dir "$FXD"
  local id="$1"; shift
  if [ "$#" -eq 0 ]; then printf '{"total_count":0,"jobs":[]}\n' > "$FXD/jobs-$id.json"; return; fi
  local args=() n c
  for pair in "$@"; do n="${pair%%:*}"; c="${pair#*:}"; args+=("$n" "$c"); done
  # the jobs API returns total_count alongside the page: the proof's pagination guard reads it (a run over
  # 100 jobs truncates page 1 and must fail closed, never elide). Fixtures emit the honest count.
  printf '%s\n' "${args[@]}" | jq -Rn '[inputs] as $a | {total_count: (($a|length)/2), jobs: [range(0; ($a|length); 2) | {name: $a[.], conclusion: (if $a[.+1]=="null" then null else $a[.+1] end)}]}' > "$FXD/jobs-$id.json"
}
# The canonical jobs list: every leg the oracle lane can skip must conclude `success` for the proof
# to hold (#12156, Guard 3) — the six heavy legs plus shard-totality-mutations — alongside `test`.
SEVEN_LEGS=(test-webplat test-webplat-mutations test-bun test-scripts test-scripts-heavy web-platform-build shard-totality-mutations)
GOOD_JOBS=(test-webplat:success test-webplat-mutations:success test-bun:success test-scripts:success test-scripts-heavy:success web-platform-build:success shard-totality-mutations:success test:success e2e:success)
QB="gh-readonly-queue/main/pr-1-$SHA_A"
fx_canonical() {
  fx_new "$1"
  fx_run "$MG_ID" merge_group completed success "$SHA_A" "$QB" "$REPO_SLUG" .github/workflows/ci.yml
  fx_jobs "$MG_ID" "${GOOD_JOBS[@]}"
  fx_flush
}

# ── Row runner: executes a body under the Actions shell against the shim ─────
# Globals per row: ROW_ENV (assoc of overrides), RB_SHIMPATH, RB_CATCHALL.
declare -A E
set_env_defaults() {
  E=([GH_TOKEN]=tok [GH_REPO]="$REPO_SLUG" [SHA]="$SHA_A" [EVENT_NAME]=push [REF]=refs/heads/main [RUN_ATTEMPT]=1 [SWITCH]=on)
}
BAT_N=0
BAT_LINES=""
ROWS_SEEN_REASONS=""
# row <id> <expect_elide> <expect_would> <expect_reason>   (fixture already built in $FXD, env in E)
row() {
  local id="$1" xe="$2" xw="$3" xr="$4" out so rc why=""
  BAT_N=$((BAT_N + 1))
  assert_fixture_dir "$FXD"
  out="$FXD/gh_output"; so="$FXD/stdout"; : > "$out"
  local pathv jqdir
  jqdir=$(dirname "$(command -v jq)")
  pathv="${RB_SHIMPATH:-/nonexistent}:$SANDBOX/shim:$jqdir:/usr/bin:/bin"
  ( cd "$FXD" && env -i PATH="$pathv" HOME="$FXD" FIX="$FXD" GITHUB_OUTPUT="$out" GITHUB_STEP_SUMMARY="$FXD/summary" \
      GH_TOKEN="${E[GH_TOKEN]}" GH_REPO="${E[GH_REPO]}" SHA="${E[SHA]}" EVENT_NAME="${E[EVENT_NAME]}" REF="${E[REF]}" \
      RUN_ATTEMPT="${E[RUN_ATTEMPT]}" SWITCH="${E[SWITCH]}" CATCHALL="${RB_CATCHALL:-}" CATCHALL_RUNS="${RB_CA_RUNS:-}" CATCHALL_JOBS="${RB_CA_JOBS:-}" \
      bash --noprofile --norc -eo pipefail "$BODY" > "$so" 2> "$FXD/stderr" )
  rc=$?
  [ "$rc" -eq 0 ] || why="$why rc=$rc"
  # every output line is a literal verdict
  local bad_lines
  bad_lines=$(grep -cvE '^(elide|would_elide)=(true|false)$' "$out" || true)
  [ "$bad_lines" = 0 ] || why="$why output-line-not-literal"
  # last-wins values
  local ge gw
  ge=$(grep -E '^elide=' "$out" | tail -n 1 | cut -d= -f2)
  gw=$(grep -E '^would_elide=' "$out" | tail -n 1 | cut -d= -f2)
  [ "$ge" = "$xe" ] || why="$why elide=$ge(want $xe)"
  [ "$gw" = "$xw" ] || why="$why would=$gw(want $xw)"
  if [ "$ge" = true ]; then
    [ "$(grep -E '^[a-z_]+=' "$out" | tail -n 1)" = "elide=true" ] || why="$why true-not-last"
  fi
  # stdout: only the one annotation, never a fixture string, mg_run numeric or none
  local nlines notices reason mg
  nlines=$(grep -c '' "$so" || true)
  notices=$(grep -cE '^::(notice|warning) title=ci-push-dedupe::sha=[0-9a-f]{40}|^::(notice|warning) title=ci-push-dedupe::sha=invalid' "$so" || true)
  [ "$nlines" = 1 ] && [ "$notices" = 1 ] || why="$why stdout-shape(lines=$nlines,annot=$notices)"
  if grep -qF 'pwn' "$so" "$out" "$FXD/summary" "$FXD/stderr" 2>/dev/null; then why="$why fixture-string-leaked"; fi
  reason=$(sed -n 's/.* reason=\([a-z_]*\) mg_run=.*/\1/p' "$so" | head -n 1)
  mg=$(sed -n 's/.* mg_run=\(.*\)$/\1/p' "$so" | head -n 1)
  [ "$reason" = "$xr" ] || why="$why reason=$reason(want $xr)"
  [[ "$mg" =~ ^(none|[0-9]+)$ ]] || why="$why mg_run=$mg"
  if grep -q 'STUB-MISS' "$FXD/calls.log" 2>/dev/null; then why="$why stub-miss"; fi
  ROWS_SEEN_REASONS="$ROWS_SEEN_REASONS $reason"
  if [ -z "$why" ]; then BAT_LINES="$BAT_LINES"$'\n'"ROW $id ok"; else BAT_LINES="$BAT_LINES"$'\n'"ROW $id bad:$why"; fi
}

# battery <body> [shim-path] : fills BAT_LINES, BAT_N, ROWS_SEEN_REASONS
battery() {
  BODY="$1"; RB_SHIMPATH=""; RB_CATCHALL="${2:-}"
  BAT_N=0; BAT_LINES=""; ROWS_SEEN_REASONS=""
  local d="$SANDBOX/bat" v ev
  # R01 canonical, variable on
  fx_canonical "$d"; set_env_defaults; row R01-canonical true true ok
  # R02 variable unset / empty
  fx_canonical "$d"; set_env_defaults; E[SWITCH]=""; row R02-switch-unset false true switch_off
  # R03 variable shapes that must NOT enable elision
  for v in ON " on " On true 1 yes "on " " on" onn; do
    fx_canonical "$d"; set_env_defaults; E[SWITCH]="$v"; row "R03-switch-[$v]" false true switch_off
  done
  # R04 other events are never elided and never proven
  for ev in pull_request merge_group workflow_dispatch schedule; do
    fx_canonical "$d"; set_env_defaults; E[EVENT_NAME]="$ev"; row "R04-event-$ev" false false not_push
  done
  # R05 other refs
  for v in refs/heads/foo refs/pull/1/merge refs/heads/main2 ""; do
    fx_canonical "$d"; set_env_defaults; E[REF]="$v"; row "R05-ref-[$v]" false false not_main
  done
  # R06 re-runs
  for v in 2 3 0 ""; do
    fx_canonical "$d"; set_env_defaults; E[RUN_ATTEMPT]="$v"; row "R06-attempt-[$v]" false false rerun
  done
  # R07 malformed SHA
  for v in abc "${SHA_A^^}" "${SHA_A}a" "${SHA_A:0:39}" "" "${SHA_A:0:39}g" $'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\nelide=true'; do
    fx_canonical "$d"; set_env_defaults; E[SHA]="$v"; row "R07-sha-[${v:0:12}]" false false bad_sha
  done
  # R08 merge_group run state other than completed+success
  for v in "in_progress:null" "queued:null" "completed:cancelled" "completed:failure" "completed:skipped" "completed:timed_out" "completed:neutral" "completed:null" "in_progress:success" "queued:success"; do
    fx_new "$d"; fx_run "$MG_ID" merge_group "${v%%:*}" "${v#*:}" "$SHA_A" "$QB" "$REPO_SLUG" .github/workflows/ci.yml
    fx_jobs "$MG_ID" "${GOOD_JOBS[@]}"; fx_flush
    set_env_defaults; row "R08-state-$v" false false no_mg_success
  done
  # R09 a lagging search returns a run for another SHA
  fx_new "$d"; fx_run "$MG_ID" merge_group completed success "$SHA_B" "gh-readonly-queue/main/pr-2-$SHA_B" "$REPO_SLUG" .github/workflows/ci.yml
  fx_jobs "$MG_ID" "${GOOD_JOBS[@]}"; fx_flush; set_env_defaults; row R09-other-sha false false no_mg_success
  # R10 branch prefix
  for v in main feature/x gh-readonly-queue/other/pr-1 "x/gh-readonly-queue/main/pr-1" gh-readonly-queue/main; do
    fx_new "$d"; fx_run "$MG_ID" merge_group completed success "$SHA_A" "$v" "$REPO_SLUG" .github/workflows/ci.yml
    fx_jobs "$MG_ID" "${GOOD_JOBS[@]}"; fx_flush; set_env_defaults; row "R10-branch-[$v]" false false no_mg_success
  done
  # R11 the `test` job: missing, skipped, failed, cancelled, prefix collision only
  for v in "test-scripts (1/8):success" "test:skipped" "test:failure" "test:cancelled" "test:null" "tests:success" "Test:success" "test-scripts:success"; do
    fx_new "$d"; fx_run "$MG_ID" merge_group completed success "$SHA_A" "$QB" "$REPO_SLUG" .github/workflows/ci.yml
    fx_jobs "$MG_ID" test-webplat:success e2e:success "$v"; fx_flush; set_env_defaults; row "R11-test-job-[$v]" false false no_test_job
  done
  fx_new "$d"; fx_run "$MG_ID" merge_group completed success "$SHA_A" "$QB" "$REPO_SLUG" .github/workflows/ci.yml
  fx_jobs "$MG_ID"; fx_flush; set_env_defaults; row R11-empty-job-list false false no_test_job
  # R12 API failure shapes: every one is a full run with reason proof_error
  for v in fail_runs bad_runs nonarray fail_jobs bad_jobs; do
    fx_canonical "$d"; printf '%s' "$v" > "$d/mode"; set_env_defaults; row "R12-api-$v" false false proof_error
  done
  fx_canonical "$d"; set_env_defaults; RB_SHIMPATH="$SANDBOX/shim-timeout"; row R12-api-timeout false false proof_error; RB_SHIMPATH=""
  fx_canonical "$d"; set_env_defaults; E[GH_TOKEN]=""; row R12-no-token false false proof_error
  # R13 binding: a run that is not a merge_group run of THIS repository's ci.yml cannot vouch, even on a queue-named branch
  for v in pull_request workflow_dispatch push schedule; do
    fx_new "$d"; fx_run "$MG_ID" "$v" completed success "$SHA_A" "$QB" "$REPO_SLUG" .github/workflows/ci.yml
    fx_jobs "$MG_ID" "${GOOD_JOBS[@]}"; fx_flush; set_env_defaults; row "R13-event-$v" false false no_mg_success
  done
  fx_new "$d"; fx_run "$MG_ID" merge_group completed success "$SHA_A" "$QB" "attacker/soleur" .github/workflows/ci.yml
  fx_jobs "$MG_ID" "${GOOD_JOBS[@]}"; fx_flush; set_env_defaults; row R13-fork-repo false false no_mg_success
  for v in .github/workflows/other.yml .github/workflows/x-ci.yml ci.yml ".github/workflows/ci.yml@refs/heads/main"; do
    fx_new "$d"; fx_run "$MG_ID" merge_group completed success "$SHA_A" "$QB" "$REPO_SLUG" "$v"
    fx_jobs "$MG_ID" "${GOOD_JOBS[@]}"; fx_flush; set_env_defaults; row "R13-path-[$v]" false false no_mg_success
  done
  fx_new "$d"; fx_run "$MG_ID" merge_group completed success "$SHA_A" "$QB" "$REPO_SLUG" ""
  fx_jobs "$MG_ID" "${GOOD_JOBS[@]}"; fx_flush; set_env_defaults; row R13-empty-path false false no_mg_success
  # R14 injection: a poisoned title/branch on a MATCHING run (poisoned stderr on a failing read is the R12 rows, via row()'s leak check)
  fx_new "$d"; fx_run "$MG_ID" merge_group completed success "$SHA_A" "gh-readonly-queue/main/$POISON" "$REPO_SLUG" .github/workflows/ci.yml "$POISON"
  fx_jobs "$MG_ID" "${GOOD_JOBS[@]}"; fx_flush; set_env_defaults; row R14-poisoned-match true true ok
  # R15 permitted shapes that are NOT the canonical fixture
  fx_new "$d"; fx_run 100 merge_group completed failure "$SHA_A" "$QB" "$REPO_SLUG" .github/workflows/ci.yml
  fx_run "$MG_ID" merge_group completed success "$SHA_A" "$QB" "$REPO_SLUG" .github/workflows/ci.yml
  fx_jobs 100 test:failure; fx_jobs "$MG_ID" "${GOOD_JOBS[@]}"; fx_flush
  # reverse listing order: success first, older failure second
  jq -s '{workflow_runs: (. | reverse)}' "$d/runs.ndjson" > "$d/runs.json"
  set_env_defaults; row R15-two-runs-reverse-order true true ok
  fx_new "$d"; fx_run "$MG_ID" merge_group completed success "$SHA_A" "$QB" "$REPO_SLUG" .github/workflows/ci.yml
  fx_jobs "$MG_ID" lint-bot-statuses:skipped e2e:success test:success test-webplat:success test-webplat-mutations:success test-bun:success test-scripts:success test-scripts-heavy:success web-platform-build:success shard-totality-mutations:success advisory:skipped; fx_flush
  set_env_defaults; row R15-job-order-extra-advisory true true ok
  fx_canonical "$d"; set_env_defaults; E[SWITCH]=on; row R15-switch-on-canonical-again true true ok
  # R16 the proof is evaluated for the dark phase: variable unset, canonical, would be elided
  fx_canonical "$d"; set_env_defaults; E[SWITCH]=""; row R16-dark-would-elide false true switch_off
  # R17 a run id that is not digits never reaches a URL (it would add path segments to the jobs read)
  fx_new "$d"; jq -nc --arg sha "$SHA_A" --arg br "$QB" --arg repo "$REPO_SLUG" '{id:"111/../../../../repos/x",event:"merge_group",status:"completed",conclusion:"success",head_sha:$sha,head_branch:$br,path:".github/workflows/ci.yml",head_repository:{full_name:$repo}}' >> "$d/runs.ndjson"
  fx_flush; set_env_defaults; row R17-nonnumeric-run-id false false proof_error
  # R18 the oracle-lane seven-leg proof (#12156, Guard 3): an oracle-reduced merge_group green must NOT elide the
  # push run — every leg the lane can skip (the six heavy legs + shard-totality-mutations) must conclude
  # `success`. A `skipped`, absent or malformed leg entry fails closed. The implementation's reason token for
  # "a required leg did not conclude success" is `legs_incomplete` (distinct from `no_test_job`, which stays
  # reserved for the `test` job itself not concluding success).
  seven_ok() {  # $1=fxdir $2=omit-leg|"" $3=override name:conclusion|""
    local fx="$1" omit="$2" over="${3:-}" j=()
    for _l in "${SEVEN_LEGS[@]}"; do
      [ "$_l" = "$omit" ] && continue
      if [ -n "$over" ] && [ "${over%%:*}" = "$_l" ]; then j+=("$over"); else j+=("$_l:success"); fi
    done
    j+=(test:success e2e:success)
    fx_new "$fx"; fx_run "$MG_ID" merge_group completed success "$SHA_A" "$QB" "$REPO_SLUG" .github/workflows/ci.yml
    fx_jobs "$MG_ID" "${j[@]}"; fx_flush
  }
  local _l
  for _l in "${SEVEN_LEGS[@]}"; do
    seven_ok "$d" "" "$_l:skipped"; set_env_defaults; row "R18-leg-skipped-$_l" false false legs_incomplete
    seven_ok "$d" "$_l"; set_env_defaults; row "R18-leg-absent-$_l" false false legs_incomplete
  done
  # malformed/absent conclusions on a required leg: failure, null, cancelled, and a case variant
  for _v in failure null cancelled Success; do
    seven_ok "$d" "" "test-webplat:$_v"; set_env_defaults; row "R18-leg-conclusion-$_v" false false legs_incomplete
  done
  # matrix member rows name the leg with a ` (N/M)` suffix: they satisfy the leg only when ALL succeed;
  # a skipped matrix member fails closed; a `test-scripts-heavy` matrix row can never satisfy `test-scripts`.
  seven_ok "$d" "test-scripts"; set_env_defaults
  jq '.jobs += [{"name":"test-scripts (1/4)","conclusion":"success"},{"name":"test-scripts (2/4)","conclusion":"success"},{"name":"test-scripts (3/4)","conclusion":"success"},{"name":"test-scripts (4/4)","conclusion":"success"}]' "$d/jobs-$MG_ID.json" > "$d/j.json" && mv "$d/j.json" "$d/jobs-$MG_ID.json"
  row R18-matrix-members-all-success true true ok
  seven_ok "$d" "test-scripts"; set_env_defaults
  jq '.jobs += [{"name":"test-scripts (1/2)","conclusion":"success"},{"name":"test-scripts (2/2)","conclusion":"skipped"}]' "$d/jobs-$MG_ID.json" > "$d/j.json" && mv "$d/j.json" "$d/jobs-$MG_ID.json"
  row R18-matrix-member-skipped false false legs_incomplete
  seven_ok "$d" "test-scripts"; set_env_defaults
  jq '.jobs += [{"name":"test-scripts-heavy (1/2)","conclusion":"success"},{"name":"test-scripts-heavy (2/2)","conclusion":"success"}]' "$d/jobs-$MG_ID.json" > "$d/j.json" && mv "$d/j.json" "$d/jobs-$MG_ID.json"
  row R18-prefix-trap-heavy-not-scripts false false legs_incomplete
  # a name that merely SHARES a prefix is not the leg
  seven_ok "$d" "test-webplat"; set_env_defaults
  jq '.jobs += [{"name":"test-webplatx","conclusion":"success"}]' "$d/jobs-$MG_ID.json" > "$d/j.json" && mv "$d/j.json" "$d/jobs-$MG_ID.json"
  row R18-prefix-trap-webplatx false false legs_incomplete
  # e2e is NOT in the required set (the lane never skips it, so the proof does not demand it); unknown
  # extra legs do not matter either way
  seven_ok "$d" "" "e2e:skipped"; set_env_defaults; row R18-e2e-not-required true true ok
  seven_ok "$d" ""; set_env_defaults
  jq '.jobs += [{"name":"future-leg","conclusion":"skipped"}]' "$d/jobs-$MG_ID.json" > "$d/j.json" && mv "$d/j.json" "$d/jobs-$MG_ID.json"
  row R18-unknown-extra-leg true true ok
  # Guard 3 row 4 (must-PASS non-canonical): all seven legs + test success in a different job order
  fx_new "$d"; fx_run "$MG_ID" merge_group completed success "$SHA_A" "$QB" "$REPO_SLUG" .github/workflows/ci.yml
  fx_jobs "$MG_ID" shard-totality-mutations:success test:success web-platform-build:success e2e:success test-scripts-heavy:success test-scripts:success test-bun:success test-webplat-mutations:success test-webplat:success
  fx_flush; set_env_defaults; row R18-all-success-reordered true true ok
  unset -f seven_ok
  # R19 the pagination guard: a jobs API page-1 total_count over 100 truncates the page — the proof cannot see
  # every leg, so it fails closed (page_truncated), never elides. Boundary: 100 elides, 101 does not.
  fx_canonical "$d"; set_env_defaults; row R19-page-boundary-100 true true ok
  fx_canonical "$d"; jq '.total_count = 101' "$d/jobs-$MG_ID.json" > "$d/j.json" && mv "$d/j.json" "$d/jobs-$MG_ID.json"
  set_env_defaults; row R19-page-truncated-101 false false page_truncated
  fx_canonical "$d"; jq '.total_count = 2000' "$d/jobs-$MG_ID.json" > "$d/j.json" && mv "$d/j.json" "$d/jobs-$MG_ID.json"
  set_env_defaults; row R19-page-truncated-huge false false page_truncated
  fx_canonical "$d"; jq '.total_count = null' "$d/jobs-$MG_ID.json" > "$d/j.json" && mv "$d/j.json" "$d/jobs-$MG_ID.json"
  set_env_defaults; row R19-total-count-null false false page_truncated
  fx_canonical "$d"; jq 'del(.total_count)' "$d/jobs-$MG_ID.json" > "$d/j.json" && mv "$d/j.json" "$d/jobs-$MG_ID.json"
  set_env_defaults; row R19-total-count-absent false false page_truncated
}

# ── Extract the live body ────────────────────────────────────────────────────
LIVE="$SANDBOX/live"
chk extract "$WF" "$LIVE" 2> "$SANDBOX/extract.err"; EXTRACT_RC=$?
if [ "$EXTRACT_RC" -ne 0 ]; then
  fail "EXTRACT: the push-dedupe proof step could not be extracted from ci.yml (rc=$EXTRACT_RC: $(head -c 200 "$SANDBOX/extract.err"))"
  # Everything below needs a body; report and stop so the failure is the extraction, not a cascade.
  printf 'ci-push-dedupe: %d passed, %d failed\n' "$passes" "$fails"
  exit 1
fi
cp "$LIVE/body.sh" "$SANDBOX/pristine-body.sh"
bash -n "$LIVE/body.sh" 2>/dev/null && pass || fail "SYNTAX: the extracted body does not parse under bash -n"

# ── Control run of the battery on the live body ──────────────────────────────
battery "$LIVE/body.sh"
CTRL_N=$BAT_N; CTRL_LINES="$BAT_LINES"; CTRL_REASONS="$ROWS_SEEN_REASONS"
_ok=0; _bad=0
while IFS= read -r ln; do
  case "$ln" in
    "ROW "*" ok") _ok=$((_ok + 1)); pass ;;
    "ROW "*) _bad=$((_bad + 1)); fail "BATTERY ${ln#ROW }" ;;
  esac
done <<<"$CTRL_LINES"
# independent producer count: the rows executed (counter in row()) must equal the verdict lines read back
if [ "$CTRL_N" -eq $((_ok + _bad)) ] && [ "$CTRL_N" -ge 78 ]; then pass
else fail "BATTERY COUNT: row() ran $CTRL_N rows but $((_ok + _bad)) verdict lines were read (floor 78)"; fi
# every reason code in the enum is reached at least once, taken from what the body PRINTED
_missing=""
for r in $REASONS; do
  case " $CTRL_REASONS " in *" $r "*) ;; *) _missing="$_missing $r" ;; esac
done
if [ -z "$_missing" ]; then pass; else fail "REASONS: never reached:$_missing"; fi

# ── Wrapper, gated set, truth table, aggregator ──────────────────────────────
# A checker that CRASHES prints nothing to stdout; its exit status is part of its verdict.
live_check() { # <label> <mode>
  local out rc
  out=$(chk "$2" "$WF" 2>"$SANDBOX/chk.err"); rc=$?
  if [ "$rc" -ne 0 ]; then fail "$1: the checker crashed (rc=$rc: $(head -c 160 "$SANDBOX/chk.err"))"
  elif [ -n "$out" ]; then fail "$1 tags: $out"
  else pass; fi
}
live_check WRAPPER wrapper
live_check "GATED" gated
live_check "PR-SELECTION ABSENT (S4 retired)" prsel
live_check "PR-SELECTION REFERENCE CENSUS (zero allowed)" prcensus
live_check "LEG PARITY (post-removal absence)" legparity
live_check "TRUTH TABLE" truth
live_check "DARK LEVER ABSENT (S4 retired)" darkequiv
live_check "ORACLE-SELECTION OUTPUT CENSUS" ocensus
live_check "ORACLE-SELECTION JOB" orasel
live_check AGGREGATOR agg

# Guard 3 bi-directional leg-name pin (#12156): the proof's required set is EXACTLY the seven skippable
# legs (the six heavy legs + shard-totality-mutations) plus `test`. A NEW skippable leg must edit the
# driver allowlist, the aggregator regex AND this proof in the same diff — the sentinel pins all three.
for _l in "${SEVEN_LEGS[@]}"; do
  if grep -qF -- "\"$_l\"" "$SANDBOX/pristine-body.sh"; then pass; else fail "SEVEN-LEG PIN: the proof body never names '$_l' — the leg the oracle lane can skip is absent from the elide proof"; fi
done
unset _l
# Guard 3 leg-conclusion blindness: the proof's CODE reads job conclusions only — it must never name an oracle
# term (lane outputs live on `oracle-selection`, not in the sibling results it sums). Comments are stripped
# first: the Guard-3 comment block legitimately names the lane it backstops; a CODE-level hit is a real flag.
if grep -qiE 'oracle' < <(grep -v '^[[:space:]]*#' "$SANDBOX/pristine-body.sh"); then
  fail "SEVEN-LEG BLINDNESS: the elide proof body references an oracle term in executable code — the proof must read leg conclusions only, never lane outputs"
else
  pass
fi
# the six-name allowlist the aggregator tolerates (ORACLE-ONLY-SKIP) must equal SEVEN_LEGS minus
# shard-totality-mutations — assert each name appears in the extracted aggregator body.
chk aggbody "$WF" "$SANDBOX/live" 2>/dev/null
for _l in test-webplat test-webplat-mutations test-bun test-scripts test-scripts-heavy web-platform-build; do
  if [ -s "$SANDBOX/live/agg.sh" ] && grep -qF -- "$_l" "$SANDBOX/live/agg.sh"; then pass; else fail "SIX-LEG PARITY: the aggregator never names '$_l' — the ORACLE-ONLY-SKIP allowlist and the proof's required set drifted apart"; fi
done
unset _l

# ── The release workflow's CI budget ───────────────────────────────────────────────────────────────────────
# web-platform-release.yml sums the longest declared `needs:` path through ci.yml and hard-fails above a cap (75 minutes). The S4
# pr-selection lever retired 2026-11-09, so today the zeroed-copy comparison is the identity — kept as a re-introduction guard: a
# re-added `pr-selection` job resumes the real comparison (zero-prsel writes timeout 0 again) and a serial edge or a longer bound
# on it lengthens the path. The function is EXTRACTED from the release workflow and EXECUTED against ci.yml (never re-implemented
# here), once as shipped and once with the lever's job-level timeout rewritten to 0; the two must be equal.
REL_YML="$REPO_ROOT/.github/workflows/web-platform-release.yml"
awk '/^          run_declared_path\(\) \{/{f=1} f{print} f&&/^          }$/{exit}' "$REL_YML" | sed 's/^          //' > "$SANDBOX/rdp.sh"
declared_path() { bash --noprofile --norc -c 'source "$1"; run_declared_path "$2"' _ "$SANDBOX/rdp.sh" "$1" 2>/dev/null; }
budget_tag() { # <ci.yml copy> -> empty when a lever job adds nothing to the declared path, else a tag
  local z="$SANDBOX/mut/zero.$RANDOM.yml" a b
  chk zero-prsel "$1" "$z" 2>/dev/null || { echo "B-ZERO-FAILED"; return; }
  a=$(declared_path "$1"); b=$(declared_path "$z")
  case "$a$b" in ""|*[!0-9]*) echo "B-UNMEASURED"; return ;; esac
  [ "$a" -eq "$b" ] || echo "B-PATH:$a>$b"
}
if [ -s "$SANDBOX/rdp.sh" ] && [ -z "$(budget_tag "$WF")" ] && [ "$(declared_path "$WF")" -gt 0 ] 2>/dev/null; then pass
else fail "BUDGET: the lever job lengthens the declared needs: path ($(budget_tag "$WF") / extracted $(wc -l <"$SANDBOX/rdp.sh") lines); web-platform-release.yml would fail the CI budget on every push"; fi
# the canonical condition is restated by two pre-existing suites' carve-outs; each ASSIGNMENT must still equal ci.yml's
# (the needle starts at the assignment head, so a comment or prose copy of the literal cannot satisfy it)
for pair in "plugins/soleur/test/ci-e2e-skip-anchors.test.sh|E2E_ELIDE_IF=\"if: \\\${{ !cancelled() && " "plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh|_ALLOWED_IF = (\"always()\", \"\${{ always() && "; do
  f="${pair%%|*}"; lit="${pair#*|}$ELIDE_TAIL"
  if [ "$(grep -cF -- "$lit" "$REPO_ROOT/$f")" -eq 1 ]; then pass; else fail "PARITY: $f no longer carries the canonical condition in its assignment ($lit)"; fi
done

# the proof demands only the `test` job: that is sound only while the aggregator concludes red on a
# skipped leg. Execute the extracted aggregator over a merge_group triple with one gated leg skipped.
chk aggbody "$WF" "$SANDBOX/live" 2>/dev/null
agg_run() { # <skipped-leg-var|none>
  local envs=() k
  while IFS= read -r k; do
    [ -n "$k" ] || continue
    case "$k" in EVENT_NAME) envs+=("EVENT_NAME=merge_group") ;; *) envs+=("$k=success") ;; esac
  done < "$SANDBOX/live/agg.env"
  [ "$1" = none ] || envs+=("$1=skipped")
  env -i PATH=/usr/bin:/bin "${envs[@]}" bash --noprofile --norc -eo pipefail "$SANDBOX/live/agg.sh" >/dev/null 2>&1
}
if [ -s "$SANDBOX/live/agg.sh" ]; then
  agg_run none; rc0=$?
  agg_run SCRIPTS_RESULT; rc1=$?
  agg_run BUN_RESULT; rc2=$?
  agg_run BUILD_RESULT; rc3=$?
  if [ "$rc0" -eq 0 ] && [ "$rc1" -ne 0 ] && [ "$rc2" -ne 0 ] && [ "$rc3" -ne 0 ]; then pass
  else fail "COUPLING: the aggregator must pass on an all-success triple (rc=$rc0) and fail on a skipped leg (scripts rc=$rc1, bun rc=$rc2, build rc=$rc3)"; fi
else
  fail "COUPLING: the test aggregator body could not be extracted"
fi

# ── Mutation rows ────────────────────────────────────────────────────────────
MUT_RUN=0; MUT_CAUGHT=0
cat > "$SANDBOX/mut.py" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src).read()
if s.count(old) != 1:
    sys.stderr.write("anchor count %d for %r\n" % (s.count(old), old)); sys.exit(3)
open(dst, "w").write(s.replace(old, new))
PY
# mutate_body <name> <old> <new> <expected-row-prefix>: the battery on the mutant must flag a row with the prefix
mutate_body() {
  local name="$1" old="$2" new="$3" want="$4" f got
  f="$SANDBOX/mut/$name.sh"
  MUT_RUN=$((MUT_RUN + 1))
  if ! python3 "$SANDBOX/mut.py" "$SANDBOX/pristine-body.sh" "$f" "$old" "$new" 2>"$SANDBOX/mut.err"; then
    fail "MUTANT $name: mutation did NOT land ($(head -c 120 "$SANDBOX/mut.err"))"; return
  fi
  if cmp -s "$f" "$SANDBOX/pristine-body.sh"; then fail "MUTANT $name: mutant is byte-identical to the pristine body"; return; fi
  battery "$f"
  if [ "$want" = NONE ]; then # known-negative control: a harmless edit must leave EVERY row green
    got=$(grep -E "^ROW .* bad:" <<<"$BAT_LINES" | head -n 1)
    if [ -z "$got" ]; then MUT_CAUGHT=$((MUT_CAUGHT + 1)); pass; else fail "CONTROL $name: a harmless edit turned a row red ($got)"; fi
    return
  fi
  got=$(grep -E "^ROW $want.* bad:" <<<"$BAT_LINES" | head -n 1)
  if [ -n "$got" ]; then MUT_CAUGHT=$((MUT_CAUGHT + 1)); pass
  else fail "MUTANT $name: no row with prefix $want went red"; fi
}
mutate_body c-harmless-noop 'note=invalid' 'note=invalid; :' NONE
# the verdict logic itself must be able to say "not caught": a mutant that changes nothing observable is refused above
mutate_body m-switch-case '[ "$SWITCH" = on ]' '[ "${SWITCH,,}" = on ]' R03
mutate_body m-switch-always '[ "$SWITCH" = on ]' 'true' R03
mutate_body m-no-push-check '[ "$EVENT_NAME" = push ] || finish' 'true' R04
mutate_body m-no-main-check '[ "$REF" = refs/heads/main ] || finish' 'true' R05
mutate_body m-no-attempt-check '[ "$RUN_ATTEMPT" = 1 ] || finish' 'true' R06
mutate_body m-no-sha-check '[[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || finish' 'true' R07
mutate_body m-conclusion '.conclusion == "success" and .head_sha' '.head_sha' R08
mutate_body m-status '.status == "completed" and .conclusion' '.conclusion' R08
mutate_body m-no-sha-recheck ' and .head_sha == $sha' '' R09
mutate_body m-no-branch-prefix ' and ((.head_branch // "") | startswith("gh-readonly-queue/main/"))' '' R10
mutate_body m-test-prefix '.name == "test" and' '(.name | startswith("test")) and' R11
mutate_body m-test-conclusion 'select(.name == "test" and .conclusion == "success")' 'select(.name == "test")' R11
mutate_body m-no-event-check '.event == "merge_group" and ' '' R13
mutate_body m-no-repo-check ' and .head_repository.full_name == $repo' '' R13
mutate_body m-no-path-check ' and .path == ".github/workflows/ci.yml"' '' R13
mutate_body m-path-endswith '.path == ".github/workflows/ci.yml"' '(.path | endswith("ci.yml"))' R13
mutate_body m-runs-stderr 'head_sha=${SHA}&per_page=100" 2>/dev/null) || finish' 'head_sha=${SHA}&per_page=100") || finish' R12
mutate_body m-jobs-stderr 'filter=latest" 2>/dev/null) || finish' 'filter=latest") || finish' R12
# fail-open on a failed read (the read is replaced by a vouching answer): must go red on the failure rows
_open_runs=$(cat <<'EOS'
head_sha=${SHA}&per_page=100" 2>/dev/null) || runs=$(printf '{"workflow_runs":[{"event":"merge_group","status":"completed","conclusion":"success","head_sha":"%s","path":".github/workflows/ci.yml","head_repository":{"full_name":"%s"},"head_branch":"gh-readonly-queue/main/x","id":111}]}' "$SHA" "$GH_REPO")
EOS
)
mutate_body m-runs-failure-fails-open 'head_sha=${SHA}&per_page=100" 2>/dev/null) || finish' "$_open_runs" R12
mutate_body m-jobs-failure-fails-open 'filter=latest" 2>/dev/null) || finish' 'filter=latest" 2>/dev/null) || jobs='"'"'{"jobs":[{"name":"test","conclusion":"success"}]}'"'"'' R12
mutate_body m-echo-branch "printf '::notice title=ci-push-dedupe::sha=%s" "printf '%s' \"\$runs\"; printf '::notice title=ci-push-dedupe::sha=%s" R14
# REORDER: write elide=true before the jobs read, with a jobs read that fails (R12-api-fail_jobs must go red)
mutate_body m-reorder-true 'mg="$id"' 'mg="$id"; emit "elide=true"' R12
mutate_body m-default-after-gh 'emit "elide=false"' ':' R12
mutate_body m-mgid-unchecked '[[ "$id" =~ ^[0-9]+$ ]] || finish' 'true' R17
# Guard 3 mutants: dropping each required leg name from the proof must turn an R18 (or the canonical)
# row red — the replaced name is a job that never exists, so the canonical fixture fails the proof.
for _l in "${SEVEN_LEGS[@]}"; do
  mutate_body "m-leg-dropped-${_l}" "\"$_l\"" "\"zz-not-a-job\"" R18
done
unset _l
# and the whole six-leg requirement gone (only `test` checked again): every R18 row must go red.
mutate_body m-six-leg-check-gone ',"shard-totality-mutations"' ',"test"' R18

# EQUIVALENT mutants, recorded rather than hidden: each removes a guard that a LATER guard repeats, so no verdict
# changes (a failed runs read leaves the listing empty, which the array check, then the id extraction, both refuse).
# Reading 2 of "a surviving mutant" in the work skill: equivalent, proven by the battery staying green on it.
EQUIV_RUN=0; EQUIV_OK=0
mutate_body_equiv() {
  local name="$1" old="$2" new="$3" f
  f="$SANDBOX/mut/$name.sh"; EQUIV_RUN=$((EQUIV_RUN + 1))
  if ! python3 "$SANDBOX/mut.py" "$SANDBOX/pristine-body.sh" "$f" "$old" "$new" 2>"$SANDBOX/mut.err"; then
    fail "EQUIVALENT $name: mutation did NOT land"; return
  fi
  battery "$f"
  if [ -z "$(grep -E '^ROW .* bad:' <<<"$BAT_LINES")" ]; then EQUIV_OK=$((EQUIV_OK + 1)); pass
  else fail "EQUIVALENT $name: expected no row to go red, but these did:$(grep -E '^ROW .* bad:' <<<"$BAT_LINES" | tr '\n' ';') (not equivalent: add a killing row)"; fi
}
mutate_body_equiv e-runs-failure-ignored 'head_sha=${SHA}&per_page=100" 2>/dev/null) || finish' 'head_sha=${SHA}&per_page=100" 2>/dev/null) || true'
mutate_body_equiv e-nonarray-check-dropped "jq -e '.workflow_runs | type == \"array\"' >/dev/null 2>&1 || finish" 'cat >/dev/null'

# harness: a stub proof that always elides must be refused by the battery
printf '%s\n' 'printf "elide=true\nwould_elide=true\n" >> "$GITHUB_OUTPUT"; printf "::notice title=ci-push-dedupe::sha=invalid would_elide=true elide=true reason=ok mg_run=none\n"; exit 0' > "$SANDBOX/mut/stub-always.sh"
MUT_RUN=$((MUT_RUN + 1))
battery "$SANDBOX/mut/stub-always.sh"
_n_bad=$(grep -cE '^ROW .* bad:' <<<"$BAT_LINES" || true)
if [ "$_n_bad" -ge 50 ]; then MUT_CAUGHT=$((MUT_CAUGHT + 1)); pass; else fail "HARNESS H1: an always-elide stub went red on only $_n_bad rows (floor 50)"; fi
# harness: a catch-all gh shim (canonical fixture for every call) must not let the must-be-false rows pass
fx_canonical "$SANDBOX/ca"; RB_CA_RUNS="$SANDBOX/ca/runs.json"; RB_CA_JOBS="$SANDBOX/ca/jobs-$MG_ID.json"
MUT_RUN=$((MUT_RUN + 1))
battery "$LIVE/body.sh" 1
RB_CA_RUNS=""; RB_CA_JOBS=""
if grep -qE '^ROW R(08|09|10|11|13)' <<<"$(grep -E '^ROW .* bad:' <<<"$BAT_LINES")"; then MUT_CAUGHT=$((MUT_CAUGHT + 1)); pass
else fail "HARNESS H2: with a catch-all gh shim the no_mg_success / no_test_job rows must still go red"; fi

# workflow mutants: yml copies run through the checkers
# mutate_yml <name> <old> <new> <mode> <expected-tag-prefix>
mutate_yml() {
  local name="$1" old="$2" new="$3" cmode="$4" want="$5" f got
  f="$SANDBOX/mut/$name.yml"
  MUT_RUN=$((MUT_RUN + 1))
  if ! python3 "$SANDBOX/mut.py" "$WF" "$f" "$old" "$new" 2>"$SANDBOX/mut.err"; then
    fail "MUTANT $name: mutation did NOT land ($(head -c 120 "$SANDBOX/mut.err"))"; return
  fi
  cmp -s "$f" "$WF" && { fail "MUTANT $name: byte-identical to ci.yml"; return; }
  got=$(chk "$cmode" "$f" 2>/dev/null)
  case " $got " in
    *" $want"*) MUT_CAUGHT=$((MUT_CAUGHT + 1)); pass ;;
    *) fail "MUTANT $name: checker $cmode did not report $want (got: ${got:0:160})" ;;
  esac
}
COND_DEFAULT="if: \${{ !cancelled() && $ELIDE_TAIL && $(or_term test-bun) }}"
BUN_HDR="  test-bun:
    needs: [push-dedupe, oracle-selection]
    $COND_DEFAULT"
# anchors carry the push-dedupe-only line that follows (`SHA:` / `actions: read`) so they stay unique now that draft-light (S3) has the same shape
mutate_yml y-no-coe "        continue-on-error: true
        timeout-minutes: 2
        env:
          GH_TOKEN: \${{ github.token }}
          GH_REPO: \${{ github.repository }}
          SHA:" "        timeout-minutes: 2
        env:
          GH_TOKEN: \${{ github.token }}
          GH_REPO: \${{ github.repository }}
          SHA:" wrapper W-COE
mutate_yml y-no-step-timeout "        timeout-minutes: 2
        env:
          GH_TOKEN: \${{ github.token }}
          GH_REPO: \${{ github.repository }}
          SHA:" "        timeout-minutes: 9
        env:
          GH_TOKEN: \${{ github.token }}
          GH_REPO: \${{ github.repository }}
          SHA:" wrapper W-STEPTIMEOUT
mutate_yml y-job-timeout "    timeout-minutes: 3
    permissions:
      actions: read" "    timeout-minutes: 5
    permissions:
      actions: read" wrapper W-JOBTIMEOUT
mutate_yml y-no-output "      elide: \${{ steps.proof.outputs.elide }}" "      elide: \${{ steps.proof.outputs.would_elide }}" wrapper W-OUTPUTS
mutate_yml y-perm "      actions: read" "      actions: write" wrapper W-PERM
mutate_yml y-success-fn "$BUN_HDR" "  test-bun:
    needs: [push-dedupe]
    if: \${{ success() && $ELIDE_TAIL && $(or_term test-bun) }}" truth TT:test-bun
mutate_yml y-no-event-disjunct "$BUN_HDR" "  test-bun:
    needs: [push-dedupe]
    if: \${{ !cancelled() && needs.push-dedupe.outputs.elide != 'true' && $(or_term test-bun) }}" truth TT:test-bun
mutate_yml y-lost-cancelled "$BUN_HDR" "  test-bun:
    needs: [push-dedupe]
    if: \${{ (github.event_name != 'push' || needs.push-dedupe.outputs.elide != 'true') && $(or_term test-bun) }}" truth TT:test-bun
mutate_yml y-lost-need "  test-bun:
    needs: [push-dedupe, oracle-selection]" "  test-bun:
    needs: [oracle-selection]" gated G-NEEDS:test-bun
# S4 retirement (2026-11-09): the mutants below pin the POST-REMOVAL grammar — a re-introduced pr-selection job,
# needs edge, output read, variable read, aggregator `skip_re` arm or driver file is the tag that kills them. The
# oracle-lane machinery keeps its own mutants further down.
mutate_yml y-prsel-job-returns "  oracle-selection:" "  pr-selection:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    steps:
      - run: true

  oracle-selection:" prsel P-JOB-PRESENT
mutate_yml y-prsel-job-returns-dark "  oracle-selection:" "  pr-selection:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    steps:
      - run: true

  oracle-selection:" darkequiv DE-JOB-PRESENT
mutate_yml y-pr-term-returns "$BUN_HDR" "  test-bun:
    needs: [push-dedupe, oracle-selection]
    if: \${{ !cancelled() && $ELIDE_TAIL && !(needs.pr-selection.outputs.active == 'true') && $(or_term test-bun) }}" legparity L-TERM:test-bun
mutate_yml y-pr-need-returns "  test-webplat:
    needs: [push-dedupe, draft-light, oracle-selection]" "  test-webplat:
    needs: [push-dedupe, draft-light, pr-selection, oracle-selection]" gated G-PRNEEDS:test-webplat
mutate_yml y-pr-e2e-needs "  e2e:
    needs: [push-dedupe]" "  e2e:
    needs: [push-dedupe, pr-selection]" gated G-PRNEEDS:e2e
# the ungated-required-job escape: any job that needs pr-selection now waits on a retired job
mutate_yml y-prneeds-extra "  guards-ruleset:
    name: guards-ruleset" "  guards-ruleset:
    name: guards-ruleset
    needs: [pr-selection]" gated G-PRNEEDS-EXTRA:guards-ruleset
# a re-introduced aggregator tolerance arm: no skip_re line may exist post-removal
mutate_yml y-agg-skipre-returns "          oracle_tolerated=\",\"" "          skip_re='^test-bun\$'
          oracle_tolerated=\",\"" legparity L-SKIPRE
# the census of references to the retired lever's outputs: one more consumer, anywhere, is a tag
mutate_yml y-census-step-if "        if: strategy.job-index == 0
" "        if: strategy.job-index == 0 && needs.pr-selection.outputs.active != 'true'
" prcensus C-REF:test-webplat.steps
mutate_yml y-census-matrix-exclude "        shard: [\"1/2\", \"2/2\"]
" "        shard: [\"1/2\", \"2/2\"]
        exclude:
          - shard: \${{ needs.pr-selection.outputs.skip_legs }}
" prcensus C-REF:test-webplat.strategy
# the pinned-set guard itself: a non-empty PR-gated pinned set is a tag, so the empty pin is load-bearing
MUT_RUN=$((MUT_RUN + 1))
if [ -n "$(PR_GATED_PINNED="test-bun test-webplat" chk legparity "$WF" 2>/dev/null)" ]; then MUT_CAUGHT=$((MUT_CAUGHT + 1)); pass
else fail "MUTANT y-leg-pinned: a non-empty PR-gated pinned set went unnoticed by the leg-parity row"; fi
# the retired driver must stay deleted: planted back in the tree it is the L-DRIVER-PRESENT tag
MUT_RUN=$((MUT_RUN + 1))
mkdir -p "$SANDBOX/driver"
printf '# stub\n' > "$SANDBOX/driver/${DRV_STEM##*/}.sh"
if [ -n "$(DRIVER_SH="$SANDBOX/driver/${DRV_STEM##*/}.sh" chk legparity "$WF" 2>/dev/null)" ]; then MUT_CAUGHT=$((MUT_CAUGHT + 1)); pass
else fail "MUTANT y-driver-returns: a present selector driver file went unnoticed by the leg-parity row"; fi
# the switch census (structural seat, review of #10341): post-removal, ANY read of the retired variable or a
# whole-context read is a tag — none of these touches `needs.pr-selection`, so only `prcensus` can see them. One
# mutant per shape class (the whitespace and case spellings of the first census are pinned by the three y-ref-*
# mutants): the literal name, its lowercase spelling, a dynamic index, every whole-context spelling, a job-level
# and a step-level env.
BUN_RUN="      - name: Run bun-side tests
        run: bash scripts/test-all.sh bun"
vars_step_if() {  # $1 name  $2 the expression put in a step-level if on test-bun's test step  $3 expected tag prefix
  mutate_yml "$1" "$BUN_RUN" "      - name: Run bun-side tests
        if: \${{ $2 }}
        run: bash scripts/test-all.sh bun" prcensus "$3"
}
vars_step_if y-vars-step-if "vars.CI_PR_"AFFECTED" == 'on'" C-VARS:jobs.test-bun.steps.
vars_step_if y-vars-lowercase "vars.ci_pr_"affected" == 'on'" C-VARS:jobs.test-bun.steps.
vars_step_if y-vars-dynamic-index "vars[format('CI_PR_{0}','AFFECTED')] == 'on'" C-VARS:jobs.test-bun.steps.
vars_step_if y-ref-ws-dot "needs . pr-selection . outputs.active == 'true'" C-REF:test-bun.steps.
vars_step_if y-ref-ws-bracket "needs ['pr-selection'].outputs.active == 'true'" C-REF:test-bun.steps.
vars_step_if y-ref-upper "NEEDS.PR-SELECTION.outputs.active == 'true'" C-REF:test-bun.steps.
vars_step_if y-vars-toJSON-needs "!contains(toJSON(needs), 'active')" C-VARS:jobs.test-bun.steps.
vars_step_if y-vars-toJson-lower "!contains(toJson(needs), 'active')" C-VARS:jobs.test-bun.steps.
vars_step_if y-vars-toJSON-vars "toJSON(vars) != ''" C-VARS:jobs.test-bun.steps.
vars_step_if y-vars-needs-star "!contains(needs.*.result, 'failure')" C-VARS:jobs.test-bun.steps.
vars_step_if y-vars-format-needs "contains(format('{0}', needs), 'x')" C-VARS:jobs.test-bun.steps.
BUN_RUN_ENV="        run: bash scripts/test-all.sh bun
        env:
          GITHUB_TOKEN: \${{ secrets.GITHUB_TOKEN }}"
mutate_yml y-vars-step-env "$BUN_RUN_ENV" "$BUN_RUN_ENV
          SW: \${{ vars.CI_PR_"AFFECTED" }}" prcensus C-VARS:jobs.test-bun.steps.
mutate_yml y-vars-job-env "$BUN_HDR" "$BUN_HDR
    env:
      SW: \${{ vars.CI_PR_"AFFECTED" }}" prcensus C-VARS:jobs.test-bun.env.
# no workflow-level env or defaults: both reach every job (the top-level pins survived the lever's removal)
mutate_yml y-top-env "
jobs:
" "
env:
  PR_SELECTION_TEST_ALL: '1'
jobs:
" prsel P-TOPENV
mutate_yml y-top-defaults "
jobs:
" "
defaults:
  run:
    working-directory: scripts
jobs:
" prsel P-TOPDEFAULTS
# the oracle-reference census (structural seat, #12156): a step-level `if:` reading oracle-selection outputs on a
# NON-whitelisted step is a hidden skip — the job still concludes `success` while the work never ran. One on a lane
# leg's run step, one inside the aggregator (test.steps.*.if is also not on the whitelist).
mutate_yml y-orasel-step-if-leg "$BUN_RUN_ENV" "        if: needs.oracle-selection.outputs.oracle_only == 'true'
$BUN_RUN_ENV" ocensus O-REF-EXTRA
mutate_yml y-orasel-step-if-agg "      - name: Aggregate shard results" "      - name: Aggregate shard results
        if: needs.oracle-selection.outputs.oracle_only == 'true'" ocensus O-REF-EXTRA
mutate_yml y-extra-gated "    needs: detect-changes
    if: needs.detect-changes.outputs.docs == 'true'
" "    needs: detect-changes
    if: needs.detect-changes.outputs.docs == 'true' || needs.push-dedupe.outputs.elide == 'x'
" gated G-SET
mutate_yml y-agg-env "          ATTEMPT: \${{ github.run_attempt }}
        run: |
          # NAME THE MEASURED CAUSE" "          ATTEMPT: \${{ github.run_attempt }}
          ELIDE: \${{ needs.push-dedupe.outputs.elide }}
        run: |
          # NAME THE MEASURED CAUSE" agg A-DIGEST
mutate_yml y-agg-tolerate "              skipped)
                echo \"\$shard: SKIPPED — the leg did not run\" >&2" "              skipped)
                fail=0
                echo \"\$shard: SKIPPED — the leg did not run\" >&2" agg A-DIGEST
# the checker tags that only a yml mutant can reach and review found unreached (the other W-*/G-*/TT-* tags are
# reached only through the pristine-tree rows; a tag deleted from chk.py is NOT caught for those: add a row first)
mutate_yml y-no-job-coe "    continue-on-error: true
    runs-on: ubuntu-latest
    timeout-minutes: 3
    permissions:
      actions: read" "    runs-on: ubuntu-latest
    timeout-minutes: 3
    permissions:
      actions: read" wrapper W-JOBCOE
mutate_yml y-runs-on "    runs-on: ubuntu-latest
    timeout-minutes: 3
    permissions:
      actions: read" "    runs-on: macos-latest
    timeout-minutes: 3
    permissions:
      actions: read" wrapper W-RUNSON
mutate_yml y-xtrace-off-gone "          set +x
          emit() { printf '%s\\n' \"\$1\" >> \"\$GITHUB_OUTPUT\"; }
          elide=false" "          emit() { printf '%s\\n' \"\$1\" >> \"\$GITHUB_OUTPUT\"; }
          elide=false" wrapper W-NOXTRACEOFF
mutate_yml y-unclassified "
  guards-ruleset:
" "
  new-heavy-job:
    runs-on: ubuntu-latest
    steps:
      - run: true

  guards-ruleset:
" gated G-UNCLASSIFIED:new-heavy-job
mutate_yml y-dependent "
  guards-ruleset:
" "
  dep-job:
    needs: [test-bun]
    runs-on: ubuntu-latest
    steps:
      - run: true

  guards-ruleset:
" gated G-DEPENDENT:dep-job
mutate_yml y-reexport "
  guards-ruleset:
" "
  reexport-job:
    runs-on: ubuntu-latest
    outputs:
      elide: \${{ needs.push-dedupe.outputs.elide }}
    steps:
      - run: true

  guards-ruleset:
" gated G-REEXPORT:reexport-job
mutate_yml y-ungated-gone "
  guards-ruleset:
    name: guards-ruleset" "
  guards-ruleset-renamed:
    name: guards-ruleset" gated G-GONE:guards-ruleset

# the coupling row itself must go red when the aggregator tolerates a skipped leg
cp "$SANDBOX/live/agg.sh" "$SANDBOX/mut/agg-tol.sh" 2>/dev/null
MUT_RUN=$((MUT_RUN + 1))
if python3 "$SANDBOX/mut.py" "$SANDBOX/live/agg.sh" "$SANDBOX/mut/agg-tol.sh" '      echo "$shard: SKIPPED — the leg did not run" >&2' '      fail=0; continue' 2>/dev/null; then
  _save="$SANDBOX/live/agg.sh"; cp "$_save" "$SANDBOX/live/agg.orig"; cp "$SANDBOX/mut/agg-tol.sh" "$_save"
  agg_run SCRIPTS_RESULT; _rc=$?
  cp "$SANDBOX/live/agg.orig" "$_save"
  if [ "$_rc" -eq 0 ]; then MUT_CAUGHT=$((MUT_CAUGHT + 1)); pass
  else fail "MUTANT agg-tolerates-skip: a tolerant aggregator should exit 0 on a skipped leg (the coupling row would see it); got rc=$_rc"; fi
else
  fail "MUTANT agg-tolerates-skip: mutation did NOT land"
fi

# ── Mutant accounting and measured counts ────────────────────────────────────
if [ "$MUT_RUN" -eq "$MUT_CAUGHT" ]; then pass
else fail "MUTANTS: $MUT_CAUGHT of $MUT_RUN caught (every mutant must be caught)"; fi
# Floor re-pinned 2026-11-09 (S4 retirement): the pr-selection driver/lever mutation block retired with
# the lever, so the battery measures 82 mutants+controls (was 120+). All 82 are caught.
if [ "$MUT_RUN" -ge 82 ] && [ "$EQUIV_RUN" -eq 2 ] && [ "$EQUIV_OK" -eq 2 ]; then pass
else fail "MUTANT FLOOR: $MUT_RUN mutants and controls ran (floor 82), $EQUIV_OK of $EQUIV_RUN equivalent mutants confirmed (want 2 of 2)"; fi

# ── Assertion floor ──────────────────────────────────────────────────────────
# DELIBERATELY NOT ROUTED THROUGH fail(): a floor that increments the counter it guards shares a
# lifetime with the thing it is checking. This compares against a literal and exits directly.
#
# KEEP THESE TWO ASSIGNMENTS CONTIGUOUS (no comment between them or before the `if`):
# scripts/guard-vacuity-floor.test.sh binds a floor's variables by walking BACKWARD from the `if`.
_total=$((passes + fails))
_FLOOR=217
if [ "$_total" -lt "$_FLOOR" ]; then
  printf 'FAIL: assertion floor: %d assertion(s) ran, floor is %d — the harness lost coverage rather than passing it\n' \
    "$_total" "$_FLOOR" >&2
  printf 'ci-push-dedupe: %d passed, %d failed (%d assertions)\n' "$passes" "$fails" "$_total"
  exit 1
fi

printf 'ci-push-dedupe: %d passed, %d failed (%d assertions; %d mutants caught of %d; %d battery rows)\n' \
  "$passes" "$fails" "$_total" "$MUT_CAUGHT" "$MUT_RUN" "$CTRL_N"
exit $(( ${#FAILURES[@]} > 0 ))
