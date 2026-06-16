---
title: Finish ADR-044 — workspace-owned connection & always-enforce-workspace (PR-1)
issue: 5437
branch: feat-adr-044-workspace-connection
worktree: .worktrees/feat-adr-044-workspace-connection
pr: 5435
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-06-16-adr-044-workspace-owned-connection-brainstorm.md
spec: knowledge-base/project/specs/feat-adr-044-workspace-connection/spec.md
---

# Finish ADR-044 — Workspace-Owned Connection (PR-1)

## Enhancement Summary

**Deepened:** 2026-06-16 · **Agents:** data-integrity-guardian, security-sentinel, architecture-strategist, verify-the-negative grep pass. All 6 plan factual claims verified against code.

**Load-bearing corrections (deepen):**
1. **Split-brain layering (arch P0):** not-ready copy assembles at the **dispatch boundary** (`cc-dispatcher.ts`), not the pure `repo-readiness.ts` predicate — the member-solo-no-repo state never flows through the readiness layer.
2. **Resolver proliferation (arch P1):** `resolveActiveWorkspace` **refactors** the silent `resolveActiveWorkspaceIdWithMembership`, not a third peer; all callers collapse onto it.
3. **Non-convergent reset (arch P1):** breadcrumb deduped by `(userId, resetFromClaim)` fingerprint to prevent a per-dispatch storm.
4. **Confused-deputy (security P0):** owner-gate `p_workspace_id` = the mutation target (`user.id`); a no-op-for-solo in PR-1, load-bearing in PR-2.
5. **Backfill integrity (data P2):** composite-PK conflict target + parent org/workspace rows (FK `ON DELETE RESTRICT`); verified `claim_repo_clone_lock`/`set_repo_status` self-gate on membership and the reset is read-only.
6. **C4 (arch P2):** connection edge is read=Workspace / write=User (`adopting`) — PR-1 cuts only the read path.

## Overview

Invited team-workspace members can't dispatch Concierge work: the `soleur:go` Step 0.0 gate
says "workspace isn't ready — reconnect your repository," but they don't own the connection and
reconnecting can't fix it. Root cause (diagnosed): two resolver paths diverge inside one
`Promise.all` at `cc-dispatcher.ts:1533-1556` — `fetchUserWorkspacePath` resolves the agent
CWD/clone path through the membership self-heal (which can fall back to `userId` on a probe
miss/error), while `resolveInstallationId` / `getCurrentRepoUrl` / `getCurrentRepoStatus`
resolve repo+install directly. A **second** raw resolve sits in the self-heal block at
`cc-dispatcher.ts:1703`. On a miss the clone lands in the solo `/workspaces/<userId>` dir
(no `.git`) while repo+install resolve the team workspace. Zero Sentry; invisible.

**PR-1 = the incident-stopping, non-destructive slice:** resolve ONE membership-verified id and
thread it into all consumers (including `:1703`); make the fallback observable; owner-gate the
repo routes/card. PR-2 (soak-gated: connect-write relocation + legacy `users.*` column drop) is
sketched at the end and planned separately.

The fix core is small (resolve once, thread the id into params that mostly already exist). This
plan was trimmed after a 3-reviewer pass (DHH/Kieran/simplicity) — see Research Reconciliation.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality (verified file:line) | Plan response |
|---|---|---|
| FR1 "thread into four via existing `workspaceId?` overrides" | `resolveInstallationId` (`resolve-installation-id.ts:30`), `getCurrentRepoUrl` (`current-repo-url.ts:29`), `getCurrentRepoStatus` (`current-repo-url.ts:106`) already take `workspaceId?`. `resolveActiveWorkspaceRepoMeta` has `preResolvedActiveWorkspaceId` (`workspace-resolver.ts:544`). | Only `resolveActiveWorkspacePath` (`workspace-resolver.ts:397`, consumed by `fetchUserWorkspacePath` at `kb-document-resolver.ts:91`) needs the param ADDED. |
| **[CORRECTED]** First draft said signup does NOT provision membership (FR5 = net-new build) | **Wrong** — repo-research misread mig 053's "Phase 5" comment (which refers only to the TS *mirror*). The current `handle_new_user` trigger (**mig 091:158-169**) already inserts `workspace_members(workspace_id=NEW.id, user_id=NEW.id, role='owner')`; mig 053 also backfilled existing users. | FR5 is **verify-coverage + residual backfill only** (matches the spec's original wording), NOT a trigger rewrite. Cite mig 091, not 053. |
| **[NEW — Kieran P1]** Threading only listed the 4 `Promise.all` consumers | A **second** `resolveCurrentWorkspaceId(args.userId, tenant)` at `cc-dispatcher.ts:1703` (self-heal clone-lock/clone-target) re-derives the raw claim — same divergence class. | Thread the unified id into `:1703` too; it must land atomically with the `Promise.all` threading. |
| FR3 owner-gate | `is_workspace_owner` RPC exists (`mig 098`, used at `workspace-identity-resolver.ts:105`); `workspaceIdentity.isOwner` already plumbed to settings (`settings-content.tsx:55`). `disconnect`/`setup` routes auth via `auth.getUser()` only — no role check (gap). | Add `is_workspace_owner` check to both routes; thread `isOwner` into the card (small — data already exists). |

## User-Brand Impact

**If this lands broken, the user experiences:** an invited member opens any Concierge workflow
and is told to "reconnect your repository" — an action they cannot perform — looping forever.
**If this leaks, the user's workflow is exposed via:** a resolver that fail-closes to the wrong
workspace would run an agent against a sibling tenant's clone. The TR1 invariant makes that
structurally impossible.
**Brand-survival threshold:** single-user incident. CPO sign-off at plan time; `user-impact-reviewer` at PR review.

## Implementation Phases (PR-1)

### Phase 1 — Unified resolver + thread into ALL dispatch consumers [FR1, TR1]

The core fix; the `:1703` thread must land in the same phase (atomic — no intermediate commit
where path/repo/install are unified but the clone target diverges).

1. **Refactor (not a new peer)** `resolveActiveWorkspaceIdWithMembership` (`workspace-resolver.ts:344`) into `resolveActiveWorkspace(userId, supabase): Promise<ResolveResult>` — make its silent solo-rewrite (`:380-382`) **explicit**. Collapse its existing callers (`resolveActiveWorkspacePath:401`, `resolveActiveWorkspaceKbRoot:415`) onto it (each unwraps `ok`→id, maps `{ok:false}` to its existing 404/503). Do NOT leave the silent function beside the explicit one — that ships two membership resolvers, the exact divergence surface this PR kills. AC: no caller of the silent `resolveActiveWorkspaceIdWithMembership` remains.
   `ResolveResult = { ok: true; workspaceId: string; resetFromClaim?: string } | { ok: false; reason: "db-error" }`.
   - claim (`current_workspace_id`) === `userId` OR null → `ok(userId)` (genuine solo / unbound — always a valid own workspace, safe pre-backfill).
   - claim is a team the user IS a member of → `ok(claim)`.
   - claim is a team the user is NOT a member of (removed / stale claim) → `ok(userId, resetFromClaim=claim)` — **reset to own workspace, non-blocking** (matches today's shipping self-heal; safe — own tenant), emit breadcrumb (Phase 4).
   - membership probe DB error → `{ ok: false, "db-error" }` — transient; do NOT reset a possibly-real member, do NOT dispatch into an unverified team.
   - **TR1 invariant:** the only `ok` returns are a membership-verified team id or the caller's own `userId`. NEVER a claim id that failed/skipped the probe; NEVER `MIN(created_at)`/first-membership (the #4767 bug class). Test: probe DB error returns `{ok:false}`, never the claim id.
2. Add `preResolvedActiveWorkspaceId?: string` to `resolveActiveWorkspacePath` (`workspace-resolver.ts:397`) and plumb it through `fetchUserWorkspacePath` (`kb-document-resolver.ts:91`).
3. In `cc-dispatcher.ts`: resolve `resolveActiveWorkspace(userId)` **once before** the `Promise.all` (~:1533). On `ok:false` throw `WorkspaceNotReadyError("db-error")` (do not dispatch). On `ok`, pass `workspaceId` into all four consumers AND into the self-heal block at **`:1703`** (replace the raw `resolveCurrentWorkspaceId` there with the already-resolved id). Confirm `ensureWorkspaceDirExists` + `ensureWorkspaceRepoCloned` run against that id BEFORE `evaluateRepoReadiness`/the in-agent Step 0.0 gate (gate-after-recovery, #5240). Self-heal handles both clone failure states per `2026-06-16-diverged-clone-recovery-branch-aside-before-reset` (absent → re-clone; diverged → branch-aside then reset).

### Phase 2 — Personal-workspace coverage [FR5, verify-only]

Per the correction above, signup already provisions `workspace_members(owner)` (mig 091). So:
1. Run the read-only count: `select count(*) from users u left join workspace_members m on m.user_id=u.id where m.user_id is null`. Expect 0 or a tiny trigger-failure residue.
2. If non-zero, ship ONE idempotent residual backfill migration mirroring mig 053:228-259 / 091:169-171 **exactly**: insert parent `organizations` + `workspaces(id=user.id)` rows first if missing (the `workspace_members.workspace_id` FK to `workspaces` is `ON DELETE RESTRICT` — a missing-membership user may be missing the whole chain, not just the join row), then `insert into workspace_members (workspace_id, user_id, role, attestation_id) values (u.id, u.id, 'owner', NULL) on conflict (workspace_id, user_id) do nothing` (composite-PK target, deepen data P2). The `AFTER INSERT` audit trigger emits one benign `actor_user_id=NULL` WORM row (tolerated — same path mig 053's own backfill exercised). If count = 0, no migration — record in PR body.
No trigger rewrite, no TS-fallback build (already present).

### Phase 3 — Not-ready copy assembled at the DISPATCH BOUNDARY [FR2]

**Corrected after deepen (arch P0 — split-brain):** `repo-readiness.ts` is a pure `(repoStatus, repoError)` predicate (`:69`) with NO access to solo/team, the target team id, or role; `RepoNotReadyError` carries only `(code, message, errorCode)`. The member-in-solo-no-repo state is `repo_url IS NULL` on the resolved solo workspace, which `evaluateRepoReadiness` maps to `{ok:true}` (fail-open) — it never flows through the readiness layer. So **copy assembly lives in `cc-dispatcher.ts` at the dispatch boundary** (catch sites ~`:3431`/`:3507`), where `userId`, the `resolveActiveWorkspace` result (incl `resetFromClaim`), and a role probe are all in scope. `repo-readiness.ts` stays a pure `repo_status` predicate and gains NO role/team knowledge.

States (collapsed from 7 after the simplicity review):
- **`{ok:false, db-error}`** → transient copy: "Temporary problem reaching your workspace — try again in a moment." NO switcher, NO reconnect. (Indeterminate-role folds here.)
- **Member, resolved-solo-has-no-repo** (incl the `resetFromClaim` reset case) → "This workspace has no project connected. If your team's project lives in **<Team>**, switch workspaces and try again." Primary action = workspace-switcher deep link **carrying the target team id** — which, for a reset, is exactly the discarded `resetFromClaim` claim (thread it resolver → catch → card), via `set_current_workspace_id` RPC. No reconnect CTA. Unresolvable `<Team>` name under RLS → "the team workspace this repo belongs to" (name omitted).
- **Owner, solo-has-no-repo / error** → actionable "reconnect in Settings → Repository."
- Update `go.md` Step 0.0 to remove the unconditional "reconnect your repository" advice from the member path. Leave `repo-readiness.ts` pure (no edit beyond not emitting member-reconnect copy from it — it never did).

### Phase 4 — Divergence observability [FR4, breadcrumb only]

At the `resetFromClaim` branch (Phase 1) and any post-switch self-heal failure, call
`reportSilentFallback(new Error("repo_resolver_divergence"), { feature: "repo-resolver-divergence", op: <"non-member-claim-reset" | "self-heal-failed">, extra: { activeClaimWorkspaceId, resolvedWorkspaceId } })`. Helper hashes userId. **Dedupe by `(userId, resetFromClaim)` fingerprint — NOT just `op`** (deepen arch P1): the reset is read-time and mutates nothing, so without claim-pair fingerprinting it re-fires on EVERY dispatch for a removed member → a breadcrumb storm that buries the real first-occurrence signal. The `extra` is exactly `{activeClaimWorkspaceId, resolvedWorkspaceId}` (both UUIDs) — no `repoUrl`/`installationId`/raw-userId (security P2). NOT fired on db-error or normal cloning. The Sentry **alert rule** (routing) is a fast-follow (see Infrastructure) — the breadcrumb makes the next occurrence queryable, which is PR-1's job.

### Phase 5 — Owner-gate routes + repo card [FR3]

1. `disconnect/route.ts` + `setup/route.ts`: `is_workspace_owner(p_workspace_id, p_user_id)` check after `auth.getUser()`; 403 non-owner. **`p_workspace_id` MUST equal the workspace id the handler actually mutates** (deepen security P0 — confused-deputy). In PR-1 both routes mutate the **solo** `users` row + solo mirror keyed on `user.id`, so `p_workspace_id = user.id` → the gate is a **no-op for solo users by construction** (a solo user is always owner of `workspace_id=user.id`) and only becomes load-bearing in **PR-2** when connect-writes relocate to `workspaces.*` keyed on the active (possibly team) id. Document this plainly so the gate gives no false assurance. `is_workspace_owner` is SECURITY DEFINER with `SET search_path = public, pg_temp` (mig 098:73-74, verified); reuse the call shape from `workspace/logo/route.ts`.
2. Thread `isOwner` (already on `workspaceIdentity.isOwner`, `settings-content.tsx:55`) into `project-setup-card.tsx`; members see read-only "Connected: <repo> · managed by <owner>", no controls (match `RenameWorkspaceAction` gating). **This card gating is the load-bearing member-facing FR3 value in PR-1** (prevents a member clicking a control that would disconnect their *own solo* connection — a confusing-but-not-cross-tenant action).

### Phase 6 — ADR-044 amendment + C4 [FR7] — see Architecture Decision

### Phase 7 — Tests (RED-first, `cq-write-failing-tests-before`)

Resolver: `ok(userId)` for solo/unbound; `ok(team)` for member; `ok(userId, resetFromClaim)` for non-member team claim (asserts breadcrumb fires); `{ok:false,"db-error"}` on probe error (TR1: asserts it does NOT return the claim id). Threading: all four consumers AND `:1703` receive the same id; assert no second raw `resolveCurrentWorkspaceId` remains on the dispatch path. Copy: db-error → transient (no switcher/reconnect); member-solo-no-repo → switcher deep link with team id; owner → reconnect. Routes 403 non-owner. Breadcrumb fires on reset/self-heal-failed only.
Runner: `apps/web-platform` = **vitest** (`./node_modules/.bin/vitest run <path>`), files under `test/**/*.test.ts(x)` per `vitest.config.ts` (not co-located). Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.

## Files to Edit

- `apps/web-platform/server/workspace-resolver.ts` — add `resolveActiveWorkspace`; add `preResolvedActiveWorkspaceId?` to `resolveActiveWorkspacePath:397`.
- `apps/web-platform/server/kb-document-resolver.ts` — plumb override through `fetchUserWorkspacePath:91`.
- `apps/web-platform/server/cc-dispatcher.ts` — resolve once before `Promise.all` (~:1533); thread into the four consumers AND `:1703`; throw `WorkspaceNotReadyError` on `ok:false`.
- `apps/web-platform/server/ensure-workspace-repo.ts` (self-heal) — both clone failure states; emit `self-heal-failed` op.
- `apps/web-platform/server/repo-readiness.ts` — role-branched member-solo-no-repo copy + switcher deep link; db-error transient; remove member "reconnect" advice.
- `apps/web-platform/app/api/repo/disconnect/route.ts`, `apps/web-platform/app/api/repo/setup/route.ts` — owner-role check.
- `apps/web-platform/components/settings/project-setup-card.tsx`, `settings-content.tsx` — `isOwner` gating + read-only member variant.
- `plugins/soleur/commands/go.md` — Step 0.0 member-path copy.
- `knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md` — amendment (`status: adopting`).

## Files to Create

- (conditional) `apps/web-platform/supabase/migrations/0NN_backfill_residual_personal_workspace_membership.sql` — only if Phase 2 count > 0.
- Test files under `apps/web-platform/test/...` (Phase 7).

## Open Questions

1. **Non-member-claim solo user** (claim points at a team they were removed from / never joined): plan recommends **reset-to-own-workspace + breadcrumb** (non-blocking, matches today's shipping self-heal, never strands). Confirm vs a hard not-ready gate. (Kieran P2 — recommended path applied; flag for `/work`/operator if the product intent differs.)
2. **Phase 0 prod diagnostics** (incident user `52af49c2` session/membership state) — pull read-only at `/work` time to confirm the mechanism; does not block code (TR1 short-circuit). Co-membered SKIP backlog count is **PR-2 recon**, not PR-1.

## Open Code-Review Overlap

None (checked `gh issue list --label code-review --state open` against the file list).

## Domain Review

**Domains relevant:** Engineering, Product, Legal, Finance (carry-forward from brainstorm `## Domain Assessments`).

### Engineering (CTO) — reviewed (carry-forward)
Divergence `cc-dispatcher.ts:1533-1556` + `:1703`; unified resolver resolved once + threaded. PR-2 migration → `data-migration-expert` + `data-integrity-guardian`.
### Legal (CLO) — reviewed (carry-forward)
Solo fallback is not cross-tenant exposure (own `userId`, never a sibling); forbid `MIN(created_at)`. Column-drop gating is PR-2.
### Finance (CFO) — reviewed (carry-forward)
Billing stays user-keyed (#5438 follow-up).

### Product/UX Gate
**Tier:** blocking · **Decision:** reviewed (carry-forward + spec-flow this session)
**Agents invoked:** spec-flow-analyzer (this session), cpo (brainstorm carry-forward), ux-design-lead (brainstorm — `.pen` on disk)
**Skipped specialists:** none · **Pencil available:** yes — `knowledge-base/product/design/workspace-connection/member-owner-repo-states.pen`
#### Findings
spec-flow surfaced 7 flow gaps; after the simplicity review they collapse to: db-error transient copy, member-solo-no-repo switcher (team-id-carrying, name-fallback), owner reconnect, breadcrumb branch-correctness. Indeterminate-role → db-error; provisioning-in-progress is near-unreachable given mig 091.

## Observability

```yaml
liveness_signal:
  what: repo_resolver_divergence Sentry issue (captureMessage via reportSilentFallback)
  cadence: on-event (non-member-claim reset, or self-heal-failed)
  alert_target: queryable by fingerprint in PR-1; Sentry issue-alert routing is a fast-follow
  configured_in: apps/web-platform/server/observability.ts (emit)
error_reporting:
  destination: Sentry (hashed userId + both workspace ids in extra)
  fail_loud: true (was zero-Sentry/invisible — this is the fix)
failure_modes:
  - mode: non-member team claim (removed/stale) → reset to solo
    detection: repo_resolver_divergence issue, op=non-member-claim-reset
    alert_route: Sentry issue (query by fingerprint; alert rule fast-follow)
  - mode: cold-dispatch self-heal fails
    detection: repo_resolver_divergence issue, op=self-heal-failed
    alert_route: Sentry issue (query by fingerprint)
logs:
  where: pino stdout (web-platform container) mirrored to Sentry
  retention: Sentry default
discoverability_test:
  command: "query Sentry issues API for fingerprint 'repo-resolver-divergence' (no ssh)"
  expected_output: issue present after a member-divergence repro in dev
```

## Infrastructure (IaC)

PR-1 introduces **no new infrastructure** — the breadcrumb reuses the existing Sentry emit path.
The `sentry_issue_alert` rule (routing first-seen of the `repo-resolver-divergence` fingerprint to
the operator) is a **fast-follow** added once the breadcrumb has demonstrably fired in soak, via
`apps/web-platform/infra/sentry/*.tf` + `apply-sentry-infra.yml` (`-target=sentry_issue_alert.*`),
mirroring #5434. Deferred deliberately per the simplicity review — breadcrumb alone makes the
signal queryable (no SSH), which satisfies the observability gate for PR-1.

## Architecture Decision (ADR/C4)

[plan Phase 2.10 — `wg-architecture-decision-is-a-plan-deliverable`]

### ADR
Amend **ADR-044**: record **always-enforce-workspace** — every user owns a guaranteed 1-member
personal workspace; connection keys on workspace; the dispatch resolver fails closed to an explicit
not-ready (`db-error`) state and resets a non-member claim to the user's own workspace, never to a
`userId` solo *sentinel*. `status: adopting` (fully holds after the PR-2 drop). Add to
`## Alternatives Considered`: "keep dual user/workspace keying with silent solo fallback" (rejected —
the incident). In-scope deliverable (Phase 6), not deferred (closed #5440).
### C4 views
**Container**: the connection edge is **read=Workspace / write=User (dual, `adopting`)** — PR-1 cuts over only the read path; connect-time writers still target `users.*` until PR-2 (deepen arch P2 — a wholly-Workspace edge would misrepresent the shipped state). **Component**: `cc-dispatcher` consumes one `resolveActiveWorkspace` result feeding path+repo+install+self-heal (`:1703`). Route via `/soleur:architecture` (Concierge-only, `c4-edit` flag, per commit `3c8849655`).
### Sequencing
ADR authored now (`status: adopting`); C4 edit Phase 6. Not postponed to its own issue.

## GDPR / Compliance

PR-1's regulated surface is `workspace_members` reads (RLS-protected, mig 053 `is_workspace_member`)
+ the conditional FR5 residual backfill (owner role, own workspace — no cross-user data movement).
The heavy regulated surface (column drop, DSAR, Art.17 erasure) lands in **PR-2**;
`/soleur:gdpr-gate` runs on the PR-2 migration diff. CLO brainstorm gating carried: dropped columns
are in the Art.15/30 DSAR surface (`dsar-export.ts`); `account-delete.ts` must not reference dropped
columns post-drop (mig-064 23514 saga-abort class). **Deliberate scoping** (recorded, not silent):
PR-1 changes no schema-drop/DSAR/erasure path; deepen-plan's brand-survival triad re-checks.

## Acceptance Criteria

### Pre-merge (PR-1)
- [ ] `resolveActiveWorkspace`: `ok(userId)` for solo/unbound; `ok(team)` for member; `ok(userId, resetFromClaim)` for non-member team claim; `{ok:false,"db-error"}` on probe error.
- [ ] **TR1 cross-tenant test:** probe db-error returns `{ok:false}`, NEVER the claim id; no `MIN(created_at)`/first-membership fallback.
- [ ] Path/repo/install resolve to the same id for a team member; assert **no raw `resolveCurrentWorkspaceId` remains on the dispatch path** (incl `:1703`), AND **no caller of the silent `resolveActiveWorkspaceIdWithMembership` remains** (it was refactored into `resolveActiveWorkspace`).
- [ ] **Reset clone-dir test:** claim=team-not-member → all of `workspacePath`/install/repo/`:1703` derive from one `resolveActiveWorkspace` result; the clone dir is `/workspaces/<userId>` (not `/workspaces/<team>`).
- [ ] **Owner-gate confused-deputy:** `p_workspace_id` === the workspace id every UPDATE/`deleteWorkspace`/mirror in the handler targets (= `user.id` in PR-1).
- [ ] **Breadcrumb fingerprint:** deduped by `(userId, resetFromClaim)` (not just `op`) — does not re-fire per dispatch; `extra` keys are exactly `{activeClaimWorkspaceId, resolvedWorkspaceId}` (no repoUrl/installationId/raw-userId).
- [ ] db-error renders transient copy — asserts NO switcher, NO reconnect.
- [ ] Member-solo-no-repo renders a switcher deep link carrying the **target team id** (multi-team-safe); unresolvable team name → name-omitted fallback.
- [ ] `disconnect` + `setup` routes 403 non-owner; member repo card read-only.
- [ ] Breadcrumb fires on non-member-claim-reset + self-heal-failed only; NOT on db-error/cloning.
- [ ] FR5: Phase 2 count recorded; residual backfill shipped iff count > 0 (idempotent).
- [ ] FR7: ADR-044 amended (`status: adopting`); C4 connection-owner edge updated via `/soleur:architecture`.
- [ ] `tsc --noEmit` clean; vitest green.

### Post-merge (operator/automated)
- [ ] Phase 2 backfill (if any) verified: membership-null count returns 0 (read-only).
- [ ] Sentry breadcrumb confirmed queryable by fingerprint after a dev repro.
- [ ] `Ref #5437` in PR body (not `Closes` — PR-2 remains).
- [ ] Fast-follow filed: `sentry_issue_alert` routing for `repo-resolver-divergence`.

## Risks & Mitigations

- **Removing the solo fallback strands owners** — mitigated: `claim===userId`/unbound/non-member-claim all return an `ok` own-workspace id; `{ok:false}` only on probe db-error.
- **db-error masquerading as structural** — distinct reason + distinct transient copy; never tells a transient fault to switch.
- **Cross-tenant breach via wrong-workspace resolution** — structurally impossible (only `ok` returns are membership-verified or own `userId`).
- **`:1703` left un-threaded** — explicitly in Files to Edit + an AC; lands atomically with Phase 1.

## Sharp Edges

- `## User-Brand Impact` filled (else deepen-plan Phase 4.6 halts).
- `apps/web-platform` runner is **vitest** (not bun test); test paths must match `vitest.config.ts` include globs. Typecheck via in-package `./node_modules/.bin/tsc --noEmit` (no root `workspaces` field → `npm run -w` fails).
- `reportSilentFallback` first arg is `err: unknown` — pass a synthetic `Error` so the divergence groups by fingerprint.
- The FR5-is-net-new misread (repo-research read mig 053's "Phase 5" comment, not the live mig 091 trigger): always cite the LATEST `handle_new_user` definition, not the migration that first created the table.

## PR-2 (sketch — soak-gated, planned separately)

Relocate connect-time writers (`repo/setup`, `repo/create`, `detect-installation`, `cron-workspace-sync-health.ts:192`) to `workspaces.*`; reconcile co-membered backfill (mig 080 SKIP backlog); ADR-044 drift gate (`COUNT(*)=0` on `repo_url` AND `github_installation_id`); drop legacy `users.repo_url`/`workspace_path`/`github_installation_id` with `.down.sql`. Update `dsar-export.ts` + `account-delete.ts`. Route through `data-migration-expert` + `data-integrity-guardian` + `/soleur:gdpr-gate`. Credential protection: `REVOKE SELECT (github_installation_id)` + membership-checked SECURITY DEFINER RPC same migration (`2026-03-20-supabase-column-level-grant-override`). Add the `sentry_issue_alert` routing here too.
