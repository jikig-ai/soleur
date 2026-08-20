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
# The INDEPENDENT case counter (ADR-193 #2). It moves in assert() — the ASSERTION helper —
# and NEVER in pass()/fail(), the VERDICT helpers. That split is the whole point: a counter
# incremented inside the verdict helpers moves WITH the verdict, so stubbing fail() drops the
# row and its count together and the conservation identity below holds under the exact fault
# it exists to catch. Never increment this inside `$( )`; a subshell discards it.
CASES=0

# VERDICT helpers — they own passes/fails and nothing else.
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() {
  fails=$((fails + 1))
  printf '  FAIL %s\n' "$1"
  [[ -n "${2:-}" ]] && printf '       %s\n' "$2"
  return 0
}

# ASSERTION helper — owns CASES. $1 = description, $2 = condition (eval'd), $3 = failure detail.
assert() {
  CASES=$((CASES + 1))
  if eval "$2"; then
    pass "$1"
  else
    fail "$1" "${3:-$2}"
  fi
}

printf '\n=== emit-review-trailer coverage field ===\n\n'

# Reported DIRECTLY, not through fail(): with the SUT absent there is nothing to assert, so a
# verdict-helper report here would be a row in a suite that never ran.
[[ -f "$SUT" ]] || {
  printf '\n[FATAL] SUT missing at %s — nothing to test.\n' "$SUT" >&2
  exit 1
}

# A fresh repo on a feature branch with a `main` to scope against. The script refuses to run
# on main/master, and its idempotence check scopes to `origin/main..HEAD`-equivalent, so both
# refs have to exist for the arms below to exercise the real paths.
new_repo() {
  local d="$TMP/$1"; mkdir -p "$d"
  git -C "$d" init -q -b main
  # LOCAL config, not `-c` on our own commits. The SUT runs its OWN `git commit`, so an
  # identity supplied only via `-c` on the fixture's setup commits does not reach it — it
  # inherits whatever the ambient environment has. On a developer laptop that is the global
  # config and every arm passes; on a bare CI runner there is none and the SUT dies with
  # "Please tell me who you are", which surfaces as `git commit failed` and 8 of 12 arms red.
  # Measured: this suite was 12/12 locally and 4/8 in CI on its first run (#7070).
  git -C "$d" config user.email soleur-test@example.invalid
  git -C "$d" config user.name  "Soleur Test"
  # Some runners set commit.gpgsign globally; a throwaway repo has no key.
  git -C "$d" config commit.gpgsign false
  git -C "$d" commit -q --allow-empty -m "base"
  git -C "$d" checkout -q -b feat-x
  printf '%s' "$d"
}

coverage_of() {  # $1 = repo dir -> the parsed Reviewed-Coverage trailer value
  git -C "$1" log -1 --format='%(trailers:key=Reviewed-Coverage,valueonly)' | tr -d '\n'
}

# ── ARM 1: full coverage ──────────────────────────────────────────────────────────
d="$(new_repo full)"
out="$(cd "$d" && bash "$SUT" --findings 0 --agents-ran 9 --agents-expected 9 2>&1)"; rc=$?
assert "full coverage exits 0" '[[ "$rc" -eq 0 ]]' "rc=$rc out=$out"
cov="$(coverage_of "$d")"
assert "records 'full 9/9 agents'" '[[ "$cov" == *"full 9/9 agents"* ]]' "got: '$cov'"

# ── ARM 2: degraded coverage, with the missing agents NAMED ───────────────────────
#
# This is the shape measured on PR #7066 (7 of 9 died on 529s). The named list is the part a
# reader needs: "2/9" says how much ran, not WHICH lens is absent, and the agents that die
# are not the ones you needed least.
d="$(new_repo degraded)"
out="$(cd "$d" && bash "$SUT" --findings 3 --agents-ran 2 --agents-expected 9 \
        --agents-missing security-sentinel,test-design-reviewer 2>&1)"; rc=$?
cov="$(coverage_of "$d")"
assert "records 'degraded 2/9 agents'" \
  '[[ "$rc" -eq 0 && "$cov" == *"degraded 2/9 agents"* ]]' "rc=$rc got: '$cov'"
assert "names the missing agents in the trailer value" \
  '[[ "$cov" == *"security-sentinel"* && "$cov" == *"test-design-reviewer"* ]]' "got: '$cov'"

# ── ARM 3: zero agents => inline-fallback ─────────────────────────────────────────
d="$(new_repo zero)"
(cd "$d" && bash "$SUT" --findings 1 --agents-ran 0 --agents-expected 8 >/dev/null 2>&1)
cov="$(coverage_of "$d")"
assert "zero agents records 'inline-fallback'" \
  '[[ "$cov" == *"inline-fallback 0/8 agents"* ]]' "got: '$cov'"

# ── ARM 4: THE COUNTS OVERRIDE A CALLER'S LABEL ───────────────────────────────────
#
# A caller passing `--mode full` with 2-of-10 counts is either confused or overclaiming.
# Deriving the mode from the counts is what makes the field non-forgeable by accident.
d="$(new_repo overclaim)"
(cd "$d" && bash "$SUT" --agents-ran 2 --agents-expected 10 --mode full >/dev/null 2>&1)
cov="$(coverage_of "$d")"
assert "counts override an overclaiming --mode full" \
  '[[ "$cov" == *degraded* && "$cov" != *full* ]]' "got: '$cov'"

# ── ARM 5: ABSENT measurement is 'unknown', NOT 'full' ────────────────────────────
#
# The load-bearing default. Every legacy call site omits the flags, so defaulting an absent
# measurement to the strongest value would make the field decorative on exactly the calls
# that predate it — and would read as a full review having run.
d="$(new_repo legacy)"
(cd "$d" && bash "$SUT" --findings 0 >/dev/null 2>&1)
cov="$(coverage_of "$d")"
assert "absent measurement records 'unknown', not 'full'" '[[ "$cov" == "unknown" ]]' "got: '$cov'"

# ── ARM 6: the coverage trailer PARSES (it is last, so it splits first) ───────────
#
# git needs the whole final paragraph to be `Key: value` lines. Reviewed-Coverage sits LAST,
# so it is the first casualty of a split — and a value that does not parse is invisible to
# every consumer while looking like evidence in `git log`.
d="$(new_repo parse)"
(cd "$d" && bash "$SUT" --agents-ran 4 --agents-expected 4 >/dev/null 2>&1)
cov="$(coverage_of "$d")"
# shellcheck disable=SC2034  # consumed via `eval "$condition"` in assert()
by="$(git -C "$d" log -1 --format='%(trailers:key=Reviewed-By-Soleur,valueonly)' | tr -d '[:space:]')"
assert "both Reviewed-By-Soleur and Reviewed-Coverage parse as trailers" \
  '[[ -n "$cov" && -n "$by" ]]' "$(git -C "$d" log -1 --format=%B)"

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
  # CASES moves here, once per loop iteration, because assert() is called once per iteration —
  # the counter has to track the arms that actually run, not the arms written in the source.
  assert "refuses '$bad' with no commit" '[[ "$rc" -eq 2 && "$before" == "$after" ]]' \
    "rc=$rc committed=$([[ "$before" != "$after" ]] && echo yes || echo no) out=$out"
done

# ── ARM 8: still refuses to run on main ──────────────────────────────────────────
# Guards against the coverage plumbing having disturbed the pre-existing branch guard.
d="$(new_repo onmain)"; git -C "$d" checkout -q main
out="$(cd "$d" && bash "$SUT" --agents-ran 1 --agents-expected 1 2>&1)"; rc=$?
assert "still skips on main (pre-existing guard intact)" \
  '[[ "$rc" -eq 0 && "$out" == *"nothing to mark, skipping"* ]]' "rc=$rc out=$out"

# ── Accounting conservation (ADR-193 #3) ─────────────────────────────────────────
# Ordered BEFORE the floor per ADR-193 #4: a neutered fail() deflates the verdict counts, so
# a floor reading them would ALSO trip and would report the misleading "arms were deleted".
# This says "a verdict was discarded" instead. Reported with printf >&2 + exit 1 DIRECTLY,
# never through pass()/fail(): a check that reports by calling a verdict helper increments the
# very counter the exit status reads, so neutering the helper silences the rows AND the check
# meant to notice the silence. The literal `[FATAL] accounting` is load-bearing —
# guard-vacuity-floor's ARM 10 builds its conservation population by grepping that string.
if [[ $((passes + fails)) -ne "$CASES" ]]; then
  printf '\n[FATAL] accounting: passes+fails (%d) != CASES (%d).\n' \
    "$((passes + fails))" "$CASES" >&2
  if [[ $((passes + fails)) -lt "$CASES" ]]; then
    printf '  An assertion was counted but its verdict was discarded — that is what a neutered pass()/fail() looks like.\n' >&2
  else
    printf '  A verdict was recorded at a call site with no `CASES=$((CASES + 1))` before it. This is a harness bug, not a product failure: add the increment at that call site.\n' >&2
  fi
  printf '\n=== emit-review-trailer coverage: %d passed, %d failed (%d assertions) ===\n\n' \
    "$passes" "$fails" "$CASES"
  exit 1
fi

# ── Anti-vacuity floor (ADR-193 #1) ──────────────────────────────────────────────
# Reads the INDEPENDENT case counter, and reports with printf >&2 + exit 1 DIRECTLY. It
# previously read `passes + fails` and reported via `fails=$((fails + 1))` — a tautology on
# both counts: the operand moved WITH the verdict, and the report went into a counter that a
# neutered fail() had already stopped feeding. Stub the assertion machinery and the suite
# printed a clean total and exited 0.
#
# A floor, not equality: developer-incremented, so `-eq` would redden the suite on every added
# arm. Ratchet when adding arms; read a floor failure on an otherwise-green run as "you added
# assertions, update this number".
TRAILER_MIN_ASSERTIONS=12
if (( CASES < TRAILER_MIN_ASSERTIONS )); then
  printf '\n[FATAL] anti-vacuity floor: only %d assertion(s) ran, expected >= %d.\n' \
    "$CASES" "$TRAILER_MIN_ASSERTIONS" >&2
  printf '  Arms were deleted or skipped; a green run here would be a coverage loss.\n' >&2
  printf '\n=== emit-review-trailer coverage: %d passed, %d failed (%d assertions) ===\n\n' \
    "$passes" "$fails" "$CASES"
  exit 1
fi

printf '\n=== emit-review-trailer coverage: %d passed, %d failed (%d assertions) ===\n\n' \
  "$passes" "$fails" "$CASES"
[[ "$fails" -eq 0 ]]
