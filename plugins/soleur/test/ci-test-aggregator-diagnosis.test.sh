#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Guard 6 (#7931 part 2) — the `test` aggregator names the MEASURED cause.
#
# WHAT THIS EXISTS TO CATCH. `ci.yml`'s `test` job reported every non-success
# leg as a bare `echo "$shard: $result"`. A leg killed by its own declared
# `timeout-minutes` and a leg cancelled because a newer commit superseded the
# run both render as the identical string `test-scripts: cancelled`. `test` is
# the repo's most load-bearing required status, and its own output could not
# distinguish "CI is too slow" from "someone pushed again" — the discrimination
# #7902 needed and had to reconstruct from the REST API after the fact.
#
# WHY A SHAPE COMPARISON AND NOT AN ELAPSED-TIME LOOKUP. An earlier revision of
# the plan added `actions/checkout`, a `gh api` call and a new script to this
# job so it could compare each leg's elapsed time against a parsed budget. That
# widens the input surface of the repo's most load-bearing required check —
# from three GitHub-provided strings plus the workflow file, to those plus a
# checkout plus a network call — in order to obtain a DIAGNOSTIC STRING. It was
# cut. The discriminator is already in the three strings:
#
#   * a concurrency cancellation cancels the WHOLE run, so every in-flight leg
#     reads `cancelled`;
#   * a `timeout-minutes` kill stops ONE leg while its siblings conclude.
#
# That comparison is also correct whether GitHub reports a timed-out job as
# `cancelled` or as `failure`, which the elapsed-vs-budget approach had to
# assume without a citation.
#
# WHY THE BODY IS EXECUTED, NOT GREPPED. A grep over the workflow source cannot
# tell "the classifier emits this line" from "the classifier never looked" —
# both are the same bytes on disk. So this harness EXTRACTS the step's `run:`
# body and EXECUTES it, under the shell GitHub Actions actually uses for a
# `run:` block with no `shell:` key:
#     bash --noprofile --norc -eo pipefail {0}
# `-e` and `pipefail` are ON before the body's own `set` runs. A harness that
# executed the body under a bare `bash` would make the whole `set -e` abort
# class structurally invisible. Precedent: scripts/skill-security-scan-step-body.test.sh.
#
# RED BY DESIGN AT THE COMMIT THAT INTRODUCES IT (cq-write-failing-tests-before).
# Every classification row below asserts a named line the aggregator does not
# yet emit, so this suite fails against the unmodified `ci.yml`. The closer is
# the next commit. That separation is re-derivable from history forever:
#   git log --diff-filter=A --format=%H -- plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh
# yields a SHA whose `git show --name-only` contains no `.github/workflows` path.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

# A DIRECT invocation inherits the bare /tmp — a machine-global 4 GiB tmpfs
# shared by every parallel worktree — while the registered runners default to
# /var/tmp. Without this, verdicts become a function of another session's disk
# usage rather than of the code under test.
export TMPDIR="${TMPDIR:-/var/tmp}"

passes=0
fails=0
# APPEND-ONLY FAILURE LEDGER. A verdict computed as `[ "$fails" -eq 0 ]` shares
# its counter with the thing it guards, so ONE token silences the suite:
# rewrite `fail()` to increment `passes` and a real regression reports a full
# green run at exit 0. The exit status reads a ledger that can only be silenced
# by DELETING evidence, not by moving a number.
FAILURES=()
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); FAILURES+=("$1"); printf 'FAIL: %s\n' "$1" >&2; }

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
CI_YML="$REPO_ROOT/.github/workflows/ci.yml"
STEP_NAME="Aggregate shard results"

[ -f "$CI_YML" ] || { printf 'FAIL: %s not found\n' "$CI_YML" >&2; exit 2; }

SANDBOX=$(mktemp -d -t ci-aggr-diag.XXXXXXXX) || {
  printf 'FAIL: could not create sandbox (mktemp -d failed)\n' >&2; exit 2; }
# A harness that fails to SET UP must abort, never continue — a half-built
# sandbox produces a CONFIDENT WRONG verdict about the SUT, not a missing one.
trap 'rm -rf "$SANDBOX"' EXIT

python3 -c 'import yaml' 2>/dev/null || {
  printf 'FAIL: PyYAML is required to extract the step body\n' >&2; exit 2; }

echo "=== Guard 6: the test aggregator names the measured cause (#7931 part 2) ==="

# ── Extraction ───────────────────────────────────────────────────────────────
# Bound BY NAME, never by index: an index-bound extraction shifts silently when
# a step is inserted above, and every must-FAIL row then passes for the wrong
# reason (bash on a missing file exits 127, which reads as "failed closed").
BODY="$SANDBOX/body.aggregate"
extract_body() {  # $1 = workflow path, $2 = destination
  python3 - "$1" "$2" "$STEP_NAME" <<'PY'
import sys, yaml
wf, dst, want = sys.argv[1], sys.argv[2], sys.argv[3]
doc = yaml.safe_load(open(wf))
found = []
for jname, job in (doc.get("jobs") or {}).items():
    for step in (job.get("steps") or []):
        if step.get("name") == want and "run" in step:
            found.append((jname, step["run"]))
if len(found) != 1:
    sys.stderr.write("expected exactly 1 step named %r, found %d\n" % (want, len(found)))
    sys.exit(3)
open(dst, "w").write(found[0][1])
PY
}

if ! extract_body "$CI_YML" "$BODY" 2>"$SANDBOX/extract.err"; then
  printf 'FAIL: could not extract the %s step body: %s\n' \
    "$STEP_NAME" "$(cat "$SANDBOX/extract.err")" >&2
  exit 2
fi
[ -s "$BODY" ] || { printf 'FAIL: extracted body is empty\n' >&2; exit 2; }
cp "$BODY" "$SANDBOX/body.pristine"
_body_lines=$(grep -c . "$BODY")
echo "  extracted: $_body_lines non-blank lines from the '$STEP_NAME' step"

# ── INSTRUMENT SELF-TEST ─────────────────────────────────────────────────────
# Drive both assertion helpers once each and refuse to continue unless BOTH
# counters moved. A battery whose helpers are broken prints verdicts about the
# SUT that are really verdicts about the harness; this is the one check that
# cannot be dispatched through the helpers it guards.
_p0=$passes; _f0=$fails
pass; fail "INSTRUMENT SELF-TEST (expected — this row proves fail() increments)"
if [ "$passes" -ne $((_p0 + 1)) ] || [ "$fails" -ne $((_f0 + 1)) ]; then
  printf 'FAIL: instrument self-test — pass()/fail() did not both move (passes %d->%d, fails %d->%d)\n' \
    "$_p0" "$passes" "$_f0" "$fails" >&2
  exit 2
fi
# Retract the deliberate failure so it does not colour the verdict.
fails=$((fails - 1)); unset 'FAILURES[${#FAILURES[@]}-1]'
echo "  instrument self-test: pass() and fail() both move"

# ── Execution harness ────────────────────────────────────────────────────────
# Executes an extracted body under the shell GitHub Actions actually uses.
run_body() {  # $1=body $2=webplat $3=bun $4=scripts $5=event ; sets OUT/RC
  OUT="$SANDBOX/out.$RANDOM.$RANDOM"
  ( WEBPLAT_RESULT="$2" BUN_RESULT="$3" SCRIPTS_RESULT="$4" EVENT_NAME="$5" \
      bash --noprofile --norc -eo pipefail "$1" ) >"$OUT" 2>&1
  RC=$?
}

# A single classification expectation. Every row states the FULL triple so the
# fixture-space cardinality is visible at the call site rather than implied.
expect_line() {  # $1=label $2=body $3..$5=results $6=event $7=needle $8=want_rc
  local label="$1" body="$2" w="$3" b="$4" s="$5" ev="$6" needle="$7" want_rc="$8"
  run_body "$body" "$w" "$b" "$s" "$ev"
  local ok=1
  grep -qF -- "$needle" "$OUT" || ok=0
  [ "$RC" -eq "$want_rc" ] || ok=0
  if [ "$ok" -eq 1 ]; then pass; return 0; fi
  fail "$label — triple=($w,$b,$s) event=$ev: expected a line containing '$needle' and rc=$want_rc; got rc=$RC, output: $(tr '\n' '|' <"$OUT" | head -c 300)"
  return 1
}

# `grep -qF -- "$needle" "$OUT"` reads a FILE, never a pipe. Under pipefail a
# `producer | grep -q` reports 141 when grep exits on its first match and the
# producer takes SIGPIPE, so the `if` takes the ELSE branch ON A MATCH — the
# defect this repo has hit repeatedly (#6588, #6178).

# ── CONTROL: the unmutated body must be GREEN before any mutant is read ──────
# A battery whose control is red scores every mutant against a broken baseline
# and each row's verdict is arbitrary. This runs FIRST and aborts on failure.
_c0=$fails
expect_line "CONTROL all-green" "$BODY" success success success push \
  "All three shards green." 0
if [ "$fails" -ne "$_c0" ]; then
  printf '\nCONTROL ROW FAILED — the battery is VOID, not failing. The unmutated\n' >&2
  printf 'aggregator body does not emit its own success line, so every mutation\n' >&2
  printf 'verdict below would be measured against a broken baseline.\n' >&2
  printf 'rows=%d passed=%d failed=%d\n' "$((passes + fails))" "$passes" "$fails" >&2
  exit 1
fi

# ── Classification rows (the B.2 contract) ───────────────────────────────────
# One row per disjunct, ALONE. A fixture satisfying several arms at once proves
# the set is non-empty and nothing else: dropping either arm keeps it green.

# A failing leg names itself, whatever its siblings did.
expect_line "R1 failure/any" "$BODY" failure success success push \
  "FAILED" 1
expect_line "R1b failure names the leg" "$BODY" success success failure push \
  "test-scripts: FAILED" 1
# R1c/R1d — THE FAILURE ARM MUST NOT ASSERT A MECHANISM IT DID NOT MEASURE.
# `failure` is GitHub's conclusion for an assertion failure AND a
# timeout-minutes kill AND a lost runner AND an OOM. The arm used to read
# "assertions failed", a guessed cause — the same defect this whole step exists
# to remove, one arm over from where it was removed. The bare needle "FAILED"
# above cannot see that: it survives every rewrite of the sentence, which is why
# rewriting the arm left this suite green (cq-assert-anchor-not-bare-token).
run_body "$BODY" failure success success push
if grep -qiE 'assertions? failed' "$OUT"; then
  fail "R1c the failure arm asserts 'assertions failed' — a cause this job did NOT measure; a timeout-minutes kill also concludes failure (AP-021)"
else pass; fi
if grep -qF -- "timeout-minutes" "$OUT"; then pass; else
  fail "R1d the failure arm does not name the timeout ambiguity, so the reader is left with the same undiscriminated verdict #7902 had to reconstruct from the API"
fi
# R1e — test-scripts is a 3-leg MATRIX rollup, so "the job log" is not one log.
run_body "$BODY" success success failure push
if grep -qF -- "matrix" "$OUT"; then pass; else
  fail "R1e the test-scripts failure message points at a single job log, but test-scripts is a matrix rollup — that log does not exist"
fi

# Two legs cancelled on a pull_request run: the run was superseded.
expect_line "R2 cancelled+sibling-cancelled on pull_request" "$BODY" \
  cancelled cancelled success pull_request "SUPERSEDED" 1

# One leg cancelled while both siblings CONCLUDED: it was stopped alone, and
# the usual cause is its own declared timeout-minutes. This is the arm #7902
# had to reconstruct from the API.
expect_line "R3 cancelled alone, siblings concluded (success)" "$BODY" \
  success success cancelled push "STOPPED ALONE" 1
expect_line "R3b cancelled alone, a sibling FAILED (still concluded)" "$BODY" \
  failure success cancelled push "STOPPED ALONE" 1

# Cancelled with a sibling neither cancelled nor concluded (skipped): the shape
# does not determine the cause, and the honest answer is to say so. A confident
# third mechanism is exactly what ci.yml's dispatch note has already retracted
# twice on the adjacent question.
expect_line "R4 cancelled, sibling skipped -> honest UNKNOWN" "$BODY" \
  skipped success cancelled push "cause not determined" 1

# A skipped leg did not run.
expect_line "R5 skipped/any" "$BODY" success skipped success push \
  "SKIPPED" 1

# ── Row 24b — SUPERSEDED must be UNREACHABLE on a push event ─────────────────
# After #7931 part 1 every `main` push has its OWN concurrency group and
# cancel-in-progress stays pull_request-only, so nothing on `main` is cancelled
# by supersession. A confident SUPERSEDED there names the one cause that has
# become impossible — part 1 reintroducing into part 2 the exact error class
# ci.yml's own twice-retracted dispatch note exists to prevent.
run_body "$BODY" cancelled cancelled success push
if grep -qF -- "SUPERSEDED" "$OUT"; then
  fail "24b PUSH-EVENT SUPERSEDED: the classifier emitted SUPERSEDED on a push event, where per-SHA concurrency makes supersession structurally impossible. Output: $(tr '\n' '|' <"$OUT" | head -c 300)"
else
  pass
fi
# ...and it must still say SOMETHING, not fall silently through.
if grep -qE 'CANCELLED|cause not determined' "$OUT"; then pass; else
  fail "24b PUSH-EVENT SUPERSEDED: no classification line at all for a two-leg cancellation on push"
fi

# ── Row 25 — every failing leg is named, not just the first ──────────────────
# Second-member row: a loop that `break`s after the first non-success leg names
# one of two failures, and the operator fixes half the problem.
run_body "$BODY" failure success cancelled push
_named=0
grep -qF -- "test-webplat" "$OUT" && _named=$((_named + 1))
grep -qF -- "test-scripts" "$OUT" && _named=$((_named + 1))
if [ "$_named" -eq 2 ]; then pass; else
  fail "25 SECOND MEMBER: two legs are non-success but only $_named of 2 were named — the loop stops early. Output: $(tr '\n' '|' <"$OUT" | head -c 300)"
fi

# ── Row 24 — never swallow a failure ─────────────────────────────────────────
# The branch is additive: classification is a diagnostic, and every non-success
# leg must still exit non-zero. Swallowing is the failure mode with independent
# value, so it is asserted over EVERY non-success result value, not one sample.
for _r in failure cancelled skipped; do
  run_body "$BODY" "$_r" success success push
  if [ "$RC" -ne 0 ]; then pass; else
    fail "24 SWALLOWED: a leg with result='$_r' exited 0 — the required check would report green on a non-success shard"
  fi
done

# ── Harness row (b) — must-PASS negative control ─────────────────────────────
# An all-success run emits the success line and exits 0. Asserted above as the
# CONTROL; repeated here across the other event name so the event gate cannot
# be implemented as "always fail on pull_request".
expect_line "Hb must-PASS all-green on pull_request" "$BODY" success success success pull_request \
  "All three shards green." 0

# ── MUTATION BATTERY ─────────────────────────────────────────────────────────
# Each row mutates a COPY of the extracted body, asserts the mutation LANDED
# (a mutation that does not land reports the BASELINE, which is
# indistinguishable from a pass), re-runs the relevant expectation, and
# requires it to FAIL. A surviving mutant is a RESULT with two readings —
# fixture-inadequate or equivalent — and each is labelled below.
MUT_TOTAL=0; MUT_KILLED=0; MUT_SURVIVED=()

mutate() {  # $1=label $2=sed-expr $3..: probe args (results, event, needle, rc)
  local label="$1" expr="$2"; shift 2
  local m="$SANDBOX/mut.$RANDOM"
  MUT_TOTAL=$((MUT_TOTAL + 1))
  sed "$expr" "$SANDBOX/body.pristine" > "$m"
  if cmp -s "$m" "$SANDBOX/body.pristine"; then
    fail "MUTATION DID NOT LAND: $label — sed expression matched nothing, so this row measured the BASELINE"
    return
  fi
  # Re-run the probe against the mutant; it must now FAIL.
  local _f=$fails
  expect_line "  (mutant probe) $label" "$m" "$@" >/dev/null 2>&1
  if [ "$fails" -gt "$_f" ]; then
    # The probe failed as required. Retract its failure — the mutant being
    # caught is a PASS for the battery, not a failure of the suite.
    fails=$((fails - 1)); unset 'FAILURES[${#FAILURES[@]}-1]'
    pass; MUT_KILLED=$((MUT_KILLED + 1))
  else
    fail "MUTANT SURVIVED: $label — the guard did not detect this edit"
    MUT_SURVIVED+=("$label")
  fi
}

# 22 — remove the STOPPED ALONE branch.
mutate "22 remove the STOPPED ALONE branch" 's/STOPPED ALONE[^"]*/REDACTED/' \
  success success cancelled push "STOPPED ALONE" 1
# 23 — remove the honest UNKNOWN fallback.
mutate "23 remove the UNKNOWN fallback" 's/cause not determined/xx/' \
  skipped success cancelled push "cause not determined" 1
# 24 — stop setting fail=1 for a non-success leg.
mutate "24 non-success leg stops setting fail=1" 's/^\([[:space:]]*\)fail=1/\1: fail=1/' \
  failure success success push "FAILED" 1
# 25 — break after the first failing leg. The probe MUST use a triple with TWO
# non-success legs and assert on the SECOND: with only one failing leg a `break`
# changes nothing observable, so a single-failure probe would report this mutant
# as surviving and the row would prove nothing about early exit.
mutate "25 loop breaks after the first failing leg" 's/^\([[:space:]]*\)fail=1/\1fail=1; break/' \
  failure success failure push "test-scripts: FAILED" 1

# Harness row (a): delete the battery's own exit-code assertion and confirm the
# suite would go green on a swallowing body — i.e. the rc arm is load-bearing.
# Implemented as a POSITIVE control on the probe itself rather than a comment.
_swallow="$SANDBOX/mut.swallow"
sed 's/^\([[:space:]]*\)fail=1/\1: fail=1/' "$SANDBOX/body.pristine" > "$_swallow"
run_body "$_swallow" failure success success push
if [ "$RC" -eq 0 ]; then pass; else
  fail "Ha HARNESS: the swallowing mutant did not actually exit 0 (rc=$RC), so row 24's kill proves nothing about the rc assertion"
fi

# ── E1-E3: EVERY event ci.yml declares, not the two that were fixtured ──────
# SUPERSEDED is gated on the event because supersession requires
# cancel-in-progress, which since #7931 part 1 is pull_request-only. That is
# equally true on merge_group and workflow_dispatch — but only push was
# fixtured, so `== "pull_request"` and `!= "push"` were indistinguishable to
# this suite, and the second silently claims SUPERSEDED on two more events.
for _ev in merge_group workflow_dispatch; do
  run_body "$BODY" cancelled cancelled success "$_ev"
  if grep -qF -- "SUPERSEDED" "$OUT"; then
    fail "E1 the classifier claims SUPERSEDED on a '$_ev' run. cancel-in-progress is pull_request-only, so nothing could have superseded it — this is a guessed cause on an event the fixtures never instantiated (AP-021)"
  else pass; fi
done
# E3 — the catch-all arm must exist AND say something. A result value outside
# {success,failure,cancelled,skipped} must not vanish silently; GitHub has added
# conclusion values before.
run_body "$BODY" neutral success success push
if [ -s "$OUT" ] && [ "$RC" -eq 1 ]; then pass; else
  fail "E3 an out-of-enum leg result ('neutral') produced rc=$RC and output '$(tr '\n' '|' <"$OUT" | head -c 120)'. A result the case does not enumerate must still fail the job and say so — otherwise a new GitHub conclusion value passes CI silently"
fi

# ── W1-W4: the STEP's wiring, which no row asserted ─────────────────────────
# Every row above executes the extracted `run:` body against env vars the HARNESS
# supplies. That proves the classifier is right and says NOTHING about whether
# the workflow feeds it the right values, or whether the `test` job still watches
# all three shards. Both are one-line edits with no local symptom.
_ciy="$REPO_ROOT/.github/workflows/ci.yml"
_wiring=$(python3 - "$_ciy" <<'PYW'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
job = d["jobs"]["test"]
needs = job.get("needs") or []
needs = [needs] if isinstance(needs, str) else list(needs)
step = None
for st in job.get("steps") or []:
    if st.get("name") == "Aggregate shard results":
        step = st
        break
if step is None:
    print("NOSTEP"); raise SystemExit
env = step.get("env") or {}
want = {"WEBPLAT_RESULT": "test-webplat", "BUN_RESULT": "test-bun", "SCRIPTS_RESULT": "test-scripts"}
bad = []
for var, shard in want.items():
    v = str(env.get(var, ""))
    if ("needs.%s.result" % shard) not in v:
        bad.append("%s should read needs.%s.result, reads %r" % (var, shard, v))
    if shard not in needs:
        bad.append("the test job does not need %s, so %s resolves to empty" % (shard, var))
print("; ".join(bad))
PYW
)
if [ "$_wiring" = "NOSTEP" ]; then
  fail "W1 the 'Aggregate shard results' step is gone from ci.yml's test job — every row in this suite executes a body that no longer runs"
elif [ -z "$_wiring" ]; then
  pass
else
  fail "W1 the aggregator's env: -> needs.* wiring is wrong: $_wiring. The classifier rows above cannot see this — they are handed the three values directly"
fi
# W2 — the shard set the harness fixtures must equal the shard set the job wires.
_nshards=$(python3 - "$_ciy" <<'PYN'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
n = d["jobs"]["test"].get("needs") or []
n = [n] if isinstance(n, str) else list(n)
print(len([x for x in n if x.startswith("test-")]))
PYN
)
if [ "$_nshards" -eq 3 ]; then pass; else
  fail "W2 the test job watches $_nshards test-* shards, but this suite fixtures exactly 3 — dropping a shard from needs: makes its result resolve to EMPTY, which falls straight into the *) arm, and every row here would still pass"
fi

# ── Verdict ──────────────────────────────────────────────────────────────────
TOTAL=$((passes + fails))

# ASSERTION FLOOR, reported with printf + exit rather than through the helpers
# it backstops (ADR-193). A floor dispatched through pass()/fail() is silenced
# by the same edit that silences everything else.
# DERIVED FROM THE ROWS BELOW, NOT GUESSED. A floor set above the real count is
# a broken instrument that reds a correct tree; a floor set below it is slack an
# undispatched row can hide in. Itemised so the next author can re-derive it
# after adding a row:
#   1 instrument self-test + 1 control + 7 classification (R1,R1b,R2,R3,R3b,R4,R5)
# + 3 failure-arm honesty (R1c no guessed mechanism, R1d names the ambiguity,
#   R1e matrix rollup is not one log)
# + 2 event-gate (24b absent-SUPERSEDED, 24b says-something)
# + 1 second-member (25) + 3 swallow (24, one per non-success result value)
# + 1 must-PASS (Hb) + 4 mutants + 1 harness (Ha)
# + 2 wiring (W1 env->needs mapping, W2 shard cardinality)
# + 3 event/value cardinality (E1 merge_group, E1 workflow_dispatch,
#   E3 out-of-enum result) = 29
MIN_ROWS=29
if [ "$TOTAL" -lt "$MIN_ROWS" ]; then
  printf 'FAIL: assertion floor — %d rows executed, at least %d required. Rows were removed or a loop stopped early.\n' \
    "$TOTAL" "$MIN_ROWS" >&2
  exit 1
fi
MIN_MUTANTS=4
if [ "$MUT_TOTAL" -lt "$MIN_MUTANTS" ]; then
  printf 'FAIL: mutation floor — %d mutants executed, at least %d required.\n' \
    "$MUT_TOTAL" "$MIN_MUTANTS" >&2
  exit 1
fi

echo
echo "mutation battery: $MUT_KILLED/$MUT_TOTAL killed"
if [ "${#MUT_SURVIVED[@]}" -gt 0 ]; then
  printf 'surviving mutants (fixture-inadequate or equivalent — label which):\n' >&2
  printf '  - %s\n' "${MUT_SURVIVED[@]}" >&2
fi
echo "ci-test-aggregator-diagnosis.test.sh: $TOTAL rows, $passes passed, $fails failed"
if [ "${#FAILURES[@]}" -gt 0 ]; then
  printf '\nfailures:\n' >&2
  printf '  - %s\n' "${FAILURES[@]}" >&2
  exit 1
fi
exit 0
