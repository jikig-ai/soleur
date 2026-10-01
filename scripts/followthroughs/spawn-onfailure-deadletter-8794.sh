#!/usr/bin/env bash
# Follow-through probe for the #8794 scope-out: agent-on-spawn-requested runs that
# end without persistFailure (retry-exhausted throws, the finish timeout,
# cancellation) get no failure_reason, no tagged dead-letter event and no page.
#
# PASS (exit 0) only once main's handler carries an `onFailure` handler — the fix
# this issue asks for. Before that, FAIL (exit 1) so the sweeper comments and the
# issue stays open. A read that returns nothing is TRANSIENT (exit 2), never FAIL.
#
# Convention: knowledge-base/engineering/operations/runbooks/followthrough-convention.md

set -uo pipefail
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this probe handles live credentials and -x would print them (see #7797)\n' >&2; exit 78 ;;
esac

# soleur:followthrough-stub v1

path="apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts"
rc=0
content="$(gh api -H 'Accept: application/vnd.github.raw' "repos/jikig-ai/soleur/contents/${path}?ref=main")" || rc=$?
if [ "$rc" -ne 0 ] || [ -z "$content" ]; then
  printf 'TRANSIENT: could not read %s on main (rc=%s)\n' "$path" "$rc"
  exit 2
fi
# Herestring, not a pipe: `grep -q` closing early would SIGPIPE a pipe writer.
if grep -Eq '^[[:space:]]*onFailure[[:space:]]*:' <<<"$content"; then
  printf 'PASS: %s on main declares an onFailure handler\n' "$path"
  exit 0
fi
printf 'FAIL: %s on main still has no onFailure handler\n' "$path"
exit 1
