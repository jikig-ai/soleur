#!/usr/bin/env bash
# Tests for scripts/sweep-followthroughs.sh hardening (issue #4193).
#
# Covers the three gaps surfaced by multi-agent review of PR #4191:
#   T1 (Gap 1, HIGH):   realpath canonicalization rejects `..` traversal that
#                       a bare case-glob prefix-match would accept.
#   T2 (Gap 2, MEDIUM): multi-directive bodies honor the FIRST directive only
#                       and emit the warning the line-35 comment promises.
#   T3 (Gap 3, LOW):    awk start-range is anchored to column 1, so a directive
#                       embedded mid-prose does not parse.
#   T4 (regression):    canonical single-directive body at column 1 still
#                       parses and runs to completion (DRY_RUN=1).
#
# Each test runs in its own tmpdir with a stubbed `gh` on PATH, so no real
# GitHub API call is ever attempted.
#
# Run: bash scripts/sweep-followthroughs.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/sweep-followthroughs.sh"

PASS=0
FAIL=0
TOTAL=0

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
    echo "  haystack: ${haystack:0:600}"
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
    echo "  haystack: ${haystack:0:600}"
    FAIL=$((FAIL + 1))
  fi
  TOTAL=$((TOTAL + 1))
}

# Make a tmpdir with a stubbed `gh` that fails loudly if invoked. The sweeper
# only reaches `gh issue close` / `gh issue comment` when run_one chooses to
# act on a real issue; DRY_RUN=1 short-circuits before that, so the stub
# exists only as a safety net.
setup_tmpdir() {
  local root
  root=$(mktemp -d)
  mkdir -p "$root/scripts/followthroughs" "$root/bin"
  cat > "$root/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "TEST BUG: real gh invoked with: $*" >&2
exit 99
EOF
  chmod +x "$root/bin/gh"
  echo "$root"
}

# Invoke run_one from within $tmpdir with the given body. Captures combined
# stdout+stderr and returns run_one's exit code via a sidecar file so the
# caller can assert both.
invoke_run_one() {
  local tmpdir="$1" body="$2" issue_num="${3:-9999}"
  local rc_file="$tmpdir/run-one-rc"
  local out
  # Subshell so the sourced sweeper's top-level side effects (set -euo
  # pipefail, REPO=, now_epoch=) do not leak back into the test harness.
  out=$(
    cd "$tmpdir"
    export PATH="$tmpdir/bin:$PATH"
    export GH_REPO="test/test"
    export DRY_RUN=1
    # shellcheck disable=SC1090
    source "$SUT"
    set +e
    run_one "$issue_num" "$body" 2>&1
    echo "$?" > "$rc_file"
  )
  local rc
  rc=$(cat "$rc_file")
  printf '%s\n__RC__=%s\n' "$out" "$rc"
}

# --- T1 (Gap 1): realpath rejects path traversal --------------------------
t1_realpath_rejects_traversal() {
  local root; root=$(setup_tmpdir)
  # Create a real `bin/sh` so any pre-fix sweeper that bypassed realpath
  # would proceed past the `-f`/`-x` checks. Without realpath, the case-glob
  # `scripts/followthroughs/*` matches the traversal path and execution falls
  # through to the existence check; with realpath, the canonical form
  # (`bin/sh`) is rejected BEFORE any disk check.
  echo '#!/usr/bin/env bash' > "$root/bin/sh"
  chmod +x "$root/bin/sh"
  local body
  body=$(cat <<'EOF'
Body text.

<!-- soleur:followthrough script=scripts/followthroughs/../../bin/sh earliest=2020-01-01T00:00:00Z -->
EOF
)
  local combined
  combined=$(invoke_run_one "$root" "$body")
  local rc="${combined##*__RC__=}"
  assert_eq        "T1 run_one returns 2 (path escape)" "2" "$rc"
  assert_contains  "T1 stderr names the escape" \
                   "escapes scripts/followthroughs/" "$combined"
  rm -rf "$root"
}

# --- T2 (Gap 2): first directive wins, multi-directive warning emitted ----
t2_first_directive_wins() {
  local root; root=$(setup_tmpdir)
  # Two real, executable scripts. Pre-fix awk emits BOTH directives' fields;
  # the bash read loop's last-wins assignment would pick second.sh.
  cat > "$root/scripts/followthroughs/first-test.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat > "$root/scripts/followthroughs/second-test.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$root/scripts/followthroughs/first-test.sh" \
           "$root/scripts/followthroughs/second-test.sh"
  local body
  body=$(cat <<'EOF'
<!-- soleur:followthrough script=scripts/followthroughs/first-test.sh earliest=2020-01-01T00:00:00Z -->

Some prose between directives.

<!-- soleur:followthrough script=scripts/followthroughs/second-test.sh earliest=2020-01-01T00:00:00Z -->
EOF
)
  local combined
  combined=$(invoke_run_one "$root" "$body")
  local rc="${combined##*__RC__=}"
  assert_eq        "T2 run_one returns 0 (DRY_RUN happy path)" "0" "$rc"
  assert_contains  "T2 multi-directive warning logged" \
                   "multi-directive body: 2 directives" "$combined"
  assert_contains  "T2 first script is executed" \
                   "running scripts/followthroughs/first-test.sh" "$combined"
  assert_not_contains "T2 second script is NOT executed" \
                   "running scripts/followthroughs/second-test.sh" "$combined"
  rm -rf "$root"
}

# --- T3 (Gap 3): mid-prose directive does not parse -----------------------
t3_anchored_awk_skips_mid_prose() {
  local root; root=$(setup_tmpdir)
  cat > "$root/scripts/followthroughs/embedded.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$root/scripts/followthroughs/embedded.sh"
  local body
  body=$(cat <<'EOF'
This is prose. See the example: <!-- soleur:followthrough script=scripts/followthroughs/embedded.sh earliest=2020-01-01T00:00:00Z --> embedded mid-line.
EOF
)
  local combined
  combined=$(invoke_run_one "$root" "$body")
  local rc="${combined##*__RC__=}"
  assert_eq        "T3 run_one returns 0 (no directive)" "0" "$rc"
  assert_contains  "T3 reports no-directive skip" \
                   "no directive" "$combined"
  assert_not_contains "T3 embedded script is NOT executed" \
                   "running scripts/followthroughs/embedded.sh" "$combined"
  rm -rf "$root"
}

# --- T4 (regression): canonical body parses and runs ----------------------
t4_canonical_body_happy_path() {
  local root; root=$(setup_tmpdir)
  cat > "$root/scripts/followthroughs/ok-test.sh" <<'EOF'
#!/usr/bin/env bash
echo "ok-test ran"
exit 0
EOF
  chmod +x "$root/scripts/followthroughs/ok-test.sh"
  local body
  body=$(cat <<'EOF'
<!-- soleur:followthrough script=scripts/followthroughs/ok-test.sh earliest=2020-01-01T00:00:00Z -->
EOF
)
  local combined
  combined=$(invoke_run_one "$root" "$body")
  local rc="${combined##*__RC__=}"
  assert_eq        "T4 run_one returns 0 (PASS verdict)" "0" "$rc"
  assert_contains  "T4 script is executed" \
                   "running scripts/followthroughs/ok-test.sh" "$combined"
  assert_contains  "T4 DRY_RUN short-circuit names the close action" \
                   "DRY_RUN" "$combined"
  rm -rf "$root"
}

t1_realpath_rejects_traversal
t2_first_directive_wins
t3_anchored_awk_skips_mid_prose
t4_canonical_body_happy_path

echo
echo "PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"
[[ "$FAIL" -eq 0 ]] || exit 1
