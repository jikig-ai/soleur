#!/usr/bin/env bash
# AC9 fixture for plan 2026-05-25 (issue #4387): extracts the Phase 7 poll
# bash block from plugins/soleur/skills/ship/SKILL.md and exercises four
# scripted scenarios against mocked `gh` / `git` / `sleep`:
#
#   1. clean MERGED on tick 3
#   2. required-check failure on tick 5 (exit on first failure)
#   3. BEHIND saturation through 6 syncs then structured warning
#   4. DIRTY exit (server-side merge conflict)
#
# Synthesized-only — no live `gh` calls, no network, no real PR
# (per cq-test-fixtures-synthesized-only). Run via:
#
#   bash plugins/soleur/test/ship-phase-7-poll-fixtures.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SKILL="$REPO_ROOT/plugins/soleur/skills/ship/SKILL.md"

PASS=0; FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# ---------------------------------------------------------------------------
# Extract the Phase 7 bash block (between the first ```bash and matching ```)
# ---------------------------------------------------------------------------
BLOCK_FILE="$(mktemp)"
awk '
  /^## Phase 7:/ { phase=1; next }
  phase && /^```bash$/ { capture=1; next }
  capture && /^```$/ { exit }
  capture { print }
' "$SKILL" | sed 's/<number>/4387/g' > "$BLOCK_FILE"

if [[ ! -s "$BLOCK_FILE" ]]; then
  fail "could not extract Phase 7 bash block from $SKILL"
  exit 1
fi
pass "Phase 7 block extracted ($(wc -l < "$BLOCK_FILE") lines)"

# Static syntax check (mitigates Risk 3 — bash heredoc fragility)
if ! bash -n "$BLOCK_FILE" 2>"$BLOCK_FILE.err"; then
  fail "Phase 7 block fails bash -n:"
  sed 's/^/    /' "$BLOCK_FILE.err"
  exit 1
fi
pass "Phase 7 block passes bash -n"

# ---------------------------------------------------------------------------
# Scenario harness. Each scenario file defines `gh()` (and may override
# `git()` to inject conflict states); `sleep` and `date` are always shadowed
# in the subshell to keep the fixture fast and timestamp-stable.
# ---------------------------------------------------------------------------
run_scenario() {
  local label="$1"
  local mocks_file="$2"
  local must_match="$3"
  local must_not_match="${4:-}"
  local logfile
  logfile="$(mktemp)"

  (
    sleep() { return 0; }
    date() { echo "00:00:00"; }
    # Default git: no-op, returns the test branch name for rev-parse.
    # Scenarios may override.
    git() {
      case "$1" in
        rev-parse) echo "test-branch" ;;
        *) return 0 ;;
      esac
    }
    # shellcheck disable=SC1090
    source "$mocks_file"
    # shellcheck disable=SC1090
    source "$BLOCK_FILE"
  ) > "$logfile" 2>&1
  local rc=$?

  if grep -qE "$must_match" "$logfile"; then
    pass "[$label] matched: $must_match"
  else
    fail "[$label] did NOT match: $must_match (rc=$rc)"
    echo "    --- scenario output ---"
    sed 's/^/      /' "$logfile"
    echo "    --- end output ---"
  fi
  if [[ -n "$must_not_match" ]]; then
    if grep -qE "$must_not_match" "$logfile"; then
      fail "[$label] forbidden pattern present: $must_not_match"
      echo "    --- scenario output ---"
      sed 's/^/      /' "$logfile"
      echo "    --- end output ---"
    else
      pass "[$label] forbidden pattern absent: $must_not_match"
    fi
  fi
  rm -f "$logfile"
}

# ---------------------------------------------------------------------------
# Scenario 1 — clean MERGED on tick 3
# ---------------------------------------------------------------------------
SCEN1="$(mktemp)"
cat > "$SCEN1" <<'EOF'
gh() {
  case "$1 $2" in
    "pr view")
      case "$i" in
        1) echo "OPEN BLOCKED" ;;
        2) echo "OPEN CLEAN" ;;
        *) echo "MERGED CLEAN" ;;
      esac
      ;;
    "pr checks") echo "" ;;
    "api "*)     echo "" ;;
  esac
}
EOF
run_scenario "1-clean-merged" "$SCEN1" \
  "MERGED CLEAN" \
  "required check.*FAILED|BEHIND budget exhausted|DIRTY \(merge conflict\)"
rm -f "$SCEN1"

# ---------------------------------------------------------------------------
# Scenario 2 — required-check failure on tick 5
# ---------------------------------------------------------------------------
SCEN2="$(mktemp)"
cat > "$SCEN2" <<'EOF'
gh() {
  case "$1 $2" in
    "pr view")
      echo "OPEN BLOCKED"
      ;;
    "pr checks")
      if [[ "$i" -ge 5 ]]; then
        echo "test"
      fi
      ;;
    "api "*)
      # Required-check name set: includes 'test'
      echo "test"
      echo "e2e"
      ;;
  esac
}
EOF
run_scenario "2-required-ci-fail" "$SCEN2" \
  "required check 'test' FAILED" \
  "Merge poll timed out"
rm -f "$SCEN2"

# ---------------------------------------------------------------------------
# Scenario 3 — BEHIND saturation (6 syncs, then structured warning, heartbeat
# continues to tick 15)
# ---------------------------------------------------------------------------
SCEN3="$(mktemp)"
cat > "$SCEN3" <<'EOF'
gh() {
  case "$1 $2" in
    "pr view")  echo "OPEN BEHIND" ;;
    "pr checks") echo "" ;;
    "api "*)    echo "" ;;
  esac
}
EOF
run_scenario "3-behind-saturation" "$SCEN3" \
  "BEHIND budget exhausted after 6 auto-syncs" \
  "required check.*FAILED|DIRTY \(merge conflict\)"
rm -f "$SCEN3"

# ---------------------------------------------------------------------------
# Scenario 4 — DIRTY (server-side conflict) on tick 2
# ---------------------------------------------------------------------------
SCEN4="$(mktemp)"
cat > "$SCEN4" <<'EOF'
gh() {
  case "$1 $2" in
    "pr view")
      case "$i" in
        1) echo "OPEN BLOCKED" ;;
        *) echo "OPEN DIRTY" ;;
      esac
      ;;
    "pr checks") echo "" ;;
    "api "*)    echo "" ;;
  esac
}
EOF
run_scenario "4-dirty-exit" "$SCEN4" \
  "DIRTY \(merge conflict\)" \
  "Merge poll timed out|BEHIND budget exhausted"
rm -f "$SCEN4"

# ---------------------------------------------------------------------------
rm -f "$BLOCK_FILE" "$BLOCK_FILE.err"
echo
echo "ship-phase-7 fixture: $PASS pass, $FAIL fail"
[[ "$FAIL" -eq 0 ]] || exit 1
