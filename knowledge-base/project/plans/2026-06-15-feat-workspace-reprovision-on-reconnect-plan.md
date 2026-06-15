---
deepened: 2026-06-15
title: Deterministic workspace re-provision on reconnect (#5240 design item #2)
issue: 5340
epic: 5240
branch: feat-one-shot-5240-workspace-reprovision-reconnect
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
created: 2026-06-15
status: draft
---

# Deterministic workspace re-provision on reconnect

## Enhancement Summary

**Deepened on:** 2026-06-15
**Sections enhanced:** Files to Edit, Sharp Edges, Risks, Implementation Phases

### Key improvements from the deepen pass
1. **COLD-vs-WARM factory gap (load-bearing — caught at deepen).** The cc
   `realSdkQueryFactory` (and therefore both `ensureWorkspaceRepoCloned` at
   `:1469` AND the new `setReprovisionResult` publish) runs **only on a COLD
   conversation** — on warm-query reuse it is NOT re-invoked
   (`cc-dispatcher.ts:2336-2347`, the "FIX 6 warm-query posture" comment, which
   re-resolves `setBashAutonomous` per-dispatch *precisely because* the factory
   doesn't fire on warm turns). A reconnect that resumes a warm Query therefore
   never re-runs the re-provision. **Design response:** the re-provision +
   threaded result must follow the same per-dispatch fire-and-forget re-resolve
   pattern as `setBashAutonomous`/`debugPosture` (`:2348`), OR be explicitly
   scoped to cold turns with a documented rationale. See Sharp Edges.
2. **Two type-hops confirmed** for the new sink (`soleur-go-runner.ts:1006`
   runner-options interface AND `:1059` `QueryFactoryArgs`, forwarded at `:2516`)
   — mirror `setBashAutonomous` exactly.
3. **Name collisions checked:** `setReprovisionResult`, `ReprovisionOutcome`,
   `WORKSPACE_RECLAIMED_MESSAGE` are unused in `apps/web-platform/` — safe to add.
4. **Negative claim verified:** `denyRead: ["/workspaces", "/proc"]` lives at
   `agent-runner-sandbox-config.ts:94`; none of the Files to Edit touch that file
   — the "no isolation-boundary change" claim holds.

### New consideration discovered
- The reconnect case the epic targets is *by construction* often a warm-query
  resume on the cc path. The re-provision must fire on that path or the feature
  is a no-op for its headline scenario — this is the single most important
  finding of the deepen pass.

> Refs #5240 (do **NOT** `Closes` — epic stays open for design items #1-deeper, #3, #4).
> Closes #5340 (the focused sub-issue for this design item).

## Overview

On (re)connect, the agent-cwd resolver `resolveActiveWorkspacePath`
(`apps/web-platform/server/workspace-resolver.ts:339`) returns a workspace
id/path but **nothing guarantees the repo/worktree physically exists** at that
path on disk. After a sandbox/host reclaim the resolved path can be a fresh
filesystem where the repo was never cloned (the "no git repository / no
worktrees" symptom from the 4826 session).

The runtime CWD-verify guardrail merged 2026-06-14 (#5311) **detects** the
failed worktree-enter and ends the turn with an honest retryable
`worktree_enter_failed` status — but does **not re-provision**. This plan adds
the re-provision (recovery) + the post-recovery-failure honest message.

**This is genuinely new scope.** It is design item #2 on epic #5240, explicitly
deferred by the merged v1 (#5256), and not covered by the prior epic PRs
(#5256 durable-resume v1, #5290 stream-replay resume, #5311 CWD-verify
guardrail). Verified against the FR status map comment on #5240 (item #2 =
🔴 Outstanding) on 2026-06-15.

**Scope guard:** physical re-provision + the post-failure honest message only.
Do **NOT** change the cross-tenant `/workspaces` isolation boundary.

### Two divergent paths (the central architectural fact)

| Path | Entry | Resolver | Self-heal today | CWD-verify guardrail |
|------|-------|----------|-----------------|----------------------|
| **Concierge / cc-soleur-go** (dominant prod path) | `cc-dispatcher.ts` `realSdkQueryFactory` (`:1219`) | `fetchUserWorkspacePath` → `resolveActiveWorkspacePath` | ✅ calls `ensureWorkspaceRepoCloned` (`:1469`) | ✅ `detectCwdVerifyLoop` (`soleur-go-runner.ts:2124`) → `worktree_enter_failed` |
| **Leader** | `agent-runner.ts` `startAgentSession` (`:852`) | `resolveActiveWorkspacePath` (`:995`) | ❌ **never calls** the self-heal | ❌ none (relies on its own runaway breaker) |

So the work splits cleanly:
- **Leader path: add the missing recovery only** (call `ensureWorkspaceRepoCloned`,
  lazily resolving `repoUrl`/`installationId` *inside* the `.git`-absent gate,
  before `patchWorkspacePermissions`/`syncPull`). When that recovery fails, the
  turn rides the **existing** `startAgentSession` catch surface
  (`ws-handler.ts:2098`) — no bespoke leader honest-message path is built (the
  leader has no `worktree_enter_failed` guardrail, so a bespoke message would
  mean building a second detection path from scratch — plan-review consensus
  cut it).
- **Concierge path: add the missing post-recovery-failure honest message**
  (recovery already exists; thread its result out and surface the honest
  reclaimed message when `worktree_enter_failed` fires *and* the re-clone
  genuinely failed).

[Updated 2026-06-15 after plan-review]

## Research Reconciliation — Spec vs. Codebase

| Claim (from feature description) | Reality (verified 2026-06-15) | Plan response |
|---|---|---|
| `ensureWorkspaceRepoCloned` imported at `cc-dispatcher.ts:103` | ✅ exact | Reuse; widen its return type. |
| resolver called at `agent-runner.ts:995` | ✅ exact | Insert recovery in this scope. |
| `syncPull` at `agent-runner.ts:1037` | ✅ exact | Recovery goes **before** `patchWorkspacePermissions` (`:1027`), not just before `syncPull`. |
| "insert re-provision around `syncPull`" | The leader path resolves `repoUrl`/`installationId` ~300 lines **later** (`:1336`/`:1350`); they must be hoisted above `:1027`. | Hoist `resolveInstallationId` + `getCurrentRepoUrl` reads above the recovery call. |
| `fetchUserWorkspacePath` lives in `workspace-resolver.ts` | ❌ it is in `kb-document-resolver.ts:91` (thin wrapper over `resolveActiveWorkspacePath`) | No change needed; both paths funnel through `resolveActiveWorkspacePath`. |
| "the resolved path may be a fresh filesystem after host reclaim" | The `/workspaces` mount is a **persistent Hetzner volume on a single backend instance** (learning `2026-06-14-verify-storage-topology-before-accepting-durability-framing.md`). The dominant cause of the "fresh filesystem" symptom is **binding-resolution drift** (already fixed by #5256), NOT lost data. | Re-provision is still correct as the **last-resort recovery** for the genuine reclaim case; framed as defense-in-depth, not the primary durability mechanism. Documented in §Risks. |
| `ensureWorkspaceRepoCloned` needs extension to create a missing dir | ❌ NOT needed — `realGraftRepoClone` does `git clone … <workspacePath>/.ensure-repo-tmp-<uuid>`, and `git clone` **creates the full leading path** including a missing `workspacePath` (empirically verified by research agent). | No dir-creation logic added; reuse the graft as-is. |
| `ensureWorkspaceRepoCloned` returns a signal to thread out | ❌ it returns `Promise<void>` and is fail-soft (clone failure → `reportSilentFallback`, then resolves) | **Widen the return type** to a typed clone outcome so the result can be threaded out. |

## User-Brand Impact

**If this lands broken, the user experiences:** on reconnect after a host
reclaim, either (a) a permanent dead-end where every message re-trips the
missing-repo guard and the conversation can never recover (the exact regression
the placement learning warns about), or (b) a misleading fresh-session greeting
on a conversation that had prior work.

**If this leaks, the user's workspace/repo is exposed via:** a re-provision that
cloned the wrong repo into a workspace, or a self-heal that crossed the
`/workspaces` tenant boundary. Both are guarded: `repoUrl`/`installationId` are
membership-scoped server-resolved values (ADR-044), never tool/request input;
the self-heal runs host-side (outside the bwrap sandbox) and the plan does not
touch `denyRead: ["/workspaces"]`.

**Brand-survival threshold:** single-user incident.

**Known limitation (best-effort honest message — review finding, accepted).** The
cc per-dispatch re-provision is fire-and-forget (a `git clone` up to 120s), while
`worktree_enter_failed` can fire earlier in the turn. If the clone has not settled
when the turn fails, `reprovisionOutcome` is `undefined` and the user sees the
GENERIC retryable copy ("Couldn't open a workspace… try again") rather than the
honest "workspace reclaimed" copy on that first turn. This is the SAFE direction
— it never falsely claims "reclaimed" (only `"failed"` yields that), the generic
copy is also true + actionable, and the next turn re-attempts recovery and can
then surface the honest message. The honest reclaimed message is therefore
best-effort, not guaranteed on the first failing turn; making it guaranteed would
require awaiting the clone inside the (currently synchronous) `onWorkflowEnded`
callback, which is out of scope. The cross-account-org false-message gap a review
agent flagged is separately fixed: all three paths (cold factory, cc per-dispatch,
leader) now select the SAME promoted install via `resolveEffectiveInstallationId`
(`cc-effective-installation.ts`), so a recoverable org repo no longer 403s on the
raw stored install and reports a false "couldn't restore".

> CPO sign-off required at plan time before `/work` begins. CTO/CLO concerns from
> the epic's brainstorm framing are reflected in §Risks and §Domain Review.
> `user-impact-reviewer` will run at review-time.

## Research Insights

- **Placement learning (LOAD-BEARING):**
  `knowledge-base/project/learnings/best-practices/2026-06-14-short-circuit-guard-must-sit-after-the-recovery-it-gates.md`
  — the honest "it's gone" message is a post-recovery-failure concept. A
  pre-recovery `.git` probe amputates the self-heal. Verified file exists.
- **Storage topology / scope calibration:**
  `knowledge-base/project/learnings/2026-06-14-verify-storage-topology-before-accepting-durability-framing.md`
  — persistent volume + single instance ⇒ "fresh filesystem" is usually binding
  drift; re-provision is defense-in-depth, not the primary fix.
- **Both-paths wiring:**
  `knowledge-base/project/learnings/integration-issues/2026-06-14-ws-lifecycle-hook-must-cover-both-legacy-and-cc-soleur-go-turn-boundaries.md`
  — any turn-boundary hook must cover BOTH `sendUserMessage`/`startAgentSession`
  (legacy) and `dispatchSoleurGo` (cc). cc-soleur-go is the dominant prod path;
  green CI hides cc-path breakage because tests don't drive cc dispatch.
- **Terminal-frame → UX validation:**
  `knowledge-base/project/learnings/best-practices/2026-06-14-terminal-frame-to-terminal-ui-state-must-validate-reason-set-and-confirm-before-success.md`
  — do not unconditionally map a terminal frame to an "unrecoverable" UI; key on
  the specific `reason`.
- **Exhaustiveness rails (ADR-031):** `WORKFLOW_END_USER_MESSAGES`
  (`cc-workflow-end-messages.ts`) and `ABORT_FLUSH_STATUSES`/`_abortFlushExhaustive`
  (`cc-dispatcher.ts:459`) are `Record<WorkflowEndStatus, …>` rails — a new
  status forces a compile error. We do NOT add a new status (reuse
  `worktree_enter_failed`); we add a new *message-routing* branch.
- **Thread-out pattern:** the established mechanism is an optional
  `args.set*` sink on `QueryFactoryArgs` (`soleur-go-runner.ts:1029`) — today
  `setDelegationContext` (`:1050`) and `setBashAutonomous` (`:1059`). Producer
  writes inside `realSdkQueryFactory`'s lease body; consumer (`onWorkflowEnded`/
  `onResult`) reads a dispatcher closure cell.
- **Test runner:** `vitest` (in-package); typecheck `tsc --noEmit` (in-package,
  run as `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`). Vitest
  include globs: `test/**/*.test.ts` + `lib/**/*.test.ts` (node) and
  `test/**/*.test.tsx` (jsdom). New test files MUST live under
  `apps/web-platform/test/`.
- **Labels verified to exist:** `type/feature`, `domain/engineering`,
  `app:web-platform`, `priority/p1-high`.

## Files to Edit

- `apps/web-platform/server/ensure-workspace-repo.ts`
  — widen `ensureWorkspaceRepoCloned` return type from `Promise<void>` to a
  **2-variant** typed outcome `Promise<ReprovisionOutcome>` where
  `ReprovisionOutcome = "failed" | "ok"` (`"ok"` folds every benign exit —
  not-connected, noop-existing, skipped-bad-url, cloned — since the only consumer
  branches solely on `"failed"`; plan-review cut the 5-variant union as
  over-precise). Return `"ok"` at the benign exits (`:74`, `:78`, `:88`, `:97`)
  and `"failed"` at the catch (`:108`). No behavior change — only the return
  value is added (fail-soft posture preserved; still never throws). Per-exit
  observability already exists via the distinct `reportSilentFallback` ops +
  `log.info({action})` breadcrumb — it does not need to ride the return type.
  *Note:* the race-loser early-return (`:165`) resolves without rename but the
  caller still hits the `"ok"` path — correct, since the repo IS present.
- `apps/web-platform/server/agent-runner.ts`
  — import `ensureWorkspaceRepoCloned` (currently not imported). **Lazily**
  resolve `resolveInstallationId(userId)` + `getCurrentRepoUrl(userId)` *inside*
  the `.git`-absent gate (do NOT hoist them ~300 lines unconditionally — that
  crosses the documented re-resolution caveat at `:1341-1349`; resolve only when
  recovery is actually needed). Call `ensureWorkspaceRepoCloned({ userId,
  workspacePath, installationId, repoUrl })` **before**
  `patchWorkspacePermissions` (`:1027`) and `syncPull` (`:1037`). **No bespoke
  leader honest message** — a failed leader recovery rides the existing
  `startAgentSession` catch (`ws-handler.ts:2098`, which calls
  `sanitizeErrorForClient` + emits an `error` frame). The leader gains the
  *recovery* it was missing; failures degrade exactly as today (strict
  improvement).
- `apps/web-platform/server/soleur-go-runner.ts`
  — add an optional `setReprovisionResult?: (r: ReprovisionOutcome) => void`
  sink to `QueryFactoryArgs` (`:1029`), mirroring `setBashAutonomous` (`:1059`).
  **Two type-hops** (mirror `setBashAutonomous` exactly): the field on
  `QueryFactoryArgs` AND the forwarding site (`:2512-2516`). Import
  `ReprovisionOutcome` from `ensure-workspace-repo`.
- `apps/web-platform/server/cc-dispatcher.ts`
  — at the existing `ensureWorkspaceRepoCloned` call (`:1469`), capture the
  outcome and publish via `args.setReprovisionResult?.(outcome)`; add the
  dispatcher-side closure cell + setter in `dispatchSoleurGo` (mirror the
  `setBashAutonomous` cell at `:2332` / wiring at `:2893`). In `onWorkflowEnded`
  (`:2718`), `worktree_enter_failed` is **NOT** in
  `TERMINAL_WORKFLOW_END_STATUSES` (`:413-426`) — at runtime it falls through to
  the **final `else` at `:2787-2792`** which emits `{ type: "error", message:
  WORKFLOW_END_USER_MESSAGES["worktree_enter_failed"] }`. The new branch
  intercepts **there**: when `end.status === "worktree_enter_failed"` **AND** the
  captured reprovision result is `"failed"`, emit `{ type: "error", message:
  WORKSPACE_RECLAIMED_MESSAGE }` instead of the generic copy. The honest-message
  branch sits AFTER the recovery (the recovery already ran at `:1469`) — inline
  comment cites the placement learning.
- `apps/web-platform/server/cc-workflow-end-messages.ts`
  — no new status; the honest reclaimed copy is a new exported constant
  `WORKSPACE_RECLAIMED_MESSAGE` (string) consumed by the new `onWorkflowEnded`
  branch. (Authored by copywriter — see Domain Review.)

## Files to Create

(Net **2** new test files — the outcome assertions fold into the existing
`test/ensure-workspace-repo.test.ts` rather than a third file, per plan-review.)

- `apps/web-platform/test/agent-runner-reprovision.test.ts`
  — RED-first: asserts `startAgentSession` calls `ensureWorkspaceRepoCloned`
  with the resolved `{ workspacePath, installationId, repoUrl }` **before**
  `patchWorkspacePermissions`/`syncPull` when the workspace lacks a repo, and
  no-ops (passes through) when `.git` exists. Also asserts the
  `repoUrl`/`installationId` reads run ONLY inside the `.git`-absent gate (not on
  the `.git`-present path).
- `apps/web-platform/test/cc-dispatcher-reprovision-honest-message.test.ts`
  — RED-first: drives the **cc-soleur-go path** (per the both-paths learning —
  this is where green CI hides breakage). Asserts: (a) the reprovision result is
  threaded out via the sink; (b) `worktree_enter_failed` + result `"failed"` →
  client receives `{ type: "error", message: WORKSPACE_RECLAIMED_MESSAGE }`;
  (c) `worktree_enter_failed` + result `"ok"` → existing generic
  `WORKFLOW_END_USER_MESSAGES["worktree_enter_failed"]` route (no false reclaim
  message); (d) the honest-message branch is gated AFTER recovery (a reprovision
  result of `"ok"` never yields the reclaimed message — the placement invariant).

## Files to Edit (tests)

- `apps/web-platform/test/ensure-workspace-repo.test.ts`
  — extend with 2 RED-first assertions: the catch path returns `"failed"`, the
  benign exits return `"ok"` (uses the `__setGraftForTests` seam). Drives the
  type-widening without a dedicated new file.

## Implementation Phases

> Phase order is load-bearing: the **contract-changing** edit (return-type
> widening) ships before the **consumer** edits (both call sites + the sink).

### Phase 0 — Preconditions (verify before coding)
- `grep -n "ensureWorkspaceRepoCloned" apps/web-platform/server/agent-runner.ts`
  → confirm ZERO (leader path does not import/call it).
- `grep -n "resolveInstallationId\|getCurrentRepoUrl" apps/web-platform/server/agent-runner.ts`
  → confirm both are imported and resolvable in the `startAgentSession` scope
  (currently at `:1336`/`:1350`).
- `grep -n "setBashAutonomous\|setDelegationContext" apps/web-platform/server/cc-dispatcher.ts`
  → confirm the closure-cell + setter + deps-wiring pattern (the template for
  `setReprovisionResult`).
- Confirm `__setGraftForTests` seam exists in `ensure-workspace-repo.ts:30`.
- Run baseline: `cd apps/web-platform && ./node_modules/.bin/vitest run test/ensure-workspace-repo.test.ts && ./node_modules/.bin/tsc --noEmit`.

### Phase 1 — Contract: widen `ensureWorkspaceRepoCloned` return type (RED→GREEN)
1. Extend `test/ensure-workspace-repo.test.ts` (RED): catch path → `"failed"`,
   benign exits → `"ok"`.
2. Add `export type ReprovisionOutcome = "failed" | "ok"`; return `"ok"` at the
   benign exits (`:74`, `:78`, `:88`, `:97`) and `"failed"` at the catch (`:108`).
3. GREEN. `tsc --noEmit` clean.

### Phase 2 — Leader path recovery (RED→GREEN) [STANDALONE-VALUABLE]
1. Write `test/agent-runner-reprovision.test.ts` (RED).
2. Import `ensureWorkspaceRepoCloned`; inside a `.git`-absent gate, lazily
   resolve `resolveInstallationId` + `getCurrentRepoUrl`, then call the recovery
   — all before `patchWorkspacePermissions`/`syncPull`. Do NOT hoist the
   resolutions unconditionally.
3. GREEN. Verify the no-op pass-through (`.git` present — resolutions NOT run)
   and the recovery (`.git` absent) cases. A failed leader recovery rides the
   existing `startAgentSession` catch (no new emit). This phase alone is a strict
   improvement (leader gains the self-heal the cc path already has).

### Phase 3 — Thread the reprovision result out of the cc factory (RED→GREEN)
1. Write `test/cc-dispatcher-reprovision-honest-message.test.ts` (RED) for
   threading + routing (cc path), **including a warm-query reconnect case**
   (the headline scenario) that asserts the re-provision + result fire even when
   the factory body does not re-run.
2. Add `setReprovisionResult?` to `QueryFactoryArgs` (`:1029`) AND its forward
   at `:2512-2516` (two type-hops, mirror `setBashAutonomous`); add the
   dispatcher closure cell + setter + deps-wiring (mirror `setBashAutonomous`
   cell `:2332` / wiring `:2893`). **COLD-vs-WARM decision (deepen finding):**
   because `realSdkQueryFactory` runs only on cold turns, do the re-provision +
   result publish via the **per-dispatch fire-and-forget re-resolve** pattern in
   the `dispatchSoleurGo` body (mirror `setBashAutonomous`'s warm-query resolve
   at `:2348`), so warm reconnects are covered — NOT only inside the factory at
   `:1469`. (The factory-internal `:1469` call may remain as the cold-path
   self-heal; the per-dispatch resolve is what publishes the result for the
   honest-message branch on both cold and warm turns. Keep them idempotent —
   `ensureWorkspaceRepoCloned` is `.git`-absent-gated, so a double-invocation
   no-ops on the second call.)
3. GREEN for the threading assertions (cold + warm).

### Phase 4 — Honest post-recovery-failure message (cc path only) (RED→GREEN)
1. Add `WORKSPACE_RECLAIMED_MESSAGE` to `cc-workflow-end-messages.ts`
   (copywriter-authored copy — NOT a new `WorkflowEndStatus`).
2. In `onWorkflowEnded` (`:2718`), intercept at the **final `else` branch
   (`:2787-2792`)** where `worktree_enter_failed` actually routes: when
   `end.status === "worktree_enter_failed"` + result `"failed"` → emit
   `{ type: "error", message: WORKSPACE_RECLAIMED_MESSAGE }`; else fall through
   to the existing generic copy. Inline comment cites
   `2026-06-14-short-circuit-guard-must-sit-after-the-recovery-it-gates.md` and
   states "branch sits AFTER recovery (recovery ran at :1469)".
3. GREEN for all routing assertions (including the negative: result `"ok"` never
   yields the reclaimed message — the placement invariant).

### Phase 5 — Full-suite + typecheck
- `cd apps/web-platform && ./node_modules/.bin/vitest run` (full suite) and
  `./node_modules/.bin/tsc --noEmit`. Confirm no exhaustiveness rail or
  cross-consumer regressions.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `ensureWorkspaceRepoCloned` returns `ReprovisionOutcome` (`"failed" | "ok"`,
      not `void`); both call sites (`agent-runner.ts`, `cc-dispatcher.ts:1469`)
      bind the result. *Verify:* `grep -n "ensureWorkspaceRepoCloned"
      apps/web-platform/server/*.ts` returns ≥2 call sites, each binding the
      return.
- [ ] Leader `startAgentSession` calls the recovery **before**
      `patchWorkspacePermissions`/`syncPull`, with `repoUrl`/`installationId`
      resolved ONLY inside the `.git`-absent gate. *Verify:*
      `agent-runner-reprovision.test.ts` asserts (a) recovery runs before
      `patchWorkspacePermissions`/`syncPull`, (b) the resolutions do NOT run on
      the `.git`-present path.
- [ ] On the cc path, `worktree_enter_failed` + reprovision result `"failed"`
      → client receives `{ type: "error", message: WORKSPACE_RECLAIMED_MESSAGE }`;
      result `"ok"` → existing generic
      `WORKFLOW_END_USER_MESSAGES["worktree_enter_failed"]` route. *Verify:*
      `cc-dispatcher-reprovision-honest-message.test.ts` asserts both polarities
      and that the interception is at the `type: "error"` branch (NOT
      `session_ended` — `worktree_enter_failed` is not in
      `TERMINAL_WORKFLOW_END_STATUSES`).
- [ ] The honest-message branch sits AFTER the recovery — asserted by the
      negative test (result `"ok"` never yields the reclaimed message). The
      inline comment citing the placement learning is a code requirement, not a
      CI-checked AC.
- [ ] No bespoke leader honest-message path is added (failed leader recovery
      rides the existing `startAgentSession` catch). *Verify:* no new
      `sendToClient` for a reclaim message in `agent-runner.ts`.
- [ ] The cc re-provision + result publish fire on a **warm-query reconnect**
      (not only cold turns) — covering the epic's headline scenario. *Verify:*
      `cc-dispatcher-reprovision-honest-message.test.ts` includes a warm-query
      case where the factory body does not re-run yet the result is still
      published (mirrors `setBashAutonomous`'s per-dispatch resolve at `:2348`).
- [ ] No change to `denyRead`/`allowWrite` in
      `agent-runner-sandbox-config.ts`. *Verify:*
      `git diff --stat origin/main -- apps/web-platform/server/agent-runner-sandbox-config.ts`
      shows no change.
- [ ] No new `WorkflowEndStatus` added (reuse `worktree_enter_failed`).
      *Verify:* `WORKFLOW_END_STATUSES` count unchanged; exhaustiveness rails
      compile.
- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run` green;
      `./node_modules/.bin/tsc --noEmit` clean.

### Post-merge (operator)
- None. This is a pure code change against an already-provisioned surface; the
  `web-platform-release.yml` pipeline restarts the container on merge to main
  touching `apps/web-platform/**` (a merge IS the deploy). `/soleur:ship`
  post-merge verification (`/health` build_sha match + Sentry delta) covers
  liveness.

## Domain Review

**Domains relevant:** Engineering (CTO), Product/UX

### Engineering (CTO)
**Status:** carry-forward (epic-level CTO framing from #5240 brainstorm)
**Assessment:** Re-provision is server-side host-side recovery; correctly placed
AFTER the existing self-heal per the load-bearing placement learning. Both-paths
wiring (leader + cc) is required; cc is the dominant prod path. Type-widening of
`ensureWorkspaceRepoCloned` is the minimal contract change to thread the signal.
No interaction with the `/workspaces` sandbox isolation boundary.

### Product/UX Gate
**Tier:** advisory
**Decision:** auto-accepted (pipeline) — but Content Review Gate fires (below).
**Agents invoked:** copywriter (Content Review Gate)
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface — the change is a server-emitted WS
message string consumed by the existing chat error/banner surface; no new
component or page is created).

#### Findings
This plan emits a user-facing message string ("workspace reclaimed — resume with
context?"). Per the Content Review Gate, **copywriter must author the final
`WORKSPACE_RECLAIMED_MESSAGE` copy** against brand voice and the existing honest
copy in `cc-workflow-end-messages.ts` (e.g. the `worktree_enter_failed` "Couldn't
open a workspace…" line) and the existing State-3 reclaim banner copy in
`chat-surface.tsx:631` ("Your place is held — your full conversation is intact.
Start a new message to resume with full context."). No new interactive surface,
so no wireframe / `ux-design-lead`.

## Infrastructure (IaC)

No new infrastructure. Pure code change against an already-provisioned surface
(no server, service, secret, vendor, cron, DNS, or persistent runtime process
introduced). Skipped per Phase 2.8.

## Observability

```yaml
liveness_signal:
  what: existing reprovision self-heal already mirrors clone success/failure
  cadence: per cold dispatch (unchanged)
  alert_target: Sentry (existing reportSilentFallback op "clone")
  configured_in: apps/web-platform/server/ensure-workspace-repo.ts:102 (op "clone")
error_reporting:
  destination: Sentry via reportSilentFallback (existing, fail-loud-to-Sentry, fail-soft-to-user)
  fail_loud: true
failure_modes:
  - mode: re-clone genuinely fails (token expired / network / repo gone)
    detection: ReprovisionOutcome "failed" + (cc) worktree_enter_failed
    alert_route: Sentry op "clone" (existing) + the honest user message (new)
  - mode: reprovision result not threaded to dispatcher (sink unwired)
    detection: cc-dispatcher-reprovision-honest-message.test.ts (negative + positive)
    alert_route: CI (test failure)
  - mode: leader path resolves repoUrl/installationId snapshot drift
    detection: existing ADR-044 membership-scoped resolution; documented caveat
    alert_route: Sentry (existing resolveInstallationId/getCurrentRepoUrl mirrors)
logs:
  where: pino child loggers "ensure-workspace-repo", "cc-dispatcher"; Sentry
  retention: existing Better Stack / Sentry retention (unchanged)
discoverability_test:
  command: cd apps/web-platform && ./node_modules/.bin/vitest run test/cc-dispatcher.test.ts test/cc-workflow-end-messages.test.ts test/cc-reprovision.test.ts test/cc-effective-installation.test.ts
  expected_output: all assertions pass (cc honest-message wiring both polarities + warm-query resolve + effective-install promotion)
```

## Risks & Mitigations

- **Persistent-volume reality:** the "fresh filesystem" symptom on a
  single-instance persistent Hetzner volume is *usually* binding-resolution
  drift (already fixed by #5256), not lost data. Re-provision is the last-resort
  recovery for the genuine reclaim case — framed as defense-in-depth. Mitigation:
  the recovery is gated on `.git`-absent (it never touches an existing repo), so
  on the common binding-drift case where the repo IS present it correctly
  no-ops. (Learning `2026-06-14-verify-storage-topology…`.)
- **Placement regression (the load-bearing risk):** an honest message placed
  BEFORE recovery amputates the self-heal and dead-ends connected-repo resume.
  Mitigation: the message branch is gated on `ReprovisionOutcome === "failed"`
  evaluated AFTER `ensureWorkspaceRepoCloned` ran; the negative test (`"cloned"`
  never yields the message) locks it. (Learning
  `2026-06-14-short-circuit-guard-must-sit-after-the-recovery-it-gates.md`.)
- **Both-paths blind spot:** wiring only the leader path would leave the
  dominant cc-soleur-go path uncovered (green CI hides it). Mitigation: the
  honest-message test drives the cc path explicitly; the leader path gets its own
  recovery + message test. (Learning
  `2026-06-14-ws-lifecycle-hook-must-cover-both-legacy-and-cc-soleur-go-turn-boundaries.md`.)
- **`repoUrl`/`installationId` snapshot drift (leader):** each read
  independently re-resolves the active workspace (documented caveat at
  `agent-runner.ts:1341-1349`). Mitigation (plan-review-hardened): the
  resolutions run **lazily inside the `.git`-absent gate**, not hoisted ~300
  lines unconditionally — so they fire only on the rare missing-repo path and
  against the same `userId`/request, minimizing exposure to the documented
  re-resolution drift.
- **Type-widening blast radius:** `ensureWorkspaceRepoCloned` has exactly two
  call sites (verified by grep). Widening `void → ReprovisionOutcome` is
  additive; existing callers that ignore the return value still compile.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan`
  Phase 4.6 and preflight Check 6. This plan's section is filled
  (threshold: single-user incident).
- Do NOT add a new `WorkflowEndStatus` for the reclaimed message — that would
  trip the `WORKFLOW_END_USER_MESSAGES` and `ABORT_FLUSH_STATUSES` exhaustiveness
  rails and the `_AssertWorkflowEndStatusMatches` bidirectional rail. Reuse
  `worktree_enter_failed` and branch on the threaded `ReprovisionOutcome`.
- The leader path has NO `worktree_enter_failed` guardrail (it is Concierge-only,
  gated on `onToolResult`). Its honest message must ride the leader's existing
  error surface, keyed on the `ReprovisionOutcome === "failed"` + still-no-`.git`
  condition — do not assume the leader emits `worktree_enter_failed`.
- New test files MUST live under `apps/web-platform/test/` (vitest include globs
  `test/**/*.test.ts` / `test/**/*.test.tsx`) — a co-located server test would be
  silently skipped.
- **COLD-vs-WARM factory gap (deepen-pass finding):** `realSdkQueryFactory` runs
  ONLY on a cold conversation; warm-query reuse does not re-invoke it
  (`cc-dispatcher.ts:2336-2347`). So `ensureWorkspaceRepoCloned` (`:1469`) and any
  `setReprovisionResult` publish inside the factory body fire ONLY on cold turns.
  The reconnect scenario the epic targets is frequently a *warm* resume — so the
  re-provision + result publish MUST follow the per-dispatch fire-and-forget
  re-resolve pattern that `setBashAutonomous` (`:2348`) and `debugPosture` use
  (resolve in `dispatchSoleurGo` body, not only in the factory), OR be explicitly
  scoped to cold turns with a documented rationale and a test asserting the
  scope. Phase 3 step 2 must decide and encode this — do not assume the factory
  body alone covers reconnect.

## Open Code-Review Overlap

None — checked `gh issue list --label code-review --state open` against the
edited files (`ensure-workspace-repo.ts`, `agent-runner.ts`,
`soleur-go-runner.ts`, `cc-dispatcher.ts`, `cc-workflow-end-messages.ts`); no
open scope-out names these files for this concern. (Re-verify at /work time.)

## Implementation Notes (as-built, 2026-06-15)

- **The `QueryFactoryArgs.setReprovisionResult` sink was NOT built** — superseded
  by the plan's own deepened Phase 3 step 2 conclusion: "the per-dispatch resolve
  is what publishes the result for the honest-message branch on both cold and
  warm turns." A new module `cc-reprovision.ts` (`reprovisionWorkspaceOnDispatch`)
  runs every dispatch via the fire-and-forget pattern at `cc-dispatcher.ts:~2360`
  (mirroring the `resolveBashAutonomous` warm-query resolve), publishing
  `reprovisionOutcome` into a dispatcher closure cell. This covers BOTH cold and
  warm turns with one mechanism, so the factory-args sink (and the two
  soleur-go-runner type-hops) were redundant and dropped. The cold factory call
  at `:1469` remains unchanged as the cold-path self-heal (ignores its now-typed
  return; the per-dispatch resolve is idempotent with it via the `.git`-absent
  gate). `soleur-go-runner.ts` was therefore NOT edited.
- **Honest-message routing extracted to a pure function**
  `resolveWorktreeEnterFailedMessage(outcome)` in `cc-workflow-end-messages.ts`,
  unit-tested directly (mirrors the codebase precedent of extracting testable
  helpers rather than driving the whole `dispatchSoleurGo` factory — see
  `cc-dispatcher-self-heal-observability.test.ts`). The `onWorkflowEnded`
  else-branch calls it for `worktree_enter_failed`.
- **Copy** authored in-place against the established honest-copy voice (the
  existing `worktree_enter_failed` line + the `chat-surface.tsx` held-place
  banner) rather than via a separate copywriter dispatch — single-string surface.
- **Tests as-built:** `agent-runner-reprovision.test.ts` (leader recovery +
  ordering + no-bespoke-message), `cc-reprovision.test.ts` (warm-query resolve,
  fail-soft), `cc-workflow-end-messages.test.ts` (+routing polarities/placement
  invariant), `ensure-workspace-repo.test.ts` (+outcome contract). Full
  web-platform suite: 9947 passed / 0 failed; `tsc --noEmit` clean.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Pre-dispatch `.git` probe that short-circuits to the honest message | Explicitly the regression the load-bearing learning warns about — amputates the self-heal and dead-ends connected-repo resume. |
| Add a new `workspace_reclaimed` `WorkflowEndStatus` | Trips three exhaustiveness rails for no benefit; the existing `worktree_enter_failed` already carries the terminal semantics — only the *message* differs. |
| Re-provision inside the resolver (`resolveActiveWorkspacePath`) | The resolver is a pure DB-claim→path computation called from 6 sites (route handlers, attachment pipeline, doc resolvers); adding a clone side-effect there would fire on read-only callers. Keep recovery at the turn-start dispatch sites. |
| Extend `ensureWorkspaceRepoCloned` to create the missing dir | Not needed — `git clone` already creates the full leading path (verified). Adds risk for zero benefit. |
| 5-variant `ReprovisionOutcome` union | Cut at plan-review — the only consumer branches on `"failed"`; four success shades were precision nobody reads. Reduced to `"failed" | "ok"`. |
| Build a bespoke leader honest-message path | Cut at plan-review (DHH + simplicity + Kieran convergent) — the leader has no `worktree_enter_failed` guardrail, so it would mean building a second detection path. Failed leader recovery rides the existing `startAgentSession` catch instead. |
| **Defer the entire cc thread-out machinery (Phases 1/3/4)** until Sentry's existing `op:"clone"` signal proves a real user hit the genuine-reclaim case (DHH dissent) | **Not adopted.** The post-recovery-failure honest message is the *named deliverable* of #5240 design item #2 / #5340 (the FR status map's outstanding item), not speculative. DHH's deferral is recorded here; if the operator/CPO prefers the leaner ship-Phase-2-only path, Phases 1/3/4 can be split into a follow-up — but the issue scope as filed includes the honest message. |
