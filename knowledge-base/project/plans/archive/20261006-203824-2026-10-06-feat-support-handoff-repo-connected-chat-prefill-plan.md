---
title: "feat: carry repoConnected on the support_handoff frame and wire the command-palette ?q= prefill consumer"
date: 2026-10-06
slug: support-handoff-repo-connected-chat-prefill
branch: feat-one-shot-9556-9557-handoff-prefill
issue: 9556
closes: [9556, 9557]
type: feat
priority: p3-low
domain: product
brand_survival_threshold: none
lane: cross-domain
---

# feat: carry repoConnected on the support_handoff frame and wire the command-palette ?q= prefill consumer

## Enhancement Summary

**Deepened on:** 2026-10-06
**Sections enhanced:** Files to Edit (test-blast-radius), FR-6 (empty-string guard), Dependencies & Risks (precedent-diff + post-connect gap), Technical Considerations (path fix + assertion census)
**Research agents used:** none — sequential-fallback (this harness has no Task/subagent spawn surface); all deepen-plan gates (4.4–4.12) and quality checks run inline with live greps
**Halt gates:** 4.6 User-Brand PASS (sensitive paths + `threshold: none, reason:` scope-out) · 4.7 Observability PASS (5 fields, `grep` verb, literal `expected_output`, no shell-active tokens) · 4.8 PAT PASS · 4.9 UI-wireframe PASS (committed `.pen` referenced) · 4.10 Encryption SKIP (no new store/connection) · 4.11 Guard Contract SKIP (no guard deliverable) · 4.12 Scope Check PASS (1 unfenced section, 3 subsections, 0 unmapped rows) · 4.5 network-outage SKIP · 4.55 downtime SKIP
**Deepen corrections applied:** retired rule-id citations re-pointed to `constitution.md` §Testing; `hooks/use-support-chat.ts` corrected to `components/support/use-support-chat.ts`; AC3 count fixed (import+call = 2, call-site = 1); 13-assertion test blast radius recorded; `prefill` non-empty guard added

### Key Improvements

1. FR-6 sharpened: `prefill` applies only when `prefill` is non-empty AND `value` is empty — the `?q=` (empty-param) edge becomes a no-op, not a latch burn.
2. `test/support-handoff.test.ts` carries **13** `toBe("<source>")` assertions that break on the `consumeSupportEscalation` return-shape widening — the work phase rewrites them as `?.source` extraction (recorded, not discovered at RED time).
3. Precedent-diff added: all three new local patterns map to in-repo precedents (no novel shape).

## Overview

Two small deferral follow-ups from PR #9540 (#9539, ADR-113 addendum) land in one PR. First, the `support_handoff` SSE frame grows a `repoConnected` boolean — sourced from the `repoUrl` resolution that `dispatchSoleurGo` already performs — so the support chat's "Ask an agent" affordance can render honest copy for repo-less users instead of linking them into the Command Center's repo-required surface. Second, the command palette's `?q=` URL parameter, produced for `/dashboard/chat/new` but read by nothing, gains a consumer that seeds the chat composer as a prefill (never an auto-send).

## Research Insights

### Premise Validation (Phase 0.6)

- Issues #9556 (`enhancement: carry repoConnected on the support_handoff frame for honest repo-less copy`) and #9557 (`fix: command-palette '?q=' prefill param has no consumer under components/chat/`) both verified **OPEN** via `gh issue view` — they are the two tracked deferrals from PR #9540's `wg-when-deferring-a-capability-create-a` filings.
- PR #9570 **MERGED** 2026-10-06 (`fix(support): safe-bash git-branch read-only arms + kb-search support tool path (#9555, #9559)`) — its safe-bash/kb-search semantics are live on main; this plan's diff does not touch the allowlist.
- PR #9540 **MERGED** 2026-10-05, `closingIssuesReferences` = #9539 only — citation, not collision.
- #9618 **OPEN** — `sandbox-canary-capture-gate projection_error` blocks any PR touching `apps/web-platform/server/agent-runner-sandbox-config.ts` or capture inputs. This plan's file list is verified free of it (the `ccDeps` edit lands in `cc-dispatcher.ts`; `agent-runner-sandbox-config.ts` is untouched).
- Cited artifacts all exist on this branch: `lib/support-handoff.ts` (`buildSupportHandoffMarkdown`, `SUPPORT_AGENT_SESSION_HREF="/dashboard/chat/new"`), `lib/support-sse.ts` (`SupportSseMessage` union, `reduceSupportFrame` `support_handoff` arm, `supportTerminalPrefixFrames`), `server/support-escalation.ts` (consume-on-read registry, `denySupport`), `app/api/support/route.ts` (terminal-adjacent emit inside `enqueue`), `components/command-palette/use-shortcuts.tsx` (`?q=` producer in the `openChat` effect).
- Issue #9556's claim "the flag is already resolved elsewhere in dispatch" is **verified**: `dispatchSoleurGo` resolves `repoUrl` via `getCurrentRepoUrl(args.userId, activeWorkspaceId)` inside the unconditional `Promise.all` in `server/cc-dispatcher.ts` (the `getCurrentRepoUrl` call site — runs for the support persona too, because `mode.runRepoLifecycle=false` only skips the *lifecycle* gates, not the resolution). Reusing it costs zero extra DB reads.
- Issue #9557's "no consumer" claim is **verified**: the only `searchParams.get("q")` call in the repo is the KB-search API route (`app/api/kb/search/route.ts`); nothing under `components/` reads `?q=`. The producer at `use-shortcuts.tsx` (`/dashboard/chat/new?q=${encodeURIComponent(effect.query)}`) is asserted by `test/command-palette.test.tsx` ("Ask an agent about <q>" fallback).
- The deferral rationale recorded in the archived PR-#9540 plan ("extra DB read per deny") is **stale**: the route need not re-resolve anything — `denySupport`'s call context (`createCanUseTool` in `server/permission-callback.ts`) receives `deps: CanUseToolDeps`, and `ccDeps` is constructed inside `dispatchSoleurGo` after `repoUrl` resolves, so the flag rides the existing deny→emit registry at zero marginal cost.
- `/connect-repo` route exists (`app/(auth)/connect-repo`) — the canonical connect flow (`use-reconnect.ts` redirects there); the degraded handoff copy can point at it.
- ADR-113's decision addendum documents the frame as `{task, conversationId}` — widening it with `repoConnected` is an extension of a recorded mechanism, so an ADR-113 addendum line-edit is an in-scope deliverable (not a new ADR).

### Property List (Phase 0.6b)

- P1: A repo-less support user sees handoff copy that matches their reality — "connect a repository first" — instead of a link that dead-ends on the Command Center's repo gate.
- P2: Repo-connected state reaches the emit site with **zero** additional DB reads (reuse the dispatch-time `repoUrl` resolution).
- P3: The `?q=` prefill param produced by the command palette lands in the chat composer — seeded as draft text, never auto-sent (auto-send is `?msg=`'s contract).

### Cut List (Phase 0.6b)

- Mechanism "client-side repo lookup in the support panel" (add `useActiveRepo` to `components/support/*`) — cut: buys P1, but `components/support/use-support-chat.ts` carries no repo state today, the flag would be SWR-timing-racey against the emit, and the issue's mechanism (P2) is strictly cheaper.
- Mechanism "route-side `getCurrentRepoUrl` at emit" — cut: buys P1 but re-resolves the workspace claim a second time (the extra read #9556 was deferred over) and would need async plumbing inside the synchronous `enqueue` closure.
- Mechanism "switch the handoff deep link from `?msg=` to `?q=`" — cut: not asked by either issue; changes #9539's shipped auto-send behavior. Recorded as an available variant, not this PR.

### Local Research (Phase 1 — fan-out run inline; this harness has no subagent/Task capability)

- `server/permission-callback.ts` — `createCanUseTool(ctx)` has **exactly 8** `denySupport(` call sites (Skill, both Bash arms, write-file, outside-workspace, Agent, platform, deny-by-default). A single closure-local `deny(...)` wrapper that injects `repoConnected: deps.repoConnected` keeps present and future sites correct — mirrors `denySupport`'s own contract ("every present and future support deny path gets record + telemetry for free").
- `server/support-escalation.ts` — `Map<string, SupportEscalationSource>` becomes `Map<string, { source; repoConnected?: boolean }>`; `consumeSupportEscalation` return type widens (callers: `route.ts` + tests only).
- `server/cc-dispatcher.ts` — `ccDeps: CanUseToolDeps` gains `repoConnected: repoUrl !== null`; `repoUrl` is in scope (same function body as the `Promise.all` destructure).
- `app/api/support/route.ts` — `enqueue` builds the frame from the consumed record; `{ type:"support_handoff", task, conversationId, repoConnected }`. Log lines key on `consumed.source`.
- `lib/support-sse.ts` — union member widens (`repoConnected?: boolean` — optional keeps additive-safety across the JSON parse boundary, per `hr-type-widening-cross-consumer-grep`); `reduceSupportFrame` passes it to the copy builder. `lib/types.ts`/`ws-zod-schemas.ts` stay untouched (the `_SchemaCovers` pin is why the frame is support-local).
- `lib/support-handoff.ts` — `buildSupportHandoffMarkdown(task, repoConnected?)` tri-state: `true` → clean "Ask an agent to do this →" link; `false` → "Connect a repository to hand this task to an agent →" pointing at `/connect-repo`; `undefined` → today's "(needs a connected repo)" copy (backward-compatible for frames emitted before resolution or by dep-less paths).
- `components/chat/chat-surface.tsx` — already owns `useSearchParams` reads (`leader`, `msg`, `fr`) and the `router.replace(pathname)` strip convention (first-run effect); `qParam` joins the same pattern. The chat page is a **dynamic segment** — the `useSearchParams`/Suspense build-gate hazard in `2026-06-18-usesearchparams-on-static-route-needs-suspense-and-next-build-gate.md` does not apply.
- `components/chat/chat-input.tsx` — owns `value`/`setValue`, `textareaRef`, `draftKey`/sessionStorage rehydrate; gains a `prefill?: string` prop applied once via a latched effect (robust to late-populating `useSearchParams`, never clobbers a hydrated draft).
- Institutional learnings applied: `2026-07-22-…-type-widening-must-sweep-injected-dep-signatures.md` (sweep `CanUseToolDeps` constructions: cc-dispatcher + legacy `agent-runner.ts` + test mocks — the new field is optional so the legacy site needs no edit), `cq-union-widening-grep-three-patterns` (additive optional field, no new union member — if-ladder consumers unaffected), constitution.md §Testing (prefill tests assert the `textarea` value, not jsdom layout), constitution.md §Testing (tests pin exact copy per `repoConnected` state).

### External Research (Phase 1.6)

- Skipped — both issues are surgical extensions of mechanisms designed and documented in-repo (PR #9540, ADR-113 addendum, archived sibling plan). No new stack or external API.

### Related Issues / PRs

- #9539 / PR #9540 (parent, merged) · #9555, #9559 / PR #9570 (sibling deferrals, merged) · #9558 (known residual: GH-token mint/askpass/egress persona-gate — out of scope) · #9618 (sandbox-canary gate blocker — hard constraint honored) · code-review #3243, #3242 (open scope-outs citing `cc-dispatcher.ts` — see `## Open Code-Review Overlap`).

## Problem Statement / Motivation

Two tracked deferrals from PR #9540 (#9539, ADR-113 addendum) leave honest-behavior gaps on the support and chat surfaces:

1. **`support_handoff` copy lies to repo-less users (#9556).** The deny→handoff affordance renders "Ask an agent to do this (needs a connected repo) →" to *every* user. Repo-less users click through to `/dashboard/chat/new` and land on the repo-gate — a relocated dead-end. The server already knows the answer: `dispatchSoleurGo` resolves `repoUrl` for every dispatch (support persona included). The frame simply doesn't carry it.
2. **`?q=` is a dangling producer (#9557).** The command palette's "Ask an agent about <q>" fallback navigates to `/dashboard/chat/new?q=<encoded>` and nothing reads the param — the typed query silently evaporates. The composer needs a prefill consumer that seeds the draft *without* auto-sending (auto-send is `?msg=`'s shipped contract, and stays).

## Proposed Solution

### #9556 — `repoConnected` on the `support_handoff` frame

- **FR-1** — `server/support-escalation.ts` › registry values become `{ source: SupportEscalationSource; repoConnected?: boolean }`; `recordSupportEscalation(conversationId, source, repoConnected?)` stores it; `consumeSupportEscalation` returns `SupportEscalationRecord | null`; `denySupport(opts)` accepts `repoConnected?: boolean` and forwards it.
- **FR-2** — `server/permission-callback.ts` › `CanUseToolDeps` gains `repoConnected?: boolean`; inside `createCanUseTool`, a closure-local `deny(opts)` wrapper calls `denySupport({ ...opts, repoConnected: deps.repoConnected })` and all **8** existing `denySupport(` call sites are renamed to `deny(` — one injection point, so every present and future support deny path carries the flag (the helper's own contract).
- **FR-3** — `server/cc-dispatcher.ts` › `ccDeps` gains `repoConnected: repoUrl !== null` — the `repoUrl` already resolved in the unconditional `Promise.all` earlier in the same function body. Zero new reads; `repoStatus` deliberately does not participate (`cloning`/`error` still means a repo *is* connected — the destination surface explains its own state).
- **FR-4** — `app/api/support/route.ts` › `enqueue` consumes the record, emits `{ type:"support_handoff", task, conversationId, repoConnected }`, and logs `support-handoff-emitted` with `repoConnected` added to the join fields. `lib/support-sse.ts` › the union member widens to `repoConnected?: boolean` (optional — additive-safe across the JSON parse boundary); `reduceSupportFrame` passes `msg.repoConnected` through.
- **FR-5** — `lib/support-handoff.ts` › `buildSupportHandoffMarkdown(task, repoConnected?)` is tri-state: `false` → `[Connect a repository to hand this task to an agent →](</connect-repo>)` (new `SUPPORT_CONNECT_REPO_HREF` const; `?return_to=` is NOT added — the connect flow's own resume already handles it and the task text is preserved in the bubble); `true` → `[Ask an agent to do this →](<${SUPPORT_AGENT_SESSION_HREF}?msg=...>)` — the "(needs a connected repo)" caveat drops because the precondition is verified; `undefined` → the current copy, byte-identical (backward-compatible when the flag is absent — dep-less contexts, pre-resolution denies).

### #9557 — `?q=` prefill consumer

- **FR-6** — `components/chat/chat-input.tsx` › new optional prop `prefill?: string`. A latched effect applies it exactly once (`prefillAppliedRef`), only when `prefill` is non-empty (the `?q=` bare-param edge is a no-op, not a latch burn) AND the current `value` is empty — a hydrated `draftKey` draft is never clobbered — then focuses the textarea. Latch+effect (not the `useState` initializer) because `useSearchParams` may populate after mount and the initializer would miss it.
- **FR-7** — `components/chat/chat-surface.tsx` › `const qParam = searchParams.get("q")` beside the existing `leader`/`msg`/`fr` reads; pass `prefill={variant === "full" && conversationId === "new" && !msgParam ? qParam || undefined : undefined}` to `<ChatInput>`; a latched effect strips the param via `router.replace(pathname, { scroll: false })` — the same convention as the `msg`/`fr` strip in the first-run effect.
- **FR-8** — Precedence: `?msg=` (auto-send) wins over `?q=`; `?q=` applies only on `variant === "full" && conversationId === "new"` (the only producer target); a non-empty draft wins over `?q=` (user-typed content beats navigation-carried text — the param is still consumed+stripped).

### Documentation deliverable

- **FR-9** — `knowledge-base/engineering/architecture/decisions/ADR-113-support-persona-scoped-concierge.md` › the addendum's frame description is updated to `{task, conversationId, repoConnected?}` with a one-line provenance note (recorded-at-deny, sourced from the dispatch `repoUrl` resolution) — recorded architecture must not lag the mechanism (plan Phase 2.10).

## Technical Considerations

- **Type-widening sweeps (rule-mandated).** `hr-type-widening-cross-consumer-grep`: `SupportSseMessage.support_handoff` gains an optional field crossing a `JSON.parse` boundary — consumers enumerated: `formatSupportSseFrame`, `parseSupportSseChunks`, `reduceSupportFrame`, `supportTerminalPrefixFrames` (all in `support-sse.ts`), `route.ts`, `use-support-chat.ts` under `components/support/` (reads only the derived `handoffMarkdown` — untouched). `consumeSupportEscalation` return-shape change: callers are `route.ts` and `test/support-handoff.test.ts` only (`git grep consumeSupportEscalation` census). `CanUseToolDeps` constructions: `cc-dispatcher.ts` (edited) + `agent-runner.ts` legacy runner (optional field — no edit needed; verify at work time) + test mocks (`test/support-handoff.test.ts` builds a `CanUseToolDeps` literal — may need the field in mock factories). `denySupport` call sites: the 8 in `permission-callback.ts` plus test-call sites — census pinned by AC.
- **`repoUrl` is in scope at the `ccDeps` construction site** — both live in `dispatchSoleurGo`'s function body (the `Promise.all` destructure precedes it). Verified by reading both sites.
- **Sandbox-canary constraint (#9618).** The diff MUST NOT touch `server/agent-runner-sandbox-config.ts` or any sandbox-capture input. Nothing in this plan's file list does — an explicit AC greps the diff for it.
- **`useSearchParams` precedent.** `chat-surface.tsx` already reads `searchParams` unconditionally; the `[conversationId]` segment is dynamic, so the static-route Suspense build-gate hazard (`2026-06-18-usesearchparams-on-static-route-needs-suspense-and-next-build-gate.md`) does not apply. No new `useSearchParams` call site is added — the existing one gains a `.get("q")` read.
- **Deny-copy surfaces unchanged.** `SUPPORT_AGENT_SESSION_HINT` and the `denySupport` `message:` strings are model-relayed prose about the *destination*, not the affordance — they stay byte-identical (the support persona cannot see `repoConnected` in prompt space and telling the model "user has no repo" would leak nothing useful).
- **`components/support/use-support-chat.ts` needs no change** — it consumes `state.handoffMarkdown`, which `buildSupportHandoffMarkdown` still produces.
- **jsdom test note.** Prefill assertions pin `textarea.value` / `data-*` hooks, never layout (constitution.md §Testing — jsdom returns 0 for layout values). `useSearchParams` is mocked via the established `vi.mock("next/navigation")` + `mockSearchParams` pattern (`chat-surface-first-run-attachments.test.tsx`).
- **Compliance (GDPR gate — run inline; no Task surface in this harness).** `app/api/support/route.ts` matches the regulated-surface regex, so the gate fires: `repoConnected` is a boolean about the *requesting user's own workspace*, already resolved server-side for the dispatch and already rendered to the same user elsewhere (workspace settings, composer repo-state); it crosses to the user over their own authenticated SSE stream. `?q=` text is user-authored. No new data category, no new processor, no cross-controller movement → **no findings**, no `compliance-posture.md` entry.
- **Test blast radius (deepen 4.45 census).** `test/support-handoff.test.ts` carries **13** `expect(consumeSupportEscalation(...)).toBe("<source>")` assertions (`:121,:137,:148,:158,:171,:187,:203,:210,:275,:297,:306,:314,:320`) that break on the return-shape widening — rewrite each to `expect(consumeSupportEscalation(...)?.source).toBe("<source>")` (or `toMatchObject({ source: ... })`); `route.ts` consumes the record as `consumed` with `consumed.source` keying the `source:` log field at its three call sites (emit-failed warn, emitted info) and `consumed.repoConnected` feeding the frame literal at `route.ts:187`. `denySupport` has **zero** test-call sites — the wrapper rename is contained to `permission-callback.ts`.

## Non-Goals

- Switching the handoff deep link from `?msg=` (auto-send) to `?q=` (prefill) — an available variant now that `?q=` is wired, but it changes #9539's shipped behavior and needs product sign-off.
- Any change to `use-shortcuts.tsx`, `command-palette.tsx`, or the `?q=` producer.
- `repoStatus`-graded handoff copy (`cloning`/`error` tri-state) — `Boolean(repoUrl)` is the issue's contract; the destination already explains its own setup state.
- `lib/types.ts` / `ws-zod-schemas.ts` changes — the frame stays support-local by design (the `_SchemaCovers` pin).
- Anything under `server/agent-runner-sandbox-config.ts` or the sandbox-canary capture inputs (#9618 hard constraint).
- `components/support/use-support-chat.ts` / `components/support/*.tsx` changes.
- #9558 (GH-token mint/askpass/egress persona-gate) — separate tracked residual.

## Files to Create

- `knowledge-base/product/design/support/support-handoff-repo-connected-prefill.pen` — wireframe covering the three handoff-copy states and the `?q=` prefilled composer (committed at plan time per `wg-ui-feature-requires-pen-wireframe`).
- `apps/web-platform/test/chat-prefill.test.tsx` — `?q=` consumer coverage (seed, strip, precedence, draft preservation, no auto-send).

## Files to Edit

- `apps/web-platform/lib/support-handoff.ts` — `buildSupportHandoffMarkdown(task, repoConnected?)` tri-state + `SUPPORT_CONNECT_REPO_HREF`.
- `apps/web-platform/lib/support-sse.ts` — `support_handoff` member gains `repoConnected?: boolean`; reducer passes it.
- `apps/web-platform/server/support-escalation.ts` — record shape `{source, repoConnected?}`; `recordSupportEscalation`/`consumeSupportEscalation`/`denySupport` signatures.
- `apps/web-platform/server/permission-callback.ts` — `CanUseToolDeps.repoConnected?: boolean`; `deny()` wrapper; 8 call-site renames.
- `apps/web-platform/server/cc-dispatcher.ts` — `ccDeps.repoConnected: repoUrl !== null` (one line + comment).
- `apps/web-platform/app/api/support/route.ts` — consume record → frame field + `repoConnected` in the `support-handoff-emitted` log.
- `apps/web-platform/components/chat/chat-input.tsx` — `prefill?: string` prop + latched apply effect.
- `apps/web-platform/components/chat/chat-surface.tsx` — `qParam` read + `prefill` prop wiring + strip effect.
- `apps/web-platform/test/support-handoff.test.ts` — registry shape, deny injection, route emit field coverage.
- `apps/web-platform/test/support-sse.test.ts` — reducer copy-variant coverage.
- `knowledge-base/engineering/architecture/decisions/ADR-113-support-persona-scoped-concierge.md` — addendum frame-shape line edit (FR-9).

## Open Code-Review Overlap

2 open scope-outs cite `cc-dispatcher.ts`; both acknowledged, neither folded in:

- `#3243: arch: decompose cc-dispatcher.ts into focused modules (Ref #3235)` — **Acknowledge.** A structural decomposition; this diff adds one property line to `ccDeps`, which survives any module split. Different concern, needs its own cycle.
- `#3242: review: tool_use WS event lacks raw name field for agent consumers (Ref #3235)` — **Acknowledge.** Unrelated payload gap on the WS surface; this diff touches the support SSE surface only.

## User-Brand Impact

- **If this lands broken, the user experiences:** today's status quo — the "(needs a connected repo)" link to a repo-gated surface (`repoConnected` absent/mis-set → `undefined`-arm copy, byte-identical to current) — or a composer that ignores `?q=` (the param silently evaporates, as today). No new failure mode beyond mis-rendered copy.
- **If this leaks, the user's data is exposed via:** `repoConnected` is a boolean about the user's own workspace sent on their own authenticated SSE stream — already derivable from their own workspace settings UI. `?q=` text is user-authored input re-delivered to its author's composer. No third-party surface, no persisted copy, no cross-user path.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** worst realistic outcome is a copy line that mis-renders or a missed prefill — no data exposure, no money path, no cross-tenant reach.
- `threshold: none, reason:` the diff touches sensitive paths (`server/permission-callback.ts`, `server/cc-dispatcher.ts`, `app/api/support/route.ts`) but only adds a deny-recorded flag and a UI prefill — it never widens what a support session can do; blast radius is a wrong copy string or a dropped affordance.

## Observability

```yaml
liveness_signal:
  what: "structured deny→emit join per support turn: `deny-support-{skill,bash,tool}` (permission-callback) paired with `support-handoff-emitted` (support route) — the emitted log now carries `repoConnected`, so the copy-variant each user saw is derivable per turn"
  cadence: "per denied support turn (event-driven)"
  alert_target: "Better Stack log query on the existing support markers"
  configured_in: "apps/web-platform/app/api/support/route.ts (`support-handoff-emitted` log site)"
error_reporting:
  destination: "Sentry web-platform via SENTRY_DSN (route-level reportSilentFallback already wraps dispatch/resolve failures)"
  fail_loud: "`support-handoff-emit-failed` warn + `support-handoff-cleared-unconsumed` info markers (existing emit-failure and orphan paths)"
failure_modes:
  - mode: "deny recorded but frame never emitted (zombie flag, dead stream)"
    detection: "`support-handoff-emit-failed` / `support-handoff-cleared-unconsumed` markers — the deny→emit join stays complete with the added `repoConnected` field"
    alert_route: "Better Stack log query (existing marker family, no new alert)"
  - mode: "`repoConnected` wrong for a user (recorded before repo state changed)"
    detection: "`support-handoff-emitted` log carries the emitted value; the frame payload is in the SSE body — the join is per-turn and timestamped"
    alert_route: "none (worst case: one user's copy is stale for one turn; destination surfaces its own state)"
logs:
  where: "web-platform pino logs → Better Stack (structured `sec: true` entries)"
  retention: "existing platform log retention (unchanged)"
discoverability_test:
  command: grep -rn repoConnected apps/web-platform/lib/support-sse.ts apps/web-platform/app/api/support/route.ts apps/web-platform/server/support-escalation.ts
  expected_output: "repoConnected"
```

## Architecture Decision (ADR/C4)

### ADR

- `ADR-113-support-persona-scoped-concierge.md` — **amend** the 2026-10-05 addendum in place (FR-9): the documented frame shape `{task, conversationId}` becomes `{task, conversationId, repoConnected?}` with provenance (recorded at deny time from the dispatch-resolved `repoUrl`, zero added reads). Not a new ADR — an extension of the same mechanism.

### C4 views

- **No C4 impact.** Enumeration performed against `model.c4`, `views.c4`, `spec.c4`: (a) external human actors — the `supportUser` actor (End User, Support Chat) is already modeled with its `supportUser -> webapp` edge; no new actor; (b) external systems/vendors — none introduced (the SSE transport and `/connect-repo` route already exist); (c) containers/data stores — the frame rides the existing `webapp`/API container boundary; no new store; (d) actor↔surface relationships — the support-bubble edge already covers "asks app-help questions"; an added frame *field* and a composer prefill do not create a relationship. Element descriptions falsified by this change: none (`supportUser`'s description stays accurate — the persona is unchanged).

### Sequencing

- The ADR addendum edit ships in this PR with the mechanism it records.

## Domain Review

**Domains relevant:** Engineering (deny/deps surface), Product (UI-surface glob match), Support (the support-chat surface itself)

### Engineering

**Status:** reviewed (assessed inline — this harness has no subagent/Task capability; domain leaders were not spawned)
**Assessment:** touches the deny→emit path only; the security chokepoint (`canUseTool`, sandbox `allowWrite`, persona discriminant) is additive-preserved — a new dep field and a wrapper that *adds* a recorded field, never widens an allow. Blast radius: a missing/wrong copy line or a dropped handoff.

### Support (CCO lens)

**Status:** reviewed (inline)
**Assessment:** a support-workflow honesty improvement — repo-less users get a connect-repo path instead of a dead-end link; the dead-end the copy currently routes to is the defect this closes.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (no subagent spawn surface in this harness; `Reviewed-Coverage: sequential-fallback`)
**Skipped specialists:** `soleur:product:design:ux-design-lead` — not required at ADVISORY tier (modifies two existing components, adds no new page/flow/interactive surface); the wireframe invariant is still satisfied — see Pencil line.
**Pencil available:** yes (headless CLI, `pencil-setup check_deps.sh` Tier 0 verified). Wireframe artifact committed at plan time: `knowledge-base/product/design/support/support-handoff-repo-connected-prefill.pen` — covers the three `repoConnected` copy states and the `?q=` prefilled composer; satisfies deepen-plan Phase 4.9's committed-`.pen` probe.

#### Findings

- The mechanical UI-surface glob matched `components/**/*.tsx` in Files to Edit, forcing Product relevance — honestly recorded. Under the three-tier rubric the change modifies existing components without adding interactive surfaces → ADVISORY (precedent: `2026-10-05-fix-workflow-ended-status-copy-plan.md`, same worktree family, same rubric).
- Copy decisions needing review-panel taste sign-off: the `repoConnected === false` copy verb ("Connect a repository to hand this task to an agent") and the dropped caveat on `true`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Adding a `repoConnected` boolean to the frame would let the copy degrade honestly ("connect a repository to hand this task to an agent") without an extra DB read per deny — the flag is already resolved elsewhere in dispatch." [issue #9556] | FR-1…FR-5 / Files to Edit (support-escalation, permission-callback, cc-dispatcher, route, support-sse, support-handoff) | mapped |
| 2 | "`use-shortcuts.tsx` (command palette) produces a `?q=` URL param intended to prefill the chat composer, but no consumer under `components/chat/` reads it — a dangling-param dead-end." [issue #9557] | FR-6…FR-8 / Files to Edit (chat-input, chat-surface) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `lib/support-sse.ts` frame field | "a `repoConnected` boolean to the frame" | asked |
| `lib/support-handoff.ts` copy variants | "let the copy degrade honestly ("connect a repository to hand this task to an agent")" | asked |
| `app/api/support/route.ts` emit | "a `repoConnected` boolean to the frame" | asked |
| `server/support-escalation.ts` record shape | "without an extra DB read per deny — the flag is already resolved elsewhere in dispatch" | asked |
| `server/permission-callback.ts` deps + wrapper | "the flag is already resolved elsewhere in dispatch" | inferred — justification: the deny→emit registry is the only channel that reaches the emit site without a second DB read; the deps injection is the plumbing the named mechanism requires |
| `server/cc-dispatcher.ts` `ccDeps` field | "the flag is already resolved elsewhere in dispatch" | asked |
| `components/chat/chat-input.tsx` `prefill` prop | "no consumer under `components/chat/` reads it" | asked |
| `components/chat/chat-surface.tsx` `?q=` wiring | "intended to prefill the chat composer" | asked |
| `test/chat-prefill.test.tsx` + test-file edits | — | inferred — justification: constitution "new modules and source files must have corresponding test files"; `cq-write-failing-tests-before` |
| ADR-113 addendum edit | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable` — recorded architecture must not lag the extended frame shape |
| `.pen` wireframe | — | inferred — justification: `wg-ui-feature-requires-pen-wireframe` / deepen-plan Phase 4.9 committed-.pen probe on a UI-surface plan |

### Split Assessment

- Subsystems touched: 1 — `apps/web-platform` (plus `knowledge-base/` artifacts)
- Planned files: 13 | Estimated changed lines: ~250
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1: `consumeSupportEscalation` returns `SupportEscalationRecord | null`; a deny recorded with `deps.repoConnected === false` produces a `support_handoff` SSE frame carrying `"repoConnected":false` before the terminal frame (route-level test in `support-handoff.test.ts`).
- [ ] AC2: `buildSupportHandoffMarkdown` pins all three copy arms exactly (constitution.md §Testing — pin exact post-state): `false` → `/connect-repo` link + connect copy; `true` → `?msg=` link without the "(needs a connected repo)" caveat; `undefined` → the current byte-identical string.
- [ ] AC3: `grep -c 'getCurrentRepoUrl(' apps/web-platform/server/cc-dispatcher.ts` stays `1` — zero added DB reads (the call-site count, distinct from the `getCurrentRepoUrl` import at `:134`; both verified at plan-write time); `ccDeps` carries `repoConnected: repoUrl !== null` (`grep -n 'repoConnected: repoUrl' apps/web-platform/server/cc-dispatcher.ts` returns ≥1).
- [ ] AC4: `grep -c 'denySupport(' apps/web-platform/server/permission-callback.ts` returns `1` (the `deny()` wrapper's own call — down from the verified pre-change `8` at `:282,:292,:493,:593,:1031,:1065,:1090,:1227`) and `grep -c 'deny(' apps/web-platform/server/permission-callback.ts` ≥ 8 — every deny site routes through the wrapper.
- [ ] AC5: `/dashboard/chat/new?q=<text>` seeds the composer `textarea.value` with the decoded text and `sendMessage` is never called; `router.replace` strips `q` (jsdom tests).
- [ ] AC6: `?msg=` + `?q=` together → the auto-send path runs and `q` is ignored; `?q=` on a non-`new` `conversationId` or non-`full` variant is not applied; a non-empty draft is never overwritten by `?q=`.
- [ ] AC7: `git diff --name-only origin/main...HEAD | grep -E 'agent-runner-sandbox-config\.ts|lib/types\.ts|ws-zod-schemas\.ts|use-shortcuts\.tsx'` returns empty — the #9618 constraint and the frame-locality pin both hold.
- [ ] AC8: The ADR-113 addendum describes the frame as `{task, conversationId, repoConnected?}` (`grep -n 'repoConnected' knowledge-base/engineering/architecture/decisions/ADR-113-support-persona-scoped-concierge.md` returns ≥1), and the committed `.pen` is referenced (`git ls-files --error-unmatch knowledge-base/product/design/support/support-handoff-repo-connected-prefill.pen` exits 0).
- [ ] AC9: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` is green and `cd apps/web-platform && ./node_modules/.bin/vitest run test/support-handoff.test.ts test/support-sse.test.ts test/chat-prefill.test.tsx` is green — no `denySupport` behavioral regression (all 8 support deny arms still record + relay; the existing support-handoff suite stays green).

## Test Scenarios

- Given a support turn where `ccDeps.repoConnected === false`, when a deny is recorded and the terminal frame arrives, then the SSE body contains `"type":"support_handoff"` with `"repoConnected":false` before the terminal frame, and the reducer composes `handoffMarkdown` pointing at `/connect-repo`.
- Given `repoConnected === true`, when the same flow runs, then the frame carries `true` and the composed markdown is the clean `?msg=` link with no caveat.
- Given a `denySupport` site added later without the wrapper, when `tsc` runs, then the `deny()` closure type forces the `repoConnected` injection — the wrapper is the only `denySupport(` call in the file.
- Given `/dashboard/chat/new?q=refund%20policy` on a `full`-variant surface, when ChatSurface mounts, then the composer shows `refund policy`, the URL no longer carries `q`, and no message is sent.
- Given `/dashboard/chat/new?q=x&msg=y`, when the surface mounts, then the first-run send consumes `msg`, `q` is not applied to the composer, and both params are stripped.
- Given `/dashboard/chat/<real-id>?q=x`, when the surface mounts, then the composer stays empty (non-`new` ids do not consume `q`).
- Given a stored `draftKey` draft of "draft text" and `?q=other`, when the composer mounts, then `textarea.value` is the draft (prefill never clobbers) — full-variant has no `draftKey`, so this is pinned at the `ChatInput` prop level with a stubbed `safeSession` read.
- Given a second mount / StrictMode re-run, when `?q=` is still visible pre-strip, then the composer is seeded exactly once (the latch holds; no duplicate text).

## Success Metrics

- A repo-less support user who is handed off sees a connect-repo affordance and lands on `/connect-repo`, never on the repo-gated chat error.
- `/dashboard/chat/new?q=<text>` deterministically lands the text in the composer with zero sends (palette "Ask an agent about <q>" no longer dead-ends).
- Zero new DB reads on the dispatch path (`getCurrentRepoUrl` call count unchanged).

## Dependencies & Risks

- **`repoConnected` recorded at deny time can be stale at emit** (repo connected mid-turn) — bounded: worst case is one turn's copy pointing at `/connect-repo` for a now-connected user; the destination self-explains. Accepted as the issue's contract.
- **`repoUrl !== null` vs. `repoStatus === "ready"`** — a `cloning`/`error` workspace yields `repoConnected: true` and the link lands on a surface that gates the composer anyway (honest). Chosen deliberately (FR-3); a tri-state frame was cut as YAGNI.
- **`enqueue` is synchronous** — the record must carry the flag; any async re-resolve would not fit the emit site (the Cut List).
- **Permission-callback blast radius** — the `deny()` wrapper is a rename across 8 deny sites; a missed rename silently drops the flag (not the deny — `denySupport` still works if called directly). AC4's census makes a miss loud.
- **`useSearchParams` timing** — the latched-effect design is deliberately robust to params populating after mount (initializer-based seeding would be flaky).
- **Post-connect task carry** — the `repoConnected: false` link lands on `/connect-repo` without the task text; after connecting, the user re-copies the task from the support bubble (preserved). A task-carrying connect param would invent a second dangling consumer — cut deliberately.
- **Plan-file self-reference** — this plan is a knowledge-base artifact; no product code is touched by the `.pen` or ADR edits.

### Precedent-diff (deepen-plan Phase 4.4)

Every new local pattern maps to an in-repo precedent; none is novel:

| Pattern | Precedent | Diff |
|---------|-----------|------|
| `deny(opts)` closure wrapper injecting `deps.repoConnected` | `denySupport` itself + the `deps:` injection model (`permission-callback.ts:265`, `ccDeps` at `cc-dispatcher.ts:2654`) | The wrapper *is* the injection-point pattern applied at the callback's chokepoint; `denySupport`'s own contract ("one injection point for every deny path") is mirrored one level up. |
| `prefillAppliedRef` apply-once latch | `prevDraftKeyRef` change-detection latch, `chat-input.tsx:154` | Same ref-latch shape; applies once rather than on change. |
| `router.replace(pathname, { scroll: false })` strip | first-run `msg`/`fr` strip, `chat-surface.tsx:611` | Byte-identical convention; separate latched effect so `q`-only navigation still strips. |
| `prefill` prop into a self-owned-state input | `draftKey`/`safeSession` rehydrate in `useState` initializer, `chat-input.tsx:137` | Both are one-shot seeds into `value`; `prefill` is effect-based (param may populate post-mount), the draft is initializer-based (sync storage read). |

### Verify-the-negative results (deepen-plan Phase 4.45)

| Claim | Verdict | Evidence |
|-------|---------|----------|
| "flag already resolved in dispatch" | confirms | `getCurrentRepoUrl(args.userId, activeWorkspaceId)` at `cc-dispatcher.ts:1843` (Promise.all, unconditional); `repoUrl` destructured at `:1814`; `ccDeps` at `:2654`, same function body |
| "no `?q=` consumer under components/chat/" | confirms | `git grep 'searchParams.get("q")' components/ app/` → only `app/api/kb/search/route.ts` |
| "zero added DB reads" | confirms | `getCurrentRepoUrl(` call-site count is 1 pre-change; FR-3 adds no call |
| "`enqueue` is synchronous" | confirms | `const enqueue = (msg: WSMessage): boolean =>` at `route.ts:170` |
| "support client reads only handoffMarkdown" | confirms | `components/support/use-support-chat.ts:158,172,232` — no repo state |
| "`support_handoff` is not in the WS union" | confirms | zero hits in `lib/types.ts` / `lib/ws-zod-schemas.ts` |
| "never auto-sends" (`?q=`) | confirms (design) | `sendMessage` is invoked only by user action and the first-run `msg` effect; the `prefill` path writes `value` only |
| "draft never clobbered" | confirms | `draftKey` rehydrate is a `useState` initializer (`chat-input.tsx:137`) that precedes the latch effect; the guard reads `value` empty-state at apply time |
| "does not touch `agent-runner-sandbox-config.ts`" | confirms | `git diff --name-only origin/main...HEAD` shows no match (AC7) |

## Sharp Edges

- `repoUrl` must be read at the `ccDeps` site inside `dispatchSoleurGo` — it is in scope there; do NOT re-resolve it (that would be the "extra DB read" the issue forbids) and do NOT thread it through a new dispatch arg.
- Rename all 8 `denySupport(` sites to `deny(` — a missed one still works but loses the flag silently. The census AC exists because this is a rename, not a type error.
- `CanUseToolDeps.repoConnected` is **optional** — the legacy `agent-runner.ts` construction and test mocks compile unchanged; do not make it required.
- `repoConnected` on the frame is `repoConnected?` (optional) — required would break `supportTerminalPrefixFrames` callers and any older parsed frame.
- The `prefill` prop applies via a **latched effect**, never the `useState` initializer — the initializer races `useSearchParams` population and would lose the param intermittently.
- `?q=` strip uses `router.replace(pathname, { scroll: false })` — the `msg`/`fr` convention; a `push` would leave a history entry that re-seeds on Back.
- Do not "simplify" `?msg=` and `?q=` into one param — auto-send vs prefill are different shipped contracts (`runFirstRunSend` vs. composer seed).
- `SUPPORT_TERMINAL_FRAME_TYPES` ordering stays load-bearing — the handoff frame still precedes the terminal frame; the widened record changes nothing about ordering.
- `encodeURIComponent` + `!~*'()` percent-encoding in `buildSupportHandoffMarkdown` must be reused verbatim for the `/connect-repo` arm's copy — the surrogate-pair and markdown-destination hazards the function documents apply to any new arm.
- `agent-runner-sandbox-config.ts` is off-limits this entire PR (#9618) — verify the diff stays clean before every push.

## Alternative Approaches Considered

| Approach | Why not chosen |
|----------|----------------|
| Route-side `getCurrentRepoUrl` re-resolve at emit | The "extra DB read per deny" the issue was deferred over; second claim-resolution could disagree with dispatch's; `enqueue` is sync |
| Dispatch out-callback (`args.onRepoContextResolved`) | Adds a new args surface; a dispatch that throws before resolution leaves the flag unknowable vs. recorded-at-deny precision; the registry already exists as the deny→emit bridge |
| Client-side `useActiveRepo` in the support panel | Adds an SWR fetch + timing race to a surface with no repo state; frame flag is emit-time truth at zero fetch cost |
| `insertRef.current?.(q, 0)` for prefill | Reuses @-mention machinery (adds trailing space, wrong cursor semantics) for a different intent |
| `ChatInput` reads `useSearchParams` itself | Param is a route-level concern (page owns `context`, surface owns `msg`/`leader`/`fr`); would also fire in KB-sidebar variants |
| `repoConnected` as tri-state (`repoStatus`-graded) | YAGNI — the issue asks for a boolean; `cloning`/`error` self-describe at the destination |
| Switch handoff link to `?q=` (prefill) | Changes #9539's shipped auto-send; unrequested — kept as Non-Goal |

## References & Research

- Parent plan (archived): `knowledge-base/project/plans/archive/20261005-182039-2026-10-05-fix-support-persona-write-dead-end-plan.md` (the deferral origin; AC1 emit pattern).
- ADR: `knowledge-base/engineering/architecture/decisions/ADR-113-support-persona-scoped-concierge.md` (addendum — mechanism + known residuals).
- Sibling shipped plan: `knowledge-base/project/plans/2026-10-06-fix-safe-bash-git-branch-support-kb-search-plan.md` (#9555/#9559, merged as PR #9570).
- Learnings: `2026-07-22-…-type-widening-must-sweep-injected-dep-signatures.md`, `2026-06-18-usesearchparams-on-static-route-needs-suspense-and-next-build-gate.md`.
- Precedent for the Product/UX rubric + plan-time `.pen`: `knowledge-base/project/plans/archive/20261005-162543-2026-10-05-fix-workflow-ended-status-copy-plan.md`.

## Implementation Phases

- **Phase 1 — server plumbing (#9556):** `support-escalation.ts` record shape → `permission-callback.ts` deps + `deny()` wrapper + renames → `cc-dispatcher.ts` `ccDeps` field → `route.ts` emit + log. Failing tests first (`cq-write-failing-tests-before`).
- **Phase 2 — frame + copy (#9556):** `support-sse.ts` union + reducer → `support-handoff.ts` tri-state builder → tests green.
- **Phase 3 — `?q=` consumer (#9557):** `chat-input.tsx` prop → `chat-surface.tsx` wiring + strip → `test/chat-prefill.test.tsx`.
- **Phase 4 — docs + verify:** ADR-113 addendum edit (`.pen` already committed at plan time) → typecheck + touched vitest files + the AC7 clean-diff greps.
