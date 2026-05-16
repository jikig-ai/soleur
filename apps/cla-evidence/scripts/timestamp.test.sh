#!/usr/bin/env bash
# RED-first per cq-write-failing-tests-before. Phase 5.
# TS17: RFC 3161 verify-replay against recorded FreeTSA .tsr fixture.
#
# Strategy: bundle a real .tsr captured from https://freetsa.org/tsr at
# fixture-creation time (single submission, well within "do not abuse")
# alongside the FreeTSA root CA + TSA cert (repo assets per plan Phase 5).
# Run `openssl ts -verify` against the fixture. PASS = exit 0 + "Verification: OK".
#
# This is the gate for Phase 5: if openssl ts -verify ever stops accepting the
# fixture (cert rotation by FreeTSA, openssl behavior change), monthly
# timestamping is at risk and the operator must refresh the bundled certs.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES="$SCRIPT_DIR/fixtures"
FREETSA="$(cd "$SCRIPT_DIR/.." && pwd)/freetsa"

red()   { printf '\033[31m%s\033[0m\n' "$*" >&2; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

fail=0

# TS17.a: fixtures + FreeTSA certs exist.
for f in "$FIXTURES/manifest.jsonl" "$FIXTURES/response.tsr" \
         "$FREETSA/cacert.pem" "$FREETSA/tsa.crt"; do
  if [[ ! -s "$f" ]]; then
    red "FAIL: TS17.a missing or empty fixture: $f"
    fail=1
  fi
done
[[ "$fail" -eq 0 ]] && green "PASS: TS17.a fixtures + FreeTSA certs present"

# TS17.b: openssl ts -verify accepts the fixture.tsr against the fixture
# manifest + FreeTSA certs. Captures stdout+stderr and asserts the canonical
# "Verification: OK" line is present (exit 0 alone is not enough — openssl
# can emit warnings then exit 0 without verifying).
if [[ "$fail" -eq 0 ]]; then
  out=$(openssl ts -verify \
    -in "$FIXTURES/response.tsr" \
    -data "$FIXTURES/manifest.jsonl" \
    -CAfile "$FREETSA/cacert.pem" \
    -untrusted "$FREETSA/tsa.crt" 2>&1) || {
      red "FAIL: TS17.b openssl ts -verify exited non-zero"
      red "$out"
      fail=1
    }
  if [[ "$fail" -eq 0 ]] && grep -qE '^Verification: OK$' <<<"$out"; then
    green "PASS: TS17.b openssl ts -verify against fixture → Verification: OK"
  elif [[ "$fail" -eq 0 ]]; then
    red "FAIL: TS17.b openssl ts -verify did not emit 'Verification: OK'"
    red "$out"
    fail=1
  fi
fi

# TS17.c: tampering with the manifest invalidates the timestamp (the
# fixture .tsr binds the SHA-256 of the manifest bytes; any byte change
# must produce a verification failure or the chain is broken).
if [[ "$fail" -eq 0 ]]; then
  tmp_manifest=$(mktemp)
  trap 'rm -f "$tmp_manifest"' EXIT
  # Append one byte — alters SHA-256 deterministically.
  cat "$FIXTURES/manifest.jsonl" > "$tmp_manifest"
  printf 'x' >> "$tmp_manifest"
  if openssl ts -verify \
      -in "$FIXTURES/response.tsr" \
      -data "$tmp_manifest" \
      -CAfile "$FREETSA/cacert.pem" \
      -untrusted "$FREETSA/tsa.crt" >/dev/null 2>&1; then
    red "FAIL: TS17.c tampered manifest verified as OK — chain is not actually bound"
    fail=1
  else
    green "PASS: TS17.c tampered manifest fails verification"
  fi
fi

if [[ "$fail" -eq 0 ]]; then
  green "ALL Phase 5 timestamp.test.sh tests passed."
fi
exit "$fail"
