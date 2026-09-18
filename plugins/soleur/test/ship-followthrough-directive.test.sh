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

# THE PARSER IS NO LONGER MIRRORED HERE -- it is the sweeper's own, sourced.
#
# This file used to carry a hand-copied `parse_directive`, with a header instructing future
# authors to mirror edits into it and an assertion 5 that diff-checked the copy against the
# real one. #7490 is the proof that both failed: the sweeper's predicate was widened (CommonMark
# fences, `~~~`, fence-length tracking, CRLF, two new END metas) and this copy was not touched,
# while assertion 5 stayed GREEN -- because its only fixture, `expected-issue-body.md`, contains
# ZERO fence lines, so the comparison was blind to every property that changed.
#
# A copy that must be manually synced plus a comparison that cannot see the difference is worse
# than no guard: it reports agreement. Sourcing the shipped function removes the copy, so
# assertion 5 below is now a tautology and is replaced by a REACHABILITY check -- the thing that
# can actually fail is the function no longer loading.
# shellcheck disable=SC1090
source "$REPO_ROOT/scripts/sweep-followthroughs.sh" >/dev/null 2>&1 || true
if ! declare -F parse_directive >/dev/null; then
  echo "FAIL: parse_directive did not load from scripts/sweep-followthroughs.sh" >&2
  exit 1
fi
run_parser() { parse_directive < "$1"; }


fail() { echo "FAIL: $*" >&2; exit 1; }

# --- Assertion 1: golden issue body parses into valid script + earliest ---
[[ -f "$FIXTURE_DIR/expected-issue-body.md" ]] \
  || fail "fixture missing: $FIXTURE_DIR/expected-issue-body.md"

parsed=$(run_parser "$FIXTURE_DIR/expected-issue-body.md")
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

# --- Assertion 5: the sourced parser actually SKIPS a fenced directive ---
# The old assertion compared this file's copy of the parser against the sweeper's. With the
# copy gone that is `x == x`. What is still worth pinning -- and what the old assertion could
# never see, because its fixture had no fence -- is the BEHAVIOUR the ship template depends on:
# a directive inside a fence must yield no `script=`, and must be reported as fenced.
fenced_body=$(mktemp)
{
  printf '## Verification\n\n```html\n'
  grep -m1 '^<!-- soleur:followthrough' "$FIXTURE_DIR/expected-issue-body.md" \
    || printf '<!-- soleur:followthrough script=scripts/followthroughs/x.sh earliest=2020-01-01T00:00:00Z -->\n'
  printf '```\n'
} > "$fenced_body"
fenced_out=$(run_parser "$fenced_body")
rm -f "$fenced_body"
grep -q '^script ' <<<"$fenced_out" \
  && fail "a FENCED directive yielded a script= -- the sweeper's fence skip is not in effect"
grep -q 'fenced_directive_count' <<<"$fenced_out" \
  || fail "a FENCED directive did not emit fenced_directive_count -- the tracker would rot silently"
echo "  PASS: a fenced directive yields no script= and is reported as fenced"

echo ""
echo "PASS: ship-followthrough-directive contract"
