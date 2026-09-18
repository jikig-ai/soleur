#!/usr/bin/env bash
# Fixture-based tests for follow-through-directive-gate.sh. Each test composes
# a PreToolUse(Bash) input shape, pipes it to the hook, asserts the JSON
# permissionDecision matches expectation.
#
# Isolation pattern matches ship-unpushed-commits-gate.test.sh.

set -euo pipefail

# Redirect incident telemetry into a per-suite sandbox BEFORE any case runs.
# Inline per-call `INCIDENTS_REPO_ROOT=… bash "$HOOK"` is what leaked here:
# it was set on some invocations and missed on others, which greps identically
# to full isolation. See the helper header.
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/test-incident-sandbox.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/follow-through-directive-gate.sh"

PASS=0
FAIL=0
TOTAL=0
declare -a FAILURES=()   # append-only ledger the verdict reads; see the instrument self-test
_case=""          # set by run(); names the case a FAIL row belongs to

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq missing"; exit 0; }
command -v realpath >/dev/null 2>&1 || { echo "SKIP: realpath missing"; exit 0; }

# Build a tmp WORK_DIR with scripts/followthroughs/ + an existing executable
# stub. Echoes the path.
make_work_dir() {
  local tmp="$1"
  mkdir -p "$tmp/scripts/followthroughs"
  cat > "$tmp/scripts/followthroughs/ok-1234.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$tmp/scripts/followthroughs/ok-1234.sh"

  # Non-executable stub (chmod -x) to exercise the executable-bit gate
  cat > "$tmp/scripts/followthroughs/not-executable-1235.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod 644 "$tmp/scripts/followthroughs/not-executable-1235.sh"

  echo "$tmp"
}

# Compose the PreToolUse input as JSON. Args: <command> <cwd>
make_input() {
  jq -n --arg cmd "$1" --arg cwd "$2" '{
    tool_name: "Bash",
    tool_input: { command: $cmd },
    cwd: $cwd,
  }'
}

run() {
  local label="$1" input="$2"
  TOTAL=$((TOTAL + 1))
  _case="$1"
  local out rc
  out=$(printf '%s' "$input" | "$HOOK" 2>&1)
  rc=$?
  printf '[T%d] %s — rc=%d\n' "$TOTAL" "$label" "$rc"
  if [[ -n "$out" ]]; then
    printf '       output: %s\n' "$out" | head -c 300
    printf '\n'
  fi
  HOOK_OUT="$out"
  HOOK_RC="$rc"
}

assert_pass() {
  if [[ "$HOOK_RC" -ne 0 ]]; then
    echo "       FAIL: expected exit 0, got $HOOK_RC"
    FAIL=$((FAIL + 1)); FAILURES+=("$_case")
    return
  fi
  if [[ -n "$HOOK_OUT" ]]; then
    # Hook fail-open path: silent exit 0
    echo "       FAIL: expected silent fail-open, got output"
    FAIL=$((FAIL + 1)); FAILURES+=("$_case")
    return
  fi
  PASS=$((PASS + 1))
}

assert_deny() {
  local expected_substring="$1"
  if [[ "$HOOK_RC" -ne 0 ]]; then
    echo "       FAIL: expected exit 0 (deny JSON returned via stdout), got $HOOK_RC"
    FAIL=$((FAIL + 1)); FAILURES+=("$_case")
    return
  fi
  if [[ -z "$HOOK_OUT" ]]; then
    echo "       FAIL: expected deny JSON, got empty output"
    FAIL=$((FAIL + 1)); FAILURES+=("$_case")
    return
  fi
  local decision
  decision=$(printf '%s' "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null)
  if [[ "$decision" != "deny" ]]; then
    echo "       FAIL: expected permissionDecision=deny, got '$decision'"
    FAIL=$((FAIL + 1)); FAILURES+=("$_case")
    return
  fi
  if ! printf '%s' "$HOOK_OUT" | grep -q "$expected_substring"; then
    echo "       FAIL: deny reason missing substring '$expected_substring'"
    FAIL=$((FAIL + 1)); FAILURES+=("$_case")
    return
  fi
  PASS=$((PASS + 1))
}

# === T1: fail-open on non-issue-create commands ===
TMP=$(mktemp -d)
make_work_dir "$TMP" > /dev/null
INPUT=$(make_input "git status" "$TMP")
run "T1: git status is not gh issue create — fail open" "$INPUT"
assert_pass
rm -rf "$TMP"

# === T2: fail-open on gh issue create WITHOUT follow-through label ===
TMP=$(mktemp -d)
make_work_dir "$TMP" > /dev/null
INPUT=$(make_input 'gh issue create --title "test" --label bug --body "no directive needed"' "$TMP")
run "T2: no follow-through label — fail open" "$INPUT"
assert_pass
rm -rf "$TMP"

# === T3: deny when follow-through label + body lacks directive ===
TMP=$(mktemp -d)
make_work_dir "$TMP" > /dev/null
cat > "$TMP/body.md" <<'EOF'
## Follow-Through

Some text. No directive.
EOF
INPUT=$(make_input "gh issue create --title 'test' --label follow-through --body-file $TMP/body.md" "$TMP")
run "T3: directive missing — deny" "$INPUT"
assert_deny "requires a"
rm -rf "$TMP"

# === T4: deny when directive open marker present but no closing --> ===
TMP=$(mktemp -d)
make_work_dir "$TMP" > /dev/null
cat > "$TMP/body.md" <<'EOF'
## Follow-Through

<!-- soleur:followthrough script=scripts/followthroughs/ok-1234.sh earliest=2026-05-22T00:00:00Z

(missing closing marker)
EOF
INPUT=$(make_input "gh issue create --title 'test' --label follow-through --body-file $TMP/body.md" "$TMP")
run "T4: directive missing closing --> — deny" "$INPUT"
assert_deny "closing"
rm -rf "$TMP"

# === T5: deny when script= empty ===
TMP=$(mktemp -d)
make_work_dir "$TMP" > /dev/null
cat > "$TMP/body.md" <<'EOF'
## Follow-Through

<!-- soleur:followthrough earliest=2026-05-22T00:00:00Z -->
EOF
INPUT=$(make_input "gh issue create --title 'test' --label follow-through --body-file $TMP/body.md" "$TMP")
run "T5: missing script= — deny" "$INPUT"
assert_deny "script="
rm -rf "$TMP"

# === T6: deny when earliest= empty ===
TMP=$(mktemp -d)
make_work_dir "$TMP" > /dev/null
cat > "$TMP/body.md" <<'EOF'
## Follow-Through

<!-- soleur:followthrough script=scripts/followthroughs/ok-1234.sh -->
EOF
INPUT=$(make_input "gh issue create --title 'test' --label follow-through --body-file $TMP/body.md" "$TMP")
run "T6: missing earliest= — deny" "$INPUT"
assert_deny "earliest="
rm -rf "$TMP"

# === T7: deny when script path escapes scripts/followthroughs/ via .. traversal ===
TMP=$(mktemp -d)
make_work_dir "$TMP" > /dev/null
cat > "$TMP/body.md" <<'EOF'
## Follow-Through

<!-- soleur:followthrough script=scripts/followthroughs/../../etc/passwd earliest=2026-05-22T00:00:00Z -->
EOF
INPUT=$(make_input "gh issue create --title 'test' --label follow-through --body-file $TMP/body.md" "$TMP")
run "T7: script path traversal escape — deny" "$INPUT"
assert_deny "does not resolve under"
rm -rf "$TMP"

# === T8: deny when script does not exist on disk ===
TMP=$(mktemp -d)
make_work_dir "$TMP" > /dev/null
cat > "$TMP/body.md" <<'EOF'
## Follow-Through

<!-- soleur:followthrough script=scripts/followthroughs/missing-9999.sh earliest=2026-05-22T00:00:00Z -->
EOF
INPUT=$(make_input "gh issue create --title 'test' --label follow-through --body-file $TMP/body.md" "$TMP")
run "T8: script does not exist — deny" "$INPUT"
assert_deny "does not exist"
rm -rf "$TMP"

# === T9: deny when script is not executable ===
TMP=$(mktemp -d)
make_work_dir "$TMP" > /dev/null
cat > "$TMP/body.md" <<'EOF'
## Follow-Through

<!-- soleur:followthrough script=scripts/followthroughs/not-executable-1235.sh earliest=2026-05-22T00:00:00Z -->
EOF
INPUT=$(make_input "gh issue create --title 'test' --label follow-through --body-file $TMP/body.md" "$TMP")
run "T9: script not executable — deny" "$INPUT"
assert_deny "not executable"
rm -rf "$TMP"

# === T10: deny when earliest= does not parse ===
TMP=$(mktemp -d)
make_work_dir "$TMP" > /dev/null
cat > "$TMP/body.md" <<'EOF'
## Follow-Through

<!-- soleur:followthrough script=scripts/followthroughs/ok-1234.sh earliest=not-a-date -->
EOF
INPUT=$(make_input "gh issue create --title 'test' --label follow-through --body-file $TMP/body.md" "$TMP")
run "T10: earliest does not parse — deny" "$INPUT"
assert_deny "does not parse"
rm -rf "$TMP"

# === T11: PASS — valid directive + script + earliest ===
TMP=$(mktemp -d)
make_work_dir "$TMP" > /dev/null
cat > "$TMP/body.md" <<'EOF'
## Follow-Through

<!-- soleur:followthrough
  script=scripts/followthroughs/ok-1234.sh
  earliest=2026-05-22T15:00:00Z
  secrets=SOME_SECRET
-->

Verification details here.
EOF
INPUT=$(make_input "gh issue create --title 'test' --label follow-through --body-file $TMP/body.md" "$TMP")
run "T11: valid directive — pass" "$INPUT"
assert_pass
rm -rf "$TMP"

# === T12: fail-open when WORK_DIR is not a directory ===
INPUT=$(make_input "gh issue create --label follow-through --body 'no directive'" "/non/existent/path")
run "T12: invalid WORK_DIR — fail open" "$INPUT"
assert_pass

# === T13: deny on quoted label (e.g. --label "follow-through") ===
TMP=$(mktemp -d)
make_work_dir "$TMP" > /dev/null
cat > "$TMP/body.md" <<'EOF'
no directive
EOF
INPUT=$(make_input "gh issue create --title 'test' --label \"follow-through\" --body-file $TMP/body.md" "$TMP")
run "T13: quoted label — deny" "$INPUT"
assert_deny "requires a"
rm -rf "$TMP"

# === T14: fail-open when label substring matches but does not exactly match
# the follow-through label (e.g., 'follow-through-meta'). ===
TMP=$(mktemp -d)
make_work_dir "$TMP" > /dev/null
cat > "$TMP/body.md" <<'EOF'
no directive needed for follow-through-meta label
EOF
INPUT=$(make_input "gh issue create --title 'test' --label follow-through-meta --body-file $TMP/body.md" "$TMP")
run "T14: label superset 'follow-through-meta' — fail open" "$INPUT"
assert_pass
rm -rf "$TMP"

# === T15 (#5192): commit-body documenting `gh issue create --label
# follow-through` must NOT fire — the strip blanks the -m message body before
# the trigger grep. The body carries `--label follow-through` AND a `--body`
# value so the test reaches the strip path rather than the unrelated `:54`
# label early-exit: WITHOUT the strip this denies (directive-missing), WITH it
# the body is blanked and the hook fails open. See deepen finding D-P1-A. ===
TMP=$(mktemp -d)
make_work_dir "$TMP" > /dev/null
FP_CMD=$'git add . && git commit -m \'doc: gate needs\ngh issue create --label follow-through --body "x"\nend\''
INPUT=$(make_input "$FP_CMD" "$TMP")
run "T15 (#5192): commit-body gh issue create --label follow-through — fail open" "$INPUT"
assert_pass
rm -rf "$TMP"

# === T16: inline --body (not --body-file) carrying a VALID directive must PASS.
# Regression guard for the `print 2` → `print $2` typo in the BODY_INLINE perl
# extractor: pre-fix, BODY_INLINE was the literal "2" so EVERY inline-body
# create was wrongly denied (directive-missing). ===
TMP=$(mktemp -d)
make_work_dir "$TMP" > /dev/null
DIRECTIVE='<!-- soleur:followthrough script=scripts/followthroughs/ok-1234.sh earliest=2026-05-22T00:00:00Z -->'
INPUT=$(make_input "gh issue create --label follow-through --title t --body \"$DIRECTIVE\"" "$TMP")
run "T16: inline --body with valid directive — pass" "$INPUT"
assert_pass
rm -rf "$TMP"

# === T17 (#7490): a directive INSIDE A CODE FENCE denies, and the reason SAYS SO. ===
# The presence check greps the raw body, so a fenced directive satisfies it; the awk parser
# skips fences, so `script=` comes back empty and both land in the same branch. The generic
# "script= is empty" message sent the author hunting for a token that is visibly present,
# which is how the fenced form survived as the ship template's default and killed six
# trackers. The deny must name the fence.
TMP=$(mktemp -d)
make_work_dir "$TMP" > /dev/null
FENCED_BODY=$'## Verification\n\n```html\n<!-- soleur:followthrough script=scripts/followthroughs/ok-1234.sh earliest=2026-05-22T00:00:00Z -->\n```\n'
printf '%s' "$FENCED_BODY" > "$TMP/body.md"
INPUT=$(make_input "gh issue create --label follow-through --title t --body-file $TMP/body.md" "$TMP")
run "T17 (#7490): fenced directive — deny names the code fence" "$INPUT"
assert_deny "CODE FENCE"
rm -rf "$TMP"

# === T17b: the MATCHED CONTROL. The same body with the two fence lines removed must PASS.
# Without it, T17 is also satisfied by a gate that denies every body. ===
TMP=$(mktemp -d)
make_work_dir "$TMP" > /dev/null
printf '%s' $'## Verification\n\n<!-- soleur:followthrough script=scripts/followthroughs/ok-1234.sh earliest=2026-05-22T00:00:00Z -->\n' > "$TMP/body.md"
INPUT=$(make_input "gh issue create --label follow-through --title t --body-file $TMP/body.md" "$TMP")
run "T17b: the SAME body unfenced — pass (the fence branch narrows, not denies-everything)" "$INPUT"
assert_pass
rm -rf "$TMP"

# === T17c: a body with NO directive at all keeps the ORIGINAL deny reason. The fence branch
# must not swallow the case it was carved out of. ===
TMP=$(mktemp -d)
make_work_dir "$TMP" > /dev/null
printf '%s' $'## Verification\n\nNothing here.\n' > "$TMP/body.md"
INPUT=$(make_input "gh issue create --label follow-through --title t --body-file $TMP/body.md" "$TMP")
run "T17c: no directive at all — deny still names the MISSING directive, not a fence" "$INPUT"
assert_deny "requires a"
rm -rf "$TMP"

# === T17d (DISPATCH): with the fence branch reverted in a copy of the hook, the fenced body
# falls back to the generic "script= is empty" message. The branch is the mechanism. ===
TMP=$(mktemp -d)
make_work_dir "$TMP" > /dev/null
# The mutant must live BESIDE the real hook: the hook resolves `lib/incidents.sh` relative to
# its own directory, so a copy in a mktemp dir dies at source time and the row would measure
# that, not the branch. Removed in the same block.
MUT="$(dirname "$HOOK")/.tmp-hook-no-fence-branch-$$.sh"
# Anchored on the CURRENT comment. When #7490's review rewrote this block from two arms to
# three, the old anchor stopped matching and the row reported "mutation did not land" — the
# landing assertion doing its job. Strip from the fence-branch preamble through the fenced
# arm's closing `fi`, leaving the generic script=-is-empty deny as the only outcome.
awk '/# THREE WAYS TO ARRIVE HERE, AND THEY NEED DIFFERENT ADVICE/{skip=1} skip && /^  fi$/{n++; if (n==3) {skip=0}; next} skip{next} {print}' "$HOOK" > "$MUT"
chmod +x "$MUT"
TOTAL=$((TOTAL + 1))
if diff -q "$HOOK" "$MUT" >/dev/null 2>&1; then
  echo "[T$TOTAL] T17d mutation did NOT land — the fence branch is not where this row mutates"
  FAIL=$((FAIL + 1))
elif grep -q 'CODE FENCE' "$MUT"; then
  echo "[T$TOTAL] T17d mutation left the fence reason behind — the row would be vacuous"
  FAIL=$((FAIL + 1))
else
  printf '%s' "$FENCED_BODY" > "$TMP/body.md"
  MUT_OUT=$(printf '%s' "$(make_input "gh issue create --label follow-through --title t --body-file $TMP/body.md" "$TMP")" | "$MUT" 2>&1 || true)
  if printf '%s' "$MUT_OUT" | grep -q 'script=. is empty'; then
    echo "[T$TOTAL] T17d with the fence branch reverted, the fenced body falls back to the generic reason"
    PASS=$((PASS + 1))
  else
    echo "[T$TOTAL] T17d FAIL: expected the generic script=-is-empty reason from the mutant, got: $(printf '%s' "$MUT_OUT" | head -c 200)"
    FAIL=$((FAIL + 1))
  fi
fi
rm -f "$MUT"
rm -rf "$TMP"

# === T17e/f/g (#7490 review): the parser must AGREE WITH THE CONSUMER on every shape, not
# just the one the retired ship template emitted. Measured before the fix, all three of these
# PASSED this gate while `scripts/sweep-followthroughs.sh` refused to honour them — the create
# gate green-lighting exactly the dead-tracker state it exists to prevent. The third is the
# original #7490 bug class, still live, and it is the one the ship template's own list
# indentation invites. ===
ft_shape_case() {  # ft_shape_case <label> <body-printf-fmt> <expect-substring>
  local label="$1" fmt="$2" expect="$3" TMP
  TMP=$(mktemp -d)
  make_work_dir "$TMP" > /dev/null
  # shellcheck disable=SC2059
  printf "$fmt" > "$TMP/body.md"
  local INPUT; INPUT=$(make_input "gh issue create --label follow-through --title t --body-file $TMP/body.md" "$TMP")
  run "$label" "$INPUT"
  assert_deny "$expect"
  rm -rf "$TMP"
}
ft_shape_case "T17e (#7490): a ~~~ fence is still a fence — deny names the fence" \
  '## Verification\n\n~~~html\n<!-- soleur:followthrough script=scripts/followthroughs/ok-1234.sh earliest=2026-05-22T00:00:00Z -->\n~~~\n' \
  "CODE FENCE"
ft_shape_case "T17f (#7490): a 3-space-indented fence is still a fence — deny names the fence" \
  '## Verification\n\n   ```html\n<!-- soleur:followthrough script=scripts/followthroughs/ok-1234.sh earliest=2026-05-22T00:00:00Z -->\n   ```\n' \
  "CODE FENCE"
ft_shape_case "T17g (#7490): an INDENTED unfenced directive — deny names the indentation, not a fence" \
  '## Verification\n\n  <!-- soleur:followthrough script=scripts/followthroughs/ok-1234.sh earliest=2026-05-22T00:00:00Z -->\n' \
  "INDENTED"

# === T17h: the zero-space spelling `<!--soleur:` is what the CONSUMER honours (` *`), so the
# gate must too — the mirror of the soak gate's G5-4. A false denial here blocks a legitimate
# tracker at creation time. ===
TMP=$(mktemp -d)
make_work_dir "$TMP" > /dev/null
printf '%s' $'## Verification\n\n<!--soleur:followthrough script=scripts/followthroughs/ok-1234.sh earliest=2026-05-22T00:00:00Z -->\n' > "$TMP/body.md"
INPUT=$(make_input "gh issue create --label follow-through --title t --body-file $TMP/body.md" "$TMP")
run "T17h: zero spaces after <!-- — pass (the consumer honours it, so the gate must)" "$INPUT"
assert_pass
rm -rf "$TMP"

# === Summary ===
# INSTRUMENT SELF-TEST -- drives BOTH assert helpers through their pass AND fail branches and
# requires every observable to move. The accounting identity and the floor below are computed
# from `TOTAL`, which `run()` increments BEFORE the hook's output is examined and independently
# of any verdict -- so both are satisfied with every deny assertion disarmed. Measured
# 2026-09-18: `assert_deny() { PASS=$((PASS+1)); return 0; }` -- one function, silencing 14 of
# 24 cases including EVERY row #7490 added (T17, T17c, T17e, T17f, T17g) -- reported
# `=== Results: 24/24 passed, 0 failed ===`, exit 0. Note also that `guard-vacuity-floor.test.sh`
# promotes this file on the stated grounds that its floor reads "an independent count
# incremented at the assert call sites"; `TOTAL` is incremented at the run() call sites, so that
# rationale described a suite shape this file did not have until this block existed.
_p=$PASS _f=$FAIL _t=$TOTAL _n=${#FAILURES[@]} _sc=$_case
if (( _n > 0 )); then _saved=("${FAILURES[@]}"); else _saved=(); fi
_case="self-test probe"
HOOK_RC=0 HOOK_OUT="" ; assert_pass                      # pass branch of assert_pass
HOOK_RC=1 HOOK_OUT="" ; assert_pass                      # fail branch of assert_pass
HOOK_RC=0 HOOK_OUT='{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"probe"}}'
assert_deny "probe"                                      # pass branch of assert_deny
assert_deny "a-substring-that-is-not-there"              # fail branch of assert_deny
if (( PASS != _p + 2 || FAIL != _f + 2 || ${#FAILURES[@]} != _n + 2 )); then
  printf '[FATAL] instrument self-test: an assert helper did not move every observable (PASS %d->%d, FAIL %d->%d, ledger %d->%d)\n' \
    "$_p" "$PASS" "$_f" "$FAIL" "$_n" "${#FAILURES[@]}" >&2
  exit 1
fi
PASS=$_p; FAIL=$_f; TOTAL=$_t; _case=$_sc
if (( _n > 0 )); then FAILURES=("${_saved[@]}"); else FAILURES=(); fi

printf '\n=== Results: %d/%d passed, %d failed ===\n' "$PASS" "$TOTAL" "$FAIL"

# === ADR-193 accounting + floor. This suite had NEITHER: PASS+FAIL was never reconciled
# against TOTAL, so a case whose `run` fired but whose assert helper was never reached
# vanished silently, and no floor existed at all, so deleting cases summarised green. Both are
# reported with printf + exit 1 DIRECTLY, never through the counters they police. ===
if [[ $((PASS + FAIL)) -ne "$TOTAL" ]]; then
  printf '[FATAL] accounting: PASS+FAIL (%d) != TOTAL (%d) — a case ran without recording a verdict\n' \
    "$((PASS + FAIL))" "$TOTAL" >&2
  exit 1
fi
MIN_ASSERTIONS=24
if [[ "$TOTAL" -lt "$MIN_ASSERTIONS" ]]; then
  printf '[FATAL] only %d cases ran; floor is %d — the suite was gutted\n' "$TOTAL" "$MIN_ASSERTIONS" >&2
  exit 1
fi

# Verdict reads the append-only LEDGER as well as the counter: a FAIL increment redirected to
# PASS still leaves FAILURES populated, and the run still reds.
[[ "$FAIL" -eq 0 && "${#FAILURES[@]}" -eq 0 ]] || { printf 'FAILED: %d (ledger holds %d)\n' "$FAIL" "${#FAILURES[@]}" >&2; exit 1; }
