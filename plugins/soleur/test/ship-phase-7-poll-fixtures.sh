#!/usr/bin/env bash
# AC9 fixture for plan 2026-05-25 (issue #4387): extracts the Phase 7 poll
# bash block from plugins/soleur/skills/ship/SKILL.md and exercises five
# scripted scenarios against mocked `gh` / `git` / `sleep`:
#
#   1. clean MERGED on tick 3
#   2. required-check failure on tick 5 (exit on first failure)
#   3. BEHIND saturation through 6 syncs then structured warning
#   4. DIRTY exit (server-side merge conflict)
#   5. absent required check (CI not yet registered) — does NOT exit
#
# Also asserts mirror-parity between ship/SKILL.md's canonical block and
# merge-pr/SKILL.md's derived mirror so the two state machines do not drift.
#
# Synthesized-only — no live `gh` calls, no network, no real PR
# (per cq-test-fixtures-synthesized-only). Run via:
#
#   bash plugins/soleur/test/ship-phase-7-poll-fixtures.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SKILL="$REPO_ROOT/plugins/soleur/skills/ship/SKILL.md"
MIRROR="$REPO_ROOT/plugins/soleur/skills/merge-pr/SKILL.md"

PASS=0; FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# ---------------------------------------------------------------------------
# Extract the Phase 7 bash block. Two anchors:
#  - structural: the `<!-- phase-7-poll-block:start -->` / `:end` fence
#    markers (also present in the canonical block as comments)
#  - content fingerprint: the block must contain `MAX_BEHIND_SYNCS` AND
#    `mergeStateStatus` AND `bucket == "fail"` — three load-bearing tokens
#    whose absence indicates we extracted the wrong block (or the block
#    was gutted by a future refactor that the fixture has not caught up to)
# ---------------------------------------------------------------------------
extract_block() {
  local source_file="$1"
  awk '
    /phase-7-poll-block:start/ { in_block=1; next }
    /phase-7-poll-block:end/ { in_block=0 }
    in_block && /^```bash$/ { next }
    in_block && /^```$/ { next }
    in_block { print }
  ' "$source_file"
}

BLOCK_FILE="$(mktemp)"
extract_block "$SKILL" | sed 's/<number>/4387/g' > "$BLOCK_FILE"

if [[ ! -s "$BLOCK_FILE" ]]; then
  fail "could not extract Phase 7 bash block from $SKILL"
  exit 1
fi

# Content fingerprint — three independent tokens
for token in 'MAX_BEHIND_SYNCS' 'mergeStateStatus' 'bucket == "fail"'; do
  if ! grep -q "$token" "$BLOCK_FILE"; then
    fail "extracted block missing fingerprint token: $token (extracted wrong section?)"
    exit 1
  fi
done
pass "Phase 7 block extracted ($(wc -l < "$BLOCK_FILE") lines, 3 fingerprint tokens present)"

# Static syntax check (mitigates Risk 3 — bash heredoc fragility)
if ! bash -n "$BLOCK_FILE" 2>"$BLOCK_FILE.err"; then
  fail "Phase 7 block fails bash -n:"
  sed 's/^/    /' "$BLOCK_FILE.err"
  exit 1
fi
pass "Phase 7 block passes bash -n"

# ---------------------------------------------------------------------------
# Mirror parity: merge-pr/SKILL.md §5.2 carries a derived mirror of the
# canonical block. Assert the structural skeleton matches.
# ---------------------------------------------------------------------------
MIRROR_FILE="$(mktemp)"
extract_block "$MIRROR" > "$MIRROR_FILE"
if [[ ! -s "$MIRROR_FILE" ]]; then
  fail "could not extract Phase 7 mirror from $MIRROR"
else
  # The mirror trims canonical prose but must preserve the same load-bearing
  # tokens. Skeletal parity: every fingerprint token from the canonical site
  # is also in the mirror, and the two share the same emit-line classes.
  for token in 'MAX_BEHIND_SYNCS=6' 'mergeStateStatus' 'bucket == "fail"' \
               '[ship.phase7.required_failed]' '[ship.phase7.dirty]' \
               '[ship.phase7.behind_exhausted]' '*DIRTY*' 'mapfile -t REQUIRED_CHECKS' \
               'is-inside-work-tree'; do
    if ! grep -qF "$token" "$MIRROR_FILE"; then
      fail "merge-pr mirror missing canonical token: $token"
    fi
  done
  [[ "$FAIL" -eq 0 ]] && pass "merge-pr mirror skeleton matches canonical block"
fi

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

# Shared mock prelude: every scenario installs a default fall-through arm
# for `gh` calls the scenario did not handle, so future SKILL.md edits that
# introduce a new `gh` subcommand fail loudly instead of silently no-op'ing.
PRELUDE='
_gh_unexpected() {
  echo "UNEXPECTED gh call: $*" >&2
  return 2
}
'

# ---------------------------------------------------------------------------
# Scenario 1 — clean MERGED on tick 3
# ---------------------------------------------------------------------------
SCEN1="$(mktemp)"
cat > "$SCEN1" <<EOF
${PRELUDE}
gh() {
  case "\$1 \$2" in
    "pr view")
      case "\$i" in
        1) echo "OPEN BLOCKED" ;;
        2) echo "OPEN CLEAN" ;;
        *) echo "MERGED CLEAN" ;;
      esac
      ;;
    "pr checks") : ;;
    "api "*)     : ;;
    *) _gh_unexpected "\$@" ;;
  esac
}
EOF
run_scenario "1-clean-merged" "$SCEN1" \
  "MERGED CLEAN" \
  "ship.phase7.(required_failed|dirty|behind_exhausted)|UNEXPECTED gh call"
rm -f "$SCEN1"

# ---------------------------------------------------------------------------
# Scenario 2 — required-check failure on tick 5
# ---------------------------------------------------------------------------
SCEN2="$(mktemp)"
cat > "$SCEN2" <<EOF
${PRELUDE}
gh() {
  case "\$1 \$2" in
    "pr view") echo "OPEN BLOCKED" ;;
    "pr checks")
      if [[ "\$i" -ge 5 ]]; then
        echo "test"
      fi
      ;;
    "api "*)
      echo "test"
      echo "e2e"
      ;;
    *) _gh_unexpected "\$@" ;;
  esac
}
EOF
run_scenario "2-required-ci-fail" "$SCEN2" \
  "\[ship\.phase7\.required_failed\] check='test'" \
  "Merge poll timed out|UNEXPECTED gh call"
rm -f "$SCEN2"

# ---------------------------------------------------------------------------
# Scenario 3 — BEHIND saturation (6 syncs, then structured warning, heartbeat
# continues to tick 15)
# ---------------------------------------------------------------------------
SCEN3="$(mktemp)"
cat > "$SCEN3" <<EOF
${PRELUDE}
gh() {
  case "\$1 \$2" in
    "pr view")   echo "OPEN BEHIND" ;;
    "pr checks") : ;;
    "api "*)     : ;;
    *) _gh_unexpected "\$@" ;;
  esac
}
EOF
run_scenario "3-behind-saturation" "$SCEN3" \
  "\[ship\.phase7\.behind_exhausted\] BEHIND budget exhausted after 6 auto-syncs" \
  "ship.phase7.(required_failed|dirty)|UNEXPECTED gh call"
rm -f "$SCEN3"

# ---------------------------------------------------------------------------
# Scenario 4 — DIRTY (server-side conflict) on tick 2
# ---------------------------------------------------------------------------
SCEN4="$(mktemp)"
cat > "$SCEN4" <<EOF
${PRELUDE}
gh() {
  case "\$1 \$2" in
    "pr view")
      case "\$i" in
        1) echo "OPEN BLOCKED" ;;
        *) echo "OPEN DIRTY" ;;
      esac
      ;;
    "pr checks") : ;;
    "api "*)     : ;;
    *) _gh_unexpected "\$@" ;;
  esac
}
EOF
run_scenario "4-dirty-exit" "$SCEN4" \
  "\[ship\.phase7\.dirty\] PR is DIRTY \(merge conflict\)" \
  "Merge poll timed out|ship\.phase7\.behind_exhausted|UNEXPECTED gh call"
rm -f "$SCEN4"

# ---------------------------------------------------------------------------
# Scenario 5 — absent required check (CI not yet registered) does NOT exit.
# Required set = ["test", "e2e"]; `gh pr checks` returns only "test" with
# bucket=pass (no fail event). The loop must heartbeat through to timeout
# rather than treating an unregistered required check as a failure.
# ---------------------------------------------------------------------------
SCEN5="$(mktemp)"
cat > "$SCEN5" <<EOF
${PRELUDE}
gh() {
  case "\$1 \$2" in
    "pr view")   echo "OPEN BLOCKED" ;;
    "pr checks") : ;;  # no failures returned
    "api "*)
      echo "test"
      echo "e2e"
      ;;
    *) _gh_unexpected "\$@" ;;
  esac
}
EOF
run_scenario "5-absent-required-check" "$SCEN5" \
  "Merge poll timed out" \
  "ship\.phase7\.(required_failed|dirty|behind_exhausted)|UNEXPECTED gh call"
rm -f "$SCEN5"

# ---------------------------------------------------------------------------
rm -f "$BLOCK_FILE" "$BLOCK_FILE.err" "$MIRROR_FILE"
echo
echo "ship-phase-7 fixture: $PASS pass, $FAIL fail"
[[ "$FAIL" -eq 0 ]] || exit 1
