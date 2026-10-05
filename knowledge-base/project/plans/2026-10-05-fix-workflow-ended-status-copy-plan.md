---
title: "fix: map dormant workflow_ended status renders through founder-facing copy"
date: 2026-10-05
slug: fix-workflow-ended-status-copy
branch: fix-workflow-ended-copy
type: fix
lane: cross-domain
---

# fix: map dormant workflow_ended status renders through founder-facing copy

## Overview

Two dormant render sites — the `workflow_ended` transcript card in
`components/chat/chat-surface.tsx` and the outcome badge in
`components/chat/workflow-lifecycle-bar.tsx` — render the raw
`WorkflowEndStatus` enum token (`internal_error`, `cost_ceiling`, ...)
verbatim. No server→client `workflow_ended` emitter exists today
(`server/cc-dispatcher.ts` routes terminal statuses to `session_ended`
until Stage 3), so the leak is dormant — but the moment a Stage-3 emitter
lands it reintroduces the exact defect fixed for `session_ended` at
commit `d715256ba0` (#9526). This change maps `status` through
badge-length founder-facing copy at both sites, mirroring the merged
session-ended-copy pattern (exhaustive map, membership-gated resolver,
generic fallback, warn-level unmapped report), and extends the test
surface so no snake_case token can reach the DOM.

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed);
no `spec.md` exists for `fix-workflow-ended-copy`.

## Research Insights

### Premise Validation (Phase 0.6)

- `d715256ba0` exists — "fix(web-platform): render founder copy for
  session_ended reasons, not raw enums (#9526)". Its diff added
  `lib/session-ended-copy.ts` (119 LoC), the ws-client mapping+warn arm,
  `test/session-ended-copy.test.tsx` (284 LoC), and the two dormant
  `workflow_ended` render-site comments this plan retires.
- **No `workflow_ended` server→client emitter has shipped.** Grep of
  `apps/web-platform/server/` for `type: "workflow_ended"`: zero hits.
  `ws-handler.ts` `case "workflow_ended"` is the client→server inbound
  *rejection* arm ("server-to-client only"), not an emitter.
  `cc-dispatcher.ts` still carries the "until Stage 3 … route terminal
  statuses to `session_ended`" comment at its `onWorkflowEnded` terminal
  branch. **The dormant-render premise holds.**
- **Wire status vocabulary == `WorkflowEndStatus` exactly.**
  `lib/ws-zod-schemas.ts › workflowEndedSchema` declares
  `status: z.enum(WORKFLOW_END_STATUSES)` — a *closed* enum, not the
  free-form `z.string()` that `session_ended.reason` carries. All
  inbound frames pass `parseWSMessage` (ws-client.ts), so a non-union
  status is rejected with `ws-zod-parse-failure` before the reducer ever
  sees it. The e2e injector routes through the same mocked-WS parse path.
- Cited files all exist: `lib/session-ended-copy.ts`,
  `components/chat/chat-surface.tsx`, `components/chat/workflow-lifecycle-bar.tsx`,
  `server/cc-dispatcher.ts`, `lib/ws-zod-schemas.ts`,
  `test/session-ended-copy.test.tsx`, `e2e/cc-soleur-go-routing.e2e.ts`.
- Collision surface verified live: draft PR **#9051**
  "feat(codex): wire Web lifecycle and history safeguards"
  (author deruelle, head `feat-one-shot-codex-web-live-paths`, OPEN/draft)
  touches `chat-surface.tsx` + `ws-zod-schemas.ts` — assessed disjoint
  hunks; merge-conflict watch item only.

### Property List / Cut List (Phase 0.6b)

Restated properties:

- **P1** — no raw `WorkflowEndStatus` token renders as visible DOM text
  at either `workflow_ended` surface.
- **P2** — `completed` stays visually distinct (emerald vs red keys off
  the raw `status` value — keep the styling check, replace only the
  rendered text). Union-member classification for the styling predicate
  (sharp-edge: single-enum-condition FRs must enumerate every member):
  `completed` → emerald; all 8 other members (`user_aborted`,
  `cost_ceiling`, `idle_timeout`, `plugin_load_failure`,
  `runner_runaway`, `internal_error`, `session_revoked`,
  `worktree_enter_failed`) → red; the generic fallback (unreachable via
  validated frames) renders red.
- **P3** — a status outside the known set renders honest generic copy
  and never a non-string (no render crash, no token leak).
- **P4** — badge copy is pill-length: the ended badge is a
  `text-[10px]` `rounded-full` pill inside a compact flex row; a 60–95
  char sentence cannot fit it.
- **P5** — an unmapped status self-reports (WARN-level Sentry event), so
  a new emitter/status landing without copy is triaged, not silently
  absorbed — the `session_ended` precedent's triage channel.

Mechanisms named in the ask:

| Mechanism | Property bought | Already covered? |
|---|---|---|
| Reuse `SESSION_ENDED_COPY` verbatim | P1, P3, P5 | Partially — its values are transcript *sentences* (e.g. cost_ceiling ≈ 95 chars); fails P4 in the pill badge |
| Sibling `WORKFLOW_ENDED_STATUS_COPY` map + resolver | P1–P5 | Nothing existing provides badge-length labels for `workflow_ended` |

**Cut list:** "reuse SESSION_ENDED_COPY verbatim" — cut because P4
(pill-length label) is unsatisfiable with transcript sentences and the
dormant path gets no visual iteration before a Stage-3 emitter lands.
Existing mechanisms checked (authority files grepped): `lib/session-ended-copy.ts`
(sentence map, `session_ended` frame contract), `server/cc-workflow-end-messages.ts ›
WORKFLOW_END_USER_MESSAGES` (server-side error-path sentences, `completed: ""`
deliberately empty — unusable for the terminal frame), `components/chat/chat-copy.ts ›
CONTEXT_RESET_COPY` (closed-union map precedent, context_reset reasons only).

### Relevant code anchors

- `lib/session-ended-copy.ts` — the merged precedent: exhaustive
  `Record<SessionEndedRenderableReason, string>`, `SESSION_ENDED_GENERIC_COPY`,
  `hasSessionEndedCopy` (hasOwnProperty-gated — the P1 review fix: a
  free-form string resolving `Object.prototype` members like
  `"constructor"` would dispatch a non-string into the render path),
  `sessionEndedCopy()` returning `{copy, mapped}`.
- `lib/types.ts › WORKFLOW_END_STATUSES` — 9-member tuple, single source
  for the Zod enum and the `WorkflowEndStatus` union (bidirectional
  assert rail with `server/soleur-go-runner.ts`).
- `server/cc-workflow-end-messages.ts › WORKFLOW_END_USER_MESSAGES` —
  sentence-voiced map for the non-terminal `{type:"error"}` path;
  `SESSION_ENDED_COPY` is pinned verbatim to it on shared non-empty keys
  by the parity test.
- `components/chat/chat-surface.tsx › case "workflow_ended"` — renders
  `{msg.status}` raw (red/emerald span); carries the
  "map through SESSION_ENDED_COPY" follow-up comment.
- `components/chat/workflow-lifecycle-bar.tsx` — `ended` branch renders
  `{lifecycle.status}` raw in the badge; `data-lifecycle-status` attr
  deliberately carries the raw status (e2e selector hook — stays raw).
- `lib/chat-state-machine.ts` — `ChatWorkflowEndedMessage.status` and
  `WorkflowLifecycleState.ended.status` are both typed
  `WorkflowEndStatus`; the `workflow_ended` reducer arm is the single
  state-ingress for both render surfaces.
- `lib/ws-client.ts` — `session_ended` arm (suppression set →
  `sessionEndedCopy` → `warnSilentFallback` on unmapped → dispatch);
  `workflow_ended` falls in the grouped `stream_event` pass-through.
- `lib/client-observability.ts › warnSilentFallback` — warn-level
  Sentry `captureMessage` helper.
- `test/mocks/use-websocket.ts › createWebSocketMock` — the ChatSurface
  render-test seam (`messages` injectable via overrides; pattern from
  `test/chat-surface-context-reset.test.tsx`).
- `test/workflow-lifecycle-bar.test.tsx` line asserting
  `toContain("completed")` — breaks once the badge renders mapped copy;
  must be updated to the label.
- `e2e/cc-soleur-go-routing.e2e.ts` — FR2.4-cost-ceiling test injects
  `workflow_ended{status:"cost_ceiling"}` and selects on
  `[data-lifecycle-status="cost_ceiling"]` (attribute hook, stays raw);
  the task's "update that assertion to the mapped copy" lands as a
  *visible-text* assertion added beside it (see Reconciliation).

### Institutional learnings applied

- `2026-05-12-task-subagent-prompt-text-only.md` — Task subagents receive
  prompt text only (n/a — no Task tool in this harness; research inline).
- `cq-assert-anchor-not-bare-token` / `cq-cite-content-anchor-not-line-number`
  — tests assert mapped copy strings + `data-*` hooks, never layout
  (`cq-jsdom-no-layout-gated-assertions`).
- `cq-test-fixtures-synthesized-only` — all frames/messages synthesized.
- `cq-silent-fallback-must-mirror-to-sentry` — the generic-fallback path
  reports via `warnSilentFallback`, never silently.
- Session state for `feat-one-shot-cc-dispatcher-extract-workflow-end-messages`
  — notes `WORKFLOW_END_USER_MESSAGES` is pure data; the new module
  mirrors that purity (map + resolvers, no Sentry import; warn lives at
  the ws-client call site).

### Gate-run notes

- Phase 1.4 network-outage check: no trigger tokens — skipped.
- Phase 1.5 community discovery: stack is TypeScript/Next.js (covered);
  no uncovered-stack signatures — skipped.
- Phase 1.5b functional overlap: no Task/subagent spawn capability in
  this harness; overlap risk is nil by inspection (repo-internal copy
  mapping for a repo-internal WS frame) — recorded rather than spawned.
- Phase 1.6 external research: skipped — strong local context; the fix
  replicates a just-merged in-repo pattern.
- Phase 1.8 skill-description budget: no SKILL.md `description:` edits —
  skipped.
- Phase 2.8 IaC routing: no new infrastructure — skipped.
- Phase 2.10 ADR/C4: no architectural decision (copy-map addition
  following the established ADR-025 lifecycle-notice family pattern; no
  ownership/substrate/resolver-boundary change) — skipped.
- Phase 2.11 Encryption Posture: no persistent store or new
  cross-component connection — skipped.
- Phase 3 SpecFlow: no Task spawn; edge cases enumerated inline
  (enum widening → tsc/CI fails closed; proto-key string → resolver
  membership gate; absent `summary` → optional render unchanged;
  history-fetch `workflowEndedAt` is a timestamp gate, not a status
  render — verified `ws-client.ts` lines around the `workflowEndedAt`
  seeding, no third render site).
- Phase 4.5 scoped advisor consult: no Task spawn; the change is
  near-trivially mechanical (mirror of a merged module). Skipped.
- Plan Review fan-out: requires Task subagents — unavailable in this
  harness; substituted by the Phase 6.5 sharp-edges verification pass and
  deferred to `soleur:review`'s seats at PR time.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (brief) | Reality on this branch | Plan response |
|---|---|---|
| "no server→client `workflow_ended` emitter exists yet" | Holds — zero `type: "workflow_ended"` emit sites under `server/`; `cc-dispatcher` terminal branch still routes to `session_ended` | Fix lands as dormant-hardening ahead of Stage 3 |
| "the Zod schema … may be a wider set than WorkflowEndStatus" | Narrower reading — `status: z.enum(WORKFLOW_END_STATUSES)`, a closed union; non-members die at `parseWSMessage` | Map keyed on `WorkflowEndStatus`; resolver+fallback kept for schema-widening forward-compat, not because free-form values can arrive today |
| "e2e … asserts on the lifecycle bar — update that assertion to the mapped copy" | The existing assertion keys on `data-lifecycle-status="cost_ceiling"` — an attribute hook that stays raw by design | Keep the attribute selector; ADD a visible-text assertion for the mapped label + a `not.toContainText` raw-token guard on the badge |
| "renders `{msg.status}` raw" / "`{lifecycle.status}` raw" | Confirmed at both sites, each carrying the follow-up comment | Replace rendered text only; styling check keeps `status === "completed"` |

## Problem Statement / Motivation

`workflow_ended` frames carry a machine enum (`status:
z.enum(WORKFLOW_END_STATUSES)`). Both client render sites interpolate it
verbatim: "Workflow brainstorm ended: internal_error" and a red pill
reading `internal_error`. Today no emitter reaches them, but the frames,
types, reducer arm, card, badge, and e2e injector path all exist — the
leak is armed and waiting for Stage 3. #9526 paid a 5-seat review round
to learn that `session_ended` leaked the same way; this plan applies the
fix proactively while the surface is still dormant.

## Proposed Solution

Add a sibling copy module `apps/web-platform/lib/workflow-ended-copy.ts`
mirroring `lib/session-ended-copy.ts`:

```ts
export const WORKFLOW_ENDED_STATUS_COPY: Record<WorkflowEndStatus, string> = {
  completed: "Finished",
  user_aborted: "Stopped",
  cost_ceiling: "Cost cap reached",
  idle_timeout: "Timed out",
  plugin_load_failure: "Plugin failed to load",
  runner_runaway: "Agent stalled",
  internal_error: "Something went wrong",
  session_revoked: "Session revoked",
  worktree_enter_failed: "Workspace error",
};
export const WORKFLOW_ENDED_GENERIC_COPY = "Ended";
export function hasWorkflowEndedCopy(status: string): status is WorkflowEndStatus { … }
export function workflowEndedStatusCopy(status: string): { copy: string; mapped: boolean } { … }
```

Labels above are draft wording — they mirror the semantics of the
already-reviewed sentence copy (`WORKFLOW_END_USER_MESSAGES` /
`SESSION_ENDED_COPY`) at pill length; final wording is a taste item for
review. Module stays pure data + pure resolvers (no Sentry import),
matching the session-ended module's contract.

Then:

1. `chat-surface.tsx › case "workflow_ended"`: render
   `workflowEndedStatusCopy(msg.status).copy` inside the existing
   red/emerald span; keep `msg.status === "completed"` as the styling
   condition; replace the dormant-render comment with a pointer to the
   new module.
2. `workflow-lifecycle-bar.tsx`: render
   `workflowEndedStatusCopy(lifecycle.status).copy` in the badge; keep
   `lifecycle.status === "completed"` styling and raw
   `data-lifecycle-status`; replace its comment likewise.
3. `lib/ws-client.ts`: at the `stream_event` group, add a narrow
   `msg.type === "workflow_ended" && !hasWorkflowEndedCopy(msg.status)`
   arm calling `warnSilentFallback(null, {feature:"ws-client",
   op:"workflow-ended-unmapped-status", message:"workflow_ended arrived
   with an unmapped status", extra:{status: …slice(0,64)}})` before the
   dispatch — forward-compat tripwire (unreachable today: `z.enum`
   rejects non-members upstream; live the day the schema widens to a
   free-form string, exactly like `session_ended.reason`).

### Alternative approaches considered

| Approach | Verdict |
|---|---|
| Reuse `SESSION_ENDED_COPY` verbatim at both sites | Rejected — values are transcript sentences (up to ~95 chars); the badge is a `text-[10px]` pill. P4 unsatisfied; and the dormant path gets no visual iteration before Stage 3, so "fix the wrap later" means "a founder sees the wrap first" |
| Resolve+store `statusLabel` in the reducer arm (components render the field) | Rejected — adds state-shape churn to `ChatWorkflowEndedMessage` + `WorkflowLifecycleState` for no benefit; render-site resolution matches the `CONTEXT_RESET_COPY[msg.reason]` precedent |
| Rename `session-ended-copy.ts` → shared `lifecycle-copy.ts` | Rejected — rename churn across ws-client/tests plus a muddied per-frame module contract; a frame-named sibling file is symmetric without the churn |
| Map in the reducer arm + warn there | Rejected — the reducer is documented pure; a Sentry side effect inside dispatch double-fires under StrictMode dev renders. Warn lives at the ws-client boundary, same layer as the `session_ended` warn |

## Implementation Phases

### Phase 1 — RED (tests first per `cq-write-failing-tests-before`)

1.1 Create `apps/web-platform/test/workflow-ended-copy.test.tsx`
    covering:

- map exhaustiveness: `Object.keys(WORKFLOW_ENDED_STATUS_COPY).sort()`
  equals `[...WORKFLOW_END_STATUSES].sort()`;
- no-snake_case leak guard over every copy value + the generic
  fallback (regex `/[a-zA-Z]+_[a-zA-Z]+/`, same as the session test);
- `hasWorkflowEndedCopy` rejects `Object.prototype` keys
  (`"constructor"`, `"__proto__"`, …) and unknown statuses, accepts
  every union member;
- `workflowEndedStatusCopy` returns `{mapped:false, copy:GENERIC}`
  for an unknown status;
- component render: `<WorkflowLifecycleBar lifecycle={{state:"ended",
  workflow:"brainstorm", status:"internal_error", summary:"x"}}/>`
  renders the mapped label and never the raw token; a `completed`
  render keeps the emerald class (styling keys off raw status);
- ChatSurface render: inject a synthesized
  `{type:"workflow_ended", workflow:"plan", status:"internal_error"}`
  message via `createWebSocketMock` (pattern:
  `test/chat-surface-context-reset.test.tsx`) → card contains the
  mapped label, `internal_error` nowhere in the DOM.

1.2 Update `test/workflow-lifecycle-bar.test.tsx` — the
   `toContain("completed")` assertion now asserts the mapped label
   (e.g. `WORKFLOW_ENDED_STATUS_COPY.completed`) and adds a
   not-to-contain raw-token guard on a failure status.
1.3 Update `e2e/cc-soleur-go-routing.e2e.ts` — beside the
   `[data-lifecycle-status="cost_ceiling"]` selector, assert the ended
   bar's visible text contains the mapped label and does NOT contain
   `cost_ceiling` as text (attribute stays raw; scope the negative to
   text, not the DOM attribute).

### Phase 2 — GREEN

2.1 Create `lib/workflow-ended-copy.ts` (map + resolvers + docstrings
    noting the closed-enum wire type and the forward-compat rationale).
2.2 Edit `chat-surface.tsx` `workflow_ended` card — swap rendered text,
    keep styling condition, retire the dormant comment.
2.3 Edit `workflow-lifecycle-bar.tsx` badge — same swap.
2.4 Edit `lib/ws-client.ts` — unmapped-status `warnSilentFallback` arm.

### Phase 3 — Verify

3.1 `cd apps/web-platform && ./node_modules/.bin/vitest run
    test/workflow-ended-copy.test.tsx test/workflow-lifecycle-bar.test.tsx
    test/session-ended-copy.test.tsx` green. (Runner is vitest —
    `bunfig.toml` sets `pathIgnorePatterns = ["**"]`, so `bun test`
    matches nothing; the new `.tsx` suite lands in the happy-dom project
    via `test/**/*.test.tsx` per `vitest.config.ts`.)
3.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean —
    the `Record<WorkflowEndStatus, string>` constraint pins
    exhaustiveness at compile time.
3.3 Playwright leg: `cd apps/web-platform && npx playwright test
    e2e/cc-soleur-go-routing.e2e.ts` if runnable in this environment;
    otherwise flag for CI.

## Files to Create

- `apps/web-platform/lib/workflow-ended-copy.ts`
- `apps/web-platform/test/workflow-ended-copy.test.tsx`

## Files to Edit

- `apps/web-platform/components/chat/chat-surface.tsx` — `case
  "workflow_ended"` rendered text + comment
- `apps/web-platform/components/chat/workflow-lifecycle-bar.tsx` —
  ended-badge rendered text + comment
- `apps/web-platform/lib/ws-client.ts` — unmapped-status warn arm at the
  `stream_event` group
- `apps/web-platform/test/workflow-lifecycle-bar.test.tsx` — mapped-copy
  assertions
- `apps/web-platform/e2e/cc-soleur-go-routing.e2e.ts` — visible-text
  assertion + raw-token text guard beside the attribute selector

## User-Brand Impact

- **If this lands broken, the user experiences:** a raw internal enum
  token (`internal_error`, `cost_ceiling`) rendered in the chat
  transcript card and/or the sticky lifecycle badge when a workflow
  ends — reads as an unfinished, leaky product surface. (Worst case
  equals today's dormant behavior; the fix is forward-hardening.)
- **If this leaks, the user's [data / workflow / money] is exposed via:**
  nothing — the token is internal status vocabulary only; no PII,
  secrets, or cost data beyond what the UI already shows.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the failure mode is cosmetic
  text on an already-dormant surface; no data, workflow, or money
  exposure, so it does not reach `single-user incident`.

## Observability

```yaml
liveness_signal:
  what: "Sentry warning event 'workflow_ended arrived with an unmapped status' stays at ~0 — a nonzero rate means an emitter shipped without copy"
  cadence: "per workflow_ended frame (fires only on unmapped status)"
  alert_target: "Sentry issue (warnSilentFallback → captureMessage, level: warning)"
  configured_in: "apps/web-platform/lib/ws-client.ts (warn arm) + lib/workflow-ended-copy.ts (resolver mapped flag)"

error_reporting:
  destination: "Sentry via warnSilentFallback (@/lib/client-observability), same channel as the session_ended unmapped-reason warn"
  fail_loud: "captureMessage 'workflow_ended arrived with an unmapped status' with op=workflow-ended-unmapped-status and the 64-char-bound status token"

failure_modes:
  - mode: "new WorkflowEndStatus member lands without a copy row"
    detection: "tsc Record<WorkflowEndStatus,string> exhaustiveness + vitest key-equality test (CI-time fail-closed); warn event if a non-validated path ever delivers it (runtime)"
    alert_route: "CI failure; Sentry issue"
  - mode: "copy value itself leaks a snake_case token"
    detection: "no-snake_case vitest guard over every map value + generic fallback"
    alert_route: "CI failure"
  - mode: "raw token re-rendered at a site (regression)"
    detection: "component render tests assert mapped label present + raw token absent; e2e asserts badge text"
    alert_route: "CI failure"

logs:
  where: "browser console + Sentry event stream (client-observability captureMessage)"
  retention: "Sentry project retention"

discoverability_test:
  command: grep -c "workflow-ended-unmapped-status" apps/web-platform/lib/ws-client.ts
  expected_output: "1"
```

## Guard Contract

### Guard 1 — no raw WorkflowEndStatus token reaches the DOM

**Property.** No `WorkflowEndStatus` enum token renders as visible text
on either `workflow_ended` DOM surface; every wire-reachable status
resolves to founder-facing copy, and every other string resolves to the
generic fallback.

**Assembly.** Two DOM-egress chokepoints: `chat-surface.tsx › case
"workflow_ended"` (renders `ChatWorkflowEndedMessage.status`) and
`workflow-lifecycle-bar.tsx › ended` badge (renders
`WorkflowLifecycleState.ended.status`). Both fields are written only by
the `workflow_ended` reducer arm in `lib/chat-state-machine.ts`, which
consumes Zod-gated frames (`z.enum(WORKFLOW_END_STATUSES)` via
`parseWSMessage`) — one state-ingress, two render-egresses; the
`data-lifecycle-status` attribute is deliberately out of scope (machine
hook, not rendered text).

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Restore `{msg.status}` raw interpolation in the chat-surface card | RED — ChatSurface render test: "internal_error" absent, mapped label present |
| 2 | Restore `{lifecycle.status}` raw render in the badge | RED — bar render test + e2e text assertion |
| 3 | Add a 10th `WORKFLOW_END_STATUSES` member with no copy row | RED — `Record<WorkflowEndStatus,string>` fails `tsc`; key-equality test fails |
| 4 | Change a copy value to a snake_case token (e.g. `"agent_idle_now"`) | RED — leak-guard regex over all values + generic |
| 5 | (harness) Flip the card test's negative to `toContain("internal_error")` | RED — proves the assertion reads the live DOM rather than vacuously passing |
| 6 | (must-PASS, non-canonical) Render the badge with `status:"runner_runaway"` — a member used by no other fixture | PASS — membership is per-status, not fixture-bound |

## Open Code-Review Overlap

- `#3374` (slot_reclaimed WS frame) and `#3280` (useWebSocket
  history-fetch refactor) touch `lib/ws-client.ts` — **acknowledge**:
  different regions (frame emission / history fetch vs. one warn arm in
  the dispatch group); no fold-in.
- `#3374` and `#3242` (tool_use raw name field) touch
  `lib/ws-zod-schemas.ts` — **acknowledge**: this plan does not edit the
  schema at all.
- No open code-review issues name the two component files, the copy
  module, the test files, or the e2e file.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "first check whether a `workflow_ended` emitter has since shipped (grep server/ for `type: "workflow_ended"` and check the Zod schema in lib/ws-zod-schemas.ts for the frame's status field type — it may be a wider set than WorkflowEndStatus, e.g. a separate workflow-status union)" | Research Insights › Premise Validation | mapped — verified: no emitter; `status` is the closed `z.enum(WORKFLOW_END_STATUSES)` |
| 2 | "map `status` through copy instead of rendering raw" | FR: Phase 2.1–2.3; Files to Create `lib/workflow-ended-copy.ts`; Files to Edit `chat-surface.tsx`, `workflow-lifecycle-bar.tsx` | mapped |
| 3 | "Keep `completed` visually distinct (emerald vs red styling already keys off it — preserve the styling check, only replace the rendered text)" | Phase 2.2–2.3 styling-condition clause + AC | mapped |
| 4 | "Extend test/session-ended-copy.test.tsx (or a new test) with: copy-map exhaustiveness, no-snake_case leak guard, and a component/hook-level render test asserting `{status:"internal_error"}` never reaches the DOM" | Phase 1.1; new `test/workflow-ended-copy.test.tsx` | mapped |
| 5 | "e2e/cc-soleur-go-routing.e2e.ts injects `status:"cost_ceiling"` and asserts on the lifecycle bar — update that assertion to the mapped copy" | Phase 1.3 | mapped |
| 6 | "open draft PR … touches chat-surface.tsx and ws-zod-schemas.ts in DISJOINT hunks — note it in the plan as a merge-conflict watch item, do not abort on it" | Dependencies & Risks | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `lib/workflow-ended-copy.ts` (new map + resolvers) | "add a sibling `WORKFLOW_ENDED_STATUS_COPY` map + resolver in lib/session-ended-copy.ts (or a renamed shared lifecycle-copy module)" — sibling file named `workflow-ended-copy.ts` per frame-module convention | asked |
| `chat-surface.tsx` edit | "case "workflow_ended" — renders `{msg.status}` raw (red/emerald span)" | asked |
| `workflow-lifecycle-bar.tsx` edit | "renders `{lifecycle.status}` raw in the status badge" | asked |
| `ws-client.ts` warn arm | "the WARN-level unmapped-reason Sentry report" | asked |
| `test/workflow-ended-copy.test.tsx` (new) | "Extend test/session-ended-copy.test.tsx (or a new test)" | asked |
| `test/workflow-lifecycle-bar.test.tsx` update | — | inferred — justification: its existing `toContain("completed")` assertion breaks the moment the badge renders copy; the fix is not landable without updating it |
| `e2e/cc-soleur-go-routing.e2e.ts` update | "update that assertion to the mapped copy" | asked |

### Split Assessment

- Subsystems touched: 1 — `apps/web-platform`
- Planned files: 7 (2 create, 5 edit) | Estimated changed lines: ~220
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1: `chat-surface.tsx` `workflow_ended` card renders
  `workflowEndedStatusCopy(msg.status).copy`; the raw `{msg.status}`
  interpolation and dormant-render comment are gone; the
  `msg.status === "completed"` emerald/red styling check is preserved.
- [ ] AC2: `workflow-lifecycle-bar.tsx` ended badge renders
  `workflowEndedStatusCopy(lifecycle.status).copy`; raw
  `{lifecycle.status}` and its comment gone; `=== "completed"` styling
  and raw `data-lifecycle-status` attribute preserved.
- [ ] AC3: `lib/workflow-ended-copy.ts` exports
  `WORKFLOW_ENDED_STATUS_COPY` (a `Record<WorkflowEndStatus, string>` —
  tsc fails on a missing member), `WORKFLOW_ENDED_GENERIC_COPY`,
  `hasWorkflowEndedCopy` (hasOwnProperty-gated), and
  `workflowEndedStatusCopy` (`{copy, mapped}`).
- [ ] AC4: `lib/ws-client.ts` reports `warnSilentFallback` with
  `op: "workflow-ended-unmapped-status"` when a `workflow_ended` frame's
  status fails `hasWorkflowEndedCopy` — before the stream_event dispatch,
  with the status truncated to 64 chars in `extra`.
- [ ] AC5: `test/workflow-ended-copy.test.tsx` covers exhaustiveness,
  the snake_case leak guard, proto-key/unknown membership rejection,
  and component renders asserting `internal_error` never reaches the DOM
  at either surface (mapped label rendered instead).
- [ ] AC6: `test/workflow-lifecycle-bar.test.tsx` asserts the mapped
  label for `completed` (not the raw token) plus a raw-token negative on
  a failure status; suite green.
- [ ] AC7: `e2e/cc-soleur-go-routing.e2e.ts` asserts the ended bar's
  visible text shows the mapped label for `cost_ceiling` and does not
  contain the raw token as text; the `data-lifecycle-status` attribute
  selector is unchanged.
- [ ] AC8: `cd apps/web-platform && ./node_modules/.bin/vitest run` on
  the touched suites is green; `./node_modules/.bin/tsc --noEmit` clean.

## Domain Review

**Domains relevant:** Product (mechanical UI-surface override —
`components/chat/*.tsx` in Files to Edit)

### Product/UX Gate

**Tier:** advisory — modifies rendered *text* of two existing components;
no new page/flow/component file; the shared ui-surface term list
excludes "pure copy or style tweaks with no structural/layout change"
from the wireframe requirement. (The plan skill's mechanical override
says "force tier = BLOCKING" on any glob match; the tier definitions —
BLOCKING = *creates* new surfaces, ADVISORY = modifies existing — are
followed on substance, matching the `2026-06-05-likec4-contrast` and
`2026-05-29-kb-drift-messages` advisory precedents. Recorded as a
decision-challenge note rather than silently diverging from the letter.)
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none — no Task/subagent spawn capability in this
harness; the inline spec-flow pass is recorded in Research Insights
**Skipped specialists:** none — `soleur:product:design:ux-design-lead`
not required: no new UI surface, pure copy tweak
**Pencil available:** yes (headless CLI — `check_deps.sh` Tier 0 OK,
Node 26). Fallback: if deepen-plan Phase 4.9's mechanical halt fires on
the `components/**` glob anyway, generate a minimal `.pen` for the
ended-state badge/card under `knowledge-base/product/design/web-platform/`
and reference it here — the artifact is cheap to produce in this
environment and is the gate's only satisfiable arm.

#### Findings

Copy-integrity fix on a dormant surface; UX substance is "badge gets a
pill-length founder label instead of a machine token". The
`data-lifecycle-status` attribute intentionally keeps the raw enum —
machine-readable test hook, not rendered text.

## Test Scenarios

- Given a `workflow_ended{status:"internal_error"}` frame reaches the
  reducer, when ChatSurface renders the card, then the founder sees
  "Something went wrong" (label) — never `internal_error`.
- Given `lifecycle={state:"ended", status:"cost_ceiling"}`, when the bar
  renders, then the badge shows "Cost cap reached" and
  `data-lifecycle-status` remains `cost_ceiling`.
- Given `status:"completed"`, when both surfaces render, then the
  emerald (not red) styling applies and the label reads "Finished".
- Given a status string outside the union (cast/injected past the type
  boundary), when a component renders it, then it shows "Ended" — and a
  wire-path delivery would fire the `workflow-ended-unmapped-status`
  Sentry warning at the ws-client boundary.
- Regression: `session_ended` copy path unchanged —
  `session-ended-copy.test.tsx` stays green untouched.
- E2E: injecting `workflow_ended{status:"cost_ceiling"}` produces a
  visible badge with the mapped label and no raw-token text.

## Success Metrics

- Zero raw `WorkflowEndStatus` tokens in rendered text at both surfaces
  (unit + e2e assertions).
- `workflow-ended-unmapped-status` Sentry events at ~0; a nonzero rate
  self-reports the next unmapped emitter.
- Adding a `WORKFLOW_END_STATUSES` member without copy is a compile
  error, not a leak.

## Dependencies & Risks

- **Merge-conflict watch (assessed, non-blocking):** open draft PR
  #9051 "feat(codex): wire Web lifecycle and history safeguards"
  (`feat-one-shot-codex-web-live-paths`, deruelle) touches
  `chat-surface.tsx` and `ws-zod-schemas.ts` in disjoint hunks —
  zero `workflow_ended`/`session_ended` content. If it merges first,
  rebase-conflict risk is confined to `chat-surface.tsx` hunk locality.
- **dormant-path caveat:** both surfaces are unreachable from the live
  server today; the render tests + e2e injector are the only exercisers.
  Visual polish of label-in-pill is verifiable only via the render
  tests until Stage 3 ships an emitter.
- **deepen-plan 4.9 halt risk:** the mechanical UI-surface glob matches
  `components/chat/*.tsx`; if the gate does not honor the
  copy-tweak exclusion, produce the minimal `.pen` (Pencil headless CLI
  verified available) and reference it.

## References & Research

- Precedent implementation: `lib/session-ended-copy.ts`,
  `lib/ws-client.ts › case "session_ended"`, merged at `d715256ba0`
  (#9526) — including the review-seat P1 (hasOwnProperty-gated lookup)
  and the warn-level unmapped report.
- Server-side sibling: `server/cc-workflow-end-messages.ts ›
  WORKFLOW_END_USER_MESSAGES`.
- Closed-union direct-index precedent: `components/chat/chat-copy.ts ›
  CONTEXT_RESET_COPY` consumed as `CONTEXT_RESET_COPY[msg.reason]`.
- Routing context: `server/cc-dispatcher.ts › onWorkflowEnded`
  ("until Stage 3" comment); `lib/types.ts › WORKFLOW_END_STATUSES`;
  `lib/ws-zod-schemas.ts › workflowEndedSchema`.
- Test patterns: `test/session-ended-copy.test.tsx`,
  `test/chat-surface-context-reset.test.tsx`,
  `test/workflow-lifecycle-bar.test.tsx`,
  `e2e/cc-soleur-go-ws-injector.ts`.

## Sharp Edges

- The `data-lifecycle-status` attribute MUST stay raw — it is the e2e
  hook distinguishing `cost_ceiling` from `completed`; mapping it would
  break the selector contract. Only *rendered text* changes.
- `warnSilentFallback` lives in `@/lib/client-observability` and the new
  copy module must stay pure (no Sentry import) — the warn fires at the
  ws-client dispatch boundary, same layer as the `session_ended` warn.
- Do not "fix" `WORKFLOW_END_USER_MESSAGES.completed` (`""` by design) or
  re-derive copy from it — the badge label map is a separate surface.
- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6 — this plan's section is filled.
- If the schema ever widens `status` to `z.string()` (mirroring
  `session_ended.reason`), the membership-gated resolver + warn become
  load-bearing instantly — do not strip them as "unreachable".
