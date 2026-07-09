#!/usr/bin/env bash
# Tests the zot registry-host cloud-init boot-guard + disk-observability + resize2fs
# hardening added in #6240/#6244 (cloud-init-registry.yml).
#
# TWO layers:
#   1. BEHAVIORAL (the load-bearing part): the boot isolation self-check now expects THREE
#      admitted secrets {ZOT_PULL_TOKEN, ZOT_PUSH_TOKEN, BETTERSTACK_LOGS_TOKEN}. This test
#      EXTRACTS the admit-regex + the cardinality integer FROM cloud-init-registry.yml (so the
#      decision logic under test is the SAME bytes the host boots with — no re-derived copy to
#      drift) and evaluates the guard's exact predicate against synthesized name-sets. The
#      2-secret set (the OLD cardinality) must now FATAL — that is the RED→GREEN behavioral
#      change this fix ships. Fixtures are SYNTHESIZED (cq-test-fixtures-synthesized-only).
#   2. STRUCTURAL grep assertions: resize2fs fail-loud (no `|| true`), device-wait, e2fsprogs,
#      .resize-result persistence, the SOLEUR_ZOT_DISK field set, the `doppler run` cron wrap,
#      and the tightened gc/retention values.
#
# Static + pure-bash — no docker, no network, no doppler.
#
# Run: bash apps/web-platform/infra/registry-boot-guard.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI="$SCRIPT_DIR/cloud-init-registry.yml"

PASS=0
FAIL=0
assert() {
  local desc="$1" cond="$2"
  if eval "$cond"; then PASS=$((PASS + 1)); echo "  PASS: $desc"
  else FAIL=$((FAIL + 1)); echo "  FAIL: $desc"; echo "        condition: $cond"; fi
}

echo "=== registry boot-guard + disk-observability (#6240/#6244) tests ==="
assert "cloud-init-registry.yml exists" "[[ -f '$CI' ]]"

# --- Extract the guard's admit-regex + cardinality straight from the file (no drift) ---
GUARD_RE="$(grep -F 'n_admitted=' "$CI" | grep -oE "grep -Ec '[^']*'" | sed "s/grep -Ec '//; s/'$//")"
# shellcheck disable=SC2016  # literal $n_total is intentional — we grep the file's own guard text
CARD="$(grep -oE '\[ "\$n_total" -ne [0-9]+ \]' "$CI" | grep -oE '[0-9]+' | head -1)"
echo "--- extracted: admit-regex='${GUARD_RE}' cardinality='${CARD}' ---"
assert "admit-regex was extracted" "[[ -n '$GUARD_RE' ]]"
assert "cardinality extracted and == 3" "[[ '$CARD' == '3' ]]"
assert "admit-regex names BETTERSTACK_LOGS_TOKEN" "grep -q 'BETTERSTACK_LOGS_TOKEN' <<<'$GUARD_RE'"

# guard_decision: replays the file's exact predicate (strip DOPPLER_ builtins, count total +
# admitted, FATAL unless both == CARD). Prints PASS/FATAL; returns 0 on PASS.
guard_decision() {
  local names n_total n_admitted
  names="$(printf '%s\n' "$@" | grep -v '^DOPPLER_' || true)"
  n_total="$(printf '%s\n' "$names" | grep -c . || true)"
  n_admitted="$(printf '%s\n' "$names" | grep -Ec "$GUARD_RE" || true)"
  if [ "$n_total" -ne "$CARD" ] || [ "$n_admitted" -ne "$CARD" ]; then echo FATAL; return 1; fi
  echo PASS; return 0
}

echo "--- behavioral: boot isolation self-check decision ---"
# The exact isolated 3-secret set → PASS.
assert "the 3 admitted secrets PASS the guard" \
  "[[ \"\$(guard_decision ZOT_PULL_TOKEN ZOT_PUSH_TOKEN BETTERSTACK_LOGS_TOKEN)\" == PASS ]]"
# The OLD 2-secret set is now rejected (the RED→GREEN behavioral change).
assert "the OLD 2-secret set now FATALs (cardinality raised 2->3)" \
  "[[ \"\$(guard_decision ZOT_PULL_TOKEN ZOT_PUSH_TOKEN)\" == FATAL ]]"
# An over-scoped credential leaks a foreign secret → n_total=4 → FATAL (fail-closed).
assert "an over-scoped 4th (foreign) secret FATALs" \
  "[[ \"\$(guard_decision ZOT_PULL_TOKEN ZOT_PUSH_TOKEN BETTERSTACK_LOGS_TOKEN SUPABASE_SERVICE_ROLE_KEY)\" == FATAL ]]"
# Right count (3) but wrong identity (a non-admitted name) → FATAL (identity, not just cardinality).
assert "3 names but wrong identity FATALs (identity assert)" \
  "[[ \"\$(guard_decision ZOT_PULL_TOKEN ZOT_PUSH_TOKEN FOO_TOKEN)\" == FATAL ]]"
# DOPPLER_* builtins are stripped before counting (so they do not inflate n_total).
assert "DOPPLER_* builtins are stripped before counting" \
  "[[ \"\$(guard_decision ZOT_PULL_TOKEN ZOT_PUSH_TOKEN BETTERSTACK_LOGS_TOKEN DOPPLER_PROJECT DOPPLER_CONFIG)\" == PASS ]]"

echo "--- structural: resize2fs fail-loud (#6240) ---"
assert "resize2fs is invoked in an if (exit code captured, not swallowed)" \
  "grep -qE 'if resize2fs \"\\\$DEV\"; then' '$CI'"
# The silent-swallow was `resize2fs ... || true` on a COMMAND line; the historical comment that
# documents the old bug legitimately still contains that string, so exclude comment lines first.
assert "no 'resize2fs ... || true' silent-swallow on any command line" \
  "! grep -vE '^[[:space:]]*#' '$CI' | grep -qE 'resize2fs.*\\|\\| true'"
assert "device-wait loop precedes mount (attach race)" \
  "grep -qE 'for i in \\\$\\(seq 1 30\\); do \\[ -b \"\\\$DEV\" \\]' '$CI'"
assert "e2fsprogs is in packages:" "grep -qE '^[[:space:]]*-[[:space:]]*e2fsprogs' '$CI'"
assert "e2fsprogs runcmd dpkg re-ensure guard present (packages: stage non-fatal)" \
  "grep -qE 'dpkg -s e2fsprogs' '$CI'"
assert "ext4-on-raw-device (no-partition) invariant asserted" \
  "grep -qE 'lsblk -no TYPE .*grep -q .\\^part' '$CI'"
assert ".resize-result is persisted for the reporter" \
  "grep -qF '/var/lib/zot/.resize-result' '$CI'"

echo "--- structural: SOLEUR_ZOT_DISK self-report (#6244) ---"
assert "SOLEUR_ZOT_DISK marker line emitted" "grep -qF 'SOLEUR_ZOT_DISK pcent=' '$CI'"
for f in pcent= fs_size_gb= block_size_gb= resize_ok= zot_restarts= ping_rc=; do
  assert "SOLEUR_ZOT_DISK carries field ${f}" "grep -qF 'LINE=\"SOLEUR_ZOT_DISK' '$CI' && grep -qF '${f}' '$CI'"
done
assert "ships via Better Stack Logs Authorization: Bearer token" \
  "grep -qF 'Authorization: Bearer \$TOKEN' '$CI'"
assert "cron wraps the reporter in doppler run (isolated soleur-registry/prd)" \
  "grep -qF 'doppler run --project soleur-registry --config prd -- /usr/local/bin/zot-disk-heartbeat.sh' '$CI'"
assert "absence-based <85% liveness ping retained" "grep -qE '\"\\\$USE\" -lt 85' '$CI'"

echo "--- structural: gc/retention TIMING preserved (#6240 defense-in-depth) ---"
assert "gcInterval tightened to 1h" "grep -qF '\"gcInterval\": \"1h\"' '$CI'"
assert "gcInterval no longer 24h" "! grep -qF '\"gcInterval\": \"24h\"' '$CI'"
assert "retention.delay tightened to 2h" "grep -qF '\"delay\": \"2h\"' '$CI'"
assert "gcDelay dangling-blob safety window preserved at 1h" "grep -qF '\"gcDelay\": \"1h\"' '$CI'"
assert "deleteReferrers stays false (tag-based sigs, not Subject referrers)" "grep -qF '\"deleteReferrers\": false' '$CI'"

echo "--- structural: capacity-vs-retention keep-set (#6247) ---"
# Anchor on the keepTags JSON fragments, NOT comment prose (the narrative block also names
# sha256-* / 5 / 50). The invariant under test: the previously-UNBOUNDED sha256-.* keep is now
# BOUNDED, and v*/commit-sha counts are lowered 10->5.
assert "sha256-.* cosign referrer keep-set now BOUNDED (was unbounded 'keep forever')" \
  "grep -qF '\"patterns\": [\"sha256-.*\"], \"mostRecentlyPushedCount\": 50' '$CI'"
assert "v* tag keep-set lowered to 5" \
  "grep -qF '\"patterns\": [\"v.*\"], \"mostRecentlyPushedCount\": 5' '$CI'"
assert "commit-sha tag keep-set lowered to 5" \
  "grep -qF '\"patterns\": [\"[0-9a-f]{7,64}\"], \"mostRecentlyPushedCount\": 5' '$CI'"
assert "no keepTags count left at the old value 10" \
  "! grep -qF '\"mostRecentlyPushedCount\": 10' '$CI'"

echo ""
echo "=== registry-boot-guard.test.sh: ${PASS} passed, ${FAIL} failed ==="
[ "$FAIL" -eq 0 ] || exit 1
