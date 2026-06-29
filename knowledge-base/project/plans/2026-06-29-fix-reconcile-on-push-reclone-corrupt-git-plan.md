---
title: "fix(workspace): workspace-reconcile-on-push must re-clone a missing/corrupt .git"
date: 2026-06-29
type: fix
branch: feat-one-shot-reconcile-on-push-reclone-corrupt-git
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: single-domain
status: draft
---

# 🐛 fix(workspace): reconcile-on-push must re-clone a missing/corrupt `.git`, not skip or pull/reset

## Enhancement Summary

**Deepened on:** 2026-06-30
**Review agents:** data-integrity-guardian, architecture-strategist, observability-coverage-reviewer,
code-simplifier, user-impact-reviewer (5 parallel, sonnet tier).

### Key improvements from review
1. **User-impact P0 (folded):** named the populated-but-broken `.git` honest-block as a *detection+paging,
   not auto-recovery* path with explicit `/api/repo/setup` recovery + #5591 scope-out — closes the
   "permanent-strand class with no named recovery" gap.
2. **Observability P1 (folded):** the `Sentry.addBreadcrumb` is **orphaned on a clean Inngest return** (no
   captureException → breadcrumb never transmitted). AC12 now verifies recovery via the durable
   `kb_sync_history recovered=true` row, NOT the breadcrumb; failure_modes carry layer-taxonomy substrings
   (`hr-observability-layer-citation`); the "benign ok" validate-repo-url path corrected from "non-paging"
   to "pages".
3. **Architecture P1 (folded):** `ReprovisionOutcome` docstring (ensure-workspace-repo.ts:44-47) added to
   Files-to-Edit — it claims "only consumer branches solely on failed", now false (reconcile reads `"ok"`).
4. **Simplicity (folded):** dropped the redundant 6th test case (`.git`-present-but-invalid ≡ dir-absent on
   the `isValidGitWorkTree` gate); 6→5 cases.
5. **Data-integrity P2 (folded):** op-contract test must assert ABSENCE of the removed `skip-not-ready`
   signal; cross-pod re-clone race documented as an accepted P2 residual (no data loss; unreachable at
   single-worker scale).

### Verified-safe (no change needed)
- Re-clone **never destroys un-pushed commits** (data-integrity P0): `isEmptyCorruptGitDir` requires
  positive ENOENT on both HEAD AND objects; populated/EACCES/gitdir-FILE honest-block. Plan does not touch
  this gate.
- The `recovered = "ok" && isValidGitWorkTree(re-probe)` invariant-not-proxy check is sound and covers the
  concurrent-racer early-return at `ensure-workspace-repo.ts:149`.

## Overview

The operator's containerized `/soleur:go` agent strands on **"not a git repository"** because
`/workspaces/<id>` has a missing or corrupt `.git`. Production Sentry (verified, not inferred)
shows the **only** Inngest function that fires on the affected workspace `754ee124` is
`workspace-reconcile-on-push` (26× on that workspace; **ZERO** `cc-dispatcher` /
`ensure-workspace-repo` events). The `cc-dispatcher` validity self-heal merged earlier today
(PR #5584, `git-worktree-validity.ts` + `ensure-workspace-repo.ts`) therefore **never runs on
the operator's surface** — that path is not being exercised for this workspace.

**The bug.** `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts:309`
gates readiness on `workspaceDirExists(workspacePath)` — directory *existence*, not `.git`
*validity*. When the dir exists, it calls `syncWorkspace` (`workspace-sync.ts`), which only does
`git pull --ff-only` + a gated `reset --hard origin/<default>` — it **never re-clones**. So a
workspace whose dir exists but whose `.git` is broken (or absent) is a **permanent trap**:
reconcile fires on every push but can never recover it.

**The fix.** Replace the `workspaceDirExists`-only readiness gate with a **validity-aware** gate
using `isValidGitWorkTree` (`git-worktree-validity.ts`, merged PR #5584):

- **VALID `.git`** → existing `syncWorkspace` pull/reset path, **unchanged**.
- **INVALID or ABSENT `.git`** → **re-clone** via the validity+corrupt-aware
  `ensureWorkspaceRepoCloned` (`ensure-workspace-repo.ts`) instead of skipping with
  `WORKSPACE_NOT_READY` or proceeding to pull/reset. `ensureWorkspaceRepoCloned` already:
  clones if `.git` absent; removes a *positively-fingerprinted* empty-corrupt `.git`
  (`isEmptyCorruptGitDir`) and re-clones; **honest-blocks** a populated-but-broken / EACCES /
  gitdir-FILE `.git` (never destroying commits).

Recovery is **push-triggered**, which is acceptable: `754ee124` is connected to `jikig-ai/soleur`
and frequently pushed; **this fix's own deploy-push triggers reconcile and heals `754ee124`.**

This is **NOT** a `cc-dispatcher` change (that surface was fixed earlier today but does not run on
the operator's path). The owner-less / duplicate-workspace anomaly that put `754ee124` into this
fragile state is a **separate, deeper root tracked in open investigation issue #5591** — do **not**
fix it here.

## Research Reconciliation — Spec vs. Codebase

| Claim (from feature description) | Codebase reality (verified) | Plan response |
| --- | --- | --- |
| Bug gates on `workspaceDirExists` at ~line 309 | Confirmed: `workspace-reconcile-on-push.ts:309` `if (!(await workspaceDirExists(workspacePath)))` → `skip-not-ready` + `WORKSPACE_NOT_READY` | Replace gate with `isValidGitWorkTree` + reclone |
| `workspace-sync.ts` only pulls/resets, never re-clones | Confirmed: `syncWorkspace` → `git pull --ff-only`; `selfHealNonFastForward` → `fetch` + gated `reset --hard`. No `clone`. | Re-clone lives in `ensureWorkspaceRepoCloned`, called from reconcile (not from `workspace-sync.ts`) |
| `isValidGitWorkTree` exists in `git-worktree-validity.ts` | Confirmed (PR #5584). Sync `lstatSync`/`existsSync`; valid = `.git` FILE OR dir with `HEAD`+`objects`. | Import + use as the readiness gate |
| `ensureWorkspaceRepoCloned(userId, workspacePath, installationId, repoUrl)` is corrupt-aware | Confirmed: `EnsureWorkspaceRepoArgs`; early-returns `"ok"` for not-connected / already-valid; removes empty-corrupt `.git` under `withWorkspacePermissionLock`; honest-blocks populated-broken/EACCES/gitdir-FILE → `"failed"`; clone-fail → `"failed"`. | Call it on the invalid/absent branch |
| `installationId` from push event; `repoUrl` + workspace id in scope | Confirmed: `event.data.installationId` (number); `targetRepoUrl = normalizeRepoUrl(...)`; `ws.id` in the fan-out loop | Pass directly |
| Workspace may be OWNER-LESS (`754ee124`) | Confirmed: handler already computes `ownerId = ... ?? null` and uses `ownerId ?? ws.id` for the existing `syncWorkspace` userId | Use `ownerId ?? ws.id` for `ensureWorkspaceRepoCloned`'s `userId` (logging/breadcrumb only; non-PII) |
| Reconcile test file is "new" | **Exists** at `test/server/inngest/workspace-reconcile-on-push.test.ts` (one dir deeper than the flat `test/` glob; vitest `include: test/**/*.test.ts` collects it). Drives the handler directly with a mock `step`. | **Extend** the existing file; do NOT author a duplicate |
| `#4826` should be cited | `#4826` is unrelated (`feat: nav-rail position resume`). | Do **not** cite #4826 |

## 🎯 User-Brand Impact

**If this lands broken, the user experiences:** the operator's `/soleur:go` agent continues to
strand on "not a git repository" on every session — the workspace stays a permanent dead-end, or
(worse, if the reclone branch is mis-gated) an existing populated `.git` with un-pushed commits is
destroyed.

**If this leaks, the user's data / workflow is exposed via:** no new data egress. The risk axis is
**destructive recovery** — re-cloning over a `.git` that still holds un-pushed commits would lose
the user's work. `ensureWorkspaceRepoCloned` already gates destruction behind the **positive**
`isEmptyCorruptGitDir` fingerprint (HEAD ENOENT + objects ENOENT = no commits to lose) and
honest-blocks everything else; this plan must not weaken that guarantee. The breadcrumb's `userId`
is logging-only and pseudonymized (pino `formatters.log` hashes top-level `userId`; `ws.id` is a
UUID, not PII).

**Populated-but-broken `.git` is honest-blocked, NOT auto-recovered (user-impact P0 scope-out).**
When `.git` is populated-but-broken / EACCES / a gitdir-FILE (i.e. NOT `isEmptyCorruptGitDir`),
`ensureWorkspaceRepoCloned` honest-blocks (`"failed"`) by design — to never destroy un-pushed commits.
This fix adds **detection + paging + an audit row** for that state, but **not** automated recovery: the
recovery path for a populated-broken `.git` is the existing in-app **repo-reconnect route `/api/repo/setup`**
(wipe-and-reclone, `ensure-workspace-repo.ts:124-126`), which is user-initiated because it is destructive
(this is application behavior on an already-provisioned surface, not infra provisioning). **This is not a
regression** — today such a workspace is *silently* permanently stranded; after this fix it pages (Sentry
`op:corrupt-worktree-block`) and is observably not-ready. The actual `754ee124` symptom is the empty-corrupt
/ absent `.git` case, which this fix **does** auto-recover. The corrupt-state root cause (owner-less /
duplicate workspace) is tracked under **#5591**.

**Recovery-trigger durability (user-impact P2).** Recovery is push-triggered. The self-hosted Inngest
event store queues `platform/workspace.reconcile.requested` independent of container-restart timing; the
deploy-push fires the webhook → Inngest. If a specific push's webhook delivery were dropped, recovery
re-drives on the **next** push of any commit to `jikig-ai/soleur` (frequently pushed) — the reconcile is
idempotent. A cron-triggered fallback reconcile is **out of scope** (follow-up; the push cadence on
`jikig-ai/soleur` makes it unnecessary for `754ee124`).

**Brand-survival threshold:** single-user incident.

> **CPO sign-off required at plan time before `/work` begins.** Confirm CPO has reviewed (or invoke
> the CPO domain leader). `user-impact-reviewer` runs at review-time (review SKILL conditional-agent
> block).

## Implementation Phases

### Phase 0 — Preconditions (verify before editing)

0.1. `git grep -n "workspaceDirExists" apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts`
   — confirm the only use is the readiness gate at line 309 and the local helper at 103-110. (If the
   `node:fs` `promises` import is used *only* by `workspaceDirExists`, removing the helper removes the
   import — `cq-ref-removal-sweep-cleanup-closures`.) Verify with
   `git grep -n "\bfs\." apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts`.

0.2. Confirm the exported names: `isValidGitWorkTree` (from `@/server/git-worktree-validity`) and
   `ensureWorkspaceRepoCloned` (from `@/server/ensure-workspace-repo`), and that
   `EnsureWorkspaceRepoArgs` accepts `{ userId: string; workspacePath: string; installationId: number | null; repoUrl: string | null }`.

0.3. Confirm the Sentry breadcrumb shape in use elsewhere: `git grep -n "Sentry.addBreadcrumb" apps/web-platform/server`
   (precedent: `team-workspace-boot.ts:11`, `byok-delegations-boot.ts:11`). Import `* as Sentry from "@sentry/nextjs"`
   the same way those modules do.

### Phase 1 — Validity-aware readiness gate + re-clone (the fix)

In `workspace-reconcile-on-push.ts`, inside the fan-out loop's `step.run(`reconcile-${ws.id}`)`, replace
the `workspaceDirExists` gate (lines 305-329) with:

```ts
const workspacePath = workspacePathForWorkspaceId(ws.id);
// userId is for logging/breadcrumb ONLY — pseudonymized downstream. Owner-less
// workspaces (#5591) carry no canary row, so fall back to the workspace id.
const breadcrumbUserId = ownerId ?? ws.id;

// Readiness = git work-tree VALIDITY, not mere dir existence (ADR-044 amendment
// 2026-06-29). A VALID .git takes the existing pull/reset sync path. An INVALID
// or ABSENT .git is re-cloned via the validity+corrupt-aware ensure path — the
// permanent-trap that workspaceDirExists-only readiness could never recover.
if (!isValidGitWorkTree(workspacePath)) {
  const outcome = await ensureWorkspaceRepoCloned({
    userId: breadcrumbUserId,
    workspacePath,
    installationId,        // number, from the push event
    repoUrl: targetRepoUrl, // composed + normalized in scope above
  });

  // Assert the INVARIANT, not the "ok" proxy: ensureWorkspaceRepoCloned returns
  // "ok" for a benign skip (e.g. a repo_url that fails its github-https allowlist)
  // WITHOUT having healed anything. Re-probe validity to decide recovered.
  const recovered = outcome === "ok" && isValidGitWorkTree(workspacePath);

  // Best-effort transaction-trace context (task-mandated). NOTE: a breadcrumb is
  // only transmitted when a captureException/Message fires on the same Sentry scope;
  // this handler returns cleanly on both paths, so the DURABLE signals are the
  // kb_sync_history row (below) + the inner ensure-workspace-repo Sentry mirrors —
  // not this breadcrumb (observability-review P1). Do NOT add a captureException
  // here (would double-page; ensureWorkspaceRepoCloned already mirrors failures).
  Sentry.addBreadcrumb({
    category: "workspace-reconcile-push",
    message: "corrupt-worktree-reclone",
    level: recovered ? "info" : "warning",
    data: { op: "corrupt-worktree-reclone", recovered, workspaceId: ws.id },
  });

  const at = Date.now();
  if (!recovered) {
    // Honest-block (populated-broken / EACCES / gitdir-FILE), clone failure, or a
    // benign skip that did not heal. ensureWorkspaceRepoCloned already mirrored the
    // genuine failures to Sentry via reportSilentFallback (op: corrupt-worktree-block
    // / corrupt-worktree-rm / clone) — do NOT double-page here. Record the audit row
    // so the workspace stays observably not-ready.
    await writeAuditRow({
      at: new Date(at).toISOString(),
      trigger: "webhook_push",
      sha_before: beforeSha,
      sha_after: headSha,
      ok: false,
      error_class: ERROR_CLASS_WORKSPACE_NOT_READY,
      push_received_at: pushReceivedAt,
      sync_completed_at: at,
      workspace_id: ws.id,
    });
    return { synced: false };
  }

  // Re-cloned successfully: the shallow clone is already at origin HEAD, so a
  // subsequent pull would be redundant. Record an OK audit row marked recovered.
  await writeAuditRow({
    at: new Date(at).toISOString(),
    trigger: "webhook_push",
    sha_before: beforeSha,
    sha_after: headSha,
    ok: true,
    recovered: true,
    push_received_at: pushReceivedAt,
    sync_completed_at: at,
    workspace_id: ws.id,
  });
  return { synced: true };
}

// VALID .git — preserve the existing pull/reset sync path unchanged.
const syncResult = await syncWorkspace(installationId, workspacePath, logger, {
  userId: ownerId ?? ws.id,
  op: "push",
});
// ... (existing syncResult handling, unchanged: lines 336-375)
```

**Edits:**
- Add imports: `import { isValidGitWorkTree } from "@/server/git-worktree-validity";`,
  `import { ensureWorkspaceRepoCloned } from "@/server/ensure-workspace-repo";`,
  `import * as Sentry from "@sentry/nextjs";`.
- Remove the local `workspaceDirExists` helper (lines 103-110) and the now-unused
  `import { promises as fs } from "node:fs";` (line 18) **iff** Phase 0.1 confirms no other `fs.` use.
- Keep `ERROR_CLASS_WORKSPACE_NOT_READY` imported (re-used for the honest-block audit row).
- **Update the `ReprovisionOutcome` docstring** at `ensure-workspace-repo.ts:44-47` (architecture-review
  P1): it currently asserts "the only consumer (the cc reconnect honest-message branch) branches solely
  on `"failed"`." After this change the reconcile surface is a SECOND consumer that ALSO reads the `"ok"`
  variant (via the `recovered = outcome === "ok" && isValidGitWorkTree(...)` re-probe). Reword the
  docstring to note both consumers and that callers may key on `"ok"` with a validity re-probe, not only
  on `"failed"`. (Type/behavior unchanged — docstring accuracy only.)

**Why re-clone is NOT routed through `workspace-sync.ts`:** `workspace-sync.ts` is deliberately a
leaf module kept OUT of the `next/headers` graph; it owns pull/reset only. The clone primitive
(`ensureWorkspaceRepoCloned`) carries the destructive-safety fingerprinting + workspace lock and is
the single canonical re-clone path. The reconcile handler is the right call site (it already holds
`installationId`, `targetRepoUrl`, and `ws.id`).

### Phase 2 — Tests (extend the existing harness)

Extend `apps/web-platform/test/server/inngest/workspace-reconcile-on-push.test.ts`. Add module mocks:

```ts
const isValidGitWorkTreeSpy = vi.fn();
vi.mock("@/server/git-worktree-validity", () => ({
  isValidGitWorkTree: (p: string) => isValidGitWorkTreeSpy(p),
}));
const ensureWorkspaceRepoClonedSpy = vi.fn();
vi.mock("@/server/ensure-workspace-repo", () => ({
  ensureWorkspaceRepoCloned: (args: unknown) => ensureWorkspaceRepoClonedSpy(args),
}));
// Sentry breadcrumb capture
const addBreadcrumbSpy = vi.fn();
vi.mock("@sentry/nextjs", () => ({ addBreadcrumb: (b: unknown) => addBreadcrumbSpy(b) }));
```

Cases (each asserts the audit row shape, the breadcrumb, and which downstream was/wasn't called):

1. **VALID `.git` → normal sync, NO reclone.** `isValidGitWorkTreeSpy.mockReturnValue(true)`;
   `syncWorkspaceSpy` returns `{ ok: true }`. Assert `ensureWorkspaceRepoClonedSpy` **not** called,
   `syncWorkspaceSpy` called once, audit row `ok:true`, **no** `corrupt-worktree-reclone` breadcrumb.
2. **invalid OR absent `.git` → reclone.** `isValidGitWorkTreeSpy` returns `false` on the first probe
   and `true` on the post-ensure re-probe; `ensureWorkspaceRepoClonedSpy` returns `"ok"`. Assert
   `ensureWorkspaceRepoClonedSpy` called once with `{ userId: <ownerId>, workspacePath, installationId, repoUrl: targetRepoUrl }`;
   `syncWorkspaceSpy` **not** called; audit `ok:true, recovered:true`; breadcrumb `recovered:true`.
   *(This case covers BOTH dir-absent and `.git`-present-but-invalid — the gate keys on
   `isValidGitWorkTree`, which is `false` for both states, so they share the identical code path.
   No separate test needed: the distinction is a property of `isValidGitWorkTree`, unit-tested in its
   own module — simplicity-review.)* **The spy returning `false`→`true` across the two probes also
   exercises the concurrent-racer path** (`ensureWorkspaceRepoCloned:149` early-returns `"ok"` when a
   racer already grafted a valid `.git` between the outer gate and the function entry; the re-probe sees
   `"ok" && valid` → `recovered:true`, the correct result regardless of which caller grafted —
   data-integrity-review). Name this explicitly in the test comment.
3. **populated-but-broken → honest-block, NOT destroyed.** `isValidGitWorkTreeSpy` returns `false`
   on both probes; `ensureWorkspaceRepoClonedSpy` returns `"failed"`. Assert audit
   `ok:false, error_class: WORKSPACE_NOT_READY`; breadcrumb `recovered:false`; `syncWorkspaceSpy`
   **not** called. (Destruction-safety of the `.git` is unit-tested in `ensure-workspace-repo.test.ts`;
   here we only assert the reconcile honors `"failed"` and does not claim recovery.)
4. **benign "ok" that did NOT heal (proxy guard).** `ensureWorkspaceRepoClonedSpy` returns `"ok"`
   but the re-probe `isValidGitWorkTree` stays `false`. Assert `recovered:false`, audit
   `WORKSPACE_NOT_READY`, breadcrumb `recovered:false` — proves we assert the invariant, not the proxy.
5. **owner-less workspace path.** `OWNERS` has no entry for `ws.id` (ownerId `null`). Drive case (2);
   assert `ensureWorkspaceRepoClonedSpy` called with `userId === ws.id`, and the audit row is written
   via `appendKbSyncRowForWorkspaceSpy` (workspace-keyed), not `appendKbSyncRowSpy`.

*(5 cases — was 6; simplicity-review folded the redundant `.git`-present-but-invalid case into case 2.)*

Write the failing tests FIRST (`cq-write-failing-tests-before`), then implement Phase 1.

### Phase 3 — ADR-044 amendment (architecture deliverable, in-scope)

Append an amendment to `knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md`
(follow the existing `## Amendment <date> — <title>` pattern, e.g. lines 82, 327, 450):

> **Amendment 2026-06-29 — reconcile readiness gates on worktree VALIDITY + re-clone.**
> The push-reconcile readiness gate was "filesystem existence of the workspace dir." That made a
> dir-exists-but-`.git`-broken (or `.git`-absent) workspace a permanent trap: reconcile fired on
> every push but `syncWorkspace` only pulls/resets — it never re-clones. Readiness now gates on
> `isValidGitWorkTree` (PR #5584). A VALID `.git` keeps the existing pull/reset path; an INVALID or
> ABSENT `.git` is re-cloned via `ensureWorkspaceRepoCloned` (clones if absent; removes a
> positively-fingerprinted empty-corrupt `.git`; honest-blocks populated-broken/EACCES/gitdir-FILE,
> never destroying commits). Recovery is push-triggered. This supersedes the
> "readiness is a filesystem-existence check" note (Amendment 2026-06-17b context). The owner-less /
> duplicate-workspace anomaly that produced the corrupt state is tracked separately in #5591.

### Phase 4 — Verify

- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
- `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/workspace-reconcile-on-push.test.ts`
- Re-run the sibling op-contract test:
  `./node_modules/.bin/vitest run test/sentry-workspace-sync-health-alert-op-contract.test.ts`.
  **Assert the ABSENCE of `op:"skip-not-ready"` on the reclone path** (data-integrity-review P2): the
  old gate fired `reportSilentFallback(op:"skip-not-ready")` for every dir-absent workspace (a paging
  signal); the reclone path eliminates it (dir-absent now → `ensureWorkspaceRepoCloned`). If any Sentry
  alert / Better Stack monitor keys on `skip-not-ready`, this change darks it — the op-contract test must
  cover the removal, not just the new breadcrumb.

## ✅ Acceptance Criteria

### Pre-merge (PR)
- [ ] AC1: `workspace-reconcile-on-push.ts` readiness gate calls `isValidGitWorkTree(workspacePath)`,
  not `workspaceDirExists`. `git grep -n "workspaceDirExists" apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts`
  returns **zero** matches (helper removed).
- [ ] AC2: The INVALID/ABSENT branch calls `ensureWorkspaceRepoCloned({ userId, workspacePath, installationId, repoUrl })`
  with `userId = ownerId ?? ws.id`, `repoUrl = targetRepoUrl`, `installationId` from the event.
- [ ] AC3: `recovered` is computed as `outcome === "ok" && isValidGitWorkTree(workspacePath)` (invariant
  re-probe, not the `"ok"` proxy). The honest-block / clone-fail / benign-non-heal cases all yield
  `recovered:false`.
- [ ] AC4: A VALID `.git` still takes the existing `syncWorkspace` pull/reset path — `syncWorkspace`
  is **not** called on the reclone branch, and `ensureWorkspaceRepoCloned` is **not** called on the
  valid branch (asserted by tests 1 & 2).
- [ ] AC5: `Sentry.addBreadcrumb` fires with `category: "workspace-reconcile-push"`, message/op
  `corrupt-worktree-reclone`, and `data.recovered` ∈ {true,false}. **NOTE (observability-review P1):** the
  breadcrumb is best-effort *transaction-trace context*, NOT a standalone queryable signal — a breadcrumb
  is only transmitted when a `captureException`/`captureMessage` fires on the same Sentry scope, and the
  reconcile handler returns cleanly on both the recovered and the honest-block paths. The DURABLE signals
  are: success → `kb_sync_history recovered=true` + `ensure-workspace-repo.ts:211` `log.info action:cloned`
  (Better Stack); failure → the inner `reportSilentFallback` events (`feature=ensure-workspace-repo`) +
  `kb_sync_history error_class=workspace_not_ready`. Keep the breadcrumb (task-mandated, attaches to any
  same-scope event) but do NOT rely on it as the primary verification path.
- [ ] AC6: No new `reportSilentFallback`/`captureException` page is added at the reconcile call site
  (the genuine-failure mirrors already live inside `ensureWorkspaceRepoCloned`); the reconcile layer
  adds only a breadcrumb — no double-report.
- [ ] AC7: All five test cases (Phase 2) pass; the new tests fail against the pre-fix handler (RED first).
- [ ] AC8: `tsc --noEmit` clean in `apps/web-platform`; the unused `node:fs` import is removed iff Phase 0.1 confirms it.
- [ ] AC9: ADR-044 amendment (Phase 3) committed in this PR; the C4 read-and-confirm task (see
  `## Architecture Decision`) is recorded.
- [ ] AC10: PR body uses `Closes #` only if a tracking issue for THIS bug exists; reference #5591 with
  `Ref #5591` (do NOT `Closes #5591` — it is the separate, deeper investigation). Do **not** cite #4826.

### Post-merge (operator)
- [ ] AC11: After merge to `main`, the `web-platform-release.yml` pipeline restarts the container
  (path-filtered on `apps/web-platform/**`) — **the merge IS the remediation**; no separate operator
  restart. The deploy-push to `jikig-ai/soleur` then fires `workspace-reconcile-on-push` for `754ee124`,
  which re-clones the corrupt `.git`. **Automation: feasible via the existing release pipeline; no
  manual operator step.**
- [ ] AC12: Verify recovery WITHOUT SSH — query `kb_sync_history` for `workspace_id = 754ee124` for a
  row with `recovered = true` after the post-deploy push (read-only, via the Supabase MCP / service-role
  read). This `kb_sync_history` row is the DURABLE, reliable no-SSH signal. *(observability-review P1: do
  NOT verify via "the breadcrumb in Sentry" — on a clean recovered return no Sentry event is captured, so
  the breadcrumb is never transmitted and the query would find nothing.)* (See `## Observability`
  discoverability_test.)

## Files to Edit
- `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts` — validity-aware gate,
  reclone branch, breadcrumb, remove `workspaceDirExists` + unused `fs` import.
- `apps/web-platform/test/server/inngest/workspace-reconcile-on-push.test.ts` — 5 new/extended cases
  + module mocks for `git-worktree-validity`, `ensure-workspace-repo`, `@sentry/nextjs`.
- `apps/web-platform/test/sentry-workspace-sync-health-alert-op-contract.test.ts` — assert ABSENCE of
  `skip-not-ready` on the reclone path (data-integrity-review P2); re-run in Phase 4.
- `apps/web-platform/server/ensure-workspace-repo.ts` — **docstring only** (architecture-review P1):
  update the `ReprovisionOutcome` doc (lines 44-47) to reflect the reconcile surface as a second consumer
  that reads the `"ok"` variant. No type or behavior change.
- `knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md` — Amendment 2026-06-29.

## Files to Create
- None. (Tests extend the existing harness; the reclone primitive already exists.)

## Open Code-Review Overlap
None. `gh issue list --label code-review --state open` bodies were searched for
`workspace-reconcile-on-push`, `workspace-sync.ts`, `ensure-workspace-repo`, `git-worktree-validity`
— zero matches.

## Architecture Decision (ADR/C4)

### ADR
Amend **ADR-044** (Phase 3) — reconcile readiness gates on worktree VALIDITY + re-clone, superseding
the "filesystem-existence check" readiness note. New decision is an *extension* of ADR-044's reconcile
model, not a reversal; recorded as an amendment per the file's established pattern.

### C4 views
Read all three model files — `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`
— and confirm (citing the checked elements):
- **External system** — GitHub (App-installation clone/pull edge) is already modeled; the re-clone uses
  the SAME installation-token clone path the reconcile/clone edge already represents → no new system.
- **Container / data store** — the workspace filesystem store + `kb_sync_history` are already modeled →
  no new store.
- **External actor** — no new human actor (push-triggered, no new correspondent/recipient).
- **Access relationship** — no ownership/tenancy edge changes (this is a recovery-behavior change on an
  existing edge; ADR-044's workspace-keyed ownership is unchanged).

Expected outcome: **no `.c4` edit** (the change is a behavior of an already-modeled edge). The plan
records this enumeration so the "no C4 impact" conclusion is supported, not asserted. If the read
surfaces any element whose *description* the change falsifies, fix it and run
`apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.

### Sequencing
The ADR amendment is authored now (describes the shipped target state); no soak gate.

## 📊 Observability

```yaml
liveness_signal:
  what: kb_sync_history rows for each reconciled workspace (recovered=true on a successful re-clone)
  cadence: per push to a connected repo (push-triggered)
  alert_target: none (success path — durable signal is the kb_sync_history recovered=true row + ensure-workspace-repo.ts:211 log.info action=cloned to Better Stack/pino Layer 2); failures page via existing reportSilentFallback inside ensureWorkspaceRepoCloned
  configured_in: workspace-reconcile-on-push.ts (audit-row writes + breadcrumb) + ensure-workspace-repo.ts (Sentry mirrors)
error_reporting:
  destination: Sentry (sentry-correlation Layer 1) + Better Stack (pino Layer 2)
  fail_loud: true — honest-block/clone-fail/validate-repo-url mirror via reportSilentFallback (op: corrupt-worktree-block / corrupt-worktree-rm / clone / validate-repo-url) inside ensureWorkspaceRepoCloned at ERROR level; the reconcile layer adds only a best-effort breadcrumb (transaction-trace context, not a standalone Sentry event — orphaned on clean return)
failure_modes:
  - mode: re-clone honest-blocked (populated-broken / EACCES / gitdir-FILE .git)
    detection: reportSilentFallback feature=ensure-workspace-repo op=corrupt-worktree-block (pino Layer 2 logger.error + sentry-correlation Layer 1 captureException tagged inngest.fn_id/run_id); kb_sync_history error_class=workspace_not_ready. NOTE — the reconcile breadcrumb is NOT a standalone detection signal (orphaned on clean return).
    alert_route: existing ensure-workspace-repo Sentry mirror (pages) — sentry-correlation Layer 1
  - mode: clone failure (token expired / network / repo gone)
    detection: reportSilentFallback feature=ensure-workspace-repo op=clone (pino Layer 2 + sentry-correlation Layer 1); kb_sync_history error_class=workspace_not_ready
    alert_route: existing ensure-workspace-repo Sentry mirror (pages) — sentry-correlation Layer 1
  - mode: benign "ok" that did not heal (repo_url failed github-https allowlist)
    detection: reportSilentFallback feature=ensure-workspace-repo op=validate-repo-url (pino Layer 2 + sentry-correlation Layer 1) — fires at ERROR level and PAGES (ensure-workspace-repo.ts:194-200); plus kb_sync_history error_class=workspace_not_ready
    alert_route: existing ensure-workspace-repo Sentry mirror (pages — op=validate-repo-url). NOT a by-design silent skip — observability-review P2 correction
logs:
  where: Sentry breadcrumbs (category=workspace-reconcile-push) + kb_sync_history table + Better Stack (pino)
  retention: Sentry default; kb_sync_history persistent
discoverability_test:
  command: "Supabase MCP read-only: select recovered, error_class, sync_completed_at from kb_sync_history where workspace_id = '754ee124...' order by sync_completed_at desc limit 5  (NO ssh)"
  expected_output: "a row with recovered=true after the post-deploy push (heal confirmed), OR error_class=workspace_not_ready + a paged Sentry corrupt-worktree-block event (honest-block confirmed)"
```

## Domain Review

**Domains relevant:** Engineering (reliability / architecture).

### Engineering
**Status:** reviewed (folded into plan body)
**Assessment:** Single-domain server-side bug fix. The architectural concern — changing ADR-044's
readiness model — is handled as an in-scope ADR-044 amendment (Phase 3 / `## Architecture Decision`).
The destruction-safety invariant (re-clone never destroys un-pushed commits) is already enforced by
`ensureWorkspaceRepoCloned`'s positive `isEmptyCorruptGitDir` fingerprint + workspace lock; this plan
re-uses it unchanged. Key correctness risk (proxy-vs-invariant on the `"ok"` outcome) is addressed by
AC3's re-probe. Deepen-plan will spawn data-integrity-guardian + architecture-strategist per
single-user-incident threshold.

### Product/UX Gate
**Tier:** none — mechanical UI-surface scan of `## Files to Edit` / `## Files to Create` matched no
UI-surface paths (`components/**`, `app/**/page.tsx`, `app/**/layout.tsx`). Server/Inngest + ADR doc
only. No wireframe required.

## Risks & Mitigations
- **Destroying un-pushed commits.** Mitigated: only `isEmptyCorruptGitDir` (HEAD+objects both ENOENT)
  authorizes the `rm`; populated/EACCES/gitdir-FILE honest-block. This plan does not touch that gate.
- **Claiming recovery when none happened (proxy bug).** Mitigated: `recovered` re-probes
  `isValidGitWorkTree` after `ensureWorkspaceRepoCloned` returns `"ok"` (AC3). A benign allowlist-skip
  `"ok"` correctly yields `recovered:false`.
- **Double-paging.** Mitigated: genuine failures already mirror inside `ensureWorkspaceRepoCloned`; the
  reconcile layer adds a non-paging breadcrumb only (AC6).
- **Redundant pull after fresh clone.** Avoided: the reclone branch does NOT call `syncWorkspace`
  (the shallow clone is already at origin HEAD; the push's `headSha` is HEAD).
- **`skip-not-ready` signal removed (data-integrity-review P2).** The reclone path eliminates the old
  `reportSilentFallback(op:"skip-not-ready")` paging signal for dir-absent workspaces. If any Sentry alert
  or Better Stack monitor keys on `skip-not-ready`, it goes silent. Mitigated: Phase 4 op-contract test
  asserts the ABSENCE of `skip-not-ready` on the reclone path.
- **Cross-pod re-clone race (data-integrity-review P1 — accepted P2 residual).** `withWorkspacePermissionLock`
  is process-local (`workspace-permission-lock.ts:8-9`: single Next.js worker per container at current
  scale). On a hypothetical multi-pod shared-filesystem deploy, two pods could both reach the graft path;
  the loser's `rename(.git)` throws `ENOTEMPTY`, mirrors `op:clone`, and writes a misleading
  `ok:false/workspace_not_ready` audit row + a spurious page — but **no data loss** (the workspace is
  valid; the winner grafted). This is an existing `ensureWorkspaceRepoCloned` trade-off
  (`ensure-workspace-repo.ts:240-254`); the plan does not alter it. Unreachable at the stated single-worker
  scale. Accepted residual.
- **Breadcrumb is orphaned on a clean return (observability-review P1).** A `Sentry.addBreadcrumb` only
  transmits when a `captureException`/`captureMessage` fires on the same scope; the reconcile handler
  returns cleanly on both recovered and honest-block paths (the sentry-correlation middleware captures
  only on `result.error != null`). So the breadcrumb is best-effort context, NOT a standalone signal.
  Mitigated: durable signals are `kb_sync_history` (recovered=true / workspace_not_ready) + the inner
  `ensure-workspace-repo` Sentry mirrors; AC12 verifies via `kb_sync_history`, not the breadcrumb.

## Precedent Diff — cc-reprovision.ts (the sibling re-clone call site)

`ensureWorkspaceRepoCloned` already has a canonical caller: `cc-reprovision.ts:118-138`
(`reprovisionWorkspaceOnDispatch`, the cc-dispatcher warm-path self-heal). Side-by-side:

| Aspect | cc-reprovision.ts (precedent) | This plan (reconcile surface) |
| --- | --- | --- |
| Validity short-circuit | `if (isValidGitWorkTree(workspacePath)) return "ok";` (line 118) | Same gate; valid → existing `syncWorkspace` |
| `installationId` source | `resolveEffectiveInstallationId({...})` — promotes to the entitled repo-owner install (line 128) | **Direct from the push event** — NO promotion needed: the fan-out already filtered workspaces by `.eq("github_installation_id", installationId)` (handler lines 162-172), so every matched `ws.id` carries THAT install **by construction**. This is the correct resource-selection for the reconcile surface (learning `2026-06-15-parallel-recovery-path-must-reuse-same-resource-selection.md` — the selection here is structurally the event's install, not a re-resolve). |
| Failure observability | `feature=ensure-workspace-repo op=corrupt-worktree-block/clone` (internal mirror) + a distinct cold-path `feature=repo-resolver-divergence op=corrupt-worktree-at-dispatch` breadcrumb (cc-reprovision.ts:111-117) | Same internal mirror; plan adds a DISTINCT `feature=workspace-reconcile-push op=corrupt-worktree-reclone` breadcrumb — mirrors the precedent's per-surface-distinct-op convention |
| Destruction safety | Re-uses `isEmptyCorruptGitDir` gate inside `ensureWorkspaceRepoCloned` | Identical — primitive unchanged |

**Net:** the plan reuses the precedent's primitive and per-surface-distinct-op observability
convention verbatim; the only deliberate divergence (no `resolveEffectiveInstallationId`) is
**correct** because the reconcile fan-out's install is the event's install by construction — adding a
re-resolve here would be redundant and could diverge from the row the query already matched.

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6.
  This section is filled (threshold: single-user incident).
- `ensureWorkspaceRepoCloned` returns `"ok"` for a **not-connected** workspace
  (`installationId === null || !repoUrl`). In reconcile, `installationId` is always a number and
  `repoUrl = targetRepoUrl` is always present, so this branch is unreachable here — but the invariant
  re-probe (AC3) makes the handler correct even if that ever changes.
- The reconcile test file lives at `test/server/inngest/` (one dir deeper than `test/`). vitest
  `include: ["test/**/*.test.ts"]` collects it; do not author a duplicate at `test/`.
- Typecheck/test commands for `apps/web-platform` are `./node_modules/.bin/tsc --noEmit` and
  `./node_modules/.bin/vitest run <path>` — NOT `npm run -w`.

## Research Insights
- `workspace-reconcile-on-push.ts:309` gate confirmed; `syncWorkspace` has no `clone` (only
  `pull --ff-only` + gated `reset --hard`) — verified by reading `workspace-sync.ts`.
- `git-worktree-validity.ts` + `ensure-workspace-repo.ts` merged today via PR #5584 (`fix(concierge):
  dispatch readiness gates on worktree VALIDITY`). `ensureWorkspaceRepoCloned` callers today:
  `cc-reprovision.ts`, `repo-readiness-self-heal.ts` — both on the `cc-dispatcher` surface, which the
  prod Sentry shows does NOT fire on `754ee124`. This fix wires the SAME primitive into the reconcile
  surface that DOES fire.
- Issue #5591 OPEN ("operator account owns TWO connected 'My Workspace' rows") — the duplicate/owner-less
  root; reference, do not fix. #4826 is unrelated (do not cite).
- `Sentry.addBreadcrumb` precedent: `team-workspace-boot.ts:11`, `byok-delegations-boot.ts:11`.

**Institutional learnings (knowledge-base/project/learnings/):**
- `2026-06-18-multi-workspace-per-installation-breaks-founder-resolve-and-ready-clone.md` — a
  `repo_status='ready'` workspace with a missing `.git` on disk is never re-cloned if the gate trusts
  DB/dir status without probing the disk; the disk-validity probe (`isValidGitWorkTree`) is exactly
  the gate widening this plan applies on the reconcile surface.
- `2026-06-03-self-heal-on-brand-path-only-acts-on-safe-symptom.md` — restrict destructive recovery to
  the ONE state with nothing to lose (empty/absent `.git`); land `.git` LAST so a partial failure
  self-retries. `ensureWorkspaceRepoCloned` already implements both — this plan re-uses it unchanged
  and must not weaken it.
- `2026-06-29-recurring-failure-root-cause-is-residual-bad-data-not-patched-code.md` — a recurring
  failure can be **residual bad data**, not just unpatched code. This is the framing of `754ee124`:
  this fix recovers the corrupt on-disk state on the next push, but the **data root** (owner-less /
  duplicate workspace) is #5591 — fixing the code does not retroactively fix the data anomaly that
  produced it. Reference #5591; do not conflate.
