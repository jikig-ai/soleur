#!/usr/bin/env bash
# The git-location family is written down in six places, in four languages. This pins them.
#
# WHY THIS EXISTS. `plugins/soleur/test/lib/git-clean-env.ts` states the repo's rule for this class
# — a duplicated constant gets a parity TEST, not a "keep in sync" comment — and
# `tests/scripts/test_rule_id_regex_parity.py` is the precedent: "Active enforcement replaces the
# prose drift comments in both files." The first revision of #7833 shipped four copies of this list
# pinned by nothing but a comment reading "Kept in sync with git-fixture-env.ts", which is exactly
# the shape both of those artifacts exist to forbid.
#
# The six sites and why each must agree:
#   TS       lib/git-fixture-env.ts        GIT_LOCATION_VARS   — the source of truth
#   PY       tests/scripts/_git_fixture_env.py                 — the python sibling
#   SHELL    test-helpers.sh               the tripwire's for-loop
#   GUARD    hook-git-env-coverage.test.sh REQUIRED_SCRUB_VARS — what an entry point must remove
#   SCRUB    lefthook.yml, scripts/test-all.sh, scripts/hooks/pre-push — the actual `unset`s
#
# The last row is the one that matters most and the one a prose comment could never have caught:
# if the tripwire REFUSES a variable that the scrub does not REMOVE, the guard prints a remedy it
# will then reject, and the operator loops. Detect-set and remediate-set must be the same set.
export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "$SCRIPT_DIR" in
  ""|/|//|/.) printf 'FATAL: SCRIPT_DIR degenerate\n' >&2; exit 2 ;;
  /*) : ;;
  *) printf 'FATAL: SCRIPT_DIR is relative\n' >&2; exit 2 ;;
esac
readonly SCRIPT_DIR
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)" || exit 2
readonly REPO_ROOT

PASS=0; FAIL=0; ASSERTIONS=0
ok()  { printf '  [ok]   %s\n' "$1"; PASS=$((PASS+1)); ASSERTIONS=$((ASSERTIONS+1)); }
bad() { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); ASSERTIONS=$((ASSERTIONS+1)); }

_p0=$PASS; _f0=$FAIL
ok  "instrument self-test: ok() increments"
bad "instrument self-test: bad() increments (expected; subtracted)"
if (( PASS != _p0 + 1 || FAIL != _f0 + 1 )); then
  printf 'FATAL: instrument self-test did not move both counters\n' >&2; exit 2
fi
PASS=$((PASS-1)); FAIL=$((FAIL-1)); ASSERTIONS=$((ASSERTIONS-2))
printf '  (instrument verified)\n\n'

# Each extractor prints one NAME per line, sorted. A derivation that silently yields nothing would
# make every comparison trivially equal, so the non-empty floor below is not optional.
ts_list() {
  sed -n '/^export const GIT_LOCATION_VARS = \[/,/^\] as const;/p' \
      "$SCRIPT_DIR/lib/git-fixture-env.ts" | grep -oE '"GIT_[A-Z_]+"' | tr -d '"' | sort
}
py_list() {
  sed -n '/^GIT_LOCATION_VARS = (/,/^)/p' \
      "$REPO_ROOT/tests/scripts/_git_fixture_env.py" | grep -oE '"GIT_[A-Z_]+"' | tr -d '"' | sort
}
shell_list() {
  sed -n '/for _v in GIT_/,/; do/p' "$SCRIPT_DIR/test-helpers.sh" \
    | grep -oE '\bGIT_[A-Z_]+\b' | sort -u
}
guard_list() {
  sed -n '/^readonly REQUIRED_SCRUB_VARS=(/,/^)/p' \
      "$SCRIPT_DIR/hook-git-env-coverage.test.sh" | grep -oE '\bGIT_[A-Z_]+\b' | sort -u
}
# The actual `unset` statements. Comment-stripped first: a scrub named only in a comment removes
# nothing, and this file must not certify prose.
scrub_list() {
  local f="$1"
  sed 's/[[:space:]]*#.*$//' "$f" | grep -oE '\bunset[[:space:]]+GIT_[A-Z_ ]+' \
    | head -1 | grep -oE '\bGIT_[A-Z_]+\b' | sort -u
}

TS="$(ts_list)"; PY="$(py_list)"; SH="$(shell_list)"; GD="$(guard_list)"
N=$(printf '%s\n' "$TS" | grep -c .)

# Non-vacuity: if any derivation returns empty, every set-equality below passes for the wrong
# reason. Floor on the source of truth AND require every other derivation non-empty.
if (( N >= 9 )); then
  ok "TS GIT_LOCATION_VARS derived $N names (floor 9)"
else
  bad "TS GIT_LOCATION_VARS derived only $N names — the extraction broke or the list shrank"
fi
for pair in "PY:$PY" "SHELL:$SH" "GUARD:$GD"; do
  name="${pair%%:*}"; val="${pair#*:}"
  if [[ -n "$val" ]]; then ok "$name derivation is non-empty"; else bad "$name derivation returned NOTHING"; fi
done

cmp_set() {
  local label="$1" a="$2" b="$3" d
  d="$(diff <(printf '%s\n' "$a") <(printf '%s\n' "$b") || true)"
  if [[ -z "$d" ]]; then
    ok "$label matches the TS source of truth"
  else
    bad "$label DIFFERS from the TS source of truth:"
    printf '%s\n' "$d" | sed 's/^/        /'
  fi
}
cmp_set "python  _git_fixture_env.py" "$TS" "$PY"
cmp_set "shell   test-helpers.sh"     "$TS" "$SH"
cmp_set "guard   REQUIRED_SCRUB_VARS" "$TS" "$GD"

printf '\n=== the scrub sites remove everything the tripwire refuses ===\n'
# The asymmetry that matters: a variable the tripwire REFUSES but a scrub does not REMOVE makes the
# guard print a remedy that cannot clear it. Subset direction is the whole point — the scrub must
# cover the detect set.
for f in "$REPO_ROOT/lefthook.yml" "$REPO_ROOT/scripts/test-all.sh" "$REPO_ROOT/scripts/hooks/pre-push"; do
  rel="${f#"$REPO_ROOT"/}"
  got="$(scrub_list "$f")"
  if [[ -z "$got" ]]; then
    bad "$rel has no unset statement naming the git-location family"
    continue
  fi
  missing="$(comm -23 <(printf '%s\n' "$TS") <(printf '%s\n' "$got") | tr '\n' ' ')"
  if [[ -z "${missing// }" ]]; then
    ok "$rel unsets every name the tripwire refuses"
  else
    bad "$rel does NOT unset: ${missing% }"
  fi
done

printf '\n=== summary ===\n'
printf '  %d passed, %d failed, %d assertions\n' "$PASS" "$FAIL" "$ASSERTIONS"

MIN_ASSERTIONS=10
if (( ASSERTIONS < MIN_ASSERTIONS )); then
  printf 'FLOOR: %d assertions < %d\n' "$ASSERTIONS" "$MIN_ASSERTIONS" >&2; exit 1
fi
if (( FAIL > 0 )); then exit 1; fi
exit 0
