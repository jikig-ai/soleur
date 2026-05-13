---
title: cc-soleur-go Stage 6 — PR-A (bubble e2e foundations + DEV_ORIGINS multi-port fix)
date: 2026-05-13
issue: 2939
spec: knowledge-base/project/specs/feat-cc-soleur-go-smoke-2939/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-13-cc-soleur-go-stage-6-smoke-brainstorm.md
parent_plan: knowledge-base/project/plans/2026-04-23-feat-cc-route-via-soleur-go-plan.md
branch: feat-cc-soleur-go-smoke-2939
worktree: .worktrees/feat-cc-soleur-go-smoke-2939
pr: 3743
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: plan-complete
---

# Plan: PR-A — bubble e2e foundations + DEV_ORIGINS multi-port fix (#2939)

## Overview

PR-A is the first of three layered PRs delivering Stage 6 (post-cutover regression net for cc-soleur-go). Scope: (1) extend `DEV_ORIGINS` in `lib/auth/validate-origin.ts` to accept multiple development-mode origins (Playwright runs ports 3099 + 3100 simultaneously); (2) ship a Playwright WS-frame injector helper at `apps/web-platform/e2e/cc-soleur-go-ws-injector.ts` (~50 LoC) using `page.routeWebSocket()`; (3) ship 4 per-bubble Playwright e2e tests in a single new file `apps/web-platform/e2e/cc-soleur-go-bubbles.e2e.ts` (~250 LoC) covering subagent-group, interactive-prompt-card, workflow-lifecycle-bar, and tool-use-chip.

PR-B (routing/cost/UX smoke, plan §6.1-6.7 + 6.5.2-6.5.4) and PR-C (security smoke 6.8-6.11 + manual visual-QA rubric) land separately once PR-A merges; the WS-injector helper from PR-A is the foundation both depend on.

## Research Reconciliation — Spec vs. Codebase

Six material plan-drifts surfaced during plan-time verification. All resolved before drafting; recorded here for downstream readers (PR-B/PR-C inherit the corrected shape).

| Spec claim | Reality | Plan response |
|---|---|---|
| `validate-origin.ts` lives at `apps/web-platform/server/` | Actual path: `apps/web-platform/lib/auth/validate-origin.ts:10` | Plan TR1/AC1 target the correct path |
| `DEV_ORIGINS` is fully hardcoded to `localhost:3000` | Already weaves `process.env.NEXT_PUBLIC_APP_URL` (line 13) but as a single value — insufficient for Playwright's two simultaneous ports (3099 + 3100) | Plan adds `NEXT_PUBLIC_DEV_EXTRA_ORIGINS` (comma-separated list); keeps existing single-value `NEXT_PUBLIC_APP_URL` for backward compatibility |
| WS-replay pattern source is `cc-soleur-go-end-to-end-render.test.tsx` | Confirmed — uses `applyStreamEvent(messages, activeStreams, ev, spawnIndex, workflow)` from `lib/chat-state-machine.ts`; test is jsdom (not Playwright). The promotion path is `page.routeWebSocket()` intercepting the cc-soleur-go WS endpoint, NOT calling `applyStreamEvent` directly | Plan TR1 wraps `routeWebSocket` and produces frames typed against `StreamEvent` union (`lib/chat-state-machine.ts:248-256`) |
| `tool-use-chip` exposes `[data-tool-name]` + `[data-leader-id]` + `[data-affordance]` for FR1.4 | Actual selector is single composite: `data-tool-chip-id={leaderId}-{toolName}-{toolLabel}` (`tool-use-chip.tsx:42`); **no `data-affordance` exists** | FR1.4 reframed: assert `data-tool-chip-id` starts with `cc_router-mcp__soleur_platform__` (degraded-UX literal FQN render per Spec NG3). NOT adding a new affordance attribute — that would be a UX scope-out into PR-C territory |
| `workflow-lifecycle-bar` chip removal triggers on `stream_end` (FR1.3) | Verified at `chat-state-machine.ts`: **BOTH** `case "stream_end"` (line 522-529) AND `case "workflow_started"` (line 716-718) filter out `tool_use_chip` entries. Spec was correct; an earlier draft of this plan wrongly claimed only `workflow_started` fires — Kieran-review correction | FR1.3 covers **both** chip-removal paths: `tool_use → stream_end` AND `tool_use → workflow_started`. Either path firing in isolation in a future refactor would silently break the regression net without two assertions |
| Wire-event `tool_use` shape is `{leaderId, toolName, toolLabel}` | Per `ws-zod-schemas.ts:244-248`, real shape is `{type, leaderId, label}` only. The reducer at `chat-state-machine.ts:362-364` expands `event.label` into BOTH `toolName: event.label` AND `toolLabel: event.label` when constructing the `tool_use_chip` message — Kieran-review correction | Plan §3.3 + §3.4 inject `tool_use(leaderId, label)` only. The rendered `data-tool-chip-id` is `cc_router-{label}-{label}`; the `^="cc_router-"` selector remains unambiguous |
| WS endpoint path is `**/api/ws*` | Per `ws-client.ts:496`, real URL shape is `${proto}://${host}/ws` — NO `/api/` prefix. Kieran-review correction | All `page.routeWebSocket()` globs use `"**/ws"` (Playwright baseURL-relative glob matching `/ws` path) |
| `workflow-lifecycle-bar` selector `[data-leader-id="cc_router"][data-chip]` | Actual selectors: `[data-lifecycle-state="active"\|"ended"]` (`workflow-lifecycle-bar.tsx:40,70`). The chip removal assertion targets `[data-tool-chip-id^="cc_router-"]` on `tool-use-chip` siblings, not lifecycle-bar attrs | FR1.3 assertion form: `expect(page.locator('[data-tool-chip-id^="cc_router-"]')).toHaveCount(0)` after `workflow_started` |

The `data-tool-chip-id={leaderId}-{toolName}-{toolLabel}` composite-key shape means starts-with selectors (`^=`) are the canonical lookup; per-attribute matching would require widening the component. PR-A does NOT widen — the regression net asserts the actually-shipping behavior.

## User-Brand Impact

**If this lands broken, the user experiences:** Stage 6 regression net falsely greens (smoke green-lights subsequent PRs that ship a real regression — e.g., chip-removal fails, expand-boundary breaks, or `workflow_started` no longer fires from cc-soleur-go). Since cc-soleur-go is the unconditional routing path (`FLAG_CC_SOLEUR_GO` retired by #3270), every routed conversation is affected.

**If this leaks, the user's data is exposed via:** N/A — this PR ships test infrastructure with synthesized fixtures only (per `cq-test-fixtures-synthesized-only` + Spec TR9). Mock-Supabase uses the existing `MOCK_USER` (`e2e/mock-supabase.ts:12-37`, `test@e2e.com`); no production data touches CI.

**Brand-survival threshold:** single-user incident. Carry-forward from brainstorm Phase 0.1 (operator endorsed both `trust breach` + `data loss / corruption` for the broader Stage 6 surface). PR-A is the foundation; a foundation that ships a weak regression-net assertion degrades the brand-survival floor for every cc-soleur-go-adjacent PR that ships after.

## Open Code-Review Overlap

Two open scope-outs touch `chat-state-machine`:

- **#2224** (refactor(chat): code-quality polish; **export StreamEvent**) — **Fold in (partial).** PR-A's WS-injector needs the `StreamEvent` type for frame-builder type safety. Folding in the `export StreamEvent` line item only (~3 LoC). The other items in #2224 (JSX indentation, isDone param, bubble factory, state-required type) are NOT in PR-A scope — defer. Mark `Closes #2224` only if all line items land here; otherwise add a "Partially addresses #2224" note in the PR body.
- **#2220** (refactor(chat): inject idFactory for reducer purity) — **Acknowledge.** PR-A drives WS frames via `page.routeWebSocket()`; it does NOT call `applyStreamEvent` directly. The idFactory purity concern doesn't apply at this layer. #2220 stays open.

## Implementation Phases

Pre-merge TDD: each phase is RED (failing test) → GREEN (smallest passing impl) → REFACTOR if needed. No phase commits until its tests pass.

### Phase 0 — Preconditions (HARD GATE — STOP if any verification disagrees)

**Block GREEN if any of these checks reveal a divergence from the plan's assumptions. Update the plan and re-spawn plan-review before proceeding.**

- [ ] Confirm Playwright version supports `routeWebSocket()`: `grep '"@playwright/test":' apps/web-platform/package.json` → `^1.58.2` (verified at plan-write; routeWebSocket added in 1.48).
- [ ] Confirm `StreamEvent` discriminated union shape: `grep -n "type StreamEvent" apps/web-platform/lib/chat-state-machine.ts` → line 244. Full union includes: `stream_start`, `stream`, `stream_end`, `tool_use`, `tool_progress`, `subagent_spawn`, `subagent_complete`, `workflow_started`, `workflow_ended`, `interactive_prompt`, `review_gate`, `context_reset`. **PR-A injects only the subset needed by the 4 tests: `tool_use`, `stream_end`, `workflow_started`, `workflow_ended`, `subagent_spawn`, `interactive_prompt`.** The `export StreamEvent` change in Phase 2 makes the full union available to consumers regardless.
- [ ] Confirm cc-soleur-go WS endpoint path: verified at plan-write per `ws-client.ts:496` → URL is `${proto}://${host}/ws`. Glob `"**/ws"` is the canonical Playwright `page.routeWebSocket()` form. Re-verify at /work-time with `grep -n '/ws' apps/web-platform/lib/ws-client.ts`.
- [ ] Confirm `MOCK_USER` + `MOCK_SESSION` fixtures: `grep -n "MOCK_USER\|MOCK_SESSION" apps/web-platform/e2e/mock-supabase.ts` → lines 12-37.
- [ ] Confirm 4 bubble data-* selectors against actual components (paths verified at plan-time):
  - subagent-group: `data-parent-spawn-id`, `data-expanded`, `data-child-spawn-id` (`subagent-group.tsx:128-167`)
  - interactive-prompt-card: `data-prompt-id`, `data-prompt-kind` (`interactive-prompt-card.tsx:103,134`)
  - workflow-lifecycle-bar: `data-lifecycle-state` (`workflow-lifecycle-bar.tsx:40,70`)
  - tool-use-chip: `data-tool-chip-id` (composite key `{leaderId}-{toolName}-{toolLabel}` — but the wire `tool_use` event carries only `{leaderId, label}`; reducer expands `event.label` to both fields per `chat-state-machine.ts:362-364`) (`tool-use-chip.tsx:42`)
- [ ] Confirm chip-removal triggers: `grep -n "case \"stream_end\"\|case \"workflow_started\"" apps/web-platform/lib/chat-state-machine.ts` → BOTH must show a `tool_use_chip` filter (lines 522 + 716 per plan-write verification). If only one fires, FR1.3 needs to drop the missing assertion. If a third trigger appears, extend FR1.3 in the same PR (enumerate-extend pattern per 2026-04-18 learning).

### Phase 1 — DEV_ORIGINS multi-port fix (RED → GREEN)

**Scope:** `apps/web-platform/lib/auth/validate-origin.ts` only.

- [ ] **RED**: extend `apps/web-platform/test/validate-origin.test.ts` (or create it if absent) with three new cases:
  1. `NEXT_PUBLIC_DEV_EXTRA_ORIGINS="http://localhost:3099,http://localhost:3100"` + `NODE_ENV=development` → both URLs accepted as origin.
  2. `NEXT_PUBLIC_DEV_EXTRA_ORIGINS=""` (or unset) + `NODE_ENV=development` → only `localhost:3000` + `https://app.soleur.ai` accepted (regression guard).
  3. `NEXT_PUBLIC_DEV_EXTRA_ORIGINS="http://localhost:3099"` + `NODE_ENV=production` → 3099 rejected (production behavior unchanged).
- [ ] **GREEN**: edit `lib/auth/validate-origin.ts:10-14`. Add comma-split parser for `NEXT_PUBLIC_DEV_EXTRA_ORIGINS`. Keep existing single-value `NEXT_PUBLIC_APP_URL` for backward compatibility. Concrete shape:
  ```ts
  const DEV_EXTRA = (process.env.NEXT_PUBLIC_DEV_EXTRA_ORIGINS ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter((s) => s.length > 0 && /^https?:\/\//.test(s));
  const DEV_ORIGINS = new Set([
    "https://app.soleur.ai",
    "http://localhost:3000",
    ...(process.env.NEXT_PUBLIC_APP_URL ? [process.env.NEXT_PUBLIC_APP_URL] : []),
    ...DEV_EXTRA,
  ]);
  ```
- [ ] **Document**: append a one-line block to `apps/web-platform/.env.example` documenting `NEXT_PUBLIC_DEV_EXTRA_ORIGINS` (Playwright-only, comma-separated).
- [ ] **Verify**: `bun run vitest apps/web-platform/test/validate-origin.test.ts` green.

### Phase 2 — WS-injector helper (GREEN only, no separate unit test)

**Scope:** new file `apps/web-platform/e2e/cc-soleur-go-ws-injector.ts` (~15-20 LoC). Per plan-review (DHH + Simplicity convergent): drop the generic `buildStreamEvent<T>` builder + separate vitest unit test. The 4 e2e tests in Phase 3 are the effective test of the helper; `tsc --noEmit` (AC7) covers the type-safety check; call-site `satisfies StreamEvent` gives shape verification without an indirection layer.

- [ ] **Fold in #2224 (partial)**: add `export` keyword to `type StreamEvent = ...` declaration in `apps/web-platform/lib/chat-state-machine.ts:244` (currently internal). 1-line edit.
- [ ] **GREEN**: implement helper. Final shape:
  ```ts
  import type { Page, WebSocketRoute } from "@playwright/test";
  import type { StreamEvent } from "@/lib/chat-state-machine";

  export async function attachWsInjector(page: Page) {
    let routeRef: WebSocketRoute | undefined;
    await page.routeWebSocket("**/ws", (ws) => {
      routeRef = ws;
      ws.connectToServer(); // default pass-through; tests inject via sendToClient
    });
    return {
      send: (event: StreamEvent) => {
        if (!routeRef) throw new Error("WS route not yet established");
        routeRef.sendToClient(JSON.stringify(event));
      },
    };
  }
  ```
  Call sites in Phase 3 use object literals with `satisfies StreamEvent`:
  ```ts
  injector.send({ type: "tool_use", leaderId: "cc_router", label: "Routing" } satisfies StreamEvent);
  ```

### Phase 3 — 4 bubble e2e tests (RED → GREEN per bubble, single file)

**Scope:** new file `apps/web-platform/e2e/cc-soleur-go-bubbles.e2e.ts` (~250 LoC). Uses the `authenticated` Playwright project (mock-Supabase, port 3100, `storageState: "e2e/.auth/user.json"`).

Mandatory pre-test setup (mirror `start-fresh-onboarding.e2e.ts:62-153` pattern):
1. `page.addInitScript` BEFORE `page.route` — injects fake `sb-localhost-auth-token` so Supabase JS client doesn't short-circuit before mocks fire (per TR7).
2. `page.route("**/auth/v1/user", ...)`, `**/rest/v1/conversations*`, `**/rest/v1/messages*`, `**/realtime/**` — return PostgREST `.single()`-compatible **object** payloads (per TR8), not arrays.
3. Seed one conversation (id `conv-stage-6-smoke`) with `active_workflow = "cc-router"`.
4. `attachWsInjector(page)` — internally anchors on `"**/ws"` per `ws-client.ts:496` verification.
5. `await page.goto("/dashboard/chat/conv-stage-6-smoke")` — wait for chat-surface mount.

**Per-bubble tests:**

- [ ] **3.1 subagent-group expand-boundary** (FR1.1):
  - Inject 3× `subagent_spawn` events with same `parentId="p-test-1"`, different `spawnId`/`leaderId`.
  - Assert `await expect(page.locator('[data-parent-spawn-id="p-test-1"]')).toHaveCount(1)`.
  - Assert `await expect(page.locator('[data-parent-spawn-id="p-test-1"] [data-child-spawn-id]')).toHaveCount(3)`.
  - Assert `await expect(page.locator('[data-parent-spawn-id="p-test-1"][data-expanded="false"]')).toBeVisible()` (collapsed when N=3).
  - Second test case (or chained injection): inject only 2× `subagent_spawn` with a new `parentId`; assert `[data-expanded="true"]` (auto-expand boundary at N≤2).

- [ ] **3.2 interactive-prompt-card resolved-state** (FR1.2):
  - Inject `interactive_prompt(kind="ask_user", promptId="pid-test-1", options=[{id:"a"},{id:"b"},{id:"c"}], multi_select=true)`.
  - Assert `await expect(page.locator('[data-prompt-id="pid-test-1"][data-prompt-kind="ask_user"]')).toBeVisible()`.
  - (Resolved-state assertion — derived from `interactive-prompt-card-resolved.test.tsx`): inject a follow-up event resolving the prompt with `selectedIds=["a","c"]`; assert the card's resolved-state grammar renders (specific selector form to confirm in Phase 0 from the `*-resolved.test.tsx` file).

- [ ] **3.3 workflow-lifecycle-bar chip-removal — BOTH trigger paths** (FR1.3, **covers both `stream_end` AND `workflow_started` triggers per Research Reconciliation row 5**). Two sub-test cases in the same `test()` block (or two adjacent `test()` blocks sharing the same setup):
  - **3.3a `tool_use → workflow_started` path:**
    - Inject `{ type: "tool_use", leaderId: "cc_router", label: "Routing via /soleur:go" } satisfies StreamEvent`.
    - Assert chip present: `await expect(page.locator('[data-tool-chip-id^="cc_router-"]')).toHaveCount(1)`.
    - Inject `{ type: "workflow_started", workflow: "brainstorm", conversationId: "conv-stage-6-smoke" } satisfies StreamEvent`.
    - Assert chip removed: `await expect(page.locator('[data-tool-chip-id^="cc_router-"]')).toHaveCount(0)`.
    - Assert lifecycle bar active: `await expect(page.locator('[data-lifecycle-state="active"]')).toBeVisible()`.
    - Inject `{ type: "workflow_ended", status: "completed", ... } satisfies StreamEvent`; assert `[data-lifecycle-state="ended"]`.
  - **3.3b `tool_use → stream_end` path:** (fresh page or reset state):
    - Inject `{ type: "tool_use", leaderId: "cc_router", label: "Routing via /soleur:go" } satisfies StreamEvent`.
    - Assert chip present: `await expect(page.locator('[data-tool-chip-id^="cc_router-"]')).toHaveCount(1)`.
    - Inject `{ type: "stream_end", leaderId: "cc_router" } satisfies StreamEvent` (verify required-fields against `chat-state-machine.ts:522-529` at Phase 0).
    - Assert chip removed: `await expect(page.locator('[data-tool-chip-id^="cc_router-"]')).toHaveCount(0)`.
  - **Why both:** the reducer ships both removal paths (chat-state-machine.ts lines 522 + 716). A test that asserts only one would silently green-light a regression that removes the other. Per enumerate-extend pattern (2026-04-18 learning).

- [ ] **3.4 tool-use-chip unregistered-mcp-fqn render** (FR1.4, **reframed per Research Reconciliation row 4 — degraded UX is literal FQN appearing as `data-tool-chip-id`**):
  - Inject `{ type: "tool_use", leaderId: "cc_router", label: "mcp__soleur_platform__test_synthesized_smoke" } satisfies StreamEvent` — synthesized name that is NEITHER registered NOR on the Tier 3 denylist (`mcp__soleur_platform__plausible_*`), per Spec TR9. The reducer expands `label` to BOTH `toolName` and `toolLabel` per `chat-state-machine.ts:362-364`, producing `data-tool-chip-id="cc_router-mcp__soleur_platform__test_synthesized_smoke-mcp__soleur_platform__test_synthesized_smoke"`. **Sentry-mirror impact:** none — this is a synthesized client-side injection; the production iterator-hook mirror (`cc-dispatcher.ts:1044`) fires only on real cc-router-dispatched tool calls.
  - Assert chip rendered with FQN-in-key: `await expect(page.locator('[data-tool-chip-id^="cc_router-mcp__soleur_platform__test_synthesized_smoke-"]')).toHaveCount(1)`.
  - Assert chip renders WITHOUT crash (test reaches the assertion without `page.on("pageerror", ...)` firing — wire an error capture at setup).

### Phase 4 — Integration verification

- [ ] `bun run vitest apps/web-platform/test/validate-origin.test.ts` green (Phase 1 only — no separate WS-injector unit test per plan-review).
- [ ] `cd apps/web-platform && bun playwright test --project=authenticated cc-soleur-go-bubbles.e2e.ts` green.
- [ ] **No-Sentry-flood guard** (per Spec NG4 / TR9): `grep -n "mcp__soleur_platform__plausible_" apps/web-platform/e2e/cc-soleur-go-bubbles.e2e.ts apps/web-platform/e2e/cc-soleur-go-ws-injector.ts` returns zero. Anchor is the literal denylist prefix (`*` is not regex; trailing pattern stripped). False-pass risk on shorthand object literals (`{ label }` where `label === "...plausible_..."`) is acknowledged but low — Phase 3 tests use only the synthesized `test_synthesized_smoke` FQN.
- [ ] **No-real-SDK guard** (per Spec NG2): `grep -n "ANTHROPIC_API_KEY\|claude-agent-sdk" apps/web-platform/e2e/cc-soleur-go-bubbles.e2e.ts apps/web-platform/e2e/cc-soleur-go-ws-injector.ts` returns zero.
- [ ] **No-screenshot-baseline guard** (per Spec NG1): `grep -rn "toHaveScreenshot" apps/web-platform/e2e/` returns no NEW matches vs main.
- [ ] **`tsc --noEmit` clean** for `apps/web-platform`. Verifies the `export StreamEvent` change doesn't break downstream consumers; verifies WS-injector call-site `satisfies StreamEvent` shapes (the type-safety check that replaces the dropped unit test).
- [ ] **Auth-gate enumeration** (TR10): PR-A does NOT introduce a new auth primitive — confirm via `grep -n "withUserRateLimit\|authenticateAndResolveKbPath\|getUser" apps/web-platform/lib/auth/validate-origin.ts` returns zero. No enumeration extension needed.

### Phase 5 — Compound + ship handoff (post-implementation)

- [ ] Run `skill: soleur:compound` to capture any session learnings.
- [ ] Run `skill: soleur:ship` — PR-A is title-eligible for `semver:minor` (new env var `NEXT_PUBLIC_DEV_EXTRA_ORIGINS`, new test files; no existing API changes).
- [ ] PR body: `Closes #2939 (partial — PR-A of 3); Partially addresses #2224 (export StreamEvent line item only)`. Title prefix: `feat(cc-soleur-go): Stage 6 PR-A — bubble e2e foundations + DEV_ORIGINS multi-port (#2939)`.
- [ ] Append a "PR-A scope" note to #2939 body referencing this plan + listing PR-B/PR-C as follow-ups.

## Files to Edit

- `apps/web-platform/lib/auth/validate-origin.ts` (Phase 1) — extend `DEV_ORIGINS` with `NEXT_PUBLIC_DEV_EXTRA_ORIGINS` comma-list parser.
- `apps/web-platform/lib/chat-state-machine.ts` (Phase 2) — add `export` to `type StreamEvent` declaration at line 248 (folds in #2224's `export StreamEvent` line item).
- `apps/web-platform/.env.example` (Phase 1) — document `NEXT_PUBLIC_DEV_EXTRA_ORIGINS`.

## Files to Create

- `apps/web-platform/test/validate-origin.test.ts` (Phase 1, RED) — if absent. Three new test cases per Phase 1 RED.
- `apps/web-platform/e2e/cc-soleur-go-ws-injector.ts` (Phase 2, GREEN) — ~15-20 LoC. `attachWsInjector(page)` only — no generic builder, no separate unit test (DHH + Simplicity convergent).
- `apps/web-platform/e2e/cc-soleur-go-bubbles.e2e.ts` (Phase 3, RED → GREEN) — ~250 LoC. 4 per-bubble Playwright assertions on `authenticated` project. FR1.3 carries TWO sub-cases (stream_end + workflow_started chip-removal paths).

**Total estimated LoC:** ~270 (5 DEV_ORIGINS + 20 WS-injector + 250 e2e tests — round). Inside brainstorm "PR-A ~250-300 LoC" target.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1**: `DEV_ORIGINS` honors `NEXT_PUBLIC_DEV_EXTRA_ORIGINS` (comma-separated) in development mode; production behavior unchanged. Verified by 3 new vitest cases in `validate-origin.test.ts`.
- [ ] **AC2**: `.env.example` documents `NEXT_PUBLIC_DEV_EXTRA_ORIGINS` with a 1-line description + example values.
- [ ] **AC3**: `StreamEvent` is exported from `chat-state-machine.ts` (line 248). Folds #2224 line item.
- [ ] **AC4 (collapsed into AC5 + AC7)**: ~~separate unit test~~ — dropped per plan-review. `attachWsInjector` is tested via the 4 e2e tests; type safety is enforced by `tsc --noEmit` (AC7).
- [ ] **AC5**: `cc-soleur-go-bubbles.e2e.ts` ships 4 per-bubble Playwright test cases on the `authenticated` project, each driving through `attachWsInjector` against mock-Supabase fixtures. **FR1.3 (workflow-lifecycle-bar) carries TWO sub-cases**: chip-removal on `stream_end` AND on `workflow_started`. All test cases pass on local CI run.
- [ ] **AC6**: Phase 4 guard greps all return zero matches: no `mcp__soleur_platform__plausible_*` in new e2e tests (Spec TR9), no `ANTHROPIC_API_KEY`/`claude-agent-sdk` in new e2e tests (Spec NG2), no new `toHaveScreenshot()` matches (Spec NG1).
- [ ] **AC7**: `tsc --noEmit` clean for `apps/web-platform`. Confirms `export StreamEvent` didn't break downstream consumers and the WS-injector's TS exhaustiveness over `StreamEvent` discriminator holds.
- [ ] **AC8**: PR body includes `Closes #2939 (partial — PR-A of 3); Partially addresses #2224`. Title carries `semver:minor` (new env var surface).
- [ ] **AC9**: User-Brand Impact section reflects single-user-incident threshold (carry-forward from spec). CPO sign-off acknowledged via brainstorm Phase 0.1 + this plan's frontmatter `requires_cpo_signoff: true`.

### Post-merge (operator)

- [ ] **AC10**: PR-B planning starts within 7 days. Branch `feat-cc-soleur-go-smoke-2939` is kept open OR a sibling `feat-cc-soleur-go-smoke-2939-pr-b` is cut at PR-A merge time (preferred — avoids 3-PR-on-1-branch confusion).

  **Automation: not feasible because** scheduling a follow-up planning session is a human decision (whether PR-A's signal warrants immediate PR-B vs. a wait-for-Sentry observation window). Genuinely operator-driven.

No infrastructure apply, no migration verification, no Doppler secret rotation. Standard `/soleur:ship` pipeline handles merge + post-merge workflow verification.

## Test Strategy

- **Unit (vitest, jsdom):** `validate-origin.test.ts` (3 cases), `cc-soleur-go-ws-injector.test.ts` (3 cases). Hermetic, no dev-server boot. Run via `bun run vitest`.
- **E2E (Playwright, authenticated project, port 3100):** `cc-soleur-go-bubbles.e2e.ts` (4 test cases). Mocks Supabase via existing `e2e/mock-supabase.ts`; mocks WS via `page.routeWebSocket()` driven by the new injector. No real Anthropic SDK in CI.
- **No `toHaveScreenshot()` baselines.** Per Spec NG1 + brainstorm-converged decision (theme-PR churn rate × baseline regen would degrade reviewer signal). Visual-QA rubric is PR-C scope.

## Risks & Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| `page.routeWebSocket("**/ws")` glob doesn't match — silent no-op | M (was H pre-Kieran) | Plan-write verification confirmed path is `/ws` per `ws-client.ts:496`. /work Phase 0 re-verifies via grep. Glob `"**/ws"` is the canonical Playwright form |
| Mock-Supabase's HTTP-200 Realtime stub interferes with `routeWebSocket` interception | L | Realtime uses `/realtime/**`; cc-soleur-go uses `/ws`. Different paths — no interference. Phase 0 verifies |
| `DEV_ORIGINS` change breaks legacy local dev (developer running on port 3000 without setting `NEXT_PUBLIC_DEV_EXTRA_ORIGINS`) | L | Fallback path: comma-list parser returns empty array; existing `localhost:3000` + `NEXT_PUBLIC_APP_URL` paths unchanged. Vitest case 2 (Phase 1 RED) is the regression guard |
| Tool-chip composite-key `^=` selector breaks when toolLabel later includes a hyphen-prefixed suffix that mid-matches | L | Use `data-tool-chip-id^="cc_router-"` (anchored at leaderId boundary, not suffix). The composite is `{leaderId}-{toolName}-{toolLabel}`; `^=` on `cc_router-` is unambiguous |
| `export StreamEvent` (#2224 fold-in) breaks a downstream consumer | L | `tsc --noEmit` in AC7. The `export` adds visibility; doesn't change shape |
| 4 e2e tests are too slow (each spins up dev server) | M | Playwright reuses the `authenticated` project's dev server across tests via `webServer` config; the new file adds ~4 tests not 4 server boots. Wall-clock budget for new file ≤ 60s |
| Smoke tests reveal real cc-soleur-go bugs at Phase 3 GREEN | M | This is the whole point. If revealed, file as scope-out issues in the PR body; do NOT silently fix in PR-A (would expand scope beyond authorized 3-PR layering) |

## Domain Review

**Domains relevant:** Engineering, Product, Legal (triad carry-forward from brainstorm Phase 0.5).

**Brainstorm-recommended specialists:** none beyond the triad. No copywriter, conversion-optimizer, or UX specialist named by any leader.

### Product (CPO) — carry-forward

**Status:** reviewed (brainstorm carry-forward; no re-spawn).
**Assessment summary:** Kill-switch threshold accepted. Per-bubble golden assertions identified and reflected in FR1.1-FR1.4. Manual visual QA is a one-time gate (PR-C scope). Degraded-UX assertion on tool-use-chip is the right shape for the empty-allowlist reality. **PR-A reflects all four golden-path scopes; FR1.3 + FR1.4 selector/trigger names corrected per Phase 1 verification (see Research Reconciliation).**

### Legal (CLO) — carry-forward

**Status:** reviewed (brainstorm carry-forward).
**Assessment summary:** GO with FR5.6 screenshot-redaction AC. PR-A ships NO screenshots — all 4 bubble assertions key off `data-*` attributes, no PNG capture. CLO ask deferred to PR-C (visual-QA rubric scope). Existing `cq-test-fixtures-synthesized-only` covered by mock-Supabase fixtures.

### Engineering (CTO) — carry-forward

**Status:** reviewed (brainstorm carry-forward).
**Assessment summary:** Mock at WS message boundary via `page.routeWebSocket()`; no real Anthropic SDK in CI. `applyStreamEvent` is the reducer entry point in jsdom unit tests; PR-A's e2e drives the same reducer indirectly via WS-injected frames through the production WS handler path. No new sub-agents; no Sentry-mirror introduction (none needed at this layer — the iterator-hook mirror in `cc-dispatcher.ts:1044` is unaffected). Binding learnings (DEV_ORIGINS, `.e2e.ts` + tsx, stream_end semantics, absolute screenshot paths) reflected in TR1-TR11 and Phase 0-4.

### Product/UX Gate

**Tier:** NONE. PR-A ships test infrastructure only — no new user-facing pages, modals, banners, or interactive surfaces. No `components/**/*.tsx` new file creation that would mechanically escalate to BLOCKING. ux-design-lead, copywriter, spec-flow-analyzer not invoked.

## GDPR / Compliance Gate

Skip-evaluated against canonical triggers:

- **(a) New LLM/external-API processing of operator-session data:** N/A — no LLM calls in PR-A.
- **(b) Brand-survival threshold `single-user incident`:** **YES — triggers gate.** But scope is test infrastructure with synthesized fixtures; no PII surface change. Mock-Supabase MOCK_USER is `test@e2e.com` (synthesized).
- **(c) New cron/workflow reading from learnings/specs:** N/A.
- **(d) New artifact distribution surface:** N/A.

**Gate outcome:** **GO**. Compliance posture unchanged (no new processing activity, no DPA delta, no Art. 30 RoPA edit). PR-A is test-infrastructure-only; the `validate-origin.ts` change is dev-mode-scoped and explicitly does NOT alter production CSRF semantics (production reads `PRODUCTION_ORIGINS`, unchanged). No `compliance-posture.md` Active Items entry needed; no `compliance/critical` issue.

## Sharp Edges

- **Verify the cc-soleur-go WS endpoint path in Phase 0 BEFORE writing any `page.routeWebSocket` glob.** A glob that doesn't match the real endpoint silently no-ops — all 4 bubble tests would pass against an unintercepted real WS (which mock-Supabase rejects with HTTP 200, leaving the bubble in idle state and assertion failures looking like component bugs). The Phase 0 grep is load-bearing.
- **`data-tool-chip-id` is a composite key, not a per-attribute lookup.** `^=` selectors on the leaderId prefix are the canonical form. A test that asserts `[data-tool-name=...]` will return zero matches and pass vacuously if combined with `toHaveCount(0)` — a false-green that would ship a broken net. Always use `^="cc_router-"` for leaderId scope on the chip.
- **Chip removal fires on BOTH `stream_end` AND `workflow_started`.** Plan v1 wrongly claimed only `workflow_started` removes the chip; Kieran-review surfaced that `chat-state-machine.ts:522-529` also removes via `stream_end`. FR1.3 now tests BOTH paths (3.3a + 3.3b). If a future reducer refactor adds a third removal trigger, extend FR1.3 in the same PR (enumerate-extend pattern per `2026-04-18-auth-gate-smoke-tests-enumerate-patterns.md`). Sentinel check at Phase 0 + at /work time: `grep -n "tool_use_chip" apps/web-platform/lib/chat-state-machine.ts` — count of removal sites should match the count of FR1.3 sub-cases (currently 2; lines 522 + 716).
- **Synthesized tool name `mcp__soleur_platform__test_synthesized_smoke`** MUST NOT be added to the Tier 3 denylist (`apps/web-platform/server/tool-tiers.ts` `CC_ROUTER_TIER3_DENYLIST`). Verify pre-commit via `rg "test_synthesized_smoke" apps/web-platform/server/tool-tiers.ts` returns zero. The synthesized FQN is a test seam; promoting it to denylist would pollute the production registry.
- **Open code-review fold-in is partial (#2224).** Only the `export StreamEvent` line item lands here. The other 4 items in #2224 (JSX indentation, isDone param, bubble factory, state-required type) are explicitly NOT in PR-A scope. The PR body's `Closes #2224` would over-claim; use `Partially addresses #2224` instead. Sharp-edge for the implementer: do NOT touch the other items even if grep surfaces them adjacent to the `export` line.
- **PR-A scope drift sentinel.** If during /work the implementer is tempted to also fix a real cc-soleur-go bug surfaced by the new tests, STOP. File the bug as a separate scope-out issue and add to PR-A's body. PR-A is the regression net foundation; conflating net + fix turns a 250-LoC PR into a 600-LoC fix-bundle that's harder to review and harder to revert.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan's section is filled; no action needed.

## Out of Scope (deferred)

**Deferred to PR-B:** Plan §6.1-6.7 (routing/cost/UX smoke), §6.5.1-6.5.4 (CFO gate, timing, narration, subprocess-reuse). FR2.1-FR2.10 in spec.

**Deferred to PR-C:** Plan §6.8-6.11 (security smoke: prompt-injection drain, bash review-gate, cross-user prompt-response, 11-conversation rate limit) + manual visual-QA rubric (FR5). FR3.1-FR3.4 + FR5 in spec.

**Deferred to follow-up issues (already filed):**
- **#3746** — visual-regression baselines (`toHaveScreenshot()` infra). Re-evaluate if a visual regression actually ships.
- **#3747** — nightly real-SDK canary off PR-blocking path. Re-evaluate after PR-A/B/C all merge.
- **#3748** — standing CI gate `cc-router-stage-6-smoke` on cc-router-adjacent PRs. Re-evaluate after #2939 closes.

**Explicitly NOT folded:** #2220 (idFactory injection) — different layer (reducer purity, not WS injection). #2224 other line items (JSX indent, isDone param, bubble factory, state-required type) — out of PR-A scope.

## Cross-references

- Spec: `knowledge-base/project/specs/feat-cc-soleur-go-smoke-2939/spec.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-13-cc-soleur-go-stage-6-smoke-brainstorm.md`
- Parent plan (Stage 6 origin): `knowledge-base/project/plans/2026-04-23-feat-cc-route-via-soleur-go-plan.md` §369-415
- Phase 1 MCP-tier (recently merged): #3720
- Phase 2 MCP promotion (this unblocks): #3722
- Flag-retirement PR (the framing pivot): #3270
- Open code-review fold-in: #2224 (export StreamEvent line item)
- Deferred follow-ups: #3746, #3747, #3748
- Binding learnings:
  - `knowledge-base/project/learnings/2026-04-13-local-qa-auth-csrf-playwright-gaps.md` (DEV_ORIGINS port hardcoding)
  - `knowledge-base/project/learnings/2026-03-29-playwright-e2e-test-setup-for-nextjs-custom-server.md` (.e2e.ts, tsx, dummy Supabase env)
  - `knowledge-base/project/learnings/2026-05-04-cc-soleur-go-cutover-dropped-document-context-and-stream-end.md` (stream_end regression class — PR-A asserts chip removal on workflow_started, the actual reducer trigger)
  - `knowledge-base/project/learnings/2026-02-17-playwright-screenshots-land-in-main-repo.md` (absolute paths — N/A for PR-A, no screenshots)
  - `knowledge-base/project/learnings/2026-04-18-auth-gate-smoke-tests-enumerate-patterns.md` (enumeration-extend in same PR — sentinel-grep in Sharp Edges)
  - `knowledge-base/project/learnings/2026-05-13-brainstorm-grep-cited-flag-symbol-against-main-before-spawning-leaders.md` (just landed: brainstorm symbol-staleness check)
