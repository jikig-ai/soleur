#!/usr/bin/env bash
# SessionStart hook — Layer 3 of the local-Supabase loopback defence (ADR-153).
#
# Warns loudly if a local Supabase stack is running with off-loopback bindings.
# Silent when no stack is up. NEVER blocks the session: this is an advisory
# tripwire, not a gate — a developer must always be able to start a session.
#
# Layer 1 (the wrapper) prevents the exposure; Layer 2 (CI) catches it in the
# fuzz job; this layer catches the case where someone started the stack with a
# bare `supabase start`, bypassing the wrapper entirely.
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

out="$("$ASSERT" assert 2>&1)"
rc=$?

case "$rc" in
  1)
    # EXPOSED. This is the whole reason the hook exists — make it loud.
    echo "" >&2
    echo "  ############################################################" >&2
    echo "  #  WARNING: local Supabase stack is reachable OFF-LOOPBACK  #" >&2
    echo "  ############################################################" >&2
    printf '%s\n' "$out" | sed 's/^/  /' >&2
    echo "" >&2
    echo "  Postgres and the unauthenticated Studio UI are exposed to your" >&2
    echo "  whole network. On an untrusted network this is a live data risk." >&2
    echo "" >&2
    echo "  Fix:  cd apps/web-platform && npm run db:stop && npm run db:start" >&2
    echo "  (see ADR-153 — the CLI has no bind setting; the wrapper is the fix)" >&2
    echo "" >&2
    ;;
  2)
    # Docker unreachable. Not a finding — stay quiet rather than nag on every
    # session where the daemon simply is not running.
    :
    ;;
  *)
    # 0 = loopback-only or no stack. Silent by design.
    :
    ;;
esac

exit 0
