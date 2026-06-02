---
title: "fix: kb-chat fresh-conversation history-fetch 404 (deferred-row race)"
date: 2026-06-02
type: fix
feature: feat-one-shot-kb-chat-history-404-fresh-conversation
status: planned
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
tags: [kb-chat, ws-client, api-messages, deferred-creation, silent-fallback, observability]
---

# 🐛 fix: kb-chat fresh-conversation history-fetch 404 (deferred-row race)

## Enhancement Summary

**Deepened on:** 2026-06-02
**Sections enhanced:** Overview, FR3/FR4, Risks (precedent-diff), Research Insights
**Research passes:** verify-the-negative (severity-helper contract), precedent-diff (warn-level
fallback), post-edit self-audit (no dropped symbols), halt gates 4.5–4.8 (all pass)

### Key Improvements

1. **Verified `warnSilentFallback` is a drop-in for `reportSilentFallback`** — identical
   `(err, options)` signature in BOTH `server/observability.ts:241` and
   `lib/client-observability.ts:111`. FR3/FR4 are 1-line severity swaps + an import. The server
   variant additionally surfaces a `pg_code` Sentry tag, but a row-absent 404 carries no Postgres
   error, so it stays a clean warning-level `captureMessage`.
2. **Confirmed strong in-file precedent for the warn downgrade** — `api-messages.ts:155-166`
   ALREADY emits `level: "warning"` for the sibling "fresh-but-not-yet-written conversation" noise
   class (the empty-200 breadcrumb, comment: "Some baseline noise from fresh-but-not-yet-written
   conversations is accepted"). FR3 makes the 404 branch consistent with the file's own treatment
   of the same deferred-conversation noise — NOT a novel pattern.
3. **Confirmed the discriminator is already on the wire** — `session_started` (fresh/deferred,
   `resumedFrom === null`) vs `session_resumed` (real row, sets `resumedFrom`). TR2(a) makes the
   gate explicit (`sessionKind`) without any wire change.

### New Considerations Discovered

- The `conversationCreatedAt` consumer (#3603 cohort marker) stays `null` for fresh conversations
  once FR1 skips the fetch — already handled (`null` → "do not render"), captured as a Sharp Edge.
- No infrastructure, migration, schema, or dependency change — pure code + observability tuning.

## Overview

Opening a brand-new KB-chat conversation fires a history fetch against a conversation
row that **does not exist yet**, producing a `404 not-owned-or-missing` on the server
and an `error`-level Sentry event on both server and client every single time a fresh
sidebar conversation is opened. The user-visible symptom is the dashboard error
boundary ("Something went wrong / An unexpected error occurred.") in the path where the
404's downstream `null`-handling combines with the empty-state race.

**Root cause — deferred conversation creation vs. unconditional history-fetch.** The
WS server uses *deferred creation* (learning `2026-04-11-deferred-ws-conversation-creation-and-pending-state.md`):
`start_session` mints a UUID and emits `session_started` **without inserting a DB row**;
the row materializes only on the first real `chat` message (`ws-handler.ts:816`, reached
via the deferred-creation path at `ws-handler.ts:~1767`). A genuine resume instead emits
`session_resumed` (row exists, `messageCount` known — `ws-handler.ts:1420-1439`).

The client cannot tell the two apart at the fetch site:

- `ws-client.ts:791-807` (`session_started`) sets `realConversationId = pendingUUID` and
  leaves `resumedFrom = null`.
- `ws-client.ts:809-822` (`session_resumed`) sets `realConversationId` **and** `resumedFrom`.
- The resume-history effect at `ws-client.ts:1209-1217` fires `runHistoryFetch(realConversationId)`
  for **any** `realConversationId` while `conversationId === "new"` — it does **not** gate on
  `resumedFrom`. So a fresh deferred conversation triggers
  `GET /api/conversations/{pendingUUID}/messages`.
- `api-messages.ts:103-120` runs `.single()` on `conversations WHERE id = {pendingUUID}` → no
  row → `convErr || !conv` → `404` + `reportSilentFallback(... op:"history-fetch-404-not-owned-or-missing")`
  at **`level: "error"`** (`server/observability.ts:224`).
- Client `fetchConversationHistory` (`ws-client.ts:1007-1014`) sees `!res.ok`, emits
  `op:"history-fetch-failed"` also at **`level: "error"`** (`lib/client-observability.ts:104`),
  returns `null`; `runHistoryFetch` then `return`s silently.

This is a **guaranteed** race on the most common new-conversation path (KB sidebar:
`kb-chat-content.tsx` always mounts `<ChatSurface conversationId="new" resumeByContextPath=…>`),
not an intermittent edge case. Every fresh KB-chat doc-open that does not match an existing
thread emits two error-level Sentry events for a benign, expected state.

The fix is **client-side discrimination**: a deferred (`session_started`) conversation has no
row to fetch — skip the history fetch entirely. A genuine resume (`session_resumed`) keeps
fetching. Defense-in-depth on the server downgrades the fresh-row-absent 404 from `error` to
`warning` so any residual race (timing, multi-tab) stays observable without paging.

### Why this is the right altitude

- The brainstorm-era decision to **defer** row creation (no junk inbox rows) is correct and
  stays. We do not move row creation earlier — that would resurrect the empty-row problem
  the deferred model was built to solve.
- The client already holds the discriminator (`resumedFrom` is set only by `session_resumed`).
  No new wire field is strictly required, though TR2 adds an explicit, future-proof signal.

## Research Reconciliation — Spec vs. Codebase

| Premise (from alert / framing) | Codebase reality | Plan response |
| --- | --- | --- |
| "GET /api/conversations/{id} route returns 404" | There is **no** App-Router `route.ts` for `[id]/messages`; the handler is the Node custom server `server/api-messages.ts` wired via `server/index.ts` regex (`ws-client.ts:995-999` documents this — do NOT add a duplicate `route.ts`). | Edit `server/api-messages.ts`, not a Next route. |
| "history fetch 404s for a newly created conversation" | The conversation is **not** created at `session_started`; deferred to first chat message. The 404 is row-absent, not ownership. | Confirmed: deferred-creation race. Fix at the client fetch trigger + server log level. |
| "client surfaces a generic error" | The 404 path itself returns `null` silently (no throw). The "An unexpected error occurred." string is the dashboard error boundary (`error-boundary-view.tsx:44`). The generic surface arises from the empty-state/`historyLoading` interplay, not a direct 404 throw. | Eliminate the 404 at its source (skip fetch for deferred); audit the empty-state copy so a genuinely-empty conversation never reaches the error boundary. |
| Release `web-platform@0.101.100+77f0f5ff` | `77f0f5ff` is `fix(infra): deploy-pipeline-fix` (#4805), on `main`. Valid recent prod build. | Premise holds. |

**Premise Validation:** `77f0f5ff` exists on `main`. The cited route is served by the custom
Node server (`api-messages.ts`), confirmed present. `session_started` (zod schema
`ws-zod-schemas.ts:267-286`) carries only `conversationId` + optional `capabilities` — **no
deferred/persisted flag** today, confirming the client cannot currently distinguish a deferred
row from a persisted one at the fetch site. No cited GitHub issue to validate (Sentry-sourced).

## User-Brand Impact

**If this lands broken, the user experiences:** opening any new KB-chat conversation throws an
error boundary ("Something went wrong / An unexpected error occurred.") or a flash of a broken
empty state, on the single most common entry into the product's core chat surface.

**If this leaks, the user's data is exposed via:** N/A — the 404 path is read-only and
ownership-gated; there is no data exposure. The exposure here is **operator-blindness**: real
errors drown in expected-404 noise (every fresh conversation emits 2 error-level events), so a
genuine ownership/RLS regression on this endpoint would be invisible in the alert stream.

**Brand-survival threshold:** single-user incident — the new-conversation path is the front door
to the product; a single broken open is a credibility hit, and the noise floor masks the next
real regression on the same endpoint.

CPO sign-off required at plan time before `/work` begins. `user-impact-reviewer` will be invoked
at review-time (handled by `review/SKILL.md` conditional-agent block).

## Reproduction

1. Sign in, open a KB document that has **no** prior chat thread.
2. The sidebar mounts `<ChatSurface conversationId="new" resumeByContextPath=<docPath>>`.
3. Server defers creation, emits `session_started` with a pending UUID.
4. Client sets `realConversationId = pendingUUID`; resume-history effect (`ws-client.ts:1209`)
   fires `GET /api/conversations/{pendingUUID}/messages`.
5. Observe: server logs `history-fetch-404-not-owned-or-missing` (error), client logs
   `history-fetch-failed` (error). Both for a conversation the user just legitimately started.

## Functional Requirements

- **FR1 — Skip history fetch for deferred (fresh) conversations.** The resume-history effect
  (`ws-client.ts:1209-1217`) MUST NOT fire `runHistoryFetch` when the session was started fresh
  (`session_started`, i.e. `resumedFrom === null`) rather than resumed (`session_resumed`).
  Implementation pointer: gate the effect on a discriminator that is set only by
  `session_resumed`. Today that is `resumedFrom !== null`; TR2 adds an explicit `sessionKind`
  state to avoid coupling the fetch decision to the resume-banner state.
  - Site: `apps/web-platform/lib/ws-client.ts:1209-1217` (resume-history effect) +
    `ws-client.ts:791-822` (`session_started` / `session_resumed` handlers).

- **FR2 — A genuine empty resume must not 404.** `session_resumed` with `messageCount === 0`
  (a resumed row that has the row but zero messages) MUST continue to fetch (the row exists; the
  200-empty branch at `api-messages.ts:161-169` already handles zero messages). FR1's gate keys
  on `session_started` vs `session_resumed`, **not** on message count — so this case is preserved.
  Enumerate both members of the discriminator in the implementation: `session_started` → skip;
  `session_resumed` → fetch.
  - Site: `apps/web-platform/lib/ws-client.ts:1209-1217`.

- **FR3 — Server downgrades fresh-row-absent 404 to warning (defense-in-depth).** The
  `history-fetch-404-not-owned-or-missing` site (`api-messages.ts:111-120`) MUST emit at
  `level: "warning"` via `warnSilentFallback` instead of `reportSilentFallback` (error). The
  404 HTTP status is unchanged (the contract that the row is absent stays); only the Sentry
  severity drops, because a row-absent 404 is an expected transient on the deferred path and a
  retried/multi-tab fetch can legitimately hit it. The op string is unchanged so existing alert
  rules keep matching.
  - Site: `apps/web-platform/server/api-messages.ts:112` — swap
    `reportSilentFallback` → `warnSilentFallback` (import from `@/server/observability`).

- **FR4 — Client downgrades the fresh-conversation `history-fetch-failed` 404 to warning.** When
  `fetchConversationHistory` receives a `404` specifically, it MUST emit at `level: "warning"`
  (`warnSilentFallback`) rather than error. Non-404 non-OK statuses (401/500) stay at `error`.
  This keeps the client's noise floor aligned with the server's. With FR1 in place the 404 is
  largely eliminated at the source, but FR4 covers the residual full-route deep-link case (see
  FR5).
  - Site: `apps/web-platform/lib/ws-client.ts:1007-1014` — branch on `res.status === 404`.

- **FR5 — Full-route deep link to a never-materialized conversation degrades gracefully.**
  Navigating directly to `/dashboard/chat/{uuid}` where `{uuid}` is a valid-but-deferred /
  never-persisted id (e.g. a stale bookmark, or a pending id that was never written) MUST render
  the empty composer ("Send a message to get started"), **not** the error boundary. The
  mount-time effect (`ws-client.ts:1198-1203`) fires for non-"new" ids; on 404 it already returns
  `null` and surfaces nothing — verify the ChatSurface empty-state path renders cleanly when
  `messages.length === 0 && !historyLoading && !lastError`. No code change expected if the
  empty-state already handles this; AC9 is the regression gate.
  - Sites: `apps/web-platform/lib/ws-client.ts:1198-1203`;
    `apps/web-platform/components/chat/chat-surface.tsx` (empty-state render gate).

## Technical Requirements

- **TR1 — No change to the deferred-creation model.** Row creation stays deferred to first chat
  (`ws-handler.ts:816`). Do NOT insert at `session_started`. (Re-validates the
  `2026-04-11-deferred-ws-conversation-creation-and-pending-state.md` decision.)

- **TR2 — Explicit client `sessionKind` discriminator (preferred over `resumedFrom` coupling).**
  Add a derived signal so the fetch decision does not silently break if a future change clears
  `resumedFrom`. Two acceptable shapes — choose the simpler at /work time:
  - (a) Client-only: track `sessionKind: "fresh" | "resumed" | null` in `useWebSocket`, set
    `"fresh"` in the `session_started` handler and `"resumed"` in `session_resumed`; gate FR1 on
    `sessionKind === "resumed"`. No wire change.
  - (b) Wire-level: add optional `deferred?: boolean` to `session_started` zod schema
    (`ws-zod-schemas.ts:267-286`) + `lib/types.ts:288` and emit `deferred: true` from
    `ws-handler.ts:1560-1564`. More explicit but cross-module; widening a discriminated union
    requires the `cq-union-widening-grep-three-patterns` sweep (run `tsc --noEmit` and fix every
    `: never` rail).
  - **Default to (a)** — it is client-local, needs no rolling-deploy compatibility window, and
    the client already receives a distinct message type. (b) is a follow-up only if an external
    agent client needs the signal.

- **TR3 — Severity helpers already exist.** `warnSilentFallback` exists in both
  `server/observability.ts:241` and `lib/client-observability.ts:111` with the same contract as
  `reportSilentFallback` (`(err, options) => void`). No new helper. Verified in deepen-pass:
  signatures match; the server variant adds a `pg_code` tag (no-op for non-Postgres errors — a
  row-absent 404 has none).

### Precedent-Diff (Phase 4.4)

The warn-level downgrade is **not novel** — it matches an established pattern and the file's own
existing behavior:

- **In-file precedent:** `api-messages.ts:155-166` already emits the sibling fresh-conversation
  noise (the empty-200 breadcrumb) at `level: "warning"`, with the comment "Some baseline noise
  from fresh-but-not-yet-written conversations is accepted." FR3 makes the 404 branch consistent
  with this — same deferred-conversation noise class, same severity.
- **Codebase precedent:** `warnSilentFallback` is the canonical "expected-degraded-but-observe"
  emitter at `inngest/functions/workspace-reconcile-on-push.ts:132` (drained event),
  `templates/template-registry.ts:84` (unknown id), `github/probe-octokit.ts:137` (diagnostic
  capture). The 404-on-deferred-row is the same class: expected, recoverable, worth one warning.

No novel observability primitive introduced.

- **TR4 — Tests run via vitest, not bun.** `apps/web-platform` uses vitest
  (`apps/web-platform/vitest.config.ts`); `bunfig.toml` ignores test discovery. Run
  `cd apps/web-platform && ./node_modules/.bin/vitest run <path>`. Test files must match the
  vitest `include:` globs (`test/**/*.test.ts`, `test/**/*.test.tsx`) — co-located component
  tests are NOT collected. Extend the existing `test/kb-chat-resume-hydration.test.tsx` and
  `test/api-messages-handler.test.ts` rather than adding new files where possible.

## Files to Edit

- `apps/web-platform/lib/ws-client.ts` — FR1 (gate resume-history effect), FR4 (404→warning),
  TR2(a) (`sessionKind` state set in `session_started`/`session_resumed` handlers).
- `apps/web-platform/server/api-messages.ts` — FR3 (404 site → `warnSilentFallback`); add import.
- `apps/web-platform/test/kb-chat-resume-hydration.test.tsx` — FR1/FR2/FR4 client tests.
- `apps/web-platform/test/api-messages-handler.test.ts` — FR3 server severity test.
- `apps/web-platform/components/chat/chat-surface.tsx` — only if FR5 verification shows the
  empty-state gate needs a tweak; otherwise no edit (AC9 verifies).

(TR2(b) additionally would touch `lib/ws-zod-schemas.ts`, `lib/types.ts`, `server/ws-handler.ts`
— deferred unless (b) is chosen.)

## Files to Create

- None expected. New tests extend existing suites.

## Open Code-Review Overlap

3 open code-review issues touch these files:

- **#3280** (`review: refactor useWebSocket history-fetch into reducer-driven state machine`,
  touches `lib/ws-client.ts`) — **Acknowledge.** This is a structural refactor of the history-
  fetch machinery; FR1/FR4 are a targeted behavioral fix to the existing effect. Folding the
  refactor in would balloon scope on a single-user-incident hotfix. The fix is written to be
  compatible with a future reducer migration (the gate is a single condition). Issue stays open;
  add a note that the `sessionKind` gate should be carried into the reducer when #3280 lands.
- **#3374** (`emit slot_reclaimed WS frame`, touches `lib/ws-client.ts`) — **Acknowledge.**
  Unrelated concern (concurrency-cap ledger recovery); no interaction with the history-fetch path.
- **#3289** (`add conversation_messages MCP tool`, touches `server/api-messages.ts`) —
  **Acknowledge.** Agent-parity read tool; orthogonal to the 404 severity change. The
  `warnSilentFallback` swap is a 1-line severity change that does not affect the future MCP tool.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1 (FR1):** With the client mocked to receive `session_started` (fresh) while
  `conversationId="new"`, `fetch` is **not** called for `/api/conversations/{id}/messages`.
  Verify in `test/kb-chat-resume-hydration.test.tsx`: assert `fetchSpy` not called after a
  `session_started` frame.
- **AC2 (FR2):** With the client mocked to receive `session_resumed` (`messageCount: 0`) while
  `conversationId="new"`, `fetch` **is** called once for the resolved id, and a 200-empty
  response hydrates zero messages without error. Assert `fetchSpy` called exactly once.
- **AC3 (FR4):** When `fetchConversationHistory` receives `res.status === 404`,
  `warnSilentFallback` is invoked (not `reportSilentFallback`); for `res.status === 500`,
  `reportSilentFallback` is invoked. Assert via the mocked observability spies in
  `test/kb-chat-resume-hydration.test.tsx`.
- **AC4 (FR3):** In `test/api-messages-handler.test.ts`, a GET for a non-existent conversation id
  returns HTTP 404 **and** the mocked `warnSilentFallback` (warning) is called with
  `op: "history-fetch-404-not-owned-or-missing"`; `reportSilentFallback` (error) is **not** called
  for that op. Response body shape (`{ error: "Conversation not found" }`) unchanged.
- **AC5 (TR1):** `git grep -n 'from("conversations").insert' apps/web-platform/server/ws-handler.ts`
  still returns exactly the single first-chat-message insert site (no new insert at
  `session_started`). Deferred model intact.
- **AC6 (TR2a):** `grep -n 'sessionKind' apps/web-platform/lib/ws-client.ts` shows the discriminator
  set in BOTH the `session_started` and `session_resumed` handler arms, and read by the
  resume-history effect's gate. (Skip if (b) chosen — then assert the zod + union sweep instead.)
- **AC7 (regression — type safety):** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
  passes (catches any `: never` exhaustiveness rail if TR2(b) widens the union).
- **AC8 (full suite):** `cd apps/web-platform && ./node_modules/.bin/vitest run test/kb-chat-resume-hydration.test.tsx test/api-messages-handler.test.ts test/ws-client-resume-history.test.tsx`
  passes.
- **AC9 (FR5):** A test (extend `test/ws-client-resume-history.test.tsx` or chat-surface render
  test) confirms that with `conversationId="<uuid>"` (non-"new") and a mocked 404 response, the
  hook ends in `historyLoading === false`, `messages.length === 0`, `lastError === null` — i.e.
  the empty-state, not the error boundary, is the resting state.

### Post-merge (operator)

- **AC10:** After deploy, confirm in Sentry that the `history-fetch-404-not-owned-or-missing`
  event volume drops to ~0 (it should no longer fire on fresh KB-chat opens) and that any residual
  occurrences are `warning`-level, not `error`. Automation: query Sentry issues API for the op
  over a 24h window post-deploy; deterministic verdict = error-level count for that op == 0.
  (Per `hr-no-dashboard-eyeball-pull-data-yourself` — pull via API, do not eyeball the dashboard.)

## Hypotheses

(Not a network-outage class — no SSH/connection/timeout keywords. Standard root-cause hypotheses:)

1. **PRIMARY (confirmed by code read):** deferred-creation row absence + unconditional
   resume-history fetch on `session_started`'s pending UUID. Confirmed via `ws-handler.ts:1540-1566`
   (defer + emit), `ws-handler.ts:816` (lazy insert), `ws-client.ts:1209-1217` (ungated fetch),
   `api-messages.ts:103-120` (`.single()` 404).
2. SECONDARY (ruled out): genuine ownership/RLS failure — ruled out because the same id later
   resolves fine once the first chat message materializes the row; the 404 is row-absence, not a
   permission denial (RLS would still find no row for a not-yet-inserted id either way).
3. TERTIARY (FR5 covers): stale full-route deep link to a never-materialized id — real but rare;
   handled by the empty-state degradation path, not a code defect in the fix's primary scope.

## Observability

```yaml
liveness_signal:
  what: "history-fetch-404-not-owned-or-missing event-rate in Sentry (kb-chat feature)"
  cadence: "per fresh-conversation open (pre-fix: ~1 per open; post-fix target: ~0)"
  alert_target: "existing kb-chat error-rate alert rule (op-scoped)"
  configured_in: "Sentry alert rules (terraform apps/web-platform/infra sentry_* if codified) — op string unchanged so rule keeps matching"
error_reporting:
  destination: "Sentry via warnSilentFallback (warning) for fresh-row-absent 404; reportSilentFallback (error) retained for 401/500"
  fail_loud: "yes — genuine 401 invalid-token / 500 auth-probe / messages-load failures stay error-level and page"
failure_modes:
  - mode: "fresh conversation opens but FR1 gate regresses (fetch fires on session_started)"
    detection: "history-fetch-404 error-rate climbs back; AC1 vitest gate fails in CI"
    alert_route: "CI red on AC1 + Sentry error-rate alert if it reaches prod"
  - mode: "genuine empty resume (session_resumed, messageCount 0) wrongly skips fetch"
    detection: "AC2 vitest gate fails; resumed thread renders blank where messages exist"
    alert_route: "CI red on AC2"
  - mode: "real ownership/RLS regression masked by warning downgrade"
    detection: "FR3 downgrades ONLY the not-owned-or-missing op; 401 invalid-token and 500 auth-probe stay error — those page"
    alert_route: "Sentry error-level alert on 401/500 ops (unchanged)"
logs:
  where: "Sentry (client + server breadcrumbs/events); pino server logs via observability helpers"
  retention: "Sentry default project retention"
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/kb-chat-resume-hydration.test.tsx test/api-messages-handler.test.ts"
  expected_output: "all tests pass; AC1 (no fetch on session_started), AC3/AC4 (404→warning) green"
```

## Domain Review

**Domains relevant:** Engineering (frontend + server). Product/UX assessed below.

### Engineering

**Status:** reviewed
**Assessment:** Pure behavioral fix on an existing read path + observability severity tuning. No
schema, no migration, no new infra, no new dependency. The deferred-creation invariant is
preserved (TR1). Cross-module blast radius is minimal for TR2(a) (client-local state); TR2(b)
would widen a discriminated union and require the union-widening exhaustiveness sweep — deferred
unless an external agent client needs the wire signal.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A

#### Findings

No new user-facing surface, page, or component. The change removes an error state from an
existing flow (fresh KB-chat open) and ensures the empty composer renders instead of an error
boundary. The only copy adjacency is the existing empty-state placeholder ("Send a message to get
started") — verified present, not modified. Modifies behavior of an existing surface only →
advisory; auto-accepted in pipeline.

## Infrastructure (IaC)

No new infrastructure. No server, service, cron, secret, vendor, DNS, or firewall change. The
Sentry alert rule is unchanged (op string preserved). Skip — pure code change against
already-provisioned surfaces (`apps/web-platform/lib`, `apps/web-platform/server`).

## Test Scenarios

| # | Scenario | Expected |
| --- | --- | --- |
| 1 | Fresh KB doc open (no prior thread) → `session_started` | No `/messages` fetch; no 404; empty composer renders |
| 2 | Resume existing thread (N>0 messages) → `session_resumed` | Fetch fires; N messages hydrate |
| 3 | Resume row with 0 messages → `session_resumed` msgCount 0 | Fetch fires; 200-empty; no error |
| 4 | Full-route deep link to never-materialized uuid | 404 → warning; empty composer, not error boundary |
| 5 | 401 invalid token on `/messages` | error-level event retained (paging) |
| 6 | 500 auth-probe / messages-load failure | error-level event retained (paging) |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This section is filled.)
- **Do NOT add an App-Router `app/api/conversations/[id]/messages/route.ts`.** The endpoint is
  served by the custom Node server (`server/api-messages.ts` via `server/index.ts` regex). A
  duplicate route would shadow it with undefined precedence (documented at `ws-client.ts:995-999`).
- **FR3/FR4 must keep the HTTP 404 status and the op string unchanged** — only the Sentry severity
  drops. Changing the status or op would break the existing alert rule and the client's
  `!res.ok` branch.
- **Do not gate FR1 on message count.** A `session_resumed` row with 0 messages is a real row
  (200-empty path) and must still fetch. Gate strictly on `session_started` vs `session_resumed`
  (TR2a `sessionKind`), per FR2.
- If TR2(b) (wire `deferred?` flag) is chosen, the `session_started` union widening triggers
  `cq-union-widening-grep-three-patterns`: run `tsc --noEmit` and resolve every `: never` rail in
  `ws-client.ts` and the test-d gates before declaring done.
- The cohort-missing-reply marker (`#3603`) consumes `conversationCreatedAt` from the history
  fetch. FR1 skips the fetch for fresh conversations, so `conversationCreatedAt` stays `null` for
  a brand-new conversation — the marker already treats `null` as "do not render" (`ws-client.ts:121-126`),
  so this is correct, but verify the marker does not regress (no render for fresh conversations).

## References

- Learning: `knowledge-base/project/learnings/2026-04-11-deferred-ws-conversation-creation-and-pending-state.md` (deferred-creation rationale)
- Learning: `knowledge-base/project/learnings/ui-bugs/2026-05-05-kb-chat-continuing-banner-h1-h5-residual-races.md` (#3267 history-fetch op taxonomy)
- Learning: `knowledge-base/project/learnings/ui-bugs/2026-05-05-kb-chat-resume-hydration-race-strict-mode-and-prefetch-clobber.md` (historyLoading/prefetch race)
- Server handler: `apps/web-platform/server/api-messages.ts`
- WS hook: `apps/web-platform/lib/ws-client.ts`
- WS server: `apps/web-platform/server/ws-handler.ts`
- KB-chat sidebar: `apps/web-platform/components/chat/kb-chat-content.tsx`
