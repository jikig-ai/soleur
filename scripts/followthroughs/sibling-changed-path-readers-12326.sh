#!/usr/bin/env bash
# Follow-through verification (date shape) for the scope-out filed from PR #12326 review:
# the sibling readers of changed-path lists (battery-refusal-wait.sh, test-all.sh _diff_names, CI workflow
# regexes, skill prose) still need the -z / --ignore-submodules=none construction battery-owed.sh now uses.
#
# Date trigger: the `earliest=` wall-clock gate in the issue directive defers closure until 2026-12-07; this
# body is the trivial `exit 0` the convention prescribes for that shape. Reaching the date CLOSES the tracker
# for re-evaluation -- it does not assert the sweep was done.
#
# Convention: knowledge-base/engineering/operations/runbooks/followthrough-convention.md

set -uo pipefail

case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this probe handles live credentials and -x would print them (see #7797)\n' >&2; exit 78 ;;
esac

# soleur:followthrough-stub v1

exit 0
