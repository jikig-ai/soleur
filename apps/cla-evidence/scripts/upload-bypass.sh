#!/usr/bin/env bash
# upload-bypass.sh — R2 conditional-PUT for the per-quarter allowlist-bypass
# canonical record. Companion to upload-evidence.sh (Phase 2).
#
# Differs from upload-evidence.sh in the key derivation only:
#   - Signature record key:   signatures/<sha-of-payload>.json
#   - Bypass record key:      allowlist/<principal_safe>/<yyyy-qN>.json
#
# Behaviour matches upload-evidence.sh: 200/201 → exit 0; 412 → exit 0
# (idempotent, the canonical record already exists for this principal+quarter);
# 5xx/429 → retry up to 3 with backoff; 4xx ≠ 412 → fast-fail (Kieran F5).

set -euo pipefail

if [[ "$#" -lt 1 ]]; then
  echo "::error::usage: upload-bypass.sh <payload-json>" >&2
  exit 64
fi

payload="$1"
bucket="${R2_CLA_EVIDENCE_BUCKET:-soleur-cla-evidence}"
endpoint="${R2_CLA_EVIDENCE_ENDPOINT:?R2_CLA_EVIDENCE_ENDPOINT must be set}"

# Extract principal_safe + quarter from payload (jq is available on
# ubuntu-latest runners by default).
principal_safe=$(printf '%s' "$payload" | jq -r '.principal_safe')
quarter=$(printf '%s' "$payload" | jq -r '.quarter')
if [[ -z "$principal_safe" || "$principal_safe" == "null" || -z "$quarter" || "$quarter" == "null" ]]; then
  echo "::error::upload-bypass: payload missing principal_safe or quarter" >&2
  exit 64
fi
key="allowlist/${principal_safe}/${quarter}.json"
url="${endpoint%/}/${bucket}/${key}"

put_once() {
  curl -sS -o /dev/null -w "%{http_code}\n" --max-time 30 \
    -X PUT \
    -H "If-None-Match: *" \
    -H "Content-Type: application/json" \
    --aws-sigv4 "aws:amz:auto:s3" \
    --user "${R2_CLA_EVIDENCE_ACCESS_KEY_ID}:${R2_CLA_EVIDENCE_SECRET}" \
    --data-binary "$payload" \
    "$url" 2>/dev/null || echo "000"
}

attempt_max=3
backoff=250
attempt=1
while [[ "$attempt" -le "$attempt_max" ]]; do
  code=$(put_once)
  case "$code" in
    200|201)
      echo "ok status=$code key=$key attempt=$attempt"
      exit 0
      ;;
    412)
      echo "duplicate-quarter status=412 key=$key attempt=$attempt (idempotent)"
      exit 0
      ;;
    429|5*)
      if [[ "$attempt" -lt "$attempt_max" ]]; then
        sleep "$(awk "BEGIN { printf \"%.3f\", $backoff / 1000 }")"
        backoff=$(( backoff * 2 ))
        attempt=$(( attempt + 1 ))
        continue
      fi
      echo "::error::upload-bypass: ${attempt_max} 5xx/429; last status=$code key=$key" >&2
      exit 2
      ;;
    4*)
      echo "::error::upload-bypass: fatal-4xx status=$code key=$key" >&2
      exit 2
      ;;
    *)
      echo "::error::upload-bypass: unexpected status=$code key=$key" >&2
      exit 2
      ;;
  esac
done
exit 2
