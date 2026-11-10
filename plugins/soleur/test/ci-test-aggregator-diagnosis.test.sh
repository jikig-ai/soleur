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
# PROBE MODE. While a MUTANT is being driven (PROBE=1) the helper verdicts are about the mutant, not about the tree: a probe
# verdict counts into PROBE_PASSES / PROBE_FAILS and touches NEITHER `passes`/`fails` NOR the FAILURES ledger, so the row floor
# counts only rows that ran against the real body (an earlier revision let ~150 probe passes leak into `passes`, inflating the
# floor). A mutant is KILLED when PROBE_FAILS > 0. PROBE is asserted back at 0 before the verdict.
PROBE=0; PROBE_PASSES=0; PROBE_FAILS=0
pass() { if [ "$PROBE" = 1 ]; then PROBE_PASSES=$((PROBE_PASSES + 1)); else passes=$((passes + 1)); fi; }
fail() {
  if [ "$PROBE" = 1 ]; then PROBE_FAILS=$((PROBE_FAILS + 1)); return 0; fi
  fails=$((fails + 1)); FAILURES+=("$1"); printf 'FAIL: %s\n' "$1" >&2
}

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
# $6 is the 4th leg (web-platform-build, #8136), $7 the 5th (test-scripts-heavy, #8006)
# and $8 the 6th (encryption-posture, #6907). All three default to success so the
# three-shard rows keep stating their FULL triple while the build, heavy and posture
# rows below name their own values explicitly.
run_body() {  # $1=body $2=webplat $3=bun $4=scripts $5=event [$6=build] [$7=scripts-heavy] [$8=posture] [$9=draft-light output] [$10-$12 RETIRED env spellings, fed nowhere now] [$13=ATTEMPT] [$14=ORACLE_INDEX_RESULT] [$15=ORACLE_SKIP_LEGS] [$16=ORACLE_ACTIVE] [$17=ORACLE_HEAD_OK] ; sets OUT/RC
  OUT="$SANDBOX/out.$RANDOM.$RANDOM"
  ( WEBPLAT_RESULT="$2" BUN_RESULT="$3" SCRIPTS_RESULT="$4" EVENT_NAME="$5" \
      BUILD_RESULT="${6:-success}" SCRIPTS_HEAVY_RESULT="${7:-success}" POSTURE_RESULT="${8:-success}" \
      DRAFT_LIGHT="${9:-}" \
      ATTEMPT="${13-1}" \
      ORACLE_INDEX_RESULT="${14:-success}" ORACLE_SKIP_LEGS="${15:-}" ORACLE_ACTIVE="${16:-}" ORACLE_HEAD_OK="${17:-}" \
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
  "All legs green (six battery legs + oracle-index-check)." 0
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
# R1e — test-scripts is a MATRIX rollup, so "the job log" is not one log.
run_body "$BODY" success success failure push
if grep -qF -- "matrix" "$OUT"; then pass; else
  fail "R1e the test-scripts failure message points at a single job log, but test-scripts is a matrix rollup — that log does not exist"
fi

# R1f/R1g — the 4th leg (web-platform-build, #8136): red ALONE fails the job and
# names itself; skipped ALONE (GitHub reports a needs-dependency that never ran
# as `skipped`) is NOT success — the fail-open the aggregator's header forbids.
run_body "$BODY" success success success push failure
if [ "$RC" -eq 1 ] && grep -qF -- "web-platform-build: FAILED" "$OUT"; then pass; else
  fail "R1f a red web-platform-build with every shard green must fail the aggregator and name the leg (rc=$RC): $(tr '\n' '|' <"$OUT" | head -c 200)"
fi
run_body "$BODY" success success success push skipped
if [ "$RC" -eq 1 ] && grep -qF -- "web-platform-build: SKIPPED" "$OUT"; then pass; else
  fail "R1g a skipped web-platform-build reads as success — the fail-open the header forbids (rc=$RC)"
fi

# R1h/R1i/R1j — the 5th leg (test-scripts-heavy): same contract as the other matrix job.
# Red ALONE fails and names itself; skipped ALONE is not success; and the failure arm must
# use MATRIX wording for it too — `== "test-scripts"` alone would emit the single-log
# pointer R1e forbids, on the job where it is equally untrue.
run_body "$BODY" success success success push success failure
if [ "$RC" -eq 1 ] && grep -qF -- "test-scripts-heavy: FAILED" "$OUT"; then pass; else
  fail "R1h a red test-scripts-heavy with every other leg green must fail the aggregator and name the leg (rc=$RC): $(tr '\n' '|' <"$OUT" | head -c 200)"
fi
run_body "$BODY" success success success push success skipped
if [ "$RC" -eq 1 ] && grep -qF -- "test-scripts-heavy: SKIPPED" "$OUT"; then pass; else
  fail "R1i a skipped test-scripts-heavy reads as success — the same fail-open R1g pins on the build leg (rc=$RC)"
fi
# R1j re-runs the FAILURE fixture: reading $OUT here without this call asserts the
# matrix needle against R1i's SKIPPED output — a stale-file read that fails for the
# wrong reason no matter what the failure arm says.
run_body "$BODY" success success success push success failure
if grep -qF -- "matrix" "$OUT"; then pass; else
  fail "R1j the test-scripts-heavy failure message does not say 'matrix' — the failure arm special-cases only test-scripts, but this job is a matrix rollup too (rc=$RC): $(tr '\n' '|' <"$OUT" | head -c 200)"
fi

# R1k — oracle-index-check is a K=5 matrix rollup too (#12393): its failure arm must use the
# matrix wording, not the single-log pointer.
run_body "$BODY" success success success push success success success true "" true true 1 failure
if grep -qF -- "oracle-index-check: FAILED" "$OUT" && grep -qF -- "matrix" "$OUT"; then pass; else
  fail "R1k the oracle-index-check failure message does not say 'matrix' — the failure arm must special-case this job too (rc=$RC): $(tr '\n' '|' <"$OUT" | head -c 200)"
fi

# R1k/R1l — the 6th leg (encryption-posture, #6907). Before #6907 it was a
# standalone ADVISORY job: a PR could merge with the ledger sweep red. Joining
# the aggregator is what arms it, so red ALONE must fail `test` and name the
# leg, and skipped ALONE must not read as success.
run_body "$BODY" success success success push success success failure
if [ "$RC" -eq 1 ] && grep -qF -- "encryption-posture: FAILED" "$OUT"; then pass; else
  fail "R1k a red encryption-posture with every other leg green must fail the aggregator and name the leg (rc=$RC): $(tr '\n' '|' <"$OUT" | head -c 200)"
fi
run_body "$BODY" success success success push success success skipped
if [ "$RC" -eq 1 ] && grep -qF -- "encryption-posture: SKIPPED" "$OUT"; then pass; else
  fail "R1l a skipped encryption-posture reads as success — the gate #6907 arms would be a no-op whenever the job does not run (rc=$RC)"
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
  "All legs green (six battery legs + oracle-index-check)." 0

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
  # Re-run the probe against the mutant (PROBE mode: nothing reaches the counters or the ledger); it must now FAIL.
  PROBE=1; PROBE_FAILS=0
  expect_line "  (mutant probe) $label" "$m" "$@" >/dev/null 2>&1
  PROBE=0
  if [ "$PROBE_FAILS" -gt 0 ]; then
    # The probe failed as required: the mutant being caught is a PASS for the battery, not a failure of the suite.
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

# ── D1-D9: the draft arm (ADR-276 S3, #9728, Option R) ───────────────────────
# On a `pull_request` run whose `draft-light` output is exactly `true`, the heavy legs are skipped and the aggregator must
# conclude RED with `draft: full battery owed at ready`. The loop above already fails a skipped leg; the ARM is a second,
# independent chokepoint so a later edit that makes the loop tolerate skipped legs cannot turn a light draft green.
# It must not fire on merge_group, push or workflow_dispatch, and it must not fire for any value other than `true`.
DRAFT_MSG="draft: full battery owed at ready"
draft_must() {  # $1=label $2=body $3=event $4=draft-light $5=want_rc $6=want_msg(0|1) $7..$9=webplat bun scripts [$10=heavy]
  local label="$1" body="$2" ev="$3" dl="$4" wrc="$5" wmsg="$6" w="${7:-success}" b="${8:-success}" s="${9:-success}" h="${10:-success}"
  run_body "$body" "$w" "$b" "$s" "$ev" success "$h" success "$dl"
  local ok=1
  [ "$RC" -eq "$wrc" ] || ok=0
  if grep -qF -- "$DRAFT_MSG" "$OUT"; then [ "$wmsg" -eq 1 ] || ok=0; else [ "$wmsg" -eq 0 ] || ok=0; fi
  if [ "$ok" -eq 1 ]; then pass; return 0; fi
  fail "$label — event=$ev draft-light='$dl' legs=($w,$b,$s,$h): want rc=$wrc msg=$wmsg; got rc=$RC, output: $(tr '\n' '|' <"$OUT" | head -c 300)"
  return 1
}
# D1 a light draft (heavy legs skipped): red, names the draft message AND still names the skipped legs
draft_must "D1 light draft, heavy legs skipped" "$BODY" pull_request true 1 1 skipped success skipped skipped
if grep -qF -- "test-webplat: SKIPPED" "$OUT" && grep -qF -- "test-scripts-heavy: SKIPPED" "$OUT"; then pass; else
  fail "D1b the per-leg SKIPPED lines are gone from a light draft's output: $(tr '\n' '|' <"$OUT" | head -c 300)"
fi
# D2 the arm is unconditional on the legs: a light draft with every leg success is still red
draft_must "D2 light draft, every leg success" "$BODY" pull_request true 1 1
# D3/D4 other events are untouched: a skipped leg still fails (the loop), the draft message never prints; all-green passes
for _ev in merge_group push workflow_dispatch; do
  draft_must "D3 $_ev with light=true and a skipped leg" "$BODY" "$_ev" true 1 0 success success skipped
  draft_must "D4 $_ev with light=true and every leg success" "$BODY" "$_ev" true 0 0
done
# D5 only the exact string `true` arms it
for _v in "" false FALSE True TRUE 1 yes " true" "true "; do
  draft_must "D5 pull_request with draft-light='$_v' and every leg success" "$BODY" pull_request "$_v" 0 0
done
draft_must "D5b pull_request not light, skipped leg" "$BODY" pull_request "" 1 0 success success skipped
# D6 the arm is independent of the loop: with the loop made to TOLERATE skipped legs a light draft is still red
_tol="$SANDBOX/mut.tolerant"
sed 's/^\([[:space:]]*\)fail=1/\1: fail=1/' "$SANDBOX/body.pristine" > "$_tol"
draft_must "D6 light draft, tolerant loop" "$_tol" pull_request true 1 1 skipped success skipped skipped
# ...and the tolerant loop really tolerates (merge_group, skipped leg -> exit 0), so D6 is not vacuous
draft_must "D6b tolerant loop control (merge_group, skipped leg)" "$_tol" merge_group true 0 0 success success skipped

# D7 mutants of the ARM itself: each must be caught by the rows above. The mutator is a named-operation helper, so no
# quoting of a code snippet is ever passed through the shell.
cat > "$SANDBOX/armmut.py" <<'PYM'
import re, sys
src, dst, op = sys.argv[1:4]
s = open(src).read()
ARM = re.compile(r'(?ms)^[ \t]*if \[\[ "\$EVENT_NAME" == "pull_request" && "\$DRAFT_LIGHT" == "true" \]\]; then.*?^[ \t]*fi\n')
m = ARM.search(s)
if not m:
    sys.stderr.write("arm not found\n"); sys.exit(3)
arm = m.group(0)
if op == "remove":
    s = s.replace(arm, "", 1)
elif op == "exit0":
    s = s.replace(arm, arm.replace("exit 1", "exit 0"), 1)
elif op == "anyevent":
    s = s.replace(arm, arm.replace('"$EVENT_NAME" == "pull_request" && ', "", 1), 1)
elif op == "nonempty":
    s = s.replace(arm, arm.replace('"$DRAFT_LIGHT" == "true"', '-n "$DRAFT_LIGHT"', 1), 1)
elif op == "stdout":
    s = s.replace(arm, arm.replace(">&2", "", 1), 1)
elif op == "after-final":
    s = s.replace(arm, "", 1)
    k = s.rfind('echo "All legs green (six battery')
    s = s[:k] + arm + s[k:]
else:
    sys.stderr.write("unknown op\n"); sys.exit(2)
open(dst, "w").write(s)
PYM
mutate_arm() {  # $1=label $2=op ; probe: D1/D2/D3/D5/D6 over the mutant
  local label="$1" op="$2" m="$SANDBOX/mut.arm.$RANDOM"
  MUT_TOTAL=$((MUT_TOTAL + 1))
  if ! python3 "$SANDBOX/armmut.py" "$SANDBOX/body.pristine" "$m" "$op" 2>"$SANDBOX/armmut.err"; then
    fail "MUTATION DID NOT LAND: $label ($(head -c 120 "$SANDBOX/armmut.err"))"; return
  fi
  if cmp -s "$m" "$SANDBOX/body.pristine"; then
    fail "MUTATION DID NOT LAND: $label — the mutant is byte-identical, so this row measured the BASELINE"; return
  fi
  PROBE=1; PROBE_FAILS=0
  draft_must "(mutant probe) $label D1" "$m" pull_request true 1 1 skipped success skipped skipped >/dev/null 2>&1
  draft_must "(mutant probe) $label D2" "$m" pull_request true 1 1 >/dev/null 2>&1
  draft_must "(mutant probe) $label D3" "$m" merge_group true 1 0 success success skipped >/dev/null 2>&1
  draft_must "(mutant probe) $label D5" "$m" pull_request false 0 0 >/dev/null 2>&1
  PROBE=0
  if [ "$PROBE_FAILS" -gt 0 ]; then
    # the mutant being caught is a PASS for the battery
    pass; MUT_KILLED=$((MUT_KILLED + 1))
  else
    fail "MUTANT SURVIVED: $label — the draft arm's rows did not detect this edit"
    MUT_SURVIVED+=("$label")
  fi
}
mutate_arm "D7 remove the draft arm" remove
mutate_arm "D7b the arm exits 0" exit0
mutate_arm "D7c the arm fires on every event" anyevent
mutate_arm "D7d the arm fires on any non-empty value" nonempty
mutate_arm "D7e the arm moves AFTER the final check (unreachable for a light draft)" after-final
# D8 the arm sits AFTER the loop and BEFORE the final check, once (structure, not behaviour)
_armpos=$(python3 - "$SANDBOX/body.pristine" <<'PYS'
import sys
s = open(sys.argv[1]).read()
final = s.find("if [[ $fail -ne 0 ]]")
arm = s.find('"$DRAFT_LIGHT" == "true"')
done = s.rfind("\ndone", 0, final if final >= 0 else len(s))
print("ok" if 0 <= done < arm < final and s.count('"$DRAFT_LIGHT" == "true"') == 1 else "bad done=%d arm=%d final=%d" % (done, arm, final))
PYS
)
if [ "$_armpos" = ok ]; then pass; else fail "D8 the draft arm must sit after the loop and before the final fail check, exactly once ($_armpos)"; fi

# ── Guard 1 (S4 retirement, 2026-11-09): NO PR-affected skip tolerance may exist ──────────────────────────
# PROPERTY: a `skipped` leg is ALWAYS red. The retired arm's SKIP_LEGS/ACTIVE/HEAD_SHA_OK inputs are gone from
# the workflow, so the harness feeds the retired env spellings and they can never reach the body — every shape
# that used to satisfy the tolerance now fails the run with the plain SKIPPED line. The ONLY named tolerance
# left is ORACLE-ONLY-SKIP (Guard 2). These rows re-assert the post-removal grammar; a re-introduced arm is a
# mutation, not a green.
S=skipped; OK=success
SIX_LINE="All legs green (six battery legs + oracle-index-check)."
TOL_MSG="PR-AFFECTED-SKIP"
OREM_TXT='the oracle-lane skip decision is cached from attempt 1; use "Re-run all jobs" (or push) to get a full run'
REM_TXT="$OREM_TXT"
for _ev in pull_request merge_group push workflow_dispatch; do
  run_body "$BODY" $S $OK $OK "$_ev" $OK $OK $OK "" "test-webplat,test-bun,test-scripts-heavy" "true" "true" 1
  if [ "$RC" -eq 1 ] && grep -qF -- "test-webplat: SKIPPED — the leg did not run" "$OUT" && ! grep -qF -- "$TOL_MSG" "$OUT"; then pass
  else fail "R1-1 $_ev a skipped leg is never tolerated post-removal (rc=$RC): $(tr '\n' '|' <"$OUT" | head -c 200)"; fi
  run_body "$BODY" $OK $OK $OK "$_ev" $OK $OK $OK "" "test-bun" "true" "true" 1
  if [ "$RC" -eq 0 ] && grep -qxF -- "$SIX_LINE" "$OUT" && ! grep -qF -- "pr-affected" "$OUT"; then pass
  else fail "R1-2 $_ev an all-green run is the exact six-leg line, no tolerated clause (rc=$RC)"; fi
done
unset _ev
# stale skip-decision inputs fed on a re-run can arm nothing: the remedy reads ORACLE_SKIP_LEGS only
run_body "$BODY" $OK $OK $OK pull_request $OK $S $OK "" "test-scripts-heavy,test-webplat" "true" "true" 2
if [ "$RC" -eq 1 ] && grep -qF -- "test-scripts-heavy: SKIPPED — the leg did not run" "$OUT" && ! grep -qF -- "cached from attempt 1" "$OUT"; then pass
else fail "R1-3 stale skip inputs on attempt 2 can arm neither tolerance nor remedy (rc=$RC)"; fi
# a listed-but-failed leg was never tolerated and still is not (the tolerance keyed on `skipped` only)
run_body "$BODY" $OK failure $OK pull_request $OK $OK $OK "" "test-bun" "true" "true" 1
if [ "$RC" -eq 1 ] && grep -qF -- "test-bun: FAILED" "$OUT" && ! grep -qF -- "$TOL_MSG" "$OUT"; then pass
else fail "R1-4 a listed-but-failed leg is red, never tolerated (rc=$RC)"; fi
# Option R is unchanged: a skipped leg on a light draft is red (the draft arm prints its own diagnosis)
run_body "$BODY" success skipped success pull_request success success success true "test-bun" "true" "true" 1
if [ "$RC" -eq 1 ] && grep -qF -- "$DRAFT_MSG" "$OUT"; then pass
else fail "R1-5 a skipped leg on a light draft is red with the draft diagnosis (rc=$RC): $(tr '\n' '|' <"$OUT" | head -c 200)"; fi
# ── Guard 2 (#12156, ADR-276 oracle-only lane): the ORACLE-ONLY-SKIP tolerance ─────────────────────
# PROPERTY: a `skipped` leg turns the aggregator green ONLY on a pull_request OR merge_group run
# with ORACLE_ACTIVE exactly `true`, the head bound (ORACLE_HEAD_OK == `true`), attempt 1, a
# well-formed ORACLE_SKIP_LEGS over the FIVE lane legs (test-webplat, test-bun, test-scripts,
# test-scripts-heavy, web-platform-build), and the leg named in it by a delimited match. Every other
# skip reds it; encryption-posture, e2e, shard-totality-mutations and oracle-index-check can never
# be tolerated — oracle-index-check is the lane's own validation leg, always-required success.
# CONTRACT NOTE: the oracle env names pinned here are ORACLE_SKIP_LEGS / ORACLE_ACTIVE /
# ORACLE_HEAD_OK / ORACLE_INDEX_RESULT (the plan's named terms); ATTEMPT is shared with the PR arm.
OTOL_MSG="ORACLE-ONLY-SKIP"
ALL5="test-webplat,test-bun,test-scripts,test-scripts-heavy,web-platform-build"
otol() {  # $1=label $2=body $3=event $4=oracle_skip_legs $5=oracle_active $6=oracle_head_ok $7=attempt $8=index $9=webplat ${10}=bun ${11}=scripts ${12}=heavy ${13}=build ${14}=posture ${15}=want_rc ${16}=needle ${17}=forbid
  local label="$1" body="$2" ev="$3" osk="$4" oac="$5" oho="$6" at="$7" ix="$8" w="$9" s10="${10}" s11="${11}" h="${12}" bd="${13}" po="${14}" wrc="${15}" need="${16:-}" forbid="${17:-}"
  run_body "$body" "$w" "$s10" "$s11" "$ev" "$bd" "$h" "$po" "" "" "" "" "$at" "$ix" "$osk" "$oac" "$oho"
  local ok=1
  [ "$RC" -eq "$wrc" ] || ok=0
  if [ -n "$need" ]; then grep -qF -- "$need" "$OUT" || ok=0; fi
  if [ -n "$forbid" ]; then if grep -qF -- "$forbid" "$OUT"; then ok=0; fi; fi
  if [ "$ok" -eq 1 ]; then pass; return 0; fi
  fail "$label — event=$ev oracle_skip_legs='$osk' active='$oac' head_ok='$oho' attempt='$at' index='$ix' legs=($w,$s10,$s11,$h,$bd,$po): want rc=$wrc need='$need' forbid='$forbid'; got rc=$RC, output: $(tr '\n' '|' <"$OUT" | head -c 300)"
  return 1
}
# must-PASS (Guard 2 row 7): one listed skip on an active, head-bound, attempt-1 run — both lane events
otol "O2-0 must-PASS: one listed skip on pull_request" "$BODY" pull_request test-bun true true 1 $OK $OK $S $OK $OK $OK $OK 0 "test-bun: $OTOL_MSG" "test-bun: SKIPPED"
otol "O2-0b must-PASS: two-leg skip on merge_group" "$BODY" merge_group "test-webplat,test-bun" true true 1 $OK $S $S $OK $OK $OK $OK 0 "test-bun: $OTOL_MSG" "test-webplat: SKIPPED"
otol "O2-0c must-PASS: all five listed and skipped on merge_group" "$BODY" merge_group "$ALL5" true true 1 $OK $S $S $S $S $S $OK 0 "$OTOL_MSG" "SKIPPED —"
otol "O2-0d must-PASS: a leg listed but ran" "$BODY" merge_group test-bun true true 1 $OK $OK $OK $OK $OK $OK $OK 0 "" "$OTOL_MSG"
# Guard 2 row 1: a skipped leg with ORACLE inputs EMPTY (the oracle-selection job was skipped/var unset)
for _ev in pull_request merge_group; do
  otol "O2-1 $_ev leg skipped, oracle outputs empty" "$BODY" "$_ev" "" "" "" 1 $OK $S $OK $OK $OK $OK $OK 1 "test-webplat: SKIPPED — the leg did not run" "$OTOL_MSG"
done
# Guard 2 row 2: a leg outside the five-name allowlist is never tolerated — encryption-posture, e2e's
# siblings, shard-totality-mutations AND oracle-index-check, listed or not.
otol "O2-2 encryption-posture skipped and listed" "$BODY" merge_group "encryption-posture" true true 1 $OK $OK $OK $OK $OK $OK $S 1 "encryption-posture: SKIPPED" "$OTOL_MSG"
otol "O2-2b shard-totality-mutations named in the list" "$BODY" merge_group "test-bun,shard-totality-mutations" true true 1 $OK $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" "$OTOL_MSG"
otol "O2-2c oracle-index-check named in the list" "$BODY" merge_group "test-bun,oracle-index-check" true true 1 $OK $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" "$OTOL_MSG"
# Guard 2 row 6 (harness): oracle-index-check skipped while the heavy legs are tolerated — RED.
otol "O2-6 oracle-index-check skipped under a valid five-leg list" "$BODY" merge_group "$ALL5" true true 1 $S $S $S $S $S $S $OK 1 "oracle-index-check: SKIPPED" "oracle-index-check: $OTOL_MSG"
otol "O2-6b oracle-index-check skipped, heavy legs green" "$BODY" pull_request "$ALL5" true true 1 $S $OK $OK $OK $OK $OK $OK 1 "oracle-index-check: SKIPPED" "$OTOL_MSG"
# Guard 2 row 3: the head must be bound — every non-`true` spelling of ORACLE_HEAD_OK
for _ho in "" false False TRUE 1 " true"; do
  otol "O2-3 listed skip with ORACLE_HEAD_OK='$_ho'" "$BODY" merge_group test-bun true "$_ho" 1 $OK $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" "$OTOL_MSG"
done
# Guard 2 row 4: a re-run reuses cached outputs — only attempt 1 tolerates
for _at in 2 3 "" 01 " 1"; do
  otol "O2-4 listed skip on ATTEMPT='$_at'" "$BODY" merge_group test-bun true true "$_at" $OK $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" "$OTOL_MSG"
done
# Guard 2 row 5: push / workflow_dispatch / schedule never tolerate, identical other inputs
for _ev in push workflow_dispatch schedule; do
  otol "O2-5 listed skip on $_ev" "$BODY" "$_ev" test-bun true true 1 $OK $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" "$OTOL_MSG"
done
# ORACLE_ACTIVE must be exactly `true`
for _ac in "" false False TRUE True 1 yes " true" "true "; do
  otol "O2-3b listed skip with ORACLE_ACTIVE='$_ac'" "$BODY" merge_group test-bun "$_ac" true 1 $OK $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" "$OTOL_MSG"
done
# the delimited match: a substring or a foreign member anywhere in the list invalidates it
otol "O2-7 test-scripts listed, test-scripts-heavy skipped (delimited, not prefix)" "$BODY" merge_group "test-scripts" true true 1 $OK $OK $OK $OK $S $OK $OK 1 "test-scripts-heavy: SKIPPED" "$OTOL_MSG"
otol "O2-7b test-scripts-heavy listed, test-scripts skipped (both are lane legs — delimited exact)" "$BODY" merge_group "test-scripts-heavy" true true 1 $OK $OK $OK $S $OK $OK $OK 1 "test-scripts: SKIPPED" "$OTOL_MSG"
for _l in "encryption-posture,test-bun" ",test-bun" "test-bun," " test-bun" "TEST-BUN" "test-bun,,test-scripts"; do
  otol "O2-8 malformed list '$_l' tolerates nothing" "$BODY" merge_group "$_l" true true 1 $OK $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" "$OTOL_MSG"
done
# a tolerated skip never hides a failing sibling, and a failed/cancelled listed leg is not tolerated
otol "O2-9 tolerated skip plus a failing sibling" "$BODY" merge_group test-bun true true 1 $OK failure $S $OK $OK $OK $OK 1 "test-webplat: FAILED" ""
otol "O2-9b tolerated skip plus a failing sibling still names the tolerated leg" "$BODY" merge_group test-bun true true 1 $OK failure $S $OK $OK $OK $OK 1 "test-bun: $OTOL_MSG" ""
for _r in failure cancelled; do
  otol "O2-10 listed leg with result=$_r is not tolerated" "$BODY" merge_group test-bun true true 1 $OK $OK $_r $OK $OK $OK $OK 1 "" "test-bun: $OTOL_MSG"
done
# an unlisted leg skipped beside a compliant listed skip: the unlisted one reds
otol "O2-11 second leg skipped and unlisted after a compliant first" "$BODY" merge_group test-bun true true 1 $OK $S $S $OK $OK $OK $OK 1 "test-webplat: SKIPPED" "test-webplat: $OTOL_MSG"
# oracle tolerance does not fire on pull_request without the oracle inputs, and no second arm survives to leak into
otol "O2-12 a pull_request skip with empty oracle inputs is never tolerated" "$BODY" pull_request "" "" "" 1 $OK $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" "$OTOL_MSG"
# the ORACLE re-run remedy (P2-5, mirror of the PR G1-17 family): on attempt > 1 a leg the cached ORACLE_SKIP_LEGS
# decision NAMED gets the remedy line; a leg skipped for another reason keeps the plain line. The remedy is a
# courtesy, not the verdict — the skip itself is already not tolerated (rc=1) because the arm requires attempt 1.
otol "O2-14 a NAMED skip on ATTEMPT=2 names the oracle re-run remedy" "$BODY" pull_request test-bun true true 2 $OK $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED — $OREM_TXT" "$OTOL_MSG"
otol "O2-14b an UNNAMED shard skipped beside a set list keeps the plain line" "$BODY" pull_request test-bun true true 2 $OK $S $OK $OK $OK $OK $OK 1 "test-webplat: SKIPPED — the leg did not run" "cached from attempt 1"
otol "O2-14d delimited, not substring: 'test-scripts-heavy' names no remedy for 'test-scripts'" "$BODY" merge_group test-scripts-heavy true true 2 $OK $OK $OK $S $OK $OK $OK 1 "test-scripts: SKIPPED — the leg did not run" "cached from attempt 1"
otol "O2-14c attempt 1, named skip tolerated: no remedy line" "$BODY" pull_request test-bun true true 1 $OK $OK $S $OK $OK $OK $OK 0 "test-bun: $OTOL_MSG" "cached from attempt 1"
run_body "$BODY" success skipped success pull_request success success success "" test-bun true true 1 success "" "" ""
if [ "$RC" -eq 1 ] && grep -qF -- "test-bun: SKIPPED" "$OUT" && ! grep -qF -- "$TOL_MSG" "$OUT"; then pass; else
  fail "O2-13 the retired PR arm can never fire — a stale-arm-shaped input stays red (rc=$RC): $(tr '\n' '|' <"$OUT" | head -c 200)"
fi

# O2-H1 (Guard 2 harness): mutate the oracle arm under test and require RED. Anchors key on literals
# the contract fixes (ORACLE_ACTIVE/ORACLE_HEAD_OK/ORACLE_SKIP_LEGS env names, the ORACLE-ONLY-SKIP
# token, the five-name allowlist); a did-not-land is a coordination signal, not a pass.
cat > "$SANDBOX/omut.py" <<'PYM'
import sys
src, dst, op = sys.argv[1:4]
s = open(src).read()
def sub(old, new, n=1):
    global s
    if s.count(old) < 1:
        sys.stderr.write("anchor missing for %r\n" % (old,)); sys.exit(3)
    s = s.replace(old, new, n)
if op == "remove-arm":
    # the tolerance arm itself, not just the marker: a tolerated leg becomes an ordinary SKIPPED again
    sub('if [[ "$oracle_tolerated" == *",$shard,"* ]]; then', 'if false; then')
elif op == "no-active":
    sub('"$ORACLE_ACTIVE" == "true" && ', "")
elif op == "no-head":
    sub('"$ORACLE_HEAD_OK" == "true" && ', "")
elif op == "active-loose":
    sub('"$ORACLE_ACTIVE" == "true"', '"$ORACLE_ACTIVE" != "false"')
elif op == "event-any":
    sub('"$EVENT_NAME" == "merge_group"', '"$EVENT_NAME" == "merge_group" || "$EVENT_NAME" == "push"')
elif op == "index-tolerable":
    sub("test-webplat|test-bun|test-scripts|test-scripts-heavy|web-platform-build",
        "test-webplat|test-bun|test-scripts|test-scripts-heavy|web-platform-build|oracle-index-check")
elif op == "posture-tolerable":
    sub("test-webplat|test-bun|test-scripts|test-scripts-heavy|web-platform-build",
        "test-webplat|test-bun|test-scripts|test-scripts-heavy|web-platform-build|encryption-posture")
elif op == "substring":
    # the ORACLE loop's delimited match (the `entry` var is shared; the `oracle_tolerated=` target disambiguates)
    sub('*",${entry%%:*},"*) oracle_tolerated=', '*"${entry%%:*}"*) oracle_tolerated=')
elif op == "o-remedy-removed":
    # the oracle re-run remedy arm (P2-5): a leg the cached oracle decision NAMED keeps only the plain SKIPPED
    # line on attempt > 1 — the mirror of the PR family's remedy-removed.
    sub('if [[ "$ATTEMPT" != "1" && ",$ORACLE_SKIP_LEGS," == *",$shard,"* ]]; then', 'if false; then')
elif op == "o-remedy-any-shard":
    sub('if [[ "$ATTEMPT" != "1" && ",$ORACLE_SKIP_LEGS," == *",$shard,"* ]]; then', 'if [[ "$ATTEMPT" != "1" && -n "$ORACLE_SKIP_LEGS" ]]; then')
elif op == "o-remedy-substring":
    sub('if [[ "$ATTEMPT" != "1" && ",$ORACLE_SKIP_LEGS," == *",$shard,"* ]]; then', 'if [[ "$ATTEMPT" != "1" && ",$ORACLE_SKIP_LEGS," == *"$shard"* ]]; then')
else:
    sys.stderr.write("unknown op\n"); sys.exit(2)
open(dst, "w").write(s)
PYM
mutate_otol() {  # $1=label $2=op ; probes the Guard-2 rows over the mutant — at least one must go RED
  local label="$1" op="$2" m="$SANDBOX/mut.otol.$RANDOM"
  MUT_TOTAL=$((MUT_TOTAL + 1))
  if ! python3 "$SANDBOX/omut.py" "$SANDBOX/body.pristine" "$m" "$op" 2>"$SANDBOX/omut.err"; then
    fail "MUTATION DID NOT LAND: $label ($(head -c 120 "$SANDBOX/omut.err"))"; return
  fi
  if cmp -s "$m" "$SANDBOX/body.pristine"; then fail "MUTATION DID NOT LAND: $label — byte-identical"; return; fi
  PROBE=1; PROBE_FAILS=0
  { otol "o0" "$m" merge_group test-bun true true 1 $OK $OK $S $OK $OK $OK $OK 0 "test-bun: $OTOL_MSG" "test-bun: SKIPPED"
    otol "o1" "$m" merge_group "" "" "" 1 $OK $S $OK $OK $OK $OK $OK 1 "test-webplat: SKIPPED" "$OTOL_MSG"
    otol "o2" "$m" push test-bun true true 1 $OK $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" "$OTOL_MSG"
    otol "o3" "$m" merge_group test-bun true false 1 $OK $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" "$OTOL_MSG"
    otol "o4" "$m" merge_group test-bun true "" 1 $OK $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" "$OTOL_MSG"
    otol "o5" "$m" merge_group test-bun true true 2 $OK $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" "$OTOL_MSG"
    otol "o6" "$m" merge_group "$ALL5" true true 1 $S $S $S $S $S $S $OK 1 "oracle-index-check: SKIPPED" "oracle-index-check: $OTOL_MSG"
    otol "o7" "$m" merge_group "encryption-posture" true true 1 $OK $OK $OK $OK $OK $OK $S 1 "encryption-posture: SKIPPED" "$OTOL_MSG"
    otol "o8" "$m" merge_group "test-scripts" true true 1 $OK $OK $OK $OK $S $OK $OK 1 "test-scripts-heavy: SKIPPED" "$OTOL_MSG"
    otol "o9" "$m" pull_request "test-webplat,test-bun" true true 1 $OK $S $S $OK $OK $OK $OK 0 "test-bun: $OTOL_MSG" ""
    # o10 kills no-active/active-loose: VALID list, every other conjunct true, only ACTIVE non-true
    otol "o10" "$m" merge_group test-bun "" true 1 $OK $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" "$OTOL_MSG"
    # o11 kills index-tolerable: the list names ONLY oracle-index-check and it is the skipped leg
    otol "o11" "$m" merge_group "oracle-index-check" true true 1 $S $OK $OK $OK $OK $OK $OK 1 "oracle-index-check: SKIPPED" "oracle-index-check: $OTOL_MSG"
    # o12 kills the substring mutant: `test-scripts` is a strict substring of the listed `test-scripts-heavy`
    otol "o12" "$m" merge_group test-scripts-heavy true true 1 $OK $OK $OK $S $OK $OK $OK 1 "test-scripts: SKIPPED" "test-scripts: $OTOL_MSG"
    # the oracle re-run remedy probes: a NAMED skip on attempt 2 prints the remedy, an UNNAMED one does not,
    # the match is delimited (heavy does not name scripts), and nothing prints at attempt 1.
    otol "o13" "$m" pull_request test-bun true true 2 $OK $OK $S $OK $OK $OK $OK 1 "the oracle-lane skip decision is cached" ""
    otol "o14" "$m" pull_request test-bun true true 2 $OK $S $OK $OK $OK $OK $OK 1 "test-webplat: SKIPPED — the leg did not run" "cached from attempt 1"
    otol "o15" "$m" merge_group test-scripts-heavy true true 2 $OK $OK $OK $S $OK $OK $OK 1 "test-scripts: SKIPPED — the leg did not run" "cached from attempt 1"
    otol "o16" "$m" pull_request test-bun true true 1 $OK $OK $S $OK $OK $OK $OK 0 "test-bun: $OTOL_MSG" "cached from attempt 1"
  } >/dev/null 2>&1
  PROBE=0
  if [ "$PROBE_FAILS" -gt 0 ]; then pass; MUT_KILLED=$((MUT_KILLED + 1))
  else fail "MUTANT SURVIVED: $label — no Guard-2 row detected this edit"; MUT_SURVIVED+=("$label"); fi
}
mutate_otol "O2-H1a remove the ORACLE-ONLY-SKIP tolerance" remove-arm
mutate_otol "O2-H1b drop the ORACLE_ACTIVE term" no-active
mutate_otol "O2-H1c drop the ORACLE_HEAD_OK term" no-head
mutate_otol "O2-H1d loosen ORACLE_ACTIVE to != false" active-loose
mutate_otol "O2-H1e the arm also fires on push" event-any
mutate_otol "O2-H1f the allowlist gains oracle-index-check" index-tolerable
mutate_otol "O2-H1g the allowlist gains encryption-posture" posture-tolerable
mutate_otol "O2-H1h delimited match becomes a substring match" substring
mutate_otol "O2-H2a the oracle re-run remedy arm is removed" o-remedy-removed
mutate_otol "O2-H2b the remedy fires for any shard when the list is nonempty" o-remedy-any-shard
mutate_otol "O2-H2c the remedy match becomes a substring match" o-remedy-substring

# ── S4-retirement mutant harness: a re-introduced skip tolerance must turn a post-removal row RED ──────────
cat > "$SANDBOX/rtmut.py" <<'PYR'
import sys
src, dst, op = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(src).read()
def sub(old, new):
    global s
    if s.count(old) != 1:
        sys.stderr.write("anchor count %d for %r\n" % (s.count(old), old)); sys.exit(3)
    s = s.replace(old, new)
if op == "tolerance-returns":
    # re-introduce the retired arm's shape: a skipped leg stops being a failure (fail=1 sits BEFORE the
    # diagnostic case by design, so a tolerated skip must bypass it — this is the arm's only green path)
    sub('  fail=1\n  case "$result" in', '  [ "$result" = "skipped" ] || fail=1\n  case "$result" in')
elif op == "remedy-on-any":
    # the re-run remedy fires on ANY skipped shard, not just the oracle-listed ones
    sub('if [[ "$ATTEMPT" != "1" && ",$ORACLE_SKIP_LEGS," == *",$shard,"* ]]; then',
        'if [[ "$ATTEMPT" != "1" ]]; then')
else:
    sys.stderr.write("unknown op\n"); sys.exit(2)
open(dst, "w").write(s)
PYR
mutate_rtol() {  # $1=label $2=op ; the post-removal rows over the mutant: at least one must go RED
  local label="$1" op="$2" m="$SANDBOX/mut.rt.$RANDOM"
  MUT_TOTAL=$((MUT_TOTAL + 1))
  if ! python3 "$SANDBOX/rtmut.py" "$SANDBOX/body.pristine" "$m" "$op" 2>"$SANDBOX/rtmut.err"; then
    fail "MUTATION DID NOT LAND: $label ($(head -c 120 "$SANDBOX/rtmut.err"))"; return
  fi
  if cmp -s "$m" "$SANDBOX/body.pristine"; then fail "MUTATION DID NOT LAND: $label — byte-identical"; return; fi
  PROBE=1; PROBE_FAILS=0
  {
    run_body "$m" $S $OK $OK pull_request $OK $OK $OK "" "" "" "" 1 success "" "" ""
    [ "$RC" -eq 1 ] && grep -qF -- "test-webplat: SKIPPED — the leg did not run" "$OUT" || PROBE_FAILS=$((PROBE_FAILS + 1))
    run_body "$m" $S $OK $OK pull_request $OK $OK $OK "" "" "" "" 2 success "" "" ""
    { [ "$RC" -eq 1 ] && grep -qF -- "test-webplat: SKIPPED — the leg did not run" "$OUT" && ! grep -qF -- "cached from attempt 1" "$OUT"; } || PROBE_FAILS=$((PROBE_FAILS + 1))
  } >/dev/null 2>&1
  PROBE=0
  if [ "$PROBE_FAILS" -gt 0 ]; then pass; MUT_KILLED=$((MUT_KILLED + 1))
  else fail "MUTANT SURVIVED: $label — no post-removal row detected this edit"; MUT_SURVIVED+=("$label"); fi
}
mutate_rtol "R-H1a a re-introduced skip tolerance (the retired arm's continue)" tolerance-returns
mutate_rtol "R-H1b the remedy arms on any skipped shard, not a named one" remedy-on-any

# ── W1-W4: the STEP's wiring, which no row asserted ─────────────────────────
# Every row above executes the extracted `run:` body against env vars the HARNESS
# supplies. That proves the classifier is right and says NOTHING about whether
# the workflow feeds it the right values, or whether the `test` job still watches
# all four leg jobs. Both are one-line edits with no local symptom.
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
want = {"WEBPLAT_RESULT": "test-webplat", "BUN_RESULT": "test-bun", "SCRIPTS_RESULT": "test-scripts", "SCRIPTS_HEAVY_RESULT": "test-scripts-heavy", "BUILD_RESULT": "web-platform-build", "POSTURE_RESULT": "encryption-posture"}
bad = []
for var, shard in want.items():
    v = str(env.get(var, ""))
    # EXACT match, not a substring: `${{ needs.x.result && 'success' }}` and
    # `${{ contains(needs.x.result, 'y') && 'failure' || 'success' }}` both
    # contain the substring and both always resolve to success (#6907 review).
    if "".join(v.split()) != "${{needs.%s.result}}" % shard:
        bad.append("%s should be exactly ${{ needs.%s.result }}, reads %r" % (var, shard, v))
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
# push-dedupe (#9512, ADR-276 S2) is a NON-LEG need: it gates the job off an elided push and is never
# read by the aggregator body. It is counted separately (W5), not as an eighth leg. Likewise draft-light
# (#9728, ADR-276 S3): the aggregator reads its output once, through DRAFT_LIGHT (W6), never as a leg. Likewise pr-selection
# (#9729, ADR-276 S4 PR B): its outputs feed only the PR-AFFECTED-SKIP tolerance, through SKIP_LEGS/ACTIVE/HEAD_SHA_OK/ATTEMPT (W7).
# Likewise oracle-selection (#12156): its outputs feed only the ORACLE-ONLY-SKIP tolerance (W8). oracle-index-check
# IS a leg — it joins entries[] and its result is always required.
print(len([x for x in n if x not in ("push-dedupe", "draft-light", "oracle-selection")]))
PYN
)
if [ "$_nshards" -eq 7 ]; then pass; else
  fail "W2 the test job watches $_nshards legs, but this suite fixtures exactly 7 (four test-* shards + web-platform-build #8136 + encryption-posture #6907 + oracle-index-check #12156) — dropping a leg from needs: makes its result resolve to EMPTY, which falls straight into the *) arm, and every row here would still pass"
fi
# W5 — the one non-leg need is push-dedupe, exactly once, and the aggregator's env: never reads it. If the
# body ever read its output the stage-S2 claim "the aggregator is byte-identical" would be false.
_nonleg=$(python3 - "$_ciy" <<'PYX'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
job = d["jobs"]["test"]
n = job.get("needs") or []
n = [n] if isinstance(n, str) else list(n)
legs = {"test-webplat", "test-bun", "test-scripts", "test-scripts-heavy", "web-platform-build", "encryption-posture", "oracle-index-check"}
extra = [x for x in n if x not in legs]
env = {}
for st in job.get("steps") or []:
    env.update(st.get("env") or {})
leak = [k for k, v in env.items() if "push-dedupe" in str(v)]
print(("extra=%s" % ",".join(sorted(extra))) + ((" env-reads-push-dedupe=%s" % ",".join(leak)) if leak else ""))
PYX
)
if [ "$_nonleg" = "extra=draft-light,oracle-selection,push-dedupe" ]; then pass; else
  fail "W5 the test job's only non-leg needs must be draft-light, oracle-selection and push-dedupe, and its env: must not read push-dedupe (got: $_nonleg)"
fi
# W6 — the draft arm's input is exactly the draft-light output, and EVENT_NAME is exactly the event. A DRAFT_LIGHT that read
# `.result`, a literal, or any other expression would make the arm fire on every PR (red-always) or never (Option R void).
_dl_env=$(python3 - "$_ciy" <<'PYD'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
st = [s for s in d["jobs"]["test"].get("steps") or [] if s.get("name") == "Aggregate shard results"][0]
env = st.get("env") or {}
bad = []
if "".join(str(env.get("DRAFT_LIGHT", "")).split()) != "${{needs.draft-light.outputs.light}}":
    bad.append("DRAFT_LIGHT reads %r" % env.get("DRAFT_LIGHT"))
if "".join(str(env.get("EVENT_NAME", "")).split()) != "${{github.event_name}}":
    bad.append("EVENT_NAME reads %r" % env.get("EVENT_NAME"))
print("; ".join(bad))
PYD
)
if [ -z "$_dl_env" ]; then pass; else fail "W6 the aggregator's draft inputs are mis-wired: $_dl_env"; fi

# W7 — the retired arm's env is GONE (S4 retirement, 2026-11-09): SKIP_LEGS/ACTIVE/HEAD_SHA_OK must not exist
# and no env may read `needs.pr-selection`. A survivor would silently re-arm a tolerance the rows above cannot
# see (the harness hands the body its inputs); ATTEMPT stays — the oracle remedy shares it.
_tol_env=$(python3 - "$_ciy" <<'PYT'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
st = [s for s in d["jobs"]["test"].get("steps") or [] if s.get("name") == "Aggregate shard results"][0]
env = st.get("env") or {}
bad = []
for k in ("SKIP_LEGS", "ACTIVE", "HEAD_SHA_OK"):
    if k in env:
        bad.append("retired env %s still present (%r)" % (k, env.get(k)))
for k, v in env.items():
    if "pr-selection" in str(v):
        bad.append("%s reads needs.pr-selection (%r)" % (k, v))
if "".join(str(env.get("ATTEMPT", "")).split()) != "${{github.run_attempt}}":
    bad.append("ATTEMPT reads %r" % env.get("ATTEMPT"))
print("; ".join(bad))
PYT
)
if [ -z "$_tol_env" ]; then pass; else fail "W7 the aggregator carries retired pr-selection inputs: $_tol_env"; fi

# W8 — the ORACLE-ONLY-SKIP inputs (#12156) are exactly the oracle-selection outputs and the
# oracle-index-check result. ORACLE_SKIP_LEGS/ORACLE_ACTIVE read oracle-selection's outputs;
# ORACLE_HEAD_OK binds the reported head to the event's own head (pull_request.head.sha OR
# merge_group.head_sha, the event-agnostic pair); ORACLE_INDEX_RESULT reads the leg's result.
_ora_env=$(python3 - "$_ciy" <<'PYO'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
st = [s for s in d["jobs"]["test"].get("steps") or [] if s.get("name") == "Aggregate shard results"][0]
env = st.get("env") or {}
def sq(k): return "".join(str(env.get(k, "")).split())
bad = []
if sq("ORACLE_SKIP_LEGS") != "${{needs.oracle-selection.outputs.skip_legs}}":
    bad.append("ORACLE_SKIP_LEGS reads %r" % env.get("ORACLE_SKIP_LEGS"))
if sq("ORACLE_ACTIVE") != "${{needs.oracle-selection.outputs.active}}":
    bad.append("ORACLE_ACTIVE reads %r" % env.get("ORACLE_ACTIVE"))
hok = sq("ORACLE_HEAD_OK")
if "needs.oracle-selection.outputs.head_sha" not in hok or "pull_request.head.sha" not in hok or "merge_group.head_sha" not in hok:
    bad.append("ORACLE_HEAD_OK reads %r — must bind the oracle head to BOTH event head shapes" % env.get("ORACLE_HEAD_OK"))
if sq("ORACLE_INDEX_RESULT") != "${{needs.oracle-index-check.result}}":
    bad.append("ORACLE_INDEX_RESULT reads %r" % env.get("ORACLE_INDEX_RESULT"))
print("; ".join(bad))
PYO
)
if [ -z "$_ora_env" ]; then pass; else fail "W8 the aggregator's ORACLE-ONLY-SKIP inputs are mis-wired: $_ora_env"; fi

# W3 — the ARMED leg must be able to conclude failure (#6907 MB-10). Fail-OPEN
# shapes: a job-level `continue-on-error`, a step-level `if:` or
# `continue-on-error`, or a run line other than the bare sweep (`|| true`,
# `--today`, `--repo-root`, `--check-templates`, an `echo` prefix) — each lets
# needs.encryption-posture.result read success over a red or unrun sweep. A
# job-level `if:` fails CLOSED (the leg reads skipped; R1i) but wedges the paths
# it skips, so it is refused too.
_posture=$(python3 - "$_ciy" <<'PYP'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
job = d["jobs"].get("encryption-posture")
if job is None:
    print("the encryption-posture job is gone"); raise SystemExit
bad = []
if job.get("continue-on-error") not in (None, False):
    bad.append("job-level continue-on-error=%r lets a red sweep conclude success" % job.get("continue-on-error"))
if "if" in job:
    bad.append("job-level if: %r fails closed and wedges every PR it skips" % job.get("if"))
if "EP_TODAY" in (job.get("env") or {}):
    bad.append("job env sets EP_TODAY, which moves the expiry clock")
SWEEP = "python3 scripts/lint-encryption-posture.py --repo-sweep"
sweeps = [st for st in job.get("steps") or [] if "lint-encryption-posture.py" in str(st.get("run", ""))]
if len(sweeps) != 1:
    bad.append("expected exactly one sweep step, found %d" % len(sweeps))
for st in sweeps:
    # The run line must be EXACTLY the sweep: `|| true`, an `echo` prefix,
    # `--repo-root /tmp` (reads no ledger), `--check-templates` (the sweep
    # never runs) and `--today 2000-01-01` (hides an expired exception) all
    # contain the substring an earlier revision matched on (#6907 review).
    if str(st.get("run", "")).strip() != SWEEP:
        bad.append("sweep step run is %r, must be exactly %r" % (st.get("run"), SWEEP))
    for key in ("if", "shell", "working-directory"):
        if key in st:
            bad.append("sweep step sets %s: %r" % (key, st.get(key)))
    if "EP_TODAY" in (st.get("env") or {}):
        bad.append("sweep step env sets EP_TODAY")
for st in job.get("steps") or []:
    if st.get("continue-on-error") not in (None, False):
        bad.append("step %r sets continue-on-error" % st.get("name"))
print("; ".join(bad))
PYP
)
if [ -z "$_posture" ]; then pass; else
  fail "W3 the encryption-posture leg cannot red the aggregator: $_posture"
fi

# W4 — the AGGREGATOR itself must be able to go red. Removing `if: always()`
# makes `test` SKIPPED when any leg fails, and GitHub counts a skipped required
# check as passing — the fail-open this PR exists to close, one job up. A
# `continue-on-error` or an `if:` on the job or its aggregate step does the same.
_aggr=$(python3 - "$_ciy" <<'PYA'
import sys, yaml
# Reject DUPLICATE mapping keys anywhere in ci.yml. PyYAML keeps the LAST
# value, so `continue-on-error: true` followed by `continue-on-error: false`
# reads clean to every row above while a parser that keeps the FIRST value
# would disarm the gate. A duplicate key is never intended in a workflow.
class StrictLoader(yaml.SafeLoader):
    pass
def _no_dups(loader, node, deep=False):
    seen = set()
    for key_node, _ in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in seen:
            raise yaml.constructor.ConstructorError(
                None, None, "duplicate key %r" % (key,), key_node.start_mark)
        seen.add(key)
    return loader.construct_mapping(node, deep=deep)
StrictLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _no_dups)
bad = []
try:
    job = yaml.load(open(sys.argv[1]), Loader=StrictLoader)["jobs"]["test"]
except yaml.YAMLError as exc:
    print("ci.yml does not parse strictly: %s" % str(exc).replace("\n", " "))
    raise SystemExit

# `always()` alone, or the one canonical form S2 (#9512, ADR-276) uses: always() ANDed with the push-dedupe elision
# condition, which is true on every event except an elided push (scripts/ci-push-dedupe.test.sh evaluates it).
_ALLOWED_IF = ("always()", "${{ always() && (github.event_name == 'merge_group' || github.event_name != 'push' || needs.push-dedupe.outputs.elide != 'true') }}")
if str(job.get("if", "")).strip() not in _ALLOWED_IF:
    bad.append("test job if is %r, must be always() or the canonical push-dedupe form" % job.get("if"))
if job.get("continue-on-error") not in (None, False):
    bad.append("test job sets continue-on-error")
for st in job.get("steps") or []:
    if st.get("name") == "Aggregate shard results":
        for key in ("if", "continue-on-error"):
            if key in st and st.get(key) is not False:
                bad.append("aggregate step sets %s: %r" % (key, st.get(key)))
print("; ".join(bad))
PYA
)
if [ -z "$_aggr" ]; then pass; else
  fail "W4 the test aggregator cannot go red: $_aggr"
fi

# ── Verdict ──────────────────────────────────────────────────────────────────
TOTAL=$((passes + fails))

# ASSERTION FLOOR, reported with printf + exit rather than through the helpers
# it backstops (ADR-193). A floor dispatched through pass()/fail() is silenced
# by the same edit that silences everything else.
if [ "$PROBE" -ne 0 ]; then
  printf 'FAIL: PROBE mode leaked: PROBE=%s at the verdict, so every verdict after the leak was counted nowhere.\n' "$PROBE" >&2
  exit 1
fi
# DERIVED FROM A GREEN RUN, NOT GUESSED, and with ZERO SLACK: a floor above the real count is a broken instrument that reds a correct
# tree; a floor below it is slack an undispatched row can hide in. Mutant probes run in PROBE mode (pass()/fail() above), so the total
# below counts ONLY rows that ran against the real body plus one row per mutant verdict; an earlier revision let ~150 probe passes
# leak in and the floor it pinned (298) was inflated by them. Itemised so the next author can re-derive it after adding a row:
#    1 instrument self-test + 1 control
# + 17 classification: R1, R1b, R1c, R1d, R1e, R1f, R1g, R1h, R1i, R1j, R1k, R1l, R2, R3, R3b, R4, R5
# +  2 event gate (24b absent-SUPERSEDED, 24b says-something) + 1 second member (25) + 3 swallow (24, one per non-success value)
# +  1 must-PASS (Hb)
# +  5 mutation battery (22, 23, 24, 25 as mutants; Ha, the swallowing-mutant harness row)
# +  3 event/value cardinality (E1 merge_group, E1 workflow_dispatch, E3 out-of-enum)                                  = 34
# + 27 the draft arm (ADR-276 S3, #9728): D1, D1b, D2 (3); D3 and D4 over 3 events (6); D5 over 9 values plus D5b (10); D6, D6b (2);
#      the 5 arm mutants D7, D7b-D7e (5); D8 structure (1)                                                            = 61
# + 39 post-removal Guard-1/2 executed rows: 11 R1 (R1-1/R1-2 over 4 events = 8, R1-3..R1-5 = 3), the O2 oracle
#      family, and 2 retirement mutants R-H1a,b (re-introduced tolerance/remedy over the post-removal probes) = 140
# +  7 wiring: W1, W2, W5, W6, W7, W3, W4                                                                                = 184
MIN_ROWS=147
if [ "$TOTAL" -lt "$MIN_ROWS" ]; then
  printf 'FAIL: assertion floor — %d rows executed, at least %d required. Rows were removed or a loop stopped early.\n' \
    "$TOTAL" "$MIN_ROWS" >&2
  exit 1
fi
# 4 mutate() + 5 mutate_arm() + 11 mutate_otol() + 2 mutate_rtol() = 22, the measured count.
MIN_MUTANTS=22
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
