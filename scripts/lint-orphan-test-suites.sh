#!/usr/bin/env bash
# lint-orphan-test-suites.sh -- fail when a scripts/*.test.sh, or a required nested RUNNER,
# is never run by test-all.sh.
#
# WHY (#6734): test-all.sh's glob covers `scripts/lib/*.test.sh` but NOT `scripts/*.test.sh`,
# which must be registered by hand. Three suites had silently never run in any CI job.
# That is worse than having no suite at all: a test added to an orphan file gates nothing
# while looking like coverage. This PR's own #6734 work added a residue harness to exactly
# such a file, so the gap was load-bearing at the moment it was found.
#
# Deliberately ~20 lines with NO companion .test.sh: a 150-line suite testing a grep
# would reproduce the orphan problem in miniature. AC3 mutation-proves it inline instead
# (delete a run_suite line -> this must exit non-zero).
#
# Exclusions carry a REASON and a tracking issue. An exclusion without both is an error --
# the point is that skipping is a recorded decision, not a silent absorption.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$REPO_ROOT/scripts/test-all.sh"

# name | reason (must cite a tracking issue)
#
# EMPTY IS THE GOAL STATE. lint-agents-enforcement-tags.test.sh was excluded
# here as a pre-existing failure (7/9) tracked in #6751; #7172 fixed the
# defect, registered both suites in test-all.sh, and removed the exclusion.
# Leaving a stale exclusion behind would re-hide the next regression in the
# very suite that was just repaired.
EXCLUSIONS=()

fails=0
for f in "$REPO_ROOT"/scripts/*.test.sh; do
  [[ -e "$f" ]] || continue
  base=$(basename "$f")

  excluded=""
  # `${a[@]+"${a[@]}"}` so an EMPTY exclusion list does not trip `set -u` on
  # bash < 4.4 (macOS still ships 3.2). Empty is now the expected state.
  for e in ${EXCLUSIONS[@]+"${EXCLUSIONS[@]}"}; do
    [[ "${e%%|*}" == "$base" ]] && excluded="${e#*|}"
  done
  if [[ -n "$excluded" ]]; then
    # Fail-closed on a reasonless or issue-less exclusion.
    if [[ -z "${excluded// /}" ]] || ! grep -qE '#[0-9]+' <<< "$excluded"; then
      echo "ERROR: exclusion for $base has no reason or no tracking issue" >&2
      fails=$((fails + 1))
    else
      echo "note: $base excluded -- $excluded"
    fi
    continue
  fi

  # Anchor on the run_suite CALL SHAPE, not a bare filename: the bare name also appears
  # in comments and in this script's own EXCLUSIONS, either of which would let an
  # unregistered suite pass vacuously (cq-assert-anchor-not-bare-token).
  if ! grep -qE "^[[:space:]]*run_suite .*[\"' ]scripts/${base}([\"' ]|$)" "$RUNNER"; then
    echo "ERROR: scripts/${base} is never run by test-all.sh -- add a run_suite line, or add a reasoned exclusion citing a tracking issue" >&2
    fails=$((fails + 1))
  fi
done

# --- Required nested runners (#7103 R5(a)) ---------------------------------------------
# The loop above answers "is every scripts/*.test.sh registered?". This answers the inverse
# question one level up: "is every nested RUNNER still registered?"
#
# The two failures are not symmetric. An unregistered suite leaves an orphan FILE that the
# glob above can find. A de-registered runner leaves NOTHING to find -- the runner still
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
  "apps/web-platform/infra/run-registered-suites.sh"
  ".github/scripts/test/run-all.sh"
  "scripts/lint-legal-scope-block-placement.sh"
  "scripts/lint-legal-mirror-drift-baseline.sh"
)
for r in "${REQUIRED_RUNNERS[@]}"; do
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
  RELEVANCE_ARRAYS=(
    "REGISTRY_BATTERY_PATHS|tests/scripts/test-registry-gate-mutation-battery.sh"
    "CF_TUNNEL_BATTERY_PATHS|scripts/cf-tunnel-liveness-gate-mutations.test.sh"
    "C4_PRODUCER_PATHS|plugins/soleur/test/c4-from-components.test.sh"
    "GITHUB_SCRIPTS_SUITE_PATHS|.github/scripts/test/run-all.sh"
  )

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
  want=$(grep -cE '_diff_touches "\$\{[A-Z0-9_]+\[@\]\}"' "$RUNNER")
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
    battery="${entry#*|}"

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
      for pre in "${TEST_RELEVANCE_PREFIXES[@]}"; do
        [[ "$p" == "$pre"* ]] && covered=1
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
# test-all.sh registers this directory by explicit run_suite lines with NO glob, and the
# scripts/*.test.sh loop above cannot see it, so the tombstone did not cover it. A suite
# added here without a run_suite line gates nothing while looking like coverage — the same
# class this file exists to catch, in a directory it could not reach.
#
# The naming convention differs (`test-<name>.sh`, not `<name>.test.sh`), which is exactly
# why the existing glob misses it rather than merely under-matching.
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
