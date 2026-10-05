---
title: "fix: map dormant workflow_ended status renders through founder-facing copy"
date: 2026-10-05
slug: fix-workflow-ended-status-copy
branch: fix-workflow-ended-copy
type: fix
lane: cross-domain
priority: P2
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
---

# fix: map dormant workflow_ended status renders through founder-facing copy

## Enhancement Summary

**Deepened on:** 2026-10-05 (soleur:deepen-plan, sequential-fallback —
no subagent spawn surface in this harness; review passes ran inline)
**Sections enhanced:** Proposed Solution, Research Insights, Research
Reconciliation, Observability, Guard Contract, Scope Check, Acceptance
Criteria, Test Scenarios, Sharp Edges, Implementation Phases

### Key Improvements

1. **Dropped the ws-client unmapped-status warn (was FR-4).** The deepen
   verify-the-negative pass proved it unreachable: `ws-client.ts:951`
   runs `parseWSMessage` on every incoming frame, and
   `workflow_ended.status` is `z.enum(WORKFLOW_END_STATUSES)` — an
   unmapped value fails parse upstream and reports via the pre-existing
   `ws-zod-parse-failure` Sentry event (already covered by
   `test/ws-zod-schemas.test.ts` "workflow_ended with unknown status
   rejects"). A warn inside the parse-gated `stream_event` arm is dead
   code on every channel — a future non-WS channel would bypass that
   code location entirely. Deviation from the literal ask recorded in
   `specs/fix-workflow-ended-copy/decision-challenges.md`; the ask's
   *property* ("unmapped statuses self-report") is preserved by the
   upstream parse-failure report plus the render-side generic fallback.
2. **Observability section rewritten** around signals that actually
   exist post-change (compile-time Record rail + the inherited
   `ws-zod-parse-failure` coverage) instead of the dropped warn op.
3. **Scope Check / ACs / tasks.md updated in the same pass** — warn
   items removed, AC5 replaced, Guard Contract row 4 repointed from the
   dropped warn to a suite-level mutation row.

### New Considerations Discovered

- The e2e injector (`cc-soleur-go-ws-injector.ts`) sends frames over the
  real intercepted socket → they pass `parseWSMessage` too; no test
  channel can deliver an unmapped `workflow_ended.status`. Unknown-status
  behavior is only testable at the resolver level (direct calls) and at
  the schema level (already tested).
- `session_ended`'s warn is meaningful precisely because `reason` is
  free-form `z.string()`; `workflow_ended.status`'s closed enum makes
  the symmetric warn vacuous — the pattern to mirror is the *property*,
  not the mechanism.

## Overview

Two dormant render sites — the `workflow_ended` transcript card in
`chat-surface.tsx` and the outcome badge in `workflow-lifecycle-bar.tsx` —
render the raw `WorkflowEndStatus` enum token (`internal_error`,
`cost_ceiling`, ...) verbatim. No server→client `workflow_ended` emitter
exists today (cc-dispatcher routes terminal statuses to `session_ended`
until Stage 3), so the leak is dormant, but the moment a Stage-3 emitter
lands it reintroduces the exact defect fixed for `session_ended` at
d715256ba0 (#9526). This change maps `status` through founder-facing copy
at both sites, mirroring the merged session-ended-copy pattern
(membership-gated resolver, generic fallback, warn-level unmapped
report), and extends the test surface so no snake_case token can reach
the DOM.

`lane:` note: no `spec.md` exists for this branch (one-shot pipeline
entry, no brainstorm) — `cross-domain` retained per the fail-closed
default.

## Problem Statement / Motivation

`session_ended` leaked `internal_error` verbatim into the founder
transcript until #9526 mapped `reason` through `SESSION_ENDED_COPY`. The
two `workflow_ended` render sites carry the same latent defect, documented
in place at both sites with a comment pointing at this follow-up:

- `apps/web-platform/components/chat/chat-surface.tsx` › `case
  "workflow_ended"` renders `{msg.status}` raw inside a red/emerald span
  (line ~1120).
- `apps/web-platform/components/chat/workflow-lifecycle-bar.tsx` ›
  `ended` branch renders `{lifecycle.status}` raw in the status badge
  (line ~90).

The leak is dormant for the live-WS path — `grep -rn 'type:
"workflow_ended"' apps/web-platform/server/` returns zero (rc=1), and
`cc-dispatcher.ts` still routes terminal statuses to `session_ended`
"until Stage 3" (comment at cc-dispatcher.ts:4109-4116; ws-handler.ts:2904
lists `workflow_ended` among server→client-only frame types). But the
render path is NOT dead code: the e2e injector already drives it
(`cc-soleur-go-routing.e2e.ts` sends `status:"cost_ceiling"` and
`status:"completed"` frames), so any injected, replayed, or future-emitted
frame renders the raw token to a founder today — the same class the Stage
3 emitter will exercise unconditionally.

## Proposed Solution

### Design

One new sibling module plus four call-site edits, mirroring
d715256ba0's pattern 1:1:

1. **FR-1 — `apps/web-platform/lib/workflow-ended-copy.ts`** (new) — the
   `workflow_ended` counterpart of `session-ended-copy.ts`:

   - `WORKFLOW_ENDED_BADGE_COPY: Record<WorkflowEndStatus, string>` —
     terse pill labels for the lifecycle badge (exhaustive over the
     9-member union; a new status without a row is a `tsc` error).
     Proposed labels: `completed`→"Completed", `user_aborted`→"Stopped",
     `cost_ceiling`→"Cost cap reached", `idle_timeout`→"Timed out",
     `plugin_load_failure`→"Could not start", `runner_runaway`→"Stalled",
     `internal_error`→"Error", `session_revoked`→"Revoked",
     `worktree_enter_failed`→"Workspace error". (Wording is tunable at
     review; the contract is "short, honest, no internal jargon".)
   - `WORKFLOW_ENDED_BADGE_GENERIC = "Ended"` — badge fallback.
   - `hasWorkflowEndedBadge(status)` / `workflowEndedBadge(status)` —
     hasOwnProperty-gated membership test + `{copy, mapped}` resolver,
     the `isWorkflowBucket` idiom (review-seat P1 at d715256ba0: a bare
     index on a wire string resolves `Object.prototype` members).
   - `WORKFLOW_ENDED_GENERIC_COPY` — "This workflow ended. Start a new
     conversation to continue."
   - `workflowEndedCopy(status)` — thin wrapper over `sessionEndedCopy()`
     for the transcript card: mapped statuses reuse the parity-pinned
     `SESSION_ENDED_COPY` sentence verbatim (zero new sentence copy,
     existing parity test keeps guarding drift vs
     `WORKFLOW_END_USER_MESSAGES`); unmapped falls back to
     `WORKFLOW_ENDED_GENERIC_COPY` so a generic line says "workflow", not
     "session".

2. **FR-2 — `chat-surface.tsx`** — replace the `{msg.status}` render with
   `{workflowEndedCopy(msg.status).copy}`. The `msg.status ===
   "completed"` emerald/red styling check stays keyed on the raw status
   (internal logic, not rendered text). Update the dormant-leak comment
   to describe the mapping.

3. **FR-3 — `workflow-lifecycle-bar.tsx`** — replace the `{lifecycle.status}`
   badge render with `{workflowEndedBadge(lifecycle.status).copy}`.
   Keep `lifecycle.status === "completed"` styling check and the
   `data-lifecycle-status={lifecycle.status}` attribute keyed on the raw
   status — the attribute is a deliberate test hook the e2e relies on
   (e2e comment at cc-soleur-go-routing.e2e.ts:281-283: distinguish
   terminations "without coupling to copy"), not founder-facing text.

4. **FR-4 — `lib/ws-client.ts`** — comment-only change in the grouped
   `stream_event` arm documenting coverage: an unmapped
   `workflow_ended.status` cannot reach this point because
   `parseWSMessage` (ws-client.ts:951) validates against
   `z.enum(WORKFLOW_END_STATUSES)` and reports shape-misses via the
   pre-existing `ws-zod-parse-failure` Sentry event — the symmetric warn
   to `session-ended-unmapped-reason` would be unreachable dead code
   (see Enhancement Summary #1). No warn is added — and the comment must
   not contain the literal token `warnSilentFallback`, because AC5
   counts it (word it around `ws-zod-parse-failure`). The `{copy, mapped}`
   resolver shape is retained anyway: `mapped` costs nothing, keeps the
   API identical to `sessionEndedCopy`, and is asserted by the
   resolver-level tests for direct-construction channels.

5. **FR-5 — Tests** — new `test/workflow-ended-copy.test.tsx` (module + render
   coverage), updates to `test/workflow-lifecycle-bar.test.tsx` (the
   `toContain("completed")` assertion becomes the mapped label
   "Completed") and `e2e/cc-soleur-go-routing.e2e.ts` FR2.4 (keep the
   `data-lifecycle-status` attribute selector; add a mapped-copy text
   assertion and a negative raw-token assertion on rendered text).

### Alternative approaches considered

| Alternative | Verdict | Why |
|---|---|---|
| Reuse `SESSION_ENDED_COPY` sentence in the badge pill | Rejected | The badge is a `rounded-full px-2 py-0.5 text-[10px]` pill with no truncation; a ~90-char sentence overflows the sticky bar row. A terse-label map buys a property the sentence map cannot (badge-appropriate copy). |
| Duplicate the sentence map as `WORKFLOW_ENDED_STATUS_COPY` | Rejected | Duplicating sentences creates a drift surface `SESSION_ENDED_COPY`'s parity test already guards; `workflowEndedCopy` delegates instead. |
| Rename `session-ended-copy.ts` to `lifecycle-copy.ts` | Rejected | Import churn for a cosmetic gain; the sibling-file layout mirrors the precedent 1:1. |
| Warn inside the resolvers | Rejected | Resolvers run at render time (React re-renders) — a warn there fires per render, and dedup state is complexity defending an unreachable state. |
| Warn inside `chat-state-machine.ts` | Rejected | The reducer is deliberately pure ("the hook layer owns timers and other side effects", module docstring). |
| Warn at the ws-client `stream_event` boundary (initial design, FR-4) | Rejected — dropped at deepen | `ws-client.ts:951` `parseWSMessage` validates every frame against `z.enum(WORKFLOW_END_STATUSES)`; an unmapped status never reaches the arm (shape-miss already reports via `ws-zod-parse-failure`). A warn inside a parse-gated arm is dead code on every channel — including future non-WS channels, which would bypass that code location entirely. |

## Research Insights

### Premise Validation (Phase 0.6)

| Cited premise | Verified | Result |
|---|---|---|
| Commit `d715256ba0` merged session-ended fix | `git show d715256ba0` | Held — `fix(web-platform): render founder copy for session_ended reasons` (#9526): `lib/session-ended-copy.ts` (80 LoC map + resolvers), `ws-client.ts` warn + render, `test/session-ended-copy.test.tsx` (177 LoC). |
| Two dormant raw-status renders | read both files | Held — `chat-surface.tsx:1120` `{msg.status}` (JSX text), `workflow-lifecycle-bar.tsx:90` `{lifecycle.status}` (JSX text). Census over `components/` confirms exactly 2 JSX-text sites (line 1042 is a `status={msg.status}` **prop** on MessageBubble — different type, not a render; `data-lifecycle-status` at :73 is an attribute). |
| No `workflow_ended` server→client emitter | `grep -rn 'type: "workflow_ended"' apps/web-platform/server/` → rc=1, zero matches | Held. cc-dispatcher.ts:4109-4116 comment still routes terminal→`session_ended` pending Stage 3; ws-handler.ts:2904 treats the frame as server→client-only. **Correction to the "dormant" framing:** the e2e injector drives the render path today, so it is dormant only for the live-WS path, not unreachable. |
| Frame `status` may be a wider union than `WorkflowEndStatus` | `ws-zod-schemas.ts:547` | **Corrected** — `status: z.enum(WORKFLOW_END_STATUSES)`, exactly `WorkflowEndStatus` (9 members, `lib/types.ts:20-54`), a **closed** enum — unlike `session_ended.reason` which is free-form `z.string()`. Reuse of `SESSION_ENDED_COPY` is sanctioned (vocabulary == `WorkflowEndStatus`); membership-gated resolvers remain for non-Zod paths (test injector, future unvalidated channels) since a closed-schema value can still arrive unvalidated. |
| e2e "asserts on the lifecycle bar — update that assertion to the mapped copy" | read e2e:253-301, 487-513 | **Corrected** — FR2.4 asserts the `data-lifecycle-status="cost_ceiling"` **attribute** (deliberately decoupled from copy per comment :281-283), not rendered text. Response: keep the attribute assertion; ADD a mapped-copy text assertion + a `not.toContainText("cost_ceiling")` leak assertion. `workflow-lifecycle-bar.test.tsx:61` `toContain("completed")` DOES need updating (case-sensitive; "Completed" ≠ "completed"). |
| Open draft PR #9051 (deruelle) touches chat-surface.tsx + ws-zod-schemas.ts disjoint | `gh pr view 9051` | Held — draft, `feat-one-shot-codex-web-live-paths`, file list adds codex lifecycle source + migrations + one chat-surface test file; no `workflow_ended`/`session_ended` content. Merge-conflict watch item, not a blocker. |
| Warn-level unmapped-reason Sentry report applies to `workflow_ended` (deepen verify-the-negative) | read ws-client.ts:915-977 + e2e injector | **Refuted as reachable.** `ws-client.ts:951` runs `parseWSMessage` on every frame; `z.enum(WORKFLOW_END_STATUSES)` drops an unmapped status upstream and reports via `ws-zod-parse-failure` (pre-existing, error-level — covered by `test/ws-zod-schemas.test.ts` "workflow_ended with unknown status rejects"). The e2e injector (`cc-soleur-go-ws-injector.ts:81-88`) sends over the real intercepted socket → also parse-gated. A `stream_event`-arm warn is dead code on every channel → dropped (design §4 becomes a comment documenting the coverage). |

### Property List (Phase 0.6b)

- P1: No `WorkflowEndStatus` token — known, unknown, or proto-key —
  reaches the DOM as rendered text at either site.
- P2: Founder-facing copy per status — sentence for the transcript card
  (parity-pinned reuse), terse label for the badge pill.
- P3: `completed` stays visually distinct — emerald vs red keyed on the
  raw status value; only rendered text changes.
- P4: An unmapped status self-reports — satisfied by the pre-existing
  `ws-zod-parse-failure` Sentry report on the wire path (`z.enum` reject
  at `parseWSMessage`) and by the generic fallback on direct-construction
  channels; no new warn is needed (a parse-gated warn is unreachable).
- P5: Copy-map exhaustiveness is compile-time enforced
  (`Record<WorkflowEndStatus, string>`) and test-pinned.

### Cut List (Phase 0.6b)

- Second sentence map duplicating `SESSION_ENDED_COPY` → P2-sentence
  already bought by delegation to `sessionEndedCopy` → cut.
- Wire/schema change (status already `z.enum(WORKFLOW_END_STATUSES)`) →
  no property → cut.
- Module rename to `lifecycle-copy.ts` → cosmetic, no property → cut.
- Suppression set for `workflow_ended` (every status renders; nothing is
  suppressed) → no property → cut.
- `data-lifecycle-status` attribute mapping → attribute is a test hook
  intentionally decoupled from copy; not founder-facing text → cut
  (stays raw by design).
- `workflow-ended-unmapped-status` warn in ws-client (initial FR-4) →
  unreachable: every frame reaching `stream_event` passed
  `parseWSMessage`'s `z.enum(WORKFLOW_END_STATUSES)`, and every member
  has a copy row by the `Record<>` rail → cut at deepen (see Enhancement
  Summary #1).

### Relevant file paths

- `apps/web-platform/lib/session-ended-copy.ts` — precedent module
  (SESSION_ENDED_COPY, hasSessionEndedCopy/sessionEndedCopy,
  SESSION_ENDED_GENERIC_COPY, SESSION_ENDED_SUPPRESSED).
- `apps/web-platform/lib/types.ts:20-54` — `WORKFLOW_END_STATUSES`
  (9 members) + `WorkflowEndStatus`; `soleur-go-runner.ts` is canonical
  via `_AssertWorkflowEndStatusMatches`.
- `apps/web-platform/lib/ws-zod-schemas.ts:544-549` — `workflow_ended`
  frame: `status: z.enum(WORKFLOW_END_STATUSES)` (closed enum).
- `apps/web-platform/lib/ws-client.ts:1290-1306` — warn + copy-resolve
  precedent (`session-ended-unmapped-reason` op, 64-char bound).
- `apps/web-platform/lib/chat-state-machine.ts:1617-1638` — pure reducer
  arm producing `ChatWorkflowEndedMessage` + `workflow.state="ended"`
  (status typed `WorkflowEndStatus` on both).
- `apps/web-platform/server/cc-workflow-end-messages.ts:28-52` —
  `WORKFLOW_END_USER_MESSAGES` parity source (sentences).
- `apps/web-platform/test/session-ended-copy.test.tsx` — test pattern to
  mirror (exhaustiveness, snake_case, proto-key, ws-client warn,
  unmapped fallback).
- `apps/web-platform/test/mocks/use-websocket.ts` +
  `test/mocks/use-team-names.ts` — existing harness for ChatSurface
  render tests (`chat-surface-context-reset.test.tsx` is the template).

### Institutional learnings

- plan-sharp-edges: an FR conditioning on a single union value must
  classify EVERY member — the `completed`-vs-rest styling is stated
  explicitly per member (design items FR-2/FR-3).
- plan-sharp-edges: absence-greps false-fail on legitimate occurrences —
  no-leak assertions scope to rendered text (`textContent` /
  `toContainText`), never `innerHTML` (`data-lifecycle-status`
  legitimately contains `cost_ceiling`).
- `cq-union-widening-grep-three-patterns` — `Record<WorkflowEndStatus,
  string>` keeps map exhaustiveness compile-time-enforced on union
  widening.
- Test-runner edge: vitest projects collect `test/**/*.test.ts` (node)
  and `test/**/*.test.tsx` (jsdom) only — the new test file lands under
  `test/` and matches. Run via `cd apps/web-platform &&
  ./node_modules/.bin/vitest run <file>`; typecheck via
  `./node_modules/.bin/tsc --noEmit` (repo root has no npm workspaces).

### Related issues/PRs

- #9526 / d715256ba0 — merged precedent (this plan's pattern source).
- #3827, #2885/#2886 — status-enum drift fix and Stage 3/4 lifecycle
  surfaces that introduced the renders.
- #4440, #5313 — `session_revoked`, `worktree_enter_failed` additions
  (the union-widening path this design is exhaustiveness-railed for).
- #9051 (draft, deruelle) — merge-conflict watch item; disjoint content
  (codex lifecycle), verified.
- #3374, #3242 — open code-review issues mentioning `ws-zod-schemas.ts`
  (other frames; we do not edit that file — informational only).

## Research Reconciliation — Spec vs. Codebase

| Spec/ask claim | Codebase reality | Plan response |
|---|---|---|
| "status field may be a wider set than WorkflowEndStatus" | `z.enum(WORKFLOW_END_STATUSES)` — identical vocabulary, closed enum | Reuse `SESSION_ENDED_COPY` via delegation for the card; new badge map keyed on the same union. |
| "update that [e2e] assertion to the mapped copy" | Assertion is on the `data-lifecycle-status` attribute, intentionally decoupled from copy | Keep attribute assertion; add text-level copy + no-leak assertions. |
| "renders ... dormant because no server→client emitter exists" | True for live-WS; e2e injector + test suite already exercise the render path | Same fix, reframed urgency: reachable today via injected/replayed frames. |
| "Extend test/session-ended-copy.test.tsx (or a new test)" | Precedent test is module-resident | New sibling `test/workflow-ended-copy.test.tsx` mirrors the precedent file. |
| "the WARN-level unmapped-reason Sentry report" as pattern element | `session_ended.reason` is `z.string()` (free-form → warn is live-reachable); `workflow_ended.status` is a closed `z.enum` gated by `parseWSMessage` before dispatch | Warn dropped — property preserved by `ws-zod-parse-failure` (upstream, error-level) + render-side generic fallback. Deviation recorded in `decision-challenges.md`. |

## Technical Considerations

- **Import boundary:** `workflow-ended-copy.ts` lives in `lib/` beside
  `session-ended-copy.ts`, imports `sessionEndedCopy` + `type
  WorkflowEndStatus` — client-safe (no `server/` imports); consumers are
  `"use client"` components and `ws-client.ts`.
- **Purity:** the reducer (`chat-state-machine.ts`) is untouched; the
  only `ws-client.ts` change is a comment documenting where the
  unknown-status coverage lives (the `z.enum` parse boundary).
- **Zod semantics:** unknown statuses are dropped at parse on the
  live-WS path — `parseWSMessage` (ws-client.ts:951) rejects a status
  outside `z.enum(WORKFLOW_END_STATUSES)` and reports via the
  pre-existing `ws-zod-parse-failure` Sentry event (verified:
  `test/ws-zod-schemas.test.ts` "workflow_ended with unknown status
  rejects"). Every frame/test channel — live socket, e2e injector,
  MockWebSocket harness — passes through that gate, so an unmapped
  `workflow_ended.status` is unreachable in code and only constructible
  at the resolver level (direct calls / direct message construction);
  the membership-gated resolver + generic fallback covers those, and a
  warn inside the parse-gated arm would be dead code.
- **Copy provenance:** card sentences come from `SESSION_ENDED_COPY`,
  which the existing parity test pins verbatim to
  `WORKFLOW_END_USER_MESSAGES` — no new sentence copy is authored. Badge
  labels are new terse copy in the same voice family.
- **Styling contract:** `completed`→emerald, all other 8 members
  (`user_aborted`, `cost_ceiling`, `idle_timeout`,
  `plugin_load_failure`, `runner_runaway`, `internal_error`,
  `session_revoked`, `worktree_enter_failed`)→red — unchanged; keyed on
  raw `status` both before and after.

## Files to Create

- `apps/web-platform/lib/workflow-ended-copy.ts` — badge map, generic
  fallbacks, and membership-gated resolvers (`WORKFLOW_ENDED_BADGE_COPY`,
  `WORKFLOW_ENDED_BADGE_GENERIC`, `WORKFLOW_ENDED_GENERIC_COPY`,
  `hasWorkflowEndedBadge`, `workflowEndedBadge`, `workflowEndedCopy`).
- `apps/web-platform/test/workflow-ended-copy.test.tsx` — module +
  component + ws-client boundary coverage (FR-5).

## Files to Edit

- `apps/web-platform/components/chat/chat-surface.tsx` — map `msg.status`
  through `workflowEndedCopy`; keep styling check; update comment.
- `apps/web-platform/components/chat/workflow-lifecycle-bar.tsx` — map
  `lifecycle.status` through `workflowEndedBadge`; keep styling check +
  `data-lifecycle-status` attribute; update comment.
- `apps/web-platform/lib/ws-client.ts` — comment only: name
  `ws-zod-parse-failure` / the `z.enum` gate as the unknown-status
  coverage at the `stream_event` arm (no warn — unreachable; see
  Enhancement Summary #1).
- `apps/web-platform/lib/session-ended-copy.ts` — one-line docstring
  note naming the sibling module (no behavior change).
- `apps/web-platform/test/workflow-lifecycle-bar.test.tsx` — update the
  `toContain("completed")` assertion to the mapped badge label.
- `apps/web-platform/e2e/cc-soleur-go-routing.e2e.ts` — FR2.4: add
  mapped-copy + no-raw-token text assertions (attribute selector kept).

## Open Code-Review Overlap

Checked `gh issue list --label code-review --state open` bodies against
every planned path — **None** for the planned files. Informational only:
#3374 and #3242 mention `apps/web-platform/lib/ws-zod-schemas.ts`
(`slot_reclaimed`, `tool_use` frames) — that file is not in this plan's
edit list. Disposition: acknowledge — unrelated frames, no action.

## User-Brand Impact

- **If this lands broken, the user experiences:** a raw internal enum
  token (`internal_error`, `cost_ceiling`) or a wrong/missing label in
  the ended-workflow transcript card or the sticky lifecycle badge —
  cosmetic confusion on a status surface.
- **If this leaks, the user's [data / workflow / money] is exposed
  via:** nothing — the values are internal enum names and static copy;
  no user data, credentials, or money path is touched.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** display-copy change on a
  render path whose only exposure is cosmetic text; diff paths
  (`components/`, `lib/{ws-client,workflow-ended-copy,
  session-ended-copy}.ts`, `test/`, `e2e/`) match none of the preflight
  Check 6.1 sensitive-path regex branches (verified against
  `plugins/soleur/skills/preflight/SKILL.md` Step 6.1).

## Observability

No new Sentry signal is introduced (the initially-planned
`workflow-ended-unmapped-status` warn was dropped at deepen — see
Enhancement Summary #1). The change's failure surface is compile-time
and CI-gated; the one runtime signal it depends on is the pre-existing
`ws-zod-parse-failure` report.

```yaml
liveness_signal:
  what: pre-existing ws-zod-parse-failure Sentry event covers the only
    runtime path an unmapped workflow_ended.status can travel (z.enum
    reject at parseWSMessage); new-status-without-copy fails at tsc +
    vitest, both pre-merge
  cadence: per parse failure (runtime) / per build (compile-time rail)
  alert_target: Sentry web-platform project (ws-zod-parse-failure) + CI red
  configured_in: apps/web-platform/lib/ws-zod-schemas.ts (existing),
    apps/web-platform/lib/workflow-ended-copy.ts (new Record rail)
error_reporting:
  destination: Sentry web-platform via @sentry/nextjs (existing
    parse-failure report; unchanged)
  fail_loud: tsc error on Record<WorkflowEndStatus,string> when a status
    lacks a badge row; vitest red on the key-parity test
failure_modes:
  - mode: new WorkflowEndStatus variant added without a badge row
    detection: tsc error on Record<WorkflowEndStatus,string> plus
      key-parity test red
    alert_route: CI (pre-merge)
  - mode: unmapped status on the wire (schema-skew, malformed frame)
    detection: ws-zod-parse-failure (pre-existing report at the
      parseWSMessage boundary — frame is dropped, never rendered)
    alert_route: Sentry web-platform
  - mode: unmapped status via direct construction (test channel,
      future non-WS source)
    detection: resolver returns generic copy (WORKFLOW_ENDED_BADGE_GENERIC
      / WORKFLOW_ENDED_GENERIC_COPY); no token renders
    alert_route: unit-test asserted; visually bounded by design
logs:
  where: client-observability pino-free path (unchanged); Sentry
    captureMessage/captureException is the durable record
  retention: Sentry project retention
discoverability_test:
  command: grep -n workflowEndedBadge apps/web-platform/components/chat/workflow-lifecycle-bar.tsx
  expected_output: workflowEndedBadge
```

## Guard Contract

### Guard 1 — workflow_ended raw-enum DOM-leak guard

**Property.** No `WorkflowEndStatus` wire token — known member, unknown
string, or `Object.prototype` key — reaches the DOM as rendered text at
either render site; every status renders founder-facing copy or a
generic fallback.

**Assembly.** Every path that renders a workflow-end status as text:
`chat-surface.tsx` › `case "workflow_ended"` card and
`workflow-lifecycle-bar.tsx` › `ended` badge — census-verified complete
(`grep -n '^\s*{msg\.status}\s*$'` =1, `'^\s*{lifecycle\.status}\s*$'` =1;
the `status={msg.status}` MessageBubble prop and `data-lifecycle-status`
attribute are a different type/test hook, out of the property's scope).
The chokepoint both sites must flow through is the
`lib/workflow-ended-copy.ts` resolver pair; the wire-side complement is
the `z.enum` parse gate upstream (an unmapped status never reaches a
render).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Revert `chat-surface.tsx` card to `{msg.status}` raw | RED — ChatSurface render test asserts mapped copy for `internal_error` |
| 2 | Drop the `hasOwnProperty` membership gate (bare `WORKFLOW_ENDED_BADGE_COPY[status]` index) | RED — proto-key test: `"constructor"` must yield generic copy and a string, not an inherited member |
| 3 | Add a 10th member to `WORKFLOW_END_STATUSES` with no badge row (second member after compliant set) | RED — `Record<WorkflowEndStatus,string>` tsc rail + key-parity test |
| 4 | (suite) In the badge render test, flip the assertion to demand the raw token (`toContain("internal_error")` on rendered text) | RED — proves the suite asserts mapped text, not mere rendering (a suite agreeing with the leak is not coverage) |
| 5 | (must-PASS, non-canonical) `workflowEndedBadge("user_aborted")` — a mapped status that is NOT `completed` (the styling-divergent member) renders "Stopped" | PASS |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "first check whether a `workflow_ended` emitter has since shipped (grep server/ for `type: "workflow_ended"` and check the Zod schema in lib/ws-zod-schemas.ts for the frame's status field type)" | Research Insights › Premise Validation | mapped — done: no emitter; `z.enum(WORKFLOW_END_STATUSES)` |
| 2 | "map `status` through copy instead of rendering raw" | FR-1 (module), FR-2/FR-3 (two render sites) | mapped |
| 3 | "Keep `completed` visually distinct (emerald vs red styling already keys off it — preserve the styling check, only replace the rendered text)" | FR-2/FR-3 styling checks / Technical Considerations §Styling contract | mapped |
| 4 | "copy-map exhaustiveness, no-snake_case leak guard, and a component/hook-level render test asserting `{status:"internal_error"}` never reaches the DOM" | FR-5 (new test file) | mapped |
| 5 | "e2e/cc-soleur-go-routing.e2e.ts injects `status:"cost_ceiling"` and asserts on the lifecycle bar — update that assertion to the mapped copy" | FR-5 (e2e arm) — corrected per Reconciliation (attribute assertion kept; text assertions added) | mapped |
| 6 | "the review-seat P1 (hasOwnProperty-gated lookup on free-form wire strings) and the WARN-level unmapped-reason Sentry report" | FR-1 membership-gated resolvers (P1 idiom) + FR-4 coverage comment; warn → mapped to the pre-existing `ws-zod-parse-failure` coverage + render fallback — mechanism deviation recorded in `decision-challenges.md` (warn proven unreachable through the `z.enum` parse gate) | mapped |
| 7 | "note it in the plan as a merge-conflict watch item, do not abort on it" | Dependencies & Risks | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| `lib/workflow-ended-copy.ts` (new) | "add a sibling `WORKFLOW_ENDED_STATUS_COPY` map + resolver in lib/session-ended-copy.ts (or a renamed shared lifecycle-copy module)" | asked — sibling-module arm chosen |
| chat-surface.tsx card mapping | "renders `{msg.status}` raw (red/emerald span)" + "map `status` through copy" | asked |
| workflow-lifecycle-bar.tsx badge mapping | "renders `{lifecycle.status}` raw in the status badge" + "map `status` through copy" | asked |
| ws-client.ts coverage comment (was: warn) | "the WARN-level unmapped-reason Sentry report" | inferred — justification: deepen prove-out showed a warn inside the parse-gated `stream_event` arm is unreachable (`z.enum` rejects unmapped statuses upstream); the asked property ("unmapped self-reports") is satisfied by `ws-zod-parse-failure`. The comment preserves discoverability of that reasoning at the exact site a future reader would add a warn |
| `WORKFLOW_ENDED_BADGE_COPY` short labels | — | inferred — justification: the badge is a `text-[10px] rounded-full` pill with no truncation; the parity-pinned sentences (~90 chars) overflow the sticky-bar row, so badge-appropriate copy is a property the sentence map cannot satisfy |
| session-ended-copy.ts docstring line | — | inferred — justification: one line naming the sibling keeps the "single source of truth" pointer honest; no behavior change |
| `test/workflow-lifecycle-bar.test.tsx` update | "a component/hook-level render test asserting `{status:"internal_error"}` never reaches the DOM" | asked — existing assertion must move to the mapped label |
| e2e text assertions | "update that assertion to the mapped copy" | asked — attribute kept per its own decoupling comment |

### Split Assessment

- Subsystems touched: 1 — `apps/web-platform`
- Planned files: 8 | Estimated changed lines: ~350
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1: `grep -cn '^\s*{msg\.status}\s*$' apps/web-platform/components/chat/chat-surface.tsx` returns `0` AND `grep -cn '^\s*{lifecycle\.status}\s*$' apps/web-platform/components/chat/workflow-lifecycle-bar.tsx` returns `0` (both currently `1` — verified 2026-10-05).
- [ ] AC2: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits clean — including the exhaustiveness rail (`Record<WorkflowEndStatus, string>`).
- [ ] AC3: `cd apps/web-platform && ./node_modules/.bin/vitest run test/workflow-ended-copy.test.tsx` passes — exhaustiveness (badge keys == `WORKFLOW_END_STATUSES`), no-snake_case in every badge label + both generics, proto-key rejection (`constructor`/`__proto__`/... → generic + string), resolver `mapped` semantics + generic fallback on a non-member status (direct call — the only reachable unmapped path), `workflowEndedCopy` delegation to `SESSION_ENDED_COPY` for a mapped status, ChatSurface card render with `status:"internal_error"` shows copy not the token, `WorkflowLifecycleBar` render with `status:"internal_error"` shows the badge label not the token.
- [ ] AC4: `./node_modules/.bin/vitest run test/session-ended-copy.test.tsx test/workflow-lifecycle-bar.test.tsx test/chat-state-machine.test.ts test/cc-soleur-go-end-to-end-render.test.tsx` passes — no regression on the touched suites.
- [ ] AC5: No `workflow-ended-unmapped-status` warn is introduced — `grep -cn 'warnSilentFallback' apps/web-platform/lib/ws-client.ts` is unchanged from `origin/main` (the coverage comment is text-only; verified reachable-state analysis in Research Reconciliation).
- [ ] AC6: Both files still carry the raw-status styling keys — `grep -n 'status === "completed"' apps/web-platform/components/chat/chat-surface.tsx apps/web-platform/components/chat/workflow-lifecycle-bar.tsx` returns >= 2 — and `data-lifecycle-status` remains keyed on the raw `lifecycle.status`.
- [ ] AC7: `e2e/cc-soleur-go-routing.e2e.ts` FR2.4 retains the `[data-lifecycle-status="cost_ceiling"]` selector AND asserts the mapped badge copy in rendered text plus `not.toContainText("cost_ceiling")` on the ended bar.
- [ ] AC8: No other render site displays a `WorkflowEndStatus` token: `git grep -n '{lifecycle.status}\|{msg.status}' -- 'apps/web-platform/components/**/*.tsx'` shows only non-text-prop/attribute uses.

## Domain Review

**Domains relevant:** Marketing, Product (mechanical UI-surface match)

### Marketing

**Status:** reviewed (orchestrator-assessed — sequential fallback; no
independent leader ran)
**Assessment:** the diff authors ~9 terse badge labels — founder-facing
copy, so the domain is semantically relevant (content/messaging), but
the labels are status indicators in the same voice family as the already
approved `WORKFLOW_END_USER_MESSAGES`/`SESSION_ENDED_COPY` sentences
(parity-pinned). Label wording is flagged for review-panel taste review;
no brand-guide deviation identified.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (pipeline; `Reviewed-Coverage:
sequential-fallback` — no subagent spawn surface in this harness)
**Skipped specialists:** none — `soleur:product:design:ux-design-lead`
not required at ADVISORY tier; the shared UI-surface term list excludes
"pure copy or style tweaks with no structural/layout change", which is
the whole diff (no new interactive surface, no new `.tsx` component —
wireframe not *required* at this tier; one exists anyway, below)
**Pencil available:** yes (headless CLI). Wireframe artifact committed:
`knowledge-base/product/design/chat/workflow-ended-copy-states.pen` —
ended bar in both styling arms (emerald `Finished` vs red `Cost cap
reached` badge) and the transcript card rendering mapped copy.
Satisfies deepen-plan Phase 4.9's committed-`.pen` probe under either
reading of the copy-tweak exclusion.

#### Findings

The mechanical UI-surface glob matched `components/**/*.tsx` in Files
to Edit, so Product relevance is forced — honestly recorded. Under the
three-tier rubric the change modifies existing components without adding
interactive surfaces → ADVISORY, auto-accepted in pipeline context per
the gate's own headless arm. The `wg-ui-feature-requires-pen-wireframe`
block does not fire: the shared term list's exclusion clause classifies
this as not-a-UI-surface change.

## Test Scenarios

- Given a `workflow_ended{status:"internal_error"}` message in the chat
  state, when ChatSurface renders the card, then the DOM contains
  `SESSION_ENDED_COPY.internal_error` ("Something went wrong on our
  side. Try sending the message again.") and NOT the token
  `internal_error` (rendered text scope).
- Given `lifecycle={state:"ended", status:"internal_error"}`, when
  WorkflowLifecycleBar renders, then the badge shows
  `WORKFLOW_ENDED_BADGE_COPY.internal_error` and
  `container.textContent` does NOT contain `internal_error`.
- Given `lifecycle={state:"ended", status:"completed"}`, when the badge
  renders, then it shows "Completed" AND keeps the emerald classes
  (`bg-emerald-900/40 text-emerald-300`); any other status keeps the
  red classes.
- Given a `workflow_ended` frame with a status outside
  `WORKFLOW_END_STATUSES`, when it arrives over ANY frame channel
  (live socket, e2e injector, MockWebSocket), then `parseWSMessage`
  drops it and reports `ws-zod-parse-failure` — no render site ever
  sees it (pre-existing coverage at `test/ws-zod-schemas.test.ts`
  "workflow_ended with unknown status rejects"; no new test needed).
- Given `workflowEndedBadge("brand_new_status")` / `workflowEndedCopy`
  called directly with a non-member (the only reachable unmapped
  path), then both return generic copy with `mapped:false`.
- Given `status:"constructor"` (proto-key), when the resolvers run, then
  both return the generic copy with `mapped:false` — no inherited-member
  resolution, `typeof copy === "string"`.
- Given a new `WorkflowEndStatus` variant added to
  `WORKFLOW_END_STATUSES` without a badge row, when `tsc --noEmit` runs,
  then it fails on the `Record<WorkflowEndStatus, string>` rail.
- **Vitest:** `cd apps/web-platform && ./node_modules/.bin/vitest run
  test/workflow-ended-copy.test.tsx` expects all-green.
- **E2E (existing suite, updated assertion):** FR2.4 in
  `cc-soleur-go-routing.e2e.ts` — `data-lifecycle-status="cost_ceiling"`
  bar visible AND `toContainText` the mapped label AND
  `not.toContainText("cost_ceiling")` on rendered text.

## Success Metrics

- Zero `{…status}` JSX-text renders of `WorkflowEndStatus` remain
  (grep-verified census, AC1/AC8).
- No dead-code warn is introduced at the parse-gated boundary; unknown
  statuses keep reporting via `ws-zod-parse-failure` (AC5).
- Every new `WorkflowEndStatus` variant fails `tsc` until it has copy
  (compile-time rail, Guard Contract row 3).

## Dependencies & Risks

- **Merge-conflict watch:** open draft PR #9051
  (`feat-one-shot-codex-web-live-paths`, deruelle) edits
  `chat-surface.tsx` and `ws-zod-schemas.ts` in disjoint content (codex
  lifecycle + history transfer). Verified no `workflow_ended` /
  `session_ended` overlap. If it merges first, rebase and re-run AC1/AC8
  census greps. Do not abort on it.
- **Stage-3 emitter timing:** the fix is forward-compat — when a real
  `workflow_ended` emitter ships, copy is already in place; statuses
  added later still fail `tsc` until mapped.
- **Copy-vocabulary skew:** if Stage 3 emits a `workflow_ended.status`
  outside `WorkflowEndStatus`, the Zod enum rejects it upstream at
  `parseWSMessage` (`ws-zod-parse-failure` report — verified coverage);
  a status added to the union without copy fails `tsc` on the Record
  rail. Residual surface is direct-construction channels only, covered
  by the generic fallback.
- **Label wording:** badge labels are taste-class copy; review panel may
  tune wording (mechanical contract: terse, honest, no snake_case).

## Sharp Edges

- The "assert no raw token in the DOM" test MUST scope to rendered text
  (`container.textContent` / Playwright `toContainText`), never
  `innerHTML`/`outerHTML` — `data-lifecycle-status="cost_ceiling"`
  legitimately keeps the raw token as a test hook and a naive sweep
  false-fails (sharp-edge: absence-grep on a surface with legitimate
  occurrences).
- `workflow-lifecycle-bar.test.tsx:61` currently asserts
  `toContain("completed")` — case-sensitive, breaks on the mapped
  "Completed"; update it in the same diff (a hidden third consumer).
- The `status={msg.status}` prop at chat-surface.tsx:1042 is a
  MessageBubble prop (different status type) — do NOT map it; AC1's
  anchored grep (`^\s*{msg\.status}\s*$`) already excludes it.
- The reducer stays pure: no warn/copy-resolution inside
  `chat-state-machine.ts`.
- **Do not reintroduce a ws-client warn for unmapped statuses** — it is
  provably unreachable (every frame path passes `parseWSMessage`'s
  `z.enum`; even a future non-WS channel would bypass the ws-client arm
  entirely). The coverage comment in `ws-client.ts` names where the
  signal lives (`ws-zod-parse-failure`). A warn that cannot fire reads
  as coverage it is not.
- New test file must land under `apps/web-platform/test/` — vitest
  projects only collect `test/**/*.test.ts(x)` (verified
  `vitest.config.ts` include globs).

## References & Research

- Precedent: commit d715256ba0 / PR #9526 — `lib/session-ended-copy.ts`,
  `ws-client.ts:1290-1306`, `test/session-ended-copy.test.tsx`.
- Status vocabulary: `lib/types.ts:20-54` (`WORKFLOW_END_STATUSES`,
  canonical twin `soleur-go-runner.ts` via
  `_AssertWorkflowEndStatusMatches`); schema `lib/ws-zod-schemas.ts:544-549`.
- Sentence parity source: `server/cc-workflow-end-messages.ts:28-52`.
- Render sites: `components/chat/chat-surface.tsx:1097-1128`,
  `components/chat/workflow-lifecycle-bar.tsx:69-107`.
- Label-divergence precedent: `components/chat/conversations-rail.tsx:27-53`
  (`RAIL_STATUS_LABEL` intentionally diverges from ops `STATUS_LABELS`).
- ChatSurface test harness: `test/chat-surface-context-reset.test.tsx`,
  `test/mocks/use-websocket.ts`, `test/mocks/use-team-names.ts`.
- Parse-gate coverage (deepen finding): `lib/ws-client.ts:939-977`
  (`parseWSMessage` gate), `e2e/cc-soleur-go-ws-injector.ts:76-88`
  (injector rides the real intercepted socket → also parse-gated),
  `test/ws-zod-schemas.test.ts` "workflow_ended with unknown status
  rejects".

## Implementation Phases

1. **Phase 1 — Contract first.** Write `lib/workflow-ended-copy.ts`
   (map + generics + resolvers) and `test/workflow-ended-copy.test.tsx`
   module-level tests; write the two component render tests as RED
   first (failing tests before implementation per
   `cq-write-failing-tests-before` — the module tests define the
   contract the renders consume).
2. **Phase 2 — Render sites.** Map `msg.status` (card) and
   `lifecycle.status` (badge) through the resolvers; keep styling checks
   and `data-lifecycle-status`; update both dormant-leak comments +
   the `session-ended-copy.ts` docstring line.
3. **Phase 3 — Coverage comment.** Add the comment in `ws-client.ts`'s
   `stream_event` arm naming `ws-zod-parse-failure` + the `z.enum` gate
   as the unknown-status coverage (no warn — dead code; see
   Enhancement Summary #1).
4. **Phase 4 — Test updates.** Update `workflow-lifecycle-bar.test.tsx`
   label assertion; add the FR2.4 e2e text assertions.
5. **Phase 5 — Verify.** AC1-AC8 greps, `tsc --noEmit`, the four touched
   vitest suites; `npx markdownlint-cli2` on authored docs if any are
   committed in the PR.
