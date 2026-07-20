# Tasks — fix(concierge): await the warm-dispatch re-clone gate (#5715)

lane: single-domain
brand_survival_threshold: single-user incident
Plan: `knowledge-base/project/plans/2026-06-29-fix-warm-dispatch-reclone-await-plan.md`

Test runner: `cd apps/web-platform && ./node_modules/.bin/vitest run` (NOT `bun test` — `bunfig.toml:11 pathIgnorePatterns=["**"]`). Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.

## Phase 0 — Preconditions (verify-before-code)

- [x] 0.1 Read the three C4 model files (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`); confirm the no-impact enumeration (operator actor `model.c4:9`, `claude -> github` edges `:215`/`:238` already present — no new element).
- [x] 0.2 Confirm seams: `runner.hasActiveQuery`/`hasActiveCcQuery` (`cc-dispatcher.ts:2372`), `__setCcRunnerForTests` (`:3759`), module-mocked `reprovisionWorkspaceOnDispatch` (`cc-dispatcher.test.ts:95`).
- [x] 0.3 Read `cc-reprovision.ts:50-104` + LEADER precedent `agent-runner.ts:1148` to fix the single-resolve refactor shape.

## Phase 1 — RED (write failing tests first; `cq-write-failing-tests-before`)

- [x] 1.1 Create `apps/web-platform/test/cc-dispatcher-warm-reclone-await.test.ts` using the `__setCcRunnerForTests({ hasActiveQuery: () => true, dispatch: vi.fn() })` seam + module-mocked `reprovisionWorkspaceOnDispatch`. Do NOT use the real-factory scaffold (never enters `dispatchSoleurGo`); do NOT use `invocationCallOrder`/`mockQuery` (green-on-main).
- [x] 1.2 Scenario 1 (AC1, load-bearing RED): deferred-promise `reprovisionWorkspaceOnDispatch`; after `flushMicrotasks()`, `expect(stubRunner.dispatch).not.toHaveBeenCalled()` — confirm this FAILS on current fire-and-forget code. Then resolve → `dispatch` called once (non-vacuity guard, mirror `agent-runner-reprovision.test.ts:277-281`).
- [x] 1.3 Scenarios 2–6: hot-path `.git`-present (real tmpdir, unmocked `existsSync`, no clone), cold inert, AC9 fail-safe (throw → mirror + dispatch still runs), AC10 `"failed"` short-circuit (honest message + no dispatch; `"ok"` → dispatch), AC11 path-unresolved breadcrumb.

## Phase 2a — GREEN Part A (`apps/web-platform/server/cc-reprovision.ts`)

- [x] 2a.1 After the single `resolveActiveWorkspace` + `fetchUserWorkspacePath(userId, activeWorkspaceId)` resolve, add `existsSync(path.join(workspacePath, ".git"))` → early-return `"ok"` BEFORE `resolveInstallationId`/`getCurrentRepoUrl`/`resolveEffectiveInstallationId` + clone. Add `existsSync` import. Single resolve ⇒ probe path == clone path (closes divergence P1-1).
- [x] 2a.2 Update `cc-reprovision.test.ts`: add `existsSync` mock; assert the early-return skips install/repo resolves on `.git`-present, and still clones on `.git`-absent. Preserve all existing cases (resetFromClaim, db-error skip, fail-soft).

## Phase 2b — GREEN Part B (`apps/web-platform/server/cc-dispatcher.ts`)

- [x] 2b.1 Replace the fire-and-forget block (`:2899-2912`) with the warm gate: `if (runner.hasActiveQuery(conversationId)) { try { reprovisionOutcome = await reprovisionWorkspaceOnDispatch(userId); if (reprovisionOutcome === "failed") { sendToClient(...resolveWorktreeEnterFailedMessage("failed")); return; } } catch (err) { reportSilentFallback(..., op: "reprovision-on-dispatch-await"); /* fall through */ } } else { void reprovision(...).then().catch(reportSilentFallback ... op: "reprovision-on-dispatch-publish"); }`.
- [x] 2b.2 AC9: gate is self-contained (own try/catch, never rejects out of dispatch). AC10: `"failed"` short-circuit gated strictly on `"failed"` (never `"ok"`/`undefined`). AC12: cold arm keeps the real `.catch` mirror (no empty catch).
- [x] 2b.3 Run new suite + `cc-dispatcher*`/`soleur-go-runner*`/`agent-runner-reprovision`/`cc-reprovision` suites; fix mock blast-radius (real-FS-op learning 2026-06-15).

## Phase 3 — Secondary cleanup (remove invented #4826 attribution)

- [x] 3.1 `apps/web-platform/server/soleur-go-runner.ts:541` + `:2233` — replace `4826-session`/`#4826` with neutral phrasing ("no-git-checkout flail loop"). Comment-only.
- [x] 3.2 `plugins/soleur/skills/one-shot/SKILL.md:8` (body) — "the `#4826`-class flail" → "the missing-repo flail".
- [x] 3.3 `plugins/soleur/commands/go.md:31` (body) — "the Concierge `#4826` session hit" → "the Concierge no-repo session hit".
- [x] 3.4 AC7 grep: `grep -rn '4826' plugins/soleur/skills/one-shot/SKILL.md plugins/soleur/commands/go.md apps/web-platform/server/soleur-go-runner.ts` → zero (the `conversations-rail-connect-race.test.tsx` fixture "Fix Issue 4826" is out of scope).

## Phase 4 — Verify

- [x] 4.1 `cd apps/web-platform && ./node_modules/.bin/vitest run` (full suite green) + `./node_modules/.bin/tsc --noEmit`.
- [x] 4.2 AC sweep (AC1–AC12, AC7, AC8). PR body: `Closes #5715`.
