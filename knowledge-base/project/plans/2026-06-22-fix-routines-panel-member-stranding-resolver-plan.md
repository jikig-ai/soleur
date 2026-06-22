---
title: "fix: routines-panel member stranding — thread one membership-verified id through the per-dispatch reprovision resolver"
date: 2026-06-22
type: bug-fix
branch: feat-one-shot-routines-panel-member-stranding-resolver
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: single-domain
adr: ADR-044 (amend — PR-3 reprovision-path closure)
---

# 🐛 fix: routines-panel Members stranded — unify the per-dispatch reprovision resolver (ADR-044 PR-3)

## Enhancement Summary

**Deepened on:** 2026-06-22
**Sections enhanced:** Root Cause, Files to Edit, Test Scenarios, Sharp Edges, Acceptance Criteria
**Research/verify passes used:** call-graph trace (Explore), test-seam + edge-case verify (Explore), precedent-diff (4.4), verify-the-negative (4.45), halt gates 4.6/4.7/4.8/4.9

### Key Improvements (all verified against installed code at HEAD)
1. **Root cause confirmed and relocated.** The divergence is NOT in a routines-specific dispatch entry (none exists — `routine-authoring` is a mode-flag on the shared path); it is `reprovisionWorkspaceOnDispatch` (`cc-reprovision.ts`), fire-and-forget on EVERY dispatch (`cc-dispatcher.ts:2899`), re-deriving the workspace id via three divergent resolvers.
2. **Existing test seam reuse.** `apps/web-platform/test/cc-reprovision.test.ts` ALREADY `vi.mock`s all three consumers at the module boundary (`:32-39`) — EXTEND it (do NOT create a sibling). Two NEW mocks needed: `@/lib/supabase/tenant` (`getFreshTenantClient`) and `@/server/workspace-resolver` (`resolveActiveWorkspace`).
3. **Precedent is exact.** The fix mirrors the cold factory's resolve-once-and-thread (`cc-dispatcher.ts:1536-1602`) verbatim, with ONE deliberate divergence: db-error → skip/return `"ok"` (fire-and-forget) instead of throw.
4. **No signature changes.** All three consumers already accept the optional pre-resolved workspace id (`resolve-installation-id.ts:32`, `current-repo-url.ts:31`, `kb-document-resolver.ts:98`). The fix is wiring-only.
5. **Breadcrumb pseudonymization.** `reportRepoResolverDivergence` puts `userId` in `extra` but it is hashed to `userIdHash` at the emit boundary (ADR-029). The breadcrumb test asserts `not.toHaveProperty("repoUrl"|"installationId")` — mirror for the new op.

### New Considerations Discovered
- `resolveEffectiveInstallationId` (`cc-effective-installation.ts:57-61`) consumes ONLY `{userId, installationId, repoUrl}` and does NOT re-resolve the workspace — so once `installationId`/`repoUrl` are threaded correct, the effective-install promotion is automatically correct. No extra threading needed there.
- `getFreshTenantClient` imports from `@/lib/supabase/tenant` (lib-tier, NOT `@/server/`).
- `current-repo-url.ts` also exports `getCurrentRepoStatus` (`:104`, same `workspaceId?` param) — NOT consumed by reprovision; out of scope.

## Overview

Team-workspace **Members** (not Owners) are stranded with "your workspace isn't ready" when
they use the new **routines panel** in Concierge to draft a routine. The repro: a member of a
connected team workspace opens the routines panel → "Draft a routine with Concierge"
(`components/routines/routines-surface.tsx`, which dispatches with `initialContext { type:
"routine-authoring" }`) → the agent's `git rev-parse --is-inside-work-tree` check fails (the
`ROUTINE_AUTHORING_DIRECTIVE` then tells the agent to STOP — "connect/reconnect a GitHub
repository in Settings → Repository"), because `/workspaces/<id>` has no `.git`.

**Root cause — confirmed during planning (NOT the hypothesis's exact site).** The ADR-044 PR-1
fix (#5435) resolved the active workspace ONCE via the membership-verified `resolveActiveWorkspace`
in the **cold-start dispatch factory** (`cc-dispatcher.ts realSdkQueryFactory:1536`) and threaded
the single id into all clone/repo/install consumers + the `:1703` self-heal. But that fix did
**not** cover `reprovisionWorkspaceOnDispatch(userId)` (`server/cc-reprovision.ts`), a SEPARATE
per-dispatch consumer that runs **fire-and-forget on EVERY dispatch — cold AND warm**
(`cc-dispatcher.ts:2899`, inside `dispatchSoleurGo`, the single entry routine-authoring rides).
`reprovisionWorkspaceOnDispatch` re-derives the workspace id **three times, through three
divergent resolvers**:

| Consumer (cc-reprovision.ts:39-43) | Resolves via | Membership-verified? |
|---|---|---|
| `fetchUserWorkspacePath(userId)` | `resolveActiveWorkspacePath` → `resolveActiveWorkspace` | **YES** — resets a non-member claim to solo (`= userId`) |
| `resolveInstallationId(userId)` | `resolveCurrentWorkspaceId` (raw claim) | **NO** — keeps the team claim (RPC denies → null) |
| `getCurrentRepoUrl(userId)` | `resolveCurrentWorkspaceId` (raw claim) | **NO** — keeps the team claim (returns team repo_url) |

For a member whose membership state diverges from the claim (removed/stale claim, OR a transient
membership-probe `db-error` where `resolveActiveWorkspace` fails-closed to solo while the raw-claim
resolvers keep the team), the **clone location** (`fetchUserWorkspacePath` → `/workspaces/<userId>`,
solo, no `.git`) diverges from **repo+install** (team). `ensureWorkspaceRepoCloned` (which is
`.git`-absent-gated) then attempts the **team** repo into the **solo** path — or no-ops — and the
routine-authoring session lands repo-less. This is the EXACT #4767 divergence the post-mortem
killed in the factory, reincarnated on the warm/reprovision path.

**This path emits ZERO divergence observability today.** `reportRepoResolverDivergence` exists with
three ops (`non-member-claim-reset`, `self-heal-failed`, `connected-null-install-at-dispatch`), but
NONE fire from `reprovisionWorkspaceOnDispatch`. The next occurrence is invisible without SSH.

**The fix (single-resolve-then-thread, mirroring the factory's :1536 pattern):** inside
`reprovisionWorkspaceOnDispatch`, call `resolveActiveWorkspace(userId, tenant)` ONCE, fail-closed on
`db-error` (skip the reprovision rather than clone into an unverified location), and thread the one
membership-verified `activeWorkspaceId` into `fetchUserWorkspacePath(userId, id)`,
`resolveInstallationId(userId, id)`, and `getCurrentRepoUrl(userId, id)`. Emit the deduped
`repo_resolver_divergence` breadcrumb (new op `reprovision-non-member-claim-reset`) when the resolve
carried `resetFromClaim`. The infrastructure already supports this — every consumer accepts an
optional pre-resolved workspace id; only the reprovision wiring is missing it.

This is **single-domain** (engineering / Concierge dispatch), a bug fix on an already-provisioned
surface — no new infrastructure, no schema/migration, no new vendor.

## Research Reconciliation — Spec vs. Codebase

| Hypothesis claim (from the issue) | Codebase reality (verified) | Plan response |
|---|---|---|
| The divergence is in the routines-panel / `routine-authoring` dispatch entry, which "re-derives the workspace id independently" | `routine-authoring` is a **mode-flag** (`context.type`, path-omitted), NOT a separate dispatch entry. It rides the SINGLE path `ws-handler.dispatchSoleurGoForConversation` → `cc-dispatcher.dispatchSoleurGo` → `realSdkQueryFactory`. `routine-authoring-directive.ts` is a system-prompt addendum only — it resolves no workspace. | Fix the SHARED divergent resolver (`reprovisionWorkspaceOnDispatch`), not a routines-specific entry. The routines panel is the *trigger* that exposes it (its directive STOPs the agent on a missing work tree, so a member sees the stranding more sharply than a chat user). |
| The fix should live near `cc-dispatcher.ts:1703` self-heal | `:1703` (the cold-factory installation self-heal) is ALREADY threaded the unified id (post-PR-1). The unthreaded site is `cc-reprovision.ts` (warm+cold per-dispatch), called at `cc-dispatcher.ts:2899`. | Apply the fix in `cc-reprovision.ts`; the `:1703` region needs no change. |
| `resolveInstallationId` / `getCurrentRepoUrl` "re-derive independently" | Confirmed: both fall back to `resolveCurrentWorkspaceId` (raw claim, NO membership check) when called with no workspace id (`resolve-installation-id.ts:37`, `current-repo-url.ts:56`). `fetchUserWorkspacePath` uses the membership-verified `resolveActiveWorkspace`. The three diverge. | Thread ONE id into all three; `resolveActiveWorkspace` is the single membership-verified source. |
| ADR-044 should be authored | ADR-044 **already exists** as a decision file with amendments (2026-06-17 always-enforce-workspace, 2026-06-18 dispatch-readiness gate). | **Amend** ADR-044 (add the reprovision-path closure as PR-3), do NOT author a new ADR. |

## Root Cause (confirmed)

1. **Member opens routines panel → "Draft a routine"** → `ChatSurface` mounts with
   `initialContext={{ type: "routine-authoring" }}` (`routines-surface.tsx:235`). Frontend sends
   ONLY the context type over the WS (`ws-client.ts startSession`); the server resolves the
   workspace (no client-side id — IDOR-safe).
2. Server sets `routineAuthoring: context?.type === "routine-authoring"` (`ws-handler.ts:1246`) and
   dispatches via `dispatchSoleurGo` (`cc-dispatcher.ts:2640`).
3. `dispatchSoleurGo` fires `reprovisionWorkspaceOnDispatch(userId)` (`:2899`, fire-and-forget, every
   dispatch). The cold factory's unified `activeWorkspaceId` (`:1543`) is NOT in scope here.
4. `reprovisionWorkspaceOnDispatch` resolves the **path** membership-verified (→ solo for a
   non-member-claim) but **install+repo** from the raw claim (→ team). The team repo grafts into the
   solo path / no-ops; `/workspaces/<solo-id>` has no `.git`.
5. The routine-authoring agent runs `git rev-parse --is-inside-work-tree`, gets non-true, and (per
   `ROUTINE_AUTHORING_DIRECTIVE` step 2) STOPs with "connect/reconnect a GitHub repository" — an
   action a member cannot perform. Stranded, zero Sentry.

## User-Brand Impact

**If this lands broken, the user experiences:** an invited team Member opening the routines panel
and being told to "connect/reconnect a GitHub repository in Settings → Repository" — an action they
cannot perform (they don't own the connection). The routine-authoring session is dead on arrival;
the member cannot draft a routine at all. Recurs on every attempt (infinite loop).

**If this leaks, the user's workflow is exposed via:** this is an **availability** incident, not a
data-exposure one. The membership-verified resolver fail-closes to the caller's OWN solo workspace
(never a sibling), and `resolve_workspace_installation_id` is a membership-checked SECURITY DEFINER
RPC that denies (→ null) for non-members — so no cross-tenant repo/credential read occurs. The
divergence wastes a clone into the wrong own-workspace directory; it does not move one tenant's repo
into another's. (Consistent with the ADR-044 post-mortem's Art. 33/34 = not-triggered determination.)

**Brand-survival threshold:** single-user incident — one stranded Member is one user who cannot use
a shipped feature, with the brand promise ("Concierge just works for your team") broken for them
specifically. `requires_cpo_signoff: true`; `user-impact-reviewer` runs at review-time.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — single resolve.** `reprovisionWorkspaceOnDispatch` calls `resolveActiveWorkspace(userId, tenant)` exactly ONCE (one `getFreshTenantClient` + one resolve), BEFORE the `Promise.all`. Verified by the new unit test asserting the resolve is invoked once and the three consumers each receive the resolved id.
- [ ] **AC2 — thread, not re-derive.** The three consumers are called with the threaded id: `fetchUserWorkspacePath(userId, activeWorkspaceId)`, `resolveInstallationId(userId, activeWorkspaceId)`, `getCurrentRepoUrl(userId, activeWorkspaceId)`. Verified: `git grep -nE "fetchUserWorkspacePath\(userId\)|resolveInstallationId\(userId\)|getCurrentRepoUrl\(userId\)" apps/web-platform/server/cc-reprovision.ts` returns ZERO (no bare-userId calls remain).
- [ ] **AC3 — member vs owner unit test.** New test `test/cc-reprovision-resolver.test.ts` (or extend `test/cc-reprovision.test.ts`) asserts, with the structural supabase mock (mirror `workspace-resolver-repo-meta.test.ts:43-59`): (a) **solo owner** — solo claim → path/install/repo all key to `userId`, no membership probe; (b) **member-of-team** — team claim, membership probe confirms → path/install/repo all key to the TEAM id (no solo/team split); (c) **non-member-claim reset** — team claim, probe returns null → path/install/repo all key to `userId` (solo), AND the `repo_resolver_divergence` breadcrumb fires with op `reprovision-non-member-claim-reset`; (d) **membership-probe db-error** — `resolveActiveWorkspace` returns `{ok:false}` → reprovision is SKIPPED (returns `"ok"`, no clone attempt into an unverified location), error mirrored.
- [ ] **AC4 — divergence breadcrumb.** On the non-member-claim reset, `reportRepoResolverDivergence({ op: "reprovision-non-member-claim-reset", userId, activeClaimWorkspaceId: resetFromClaim, resolvedWorkspaceId: workspaceId })` is called. Verified by the AC3(c) assertion mirroring `repo-resolver-divergence.test.ts:19-42`: destructure `[err, ctx]` from `reportSilentFallback.mock.calls[0]`; assert `err.message === "repo_resolver_divergence"`, `ctx.feature === "repo-resolver-divergence"`, `ctx.op === "reprovision-non-member-claim-reset"`, `ctx.extra` matches the two workspace ids, and `ctx.extra` has NEITHER `repoUrl` NOR `installationId`. (Note: `userId` is placed in `extra` but hashed to `userIdHash` at the `reportSilentFallback` emit boundary per ADR-029 — assert on the two workspace ids, not the raw userId.)
- [ ] **AC5 — new op registered.** `reprovision-non-member-claim-reset` is added to the `RepoResolverDivergenceOp` union in `server/repo-resolver-divergence.ts`. `tsc --noEmit` clean (the union widens; grep the breadcrumb test for exhaustiveness).
- [ ] **AC6 — fail-closed copy preserved.** No regression to the existing dispatch-boundary not-ready copy/breadcrumb (the cold-factory path at `cc-dispatcher.ts:1540-1554` is UNCHANGED). The reprovision path is fire-and-forget (does not throw `WorkspaceNotReadyError`); on a db-error it returns `"ok"` (fail-soft, no false reclaim message) — the existing behavior, but now AFTER an explicit single membership-verified resolve. `test/server/workspace-not-ready.test.ts` and the cold-factory dispatch tests still pass unchanged.
- [ ] **AC7 — typecheck + suite.** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean; `cd apps/web-platform && ./node_modules/.bin/vitest run` full suite green (no regression); the new + edited reprovision/divergence tests pass.
- [ ] **AC8 — ADR-044 amended.** `knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md` gains a PR-3 amendment recording the reprovision-path closure (single-resolve-then-thread on the warm+cold per-dispatch reprovision; new breadcrumb op). No new ADR file created.

### Post-merge (operator)

- [ ] **AC9 — breadcrumb queryable in soak.** After deploy, the `repo_resolver_divergence` Sentry issue with `op:reprovision-non-member-claim-reset` is queryable by fingerprint (no SSH). `Automation: deferred` — the breadcrumb only fires when a real member with a stale/removed claim dispatches; verification is a soak observation, not a synthetic prod write (`hr-dev-prd-distinct-supabase-projects` — never seed synthetic members into prod). Confirm via Sentry search post-soak.

## Files to Edit

- `apps/web-platform/server/cc-reprovision.ts` — **core fix.** Resolve `resolveActiveWorkspace(userId, tenant)` ONCE (reuse one `getFreshTenantClient(userId)`); fail-closed on `{ok:false}` (skip reprovision, return `"ok"`, mirror); thread `activeWorkspaceId` into `fetchUserWorkspacePath(userId, id)`, `resolveInstallationId(userId, id)`, `getCurrentRepoUrl(userId, id)`; emit `reportRepoResolverDivergence({ op: "reprovision-non-member-claim-reset", ... })` when `resetFromClaim` is set. Import `resolveActiveWorkspace` from `./workspace-resolver`, `getFreshTenantClient` from `@/lib/supabase/tenant`, `reportRepoResolverDivergence` from `./repo-resolver-divergence`.
- `apps/web-platform/server/repo-resolver-divergence.ts` — add `"reprovision-non-member-claim-reset"` to the `RepoResolverDivergenceOp` union (and any JSDoc op list).
- `apps/web-platform/test/cc-reprovision.test.ts` — **EXTEND** (verified at deepen-plan: this file already `vi.mock`s `@/server/kb-document-resolver`, `@/server/resolve-installation-id`, `@/server/current-repo-url`, `@/server/cc-effective-installation`, `@/server/ensure-workspace-repo`, `@/server/observability` at `:32-49`, with `vi.hoisted` spies at `:16-30`). Add the AC3 member-vs-owner-vs-reset-vs-dberror cases + AC4 breadcrumb assertion. **Two NEW mocks required** in the hoisted block: `vi.mock("@/lib/supabase/tenant", () => ({ getFreshTenantClient: mockGetFreshTenantClient }))` and `vi.mock("@/server/workspace-resolver", () => ({ resolveActiveWorkspace: mockResolveActiveWorkspace }))`. Do NOT create a sibling file. vitest collects `test/**/*.test.ts`.
- `apps/web-platform/test/server/repo-resolver-divergence.test.ts` — add a case for the new op (dedup key `op:userId:activeClaimWorkspaceId`, security: no repoUrl/install in `extra`).
- `knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md` — append the PR-3 reprovision-path amendment.

## Files to Create

- **None.** (Verified at deepen-plan: the existing `cc-reprovision.test.ts` seam supports the new cases by extension — no sibling test file needed.)

## Precedent Diff (4.4) — cold factory vs. the reprovision fix

The fix is a verbatim port of the ADR-044 PR-1 cold-factory pattern. Side-by-side:

```
COLD FACTORY (cc-dispatcher.ts realSdkQueryFactory:1536-1602) — the canonical precedent:
  const dispatchTenant = await getFreshTenantClient(args.userId);
  const activeWorkspace = await resolveActiveWorkspace(args.userId, dispatchTenant);
  if (!activeWorkspace.ok) throw new WorkspaceNotReadyError({ kind: "db-error" });   // <-- THROWS (dispatch boundary)
  const activeWorkspaceId = activeWorkspace.workspaceId;
  if (activeWorkspace.resetFromClaim) reportRepoResolverDivergence({ op:"non-member-claim-reset", ... });
  await Promise.all([
    fetchUserWorkspacePath(args.userId, activeWorkspaceId),
    resolveInstallationId(args.userId, activeWorkspaceId),
    getCurrentRepoUrl(args.userId, activeWorkspaceId),
    ...
  ]);

REPROVISION FIX (cc-reprovision.ts reprovisionWorkspaceOnDispatch) — same shape, ONE deliberate divergence:
  const tenant = await getFreshTenantClient(userId);
  const resolved = await resolveActiveWorkspace(userId, tenant);
  if (!resolved.ok) return "ok";                                                      // <-- SKIP (fire-and-forget; NOT throw)
  const activeWorkspaceId = resolved.workspaceId;
  if (resolved.resetFromClaim) reportRepoResolverDivergence({ op:"reprovision-non-member-claim-reset", ... });
  const [workspacePath, storedInstallationId, repoUrl] = await Promise.all([
    fetchUserWorkspacePath(userId, activeWorkspaceId),
    resolveInstallationId(userId, activeWorkspaceId),
    getCurrentRepoUrl(userId, activeWorkspaceId),
  ]);
  // resolveEffectiveInstallationId({userId, installationId, repoUrl}) — no workspace re-resolve (verified)
```

**Why the db-error divergence is correct, not a bug:** the factory IS the dispatch readiness boundary (it must throw `WorkspaceNotReadyError` to surface the not-ready CTA). `reprovisionWorkspaceOnDispatch` is a fire-and-forget recovery whose `ReprovisionOutcome` only gates the post-recovery honest message — on a transient db-error it must NOT throw and must NOT clone into an unverified location; returning `"ok"` (skip) is the existing fail-soft contract, now reached AFTER an explicit single membership-verified resolve. This is the "defense relaxation must name the new ceiling" pattern: no defense is relaxed; the skip preserves fail-closed semantics (no clone on unverified state).

## Architecture Decision (ADR/C4)

**This change closes a resolver/dispatch trust-boundary invariant** (the always-enforce-workspace
invariant ADR-044 introduced), so it IS an architectural-record deliverable — but as an **amendment**
to the existing ADR-044, not a new ADR (per the Phase 0.6 grep: ADR-044 exists with prior amendments).

### ADR
- **Amend `ADR-044-workspace-repo-ownership.md`** with a PR-3 entry: "The always-enforce-workspace
  invariant (PR-1, factory `realSdkQueryFactory:1536`) is extended to the per-dispatch reprovision
  resolver (`reprovisionWorkspaceOnDispatch`, warm+cold, `cc-dispatcher.ts:2899`): resolve the active
  workspace ONCE via the membership-verified `resolveActiveWorkspace`, thread the single id into the
  path/install/repo consumers, fail-closed on `db-error` (skip reprovision rather than clone into an
  unverified location), and emit the deduped `repo_resolver_divergence` breadcrumb (op
  `reprovision-non-member-claim-reset`)." This is an in-scope task of THIS PR, not a follow-up.

### C4 views
**No C4 impact** — verified against all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`) at plan time
(implementer MUST re-confirm at /work, reading all three, not grepping). The change adds no external
actor (the Member and the GitHub App integration are already modeled as part of the ADR-044
workspace-connection edge; no new vendor/correspondent/data-store), no new container, and no new
actor↔surface access relationship (the Member↔team-workspace membership-verified read edge already
exists from PR-1). It corrects WHICH resolver an existing internal dispatch consumer uses — an
internal wiring fix below the C4 component grain. The "no C4 impact" line is supported by: (a) no
new external human actor (Member already modeled), (b) no new external system/vendor (GitHub App
already modeled), (c) no new container/data-store touched (`workspaces`/`user_session_state` already
modeled), (d) no changed actor↔surface access relationship (membership-verified read already the
modeled edge).

### Sequencing
Single atomic PR. The breadcrumb op + the wiring + the ADR amendment + the tests ship together.

## Observability

```yaml
liveness_signal:
  what: "repo_resolver_divergence Sentry issue (op=reprovision-non-member-claim-reset) when a member's reprovision resolve resets a non-member/stale team claim to solo"
  cadence: "on-demand (fires per real divergent dispatch, fingerprint-deduped by op:userId:activeClaimWorkspaceId)"
  alert_target: "Sentry (feature=repo-resolver-divergence). Routing alert is soak-gated per ADR-044 PR-1 follow-up (#5437) — added once the breadcrumb has demonstrably fired."
  configured_in: "apps/web-platform/server/repo-resolver-divergence.ts (reportRepoResolverDivergence → reportSilentFallback → Sentry)"
error_reporting:
  destination: "Sentry via reportSilentFallback (cq-silent-fallback-must-mirror-to-sentry)"
  fail_loud: "the formerly-invisible reprovision divergence is now a queryable Sentry event; the db-error skip path also mirrors (existing cc-reprovision catch → reportSilentFallback op=reprovision-on-dispatch)"
failure_modes:
  - mode: "non-member/stale team claim on reprovision (the stranding bug)"
    detection: "repo_resolver_divergence op=reprovision-non-member-claim-reset"
    alert_route: "Sentry issue search (soak), then sentry_issue_alert routing (#5437 follow-up)"
  - mode: "membership-probe db-error during reprovision"
    detection: "reportSilentFallback op=resolveActiveWorkspace.membership-probe (existing) + reprovision returns 'ok' fail-soft (no false reclaim message)"
    alert_route: "Sentry feature=workspace-resolver"
  - mode: "clone into resolved path fails"
    detection: "ensure-workspace-repo op=clone (existing) → reprovision returns 'failed' → honest worktree-enter message"
    alert_route: "Sentry feature=ensure-workspace-repo"
logs:
  where: "Sentry (events + breadcrumbs); pino stdout on the host (structured)"
  retention: "Sentry project default"
discoverability_test:
  command: "Sentry issue search: feature:repo-resolver-divergence op:reprovision-non-member-claim-reset (web UI / Sentry API — NO ssh)"
  expected_output: "zero events pre-repro; one fingerprint-deduped event per (op,userId,claim) after a real member dispatches with a stale claim"
```

## Domain Review

**Domains relevant:** Engineering (Product NONE — no UI surface changed)

The only edited files are `apps/web-platform/server/**` + a test + an ADR. No path matches
`components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`, and the UI-surface mechanical
override does not fire (`routines-surface.tsx` is READ for tracing, not EDITED). The bug fixes the
SERVER resolver that strands a Member; the routines panel UI is unchanged. The "your workspace isn't
ready" copy the Member sees is the existing agent-directive STOP (`routine-authoring-directive.ts`)
+ existing `WorkspaceNotReadyError` copy — neither is reworded. Product/UX Gate: NONE.

### Engineering
**Status:** reviewed (plan-time CTO/architecture lens applied inline)
**Assessment:** This is the textbook "application-layer recovery primitive that mirrors a sibling
predicate at the same threshold" case — but here the two siblings (cold factory vs per-dispatch
reprovision) were SUPPOSED to be identical and silently diverged. The load-bearing sub-value of the
reprovision copy is (a) warm-reconnect coverage the cold factory does not provide AND (b) the new
divergence observability. Both justify keeping the reprovision path; the fix is to make it use the
SAME membership-verified resolve the factory uses. No new defense is relaxed.

## Hypotheses

The issue's hypothesis (divergence in a routines-specific dispatch entry) is **partially wrong on
location, right on mechanism.** Confirmed during planning: `routine-authoring` is a mode-flag on the
shared dispatch path, not a separate entry; the actual unthreaded divergent resolver is
`reprovisionWorkspaceOnDispatch` (shared by all dispatches, exposed most sharply by the routines
directive's hard STOP-on-missing-work-tree). No network/SSH hypothesis applies (this is a pure
application-logic divergence, not a connectivity failure).

## Open Code-Review Overlap

None checked at plan-write time against the finalized file list (run `gh issue list --label
code-review --state open` at /work Phase 0 and grep the bodies for `cc-reprovision.ts` /
`repo-resolver-divergence.ts` / `cc-dispatcher.ts` before coding; record the result).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text,
  or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is filled.)
- **Do NOT thread the autonomous-toggle trio.** The cold factory (`cc-dispatcher.ts:1573-1591`)
  DELIBERATELY leaves `resolveBashAutonomous` / `resolveAutonomousAck` / `resolveIsWorkspaceOwner`
  un-threaded (each backs onto an `is_workspace_member`-gated RPC → fail-closed false/null on a
  non-member reset). `reprovisionWorkspaceOnDispatch` does not touch those — only path/install/repo.
  Keep that scoping; threading the trio is out of scope and would change the autonomous posture.
- **`resolveInstallationId` / `getCurrentRepoUrl` already accept an optional second arg** (`workspaceId?: string | null`, `resolve-installation-id.ts:30-32`, `current-repo-url.ts:29`). No
  signature change needed — pass the threaded id positionally. `fetchUserWorkspacePath` accepts
  `preResolvedActiveWorkspaceId?` (`kb-document-resolver.ts:91-93`). The threading is wiring-only.
- **db-error semantics differ from the factory.** The factory THROWS `WorkspaceNotReadyError` on
  `{ok:false}` (it is the dispatch-boundary gate). `reprovisionWorkspaceOnDispatch` is fire-and-forget
  (its `ReprovisionOutcome` only gates the post-recovery honest message) — so on `{ok:false}` it must
  SKIP the reprovision and return `"ok"` (NOT throw, NOT clone into an unverified location), mirroring
  the existing fail-soft catch. Do not change the outcome contract.
- **vitest test path glob.** New tests MUST live under `test/**/*.test.ts` (node) — `vitest.config.ts`
  `include` does NOT collect co-located `server/*.test.ts`. `bunfig.toml` blocks `bun test`; the only
  runner is `./node_modules/.bin/vitest run`. Typecheck is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (the repo root has NO `workspaces` field — `npm run -w` fails).
- **Breadcrumb `extra` security.** The breadcrumb must carry ONLY the two workspace ids — NEVER
  `repoUrl` or `installationId` (mirror the existing `repo-resolver-divergence.test.ts` no-leak
  assertion).

## Test Scenarios

| Scenario | Setup | Expected |
|---|---|---|
| Solo owner reprovision | claim === userId | one resolve, no membership probe; path/install/repo all key `userId`; no breadcrumb |
| Team member reprovision | claim = TEAM, membership probe confirms | one resolve; path/install/repo all key TEAM; no breadcrumb; clone targets `/workspaces/<TEAM>` |
| Non-member / stale claim | claim = TEAM, probe returns null | one resolve; path/install/repo all key `userId` (solo); breadcrumb op=`reprovision-non-member-claim-reset` fires (deduped); NO team repo cloned into solo path |
| Membership-probe db-error | `resolveActiveWorkspace` → `{ok:false}` | reprovision SKIPPED, returns `"ok"`, error mirrored; no clone attempt |
| Routine-authoring end-to-end (member) | member dispatches with `context.type="routine-authoring"` | clone lands in the membership-verified team workspace; `git rev-parse --is-inside-work-tree` true; agent proceeds to draft (no STOP) |

## Implementation Phases

1. **Phase 0 — preconditions (/work).** Re-confirm at HEAD: the three bare-`userId` calls in
   `cc-reprovision.ts:39-43`; `resolveActiveWorkspace` import path; the structural-mock seam in the
   existing `cc-reprovision.test.ts`; the `RepoResolverDivergenceOp` union; vitest glob + tsc form.
   Run the Open Code-Review Overlap grep. Read all three `.c4` files to re-confirm "no C4 impact".
2. **Phase 1 — RED.** Write the AC3 member-vs-owner-vs-reset-vs-dberror tests + AC4 breadcrumb test
   (they fail against current `cc-reprovision.ts`).
3. **Phase 2 — GREEN.** Add the new op to `repo-resolver-divergence.ts`. Refactor
   `reprovisionWorkspaceOnDispatch`: one `getFreshTenantClient` + one `resolveActiveWorkspace`;
   fail-closed `{ok:false}` → return `"ok"` (skip); thread the id into all three consumers; emit the
   breadcrumb on `resetFromClaim`. Tests go green.
4. **Phase 3 — refactor + ADR.** Amend ADR-044 with the PR-3 entry. `tsc --noEmit` + full `vitest`.
5. **Phase 4 — ship.** PR body uses `Ref` (not `Closes`) only if any post-merge operator step
   remains; here AC9 is a soak observation, so `Closes <issue>` is fine if an issue is filed.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Pass the cold-factory's resolved `activeWorkspaceId` down into `reprovisionWorkspaceOnDispatch` | The factory runs LAZILY inside the runner's query construction, AFTER `dispatchSoleurGo` fires reprovision at `:2899` — the factory id is not in scope at the reprovision call site. Resolving once INSIDE reprovision is the correct, in-scope fix and mirrors how the factory itself resolves locally. |
| Make `resolveInstallationId` / `getCurrentRepoUrl` use the membership-verified `resolveActiveWorkspace` by default (no second arg) | Broad blast radius — those resolvers have many callers that intentionally pass an explicit id or rely on the claim resolver. Changing the default could shift behavior on unrelated paths. Threading the id at the ONE divergent site is the minimal, targeted fix (matches the factory's pattern). |
| Gate the fix on `routineAuthoring` | The divergence is on the SHARED dispatch path (every warm/cold dispatch), not routines-specific. Gating would leave the same stranding live for chat/KB dispatches. Fix the shared resolver. |
