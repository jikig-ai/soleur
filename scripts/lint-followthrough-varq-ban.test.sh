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
#   R2-M5  DISPATCH: guard COPY with the rule-2 grep line deleted,  -> exit 0 on the M1 fixture (the grep IS the mechanism)
#   R2-M6  guard COPY with rule 2's file count forced to 0, run      -> exit 2, diagnostic names rule 2 (its OWN floor
#          against the production tree                               fires; rule 1's `scanned` is untouched)
#   R2-M7  two hits in ONE file                                      -> exit 1, BOTH lines cited (the read loop does not stop)
#   R2-M8  a SUPERSTRING of the name (`MY_SENTRY_AUTH_TOKEN`)        -> exit 1 (the ban is on the substring, on purpose)
#   R2-M9  the name in a NON-.sh file in a SUBDIRECTORY              -> exit 1 (any file, any depth)
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
declare -a FAILURES=()   # append-only ledger the verdict reads; see the instrument self-test below
fails=0
asserted=0
pass() { passes=$((passes + 1)); printf '  ✓ %s\n' "$1"; }
fail() { fails=$((fails + 1)); FAILURES+=("$1"); printf '  ✗ %s\n' "$1" >&2; }
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
RETIRED_NAME='SENTRY_AUTH_TOKEN'  # the same constant the guard carries

# --- R2-M1: retired name on an executable line -> exit 1, cited at its true line ---
d=$(mkcase r2_m1)
cat >"$d/probe-old-name.sh" <<EOF
#!/usr/bin/env bash
set -uo pipefail
# a comment line so the offender is NOT line 3
if [[ -z "\${${RETIRED_NAME}:-}" ]]; then echo "TRANSIENT: token not set" >&2; exit 2; fi
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
TOK="\$${RETIRED_NAME}"
EOF
cat >"$d/c-old.sh" <<EOF
#!/usr/bin/env bash
echo "x"
: "\${${RETIRED_NAME}:-}"
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
cat >"$d/probe-1234.test.sh" <<EOF
#!/usr/bin/env bash
out="\$(${RETIRED_NAME}=stub bash probe.sh)"
EOF
run_guard "$d"
(( GUARD_RC == 1 )); check $? "R2-M3 retired name in a .test.sh only -> exit 1 (rule 2 walks test files)" "R2-M3 expected exit 1, got $GUARD_RC: $GUARD_OUT"
grep -q 'probe-1234.test.sh:2:' <<<"$GUARD_OUT"; check $? "R2-M3 cites the .test.sh at its true line" "R2-M3 did not cite probe-1234.test.sh:2: $GUARD_OUT"

# --- R2-M4: retired name in a FULL-LINE comment only -> exit 1 (comments are what get copied) ---
d=$(mkcase r2_m4)
cat >"$d/probe-comment.sh" <<EOF
#!/usr/bin/env bash
set -uo pipefail
# the sweeper forwards ${RETIRED_NAME} from its env: block
if [[ -z "\${SENTRY_ACTIONS_RO_TOKEN:-}" ]]; then echo "TRANSIENT" >&2; exit 2; fi
EOF
run_guard "$d"
(( GUARD_RC == 1 )); check $? "R2-M4 retired name in a full-line comment -> exit 1 (rule 2 does NOT strip comments)" "R2-M4 expected exit 1, got $GUARD_RC: $GUARD_OUT"
grep -q 'probe-comment.sh:3:' <<<"$GUARD_OUT"; check $? "R2-M4 cites the comment line (probe-comment.sh:3)" "R2-M4 did not cite probe-comment.sh:3: $GUARD_OUT"

# --- R2-M5: DISPATCH row. A sandbox COPY of the guard with the rule-2 grep line DELETED, run
# against the M1 fixture, exits 0: the grep is the mechanism, and nothing else in the guard
# vouches for it. ---
MUT="$SANDBOX/guard-rule2-grep-deleted.sh"
sed '/# rule2-grep$/d' "$GUARD" >"$MUT"
if diff -q "$GUARD" "$MUT" >/dev/null; then
  check 1 "" "R2-M5 mutation did NOT land (no '# rule2-grep' marker in the guard) -- the row would be vacuous"
else
  d=$(mkcase r2_m5)
  cat >"$d/probe-old-name.sh" <<EOF
#!/usr/bin/env bash
if [[ -z "\${${RETIRED_NAME}:-}" ]]; then echo "TRANSIENT" >&2; exit 2; fi
EOF
  M5_OUT="$(bash "$MUT" "$d" 2>&1)"; M5_RC=$?
  (( M5_RC == 0 )); check $? "R2-M5 with the rule-2 grep deleted the M1 fixture passes (exit 0) -- the grep is the mechanism" "R2-M5 expected exit 0 on the mutant, got $M5_RC: $M5_OUT"
fi

# --- R2-M6: rule 2's OWN floor. A COPY with the rule-2 file count forced to 0, run against the
# production tree, exits 2 naming rule 2 -- and rule 1's `scanned` (untouched) is not what fires. ---
MUT6="$SANDBOX/guard-rule2-count-zeroed.sh"
sed 's|^scanned_rule2=.*# rule2-count$|scanned_rule2=0  # rule2-count|' "$GUARD" >"$MUT6"
if diff -q "$GUARD" "$MUT6" >/dev/null; then
  check 1 "" "R2-M6 mutation did NOT land (no '# rule2-count' marker in the guard) -- the row would be vacuous"
else
  M6_OUT="$(bash "$MUT6" 2>&1)"; M6_RC=$?
  (( M6_RC == 2 )); check $? "R2-M6 rule 2's count zeroed on the production tree -> exit 2" "R2-M6 expected exit 2, got $M6_RC: $M6_OUT"
  grep -qi 'rule 2' <<<"$M6_OUT"; check $? "R2-M6 diagnostic names rule 2 (its own floor fired, not rule 1's)" "R2-M6 diagnostic does not name rule 2: $M6_OUT"
  ! grep -q 'expected the full set' <<<"$M6_OUT"; check $? "R2-M6 rule 1's broken-glob diagnostic did NOT fire (its walk was untouched)" "R2-M6 rule 1's floor fired on a rule-2 mutation: $M6_OUT"
fi

# --- R2-M7: two hits in ONE file -> both cited (the read loop does not stop at the first) ---
d=$(mkcase r2_m7)
cat >"$d/probe-two.sh" <<EOF
#!/usr/bin/env bash
# reads ${RETIRED_NAME}
: "\${${RETIRED_NAME}:-}"
EOF
run_guard "$d"
(( GUARD_RC == 1 )); check $? "R2-M7 two hits in one file -> exit 1" "R2-M7 expected exit 1, got $GUARD_RC: $GUARD_OUT"
grep -q 'probe-two.sh:2:' <<<"$GUARD_OUT" && grep -q 'probe-two.sh:3:' <<<"$GUARD_OUT"; check $? "R2-M7 BOTH lines cited (probe-two.sh:2 and :3)" "R2-M7 did not cite both lines: $GUARD_OUT"

# --- R2-M8: a SUPERSTRING of the name is caught: the ban is on the substring, so a prefixed or
# suffixed variant cannot smuggle the personal binding back in under a new spelling. ---
d=$(mkcase r2_m8)
cat >"$d/probe-super.sh" <<EOF
#!/usr/bin/env bash
: "\${MY_${RETIRED_NAME}_V2:-}"
EOF
run_guard "$d"
(( GUARD_RC == 1 )); check $? "R2-M8 a superstring of the retired name -> exit 1 (substring ban)" "R2-M8 expected exit 1, got $GUARD_RC: $GUARD_OUT"

# --- R2-M9: the name in a NON-.sh file inside a SUBDIRECTORY -> exit 1 (any file, any depth).
# The pre-review walk was a top-level `*.sh` glob; a fixture under `fixtures/` was invisible. ---
d=$(mkcase r2_m9)
mkdir -p "$d/fixtures"
cat >"$d/probe.sh" <<'EOF'
#!/usr/bin/env bash
if [[ -z "${SENTRY_ACTIONS_RO_TOKEN:-}" ]]; then echo "TRANSIENT" >&2; exit 2; fi
EOF
printf 'env: %s=stub\n' "${RETIRED_NAME}" >"$d/fixtures/env.yml"
run_guard "$d"
(( GUARD_RC == 1 )); check $? "R2-M9 the name in fixtures/env.yml (non-.sh, one level down) -> exit 1" "R2-M9 expected exit 1, got $GUARD_RC: $GUARD_OUT"
grep -q 'fixtures/env.yml:1:' <<<"$GUARD_OUT"; check $? "R2-M9 cites the nested file at its true line" "R2-M9 did not cite fixtures/env.yml:1: $GUARD_OUT"

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
[[ "$n2" =~ ^[0-9]+$ && "$n2" -gt "$n1" ]]; check $? "R2-H4 live tree: rule 2 checked $n2 file(s) (> rule 1's $n1: the .test.sh files rule 1 skips)" "R2-H4 rule 2 count unparseable or not above rule 1's: n2='$n2' n1='$n1' out=$LIVE_OUT"


# =============================================================================
# RULE 3 (#7490) -- the PROBE REPO-PATH EXISTENCE check. Every row below is named in the
# Guard 1 mutation matrix of the plan and appears by name in this suite's PASS output.
#
# The fixture sandbox is OUTSIDE scripts/followthroughs/, so the resolution base (the repo
# root) and the scan base (TARGET_DIR) are genuinely different directories -- which is what
# rows R3-M9 and R3-M10 exist to pin. A suite whose sandbox sat inside the repo's own probe
# directory could not tell the two bases apart.
# =============================================================================

# helper: write a probe fixture carrying ONE path assignment, in a named arm's shape.
r3_fixture() {  # r3_fixture <dir> <basename> <assignment-line>
  cat >"$1/$2" <<EOF
#!/usr/bin/env bash
set -uo pipefail
$3
echo ok
EOF
}

# --- R3-M1: an absent literal repo-relative path -> exit 1, cited as MISSING with the path ---
d=$(mkcase r3_m1)
r3_fixture "$d" probe-a.sh 'REPORTS="knowledge-base/project/specs/nope/upstream-reports.md"'
run_guard "$d"
(( GUARD_RC == 1 )); check $? "R3-M1 absent literal repo path -> exit 1" "R3-M1 expected exit 1, got $GUARD_RC: $GUARD_OUT"
grep -q 'rule 3: MISSING' <<<"$GUARD_OUT"; check $? "R3-M1 diagnostic is cited as 'rule 3: MISSING'" "R3-M1 diagnostic lacks the MISSING citation: $GUARD_OUT"
grep -q 'knowledge-base/project/specs/nope/upstream-reports.md' <<<"$GUARD_OUT"; check $? "R3-M1 diagnostic names the offending PATH" "R3-M1 diagnostic omits the path: $GUARD_OUT"
grep -q 'probe-a.sh:3:' <<<"$GUARD_OUT"; check $? "R3-M1 diagnostic cites the TRUE line (3), not a re-indexed one" "R3-M1 wrong line citation: $GUARD_OUT"

# --- R3-M2 / R3-M3: the REF floor is what the override drives, and row 3 proves row 2 measures
# the floor rather than the tree. Both run the PRODUCTION tree (no arg). ---
M2_OUT="$(REPO_PATHS_MIN_REFS=100000 bash "$GUARD" 2>&1)"; M2_RC=$?
(( M2_RC == 2 )); check $? "R3-M2 production run with REPO_PATHS_MIN_REFS above the census -> exit 2" "R3-M2 expected exit 2, got $M2_RC: $M2_OUT"
grep -q 'census REGEX is broken' <<<"$M2_OUT"; check $? "R3-M2 the REF floor fired (diagnostic names the regex, not the glob)" "R3-M2 wrong floor fired: $M2_OUT"
M3_OUT="$(bash "$GUARD" 2>&1)"; M3_RC=$?
(( M3_RC == 0 )); check $? "R3-M3 must-PASS: same production run with the override unset -> exit 0" "R3-M3 expected exit 0, got $M3_RC: $M3_OUT"

# --- R3-M4: a COPY with the census regex neutered. Every file is still walked, so the FILE
# floor cannot see it; only the REF floor can. A broken glob and a broken regex are different
# vacuity modes and the messages must say which. ---
MUT4="$SANDBOX/guard-rule3-census-neutered.sh"
sed 's|^\(  done < <(awk -v TOPDIRS="\$TOPDIRS" "\$RULE3_AWK" "\$f")\)   # rule3-census$|  done < <(true)   # rule3-census|' "$GUARD" >"$MUT4"
if diff -q "$GUARD" "$MUT4" >/dev/null; then
  check 1 "" "R3-M4 mutation did NOT land (no '# rule3-census' marker in the guard) -- the row would be vacuous"
else
  M4_OUT="$(bash "$MUT4" 2>&1)"; M4_RC=$?
  (( M4_RC == 2 )); check $? "R3-M4 census regex neutered on the production tree -> exit 2" "R3-M4 expected exit 2, got $M4_RC: $M4_OUT"
  grep -q 'census REGEX is broken' <<<"$M4_OUT"; check $? "R3-M4 the REF floor fired, naming the regex" "R3-M4 wrong floor: $M4_OUT"
  ! grep -q 'the GLOB or path is broken' <<<"$M4_OUT"; check $? "R3-M4 the FILE floor did NOT fire (the walk was untouched)" "R3-M4 the file floor fired on a regex mutation: $M4_OUT"
fi

# --- R3-M5: the SECOND member of a two-file sandbox is checked (the walk does not stop) ---
d=$(mkcase r3_m5)
r3_fixture "$d" probe-ok.sh 'Q="scripts/betterstack-query.sh"'
r3_fixture "$d" probe-bad.sh 'Q="scripts/does-not-exist-7490.sh"'
run_guard "$d"
(( GUARD_RC == 1 )); check $? "R3-M5 a clean first file does not excuse an absent second -> exit 1" "R3-M5 expected exit 1, got $GUARD_RC: $GUARD_OUT"
grep -q 'probe-bad.sh' <<<"$GUARD_OUT"; check $? "R3-M5 the SECOND member is the one cited" "R3-M5 second member not cited: $GUARD_OUT"

# --- Arms. One row per shape the census must carry; each is the ONLY assignment in its file,
# so a row that stops matching goes RED on its own rather than hiding behind a sibling. ---
r3_arm() {  # r3_arm <row> <assignment> <label>
  local d; d=$(mkcase "r3_arm_$1")
  r3_fixture "$d" probe.sh "$2"
  run_guard "$d"
  (( GUARD_RC == 1 )); check $? "$1 $3 -> exit 1" "$1 expected exit 1, got $GUARD_RC: $GUARD_OUT"
}
r3_arm R3-M6  'X="${REPO_ROOT}/scripts/followthroughs/absent-7490.sh"'                  'braced ${VAR}/ arm'
r3_arm R3-M6b 'X="$REPO_ROOT/scripts/followthroughs/absent-7490.sh"'                    'bare $VAR/ arm (the corpus dominant shape)'
r3_arm R3-M7  'Q="${SOME_OVERRIDE:-${REPO_ROOT}/scripts/absent-7490.sh}"'               'braced :- default-expansion arm'
r3_arm R3-M7b 'Q="${SOME_OVERRIDE:-$REPO_ROOT/scripts/absent-7490.sh}"'                 'bare :- default-expansion arm (the live 7761 shape)'
r3_arm R3-M7c 'Q="${SOME_OVERRIDE:-scripts/absent-7490.sh}"'                            'literal :- default-expansion arm'
# R3-M7d: the SAME arm with a HYPHENATED first segment. The first implementation walked
# backwards to the nearest `-`, which is the `-` of `:-` only when segment one is hyphen-free,
# so `knowledge-base/` -- this repo's commonest repo-relative prefix -- yielded `base/...`,
# failed the tracked-top-dir test, and was dropped with NO diagnostic. A silent miss in the
# arm's own most likely shape, and invisible to R3-M7c because `scripts` has no hyphen.
r3_arm R3-M7d 'Q="${SOME_OVERRIDE:-knowledge-base/project/absent-7490.md}"'             'literal :- default, HYPHENATED first segment'
r3_arm R3-M8  'source "${REPO_ROOT}/scripts/lib/absent-7490.sh"'                        'source arm'

# R3-M7e (must-PASS): the same hyphenated shape pointing at a path that EXISTS. Without it,
# R3-M7d is equally satisfied by an arm that reports EVERY `knowledge-base/` default as missing.
d=$(mkcase r3_m7e)
r3_fixture "$d" probe.sh 'Q="${SOME_OVERRIDE:-knowledge-base/project/README.md}"'
run_guard "$d"
(( GUARD_RC == 0 )); check $? "R3-M7e must-PASS: a hyphenated-prefix default that EXISTS is not a miss" "R3-M7e expected exit 0, got $GUARD_RC: $GUARD_OUT"

# --- R3-M8b: `..`-relative is a DECLARED BLIND SPOT. The row pins the declaration either way:
# if a future revision normalises `..`, this must be re-decided deliberately, not drift. ---
d=$(mkcase r3_m8b)
r3_fixture "$d" probe.sh 'X="$SCRIPT_DIR/../lib/absent-7490.sh"'
run_guard "$d"
(( GUARD_RC == 0 )); check $? "R3-M8b '..'-relative path is ignored (DECLARED blind spot, named in the guard header)" "R3-M8b expected exit 0 (blind spot), got $GUARD_RC: $GUARD_OUT"

# --- R3-M9 (must-PASS) / R3-M10: the resolution base is the REPO ROOT, not TARGET_DIR. The two
# rows are a matched pair: M9 cites a path that exists at the repo root and NOT in the sandbox
# (must pass); M10 cites a path that exists in the SANDBOX and not at the repo root (must fail).
# Either row alone is satisfied by the wrong base. ---
d=$(mkcase r3_m9)
r3_fixture "$d" probe.sh 'S="scripts/sweep-followthroughs.sh"'
run_guard "$d"
(( GUARD_RC == 0 )); check $? "R3-M9 must-PASS: a repo-root-tracked path the sandbox lacks -> exit 0 (base is the repo root)" "R3-M9 expected exit 0, got $GUARD_RC: $GUARD_OUT"

d=$(mkcase r3_m10)
r3_fixture "$d" probe-local.sh 'S="scripts/followthroughs/probe-local.sh"'
run_guard "$d"
(( GUARD_RC == 1 )); check $? "R3-M10 a path present in the SANDBOX but absent at the repo root -> exit 1 (base is not TARGET_DIR)" "R3-M10 expected exit 1, got $GUARD_RC: $GUARD_OUT"

# --- R3-M11 (must-PASS): a URL, prose, and a grep pattern each carrying a repo-dir prefix are
# ignored -- AND the summary reports ZERO refs from that file. PASS alone cannot distinguish
# "correctly ignored" from "never walked", which is the whole point of asserting the count. ---
d=$(mkcase r3_m11)
cat >"$d/probe.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
URL="https://example.invalid/scripts/does-not-exist.sh"
MSG="see knowledge-base/project/nope.md for details"
PAT="scripts/followthroughs/[a-z]*\.sh"
echo "$URL $MSG $PAT"
EOF
run_guard "$d"
(( GUARD_RC == 0 )); check $? "R3-M11 must-PASS: URL / prose / grep-pattern values are not path literals -> exit 0" "R3-M11 expected exit 0, got $GUARD_RC: $GUARD_OUT"
r11_refs="$(grep -oE 'extracted [0-9]+ repo-path ref' <<<"$GUARD_OUT" | grep -oE '[0-9]+' || echo -1)"
[[ "$r11_refs" == "0" ]]; check $? "R3-M11 the summary reports 0 refs from that file (ignored, not merely walked)" "R3-M11 expected 0 refs, got '$r11_refs': $GUARD_OUT"

# --- R3-M12 (must-PASS): an existing tracked path inside SINGLE quotes. Quoting is permitted;
# the census keys on the value, not on which quote character wraps the assignment. ---
d=$(mkcase r3_m12)
r3_fixture "$d" probe.sh "S='scripts/sweep-followthroughs.sh'"
run_guard "$d"
(( GUARD_RC == 0 )); check $? "R3-M12 must-PASS: a tracked path in single quotes -> exit 0" "R3-M12 expected exit 0, got $GUARD_RC: $GUARD_OUT"

# --- R3-M13 (must-PASS): a sandbox holding ONLY a *.test.sh citing an absent gitignored path.
# Rule 1's exclusion is load-bearing here: ccla-representative-icla-7922.test.sh assigns a
# gitignored node_modules path that exists locally and NOT in the test-scripts CI shard. ---
d=$(mkcase r3_m13)
r3_fixture "$d" probe.sh 'S="scripts/sweep-followthroughs.sh"'
r3_fixture "$d" helper.test.sh 'TSX="node_modules/.bin/tsx"'
run_guard "$d"
(( GUARD_RC == 0 )); check $? "R3-M13 must-PASS: a *.test.sh is outside rule 3's census -> exit 0" "R3-M13 expected exit 0, got $GUARD_RC: $GUARD_OUT"

# --- R3-M14: one real miss on a production run exits 1 (NOT 2), and the summary's counts parse
# as integers with refs at or above the floor. Bounded, not pinned: a count assertion that
# pinned an exact number would red on every legitimate probe added. ---
d=$(mkcase r3_m14)
r3_fixture "$d" probe.sh 'X="scripts/absent-7490.sh"'
run_guard "$d"
(( GUARD_RC == 1 )); check $? "R3-M14 a single miss is exit 1 (a violation), never exit 2 (a broken walk)" "R3-M14 expected exit 1, got $GUARD_RC: $GUARD_OUT"
LIVE3="$(bash "$GUARD" 2>&1)"
l_files="$(grep -oE 'rule 3 walked [0-9]+' <<<"$LIVE3" | grep -oE '[0-9]+$' || echo -1)"
l_refs="$(grep -oE 'extracted [0-9]+ repo-path ref' <<<"$LIVE3" | grep -oE '[0-9]+' || echo -1)"
[[ "$l_files" =~ ^[0-9]+$ && "$l_files" -ge 70 ]]; check $? "R3-M14 live tree: rule 3 walked $l_files file(s) (>= its file floor)" "R3-M14 walked count unparseable or below floor: '$l_files': $LIVE3"
[[ "$l_refs" =~ ^[0-9]+$ && "$l_refs" -ge 40 ]]; check $? "R3-M14 live tree: rule 3 extracted $l_refs ref(s) (>= its ref floor)" "R3-M14 ref count unparseable or below floor: '$l_refs': $LIVE3"

# --- R3-M15: DISPATCH. A COPY with rule 3's `missing` increment deleted passes the M1 fixture:
# the COUNTER is the mechanism, not the walk. A guard that finds the miss and forgets to count
# it reports clean, and no other row can see that. ---
MUT15="$SANDBOX/guard-rule3-missing-deleted.sh"
sed 's|^      missing_rule3=\$((missing_rule3 + 1))   # rule3-missing$|      :   # rule3-missing|; s|^      violations=\$((violations + 1))$|      :|' "$GUARD" >"$MUT15"
if diff -q "$GUARD" "$MUT15" >/dev/null; then
  check 1 "" "R3-M15 mutation did NOT land (no '# rule3-missing' marker in the guard) -- the row would be vacuous"
else
  d=$(mkcase r3_m15)
  r3_fixture "$d" probe-a.sh 'REPORTS="knowledge-base/project/specs/nope/upstream-reports.md"'
  M15_OUT="$(bash "$MUT15" "$d" 2>&1)"; M15_RC=$?
  (( M15_RC == 0 )); check $? "R3-M15 with the missing counter deleted the M1 fixture passes -- the counter is the mechanism" "R3-M15 expected exit 0 on the mutant, got $M15_RC: $M15_OUT"
fi

# --- R3-M16: neither rule's floor vouches for the other. A rule-1 violation with rule 3 clean
# reddens alone, and the inverse reddens alone. (The rule-2 precedent, extended to rule 3.) ---
d=$(mkcase r3_m16a)
cat >"$d/probe.sh" <<'EOF'
#!/usr/bin/env bash
: "${FOO:?must be set}"
S="scripts/sweep-followthroughs.sh"
EOF
run_guard "$d"
# The per-violation DIAGNOSTIC lines are what carry the attribution; the trailing `FAILED:`
# summary names all three rules on every failure, so a negative assertion over the whole
# output can never hold. Strip the summary before asserting which rule fired.
r3_diag() { grep -v '^FAILED:' <<<"$GUARD_OUT"; }
(( GUARD_RC == 1 )) && r3_diag | grep -q 'banned' && ! r3_diag | grep -q 'rule 3: MISSING'
check $? "R3-M16a a rule-1 violation with rule 3 clean reddens on rule 1 alone" "R3-M16a expected a rule-1-only failure, got rc=$GUARD_RC: $GUARD_OUT"
d=$(mkcase r3_m16b)
cat >"$d/probe.sh" <<'EOF'
#!/usr/bin/env bash
if [[ -z "${FOO:-}" ]]; then echo "TRANSIENT" >&2; exit 2; fi
S="scripts/absent-7490.sh"
EOF
run_guard "$d"
(( GUARD_RC == 1 )) && r3_diag | grep -q 'rule 3: MISSING' && ! r3_diag | grep -qE 'banned \$\{VAR'
check $? "R3-M16b a rule-3 violation with rule 1 clean reddens on rule 3 alone" "R3-M16b expected a rule-3-only failure, got rc=$GUARD_RC: $GUARD_OUT"

# --- R3-M19: the `# repo-path: runtime` opt-out is per LINE, not per file. Two absent paths,
# only the FIRST annotated: the SECOND must still be cited. A file-scoped skip passes every
# other row in this matrix while silently exempting a real rot target. ---
d=$(mkcase r3_m19)
cat >"$d/probe.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
AFTER="scripts/followthroughs/written-at-runtime-7490.after"  # repo-path: runtime
REPORTS="knowledge-base/project/specs/nope/upstream-reports.md"
EOF
run_guard "$d"
(( GUARD_RC == 1 )); check $? "R3-M19 an annotated line does not exempt the rest of the file -> exit 1" "R3-M19 expected exit 1, got $GUARD_RC: $GUARD_OUT"
grep -q 'specs/nope/upstream-reports.md' <<<"$GUARD_OUT"; check $? "R3-M19 the UNANNOTATED second line is cited" "R3-M19 second line not cited: $GUARD_OUT"
! grep -q 'written-at-runtime-7490.after' <<<"$GUARD_OUT"; check $? "R3-M19 the ANNOTATED first line is NOT cited" "R3-M19 annotated line was cited: $GUARD_OUT"

# --- R3-M20 (must-PASS + its inverse): the annotation's real user on the LIVE tree. Removing
# the annotation from inngest-cutover-flip-rollout-7761.sh's AFTER_FILE line must red the tree;
# with it, the tree is green. Without the inverse this row cannot tell a working opt-out from a
# path that happens to exist. ---
LIVE20="$(bash "$GUARD" 2>&1)"; LIVE20_RC=$?
(( LIVE20_RC == 0 )); check $? "R3-M20 must-PASS: the live tree is clean with the AFTER_FILE annotation in place" "R3-M20 live tree not clean: $LIVE20"
R20_SB="$SANDBOX/r3_m20_probes"; mkdir -p "$R20_SB"
sed 's|  # repo-path: runtime.*$||' "$REPO_ROOT/scripts/followthroughs/inngest-cutover-flip-rollout-7761.sh" >"$R20_SB/inngest-cutover-flip-rollout-7761.sh"
if diff -q "$REPO_ROOT/scripts/followthroughs/inngest-cutover-flip-rollout-7761.sh" "$R20_SB/inngest-cutover-flip-rollout-7761.sh" >/dev/null; then
  check 1 "" "R3-M20 inverse: the annotation is absent from the live probe -- the opt-out has no user and the row is vacuous"
else
  run_guard "$R20_SB"
  (( GUARD_RC == 1 )); check $? "R3-M20 inverse: strip the annotation and the same probe reddens -- the opt-out is load-bearing" "R3-M20 inverse expected exit 1, got $GUARD_RC: $GUARD_OUT"
fi

# --- R3-M18: the live tree AFTER the repoint. Before it, plugin-delivery-canary-7490.sh was the
# miss this whole rule was written for; the assertion is that it is gone AND that the probe's
# current literal is the archive path (a repoint to some OTHER existing file would also clear
# the miss, and would be wrong). ---
grep -q 'specs/archive/.*feat-one-shot-7489-7490-marketplace-retire-delivery-followups/upstream-reports.md' "$REPO_ROOT/scripts/followthroughs/plugin-delivery-canary-7490.sh"
check $? "R3-M18 plugin-delivery-canary-7490.sh cites the ARCHIVE path (the repoint landed where it should)" "R3-M18 the canary does not cite the archive path"

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
# INSTRUMENT SELF-TEST -- drives check() through BOTH branches and requires every observable to
# move. The accounting identity and the floor below are NOT sufficient on their own, and the
# header's claim that `asserted` "moves at the call site so a neutered verdict helper drops the
# verdict without dropping the count" is true of pass()/fail() and FALSE of check() itself:
# `asserted` is incremented INSIDE check, so both backstops are dispatched through the one
# helper they exist to police. Measured 2026-09-18: `check() { asserted=$((asserted+1)); pass "$2"; }`
# -- a one-branch edit on the single call site of all 73 verdicts -- reported
# `=== 73 passed, 0 failed (73 asserted, floor 73) === PASSED`, exit 0, byte-identical to the
# honest run. So does `fail() { passes=$((passes+1)); ... }`. This block catches both.
_p=$passes _f=$fails _a=$asserted _n=${#FAILURES[@]}
if (( _n > 0 )); then _saved=("${FAILURES[@]}"); else _saved=(); fi
check 0 "self-test probe (pass branch)" "unreachable"
check 1 "unreachable" "self-test probe (fail branch; expected, unwound below)"
if (( passes != _p + 1 || fails != _f + 1 || asserted != _a + 2 || ${#FAILURES[@]} != _n + 1 )); then
  printf '[FATAL] instrument self-test: check() did not move every observable (passes %d->%d, fails %d->%d, asserted %d->%d, ledger %d->%d)\n' \
    "$_p" "$passes" "$_f" "$fails" "$_a" "$asserted" "$_n" "${#FAILURES[@]}" >&2
  exit 1
fi
passes=$_p; fails=$_f; asserted=$_a
if (( _n > 0 )); then FAILURES=("${_saved[@]}"); else FAILURES=(); fi

MIN_ASSERTIONS=73
if (( asserted < MIN_ASSERTIONS )); then
  printf '[FATAL] only %d assertions ran; floor is %d -- the suite was gutted\n' "$asserted" "$MIN_ASSERTIONS" >&2
  exit 1
fi

printf '\n=== %d passed, %d failed (%d asserted, floor %d) ===\n' "$passes" "$fails" "$asserted" "$MIN_ASSERTIONS"
# The verdict reads the append-only LEDGER, not the counter: a fail() whose increment is
# redirected to `passes` still leaves FAILURES populated, and the run still reds.
if (( fails == 0 && ${#FAILURES[@]} == 0 )); then
  echo "PASSED"
  exit 0
fi
printf 'FAILED: %d (ledger holds %d)\n' "$fails" "${#FAILURES[@]}" >&2
exit 1
