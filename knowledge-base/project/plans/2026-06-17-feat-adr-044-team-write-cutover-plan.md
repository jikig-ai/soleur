---
title: "ADR-044 team write-cutover — relocate connect-time repo writes users.* → workspaces.* + team on-disk provisioning"
issue: 5462
branch: feat-one-shot-5462-team-write-cutover
worktree: .worktrees/feat-one-shot-5462-team-write-cutover
adr: ADR-044
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
spec: knowledge-base/project/specs/feat-adr-044-pr2-write-relocation/spec.md
blocks: 5437
type: enhancement
---

# ADR-044 Team Write-Cutover (#5462)

## Enhancement Summary

**Deepened:** 2026-06-17 · **Agents:** repo-research-analyst, learnings-researcher,
spec-flow-analyzer (7 P0 / 6 P1 / 4 P2), data-integrity-guardian (credential boundary).
Precedent-diff (4.4), verify-the-negative, and all four mandatory halt gates (4.6
User-Brand Impact, 4.7 Observability, 4.8 PAT-shaped, 4.9 UI-wireframe) PASS.

**Load-bearing corrections (deepen):**
1. **Co-membered SKIP backlog is a CLO/GDPR blocker for auto-backfill (data P0).** PA-17(c)(2)
   + the counsel review (`2026-05-counsel-review-4558.md`) require a fresh Art. 6(1)(a)
   attestation per co-member — auto-adopting the owner's repo onto a co-membered workspace
   is unlawful. The literal "drift COUNT → 0" exit is reshaped: solo rows → 0; co-membered
   rows are a **lawful carried residual** cleared only by owner re-connect (this PR's write
   path). Surfaced to CPO/CLO.
2. **Background-callback 0-row write is a silent no-op (data P0).** `.eq("id",capturedId)`
   matching 0 rows returns `{error:null}`; the workspace can be deleted mid-clone
   (`current_workspace_id` ON DELETE SET NULL). Callback must `.select("id")` + Sentry-mirror.
3. **23505 unique-violation branch goes DEAD on relocation (data P1).** The UNIQUE is on
   `users` only (mig 052); `workspaces` is non-unique (ADR-044 fan-out). Delete the branch;
   re-justify cross-tenant attribution via the webhook fan-out reconcile.
4. **`repo_error` needs a real column add + mirror extension (data P1)** — not just a GRANT
   line (the column doesn't exist on `workspaces` yet; GRANT alone errors). Confirmed
   non-credential (sanitized).
5. **Resolve-once-thread-everywhere rule (spec-flow P0):** one membership-verified
   `resolveActiveWorkspace` id threads into owner-gate `p_workspace_id`, all writes, the
   optimistic lock, provisioning, the callback closure, the cloning-guard read, and
   `repo_error` — with the `resetFromClaim` self-heal and `{ok:false}` fail-closed branches.
6. **`users.*` rollback-net removal is directional (issue supersedes spec scaffold)** —
   exit criterion is *zero* `users.*` writes; rollback is whole-PR revert (read path is
   workspaces-only; columns not dropped here).

### New considerations discovered
- disconnect tears down a SHARED team dir → must abort live member sessions before `rm`.
- The deliberate column split (repo cols → activeId; provisioning/readiness cols → owner's
  `users` row) must be explicit so reviewers don't flag the retained `user.id` writes.

## Overview

ADR-044 relocates GitHub repo-connection state from `users.*` to `workspaces.*`.
The **read** path is already cut over (`current-repo-url.ts`, `workspace-resolver.ts`
read `workspaces.repo_url` / the `resolve_workspace_installation_id` SECURITY DEFINER
RPC). The **write** path is still `users`-authoritative: the four connect routes write
`users.{repo_url, workspace_path, github_installation_id, repo_error}` and best-effort
*mirror* a subset to `workspaces` via `mirrorRepoColsToSoloWorkspace`, always keyed on
`user.id` (the solo workspace). PR-2a (#5455, shipped) added a **422 refusal** when a
team workspace is active, because the legacy path would silently provision/disconnect
the caller's *personal* solo workspace.

This PR **inverts the dual-write**: `workspaces` becomes authoritative (keyed on the
**resolved active workspace id** — team or solo), the `users.*` connect-time writes are
removed, the PR-2a 422 refusal is **replaced by real team on-disk provisioning**, and
`repo_error` is re-keyed to `workspaces`. This is the precondition that unblocks PR-2b
(#5437, the destructive `users` column drop). After this PR, a `git grep` of
`repo_url|workspace_path|github_installation_id` write sites under `app/api/repo/**`
targeting `users.*` returns **0** (the `hr-write-boundary-sentinel-sweep-all-write-sites`
gate).

**Scope (4 work items, single atomic PR):**
1. **Team on-disk provisioning** in `repo/setup` + `repo/disconnect` — resolve the
   target workspace id server-side (claim/session-derived, IDOR-safe, never `req.body`)
   via the **membership-verified** `resolveActiveWorkspace`, provision/tear down
   `/workspaces/<active_id>`, and replace the 422 refusal.
2. **Write relocation** — `repo_url` / `workspace_path` / `github_installation_id`
   writes move from `users` → the active `workspaces` row across `setup`, `install`,
   `detect-installation`, `disconnect`. `mirrorRepoColsToSoloWorkspace` is
   inverted/removed (workspaces becomes the authoritative write target).
3. **Re-key `repo_error`** to `workspaces` (new migration 110 adds the column; the
   write moves; `getCurrentRepoStatus` reads it from `workspaces`).
4. **Re-backfill + reconcile the mig-080 co-membered SKIP backlog** so PR-2b's
   drift-gate `COUNT` can reach 0.

> **Why no `users.*` rollback net (directional decision — confirm).** The spec
> scaffold (authored for PR-2a) said "the existing `users.*` writes stay as the
> rollback net." The **issue #5462 supersedes** this: its exit criterion is *zero*
> `users.*` write sites, which is the literal precondition for PR-2b's column drop.
> Keeping the `users.*` write would re-introduce the dual-source-of-truth divergence
> ADR-044 forbids and would make the PR-2b drift gate unreachable. So this PR removes
> the `users.*` connect-time writes. The rollback net during *this* PR's soak is
> git-revert of the whole PR (read path already reads `workspaces`; mig 110 is additive
> + `.down.sql`-reversible; the `users` columns are NOT dropped here, so a revert
> restores the `users`-authoritative writes without data loss). **This is the merge of
> two source-of-truth directions (users→workspaces); the direction is workspaces-wins,
> confirmed by the issue body and ADR-044 Decision.**

## Premise Validation

- **Issue #5462 is OPEN** (`gh issue view 5462` → state OPEN). It is the tracking item
  for the team write-cutover; the spec body confirms #4560 is journey-state UI polish,
  NOT this work (corrected mis-attribution).
- **Blocker check:** #5437 (PR-2b column drop) is OPEN and blocked-by this; not stale.
- **Cited write sites verified on the branch** (line numbers match issue body within ±2):
  `setup/route.ts:182,213-214,257,331`, `install/route.ts:120`,
  `detect-installation/route.ts:141`, `disconnect/route.ts:121-130`.
- **Mechanism vs ADR corpus:** ADR-044 `## Decision` Option A *is* this relocation
  ("TS read-cutover 081-equivalent; later decommission of the `users` columns after a
  prod soak"). The write-cutover is the gap PR-1 + PR-2a left open — NOT a rejected
  alternative. ADR-044 is `status: adopting`; its C4 edge is "read=Workspace /
  write=User (dual)" and explicitly waits for "PR-2 [to] relocate them to `workspaces.*`."
- **Self-capability check:** `repo_error` is NOT on `workspaces` — mig 079 added exactly
  5 columns (`repo_url, repo_provider, github_installation_id, repo_status,
  repo_last_synced_at`), no `repo_error` (verified via grep of `079_*.sql`). So re-keying
  `repo_error` *requires a new migration* (110); it is not a pure app-layer move.
- **Next migration number = 110** (`ls migrations/` tail = 107/108/109).
- **No external premises beyond the above; all held.**

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Reality (verified file:line) | Plan response |
|---|---|---|
| Spec scaffold: "existing `users.*` writes stay as the rollback net" | Issue #5462 exit criterion: **zero** `users.*` write sites under `app/api/repo/**`. Keeping them blocks PR-2b's drift gate. | **Remove** the `users.*` connect-time writes; rollback net is whole-PR git-revert (read path is workspaces-only; mig 110 is reversible; `users` cols not dropped). Directional decision flagged above. |
| Issue: "invert/remove `mirrorRepoColsToSoloWorkspace`" | `mirrorRepoColsToSoloWorkspace` (`workspace-repo-mirror.ts:52`) writes a SUBSET to `workspaces.id=userId`; `users` is authoritative. | Replace with a `writeRepoColsToWorkspace(service, workspaceId, patch)` that writes the authoritative `workspaces` row keyed on the **resolved active id**; delete the mirror + its solo-only assumptions. |
| Issue: "resolve target `workspace_id` server-side (IDOR-safe, never `req.body`)" | Routes already resolve via `resolveCurrentWorkspaceId(user.id, supabase)` (claim-derived). But the **membership-verified** `resolveActiveWorkspace` (`workspace-resolver.ts:365`) is stronger: `{ok:true, workspaceId}` only for a membership-verified team id or own solo id; `{ok:false,"db-error"}` otherwise. | Use `resolveActiveWorkspace` (NOT the simple `resolveCurrentWorkspaceId`) at the write boundary — its `{ok:false}` must fail-closed (do NOT provision into an unverified team). See SE on identity-pinned writes. |
| Issue: "preserve owner-gate invariant (`p_workspace_id` == the id the handler mutates)" | Both routes call `is_workspace_owner({p_workspace_id: user.id, ...})` — but they will now mutate `workspaces.<active_id>` and provision `/workspaces/<active_id>`. | Change `p_workspace_id` to the **resolved active id**, atomically with the write-target change. A window where the gate checks `user.id` but the handler mutates `<active_id>` is a confused-deputy hole. |
| Issue: "re-key `repo_error` to `workspaces`" | `repo_error` is on `users` only (mig 079 has no such column); `getCurrentRepoStatus` reads `users.repo_error` (`current-repo-url.ts:140-144`). | New migration 110: `ADD COLUMN repo_error text` on `workspaces` (in the non-credential GRANT set); move the write (`setup` error branch, `disconnect` clear) to `workspaces`; read from `workspaces`. Fixes the documented dispatching-user-vs-active-workspace key mismatch (`current-repo-url.ts:97-104`). |
| Issue: "re-backfill the mig-080 co-membered SKIP backlog so the drift-gate COUNT can reach 0" | mig-080 SKIPped solo workspaces with `>1` member. **Deepen-confirmed CLO blocker:** PA-17(c)(2) + counsel review require a fresh Art. 6(1)(a) attestation per co-member — auto-adopting the owner's repo onto a co-membered workspace is **unlawful**. PR-2b drift gate counts `users.* DISTINCT FROM workspaces.*`. | mig 110 re-keys the **solo** backfill → 0 solo drift. Co-membered rows are **NOT auto-adopted** — they are a lawful carried residual cleared only by owner re-connect (this PR's owner-gated write path). The drift exit is reshaped: solo COUNT=0 + "0 co-membered rows adopted WITHOUT an attestation." Surfaced to CPO/CLO. See Phase 1 items 4-5 + the SE. |

## User-Brand Impact

**If this lands broken, the user experiences:** a team owner connects a repository to
their team workspace and it silently lands on their personal solo workspace (or vice
versa) — the team's agents run against the wrong (empty) clone, or a disconnect leaves a
live GitHub App credential readable on the team's read path. A non-owner member could
connect/disconnect a workspace they don't own (confused deputy).

**If this leaks, the user's data/workflow/money is exposed via:** `github_installation_id`
is a GitHub App **token grant**; relocating it across the user→workspace tenant boundary
with a mis-resolved id (or a write that races the owner-gate) could bind one tenant's
credential into another workspace's read path. The IDOR-safe claim-derived +
membership-verified resolution and the `p_workspace_id == mutation-target` owner-gate
invariant make that structurally impossible.

**Brand-survival threshold:** single-user incident. CPO sign-off required at plan time
before `/work`; `user-impact-reviewer` runs at PR review (handled by `review/SKILL.md`
conditional-agent block). Inherited from ADR-044 (`brand_survival_threshold: single-user
incident`).

## Architecture Decision (ADR/C4)

This PR changes the **write side** of the ADR-044 ownership boundary (connect-time writes
move User → Workspace). That is an architectural-decision *completion*, so the ADR + C4
update are deliverables of THIS plan, not a follow-up.

### ADR
Amend **ADR-044** (`knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md`)
via `/soleur:architecture`:
- Add a PR-2 (write-cutover) entry to the lifecycle note documenting that connect-time
  writes now target `workspaces.*`, `repo_error` relocated, the co-membered backlog
  reconciled.
- **Status stays `adopting`** (NOT `accepted`): per ADR-044 line 148, the
  `adopting → accepted` flip lands with PR-2b's column drop after a prod soak. This PR
  moves the write edge but does not drop the legacy columns, so the invariant is not yet
  fully held.

### C4 views
- ADR-044 prose C4 edge: connection edge moves **read=Workspace / write=User (dual)** →
  **read=Workspace / write=Workspace** (the `users` columns survive only as un-written
  legacy until PR-2b). Update the edge description in ADR-044's `## Consequences` C4 note.
- Check `knowledge-base/engineering/architecture/diagrams/model.c4` at /work time for an
  explicit User→repo / Workspace→repo relationship; if present, the C4 edit is gated
  behind the `c4-edit` Concierge-only KB-write flag (commit `3c8849655`) — route through
  the Concierge path, but the update lands in THIS feature's lifecycle.

### Sequencing
The ADR/C4 edit describes the post-merge target state and lands in this PR's commits.
No deferral.

## Implementation Phases

> **TDD throughout** (`cq-write-failing-tests-before`): each phase writes failing tests
> first, then the implementation. Phase order is **load-bearing**: the migration (Phase 1)
> ships the `workspaces.repo_error` column + reconcile BEFORE the write-relocation code
> (Phase 2-3) that targets it. Atomic merge ≠ atomic per-phase — the release pipeline runs
> `run-migrations.sh` before code cutover (per the mig-109 prerequisite pattern).

### Phase 1 — Migration 110: `workspaces.repo_error` + co-membered re-backfill/reconcile [data]

`apps/web-platform/supabase/migrations/110_workspace_repo_error_and_comember_reconcile.sql`
(+ `.down.sql`, + `verify/110_*.sql`):

1. `ALTER TABLE public.workspaces ADD COLUMN IF NOT EXISTS repo_error text;` — read the
   2-3 most recent migrations first (`108`, `109`) to confirm the transaction-wrapping +
   no-`CONCURRENTLY` convention (Supabase wraps each file in a txn; SQLSTATE 25001).
2. Extend the **non-credential GRANT** on `workspaces` to include `repo_error`. Re-issue
   the FULL GRANT after the existing REVOKE (mirror mig 079:89's shape — do NOT issue a
   partial column GRANT): `GRANT SELECT (id, organization_id, name, created_at, repo_url,
   repo_provider, repo_status, repo_last_synced_at, repo_error) ON public.workspaces TO
   authenticated`. **`repo_error` is non-credential (deepen-confirmed):** it is built at
   `setup/route.ts:324-328` as `JSON.stringify({code, message: sanitizeGitStderr(...), ...})`;
   `sanitizeGitStderr` (`git-auth.ts:211-213`) strips absolute paths, and the GitHub App
   token never reaches stderr (askpass via env, never argv; `GIT_TERMINAL_PROMPT=0`). So it
   belongs in the `authenticated` read set — `getCurrentRepoStatus` reads it via the tenant
   client, preserving the cc-dispatcher OFF-service-role posture (`current-repo-url.ts:88`).
   **The GRANT alone is insufficient — the column MUST be added first (step 1)** or
   `GRANT SELECT (repo_error)` errors on a missing column (deepen item 1).
3. Backfill `workspaces.repo_error` from `users.repo_error` for the solo canary rows
   (mirror mig-080's `w.id = u.id` + sole-member guard + idempotency `WHERE
   w.repo_error IS NULL`).
4. **Co-membered SKIP backlog — re-key the solo backfill, DO NOT auto-adopt co-membered
   rows (CLO blocker, deepen-confirmed).** Re-run the mig-080 solo backfill for any solo
   rows that became correctly-provisioned. **The co-membered SKIP backlog MUST NOT be
   auto-drained.** The deepen data-integrity pass confirmed against the legal corpus:
   - mig-080 SKIPs co-membered workspaces (`080:48-83`) citing the CLO requirement
     (`080:7-10`).
   - `knowledge-base/legal/audits/2026-05-counsel-review-4558.md` (call B1) + the Art. 30
     register **PA-17 sub-clause (c)(2)** establish that co-member repo access is lawful
     ONLY via a **fresh Art. 6(1)(a) invite attestation** (`workspace_member_attestations`,
     mig 058) — "the Art. 6(1)(a) basis **never operates retroactively** on a connection
     established before the Owner's consent of record." A blind re-backfill that copies the
     owner's `users.repo_url` onto a co-membered workspace processes co-member access
     WITHOUT that attestation → a direct GDPR violation of the lawful-basis split the CLO
     signed. `hr-gdpr-gate-on-regulated-data-surfaces` blocks it.
   - **Correct closure (not auto-drain):** the SKIP backlog clears **only when the owner
     re-connects the repo from within the team-workspace context** — which is exactly the
     owner-gated write path THIS PR implements (Phase 3). A re-connect re-establishes the
     connection under a fresh attestation, so it is lawful. The backlog is therefore
     **carried, not auto-drained**.
5. **Drift-gate semantics (reshaped — deepen-confirmed).** The PR-2b drift gate (ADR-044
   Consequences) counts `users.* DISTINCT FROM workspaces.*`. Because the co-membered rows
   CANNOT be auto-adopted (item 4), this PR CANNOT drive the raw `COUNT` to 0 for
   co-membered workspaces by backfill. Two-part exit:
   - **Solo rows:** the re-keyed solo backfill brings them to 0 divergence.
   - **Co-membered rows:** the gate must assert "**0 co-membered rows adopted WITHOUT a
     corresponding attestation**," NOT "0 SKIP rows remaining." Carry the un-re-connected
     co-membered rows as a **known residual** (documented in the migration header + the
     PR-2b precondition note). PR-2b's column drop must tolerate this residual (the `users`
     value for an un-re-connected co-membered owner is the LAST owner-connected value;
     dropping it after the owner re-connects via the team path is safe). **This is a
     directional refinement of the issue's "drift COUNT can reach 0" — surface to CPO/CLO:
     the literal COUNT-to-0 is unlawful for co-membered rows; the lawful exit is
     attestation-gated re-connect.** Re-key the solo backfill on `(github_installation_id,
     normalizeRepoUrl(repo_url))` per ADR-044's fan-out; never adopt across an
     `organization` boundary. Run from the still-authoritative `users` snapshot BEFORE the
     write cutover deploys (Phase 1 before Phase 2-3 per the ordering).
6. **Drift-gate convergence check** (verify/110): run ADR-044's exact PR-2b gate query
   (`SELECT COUNT(*) FROM users u JOIN workspaces w ON w.id=u.id WHERE (u.repo_url IS NOT
   NULL AND w.repo_url IS DISTINCT FROM u.repo_url) OR (u.github_installation_id IS NOT
   NULL AND w.github_installation_id IS DISTINCT FROM u.github_installation_id)`) **scoped
   to SOLO rows** (sole-member workspaces) and assert it returns 0 post-reconcile. The
   co-membered residual is asserted separately as "0 co-membered rows adopted WITHOUT an
   attestation" (item 5). **These counts are preconditions to verify at /work time against
   live dev (Doppler `DATABASE_URL_POOLER`), NOT plan-time facts** — see SE.
7. Verify in a **rolled-back dev transaction** (`BEGIN; <body>; <drift count>;
   <re-run for idempotency>; ROLLBACK`) — zero `_schema_migrations` drift, leaving the
   real apply to the pipeline.

**Precedent (deepen 4.4 — grepped):** the column-add + GRANT-extension shape is canonical:
- `ALTER TABLE public.workspaces ADD COLUMN IF NOT EXISTS …` — mig 079:50-55, 098:35.
- `GRANT SELECT (id, organization_id, name, created_at, repo_url, repo_provider,
  repo_status, repo_last_synced_at) ON public.workspaces TO authenticated` — mig 079:89.
  Add `repo_error` to this exact list (re-issue the full GRANT after the `REVOKE`, mirroring
  079's shape — do NOT issue a partial column GRANT).
- The idempotent backfill `DO $$ … GET DIAGNOSTICS v_rc = ROW_COUNT; RAISE NOTICE … $$`
  shape is mig 080:27-56. Reuse verbatim.

**Tests:** follow the repo's migration-test convention at
`apps/web-platform/test/supabase-migrations/NNN-<topic>.test.ts` (siblings:
`108-repo-clone-self-heal-rpc.test.ts`, `098-workspace-logos.test.ts`). Add
`110-workspace-repo-error-and-comember-reconcile.test.ts` asserting: column exists + in
the `authenticated` GRANT set; solo backfill idempotent; co-membered reconcile lands only
owner-owned rows (or defers per the legal decision); drift count → 0. Also add a
`verify/110_*.sql` following the `check_name`/`bad` contract (each row returns `check_name`
+ `bad`; any `bad > 0` fails CI `verify-migrations` and auto-closes the matching
`follow-through` issue) — siblings: `verify/109_*.sql`. The drift-gate check is a
`SELECT 'repo_drift_count' AS check_name, (<ADR-044 drift query>) AS bad`.

### Phase 2 — Write helper inversion: `workspaces` authoritative [TR: write-boundary]

`apps/web-platform/server/workspace-repo-mirror.ts` → rename/replace with
`writeRepoColsToWorkspace(service, workspaceId, patch, opts?)`:

1. Write the authoritative `workspaces` row keyed on the **caller-supplied resolved
   workspace id** (NOT hardcoded `userId`). Extend `MirroredRepoCols` to include
   `repo_error?: string | null` (now a `workspaces` column).
2. Keep the **fail-closed on credential-clear** asymmetry (`throwOnError` on disconnect)
   — but it is now load-bearing for the AUTHORITATIVE write, not a mirror: a failed
   `workspaces` write on connect means the connection didn't persist (surface the error
   to the caller, do NOT fall through to a `users` write — there is none).
3. Preserve the exact `reportSilentFallback` `message:` string
   (`cq-silent-fallback-must-mirror-to-sentry` + the helper-migration message-preservation
   SE) and `op` slug so operator dashboards keyed on it don't go dark.
4. Update `test/workspace-repo-mirror.test.ts` → assert writes target the supplied id
   (team id case + solo id case), `repo_error` round-trips, fail-closed throws.

### Phase 3 — Relocate the four route write sites + team provisioning [FR1, FR2, IDOR]

**The single load-bearing rule (resolve once, thread everywhere — P0-1/P0-2/P0-3):**
resolve the target workspace id ONCE per request via `resolveActiveWorkspace(user.id,
supabase)` (membership-verified), then thread that SAME id into ALL of: (a) the owner-gate
`p_workspace_id`, (b) every `workspaces.*` write, (c) the optimistic clone-lock predicate,
(d) `provisionWorkspaceWithRepo` / `deleteWorkspace`, (e) the setup background-callback
closure, (f) the cloning-guard read, (g) the `repo_error` write. Add a test asserting
gate-id === mutation-id === provision-id. The `resolveActiveWorkspace` outcomes:
- `{ok:true, workspaceId}` (membership-verified team id OR own solo id) → proceed against it.
- `{ok:true, workspaceId:userId, resetFromClaim:<staleTeam>}` (**P0-3 self-heal branch**):
  the caller is a removed/non-member of the claimed team. The handler MUST connect/disconnect
  the caller's **own solo workspace** (the reset `userId`), and the owner-gate + writes +
  provisioning ALL use that reset id — never the stale claim. A removed member disconnecting
  thus tears down their OWN repo, not the team's. (Emit the existing divergence breadcrumb.)
- `{ok:false, reason:"db-error"}` → **fail-closed 503** (retryable). Do NOT fall back to
  solo and write (the `resolveCurrentWorkspaceId` fail-to-solo posture is unsafe at a WRITE
  boundary — it would silently misroute a team write to the caller's solo row). This is why
  the routes switch from `resolveCurrentWorkspaceId` → `resolveActiveWorkspace`.

**The deliberate column split (P2-2 — make explicit so reviewers don't flag it):** the
**repo-connection** columns (`repo_url`, `github_installation_id`, `repo_status`,
`repo_last_synced_at`, `repo_error`) move to `workspaces.<activeId>`. The
**provisioning/readiness** columns (`workspace_status`, `health_snapshot`) are NOT relocated
by ADR-044 and stay on the **owner's `users` row** — and the connecting caller IS the owner
(owner-gated), so `user.id` is the correct key for those specific writes. This split is
intentional; the readiness gate (`resolveActiveWorkspaceKbRoot:518-532`) reads the active
workspace OWNER's `users.workspace_status`, so the owner-keyed write is correct.

**3a. `app/api/repo/setup/route.ts`:**
- Replace the PR-2a 422 block (`:50-59`) with: resolve active id; on `{ok:false,"db-error"}`
  return 503 (retryable). Keep IDOR posture — the id is claim-derived, never `req.body`.
- Owner-gate (`:69-72`): `p_workspace_id` = **resolved active id** (was `user.id`).
- Lock flip + repo write (`:179-208`): write `workspaces` (status `cloning`, `repo_url`,
  `repo_error: null`, `repo_last_synced_at`) keyed on active id; the optimistic
  `.neq("repo_status","cloning")` lock moves to the `workspaces` row. **Remove** the
  `users.*` write at `:182-186` and the mirror at `:212-217`.
  - **P0-5 (race):** the lock predicate MUST become
    `workspaces.update(...).eq("id", activeId).neq("repo_status","cloning")` so the contended
    row is the SHARED workspace, not each caller's own `users` row. On `users` keyed per
    caller, two concurrent connect attempts on the same team workspace would both win the
    lock; on `workspaces.<activeId>` they serialize correctly. `workspaces.repo_status` has
    the same CHECK enum (mig 079:53-54) so the transition is schema-compatible; `service_role`
    keeps its default grant so the service-client lock write is unaffected by the REVOKE.
- `provisionWorkspaceWithRepo(activeId, ...)` (`:228`, was `user.id`) — provision
  `/workspaces/<active_id>` on disk.
- Background callback (`:236-345`): the resolved active id is **captured in the closure**
  (do NOT re-resolve inside the callback — the session claim could drift between request
  return and clone completion; identity-pinned write SE). Write the **repo-connection**
  cols (`repo_status:ready/error`, `repo_error`, `repo_last_synced_at`) to
  `workspaces.<capturedActiveId>`; keep the **provisioning/readiness** cols
  (`workspace_status`, `health_snapshot`) on the owner's `users` row (the connecting caller
  IS the owner — see the deliberate column split above). **Remove** the `users.*`
  repo-connection writes at `:254-263`/`:329-332` and the mirrors at `:274-277`/`:342-344`.
  - **P0-4 (`triggerHeadlessSync`):** the call at `:297-304` passes
    `resolveWorkspaceId: resolveCurrentWorkspaceId`, which RE-RESOLVES inside the helper. It
    must instead target the **captured active id** (pass a `() => capturedActiveId` thunk or
    the id directly), else headless sync runs against the now-active workspace instead of the
    just-cloned one if the user switched workspaces mid-clone.
  - **0-row silent no-op (deepen data-integrity — load-bearing):** a
    `workspaces.update(...).eq("id", capturedId)` that matches **0 rows** returns
    `{error:null}` — a SILENT no-op (the workspace could be deleted between request return
    and callback completion; `current_workspace_id` is `ON DELETE SET NULL`, mig 079:145).
    The callback's terminal `workspaces` writes (success + error branch) MUST `.select("id")`
    and treat an empty result as a failure class → `reportSilentFallback`
    (`cq-silent-fallback-must-mirror-to-sentry`). For the team-id path, prefer re-validating
    workspace existence/membership at callback time over blindly trusting the
    closure-captured id across the clone RTT.
  - Note: `workspace_path` becomes a `workspaces` column write — **confirm the column
    exists** (mig 079 did NOT add `workspace_path` to `workspaces`; the read path uses
    `workspacePathForWorkspaceId(id)` deriving the path from id, `workspace-resolver.ts:792`).
    If no consumer reads `workspaces.workspace_path`, the relocation target for
    `workspace_path` is to **drop the write entirely** (the path is derived from the
    workspace id, not stored) — verify at /work; this is the cleanest exit and still
    satisfies the zero-`users.*`-write criterion. `health_snapshot` similarly: check
    whether it must relocate or stays a `users` column (it is NOT a repo-connection
    column ADR-044 relocates; confirm consumer reads).
- **`workspaces.workspace_status`** is read by `resolveActiveWorkspaceKbRoot` readiness
  gate via the OWNER's `users.workspace_status` (`workspace-resolver.ts:518-532`) — this
  is a `users` read (owner's row), NOT a `users` *write* under `app/api/repo/**`, so it is
  out of the exit-criterion scope; do not relocate it in this PR (flag in Non-Goals).

**3b. `app/api/repo/disconnect/route.ts`:**
- Replace the 422 block (`:49-58`) with active-id resolution (same fail-closed posture).
- Owner-gate `p_workspace_id` = resolved active id.
- The `cloning`-lock fetch (`:94-98`) + the clear write (`:119-131`) → `workspaces` keyed
  on active id (clear `repo_url`, `github_installation_id`, `repo_status:not_connected`,
  `repo_last_synced_at`, `repo_error`). **Remove** the `users.*` clear and the mirror
  (`:150-164`). Fail-closed on the authoritative `workspaces` write.
  - **P1-6:** the cloning-guard SELECT at `:94-98` reads `users.repo_status` today — it MUST
    move to `workspaces.<activeId>.repo_status`, or a team disconnect checks the
    disconnecter's personal (non-cloning) row and proceeds to delete a workspace whose
    shared clone is in flight (the background `.then` then writes `ready` to a deleted dir).
- **On-disk teardown** (`deleteWorkspace(active_id)`, was `user.id`): **P0-6 — a team
  workspace dir is SHARED across members.** Tearing down `/workspaces/<team_id>` on a
  disconnect removes the shared clone for all members, and a member running an agent session
  in that dir gets ENOENT mid-operation. This is *intended* (disconnecting the team's repo
  disconnects it for everyone, owner-only) — but the handler MUST **abort live member
  sessions before the `rm`** (the `abortAllWorkspaceMemberSessions` path referenced at
  `workspace-resolver.ts:730` / the ws-handler) so no agent is mid-write when the dir
  disappears. Confirm the abort hook with spec-flow/CPO at /work. (Member *removal* is a
  separate flow that does NOT call `deleteWorkspace` — `workspace.ts:268-270`.)

**3c. `app/api/repo/install/route.ts`:**
- The install route stores `github_installation_id` pre-setup. It has NO active-workspace
  resolution today (`:118-121` writes `users`). The installation grant must land on the
  active `workspaces` row. **Resolve active id** (claim-derived) and write
  `workspaces.github_installation_id` keyed on it; **remove** the `users` write (`:120`)
  and the mirror (`:139-141`). Note: `github_installation_id` is REVOKE'd from the
  `authenticated` grant — a service-role write is required (route already uses
  `serviceClient`), correct.
- **Owner-gate consideration:** install writes a credential to the active workspace — add
  the `is_workspace_owner(activeId, user.id)` gate (parity with setup/disconnect) so a
  non-owner can't write the team's credential. Flag for spec-flow: is install reachable
  with a team workspace active? If yes, gate it; if it's always pre-team (solo onboarding),
  document the no-op.

**3d. `app/api/repo/detect-installation/route.ts`:**
- Same as install: the login-matched install write (`:141`) + mirror (`:178-180`) →
  `workspaces.github_installation_id` keyed on the resolved active id; remove the `users`
  write.
- **23505 branch goes DEAD on full relocation (deepen-confirmed).** The partial-UNIQUE is
  on `users.github_installation_id` ONLY (mig 052:159-161); `workspaces` is intentionally
  NON-unique (mig 079:57-66, ADR-044 fan-out). So the `23505` tolerance branch (`:145-165`)
  can never fire on a `workspaces.github_installation_id` UPDATE — **delete it** (do not
  keep dead error-handling). **But re-justify the cross-tenant guard it served:** the
  `users` UNIQUE was the load-bearing guard against "founder A's PRs land on founder B's
  dashboard" (mig 052:153-157). After removal, that invariant is enforced by the **webhook
  push-reconcile fan-out** over `(installation_id, normalizeRepoUrl(repo_url))` (ADR-044
  Decision §1). The plan MUST confirm at /work that the fan-out reconcile preserves the
  attribution invariant before relying on it instead of the DB UNIQUE — cite the reconcile
  code path. (The `users` UNIQUE itself is dropped by PR-2b, not here.)

**Exit-criterion gate (Phase 3 AC):** `git grep -nE
'\.from\("users"\)[^;]*\.update\([^)]*\b(repo_url|workspace_path|github_installation_id|repo_error)\b'
-- 'apps/web-platform/app/api/repo/**'` returns **0** matches. (Plus a broader sweep that
covers multi-line `.update({...})` blocks — see SE on write-boundary sweeps; the AC must
catch the patch-object form, not just a single-line literal.)

**Tests:** extend `test/setup-route-install-resolution.test.ts`,
`test/disconnect-route.test.ts`, `test/install-route*.test.ts`,
`test/detect-installation-fallback.test.ts`:
- The PR-2a 422 tests (`setup-route-install-resolution.test.ts:176`,
  `disconnect-route.test.ts:141`) **must be rewritten** — a team workspace active now
  PROVISIONS (200), it does not 422. Replace with: team-active + owner → provisions
  `/workspaces/<team_id>` and writes `workspaces.<team_id>`; team-active + non-owner → 403;
  active-id resolver `{ok:false}` → 503.
- Owner-gate `p_workspace_id` asserted to equal the **resolved active id** (not `user.id`)
  on the team path.
- Writes target `workspaces`, never `users` (mock asserts no `users.update` of the four
  columns).

### Phase 4 — Re-key `repo_error` read [FR3]

`apps/web-platform/server/current-repo-url.ts`:
- `getCurrentRepoStatus` (`:106-166`): read `repo_error` from `workspaces` (keyed on the
  resolved target workspace id, `:129-130`) instead of `users` (`:140-144`). This **fixes**
  the documented dispatching-user-vs-active-workspace key mismatch (`:97-104`): the error
  reason now keys on the same active workspace as `repo_status`, so a member dispatching
  against a workspace whose error was caused by another member reads the correct reason.
- Remove the now-stale forward-looking comment block (`:97-104`) and the `users.repo_error`
  read; update the doc comment.
- **Tests:** `getCurrentRepoStatus` returns the active workspace's `repo_error`; the
  cross-member case now returns the workspace reason, not null.

### Phase 5 — ADR-044 amendment + C4 edge [arch, wg-architecture-decision-is-a-plan-deliverable]

Per the `## Architecture Decision` section: amend ADR-044 lifecycle note + C4 edge
prose (write=User → write=Workspace), status stays `adopting`. Check `model.c4` for an
explicit edge; route any `.c4` edit through the Concierge `c4-edit` path.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] AC1: `git grep -nE '\.from\("users"\)' -- 'apps/web-platform/app/api/repo/**'`
  shows NO `.update()` of `repo_url|workspace_path|github_installation_id|repo_error`
  (the `hr-write-boundary-sentinel-sweep` gate). Sweep covers multi-line patch objects.
- [ ] AC2: Connect-time writes for those columns target `workspaces` keyed on the
  resolved active workspace id (assert in route tests, both team + solo).
- [ ] AC3: The PR-2a 422 refusal is **gone** from `setup` + `disconnect`; a team-active
  owner now provisions (200); a team-active non-owner gets 403; resolver `{ok:false}`
  gets 503. (Old 422 tests rewritten, not deleted silently.)
- [ ] AC4: Owner-gate `p_workspace_id` equals the resolved active id (the mutation
  target) in all gated routes — asserted in tests.
- [ ] AC5: The active workspace id is resolved from session/claim via
  `resolveActiveWorkspace`, never from `req.body`/`req.query` (IDOR) — grep the routes
  for `body.workspaceId`/`req` workspace-id reads returns 0.
- [ ] AC6: mig 110 adds `workspaces.repo_error`, re-issues the full non-credential GRANT
  with `repo_error` included, and is idempotent + `.down.sql`-reversible; `verify/110`
  asserts (a) SOLO drift-gate `COUNT = 0` post-reconcile AND (b) `0 co-membered rows
  adopted WITHOUT an attestation` (NOT "0 SKIP rows remaining" — co-membered backlog is a
  lawful carried residual cleared by owner re-connect, per CLO/PA-17(c)). Verified in a
  rolled-back dev txn.
- [ ] AC7: `getCurrentRepoStatus` reads `repo_error` from `workspaces`; cross-member case
  returns the workspace reason (test).
- [ ] AC8: `repo_error` is in the `authenticated` GRANT set on `workspaces` (it is a
  reason string, not a credential) — `github_installation_id` stays REVOKE'd.
- [ ] AC9: Typecheck clean: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [ ] AC10: Test suite green via the repo's runner (check `apps/web-platform/package.json
  scripts.test` / `vitest.config.ts include:` globs before prescribing a path —
  `./node_modules/.bin/vitest run <path>`).
- [ ] AC11: ADR-044 amended (lifecycle + C4 edge write=Workspace, status stays
  `adopting`); C4 model checked/updated.
- [ ] AC12: `## Observability` failure modes (below) reachable from Sentry without SSH.

### Post-merge (operator → automated)
- [ ] AC13: mig 110 applied by the release pipeline (`web-platform-release.yml #migrate`
  runs before code cutover — automated, no operator SSH). Verify via the Supabase MCP /
  `gh` post-merge, not a dashboard eyeball.
- [ ] AC14: Open the PR-2b soak window — confirm `repo_resolver_divergence` breadcrumb
  volume in Sentry (issues API query, deterministic verdict) before #5437 proceeds. `Ref
  #5437` (do not `Closes` — PR-2b is the closer).

## Observability

```yaml
liveness_signal:
  what: workspaces-authoritative connect writes succeed (repo_status transitions cloning→ready)
  cadence: per repo-connect event
  alert_target: Sentry (feature=workspace-repo-write) + existing repo-setup dashboards
  configured_in: apps/web-platform/server/workspace-repo-mirror.ts (renamed writeRepoColsToWorkspace) reportSilentFallback
error_reporting:
  destination: Sentry via reportSilentFallback / withIsolationScope (existing setup-route catch)
  fail_loud: true (authoritative workspaces write failure surfaces to the caller; no silent users fallback)
failure_modes:
  - mode: workspaces write fails on connect → connection not persisted
    detection: reportSilentFallback feature=workspace-repo-write op=write-to-workspace
    alert_route: Sentry issue (existing op-contract)
  - mode: resolveActiveWorkspace {ok:false} → 503, no provisioning into unverified team
    detection: reportSilentFallback op=resolveActiveWorkspace.membership-probe
    alert_route: Sentry
  - mode: disconnect credential-clear mirror/write fails → fail-closed 500
    detection: logger.error "Failed to clear repo fields"/"mirror repo disconnect" + 500 status
    alert_route: Sentry + 5xx rate
  - mode: mig-110 drift reconcile leaves COUNT>0 (PR-2b drift gate unreachable)
    detection: verify/110 assertion + the PR-2b drift query
    alert_route: pipeline migrate-step failure (web-platform-release.yml)
logs:
  where: pino structured logs (server/logger) + Sentry; preserve existing message: strings
  retention: per existing Sentry/Better Stack config
discoverability_test:
  command: gh api -X GET "/repos/.../issues?labels=..." OR Sentry issues API query feature=workspace-repo-write (NO ssh)
  expected_output: zero new error issues for a healthy connect/disconnect cycle on dev
```

## Domain Review

**Domains relevant:** Engineering (CTO/architecture), Product (CPO — single-user-incident
threshold), Legal (CLO — co-member repo adoption consent basis). No UI surface (the four
routes are API-only; no `components/**/*.tsx` or `app/**/page.tsx` in Files to Edit) →
**Product/UX Gate = NONE** (no wireframe needed; `wg-ui-feature-requires-pen-wireframe`
does not fire).

### Engineering (CTO / architecture-strategist)
**Status:** carried-forward from ADR-044 + this plan's premise validation.
**Assessment:** The write-cutover is the architecturally-load-bearing half (the read path
shipped in PR-1). Key risks: (a) the `p_workspace_id == mutation-target` confused-deputy
invariant must hold atomically; (b) the membership-verified resolver must fail-closed; (c)
removing the `users.*` rollback net is sound only because the read path is workspaces-only
and the columns are not dropped (revert-safe). All addressed in phases.

### Product (CPO)
**Status:** sign-off required (`requires_cpo_signoff: true`). The team-provisioning replaces
a deliberate honesty-refusal (422) with real behavior — the brand-survival framing (wrong
clone / leaked credential) is inherited from ADR-044.

### Product/UX Gate
**Tier:** none — no UI surface (API routes + migration only; no `components/**/*.tsx`,
`app/**/page.tsx`, or `app/**/layout.tsx` in Files to Edit). `wg-ui-feature-requires-pen-wireframe`
does not fire; no `.pen` wireframe required.
**Decision:** N/A (no UI surface).
**Agents invoked:** spec-flow-analyzer (gap analysis — 7 P0 / 6 P1 / 4 P2; all P0/P1 folded
into Phases 1-4 + Sharp Edges).
**Skipped specialists:** none.
**Pencil available:** N/A (no UI surface).

### Legal (CLO)
**Status:** review the co-member repo-adoption consent basis shift. mig-080 SKIPped
co-membered workspaces "no Art. 6(1)(f) co-member access without owner re-consent." Phase 4
reconcile adopts the owner-connected repo onto co-membered workspaces **the owner owns**;
the owner re-consent is now structurally the owner-gated write itself. Confirm this
satisfies the CLO requirement (owner-initiated = Art. 6(1)(b) contract), documented in the
migration header.

## GDPR / Compliance Gate

Touches regulated-data surfaces (migration, credential column `github_installation_id`,
auth-adjacent owner-gate). `/soleur:gdpr-gate` runs at /work against the plan + migration
110. Watch items: (a) the credential stays REVOKE'd from `authenticated` (only the reader
RPC); (b) `repo_error` is a *sanitized* reason (`sanitizeGitStderr`) — confirm no raw paths
leak into the new `workspaces.repo_error` column; (c) the co-member adoption consent basis
(CLO above). Output advisory-only with mandatory disclaimer.

## Open Code-Review Overlap

1 open scope-out touches a file this plan edits:
- **#3739** (`review: extract reportSilentFallbackWithUser helper — collapse 11-site
  withIsolationScope+setUser duplication`) — touches the `setup/route.ts` catch block
  (`:307-315`) this plan modifies. **Disposition: Acknowledge.** This plan relocates the
  *write target* inside that catch (users→workspaces) but does not refactor the
  `withIsolationScope+setUser` duplication; folding in the 11-site helper extraction is a
  distinct concern with broader blast radius. The scope-out remains open; the new write
  site should adopt the helper if/when #3739 lands. Do not silently re-file.

## Test Scenarios

1. Solo owner connects → `workspaces.<user.id>` authoritative write, `/workspaces/<user.id>`
   provisioned, no `users.*` write.
2. Team owner connects → `workspaces.<team_id>` write, `/workspaces/<team_id>` provisioned,
   owner-gate `p_workspace_id=<team_id>`.
3. Team non-owner connects → 403 (owner-gate), no write, no provisioning.
4. Active-id resolver `{ok:false,"db-error"}` → 503, no provisioning into unverified team.
5. Disconnect by team owner → `workspaces.<team_id>` cleared, fail-closed on write error,
   `/workspaces/<team_id>` torn down (shared — owner-only).
6. `repo_error` written to `workspaces` on clone failure; `getCurrentRepoStatus` reads it
   from `workspaces` for the active workspace (cross-member case correct).
7. mig 110 idempotent; SOLO drift-gate COUNT → 0 after re-key; co-membered residual carried
   (asserted as "0 adopted without attestation", not auto-drained) — rolled-back dev txn.
8. install / detect-installation write `github_installation_id` to `workspaces`, not `users`.

## Non-Goals (deferred — tracked)
- **DROP** `users.{repo_url, workspace_path, github_installation_id}` + the mig-052
  partial-UNIQUE index → **PR-2b / #5437** (soak-gated; this PR opens the soak window).
- **Auto-draining the co-membered SKIP backlog** is OUT OF SCOPE and **deliberately not
  done** (CLO/PA-17(c) blocker — auto-adoption without a fresh attestation is unlawful).
  These rows are a lawful carried residual; they clear when the owner re-connects from the
  team context (this PR's write path). PR-2b's column drop must tolerate this residual.
- `workspace_status` / `health_snapshot` relocation (not repo-connection columns ADR-044
  relocates; stay on `users`). If a future need arises, file separately.
- ADR-044 `status: adopting → accepted` flip + wholly-Workspace C4 edge → PR-2b.
- Sentry `sentry_issue_alert` routing for the divergence fingerprint (ADR-044 fast-follow).

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/placeholder,
  or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above.)
- **The owner-gate `is_workspace_owner` reads a `workspace_members` owner row — it is a
  DATA precondition, not a structural no-op.** mig 109 already backfilled the solo
  owner-membership canary (18,287→0 on dev). For TEAM workspaces the owner row exists by
  construction (team creation inserts it). Re-run the canary count at /work before relying
  on the gate (`2026-06-17-rls-gate-on-db-row-presence...`).
- **Write-boundary sweep must catch the multi-line patch-object form.** A grep for a
  single-line `repo_url:` literal misses `.from("users").update({ \n repo_url, ... })`.
  The AC1 grep must match the `.from("users").update(` open across the four columns
  (`hr-write-boundary-sentinel-sweep-all-write-sites`).
- **Capture the resolved active id in the setup background-callback closure — do NOT
  re-resolve.** The session claim can drift between request and callback completion;
  re-resolving could write `repo_status:ready` to a different workspace than the one
  provisioned (`2026-05-29-identity-pinned-workspace-not-session-selection-for-automation-writes`).
- **Use `resolveActiveWorkspace` (membership-verified), not `resolveCurrentWorkspaceId`
  (fail-closes to solo).** At the WRITE/provisioning boundary, a db-error must fail-closed
  (503), never silently provision into the caller's solo workspace under a team claim.
- **`workspace_path` may have no `workspaces` column / consumer** — the read path derives
  the path from the workspace id (`workspacePathForWorkspaceId`). Verify before writing
  `workspaces.workspace_path`; the clean relocation may be to DROP the write entirely
  (still satisfies zero-`users.*`-write). Same for `health_snapshot`.
- **The `23505` unique-violation branch in detect-installation** guards the mig-052 UNIQUE
  on `users.github_installation_id`. `workspaces` has no such UNIQUE (ADR-044 fan-out) — the
  branch may become dead on the `workspaces` write; verify reachability, don't keep dead
  error-handling.
- **Migration-test + test-runner discovery:** check `apps/web-platform/vitest.config.ts`
  `include:` globs and `package.json scripts.test` before prescribing a test path; typecheck
  is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (no `npm run -w`).
- **`Ref #5437`, not `Closes`** — PR-2b is the closer; this PR only opens its soak window.
- **The new `workspaces.repo_error` column needs an explicit re-GRANT.** Adding a column does
  NOT auto-add it to the column-level GRANT mig 079 set (`GRANT SELECT (id, …) ON
  public.workspaces TO authenticated`). Without adding `repo_error` to that list, a tenant
  read of it returns permission-denied. It is a sanitized reason string (non-credential) so
  it belongs in the `authenticated` set; `github_installation_id` stays REVOKE'd. (AC8.)
- **No `users.*` rollback net during this PR's soak (P1-3).** The read path is workspaces-only,
  so a relocation bug is *immediately* user-visible (no users fallback masks it). Keep the
  `users.*` repo columns PRESENT (PR-2b drops them) so a hotfix can reconcile from the frozen
  `users` snapshot, and rely on the Sentry divergence breadcrumb (Observability) for early
  detection. PR-2b must not merge until this write-cutover soaks.
- **The `resetFromClaim` self-heal branch is a WRITE-path concern (P0-3), not just a read
  one.** A removed member with a stale team claim must disconnect/connect their OWN solo
  workspace (the reset id), with the owner-gate + writes + provisioning all on that reset id
  — never the stale claim. Without this, the write path could target a team the caller no
  longer belongs to.
