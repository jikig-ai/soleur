# Learning: a lazily-created parent row makes every "upload then reference it" flow fragile

## Problem

A user attached a `.md` to a fresh chat and the tile showed a raw `conversation_not_found`; the message also went out without the file. Root cause was not the composer: a `conversations` row does not exist until the first `chat` WebSocket message (deferred creation), so presign against the route id `"new"` — and even against the server's *pending* UUID — 404ed. Three separate defects shared that one fact: the composer passed the route sentinel, the first-run flow sent the message before uploading (and uploaded nothing for an empty message), and the tile rendered the raw error code.

## Solution

- Presign: strict lowercase-UUID shape check BEFORE any DB call, `.maybeSingle()` with the error checked first, and an absent row is the expected state (caller-prefixed own-folder path). A DB error must not fall through to the tolerant branch.
- ws-handler: accept an attachments-only first message, but validate every ref BEFORE `createConversation`.
- Client: one `runFirstRunSend` that uploads first and sends once, gated by an explicit `fr=1` marker (the pending-file store is module-global).

## Key Insight

When a flow references a parent id that is only materialized by the act it precedes, list every gate that keys on "the parent exists" and decide each one deliberately. Relaxing one gate (presign) moves the real check to another (the pipeline's prefix check), so the validation must be ONE shared function, not a second hand-written copy.

## Session Errors

- **Duplicated validation drifted on day one.** The ws pre-validation re-implemented three of the pipeline's four per-ref checks and omitted the extension check; review (six seats converged) found a forged-extension ref could still create an empty conversation, and the same gap applied whenever text was present. Recovery: extracted `validateAttachmentRef`, ran it for any non-empty attachments. **Prevention:** when a plan says "validate X before Y" and the same validation already exists after Y, extract the shared function first and call it from both sites.
- **Vacuous negative assertions.** `not.toHaveBeenCalledWith(expect.anything(), ...)` can never fail when production passes `null` first (`expect.anything()` does not match null). Recovery: assert over `mock.calls.some(...)`. **Prevention:** a "was not called" assertion needs a positive control asserting the same matcher DOES match the real call shape.
- **Stale closure dependency.** `uploadAttachments` closed over `conversationId` with deps `[attachments]`, so a reconnect-minted pending id presigned under a dead id. **Prevention:** any prop that can become `null`/change over a session belongs in the deps of callbacks that read it, with a rerender (not remount) test.
- **Stale planning subagent notifications.** The plan+deepen subagent returned "stopped with background work still running" and re-notified about 20 times (each a leftover wait-loop timer), churning the turn. Recovery: `TaskStop` on its id. **Prevention:** after a planning subagent returns its Session Summary, `TaskStop` it if its notification says it stopped with background work of its own.
- **Commit hook blocked ~10 min under contention.** `bun-test` (the affected battery) ran behind a saturated machine. Recovery: killed it and committed with `LEFTHOOK_EXCLUDE=bun-test,web-platform-typecheck` on explicit operator instruction (CI is the gate). **Prevention:** none new; `LEFTHOOK_EXCLUDE` is already the documented narrow escape.
- **Playwright MCP disconnected.** The e2e/nav-states gate was deferred to CI's containerized job.

## Tags
category: logic-errors
module: web-platform/attachments
