#!/usr/bin/env bash
# r2-conditional-put.sh — shared R2 conditional-PUT primitive (single source of
# truth per Kieran F7). Used by upload-evidence.sh and upload-bypass.sh, which
# differ only in key derivation. Both wrappers compute the key, then exec this
# script with (key, payload).
#
# Behaviour (matches the prior duplicated bodies in upload-{evidence,bypass}.sh):
#   - PUT <bucket>/<key> with `If-None-Match: *`.
#   - 200 / 201        → ok-label, exit 0.
#   - 412              → dup-label, exit 0 (idempotent first-writer-wins).
#   - 5xx / 429        → retry up to 3 with 250ms / 500ms / 1000ms backoff.
#   - 4xx ≠ 412        → fast-fail (Kieran F5; e.g., 403 from stale token is a
#                        config bug, not transient).
#
# Status classification uses explicit integer comparisons rather than shell
# globs (`5*` would match "5" or "50"; the prior `case` was ordering-coupled —
# 429 only reached the retry arm because `429|5*` was listed before `4*`).
#
# Inputs:
#   $1                            object key (e.g., signatures/<sha>.json)
#   $2                            JSON payload
#   $LABEL                        (optional) per-caller label for log lines
#                                 ("upload-evidence" by default; wrappers set
#                                 e.g. "upload-bypass" or "upload-receipt").
#   $DUP_LABEL                    (optional) per-caller word for the 412 case
#                                 ("duplicate" by default).
#
# Required environment:
#   R2_CLA_EVIDENCE_ACCESS_KEY_ID R2 access key.
#   R2_CLA_EVIDENCE_SECRET        R2 secret access key.
#   R2_CLA_EVIDENCE_BUCKET        Bucket name (default: soleur-cla-evidence).
#   R2_CLA_EVIDENCE_ENDPOINT      S3-compat endpoint URL.

set -euo pipefail

if [[ "$#" -lt 2 ]]; then
  echo "::error::usage: r2-conditional-put.sh <key> <payload-json>" >&2
  exit 64
fi

key="$1"
payload="$2"
label="${LABEL:-upload-evidence}"
dup_label="${DUP_LABEL:-duplicate}"
bucket="${R2_CLA_EVIDENCE_BUCKET:-soleur-cla-evidence}"
endpoint="${R2_CLA_EVIDENCE_ENDPOINT:?R2_CLA_EVIDENCE_ENDPOINT must be set}"
url="${endpoint%/}/${bucket}/${key}"

put_once() {
  # Stub-friendly: in tests, $(which curl) is the PATH-stub that emits a numeric
  # HTTP code on stdout. In production, curl is invoked with full SigV4 via
  # --aws-sigv4 (curl 7.75+) and emits the code via -w "%{http_code}".
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

  # Integer comparisons — `case` globs are ordering-coupled and fragile.
  # `5*` matches both "5" and "500"; `4*` matches "4". Using arithmetic
  # guards removes that coupling and makes the classification order-
  # independent and refactor-safe.
  if ! [[ "$code" =~ ^[0-9]+$ ]]; then
    echo "::error::${label}: non-numeric status=$code key=$key" >&2
    exit 2
  fi

  if (( code == 200 || code == 201 )); then
    echo "ok status=$code key=$key attempt=$attempt"
    exit 0
  fi

  if (( code == 412 )); then
    echo "${dup_label} status=412 key=$key attempt=$attempt (idempotent)"
    exit 0
  fi

  if (( code == 429 || (code >= 500 && code < 600) )); then
    if (( attempt < attempt_max )); then
      sleep "$(awk "BEGIN { printf \"%.3f\", $backoff / 1000 }")"
      backoff=$(( backoff * 2 ))
      attempt=$(( attempt + 1 ))
      continue
    fi
    echo "::error::${label}: ${attempt_max} consecutive 5xx/429; last status=$code key=$key" >&2
    exit 2
  fi

  if (( code >= 400 && code < 500 )); then
    # 4xx ≠ 412 → fast-fail per Kieran F5 (e.g., 403 from stale token is a
    # config bug, not transient).
    echo "::error::${label}: fatal-4xx status=$code key=$key (config bug; stale token or missing perms)" >&2
    exit 2
  fi

  echo "::error::${label}: unexpected status=$code key=$key" >&2
  exit 2
done

exit 2
