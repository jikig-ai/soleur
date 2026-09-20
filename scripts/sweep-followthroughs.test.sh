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
# One owning trap for every tempfile/tempdir this suite allocates (ADR-129,
# lint-trap-tempfile-ownership rule (c)). setup_tmpdir roots and per-row fixtures all live
# under it, so a suite that dies mid-row leaks nothing.
SUITE_TMP=$(mktemp -d)
trap 'rm -rf "$SUITE_TMP"' EXIT
declare -a FAILURES=()   # append-only ledger the verdict reads; see the instrument self-test
FAIL=0
TOTAL=0

# ADR-193 shape: pass()/fail() are the TERMINAL verdict helpers and move ONLY the verdict
# counters; the assert_* wrappers move TOTAL (the case counter) at the call site. Stubbing
# a verdict helper therefore drops the verdict WITHOUT dropping its count, and the
# conservation identity at the bottom catches it.
pass() { PASS=$((PASS + 1)); echo "PASS: $1"; }
# TOTAL is deliberately NOT incremented here. A case counter moved inside a verdict helper
# makes the conservation identity a tautology, and `scripts/guard-vacuity-floor.test.sh`
# rejects exactly that shape -- measured: it caught this file the moment the increment moved
# in. The six DIRECT `fail "...mutation did not land..."` call sites therefore carry their own
# `TOTAL=$((TOTAL + 1));` prefix, at the CALL SITE, the same discipline the assert helpers use.
# Before that, a fired landing check skewed the identity by +1 and the run died with
# `accounting: PASS+FAIL (179) != TOTAL (178)` -- handing the operator "a verdict was dropped"
# instead of the author`s carefully worded "mutation did not land" diagnosis.
fail() { FAIL=$((FAIL + 1)); FAILURES+=("$1"); echo "FAIL: $1"; }

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
  root=$(mktemp -d -p "$SUITE_TMP")
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
  assert_eq        "T6 run_one returns 0 (the fenced directive is not honored)" "0" "$rc"
  # RE-PINNED (#7490). The fence skip is unchanged -- the script still must not run -- but the
  # SILENCE is gone: `no directive` was indistinguishable from a tracker nobody ever wrote a
  # directive for, which is how six trackers stayed dead for months. The verdict now names the
  # cause. Asserting the OLD string here would pin the very silence this change removes.
  assert_contains  "T6 reports the fenced cause, not a bare no-directive skip" \
                   "directive found INSIDE A CODE FENCE" "$combined"
  assert_not_contains "T6 does NOT report a bare no-directive skip (that is a different fix)" \
                   "no directive — skipping" "$combined"
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
# `-` not `:-`, so SET-BUT-EMPTY and UNSET are distinguishable from the outside. They are
# different states for the clock channel: empty means "the directive carries no earliest=",
# unset means "the sweeper never forwarded one at all", and a probe must be able to tell them
# apart to say which fix the operator owes (#8386).
printf 'SOLEUR_FT_EARLIEST=[%s]\n' "${SOLEUR_FT_EARLIEST-<unset>}"
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

# =============================================================================
# THE CLOCK CHANNEL (#8386) -- the sweeper forwards the `earliest` IT GATED ON.
#
# A probe that measures how long it has been parked needs the horizon this sweep actually
# applied. Before this, probes re-derived it from a copy in their own file header -- a second
# copy of an issue-body value. The two drift the moment a body directive is re-baselined, or a
# SECOND tracker enrols the same script with its own `earliest=`; the probe then escalates (or
# declines to) on a horizon nobody set. These rows pin the producer half of that seam. The
# consumer half is pinned in scripts/followthroughs/registry-luks-live-8386.test.sh
# (the WHOSE CLOCK block).
# =============================================================================

# --- CLK-1: the value the probe receives IS the directive's, byte for byte ---
t_clk1_earliest_forwarded() {
  local root; root=$(g3_root "$(g3_body "")")
  g3_run "$root" "$SUT"
  local posted=""; [[ -f "$root/comment-9001" ]] && posted=$(cat "$root/comment-9001")
  assert_eq       "CLK-1 forwarding the clock does not change the verdict" "0" "$(cat "$root/rc")"
  # By VALUE, not presence: a forward that hardcoded a constant, or passed the wrong variable,
  # satisfies every presence-only assertion. g3_body's directive says earliest=2020-01-01.
  assert_contains "CLK-1 the probe receives the directive's own earliest" \
                  "SOLEUR_FT_EARLIEST=[2020-01-01T00:00:00Z]" "$posted"
  rm -rf "$root"
}

# --- CLK-2: a directive with NO `earliest=` forwards SET-BUT-EMPTY, never unset ---
# The sweeper gates on `${earliest:-}` -> iso_to_epoch "" -> 0, i.e. it runs. The probe must be
# able to see that it ran with no horizon: unset would be indistinguishable from a standalone
# run, which is exactly the case where falling back to a file-header copy is correct.
t_clk2_absent_earliest_is_empty_not_unset() {
  local root; root=$(g3_root \
    '[{"number":9001,"body":"<!-- soleur:followthrough script=scripts/followthroughs/p.sh -->"}]')
  g3_run "$root" "$SUT"
  local posted=""; [[ -f "$root/comment-9001" ]] && posted=$(cat "$root/comment-9001")
  assert_eq       "CLK-2 a directive with no earliest= still runs" "0" "$(cat "$root/rc")"
  assert_contains "CLK-2 the probe sees SET-BUT-EMPTY, not <unset>" \
                  "SOLEUR_FT_EARLIEST=[]" "$posted"
  rm -rf "$root"
}

# --- CLK-3: a directive cannot name the channel in `secrets=` ---
# Forwarding is last-assignment-wins, so a directive-supplied SOLEUR_FT_EARLIEST placed after
# the sweeper's own would hand the probe a horizon this sweep did not gate on -- the whole
# defect the channel closes, re-opened from the issue body. Reserved, and refused loudly.
t_clk3_channel_name_is_reserved() {
  local root; root=$(g3_root "$(g3_body SOLEUR_FT_EARLIEST)")
  g3_run "$root" "$SUT" SOLEUR_FT_EARLIEST=2099-01-01T00:00:00Z
  local rc; rc=$(cat "$root/rc"); local posted=""; [[ -f "$root/comment-9001" ]] && posted=$(cat "$root/comment-9001")
  assert_eq       "CLK-3 naming the clock channel reds the run" "1" "$([[ "$rc" != "0" ]] && echo 1 || echo 0)"
  assert_contains "CLK-3 the comment says the name is reserved" "reserved name" "$posted"
  assert_not_contains "CLK-3 the probe was NOT run" "running scripts/followthroughs/p.sh" "$(cat "$root/out")"
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


# =============================================================================
# GUARD 2 (#7490) -- the sweeper's FENCED-ONLY DIRECTIVE verdict is LOUD.
#
# Property: an OPEN follow-through issue whose body carries a column-0 directive OPENER only
# inside a code fence receives a comment naming the cause and the fix, and the run exits
# non-zero -- while a body with NO directive at all, and a body with a fenced example beside a
# real directive, are unaffected.
#
# WHICH HARNESS DECIDES WHICH ROW. `invoke_run_one` sources the SUT and calls run_one directly
# under DRY_RUN=1: it can observe neither the run-level exit (raised in the `BASH_SOURCE == $0`
# block) nor a posted comment. Every row asserting a run-level verdict or a comment therefore
# uses `g3_run` -- `env -i ... bash "$SUT"` end to end. `FENCED_DIRECTIVE=1` is an internal
# variable with NO observable, so no row asserts the flag; rows assert the ::error:: and the rc.
#
# Every source-mutation row goes through `g4_mutate`, which asserts the mutation LANDED in the
# region under test: `diff -q` proves the file changed, not that the edit hit the right line.
# =============================================================================

G4_FENCED_BODY='Example (for reference):\n\n```html\n<!-- soleur:followthrough script=scripts/followthroughs/p.sh earliest=2020-01-01T00:00:00Z -->\n```\n\nEnd.'

g4_open_json() { # g4_open_json <number> <body-with-\n-escapes>
  printf '[{"number":%s,"body":"%s"}]' "$1" "$2"
}

# g4_mutate <name> <sed-expr> <post-image-grep> <pre-image-grep> -> echoes the mutant path, or
# the empty string when the mutation did not land (caller records a FAIL row in that case).
g4_mutate() {
  local root="$1" name="$2" expr="$3" post="$4" pre="$5"
  local mut="$root/sut-$name.sh"
  sed "$expr" "$SUT" > "$mut"
  if diff -q "$SUT" "$mut" >/dev/null 2>&1; then printf ''; return; fi
  local n_post; n_post=$(grep -cF -- "$post" "$mut" || true)
  local n_pre;  n_pre=$(grep -cF -- "$pre" "$mut" || true)
  if [[ "$n_post" != "1" || "$n_pre" != "0" ]]; then printf ''; return; fi
  printf '%s' "$mut"
}

# --- G4-1: the target. Fenced-only body, open mode, end-to-end. ---
t_g4_1_fenced_only_is_loud() {
  local root; root=$(g3_root "$(g4_open_json 9101 "$G4_FENCED_BODY")")
  g3_run "$root" "$SUT"
  local rc; rc=$(cat "$root/rc"); local posted=""; [[ -f "$root/comment-9101" ]] && posted=$(cat "$root/comment-9101")
  assert_contains "G4-1 the comment carries the fenced heading" "### Sweeper run: DIRECTIVE INSIDE CODE FENCE" "$posted"
  assert_contains "G4-1 the comment names the fix (column 0, outside any fence)" "column 0, outside any fence" "$posted"
  assert_contains "G4-1 the per-tracker ::error:: names the issue and the count" "issue #9101: its soleur:followthrough directive is inside a code fence (1 occurrence(s))" "$(cat "$root/err")"
  assert_contains "G4-1 the run-level ::error:: names the cause" "FAILING THE RUN because at least one tracker carries a soleur:followthrough directive inside a code fence" "$(cat "$root/err")"
  assert_not_contains "G4-1 the fenced script is NOT run" "running scripts/followthroughs/p.sh" "$(cat "$root/out")"
  assert_eq "G4-1 the run exits non-zero" "1" "$([[ "$rc" != "0" ]] && echo 1 || echo 0)"
  rm -rf "$root"
}

# --- G4-2: DISPATCH. Delete `FENCED_DIRECTIVE=1` -> the run exits 0 on the same body. ---
t_g4_2_flag_is_the_mechanism() {
  local root; root=$(g3_root "$(g4_open_json 9101 "$G4_FENCED_BODY")")
  local mut; mut=$(g4_mutate "$root" nofence-flag 's|^      FENCED_DIRECTIVE=1$|      FENCED_DIRECTIVE_MUTATED=1|' 'FENCED_DIRECTIVE_MUTATED=1' '      FENCED_DIRECTIVE=1')
  if [[ -z "$mut" ]]; then
    TOTAL=$((TOTAL + 1)); fail "G4-2 mutation did not land in the region under test (no lone FENCED_DIRECTIVE=1 assignment) -- the row would be vacuous"
  else
    g3_run "$root" "$mut"
    assert_eq "G4-2 with FENCED_DIRECTIVE=1 deleted the same body exits 0 -- the flag is the mechanism" "0" "$(cat "$root/rc")"
    assert_contains "G4-2 the mutant still posts the comment (only the VERDICT was removed)" "DIRECTIVE INSIDE CODE FENCE" "$(cat "$root/comment-9101" 2>/dev/null)"
  fi
  rm -rf "$root"
}

# --- G4-3: move the increment onto the FENCE DELIMITER line -> the 19 fenced-but-directive-less
# trackers start reporting as fenced. The false positive pinned as a mutation. ---
t_g4_3_increment_on_delimiter_false_positives() {
  local root; root=$(g3_root "$(g4_open_json 9102 'Some prose.\n\n```bash\necho hi\n```\n\nMore prose, no directive anywhere.')")
  local mut; mut=$(g4_mutate "$root" delimiter-increment \
    's@fence = 1; fence_ch = fc; fence_len = fn; next@fence = 1; fence_ch = fc; fence_len = fn; fenced_seen++; next@' \
    'fence_len = fn; fenced_seen++; next' \
    'fence_len = fn; next')
  if [[ -z "$mut" ]]; then
    TOTAL=$((TOTAL + 1)); fail "G4-3 mutation did not land -- the increment is not on the line this row mutates"
  else
    g3_run "$root" "$mut"
    assert_eq "G4-3 with the increment on the delimiter, a fence-but-no-directive body reds (the 19-tracker false positive)" "1" "$([[ "$(cat "$root/rc")" != "0" ]] && echo 1 || echo 0)"
  fi
  rm -rf "$root"
}

# --- G4-7 (must-PASS): two fenced blocks, NO directive anywhere -> quiet, exit 0. ---
t_g4_7_fences_without_directive_stay_quiet() {
  local root; root=$(g3_root "$(g4_open_json 9102 'Prose.\n\n```bash\necho one\n```\n\n```json\n{\"a\":1}\n```\n\nNo directive.')")
  g3_run "$root" "$SUT"
  assert_eq "G4-7 must-PASS: fences with no directive exit 0" "0" "$(cat "$root/rc")"
  assert_contains "G4-7 it is reported as a plain no-directive skip" "no directive — skipping" "$(cat "$root/out")"
  assert_not_contains "G4-7 no fenced verdict is emitted" "INSIDE A CODE FENCE" "$(cat "$root/out")$(cat "$root/err")"
  assert_eq "G4-7 no comment was posted" "absent" "$([[ -f "$root/comment-9102" ]] && echo present || echo absent)"
  rm -rf "$root"
}

# --- G4-4 + G4-8 (must-PASS): a fenced EXAMPLE FIRST and a real unfenced directive AFTER.
# The `fence &&` guard is what keeps this quiet; removing it reds this body. ---
t_g4_8_example_beside_real_directive() {
  local body='Example:\n\n```html\n<!-- soleur:followthrough script=scripts/followthroughs/p.sh earliest=2020-01-01T00:00:00Z -->\n```\n\nReal:\n\n<!-- soleur:followthrough script=scripts/followthroughs/p.sh earliest=2020-01-01T00:00:00Z -->'
  local root; root=$(g3_root "$(g4_open_json 9103 "$body")")
  g3_run "$root" "$SUT"
  assert_eq "G4-8 must-PASS: a fenced example beside a real directive exits 0" "0" "$(cat "$root/rc")"
  assert_contains "G4-8 the real directive is honored and the probe runs" "running scripts/followthroughs/p.sh" "$(cat "$root/out")"
  assert_not_contains "G4-8 no fenced verdict" "INSIDE A CODE FENCE" "$(cat "$root/out")$(cat "$root/err")"

  # G4-4. The example-beside-real shape is protected by TWO independent conditions, and the
  # row reports that rather than pretending one of them is the mechanism:
  #   (a) parse_directive's END emits the meta only when `seen == 0`;
  #   (b) run_one's loud branch sits inside `if [[ -z "${script:-}" ]]`, so a honoured
  #       directive never reaches it whatever the meta says.
  # Each single mutation therefore SURVIVES -- not because the fixture is inadequate, but
  # because the other condition still holds. That is a defence-in-depth result, and the rows
  # below assert it in both directions: each alone survives (labelled equivalent under its
  # sibling), and the PAIR is load-bearing.
  local mut_a; mut_a=$(g4_mutate "$root" no-seen-zero-guard \
    's@if (seen == 0 && fenced_seen > 0)@if (fenced_seen > 0)@' \
    'if (fenced_seen > 0) print' \
    'if (seen == 0 && fenced_seen > 0)')
  if [[ -z "$mut_a" ]]; then
    TOTAL=$((TOTAL + 1)); fail "G4-4 mutation (a) did not land -- the END block's seen==0 condition is not where this row mutates"
  else
    local root2; root2=$(g3_root "$(g4_open_json 9103 "$body")")
    g3_run "$root2" "$mut_a"
    assert_eq "G4-4a dropping only END's 'seen == 0' SURVIVES -- equivalent while run_one's -z script gate stands" "0" "$(cat "$root2/rc")"
    rm -rf "$root2"
  fi
  local mut_b; mut_b="$root/sut-both-guards-dropped.sh"
  sed -e 's@if (seen == 0 && fenced_seen > 0)@if (fenced_seen > 0)@' \
      -e 's@^  if \[\[ -z "\${script:-}" \]\]; then$@  if [[ 1 == 1 ]]; then  # both-guards-dropped@' "$SUT" > "$mut_b"
  if [[ "$(grep -c 'both-guards-dropped' "$mut_b" || true)" != "1" || "$(grep -c 'seen == 0 && fenced_seen' "$mut_b" || true)" != "0" ]]; then
    TOTAL=$((TOTAL + 1)); fail "G4-4 mutation (b) did not land in both regions -- the paired row would be vacuous"
  else
    local root3; root3=$(g3_root "$(g4_open_json 9103 "$body")")
    g3_run "$root3" "$mut_b"
    assert_eq "G4-4b dropping BOTH guards reds the example-beside-real body -- the PAIR is what keeps row 8 quiet" "1" "$([[ "$(cat "$root3/rc")" != "0" ]] && echo 1 || echo 0)"
    rm -rf "$root3"
  fi
  rm -rf "$root"
}

# --- G4-9: an INDENTED (3-space) fence. The widened predicate must see it; three live bodies
# (#6678, #6565, #7674) carry indented fences, which is why the predicate is widened at all. ---
t_g4_9_indented_fence() {
  local root; root=$(g3_root "$(g4_open_json 9104 'Note:\n\n   ```html\n<!-- soleur:followthrough script=scripts/followthroughs/p.sh earliest=2020-01-01T00:00:00Z -->\n   ```\n\nEnd.')")
  g3_run "$root" "$SUT"
  assert_eq "G4-9 a 3-space-indented fence is still a fence -> red" "1" "$([[ "$(cat "$root/rc")" != "0" ]] && echo 1 || echo 0)"
  assert_contains "G4-9 the fenced verdict is emitted" "DIRECTIVE INSIDE CODE FENCE" "$(cat "$root/comment-9104" 2>/dev/null)"
  rm -rf "$root"
}

# --- G4-5 + G4-10: the `mode == "open"` gate. A CLOSED tracker with a fenced-only body is
# logged and returns 0 with no comment and no summary entry; deleting the gate reds it. ---
t_g4_10_closed_mode_is_quiet() {
  local root; root=$(setup_tmpdir)
  cat > "$root/scripts/followthroughs/p.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$root/scripts/followthroughs/p.sh"
  make_gh_stub "$root" '[]' '[]' '{"comments":[]}'
  local body
  body=$(printf 'Example:\n\n```html\n<!-- soleur:followthrough script=scripts/followthroughs/p.sh earliest=2020-01-01T00:00:00Z -->\n```\n')
  local out
  out=$(
    cd "$root"
    export PATH="$root/bin:$PATH" GH_REPO="test/test" DRY_RUN=0
    # shellcheck disable=SC1090
    source "$SUT"
    set +e
    FENCED_FILE="$root/fenced.txt" NO_DIRECTIVE_FILE="$root/nodir.txt" run_one 9105 "$body" closed 2>&1
    echo "__RC__=$?"
  )
  assert_eq       "G4-10 closed mode returns 0" "0" "${out##*__RC__=}"
  assert_not_contains "G4-10 closed mode posts no fenced comment" "DIRECTIVE INSIDE CODE FENCE" "$out"
  assert_eq       "G4-10 closed mode writes no FENCED_FILE entry" "absent" "$([[ -s "$root/fenced.txt" ]] && echo present || echo absent)"
  assert_eq       "G4-10 closed mode writes no NO_DIRECTIVE_FILE entry either (it is not directive-less)" "absent" "$([[ -s "$root/nodir.txt" ]] && echo present || echo absent)"
  rm -rf "$root"
}

t_g4_5_mode_gate_is_load_bearing() {
  local root; root=$(g3_root '[]' )
  local mut; mut=$(g4_mutate "$root" no-mode-gate \
    's@ && "\$mode" == "open" \]\]; then$@ ]]; then  # mode-gate-removed@' \
    '# mode-gate-removed' \
    '&& "$mode" == "open" ]]; then')
  if [[ -z "$mut" ]]; then
    TOTAL=$((TOTAL + 1)); fail "G4-5 mutation did not land -- the mode gate is not where this row mutates"
  else
    local body; body=$(printf 'Example:\n\n```html\n<!-- soleur:followthrough script=scripts/followthroughs/p.sh earliest=2020-01-01T00:00:00Z -->\n```\n')
    local out
    out=$(
      cd "$root"
      export PATH="$root/bin:$PATH" GH_REPO="test/test" DRY_RUN=1
      # shellcheck disable=SC1090
      source "$mut"
      set +e
      run_one 9105 "$body" closed 2>&1
    )
    assert_contains "G4-5 with the mode gate deleted, a CLOSED tracker enters the fenced verdict branch (the gate is load-bearing)" "would comment: directive inside code fence" "$out"
  fi
  rm -rf "$root"
}

# --- G4-11 / G4-12: unbalanced fences. BEFORE a directive -> the verdict carries the extra
# sentence; AFTER a valid directive -> the directive is honored and only a ::warning:: fires. ---
t_g4_11_unbalanced_before_directive() {
  local root; root=$(g3_root "$(g4_open_json 9106 'Note:\n\n```html\n<!-- soleur:followthrough script=scripts/followthroughs/p.sh earliest=2020-01-01T00:00:00Z -->\n\n(the fence is never closed)')")
  g3_run "$root" "$SUT"
  local posted=""; [[ -f "$root/comment-9106" ]] && posted=$(cat "$root/comment-9106")
  assert_eq       "G4-11 an unbalanced fence swallowing the directive reds the run" "1" "$([[ "$(cat "$root/rc")" != "0" ]] && echo 1 || echo 0)"
  assert_contains "G4-11 the comment carries the UNBALANCED sentence, not just 'move it out'" "unbalanced" "$posted"
  rm -rf "$root"
}

t_g4_12_unbalanced_after_directive() {
  local root; root=$(g3_root "$(g4_open_json 9107 '<!-- soleur:followthrough script=scripts/followthroughs/p.sh earliest=2020-01-01T00:00:00Z -->\n\nNotes:\n\n```bash\necho unterminated')")
  g3_run "$root" "$SUT"
  assert_eq       "G4-12 must-PASS: an unbalanced fence AFTER a valid directive still exits 0" "0" "$(cat "$root/rc")"
  assert_contains "G4-12 the directive is honored and the probe runs" "running scripts/followthroughs/p.sh" "$(cat "$root/out")"
  assert_contains "G4-12 a ::warning:: names the unbalanced fence" "::warning::sweep-followthroughs: issue #9107: its directive was honored, but the body has an unbalanced code fence" "$(cat "$root/err")"
  assert_not_contains "G4-12 no fenced VERDICT is emitted" "INSIDE A CODE FENCE" "$(cat "$root/err")"
  rm -rf "$root"
}

# --- G4-13: an UNFENCED but INDENTED directive. The column-0 contract means the sweeper does
# not honor it, and it must report as a plain no-directive skip -- not as fenced. The AC14
# verification check fails on the same body, so the two agree rather than disagreeing. ---
t_g4_13_indented_directive_is_no_directive() {
  local root; root=$(g3_root "$(g4_open_json 9108 'Notes:\n\n <!-- soleur:followthrough script=scripts/followthroughs/p.sh earliest=2020-01-01T00:00:00Z -->')")
  g3_run "$root" "$SUT"
  assert_eq       "G4-13 a one-space-indented directive is not honored (column-0 contract) -> exit 0" "0" "$(cat "$root/rc")"
  assert_contains "G4-13 it reports as a plain no-directive skip" "no directive — skipping" "$(cat "$root/out")"
  assert_not_contains "G4-13 it is NOT reported as fenced" "INSIDE A CODE FENCE" "$(cat "$root/out")$(cat "$root/err")"
  rm -rf "$root"
}

# --- G4-14: CRLF bodies. `sub(/\r$/,"")` runs before the fence rule, so a web-editor paste
# classifies identically to an LF body -- fenced-only reds, unfenced passes. ---
t_g4_14_crlf() {
  local root; root=$(g3_root "$(g4_open_json 9109 'Note:\r\n\r\n```html\r\n<!-- soleur:followthrough script=scripts/followthroughs/p.sh earliest=2020-01-01T00:00:00Z -->\r\n```\r\n')")
  g3_run "$root" "$SUT"
  assert_eq "G4-14 a CRLF fenced-only body still reds" "1" "$([[ "$(cat "$root/rc")" != "0" ]] && echo 1 || echo 0)"
  rm -rf "$root"
  local root2; root2=$(g3_root "$(g4_open_json 9110 '<!-- soleur:followthrough script=scripts/followthroughs/p.sh earliest=2020-01-01T00:00:00Z -->\r\n')")
  g3_run "$root2" "$SUT"
  assert_eq "G4-14 must-PASS: a CRLF UNFENCED directive is still honored" "0" "$(cat "$root2/rc")"
  assert_contains "G4-14 the CRLF directive's probe runs" "running scripts/followthroughs/p.sh" "$(cat "$root2/out")"
  rm -rf "$root2"
}

# --- G4-15: the comment post fails. The run is already red; the LOST COMMENT must be visible
# in the annotations too, or the outcome is "red run, silent tracker". ---
t_g4_15_comment_post_failure() {
  local root; root=$(g3_root "$(g4_open_json 9101 "$G4_FENCED_BODY")")
  cat > "$root/bin/gh" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *"--state closed"*) cat "$root/closed.json" ;;
  *"issue list"*)     cat "$root/open.json" ;;
  *"--json comments"*) cat "$root/comments.json" ;;
  *"issue comment"*)  cat > /dev/null; exit 1 ;;
  *) exit 99 ;;
esac
EOF
  chmod +x "$root/bin/gh"
  g3_run "$root" "$SUT"
  assert_contains "G4-15 a failed comment post emits the LOST-COMMENT ::warning::" "the DIRECTIVE INSIDE CODE FENCE comment could not be posted; the tracker was not told" "$(cat "$root/err")"
  assert_eq       "G4-15 the run is still red" "1" "$([[ "$(cat "$root/rc")" != "0" ]] && echo 1 || echo 0)"
  rm -rf "$root"
}

# --- G4-16: DRY_RUN. The comment is suppressed and no gh write is attempted, but the
# ::error:: still fires and the run is still red -- a dry run that hid the finding would make
# the rehearsal useless for exactly the case it exists to rehearse. ---
t_g4_16_dry_run() {
  local root; root=$(g3_root "$(g4_open_json 9101 "$G4_FENCED_BODY")")
  G3_DRY_RUN=1 g3_run "$root" "$SUT"
  assert_contains "G4-16 DRY_RUN still emits the per-tracker ::error::" "is inside a code fence" "$(cat "$root/err")"
  assert_eq       "G4-16 DRY_RUN posts no comment" "absent" "$([[ -f "$root/comment-9101" ]] && echo present || echo absent)"
  assert_not_contains "G4-16 DRY_RUN attempts no gh issue comment" "issue comment" "$(cat "$root/gh-calls.log" 2>/dev/null || echo)"
  assert_eq       "G4-16 DRY_RUN still reds the run" "1" "$([[ "$(cat "$root/rc")" != "0" ]] && echo 1 || echo 0)"
  rm -rf "$root"
}

# --- G4-17: three open trackers -- compliant, fenced, fenced. BOTH fenced ones are commented
# (the walk does not stop at the first), the compliant one gets its normal verdict, and each
# tracker's comment count is exactly 1. ---
t_g4_17_walk_does_not_stop() {
  local dq='<!-- soleur:followthrough script=scripts/followthroughs/p.sh earliest=2020-01-01T00:00:00Z -->'
  local open_json
  open_json=$(printf '[{"number":9200,"body":"%s"},{"number":9201,"body":"%s"},{"number":9202,"body":"%s"}]' \
    "$dq" "$G4_FENCED_BODY" "$G4_FENCED_BODY")
  local root; root=$(g3_root "$open_json")
  g3_run "$root" "$SUT"
  assert_contains "G4-17 the FIRST fenced tracker is commented" "DIRECTIVE INSIDE CODE FENCE" "$(cat "$root/comment-9201" 2>/dev/null)"
  assert_contains "G4-17 the SECOND fenced tracker is also commented (the walk does not stop)" "DIRECTIVE INSIDE CODE FENCE" "$(cat "$root/comment-9202" 2>/dev/null)"
  assert_contains "G4-17 the compliant tracker still gets its normal verdict" "### Sweeper run: PASS" "$(cat "$root/comment-9200" 2>/dev/null)"
  assert_not_contains "G4-17 the compliant tracker gets NO fenced comment" "INSIDE A CODE FENCE" "$(cat "$root/comment-9200" 2>/dev/null)"
  assert_eq "G4-17 exactly one comment call per tracker" "3" "$(grep -c 'issue comment' "$root/gh-calls.log" || echo 0)"
  rm -rf "$root"
}

# --- G4-18: GITHUB_STEP_SUMMARY. The fenced tracker appears under its OWN heading and NOT
# under "missing directive"; the directive-less one appears only under "missing directive";
# and `no_directive=N` counts 1, not 2. One tracker in both lists would tell the operator two
# different things to do. ---
t_g4_18_step_summary_separation() {
  local open_json
  open_json=$(printf '[{"number":9301,"body":"%s"},{"number":9302,"body":"%s"}]' \
    "$G4_FENCED_BODY" 'Nothing here at all.')
  local root; root=$(g3_root "$open_json")
  (
    cd "$root" || exit 97
    local rc=0
    env -i PATH="$root/bin:$PATH" HOME="$HOME" GH_REPO="test/test" DRY_RUN=0 \
      GITHUB_STEP_SUMMARY="$root/summary.md" bash "$SUT" > "$root/out" 2> "$root/err" || rc=$?
    echo "$rc" > "$root/rc"
  )
  local summary; summary=$(cat "$root/summary.md" 2>/dev/null || echo)
  assert_contains "G4-18 the summary carries a fenced-directive section" "Follow-through directives inside a code fence (1)" "$summary"
  assert_contains "G4-18 the summary carries a missing-directive section" "Follow-through issues missing directive (1)" "$summary"
  # The no-directive section is emitted FIRST and the fenced section second, so "from the
  # missing heading to EOF" would swallow the fenced list and make the negative assertion
  # unfalsifiable. Split at the fenced heading: missing = before it, fenced = from it on.
  local missing_sec; missing_sec=$(awk '/^### .*issues missing directive/{f=1} /^### .*inside a code fence/{f=0} f' <<<"$summary")
  local fenced_sec;  fenced_sec=$(awk '/^### .*inside a code fence/{f=1} f' <<<"$summary")
  assert_contains     "G4-18 the FENCED tracker is listed under the fenced heading" "#9301" "$fenced_sec"
  assert_not_contains "G4-18 the FENCED tracker is NOT listed under missing-directive" "#9301" "$missing_sec"
  assert_contains     "G4-18 the directive-less tracker is listed under missing-directive" "#9302" "$missing_sec"
  assert_contains     "G4-18 no_directive counts 1, not 2" "sweep done (no_directive=1 fenced_directive=1)" "$(cat "$root/out")"
  rm -rf "$root"
}

# --- G4-19: an open list at OPEN_LIMIT (200) containing one fenced-only tracker. BOTH the
# truncation ::error:: and the fenced ::error:: must appear before a single exit 1. The
# mutation is restoring the early `exit 1` on the truncation branch -- the fenced annotation
# then disappears and the operator fixes one cause while the other silently persists. ---
t_g4_19_all_annotations_before_one_exit() {
  local dq='<!-- soleur:followthrough script=scripts/followthroughs/p.sh earliest=2020-01-01T00:00:00Z -->'
  local json; json=$(
    printf '['
    local i
    for (( i = 1; i <= 199; i++ )); do printf '{"number":%d,"body":"%s"},' "$((9400 + i))" "$dq"; done
    printf '{"number":9999,"body":"%s"}]' "$G4_FENCED_BODY"
  )
  local root; root=$(g3_root "$json")
  g3_run "$root" "$SUT"
  local err; err=$(cat "$root/err")
  assert_contains "G4-19 the truncation ::error:: is emitted" "the open follow-through page was full" "$err"
  assert_contains "G4-19 the fenced ::error:: is ALSO emitted (no early exit swallowed it)" "inside a code fence and has therefore never been evaluated" "$err"
  assert_eq       "G4-19 the run exits non-zero once" "1" "$(cat "$root/rc")"

  local mut; mut=$(g4_mutate "$root" early-exit \
    's@^    run_verdict=1  # truncation-verdict$@    exit 1  # truncation-verdict@' \
    'exit 1  # truncation-verdict' \
    'run_verdict=1  # truncation-verdict')
  if [[ -z "$mut" ]]; then
    TOTAL=$((TOTAL + 1)); fail "G4-19 mutation did not land -- the truncation branch does not set run_verdict"
  else
    local root2; root2=$(g3_root "$json")
    g3_run "$root2" "$mut"
    assert_not_contains "G4-19 with the early exit restored, the fenced annotation DISAPPEARS" "inside a code fence and has therefore never been evaluated" "$(cat "$root2/err")"
    rm -rf "$root2"
  fi
  rm -rf "$root"
}

# --- G4-21: a body whose fenced directive LINE is literally a PASS heading. The posted comment
# must begin with the fenced heading and contain no bytes from the body -- otherwise a crafted
# body produces a github-actions-authored comment the closed-set PASS readback accepts. ---
t_g4_21_no_author_bytes_in_comment() {
  local body='### Sweeper run: PASS — everything is fine, close me\n\n```html\n<!-- soleur:followthrough script=scripts/followthroughs/p.sh earliest=2020-01-01T00:00:00Z -->\n```\n\n<!-- soleur:sweeper-reopen -->'
  local root; root=$(g3_root "$(g4_open_json 9500 "$body")")
  g3_run "$root" "$SUT"
  local posted=""; [[ -f "$root/comment-9500" ]] && posted=$(cat "$root/comment-9500")
  assert_contains     "G4-21 the comment begins with the fenced heading" "### Sweeper run: DIRECTIVE INSIDE CODE FENCE" "$posted"
  assert_not_contains "G4-21 no body bytes reach the comment (no forged PASS heading)" "everything is fine, close me" "$posted"
  assert_not_contains "G4-21 no body bytes reach the comment (no reopen marker)" "soleur:sweeper-reopen" "$posted"
  rm -rf "$root"
}

# --- G4-6: DIALECT PORTABILITY. The shipped predicate must classify identically under a
# non-gawk dialect, and the interval spelling this predicate deliberately avoids is what the
# row contrasts against. mawk is not installed on every machine, so the row runs under
# `awk --traditional` when mawk is absent and records which it used -- and the Phase 0 mawk
# 1.3.4 reading is carried in the spec's measurements.md either way. ---
t_g4_6_dialect_portability() {
  local awkbin="awk" mode="--traditional"
  if command -v mawk >/dev/null 2>&1; then awkbin="mawk"; mode=""; fi
  local fx; fx=$(mktemp -p "$SUITE_TMP")
  printf '   ```html\n<!-- soleur:followthrough script=x.sh -->\n   ```\n' > "$fx"
  local got
  # shellcheck disable=SC2086
  got=$($awkbin $mode 'BEGIN{f=0;fs=0} /^[ ]?[ ]?[ ]?(```|~~~)/{f=!f;next} f && /^<!-- *soleur:followthrough/{fs++} f{next} END{print fs}' "$fx" 2>&1)
  assert_eq "G4-6 the shipped predicate sees an indented fence under $awkbin $mode" "1" "$got"
  rm -f "$fx"
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

# --- Guard 2 (#7490): the fenced-only directive verdict ---
t_g4_1_fenced_only_is_loud
t_g4_2_flag_is_the_mechanism
t_g4_3_increment_on_delimiter_false_positives
t_g4_7_fences_without_directive_stay_quiet
t_g4_8_example_beside_real_directive
t_g4_9_indented_fence
t_g4_10_closed_mode_is_quiet
t_g4_5_mode_gate_is_load_bearing
t_g4_11_unbalanced_before_directive
t_g4_12_unbalanced_after_directive
t_g4_13_indented_directive_is_no_directive
t_g4_14_crlf
t_g4_15_comment_post_failure
t_g4_16_dry_run
t_g4_17_walk_does_not_stop
t_g4_18_step_summary_separation
t_g4_19_all_annotations_before_one_exit
t_g4_21_no_author_bytes_in_comment
t_g4_6_dialect_portability
t_g3_h4_crlf_body_tolerated
t_g3_h2_two_names_forwarded
t_g3_h3_no_secrets_clause
t_clk1_earliest_forwarded
t_clk2_absent_earliest_is_empty_not_unset
t_clk3_channel_name_is_reserved

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

# INSTRUMENT SELF-TEST -- drives all three assert helpers through BOTH branches and requires
# every observable to move. Neither the identity nor the floor below can see this: both are
# computed from TOTAL, which the assert helpers move BEFORE consulting their condition.
# Measured 2026-09-18: forcing all three conditions to `[[ 1 == 1 ]]` reported
# `PASS=181 FAIL=0 TOTAL=181`, exit 0, byte-identical to the honest baseline; so did
# `fail() { PASS=$((PASS+1)); ... }`. This block catches both.
_p=$PASS _f=$FAIL _t=$TOTAL _n=${#FAILURES[@]}
if (( _n > 0 )); then _saved=("${FAILURES[@]}"); else _saved=(); fi
assert_eq           "self-test: assert_eq pass branch"            "x" "x"
assert_eq           "self-test: assert_eq fail branch (expected)" "x" "y"
assert_contains     "self-test: assert_contains pass branch"            "x" "axb"
assert_contains     "self-test: assert_contains fail branch (expected)" "x" "ab"
assert_not_contains "self-test: assert_not_contains pass branch"            "x" "ab"
assert_not_contains "self-test: assert_not_contains fail branch (expected)" "x" "axb"
if (( PASS != _p + 3 || FAIL != _f + 3 || TOTAL != _t + 6 || ${#FAILURES[@]} != _n + 3 )); then
  printf '[FATAL] instrument self-test: an assert helper did not move every observable (PASS %d->%d, FAIL %d->%d, TOTAL %d->%d, ledger %d->%d)\n' \
    "$_p" "$PASS" "$_f" "$FAIL" "$_t" "$TOTAL" "$_n" "${#FAILURES[@]}" >&2
  exit 1
fi
PASS=$_p; FAIL=$_f; TOTAL=$_t
if (( _n > 0 )); then FAILURES=("${_saved[@]}"); else FAILURES=(); fi

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
MIN_ASSERTIONS=188
if [[ "$TOTAL" -lt "$MIN_ASSERTIONS" ]]; then
  printf '[FATAL] only %d assertions ran; floor is %d -- the suite was gutted\n' "$TOTAL" "$MIN_ASSERTIONS" >&2
  exit 1
fi
# The verdict reads the append-only LEDGER as well as the counter: a fail() whose increment is
# redirected to PASS still leaves FAILURES populated, and the run still reds.
[[ "$FAIL" -eq 0 && "${#FAILURES[@]}" -eq 0 ]] || { printf 'FAILED: %d (ledger holds %d)\n' "$FAIL" "${#FAILURES[@]}" >&2; exit 1; }
