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
  R2_CLA_EVIDENCE_ENDPOINT=https://0123456789abcdef0123456789abcdef.r2.cloudflarestorage.com \
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

# ── Tombstone-mode tests (issue #3950 item 4) ──────────────────────────────
# Tombstone stub: `s3 cp s3://…/tombstones/<sha>.deleted.json -` returns the
# fixture body. A cp whose s3 URI contains the all-'b' sha emits a 404-shaped
# stderr (genuine "no such erasure"); the all-'c' sha emits a non-404 error
# (AccessDenied) so the reader's 404-vs-transport distinction is exercised.
mk_tombstone_stub() {
  local fixture_body="$1"
  cat > "$work/aws" <<EOF
#!/usr/bin/env bash
MODE=; src=
for a in "\$@"; do
  case "\$a" in
    cp)     MODE=cp ;;
    s3://*) src="\$a" ;;
  esac
done
if [[ "\$MODE" == cp ]]; then
  if [[ "\$src" == *bbbbbbbbbbbbbbbb* ]]; then
    echo "fatal error: An error occurred (404) when calling the HeadObject operation: Not Found" >&2
    exit 1
  fi
  if [[ "\$src" == *cccccccccccccccc* ]]; then
    echo "fatal error: An error occurred (AccessDenied) when calling the GetObject operation: Access Denied" >&2
    exit 1
  fi
  cat "$work/body.json"
  exit 0
fi
exit 0
EOF
  chmod +x "$work/aws"
  printf '%s\n' "$fixture_body" > "$work/body.json"
}

run_tombstone() {
  PATH="$work:$PATH" \
  R2_CLA_EVIDENCE_ACCESS_KEY_ID=stub-key \
  R2_CLA_EVIDENCE_SECRET=stub-secret \
  R2_CLA_EVIDENCE_BUCKET=soleur-cla-evidence \
  R2_CLA_EVIDENCE_ENDPOINT=https://0123456789abcdef0123456789abcdef.r2.cloudflarestorage.com \
    bash "$SUT" tombstone "$1"
}

SHA_OK=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
SHA_MISSING=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
SHA_DENIED=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc

# TS10: tombstone <sha> with schema_version 1.0 → exit 0, body + _key echoed.
mk_tombstone_stub "{\"schema_version\":\"1.0\",\"deleted_at\":\"2026-06-02T00:00:00Z\",\"admin_actor\":\"ops@stub.invalid\",\"gdpr_request_ref\":\"DSAR-2026-001\",\"prior_object_sha\":\"$SHA_OK\",\"override_reason\":\"art17 erasure\"}"
if out=$(run_tombstone "$SHA_OK" 2>&1); then
  if grep -q '"schema_version": "1.0"' <<<"$out" && grep -q "\"_key\": \"tombstones/$SHA_OK.deleted.json\"" <<<"$out"; then
    green "PASS: TS10 tombstone 1.0 → exit 0 + body with _key"
  else
    red "FAIL: TS10 expected 1.0 body + _key in stdout; got:"; red "$out"; fail=1
  fi
else
  red "FAIL: TS10 expected exit 0 on tombstone 1.0; got non-zero"; red "$out"; fail=1
fi

# TS11: tombstone <sha> with schema_version 2.0 → exit 3 (consumer boundary).
mk_tombstone_stub "{\"schema_version\":\"2.0\",\"prior_object_sha\":\"$SHA_OK\"}"
out=$(run_tombstone "$SHA_OK" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 3 ]] && grep -qE '::error::schema_version mismatch' <<<"$out"; then
  green "PASS: TS11 tombstone 2.0 → exit 3 + ::error:: annotation"
else
  red "FAIL: TS11 expected exit 3 + schema_version mismatch; got rc=$rc"; red "$out"; fail=1
fi

# TS12: tombstone <sha> on a genuine 404 → exit 0 with 'no tombstone' message.
mk_tombstone_stub '{"schema_version":"1.0"}'
out=$(run_tombstone "$SHA_MISSING" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]] && grep -qE "no tombstone for ${SHA_MISSING}" <<<"$out"; then
  green "PASS: TS12 genuine 404 → exit 0 + 'no tombstone' message"
else
  red "FAIL: TS12 expected exit 0 + 'no tombstone for <sha>'; got rc=$rc"; red "$out"; fail=1
fi

# TS12b: tombstone fetch FAILS for a non-404 reason (AccessDenied / cred error)
# → exit 1 + ::error:: (must NOT be reported as an authoritative "no tombstone").
mk_tombstone_stub '{"schema_version":"1.0"}'
out=$(run_tombstone "$SHA_DENIED" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 1 ]] && grep -qE '::error::tombstone fetch failed' <<<"$out" && ! grep -qE "no tombstone for ${SHA_DENIED}" <<<"$out"; then
  green "PASS: TS12b non-404 fetch error → exit 1 + ::error::, NOT a false 'no tombstone'"
else
  red "FAIL: TS12b expected exit 1 + 'tombstone fetch failed' + no false negative; got rc=$rc"; red "$out"; fail=1
fi

# TS12c: malformed (non-64-hex) sha → exit 64 before any fetch.
mk_tombstone_stub '{"schema_version":"1.0"}'
out=$(run_tombstone "NOThex-and-too-short" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 64 ]] && grep -qE '::error::object-sha must be 64-char lowercase hex' <<<"$out"; then
  green "PASS: TS12c malformed sha → exit 64 (input-shape guard, mirrors write path)"
else
  red "FAIL: TS12c expected exit 64 + sha-shape error; got rc=$rc"; red "$out"; fail=1
fi

# TS13: by-pr 404 message hints at the tombstone subcommand (item 4 'or' branch).
mk_aws_stub '{"schema_version":"1.0","actor":{"login":"alice"},"pr_of_record":{"number":1}}'
out=$(run_sut 2>&1) && rc=0 || rc=$?
# run_sut queries by-pr 4242; the fixture is PR #1 → no match → hint should fire.
if grep -qE 'no records for PR #4242' <<<"$out" && grep -qE 'tombstone <' <<<"$out"; then
  green "PASS: TS13 by-pr no-match message hints at tombstone subcommand"
else
  red "FAIL: TS13 expected 'no records for PR #4242' + 'tombstone <' hint; got:"; red "$out"; fail=1
fi

if [[ "$fail" -eq 0 ]]; then
  green "ALL Phase 7 inspect.test.sh tests passed."
fi
exit "$fail"
