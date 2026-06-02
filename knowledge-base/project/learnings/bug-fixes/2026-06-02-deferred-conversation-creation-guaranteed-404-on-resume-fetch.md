---
title: "Deferred conversation creation + unconditional resume-fetch = guaranteed-404 error-noise on every fresh open"
date: 2026-06-02
category: bug-fixes
module: apps/web-platform (kb-chat, ws-client, api-messages)
tags: [kb-chat, deferred-creation, ws-client, observability, silent-fallback, enum-gate, sentry-noise]
issues: []
pr: 4816
---

# Deferred conversation creation vs. unconditional resume-history fetch

## Problem

Opening a brand-new KB-chat conversation surfaced "An unexpected error occurred."
and emitted a `history-fetch-404-not-owned-or-missing` **error-level** Sentry event
on BOTH server and client on *every* fresh open (Sentry alert "kb-chat silent
fallback", op `history-fetch-404-not-owned-or-missing`, `GET /api/conversations/{id}`).

## Root cause

The WS server uses **deferred conversation creation** (see
[[2026-04-11-deferred-ws-conversation-creation-and-pending-state]]): `start_session`
mints a UUID and emits `session_started` **without inserting a DB row** — the row
materializes only on the first real chat message. A genuine resume emits
`session_resumed` (row already exists).

The client could not tell the two apart at the fetch site. The resume-history
`useEffect` in `lib/ws-client.ts` fired `GET /api/conversations/{pendingUUID}/messages`
for **any** resolved `realConversationId` while `conversationId === "new"` — it did
not gate on whether the session was fresh or resumed. So a fresh deferred UUID hit
`.single()` on a non-existent row → 404 → `reportSilentFallback(...)` at **error**
level on both server (`server/api-messages.ts`) and client. Guaranteed, on the
single most common entry into the product's core chat surface.

## Solution

**Client-side discrimination, not server restructuring** (the deferred model is
correct and stays — it exists to avoid junk inbox rows):

1. Add a client-local `sessionKind: "fresh" | "resumed" | null` state to
   `useWebSocket`, set `"fresh"` in the `session_started` handler and `"resumed"`
   in `session_resumed`. Gate the resume-history effect on `sessionKind === "resumed"`.
   A fresh deferred conversation now skips the would-be-404 fetch entirely.
2. Key the gate on **session kind, not message count** — a `session_resumed` row
   with 0 messages is a real row (200-empty path) and must still fetch.
3. Defense-in-depth: downgrade the expected row-absent 404 from `error` →
   `warning` (`warnSilentFallback`) on both server and client (client only when
   `res.status === 404`). HTTP status + op string unchanged so alert rules keep
   matching; genuine 401/500 stay `error` and still page.
4. Reset `sessionKind` wherever `realConversationId` is reset (teardown) so the
   two stay paired — defends the gate against future refactors.

## Key insight

When a system **defers** creation of a resource (lazy row insert, lazy file
materialization, optimistic UUID), any consumer that fetches that resource by id
**must carry a discriminator for "exists yet vs. not"** — otherwise the
not-yet-created window produces a guaranteed-404 on the hottest path, and routing
that expected 404 through an error-level mirror floods the alert stream and masks
the next real regression on the same endpoint. The discriminator is usually
already on the wire (here, the distinct `session_started` vs `session_resumed`
message types); make it explicit at the fetch decision rather than coupling to a
UX-state proxy.

Corollary (review): a single-literal gate over a multi-member union
(`if (sessionKind !== "resumed")` over `"fresh" | "resumed" | null`) is correct
only if every member is classified — enumerate each (null → skip, "fresh" → skip,
"resumed" → fetch) and confirm no code path resolves the id without also setting
the discriminator. And when downgrading a Sentry severity, verify the destination
alert rule still matches (same `op`/`feature` tags) so you don't create a silent
never-page.

## Session Errors

1. **CWD-relative path drift across Bash calls.** Several Bash calls failed
   (`cd: apps/web-platform: No such file or directory`, `ls: cannot access
   'knowledge-base/...'`, `ugrep: lib/ws-client.ts: No such file or directory`)
   because the Bash tool does not persist CWD and it drifted between the worktree
   root and `apps/web-platform` (semgrep/test-all run from root; vitest/tsc run
   from the app dir). **Recovery:** absolute `cd <abs> && cmd`. **Prevention:**
   already covered by the `/work` rule "chain `cd <worktree-abs-path> && <cmd>`
   in a single Bash call" — no new rule needed.

## References

- [[2026-04-11-deferred-ws-conversation-creation-and-pending-state]] — deferred-creation rationale
- `apps/web-platform/lib/ws-client.ts` — sessionKind gate + 404→warning client mirror
- `apps/web-platform/server/api-messages.ts` — 404→warning server mirror
