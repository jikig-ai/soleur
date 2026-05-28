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
- Indexes: partial UNIQUE on `workspaces.repo_url WHERE repo_url IS NOT NULL` (one workspace per repo → deterministic webhook lookup); **non-unique** index on `workspaces.github_installation_id` (org-level installs span workspaces — do NOT make unique).
- Add `current_workspace_id uuid NULL REFERENCES public.workspaces(id) ON DELETE SET NULL` to `public.user_session_state`; backfill from each user's solo workspace (`= users.id`), idempotent `ON CONFLICT DO NOTHING`-style `WHERE current_workspace_id IS NULL`.
- Extend `runtime_jwt_mint_hook` (single Auth hook slot, migration 060 pattern) to also inject `app_metadata.current_workspace_id` from `user_session_state` (omit claim when NULL → consumer reads `undefined`). plpgsql, `SECURITY DEFINER`, `SET search_path = public, pg_temp`, no `EXCEPTION WHEN OTHERS`.
- Add RPC `set_current_workspace_id(p_workspace_id uuid)`. Match the 060 precedent (`060:175-218`) **fully**, including the two guards the first draft omitted: `auth.uid() IS NULL → RAISE ERRCODE '28000'` and `p_workspace_id IS NULL → RAISE ERRCODE '22004'`. Then membership-check via `is_workspace_member(p_workspace_id, auth.uid())` (it's `SECURITY DEFINER`, runs owner-context — safe to call from inside this RPC). On success: `SELECT organization_id INTO v_org_id FROM workspaces WHERE id = p_workspace_id` (explicit lookup — the membership check is workspace-grained, so the org value must be fetched, not inferred), then upsert BOTH `current_workspace_id` and `current_organization_id = v_org_id`. `SECURITY DEFINER`, `search_path = public, pg_temp`, `REVOKE ALL ... FROM PUBLIC, anon`; `GRANT EXECUTE TO authenticated`.
- `.down.sql`: drop RPC, revert hook to 060 body, drop `current_workspace_id`, drop indexes + workspace repo columns.

### Phase 080 — Idempotent solo-only backfill (keep users cols)

**Migration `080_backfill_workspace_repo_from_users.sql`:**
- Copy `users.{repo_url, repo_provider, github_installation_id, repo_status, repo_last_synced_at}` → `workspaces` joined on `w.id = u.id`. This join is **solo-only by construction**: post-flag-flip multi-member workspaces use `gen_random_uuid()`, so `w.id` never equals a `u.id` (ADR-038 N2, `053:43,62-69`). **Residual hole (Kieran P1-3):** a solo workspace whose owner invited someone still has `w.id = u.id` but is now co-membered. Close it with the canary-owner-row discriminator + count, matching the 053 idempotency canary (`053:207-215`): backfill only when `EXISTS (workspace_members WHERE workspace_id=w.id AND user_id=w.id AND role='owner')` **AND** `(SELECT COUNT(*) FROM workspace_members WHERE workspace_id=w.id) = 1`. Otherwise SKIP and `RAISE NOTICE` the workspace_id for owner re-consent (CLO requirement — never land a repo onto a co-membered workspace).
- Idempotency: `WHERE w.repo_url IS NULL AND u.repo_url IS NOT NULL` (re-runs log 0 rows). `DO $$ ... GET DIAGNOSTICS rc; RAISE NOTICE $$` audit per 053 precedent.
- **TS/SQL `normalizeRepoUrl` parity** (plan-time gate): run all `lib/repo-url.ts` fixtures through the SQL normalizer (migration 031) via a `WITH fixtures AS (VALUES ...)` CTE before committing; include `.git.git` repeated-suffix fixtures.
- `users` repo columns remain authoritative — NOT dropped here.

### Phase 081 — Read cutover + switcher + sweep + security fix (TS-heavy)

Reads come from `workspaces` **only** (no `users` fallback → avoids the dual-ownership divergence trap).

- **Resolver rewrite** (`resolve-installation-id.ts:25-92`): signature → `resolveInstallationId(userId, workspaceId)` (breaking change — every caller must pass a real `workspaceId`, not a placeholder; the sweep verifies this). Read `workspaces.github_installation_id` for the active workspace via `.eq("id", workspaceId)` (membership enforced upstream by RLS / the switcher RPC). **Delete the `.ilike("repo_url", ...)` sibling fallback outright** — do NOT replace it with an escaped-regex variant (YAGNI; no current call site needs owner-grain once resolution is workspace-keyed). This removes the pre-existing HIGH (LIKE wildcard injection) by deletion.
- **Run-time repo revalidation (replaces realtime badge reactivity).** The wrong-repo hazard's moment of harm is *agent-run time*. The resolver/sync entry path re-reads the active workspace's `repo_url` + `github_installation_id` at run time; if the repo is gone / the App lost access (GitHub 404) / the workspace changed under the user, it fails loud and surfaces the J3/J5 state. The badge then reads workspace-repo state **on mount/focus** (poll), not via a new realtime subscription. AC asserts *truthful-at-run-time*, not *re-renders-live*.
- **Call-site sweep** (`hr-write-boundary-sentinel-sweep-all-write-sites` + RLS same-PR client `.eq` sweep): thread active `workspaceId` through every site reading `users.repo_url`/`github_installation_id`. **Two signature breaks** beyond the resolver: `current-repo-url.ts:26 getCurrentRepoUrl(userId)` and the resolver itself — their callers must be swept. Known sites: `session-sync.ts` (getInstallationId 224, syncPull/Push), `current-repo-url.ts:50,68`, `kb-route-helpers.ts:92,103-113,158-159`, `agent-runner.ts:931,1255`, `app/api/repo/status/route.ts`, `kb/upload/route.ts`, `kb/sync/route.ts`, `kb/file/[...path]/route.ts`, dashboard pages, `hooks/use-conversations.ts`. **Re-grep at /work** (constrained): `git grep -nE '\.(eq|select)\([^)]*github_installation_id|users.*repo_url' apps/web-platform/server apps/web-platform/app` (exclude migrations/tests/comments — a bare `repo_url` grep is too coarse to be load-bearing, Kieran P2-3).
- **Webhook + push-reconcile re-architecture (Kieran P0-1 — the load-bearing gap).** Re-keying only `route.ts:237-241 .maybeSingle()` is insufficient: the `push` branch (`route.ts:275-316`) dispatches `{founderId, installationId}` to Inngest, and `workspace-reconcile-on-push.ts:97-128` fetches a **users** row by `founderId` then install-matches at `:124-128` — that is the primary KB-sync path #4543 is about. Required: (a) pass `repository.full_name` into the Inngest event payload; (b) in the reconcile, resolve the target **workspace** by `(github_installation_id, repo_url=normalized full_name)` and rewrite the `:124-128` match against the workspace row; (c) route founder/workspace resolution by `(installation_id, repo_full_name)`, deterministic via the `workspaces.repo_url` partial-UNIQUE + `normalizeRepoUrl` parity.
- **`repository.full_name` fail-closed (Kieran P0-2).** The route body type (`route.ts:193-201`) declares only `repository?.default_branch`; some handled event classes (`secret_scanning_alert`, `repository_advisory`) may omit `full_name` (read as `?? null` at `github-on-event.ts:80`). When `full_name` is absent, **fail closed** (404/skip with a logged reason) — never fall back to an installation-id-only `.maybeSingle()` (re-introduces the 1:N mis-route).
- **Switcher write-path** (`org-switcher-container.tsx` + `org-switcher.tsx`): call `set_current_workspace_id` → `refreshSession()`; **read the claim from the session JWT, not `getUser()`** (`raw_app_meta_data` omits mint-hook claims — `2026-05-27` learning). **Inline** the confirmation + status chain (switching → syncing → ready / failed-with-retry) into the existing container — do NOT create a separate `workspace-switch-confirm.tsx` (DHH: it's one piece of container state, not a component).
- **Live-repo badge** (`live-repo-badge.tsx`, NEW): "Working on: owner/repo", reads workspace-repo state on mount/focus; backed by the run-time revalidation above. Renders the J7 "connect a repo" CTA when no repo, and the J1 empty-workspace state.
- **Workspace-path** resolution → active-workspace-relative (`workspace-resolver.ts`, `agent-runner.ts`).
- **Cascade** (`anonymise_organization_membership` migration 078 + account-delete): null/handle `workspaces.github_installation_id` (+ `.down.sql`-tested) — GDPR-gate Art-17.

### Phase (later) — Decommission

Separate migration drops `users.{repo_url, repo_provider, github_installation_id, repo_status, repo_last_synced_at}` + the 052 `users_github_installation_id_unique_idx` after a prod soak. Rollback of the whole feature = revert Phase 081; backfilled workspace columns go inert, `users` columns still authoritative — which is why decommission is separated.

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
- AC1 `workspaces` has the 5 repo columns; partial-UNIQUE on `repo_url WHERE NOT NULL`; **non-unique** index on `github_installation_id` (pg_indexes shows no unique on installation_id). 079 header contains `-- LAWFUL_BASIS:` (GDPR-gate Art-6).
- AC2 `080` backfill is idempotent: second apply against a populated DB logs `0 rows` (RAISE NOTICE). A solo workspace that was invited-into (canary owner-row present BUT member count > 1) is SKIPPED and its id is NOTICE-logged (Kieran P1-3).
- AC3 `resolveInstallationId` signature is `(userId, workspaceId)`; `git grep -n 'ilike("repo_url"' apps/web-platform` returns **0** (fallback deleted, not replaced). A test asserts a 2-workspace member resolves the ACTIVE workspace's installation_id, never a sibling's.
- AC4 (checkable, not LARP) Constrained grep `git grep -nE '\.(eq|select)\([^)]*github_installation_id|\.from\("users"\)[^;]*repo_url' apps/web-platform/server apps/web-platform/app` (excluding migrations/tests) returns **0** bare `users`-keyed repo reads in cutover scope. Caller sweep also covers the two signature breaks (`getCurrentRepoUrl`, `resolveInstallationId`) — every caller passes a real `workspaceId`, verified by tsc (no optional/placeholder arg).
- AC5 (covers the push path, Kieran P0-1) Unit test: two workspaces sharing one `installation_id` route to the correct workspace **both** in the route resolution AND in `workspace-reconcile-on-push.ts` (event payload carries `repository.full_name`; reconcile matches the workspace row, not a users row). Separate test: a handled event with `full_name` absent **fails closed** (404/skip), does not `.maybeSingle()`-fallback (P0-2).
- AC6 `set_current_workspace_id`: rejects null auth (28000), rejects null arg (22004), rejects non-member (42501), accepts a member; sets `current_workspace_id` AND `current_organization_id` (via explicit `workspaces.organization_id` lookup).
- AC7 (truthful-at-run-time, not re-renders-live) Switcher reads `current_workspace_id` from the session JWT (not `getUser()`). Test: after a non-switch repo mutation (owner swaps/disconnects repo — J4) the resolver/sync entry path re-reads workspace-repo state and fails loud / surfaces J3/J5 rather than running against the stale repo; badge reflects the new state on mount/focus.
- AC8 OTP auth path still carries the new `current_workspace_id` claim (the JWT hook injects org_id for OTP too, so workspace_id must — Kieran P1-2).
- AC9 TS/SQL `normalizeRepoUrl` parity test passes (CTE fixtures incl. `.git.git`); fixtures are **synthesized**, not from prod (GDPR-gate TS-01).
- AC10 `anonymise_organization_membership` (or its sibling) nulls `workspaces.github_installation_id`; `.down.sql` tested (GDPR-gate Art-17).
- AC11 Migrations apply cleanly on a **dev** Supabase branch (NOT shared dev pre-merge per `hr-dev-prd-distinct-supabase-projects`); verified against a real DB, not mocks.
- AC12 Must-ship journey states (post-conditions): owner-changed-repo → run-time revalidation interrupt (J4, = AC7); revocation → interstitial + `current_workspace_id` fallback to personal workspace (J5); post-backfill default landing = personal workspace (J6). _Deferred to follow-up issues:_ J1 empty-workspace copy, J2 mid-flight "switch anyway", J3 transient-vs-permanent failure differentiation, J7 zero-repo CTA polish.

### Post-merge (operator)
- AC13 Apply 079 → 080 to prd via `web-platform-release.yml#migrate`; verify column presence + backfill row counts via Supabase MCP (read-only).
- AC14 **Open Q (ops fix):** verify GitHub App install `122213433` grants `jikig-ai/soleur` via an App-authenticated JWT call (`gh api /installation/repositories` with App JWT). `Automation: feasible` — bake into a verification step, not operator dashboard-watching. If access absent, ops needs the App installed on `soleur` (separate follow-up).

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carry-forward from brainstorm Phase 0.5 triad).

### Engineering (CTO — carry-forward)
Stage 079 (additive) → 080 (idempotent solo-only backfill, keep users cols) → 081 (workspaces-only read cutover) → later decommission. Non-unique `installation_id` on workspaces; webhook resolves by `(installation_id, repo_full_name)`. Resolver sibling-fallback is the most dangerous code — delete/workspace-scope it. Complexity: LARGE.

### Legal (CLO — carry-forward)
No statutory clock. Design-time: amend PA-17 across Privacy Policy / Data-Protection-Disclosure §2.3 / GDPR Article-30 register + balancing for co-member repo/KB access (TR8). Backfill solo-only (enforced in 080). Removed-member local-clone purge obligation (TR7 + Open Q3). Attestation (058) copy must cover repo/KB data-access consent. Sequence `legal-document-generator` after the access model settles; re-audit with `legal-compliance-auditor`.

### Product/UX Gate

**Tier:** blocking (new component files: `live-repo-badge.tsx`, `workspace-switch-confirm.tsx`)
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
- Webhook: shared installation_id across 2 workspaces routes by repo name.
- Switcher: non-member rejected; member switch flips claim + re-sync; badge reactive on J4 owner-repo-change.
- Backfill normalizer parity (TS fixtures == SQL output).
- RLS: a member cannot SELECT another workspace's repo columns they don't belong to.

## Risks & Sharp Edges

- A plan whose `## User-Brand Impact` section is empty/placeholder fails `deepen-plan` Phase 4.6 — this one is filled.
- **Dual-ownership divergence:** during soak, reads MUST come from `workspaces` only (no `users` fallback). A read-time fallback re-introduces the two-sources-of-truth trap (`2026-05-27-workspace-dual-ownership-source-of-truth.md`).
- **Supabase migration runner wraps each file in a transaction** — no `CREATE INDEX CONCURRENTLY` (sibling migrations document this). Plain `CREATE INDEX` for the small workspaces table is fine.
- **Webhook UNIQUE coupling** — do NOT make `installation_id` unique on workspaces AND do NOT keep the `.maybeSingle()` users lookup after cutover; both must change together (Research Reconciliation row 3).
- **Push-reconcile is the real KB-sync path (Kieran P0-1)** — the cutover MUST re-key `workspace-reconcile-on-push.ts` (founderId→users lookup at `:97-128`), not just the webhook route's `.maybeSingle()`. Threading `repository.full_name` into the Inngest event payload is load-bearing; a route-only fix leaves #4543's actual path untouched.
- **`repository.full_name` is not universal (Kieran P0-2)** — fail closed when absent; never fall back to installation-id-only resolution.
- **Phase order is load-bearing:** 079 (schema/claim) before 080 (backfill) before 081 (reads). Atomic merge ≠ atomic per-phase.
- At `single-user incident` threshold, run `/soleur:deepen-plan` before `/work` — plan-review (DHH/Kieran/Simplicity) is structurally blind to SQL-atomicity/security-primitive findings the deepen-plan triad (data-integrity-guardian + security-sentinel + architecture-strategist) catches.

## Open Questions

1. **GitHub App install scope (blocks ops fix):** does install `122213433` grant `jikig-ai/soleur`? Needs App-authenticated JWT — unresolvable from a user token. AC12.
2. Do `repo_last_synced_at` / `kb_sync_history` fully move to `workspaces`? Plan moves `repo_last_synced_at` (it's in the 011 set); `kb_sync_history` (jsonb on users, migration 017) — lean: move with repo, decide at deepen-plan.
3. Removed-member local-clone purge mechanism (TR7) — server-clone is controller-side; member-local copy out of technical control → T&C expectation-setting.
