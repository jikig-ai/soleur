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
