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

# Portability: T1's realpath canonicalization assertion requires the
# `--relative-to` flag (uutils 0.8.0 / GNU coreutils ≥8.23). Skip the
# whole suite cleanly on minimal images that lack coreutils, matching
# the convention from `scripts/compound-promote.test.sh`.
command -v realpath >/dev/null 2>&1 || { echo "SKIP: realpath missing"; exit 0; }

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

# Invoke run_one from within $tmpdir with the given body. Splits stdout
# and stderr to per-stream sidecar files so T1 can assert "escape message
# went to stderr" (where humans grep) rather than just "appears somewhere
# in combined output." Returns combined + __RC__= packed string for
# tests that only care about the combined view.
#
# GH_REPO=test/test is load-bearing: the sweeper's top-level (line 23)
# runs `gh repo view --json nameWithOwner` IF GH_REPO is unset. Setting
# it short-circuits the subshell at source time, so the gh-stub on PATH
# (which exits 99 on any real invocation) is only the safety net.
invoke_run_one() {
  local tmpdir="$1" body="$2" issue_num="${3:-9999}"
  local rc_file="$tmpdir/run-one-rc"
  local stdout_file="$tmpdir/run-one-stdout"
  local stderr_file="$tmpdir/run-one-stderr"
  # Subshell so the sourced sweeper's top-level side effects (set -euo
  # pipefail, REPO=, now_epoch=) do not leak back into the test harness.
  (
    cd "$tmpdir"
    export PATH="$tmpdir/bin:$PATH"
    export GH_REPO="test/test"
    export DRY_RUN=1
    # shellcheck disable=SC1090
    source "$SUT"
    set +e
    run_one "$issue_num" "$body" > "$stdout_file" 2> "$stderr_file"
    echo "$?" > "$rc_file"
  )
  local rc
  rc=$(cat "$rc_file")
  local combined
  combined=$(cat "$stdout_file" "$stderr_file")
  printf '%s\n__RC__=%s\n' "$combined" "$rc"
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
  # The error message MUST land on stderr — humans grep stderr for failures
  # and the GHA workflow run summary surfaces stderr separately. A regression
  # that prints to stdout still satisfies a combined-stream assert but loses
  # the operator-facing failure signal.
  local stderr_only
  stderr_only=$(cat "$root/run-one-stderr")
  assert_contains  "T1 escape message lands on stderr (not stdout)" \
                   "escapes scripts/followthroughs/" "$stderr_only"
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
  # Match the full DRY_RUN log line — substring `DRY_RUN` alone would pass
  # on an incidental mention elsewhere (e.g., a stub printing the env).
  assert_contains  "T4 DRY_RUN short-circuit names the close action with PASS verdict" \
                   "DRY_RUN — would close with verdict=PASS" "$combined"
  rm -rf "$root"
}

# --- T5 (Gap 2 extension): multiple script= tokens in ONE directive ------
# The bash read loop's `[[ -z "$script" ]]` first-wins guard MUST hold even
# when a single directive line contains multiple `script=` tokens. Without
# the guard, the awk for-loop emits one `script ...` line per matching
# token and the bash loop's plain `script="$val"` assignment is last-wins,
# bypassing the Gap-2 first-directive-wins intent within a single directive.
t5_multi_script_token_first_wins() {
  local root; root=$(setup_tmpdir)
  cat > "$root/scripts/followthroughs/first-tok.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat > "$root/scripts/followthroughs/second-tok.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$root/scripts/followthroughs/first-tok.sh" \
           "$root/scripts/followthroughs/second-tok.sh"
  local body
  body=$(cat <<'EOF'
<!-- soleur:followthrough script=scripts/followthroughs/first-tok.sh script=scripts/followthroughs/second-tok.sh earliest=2020-01-01T00:00:00Z -->
EOF
)
  local combined
  combined=$(invoke_run_one "$root" "$body")
  local rc="${combined##*__RC__=}"
  assert_eq        "T5 run_one returns 0 (DRY_RUN happy path)" "0" "$rc"
  assert_contains  "T5 first script token is executed" \
                   "running scripts/followthroughs/first-tok.sh" "$combined"
  assert_not_contains "T5 second script token is NOT executed" \
                   "running scripts/followthroughs/second-tok.sh" "$combined"
  rm -rf "$root"
}

# --- T6 (Gap 3 extension): directive inside a fenced markdown block ------
# The anchored start-range regex `/^<!-- *soleur:followthrough/` still
# matches a directive at column 1 inside a ```html``` fenced code block.
# The awk fence-flag closes this residual — a directive inside any code
# fence (three-backtick start, regardless of language tag) is skipped
# wholesale.
t6_fenced_block_directive_is_skipped() {
  local root; root=$(setup_tmpdir)
  cat > "$root/scripts/followthroughs/fenced.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$root/scripts/followthroughs/fenced.sh"
  local body
  body=$(cat <<'EOF'
Example directive shape (for reference, not for the sweeper to honor):

```html
<!-- soleur:followthrough script=scripts/followthroughs/fenced.sh earliest=2020-01-01T00:00:00Z -->
```

End of example.
EOF
)
  local combined
  combined=$(invoke_run_one "$root" "$body")
  local rc="${combined##*__RC__=}"
  assert_eq        "T6 run_one returns 0 (no directive)" "0" "$rc"
  assert_contains  "T6 reports no-directive skip" \
                   "no directive" "$combined"
  assert_not_contains "T6 fenced script is NOT executed" \
                   "running scripts/followthroughs/fenced.sh" "$combined"
  rm -rf "$root"
}

# --- T7 (Gap 1 extension): symlinks under the allowlist are rejected -----
# `realpath -m` follows symlinks, so an attacker-committed symlink under
# scripts/followthroughs/ pointing at a privileged script elsewhere in the
# repo (terraform-apply wrapper, admin-ip refresh, etc.) would have its
# existence/executability checks pass while the sweeper's mental model
# scopes "is this safe to run from the sweeper" to the allowlist root.
# The pre-realpath symlink check refuses every symlink under the root.
t7_symlink_under_allowlist_rejected() {
  local root; root=$(setup_tmpdir)
  cat > "$root/scripts/followthroughs/real-target.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$root/scripts/followthroughs/real-target.sh"
  ln -s real-target.sh "$root/scripts/followthroughs/symlink.sh"
  local body
  body=$(cat <<'EOF'
<!-- soleur:followthrough script=scripts/followthroughs/symlink.sh earliest=2020-01-01T00:00:00Z -->
EOF
)
  local combined
  combined=$(invoke_run_one "$root" "$body")
  local rc="${combined##*__RC__=}"
  assert_eq        "T7 run_one returns 2 (symlink reject)" "2" "$rc"
  local stderr_only
  stderr_only=$(cat "$root/run-one-stderr")
  assert_contains  "T7 stderr names the symlink rejection" \
                   "is a symlink" "$stderr_only"
  assert_not_contains "T7 real-target is NOT executed" \
                   "running scripts/followthroughs/real-target.sh" "$combined"
  rm -rf "$root"
}

t1_realpath_rejects_traversal
t2_first_directive_wins
t3_anchored_awk_skips_mid_prose
t4_canonical_body_happy_path
t5_multi_script_token_first_wins
t6_fenced_block_directive_is_skipped
t7_symlink_under_allowlist_rejected

echo
echo "PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"
[[ "$FAIL" -eq 0 ]] || exit 1
