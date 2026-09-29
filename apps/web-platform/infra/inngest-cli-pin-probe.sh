#!/usr/bin/env bash
# Sub-second liveness probe for the inngest CLI pin (#7463).
#
# Prints the pinned version, the sidecar's capture date, and a one-word verdict.
# Deliberately NOT the full staleness suite — the observability gate's
# discoverability_test.command is capped at 15s and must be plain-words-only, so this
# is the smallest command that emits the liveness signal. Offline: reads committed
# files only, never the network.
#
#   PINNED=vX.Y.Z  CAPTURE_DATE=YYYY-MM-DD  VERDICT=fresh|stale|unverifiable
#
# Exit: 0 fresh / 10 stale / 2 unverifiable (same rc contract as the suite).
# GNU date only (`date -d`); on a BSD host the parse fails closed to
# VERDICT=unverifiable — never a silent fresh.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF="$DIR/inngest.tf"
PROV="$DIR/inngest-cli.provenance.md"
MAX_AGE_DAYS=60   # same bound as inngest-cli-staleness.test.sh — keep in lockstep
                # (the mutation battery's baseline asserts the two constants agree)

PINNED="$(grep -oE '^[[:space:]]*inngest_cli_version[[:space:]]*=[[:space:]]*"v[0-9]+\.[0-9]+\.[0-9]+"' "$TF" 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"

# Scope the capture date to the sidecar's header table — a file-wide head -1 would
# let a later '## Bump log' row shadow the attestation (the class the full suite
# refuses at check 6). Refuse on more than one matching row anywhere in the file:
# shadowing is a detector failure, not a stale verdict.
cap_rows="$(grep -cE 'Capture date \(UTC\) \| \*\*[0-9]{4}-[0-9]{2}-[0-9]{2}\*\*' "$PROV" 2>/dev/null || echo 0)"
header_table="$(awk '/^\| Field \| Value \|/{f=1} /^## /{f=0} f' "$PROV" 2>/dev/null || true)"
CAPTURE_DATE="$(printf '%s\n' "$header_table" | grep -oE 'Capture date \(UTC\) \| \*\*[0-9]{4}-[0-9]{2}-[0-9]{2}\*\*' | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || true)"

echo "PINNED=${PINNED:-unknown}"
echo "CAPTURE_DATE=${CAPTURE_DATE:-unknown}"

if [[ -z "$PINNED" || -z "$CAPTURE_DATE" || "$cap_rows" -gt 1 ]]; then
  echo "VERDICT=unverifiable"
  exit 2
fi
cap_epoch="$(date -u -d "$CAPTURE_DATE" +%s 2>/dev/null || echo '')"
if [[ -z "$cap_epoch" ]]; then
  echo "VERDICT=unverifiable"
  exit 2
fi
age_days=$(( ( $(date -u +%s) - cap_epoch ) / 86400 ))
if (( age_days > MAX_AGE_DAYS || age_days < 0 )); then
  echo "VERDICT=stale"
  exit 10
fi
echo "VERDICT=fresh"
exit 0
