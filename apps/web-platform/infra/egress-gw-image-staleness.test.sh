#!/usr/bin/env bash
# Freshness + coherence gate for the pinned egress-gateway Squid image (#9534).
#
# Enforcement half of the pin cadence (the detection half is the upstream poll
# in .github/workflows/rule-audit.yml). Cloned from zot-image-staleness.test.sh
# at reduced scope: the gateway pin is a single multi-arch index digest, so
# there is no arch-swap class to cover — only "pin exists, is digest-pinned,
# the sidecar records the same digest, and the analysis is not ancient".
#
# NO NETWORK, BY DESIGN. Everything here reads committed files only.
#
# EXIT CODES (the rule-audit step discriminates on these; do not overload 1):
#   0  — fresh and coherent
#   10 — DRIFT: stale or incoherent (the actionable "a human must look" signal)
#   2  — DETECTOR FAILURE: inputs missing/unparseable. Never conflated with "fresh".
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP="$DIR/egress-gateway-bootstrap.sh"
PROV="$DIR/egress-gw-image.provenance.md"

# ubuntu/squid tracks Ubuntu LTS Squid; upstream moves on a slow cadence but the
# rule-audit poll runs fortnightly, so 180 days is ~12 poll firings — a genuine
# stall, not routine lag.
MAX_AGE_DAYS=180

PASS=0; FAIL=0; DRIFT=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
drift() { DRIFT=$((DRIFT + 1)); echo "  DRIFT: $1"; }

[[ -f "$BOOTSTRAP" ]] || { echo "FATAL: $BOOTSTRAP missing" >&2; exit 2; }
[[ -f "$PROV" ]] || { echo "FATAL: $PROV missing" >&2; exit 2; }

# 1. Digest pin, anchored on the assignment (an unanchored grep matches comments).
PIN_RE='EGRESS_GW_IMAGE:-[a-z]+/[a-z]+@sha256:[0-9a-f]{64}'
if grep -qE "EGRESS_GW_IMAGE:-ubuntu/squid@sha256:[0-9a-f]{64}" "$BOOTSTRAP"; then
  pass "bootstrap carries a digest-pinned ubuntu/squid reference"
else
  fail "bootstrap EGRESS_GW_IMAGE is not a digest-pinned ubuntu/squid reference"
fi
PINNED="$(grep -oE 'ubuntu/squid@sha256:[0-9a-f]{64}' "$BOOTSTRAP" | head -1)"
[[ -n "$PINNED" ]] || { echo "FATAL: could not extract pinned reference" >&2; exit 2; }

# 2. Sidecar records the SAME digest — a re-pin that updates one and not the
#    other is the exact coherence class the zot gate caught per-file.
if grep -qF "$PINNED" "$PROV"; then
  pass "provenance sidecar records the pinned digest"
else
  fail "provenance sidecar does not record the pinned digest ($PINNED)"
fi

# 3. Sidecar capture date — age gate (a fresh-looking pin analysis that has
#    never been re-verified reads as current forever otherwise).
CAP_DATE="$(grep -oE 'Capture date \(UTC\).{0,40}[0-9]{4}-[0-9]{2}-[0-9]{2}' "$PROV" \
  | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)"
if [[ -z "$CAP_DATE" ]]; then
  fail "provenance sidecar has no parseable Capture date"
else
  CAP_EPOCH="$(date -d "$CAP_DATE" +%s 2>/dev/null || date -jf %Y-%m-%d "$CAP_DATE" +%s 2>/dev/null || echo 0)"
  NOW_EPOCH="$(date +%s)"
  AGE_DAYS=$(( (NOW_EPOCH - CAP_EPOCH) / 86400 ))
  if (( AGE_DAYS <= MAX_AGE_DAYS )); then
    pass "sidecar capture date is ${AGE_DAYS}d old (< ${MAX_AGE_DAYS}d)"
  else
    drift "sidecar capture date is ${AGE_DAYS}d old (> ${MAX_AGE_DAYS}d) — re-run the re-pin procedure"
  fi
fi

echo "RESULT: $PASS passed, $FAIL failed, $DRIFT drifted"
if [[ $((PASS + FAIL + DRIFT)) -lt 3 ]]; then
  echo "[FATAL] anti-vacuity floor: < 3 verdicts — the gate checked nothing" >&2
  exit 2
fi
(( DRIFT > 0 )) && exit 10
(( FAIL > 0 )) && exit 1
exit 0
