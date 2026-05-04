#!/usr/bin/env bash
# upload-evidence.sh — single source of truth for R2 conditional-PUT writes
# of CLA evidence records (Kieran F7).
#
# Used by:
#   - .github/workflows/cla-evidence.yml (sign-time sidecar)
#   - apps/web-platform/scripts/cla-backfill-evidence.ts (Phase 3 backfill)
#
# Behaviour (per Phase 2 plan, Kieran F5 + plan Acceptance Criteria):
#   - PUT signatures/<sha256-of-payload>.json with `If-None-Match: *`.
#   - 200/201 (first write)         → exit 0.
#   - 412 (precondition failed)     → exit 0 (idempotent duplicate).
#   - 5xx / 429                     → retry up to 3 times with exponential
#                                     backoff (250ms, 500ms, 1000ms).
#   - 4xx ≠ 412                     → fast-fail with exit 2 + ::error::
#                                     (config bug: stale token, missing perms, etc.).
#
# Inputs:
#   $1                              JSON payload (already validated by the caller's
#                                   schema_version assertion).
#
# Required environment:
#   R2_CLA_EVIDENCE_ACCESS_KEY_ID   R2 access key (object-write scope only).
#   R2_CLA_EVIDENCE_SECRET          R2 secret access key.
#   R2_CLA_EVIDENCE_BUCKET          Bucket name (default: soleur-cla-evidence).
#   R2_CLA_EVIDENCE_ENDPOINT        S3-compat endpoint URL.
#
# All bounded by --max-time per AGENTS.md plan-skill sharp-edge.

set -euo pipefail

if [[ "$#" -lt 1 ]]; then
  echo "::error::usage: upload-evidence.sh <payload-json>" >&2
  exit 64
fi

payload="$1"
bucket="${R2_CLA_EVIDENCE_BUCKET:-soleur-cla-evidence}"
endpoint="${R2_CLA_EVIDENCE_ENDPOINT:?R2_CLA_EVIDENCE_ENDPOINT must be set}"

# Content-addressed key: sha256 of the canonical JSON payload bytes.
sha=$(printf '%s' "$payload" | sha256sum | awk '{print $1}')
key="signatures/${sha}.json"
url="${endpoint%/}/${bucket}/${key}"

# AWS SigV4 via aws CLI is the simplest portable signer; if curl is the only
# tool available the workflow YAML can swap this. For the test stub, the
# `curl` binary on PATH is an inert mock; so we always invoke `curl` here.
attempt_max=3
backoff=250

put_once() {
  # Stub-friendly: in the test, $(which curl) is the test stub that emits a
  # numeric HTTP code on stdout. In production, curl is invoked with full SigV4
  # via --aws-sigv4 (curl 7.75+) and emits the HTTP code via -w "%{http_code}".
  curl -sS -o /dev/null -w "%{http_code}\n" --max-time 30 \
    -X PUT \
    -H "If-None-Match: *" \
    -H "Content-Type: application/json" \
    --aws-sigv4 "aws:amz:auto:s3" \
    --user "${R2_CLA_EVIDENCE_ACCESS_KEY_ID}:${R2_CLA_EVIDENCE_SECRET}" \
    --data-binary "$payload" \
    "$url" 2>/dev/null || echo "000"
}

attempt=1
while [[ "$attempt" -le "$attempt_max" ]]; do
  code=$(put_once)
  case "$code" in
    200|201)
      echo "ok status=$code key=$key attempt=$attempt"
      exit 0
      ;;
    412)
      echo "duplicate status=412 key=$key attempt=$attempt (idempotent)"
      exit 0
      ;;
    429|5*)
      if [[ "$attempt" -lt "$attempt_max" ]]; then
        sleep_ms="$backoff"
        # Bash sleeps in seconds; convert ms to fractional seconds.
        sleep "$(awk "BEGIN { printf \"%.3f\", $sleep_ms / 1000 }")"
        backoff=$(( backoff * 2 ))
        attempt=$(( attempt + 1 ))
        continue
      fi
      echo "::error::upload-evidence: ${attempt_max} consecutive 5xx/429; last status=$code key=$key" >&2
      exit 2
      ;;
    4*)
      # 4xx ≠ 412 → fast-fail per Kieran F5.
      echo "::error::upload-evidence: fatal-4xx status=$code key=$key (config bug; stale token or missing perms)" >&2
      exit 2
      ;;
    *)
      echo "::error::upload-evidence: unexpected status=$code key=$key" >&2
      exit 2
      ;;
  esac
done
exit 2
