---
title: "fix: C4 + KB write path resolves the ACTIVE workspace (ADR-044 write-side cutover)"
date: 2026-06-05
type: fix
semver: minor
app: web-platform
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
status: planned
---

# 🐛 fix: C4 + KB write path resolves the ACTIVE workspace (ADR-044 write-side cutover)

## Enhancement Summary

**Deepened on:** 2026-06-05
**Sections enhanced:** Research Insights (verify-the-negative + precedent-diff folded in)
**Gates passed:** 4.4 precedent-diff, 4.45 verify-the-negative, 4.6 User-Brand Impact, 4.7 Observability, 4.8 PAT-shape

### Key Improvements (grounded against the worktree)
1. **Precedent-diff confirmed.** `resolveInstallationId` self-mints a fresh tenant client
   (`resolve-installation-id.ts:35` `getFreshTenantClient`) before the `tenant.rpc(...)` call, so
   passing a **service-role** client to `resolveActiveWorkspaceRepoMeta` is correct — the RPC step
   self-mints tenant internally to satisfy the RPC's `auth.uid()` membership check. This is the
   load-bearing design fact; the upload route (`kb/upload/route.ts:77-107`) is the exact precedent.
2. **Verify-the-negative confirmed.** The plan's "helper NEVER reads `req.body`/`req.query` for a
   workspace id" is true today (the helper only reads path `params` for the FILE path, never a
   workspace id) — the cutover preserves this IDOR guard. The RPC's `REVOKE … FROM service_role`
   (migration 079:126) confirms the "do not call the RPC with service-role" guidance.
3. **ctx-shape stability confirmed.** c4 PUT consumes only `ctx.user.id`,
   `ctx.userData.github_installation_id`, `ctx.owner`, `ctx.repo`, `ctx.userData.workspace_path`,
   `ctx.relativePath` (route lines 41-46) — all stable across the cutover. **No route file changes.**

### New Considerations Discovered
- The only open implementation hypothesis is the `denied_jti` → 403 deny-list branch (Hypotheses
  section); falsify at /work Phase 0.3 before removing the tenant-mint probe.

## Overview

The LikeC4 diagram editor (and the sibling KB markdown rename/delete path) has a confirmed
read/write **workspace-resolution asymmetry**. The READ path resolves the caller's **active
workspace**; the WRITE path resolves the caller's **solo `users` row**. For any user whose active
workspace ≠ their solo workspace (an invited member viewing a shared workspace), an edit+save
**commits to the wrong repo** (their personal/solo repo) while the reader keeps reading the active
workspace — the edit silently lands in the wrong repo and the displayed diagram never updates.

This plan finishes **ADR-044's write-side cutover** for the two remaining KB write routes by making
the shared resolver `authenticateAndResolveKbPath` active-workspace-aware, using the **exact
composition the `kb/upload` route already ships** (`resolveActiveWorkspaceKbRoot` +
`resolveActiveWorkspaceRepoMeta`). No new resolver is built — the building blocks already exist and
are already in production use on the upload route.

**Confirmed live (prod, 2026-06-05):** user active workspace `754ee124` (jikig-ai/soleur, member
role); their `model.c4` "Founder TEST" edit committed to workspace `c30e6c0a`'s repo
`Elvalio/SAE_for_Soleur` (their solo, owner role). The legacy `users` repo columns are still
populated (ADR-044 soak, dual-written via `mirrorRepoColsToSoloWorkspace`), so the write **succeeds**
but targets the solo repo.

### Root cause (one diagram)

```text
                         model.c4 edit + Save
                                 │
       ┌─────────────────────────┴──────────────────────────┐
       ▼ READ (correct)                                       ▼ WRITE (buggy)
GET /api/kb/c4/project                          PUT /api/kb/c4/[...path]
resolveActiveWorkspaceKbRoot(user.id)           authenticateAndResolveKbPath(req, params)
 → claim-derived current_workspace_id            → from("users").select(
 → membership self-heal to solo                       "workspace_path, repo_url,
 → workspaces.repo_status                              github_installation_id")  ← SOLO ROW
 → kbRoot = ACTIVE workspace                      → owner/repo/installation = SOLO repo
       │                                                 │
       ▼                                                 ▼
 reads ACTIVE workspace clone                    writes SOLO workspace repo  ✗ DIVERGENCE
```

### Fix in one line

Replace the `from("users")` block inside `authenticateAndResolveKbPath` with the upload route's
two-resolver composition, so owner/repo/workspace_path/installationId all key off the **active**
workspace (membership-self-healed, IDOR-safe, claim-derived). Verify the Concierge `edit_c4_diagram`
path is already active-workspace-aware (it is) and lock it with a parity regression test.

---

## Research Reconciliation — Spec vs. Codebase

| Claim (from task brief) | Reality (verified against worktree + origin/main) | Plan response |
| --- | --- | --- |
| "feared read-path blast radius if shared helper changed" | `authenticateAndResolveKbPath` is called by **exactly two routes, BOTH writes**: `kb/c4/[...path]` (PUT) and `kb/file/[...path]` (PATCH/DELETE). **Zero read routes** use it (c4/project, tree, content, search call `resolveActiveWorkspaceKbRoot`/`resolveActiveWorkspaceRepoMeta` directly). | **SCOPE = shared resolver.** No read-path risk exists. Fixing the helper fixes c4 AND the latent kb/file markdown bug in one change. |
| "a new `resolveActiveWorkspaceRepoForWrite` is likely needed" | `resolveActiveWorkspaceRepoMeta(userId, supabase, preResolvedActiveWorkspaceId?)` already exists (`workspace-resolver.ts:473`), returns `{ ok, repoUrl, githubInstallationId }` for the active workspace, and is **already used by `kb/upload`**. | **No new resolver.** Compose the two existing resolvers exactly as `kb/upload/route.ts:77-107` does. |
| "call `resolve_workspace_installation_id` via `supabase.rpc`" | The RPC EXECUTE is granted to `authenticated` only and gates on `auth.uid()`. It must run on a **tenant** client, not service-role. `resolveActiveWorkspaceRepoMeta` already handles this: it self-mints a fresh tenant client inside `resolveInstallationId(userId, activeId)`. | **Do not call the RPC directly.** Pass a service-role client to `resolveActiveWorkspaceRepoMeta` for the `workspaces.repo_url` read; the RPC step self-mints tenant internally. Matches the upload route. |
| "Concierge edit_c4_diagram may need a fix" | cc-dispatcher already resolves: `workspacePath ← fetchUserWorkspacePath → resolveActiveWorkspacePath`; `repoUrl ← getCurrentRepoUrl(args.userId)` (active `workspaces.repo_url`); `installationId ← resolveInstallationId(args.userId)` (active id + membership RPC); owner/repo parsed from that server-resolved repoUrl; `effectiveInstallationId` self-heals to repo-owner install. | **No concierge code change.** Add a parity regression test asserting the concierge and the PUT route resolve the identical active-workspace source. |

---

## User-Brand Impact

**If this lands broken, the user experiences:** their LikeC4 diagram edit (or KB markdown
rename/delete) silently commits to the wrong GitHub repo — their personal/solo repo instead of the
shared workspace they are viewing — and the on-screen diagram never reflects the save. They believe
their edit was lost; in fact it landed in a repo their collaborators can't see.

**If this leaks, the user's diagram/KB edits are exposed via:** cross-workspace write-target
confusion — content intended for a shared workspace is committed to a different repo. This is
mitigated by membership-scoped, claim-derived, self-healing resolution: the resolver only ever
yields a workspace the caller is a member of (a non-member claim self-heals to the caller's own solo
workspace), so there is **no new unauthorized cross-tenant write surface** — a user can only ever
write to a workspace they belong to.

**Brand-survival threshold:** single-user incident — a member's edits silently going to the wrong
repo is a per-user data-integrity / trust failure.

> CPO sign-off required at plan time before `/work` begins. Invoke CPO domain leader if not already
> covered by Phase 2.5 carry-forward, or confirm CPO has reviewed the brainstorm.
> `user-impact-reviewer` will be invoked at review-time (handled by review/SKILL.md conditional-agent block).

---

## Files to Edit

### Primary fix
- **`apps/web-platform/server/kb-route-helpers.ts`** — `authenticateAndResolveKbPath`. Replace the
  tenant `from("users").select("workspace_path, workspace_status, repo_url, github_installation_id")`
  block (lines ~116-140) + the owner/repo parse (lines ~171-175) with the upload route's two-resolver
  composition:
  - import `createServiceClient` from `@/lib/supabase/server`, and
    `resolveActiveWorkspaceKbRoot` + `resolveActiveWorkspaceRepoMeta` from `@/server/workspace-resolver`;
  - after auth (`supabase.auth.getUser()`), build `const serviceClient = createServiceClient()`;
  - `const access = await resolveActiveWorkspaceKbRoot(user.id, serviceClient)` →
    map `access.status` (404/503) to the existing `err()` responses (preserve the 503 "Workspace not
    ready" / 404 contract the client hook discriminates);
  - `const repoMeta = await resolveActiveWorkspaceRepoMeta(user.id, serviceClient, access.activeWorkspaceId)`
    → map `repoMeta.status` (400/404/503) to `err()` ("No repository connected" / "Workspace not ready");
  - assemble `userData = { workspace_path: access.workspacePath, repo_url: repoMeta.repoUrl,
    github_installation_id: repoMeta.githubInstallationId }`;
  - **keep** `kbRoot = access.kbRoot` (do NOT recompute via `path.join(userData.workspace_path, ...)`
    — `access.kbRoot` is already `<active>/knowledge-base`, byte-identical and source-of-truth);
  - **keep** the existing path validation, null-byte check, markdown block, `isPathInWorkspace`,
    and symlink/`lstat` checks unchanged — they now run against the ACTIVE kbRoot;
  - parse owner/repo from `repoMeta.repoUrl` via the existing
    `.replace(/\.git$/, "").split("/")` shape (unchanged);
  - **delete** the now-dead tenant-mint try/catch around `getFreshTenantClient` IF and only if no
    other code in the function still needs the tenant client (it does not — the only tenant read was
    the `users` SELECT). Preserve the `reportSilentFallback` Sentry-mirror posture by relying on the
    resolvers' own internal `reportSilentFallback` calls (they already mirror every query error).
    **Decision point for /work:** confirm no consumer of the removed 503/`jwt_mint`/`denied_jti`
    branch semantics remains; the resolvers return 503 for readiness failures, preserving the
    client-visible contract. If the deny-list (`denied_jti` → 403) behavior is load-bearing for these
    write routes, retain a minimal tenant-mint probe; otherwise remove. See Sharp Edges.
  - update the `KbRouteContext` doc-comment + the helper's header doc-comment to state it now resolves
    the ACTIVE workspace (ADR-044 write-side cutover), citing the upload-route precedent.

### Tests
- **`apps/web-platform/test/kb-route-helpers.test.ts`** — add cases:
  (a) member viewing a shared workspace (active ≠ solo) resolves the **active** workspace's
  owner/repo/workspacePath/installationId, NOT the solo `users` row;
  (b) solo caller (active == solo) still resolves their own workspace (no regression);
  (c) non-member stale claim self-heals to solo (resolver guarantee — assert the helper inherits it);
  (d) `repoMeta.status` 404 → "No repository connected"; 503 → "Workspace not ready"; 400 → "No
  repository connected" — mapping parity with the upload route.
- **`apps/web-platform/test/server/kb-route-helpers.tenant-isolation.test.ts`** — extend the
  tenant-isolation suite: a member MUST NOT be able to resolve a workspace they are not a member of
  (the RPC + self-heal guarantee); assert the helper never reads `req.body`/`req.query` for a
  workspace id (IDOR guard).
- **`apps/web-platform/test/kb-security.test.ts`** — assert the symlink/path-traversal guards still
  fire against the ACTIVE kbRoot (regression: the guards must not have been bypassed by the kbRoot
  source change).
- **`apps/web-platform/test/kb-delete.test.ts`** — confirm the kb/file PATCH/DELETE path now targets
  the active workspace's owner/repo (sibling-route regression coverage).
- **NEW: `apps/web-platform/test/c4-write-active-workspace-parity.test.ts`** — the parity assertion:
  given a member whose active workspace ≠ solo, BOTH the PUT-route resolution
  (`authenticateAndResolveKbPath`) AND the concierge resolution
  (`fetchUserWorkspacePath` / `getCurrentRepoUrl` / `resolveInstallationId`) yield the SAME
  owner/repo/workspacePath/installationId for the active workspace. This locks the read/write/chat
  three-way agreement so a future regression in either surface is caught.

### Allowlist / coverage
- **`apps/web-platform/.service-role-allowlist`** — `authenticateAndResolveKbPath` now constructs a
  `createServiceClient()` (it previously used only a tenant client). Verify the function/file is
  represented in the service-role allowlist (the upload/tree/content/c4-project routes already are);
  add the entry if the allowlist is keyed per call-site. **Verify at /work:** read the allowlist
  format before editing.
- **`apps/web-platform/lib/auth/csrf-coverage.test.ts`** — no change expected (CSRF validation in
  the helper is unchanged); confirm the test still passes after the edit.

## Files to Create
- `apps/web-platform/test/c4-write-active-workspace-parity.test.ts` (above).

> **Test-runner note:** `apps/web-platform` uses **vitest**, not bun test (per `apps/web-platform/bunfig.toml`
> `[test] pathIgnorePatterns` and `vitest.config.ts`). Run via `./node_modules/.bin/vitest run <path>`.
> New test FILE must live under `apps/web-platform/test/**/*.test.ts` to match `vitest.config.ts`
> `include:` globs (verify the glob before placing the file). Do NOT co-locate under `server/`.

---

## Open Code-Review Overlap

**1 open scope-out touches `kb-route-helpers.ts`:** **#2246** — `refactor(kb): low-severity polish
from PR #2235 review`. Relevant items:
- Item #6 — duplicate `parseOwnerRepo` between `kb-route-helpers.ts:116-119` and
  `upload/route.ts:135-144`. **Disposition: Acknowledge (and opportunistically reduce).** This plan's
  cutover replaces the helper's inline owner/repo derivation with the SAME
  `.replace(/\.git$/,"").split("/")` shape the upload route uses; if /work finds it trivial to extract
  the shared parse to `server/github-app.ts` while editing the block anyway, fold it in and add
  `Refs #2246`. Otherwise leave #2246 open — the dedup is not required for the fix.
- Item #13 — "add comment explaining why upload can't use `authenticateAndResolveKbPath`".
  **Disposition: Defer with note.** This plan makes the helper adopt the upload route's resolution
  composition, so the rationale shifts (the helper now CAN share the active-workspace resolution; the
  remaining difference is FormData `targetDir` vs URL path). Update #2246 item #13 with a
  re-evaluation note: "revisit after the active-workspace cutover lands — the helper now shares the
  upload route's resolver composition."
- Items #1/#4/#9 (return-type `Response` vs `NextResponse`, hoisted `err()`, sync I/O) — **Acknowledge,
  out of scope.** Pre-existing polish unrelated to the workspace-resolution fix; #2246 stays open.

/work must re-run the `gh issue list --label code-review` overlap query against the FINAL file list
before coding and confirm these dispositions still hold.

---

## Implementation Phases

> **Phase ordering is load-bearing.** The contract change (helper resolution) ships in Phase 2; the
> consumer routes (c4 PUT, kb/file) are NOT edited — they already consume the helper's `ctx` shape,
> which is unchanged (`owner`, `repo`, `userData.workspace_path`, `userData.github_installation_id`,
> `kbRoot`, …). This is the key simplifier: the cutover is **entirely inside the helper**; no route
> file changes.

### Phase 0 — Preconditions (verify, do not rebuild)
1. Confirm `resolveActiveWorkspaceRepoMeta` + `resolveActiveWorkspaceKbRoot` signatures and return
   shapes (`workspace-resolver.ts:350,473`) — already grounded; re-read at /work for drift.
2. Read `kb/upload/route.ts:60-107` — the canonical composition this plan mirrors.
3. Confirm `authenticateAndResolveKbPath`'s `ctx` consumers (c4 PUT lines 40-48; kb/file
   PATCH/DELETE) read ONLY `ctx.owner`, `ctx.repo`, `ctx.userData.workspace_path`,
   `ctx.userData.github_installation_id`, `ctx.relativePath`, `ctx.filePath`, `ctx.kbRoot`, `ctx.ext`
   — so the `ctx` shape stays stable across the cutover (it does; verify).
4. Confirm the RPC (`migration 079`) requires a tenant client (`auth.uid()`), and that
   `resolveActiveWorkspaceRepoMeta` self-mints tenant inside `resolveInstallationId` — so the helper
   passes a **service-role** client and the credential read stays membership-scoped.
5. Read `.service-role-allowlist` format.

### Phase 1 — RED: failing tests
Write the failing tests in `kb-route-helpers.test.ts` for the member (active ≠ solo) case asserting
active-workspace resolution; the parity test; the status-mapping cases. These FAIL against the
current `from("users")` implementation (it resolves solo).

### Phase 2 — GREEN: cut the helper over
Apply the `authenticateAndResolveKbPath` edit (Files to Edit §Primary). Run vitest until Phase 1
tests pass. No route files change.

### Phase 3 — Parity lock + sibling regression
Add the concierge-parity test and the kb/file PATCH/DELETE regression coverage. Confirm
`kb-security.test.ts` symlink/traversal guards still fire against the active kbRoot.

### Phase 4 — REFACTOR + docs
Tidy the helper (remove dead tenant-mint code if confirmed unused in Phase 0.3/§Primary decision
point), update doc-comments, ensure `reportSilentFallback` posture is preserved via the resolvers'
own mirroring.

### Phase 5 — Full suite + typecheck
`./node_modules/.bin/vitest run` (web-platform suite) + `tsc --noEmit`. Confirm CSRF coverage,
tenant-isolation, kb-delete, kb-security all green.

---

## Acceptance Criteria

### Pre-merge (PR)
- [ ] **AC1 — active-workspace write (the fix).** For a member whose `current_workspace_id` ≠
  `users.id`, `authenticateAndResolveKbPath` returns `ctx.owner`/`ctx.repo`/
  `ctx.userData.workspace_path`/`ctx.userData.github_installation_id` derived from the **active**
  workspace's `workspaces.repo_url` + the membership RPC — asserted by a vitest case that mocks
  active ≠ solo and checks the resolved repo is the active one, NOT the solo `users` row.
- [ ] **AC2 — solo no-regression.** For a solo caller (active == solo), the resolved
  owner/repo/workspacePath/installationId equals the prior behavior (byte-identical to the
  solo-workspace resolution).
- [ ] **AC3 — membership is the authorization.** A vitest case proving a non-member stale claim
  self-heals to the caller's solo workspace (the helper inherits
  `resolveActiveWorkspaceIdWithMembership`'s guarantee); the helper NEVER reads a workspace id from
  `req.body`/`req.query` (grep the helper body: zero `request.json()`/`searchParams` reads for a
  workspace id).
- [ ] **AC4 — status-contract parity.** `access.status` 404→"Workspace not found"/404,
  503→"Workspace not ready"/503; `repoMeta.status` 404→"No repository connected"/404,
  400→"No repository connected"/400, 503→"Workspace not ready"/503. Asserted per-branch.
- [ ] **AC5 — sibling route fixed.** A `kb-delete.test.ts` case confirms PATCH/DELETE on
  `kb/file/[...path]` targets the ACTIVE workspace's owner/repo for a member (active ≠ solo).
- [ ] **AC6 — guards intact.** `kb-security.test.ts` symlink + path-traversal cases still reject
  against `access.kbRoot` (the active kbRoot); no guard was bypassed by the kbRoot source change.
- [ ] **AC7 — concierge parity.** `c4-write-active-workspace-parity.test.ts` asserts the PUT-route
  resolution and the concierge `edit_c4_diagram` resolution yield identical
  owner/repo/workspacePath/installationId for a member's active workspace.
- [ ] **AC8 — service-role allowlist.** `.service-role-allowlist` includes (or already covers)
  `authenticateAndResolveKbPath`'s new `createServiceClient()` call-site; the allowlist test passes.
- [ ] **AC9 — typecheck + full suite green.** `tsc --noEmit` clean; web-platform vitest suite green
  (CSRF coverage, tenant-isolation, kb-delete, kb-security, kb-route-helpers).
- [ ] **AC10 — security-sentinel review** completed on the diff (write path + installation-token
  selection); findings folded in or scoped out with rationale.

### Post-merge (operator)
- [ ] **AC11 — prod round-trip verify (the original repro).** As the confirmed-live member (active
  workspace `754ee124` / jikig-ai/soleur, member role), edit `model.c4`, Save, and confirm via
  `gh api /repos/jikig-ai/soleur/commits` (active repo) that the commit landed in the **active**
  repo — and that `Elvalio/SAE_for_Soleur` (solo) receives NO new commit.
  `Automation:` GitHub API read via `gh` CLI — bake into ship post-merge verification.

---

## Test Scenarios

| # | Scenario | Setup | Expected |
| --- | --- | --- | --- |
| TS1 | Member edits shared-workspace diagram | active=`754ee124` (member), solo=`c30e6c0a` (owner) | Commit lands in active repo (jikig-ai/soleur); diagram re-renders & reflects edit |
| TS2 | Solo user edits own diagram | active==solo | Commit lands in own repo (unchanged behavior) |
| TS3 | Stale non-member claim | `current_workspace_id` points at a workspace the caller left | Self-heals to solo; writes to solo repo (NEVER the sibling) |
| TS4 | Active workspace has no repo connected | active workspace `repo_url` is null | 404 "No repository connected" (no write attempted) |
| TS5 | Active workspace not ready | owner `users.workspace_status` ≠ "ready" | 503 "Workspace not ready" |
| TS6 | Installation revoked / RPC deny | RPC returns NULL (non-member or revoked grant) | 400 "No repository connected" (membership-scoped deny, indistinguishable from not-connected) |
| TS7 | IDOR attempt | caller sends a workspace id in body/query | Ignored; resolution is claim-derived only |
| TS8 | kb/file rename by member | member renames a markdown file in shared workspace | Rename commits to active repo |
| TS9 | Symlink / traversal | crafted relativePath / planted symlink at fullPath | Rejected by existing guards against active kbRoot |
| TS10 | Concierge edit parity | member asks Concierge to edit_c4_diagram | Concierge writes to the SAME active repo as the UI PUT path |

---

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO), Legal/Compliance (CLO — data-integrity /
tenant-isolation lens)

### Engineering (CTO)
**Status:** to-run (Phase 2.5 spawns domain leader)
**Assessment focus:** write-path workspace resolution, GitHub App installation-token selection,
membership-scoped self-heal as the authorization boundary, service-role-vs-tenant client split for
the RPC, no new cross-tenant surface. Confirm the helper cutover preserves the 503/404 client
contract and the symlink/TOCTOU guards.

### Legal/Compliance (CLO)
**Status:** to-run
**Assessment focus:** tenant isolation (a member can only write to a workspace they belong to);
no cross-tenant data movement; the fix REDUCES a data-integrity exposure (edits landing in the
wrong repo). No regulated-data schema change (no migration). GDPR gate (Phase 2.7): trigger (b)
fires — `single-user incident` threshold declared — so gdpr-gate runs advisory.

### Product/UX Gate
**Tier:** none
**Decision:** N/A — no new user-facing page, flow, or component; this is a server-side resolution
fix. The visible behavior change (edits now round-trip correctly) is a bug fix, not a new surface.
No `components/**/*.tsx` or `app/**/page.tsx` created → mechanical escalation does not fire.

---

## Infrastructure (IaC)

None. Pure code change against an already-provisioned surface (`apps/web-platform/server/` +
`apps/web-platform/app/api/`). No new server, secret, vendor, cron, or persistent process. The RPC
(`resolve_workspace_installation_id`) and its grants already exist (migration 079, shipped). No
migration in scope (ADR-044 legacy-column decommission is explicitly OUT OF SCOPE — separate
soak-gated work).

---

## Observability

```yaml
liveness_signal:
  what: c4_write structured log event (server/c4-writer.ts logger.info "kb/c4: diagram source written")
        already emits { event: "c4_write", userIdHash, path }; the cutover does not change the event,
        but the resolved owner/repo now reflects the ACTIVE workspace
  cadence: per save (user-driven, not periodic)
  alert_target: existing kb_tenant_mint_silent_fallback Sentry alert (#4920) + reportSilentFallback
                mirrors from the two resolvers
  configured_in: apps/web-platform/infra/sentry/issue-alerts.tf (existing)
error_reporting:
  destination: Sentry via reportSilentFallback (resolvers) + Sentry.captureException (c4-writer/kb-file routes)
  fail_loud: yes — every resolver query error mirrors to Sentry before returning a 404/503/400;
             write failures already captureException
failure_modes:
  - mode: active-workspace resolves to wrong/null repo (resolver regression)
    detection: resolveActiveWorkspaceRepoMeta returns {ok:false} → 404/400 surfaced to client + Sentry mirror
    alert_route: reportSilentFallback → Sentry (workspace-resolver feature tag)
  - mode: installation RPC deny (non-member / revoked grant)
    detection: resolveInstallationId returns null → repoMeta 400 → "No repository connected"
    alert_route: resolve-installation-id reportSilentFallback (rpc-read op)
  - mode: write still targets solo repo (the bug regressing)
    detection: c4-write-active-workspace-parity.test.ts (CI) + AC11 prod round-trip
    alert_route: CI red on regression; no prod alert needed (caught pre-merge)
logs:
  where: server pino logs (c4_write, kb_delete, kb_rename events) + Sentry breadcrumbs
  retention: existing pino/Sentry retention (unchanged)
discoverability_test:
  command: "./node_modules/.bin/vitest run apps/web-platform/test/c4-write-active-workspace-parity.test.ts"
  expected_output: "test passes — PUT-route and concierge resolve identical active-workspace owner/repo/installationId"
```

---

## Hypotheses

Root cause is **confirmed** (live prod repro, 2026-06-05), not hypothesized. The only open
implementation hypothesis: whether the `denied_jti` → 403 deny-list branch in the removed
tenant-mint probe is load-bearing for these write routes. **Falsify at /work Phase 0.3:** trace
whether any revocation path relies on the helper's tenant-mint 403 for kb/c4 and kb/file. The
resolvers gate readiness/connectivity/membership independently, so the deny-list is likely
redundant here — but confirm before removing. If load-bearing, retain a minimal tenant-mint probe
(mint then discard) purely for the deny-list, and document why.

---

## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| Removing the tenant-mint block drops the `denied_jti` → 403 deny-list behavior for write routes | Phase 0.3 falsification; retain a minimal probe if load-bearing. Resolvers preserve the 503/404 readiness/connectivity contract regardless. |
| `access.kbRoot` vs recomputed kbRoot drift | Use `access.kbRoot` directly (do NOT recompute) — it is already `<active>/knowledge-base` and is the source of truth the read path uses. |
| Service-role client for the RPC would bypass `auth.uid()` membership | Do NOT call the RPC with service-role. `resolveActiveWorkspaceRepoMeta` self-mints a TENANT client inside `resolveInstallationId` — pass it a service-role client only for the `workspaces.repo_url` read. Mirrors the upload route exactly. |
| Sentry signal loss when removing the helper's `reportSilentFallback` call | The two resolvers each mirror every query error via `reportSilentFallback` already — signal is preserved, not lost. Verify in Phase 4. |
| Precedent drift (upload route changes) | The upload route (`kb/upload/route.ts:77-107`) is the cited precedent. Re-read it at /work Phase 0.2; if it has changed, reconcile. |

---

## Sharp Edges

- **The fix is entirely inside the helper — no route files change.** The temptation will be to "also
  fix the c4 PUT route" or "also fix kb/file". Resist: those routes consume `ctx` which is unchanged.
  Editing them is scope creep and risks divergence.
- **Do NOT build a new `resolveActiveWorkspaceRepoForWrite`.** `resolveActiveWorkspaceRepoMeta`
  already exists and is already in production on the upload route. Compose, don't rebuild.
- **The RPC is tenant-scoped (`auth.uid()`), EXECUTE granted to `authenticated` only.** A service-role
  client cannot read the credential via the RPC. The composition works because
  `resolveActiveWorkspaceRepoMeta` self-mints tenant inside `resolveInstallationId`. Passing a tenant
  client to the whole resolver also works but the upload-route precedent passes service-role (for the
  `workspaces` read) and lets the RPC step self-mint — follow that.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This section is filled (threshold:
  single-user incident).
- **Test placement.** New parity test MUST live under `apps/web-platform/test/**/*.test.ts` (vitest
  `include:` glob) and run via `./node_modules/.bin/vitest run`, NOT bun test (bunfig.toml ignores
  the path). Co-locating under `server/` = silently never run.
- **OUT OF SCOPE:** ADR-044 decommission of legacy `users` repo columns (separate soak-gated work).
  This plan completes the WRITE-side cutover for the two remaining KB write routes; it does not drop
  the dual-written columns.
