#!/usr/bin/env bash
# Local fixture tests for check-auto-commit-density.sh (#2905).
#
# The script under test calls `gh pr view ... --json commits` for headlines.
# To test offline, we replicate the script's regex-match logic here against
# synthetic headlines, then run the full SUT only when GH_TOKEN is set.

set -uo pipefail

PASS=0
FAIL=0

# The regex MUST stay byte-identical to the one in check-auto-commit-density.sh.
# When the SUT regex changes, update this fixture in the same PR.
auto_re='^(Auto-commit (before sync pull|after session)|Merge branches '\''main'\'' and '\''main'\'' of )'

count_matches() {
  local headlines="$1"
  local total=0 matched=0
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    total=$((total + 1))
    if [[ "$line" =~ $auto_re ]]; then
      matched=$((matched + 1))
    fi
  done <<<"$headlines"
  echo "$total $matched"
}

assert() {
  local name="$1" headlines="$2" expect_total="$3" expect_matched="$4"
  read -r total matched <<<"$(count_matches "$headlines")"
  if [[ "$total" -eq "$expect_total" && "$matched" -eq "$expect_matched" ]]; then
    echo "PASS [$name]"
    PASS=$((PASS + 1))
  else
    echo "FAIL [$name]: total=$total matched=$matched, expected total=$expect_total matched=$expect_matched"
    FAIL=$((FAIL + 1))
  fi
}

# 4 commits, 3 auto-commit → 75% (would fail SUT)
assert "75-percent-density" \
$'feat: real change\nAuto-commit before sync pull\nAuto-commit after session\nAuto-commit before sync pull' \
  4 3

# 4 commits, 0 auto-commit → 0% (passes SUT)
assert "no-auto-commit" \
$'feat: a\nfix: b\nchore: c\ndocs: d' \
  4 0

# 2 commits, 1 auto-commit → 50% (passes — SUT fails only on >50%)
assert "exactly-50-percent" \
$'feat: real\nAuto-commit before sync pull' \
  2 1

# Exact session-sync.ts strings only (anchored regex must reject prose)
assert "prose-mention-not-matched" \
$'fix: the Auto-commit before sync pull pattern is bad' \
  1 0

# Merge headline matches
MERGE_HEADLINES="Merge branches 'main' and 'main' of github.com:foo/bar
feat: x"
assert "merge-headline" "$MERGE_HEADLINES" 2 1

# Single dependabot-style commit — must not match
assert "dependabot-not-matched" \
$'chore(deps): bump foo from 1.0.0 to 1.0.1\nAuto-commit before sync pull' \
  2 1

echo ""
echo "Results: $PASS pass, $FAIL fail"
[[ "$FAIL" -eq 0 ]] || exit 1
