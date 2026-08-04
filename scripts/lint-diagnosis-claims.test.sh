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
trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/.github/workflows" "$FIX/.github/actions/some-action"

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

# ── The ratchet mechanics ──────────────────────────────────────────────────────────────
# A MISSING baseline must be a hard error (exit 2), never a pass. Precedent:
# lint-trap-tempfile-ownership.py. A ratchet whose baseline vanished would otherwise
# certify any population at all.
HW="$SCRIPT_DIR/lint-diagnosis-claims.highwater"
saved="$(mktemp)"; cp "$HW" "$saved"
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
rm -f "$saved"

# ANTI-VACUITY: a walk that finds nothing must be a hard error, not a clean bill. os.walk
# on a missing tree yields nothing, so a rename or an extension typo would otherwise
# certify silence forever — "zero offenders" and "walked zero files" must not be the same
# answer.
empty_root="$(mktemp -d -t lint-diag-empty.XXXXXXXX)"
mkdir -p "$empty_root/.github/workflows"
set +e
LINT_DIAGNOSIS_ROOT="$empty_root" bash "$LINT" >/dev/null 2>&1
rc_vacuous=$?
set -e
rm -rf "$empty_root"
assert_eq "a walk that scans no files is a hard error, not a clean pass" "2" "$rc_vacuous"

# ── The live repo ──────────────────────────────────────────────────────────────────────
# The gate's own invocation. Kept last so a fixture failure above is not mistaken for a
# repo regression.
set +e
bash "$LINT" >/dev/null 2>&1
rc_live=$?
set -e
assert_eq "the live repo is at or below its committed baseline" "0" "$rc_live"

echo "=== Results: $PASS passed, $FAIL failed ==="

# ANTI-VACUITY DISPATCH FLOOR — see zot-mirror-diagnosis.test.sh. Neutering assert_eq
# yields "0 passed, 0 failed" and exit 0, and test-all.sh reads only the exit code.
MIN_ASSERTIONS=9   # derived from a green run (11 at time of writing), with headroom
if [[ $((PASS + FAIL)) -lt "$MIN_ASSERTIONS" ]]; then
  echo "FAIL: only $((PASS + FAIL)) assertions ran, expected >= ${MIN_ASSERTIONS}." >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]]
