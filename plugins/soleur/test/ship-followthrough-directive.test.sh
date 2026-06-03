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

# Parser block mirrored from scripts/sweep-followthroughs.sh parse_directive()
# so the test exercises the EXACT shape the sweeper runs. Edits to the sweeper
# parser MUST be mirrored here; assertion 5 below diff-checks against the
# sweeper's actual parse_directive() so drift is caught at PR time.
# shellcheck disable=SC2016  # single quotes are intentional — awk vars ($i, $NF) must not be bash-expanded
PARSER='BEGIN { in_dir = 0; seen = 0; closing = 0; fence = 0 }
/^```/ { fence = !fence; next }
fence { next }
/^<!-- *soleur:followthrough/ {
  seen++
  if (seen == 1) in_dir = 1
}
/-->/ && in_dir {
  closing = 1
}
in_dir {
  gsub(/^<!-- *soleur:followthrough/, "")
  gsub(/-->/, "")
  for (i = 1; i <= NF; i++) {
    if ($i ~ /^script=/)   { sub(/^script=/, "", $i);   print "script "   $i }
    if ($i ~ /^earliest=/) { sub(/^earliest=/, "", $i); print "earliest " $i }
    if ($i ~ /^secrets=/)  { sub(/^secrets=/, "", $i);  print "secrets "  $i }
  }
}
closing { in_dir = 0; closing = 0 }
END { if (seen > 1) print "__sweeper_meta__ multi_directive_count " seen }'

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
grep -qF 'knowledge-base/engineering/operations/runbooks/followthrough-convention.md' "$SKILL_MD" \
  || fail "SKILL.md Step 3.5 does not reference the canonical runbook"
echo "  PASS: SKILL.md references canonical runbook"

# --- Assertion 5: this test's PARSER is behaviorally equivalent to the
#     sweeper's parse_directive() on the canonical fixture. Catches drift
#     between the test/SKILL.md awk-block copies and the authoritative parser
#     at PR time (pattern-recognition P1-1, multi-agent review of #4190).
SWEEPER="$REPO_ROOT/scripts/sweep-followthroughs.sh"
[[ -f "$SWEEPER" ]] || fail "sweeper script missing: $SWEEPER"
# Source parse_directive() in a subshell to avoid pulling in main(); use sed
# to extract the function body and eval it in isolation.
sweeper_fn=$(sed -n '/^parse_directive() {/,/^}/p' "$SWEEPER")
[[ -n "$sweeper_fn" ]] || fail "could not extract parse_directive() from sweeper"
sweeper_out=$(bash -c "$sweeper_fn
parse_directive < '$FIXTURE_DIR/expected-issue-body.md'")
test_out=$(awk "$PARSER" "$FIXTURE_DIR/expected-issue-body.md")
if [[ "$sweeper_out" != "$test_out" ]]; then
  echo "FAIL: test PARSER output differs from sweeper parse_directive()" >&2
  echo "--- sweeper parse_directive ---" >&2
  printf '%s\n' "$sweeper_out" >&2
  echo "--- test PARSER ---" >&2
  printf '%s\n' "$test_out" >&2
  exit 1
fi
echo "  PASS: test PARSER and sweeper parse_directive produce equivalent output"

echo ""
echo "PASS: ship-followthrough-directive contract"
