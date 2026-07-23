#!/usr/bin/env bash
# Mutation test for scripts/lint-followthrough-varq-ban.sh (#6757) -- the NON-VACUITY core.
#
# Drives the ACTUAL Phase-1 guard (never a re-implementation) over a mktemp sandbox of
# synthesized fixtures, asserting BOTH directions so every assertion can fail:
#   GREEN            compliant `if [[ -z "${VAR:-}" ]]` fixture   -> guard exits 0
#   RED-A (:?)       executable `: "${FOO:?msg}"`                 -> guard exits 1 + cites file AT TRUE LINE
#   RED-B (colon-)   executable `${BAR?msg}`                      -> guard exits 1 + cites line (proves :?\? breadth)
#   COMMENT-GREEN    banned form in a FULL-LINE `#` comment only  -> guard exits 0 (proves the strip)
#   INLINE-COMMENT   banned form in a TRAILING comment on code    -> guard exits 1 (fail-closed contract)
#   MISSING-DIR      nonexistent target dir                       -> guard exits 2 (internal error)
#   FLOOR            production run below min-cardinality floor    -> guard exits 2 (broken-glob anti-vacuity)
#   LIVE-GREEN       production run (no arg) over the real tree   -> guard exits 0 (post-conversion)
#
# RED-A/RED-B pin the offender's file:LINE (not just the filename): the guard's whole value is
# naming the offender ACCURATELY, and a re-index regression passes a filename-only assertion.
# MISSING-DIR + FLOOR cover the two exit-2 fail-closed paths a "clean passes" battery leaves green.
#
# A test that only checks "clean passes" is vacuous; each RED asserts non-zero AND each
# GREEN asserts zero. Fixtures are synthesized under mktemp OUTSIDE scripts/followthroughs/,
# so the live guard never sees them (no fixture leakage).
#
# Tempfile ownership (satisfies scripts/lint-trap-tempfile-ownership.py rule (c)): the trap
# below owns ONLY the mktemp dir this script created.

set -uo pipefail

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$REPO_ROOT/scripts/lint-followthrough-varq-ban.sh"

fails=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1" >&2; fails=$((fails + 1)); }

echo "lint-followthrough-varq-ban.test.sh: mutation proof (both RED directions + comment GREEN + live)"

# Each case gets its own sandbox subdir so the guard scans exactly the fixture(s) under test.
mkcase() { local d="$SANDBOX/$1"; mkdir -p "$d"; printf '%s' "$d"; }

run_guard() {
  # run_guard <dir>  -> sets GUARD_RC and GUARD_OUT
  GUARD_OUT="$(bash "$GUARD" "$1" 2>&1)"
  GUARD_RC=$?
}

# --- GREEN: compliant fixture -> exit 0 ---
d=$(mkcase green)
cat >"$d/compliant-1.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
if [[ -z "${FOO:-}" ]]; then echo "TRANSIENT: FOO not set" >&2; exit 2; fi
echo "ok"
EOF
run_guard "$d"
if (( GUARD_RC == 0 )); then pass "GREEN compliant fixture -> exit 0"; else fail "GREEN compliant fixture expected exit 0, got $GUARD_RC: $GUARD_OUT"; fi

# --- RED-A (:?): executable `: "${FOO:?msg}"` -> exit 1 AND names the file AT THE RIGHT LINE ---
# The banned form sits on line 4, AFTER a shebang (#!) and a full-line `#` comment. A guard that
# re-indexes with the anti-pattern `grep -v '^#' | grep -n` (the guard header's LOAD-BEARING
# warning) strips those two comment lines FIRST and mis-cites the offender as line 2. Pinning
# `:4:` is the only assertion that reddens on that re-index mutant -- naming the file alone does
# not (the whole value of the guard is naming the offender ACCURATELY -- #6757 review).
d=$(mkcase red_a)
cat >"$d/banned-colon-q.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
# provisioning note: this probe reads FOO from Doppler at sweep time
: "${FOO:?FOO must be set}"
echo "ok"
EOF
run_guard "$d"
if (( GUARD_RC == 1 )); then pass "RED-A (:?) fixture -> exit 1 (violation)"; else fail "RED-A (:?) fixture expected exit 1 (violation), got $GUARD_RC: $GUARD_OUT"; fi
if grep -q 'banned-colon-q.sh:4:' <<<"$GUARD_OUT"; then pass "RED-A cites the offender at its TRUE line (banned-colon-q.sh:4)"; else fail "RED-A mis-cited the offender line (expected banned-colon-q.sh:4): $GUARD_OUT"; fi

# --- RED-B (colon-less `?`): executable `${BAR?msg}` -> non-zero (proves :?\? breadth) ---
d=$(mkcase red_b)
cat >"$d/banned-colonless-q.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
echo "${BAR?BAR must be set}"
EOF
run_guard "$d"
if (( GUARD_RC == 1 )); then pass "RED-B (colon-less \${BAR?}) fixture -> exit 1 (a :?-only regex would MISS this)"; else fail "RED-B colon-less fixture expected exit 1, got $GUARD_RC -- regex too narrow or wrong exit"; fi
if grep -q 'banned-colonless-q.sh:3:' <<<"$GUARD_OUT"; then pass "RED-B cites the colon-less offender at its TRUE line (banned-colonless-q.sh:3)"; else fail "RED-B mis-cited the offender line (expected banned-colonless-q.sh:3): $GUARD_OUT"; fi

# --- COMMENT-GREEN: banned form only inside a FULL-LINE comment -> exit 0 ---
d=$(mkcase comment)
cat >"$d/comment-only.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
# Deliberately NOT `: "${FOO:?msg}"` -- under a non-interactive shell that aborts status 1.
   # Also indented: never `${BAR?msg}` either.
if [[ -z "${FOO:-}" ]]; then echo "TRANSIENT: FOO not set" >&2; exit 2; fi
EOF
run_guard "$d"
if (( GUARD_RC == 0 )); then pass "COMMENT-GREEN full-line-comment fixture -> exit 0 (strip works)"; else fail "COMMENT-GREEN fixture expected exit 0, got $GUARD_RC: $GUARD_OUT"; fi

# Guard against a vacuous comment-strip: prove the comment fixture WOULD trip if the banned
# form were on an executable line (mutate it, re-run, expect non-zero).
d=$(mkcase comment_mutated)
cat >"$d/comment-mutated.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
: "${FOO:?msg}"
EOF
run_guard "$d"
if (( GUARD_RC != 0 )); then pass "COMMENT mutation control: same form on executable line -> non-zero"; else fail "COMMENT mutation control expected non-zero, got 0"; fi

# --- INLINE-COMMENT CONTRACT: the strip is FULL-LINE-only by design. A banned form in a TRAILING
# comment on an executable line is conservatively FLAGGED (fail-CLOSED) -- authors document the ban
# in full-line comments. This pins the current behavior so it is a documented contract, not a
# silent surprise, and proves the guard never lets the banned token slip through on a code line
# (the same line could also carry a REAL banned expansion). #6757 review (3 agents concurred). ---
d=$(mkcase inline_comment)
cat >"$d/inline-comment.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
echo "running"  # historically we (wrongly) gated on ${FOO:?FOO must be set} here
EOF
run_guard "$d"
if (( GUARD_RC == 1 )); then pass "INLINE-COMMENT contract: banned form in a trailing comment is flagged (fail-closed, full-line strip only)"; else fail "INLINE-COMMENT contract expected exit 1 (fail-closed), got $GUARD_RC: $GUARD_OUT"; fi

# --- MISSING-DIR: a nonexistent target dir -> exit 2 (TRANSIENT/internal error, never a silent 0) ---
run_guard "$SANDBOX/does-not-exist"
if (( GUARD_RC == 2 )); then pass "MISSING-DIR -> exit 2 (internal error, not a vacuous 0)"; else fail "MISSING-DIR expected exit 2, got $GUARD_RC: $GUARD_OUT"; fi

# --- FLOOR: a production run whose probe count is below the min-cardinality floor -> exit 2.
# Force the breach on the REAL tree via the test-only VARQ_BAN_MIN_PROBES override (set above the
# ~41 real probes). Proves the anti-vacuity floor actually FIRES -- neutering it (e.g. `scanned < 0`)
# ships green without this case. #6757 review MEDIUM. ---
FLOOR_OUT="$(VARQ_BAN_MIN_PROBES=100000 bash "$GUARD" 2>&1)"; FLOOR_RC=$?
if (( FLOOR_RC == 2 )); then pass "FLOOR breach (min-cardinality) -> exit 2"; else fail "FLOOR breach expected exit 2, got $FLOOR_RC: $FLOOR_OUT"; fi
if grep -q 'expected the full set' <<<"$FLOOR_OUT"; then pass "FLOOR breach emits the broken-glob diagnostic"; else fail "FLOOR breach did not emit the expected diagnostic: $FLOOR_OUT"; fi

# --- LIVE-GREEN: production run (no arg) over the real tree -> exit 0 (post-conversion) ---
LIVE_OUT="$(bash "$GUARD" 2>&1)"; LIVE_RC=$?
if (( LIVE_RC == 0 )); then pass "LIVE production run over real tree -> exit 0"; else fail "LIVE production run expected exit 0, got $LIVE_RC: $LIVE_OUT"; fi

if (( fails == 0 )); then
  echo "PASSED"
  exit 0
fi
echo "FAILED: $fails" >&2
exit 1
