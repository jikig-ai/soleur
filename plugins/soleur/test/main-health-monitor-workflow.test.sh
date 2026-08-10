#!/usr/bin/env bash
# Static guards for .github/workflows/main-health-monitor.yml (#7307).
#
# WHY THIS EXISTS. That workflow is the repo's only main-branch backstop and it
# filed ZERO issues in the four months it existed, because three of its
# properties were load-bearing and pinned by nothing:
#
#   A. a job timeout is recorded `cancelled`, never `failure`
#   B. `| tee` under the default `bash -e {0}` shell (pipefail OFF) discards the
#      suite's exit code, so a red suite reports success AND the closer then
#      auto-closes human-filed trackers
#   C. the infra suites were never covered on the main path
#
# The fix's own correctness is likewise a set of relations no test could see.
# Measured during #7307's review: a sandbox battery mutated the shipped workflow
# 28 ways and 24 survived every existing gate — including `closer if: -> always()`,
# which auto-closes the tracker while main is red, i.e. defect B's consequence
# restored. Each assertion below corresponds to a mutation that used to survive.
#
# NOT covered here, deliberately: `scripts/lint-workflow-errexit-capture.py`
# cannot see this file's PIPESTATUS idiom. Its pass 2 short-circuits on
# `if not state[cmd_pos]: continue` ("errexit was already clear when the command
# ran"), and this workflow puts `set +e` BEFORE the pipeline, so it lands in that
# exempt branch. Verified during review: moving `set -e` above the read — a
# silent false-pass, strictly worse than the original bug — leaves that linter
# reporting `clean`. Assertion (7) is the only thing that catches it.
#
# ANCHORING. Every assertion runs against a WHOLE-LINE-COMMENT-STRIPPED copy.
# This file is ~50% rationale prose that necessarily quotes the very tokens being
# asserted (`!cancelled()`, `^RED `, `PIPESTATUS`), so an unstripped body-grep
# would be satisfied by the comment explaining the guard — the collision class
# documented repo-wide. Stripping is done once, at extraction, so a future
# assertion inherits the immunity instead of having to remember it.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WF="$REPO_ROOT/.github/workflows/main-health-monitor.yml"

# Allow a sandbox copy to be driven (mutation battery); default to the real file.
WF="${MHM_WORKFLOW:-$WF}"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  [ok]   $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  [FAIL] $1 -- $2" >&2; }

echo "=== main-health-monitor.yml static guards (#7307) ==="

if [[ ! -f "$WF" ]]; then
  echo "  [FAIL] workflow not found at $WF" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "  [FAIL] python3 required (this suite runs in TEST_GROUP=scripts, which has it)" >&2
  exit 1
fi

RESULT_FILE="$(mktemp -t mhm-guards.XXXXXXXX)" || exit 1
trap 'rm -f "$RESULT_FILE"' EXIT

python3 - "$WF" >"$RESULT_FILE" 2>&1 <<'PY'
import re, sys, math

wf_path = sys.argv[1]
raw = open(wf_path).read()

# Whole-line comments only. A naive strip-from-# would truncate legitimate
# content: the issue body contains `echo "## Main branch ..."` and a label colour
# `--color "B60205"`, neither of which is a comment.
stripped = "\n".join(l for l in raw.splitlines() if not re.match(r'^\s*#', l))

results = []
def ok(msg):   results.append(("ok", msg, ""))
def bad(msg, detail): results.append(("FAIL", msg, detail))

def step_if(name):
    """The `if:` of the step whose `- name: <name>` line matches, from the
    stripped body. Returns None when the step or its `if:` is absent."""
    m = re.search(r'^      - name: ' + re.escape(name) + r'\s*$', stripped, re.M)
    if not m:
        return None
    # scan forward to the next step boundary
    rest = stripped[m.end():]
    nxt = re.search(r'^      - (name|uses):', rest, re.M)
    block = rest[:nxt.start()] if nxt else rest
    mi = re.search(r'^        if:\s*(.+)$', block, re.M)
    return mi.group(1).strip() if mi else None

FILER   = "Create issue on failure"
CLOSER  = "Close issue on success"
BEAT    = "Sentry check-in (final)"

# ---- (1) the filer must not inherit the implicit success() gate -------------
f_if = step_if(FILER)
if f_if is None:
    bad("(1) filer step and its if: exist", "step or if: not found")
elif "!cancelled()" not in f_if:
    bad("(1) filer if: carries !cancelled()",
        "GitHub ANDs an implicit success() into any if: with no status function, "
        "so without this the filer is SKIPPED on every setup-step failure -- "
        "the runs where the monitor knows least. if=" + f_if)
else:
    ok("(1) filer if: carries !cancelled() (defeats the implicit success())")

# ---- (2) filer fires on NOT-success, disjunctively over both steps ---------
if f_if:
    has_or   = "||" in f_if
    tests_ne = re.search(r"steps\.tests\.outcome\s*!=\s*'success'", f_if)
    infra_ne = re.search(r"steps\.infra\.outcome\s*!=\s*'success'", f_if)
    if has_or and tests_ne and infra_ne:
        ok("(2) filer fires on tests != success OR infra != success")
    else:
        bad("(2) filer fires on tests != success OR infra != success",
            "a job/step timeout is `cancelled` and a skipped step is `skipped`; "
            "`== 'failure'` misses both, and && would need BOTH to fail. if=" + f_if)

# ---- (3) closer is strict AND on success, over both steps ------------------
c_if = step_if(CLOSER)
if c_if is None:
    bad("(3) closer step and its if: exist", "step or if: not found")
else:
    has_and  = "&&" in c_if
    tests_eq = re.search(r"steps\.tests\.outcome\s*==\s*'success'", c_if)
    infra_eq = re.search(r"steps\.infra\.outcome\s*==\s*'success'", c_if)
    if has_and and tests_eq and infra_eq:
        ok("(3) closer requires tests == success AND infra == success")
    else:
        bad("(3) closer requires tests == success AND infra == success",
            "a loosened closer auto-closes the tracker while main is red -- "
            "defect B's consequence. if=" + c_if)
    if "always()" in c_if:
        bad("(3b) closer must NOT be always()",
            "always() closes the tracker regardless of the suite verdict")
    else:
        ok("(3b) closer is not always()")

# ---- (4) dry_run gates exactly the side-effecting steps --------------------
gated = [n for n in (FILER, CLOSER, BEAT)
         if (step_if(n) or "") and "!inputs.dry_run" in (step_if(n) or "")]
if len(gated) == 3:
    ok("(4) !inputs.dry_run gates all three side-effecting steps")
else:
    bad("(4) !inputs.dry_run gates all three side-effecting steps",
        "gated=" + repr(gated) + " -- a measurement dispatch would file, close, "
        "or post a check-in that masks a genuinely missed scheduled run")

# The boolean spelling is load-bearing: github.event.inputs.* is ALWAYS a string,
# so !github.event.inputs.dry_run is !'false' == false and would permanently
# disable all three gates -- defect A arriving through a rename.
if "github.event.inputs.dry_run" in stripped:
    bad("(4b) dry_run read via the typed `inputs` context",
        "github.event.inputs.* is a string; !'false' is false, silently disabling every gate")
else:
    ok("(4b) dry_run read via the typed `inputs` context, not github.event.inputs")

# ---- (5) steps.tests / steps.infra referenced in lockstep -----------------
n_tests = len(re.findall(r'steps\.tests\.outcome', stripped))
n_infra = len(re.findall(r'steps\.infra\.outcome', stripped))
has_infra_step = re.search(r'^        id: infra\s*$', stripped, re.M) is not None
if not has_infra_step:
    if n_infra == 0:
        ok("(5) no id: infra step and no steps.infra references (both zero)")
    else:
        bad("(5) steps.infra referenced with no id: infra step",
            "a missing step context is a null dereference: GitHub casts null to 0, "
            "so == 'success' is always false and != 'success' always true")
elif n_tests == n_infra and n_tests > 0:
    ok(f"(5) steps.tests and steps.infra referenced in lockstep ({n_tests} each)")
else:
    bad("(5) steps.tests and steps.infra referenced in lockstep",
        f"tests={n_tests} infra={n_infra} -- a partial reference set means one step's "
        "verdict is silently dropped from the filer, closer, summary or heartbeat")

# ---- (6) ceiling arithmetic ------------------------------------------------
job_m = re.search(r'^    timeout-minutes:\s*(\d+)', stripped, re.M)
step_ms = re.findall(r'^        timeout-minutes:\s*(\d+)', stripped, re.M)
if not job_m or len(step_ms) < 2:
    bad("(6) job and both step ceilings are declared",
        f"job={bool(job_m)} steps={step_ms}")
else:
    job = int(job_m.group(1)); steps_sum = sum(int(x) for x in step_ms)
    if job >= steps_sum + 15:
        ok(f"(6) job ceiling dominates the SUM of step ceilings ({job} >= {steps_sum}+15)")
    else:
        bad("(6) job ceiling dominates the SUM of step ceilings",
            f"job={job} sum={steps_sum}. With two timed steps a max-based job ceiling "
            "lets the job token trip mid-second-step, and a JOB cancel skips every "
            "remaining step regardless of if: -- defect A, restored with the fix in place")
    # 360 min is both the 6h inter-fire gap and GitHub's hosted-runner job cap.
    if job < 360:
        ok(f"(6b) job ceiling ({job}) is under the 360-min inter-fire gap")
    else:
        bad("(6b) job ceiling is under the 360-min inter-fire gap", f"job={job}")

# ---- (7) PIPESTATUS adjacency (the repo linter cannot see this) ------------
# `set -e` is a builtin, i.e. a pipeline, so bash RESETS PIPESTATUS after it.
# Anything between the pipeline and the read makes rc always 0 -- a silent false
# pass, strictly worse than the original bug.
run_lines = [l.rstrip() for l in stripped.splitlines()]
pipe_idx = [i for i, l in enumerate(run_lines)
            if re.search(r'bash scripts/test-all\.sh .*\|\s*tee', l)]
if not pipe_idx:
    bad("(7) suite invocations pipe into tee", "no `test-all.sh ... | tee` found")
else:
    bad_sites = []
    for i in pipe_idx:
        nxt = run_lines[i + 1].strip() if i + 1 < len(run_lines) else ""
        if not re.match(r'^rc=\$\{PIPESTATUS\[0\]\}$', nxt):
            bad_sites.append((i + 1, nxt))
    if bad_sites:
        bad("(7) ${PIPESTATUS[0]} is read on the line IMMEDIATELY after the pipeline",
            f"offending={bad_sites} -- anything in between (notably `set -e`) resets "
            "PIPESTATUS and makes rc always 0")
    else:
        ok(f"(7) ${{PIPESTATUS[0]}} read immediately after each pipeline ({len(pipe_idx)} sites)")

    # and the captured rc must actually be surfaced to the engine
    if stripped.count('exit "$rc"') >= len(pipe_idx):
        ok("(7b) each captured rc is re-raised with exit \"$rc\"")
    else:
        bad("(7b) each captured rc is re-raised with exit \"$rc\"",
            "without it the step's status is `set -e`'s (0) and the whole fix is a no-op")

# ---- (8) failure marker must anchor on ^RED , not only [FAIL] -------------
# run-registered-suites.sh's own header: "a failing suite prints `RED <path>`,
# not `FAIL`. A `grep FAIL` over this runner's log returns zero hits on a failing
# run and reads as clean -- measured 2026-08-04 (#7220)."
if re.search(r"grep -E '\^RED \|\^\\\[FAIL\\\]'", stripped):
    ok("(8) failure marker matches ^RED as well as ^[FAIL]")
else:
    bad("(8) failure marker matches ^RED as well as ^[FAIL]",
        "the infra runner never emits [FAIL]; matching it alone re-labels a real "
        "infra failure as 'Run did not complete' and names a timeout that did not happen")

# ---- (9) closer may only retire trackers this monitor filed ---------------
sentinel = "<!-- soleur:main-health-monitor -->"
if stripped.count(sentinel) >= 2:
    ok("(9) filer writes a sentinel and the closer consults it")
else:
    bad("(9) filer writes a sentinel and the closer consults it",
        f"occurrences={stripped.count(sentinel)} -- selecting on the label alone lets "
        "this job close a HUMAN-filed tracker about a failure class it never ran "
        "(#5393 Playwright-401 and #5372 dev-Supabase are real examples)")

# ---- (10) no pipeline whose status is discarded in setup steps ------------
# defect B's shape: `cmd | tail` under bash -e (pipefail OFF) always exits 0.
offenders = [l.strip() for l in run_lines
             if re.search(r'\|\s*(tail|head)\b', l)
             and 'PIPESTATUS' not in l
             and 'grep -E' not in l]
if offenders:
    bad("(10) no setup pipeline silently discards its producer's exit status",
        f"offenders={offenders} -- this is defect B's exact shape")
else:
    ok("(10) no setup pipeline silently discards its producer's exit status")

# ---- (12) JOBS=1 on BOTH suite steps ---------------------------------------
# Added after this guard FAILED to catch its own regression: the review moved
# JOBS off workflow scope (node-gyp reads it as `make -j`) and did not re-add it
# to the steps, so run 31367748528 ran the infra runner at -P 4, hit the harness
# flake (#7376) and filed a spurious issue. The step-scoped form is what covers
# BOTH invocations -- the standalone runner and the nested one inside the tests
# step -- so assert it on each, not merely somewhere in the file.
step_env_blocks = re.findall(
    r'^        id: (tests|infra)\n(?:.*\n)*?^        env:\n((?:^          .*\n)+)',
    stripped, re.M)
jobs_ok = {sid: bool(re.search(r'^          JOBS:\s*1\s*$', env, re.M))
           for sid, env in step_env_blocks}
if set(jobs_ok) == {"tests", "infra"} and all(jobs_ok.values()):
    ok("(12) JOBS: 1 is set on both the tests and infra step env blocks")
else:
    bad("(12) JOBS: 1 is set on both the tests and infra step env blocks",
        f"found={jobs_ok} -- without it run-registered-suites.sh defaults to "
        "-P min(nproc,6) = -P 4 on a hosted runner, which is the configuration "
        "measured flaky in 3 of 7 executions (#7376) and files a spurious P1")

# ---- (11) the machine-readable verdict annotation --------------------------
# GitHub exposes no REST field for job summaries; annotations ARE retrievable via
# gh api .../check-runs/<id>/annotations. Without this the verdict is unreadable
# by any agent on the green and dry-run paths.
if "::notice title=main-health-outcomes::" in stripped:
    ok("(11) verdict is mirrored to an API-retrievable ::notice:: annotation")
else:
    bad("(11) verdict is mirrored to an API-retrievable ::notice:: annotation",
        "the $GITHUB_STEP_SUMMARY write is human-only -- no REST field exposes it")

for status, msg, detail in results:
    print(f"{status}\t{msg}\t{detail}")
PY

rc=$?
if [[ $rc -ne 0 ]]; then
  echo "  [FAIL] guard script did not run cleanly (rc=$rc)" >&2
  sed -n '1,40p' "$RESULT_FILE" >&2
  exit 1
fi

while IFS=$'\t' read -r status msg detail; do
  [[ -n "${status:-}" ]] || continue
  if [[ "$status" == "ok" ]]; then pass "$msg"; else fail "$msg" "$detail"; fi
done < "$RESULT_FILE"

# POSITIVE CONTROL. The floor below counts PASS+FAIL, so it catches a dispatch
# layer that stops emitting entirely -- but NOT a `fail()` neutered to a no-op,
# which would keep the count while making the suite structurally incapable of
# reddening. Exercise both counters and prove each moved.
_p0=$PASS; _f0=$FAIL
pass "positive-control probe" >/dev/null
fail "positive-control probe" "deliberate" 2>/dev/null
if [[ "$PASS" -eq $((_p0 + 1)) && "$FAIL" -eq $((_f0 + 1)) ]]; then
  PASS=$((_p0 + 1)); FAIL=$_f0   # keep the pass, retract the deliberate fail
  echo "  [ok]   positive control: pass() and fail() both mutate their counters"
else
  echo "  [FAIL] positive control: pass()/fail() do not mutate their counters" >&2
  echo "         PASS $_p0->$PASS  FAIL $_f0->$FAIL" >&2
  exit 1
fi

# ANTI-VACUITY FLOOR. Every assertion above is dispatched through pass()/fail(),
# so deleting the python block, or having it emit nothing, would otherwise exit 0
# having asserted nothing -- the exact "a check that cannot report is
# indistinguishable from one that passed" class. A FLOOR, not equality: a new
# assertion must not require editing this number.
MIN_ASSERTIONS=14
TOTAL=$((PASS + FAIL))
if [[ "$TOTAL" -lt "$MIN_ASSERTIONS" ]]; then
  echo "  [FAIL] anti-vacuity: only $TOTAL assertion(s) ran, expected >= $MIN_ASSERTIONS" >&2
  FAIL=$((FAIL + 1))
else
  pass "anti-vacuity: $TOTAL assertions ran (floor $MIN_ASSERTIONS)"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
