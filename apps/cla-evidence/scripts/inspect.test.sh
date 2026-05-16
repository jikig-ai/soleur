#!/usr/bin/env bash
# RED-first per cq-write-failing-tests-before. Phase 7.
# TS25: inspect-evidence.sh exits 3 when reading a record whose
# schema_version != "1.0" -- third consumer-boundary assertion per
# Kieran F3 + learning #18.
#
# Strategy: stub `aws` on PATH so list-objects returns a fixture key and
# `s3 cp` returns a fixture body. Run inspect-evidence.sh in by-pr mode
# and assert it exits 3 with the canonical ::error:: annotation when the
# body has schema_version "2.0", or exits 0 when the body has "1.0".

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/inspect-evidence.sh"

red()   { printf '\033[31m%s\033[0m\n' "$*" >&2; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

if [[ ! -x "$SUT" ]]; then
  red "FAIL: $SUT does not exist or is not executable."
  exit 1
fi

# jq is required by the script under test (real CLI, not stubbed).
command -v jq >/dev/null || { red "FAIL: jq not on PATH; cannot run inspect.test.sh"; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Stub `aws`. The SUT (by-pr mode) calls:
#   1) list-objects-v2 --bucket ... --prefix signatures/ --query 'Contents[].Key' --output text
#   2) s3 cp s3://bucket/<key> - (per matching record)
# The fixture body is then filtered server-side by .pr_of_record.number; the
# stub returns ONE key so the body filter is the gate under test.
mk_aws_stub() {
  local fixture_body="$1"
  cat > "$work/aws" <<EOF
#!/usr/bin/env bash
# Stub aws — recognise list-objects-v2 (JSON output for pagination) and s3 cp.
for a in "\$@"; do
  case "\$a" in
    list-objects-v2) MODE=list ;;
    cp)              MODE=cp   ;;
  esac
done
case "\${MODE:-}" in
  list) printf '{"Contents":[{"Key":"signatures/abc123def.json"}]}\n' ;;
  cp)   cat "$work/body.json" ;;
  *)    exit 0 ;;
esac
EOF
  chmod +x "$work/aws"
  printf '%s\n' "$fixture_body" > "$work/body.json"
}

run_sut() {
  PATH="$work:$PATH" \
  R2_CLA_EVIDENCE_ACCESS_KEY_ID=stub-key \
  R2_CLA_EVIDENCE_SECRET=stub-secret \
  R2_CLA_EVIDENCE_BUCKET=soleur-cla-evidence \
  R2_CLA_EVIDENCE_ENDPOINT=https://example.invalid \
    bash "$SUT" by-pr 4242
}

fail=0

# TS25.a: schema_version "1.0" → exits 0, prints record JSON.
mk_aws_stub '{"schema_version":"1.0","actor":{"login":"alice"},"pr_of_record":{"number":4242}}'
if out=$(run_sut 2>&1); then
  if grep -q '"schema_version": "1.0"' <<<"$out"; then
    green "PASS: TS25.a schema_version=1.0 → exit 0 + record echoed"
  else
    red "FAIL: TS25.a expected record body in stdout; got:"
    red "$out"
    fail=1
  fi
else
  red "FAIL: TS25.a expected exit 0 on schema_version=1.0; got non-zero"
  red "$out"
  fail=1
fi

# TS25.b: schema_version "2.0" → exits 3 with ::error:: annotation.
mk_aws_stub '{"schema_version":"2.0","actor":{"login":"alice"},"pr_of_record":{"number":4242}}'
out=$(run_sut 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 3 ]]; then
  if grep -qE '::error::schema_version mismatch' <<<"$out"; then
    green "PASS: TS25.b schema_version=2.0 → exit 3 + ::error:: annotation"
  else
    red "FAIL: TS25.b expected ::error::schema_version mismatch in stderr; got:"
    red "$out"
    fail=1
  fi
else
  red "FAIL: TS25.b expected exit 3 on schema_version=2.0; got rc=$rc"
  red "$out"
  fail=1
fi

# TS25.c: missing schema_version → exits 3 (consumer-boundary assertion).
mk_aws_stub '{"actor":{"login":"alice"},"pr_of_record":{"number":4242}}'
out=$(run_sut 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 3 ]]; then
  green "PASS: TS25.c missing schema_version → exit 3"
else
  red "FAIL: TS25.c expected exit 3 on missing schema_version; got rc=$rc"
  red "$out"
  fail=1
fi

if [[ "$fail" -eq 0 ]]; then
  green "ALL Phase 7 inspect.test.sh tests passed."
fi
exit "$fail"
