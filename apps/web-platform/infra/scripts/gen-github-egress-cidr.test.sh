#!/usr/bin/env bash
# Unit tests for gen-github-egress-cidr.sh (#5284) — the self-refreshing GitHub
# /meta CIDR generator. Drives the generator offline against a synthesized
# fixture (cq-test-fixtures-synthesized-only); never touches live /meta.
#
# Run: bash apps/web-platform/infra/scripts/gen-github-egress-cidr.test.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEN="$SCRIPT_DIR/gen-github-egress-cidr.sh"
LOADER="$SCRIPT_DIR/../cron-egress-nftables.sh"
FIXTURE="$SCRIPT_DIR/../test-fixtures/github-meta-sample.json"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Synthesized golden body (the (.git+.api) IPv4 union of the fixture, sort -u;
# IPv6 dropped, the duplicate 192.0.2.0/24 collapsed).
read -r -d '' EXPECTED_BODY <<'EOF'
192.0.2.0/24
198.51.100.0/24
203.0.113.10/32
203.0.113.11/32
EOF

echo "--- gen-github-egress-cidr.sh tests ---"

echo "-- parse + presence --"
if bash -n "$GEN"; then pass "generator parses (bash -n)"; else fail "generator parses (bash -n)"; fi
if [[ -f "$FIXTURE" ]]; then pass "fixture exists"; else fail "fixture exists"; fi

echo "-- golden body + header markers --"
OUT1="$WORK/cidr-golden.txt"
if META_JSON_FILE="$FIXTURE" OUT="$OUT1" bash "$GEN" >/dev/null 2>&1; then
  pass "generates against fixture (exit 0)"
else
  fail "generates against fixture (exit 0)"
fi
ACTUAL_BODY="$(grep -vE '^[[:space:]]*(#|$)' "$OUT1" 2>/dev/null)"
if [[ "$ACTUAL_BODY" == "$EXPECTED_BODY" ]]; then
  pass "body == expected (.git+.api) IPv4 union, sort -u"
else
  fail "body mismatch — got:[$ACTUAL_BODY]"
fi
grep -qF 'DO NOT EDIT' "$OUT1" && pass "header carries DO NOT EDIT" || fail "header carries DO NOT EDIT"
grep -qF 'gen-github-egress-cidr.sh' "$OUT1" && pass "header names the generator script" || fail "header names the generator script"
grep -qF 'https://api.github.com/meta' "$OUT1" && pass "header carries source URL" || fail "header carries source URL"
grep -qE '^# Snapshot:' "$OUT1" && pass "header carries a Snapshot: line" || fail "header carries a Snapshot: line"
TODAY="$(date -u +%F)"
grep -qE "^# Generated: ${TODAY}\$" "$OUT1" && pass "header carries Generated: today (UTC)" || fail "header carries Generated: today"
grep -qF '(.git+.api)[]|select(test(":")|not)' "$OUT1" && pass "header carries verbatim jq filter (AC2)" || fail "header carries verbatim jq filter"

echo "-- IPv6 drop + dedup --"
if ! printf '%s' "$ACTUAL_BODY" | grep -q ':'; then pass "IPv6 entries dropped (no ':' in body)"; else fail "IPv6 entries dropped"; fi
DUP_N="$(grep -cxF '192.0.2.0/24' "$OUT1")"
if [[ "$DUP_N" -eq 1 ]]; then pass "duplicate collapsed (192.0.2.0/24 once)"; else fail "duplicate collapsed (got $DUP_N)"; fi

echo "-- fail-loud on bad input (file untouched, exit non-zero) --"
assert_reject() { # $1 desc, $2 meta-json-content
  local desc="$1" content="$2"
  local guard="$WORK/guard-$RANDOM.txt"
  printf 'SENTINEL\n' > "$guard"
  local bad="$WORK/bad-$RANDOM.json"
  printf '%s' "$content" > "$bad"
  if META_JSON_FILE="$bad" OUT="$guard" bash "$GEN" >/dev/null 2>&1; then
    fail "$desc (should exit non-zero)"
  elif [[ "$(cat "$guard")" == "SENTINEL" ]] && [[ -z "$(ls "$guard".* 2>/dev/null)" ]]; then
    pass "$desc (rejected; output untouched; no stray tmp)"
  else
    fail "$desc (output mutated or stray tmp left)"
  fi
}
assert_reject "non-JSON body"        'not json at all'
assert_reject "empty object {}"      '{}'
assert_reject "missing .api key"     '{"git":["192.0.2.0/24"]}'
assert_reject "IPv6-only (empty extraction)" '{"git":["2001:db8::/48"],"api":["2001:db8:1::/48"]}'
assert_reject "over-broad 0.0.0.0/0" '{"git":["0.0.0.0/0"],"api":["203.0.113.10/32"]}'
assert_reject "over-broad /4 prefix" '{"git":["10.0.0.0/4"],"api":["203.0.113.10/32"]}'
assert_reject "nft-injection shape"  '{"git":["192.0.2.0/24}; add rule x"],"api":["203.0.113.10/32"]}'

echo "-- date-header no-op (body unchanged → byte-identical, date not advanced) --"
OUT2="$WORK/cidr-noop.txt"
META_JSON_FILE="$FIXTURE" OUT="$OUT2" bash "$GEN" >/dev/null 2>&1
# Backdate the Generated: line to prove a no-op re-run does NOT restamp it.
sed -i -E 's/^# Generated: .*/# Generated: 2000-01-01/' "$OUT2"
BEFORE="$(cat "$OUT2")"
META_JSON_FILE="$FIXTURE" OUT="$OUT2" bash "$GEN" >/dev/null 2>&1
AFTER="$(cat "$OUT2")"
if [[ "$BEFORE" == "$AFTER" ]]; then
  pass "no-op re-run leaves file byte-identical (date not advanced)"
else
  fail "no-op re-run rewrote the file (date churn)"
fi

echo "-- idempotent (two fresh runs byte-identical) --"
OUT3="$WORK/cidr-a.txt"; OUT4="$WORK/cidr-b.txt"
META_JSON_FILE="$FIXTURE" OUT="$OUT3" bash "$GEN" >/dev/null 2>&1
META_JSON_FILE="$FIXTURE" OUT="$OUT4" bash "$GEN" >/dev/null 2>&1
if diff -q "$OUT3" "$OUT4" >/dev/null; then pass "two fresh runs byte-identical"; else fail "two fresh runs differ"; fi

echo "-- --check mode --"
OUT5="$WORK/cidr-check.txt"
META_JSON_FILE="$FIXTURE" OUT="$OUT5" bash "$GEN" >/dev/null 2>&1
if META_JSON_FILE="$FIXTURE" OUT="$OUT5" bash "$GEN" --check >/dev/null 2>&1; then
  pass "--check exits 0 when committed body matches /meta"
else
  fail "--check exits 0 when matches"
fi
# Mutate the body → drift → --check must exit 1.
sed -i 's#203.0.113.11/32#203.0.113.99/32#' "$OUT5"
if META_JSON_FILE="$FIXTURE" OUT="$OUT5" bash "$GEN" --check >/dev/null 2>&1; then
  fail "--check exits 1 on body drift"
else
  pass "--check exits 1 on body drift"
fi

echo "-- validator parity with the loader (#5268) --"
# The generator must carry the loader's is_valid_ipv4_cidr regex byte-for-byte.
CIDR_RE='([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})/([0-9]{1,2})'
CIDR_RANGE='o1 <= 255 && o2 <= 255 && o3 <= 255 && o4 <= 255 && prefix <= 32'
if grep -qF -- "$CIDR_RE" "$GEN" && grep -qF -- "$CIDR_RE" "$LOADER"; then
  pass "CIDR regex literal pinned identically in generator and loader"
else
  fail "CIDR regex literal drift between generator and loader"
fi
if grep -qF -- "$CIDR_RANGE" "$GEN" && grep -qF -- "$CIDR_RANGE" "$LOADER"; then
  pass "CIDR range-check arithmetic pinned identically in generator and loader"
else
  fail "CIDR range-check drift between generator and loader"
fi

echo "-- atomic-write invariants (source-shape) --"
grep -qF "trap 'rm -f" "$GEN" && pass "EXIT trap removes the temp file on failure" || fail "EXIT trap present"
grep -qE 'mktemp .*\$\{?OUT' "$GEN" && pass "mktemp in the target dir (atomic mv, same fs)" || fail "mktemp in the target dir"
grep -qF 'curl -fsS --max-time 30' "$GEN" && pass "live fetch is bounded (curl --max-time 30, AC11)" || fail "live fetch bounded"

echo ""
echo "RESULT: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
