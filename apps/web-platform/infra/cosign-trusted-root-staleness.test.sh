#!/usr/bin/env bash
# CI staleness + integrity gate for the pinned cosign trusted root (#6005, ADR-086,
# security-sentinel HIGH #2). MUST land + stay green before any WARN→ENFORCE flip — a
# stale pinned root fail-CLOSES every deploy once ENFORCE is on.
#
# WHY CAPTURE-AGE, NOT EXPIRY-PARSE: sigstore's trusted_root.json has NO root-level
# expiry. Current CA/tlog/ctlog/tsa key material is open-ended; the only validFor.end
# timestamps in the file are 2022 (retired keys), always in the past by design. So
# "parse expiry, fail within N days" would false-fail immediately. The actionable
# staleness signal is the CAPTURE AGE: when sigstore rotates to new key material a stale
# pinned root will not contain it and new signatures stop verifying. This gate fails once
# the committed root's capture date (from the provenance sidecar) exceeds MAX_AGE_DAYS,
# forcing a re-capture + re-verify against a live signed image. Deterministic, no network.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_JSON="$DIR/cosign-trusted-root.json"
PROV="$DIR/cosign-trusted-root.provenance.md"
MAX_AGE_DAYS=150  # re-capture cadence; sigstore roots rotate ~annually → comfortable margin

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

echo "--- cosign trusted-root staleness + integrity gate (#6005) ---"

# 1. Files present.
[[ -s "$ROOT_JSON" ]] || { fail "cosign-trusted-root.json missing/empty"; echo "RESULT: $PASS passed, $FAIL failed"; exit 1; }
[[ -s "$PROV" ]] || { fail "provenance sidecar missing/empty"; echo "RESULT: $PASS passed, $FAIL failed"; exit 1; }

# 2. Valid sigstore trusted root (has certificateAuthorities). Use jq if present, else grep.
if command -v jq >/dev/null 2>&1; then
  if jq -e '.certificateAuthorities | length > 0' "$ROOT_JSON" >/dev/null 2>&1; then
    pass "trusted root is valid JSON with certificateAuthorities"
  else fail "trusted root is not a valid sigstore root (no certificateAuthorities)"; fi
else
  grep -q certificateAuthorities "$ROOT_JSON" && pass "trusted root contains certificateAuthorities (grep)" || fail "trusted root missing certificateAuthorities"
fi

# 3. Recorded sha256 in the provenance sidecar matches the committed file (drift guard).
# (|| true: pipefail + a no-match grep would otherwise abort under set -e.)
recorded_sha="$(grep -oE '[0-9a-f]{64}' "$PROV" | head -1 || true)"
actual_sha="$(sha256sum "$ROOT_JSON" | cut -d' ' -f1)"
if [[ -n "$recorded_sha" && "$recorded_sha" == "$actual_sha" ]]; then
  pass "provenance sha256 matches committed trusted root ($actual_sha)"
else
  fail "provenance sha256 ($recorded_sha) != committed file sha256 ($actual_sha) — update the sidecar"
fi

# 4. Capture-age gate. Parse "Capture date (UTC) | **YYYY-MM-DD**" from the sidecar.
capture_date="$(grep -oE 'Capture date \(UTC\) \| \*\*[0-9]{4}-[0-9]{2}-[0-9]{2}\*\*' "$PROV" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || true)"
if [[ -z "$capture_date" ]]; then
  fail "could not parse capture date from provenance sidecar"
else
  cap_epoch="$(date -u -d "$capture_date" +%s 2>/dev/null || echo '')"
  now_epoch="$(date -u +%s)"
  if [[ -z "$cap_epoch" ]]; then
    fail "capture date '$capture_date' not parseable by date(1)"
  else
    age_days=$(( (now_epoch - cap_epoch) / 86400 ))
    if (( age_days < 0 )); then
      fail "capture date '$capture_date' is in the future (age=${age_days}d) — check the sidecar"
    elif (( age_days > MAX_AGE_DAYS )); then
      fail "pinned trusted root is ${age_days}d old (> ${MAX_AGE_DAYS}d) — re-capture per the provenance rotation recipe + re-verify a live signed digest BEFORE relying on ENFORCE"
    else
      pass "pinned trusted root capture age ${age_days}d (<= ${MAX_AGE_DAYS}d)"
    fi
  fi
fi

echo "RESULT: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
