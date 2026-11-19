#!/usr/bin/env bash
#
# Tests for plugins/soleur/scripts/retry-budget-ruling.sh.
# Written from the plan's Phase 1 contract and Guard 1. The script is the
# only verb parser: identity, then ruling_spawn: used, then empty history,
# then at most 64 stdin bytes.
#
# Run: bash plugins/soleur/scripts/retry-budget-ruling.test.sh

set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_TEMPLATE_DIR GIT_EXEC_PATH 2>/dev/null || true
unset SOLEUR_DISABLE_SESSION_STATE SOLEUR_SESSION_STATE_ROOT 2>/dev/null || true

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$DIR/retry-budget-ruling.sh"

TMP="$(mktemp -d -t ruling.XXXXXXXX)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
[[ "$TMP" == /* ]] || { echo "FATAL: TMP is not absolute: $TMP" >&2; exit 2; }

# shellcheck source=../test/test-helpers.sh
source "$DIR/../test/test-helpers.sh" || { echo "FATAL: could not source test-helpers.sh" >&2; exit 2; }
set +e -uo pipefail
assert_fixture_dir "$TMP"

BRANCH="feat-12526-retry-budget-arbitration"
TOP="$TMP/repo"
SPEC="$TOP/knowledge-base/project/specs/$BRANCH"
LEDGER="$SPEC/session-state.md"
HIST="$TMP/history.txt"
CHILD="$TMP/child-session.md"
COMMON="$TOP/.git"
EVIDENCE="evidence-sentinel-not-written"
STDIN_PATH=""
OUT=""
ERR=""
RC=0

assert_not_contains() {
  local haystack="$1" needle="$2" msg="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "  PASS: $msg"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg"
    echo "    expected NOT to contain: '$needle'"
    FAIL=$((FAIL + 1))
  fi
}

fresh_ledger() {
  assert_fixture_dir "$SPEC"
  mkdir -p "$SPEC"
  printf 'session: open\ncapped=ci_cycles\n' >"$LEDGER"
  printf 'attempt one\n' >"$HIST"
  printf 'child\n' >"$CHILD"
}

run_case() {
  local errf="$TMP/last.err"
  OUT=""
  ERR=""
  RC=0
  assert_fixture_dir "$TMP"
  : >"$errf"
  if [[ ! -f "$SUT" ]]; then
    RC=127
    ERR="missing sut"
    return 0
  fi
  if [[ -n "$STDIN_PATH" ]]; then
    OUT=$(bash "$SUT" "$@" <"$STDIN_PATH" 2>"$errf") || RC=$?
  else
    OUT=$(bash "$SUT" "$@" </dev/null 2>"$errf") || RC=$?
  fi
  ERR=$(cat "$errf" 2>/dev/null || true)
}

# Identity-matching flags. History and phase are added by the caller.
id_flags() {
  ID_FLAGS=(
    --toplevel "$TOP"
    --branch "$BRANCH"
    --git-common-dir "$COMMON"
    --ledger "$LEDGER"
    --child-session "$CHILD"
    --evidence "$EVIDENCE"
  )
}

write_stdin() {
  local dest="$TMP/stdin.bin"
  assert_fixture_dir "$TMP"
  STDIN_PATH="$dest"
  printf '%s' "$1" >"$dest"
}

section_count() {
  grep -c '^## Retry budget ruling$' "$1" 2>/dev/null || true
}

file_digest() {
  sha256sum "$1" | awk '{print $1}'
}

assert_spawn_section() {
  local verb="$1" reason="$2" phase="$3" spawn="$4"
  local body
  body=$(cat "$LEDGER")
  assert_contains "$body" "## Retry budget ruling" "ruling section heading ($verb/$reason)"
  assert_contains "$body" "branch: $BRANCH" "section records branch"
  assert_contains "$body" "toplevel: $TOP" "section records toplevel"
  assert_contains "$body" "git-common-dir: $COMMON" "section records git common dir"
  assert_contains "$body" "verb: $verb" "section records verb $verb"
  assert_contains "$body" "reason: $reason" "section records reason $reason"
  assert_contains "$body" "child-session: $CHILD" "section records the child-session path"
  assert_contains "$body" "session: open" "preamble survived the append"
  assert_contains "$body" "capped=ci_cycles" "fixture capped= line is unchanged"
  assert_not_contains "$body" "ruling_grant" "section does not contain ruling_grant"
  assert_not_contains "$body" "$EVIDENCE" "evidence argument is not written"
  if [[ "$spawn" == yes ]]; then
    assert_contains "$body" "ruling_spawn: used" "spawn bit is set"
  else
    assert_not_contains "$body" "ruling_spawn: used" "empty history does not set the spawn bit"
  fi
  if [[ -n "$phase" ]]; then
    assert_contains "$body" "phase: $phase" "section records phase $phase"
  else
    if grep -qx 'phase:' "$LEDGER"; then
      echo "  PASS: phase field is empty"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: phase field is empty"
      FAIL=$((FAIL + 1))
    fi
  fi
}

echo "=== probe ==="
run_case --probe --ledger "$TMP/probe-must-not-create.md" --evidence "$EVIDENCE"
assert_eq "0" "$RC" "probe exits 0"
assert_eq "ok" "$OUT" "probe prints ok"
assert_file_not_exists "$TMP/probe-must-not-create.md" "probe does not create a ledger"

echo "=== identity ==="
fresh_ledger
before=$(file_digest "$LEDGER")
write_stdin "continue"
run_case --toplevel "$TMP/elsewhere" --branch "$BRANCH" --git-common-dir "$COMMON" --ledger "$LEDGER" --history "$HIST" --evidence "$EVIDENCE"
assert_eq "2" "$RC" "identity mismatch exits 2"
assert_eq $'SOLEUR_RETRY_BUDGET_RULING verb=fail reason=identity\nfail identity' "$OUT" "identity prints the verdict and the plain line"
assert_eq "$before" "$(file_digest "$LEDGER")" "identity mismatch does not append"
assert_not_contains "$(cat "$LEDGER")" "ruling_spawn: used" "identity mismatch does not set the spawn bit"
STDIN_PATH=""

run_case --branch "$BRANCH" --git-common-dir "$COMMON" --ledger "$LEDGER"
assert_eq "2" "$RC" "missing toplevel is identity"
assert_eq $'SOLEUR_RETRY_BUDGET_RULING verb=fail reason=identity\nfail identity' "$OUT" "missing toplevel plain line"

other="$TMP/repo/knowledge-base/project/specs/other-branch/session-state.md"
assert_fixture_dir "$TMP/repo/knowledge-base/project/specs/other-branch"
mkdir -p "$(dirname "$other")"
printf 'keep\n' >"$other"
before=$(file_digest "$other")
write_stdin "continue"
run_case --toplevel "$TOP" --branch "$BRANCH" --git-common-dir "$COMMON" --ledger "$other" --history "$HIST"
assert_eq "2" "$RC" "parent basename mismatch exits 2"
assert_eq "$before" "$(file_digest "$other")" "basename mismatch writes nothing"
STDIN_PATH=""

prefix="$TMP/repo2/knowledge-base/project/specs/$BRANCH/session-state.md"
assert_fixture_dir "$TMP/repo2/knowledge-base/project/specs/$BRANCH"
mkdir -p "$(dirname "$prefix")"
printf 'keep\n' >"$prefix"
before=$(file_digest "$prefix")
run_case --toplevel "$TOP" --branch "$BRANCH" --git-common-dir "$COMMON" --ledger "$prefix" --history "$HIST"
assert_eq "2" "$RC" "ledger outside toplevel exits 2"
assert_eq "$before" "$(file_digest "$prefix")" "outside toplevel writes nothing"
assert_file_not_exists "$TMP/no-parent/specs/$BRANCH/session-state.md" "identity does not create a missing tree"
run_case --toplevel "$TOP" --branch "$BRANCH" --git-common-dir "$COMMON" --ledger "$TMP/no-parent/specs/$BRANCH/session-state.md"
assert_eq "2" "$RC" "missing parent directory is identity"
assert_file_not_exists "$TMP/no-parent/specs/$BRANCH/session-state.md" "missing parent directory is not created"

echo "=== spent before empty history and before stdin ==="
fresh_ledger
printf '\nruling_spawn: used\n' >>"$LEDGER"
before=$(file_digest "$LEDGER")
write_stdin "continue"
run_case --toplevel "$TOP" --branch "$BRANCH" --git-common-dir "$COMMON" --ledger "$LEDGER" --evidence "$EVIDENCE"
assert_eq "2" "$RC" "spent exits 2 when history is omitted"
assert_eq "SOLEUR_RETRY_BUDGET_RULING verb=fail reason=spent" "$OUT" "spent prints the verdict line only"
assert_eq "$before" "$(file_digest "$LEDGER")" "spent with empty history appends nothing"
STDIN_PATH=""

fresh_ledger
printf '\nruling_spawn: used\n' >>"$LEDGER"
before=$(file_digest "$LEDGER")
write_stdin "continue"
id_flags
run_case "${ID_FLAGS[@]}" --history "$HIST" --phase work
assert_eq "2" "$RC" "spent exits 2 when stdin is continue"
assert_eq "SOLEUR_RETRY_BUDGET_RULING verb=fail reason=spent" "$OUT" "spent continue has no plain line"
assert_eq "$before" "$(file_digest "$LEDGER")" "spent continue appends nothing"
if [[ "$(section_count "$LEDGER")" == "0" ]]; then
  echo "  PASS: spent file has no ruling heading"
  PASS=$((PASS + 1))
else
  echo "  FAIL: spent file has no ruling heading (count=$(section_count "$LEDGER"))"
  FAIL=$((FAIL + 1))
fi
STDIN_PATH=""

echo "=== empty history ==="
fresh_ledger
rm -f "$LEDGER"
write_stdin "continue"
id_flags
run_case "${ID_FLAGS[@]}" --history "$HIST" --phase work
assert_eq "2" "$RC" "missing ledger is empty-history even when stdin is continue"
assert_eq $'SOLEUR_RETRY_BUDGET_RULING verb=fail reason=empty-history\nfail empty-history' "$OUT" "missing ledger plain line"
assert_file_exists "$LEDGER" "missing ledger still receives one section"
assert_not_contains "$(cat "$LEDGER")" "ruling_spawn: used" "missing ledger section has no spawn bit"
assert_not_contains "$(cat "$LEDGER")" "ruling_grant" "missing ledger section has no ruling_grant"
assert_not_contains "$(cat "$LEDGER")" "$EVIDENCE" "missing ledger does not store evidence"
STDIN_PATH=""

fresh_ledger
: >"$HIST"
write_stdin "continue"
id_flags
run_case "${ID_FLAGS[@]}" --history "$HIST" --phase work
assert_eq "2" "$RC" "zero-byte history is empty-history"
assert_eq $'SOLEUR_RETRY_BUDGET_RULING verb=fail reason=empty-history\nfail empty-history' "$OUT" "zero-byte history plain line"
assert_spawn_section "fail" "empty-history" "work" no
assert_eq "1" "$(section_count "$LEDGER")" "empty history appends one section"
STDIN_PATH=""

fresh_ledger
id_flags
run_case "${ID_FLAGS[@]}" --phase work
assert_eq "2" "$RC" "omitted --history is empty-history"
assert_not_contains "$(cat "$LEDGER")" "ruling_spawn: used" "omitted history does not set the spawn bit"

fresh_ledger
id_flags
run_case "${ID_FLAGS[@]}" --history "$TMP/missing-history.txt" --phase work
assert_eq "2" "$RC" "missing history file is empty-history"
assert_eq "SOLEUR_RETRY_BUDGET_RULING verb=fail reason=empty-history" "$(printf '%s' "$OUT" | head -n 1)" "missing history file verdict"

echo "=== accept continue and allow-listed goto ==="
fresh_ledger
side="$TMP/capped-side"
printf 'capped=ci_cycles\n' >"$side"
write_stdin $'continue\n'
id_flags
run_case "${ID_FLAGS[@]}" --history "$HIST" --phase work
assert_eq "0" "$RC" "continue with one trailing LF exits 0"
assert_eq "SOLEUR_RETRY_BUDGET_RULING verb=continue reason=ok" "$OUT" "continue verdict"
assert_spawn_section "continue" "ok" "work" yes
assert_eq "capped=ci_cycles" "$(cat "$side")" "continue does not clear a side capped= file"
if [[ -f "$SUT" ]] && grep -F 'pipeline-tally.sh' "$SUT" >/dev/null 2>&1; then
  echo "  FAIL: script does not invoke pipeline-tally.sh"
  FAIL=$((FAIL + 1))
elif [[ ! -f "$SUT" ]]; then
  echo "  FAIL: script does not invoke pipeline-tally.sh (script missing)"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: script does not invoke pipeline-tally.sh"
  PASS=$((PASS + 1))
fi
if [[ -f "$SUT" ]] && grep -F 'HephaestusNG' "$SUT" >/dev/null 2>&1; then
  echo "  FAIL: script does not name the compared peer"
  FAIL=$((FAIL + 1))
elif [[ ! -f "$SUT" ]]; then
  echo "  FAIL: script does not name the compared peer (script missing)"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: script does not name the compared peer"
  PASS=$((PASS + 1))
fi
HOOK_FILE="$DIR/../hooks/stop-hook.sh"
if [[ -f "$HOOK_FILE" ]] && grep -F 'HephaestusNG' "$HOOK_FILE" >/dev/null 2>&1; then
  echo "  FAIL: stop-hook does not name the compared peer"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: stop-hook does not name the compared peer"
  PASS=$((PASS + 1))
fi
STDIN_PATH=""

for phase in plan work review qa test-fix-loop; do
  fresh_ledger
  write_stdin "goto ${phase}"$'\n'
  id_flags
  run_case "${ID_FLAGS[@]}" --history "$HIST" --phase ship
  assert_eq "0" "$RC" "goto $phase exits 0"
  assert_eq "SOLEUR_RETRY_BUDGET_RULING verb=goto reason=ok phase=${phase}" "$OUT" "goto $phase verdict"
  assert_spawn_section "goto" "ok" "$phase" yes
  assert_not_contains "$(cat "$LEDGER")" "phase: ship" "goto does not record the unused phase flag"
  assert_not_contains "$(cat "$LEDGER")" "retry_budget_grant" "goto does not write the ralph grant"
done
STDIN_PATH=""

echo "=== fail, empty stdin, unparseable ==="
fresh_ledger
write_stdin "fail"
id_flags
run_case "${ID_FLAGS[@]}" --history "$HIST" --phase work
assert_eq "2" "$RC" "explicit fail exits 2"
assert_eq $'SOLEUR_RETRY_BUDGET_RULING verb=fail reason=fail\nfail fail' "$OUT" "explicit fail plain line"
assert_spawn_section "fail" "fail" "work" yes
STDIN_PATH=""

fresh_ledger
id_flags
run_case "${ID_FLAGS[@]}" --history "$HIST" --phase work
assert_eq "2" "$RC" "empty stdin exits 2"
assert_eq $'SOLEUR_RETRY_BUDGET_RULING verb=fail reason=empty\nfail empty' "$OUT" "empty stdin plain line"
assert_spawn_section "fail" "empty" "work" yes
STDIN_PATH=""

unparseable_cases() {
  local label="$1" bytes="$2"
  fresh_ledger
  write_stdin "$bytes"
  id_flags
  run_case "${ID_FLAGS[@]}" --history "$HIST" --phase work
  assert_eq "2" "$RC" "$label exits 2"
  assert_eq $'SOLEUR_RETRY_BUDGET_RULING verb=fail reason=unparseable\nfail unparseable' "$OUT" "$label verdict"
  assert_spawn_section "fail" "unparseable" "work" yes
}

unparseable_cases "continue please" "continue please"
unparseable_cases "second line" $'continue\ngoto plan\n'
unparseable_cases "goto ship" $'goto ship\n'
unparseable_cases "goto merge" "goto merge"
unparseable_cases "quoted continue" '"continue"'
unparseable_cases "leading space" " continue"
unparseable_cases "double space goto" "goto  plan"
unparseable_cases "CR" $'continue\r\n'
unparseable_cases "byte after delimiter" $'continue\nX'
STDIN_PATH=""

# NUL is not a bash string. Write the byte with python.
fresh_ledger
assert_fixture_dir "$TMP"
python3 -c 'import sys; sys.stdout.buffer.write(b"continue\x00")' >"$TMP/stdin.bin"
STDIN_PATH="$TMP/stdin.bin"
id_flags
run_case "${ID_FLAGS[@]}" --history "$HIST" --phase work
assert_eq "2" "$RC" "NUL exits 2"
assert_eq $'SOLEUR_RETRY_BUDGET_RULING verb=fail reason=unparseable\nfail unparseable' "$OUT" "NUL is unparseable"
assert_spawn_section "fail" "unparseable" "work" yes
STDIN_PATH=""

echo "=== 64-byte stop ==="
flood_case() {
  local label="$1"
  local py="$2"
  local fifo="$TMP/flood.fifo"
  local errf="$TMP/flood.err"
  local wpid=""
  fresh_ledger
  assert_fixture_dir "$TMP"
  rm -f "$fifo"
  mkfifo "$fifo"
  {
    python3 -c "$py" || true
    sleep 30
  } >"$fifo" 2>/dev/null &
  wpid=$!
  OUT=""
  RC=0
  OUT=$(timeout 2 bash "$SUT" --toplevel "$TOP" --branch "$BRANCH" --git-common-dir "$COMMON" --ledger "$LEDGER" --history "$HIST" --child-session "$CHILD" --phase work --evidence "$EVIDENCE" <"$fifo" 2>"$errf") || RC=$?
  kill "$wpid" 2>/dev/null || true
  wait "$wpid" 2>/dev/null || true
  rm -f "$fifo"
  assert_eq "2" "$RC" "$label stops at 64 bytes (not timeout 124)"
  assert_eq $'SOLEUR_RETRY_BUDGET_RULING verb=fail reason=unparseable\nfail unparseable' "$OUT" "$label is unparseable, not empty"
  assert_spawn_section "fail" "unparseable" "work" yes
}

flood_case "256 KB newlines" 'import sys; sys.stdout.buffer.write(b"\n"*64)'
flood_case "256 KB spaces" 'import sys; sys.stdout.buffer.write(b" "*64)'
flood_case "URL-scheme flood" 'import sys; sys.stdout.buffer.write(b"https://"*8)'
flood_case "unterminated comment" 'import sys; sys.stdout.buffer.write(b"/*" + b"*"*62)'

echo "=== second call is spent ==="
fresh_ledger
write_stdin "continue"
id_flags
run_case "${ID_FLAGS[@]}" --history "$HIST" --phase work
assert_eq "0" "$RC" "first continue exits 0"
before=$(file_digest "$LEDGER")
write_stdin "continue"
run_case "${ID_FLAGS[@]}" --history "$HIST" --phase work
assert_eq "2" "$RC" "second continue is spent"
assert_eq "SOLEUR_RETRY_BUDGET_RULING verb=fail reason=spent" "$OUT" "second continue verdict only"
assert_eq "$before" "$(file_digest "$LEDGER")" "second continue appends nothing"
assert_eq "1" "$(section_count "$LEDGER")" "one ruling section after the second call"
STDIN_PATH=""

echo "=== not-capped before history ==="
fresh_ledger
write_stdin "continue"
id_flags
run_case "${ID_FLAGS[@]}" --not-capped --history "$HIST" --phase work
assert_eq "2" "$RC" "not-capped exits 2"
assert_eq $'SOLEUR_RETRY_BUDGET_RULING verb=fail reason=not-capped\nfail not-capped' "$OUT" "not-capped plain line"
assert_spawn_section "fail" "not-capped" "work" no
assert_not_contains "$(cat "$LEDGER")" "empty-history" "not-capped is not labeled empty-history"
assert_eq "1" "$(section_count "$LEDGER")" "not-capped appends one section"
STDIN_PATH=""

fresh_ledger
printf '\nruling_spawn: used\n' >>"$LEDGER"
before=$(file_digest "$LEDGER")
write_stdin "continue"
id_flags
run_case "${ID_FLAGS[@]}" --not-capped --history "$HIST" --phase work
assert_eq "2" "$RC" "spent wins over not-capped"
assert_eq "SOLEUR_RETRY_BUDGET_RULING verb=fail reason=spent" "$OUT" "spent not-capped prints the verdict only"
assert_eq "$before" "$(file_digest "$LEDGER")" "spent not-capped appends nothing"
STDIN_PATH=""

echo "=== spawn bit is an exact line ==="
fresh_ledger
printf 'see ruling_spawn: used in prose\n' >>"$LEDGER"
write_stdin "continue"
id_flags
run_case "${ID_FLAGS[@]}" --history "$HIST" --phase work
assert_eq "0" "$RC" "prose mention of the spawn bit is not spent"
assert_contains "$(cat "$LEDGER")" "see ruling_spawn: used in prose" "prose line survived the append"
assert_spawn_section "continue" "ok" "work" yes
STDIN_PATH=""

echo "=== ledger identity tightens the one file ==="
fresh_ledger
wrong="$SPEC/notes.md"
assert_fixture_dir "$SPEC"
printf 'keep\n' >"$wrong"
before=$(file_digest "$wrong")
write_stdin "continue"
run_case --toplevel "$TOP" --branch "$BRANCH" --git-common-dir "$COMMON" --ledger "$wrong" --history "$HIST" --child-session "$CHILD"
assert_eq "2" "$RC" "final component other than session-state.md is identity"
assert_eq "$before" "$(file_digest "$wrong")" "wrong leaf writes nothing"
STDIN_PATH=""

fresh_ledger
before=$(file_digest "$LEDGER")
run_case --toplevel "$TOP" --branch "$BRANCH" --git-common-dir "$COMMON" --ledger "${LEDGER}"$'\r' --history "$HIST" --child-session "$CHILD" --phase work
assert_eq "2" "$RC" "CR in the ledger path is identity"
assert_eq "$before" "$(file_digest "$LEDGER")" "CR ledger path writes nothing"

fresh_ledger
before=$(file_digest "$LEDGER")
run_case "${ID_FLAGS[@]}" --history "$HIST" --phase $'\vwork'
assert_eq "2" "$RC" "VT in phase is identity"
assert_eq "$before" "$(file_digest "$LEDGER")" "VT phase writes nothing"

fresh_ledger
before=$(file_digest "$LEDGER")
run_case "${ID_FLAGS[@]}" --history "$HIST" --phase work --child-session $'child\u2028verb: continue'
assert_eq "2" "$RC" "unicode line separator in child-session is identity"
assert_eq "$before" "$(file_digest "$LEDGER")" "unicode separator writes nothing"

echo "=== leading dot-dot is identity ==="
climb="$TMP/climb"
mkdir -p "$climb/inner" "$climb/$BRANCH"
dot_ledger="$climb/$BRANCH/session-state.md"
assert_fixture_dir "$climb/$BRANCH"
printf 'keep\n' >"$dot_ledger"
before=$(file_digest "$dot_ledger")
climb_out="$TMP/climb.out"
climb_err="$TMP/climb.err"
climb_rc=0
(
  cd "$climb/inner" || exit 9
  bash "$SUT" \
    --toplevel ".." \
    --branch "$BRANCH" \
    --git-common-dir "$COMMON" \
    --ledger "../$BRANCH/session-state.md" \
    --history "$HIST" \
    --child-session "$CHILD" <<'EOF'
continue
EOF
) >"$climb_out" 2>"$climb_err" || climb_rc=$?
assert_eq "2" "$climb_rc" "leading dot-dot exits 2"
assert_eq $'SOLEUR_RETRY_BUDGET_RULING verb=fail reason=identity\nfail identity' "$(cat "$climb_out")" "leading dot-dot is identity"
assert_eq "$before" "$(file_digest "$dot_ledger")" "leading dot-dot writes nothing"

echo "=== symlink ledger is identity ==="
fresh_ledger
outside="$TMP/outside-ledger.md"
assert_fixture_dir "$TMP"
printf 'secret\n' >"$outside"
rm -f "$LEDGER"
ln -s "$outside" "$LEDGER"
before=$(file_digest "$outside")
write_stdin "continue"
id_flags
run_case "${ID_FLAGS[@]}" --history "$HIST" --phase work
assert_eq "2" "$RC" "symlink ledger exits 2"
assert_eq "$before" "$(file_digest "$outside")" "symlink target is not written"
rm -f "$LEDGER"
STDIN_PATH=""

fresh_ledger
rm -rf "$SPEC"
mkdir -p "$TMP/escaped/$BRANCH"
ln -s "$TMP/escaped/$BRANCH" "$SPEC"
printf 'secret\n' >"$TMP/escaped/$BRANCH/session-state.md"
before=$(file_digest "$TMP/escaped/$BRANCH/session-state.md")
write_stdin "continue"
id_flags
run_case "${ID_FLAGS[@]}" --history "$HIST" --phase work
assert_eq "2" "$RC" "symlinked spec directory exits 2"
assert_eq "$before" "$(file_digest "$TMP/escaped/$BRANCH/session-state.md")" "escaped ledger is not written"
rm -rf "$SPEC"
mkdir -p "$SPEC"
STDIN_PATH=""

echo "=== locked append keeps one spawn bit ==="
fresh_ledger
id_flags
race_a="$TMP/race-a.out"
race_b="$TMP/race-b.out"
bash "$SUT" "${ID_FLAGS[@]}" --history "$HIST" --phase work >"$race_a" <<'EOF' &
continue
EOF
race_pa=$!
bash "$SUT" "${ID_FLAGS[@]}" --history "$HIST" --phase work >"$race_b" <<'EOF' &
continue
EOF
race_pb=$!
wait "$race_pa" || true
wait "$race_pb" || true
race_combo="$(cat "$race_a" "$race_b")"
assert_eq "1" "$(section_count "$LEDGER")" "parallel continues leave one ruling section"
assert_contains "$race_combo" "verb=continue reason=ok" "one parallel call continues"
assert_contains "$race_combo" "verb=fail reason=spent" "the other parallel call is spent"

echo "=== reference matches the ruling ==="
REF="$DIR/../skills/one-shot/references/retry-budget-ruling.md"
SKILL="$DIR/../skills/one-shot/SKILL.md"
assert_contains "$(cat "$REF")" "plugins/soleur/scripts/retry-budget-ruling.sh" "reference names the ruling script"
assert_contains "$(cat "$REF")" "Do not write \`retry_budget_grant: 1\`" "reference tells the parent not to write the grant"
assert_not_contains "$(cat "$REF")" "Write the unquoted line" "reference does not instruct writing the grant line"
assert_contains "$(cat "$REF")" "reason=not-capped" "reference names the not-capped halt"
assert_contains "$(cat "$REF")" "phase=" "reference tells the parent to read phase="
cue_count=$(grep -c -F 'Read references/retry-budget-ruling.md.' "$SKILL" || true)
assert_eq "2" "$cue_count" "one-shot carries the ruling cue twice"

print_results 350
