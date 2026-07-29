#!/usr/bin/env bash
#
# Tests for emit-review-trailer.sh's coverage field (#7066 follow-up).
#
# WHY THIS SUITE EXISTS. The script's whole value is that a downstream consumer can tell a
# full review from a degraded one. Every way that can silently stop being true looks like
# success: a value that does not parse as a trailer is invisible to `git log
# --format='%(trailers:...)'` while reading fine to a human; an absent measurement defaulting
# to the strongest value makes the field decorative; and a caller-supplied `--mode full`
# alongside 2-of-10 counts overclaims in the one direction that matters.
#
# EVERY ARM RUNS AGAINST A THROWAWAY REPO, never the real one — the script COMMITS, so a
# suite that ran in-tree would leave empty commits on whatever branch invoked it.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# ../scripts/ — this suite deliberately lives in skills/review/test/ and not beside the SUT
# in skills/review/scripts/, because scripts/test-all.sh discovers
# `plugins/soleur/skills/*/test/*.test.sh` and NOT `skills/*/scripts/*.test.sh`. Placed next
# to the SUT it would be silent AND green: never run, never red (#3366).
SUT="$(cd "${DIR}/../scripts" && pwd)/emit-review-trailer.sh"

TMP="$(mktemp -d -t emitrt.XXXXXXXX)" || { echo "mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

passes=0
fails=0
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() {
  fails=$((fails + 1))
  printf '  FAIL %s\n' "$1"
  [[ -n "${2:-}" ]] && printf '       %s\n' "$2"
  return 0
}

printf '\n=== emit-review-trailer coverage field ===\n\n'

[[ -f "$SUT" ]] || { fail "SUT exists at $SUT"; printf '\n=== 0 passed, 1 failed ===\n\n'; exit 1; }

# A fresh repo on a feature branch with a `main` to scope against. The script refuses to run
# on main/master, and its idempotence check scopes to `origin/main..HEAD`-equivalent, so both
# refs have to exist for the arms below to exercise the real paths.
new_repo() {
  local d="$TMP/$1"; mkdir -p "$d"
  git -C "$d" init -q -b main
  git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "base"
  git -C "$d" checkout -q -b feat-x
  printf '%s' "$d"
}

coverage_of() {  # $1 = repo dir -> the parsed Reviewed-Coverage trailer value
  git -C "$1" log -1 --format='%(trailers:key=Reviewed-Coverage,valueonly)' | tr -d '\n'
}

# ── ARM 1: full coverage ──────────────────────────────────────────────────────────
d="$(new_repo full)"
out="$(cd "$d" && bash "$SUT" --findings 0 --agents-ran 9 --agents-expected 9 2>&1)"; rc=$?
if [[ "$rc" -eq 0 ]]; then pass "full coverage exits 0"; else fail "full coverage exits 0" "rc=$rc out=$out"; fi
cov="$(coverage_of "$d")"
if [[ "$cov" == *"full 9/9 agents"* ]]; then pass "records 'full 9/9 agents'"; else
  fail "records 'full 9/9 agents'" "got: '$cov'"; fi

# ── ARM 2: degraded coverage, with the missing agents NAMED ───────────────────────
#
# This is the shape measured on PR #7066 (7 of 9 died on 529s). The named list is the part a
# reader needs: "2/9" says how much ran, not WHICH lens is absent, and the agents that die
# are not the ones you needed least.
d="$(new_repo degraded)"
out="$(cd "$d" && bash "$SUT" --findings 3 --agents-ran 2 --agents-expected 9 \
        --agents-missing security-sentinel,test-design-reviewer 2>&1)"; rc=$?
cov="$(coverage_of "$d")"
if [[ "$rc" -eq 0 && "$cov" == *"degraded 2/9 agents"* ]]; then
  pass "records 'degraded 2/9 agents'"
else
  fail "records 'degraded 2/9 agents'" "rc=$rc got: '$cov'"
fi
if [[ "$cov" == *"security-sentinel"* && "$cov" == *"test-design-reviewer"* ]]; then
  pass "names the missing agents in the trailer value"
else
  fail "names the missing agents in the trailer value" "got: '$cov'"
fi

# ── ARM 3: zero agents => inline-fallback ─────────────────────────────────────────
d="$(new_repo zero)"
(cd "$d" && bash "$SUT" --findings 1 --agents-ran 0 --agents-expected 8 >/dev/null 2>&1)
cov="$(coverage_of "$d")"
if [[ "$cov" == *"inline-fallback 0/8 agents"* ]]; then
  pass "zero agents records 'inline-fallback'"
else
  fail "zero agents records 'inline-fallback'" "got: '$cov'"
fi

# ── ARM 4: THE COUNTS OVERRIDE A CALLER'S LABEL ───────────────────────────────────
#
# A caller passing `--mode full` with 2-of-10 counts is either confused or overclaiming.
# Deriving the mode from the counts is what makes the field non-forgeable by accident.
d="$(new_repo overclaim)"
(cd "$d" && bash "$SUT" --agents-ran 2 --agents-expected 10 --mode full >/dev/null 2>&1)
cov="$(coverage_of "$d")"
if [[ "$cov" == *degraded* && "$cov" != *full* ]]; then
  pass "counts override an overclaiming --mode full"
else
  fail "counts override an overclaiming --mode full" "got: '$cov'"
fi

# ── ARM 5: ABSENT measurement is 'unknown', NOT 'full' ────────────────────────────
#
# The load-bearing default. Every legacy call site omits the flags, so defaulting an absent
# measurement to the strongest value would make the field decorative on exactly the calls
# that predate it — and would read as a full review having run.
d="$(new_repo legacy)"
(cd "$d" && bash "$SUT" --findings 0 >/dev/null 2>&1)
cov="$(coverage_of "$d")"
if [[ "$cov" == "unknown" ]]; then pass "absent measurement records 'unknown', not 'full'"; else
  fail "absent measurement records 'unknown', not 'full'" "got: '$cov'"; fi

# ── ARM 6: the coverage trailer PARSES (it is last, so it splits first) ───────────
#
# git needs the whole final paragraph to be `Key: value` lines. Reviewed-Coverage sits LAST,
# so it is the first casualty of a split — and a value that does not parse is invisible to
# every consumer while looking like evidence in `git log`.
d="$(new_repo parse)"
(cd "$d" && bash "$SUT" --agents-ran 4 --agents-expected 4 >/dev/null 2>&1)
if [[ -n "$(coverage_of "$d")" ]] \
   && [[ -n "$(git -C "$d" log -1 --format='%(trailers:key=Reviewed-By-Soleur,valueonly)' | tr -d '[:space:]')" ]]; then
  pass "both Reviewed-By-Soleur and Reviewed-Coverage parse as trailers"
else
  fail "both trailers parse" "$(git -C "$d" log -1 --format=%B)"
fi

# ── ARM 7: malformed input is REFUSED before any commit ───────────────────────────
#
# A bad count must not land in main's permanent history as an unparseable coverage claim.
# Asserting "no commit was created" is the load-bearing half: exiting 2 while having already
# committed would be strictly worse than accepting the value.
for bad in "--agents-ran abc --agents-expected 5" \
           "--agents-ran 5 --agents-expected 2" \
           "--mode enthusiastic"; do
  d="$(new_repo "bad$(echo "$bad" | tr -cd 'a-z0-9')")"
  before="$(git -C "$d" rev-parse HEAD)"
  # shellcheck disable=SC2086
  out="$(cd "$d" && bash "$SUT" $bad 2>&1)"; rc=$?
  after="$(git -C "$d" rev-parse HEAD)"
  if [[ "$rc" -eq 2 && "$before" == "$after" ]]; then
    pass "refuses '$bad' with no commit"
  else
    fail "refuses '$bad' with no commit" "rc=$rc committed=$([[ "$before" != "$after" ]] && echo yes || echo no) out=$out"
  fi
done

# ── ARM 8: still refuses to run on main ──────────────────────────────────────────
# Guards against the coverage plumbing having disturbed the pre-existing branch guard.
d="$(new_repo onmain)"; git -C "$d" checkout -q main
out="$(cd "$d" && bash "$SUT" --agents-ran 1 --agents-expected 1 2>&1)"; rc=$?
if [[ "$rc" -eq 0 && "$out" == *"nothing to mark, skipping"* ]]; then
  pass "still skips on main (pre-existing guard intact)"
else
  fail "still skips on main" "rc=$rc out=$out"
fi

# ── Minimum-cardinality floor ────────────────────────────────────────────────────
# A floor, not equality: developer-incremented, so `-eq` would redden the suite on every
# added arm. Counts passes+fails so a genuine failure reports as a failure rather than as an
# empty suite.
_ran=$((passes + fails))
if [[ "$_ran" -lt 12 ]]; then
  fails=$((fails + 1))
  printf '  FAIL ANTI-VACUITY: only %s assertions ran, floor is 12.\n' "$_ran"
else
  printf '  ok   anti-vacuity floor: %s assertions ran (floor 12)\n' "$_ran"
fi

printf '\n=== emit-review-trailer coverage: %d passed, %d failed ===\n\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]]
