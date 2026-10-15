#!/usr/bin/env bash
# Structural + behavioural guard for the egress audit rollup in the shared vector.toml
# (#9545, ADR-288). Two halves:
#
#   1. STRUCTURE (python3 tomllib over the real vector.toml): the rollup reads the egress
#      source directly, the throttle cap and reduce window are what the plan ruled, the sink
#      reads its token ONLY through the default-value interpolation, buffers to disk with
#      drop_newest, and the Better Stack sink inputs are untouched.
#   2. BEHAVIOUR: `vector test` of vector-egress-rollup.test.toml against the real file, when
#      a Vector 0.43.x binary (or the pinned docker image) is reachable. The BLOCKING run is
#      the validate-vector-config.yml step, which installs the binary; here an absent binary
#      is reported as SKIP, never as a pass.
#
# No network. Fixtures are synthetic (*.example.test, documentation IPs, random-looking ids).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VECTOR_TOML="$SCRIPT_DIR/vector.toml"
TESTS_TOML="$SCRIPT_DIR/vector-egress-rollup.test.toml"
VECTOR_IMAGE="${VECTOR_IMAGE:-timberio/vector:0.43.1-alpine}"

command -v python3 >/dev/null 2>&1 || { echo "SETUP FAILED: python3 absent" >&2; exit 2; }
python3 -c 'import tomllib' 2>/dev/null || { echo "SETUP FAILED: python3 tomllib absent (need >=3.11)" >&2; exit 2; }
[[ -f "$VECTOR_TOML" && -f "$TESTS_TOML" ]] || { echo "SETUP FAILED: vector.toml or its test file is missing" >&2; exit 2; }

PASS=0
FAIL=0
SKIP=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
check() { # check <description> <rc>
  if [[ "$2" -eq 0 ]]; then pass "$1"; else fail "$1"; fi
}

echo "-- structure --"
STRUCT="$(python3 - "$VECTOR_TOML" "$TESTS_TOML" <<'PY'
import sys, tomllib
c = tomllib.load(open(sys.argv[1], "rb"))
t, s, so = c["transforms"], c["sinks"], c["sources"]
def row(name, ok):
    print(f"{name}\t{0 if ok else 1}")
prep, thr, red = t["egress_audit_prep"], t["egress_audit_throttle"], t["egress_audit_reduce"]
sink = s["egress_audit_ingest"]
row("prep reads the egress source directly and only that", prep["inputs"] == ["egress_gw_journald"])
row("egress source still admits only the gateway container", so["egress_gw_journald"].get("include_matches", {}).get("CONTAINER_NAME") == ["soleur-egress-gw"])
row("throttle sits between prep and reduce", thr["inputs"] == ["egress_audit_prep"] and red["inputs"] == ["egress_audit_throttle"])
row("throttle cap is 1000 events per workspace per 900 s", thr["threshold"] == 1000 and thr["window_secs"] == 900 and thr["key_field"] == "{{ workspace_id }}")
row("throttle emits per-key discard metrics (the operator-visible flood signal)", thr.get("internal_metrics", {}).get("emit_events_discarded_per_key") is True)
row("reduce groups by workspace, bucket, host, decision AND source host", red["group_by"] == ["workspace_id", "bucket_start", "requested_host", "decision", "source_host"])
row("reduce expires after a full bucket (one row per key per bucket)", red["expire_after_ms"] == 900000)
row("reduce merges counts with sum, first_seen with min, last_seen with max",
    red["merge_strategies"] == {"request_count": "sum", "bytes_out": "sum", "first_seen": "min", "last_seen": "max"})
row("sink targets the same-host ingest route over loopback", sink["uri"] == "http://127.0.0.1:3000/api/internal/egress-audit-ingest")
row("sink authenticates with the bearer strategy", sink.get("auth", {}).get("strategy") == "bearer")
row("sink token is the default-value interpolation", sink.get("auth", {}).get("token") == "${EGRESS_AUDIT_INGEST_TOKEN:-}")
buf = sink.get("buffer", {})
row("sink buffers to disk and drops the newest events when full", buf.get("type") == "disk" and buf.get("when_full") == "drop_newest")
row("disk buffer is at least Vector's 256 MiB minimum", buf.get("max_size", 0) >= 268435488)
row("sink consumes only the shaped rollup", sink["inputs"] == ["egress_audit_shape"])
row("discard marker rides the PII-scrub chain", "egress_audit_throttled_dedupe" in t["pii_scrub_drop_userdata"]["inputs"])
row("Better Stack sink inputs are unchanged", s["betterstack"]["inputs"] == ["tag_journald", "tag_metrics"])
row("the ingest sink has no literal Authorization header", "headers" not in sink.get("request", {}))
import re
hosts = re.findall(r'"requested_host":"([^"\\]*)', open(sys.argv[2]).read())
row("every fixture host is synthetic (example.test, the metadata address or empty)",
    bool(hosts) and all(h == "" or h == "169.254.169.254" or h.lower().endswith("example.test") for h in hosts))
PY
)"
if [[ -z "$STRUCT" ]]; then fail "structure pass produced no rows"; fi
while IFS=$'\t' read -r name rc; do
  [[ -n "$name" ]] || continue
  check "$name" "$rc"
done <<< "$STRUCT"

echo "-- interpolation hygiene --"
# Vector interpolates inside COMMENTS too, so the strict form anywhere in the file (even in prose)
# breaks startup on the host that has no copy of the secret.
STRICT_N="$(grep -cE '\$\{EGRESS_AUDIT_INGEST_TOKEN\}' "$VECTOR_TOML" || true)"
DEFAULT_N="$(grep -cF '${EGRESS_AUDIT_INGEST_TOKEN:-}' "$VECTOR_TOML" || true)"
check "no strict (default-less) reference to the ingest token anywhere, comments included" "$([[ "$STRICT_N" -eq 0 ]]; echo $?)"
check "exactly one default-value reference to the ingest token" "$([[ "$DEFAULT_N" -eq 1 ]]; echo $?)"
check "the token name appears nowhere else as an assignment (no literal secret)" "$(! grep -qE 'EGRESS_AUDIT_INGEST_TOKEN[[:space:]]*=' "$VECTOR_TOML"; echo $?)"

echo "-- fixture file --"
N_TESTS="$(grep -c '^\[\[tests\]\]' "$TESTS_TOML" || true)"
N_NEG="$(grep -c '^no_outputs_from' "$TESTS_TOML" || true)"
check "fixture file carries at least 17 vector tests" "$([[ "$N_TESTS" -ge 17 ]]; echo $?)"
check "fixture file carries at least 13 drop-everything tests (407, probe, non-UUID, no status, injection, bad ts, not JSON, marker)" "$([[ "$N_NEG" -ge 13 ]]; echo $?)"

echo "-- behaviour (vector test against the real vector.toml) --"
run_vector_test() {
  if [[ -n "${VECTOR_BIN:-}" ]] && command -v "$VECTOR_BIN" >/dev/null 2>&1; then
    BETTERSTACK_LOGS_TOKEN=dummy SENTRY_USERID_PEPPER=fixture-only "$VECTOR_BIN" test "$VECTOR_TOML" "$TESTS_TOML"
  elif command -v vector >/dev/null 2>&1 && vector --version 2>/dev/null | grep -q ' 0\.43\.'; then
    BETTERSTACK_LOGS_TOKEN=dummy SENTRY_USERID_PEPPER=fixture-only vector test "$VECTOR_TOML" "$TESTS_TOML"
  elif command -v docker >/dev/null 2>&1 && docker image inspect "$VECTOR_IMAGE" >/dev/null 2>&1; then
    docker run --rm -e BETTERSTACK_LOGS_TOKEN=dummy -e SENTRY_USERID_PEPPER=fixture-only \
      -v "$SCRIPT_DIR:/c:ro" "$VECTOR_IMAGE" test /c/vector.toml /c/vector-egress-rollup.test.toml
  else
    return 99
  fi
}
VT_OUT="$(mktemp -d "${TMPDIR:-/tmp}/vector-egress-rollup.XXXXXX")/out"
trap 'rm -rf "$(dirname "$VT_OUT")"' EXIT
run_vector_test > "$VT_OUT" 2>&1
VT_RC=$?
if [[ "$VT_RC" -eq 99 ]]; then
  if [[ "${REQUIRE_VECTOR_TEST:-0}" == "1" ]]; then
    fail "REQUIRE_VECTOR_TEST=1 but no Vector binary or pinned docker image is reachable (a skip is not a pass here)"
  else
    SKIP=$((SKIP + 1))
    echo "  SKIP: no Vector 0.43.x binary or pinned docker image reachable (the validate-vector-config.yml step runs this blocking)"
  fi
else
  VT_PASSED="$(sed 's/\x1b\[[0-9;]*m//g' "$VT_OUT" | grep -cE '^test .* \.\.\. passed' || true)"
  VT_FAILED="$(sed 's/\x1b\[[0-9;]*m//g' "$VT_OUT" | grep -cE '^test .* \.\.\. failed' || true)"
  check "vector test exits 0" "$([[ "$VT_RC" -eq 0 ]]; echo $?)"
  check "vector test reports no failed test" "$([[ "$VT_FAILED" -eq 0 ]]; echo $?)"
  check "vector test passed every test in the fixture file (not zero)" "$([[ "$VT_PASSED" -eq "$N_TESTS" && "$VT_PASSED" -gt 0 ]]; echo $?)"
fi

echo ""
echo "RESULT: $PASS passed, $FAIL failed, $SKIP skipped"
if [[ $((PASS + FAIL)) -lt 23 ]]; then
  printf '\n[FATAL] anti-vacuity floor: only %d verdict(s) recorded, expected >= 23.\n' "$((PASS + FAIL))" >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]] || exit 1
