#!/usr/bin/env bash
# Unit suite for scripts/derive-app-domain-base.sh — the shared APP_DOMAIN_BASE derivation.
#
# ── WHAT THIS PINS, AND WHY IT IS NOT A TYPO TEST ───────────────────────────────────────────
# The D10 authorization gate for `registry-luks-recut` derived its /health URL from a Doppler
# secret named APP_DOMAIN_BASE. That secret exists in NO config of the `soleur` project —
# measured 2026-08-06 across all 13. The name is real, but it is a HOST ENV VAR that
# `server.tf` sets from `var.app_domain_base`; it was never a Doppler key. Both D10 arms read
# it with no fallback and fail closed on empty, so the gate aborted at PREPARE before it could
# ever reach its own destroy-guard — the dispatch was unfireable during exactly the incident it
# exists to recover from.
#
# The fix inverts the provenance: read the COMMITTED variable Terraform actually applied. That
# makes `variables.tf` the causal source rather than a derived copy, so this suite's job is to
# prove the derivation is correct AND that a malformed value can never reach a URL.
#
# ── HARNESS CONTRACT ────────────────────────────────────────────────────────────────────────
# Accumulate-then-exit. Every case runs the REAL script against a fixture `variables.tf` in a
# per-run mktemp sandbox — never a fixed path, because parallel worktrees are this repo's
# documented workflow and a name derived from this file is a pure function of it.
#
# Three authoring traps this file deliberately avoids (all documented in work/SKILL.md):
#   1. A deliberately-nonzero command inside `$( )` aborts under `set -e` BEFORE fail() prints.
#      Every script invocation is wrapped `rc=0; out=$(…) || rc=$?`.
#   2. A loop over an empty data source exits 0 with ZERO coverage. CASES_RUN is reconciled
#      against a minimum-cardinality floor at the end.
#   3. `producer | grep -q` under pipefail can exit 141 (SIGPIPE) on an early match, which
#      fails OPEN on a negative assertion. Assertions grep FILES directly or use bash `[[ ]]`.
export TMPDIR="${TMPDIR:-/var/tmp}"

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="${SCRIPT_DIR}/derive-app-domain-base.sh"

passes=0
fails=0
CASES_RUN=0

pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { fails=$((fails + 1)); printf '  FAIL %s\n' "$1"; }

SB="$(mktemp -d)" || { printf 'harness: mktemp -d failed\n' >&2; exit 2; }
trap 'rm -rf "$SB"' EXIT

# Writes a variables.tf fixture whose `app_domain_base` default is $2, into dir $1.
# Deliberately includes a sibling variable so the anchored match is exercised on every case.
write_fixture() {
  local dir="$1" value="$2"
  mkdir -p "$dir" || return 1
  cat > "${dir}/variables.tf" <<EOF
variable "unrelated_before" {
  description = "noise"
  type        = string
  default     = "ignore-me"
}

variable "app_domain_base" {
  description = "Base domain for the application (e.g., soleur.ai)"
  type        = string
  default     = "${value}"
}

variable "unrelated_after" {
  description = "noise"
  type        = string
  default     = "ignore-me-too"
}
EOF
}

# run_sut <fixture-path> -> sets RC, OUT, ERRTEXT
run_sut() {
  local target="$1"
  local errfile
  errfile="$(mktemp)" || return 1
  RC=0
  OUT="$(bash "$SUT" "$target" 2>"$errfile")" || RC=$?
  ERRTEXT="$(cat "$errfile")"
  rm -f "$errfile"
  CASES_RUN=$((CASES_RUN + 1))
}

# ── T1: the committed default resolves ──────────────────────────────────────────────────────
write_fixture "${SB}/t1" "soleur.ai"
run_sut "${SB}/t1/variables.tf"
[[ "$RC" -eq 0 ]] && pass "T1 exit 0 on a well-formed default" || fail "T1 expected exit 0, got $RC"
[[ "$OUT" == "soleur.ai" ]] && pass "T1 stdout is the base" || fail "T1 stdout expected 'soleur.ai', got '$OUT'"
[[ "$ERRTEXT" == *"${SB}/t1/variables.tf"* ]] && pass "T1 stderr resolution line names the source file" \
  || fail "T1 stderr did not name the source file: $ERRTEXT"

# ── T2: no hardcoded domain — a different value resolves just as well ───────────────────────
write_fixture "${SB}/t2" "dev.soleur.ai"
run_sut "${SB}/t2/variables.tf"
[[ "$RC" -eq 0 && "$OUT" == "dev.soleur.ai" ]] && pass "T2 a non-canonical base resolves (no hardcoded domain)" \
  || fail "T2 expected 'dev.soleur.ai' exit 0, got '$OUT' rc=$RC"

# ── T3: missing file is fatal and names the path ────────────────────────────────────────────
run_sut "${SB}/nope/variables.tf"
[[ "$RC" -ne 0 ]] && pass "T3 missing file exits non-zero" || fail "T3 expected non-zero for a missing file"
[[ "$ERRTEXT" == *"::error::"* && "$ERRTEXT" == *"${SB}/nope/variables.tf"* ]] \
  && pass "T3 ::error:: names the missing path" || fail "T3 ::error:: did not name the path: $ERRTEXT"

# ── T4: file present, variable absent, is fatal and names the variable ──────────────────────
mkdir -p "${SB}/t4"
cat > "${SB}/t4/variables.tf" <<'EOF'
variable "something_else" {
  type    = string
  default = "soleur.ai"
}
EOF
run_sut "${SB}/t4/variables.tf"
[[ "$RC" -ne 0 ]] && pass "T4 absent variable exits non-zero" || fail "T4 expected non-zero when the variable is absent"
[[ "$ERRTEXT" == *"app_domain_base"* ]] && pass "T4 ::error:: names the variable" \
  || fail "T4 error did not name app_domain_base: $ERRTEXT"

# ── T5-T9: malformed shapes are fatal, each asserted separately ─────────────────────────────
# Separate cases (not a loop over one fixture) so a guard that catches only one shape cannot
# report the whole class as covered.
assert_malformed() {
  local label="$1" value="$2" dir="${SB}/mal_$3"
  write_fixture "$dir" "$value"
  run_sut "${dir}/variables.tf"
  [[ "$RC" -ne 0 ]] && pass "${label} rejected" || fail "${label} was ACCEPTED (rc=0, out='$OUT') — a malformed base would reach a URL"
}
assert_malformed "T5 scheme (https://soleur.ai)" "https://soleur.ai" t5
assert_malformed "T6 slash (soleur.ai/x)"        "soleur.ai/x"       t6
assert_malformed "T7 whitespace (sole ur.ai)"    "sole ur.ai"        t7
assert_malformed "T8 no dot (soleurai)"          "soleurai"          t8
assert_malformed "T9 app. prefix (app.soleur.ai)" "app.soleur.ai"    t9

# ── T10: a sibling declared BEFORE the real one must not be selected ────────────────────────
mkdir -p "${SB}/t10"
cat > "${SB}/t10/variables.tf" <<'EOF'
variable "app_domain_base_legacy" {
  description = "a prefix-matching sibling declared first"
  type        = string
  default     = "legacy.example.com"
}

variable "app_domain_base" {
  description = "the real one"
  type        = string
  default     = "soleur.ai"
}
EOF
run_sut "${SB}/t10/variables.tf"
[[ "$OUT" == "soleur.ai" ]] && pass "T10 anchored match skips the prefix-matching sibling" \
  || fail "T10 selected the wrong variable: got '$OUT' (expected soleur.ai)"

# ── T11: stdout carries ONLY the base ───────────────────────────────────────────────────────
write_fixture "${SB}/t11" "soleur.ai"
run_sut "${SB}/t11/variables.tf"
[[ "$(printf '%s' "$OUT" | wc -l)" -eq 0 ]] && pass "T11 stdout is a single line (no trailing annotations)" \
  || fail "T11 stdout carried extra lines: '$OUT'"
[[ "$OUT" != *"derive-app-domain-base"* ]] && pass "T11 the resolution line is NOT on stdout" \
  || fail "T11 diagnostics leaked onto stdout: '$OUT'"

# ── T12: the positional parameter is honoured ───────────────────────────────────────────────
# Distinct value from every other fixture, so honouring $1 is the only way to produce it.
write_fixture "${SB}/t12" "pinned.example.org"
run_sut "${SB}/t12/variables.tf"
[[ "$OUT" == "pinned.example.org" ]] && pass "T12 \$1 selects the fixture" \
  || fail "T12 did not honour \$1: got '$OUT'"

# ── T13: TF_VAR_app_domain_base overrides the committed default ─────────────────────────────
# Terraform's own precedence. Without this tier the script reports "what Terraform WOULD apply
# absent an override" rather than "what Terraform applied", which is the plan's whole claim.
write_fixture "${SB}/t13" "soleur.ai"
errfile13="$(mktemp)"
RC13=0
OUT13="$(TF_VAR_app_domain_base="override.example.net" bash "$SUT" "${SB}/t13/variables.tf" 2>"$errfile13")" || RC13=$?
rm -f "$errfile13"
CASES_RUN=$((CASES_RUN + 1))
[[ "$RC13" -eq 0 && "$OUT13" == "override.example.net" ]] && pass "T13 TF_VAR override wins over the committed default" \
  || fail "T13 override ignored: got '$OUT13' rc=$RC13"

# ── T14: a malformed OVERRIDE is fatal too ──────────────────────────────────────────────────
# The shape guard must sit at the consumption point, after precedence is resolved — not only
# on the committed-default branch.
write_fixture "${SB}/t14" "soleur.ai"
RC14=0
OUT14="$(TF_VAR_app_domain_base="https://bad.example.net" bash "$SUT" "${SB}/t14/variables.tf" 2>/dev/null)" || RC14=$?
CASES_RUN=$((CASES_RUN + 1))
[[ "$RC14" -ne 0 ]] && pass "T14 a malformed TF_VAR override is rejected" \
  || fail "T14 malformed override ACCEPTED (out='$OUT14') — the guard is on the wrong branch"

# ── T15: CWD-independence ───────────────────────────────────────────────────────────────────
# Several workflow steps set `working-directory:`, and the discoverability contract requires
# the script to run from any checkout. Invoke from an unrelated CWD with a RELATIVE-free
# absolute fixture and assert an identical answer.
write_fixture "${SB}/t15" "cwdproof.example.com"
RC15=0
OUT15="$(cd "$SB" && bash "$SUT" "${SB}/t15/variables.tf" 2>/dev/null)" || RC15=$?
CASES_RUN=$((CASES_RUN + 1))
[[ "$RC15" -eq 0 && "$OUT15" == "cwdproof.example.com" ]] && pass "T15 derivation is CWD-independent" \
  || fail "T15 CWD-dependent: got '$OUT15' rc=$RC15"

# ── T16: the default path resolves with no argument ─────────────────────────────────────────
# Pins the zero-argument contract the workflow steps actually use.
RC16=0
OUT16="$(cd / && bash "$SUT" 2>/dev/null)" || RC16=$?
CASES_RUN=$((CASES_RUN + 1))
[[ "$RC16" -eq 0 && -n "$OUT16" ]] && pass "T16 zero-arg invocation resolves the repo's own variables.tf" \
  || fail "T16 zero-arg invocation failed: got '$OUT16' rc=$RC16"

# ── Anti-vacuity floor ──────────────────────────────────────────────────────────────────────
# A loop or fixture source that silently produced nothing would otherwise exit 0 having
# asserted nothing at all.
if [[ "$CASES_RUN" -lt 16 ]]; then
  fail "anti-vacuity: only ${CASES_RUN} script invocations ran (expected >= 16)"
else
  pass "anti-vacuity floor: ${CASES_RUN} script invocations"
fi

printf '\n=== %d passed, %d failed ===\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]] || exit 1
