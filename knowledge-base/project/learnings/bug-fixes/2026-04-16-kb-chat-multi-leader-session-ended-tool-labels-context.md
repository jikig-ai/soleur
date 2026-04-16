# Learning: KB chat multi-leader session lifecycle, tool labels, document context

## Problem

Three interrelated bugs in the KB chat feature:

1. **Agents never stop working** — In multi-leader dispatch, each leader's `startAgentSession` sent its own `session_ended` event. The first leader to finish triggered the client's `session_ended` handler which called `activeStreamsRef.current.clear()` and `clearAllTimeouts()`, killing ALL other leaders' streams. Remaining leaders appeared stuck in "Working" state forever.

2. **No substantive interim messages** — The `TOOL_LABELS` map was a static lookup (`Read → "Reading file..."`, `Bash → "Running command..."`) with no input details. Users saw generic status while agents worked.

3. **PDF context not used** — When `context.path` was set but `context.content` absent (PDFs, large files), agents received a passive "Read this file first" instruction that was weak enough for them to ignore and ask "which PDF are you referring to?" instead.

## Solution

1. **skipSessionEnded parameter** — Added `skipSessionEnded?: boolean` to `startAgentSession`. `dispatchToLeaders` passes `true` for multi-leader dispatch and sends a single `session_ended` after `Promise.allSettled` resolves. Single-leader flow unchanged (backward compatible).

2. **buildToolLabel function** — Extracted to `server/tool-labels.ts`. Extracts file paths from Read/Edit/Write, command text from Bash, patterns from Grep/Glob. Strips workspace paths. Truncates at 60 chars.

3. **Three-tier context injection** — (a) Client-provided content → inline directly, (b) Server-read text under 50KB → inject into system prompt, (c) PDF or oversized files → assertive Read instruction. All branches include "Do not ask which document" language. Path traversal guarded by `isPathInWorkspace`.

## Key Insight

When multiple async operations share a global lifecycle signal (`session_ended`), each operation must NOT emit it independently. The orchestrator (`dispatchToLeaders`) owns the lifecycle boundary, individual workers own only their own stream boundaries (`stream_end`).

## Session Errors

1. **TDD violation — implementation before tests** — Started writing implementation code before writing failing tests, creating flat tasks instead of RED/GREEN pairs. User caught the violation. Recovery: Reverted implementation, restructured tasks as RED/GREEN pairs with blockedBy dependencies. **Prevention:** Add post-task-creation validation in work skill Phase 1 that scans for implementation tasks without RED test blockers.

2. **Test case sensitivity mismatch** — Tests checked for `"do not ask which document"` but implementation used uppercase `"Do not ask..."`. Recovery: Fixed test assertions. **Prevention:** Normal RED/GREEN cycle catches this; no structural fix needed.

3. **Missing supabase rpc mock** — Test helper's supabase mock lacked `rpc` method, causing result handler to throw. Recovery: Added `rpc: vi.fn().mockResolvedValue({ error: null })` to the test's supabase mock. **Prevention:** Consider adding `rpc` to the shared `createSupabaseMockImpl` helper for future tests that exercise the result handler path.

## Tags

category: bug-fixes
module: kb-chat, agent-runner, tool-labels
