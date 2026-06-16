---
title: "fix: ensure workspace dir exists pre-sandbox on warm dispatch (CWD-doesn't-exist after reclaim)"
date: 2026-06-15
type: fix
branch: feat-one-shot-warm-reprovision-ensure-dir-presandbox
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: single-domain
issue: 5240
parent_epic: 5240
related_pr: 5367
---

# fix: unconditionally ensure `workspacePath` exists BEFORE bwrap sandbox construction (Concierge + leader)

🐛 **Bug class:** post-reclaim recovery gap — the only mkdir that re-creates a reclaimed workspace dir is **conditionally gated** (skipped for not-connected and `.git`-present workspaces), so the bwrap sandbox (CWD = `workspacePath`) is constructed against a non-existent dir whenever the connected-repo self-heal short-circuits.

## Enhancement Summary

**Deepened on:** 2026-06-15
**Sections reshaped:** Overview, Research Reconciliation, Acceptance Criteria, Files to Edit, Files to Create, Test Scenarios, Risks, Sharp Edges (+ new Research Insights)
**Agents used:** architecture-strategist, spec-flow-analyzer, verify-the-negative grep pass (sonnet)

### Key Improvements
1. **Relocated the fix** from `dispatchSoleurGo` (guards the wrong `workspacePath` value — `args.workspacePath` is NOT what the sandbox binds) into `realSdkQueryFactory` after its own `:1315` resolve, so guaranteed-path === bound-path by construction, zero added RTT.
2. **Re-diagnosed the root cause** from "fire-and-forget ordering race" to "conditional mkdir skips not-connected / `.git`-present" — the factory already awaits its mkdir, so the genuine gap is the `ensure-workspace-repo.ts:85`/`:89` early-returns.
3. **Re-spec'd AC1** from a proxy (mocked-call ordering, GREEN on `main`) to the invariant (real-tmpdir `existsSync(boundPath)` at sandbox-construction, RED on `main`, not-connected fixture).
4. **Fixed AC6's unsafe fail-soft** — surface the honest/retryable envelope on mkdir failure rather than silently building a doomed sandbox.
5. **Defaulted leader-path parity to fold-in** (AC8) — `agent-runner.ts` shares the same conditional-mkdir gap.

### New Considerations Discovered
- The not-connected reclaimed workspace was a silently-dropped failure slice in the original plan (no clone, no honest message, no recovery).
- `buildAgentQueryOptions` is synchronous + drift-snapshot-guarded → folding the mkdir there is a non-trivial async conversion; two call-site mkdirs chosen instead.

> **[Updated 2026-06-15 — deepen-plan correction].** The original framing ("fire-and-forget ordering race on the warm path; fix with an awaited mkdir in `dispatchSoleurGo` before `runner.dispatch`") was **structurally wrong** and was corrected after architecture-strategist (P1) + spec-flow-analyzer (P0-1, P0-2, P1-1, P1-3) both independently found, code-verified, that (a) the bwrap sandbox binds to the **factory's own independently-resolved** `workspacePath` (`cc-dispatcher.ts:1315→1800`), NOT `dispatchSoleurGo`'s `args.workspacePath` — so a `dispatchSoleurGo`-level mkdir guards the wrong variable; (b) on the cold-Query-construction branch the factory **already `await`s** `ensureWorkspaceRepoCloned` before the sandbox build, so there is no ordering race there; (c) the genuine RED-on-`main` defect is that `ensureWorkspaceRepoCloned` **early-returns at `:85` (not-connected) and `:89` (`.git` present) BEFORE reaching its mkdir at `:163`**, leaving a reclaimed-but-not-connected (or `.git`-present-but-dir-deleted) workspace with no dir re-creation at all. The corrected fix moves an **unconditional** awaited mkdir into each `query()`-construction site (`realSdkQueryFactory` + `agent-runner.ts`), using the factory's own resolved `workspacePath`, so the guaranteed path and the bound path are the same value by construction, with zero added RTT. See `## Research Insights` for the full agent findings.

## Overview

The Concierge / leader agent dead-ends with **"the configured CWD `/workspaces/<uuid>` doesn't exist on this machine"** / **"No Git repository found"** after a sandbox/host reclaim. The agent's entire turn is blocked for the affected user until manual intervention.

The mkdir-before-clone fix that shipped 2026-06-15 (PR #5367, `web-v` release 17:08) is deployed but **insufficient**. PR #5367 added `await mkdir(workspacePath, { recursive: true })` as the first statement of `realGraftRepoClone()` (`ensure-workspace-repo.ts:163`). That mkdir is only reached on the **connected-repo + `.git`-absent** path: `ensureWorkspaceRepoCloned` returns `"ok"` at `:85` (`installationId === null || !repoUrl` → **not connected**) and at `:89` (`existsSync(<workspacePath>/.git)` → **`.git` already present**) **before** it ever calls `realGraftRepoClone`. So for a reclaimed workspace that is **not connected to a repo**, or whose `.git` somehow survived while the rest of the dir was reclaimed, the mkdir never runs — neither on the awaited cold-factory call (`cc-dispatcher.ts:1450`) nor on the fire-and-forget warm reprovision (`cc-dispatcher.ts:2375`). The bwrap sandbox then `chdir`s into a non-existent dir → the reported symptom.

This is a **continuation / insufficiency of the same-day workspace-reprovision work** (#5339 / #5367), **not a regression** in it. PR #5367's conditional mkdir is correct *for the clone* (you only clone into a `.git`-absent connected workspace); the gap is that **dir-existence is a stronger precondition than clone-eligibility** — the sandbox needs the dir whether or not the workspace is connected. This plan adds an **unconditional** awaited dir-existence guarantee at the sandbox-construction sites, decoupled from clone-eligibility.

**Fix in one sentence:** add an **unconditional** `await mkdir(workspacePath, { recursive: true })` (dir-existence only — NOT the clone) at each `query()`-construction site — `realSdkQueryFactory` (`cc-dispatcher.ts`, after the factory's own `:1315` `workspacePath` resolve, before `buildAgentQueryOptions` at `:1799`) and the leader path (`agent-runner.ts`, after its `workspacePath` resolve, before `buildAgentQueryOptions` at `:1869`) — so the guaranteed path is **the same value the sandbox binds** (`agent-runner-query-options.ts:149` `cwd: args.workspacePath`), independent of `ensureWorkspaceRepoCloned`'s connected/`.git` early-returns; keep the existing clone + `reprovisionOutcome` publish for the honest "workspace reclaimed" message; preserve the `.git`-absent no-op clone guard.

### Why a bwrap sandbox needs the dir to pre-exist (code-verified)

- The agent runs inside an SDK **bubblewrap (`bwrap`) sandbox** whose **working directory is frozen once per SDK `query()` call**: `agent-runner-query-options.ts:149` sets `cwd: args.workspacePath`; `buildAgentQueryOptions({ workspacePath })` is consumed by `sdkQuery({ options })` at `cc-dispatcher.ts:1797` (Concierge) and `agent-runner.ts:1869` (leader). bwrap `chdir`s into that path at construction and **requires the directory to EXIST at sandbox-construction time**; when it cannot, it falls back to `$HOME` (`/home/soleur`) and the agent's CWD-verification gate can never pass. (Mount/CWD-vs-visibility background: `knowledge-base/project/learnings/2026-06-15-bash-bwrap-sandbox-mount-visibility-vs-cwd-persistence.md`.)
- After a sandbox/host reclaim, `workspacePath` resolves to a path whose directory has been **deleted out from under the process** — so sandbox construction sees a non-existent CWD.
- **The sandbox binds the FACTORY's own resolved path, not `args.workspacePath`.** On the Concierge path, `realSdkQueryFactory` independently re-resolves `workspacePath` via `fetchUserWorkspacePath(args.userId)` in its `Promise.all` (`cc-dispatcher.ts:1314-1315`) and passes *that* local into `buildAgentQueryOptions({ workspacePath })` at `:1799`. `args.workspacePath` (what `dispatchSoleurGo` threads at `:2944`) is used only for the system prompt, NOT the cwd bind. **Therefore the dir-existence guarantee MUST be placed where it sees the same resolved value the sandbox binds — inside the factory, after `:1315` — not in `dispatchSoleurGo`.**

### Warm vs. cold — which branch (re)constructs the sandbox

`SoleurGoRunner.dispatch` (`soleur-go-runner.ts:2469`) keys an `activeQueries` map by `conversationId`:

- **`if (!state)` branch (`soleur-go-runner.ts:2475`)** — *cold-Query construction*. `await deps.queryFactory(...)` (`:2497`) builds a fresh SDK `query()` via `realSdkQueryFactory`. This branch fires for a genuinely-new conversation **and** for a **warm-resume after a server-process / host reclaim** — the reclaim destroys the in-process `activeQueries` map, so the next dispatch in the fresh process hits `if (!state)` with `resumeSessionId`/`args.sessionId` seeded to resume the SDK transcript. In this branch the bwrap sandbox is (re)constructed; the factory's `query()` is awaited, so an unconditional mkdir *inside* the factory before `:1799` deterministically precedes the sandbox build. **This is the dominant reported path** (the same reclaim that deletes the dir drops the in-process Query). *Assumption (stated explicitly per architecture review):* the reclaim that deletes the dir is the same event that drops the in-process Query (host/process reclaim, not a selective dir deletion under a live process).
- **`else` branch (reused session, `queryReused = true`, `soleur-go-runner.ts:2620-2682`)** — only resets per-turn state and pushes the user message into the **still-alive** in-process Query via `pushUserMessage`; it does NOT call `deps.queryFactory` and does NOT rebuild the sandbox. A recursive mkdir cannot re-bind a live bwrap sandbox whose `cwd` was frozen on a now-deleted inode — that recovery is the session-checkpoint/restart path (#5356 / #5275). **Correctly scoped out** (see Non-Goals).

## Research Reconciliation — Spec vs. Codebase

| Premise (from feature description) | Codebase reality (verified on this branch) | Plan response |
| --- | --- | --- |
| Agent runs in a bwrap sandbox bound to `workspacePath` with `CWD=workspacePath`; bwrap needs the dir at construction time | `agent-runner-query-options.ts:149` `cwd: args.workspacePath` → `sdkQuery` at `cc-dispatcher.ts:1797` (Concierge) + `agent-runner.ts:1869` (leader); learning `2026-06-15-bash-bwrap-...` confirms cwd frozen per `query()` | Confirmed; **unconditional** mkdir must precede sandbox build at BOTH construction sites |
| Sandbox binds `args.workspacePath` (the value `dispatchSoleurGo` threads) | **FALSE** — the factory independently re-resolves its own `workspacePath` via `fetchUserWorkspacePath(args.userId)` (`cc-dispatcher.ts:1314-1315`) and binds *that* at `:1799`; `args.workspacePath` is system-prompt-only | **Corrected:** place the mkdir inside the factory after `:1315` (same resolved value the sandbox binds), NOT in `dispatchSoleurGo` |
| COLD path `cc-dispatcher.ts ~1452` awaits `ensureWorkspaceRepoCloned`, so cold recovers | Awaited at `cc-dispatcher.ts:1450` — BUT `ensureWorkspaceRepoCloned` early-returns at `:85` (not-connected) and `:89` (`.git` present) **before** its mkdir at `:163` | **Corrected:** "cold recovers" holds ONLY for connected + `.git`-absent. Not-connected / `.git`-present reclaimed dirs skip the mkdir even on the awaited cold path — this is the genuine RED-on-main gap |
| WARM path `cc-dispatcher.ts ~2375` fires `void reprovisionWorkspaceOnDispatch(userId)` fire-and-forget; the fix is to await before sandbox | `cc-dispatcher.ts:2375` is un-awaited — BUT on the cold-Query-construction branch the factory `await`s `query()`, so the factory's own mkdir (when reached) already precedes the sandbox; there is **no ordering race** there | **Corrected:** the bug is NOT a fire-and-forget *ordering* race; it is the *conditional* mkdir skipping not-connected / `.git`-present. The fire-and-forget reprovision + clone + outcome publish are kept unchanged for the honest message |
| mkdir added 2026-06-15 lives inside `realGraftRepoClone` | `ensure-workspace-repo.ts:163` inside `realGraftRepoClone` (reached only past the `:85`/`:89` guards) | Confirmed; that conditional mkdir stays (clone safety); the new unconditional mkdir is the stronger dir-existence precondition |
| Bwrap can recover a reused-session sandbox after reclaim by re-creating the dir | bwrap cwd **frozen per `query()`**; the reused `else` branch (`soleur-go-runner.ts:2620-2682`) does NOT rebuild the sandbox | **Scope-out:** deterministically-recoverable case is cold-Query construction (`if (!state)`). A genuinely reused in-process sandbox whose host was reclaimed mid-session is already dead; recovery is session-checkpoint/restart (#5356/#5275). See Non-Goals. |

## User-Brand Impact

**If this lands broken, the user experiences:** the Concierge chat replies "the configured CWD `/workspaces/<uuid>` doesn't exist on this machine" / "No Git repository found" and every subsequent turn dead-ends — the agent is fully blocked for that user until an operator manually re-provisions the workspace.

**If this leaks, the user's workflow is exposed via:** N/A — this change creates no new data surface. It is a server-side `mkdir(workspacePath, { recursive: true })` on a server-resolved, membership-scoped path (`fetchUserWorkspacePath`, ADR-044) that is never request input. No PII, no new egress, no new persisted field.

**Brand-survival threshold:** single-user incident (the affected user's agent work is fully blocked until manual intervention).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (RED-first — dir-exists-at-bound-path, NOT-CONNECTED fixture).** A new test asserts that when `realSdkQueryFactory` runs against a **not-connected** workspace (`installationId === null` / `repoUrl` empty) whose dir has been reclaimed, the workspace dir **exists at the moment the bwrap sandbox is constructed**. This is genuinely RED on `main` (the not-connected workspace skips `realGraftRepoClone`'s mkdir via the `ensure-workspace-repo.ts:85` early-return, so no mkdir runs before `buildAgentQueryOptions` at `:1799`). The assertion checks the **invariant, not a proxy**: use a real tmpdir as `workspacePath`, `rm -rf` it to simulate reclaim, stub `buildAgentSandboxConfig`/`sdkQuery` to capture `existsSync(boundWorkspacePath)` **at invocation time**, and assert it is `true` after the fix (was `false` on `main`). A mocked-call-ordering assertion (`mkdir` index < `query` index) is INSUFFICIENT — it tests a proxy and goes GREEN on `main` for connected users. (`cq-write-failing-tests-before`.)
- [ ] **AC2 (unconditional — covers `.git`-present + connected too).** The mkdir is **unconditional** — it runs before sandbox construction regardless of `installationId`/`repoUrl`/`.git`-presence. A test asserts the dir is ensured for a `.git`-present-but-reclaimed-root fixture (which also skips `ensureWorkspaceRepoCloned`'s mkdir via the `:89` early-return) and for the connected path (idempotent on the already-mkdir'd dir).
- [ ] **AC3 (cold path / clone preserved).** Existing behavior is unchanged: `realSdkQueryFactory` still awaits `ensureWorkspaceRepoCloned` at `:1450`, and `realGraftRepoClone` still mkdirs first inside the clone. The new unconditional mkdir is additive and idempotent. Existing tests `cc-dispatcher-real-factory.test.ts`, `ensure-workspace-repo.test.ts`, `ensure-workspace-repo-graft-race.test.ts`, `cc-reprovision.test.ts` stay green.
- [ ] **AC4 (`.git`-absent no-op clone safety preserved).** The unconditional mkdir creates only the workspace **root** dir, never `.git`. A test asserts `existsSync(join(workspacePath,".git")) === false` immediately after the pre-sandbox mkdir on a fresh dir — so `ensureWorkspaceRepoCloned`'s `:89` `.git`-present no-op guard and the clone's `"failed"` outcome (which gates the honest message) are unperturbed. Recursive mkdir on an existing dir is idempotent (no throw, no clobber).
- [ ] **AC5 (clone + honest message preserved).** `void reprovisionWorkspaceOnDispatch(userId)` and the `reprovisionOutcome` publish (`cc-dispatcher.ts:2375-2388`) remain — the honest "workspace reclaimed" message branch (`onWorkflowEnded`, gated AFTER recovery per `2026-06-14-short-circuit-guard-must-sit-after-the-recovery-it-gates.md`) still fires on a genuine clone `"failed"`.
- [ ] **AC6 (fail-soft, but does NOT silently re-arm the bug).** A pre-sandbox mkdir failure (EACCES / EROFS / unexpected) is caught and mirrored to Sentry via `reportSilentFallback` (`cq-silent-fallback-must-mirror-to-sentry`). It MUST NOT throw an unhandled error. **BUT** it must NOT silently proceed to construct the sandbox against a still-non-existent dir — for the not-connected case there is no clone to recover and no clone-`"failed"` to surface the honest message, so silent-proceed reconstructs the exact original symptom with only a swallowed Sentry event. On mkdir failure, the turn surfaces a retryable/honest error envelope (the symptom is non-recoverable this turn) rather than building a sandbox guaranteed to fail. A bounded single retry of the mkdir before surfacing is acceptable.
- [ ] **AC7 (observability).** The mkdir-fail Sentry mirror carries `feature: "cc-dispatcher"` (Concierge) / `feature: "agent-runner"` (leader), a stable `op` (e.g. `ensure-workspace-dir-presandbox`), and `extra.userId` (hashed per the pino formatter), reachable from Sentry without SSH (`hr-no-ssh-fallback-in-runbooks`).
- [ ] **AC8 (leader-path parity — fold-in).** The same unconditional pre-sandbox mkdir is added to the leader path (`agent-runner.ts`, after its `workspacePath` resolve, before `buildAgentQueryOptions` at `:1869`), since the leader path shares the identical conditional-mkdir-skips-not-connected gap (`agent-runner.ts:1064` awaited `ensureWorkspaceRepoCloned` → same `:85`/`:89` early-returns). A test (or extension of `agent-runner-reprovision.test.ts`) asserts the leader path ensures the dir before its sandbox build for a not-connected reclaimed fixture. *(Default fold-in; scope-out only with an explicit per-path rationale + tracking issue — see Files to Edit.)*
- [ ] **AC9 (typecheck + suite).** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes; `cd apps/web-platform && ./node_modules/.bin/vitest run test/<new-file>.test.ts test/cc-dispatcher.test.ts test/cc-dispatcher-real-factory.test.ts test/cc-reprovision.test.ts test/agent-runner-reprovision.test.ts` passes.

### Post-merge (operator)

- [ ] **AC9.** `web-platform-release.yml` restarts the container on merge to main touching `apps/web-platform/**` (path-filtered `on.push`) — the PR merge IS the deploy. No separate operator restart step. Verify post-deploy via the deploy webhook (`deploy.soleur.ai/hooks/deploy-status`, read-only, HMAC + CF Access via Doppler `prd_terraform`) that the release shipped green. `Automation:` covered by existing release pipeline.

## Files to Edit

- **`apps/web-platform/server/cc-dispatcher.ts`** — in `realSdkQueryFactory`, add an **unconditional** `await mkdir(workspacePath, { recursive: true })` dir-existence guarantee **after the factory's own `workspacePath` resolve** (the `Promise.all` at `:1314-1315`) and **before** `buildAgentQueryOptions({ workspacePath })` at `:1799`. This uses the **same resolved value the sandbox binds** (closing the path-divergence finding) with **zero added RTT** (the factory already holds the value). Wrap in try/catch → `reportSilentFallback` (`feature:"cc-dispatcher"`, `op:"ensure-workspace-dir-presandbox"`) → on failure surface the retryable/honest error envelope rather than silently building a doomed sandbox (AC6). Import `mkdir` from `node:fs/promises`. Add a doc-comment: dir-existence is a STRONGER precondition than clone-eligibility (`ensureWorkspaceRepoCloned` early-returns for not-connected / `.git`-present), so this mkdir is unconditional and independent of the clone. **Do NOT add the mkdir in `dispatchSoleurGo`** — that resolves a *different* `workspacePath` value than the sandbox binds (see Overview + Reconciliation).
- **`apps/web-platform/server/agent-runner.ts`** *(leader-path parity — fold-in, AC8)* — add the identical unconditional `await mkdir(workspacePath, { recursive: true })` after the leader's `workspacePath` resolve and before `buildAgentQueryOptions` at `:1869`. The leader shares the same gap (awaited `ensureWorkspaceRepoCloned` at `:1064` → same `:85`/`:89` early-returns skip the mkdir for not-connected / `.git`-present). `feature:"agent-runner"`, same `op`. *(Scope-out only with an explicit per-path rationale + tracking issue; default is fold-in given the single-user-incident threshold and shared defect.)*
- **`apps/web-platform/test/cc-dispatcher-warm-presandbox-mkdir.test.ts`** *(new — see Files to Create)*.
- **`apps/web-platform/test/agent-runner-reprovision.test.ts`** *(extend)* — add the leader-path not-connected dir-ensure-before-sandbox assertion (AC8).

**Insertion-point precondition (verify at /work Phase 0, numbers may drift):**
- `git grep -n "fetchUserWorkspacePath\|buildAgentQueryOptions\|ensureWorkspaceRepoCloned" apps/web-platform/server/cc-dispatcher.ts` — confirm the factory `Promise.all` resolves `workspacePath` (~`:1314`), `ensureWorkspaceRepoCloned` is awaited (~`:1450`), and `buildAgentQueryOptions({ workspacePath })` is the sandbox-construction site (~`:1799`). The unconditional mkdir sits between the resolve and `buildAgentQueryOptions`.
- `git grep -n "fetchUserWorkspacePath\|buildAgentQueryOptions\|ensureWorkspaceRepoCloned" apps/web-platform/server/agent-runner.ts` — confirm the leader's resolve, the awaited `ensureWorkspaceRepoCloned` (~`:1064`), and `buildAgentQueryOptions` (~`:1869`).
- Confirm `ensure-workspace-repo.ts:85` (`installationId === null || !repoUrl` → `return "ok"`) and `:89` (`.git`-present → `return "ok"`) BOTH precede the mkdir at `:163` — this is the load-bearing gap the unconditional mkdir closes.

**Considered-and-rejected placement (`buildAgentQueryOptions` itself):** folding the mkdir into `buildAgentQueryOptions` (`agent-runner-query-options.ts:149`, the single place that reads `workspacePath` into `cwd`) would be one guard for both consumers — but that function is currently **synchronous** and drift-snapshot-guarded by `agent-runner-query-options.test.ts`; making it async is a non-trivial blast-radius change. Two call-site-adjacent awaited mkdirs are the pragmatic equivalent. Re-evaluate at /work if the async conversion turns out cheap.

## Files to Create

- **`apps/web-platform/test/cc-dispatcher-warm-presandbox-mkdir.test.ts`** — vitest, node env (matches `vitest.config.ts` `include: ["test/**/*.test.ts"]`). Mirror the hoisted-mock pattern in `cc-dispatcher-real-factory.test.ts` (invoke `realSdkQueryFactory` with a fully-typed `QueryFactoryArgs`). The assertion must check **dir-exists-at-bound-path**, NOT mocked-call ordering. Recommended shape:
  1. **RED-first (not-connected fixture):** stub `resolveInstallationId` → `null` (and/or `getCurrentRepoUrl` → empty) so `ensureWorkspaceRepoCloned` early-returns at `:85`. Use a **real tmpdir** as the resolved `workspacePath` (mock `fetchUserWorkspacePath` to return it), then `rm -rf` it to simulate reclaim. Stub `buildAgentSandboxConfig`/`sdkQuery` to record `existsSync(workspacePath)` **at the instant it is invoked**. Assert `true` after the fix (RED `false` on `main`).
  2. **`.git`-present fixture (AC2):** create the tmpdir then delete it but leave the resolver believing `.git` exists (stub the `existsSync(.git)` site) → `ensureWorkspaceRepoCloned` early-returns at `:89`; assert the dir is still ensured before sandbox build.
  3. **AC4:** assert `existsSync(join(workspacePath,".git")) === false` immediately after the pre-sandbox mkdir on a fresh dir.
  4. **AC6 fail-soft:** make `mkdir` reject → `reportSilentFallback` called with the AC7 shape AND the turn surfaces the retryable/honest envelope (does NOT proceed to build a doomed sandbox).

## Test Scenarios

| # | Scenario | Expected |
| --- | --- | --- |
| T1 (RED-first) | Factory runs, **not-connected** workspace, dir reclaimed | `existsSync(boundWorkspacePath)` is `true` at sandbox-construction time (RED `false` on `main`: not-connected skips clone mkdir) |
| T2 | `.git`-present-but-root-reclaimed (skips `:89`) | unconditional mkdir still ensures dir before sandbox build |
| T3 | Connected + `.git`-absent (clone-eligible) | mkdir idempotent (clone's own `:163` mkdir already covers it); dir present; no double-create harm |
| T4 | mkdir rejects (EACCES) | `reportSilentFallback({feature:"cc-dispatcher",op:"ensure-workspace-dir-presandbox",...})`; turn surfaces retryable/honest envelope; does NOT build a doomed sandbox; no unhandled throw |
| T5 | AC4 — `.git` not created by mkdir | `existsSync(<workspacePath>/.git) === false` right after pre-sandbox mkdir; clone's `.git`-no-op + `"failed"` honest-message path unperturbed |
| T6 | Cold path / clone unchanged | `realSdkQueryFactory` still awaits `ensureWorkspaceRepoCloned`; `realGraftRepoClone` still mkdirs first; existing tests green |
| T7 (leader) | Leader path, not-connected, dir reclaimed | `agent-runner.ts` ensures dir before its `buildAgentQueryOptions`/sandbox build (AC8) |
| T8 | Reused in-process session (`else` branch), host reclaimed mid-session | OUT OF SCOPE — sandbox not rebuilt; documented Non-Goal (#5356/#5275); no test asserts recovery here |

## Hypotheses

The feature description matches no network-outage trigger pattern (no SSH/connection-reset/handshake/502/timeout keywords; the symptom is a local-filesystem ENOENT on a bwrap CWD, not a network failure). Network-outage checklist not applicable.

Primary hypothesis (confirmed by code read, not just prose): the warm path's only dir-existence guarantee lives inside the un-awaited clone promise, so it races bwrap construction and loses. Confirmed against `cc-dispatcher.ts:2375` (fire-and-forget), `ensure-workspace-repo.ts:163` (mkdir inside `realGraftRepoClone`), `agent-runner-query-options.ts:149` (`cwd: workspacePath`), and the two same-day learnings.

## Risks & Mitigations

- **Risk (primary, from review): guarding the wrong `workspacePath` value.** An awaited mkdir placed in `dispatchSoleurGo` resolves a *different* path (`callerWorkspacePath ?? fetchUserWorkspacePath`) than the one the sandbox binds (the factory's own `:1315` resolve) — so a green test could ship while the production bug stays live whenever the two resolve a different active workspace. **Mitigation:** place the mkdir **inside the factory** after its own `:1315` resolve, so guaranteed-path === bound-path **by construction**. This is the corrected fix (see Files to Edit). Zero added RTT (the factory already holds the value), which also dissolves the "double-RTT" concern entirely.
- **Risk: not-connected reclaimed workspace silently re-arms the bug on fail-soft.** For a not-connected workspace there is no clone to recover and no clone-`"failed"` to surface the honest message, so a silently-proceeding mkdir failure reconstructs the exact original symptom with only a swallowed Sentry event. **Mitigation:** AC6 — on mkdir failure, surface the retryable/honest envelope (optionally one bounded retry first), never build a sandbox guaranteed to fail.
- **Risk: leader-path parity gap.** `agent-runner.ts` shares the **same conditional-mkdir-skips-not-connected gap** (NOT a fire-and-forget race — `startAgentSession` is fully awaited). **Mitigation:** AC8 + Files to Edit default the leader fix to **fold-in** (one PR, same shared defect); scope-out requires explicit rationale + tracking issue.
- **Risk: reused-session sandbox (genuine in-process reuse) bound to a dead inode.** A recursive mkdir cannot repair a live bwrap sandbox whose host was reclaimed mid-session (cwd frozen per `query()`; the `else` branch does not rebuild it). **Mitigation:** scoped out (Non-Goals) → session-checkpoint/restart (#5356/#5275). This fix covers the cold-Query-construction case (dominant path: reclaim drops the in-process Query → next dispatch re-enters `if (!state)`).
- **Precedent diff:** the unconditional-mkdir pattern mirrors `ensure-workspace-repo.ts:163` (PR #5367, the conditional clone-mkdir) and the signup path `workspace.ts:111` (`ensureDir(workspacePath)`). We inline the operative `mkdir(p,{recursive:true})` rather than importing `ensureDir` (whose symlink-rejection/TOCTOU contract is irrelevant here), exactly per the #5367 learning's corollary. No novel pattern. The *new* property vs. PR #5367: the mkdir is **unconditional** (dir-existence ⊋ clone-eligibility), at the **sandbox-construction site**, on **both** the Concierge and leader paths.

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open --json number,title,body` → none of the open scope-outs touch `cc-dispatcher.ts` / `ensure-workspace-repo.ts` / `cc-reprovision.ts`. Re-run the per-path `jq --arg path ...` check at /work Phase 0 to confirm before freezing.)

## Observability

```yaml
liveness_signal:
  what: existing web-platform deploy health (no new liveness surface added)
  cadence: per release (web-platform-release.yml)
  alert_target: existing Sentry/Better Stack deploy + /health monitors
  configured_in: apps/web-platform/infra (existing)
error_reporting:
  destination: Sentry via reportSilentFallback (cc-dispatcher feature)
  fail_loud: true  # mkdir-fail mirrors to Sentry AND throws a retryable error (AC6) — it must NOT silently proceed to build a sandbox against a non-existent CWD (that re-arms the symptom for the not-connected case, where there is no clone-"failed" to surface the honest message). The throw rides the caller's query()-construction catch → retryable envelope. (The fire-and-forget CLONE remains fail-soft; only this unconditional dir-ensure is fail-loud.)
failure_modes:
  - mode: pre-sandbox mkdir fails (EACCES/EROFS/unexpected)
    detection: reportSilentFallback({feature:"cc-dispatcher", op:"ensure-workspace-dir-presandbox", extra:{userId}})
    alert_route: Sentry cc-dispatcher feature tag (existing routing)
  - mode: clone still fails after dir ensured (token expired / repo gone)
    detection: existing ensureWorkspaceRepoCloned "failed" → reprovisionOutcome → honest "workspace reclaimed" message
    alert_route: Sentry ensure-workspace-repo feature tag (existing)
logs:
  where: pino structured logs (createChildLogger) + Sentry breadcrumbs; userId hashed by pino formatter
  retention: existing web-platform log retention (unchanged)
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/cc-dispatcher-warm-presandbox-mkdir.test.ts"
  expected_output: "all tests pass; invariant assertion green — workspace dir EXISTS at the bound cwd at sandbox-construction time (existsSync captured inside the sandbox-construction mock), for the not-connected reclaimed fixture (RED on main)"
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — server-side reliability fix on an already-provisioned surface (no new UI, no schema/migration, no auth flow change, no new vendor/infra/secret, no marketing/legal/finance/product surface). The `## User-Brand Impact` threshold is `single-user incident` → `requires_cpo_signoff: true` is set; CPO sign-off on the technical approach is required at plan time (carry forward from the #5240 epic framing if already covered, else invoke CPO). `user-impact-reviewer` will run at review time per the review-skill conditional-agent block.

## Infrastructure (IaC)

Not applicable — pure code change against an already-provisioned surface (`apps/web-platform/server/`). No new server, service, secret, vendor, DNS, cron, or persistent runtime process. Phase 2.8 trigger set not matched.

## Non-Goals

- **Repairing a genuinely reused in-process bwrap sandbox after a mid-session host reclaim.** The bwrap cwd is frozen per `query()`; a live sandbox bound to a deleted inode is not repaired by re-creating the path. That recovery is the session-checkpoint / restart path (#5356 / #5275). *Tracking:* covered by the existing #5240 epic + #5356; no new deferral issue needed (the reported symptom's dominant path is cold-Query-construction-on-warm-resume, which this fix covers). Re-confirm at /work whether a separate tracking issue is warranted.
- **Full-history / branch checkout clone.** The clone stays shallow (`--depth 1`) per the existing first-slice limitation; unchanged here.
- **Changing the honest "workspace reclaimed" message or its gating.** Preserved as-is.

## Research Insights

**Deepened 2026-06-15.** Two review agents (architecture-strategist, spec-flow-analyzer) + one verify-the-negative grep pass were run against the plan and the implementation files. Findings reshaped the fix.

**Key correction (P0/P1, both agents converged, code-verified):**

- **The bwrap sandbox binds the FACTORY's own resolved `workspacePath`, not `args.workspacePath`.** `realSdkQueryFactory`'s `Promise.all` at `cc-dispatcher.ts:1314-1315` calls `fetchUserWorkspacePath(args.userId)` and binds *that* local into `buildAgentQueryOptions` at `:1799`; `args.workspacePath` is system-prompt-only. The original plan's `dispatchSoleurGo`-level mkdir guarded the wrong variable. → Moved the mkdir inside the factory.
- **The real RED-on-`main` defect is the CONDITIONAL mkdir, not a fire-and-forget ordering race.** `ensureWorkspaceRepoCloned` returns `"ok"` at `:85` (not-connected) and `:89` (`.git` present) *before* `realGraftRepoClone`'s mkdir at `:163`. On the cold-Query-construction branch the factory *awaits* `query()`, so there is no ordering race — but the not-connected / `.git`-present reclaimed workspace skips the mkdir entirely on both the awaited cold path and the fire-and-forget warm path. → Fix is an **unconditional** mkdir at the sandbox-construction site.
- **AC1's original ordering test was a proxy and would be GREEN on `main`** for connected users. → Re-spec'd around the not-connected fixture + real-tmpdir `existsSync(boundPath)` at sandbox-construction (the invariant, not mocked-call order).
- **AC6's fail-soft was unsafe** — silently proceeding after an mkdir failure reconstructs the original symptom (no clone to recover, no `"failed"` honest message) for the not-connected case. → AC6 now surfaces the retryable/honest envelope (optional bounded retry) instead of building a doomed sandbox.
- **Leader path (`agent-runner.ts`) shares the gap** (awaited `ensureWorkspaceRepoCloned` at `:1064` → same `:85`/`:89` early-returns) but **NOT** a fire-and-forget race. → AC8 + Files to Edit default to fold-in.

**Verify-the-negative pass:** all 8 cited code anchors confirmed (factory awaits `ensureWorkspaceRepoCloned`; `:2375` is `void`-prefixed; `:2917` is `await runner.dispatch`; `agent-runner-query-options.ts:149` `cwd: args.workspacePath`; `ensure-workspace-repo.ts:163` mkdir first in graft; `:89` `.git` guard; reused `else` branch does NOT rebuild the sandbox; `:2288` fire-and-forget resolve). `dispatchSoleurGo` already carries `callerWorkspacePath` (`DispatchSoleurGoArgs.workspacePath` at `:2016`).

**Scope-out soundness:** the reused-in-process-sandbox scope-out is architecturally correct (bwrap cwd frozen per `query()`; `else` branch at `soleur-go-runner.ts:2620-2682` never calls `queryFactory`). The "dominant path is cold-Query-construction-on-warm-resume" claim is defensible under the stated assumption (reclaim drops the in-process Query AND deletes the dir in the same host/process-reclaim event).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This section is filled.)
- **Invariant test, not proxy test.** AC1's RED-first test MUST assert **the dir exists at the path the sandbox binds, at sandbox-construction time** (real tmpdir + `existsSync(boundPath)` checked inside the `buildAgentSandboxConfig`/`sdkQuery` mock). A mocked-call-ordering assertion (`mkdir` index < `query` index) is a **proxy** — it goes GREEN on `main` for connected users (the factory already awaits its mkdir before the sandbox) and cannot detect path-divergence. The genuinely-RED fixture is **not-connected** (`installationId=null`/empty `repoUrl`), which skips the clone mkdir via `ensure-workspace-repo.ts:85`.
- **Guard the bound value, not a sibling resolve.** The sandbox binds the factory's own `fetchUserWorkspacePath` resolve (`cc-dispatcher.ts:1315`), not `dispatchSoleurGo`'s `args.workspacePath`. Place the mkdir inside the factory (and the leader's `startAgentSession`) so guaranteed-path === bound-path by construction. A `dispatchSoleurGo`-level mkdir guards the wrong variable.
- **Unconditional, not clone-gated.** Dir-existence ⊋ clone-eligibility. `ensureWorkspaceRepoCloned` early-returns for not-connected (`:85`) and `.git`-present (`:89`) before its mkdir (`:163`); the new mkdir must run regardless of those conditions.
- **Don't await the clone.** Keep `void reprovisionWorkspaceOnDispatch(userId)` fire-and-forget — only the unconditional `mkdir` is awaited. Awaiting the ~120 s clone would block first-token (latency regression).
- **Line numbers drift.** `:85`, `:89`, `:163`, `:1064`, `:1315`, `:1450`, `:1797`/`:1799`, `:1869`, `:2288`, `:2375`, `:2917`, `:2944` are anchors from this branch's read (cc-dispatcher.ts is 3182 lines). Re-grep at /work Phase 0 (`git grep -n`) before editing — do not trust the numbers.
- **Phantom-test-path trap (from PR #5367 session error).** When an AC or tasks.md cites an explicit test-file path, `ls test/<file>` before trusting it — vitest silently runs only the files that match its arg list, so a typo'd path produces a false-green. Verify every cited test path exists. *(All six cited existing test files verified present during deepen-plan; the one new file correctly does not yet exist.)*
