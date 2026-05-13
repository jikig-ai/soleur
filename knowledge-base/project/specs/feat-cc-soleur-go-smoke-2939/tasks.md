---
title: Tasks — cc-soleur-go Stage 6 PR-A
date: 2026-05-13
issue: 2939
plan: knowledge-base/project/plans/2026-05-13-feat-cc-soleur-go-smoke-2939-pr-a-plan.md
spec: knowledge-base/project/specs/feat-cc-soleur-go-smoke-2939/spec.md
lane: cross-domain
brand_survival_threshold: single-user incident
status: tasks-complete
---

# Tasks: PR-A (bubble e2e foundations + DEV_ORIGINS multi-port fix)

TDD-structured. Each task: RED (failing test) → GREEN (smallest impl) → REFACTOR if needed. No commit until tests pass.

## Phase 0 — Preconditions (HARD GATE)

Block /work GREEN if any verification disagrees. Update plan + re-spawn plan-review.

- [ ] 0.1 Verify Playwright supports `routeWebSocket()`: `grep '"@playwright/test":' apps/web-platform/package.json` → expect `^1.58.2`
- [ ] 0.2 Verify `StreamEvent` union shape: `grep -n "type StreamEvent" apps/web-platform/lib/chat-state-machine.ts` → expect line 244
- [ ] 0.3 Verify WS endpoint path is `/ws`: `grep -n "/ws" apps/web-platform/lib/ws-client.ts` → expect line 496 with `${proto}://${host}/ws`
- [ ] 0.4 Verify mock fixtures: `grep -n "MOCK_USER\|MOCK_SESSION" apps/web-platform/e2e/mock-supabase.ts` → expect lines 12-37
- [ ] 0.5 Verify all 4 bubble data-* selectors per plan §Phase 0
- [ ] 0.6 Verify chip-removal trigger count: `grep -n "tool_use_chip" apps/web-platform/lib/chat-state-machine.ts` — both `case "stream_end"` (line 522) AND `case "workflow_started"` (line 716) must show filters. If count ≠ 2, extend FR1.3.

## Phase 1 — DEV_ORIGINS multi-port fix

### 1.1 Setup
- [ ] 1.1.1 `ls apps/web-platform/test/validate-origin.test.ts` — note whether file exists (RED creates if absent; otherwise extends)

### 1.2 RED — failing tests
- [ ] 1.2.1 Add test case: `NEXT_PUBLIC_DEV_EXTRA_ORIGINS="http://localhost:3099,http://localhost:3100"` + `NODE_ENV=development` → both URLs accepted (currently fails — env var not read)
- [ ] 1.2.2 Add regression test: empty `NEXT_PUBLIC_DEV_EXTRA_ORIGINS` + `NODE_ENV=development` → only `localhost:3000` + `https://app.soleur.ai` accepted
- [ ] 1.2.3 Add production-unchanged test: `NEXT_PUBLIC_DEV_EXTRA_ORIGINS="http://localhost:3099"` + `NODE_ENV=production` → 3099 rejected
- [ ] 1.2.4 Run `bun run vitest apps/web-platform/test/validate-origin.test.ts` → confirm 1.2.1 fails

### 1.3 GREEN — implementation
- [ ] 1.3.1 Edit `apps/web-platform/lib/auth/validate-origin.ts:10-14`: add `DEV_EXTRA` parser per plan Phase 1 sketch
- [ ] 1.3.2 Verify `https?://` regex prefix-check (no protocol-relative or malformed URLs sneak in)
- [ ] 1.3.3 Run vitest → all 3 new cases green
- [ ] 1.3.4 Run existing `validate-origin.test.ts` cases → still green (no regression)

### 1.4 Documentation
- [ ] 1.4.1 Append `NEXT_PUBLIC_DEV_EXTRA_ORIGINS` documentation block to `apps/web-platform/.env.example` (1-line description + example value `http://localhost:3099,http://localhost:3100`)

### 1.5 Commit
- [ ] 1.5.1 `git add apps/web-platform/lib/auth/validate-origin.ts apps/web-platform/test/validate-origin.test.ts apps/web-platform/.env.example`
- [ ] 1.5.2 Commit: `feat(auth): DEV_ORIGINS honors NEXT_PUBLIC_DEV_EXTRA_ORIGINS comma-list for Playwright multi-port (#2939)`

## Phase 2 — WS-injector helper

### 2.1 Fold-in #2224 (partial)
- [ ] 2.1.1 Edit `apps/web-platform/lib/chat-state-machine.ts:244` — change `type StreamEvent = ...` to `export type StreamEvent = ...` (1-token edit)
- [ ] 2.1.2 Run `bun tsc --noEmit` from `apps/web-platform/` → green

### 2.2 GREEN — helper implementation
- [ ] 2.2.1 Create `apps/web-platform/e2e/cc-soleur-go-ws-injector.ts` per plan Phase 2 sketch (~15-20 LoC)
- [ ] 2.2.2 Verify glob `"**/ws"` matches the Playwright baseURL-relative path (cross-reference Phase 0.3)
- [ ] 2.2.3 No separate unit test — `tsc --noEmit` + 4 e2e tests in Phase 3 are the effective test (per plan-review)

### 2.3 Commit
- [ ] 2.3.1 `git add apps/web-platform/lib/chat-state-machine.ts apps/web-platform/e2e/cc-soleur-go-ws-injector.ts`
- [ ] 2.3.2 Commit: `feat(e2e): export StreamEvent + add cc-soleur-go WS injector helper (#2939 #2224)`

## Phase 3 — Per-bubble Playwright e2e tests

Single file: `apps/web-platform/e2e/cc-soleur-go-bubbles.e2e.ts` (~250 LoC). Build incrementally; each sub-bubble's tests merge into the same file.

### 3.1 Shared test setup
- [ ] 3.1.1 Create the file with describe block + shared `setupAuth` helper (mirror `start-fresh-onboarding.e2e.ts:62-153`):
  - `page.addInitScript` BEFORE `page.route` mocks (per TR7)
  - `page.route("**/auth/v1/user"|"**/rest/v1/conversations*"|"**/rest/v1/messages*"|"**/realtime/**", ...)` — return `.single()`-compatible objects (per TR8)
  - Seed 1 conversation `id="conv-stage-6-smoke"` with `active_workflow="cc-router"`
  - `await attachWsInjector(page)`
  - `await page.goto("/dashboard/chat/conv-stage-6-smoke")`
- [ ] 3.1.2 Wire `page.on("pageerror", ...)` capture for the "no crash" assertion in 3.5

### 3.2 subagent-group expand-boundary (FR1.1)
- [ ] 3.2.1 RED: assert `[data-parent-spawn-id]` count = 1 after injecting 3× `subagent_spawn` (test fails initially — no injection yet)
- [ ] 3.2.2 GREEN: inject 3× `subagent_spawn(parentId="p-test-1", spawnId=...)` via `injector.send(...)`; assertion passes
- [ ] 3.2.3 Add 2× injection sub-case (different `parentId`) → assert `[data-expanded="true"]` (auto-expand boundary)
- [ ] 3.2.4 Run `bun playwright test --project=authenticated cc-soleur-go-bubbles.e2e.ts -g "subagent-group"` → green

### 3.3 interactive-prompt-card resolved-state (FR1.2)
- [ ] 3.3.1 RED: assert `[data-prompt-id="pid-test-1"][data-prompt-kind="ask_user"]` visible (fails initially)
- [ ] 3.3.2 GREEN: inject `interactive_prompt(kind="ask_user", promptId="pid-test-1", options=[{id:"a"},{id:"b"},{id:"c"}], multi_select=true)`
- [ ] 3.3.3 Read `apps/web-platform/test/interactive-prompt-card-resolved.test.tsx` to confirm resolved-state selector form; add resolution event + assertion (selectedIds=["a","c"], `aria-checked="true"` on multi-select checkboxes)
- [ ] 3.3.4 Run `-g "interactive-prompt-card"` → green

### 3.4 workflow-lifecycle-bar chip-removal — BOTH paths (FR1.3)
- [ ] 3.4.1 RED: test 3.4a assert chip present after `tool_use(cc_router, label)` (fails initially)
- [ ] 3.4.2 GREEN 3.4a (`tool_use → workflow_started`): inject sequence per plan §3.3a; assert chip removed + lifecycle-bar active + lifecycle-bar ended
- [ ] 3.4.3 GREEN 3.4b (`tool_use → stream_end`): fresh page or reset state; inject `tool_use → stream_end(leaderId="cc_router")`; assert chip removed
  - Verify required fields on `stream_end` via Phase 0.6 grep against `chat-state-machine.ts:522-529`
- [ ] 3.4.4 Run `-g "workflow-lifecycle-bar"` → both sub-cases green

### 3.5 tool-use-chip unregistered-mcp-fqn render (FR1.4)
- [ ] 3.5.1 RED: assert `[data-tool-chip-id^="cc_router-mcp__soleur_platform__test_synthesized_smoke-"]` count = 1 (fails initially)
- [ ] 3.5.2 GREEN: inject `tool_use(leaderId="cc_router", label="mcp__soleur_platform__test_synthesized_smoke")`; assertion passes
- [ ] 3.5.3 Confirm `pageerror` capture from 3.1.2 fired ZERO times (no-crash assertion)
- [ ] 3.5.4 Pre-commit check: `grep "test_synthesized_smoke" apps/web-platform/server/tool-tiers.ts` returns zero (synthesized FQN must NOT pollute the production tier registry — Sharp Edge)
- [ ] 3.5.5 Run `-g "tool-use-chip"` → green

### 3.6 Commit
- [ ] 3.6.1 `git add apps/web-platform/e2e/cc-soleur-go-bubbles.e2e.ts`
- [ ] 3.6.2 Commit: `feat(e2e): per-bubble Stage 6 regression assertions (#2939)`

## Phase 4 — Integration verification

### 4.1 Run all tests
- [ ] 4.1.1 `bun run vitest apps/web-platform/test/validate-origin.test.ts` → green
- [ ] 4.1.2 `cd apps/web-platform && bun playwright test --project=authenticated cc-soleur-go-bubbles.e2e.ts` → all 4 bubble test groups green
- [ ] 4.1.3 `bun tsc --noEmit` from `apps/web-platform/` → green (verifies `export StreamEvent` consumers + `satisfies StreamEvent` call-sites)

### 4.2 Guard greps (Spec NG enforcement)
- [ ] 4.2.1 `grep -n "mcp__soleur_platform__plausible_" apps/web-platform/e2e/cc-soleur-go-bubbles.e2e.ts apps/web-platform/e2e/cc-soleur-go-ws-injector.ts` returns zero (NG4 / TR9)
- [ ] 4.2.2 `grep -n "ANTHROPIC_API_KEY\|claude-agent-sdk" apps/web-platform/e2e/cc-soleur-go-bubbles.e2e.ts apps/web-platform/e2e/cc-soleur-go-ws-injector.ts` returns zero (NG2)
- [ ] 4.2.3 `grep -rn "toHaveScreenshot" apps/web-platform/e2e/` returns no NEW matches vs `git diff main -- apps/web-platform/e2e/` (NG1)
- [ ] 4.2.4 `grep -n "withUserRateLimit\|authenticateAndResolveKbPath\|getUser" apps/web-platform/lib/auth/validate-origin.ts` returns zero (TR10 — no new auth primitive)

## Phase 5 — Ship handoff

- [ ] 5.1 Run `skill: soleur:compound` — capture any session learnings
- [ ] 5.2 Run `skill: soleur:ship` — PR-A title prefix: `feat(cc-soleur-go): Stage 6 PR-A — bubble e2e foundations + DEV_ORIGINS multi-port (#2939)`
- [ ] 5.3 PR body: `Closes #2939 (partial — PR-A of 3); Partially addresses #2224 (export StreamEvent line item only)`. Apply `semver:minor` label (new env var surface)
- [ ] 5.4 Append "PR-A scope" note to #2939 body referencing this plan + listing PR-B/PR-C as follow-ups

## Phase 6 — Post-merge (operator)

- [ ] 6.1 (operator decision, no automation) Schedule PR-B planning within 7 days. Either keep `feat-cc-soleur-go-smoke-2939` branch open OR cut `feat-cc-soleur-go-smoke-2939-pr-b` at PR-A merge time (preferred — avoids 3-PR-on-1-branch confusion).
