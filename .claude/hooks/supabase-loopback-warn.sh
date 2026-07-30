#!/usr/bin/env bash
# SessionStart hook — Layer 3 of the local-Supabase loopback defence (ADR-153).
#
# Warns if a local Supabase stack is running with off-loopback bindings. Silent
# when no stack is up. NEVER blocks the session: this is an advisory tripwire,
# not a gate — a developer must always be able to start a session.
#
# Layer 1 (the wrapper) prevents the exposure; Layer 2 (CI) catches it in the
# fuzz job; this layer catches the case where someone started the stack with a
# bare `supabase start`, bypassing the wrapper entirely.
#
# OUTPUT CHANNEL (load-bearing — this was wrong in the first revision):
# `systemMessage` on STDOUT is the operator-visible channel for an exit-0 hook.
# Plain stderr is DISCARDED there (`.claude/hooks/README.md`), so the original
# "make it loud" stderr block was silent — a dark tripwire that read as
# protection. Same defect class the sibling `pre-merge-auto-close-scan.sh`
# header documents ("Silence is how the PR-body arm stayed dead for 17 days at
# 8/8 green"). stderr is kept as a SECOND sink for the interactive case, but
# the systemMessage is what actually reaches the operator.
#
# Exits 0 unconditionally.

set -uo pipefail   # deliberately NOT -e: a probe failure must not abort the hook

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
ASSERT="${PROJECT_DIR}/apps/web-platform/scripts/supabase-local.sh"

# Nothing to do if the wrapper is absent (e.g. a worktree predating it).
[[ -x "$ASSERT" ]] || exit 0

# Skip silently when docker is not installed — the overwhelmingly common case
# for sessions that never touch the local stack.
command -v docker >/dev/null 2>&1 || exit 0

# Bound the probe so an unresponsive Docker socket cannot hang SessionStart.
# Two sibling hooks wrap external CLIs this way (pre-merge-auto-close-scan.sh,
# ship-net-issue-flow-gate.sh) — measured, not estimated. Without it, a wedged
# daemon blocks every new session — an availability regression introduced by a
# purely advisory check.
# `timeout` is NOT universally present — macOS ships none in the base system
# (it is `gtimeout` from coreutils). Hardcoding it made the hook exit 127,
# miss the `rc -eq 1` branch, and go SILENT over an exposed stack: a dark
# tripwire, the same defect class as the stderr channel bug above.
TO=(); command -v timeout >/dev/null 2>&1 && TO=(timeout 10)
out="$("${TO[@]}" "$ASSERT" assert 2>&1)"
rc=$?

# rc 124 = timeout killed it. Treat as UNKNOWN, stay quiet (same disposition as
# an unreachable daemon): a slow socket is not evidence of exposure.
if [[ "$rc" -eq 1 ]]; then
  msg="WARNING: your local Supabase stack is reachable OFF-LOOPBACK.

${out}

Postgres and the unauthenticated Studio UI are exposed to your whole network.
On an untrusted network this is a live data risk.

Fix:  cd apps/web-platform && npm run db:stop && npm run db:start
(ADR-153 — the Supabase CLI has no bind setting; the wrapper is the fix.)"

  # Operator-visible channel. jq is present in this repo's hook environment;
  # if it is somehow absent, fall through to stderr rather than emitting
  # malformed JSON that the harness would reject.
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg m "$msg" '{systemMessage:$m}' 2>/dev/null
    printf '%s\n' "$msg" >&2
    exit 0
  fi

  # No jq: systemMessage is unavailable, and this file's own header records
  # that plain stderr is DISCARDED on an exit-0 hook — so exiting 0 here would
  # write the warning to the one sink documented not to work. Exit 1 surfaces
  # stderr as a non-blocking hook notice, preserving the NEVER-blocks contract.
  printf '%s\n' "$msg" >&2
  exit 1
fi

exit 0
