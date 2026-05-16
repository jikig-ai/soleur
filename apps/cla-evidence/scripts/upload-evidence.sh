#!/usr/bin/env bash
# upload-evidence.sh — R2 conditional-PUT wrapper for content-addressed
# CLA evidence records (Kieran F7 single source of truth).
#
# Used by:
#   - .github/workflows/cla-evidence.yml (sign-time sidecar)
#   - apps/web-platform/scripts/cla-backfill-evidence.ts (Phase 3 backfill)
#
# Key derivation: signatures/<sha256-of-payload>.json (content-addressed).
# All retry / classification logic lives in r2-conditional-put.sh; this script
# computes the key and delegates so the two upload paths (evidence + bypass)
# stay in lockstep on backoff, fast-fail, and error formatting.
#
# Behaviour (delegated):
#   - 200 / 201 → exit 0.
#   - 412       → exit 0 (idempotent duplicate).
#   - 5xx / 429 → retry up to 3 with exponential backoff.
#   - 4xx ≠ 412 → fast-fail with exit 2 + ::error:: (Kieran F5).
#
# Inputs:
#   $1                              JSON payload (already validated by the
#                                   caller's schema_version assertion).
#
# Required environment:
#   R2_CLA_EVIDENCE_ACCESS_KEY_ID, R2_CLA_EVIDENCE_SECRET,
#   R2_CLA_EVIDENCE_BUCKET (default soleur-cla-evidence),
#   R2_CLA_EVIDENCE_ENDPOINT.

set -euo pipefail

if [[ "$#" -lt 1 ]]; then
  echo "::error::usage: upload-evidence.sh <payload-json>" >&2
  exit 64
fi

payload="$1"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Content-addressed key: sha256 of the canonical JSON payload bytes.
sha=$(printf '%s' "$payload" | sha256sum | awk '{print $1}')
key="signatures/${sha}.json"

LABEL=upload-evidence \
DUP_LABEL=duplicate \
  exec bash "$script_dir/r2-conditional-put.sh" "$key" "$payload"
