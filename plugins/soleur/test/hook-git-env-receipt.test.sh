#!/usr/bin/env bash
# Guard 2's external receipt consumer.
#
# WHY THIS FILE EXISTS. Every floor inside `hook-git-env-coverage.test.sh` lives inside that file,
# so replacing its body with `exit 0` deletes the guard and its floors together and reports success
# having asserted nothing. A guard cannot detect its own erasure from the inside.
#
# The guard therefore emits SOLEUR_GUARD2_RECEIPT and something outside it must READ that. In the
# first revision the only reader was `hook-git-env-coverage.mutation.sh` — a `.mutation.sh`, which
# matches none of SUITE_GLOBS in scripts/test-all.sh, so nothing in CI read the receipt at all and
# `exit 0` at the top of the guard shipped undetected. This file is a `.test.sh`, so the
# `plugins/soleur/test/*.test.sh` glob registers it and the check actually runs on every battery.
#
# It deliberately does NOT source test-helpers.sh: that file carries the Guard 3 shell prelude, and
# this suite must stay runnable while diagnosing a hostile environment.
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
GUARD="$SCRIPT_DIR/hook-git-env-coverage.test.sh"

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

[[ -f "$GUARD" ]] || { printf 'FATAL: guard missing at %s\n' "$GUARD" >&2; exit 2; }

OUT="$(mktemp -t g2rcpt.XXXXXXXX)" || exit 2
trap 'rm -f "$OUT"' EXIT INT TERM HUP

( cd "$REPO_ROOT" && bash "$GUARD" ) > "$OUT" 2>&1
GUARD_RC=$?

if (( GUARD_RC == 0 )); then
  ok "Guard 2 exits 0 against the live corpus"
else
  bad "Guard 2 exited $GUARD_RC against the live corpus"
  tail -8 "$OUT" | sed 's/^/        /'
fi

RECEIPT="$(grep -oE 'SOLEUR_GUARD2_RECEIPT run_lines=[0-9]+ runners=[0-9]+ hook_files=[0-9]+ assertions=[0-9]+' "$OUT" | tail -1)"
if [[ -n "$RECEIPT" ]]; then
  ok "Guard 2 emitted a well-formed receipt"
else
  bad "Guard 2 emitted NO receipt — it may have been replaced by a no-op (this is the erasure case)"
fi

# The counts must be above floor. A receipt whose numbers collapsed is a guard that ran over a
# corpus it could not see — indistinguishable from a clean sweep by exit code alone.
if [[ -n "$RECEIPT" ]]; then
  rl=$(printf '%s' "$RECEIPT" | sed -n 's/.*run_lines=\([0-9]*\).*/\1/p')
  rn=$(printf '%s' "$RECEIPT" | sed -n 's/.*runners=\([0-9]*\).*/\1/p')
  hf=$(printf '%s' "$RECEIPT" | sed -n 's/.*hook_files=\([0-9]*\).*/\1/p')
  as=$(printf '%s' "$RECEIPT" | sed -n 's/.*assertions=\([0-9]*\).*/\1/p')
  if (( rl >= 26 )); then ok "receipt run_lines=$rl (floor 26)"; else bad "receipt run_lines=$rl below floor 26"; fi
  if (( rn >= 3 ));  then ok "receipt runners=$rn (floor 3)";     else bad "receipt runners=$rn below floor 3"; fi
  if (( hf >= 2 ));  then ok "receipt hook_files=$hf (floor 2)";  else bad "receipt hook_files=$hf below floor 2"; fi
  if (( as >= 8 ));  then ok "receipt assertions=$as (floor 8)";  else bad "receipt assertions=$as below floor 8"; fi
fi

printf '\n=== summary ===\n'
printf '  %d passed, %d failed, %d assertions\n' "$PASS" "$FAIL" "$ASSERTIONS"

MIN_ASSERTIONS=6
if (( ASSERTIONS < MIN_ASSERTIONS )); then
  printf 'FLOOR: %d assertions < %d\n' "$ASSERTIONS" "$MIN_ASSERTIONS" >&2; exit 1
fi
if (( FAIL > 0 )); then exit 1; fi
exit 0
