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
# RULE 2 (#7946) -- the retired-credential-name ban. Same guard, second walk, its own counter:
#   R2-M1  the retired name on an executable line of one .sh    -> exit 1, cites file AT TRUE LINE
#   R2-M2  a second file after the first is compliant             -> exit 1, cites BOTH (walk does not stop)
#   R2-M3  the retired name in a .test.sh only                    -> exit 1 (rule 2 walks test files; rule 1 skips them)
#   R2-M4  the retired name in a FULL-LINE comment only           -> exit 1 (a comment is what the next author copies)
#   R2-M5  sandbox COPY of the guard with rule 2's walk emptied,   -> exit 2, diagnostic names rule 2 (its OWN floor
#          run against the production tree                           fires; rule 1's `scanned` is untouched)
#   R2-H2  must-PASS non-canonical: the NEW name + a Better Stack  -> exit 0
#          name + a comment about "the sweeper's Sentry secret"
#   R2-H3  must-PASS: an EMPTY sandbox dir                         -> exit 0 (pins the sandbox floor exemption)
#   R2-H4  must-PASS: the live tree, counts parsed                 -> rule 1's N >= 10, rule 2's count >= N
#
# ADR-193 floor: `asserted` moves at the CALL SITE (check()), never inside pass()/fail(); the
# conservation identity and MIN_ASSERTIONS are reported with printf + exit 1, never via fail().
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

passes=0
fails=0
asserted=0
pass() { passes=$((passes + 1)); printf '  ✓ %s\n' "$1"; }
fail() { fails=$((fails + 1)); printf '  ✗ %s\n' "$1" >&2; }
# check <ok:0|nonzero> <pass-msg> <fail-msg> -- the ONE call site of pass()/fail(); `asserted`
# moves here so a neutered verdict helper drops the verdict without dropping the count.
check() { asserted=$((asserted + 1)); if [[ "$1" == "0" ]]; then pass "$2"; else fail "$3"; fi; }

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
(( GUARD_RC == 0 )); check $? "GREEN compliant fixture -> exit 0" "GREEN compliant fixture expected exit 0, got $GUARD_RC: $GUARD_OUT"

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
(( GUARD_RC == 1 )); check $? "RED-A (:?) fixture -> exit 1 (violation)" "RED-A (:?) fixture expected exit 1 (violation), got $GUARD_RC: $GUARD_OUT"
grep -q 'banned-colon-q.sh:4:' <<<"$GUARD_OUT"; check $? "RED-A cites the offender at its TRUE line (banned-colon-q.sh:4)" "RED-A mis-cited the offender line (expected banned-colon-q.sh:4): $GUARD_OUT"

# --- RED-B (colon-less `?`): executable `${BAR?msg}` -> non-zero (proves :?\? breadth) ---
d=$(mkcase red_b)
cat >"$d/banned-colonless-q.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
echo "${BAR?BAR must be set}"
EOF
run_guard "$d"
(( GUARD_RC == 1 )); check $? "RED-B (colon-less \${BAR?}) fixture -> exit 1 (a :?-only regex would MISS this)" "RED-B colon-less fixture expected exit 1, got $GUARD_RC -- regex too narrow or wrong exit"
grep -q 'banned-colonless-q.sh:3:' <<<"$GUARD_OUT"; check $? "RED-B cites the colon-less offender at its TRUE line (banned-colonless-q.sh:3)" "RED-B mis-cited the offender line (expected banned-colonless-q.sh:3): $GUARD_OUT"

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
(( GUARD_RC == 0 )); check $? "COMMENT-GREEN full-line-comment fixture -> exit 0 (strip works)" "COMMENT-GREEN fixture expected exit 0, got $GUARD_RC: $GUARD_OUT"

# Guard against a vacuous comment-strip: prove the comment fixture WOULD trip if the banned
# form were on an executable line (mutate it, re-run, expect non-zero).
d=$(mkcase comment_mutated)
cat >"$d/comment-mutated.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
: "${FOO:?msg}"
EOF
run_guard "$d"
(( GUARD_RC != 0 )); check $? "COMMENT mutation control: same form on executable line -> non-zero" "COMMENT mutation control expected non-zero, got 0"

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
(( GUARD_RC == 1 )); check $? "INLINE-COMMENT contract: banned form in a trailing comment is flagged (fail-closed, full-line strip only)" "INLINE-COMMENT contract expected exit 1 (fail-closed), got $GUARD_RC: $GUARD_OUT"

# --- MISSING-DIR: a nonexistent target dir -> exit 2 (TRANSIENT/internal error, never a silent 0) ---
run_guard "$SANDBOX/does-not-exist"
(( GUARD_RC == 2 )); check $? "MISSING-DIR -> exit 2 (internal error, not a vacuous 0)" "MISSING-DIR expected exit 2, got $GUARD_RC: $GUARD_OUT"

# --- FLOOR: a production run whose probe count is below the min-cardinality floor -> exit 2.
# Force the breach on the REAL tree via the test-only VARQ_BAN_MIN_PROBES override (set above the
# ~41 real probes). Proves the anti-vacuity floor actually FIRES -- neutering it (e.g. `scanned < 0`)
# ships green without this case. #6757 review MEDIUM. ---
FLOOR_OUT="$(VARQ_BAN_MIN_PROBES=100000 bash "$GUARD" 2>&1)"; FLOOR_RC=$?
(( FLOOR_RC == 2 )); check $? "FLOOR breach (min-cardinality) -> exit 2" "FLOOR breach expected exit 2, got $FLOOR_RC: $FLOOR_OUT"
grep -q 'expected the full set' <<<"$FLOOR_OUT"; check $? "FLOOR breach emits the broken-glob diagnostic" "FLOOR breach did not emit the expected diagnostic: $FLOOR_OUT"

# --- LIVE-GREEN: production run (no arg) over the real tree -> exit 0 (post-conversion) ---
LIVE_OUT="$(bash "$GUARD" 2>&1)"; LIVE_RC=$?
(( LIVE_RC == 0 )); check $? "LIVE production run over real tree -> exit 0" "LIVE production run expected exit 0, got $LIVE_RC: $LIVE_OUT"


# =======================================================================================
# RULE 2 (#7946): the retired credential name `SENTRY_AUTH_TOKEN` may not appear anywhere
# under scripts/followthroughs/ -- executable line, comment, .sh or .test.sh. The name is the
# one a workstation `doppler run -c prd_terraform` binds to a PERSONAL token.
# =======================================================================================
RETIRED='SENTRY_AUTH_TOKEN'

# --- R2-M1: retired name on an executable line -> exit 1, cited at its true line ---
d=$(mkcase r2_m1)
cat >"$d/probe-old-name.sh" <<EOF
#!/usr/bin/env bash
set -uo pipefail
# a comment line so the offender is NOT line 3
if [[ -z "\${${RETIRED}:-}" ]]; then echo "TRANSIENT: token not set" >&2; exit 2; fi
EOF
run_guard "$d"
(( GUARD_RC == 1 )); check $? "R2-M1 retired name on an executable line -> exit 1" "R2-M1 expected exit 1, got $GUARD_RC: $GUARD_OUT"
grep -q 'probe-old-name.sh:4:' <<<"$GUARD_OUT"; check $? "R2-M1 cites the offender at its TRUE line (probe-old-name.sh:4)" "R2-M1 mis-cited the offender line (expected probe-old-name.sh:4): $GUARD_OUT"
grep -q 'SENTRY_ACTIONS_RO_TOKEN' <<<"$GUARD_OUT"; check $? "R2-M1 diagnostic names the replacement" "R2-M1 diagnostic does not name the replacement: $GUARD_OUT"

# --- R2-M2: a SECOND offender after a compliant file -> both cited (the walk does not stop) ---
d=$(mkcase r2_m2)
cat >"$d/a-compliant.sh" <<'EOF'
#!/usr/bin/env bash
if [[ -z "${SENTRY_ACTIONS_RO_TOKEN:-}" ]]; then echo "TRANSIENT" >&2; exit 2; fi
EOF
cat >"$d/b-old.sh" <<EOF
#!/usr/bin/env bash
TOK="\$${RETIRED}"
EOF
cat >"$d/c-old.sh" <<EOF
#!/usr/bin/env bash
echo "x"
: "\${${RETIRED}:-}"
EOF
run_guard "$d"
(( GUARD_RC == 1 )); check $? "R2-M2 two offenders -> exit 1" "R2-M2 expected exit 1, got $GUARD_RC: $GUARD_OUT"
grep -q 'b-old.sh:2:' <<<"$GUARD_OUT" && grep -q 'c-old.sh:3:' <<<"$GUARD_OUT"; check $? "R2-M2 cites BOTH offenders (b-old.sh:2, c-old.sh:3)" "R2-M2 did not cite both offenders: $GUARD_OUT"

# --- R2-M3: retired name in a .test.sh ONLY -> exit 1 (rule 2 walks test files; rule 1 skips them) ---
d=$(mkcase r2_m3)
cat >"$d/probe.sh" <<'EOF'
#!/usr/bin/env bash
if [[ -z "${SENTRY_ACTIONS_RO_TOKEN:-}" ]]; then echo "TRANSIENT" >&2; exit 2; fi
EOF
cat >"$d/probe.test.sh" <<EOF
#!/usr/bin/env bash
out="\$(${RETIRED}=stub bash probe.sh)"
EOF
run_guard "$d"
(( GUARD_RC == 1 )); check $? "R2-M3 retired name in a .test.sh only -> exit 1 (rule 2 walks test files)" "R2-M3 expected exit 1, got $GUARD_RC: $GUARD_OUT"
grep -q 'probe.test.sh:2:' <<<"$GUARD_OUT"; check $? "R2-M3 cites the .test.sh at its true line" "R2-M3 did not cite probe.test.sh:2: $GUARD_OUT"

# --- R2-M4: retired name in a FULL-LINE comment only -> exit 1 (comments are what get copied) ---
d=$(mkcase r2_m4)
cat >"$d/probe-comment.sh" <<EOF
#!/usr/bin/env bash
set -uo pipefail
# the sweeper forwards ${RETIRED} from its env: block
if [[ -z "\${SENTRY_ACTIONS_RO_TOKEN:-}" ]]; then echo "TRANSIENT" >&2; exit 2; fi
EOF
run_guard "$d"
(( GUARD_RC == 1 )); check $? "R2-M4 retired name in a full-line comment -> exit 1 (rule 2 does NOT strip comments)" "R2-M4 expected exit 1, got $GUARD_RC: $GUARD_OUT"
grep -q 'probe-comment.sh:3:' <<<"$GUARD_OUT"; check $? "R2-M4 cites the comment line (probe-comment.sh:3)" "R2-M4 did not cite probe-comment.sh:3: $GUARD_OUT"

# --- R2-M5: DISPATCH row. A sandbox COPY of the guard with rule 2's walk emptied, run against the
# production tree, must exit 2 with a diagnostic naming rule 2 -- rule 2's OWN floor fires, and
# rule 1's `scanned` (untouched by the mutation) must not be what fires. ---
MUT="$SANDBOX/guard-rule2-emptied.sh"
sed 's|"\$TARGET_DIR"/\*\.sh; do  # rule2-walk|"$TARGET_DIR"/*.nomatch-7946; do  # rule2-walk|' "$GUARD" >"$MUT"
if diff -q "$GUARD" "$MUT" >/dev/null; then
  check 1 "" "R2-M5 mutation did NOT land (no '# rule2-walk' marker in the guard) -- the row would be vacuous"
else
  M5_OUT="$(bash "$MUT" 2>&1)"; M5_RC=$?
  (( M5_RC == 2 )); check $? "R2-M5 rule 2's walk emptied on the production tree -> exit 2" "R2-M5 expected exit 2, got $M5_RC: $M5_OUT"
  grep -qi 'rule 2' <<<"$M5_OUT"; check $? "R2-M5 diagnostic names rule 2 (its own floor fired, not rule 1's)" "R2-M5 diagnostic does not name rule 2: $M5_OUT"
  ! grep -q 'expected the full set' <<<"$M5_OUT"; check $? "R2-M5 rule 1's broken-glob diagnostic did NOT fire (its walk was untouched)" "R2-M5 rule 1's floor fired on a rule-2 mutation: $M5_OUT"
fi

# --- R2-H2: must-PASS, not the canonical: the NEW name + a Better Stack name + prose about the
# sweeper's Sentry secret that never spells the retired literal -> exit 0 ---
d=$(mkcase r2_h2)
cat >"$d/probe-new.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
# The sweeper's Sentry secret is the read-only actions integration token (ADR-031).
if [[ -z "${SENTRY_ACTIONS_RO_TOKEN:-}" ]]; then echo "TRANSIENT: token not set" >&2; exit 2; fi
if [[ -z "${BETTERSTACK_API_TOKEN:-}" ]]; then echo "TRANSIENT: bs token not set" >&2; exit 2; fi
echo "ok"
EOF
run_guard "$d"
(( GUARD_RC == 0 )); check $? "R2-H2 new name + Better Stack name + prose -> exit 0" "R2-H2 expected exit 0, got $GUARD_RC: $GUARD_OUT"

# --- R2-H3: must-PASS: an EMPTY sandbox -> exit 0 (the floor keys on the RESOLVED default dir,
# so a mktemp sandbox is exempt; a later "fix" that fires the floor in sandboxes breaks THIS row) ---
d=$(mkcase r2_h3_empty)
run_guard "$d"
(( GUARD_RC == 0 )); check $? "R2-H3 empty sandbox -> exit 0 (sandbox floor exemption pinned)" "R2-H3 expected exit 0 on an empty sandbox, got $GUARD_RC: $GUARD_OUT"

# --- R2-H4: the live tree, counts PARSED: rule 1's N at or above the Phase 0.1 reading (70 on
# 2026-09-11) is a LOWER bound so new probes never trip it; rule 2's count covers at least N
# (it also walks .test.sh). Reuses LIVE_OUT from the LIVE-GREEN case above. ---
n1="$(grep -oE '[0-9]+ probe\(s\) scanned' <<<"$LIVE_OUT" | grep -oE '^[0-9]+' || echo 0)"
n2="$(grep -oE 'retired-name rule checked [0-9]+' <<<"$LIVE_OUT" | grep -oE '[0-9]+$' || echo 0)"
[[ "$n1" =~ ^[0-9]+$ && "$n1" -ge 10 ]]; check $? "R2-H4 live tree: rule 1 scanned $n1 probe(s) (>= 10)" "R2-H4 rule 1 count unparseable or below floor: n1='$n1' out=$LIVE_OUT"
[[ "$n2" =~ ^[0-9]+$ && "$n2" -ge "$n1" && "$n2" -gt 0 ]]; check $? "R2-H4 live tree: rule 2 checked $n2 file(s) (>= rule 1's $n1)" "R2-H4 rule 2 count unparseable or below rule 1's: n2='$n2' n1='$n1' out=$LIVE_OUT"

# --- Accounting (ADR-193). Emitted DIRECTLY, never through fail(): a conservation check routed
# through the verdict helper it polices cannot report the fault that corrupted it. ---
if (( passes + fails != asserted )); then
  printf '\n[FATAL] accounting: passes+fails (%d) != asserted (%d) -- a verdict was dropped or a call site lacks its increment\n' \
    "$((passes + fails))" "$asserted" >&2
  exit 1
fi

# Absolute floor at the MEASURED green count; a lower bound, so adding rows never trips it --
# re-measure and raise it in the same commit that adds a row. Reported with printf + exit 1,
# never via fail(), so one edit cannot disarm both.
MIN_ASSERTIONS=32
if (( asserted < MIN_ASSERTIONS )); then
  printf '[FATAL] only %d assertions ran; floor is %d -- the suite was gutted\n' "$asserted" "$MIN_ASSERTIONS" >&2
  exit 1
fi

printf '\n=== %d passed, %d failed (%d asserted, floor %d) ===\n' "$passes" "$fails" "$asserted" "$MIN_ASSERTIONS"
if (( fails == 0 )); then
  echo "PASSED"
  exit 0
fi
echo "FAILED: $fails" >&2
exit 1
