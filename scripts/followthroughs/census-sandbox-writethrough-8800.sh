#!/usr/bin/env bash
# census-sandbox-writethrough-8800.sh — re-evaluation gate for the scope-out
# filed from PR #8765's review (build_census_sandbox shares inodes/symlinks
# with the live repo — a write-through hazard that is latent today because the
# censused linter is read-only).
#
# Exit semantics (sweep-followthroughs.sh contract):
#   0 = PASS (the earliest= wall-clock gate alone defers closure; nothing else
#        is asserted — the issue body is the re-eval record)
#   2 = TRANSIENT otherwise
set -uo pipefail

case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this probe handles live credentials and -x would print them (see #7797)\n' >&2; exit 78 ;;
esac

# Date-trigger stub: the earliest= directive field is the deferral; once it
# passes, the sweeper re-surfaces the issue for triage rather than closing a
# decision that is not mechanically decidable.
echo "RE-EVAL DUE: census sandbox write-through hazard — see issue body"
exit 0
