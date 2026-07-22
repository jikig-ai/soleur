#!/usr/bin/env bash
# Runtime contract has moved to apps/web-platform/server/inngest/functions/cron-compound-promote.ts
# (TR9 PR-11). This test script covers the retained hand-testing script only; it does NOT
# test the Inngest handler runtime contract (see test/server/inngest/cron-compound-promote.test.ts).
#
# Tests for scripts/compound-promote.sh.
#
# Covers Phase 2 of the compound-promotion-loop plan
# (knowledge-base/project/plans/2026-05-11-feat-compound-promotion-loop-plan.md):
#   T1: no promotion-config.yml → exit 0 + `::compound-promote-status::no-config`
#   T2: promotion-config.yml with `enabled: false` → exit 0 +
#       `::compound-promote-status::disabled`
#   T3: GDPR shell pre-pass excludes any learning matching the canonical PII
#       regex BEFORE the Anthropic call. We assert the script emits
#       `::compound-promote-pii-excluded::<path>` for the PII fixture AND that
#       the mocked curl is called with a corpus payload that omits that path.
#
# Isolation: each test builds a throwaway repo via `mktemp -d`, copies the
# tracked fixtures from tests/fixtures/compound-promote/learnings/ into it,
# and points the script at the temp root via COMPOUND_PROMOTE_FIXTURE_ROOT.
# GH_BIN / CURL_BIN env vars redirect the script to mock binaries so no real
# Anthropic call or `gh pr list` runs.
#
# Issue: #2720.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/compound-promote.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURES_SRC="$REPO_ROOT/tests/fixtures/compound-promote/learnings"

PASS=0
FAIL=0
TOTAL=0

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq missing"; exit 0; }

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
  TOTAL=$((TOTAL + 1))
}

assert_contains() {
  local name="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name"
    echo "  needle:   $needle"
    echo "  haystack: ${haystack:0:400}"
    FAIL=$((FAIL + 1))
  fi
  TOTAL=$((TOTAL + 1))
}

assert_not_contains() {
  local name="$1" needle="$2" haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name"
    echo "  forbidden needle: $needle"
    echo "  haystack: ${haystack:0:400}"
    FAIL=$((FAIL + 1))
  fi
  TOTAL=$((TOTAL + 1))
}

make_temp_root() {
  # Throwaway repo skeleton: matches the layout the SUT expects relative to
  # COMPOUND_PROMOTE_FIXTURE_ROOT (knowledge-base/project/learnings + optional
  # promotion-config.yml + scripts/retired-rule-ids.txt).
  local root
  root=$(mktemp -d)
  mkdir -p "$root/knowledge-base/project/learnings" "$root/scripts"
  echo "$root"
}

copy_fixtures() {
  # Mirror tests/fixtures/compound-promote/learnings/*.md into the temp root.
  local root="$1"
  cp "$FIXTURES_SRC"/*.md "$root/knowledge-base/project/learnings/"
}

make_mock_gh() {
  # gh stub: only `gh pr list --label self-healing/auto --state open` is called
  # by the SUT; returns an empty JSON array (zero open PRs → full week-cap
  # remaining).
  local path="$1"
  cat > "$path" <<'EOF'
#!/usr/bin/env bash
# Mock gh for compound-promote tests.
case "$*" in
  "pr list --label self-healing/auto --state open --json number --jq length")
    echo 0
    ;;
  *)
    echo "[]"
    ;;
esac
EOF
  chmod +x "$path"
}

make_mock_curl() {
  # curl stub: writes the request body (from -d "$REQUEST") to $CURL_CAPTURE
  # so the test can inspect which files appeared in the corpus payload, then
  # emits a canned Anthropic-shaped response (a single text content block
  # containing a valid empty JSON array — sufficient to exercise the response
  # parse path without staging cluster diffs).
  local path="$1" capture="$2"
  cat > "$path" <<EOF
#!/usr/bin/env bash
# Capture the request payload for assertions.
CAPTURE="$capture"
# Walk args, find -d <payload> or --data <payload>, write payload to capture.
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -d|--data|--data-raw)
      printf '%s' "\$2" > "\$CAPTURE"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
# Emit a canned Anthropic response: empty clusters array.
printf '%s' '{"content":[{"type":"text","text":"[]"}]}'
EOF
  chmod +x "$path"
}

# --- T1: no promotion-config.yml → exit 0 + no-config sentinel ----------------
t1_no_config_returns_noop() {
  local root; root=$(make_temp_root)
  copy_fixtures "$root"
  local gh_bin="$root/gh"; make_mock_gh "$gh_bin"
  local curl_bin="$root/curl"; make_mock_curl "$curl_bin" "$root/curl-capture.txt"

  local out exit_code=0
  out=$(COMPOUND_PROMOTE_FIXTURE_ROOT="$root" \
        GH_BIN="$gh_bin" \
        CURL_BIN="$curl_bin" \
        ANTHROPIC_API_KEY="fake-key-not-used" \
        bash "$SUT" 2>&1) || exit_code=$?

  assert_eq        "T1 exit code is 0"          "0" "$exit_code"
  assert_contains  "T1 emits no-config sentinel" \
                   "::compound-promote-status::no-config" "$out"
  assert_eq        "T1 mock curl never called"  "false" \
                   "$([[ -f "$root/curl-capture.txt" ]] && echo true || echo false)"
  rm -rf "$root"
}

# --- T2: promotion-config.yml with enabled:false → disabled sentinel ----------
t2_disabled_config_returns_noop() {
  local root; root=$(make_temp_root)
  copy_fixtures "$root"
  cat > "$root/knowledge-base/project/promotion-config.yml" <<'EOF'
enabled: false
EOF
  local gh_bin="$root/gh"; make_mock_gh "$gh_bin"
  local curl_bin="$root/curl"; make_mock_curl "$curl_bin" "$root/curl-capture.txt"

  local out exit_code=0
  out=$(COMPOUND_PROMOTE_FIXTURE_ROOT="$root" \
        GH_BIN="$gh_bin" \
        CURL_BIN="$curl_bin" \
        ANTHROPIC_API_KEY="fake-key-not-used" \
        bash "$SUT" 2>&1) || exit_code=$?

  assert_eq        "T2 exit code is 0"           "0" "$exit_code"
  assert_contains  "T2 emits disabled sentinel" \
                   "::compound-promote-status::disabled" "$out"
  assert_eq        "T2 mock curl never called"   "false" \
                   "$([[ -f "$root/curl-capture.txt" ]] && echo true || echo false)"
  rm -rf "$root"
}

# --- T3: GDPR shell pre-pass excludes PII fixtures before Anthropic call ------
# This test is the load-bearing safety assertion. The PII fixture
# (2026-05-11-pii-email.md) contains a synthesized `test@example.com` that
# matches the canonical PII regex. The script MUST emit a `pii-excluded`
# sentinel for it AND the corpus payload sent to (mocked) curl MUST omit it.
# Both conditions matter: the sentinel proves the script saw the file; the
# corpus check proves the file did not leak into the Anthropic-bound payload.
# Per the plan's "gate-absent vs gate-present" RED guidance, the second
# assertion is what would fail if the pre-pass were silently bypassed.
t3_gdpr_pre_pass_excludes_pii_files() {
  local root; root=$(make_temp_root)
  copy_fixtures "$root"
  cat > "$root/knowledge-base/project/promotion-config.yml" <<'EOF'
enabled: true
EOF
  local gh_bin="$root/gh"; make_mock_gh "$gh_bin"
  local curl_bin="$root/curl"; make_mock_curl "$curl_bin" "$root/curl-capture.txt"

  local out exit_code=0
  out=$(COMPOUND_PROMOTE_FIXTURE_ROOT="$root" \
        GH_BIN="$gh_bin" \
        CURL_BIN="$curl_bin" \
        ANTHROPIC_API_KEY="fake-key-for-mock" \
        bash "$SUT" 2>&1) || exit_code=$?

  assert_eq        "T3 exit code is 0"          "0" "$exit_code"
  assert_contains  "T3 emits enabled sentinel" \
                   "::compound-promote-status::enabled" "$out"
  assert_contains  "T3 emits pii-excluded sentinel for the email fixture" \
                   "::compound-promote-pii-excluded::knowledge-base/project/learnings/2026-05-11-pii-email.md" \
                   "$out"

  # Negative space: the corpus payload sent to curl MUST NOT include the
  # PII fixture path. This is the gate-present assertion.
  local payload=""
  [[ -f "$root/curl-capture.txt" ]] && payload=$(cat "$root/curl-capture.txt")
  assert_contains    "T3 curl captured (pre-pass did NOT short-circuit)" \
                     "messages" "$payload"
  assert_not_contains "T3 corpus payload OMITS the PII fixture path" \
                     "2026-05-11-pii-email.md" "$payload"
  # And the safe fixtures DO appear in the corpus.
  assert_contains    "T3 corpus payload INCLUDES safe-learning-one.md" \
                     "2026-05-11-safe-learning-one.md" "$payload"
  rm -rf "$root"
}

# --- T4: retired-rule pre-pass drops learnings referenced in retired-rule-ids.txt
# Reviewer #16: the original regex (`knowledge-base/project/learnings/[^ ]+\.md`)
# never matched rule-prune.sh's actual breadcrumb format. The fix broadens to
# `knowledge-base/[^ |]+\.md`. This test confirms the broader regex catches
# both learnings/ and constitution/skill paths in the breadcrumb column.
t4_retired_rule_pre_pass_excludes() {
  local root; root=$(make_temp_root)
  copy_fixtures "$root"
  cat > "$root/knowledge-base/project/promotion-config.yml" <<'EOF'
enabled: true
EOF
  # Synthesize a retired-rule row whose breadcrumb names safe-learning-one.md.
  cat > "$root/scripts/retired-rule-ids.txt" <<EOF
hr-synth-retired-test | 2026-05-11 | #0000 | retiring per knowledge-base/project/learnings/2026-05-11-safe-learning-one.md context
EOF
  local gh_bin="$root/gh"; make_mock_gh "$gh_bin"
  local curl_bin="$root/curl"; make_mock_curl "$curl_bin" "$root/curl-capture.txt"

  local out exit_code=0
  out=$(COMPOUND_PROMOTE_FIXTURE_ROOT="$root" \
        GH_BIN="$gh_bin" \
        CURL_BIN="$curl_bin" \
        ANTHROPIC_API_KEY="fake-key-for-mock" \
        bash "$SUT" 2>&1) || exit_code=$?

  assert_eq        "T4 exit code is 0" "0" "$exit_code"
  assert_contains  "T4 emits retired-excluded sentinel for safe-learning-one" \
                   "::compound-promote-retired-excluded::knowledge-base/project/learnings/2026-05-11-safe-learning-one.md" \
                   "$out"
  local payload=""
  [[ -f "$root/curl-capture.txt" ]] && payload=$(cat "$root/curl-capture.txt")
  assert_not_contains "T4 corpus OMITS the retired learning" \
                     "2026-05-11-safe-learning-one.md" "$payload"
  # safe-learning-two is NOT retired and is NOT PII; it must survive.
  assert_contains    "T4 corpus INCLUDES the non-retired safe-learning-two" \
                     "2026-05-11-safe-learning-two.md" "$payload"
  rm -rf "$root"
}

# --- T5: week-cap-reached short-circuits before any work --------------------
# Reviewer code-quality M3 + test-design top-3: untested branches in the SUT.
# When mock gh reports 2 open self-healing/auto PRs (= WEEK_CAP_DEFAULT), the
# script MUST emit week-cap-reached and exit 0 WITHOUT calling curl.
t5_week_cap_reached_short_circuits() {
  local root; root=$(make_temp_root)
  copy_fixtures "$root"
  cat > "$root/knowledge-base/project/promotion-config.yml" <<'EOF'
enabled: true
EOF
  # gh mock that reports 2 open PRs (== WEEK_CAP_DEFAULT) so REMAINING == 0.
  local gh_bin="$root/gh"
  cat > "$gh_bin" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"pr list"*"self-healing/auto"*"--state open"*"--json number"*"--jq length"*) echo 2 ;;
  *) echo "[]" ;;
esac
EOF
  chmod +x "$gh_bin"
  local curl_bin="$root/curl"; make_mock_curl "$curl_bin" "$root/curl-capture.txt"

  local out exit_code=0
  out=$(COMPOUND_PROMOTE_FIXTURE_ROOT="$root" \
        GH_BIN="$gh_bin" \
        CURL_BIN="$curl_bin" \
        ANTHROPIC_API_KEY="fake-key-not-used" \
        bash "$SUT" 2>&1) || exit_code=$?

  assert_eq        "T5 exit code is 0"            "0" "$exit_code"
  assert_contains  "T5 emits week-cap sentinel"   "::compound-promote-week-cap::0" "$out"
  assert_contains  "T5 emits week-cap-reached"    "::compound-promote-status::week-cap-reached" "$out"
  # Most importantly: curl was never called (no payload captured).
  assert_eq        "T5 mock curl never called"    "false" \
                   "$([[ -f "$root/curl-capture.txt" ]] && echo true || echo false)"
  rm -rf "$root"
}

# --- T6: byte-budget sentinel emits live AGENTS payload size ----------------
# Reviewer agent-native #1: the budget MUST be computed in the driver, not
# just asserted in the prompt. Emits the sentinel so the workflow / aggregator
# / reviewer can see the live size. Assert the sentinel fires with both
# numeric fields populated.
t6_byte_budget_sentinel_emitted() {
  local root; root=$(make_temp_root)
  copy_fixtures "$root"
  cat > "$root/knowledge-base/project/promotion-config.yml" <<'EOF'
enabled: true
EOF
  # Synthesize stand-in AGENTS files so the driver has something to wc.
  printf 'idx\n' > "$root/AGENTS.md"
  printf 'core\n' > "$root/AGENTS.core.md"
  local gh_bin="$root/gh"; make_mock_gh "$gh_bin"
  local curl_bin="$root/curl"; make_mock_curl "$curl_bin" "$root/curl-capture.txt"

  local out exit_code=0
  out=$(COMPOUND_PROMOTE_FIXTURE_ROOT="$root" \
        GH_BIN="$gh_bin" \
        CURL_BIN="$curl_bin" \
        ANTHROPIC_API_KEY="fake-key-for-mock" \
        bash "$SUT" 2>&1) || exit_code=$?

  assert_eq        "T6 exit code is 0"               "0" "$exit_code"
  # `idx\n` = 4 bytes, `core\n` = 5 bytes → total = 9. The sentinel reports the
  # HARD ceiling (ALWAYS_LOADED_CAP), which tracks B_ALWAYS_REJECT in
  # scripts/lint-agents-rule-budget.py — not the lower proposal budget.
  assert_contains  "T6 byte-budget sentinel with 9:23000" \
                   "::compound-promote-byte-budget::9:23000" "$out"
  rm -rf "$root"
}

t1_no_config_returns_noop
t2_disabled_config_returns_noop
t3_gdpr_pre_pass_excludes_pii_files
t4_retired_rule_pre_pass_excludes
t5_week_cap_reached_short_circuits
t6_byte_budget_sentinel_emitted

echo
echo "PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"
[[ "$FAIL" -eq 0 ]] || exit 1
