#!/usr/bin/env bash
# Tests for infra-config-verify.sh — the infra-config apply verification gate.
#
# #7104 PR-B / plan R22.2: this file was the ~240-line `run:` body of the
# "Verify infra-config apply succeeded" step in apply-deploy-pipeline-fix.yml.
# It was moved out verbatim (ADR-150 shape) so that the split recovery can
# invoke the SAME tested artifact twice instead of duplicating 240 lines of
# untestable YAML across two steps.
#
# ADR-150's recorded regret is that scripts/cutover-inngest.sh shipped WITHOUT a
# companion suite. This file is that companion, and it is registered in
# .github/workflows/infra-validation.yml so lint-orphan-test-suites cannot let a
# future edit land unguarded.
#
# What this suite does NOT do: assert byte-identity against the pre-move `run:`
# block. That verification is a COMMIT-1 event, not a standing property — plan
# R22.3's commit 2 deliberately parameterises this script, so a permanent
# byte-identity assert would be RED by the end of this very PR. Worse, the
# prescribed baseline (`git show origin/main:<the workflow>`) FLIPS at merge:
# post-merge that revision carries the one-line `run:`, so the guard would
# either fail or pass vacuously for the next contributor. The move's
# verbatim-ness is instead pinned by the SHA-256 recorded in ADR-187 and in
# commit 1's message (both sides 2a23f958…, 19774 bytes).
set -euo pipefail

# A direct invocation inherits the bare /tmp (a machine-global 4 GiB tmpfs shared
# by parallel worktrees); test-all.sh and run-registered-suites.sh default this to
# /var/tmp. Without it this suite's verdicts become a function of another
# session's disk usage.
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
VERIFY_SH="${SCRIPT_DIR}/infra-config-verify.sh"
GATE_SH="${SCRIPT_DIR}/infra-config-gate.sh"
APPLY_WF="${REPO_ROOT}/.github/workflows/apply-deploy-pipeline-fix.yml"

PASS=0
FAIL=0

pass() {
  echo "  PASS: $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "  FAIL: $1" >&2
  FAIL=$((FAIL + 1))
}

# Command-position matcher. Anchored on shell syntax (line start, a separator, or
# the head of a command substitution) rather than a bare token: both files carry
# 20+ comment-only occurrences of these words, and a bare grep would match the
# prose that DOCUMENTS the prohibition (cq-assert-anchor-not-bare-token).
#
# Single-quoted so the shell does not eat the backslash in `\$\(` — double
# quoting turns it into `$(`, where `$` is an ERE end-anchor that can never
# match, silently reporting 0 for every input. That exact defect produced a
# false "0 curl occurrences" reading while authoring this suite.
cmd_position_count() {
  local file="$1" cmd="$2"
  grep -cE '(^|[;&|]|\$\()[[:space:]]*(sudo[[:space:]]+)?'"$cmd"'[[:space:]]' "$file" 2>/dev/null || true
}

echo "== infra-config-verify.sh =="

# --- T1: the artifact exists and is a bash script -------------------------------------------
if [[ -f "$VERIFY_SH" ]]; then
  pass "infra-config-verify.sh exists"
  if [[ "$(head -n 1 "$VERIFY_SH")" == "#!/usr/bin/env bash" ]]; then
    pass "carries the bash shebang"
  else
    fail "missing or wrong shebang: $(head -n 1 "$VERIFY_SH")"
  fi
else
  fail "infra-config-verify.sh not found at $VERIFY_SH"
fi

# --- T2: it parses. `bash -n` on the EXTRACTED FILE ------------------------------------------
# Never `bash -n` on the .yml (it is not shell), and never `bash -c`, which would
# RUN the body — and this body reaches a production terraform apply (plan R16.3).
if [[ -f "$VERIFY_SH" ]] && bash -n "$VERIFY_SH" 2>/dev/null; then
  pass "bash -n clean"
else
  fail "bash -n reported a syntax error"
fi

# --- T3: no GitHub expression syntax survived the move ---------------------------------------
# `${{ }}` is interpolated by Actions BEFORE the shell sees it. Inside a standalone
# script it is a literal that bash would mis-parse, so any occurrence means the move
# took something that cannot work outside the workflow.
if [[ -f "$VERIFY_SH" ]]; then
  ghexpr=$(grep -cF '${{' "$VERIFY_SH" || true)
  if [[ "$ghexpr" -eq 0 ]]; then
    pass "no \${{ }} GitHub expressions in the extracted body"
  else
    fail "$ghexpr GitHub expression(s) survived extraction — they cannot evaluate in a standalone script"
  fi
fi

# --- T4: production invokes it ---------------------------------------------------------------
# A tested script no step runs is the vacuity the F1 pin exists to prevent, one
# indirection deeper. The mirror clause lives in infra-config-gate.test.sh.
if [[ -r "$APPLY_WF" ]]; then
  if grep -qE '^[[:space:]]*run:[[:space:]]+bash[[:space:]]+.*infra-config-verify\.sh' "$APPLY_WF"; then
    pass "apply-deploy-pipeline-fix.yml invokes infra-config-verify.sh"
  else
    fail "no step in apply-deploy-pipeline-fix.yml invokes infra-config-verify.sh — the extracted gate is dead in production"
  fi
else
  fail "cannot read $APPLY_WF — the production invocation pin cannot be evaluated"
fi

# --- T5: the verification surface does not ACTUATE -------------------------------------------
# Plan R22.4: "PR-B ships no verification surface that actuates." This converts that
# sentence from a claim in an ADR into a contract. infra-config-verify.sh senses,
# polls and adjudicates; the re-push it triggers is planned, graded and applied in
# SEPARATE workflow steps. A `terraform` here would collapse the boundary the whole
# ruling restored.
#
# curl and `doppler secrets get` are deliberately NOT in this set: polling the status
# endpoint and reading a secret are what a verification gate does. T6 pins the doppler
# half to read-only subcommands.
ACTUATING="terraform ssh systemctl"
if [[ -f "$VERIFY_SH" ]]; then
  checked=0
  for c in $ACTUATING; do
    checked=$((checked + 1))
    n=$(cmd_position_count "$VERIFY_SH" "$c")
    if [[ "$n" -eq 0 ]]; then
      pass "infra-config-verify.sh has no command-position \`$c\` (it verifies; it does not actuate)"
    else
      fail "infra-config-verify.sh runs \`$c\` at $n command position(s) — the verification gate actuates, collapsing the step boundary R22 restored"
    fi
  done
  # `gh issue` specifically: the escalation credentials live in none of these steps
  # (R18.6). A bare `gh` would over-match `gh` in prose; anchor on the subcommand.
  ghn=$(grep -cE '(^|[;&|]|\$\()[[:space:]]*gh[[:space:]]+issue[[:space:]]' "$VERIFY_SH" || true)
  checked=$((checked + 1))
  if [[ "$ghn" -eq 0 ]]; then
    pass "infra-config-verify.sh runs no \`gh issue\` (escalation stays out of the verdict step)"
  else
    fail "infra-config-verify.sh runs \`gh issue\` at $ghn site(s) — escalation credentials do not belong in the verdict step"
  fi
  # Minimum-cardinality guard: a loop whose data source silently empties reports a
  # clean sweep having examined nothing.
  if [[ "$checked" -ge 4 ]]; then
    pass "actuation sweep examined $checked commands"
  else
    fail "actuation sweep examined only $checked commands — the command list emptied"
  fi
fi

# --- T6: every doppler call is READ-only ------------------------------------------------------
# `doppler secrets get` reads. `doppler secrets set|delete|upload`, `doppler run`,
# and `doppler configure` mutate or execute. The gate may read a secret; it may not
# write one.
if [[ -f "$VERIFY_SH" ]]; then
  dtotal=$(cmd_position_count "$VERIFY_SH" doppler)
  dread=$(grep -cE '(^|[;&|]|\$\()[[:space:]]*doppler[[:space:]]+secrets[[:space:]]+get[[:space:]]' "$VERIFY_SH" || true)
  if [[ "$dtotal" -eq 0 ]]; then
    fail "no command-position doppler call found — the fixture for T6 has drifted, so this assert is vacuous"
  elif [[ "$dtotal" -eq "$dread" ]]; then
    pass "all $dtotal command-position doppler call(s) are read-only \`secrets get\`"
  else
    fail "$((dtotal - dread)) of $dtotal command-position doppler call(s) are not \`secrets get\` — the gate mutates secret state"
  fi
fi

# --- T7: infra-config-gate.sh remains a PURE adjudicator --------------------------------------
# Plan R20.7 §1: the sourced library is invisible to any grep over the workflow, and
# is a pure adjudicator BY CONVENTION ONLY. PR-B adds a function to it, which widens
# exactly that escape — so the sweep scopes to two files, and for the library the
# prohibition is absolute: it adjudicates in-process and touches nothing.
if [[ -f "$GATE_SH" ]]; then
  gchecked=0
  for c in terraform curl ssh systemctl doppler; do
    gchecked=$((gchecked + 1))
    n=$(cmd_position_count "$GATE_SH" "$c")
    if [[ "$n" -eq 0 ]]; then
      pass "infra-config-gate.sh has no command-position \`$c\` (pure adjudicator)"
    else
      fail "infra-config-gate.sh runs \`$c\` at $n command position(s) — it is no longer a pure adjudicator"
    fi
  done
  if [[ "$gchecked" -ge 5 ]]; then
    pass "purity sweep examined $gchecked commands"
  else
    fail "purity sweep examined only $gchecked commands — the command list emptied"
  fi
else
  fail "infra-config-gate.sh not found — the purity contract cannot be evaluated"
fi

# --- assertion floor --------------------------------------------------------------------------
# Anti-vacuity. Counts assertions that RAN, so a structural break that skips whole
# blocks (an unset file path, an early `else`) reds instead of reporting a clean 0/0.
VERIFY_MIN_ASSERTIONS=17
echo ""
echo "  $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
if [[ "$PASS" -lt "$VERIFY_MIN_ASSERTIONS" ]]; then
  echo "  FAIL: assertion-count floor: only $PASS assertions ran, expected >= $VERIFY_MIN_ASSERTIONS — arms were deleted or skipped" >&2
  exit 1
fi
exit 0
