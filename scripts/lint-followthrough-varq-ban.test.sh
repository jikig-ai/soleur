#!/usr/bin/env bash
# Mutation test for scripts/lint-followthrough-varq-ban.sh (#6757) -- the NON-VACUITY core.
#
# Drives the ACTUAL Phase-1 guard (never a re-implementation) over a mktemp sandbox of
# synthesized fixtures, asserting BOTH directions so every assertion can fail:
#   GREEN            compliant `if [[ -z "${VAR:-}" ]]` fixture   -> guard exits 0
#   RED-A (:?)       executable `: "${FOO:?msg}"`                 -> guard exits NON-ZERO + names file
#   RED-B (colon-)   executable `${BAR?msg}`                      -> guard exits NON-ZERO (proves :?\? breadth)
#   COMMENT-GREEN    banned form in a FULL-LINE `#` comment only  -> guard exits 0 (proves the strip)
#   LIVE-GREEN       production run (no arg) over the real tree   -> guard exits 0 (post-conversion)
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

# --- RED-A (:?): executable `: "${FOO:?msg}"` -> non-zero AND names the file ---
d=$(mkcase red_a)
cat >"$d/banned-colon-q.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
: "${FOO:?FOO must be set}"
echo "ok"
EOF
run_guard "$d"
if (( GUARD_RC != 0 )); then pass "RED-A (:?) fixture -> exit $GUARD_RC (non-zero)"; else fail "RED-A (:?) fixture expected non-zero, got 0"; fi
if grep -q 'banned-colon-q.sh' <<<"$GUARD_OUT"; then pass "RED-A names the offending file"; else fail "RED-A did not name the offending file: $GUARD_OUT"; fi

# --- RED-B (colon-less `?`): executable `${BAR?msg}` -> non-zero (proves :?\? breadth) ---
d=$(mkcase red_b)
cat >"$d/banned-colonless-q.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
echo "${BAR?BAR must be set}"
EOF
run_guard "$d"
if (( GUARD_RC != 0 )); then pass "RED-B (colon-less \${BAR?}) fixture -> exit $GUARD_RC (a :?-only regex would MISS this)"; else fail "RED-B colon-less fixture expected non-zero, got 0 -- regex is too narrow"; fi

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

# --- LIVE-GREEN: production run (no arg) over the real tree -> exit 0 (post-conversion) ---
LIVE_OUT="$(bash "$GUARD" 2>&1)"; LIVE_RC=$?
if (( LIVE_RC == 0 )); then pass "LIVE production run over real tree -> exit 0"; else fail "LIVE production run expected exit 0, got $LIVE_RC: $LIVE_OUT"; fi

if (( fails == 0 )); then
  echo "PASSED"
  exit 0
fi
echo "FAILED: $fails" >&2
exit 1
