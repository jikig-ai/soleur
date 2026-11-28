#!/usr/bin/env bash
# Integration tests for plugins/soleur/scripts/seat-liveness.sh and run-health-emit.sh seat summary (#12524).
# Includes live, slow-progress, rate-limited, truncated, dead/zombie, dirty-diff, side-effecting, and 24h TTL controls.

set -euo pipefail

SUITE_TMP=$(mktemp -d)
[[ "$SUITE_TMP" == /* ]] || { echo "FATAL: SUITE_TMP is not absolute: $SUITE_TMP" >&2; exit 2; }
trap 'rm -rf "$SUITE_TMP"' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/test-helpers.sh"

assert_fixture_dir "$SUITE_TMP"

SEAT_CLI="$SCRIPT_DIR/../scripts/seat-liveness.sh"
HEALTH_CLI="$SCRIPT_DIR/../scripts/run-health-emit.sh"

assert_file_exists "$SEAT_CLI" "seat-liveness.sh script exists"

make_run_dir() {
  local d
  d=$(mktemp -d -p "$SUITE_TMP")
  assert_fixture_dir "$d"
  echo "$d"
}

echo "=== T1: --self-test discoverability probe ==="
rc=0
out="$(bash "$SEAT_CLI" --self-test 2>&1)" || rc=$?
assert_eq "0" "$rc" "self-test exits 0"
assert_contains "$out" "SOLEUR_SEAT_LIVENESS_SELFTEST=ok" "self-test prints discoverability literal"

echo "=== T2: live control & clean-completion positive control ==="
RUN_DIR=$(make_run_dir)
assert_fixture_dir "$RUN_DIR"
rc=0
out="$(bash "$SEAT_CLI" init --run-dir "$RUN_DIR" --seat "seat-live" --harness claude --role "soleur:engineering:review:security-sentinel" --tier standard --idle-timeout-ms 120000 --deadline-ms 600000 --artifact-path "$RUN_DIR/live-out.json" --now-ms 1000000 2>&1)" || rc=$?
assert_eq "0" "$rc" "init seat-live exits 0"
assert_contains "$out" "SOLEUR_SEAT_LIVENESS seat=seat-live status=alive action=init" "init emits alive marker"
assert_file_exists "$RUN_DIR/seats/seat-live.json" "seat-live.json created"

rc=0
out="$(bash "$SEAT_CLI" sweep --run-dir "$RUN_DIR" --seat "seat-live" --now-ms 1050000 2>&1)" || rc=$?
assert_eq "0" "$rc" "sweep live seat exits 0"
assert_contains "$out" "SOLEUR_SEAT_LIVENESS seat=seat-live status=alive action=sweep" "live seat classifies as alive"

rc=0
out="$(bash "$SEAT_CLI" decide --run-dir "$RUN_DIR" --seat "seat-live" 2>&1)" || rc=$?
assert_eq "0" "$rc" "decide healthy live seat exits 0"
assert_contains "$out" "SOLEUR_SEAT_LIVENESS seat=seat-live status=alive action=none attempt=0 fallback_tier=none reviewed_coverage=full" "healthy live seat returns action=none"

# Clean-completion positive control: artifact exists and is non-empty on exit 0
printf '{"findings":[]}\n' > "$RUN_DIR/live-out.json"
rc=0
out="$(bash "$SEAT_CLI" sweep --run-dir "$RUN_DIR" --seat "seat-live" --now-ms 1080000 --exited true --exit-code 0 --floor-passed true 2>&1)" || rc=$?
assert_eq "0" "$rc" "sweep clean-completed seat exits 0"
assert_contains "$out" "SOLEUR_SEAT_LIVENESS seat=seat-live status=alive action=sweep" "cleanly exited seat with artifact classifies as alive"

echo "=== T3: slow-progress control — heartbeats reset idle window but never extend deadline_at ==="
RUN_DIR=$(make_run_dir)
assert_fixture_dir "$RUN_DIR"
bash "$SEAT_CLI" init --run-dir "$RUN_DIR" --seat "seat-slow" --harness claude --role "soleur:engineering:review:architecture-strategist" --idle-timeout-ms 120000 --deadline-ms 600000 --now-ms 1000000 >/dev/null
bash "$SEAT_CLI" heartbeat --run-dir "$RUN_DIR" --seat "seat-slow" --now-ms 1100000 >/dev/null
bash "$SEAT_CLI" heartbeat --run-dir "$RUN_DIR" --seat "seat-slow" --now-ms 1200000 >/dev/null

rc=0
out="$(bash "$SEAT_CLI" sweep --run-dir "$RUN_DIR" --seat "seat-slow" --now-ms 1250000 2>&1)" || rc=$?
assert_eq "0" "$rc" "sweep slow-progress seat exits 0"
assert_contains "$out" "SOLEUR_SEAT_LIVENESS seat=seat-slow status=legit_long_turn action=sweep" "slow seat with heartbeats classifies as legit_long_turn"

# Exceed absolute turn cap (1000000 + 600000 = 1600000) even with recent heartbeat at 1595000
bash "$SEAT_CLI" heartbeat --run-dir "$RUN_DIR" --seat "seat-slow" --now-ms 1595000 >/dev/null
rc=0
out="$(bash "$SEAT_CLI" sweep --run-dir "$RUN_DIR" --seat "seat-slow" --now-ms 1600001 2>&1)" || rc=$?
assert_eq "0" "$rc" "sweep past deadline exits 0"
assert_contains "$out" "SOLEUR_SEAT_LIVENESS seat=seat-slow status=crash action=sweep" "absolute deadline cap overrides recent heartbeat"

echo "=== T4: rate-limit control & tier-fallback respawn + max-1 cap ==="
RUN_DIR=$(make_run_dir)
assert_fixture_dir "$RUN_DIR"
bash "$SEAT_CLI" init --run-dir "$RUN_DIR" --seat "seat-rl" --harness devin --role "soleur:engineering:research:repo-research-analyst" --tier standard --now-ms 1000000 >/dev/null
rc=0
out="$(bash "$SEAT_CLI" sweep --run-dir "$RUN_DIR" --seat "seat-rl" --now-ms 1030000 --exited true --exit-code 1 --error "429 Too Many Requests: rate limit exceeded" 2>&1)" || rc=$?
assert_eq "0" "$rc" "sweep rate-limited seat exits 0"
assert_contains "$out" "SOLEUR_SEAT_LIVENESS seat=seat-rl status=rate_limit action=sweep" "429 classifies as rate_limit"

rc=0
out="$(bash "$SEAT_CLI" decide --run-dir "$RUN_DIR" --seat "seat-rl" 2>&1)" || rc=$?
assert_eq "0" "$rc" "decide rate-limited seat attempt 0 exits 0"
assert_contains "$out" "SOLEUR_SEAT_LIVENESS seat=seat-rl status=rate_limit action=respawn attempt=1 fallback_tier=cheap reviewed_coverage=full" "attempt 0 respawns with fallback_tier=cheap"

# Re-running init on an in-flight respawned seat preserves attempt=1 (prevents retry storm)
bash "$SEAT_CLI" init --run-dir "$RUN_DIR" --seat "seat-rl" --harness devin --role "soleur:engineering:research:repo-research-analyst" --tier cheap --now-ms 1040000 >/dev/null

# Second failure on the same seat must escalate (attempt >= 1)
bash "$SEAT_CLI" sweep --run-dir "$RUN_DIR" --seat "seat-rl" --now-ms 1060000 --exited true --exit-code 1 --error "529 Overloaded" >/dev/null
rc=0
out="$(bash "$SEAT_CLI" decide --run-dir "$RUN_DIR" --seat "seat-rl" 2>&1)" || rc=$?
assert_eq "0" "$rc" "decide rate-limited seat attempt 1 exits 0"
assert_contains "$out" "SOLEUR_SEAT_LIVENESS seat=seat-rl status=rate_limit action=escalate attempt=1 fallback_tier=none reviewed_coverage=degraded" "attempt 1 escalates with degraded coverage"

echo "=== T5: truncated control — in-band nudge on capable harness vs respawn on non-nudge harness ==="
RUN_DIR=$(make_run_dir)
assert_fixture_dir "$RUN_DIR"
bash "$SEAT_CLI" init --run-dir "$RUN_DIR" --seat "seat-trunc" --harness claude --role "soleur:engineering:review:code-quality-analyst" --artifact-path "$RUN_DIR/missing-output.json" --now-ms 1000000 >/dev/null
rc=0
out="$(bash "$SEAT_CLI" sweep --run-dir "$RUN_DIR" --seat "seat-trunc" --now-ms 1040000 --exited true --exit-code 0 2>&1)" || rc=$?
assert_eq "0" "$rc" "sweep truncated seat exits 0"
assert_contains "$out" "SOLEUR_SEAT_LIVENESS seat=seat-trunc status=truncated action=sweep" "missing expected artifact on exit 0 classifies as truncated"

rc=0
out="$(bash "$SEAT_CLI" decide --run-dir "$RUN_DIR" --seat "seat-trunc" 2>&1)" || rc=$?
assert_eq "0" "$rc" "decide truncated seat on claude exits 0"
assert_contains "$out" "SOLEUR_SEAT_LIVENESS seat=seat-trunc status=truncated action=nudge attempt=1" "claude truncated seat nudges in-band once"

# Non-nudge harness (opencode, auto-detected from OPENCODE=1 when --harness is omitted) must respawn instead of nudging on truncated seat
OPENCODE=1 CLAUDECODE="" SOLEUR_HARNESS="" bash "$SEAT_CLI" init --run-dir "$RUN_DIR" --seat "seat-trunc-oc" --role "soleur:engineering:review:code-quality-analyst" --artifact-path "$RUN_DIR/missing-output.json" --now-ms 1000000 >/dev/null
bash "$SEAT_CLI" sweep --run-dir "$RUN_DIR" --seat "seat-trunc-oc" --now-ms 1040000 --exited true --exit-code 0 >/dev/null
rc=0
out="$(bash "$SEAT_CLI" decide --run-dir "$RUN_DIR" --seat "seat-trunc-oc" 2>&1)" || rc=$?
assert_eq "0" "$rc" "decide truncated seat on opencode exits 0"
assert_contains "$out" "SOLEUR_SEAT_LIVENESS seat=seat-trunc-oc status=truncated action=respawn attempt=1" "opencode truncated seat respawns instead of nudging"

# childDiskHeartbeat=false harness (devin) degrades to parent-side deadline_at (legit_long_turn at 180s, crash at deadline_at)
DEVIN=1 OPENCODE="" CLAUDECODE="" SOLEUR_HARNESS="" bash "$SEAT_CLI" init --run-dir "$RUN_DIR" --seat "seat-devin-long" --role "soleur:engineering:research:repo-research-analyst" --idle-timeout-ms 120000 --deadline-ms 600000 --now-ms 1000000 >/dev/null
rc=0
out="$(bash "$SEAT_CLI" sweep --run-dir "$RUN_DIR" --seat "seat-devin-long" --now-ms 1180000 2>&1)" || rc=$?
assert_eq "0" "$rc" "sweep in-flight devin seat past idle_timeout_ms exits 0"
assert_contains "$out" "SOLEUR_SEAT_LIVENESS seat=seat-devin-long status=legit_long_turn action=sweep" "childDiskHeartbeat=false harness degrades to legit_long_turn before deadline_at"

echo "=== T6: dead/zombie control & dirty-diff / side-effecting guards ==="
RUN_DIR=$(make_run_dir)
assert_fixture_dir "$RUN_DIR"
bash "$SEAT_CLI" init --run-dir "$RUN_DIR" --seat "seat-writer" --harness opencode --role "resolver-1" --writable true --idle-timeout-ms 120000 --now-ms 1000000 >/dev/null
# Silent for 200s (> 120s idle timeout)
rc=0
out="$(bash "$SEAT_CLI" sweep --run-dir "$RUN_DIR" --seat "seat-writer" --now-ms 1200000 2>&1)" || rc=$?
assert_eq "0" "$rc" "sweep dead/zombie seat exits 0"
assert_contains "$out" "SOLEUR_SEAT_LIVENESS seat=seat-writer status=crash action=sweep" "zombie silent seat classifies as crash"

# Unverified dirty diff must demand verify_disk, never blind respawn
rc=0
out="$(bash "$SEAT_CLI" decide --run-dir "$RUN_DIR" --seat "seat-writer" --dirty-diff true 2>&1)" || rc=$?
assert_eq "0" "$rc" "decide dirty-diff unverified exits 0"
assert_contains "$out" "action=verify_disk" "dirty diff returns verify_disk"

# Verified dirty diff accepts work without respawning
rc=0
out="$(bash "$SEAT_CLI" decide --run-dir "$RUN_DIR" --seat "seat-writer" --dirty-diff true --diff-verified true 2>&1)" || rc=$?
assert_eq "0" "$rc" "decide dirty-diff verified exits 0"
assert_contains "$out" "action=accept" "verified dirty diff returns accept"

# Side-effecting seat escalates immediately on crash
bash "$SEAT_CLI" init --run-dir "$RUN_DIR" --seat "seat-sidefx" --harness claude --role "deploy-worker" --side-effecting true --now-ms 1000000 >/dev/null
bash "$SEAT_CLI" sweep --run-dir "$RUN_DIR" --seat "seat-sidefx" --now-ms 1030000 --exited true --exit-code 1 >/dev/null
rc=0
out="$(bash "$SEAT_CLI" decide --run-dir "$RUN_DIR" --seat "seat-sidefx" 2>&1)" || rc=$?
assert_eq "0" "$rc" "decide side-effecting seat exits 0"
assert_contains "$out" "action=escalate" "side-effecting seat never auto-respawns"

# Cleanly completed third seat to verify completed + recovered + escalated summary
bash "$SEAT_CLI" init --run-dir "$RUN_DIR" --seat "seat-done" --harness claude --role "clean-worker" --now-ms 1000000 >/dev/null
bash "$SEAT_CLI" sweep --run-dir "$RUN_DIR" --seat "seat-done" --now-ms 1020000 --exited true --exit-code 0 >/dev/null

echo "=== T7: metadata-only guard & 24h TTL cleanup + run-health-emit.sh integration ==="
rc=0
out="$(bash "$SEAT_CLI" init --run-dir "$RUN_DIR" --seat "seat-bad" --prompt "forbidden raw prompt" 2>&1)" || rc=$?
assert_eq "2" "$rc" "forbidden --prompt flag rejected with exit 2"
assert_contains "$out" "forbidden metadata-only violation" "forbidden --prompt flag prints metadata-only violation message"

FAKE_SECRET="sk-ant-""api03-abcdefghijklmnopqrstuvwxyz012345"
rc=0
out="$(bash "$SEAT_CLI" init --run-dir "$RUN_DIR" --seat "seat-secret" --role "$FAKE_SECRET" 2>&1)" || rc=$?
assert_eq "2" "$rc" "secret-bearing --role rejected with exit 2"
assert_contains "$out" "secret redaction violation" "secret-bearing --role prints secret redaction violation message"

# Create an expired seat (started at 1000000, now is 1000000 + 90000000 > 86400000 24h TTL)
TTL_DIR=$(make_run_dir)
assert_fixture_dir "$TTL_DIR"
bash "$SEAT_CLI" init --run-dir "$TTL_DIR" --seat "seat-old" --harness claude --role "old-reviewer" --now-ms 1000000 >/dev/null
bash "$SEAT_CLI" init --run-dir "$TTL_DIR" --seat "seat-fresh" --harness claude --role "fresh-reviewer" --now-ms 80000000 >/dev/null
rc=0
out="$(bash "$SEAT_CLI" cleanup --run-dir "$TTL_DIR" --now-ms 91000000 2>&1)" || rc=$?
assert_eq "0" "$rc" "cleanup exits 0"
assert_contains "$out" "SOLEUR_SEAT_LIVENESS_CLEANUP removed=1 retained=1" "cleanup removes expired seat and retains fresh seat"
assert_file_not_exists "$TTL_DIR/seats/seat-old.json" "expired seat-old.json removed"
assert_file_exists "$TTL_DIR/seats/seat-fresh.json" "fresh seat-fresh.json retained"

# run-health-emit.sh summarizes seats in RUN_DIR (even if an earlier phase recorded reviewed_coverage=full)
bash "$HEALTH_CLI" --run-dir "$RUN_DIR" --phase "work" --status "completed" --reviewed-coverage "full"
bash "$HEALTH_CLI" --run-dir "$RUN_DIR" --phase "review" --status "completed"
assert_file_exists "$RUN_DIR/run_health.json" "run_health.json emitted"
summary="$(python3 -c "import json; d=json.load(open('$RUN_DIR/run_health.json')); s=d.get('seats_summary',{}); print(f'total={s.get(\"total\")} completed={s.get(\"completed\")} recovered={s.get(\"recovered\")} escalated={s.get(\"escalated\")} rcov={d.get(\"reviewed_coverage\")}')" 2>/dev/null)"
assert_contains "$summary" "total=3 completed=1 recovered=1 escalated=1 rcov=degraded" "run_health.json records seats_summary and clamps reviewed_coverage to degraded"

print_results 48
