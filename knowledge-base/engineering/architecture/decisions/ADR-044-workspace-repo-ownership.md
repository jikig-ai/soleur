---
adr: ADR-044
title: Relocate repo-connection state from users to workspaces; uniqueness guarantee moves from DB constraint to normalizeRepoUrl contract
status: adopting
date: 2026-05-28
amends: [ADR-038]
related_adrs: [ADR-038, ADR-023]
related: [4558, 4559, 4543, 5437]
related_plans:
  - knowledge-base/project/plans/2026-05-28-feat-workspace-repo-ownership-plan.md
  - knowledge-base/project/plans/2026-06-16-feat-adr-044-workspace-owned-connection-plan.md
related_specs:
  - knowledge-base/project/specs/feat-workspace-repo-ownership/spec.md
  - knowledge-base/project/specs/feat-adr-044-workspace-connection/spec.md
brand_survival_threshold: single-user incident
---

# ADR-044: Workspace repo ownership (amends ADR-038)

## Context

ADR-038 decoupled the workspace from `userId` (organizations + workspaces + workspace_members) but **deliberately left GitHub repo-connection state on `users`** — the 9-table workspace-keyed RLS sweep (migration 059) enumerated `conversations`, `messages`, `kb_share_links`, `push_subscriptions`, `concurrency_slots`, `audit_byok_use`, `dsar_export_jobs`, `scope_grants`, `multi_source_dedup`, and explicitly excluded the repo columns (`repo_url`, `repo_provider`, `github_installation_id`, `repo_status`, `repo_last_synced_at`, migration 011). At the time, repo connection was a per-user concern and no co-member shared a repo.

This produces a brand-survival defect (#4543): a user who **joins another user's workspace** cannot sync **that workspace's** repo, because every repo read keys on `auth.uid()` = the joiner's own `users.id`, which has no repo. The KB-sync path silently points at the joiner's (empty) repo. Band-aids #4546/#4557 were inert — they matched siblings by GitHub org/installation rather than fixing the ownership grain.

A second force: migration 052 enforces a **partial-UNIQUE index on `users.github_installation_id`**, which the GitHub webhook relies on to resolve `installation_id → founder` via `.maybeSingle()`. Moving the installation id to `workspaces` cannot carry that UNIQUE forward: two users may each legitimately connect the **same public repo/fork** to their own personal workspace, so a global UNIQUE on `workspaces.repo_url` would throw `23505` at the second user mid-connect. Webhook determinism must come from somewhere else.

Brand-survival threshold: **single-user incident** — the columns being relocated are credentials (`github_installation_id` is a GitHub App token grant) and the change spans cross-tenant repo access + a data backfill.

## Considered Options

- **Option A: Relocate repo state to `workspaces`; webhook determinism via fan-out reconcile + `normalizeRepoUrl` contract (chosen).** Add the 5 repo columns to `workspaces`; no global UNIQUE on `repo_url`. The push-reconcile fans out to **every** workspace matching `(github_installation_id, normalized repo_url)` — correct because a push to a shared repo legitimately affects all connected workspaces. Pros: fixes #4543 at the ownership grain; supports two-users-same-fork; reconcile semantics match real-world push fan-out. Cons: relocates the uniqueness *guarantee* from a DB constraint (compiler/DB-enforced) to the `normalizeRepoUrl` TS↔SQL parity *contract* (test-enforced) — the parity test becomes the sole load-bearing cross-tenant matching guard and therefore a hard merge gate.
- **Option B: Keep repo state on `users`, resolve the joiner→owner repo at read time.** A read-time fallback ("if the active workspace has no repo, read the owner's `users.repo_url`"). Pros: no schema change. Cons: re-introduces two-sources-of-truth divergence (`2026-05-27-workspace-dual-ownership-source-of-truth.md`); the joiner would read the owner's *credential* across a tenant boundary with no membership-scoped gate; does not generalize to N members.
- **Option C: Relocate to `workspaces` AND add a global UNIQUE on `repo_url`.** Pros: preserves a DB-enforced uniqueness guarantee; webhook keeps a `.maybeSingle()` resolve. Cons: breaks the legitimate two-users-same-fork case (second connect throws `23505`); conflates "this repo is connected once globally" (false) with "a push reconciles deterministically" (true via fan-out). Rejected.

## Decision

Adopt **Option A**. Move `repo_url`, `repo_provider`, `github_installation_id`, `repo_status`, `repo_last_synced_at` from `users` to `workspaces` (additive migration 079; idempotent solo-only backfill 080; TS read-cutover 081-equivalent; later decommission of the `users` columns + the 052 UNIQUE index after a prod soak). Repo reads come from `workspaces` **only** during and after soak — no `users` read-time fallback.

Three guarantees change grain:

1. **Uniqueness guarantee → `normalizeRepoUrl` contract.** No `UNIQUE` on `workspaces.repo_url`. Webhook/push determinism comes from **fan-out** over `(installation_id, normalize("https://github.com/" + repository.full_name))`. The TS (`lib/repo-url.ts`) ↔ SQL (migration 031) `normalizeRepoUrl` parity test is the **sole** matching contract and is a **hard merge gate**.
2. **Credential read → membership-scoped SECURITY DEFINER RPC.** Postgres RLS has no column scoping, so the existing row-level `workspaces_select_for_members` policy would expose `github_installation_id` (a token grant) to any member. Close it with a **column-level** `REVOKE SELECT (github_installation_id) ON public.workspaces FROM authenticated`; the value is readable only via the new `resolve_workspace_installation_id(p_workspace_id)` definer RPC (membership-checked, deny → returns NULL).
3. **Active-workspace context → `current_workspace_id` JWT claim.** Mirror the migration-060 `current_organization_id` pattern: add `current_workspace_id` to `user_session_state`, inject it via the single `runtime_jwt_mint_hook` slot (preserving the existing org-injection + OTP blocks verbatim), and write it via a membership-checked `set_current_workspace_id` RPC. `workspaceId` is **claim-derived at every call site — never from `req.body`/`req.query`** (IDOR). An `undefined` claim (un-refreshed session, or workspace deleted via `ON DELETE SET NULL`) defaults to the caller's solo workspace (`= users.id`), never an unscoped sibling.

## Consequences

- **Fixes #4543 durably.** Joined-workspace members sync that workspace's repo at the ownership grain, not via installation-id heuristics.
- **The `normalizeRepoUrl` TS↔SQL parity test is now load-bearing for cross-tenant correctness.** Before, a parity drift was a cosmetic backfill bug; now a drift makes the reconcile match zero (or wrong) workspaces. Mitigated by promoting the parity test to a hard merge gate (AC7) including bare-slug→URL fixtures — `repository.full_name` is a bare `owner/repo` slug and MUST be composed to `https://github.com/${full_name}` **before** normalizing, or the reconcile matches zero rows while a URL→URL test passes green.
- **Inngest payload is a versioned consumer boundary.** Adding `repository.full_name` to the reconcile event requires bumping `WORKSPACE_RECONCILE_SCHEMA_V` "1"→"2"; in-flight v=1 events drain to `{ok:false}` via the existing non-throwing mismatch branch rather than passing the gate with a missing field.
- **Rollback is not clean-by-revert while 079 is shipped.** Reverting only the read-cutover while the `current_workspace_id` claim still points a user at a joined workspace B induces the exact wrong-repo hazard (reads fall back to repo A, UI says B). Rollback MUST be all-or-nothing (revert schema + backfill + cutover together) OR include resetting every `user_session_state.current_workspace_id` to the user's solo workspace.
- **Pre-decommission drift gate.** A user who connects a repo between the 080 backfill and the read-cutover strands on `users`. Before dropping the `users` columns, `SELECT COUNT(*) FROM users u JOIN workspaces w ON w.id=u.id WHERE (u.repo_url IS NOT NULL AND w.repo_url IS DISTINCT FROM u.repo_url) OR (u.github_installation_id IS NOT NULL AND w.github_installation_id IS DISTINCT FROM u.github_installation_id)` MUST return 0 (re-backfill first). The gate covers `github_installation_id` as well as `repo_url` because the credential is the security-relevant divergence — a disconnect whose best-effort mirror failed (now fixed to fail closed, but the gate is the durable backstop) would leave a stale GitHub App grant on the workspaces-only read path.
- **Backfill is solo-only by construction + guarded.** The `w.id = u.id` join is solo-only (post-flag-flip workspaces use `gen_random_uuid()`), but a solo workspace that has since invited a co-member still has `w.id = u.id`; the backfill SKIPs (and `RAISE NOTICE`s) any workspace with member count > 1, so a repo is never landed onto a co-membered workspace without owner re-consent (CLO requirement).

### `github_installation_id` is workspace-repo-credential-based, not user-identity-based (settled 2026-05-28)

A GitHub App `installation_id` is fundamentally an **(account that owns the repo) → repo-access** grant — keyed to the repo's owning account, not to the Soleur user. The legacy `users.github_installation_id` scalar was a solo-era simplification that (a) cannot represent a user with installations across multiple accounts/orgs, (b) *caused* #4543 (a joined member's `users.github_installation_id` is null, so sync broke), and (c) duplicates a fact GitHub resolves on demand.

Decision: the credential lives on `workspaces` only. Retaining a parallel `users.github_installation_id` permanently would re-create exactly the dual-source-of-truth drift surface this ADR forbids for `repo_url` — so the user scalar is **not** a stable end-state. It survives only as a transient onboarding-discovery artifact during the soak (dual-written via `mirrorRepoColsToSoloWorkspace`, so it does not drift while it exists).

End-state (executed at the decommission migration — see tasks.md Phase 6):
- **Connect flow** resolves the installation from the repo, not a stored user scalar: `GET /repos/{owner}/{repo}/installation` (the connect routes already call the GitHub API, so this is near-free).
- **Onboarding "has the user connected GitHub?" gate** moves from `users.github_installation_id IS NOT NULL` to on-demand `GET /user/installations` (user token).
- The decommission migration drops `users.github_installation_id` + the migration-052 partial-UNIQUE index; the user scalar becomes vestigial.

Do not invest in making the user-level installation read permanent; fold the on-demand-GitHub-resolution swap into decommission rather than carrying the `users` column forward.

## Cost Impacts

None. No new vendor, tier, or infrastructure. Two additive migrations + a TS cutover on existing surfaces.

## NFR Impacts

- **NFR (tenant isolation / data confidentiality):** strengthens it — the credential column moves from row-level-RLS-exposed to membership-scoped-definer-RPC-only, and the pre-existing `.ilike("repo_url", …)` LIKE-injection fallback in `resolve-installation-id.ts` is deleted outright. No NFR tier in `nfr-register.md` regresses.

## Principle Alignment

- **AP — least privilege / membership-scoped access:** Aligned — credential read is gated behind a membership-checked definer RPC; column-level GRANT revoked from `authenticated`.
- **AP — single source of truth:** Aligned — reads come from `workspaces` only; no dual-ownership read-time fallback (the divergence trap from `2026-05-27-workspace-dual-ownership-source-of-truth.md` is explicitly rejected).
- **Deviation from ADR-038's "repo state stays on users" boundary:** Documented and justified here — the boundary was correct for solo-only repo connection and is invalidated by joined-workspace repo sync (#4543).

## Amendment 2026-06-17 — always-enforce-workspace (PR-1, #5437)

`status: active → adopting`. The original ADR cut over the repo **read** path to `workspaces` but left the dispatch resolver with a SILENT solo fallback (`resolveActiveWorkspaceIdWithMembership` returned `userId` on a non-member claim AND on a probe DB error, with zero Sentry). That produced the #5437 incident: two resolver paths diverged inside one `Promise.all` (`cc-dispatcher.ts`), so an invited member's clone landed in `/workspaces/<userId>` while repo+install resolved the team — the member was told to "reconnect your repository," an action they cannot perform, forever.

This amendment records the **always-enforce-workspace** invariant: every user owns a guaranteed 1-member personal workspace (the owner-membership canary, backfilled by mig 109 for any residual user); connection keys on the workspace; and the dispatch resolver (`resolveActiveWorkspace`) **fails closed to an explicit not-ready (`db-error`) state** and **resets a non-member claim to the user's OWN workspace, never to a `userId` solo sentinel that skipped the membership probe** (TR1). The only `ok` returns are a membership-verified team id or the caller's own `userId`.

`adopting` (not `active`) because the invariant **fully holds only after the PR-2 column drop**: PR-1 cuts the dispatch READ path to one membership-verified id and owner-gates the connect/disconnect routes (a no-op for solo by construction, once the canary holds), but connect-time WRITES still target `users.*` until PR-2 relocates them to `workspaces.*` and drops the legacy columns. C4: the connection edge is **read=Workspace / write=User (dual)** during `adopting`.

### Considered Options (amendment)

- **Option A2 (chosen): membership-verified resolve-once + explicit db-error + non-member-claim reset-to-solo.** One `resolveActiveWorkspace` per dispatch threaded into every consumer (path/repo/install/self-heal); a probe DB error returns `{ok:false,"db-error"}` (transient, never dispatched); a non-member claim resets to the user's own workspace with a deduped divergence breadcrumb. Pros: structurally cross-tenant-safe (TR1); makes the formerly-invisible divergence queryable; non-destructive (read-path only). Cons: forward-places the owner-gate (no-op until PR-2).
- **Option B2 (rejected): keep dual user/workspace keying with a silent solo fallback.** Retain the silent `resolveActiveWorkspaceIdWithMembership` (solo fallback on miss AND error, no Sentry). Rejected — **this is the #5437 incident**: the silent fallback masks a non-member claim as success, diverges the clone target from repo+install inside the same dispatch, and strands the member with no signal. A `MIN(created_at)`/first-membership fallback (the #4767 class) is rejected for the same reason: it can return a sibling tenant's workspace.

## Amendment 2026-06-17 — PR-2 splits into PR-2a (refusal guard) + PR-2b (drop), gated on the team write-cutover (#5462)

> **Correction 2026-06-17 (citation fix).** An earlier draft of this amendment
> cited **#4560** as the issue "delivering the team write-cutover" that PR-2b is
> blocked on. That was a mis-citation: **#4560 is journey-state UI polish**
> (J1/J2/J3/J7 — empty-workspace CTAs, mid-flight-switch prompts, failure copy,
> deferred from #4558) and will never relocate the connect-time writes. The team
> write-cutover (team on-disk provisioning + `users.*` → `workspaces.*` write
> relocation + `repo_error` re-key + co-membered backfill reconcile) was
> **untracked**; it is now filed as **#5462**. All "the write-cutover work"
> references below have been corrected #4560 → #5462. Genuine journey-state
> deferrals (the #4558 plan's J1/J2/J3/J7) correctly remain #4560.

`status` stays `adopting`. Implementing PR-2 surfaced that the plan's "additive
write relocation (`users.*` → `workspaces.*`, then drop)" is **not a decoupled
additive step** — it is structurally the **#5462 / Phase-5
team-workspace provisioning** effort. Evidence (verified in code, ruled on by the
`cto` agent):

- `app/api/repo/setup/route.ts` provisions the **solo** workspace on disk
  (`provisionWorkspaceWithRepo(user.id, …)` clones into `/workspaces/<user.id>`);
  relocating the write to an arbitrary team workspace id requires team on-disk
  provisioning — the #5462 work. The route comment is explicit: *"Team-invite
  repo-setup flows (Phase 5) will resolve the target workspace_id first."*
- The owner-gate's own invariant — *"`p_workspace_id` MUST equal the id the
  handler mutates"* — couples the gate change to the write relocation; one cannot
  land without the other.
- `repo_error` deliberately stays on `users` (read keyed on the dispatching
  user); `current-repo-url.ts` assigns the team-workspace `repo_error`
  relocation to #5462, and `workspaces.repo_error` is never written.
- The genuinely-additive pre-drop steps were **already shipped**: mig 079 added
  the `workspaces` repo columns AND the full credential protection
  (`REVOKE SELECT ON workspaces FROM authenticated` + re-GRANT excluding
  `github_installation_id` + `resolve_workspace_installation_id` reader RPC); PR-1
  cut the read path over.

**Decision — split PR-2:**

- **PR-2a (this PR, shipped):** the confused-deputy honesty fix. `repo/setup` +
  `repo/disconnect` resolve the active workspace server-side
  (`resolveCurrentWorkspaceId`, IDOR-safe) and return **422** when a TEAM
  workspace is active, instead of silently provisioning/disconnecting the
  caller's PERSONAL solo workspace. Strict no-op for solo
  (`activeWorkspaceId === user.id`). No `users.*` write change, no migration, no
  column drop. `Refs #5437` (closes nothing). C4 connection edge **unchanged**:
  still **read=Workspace / write=User (dual)** — PR-2a lands no write relocation.
- **PR-2b (deferred, the destructive drop):** drops `users.repo_url` /
  `workspace_path` / `github_installation_id` (+ the mig-052 partial-UNIQUE
  index), with the pre-decommission drift gate above. **Blocked on BOTH** (a)
  **#5462** delivering the team write-cutover so the `users.*` writes can stop,
  AND (b) the PR-1 `repo-resolver-divergence` breadcrumb showing zero divergence
  over a real prod soak window. At PR-2a authoring time the breadcrumb had **0
  events** because PR-1 had merged ~28 min earlier — *no soak yet*, not
  *proven clean*. `status: adopting → accepted` and the C4 edge → wholly-Workspace
  move with PR-2b (when the write side actually relocates), not PR-2a.

### Considered Options (amendment)

- **Option A3 (chosen): ship the thin refusal guard now (PR-2a), defer the drop to PR-2b/#5462.** Converts a live silent confused-deputy (team-active connect/disconnect targeting the personal solo workspace) into an honest 422, decoupled from #5462, forward-compatible (#5462 replaces the refusal with real team provisioning). Small, testable, no one-way-door.
- **Option B3 (rejected): fold #5462 into this PR and do the full write-cutover + drop now.** Large (team on-disk provisioning + gate/write co-relocation + `repo_error` re-key + co-membered backfill reconcile), couples the irreversible column drop to a large untested change, and discards the operator-confirmed soak deferral.
- **Option C3 (rejected): ship zero code, only re-sequence the issues.** Correct bookkeeping but leaves the silent confused-deputy live; the refusal is cheap and strictly improves correctness.

## Amendment 2026-06-17 — PR-2b prerequisite verification (soak baseline + drift-gate authority)

A `/soleur:go` PR-2b attempt on 2026-06-17 ran the prerequisite gates **before**
creating any migration and **halted** — neither precondition was met. Recorded
here so the next attempt starts from verified facts, not assumptions.

**Prereq (1) — team write-cutover merged + soaked: NOT MET (hard block).**
Connect-time writes on `main` still target `users.*`: `repo/setup/route.ts:213-214`
(`repo_url`, `github_installation_id`), `repo/setup/route.ts:257` (`workspace_path`),
`repo/install/route.ts:120` + `repo/detect-installation/route.ts:141`
(`github_installation_id`). The write-cutover (#5462) has not merged; dropping the
columns now would make every connect/install write throw — a single-user incident.

**Prereq (2) — PR-1 divergence zero-over-soak: baseline only, not yet a pass.**
Pulled from the Sentry issues API on 2026-06-17 (org `jikigai-eu`, project
`web-platform`, EU host, via the `SENTRY_ISSUE_RW_TOKEN` Doppler secret —
the alert-rule IaC `SENTRY_AUTH_TOKEN` lacks `event:read` and 403s on `/issues/`):

- `query=feature:repo-resolver-divergence` over the max `14d` window (spans the
  entire post-PR-1 period; PR-1/#5435 merged **2026-06-16 23:06 UTC**) →
  **0 matching issues**. Token read-capability confirmed by a control query
  returning real project issues. So the breadcrumb has fired **zero times** since
  the read-path cutover.
- **Caveat (do not mistake this for a pass):** 0 events over ~1 day with an
  **internal-only** user population is consistent with *both* "read path is clean"
  *and* "no team/member dispatch traffic exercised the path at all." Absence of the
  breadcrumb is weak evidence. The breadcrumb only fires on
  `non-member-claim-reset` / `self-heal-failed`, which require an actual joined
  member dispatching.

**Authoritative gate for an internal-only population.** Because the breadcrumb
soak is a *proxy*, with only internal users the calendar-soak requirement is
substitutable by **direct enumeration**: run the pre-decommission drift-gate query
(see Consequences §"Pre-decommission drift gate") against prod and require
`COUNT = 0`, plus synthetically exercise the member/team dispatch path. Treat the
drift-gate COUNT as authoritative and the breadcrumb as informational. This retires
the *calendar*-soak requirement for internal-only — it does **not** unblock PR-2b,
which still waits on the #5462 write-cutover (prereq 1) regardless of soak.

## Amendment 2026-06-17 — PR-2 write-cutover lands (#5462)

The connect-time **write** path is relocated `users.*` → `workspaces.*`. This is the
prereq-(1) the prior amendment recorded as the hard block on PR-2b.

`status` stays **`adopting`** (NOT `accepted`): the `adopting → accepted` flip lands
with PR-2b's destructive column drop after a real prod soak. This PR moves the write
edge but does not drop the legacy `users` columns (they survive as the revert net).

**C4 edge moves: `read=Workspace / write=User (dual)` → `read=Workspace /
write=Workspace`.** The four `app/api/repo/**` routes (`setup`, `disconnect`,
`install`, `detect-installation`) now write the authoritative repo-connection
columns to the `workspaces` row keyed on the **membership-verified resolved active
workspace id**; the owner-gate `p_workspace_id` equals that mutation-target id; team
on-disk provisioning + teardown (with live-member-session abort before the shared-dir
`rm`) replaces the PR-2a 422 refusal. `repo_error` was relocated by migration 110
(non-credential `authenticated` GRANT). The `users` columns are now **un-written
legacy** until PR-2b drops them.

### Read-cutover scope correction (the "read path is already cut over" claim was false)

The PR-1 amendment and the #5462 plan asserted the read path was fully on `workspaces`.
Implementing PR-2 surfaced FIVE+ surviving `users.{github_installation_id, repo_url,
repo_status}` readers. The binding ruling (engineering CTO):

- **Chosen (Option D): migrate the authenticated *interactive* readers in this PR,
  defer the *service-role* readers to PR-2b's blocker set.** Migrated here:
  `repo/status`, `repo/create`, `kb/tree`, `dashboard/today/[id]/undo`,
  `(auth)/callback`, and `repo/setup`'s degraded install-fallback — each now reads
  `workspaces` (via the `resolve_workspace_installation_id` RPC / `resolveInstallationId`
  for the credential, or a service-role `workspaces` read for the non-credential cols).
  Without this, a *newly-connected* user would strand on stale-NULL `users.*`
  (a `single-user incident`: broken GitHub-App git auth / "no repo connected" UI).
- **Rejected: migrate all readers in-PR (pure Option A)** — three readers are
  service-role/cron contexts where `resolve_workspace_installation_id` is structurally
  unusable (it gates on `auth.uid()` and is `REVOKE`'d from `service_role`, mig
  079:114/126); cutting them needs a *net-new* service-role-safe resolver, outside a
  write-cutover's blast radius.
- **Rejected: dark-launch flag (Option C)** — a write-relocation flag gates the wrong
  layer (the reads are the hazard); default-off leaves dual-writes live, which is
  Option B and re-blocks the PR-2b drift gate. Loud failure (`reportSilentFallback` /
  throw) + the whole-PR git-revert already satisfy the `single-user incident`
  threshold without a second drift surface (flag-state vs deploy-state).
- **Rejected: keep `users.*` dual-writes (Option B)** — re-introduces the
  dual-source-of-truth divergence ADR-044 forbids and makes the PR-2b drift gate
  unreachable.

**PR-2b (#5437) precondition set is amended:** PR-2b is blocked on the soak **AND** the
deferred service-role-context migrations, all tracked in **#5470** (PR-2b-blocker).
PR #5466 multi-agent review found these are **three** read sites + one write site, not
two — all service-role contexts where the `auth.uid()`-gated RPC is unusable:
- `server/inngest/functions/agent-on-spawn-requested.ts` — reads `users.github_installation_id`.
- `server/inngest/functions/cron-workspace-sync-health.ts` — reads `users.github_installation_id`.
- `app/api/webhooks/github/route.ts` — resolves `founderId` via `.eq("github_installation_id", …)`
  (a lookup, missed by the original `.select(…)` grep). They need a service-role-safe
  founder→workspace installation resolver (membership-bypass, trusted server context); the
  webhook additionally needs the fan-out reconcile because `workspaces.github_installation_id`
  is non-unique (ADR-044 fan-out).
- `server/session-sync.ts` `updateLastSynced` — writes `users.repo_last_synced_at`; PR #5466
  moved the `repo/status` read to `workspaces.repo_last_synced_at`, so the timestamp display
  freezes at connect time until this write relocates (needs `session-sync` on the
  service-role allowlist).

**Soak limitation (documented, accepted):** until #5470 lands, a user who connects via the
new workspaces-authoritative path during the soak does **not** get push auto-sync (the
webhook founder-resolver reads NULL `users.github_installation_id`) and shows a stale
last-synced timestamp. The soak population is internal-only, so this is an accepted
internal-dogfood limitation, consistent with the Option-D deferral logic (loud-failure +
revert-net for the interactive paths; the service-role paths fail in low-frequency
background contexts surfaced by the soak itself).

### Considered Options (amendment)

- **Option D (chosen):** above.
- **Capability gap recorded:** there is no service-role-safe installation-id resolver
  (the only one is `auth.uid()`-gated). It must be built before PR-2b can drop
  `users.github_installation_id`.

## Amendment 2026-06-17 — service-role-safe installation resolver (#5470, PR-2b precondition)

**The Option-D capability gap is now CLOSED.** `resolveInstallationIdForWorkspace(workspaceId, service)`
(`apps/web-platform/server/resolve-installation-id-for-workspace.ts`) does a **direct
service-role read** of `workspaces.github_installation_id` keyed on an explicit
`workspaceId`, with NO `auth.uid()` dependency — the distinct path service-role/cron
contexts need.

- **Mechanism chosen: direct service-role read, NOT a new RPC.** Migration 079 §2 (and
  mig 110) revoked the `github_installation_id` column SELECT from `authenticated`
  **only** — `service_role` retains its default `workspaces` table grant, so it reads the
  credential column today. A net-new SECURITY DEFINER RPC would add a privileged surface
  to audit for zero capability gain. The resolver takes an **injected** service client
  (mirrors `workspace-identity-resolver.ts`), so it imports no service-role factory and
  needs no `.service-role-allowlist` entry of its own.
- **Membership-bypass justification:** the credential is a GitHub App installation-token
  grant (repo write access). The bypass is sound ONLY because callers key on a
  **server-derived** id (`founderId` / the user's own solo workspace, `workspaces.id =
  users.id` per ADR-038 N2), never a request-supplied id. A single `eq("id", …)` read —
  no sibling discovery (CLO forbid: no unscoped membership scan, no `MIN(created_at)`
  first-membership lookup).

**Two of the three #5470 read sites are cut over in this PR:**

- `server/inngest/functions/agent-on-spawn-requested.ts` — `resolve-installation` step
  resolves the founder's solo-workspace install via the resolver (founderId keying
  preserved). Behavior-equivalent **for solo workspaces only** (`workspaces.id =
  users.id`, ADR-038 N2; backfilled by mig 080) — a team-workspace founder resolves
  NULL under BOTH the old `users` read and this solo read (the install lives on the
  team row), so agent-on-spawn remains solo-only exactly as before; broadening to
  active-workspace keying is out of scope (north-star).
- `server/inngest/functions/cron-workspace-sync-health.ts` — `scan-stale-sync-failed` +
  `scan-went-quiet` drop the `users.github_installation_id` select/predicate and resolve
  per-row from `workspaces`. The `users` read **stays** for `kb_sync_history` (users-only,
  mig 017; ADR-044 deliberately did not mirror history to workspaces). Newly-connected
  users (NULL legacy `users` install, populated `workspaces`) are now **caught** where the
  old `users` predicate false-negatively excluded them — a strict detection improvement.

`git grep 'users.*github_installation_id' apps/web-platform/server/inngest/` returns **0**.

**Remaining #5470 set — CLOSED (Amendment 2026-06-17b):**

- ~~`app/api/webhooks/github/route.ts`~~ — the reverse `.eq("github_installation_id", …)`
  founder lookup. **CLOSED:** relocated to a solo-workspace self-join resolver with a
  `>1` fail-closed branch (Amendment 2026-06-17b below).
- ~~`server/session-sync.ts` `updateLastSynced`~~ — the `users.repo_last_synced_at` write.
  **CLOSED:** relocated to `writeRepoColsToWorkspace` (service-role-injected) keyed on the
  caller's resolved active-workspace id (Amendment 2026-06-17b below).

With both sites relocated, **every** `users.github_installation_id` reader/writer and the
last `users.*` repo-column write are off `users`. PR-2b's `users.github_installation_id`
column DROP is now fully unblocked (the residual step is PR-2b itself).

## Amendment 2026-06-17b — webhook founder attribution + session-sync write (remaining set CLOSED)

Closes the two-site "Remaining #5470 set" above. Two surfaces relocated off `users`
in one branch as two reviewable commits (PR-A webhook, PR-B session-sync). Ref #5437.

**Verified fact:** the webhook Step 5 founder lookup was the SOLE remaining
`users.github_installation_id` **1:N reverse-lookup** (`.eq("github_installation_id", …)`).
The full reader sweep also surfaced a THIRD stranded reader the original framing missed —
`app/api/repo/detect-installation/route.ts` did a `users.select("github_installation_id")`
**self-read** (`.eq("id", user.id)`), a column-location cutover (not a 1:N lookup); it now
reads via `resolveInstallationIdForWorkspace(user.id, serviceClient)` (the solo workspace
carries the install, same value). `github_username` is NOT relocated by ADR-044 and stays a
`users` read.

### CTO binding ruling (transcribed verbatim) — Decision: Option C (hybrid)

- **Push stays exactly as-is.** The reconcile fan-out (`workspace-reconcile-on-push.ts`)
  re-derives workspaces from `(installation_id, repo_url)`, so the per-event founder lookup
  is unnecessary. The only push change: `founderId` must no longer be sourced from the
  deleted `users` read. **`founderId` is dropped from the `WORKSPACE_RECONCILE_REQUESTED`
  payload entirely** (vestigial — never destructured/read for routing) and
  `WORKSPACE_RECONCILE_SCHEMA_V` is bumped `2`→`3`. In-flight v=2 events deadletter via the
  consumer's non-throwing schema-gate; the next push re-drives (reconcile is idempotent by
  `(installation_id, repo_url)`).
- **Non-push events** (`pull_request`, `workflow_run` failure, `issues`,
  `repository_advisory`, `secret_scanning_alert` — all five `HEADER_TO_ACTION_CLASS`
  entries) resolve a **SINGLE** founder via the solo-workspace rule. Steps 6 (`isGranted`)
  and 7 (dispatch) remain single-decision, structurally unchanged. **Do NOT fan out
  Steps 6/7** (Option A rejected — fanning out grant-checks / N dispatches multiplies the
  consent + installation-token surface by N: the cross-tenant hazard).

**Non-push founder resolution rule** (replaces the Step 5 `users` read) — service-role read
on `workspaces` filtered to SOLO workspaces via the membership self-join:

```sql
SELECT w.id
FROM workspaces w
JOIN workspace_members m
  ON m.workspace_id = w.id
 AND m.user_id      = w.id        -- solo invariant: member.user_id == workspace.id (ADR-038 N2)
 AND m.role         = 'owner'
WHERE w.github_installation_id = :installationId
```

`founderId := w.id` (== owner `users.id` by the invariant, so value-compatible with the old
`users` read; `isGranted` + the installation-token path need no other change). There is no
`is_solo` column — solo identity is structural; the `m.user_id = w.id` join is the only sound
discriminator and deliberately excludes team workspaces sharing the install (a team `id` is a
fresh uuid, never == a member's user_id).

**Fail-closed by match count** (implemented as the `resolveSoloFounderForInstallation`
discriminated union `{found|none|ambiguous|db-error}`):
- **0 rows** → `logger.warn` + `releaseDedupRow()` + **404** (GitHub does not retry 4xx).
- **1 row** → proceed to Step 6 with `founderId = w.id`.
- **>1 rows** (two users + same fork — genuinely reachable now the column is NON-UNIQUE) →
  **fail closed: do NOT pick one. `Sentry.captureException` (tag `op:"founder-ambiguous"`,
  level error) + `releaseDedupRow()` + 404-drop. ZERO `inngest.send`, ZERO `isGranted`.**
  Dropping a re-drivable event is strictly safer than misattributing it (an unrecoverable
  cross-tenant action/repo-write). This is the single most important new code path.
- **DB error** → `Sentry.captureException` (`op:"founder-resolve"`) + `releaseDedupRow()` +
  **500** (preserves the existing Step 5 `founderErr` contract — never a silent 200).

**Test invariants:** the `>1` fail-closed (Test Scenario 3) is mandatory; the solo self-join
excludes team workspaces (Scenario 4); same-user double-solo-row drift trips ambiguous
(Scenario 11); the resolver covers all five action classes (Scenario 12).

**Structural-guarantee note (R7):** the dropped mig-052 partial-UNIQUE on
`users.github_installation_id` has **NO structural replacement** on `workspaces` (the
"one solo workspace per installation" invariant is now enforced **nowhere structurally** —
only by the connect path + this PR's **runtime `>1` fail-closed**). A connect bug or
co-member reconcile (mig 110) that duplicates an install onto a second solo row would make
every non-push event for that install 404-drop until the duplicate is removed operationally
— a STANDING single-user availability incident (R8), so `op:"founder-ambiguous"` must
**page**, not just log. A cross-table partial-index predicate is not directly expressible;
the accepted posture is the runtime branch + the paging Sentry signal.

### Session-sync write (PR-B)

`updateLastSynced` signature changed to `updateLastSynced(service, workspaceId)`; it writes
`workspaces.repo_last_synced_at` via the **service-role-injected** `writeRepoColsToWorkspace`
(`workspaces` has exactly one RLS policy — `workspaces_select_for_members`, SELECT only;
there is NO `GRANT UPDATE` and NO UPDATE policy, so a tenant UPDATE is impossible). The
service client is **injected by the allowlisted caller** (`agent-runner.ts`); `session-sync.ts`
does NOT acquire service-role and stays OFF `.service-role-allowlist`, mirroring the in-file
`appendKbSyncRowForWorkspace` precedent. `agent-runner.ts` resolves `resolveActiveWorkspace`
ONCE (resolve-id-first) and threads the SAME id into BOTH `resolveActiveWorkspacePath(…, id)`
and `updateLastSynced(service, id)` — the explicit #5435 dual-resolver-divergence fix
(session-sync NEVER re-resolves). A `{ok:false,reason:"db-error"}` on the membership probe
fails closed (skip sync). Test Scenario 10 (team-active member's write lands on the TEAM
workspace, never `userId`) is the load-bearing write-side invariant.

### C4 edge note

The connection-owner edges for the webhook reverse-lookup and the session-sync repo-column
write are now **workspace-sourced** (read=Workspace / write=Workspace for these edges). No
`.c4` model file references an ADR-044 view (grep of `knowledge-base/**/*.c4` is empty), so
this edge change is captured in this ADR prose rather than a `.c4` edit.

### Sequencing

The edges are workspace-sourced as of this branch. The column DROP invariant fully holds
only after PR-2b (the residual step); `Ref #5437` keeps the umbrella open.
