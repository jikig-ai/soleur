# Tasks: fix(test): close happy-dom ECONNREFUSED-on-127.0.0.1:3000 test-isolation gap

Derived from [plans/2026-05-20-fix-econnrefused-web-platform-test-isolation-plan.md](../../plans/2026-05-20-fix-econnrefused-web-platform-test-isolation-plan.md).

## Phase 0: Preconditions

- [x] 0.1 Verify no pre-existing `beforeEach` in `apps/web-platform/test/setup-dom.ts`
  (`grep -nE 'beforeEach' apps/web-platform/test/setup-dom.ts` returns 0).
- [x] 0.2 Verify no pre-existing `WebSocket` reference in setup-dom.ts
  (`grep -nE '\bWebSocket\b' apps/web-platform/test/setup-dom.ts` returns 0).
- [x] 0.3 Confirm 3 known files override `globalThis.WebSocket`: `useWebSocket-abort.test.tsx`,
  `ws-client-resume-history.test.tsx`, `kb-chat-resume-hydration.test.tsx`.
- [x] 0.4 Confirm vitest hook composition order — accepted deepen-plan empirical verification
  (vitest 3.2.4, the pinned version) per plan §Implementation Phases Phase 0.

## Phase 1: RED — Drift-Guard Test

- [x] 1.1 Create `apps/web-platform/test/setup-dom-network-blockade.test.tsx` with 5 assertions
  (`.tsx` extension routes to component project where setup-dom loads):
  - [x] 1.1.1 Source contains `beforeEach` + `WebSocket` token + `Unmocked WebSocket construction in test` string.
  - [x] 1.1.2 Source contains `beforeEach` + `fetch` token + `Unmocked fetch in test` string.
  - [x] 1.1.3 Integration: `new WebSocket("ws://localhost:3000/ws")` throws `/Unmocked WebSocket construction/`.
  - [x] 1.1.4 Integration: `fetch("/api/probe")` rejects with `/Unmocked fetch in test/`.
  - [x] 1.1.5 Sanity: intra-test `vi.stubGlobal("fetch", ...)` override wins.
- [x] 1.2 RED confirmed — 4/5 fail without blockade; `fetch()` failure literally reproduces
  the ECONNREFUSED bug (`connect ECONNREFUSED 127.0.0.1:3000`).

## Phase 2: GREEN — Install Blockade

- [x] 2.1 Edit `apps/web-platform/test/setup-dom.ts`:
  - [x] 2.1.1 Add `beforeEach` import from `vitest`.
  - [x] 2.1.2 Define `class BlockedWebSocket` whose constructor throws with URL + actionable message.
  - [x] 2.1.3 Define `const blockedFetch: typeof fetch` that returns a rejected Promise with input + actionable message.
  - [x] 2.1.4 Add `beforeEach` hook installing both stubs on `globalThis`.
  - [x] 2.1.5 Preserve existing `afterAll` scrub block unchanged (`originalFetch`/`originalXHR` restore).
- [x] 2.2 GREEN — all 5 drift-guard tests pass.

## Phase 3: Full-Suite Validation

- [x] 3.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` → 0 errors.
- [x] 3.2 Ran 5× consecutive full suites (`/tmp/full-run-v2-{1..5}.log`).
- [x] 3.3 Zero ECONNREFUSED matches across all 5 runs (0/0/0/0/0).
- [x] 3.4 All runs exit 0; 4882 tests pass per run (was 4863 pre-fix +
  19 false-positives caught by initial unconditional blockade — fixed by
  switching blockade install to **conditional**: only overwrite when current
  global is happy-dom's pristine reference or the blockade itself; preserves
  module-init `vi.stubGlobal("fetch", mockFetch)` patterns in 4 files —
  `team-names-hook.test.tsx`, `display-format.test.tsx`,
  `team-settings.test.tsx`, `chat-input-attachments.test.tsx` — that the plan's
  Risks §"vi.stubGlobal at module-init" missed because it only audited `.test.ts`,
  not `.test.tsx`).
- [x] 3.5 No leaky tests required per-file mocks; conditional install
  preserves existing patterns transparently.

## Phase 4: Cross-Suite Verification

- [x] 4.1 `bash scripts/test-all.sh` → 64/64 suites pass.

## Phase 5: Learning + Commit

- [x] 5.1 Wrote `knowledge-base/project/learnings/2026-05-20-happy-dom-ws-fetch-blockade.md`.
- [ ] 5.2 Commit: plan + tasks + setup-dom.ts edit + drift-guard test + learning, with PR body `Closes #4155`.
- [ ] 5.3 Open PR (already created as draft #4158 — convert to ready when AC1-AC8 satisfied).
