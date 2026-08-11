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
