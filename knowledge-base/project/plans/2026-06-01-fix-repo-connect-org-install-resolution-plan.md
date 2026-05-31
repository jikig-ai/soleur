<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
---
title: "Fix repo-connect org/workspace installation resolution"
type: fix
date: 2026-06-01
branch: feat-one-shot-repo-connect-org-install-resolution
roadmap_phase: "Phase 1 — 1.10 Project repo connection (Done, regression fix) + Phase 4 Multi-User Readiness (MU4 team workspaces)"
adr: ADR-044
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# Fix: repo-connect org/workspace installation resolution

## Overview

The GitHub App repo-connection flow resolves a user's installation by matching the user's
**GitHub login** to an installation **account login**. That is correct for a personal install
(login == account) but wrong for an **organization** repo: the org install's account login
(e.g. `jikig-ai`) does not equal the member's personal login (e.g. `deruelle`), so the
login-match picks the wrong install or none. The user then hits **"Project Setup Failed"**
(clone with a wrong/non-existent install) followed by **"No projects found"**.

A second, structural reason the login path dead-ends for org members: `users.github_installation_id`
carries a **UNIQUE** constraint (`users_github_installation_id_unique_idx`). When a first user
already owns an org install on their `users` row, a second member of the same org **cannot** store
the same install id. By ADR-044 design, multi-user-same-install must resolve via **workspace
membership** (`workspaces.github_installation_id` read through the membership-checked
`resolve_workspace_installation_id` SECURITY DEFINER RPC), not via the `users` row.

**The fix is three coordinated changes, all code-only (no migration):**

1. **detect-installation + repos listing** — resolve the *set* of installations the user can
   legitimately reach = (a) any install whose account login matches the user (existing personal
   path, kept) **PLUS** (b) installs carried by the workspaces the user is a member of. Aggregate
   repos across those installs (each install's `GET /installation/repositories`), so an org repo
   whose org login != the user's login is listed. When a repo is *selected*, resolve the **owning**
   installation from the repo (the reachable install whose repo list contains it), not from login.
2. **setup route** — when `users.github_installation_id` is NULL, fall back to the
   **membership-resolved** installation for the target workspace (reuse the existing
   `resolve_workspace_installation_id` RPC via the `resolveInstallationId(userId)` helper used by
   `/api/kb/sync`) so the clone uses the install that actually has the repo. Do **not** write the
   shared install onto `users.github_installation_id` (the unique constraint forbids it) — resolve
   it **per-request**.
3. **Preserve all existing security** — keep CSRF/origin validation, keep membership/ownership
   checks, do not weaken the service-role allowlist. Every install the flow uses must be one the
   user can legitimately reach (own account **OR** a workspace they are a member of) — never an
   arbitrary install id.

The concrete unblock: `ops@jikigai.com` (login `deruelle`, `users.id 754ee124`, owner of
workspace `754ee124` which now carries install `122213433` with access to `jikig-ai/soleur`) must
(a) see `jikig-ai/soleur` in the connectable list and (b) clone it via install `122213433`.

> **Note:** A separate prod-data repair (install `122213433` on the `workspaces` row for workspace
> `754ee124`) was already applied manually. This PR is the **durable code fix** and includes **no
> prod-data step**. After merge+deploy the user re-runs the connect flow, which un-freezes the KB.

## Research Reconciliation — Spec vs. Codebase

| Spec/premise claim | Codebase reality (verified 2026-06-01) | Plan response |
| --- | --- | --- |
| `detect-installation` resolves install by login-match + ownership verify, then stores on `users`. | Confirmed: `route.ts:104` `findInstallationForLogin(githubLogin)`, `:113` `verifyInstallationOwnership`, `:129` `users.update({github_installation_id})`. | Add the membership-reachable install set; keep the login path. |
| `setup` reads `users.github_installation_id` directly and 400s when NULL. | Confirmed: `setup/route.ts:58-69` selects `github_installation_id`; `:64` returns 400 "GitHub App not installed" on NULL. | Insert a membership fallback before the 400. |
| `repos` reads `users.github_installation_id`, 400s when NULL, lists that one install's repos. | Confirmed: `repos/route.ts:23-37`. | Aggregate across the reachable install set. |
| A `resolve_workspace_installation_id` RPC + `resolveInstallationId(userId)` helper already exist (migration 079). | Confirmed: RPC at `079_workspace_repo_ownership_schema.sql:103`; helper at `server/resolve-installation-id.ts:30`, consumed by `/api/kb/sync`, `session-sync`, `kb-route-helpers`, `agent-runner`. | Reuse the helper concept in `setup`; **no new migration.** |
| There is an existing helper that enumerates the SET of installs across ALL of a user's workspaces. | **FALSE — no such helper/RPC exists.** `resolveInstallationId` resolves ONE workspace (current/active or passed). `workspaces.github_installation_id` is REVOKE'd from `authenticated` (079:88), readable only per-workspace via the RPC. | New server helper `resolveReachableInstallationIds(userId)` using the **service client** (already in scope in all three routes) to enumerate the user's `workspace_members` rows -> their workspaces' `github_installation_id`s, plus the login-matched install. Service-role read is the established pattern in these routes (the `users` read is already service-role) and needs no migration. |
| `users.github_installation_id` has a UNIQUE constraint. | Confirmed by premise; detect-installation already has a 23505-handling branch (`route.ts:135-156`) treating a unique violation as "share via workspace membership". | Per-request resolution in setup; never write the shared install to `users`. |
| ADR-044 read path is workspaces-only via the membership RPC; the column is off the `authenticated` grant. | Confirmed: 079 sec.2 REVOKE/GRANT, sec.3 RPC is the only credential reader; service_role keeps its default grant. | Membership enumeration uses the **service client** (trusted server context), mirroring how `setup`/`repos`/`detect` already read `users`. Tenant-client paths still go through the RPC. |

## User-Brand Impact

**If this lands broken, the user experiences:** the connect-repo flow shows "Project Setup
Failed" then "No projects found" — an org member can never connect their org's repo, the workspace
KB stays frozen, and the entire AI-team product is unusable for that account. For
`ops@jikigai.com` specifically, this is the live blocker keeping the KB frozen.

**If this leaks, the user's data/workflow is exposed via:** an over-broad install resolver that
returns an installation the user cannot legitimately reach would let one user clone/act against
**another org's private repos** through a GitHub App grant they have no membership claim to —
cross-tenant repo access via a forged/guessed install id. The single defense is: every install the
flow touches MUST be either login-matched to the user **or** carried by a workspace the user is a
`workspace_members` member of.

**Brand-survival threshold:** single-user incident. One user reaching another org's private install
(or one user permanently unable to connect) is a brand-survival event for a product whose core
promise is "your AI team works on *your* repo, safely."

## Implementation Phases

### Phase 0 — Preconditions (verify before any edit)

- [ ] **0.1 Confirm RPC + helper shape.** `resolveInstallationId(userId, workspaceId?)` returns
      `number | null` and reads via `resolve_workspace_installation_id` (membership-checked, NULL
      for non-members). Verified at `server/resolve-installation-id.ts:30`.
- [ ] **0.2 Confirm service-client read of `workspace_members` is available in the three routes.**
      All three already call `createServiceClient()` (`detect:43`, `repos:22`, `setup:55`).
      Service-role bypasses RLS and the column-REVOKE, so a service-client SELECT of
      `workspace_members (workspace_id) WHERE user_id = <userId>` joined to
      `workspaces (id, github_installation_id)` is readable. Grep:
      `git grep -n 'from("workspace_members")' apps/web-platform/server` confirms the
      service-role enumeration precedent (`org-memberships-resolver.ts:74,128`).
- [ ] **0.3 Confirm `checkRepoAccess(installationId, owner, repo)` exists** (`github-app.ts:596`)
      and maps 200->`ok` / 404->`not_found` / 403->`access_revoked`. This is the per-repo
      owning-install resolver primitive — selecting an install for a chosen repo is "find the
      reachable install whose `GET /repos/{owner}/{repo}` returns 200".
- [ ] **0.4 Confirm `listInstallationRepos(installationId)` returns `Repo[]`** with `fullName`
      (`github-app.ts:643`). Aggregation de-dupes on `fullName`.
- [ ] **0.5 Confirm test runner.** `apps/web-platform/vitest.config.ts` collects node tests at
      `test/**/*.test.ts` and dom tests at `test/**/*.test.tsx`. New server/route tests go under
      `apps/web-platform/test/` with the `.test.ts` suffix. Pinned runner:
      `./node_modules/.bin/vitest run`.

### Phase 1 — New shared resolver: `resolveReachableInstallationIds`

**File to create:** `apps/web-platform/server/reachable-installations.ts`

A single source of truth for "the set of installs this user can legitimately reach". Two
contributing sources, unioned and de-duplicated:

```ts
// apps/web-platform/server/reachable-installations.ts
import { findInstallationForLogin } from "@/server/github-app";
import { reportSilentFallback } from "@/server/observability";

interface ServiceClientLike {
  from: (table: string) => unknown; // PostgREST chain
}

/**
 * Resolve the SET of GitHub App installation ids the user can legitimately
 * reach, for repo-listing/aggregation and owning-install resolution.
 *
 * Sources (unioned, de-duplicated):
 *   (a) Personal/login-matched install — findInstallationForLogin(githubLogin).
 *       Covers the user's own account install AND org installs where GitHub
 *       reports the user as an org member (existing behavior, kept).
 *   (b) Workspace-membership installs — every github_installation_id carried by
 *       a workspace the user is a workspace_members member of. This is the path
 *       that surfaces an ORG install when the org login != the user's login and
 *       the install lives on the user's WORKSPACE row (ADR-044).
 *
 * SECURITY: the membership read is service-role (trusted server context, same
 * as the existing users read in these routes). It is scoped by an explicit
 * `.eq("user_id", userId)` filter, so it only ever returns installs for
 * workspaces THIS user belongs to — never an arbitrary install. The login
 * source is GitHub-authoritative. The union therefore contains only
 * legitimately-reachable installs.
 *
 * Returns a deduped number[] (may be empty -> caller surfaces "not installed").
 */
export async function resolveReachableInstallationIds(
  service: ServiceClientLike,
  userId: string,
  githubLogin: string | null,
): Promise<number[]> {
  const ids = new Set<number>();

  // (a) login-matched install (personal account or GitHub-reported org member)
  if (githubLogin) {
    try {
      const loginInstall = await findInstallationForLogin(githubLogin);
      if (loginInstall) ids.add(loginInstall);
    } catch (err) {
      reportSilentFallback(err, {
        feature: "reachable-installations",
        op: "login-install",
        extra: { userId },
        message: "findInstallationForLogin failed during reachable-install resolution",
      });
    }
  }

  // (b) workspace-membership installs (service-role, user-scoped)
  try {
    const { data, error } = await service
      .from("workspace_members")
      .select("workspaces!inner(github_installation_id)")
      .eq("user_id", userId);
    if (error) {
      reportSilentFallback(error, {
        feature: "reachable-installations",
        op: "membership-installs",
        extra: { userId },
        message: "workspace_members install enumeration failed",
      });
    } else {
      for (const row of data ?? []) {
        // PostgREST embed may be object or array depending on cardinality
        const ws = (row as { workspaces: unknown }).workspaces;
        const list = Array.isArray(ws) ? ws : ws ? [ws] : [];
        for (const w of list) {
          const id = (w as { github_installation_id: number | null }).github_installation_id;
          if (typeof id === "number" && id > 0) ids.add(id);
        }
      }
    }
  } catch (err) {
    reportSilentFallback(err, {
      feature: "reachable-installations",
      op: "membership-installs",
      extra: { userId },
    });
  }

  return [...ids];
}
```

- [ ] **1.1** Write the helper as above. Confirm the PostgREST embed shape against the precedent in
      `workspace-resolver.ts:201` (`.select("workspace_id, workspaces!inner(created_at)")`) and
      `org-memberships-resolver.ts:74` — same `workspaces!inner(...)` embedded-resource form. The
      embed returns an object (or array) the helper normalizes.
- [ ] **1.2** No new RPC, no migration — service-role read of `workspace_members` + the embedded
      `workspaces.github_installation_id` is permitted under the service grant (079 only REVOKEs the
      `authenticated` table grant; `service_role` keeps its default grant per 079:86).

### Phase 2 — New owning-install resolver for a selected repo

**File to edit:** `apps/web-platform/server/reachable-installations.ts` (add a second export)

When a repo is *selected* (setup), resolve the install that actually owns it from the reachable set
— not from login:

```ts
import { checkRepoAccess } from "@/server/github-app";

/**
 * From the user's reachable install set, return the install that has access to
 * `owner/repo` (the first whose GET /repos/{owner}/{repo} returns "ok").
 * Returns null when no reachable install can see the repo — the caller then
 * surfaces "not installed" / "no access" WITHOUT falling back to an arbitrary
 * install. Probes sequentially and short-circuits on the first match.
 */
export async function resolveOwningInstallationForRepo(
  reachableIds: number[],
  owner: string,
  repo: string,
): Promise<number | null> {
  for (const id of reachableIds) {
    const status = await checkRepoAccess(id, owner, repo);
    if (status === "ok") return id;
    // "degraded" (5xx/network/token-gen) is inconclusive — keep probing other
    // installs; only "ok" is an affirmative owning-install signal.
  }
  return null;
}
```

- [ ] **2.1** Add the export. `checkRepoAccess` already returns the small closed set the loop
      branches on. Sequential probing keeps the GitHub call count bounded by the (small) reachable
      set; short-circuit on first `ok`.

### Phase 3 — `detect-installation` route: list across reachable installs

**File to edit:** `apps/web-platform/app/api/repo/detect-installation/route.ts`

Current behavior keeps the early "already stored" return and the login resolution, but the repo
listing must aggregate across the reachable set so an org repo (org login != user login) appears.

- [ ] **3.1** Keep the `userData.github_installation_id` early-return (`:52-65`) AND extend it:
      after listing the stored install's repos, also union the **membership-reachable** installs'
      repos (a stored personal install does not preclude a separate workspace org install).
- [ ] **3.2** Keep the login resolution (`:67-101`) to obtain `githubLogin`.
- [ ] **3.3** Replace the single `findInstallationForLogin` -> store -> `listInstallationRepos` tail
      (`:103-182`) with:
      1. `const reachable = await resolveReachableInstallationIds(serviceClient, user.id, githubLogin)`.
      2. If `reachable.length === 0` -> `{ installed: false, reason: "not_installed" }` (unchanged
         contract; no arbitrary install leakage).
      3. For a login-matched personal install, **keep** the existing `verifyInstallationOwnership`
         + `users.update` + `mirrorRepoColsToSoloWorkspace` store path (still correct for the
         personal case; the 23505 branch already tolerates the shared case). Do NOT attempt to
         store a membership-only install on `users` (unique constraint).
      4. Aggregate: `for (const id of reachable) repos.push(...await listInstallationRepos(id))`,
         de-duped on `fullName`. A per-install failure is logged and skipped (do not fail the whole
         list — the user may have a stale/revoked sibling install).
      5. Return `{ installed: true, repos }`.
- [ ] **3.4** Preserve CSRF (`validateOrigin`/`rejectCsrf` at `:31-32`) and the auth gate.

### Phase 4 — `repos` route: list across reachable installs

**File to edit:** `apps/web-platform/app/api/repo/repos/route.ts`

This route is GET (no body, no CSRF token — read-only, auth-gated). It currently 400s when
`users.github_installation_id` is NULL.

- [ ] **4.1** Resolve `githubLogin` the same way detect does. **Phase 4.1a** extracts
      `resolveGithubLogin(serviceClient, userId, userData)` into a shared module (the detect +
      install routes both inline the `auth.admin.getUserById` + `github_username` fallback — this
      avoids a third copy). The `users` read here must also select `github_username` for the
      email-only fallback (mirror `detect:48`).
- [ ] **4.2** `const reachable = await resolveReachableInstallationIds(serviceClient, user.id, githubLogin)`.
- [ ] **4.3** If `reachable.length === 0` -> keep the 400 "GitHub App not installed" contract (the
      frontend `fetchRepos`/`handleConnectExisting` paths branch on `!res.ok` to then try
      detect/redirect — preserve that). **No arbitrary install fallback.**
- [ ] **4.4** Otherwise aggregate repos across `reachable` (de-dupe on `fullName`), return
      `{ repos }`. Per-install failure logged + skipped.

### Phase 5 — `setup` route: membership fallback for the clone install

**File to edit:** `apps/web-platform/app/api/repo/setup/route.ts`

The repoUrl is already validated and normalized (`:43-53`) to `https://github.com/<owner>/<repo>`.
Parse `owner`/`repo` from the normalized URL for owning-install resolution.

- [ ] **5.1** Keep the `users` read (`:58-62`) but treat NULL `github_installation_id` as a
      *fallback trigger*, not a hard 400. Resolve the install in this priority order:
      1. **Owning install from the reachable set** (most correct): parse `owner/repo` from
         `repoUrl`; `reachable = resolveReachableInstallationIds(serviceClient, user.id, githubLogin)`;
         `installId = await resolveOwningInstallationForRepo(reachable, owner, repo)`. This picks the
         install that actually has the repo (the org install for `jikig-ai/soleur`), regardless of
         whether `users.github_installation_id` is set.
      2. If owning resolution returns null AND `users.github_installation_id` is set, use the stored
         id (preserves the personal happy path even on a transient `checkRepoAccess` degraded probe).
      3. If still unresolved -> keep the 400 "GitHub App not installed" contract.
- [ ] **5.2** Use the resolved `installId` everywhere the route currently uses
      `userData.github_installation_id`: the optimistic-lock mirror (`:101-105`) and the
      `provisionWorkspaceWithRepo(...)` call (`:116-123`). **Do NOT write the resolved install onto
      `users.github_installation_id`** — resolve per-request (unique-constraint safe). The
      `mirrorRepoColsToSoloWorkspace` write targets `workspaces` (the user's solo workspace) and is
      ADR-044-correct; it may carry the resolved install (it already did for the stored case).
- [ ] **5.3** Preserve CSRF (`:23-24`), the optimistic clone-lock (`:71-97`), and the
      Sentry/observability error path (`:225-264`) unchanged.
- [ ] **5.4** **Owner/repo parse safety:** derive `owner`/`repo` from the *normalized* `repoUrl`
      (post-`normalizeRepoUrl`, post-regex) so the parse sees the canonical form. A
      `new URL(repoUrl).pathname.split("/")` against the already-validated form is safe (the regex
      at `:48` guarantees exactly `<owner>/<repo>`).

### Phase 6 — Type-check + suite

- [ ] **6.1** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — zero errors.
- [ ] **6.2** `cd apps/web-platform && ./node_modules/.bin/vitest run` — full suite green (the new
      tests + no regression in `detect-installation-fallback`, `install-route`,
      `setup-route-health-scanner`, `resolve-installation-id`, `repo-url`).

## Test Strategy (RED first)

Pinned runner: `cd apps/web-platform && ./node_modules/.bin/vitest run <path>`. New tests under
`apps/web-platform/test/*.test.ts` (node project — server/route tests, no JSX). Mirror the existing
mock harness in `detect-installation-fallback.test.ts` (table-routing `mockServiceFrom`,
`vi.mock("@/server/github-app", ...)`) and `setup-route-health-scanner.test.ts` (hoisted supabase
chain mocks). All fixtures synthesized — no prod data (`cq-test-fixtures-synthesized-only`).

### New file: `apps/web-platform/test/reachable-installations.test.ts`

- [ ] **T1 (RED -> GREEN): org member, login != org login, install on workspace.** Mock
      `findInstallationForLogin("deruelle") -> null` (no personal install). Mock the service-client
      `workspace_members` embed to return one workspace carrying install `122213433`. Assert
      `resolveReachableInstallationIds(service, "754ee124", "deruelle")` -> `[122213433]`.
- [ ] **T2 (RED -> GREEN): owning-install resolution for the selected repo.** Mock
      `checkRepoAccess(122213433, "jikig-ai", "soleur") -> "ok"`. Assert
      `resolveOwningInstallationForRepo([122213433], "jikig-ai", "soleur")` -> `122213433`.
- [ ] **T3 (regression): no matching install AND no membership install -> empty set / null.**
      `findInstallationForLogin -> null`, `workspace_members` embed -> `[]`. Assert
      `resolveReachableInstallationIds` -> `[]` and `resolveOwningInstallationForRepo([], ...)` ->
      `null` (no arbitrary install leakage).
- [ ] **T4 (security): membership read is user-scoped.** Assert the helper calls
      `.eq("user_id", <userId>)` on the `workspace_members` chain (spy on the chain) — proves the
      enumeration cannot return a sibling-user's install.
- [ ] **T5 (union + dedupe): personal install + workspace install, overlapping.**
      `findInstallationForLogin -> 999`; workspace carries `999` and `122213433`. Assert the set is
      `[999, 122213433]` (deduped, both present).
- [ ] **T6 (resilience): `checkRepoAccess` returns "degraded" for one install, "ok" for next.**
      Assert `resolveOwningInstallationForRepo` keeps probing past `degraded` and returns the `ok`
      install.

### New file: `apps/web-platform/test/repos-route-reachable.test.ts`

- [ ] **T7 (RED -> GREEN): GET /api/repo/repos lists the org repo for the org member.**
      `users.github_installation_id = null`, `github_username = "deruelle"`,
      `findInstallationForLogin -> null`, workspace carries `122213433`,
      `listInstallationRepos(122213433) -> [{ fullName: "jikig-ai/soleur", ... }]`. Assert response
      `{ repos: [{ fullName: "jikig-ai/soleur" }] }` (was: 400 "not installed").
- [ ] **T8 (regression): no reachable install -> 400 "GitHub App not installed".** All sources empty.
      Assert status 400 + the unchanged error string (frontend depends on it).

### New file: `apps/web-platform/test/setup-route-install-resolution.test.ts`

- [ ] **T9 (RED -> GREEN — the headline case): org member clones org repo via membership install.**
      `users.github_installation_id = null`; `repoUrl = https://github.com/jikig-ai/soleur`;
      reachable set `[122213433]`; `checkRepoAccess(122213433,"jikig-ai","soleur") -> "ok"`. Assert
      `provisionWorkspaceWithRepo` is called with install `122213433` (spy the mock's args) and the
      route returns `{ status: "cloning" }` (was: 400 "GitHub App not installed").
- [ ] **T10 (no write to users): assert no `users.update({github_installation_id})` occurs in the
      membership-fallback path** (spy the `users` update chain) — per-request resolution only,
      unique-constraint-safe.
- [ ] **T11 (regression: personal happy path unchanged).** `users.github_installation_id = 999`;
      `checkRepoAccess(999, owner, repo) -> "ok"`; assert clone uses `999`.
- [ ] **T12 (regression: no reachable install -> 400).** NULL stored id, empty reachable set, owning
      resolution null. Assert 400 "GitHub App not installed".
- [ ] **T13 (degraded-probe fallback to stored id).** `users.github_installation_id = 999`;
      `resolveOwningInstallationForRepo -> null` because `checkRepoAccess` returned "degraded" for
      999; assert the route falls back to the stored `999` (Phase 5.1 priority 2) and clones.

### Detect-installation augmentation (extend existing suite)

- [ ] **T14 (extend `detect-installation-fallback.test.ts`): org member sees the org repo.** Add a
      case: `findInstallationForLogin -> null`, workspace carries `122213433`,
      `listInstallationRepos(122213433) -> [jikig-ai/soleur]`. Assert
      `{ installed: true, repos: [{ fullName: "jikig-ai/soleur" }] }`.
- [ ] **T15 (extend): existing personal-install detect cases stay green** (no regression to the
      login-match + store + mirror path).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** `resolveReachableInstallationIds(service, "754ee124", "deruelle")` returns
      `[122213433]` when the login source is empty and the user's workspace carries `122213433` (T1).
- [ ] **AC2** `resolveOwningInstallationForRepo([122213433], "jikig-ai", "soleur")` returns
      `122213433` (T2); returns `null` for an empty reachable set (T3).
- [ ] **AC3** `GET /api/repo/repos` for the org member (NULL `users.github_installation_id`,
      membership install present) returns `200 { repos: [..., {fullName:"jikig-ai/soleur"}, ...] }`
      (T7).
- [ ] **AC4** `POST /api/repo/setup` with `repoUrl=https://github.com/jikig-ai/soleur` and NULL
      `users.github_installation_id` calls `provisionWorkspaceWithRepo` with install `122213433` and
      returns `{ status: "cloning" }` (T9).
- [ ] **AC5** The membership-fallback setup path performs **no** `users.update` of
      `github_installation_id` (T10) — verified by spying the `users` update chain.
- [ ] **AC6 (security):** the membership enumeration query is scoped by `.eq("user_id", <userId>)`
      (T4); a user with no login-match and no membership install gets 400 / empty set, never an
      arbitrary install (T3, T8, T12).
- [ ] **AC7 (regression):** personal-install happy path unchanged in detect (T15), repos (implicit
      via reachable union), and setup (T11); the degraded-probe path falls back to the stored id
      (T13).
- [ ] **AC8** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0.
- [ ] **AC9** `cd apps/web-platform && ./node_modules/.bin/vitest run` exits 0 (full suite),
      including the unchanged `detect-installation-fallback`, `install-route`,
      `setup-route-health-scanner`, `resolve-installation-id` suites.
- [ ] **AC10** No new Supabase migration file is added (`git status apps/web-platform/supabase/migrations/`
      shows no new file); the fix reuses `resolve_workspace_installation_id` and the service-role read.
- [ ] **AC11** PR body uses `Ref #<issue>` (not `Closes`) if the un-freeze depends on the post-merge
      re-run of the connect flow; the code fix itself is complete at merge.

### Post-merge (user dogfood)

- [ ] **AC12** After deploy, the connect-repo flow is re-run for `jikig-ai/soleur`; the clone
      succeeds via install `122213433` and the KB un-freezes.
      **Automation: not feasible because** the connect flow is an authenticated, OAuth-gated browser
      UX (the documented interactive-OAuth exception). The *result* (workspace `repo_status = ready`)
      is API-readable via the Supabase MCP read — that verification IS automatable and SHOULD be run
      post-merge.

## Files to Edit

- `apps/web-platform/app/api/repo/detect-installation/route.ts` — aggregate repos across reachable
  installs; keep login store path; keep CSRF.
- `apps/web-platform/app/api/repo/repos/route.ts` — resolve login, aggregate across reachable
  installs, keep 400 contract when empty.
- `apps/web-platform/app/api/repo/setup/route.ts` — membership/owning-install fallback for the clone;
  no `users` write of the shared install; keep CSRF + lock + error path.
- `apps/web-platform/app/api/repo/install/route.ts` — (Phase 4.1a only) swap the inline
  `auth.admin.getUserById` login lookup for the shared `resolveGithubLogin` helper, no behavior
  change. (Touch only if the extraction lands here; otherwise leave untouched.)

## Files to Create

- `apps/web-platform/server/reachable-installations.ts` — `resolveReachableInstallationIds` +
  `resolveOwningInstallationForRepo`.
- `apps/web-platform/server/github-login.ts` (Phase 4.1a) — shared
  `resolveGithubLogin(serviceClient, userId, userData)` extracted from the detect/install copies.
- `apps/web-platform/test/reachable-installations.test.ts` (T1-T6).
- `apps/web-platform/test/repos-route-reachable.test.ts` (T7-T8).
- `apps/web-platform/test/setup-route-install-resolution.test.ts` (T9-T13).

## Open Code-Review Overlap

(Filled by Phase 1.7.5 after `gh issue list --label code-review --state open`.) The plan touches
`detect-installation/route.ts`, `repos/route.ts`, `setup/route.ts`, `install/route.ts`,
`server/reachable-installations.ts` (new), `server/github-login.ts` (new). If any open `code-review`
scope-out names these files, **fold in / acknowledge / defer** per the gate; if none, record `None`.
The `resolveGithubLogin` extraction (Phase 4.1a) is a deliberate de-duplication fold, not a separate
concern.

## Risks & Mitigations

- **Cross-tenant install leakage (the brand-survival risk).** *Mitigation:* the only two install
  sources are GitHub-authoritative login-match and a `.eq("user_id", userId)`-scoped
  `workspace_members` read; `resolveOwningInstallationForRepo` returns `null` (not an arbitrary id)
  when no reachable install owns the repo. Tested by T3, T4, T8, T12.
- **Service-role read of a credential column.** *Mitigation:* the membership enumeration reads
  `workspaces.github_installation_id` via the **service client**, the same trust boundary the routes
  already use for the `users` read; the column stays off the `authenticated` grant (079:88) and
  tenant-client paths still use the RPC. No new exposure surface.
- **GitHub call fan-out** (one `checkRepoAccess`/`listInstallationRepos` per reachable install).
  *Mitigation:* the reachable set is small (a user belongs to few workspaces); `checkRepoAccess`
  short-circuits on first `ok`; `listInstallationRepos` failures are per-install skipped, not fatal.
  All GitHub fetches already carry a 15s `AbortSignal.timeout` (`github-app.ts:208`).
- **`users.github_installation_id` UNIQUE constraint.** *Mitigation:* the membership path never
  writes the shared install to `users` (per-request resolution); the existing 23505 branch in detect
  already tolerates the personal-store collision. Tested by T10.
- **Frontend contract drift.** The `400 "GitHub App not installed"` string and the
  `{ installed, repos, reason }` / `{ repos }` / `{ status: "cloning" }` shapes are unchanged; the
  connect-repo page branches on `!res.ok` and `data.installed`/`data.repos`/`data.reason` — all
  preserved. No `page.tsx` change required (verified against `connect-repo/page.tsx`).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text,
  or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is filled (threshold:
  single-user incident, `requires_cpo_signoff: true`).
- **PostgREST embed cardinality.** `workspaces!inner(github_installation_id)` may return the embed as
  an object or a single-element array depending on the client/version; the helper normalizes both
  (`Array.isArray(ws) ? ws : [ws]`). Confirm against the `workspace-resolver.ts:201` precedent at
  /work time.
- **Owner/repo parse must use the normalized URL.** Parse `owner/repo` AFTER `normalizeRepoUrl` + the
  format regex in `setup`, so the parser sees the canonical `<owner>/<repo>` the regex guarantees —
  do not re-parse the raw `body.repoUrl`.
- **Do not store a membership-only install on `users`.** The unique index forbids it and ADR-044
  designs the shared case to resolve per-request; only the login-matched personal install takes the
  existing `users.update` + mirror path.
- **Service-role membership read, not tenant RPC, for the SET.** `resolveInstallationId` (tenant RPC)
  resolves ONE workspace; the listing aggregation needs the SET across the user's workspaces, which
  has no RPC — use the user-scoped service-role read. Keep tenant-client credential reads on the RPC.

## Observability

```yaml
liveness_signal:
  what: "POST /api/repo/setup returning { status: 'cloning' } then repo_status transitioning to 'ready'"
  cadence: "per connect-flow invocation (user-initiated; not a periodic job)"
  alert_target: "Sentry (existing reportSilentFallback in setup clone .catch + reachable-installations helper)"
  configured_in: "apps/web-platform/server/observability.ts (reportSilentFallback) — already wired in setup/route.ts:228"
error_reporting:
  destination: "Sentry via reportSilentFallback (feature: 'reachable-installations' | 'repo-setup')"
  fail_loud: "membership-enumeration and login-install failures are Sentry-mirrored; per-install listInstallationRepos failures are logged + skipped (degraded-not-fatal by design)"
failure_modes:
  - mode: "membership enumeration query error"
    detection: "reportSilentFallback feature='reachable-installations' op='membership-installs'"
    alert_route: "Sentry"
  - mode: "no reachable install for an org member (data-repair regression)"
    detection: "400 'GitHub App not installed' on a user who SHOULD have a workspace install — connect-flow dead-end; Sentry breadcrumb on the empty reachable set"
    alert_route: "Sentry"
  - mode: "owning-install resolution returns null while a stored id exists"
    detection: "Phase 5.1 priority-2 fallback log line; clone proceeds on stored id"
    alert_route: "logger.info"
  - mode: "clone failure after install resolved"
    detection: "existing setup .catch -> reportSilentFallback feature='repo-setup' op='clone'"
    alert_route: "Sentry (unchanged)"
logs:
  where: "pino structured logs (server/logger) + Sentry"
  retention: "per existing platform log retention (unchanged)"
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/reachable-installations.test.ts test/repos-route-reachable.test.ts test/setup-route-install-resolution.test.ts"
  expected_output: "all suites pass — RED tests (T1,T2,T7,T9) green after implementation; regression tests (T3,T8,T11,T12) green"
```

## Domain Review

(To be completed by Phase 2.5 — domain sweep + Product/UX gate. No new user-facing page or component
is created; the connect-repo page contract is unchanged, so the Product/UX tier is expected
NONE/ADVISORY. Security/Engineering are the relevant lenses given the cross-tenant install-resolution
surface and the `single-user incident` threshold.)

## Infrastructure (IaC)

None — pure code change against an already-provisioned surface. No server, secret, vendor account,
DNS record, TLS cert, firewall rule, systemd unit, cron, or runtime process is introduced. Phase 2.8
reviewed (ack at top of file). The single post-merge step (AC12) is an interactive, OAuth-gated
authenticated browser flow (the documented interactive-OAuth exception), not infrastructure
provisioning.

## Out of Scope

- Team-invite repo-setup flows that resolve a *non-solo* target workspace (deferred to #4560 /
  Phase 5 per `workspace-repo-mirror.ts`). This fix keeps the solo-workspace mirror; the reachable
  set already spans all the user's workspaces for *listing*, but the clone still provisions the solo
  workspace (`user.id`), matching current `setup` behavior.
- Any prod-data repair (the workspace `754ee124` install was already set manually — not in this PR).
- No new migration (`resolve_workspace_installation_id` already exists).
