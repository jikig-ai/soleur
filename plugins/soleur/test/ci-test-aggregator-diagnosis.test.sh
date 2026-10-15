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
run_body() {  # $1=body $2=webplat $3=bun $4=scripts $5=event [$6=build] [$7=scripts-heavy] [$8=posture] [$9=draft-light output] [$10=SKIP_LEGS] [$11=ACTIVE] [$12=HEAD_SHA_OK] [$13=ATTEMPT] ; sets OUT/RC
  OUT="$SANDBOX/out.$RANDOM.$RANDOM"
  ( WEBPLAT_RESULT="$2" BUN_RESULT="$3" SCRIPTS_RESULT="$4" EVENT_NAME="$5" \
      BUILD_RESULT="${6:-success}" SCRIPTS_HEAVY_RESULT="${7:-success}" POSTURE_RESULT="${8:-success}" \
      DRAFT_LIGHT="${9:-}" \
      SKIP_LEGS="${10:-}" ACTIVE="${11:-}" HEAD_SHA_OK="${12:-}" ATTEMPT="${13-1}" \
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
  "All six legs green (four shards + web-platform-build + encryption-posture)." 0
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
  "All six legs green (four shards + web-platform-build + encryption-posture)." 0

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
    k = s.rfind('echo "All six legs green')
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

# ── Guard 1 (ADR-276 S4, #9729 PR B): the PR-AFFECTED-SKIP tolerance ─────────────────────────────────────────────────────────
# PROPERTY: a `skipped` leg turns the aggregator green ONLY on a pull_request run with ACTIVE exactly `true`, the head bound, attempt 1,
# a well-formed SKIP_LEGS over the three gateable legs, and the leg named in it by a delimited match. Every other skip reds it, and
# test-scripts / web-platform-build / encryption-posture can never be tolerated. Rows G1-0..G1-18 execute the extracted body (G1-16 the exact final line, G1-17 the re-run remedy, G1-18 foreign-first lists).
TOL_MSG="PR-AFFECTED-SKIP"
ALL3="test-webplat,test-bun,test-scripts-heavy"
tol() {  # $1=label $2=body $3=event $4=skip_legs $5=active $6=head_ok $7=attempt $8=webplat $9=bun ${10}=scripts ${11}=heavy ${12}=build ${13}=posture ${14}=want_rc ${15}=needle(or "") ${16}=forbid(or "")
  local label="$1" body="$2" ev="$3" sk="$4" ac="$5" ho="$6" at="$7" w="$8" b="$9" s="${10}" h="${11}" bd="${12}" po="${13}" wrc="${14}" need="${15:-}" forbid="${16:-}"
  run_body "$body" "$w" "$b" "$s" "$ev" "$bd" "$h" "$po" "" "$sk" "$ac" "$ho" "$at"
  local ok=1
  [ "$RC" -eq "$wrc" ] || ok=0
  if [ -n "$need" ]; then grep -qF -- "$need" "$OUT" || ok=0; fi
  if [ -n "$forbid" ]; then if grep -qF -- "$forbid" "$OUT"; then ok=0; fi; fi
  if [ "$ok" -eq 1 ]; then pass; return 0; fi
  fail "$label — event=$ev skip_legs='$sk' active='$ac' head_ok='$ho' attempt='$at' legs=($w,$b,$s,$h,$bd,$po): want rc=$wrc need='$need' forbid='$forbid'; got rc=$RC, output: $(tr '\n' '|' <"$OUT" | head -c 300)"
  return 1
}
S=skipped; OK=success
# must-PASS (the canonical shape, and two non-canonical ones): a listed skip on an active, head-bound, attempt-1 pull_request run
tol "G1-0 must-PASS: one listed skip" "$BODY" pull_request test-bun true true 1 $OK $S $OK $OK $OK $OK 0 "test-bun: $TOL_MSG" "test-bun: SKIPPED"
tol "G1-0b must-PASS: all three listed and skipped" "$BODY" pull_request "$ALL3" true true 1 $S $S $OK $S $OK $OK 0 "All legs green or $TOL_MSG tolerated" "SKIPPED —"
tol "G1-0c must-PASS: listed skip, list in another order" "$BODY" pull_request "test-scripts-heavy,test-webplat" true true 1 $S $OK $OK $S $OK $OK 0 "test-scripts-heavy: $TOL_MSG" ""
# G1-1 a skipped leg that is NOT in skip_legs, with a compliant first listed skip beside it; G1-5 a second leg after a compliant first
tol "G1-1 skipped leg absent from skip_legs" "$BODY" pull_request test-bun true true 1 $S $OK $OK $OK $OK $OK 1 "test-webplat: SKIPPED" ""
tol "G1-5 second leg skipped and unlisted after a compliant first" "$BODY" pull_request test-webplat true true 1 $S $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" ""
# G1-2 never on merge_group / push / workflow_dispatch, whatever the other inputs say
for _ev in merge_group push workflow_dispatch; do
  tol "G1-2 listed skip on $_ev" "$BODY" "$_ev" test-bun true true 1 $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" "$TOL_MSG"
done
# G1-3 ACTIVE must be exactly `true`
for _ac in "" false False TRUE True 1 yes " true" "true "; do
  tol "G1-3 listed skip with ACTIVE='$_ac'" "$BODY" pull_request test-bun "$_ac" true 1 $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" "$TOL_MSG"
done
# G1-7b the head binding: HEAD_SHA_OK must be exactly `true`
for _ho in "" false False TRUE True 1 " true"; do
  tol "G1-7b listed skip with HEAD_SHA_OK='$_ho'" "$BODY" pull_request test-bun true "$_ho" 1 $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" "$TOL_MSG"
done
# G1-9 only attempt 1: a re-run reuses the original event payload, so the head comparison cannot detect a moved base
for _at in 2 3 "" 01 " 1" 10; do
  tol "G1-9 listed skip with ATTEMPT='$_at'" "$BODY" pull_request test-bun true true "$_at" $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" "$TOL_MSG"
done
# G1-4 / G1-10 the allowlist is a literal: test-scripts, web-platform-build and encryption-posture are never tolerated, even when listed
tol "G1-4 encryption-posture skipped and listed" "$BODY" pull_request "encryption-posture" true true 1 $OK $OK $OK $OK $OK $S 1 "encryption-posture: SKIPPED" "$TOL_MSG"
tol "G1-4b encryption-posture skipped beside a valid list" "$BODY" pull_request "$ALL3" true true 1 $OK $OK $OK $OK $OK $S 1 "encryption-posture: SKIPPED" "encryption-posture: $TOL_MSG"
tol "G1-10 test-scripts skipped beside a valid list" "$BODY" pull_request "$ALL3" true true 1 $OK $OK $S $OK $OK $OK 1 "test-scripts: SKIPPED" "test-scripts: $TOL_MSG"
tol "G1-10b web-platform-build skipped beside a valid list" "$BODY" pull_request "$ALL3" true true 1 $OK $OK $OK $OK $S $OK 1 "web-platform-build: SKIPPED" "web-platform-build: $TOL_MSG"
# a list naming ANY other leg is invalid as a whole: even its valid members are not tolerated
tol "G1-4c invalid list (one foreign member) tolerates nothing" "$BODY" pull_request "test-bun,test-scripts" true true 1 $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" "$TOL_MSG"
tol "G1-4d list with surrounding whitespace is invalid (exact, no trimming)" "$BODY" pull_request " test-bun" true true 1 $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" "$TOL_MSG"
tol "G1-4e list with a trailing comma is invalid" "$BODY" pull_request "test-bun," true true 1 $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" "$TOL_MSG"
tol "G1-4f list with uppercase is invalid" "$BODY" pull_request "TEST-BUN" true true 1 $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" "$TOL_MSG"
# G1-7 the substring trap: `test-scripts` is a prefix of `test-scripts-heavy`
tol "G1-7 test-scripts skipped, only test-scripts-heavy listed" "$BODY" pull_request "test-scripts-heavy" true true 1 $OK $OK $S $OK $OK $OK 1 "test-scripts: SKIPPED" "test-scripts: $TOL_MSG"
tol "G1-7c test-scripts-heavy skipped, only test-scripts listed (invalid list)" "$BODY" pull_request "test-scripts" true true 1 $OK $OK $OK $S $OK $OK 1 "test-scripts-heavy: SKIPPED" "$TOL_MSG"
# G1-12 the tolerance keys on `skipped` only: a listed leg that failed or was cancelled is still red, and is not called tolerated
for _r in failure cancelled; do
  tol "G1-12 listed leg with result=$_r" "$BODY" pull_request test-bun true true 1 $OK $_r $OK $OK $OK $OK 1 "" "test-bun: $TOL_MSG"
done
# G1-13 a tolerated skip never hides a failing sibling
tol "G1-13 tolerated skip plus a failing sibling" "$BODY" pull_request test-bun true true 1 failure $S $OK $OK $OK $OK 1 "test-webplat: FAILED" ""
tol "G1-13b tolerated skip plus a failing sibling still names the tolerated leg" "$BODY" pull_request test-bun true true 1 failure $S $OK $OK $OK $OK 1 "test-bun: $TOL_MSG" ""
# G1-14 sibling inference: a leg stopped alone, whose siblings finished or were tolerated, is STOPPED ALONE, not an undetermined cancel
tol "G1-14 cancelled alone beside tolerated skips" "$BODY" pull_request "test-webplat,test-bun" true true 1 $S $S cancelled $OK $OK $OK 1 "STOPPED ALONE" "cause not determined"
# G1-8 pr-selection skipped leaves the inputs empty: the full battery's normal verdict is unchanged. Non-PR events always have it skipped; since the
# job-level switch gate (ADR-276 S4 follow-up, #9729) a `pull_request` run does too while CI_PR_AFFECTED is unset or empty, so `pull_request` joins the loop.
for _ev in merge_group push workflow_dispatch pull_request; do
  tol "G1-8 $_ev with empty pr-selection inputs, all green" "$BODY" "$_ev" "" "" "" "" $OK $OK $OK $OK $OK $OK 0 "All six legs green" "$TOL_MSG"
  tol "G1-8b $_ev with empty pr-selection inputs, a skipped leg" "$BODY" "$_ev" "" "" "" "" $S $OK $OK $OK $OK $OK 1 "test-webplat: SKIPPED" ""
done
# G1-15 Option R still wins: a tolerated skip on a light draft is red
run_body "$BODY" success skipped success pull_request success success success true test-bun true true 1
if [ "$RC" -eq 1 ] && grep -qF -- "$DRAFT_MSG" "$OUT"; then pass; else
  fail "G1-15 a tolerated skip on a light draft must still conclude RED with '$DRAFT_MSG' (rc=$RC): $(tr '\n' '|' <"$OUT" | head -c 200)"
fi

# G1-16 the final success line with tolerated skips is EXACT: the tolerated legs joined by a comma (no leading or trailing comma, in
# entries order), then the raw skip_legs. `tol_exact` reads a whole line (grep -x), so a stray trailing comma or a dropped suffix is red.
REM_TXT='the pr-selection skip decision is cached from attempt 1; use "Re-run all jobs" (or push) to get a full run'
tol_exact() {  # $1=label $2=body $3=skip_legs $4=webplat $5=bun $6=heavy $7=exact expected line ; pull_request, active, head bound, attempt 1, rc 0
  run_body "$2" "$4" "$5" success pull_request success "$6" success "" "$3" true true 1
  if [ "$RC" -eq 0 ] && grep -qxF -- "$7" "$OUT"; then pass; return 0; fi
  fail "$1 — skip_legs='$3' legs=($4,$5,$6): want rc=0 and the exact line '$7'; got rc=$RC, output: $(tr '\n' '|' <"$OUT" | head -c 300)"
  return 1
}
SIX_LINE="All six legs green (four shards + web-platform-build + encryption-posture)."
tol_exact "G1-16 one tolerated skip" "$BODY" test-bun $OK $S $OK "All legs green or $TOL_MSG tolerated (test-bun); skip_legs=test-bun"
tol_exact "G1-16b all three tolerated" "$BODY" "$ALL3" $S $S $S "All legs green or $TOL_MSG tolerated (test-webplat,test-bun,test-scripts-heavy); skip_legs=$ALL3"
tol_exact "G1-16c two tolerated, list in another order (legs print in entries order, skip_legs verbatim)" "$BODY" "test-scripts-heavy,test-webplat" $S $OK $S "All legs green or $TOL_MSG tolerated (test-webplat,test-scripts-heavy); skip_legs=test-scripts-heavy,test-webplat"
tol_exact "G1-16d a leg listed but ran: the all-six sentence is byte-identical" "$BODY" test-bun $OK $OK $OK "$SIX_LINE"
# G1-8c a pull_request run whose pr-selection job was SKIPPED (the job-level switch gate: CI_PR_AFFECTED unset or empty) hands the body EMPTY SKIP_LEGS and
# ACTIVE, and HEAD_SHA_OK is the computed boolean string `false` (`'' != ''` is false) or, defensively, empty. That state is full CI: a must-PASS characterization
# through the real body (SKIP_LEGS='' fails the regex on its own, so the tolerance arm is dead here; the p23..p25 probes in the mutant set drive this state).
# All six legs success: rc 0 and EXACTLY the six-leg line (a whole-line match), never the tolerated banner. Each gateable leg skipped: rc 1 naming it. A failed leg: rc 1.
tol_empty() {  # $1=label $2=head_ok $3=webplat $4=bun $5=heavy $6=want_rc $7=needle ; pull_request, attempt 1, SKIP_LEGS and ACTIVE empty, test-scripts/build/posture success
  run_body "$BODY" "$3" "$4" success pull_request success "$5" success "" "" "" "$2" 1
  local ok=1
  [ "$RC" -eq "$6" ] || ok=0
  if [ "$7" = "$SIX_LINE" ]; then grep -qxF -- "$7" "$OUT" || ok=0; else grep -qF -- "$7" "$OUT" || ok=0; fi
  if grep -qF -- "$TOL_MSG" "$OUT"; then ok=0; fi
  if [ "$ok" -eq 1 ]; then pass; return 0; fi
  fail "$1 — head_ok='$2' legs=($3,$4,$5): want rc=$6 and the line '$7' (a whole line for the six-leg sentence) without $TOL_MSG; got rc=$RC, output: $(tr '\n' '|' <"$OUT" | head -c 300)"
  return 1
}
for _ho in "" false; do
  tol_empty "G1-8c all six green, empty pr-selection inputs, HEAD_SHA_OK='$_ho'" "$_ho" $OK $OK $OK 0 "$SIX_LINE"
  tol_empty "G1-8c test-webplat skipped, empty inputs, HEAD_SHA_OK='$_ho'" "$_ho" $S $OK $OK 1 "test-webplat: SKIPPED — the leg did not run"
  tol_empty "G1-8c test-bun skipped, empty inputs, HEAD_SHA_OK='$_ho'" "$_ho" $OK $S $OK 1 "test-bun: SKIPPED — the leg did not run"
  tol_empty "G1-8c test-scripts-heavy skipped, empty inputs, HEAD_SHA_OK='$_ho'" "$_ho" $OK $OK $S 1 "test-scripts-heavy: SKIPPED — the leg did not run"
  tol_empty "G1-8c test-webplat failure, empty inputs, HEAD_SHA_OK='$_ho'" "$_ho" failure $OK $OK 1 "test-webplat: FAILED — the leg concluded failure. GitHub reports an assertion failure and a timeout-minutes kill identically here; check the test-webplat job log for a timeout annotation before assuming assertions."
  tol_empty "G1-8c test-bun failure, empty inputs, HEAD_SHA_OK='$_ho'" "$_ho" $OK failure $OK 1 "test-bun: FAILED — the leg concluded failure. GitHub reports an assertion failure and a timeout-minutes kill identically here; check the test-bun job log for a timeout annotation before assuming assertions."
  tol_empty "G1-8c test-scripts-heavy failure, empty inputs, HEAD_SHA_OK='$_ho'" "$_ho" $OK $OK failure 1 "test-scripts-heavy: FAILED — one or more matrix legs concluded failure. GitHub reports an assertion failure and a timeout-minutes kill identically here; open the failing leg and check for a timeout annotation before assuming assertions."
done
# G1-17 the re-run remedy: on attempt > 1 a skipped leg that the cached skip decision NAMES (delimited match against SKIP_LEGS, the same
# one the tolerance uses) names the remedy. A leg skipped for any other reason (draft-light, push-dedupe, an upstream need) keeps the plain
# SKIPPED line: telling its reader "the pr-selection skip decision is cached" would misdiagnose an unrelated red.
for _at in 2 3 ""; do
  tol "G1-17 listed skip on ATTEMPT='$_at' names the re-run remedy" "$BODY" pull_request test-bun true true "$_at" $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED — $REM_TXT" "$TOL_MSG"
done
tol "G1-17b attempt 2, skip_legs set, an UNNAMED shard skipped (another cause): the plain line, no remedy" "$BODY" pull_request test-bun true true 2 $S $OK $OK $OK $OK $OK 1 "test-webplat: SKIPPED — the leg did not run" "cached from attempt 1"
tol "G1-17b2 attempt 2, a NAMED shard that is not the first in the list names the remedy" "$BODY" pull_request "test-bun,test-webplat" true true 2 $S $OK $OK $OK $OK $OK 1 "test-webplat: SKIPPED — $REM_TXT" ""
tol "G1-17h attempt 2, test-scripts skipped, only test-scripts-heavy named: no remedy (delimited, not a prefix match)" "$BODY" pull_request test-scripts-heavy true true 2 $OK $OK $S $OK $OK $OK 1 "test-scripts: SKIPPED — the leg did not run" "cached from attempt 1"
tol "G1-17i attempt 2, one named and one unnamed shard skipped: the remedy is per shard" "$BODY" pull_request test-bun true true 2 $S $S $OK $OK $OK $OK 1 "test-bun: SKIPPED — $REM_TXT" "test-webplat: SKIPPED — $REM_TXT"
tol "G1-17c the generic SKIPPED line is kept beside the remedy" "$BODY" pull_request test-bun true true 2 $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED — the leg did not run" ""
tol "G1-17d attempt 1, listed skip made non-tolerated by ACTIVE=false: no remedy" "$BODY" pull_request test-bun false true 1 $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" "cached from attempt 1"
tol "G1-17e attempt 1, unlisted skip: no remedy" "$BODY" pull_request test-bun true true 1 $S $OK $OK $OK $OK $OK 1 "test-webplat: SKIPPED" "cached from attempt 1"
tol "G1-17f attempt 2, EMPTY skip_legs: no skip decision to cache, no remedy" "$BODY" pull_request "" "" "" 2 $S $OK $OK $OK $OK $OK 1 "test-webplat: SKIPPED" "cached from attempt 1"
tol "G1-17g attempt 2, skip_legs set, leg FAILED not skipped: no remedy" "$BODY" pull_request test-bun true true 2 $OK failure $OK $OK $OK $OK 1 "test-bun: FAILED" "cached from attempt 1"
# G1-18 a list with a foreign or empty member FIRST is invalid as a whole: the valid member after it is not tolerated (the `^` anchor)
for _l in "test-scripts,test-bun" "encryption-posture,test-bun" ",test-bun"; do
  tol "G1-18 list '$_l' with test-bun skipped: nothing tolerated" "$BODY" pull_request "$_l" true true 1 $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" "$TOL_MSG"
done
tol "G1-18b foreign-first list, the foreign leg itself skipped" "$BODY" pull_request "test-scripts,test-bun" true true 1 $OK $OK $S $OK $OK $OK 1 "test-scripts: SKIPPED" "test-scripts: $TOL_MSG"
tol "G1-18c foreign-first list (encryption-posture), the foreign leg itself skipped" "$BODY" pull_request "encryption-posture,test-bun" true true 1 $OK $OK $OK $OK $OK $S 1 "encryption-posture: SKIPPED" "encryption-posture: $TOL_MSG"

# G1-H1 (Guard 1 harness): mutate the body under test and require RED. Each named operation edits ONE condition of the tolerance; the
# row set above must catch it. A mutant that survives is labelled fixture-inadequate or equivalent.
cat > "$SANDBOX/tolmut.py" <<'PYM'
import sys
src, dst, op = sys.argv[1:4]
s = open(src).read()
def sub(old, new):
    global s
    if s.count(old) != 1:
        sys.stderr.write("anchor count %d for %r\n" % (s.count(old), old)); sys.exit(3)
    s = s.replace(old, new)
COND = '[[ "$EVENT_NAME" == "pull_request" && "$ACTIVE" == "true" && "$HEAD_SHA_OK" == "true" && "$ATTEMPT" == "1" && "$SKIP_LEGS" =~ $skip_re ]]'
# The body is the YAML block scalar, i.e. 10 columns left of the file: these anchors carry the BODY's indentation.
SIB = ("          skipped)\n"
       "            if [[ \"$tolerated\" == *\",${other%%:*},\"* ]]; then\n"
       "              concluded_siblings=$((concluded_siblings + 1))\n"
       "            fi\n"
       "            ;;\n")
REMNAMED = '",$SKIP_LEGS," == *",$shard,"*'
REMGATE = '"$ATTEMPT" != "1" && ' + REMNAMED
TOLMSG = 'echo "$shard: PR-AFFECTED-SKIP — skipped by pr-selection (active, attempt 1, head bound); not a failure" >&2\n    continue'
if op == "remove-tolerance":
    sub('if [[ "$tolerated" == *",$shard,"* ]]; then', 'if false; then')
elif op == "no-active":
    sub(COND, COND.replace('"$ACTIVE" == "true" && ', ""))
elif op == "no-event":
    sub(COND, COND.replace('"$EVENT_NAME" == "pull_request" && ', ""))
elif op == "no-head":
    sub(COND, COND.replace('"$HEAD_SHA_OK" == "true" && ', ""))
elif op == "no-attempt":
    sub(COND, COND.replace('"$ATTEMPT" == "1" && ', ""))
elif op == "no-regex":
    sub(COND, COND.replace(' && "$SKIP_LEGS" =~ $skip_re', ""))
elif op == "loose-active":
    sub('"$ACTIVE" == "true"', '"$ACTIVE" != "false"')
elif op == "substring":
    sub('*",${entry%%:*},"*) tolerated=', '*"${entry%%:*}"*) tolerated=')
elif op == "tolerate-still-fails":
    sub(TOLMSG, TOLMSG.replace("\n    continue", "\n    fail=1\n    continue"))
elif op == "siblings-not-concluded":
    sub(SIB, "")
elif op == "tolerate-anything-skipped":
    sub('if [[ "$tolerated" == *",$shard,"* ]]; then', 'if [[ "$tolerated" == *",$shard,"* || "$result" == "skipped" ]]; then')
elif op == "tolerate-failure":
    sub('if [[ "$tolerated" == *",$shard,"* ]]; then', 'if [[ "$tolerated" == *",$shard,"* || "$result" == "failure" ]]; then')
elif op == "skip-re-no-caret":
    sub("skip_re='^(", "skip_re='(")
elif op == "skip-re-no-dollar":
    sub(")*$'", ")*'")
elif op == "remedy-removed":
    sub('if [[ ' + REMGATE + ' ]]; then', 'if false; then')
elif op == "remedy-at-attempt-1":
    sub(REMGATE, REMNAMED)
elif op == "remedy-without-skip-legs":
    sub(REMGATE, '"$ATTEMPT" != "1"')
elif op == "remedy-any-shard":
    sub(REMGATE, '"$ATTEMPT" != "1" && -n "$SKIP_LEGS"')
elif op == "remedy-substring":
    sub(REMGATE, '"$ATTEMPT" != "1" && ",$SKIP_LEGS," == *"$shard"*')
elif op == "remedy-inverted":
    sub(REMGATE, '"$ATTEMPT" == "1" && ' + REMNAMED)
elif op == "final-trailing-comma":
    sub('tol_list="${tol_list%,}"', 'tol_list="${tol_list}"')
elif op == "final-leading-comma":
    sub('tol_list="${tolerated#,}"', 'tol_list="${tolerated}"')
elif op == "final-no-skip-legs":
    sub('; skip_legs=${SKIP_LEGS}"', '"')
elif op == "head-loose-empty":
    # ADR-276 S4 follow-up (#9729), Guard 3 row 1: HEAD_SHA_OK read as "not false", so its EMPTY spelling reads as bound
    sub('"$HEAD_SHA_OK" == "true"', '"$HEAD_SHA_OK" != "false"')
elif op == "compound-outer-removed-tolerate-skipped":
    # Guard 3 row 2, COMPOUND: the whole outer tolerance condition removed AND any skipped leg tolerated, applied together (the two existing single
    # operators, no-active/no-regex and tolerate-anything-skipped, each reach part of this; the compound is the named mutant, driven by the new p24 probes).
    sub(COND, 'true')
    sub('if [[ "$tolerated" == *",$shard,"* ]]; then', 'if [[ "$tolerated" == *",$shard,"* || "$result" == "skipped" ]]; then')
elif op == "banner-when-none-tolerated":
    # Guard 3 row 3: the tolerated banner printed when `tolerated` is "," (nothing was tolerated)
    sub('if [[ "$tolerated" != "," ]]; then', 'if true; then')
elif op == "six-green-reworded":
    sub('All six legs green (four shards', 'All six legs green (the four shards')
else:
    sys.stderr.write("unknown op\n"); sys.exit(2)
open(dst, "w").write(s)
PYM
mutate_tol() {  # $1=label $2=op ; the Guard 1 rows over the mutant: at least one must go RED
  local label="$1" op="$2" m="$SANDBOX/mut.tol.$RANDOM"
  MUT_TOTAL=$((MUT_TOTAL + 1))
  if ! python3 "$SANDBOX/tolmut.py" "$SANDBOX/body.pristine" "$m" "$op" 2>"$SANDBOX/tolmut.err"; then
    fail "MUTATION DID NOT LAND: $label ($(head -c 120 "$SANDBOX/tolmut.err"))"; return
  fi
  if cmp -s "$m" "$SANDBOX/body.pristine"; then fail "MUTATION DID NOT LAND: $label — byte-identical, so this row measured the BASELINE"; return; fi
  PROBE=1; PROBE_FAILS=0
  { tol "p0" "$m" pull_request test-bun true true 1 $OK $S $OK $OK $OK $OK 0 "test-bun: $TOL_MSG" "test-bun: SKIPPED"
    tol "p1" "$m" pull_request test-bun true true 1 $S $OK $OK $OK $OK $OK 1 "test-webplat: SKIPPED" ""
    tol "p2" "$m" merge_group test-bun true true 1 $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" "$TOL_MSG"
    tol "p3" "$m" pull_request test-bun false true 1 $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" "$TOL_MSG"
    tol "p3b" "$m" pull_request test-bun "" true 1 $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" "$TOL_MSG"
    tol "p4" "$m" pull_request test-bun true false 1 $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" "$TOL_MSG"
    tol "p5" "$m" pull_request test-bun true true 2 $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" "$TOL_MSG"
    tol "p6" "$m" pull_request "$ALL3" true true 1 $OK $OK $S $OK $OK $OK 1 "test-scripts: SKIPPED" "test-scripts: $TOL_MSG"
    tol "p6b" "$m" pull_request "$ALL3" true true 1 $OK $OK $OK $OK $OK $S 1 "encryption-posture: SKIPPED" "encryption-posture: $TOL_MSG"
    tol "p7" "$m" pull_request "test-scripts-heavy" true true 1 $OK $OK $S $OK $OK $OK 1 "test-scripts: SKIPPED" "test-scripts: $TOL_MSG"
    tol "p8" "$m" pull_request "test-bun,test-scripts" true true 1 $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" "$TOL_MSG"
    tol "p9" "$m" pull_request test-bun true true 1 $OK failure $OK $OK $OK $OK 1 "" "test-bun: $TOL_MSG"
    tol "p10" "$m" pull_request "test-webplat,test-bun" true true 1 $S $S cancelled $OK $OK $OK 1 "STOPPED ALONE" "cause not determined"
    tol "p11" "$m" pull_request test-bun true true 1 failure $S $OK $OK $OK $OK 1 "test-webplat: FAILED" ""
    tol "p12" "$m" pull_request test-bun True true 1 $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" "$TOL_MSG"
    tol "p13" "$m" pull_request "test-scripts,test-bun" true true 1 $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" "$TOL_MSG"
    tol "p14" "$m" pull_request ",test-bun" true true 1 $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" "$TOL_MSG"
    tol "p15" "$m" pull_request "encryption-posture,test-bun" true true 1 $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" "$TOL_MSG"
    tol "p16" "$m" pull_request "test-bun," true true 1 $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" "$TOL_MSG"
    tol "p17" "$m" pull_request test-bun true true 2 $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED — $REM_TXT" "$TOL_MSG"
    tol "p18" "$m" pull_request test-bun false true 1 $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" "cached from attempt 1"
    tol "p19" "$m" pull_request "" "" "" 2 $S $OK $OK $OK $OK $OK 1 "test-webplat: SKIPPED" "cached from attempt 1"
    tol "p19b" "$m" pull_request test-bun true true 2 $S $OK $OK $OK $OK $OK 1 "test-webplat: SKIPPED — the leg did not run" "cached from attempt 1"
    tol "p19c" "$m" pull_request test-scripts-heavy true true 2 $OK $OK $S $OK $OK $OK 1 "test-scripts: SKIPPED — the leg did not run" "cached from attempt 1"
    tol_exact "p20" "$m" test-bun $OK $S $OK "All legs green or $TOL_MSG tolerated (test-bun); skip_legs=test-bun"
    tol_exact "p21" "$m" "test-scripts-heavy,test-webplat" $S $OK $S "All legs green or $TOL_MSG tolerated (test-webplat,test-scripts-heavy); skip_legs=test-scripts-heavy,test-webplat"
    tol_exact "p22" "$m" test-bun $OK $OK $OK "$SIX_LINE"
    # ADR-276 S4 follow-up (#9729), Guard 3: NEW probe rows (this p-set never runs the main-line G1-8c rows). p23: HEAD_SHA_OK EMPTY (the p-set had only `false`).
    # p24: pull_request with the empty inputs a skipped pr-selection job produces, each gateable leg skipped. p25: the same empty inputs, all green.
    tol "p23" "$m" pull_request test-bun true "" 1 $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" "$TOL_MSG"
    tol "p24" "$m" pull_request "" "" "" 1 $S $OK $OK $OK $OK $OK 1 "test-webplat: SKIPPED" "$TOL_MSG"
    tol "p24b" "$m" pull_request "" "" "" 1 $OK $S $OK $OK $OK $OK 1 "test-bun: SKIPPED" "$TOL_MSG"
    tol "p24c" "$m" pull_request "" "" "" 1 $OK $OK $OK $S $OK $OK 1 "test-scripts-heavy: SKIPPED" "$TOL_MSG"
    tol "p25" "$m" pull_request "" "" "" 1 $OK $OK $OK $OK $OK $OK 0 "$SIX_LINE" "$TOL_MSG"
  } >/dev/null 2>&1
  PROBE=0
  if [ "$PROBE_FAILS" -gt 0 ]; then
    pass; MUT_KILLED=$((MUT_KILLED + 1))
  else
    fail "MUTANT SURVIVED: $label — no Guard 1 row detected this edit"
    MUT_SURVIVED+=("$label")
  fi
}
mutate_tol "G1-H1a remove the tolerance arm" remove-tolerance
mutate_tol "G1-H1b drop the ACTIVE term" no-active
mutate_tol "G1-H1c drop the EVENT_NAME term" no-event
mutate_tol "G1-H1d drop the HEAD_SHA_OK term" no-head
mutate_tol "G1-H1e drop the ATTEMPT term" no-attempt
mutate_tol "G1-H1f drop the SKIP_LEGS format check" no-regex
mutate_tol "G1-H1g loosen ACTIVE to != false" loose-active
mutate_tol "G1-H1h delimited match becomes a substring match" substring
mutate_tol "G1-H1i a tolerated skip still sets fail=1" tolerate-still-fails
mutate_tol "G1-H1j tolerated skips stop counting as concluded siblings" siblings-not-concluded
mutate_tol "G1-H1k every skipped leg is tolerated" tolerate-anything-skipped
mutate_tol "G1-H1l a failed leg is tolerated" tolerate-failure
# Anchors of skip_re. The caret mutant is what the foreign-FIRST rows (G1-18) exist to kill: `^` dropped, `test-scripts,test-bun` matches
# from its tail and the valid member is tolerated. The dollar mutant is killed by the trailing-comma row (G1-4e) and p16.
mutate_tol "G1-H1m drop the ^ anchor of skip_re" skip-re-no-caret
mutate_tol "G1-H1n drop the \$ anchor of skip_re" skip-re-no-dollar
# The re-run remedy (G1-17) and the exact final line (G1-16).
mutate_tol "G1-H1o the re-run remedy is removed" remedy-removed
mutate_tol "G1-H1p the re-run remedy also fires on attempt 1" remedy-at-attempt-1
mutate_tol "G1-H1q the re-run remedy fires with no skip decision (empty skip_legs)" remedy-without-skip-legs
mutate_tol "G1-H1r the re-run remedy is inverted (fires on attempt 1 only)" remedy-inverted
mutate_tol "G1-H1r2 the re-run remedy fires for any shard when skip_legs is non-empty (the pre-fix gate)" remedy-any-shard
mutate_tol "G1-H1r3 the re-run remedy matches the shard by substring, not delimited" remedy-substring
mutate_tol "G1-H1s the final line keeps its trailing comma" final-trailing-comma
mutate_tol "G1-H1t the final line keeps its leading comma" final-leading-comma
mutate_tol "G1-H1u the final line drops the skip_legs suffix" final-no-skip-legs
mutate_tol "G1-H1v the all-six sentence is reworded (byte identity)" six-green-reworded
# ADR-276 S4 follow-up (#9729), Guard 3 (matrix rows 1 to 3). Measured at review: p23 is the one probe H1w needs (without it H1w survives); H1x is the union of two
# existing operators and H1y is killed by the existing p1..p22, so p24, p24b, p24c and p25 are NOT additional kills. They are kept because they pin the state this PR
# creates (a skipped pr-selection: empty outputs, each gateable leg skipped, then all green) through the real body, and they are counted in MIN_ROWS, not credited as kill power.
mutate_tol "G1-H1w HEAD_SHA_OK loosened to != false (its empty spelling reads as bound)" head-loose-empty
mutate_tol "G1-H1x COMPOUND: the outer tolerance condition removed AND any skipped leg tolerated" compound-outer-removed-tolerate-skipped
mutate_tol "G1-H1y the tolerated banner printed when nothing was tolerated" banner-when-none-tolerated

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
# read by the aggregator body. It is counted separately (W5), not as a seventh leg. Likewise draft-light
# (#9728, ADR-276 S3): the aggregator reads its output once, through DRAFT_LIGHT (W6), never as a leg. Likewise pr-selection
# (#9729, ADR-276 S4 PR B): its outputs feed only the PR-AFFECTED-SKIP tolerance, through SKIP_LEGS/ACTIVE/HEAD_SHA_OK/ATTEMPT (W7).
print(len([x for x in n if x not in ("push-dedupe", "draft-light", "pr-selection")]))
PYN
)
if [ "$_nshards" -eq 6 ]; then pass; else
  fail "W2 the test job watches $_nshards legs, but this suite fixtures exactly 6 (four test-* shards + web-platform-build #8136 + encryption-posture #6907) — dropping a leg from needs: makes its result resolve to EMPTY, which falls straight into the *) arm, and every row here would still pass"
fi
# W5 — the one non-leg need is push-dedupe, exactly once, and the aggregator's env: never reads it. If the
# body ever read its output the stage-S2 claim "the aggregator is byte-identical" would be false.
_nonleg=$(python3 - "$_ciy" <<'PYX'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
job = d["jobs"]["test"]
n = job.get("needs") or []
n = [n] if isinstance(n, str) else list(n)
legs = {"test-webplat", "test-bun", "test-scripts", "test-scripts-heavy", "web-platform-build", "encryption-posture"}
extra = [x for x in n if x not in legs]
env = {}
for st in job.get("steps") or []:
    env.update(st.get("env") or {})
leak = [k for k, v in env.items() if "push-dedupe" in str(v)]
print(("extra=%s" % ",".join(sorted(extra))) + ((" env-reads-push-dedupe=%s" % ",".join(leak)) if leak else ""))
PYX
)
if [ "$_nonleg" = "extra=draft-light,pr-selection,push-dedupe" ]; then pass; else
  fail "W5 the test job's only non-leg needs must be draft-light, pr-selection and push-dedupe, and its env: must not read push-dedupe (got: $_nonleg)"
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

# W7 — the tolerance's four inputs are exactly the pr-selection outputs and the run attempt. A SKIP_LEGS or ACTIVE read from anything else
# (a literal, `.result`, a different job) would arm or disarm the tolerance without any row above noticing, since they hand the body its inputs.
_tol_env=$(python3 - "$_ciy" <<'PYT'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
st = [s for s in d["jobs"]["test"].get("steps") or [] if s.get("name") == "Aggregate shard results"][0]
env = st.get("env") or {}
want = {"SKIP_LEGS": "${{needs.pr-selection.outputs.skip_legs}}", "ACTIVE": "${{needs.pr-selection.outputs.active}}",
        "HEAD_SHA_OK": "${{needs.pr-selection.outputs.head_sha!=''&&needs.pr-selection.outputs.head_sha==github.event.pull_request.head.sha}}",
        "ATTEMPT": "${{github.run_attempt}}"}
bad = []
for k, v in want.items():
    if "".join(str(env.get(k, "")).split()) != v:
        bad.append("%s reads %r" % (k, env.get(k)))
print("; ".join(bad))
PYT
)
if [ -z "$_tol_env" ]; then pass; else fail "W7 the aggregator's PR-AFFECTED-SKIP inputs are mis-wired: $_tol_env"; fi

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
# + 89 Guard 1 executed rows (ADR-276 S4, #9729 PR B): 54 from the plan's G1-0..G1-15 matrix (G1-0 3, G1-1/5 2, G1-2 3, G1-3 9, G1-7b 7,
#      G1-9 6, G1-4 family 8, G1-7/7c 2, G1-12 2, G1-13 2, G1-14 1, G1-8 8 (4 events x 2 rows; `pull_request` joined at the job-level switch gate,
#      #9729 follow-up), G1-15 1) + 21 added by the review: G1-16 exact final line (4), G1-17 re-run remedy (12: 17 x3, 17b, 17b2, 17c-17g, 17h, 17i),
#      G1-18 foreign-first lists (5) + 14 G1-8c (#9729 follow-up: HEAD_SHA_OK in {empty, false} x [all green, 3 skipped legs, 3 failed legs] = 2 x 7)
# + 27 tolerance mutants G1-H1a..y plus H1r2, H1r3 (one row per mutant verdict; H1w..y are the #9729 follow-up's)         = 177
# +  7 wiring: W1, W2, W5, W6, W7, W3, W4                                                                                = 184
MIN_ROWS=184
if [ "$TOTAL" -lt "$MIN_ROWS" ]; then
  printf 'FAIL: assertion floor — %d rows executed, at least %d required. Rows were removed or a loop stopped early.\n' \
    "$TOTAL" "$MIN_ROWS" >&2
  exit 1
fi
# 4 mutate() + 5 mutate_arm() + 27 mutate_tol() = 36, the measured count.
MIN_MUTANTS=36
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
