#!/usr/bin/env bash
# Unit tests for lib/freeze-lock.sh — the freeze edit-lock control + reader.
#
# Contract under test:
#   set <path> | status | clear   — CLI round-trip against a redirected state
#                                    file (FREEZE_LOCK_REPO_ROOT override).
#   freeze_active_prefix           — reader sourced by guardrails.sh; echoes the
#                                    active absolute prefix ONLY for a
#                                    well-formed single-line absolute path;
#                                    absent/empty/malformed → echo nothing
#                                    (fail-open, OQ2 blast-radius guarantee).
#
# Isolation: FREEZE_LOCK_REPO_ROOT points every read/write at a temp root, so
# the operator's real .claude/.freeze-lock is never touched.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/freeze-lock.sh"

PASS=0
FAIL=0
TOTAL=0

assert_eq() {
  local label="$1" want="$2" got="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1)); echo "PASS: $label → $got"
  else
    FAIL=$((FAIL + 1)); echo "FAIL: $label"; echo "  want: $want"; echo "  got:  $got"
  fi
}

# Each test gets a fresh temp root; the state file lands at
# $root/.claude/.freeze-lock.
mk_root() { mktemp -d; }

# Invoke the helper CLI with the state root redirected.
cli() {
  local root="$1"; shift
  FREEZE_LOCK_REPO_ROOT="$root" bash "$HELPER" "$@" 2>/dev/null
}

# Invoke the sourced reader with the state root redirected. The wrapper `$0`
# ("_srcwrap") differs from the sourced file's BASH_SOURCE[0], so the helper's
# CLI-dispatch guard (`BASH_SOURCE[0] == $0`) does NOT fire — mirroring how
# guardrails.sh sources it (source path != the sourcing script's $0).
reader() {
  local root="$1"
  FREEZE_LOCK_REPO_ROOT="$root" bash -c \
    'source "$1"; freeze_active_prefix' _srcwrap "$HELPER" 2>/dev/null
}

# --- set/status/clear round-trip ------------------------------------------
root="$(mk_root)"
cli "$root" set "$root/apps/web-platform" >/dev/null
assert_eq "status after set → active prefix" \
  "$root/apps/web-platform" "$(cli "$root" status)"
assert_eq "reader after set → active prefix" \
  "$root/apps/web-platform" "$(reader "$root")"
cli "$root" clear >/dev/null
assert_eq "status after clear → inactive" "inactive" "$(cli "$root" status)"
assert_eq "reader after clear → empty (fail-open)" "" "$(reader "$root")"
rm -rf "$root"

# --- absent state file → inactive / empty ---------------------------------
root="$(mk_root)"
assert_eq "status, no state file → inactive" "inactive" "$(cli "$root" status)"
assert_eq "reader, no state file → empty (fail-open)" "" "$(reader "$root")"
rm -rf "$root"

# --- malformed: two lines → fail-open -------------------------------------
root="$(mk_root)"
mkdir -p "$root/.claude"
printf '%s\n%s\n' "/some/allowed/path" "/an/extra/line" > "$root/.claude/.freeze-lock"
assert_eq "reader, two-line state → empty (fail-open)" "" "$(reader "$root")"
assert_eq "status, two-line state → inactive" "inactive" "$(cli "$root" status)"
rm -rf "$root"

# --- malformed: non-absolute path → fail-open -----------------------------
root="$(mk_root)"
mkdir -p "$root/.claude"
printf '%s\n' "relative/not/absolute" > "$root/.claude/.freeze-lock"
assert_eq "reader, relative-path state → empty (fail-open)" "" "$(reader "$root")"
rm -rf "$root"

# --- malformed: empty file → fail-open ------------------------------------
root="$(mk_root)"
mkdir -p "$root/.claude"
: > "$root/.claude/.freeze-lock"
assert_eq "reader, empty state file → empty (fail-open)" "" "$(reader "$root")"
rm -rf "$root"

# --- set resolves a relative path to absolute -----------------------------
root="$(mk_root)"
( cd "$root" && FREEZE_LOCK_REPO_ROOT="$root" bash "$HELPER" set "./apps" >/dev/null 2>&1 )
assert_eq "set resolves relative → absolute prefix" \
  "$root/apps" "$(reader "$root")"
rm -rf "$root"

echo
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
