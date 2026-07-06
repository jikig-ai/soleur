#!/usr/bin/env bash
# Cross-redactor secret-class parity guard (#6045 item 8).
#
# The two INDEPENDENT secret-class redactors — incident/redact-engine.py (the
# canonical Python engine) and operator-digest/digest-scrub.sh (the digest egress
# gate, bash ERE) — drift silently: digest-scrub's header claims "Verbatim from
# redact-sentinel.sh" but has historically fallen behind (it shipped missing the
# doppler/slack crown-jewel classes added in #5987). A class the engine catches but
# digest-scrub misses is a secret that leaks through the digest egress path.
#
# This guard asserts NAME-LEVEL parity: every secret CLASS the engine defines is
# either present in digest-scrub.sh's SECRET map OR listed in DIVERGENCE_ALLOWLIST
# with a one-word rationale (a class the digest legitimately handles differently or
# does not carry). Regex-BODY parity (ERE vs Python `re` dialects) is a documented
# NON-GOAL — the two bodies are not cheaply comparable; the one-time body sync in the
# same PR keeps digest a superset for the shared classes, and pattern edits get manual
# cross-review. Fails CLOSED on any new engine class that is neither synced nor allowlisted.
#
# OUT OF SET: linear-fetch/redact-linear-urls.sh is a single ORTHOGONAL class (Linear
# CDN image URLs, sed-rewrite, no secret overlap, different egress boundary). It is NOT
# a secret-class redactor and is deliberately not parity-checked here.
#
# Class enumeration is done by IMPORTING redact-engine.py (Python is the authoritative
# source of PATTERNS — a bash regex parser could silently under-enumerate and dark-pass;
# see spec-flow plan-review). A floor sanity-check guards against a broken/empty import.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
ENGINE="${REPO_ROOT}/plugins/soleur/skills/incident/scripts/redact-engine.py"
DIGEST="${REPO_ROOT}/plugins/soleur/skills/operator-digest/scripts/digest-scrub.sh"

PASS=0
FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# Classes the digest legitimately does NOT carry in its SECRET map, with a one-word
# rationale. email/UUID/IPv4: the digest handles these OUTSIDE SECRET (email via
# first-party-vs-foreign domain logic; UUID/IPv4 as WARN-only prose, not aborts).
declare -A DIVERGENCE_ALLOWLIST=(
  [email]=domain-logic
  [UUID]=warn-only
  [IPv4]=warn-only
  [cloudflare_token]=not-in-digest
)

command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 not found — cannot enumerate engine classes"; exit 1; }
[[ -r "$ENGINE" ]] || { echo "FAIL: engine not readable: $ENGINE"; exit 1; }
[[ -r "$DIGEST" ]] || { echo "FAIL: digest-scrub not readable: $DIGEST"; exit 1; }

# Authoritative class enumeration via import (hyphenated filename → importlib).
mapfile -t ENGINE_CLASSES < <(python3 -c "
import importlib.util, sys
spec = importlib.util.spec_from_file_location('re_engine', '${ENGINE}')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
for name, _ in m.PATTERNS:
    sys.stdout.write(name + '\n')
")

# Floor sanity-check: a broken import (empty/short PATTERNS) would vacuously pass the per-class loop.
# The <13 floor is the real contract — enough secret classes must enumerate to make the loop meaningful.
if (( ${#ENGINE_CLASSES[@]} < 13 )); then
  fail "engine class enumeration returned ${#ENGINE_CLASSES[@]} (< 13 floor) — import broken or PATTERNS empty"
else
  pass "engine class enumeration: ${#ENGINE_CLASSES[@]} classes (>= 13 floor)"
fi

# Per-class parity: present in digest SECRET map OR allowlisted.
for cls in "${ENGINE_CLASSES[@]}"; do
  if [[ -n "${DIVERGENCE_ALLOWLIST[$cls]:-}" ]]; then
    pass "class '${cls}': documented divergence (${DIVERGENCE_ALLOWLIST[$cls]})"
    continue
  fi
  # SECRET map key form in digest-scrub.sh: `  [<name>]='...'`
  if grep -qE "^\s*\[${cls}\]=" "$DIGEST"; then
    pass "class '${cls}': present in digest-scrub.sh SECRET map"
  else
    fail "class '${cls}': MISSING from digest-scrub.sh SECRET map AND not allowlisted — secret leaks through digest egress"
  fi
done

echo
echo "Total: ${PASS} pass, ${FAIL} fail"
[[ "${FAIL}" -eq 0 ]]
