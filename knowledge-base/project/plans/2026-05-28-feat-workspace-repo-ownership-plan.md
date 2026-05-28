---
title: Workspace Repo Ownership (user → workspace)
date: 2026-05-28
issue: 4558
branch: feat-workspace-repo-ownership
pr: 4559
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-05-28-workspace-repo-ownership-brainstorm.md
spec: knowledge-base/project/specs/feat-workspace-repo-ownership/spec.md
status: plan
---

# ✨ Plan: Workspace Repo Ownership (#4558)

## Enhancement Summary

**Deepened on:** 2026-05-28 · **Agents:** data-integrity-guardian, security-sentinel, architecture-strategist, Supabase Postgres best-practices (+ prior 4-agent plan-review & GDPR gate).

### Key improvements folded in (substance layer plan-review can't see)
1. **P0 slug-vs-URL parity** — webhook `repository.full_name` is a bare `owner/repo` slug, not a URL; compose `https://github.com/${full_name}` before `normalizeRepoUrl` or the reconcile matches zero rows while green tests pass (silently kills #4543's path). (AC7)
2. **P0 Inngest schema bump** — adding `full_name` to the reconcile payload requires `WORKSPACE_RECONCILE_SCHEMA_V` "1"→"2"; in-flight v=1 replays would pass the gate with a missing field. (AC6)
3. **High-severity RLS credential leak** — row-level RLS exposes `github_installation_id` (a token grant) to any workspace member; column-level REVOKE + read only via the new `resolve_workspace_installation_id` SECURITY DEFINER RPC. (AC2/AC4)
4. **P0 backfill drift** — repos connected between 080 and 081 strand on `users`; pre-decommission reconciliation gate. (AC15)
5. **P1 undefined-claim cross-tenant read** — null `current_workspace_id` must default to the caller's solo workspace, never an unscoped `LIMIT 1` sibling. (AC4)
6. **P1 RPC 4-role REVOKE**, **FK-race `v_org_id` guard**, **hook org-injection preservation**, **rollback claim-reset**, **dropped the `repo_url` UNIQUE in favor of fan-out reconcile**, and a flagged **ADR-038 amendment**.

### New consideration discovered
- The installation-id uniqueness guarantee migrates from a **DB UNIQUE constraint** to an **application-level `normalizeRepoUrl` contract** — so the TS/SQL parity test is now a **hard merge gate**, the single load-bearing cross-tenant guard.

## Overview

Move GitHub repo connection state (`repo_url`, `github_installation_id`, `repo_provider`, `repo_status`, `repo_last_synced_at`) from the `users` table to the `workspaces` table so a user can join another user's workspace and sync **that workspace's** repo. Durable root-cause fix for KB sync breaking for joined-workspace members (#4543, closed by inert band-aids #4546/#4557). Staged, additive, reversible. Brand-survival threshold = **single-user incident** (credentials + cross-tenant repo access + backfill).

Settled forks (from brainstorm): auto-adopt repo on join (read-only inherit) · preserve/restore personal sync per-workspace ("rooms") · `installation_id` on `workspaces` **non-unique** · confirm-then-switch switcher with a persistent live-repo badge kept truthful by **run-time repo revalidation** (not realtime push).

**Migration framing (post-review):** 2 SQL migrations — `079` (schema + session plumbing) and `080` (backfill) — applied in one `web-platform-release.yml#migrate` run but kept as separate files for `.down.sql` rollback granularity (schema vs. data). Then a TS-heavy read-cutover (no new DDL expected). Then a later decommission migration. The "staged" value is the *ordering* (schema before reads), not three numbered SQL files.

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Codebase reality (verified) | Plan response |
|---|---|---|
| Sync path hardcoded to `/workspaces/{user.id}` | No literal exists. `session-sync.ts` is `userId`-keyed; `agent-runner.ts` reads `users.workspace_path`; the `/workspaces/{user.id}` shape is *emergent* from ADR-038 solo invariant (`workspaces.id == users.id`). | Phase 081 re-keys workspace-path + installation resolution to active `current_workspace_id`; not a string swap. |
| Switcher must become "write-capable" | Already write-capable at **org-grain**: `org-switcher-container.tsx` POSTs `set_current_organization_id` (membership-checked RPC, migration 060) → `refreshSession()` → reload. "Read-only" is copy only. | Delta = workspace-grain claim + repo re-sync trigger + reactive badge. Reuse the 060 RPC pattern. |
| `installation_id` UNIQUE guard can move to workspaces | Webhook (`webhooks/github/route.ts:230-256`) resolves founder via `.eq("github_installation_id").maybeSingle()` and its comment states the 052 partial-UNIQUE is **load-bearing** (prevents 1:N mis-route). | Non-unique on workspaces REQUIRES switching the webhook to `(installation_id, repo_full_name)` resolution in the **same** cutover (Phase 081, TR5). Otherwise `.maybeSingle()` errors/mis-routes. |
| `075_transfer_workspace_ownership` may already move repo cols | It transfers owner **role** only (workspace_members + organizations.owner_user_id); touches zero repo columns. | Net-new schema work; no reuse beyond RPC-shape precedent. |
| Session carries `current_workspace_id` | Zero matches anywhere. Only `current_organization_id` exists (`user_session_state` + JWT hook, migration 060). | Phase 079 adds `current_workspace_id` to `user_session_state` + JWT hook + `set_current_workspace_id` RPC. |

## User-Brand Impact

**If this lands broken, the user experiences:** their agents run against the **wrong workspace's repo** (e.g., the badge says "Working on B" while sync still points at A), or KB sync silently stops after switching with no error.

**If this leaks, the user's source code + synced knowledge-base is exposed via:** a member resolving another workspace's `github_installation_id` (cross-tenant repo read), the LIKE-injection fallback in `resolve-installation-id.ts`, or a backfill that lands a repo onto a workspace that already has co-members (pre-vetting access).

**Brand-survival threshold:** single-user incident.

> CPO sign-off required at plan time (carried forward from brainstorm Phase 0.1 triad: CPO + CLO + CTO). `user-impact-reviewer` will be invoked at review time.

## Implementation Phases

### Phase 079 — Additive schema + session plumbing (reversible)

No existing reader changes behavior; new claim is injected but unread.

**Migration `079_workspace_repo_ownership_schema.sql`:**
- Header MUST carry a `-- LAWFUL_BASIS:` annotation (GDPR-gate Art-6): `Art. 6(1)(b) contract — repo connection is constitutive of the workspace service; co-member access under Art. 6(1)(f) per amended PA-17`.
- Add to `public.workspaces` (mirror 011 column shapes exactly): `repo_url text`, `repo_provider text DEFAULT 'github'`, `github_installation_id bigint`, `repo_status text DEFAULT 'not_connected' CHECK (repo_status IN ('not_connected','cloning','ready','error'))`, `repo_last_synced_at timestamptz`.
- Indexes: **non-unique** index on `(github_installation_id, repo_url)` (supports the webhook fan-out lookup) + non-unique index on `repo_url`. **Do NOT add a global UNIQUE on `repo_url`** (data-integrity P1): two users may each legitimately connect the same public repo/fork to their own personal workspace; a global UNIQUE throws 23505 at the second user mid-connect. Webhook determinism comes from **fan-out** (reconcile every workspace matching the repo), not from uniqueness — see Phase 081.
- **Column-level credential protection (Supabase RLS gap — highest-severity deepen finding).** `workspaces_select_for_members` (053:169) is *row*-level; Postgres RLS has no column scoping, so any member could `SELECT github_installation_id` (a GitHub App token grant) of their workspace. Close it: `REVOKE SELECT (github_installation_id) ON public.workspaces FROM authenticated` (column-level GRANT). The `authenticated` role keeps SELECT on `repo_url`/`repo_status`/etc. (members need "Working on: repo"); only the credential column is revoked.
- Add SECURITY DEFINER RPC `resolve_workspace_installation_id(p_workspace_id uuid) RETURNS bigint`: `is_workspace_member(p_workspace_id, auth.uid())` check (deny → return NULL, not raise), then `SELECT github_installation_id FROM workspaces WHERE id = p_workspace_id`. This is the *only* path that reads the credential — it enforces membership AND keeps the column off the `authenticated` grant. plpgsql, `SECURITY DEFINER`, `search_path = public, pg_temp`, `REVOKE ALL ... FROM PUBLIC, anon, authenticated, service_role` then `GRANT EXECUTE TO authenticated`.
- Add `current_workspace_id uuid NULL REFERENCES public.workspaces(id) ON DELETE SET NULL` to `public.user_session_state`; backfill from each user's solo workspace (`= users.id`), idempotent `WHERE current_workspace_id IS NULL`.
- Extend `runtime_jwt_mint_hook` (single Auth hook slot, migration 060 pattern) to also inject `app_metadata.current_workspace_id` from `user_session_state`, **preserving the existing org-injection block (`060:131-135`) and OTP precheck block (`060:139-148`) verbatim** (arch P1 — a copy-paste drop silently breaks org context for every token). Omit the workspace claim when NULL → consumer reads `undefined`. plpgsql, `SECURITY DEFINER`, `SET search_path = public, pg_temp`, no `EXCEPTION WHEN OTHERS`. `ALTER TABLE ... ADD current_workspace_id` MUST precede the `CREATE OR REPLACE` (it reads the column). Hook grant unchanged: `REVOKE ALL ... FROM PUBLIC, anon, authenticated, service_role` + `GRANT EXECUTE TO supabase_auth_admin` (NOT authenticated — arch P1).
- Add RPC `set_current_workspace_id(p_workspace_id uuid)`. Match the 060 precedent (`060:175-218`) **fully**: guards `auth.uid() IS NULL → 28000`, `p_workspace_id IS NULL → 22004`; membership-check via `is_workspace_member`; `SELECT organization_id INTO v_org_id FROM workspaces WHERE id = p_workspace_id` then **`IF v_org_id IS NULL THEN RAISE` (FK-race guard** — workspace deleted between membership-check and lookup → don't silently write `current_organization_id=NULL`, data-integrity P1); upsert BOTH `current_workspace_id` and `current_organization_id = v_org_id`. `SECURITY DEFINER`, `search_path = public, pg_temp`, **`REVOKE ALL ... FROM PUBLIC, anon, authenticated, service_role`** (4-role — omitting `authenticated`+`service_role` leaves the default EXECUTE grant intact per `2026-05-06-supabase-default-privileges-defeat-revoke-from-public`; arch P1) then `GRANT EXECUTE TO authenticated`.
- `.down.sql`: drop both RPCs, revert hook to exact 060 body, drop `current_workspace_id`, drop indexes + workspace repo columns + restore the column GRANT.

### Phase 080 — Idempotent solo-only backfill (keep users cols)

**Migration `080_backfill_workspace_repo_from_users.sql`:**
- Copy `users.{repo_url, repo_provider, github_installation_id, repo_status, repo_last_synced_at}` → `workspaces` joined on `w.id = u.id`. This join is **solo-only by construction**: post-flag-flip multi-member workspaces use `gen_random_uuid()`, so `w.id` never equals a `u.id` (ADR-038 N2, `053:43,62-69`). **Residual hole (Kieran P1-3):** a solo workspace whose owner invited someone still has `w.id = u.id` but is now co-membered. Close it with the canary-owner-row discriminator + count, matching the 053 idempotency canary (`053:207-215`): backfill only when `EXISTS (workspace_members WHERE workspace_id=w.id AND user_id=w.id AND role='owner')` **AND** `(SELECT COUNT(*) FROM workspace_members WHERE workspace_id=w.id) = 1`. Otherwise SKIP and `RAISE NOTICE` the workspace_id for owner re-consent (CLO requirement — never land a repo onto a co-membered workspace).
- Idempotency: `WHERE w.repo_url IS NULL AND u.repo_url IS NOT NULL` (re-runs log 0 rows). `DO $$ ... GET DIAGNOSTICS rc; RAISE NOTICE $$` audit per 053 precedent.
- **TS/SQL `normalizeRepoUrl` parity** (plan-time gate): run all `lib/repo-url.ts` fixtures through the SQL normalizer (migration 031) via a `WITH fixtures AS (VALUES ...)` CTE before committing; include `.git.git` repeated-suffix fixtures.
- `users` repo columns remain authoritative — NOT dropped here.
- **`080.down.sql` is forward-only for the data (data-integrity P2):** a blanket `UPDATE workspaces SET repo_url=NULL` would destroy repos connected *directly* to a workspace after 080 ran. The down must scope to rows still equal to the source (`workspaces.repo_url = users.repo_url AND workspaces.id = users.id`) OR document the data-copy as forward-only and rely on 079.down to drop the columns wholesale. Document the choice in the file.

### Phase 081 — Read cutover + switcher + sweep + security fix (TS-heavy)

Reads come from `workspaces` **only** (no `users` fallback → avoids the dual-ownership divergence trap).

- **Resolver rewrite** (`resolve-installation-id.ts:25-92`): signature → `resolveInstallationId(userId, workspaceId?)` (breaking change — callers pass the **claim-derived** active workspace). Read the credential **only via the `resolve_workspace_installation_id(workspaceId)` SECURITY DEFINER RPC** (membership-checked, column off the `authenticated` grant) — do NOT read `workspaces.github_installation_id` directly with a tenant or service client (closes the cross-tenant credential-read surface, security MEDIUM + Supabase RLS finding). **Delete the `.ilike("repo_url", ...)` sibling fallback outright** (removes the pre-existing LIKE-injection HIGH by deletion) AND **delete the unscoped `workspace_members … LIMIT 1` pattern (`:57-62`)** — a null/undefined claim must NOT resolve an arbitrary sibling workspace (cross-tenant read, data-integrity P1).
- **`workspaceId` provenance + undefined-claim default (security IDOR + data-integrity P1).** `workspaceId` is derived from the JWT `current_workspace_id` claim at every call site — **never** from `req.body`/`req.query`. When the claim is `undefined` (user hasn't re-logged-in post-079, or workspace deleted → `ON DELETE SET NULL`), the resolver defaults to the caller's **solo/personal workspace (`= users.id`)** — never errors, never picks a sibling. Mirror the documented `current_organization_id` → default-org fallback (`060:118-126`).
- **Run-time repo revalidation (replaces realtime badge reactivity).** The wrong-repo hazard's moment of harm is *agent-run time*. The resolver/sync entry path re-reads the active workspace's `repo_url` + `github_installation_id` at run time; if the repo is gone / the App lost access (GitHub 404) / the workspace changed under the user, it fails loud and surfaces the J3/J5 state. The badge then reads workspace-repo state **on mount/focus** (poll), not via a new realtime subscription. AC asserts *truthful-at-run-time*, not *re-renders-live*.
- **Call-site sweep** (`hr-write-boundary-sentinel-sweep-all-write-sites` + RLS same-PR client `.eq` sweep): thread active `workspaceId` through every site reading `users.repo_url`/`github_installation_id`. **Two signature breaks** beyond the resolver: `current-repo-url.ts:26 getCurrentRepoUrl(userId)` and the resolver itself — their callers must be swept. Known sites: `session-sync.ts` (getInstallationId 224, syncPull/Push), `current-repo-url.ts:50,68`, `kb-route-helpers.ts:92,103-113,158-159`, `agent-runner.ts:931,1255`, `app/api/repo/status/route.ts`, `kb/upload/route.ts`, `kb/sync/route.ts`, `kb/file/[...path]/route.ts`, dashboard pages, `hooks/use-conversations.ts`. **Re-grep at /work** (constrained): `git grep -nE '\.(eq|select)\([^)]*github_installation_id|users.*repo_url' apps/web-platform/server apps/web-platform/app` (exclude migrations/tests/comments — a bare `repo_url` grep is too coarse to be load-bearing, Kieran P2-3).
- **Webhook + push-reconcile re-architecture (Kieran P0-1 — the load-bearing gap).** Re-keying only `route.ts:237-241 .maybeSingle()` is insufficient: the `push` branch (`route.ts:275-316`) dispatches `{founderId, installationId}` to Inngest, and `workspace-reconcile-on-push.ts:97-128` fetches a **users** row by `founderId` then install-matches at `:124-128` — that is the primary KB-sync path #4543 is about. Required: (a) add `repository.full_name` to the route body type (`route.ts:193-201`, currently only `default_branch`) AND to the dispatched Inngest event payload (absent at `:305-313`); (b) **bump `WORKSPACE_RECONCILE_SCHEMA_V` "1" → "2"** and emit v=2 — adding a payload field is a consumer-boundary schema change; in-flight v=1 events persist ~24h and replay, and the gate (`workspace-reconcile-on-push.ts:83-91`) would pass a v=1 body lacking `full_name`. v=1 events drain cleanly to `{ok:false}` via the existing non-throwing mismatch branch (arch P0). (c) in the reconcile, resolve the target **workspace(s)** by `(github_installation_id, repo_url = normalize("https://github.com/" + full_name))` and rewrite the `:124-128` match against the workspace row.
- **Slug-vs-URL parity (data-integrity P0 — silent zero-match).** `repository.full_name` is a bare `owner/repo` **slug**, but `workspaces.repo_url` stores `https://github.com/owner/repo` (031 requires `scheme://host`; `lib/repo-url.ts` `new URL()` throws on a slug). `normalize(full_name)` never equals the stored URL → reconcile matches **zero rows** while the URL→URL parity test passes green, silently killing the #4543 path. Required: **compose `https://github.com/${full_name}` BEFORE normalizing**, and the AC9 parity test MUST include bare-slug→URL fixtures.
- **Fan-out reconcile (resolves the UNIQUE tension).** Because `repo_url` is **not** globally unique (two users may connect the same repo to their own workspaces), `(installation_id, normalized repo)` can match >1 workspace. The reconcile **fans out** and processes every matching workspace independently — this is both correct (a push to a shared repo affects all connected workspaces) and the reason no UNIQUE is needed for determinism. The `normalizeRepoUrl` TS/SQL parity is now the **sole** matching contract → AC9 is a **hard merge gate**, not advisory (arch P1).
- **`repository.full_name` fail-closed (Kieran P0-2).** Some handled event classes (`secret_scanning_alert`, `repository_advisory`) may omit `full_name` (read as `?? null` at `github-on-event.ts:80`). When absent, **fail closed** (404/skip with a logged reason) — never fall back to an installation-id-only `.maybeSingle()`.
- **Switcher write-path** (`org-switcher-container.tsx` + `org-switcher.tsx`): call `set_current_workspace_id` → `refreshSession()`; **read the claim from the session JWT, not `getUser()`** (`raw_app_meta_data` omits mint-hook claims — `2026-05-27` learning). **Inline** the confirmation + status chain (switching → syncing → ready / failed-with-retry) into the existing container — do NOT create a separate `workspace-switch-confirm.tsx` (DHH: it's one piece of container state, not a component).
- **Live-repo badge** (`live-repo-badge.tsx`, NEW): "Working on: owner/repo", reads workspace-repo state on mount/focus; backed by the run-time revalidation above. Renders the J7 "connect a repo" CTA when no repo, and the J1 empty-workspace state.
- **Workspace-path** resolution → active-workspace-relative (`workspace-resolver.ts`, `agent-runner.ts`).
- **Cascade** (`anonymise_organization_membership` migration 078 + account-delete): null/handle `workspaces.github_installation_id` (+ `.down.sql`-tested) — GDPR-gate Art-17.

### Phase (later) — Decommission

Separate migration drops `users.{repo_url, repo_provider, github_installation_id, repo_status, repo_last_synced_at}` + the 052 `users_github_installation_id_unique_idx` after a prod soak.

**Pre-decommission drift reconciliation (data-integrity P0 — gated AC, not "soak").** A user who connects a repo *between* 080's run and the 081 cutover is stranded on `users`, never backfilled. Before dropping `users` columns, assert: `SELECT COUNT(*) FROM users u JOIN workspaces w ON w.id=u.id WHERE u.repo_url IS NOT NULL AND w.repo_url IS DISTINCT FROM u.repo_url` returns **0** (re-backfill any drift first).

**Rollback is NOT clean-by-revert while 079 is shipped (arch P1).** Reverting only 081 (reads fall back to `users.*`) while 079's `current_workspace_id` claim still points a user at a *joined* workspace B → the agent runs against the user's own repo A while the UI/claim says B (the exact wrong-repo hazard, induced by the rollback). **The rollback runbook MUST also reset every `user_session_state.current_workspace_id` to the user's solo workspace** (reuse the J5 fallback) — make the rollback all-or-nothing (revert 079+080+081 together) or include the claim reset.

## Files to Edit

- `apps/web-platform/server/resolve-installation-id.ts` (resolver rewrite + delete LIKE fallback)
- `apps/web-platform/server/session-sync.ts` (workspace-keyed resolution)
- `apps/web-platform/server/workspace-resolver.ts` (active-workspace path)
- `apps/web-platform/server/current-repo-url.ts`
- `apps/web-platform/server/kb-route-helpers.ts`
- `apps/web-platform/server/agent-runner.ts`
- `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts`
- `apps/web-platform/app/api/webhooks/github/route.ts` (founder→workspace resolution)
- `apps/web-platform/app/api/repo/status/route.ts`, `kb/upload/route.ts`, `kb/sync/route.ts`, `kb/file/[...path]/route.ts`
- `apps/web-platform/components/dashboard/org-switcher.tsx`, `org-switcher-container.tsx` (write-path + confirm + status)
- `apps/web-platform/hooks/use-conversations.ts`
- `docs/legal/privacy-policy.md`, `docs/legal/data-protection-disclosure.md`, `docs/legal/gdpr-policy.md`, `knowledge-base/legal/article-30-register.md` (PA-17 co-member access — TR8)
- `apps/web-platform/supabase/migrations/058_workspace_member_attestations.sql` consumers (attestation copy — repo/KB data-access consent)

## Files to Create

- `apps/web-platform/supabase/migrations/079_workspace_repo_ownership_schema.sql` (+ `.down.sql`)
- `apps/web-platform/supabase/migrations/080_backfill_workspace_repo_from_users.sql` (+ `.down.sql`)
- `apps/web-platform/components/dashboard/live-repo-badge.tsx` (poll-on-mount badge + J1/J7 empty/CTA states)
- Test files alongside (vitest — confirm runner via `package.json`; check `apps/web-platform/bunfig.toml`)
- _NOT created:_ `workspace-switch-confirm.tsx` (inline into the switcher container per DHH). The cascade/anonymise update migration is created only if `/work` finds 078 doesn't already cover the new column — decide at /work, don't pre-create an `081_*.sql`.

## Open Code-Review Overlap

2 open scope-outs touch a planned file (`kb-route-helpers.ts`): **#2244** (migrate upload route to `syncWorkspace`, finish PR #2235 scope) and **#2246** (low-severity polish). **Disposition: Acknowledge** — both are sync-helper consolidation/polish, a different concern from repo-ownership grain; folding them in would balloon a brand-survival PR. **Flag:** the Phase 081 call-site sweep MUST reconcile with #2244 if still open at /work time (if #2244's `syncWorkspace` migration changes the `kb/upload` call shape, thread `workspaceId` through the new shape).

## Acceptance Criteria

### Pre-merge (PR)
- AC1 `workspaces` has the 5 repo columns; **non-unique** indexes `(github_installation_id, repo_url)` + `repo_url`; **NO UNIQUE on `repo_url`** (pg_indexes assertion). 079 header contains `-- LAWFUL_BASIS:` (GDPR-gate Art-6).
- AC2 (credential column protection — Supabase RLS) A non-owner member's direct `SELECT github_installation_id FROM workspaces WHERE id=<their-ws>` is **denied/empty** (column-level GRANT revoked from `authenticated`); the value is obtainable only via `resolve_workspace_installation_id`. Non-credential cols (`repo_url`, `repo_status`) remain member-selectable.
- AC3 `080` backfill idempotent: second apply logs `0 rows`. A solo workspace that was invited-into (canary owner-row present BUT member count > 1) is SKIPPED + NOTICE-logged (Kieran P1-3).
- AC4 `resolveInstallationId` reads the credential **only via `resolve_workspace_installation_id` RPC**; `git grep -n 'ilike("repo_url"' apps/web-platform` returns **0**; the unscoped `workspace_members … LIMIT 1` pattern is gone. Tests: (a) 2-workspace member resolves the ACTIVE workspace's id, never a sibling's; (b) a **non-member** workspaceId resolves **null** (definer RPC membership-check); (c) **undefined** claim resolves the caller's **solo** workspace, never a sibling.
- AC5 `workspaceId` is **claim-derived** (JWT `current_workspace_id`) at every read/write site — grep confirms no site reads it from `req.body`/`req.query` (security IDOR). Constrained sweep `git grep -nE '\.(eq|select)\([^)]*github_installation_id|\.from\("users"\)[^;]*repo_url' apps/web-platform/server apps/web-platform/app` (excl. migrations/tests) returns **0**; the two signature breaks (`getCurrentRepoUrl`, `resolveInstallationId`) verified by tsc.
- AC6 (push path + schema bump, Kieran P0-1 + arch P0) `WORKSPACE_RECONCILE_SCHEMA_V` is `"2"`; route emits v=2 with `repository.full_name`; in-flight v=1 events drain to `{ok:false}` (non-throwing mismatch). Test: two workspaces sharing one `installation_id` are **both** reconciled (fan-out) by repo match; `full_name`-absent event **fails closed** (P0-2).
- AC7 (slug-vs-URL parity, data-integrity P0 — **hard merge gate**) The reconcile composes `https://github.com/${full_name}` before `normalizeRepoUrl`; the TS/SQL parity test includes **bare-slug→URL** fixtures + `.git.git`; fixtures **synthesized** (GDPR-gate TS-01). A reconcile-match test asserts a real push payload matches the stored `repo_url` (non-zero rows).
- AC8 `set_current_workspace_id`: rejects null auth (28000), null arg (22004), non-member (42501); on member-accept sets `current_workspace_id` AND `current_organization_id` via explicit `workspaces.organization_id` lookup; **raises if `v_org_id` is NULL** (FK-race guard). 4-role REVOKE asserted (no residual `authenticated`/`service_role` EXECUTE).
- AC9 (truthful-at-run-time) Switcher reads `current_workspace_id` from the **session JWT** (not `getUser()`). Test: after a non-switch repo mutation (J4) the resolver/sync entry path re-reads workspace-repo state and fails loud rather than running against the stale repo; badge reflects new state on mount/focus.
- AC10 OTP auth path still carries BOTH the existing `current_organization_id` AND the new `current_workspace_id` claim (hook org-injection preserved — arch P1 + Kieran P1-2).
- AC11 `anonymise_organization_membership` (or sibling) nulls `workspaces.github_installation_id`; `.down.sql` tested (GDPR-gate Art-17).
- AC12 Migrations apply cleanly on a **dev** Supabase branch (NOT shared dev pre-merge per `hr-dev-prd-distinct-supabase-projects`); verified against a real DB, not mocks.
- AC13 Must-ship journey states: owner-changed-repo → run-time revalidation interrupt (J4, = AC9); revocation → interstitial + `current_workspace_id` fallback to personal workspace (J5); post-backfill default landing = personal workspace (J6). _Deferred to #4560:_ J1/J2/J3/J7.

### Post-merge (operator)
- AC14 Apply 079 → 080 to prd via `web-platform-release.yml#migrate`; verify column presence + backfill row counts via Supabase MCP (read-only).
- AC15 **Pre-decommission drift reconciliation (data-integrity P0):** before any decommission migration, `SELECT COUNT(*) FROM users u JOIN workspaces w ON w.id=u.id WHERE u.repo_url IS NOT NULL AND w.repo_url IS DISTINCT FROM u.repo_url` returns **0** (re-backfill mid-migration connects first).
- AC16 **Open Q (ops fix):** verify GitHub App install `122213433` grants `jikig-ai/soleur` via App-JWT (`gh api /installation/repositories`). `Automation: feasible` — bake into a verification step. If absent, ops needs the App installed on `soleur` (separate follow-up).

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carry-forward from brainstorm Phase 0.5 triad).

### Engineering (CTO — carry-forward)
Stage 079 (additive) → 080 (idempotent solo-only backfill, keep users cols) → 081 (workspaces-only read cutover) → later decommission. Non-unique `installation_id` on workspaces; webhook resolves by `(installation_id, repo_full_name)`. Resolver sibling-fallback is the most dangerous code — delete/workspace-scope it. Complexity: LARGE.

### Legal (CLO — carry-forward)
No statutory clock. Design-time: amend PA-17 across Privacy Policy / Data-Protection-Disclosure §2.3 / GDPR Article-30 register + balancing for co-member repo/KB access (TR8). Backfill solo-only (enforced in 080). Removed-member local-clone purge obligation (TR7 + Open Q3). Attestation (058) copy must cover repo/KB data-access consent. Sequence `legal-document-generator` after the access model settles; re-audit with `legal-compliance-auditor`.

### Product/UX Gate

**Tier:** blocking (new component file: `live-repo-badge.tsx`; confirm+status inlined into the switcher container)
**Decision:** reviewed (partial — wireframes deferred)
**Agents invoked:** spec-flow-analyzer, cpo (carry-forward)
**Skipped specialists:** ux-design-lead (existing `.pen` assets `team-workspace-collaboration.pen` + `workspace-invite-acceptance.pen` cover the surface; wireframe the badge/confirm delta at /work or via Pencil before implementation)
**Pencil available:** not checked this session

#### Findings (spec-flow journey gaps)
- **Cross-cutting wrong-repo hazard (brand-survival, MUST SHIP):** the badge is written only on switch; J4 (owner swaps/disconnects repo) and J5 (revocation) mutate the active repo with **no switch event**. Resolved NOT via realtime push but via **run-time repo revalidation** at the moment of harm (resolver/sync re-reads workspace-repo state before running; fails loud on 404/change) + poll-on-mount badge (DHH/Simplicity convergence). (AC7)
- **J5 (MUST SHIP):** revocation interstitial "you no longer have access — returning to your personal workspace" + `current_workspace_id` fallback to personal workspace (else stale claim → blank/error).
- **J6 (MUST SHIP):** post-backfill default landing = personal workspace.
- **J1 (DEFERRED → follow-up):** first-sync entry screen / empty-workspace state ("owner hasn't connected a repo yet"). Copy/edge polish, not data-integrity.
- **J2 (DEFERRED → follow-up):** mid-flight "switch anyway?" prompt.
- **J3 (DEFERRED → follow-up):** transient-vs-permanent failure differentiation ("repo unavailable — owner must reconnect" + owner-notify). Run-time revalidation already fails loud; the differentiated copy is the deferred polish. (= Open Q1.)
- **J7 (DEFERRED → follow-up):** zero-repo "connect a repo to get started" CTA in the badge's place.

## Observability

```yaml
liveness_signal:
  what: KB sync success/last_synced_at per active workspace
  cadence: on every switch + on push-reconcile (inngest)
  alert_target: Sentry (sync failure) + structured pino log
  configured_in: apps/web-platform/server/session-sync.ts (recordKbSyncHistory)
error_reporting:
  destination: Sentry via reportSilentFallback / captureException
  fail_loud: true (no silent .catch on resolver/sync/switch paths)
failure_modes:
  - {mode: wrong-workspace installation resolved, detection: resolver unit test + Sentry tag feature=resolve-installation-id, alert_route: Sentry}
  - {mode: switch re-sync failed (transient), detection: FR3 status chain + Sentry, alert_route: in-UI retry + Sentry}
  - {mode: repo unavailable / App lost access (permanent), detection: GitHub API 404 on resolve, alert_route: in-UI owner-reconnect prompt + Sentry}
  - {mode: backfill skipped a co-membered workspace, detection: RAISE NOTICE in 080, alert_route: migration apply log review}
logs:
  where: pino structured logs (web-platform) → stdout; Sentry for errors
  retention: per existing web-platform retention
discoverability_test:
  command: "supabase MCP: select repo_url, github_installation_id from workspaces where id = '<ws>'; + Sentry issue search feature=resolve-installation-id"
  expected_output: active workspace row shows expected repo; zero new wrong-workspace Sentry events post-deploy
```

## Test Scenarios

- Migration idempotence (079 + 080 re-apply → 0 rows); multi-member workspace skipped.
- Resolver: member of 2 workspaces resolves the ACTIVE workspace's installation_id (never a sibling's).
- Webhook: shared installation_id across 2 workspaces **fans out** (both reconciled by repo name); `full_name`-absent fails closed; v=1 in-flight event drains to `{ok:false}`.
- Switcher: non-member rejected; member switch flips claim + re-sync; run-time revalidation fails loud on J4 owner-repo-change.
- Backfill slug→URL normalizer parity (bare `owner/repo` → `https://github.com/owner/repo`, incl. `.git.git`; synthesized fixtures).
- RLS: a member cannot SELECT another workspace's row (cross-workspace) AND cannot SELECT `github_installation_id` of their OWN workspace (column-level credential denial) — obtainable only via `resolve_workspace_installation_id`.
- Resolver: non-member workspaceId → null; undefined claim → solo workspace (never sibling).

## Risks & Sharp Edges

- A plan whose `## User-Brand Impact` section is empty/placeholder fails `deepen-plan` Phase 4.6 — this one is filled.
- **Dual-ownership divergence:** during soak, reads MUST come from `workspaces` only (no `users` fallback). A read-time fallback re-introduces the two-sources-of-truth trap (`2026-05-27-workspace-dual-ownership-source-of-truth.md`).
- **Supabase migration runner wraps each file in a transaction** — no `CREATE INDEX CONCURRENTLY` (sibling migrations document this). Plain `CREATE INDEX` for the small workspaces table is fine.
- **No UNIQUE on `repo_url`; webhook determinism via fan-out (deepen — resolves the reviewer tension).** `installation_id` non-unique on workspaces AND the `.maybeSingle()` users lookup both change together; but do NOT add a global UNIQUE on `repo_url` (breaks two-users-same-fork). The reconcile fans out to all workspaces matching `(installation_id, normalized repo)`. `normalizeRepoUrl` parity is the **sole** matching contract → hard merge gate (AC7).
- **Push-reconcile is the real KB-sync path (Kieran P0-1)** — re-key `workspace-reconcile-on-push.ts` (`:97-128`), not just the route; thread `repository.full_name` into the Inngest payload.
- **Inngest schema bump (arch P0)** — adding `full_name` to the payload requires `WORKSPACE_RECONCILE_SCHEMA_V` "1"→"2"; in-flight v=1 events would otherwise pass the gate with a body lacking the field. Drain v=1 to `{ok:false}`.
- **Slug-vs-URL parity (data-integrity P0)** — `repository.full_name` is a bare slug; compose `https://github.com/${full_name}` BEFORE normalizing or the reconcile matches zero rows while green tests pass.
- **Credential column leak (Supabase RLS, highest-severity)** — `github_installation_id` is a token grant; row-level RLS exposes it to any member. Column-level `REVOKE SELECT (github_installation_id) ... FROM authenticated` + read only via `resolve_workspace_installation_id` definer RPC.
- **Undefined `current_workspace_id` claim (data-integrity P1)** — un-refreshed sessions + `ON DELETE SET NULL` produce a NULL claim; resolver MUST default to the caller's solo workspace, never an unscoped `LIMIT 1` sibling (cross-tenant read).
- **RPC 4-role REVOKE (arch P1)** — `REVOKE ALL FROM PUBLIC, anon, authenticated, service_role` then `GRANT TO authenticated`; 2-role REVOKE leaves the default EXECUTE grant.
- **Decommission rollback strands the JWT claim (arch P1)** — reverting only 081 while 079 ships points a user at workspace B while reads fall back to their own repo A. Rollback must reset `current_workspace_id` to the solo workspace (all-or-nothing).
- **ADR-038 amendment required (arch P1)** — ADR-038 deliberately left repo state on `users`; this reverses that boundary and relocates the installation-id uniqueness guarantee from a DB UNIQUE to the `normalizeRepoUrl` contract. **Task: run `/soleur:architecture create` for a new ADR `amends: [ADR-038]`** before/with this PR.
- **`is_workspace_member` search_path** — verify it pins `search_path = public, pg_temp` (053:120 — it does) since the new definer RPCs call it.
- **Phase order is load-bearing:** 079 → 080 → 081. Atomic merge ≠ atomic per-phase.
- At `single-user incident` threshold, deepen-plan already ran — the triad (data-integrity-guardian + security-sentinel + architecture-strategist + Supabase pass) caught 2 P0s, a high-severity RLS credential leak, and the Inngest schema bump that the 4-agent plan-review missed.

## Open Questions

1. **GitHub App install scope (blocks ops fix):** does install `122213433` grant `jikig-ai/soleur`? Needs App-authenticated JWT — unresolvable from a user token. AC16.
2. Do `repo_last_synced_at` / `kb_sync_history` fully move to `workspaces`? Plan moves `repo_last_synced_at` (in the 011 set); `kb_sync_history` (jsonb on users, migration 017) — lean: move with repo, settle at /work.
3. Removed-member local-clone purge mechanism (TR7) — server-clone is controller-side; member-local copy out of technical control → T&C expectation-setting.
4. **ADR amendment:** create a new ADR amending ADR-038 (repo ownership user→workspace; uniqueness guarantee → normalization contract). Run `/soleur:architecture create` at /work Phase 0.
