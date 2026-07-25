---
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

### Amendment 2026-06-30 (#5733) — the in-process dispatch clone is the authoritative same-FS lander; absent/dir-invalid + empty-output are strands

A third multi-workspace defect on the same dispatch surface: a connected
workspace (`754ee124`) whose `/workspaces/<id>/.git` is **ABSENT** stranded
`/soleur:go` Step 0.0 while emitting ZERO server-side signal — every prior
re-clone mechanism (push-reconcile, `/api/repo/setup` reconnect) failed to land
the repo, and the cold dispatch path's existing in-process clone outcome was
**silently discarded**. Decided here:

- **The authoritative lander is the IN-PROCESS dispatch-time clone.** The repo
  re-clone the agent depends on MUST run in the SAME process that constructs the
  agent sandbox (the cc-dispatcher cold path, `ensureWorkspaceRepoCloned` into the
  agent's own `workspacePath` — the one placement guaranteed to share the agent's
  bwrap filesystem), keyed on the **workspace's OWN `github_installation_id`**
  (never the dispatching user's membership-resolved install, never founder/owner
  resolution — the #5591 owner-canary drift makes founder resolution unusable).
  Out-of-process re-clones (Inngest reconcile, cron) are best-effort backstops
  only; they are NOT guaranteed to share the agent's filesystem (an open
  FS/mount-divergence question for multi-replica `/workspaces` — tracked for a
  same-container periodic backstop if confirmed).
- **The clone outcome must be consumed LOUDLY, never swallowed.** On a `"failed"`
  clone a distinct, paging `repo_clone_failed` Sentry event fires with the
  git-token-redacted + path/url-sanitized reason (ADR-029 pseudonymization), and
  the dispatch honest-blocks. The `repo_status→error` write is **F4-gated**: only
  on the solo/owner path (`workspaceId===userId`) AND after a post-clone
  `.git`-absence CAS (a member must not flip a co-owned workspace's shared status;
  a concurrent winner's fresh `ready` must never be clobbered). The pre-existing
  `graftReadyButGitAbsent` failure write is gated identically (matching the
  corrupt sibling's emit-only team posture). cc-dispatcher stays OFF the
  service-role allowlist (no new column read).
- **The DB `repo_status` is NOT authoritative over on-disk reality.** The shared
  dispatch gate (`evaluateAgentReadiness`) treats `absent`/`dir-invalid` `.git` as
  a confirmed terminal strand on the **post-heal** surface (cold/warm) →
  honest-block + `agent_readiness_self_stop`; on the **pre-heal** surface
  (reconcile, which re-clones the same shape one line later) it does NOT emit
  (soak-signal guard). The agent's in-sandbox Step 0.0 `git rev-parse … 2>/dev/null
  || true` EMPTY output is also a strand signal (the C2 in-sandbox backstop).

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
  proxy is the hot-path gate; no off-hot-path `rev-parse` recovery probe ships. A
  fully-populated-but-internally-broken `.git` that passes the structural proxy is
  honest-blocked STRUCTURALLY — it is never auto-recovered (it has objects, so the
  empty-corrupt fingerprint never authorizes an `rm`) and never silently destroyed
  (rare; honest Step-0.0 error + operator reconnect).

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

## Amendment 2026-06-22 — PR-3: extend resolve-once-and-thread to the per-dispatch reprovision resolver

PR-1's always-enforce-workspace invariant was applied in the **cold dispatch
factory** (`cc-dispatcher.ts realSdkQueryFactory:1536`): resolve the active
workspace ONCE via the membership-verified `resolveActiveWorkspace` and thread the
single id into every consumer (path/repo/install/self-heal). PR-3 records that the
SAME invariant was **missing** on a second, separate per-dispatch consumer:
`reprovisionWorkspaceOnDispatch` (`server/cc-reprovision.ts`), fire-and-forget on
**every** dispatch — warm AND cold — at `cc-dispatcher.ts:2899`.

### Symptom (member-stranding, reincarnated on the warm path)

A team-workspace **Member** (not Owner) opening the new **routines panel** in
Concierge (`components/routines/routines-surface.tsx`, dispatching with
`initialContext { type: "routine-authoring" }`) was told to "connect/reconnect a
GitHub repository in Settings → Repository" — an action a member cannot perform.
The `routine-authoring` directive hard-STOPs the agent when
`git rev-parse --is-inside-work-tree` is non-true, so the missing clone surfaces
more sharply there than on a chat dispatch, but the defect is on the **shared**
reprovision path, not routines-specific.

### Root cause

`reprovisionWorkspaceOnDispatch` re-derived the workspace id through **three
divergent resolvers**: `fetchUserWorkspacePath` (→ `resolveActiveWorkspace`,
membership-verified, resets a non-member claim to solo) vs. `resolveInstallationId`
and `getCurrentRepoUrl` (→ `resolveCurrentWorkspaceId`, **raw claim**, no
membership check). For a member whose membership state diverged from the claim
(removed/stale claim, or a transient membership-probe `db-error` where the
verified resolver fails closed to solo while the raw-claim resolvers keep the
team), the clone **location** (solo `/workspaces/<userId>`) diverged from
**repo+install** (team) — the team repo grafted into the solo path (no `.git`) or
no-op'd. This is the exact #4767 divergence PR-1 killed in the factory, surviving
on the warm/reprovision path with **zero divergence observability**.

### Decision

- **Option A4 (chosen): resolve once + thread + fail-closed-skip + breadcrumb.**
  Inside `reprovisionWorkspaceOnDispatch`, call `resolveActiveWorkspace(userId,
  tenant)` ONCE (one `getFreshTenantClient`), thread the single membership-verified
  `activeWorkspaceId` into `fetchUserWorkspacePath`/`resolveInstallationId`/
  `getCurrentRepoUrl`, and emit the deduped `repo_resolver_divergence` breadcrumb
  (new op `reprovision-non-member-claim-reset`) on a non-member-claim reset. The
  ONE deliberate divergence from the factory: on a `{ok:false,"db-error"}` this
  **fire-and-forget recovery SKIPS** (returns `"ok"`) rather than throwing
  `WorkspaceNotReadyError` — the factory is the dispatch readiness *boundary* (it
  must throw to surface the not-ready CTA); the reprovision is a post-recovery
  helper whose `ReprovisionOutcome` only gates the honest message, so the skip
  preserves the existing fail-soft contract (no false reclaim) while never cloning
  into an unverified location.
- **Rejected: thread the cold factory's already-resolved id down into
  reprovision.** The factory resolves lazily inside the runner's query
  construction, AFTER `dispatchSoleurGo` fires reprovision at `:2899` — the id is
  not in scope at the call site. Resolving once inside reprovision mirrors how the
  factory resolves locally.
- **Rejected: make the install/repo resolvers membership-verify by default.** Broad
  blast radius (many callers pass an explicit id or rely on the claim resolver);
  threading the id at the one divergent site is the minimal, targeted fix.

The autonomous-toggle trio (`resolveBashAutonomous`/`resolveAutonomousAck`/
`resolveIsWorkspaceOwner`) is **deliberately not threaded** here either (each backs
onto an `is_workspace_member`-gated RPC → fail-closed on a non-member reset), the
same scoping PR-1 chose for the factory.

### C4 edge note

No `.c4` model edit. The Member is already covered by the multi-Owner ADR-038
`founder` actor; the install RPC read and clone edge are already modeled; this is
an internal wiring fix below the C4 component grain (which resolver an existing
internal dispatch consumer uses). Grep of `knowledge-base/**/*.c4` for the
relevant identifiers confirms **no C4 impact**.

### Observability

New op `reprovision-non-member-claim-reset` on the existing
`repo_resolver_divergence` breadcrumb (`server/repo-resolver-divergence.ts`),
fingerprint-deduped by `op:userId:activeClaimWorkspaceId`, carrying ONLY the two
workspace ids (no `repoUrl`/`installationId`). The Sentry issue-alert is
feature-scoped (not op-scoped), so the new op routes through the existing rule with
no `infra/sentry/*.tf` change. Routing-rule fan-out remains the soak-gated #5437
follow-up.

### Sequencing

Single atomic PR (wiring + new breadcrumb op + tests + this amendment). No schema
change, no migration, no soak gate on the code change; the breadcrumb's
prod-soak observation is a post-merge verification only.

## Amendment 2026-06-29 — application-enforced scoped solo-uniqueness at the connect boundary (#5673)

**Status: adopting** → accepted after the AC8 soak holds `op:founder-ambiguous` at
~0 for 7 days post-deploy.

This **closes the "connect path" half of the gap R7 (Amendment 2026-06-17b) named**:
R7 recorded that the "one solo workspace per `(installation_id, repo_url)`"
invariant became "enforced **nowhere structurally** — only by the connect path +
this PR's runtime `>1` fail-closed," but the **connect path itself had no guard** —
a second solo workspace could still bind an already-owned `(install, repo)`, after
which every non-push webhook for that install 404-dropped + paged (WEB-PLATFORM-3M).
This amendment implements that connect-path check.

### Decision

A **second solo workspace** is prevented from binding `(github_installation_id,
normalizeRepoUrl(repo_url))` already owned by a *different* solo workspace, via an
**application-level TypeScript check at the `repo/setup` connect boundary**
(`server/repo-connect-guard.ts`, invoked from `app/api/repo/setup/route.ts` before
the `:202-215` cloning-flip write). The guard **reuses the existing
`resolveSoloFounderForInstallation`** (one source of truth for the solo invariant —
not a second, drift-prone SQL copy) and branches:

- resolver `none` → **proceed** (happy path).
- `found`, founder == caller's active workspace → **proceed** (re-connect/no-op).
- `found`, founder == caller's OWN solo (≠ active) AND that workspace `ready` →
  **switch** redirect (reuse `set_current_workspace_id`; the surfaced
  `existingWorkspaceId` is the caller's OWN id only).
- `found`, founder == caller's own solo but NOT `ready` → **decline**.
- `found`, founder == a DIFFERENT user's solo → **generic decline** (fixed 409,
  no workspace/user reference — no information disclosure / IDOR).
- `ambiguous` / `db-error` → **decline** + `reportSilentFallback` (fail-closed).

The owning solo workspace is always solo (id == owner user id, ADR-038 N2), so
"the caller is the owner" reduces to `founderId == user.id` — no membership query.
The `repo_status == 'ready'` switch gate needs an **explicit** `workspaces`
read keyed on `founderId` (the resolver returns only `{kind, founderId}`).

### Considered Options (amendment)

- **Option A (chosen): application-enforced scoped solo-uniqueness in TS, reusing
  the resolver.** No new migration/RPC/advisory-lock. The WEB-PLATFORM-3M incident
  is **sequential** (one operator, two sessions); the double-click race is already
  covered by the optimistic `.neq("repo_status","cloning")` lock on the cloning-flip
  write in `repo/setup/route.ts`; the
  rare true concurrent double-connect degrades to **today's** behavior via the
  retained resolver `>1` backstop. One source of truth for the solo invariant.
- **Rejected: a SECURITY-DEFINER RPC + advisory lock for hard atomicity.** The
  advisory lock releases at the RPC tx end, but the route's cloning-flip write is a
  separate PostgREST tx — the lock would NOT span read→write, so it adds a second
  drift-prone SQL copy of the solo invariant for **no** atomicity the optimistic
  lock + `>1` backstop don't already provide for the realistic (sequential) threat.
- **NOT a reversal of Option C** (the original ADR-044 rejected global
  `UNIQUE(repo_url)`). This invariant is scoped to `(install, repo)` **and** further
  narrowed to **solo-only**; cross-install fan-out (two users + same public repo
  under DIFFERENT installs) is preserved exactly (resolver returns `none` → proceed).
  Option C's global uniqueness threw `23505` on that legitimate case; this does not.
- **NOT case-normalized** (dropped TR2/AC2): the resolver matches `repo_url`
  case-sensitively and GitHub sends one canonical casing, so `Foo/Bar` vs `foo/bar`
  never yields `>1`. Mis-cased-row-gets-no-webhooks is a separate hardening issue.

### Dropped-atomicity tradeoff (accepted)

The retained `soloRows.length > 1` ambiguous branch in
`resolve-founder-for-installation.ts` is now the
**primary** race safety net (commented as such), not merely webhook defense-in-depth.
A sub-ms concurrent double-connect by two *different* users on the same
`(install, repo)` (never observed; same install ≈ same org/account) would create two
well-formed rows on distinct keys — never a torn/dirty row — and the next non-push
webhook fail-closes (drop + page) until an operator re-points: **today's** behavior,
not worse. Escape hatch if it ever materializes: fold the write into the
`claim_repo_clone_lock` (mig-108) advisory-lock shape.

### Existence-oracle residual (accepted, v1)

The decline **body** is uniform across decline sub-cases, but the proceed-vs-decline
**outcome** (200 cloning vs 409) reveals to the caller whether `(install, repo)` is
already connected. This is inherent to any duplicate block and **bounded to
same-installation members**: a true stranger never reaches the decline — they bounce
at the `400 "GitHub App not installed"` gate first, because `installationId` is
resolved only from the caller's own reachable set. Same-install members already hold
GitHub read access to the repo. The genuine fix (collaborator-gate) is the
**deferred** request-to-join path; v1 accepts this residual.

### C4 edge note

**No `.c4` model edit.** Verified against all three model files
(`model.c4`/`views.c4`/`spec.c4`): (a) the connecting user is the existing `founder`
Owner actor (description already models multiple Owners, ADR-038) — no new actor;
(b) GitHub is modeled but v1 makes **no** collaborator-API call (that `api -> github`
edge belongs to the deferred request-to-join path); (c) `api` + `supabase` are
modeled and the new guard logic is TS inside `api`, reached via the existing
`api -> supabase` edge; (d) the switch reuses the existing
`api/dashboard -> supabase set_current_workspace_id` path. No access-relationship
edge is added or falsified. Grep of `knowledge-base/**/*.c4` for the relevant
identifiers is empty. **No C4 impact.**

### Observability

The connect-time guard mirrors `ambiguous` (a pre-existing duplicate-solo pair hit
at the connect boundary) and `db-error` (fail-closed) to Sentry via
`reportSilentFallback` with `feature=repo-setup`, op `connect-guard-ambiguous` /
`connect-guard-db-error` — distinct from the webhook-time
`op:founder-ambiguous` page so on-call can tell a connect-time block from a
webhook-time drop. The existing `github_webhook_founder_ambiguous` paging rule
(R8) is unchanged. A **detection-only** query surfaces any remaining
duplicate-solo `(install, lower(repo_url))` groups at deploy for the operator's
keep-which intent decision (no automated remediation — wrong-keep risk).

### Sequencing

Single atomic PR (guard + route wiring + UI switch/decline states + resolver
comments + this amendment + tests). No schema change, no migration, no soak gate on
the **code**; the AC8 `op:founder-ambiguous`-stays-at-0 soak is a post-merge
verification that flips this amendment's status `adopting` → accepted and closes
#5673 (the PR uses `Ref #5673`, not `Closes`).

## Amendment 2026-06-29 — periodic backstop reconciles ready+NULL-install (entitlement-scoped, solo-only) (#5675)

**Lineage.** The 2026-06-18 *"dispatch readiness must distinguish membership-deny
NULL install from not-connected"* amendment (above) closed the **synchronous
dispatch** dark path and established the **zero-write rule** at that gate. This
amendment is its **operational-reconciliation counterpart** on the **periodic
backstop** (`cron-workspace-sync-health.ts` arm-1), and carries the zero-write
rule forward only in its **narrow** form. The two are deliberately different:
the dispatch gate reads a **membership-deny NULL** (it cannot tell deny from
not-connected) and therefore must **never** bind an install; the cron reads the
**true NULL** via service-role (no membership gate in scope) and **can** safely
backfill within entitlement scope.

**Defect.** A workspace in `repo_status='ready'` whose
`workspaces.github_installation_id IS NULL` is unreachable by the push-driven
reconcile (`workspace-reconcile-on-push.ts` filters `WHERE github_installation_id
= <push.installation.id> AND repo_url = …`, so a NULL-install row never matches).
Arm-1 **detected** this class and reported it to Sentry
(`op:ready-null-installation`) but **never resolved** it — so a genuine
ready+NULL-install workspace stayed frozen indefinitely (this exact state froze
the founder's own KB for ~5 weeks; Sentry folds the recurring daily occurrences
into one standing issue, so "33 occurrences" ≈ one workspace stuck ~33 days, not
33 distinct alerts).

**Decision (decided here).** Arm-1 backfills `workspaces.github_installation_id`
for **SOLO workspaces only**, resolving the install via the **entitlement-scoped
connect-path resolver** (`resolveReachableInstallationIds` keyed on the owner's
`user_id` + `github_username` → `resolveOwningInstallationForRepoDetailed`), and
writing through the canonical `writeRepoColsToWorkspace` boundary (keyed on the
finding's own server-derived id). Team workspaces (never auto-detect their
install — `detect-installation`) and genuinely-unresolvable findings (owner not
entitled / app uninstalled / empty listing) keep the existing folded, **visible**
`op:ready-null-installation` signal; an all-degraded GitHub probe no-ops as
**transient** and self-recovers on the next fire. It **NEVER** flips
`repo_status`.

**The load-bearing correctness invariant** is that the backfilled id MUST equal
the `installation.id` GitHub sends in future push webhooks for that repo. The
entitlement-scoped resolver guarantees this — it returns the owner's *owning*
install for the repo (which is the push-webhook install). A bare
`findInstallationByAccountLogin(owner)` + `checkRepoAccess` would NOT: its own
docstring notes `checkRepoAccess` cannot distinguish the owning install from a
collaborator install, so for an org repo it would over-grant the org's full-write
install onto a workspace whose owner is not entitled to it.

**Honest exception-carve (this is NOT "zero workspaces writes").** This carries
forward only the narrow *"never persist `repo_status=error`"* sub-rule of the
2026-06-18 zero-write rule — it does **not** inherit "zero `workspaces` writes."
A *populating* `github_installation_id` write is safe here (unlike the dispatch
path) because: **(a)** the cron reads the **true** NULL via service-role, not a
membership-deny NULL; **(b)** resolution is **entitlement-scoped** to the owner's
reachable installs — it does **not** widen the credential RPC (the option the
2026-06-18 amendment rejected); **(c)** it is **solo-only**, so there is no
shared-row cross-tenant corruption surface. The dispatch gate's zero-write rule
stands unchanged on the dispatch path.

**Reconcile against the 2026-06-18 rejected option.** That amendment **rejected**
*"widen `resolve_workspace_installation_id` to return the install on
membership-deny."* That rejection **stands**. This amendment does the **opposite
of widening**: it resolves the install **server-side, within the owner's
entitlement scope**, and **never** exposes the credential to a non-member. The
credential RPC is unmodified.

**Arc status.** The column-ownership decision (`workspaces` is the source of
truth for the repo-connection columns) remains **COMPLETE**; this amends only the
*operational reconciliation consequence* of a NULL-install row, not the ownership
grain.

### Considered Options (amendment)

- **Demote-only signal (the issue's literal "skip-with-reason so it no-ops
  cleanly")** — **REJECTED.** Leaves the KB frozen (non-resolution is the real
  defect, not paging fatigue); and the `workspace_sync_health` alert is
  **feature-only / level-agnostic**, so demoting the report's level is a **no-op**
  (a warn still trips the feature rule; the daily occurrences already fold into
  one issue). Resolution, not demotion, is the fix.
- **Bare `findInstallationByAccountLogin(owner)` + `checkRepoAccess`** —
  **REJECTED.** Over-grants an org's full-write install onto a non-entitled
  owner's workspace (cross-tenant credential escalation). This is the exact
  pattern the connect flow already rejected for credential binding.
- **Flip `repo_status='error'`** — **REJECTED.** A 409 on the `/api/kb/tree` read
  would BLANK the user's tree (strictly worse than a stale-but-visible tree); and
  on a transient install blip it converts a self-recovering state into a sticky
  failure (the dispatch amendment's sticky-transient failure mode).

### C4 edge note

No `.c4` model edit. The affected user is a workspace Owner (already covered by
the `founder` actor's multi-Owner ADR-038 description); the install resolution +
repo probe (`api`/`engine -> github`) and the `workspaces` write (`-> supabase`)
are already modeled; `github_installation_id` is a column, below the C4 component
grain — consistent with every prior ADR-044 amendment ("captured in ADR prose,
not a `.c4` edit"). Grep of `knowledge-base/**/*.c4` for
`installation`/`reconcile`/`sync-health`/`adr-044` is empty. **No C4 impact.**

### Sequencing

Single atomic PR (arm-1 reconcile wiring + the `resolveOwningInstallationForRepoDetailed`
variant + allowlist rationale + tests + this amendment). No schema change, no
migration, no soak gate on the code (the credential RPC is unmodified). Post-merge
verification (AC11–AC13) is observation-only: confirm reconciled solo workspaces
carry a non-NULL install and drop out of the next scan; if a `needs-reauth` /
`transient` residual persists after a one-week soak, the write-path that mints
`ready`+NULL rows is investigated (the cron is a backstop, not the fix-of-record).

**Follow-on (#5689 item 2, 2026-06-29).** Arm-1 now also performs an immediate
in-arm `syncWorkspace` (live default-branch HEAD pull) right after a successful
backfill, audited under a truthful `reconcile_backfill` `kb_sync_history` trigger,
so a reconciled solo workspace's KB no longer waits days for the next push to
catch up. It emits no Inngest event (ADR-033 I6 preserved) and needs no migration
(`trigger` is free-form JSONB). On sync failure the row is not re-synced by arm-1
(it has left the scan predicate); push + arm-2 `stale-sync-failed` own the failure
loudness. Item 1 (producer investigation above) remains soak-gated.

## Amendment 2026-06-29 — reconcile readiness gates on worktree VALIDITY + re-clone

The push-reconcile readiness gate was "filesystem existence of the workspace dir." That made a
dir-exists-but-`.git`-broken (or `.git`-absent) workspace a permanent trap: reconcile fired on
every push but `syncWorkspace` only pulls/resets — it never re-clones. Readiness now gates on
`isValidGitWorkTree` (the validity primitive landed in PR #5584; this amendment wires it into the
reconcile readiness gate). A VALID `.git` keeps the existing pull/reset path; an INVALID or
ABSENT `.git` is re-cloned via `ensureWorkspaceRepoCloned` (clones if absent; removes a
positively-fingerprinted empty-corrupt `.git`; honest-blocks populated-broken/EACCES/gitdir-FILE,
never destroying commits). Recovery is push-triggered. This supersedes the
"readiness is a filesystem-existence check" note (Amendment 2026-06-17b context). The owner-less /
duplicate-workspace anomaly that produced the corrupt state is tracked separately in #5591.

## Amendment 2026-06-30 — readiness is `git rev-parse`-AWARE (closes the dominant strand case), not lstat-structural-only; keying-divergence boundary; strand observability (#5733)

Investigation of #5733 (operator `/soleur:go` strands on `not a git repository`
after #5716/#5584/#5730) refuted the issue's separate-container hypothesis (one
container, one `/mnt/data/workspaces` volume; the agent is an in-process bubblewrap
sandbox) and isolated three load-bearing corrections:

1. **`isValidGitWorkTree` (lstat-structural) is INSUFFICIENT as the readiness
   invariant.** It returns `true` for a `.git` FILE (a `gitdir:` pointer;
   `git-worktree-validity.ts:60`). The agent's Bash tool runs `git rev-parse
   --is-inside-work-tree` INSIDE a bubblewrap sandbox whose mount set is frozen
   per `query()` with `denyRead:["/workspaces"]`. A `.git` FILE whose gitdir
   target resolves under `/workspaces` is therefore unreadable in-sandbox → the
   agent's `rev-parse` fails and `/soleur:go` Step 0.0 self-stops, even though the
   host-side lstat gate passed. **A personal workspace root is never a legitimate
   linked-worktree/submodule, so a `.git` FILE there is an anomalous stale
   pointer.** Readiness now uses `isReadyGitWorkTree` (a self-contained valid dir
   OR a NON-escaping in-workspace pointer that is readable in-sandbox) — a
   structural, `rev-parse`-AWARE check; it does not itself run `rev-parse`. Only an
   ESCAPING (or unclassifiable) pointer is treated as not-ready and re-cloned to a
   SELF-CONTAINED `.git` (unlink the single pointer file under the workspace lock —
   NOT a widening of the empty-corrupt recursive-rm fingerprint — then clone from
   origin HEAD); a non-escaping in-workspace pointer is left untouched. The
   predicate is swept across **all THREE** workspace-readiness gates — cold
   dispatch (`cc-dispatcher`), WARM re-provision (`cc-reprovision`), and
   reconcile-on-push — so a pointer arising mid-session heals on the next warm turn
   too. The new `agent-readiness-self-stop` signal is **query-only by design** (the
   strand auto-heals in the same dispatch), a discoverability event, not a page.

2. **Keying-divergence trust boundary (root architectural cause).** The two
   writers/readers of the `/workspaces/<id>` volume key the path by DIFFERENT
   identifiers: reconcile-on-push heals `<id>` by `(installation_id, repo_url)`
   (independent of any session claim); the agent resolves its cwd from the user's
   ACTIVE workspace (`user_session_state.current_workspace_id` →
   membership-verified → fail-closed to solo). These keys can point at different
   dirs. For the operator's solo case they coincide (`current_workspace_id ==
   userId == workspace_id`), so the strand was purely the `.git`-shape blind spot
   above, not a resolution divergence.

3. **The prompt-driven readiness self-stop MUST emit a server-side signal.** The
   self-stop is the agent reasoning over `/soleur:go` Step 0.0 prompt text — it
   produces NO server Sentry event, the deepest reason all three prior server-side
   fixes left "zero events on the agent surface." A distinct
   `agent-readiness-self-stop` event (own Sentry issue group) now fires at the
   dispatch readiness gate carrying the resolved id + path + `.git` shape, BEFORE
   the heal.

**Owner model note (supersedes #4520, dedicated ADR to follow).** #5733 also found
the "owner-less reconciled ×28" headline was a FALSE positive: the reconcile
owner-attribution used `.maybeSingle()`, which ERRORS on a workspace with ≥2
`workspace_members(role='owner')` rows. Per the founder, **workspaces support N
co-owners by design** — this supersedes the single-owner-strict model asserted in
migration `075` (#4520). The reconcile attribution now tolerates N owners
(deterministic self-row/earliest pick; "owner-less" warns only on genuinely zero
owners). Reconciling the single-owner ownership RPCs (`transfer_workspace_ownership`,
the `update_workspace_member_role` owner-promotion block) to the multi-owner model
is tracked as a follow-up; this ADR records the direction, and the dedicated
decision-of-record is now **ADR-073** (multi-owner workspaces + the
`organizations.owner_user_id` primary-owner pointer), which captures the
supersession and additionally pins the `owner_user_id` pointer semantics under
N owners.

## Amendment 2026-06-30 — dispatch readiness adds a host `git rev-parse` confirm for `dir-valid` worktrees (SUPERSEDES the 2026-06-19 zero-await trade-off for the connected cold path) + an agent-context observability backstop (#5733)

The prior #5733 fix (commit `190ab58a5`) shipped the lstat-structural
`rev-parse`-AWARE scaffolding above and the `agent-readiness-self-stop` mirror,
but left a GAP confirmed against live prod: the operator's workspace `754ee124`
strands `/soleur:go` on `not a git repository` even though its on-disk `.git` is
**`dir-valid`** (lstat sees `HEAD`+`objects`), because the lstat verdict
`isReadyGitWorkTree` returns `true` for a `dir-valid` whose `.git` `git` itself
cannot resolve as a work tree (broken `config`/`commondir`/refs/gitdir
indirection). This is the textbook proxy-vs-invariant divergence: the cheap lstat
proxy greenlights a spawn the agent's own in-bwrap `git rev-parse` then strands
on, and — because the on-main mirror fires on the SAME lstat proxy
(`!isReadyGitWorkTree`) — the observability is blind precisely on the shape it was
built to see.

### Decision

1. **Add an authoritative host `git rev-parse --is-inside-work-tree` CONFIRM,
   scoped to `dir-valid` shapes** in the lstat-ready + connected (`repoUrl`) +
   DB-ready population (`hostGitRevParseOutcome` / the shared
   `evaluateAgentReadiness` in `git-worktree-validity.ts`). Outcomes:
   `worktree` → ready (fast path); `not-a-worktree` → emit the self-stop
   (`gitRevParseValid=false`, `gitKind=dir-valid`) + honest-block
   `RepoNotReadyError` (NO spawn, **NO destroy** — `ensureWorkspaceRepoCloned`
   no-ops on a populated `.git`, so honest-block is the only safe outcome);
   `inconclusive` (spawn-error/timeout/EACCES) → re-probe once, then **FAIL-OPEN**
   to spawn + a low-signal `agent-readiness-probe-inconclusive` breadcrumb (a
   transient blip must NEVER honest-block a healthy repo — fail-closed-to-heal
   manufactures the exact #5733 strand on a working repo). Hardened like the
   `git-auth.ts` spawn precedent: `execFile` array form, `GIT_CONFIG_NOSYSTEM` /
   `GIT_CONFIG_GLOBAL=/dev/null` / `GIT_TERMINAL_PROMPT=0`, **no installation
   token / askpass**, ~2s timeout + `maxBuffer` + `killSignal`, and
   `GIT_CEILING_DIRECTORIES=<abs, symlink-resolved parent>` so host git cannot
   ascend into a parent `.git` and false-pass.

2. **One shared `evaluateAgentReadiness` helper across all THREE gates** (cold
   `cc-dispatcher`, warm `cc-reprovision`, reconcile `workspace-reconcile-on-push`)
   so the emit + heal-route + re-probe + fail-open decision is **structural, not
   re-specified per gate** — the cold-only-emit / warm+reconcile-dark drift was the
   26×-fired-yet-unqueryable incident. **No warm memoization** (a stale positive
   masks sub-lstat corruption from a concurrent reconcile/pull and re-darkens the
   warm path). Reconcile computes the verdict ONCE per event (one `rev-parse`
   spawn) and swaps both its readiness gate and its `recovered` re-probe to the
   shared verdict.

3. **An agent-context observability backstop (deliverable C2).** Because the host
   `rev-parse` is blind to the escaping-pointer strand (host git is NOT sandboxed)
   AND to object-store corruption (rev-parse passes both sides), a host-side emit
   alone can leave a strand dark for shapes it cannot see. The agent's OWN in-bwrap
   Step 0.0 `git rev-parse --is-inside-work-tree` RESULT is the guaranteed signal:
   the dispatcher's `onToolResult` mirror (`isInSandboxRevParseStrand`) fires the
   self-stop with a distinct `source: "in-sandbox-backstop"` tag, so a strand of
   ANY on-disk shape — including the object-store residual the host confirm is
   blind to — produces a queryable event without pre-confirming 754ee124's
   (unobservable) shape.

### SUPERSESSION of the 2026-06-19 zero-await trade-off

The 2026-06-19 amendment chose the lstat proxy *explicitly* as "deliberately
WEAKER than `git rev-parse --is-inside-work-tree` but cheap enough to keep the AC7
zero-await hot path." This amendment **supersedes** that guarantee **for the
connected cold path**: an async `dir-valid` host `rev-parse` confirm now runs on
the common healthy connected cold dispatch (and the warm dir-valid turn). The fast
sync lstat routing is unchanged and still owns the absent / dir-invalid / pointer /
repo-less / not-DB-ready shapes; the subprocess is additive and `dir-valid`-gated.
This is NOT a "retained" fast path — the zero-await property no longer holds for a
connected `dir-valid` dispatch, and that cost is accepted because the dispatch does
an agent round-trip regardless.

### Scope of the subprocess's net-new coverage (attributed honestly)

The host confirm's net-new coverage is **exactly the corrupt-`dir-valid` slice**.
It is **blind to the escaping pointer** (host git is not sandboxed → returns
`worktree`; the lstat verdict already heals that case structurally) and **blind to
object-store corruption** (HEAD→missing objects / broken `objects/info/alternates`
pass `--is-inside-work-tree`, which validates gitdir *discoverability*, not object
integrity — the documented out-of-scope residual). Deliverable C2 is what surfaces
both blind shapes. The destroy authorizations are **UNCHANGED** — exactly the two
`.git`-targeting `rm` sites (`ensure-workspace-repo.ts` stale-pointer FILE +
empty-corrupt dir); a populated `dir-valid` satisfies neither fingerprint, so it
can only hit the `:207` no-op or the honest block, never an `rm`.

### Considered Options (amendment)

- **(CHOSEN) `dir-valid`-only host `rev-parse` confirm + the C2 in-sandbox
  backstop.** Behind the lstat pre-filter the escaping-pointer arm is already dead
  (the on-main verdict heals it), so the confirm collapses to a single `dir-valid`
  slice — removing a dead arm and two overlapping authorities for the pointer
  shape. Fail-OPEN on inconclusive; never destroys a populated `.git`.
- **(REJECTED) A bwrap-reproducing probe** (run `rev-parse` under a hand-rolled
  `denyRead:["/workspaces"]` mount to reproduce the sandbox exactly). The only
  host/in-sandbox divergence is the escaping pointer, already healed structurally
  on main; host `rev-parse` cannot reproduce the sandbox `denyRead`, so a
  reproduction adds the expensive namespace setup **and** a silent-drift coupling
  to `agent-runner-sandbox-config.ts` for ZERO extra coverage. The C2 backstop —
  which reads the agent's REAL in-sandbox result — covers that divergence for free.
- **(REJECTED) Widen the destructive re-clone to "rev-parse-invalid + has origin →
  reclone".** Origin is canonical for the *base*, not the working tree; a populated
  `.git` may hold the only copy of un-pushed prior-turn work. Loses the
  brand-survival invariant. The populated-corrupt `dir-valid` is observed +
  honest-blocked, never destroyed.
- **(REJECTED) Unconditional `rev-parse` on every dispatch / warm memoization.**
  Scoped to `dir-valid` in the lstat-ready + connected + DB-ready population
  instead; memoization was dropped because a stale positive masks sub-lstat
  corruption and re-darkens the warm path.

### Observability

`agent-readiness-self-stop` (own Sentry issue group, query-only by design) now
fires from all THREE gates AND the C2 in-sandbox backstop, carrying
`gitRevParseValid` + `gitValid` + `gitKind` + `source` + `activeWorkspaceIdHash`.
SECURITY: the probe's `stderr` / `error.message` is NEVER placed in `extra` — git's
failure text embeds the raw absolute path (`fatal: not a git repository:
/workspaces/<id>/.git`), and for a solo workspace `id == raw userId`, so leaking it
would defeat the deliberate boundary-rename pseudonymization. Only the structured
booleans + `gitKind` + `source` are emitted (no `installationId`/`repoUrl`/raw
path/`gitdirTarget`). The fail-OPEN path emits a DISTINCT
`agent-readiness-probe-inconclusive` op so it does not inflate the strand
discoverability count.

### C4 edge note

No C4 impact. The fix tightens the **pre-condition on the existing `api -> claude
"Spawns agent sessions"` edge** (`model.c4:249`), not the topology — no actors,
external systems, containers, data-stores, or access relationships added or
changed. Consistent with this ADR's prior no-C4-impact readiness amendments.
