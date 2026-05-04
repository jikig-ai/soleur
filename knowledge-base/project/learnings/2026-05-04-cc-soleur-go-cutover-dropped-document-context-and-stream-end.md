---
date: 2026-05-04
category: integration-issues
tags: [cc-soleur-go, kb-concierge, regression, sdk-router, streaming-input]
pr: 3213
related-prs: [2901, 2923, 2954]
---

# Learning: cc-soleur-go cutover dropped legacy document-context injection and per-turn stream_end

## Problem

Three user-visible regressions surfaced in the KB Concierge "Ask about
this document" panel after the PR #2901 Stage 2.12 cutover from the
legacy `agent-runner.ts` path to the streaming-input cc-soleur-go runner:

1. **PDF context lost.** Opening a PDF and asking "summarize this
   document" returned "no document was attached." The legacy
   `agent-runner.ts § "Inject artifact context"` (~lines 590-635) had
   been silently bypassed -- `dispatchSoleurGo` and
   `dispatchSoleurGoForConversation` never threaded `pendingContext`
   into the new system prompt.
2. **Yellow-square avatar.** `cc_router` had `defaultIcon: ""` and no
   `ICON_MAP` entry, so `LeaderAvatar` rendered an empty lucide-icon
   branch over the `bg-yellow-500` background.
3. **Markdown not rendered.** Concierge replies showed raw `**bold**`
   and `- ` instead of formatted output. `chat-state-machine.ts:484-516`
   already special-cased `cc_router` for `stream_end`, but the server
   never emitted `stream_end` -- only `stream` partials. The bubble
   never transitioned to `state: "done"`, so MarkdownRenderer never
   engaged.

## Root cause

A long-lived streaming-input `Query` in cc-soleur-go has its system
prompt baked at cold-Query construction. The cutover (PR #2901) wired
the new runner without porting two load-bearing pieces of the legacy
path:

- The **context-injection contract** (caller-provided / server-read /
  Read-directive tiers, 50KB inline cap, `isPathInWorkspace` guard) --
  PR #2954 partially fixed this for `artifactPath` in the system
  prompt template but never added the dispatcher wiring to feed it.
- The **per-turn stream_end signal** -- the SDK emits `result` blocks
  per turn; the runner's `handleResultMessage` had no event hook for
  the dispatcher to forward as `stream_end`.

## Solution

1. **Thread context through every layer.** Added `artifactPath`,
   `documentKind`, `documentContent` to `DispatchSoleurGoArgs ->
   runner.dispatch -> buildSoleurGoSystemPrompt`. PDFs get a Read
   directive; small text inlines under the 50KB cap; oversized falls
   through to instruction-only. Source of truth for the legacy parity:
   new `kb-document-resolver.ts` (extracted from `cc-dispatcher.ts` so
   the orchestration layer doesn't carry filesystem responsibility).
2. **Avatar.** Coalesced `cc_router` into the existing `isSystem` logo
   branch in `LeaderAvatar`. Used a new client-safe
   `lib/cc-router-id.ts` to avoid pulling pino-laden `@/server/*` into
   the browser bundle.
3. **Per-turn boundary event.** Added `onTextTurnEnd?: () => void` to
   `DispatchEvents`; runner fires it in `handleResultMessage`
   immediately after `onResult`; dispatcher forwards to
   `sendToClient({ type: "stream_end", leaderId: CC_ROUTER_LEADER_ID })`.

## Key insight

When a long-lived `Query` replaces a per-request runner, the cutover
must port **three** invisible contracts, not just the message API:

1. **Per-turn lifecycle events** (start/end signals the client reducer
   needs to transition state).
2. **Context-injection seams** (paths the prior runner read at
   construction time -- PDFs, attached docs, system files).
3. **Identity / presentation metadata** (avatar, color, label slots
   the UI keys off the leader id).

Greppable handle: search for every consumer of the legacy entry point
and verify each consumer's downstream dependencies (state machine
transitions, asset maps, presence tables) have a corresponding cold-Query
provision before deleting the legacy path.

## Prevention

- **Cutover checklist for streaming-input migrations.** Before deleting
  a per-request runner, enumerate: (a) every value the old runner read
  at construction, (b) every event the client reducer keys off, (c)
  every leader-id-keyed presentation map. Each item needs an explicit
  forwarding path or a documented decision to drop it.
- **Defense-in-depth on the resolver path.** The new
  `resolveConciergeDocumentContext` enforces a `knowledge-base/`
  prefix even though `isPathInWorkspace` already blocks parent
  traversal. `validateContextPath` (used for `resumeByContextPath`)
  already had this guard; `validateConversationContext` did not. Bring
  both paths to parity when adding a new injection seam.
- **PII redaction in Sentry breadcrumbs.** KB paths can carry
  user-identifying segments (`knowledge-base/customers/jane-doe.md`).
  Default Sentry scrubbing matches on field NAMES (password / email /
  ssn) -- not on `path` values. Log `path.basename(contextPath)` only.

## Session Errors

- **Stale dev server on port 3000** (PID 3582586, 8h old, 5xx-responding).
  Recovery: `kill <pid>` then restart. **Prevention:** QA Step 1.5
  should distinguish "reachable" from "healthy" -- a 5xx response
  means the existing server is broken, not usable.
- **`grep` returned no output** on the plan file until
  `--binary-files=text` was added; `file` reported the plan as
  `data` despite ASCII content. **Prevention:** when grep is empty on
  a file you know contains the pattern, retry with
  `--binary-files=text` before re-reading.
- **esbuild rejected literal U+2028/U+2029** in a regex character
  class. **Prevention:** always use `  ` escape sequences
  in source for paragraph/line-separator sentinels -- never the
  literal codepoints.
- **`vi.fn()` empty-tuple inference** broke
  `dispatchSpy.mock.calls[0][0]` access. **Prevention:** type
  `vi.fn()` factories explicitly when downstream code reads the
  captured args (`vi.fn(async (_args: ArgType) => {...})`).
- **Wrong filter scope (F13).** Added `.is("archived_at", null)` to
  the chat-case lookup interpreting an agent's "archived" comment as
  archived-DOCUMENTS when the agent meant archived-CONVERSATIONS.
  Recovery: reverted. **Prevention:** when an agent flags "archived"
  semantics, distinguish entity scope before adding a SQL filter.
- **code-simplicity-reviewer DISSENTED on F2 + F14** scope-out filings
  -- both flipped to fix-inline per the review-findings rule.
  Working as designed; the second-reviewer gate caught speculative
  scope-out claims.

## Related

- PR #2901 (Stage 2.12 cutover -- introduced regressions)
- PR #2923 (#2954) -- partial fix added `artifactPath` to system
  prompt template but never wired dispatcher
- ADR-022 (SDK-as-router) -- architectural framing for cc-soleur-go
- `agent-runner.ts:590-635` -- legacy injection contract this PR
  brings to parity
