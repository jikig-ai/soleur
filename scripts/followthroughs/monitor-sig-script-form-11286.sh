#!/usr/bin/env bash
# Follow-through verification stub (template).
#
# Date-shaped re-evaluation reminder for the monitor_sig script-form gap (deferred from PR #11286).
# The directive's earliest= is the whole gate: this script only reports that the date arrived, so the sweeper comments and a human decides.
#
# Exit semantics (enforced by scripts/sweep-followthroughs.sh):
#   0 = PASS         (close-criteria met; sweeper closes the issue)
#   1 = FAIL         (criteria not met; sweeper comments, leaves open)
#   2 = NOT YET      (rendered "NOT YET"; the issue stays open)
#   3 = CANNOT ESTABLISH (rendered as such; the issue stays open: use it when a read the verdict depends on failed)
#   5 = ACTION REQUIRED  (rendered as such; a human must act)
#   * = TRANSIENT    (any other code: network error, unexpected state; sweeper retries next sweep)
#
# Required secrets: declare via the directive `secrets=` clause AND add to
# .github/workflows/scheduled-followthrough-sweeper.yml env: block.
#
# Convention: knowledge-base/engineering/operations/runbooks/followthrough-convention.md

set -uo pipefail

# REFUSE TO RUN UNDER XTRACE (#7797). A probe receives its secrets from the
# sweeper's env, and tracing echoes commands AFTER expansion -- so a credential
# leaks the moment it is used, and the sweeper posts probe output into a public
# issue comment. Unconditional is the safe default for a scaffold, because the
# template cannot know which credentials this probe will end up reading.
#
# If your probe INHERITS a known, fixed set of credentials, you may narrow this
# to a hatch that keeps the script traceable when they are unset:
#
#   case "$-" in
#     *x*)
#       if [ -n "${YOUR_TOKEN:+x}" ]; then   # `:+x` -- `:-` would PRINT the value
#         printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
#         exit 78
#       fi
#       ;;
#   esac
#
# Keep it directly below `set ...`: `scripts/lint-shell-trace-credential-refusal.py`
# requires the refusal in the prologue, before any command that could be traced.
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this probe handles live credentials and -x would print them (see #7797)\n' >&2; exit 78 ;;
esac

# soleur:followthrough-stub v1

# Date trigger: exit 0 once the sweeper's `earliest` gate has passed. There is deliberately no other probe;
# whether the hook gap still matters is the human re-evaluation this reminder exists to prompt.
echo "PASS: re-evaluation date reached - decide whether .claude/hooks/lib/monitor_sig needs a monitor-pr-checks.sh arm (see the issue body)"
exit 0
