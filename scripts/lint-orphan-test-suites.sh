#!/usr/bin/env bash
# lint-orphan-test-suites.sh -- fail when a scripts/*.test.sh is never run by test-all.sh.
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
EXCLUSIONS=(
  "lint-agents-enforcement-tags.test.sh|pre-existing FAILURE on main (Total: 9 Pass: 7 Fail: 2), unrelated to #6734. Registering it as-is would turn test-all.sh red for a defect this PR did not introduce and does not fix. Tracked in #6751."
)

fails=0
for f in "$REPO_ROOT"/scripts/*.test.sh; do
  [[ -e "$f" ]] || continue
  base=$(basename "$f")

  excluded=""
  for e in "${EXCLUSIONS[@]}"; do
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

if (( fails > 0 )); then
  echo "orphan test suites: $fails" >&2
  exit 1
fi
echo "orphan test suites: none"
