#!/usr/bin/env bash
# Pins the STEP ORDER of the drift-check job in .github/workflows/scheduled-terraform-drift.yml
# (#7071).
#
# WHY THIS FILE EXISTS. The defect it guards was an ORDERING defect, and nothing in the repo
# could see ordering. "Enforce token-drift result" originally sat immediately after the
# token-drift check, so its `exit 1` skipped the four reporting steps below it — the infra-drift
# label, the drift issue, the drift email body, and the drift email — because each carries a
# plain-expression `if:` and GitHub Actions gives those an implicit `success()`. A day with BOTH
# a stale Cloudflare token and real Terraform drift would have reported NEITHER: the step added
# to make token drift loud was darkening the channel it was added to.
#
# A co-presence grep ("the enforce step exists", "the email step exists") passes on the buggy
# version, which is why this asserts POSITION. And position alone is not enough either: an
# ordering-only guard passes a variant that drops `always()`, under which a failure in the issue
# filer would skip the enforce step. Both halves are asserted; each was mutation-verified RED on
# its own.
#
# Registration: auto-globbed by scripts/test-all.sh via plugins/soleur/test/*.test.sh — unlike
# scripts/*.test.sh, this directory needs no explicit run_suite line. Verified by running the
# runner and confirming this file appears in its log, not by assuming the glob.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WF="$REPO_ROOT/.github/workflows/scheduled-terraform-drift.yml"

PASS=0
FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

[[ -f "$WF" ]] || { echo "FATAL: workflow not found at $WF" >&2; exit 2; }

# Extract a named job's block. Same shape as named_job_block() in
# reusable-release-caller-permissions.test.sh; duplicated rather than sourced because these
# suites are independently registered and a cross-file source makes one suite's failure look
# like the other's.
named_job_block() {
  local file="$1" job="$2"
  awk -v job="$job" '
    /^jobs:[[:space:]]*$/ { injobs = 1; next }
    !injobs { next }
    /^  [A-Za-z0-9_-]+:[[:space:]]*(#.*)?$/ {
      cur = $0; sub(/^  /, "", cur); sub(/:.*/, "", cur)
      inblock = (cur == job)
    }
    inblock { print }
  ' "$file"
}

BLOCK="$(named_job_block "$WF" drift-check)"
# Non-vacuity floor on the extraction itself. An awk change or a `jobs:` reshuffle that yields an
# empty block would otherwise make every index below -1 and every ordering assertion pass by
# comparing two absent things.
if [[ "$(wc -l <<<"$BLOCK")" -lt 50 ]]; then
  echo "FATAL: drift-check block extracted as $(wc -l <<<"$BLOCK") lines — the extractor is broken, so no assertion below means anything." >&2
  exit 2
fi

# step_index <step name> -> 1-based line number of its `- name:` line within the job block.
# Empty when absent, which every caller treats as a hard failure rather than as position 0.
step_index() {
  grep -n -F -- "      - name: $1" <<<"$BLOCK" | head -1 | cut -d: -f1
}

echo "=== scheduled-terraform-drift: drift-check step order ==="
echo ""

ENFORCE="$(step_index 'Enforce token-drift result')"
if [[ -z "$ENFORCE" ]]; then
  fail "the 'Enforce token-drift result' step is gone — this suite pins its POSITION, so its absence is a hard failure, not a skip"
else
  pass "found the enforce step"

  # The four steps whose channel the enforce step used to darken. Named individually rather
  # than counted: a count assertion passes when one is renamed away, and the whole point is
  # that each of these is a distinct operator-facing channel.
  for step in \
    'Ensure infra-drift label exists' \
    'Create or update drift issue' \
    'Prepare email content' \
    'Email notification (drift/error)' \
    ; do
    idx="$(step_index "$step")"
    if [[ -z "$idx" ]]; then
      fail "reporting step '$step' not found — it was one of the four the enforce step used to skip; if it was deliberately removed, update this suite in the same commit"
    elif [[ "$idx" -lt "$ENFORCE" ]]; then
      pass "'$step' precedes the enforce step"
    else
      fail "'$step' sits AFTER the enforce step (line $idx vs $ENFORCE) — the enforce step's 'exit 1' will skip it via implicit success(), which is the #7071 defect"
    fi
  done
fi

# `always()` is the other half. Without it the enforce step inherits the implicit success() and
# is skipped exactly when an earlier reporting step failed — i.e. when the run is worst.
echo "T2: the enforce step's condition carries always()"
enforce_if="$(grep -A 3 -F -- '      - name: Enforce token-drift result' <<<"$BLOCK" | grep -E '^\s+if:' | head -1)"
if [[ -z "$enforce_if" ]]; then
  fail "could not read the enforce step's if: condition"
elif grep -qF 'always()' <<<"$enforce_if"; then
  pass "enforce step is gated on always()"
else
  fail "enforce step MUST be gated on always() — without it a failure in any reporting step above skips the enforcement entirely (got: ${enforce_if})"
fi

# The token-drift step's `if:` compares against a matrix value. A rename on either side silently
# disables the detector on every run — no email, no annotation, and the Sentry monitor still
# reports ok, so the failure is invisible.
echo "T3: the token-drift step's matrix guard names a real matrix directory"
td_if="$(grep -A 3 -F -- '      - name: Cloudflare token drift' <<<"$BLOCK" | grep -E '^\s+if:' | head -1)"
guard_dir="$(grep -oE "matrix\.directory == '[^']+'" <<<"$td_if" | sed "s/.*== '//; s/'//")"
if [[ -z "$guard_dir" ]]; then
  fail "could not extract the token-drift step's matrix.directory guard from: ${td_if:-<no if: found>}"
elif grep -qF -- "- $guard_dir" <<<"$BLOCK"; then
  pass "matrix guard '$guard_dir' appears in the job's matrix list"
else
  fail "token-drift step is gated on matrix.directory == '$guard_dir', which is NOT in this job's matrix list — the detector would never run and would fail silently"
fi

echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
# Anti-vacuity floor. Deleting the assertion calls above yields "0/0 passed, 0 failed" and exit
# 0, and test-all.sh reads only the exit code — so a suite that ran nothing is indistinguishable
# from one where everything passed. A FLOOR, not equality: adding a case must not edit this line.
if [[ "$((PASS + FAIL))" -lt 6 ]]; then
  echo "FATAL: only $((PASS + FAIL)) assertions ran; expected >= 6. The suite did not execute what it claims to." >&2
  exit 1
fi
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
