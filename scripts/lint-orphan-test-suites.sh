#!/usr/bin/env bash
# lint-orphan-test-suites.sh -- fail when a tracked *.test.sh ANYWHERE in the repo is run by
# no runner, or when a required nested RUNNER is de-registered from test-all.sh.
#
# WHY (#6734, widened by #7402): a test added to a file nothing executes gates nothing while
# looking exactly like coverage -- strictly worse than having no test at all, because the
# green summary is read as evidence. #6734 found three such suites under scripts/; #7402
# found that the same check, scoped to `scripts/*.test.sh`, was blind to the other ~270
# tracked suites and that 9 of them ran in ZERO runners.
#
# THE PRODUCER IS `git ls-files '*.test.sh'` -- the whole repo, not a directory list. A walk
# scoped to any directory answers a question about that directory; the property this file
# asserts is about the REPOSITORY, and every directory-scoped version of it has eventually
# been outgrown by a suite added one directory over. Scope note (deliberate, not an
# oversight): the producer is keyed on the `*.test.sh` SUFFIX, so the `test-<name>.sh`
# convention used under tests/scripts/ and tests/commands/ is outside it. tests/commands/ has
# its own dedicated loop at the bottom of this file; tests/scripts/ is floored by
# .github/scripts/test/run-all.sh's own MIN_SUITES.
#
# THE COVERED SET IS A UNION OF SIX REGISTRATION SURFACES, enumerated below at their point of
# use. Six, not one: a linter that only knew test-all.sh would report all 98 infra suites as
# orphans, and one that only knew the single-line `run: bash …` workflow shape would report
# workspaces-luks-loopback.test.sh as an orphan when it demonstrably runs in CI under
# `sudo bash` inside a multi-line `run: |` block.
#
# THIS FILE HAS A COMPANION SUITE (scripts/lint-orphan-test-suites.test.sh) and needs one.
# The earlier header claimed the opposite -- "deliberately ~20 lines with NO companion
# .test.sh" -- and that stopped being true long before it was corrected: the file was 396
# lines with four independent checks, and scripts/lint-workflows.sh cited it as precedent for
# going untested. A guard whose failure mode is "silently stops detecting" cannot be proved by
# reading it; the companion suite mutates each of the six surfaces individually and asserts
# this file reddens.
#
# Exclusions carry a REASON and a tracking issue, and are keyed on the REPO-RELATIVE PATH.
# The point is that skipping is a recorded decision, not a silent absorption.

set -euo pipefail

# LC_ALL=C, EXPORTED, and pinned again on every sort/comm below.
#
# `comm` requires both inputs sorted in the SAME collation it uses to compare them. Under a
# UTF-8 locale glibc's sort ignores punctuation at the primary level, so `a-b/c.test.sh` and
# `a/b-c.test.sh` order differently than byte order -- and `comm` then reads its own input as
# unsorted and emits an undefined diff. Measured on this repo: the default locale produced 48
# phantom orphans, every one of them a registered suite. The export covers the whole script
# (including the child processes it invokes); the per-command pins survive someone deleting
# the export, which is the edit most likely to happen.
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$REPO_ROOT/scripts/test-all.sh"
WORKFLOW_DIR="$REPO_ROOT/.github/workflows"
INFRA_VALIDATION_WF="$WORKFLOW_DIR/infra-validation.yml"
INFRA_RUNNER="$REPO_ROOT/apps/web-platform/infra/run-registered-suites.sh"

# repo-relative path | reason (must cite a tracking issue)
#
# KEYED ON THE PATH, NOT THE BASENAME (#7402). A basename key was safe while this file walked
# one flat directory and is unsafe repo-wide: measured, `argv-ceiling.test.sh` exists under
# both drain-prs/test/ and skill-security-scan/test/, and `parity.test.sh` under both
# constraint-scaffold/test/ and linear-fetch/test/. A basename exclusion would silently
# absorb a suite nobody decided to skip -- the exact silent absorption this mechanism exists
# to prevent, introduced by the mechanism itself.
#
# EMPTY IS THE GOAL STATE. lint-agents-enforcement-tags.test.sh was excluded
# here as a pre-existing failure (7/9) tracked in #6751; #7172 fixed the
# defect, registered both suites in test-all.sh, and removed the exclusion.
# Leaving a stale exclusion behind would re-hide the next regression in the
# very suite that was just repaired.
#
# CROSS-CHECKED against the other exclusion list over an overlapping domain,
# .github/scripts/test/test-infra-suite-registration.sh's EXCLUSIONS (#7402 step 8). That list
# carries exactly one entry, workspaces-luks-loopback.test.sh, excluded from
# run-registered-suites.sh's single-line DERIVATION because it needs root and exits 2
# unprivileged (#7076). That is a statement about local EXECUTION, not about registration:
# this file asks only "does anything run it?", surface 6 answers yes, and it is therefore
# COVERED here and must not be excluded. The two lists are disjoint today and one being empty
# is what keeps them from disagreeing.
EXCLUSIONS=()

fails=0

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- The producer -----------------------------------------------------------------------
# One line, deliberately: it is the single point where this guard could silently start
# certifying a subset. Its companion suite mutates exactly this line two ways -- to enumerate
# zero (the vacuity direction) and to enumerate the pre-#7402 `scripts/*.test.sh` subset (the
# plausible-subset direction, which clears a zero-check and prints a clean report).
git -C "$REPO_ROOT" ls-files '*.test.sh' | LC_ALL=C sort -u > "$WORK/tracked"
tracked_n=$(wc -l < "$WORK/tracked" | tr -d ' ')

# PRODUCER FLOOR. A zero-check alone cannot see the failure that matters most here: narrowing
# the producer back to one directory leaves it enumerating 70 real files, passes every
# per-surface zero-check, finds no orphans among them, and prints `orphan test suites: none`
# -- byte-identical to a healthy repo. Only a count floor separates "certified the repo" from
# "certified a corner of it".
#
# ABSOLUTE and hand-ratcheted, like REQUIRED_RUNNERS' floor below and for the same stated
# reason: there is no second producer in the tree to derive it from, and deriving it from
# `git ls-files` would be deriving the floor from its own subject.
#
# 320 against 342 measured 2026-08-13. It was 250, and that was too loose: measured at review,
# narrowing the producer to `-- apps plugins scripts` drops all 43 `.claude/**` suites, still
# enumerates 299, clears a 250 floor, leaves every per-surface zero-check non-zero (s3/s4/s6
# all live under `apps/`), and prints `0 orphaned` over a repo it stopped walking. Slack in a
# floor is not safety margin, it is narrowing budget. Keep just enough for a real cleanup.
MIN_TRACKED_SUITES=320
if (( tracked_n < MIN_TRACKED_SUITES )); then
  echo "ERROR: the *.test.sh walk enumerated ${tracked_n} tracked suites, below the floor of ${MIN_TRACKED_SUITES} -- the producer is narrowed or broken, so every check below certified a SUBSET of the repo while reporting on all of it." >&2
  fails=$((fails + 1))
fi

# A COUNT cannot see a narrowing that stays above the floor, and it cannot see a SUBSTITUTION
# at all -- the defect class this very PR exists to close, one level up. So assert the SET of
# top-level roots the producer reached, not how many files it returned. A narrowing that drops
# an entire root reds here even when the count survives, and it names the root.
#
# Derived from the producer's own output and compared against an explicit expected set: the
# expected side is the decision point, so adding a root is a deliberate edit rather than a
# silent widening.
# Measured, not guessed: the first cut of this line listed `tests` from memory and the check
# reddened on its own first run -- `tests/` uses a `test-*.sh` convention this producer does
# not match. Re-derive with:
#   git ls-files '*.test.sh' | awk -F/ 'NF{print $1}' | LC_ALL=C sort -u
EXPECTED_SUITE_ROOTS=".claude apps plugins scripts"
actual_roots="$(awk -F/ 'NF{print $1}' "$WORK/tracked" | LC_ALL=C sort -u | tr '\n' ' ')"
actual_roots="${actual_roots% }"
# Non-vacuity: an empty derivation must never be compared as a legitimate set. (It was, on the
# first cut of this check -- the producer's output is a FILE, not an array, so `${tracked[@]}`
# expanded to nothing. It reddened rather than passing, which is the only reason it was cheap.)
if [[ -z "$actual_roots" ]]; then
  echo "ERROR: the root derivation produced an EMPTY set from ${WORK}/tracked -- the extraction broke, so the comparison below would be meaningless." >&2
  fails=$((fails + 1))
fi
# SUPERSET, not equality — and the asymmetry is the whole point.
#
# The hazard this closes is a root DISAPPEARING: the producer silently stops walking it and
# every "covered" verdict below excludes it while the report still says 0 orphaned. So every
# expected root must be PRESENT.
#
# A root APPEARING is a different and much weaker concern, and it is already covered: a suite
# under a brand-new root matches no surface, so the orphan walk itself reports it by name (rows
# M2 and M16 in the companion suite create suites under `tools/` and `docs/deep/nested/` and
# assert exactly that). Demanding equality here would therefore red on a legitimate new
# directory AND break those two fixtures — which is precisely what it did on its first run,
# caught by M16 rather than by review.
_missing_roots=""
for _r in $EXPECTED_SUITE_ROOTS; do
  case " $actual_roots " in
    *" $_r "*) ;;
    *) _missing_roots="${_missing_roots}${_r} " ;;
  esac
done
if [[ -n "$_missing_roots" ]]; then
  echo "ERROR: the *.test.sh walk reached roots [${actual_roots}] but did NOT reach [${_missing_roots% }] -- the producer stopped walking a root it is expected to cover, so every 'covered' verdict below silently excludes it. A count floor cannot see this: dropping .claude/** leaves 299 suites, above any floor loose enough not to red on a real cleanup." >&2
  fails=$((fails + 1))
fi

# --- Surface 1: explicit `run_suite … bash <path>` lines in test-all.sh --------------------
# Extracted from COMMAND position -- the token after `bash` -- never from anywhere on the
# line. run_suite's first argument is a free-form display LABEL, so a pattern that accepts the
# path anywhere after `run_suite ` is satisfied by the label alone. Measured at #7103:
# `run_suite "…/run-registered-suites.sh" bash -c true` left this linter reporting
# `orphan test suites: none` while the runner it named executed nothing.
sed -nE 's/^[[:space:]]*run_suite[[:space:]].*[[:space:]]bash[[:space:]]+"?([A-Za-z0-9._\/-]+\.test\.sh)"?([[:space:]].*)?$/\1/p' \
  "$RUNNER" | LC_ALL=C sort -u > "$WORK/raw1"

# --- Surface 2: the auto-discovery globs, ASKED OF THE RUNNER ------------------------------
# `test-all.sh --print-suite-globs` is a contract, not a parse. This file must NEVER carry its
# own copy of the patterns: with a copy, deleting a pattern from the runner stops those suites
# running while this linter, reading its stale duplicate, still reports them covered and exits
# 0. The guard would be blind to the one mutation it exists to catch, by construction.
#
# Fail CLOSED if the flag is gone: a runner that does not answer prints nothing on stdout and
# exits 2 (the flag reads as an unknown TEST_GROUP), so an unchecked capture would silently
# yield an empty pattern set and turn every glob-registered suite into a phantom orphan.
# SOLEUR_DISABLE_SESSION_STATE=1 is LOAD-BEARING, not hygiene. This is a read-only metadata
# query and must never serialize on anything — but the handler it targets sits before
# `tc_acquire` by placement alone, and placement is exactly what a future edit can change.
#
# Measured 2026-08-13: with the handler moved (or mutated) past `tc_acquire`, this invocation
# falls through into the advisory lock. When the linter runs as a registered suite INSIDE
# `test-all.sh`, the lock is held by its own parent, so the child can never acquire it — it
# waits the full `TC_LOCK_TIMEOUT` (900 s) and only then proceeds. Observed with four such
# children parked in `do_wait` at once, adding tens of minutes to a local shard.
#
# CI never sees it (`tc_acquire` returns early when `CI` is set), so this can only ever punish
# the local gate — which is the gate people stop running when it gets slow.
#
# With the kill switch set, a moved handler still fails CLOSED and fast: the flag reads as an
# unknown TEST_GROUP, the runner exits 2, and the `globs_rc != 0` branch below fires. The switch
# removes the 900 s wait, never the detection.
# `env -u TEST_GROUP` is the OTHER half, and it is the one that matters most.
#
# The fallback this whole block relies on is "an unhandled `--print-suite-globs` reads as an
# unknown TEST_GROUP, so the runner exits 2 and we fail closed". That sentence is only true when
# TEST_GROUP is UNSET. This linter runs as a registered suite inside `test-all.sh`, which exports
# `TEST_GROUP=<shard>` — so the child inherits a *valid* group, the unknown-group branch is never
# reached, and instead of exiting 2 the mutant RUNS THE ENTIRE SHARD. That shard contains this
# suite, which mutates and re-invokes again: unbounded recursion.
#
# Measured 2026-08-13, and it is not subtle:
#   TEST_GROUP unset    -> 17 rows, 65 passed, 10 s
#   TEST_GROUP=scripts  -> still running at 120 s, three nested copies of the suite alive at once
#
# It reproduces in CI, which sets TEST_GROUP per shard, and in the documented local exit gate
# (`TEST_GROUP=scripts bash scripts/test-all.sh`). It did NOT reproduce standalone, which is
# exactly why it survived: the suite's own green run leaves TEST_GROUP unset.
#
# Clearing it makes the fail-closed path unconditional — independent of whatever the caller's
# environment happens to hold, which is the only form of "fail closed" worth the name.
globs_rc=0
env -u TEST_GROUP SOLEUR_DISABLE_SESSION_STATE=1 bash "$RUNNER" --print-suite-globs > "$WORK/globs" 2>/dev/null || globs_rc=$?
globs_n=$(wc -l < "$WORK/globs" | tr -d ' ')
if (( globs_rc != 0 )) || (( globs_n < 1 )); then
  echo "ERROR: 'bash scripts/test-all.sh --print-suite-globs' exited ${globs_rc} and printed ${globs_n} pattern(s) -- this linter derives the auto-discovery surface from that flag, so without it every glob-registered suite would be reported as an orphan. Restore the flag rather than re-copying the patterns here." >&2
  fails=$((fails + 1))
fi
: > "$WORK/raw2"
while IFS= read -r pattern; do
  [[ -n "$pattern" ]] || continue
  # Expanded from REPO_ROOT so the patterns mean what they mean in the runner, which `cd`s
  # nowhere and expands them against the repo root it is invoked from.
  ( cd "$REPO_ROOT" && for f in $pattern; do [[ -f "$f" ]] && printf '%s\n' "$f"; done ) >> "$WORK/raw2" || true
done < "$WORK/globs"
LC_ALL=C sort -u -o "$WORK/raw2" "$WORK/raw2"

# --- Surface 3: the infra suites, DELEGATED to run-registered-suites.sh --------------------
# Three authorities already derive over this one domain (this file, run-registered-suites.sh's
# own report_orphans, and .github/scripts/test/test-infra-suite-registration.sh) and they
# disagreed on method. Re-grepping infra-validation.yml here would make a fourth. `--list`
# prints the runner's OWN derivation, so a change to that extraction cannot silently
# desynchronise from what this file believes runs (#7402 step 8).
#
# INFRA_ORPHAN_LIST=/dev/null suppresses the runner's own orphan section, for two reasons.
# (1) That section is a naive bare-basename `git grep` -- the technique this file rejects, and
# the one that reports a suite covered because a COMMENT names it; consuming its output would
# re-import the method through the back door. (2) It prints its members with the same
# two-space indent as the derived list and costs 10.6 s of `git grep` per invocation, against
# 0.03 s without it.
infra_rc=0
( cd "$REPO_ROOT" && INFRA_ORPHAN_LIST=/dev/null bash "$INFRA_RUNNER" --list ) > "$WORK/infra_list" 2>/dev/null || infra_rc=$?
# The header states the count the runner derived. Assert the parse recovered exactly that
# many: a header saying 98 over a body this file read as 3 is a broken parse, and a broken
# parse here manufactures 95 phantom orphans that a reader would rightly ignore -- after which
# the check is ignored permanently.
infra_declared=$(sed -nE 's/^Derived ([0-9]+) registered infra suite.*/\1/p' "$WORK/infra_list" | head -1)
sed -nE 's/^  ([A-Za-z0-9._\/-]+\.test\.sh)$/\1/p' "$WORK/infra_list" | LC_ALL=C sort -u > "$WORK/raw3"
infra_parsed=$(wc -l < "$WORK/raw3" | tr -d ' ')
if (( infra_rc != 0 )) || [[ -z "$infra_declared" ]] || [[ "$infra_declared" != "$infra_parsed" ]]; then
  echo "ERROR: 'run-registered-suites.sh --list' exited ${infra_rc} and declared '${infra_declared:-<no header>}' derived suites while this parse recovered ${infra_parsed} -- the infra registration surface is not readable, so every infra suite would be judged against an incomplete covered set." >&2
  fails=$((fails + 1))
fi

# --- Surface 4: the per-app `main.test.sh` hook in infra-validation.yml ---------------------
# One workflow step (`if [[ -f main.test.sh ]]; then bash main.test.sh; fi`, run with
# `working-directory: ${{ matrix.directory }}`) registers a suite in EVERY infra root at once,
# without naming any of them. Nothing else in this file can see that: the path on the step is
# relative, so surfaces 5 and 6 extract `main.test.sh`, which matches no tracked path.
#
# The matrix directories are computed at run time from the diff, so they cannot be read out of
# the YAML. What CAN be read is the producer's two infra-root families, stated in the
# `Find changed infra directories` step: `apps/*/infra` and `infra/<name>`. Presence of the
# hook step is the condition; the two families are the domain.
: > "$WORK/raw4"
if grep -qE '^[[:space:]]*bash[[:space:]]+main\.test\.sh[[:space:]]*$' "$INFRA_VALIDATION_WF"; then
  git -C "$REPO_ROOT" ls-files 'apps/*/infra/main.test.sh' 'infra/*/main.test.sh' \
    | LC_ALL=C sort -u > "$WORK/raw4"
fi

# --- Surface 5: single-line `run: … bash <path>.test.sh` in any workflow --------------------
# Every workflow, INCLUDING infra-validation.yml, minus whatever surface 3 already derived.
# Subtracting surface 3's actual output (rather than excluding the file, or excluding a path
# prefix) is what keeps the two surfaces disjoint AND complete: the seven suites under
# apps/web-platform/infra/<subdir>/ carry correct single-line steps but are structurally
# underivable by run-registered-suites.sh, whose extraction class excludes `/` (#7076,
# pinned as KNOWN_UNDERIVABLE in .github/scripts/test/test-infra-suite-registration.sh).
# Excluding the file would have dropped all seven and reported them as orphans.
#
# Disjointness is not cosmetic: the covered set is a UNION, so two surfaces matching one suite
# make a single-surface de-registration a silent no-op, and any mutation row aimed at it
# passes green while the suite stops running.
grep -hEo 'run:[[:space:]]+(sudo[[:space:]]+)?bash[[:space:]]+[A-Za-z0-9._/-]+\.test\.sh' \
  "$WORKFLOW_DIR"/*.yml 2>/dev/null | sed -E 's/.*bash[[:space:]]+//' \
  | LC_ALL=C sort -u > "$WORK/raw5all" || true
LC_ALL=C comm -23 "$WORK/raw5all" "$WORK/raw3" > "$WORK/raw5"

# --- Surface 6: `bash <path>.test.sh` inside a multi-line `run: |` block ---------------------
# The line carries no `run:` -- it is a body line of a block scalar -- and it may carry a
# prefix. Today's only member is `sudo bash apps/web-platform/infra/workspaces-luks-loopback.test.sh`
# at infra-validation.yml, which needs root for losetup/luksFormat.
#
# THIS SURFACE IS WHY ZERO ORPHANS IS SATISFIABLE. Without it that suite is reported as an
# orphan while it demonstrably runs in CI, and the only ways to make the report green would
# have been to excuse it with an exclusion (a false statement about a suite that runs) or to
# stop believing the report. Disjoint from 3 and 5 by construction: both of those require
# `run:` on the same line.
grep -hEo '^[[:space:]]*(sudo[[:space:]]+)?bash[[:space:]]+[A-Za-z0-9._/-]+\.test\.sh' \
  "$WORKFLOW_DIR"/*.yml 2>/dev/null | sed -E 's/.*bash[[:space:]]+//' \
  | LC_ALL=C sort -u > "$WORK/raw6" || true

# --- Assembly ------------------------------------------------------------------------------
# Each surface is intersected with the producer before it counts. A surface entry that matches
# no tracked file (`main.test.sh` from surface 4's own hook body, a path deleted but still
# referenced) is not coverage of anything, and letting it inflate a surface's count would let
# a dead reference satisfy that surface's zero-check.
: > "$WORK/covered"
surface_summary=""
for i in 1 2 3 4 5 6; do
  LC_ALL=C comm -12 "$WORK/raw${i}" "$WORK/tracked" > "$WORK/s${i}"
  n=$(wc -l < "$WORK/s${i}" | tr -d ' ')
  surface_summary="${surface_summary}s${i}=${n} "
  cat "$WORK/s${i}" >> "$WORK/covered"
  # PER-SURFACE ZERO-CHECK, not a ratcheting per-surface count. A count floor per surface has
  # to be hand-maintained on every commit that adds a suite, and -- the reason it is refused
  # here -- a count is structurally blind to a RENAME, which holds the total constant while
  # the covered set changes underneath it. This repo has shipped that exact defect. What a
  # zero-check catches is the one failure the producer floor cannot: a single surface silently
  # going dark (a renamed workflow, a changed step shape) while the other five keep the total
  # plausible and the report clean.
  if (( n < 1 )); then
    # A surface with exactly ONE member (surface 6 today: workspaces-luks-loopback.test.sh)
    # makes this check double as a tripwire on that single suite, and the two causes need
    # opposite remedies -- re-derive a broken extractor, versus drop a surface whose last
    # member legitimately went away. Naming both is the difference between a 30-second fix and
    # an investigation into an extractor that was never broken.
    echo "ERROR: registration surface ${i} matched ZERO tracked suites. Either it silently stopped matching (so every suite that depended on it is now judged against a covered set that no longer contains it -- re-derive the extractor), OR its last remaining member was legitimately deleted or relocated (in which case retire the surface deliberately, in the same commit). Check which before fixing: a surface that had exactly one member cannot tell these apart on its own." >&2
    fails=$((fails + 1))
  fi
done
LC_ALL=C sort -u -o "$WORK/covered" "$WORK/covered"
LC_ALL=C comm -23 "$WORK/tracked" "$WORK/covered" > "$WORK/orphans"

# TEST SEAM. The companion suite's single-surface precondition needs to know WHICH surfaces
# cover a given suite before it mutates one of them away: on a union, de-registering a
# double-covered suite is a no-op and the row it belongs to proves nothing while passing.
if [[ "${SOLEUR_LINT_ORPHAN_DUMP_SURFACES:-}" == "1" ]]; then
  for i in 1 2 3 4 5 6; do
    while IFS= read -r p; do [[ -n "$p" ]] && echo "SURFACE${i} ${p}"; done < "$WORK/s${i}"
  done
fi

# --- Exclusions -----------------------------------------------------------------------------
# Validated BEFORE they are applied, and fail-closed in three independent directions. Each is
# a way for an exclusion to look disciplined while masking something nobody decided to mask.
: > "$WORK/excluded"
for e in ${EXCLUSIONS[@]+"${EXCLUSIONS[@]}"}; do
  key="${e%%|*}"
  reason="${e#*|}"

  # (a) No reason, or no tracking issue.
  if [[ -z "${reason// /}" ]] || ! grep -qE '#[0-9]+' <<< "$reason"; then
    echo "ERROR: exclusion for '${key}' has no reason or no tracking issue -- an exclusion is a recorded decision with an owner, not a silent absorption." >&2
    fails=$((fails + 1))
    continue
  fi

  # (b) The key matches zero, or two or more, tracked files. Zero is a STALE key: it masks
  # nothing, reads as discipline, and survives the deletion or rename of the suite it was
  # written for. Two or more is an AMBIGUOUS key -- the basename-collision failure this
  # mechanism was re-keyed to prevent, which would excuse a suite nobody named.
  # rc captured, never bare: under this file's `set -euo pipefail` a git failure (a key git
  # rejects as a pathspec -- `../x`, a bad magic prefix) makes the pipeline non-zero and the
  # BARE assignment aborts the whole linter with git's fatal on stderr and no message of our
  # own -- before REQUIRED_RUNNERS, the relevance-array block and the tests/commands loop ever
  # run. A malformed exclusion key must fail THIS key loudly, not silently truncate the run.
  _ls_rc=0
  match_n=$(git -C "$REPO_ROOT" ls-files -- "$key" 2>/dev/null | wc -l | tr -d ' ') || _ls_rc=$?
  if (( _ls_rc != 0 )); then
    echo "ERROR: exclusion key '${key}' was rejected by git as a pathspec (rc ${_ls_rc}) -- fix the key; the walk below is otherwise unaffected." >&2
    fails=$((fails + 1))
    continue
  fi
  if [[ "$match_n" != "1" ]]; then
    echo "ERROR: exclusion key '${key}' matches ${match_n} tracked files, expected exactly 1 -- a key matching none is stale and masks nothing while looking deliberate; a key matching several excuses suites nobody named. Use the repo-relative path." >&2
    fails=$((fails + 1))
    continue
  fi

  # (c) The excluded suite is actually covered. An exclusion for a suite that RUNS is a false
  # statement in the file that exists to make coverage claims true, and it survives the fix
  # that made it unnecessary. (Caught while writing this: an intermediate revision carried
  # workspaces-luks-loopback.test.sh as an exclusion when surface 6 covers it.)
  if LC_ALL=C grep -qxF -- "$key" "$WORK/covered"; then
    echo "ERROR: exclusion for '${key}' is stale -- that suite IS covered by a registration surface, so the exclusion states something false and would mask a future regression in a suite that runs. Delete the entry." >&2
    fails=$((fails + 1))
    continue
  fi

  echo "note: ${key} excluded -- ${reason}"
  printf '%s\n' "$key" >> "$WORK/excluded"
done
LC_ALL=C sort -u -o "$WORK/excluded" "$WORK/excluded"

LC_ALL=C comm -23 "$WORK/orphans" "$WORK/excluded" > "$WORK/orphans_final"
orphan_n=$(wc -l < "$WORK/orphans_final" | tr -d ' ')
while IFS= read -r p; do
  [[ -n "$p" ]] || continue
  echo "ERROR: ${p} is never run by any runner -- it is registered in no test-all.sh line, no auto-discovery glob and no workflow step, so every assertion in it gates nothing. Add a run_suite line (or a workflow step), or add a reasoned exclusion citing a tracking issue." >&2
  fails=$((fails + 1))
done < "$WORK/orphans_final"

# Printed on every run, pass or fail. The counts are the evidence that the walk happened: a
# report with no numbers cannot be distinguished from a report over nothing, which is the
# failure the floors above exist to make impossible.
echo "walked ${tracked_n} tracked *.test.sh against 6 registration surfaces (${surface_summary}) -- $(wc -l < "$WORK/covered" | tr -d ' ') covered, ${orphan_n} orphaned"

# --- Required nested runners (#7103 R5(a)) ---------------------------------------------
# The walk above answers "is every tracked *.test.sh registered?". This answers the inverse
# question one level up: "is every nested RUNNER still registered?"
#
# The two failures are not symmetric. An unregistered suite leaves an orphan FILE that the
# walk above can find. A de-registered runner leaves NOTHING to find -- the runner still
# exists, still passes when invoked by hand, and still gates in CI; it has simply stopped
# being reachable from the local gate, taking its entire suite set with it. That is the
# #6730/#6969 shape exactly: a green summary read as evidence for suites the run never
# invoked. So the registration needs its own tombstone.
#
# Anchored on the run_suite CALL SHAPE, never the bare path. Both paths ALREADY appear in
# test-all.sh comments and echo strings (measured: 5 sites for the infra runner alone,
# including the skip messages that print the re-run command), so a bare-path grep would
# false-pass on the prose describing the registration it just lost -- the failure mode is
# not hypothetical, it is the default. cq-assert-anchor-not-bare-token.
# #7387 extends this beyond nested RUNNERS to the two legal-corpus gates' LIVE lines. The
# glob above already forces each gate's *.test.sh to be registered, but a unit suite and a
# live run answer different questions: the unit suite proves the gate can detect a planted
# defect in a sandbox, the live line is the only thing that ever points the gate at the real
# corpus. Dropping the live line leaves the unit suite green and the corpus ungated -- the
# same "named but not run" shape this file's tombstone exists to catch, one level down.
REQUIRED_RUNNERS=(
  # THIS FILE. Without the entry, deleting its run_suite line from test-all.sh silently
  # removes every check below from the blocking gate -- the exact "named but not run" shape
  # this list exists to catch, applied to the catcher.
  "scripts/lint-orphan-test-suites.sh"
  "apps/web-platform/infra/run-registered-suites.sh"
  ".github/scripts/test/run-all.sh"
  "scripts/lint-legal-scope-block-placement.sh"
  "scripts/lint-legal-mirror-drift-baseline.sh"
)
# FLOOR. `RELEVANCE_ARRAYS` got a derived floor and this list, the same shape, got none --
# `REQUIRED_RUNNERS=()` exited 0 printing `orphan test suites: none` over zero checks. Absolute and
# hand-ratcheted: unlike the gate count there is nothing in the runner to derive it from, and the
# set only ever grows.
if (( ${#REQUIRED_RUNNERS[@]} < 5 )); then
  echo "ERROR: REQUIRED_RUNNERS has ${#REQUIRED_RUNNERS[@]} entries, expected >= 5 -- an emptied or trimmed list makes every runner-registration check below pass over nothing." >&2
  fails=$((fails + 1))
fi
for r in ${REQUIRED_RUNNERS[@]+"${REQUIRED_RUNNERS[@]}"}; do
  # Escape regex metacharacters in the path (`.` in particular) so the anchor matches the
  # literal path and not an any-character wildcard.
  r_re="${r//./\\.}"
  # ANCHOR ON THE COMMAND, NOT THE LABEL. run_suite's first argument is a display label and the
  # rest is the command it executes, so a pattern that accepts the path anywhere after
  # `run_suite ` is satisfied by the LABEL alone. Measured: replacing the command while keeping
  # the label — `run_suite "apps/web-platform/infra/run-registered-suites.sh" bash -c true` —
  # left this linter reporting `orphan test suites: none`. That is the same class the tombstone
  # exists to catch, one level up: a runner that is NAMED but not RUN.
  if ! grep -qE "^[[:space:]]*run_suite .*[[:space:]]bash[[:space:]]+[\"']?${r_re}[\"']?([[:space:]]|\$)" "$RUNNER"; then
    echo "ERROR: required runner ${r} has no run_suite call in test-all.sh -- it is registered nowhere in the local gate, so its whole suite set is silently uncovered. Restore the run_suite line." >&2
    fails=$((fails + 1))
  fi
done

# --- Relevance-predicate anti-rot (ADR-181) --------------------------------------------
# The two checks above answer "is this suite registered?". This answers the question ADR-181
# created: "is the predicate that decides whether a REGISTERED suite actually executes still
# pointing at real files?"
#
# THE FAILURE THIS CATCHES. A declared path is renamed. The predicate stops matching, the suite
# is declined locally forever, and no later edit re-arms it — because the edit that broke the
# predicate is the edit that would have fixed it. Nothing else in the tree notices: the suite is
# still registered, still passes when invoked by hand, still gates in CI. Locally it has simply
# stopped running, behind a summary that now says "1 skipped" and is read as intentional.
#
# WHY THE ARRAYS LIVE IN A DATA FILE. Parsing them back out of test-all.sh was measured to match
# ZERO lines — both call sites are indented two spaces inside `if want_scripts`, so a column-0
# anchor extracts nothing and every check below would pass over an empty list. Sourcing
# test-all.sh instead is worse: it exports TMPDIR/TC_TMPDIR into this process, can `exit` this
# script from its bare-repo guard or its TEST_GROUP `case`, and calls tc_acquire — which would
# block for up to 900 s on the advisory flock this linter is ALREADY running inside, held by its
# own parent. A shared declaration source needs no derivation at all.
#
# Precedent: tests/scripts/test-zot-inventory.sh derives key lists from the producer's own arrays
# and carries the same fail-closed vacuity guard, for the same stated reason — a hand-copied list
# has gone green in this repo while the producer silently dropped two keys.
REL_LIB="$REPO_ROOT/scripts/lib/test-relevance-paths.sh"
if [[ ! -f "$REL_LIB" ]]; then
  echo "ERROR: $REL_LIB is missing -- test-all.sh sources it fail-closed, so the local gate cannot run at all." >&2
  fails=$((fails + 1))
else
  # shellcheck source=scripts/lib/test-relevance-paths.sh
  source "$REL_LIB"

  # array name | the battery file that array gates. bash 3.2 has no associative arrays and no
  # `declare -n` (macOS ships 3.2 and lefthook runs this locally), so the mapping is a
  # pipe-delimited list and the arrays are expanded by name via eval.
  #
  # The mapped value is the array's own SUITE FILE, which the self-inclusion check requires to be
  # an element of the array. It is NOT the skip_suite display label, and in this repo the two
  # differ for both batteries (`tests/scripts/test-registry-gate-mutation-battery.sh` vs the label
  # `tests/scripts/registry-gate-mutation-battery`). Anything anchoring on this field as a label
  # would red two correctly-wired suites.
  # array name | the battery file it gates | MINIMUM element count
  #
  # THE THIRD FIELD IS LOAD-BEARING. Every other check here tolerates a SHORTER array: declared,
  # non-empty, resolves, self-includes, de-referenced and prefix-covered all still pass after an
  # element is deleted, and the harness cannot help because its floor derives ELEM_TOTAL from the
  # same arrays. Measured: dropping `scripts/zot-mirror-diagnosis.sh` from the registry predicate
  # left the linter green and the harness green at one assertion fewer. The floor makes a deliberate
  # removal an explicit, reviewable edit to this number instead of a silent narrowing.
  RELEVANCE_ARRAYS=(
    "REGISTRY_BATTERY_PATHS|tests/scripts/test-registry-gate-mutation-battery.sh|9"
    "CF_TUNNEL_BATTERY_PATHS|scripts/cf-tunnel-liveness-gate-mutations.test.sh|12"
    "C4_PRODUCER_PATHS|plugins/soleur/test/c4-from-components.test.sh|6"
    "GITHUB_SCRIPTS_SUITE_PATHS|.github/scripts/test/run-all.sh|9"
  )

  # TEST_RELEVANCE_PREFIXES VACUITY. It is the one array with no fail-closed guard of its own,
  # yet the untracked arm expands it BARE. Emptied, that arm silently scopes to nothing (or aborts
  # cryptically on bash 3.2), and the prefix-coverage check below would red for every declared path
  # with a misleading message. Check the cause, not the symptom.
  if [[ "${#TEST_RELEVANCE_PREFIXES[@]}" -eq 0 ]]; then
    echo "ERROR: TEST_RELEVANCE_PREFIXES is EMPTY -- test-all.sh's untracked-file arm is scoped to nothing, so every predicate goes blind to uncommitted work." >&2
    fails=$((fails + 1))
  fi

  # DISPATCH FLOOR, DERIVED FROM THE RUNNER — not a hand-typed literal.
  #
  # Today RELEVANCE_ARRAYS=() makes the ENTIRE anti-rot block below iterate zero times while this
  # script still prints `orphan test suites: none`. That is the same vacuity the two guards below
  # exist to catch, reproduced inside the guard itself.
  #
  # Derived rather than literal for the reason the neighbouring MIN_ASSERTIONS comment in
  # scripts/test-all-infra-coverage-notice.test.sh gives: "a fixed literal acquires slack every
  # time a list grows". It also catches strictly MORE — a literal floor can only see the list
  # SHRINK, while deriving `want` from the runner catches a gate ADDED to test-all.sh and never
  # registered here, which a literal cannot see at all. Verified: this pattern matches only the
  # four real `_diff_touches "${ARRAY[@]}"` call sites and no comment in test-all.sh.
  #
  # `[A-Z0-9_]+`, NOT `[A-Z_]+`. Measured: the first form counted 3 of 4 gates, because
  # C4_PRODUCER_PATHS carries a DIGIT and a digit-free class silently skips it. The failure is the
  # worst possible shape for a floor -- it under-counts `want`, so the floor is satisfied by a
  # SHORTER list and the guard passes over exactly the gate it could not see. Any future array
  # whose name contains a digit depends on this class.
  #
  # `grep -c` EXITS 1 ON A ZERO COUNT, and this script runs under `set -e`. A bare
  # `want=$(grep -c …)` therefore ABORTS here -- and it aborts in precisely the catastrophic case
  # this floor exists to catch: every `_diff_touches` gate removed from test-all.sh. The script
  # would die at this line with no message, and every check below it (the whole per-array block,
  # the tests/commands loop, its cardinality guard) would never run, while the non-zero exit read
  # as "the linter found something". Caught by scripts/lint-shell-capture-exit.py, which is
  # registered in this same runner.
  #
  # NOT `|| true`: that collapses grep's two distinct non-zero meanings into one. Exit 1 is "zero
  # matches", a legitimate answer; exit >= 2 is a real error (an unreadable or missing runner), and
  # silently reading that as a count of 0 would make the floor pass VACUOUSLY on a file it could
  # not open -- the same fail-open shape the floor is here to close.
  # STRIPPED, and BOTH expansion shapes. `grep -c` counts LINES over unstripped source, so a future
  # doc comment quoting a gate inflates `want` into a false red -- in the very file this PR adds
  # comment blocks to. And the pattern must accept `${NAME[@]+"${NAME[@]}"}`, the set-u-safe form
  # this repo mandates elsewhere: matching only the bare shape re-creates the digit bug one idiom
  # over, under-counting `want` so a SHORTER registry satisfies the floor.
  # Match ANY dereference of a name, not an enumeration of spellings. Two earlier forms each
  # under-counted: `[A-Z_]+` missed the array whose name carries a digit, and an explicit two-shape
  # alternation still missed `"${NAME[@]:-}"`. Every miss is the same failure -- `want` drops, so a
  # SHORTER registry satisfies the floor and the unseen gate is the one that rots.
  want=$(sed 's/[[:space:]]*#.*$//' "$RUNNER" \
         | grep -cE '_diff_touches +[^#]*\$\{[A-Z0-9_]+\[@\]') || {
    grep_rc=$?
    if (( grep_rc > 1 )); then
      echo "ERROR: could not read ${RUNNER} to count _diff_touches gates (grep exit ${grep_rc}) -- the dispatch floor could not be derived, so it is not evidence about anything." >&2
      fails=$((fails + 1))
    fi
    want=0
  }
  # A zero `want` needs no floor error of its own: if the runner truly has no gates while arrays
  # are registered here, the DE-REFERENCE ANCHOR check below fires once per array, which is the
  # more specific message.
  if (( ${#RELEVANCE_ARRAYS[@]} < want )); then
    echo "ERROR: RELEVANCE_ARRAYS has ${#RELEVANCE_ARRAYS[@]} entries but test-all.sh has ${want} _diff_touches gates -- an unregistered gate rots unchecked, and an emptied list makes every check below pass over nothing." >&2
    fails=$((fails + 1))
  fi

  # `${a[@]+"${a[@]}"}` for the SAME reason the EXCLUSIONS loop above already carries it: under
  # `set -u` on bash 3.2 an EMPTY array under `[@]` aborts the script. Without it the floor's
  # message above would be followed two lines later by an `unbound variable` crash, so the
  # RELEVANCE_ARRAYS=() mutation would exit non-zero for a reason unrelated to the check under
  # test -- a guard that appears to fire while actually crashing.
  for entry in ${RELEVANCE_ARRAYS[@]+"${RELEVANCE_ARRAYS[@]}"}; do
    arr_name="${entry%%|*}"
    _rest="${entry#*|}"
    battery="${_rest%%|*}"
    min_elems="${_rest#*|}"

    # `declare -p` rather than `${#arr[@]}`: on bash 3.2 an UNSET array under `set -u` aborts the
    # script instead of reporting, which would turn a renamed array into a crash with no message.
    if ! declare -p "$arr_name" >/dev/null 2>&1; then
      echo "ERROR: relevance predicate array ${arr_name} is not declared in ${REL_LIB} -- test-all.sh references it by name, so the gated suite would abort or decline." >&2
      fails=$((fails + 1))
      continue
    fi

    # `${a[@]+"${a[@]}"}` so an EMPTY array does not trip `set -u` on bash < 4.4.
    eval "rel_elems=( \${${arr_name}[@]+\"\${${arr_name}[@]}\"} )"

    # FAIL-CLOSED VACUITY GUARD. This is the load-bearing half. Without it, emptying an array
    # makes every check below pass over nothing and this linter reports success while both
    # batteries decline on every diff forever.
    # shellcheck disable=SC2154  # rel_elems is assigned by the eval above; bash 3.2 has no
    #   declare -n, so the array must be expanded by name and shellcheck cannot follow it.
    if [[ "${#rel_elems[@]}" -eq 0 ]]; then
      echo "ERROR: relevance predicate array ${arr_name} is EMPTY -- every check over it would pass vacuously while its suite declined on every diff." >&2
      fails=$((fails + 1))
      continue
    fi

    if [[ "${#rel_elems[@]}" -lt "$min_elems" ]]; then
      echo "ERROR: ${arr_name} has ${#rel_elems[@]} elements but declares a floor of ${min_elems} -- a predicate path was removed, which every other check here tolerates. Restore it, or lower the floor deliberately in RELEVANCE_ARRAYS." >&2
      fails=$((fails + 1))
    fi

    # Each declared path must still exist in the tree. `git -C` because this linter is invocable
    # from any cwd (lefthook runs it from the repo root; a developer may not).
    for p in "${rel_elems[@]}"; do
      if ! git -C "$REPO_ROOT" ls-files --error-unmatch -- "$p" >/dev/null 2>&1; then
        echo "ERROR: ${arr_name} declares '${p}', which is not a tracked file -- the predicate can never match it, so its suite is declined locally forever." >&2
        fails=$((fails + 1))
      fi
    done

    # PREFIX COVERAGE. scripts/lib/test-relevance-paths.sh states this invariant in its own prose
    # -- TEST_RELEVANCE_PREFIXES is "the union of the top-level prefixes every declared path lives
    # under" -- and until now NOTHING enforced it. Measured: `grep -c TEST_RELEVANCE_PREFIXES` in
    # this file was 0.
    #
    # WHY IT MATTERS. test-all.sh's untracked-file arm is `git ls-files --others -- "${PREFIXES}"`,
    # so a declared path outside every prefix is invisible to the predicate WHILE UNTRACKED. The
    # failure is precisely inverted from useful: a session that ADDS a new fixture or mutation
    # target under that path and runs the gate before committing gets the suite DECLINED on the
    # one diff that needed it, and the decline reads as intentional in the summary.
    #
    # Prefix match, not equality: the prefixes are directory roots and the declared paths are
    # files or subdirectories beneath them.
    for p in "${rel_elems[@]}"; do
      covered=""
      # `$pre` OR `$pre/` -- never a bare `$pre*`. git's pathspec is path-component scoped, so
      # `scripts` matches `scripts` and `scripts/**` but NOT `scriptsx/thing.sh`. The looser form
      # certified coverage the untracked arm does not actually have.
      for pre in "${TEST_RELEVANCE_PREFIXES[@]}"; do
        [[ "$p" == "$pre" || "$p" == "$pre"/* ]] && covered=1
      done
      if [[ -z "$covered" ]]; then
        echo "ERROR: ${arr_name} declares '${p}', which lives under no TEST_RELEVANCE_PREFIXES entry -- an UNTRACKED file there is invisible to the predicate, so the suite declines on the diff that adds it." >&2
        fails=$((fails + 1))
      fi
    done

    # SELF-INCLUSION. The one element that makes new-target drift self-correcting: a commit that
    # teaches a battery to mutate something new necessarily edits the battery, so it necessarily
    # matches the predicate and necessarily runs the suite with the stale list.
    self_ok=""
    for p in "${rel_elems[@]}"; do
      [[ "$p" == "$battery" ]] && self_ok=1
    done
    # THE DATA FILE ITSELF. The HOW-TO block's site 1 says "self-including the suite's own file AND
    # this file"; only the first half was checked. Deleting the scripts/lib/test-relevance-paths.sh
    # element left every check green while a PR editing ONLY the predicate data stopped arming the
    # suite -- which is the property AC5's demonstration rests on.
    lib_ok=""
    for p in "${rel_elems[@]}"; do
      [[ "$p" == "scripts/lib/test-relevance-paths.sh" ]] && lib_ok=1
    done
    if [[ -z "$lib_ok" ]]; then
      echo "ERROR: ${arr_name} does not contain 'scripts/lib/test-relevance-paths.sh' -- a commit editing only the predicate data would not re-arm the suite, so a narrowed predicate ships unexercised." >&2
      fails=$((fails + 1))
    fi

    if [[ -z "$self_ok" ]]; then
      echo "ERROR: ${arr_name} does not contain its own battery '${battery}' -- without it, a commit adding a mutation target does not re-arm the predicate and the new target is never exercised locally." >&2
      fails=$((fails + 1))
    fi

    # DE-REFERENCE ANCHOR. Mirrors what REQUIRED_RUNNERS does for de-registered runners, one
    # level up: an array can be correct, fully resolvable, and consumed by NOTHING. Anchored on
    # the call shape, never the bare name -- the name also appears in this script and in
    # test-all.sh's comments, either of which would satisfy a bare-token grep.
    ref_re='_diff_touches "\$\{'"$arr_name"'\[@\]\}"'
    if ! grep -qE "$ref_re" "$RUNNER"; then
      echo "ERROR: test-all.sh no longer references \${${arr_name}[@]} in a _diff_touches call -- the predicate is declared but consumes nothing, so its suite is ungated or unreachable." >&2
      fails=$((fails + 1))
    fi
  done
fi

# --- tests/commands/*.sh (#7442) -------------------------------------------------------
# test-all.sh registers this directory by explicit run_suite lines with NO glob, and the walk
# above cannot see it, so the tombstone did not cover it. A suite added here without a
# run_suite line gates nothing while looking like coverage — the same class this file exists
# to catch, in a directory it could not reach.
#
# STILL NEEDED AFTER THE WHOLE-REPO WIDENING (#7402), and this is the reason: the naming
# convention here is `test-<name>.sh`, not `<name>.test.sh`, so the producer's suffix does not
# match it. Widening the walk to every directory does not widen it to every naming convention.
# The same gap covers tests/scripts/, which is floored instead by
# .github/scripts/test/run-all.sh's own MIN_SUITES.
cmd_seen=0
for f in "$REPO_ROOT"/tests/commands/*.sh; do
  [[ -e "$f" ]] || continue
  base=$(basename "$f")
  cmd_seen=$((cmd_seen + 1))

  # Anchored on the run_suite CALL SHAPE, and on the COMMAND rather than the label: the
  # label is free-form text, so a pattern accepting the path anywhere after `run_suite ` is
  # satisfied by the label alone while the command runs something else entirely.
  if ! grep -qE "^[[:space:]]*run_suite .*[[:space:]]bash[[:space:]]+[\"']?tests/commands/${base}[\"']?([[:space:]]|\$)" "$RUNNER"; then
    echo "ERROR: tests/commands/${base} is never run by test-all.sh -- add a run_suite line" >&2
    fails=$((fails + 1))
  fi
done

# Minimum-cardinality guard: a glob that matches nothing would report a clean pass and
# certify zero coverage. The directory is non-empty today; if it ever is not, that is a
# finding, not a silent green.
if (( cmd_seen < 1 )); then
  echo "ERROR: tests/commands/ matched zero suites -- the glob is broken, so this check certified nothing" >&2
  fails=$((fails + 1))
fi

if (( fails > 0 )); then
  echo "orphan test suites: $fails" >&2
  exit 1
fi
echo "orphan test suites: none"
