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

# ADR-193 shape: pass()/fail() are the TERMINAL verdict helpers and move ONLY the verdict
# counters; the assert_* wrappers move TOTAL (the case counter) at the call site. Stubbing
# a verdict helper therefore drops the verdict WITHOUT dropping its count, and the
# conservation identity at the bottom catches it.
pass() { PASS=$((PASS + 1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$expected" == "$actual" ]]; then
    pass "$name"
  else
    fail "$name"
    echo "  expected: $expected"
    echo "  actual:   $actual"
  fi
}

assert_contains() {
  local name="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name"
    echo "  needle:   $needle"
    echo "  haystack: ${haystack:0:600}"
  fi
}

assert_not_contains() {
  local name="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$haystack" != *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name"
    echo "  forbidden needle: $needle"
    echo "  haystack: ${haystack:0:600}"
  fi
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
# The JSON responses live in FILES the stub cats (a case may rewrite $root/open.json after the
# stub exists), and every `issue comment N` body is captured to $root/comment-N so per-tracker
# assertions are real. One stub for every case, including the Guard 3 rows below.
make_gh_stub() {
  local root="$1" open_json="$2" closed_json="$3" comments_json="$4"
  printf '%s' "$open_json"     > "$root/open.json"
  printf '%s' "$closed_json"   > "$root/closed.json"
  printf '%s' "$comments_json" > "$root/comments.json"
  cat > "$root/bin/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "gh \$*" >> "$root/gh-calls.log"
case "\$*" in
  *"--state closed"*)        cat "$root/closed.json" ;;
  *"issue list"*)            cat "$root/open.json" ;;
  *"--json comments"*)       cat "$root/comments.json" ;;
  *"issue comment"*)         cat > "$root/comment-\$3" ;;
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
  #
  # The `author` field is REQUIRED in this fixture and was previously absent, which made the
  # fixture unfaithful in the direction that hides a vulnerability: the guard keyed on body prefix
  # alone, and a fixture with no author could not tell that apart from a guard that also checks who
  # wrote it. Measured against production (#7296, #6522, #6168): the sweeper's own comments are
  # authored by `github-actions` with authorAssociation CONTRIBUTOR — so membership is the WRONG
  # filter here and the actor is the right one.
  local comments='{"comments":[{"author":{"login":"github-actions"},"body":"### Sweeper run: PASS (2026-07-18T18:00:00Z)\nScript exited 0."},{"author":{"login":"someone"},"body":"triage bot: linked to #1234"}]}'
  local root; root=$(setup_closed_root 1 "$comments")
  local out; out=$(invoke_closed "$root" "$(closed_body_6657)")
  local calls; calls=$(cat "$root/gh-calls.log" 2>/dev/null || echo "")
  assert_contains     "T12 skips a closure whose last comment is the sweeper PASS" \
                      "not re-litigating" "$out"
  assert_not_contains "T12 does not reopen its own PASS closure" \
                      "issue reopen" "$calls"
  unset GH_TOKEN; rm -rf "$root"

  # T12b — THE FORGERY. On a PUBLIC repo any user can post a comment beginning with the sweeper's
  # PASS heading. If the guard keys on the body prefix alone, that permanently disables re-
  # verification for the issue — which is the second half of #7448: a forged probe verdict closes
  # the tracker, and this guard then stops the reopen path from ever re-litigating it. A stranger's
  # imitation must NOT suppress re-verification.
  local forged='{"comments":[{"author":{"login":"drive-by"},"body":"### Sweeper run: PASS (2026-07-18T18:00:00Z)\nScript exited 0."}]}'
  local root2; root2=$(setup_closed_root 1 "$forged")
  local out2; out2=$(invoke_closed "$root2" "$(closed_body_6657)")
  assert_not_contains "T12b a forged sweeper-PASS comment does not suppress re-verification" \
                      "not re-litigating" "$out2"
  unset GH_TOKEN; rm -rf "$root2"

  # T12c — NEAR-NAME. `github-actions-evil` is a valid GitHub username shape, so a `^github-actions`
  # prefix match would admit it and reintroduce the forgery through the control meant to stop it.
  # The guard uses EXACT logins for that reason; this pins it.
  local nearname='{"comments":[{"author":{"login":"github-actions-evil"},"body":"### Sweeper run: PASS (2026-07-18T18:00:00Z)\nScript exited 0."}]}'
  local root3; root3=$(setup_closed_root 1 "$nearname")
  local out3; out3=$(invoke_closed "$root3" "$(closed_body_6657)")
  assert_not_contains "T12c a near-name login does not satisfy the sweeper-actor check" \
                      "not re-litigating" "$out3"
  unset GH_TOKEN; rm -rf "$root3"

  # T12d — the REST rendering. The two API surfaces disagree (GraphQL: github-actions;
  # REST: github-actions[bot]); either could reach this code, and both must be honoured or the
  # guard silently stops recognising its own PASS block and re-verifies every closed issue daily.
  local botform='{"comments":[{"author":{"login":"github-actions[bot]"},"body":"### Sweeper run: PASS (2026-07-18T18:00:00Z)\nScript exited 0."}]}'
  local root4; root4=$(setup_closed_root 1 "$botform")
  local out4; out4=$(invoke_closed "$root4" "$(closed_body_6657)")
  assert_contains "T12d the REST [bot] rendering is recognised as the sweeper" \
                  "not re-litigating" "$out4"
  unset GH_TOKEN; rm -rf "$root4"
}

# --- T13 (AC14): stateless reopen cap bounds the loop ------------------------
t13_reopen_cap_bounds_the_loop() {
  # The script is stateless and runs verification under `env -i`, so an
  # in-process counter cannot survive between sweeps — GitHub's comment history
  # is the state.
  #
  # The `author` field is REQUIRED here, and its absence was the same unfaithfulness that hid the
  # hole in T12. The reopen marker is an INVISIBLE HTML comment, so without an actor gate any user
  # posts three innocuous-looking comments secretly carrying it and the sweeper permanently stops
  # reopening that issue. A fixture with no author cannot tell a marker-only cap apart from one
  # that also checks who wrote it. Real reopen comments come from the workflow (see T12).
  local m='<!-- soleur:sweeper-reopen -->'
  local ga='{"login":"github-actions"}'
  local comments="{\"comments\":[{\"author\":$ga,\"body\":\"r1 $m\"},{\"author\":$ga,\"body\":\"r2 $m\"},{\"author\":$ga,\"body\":\"r3 $m\"}]}"
  local root; root=$(setup_closed_root 1 "$comments")
  local out; out=$(invoke_closed "$root" "$(closed_body_6657)")
  local calls; calls=$(cat "$root/gh-calls.log" 2>/dev/null || echo "")
  assert_contains     "T13 gives up after the reopen cap" \
                      "cap=3" "$out"
  assert_not_contains "T13 does not reopen past the cap" \
                      "issue reopen" "$calls"

  # Non-vacuity: one fewer prior reopen and it DOES act, so the cap is what
  # stopped it rather than some unrelated skip.
  local root2; root2=$(setup_closed_root 1 "{\"comments\":[{\"author\":$ga,\"body\":\"r1 $m\"}]}")
  invoke_closed "$root2" "$(closed_body_6657)" >/dev/null
  local calls2; calls2=$(cat "$root2/gh-calls.log" 2>/dev/null || echo "")
  assert_contains     "T13 still reopens below the cap (non-vacuity)" \
                      "issue reopen" "$calls2"

  # T13b — FORGED CAP. Three marker-carrying comments from a NON-sweeper author must not consume
  # the reopen budget. Otherwise any GitHub user silently disables reopening for any of the ~50
  # open follow-through issues — the same end as a forged verdict, by a quieter route.
  local rando='{"login":"drive-by"}'
  local root3; root3=$(setup_closed_root 1 "{\"comments\":[{\"author\":$rando,\"body\":\"r1 $m\"},{\"author\":$rando,\"body\":\"r2 $m\"},{\"author\":$rando,\"body\":\"r3 $m\"}]}")
  local out3; out3=$(invoke_closed "$root3" "$(closed_body_6657)")
  assert_not_contains "T13b a forged reopen marker does not consume the reopen cap" \
                      "cap=3" "$out3"
  unset GH_TOKEN; rm -rf "$root" "$root2" "$root3"
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
                      '--state open --limit "$OPEN_LIMIT"' "$(cat "$SUT")"
  # The VALUE moved from 50 to 200 because 50 was below the live open set (51
  # measured 2026-09-07) and `gh issue list` returns newest-first, so the oldest
  # tracker was silently never swept -- an absence of comments, which reads
  # exactly like a healthy quiet probe.
  assert_contains     "T15 the open limit is bound to a named constant, not a bare literal" \
                      "OPEN_LIMIT=200" "$(cat "$SUT")"
  # Raising the number without a detector just moves the silent failure, so the
  # detector is pinned too: a full page must say so out loud.
  assert_contains     "T15 a full page of open trackers is reported, not silently truncated" \
                      'count" -ge "$OPEN_LIMIT' "$(cat "$SUT")"
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
                      "--state closed --search label:follow-through closed:>=" "$calls"
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

# --- T17 (#7797): shell-trace lines must never reach a public issue comment ---
# The probe's combined output is posted verbatim into a GitHub issue comment,
# and issue-comment bodies do NOT pass through the Actions runner's secret
# masker -- that masking covers job LOG output and only for `secrets.*` values,
# The probe secrets DO come from `secrets.*`; masking is applied to the log
# stream, not to an API payload, so a registered value still lands unmasked in a
# comment. So a traced probe
# would publish its own credential.
#
# RUNS WITH DRY_RUN=0 AND A CAPTURING STUB, DELIBERATELY. The first draft of
# this case asserted on run_one's stdout under DRY_RUN, where `body_msg` is
# never emitted -- so it passed with the scrub fully DISABLED. That is the
# vacuity this whole PR is about, reproduced inside its own test. The body is
# only observable where it is actually sent, so the stub captures stdin.
t17_trace_lines_are_scrubbed_before_comment() {
  local root; root=$(setup_tmpdir)
  cat > "$root/scripts/followthroughs/traced-test.sh" <<'EOF'
#!/usr/bin/env bash
printf '+ TOK=NOTAREALTOKEN_T17\n'
printf '++ printf %%s NOTAREALTOKEN_T17\n'
printf '+++ curl -H Bearer NOTAREALTOKEN_T17\n'
printf 'genuine probe output line\n'
exit 1
EOF
  chmod +x "$root/scripts/followthroughs/traced-test.sh"

  # Capture the comment body instead of discarding it.
  cat > "$root/bin/gh" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *"issue comment"*) cat > "$root/comment-body" ;;
  *) : ;;
esac
EOF
  chmod +x "$root/bin/gh"

  local body
  body=$(cat <<'EOF'
<!-- soleur:followthrough script=scripts/followthroughs/traced-test.sh earliest=2020-01-01T00:00:00Z -->
EOF
)
  (
    cd "$root"
    export PATH="$root/bin:$PATH" GH_REPO="test/test" DRY_RUN=0
    # shellcheck disable=SC1090
    source "$SUT"
    set +e
    run_one 9999 "$body" >/dev/null 2>&1
  )

  local posted=""
  [[ -f "$root/comment-body" ]] && posted=$(cat "$root/comment-body")

  # Precondition: if nothing was captured, every assertion below is vacuous.
  assert_eq "T17 captured a comment body (precondition -- without it the rows below are vacuous)" \
            "captured" "$([[ -n "$posted" ]] && echo captured || echo empty)"
  if [[ -n "$posted" ]]; then
    assert_not_contains "T17 traced probe output is scrubbed before it reaches a public comment" \
                        "NOTAREALTOKEN_T17" "$posted"
    assert_contains     "T17 genuine (non-trace) probe output survives the scrub" \
                        "genuine probe output line" "$posted"
  fi
  rm -rf "$root"
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
t17_trace_lines_are_scrubbed_before_comment

# =============================================================================
# Guard 3 (#7946): a directive naming a secret the env does not carry -- absent, SET BUT
# EMPTY (what `${{ secrets.X }}` resolves to when the repo secret is gone), or not a valid
# identifier -- is reported ON THE TRACKER and reds the run; no name is ever expanded before
# it is validated. Before this guard the branch was `fail … ; return 0`: stderr only, green.
#
# EVERY CASE RUNS `bash "$SUT"` END TO END -- never `source "$SUT"; main` -- because the
# red-run verdict (MISSING_SECRET beside TRUNCATED_SWEEP) is raised in the
# `BASH_SOURCE == $0` block AFTER main returns, which a sourced main can never observe.
# =============================================================================

# g3_root <open_json> [closed_json] -> root with the p.sh probe and the shared gh stub.
g3_root() {
  local open_json="$1" closed_json="${2:-[]}" root; root=$(setup_tmpdir)
  cat > "$root/scripts/followthroughs/p.sh" <<'EOF'
#!/usr/bin/env bash
printf 'FOO_TOKEN=%s\n' "${FOO_TOKEN:-<unset>}"
exit 0
EOF
  chmod +x "$root/scripts/followthroughs/p.sh"
  make_gh_stub "$root" "$open_json" "$closed_json" '{"comments":[]}'
  printf '%s' "$root"
}

# g3_run <root> <sut> [NAME=value ...] -> writes $root/{out,err,rc}. `env -i` so no ambient
# credential can satisfy a directive by accident; only the names given here exist.
g3_run() {
  local root="$1" sut="$2"; shift 2
  # `|| rc=$?` because the suite runs under `set -e` and the SUT's expected NON-ZERO exit is
  # the very thing under test -- a bare `bash "$sut"; echo $?` would abort the subshell
  # before the rc file is written, and every row after it would silently never run.
  (
    cd "$root" || exit 97
    local rc=0
    env -i PATH="$root/bin:$PATH" HOME="$HOME" GH_REPO="test/test" DRY_RUN="${G3_DRY_RUN:-0}" "$@" \
      bash "$sut" > "$root/out" 2> "$root/err" || rc=$?
    echo "$rc" > "$root/rc"
  )
}

g3_body() { # g3_body <secrets-clause-or-empty> -> a one-issue open list JSON
  local clause="$1"
  local directive="<!-- soleur:followthrough script=scripts/followthroughs/p.sh earliest=2020-01-01T00:00:00Z"
  [[ -n "$clause" ]] && directive="$directive secrets=$clause"
  directive="$directive -->"
  printf '[{"number":9001,"body":"%s"}]' "$directive"
}

# --- G3-M1: the directive names SENTRY_AUTH_TOKEN; the env carries only SENTRY_ACTIONS_RO_TOKEN ---
t_g3_m1_missing_secret_is_loud() {
  local root; root=$(g3_root "$(g3_body SENTRY_AUTH_TOKEN)")
  g3_run "$root" "$SUT" SENTRY_ACTIONS_RO_TOKEN=x
  local rc; rc=$(cat "$root/rc"); local posted=""; [[ -f "$root/comment-9001" ]] && posted=$(cat "$root/comment-9001")
  assert_eq       "G3-M1 a missing secret reds the run (rc != 0)" "1" "$([[ "$rc" != "0" ]] && echo 1 || echo 0)"
  assert_contains "G3-M1 a comment is posted ON THE TRACKER naming the secret" "SENTRY_AUTH_TOKEN" "$posted"
  assert_contains "G3-M1 the comment names the fix" "Fix: add the name to the" "$posted"
  assert_contains "G3-M1 the comment carries the run heading" "### Sweeper run: REQUIRED SECRET MISSING" "$posted"
  assert_contains "G3-M1 the per-tracker ::error:: annotation is emitted" "::error::sweep-followthroughs: issue #9001: required secret" "$(cat "$root/err")"
  assert_contains "G3-M1 the run-level ::error:: names the cause" "FAILING THE RUN because at least one tracker" "$(cat "$root/err")"
  assert_not_contains "G3-M1 the probe was NOT run with the secret missing" "running scripts/followthroughs/p.sh" "$(cat "$root/out")"
  rm -rf "$root"
}

# --- G3-M2: a SECOND tracker with a missing secret after a compliant first -> both commented ---
t_g3_m2_second_tracker_after_compliant() {
  local open_json
  open_json='[{"number":9000,"body":"<!-- soleur:followthrough script=scripts/followthroughs/p.sh earliest=2020-01-01T00:00:00Z secrets=FOO_TOKEN -->"},{"number":9001,"body":"<!-- soleur:followthrough script=scripts/followthroughs/p.sh earliest=2020-01-01T00:00:00Z secrets=SENTRY_AUTH_TOKEN -->"},{"number":9002,"body":"<!-- soleur:followthrough script=scripts/followthroughs/p.sh earliest=2020-01-01T00:00:00Z secrets=OTHER_TOKEN -->"}]'
  local root; root=$(g3_root "$open_json")
  g3_run "$root" "$SUT" FOO_TOKEN=forwarded
  local rc; rc=$(cat "$root/rc")
  assert_eq       "G3-M2 two missing secrets -> one non-zero exit" "1" "$([[ "$rc" != "0" ]] && echo 1 || echo 0)"
  assert_contains "G3-M2 tracker 9001 commented" "SENTRY_AUTH_TOKEN" "$(cat "$root/comment-9001" 2>/dev/null)"
  assert_contains "G3-M2 tracker 9002 commented (the walk does not stop at the first)" "OTHER_TOKEN" "$(cat "$root/comment-9002" 2>/dev/null)"
  assert_not_contains "G3-M2 the compliant tracker's verdict comment is not a missing-secret comment" "required secret" "$(cat "$root/comment-9000" 2>/dev/null)"
  assert_contains "G3-M2 the compliant tracker still got its verdict" "### Sweeper run: PASS" "$(cat "$root/comment-9000" 2>/dev/null)"
  rm -rf "$root"
}

# --- G3-M3: DISPATCH row. A sed copy of the SUT with the `MISSING_SECRET=1` assignment deleted
# lets M1 through (rc 0); the diff proves the mutation landed. The FLAG is the mechanism. ---
t_g3_m3_flag_is_the_mechanism() {
  local root; root=$(g3_root "$(g3_body SENTRY_AUTH_TOKEN)")
  local mut="$root/sut-no-flag.sh"
  sed '/^[[:space:]]*MISSING_SECRET=1[[:space:]]*$/d' "$SUT" > "$mut"
  assert_eq "G3-M3 the mutation landed (a MISSING_SECRET=1 line existed to delete)" \
            "landed" "$(diff -q "$SUT" "$mut" >/dev/null 2>&1 && echo not-landed || echo landed)"
  if ! diff -q "$SUT" "$mut" >/dev/null 2>&1; then
    g3_run "$root" "$mut" SENTRY_ACTIONS_RO_TOKEN=x
    assert_eq "G3-M3 with the flag assignment deleted, the M1 input exits 0 (flag is the mechanism)" "0" "$(cat "$root/rc")"
  fi
  rm -rf "$root"
}

# --- G3-M4: DRY_RUN=1 -> no comment posted, the would-comment and the ::error:: both logged, still rc != 0 ---
t_g3_m4_dry_run_is_still_red() {
  local root; root=$(g3_root "$(g3_body SENTRY_AUTH_TOKEN)")
  G3_DRY_RUN=1 g3_run "$root" "$SUT" SENTRY_ACTIONS_RO_TOKEN=x
  local rc; rc=$(cat "$root/rc")
  assert_eq       "G3-M4 DRY_RUN=1 still reds the run" "1" "$([[ "$rc" != "0" ]] && echo 1 || echo 0)"
  assert_eq       "G3-M4 DRY_RUN=1 posts NO comment" "absent" "$([[ -f "$root/comment-9001" ]] && echo present || echo absent)"
  assert_contains "G3-M4 DRY_RUN=1 logs the would-comment" "DRY_RUN" "$(cat "$root/out")"
  assert_contains "G3-M4 DRY_RUN=1 still emits the per-tracker ::error::" "::error::sweep-followthroughs: issue #9001: required secret" "$(cat "$root/err")"
  rm -rf "$root"
}

# --- G3-M5: a malformed name is refused BEFORE any expansion. `${!name+x}` on
# `a[$(cmd)]` evaluates the subscript, running cmd inside the sweeper job with every forwarded
# secret in its env. The sentinel must stay absent; the comment quotes the token. ---
t_g3_m5_malformed_name_never_expands() {
  local root; root=$(g3_root '[]')
  # ${IFS} stands in for the space the awk field split would otherwise eat.
  local payload="a[\$(touch\${IFS}$root/pwned)]"
  printf '[{"number":9001,"body":"<!-- soleur:followthrough script=scripts/followthroughs/p.sh earliest=2020-01-01T00:00:00Z secrets=%s -->"}]' "$payload" > "$root/open.json"
  g3_run "$root" "$SUT" SENTRY_ACTIONS_RO_TOKEN=x
  local rc; rc=$(cat "$root/rc"); local posted=""; [[ -f "$root/comment-9001" ]] && posted=$(cat "$root/comment-9001")
  assert_eq       "G3-M5 the malformed name's payload did NOT execute (sentinel absent)" "absent" "$([[ -e "$root/pwned" ]] && echo present || echo absent)"
  assert_eq       "G3-M5 a malformed name reds the run" "1" "$([[ "$rc" != "0" ]] && echo 1 || echo 0)"
  # The token is author-controlled bytes: it reaches the comment SANITIZED (every byte outside
  # [A-Za-z0-9_.-] becomes `?`), never verbatim -- verbatim would let a crafted token close the
  # backtick span or open a `<!-- soleur:followthrough` directive inside the sweeper's own comment.
  assert_contains     "G3-M5 the comment quotes the token in sanitized form" "a???touch??IFS?" "$posted"
  assert_not_contains "G3-M5 the comment never carries the raw \$( from the token" "\$(" "$posted"
  assert_contains "G3-M5 the comment says it is malformed" "malformed" "$posted"
  rm -rf "$root"
}

# --- G3-M6: the name is present in the env but EMPTY -> reported as bound but empty ---
t_g3_m6_bound_but_empty() {
  local root; root=$(g3_root "$(g3_body SENTRY_AUTH_TOKEN)")
  g3_run "$root" "$SUT" SENTRY_AUTH_TOKEN=
  local rc; rc=$(cat "$root/rc"); local posted=""; [[ -f "$root/comment-9001" ]] && posted=$(cat "$root/comment-9001")
  assert_eq       "G3-M6 a set-but-empty secret reds the run" "1" "$([[ "$rc" != "0" ]] && echo 1 || echo 0)"
  assert_contains "G3-M6 the comment says bound but empty" "bound but empty" "$posted"
  assert_not_contains "G3-M6 the probe was NOT run with an empty secret" "running scripts/followthroughs/p.sh" "$(cat "$root/out")"
  rm -rf "$root"
}

# --- G3-M7: a RESERVED name is refused even though it is set and non-empty. `PATH` is bound in
# every environment, so without the denylist `secrets=PATH` would forward the runner's PATH into
# the env -i sandbox and defeat the pin. ---
t_g3_m7_reserved_name_refused() {
  local root; root=$(g3_root "$(g3_body PATH)")
  g3_run "$root" "$SUT" SENTRY_ACTIONS_RO_TOKEN=x
  local rc; rc=$(cat "$root/rc"); local posted=""; [[ -f "$root/comment-9001" ]] && posted=$(cat "$root/comment-9001")
  assert_eq       "G3-M7 a reserved name reds the run" "1" "$([[ "$rc" != "0" ]] && echo 1 || echo 0)"
  assert_contains "G3-M7 the comment says the name is reserved" "reserved name" "$posted"
  assert_not_contains "G3-M7 the probe was NOT run" "running scripts/followthroughs/p.sh" "$(cat "$root/out")"
  rm -rf "$root"
}

# --- G3-M8: BOTH names in one clause missing -> one comment listing both; the count in the
# annotation is 2 (the walk over the clause does not stop at the first miss) ---
t_g3_m8_both_names_missing_listed() {
  local root; root=$(g3_root "$(g3_body SENTRY_AUTH_TOKEN,OTHER_TOKEN)")
  g3_run "$root" "$SUT" SENTRY_ACTIONS_RO_TOKEN=x
  local rc; rc=$(cat "$root/rc"); local posted=""; [[ -f "$root/comment-9001" ]] && posted=$(cat "$root/comment-9001")
  assert_eq       "G3-M8 two missing names in one clause red the run" "1" "$([[ "$rc" != "0" ]] && echo 1 || echo 0)"
  assert_contains "G3-M8 the comment lists the first name" "\`SENTRY_AUTH_TOKEN\` — not set" "$posted"
  assert_contains "G3-M8 the comment lists the second name" "\`OTHER_TOKEN\` — not set" "$posted"
  assert_contains "G3-M8 the annotation counts both" "(2 name(s); see the comment on the tracker)" "$(cat "$root/err")"
  assert_eq       "G3-M8 exactly one comment on the tracker" "1" "$(grep -c 'issue comment 9001' "$root/gh-calls.log")"
  rm -rf "$root"
}

# --- G3-M9: the CLOSED path. A tracker closed within the lookback whose directive names a
# retired credential is commented on (the guard sits before the verdict split), and is NOT
# reopened -- a missing binding is not evidence the closure was premature. ---
t_g3_m9_closed_tracker_commented_not_reopened() {
  local closed_json
  closed_json='[{"number":9002,"body":"<!-- soleur:followthrough script=scripts/followthroughs/p.sh earliest=2020-01-01T00:00:00Z secrets=SENTRY_AUTH_TOKEN -->","stateReason":"COMPLETED"}]'
  local root; root=$(g3_root '[]' "$closed_json")
  g3_run "$root" "$SUT" SENTRY_ACTIONS_RO_TOKEN=x
  local rc; rc=$(cat "$root/rc"); local posted=""; [[ -f "$root/comment-9002" ]] && posted=$(cat "$root/comment-9002")
  assert_eq       "G3-M9 a closed tracker naming a missing secret reds the run" "1" "$([[ "$rc" != "0" ]] && echo 1 || echo 0)"
  assert_contains "G3-M9 the closed tracker is commented on" "### Sweeper run: REQUIRED SECRET MISSING" "$posted"
  assert_not_contains "G3-M9 the closed tracker is NOT reopened" "issue reopen 9002" "$(cat "$root/gh-calls.log")"
  rm -rf "$root"
}

# --- G3-H4: must-PASS: a CRLF body (web-editor paste) with the secrets clause ending a line.
# Without the `\r` strip in parse_directive every line-final token keeps its CR: measured on a
# strip-less copy, `script=…/p.sh\r` fails the on-disk check and the tracker is skipped under a
# GREEN run with no comment -- so the discriminating assertion is the forwarded-secret line in
# the posted comment, not the exit code. ---
t_g3_h4_crlf_body_tolerated() {
  local root; root=$(g3_root '[]')
  # `\\r\\n` (doubled) so printf emits the JSON escape and jq decodes it to a real CR LF in the body.
  printf '[{"number":9001,"body":"<!-- soleur:followthrough script=scripts/followthroughs/p.sh\\r\\nearliest=2020-01-01T00:00:00Z secrets=FOO_TOKEN\\r\\n-->\\r\\n"}]' > "$root/open.json"
  g3_run "$root" "$SUT" FOO_TOKEN=crlf-7946
  local posted=""; [[ -f "$root/comment-9001" ]] && posted=$(cat "$root/comment-9001")
  assert_eq       "G3-H4 a CRLF directive with a correct clause -> exit 0" "0" "$(cat "$root/rc")"
  assert_contains "G3-H4 the secret was forwarded" "FOO_TOKEN=crlf-7946" "$posted"
  assert_not_contains "G3-H4 no missing-secret comment" "REQUIRED SECRET MISSING" "$posted"
  rm -rf "$root"
}

# --- G3-H2: must-PASS, not the canonical: two names both set AND non-empty, one not GH_TOKEN ---
t_g3_h2_two_names_forwarded() {
  local root; root=$(g3_root "$(g3_body GH_TOKEN,FOO_TOKEN)")
  g3_run "$root" "$SUT" GH_TOKEN=stub FOO_TOKEN=forwarded-7946
  local posted=""; [[ -f "$root/comment-9001" ]] && posted=$(cat "$root/comment-9001")
  assert_eq       "G3-H2 both names present and non-empty -> exit 0" "0" "$(cat "$root/rc")"
  assert_contains "G3-H2 the second name was forwarded into the env -i sandbox" "FOO_TOKEN=forwarded-7946" "$posted"
  assert_not_contains "G3-H2 no missing-secret comment on this path" "required secret" "$posted"
  assert_not_contains "G3-H2 no ::error:: on this path" "::error::" "$(cat "$root/err")"
  rm -rf "$root"
}

# --- G3-H3: must-PASS: a directive with no `secrets=` clause at all -> path not entered ---
t_g3_h3_no_secrets_clause() {
  local root; root=$(g3_root "$(g3_body "")")
  g3_run "$root" "$SUT"
  local posted=""; [[ -f "$root/comment-9001" ]] && posted=$(cat "$root/comment-9001")
  assert_eq       "G3-H3 no secrets= clause -> exit 0" "0" "$(cat "$root/rc")"
  assert_contains "G3-H3 the probe ran (FOO_TOKEN unset inside the sandbox)" "FOO_TOKEN=<unset>" "$posted"
  assert_not_contains "G3-H3 no missing-secret comment" "required secret" "$posted"
  rm -rf "$root"
}

t_g3_m1_missing_secret_is_loud
t_g3_m2_second_tracker_after_compliant
t_g3_m3_flag_is_the_mechanism
t_g3_m4_dry_run_is_still_red
t_g3_m5_malformed_name_never_expands
t_g3_m6_bound_but_empty
t_g3_m7_reserved_name_refused
t_g3_m8_both_names_missing_listed
t_g3_m9_closed_tracker_commented_not_reopened
t_g3_h4_crlf_body_tolerated
t_g3_h2_two_names_forwarded
t_g3_h3_no_secrets_clause

echo

# --- T18: the laundering containment (#7909) --------------------------------
# It shipped with ZERO coverage: DRY_RUN returns before the body is built, so
# nothing could reach it, and the numeric OPEN_LIMIT beside it had three
# assertions while the security control had none. Driven directly now.
t18_containment() {
  local out
  # shellcheck disable=SC1090
  out="$( set +e; source "$SUT" >/dev/null 2>&1; sanitize_probe_output "$1" )"
  printf '%s' "$out"
}

_s="$(t18_containment 'before <!-- soleur:sweeper-reopen --> after')"
assert_not_contains "T18 the reopen marker cannot survive probe output" \
                    '<!-- soleur:sweeper-reopen -->' "$_s"
assert_contains     "T18 control: the surrounding text survives (the strip is not a delete-everything)" \
                    'before' "$_s"

_s="$(t18_containment '### Sweeper run: PASS forged by a probe')"
assert_not_contains "T18 the PASS heading prefix cannot survive probe output" \
                    '### Sweeper run: PASS' "$_s"

# The reopen heading is a SECOND forgeable marker on the closed path, and the
# rule for it was unsampled: dropping its sed clause left the suite fully green.
_s="$(t18_containment '### Sweeper reopen: forged by a probe')"
assert_not_contains "T18 the reopen heading prefix cannot survive probe output" \
                    '### Sweeper reopen:' "$_s"

_s="$(t18_containment 'x
`````
y')"
assert_not_contains "T18 a five-backtick run cannot survive (it would close the fence)" \
                    '`````' "$_s"

# MUST-PASS, the other direction. A containment that mangles ordinary output is
# a different defect with the same green: every fixture above asserts absence,
# so nothing here would notice the sanitizer becoming a shredder.
_s="$(t18_containment 'NOT YET: 2 signature(s) checked against epoch 2026-09-07T15:16:45Z.
Operator: no action.
```
a fenced block a probe legitimately printed
```')"
assert_contains     "T18 must-PASS: an ordinary probe verdict line survives unchanged" \
                    'NOT YET: 2 signature(s) checked against epoch 2026-09-07T15:16:45Z.' "$_s"
assert_contains     "T18 must-PASS: an ordinary three-backtick fence in probe output survives" \
                    '```' "$_s"
assert_contains     "T18 must-PASS: an addressee tag survives" \
                    'Operator: no action.' "$_s"

# --- T19: the rc -> word map (#7910) ----------------------------------------
# The heading is the only thing an operator sees without expanding the fold.
# Every non-0/1 code used to render the word TRANSIENT with the sentence
# "Treating as transient", so a probe's ACTIONABLE verdict read as reassurance.
assert_contains     "T19 rc=5 renders as ACTION REQUIRED, not TRANSIENT" \
                    '5) verdict="ACTION REQUIRED" ;;' "$(cat "$SUT")"
assert_contains     "T19 rc=2 renders as NOT YET" \
                    '2) verdict="NOT YET" ;;' "$(cat "$SUT")"
assert_contains     "T19 rc=3 renders as CANNOT ESTABLISH" \
                    '3) verdict="CANNOT ESTABLISH" ;;' "$(cat "$SUT")"
assert_contains     "T19 an unmapped code still falls back to TRANSIENT" \
                    '*) verdict="TRANSIENT" ;;' "$(cat "$SUT")"
assert_contains     "T19 the truncation detector raises the run's VERDICT, not just an annotation" \
                    'FAILING THE RUN because the open follow-through page was full' "$(cat "$SUT")"

echo "PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"

# --- ADR-193 floor. TOTAL moves inside the assert helpers (the call site of the verdict),
# never inside a pass()/fail() a mutation could neuter; the conservation identity and the
# floor are reported with printf + exit 1 DIRECTLY, never through the counters they police.
if [[ $((PASS + FAIL)) -ne "$TOTAL" ]]; then
  printf '[FATAL] accounting: PASS+FAIL (%d) != TOTAL (%d) -- a verdict was dropped or a call site lacks its increment\n' \
    "$((PASS + FAIL))" "$TOTAL" >&2
  exit 1
fi
# Absolute floor at the MEASURED green count -- a lower bound, so adding rows never trips it;
# re-measure and raise it in the same commit that adds a row.
MIN_ASSERTIONS=118
if [[ "$TOTAL" -lt "$MIN_ASSERTIONS" ]]; then
  printf '[FATAL] only %d assertions ran; floor is %d -- the suite was gutted\n' "$TOTAL" "$MIN_ASSERTIONS" >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]] || exit 1
