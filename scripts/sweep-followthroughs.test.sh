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

# --- T8: secrets=GH_TOKEN forwarding through the env -i sandbox ------------
# Regression guard for the silent-never-close P1 (gh-using follow-through
# probes): the sweeper runs verification scripts under `env -i` (PATH + HOME +
# directive-declared secrets= ONLY). A gh-probe that omits `secrets=GH_TOKEN`
# loses the token in CI and returns transient forever. Proves both directions:
# (a) without secrets= the token is STRIPPED; (b) with secrets=GH_TOKEN it is
# FORWARDED. The probe writes the value it sees to a CWD-relative sidecar
# (CWD = the issue tmpdir, preserved across env -i).
t8_secrets_gh_token_forwarded() {
  local root; root=$(setup_tmpdir)
  cat > "$root/scripts/followthroughs/token-probe.sh" <<'EOF'
#!/usr/bin/env bash
echo "${GH_TOKEN:-ABSENT}" > token-probe.out
exit 0
EOF
  chmod +x "$root/scripts/followthroughs/token-probe.sh"
  export GH_TOKEN="ghs_t8_sentinel_value"

  # (a) NO secrets= → env -i strips GH_TOKEN → probe sees ABSENT.
  rm -f "$root/token-probe.out"
  local body_nosecret
  body_nosecret=$(cat <<'EOF'
<!-- soleur:followthrough script=scripts/followthroughs/token-probe.sh earliest=2020-01-01T00:00:00Z -->
EOF
)
  invoke_run_one "$root" "$body_nosecret" >/dev/null
  assert_eq        "T8a no secrets= → GH_TOKEN stripped by env -i" \
                   "ABSENT" "$(cat "$root/token-probe.out" 2>/dev/null)"

  # (b) secrets=GH_TOKEN → forwarded → probe sees the sentinel value.
  rm -f "$root/token-probe.out"
  local body_secret
  body_secret=$(cat <<'EOF'
<!-- soleur:followthrough script=scripts/followthroughs/token-probe.sh earliest=2020-01-01T00:00:00Z secrets=GH_TOKEN -->
EOF
)
  invoke_run_one "$root" "$body_secret" >/dev/null
  assert_eq        "T8b secrets=GH_TOKEN → forwarded into env -i sandbox" \
                   "ghs_t8_sentinel_value" "$(cat "$root/token-probe.out" 2>/dev/null)"

  unset GH_TOKEN
  rm -rf "$root"
}

# =============================================================================
# T9-T13 (#6698): the CLOSED-set reopen path.
#
# A follow-through can be closed while its condition is still unrecovered — by
# the operator, an agent session, or a `Closes #N` that GitHub's keyword parser
# matched in descriptive PR prose. The sweeper previously listed `--state open`
# only, so such a close was permanently invisible.
# =============================================================================

# A gh stub that serves the queries the closed path makes. Records every
# invocation so tests can assert what was NOT called (no-comment cases).
make_gh_stub() {
  local root="$1" open_json="$2" closed_json="$3" comments_json="$4"
  cat > "$root/bin/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "gh \$*" >> "$root/gh-calls.log"
case "\$*" in
  *"state:closed"*)          printf '%s' '$closed_json' ;;
  *"issue list"*)            printf '%s' '$open_json' ;;
  *"--json comments"*)       printf '%s' '$comments_json' ;;
  *"issue comment"*)         cat >/dev/null ;;
  *"issue reopen"*)          : ;;
  *"issue close"*)           : ;;
  *) printf 'UNSTUBBED gh: %s\n' "\$*" >&2; exit 99 ;;
esac
EOF
  chmod +x "$root/bin/gh"
}

# Run run_one in CLOSED mode (the 3rd arg), for real (DRY_RUN=0) so the
# comment/reopen calls actually reach the stub and become assertable.
invoke_closed() {
  local tmpdir="$1" body="$2" issue_num="${3:-6657}"
  local out_file="$tmpdir/closed-out"
  (
    cd "$tmpdir"
    export PATH="$tmpdir/bin:$PATH"
    export GH_REPO="test/test"
    export DRY_RUN=0
    # The directive declares `secrets=GH_TOKEN`, and the sweeper refuses to run
    # a script whose declared secret is absent. Exported HERE rather than in
    # setup_closed_root: that helper's output is captured via `$(...)`, so its
    # exports die with the command-substitution subshell.
    export GH_TOKEN="stub"
    # shellcheck disable=SC1090
    source "$SUT"
    set +e
    run_one "$issue_num" "$body" closed > "$out_file" 2>&1
    echo "$?" > "$tmpdir/closed-rc"
  )
  cat "$out_file"
}

# The #6657 shape once its soak HAS elapsed: closed COMPLETED, `earliest` in the
# past, probe still exits 1 → the closure was premature and must be reopened.
# #6657 was closed 2026-07-18 with earliest=2026-07-25 and CLOSED_LOOKBACK_DAYS
# is 14, so it stays a candidate until 08-01 and is evaluated from 07-25 with
# the earliest gate intact — the gate never had to be bypassed for this case.
closed_body_6657() {
  cat <<'EOF'
[cert-poll] GitHub Pages cert requires attention

<!-- soleur:followthrough script=scripts/followthroughs/cert-probe.sh earliest=2020-01-01T00:00:00Z secrets=GH_TOKEN -->
EOF
}

# The same issue BEFORE its soak elapses. Probes use exit 1 for "still soaking"
# (see workspaces-luks-soak-6604.sh: `1 = FAIL (still soaking, ...)`), so an
# earliest-bypassing sweeper would read every legitimately-closed-but-soaking
# issue as prematurely closed and reopen it, overriding the operator.
closed_body_still_soaking() {
  cat <<'EOF'
[soak] verification still running

<!-- soleur:followthrough script=scripts/followthroughs/cert-probe.sh earliest=2099-01-01T00:00:00Z secrets=GH_TOKEN -->
EOF
}

setup_closed_root() {
  local exit_code="$1" comments_json="$2"
  local root; root=$(setup_tmpdir)
  cat > "$root/scripts/followthroughs/cert-probe.sh" <<EOF
#!/usr/bin/env bash
exit $exit_code
EOF
  chmod +x "$root/scripts/followthroughs/cert-probe.sh"
  make_gh_stub "$root" '[]' '[]' "$comments_json"
  printf '%s' "$root"
}

# --- T9 (AC14b): #6657's exact shape → reopened despite a future `earliest` --
t9_closed_fail_reopens_bypassing_earliest() {
  local root; root=$(setup_closed_root 1 '{"comments":[]}')
  local out; out=$(invoke_closed "$root" "$(closed_body_6657)")
  local calls; calls=$(cat "$root/gh-calls.log" 2>/dev/null || echo "")
  assert_not_contains "T9 does not skip once earliest has elapsed" \
                      "not yet reached" "$out"
  assert_contains     "T9 reopens the prematurely-closed issue (exit 1)" \
                      "issue reopen 6657" "$calls"
  assert_contains     "T9 comments with the reopen block" \
                      "issue comment 6657" "$calls"
  unset GH_TOKEN; rm -rf "$root"
}

# --- T9b: a still-soaking closed issue must NOT be reopened -------------------
t9b_still_soaking_closure_is_not_reopened() {
  # THE REGRESSION THIS GUARDS: an earlier draft bypassed the earliest gate for
  # the closed set. Because soak probes exit 1 for "still soaking", that would
  # have reopened every legitimately-closed issue whose soak had not elapsed.
  # Measured 2026-07-19: #6604 (earliest=07-25), #6416 (07-22) and #6462 (07-29)
  # were all closed COMPLETED with a future earliest and would have been
  # reopened that night, overriding the operator.
  local root; root=$(setup_closed_root 1 '{"comments":[]}')
  local out; out=$(invoke_closed "$root" "$(closed_body_still_soaking)")
  local calls; calls=$(cat "$root/gh-calls.log" 2>/dev/null || echo "")
  assert_contains     "T9b honors the earliest gate on the closed set" \
                      "not yet reached" "$out"
  assert_not_contains "T9b does NOT reopen a still-soaking closure" \
                      "issue reopen" "$calls"
  assert_not_contains "T9b does not even run the probe before earliest" \
                      "issue comment" "$calls"
  unset GH_TOKEN; rm -rf "$root"
}

# --- T10 (AC14): exit 0 on a closed issue → FULL no-op, comment included -----
t10_closed_pass_is_full_noop() {
  local root; root=$(setup_closed_root 0 '{"comments":[]}')
  local out; out=$(invoke_closed "$root" "$(closed_body_6657)")
  local calls; calls=$(cat "$root/gh-calls.log" 2>/dev/null || echo "")
  assert_contains     "T10 logs the no-action decision" \
                      "no action, no comment" "$out"
  # run_one's OPEN path comments unconditionally before deciding to close;
  # reusing it here would post a fresh comment on every correctly-closed issue
  # every day, forever. The reopen cap bounds reopens, not comments.
  assert_not_contains "T10 posts NO comment on a passing closed issue" \
                      "issue comment" "$calls"
  assert_not_contains "T10 does not reopen a passing closed issue" \
                      "issue reopen" "$calls"
  unset GH_TOKEN; rm -rf "$root"
}

# --- T11 (AC14): TRANSIENT on a closed issue → no action AND no comment -----
t11_closed_transient_is_silent() {
  local root; root=$(setup_closed_root 3 '{"comments":[]}')
  local out; out=$(invoke_closed "$root" "$(closed_body_6657)")
  local calls; calls=$(cat "$root/gh-calls.log" 2>/dev/null || echo "")
  assert_contains     "T11 treats a non-0/1 exit as transient" \
                      "TRANSIENT (exit 3)" "$out"
  assert_not_contains "T11 posts NO comment on a transient closed issue" \
                      "issue comment" "$calls"
  assert_not_contains "T11 does not reopen on a transient exit" \
                      "issue reopen" "$calls"
  unset GH_TOKEN; rm -rf "$root"
}

# --- T12 (AC14): does not re-litigate the sweeper's own PASS closure --------
t12_skips_own_pass_closure() {
  # Evidence-based, not actor-based: still catches a premature close by ANY
  # actor, while not re-verifying a closure the sweeper itself justified. Absent
  # this, one follow-through silently becomes a permanent daily monitor.
  # Two comments, with the PASS NOT last — a positional `.comments[-1]` check
  # would miss it and re-arm daily re-verification on exactly the issues humans
  # have touched.
  local comments='{"comments":[{"body":"### Sweeper run: PASS (2026-07-18T18:00:00Z)\nScript exited 0."},{"body":"triage bot: linked to #1234"}]}'
  local root; root=$(setup_closed_root 1 "$comments")
  local out; out=$(invoke_closed "$root" "$(closed_body_6657)")
  local calls; calls=$(cat "$root/gh-calls.log" 2>/dev/null || echo "")
  assert_contains     "T12 skips a closure whose last comment is the sweeper PASS" \
                      "not re-litigating" "$out"
  assert_not_contains "T12 does not reopen its own PASS closure" \
                      "issue reopen" "$calls"
  unset GH_TOKEN; rm -rf "$root"
}

# --- T13 (AC14): stateless reopen cap bounds the loop ------------------------
t13_reopen_cap_bounds_the_loop() {
  # The script is stateless and runs verification under `env -i`, so an
  # in-process counter cannot survive between sweeps — GitHub's comment history
  # is the state.
  local m='<!-- soleur:sweeper-reopen -->'
  local comments="{\"comments\":[{\"body\":\"r1 $m\"},{\"body\":\"r2 $m\"},{\"body\":\"r3 $m\"}]}"
  local root; root=$(setup_closed_root 1 "$comments")
  local out; out=$(invoke_closed "$root" "$(closed_body_6657)")
  local calls; calls=$(cat "$root/gh-calls.log" 2>/dev/null || echo "")
  assert_contains     "T13 gives up after the reopen cap" \
                      "cap=3" "$out"
  assert_not_contains "T13 does not reopen past the cap" \
                      "issue reopen" "$calls"

  # Non-vacuity: one fewer prior reopen and it DOES act, so the cap is what
  # stopped it rather than some unrelated skip.
  local root2; root2=$(setup_closed_root 1 "{\"comments\":[{\"body\":\"r1 $m\"}]}")
  invoke_closed "$root2" "$(closed_body_6657)" >/dev/null
  local calls2; calls2=$(cat "$root2/gh-calls.log" 2>/dev/null || echo "")
  assert_contains     "T13 still reopens below the cap (non-vacuity)" \
                      "issue reopen" "$calls2"
  unset GH_TOKEN; rm -rf "$root" "$root2"
}

# --- T14 (AC14): a failed reopen emits ::error:: ----------------------------
t14_failed_reopen_emits_error_annotation() {
  local root; root=$(setup_closed_root 1 '{"comments":[]}')
  # Re-stub gh so `issue reopen` fails — the only failure surface for this path.
  cat > "$root/bin/gh" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *"--json comments"*) printf '%s' '{"comments":[]}' ;;
  *"issue comment"*)   cat >/dev/null ;;
  *"issue reopen"*)    exit 1 ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$root/bin/gh"
  local out; out=$(invoke_closed "$root" "$(closed_body_6657)")
  assert_contains     "T14 failed reopen emits a ::error:: annotation" \
                      "::error::sweeper failed to reopen issue #6657" "$out"
  unset GH_TOKEN; rm -rf "$root"
}

# --- T15 (AC14): the OPEN path is unchanged ---------------------------------
t15_open_path_still_honors_earliest() {
  # The closed set must not have widened the open query or relaxed its gate.
  local root; root=$(setup_closed_root 1 '{"comments":[]}')
  local body; body=$(closed_body_still_soaking)
  local combined; combined=$(invoke_run_one "$root" "$body" 6657)
  assert_contains     "T15 open path still skips on a future earliest" \
                      "not yet reached" "$combined"
  assert_contains     "T15 open issue query keeps its own --state open limit" \
                      "--state open --limit 50" "$(cat "$SUT")"
  unset GH_TOKEN; rm -rf "$root"
}

# --- T16: main()'s closed-set loop (V1 — was entirely untested) -------------
# The whole reopen feature lives in main(): the search string, the COMPLETED
# filter, the lookback, CLOSED_LIMIT, and the per-issue dispatch. Every prior
# test drove run_one directly, so main() could have been pointed at a
# nonexistent label, had its wontfix filter deleted, or run a zero-day lookback
# with a fully green suite.
t16_main_closed_set_dispatch() {
  local root; root=$(setup_tmpdir)
  cat > "$root/scripts/followthroughs/cert-probe.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$root/scripts/followthroughs/cert-probe.sh"

  # Three closed issues: COMPLETED (candidate), NOT_PLANNED (wontfix), and a
  # null reason (unknown provenance). Only the first may be evaluated.
  local body='[cert] x\n\n<!-- soleur:followthrough script=scripts/followthroughs/cert-probe.sh earliest=2020-01-01T00:00:00Z secrets=GH_TOKEN -->'
  local closed_json
  closed_json=$(printf '[{"number":6657,"body":"%s","stateReason":"COMPLETED"},{"number":7001,"body":"%s","stateReason":"NOT_PLANNED"},{"number":7002,"body":"%s","stateReason":null}]' "$body" "$body" "$body")
  make_gh_stub "$root" '[]' "$closed_json" '{"comments":[]}'

  local out
  out=$(
    cd "$root"
    export PATH="$root/bin:$PATH" GH_REPO="test/test" DRY_RUN=0 GH_TOKEN="stub"
    # shellcheck disable=SC1090
    source "$SUT"
    main 2>&1
  )
  local calls; calls=$(cat "$root/gh-calls.log" 2>/dev/null || echo "")

  assert_contains     "T16 queries the closed set by label+state+recency" \
                      "label:follow-through state:closed closed:>=" "$calls"
  assert_contains     "T16 honors CLOSED_LIMIT on the closed query" \
                      "--limit 30" "$calls"
  assert_contains     "T16 reopens the COMPLETED candidate" \
                      "issue reopen 6657" "$calls"
  assert_not_contains "T16 leaves the NOT_PLANNED wontfix closed" \
                      "issue reopen 7001" "$calls"
  assert_not_contains "T16 leaves a null-stateReason closure alone" \
                      "issue reopen 7002" "$calls"
  assert_contains     "T16 says why it skipped the wontfix" \
                      "not COMPLETED" "$out"
  unset GH_TOKEN; rm -rf "$root"
}

t1_realpath_rejects_traversal
t2_first_directive_wins
t3_anchored_awk_skips_mid_prose
t4_canonical_body_happy_path
t5_multi_script_token_first_wins
t6_fenced_block_directive_is_skipped
t7_symlink_under_allowlist_rejected
t8_secrets_gh_token_forwarded
t9_closed_fail_reopens_bypassing_earliest
t9b_still_soaking_closure_is_not_reopened
t10_closed_pass_is_full_noop
t11_closed_transient_is_silent
t12_skips_own_pass_closure
t13_reopen_cap_bounds_the_loop
t14_failed_reopen_emits_error_annotation
t15_open_path_still_honors_earliest
t16_main_closed_set_dispatch

echo
echo "PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"
[[ "$FAIL" -eq 0 ]] || exit 1
