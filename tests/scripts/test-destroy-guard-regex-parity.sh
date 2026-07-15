#!/usr/bin/env bash
# Pins the [ack-destroy] regex across all six sites where it lives — the
# three apply-* workflows AND the three destroy-guard test scripts that
# mirror their control flow.
#
# The regex `(^|$'\n')\[ack-destroy\]($|$'\n')` is load-bearing across all
# six files: any drift silently breaks the operator-acknowledgement gate.
# CODEOWNERS @deruelle gates approval but not content coherence — this
# script is the deterministic coherence check.
#
# Closes #4419 review-finding F2 (pattern-recognition-specialist).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$REPO_ROOT/.." && pwd)"

# Byte-identical regex (with the bash $'\n' ANSI-C-quoting). All six sites
# MUST contain a line matching this exact literal after the `=~` operator:
#   (^|$'\n')\[ack-destroy\]($|$'\n')
# The grep below uses `-F` (literal) to avoid regex-meta-on-regex confusion.
EXPECTED_SITES=(
  ".github/workflows/apply-github-infra.yml"
  ".github/workflows/apply-sentry-infra.yml"
  ".github/workflows/apply-web-platform-infra.yml"
  "tests/scripts/test-destroy-guard-counter.sh"
  "tests/scripts/test-destroy-guard-counter-sentry.sh"
  "tests/scripts/test-destroy-guard-counter-web-platform.sh"
)

fail=0
for site in "${EXPECTED_SITES[@]}"; do
  path="$REPO_ROOT/$site"
  if [[ ! -f "$path" ]]; then
    echo "[FAIL] $site does not exist" >&2
    fail=$((fail + 1))
    continue
  fi
  if grep -qF "(^|\$'\\n')\\[ack-destroy\\](\$|\$'\\n')" "$path"; then
    echo "[ok] $site"
  else
    echo "[FAIL] $site: canonical [ack-destroy] regex not found" >&2
    fail=$((fail + 1))
  fi
done

if [[ "$fail" -gt 0 ]]; then
  echo "=== $fail site(s) drifted from canonical regex ===" >&2
  printf 'Canonical literal:  (^|$%s\\n%s)\\[ack-destroy\\]($|$%s\\n%s)\n' \
    "'" "'" "'" "'" >&2
  exit 1
fi

echo "=== ${#EXPECTED_SITES[@]} sites all carry the canonical [ack-destroy] regex ==="

# ---------------------------------------------------------------------------
# 7th surface (#6416): the `host_creates` HALT's CONTROL FLOW.
#
# WHY THIS LIVES HERE. The counter tests
# (test-destroy-guard-counter-web-platform.sh) exercise a hand-written mirror of
# the workflow's bash, so they pin the jq filter's COUNTING but cannot pin the
# workflow's HALT. Demonstrated at review: deleting the entire `host_creates`
# HALT block from apply-web-platform-infra.yml left that whole suite GREEN — the
# gate the PR exists to add could be removed and nothing noticed. This file is
# the repo's designated coherence check for exactly that gap (see header:
# "CODEOWNERS gates approval but not content coherence").
#
# The three properties below are the HALT's entire contract. Each is asserted
# against the workflow's literal bytes, so removing or weakening any one of them
# fails here even though every counter test still passes.
# ---------------------------------------------------------------------------
WF="$REPO_ROOT/.github/workflows/apply-web-platform-infra.yml"
hc_fail=0

# The three literals below are the workflow's SOURCE TEXT, matched with `grep -F`. The single
# quotes are load-bearing: the text contains `$host_creates` verbatim, and letting the shell
# expand it would search for the empty string and pass vacuously — the exact false-green this
# block exists to prevent.
# shellcheck disable=SC2016
HALT_PATTERN='if [[ "$host_creates" -gt 0 ]]; then'
# shellcheck disable=SC2016
SUM_PATTERN='destroy_count=$((resource_deletes + nested_deletes + reboot_updates))'
# shellcheck disable=SC2016
NUMERIC_PATTERN='! "$host_creates" =~ ^[0-9]+$'

# (1) The HALT exists at all.
if grep -qF "$HALT_PATTERN" "$WF"; then
  echo "[ok] host_creates HALT present"
else
  echo "[FAIL] host_creates HALT missing from apply-web-platform-infra.yml — a per-PR apply can birth an unattached host (#6416)" >&2
  hc_fail=$((hc_fail + 1))
fi

# (2) The HALT precedes the destroy_count sum. This is what makes it ack-INDEPENDENT:
# `[ack-destroy]` is parsed and consulted only by the destroy gate below the sum, so a HALT
# above it cannot be typed past. Order is the guarantee — assert the order, not just presence.
halt_line=$(grep -nF "$HALT_PATTERN" "$WF" | head -1 | cut -d: -f1)
sum_line=$(grep -nF "$SUM_PATTERN" "$WF" | head -1 | cut -d: -f1)
if [[ -n "$halt_line" && -n "$sum_line" && "$halt_line" -lt "$sum_line" ]]; then
  echo "[ok] host_creates HALT (line $halt_line) precedes the destroy_count sum (line $sum_line) — no [ack-destroy] bypass"
else
  echo "[FAIL] host_creates HALT must precede the destroy_count sum (halt=${halt_line:-absent} sum=${sum_line:-absent}); below it, [ack-destroy] would bypass a host create/replace" >&2
  hc_fail=$((hc_fail + 1))
fi

# (3) host_creates is in the fail-closed numeric validation. Without it an empty value from a
# jq failure evaluates false in the `-gt 0` test and the guard ships fail-OPEN — the exact
# hazard that block's own comment documents.
if grep -qF "$NUMERIC_PATTERN" "$WF"; then
  echo "[ok] host_creates is in the numeric-parse validation (fail-closed)"
else
  echo "[FAIL] host_creates missing from the numeric-parse validation — a jq failure would silently evaluate false and let a host create through" >&2
  hc_fail=$((hc_fail + 1))
fi

if [[ "$hc_fail" -gt 0 ]]; then
  echo "=== $hc_fail host_creates HALT contract violation(s) ===" >&2
  exit 1
fi

echo "=== host_creates HALT contract intact (present, pre-sum, fail-closed) ==="
