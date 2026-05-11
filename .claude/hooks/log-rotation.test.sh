#!/usr/bin/env bash
# Tests for .claude/hooks/lib/log-rotation.sh.
#
# Verifies the per-write rotator helper under the conditions enumerated in
# plan 2026-05-10-feat-shared-log-rotation-primitive-plan.md Phase 4 (T1-T12).
#
# Run via:  bash .claude/hooks/log-rotation.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/lib/log-rotation.sh"

PASS=0
FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }

ROOTS=()
trap 'for r in "${ROOTS[@]}"; do rm -rf "$r"; done' EXIT

make_root() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/.claude"
  echo "$dir"
}

# Source helper in a subshell-safe way; each test sources fresh to avoid
# leaking state between cases.
source_helper() {
  # shellcheck source=/dev/null
  source "$HELPER"
}

# ------------------------------------------------------------------------
# Test 1: No rotation when below thresholds
# ------------------------------------------------------------------------
echo "Test 1: no rotation below thresholds"
ROOT=$(make_root); ROOTS+=("$ROOT")
ACTIVE="$ROOT/.claude/.test.jsonl"
printf 'small\n' > "$ACTIVE"
(
  source_helper
  rotate_if_needed "$ACTIVE"
)
if [[ ! -f "$ACTIVE" ]] || [[ "$(wc -c < "$ACTIVE")" -eq 0 ]]; then
  fail "active file truncated when below threshold"
elif compgen -G "$ROOT/.claude/.test-*" > /dev/null; then
  fail "archive created when below threshold"
else
  pass "no rotation, active intact, no archive"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Test 2: Rotates on size threshold
# ------------------------------------------------------------------------
echo "Test 2: rotates on size threshold"
ROOT=$(make_root); ROOTS+=("$ROOT")
ACTIVE="$ROOT/.claude/.test.jsonl"
# Create a 6 MB file
dd if=/dev/zero bs=1024 count=6144 2>/dev/null | tr '\0' 'x' > "$ACTIVE"
(
  source_helper
  rotate_if_needed "$ACTIVE"
)
SIZE_AFTER=$(wc -c < "$ACTIVE")
if [[ "$SIZE_AFTER" -ne 0 ]]; then
  fail "active file not truncated after rotation (size=$SIZE_AFTER)"
elif ! compgen -G "$ROOT/.claude/.test-*.jsonl.gz" > /dev/null; then
  fail "no .gz archive created"
else
  pass "rotated: active=0 bytes, archive.gz exists"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Test 3: Rotates on age threshold
# ------------------------------------------------------------------------
echo "Test 3: rotates on age threshold"
ROOT=$(make_root); ROOTS+=("$ROOT")
ACTIVE="$ROOT/.claude/.test.jsonl"
printf 'old line\n' > "$ACTIVE"
# Set mtime to 31 days ago. touch -d works on both GNU and uutils coreutils.
OLD_TIME=$(date -u -d '31 days ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v-31d '+%Y-%m-%dT%H:%M:%SZ')
touch -d "$OLD_TIME" "$ACTIVE"
(
  source_helper
  rotate_if_needed "$ACTIVE"
)
SIZE_AFTER=$(wc -c < "$ACTIVE")
if [[ "$SIZE_AFTER" -ne 0 ]]; then
  fail "active not truncated on age trigger (size=$SIZE_AFTER)"
elif ! compgen -G "$ROOT/.claude/.test-*.jsonl.gz" > /dev/null; then
  fail "no archive on age trigger"
else
  pass "age-triggered rotation: active=0, archive.gz exists"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Test 4: Configurable thresholds via env
# ------------------------------------------------------------------------
echo "Test 4: env-overridden size threshold"
ROOT=$(make_root); ROOTS+=("$ROOT")
ACTIVE="$ROOT/.claude/.test.jsonl"
# 2 KB file with 1 KB threshold
dd if=/dev/zero bs=1024 count=2 2>/dev/null | tr '\0' 'y' > "$ACTIVE"
(
  source_helper
  LOG_ROTATION_SIZE_BYTES=1024 rotate_if_needed "$ACTIVE"
)
if [[ "$(wc -c < "$ACTIVE")" -ne 0 ]]; then
  fail "env override not respected"
elif ! compgen -G "$ROOT/.claude/.test-*.jsonl.gz" > /dev/null; then
  fail "no archive after env-override rotation"
else
  pass "LOG_ROTATION_SIZE_BYTES=1024 triggered rotation"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Test 5: Copy failure leaves active intact (truncate gated on cat success)
# ------------------------------------------------------------------------
echo "Test 5: copy failure preserves active"
ROOT=$(make_root); ROOTS+=("$ROOT")
ACTIVE="$ROOT/.claude/.test.jsonl"
ARCHIVE_DIR="$ROOT/.claude"
dd if=/dev/zero bs=1024 count=6144 2>/dev/null | tr '\0' 'z' > "$ACTIVE"
ORIG_SIZE=$(wc -c < "$ACTIVE")
# Force cat-to-archive failure: make .claude read-only so the archive can't
# be created. Linux honors directory write permission; if running as root,
# this test passes vacuously — guard against that.
if [[ $(id -u) -eq 0 ]]; then
  pass "skipped under root (chmod 0500 ineffective)"
else
  chmod 0500 "$ARCHIVE_DIR"
  (
    source_helper
    rotate_if_needed "$ACTIVE"
  ) 2>/dev/null || true
  chmod 0700 "$ARCHIVE_DIR"
  POST_SIZE=$(wc -c < "$ACTIVE")
  if [[ "$POST_SIZE" -ne "$ORIG_SIZE" ]]; then
    fail "active file mutated despite copy failure (orig=$ORIG_SIZE, now=$POST_SIZE)"
  else
    pass "active file preserved when archive write fails"
  fi
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Test 6: Concurrent writers do not tear lines (gated rotation under flock)
# ------------------------------------------------------------------------
echo "Test 6: 100 concurrent writers + rotator"
ROOT=$(make_root); ROOTS+=("$ROOT")
ACTIVE="$ROOT/.claude/.test.jsonl"
: > "$ACTIVE"
# Pre-fill to push it just under the threshold so a concurrent rotation
# is plausible mid-burst.
dd if=/dev/zero bs=1024 count=4 2>/dev/null | tr '\0' 'q' > "$ACTIVE"

write_one() {
  local i=$1
  (
    # Each writer sources helper, calls rotate_if_needed, then appends
    # a line under flock — same pattern as the production hooks.
    # shellcheck source=/dev/null
    source "$HELPER"
    LOG_ROTATION_SIZE_BYTES=2048 rotate_if_needed "$ACTIVE"
    (
      flock -x 9
      printf 'line-%03d\n' "$i" >&9
    ) 9>>"$ACTIVE"
  )
}

for i in $(seq 1 100); do
  write_one "$i" &
done
wait

# Combined line count across active + archives (any matching `line-NNN`)
TOTAL_LINES=0
for f in "$ACTIVE" "$ROOT"/.claude/.test-*.jsonl "$ROOT"/.claude/.test-*.jsonl.gz; do
  [[ -e "$f" ]] || continue
  case "$f" in
    *.gz) C=$(gunzip -c "$f" 2>/dev/null | grep -c '^line-' || true) ;;
    *)    C=$(grep -c '^line-' "$f" 2>/dev/null || true) ;;
  esac
  TOTAL_LINES=$((TOTAL_LINES + C))
done
if [[ "$TOTAL_LINES" -ne 100 ]]; then
  fail "non-exact write count: $TOTAL_LINES of 100 lines preserved (torn or duplicated)"
else
  pass "$TOTAL_LINES (=100) lines preserved across concurrent writers + rotation"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Test 7: kill-switch LOG_ROTATION_DISABLE=1
# ------------------------------------------------------------------------
echo "Test 7: kill-switch short-circuits"
ROOT=$(make_root); ROOTS+=("$ROOT")
ACTIVE="$ROOT/.claude/.test.jsonl"
dd if=/dev/zero bs=1024 count=6144 2>/dev/null | tr '\0' 'k' > "$ACTIVE"
(
  source_helper
  LOG_ROTATION_DISABLE=1 rotate_if_needed "$ACTIVE"
)
if [[ "$(wc -c < "$ACTIVE")" -eq 0 ]]; then
  fail "active was rotated despite kill-switch"
elif compgen -G "$ROOT/.claude/.test-*" > /dev/null; then
  fail "archive created despite kill-switch"
else
  pass "no rotation when LOG_ROTATION_DISABLE=1"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Test 8: Existing archive — collision suffix appends
# ------------------------------------------------------------------------
echo "Test 8: collision suffix on existing archive"
ROOT=$(make_root); ROOTS+=("$ROOT")
ACTIVE="$ROOT/.claude/.test.jsonl"
TS=$(date -u +%Y-%m)
EXISTING="$ROOT/.claude/.test-${TS}.jsonl.gz"
echo "preexisting" | gzip > "$EXISTING"
dd if=/dev/zero bs=1024 count=6144 2>/dev/null | tr '\0' 'c' > "$ACTIVE"
(
  source_helper
  LOG_ROTATION_UNIQ_SUFFIX="testsfx" rotate_if_needed "$ACTIVE"
)
COLLISION="$ROOT/.claude/.test-${TS}-testsfx.jsonl.gz"
if [[ ! -f "$COLLISION" ]]; then
  fail "collision archive not created at $COLLISION (got: $(ls "$ROOT"/.claude/))"
elif [[ ! -f "$EXISTING" ]]; then
  fail "preexisting archive was clobbered"
else
  pass "collision archive created with suffix; preexisting intact"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Test 9: Helper exits 0 on missing file
# ------------------------------------------------------------------------
echo "Test 9: missing file is no-op"
ROOT=$(make_root); ROOTS+=("$ROOT")
set +e
(
  source_helper
  rotate_if_needed "$ROOT/.claude/.does-not-exist.jsonl"
)
RC=$?
set -e
if [[ "$RC" -ne 0 ]]; then
  fail "exit code $RC for missing file (expected 0)"
else
  pass "missing file → exit 0"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Test 10: Helper exits 0 on empty file (regardless of mtime)
# ------------------------------------------------------------------------
echo "Test 10: empty file is not rotated even if old"
ROOT=$(make_root); ROOTS+=("$ROOT")
ACTIVE="$ROOT/.claude/.test.jsonl"
: > "$ACTIVE"
OLD_TIME=$(date -u -d '60 days ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v-60d '+%Y-%m-%dT%H:%M:%SZ')
touch -d "$OLD_TIME" "$ACTIVE"
(
  source_helper
  rotate_if_needed "$ACTIVE"
)
if compgen -G "$ROOT/.claude/.test-*" > /dev/null; then
  fail "empty file rotated, producing empty archive"
else
  pass "empty file not rotated"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Test 11: Helper exits 0 with no argument
# ------------------------------------------------------------------------
echo "Test 11: no argument is no-op"
set +e
(
  source_helper
  rotate_if_needed ""
)
RC=$?
set -e
if [[ "$RC" -ne 0 ]]; then
  fail "exit code $RC for empty arg (expected 0)"
else
  pass "empty arg → exit 0"
fi

# ------------------------------------------------------------------------
# Test 12: Schema invariant — archive .gz decompresses to valid JSONL
# ------------------------------------------------------------------------
echo "Test 12: archive .gz is valid JSONL after rotation"
ROOT=$(make_root); ROOTS+=("$ROOT")
ACTIVE="$ROOT/.claude/.test.jsonl"
for i in $(seq 1 100); do
  printf '{"i":%d,"x":"some_text_to_pad"}\n' "$i" >> "$ACTIVE"
done
# Bump it over 1 KB threshold via env
(
  source_helper
  LOG_ROTATION_SIZE_BYTES=512 rotate_if_needed "$ACTIVE"
)
ARCHIVE=$(compgen -G "$ROOT/.claude/.test-*.jsonl.gz" | head -1)
if [[ -z "$ARCHIVE" ]]; then
  fail "no archive produced"
elif ! gunzip -c "$ARCHIVE" | jq -c -e '.i' >/dev/null 2>&1; then
  fail "archive does not parse as JSONL via jq"
else
  LINES=$(gunzip -c "$ARCHIVE" | wc -l)
  if [[ "$LINES" -ne 100 ]]; then
    fail "expected 100 lines in archive, got $LINES"
  else
    pass "archive .gz is valid 100-line JSONL"
  fi
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Test 13: stat -L dereferences symlinks (sink can be relocated via symlink)
# ------------------------------------------------------------------------
echo "Test 13: rotation follows symlinks (stat -L)"
ROOT=$(make_root); ROOTS+=("$ROOT")
TARGET_DIR="$(mktemp -d)"
ROOTS+=("$TARGET_DIR")
TARGET="$TARGET_DIR/real.jsonl"
LINK="$ROOT/.claude/.test.jsonl"
dd if=/dev/zero bs=1024 count=6144 2>/dev/null | tr '\0' 's' > "$TARGET"
ln -sf "$TARGET" "$LINK"
(
  source_helper
  rotate_if_needed "$LINK"
)
TARGET_SIZE=$(wc -c < "$TARGET")
if [[ "$TARGET_SIZE" -ne 0 ]]; then
  fail "symlink target not truncated (size=$TARGET_SIZE)"
elif ! compgen -G "$ROOT/.claude/.test-*.jsonl.gz" > /dev/null; then
  fail "no archive created via symlink"
else
  pass "symlinked sink rotated correctly"
fi
rm -rf "$ROOT" "$TARGET_DIR"
ROOTS=("${ROOTS[@]:0:${#ROOTS[@]}-2}")

# ------------------------------------------------------------------------
# Test 14: archive-write failure → warn-once + partial cleanup
# ------------------------------------------------------------------------
echo "Test 14: archive-write failure emits one warn, removes partial"
ROOT=$(make_root); ROOTS+=("$ROOT")
ACTIVE="$ROOT/.claude/.test.jsonl"
ARCHIVE_DIR="$ROOT/.claude"
dd if=/dev/zero bs=1024 count=6144 2>/dev/null | tr '\0' 'w' > "$ACTIVE"
ORIG_SIZE=$(wc -c < "$ACTIVE")
if [[ $(id -u) -eq 0 ]]; then
  pass "skipped under root (chmod 0500 ineffective)"
else
  # Clear any prior warn marker for this test process so we measure THIS run
  rm -f "/tmp/log-rotation-warned-$$" 2>/dev/null || true
  chmod 0500 "$ARCHIVE_DIR"
  STDERR=$(
    (
      source_helper
      rotate_if_needed "$ACTIVE"
    ) 2>&1 >/dev/null
  ) || true
  chmod 0700 "$ARCHIVE_DIR"
  POST_SIZE=$(wc -c < "$ACTIVE")
  PARTIAL_COUNT=$(compgen -G "$ROOT/.claude/.test-*" | wc -l || true)
  if [[ "$POST_SIZE" -ne "$ORIG_SIZE" ]]; then
    fail "active mutated despite archive failure (orig=$ORIG_SIZE, now=$POST_SIZE)"
  elif [[ "$PARTIAL_COUNT" -ne 0 ]]; then
    fail "partial archive left behind ($PARTIAL_COUNT files)"
  elif ! grep -q '\[log-rotation\] warning' <<< "$STDERR"; then
    fail "no stderr warning emitted (got: $STDERR)"
  else
    pass "active intact, no partial archive, one stderr warning"
  fi
  rm -f "/tmp/log-rotation-warned-$$" 2>/dev/null || true
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Test 15: archive-write failure returns 1 (rotation contract for sentinels)
# ------------------------------------------------------------------------
# Counterpart to Test 14 (warn + cleanup). Sentinel-aware callers branch on
# the exit code: `if ! rotate_if_needed "$f"; then _emit_drop_sentinel ...`.
# Existing fire-and-forget callers using `|| true` are unaffected — they
# swallow the non-zero return.
echo "Test 15: archive-write failure returns 1"
ROOT=$(make_root); ROOTS+=("$ROOT")
ACTIVE="$ROOT/.claude/.test.jsonl"
ARCHIVE_DIR="$ROOT/.claude"
dd if=/dev/zero bs=1024 count=6144 2>/dev/null | tr '\0' 'r' > "$ACTIVE"
if [[ $(id -u) -eq 0 ]]; then
  pass "skipped under root (chmod 0500 ineffective)"
else
  rm -f "/tmp/log-rotation-warned-$$" 2>/dev/null || true
  chmod 0500 "$ARCHIVE_DIR"
  set +e
  (
    source_helper
    rotate_if_needed "$ACTIVE"
  ) >/dev/null 2>&1
  RC=$?
  set -e
  chmod 0700 "$ARCHIVE_DIR"
  if [[ "$RC" -ne 1 ]]; then
    fail "expected return 1 on archive-write failure, got $RC"
  else
    pass "rotate_if_needed returned 1 on archive-write failure"
  fi
  rm -f "/tmp/log-rotation-warned-$$" 2>/dev/null || true
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Test 16: success path returns 0 (existing fire-and-forget callers stay green)
# ------------------------------------------------------------------------
echo "Test 16: successful rotation returns 0"
ROOT=$(make_root); ROOTS+=("$ROOT")
ACTIVE="$ROOT/.claude/.test.jsonl"
dd if=/dev/zero bs=1024 count=6144 2>/dev/null | tr '\0' 'g' > "$ACTIVE"
set +e
(
  source_helper
  rotate_if_needed "$ACTIVE"
) >/dev/null 2>&1
RC=$?
set -e
if [[ "$RC" -ne 0 ]]; then
  fail "expected return 0 on successful rotation, got $RC"
elif ! compgen -G "$ROOT/.claude/.test-*.jsonl.gz" >/dev/null; then
  fail "no archive produced"
else
  pass "rotate_if_needed returned 0 on success path"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Test 17: no-op path (below threshold) returns 0
# ------------------------------------------------------------------------
echo "Test 17: no-op below threshold returns 0"
ROOT=$(make_root); ROOTS+=("$ROOT")
ACTIVE="$ROOT/.claude/.test.jsonl"
printf 'small\n' > "$ACTIVE"
set +e
(
  source_helper
  rotate_if_needed "$ACTIVE"
) >/dev/null 2>&1
RC=$?
set -e
if [[ "$RC" -ne 0 ]]; then
  fail "expected return 0 below threshold, got $RC"
else
  pass "below-threshold rotate_if_needed returned 0"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
echo ""
echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
