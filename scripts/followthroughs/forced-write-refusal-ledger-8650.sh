#!/usr/bin/env bash
# Follow-through verification: durable visibility for a refused/forced
# production-write attempt (PR #8650 scope-out, review #8650, #8486).
#
# Mirror of scripts/followthroughs/sentry-checkins-3859.sh.
#
# Exit semantics (enforced by scripts/sweep-followthroughs.sh):
#   0 = PASS         (close-criteria met; sweeper closes the issue)
#   1 = FAIL         (criteria not met; sweeper comments, leaves open)
#   * = TRANSIENT    (network error, unexpected state; sweeper retries next sweep)
#
# Convention: knowledge-base/engineering/operations/runbooks/followthrough-convention.md

set -uo pipefail

case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this probe handles live credentials and -x would print them (see #7797)\n' >&2; exit 78 ;;
esac

# soleur:followthrough-stub v1

# The scope-out's re-evaluation trigger: re-open once ANY observability sink
# (Sentry / Better Stack) is wired into operator-script.sh for any other
# event -- at that point the ack-refusal event should be routed through the
# same sink instead of staying local-only. A match means the trigger fired;
# the sweeper closes the tracker and the next review picks up the routing.
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "TRANSIENT: not inside a git checkout" >&2; exit 2; }
LIB="$ROOT/plugins/soleur/scripts/lib/operator-script.sh"
[[ -r "$LIB" ]] || { echo "TRANSIENT: $LIB not found" >&2; exit 2; }

if grep -qE 'Sentry|BetterStack' "$LIB"; then
  echo "PASS: operator-script.sh now references an observability sink -- route the ack-refusal event through it"
  exit 0
else
  echo "FAIL: no observability sink referenced yet in operator-script.sh; scope-out still open"
  exit 1
fi
