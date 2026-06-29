---
title: "fix(concierge): await the warm-dispatch re-clone gate before the agent runs"
type: bug-fix
issue: 5715
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
created: 2026-06-29
deepened: 2026-06-29
branch: feat-one-shot-warm-dispatch-reclone-await-5715
---

# fix(concierge): warm-dispatch re-clone is fire-and-forget — agent spawns into a `.git`-less workspace after reclaim

## Enhancement Summary (deepen-plan 2026-06-29)

Deepened with 4 parallel reviewers (architecture-strategist, silent-failure-hunter, test-design-reviewer, verify-the-negative grep). All 9 factual preconditions verified against the codebase (zero contradictions). The review folded in **two coupled P1 design corrections** and **four error-handling ACs**, and **rewrote the test seam** (the original `invocationCallOrder` assertion was green-on-main):

1. **P1 — single-resolve to close probe/clone path divergence.** The `.git` short-circuit moves INTO `reprovisionWorkspaceOnDispatch` so ONE membership-verified `resolveActiveWorkspace` result feeds both the `existsSync` stat and the clone (the LEADER precedent `agent-runner.ts:1148`). This closes a real strand bug on the `resetFromClaim` edge that an external `fetchUserWorkspacePath(userId)` probe (`:2812`, no reset) would have. **`cc-reprovision.ts` added to Files to Edit.**
2. **P1 — honest latency.** "Zero added latency" was false: a correct `.git` probe needs the membership resolve (~1-3 indexed reads) on every warm turn — the same cost the LEADER already pays every turn. The hot path skips only the install/repo/effective-install resolves + the clone + the 120s clone timeout.
3. **AC9–AC12** (silent-failure): self-contained gate try/catch; short-circuit dispatch on a genuine `"failed"` reclone (don't spawn the agent into a known-broken workspace); observable forced-slow-path; retained `.catch` mirrors.
4. **Test seam rewrite:** deferred-promise gate on `runner.dispatch` via `__setCcRunnerForTests` + `hasActiveQuery:()=>true` + module-mocked `reprovisionWorkspaceOnDispatch` — NOT `invocationCallOrder`/`mockQuery` (the warm path never re-invokes the factory; call-order ≠ resolution-order, so the original assertion passed on the unfixed code).

Guard placement, seam choice, and C4 no-impact were all confirmed sound.

🐛 **Bug fix.** Closes #5715.

## Overview

The **cold** Concierge dispatch path AWAITS a workspace re-clone before it constructs the bubblewrap sandbox / SDK `query()`. The **warm** path does not: it fires `reprovisionWorkspaceOnDispatch(userId)` fire-and-forget and immediately pushes the user's turn into the already-running SDK iterator. When a workspace is **reclaimed mid-conversation** (filesystem wiped, `.git` gone), the next warm turn's per-tool bwrap sandbox `chdir`s into a `.git`-less `/workspaces/<id>` **before** the (slow, full-repo, 120s-timeout) re-clone finishes. The agent then runs `git status` → `fatal: not a git repository`, and `/soleur:go` Step 0.0 honest-stops with "your workspace isn't ready."

**Fix:** gate the warm-dispatch agent start on the re-clone the same way the cold path already does — `await reprovisionWorkspaceOnDispatch(userId)` before `runner.dispatch(...)` on the warm path. The `.git` short-circuit lives INSIDE `reprovisionWorkspaceOnDispatch` (one membership-verified resolve feeds both the stat and the clone — the LEADER precedent `agent-runner.ts:1148`), so `.git`-present warm turns skip the clone + the 120s timeout (paying only the membership resolve the LEADER already pays every turn). See Proposed Fix Design for the single-resolve design and the honest-latency note.

Secondary (low): the Step 0.0 / one-shot honest-stop copy cites `#4826` as if it were a filed issue about this failure mode. #4826 is an unrelated nav-rail feature (`feat: nav-rail position resume`). Remove the invented issue attribution.

Live-verified on prod 2026-06-29: operator active workspace `754ee124-…` → `jikig-ai/soleur`, `repo_status='ready'`, synced 14:46; the 16:52 dispatch ran in `/workspaces/754ee124-…` with `.git` absent after a reclaim. **Not** the #5591 duplicate-workspace case (the operator's two workspaces point at different repos: solo→`chatte`, active→`soleur`).

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase reality | Plan response |
|---|---|---|
| `await ensureWorkspaceRepoCloned` at `cc-dispatcher.ts:1897` (cold path) | ✅ Confirmed at `:1897`, inside `realSdkQueryFactory`'s BYOK-lease body. Plus the awaited `resolveRepoReadinessWithSelfHeal` / `.git`-absent gate at `:1781-1877`. | Mirror this awaited contract on the warm path. |
| Warm path fires `void reprovisionWorkspaceOnDispatch(userId)` at `:2899` | ✅ Confirmed at `:2899-2912`, inside `dispatchSoleurGo` (def `:2640`), fire-and-forget, runs **before** `runner.dispatch` at `:3503`. | Convert to an awaited gate on warm turns when `.git` is absent. |
| `cc-reprovision.ts` documents the factory self-heal runs only on cold conversations | ✅ Confirmed at `cc-reprovision.ts:18-25`. The runner (`soleur-go-runner.ts:2492 dispatch`) calls `queryFactory` only on a cold turn (`!activeQueries.get(conversationId)`, `:2498-2520`); warm turns reuse the long-lived Query and skip the factory entirely. | Gate must live in `dispatchSoleurGo` (the warm path never re-enters the factory). |
| Honest-stop copy "fabricated 'issue #4826 was filed to prevent this failure mode'" | ⚠️ **Paraphrase.** The literal text is not that sentence. The actual fabrication is `#4826`-style attribution in 4 sites: `one-shot/SKILL.md:8` ("the `#4826`-class flail"), `commands/go.md:31` ("the Concierge `#4826` session"), `soleur-go-runner.ts:541` + `:2233` ("the 4826-session loop"). #4826 = `feat: nav-rail position resume` (unrelated, OPEN). | Remove the `#4826`/`4826-session` attributions; replace with neutral descriptions ("the missing-repo flail" / "the no-git-checkout loop"). No invented issue numbers. |
| Reclaim, not duplicate-workspace (#5591) | ✅ Issue body + #5591 correction comment confirm the two operator workspaces point at different repos. | Scope is timing/await only; no workspace-resolution change. |

**Premise Validation:** #5715 OPEN and matches the cited file:line evidence (verified by `grep` against the worktree). #4826 confirmed OPEN and unrelated (`gh issue view 4826` → nav-rail feature), validating the secondary cleanup. All cited symbols (`ensureWorkspaceRepoCloned`, `resolveRepoReadinessWithSelfHeal`, `reprovisionWorkspaceOnDispatch`, `hasActiveCcQuery`) exist on the branch. No stale premises.

## User-Brand Impact

**If this lands broken, the user experiences:** their Concierge turn either (a) still strands on `fatal: not a git repository` (fix ineffective), or (b) — the regression risk — the warm hot path now blocks on a clone/`existsSync`/DB round-trip on **every** warm turn, slowing or hanging every Concierge reply.

**If this leaks, the user's data / workflow is exposed via:** no new data-exposure vector. The re-clone target is already membership-verified (ADR-044 `resolveActiveWorkspace`); this change alters only *when* the existing recovery runs (await vs fire-and-forget), not *what* it resolves. The one safety invariant the fix must hold: re-clone only when `.git` is **absent** (never touch a present `.git` — that would destroy Start-Fresh work / un-pushed commits, per learning `2026-06-03-self-heal-on-brand-path-only-acts-on-safe-symptom.md`).

**Brand-survival threshold:** single-user incident — the Concierge dispatch path is the dogfooding operator's core workflow; a strand (or a hot-path hang) makes the product unusable for the single live user. `requires_cpo_signoff: true`; `user-impact-reviewer` runs at review time (review/SKILL.md conditional-agent block); deepen-plan's single-user-incident triad (data-integrity-guardian + security-sentinel + architecture-strategist) provides substantive review beyond style.

## Root Cause

`soleur-go-runner.ts dispatch()` (`:2492`) keys `activeQueries` by `conversationId`:

- **Cold** (`!state`, `:2498`): calls `deps.queryFactory` (`= realSdkQueryFactory`, `:2520`). The factory awaits the `.git`-absent self-heal (`:1781-1877`) and `ensureWorkspaceRepoCloned` (`:1897`) **before** `buildAgentQueryOptions` binds the sandbox `cwd` (`agent-runner-query-options.ts:149`) at `query()` construction.
- **Warm** (`state` exists, `:2659`): the factory is **never re-invoked**. The reused long-lived Query's bwrap sandbox spawns per-tool-call and `chdir`s into the bound `cwd`. After a reclaim that path is `.git`-less.

The bwrap mount + cwd are frozen at `query()` construction and re-bound per tool spawn — they are NOT re-derived from a mid-session repair (learning `2026-06-15-bash-bwrap-sandbox-mount-visibility-vs-cwd-persistence.md`). So the only correct place to guarantee `.git` for a warm turn is **before `runner.dispatch` lets the turn reach the sandbox** — and `reprovisionWorkspaceOnDispatch` (the warm-path recovery) is currently not awaited there.

## Proposed Fix Design

**[Revised post-deepen — see Deepen-Plan Review Synthesis at top.]** The deepen-plan architecture review showed that a *dispatch-level* `existsSync` probe with a separately-resolved path (a) re-introduces the `#4767`-class **second divergent resolve** the cold factory eliminated, because the dispatch-level `fetchUserWorkspacePath(userId)` (`:2812`) does NOT apply the membership reset that `reprovisionWorkspaceOnDispatch`'s internal `resolveActiveWorkspace` does (`cc-reprovision.ts:57-74`, `resetFromClaim`) — so on the reset-from-claim edge the probe path and the clone path diverge and a false `.git`-present short-circuit **strands the very turn we are fixing**; and (b) cannot be "zero added latency" because statting `.git` requires resolving the path first.

**Correct design — push the `.git` short-circuit INTO `reprovisionWorkspaceOnDispatch`, mirroring the LEADER precedent (`agent-runner.ts:1148`: resolve once → `if (!existsSync(join(workspacePath, ".git"))) await ensureWorkspaceRepoCloned`).** One membership-verified resolve feeds BOTH the stat and the clone — no second resolve, no divergence window.

1. **`cc-reprovision.ts` refactor:** after the existing single `resolveActiveWorkspace` + `fetchUserWorkspacePath(userId, activeWorkspaceId)` resolve, stat `.git` on that resolved path and **early-return `"ok"` when present — BEFORE the heavier `resolveInstallationId` / `getCurrentRepoUrl` / `resolveEffectiveInstallationId` chain + clone.** `ensureWorkspaceRepoCloned` already re-checks `.git` internally (`ensure-workspace-repo.ts:142`); this hoists the cheap discriminator earlier so the hot path skips the install/repo resolution AND the clone. The resolved path the stat used is exactly the path `ensureWorkspaceRepoCloned` would clone into — probe == clone by construction.

2. **`dispatchSoleurGo` gate** (replaces the fire-and-forget block at `:2899-2912`, before `runner.dispatch` at `:3503`):

```text
let reprovisionOutcome: ReprovisionOutcome | undefined;
if (runner.hasActiveQuery(conversationId)) {                 // WARM: factory did NOT run
  try {                                                       // AC9 — self-contained gate
    reprovisionOutcome = await reprovisionWorkspaceOnDispatch(userId);  // self-short-circuits on .git-present
    if (reprovisionOutcome === "failed") {                   // AC10 — definitively unrecoverable
      sendToClient(userId, { type: "error",
        message: resolveWorktreeEnterFailedMessage("failed") });        // honest reclaim copy
      return;                                                 // do NOT spawn the agent into a known-.git-less ws
    }
  } catch (err) {                                             // AC9 fail-safe: NEVER reject out of dispatch
    reportSilentFallback(err, { feature: "cc-dispatcher",
      op: "reprovision-on-dispatch-await", extra: { userId, conversationId } });
    // fall through to runner.dispatch (fail-safe)
  }
} else {                                                      // COLD: factory awaits the clone — unchanged
  void reprovisionWorkspaceOnDispatch(userId)
    .then(o => { reprovisionOutcome = o; })
    .catch(err => reportSilentFallback(err, { feature: "cc-dispatcher",   // AC12 — keep the mirror
      op: "reprovision-on-dispatch-publish", extra: { userId, conversationId } }));
}
```

Key properties (each is an AC below):

1. **Warm + `.git` absent → await the re-clone before `runner.dispatch`** (the fix). The turn cannot reach the sandbox until the clone resolves.
2. **Warm + `.git` present → reprovision self-short-circuits** after the membership-verified path resolve (skips install/repo resolution + clone). Safety invariant: a present `.git` is never re-cloned. NOTE — this is NOT zero added latency: the warm `.git`-present hot path now pays the membership-verified active-workspace path resolve (JWT-cached tenant client + the indexed `user_session_state`/workspace reads) that the old fire-and-forget added zero of. The expensive 120s clone is still skipped. This is the deliberate correctness↔latency trade at single-user-incident threshold (see Risks).
3. **Cold → unchanged** (factory owns the await before `query()` construction; cold LTFT preserved; fire-and-forget publish retained for the honest-message outcome). `runner.hasActiveQuery` is the existing warm/cold predicate (`hasActiveCcQuery` wraps it, `:2372`/`:2374`).
4. **Guard placement (learning `2026-06-14`):** the `.git`-absent branch RUNS the re-clone (await) then proceeds — never an early return that *skips* the recovery. The ONLY early return is on `"failed"` (AC10), the definitively-unrecoverable case, which the 2026-06-14 learning explicitly is NOT about (that learning protects *recoverable* conversations; `"failed"` means the recovery already ran and lost).
5. **`reprovisionOutcome` feeds the honest message** at `:3417` on the non-short-circuit paths; AC10 makes the warm-`"failed"` honest stop *deterministic* (no longer dependent on the agent tripping `git status` first).

**Probe == clone path identity (deepen-plan precedent-diff, Phase 4.4):** guaranteed structurally because the stat and the clone share `reprovisionWorkspaceOnDispatch`'s single `resolveActiveWorkspace` (with `resetFromClaim`) — no dispatch-level second resolve. Leader precedent `agent-runner.ts:1148`; cold-factory precedent `cc-dispatcher.ts:1781-1784`. The `#4767` divergence comment (`cc-dispatcher.ts:1788-1794`) is the anti-pattern this design avoids.

## Files to Edit

- **`apps/web-platform/server/cc-reprovision.ts`** (Part A — **added at deepen-plan, architecture review P1-1**) — move the `.git` short-circuit INTO `reprovisionWorkspaceOnDispatch`: after the single `resolveActiveWorkspace` + `fetchUserWorkspacePath(userId, activeWorkspaceId)` resolve, `existsSync(path.join(workspacePath, ".git"))` → early-return `"ok"` when present, BEFORE the `resolveInstallationId`/`getCurrentRepoUrl`/`resolveEffectiveInstallationId` chain + clone. `existsSync` import to add here (currently imported in `cc-dispatcher.ts:17`, not `cc-reprovision.ts`). Single resolve ⇒ probe path == clone path by construction.
- **`apps/web-platform/server/cc-dispatcher.ts`** (Part B) — replace the fire-and-forget reprovision block (`:2899-2912`) with the warm-gated `try/catch` await + `"failed"` short-circuit described above (in `dispatchSoleurGo`). Imports already present: `reprovisionWorkspaceOnDispatch` (`:60`), `sendToClient`, `resolveWorktreeEnterFailedMessage`, `runner.hasActiveQuery`.
- **`apps/web-platform/server/soleur-go-runner.ts`** — secondary cleanup only: replace the `#4826` / `4826-session` attributions in the comments at `:541` and `:2233` with neutral phrasing ("the no-git-checkout flail loop"). No logic change.
- **`plugins/soleur/skills/one-shot/SKILL.md`** — `:8` (Step 0 body, NOT the `description:` frontmatter at `:3` → no skill-budget impact): replace "the `#4826`-class flail" with "the missing-repo flail".
- **`plugins/soleur/commands/go.md`** — `:31` body: replace "the Concierge `#4826` session hit" with "the Concierge no-repo session hit".

## Files to Create

- **`apps/web-platform/test/cc-dispatcher-warm-reclone-await.test.ts`** — new regression suite (see Test Scenarios). Path under `test/` matches the vitest node include glob `test/**/*.test.ts` (`vitest.config.ts:44`). **Harness mirrors `cc-dispatcher.test.ts`** (the `__setCcRunnerForTests` seam at `cc-dispatcher.ts:3759` + the module-mocked `reprovisionWorkspaceOnDispatch` at `cc-dispatcher.test.ts:95`) — NOT the real-factory scaffold (`cc-dispatcher-warm-presandbox-mkdir.test.ts` drives `realSdkQueryFactory` directly and never enters `dispatchSoleurGo`, so it cannot exercise the warm gate). Carry over the non-vacuity guard from `agent-runner-reprovision.test.ts:277-281` ("both mocks MUST have fired").

## Open Code-Review Overlap

4 open `code-review` issues name `cc-dispatcher.ts` / `soleur-go-runner.ts`: **#3243** (arch: decompose cc-dispatcher.ts into modules — broad refactor), **#3242** (tool_use WS event lacks raw name field), **#3820** (safe-bash allowlist extension), **#4254** (template_id fixture drift). **Disposition: Acknowledge all** — none touches the warm-dispatch reclone/await path; each is a distinct concern with its own cycle. #3243 is a large structural refactor that this focused timing fix should not be folded into. The scope-outs remain open.

## Acceptance Criteria (Pre-merge / PR)

- [ ] **AC1 (fix — RED on main):** On a warm turn (`runner.hasActiveQuery → true`) with `.git` ABSENT, `runner.dispatch` is NOT called until the awaited `reprovisionWorkspaceOnDispatch` **resolves**. Asserted by a **deferred-promise gate** (test-design review): mock `reprovisionWorkspaceOnDispatch` to return a pending deferred; after a microtask flush, `expect(stubRunner.dispatch).not.toHaveBeenCalled()` — this **fails on `origin/main`** (fire-and-forget → dispatch already fired) and passes only after the fix; then resolve the deferred and assert `dispatch` was called exactly once. (Do NOT assert via `invocationCallOrder`/`mockQuery`: the warm path never re-invokes the factory, and call-order ≠ resolution-order, so that assertion is green on the unfixed code.)
- [ ] **AC2 (hot path — `.git` present):** On a warm turn with `.git` PRESENT, `reprovisionWorkspaceOnDispatch` self-short-circuits after the membership resolve — `ensureWorkspaceRepoCloned`/the clone is NOT invoked, and `runner.dispatch` proceeds (the gate's await returns fast, no 120s clone). Use a real `.git`-present tmpdir fixture so the `existsSync` short-circuit runs unmocked.
- [ ] **AC3 (cold unchanged):** On a cold turn (`!hasActiveQuery`), the dispatch-level gate stays fire-and-forget (factory owns the await); the cold call sequence and LTFT are unchanged.
- [ ] **AC4 (safety invariant):** A present `.git` is never re-cloned/overwritten (only `.git`-absent triggers the clone), proven against a real `.git`-present dir.
- [ ] **AC5 (honest message intact):** `reprovisionOutcome` still routes `resolveWorktreeEnterFailedMessage` at `:3417`; a resolver error still maps to `"ok"`/generic (no false reclaim message).
- [ ] **AC9 (gate self-contained — silent-failure P0):** the entire warm gate is wrapped in its own `try/catch` (it sits BEFORE the `runner.dispatch` try at `:3502`). On any throw (`existsSync` EACCES/ELOOP, resolver throw, an unexpected reprovision throw) it calls `reportSilentFallback(err, { feature: "cc-dispatcher", op: "reprovision-on-dispatch-await", extra: { userId, conversationId } })` and **falls through to `runner.dispatch`** (fail-safe) — it never rejects out of `dispatchSoleurGo`. Test: make the awaited call throw; assert dispatch still runs AND the mirror fired.
- [ ] **AC10 (short-circuit on definitive failure — silent-failure P1):** warm + `.git`-absent + `reprovisionOutcome === "failed"` sends `resolveWorktreeEnterFailedMessage("failed")` (honest reclaim copy) and returns WITHOUT calling `runner.dispatch` — the agent is never spawned into a known-`.git`-less workspace. Gated STRICTLY on `"failed"` (never `"ok"`/`undefined`), so a recoverable conversation is never skipped (learning `2026-06-14`). Test: `"failed"` → no `runner.dispatch`, honest message sent; `"ok"` → dispatch proceeds.
- [ ] **AC11 (forced-slow-path observability — silent-failure P2):** when `reprovisionWorkspaceOnDispatch` cannot resolve the active workspace path (fail-soft internal `"ok"` with no clone), the path is observable — a distinct `reportSilentFallback` breadcrumb (e.g. `op: "reprovision-on-dispatch-await"`, `extra.reason: "workspace-path-unresolved"`) fires so a resolver outage forcing the slow path is queryable in Sentry, not silent.
- [ ] **AC12 (fire-and-forget arm keeps mirroring — silent-failure P2):** the retained COLD `void reprovision(...).then(...).catch(...)` arm preserves the real `.catch(err => reportSilentFallback(err, { feature: "cc-dispatcher", op: "reprovision-on-dispatch-publish", extra: { userId, conversationId } }))`. No empty catch. Grep-assert: zero `.catch(() => {})` / `.catch(() => undefined)` on the reprovision calls.
- [ ] **AC7 (no #4826 attribution):** `grep -rn '4826' plugins/soleur/skills/one-shot/SKILL.md plugins/soleur/commands/go.md apps/web-platform/server/soleur-go-runner.ts` returns zero issue-style `#4826`/`4826-session` references (the `conversations-rail-connect-race.test.tsx` fixture string "Fix Issue 4826" is a separate unrelated test fixture, out of scope).
- [ ] **AC8 (suite green):** `cd apps/web-platform && ./node_modules/.bin/vitest run` passes — INCLUDING the existing `dispatchSoleurGo`/`cc-reprovision` suites whose mocks must cover the new gate path (see Sharp Edges: real-FS-op blast radius). Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.

## Test Scenarios

New suite `cc-dispatcher-warm-reclone-await.test.ts` (vitest; `./node_modules/.bin/vitest run` — `bunfig.toml:11 pathIgnorePatterns=["**"]` blocks `bun test`). **Seam (test-design review):** force the warm branch deterministically with `__setCcRunnerForTests({ hasActiveQuery: () => true, dispatch: vi.fn(), ... })` (`cc-dispatcher.ts:3759`); module-mock `reprovisionWorkspaceOnDispatch` (the awaited call — NOT its internal `ensureWorkspaceRepoCloned`). Reject "drive twice on one conversationId" (flaky — first dispatch spawns a background `consumeStream`) and "pre-seed `activeQueries`" (module-private to the runner).

1. **warm + `.git` absent → dispatch gated on clone resolution (RED on main).** Mock `reprovisionWorkspaceOnDispatch` to return a `deferred()` promise. Kick off `dispatchSoleurGo` without awaiting; `await flushMicrotasks()`; `expect(stubRunner.dispatch).not.toHaveBeenCalled()` — **FAILS on main** (fire-and-forget fired dispatch already). Then `deferred.resolve("ok")`; `await` the dispatch promise + flush; `expect(stubRunner.dispatch).toHaveBeenCalledTimes(1)`. (Non-vacuity guard: assert dispatch DID fire after resolve, not only "not before".)
2. **warm + `.git` present → reprovision self-short-circuits (hot path).** Use a **real `.git`-present tmpdir** (create `<dir>/.git/`) and let `reprovisionWorkspaceOnDispatch`'s internal `existsSync` run **unmocked** (mock only the resolve-active-workspace inputs to point at the real dir); assert the clone (`ensureWorkspaceRepoCloned`) is NOT invoked and `stubRunner.dispatch` proceeds.
3. **cold → gate inert.** `hasActiveQuery: () => false`; assert the dispatch-level gate stays fire-and-forget (no await before `dispatch`); cold sequence unchanged.
4. **AC9 fail-safe:** make `reprovisionWorkspaceOnDispatch` throw → assert `reportSilentFallback` fired (`op: reprovision-on-dispatch-await`) AND `stubRunner.dispatch` still ran (no throw out of dispatch).
5. **AC10 short-circuit on `"failed"`:** mock `reprovisionWorkspaceOnDispatch → "failed"` → assert `sendToClient` got `resolveWorktreeEnterFailedMessage("failed")` AND `stubRunner.dispatch` was NOT called. Counter-case: `"ok"` → dispatch IS called.
6. **AC11 forced-slow-path breadcrumb:** path-unresolved fail-soft → assert the distinct `reportSilentFallback` breadcrumb fired.

Follow `cq-write-failing-tests-before` (RED before GREEN — scenario 1's `not.toHaveBeenCalled()` after flush is the load-bearing RED). Use a **real `.git`-present vs reclaimed tmpdir** (à la `cc-dispatcher-warm-presandbox-mkdir.test.ts reclaimedWorkspacePath()`) for scenarios 2/4 so the `existsSync` discriminator is genuine, not a mocked tautology.

## Observability

```yaml
liveness_signal:
  what: warm-dispatch reclone gate fires on every warm Concierge turn with `.git` absent (request-driven, no separate heartbeat)
  cadence: per warm dispatch
  alert_target: Sentry (existing repo-resolver-divergence / reprovision-on-dispatch fingerprints)
  configured_in: apps/web-platform/server/cc-dispatcher.ts (dispatchSoleurGo gate) + cc-reprovision.ts
error_reporting:
  destination: Sentry via reportSilentFallback (feature "cc-dispatcher", op "reprovision-on-dispatch" / new "reprovision-on-dispatch-await")
  fail_loud: gate errors are fail-soft (await fallback / generic message) but ALWAYS mirrored (cq-silent-fallback-must-mirror-to-sentry); a genuine clone "failed" surfaces the honest reclaim message to the user
failure_modes:
  - mode: re-clone genuinely fails on warm-absent
    detection: reprovisionOutcome === "failed"
    alert_route: honest "workspace reclaimed" client message (resolveWorktreeEnterFailedMessage) + Sentry (ensure-workspace-repo "failed" mirror)
  - mode: active-workspace path / existsSync probe error
    detection: catch in gate
    alert_route: reportSilentFallback (cc-dispatcher) + fail-safe await
  - mode: gate await hangs (clone 120s timeout)
    detection: existing runner runaway / dispatch catch
    alert_route: rides existing dispatch error envelope (no new dark path)
logs:
  where: pino structured logs in cc-dispatcher (existing Concierge dispatch breadcrumbs)
  retention: Better Stack (standard app log retention)
discoverability_test:
  command: "Sentry issue search: feature:cc-dispatcher op:reprovision-on-dispatch (no ssh)"
  expected_output: reprovision/clone-failure events queryable without host access (hr-no-ssh-fallback-in-runbooks)
```

## Architecture Decision (ADR / C4)

**No new architectural decision.** This bug fix closes a timing gap in the EXISTING cold/warm self-heal design already documented in `cc-reprovision.ts:18-25` and ADR-044 (workspace repo ownership) / ADR-051 (Concierge sandbox egress). It introduces no new substrate, ownership boundary, resolver, or trust boundary — it makes the warm path honor the same await contract the cold path already has. **Note for reviewers (architecture review):** Part A changes `reprovisionWorkspaceOnDispatch`'s internal control flow (adds the `.git` short-circuit before the clone-input resolves) — a refactor of an existing component, NOT a new element. The diff spans `cc-reprovision.ts` + `cc-dispatcher.ts`, not `cc-dispatcher.ts` alone; this is expected, not scope creep.

**C4 — no impact (enumeration, all three model files read: `model.c4`, `views.c4`, `spec.c4`).** Checked for the elements a timing fix could plausibly add: (a) **external human actor** — the workspace Owner/operator is already modeled (`model.c4:9`); no new correspondent/recipient. (b) **external system** — GitHub is already modeled with the git-clone edges `claude -> github "Git operations"` (`:238`) and `engine -> github` (`:215`); no new vendor. (c) **container/data-store** — the workspace filesystem is unchanged; no new store. (d) **actor↔surface access relationship** — unchanged (the Concierge→workspace clone relationship already exists; this fix changes only its *timing*, not who-resolves-what). Phase 0 task: a final read-confirm of the three `.c4` files; an unsupported "None" is rejected, so this enumeration is the citation. No `view include` edit needed.

## Domain Review

**Domains relevant:** none — engineering reliability bug fix (server TS + skill/command docs, no UI surface). Mechanical UI-surface override did not fire (no `components/**`, `app/**/page.tsx`, or UI-surface path in Files to Edit/Create). Product/UX Gate: NONE.

## Implementation Phases

- **Phase 0 — Preconditions (verify-before-code):** read the three `.c4` files (confirm no-impact enumeration above); confirm `runner.hasActiveQuery`/`hasActiveCcQuery` (`:2372`) and `__setCcRunnerForTests` (`:3759`) seams; read `cc-reprovision.ts:50-104` + `agent-runner.ts:1148` (LEADER precedent) to confirm the single-resolve refactor shape.
- **Phase 1 — RED:** add `cc-dispatcher-warm-reclone-await.test.ts` scenarios 1–6 via the `__setCcRunnerForTests` + module-mocked-reprovision seam; confirm scenario 1 (`dispatch not called after flush while deferred pending`) fails on the current fire-and-forget code.
- **Phase 2a — GREEN (Part A, `cc-reprovision.ts`):** hoist the `.git` `existsSync` short-circuit before the install/repo resolves + clone (single resolve feeds both stat and clone). Update `cc-reprovision.test.ts` for the new early-return + `existsSync` mock.
- **Phase 2b — GREEN (Part B, `cc-dispatcher.ts`):** implement the warm gate (try/catch await + `"failed"` short-circuit) replacing `:2899-2912`. Run the new suite + `cc-dispatcher*`/`soleur-go-runner*`/`agent-runner-reprovision`/`cc-reprovision` suites (blast-radius).
- **Phase 3 — Secondary cleanup:** remove `#4826`/`4826-session` attributions in the 4 sites; AC7 grep.
- **Phase 4 — Verify:** full `./node_modules/.bin/vitest run` + `./node_modules/.bin/tsc --noEmit`; AC sweep (AC1–AC12 + AC7/AC8).

## Risks & Sharp Edges

- **Real-FS-op blast radius (load-bearing):** adding an awaited recovery (and, in `cc-reprovision.ts`, an earlier `existsSync`) to the warm dispatch path will ripple into the many existing `dispatchSoleurGo`/`cc-reprovision` suites (`cc-dispatcher*.test.ts`, `cc-reprovision.test.ts`, `ws-handler-cc-*`). Learning `2026-06-15-real-fs-op-in-agent-startup-path-breaks-unmocked-tests.md`: a prior unconditional FS op on this startup path broke 95 tests across 17 suites. Every warm-path suite must mock `reprovisionWorkspaceOnDispatch` (already module-mocked in `cc-dispatcher.test.ts:95`); `cc-reprovision.test.ts` must add an `existsSync` mock for the new early short-circuit. Budget Phase 2 for cross-suite mock updates.
- **`.git`-present = SAFE symptom only:** the warm gate must NEVER re-clone a present `.git` (learnings `2026-06-03-self-heal-on-brand-path-only-acts-on-safe-symptom.md`, `2026-06-16-diverged-clone-recovery-branch-aside-before-reset.md`). `existsSync('.git') → skip` is a safety invariant, not just a latency optimization. (A `.git`-present-but-*diverged* clone is explicitly out of scope here — the recovery primitives are `.git`-absent-gated by design; do not widen the gate to diverged clones in this PR.)
- **Guard placement:** the `.git`-absent branch RUNS the re-clone (await) then proceeds — it must not early-return to *skip* dispatch (learning `2026-06-14-short-circuit-guard-must-sit-after-the-recovery-it-gates.md`); skipping would strand a resumed connected-repo conversation permanently.
- **Probe/clone path divergence (CLOSED by the single-resolve design — architecture review P1-1):** the `.git` stat and the clone MUST target the same membership-verified id. The original external-probe design (dispatch-level `fetchUserWorkspacePath(userId)` at `:2812`) is a DIFFERENT resolver that does NOT apply the `resetFromClaim` non-member reset (`cc-reprovision.ts:57-74`) — on the reset edge it diverges from the clone target and a false `.git`-present short-circuit strands the very turn being fixed. Part A closes this structurally: stat and clone share `reprovisionWorkspaceOnDispatch`'s ONE `resolveActiveWorkspace`. Do NOT re-introduce a dispatch-level second resolve (the `#4767`-class anti-pattern at `cc-dispatcher.ts:1788-1794`).
- **Hot-path latency is NOT zero (architecture review P1-2):** a correct `.git` probe requires the membership resolve, so warm `.git`-present turns pay `getFreshTenantClient` + `resolveActiveWorkspace` + one indexed `fetchUserWorkspacePath` read (~1-3 RTT) — but skip the install/repo/effective-install resolves + the 120s clone. This is the **same per-turn cost the LEADER `startAgentSession` already pays** (`agent-runner.ts:1148`), so the fix normalizes the two runtimes rather than adding a novel cost. The deliberate correctness↔latency trade is justified at single-user-incident threshold. Optional micro-opt: reuse the in-flight `:2812` resolve for the stat — but only as latency polish, never as the correctness source (it lacks `resetFromClaim`).
- **Dual warm/cold predicate read + TOCTOU (architecture review P2-1):** the warm decision is read as `runner.hasActiveQuery(conversationId)` in the dispatcher and `!activeQueries.get(conversationId)` inside the runner — one source of truth (the runner's `activeQueries`), so consistent; the TOCTOU window between the gate read and `runner.dispatch` (`:3503`) is benign for the single-user serial dispatch. Acknowledged, not guarded.
- **Security framing (architecture review P2-2):** the fix ADDS a resolution (the `.git` probe inside reprovision) but no access-widening — it reuses the same `userId`-scoped, membership-verified resolver; `existsSync` is a read-only stat. The genuine risk on this surface is the divergence/strand (correctness), not access. ("only timing changes" was imprecise — it adds a resolution with the same semantics.)
- **Frozen-cwd vs current-active on mid-conversation workspace switch (architecture review P2-3 — pre-existing, out of scope):** the warm sandbox `cwd` is frozen at the COLD `query()` construction (the active workspace at cold-start). The probe + reprovision resolve the CURRENT active workspace. On a mid-conversation workspace switch these differ; the live-verified incident (single workspace) does not surface it, and a timing fix should not change cwd-rebind semantics. Acknowledged.
- **`#4826` is a real OPEN issue** (`feat: nav-rail position resume`) — the cleanup must *remove the attribution*, not link to #4826. The `conversations-rail-connect-race.test.tsx` "Fix Issue 4826" fixture string is unrelated and out of scope.
- **`## User-Brand Impact` completeness:** this section is filled (threshold + artifact + vector); deepen-plan Phase 4.6 halts on an empty one.
