# Tasks: fix(test): close happy-dom ECONNREFUSED-on-127.0.0.1:3000 test-isolation gap

Derived from [plans/2026-05-20-fix-econnrefused-web-platform-test-isolation-plan.md](../../plans/2026-05-20-fix-econnrefused-web-platform-test-isolation-plan.md).

## Phase 0: Preconditions

- [ ] 0.1 Verify no pre-existing `beforeEach` in `apps/web-platform/test/setup-dom.ts`
  (`grep -nE 'beforeEach' apps/web-platform/test/setup-dom.ts` returns 0).
- [ ] 0.2 Verify no pre-existing `WebSocket` reference in setup-dom.ts
  (`grep -nE '\bWebSocket\b' apps/web-platform/test/setup-dom.ts` returns 0).
- [ ] 0.3 Confirm 3 known files override `globalThis.WebSocket`: `useWebSocket-abort.test.tsx`,
  `ws-client-resume-history.test.tsx`, `kb-chat-resume-hydration.test.tsx`.
- [ ] 0.4 Confirm vitest hook composition order via a throwaway 1-test fixture
  (delete after verifying).

## Phase 1: RED — Drift-Guard Test

- [ ] 1.1 Create `apps/web-platform/test/setup-dom-network-blockade.test.ts` with 5 assertions:
  - [ ] 1.1.1 Source contains `beforeEach` + `WebSocket` token + `Unmocked WebSocket construction in test` string.
  - [ ] 1.1.2 Source contains `beforeEach` + `fetch` token + `Unmocked fetch in test` string.
  - [ ] 1.1.3 Integration: `new WebSocket("ws://localhost:3000/ws")` throws `/Unmocked WebSocket construction/`.
  - [ ] 1.1.4 Integration: `fetch("/api/probe")` rejects with `/Unmocked fetch in test/`.
  - [ ] 1.1.5 Sanity: intra-test `vi.stubGlobal("fetch", ...)` override wins.
- [ ] 1.2 Run `cd apps/web-platform && npx vitest run test/setup-dom-network-blockade.test.ts` — expect RED.

## Phase 2: GREEN — Install Blockade

- [ ] 2.1 Edit `apps/web-platform/test/setup-dom.ts`:
  - [ ] 2.1.1 Add `beforeEach` import from `vitest`.
  - [ ] 2.1.2 Define `class BlockedWebSocket` whose constructor throws with URL + actionable message.
  - [ ] 2.1.3 Define `const blockedFetch: typeof fetch` that returns a rejected Promise with input + actionable message.
  - [ ] 2.1.4 Add `beforeEach` hook installing both stubs on `globalThis`.
  - [ ] 2.1.5 Preserve existing `afterAll` scrub block unchanged (`originalFetch`/`originalXHR` restore).
- [ ] 2.2 Re-run RED test — expect GREEN.

## Phase 3: Full-Suite Validation

- [ ] 3.1 `cd apps/web-platform && npx tsc --noEmit` → 0 errors.
- [ ] 3.2 Run 5× consecutive full suites: `for i in 1..5; do doppler run -p soleur -c dev -- npm test 2>&1 | tee /tmp/full-run-$i.log; done`.
- [ ] 3.3 Verify zero ECONNREFUSED matches across all 5 runs:
  `grep -c 'ECONNREFUSED.*127\.0\.0\.1:3000\|ECONNREFUSED.*localhost:3000' /tmp/full-run-{1,2,3,4,5}.log` → 5× `0`.
- [ ] 3.4 Verify all 5003 tests pass on each of the 5 runs (exit 0 per run).
- [ ] 3.5 If any leaky test surfaces (blockade error names it), add `vi.mock("@/lib/ws-client", ...)` or per-file `globalThis.WebSocket = MockWebSocket` to that file in this same PR.

## Phase 4: Cross-Suite Verification

- [ ] 4.1 `bash scripts/test-all.sh` → 64+ suites pass.

## Phase 5: Learning + Commit

- [ ] 5.1 Write `knowledge-base/project/learnings/<topic>.md`
  (topic: happy-dom WebSocket/fetch are real-network — install fail-loud blockade for deterministic test isolation).
- [ ] 5.2 Commit: plan + tasks + setup-dom.ts edit + drift-guard test + learning, with PR body `Closes #4155`.
- [ ] 5.3 Open PR (already created as draft #4158 — convert to ready when AC1-AC8 satisfied).
