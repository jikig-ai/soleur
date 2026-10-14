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
# SC2319: the behavioural rows pass `$([[ condition ]]; echo $?)` to row() ON PURPOSE -- the status of the
# CONDITION is the value being asserted, and nothing sits between the test and the echo to overwrite it.
# shellcheck disable=SC2319
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WF="$REPO_ROOT/.github/workflows/main-health-monitor.yml"

# Allow a sandbox copy to be driven (mutation battery); default to the real file.
WF="${MHM_WORKFLOW:-$WF}"
# Same override for the Sentry monitor's Terraform (Guard 2, #8112), so a battery can mutate a COPY
# of it as well and not only the workflow.
SENTRY_TF="${MHM_SENTRY_TF:-$REPO_ROOT/apps/web-platform/infra/sentry/cron-monitors.tf}"
RUNNER_SH="$REPO_ROOT/scripts/test-all.sh"

PASS=0
FAIL=0
# CASES counts assertions DISPATCHED. It is incremented at the CALL SITE and
# never inside pass()/fail(), and that placement is the whole substance of the
# accounting-conservation check further down: a counter that moves inside both
# verdict helpers moves WITH the verdict, so stubbing fail() to a no-op drops the
# row and its count together and PASS+FAIL == CASES still holds under the exact
# fault it exists to catch.
#
# Never increment inside `$( )` — a subshell discards it. `$((` is arithmetic and
# is fine; `$(` is command substitution and is not.
CASES=0
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

python3 - "$WF" "$RUNNER_SH" "$SENTRY_TF" >"$RESULT_FILE" 2>&1 <<'PY'
import re, sys, math

wf_path = sys.argv[1]
runner_path = sys.argv[2]
sentry_tf_path = sys.argv[3]
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
    # The derivation rule's floors (tests_step = max(30, ...), infra_step = max(10, ...)): a step
    # ceiling dropped far below the measured need reproduces #8112's budget exhaustion while the
    # SUM check above still passes (a 30-minute tests step under a 185-minute job).
    if int(step_ms[0]) >= 30 and int(step_ms[1]) >= 10:
        ok(f"(6c) step ceilings meet the derivation floors (tests {step_ms[0]} >= 30, infra {step_ms[1]} >= 10)")
    else:
        bad("(6c) step ceilings meet the derivation floors (tests >= 30, infra >= 10)",
            f"steps={step_ms} -- a tests step ceiling this low is the original #8112 failure")
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
# AMENDED 2026-08-11 (#7376): the anchor was widened to include `^UNACCOUNTED `, so this now
# asserts the two REQUIRED alternates are present rather than pinning the exact spelling.
# An exact-string pin would have to be edited for every legitimate widening, and editing it is
# indistinguishable from removing a required alternate. `^UNACCOUNTED ` is required for the
# same reason `^RED ` is: a suite whose wrapper is killed emits NEITHER PASS nor RED, so
# without it HAS_FAIL_MARKER stays 0 and the monitor titles the issue "did not complete ...
# usually a timeout" -- a cause it never measured, on the exact failure the runner's accounting
# assertion exists to catch.
# `grep [^']*-E` rather than `grep -E`: the alternates are what this asserts (see the
# comment above), so the EXTRACTOR must not pin flag adjacency. #7424 added `-m 20`, which
# left the exact-adjacency form matching nothing -- and `_alts` then came back EMPTY, which
# reports as "all three alternates missing" rather than as "the extraction broke". A check
# whose failure mode is indistinguishable from the defect it hunts is the class this file
# exists to keep out of the monitor.
#
# AMENDED for #8112: the display capture is now TWO greps (`red_hits` for `^RED |^UNACCOUNTED `,
# `fail_hits` for `^\[FAIL\]`) so early control `[FAIL]` lines cannot crowd a later `RED` out of a
# single 20-line cap. This still asserts the union of the display greps carries the three alternates;
# WHICH of them is a verdict input is (8h)'s question, and the behavioural rows below answer it.
_anchors = re.findall(r"(?:red_hits|fail_hits)=\$\(grep [^']*-E '([^']+)'", stripped)
_anchor = bool(_anchors)
_alts = "|".join(_anchors)
_required = ["^RED ", "^UNACCOUNTED ", "^\\[FAIL\\]"]
_missing = [a for a in _required if a not in _alts]
if _anchor and not _missing:
    ok("(8) failure-marker anchor carries ^RED , ^UNACCOUNTED and ^[FAIL]")
else:
    bad("(8) failure-marker anchor carries ^RED , ^UNACCOUNTED and ^[FAIL]",
        f"missing={_missing or '<anchor not found>'} in {_alts!r} -- the infra runner never "
        "emits [FAIL] itself; and without ^UNACCOUNTED a vanished suite sets no marker at all, "
        "so the monitor names a timeout that did not happen")

# ---- (8b) [KILLED] is a SEPARATE grep whose hits reach SUMMARY ------------
# scripts/test-all.sh now carries a THIRD result class. A suite terminated by a signal
# renders `[KILLED] <label> (exit=<rc>, signal-shaped 128+<n> = SIG<NAME>, <ms>ms)` and is
# NOT counted as a failure, because the runner did not measure what terminated it.
#
# Folding that marker into (8)'s grep breaks two things at once: it would set
# HAS_FAIL_MARKER, re-labelling an UNRESOLVED run "CI: main branch tests failing" -- the
# exact conflation the runner change removes -- and it would break (8) itself, whose regex
# ends on the literal `^\[FAIL\]'`. So the marker needs its own grep, its own variable, and
# its own classification arm.
KILLED_LITERAL = r"\^\\\[KILLED\\\]"        # matches the source text  ^\[KILLED\]

m_killed = re.search(
    r'^[ \t]*(?P<var>[A-Za-z_][A-Za-z0-9_]*)=\$\(grep\b.*' + KILLED_LITERAL,
    stripped, re.M)
killed_var = m_killed.group("var") if m_killed else None

if killed_var is None:
    bad("(8b) a separate grep matches the runner's ^[KILLED] marker",
        "without it a signal-terminated suite reaches the operator as either "
        "'main branch tests failing' (if folded into the ^RED grep) or as a body whose "
        "only content is tail -30 -- naming no suite at all")
elif killed_var in ("hits", "red_hits", "fail_hits", "gone_hits", "failed_breakdown", "short_fail"):
    bad("(8b) the ^[KILLED] grep uses a variable distinct from the failure greps'",
        f"var={killed_var!r} -- sharing a failure-verdict variable sets HAS_FAIL_MARKER, which "
        "re-labels an unresolved run as a failing one")
else:
    ok(f"(8b) ^[KILLED] is matched by its own grep into `{killed_var}` (not `hits`)")

    # THE APPEND IS THE WHOLE POINT. `hits` feeds BOTH HAS_FAIL_MARKER and SUMMARY; a
    # killed-only run whose hits never reach SUMMARY yields a body containing nothing but
    # `tail -30`, and the runner emits a contention epilogue plus up to four multi-line
    # infra NOTE blocks after its summary -- so a [KILLED] line 200 suites earlier is
    # outside that window. The operator gets an issue titled "terminated" naming no suite.
    if re.search(r'SUMMARY="\$\{SUMMARY\}\$\{' + re.escape(killed_var) + r'\}"', stripped):
        ok(f"(8b-i) the ^[KILLED] hits are appended to SUMMARY via ${{{killed_var}}}")
    else:
        bad(f"(8b-i) the ^[KILLED] hits are appended to SUMMARY via ${{{killed_var}}}",
            "without the append the issue body is `tail -30` only, and the [KILLED] line "
            "sits outside that window -- an issue titled 'terminated' that names no suite")

    # SHAPE-anchored, not prefix-anchored: the capture file is arbitrary suite stdout, so a
    # bare `^\[KILLED\]` is forgeable by any suite that prints it.
    if re.search(KILLED_LITERAL + r' \.\+ \\\(exit=', stripped):
        ok("(8b-ii) the ^[KILLED] grep is shape-anchored, not prefix-anchored")
    else:
        bad("(8b-ii) the ^[KILLED] grep is shape-anchored, not prefix-anchored",
            "a bare ^\\[KILLED\\] prefix is forgeable by any suite that prints the token "
            "in its own stdout (cq-assert-anchor-not-bare-token)")

    # LENGTH bound as well as line bound. One 100 KB line pushes the body past GitHub's
    # 65536-character issue limit, `gh issue create` fails, and the monitor files NOTHING
    # on a broken main -- an alarm that dies exactly when it is needed.
    killed_line = stripped[m_killed.start():].split("\n")[0]
    has_line_bound = bool(re.search(r'-m\s*\d+', killed_line) or re.search(r'head\s+-\d+', killed_line))
    has_len_bound = "cut -c1-" in killed_line
    if has_line_bound and has_len_bound:
        ok("(8b-iii) the ^[KILLED] capture is bounded in both line count and line length")
    else:
        bad("(8b-iii) the ^[KILLED] capture is bounded in both line count and line length",
            f"line_bound={bool(has_line_bound)} len_bound={bool(has_len_bound)} -- an "
            "unbounded excerpt pushes the body past GitHub's 65536-char limit and the "
            "filer creates no issue at all")

# ---- (8c) the killed grep runs BEFORE the redactor -------------------------
# The [KILLED] line's own fields carry no secret, but this change alters WHAT ENTERS the
# body (hits -> hits u killed_hits u tail), and the ordering that keeps the new content
# redacted was asserted nowhere. A later edit appending after REDACTED= would ship raw.
if m_killed:
    red_m = re.search(r'^[ \t]*REDACTED=\$\(', stripped, re.M)
    if not red_m:
        bad("(8c) the killed grep precedes the redaction pass", "no REDACTED= assignment found")
    elif m_killed.start() < red_m.start():
        ok("(8c) the ^[KILLED] hits are appended BEFORE the redaction pass")
    else:
        bad("(8c) the ^[KILLED] hits are appended BEFORE the redaction pass",
            "this repo is PUBLIC and `tee` captures raw stdout before the runner's masking "
            "pass; content appended after REDACTED= is published unredacted")

# ---- (8d) a FOURTH arm, ordered after the failure arm ----------------------
fail_arm   = re.search(r'^[ \t]*elif \[\[ "\$HAS_FAIL_MARKER" == "1" \]\]; then', stripped, re.M)
killed_arm = re.search(r'^[ \t]*elif \[\[ "\$HAS_KILLED_MARKER" == "1" \]\]; then', stripped, re.M)
if not killed_arm:
    bad("(8d) a fourth classification arm keys on HAS_KILLED_MARKER",
        "without it a terminated suite is reported under 'Run did not complete', a heading "
        "whose lede names a cause the job never measured")
elif not fail_arm or fail_arm.start() > killed_arm.start():
    bad("(8d) the killed arm is ordered AFTER the failure arm",
        "failure must dominate: a run with both a real [FAIL] and a [KILLED] is a failing "
        "run, and calling it merely 'terminated' would hide the failure")
else:
    ok("(8d) a fourth HAS_KILLED_MARKER arm exists, ordered after the failure arm")

if re.search(r'^[ \t]*HAS_KILLED_MARKER=0[ \t]*$', stripped, re.M):
    ok("(8d-i) HAS_KILLED_MARKER is initialised, like HAS_FAIL_MARKER")
else:
    bad("(8d-i) HAS_KILLED_MARKER is initialised, like HAS_FAIL_MARKER",
        "under `set -u` an unset flag aborts the step at the arm chain; without `set -u` it "
        "is the empty string and the arm can never be selected")

# ---- (8e) no LEDE names a cause the job did not measure --------------------
# The pre-existing third arm said "This is usually a step or job timeout". The job measures
# a step OUTCOME, never a reason; `usually` is not in lint-diagnosis-claims.sh's CLAIM
# regex, which is why that line survived the ADR-166 gate. It is still a miss.
lede_lines = re.findall(r'^[ \t]*LEDE=.*$', stripped, re.M)
if not lede_lines:
    bad("(8e) LEDE assignments exist", "none found")
else:
    timeouty = [l.strip()[:120] for l in lede_lines if "timeout" in l.lower()]
    if timeouty:
        bad("(8e) no LEDE names a timeout the job did not measure",
            f"offenders={timeouty} -- a step outcome of `cancelled` is what was MEASURED; "
            "the reason for it was not, and naming one sends the operator after a phantom")
    else:
        ok(f"(8e) no LEDE names a timeout the job did not measure ({len(lede_lines)} arms)")

    disclaimed = [l for l in lede_lines if "did not measure what terminated" in l]
    if disclaimed:
        ok("(8e-i) the killed arm's LEDE states the run is unresolved, not a verdict on main")
    else:
        bad("(8e-i) the killed arm's LEDE states the run is unresolved, not a verdict on main",
            "an issue that reads as 'main is broken' over a run that measured nothing is the "
            "misattribution this arm exists to prevent")

# ---- (8f) `Actions required` is derived per arm, not hardcoded -------------
# Left hardcoded, the operator gets an issue titled "...was terminated before it could
# report", a lede that says "this issue is not a statement that main is broken", and then
# three numbered instructions to find the bad commit and revert it -- the only actionable
# text on the page, and it is wrong for this arm.
if re.search(r'echo "1\. Identify the commit that introduced the failure"', stripped):
    bad("(8f) the Actions block is derived per arm, not hardcoded across all of them",
        "the revert instructions are still emitted literally, so the killed arm tells a "
        "non-technical operator to revert a commit on a run that reported no failure")
elif not re.search(r'printf .%s\\n. "\$\{ACTIONS\[@\]\}"', stripped):
    bad("(8f) the Actions block renders the per-arm ACTIONS array",
        "no `printf '%s\\n' \"${ACTIONS[@]}\"` render found in the issue body")
else:
    ok("(8f) the Actions block renders a per-arm ACTIONS array")

if killed_arm:
    tail_after = stripped[killed_arm.end():]
    arm_end = re.search(r'^[ \t]*(else|fi)[ \t]*$', tail_after, re.M)
    killed_block = tail_after[:arm_end.start()] if arm_end else tail_after
    has_rerun  = "gh workflow run main-health-monitor.yml" in killed_block
    has_revert = "revert the breaking change" in killed_block
    if has_rerun and not has_revert:
        ok("(8f-i) the killed arm's actions name a re-run and prescribe no revert")
    else:
        bad("(8f-i) the killed arm's actions name a re-run and prescribe no revert",
            f"rerun={has_rerun} revert={has_revert} -- the arm's own lede says no suite "
            "reported a failure, so a revert instruction contradicts the issue it is on")

# ---- (8g) the comment path emits the arm's LEDE ---------------------------
# Runs 2, 3, 4 ... of a flapping killed suite each append "still not passing" under a fixed
# sentence, an escalating claim that main is broken produced by a runner that measured
# nothing. The arm's LEDE is the one sentence that must survive into the comment.
cm = re.search(r'Main branch health check still not passing(?:.*\n)*?.*issue-comment\.md', stripped)
if not cm:
    bad("(8g) the existing-tracker comment path is present", "comment block not found")
elif '${LEDE}' in cm.group(0):
    ok("(8g) the existing-tracker comment emits the arm's LEDE")
else:
    bad("(8g) the existing-tracker comment emits the arm's LEDE",
        "without it every follow-up comment on a flapping killed suite reads as a stronger "
        "claim that main is broken, from a runner that measured nothing")

# ---- (8h) a bare `[FAIL]` is a DISPLAY line, never a verdict input (#8112) --
# Seven `[FAIL]` lines in #8112's body were self-labelled EXPECTED positive controls printed by
# suites that exercise their own fail() helper, yet they selected the "tests failing" arm while the
# runner's own breakdown said `0 failed`. The verdict is the runner's: a `^RED `/`^UNACCOUNTED `
# line, or a printed breakdown with at least one failed suite. Asserted structurally here (what
# feeds HAS_FAIL_MARKER) and behaviourally below (what the arms actually select).
_verdict = re.search(r'^[ \t]*if \[\[ (?P<cond>[^\n]*) \]\]; then\n[ \t]*HAS_FAIL_MARKER=1', stripped, re.M)
_vcond = _verdict.group("cond") if _verdict else ""
_bd = re.search(r"failed_breakdown=\$\(grep [^']*-E '([^']+)'", stripped)
_bd_re = _bd.group(1) if _bd else ""
_vproblems = []
if not _verdict:
    _vproblems.append("no `if [[ ... ]]; then HAS_FAIL_MARKER=1` verdict statement found")
else:
    if "red_hits" not in _vcond:
        _vproblems.append("verdict does not read the RED/UNACCOUNTED capture")
    if "failed_breakdown" not in _vcond:
        _vproblems.append("verdict does not read the runner's failed-suite breakdown")
    if "fail_hits" in _vcond:
        _vproblems.append("verdict reads the bare [FAIL] capture")
if "^RED " not in "".join(re.findall(r"red_hits=\$\(grep [^']*-E '([^']+)'", stripped)) or \
   "^UNACCOUNTED " not in "".join(re.findall(r"red_hits=\$\(grep [^']*-E '([^']+)'", stripped)):
    _vproblems.append("red_hits grep lacks ^RED / ^UNACCOUNTED")
if "[1-9][0-9]* failed" not in _bd_re:
    _vproblems.append("breakdown regex does not require a NON-ZERO failed count ([1-9][0-9]* failed)")
if _vproblems:
    bad("(8h) the verdict reads RED/UNACCOUNTED and a failing breakdown, never a bare [FAIL]",
        "; ".join(_vproblems))
else:
    ok("(8h) the verdict reads RED/UNACCOUNTED and a failing breakdown, never a bare [FAIL]")

# The breakdown shape is the RUNNER's. Derive a sample line from the `=== $suites suites:` echo in
# scripts/test-all.sh instead of typing one, so a runner-side rename reds this suite rather than
# leaving the workflow matching a line the runner no longer prints.
_echo = None
for _l in open(runner_path).read().splitlines():
    if re.match(r'^\s*echo "=== \$suites suites: ', _l):
        _echo = _l.strip()
        break
if _echo is None or not _bd_re:
    bad("(8h-i) the breakdown regex matches the line the runner prints",
        f"runner echo found={_echo is not None} workflow regex found={bool(_bd_re)}")
else:
    def _sample(failed, killed):
        t = _echo[len('echo "'):-1]
        t = t.replace("$failed", str(failed)).replace("$killed", str(killed))
        t = re.sub(r"\$\(\(.*?\)\)", "7", t)
        t = re.sub(r"\$\{[A-Za-z_]+\}", "", t)
        t = re.sub(r"\$[A-Za-z_]+", "9", t)
        return t
    try:
        _rx = re.compile(_bd_re)
        _m_fail = bool(_rx.search(_sample(2, 0)))
        _m_zero = bool(_rx.search(_sample(0, 0)))
        _m_kill = bool(_rx.search(_sample(0, 3)))
    except re.error as e:
        _m_fail = _m_zero = _m_kill = None
        bad("(8h-i) the breakdown regex matches the line the runner prints", f"regex error: {e}")
    if _m_fail is not None:
        if _m_fail and not _m_zero and not _m_kill:
            ok("(8h-i) the breakdown regex matches the runner's failing line and rejects 0-failed and killed-only")
        else:
            bad("(8h-i) the breakdown regex matches the runner's failing line and rejects 0-failed and killed-only",
                f"failed=2 -> {_m_fail}; failed=0 -> {_m_zero}; killed-only -> {_m_kill}; "
                f"sample={_sample(2, 0)!r}")

# ---- (8i) the unfiltered raw tail append is gone (#8112) -------------------
# `SUMMARY="${SUMMARY}$(tail -30 "$file")"` re-added the raw last 30 lines after the filtered
# append, which duplicated the tail in the body AND defeated the `SOLEUR| ` filter on a PUBLIC
# issue. The behavioural harness evaluated only the filtered expression, so nothing guarded it.
_raw_tail = re.findall(r'\$\(tail -\d+ "\$file"\)', stripped)
if _raw_tail:
    bad("(8i) no unfiltered `tail` of the capture reaches the public body",
        f"found {len(_raw_tail)} raw tail append(s); the `grep -v '^SOLEUR| '` filter is bypassed")
else:
    ok("(8i) no unfiltered `tail` of the capture reaches the public body")

# ---- (8k) each step's elapsed seconds reach the annotation (#8112) ---------
# A step the runner kills reports outcome=failure and carries no duration; recording each step's
# own elapsed seconds is what makes the NEXT ceiling derivation read uncensored figures from
# ordinary runs. The WIRING is the property: producer (the step writes elapsed_s) -> output name
# -> env mapping of the RIGHT step's output in BOTH consumers -> numeric guard per variable.
# The behavioural rows inject the env value directly, so they cannot see any of the first three.
def _step_block(name):
    # `stripped` is a "\n".join — it never ends in a newline, so `(?:.*\n)*?`
    # cannot consume the file's LAST line and the `\Z` arm of the lookahead
    # never fires: asking for the LAST step (Sentry check-in) returned "".
    # Search the newline-completed text so the last step is extractable too
    # (#9082's MWb row caught this on its first run).
    m = re.search(r'^      - name: ' + re.escape(name) + r'\s*$(?P<b>(?:.*\n)*?)(?=^      - (?:name|uses):|\Z)',
                  stripped + "\n", re.M)
    return m.group("b") if m else ""
_kproblems = []
for _sid, _sname in (("tests", "Run test suite"), ("infra", "Run infra suites")):
    _sb = _step_block(_sname)
    _w = _sb.find('echo "elapsed_s=${elapsed}" >> "$GITHUB_OUTPUT"')
    _x = _sb.find('exit "$rc"')
    if _w < 0:
        _kproblems.append(f"step {_sid!r} never writes elapsed_s to $GITHUB_OUTPUT")
    elif _x < 0 or _w > _x:
        _kproblems.append(f"step {_sid!r} writes elapsed_s AFTER `exit \"$rc\"` (never reached)")
    if "t0=$SECONDS" not in _sb:
        _kproblems.append(f"step {_sid!r} never starts its timer (t0=$SECONDS)")
_rb = _step_block("Record step outcomes")
_fb = _step_block("Create issue on failure")
for _bname, _blk in (("Record step outcomes", _rb), ("Create issue on failure", _fb)):
    for _var, _sid in (("TESTS_ELAPSED_S", "tests"), ("INFRA_ELAPSED_S", "infra")):
        _line = f"{_var}: ${{{{ steps.{_sid}.outputs.elapsed_s }}}}"
        if _line not in _blk:
            _kproblems.append(f"{_bname!r} lacks the env mapping `{_line}`")
    if _blk.count("^[0-9]+$") < 2:
        _kproblems.append(f"{_bname!r} numeric-guards fewer than both elapsed values (^[0-9]+$ x{_blk.count('^[0-9]+$')})")
    if re.search(r'\$\{\{ steps\.(tests|infra)\.outputs[^}]*\}\}', re.sub(r'^\s+[A-Z_]+: \$\{\{ steps\.(tests|infra)\.outputs\.elapsed_s \}\}\s*$', '', _blk, flags=re.M)):
        _kproblems.append(f"{_bname!r} uses a step output outside its env: mapping")
for _tok in ("tests_elapsed_s=", "infra_elapsed_s="):
    if _tok not in _rb:
        _kproblems.append(f"{_tok} absent from the Record step outcomes step")
_notice = re.search(r'::notice title=main-health-outcomes::[^\n]*', _rb)
if not _notice or "${T_EL}" not in _notice.group(0) or "${I_EL}" not in _notice.group(0):
    _kproblems.append("the ::notice:: line does not carry the ${T_EL}/${I_EL} elapsed figures")
if _kproblems:
    bad("(8k) elapsed seconds are produced, mapped to the right step output and numeric-guarded in both consumers",
        "; ".join(_kproblems))
else:
    ok("(8k) elapsed seconds are produced, mapped to the right step output and numeric-guarded in both consumers")

# ---- (G2) Guard 2: the Sentry cron monitor's envelope tracks the job ceiling (#8112) --------
# The monitor sends ONE terminal check-in, so max_runtime_minutes is decorative and the margin
# must cover the WHOLE run. Both are coupled to the workflow's job-level timeout-minutes and
# nothing pinned the relation: the TF comments said 65 while the workflow said 75.
_tf = open(sentry_tf_path).read()
_tf_s = "\n".join(l for l in _tf.splitlines() if not re.match(r'^\s*#', l))
_blocks = re.findall(r'^resource "sentry_cron_monitor" "[^"]+" \{\n(.*?)^\}', _tf_s, re.M | re.S)
_mine = [b for b in _blocks if re.search(r'^\s*name\s*=\s*"main-health-monitor"\s*$', b, re.M)]
if len(_mine) != 1:
    bad("(G2) exactly one sentry_cron_monitor block is named main-health-monitor",
        f"found {len(_mine)} of {len(_blocks)} sentry_cron_monitor block(s) -- a missing block must "
        "be a RED, not a skip, or the parity guard passes over zero blocks")
elif not job_m:
    bad("(G2) the workflow's job-level timeout-minutes is readable", "no job-level timeout-minutes")
else:
    _mr = re.search(r'^\s*max_runtime_minutes\s*=\s*(\d+)\s*$', _mine[0], re.M)
    _cm = re.search(r'^\s*checkin_margin_minutes\s*=\s*(\d+)\s*$', _mine[0], re.M)
    if not _mr or not _cm:
        bad("(G2) max_runtime_minutes and checkin_margin_minutes are numeric literals",
            f"max_runtime={bool(_mr)} margin={bool(_cm)}")
    else:
        _job = int(job_m.group(1)); _mrv = int(_mr.group(1)); _cmv = int(_cm.group(1))
        _gp = []
        if _mrv != _job:
            _gp.append(f"max_runtime_minutes={_mrv} != job timeout-minutes={_job}")
        if _cmv < _job + 25:
            _gp.append(f"checkin_margin_minutes={_cmv} < job+25={_job + 25} (a healthy slow run would page)")
        if _cmv >= 360:
            _gp.append(f"checkin_margin_minutes={_cmv} >= the 360-min inter-fire gap (a dropped run would never page)")
        if _gp:
            bad("(G2) Sentry max_runtime/margin track the workflow job ceiling", "; ".join(_gp))
        else:
            ok(f"(G2) Sentry max_runtime ({_mrv}) == job ceiling ({_job}); margin {_cmv} in [{_job + 25}, 360)")

# The heartbeat's monitor-slug must be the Terraform resource's `name`: a typo'd slug checks in to
# a monitor that does not exist, so the real one pages as missed on every healthy run.
_slug = re.search(r'^\s*monitor-slug:\s*(\S+)\s*$', stripped, re.M)
if _slug and _slug.group(1) == "main-health-monitor":
    ok("(G2b) the Sentry heartbeat's monitor-slug is the Terraform monitor's name")
else:
    bad("(G2b) the Sentry heartbeat's monitor-slug is the Terraform monitor's name",
        f"slug={_slug.group(1) if _slug else None!r}")

# ---- (CG) a dry run must not share the cron run's concurrency group (#8112) ----------------
# A healthy run is ~110 minutes, so a manual or measurement dispatch queued in the same group
# within that window before a 6-hourly slot delays the scheduled run past the Sentry margin, and a
# dry run sends no check-in to say so.
if re.search(r"^  group: main-health-monitor\$\{\{ inputs\.dry_run && '[^']+' \|\| '' \}\}\s*$", stripped, re.M):
    ok("(CG) a dry run gets its own concurrency group")
else:
    bad("(CG) a dry run gets its own concurrency group",
        "the group does not branch on inputs.dry_run: a manual dispatch can queue the scheduled run "
        "behind it and trip the Sentry missed-check-in alarm")

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
#
# AMENDED 2026-08-10 (#7376) — deliberately, not worked around. The excerpt builder gained
# `grep -v '^SOLEUR| ' "$file" | tail -30`, which matches all three offender conditions and
# would otherwise red this check.
#
# The exemption is sound because defect B is about DISCARDING A PRODUCER'S VERDICT. This
# producer has no verdict to discard: it is a display filter over a file whose non-emptiness
# the enclosing `if [[ -s "$file" ]]` already established, and `grep -v`'s exit status here
# encodes only "did every line match the filter" — which is not an error condition, it is the
# fully-dumped case. Propagating it would make the monitor abort and file NOTHING in exactly
# the situation it exists to report.
#
# Keyed on the literal filter, so this exempts THAT line and nothing else — any other
# `| tail` still trips. Deliberately NOT spelled `grep -E -v` to slip past the substring
# exemption above, which would have widened the blind spot instead of narrowing it.
DISPLAY_FILTER_EXEMPT = "grep -v '^SOLEUR| '"
offenders = [l.strip() for l in run_lines
             if re.search(r'\|\s*(tail|head)\b', l)
             and 'PIPESTATUS' not in l
             and 'grep -E' not in l
             and DISPLAY_FILTER_EXEMPT not in l]
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

# ---- (MW) the mint-conclusion watch (#9082) ----------------------------------
# The mint-inngest-bootstrap-tag.yml workflow's own conclusion is a monitor
# input: a red run otherwise reaches the operator only via its Slack step, which
# is absent when SLACK_RELEASES_WEBHOOK_URL is unset. The mintwatch step must read
# the newest completed run on main via `gh run list --json` piped to STANDALONE
# jq (never `gh --jq`, which does not forward --arg — #9533), count `failure` and
# `startup_failure` as red, and feed the filer, the closer, and the Sentry
# check-in. An API failure must be ::error::-visible (fail-open), never a silent
# green. And the step carries NO timeout-minutes: check (6) pins the job ceiling
# at sum(step ceilings)+15, so a timed step silently breaks the derivation — the
# bounded part is the `timeout`-wrapped gh call inside.
_mw = _step_block("Read newest mint-inngest-bootstrap-tag run (slow-path)")
_mw_p = []
if not _mw:
    _mw_p.append("the mintwatch step is absent")
else:
    if "id: mintwatch" not in _mw:
        _mw_p.append("no `id: mintwatch` — the verdict output is unreferenceable")
    if "continue-on-error: true" not in _mw:
        _mw_p.append("no continue-on-error — an API blip could fail the job before the filer")
    if "timeout-minutes:" in _mw:
        _mw_p.append("declares timeout-minutes — check (6) pins job >= sum(step ceilings)+15")
    for tok in ("gh run list", "--workflow=mint-inngest-bootstrap-tag.yml", "--branch main", "--json"):
        if tok not in _mw:
            _mw_p.append(f"missing `{tok}` — it must read the newest mint run on main as JSON")
    if not re.search(r'\|\s*jq\b', _mw):
        _mw_p.append("the --json output never reaches a standalone jq")
    if "--jq" in _mw:
        _mw_p.append("uses `gh --jq` — it does not forward --arg (#9533); standalone jq only")
    if re.search(r'\|\s*grep -q', _mw):
        _mw_p.append("a pipe-fed `grep -q` decides a predicate — the banned SIGPIPE class")
    for concl in ("failure|", "startup_failure"):
        if concl not in _mw:
            _mw_p.append(f"conclusion {concl!r} not in the red set")
    if "::error::" not in _mw:
        _mw_p.append("no ::error:: — an API failure would be a silent green")
    if "verdict=" not in _mw or "GITHUB_OUTPUT" not in _mw:
        _mw_p.append("never emits `verdict=` to $GITHUB_OUTPUT")
    if "unknown" not in _mw:
        _mw_p.append("no `unknown` verdict — the fail-open third state is absent")
if _mw_p:
    bad("(MW) mintwatch reads the newest mint run, reds on failure|startup_failure, fails open loud",
        "; ".join(_mw_p))
else:
    ok("(MW) mintwatch reads the newest mint run, reds on failure|startup_failure, fails open loud")

# The verdict's THREE consumers — computed but unread is the feature's vacuous form.
_mw_w = []
_f_if = step_if(FILER) or ""
_c_if = step_if(CLOSER) or ""
# The heartbeat's verdict input is the `status:` expression, not an if: — check
# the expression itself. (_step_block now searches newline-completed text, so it
# can bound BEAT despite it being the job's LAST step; the direct regex stays
# because it names the exact input this row guards.)
_mw_status = re.search(r'^\s*status:\s*\$\{\{.*\}\}\s*$', stripped, re.M)
_mw_status = _mw_status.group(0) if _mw_status else ""
if "steps.mintwatch.outputs.verdict == 'red'" not in _f_if:
    _mw_w.append("the filer if: lacks `steps.mintwatch.outputs.verdict == 'red'` (a red mint never files)")
if "steps.mintwatch.outputs.verdict != 'red'" not in _c_if:
    _mw_w.append("the closer if: lacks `steps.mintwatch.outputs.verdict != 'red'` (a green-suite sweep retires a mint tracker)")
if "steps.mintwatch.outputs.verdict" not in _mw_status:
    _mw_w.append("the Sentry check-in's status: does not read the verdict (a red mint checks in ok)")
if _mw_w:
    bad("(MWb) the verdict reaches filer / closer / heartbeat", "; ".join(_mw_w))
else:
    ok("(MWb) the verdict reaches filer / closer / heartbeat")

# The filer's own arm: a mint-red run with green suites must not take the
# setup-failure arm — AP-021 requires the body to name what was measured.
_fblk = _step_block(FILER)
if "MINT_VERDICT" in _fblk and 'TITLE="CI: inngest-bootstrap auto-mint' in _fblk:
    ok("(MWc) the filer has a mint-red arm that names the measured conclusion")
else:
    bad("(MWc) the filer has a mint-red arm that names the measured conclusion",
        "a mint-red-only run would fall into the setup-failure arm and file a body "
        "naming nothing this run measured")

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
  CASES=$((CASES + 1))
  if [[ "$status" == "ok" ]]; then pass "$msg"; else fail "$msg" "$detail"; fi
done < "$RESULT_FILE"

# ── (13) the dump filter's EFFECT, not its spelling (#7376) ───────────────────────────────────
#
# Everything above parses the YAML with a python regex and NEVER EXECUTES THE SHELL, so an
# assertion that the literal `grep -v '^SOLEUR| '` appears would pin the filter's PRESENCE and
# say nothing about what it does. The compliance clearance for this change depends on the
# EFFECT: run-registered-suites.sh now prints per-suite diagnostics that must not reach a
# public issue body. So extract the excerpt expression from the workflow and run it.
#
# Extracted, not re-typed. A hand-copied duplicate of the pipeline is a second source of truth
# that drifts silently — this test would keep passing against a workflow that had stopped
# filtering.
# Extract ANY `grep -v '<pattern>' "$file" | tail -N` shape, not just today's sentinel. Pinning
# the extraction to `^SOLEUR| ` would make a WIDENED filter (a bare `^| `) unextractable, and it
# would then fail as "could not extract" — a correct verdict for the wrong reason, which reads
# as a missing filter rather than as the over-broad one that 13c exists to catch.
EXCERPT_EXPR="$(grep -oE "grep -v '[^']*' \"\\\$file\" \| tail -[0-9]+" "$WF" | head -1)"
if [[ -n "$EXCERPT_EXPR" ]]; then
  _fix="$(mktemp)"; _out="$(mktemp)"

  # DERIVE the sentinel from the runner instead of typing it. This is the only guard on the
  # producer->consumer direction: a runner-side rename plus its own test update (the natural
  # single-PR edit, both files under apps/web-platform/infra/) leaves this filter matching a
  # prefix the runner no longer emits, and every dumped byte — including the `[FAIL]` lines 10
  # registered suites print at column 0 — reaches the PUBLIC issue body and the monitor's
  # title derivation. Mirrors T8c's technique for MARKER_ERE in the runner's own suite.
  _RUNNER="$REPO_ROOT/apps/web-platform/infra/run-registered-suites.sh"
  SP="$(sed -n "s/^SENTINEL_PREFIX='\(.*\)'$/\1/p" "$_RUNNER")"
  CASES=$((CASES + 1))
  if [[ -z "$SP" ]]; then
    fail "(13) could not read SENTINEL_PREFIX from the runner" "$_RUNNER"
    SP='SOLEUR| '
  elif ! grep -qF "grep -v '^${SP}'" "$WF"; then
    fail "(13d) the workflow filters '^<other>' but the runner emits '${SP}'" \
      "a runner-side sentinel rename would publish every dumped diagnostic line"
  else
    pass "(13d) the workflow's filter pattern is derived from the runner's SENTINEL_PREFIX"
  fi

  # The fixture must exceed the tail window, or `tail -30` is a no-op and the ORDER of
  # `grep -v | tail` — the entire point — goes untested. A real capture puts ~46 prefixed
  # lines between the RED names and EOF, so the swapped order yields an EMPTY body.
  {
    echo "RED  apps/web-platform/infra/inngest.test.sh"
    echo "UNACCOUNTED  apps/web-platform/infra/zot-liveness.test.sh"
    echo "PASS apps/web-platform/infra/other.test.sh"
    printf "${SP}filler diagnostic line %s\n" $(seq 1 40)
    echo "${SP}[FAIL] a dumped marker that must NOT reach the public issue body"
    echo "${SP}retained per-suite log dir: /var/tmp/infra-suites.deadbeef"
    echo "| Service | Provider | Category |"
    echo "=== registered infra suites: 91 passed, 1 failed, 1 unaccounted (of 93) ==="
  } > "$_fix"
  # `file` IS read — by the workflow expression under `eval` below, which shellcheck cannot see
  # into. That indirection is the point: the expression is extracted from the YAML rather than
  # re-typed, so it reads the same variable name the workflow's own loop does.
  # shellcheck disable=SC2034
  file="$_fix"; eval "$EXCERPT_EXPR" > "$_out" 2>/dev/null || true

  CASES=$((CASES + 1))
  if ! grep -q '^SOLEUR| ' "$_out"; then
    pass "(13a) the excerpt drops every dumped diagnostic line"
  else
    fail "(13a) dumped diagnostic lines survive into the published excerpt" "$(grep -c '^SOLEUR| ' "$_out") line(s)"
  fi

  # WHITELIST, not an absence check. "no SOLEUR| line" is satisfied by a filter that drops
  # EVERYTHING, which would silently gut the issue body. Assert positively that the signal
  # the operator actually needs survived.
  CASES=$((CASES + 1))
  if grep -q '=== registered infra suites: 91 passed, 1 failed, 1 unaccounted (of 93) ===' "$_out" \
     && grep -q '^RED  *apps/web-platform/infra/inngest.test.sh' "$_out" \
     && grep -q '^UNACCOUNTED  *apps/web-platform/infra/zot-liveness.test.sh' "$_out"; then
    pass "(13b) the summary count, the RED name and the UNACCOUNTED name survive the filter"
  else
    fail "(13b) the filter removed signal the issue body depends on" "$(head -5 "$_out")"
  fi

  # The tests half of the same loop: expenses-verify-by-check prints markdown tables at
  # column 0. A bare `^| ` sentinel would have deleted them from the public excerpt; this is
  # the assertion that keeps the sentinel distinctive.
  CASES=$((CASES + 1))
  if grep -q '^| Service | Provider' "$_out"; then
    pass "(13c) a legitimate column-0 markdown table is NOT stripped"
  else
    fail "(13c) the filter stripped a markdown table — the sentinel is too broad"
  fi
  rm -f "$_fix" "$_out"
else
  CASES=$((CASES + 1))
  fail "(13) could not extract the excerpt filter from the workflow" \
    "the dump filter is missing, or its shape changed and this pin went blind"
fi

# ── (14) the redaction set actually redacts (#7376) ───────────────────────────────────────────
#
# This channel now carries per-suite diagnostic output into a PUBLIC issue body, so the
# redaction pass is load-bearing rather than belt-and-braces. Asserted by EXTRACTING the sed
# expressions from the workflow and running them — a re-typed copy would be a second source of
# truth that drifts silently.
#
# Every fixture is SYNTHESIZED (cq-test-fixtures-synthesized-only) and assembled by
# CONCATENATION, so no contiguous token-shaped literal exists in this file. A real-shaped
# literal would trip GitHub Push Protection and block the push even though the value is fake.
mapfile -t _SED_EXPRS < <(awk '/REDACTED=\$\(printf/,/^ *$/' "$WF" | grep -oE "^ *-e '.*'" | sed -E "s/^ *-e '//; s/'$//")
if (( ${#_SED_EXPRS[@]} >= 12 )); then
  _args=(); for e in "${_SED_EXPRS[@]}"; do _args+=(-e "$e"); done

  _hdr='-----BEGIN'; _ftr='-----END'
  _corpus="$(
    printf '%s\n' \
      "token gh""p_0123456789abcdefghij0123456789abcdef" \
      "jwt ey""J0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dBjftJeZ4CVPmB92K27uhbUJU1p1r_wW1gFWFOEjXk" \
      "supa sbp_""v0_0123456789abcdef0123456789abcdef01234567" \
      "stripe rk_""live_0123456789abcdefghij0123456789" \
      "whsec wh""sec_0123456789abcdefghij0123456789" \
      "doppler dp""."'scim'".0123456789abcdefghij0123456789abcdef0123" \
      "sentry sn""trys_0123456789abcdefghij0123456789abcdef" \
      "dsn https://0123456789abcdef0123456789abcdef@o123.ingest.sentry.io/456" \
      "Authorization: Bea""rer abcdefghijklmnop0123456789" \
      "${_hdr} RSA PRIVATE KEY-----" \
      "MIIEowIBAAKCAQEAsecretbodythatmustnotsurvive0123456789" \
      "${_ftr} RSA PRIVATE KEY-----" \
      "keepme: this ordinary diagnostic line must survive"
  )"
  _red="$(printf '%s' "$_corpus" | sed -E "${_args[@]}")"

  # Anchor on the SECRET-BEARING substrings, not on the word "redacted": asserting the
  # replacement text appears would pass even if one rule silently stopped matching.
  _leaks=()
  grep -q '0123456789abcdefghij0123456789abcdef' <<<"$_red" && _leaks+=("gh-token")
  grep -q 'dBjftJeZ4CVPmB92K27uhbUJU1p1r_wW1gFWFOEjXk' <<<"$_red" && _leaks+=("jwt")
  grep -q 'sbp_v0_' <<<"$_red" && _leaks+=("supabase")
  grep -qE '(rk_live|whsec)_[A-Za-z0-9]{16,}' <<<"$_red" && _leaks+=("stripe")
  grep -q 'scim\.0123456789' <<<"$_red" && _leaks+=("doppler-scim")
  grep -q 'sntrys_0123' <<<"$_red" && _leaks+=("sentry-token")
  grep -q 'o123.ingest.sentry.io' <<<"$_red" && _leaks+=("sentry-dsn")
  grep -q 'abcdefghijklmnop0123456789' <<<"$_red" && _leaks+=("authorization")
  grep -q 'MIIEowIBAAKCAQEAsecretbody' <<<"$_red" && _leaks+=("pem-body")

  CASES=$((CASES + 1))
  if (( ${#_leaks[@]} == 0 )); then
    pass "(14a) every synthesized secret shape is redacted (${#_SED_EXPRS[@]} rules)"
  else
    fail "(14a) secret shapes SURVIVED redaction" "leaked: ${_leaks[*]}"
  fi

  # The PEM rule is a RANGE. A header-only rule is an anti-mitigation: it strips the marker
  # that makes a leaked key recognisable and leaves the base64 body behind.
  CASES=$((CASES + 1))
  if ! grep -q 'MIIEowIBAAKCAQEA' <<<"$_red" && ! grep -q 'END RSA PRIVATE KEY' <<<"$_red"; then
    pass "(14b) the PEM rule removes the whole key BLOCK, not just its header"
  else
    fail "(14b) the PEM body or END line survived — the rule is header-only"
  fi

  # WHITELIST: redaction that eats everything is not a pass.
  CASES=$((CASES + 1))
  if grep -q 'keepme: this ordinary diagnostic line must survive' <<<"$_red"; then
    pass "(14c) ordinary diagnostic text survives redaction"
  else
    fail "(14c) redaction destroyed non-secret diagnostic text"
  fi
else
  CASES=$((CASES + 1))
  fail "(14) could not extract the redaction rules from the workflow" \
    "found ${#_SED_EXPRS[@]} -e expressions, expected >= 12"
fi
# =============================================================================
# BEHAVIOURAL ARMS -- the filer's `run:` body, EXECUTED (AC21 / AC22 / AC23)
# =============================================================================
# Every assertion above is a grep over source text, and a grep cannot see what the filer
# PRODUCES. The three properties that matter to the operator are all runtime facts:
#   * a `ghp_`-shaped token on a [KILLED] line is redacted out of the published body,
#   * a FORGED marker (a suite that merely prints `[KILLED] fake`) does not select the
#     fourth arm,
#   * the killed body's `Actions required` block is actionable and prescribes no revert.
#
# So this section extracts the step's real body from the live YAML and runs it against
# fixture captures with a stubbed `gh`. Two shells per scenario, and that is deliberate:
# a bare `run:` with no `shell:` key is `bash -e {0}` -- errexit ON, **pipefail OFF** (the
# 2026-07-30 correction in knowledge-base/project/learnings/best-practices/
# 2026-07-02-gha-run-default-shell-has-pipefail-guard-grep-substitutions.md). An explicit
# `shell: bash` is what adds `-o pipefail`. Running only the loose shell would let a
# pipefail-fragile capture ship; running only the strict one would model a shell this file
# does not use. Both, same expected outcome, is the only honest pair.
BEHAVE_DIR="$(mktemp -d -t mhm-behave.XXXXXXXX)" || exit 1
trap 'rm -f "$RESULT_FILE"; rm -rf "$BEHAVE_DIR"' EXIT

mkdir -p "$BEHAVE_DIR/bin" "$BEHAVE_DIR/run"

# `gh` stub: one argv element per line, so an assertion can match a WHOLE title rather
# than a substring of a space-joined blob.
cat > "$BEHAVE_DIR/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$MHM_GH_LOG"
if [[ "${1:-}" == "issue" && "${2:-}" == "list" ]]; then
  cat "$MHM_GH_LIST_JSON"
fi
exit 0
STUB
chmod +x "$BEHAVE_DIR/bin/gh"

# Extract the filer's run: body and repoint its hardcoded /tmp/ paths at the sandbox.
# `$SANDBOX/` substitution is the ONLY rewrite: any other edit would make this harness
# assert something the workflow does not do.
CASES=$((CASES + 1))
if ! python3 - "$WF" "$BEHAVE_DIR/run" > "$BEHAVE_DIR/filer.sh" 2>"$BEHAVE_DIR/extract.err"; then
  fail "(B0) the filer's run: body extracts cleanly" "$(head -5 "$BEHAVE_DIR/extract.err")"
else
  pass "(B0) the filer's run: body extracts cleanly from the live workflow"
fi <<'PY'
import re, sys
raw = open(sys.argv[1]).read().splitlines()
sandbox = sys.argv[2].rstrip("/") + "/"

start = next(i for i, l in enumerate(raw) if l == "      - name: Create issue on failure")
j = start
while raw[j].strip() != "run: |":
    j += 1
body = []
for line in raw[j + 1:]:
    if line.strip() == "":
        body.append("")
        continue
    if not line.startswith("          "):
        break
    body.append(line[10:])
text = "\n".join(body) + "\n"

# ANTI-VACUITY. An empty or truncated extraction would run cleanly and assert nothing.
assert len(body) > 100, f"extracted only {len(body)} lines"
assert "gh issue create" in text, "extraction missed the filer's create call"
# A `${{ }}` expression is interpolated by the Actions engine, not by bash, so its presence
# would mean this harness is executing something the runner never executes.
assert "${{" not in text, "run: body contains a ${{ }} expression -- not executable as-is"
sys.stdout.write(text.replace("/tmp/", sandbox))
PY

# Fixture captures. Built by concatenation on purpose: a contiguous `ghp_`-shaped literal
# in a tracked file is blocked by GitHub Push Protection even when it is synthetic, and by
# this repo's own gitleaks gate (cq-test-fixtures-synthesized-only).
_TOK="ghp_"; _TOK="${_TOK}0123456789abcdefghijklmnopqrstuv"

# 34 lines of runner epilogue after the terminal marker, so `tail -30` CANNOT reach the
# [KILLED] line. This is what makes the SUMMARY-append assertion non-vacuous: delete the
# append and the body still ends with a plausible-looking tail, naming no suite.
_epilogue() { local i; for i in $(seq 1 34); do echo "[contention] epilogue line $i"; done; }

{
  echo "PASS scripts/aaa.test.sh"
  echo "[KILLED] scripts/leaky-${_TOK}.test.sh (exit=137, signal-shaped 128+9 = SIGKILL, 42ms) — UNRESOLVED, not a failure: this runner did not measure what terminated it."
  echo "[KILLED] tests/scripts/registry-gate-mutation-battery (exit=143, signal-shaped 128+15 = SIGTERM, 560931ms) — UNRESOLVED, not a failure: this runner did not measure what terminated it."
  echo "=== 131 suites: 129 passed, 0 failed, 2 killed (unresolved — coverage not obtained) ==="
  echo "=== 129/131 suites passed ==="
  _epilogue
} > "$BEHAVE_DIR/fx-killed.txt"

{
  echo "PASS scripts/aaa.test.sh"
  echo "[KILLED] fake"
  echo "[KILLED] something the suite printed itself"
  echo "=== 131/131 suites passed ==="
  _epilogue
} > "$BEHAVE_DIR/fx-forged.txt"

# Shape-VALID [KILLED] line with no breakdown line to corroborate it: one line of suite
# stdout must not be able to select the fourth arm on its own.
{
  echo "PASS scripts/aaa.test.sh"
  echo "[KILLED] tests/scripts/forged-battery (exit=143, signal-shaped 128+15 = SIGTERM, 10ms) — printed by a suite, not by the runner"
  echo "=== 131/131 suites passed ==="
  _epilogue
} > "$BEHAVE_DIR/fx-uncorroborated.txt"

{
  echo "[FAIL] scripts/really-broken.test.sh (exit=1, 12ms)"
  echo "[KILLED] tests/scripts/registry-gate-mutation-battery (exit=143, signal-shaped 128+15 = SIGTERM, 560931ms) — UNRESOLVED, not a failure: this runner did not measure what terminated it."
  echo "=== 131 suites: 129 passed, 1 failed, 1 killed (unresolved — coverage not obtained) ==="
  echo "=== 129/131 suites passed ==="
  _epilogue
} > "$BEHAVE_DIR/fx-both.txt"

# ---- #8112 fixtures. Each is the LIVE shape of a capture, not a tidied one. -----------------
# The seven EXPECTED control lines quoted verbatim from #8112's body, then the epilogue of an
# orphaned runner that outlived the killed step: 413/414 passed, 0 failed.
{
  echo "[FAIL] dispatcher self-test: fail() increments (EXPECTED)"
  echo "[FAIL] accounting-control: fail() increments (EXPECTED, not a defect)"
  echo "[FAIL] accounting-control: fail() increments (EXPECTED, not a defect)"
  echo "[FAIL] instrument self-test: the FAIL arm records (EXPECTED — subtracted) "
  echo "[FAIL] instrument self-test (fail path — EXPECTED, discounted below)"
  echo "[FAIL] instrument self-test (fail path — EXPECTED, discounted below)"
  echo "[FAIL] positive control: bad() increments the fail counter (this FAIL line is expected)"
  _epilogue
  echo "=== 414 suites: 413 passed, 0 failed, 0 killed (unresolved — coverage not obtained), 1 skipped (declined — not relevant to this diff) ==="
  echo "=== 413/414 suites passed ==="
} > "$BEHAVE_DIR/fx-controls-zero-failed.txt"

# Run 36903587088's shape: the step ceiling killed the parent shell, the runner's parent-death
# watchdog killed the in-flight suite (rendered `[FAIL]`), and the runner died before it could
# print a breakdown. A `[FAIL]` line with NO verdict behind it.
{
  echo "PASS scripts/aaa.test.sh"
  echo "[FAIL] scripts/test-affected-kb-consumers (198336ms) log=/var/tmp/x.log"
  echo "ERROR: parent process gone — orphaned test-all run terminating itself and in-flight suite children (#8993)"
} > "$BEHAVE_DIR/fx-fail-no-breakdown.txt"

# The must-PASS non-canonical input: a label with SPACES, a `log=` suffix and a printed breakdown
# with failures. A classifier that rejects everything it does not recognise fails this one.
{
  echo "PASS scripts/aaa.test.sh"
  echo "[FAIL] apps/web-platform [unit] (1234ms) log=/var/tmp/y.log"
  echo "=== 414 suites: 412 passed, 2 failed, 0 killed (unresolved — coverage not obtained), 0 skipped (declined — not relevant to this diff) ==="
  echo "=== 412/414 suites passed ==="
} > "$BEHAVE_DIR/fx-fail-corroborated.txt"

# Infra-style failure: the infra runner prints `RED  <path>`, never `[FAIL]`, and no breakdown.
{
  echo "PASS apps/web-platform/infra/aaa.test.sh"
  echo "RED  apps/web-platform/infra/x.test.sh"
} > "$BEHAVE_DIR/fx-red-only.txt"

# The infra tail of run 36903587088: the step ceiling SIGTERMed the nested runner, which the
# top-level runner renders as a killed suite with a killed-only breakdown.
{
  echo "PASS apps/web-platform/infra/git-data-root-key.test.sh"
  echo "[KILLED] apps/web-platform/infra/run-registered-suites.sh (exit=143, signal-shaped 128+15 = SIGTERM, 1207161ms) — UNRESOLVED, not a failure: this runner did not measure what terminated it."
  echo "=== 1 suites: 0 passed, 0 failed, 1 killed (unresolved — coverage not obtained), 0 skipped (declined — not relevant to this diff) ==="
} > "$BEHAVE_DIR/fx-infra-killed.txt"

# Evidence fixtures. Each carries the 34-line epilogue AFTER the evidence lines, so `tail -30` CANNOT
# reach them: the only way they reach the body is the dedicated appends. A secret rides on every one
# of those lines to pin the redaction ORDER of the new display blocks.
{
  echo "[FAIL] scripts/evidence-a (11ms) log=/var/tmp/e.log ${_TOK}"
  echo "RED  apps/web-platform/infra/evidence-red.test.sh ${_TOK}"
  echo "ERROR: parent process gone — orphaned test-all run terminating itself ${_TOK}"
  _epilogue
} > "$BEHAVE_DIR/fx-evidence-above-tail.txt"
{
  echo "[FAIL] scripts/evidence-b (11ms) log=/var/tmp/e.log"
  echo "ERROR: parent process gone — orphaned test-all run terminating itself"
  _epilogue
} > "$BEHAVE_DIR/fx-unconfirmed-above-tail.txt"
# A plain failing run: the runner printed NO `=== N suites:` breakdown (nothing killed, skipped or
# declined) and only the terminal marker, with a short numerator.
{
  echo "PASS scripts/aaa.test.sh"
  echo "[FAIL] apps/web-platform [unit] (12ms) log=/var/tmp/z.log"
  echo "=== 3/4 suites passed ==="
} > "$BEHAVE_DIR/fx-fail-short-terminal.txt"
{
  cat "$BEHAVE_DIR/fx-fail-short-terminal.txt"
  echo "ERROR: parent process gone — orphaned test-all run terminating itself"
} > "$BEHAVE_DIR/fx-short-terminal-gone.txt"
# A NESTED runner's short marker, then the outer runner's full one: the LAST marker decides.
{
  echo "[FAIL] scripts/nested-control (1ms) log=/var/tmp/n.log"
  echo "=== 2/3 suites passed ==="
  echo "PASS scripts/zzz.test.sh"
  echo "=== 4/4 suites passed ==="
} > "$BEHAVE_DIR/fx-nested-short-then-full.txt"
# A NUL byte makes GNU grep treat the file as binary.
printf 'RED  apps/web-platform/infra/nul.test.sh\n\0\nPASS x\n' > "$BEHAVE_DIR/fx-nul.txt"
# Infra capture holding only a bare [FAIL] (no verdict behind it).
{
  echo "[FAIL] apps/web-platform/infra/bare-fail (3ms) log=/var/tmp/b.log"
} > "$BEHAVE_DIR/fx-bare-fail.txt"

# A killed suite whose label contains SPACES (the real `apps/web-platform [unit]` labels do).
{
  echo "[KILLED] apps/web-platform [unit] (exit=143, signal-shaped 128+15 = SIGTERM, 1234ms) — UNRESOLVED, not a failure: this runner did not measure what terminated it."
  echo "=== 5 suites: 4 passed, 0 failed, 1 killed (unresolved — coverage not obtained), 0 skipped (declined — not relevant to this diff) ==="
  _epilogue
} > "$BEHAVE_DIR/fx-killed-spaced.txt"

# Leak fixtures: `SOLEUR| ` diagnostic lines INSIDE the last 30 lines, and a unique final line.
# The tail block must appear exactly once and none of the diagnostic lines may reach the body.
_leak_tail() { local i; for i in 1 2 3 4 5 6; do echo "SOLEUR| leaked per-suite diagnostic $i"; done; echo "TAILMARK-8112-unique-last-line"; }
{
  echo "RED  apps/web-platform/infra/leaky.test.sh"
  echo "=== 5 suites: 3 passed, 2 failed, 0 killed (unresolved — coverage not obtained), 0 skipped (declined — not relevant to this diff) ==="
  _leak_tail
} > "$BEHAVE_DIR/fx-leak-failing.txt"
{
  echo "[KILLED] scripts/leaky.test.sh (exit=143, signal-shaped 128+15 = SIGTERM, 5ms) — UNRESOLVED, not a failure: this runner did not measure what terminated it."
  echo "=== 5 suites: 4 passed, 0 failed, 1 killed (unresolved — coverage not obtained), 0 skipped (declined — not relevant to this diff) ==="
  _leak_tail
} > "$BEHAVE_DIR/fx-leak-killed.txt"

# $1 tests fixture, $2 gh-issue-list JSON, $3 shell flags, $4 infra fixture (default: empty
# capture), $5 INFRA_OUTCOME (default success), $6 TESTS_OUTCOME (default failure). Echoes
# nothing; leaves artefacts at $BEHAVE_DIR/run/{issue-body.md,issue-comment.md,gh.log,stdout.txt}
# and sets B_RC. The second-capture arguments exist because the filer's classification
# quantifies over BOTH captures (#8112 Guard 1, mutation 3): a loop that stops at the first
# compliant capture is only visible with a second member that is not.
B_RC=0
run_filer() {
  rm -rf "${BEHAVE_DIR:?}/run"
  mkdir -p "$BEHAVE_DIR/run"
  cp "$1" "$BEHAVE_DIR/run/tests-output.txt"
  if [[ -n "${4:-}" ]]; then cp "$4" "$BEHAVE_DIR/run/infra-output.txt"; else : > "$BEHAVE_DIR/run/infra-output.txt"; fi
  printf '%s' "$2" > "$BEHAVE_DIR/run/list.json"
  : > "$BEHAVE_DIR/run/gh.log"
  B_RC=0
  # `-` selects an EMPTY outcome ("the step never ran"), which a plain default cannot express.
  local _to="${6:-failure}" _io="${5:-success}"
  [[ "$_to" == "-" ]] && _to=""
  [[ "$_io" == "-" ]] && _io=""
  # shellcheck disable=SC2086
  env PATH="$BEHAVE_DIR/bin:$PATH" \
      MHM_GH_LOG="$BEHAVE_DIR/run/gh.log" \
      MHM_GH_LIST_JSON="$BEHAVE_DIR/run/list.json" \
      GH_TOKEN=stub \
      RUN_URL="https://example.invalid/actions/runs/1" \
      COMMIT_SHA=deadbeefdeadbeef \
      TESTS_OUTCOME="$_to" INFRA_OUTCOME="$_io" \
      TESTS_ELAPSED_S="${B_TESTS_ELAPSED_S:-}" INFRA_ELAPSED_S="${B_INFRA_ELAPSED_S:-}" \
      bash --noprofile --norc $3 "$BEHAVE_DIR/filer.sh" \
      > "$BEHAVE_DIR/run/stdout.txt" 2>&1 || B_RC=$?
}

b_body() { cat "$BEHAVE_DIR/run/issue-body.md" 2>/dev/null; }
# $1 description, $2 detail on failure, $3 status (0 = holds). The CALL SITE bumps CASES.
row() { if [[ "$3" == "0" ]]; then pass "$1"; else fail "$1" "$2"; fi; }
# Anchored, whole-line greps over the body: a substring grep is satisfied by the arm-4 ACTIONS
# prose, which quotes the same phrases (B11b collided with item 3 that way).
b_has_line() { grep -qxF -- "$1" "$BEHAVE_DIR/run/issue-body.md" 2>/dev/null; }
b_count_re() { grep -c -- "$1" "$BEHAVE_DIR/run/issue-body.md" 2>/dev/null; }
b_title() { grep -m1 '^CI: ' "$BEHAVE_DIR/run/gh.log" 2>/dev/null; }

NO_TRACKER='[]'
HAS_TRACKER='[{"number":4242,"body":"tracker <!-- soleur:main-health-monitor --> body"}]'

ARM_E=0; ARM_PF=0
for SHELLOPTS_ARM in "-e" "-eo pipefail"; do
  ARM="[${SHELLOPTS_ARM}]"
  if [[ "$SHELLOPTS_ARM" == "-e" ]]; then ARM_E=$((ARM_E + 1)); else ARM_PF=$((ARM_PF + 1)); fi

  # --- AC21: redaction, and the [KILLED] line reaching the body at all -------
  run_filer "$BEHAVE_DIR/fx-killed.txt" "$NO_TRACKER" "$SHELLOPTS_ARM"
  CASES=$((CASES + 1))
  if [[ "$B_RC" -ne 0 ]]; then
    fail "(B1)$ARM the filer completes on a killed-only capture" \
      "rc=$B_RC -- under errexit an unguarded capture ABORTS the step, and everything below it (the issue body, the ::error::) never runs. stdout: $(tail -3 "$BEHAVE_DIR/run/stdout.txt" | tr '\n' ' ')"
  else
    pass "(B1)$ARM the filer completes on a killed-only capture"
  fi

  CASES=$((CASES + 1))
  if grep -qF -- 'registry-gate-mutation-battery' "$BEHAVE_DIR/run/issue-body.md"; then
    pass "(B2)$ARM the issue body NAMES the terminated suite"
  else
    fail "(B2)$ARM the issue body NAMES the terminated suite" \
      "the [KILLED] line sits 36 lines above the end of the capture, outside tail -30, so without the SUMMARY append the operator gets an issue titled 'terminated' naming no suite"
  fi

  CASES=$((CASES + 1))
  if grep -qF -- '<redacted-gh-token>' "$BEHAVE_DIR/run/issue-body.md"; then
    pass "(B3)$ARM a token on a [KILLED] line is redacted in the published body"
  else
    fail "(B3)$ARM a token on a [KILLED] line is redacted in the published body" \
      "this repo is PUBLIC; content appended AFTER the REDACTED= pass ships raw"
  fi
  CASES=$((CASES + 1))
  if grep -qF -- "$_TOK" "$BEHAVE_DIR/run/issue-body.md"; then
    fail "(B3b)$ARM the raw token literal does NOT survive into the body" \
      "the killed hits were appended after the redactor"
  else
    pass "(B3b)$ARM the raw token literal does not survive into the body"
  fi

  # --- AC23: the operator's killed issue is actionable ----------------------
  CASES=$((CASES + 1))
  if [[ "$(b_title)" == "CI: main-branch health check was terminated before it could report" ]]; then
    pass "(B4)$ARM a killed-only run selects the fourth (terminated) title"
  else
    fail "(B4)$ARM a killed-only run selects the fourth (terminated) title" \
      "title=$(b_title) -- 'tests failing' would assert a failure no suite reported"
  fi

  CASES=$((CASES + 1))
  if grep -qF -- 'gh workflow run main-health-monitor.yml' "$BEHAVE_DIR/run/issue-body.md"; then
    pass "(B5)$ARM the killed body's Actions block names a re-run command"
  else
    fail "(B5)$ARM the killed body's Actions block names a re-run command" \
      "the only actionable text on the page must match the arm it is on"
  fi
  CASES=$((CASES + 1))
  if [[ "$B_RC" -ne 0 ]] || grep -qF -- 'Fix the tests or revert the breaking change' "$BEHAVE_DIR/run/issue-body.md"; then
    fail "(B6)$ARM the killed body prescribes no revert" \
      "a non-technical operator is told to find and revert a commit on a run whose own lede says no suite reported a failure"
  else
    pass "(B6)$ARM the killed body prescribes no revert"
  fi
  CASES=$((CASES + 1))
  if grep -qF -- '### Actions required' "$BEHAVE_DIR/run/issue-body.md"; then
    pass "(B6b)$ARM the killed body still carries an Actions required block"
  else
    fail "(B6b)$ARM the killed body still carries an Actions required block" \
      "dropping the block entirely would pass (B6) while leaving the operator nothing"
  fi

  # --- AC22: a forged marker does not select the fourth arm -----------------
  # Asserted POSITIVELY (rc 0 AND the third arm's exact title), never as "not the
  # terminated title". A step that ABORTS writes no body and logs no title, so the
  # negative form is satisfied by the filer dying — measured: it let a mutation that
  # strips the `|| killed_hits=""` guard survive the whole battery. Under `-eo pipefail`
  # a no-match grep is exit 1 and errexit kills the step at that line, taking the issue
  # body, the ::error:: and the whole report with it.
  run_filer "$BEHAVE_DIR/fx-forged.txt" "$NO_TRACKER" "$SHELLOPTS_ARM"
  CASES=$((CASES + 1))
  if [[ "$B_RC" -eq 0 && "$(b_title)" == "CI: main-branch health check did not complete" ]]; then
    pass "(B7)$ARM a shape-invalid [KILLED] line does not select the fourth arm"
  else
    fail "(B7)$ARM a shape-invalid [KILLED] line does not select the fourth arm" \
      "rc=$B_RC title=$(b_title) -- either a suite that merely prints '[KILLED] fake' re-titles the operator's issue, or the no-match grep aborted the step outright"
  fi

  run_filer "$BEHAVE_DIR/fx-uncorroborated.txt" "$NO_TRACKER" "$SHELLOPTS_ARM"
  CASES=$((CASES + 1))
  if [[ "$B_RC" -eq 0 && "$(b_title)" == "CI: main-branch health check did not complete" ]]; then
    pass "(B8)$ARM a [KILLED] line with no runner breakdown line does not select the arm"
  else
    fail "(B8)$ARM a [KILLED] line with no runner breakdown line does not select the arm" \
      "rc=$B_RC title=$(b_title) -- the runner emits its breakdown line exactly once, after every suite has run; without corroboration one forged line of suite stdout re-titles the issue"
  fi

  # --- failure dominates ----------------------------------------------------
  run_filer "$BEHAVE_DIR/fx-both.txt" "$NO_TRACKER" "$SHELLOPTS_ARM"
  CASES=$((CASES + 1))
  if [[ "$(b_title)" == "CI: main branch tests failing" ]]; then
    pass "(B9)$ARM a capture with BOTH markers is reported as a failure"
  else
    fail "(B9)$ARM a capture with BOTH markers is reported as a failure" \
      "title=$(b_title) -- calling a run with a real [FAIL] merely 'terminated' hides it"
  fi
  CASES=$((CASES + 1))
  if grep -qF -- 'Fix the tests or revert the breaking change' "$BEHAVE_DIR/run/issue-body.md"; then
    pass "(B9b)$ARM the failure arm keeps its pre-existing Actions wording"
  else
    fail "(B9b)$ARM the failure arm keeps its pre-existing Actions wording" \
      "the per-arm refactor must not rewrite the arms it was not about"
  fi

  # --- AC23 (comment path): the arm's LEDE survives into the comment --------
  run_filer "$BEHAVE_DIR/fx-killed.txt" "$HAS_TRACKER" "$SHELLOPTS_ARM"
  CASES=$((CASES + 1))
  if grep -qF 'did not measure what terminated the suite' "$BEHAVE_DIR/run/issue-comment.md" 2>/dev/null; then
    pass "(B10)$ARM the existing-tracker comment carries the killed arm's LEDE"
  else
    fail "(B10)$ARM the existing-tracker comment carries the killed arm's LEDE" \
      "runs 2, 3, 4 ... of a flapping killed suite otherwise append only 'still not passing' -- an escalating claim that main is broken, from a runner that measured nothing"
  fi

  # --- #8112: a bare [FAIL] is not a verdict ---------------------------------
  # Titles are asserted POSITIVELY with rc 0 (see B7): a filer that aborts writes no title, so a
  # "not the failing title" assertion is satisfied by the filer dying.
  T_FAIL="CI: main branch tests failing"
  T_DNC="CI: main-branch health check did not complete"
  T_TERM="CI: main-branch health check was terminated before it could report"

  # P1: the seven EXPECTED control lines plus a 0-failed breakdown are not "tests failing".
  run_filer "$BEHAVE_DIR/fx-controls-zero-failed.txt" "$NO_TRACKER" "$SHELLOPTS_ARM"
  CASES=$((CASES + 1))
  if [[ "$B_RC" -eq 0 && "$(b_title)" == "$T_DNC" ]]; then
    pass "(B11)$ARM expected-control [FAIL] lines + a 0-failed breakdown select 'did not complete', not 'tests failing'"
  else
    fail "(B11)$ARM expected-control [FAIL] lines + a 0-failed breakdown select 'did not complete', not 'tests failing'" \
      "rc=$B_RC title=$(b_title) -- #8112: the runner's own breakdown said 0 failed and the tracker named a failing suite that does not exist"
  fi
  # B11b/B12b: evidence lines sit ABOVE the tail window (34-line epilogue after them), so only the
  # dedicated appends can put them in the body, and the labels are matched as WHOLE LINES.
  run_filer "$BEHAVE_DIR/fx-unconfirmed-above-tail.txt" "$NO_TRACKER" "$SHELLOPTS_ARM"
  CASES=$((CASES + 1))
  row "(B11b)$ARM an unconfirmed [FAIL] line above the tail window is shown under its own label" \
    "rc=$B_RC -- a bare [FAIL] under an arm-4 lede reads as a verdict unless labelled, and only the append can show it here" \
    "$([[ "$B_RC" -eq 0 ]] && b_has_line '--- unconfirmed [FAIL]-shaped lines (no failing breakdown) ---' \
        && grep -qxF -A0 '[FAIL] scripts/evidence-b (11ms) log=/var/tmp/e.log' "$BEHAVE_DIR/run/issue-body.md"; echo $?)"
  CASES=$((CASES + 1))
  row "(B12b)$ARM the runner's parent-process-gone line is shown under its own label" \
    "without it the reader infers a kill from a missing breakdown instead of reading the runner say so" \
    "$(b_has_line '--- runner evidence of a kill ---' \
        && grep -A1 -xF -- '--- runner evidence of a kill ---' "$BEHAVE_DIR/run/issue-body.md" | grep -c >/dev/null '^ERROR: parent process gone'; echo $?)"

  # P2: a [FAIL] artefact of a kill, with no breakdown at all, is not "tests failing" either.
  run_filer "$BEHAVE_DIR/fx-fail-no-breakdown.txt" "$NO_TRACKER" "$SHELLOPTS_ARM"
  CASES=$((CASES + 1))
  if [[ "$B_RC" -eq 0 && "$(b_title)" == "$T_DNC" ]]; then
    pass "(B12)$ARM a [FAIL] line with NO breakdown (the live shape of a killed step) selects 'did not complete'"
  else
    fail "(B12)$ARM a [FAIL] line with NO breakdown (the live shape of a killed step) selects 'did not complete'" \
      "rc=$B_RC title=$(b_title) -- run 36903587088: the parent-death watchdog rendered an in-flight suite as [FAIL] and the runner died before printing a verdict"
  fi

  # P3 (must-PASS, non-canonical): a real failure still titles "tests failing". The spaced
  # label and `log=` suffix are what a classifier written against the clean shape would reject.
  run_filer "$BEHAVE_DIR/fx-fail-corroborated.txt" "$NO_TRACKER" "$SHELLOPTS_ARM"
  CASES=$((CASES + 1))
  if [[ "$B_RC" -eq 0 && "$(b_title)" == "$T_FAIL" ]]; then
    pass "(B13)$ARM a [FAIL] line with spaces + a breakdown reporting 2 failed selects 'tests failing'"
  else
    fail "(B13)$ARM a [FAIL] line with spaces + a breakdown reporting 2 failed selects 'tests failing'" \
      "rc=$B_RC title=$(b_title) -- a classifier that rejects everything it does not recognise reports a genuinely broken main as healthy"
  fi
  CASES=$((CASES + 1))
  if [[ "$B_RC" -ne 0 ]] || grep -qF -- 'unconfirmed [FAIL]-shaped lines' "$BEHAVE_DIR/run/issue-body.md" 2>/dev/null; then
    fail "(B13b)$ARM a CONFIRMED failure does not label its [FAIL] lines unconfirmed" \
      "the label is for lines with no verdict behind them; here the runner's breakdown corroborates them"
  else
    pass "(B13b)$ARM a CONFIRMED failure does not label its [FAIL] lines unconfirmed"
  fi

  run_filer "$BEHAVE_DIR/fx-red-only.txt" "$NO_TRACKER" "$SHELLOPTS_ARM"
  CASES=$((CASES + 1))
  if [[ "$B_RC" -eq 0 && "$(b_title)" == "$T_FAIL" ]]; then
    pass "(B14)$ARM a bare RED line (no breakdown) still selects 'tests failing'"
  else
    fail "(B14)$ARM a bare RED line (no breakdown) still selects 'tests failing'" \
      "rc=$B_RC title=$(b_title) -- the infra runner's own verdict token must stay a verdict input"
  fi

  # P2b: an infra step killed at its ceiling keeps arm 3 ("terminated"), not arm 4.
  run_filer "$BEHAVE_DIR/fx-controls-zero-failed.txt" "$NO_TRACKER" "$SHELLOPTS_ARM" "$BEHAVE_DIR/fx-infra-killed.txt" failure success
  CASES=$((CASES + 1))
  if [[ "$B_RC" -eq 0 && "$(b_title)" == "$T_TERM" ]]; then
    pass "(B15)$ARM an infra capture ending in the runner's killed breakdown selects 'terminated'"
  else
    fail "(B15)$ARM an infra capture ending in the runner's killed breakdown selects 'terminated'" \
      "rc=$B_RC title=$(b_title) -- run 36903587088's infra step; arm 4 would drop the signal-shaped-exit guidance"
  fi

  # Guard 1 mutation 3: a compliant FIRST member (controls-only, 0 failed) must not hide a RED in
  # the SECOND capture. A loop that stops at the first capture yields arm 4 instead of arm 2.
  run_filer "$BEHAVE_DIR/fx-controls-zero-failed.txt" "$NO_TRACKER" "$SHELLOPTS_ARM" "$BEHAVE_DIR/fx-red-only.txt" failure failure
  CASES=$((CASES + 1))
  if [[ "$B_RC" -eq 0 && "$(b_title)" == "$T_FAIL" ]]; then
    pass "(B16)$ARM a compliant tests capture does not hide a RED in the infra capture"
  else
    fail "(B16)$ARM a compliant tests capture does not hide a RED in the infra capture" \
      "rc=$B_RC title=$(b_title) -- the classification must quantify over BOTH captures"
  fi

  # P6: the public body shows the tail once and carries no SOLEUR| diagnostic line, on the
  # failing arm and the killed arm. The leak was the unfiltered second `tail -30`.
  for _arm_fx in failing killed; do
    run_filer "$BEHAVE_DIR/fx-leak-${_arm_fx}.txt" "$NO_TRACKER" "$SHELLOPTS_ARM"
    CASES=$((CASES + 1))
    _leaked="$(grep -c '^SOLEUR| ' "$BEHAVE_DIR/run/issue-body.md" 2>/dev/null)"
    _tails="$(grep -c '^TAILMARK-8112-unique-last-line$' "$BEHAVE_DIR/run/issue-body.md" 2>/dev/null)"
    _label="$(grep -c -- '^--- (tail) ---$' "$BEHAVE_DIR/run/issue-body.md" 2>/dev/null)"
    if [[ "$B_RC" -eq 0 && "${_leaked:-x}" == "0" && "${_tails:-x}" == "1" && "${_label:-x}" == "0" ]]; then
      pass "(B17)$ARM the ${_arm_fx} arm's body has no SOLEUR| line, the tail exactly once, and no '--- (tail) ---' label"
    else
      fail "(B17)$ARM the ${_arm_fx} arm's body has no SOLEUR| line, the tail exactly once, and no '--- (tail) ---' label" \
        "rc=$B_RC soleur_lines=${_leaked:-?} tail_copies=${_tails:-?} tail_labels=${_label:-?} -- a raw unfiltered tail append publishes per-suite diagnostics to a PUBLIC issue and duplicates the tail"
    fi
  done

  # Arm 4's actions: main is UNVERIFIED, not known-broken, so no revert instruction.
  run_filer "$BEHAVE_DIR/fx-controls-zero-failed.txt" "$NO_TRACKER" "$SHELLOPTS_ARM"
  CASES=$((CASES + 1))
  row "(B18)$ARM the 'did not complete' arm says no failing suite was confirmed" \
    "arm 4 must tell the reader main is unverified, not known broken" \
    "$([[ "$B_RC" -eq 0 ]] && grep -qF -- 'confirmed no failing suite' "$BEHAVE_DIR/run/issue-body.md"; echo $?)"
  CASES=$((CASES + 1))
  row "(B18b)$ARM the 'did not complete' arm prescribes no revert and names the step-list command" \
    "arm 4 inherited the default ACTIONS ('identify the commit and revert it'), or lost its re-derivation hint" \
    "$([[ "$B_RC" -eq 0 ]] \
        && ! grep -qF -- 'Fix the tests or revert the breaking change' "$BEHAVE_DIR/run/issue-body.md" \
        && ! grep -qF -- 'Identify the commit that introduced the failure' "$BEHAVE_DIR/run/issue-body.md" \
        && grep -qF -- 'gh run view' "$BEHAVE_DIR/run/issue-body.md"; echo $?)"

  # Elapsed seconds, when the step recorded them, appear next to the outcomes in the body.
  B_TESTS_ELAPSED_S=2412 run_filer "$BEHAVE_DIR/fx-fail-no-breakdown.txt" "$NO_TRACKER" "$SHELLOPTS_ARM"
  CASES=$((CASES + 1))
  if grep -qE 'tests_elapsed_s=2412' "$BEHAVE_DIR/run/issue-body.md" 2>/dev/null; then
    pass "(B19)$ARM the step-outcomes line carries the tests step's elapsed seconds"
  else
    fail "(B19)$ARM the step-outcomes line carries the tests step's elapsed seconds" \
      "without the figure the reader cannot compare the step's elapsed time with its ceiling"
  fi
  # A non-numeric value must not reach the body at all (the value arrives from \$GITHUB_OUTPUT,
  # which every suite child inherits).
  B_TESTS_ELAPSED_S='12::error::injected' run_filer "$BEHAVE_DIR/fx-fail-no-breakdown.txt" "$NO_TRACKER" "$SHELLOPTS_ARM"
  CASES=$((CASES + 1))
  if [[ "$B_RC" -ne 0 || "$(b_title)" != "$T_DNC" ]] || grep -qF -- 'injected' "$BEHAVE_DIR/run/issue-body.md" 2>/dev/null; then
    fail "(B19b)$ARM a non-numeric elapsed value is dropped, not echoed" \
      "the value could be written by any suite child that inherits \$GITHUB_OUTPUT"
  else
    pass "(B19b)$ARM a non-numeric elapsed value is dropped, not echoed"
  fi
  # The infra figure and the existing-tracker COMMENT path carry it too.
  B_INFRA_ELAPSED_S=2326 run_filer "$BEHAVE_DIR/fx-fail-no-breakdown.txt" "$NO_TRACKER" "$SHELLOPTS_ARM" "$BEHAVE_DIR/fx-red-only.txt" failure failure
  CASES=$((CASES + 1))
  row "(B19c)$ARM the step-outcomes line carries the infra step's elapsed seconds" \
    "rc=$B_RC -- the infra half of the figure pair was unpinned" \
    "$([[ "$B_RC" -eq 0 ]] && grep -qF -- 'infra_elapsed_s=2326' "$BEHAVE_DIR/run/issue-body.md"; echo $?)"
  B_TESTS_ELAPSED_S=2412 run_filer "$BEHAVE_DIR/fx-fail-no-breakdown.txt" "$HAS_TRACKER" "$SHELLOPTS_ARM"
  CASES=$((CASES + 1))
  row "(B19d)$ARM the existing-tracker comment carries the elapsed seconds too" \
    "rc=$B_RC -- a flapping run's later comments would lose the figure the first body had" \
    "$([[ "$B_RC" -eq 0 ]] && grep -qF -- 'tests_elapsed_s=2412' "$BEHAVE_DIR/run/issue-comment.md"; echo $?)"

  # --- the runner prints no breakdown on a plain failing run: the fallback --------------------
  run_filer "$BEHAVE_DIR/fx-fail-short-terminal.txt" "$NO_TRACKER" "$SHELLOPTS_ARM"
  CASES=$((CASES + 1))
  row "(B20)$ARM a [FAIL] line + a short terminal marker and NO breakdown selects 'tests failing'" \
    "rc=$B_RC title=$(b_title) -- scripts/test-all.sh prints its breakdown only when something was killed/skipped/declined, so a plain failing run would otherwise read as 'did not complete'" \
    "$([[ "$B_RC" -eq 0 && "$(b_title)" == "$T_FAIL" ]]; echo $?)"
  run_filer "$BEHAVE_DIR/fx-short-terminal-gone.txt" "$NO_TRACKER" "$SHELLOPTS_ARM"
  CASES=$((CASES + 1))
  row "(B20b)$ARM the parent-death line disqualifies the fallback (a kill is not a verdict)" \
    "rc=$B_RC title=$(b_title)" \
    "$([[ "$B_RC" -eq 0 && "$(b_title)" == "$T_DNC" ]]; echo $?)"
  run_filer "$BEHAVE_DIR/fx-nested-short-then-full.txt" "$NO_TRACKER" "$SHELLOPTS_ARM"
  CASES=$((CASES + 1))
  row "(B20c)$ARM a nested runner's short marker followed by the outer full marker is not a failure" \
    "rc=$B_RC title=$(b_title) -- the LAST terminal marker is the outer runner's" \
    "$([[ "$B_RC" -eq 0 && "$(b_title)" == "$T_DNC" ]]; echo $?)"
  # The #8112 capture itself (0-failed breakdown AND a short terminal marker) must stay arm 4:
  # a printed breakdown is authoritative and disables the fallback.
  run_filer "$BEHAVE_DIR/fx-controls-zero-failed.txt" "$NO_TRACKER" "$SHELLOPTS_ARM"
  CASES=$((CASES + 1))
  row "(B20d)$ARM a printed 0-failed breakdown disables the terminal-marker fallback" \
    "rc=$B_RC title=$(b_title) -- the exact #8112 capture would re-title itself 'tests failing'" \
    "$([[ "$B_RC" -eq 0 && "$(b_title)" == "$T_DNC" ]]; echo $?)"

  run_filer "$BEHAVE_DIR/fx-killed-spaced.txt" "$NO_TRACKER" "$SHELLOPTS_ARM"
  CASES=$((CASES + 1))
  row "(B20e)$ARM a killed suite whose label contains spaces still selects 'terminated' and is named" \
    "rc=$B_RC title=$(b_title) -- the anchor required a label with no space, so the real 'apps/web-platform [unit]' labels were never named" \
    "$([[ "$B_RC" -eq 0 && "$(b_title)" == "$T_TERM" ]] && grep -q '^\[KILLED\] apps/web-platform \[unit\]' "$BEHAVE_DIR/run/issue-body.md"; echo $?)"

  # --- binary captures, redaction order of the new blocks, per-capture state, outcome shapes ---
  run_filer "$BEHAVE_DIR/fx-nul.txt" "$NO_TRACKER" "$SHELLOPTS_ARM"
  CASES=$((CASES + 1))
  row "(B21)$ARM a NUL byte in the capture does not hide a RED line from the verdict" \
    "rc=$B_RC title=$(b_title) -- GNU grep prints 'Binary file matches' for a file with a NUL unless -a is given" \
    "$([[ "$B_RC" -eq 0 && "$(b_title)" == "$T_FAIL" ]]; echo $?)"
  run_filer "$BEHAVE_DIR/fx-evidence-above-tail.txt" "$NO_TRACKER" "$SHELLOPTS_ARM"
  CASES=$((CASES + 1))
  row "(B22)$ARM a token on a [FAIL], a RED and a parent-process-gone line is redacted in the public body" \
    "rc=$B_RC -- the new display blocks must be appended BEFORE the redaction pass" \
    "$([[ "$B_RC" -eq 0 ]] \
        && [[ "$(grep -c -- '<redacted-gh-token>' "$BEHAVE_DIR/run/issue-body.md")" -ge 3 ]] \
        && ! grep -qF -- "$_TOK" "$BEHAVE_DIR/run/issue-body.md"; echo $?)"
  CASES=$((CASES + 1))
  row "(B22b)$ARM the RED, [FAIL] and gone lines above the tail window all reach the body" \
    "the dedicated appends are the only way these lines (34 lines above the end) get published" \
    "$(grep -q '^RED  apps/web-platform/infra/evidence-red.test.sh' "$BEHAVE_DIR/run/issue-body.md" \
        && grep -q '^\[FAIL\] scripts/evidence-a' "$BEHAVE_DIR/run/issue-body.md" \
        && grep -q '^ERROR: parent process gone' "$BEHAVE_DIR/run/issue-body.md"; echo $?)"
  # cap_fail is PER CAPTURE: a confirmed tests capture must not launder a bare [FAIL] in infra.
  run_filer "$BEHAVE_DIR/fx-fail-corroborated.txt" "$NO_TRACKER" "$SHELLOPTS_ARM" "$BEHAVE_DIR/fx-bare-fail.txt" failure failure
  CASES=$((CASES + 1))
  row "(B23)$ARM a confirmed tests capture does not launder an unconfirmed [FAIL] in the infra capture" \
    "rc=$B_RC title=$(b_title) unconfirmed_labels=$(b_count_re '^--- unconfirmed')" \
    "$([[ "$B_RC" -eq 0 && "$(b_title)" == "$T_FAIL" && "$(b_count_re '^--- unconfirmed')" == "1" ]]; echo $?)"
  # Outcome shapes: success + failure, cancelled, and an empty (never ran) outcome.
  run_filer "$BEHAVE_DIR/fx-controls-zero-failed.txt" "$NO_TRACKER" "$SHELLOPTS_ARM" "$BEHAVE_DIR/fx-red-only.txt" failure success
  CASES=$((CASES + 1))
  row "(B24)$ARM tests=success with infra=failure reports ONLY the infra capture" \
    "rc=$B_RC title=$(b_title) -- a deleted success-skip re-adds the other step's PASS lines to the body" \
    "$([[ "$B_RC" -eq 0 && "$(b_title)" == "$T_FAIL" ]] \
        && b_has_line '--- infra (outcome=failure) ---' \
        && ! grep -q '^--- tests ' "$BEHAVE_DIR/run/issue-body.md"; echo $?)"
  run_filer "$BEHAVE_DIR/fx-controls-zero-failed.txt" "$NO_TRACKER" "$SHELLOPTS_ARM" "" cancelled cancelled
  CASES=$((CASES + 1))
  row "(B25)$ARM a cancelled step with no confirmed failure selects 'did not complete'" \
    "rc=$B_RC title=$(b_title) -- a step-ceiling kill is outcome cancelled, never a failure verdict" \
    "$([[ "$B_RC" -eq 0 && "$(b_title)" == "$T_DNC" ]]; echo $?)"
  run_filer "$BEHAVE_DIR/fx-controls-zero-failed.txt" "$NO_TRACKER" "$SHELLOPTS_ARM" "" - -
  CASES=$((CASES + 1))
  row "(B26)$ARM two steps that never ran select 'could not run'" \
    "rc=$B_RC title=$(b_title) -- an unconditional RAN_ANY=1 makes this arm unreachable" \
    "$([[ "$B_RC" -eq 0 && "$(b_title)" == "CI: main-branch health check could not run" ]]; echo $?)"
done

# Both shell arms must each have run exactly once: `for ARM in "-e" "-e"` would keep the count and
# silently never run the pipefail arm.
CASES=$((CASES + 1))
if [[ "$ARM_E" -eq 1 && "$ARM_PF" -eq 1 ]]; then
  pass "(B27) both shell arms (-e and -eo pipefail) each ran the behavioural rows exactly once"
else
  fail "(B27) both shell arms (-e and -eo pipefail) each ran the behavioural rows exactly once" \
    "-e ran $ARM_E time(s), -eo pipefail ran $ARM_PF time(s)"
fi

# ---- the Record step outcomes `run:` body, EXECUTED (the numeric guard feeds a workflow command) ----
# $GITHUB_OUTPUT is inherited by every suite child, so the elapsed values are suite-controlled input
# that reaches `echo "::notice ..."`. Only an executed body can show a value cannot smuggle a command.
CASES=$((CASES + 1))
if ! python3 - "$WF" > "$BEHAVE_DIR/record.sh" 2>"$BEHAVE_DIR/record.err" <<'PY'
import sys
raw = open(sys.argv[1]).read().splitlines()
start = next(i for i, l in enumerate(raw) if l == "      - name: Record step outcomes")
j = start
while raw[j].strip() != "run: |":
    j += 1
body = []
for line in raw[j + 1:]:
    if line.strip() == "":
        body.append("")
        continue
    if not line.startswith("          "):
        break
    body.append(line[10:])
text = "\n".join(body) + "\n"
assert len(body) >= 8, f"extracted only {len(body)} lines"
text = text.replace("${{ steps.tests.outcome }}", "failure").replace("${{ steps.infra.outcome }}", "success").replace("${{ steps.mintwatch.outputs.verdict }}", "green")
# Any `${{ }}` still present is an expression the engine would interpolate INTO the script.
assert "${{" not in text, "Record step body still contains a ${{ }} expression after the three verdict substitutions"
sys.stdout.write(text)
PY
then
  fail "(R0) the Record step's run: body extracts with no workflow expression left beyond the three verdict substitutions" "$(head -3 "$BEHAVE_DIR/record.err")"
else
  pass "(R0) the Record step's run: body extracts with no workflow expression left beyond the three verdict substitutions"
fi
rec() { # $1 tests-elapsed  $2 infra-elapsed -> the ::notice line
  env TESTS_ELAPSED_S="$1" INFRA_ELAPSED_S="$2" GITHUB_STEP_SUMMARY="$BEHAVE_DIR/summary.txt" \
      bash --noprofile --norc -e "$BEHAVE_DIR/record.sh" 2>&1 | grep -a '^::notice' | head -1
}
_N='::notice title=main-health-outcomes::SOLEUR_MAIN_HEALTH tests=failure infra=success mint=green'
CASES=$((CASES + 1))
row "(R1) two numeric figures reach the ::notice annotation" "got: $(rec 4228 2326)" \
  "$([[ "$(rec 4228 2326)" == "$_N tests_elapsed_s=4228 infra_elapsed_s=2326" ]]; echo $?)"
CASES=$((CASES + 1))
row "(R2) a non-numeric tests figure is dropped and the infra figure survives" "got: $(rec '12::error::x' 2326)" \
  "$([[ "$(rec '12::error::x' 2326)" == "$_N infra_elapsed_s=2326" ]]; echo $?)"
CASES=$((CASES + 1))
row "(R3) a non-numeric infra figure is dropped and the tests figure survives" "got: $(rec 4228 $'9\n::error::x')" \
  "$([[ "$(rec 4228 $'9\n::error::x')" == "$_N tests_elapsed_s=4228" ]]; echo $?)"
CASES=$((CASES + 1))
row "(R4) empty figures (a killed step wrote none) leave the annotation without elapsed fields" "got: $(rec '' '')" \
  "$([[ "$(rec '' '')" == "$_N" ]]; echo $?)"

# ── (MWd) the mintwatch step body, EXECUTED (#9082) ────────────────────────────
#
# The MW static rows pin TOKENS (gh flags, the red-set members, ::error::) — a
# verdict-polarity swap (`failure|startup_failure) VERDICT="green"`) survives all
# of them. The convention this suite established for the filer and the Record
# step applies here too: extract the real run: body and EXECUTE it, with a stub
# `gh` feeding each fixture, and read the $GITHUB_OUTPUT the step writes. An
# API-error arm is asserted to emit ::error:: AND verdict=unknown — never a
# silent green.
CASES=$((CASES + 1))
if ! python3 - "$WF" > "$BEHAVE_DIR/mintwatch.sh" 2>"$BEHAVE_DIR/mintwatch.err" <<'PY'
import sys
raw = open(sys.argv[1]).read().splitlines()
start = next(i for i, l in enumerate(raw)
             if l == "      - name: Read newest mint-inngest-bootstrap-tag run (slow-path)")
j = start
while raw[j].strip() != "run: |":
    j += 1
body = []
for line in raw[j + 1:]:
    if line.strip() == "":
        body.append("")
        continue
    if not line.startswith("          "):
        break
    body.append(line[10:])
text = "\n".join(body) + "\n"
assert len(body) >= 20, f"extracted only {len(body)} lines"
assert "${{" not in text, "mintwatch body still contains a ${{ }} expression"
sys.stdout.write(text)
PY
then
  fail "(MWd0) the mintwatch step's run: body extracts with no workflow expression left" "$(head -3 "$BEHAVE_DIR/mintwatch.err")"
else
  pass "(MWd0) the mintwatch step's run: body extracts with no workflow expression left"
fi

# The stub answers `gh run list` only — every other gh call fails loudly so a new
# producer sneaking in cannot silently succeed under the fixture. Written once,
# with the fixture path baked in (the child env does not export BEHAVE_DIR).
mkdir -p "$BEHAVE_DIR/mintstub"
GH_STUB="$BEHAVE_DIR/mintstub/gh"
cat > "$GH_STUB" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "run" && "\$2" == "list" ]]; then
  fx="\$(cat "$BEHAVE_DIR/mintstub/fx.txt")"
  if [[ "\$fx" == "@FAIL" ]]; then echo "gh: api error (stub)" >&2; exit 1; fi
  cat "$BEHAVE_DIR/mintstub/fx.txt"
else
  echo "gh stub: unexpected argv: \$*" >&2; exit 2
fi
EOF
chmod +x "$GH_STUB"
mwv() { # $1 = fixture file (JSON emitted by the stub; a file whose content is
        # "@FAIL" makes gh exit 1)  -> prints the verdict line the step emitted
  local fx="$1" out="$BEHAVE_DIR/mintstub/out.txt"
  : > "$out"
  cp "$fx" "$BEHAVE_DIR/mintstub/fx.txt"
  env PATH="$BEHAVE_DIR/mintstub:/usr/bin:/bin" GH_TOKEN=dummy GITHUB_OUTPUT="$out" \
    bash --noprofile --norc "$BEHAVE_DIR/mintwatch.sh" > "$BEHAVE_DIR/mintstub/stdout.txt" 2>&1
  grep -oE 'verdict=[a-z]+' "$out" | tail -1
}
MWFX="$BEHAVE_DIR/mintstub/fixtures"; mkdir -p "$MWFX"
printf '%s' '[{"databaseId":1,"conclusion":"failure","status":"completed","createdAt":"2026-10-06T00:00:00Z","headSha":"abc"}]' > "$MWFX/failure.json"
printf '%s' '[{"databaseId":1,"conclusion":"startup_failure","status":"completed","createdAt":"2026-10-06T00:00:00Z","headSha":"abc"}]' > "$MWFX/startup_failure.json"
printf '%s' '[{"databaseId":1,"conclusion":"success","status":"completed","createdAt":"2026-10-06T00:00:00Z","headSha":"abc"}]' > "$MWFX/success.json"
printf '%s' '[]' > "$MWFX/none.json"
printf '%s' '[{"databaseId":1,"conclusion":null,"status":"in_progress","createdAt":"2026-10-06T00:00:00Z","headSha":"abc"}]' > "$MWFX/inflight.json"
printf '%s' '[{"databaseId":1,"conclusion":"failure","status":"completed","createdAt":"2026-10-05T00:00:00Z","headSha":"abc"},{"databaseId":2,"conclusion":"success","status":"completed","createdAt":"2026-10-06T00:00:00Z","headSha":"def"}]' > "$MWFX/newest-completed-wins.json"
printf '%s' 'not-json' > "$MWFX/invalid.json"
printf '%s' '@FAIL' > "$MWFX/api-error.txt"
for _fx in failure:red startup_failure:red success:green none:green inflight:green newest-completed-wins:green; do
  _name="${_fx%%:*}"; _want="${_fx##*:}"
  CASES=$((CASES + 1))
  _got="$(mwv "$MWFX/$_name.json")"
  if [[ "$_got" == "verdict=${_want}" ]]; then
    pass "(MWd) a $_name completed-run verdict maps to ${_want}"
  else
    fail "(MWd) a $_name completed-run verdict maps to ${_want}" "got: $_got stdout: $(tail -2 "$BEHAVE_DIR/mintstub/stdout.txt" | tr '\n' ' ')"
  fi
done
CASES=$((CASES + 1))
_got="$(mwv "$MWFX/invalid.json")"
if [[ "$_got" == "verdict=unknown" ]] && grep -q '^::error::' "$BEHAVE_DIR/mintstub/stdout.txt"; then
  pass "(MWd) unparseable gh output emits ::error:: and verdict=unknown — never a silent green"
else
  fail "(MWd) unparseable gh output emits ::error:: and verdict=unknown" "got: $_got stdout: $(tail -2 "$BEHAVE_DIR/mintstub/stdout.txt" | tr '\n' ' ')"
fi
CASES=$((CASES + 1))
_got="$(mwv "$MWFX/api-error.txt")"
if [[ "$_got" == "verdict=unknown" ]] && grep -q '^::error::' "$BEHAVE_DIR/mintstub/stdout.txt"; then
  pass "(MWd) a gh failure emits ::error:: and verdict=unknown — never a silent green"
else
  fail "(MWd) a gh failure emits ::error:: and verdict=unknown" "got: $_got stdout: $(tail -2 "$BEHAVE_DIR/mintstub/stdout.txt" | tr '\n' ' ')"
fi

# ACCOUNTING CONSERVATION. Placed BEFORE the positive control on purpose: the
# control below also trips on a neutered pass()/fail(), and whichever check runs
# first is the one that names the fault. This one names it most precisely --
# "N assertions were dispatched and only M verdicts came back" -- and it covers
# a case the control cannot: a dispatch site whose verdict is silently dropped
# while pass()/fail() themselves still work.
#
# Reported with `printf >&2` + `exit 1` DIRECTLY, never through fail(): a check
# that reports by calling fail() increments the same counter the exit status
# reads, so neutering fail() silences the rows AND the check that exists to
# notice the silence.
if [[ $((PASS + FAIL)) -ne "$CASES" ]]; then
  printf '\n[FATAL] accounting: PASS+FAIL (%d) != CASES (%d).\n' \
    "$((PASS + FAIL))" "$CASES" >&2
  if [[ $((PASS + FAIL)) -lt "$CASES" ]]; then
    printf '  An assertion was dispatched but its verdict was not recorded — that is what a neutered pass()/fail() looks like.\n' >&2
  else
    printf '  A verdict was recorded at a call site with no `CASES=$((CASES + 1))` before it. This is a harness bug, not a product failure: add the increment at that call site.\n' >&2
  fi
  echo "=== Results: $PASS passed, $FAIL failed ($CASES assertions dispatched) ==="
  exit 1
fi

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
# Calibrated to the CURRENT count, not left at the pre-#7424 value of 14. Slack in this
# floor IS the budget a stranded layer has to hide in: at 14-against-56, making the static
# block emit nothing reported 28 assertions / exit 0 (all nine #7424 static guards gone),
# and stranding the behavioural battery reported 30 / exit 0 (all 26 AC21/AC22/AC23
# assertions gone, incl. redaction and forged-marker rejection).
#
# Reported with `printf >&2` + `exit 1` DIRECTLY, never by bumping FAIL. A floor
# that reports itself through FAIL increments the same counter the exit status
# reads, so neutering pass()/fail() silences every row AND the floor that exists
# to notice the silence -- the suite prints a total and exits 0. A floor enforced
# through the suspect cannot witness the suspect.
# Raised from 63 to 135 in #8112 (the classifier, leak, elapsed-annotation and Sentry-parity rows;
# every behavioural row runs in BOTH shell arms, so count rows x 2). Re-read the current total
# from the `anti-vacuity: N assertions ran` line rather than carrying this literal forward.
MIN_ASSERTIONS=135
TOTAL=$((PASS + FAIL))
if [[ "$TOTAL" -lt "$MIN_ASSERTIONS" ]]; then
  printf '\n[FATAL] anti-vacuity floor: only %d assertion(s) ran, expected >= %d.\n' \
    "$TOTAL" "$MIN_ASSERTIONS" >&2
  echo "=== Results: $PASS passed, $FAIL failed ($CASES assertions dispatched) ==="
  exit 1
fi
pass "anti-vacuity: $TOTAL assertions ran (floor $MIN_ASSERTIONS)"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
