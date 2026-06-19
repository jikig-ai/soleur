---
adr: ADR-044
title: Relocate repo-connection state from users to workspaces; uniqueness guarantee moves from DB constraint to normalizeRepoUrl contract
status: accepted
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
The full reader sweep surfaced TWO more stranded readers the original framing missed,
bringing the relocated set to **FOUR** sites:
- **3rd** — `app/api/repo/detect-installation/route.ts` did a
  `users.select("github_installation_id")` **self-read** (`.eq("id", user.id)`), a
  column-location cutover (not a 1:N lookup); it now reads via
  `resolveInstallationIdForWorkspace(user.id, serviceClient)` (the solo workspace carries the
  install, same value).
- **4th** — `app/(dashboard)/dashboard/settings/page.tsx` read
  `users.select("repo_url, repo_status, repo_last_synced_at, github_installation_id")` in a
  **multi-line** select (which the AC grep missed) on the settings render. Since PR-2
  relocated the WRITES to `workspaces`, this `users` read served stale/frozen values, and
  PR-2b's column DROP would throw on every settings render. **CLOSED:** it now resolves the
  active workspace via `resolveActiveWorkspace(user.id, service)` and reads the repo cols
  from `workspaces` (mirrors `app/api/repo/status/route.ts`); a resolve `db-error` fails
  closed to "not connected" so the page still renders. The `users` read is removed entirely
  (no non-repo field was used).

`github_username` is NOT relocated by ADR-044 and stays a `users` read.

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
- **DB error** → the **resolver** mirrors the real Postgres error via
  `reportSilentFallback` (`feature:"github-webhook"`, `op:"founder-resolve"`); the route then
  `releaseDedupRow()` + **500** (preserves the Step 5 `founderErr` contract — never a silent
  200). The route does **not** re-`captureException` a synthetic Error on this branch — that
  would double-report one failure under the same op (one report per failure).

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
the accepted posture is the runtime branch + the paging Sentry signal. **R8 paging is now
WIRED** (no longer aspirational): the `github_webhook_founder_ambiguous` Sentry issue-alert
rule (`infra/sentry/issue-alerts.tf`) is `filter_match="all"` on BOTH `feature=github-webhook`
AND `op=founder-ambiguous` tags, so it pages specifically on this standing-state ambiguity
(NOT the routine no-founder 404 or the db-error mirror). Before this rule the HTTP monitor
treated the 404 as expected and no `github-webhook` Sentry rule existed.

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

## Amendment 2026-06-18 — PR-2b column DROP (arc CLOSED)

**Status flip:** `adopting → accepted`. This is the FINAL, irreversible step of the
ADR-044 arc. The repo-connection ownership boundary has fully moved
`users → workspaces`.

**Drop migration:** `112_drop_legacy_users_repo_columns.sql` (+ `.down.sql` +
`verify/112_…sql`). It drops the dead partial-UNIQUE index
`users_github_installation_id_unique_idx` (mig 052), then
`DROP COLUMN github_installation_id, repo_url, workspace_path` from `public.users`.
`public.workspaces` is untouched (the cutover TARGET). The `.down.sql` is a
**SCHEMA-ONLY** rollback — the dropped column DATA is NOT recoverable; the
canonical copy lives on `workspaces.*`.

**Pre-drop safety gates (verified 2026-06-18, work-start, against `origin/main` /
PROD):**
- **Drift gate COUNT = 0 against PROD** (read-only, `DATABASE_URL_POOLER`):
  `SELECT count(*) FROM users u JOIN workspaces w ON w.id=u.id WHERE
  u.repo_url IS DISTINCT FROM w.repo_url OR u.github_installation_id IS DISTINCT
  FROM w.github_installation_id` = 0. Context: 16 users / 18 workspaces;
  `repo_url_drift=0`, `install_drift=0`, `total_drift=0`. Nothing unique is
  destroyed — `users.*` and `workspaces.*` are consistent.
- **Reader sweep = 0 live readers.** The multi-line `from("users") … (the three
  columns)` sweep and the dual-shape `.eq()/.in()/.match()` sweep over
  `apps/web-platform/{app,server,lib}` return only comments, different-column
  selects (`email`/`health_snapshot`/`github_username`/`workspace_status`),
  `workspaces`/`conversations` queries, and synthesized-object reads. Zero live
  `users`-table reads/filters of `github_installation_id`, `repo_url`, or
  `workspace_path`.

**Cross-tenant guarantee carried, not lost.** The dropped index's structural
guarantee (one founder per installation) is permanently replaced at runtime by
the `resolveSoloFounderForInstallation` `{found|none|ambiguous|db-error}` resolver
(`>1` fail-closed, `server/resolve-founder-for-installation.ts`) + the
`github_webhook_founder_ambiguous` Sentry paging rule
(`apps/web-platform/infra/sentry/issue-alerts.tf:576`, `op="founder-ambiguous"`),
both adopted in Amendment 2026-06-17b (R7/R8) and verified live here. The
load-bearing post-drop signal is that paging rule (verify/112 only proves the
index is GONE, not that its replacement FIRES).

**C4:** No `.c4` model edit — the connection-owner relationship is not modeled at
column granularity, and the workspace-sourced edge is already recorded in the
prose above (grep of `knowledge-base/**/*.c4` for the dropped identifiers is
empty). No-op recorded here so a future reader is not misled.

**The ADR-044 arc is COMPLETE.** No further slice is gated. Note: `users.{repo_provider, repo_status, repo_last_synced_at}` remain as dead-but-retained columns intentionally OUTSIDE PR-2b's named drop set (a future minor cleanup), so "arc complete" refers to the ADR-044 decision arc, not zero-residual-columns.

## Amendment 2026-06-18 — non-push founder resolution MUST be repo-scoped (multi-repo-org false-ambiguity fix)

This **amends Amendment 2026-06-17b's** "Non-push founder resolution rule" (the
subsection above that defined `resolveSoloFounderForInstallation` and its
`{found|none|ambiguous|db-error}` discriminated union). It is an **amendment to
Decision.1's own contract, NOT a reversal** — it completes the same
`(installation_id, normalizeRepoUrl(repo_url))` fan-out key that Decision.1 made
load-bearing for the push path, and that the push reconcile
(`workspace-reconcile-on-push.ts`) already keys on.

**The false assumption.** The 2026-06-17b resolver SELECT keyed the solo
self-join ONLY on `w.github_installation_id = :installationId`, with NO
`repo_url` filter. That implicitly assumed **"one solo workspace per
installation"** — exactly the assumption Decision.1 **explicitly rejected** for
the push path (`workspaces.github_installation_id` is intentionally NON-UNIQUE;
a single GitHub-App installation legitimately spans MANY repos across an org,
each with its own solo workspace). For a multi-repo org install the unscoped
self-join returns `>1` solo rows → `{kind:"ambiguous"}` → `route.ts`
`Sentry.captureException(op:"founder-ambiguous")` + 404-drop, for **every**
non-push event under that install (`pull_request`, `workflow_run`, `issues`,
`repository_advisory`, `secret_scanning_alert`, AND unmapped events such as
`check_suite` that reach the resolver BEFORE the `actionClass` guard). Confirmed
in prod via Sentry `WEB-PLATFORM-3M` (install `122213433`).

**The rule (amended).** Non-push founder resolution MUST also be scoped by
`(installation_id, normalizeRepoUrl(repo_url))` — composing
`https://github.com/<repository.full_name>` and normalizing it **exactly like
the push reconcile** (compose-before-normalize; the bare `owner/repo` slug must
become a full URL before `normalizeRepoUrl`, per the Consequences note above).
The route composes the normalized `targetRepoUrl` and passes it to the resolver;
the SELECT gains `.eq("repo_url", :normalizedRepoUrl)` alongside
`.eq("github_installation_id", :installationId)`. The TS↔SQL `normalizeRepoUrl`
parity test remains the sole load-bearing matching guard (the same hard merge
gate Decision.1 established) — the non-push path now shares it.

**What is UNCHANGED.** `founderId := w.id` (== owner `users.id` by the solo
invariant) is unchanged; `isGranted` and the installation-token path need no
other change. The **SINGLE-founder, no-fan-out** posture for Steps 6/7 (the
2026-06-17b CTO ruling rejecting Option A's N-way grant-check/dispatch fan-out
as a cross-tenant consent + installation-token surface multiplier) is
**UNCHANGED** — repo-scoping resolves exactly ONE founder per `(install, repo)`
in the normal case; it does not fan out. The `>1` fail-closed branch
(`Sentry.captureException(op:"founder-ambiguous")` + `releaseDedupRow()` + 404,
ZERO `inngest.send`, ZERO `isGranted`) is **retained** but now fires ONLY for
the genuine same-repo + same-install residual ambiguity (two users + same fork);
the multi-repo-org false-ambiguity it previously caught disappears. The `none`
(0-row → 404), `db-error` (resolver `reportSilentFallback` op:`founder-resolve`
→ route 500, re-drivable), and R8 paging-rule (`github_webhook_founder_ambiguous`,
`op="founder-ambiguous"`) contracts are unchanged. Misattributing a non-push
event to the WRONG repo's founder (routing one tenant's PR/CI/issue draft + an
installation token to another founder) is a cross-tenant action-attribution
leak; the repo_url filter (with the parity-test-guaranteed normalization) and
the retained `>1` fail-closed branch are the backstops — dropping a re-drivable
event is strictly safer than misattributing it.

### Consequence — dispatch readiness MUST be (repo_status-ok AND physical `.git` present); ready-but-`.git`-gone re-clones lock-free (Bug 2)

A second multi-workspace-per-installation defect on the dispatch side: the cold
Concierge dispatch fast-pathed on `repo_status` alone, returning `{ok:true}` for
a `repo_status='ready'` workspace WITHOUT verifying the clone physically exists
on disk. A shared/team workspace whose row is `ready` (set by share/connect or a
session-sync stamping) but whose `/workspaces/<id>/.git` is absent (never
materialized at the member-session path) lands the interactive session where
`git rev-parse --is-inside-work-tree` is false — persisting across retries (each
retry re-takes the `ready` fast-path) with NO Sentry signal (the `ready` path
never reached the `op:"repo-readiness-self-heal"` mirror).

**Consequence (decided here):** dispatch readiness is the **conjunction** of
`repo_status != cloning/error` **AND** physical `.git` presence at the resolved
workspace path. A `ready`-but-`.git`-absent workspace is a recoverable condition
that is **deterministically re-cloned**:

- **Recovery policy is SPLIT by DB state.** `error` / stale-`cloning` rows KEEP
  the `claim_repo_clone_lock` RPC (migration 108) — the load-bearing
  thundering-herd guard. The `claim_repo_clone_lock` WHERE clause matches ONLY
  `error`/stale-`cloning` rows **by construction**, so it cannot acquire a
  `ready` row; the `ready`-but-`.git`-absent re-clone is therefore **lock-free**
  and relies on the graft's per-attempt `randomUUID` temp dir + atomic rename +
  `.git`-sentinel re-check (`ensure-workspace-repo.ts`) for concurrency
  correctness (winner materializes `.git`; the loser observes it and returns
  `{ok:true}` with `.git` present, or honest-waits — it never fast-paths
  `{ok:true}` with `.git` still absent).
- **Hot-path preserved.** The COMMON `ready` + `.git`-present path still
  fast-returns `{ok:true}` — the only added cost is a local `existsSync`; the
  `existsSync` is evaluated FIRST so `getFreshTenantClient` (a JWT round-trip)
  stays OFF the fast path. On the `ready`-entry SUCCESS branch the
  `setRepoStatus(ready)` write is SKIPPED (the row is already `ready`; the write
  would be a no-op + a spurious member-row write + an RPC round-trip of no value).
- **Member split-write re-targeted (migration 113).** `set_repo_status`
  previously wrote the failure reason to `users.repo_error` for `auth.uid()` (the
  caller = the member), but the readiness gate reads the OWNER's reason — so a
  member-triggered heal FAILURE wrote the member's row while the gate re-read the
  owner's (null/stale) row, looping the member forever with no honest reason.
  Migration 113 **re-targets `set_repo_status`'s failure-reason write from the
  dropped `users.repo_error` to `workspaces.repo_error`** — the column the gate
  reads as of migration 110 — so a member-triggered heal failure surfaces the
  correct reason instead of looping. (SECURITY DEFINER, `search_path = public,
  pg_temp`, REVOKE/GRANT precedent per migration 108; the membership check is
  retained.)

### C4 edge note

No `.c4` model edit. C4 enumeration for this change (all already covered or
below the model's system/container granularity):
- **Actors:** GitHub (webhook sender) is modeled as the `github` `#external`
  system; the workspace Owner and the shared-workspace **Member** are both
  covered by the existing `founder` actor, whose description already states
  "A workspace Owner ... Workspaces may have MULTIPLE Owners (ADR-038 team
  workspaces)" — it is NOT a "Solo founder"-only description, so the multi-member
  shared-workspace clone path does not falsify it (no edit needed).
- **External systems:** GitHub App (installation-token clone) is subsumed by the
  `github` external system — no new vendor.
- **Stores:** the `/workspaces` persistent volume and the
  `workspaces.repo_status` / `workspaces.repo_error` columns are below the
  model's granularity (the model stops at the `supabase` database element).
- **Edges:** the non-push webhook→founder edge (now keyed on
  `(installation, repo)`) and the dispatch-clone Member→Workspace-repo edge are
  connection-owner relationships at column/code granularity — consistent with
  the 2026-06-17b and 2026-06-18 amendments above, these are captured in this
  ADR prose, not in a `.c4` edit (grep of `knowledge-base/**/*.c4` for ADR-044 /
  the relevant identifiers is empty). **No C4 impact.**

## Amendment 2026-06-18 — dispatch readiness must distinguish membership-deny NULL install from not-connected

**Lineage:** this is a **consequence-level extension** of the prior
2026-06-18 subsection
*"Consequence — dispatch readiness MUST be (repo_status-ok AND physical `.git`
present); ready-but-`.git`-gone re-clones lock-free (Bug 2)"* (above). That
subsection made dispatch readiness the conjunction of `repo_status`-ok **AND**
physical `.git` presence. This amendment extends the same dispatch-readiness
theme from *"`.git` presence"* to *"credential-read divergence"*: a third
multi-workspace-per-installation defect, now on the dispatch **READ** path.

**Defect.** A member cold-dispatch into a genuinely-connected shared/team
workspace can spawn a **repo-less agent** even after the Bug-2 graft shipped. The
agent **was** spawned (it ran `/soleur:go` Step 0.0 and reported "no git
repository", `git rev-parse` exit 128), which proves the gate
(`resolveRepoReadinessWithSelfHeal`) returned `{ok:true}` **without the graft
running**. Root cause is a **two-read asymmetry** against the post-ADR-044 source
of truth:

- `repo_url` / `repo_status` are **non-credential** columns read via a **direct,
  RLS-gated `.select()`** (`current-repo-url.ts`) — a member **can** read them
  non-null.
- `installationId` (`workspaces.github_installation_id`) is the **credential**
  column, REVOKED from `authenticated`, read **only** via the
  `resolve_workspace_installation_id` **SECURITY DEFINER RPC**, whose mig-079
  comment is explicit: *"Returns NULL for non-members … deny is indistinguishable
  from 'not connected'."*

So a member of a connected team workspace can read `repo_url` (RLS pass) while
the install RPC returns NULL (membership-deny / transient blip) → `hasConnection`
false → the fast path returns `{ok:true}` and the graft is silently skipped
(`repo-readiness-self-heal.ts:128,134-140`); the fire-and-forget
`ensureWorkspaceRepoCloned` then no-ops on the null install → the agent spawns
repo-less, with **no Sentry signal** at the dispatch path.

**Decision (decided here).** At the Concierge dispatch readiness gate, a
`decision.ok` + `.git`-absent workspace with **`repoUrl` present but
`installationId` null** is a **resolver divergence**, NOT "not connected".
`repoUrl` (a non-credential, RLS-readable column) is the honest signal that a
connection *exists*; a null install against a present `repoUrl` means the
*credential read denied*, not that the repo is absent. The gate:

- **fails honestly** — returns an honest `RepoNotReadyError`
  (`repo_setup_failed`) with a **membership-deny-aware** message ("we couldn't
  verify your access to this repository. If you recently joined this workspace,
  ask the workspace owner to confirm the connection") instead of the unactionable
  "reconnect" CTA — and is **NEVER** fast-pathed into a repo-less agent spawn;
- emits a **paging** `repo_resolver_divergence` Sentry op
  (`op:connected-null-install-at-dispatch`, the only durable record) — closing
  the dark dispatch path (the existing `op:ready-null-installation` lives only in
  the daily CRON `cron-workspace-sync-health.ts`, a periodic backstop, not the
  synchronous dispatch signal);
- performs **ZERO `workspaces` writes** — it does **NOT** persist
  `repo_status=error`.

**The zero-write rule is load-bearing (the single most important deviation from
the `failHonestly` precedent).** `failHonestly` persists `error` because it
observed a *real, attempted clone that failed*; the divergence path attempted
**nothing** (it has no install to clone with). Persisting `error` on the
**shared `workspaces` row** here is a category error with two failure modes:
(1) **cross-tenant corruption** — a removed/transient member whose
`set_repo_status` membership check passes would flip a **healthy team workspace
to `error` for every legitimate Owner**; (2) **sticky transient** —
`installationId` is null on *any* RPC blip and `getCurrentRepoStatus` is
deliberately fail-open, so writing `error` converts a self-recovering transient
into a sticky failure. A transient blip therefore self-recovers on the next
dispatch (install resolves non-null → graft path).

### Considered Options (amendment)

- **Widen `resolve_workspace_installation_id` to return the install on
  membership-deny** — **REJECTED.** Re-opens the exact credential-leakage surface
  the RPC's deny-NULL gate closes (mig 079): it would expose
  `workspaces.github_installation_id` (a GitHub App token grant) to non-members.
  The NULL ambiguity is inherent to a membership-gated secret and MUST be
  disambiguated by the **caller** using the non-credential `repoUrl`/`repo_status`
  signals, never by widening the credential read.
- **Persist `repo_status=error` on the divergence path (mirror `failHonestly`)**
  — **REJECTED.** Cross-tenant corruption + sticky-transient (see the zero-write
  rule above). The Sentry op is the only durable record.

### C4 edge note

No `.c4` model edit. The affected member is a workspace Owner (already covered by
the `founder` actor's multi-Owner ADR-038 description); the install RPC read
(`api -> supabase`) and the clone edge (`engine -> github`) are already modeled;
the fix changes the *condition* on the existing `api -> claude "Spawns agent
sessions"` edge (block-vs-spawn), not the topology. Grep of
`knowledge-base/**/*.c4` for the relevant identifiers is empty. **No C4 impact.**

### Sequencing

Behavioral correction shipped in the same PR (no soak gate; not a destructive
migration; no schema change — the credential RPC is unmodified and no new
migration is added).

## Amendment 2026-06-19 — dispatch readiness is on-disk worktree VALIDITY (not mere `.git` presence)

**Lineage:** extends the 2026-06-18 *"dispatch readiness must be (repo_status-ok
AND physical `.git` present)"* consequence (the Bug-2 graft) and its
2026-06-18 *"distinguish membership-deny NULL install from not-connected"*
sibling. Same dispatch-readiness theme, tightening the final clause from
*"physical `.git` present"* to *"**valid** git work tree"*.

**Defect (third distinct gap).** A cold Concierge dispatch into a
FULLY-connected workspace (install NON-null, `repoUrl` present, `repo_status`
`ready`) whose on-disk `<ws>/.git` EXISTS but is **not a valid work tree**
(a partial/interrupted clone, or a leftover from a failed atomic-rename) was
fast-pathed by the presence-only `existsSync(<ws>/.git)` gate at three sites
(`cc-dispatcher.ts` `needsSelfHeal`, the `gitDirExists` self-heal seam, and
`ensure-workspace-repo.ts`'s `.git`-present early-return). Self-heal was skipped
entirely, no clone was attempted, no error was set, **no Sentry signal** was
emitted, and the agent spawned into a corrupt repo — `/soleur:go` Step 0.0's
`git rev-parse --is-inside-work-tree` then reported "no git repository". Verified
live: operator `52af49c2…`, active workspace `754ee124…`, both connected,
`repo_error` null, zero divergence/self-heal Sentry events in 24h. Distinct from
both prior 2026-06-18 fixes (install resolves NON-null; `.git` is NOT cleanly
absent).

**Decision (decided here).** Dispatch readiness = `repo_status`-ok **AND on-disk
worktree VALIDITY**. The gate keys on a SYNCHRONOUS structural validity proxy
(`isValidGitWorkTree`: `.git` is a FILE gitdir pointer → valid; or a directory
with both `HEAD` and `objects` → valid; else invalid) — deliberately WEAKER than
`git rev-parse --is-inside-work-tree` but cheap enough to keep the AC7 zero-await
hot path (a valid `.git` touches no DB/JWT). A corrupt `.git` routes to a
corrupt-worktree graft that:

- removes the corrupt `.git` **only on a POSITIVE empty-corrupt fingerprint**
  (`isEmptyCorruptGitDir`: `.git` is a directory AND `HEAD` ENOENT AND `objects`
  ENOENT — no objects ⇒ no commits to lose), **never** on the negation of the
  validity probe (an EACCES/EIO blip or a `.git` FILE must not be destroyed);
- runs the rm+reclone **serialized under `withWorkspacePermissionLock`** (the rm
  is a second `.git` writer the graft sentinel never guarded);
- on a populated-but-broken / EACCES / gitdir-FILE `.git`, **honest-blocks**
  (never destroys) rather than removing;
- emits a new `repo_resolver_divergence` op `corrupt-worktree-at-dispatch`
  carrying `extra.recovered` (true = self-healed re-clone; false = unrecovered
  honest-block), routed through the existing feature-only paging alert (NO
  Terraform change);
- on recovery FAILURE performs **ZERO `workspaces` writes** (no `setRepoStatus`)
  — a removed/transient MEMBER dispatching into a corrupt TEAM workspace must not
  flip its `repo_status` to `error` for the Owners (the same hazard the
  membership-deny-NULL amendment's `failConnectionUnresolved` avoids).

A Start-Fresh `git init` tree (HEAD+objects, no origin) is VALID → preserved,
never re-cloned. `/soleur:go` Step 0.0 still runs the authoritative `rev-parse`.

### Considered Options (amendment)

- *Invert the single `gitDirExists` seam to "valid" everywhere* — **REJECTED**:
  the null-install divergence gates require TRUE ABSENCE; inverting them would
  mis-route a corrupt-`.git` + null-install workspace to
  `connected-null-install-at-dispatch` (wrong op, no removal). The presence seam
  is kept for those gates; validity is a SEPARATE seam.
- *Trigger the rm on the negation of the validity probe* — **REJECTED**:
  `existsSync`/`stat` collapse ENOENT with EACCES/EIO, so a transient unreadable
  populated `.git` (or a gitdir-FILE worktree) would be destroyed, losing
  un-pushed commits. The rm is authorized ONLY by the positive empty-corrupt
  fingerprint.
- *Run `git rev-parse` on the hot path for full validity* — **REJECTED**: adds a
  subprocess to the common valid-`.git` dispatch (AC7 regression). The structural
  proxy is the hot-path gate; `rev-parse` is reserved as an off-hot-path recovery
  discriminator. Residual: a fully-populated-but-internally-broken `.git` that
  passes the structural proxy is not auto-recovered (rare; honest Step-0.0 error
  + operator reconnect).

### C4 edge note

**No `.c4` model edit.** Same enumeration as the 2026-06-18 amendments: GitHub is
the `github` `#external` system (clone source); the affected member is a
workspace Owner already covered by the multi-Owner `founder` actor; the
`/workspaces` volume and `workspaces.repo_status`/`repo_error` are below the
`supabase`-element granularity. The corrupt-worktree path tightens the on-disk
validity semantics of an already-modeled dispatch edge (block-vs-spawn-vs-reclone)
and adds no actor, system, store, or access relationship. Grep of
`knowledge-base/**/*.c4` for the relevant identifiers is empty. **No C4 impact.**

### Sequencing

Single atomic PR — TS-only, no migration, no Terraform change (the feature-only
Sentry alert auto-covers the new op). Behavioral correction; no soak gate.
