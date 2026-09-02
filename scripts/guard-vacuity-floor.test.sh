#!/usr/bin/env bash
# Meta-guard: anti-vacuity floors must survive a NEUTERED assertion machinery.
#
# WHY THIS EXISTS. A suite's anti-vacuity floor exists to notice "no assertions ran".
# Many enforced that floor by calling `fail`:
#
#     if [[ "$cases" -lt 75 ]]; then fail "vacuity guard: only $cases ..."; fi
#     ...
#     [[ "$fails" -eq 0 ]]
#
# `fail` increments `fails`, and the exit status reads `fails`. So the detector ran
# THROUGH the thing it detects: neuter `fail` — redefine it, break its arithmetic, lose
# its body to an editing slip — and every row goes quiet AND so does the floor that
# exists to notice the quiet. The suite prints a total and exits 0. A floor enforced
# through the suspect cannot witness the suspect.
#
# There is a second half, and it is the one that actually bites. The floor only catches
# "no assertions RAN". It cannot catch "assertions ran and their verdicts were
# DISCARDED", because the case counter is incremented by the assert HELPERS and never by
# `fail`. Stub `fail` to a no-op in a real suite and the counter stays at full value, the
# floor is satisfied, and the run exits 0 with real failures hidden. Measured on the probe
# suite before its fix: `45 passed, 0 failed (48 assertions)`, RC=0, with a genuine defect
# present. The fix for that half is an accounting-conservation check over a case counter
# incremented at the CALL SITE, so it moves independently of the verdict.
#
# THE POPULATION IS DERIVED, NEVER LISTED. This file used to name two suites. A
# hand-maintained list is the snapshot that goes stale — the same failure class one level
# up. The sweep below enumerates tracked `*.test.sh` RECURSIVELY (never a shell glob:
# `scripts/*.test.sh` is non-recursive and silently excludes `scripts/followthroughs/`)
# and classifies by SHAPE: a conditional opener whose test compares a counter the file
# itself increments against a threshold, in either bracket (`[[ … -lt … ]]`) or arithmetic
# (`(( … < … ))`) form. A suite whose floor this file cannot construct a mutant for is
# reported LOUDLY and counted — never silently skipped.
#
# THE ONE FAILURE MODE THIS FILE CANNOT REPORT ON ITSELF is a DERIVATION miss. A suite whose
# floor the sweep does not recognise never enters the population, so it is not covered, not
# deferred, and not UNCLASSIFIED either — it is simply absent, and every arm below is silent
# about it. The operator set and the syntax forms above are therefore the guard's real
# boundary, and widening them is how coverage grows. Measured: adding the arithmetic form
# moved the repo-wide population from 84 to 97 and surfaced four suites whose floors had
# never been tested.
#
# NOTHING HERE RUNS THE GUARDED SUITES TO COMPLETION. Each mutant is truncated to the
# floor block plus its threshold bindings, so this suite costs seconds and cannot be made
# slow or flaky by the batteries it guards.

export TMPDIR="${TMPDIR:-/var/tmp}"

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

passes=0
fails=0
cases=0

pass() { passes=$((passes + 1)); printf '[ok] %s\n' "$1"; }
# Deliberately NOT the mechanism this suite's own floor depends on — see the bottom.
fail() { fails=$((fails + 1)); printf '[FAIL] %s\n' "$1"; }

SUITE_TMP="$(mktemp -d "${TMPDIR}/vacuity-floor-meta.XXXXXXXX")" || {
  echo "FATAL: mktemp failed" >&2; exit 2; }
cleanup_suite() { [[ -n "${SUITE_TMP:-}" && -d "$SUITE_TMP" ]] && rm -rf "$SUITE_TMP" || true; return 0; }
trap cleanup_suite EXIT

# ---------------------------------------------------------------------------------------
# DERIVATION
# ---------------------------------------------------------------------------------------

# A suite's counter variables are exactly those it increments by one. Two shapes cover the
# corpus: `X=$((X + 1))` and `((X++))`. `grep -a` because one tracked suite carries bytes
# grep classifies as binary, and a "binary file matches" line would otherwise be parsed as
# a counter name.
counters_of() { # <file>
  {
    { grep -aoE '\b[A-Za-z_][A-Za-z0-9_]*=\$\(\( *[A-Za-z_][A-Za-z0-9_]* *\+ *1 *\)\)' "$1" || true; } | cut -d= -f1
    { grep -aoE '\(\( *[A-Za-z_][A-Za-z0-9_]*\+\+ *\)\)' "$1" || true; } | tr -d '()+ '
  } | sort -u | grep -v '^$' || true
}

# Floor candidates: `-lt`/`-ge`/`-le` comparisons referencing a counter, or a variable
# derived from counters in one step (`total=$((passes + fails))`).
#
# Variables inside an arithmetic expansion appear WITHOUT a leading `$` — `$((PASS + FAIL))`
# — so the reference test matches on a WORD BOUNDARY, not on `\$VAR`. Anchoring on `$` was
# measured to drop `plugins/soleur/test/terraform-drift-step-order.test.sh`, whose only floor
# is `if [[ "$((PASS + FAIL))" -lt 6 ]]`, from the population entirely.
# (An earlier version of this comment also named `preflight-check10-suite-integrity.test.sh`.
# That was true at `origin/main` and this PR falsified it: hardening that suite added a
# `$cases`-anchored floor, so the `$`-anchored variant now finds it. Corrected rather than
# left standing — a comment citing evidence the diff itself moved is the class this repo
# calls out explicitly.)
#
# Both `[[ ]]` and `[ ]` are matched: `apps/web-platform/infra/git-data-emit.test.sh`
# writes its floor as `if [ "$total" -lt 44 ]`, and a `[[`-only pattern misses it.
# Line numbers that are INSIDE a heredoc body, so the sweep never treats generated
# fixture/stub text as suite code. Without this, a `curl` stub emitted via
# `cat > x <<'STUB'` contributes both a counter and a floor candidate, and the slice runs
# 1200+ lines of another suite's setup (measured on prod-version-drift-check.test.sh).
heredoc_lines_of() { # <file> -> one line number per line inside a heredoc body
  awk '
    /<<-?[[:space:]]*['"'"'"]?[A-Za-z_][A-Za-z0-9_]*['"'"'"]?/ && !inhd {
      if (match($0, /<<-?[[:space:]]*['"'"'"]?[A-Za-z_][A-Za-z0-9_]*/)) {
        tag = substr($0, RSTART, RLENGTH)
        gsub(/^<<-?[[:space:]]*['"'"'"]?/, "", tag)
        inhd = 1; next
      }
    }
    inhd { if ($0 ~ "^[[:space:]]*" tag "[[:space:]]*$") { inhd = 0 } else { print NR } }
  ' "$1" 2>/dev/null || true
}

# Floor candidates. A candidate must be an actual CONDITIONAL OPENER referencing a counter:
#
#   * `if`/`elif` with a bracket test — `[[ … -lt … ]]`, `[ … -ne … ]`
#   * an arithmetic conditional — `if (( cases < 20 ))`
#
# Three narrownesses were measured and closed here, each of which silently shrank the
# population rather than reporting anything:
#
#   1. SYNTAX FORM ONLY — the operator set stays at BELOW-THRESHOLD semantics.
#      A floor says "the counter is under its minimum". That is `-lt`/`-le` and the inverted
#      `-ge` (success arm). `-gt` and `-eq` were tried and REVERTED: `-gt` is the shape of a
#      suite's FINAL EXIT GATE (`if [[ "$FAIL" -gt 0 ]]`) and `-eq` is the shape of an
#      ordinary assertion, so admitting them reported 13 "non-firing floors" that were
#      neither floors nor broken. Widening a matcher moves the error to the other side; the
#      fixtures that would have caught it all sat on the must-trip side.
#   2. SYNTAX FORM. `(( TOTAL < MIN_ASSERTIONS ))` is invisible to a bracket-only pattern.
#      19 tracked suites write their floor that way, 12 of them inside the covered scope.
#   3. COMMENTS AND HEREDOCS. A bare line match scored this file's OWN header comment
#      (`#   if [[ "$cases" -lt 75 ]]; then fail …`) as a floor, sliced 277 lines of the
#      guard's body into a mutant, and scored it FIRES off git's `fatal:` error. Requiring a
#      conditional opener and excluding heredoc bodies closes both.
#
# A suite that fails DERIVATION never reaches the mutation arm and never reaches
# UNCLASSIFIED either — `is_floor_bearing()` below is `floor_lines_of` too, so the repo-wide
# sweep and the covered population share this one pattern. That makes a too-narrow pattern the
# one failure mode this file cannot report on itself, in TWO directions, and they are bounded
# unequally:
#
#   - NARROWING (a shape that used to match stops matching) is bounded by ARM 3. Its
#     `MIN_FIRING_SUITES` is absolute and hand-ratcheted — deliberately never derived from
#     anything this file computes — so a pattern that drops existing members drives `n_fires`
#     under the ratchet and ARM 3 names it. That is the bound; there is no ARM 11. An earlier
#     revision of this comment cited one, and no such arm has ever existed (the arms are
#     1, 2, 2b, 3, 4, 5, 5b, 5c, 7, 8, 8b, 9, 10, 10d, 10e; 6 was deleted as subsumed and says
#     so at its old position).
#   - A NEW floor written in a shape the pattern never matched is bounded by NOTHING here, and
#     cannot be: it is absent from both scopes and from `n_total`, so every arithmetic
#     identity in this file still balances. Widen the pattern when you add a floor form, and
#     expect ARM 3's ratchet to be raised in the same commit.
floor_lines_of() { # <file> -> "lineno:text" per candidate
  local f="$1" base derived all alt c hd
  base="$(counters_of "$f")"
  [[ -n "$base" ]] || return 0
  derived=""
  while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    derived+="$( { grep -aoE "\b[A-Za-z_][A-Za-z0-9_]*=\\\$\\(\\([^)]*\\b${c}\\b[^)]*\\)\\)" "$f" || true; } | cut -d= -f1)"$'\n'
  done <<< "$base"
  # `{ grep || true; }` — the BRACE form, inside the pipeline. A no-match here is a normal
  # answer (a file whose only counters are undeclared), not an error. A trailing `|| true`
  # on the whole pipeline would bind to `sort` alone and leave this exact trap open: under
  # `set -euo pipefail` a zero-match `grep` exits 1, pipefail promotes it, and `set -e`
  # kills the script AT THIS ASSIGNMENT — so the `[[ -n "$alt" ]]` guard two lines below is
  # unreachable and the suite dies closed but silent.
  all="$(printf '%s\n%s\n' "$base" "$derived" | { grep -v '^$' || true; } | sort -u)"
  alt="$(printf '%s' "$all" | paste -sd'|' -)"
  [[ -n "$alt" ]] || return 0
  hd="$(heredoc_lines_of "$f" | paste -sd',' -)"
  { grep -anE '^[[:space:]]*(el)?if[[:space:]]+((\[\[|\[)[^]]*(-lt|-le|-ge)[^]]*\]|\(\([^)]*(<|<=|>=)[^)]*\)\))' "$f" || true; } \
    | grep -aE "\b(${alt})\b" \
    | awk -v hd="$hd" -F: '
        BEGIN { n = split(hd, a, ","); for (i = 1; i <= n; i++) if (a[i] != "") skip[a[i]] = 1 }
        !($1 in skip)' || true
}

is_floor_bearing() { [[ -n "$(floor_lines_of "$1")" ]]; }

# The repo-wide sweep. Recursive over TRACKED files, so a new floor-bearing suite in a
# directory nobody anticipated is found rather than missed.
ALL_SUITES="$SUITE_TMP/all.txt"
git ls-files '*.test.sh' > "$ALL_SUITES"

SELF_REL="scripts/$(basename "${BASH_SOURCE[0]}")"

FLOOR_ALL="$SUITE_TMP/floor-all.txt"
: > "$FLOOR_ALL"
while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  # A symlink is not read-and-executed. `git ls-files` can name one, `[[ -f ]]` follows it,
  # and this walker slices the target's lines into a script it then runs.
  [[ -L "$f" ]] && continue
  # THIS FILE IS NOT ITS OWN SUBJECT. Slicing the guard into a mutant and running it
  # re-enters the whole population sweep recursively, and its verdict then depends on
  # whether $TMPDIR happens to sit inside a git checkout — measured FIRES in one location
  # and NO_FIRE in another, both wrong. Its own floor is asserted directly at the bottom.
  [[ "$f" == "$SELF_REL" ]] && continue
  is_floor_bearing "$f" && printf '%s\n' "$f" >> "$FLOOR_ALL"
done < "$ALL_SUITES"

# COVERED scope: the two directories this guard mutation-tests.
COVERED_DIRS='^(scripts/|plugins/soleur/test/)'

# DEFERRED scope: an EXPLICITLY DECLARED directory ledger. These carry floors this PR does
# not mutation-test — `apps/web-platform/infra/` is a different subsystem with its own
# runner (`run-registered-suites.sh`) — but they are counted, not forgotten.
#
# DECLARING these is load-bearing and was a real defect when it was not. The first version
# derived DEFERRED as "everything that is not COVERED", which makes
# `covered + deferred == total` an IDENTITY BY CONSTRUCTION: the two sets partition the
# same list, so the sum always equals the total and the arm can never fail. Caught by
# mutation — adding a floor-bearing suite under `apps/cla-evidence/scripts/` (a directory
# in neither scope) left the guard GREEN. With the ledger declared, that suite lands in
# UNCLASSIFIED and the guard reddens naming the file, which is the entire point.
DEFERRED_DIRS='^(apps/web-platform/infra/|apps/web-platform/scripts/|apps/web-platform/test/infra/|\.claude/hooks/|plugins/soleur/skills/[^/]+/test/)'

# THE PER-FILE PROMOTION SEAM (#7585, built by #7104 PR-B).
#
# ARM 5c's own note records that #7552 raised MAX_DEFERRED 46 -> 47 for exactly one file,
# against that arm's instruction, and states: "Do NOT treat this bump as precedent for the next
# one — the correct response to a second occurrence is to build the seam, not to add another
# line here." This is the second occurrence, so this is the seam.
#
# Why it was needed: both sanctioned outs are directory-granular. "Cover it" by adding one file
# to COVERED_DIRS leaves its directory in DEFERRED_DIRS and trips ARM 5's double-count check;
# "promote its directory" is blocked by the per-scope construction ratchet that does not exist
# yet. A file listed here is moved from the deferred ledger into the covered scope INDIVIDUALLY,
# so it is mutation-tested like any covered suite — it is a promotion, not an exemption, and it
# makes the ledger SHRINK rather than the ratchet grow.
#
# Anchored with ^...$ per entry so a path cannot be promoted by prefix accident.
# `inngest-dedicated-host-classify.test.sh` added by #7674 — a dedicated-host probe-consumer suite
# under a deferred directory. Its floor is an exact-count bound (`PASS -lt <n>`, no slack) that
# reports via a direct `echo` + `exit 1` rather than through the suite's own `assert` helper, so
# neutering the assertion machinery cannot disarm it; the guard's harness measures it FIRES. This
# promotion SHRINKS the ledger 48 -> 47 rather than raising the ratchet, which is the outcome the
# failure message asks for.
# `arm-heartbeats.test.sh` added by #7587 — a heartbeat-arming suite under a deferred directory.
# Its floor (`ASSERT_FLOOR`, a literal bound adjacent to the test) is mutant-CONSTRUCTIBLE and
# measured FIRES under neutered assertion machinery, so this is a promotion that buys real
# mutation coverage rather than an exemption that moves a number.
# `ssl-full-mitigation.test.sh` added by #7749 — the guard on the Cloudflare config rule
# holding the apex off HTTP 526 while the GitHub Pages origin cert sits expired. Its floor is
# an exact cardinality split into `-lt` and `-gt` halves (no slack), reported via a direct
# `printf >&2` + `exit 1`, never through the suite's own `fail()`, so neutering the assertion
# machinery cannot disarm it — and the suite additionally carries a positive control that
# drives `pass()`/`fail()` once and requires both counters to move, which is what catches a
# neutered `fail()` that an exact-count floor alone cannot see. Promotion, not exemption: it
# is mutation-tested like any covered suite and SHRINKS the ledger 48 -> 47.
PROMOTED_FILES='^(apps/web-platform/infra/infra-config-verify\.test\.sh|apps/web-platform/infra/infra-config-repush-mutation\.test\.sh|apps/web-platform/infra/arm-heartbeats\.test\.sh|apps/web-platform/infra/inngest-dedicated-host-classify\.test\.sh|apps/web-platform/infra/ssl-full-mitigation\.test\.sh)$'

COVERED="$SUITE_TMP/covered.txt"
DEFERRED="$SUITE_TMP/deferred.txt"
UNCLASSIFIED="$SUITE_TMP/unclassified.txt"
{ { grep -E "$COVERED_DIRS" "$FLOOR_ALL" || true; }; { grep -E "$PROMOTED_FILES" "$FLOOR_ALL" || true; }; } | sort -u > "$COVERED"
{ grep -E "$DEFERRED_DIRS" "$FLOOR_ALL" || true; } | { grep -vE "$PROMOTED_FILES" || true; } > "$DEFERRED"
# Anything floor-bearing that matches NEITHER declared scope.
{ grep -vE "$COVERED_DIRS" "$FLOOR_ALL" || true; } | { grep -vE "$DEFERRED_DIRS" || true; } \
  | { grep -vE "$PROMOTED_FILES" || true; } > "$UNCLASSIFIED"
# And anything counted TWICE would satisfy the identity while covering nothing.
DOUBLE="$SUITE_TMP/double.txt"
# Unchanged by the seam: a PROMOTED file never matches COVERED_DIRS, so it cannot appear on
# both sides of this intersection. What this still catches is the original case — a
# directory listed in both scope regexes.
{ grep -E "$COVERED_DIRS" "$FLOOR_ALL" || true; } | { grep -E "$DEFERRED_DIRS" || true; } > "$DOUBLE"

n_total=$(wc -l < "$FLOOR_ALL")
n_covered=$(wc -l < "$COVERED")
n_deferred=$(wc -l < "$DEFERRED")
n_unclassified=$(wc -l < "$UNCLASSIFIED")
n_double=$(wc -l < "$DOUBLE")

# ---------------------------------------------------------------------------------------
# MUTANT CONSTRUCTION — no declarations, no per-suite contract lines
# ---------------------------------------------------------------------------------------
#
# `command_not_found_handle() { return 0; }` neuters EVERY helper name at once. The mutant
# carries only the floor block, never the suite's helper definitions, so `fail`, `bad`,
# `nope` and every other verdict name are unfound commands. That is strictly stronger than
# a declared list of helper names, which can be under-declared — and it is why no suite
# needs to carry a `# vacuity-contract:` line for this guard to work on it.
#
# The slice is widened BACKWARD over contiguous simple assignments so threshold bindings
# (`MIN_ASSERTS=26`) are bound. Without that widening the mutant dies at an unbound
# variable BEFORE reaching the floor, exits non-zero, and a bare `rc != 0` oracle scores
# that crash as a pass. Measured: 8 of 11 target floors behaved exactly that way, which
# made them equivalent mutants — the arm proved nothing about them.
#
# Only COUNTER variables are zeroed. Thresholds keep their real values: zeroing a
# threshold inverts a `-ge` floor's polarity and destroys discrimination.
build_mutant() { # <suite> <floor-lineno> <out>
  local src="$1" ln="$2" out="$3" ifline indent end start prev t
  ifline="$(sed -n "${ln}p" "$src")"
  indent="$(printf '%s' "$ifline" | sed -E 's/^([[:space:]]*).*/\1/')"
  end="$(awk -v s="$ln" -v ind="^${indent}fi[[:space:]]*$" 'NR>=s && $0 ~ ind {print NR; exit}' "$src")"
  [[ -n "$end" ]] || return 1
  start="$ln"
  while [[ "$start" -gt 1 ]]; do
    prev=$((start - 1))
    t="$(sed -n "${prev}p" "$src")"
    # `$((` is ARITHMETIC expansion and is safe to carry into the mutant; `$(` is COMMAND
    # substitution and is not (it would run the suite's setup). The first version rejected
    # both, so a floor preceded by `total=$((passes + fails))` lost its threshold binding and
    # the mutant died unbound — reported as a construction failure for a fully compliant
    # floor. Same `$((` vs `$(` distinction the conservation arm makes.
    if printf '%s' "$t" | grep -qE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=[^;]*$' \
       && ! printf '%s' "$t" | grep -qE '\$\([^(]'; then
      start="$prev"
    else
      break
    fi
  done
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' 'set -euo pipefail'
    # THE NEUTERING. This is the fault under test.
    printf '%s\n' 'command_not_found_handle() { return 0; }'
    counters_of "$src" | while IFS= read -r c; do printf '%s=0\n' "$c"; done
    sed -n "${start},${end}p" "$src"
    # Appended rather than reconstructing each suite's trailer: this tests the property
    # directly — does the floor block ITSELF exit non-zero?
    printf '%s\n' 'exit 0'
  } > "$out"
  return 0
}

# THE ORACLE ASSERTS THE REASON, NOT THE EXIT CODE.
# A mutant that dies at an unbound variable also exits non-zero. Scoring that as a pass is
# how 8 of 11 floors came to be untested. Three outcomes, and the crash is its own loud
# class rather than either colour:
#   FIRES        -> non-zero AND a floor-shaped sentinel on stderr
#   NO_FIRE      -> exit 0: the floor is enforced THROUGH the machinery it guards
#   CONSTRUCTION -> non-zero with a shell-error signature and no sentinel
classify_mutant() { # <mutant> -> prints FIRES|NO_FIRE|CONSTRUCTION
  local m="$1" errf outf both rc=0
  errf="${m}.err"
  outf="${m}.out"
  bash "$m" >"$outf" 2>"$errf" || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    printf 'NO_FIRE\n'
    return 0
  fi

  # A TOOL's error is not a floor. `-i` used to make the sentinel `FATAL` match git's
  # universal `fatal:` prefix, so a mutant that merely failed to find a git repository
  # scored FIRES. Measured: this file's own header comment produced a 277-line slice that
  # `cd`-ed outside the repo and was credited as a firing floor on
  # `fatal: not a git repository`. Tool errors are checked FIRST and are never a fire.
  if grep -qaE '^(fatal|error):' "$errf"; then
    printf 'CONSTRUCTION\n'
    return 0
  fi

  # FIRES is tested BEFORE the shell-error signature. The previous order returned
  # CONSTRUCTION for any mutant whose slice happened to emit an unrelated shell diagnostic
  # earlier, and `|| [[ "$rc" -eq 2 ]]` forced CONSTRUCTION unconditionally at rc=2 even
  # with a perfect sentinel on stderr — and 2 is this repo's own fatal convention.
  #
  # The sentinel is matched on BOTH streams. A floor that reports to stdout is
  # non-compliant with ADR-193 Decision #1, but it DID fire, and scoring it as a failed
  # CONSTRUCTION misreports which property is broken.
  #
  # The vocabulary is deliberately broader than one phrasing: an earlier allowlist required
  # `only` BEFORE the verb and so missed `dispatched only …`, and matched `vacuity` but not
  # `vacuous`, demoting three fully-compliant floors into the ratcheted debt bin.
  # Bash's own diagnostics (`<path>: line N: …`) are stripped BEFORE the sentinel test.
  # They are shell errors by definition, never floor output — and they carry the mutant's
  # PATH, which lives under a temp dir this file names `vacuity-floor-meta.XXXX`. The word
  # `vacuit` is in the sentinel vocabulary, so every crashing mutant matched FIRES on its own
  # filename. Caught by ARM 8, which is the whole reason that control exists.
  both="${m}.both"
  { cat "$outf" "$errf" 2>/dev/null || true; } \
    | { grep -avE '^[^[:space:]]*: line [0-9]+: ' || true; } > "$both"
  if grep -qaE '\[FATAL\]|\[?FAIL(ED)?\]?:|vacuit|vacuous|cardinality|assertion floor|anti-vacuity|only [0-9]|did not execute|assertions ran' "$both"; then
    printf 'FIRES\n'
    return 0
  fi

  if grep -qaE 'unbound variable|syntax error|unexpected (EOF|end of file)|bad substitution' "$errf" \
     || [[ "$rc" -eq 2 ]]; then
    printf 'CONSTRUCTION\n'
    return 0
  fi
  printf 'CONSTRUCTION\n'
}

# Best outcome across every candidate floor in a file. A file may carry several counter
# comparisons; the suite passes if ANY of them is a floor that fires. Quantifying over the
# first match alone was measured to misclassify `verify-marketplace-ruleset` (its first
# candidate sits inside a helper that reads `$1`).
classify_suite() { # <suite> -> FIRES|NO_FIRE|CONSTRUCTION
  local f="$1" best="CONSTRUCTION" ln verdict m i=0
  while IFS= read -r ln; do
    [[ -n "$ln" ]] || continue
    i=$((i + 1))
    m="$SUITE_TMP/mut.$$.${i}.sh"
    if ! build_mutant "$f" "$ln" "$m"; then continue; fi
    verdict="$(classify_mutant "$m")"
    case "$verdict" in
      FIRES) printf 'FIRES\n'; return 0 ;;
      NO_FIRE) best="NO_FIRE" ;;
    esac
  done < <(floor_lines_of "$f" | cut -d: -f1)
  printf '%s\n' "$best"
}

FIRES_LIST="$SUITE_TMP/fires.txt"; : > "$FIRES_LIST"
NOFIRE_LIST="$SUITE_TMP/nofire.txt"; : > "$NOFIRE_LIST"
CONSTRUCT_LIST="$SUITE_TMP/construct.txt"; : > "$CONSTRUCT_LIST"

# The DEFERRED scope is classified too, in the SAME pass, tagged by scope (#7580). Before this,
# the mutation loop read `< "$COVERED"` only — so every suite in a deferred directory was COUNTED
# by ARM 5c and never CLASSIFIED, and eleven of them had floors that exited 0 under a neutered
# assertion machinery while every arm of this guard returned an identical verdict. Counting is
# what failed to notice them; the fix has to be classification.
#
# One scope-tagged loop rather than two loops: less code, and it cannot drift between scopes.
DEF_FIRES_LIST="$SUITE_TMP/fires-deferred.txt"; : > "$DEF_FIRES_LIST"
DEF_NOFIRE_LIST="$SUITE_TMP/nofire-deferred.txt"; : > "$DEF_NOFIRE_LIST"
DEF_CONSTRUCT_LIST="$SUITE_TMP/construct-deferred.txt"; : > "$DEF_CONSTRUCT_LIST"

classify_into() { # <input-list> <fires-out> <nofire-out> <construct-out>
  local src="$1" fout="$2" nout="$3" cout="$4" f
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    case "$(classify_suite "$f")" in
      FIRES) printf '%s\n' "$f" >> "$fout" ;;
      NO_FIRE) printf '%s\n' "$f" >> "$nout" ;;
      *) printf '%s\n' "$f" >> "$cout" ;;
    esac
  done < "$src"
}

classify_into "$COVERED"  "$FIRES_LIST"     "$NOFIRE_LIST"     "$CONSTRUCT_LIST"
classify_into "$DEFERRED" "$DEF_FIRES_LIST" "$DEF_NOFIRE_LIST" "$DEF_CONSTRUCT_LIST"

n_fires=$(wc -l < "$FIRES_LIST")
n_nofire=$(wc -l < "$NOFIRE_LIST")
n_construct=$(wc -l < "$CONSTRUCT_LIST")
n_def_fires=$(wc -l < "$DEF_FIRES_LIST")
n_def_nofire=$(wc -l < "$DEF_NOFIRE_LIST")
n_def_construct=$(wc -l < "$DEF_CONSTRUCT_LIST")

printf '=== derived population ===\n'
printf '  repo-wide floor-bearing : %d\n' "$n_total"
printf '  covered (mutation-arm)  : %d\n' "$n_covered"
printf '  deferred (declared)     : %d\n' "$n_deferred"
printf '  unclassified (must be 0): %d\n' "$n_unclassified"
printf '  floor fires             : %d\n' "$n_fires"
printf '  floor does NOT fire     : %d\n' "$n_nofire"
printf '  mutant not constructible: %d\n' "$n_construct"
printf '  -- deferred scope (#7580) --\n'
printf '  deferred floor fires      : %d\n' "$n_def_fires"
printf '  deferred does NOT fire    : %d\n' "$n_def_nofire"
printf '  deferred not constructible: %d\n' "$n_def_construct"
printf '\n'

# --- ARM 1: no covered suite may have a floor that fails to fire -------------------------
# This is the regression the guard exists to catch, and it needs no hardcoded suite list:
# a suite that regresses to a `fail`-routed floor lands here by derivation.
cases=$((cases + 1))
if [[ "$n_nofire" -eq 0 ]]; then
  pass "every covered floor survives a neutered assertion machinery ($n_fires suites)"
else
  fail "$n_nofire covered suite(s) have a floor that EXITS 0 under a neutered assertion machinery — the floor is enforced THROUGH the machinery it guards:"
  while IFS= read -r f; do [[ -n "$f" ]] && printf '        %s\n' "$f"; done < "$NOFIRE_LIST"
fi

# --- ARM 2: construction failures are counted and may only shrink ------------------------
# A floor whose mutant is not a runnable program (it reads state computed by surrounding
# code) is NOT silently skipped: it is named here and capped by a hand-ratcheted maximum.
# Ratcheting DOWN-only means new suites cannot quietly join the uncovered set.
MAX_CONSTRUCTION_FAILURES=15
cases=$((cases + 1))
if [[ "$n_construct" -le "$MAX_CONSTRUCTION_FAILURES" ]]; then
  pass "mutant-construction failures within the ratchet ($n_construct <= $MAX_CONSTRUCTION_FAILURES)"
else
  fail "mutant-construction failures GREW to $n_construct (ratchet is $MAX_CONSTRUCTION_FAILURES). A new floor joined the uncovered set:"
  while IFS= read -r f; do [[ -n "$f" ]] && printf '        %s\n' "$f"; done < "$CONSTRUCT_LIST"
fi

# --- ARM 2b: the DEFERRED scope is CLASSIFIED, not merely counted (#7580) ------------------
#
# ARM 5c counts the deferred ledger and refuses to let it grow. Counting is exactly what failed:
# eleven deferred suites carried floors that exited 0 under a neutered assertion machinery, and
# every arm of this guard returned an identical verdict before and after they were fixed, because
# the mutation loop read the covered list only. This arm makes the deferred scope's floors
# mechanically visible, in place, without promoting any directory into COVERED_DIRS and without
# touching MAX_CONSTRUCTION_FAILURES.
#
# The ratchet is 0, not a slack figure. Slack in a floor is narrowing budget, and a set invariant
# ("every member fires") is not the kind of thing that has a tolerance.
MAX_DEFERRED_NOFIRE=0
cases=$((cases + 1))
if [[ "$n_def_nofire" -le "$MAX_DEFERRED_NOFIRE" ]]; then
  pass "every DEFERRED floor survives a neutered assertion machinery ($n_def_fires firing, $n_def_construct unconstructible)"
else
  fail "$n_def_nofire deferred suite(s) have a floor that EXITS 0 under a neutered assertion machinery (ratchet is $MAX_DEFERRED_NOFIRE):"
  while IFS= read -r f; do [[ -n "$f" ]] && printf '        %s\n' "$f"; done < "$DEF_NOFIRE_LIST"
fi

# The bucket identity. classify_suite returns exactly one of three verdicts for every input, so
# fires + nofire + construct MUST equal the population size. This is strictly stronger than a
# `>=` floor on the classified count: it catches an arm that classifies an EMPTY list (which would
# report 0 NO_FIRE and pass while classifying nothing — the vacuity this whole guard is about,
# one level up) AND one that double-counts, neither of which a floor can see.
cases=$((cases + 1))
if [[ $((n_def_fires + n_def_nofire + n_def_construct)) -eq "$n_deferred" ]]; then
  pass "the deferred classification is exhaustive ($n_def_fires + $n_def_nofire + $n_def_construct == $n_deferred)"
else
  fail "deferred classification does not account for the population: $n_def_fires + $n_def_nofire + $n_def_construct != $n_deferred — the classification loop read a different (or empty) list than ARM 5c counted"
fi

# A floor REWRITE can move a suite from NO_FIRE into CONSTRUCTION rather than into FIRES, which
# would drive the NO_FIRE count to 0 while the property still fails. MAX_CONSTRUCTION_FAILURES
# cannot catch that: it is global and derived from $COVERED. Without this ratchet the arm above
# has a live escape path, opened by the very PR that added it. Shrink-only, like its sibling.
#
# 18, measured. An earlier figure of 16 came from a probe that repointed COVERED_DIRS at four of
# the five DEFERRED_DIRS prefixes and silently omitted apps/web-platform/scripts/, which carries
# two. The conclusion it supported is unchanged and stronger: 18 exceeds the global cap of 15,
# so promoting these directories wholesale is still blocked on a per-scope ratchet.
MAX_DEFERRED_CONSTRUCTION=18
cases=$((cases + 1))
if [[ "$n_def_construct" -le "$MAX_DEFERRED_CONSTRUCTION" ]]; then
  pass "deferred mutant-construction failures: $n_def_construct (<= $MAX_DEFERRED_CONSTRUCTION)"
else
  fail "deferred construction failures GREW to $n_def_construct (ratchet is $MAX_DEFERRED_CONSTRUCTION) — a floor rewrite made a mutant unconstructible instead of making the floor fire. Do NOT raise this number."
fi

# --- ARM 3: the firing population may only grow ------------------------------------------
# Absolute and hand-ratcheted. Never derived from a variable this file computes: a floor
# that descends with the thing it guards is not a floor.
# PER-FILE MEMBERSHIP PIN ON THE PROMOTION SEAM (#7546 review).
#
# `PROMOTED_FILES` had no assertion of its own, and the aggregate ratchet below carries SLACK
# (measured: 45 firing against MIN_FIRING_SUITES=36, i.e. nine). Measured consequence: DELETING
# a promoted file's floor outright -- `if [[ "$N" -lt 40 ]]` -> `if false` in the battery -- left
# this suite reporting `19 passed, 0 failed`, rc=0. ARM 4's closure and ARM 5's double-count both
# stayed intact BY CONSTRUCTION: a deleted floor drops the file out of FLOOR_ALL entirely, so
# covered+deferred+unclassified still balances (one subtracted from each side) and MAX_DEFERRED
# is a ceiling a shrinking ledger cannot breach. Only the aggregate had a stake, and it had nine
# to spare. So nine covered floors -- including both files this PR promotes -- could be removed
# silently.
#
# The seam was already armored against a file being UNDECLARED (a typo'd entry pushes it back
# into the ledger and breaches the zero-slack MAX_DEFERRED); it was not armored against the
# promoted file's floor being REMOVED. This pin has zero slack by construction: every declared
# entry must still be floor-bearing, must land in COVERED, and must score FIRES.
promoted_problems=""
while IFS= read -r pf; do
  [[ -z "$pf" ]] && continue
  grep -qxF "$pf" "$FLOOR_ALL" || { promoted_problems="$promoted_problems $pf:no-longer-floor-bearing"; continue; }
  grep -qxF "$pf" "$COVERED"   || { promoted_problems="$promoted_problems $pf:not-in-covered"; continue; }
  grep -qxF "$pf" "$FIRES_LIST" || promoted_problems="$promoted_problems $pf:floor-does-not-fire"
done < <(printf '%s\n' "$PROMOTED_FILES" \
          | sed -e 's/^\^(//' -e 's/)\$$//' -e 's/\\//g' -e 's/|/\n/g')
cases=$((cases + 1))
if [[ -z "$promoted_problems" ]]; then
  pass "every PROMOTED_FILES entry is still floor-bearing, covered, and scores FIRES — promotion cannot decay into a silent exemption"
else
  fail "PROMOTED_FILES entries drifted:$promoted_problems. A promoted file whose floor was DELETED leaves the covered set entirely and every aggregate arm still balances, so this per-file pin is the only thing that sees it."
fi

MIN_FIRING_SUITES=36
cases=$((cases + 1))
if [[ "$n_fires" -ge "$MIN_FIRING_SUITES" ]]; then
  pass "firing-floor population at or above the ratchet ($n_fires >= $MIN_FIRING_SUITES)"
else
  fail "firing-floor population SHRANK to $n_fires (ratchet is $MIN_FIRING_SUITES) — a floor stopped being mutation-tested"
fi

# --- ARM 4: closure over the repository --------------------------------------------------
# Every floor-bearing suite is either COVERED or in the DECLARED deferral ledger. The
# `total` is swept INDEPENDENTLY over the whole repo from floor shape, and both scopes are
# declared regexes — so a new floor-bearing suite in a directory nobody anticipated lands
# in neither and is NAMED here rather than disappearing.
cases=$((cases + 1))
if [[ "$n_unclassified" -eq 0 ]]; then
  pass "closure holds: every floor-bearing suite is covered ($n_covered) or declared-deferred ($n_deferred), total $n_total"
else
  fail "closure BROKEN: $n_unclassified floor-bearing suite(s) are in NEITHER the covered scope nor the declared deferral ledger:"
  while IFS= read -r f; do [[ -n "$f" ]] && printf '        %s\n' "$f"; done < "$UNCLASSIFIED"
fi

# --- ARM 5: no suite is counted in both scopes -------------------------------------------
# Double-counting would satisfy an arithmetic identity while covering nothing.
cases=$((cases + 1))
if [[ "$n_double" -eq 0 ]]; then
  pass "no suite is counted in both the covered scope and the deferral ledger"
else
  fail "$n_double suite(s) match BOTH scopes — double-counted, so the ledger overstates coverage"
fi

# --- ARM 5b: the sweep's scope is strictly wider than the covered scope ------------------
# Without this the whole closure check is satisfiable by sweeping only the covered
# directories, which would make it trivially true and prove nothing.
cases=$((cases + 1))
if [[ "$n_deferred" -gt 0 && "$n_total" -gt "$n_covered" ]]; then
  pass "the repo-wide sweep reaches outside the covered directories ($n_deferred declared-deferred)"
else
  fail "the repo-wide sweep found nothing outside the covered directories — the closure check has become circular"
fi

# --- ARM 5c: the deferral ledger may only SHRINK -----------------------------------------
# Closure (ARM 4) stops a floor-bearing suite ESCAPING classification. It does not stop the
# deferred set ACCRETING: `DEFERRED_DIRS` is a directory regex with no upper bound, so a new
# vacuous-floored suite dropped into any deferred directory lands in the ledger and the guard
# stays green while the debt grows with CI's blessing. This ratchet closes that leak — it may
# only be lowered, never raised, so promoting a suite is the ONLY way to move it.
#
# Of the 43 deferred on 2026-08-16: 8 are measured NO_FIRE (the defect this PR fixes in the
# covered scope), 33 are CONSTRUCTION (mutant not constructible — status unknown, not
# known-bad), and 2 already FIRE unmodified. The 8 are named and tracked in issue #7580.
#
# WIDENING SCOPE NEEDS A PER-SCOPE RATCHET FIRST. MAX_CONSTRUCTION_FAILURES below is GLOBAL
# and sits at exactly its current value with zero headroom; promoting the deferred
# directories wholesale would push it from 15 to ~33 and ARM 2 would stop discriminating.
# RAISED 46 -> 47 by #7552, for exactly one file, and against this arm's own instruction —
# stated here rather than done quietly.
#
# The file is apps/web-platform/infra/zot-config-deadlines.test.sh: a new suite that renders the
# registry host's config and boots the pinned zot digest against it. Neither sanctioned out was
# available to it. "Cover it" is directory-granular, and adding one file to COVERED_DIRS while
# its directory remains in DEFERRED_DIRS trips ARM 4's double-count check. "Promote its
# directory" is blocked by this file's own prerequisite two paragraphs up — the per-scope
# construction ratchet does not exist yet, and wholesale promotion would push
# MAX_CONSTRUCTION_FAILURES from 15 to ~33 and stop ARM 2 discriminating. ARM 2b now classifies
# that scope in place instead, which is the per-scope ratchet this paragraph asks for.
#
# That leaves only "ship the suite with no anti-vacuity floor", which is the opposite of what
# this ratchet exists to encourage. The floor was instead made mutant-CONSTRUCTIBLE first (a
# literal bound adjacent to the test), so it is deferred by DIRECTORY alone and would pass the
# covered arm today if the partition allowed a single file through.
#
# The seam that removes this exception is tracked in #7585; when it lands, promote that file and
# return this to 46. Do NOT treat this bump as precedent for the next one — the correct response
# to a second occurrence is to build the seam, not to add another line here.
MAX_DEFERRED=47
cases=$((cases + 1))
if [[ "$n_deferred" -le "$MAX_DEFERRED" ]]; then
  pass "deferral ledger within its shrink-only ratchet ($n_deferred <= $MAX_DEFERRED)"
else
  fail "deferral ledger GREW to $n_deferred (ratchet is $MAX_DEFERRED). A new floor-bearing suite landed in a deferred directory: cover it, or promote its directory into COVERED_DIRS — do NOT raise this number."
fi

# ARM 6 (an absolute `MIN_POPULATION` floor on the covered set) was DELETED as subsumed.
# ARM 3's `n_fires >= MIN_FIRING_SUITES` already implies a covered population at least that
# large, and ARM 5b already catches a sweep that has stopped reaching outside the covered
# directories. Two loose floors on one quantity are weaker than one tight floor: the deleted
# arm discriminated only in the narrow band where covered sat between the firing ratchet and
# 30 AND construction failures were few, and it invited being read as the population guard it
# was not.

# --- ARM 7: NEGATIVE CONTROL --------------------------------------------------------------
# The arms above must be CAPABLE of failing. This builds the PRE-FIX shape by hand — a
# floor that reports through `fail` — and asserts it exits 0 under the same neutering. If
# this control ever turns non-zero, the arms above have stopped discriminating and this
# whole file is decorative.
control="$SUITE_TMP/prefix-shape.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'set -euo pipefail'
  printf '%s\n' 'command_not_found_handle() { return 0; }'
  printf '%s\n' 'passes=0; fails=0; cases=0'
  # `-lt 1` deliberately, not a copy of a real floor: cases=0 fires any positive threshold,
  # so restating 75/121 here would only go stale when a floor is ratcheted.
  printf '%s\n' 'if [[ "$cases" -lt 1 ]]; then'
  printf '%s\n' '  fail "vacuity guard: only $cases assertions ran"'
  printf '%s\n' 'fi'
  printf '%s\n' 'exit 0'
} > "$control"
cases=$((cases + 1))
control_verdict="$(classify_mutant "$control")"
if [[ "$control_verdict" == "NO_FIRE" ]]; then
  pass "negative control: the pre-fix fail()-routed floor DOES exit 0 when neutered (so the arms above discriminate)"
else
  fail "negative control classified $control_verdict, expected NO_FIRE — this suite can no longer tell the two forms apart"
fi

# --- ARM 8: CONSTRUCTION-FAILURE CONTROL --------------------------------------------------
# The oracle must report a crash as a crash, never as a pass. This is the regression pin
# for the equivalent-mutant class: a floor whose threshold is unbound dies before the
# comparison, exits non-zero, and a bare `rc != 0` oracle would score it green.
crashctl="$SUITE_TMP/crash-shape.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'set -euo pipefail'
  printf '%s\n' 'command_not_found_handle() { return 0; }'
  printf '%s\n' 'cases=0'
  printf '%s\n' 'if [[ "$cases" -lt "$MIN_NEVER_BOUND" ]]; then'
  printf '%s\n' '  printf "[FATAL] floor\\n" >&2; exit 1'
  printf '%s\n' 'fi'
  printf '%s\n' 'exit 0'
} > "$crashctl"
cases=$((cases + 1))
crash_verdict="$(classify_mutant "$crashctl")"
if [[ "$crash_verdict" == "CONSTRUCTION" ]]; then
  pass "construction control: an unbound threshold is reported as a construction failure, never as a fired floor"
else
  fail "construction control classified $crash_verdict, expected CONSTRUCTION — a crash is indistinguishable from a fired floor and the mutation arm is vacuous"
fi

# --- ARM 8b: PERMISSIVENESS BOUND ----------------------------------------------------------
# ARM 8 bounds the oracle in the STRICT direction (a crash must not read as a fire). Nothing
# bounded it in the PERMISSIVE direction: widening the sentinel vocabulary inflates `n_fires`
# and deflates `n_construct`, and both ratchets move that way (`-ge` and `-le`), so a looser
# oracle reports a healthier population with every arm green. Measured during review: adding
# `|FAIL|error|expected|vacuous` to the vocabulary moved fires 24 -> 27 with nothing red.
#
# This control exits NON-ZERO while printing text that carries no floor sentinel. It must NOT
# classify FIRES. Any vocabulary broad enough to match ordinary diagnostic prose fails here.
permctl="$SUITE_TMP/permissive-shape.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'set -euo pipefail'
  printf '%s\n' 'command_not_found_handle() { return 0; }'
  printf '%s\n' 'echo "the configured value was not what the step expected" >&2'
  printf '%s\n' 'exit 1'
} > "$permctl"
cases=$((cases + 1))
perm_verdict="$(classify_mutant "$permctl")"
if [[ "$perm_verdict" != "FIRES" ]]; then
  pass "permissiveness bound: a non-zero exit with no floor sentinel is NOT scored FIRES (got $perm_verdict)"
else
  fail "permissiveness bound: generic diagnostic prose scored FIRES — the sentinel vocabulary is broad enough to match any failing mutant, so n_fires is inflated and the ratchets move the permissive way"
fi

# --- ARM 9: SYNTHESIZED OUT-OF-POPULATION MUST-PASS CONTROL -------------------------------
# Counter and helper names that appear nowhere else in the repo, and NOT named `*.test.sh`
# so it sits outside the derived population by construction. A control that is also a
# subject is not a control — the two suites previously used here were population members
# already exercised by the main loop.
FIXTURE="$REPO_ROOT/scripts/fixtures/vacuity-contract-control.sh"
cases=$((cases + 1))
if [[ -f "$FIXTURE" ]]; then
  pass "synthesized control fixture is present"
else
  fail "synthesized control fixture is missing at $FIXTURE — the must-PASS arm below is vacuous"
fi

cases=$((cases + 1))
if [[ -f "$FIXTURE" ]] && bash "$FIXTURE" >/dev/null 2>&1; then
  pass "synthesized control fixture runs green unmodified (the guard accepts a compliant shape it did not author)"
else
  fail "synthesized control fixture does not run green — the contract is not satisfiable by a third naming scheme"
fi

cases=$((cases + 1))
if [[ -f "$FIXTURE" ]] && ! grep -qE '^(scripts/fixtures/)' "$COVERED" 2>/dev/null; then
  pass "synthesized control sits OUTSIDE the derived population (it is a control, not a subject)"
else
  fail "the synthesized control has entered the derived population — it is no longer an independent control"
fi

# Its floor must fire under the same machinery, proving the derivation generalises past the
# names it was written against.
cases=$((cases + 1))
fixture_verdict="CONSTRUCTION"
if [[ -f "$FIXTURE" ]]; then
  fx_ln="$(floor_lines_of "$FIXTURE" | head -1 | cut -d: -f1)"
  if [[ -n "$fx_ln" ]] && build_mutant "$FIXTURE" "$fx_ln" "$SUITE_TMP/fixture.mutant.sh"; then
    fixture_verdict="$(classify_mutant "$SUITE_TMP/fixture.mutant.sh")"
  fi
fi
if [[ "$fixture_verdict" == "FIRES" ]]; then
  pass "synthesized control's floor FIRES under neutering despite third-party counter names (tally/good/bad_n)"
else
  fail "synthesized control's floor classified $fixture_verdict — the derivation only works against names it was written for"
fi

# --- ARM 10: conservation is non-tautological ---------------------------------------------
# `passes + fails == cases` is load-bearing ONLY when `cases` moves independently of the
# verdict. A counter incremented INSIDE both verdict helpers moves WITH the verdict, so
# stubbing `fail` drops the row and its count together and the identity still holds under
# the exact fault it exists to catch. Measured on the `ok`/`bad` shape before the fix:
# `conservation GREEN — defect hidden`, RC=0.
#
# Checked statically and structurally: no suite carrying a conservation check may increment
# its case counter inside a verdict helper body. Static because running 40 full suites here
# would make this guard as slow and flaky as the batteries it guards.
CONSERVING="$SUITE_TMP/conserving.txt"; : > "$CONSERVING"
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  if grep -qaE '\[FATAL\] accounting' "$f"; then printf '%s\n' "$f" >> "$CONSERVING"; fi
done < <(cat "$COVERED" "$DEFERRED")
n_conserving=$(wc -l < "$CONSERVING")

# Raised from 18 when the deferred scope joined this population (#7580). It was accurate for a
# COVERED-only population and became stale-low by the deferred suites the moment they started
# carrying conservation checks; a shrink-only ratchet left un-raised silently fails to capture
# the gain it exists to lock in. Raised 32 -> 33 when fanout-suite-scope.test.sh gained one
# (#7553): its floor read PASS+FAIL, the counter a neutered verdict helper keeps moving.
MIN_CONSERVING=33
cases=$((cases + 1))
if [[ "$n_conserving" -ge "$MIN_CONSERVING" ]]; then
  pass "suites carrying an accounting-conservation check: $n_conserving (>= $MIN_CONSERVING)"
else
  fail "only $n_conserving suite(s) carry a conservation check, ratchet is $MIN_CONSERVING — a conservation check was removed"
fi

# Every conserving suite must report its conservation failure DIRECTLY. A conservation
# check that calls `fail` has the same defect as a floor that calls `fail`.
tautological=""
direct_ok=1
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  # The sentinel must be emitted by a printf, i.e. NOT routed through the suite's own verdict
  # helper. This checks the emitter, not the redirect: the `>&2` frequently sits on a
  # continuation line, so requiring it here would false-fail correct suites.
  if ! grep -qaE "printf.*\[FATAL\] accounting" "$f"; then
    direct_ok=0; tautological="$tautological $f(not-direct)"
  fi
done < "$CONSERVING"
cases=$((cases + 1))
if [[ "$direct_ok" -eq 1 ]]; then
  pass "every conservation check reports directly, never through the suite's own verdict helpers"
else
  fail "conservation check(s) not reported directly:$tautological"
fi

# No conserving suite may increment its case counter inside a verdict helper body, and none
# may increment inside a command substitution (a subshell discards it). `$\([^(]` is the
# COMMAND substitution `$(`; a pattern without the `[^(]` also matches the arithmetic `$((`
# and is unsatisfiable for any file that increments a counter at all.
subshell_offenders=""
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  # Counter names are DERIVED per file, not hardcoded. A literal alternation
  # `(cases|ASSERTED|asserts|tally)` under case-sensitive grep silently exempted the two
  # suites in this very PR that name their counter `CASES` — the arm passed because it could
  # not see them, which is the vacuity class this file exists to close.
  local_alt="$(counters_of "$f" | paste -sd'|' -)"
  [[ -n "$local_alt" ]] || continue
  if grep -qaE "\\$\([^(][^)]*\b(${local_alt})\b[^)]*\+ *1" "$f"; then
    subshell_offenders="$subshell_offenders $f"
  fi
done < "$CONSERVING"
cases=$((cases + 1))
if [[ -z "$subshell_offenders" ]]; then
  pass "no case-counter increment sits inside a command substitution (a subshell would discard it)"
else
  fail "case-counter increment inside a command substitution — discarded to a subshell:$subshell_offenders"
fi

# --- ARM 10d: the CASE counter must not move INSIDE a verdict helper ------------------------
# ADR-193 Decision #2, and until now only CLAIMED. A case counter incremented inside the
# verdict helpers moves WITH the verdict, so stubbing one drops the row and its count together
# and the identity holds under the exact fault it exists to catch — the tautology measured as
# `conservation GREEN — defect hidden`, RC=0.
#
# The CASE counter is derived from the conservation identity itself: in
# `if [[ $((A + B)) -ne "$C" ]]` the right operand C is the case counter, and A/B are the
# verdict counters. Deriving it this way rather than matching every counter is load-bearing —
# a first attempt flagged `passes=$((passes + 1))` inside `pass()` for every suite including
# the two reference implementations, because a verdict helper incrementing its OWN verdict
# counter is correct and expected.
helper_offenders=""
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  case_ctr="$( { grep -aoE 'if \[\[ \$\(\([^)]*\)\) -ne "?\$\{?[A-Za-z_][A-Za-z0-9_]*' "$f" || true; } \
    | sed -E 's/.*-ne "?\$\{?//' | head -1)"
  [[ -n "$case_ctr" ]] || continue
  # Extract each verdict-helper body by brace depth and look for the CASE counter in it.
  # The VERDICT counters are the two operands on the left of the identity.
  vdt="$( { grep -aoE 'if \[\[ \$\(\([^)]*\)\) -ne' "$f" || true; } | head -1 \
    | sed -E 's/^if \[\[ \$\(\(//; s/\)\) -ne$//' | tr -cd 'A-Za-z0-9_ ' | tr ' ' '|' | sed 's/||*/|/g; s/^|//; s/|$//')"
  [[ -n "$vdt" ]] || continue
  # A function is a TERMINAL VERDICT HELPER only if it moves a verdict counter. A wrapper
  # that merely CALLS one (expect_rc, eq, neg, assert_eq) is the correct home for the case
  # increment — flagging those was a false positive on every reference implementation.
  hit="$(awk -v ctr="$case_ctr" -v vdt="$vdt" '
    /^[a-zA-Z_][a-zA-Z0-9_]*\(\)[[:space:]]*\{/ { inh = 1; depth = 0; name = $0; sub(/\(\).*/, "", name); hasc = 0; hasv = 0 }
    inh {
      d = gsub(/\{/, "{"); depth += d
      d = gsub(/\}/, "}"); depth -= d
      if ($0 ~ ctr "[[:space:]]*=[[:space:]]*\\$\\(\\(" || $0 ~ "\\(\\([[:space:]]*" ctr "\\+\\+") hasc = 1
      if ($0 ~ "(" vdt ")[[:space:]]*=[[:space:]]*\\$\\(\\(") hasv = 1
      if (depth <= 0) { inh = 0; if (hasc && hasv) print name }
    }
  ' "$f" 2>/dev/null | sort -u || true)"
  while IFS= read -r h; do
    [[ -n "$h" ]] || continue
    helper_offenders="$helper_offenders ${f}:${h}()"
  done <<< "$hit"
done < "$CONSERVING"
cases=$((cases + 1))
if [[ -z "$helper_offenders" ]]; then
  pass "no CASE counter is incremented inside a verdict helper (the identity stays non-tautological)"
else
  fail "CASE counter incremented INSIDE a verdict helper — conservation becomes a tautology:$helper_offenders"
fi

# --- ARM 10e: conservation is EXECUTED, not just spelled ------------------------------------
# Arms 10a-10d are static: they grep for the sentinel, for direct reporting, and for where the
# increments sit. All four are satisfied by a conservation block whose comparison has been
# gutted — replacing the condition with `if false; then` while keeping the printf and the
# `exit 1` inside left the whole guard byte-identical green, which is the "certifies spelling,
# not behaviour" class this file exists to close, one level up.
#
# So this arm RUNS a conservation check. The synthesized fixture is the subject because it is
# outside the derived population and cheap: stub its verdict helper to a no-op, and the case
# counter keeps moving while the verdict does not, which is exactly the fault conservation
# exists to catch. It must exit non-zero AND name the accounting sentinel.
cases=$((cases + 1))
cons_exec="$SUITE_TMP/conservation-exec.sh"
if [[ -f "$FIXTURE" ]]; then
  # Stub the fixture's success helper AFTER its definition, leaving everything else intact.
  awk '{ print } /^yay\(\)/ { print "yay() { :; }" }' "$FIXTURE" > "$cons_exec"
fi
ce_rc=0
ce_err="$cons_exec.err"
if [[ -s "$cons_exec" ]]; then
  bash "$cons_exec" >/dev/null 2>"$ce_err" || ce_rc=$?
fi
if [[ "$ce_rc" -ne 0 ]] && grep -qaE '\[FATAL\] accounting' "$ce_err"; then
  pass "conservation EXECUTES: a neutered verdict helper is caught by the accounting identity (exit $ce_rc)"
else
  fail "conservation did not fire when a verdict helper was neutered (exit $ce_rc) — the identity is spelled but not enforced; a gutted comparison would pass every static arm above"
fi

# ---------------------------------------------------------------------------------------
# THIS SUITE'S OWN FLOOR. The same rule it enforces on the others: reported directly, never
# through `fail`, so it cannot be silenced by the fault it exists to catch. Ratcheted by
# hand; never derived from a variable this file computes, because a floor that descends
# with the thing it guards is not a floor.
# ---------------------------------------------------------------------------------------
MIN_META_CASES=20
if [[ "$cases" -lt "$MIN_META_CASES" ]]; then
  printf '\n[FATAL] meta-guard vacuity: only %d assertion(s) ran; expected >= %d.\n' \
    "$cases" "$MIN_META_CASES" >&2
  printf 'Total: %d passed, %d failed (%d assertions)\n' "$passes" "$fails" "$cases"
  exit 1
fi

# ACCOUNTING CONSERVATION — the arm that actually catches a neutered `fail()`.
# The floor above catches "no assertions RAN". It cannot catch "assertions ran and their
# verdicts were discarded", because `cases` is incremented at the CALL SITE and never by
# `fail` — so stubbing `fail` leaves `cases` at full value, the floor is satisfied, and the
# suite exits 0 with real failures silenced.
if [[ $((passes + fails)) -ne "$cases" ]]; then
  printf '\n[FATAL] accounting: passes+fails (%d) != cases (%d).\n' "$((passes + fails))" "$cases" >&2
  if [[ $((passes + fails)) -lt "$cases" ]]; then
    printf '  An assertion was counted but its verdict was not recorded — that is what a neutered pass()/fail() looks like.\n' >&2
  else
    printf '  A verdict was recorded at a call site with no `cases=$((cases + 1))` before it.\n' >&2
  fi
  exit 1
fi


# KNOWN-NEGATIVE SELF-TEST (#7546 review). Ported from infra-config-gate.test.sh, which was the
# ONLY one of the four sibling suites to carry it -- and the only one that survived the mutation
# below. An assertion harness that has never been shown to emit a FAIL has not returned a pass.
#
# MEASURED on a sandbox copy, with a genuine defect present (a covered suite's floor neutered --
# a defect this guard exists to catch): swapping this suite's fail() to record a pass instead
# left it reporting `19 passed, 0 failed`, rc=0, and the finding printed verbatim as
# `[ok] 1 covered suite(s) have a floor that EXITS 0 under a neutered assertion machinery`.
# The accounting identity above held throughout -- passes+fails == cases is balanced by a SWAP,
# because one verdict left a bucket and entered another. That is the whole blind spot: a
# conservation law cannot see a transfer.
#
# This matters more here than in the siblings: the suite whose stated purpose is catching a
# floor enforced THROUGH the machinery it guards was itself enforced through the machinery it
# guards. Runs in a subshell so the side effects stay off the parent's tally.
if ( _p0="$passes"; _f0="$fails"
     fail "self-test (expected -- this line proves fail() records a FAILURE)" >/dev/null 2>&1
     [[ "$fails" -eq $((_f0 + 1)) && "$passes" -eq "$_p0" ]] ); then
  :
else
  echo "harness self-test: the REAL fail() does not record a failure into fails -- it is neutered, or it records failures as passes. Every verdict above is unverifiable." >&2
  exit 1
fi

printf 'Total: %d passed, %d failed (%d assertions)\n' "$passes" "$fails" "$cases"
[[ "$fails" -eq 0 ]]
