#!/usr/bin/env bash
# Tests for /ship Phase 7 Step 3.5 sweeper-parseable follow-through directive.
# Run: bash plugins/soleur/test/ship-followthrough-directive.test.sh
#
# Verifies the rewrite from issue #4190:
#   1. The golden issue body parses via the same awk parser used in
#      scripts/sweep-followthroughs.sh:36-48 — extracted script path begins
#      with scripts/followthroughs/ and earliest is a parseable ISO-8601 UTC.
#   2. The stub template carries the # soleur:followthrough-stub vN sentinel.
#   3. SKILL.md Phase 7 Step 3.5 emits the new directive shape and contains
#      no OLD-convention type: keyed YAML keys (manual, http-200, dns-txt,
#      dns-a, sql-query, api-curl) at a YAML key position.
#   4. SKILL.md cross-references the canonical runbook path.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
FIXTURE_DIR="$SCRIPT_DIR/fixtures/followthrough-directive"
SKILL_MD="$REPO_ROOT/plugins/soleur/skills/ship/SKILL.md"
STUB="$REPO_ROOT/plugins/soleur/skills/ship/references/followthrough-stub-template.sh"

echo "=== ship-followthrough-directive tests ==="

# Parser block copied verbatim from scripts/sweep-followthroughs.sh:36-48 so
# the test exercises the EXACT shape the sweeper runs. Edits to the sweeper
# parser MUST be mirrored here; the verbatim-copy convention is the cheap
# defense against drift (plan §Risks and Sharp Edges).
PARSER='/<!-- *soleur:followthrough/, /-->/ {
  gsub(/^<!-- *soleur:followthrough/, "")
  gsub(/-->/, "")
  for (i = 1; i <= NF; i++) {
    if ($i ~ /^script=/)   { sub(/^script=/, "", $i);   print "script "   $i }
    if ($i ~ /^earliest=/) { sub(/^earliest=/, "", $i); print "earliest " $i }
    if ($i ~ /^secrets=/)  { sub(/^secrets=/, "", $i);  print "secrets "  $i }
  }
}'

fail() { echo "FAIL: $*" >&2; exit 1; }

# --- Assertion 1: golden issue body parses into valid script + earliest ---
[[ -f "$FIXTURE_DIR/expected-issue-body.md" ]] \
  || fail "fixture missing: $FIXTURE_DIR/expected-issue-body.md"

parsed=$(awk "$PARSER" "$FIXTURE_DIR/expected-issue-body.md")
script_path=$(echo "$parsed" | awk '/^script /{print $2}')
earliest=$(echo "$parsed" | awk '/^earliest /{print $2}')

[[ -n "$script_path" ]] || fail "parser extracted empty script path from golden body"
case "$script_path" in
  scripts/followthroughs/*) : ;;
  *) fail "script path '$script_path' not under scripts/followthroughs/" ;;
esac
[[ -n "$earliest" ]] || fail "parser extracted empty earliest from golden body"
date -u -d "$earliest" +%s >/dev/null 2>&1 \
  || fail "earliest '$earliest' is not parseable by date -u -d"
echo "  PASS: golden issue body parses (script=$script_path earliest=$earliest)"

# --- Assertion 2: stub template carries the sentinel line ---
[[ -f "$STUB" ]] || fail "stub template missing: $STUB"
grep -qE '^# soleur:followthrough-stub v[0-9]+$' "$STUB" \
  || fail "stub template missing sentinel line '# soleur:followthrough-stub vN'"
echo "  PASS: stub template carries sentinel"

# --- Assertion 3: SKILL.md no longer carries OLD-convention type: keys ---
[[ -f "$SKILL_MD" ]] || fail "SKILL.md missing: $SKILL_MD"
if grep -nE '^[[:space:]]+type:[[:space:]]*(manual|http-200|dns-txt|dns-a|sql-query|api-curl)[[:space:]]*$' "$SKILL_MD"; then
  fail "SKILL.md still emits OLD-convention type: keyed YAML — must use <!-- soleur:followthrough --> directive"
fi
echo "  PASS: SKILL.md contains no OLD-convention type: YAML keys"

# --- Assertion 4: SKILL.md references the canonical runbook ---
grep -qF 'knowledge-base/engineering/ops/runbooks/followthrough-convention.md' "$SKILL_MD" \
  || fail "SKILL.md Step 3.5 does not reference the canonical runbook"
echo "  PASS: SKILL.md references canonical runbook"

echo ""
echo "PASS: ship-followthrough-directive contract"
