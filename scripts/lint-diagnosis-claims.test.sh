#!/usr/bin/env bash
# Tests for scripts/lint-diagnosis-claims.sh (#7242 / ADR-166).
#
# THE POINT OF THESE TESTS. This lint is a guard whose detection list RESTATES prose that
# lives elsewhere, which is the shape that fails GREEN when the list goes stale: the phrases
# drift, the scanner matches nothing, and a clean run reads as a clean repo. So the suite
# does not merely run the lint — it drives it over fixtures and asserts BOTH arms, including
# the verbatim historical line that this lint exists to have caught.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="$SCRIPT_DIR/lint-diagnosis-claims.sh"

PASS=0
FAIL=0
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  PASS: $desc"; PASS=$((PASS + 1));
  else echo "  FAIL: $desc"; echo "    expected: $expected"; echo "    actual:   $actual"; FAIL=$((FAIL + 1)); fi
}

FIX="$(mktemp -d -t lint-diag-fix.XXXXXXXX)"
HW="$SCRIPT_DIR/lint-diagnosis-claims.highwater"
HW_SAVE="$(mktemp -t lint-diag-hw.XXXXXXXX)"
cp "$HW" "$HW_SAVE"
# The ratchet cases below move the real committed baseline out of scripts/ to prove the
# missing-baseline and regression arms. An interrupt inside either window would otherwise
# leave the repo's baseline deleted or overwritten with 0, so the trap restores it — a
# guard whose own failure mode is corrupting the thing it guards is not a guard.
trap 'rm -rf "$FIX"; [[ -f "$HW_SAVE" ]] && cp "$HW_SAVE" "$HW"; rm -f "$HW_SAVE" "$HW.bak"' EXIT
# Every DIRS entry must exist or the scanner hard-errors (scope-loss guard), so the fixture
# tree mirrors all four.
mkdir -p "$FIX/.github/workflows" "$FIX/.github/actions/some-action" \
         "$FIX/scripts" "$FIX/apps/web-platform/infra"

# A permanent benign file, so the fixture tree is never EMPTY. Without it the walk finds
# zero files after the last `rm` and the vacuity floor fires — which would make "clean tree
# passes" fail, and worse would make the missing-baseline case's exit 2 ambiguous between
# "no baseline" and "scanned nothing". Two different hard errors must not be indistinguishable.
cat > "$FIX/.github/workflows/keeper.yml" <<'YAML'
name: keeper
jobs:
  x:
    steps:
      - run: |
          echo "::notice::the mirror completed and the digest matched."
YAML

census_of() { LINT_DIAGNOSIS_ROOT="$1" LINT_DIAGNOSIS_MIN_FILES=1 bash "$LINT" --census; }
# Which file tripped, not just how many. A count-only assertion cannot distinguish "the
# fixture I wrote to pin this scope tripped" from "some other fixture tripped", so a later
# edit that relocates a fixture keeps the count green while deleting the property.
hits_of() { LINT_DIAGNOSIS_ROOT="$1" LINT_DIAGNOSIS_MIN_FILES=1 bash "$LINT" --detail; }

echo "=== lint-diagnosis-claims.sh ==="

# ── ARM 1: the fixture that MUST trip ──────────────────────────────────────────────────
# This is the VERBATIM claim that shipped, blocked three releases, and sent the operator to
# rotate a credential the same job had already verified live. If the lint ever stops
# matching this line, the lint has stopped doing the one job it was built for.
cat > "$FIX/.github/workflows/offender.yml" <<'YAML'
name: offender
jobs:
  x:
    steps:
      - run: |
          echo "::error::docker login to zot failed. A 'websocket: bad handshake' line means Cloudflare Access refused the upgrade, which is the stale-service-token shape: run the drift check."
YAML
assert_eq "the historical offender trips the lint" "1" "$(census_of "$FIX")"

# It must trip in .github/actions/ too. That directory is UNLINTED by every other tool in
# the repo (lint-workflows.sh and lint-workflow-step-env-refs.py both scan workflows/*.yml
# only), which is precisely why the two offending lines there survived two prior fixes.
rm "$FIX/.github/workflows/offender.yml"
cat > "$FIX/.github/actions/some-action/action.yml" <<'YAML'
name: offender-action
runs:
  using: composite
  steps:
    - shell: bash
      run: |
        echo "::error::the bridge failed. Most likely cause: a service token was rotated and never reached Doppler."
YAML
assert_eq "an offender under .github/actions/ trips it (the unlinted directory)" "1" "$(census_of "$FIX")"
rm "$FIX/.github/actions/some-action/action.yml"

# It must trip under apps/web-platform/infra/ too — and on THIS phrasing.
#
# This case pins BOTH halves of #7310. The directory was out of scope, so
# `registry-userdata-budget.sh:131` told operators that "#7280's registry_rationale_strip is
# the fix" — a cause the job never measured, and a WRONG one: #7280 had merged 6 h 22 m
# earlier, the strip was already applied, and the real defect was in the gate's own render.
# The claim also reached the recut runbook, which is why unwinding it took two PRs (#7300,
# #7303). NOT claimed: that any operator acted on it — #7287 predates the message on main by
# six hours, so it cannot have been mis-steered by it.
#
# Widening the scope ALONE does not catch it. Measured: with apps/web-platform/infra in
# DIRS but no fix/cause alternative in CLAIM, this exact fixture scores 0 — the phrasing
# asserts a cause by prescribing its remedy ("X is the fix") and matched none of the
# existing alternatives. So reverting EITHER half makes this assertion fail, which is the
# property that keeps part 2 enforced rather than merely present.
cat > "$FIX/apps/web-platform/infra/registry-userdata-budget.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$stored_bytes" -gt "$cap" ]]; then
  echo "registry-userdata-budget: OVER CAP by $(( stored_bytes - cap )) bytes — #7280's registry_rationale_strip is the fix."
  exit 1
fi
SH
assert_eq "an offender under apps/web-platform/infra/ trips it (the directory AND the phrasing)" "1" "$(census_of "$FIX")"
# Identity, not cardinality. Without this the assertion above is satisfied by ANY single hit
# anywhere in the fixture tree — verified: relocating this fixture to .github/workflows/
# leaves the suite fully green while deleting the directory coverage it exists to pin.
assert_eq "…and the hit is attributed to the infra path (not merely 'one hit somewhere')" \
  "apps/web-platform/infra/registry-userdata-budget.sh:4" \
  "$(hits_of "$FIX" | sed 's/: .*//')"
rm "$FIX/apps/web-platform/infra/registry-userdata-budget.sh"

# ── ARM 1b: #7578 — the message assembled into a shell VARIABLE ────────────────────────
#
# THE VERBATIM LINE FROM THE INCIDENT. For two days from 2026-08-14 19:06:58Z this ran every
# 30 minutes naming two causes the run had measured FALSE — `rc=0` means the query SUCCEEDED,
# and the real state was Better Stack refusing WRITES (402) while the READ path answered 200.
#
# It was invisible to all THREE predicates, which is why a two-filter reading of this bug
# produces a fix that changes nothing:
#
#   1. OPERATOR_LINE — its helper-call alternative requires whitespace immediately before the
#      quote (`\s+"`). An assignment has `=` there. The uppercase shell-var convention is a
#      second, independent barrier (`^\s*[a-z_]`).
#   2. CLAIM — its phrase list did not model the em-dash appendix `— <cause> / <cause>`.
#   3. MEASURED — and this is the one nobody named: `VERDICT="TRANSIENT"` on the SAME LINE
#      matches `verdict=` case-insensitively, so even with 1 and 2 widened the line is
#      exonerated. Proximity is not evidence: a verdict variable nearby shows the job measured
#      SOMETHING, not that it measured the cause the appendix names — and here the measurement
#      it was next to (`rc=0`) CONTRADICTED that cause.
#
# The `VERDICT="TRANSIENT"; ` prefix is therefore LOAD-BEARING FIXTURE CONTEXT, not
# decoration. Drop it and this case passes under a two-filter fix, hiding the defect it
# exists to pin — measured: without the prefix, reverting the exoneration narrowing leaves
# the whole suite green.
cat > "$FIX/scripts/zot-restart-loop-alarm.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ -z "$CONTROL" ]]; then
  VERDICT="TRANSIENT"; DETAIL="recent ${WINDOW} empty AND control-marker query empty/errored (rc=${control_rc}) — Better Stack unreachable / creds unset"
  emit_and_exit 2
fi
SH
assert_eq "a message assembled into a shell variable trips it (#7578)" "1" "$(census_of "$FIX")"
assert_eq "…attributed to the assignment line, not merely 'one hit somewhere'" \
  "scripts/zot-restart-loop-alarm.sh:4" "$(hits_of "$FIX" | sed 's/: .*//')"
rm "$FIX/scripts/zot-restart-loop-alarm.sh"

# The SECOND carrier, after a compliant first. A check that stops at the first member is
# itself an instance of the class this lint exists to catch, so the sibling is pinned
# separately rather than assumed to follow. `NIC_VERDICT` is in the window here, which is the
# exoneration path this fixture pins — the sibling used `_VERDICT\b` rather than `verdict=`,
# so the two lines escaped through DIFFERENT alternatives of the same regex.
cat > "$FIX/scripts/nic-alarm.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
NIC_VERDICT="FIRE"
NIC_DETAIL_OK="newest boot_id=${newest}: nic_ok=true, converged within the bounded wait"
NIC_DETAIL="recent ${WINDOW} empty for SOLEUR_PRIVATE_NIC AND the control-marker query is empty/errored (rc=${control_rc}) — Better Stack unreachable / creds unset"
SH
assert_eq "the second carrier trips it too, past a compliant first (#7578)" "1" "$(census_of "$FIX")"
rm "$FIX/scripts/nic-alarm.sh"

# #7318: the helper-call alternative is ^-anchored, so a call on a shell CONTINUATION line
# is invisible. Same regex, same class, folded in here so the triage and the ratchet are paid
# once rather than twice.
cat > "$FIX/scripts/continuation.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
copy_image "$src" "$dst" \
  || degraded sign "$?" "the mirror did not land — the registry rewrite is the fix"
SH
assert_eq "a helper call on a continuation line trips it (#7318)" "1" "$(census_of "$FIX")"
rm "$FIX/scripts/continuation.sh"

# ── ARM 2: fixtures that MUST NOT trip ─────────────────────────────────────────────────
# A message that BRANCHES on a measured verdict is the fixed shape. Flagging it would make
# the lint punish the correction it is asking for.
cat > "$FIX/.github/workflows/measured.yml" <<'YAML'
name: measured
jobs:
  x:
    steps:
      - env:
          TOKEN_VERDICT: ${{ steps.pre.outputs.verdict || 'unmeasured' }}
        run: |
          echo "::error::the bridge failed. Most likely cause: see the measured verdict ${TOKEN_VERDICT}."
YAML
assert_eq "a message branching on a measured verdict does NOT trip" "0" "$(census_of "$FIX")"
rm "$FIX/.github/workflows/measured.yml"

# The explicit escape hatch, for a basis that is real but not visible in the block.
cat > "$FIX/.github/workflows/marked.yml" <<'YAML'
name: marked
jobs:
  x:
    steps:
      - run: |
          # MEASURED-BY: the preflight probe three steps up
          echo "::error::the bridge failed. Most likely cause: the credential, per the probe above."
YAML
assert_eq "an explicit MEASURED-BY marker does NOT trip" "0" "$(census_of "$FIX")"
rm "$FIX/.github/workflows/marked.yml"

# A COMMENT is documentation, not an operator-facing message. This repo now carries several
# comments that quote retracted claims in order to warn against them; flagging those would
# make the lint fight its own remediation.
cat > "$FIX/.github/workflows/commented.yml" <<'YAML'
name: commented
jobs:
  x:
    steps:
      - run: |
          # This used to say "which is the stale-service-token shape". It was false.
          echo "::error::the bridge failed."
YAML
assert_eq "a comment quoting a retracted claim does NOT trip" "0" "$(census_of "$FIX")"
rm "$FIX/.github/workflows/commented.yml"

# A message that reports an OBSERVATION rather than a cause is the other correct shape.
cat > "$FIX/.github/workflows/observed.yml" <<'YAML'
name: observed
jobs:
  x:
    steps:
      - run: |
          echo "::error::the bridge failed: the listener did not bind within 15s and nothing was pushed."
YAML
assert_eq "a purely observational message does NOT trip" "0" "$(census_of "$FIX")"
rm "$FIX/.github/workflows/observed.yml"

# The FAR SIDE of the #7310 alternative. Every other ARM-2 case tests an EXONERATION path
# (a verdict, a MEASURED-BY marker, a comment, an observation) — none tests the regex being
# too AGGRESSIVE, so before this fixture existed all four boundary-loosening mutations
# (drop the leading \b, drop the trailing \b, drop both, widen the closed adjective list to
# an open slot) survived the whole suite green. The only thing that reddened them was the
# live-repo assertion at the end, which is an accident of what the corpus happens to
# contain today, not a designed control.
#
# Every line below is a valid OPERATOR_LINE, so the ONLY reason each must score 0 is the
# CLAIM regex declining to match it.
cat > "$FIX/.github/workflows/nearmiss.yml" <<'YAML'
name: nearmiss
jobs:
  x:
    steps:
      - run: |
          echo "::notice::This the fix was applied cleanly."
          echo "::notice::Analysis the fix landed in the previous release."
          echo "::notice::that is the fixture the gate loads for this case."
          echo "::notice::the retry count is the fixed value we ship."
          echo "::notice::it is the causes list, not a diagnosis."
          echo "::notice::out-of-stock is the documented cause, per the runbook."
YAML
assert_eq "near-miss phrasings do NOT trip (both word boundaries + the closed adjective list)" \
  "0" "$(census_of "$FIX")"
rm "$FIX/.github/workflows/nearmiss.yml"

# ── ARM 2b: the far side of #7578 ──────────────────────────────────────────────────────
#
# Rows 1b above are all RED-direction, and a guard that rejects EVERYTHING satisfies every
# one of them. Only a must-PASS input that is NOT the canonical fixture can detect
# over-rejection, which is the failure mode the tightened predicate exists to avoid. Each
# case below differs from the offender in a way the contract explicitly permits.

# (a) The appendix class, with the deliberate marker. This is the escape hatch the narrowed
#     exoneration leaves open, and it is the ONLY one it leaves open for this class.
cat > "$FIX/scripts/marked-appendix.sh" <<'SH'
#!/usr/bin/env bash
# MEASURED-BY: the 402 refusal code read by betterstack-ingest-probe.sh two lines up
DETAIL="ingest probe returned 402 — quota exhausted"
SH
assert_eq "an appendix cause with an explicit MEASURED-BY does NOT trip" "0" "$(census_of "$FIX")"
rm "$FIX/scripts/marked-appendix.sh"

# (b) An appendix that INTERPOLATES the value it is explaining. This is the dominant shape in
#     the live corpus and it is honest: the message restates a measurement it just took.
#     Excluding `$` from the appendix span is what distinguishes it from the offender, whose
#     appendix was static prose that the interpolated rc=0 contradicted — measured: without
#     the exclusion the live census is 19 rather than 12, and all 7 of the difference are
#     this shape.
cat > "$FIX/scripts/interpolating-appendix.sh" <<'SH'
#!/usr/bin/env bash
code="$(curl -so /dev/null -w '%{http_code}' "$url")"
echo "ZOT_GATE: /v2/ probe http=$code — GHCR path ($code means zot unreachable)"
SH
assert_eq "an appendix interpolating its own measurement does NOT trip" "0" "$(census_of "$FIX")"
rm "$FIX/scripts/interpolating-appendix.sh"

# (c) THE REGRESSION GUARD FOR THE NARROWED EXONERATION. The narrowing applies to the APPENDIX
#     class only; a claim matched by CLAIM's pre-existing phrase list must keep the inferred
#     MEASURED semantics it has today. Without this case, narrowing the exoneration for ALL
#     claims would pass the entire suite while reddening the live tree for a dozen messages
#     that were correctly exonerated before this PR — a fix that breaks the thing it extends.
cat > "$FIX/.github/workflows/phrase-with-inferred-evidence.yml" <<'YAML'
name: phrase-with-inferred-evidence
jobs:
  x:
    steps:
      - env:
          TOKEN_VERDICT: ${{ steps.pre.outputs.verdict || 'unmeasured' }}
        run: |
          echo "::error::the push failed. Most likely cause: ${TOKEN_VERDICT}."
YAML
assert_eq "a phrase-list claim keeps its inferred exoneration (the narrowing is appendix-only)" \
  "0" "$(census_of "$FIX")"
rm "$FIX/.github/workflows/phrase-with-inferred-evidence.yml"

# The path-based test exclusion, pinned. It was `/test/` — which matched NOTHING, because
# the directories that exist are `tests/`, `test-fixtures/` and `fixtures/`. A guard whose
# name implies coverage it does not have is the shape this lint exists to stop, so the rule
# is now `/tests?/` and this fixture is what makes that load-bearing: without it, reverting
# to the singular form is an invisible no-op.
mkdir -p "$FIX/apps/web-platform/infra/tests"
cat > "$FIX/apps/web-platform/infra/tests/harness.sh" <<'SH'
#!/usr/bin/env bash
echo "::error::the probe aborted. Most likely cause: something nobody checked."
SH
assert_eq "a helper under a tests/ directory is out of scope (the rule is /tests?/, not /test/)" \
  "0" "$(census_of "$FIX")"
rm -rf "$FIX/apps/web-platform/infra/tests"

# ── The ratchet mechanics ──────────────────────────────────────────────────────────────
# A MISSING baseline must be a hard error (exit 2), never a pass. Precedent:
# lint-trap-tempfile-ownership.py. A ratchet whose baseline vanished would otherwise
# certify any population at all.
# HW + HW_SAVE are set at the top of the file so the EXIT trap can restore the committed
# baseline if either window below is interrupted.
saved="$HW_SAVE"
mv "$HW" "$HW.bak"
set +e
LINT_DIAGNOSIS_ROOT="$FIX" LINT_DIAGNOSIS_MIN_FILES=1 bash "$LINT" >/dev/null 2>&1
rc_missing=$?
set -e
mv "$HW.bak" "$HW"
assert_eq "a missing baseline is a hard error, not a pass" "2" "$rc_missing"

# A regression above the baseline must FAIL.
#
# The baseline is PINNED TO 0 for this case rather than inherited from the committed file.
# An earlier version relied on the live baseline being 0, so the moment the ratchet moved to
# 1 the single-offender fixture merely EQUALLED it and the case silently inverted — a test
# for "a regression fails" that passes when nothing regresses is worse than no test. Pinning
# makes the case independent of wherever the ratchet currently sits.
cat > "$FIX/.github/workflows/offender2.yml" <<'YAML'
name: offender2
jobs:
  x:
    steps:
      - run: |
          echo "::error::it broke. Most likely cause: something nobody checked."
YAML
printf '0\n' > "$HW"
set +e
LINT_DIAGNOSIS_ROOT="$FIX" LINT_DIAGNOSIS_MIN_FILES=1 bash "$LINT" >/dev/null 2>&1
rc_regress=$?
set -e
cp "$saved" "$HW"
assert_eq "a count above the baseline fails the build" "1" "$rc_regress"
rm "$FIX/.github/workflows/offender2.yml"

# ...and a clean tree passes.
set +e
LINT_DIAGNOSIS_ROOT="$FIX" LINT_DIAGNOSIS_MIN_FILES=1 bash "$LINT" >/dev/null 2>&1
rc_clean=$?
set -e
assert_eq "a tree at or below the baseline passes" "0" "$rc_clean"
# NOTE: $saved is $HW_SAVE and the EXIT trap still needs it — do not remove it here.

# ANTI-VACUITY: a walk that finds nothing must be a hard error, not a clean bill. os.walk
# on a missing tree yields nothing, so a rename or an extension typo would otherwise
# certify silence forever — "zero offenders" and "walked zero files" must not be the same
# answer.
#
# ALL FOUR scoped directories are created here, deliberately. If only one existed, the
# scope-loss guard below would exit 2 first and this case would pass for a reason that has
# nothing to do with vacuity — a green that proves the wrong proposition.
empty_root="$(mktemp -d -t lint-diag-empty.XXXXXXXX)"
mkdir -p "$empty_root/.github/workflows" "$empty_root/.github/actions" \
         "$empty_root/scripts" "$empty_root/apps/web-platform/infra"
set +e
LINT_DIAGNOSIS_ROOT="$empty_root" bash "$LINT" >/dev/null 2>&1
rc_vacuous=$?
set -e
rm -rf "$empty_root"
assert_eq "a walk that scans no files is a hard error, not a clean pass" "2" "$rc_vacuous"

# SCOPE LOSS is its own hard error, distinct from vacuity. MIN_FILES is a floor over the
# TOTAL, so it cannot see one directory disappearing while the rest still clear it —
# measured before this guard existed: renaming the infra entry dropped all 71 of its files
# and the run still printed `OK — 1 unmeasured causal claims`.
#
# The tree carries a real file on purpose. With it empty, the run exits 2 via the vacuity
# floor whether or not the scope guard exists — verified: deleting the guard left this case
# green, so it was proving the wrong proposition. The file makes the walk non-vacuous, so
# exit 2 here can ONLY come from the missing directory.
partial_root="$(mktemp -d -t lint-diag-partial.XXXXXXXX)"
mkdir -p "$partial_root/.github/workflows" "$partial_root/.github/actions" \
         "$partial_root/scripts"   # apps/web-platform/infra deliberately absent
cat > "$partial_root/.github/workflows/keeper.yml" <<'YAML'
name: keeper
jobs:
  x:
    steps:
      - run: |
          echo "::notice::the mirror completed and the digest matched."
YAML
set +e
LINT_DIAGNOSIS_ROOT="$partial_root" LINT_DIAGNOSIS_MIN_FILES=1 bash "$LINT" >/dev/null 2>&1
rc_scope=$?
set -e
rm -rf "$partial_root"
assert_eq "a missing DIRS entry is a hard error, not a quietly smaller walk" "2" "$rc_scope"

# ── The live repo ──────────────────────────────────────────────────────────────────────
# The gate's own invocation. Kept last so a fixture failure above is not mistaken for a
# repo regression.
set +e
bash "$LINT" >/dev/null 2>&1
rc_live=$?
set -e
assert_eq "the live repo is at or below its committed baseline" "0" "$rc_live"

# HARNESS SELF-CHECK. The count floor below sees assertions that RAN; it cannot see
# assert_eq always PASSING. Measured: changing its condition to `if true` leaves the suite
# at "12 passed, 0 failed", exit 0, with every comparison disabled. So prove the comparator
# can still both pass and fail, then subtract the two probes from the totals.
#
# Both probes are silenced: the mismatched one legitimately prints a "FAIL:" line, and a
# log carrying a FAIL that is not a failure is the same defect class this lint exists to
# stop. Only the verdict below is reported.
_p0=$PASS; _f0=$FAIL
assert_eq "__self-check-match" "x" "x" >/dev/null 2>&1
assert_eq "__self-check-mismatch" "x" "y" >/dev/null 2>&1
if [[ $((PASS - _p0)) -ne 1 || $((FAIL - _f0)) -ne 1 ]]; then
  echo "FAIL: assert_eq is not discriminating (PASS +$((PASS - _p0)), FAIL +$((FAIL - _f0)); expected +1/+1)." >&2
  exit 1
fi
PASS=$_p0; FAIL=$_f0
echo "  PASS: the harness's own comparator still discriminates"
PASS=$((PASS + 1))

echo "=== Results: $PASS passed, $FAIL failed ==="

# ANTI-VACUITY DISPATCH FLOOR — see zot-mirror-diagnosis.test.sh. Neutering assert_eq
# yields "0 passed, 0 failed" and exit 0, and test-all.sh reads only the exit code.
#
# Set to the FULL current count, not a slack value. A floor left trailing its population
# re-opens the hole it was built to close: at 9-against-12 this suite's own newest
# assertion could be deleted and the floor would not notice (verified — 11 passed, exit 0).
# It stays `-lt` (a floor, never `-eq`), so ADDING assertions is free; only deletion reds.
MIN_ASSERTIONS=17   # full count of a green run; raise in lockstep when adding assertions
if [[ $((PASS + FAIL)) -lt "$MIN_ASSERTIONS" ]]; then
  echo "FAIL: only $((PASS + FAIL)) assertions ran, expected >= ${MIN_ASSERTIONS}." >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]]
