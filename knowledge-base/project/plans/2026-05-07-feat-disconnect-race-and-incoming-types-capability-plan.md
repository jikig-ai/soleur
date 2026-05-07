---
title: "Bundle: disconnect-after-result race + session_started.incomingTypes capability"
type: feat
date: 2026-05-07
issues: [3463, 3464]
related_prs: [3447, 3469]
requires_cpo_signoff: false
deepened_on: 2026-05-07
---

# Bundle: fix disconnect-after-result race (#3463) + extend session_started capabilities with incomingTypes (#3464)

## Enhancement Summary

**Deepened on:** 2026-05-07

**Sections enhanced:** Phase 0 verification grep run live; Proposed Solution §#3463 revised with helper-function discovery; Files to Edit refined; new "Deepen Insights" section appended.

### Key Improvements

1. **Discovered design flaw in original plan.** The original plan said
   "extend `UpdateConversationOptions` with `onlyIfStatusIn?` and pass
   it through `updateConversationStatus`" — but `updateConversationStatus`
   uses `expectMatch: true` which **throws + Sentry-mirrors** on 0-rows.
   The race-window case (row already at `waiting_for_user` when the
   abort branch's UPDATE runs) would fire a Sentry event for what is
   the *intended success path*. Plan revised to introduce a separate
   helper `updateConversationStatusIfActive` that uses `expectMatch: false`
   so the no-op is silent.
2. **Verified all line numbers live** — 1613, 1640, 1646, 1659, 1766
   (variable-named, hence missed by original literal grep), 1852, 2027
   confirmed against the worktree HEAD `b6f04394`.
3. **Enumerated all 9 test fixtures pinning `session_started`** — the
   plan now lists them explicitly (Files to Edit §"Test fixtures") so
   Phase 4 doesn't drift on which files need touch.
4. **Confirmed Supabase JS supports `.in()` on UPDATE chains** via
   Context7 — pattern is standard PostgREST and does not need
   `maxAffected` (PostgREST 13 feature, separate concern).
5. **Cross-referenced three adjacent learnings** — the typed-optional-field
   wire-drop (2026-05-07), defense-in-depth recovery mirroring SQL
   predicate (2026-05-06), and trace-callgraph-from-entrypoint
   (2026-05-05) — all apply directly.
6. **Identified one subtle behavior change** at line 1766: the abort
   branch's `updateConversationStatus` write currently fires for both
   user-Stop (writes `waiting_for_user`) and disconnect (writes
   `failed`). With `onlyIfStatusIn: ["active"]`, the user-Stop late-click
   case (user clicks Stop AFTER result branch already wrote
   `waiting_for_user`) becomes a no-op. Same end state — semantically
   equivalent. Documented in §"Deepen Insights".

### New Considerations Discovered

- The plan's `## Files to Edit` originally listed "Test fixtures pinning `session_started` shape — enumerate via Phase 0 grep". Phase 0 ran live: 9 files identified. Listed explicitly below.
- The schema currently declares `capabilities.promptKinds` but no emit site populates it — the new `incomingTypes` change is the lever to fix BOTH wire-drops in one PR.
- The four guarded sites are NOT semantically identical: line 1766 is the only one where the *value being written* depends on a runtime branch (`isUserRequested ? "waiting_for_user" : "failed"`). The other three always write a fixed value. The conditional guard is correct at all four.

## Overview

Two scope-outs from `feat-abort-conversation-web` (PRs #3447 + #3469) merged
the same day. Both touch `apps/web-platform/server/agent-runner.ts` and
`apps/web-platform/lib/{types.ts,ws-zod-schemas.ts}` — bundling them avoids
two near-simultaneous edits to the same WSMessage union and the same
agent-runner result/abort branches.

**#3463 (bug):** `agent-runner.ts:startAgentSession`'s result branch writes
`waiting_for_user`. If the WS connection dies in the millisecond window
between that write and the for-await iterator's natural termination, the
SDK iterator throws an `AbortError` with `signal.reason = "disconnected"`,
and the outer-catch's abort branch (lines ~1763) writes `failed` —
overwriting the freshly-written `waiting_for_user`. The user sees a
clean turn marked "failed" purely because they closed their tab early.

**#3464 (enhancement):** `session_started.capabilities` (added in #2885 /
Stage 3) carries `promptKinds: readonly string[]` for server→client prompt
discovery. The parallel for client→server message types does not exist —
external agents that want to feature-detect `abort_turn` must source-dive
the `WSMessage` union. Add an optional `incomingTypes?: readonly string[]`
to the capabilities manifest.

The two changes are independent in code (different files / sites) but
share the same review surface (WSMessage union, session_started emit
sites, fixture pinning), and #3464's per-variant explicit-listing
discipline reduces the risk that a sibling-class scope-out (#3242,
"tool_use lacks raw name field for agent consumers") backslides during
the change.

## Problem Statement

### #3463 — disconnect-after-result race

In `apps/web-platform/server/agent-runner.ts startAgentSession`:

1. The `result` branch writes `updateConversationStatus(..., "waiting_for_user")` at line **1613** (post-PR #3447 numbering verified by Read).
2. If the WS connection then dies before the for-await loop terminates cleanly, the SDK iterator throws an `AbortError`.
3. `controller.signal.aborted` becomes `true` and `controller.signal.reason` carries the `SessionAbortError("disconnected")` set by `ws.on("close")` at `ws-handler.ts:1876-1906` (grace-period `abortSession(uid, convId)` with no kind = registry-default `"disconnected"`).
4. The outer-catch abort branch at line **1763** picks `nextConversationStatus = isUserRequested ? "waiting_for_user" : "failed"`. Because `isUserRequested = false`, it writes `failed` — stomping the row's freshly-written `waiting_for_user`.

**User-visible symptom:** the conversation shows up as `failed` in the
sidebar history despite the assistant turn completing cleanly. The
forcing function for re-evaluation (per #3463 body): a user reports
"I closed my tab right after the answer finished and now the
conversation is marked failed."

**Provenance:** Pre-existing on main. PR #3447 inherited the same shape
verbatim from the pre-existing unconditional `failed`-write; the
result-branch-then-disconnect interleaving is unchanged in behavior by
that PR. The race exists on main and would surface identically without
PR #3447's changes.

### #3464 — agent feature-detection of abort_turn

`abort_turn` (added in PR #3447) is reachable by any holder of a Supabase
access token via the existing WS auth path (`ws-handler.ts:1747-1773`).
Action parity is satisfied: an agent acting on its own user's behalf can
connect and emit Stop exactly like the browser. **However**, nothing in
the `session_started.capabilities` manifest declares `abort_turn` as a
discoverable client→server capability, so external agents must source-dive
the `WSMessage` union (`apps/web-platform/lib/types.ts`) to find it.

Today, `session_started.capabilities` (zod schema at
`apps/web-platform/lib/ws-zod-schemas.ts:267-277`, type at
`apps/web-platform/lib/types.ts:242`) carries `promptKinds: readonly string[]`
for server→client prompt-kind discovery (added in #2885). The parallel
field for client→server message types does not exist.

## Proposed Solution

### #3463 — Conditional UPDATE with status guard

The issue body proposed three fix paths. Decision:

**Chosen:** Path 1 (Conditional UPDATE: `where status IN ('active')`) at
the abort-branch's `updateConversationStatus` call.

Rationale vs. the two alternatives:

- **Path 2 (in-flight `resultBranchCompleted` flag):** carries a boolean
  in process memory across two coroutines. The abort branch already
  reads `messagePersisted` for the partial-text guard — adding a second
  process-local flag widens the cross-coroutine state surface and is
  harder to reason about across the result-branch finalization wrap
  (the wrap that fires when the result branch *itself* throws between
  `waiting_for_user` write and the next step). A status-column guard
  has the additional virtue of also covering the result-branch's own
  fallback at line 1640 (`updateConversationStatus(..., "waiting_for_user")`
  inside `catch (resultBranchErr)`), where the same race window
  re-opens at smaller probability if a tab-close lands between the
  fallback write and the re-throw.
- **Path 3 (status state machine):** the largest scope. Useful long-term
  but unbounded for this PR. Tracked as a re-evaluation criterion in
  #3463 body ("conversation status state machine is consolidated").

**Implementation (revised after deepen-plan discovery — see Enhancement Summary §1):**

1. Extend `UpdateConversationOptions` in
   `apps/web-platform/server/conversation-writer.ts` with
   `onlyIfStatusIn?: ReadonlyArray<Conversation["status"]>`. The wrapper
   appends `.in("status", onlyIfStatusIn)` to the base query when provided.
2. Introduce a new helper
   `updateConversationStatusIfActive(userId, conversationId, status)`
   in `agent-runner.ts` (sibling to the existing
   `updateConversationStatus`). The new helper:
   - Uses `expectMatch: false` (a no-op is the success case, not an
     error to mirror).
   - Passes `onlyIfStatusIn: ["active"]`.
   - Returns `Promise<void>` — never throws on 0-rows-affected.
3. The abort branch and the three result-branch fallback sites call
   `updateConversationStatusIfActive` instead of
   `updateConversationStatus` for the `failed`-cascade. Sites enumerated
   in §Acceptance Criteria.

**Why a new helper, not a flag on the existing one:** the existing
`updateConversationStatus` has a load-bearing
`expectMatch: true` + `if (!result.ok) throw` contract (per its inline
comment: "a 0-rows write would silently desync UI state from DB"). That
contract is correct for the result branch's primary `waiting_for_user`
write at line 1613 — if THAT write returns 0-rows, something is genuinely
broken (the user's row is gone, the UI badge will be stale, on-call
needs to know). Folding `onlyIfStatusIn` into the existing helper would
either (a) throw + Sentry-mirror on every clean disconnect-after-result
(noise) or (b) require a `silentZero` flag that confuses the contract.
A separate helper makes the silent-no-op contract explicit at the call
site.

**Subtlety #1 (silent no-op contract):** the new helper does NOT mirror
to Sentry on 0-rows-affected. Per `cq-silent-fallback-must-mirror-to-sentry`
exempt clauses: "Exempt: expected states (CSRF reject, rate-limit hit,
first-time 404, intentional pass-through)" — the no-op IS the intended
pass-through.

**Subtlety #2 (line 1766 user-Stop late-click semantics):** at line 1766
the abort branch writes either `waiting_for_user` (user-requested) OR
`failed` (disconnect). With `onlyIfStatusIn: ["active"]`, both branches
no-op when the row is no longer `active`:
- Disconnect path (`failed`-write): no-op when result branch already
  wrote `waiting_for_user` — the bug fix we want.
- User-Stop late-click path (`waiting_for_user`-write): no-op when result
  branch already wrote `waiting_for_user` — same end state, semantically
  equivalent. Sending the `session_ended:user_aborted` ack still happens
  (the ack is unconditional within the `if (isUserRequested)` block),
  so the client still transitions out of `stopping` state.

**Symmetric application — must apply at all three writers in
`agent-runner.ts`:**

- Line **1646**: result-branch fallback `failed`-cascade (after a failed
  `waiting_for_user` flip). The `onlyIfStatusIn: ["active"]` guard is
  correct here too — if a concurrent abort already wrote `failed` the
  re-write is a no-op.
- Line **1659**: result-branch fallback when `assistantPersisted = false`
  (saveMessage threw). Same guard.
- Line **1766** (the issue's primary site): abort branch's
  non-superseded path. Same guard.
- Line **1852** (`else` branch — non-abort thrown errors path). Apply
  the same guard for consistency: a concurrent terminal-write should
  win over a late `failed` from this path too.

**Skipped — not narrow enough to gain from the guard:**

- Line **2027** (`updateConversationStatus(..., "failed")` from a
  different code path — verified via Read this is in
  `dispatchToLeaders`'s catch and is the only writer for that
  conversation). No race surface.

### #3464 — incomingTypes capability extension

**Chosen exposure model:** **curated stable subset**, not full-union
exposure or typed-tier shape.

Rationale vs. the two alternatives in the #3464 body:

- **Full-union exposure:** couples the public agent contract to internal
  WSMessage evolution. `review_gate_response` is feature-internal
  (resolves a server-emitted gate); leaking it implies it's a stable
  agent surface, which we do not want to commit to.
- **Typed-tier shape (`{ stable: [...], experimental: [...] }`):**
  premature governance. Today there is exactly one stable client→server
  primitive worth advertising (`abort_turn`); the others are either
  required (`auth`, `start_session`, `chat`, `resume_session`,
  `close_conversation`) or feature-internal (`review_gate_response`).
  When the next agent-facing primitive is added (per the re-evaluation
  criterion in #3464), the design choice between flat-array and
  tier-shape can be revisited with a real second data point.

**Choice symmetry with `promptKinds`:** `promptKinds` is a curated flat
array. `incomingTypes` mirrors that contract. The naming uses
`incomingTypes` (server's perspective, matching the conventional
client→server "incoming" wire direction at the server) rather than
`outgoingTypes` (client's perspective) because the manifest is *emitted*
by the server, and the server's vocabulary is the source of truth for
what it accepts.

**Initial population:** the curated array contains `abort_turn` only.
The required-for-protocol types (`auth`, `start_session`, `chat`,
`resume_session`, `close_conversation`) are NOT advertised — they are
prerequisites for any session, not feature-detectable capabilities.
`review_gate_response` is NOT advertised — feature-internal.
`interactive_prompt_response` is NOT advertised — Stage 2-internal,
tracked under the soleur-go protocol.

**Source-of-truth invariant:** the curated array MUST be exported from
a single TS module so the two emit sites (`ws-handler.ts:1194` for
`start_session`, `ws-handler.ts:1252` for `resume_session`) cannot
drift. Both emit sites already share `promptKinds` (read via the same
constant); we extend the same constant module.

## Research Reconciliation — Spec vs. Codebase

Both issue bodies enumerate file:line references. Read-verified:

| Issue claim | Codebase reality (verified at HEAD `b6f04394`) | Plan response |
|---|---|---|
| #3463: result branch writes `waiting_for_user` "around line 1528 (post-PR1 numbering)" | Actual line is **1613** in `apps/web-platform/server/agent-runner.ts` at HEAD | Plan uses verified line numbers; issue's "around" qualifier accepted |
| #3463: abort branch writes `failed` at "lines 1547-1565" | Actual abort-branch ternary is at **lines 1763-1765**; the surrounding catch starts at **1700** | Plan uses verified line numbers |
| #3463: `controller.signal.reason` set by `ws.on("close")` at `ws-handler.ts:357-370` | Actual `ws.on("close")` is at **lines 1876-1906**; the abort fires via `abortSession(uid, convId)` (no kind arg) → registry default `"disconnected"` per `abort-classifier.ts:24-29` | Plan re-cites verified locations; behavior identical (default `disconnected` kind) |
| #3464: `session_started.capabilities` schema at `lib/ws-zod-schemas.ts:274-276` | Actual schema is at **lines 267-277** (sessionStartedSchema) with capabilities at **274-276** | Plan accepted as-cited; issue partially-correct |
| #3464: `WSMessage` type at `lib/types.ts:242` | Verified — `session_started` variant at exactly **line 242** | Plan accepted |
| #3464: ws-handler emit sites for `session_started` | Two emit sites verified: **line 1194** (`start_session` deferred-creation path) and **line 1252** (`resume_session` path). Both currently emit `{ type: "session_started", conversationId }` WITHOUT `capabilities` — i.e., `promptKinds` itself is not yet emitted in this server build despite being declared in the schema. | Plan §"Implementation Phases" §Phase 2 must wire BOTH `promptKinds` AND `incomingTypes` since neither is currently emitted. |

**Surfaced gap:** the schema declares `capabilities.promptKinds` as
optional and the type allows it, but the two server emit sites
(`ws-handler.ts:1194`, `ws-handler.ts:1252`) both call
`sendToClient(userId, { type: "session_started", conversationId: ... })`
without a `capabilities` field. Per the typed-optional-field-wire-drop
learning (`knowledge-base/project/learnings/2026-05-07-typed-optional-field-wire-drop-caught-by-user-impact-reviewer.md`),
this is an exact instance of the same class — a typed optional field
that compiles and tests-green but never reaches the wire. Phase 2 of
this plan fixes both fields in the same pass to stop the wire drop on
the `promptKinds` side too.

## Open Code-Review Overlap

Six open code-review issues touch the planned files. Disposition for each:

- **#3454 (review: expose pdf_metadata as agent-callable MCP tool, agent-runner.ts):** Acknowledge — different concern (PDF metadata MCP tool; this plan's agent-runner edits are constrained to the abort/result branches at lines 1646/1659/1766/1852). No surface overlap.
- **#3392 (review: PR-B #3244 deferrals — denied_jti wire-up, allowlist tightening, agent-runner.ts):** Acknowledge — auth/JWT concerns; orthogonal to abort-branch status writes.
- **#3343 (review: case-insensitive `</document>` escape across cc + leader prompt builders):** Acknowledge — prompt-builder concern; this plan does not touch prompt construction.
- **#3242 (review: tool_use WS event lacks raw name field for agent consumers, ws-handler.ts + ws-zod-schemas.ts + lib/types.ts):** Acknowledge — adds a `name` field to the `tool_use` WSMessage variant. **Sibling-class concern** to #3464 (both extend agent-facing WS surface). Folding in #3242 would meaningfully widen scope (touches `buildToolUseWSMessage`, `cc-dispatcher.ts` parallel emit, `chat-state-machine.ts` reducer, all `tool_use` test fixtures). Defer for its own cycle. Recorded note: when #3242 lands, the implementer should re-check `incomingTypes` is still emitting per this plan's wiring (it should, but the test added in this plan exists to confirm).
- **#2955 (arch: process-local state assumption needs ADR + startup guard, agent-runner.ts):** Acknowledge — long-running architectural concern (multi-instance deploy story). Orthogonal to status-write race. The status-column guard introduced here is, incidentally, slightly more multi-instance-safe than a process-local flag would be — a small contribution to that broader effort.
- **#3374 (review: emit slot_reclaimed WS frame, ws-handler.ts + ws-zod-schemas.ts):** Acknowledge — adds a NEW server→client WS variant. Sibling concern but disjoint surface (server→client; `incomingTypes` is the client→server manifest). When #3374 lands, the implementer adds the new variant to `KNOWN_WS_MESSAGE_TYPES`, NOT to `incomingTypes`.
- **#3372 (review: tryLedgerDivergenceRecovery stale-heartbeat tautological at 120s, ws-handler.ts):** Acknowledge — different code path (ledger-divergence recovery), no overlap with abort-branch status writes.
- **#2961 (review: enforce conversations.repo_url immutability via Postgres trigger, ws-handler.ts):** Acknowledge — DB-trigger concern; orthogonal.
- **#2191 (refactor(ws): clearSessionTimers helper + jitter, ws-handler.ts):** Acknowledge — refactor concern; orthogonal.
- **#2963 (review: introduce Supabase typegen for ConversationPatch drift resistance, conversation-writer.ts):** Acknowledge — typegen concern. The new `onlyIfStatusIn` field this plan adds to `UpdateConversationOptions` (NOT `ConversationPatch`) is unaffected by the typegen choice; the patch surface stays hand-written per the existing module docstring.

No overlap is folded into this PR. All scope-outs remain open and
re-evaluated on their own cycle.

## Technical Considerations

### Architecture impacts

- **Conversation-writer wrapper (#3463):** new `onlyIfStatusIn?` option
  on `UpdateConversationOptions` is the minimal surface change. Filter
  applies a single `.in("status", ...)` on the existing base query.
  No new RPC, no new index — `conversations.status` is already
  queryable; this is just a chained filter on the existing
  composite-key UPDATE.
- **WSMessage union (#3464):** widening the `capabilities` sub-shape on
  one variant. Per `cq-union-widening-grep-three-patterns`, sub-shape
  widening of a single discriminated-union variant does NOT trigger
  the same exhaustive-switch consumer rails as a top-level variant
  add. Three consumer patterns to grep:
  1. Direct `capabilities.promptKinds` reads — none expected today
     (server doesn't emit it yet).
  2. Direct `capabilities.incomingTypes` reads — none expected; this
     plan introduces them.
  3. Test fixtures pinning `session_started` shape — must be enumerated
     and updated.

### Performance implications

Negligible. `#3463`: one extra `.in("status", ...)` predicate on a
composite-key UPDATE that already filters by `(id, user_id)`. `#3464`:
one extra `readonly string[]` field on a frame emitted at most twice
per session (start + resume).

### Security considerations

- **#3463:** the `onlyIfStatusIn` guard is a *narrowing* of an existing
  UPDATE's effective scope — strictly more conservative than today.
  Cannot widen access. The `(id, user_id)` composite key remains the
  authorization boundary.
- **#3464:** `incomingTypes` is a server-emitted advisory list; it does
  NOT change what the server accepts. The WS message router still
  matches on `case "abort_turn":` regardless of whether it's advertised.
  The inverse is also true: omitting a type from `incomingTypes`
  doesn't disable it. The manifest is observability/discovery, not a
  policy gate. **This is the load-bearing security property** — agents
  cannot escalate by injecting unadvertised types into the manifest
  (server emits, doesn't read).

### NFR impacts

- **Reliability (#3463):** removes a known false-positive `failed`-status
  write. Strictly better.
- **Compatibility (#3464):** field is `optional` — legacy clients/agents
  ignore. Cannot break wire compat.
- **Observability:** #3463 plan does NOT add a new Sentry mirror at
  the no-op site (a row already at a terminal state is the success
  case, not a degraded fallback). The `expectMatch: false` default
  means 0-rows-affected returns `{ ok: true }` silently.

### Attack Surface Enumeration (skipped — not a security fix)

Neither #3463 nor #3464 is a security-class change. #3463 is a
reliability fix; #3464 is observability/discovery. The
`User-Brand Impact` section below covers the user-impact framing.

## User-Brand Impact

- **If this lands broken, the user experiences:**
  - **#3463 if regressed:** the user's clean conversations get marked
    `failed` in their sidebar history. Concrete artifact: the
    `failed` status badge on a conversation that completed cleanly.
  - **#3464 if regressed:** an agent calling `abort_turn` cannot
    discover it via the manifest and falls back to source-diving the
    WSMessage union. Concrete artifact: the agent's feature-detection
    code path returns `false` for Stop capability and the agent doesn't
    expose Stop to its operator.
- **If this leaks, the user's data / workflow / money is exposed via:**
  - Neither change touches credentials, BYOK keys, billing rows, or
    user-owned data. The `incomingTypes` manifest is a list of WS
    message-type strings (`["abort_turn"]`) — no user-identifiable
    information. The status-column guard is a query predicate on a
    column the user already owns.
- **Brand-survival threshold:** `none` (with rationale below)

*Scope-out override (preflight Check 6):* `threshold: none, reason: this PR
modifies abort/result-branch finalization in agent-runner.ts and the
session_started capability manifest — neither writes user-owned data,
credentials, billing, or auth state; the failure modes are user-visible
inconvenience (mis-labeled status, agent feature-detect miss), not
single-user incident or aggregate exposure.`

The `single-user incident` threshold from
`hr-weigh-every-decision-against-target-user-impact` does not apply
because the worst single-user failure is a status-badge mis-label
(#3463 regression) or a feature-detection miss (#3464 regression).
Neither is brand-survival-threatening.

## Acceptance Criteria

### Functional Requirements

#### #3463 — disconnect-after-result race

- [ ] `apps/web-platform/server/conversation-writer.ts` exports a new
      `onlyIfStatusIn?: ReadonlyArray<Conversation["status"]>` field on
      `UpdateConversationOptions`. When provided, the wrapper appends
      `.in("status", onlyIfStatusIn)` to the existing
      composite-key UPDATE.
- [ ] `apps/web-platform/server/agent-runner.ts` adds a new helper
      `updateConversationStatusIfActive(userId, conversationId, status)`
      that uses `expectMatch: false` + `onlyIfStatusIn: ["active"]` and
      returns `Promise<void>` (silent no-op on 0-rows-affected).
- [ ] Line **~1766** (abort branch's non-superseded
      `updateConversationStatus` call) is replaced with the new helper
      so the disconnect path cannot stomp a row that already reached a
      terminal state.
- [ ] Same replacement applied at:
  - Line **~1646** (result-branch fallback `failed`-cascade after a
    failed `waiting_for_user` flip).
  - Line **~1659** (result-branch fallback when `assistantPersisted = false`).
  - Line **~1852** (non-abort thrown errors path).
- [ ] No guard at line **~1613** (the result branch's primary
      `waiting_for_user` write — that's the writer we want to win the
      race; guarding it would re-introduce the bug from the other side).
      This site continues to use `updateConversationStatus` (with
      `expectMatch: true`) per its load-bearing
      "0-rows = genuinely broken" contract.
- [ ] Line **~1640** (result-branch fallback's first attempt — re-write
      `waiting_for_user` when the primary write threw): keep
      `updateConversationStatus` (with `expectMatch: true`). If THAT
      write returns 0-rows, something is genuinely broken — the original
      contract is correct here.
- [ ] No guard at line **~2027** (`dispatchToLeaders`'s catch — verified
      by Read as the sole writer for that conversation in that branch;
      no race surface).

#### #3464 — incomingTypes capability extension

- [ ] `apps/web-platform/lib/ws-zod-schemas.ts:274-276` — `capabilities`
      sub-schema gains optional `incomingTypes: z.array(z.string()).readonly().optional()`.
- [ ] `apps/web-platform/lib/types.ts:242` — `session_started` variant's
      `capabilities` shape mirrors the schema: `{ promptKinds: readonly string[]; incomingTypes?: readonly string[] }`.
- [ ] New module `apps/web-platform/lib/ws-capabilities.ts` (or extend
      an existing constant module if grep finds a natural home — see
      Phase 0) exports two `readonly string[]` constants:
      - `WS_PROMPT_KINDS` — the curated server→client `interactive_prompt.kind`
        set from #2885 (already canonical somewhere; consolidate or import).
      - `WS_INCOMING_TYPES = ["abort_turn"] as const` — the curated
        client→server manifest. **Initially `abort_turn` only.**
- [ ] `apps/web-platform/server/ws-handler.ts:1194` (`start_session` emit)
      passes `capabilities: { promptKinds: WS_PROMPT_KINDS, incomingTypes: WS_INCOMING_TYPES }`.
- [ ] `apps/web-platform/server/ws-handler.ts:1252` (`resume_session` emit)
      passes the same `capabilities` payload.
- [ ] If `cc-dispatcher.ts` or any other module emits `session_started`
      independently (verified via Phase 0 grep), the same payload is
      threaded.

### Non-Functional Requirements

- [ ] No new Sentry mirror at the `onlyIfStatusIn` no-op site (silent
      success is the contract for the conditional write — the row
      legitimately may have already reached terminus).
- [ ] All three layers of `apps/web-platform/test/` fixtures that pin
      `session_started` shape are updated (Phase 0 enumerates them
      via grep).
- [ ] `tsc --noEmit` clean — discriminated-union widening on a single
      variant must not regress any consumer.
- [ ] `bun test apps/web-platform/test/` green — including any
      `WSMessage` exhaustiveness test files (`*.test-d.ts`).

### Quality Gates

- [ ] Test coverage: each of the four agent-runner sites + the new
      `onlyIfStatusIn` wrapper field + the `incomingTypes` emit at
      both `session_started` sites has a dedicated test scenario.
- [ ] No new dependencies.
- [ ] No DB migration (status-column guard is a query predicate; no
      schema change).

## Test Scenarios

### Acceptance Tests (RED phase targets)

#### #3463 — race-window coverage

Test file: `apps/web-platform/test/agent-runner-disconnect-after-result-race.test.ts` (NEW).

- **AC1.** Given an active conversation, when the result branch
  successfully writes `status='waiting_for_user'` AND the WS connection
  closes immediately after (triggering the abort branch with
  `signal.reason = SessionAbortError("disconnected")`), then the abort
  branch's UPDATE is a no-op (status remains `waiting_for_user`) and
  no Sentry event is emitted.
- **AC2.** Given an active conversation that has NOT been moved to a
  terminal state, when the WS connection closes (disconnect path
  fires before any result emission), then the abort branch writes
  `failed` exactly as today.
- **AC3.** Given a conversation already at `status='aborted'` (set by
  a concurrent `abortSession(..., "user_requested_stop")`), when a
  late disconnect-abort fires, then the late write is a no-op
  (status remains `aborted`).
- **AC4.** Result-branch fallback: given a conversation where the
  result branch's `waiting_for_user` write throws AND the row is
  already at `aborted` (concurrent user-stop), then the `failed`
  cascade at line 1646 is a no-op.

#### #3464 — capability emission

Test file: `apps/web-platform/test/ws-handler-session-started-capabilities.test.ts` (NEW or extend existing if grep finds one).

- **AC5.** Given a `start_session` request, when the server emits
  `session_started`, then the frame contains
  `capabilities: { promptKinds: [...], incomingTypes: ["abort_turn"] }`.
- **AC6.** Given a `resume_session` request, when the server emits
  `session_started`, then the frame contains the same `capabilities`
  payload.
- **AC7.** Given the curated `WS_INCOMING_TYPES` constant, when the
  zod schema parses a `session_started` frame containing
  `incomingTypes: ["abort_turn"]`, then parsing succeeds.
- **AC8.** Type-level test (`*.test-d.ts`): `WSMessage` narrowing on
  `session_started` provides `capabilities?.incomingTypes` as
  `readonly string[] | undefined`.

### Regression Tests

- **R1.** `apps/web-platform/test/agent-runner-result-branch-finalization.test.ts`
  must continue to pass — the `onlyIfStatusIn` guard at lines 1646/1659
  must NOT change behavior when the row is at `status='active'`.
- **R2.** `apps/web-platform/test/abort-all-sessions.test.ts` must
  continue to pass — superseded path is unchanged (no guard added).
- **R3.** `apps/web-platform/test/ws-abort.test.ts` must continue to
  pass — user-requested abort path's `waiting_for_user` write is
  unchanged.

### Edge Cases

- **E1.** `signal.reason` is `undefined` (defensive — should not happen
  given `abort-classifier.ts` defaults, but `classifyAbortReason` returns
  `kind: "unknown"` for non-Error reasons). Guard still fires; behavior
  identical to the `disconnected` path (today's pre-PR1 behavior, per
  abort-classifier.ts:55-56).
- **E2.** `incomingTypes` field absent (legacy server build): the
  optional field on the schema means client agents that read it must
  treat absent-or-empty as "no incoming-type discovery available, fall
  back to source-diving the union". Documented in the new constant
  module's header comment.
- **E3.** `WSMessage` exhaustiveness: extending the `capabilities`
  sub-shape on one variant does NOT trigger the
  `cq-union-widening-grep-three-patterns` consumer rails (the variant
  itself is unchanged; only its inner shape grew). The `*.test-d.ts`
  exhaustiveness gate (`KNOWN_WS_MESSAGE_TYPES`) is unaffected — the
  variant `"session_started"` is already in the set. Test AC8 is
  additive coverage for the inner shape.

### Integration Verification (for `/soleur:qa`)

- **Browser:** Navigate to `https://app.soleur.ai`, open a Command
  Center conversation, send "what is 2+2", wait for the assistant
  reply to fully stream, immediately close the tab. Reopen the
  Command Center; the conversation in the sidebar must show
  `waiting_for_user` (cleanly completed), NOT `failed`.
- **WS frame inspection:** From browser DevTools → Network → WS, on
  fresh `start_session`, verify the `session_started` frame contains
  `capabilities.incomingTypes: ["abort_turn"]`.

## Files to Edit

- `apps/web-platform/server/conversation-writer.ts` — add `onlyIfStatusIn?` option to `UpdateConversationOptions`; thread through the base query in `updateConversationFor`.
- `apps/web-platform/server/agent-runner.ts` — add `updateConversationStatusIfActive` helper; replace `updateConversationStatus` calls at lines ~1646, ~1659, ~1766, ~1852 with the new helper. **Keep** `updateConversationStatus` at lines ~1613 (primary result-branch write) and ~1640 (fallback first-attempt). **No guard** at line ~2027.
- `apps/web-platform/lib/ws-zod-schemas.ts:267-277` — add optional `incomingTypes: z.array(z.string()).readonly().optional()` to the `capabilities` sub-schema.
- `apps/web-platform/lib/types.ts:242` — extend the `session_started` variant's `capabilities` shape.
- `apps/web-platform/server/ws-handler.ts:1194` (`start_session` emit) and `:1252` (`resume_session` emit) — populate the full `capabilities` payload.

### Test fixtures pinning `session_started` shape (verified live via Phase 0 grep)

All 9 files surfaced by `rg -l 'session_started' apps/web-platform/test/`:

- `apps/web-platform/test/useWebSocket-abort.test.tsx` (8 fixture sites: lines 111, 124, 156, 175, 208, 226, 243, 272)
- `apps/web-platform/test/ws-zod-schemas.test.ts` (2 sites: lines 20, 293)
- `apps/web-platform/test/ws-client-resume-history.test.tsx` (line 244)
- `apps/web-platform/test/ws-resume-by-context-path.test.ts` (lines 174, 310)
- `apps/web-platform/test/ws-deferred-creation.test.ts` (lines 139, 154)
- `apps/web-platform/test/ws-known-types-guard.test.ts` (line 32)
- `apps/web-platform/test/ws-start-session-cap-hit.test.ts` (line 138)
- `apps/web-platform/test/ws-protocol.test.ts` (lines 36, 71, 74)
- `apps/web-platform/test/chat-page.test.tsx` (filename match — verify exact line in Phase 4)

**Audit guidance:** for each fixture, confirm the test does NOT
explicitly assert `capabilities === undefined` — fixtures that pin the
absent-capabilities shape MUST stay as-is to test the legacy-server-build
code path (E2 edge case). Fixtures that ignore the field (most of them)
need no change. Fixtures that match-on full shape via `toMatchObject` or
`toEqual` need the new shape.

## Files to Create

- `apps/web-platform/lib/ws-capabilities.ts` — exports `WS_INCOMING_TYPES` (and `WS_PROMPT_KINDS` if Phase 0 grep finds the prompt-kinds constant is currently inlined or has no canonical home).
- `apps/web-platform/test/agent-runner-disconnect-after-result-race.test.ts` — covers AC1-AC4.
- `apps/web-platform/test/ws-handler-session-started-capabilities.test.ts` — covers AC5-AC7.
- `apps/web-platform/test/ws-handler-session-started-capabilities.test-d.ts` — covers AC8 (type-level narrowing test).

## Implementation Phases

### Phase 0: Verification grep (must run before any code change)

Per `hr-when-a-plan-specifies-relative-paths-e-g`:

```bash
# Verify all session_started emit sites
git ls-files | grep -E '\.(ts|tsx)$' | xargs rg -l '"session_started"' apps/web-platform/

# Find canonical promptKinds constant (or confirm it's currently inlined)
git ls-files | grep -E '\.(ts|tsx)$' | xargs rg -l 'promptKinds' apps/web-platform/

# Find all session_started fixtures in tests
rg -l 'session_started' apps/web-platform/test/

# Verify the four agent-runner sites are still at the cited lines
rg -n 'updateConversationStatus.*"failed"' apps/web-platform/server/agent-runner.ts
rg -n 'updateConversationStatus.*"waiting_for_user"' apps/web-platform/server/agent-runner.ts

# Find any cc-dispatcher or other module emitting session_started
rg -n 'type.*session_started' apps/web-platform/server/
```

If any cited line drifted by more than ±5 from the plan's numbers,
update the plan's line references in the same commit. Per
`cq-union-widening-grep-three-patterns`, also run the three consumer
patterns for `capabilities.`:

```bash
rg -n 'capabilities\.promptKinds|capabilities\.incomingTypes' apps/web-platform/
rg -n 'capabilities\?\.promptKinds|capabilities\?\.incomingTypes' apps/web-platform/
rg -n '_exhaustive: never' apps/web-platform/ | rg -i 'session_started|capabilit'
```

### Phase 1: Conversation-writer extension (#3463 prerequisite)

1. Add `onlyIfStatusIn?: ReadonlyArray<Conversation["status"]>` to `UpdateConversationOptions`.
2. In `updateConversationFor`, after the `.eq("user_id", userId)` chain, conditionally `.in("status", options.onlyIfStatusIn)` if provided.
3. Add Vitest scenario in `apps/web-platform/test/conversation-writer-only-if-status.test.ts` (NEW) — given the option is provided AND the row's status is in the set, the UPDATE applies; given the row's status is not in the set, the UPDATE is a 0-rows no-op AND `expectMatch: false` returns `{ ok: true }`.

### Phase 2: Wire the new option at the four agent-runner sites (#3463)

1. Lines ~1646, ~1659, ~1766, ~1852 — pass `onlyIfStatusIn: ["active"]` in the options arg.
2. Update `apps/web-platform/test/agent-runner-disconnect-after-result-race.test.ts` (NEW) per AC1-AC4.

### Phase 3: Capability extension (#3464)

1. Create `apps/web-platform/lib/ws-capabilities.ts` exporting `WS_INCOMING_TYPES = ["abort_turn"] as const` (and `WS_PROMPT_KINDS` if Phase 0 grep confirms no canonical home).
2. Extend `lib/ws-zod-schemas.ts` `capabilities` sub-schema with optional `incomingTypes`.
3. Extend `lib/types.ts` `session_started` variant's `capabilities` shape.
4. Update both emit sites in `ws-handler.ts` (lines 1194 + 1252) to thread `capabilities: { promptKinds: WS_PROMPT_KINDS, incomingTypes: WS_INCOMING_TYPES }`.
5. Add tests per AC5-AC7 + AC8.

### Phase 4: Fixture sync

Update every `session_started` fixture surfaced by Phase 0 grep so
the new optional `capabilities` shape is consistent across tests.
**No fixture should pin `capabilities` as `undefined`** unless it's
explicitly testing the legacy-server-build code path (E2 edge case).

### Phase 5: Verification

1. `tsc --noEmit` from `apps/web-platform/`.
2. `bun test apps/web-platform/test/` — full app suite, including any
   `*.test-d.ts` exhaustiveness gates.
3. Local QA per "Integration Verification" above (manual browser tab-close).

## Domain Review

**Domains relevant:** Engineering only (CTO).

This is a server-side bug fix + WS protocol extension on existing
agent-facing surface. No product UI surface, no copy, no marketing
artifact, no legal/compliance touch, no payments, no infra
provisioning. The `/work` skill's CTO domain leader is implicitly
covered by the engineering-only review surface; no separate Task
spawn required (per `pdr-do-not-route-on-trivial-messages-yes` —
domain signal IS the task topic).

### CTO (engineering)

**Status:** reviewed (inline)
**Assessment:** Both changes are minimal-surface and well-scoped.
The `onlyIfStatusIn` option generalizes the existing
composite-key UPDATE wrapper without adding a parallel write path —
strictly more conservative than today. The `incomingTypes` extension
mirrors the established `promptKinds` precedent. Sharp edges to flag:

- **Typed-optional-field wire-drop class** (per
  `2026-05-07-typed-optional-field-wire-drop-caught-by-user-impact-reviewer.md`):
  `incomingTypes` is exactly the field shape that survived TS + tests
  but was missing from the wire in PR #3430. Phase 2 explicitly
  enumerates the two emit sites (`ws-handler.ts:1194` + `:1252`) AND
  test AC5-AC6 assert the field reaches the wire. The same wire-drop
  risk fires for `promptKinds` itself (currently declared but not
  emitted) — this plan fixes both in the same pass.
- **Discriminated-union sub-shape widening** (per
  `cq-union-widening-grep-three-patterns`): widening one variant's
  inner `capabilities` shape does NOT trigger the variant-level
  exhaustive-switch rails. Phase 0 grep covers the three consumer
  patterns for `capabilities.`-readers as a defense in depth.
- **Defense relaxation analysis** (per
  `2026-05-05-defense-relaxation-must-name-new-ceiling.md`): the
  `onlyIfStatusIn` guard is a *narrowing*, not a relaxation. It
  removes a known false-positive write without removing or weakening
  any existing guarantee. No new ceiling needed.

### Product (CPO)

**Tier:** none — no user-facing UI surface, no new copy, no flow change.

The bug fix's user-visible improvement is "fewer false `failed` badges
in the sidebar" — a status-correctness improvement, not a new UI
artifact. The capability extension is invisible to web users (only
agents and dev-tools inspect WS frames).

### Skipped specialists

- **ux-design-lead:** N/A (no UI surface)
- **copywriter:** N/A (no copy change)
- **spec-flow-analyzer:** skipped — bug fix + protocol field add, no
  multi-step user flow.

## Sharp Edges

- **Conditional UPDATE with `.in()` on a Postgres column with no
  matching index:** `conversations.status` is filtered through `.in()`
  in the UPDATE's WHERE clause. The composite-key
  `(id, user_id)` index already narrows to a single row; the
  `.in("status", ...)` filter executes as a row-level predicate after
  the index lookup. No extra index needed.
- **Per-variant explicit listing in `incomingTypes`:** the curated
  list is `["abort_turn"]` only. When the next agent-facing primitive
  is added, the implementer MUST decide whether to add it to
  `WS_INCOMING_TYPES` — the const's header comment must spell this
  out so the next variant author doesn't silently extend the manifest.
- **Sentry mirror NOT added at no-op site:** the wrapper's
  `expectMatch: false` default means a no-op (0-rows-affected)
  returns `{ ok: true }` silently. Per
  `cq-silent-fallback-must-mirror-to-sentry`, this is exempt
  because the no-op IS the success case (row already reached
  terminus). Do NOT add a Sentry mirror at the no-op site —
  it would fire on every clean disconnect-after-result and become
  pure noise.
- **Schema vs. wire vs. consumer parity (typed-optional-field-wire-drop
  pattern):** The schema declares `capabilities.{promptKinds, incomingTypes}`
  optional. The two emit sites must populate them. Tests AC5-AC6 must
  assert presence on the wire. Per the 2026-05-07 learning, this is the
  exact failure shape that compiles + tests-green but never reaches the
  wire. Plan Phase 2 step 4 + AC5-AC6 close the loop.
- **A plan whose `## User-Brand Impact` section is empty, contains
  only `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6.** This plan's threshold is `none` with an
  explicit scope-out reason — accepted by preflight Check 6.

## References & Research

### Internal References

- `apps/web-platform/server/agent-runner.ts:1613` — result branch's `waiting_for_user` write (the writer we want to win the race)
- `apps/web-platform/server/agent-runner.ts:1763-1765` — abort branch's `failed`-vs-`waiting_for_user` ternary (the writer we're guarding)
- `apps/web-platform/server/agent-runner.ts:1640,1646,1659` — result-branch fallback finalization wrap
- `apps/web-platform/server/agent-runner.ts:1852` — non-abort thrown errors path
- `apps/web-platform/server/ws-handler.ts:1876-1906` — `ws.on("close")` grace-period `abortSession` (origin of `disconnected` reason)
- `apps/web-platform/server/abort-classifier.ts:24-29,78-101` — `AbortKind` enum + `classifyAbortReason` shape
- `apps/web-platform/server/conversation-writer.ts:88-96,132-202` — `ConversationPatch` + `updateConversationFor` (the wrapper we're extending)
- `apps/web-platform/lib/ws-zod-schemas.ts:267-277` — `sessionStartedSchema` + `capabilities` sub-shape
- `apps/web-platform/lib/types.ts:242` — `WSMessage` `session_started` variant
- `apps/web-platform/server/ws-handler.ts:1194,1252` — the two `session_started` emit sites
- `apps/web-platform/lib/ws-known-types.ts` — `KNOWN_WS_MESSAGE_TYPES` (already includes `session_started`; no edit needed)

### Institutional Learnings

- `knowledge-base/project/learnings/2026-05-07-typed-optional-field-wire-drop-caught-by-user-impact-reviewer.md` — exact pattern match for `incomingTypes`; Phase 2 + AC5-AC6 designed to prevent recurrence on this PR.
- `knowledge-base/project/learnings/2026-05-05-defense-relaxation-must-name-new-ceiling.md` — confirmed N/A (this plan narrows, doesn't relax).
- AGENTS.md `cq-union-widening-grep-three-patterns` — Phase 0 grep covers consumer-pattern rails.
- AGENTS.md `cq-silent-fallback-must-mirror-to-sentry` — exemption rationale documented in Sharp Edges (no-op IS success).
- AGENTS.md `hr-weigh-every-decision-against-target-user-impact` — User-Brand Impact section above; threshold `none` with explicit scope-out reason.

### Related Work

- PR #3447 — `feat(web-platform): user-initiated Stop — server, DB, protocol (PR1 of #3448)` — introduced the abort branch's `isUserRequested ? waiting_for_user : failed` ternary the #3463 fix narrows.
- PR #3469 — `feat(web-platform): user-initiated Stop — client UI (PR2 of #3448)` — landed the client-side Stop UI; not directly modified by this plan.
- Issue #3448 — parent issue for the user-initiated Stop feature.
- Issue #2885 / Stage 3 — introduced `capabilities.promptKinds`; this plan generalizes the precedent.
- Issue #3242 — sibling-class scope-out (tool_use raw name field); explicitly NOT folded in (see Open Code-Review Overlap).

### Pre-merge / Post-merge Acceptance

- **Pre-merge (PR):**
  - All AC1-AC8 + R1-R3 + E1-E3 tests green.
  - `tsc --noEmit` clean from `apps/web-platform/`.
  - PR body uses `Closes #3463` and `Closes #3464` on their own lines (per `wg-use-closes-n-in-pr-body-not-title-to`).
- **Post-merge (operator):** none. No DB migration, no infra change, no Doppler secret rotation. Standard CI deploy via the merge-to-main pipeline is sufficient.

## Deepen Insights

This section captures the additional considerations surfaced during the
deepen-plan pass that were not in the original plan but are
load-bearing for implementation correctness.

### Insight 1 — `expectMatch: true` is a load-bearing contract; don't fold a silent guard into it

The original plan's "extend `UpdateConversationOptions` with
`onlyIfStatusIn?` and pass it through `updateConversationStatus`" is
load-bearing-incorrect. `updateConversationStatus` (the agent-runner.ts
helper at line 432) uses `expectMatch: true`, which:

1. Throws when 0-rows are affected.
2. Mirrors a `"conversation update affected 0 rows (expectMatch)"`
   Sentry event.

For the disconnect-after-result race, the **success** path is a 0-rows
outcome (the row already left `active`). Folding `onlyIfStatusIn` into
`updateConversationStatus` would emit a Sentry event for every clean
disconnect-after-result — directly violating
`cq-silent-fallback-must-mirror-to-sentry`'s "expected states"
exemption clause.

**Resolution:** introduce a separate helper
`updateConversationStatusIfActive` that uses `expectMatch: false` and
makes the silent-no-op contract explicit at the call site. Sites that
need the strict contract (lines 1613, 1640) keep using the original
helper.

This insight applies the same pattern as
`2026-05-06-defense-in-depth-recovery-mirroring-sql-predicate-document-load-bearing-value.md`:
when adding a defense layer at the same surface as an existing primitive,
the load-bearing sub-value (here: silent-no-op vs. throw-and-mirror)
must be documented at the call site.

### Insight 2 — The four guarded sites are not semantically identical

- **Line 1646** (`failed`-cascade after `waiting_for_user` flip
  failure): always writes `failed`. Guard prevents stomp on a row that
  reached terminus during the cascade window.
- **Line 1659** (`failed`-write when `assistantPersisted = false`):
  always writes `failed`. Guard prevents stomp.
- **Line 1766** (abort branch ternary): writes
  `isUserRequested ? "waiting_for_user" : "failed"`. Guard's effect
  splits by branch:
  - User-Stop (writes `waiting_for_user`): no-op when row is already
    `waiting_for_user`. **Same end state — semantically equivalent.**
    The `session_ended:user_aborted` ack still fires (unconditional
    within the `if (isUserRequested)` block).
  - Disconnect (writes `failed`): no-op when row is already
    `waiting_for_user`. **The bug fix.**
- **Line 1852** (non-abort thrown errors): always writes `failed`.
  Guard prevents stomp on the rare case where a concurrent terminal
  write landed before this catch fires.

The conditional-update guard is correct at all four sites; the
end-state semantics differ but the guard's intent is uniform: "if
someone else already wrote a terminal state, leave it alone."

### Insight 3 — `promptKinds` is currently declared but not emitted (typed-optional-field wire-drop, exact instance)

Per the live grep run during deepen-plan: the schema at
`ws-zod-schemas.ts:274-276` declares `capabilities: { promptKinds:
readonly string[] }` as optional, the type at `lib/types.ts:242`
mirrors it, but neither emit site at `ws-handler.ts:1194` or `:1252`
populates it. The current build emits
`{ type: "session_started", conversationId }` — no `capabilities` field
at all.

This is exactly the
`2026-05-07-typed-optional-field-wire-drop-caught-by-user-impact-reviewer.md`
pattern: a typed optional field that compiles + tests-green but never
reaches the wire. Phase 3 of this plan fixes BOTH `promptKinds` AND
`incomingTypes` in the same pass — a wire-completeness regression test
(AC5-AC6) pins the wire shape so the next field-addition that forgets
the emit hop fails the test.

**Reconciliation:** the original plan's §"Surfaced gap" prose noted
this; the deepen pass elevated the fix from "implied by Phase 2 step 4"
to a first-class AC item.

### Insight 4 — `WS_PROMPT_KINDS` constant has no canonical home today

The live grep `rg -n 'promptKinds' apps/web-platform/` returned only
two hits: the schema (line 275) and the type (line 242). There is no
shared constant, no consumer that reads it, no test that asserts it.
The "curated promptKinds set from #2885" exists only as a phrase in
PR review comments and the schema's docstring.

**Implementation requirement:** the new
`apps/web-platform/lib/ws-capabilities.ts` module is the single source
of truth for both `WS_PROMPT_KINDS` AND `WS_INCOMING_TYPES`. Phase 0
grep already confirmed no canonical home exists, so creating one in
Phase 3 step 1 is the right move.

The `WS_PROMPT_KINDS` initial population must enumerate the actual
emitted-by-server `interactive_prompt.kind` values. Per
`apps/web-platform/lib/ws-zod-schemas.ts` (the WSMessage variant
definitions for `interactive_prompt`) — verify in Phase 3 step 1 by
greping `interactive_prompt.*kind:` in `cc-dispatcher.ts` and
`soleur-go-runner.ts`. **Estimate:** 6 kinds based on the #2885
PR-body assertion ("default 6-kind set"). Confirm count live in
Phase 3.

### Insight 5 — Test fixture audit must distinguish "ignores capabilities" from "asserts absent"

Per the live `rg -l 'session_started' apps/web-platform/test/`, 9
files contain `session_started` literals. Most tests construct fixtures
that match on `type` + `conversationId` only; those need no change.
The risk is fixtures that pin the FULL shape via `toMatchObject` /
`toEqual`. Phase 4 audit guidance:

```bash
# Check each fixture file for full-shape match
for f in [9 files]; do
  rg -n 'session_started' "$f" | grep -E 'toMatchObject|toEqual|deep\.equal'
done
```

**Per file, choose one of three actions:**

- **No change** — fixture only constructs the message or matches on
  partial shape (most cases).
- **Add new fields** — fixture matches on full shape; needs
  `capabilities: { promptKinds: WS_PROMPT_KINDS, incomingTypes: WS_INCOMING_TYPES }`.
- **Pin legacy-server-build behavior** — fixture explicitly tests the
  absent-capabilities code path (E2 edge case); leave as-is and add
  comment explaining why.

### Insight 6 — Trace-callgraph-from-entrypoint applies to the emit-site sweep

Per
`knowledge-base/project/learnings/best-practices/2026-05-05-trace-callgraph-from-entrypoint-when-placing-guards.md`,
when placing a guard, trace the value-of-interest from the entry point
to the guarded site, not just from the guard outward. For #3464,
the analogous trace is from the `session_started` emit to every
external observer (browser client, agent client, future MCP tool):

- Browser client: `lib/ws-client.ts:744` — reads `msg.type` only,
  ignores `capabilities` today. Will continue to ignore. No risk.
- Agent client (hypothetical): the curated `WS_INCOMING_TYPES` arrives
  unchanged. No external transform.
- Future MCP tool: when an `mcp__soleur_platform__list_capabilities`
  tool is added (a natural follow-up), it should read from the same
  `WS_INCOMING_TYPES` constant module — single source of truth.

Phase 0 grep `rg -n 'capabilities' apps/web-platform/` returns the
schema + the type only; no consumers read it today. Adding the
emit + a curated constant unlocks consumers without coupling them
to internal WSMessage evolution.

### Insight 7 — No defense-relaxation analysis needed

Per `2026-05-05-defense-relaxation-must-name-new-ceiling.md`: a
plan that **relaxes or removes** a load-bearing defense must enumerate
every threat surface the original was bounding. This plan does the
opposite — it **adds** a guard (`onlyIfStatusIn: ["active"]`) that
narrows an existing UPDATE's effective scope. No threats are
unbounded; no new ceiling needed. **Confirmed N/A.**

### Insight 8 — No defense-in-depth-mirror analysis needed

Per `2026-05-06-defense-in-depth-recovery-mirroring-sql-predicate-document-load-bearing-value.md`:
when adding a defense at the same threshold as an existing primitive
in a different layer, name the load-bearing sub-value. The
`onlyIfStatusIn: ["active"]` guard does NOT mirror an existing SQL
or scheduler primitive — there is no DB-side check today that says
"don't write `failed` if status is already terminal." The guard is
the FIRST defense at this surface, not a mirror. **Confirmed N/A.**
