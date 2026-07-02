#!/usr/bin/env bash
# Tests for sdk-bump-sandbox-gate.sh — #5875 item 3 / ADR-079.
#
# Run via:  bash apps/web-platform/scripts/sdk-bump-sandbox-gate.test.sh
# Runs in the CI `test-scripts` shard via the apps/web-platform/scripts/*.test.sh
# glob in scripts/test-all.sh (→ the branch-protection `test` required context).
#
# All fixtures are synthesized inline (cq-test-fixtures-synthesized-only): minimal
# package-lock.json + bun.lock shapes carrying only the two SDK entries the gate reads.

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/sdk-bump-sandbox-gate.sh"

if [[ ! -x "$GATE" ]]; then
  echo "ERROR: $GATE not found or not executable" >&2
  exit 1
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

PASS=0
FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  pass: $1"; PASS=$((PASS + 1)); }

# write_pkglock <path> <agent-sdk-ver> <claude-code-ver>
write_pkglock() {
  cat >"$1" <<JSON
{
  "name": "web-platform",
  "packages": {
    "node_modules/@anthropic-ai/claude-agent-sdk": { "version": "$2" },
    "node_modules/@anthropic-ai/claude-code": { "version": "$3" }
  }
}
JSON
}

# write_bunlock <path> <agent-sdk-ver> <claude-code-ver>  (JSONC packages-map shape)
write_bunlock() {
  cat >"$1" <<JSON
{
  "lockfileVersion": 1,
  "packages": {
    "@anthropic-ai/claude-agent-sdk": ["@anthropic-ai/claude-agent-sdk@$2", {}, "sha512-x=="],
    "@anthropic-ai/claude-agent-sdk-linux-x64": ["@anthropic-ai/claude-agent-sdk-linux-x64@$2", {}, "sha512-y=="],
    "@anthropic-ai/claude-code": ["@anthropic-ai/claude-code@$3", {}, "sha512-z=="],
  }
}
JSON
}

# run_gate — invoke the gate with fixture overrides; captures rc + output.
# args: head_agent head_code bun_agent bun_code base_agent base_code ack
run_gate() {
  write_pkglock "$T/head-pkg.json" "$1" "$2"
  write_bunlock "$T/bun.lock" "$3" "$4"
  write_pkglock "$T/base-pkg.json" "$5" "$6"
  SDK_GATE_PKG_LOCK="$T/head-pkg.json" \
  SDK_GATE_BUN_LOCK="$T/bun.lock" \
  SDK_GATE_BASE_PKG_LOCK="$T/base-pkg.json" \
  SDK_GATE_ACK_TEXT="$7" \
    bash "$GATE" >"$T/out.txt" 2>&1
}

# ---------------------------------------------------------------------------
# T1 — parity OK, no bump (base == head) → exit 0.
# ---------------------------------------------------------------------------
echo "T1: parity OK + no bump → pass"
if run_gate "0.3.197" "2.1.197" "0.3.197" "2.1.197" "0.3.197" "2.1.197" ""; then
  pass "T1 exit 0"
else
  fail "T1 expected exit 0, got $? ($(tail -1 "$T/out.txt"))"
fi

# ---------------------------------------------------------------------------
# T2 — parity mismatch (bun agent-sdk != package-lock) → exit 1, cites parity.
# ---------------------------------------------------------------------------
echo "T2: parity mismatch → fail loud"
if run_gate "0.3.197" "2.1.197" "0.3.150" "2.1.197" "0.3.197" "2.1.197" ""; then
  fail "T2 expected non-zero, got 0"
else
  if grep -q "PARITY MISMATCH" "$T/out.txt"; then pass "T2 fails with parity error"; else fail "T2 wrong message: $(tail -1 "$T/out.txt")"; fi
fi

# ---------------------------------------------------------------------------
# T3 — agent-sdk bump vs base, NO ack → exit 1 (guardrail 2 no-silent-green).
# ---------------------------------------------------------------------------
echo "T3: bump without ack → fail loud"
if run_gate "0.3.200" "2.1.197" "0.3.200" "2.1.197" "0.3.197" "2.1.197" "chore: bump sdk"; then
  fail "T3 expected non-zero, got 0"
else
  if grep -q "acknowledgement is present" "$T/out.txt"; then pass "T3 fails without ack"; else fail "T3 wrong message: $(tail -1 "$T/out.txt")"; fi
fi

# ---------------------------------------------------------------------------
# T4 — same bump WITH ack token → exit 0.
# ---------------------------------------------------------------------------
echo "T4: bump with ack → pass"
if run_gate "0.3.200" "2.1.197" "0.3.200" "2.1.197" "0.3.197" "2.1.197" "chore: bump sdk

sdk-bump-verified: replayed 0.3.200 argv against committed profile, canary green"; then
  pass "T4 exit 0 with ack"
else
  fail "T4 expected exit 0, got $? ($(tail -1 "$T/out.txt"))"
fi

# ---------------------------------------------------------------------------
# T5 — bump is detected on claude-code too (not only agent-sdk), no ack → fail.
# ---------------------------------------------------------------------------
echo "T5: claude-code bump detected without ack → fail"
if run_gate "0.3.197" "2.1.200" "0.3.197" "2.1.200" "0.3.197" "2.1.197" ""; then
  fail "T5 expected non-zero, got 0"
else
  if grep -q "claude-code" "$T/out.txt"; then pass "T5 detects claude-code bump"; else fail "T5 did not name claude-code: $(tail -1 "$T/out.txt")"; fi
fi

# ---------------------------------------------------------------------------
# T6 — a package absent from package-lock → exit 1 (deploy-authoritative missing).
# ---------------------------------------------------------------------------
echo "T6: SDK package absent from package-lock → fail"
cat >"$T/head-pkg.json" <<'JSON'
{ "packages": { "node_modules/@anthropic-ai/claude-code": { "version": "2.1.197" } } }
JSON
write_bunlock "$T/bun.lock" "0.3.197" "2.1.197"
write_pkglock "$T/base-pkg.json" "0.3.197" "2.1.197"
if SDK_GATE_PKG_LOCK="$T/head-pkg.json" SDK_GATE_BUN_LOCK="$T/bun.lock" \
   SDK_GATE_BASE_PKG_LOCK="$T/base-pkg.json" SDK_GATE_ACK_TEXT="" \
   bash "$GATE" >"$T/out.txt" 2>&1; then
  fail "T6 expected non-zero, got 0"
else
  if grep -q "not found in" "$T/out.txt"; then pass "T6 fails on absent package"; else fail "T6 wrong message: $(tail -1 "$T/out.txt")"; fi
fi

# ---------------------------------------------------------------------------
# T7 (non-vacuity) — an ack token present but NO bump must NOT short-circuit the
# parity check: parity mismatch still fails even with the ack present.
# ---------------------------------------------------------------------------
echo "T7: ack present + parity mismatch (no bump) → still fails on parity"
if run_gate "0.3.197" "2.1.197" "0.3.150" "2.1.197" "0.3.197" "2.1.197" "sdk-bump-verified: whatever"; then
  fail "T7 expected non-zero (parity), got 0"
else
  if grep -q "PARITY MISMATCH" "$T/out.txt"; then pass "T7 parity still enforced under ack"; else fail "T7 wrong message: $(tail -1 "$T/out.txt")"; fi
fi

echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
