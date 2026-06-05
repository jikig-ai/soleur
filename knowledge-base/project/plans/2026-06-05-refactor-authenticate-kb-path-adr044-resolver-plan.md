---
title: "Migrate authenticateAndResolveKbPath to the ADR-044 membership-scoped resolvers"
date: 2026-06-05
type: refactor
issue: 4956
branch: feat-one-shot-4956-kb-route-helpers-adr044
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: draft
related_adrs: [ADR-044, ADR-038]
related:
  - 4953  # share+upload consolidation (Workstream B) — direct precedent
  - 4559  # ADR-044 read-cutover + resolve-installation-id rework
  - 4543  # joined-workspace dual-ownership bug this class fixes
  - 4929  # tenant-mint fallback revert (removed kb-route-helpers from allowlist)
  - 4918  # kb_tenant_mint_silent_fallback Sentry alert
related_learnings:
  - knowledge-base/project/learnings/best-practices/2026-06-05-adr-resolver-migration-must-sweep-write-routes-not-just-read-routes.md
---

# Migrate `authenticateAndResolveKbPath` to the ADR-044 resolvers ♻️

## Enhancement Summary

**Deepened on:** 2026-06-05
**Gates passed:** 4.6 User-Brand Impact (threshold present + valid), 4.7 Observability
(5/5 fields, no SSH, no placeholders), 4.8 PAT-shaped (no match), 4.9 UI-wireframe
(no UI surface → skip).

### Key Improvements (verified against code)

1. **Status-code reconciliation (the v1 "highest-risk" Sharp Edge) is DE-RISKED.**
   Verified the three client callers — `components/kb/file-tree.tsx:330-332` (rename),
   `:346-348` (delete), `components/kb/c4-shared.tsx:271` (c4 save) — discriminate ONLY
   on `!res.ok` (any non-2xx) and render `body.error` (the message string). They do NOT
   branch on the specific status code. So the legacy-vs-resolver status divergence
   (503/400 → 404) is NOT load-bearing for client behavior; only the user-facing
   **message string** matters. The helper should map resolver statuses to the legacy
   messages, but a 404-where-was-503 will not break the UI. AC10 downgraded from
   blocking-risk to message-parity check.
2. **Allowlist gate mechanics nailed down.** The enforcing gate is
   `apps/web-platform/scripts/service-role-allowlist-gate.sh` (test:
   `test/ci/service-role-allowlist-gate.test.sh`). It greps each `.ts` for a
   `createServiceClient` import and FAILs if the importing file is not a verbatim line
   in `.service-role-allowlist`. Re-add the EXACT path
   `apps/web-platform/server/kb-route-helpers.ts` AND update the removal-comment at
   `.service-role-allowlist:66` (which currently lists `kb-route-helpers` among removed
   files).
3. **The Sentry alert does NOT go dark.** Confirmed `kb-sync.tenant-mint`
   (`app/api/kb/sync/route.ts:62`) is an independent live tenant-mint surface; this
   migration only narrows the IS_IN, it does not disarm the alert.

### New Considerations Discovered

- The helper currently passes `userData.workspace_path` into both `syncWorkspace` and
  (for c4) `writeC4Diagram` → `renderC4Model(workspacePath)`. After migration this
  becomes `access.workspacePath`. The upload route already proves `syncWorkspace` works
  off `access.workspacePath`; the c4 re-render path (`renderC4Model`) is the only
  active-path consumer not yet exercised by a shipped migration — call it out in tests.
- `resolveActiveWorkspaceRepoMeta` returns `400` (repo connected, no installation),
  `404` (no repo_url), `503` (workspaces read error). The legacy helper returned `400
  "No repository connected"` for BOTH the no-repo and no-installation cases. Map both
  resolver `400` and `404` to the legacy `"No repository connected"` message for
  message parity (the client shows the string, not the code).

## Overview

`authenticateAndResolveKbPath` (`apps/web-platform/server/kb-route-helpers.ts:50`)
is the last KB write-route consumer still on the legacy pre-ADR-044 path. It mints
a **per-request tenant client** (`getFreshTenantClient`) and reads the CALLER's
`users.{workspace_path, workspace_status, repo_url, github_installation_id}` under
RLS. It serves the two URL-segment write routes:

- `PATCH` + `DELETE /api/kb/file/[...path]` (rename / delete)
- `PUT /api/kb/c4/[...path]` (save edited LikeC4 source)

PR #4953 (Workstream B) already migrated `kb/share` + `kb/upload` onto the
membership-scoped, service-role resolvers (`resolveActiveWorkspaceKbRoot` +
`resolveActiveWorkspaceRepoMeta`) and removed `resolveUserKbRoot`. This issue is the
remaining write-route sweep called out verbatim in the learning that PR shipped
(`2026-06-05-adr-resolver-migration-must-sweep-write-routes-not-just-read-routes.md`):
"the migration is NOT done until EVERY consumer of the old resolver moves — write
routes are consumers too."

**Why it matters:** the legacy resolver reads the caller's own `users` row, which is
stale/empty for (a) users provisioned after the ADR-044 `users → workspaces`
relocation and (b) an invited member operating on a shared workspace (#4543
dual-ownership). For those users, rename / delete / c4-save returns `503 "Workspace
not ready"` or `400 "No repository connected"` while the service-role resolver
(reading `workspaces.repo_status` + the membership-checked installation RPC) would
succeed. The two resolvers compute the **same** path for a solo owner — the
divergence is the read credential + readiness source + an extra tenant-mint failure
surface, **not the path** (per the learning file).

This is a refactor with no new feature surface, no new infrastructure, and no schema
change. It is a pure consumer-cutover plus one observability-contract edit.

**No new dependency.** Reuses `resolveActiveWorkspaceKbRoot`,
`resolveActiveWorkspaceRepoMeta`, `createServiceClient`, `validateOrigin` — all
already imported elsewhere in `apps/web-platform`.

## Research Reconciliation — Spec vs. Codebase

No spec exists for this branch; planning input is the issue body + the precedent PR
#4953 + the ADR-044 read of source. Premise validation (issue cites #4953, the helper
path, two route paths, the resolvers, and the Sentry alert):

| Claim (issue body) | Reality (verified) | Plan response |
| --- | --- | --- |
| `authenticateAndResolveKbPath` still reads `users.*` via a tenant/RLS client | TRUE — `kb-route-helpers.ts:97-122` mints `getFreshTenantClient` and `.select("workspace_path, workspace_status, repo_url, github_installation_id")` on `users` | Migrate to the service-role resolvers |
| Serves `kb/file` PATCH/DELETE + `kb/c4` mutations | TRUE — `kb/file/[...path]/route.ts:22,136`; `kb/c4/[...path]/route.ts:25` | Both routes preserved; helper signature retained |
| Should migrate to `resolveActiveWorkspaceKbRoot` + `resolveActiveWorkspaceRepoMeta` | Both exist, exported from `server/workspace-resolver.ts:350,473`; `resolveActiveWorkspaceRepoMeta` accepts an optional pre-resolved active id | Compose both inside the helper, passing `access.activeWorkspaceId` to skip the redundant round-trip (mirrors `kb/upload/route.ts:87-91`) |
| Migrating must re-home the `authenticateAndResolveKbPath.tenant-mint` op or adjust the alert IS_IN filter + op-contract test | TRUE — alert `kb_tenant_mint_silent_fallback` filters `op IS_IN "authenticateAndResolveKbPath.tenant-mint,kb-sync.tenant-mint"` (`infra/sentry/issue-alerts.tf:607`); op-contract test pins both slugs (`test/sentry-kb-tenant-mint-alert-op-contract.test.ts:58-67`) | **`kb-sync.tenant-mint` (a SEPARATE live surface in `kb/sync/route.ts:62`) survives this migration — so the alert does NOT go dark.** Drop only the `authenticateAndResolveKbPath.tenant-mint` slug from the IS_IN value AND the op-contract test's `OP_SLUGS` array. See §Sharp Edges. |
| `kb-route-helpers.ts` is on the service-role allowlist | FALSE — REMOVED in PR #4929 (`.service-role-allowlist:267-273`); it is tenant-only today | The migration RE-ADDS service-role to this file (the helper now calls `createServiceClient()`). Must re-add `kb-route-helpers.ts` to `.service-role-allowlist` with a one-line justification — see Phase 4. |

Premise Validation note: all five issue-cited references hold. The single material
divergence from the issue's own framing is favorable: the issue worried the alert
might go dark; verification of `kb/sync/route.ts:62` shows `kb-sync.tenant-mint` is an
independent live tenant-mint surface that keeps the alert armed, so this migration
**narrows** the alert's IS_IN rather than darkening it.

## Chosen Approach — migrate the helper internals, keep the signature

Two designs were considered (see Alternatives). The chosen design keeps
`authenticateAndResolveKbPath`'s **name, signature, options, and `KbRouteContext`
return shape unchanged**, and swaps only its credential-resolution body:

1. Keep CSRF (`validateOrigin` / `rejectCsrf`) and `supabase.auth.getUser()` exactly
   as-is (the auth probe).
2. **Replace** the `getFreshTenantClient` + `users` SELECT block (lines 97-140) with:
   - `const serviceClient = createServiceClient();`
   - `const access = await resolveActiveWorkspaceKbRoot(user.id, serviceClient);`
     → maps `access.{ok:false,status}` to the legacy response contract
     (404 → "Workspace not found"/"No repository connected"; 503 → "Workspace not
     ready"). **See §Sharp Edges for the status-code reconciliation** — the legacy
     helper returned `503` for not-ready and `400` for no-repo, but
     `resolveActiveWorkspaceKbRoot` returns `404` for not-connected. The client hook
     contract must be checked.
   - `const repoMeta = await resolveActiveWorkspaceRepoMeta(user.id, serviceClient, access.activeWorkspaceId);`
     → provides `repo_url` + `github_installation_id`.
3. Build the `userData` object from `{ access.workspacePath, repoMeta.repoUrl, repoMeta.githubInstallationId }` instead of the `users` row.
4. Keep the path / null-byte / markdown / symlink / owner-repo parsing block
   (lines 142-177) **byte-identical** — it operates on `userData.workspace_path` and
   `userData.repo_url`, which are now populated from the active workspace.
5. Remove the now-dead `getFreshTenantClient` / `RuntimeAuthError` /
   `resolveInstallationId` dynamic-import code and their imports.

This preserves: the route call-sites (no edits to `kb/file` or `kb/c4` route bodies),
the CSRF-coverage delegation regex (`csrf-coverage.test.ts:64-70` matches
`authenticateAndResolveKbPath(`), and the `syncWorkspace` re-export.

**Why not inline at the route level (like upload):** `kb/file` has TWO handlers
(PATCH + DELETE) and `kb/c4` has the `blockMarkdown:false` variant + owner/repo
parsing + symlink + markdown-block validation — duplicating the resolver composition
and the validation block across 2 files / 3 handlers is more blast radius and would
break the CSRF-coverage delegation path. Keeping the helper is the YAGNI choice and
matches the learning's "sweep the write routes onto the same resolver" framing.

## User-Brand Impact

**If this lands broken, the user experiences:** rename / delete a KB file, or save an
edited C4 diagram, fails with "Workspace not ready" / "No repository connected" /
"No Project Connected" — OR (worse) a path mismatch writes to / deletes from the
WRONG workspace's clone. For an invited member of a shared workspace this is the exact
#4543 surface the migration is meant to fix; a regression here re-breaks it.

**If this leaks, the user's repo credential / workspace data is exposed via:** the
`github_installation_id` is a GitHub App token grant. The migration moves its read
from the caller's RLS-scoped `users` row to the membership-checked
`resolve_workspace_installation_id` SECURITY DEFINER RPC (via
`resolveActiveWorkspaceRepoMeta`). A mis-wired active-id resolution could let one user
push to / delete from a sibling workspace's repo (cross-tenant write). The resolvers
fail CLOSED to the SOLO workspace (`= userId`), never an arbitrary sibling — the
single load-bearing IDOR guard.

**Brand-survival threshold:** single-user incident — inherited verbatim from ADR-044
(the relocated columns are credentials and the change spans cross-tenant repo access).

> CPO sign-off required at plan time before `/work` begins. CPO is invoked in the
> Domain Review below (Engineering + Product sweep). `user-impact-reviewer` will be
> invoked at review-time per `plugins/soleur/skills/review/SKILL.md`.

## Files to Edit

- `apps/web-platform/server/kb-route-helpers.ts` — swap the credential-resolution
  body of `authenticateAndResolveKbPath` (steps 1-5 above); remove `getFreshTenantClient`
  / `RuntimeAuthError` imports + the dynamic `resolveInstallationId` import; add
  `createServiceClient` + the two resolver imports. The `tenant-mint` try/catch and its
  `op: "authenticateAndResolveKbPath.tenant-mint"` mirror are removed.
- `apps/web-platform/infra/sentry/issue-alerts.tf` — drop
  `authenticateAndResolveKbPath.tenant-mint,` from the `kb_tenant_mint_silent_fallback`
  IS_IN value (line 607), leaving `kb-sync.tenant-mint`; update the block comment
  (lines 565-569) to reflect that `authenticateAndResolveKbPath` no longer has a
  tenant-mint surface (now reads via service-role resolvers), so the live slug is
  `kb-sync.tenant-mint` only.
- `apps/web-platform/test/sentry-kb-tenant-mint-alert-op-contract.test.ts` — remove the
  `authenticateAndResolveKbPath.tenant-mint` entry from `OP_SLUGS` (lines 58-62) and
  update the comment (lines 53-57). The remaining single slug still proves the alert is
  armed.
- `apps/web-platform/test/kb-route-helpers.test.ts` — rewrite the
  `authenticateAndResolveKbPath` test blocks: the happy-path + validation tests
  (`describe` at line 192) must drive the new resolver-mocked path; DELETE the
  `tenant-mint failure (reverted)` describe block (lines 751-end of that block) since
  the tenant-mint surface no longer exists in this helper. Add coverage for: 404/503
  mapping from `resolveActiveWorkspaceKbRoot`, the `repoMeta` not-ok branches, and the
  member-vs-solo active-id resolution (mock both resolvers).
- `apps/web-platform/.service-role-allowlist` — RE-ADD `kb-route-helpers.ts` with a
  one-line note: the ADR-044 migration (#4956) restores a service-role read (the helper
  now calls `createServiceClient()` to feed the membership-scoped resolvers), reversing
  the #4929 removal. Verify the allowlist's enforcing test passes (find via
  `git grep -l "service-role-allowlist" apps/web-platform/test`).

## Files to Create

- None. (New tests land in the existing `kb-route-helpers.test.ts`.)

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC1 — `git grep -n "getFreshTenantClient" apps/web-platform/server/kb-route-helpers.ts`
  returns ZERO. The helper no longer mints a tenant client.
- [x] AC2 — `git grep -n "authenticateAndResolveKbPath.tenant-mint" apps/web-platform`
  (excluding `knowledge-base/`) returns ZERO. The op slug is gone from the helper, the
  Sentry IS_IN, AND the op-contract test.
- [x] AC3 — The `kb_tenant_mint_silent_fallback` alert's IS_IN value contains
  `kb-sync.tenant-mint` and NOT `authenticateAndResolveKbPath.tenant-mint`. Verify the
  block: `awk '/resource "sentry_issue_alert" "kb_tenant_mint_silent_fallback"/{f=1} f{print} f&&/^}/{exit}' apps/web-platform/infra/sentry/issue-alerts.tf | grep "value ="`
  shows the narrowed value.
- [x] AC4 — `sentry-kb-tenant-mint-alert-op-contract.test.ts` passes with the single
  `kb-sync.tenant-mint` slug (and its `kb/sync/route.ts` emit-site assertion).
- [x] AC5 — `kb-route-helpers.test.ts` passes: happy path returns the populated
  `KbRouteContext` with `userData.{workspace_path, repo_url, github_installation_id}`
  sourced from the resolvers; all validation branches (CSRF/401/path/markdown/symlink/
  owner-repo) preserved; resolver-not-ok branches mapped to the correct status.
- [x] AC6 — `csrf-coverage.test.ts` passes: `kb/file` and `kb/c4` routes still satisfy
  the `delegatesToKbHelper` path (the regex `authenticateAndResolveKbPath(` + the
  `if(!x.ok)return x.response` early-return both still match).
- [x] AC7 — `.service-role-allowlist` enforcing test passes with `kb-route-helpers.ts`
  re-added.
- [x] AC8 — `npx tsc --noEmit` clean in `apps/web-platform` (the `KbRouteContext` shape
  is unchanged, so route call-sites compile without edit).
- [x] AC9 — Full `apps/web-platform` vitest suite green
  (`./node_modules/.bin/vitest run` from `apps/web-platform`, per `package.json`
  `scripts.test`).
- [x] AC10 — **Message parity** for the client (VERIFIED de-risked at deepen — clients
  show `body.error`, not the status code). The migrated helper maps resolver-not-ok to
  the legacy MESSAGE strings: `resolveActiveWorkspaceKbRoot` 503 → "Workspace not ready";
  `resolveActiveWorkspaceKbRoot` 404 (not-connected) → "No repository connected";
  `resolveActiveWorkspaceRepoMeta` 400/404 → "No repository connected"; 503 → "Workspace
  not ready". Confirm `components/kb/file-tree.tsx:330-332,346-348` (rename/delete) and
  `components/kb/c4-shared.tsx:271` (c4 save) still render the message via the existing
  `!res.ok` + `body.error` branch — no client edit required.

### Post-merge (operator)

- [ ] AC11 — Apply the Sentry IS_IN change to prod. `Automation:` the
  `apply-sentry-infra.yml` workflow (or the canonical `prd_terraform` triplet) applies
  the `sentry_issue_alert.kb_tenant_mint_silent_fallback` change on merge. PR body uses
  `Ref #4956` (not `Closes`) if the prod apply is post-merge; `gh issue close 4956`
  after the apply succeeds. If the Sentry alert is apply-on-merge via an existing
  workflow, `Closes #4956` is fine — confirm the workflow at ship time.

## Domain Review

**Domains relevant:** Engineering, Product (security/credential surface), Legal/Privacy
(credential read-path; GDPR gate)

### Engineering (CTO)

**Status:** reviewed (deepen-plan will spawn data-integrity-guardian +
security-sentinel + architecture-strategist at single-user-incident threshold)
**Assessment:** Pure consumer-cutover onto already-shipped, already-reviewed resolvers
(PR #4953). The precedent-diff is exact: `kb/upload/route.ts:77-107` is the
copy-from template. Sharp edges are the status-code remap (404 vs 503/400) and the
service-role allowlist re-add. No new infra, no schema, no migration.

### Product/UX Gate

**Tier:** none
**Decision:** N/A — no UI surface. Files edited are API route helpers, a Terraform
alert, tests, and an allowlist. No `components/**/*.tsx`, `app/**/page.tsx`, or
`app/**/layout.tsx` in Files to Edit. CPO sign-off (required by the single-user-incident
threshold) is on the SECURITY/credential approach, recorded here, not a page design.
**Pencil available:** N/A (no UI surface)

#### Findings

The user-visible behavior is the SAME success path; the change is which credential/
readiness source is read. The improvement is that invited members of shared workspaces
can now rename/delete/c4-save (the #4543 fix extends to write routes).

## Infrastructure (IaC)

This plan edits an EXISTING Terraform resource (`sentry_issue_alert.kb_tenant_mint_silent_fallback`
in `apps/web-platform/infra/sentry/issue-alerts.tf`) — it does NOT introduce new
infrastructure (no new server, service, cron, vendor, secret, DNS, or firewall rule).

### Terraform changes

- `apps/web-platform/infra/sentry/issue-alerts.tf` — narrow one `filters_v2[].tagged_event.value`
  string (drop one comma-joined slug). No new resource, provider, or variable.

### Apply path

Cloud-init: N/A. The Sentry alert change is applied via the existing
`apply-sentry-infra.yml` workflow (or the canonical `prd_terraform` triplet:
`export AWS_ACCESS_KEY_ID=$(doppler secrets get … -c prd_terraform --plain)` + same for
secret + `terraform init -input=false` + `doppler run -p soleur -c prd_terraform
--name-transformer tf-var -- terraform apply -target=sentry_issue_alert.kb_tenant_mint_silent_fallback`).
deepen-plan Phase 4.4 confirms the exact workflow/scope. Blast radius: one alert's
filter value; no app downtime.

### Distinctness / drift safeguards

`dev != prd`: the alert is prod-Sentry-scoped. `lifecycle { ignore_changes = [environment] }`
already present on the resource — preserved.

### Vendor-tier reality check

No tier gate: editing an existing `sentry_issue_alert` value, not creating a
paid-tier-only resource.

## Observability

```yaml
liveness_signal:
  what: "kb_tenant_mint_silent_fallback Sentry issue-alert remains armed via the surviving kb-sync.tenant-mint op slug"
  cadence: "event-driven (first_seen / reappeared / regression), frequency=12"
  alert_target: "IssueOwners → ActiveMembers fallthrough (solo founder)"
  configured_in: "apps/web-platform/infra/sentry/issue-alerts.tf:582"
error_reporting:
  destination: "Sentry (reportSilentFallback → captureException with feature/op tags)"
  fail_loud: "the migrated helper's resolver-not-ok branches return typed Responses; the resolvers themselves mirror every query error to Sentry (resolveActiveWorkspaceKbRoot.workspaces-read / .organizations-read / .owner-readiness-read; resolveActiveWorkspaceRepoMeta.workspaces-read; resolve-installation-id.rpc-read) — so a credential-read failure on this brand-survival write path stays Sentry-visible, not a bare 404/503"
failure_modes:
  - mode: "active-id resolution membership-probe error"
    detection: "reportSilentFallback op:resolveActiveWorkspaceKbRoot.membership-probe"
    alert_route: "feature=workspace-resolver Sentry events (existing)"
  - mode: "workspaces repo_status / repo_url read error"
    detection: "reportSilentFallback op:resolveActiveWorkspaceKbRoot.workspaces-read | resolveActiveWorkspaceRepoMeta.workspaces-read"
    alert_route: "feature=workspace-resolver Sentry events (existing)"
  - mode: "installation RPC deny / failure"
    detection: "reportSilentFallback op:resolve-installation-id.rpc-read"
    alert_route: "feature=resolve-installation-id Sentry events (existing)"
  - mode: "regression: IS_IN narrowed AND kb-sync.tenant-mint slug also removed → alert darks"
    detection: "sentry-kb-tenant-mint-alert-op-contract.test.ts asserts the surviving slug exists on BOTH the emit site (kb/sync/route.ts) and the filter block"
    alert_route: "CI fails the merge"
logs:
  where: "pino structured logs (kb_delete / kb_rename / kb_upload events) + Sentry"
  retention: "Sentry default project retention; pino to stdout is the diagnostic log, not the alert sink"
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/sentry-kb-tenant-mint-alert-op-contract.test.ts test/kb-route-helpers.test.ts lib/auth/csrf-coverage.test.ts"
  expected_output: "all suites pass — proves the alert contract, the helper behavior, and CSRF delegation all hold post-migration, without SSH"
```

## Test Scenarios

1. **Solo owner rename** — `PATCH /api/kb/file/foo.pdf` → resolver returns the solo
   workspace (`activeWorkspaceId === userId`), kbRoot/repo identical to legacy; 200.
2. **Invited member delete on shared workspace** — `current_workspace_id` claim → a
   workspace the caller is a member of but does not own; resolver reads
   `workspaces.repo_status` + the membership-checked installation RPC; 200 (the #4543
   write-route fix). Previously 400 "No repository connected" from the empty solo
   `users` row.
3. **Stale non-member claim** — claim points at a workspace the caller is no longer a
   member of → `resolveActiveWorkspaceIdWithMembership` self-heals to SOLO (never the
   sibling); write lands in the solo workspace, never cross-tenant.
4. **Repo not connected** — `workspaces.repo_url` null → resolver returns the
   no-repo status; helper maps to the legacy contract (AC10 reconciliation).
5. **Workspace not ready** — owner `users.workspace_status !== "ready"` → 503.
6. **C4 save (.md allowed)** — `PUT /api/kb/c4/...` with `blockMarkdown:false` →
   `writeC4Diagram` receives `ctx.userData.{workspace_path, github_installation_id}`
   from the active workspace; commit + re-render.
7. **CSRF reject** — bad origin → 403 before any resolver call (unchanged).
8. **Path traversal / null byte / symlink** — all 400/403 branches unchanged.

## Alternatives Considered

| Alternative | Rejected because |
| --- | --- |
| Inline the two resolvers into each route body (PATCH+DELETE+PUT), like `kb/upload` did | 3 handlers across 2 files duplicate the resolver composition + the owner/repo/symlink validation block; breaks the `csrf-coverage.test.ts` delegation regex; more blast radius for zero benefit. The upload route inlined because it has ONE handler and a bespoke FormData flow. |
| Add a service-role escape only on the availability causes (re-introduce #4919) | Explicitly reverted in #4929 as dead code (PIR #4913 proved the mint works in prod). Do not re-widen. |
| Keep the tenant `users` read as a fallback when the resolver returns not-ready | Re-introduces the dual-source-of-truth divergence ADR-044 forbids; the resolver IS the source of truth. |
| Re-home `authenticateAndResolveKbPath.tenant-mint` to a new op slug | No tenant-mint surface remains in this helper after migration, so there is nothing to re-home. `kb-sync.tenant-mint` keeps the alert armed. Adding a synthetic slug would be a dead emit site. |

## Open Code-Review Overlap

(Run at /work after Files to Edit is frozen, per plan Phase 1.7.5:
`gh issue list --label code-review --state open --json number,title,body --limit 200`
then `jq` each path. Pre-recorded here:) None expected — this is a fresh follow-up
issue; no open code-review scope-out is known to touch `kb-route-helpers.ts`,
`issue-alerts.tf`, or the named tests. Confirm at /work.

## GDPR / Compliance Gate

This plan touches an auth-flow / credential read-path (the `github_installation_id`
token grant) and an API route surface → `/soleur:gdpr-gate` is in-scope and will be
invoked against the plan during /work Phase 2.7 (advisory-only output). The migration
STRENGTHENS tenant isolation (credential read moves from RLS-row-exposed to
membership-scoped definer RPC, per ADR-044 NFR Impacts) — no new processing activity,
no new data field, no new external transfer.

## Precedent Diff (Phase 4.4)

This is a pattern-bound consumer-cutover; the canonical precedent is the migrated
upload route (`app/api/kb/upload/route.ts:76-107`), shipped + reviewed in PR #4953:

```ts
// PRECEDENT — kb/upload/route.ts (already merged):
const serviceClient = createServiceClient();
const access = await resolveActiveWorkspaceKbRoot(user.id, serviceClient);
if (!access.ok) { /* map status → message → NextResponse.json */ }
const repoMeta = await resolveActiveWorkspaceRepoMeta(
  user.id, serviceClient, access.activeWorkspaceId,  // pass pre-resolved id
);
if (!repoMeta.ok) { /* map status → message */ }
const userData = {
  workspace_path: access.workspacePath,
  repo_url: repoMeta.repoUrl,
  github_installation_id: repoMeta.githubInstallationId,
};
```

The migrated `authenticateAndResolveKbPath` body is byte-for-byte this block, dropped
in place of `kb-route-helpers.ts:97-140` (the `getFreshTenantClient` + `users` SELECT +
the `resolveInstallationId` fallback). The IDOR fail-closed guard
(`resolveActiveWorkspaceIdWithMembership` → solo on non-member,
`workspace-resolver.ts:322-324`) is inherited unchanged from the precedent. **No novel
pattern** — the only deltas from the precedent are: (a) the helper KEEPS the CSRF +
path/symlink/owner-repo validation block (upload inlines its own), and (b) the helper
returns the `KbRouteContext` discriminated union instead of writing the response inline.

## Sharp Edges

- **Status-code reconciliation (AC10 — VERIFIED de-risked at deepen).** The legacy
  helper returns `503 "Workspace not ready"` and `400 "No repository connected"`.
  `resolveActiveWorkspaceKbRoot` returns `{status: 404 | 503}`;
  `resolveActiveWorkspaceRepoMeta` returns `{status: 400 | 404 | 503}`. Deepen verified
  the three client callers discriminate ONLY on `!res.ok` and render `body.error` — they
  do NOT switch on the numeric code: `file-tree.tsx:330-332` (rename),
  `file-tree.tsx:346-348` (delete), `c4-shared.tsx:271` (c4 save). So the only
  correctness requirement is **message parity** (AC10), not code parity. Map resolver
  404/400 → "No repository connected", 503 → "Workspace not ready". Do NOT copy the
  upload route's `404 → "Workspace not found"` message — kb/file/kb/c4 used "No
  repository connected" for the no-repo case and the legacy message must be preserved.
- **Service-role allowlist re-add is load-bearing.** The helper now imports
  `createServiceClient`. PR #4929 explicitly REMOVED `kb-route-helpers.ts` from
  `.service-role-allowlist`. The enforcing gate
  (`apps/web-platform/scripts/service-role-allowlist-gate.sh`, exercised by
  `test/ci/service-role-allowlist-gate.test.sh`) greps each `.ts` for a
  `createServiceClient` import and FAILs the merge if the importing file is not a
  verbatim allowlist line. Re-add the EXACT path
  `apps/web-platform/server/kb-route-helpers.ts` AND update the removal-comment at
  `.service-role-allowlist:66` (which lists `kb-route-helpers` among removed files). Do
  NOT defer.
- **Avoid importing service-role into the App-Router `next/headers` graph.** The c4
  write path was deliberately split (`syncWorkspace` re-exported from
  `@/server/workspace-sync`, see `kb-route-helpers.ts:12-20`) so the cc-dispatcher WS
  bundle can import sync without `@/lib/supabase/server`. `authenticateAndResolveKbPath`
  is only reached from App-Router routes (it already imports `@/lib/supabase/server` for
  `createClient`), so adding `createServiceClient` here is safe — but at /work confirm no
  WS-bundle module imports `authenticateAndResolveKbPath` (grep returned only the two
  App-Router route files + the CSRF test). Do not let the resolver imports leak into
  `workspace-sync.ts`.
- **The op-contract test would silently pass if BOTH slugs were removed only from the
  filter but one lingered elsewhere in the .tf** — the test already scopes to the
  resource block (`sentry-kb-tenant-mint-alert-op-contract.test.ts:31-38`). Keep that
  block-scoping; do not loosen to whole-file `toContain`.
- **`writeC4Diagram` reads `ctx.userData.workspace_path`.** After migration this is
  `access.workspacePath` (the active workspace's on-disk path). Confirm `writeC4Diagram`
  + `syncWorkspace` operate on that path — they already do for upload, but c4 has its own
  re-render step (`renderC4Model(workspacePath)`); verify the active path resolves the
  diagrams dir.
- **Do not edit the `kb/file` / `kb/c4` route bodies.** The whole point of keeping the
  helper signature is that the routes are untouched. If a route edit becomes necessary,
  the CSRF-coverage delegation regex (`csrf-coverage.test.ts:64-70`) must still match.
- A plan whose `## User-Brand Impact` section is empty, contains only TBD/placeholder,
  or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above.)

## Notes

- Spec lacks valid `lane:` (no spec file for this branch) — defaulted to `cross-domain`
  (TR2 fail-closed).
- At `single-user incident` threshold, the exit gate recommends running
  `deepen-plan` (already queued in this pipeline) so the data-integrity-guardian +
  security-sentinel + architecture-strategist triad audits the credential read-path and
  the status-code reconciliation — issue classes plan-review (DHH/Kieran/Simplicity)
  is structurally blind to.
