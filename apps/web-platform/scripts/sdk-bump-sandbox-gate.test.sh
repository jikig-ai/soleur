#!/usr/bin/env bash
# Tests for sdk-bump-sandbox-gate.sh — #5875 item 3 / ADR-079.
#
# Run via:  bash apps/web-platform/scripts/sdk-bump-sandbox-gate.test.sh
# Runs in the CI `test-scripts` shard via the apps/web-platform/scripts/*.test.sh
# glob in scripts/test-all.sh (→ the branch-protection `test` required context).
#
# All fixtures are synthesized inline (cq-test-fixtures-synthesized-only): minimal
# package-lock.json shapes carrying only the two SDK entries the gate reads.

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

# write_pkglock_missing_agent <path> <claude-code-ver> — the shape the PRESENCE arm
# exists to catch: an SDK package that has VANISHED from the deploy-authoritative
# lockfile. Section 2's bump detection reads this as an empty head_v and short-circuits
# to green, so without section 1 it ships silently (#5849).
write_pkglock_missing_agent() {
  cat >"$1" <<JSON
{
  "name": "web-platform",
  "packages": {
    "node_modules/@anthropic-ai/claude-code": { "version": "$2" }
  }
}
JSON
}

# run_gate — invoke the gate with fixture overrides; captures rc + output.
# args: head_agent head_code <unused> <unused> base_agent base_code ack
run_gate() {
  write_pkglock "$T/head-pkg.json" "$1" "$2"
  write_pkglock "$T/base-pkg.json" "$5" "$6"
  # SDK_GATE_CHANGED_FILES="" keeps the #5913 capture gate dormant for the
  # parity/bump-ack cases (T1-T7); the capture-gate cases (T8+) set it + creds
  # + a mock verify command explicitly.
  SDK_GATE_PKG_LOCK="$T/head-pkg.json" \
  SDK_GATE_BASE_PKG_LOCK="$T/base-pkg.json" \
  SDK_GATE_ACK_TEXT="$7" \
  SDK_GATE_CHANGED_FILES="" \
    bash "$GATE" >"$T/out.txt" 2>&1
}

# run_capture_gate — exercise ONLY the #5913 capture gate (section 3): no bump,
# parity OK; the trigger + creds + mock verify VERDICT are injected. The mock
# verdict JSON is written to a file and the verify command is `cat` on it, so no
# shell brace-expansion mangles the JSON.
# args: changed_files creds(1|0) verdict_json ack
run_capture_gate() {
  write_pkglock "$T/head-pkg.json" "0.3.197" "2.1.197"
  write_pkglock "$T/base-pkg.json" "0.3.197" "2.1.197"
  printf '%s\n' "$3" > "$T/verdict.json"
  local creds_env=()
  [[ "$2" == "1" ]] && creds_env=(ANTHROPIC_API_KEY="sk-test")
  env "${creds_env[@]}" \
    SANDBOX_CANARY_GATE_ENABLED=1 \
    SDK_GATE_PKG_LOCK="$T/head-pkg.json" \
    SDK_GATE_BASE_PKG_LOCK="$T/base-pkg.json" \
    SDK_GATE_ACK_TEXT="$4" \
    SDK_GATE_CHANGED_FILES="$1" \
    SDK_GATE_VERIFY_CMD="cat '$T/verdict.json'" \
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
# T2 (was: bun.lock parity, retired with bun.lock in ADR-191) — an SDK package ABSENT
# from package-lock.json must fail loud. This is the arm that stops section 2's
# short-circuit-to-green on an empty head_v; lint-dual-lockfile.test.sh row 8 asserts
# the arm still exists, and this asserts it still WORKS.
# ---------------------------------------------------------------------------
echo "T2: SDK package missing from package-lock.json → fail loud"
write_pkglock_missing_agent "$T/head-pkg.json" "2.1.197"
write_pkglock "$T/base-pkg.json" "0.3.197" "2.1.197"
if SDK_GATE_PKG_LOCK="$T/head-pkg.json" SDK_GATE_BASE_PKG_LOCK="$T/base-pkg.json" \
   SDK_GATE_ACK_TEXT="" SDK_GATE_CHANGED_FILES="" bash "$GATE" >"$T/out.txt" 2>&1; then
  fail "T2 expected non-zero, got 0 — a vanished SDK package shipped green (#5849)"
else
  if grep -q "not found in" "$T/out.txt"; then pass "T2 fails on a vanished SDK package"; else fail "T2 wrong message: $(tail -1 "$T/out.txt")"; fi
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
write_pkglock "$T/base-pkg.json" "0.3.197" "2.1.197"
if SDK_GATE_PKG_LOCK="$T/head-pkg.json"   SDK_GATE_BASE_PKG_LOCK="$T/base-pkg.json" SDK_GATE_ACK_TEXT="" \
   SDK_GATE_CHANGED_FILES="" \
   bash "$GATE" >"$T/out.txt" 2>&1; then
  fail "T6 expected non-zero, got 0"
else
  if grep -q "not found in" "$T/out.txt"; then pass "T6 fails on absent package"; else fail "T6 wrong message: $(tail -1 "$T/out.txt")"; fi
fi

# ---------------------------------------------------------------------------
# T7 (non-vacuity) — an ack token present must NOT short-circuit the PRESENCE check.
# Otherwise a commit carrying the ack could make a vanished SDK package pass.
# ---------------------------------------------------------------------------
echo "T7: ack present + missing SDK package → still fails on presence"
write_pkglock_missing_agent "$T/head-pkg.json" "2.1.197"
write_pkglock "$T/base-pkg.json" "0.3.197" "2.1.197"
if SDK_GATE_PKG_LOCK="$T/head-pkg.json" SDK_GATE_BASE_PKG_LOCK="$T/base-pkg.json" \
   SDK_GATE_ACK_TEXT="sdk-bump-verified: whatever" SDK_GATE_CHANGED_FILES="" \
   bash "$GATE" >"$T/out.txt" 2>&1; then
  fail "T7 expected non-zero (presence), got 0"
else
  if grep -q "not found in" "$T/out.txt"; then pass "T7 presence still enforced under ack"; else fail "T7 wrong message: $(tail -1 "$T/out.txt")"; fi
fi

# ===========================================================================
# #5913 CAPTURE GATE (section 3) — trigger + creds + verdict handling.
# ===========================================================================
FIX="apps/web-platform/infra/sandbox-canary-argv.json"

# T8 — fixture-only edit + creds + verify_ok → pass (exit 0).
echo "T8: capture trigger + creds + verify_ok → pass"
if run_capture_gate "$FIX" 1 '{"verdict":"verify_ok","reason":"ok"}' ""; then
  pass "T8 exit 0 on verify_ok"
else
  fail "T8 expected exit 0, got $? ($(tail -1 "$T/out.txt"))"
fi

# T9 — capture trigger + creds + argv_drift → BLOCK (exit 1, cites drift).
echo "T9: capture trigger + creds + argv_drift → block"
if run_capture_gate "$FIX" 1 '{"verdict":"canary_infra_error","reason":"argv_drift"}' ""; then
  fail "T9 expected non-zero (drift), got 0"
else
  if grep -q "argv_drift\|STALE" "$T/out.txt"; then pass "T9 blocks on argv_drift"; else fail "T9 wrong message: $(tail -1 "$T/out.txt")"; fi
fi

# T10a — capture trigger + creds + capture-mechanism failure, NO ack → fail (ack-fallback).
echo "T10a: capture failure + no ack → ack-fallback fail"
if run_capture_gate "$FIX" 1 '{"verdict":"canary_infra_error","reason":"capture_no_bwrap:timeout"}' ""; then
  fail "T10a expected non-zero (ack-fallback), got 0"
else
  if grep -q "could not be verified automatically" "$T/out.txt"; then pass "T10a ack-fallback fails without ack"; else fail "T10a wrong message: $(tail -1 "$T/out.txt")"; fi
fi

# T10b — same capture failure WITH the ack → pass (ack-fallback satisfied).
echo "T10b: capture failure + ack → pass"
if run_capture_gate "$FIX" 1 '{"verdict":"canary_infra_error","reason":"capture_no_bwrap:timeout"}' "sdk-bump-verified: validated by hand"; then
  pass "T10b ack-fallback passes with ack"
else
  fail "T10b expected exit 0, got $? ($(tail -1 "$T/out.txt"))"
fi

# T11 — capture trigger + creds ABSENT (fork PR), no ack → fail (ack-fallback, no silent-green).
echo "T11: capture trigger + no creds + no ack → ack-fallback fail"
if run_capture_gate "$FIX" 0 '' ""; then
  fail "T11 expected non-zero (fork ack-fallback), got 0"
else
  if grep -q "ANTHROPIC_API_KEY absent\|no .*ack is present" "$T/out.txt"; then pass "T11 fork degrades to ack, not silent-green"; else fail "T11 wrong message: $(tail -1 "$T/out.txt")"; fi
fi

# T12 — NO capture trigger (unrelated change, no bump) → capture gate dormant → pass.
echo "T12: no capture trigger → gate dormant → pass"
if run_capture_gate "docs/README.md" 1 '' ""; then
  pass "T12 dormant on unrelated change"
else
  fail "T12 expected exit 0, got $? ($(tail -1 "$T/out.txt"))"
fi

# T13 — sandbox-canary.mjs edit is also a trigger (not only the fixture).
echo "T13: mjs edit triggers capture gate (verify_ok) → pass"
if run_capture_gate "apps/web-platform/scripts/sandbox-canary.mjs" 1 '{"verdict":"verify_ok","reason":"ok"}' ""; then
  pass "T13 mjs edit triggers + passes on verify_ok"
else
  fail "T13 expected exit 0, got $? ($(tail -1 "$T/out.txt"))"
fi

# T14 — SANDBOX_CANARY_GATE_ENABLED unset → section 3 DORMANT even on a
# trigger+creds PR (the always-run lockfile-sync gate must not run the paid
# capture / false-block a routine canary-script edit).
echo "T14: capture gate flag OFF → section 3 dormant → pass"
write_pkglock "$T/head-pkg.json" "0.3.197" "2.1.197"
write_pkglock "$T/base-pkg.json" "0.3.197" "2.1.197"
if env ANTHROPIC_API_KEY="sk-test" \
   SDK_GATE_PKG_LOCK="$T/head-pkg.json"   SDK_GATE_BASE_PKG_LOCK="$T/base-pkg.json" SDK_GATE_ACK_TEXT="" \
   SDK_GATE_CHANGED_FILES="$FIX" SDK_GATE_VERIFY_CMD="echo SHOULD_NOT_RUN" \
   bash "$GATE" >"$T/out.txt" 2>&1; then
  if grep -q "SHOULD_NOT_RUN\|verify" "$T/out.txt"; then fail "T14 section 3 ran despite flag off"; else pass "T14 dormant with flag unset"; fi
else
  fail "T14 expected exit 0 (dormant), got $? ($(tail -1 "$T/out.txt"))"
fi

# ---------------------------------------------------------------------------
# T15 — the verify command's STDERR must reach the gate output (#7007).
# The in-image copy prints "FATAL: in-image copy failed ..." on stderr. If the
# verdict capture ever re-acquires a `2>/dev/null`, that diagnostic is destroyed
# and a truncated-tree failure degrades to an ack-fallback with NO cause text in
# the job log. Nothing else here pins it: every other arm's VERIFY_CMD is silent
# on stderr, so re-inserting the redirect leaves the rest of this suite green.
# ---------------------------------------------------------------------------
echo "T15: verify command stderr reaches the gate output"
T15_FIX="apps/web-platform/infra/sandbox-canary-argv.json"
write_pkglock "$T/head-pkg.json" "0.3.197" "2.1.197"
write_pkglock "$T/base-pkg.json" "0.3.197" "2.1.197"
env ANTHROPIC_API_KEY="sk-test" \
  SANDBOX_CANARY_GATE_ENABLED=1 \
  SDK_GATE_PKG_LOCK="$T/head-pkg.json" \
  SDK_GATE_BASE_PKG_LOCK="$T/base-pkg.json" \
  SDK_GATE_ACK_TEXT="" \
  SDK_GATE_CHANGED_FILES="$T15_FIX" \
  SDK_GATE_VERIFY_CMD='printf "SOLEUR_T15_STDERR_MARKER\n" >&2; printf "{\"verdict\":\"verify_ok\",\"reason\":\"ok\"}\n"' \
  bash "$GATE" >"$T/out.txt" 2>&1 || true
if grep -q 'SOLEUR_T15_STDERR_MARKER' "$T/out.txt"; then
  pass "T15 verify stderr reaches the gate output"
else
  fail "T15 verify stderr was swallowed (a 2>/dev/null on the verdict capture?)"
fi

echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
