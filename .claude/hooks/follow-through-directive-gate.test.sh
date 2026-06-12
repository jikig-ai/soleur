#!/usr/bin/env bash
# Fixture-based tests for follow-through-directive-gate.sh. Each test composes
# a PreToolUse(Bash) input shape, pipes it to the hook, asserts the JSON
# permissionDecision matches expectation.
#
# Isolation pattern matches ship-unpushed-commits-gate.test.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/follow-through-directive-gate.sh"

PASS=0
FAIL=0
TOTAL=0

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
    FAIL=$((FAIL + 1))
    return
  fi
  if [[ -n "$HOOK_OUT" ]]; then
    # Hook fail-open path: silent exit 0
    echo "       FAIL: expected silent fail-open, got output"
    FAIL=$((FAIL + 1))
    return
  fi
  PASS=$((PASS + 1))
}

assert_deny() {
  local expected_substring="$1"
  if [[ "$HOOK_RC" -ne 0 ]]; then
    echo "       FAIL: expected exit 0 (deny JSON returned via stdout), got $HOOK_RC"
    FAIL=$((FAIL + 1))
    return
  fi
  if [[ -z "$HOOK_OUT" ]]; then
    echo "       FAIL: expected deny JSON, got empty output"
    FAIL=$((FAIL + 1))
    return
  fi
  local decision
  decision=$(printf '%s' "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null)
  if [[ "$decision" != "deny" ]]; then
    echo "       FAIL: expected permissionDecision=deny, got '$decision'"
    FAIL=$((FAIL + 1))
    return
  fi
  if ! printf '%s' "$HOOK_OUT" | grep -q "$expected_substring"; then
    echo "       FAIL: deny reason missing substring '$expected_substring'"
    FAIL=$((FAIL + 1))
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

# === Summary ===
printf '\n=== Results: %d/%d passed, %d failed ===\n' "$PASS" "$TOTAL" "$FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
