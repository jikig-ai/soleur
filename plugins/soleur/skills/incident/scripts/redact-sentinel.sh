#!/usr/bin/env bash
# Pre-write redaction sentinel for /soleur:incident, code-to-prd Layer 2, and the
# legal-generate gate. Thin shim (#5987) — the engine is now redact-engine.py.
#
# Contract preserved 1:1 (argv, exit codes, output shape) so all consumers are unchanged:
#   0 = clean — no matches found
#   1 = redaction needed — at least one match found (incl. synthetic HIGH on oversize input)
#   2 = cannot-evaluate — missing/unreadable file, no python3, engine crash, or any non-{0,1,2}
#
# Output format (per FR3, now capped by the engine's meta-redaction — never a full token):
#   at offset N: <=4-prefix>***<=4-suffix> matched pattern <class>
#
# Exit is NORMALIZED to {0,1,2}: any engine-cannot-run/unexpected code -> 2 (cannot-evaluate),
# which every consumer already treats as fail-closed (code-to-prd Layer 2, incident Phase 6,
# dry-run any-nonzero). python3 absent -> 2 (NOT 1: exit 1 means "matches found", which would give
# a false "secrets found" message and trap the incident operator in an unsatisfiable redact loop).
#
# The hardened engine defeats compatibility-char / invisible / bidi / control / invalid-byte /
# soft-hyphen / prefix-homoglyph evasion (matching runs over strip -> NFKC -> strip -> confusable-fold;
# invisibles are stripped by Unicode category, not a hand-picked list). It does NOT defeat the full
# cross-script homoglyph space (TR39 skeleton), whitespace token-splitting, reversibly-encoded
# secrets, or unprefixed/high-entropy tokens — each a named non-goal (see ADR-086).
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v python3 >/dev/null 2>&1 || {
  echo "redact-sentinel: python3 not found — failing closed (exit 2)." >&2
  exit 2
}

python3 "${DIR}/redact-engine.py" "$@"
rc=$?
case "${rc}" in
  0 | 1 | 2) exit "${rc}" ;;
  *)
    echo "redact-sentinel: engine exit ${rc} normalized to 2 (cannot-evaluate)." >&2
    exit 2
    ;;
esac
