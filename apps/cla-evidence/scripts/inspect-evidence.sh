#!/usr/bin/env bash
# inspect-evidence.sh - third schema_version consumer (Kieran F3 + TS25).
#
# Wraps `aws s3` reads against the soleur-cla-evidence R2 bucket and asserts
# `schema_version === "1.0"` on every record fetched. Exits 3 on schema
# mismatch (paralleling the backfill + sidecar exit codes per learning #18).
#
# Usage:
#   inspect-evidence.sh by-pr <pr-number>
#   inspect-evidence.sh by-contributor <login>
#   inspect-evidence.sh by-quarter <yyyy-qN>

set -euo pipefail

mode="${1:-}"; shift || true
arg="${1:-}"
if [[ -z "$mode" || -z "$arg" ]]; then
  cat <<USAGE >&2
Usage:
  inspect-evidence.sh by-pr <pr-number>
  inspect-evidence.sh by-contributor <login>
  inspect-evidence.sh by-quarter <yyyy-qN>
USAGE
  exit 64
fi

bucket="${R2_CLA_EVIDENCE_BUCKET:-soleur-cla-evidence}"
endpoint="${R2_CLA_EVIDENCE_ENDPOINT:?R2_CLA_EVIDENCE_ENDPOINT must be set}"

command -v aws >/dev/null || { echo "::error::aws CLI required" >&2; exit 64; }
command -v jq  >/dev/null || { echo "::error::jq required" >&2; exit 64; }

aws_exec() {
  AWS_ACCESS_KEY_ID="${R2_CLA_EVIDENCE_ACCESS_KEY_ID:?}" \
  AWS_SECRET_ACCESS_KEY="${R2_CLA_EVIDENCE_SECRET:?}" \
  AWS_REGION=auto \
  aws --endpoint-url "$endpoint" "$@"
}

assert_schema_version() {
  local payload="$1" key="$2"
  if ! printf '%s' "$payload" | jq -e --arg v "1.0" '.schema_version == $v' >/dev/null 2>&1; then
    got=$(printf '%s' "$payload" | jq -r '.schema_version // "<missing>"')
    echo "::error::schema_version mismatch on key=$key: got=\"$got\", want=\"1.0\"" >&2
    exit 3
  fi
}

list_keys() {
  local prefix="$1"
  aws_exec s3api list-objects-v2 --bucket "$bucket" --prefix "$prefix" \
    --query 'Contents[].Key' --output text 2>/dev/null || true
}

fetch_and_print() {
  local key="$1"
  local body
  body=$(aws_exec s3 cp "s3://$bucket/$key" - 2>/dev/null) || {
    echo "::error::failed to fetch $key" >&2
    return 1
  }
  assert_schema_version "$body" "$key"
  jq --arg key "$key" '. + { _key: $key }' <<< "$body"
}

case "$mode" in
  by-pr)
    pr="$arg"
    keys=$(list_keys "signatures/by-pr/${pr}/" | tr '\t' '\n')
    [[ -z "$keys" ]] && { echo "no records for PR #${pr}" >&2; exit 0; }
    for k in $keys; do fetch_and_print "$k"; done
    ;;
  by-contributor)
    login="$arg"
    keys=$(list_keys "signatures/" | tr '\t' '\n' | grep -v '^signatures/by-pr/' || true)
    [[ -z "$keys" ]] && { echo "no signature records found" >&2; exit 0; }
    for k in $keys; do
      body=$(aws_exec s3 cp "s3://$bucket/$k" - 2>/dev/null) || continue
      assert_schema_version "$body" "$k"
      if jq -e --arg l "$login" '.actor.login == $l' >/dev/null 2>&1 <<< "$body"; then
        jq --arg key "$k" '. + { _key: $key }' <<< "$body"
      fi
    done
    ;;
  by-quarter)
    quarter="$arg"
    keys=$(list_keys "allowlist/" | tr '\t' '\n' | grep "/${quarter}\\.json$" || true)
    [[ -z "$keys" ]] && { echo "no allowlist-bypass records for ${quarter}" >&2; exit 0; }
    for k in $keys; do fetch_and_print "$k"; done
    ;;
  *)
    echo "::error::unknown mode: $mode" >&2
    exit 64
    ;;
esac
