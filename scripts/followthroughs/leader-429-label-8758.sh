#!/usr/bin/env bash
# Follow-through probe for #8783: the leader loop labels a retry-exhausted
# Anthropic 429 as anthropic_timeout, because the error's status is stripped at
# the Inngest step boundary.
#
# PASS (exit 0) once main's handler tags the live error inside the step
# (`tagTransientAnthropicError`, `TRANSIENT_ANTHROPIC_CAUSES`) AND no longer
# carries the old unconditional catch-all `return "anthropic_timeout";`. FAIL
# (exit 1) otherwise, so the sweeper comments and the issue stays open. A read
# that returns nothing is TRANSIENT (exit 2), never FAIL.
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
# Herestrings, not pipes: `grep -q` closing early would SIGPIPE a pipe writer.
if ! grep -Eq 'function tagTransientAnthropicError' <<<"$content"; then
  printf 'FAIL: %s on main does not tag transient Anthropic errors in-step\n' "$path"
  exit 1
fi
if ! grep -Eq 'TRANSIENT_ANTHROPIC_CAUSES' <<<"$content"; then
  printf 'FAIL: %s on main has no TRANSIENT_ANTHROPIC_CAUSES\n' "$path"
  exit 1
fi
if grep -Fq 'return "anthropic_timeout";' <<<"$content"; then
  printf 'FAIL: %s on main still falls through to anthropic_timeout\n' "$path"
  exit 1
fi
printf 'PASS: %s on main labels retry-exhausted Anthropic errors by an in-step tag\n' "$path"
exit 0
