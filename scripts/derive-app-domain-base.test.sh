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

# The explicit `return 0` is load-bearing, not decoration. Every call site below is written
# `[[ cond ]] && pass … || fail …`, which is NOT if-then-else: if `pass` itself exited non-zero
# the `|| fail` arm would ALSO run, double-counting one case as both a pass and a failure and
# corrupting the very accounting this harness exists to produce. `printf` can fail (EPIPE,
# ENOSPC), so pinning the status is what makes the idiom safe. shellcheck SC2015.
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; return 0; }
fail() { fails=$((fails + 1)); printf '  FAIL %s\n' "$1"; return 0; }

# The runbook instructs an operator to run this suite during an incident. An exported
# TF_VAR_app_domain_base would silently satisfy tier 1 for every fixture and report a wall of
# failures that are an artefact of the shell, not a defect. T13/T14 set it per-invocation.
unset TF_VAR_app_domain_base

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

# ── T17-T20: shapes a real variables.tf can take, which previously FALSE-ABORTED ────────────
# These are not hypothetical. `variables.tf` already carries validation blocks, and an abort
# here re-arms the original defect — the D10 gate failing before it reaches its destroy-guard —
# via a routine Terraform edit rather than a code change.
mkdir -p "${SB}/t17"
cat > "${SB}/t17/variables.tf" <<'EOF'
variable "app_domain_base" {
  type = string
  validation {
    condition     = can(regex("^[a-z]", var.app_domain_base))
    error_message = "must be lowercase"
  }
  default = "soleur.ai"
}
EOF
run_sut "${SB}/t17/variables.tf"
[[ "$RC" -eq 0 && "$OUT" == "soleur.ai" ]] && pass "T17 a validation{} block BEFORE default does not abort" \
  || fail "T17 false-abort on a nested block: rc=$RC out='$OUT'"

mkdir -p "${SB}/t18"
cat > "${SB}/t18/variables.tf" <<'EOF'
variable "app_domain_base" {
  default = "soleur.ai"   # the apex the app is served from
}
EOF
run_sut "${SB}/t18/variables.tf"
[[ "$RC" -eq 0 && "$OUT" == "soleur.ai" ]] && pass "T18 a trailing # comment on the default line does not abort" \
  || fail "T18 false-abort on an inline comment: rc=$RC out='$OUT'"

# The block terminator: a target variable with NO default must not inherit a later sibling's.
# This is the fixture that makes the brace-depth tracking load-bearing — without it, deleting
# the terminator or defeating it with indentation changes nothing observable.
mkdir -p "${SB}/t19"
cat > "${SB}/t19/variables.tf" <<'EOF'
variable "app_domain_base" {
  type = string
}

variable "unrelated_sibling" {
  default = "leaked.example.com"
}
EOF
run_sut "${SB}/t19/variables.tf"
[[ "$RC" -ne 0 ]] && pass "T19 a default from a LATER sibling does not bleed into the target block" \
  || fail "T19 bled a sibling's default: got '$OUT' (expected non-zero exit)"

# One-line block form. Also the shape that made the divergence guard below silently no-op.
mkdir -p "${SB}/t20"
printf 'variable "app_domain_base" { default = "oneline.example.com" }\n' > "${SB}/t20/variables.tf"
run_sut "${SB}/t20/variables.tf"
[[ "$RC" -eq 0 && "$OUT" == "oneline.example.com" ]] && pass "T20 a one-line variable block parses" \
  || fail "T20 one-line block: rc=$RC out='$OUT'"

# ── T21: an unquoted HCL expression must NOT be returned verbatim ───────────────────────────
# `default = local.base` contains a dot, so it passes every shape check and would fabricate
# https://app.local.base/health. A legal Terraform refactor must not silently redirect the gate.
mkdir -p "${SB}/t21"
printf 'variable "app_domain_base" { default = local.base }\n' > "${SB}/t21/variables.tf"
run_sut "${SB}/t21/variables.tf"
[[ "$RC" -ne 0 ]] && pass "T21 an unquoted HCL expression is rejected, not returned verbatim" \
  || fail "T21 returned an unquoted expression: '$OUT' — that is a fabricated hostname"

# ── T22-T25: injection shapes. T22 is the sharp one ─────────────────────────────────────────
# `x@evil.com` makes https://app.x@evil.com/health resolve to evil.com with `app.x` as
# userinfo. The D10 gate reads that host to DEFINE the restore set, and the bridge sends the
# production CF Access service token to it.
assert_malformed "T22 userinfo (@) host relocation"  "x@evil.com"      t22
assert_malformed "T23 case-varied app. prefix"       "App.soleur.ai"   t23
assert_malformed "T24 empty label (..)"              "a..b"            t24
assert_malformed "T25 leading hyphen"                "-soleur.ai"      t25

# ── T26: the guard must not be TIGHTER than a real domain needs ─────────────────────────────
# Every other accepted fixture draws from [a-z.] only, so a character-class tightening
# (reject hyphen / digit / uppercase) would pass unnoticed. This is the fixture on the far side
# of the transform.
write_fixture "${SB}/t26" "a1-base.example.com"
run_sut "${SB}/t26/variables.tf"
[[ "$RC" -eq 0 && "$OUT" == "a1-base.example.com" ]] && pass "T26 a legitimate base with digits and hyphens is ACCEPTED" \
  || fail "T26 over-rejected a valid domain: rc=$RC out='$OUT'"

# ── T27-T28: the app_domain divergence guard ────────────────────────────────────────────────
# `app_domain` is the variable that HAS a live override lever (APP_DOMAIN is present in Doppler
# prd_terraform, so TF_VAR_app_domain is injected on every apply); `app_domain_base` has none.
# A domain move therefore shifts production while this derivation keeps returning the old base.
mkdir -p "${SB}/t27"
cat > "${SB}/t27/variables.tf" <<'EOF'
variable "app_domain_base" {
  default = "soleur.ai"
}
variable "app_domain" { default = "app.example.org" }
EOF
run_sut "${SB}/t27/variables.tf"
[[ "$RC" -ne 0 ]] && pass "T27 a divergent app_domain aborts (wrong-host read becomes loud)" \
  || fail "T27 accepted a divergent app_domain: '$OUT' — the gate would measure the wrong host"

mkdir -p "${SB}/t28"
cat > "${SB}/t28/variables.tf" <<'EOF'
variable "app_domain_base" {
  default = "soleur.ai"
}
variable "app_domain" {
  default = "app.soleur.ai"
}
EOF
run_sut "${SB}/t28/variables.tf"
[[ "$RC" -eq 0 && "$OUT" == "soleur.ai" ]] && pass "T28 a consistent app_domain passes" \
  || fail "T28 false-abort on consistent values: rc=$RC out='$OUT'"

# ── Anti-vacuity floors ─────────────────────────────────────────────────────────────────────
# TWO floors, because they fail differently and the second is the one that was missing.
#
# The INVOCATION floor catches a fixture source that silently produced nothing.
if [[ "$CASES_RUN" -lt 26 ]]; then
  fail "anti-vacuity: only ${CASES_RUN} script invocations ran (expected >= 26)"
else
  pass "anti-vacuity floor: ${CASES_RUN} script invocations"
fi

# The ASSERTION floor catches the dispatch layer itself going silent. Measured: neutering
# `fail()` to `return 0` — which the `&&`/`||` idiom makes a VALID no-op — reported
# "22 passed, 0 failed" while `validate_base` was deleted from the SUT and six malformed-shape
# rows were suppressed. `fails` alone is a single unguarded integer, so a suite that asserts
# nothing is byte-indistinguishable from one that passed. Pinned EXACTLY, with zero slack:
# a `>=` here would re-open the hole every time an assertion is added.
EXPECTED_PASSES=34
if [[ "$fails" -eq 0 && "$passes" -ne "$EXPECTED_PASSES" ]]; then
  printf '  FAIL anti-vacuity: %d assertions passed, expected exactly %d — assertions were added, removed, or silenced\n' \
    "$passes" "$EXPECTED_PASSES"
  fails=$((fails + 1))
fi

printf '\n=== %d passed, %d failed ===\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]] || exit 1
