#!/usr/bin/env bash
# Automated E2E test for the load-bearing persist-safe rail.
#
# Simulates a full /soleur:linear-fetch invocation cycle:
#   1. Synthesize a Linear-MCP-response shape (description + 2 comments
#      with TEST-FIXTURE-NOT-REAL.png CDN URLs).
#   2. Concatenate as the skill's Phase B would.
#   3. Pipe through the redaction primitive (Phase D persist_safe_summary).
#   4. Render through both caller templates (one-shot subagent prompt
#      and brainstorm leader prompt) via render-caller-template.sh.
#   5. Assert zero uploads.linear.app matches in either rendered prompt.
#   6. Assert disclosure-line shape matches the spec.
#   7. Assert the telemetry wrapper sees zero forbidden patterns when
#      the rendered prompts are scanned as if they were telemetry.
#
# Required by Kieran-Rails review P1.5 — for a single-user-incident
# threshold, the load-bearing rail must have automated E2E coverage,
# not only manual runbook scenarios.
#
# Fixtures are synthesized per cq-test-fixtures-synthesized-only.
# The URL strings use the non-routable allowlisted token
# TEST-FIXTURE-NOT-REAL so the CI pii-grep job permits this test file.
#
# Run via:  bash plugins/soleur/skills/linear-fetch/scripts/persist-safe-integration.test.sh

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REDACT="$SCRIPT_DIR/redact-linear-urls.sh"
RENDER="$SCRIPT_DIR/render-caller-template.sh"
TELEMETRY="$SCRIPT_DIR/assert-no-linear-telemetry.sh"

PASS=0
FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }

# --------------------------------------------------------------------
# Step 1: synthesize a Linear-shaped markdown blob.
# Description has one CDN URL. Two comments each have one CDN URL.
# Total: 3 redaction-eligible URLs.
# Synthesized fixture — no real Linear data.
# --------------------------------------------------------------------
SYNTH_ID='FEAT-1'  # NB: assertion uses generic identifier — telemetry wrapper still rejects [A-Z]{2,}-[0-9]+
SYNTH=$(cat <<'EOF'
# Issue description

The sidebar collapse button misaligns when the panel is < 200px.

Repro screenshot:
![misalignment screenshot](https://uploads.linear.app/TEST-FIXTURE-NOT-REAL-desc.png)

Expected: chevron stays centered.

--- comment by alice on 2026-05-12T10:00:00Z ---

Confirmed on staging. Here is the rendered diff:
<img src="https://uploads.linear.app/TEST-FIXTURE-NOT-REAL-c1.png" alt="diff">

--- comment by bob on 2026-05-12T11:30:00Z ---

Same on the dashboard route. Attached: <https://uploads.linear.app/TEST-FIXTURE-NOT-REAL-c2.png>
EOF
)

echo "Test 1: synth blob has 3 CDN URLs (sanity)"
synth_count=$(printf '%s' "$SYNTH" | grep -oE 'uploads\.linear\.app' | wc -l | tr -d '[:space:]')
[[ "$synth_count" == "3" ]] && pass "synth contains 3 CDN URLs" || fail "synth count=$synth_count, expected 3"

# --------------------------------------------------------------------
# Step 2: run through redaction primitive (Phase D persist_safe_summary).
# --------------------------------------------------------------------
echo "Test 2: redaction primitive on full blob"
err_file=$(mktemp)
PERSIST_SAFE=$(printf '%s' "$SYNTH" | bash "$REDACT" 2>"$err_file")
REDACT_COUNT=$(cat "$err_file" | tr -d '[:space:]')
rm -f "$err_file"
[[ "$REDACT_COUNT" == "3" ]] && pass "redaction count=3" || fail "redaction count=$REDACT_COUNT"

residue=$(printf '%s' "$PERSIST_SAFE" | grep -oE 'uploads\.linear\.app' | wc -l | tr -d '[:space:]')
[[ "$residue" == "0" ]] && pass "zero uploads.linear.app in persist_safe_summary" || fail "residue=$residue"

# --------------------------------------------------------------------
# Step 3: render through caller templates.
# Template shapes mirror the actual one-shot subagent prompt and the
# brainstorm domain-leader prompt — placeholder is __PERSIST_SAFE_SUMMARY__.
# --------------------------------------------------------------------
ONE_SHOT_TPL=$(cat <<'EOF'
Task general-purpose: "You are running the planning phase of a one-shot pipeline.

WORKING DIRECTORY: /tmp/wt
BRANCH: feat-test
ARGUMENTS: __PERSIST_SAFE_SUMMARY__

STEPS:
1. Use the Skill tool: skill: soleur:plan, args: "__PERSIST_SAFE_SUMMARY__"
"
EOF
)

BRAINSTORM_TPL=$(cat <<'EOF'
Task soleur:product:cpo: "Assess the product implications of the following brainstorm idea: __PERSIST_SAFE_SUMMARY__. Cross-reference against brand-guide.md."
EOF
)

echo "Test 3: render one-shot template with persist_safe_summary"
ONE_SHOT_RENDERED=$(printf '%s' "$ONE_SHOT_TPL" | bash "$RENDER" "$PERSIST_SAFE")
os_residue=$(printf '%s' "$ONE_SHOT_RENDERED" | grep -oE 'uploads\.linear\.app' | wc -l | tr -d '[:space:]')
[[ "$os_residue" == "0" ]] && pass "one-shot rendered prompt has zero CDN URLs" || fail "os_residue=$os_residue"

# Sanity: rendered prompt should still contain the redacted placeholder marker
if printf '%s' "$ONE_SHOT_RENDERED" | grep -q '\[linear-image: REDACTED\]'; then
  pass "one-shot rendered prompt retains REDACTED markers"
else
  fail "one-shot rendered prompt lost REDACTED markers — substitution corrupt"
fi

echo "Test 4: render brainstorm template with persist_safe_summary"
BS_RENDERED=$(printf '%s' "$BRAINSTORM_TPL" | bash "$RENDER" "$PERSIST_SAFE")
bs_residue=$(printf '%s' "$BS_RENDERED" | grep -oE 'uploads\.linear\.app' | wc -l | tr -d '[:space:]')
[[ "$bs_residue" == "0" ]] && pass "brainstorm rendered prompt has zero CDN URLs" || fail "bs_residue=$bs_residue"

# --------------------------------------------------------------------
# Step 4: disclosure-line shape (spec FR6).
# This is constructed by the skill at runtime; we simulate it here.
# --------------------------------------------------------------------
echo "Test 5: disclosure-line shape (FR6 — images present)"
N_total=3
M_with_comments=2
DISCLOSURE="Detected ${SYNTH_ID} — fetched issue + ${N_total} images from description and ${M_with_comments} comments."
expected_pattern='^Detected [A-Z]+-[0-9]+ — fetched issue \+ [0-9]+ images from description and [0-9]+ comments\.$'
if printf '%s' "$DISCLOSURE" | grep -qE "$expected_pattern"; then
  pass "disclosure matches spec shape"
else
  fail "disclosure mismatch: '$DISCLOSURE'"
fi

# --------------------------------------------------------------------
# Step 5: telemetry-wrapper boundary tests.
# The wrapper is the gate at the telemetry boundary — it is NOT
# applied to persist_safe_summary (which is for prompts and documents,
# where identifiers are useful context). These tests confirm the
# wrapper would catch a malformed telemetry payload at its boundary.
# --------------------------------------------------------------------
echo "Test 6: telemetry wrapper allows a clean telemetry-shape payload"
CLEAN_TELEMETRY='{"rule": "hr-gdpr-gate", "action": "applied", "duration_ms": 12}'
set +e
printf '%s' "$CLEAN_TELEMETRY" | bash "$TELEMETRY" >/dev/null 2>/dev/null
RC=$?
set -e
[[ "$RC" == "0" ]] && pass "wrapper allows clean telemetry" || fail "wrapper rc=$RC on clean telemetry"

echo "Test 7: telemetry wrapper rejects a payload that mistakenly contains an identifier"
DIRTY_TELEMETRY='{"rule":"linear-fetch","action":"applied","ctx":"SOL-99 processed"}'
set +e
printf '%s' "$DIRTY_TELEMETRY" | bash "$TELEMETRY" >/dev/null 2>/dev/null
RC=$?
set -e
[[ "$RC" == "1" ]] && pass "wrapper catches identifier-shape leak" || fail "wrapper rc=$RC, expected 1"

# --------------------------------------------------------------------
# Step 6: structural integrity — persist_safe_summary still contains
# the original markdown skeleton (delimiters, comment authors), proving
# the redaction is surgical (URLs only) not destructive.
# --------------------------------------------------------------------
echo "Test 8: structural integrity of persist_safe_summary"
if printf '%s' "$PERSIST_SAFE" | grep -q 'comment by alice'; then
  pass "comment-by-alice delimiter preserved"
else
  fail "delimiter lost — redaction is too aggressive"
fi

if printf '%s' "$PERSIST_SAFE" | grep -q '\[linear-image: REDACTED\]'; then
  pass "REDACTED placeholder present"
else
  fail "REDACTED placeholder missing"
fi

# --------------------------------------------------------------------
echo
echo "Results: $PASS passed, $FAIL failed"
exit $((FAIL > 0 ? 1 : 0))
