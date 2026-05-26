#!/usr/bin/env bash
# Test harness for plugins/soleur/skills/code-to-prd/scripts/code-to-prd.sh (#2726).
#
# Pattern mirrors plugins/soleur/skills/incident/test/redact-sentinel.test.sh:
#   - set -uo pipefail (NOT -e — single test failure must not abort the suite)
#   - PASS/FAIL counter
#   - trap-based cleanup
#
# Test assertions (plan Phase 6):
#   1. All 3 fixture routes captured in the PRD.
#   2. HTTP method (`GET`) captured for `api/health/route.ts` (FR3).
#   3. Zero fixture-secret tokens appear in PRD output.
#   4. No env-var VALUE appears in PRD (FR5 — only names).
#   5. `## Coverage Caveats` block non-empty with all four subsections.
#   6. Both banners present (verbatim string match).
#   7. `### How to Read This PRD` subsection present in banner block.
#   8. `## Gap Analysis` section present (populated or SKIPPED).
#   9. MIT attribution footer present.
#   10. Layer 2 sentinel halts the write when a fresh secret is injected post-render (RED).
#   11. Layer 3 deletes the file if Layer 2 is bypassed via env var (RED).
#
# Plus plan AC tests:
#   - AC3: sentinel regex matches the fixture token.
#   - AC6: gitleaks-absent preflight abort.
#   - AC8: missing-package.json preflight abort.
#   - AC9: symlink rejection.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLUGIN_DIR="$(cd "${SKILL_DIR}/../.." && pwd)"
REPO_ROOT="$(cd "${PLUGIN_DIR}/../.." && pwd)"

CODE_TO_PRD="${SKILL_DIR}/scripts/code-to-prd.sh"
REDACT_SENTINEL="${PLUGIN_DIR}/skills/incident/scripts/redact-sentinel.sh"
FIXTURE="${SCRIPT_DIR}/fixture"

PASS=0
FAIL=0
TMP_DIR="$(mktemp -d -t code-to-prd-test.XXXXXX)"
trap 'rm -rf "${TMP_DIR}"' EXIT

assert_exit() {
  local label="$1" expected="$2" actual="$3"
  if [[ "${expected}" == "${actual}" ]]; then
    echo "PASS: ${label} (exit=${actual})"
    PASS=$((PASS + 1))
  else
    echo "FAIL: ${label} (expected exit=${expected}, got ${actual})"
    FAIL=$((FAIL + 1))
  fi
}

assert_grep() {
  local label="$1" pattern="$2" file="$3"
  if grep -qE -- "${pattern}" "${file}"; then
    echo "PASS: ${label}"
    PASS=$((PASS + 1))
  else
    echo "FAIL: ${label} (pattern '${pattern}' not found in ${file##*/})"
    FAIL=$((FAIL + 1))
  fi
}

assert_grep_fixed() {
  local label="$1" needle="$2" file="$3"
  if grep -qF -- "${needle}" "${file}"; then
    echo "PASS: ${label}"
    PASS=$((PASS + 1))
  else
    echo "FAIL: ${label} (literal '${needle}' not found in ${file##*/})"
    FAIL=$((FAIL + 1))
  fi
}

assert_no_grep() {
  local label="$1" needle="$2" file="$3"
  if grep -qF -- "${needle}" "${file}"; then
    echo "FAIL: ${label} (literal '${needle}' UNEXPECTEDLY present in ${file##*/})"
    FAIL=$((FAIL + 1))
  else
    echo "PASS: ${label}"
    PASS=$((PASS + 1))
  fi
}

assert_file_absent() {
  local label="$1" path="$2"
  if [[ ! -e "${path}" ]]; then
    echo "PASS: ${label}"
    PASS=$((PASS + 1))
  else
    echo "FAIL: ${label} (path ${path} still exists)"
    FAIL=$((FAIL + 1))
  fi
}

# ---------------------------------------------------------------------------
# Generate a clean PRD from the fixture (positive baseline for tests 1-9)
# ---------------------------------------------------------------------------
BASELINE_PRD="${TMP_DIR}/baseline-prd.md"
log="${TMP_DIR}/baseline.log"
bash "${CODE_TO_PRD}" "${FIXTURE}" "${BASELINE_PRD}" >"${log}" 2>&1
baseline_rc=$?
assert_exit "Baseline: code-to-prd against fixture exits 0" 0 "${baseline_rc}"

if [[ ! -f "${BASELINE_PRD}" ]]; then
  echo "FATAL: baseline PRD was not written; remaining tests skipped."
  echo "  See ${log}"
  cat "${log}" >&2
  echo "---"
  echo "PASS=${PASS} FAIL=${FAIL}"
  exit 1
fi

# Test 1 — all 3 fixture routes captured
assert_grep_fixed "T1.a: route '/' present"      '`/`'        "${BASELINE_PRD}"
assert_grep_fixed "T1.b: route '/about' present" '`/about`'   "${BASELINE_PRD}"
assert_grep_fixed "T1.c: route '/api/health' present" '`/api/health`' "${BASELINE_PRD}"

# Test 2 — GET method captured for api/health/route.ts (FR3)
assert_grep "T2: GET method captured for api/health" '\| `/api/health` \| `app/api/health/route\.ts` \| GET \|' "${BASELINE_PRD}"

# Test 3 — sentinel-clean: zero redaction-class matches in the PRD
sentinel_out="${TMP_DIR}/sentinel.out"
bash "${REDACT_SENTINEL}" "${BASELINE_PRD}" >"${sentinel_out}" 2>&1
assert_exit "T3: redact-sentinel exits 0 on baseline PRD (AC2)" 0 $?

# Test 4 — no env-var VALUE appears (we don't have .env.example yet — once
# Phase 9b lands, this becomes load-bearing; for now we assert the marker
# 'FIXTUREDONOTUSE' is absent, which is true under any flow).
assert_no_grep "T4: env-var VALUE 'FIXTUREDONOTUSE' absent (FR5)" "FIXTUREDONOTUSE" "${BASELINE_PRD}"

# Test 5 — Coverage Caveats: non-empty + 4 subsections
assert_grep_fixed "T5.a: '## Coverage Caveats' header present" '## Coverage Caveats' "${BASELINE_PRD}"
assert_grep_fixed "T5.b: 'Frameworks not scanned' subsection" '### Frameworks not scanned' "${BASELINE_PRD}"
assert_grep_fixed "T5.c: 'Extraction techniques used' subsection" '### Extraction techniques used' "${BASELINE_PRD}"
assert_grep_fixed "T5.d: 'Excluded by path filter' subsection" '### Excluded by path filter' "${BASELINE_PRD}"
assert_grep_fixed "T5.e: 'GDPR Art. 9 special-category disclaimer' subsection" '### GDPR Art. 9 special-category disclaimer' "${BASELINE_PRD}"

# Test 6 — both banners present (verbatim signature markers)
assert_grep_fixed "T6.a: due-diligence banner sentinel present" 'BANNER:DUE-DILIGENCE' "${BASELINE_PRD}"
assert_grep_fixed "T6.b: PII/confidentiality banner sentinel present" 'BANNER:PII-CONFIDENTIALITY' "${BASELINE_PRD}"

# Test 7 — How to Read This PRD subsection (FR7.1)
assert_grep_fixed "T7: '### How to Read This PRD' subsection present (FR7.1)" '### How to Read This PRD' "${BASELINE_PRD}"

# Test 8 — Gap Analysis section present (populated or SKIPPED)
assert_grep_fixed "T8.a: '## Gap Analysis' header present" '## Gap Analysis' "${BASELINE_PRD}"
assert_grep "T8.b: SKIPPED-or-populated body present" 'SKIPPED \(spec-flow-analyzer unavailable at|^# Gap Analysis' "${BASELINE_PRD}"

# Test 9 — MIT attribution footer
assert_grep_fixed "T9: MIT attribution footer present" 'alirezarezvani/claude-skills' "${BASELINE_PRD}"

# ---------------------------------------------------------------------------
# Synthetic Stripe-shape tokens — assembled at runtime to dodge gitleaks
# default-pack AND GitHub push-protection (learning 10df08e3: literal
# `sk_live_*` / `sk_test_*` tokens in committed prose are rejected at push
# time, separate from pre-commit gitleaks). All halves are inert alone.
# ---------------------------------------------------------------------------
SK_PFX="sk_l"
SK_TAIL="ive_REDTESTLAYER2FIXTUREALNUMSTRIPE0001"  # 36 alnum, no underscores
SYNTHETIC_LIVE="${SK_PFX}${SK_TAIL}"

# ---------------------------------------------------------------------------
# Test 10 — Layer 2 sentinel halts the write when a fresh secret would land.
# Synthesize a tampered fixture whose app/page.tsx carries the secret in a
# useState initial value — the State Shapes extractor lifts that line
# verbatim into the rendered PRD, giving Layer 2 something to react to.
# ---------------------------------------------------------------------------
TAMPERED="${TMP_DIR}/tampered-fixture"
cp -a "${FIXTURE}" "${TAMPERED}"
cat >"${TAMPERED}/app/page.tsx" <<EOF
/** Tampered landing page (Layer-2/3 RED test). */
import { useState } from "react";
export default function HomePage() {
  const [k, setK] = useState("${SYNTHETIC_LIVE}");
  return <pre>{k}</pre>;
}
EOF
# Initialize a tiny git repo so the walker sees the tampered file.
(
  cd "${TAMPERED}"
  git init -q
  git add -A
  git -c user.email=t@t -c user.name=t commit -q -m fixture --no-verify >/dev/null 2>&1 || true
)
T10_OUT="${TMP_DIR}/t10-prd.md"
t10_log="${TMP_DIR}/t10.log"
bash "${CODE_TO_PRD}" "${TAMPERED}" "${T10_OUT}" >"${t10_log}" 2>&1
t10_rc=$?
assert_exit "T10: Layer 2 halts write when secret present (AC4)" 1 "${t10_rc}"
assert_file_absent "T10: no PRD on disk after Layer 2 abort" "${T10_OUT}"

# ---------------------------------------------------------------------------
# Test 11 — Layer 3 catches what Layer 2 missed (RED test via env bypass).
# ---------------------------------------------------------------------------
T11_OUT="${TMP_DIR}/t11-prd.md"
t11_log="${TMP_DIR}/t11.log"
CODE_TO_PRD_SKIP_LAYER_2=1 bash "${CODE_TO_PRD}" "${TAMPERED}" "${T11_OUT}" >"${t11_log}" 2>&1
t11_rc=$?
assert_exit "T11: Layer 3 catches Layer-2-bypass and exits 1 (AC5)" 1 "${t11_rc}"
assert_file_absent "T11: Layer 3 deletes the leaked PRD" "${T11_OUT}"

# ---------------------------------------------------------------------------
# AC3 — sentinel regex matches the planned fixture token (loud guard against
# Kieran P0-1 underscore-in-regex correctness bug).
# ---------------------------------------------------------------------------
ac3_tmp="${TMP_DIR}/ac3.txt"
AC3_PFX="sk_t"
AC3_TAIL="est_FIXTUREDONOTUSESYNTHETICTOKEN123"
printf 'STRIPE_SECRET_KEY=%s%s\n' "${AC3_PFX}" "${AC3_TAIL}" >"${ac3_tmp}"
bash "${REDACT_SENTINEL}" "${ac3_tmp}" >/dev/null 2>&1
assert_exit "AC3: sentinel matches fixture token shape (no underscore in tail)" 1 $?

# ---------------------------------------------------------------------------
# AC6 — gitleaks-absent preflight abort.
# ---------------------------------------------------------------------------
ac6_log="${TMP_DIR}/ac6.log"
SCRUBBED_PATH="$(echo "${PATH}" | tr ':' '\n' | while read -r p; do
  [[ -z "${p}" ]] && continue
  if [[ -x "${p}/gitleaks" ]]; then continue; fi
  printf '%s:' "${p}"
done)"
PATH="${SCRUBBED_PATH%:}" bash "${CODE_TO_PRD}" "${FIXTURE}" "${TMP_DIR}/ac6-prd.md" >"${ac6_log}" 2>&1
ac6_rc=$?
assert_exit "AC6: gitleaks-absent preflight aborts with exit 2" 2 "${ac6_rc}"
assert_grep_fixed "AC6: error message mentions gitleaks" "gitleaks not found" "${ac6_log}"

# ---------------------------------------------------------------------------
# AC8 — missing-package.json preflight abort.
# ---------------------------------------------------------------------------
ac8_target="${TMP_DIR}/empty-dir"
mkdir -p "${ac8_target}"
ac8_log="${TMP_DIR}/ac8.log"
bash "${CODE_TO_PRD}" "${ac8_target}" "${TMP_DIR}/ac8-prd.md" >"${ac8_log}" 2>&1
ac8_rc=$?
assert_exit "AC8: missing-package.json preflight aborts with exit 2" 2 "${ac8_rc}"
assert_grep_fixed "AC8: error message includes the literal target path" "${ac8_target}" "${ac8_log}"

# ---------------------------------------------------------------------------
# AC9 — symlink rejection (FR2.1).
# Plant a symlink inside a copy of the fixture pointing at a sibling sensitive
# file; confirm the linked content does NOT enter the PRD.
# ---------------------------------------------------------------------------
ac9_target="${TMP_DIR}/sym-fixture"
cp -a "${FIXTURE}" "${ac9_target}"
ac9_sensitive="${TMP_DIR}/sensitive.txt"
printf 'CANARY_VALUE_SHOULD_NOT_APPEAR_IN_PRD\n' >"${ac9_sensitive}"
ln -s "${ac9_sensitive}" "${ac9_target}/leaked-link.txt"
(
  cd "${ac9_target}"
  git init -q
  git add -A
  git -c user.email=t@t -c user.name=t commit -q -m sym --no-verify >/dev/null 2>&1 || true
)
ac9_out="${TMP_DIR}/ac9-prd.md"
bash "${CODE_TO_PRD}" "${ac9_target}" "${ac9_out}" >"${TMP_DIR}/ac9.log" 2>&1
assert_no_grep "AC9: symlink target content NOT in PRD" "CANARY_VALUE_SHOULD_NOT_APPEAR_IN_PRD" "${ac9_out}"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "---"
echo "PASS=${PASS} FAIL=${FAIL}"
if (( FAIL > 0 )); then
  exit 1
fi
exit 0
