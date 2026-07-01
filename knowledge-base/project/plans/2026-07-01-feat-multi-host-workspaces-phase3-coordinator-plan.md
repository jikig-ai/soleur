---
title: "Multi-host /workspaces — Phase 3: 2nd host + stateless lease-keyed coordinator (GA line)"
date: 2026-07-01
type: feature
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
epic: 5274
issue: 5274
phase: 3
adr: knowledge-base/engineering/architecture/decisions/ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md
epic_plan: knowledge-base/project/plans/2026-06-29-feat-multi-host-workspaces-layer-plan.md
spec: knowledge-base/project/specs/feat-multi-host-workspaces/spec.md
branch: feat-multi-host-workspaces-phase3
status: draft
---

# ✨ Multi-host `/workspaces` — Phase 3: 2nd host + stateless coordinator (GA line)

> **Resumed epic.** #5274 is the tracking anchor for the staged multi-host
> `/workspaces` layer (ADR-068, Approach A). Phases 0/1/2 have merged and are
> **dark-launched behind `isGitDataStoreEnabled()`**. Phase 3 is the **GA line**
> (ADR-068 §8, OQ3 resolved by operator 2026-06-30): concurrent multi-host serving
> of one workspace's users, planned moves seamless, committed/pushed work durable.
> PR bodies use **`Ref #5274`** (never `Closes`) until Phase 4 completes the epic.

## Overview

Phase 3 makes the backend a **2-host cluster** and adds the **stateless, lease-keyed
coordinator** that routes a session to the host holding its `worktree_write_lease`
and forwards cross-host control ops (abort / gate-resolve / grace). It flips the
`isGitDataStoreEnabled()` dark-launch flag on for the first time under real
contention, and ships the two cross-cutting security boundaries ADR-068 §6 requires
(per-`workspace_id` git-data credential + coordinator↔host mTLS). It implements
ADR-068 **§4** (coordinator routing), **§5** (lease-derived affinity + tunnel→coordinator
rewire), and **§6** (cross-tenant isolation), plus the 2nd-host IaC (`for_each` +
`hcloud_placement_group type=spread` + `moved` blocks → 0-destroy).

**What Phase 3 does NOT do** (deferred, per ADR-068 §8): Nomad, lease-expiry reclaim
cron, and the EU session-Redis replay buffer are **Phase 4a** (seamless *unplanned*
crash recovery). Continuous worktree checkpoint of *uncommitted* work is **Phase 4b**.
The shared-git-data-host SPOF is an **accepted GA-line residual** (honest reconnect +
GitHub rehydration cover it; #5723 / Garage closes it post-GA). **Do not introduce
Redis in this phase.**

**Design authority.** ADR-068 is authoritative for mechanism and sequencing; this
plan concretizes its §4/§5/§6 against the current code. Foundations shipped in
Phases 0–2 are reused unchanged (`worktree-write-lease.ts`, `git-data-replication.ts`,
`host-identity.ts`, `git-auth.ts`, the pre-receive CAS fence, migration 116). The
coordinator + mTLS + per-workspace cred are **built from scratch** (no prior art in
the tree).

## Research Reconciliation — Spec vs. Codebase

Verified against `origin/main` @ `02a206ad1` (2026-07-01) via four parallel research
agents (app-code trace, infra/Terraform trace, learnings, external best-practices).

| Claim (ADR / spec / brainstorm) | Codebase reality | Plan response |
|---|---|---|
| §4 "make `abortSession` return a found-count" is the enabling change; use it to decide "turn already finished vs. lives on another host." | `abortSession` returns `number` (Phase 1, `agent-session-registry.ts:208`), **but its own docblock (193–206) warns it is LEGACY-ONLY** — `cc-soleur-go` turns live in `activeQueries`, not `activeSessions`, and never register here. The dominant production path is silent to this count. | The coordinator's "is it live here?" predicate MUST be `abortSession()>0 **OR** hasActiveCcQuery(convId)` (`cc-dispatcher.ts:2759`, already exported). Build a unified `isConversationLiveHere(userId, convId)` helper and call it **before** any forward decision. (Learning `2026-06-30-found-count-over-one-registry-is-partial…`.) |
| §5 affinity keeps grace-abort cancel host-local. | Phase 1 `runDisconnectGraceAbort` (`ws-handler.ts:228–263`) guards on `sessions.get(uid)` — a **local socket map**, not the lease. Correct only if the reconnect lands on the same host. | Do **not** replace the local guard with a cross-host poll (reintroduces the TOCTOU §5 warns of). Instead the **coordinator routes the reconnect back to the lease-holder** so the local guard stays correct. The forward path is for *abort/gate* control frames that arrive at a non-owning host, not for the grace cancel. |
| §6 git-data access carries a **per-`workspace_id`** credential (reuse `resolve_workspace_installation_id` shape). | `git-data-replication.ts` authenticates every push with a **single cluster-wide** transport key (`GIT_TRANSPORT_SSH_PRIVATE_KEY`). One key can push to any workspace repo. | Phase-3 design fork (deepen-plan input): the **app-server push** is a trusted boundary (Node resolves `workspaceId` from the authenticated session), so per-workspace scoping is load-bearing on the **fetch/clone** path (the 2nd host reading shared git-data) and the coordinator↔host channel — NOT necessarily the push key. Plan wires per-workspace cred at the fetch boundary via the `resolve_workspace_installation_id` membership-RPC shape (`resolve-installation-id.ts:39`, SECURITY DEFINER, NULL-for-non-member, mig 079) and documents the push-key trust rationale in the ADR amendment. |
| §6 "the in-sandbox `GIT_PUSH_OPTION_*` injection is DEFERRED to Phase 3." | `agent-runner-query-options.ts` / `buildAgentQueryOptions` (`cc-dispatcher.ts:2623`) do not inject `GIT_PUSH_OPTION_*` (correct for Phase 2). | Phase 3 adds `GIT_PUSH_OPTION_COUNT` / `GIT_PUSH_OPTION_0=lease-gen=<N>` / `GIT_PUSH_OPTION_1=worktree-id=primary` to the sandbox env at cold-Query construction, captured from the held lease. (`receive.advertisePushOptions true` is already set — `git-data-bootstrap.sh:126`.) |
| §6 bwrap `denyRead:["/workspaces"]` does not cover remote git-data. | Confirmed: `agent-runner-sandbox-config.ts:106` denies local `/workspaces` + `/proc` only; the git-data fetch runs in the Node process, outside the sandbox. | Per-workspace cred on the Node-process fetch is the enforcement (above row); no sandbox-mount change. |
| Migration 116 = `worktree_write_lease`; release tombstones (not DELETE). | Phase-2 lease + fence complete; release UPDATEs `heartbeat_at='-infinity'` preserving `lease_generation` monotonicity (ADR-068 amendment 2026-06-30). | Phase 3 uses the lease **unchanged** but is the **first live exercise under contention** — an AC must verify tombstone-release preserves the fence token across a real cross-host takeover (learning `2026-06-30-precedent-mirror…-fencing-token-monotonicity`). |
| C4: coordinator/gitDataStore/tunnel→coordinator are Phase-0 deliverables. | Confirmed present + rendered: `model.c4:185/193/197`, `tunnel -> coordinator` (`model.c4:282`), included in `views.c4:34–35`. | **No new C4 authoring** — Phase 3 verifies render + refines the `coordinator` element description if implementation adds detail, and **amends ADR-068** (status `adopting`→`accepted` when GA lands). |
| Tunnel `service` target "becomes the coordinator." | `tunnel.tf` ingress currently fronts only `deploy.` (localhost:9000) + `ssh.` (localhost:22) + a 404 catch-all. The **primary app/WS ingress is not in this tunnel config** (proxied DNS or a separate config). | **Open question (deepen-plan / Phase 0 of /work):** confirm where user WS traffic ingresses today before rewiring; §5's "tunnel→coordinator" applies to whichever ingress fronts the app. Do not assume `tunnel.tf` is the app front door. |
| No coordinator / cross-host RPC exists. | Confirmed — no `session-coordinator.ts`, no internal-fetch/mTLS helper. | Built from scratch in this phase. |

## User-Brand Impact

_Carried forward from the brainstorm (`2026-06-29-multi-host-workspaces-brainstorm.md` §User-Brand Impact) — threshold set at framing time with CPO/CLO/CTO._

- **If this lands broken, the user experiences:** a chat session that greets them as
  fresh mid-work (loses in-progress turn context), an abort/stop button that silently
  does nothing (the turn keeps running on another host), or a "workspace unavailable"
  on reconnect — the exact #5240 regressions this epic exists to prevent.
- **If this leaks, the user's code/workflow is exposed via:** a cross-tenant git-data
  read (host A serving tenant B's bare repo), a forged control op honored by an owning
  host (abort/gate on someone else's conversation), or the coordinator↔host channel in
  cleartext on the private net. These are the §6 boundaries.
- **Brand-survival threshold:** **single-user incident.** One user's cross-tenant
  exposure or one user's silent-abort is brand-fatal at this stage.

**Sign-off:** `requires_cpo_signoff: true`. CPO reviewed the approach at brainstorm
(non-negotiables: no silent fresh-session greeting, committed/pushed work never lost,
no wrong-tenant exposure). `user-impact-reviewer` runs at each PR review (review-time,
diff-shaped). CLO/CTO brainstorm concerns are reflected in the Risks + Domain Review
+ Observability sections below.

## Implementation Phases

Phase 3 is large (6 task groups spanning IaC + a new control plane + two security
boundaries + a live cutover). Following the Phase-2 precedent (foundations vs cutover
split, CPO-approved), it ships as **five sequenced sub-PRs**, each independently
mergeable and inert until the flag flips. RED→GREEN tests (task 3.6) are woven into
each sub-PR, not deferred. Every sub-PR body uses `Ref #5274`.

### Sub-PR 3.A — Infra foundations: 2nd host + placement group + host_id (dark)

Maps task **3.1**. All inert until 3.E flips the flag.

- **`for_each` refactor of the web host** (`server.tf:21`): `hcloud_server "web"` →
  indexed set keyed by a `var.web_hosts` map (`{ "web" = {...}, "web-2" = {...} }`).
  `ignore_changes=[user_data,ssh_keys,image]` already covers the force-replace attrs,
  so 0-destroy is achievable. Add `moved` blocks for the server, `hcloud_volume` +
  `hcloud_volume_attachment` (`server.tf:926–940`), **and every one of the 8 sibling
  `terraform_data` provisioners** (each moves `X` → `X["web"]`).
- **`hcloud_placement_group "spread"`** (new, in `network.tf` or `placement-group.tf`)
  attached to both web hosts. Free tier; max 10/group. **Gotcha:** attaching the group
  to the *already-running* web host forces a power-off → schedule as a maintenance-window
  apply, or bring the group up with the 2nd host and add the existing host in a
  controlled stop. Document in the Apply path.
- **2nd host private-net attachment** (`network.tf`): `hcloud_server_network` at a
  reserved IP (e.g. `10.0.1.11`); subnet `10.0.1.0/24` has headroom.
- **`SOLEUR_HOST_ID` injection** in `ci-deploy.sh` (both canary + prod `docker run`):
  `SOLEUR_HOST_ID=$(curl -sf --max-time 5 http://169.254.169.254/hetzner/v1/metadata/instance-id || cat /etc/machine-id | head -c 32)` → `-e SOLEUR_HOST_ID`. Without it,
  `resolveHostId()` (`host-identity.ts:30`) fail-loud throws in prod once the flag is
  on. **`ci-deploy.sh` is a `deploy_pipeline_fix` trigger → the ship Phase-5.5 drift
  gate auto-applies on merge; expected.**
- **RED→GREEN (3.6a):** `terraform plan -json | jq '[.resource_changes[]|select(.change.actions!=["no-op"] and (.change.actions|contains(["delete"])))]'` returns `[]` (0-destroy assertion); `host-identity` test extended for the metadata-resolved id; `set -e` on every remote-exec inline block (learning `2026-06-10-terraform-remote-exec-gating…`).

**Files:** edit `server.tf`, `network.tf`, `variables.tf`, `ci-deploy.sh`,
`.github/workflows/apply-web-platform-infra.yml` (ensure placement-group in the
`-target` set), `expenses.md` (+2nd host). Create `placement-group.tf` (optional).

### Sub-PR 3.B — Coordinator: stateless lease-keyed routing + control forwarding

Maps task **3.2** + the §4 core. Feature-gated; no behavior change at `replicas=1`.

- **`server/session-coordinator.ts` (new):** stateless (no live handles — the lease is
  in Postgres, so N replicas are safe). Reads `worktree_write_lease` for `(workspace_id,
  "primary")` → resolves the owning `host_id` → if local, resolve in-process; if remote,
  **RPC-forward** the control op to the owning host and return its result. Composes with
  the existing intra-host prefix broadcast (`agent-session-registry.ts:225`), does not
  replace it.
- **Unified liveness predicate** `isConversationLiveHere(userId, convId)` =
  `abortSession(...)>0 || hasActiveCcQuery(convId)` — the Research-Reconciliation
  correction. All three control ops route through it:
  - **abort** (`agent-session-registry.ts:208` + cc path),
  - **gate-resolve** (`resolveCcBashGate`, `cc-dispatcher.ts:1414`),
  - **grace** (owning-host-guarded; stays host-local via affinity — 3.D).
- **Placement at the WS-upgrade handshake, not after** (fly-replay lesson): the
  coordinator decides the owning host *before* the socket upgrades; never upgrade then
  redirect. Cold session with no lease → the acquiring host becomes the owner.
- **mTLS coordinator↔host** (§6): Node `tls` server on each host with
  `requestCert:true, rejectUnauthorized:true`; coordinator is the mTLS client. Owning
  host **re-verifies** the requester owns the target conversation/lease before honoring
  a forwarded op (`assertHostIdNotUserId`, never trust-the-coordinator). Control ports
  private-subnet only.
- **RED→GREEN (3.6b):** two-registry liveness unit test (legacy-only turn vs cc-only
  turn both detected); forward-on-not-found integration test; forged/unauthorized
  control op rejected at owning host (negative); mTLS handshake failure rejects (negative).

**Files:** create `session-coordinator.ts`, mTLS cert-load helper; edit `ws-handler.ts`
(route control frames through the coordinator), `cc-dispatcher.ts` (gate-resolve forward
hook), `agent-runner.ts` (abort forward hook).

### Sub-PR 3.C — Cross-tenant isolation: per-workspace git-data credential + push-options

Maps task **3.3** + the §6 fetch boundary.

- **`server/git-data-client.ts` (new):** wraps `gitWithPrivateKeyAuth` (`git-auth.ts:342`)
  with a **per-`workspace_id`** credential resolved via the `resolve_workspace_installation_id`
  membership-RPC shape (`resolve-installation-id.ts:39`; NULL → deny, the non-member
  case). This gates the **fetch/clone** path (2nd host reading shared git-data) — the
  boundary bwrap cannot cover.
- **Clone-from-git-data when flag on:** `ensure-workspace-repo.ts` clones from the
  `git-data` remote (retaining `origin`→GitHub for rehydration — never orphan GitHub).
- **In-sandbox `GIT_PUSH_OPTION_*` env injection** (deferred-to-Phase-3 item): inject
  `GIT_PUSH_OPTION_COUNT=2 / _0=lease-gen=<N> / _1=worktree-id=primary` at cold-Query
  construction (`buildAgentQueryOptions`), captured from the held lease.
- **Encryption-at-rest** on the git-data volume (Terraform) — GA-blocking per the CLO
  finding (NFR-026).
- **RED→GREEN (3.6c):** host-A cannot read tenant-B git-data with tenant-A's cred
  (negative, the AC4 invariant); non-member RPC → NULL → fetch denied; push carries the
  lease-gen option and the fence accepts equal-gen idempotent retries.

**Files:** create `git-data-client.ts`; edit `ensure-workspace-repo.ts`,
`git-data-replication.ts` (cred plumbing), `agent-runner-query-options.ts` (push-option
env), `git-data.tf` (encryption-at-rest).

### Sub-PR 3.D — Affinity + reconnect routing

Maps task **3.5** + §5.

- **Reconnect routes to the lease-holder** (coordinator), keeping the disconnect
  grace-abort cancel **host-local** (the Phase-1 `sessions.get(uid)` guard remains
  correct because affinity guarantees the reconnect lands on the owner).
- **WS close-code for cross-host migration** (learning `2026-03-27-websocket-close-code-routing`): if a session must move hosts, emit a **non-transient** close code the client
  routes on (quiet teardown + reconnect via the new lease-holder) — never a
  retry-in-place loop. Gate the client on **materialization proof**, not a session-origin
  proxy (learning `2026-06-15-…client-gate-must-key-on-materialization-proof`).
- **RED→GREEN (3.6d):** reconnect after a lease move lands on the new holder (affinity);
  grace-abort cancel stays host-local (no cross-host poll); migration close-code
  tears down + reconnects, no fresh-session greeting.

**Files:** edit `ws-handler.ts` (reconnect routing + close-code), `ws-client.ts`
(close-code handling), `session-coordinator.ts` (affinity resolve).

### Sub-PR 3.E — Cutover + GA flip (tunnel→coordinator, rsync, flag on, 2-host live)

Maps tasks **2.5-cutover** (carried into Phase 3 per operator) + **3.1 tunnel** + GA.

- **Tunnel→coordinator rewire** (`tunnel.tf`, §5 IaC option c) — *after* confirming
  where the app WS ingress currently enters (Research-Reconciliation open item).
- **Cutover (scripted, no SSH runbook):** drain active crons (existing `CRON_DRAIN`
  gate) → `rsync` bare objects/refs to the shared git-data store → **verify
  `git rev-list --all` count-match** (both sources identical; no silent truncation) →
  flip `isGitDataStoreEnabled()` (Doppler `prd`, one switch flips clone + path-split +
  push-with-gen + lease lifecycle atomically) → route new sessions via the coordinator.
  If the cutover is automated as a scheduled apply, use **Inngest-dispatches-GHA** (keeps
  cloud-admin creds off the app host — learning `2026-06-02-inngest-dispatches-gha…`),
  never in-process terraform.
- **NFR register flip** (`nfr-register.md`: NFR-019 N/A→achieved tier; re-point rows
  ADR-027→ADR-068). **ADR-068 status** `adopting`→`accepted`.
- **RED→GREEN (3.6e):** the AC2 headline — two users on one workspace served by two
  hosts, each on their own worktree, no git-index corruption; a drain/deploy invisible
  to an active user (AC5); rollback = flag off + re-drain (documented).

**Files:** edit `tunnel.tf`, `nfr-register.md`, ADR-068, cutover script under
`apps/web-platform/infra/` or `scripts/`; `expenses.md` confirm.

## Infrastructure (IaC)

Fires the Phase-2.8 gate (2nd host, placement group, coordinator service, tunnel
rewire, mTLS certs, `SOLEUR_HOST_ID`, encryption-at-rest). All lands in the existing
`apps/web-platform/infra/` root (AP-001; `terraform validate` CI gate already covers
it — `infra-validation.yml`).

### Terraform changes
- **Edit:** `server.tf` (`for_each` + `moved`), `network.tf` (2nd-host attach +
  placement group), `git-data.tf` (encryption-at-rest), `tunnel.tf` (service→coordinator),
  `variables.tf` (`var.web_hosts` map, coordinator + mTLS vars), `ci-deploy.sh`
  (`SOLEUR_HOST_ID`).
- **Create:** `placement-group.tf` (optional split), `coordinator.tf` (service def),
  `cloud-init-coordinator.yml` if the coordinator is a distinct process, mTLS CA/cert
  material via `tls_private_key` + `tls_self_signed_cert` + `tls_locally_signed_cert`
  (static self-signed CA, long-lived certs — the minimal-burden correct choice for a
  2-host cluster; step-ca/SPIFFE rejected as over-engineered).
- **Sensitive vars:** mTLS CA/host/client keys via `random`/`tls` resources →
  `doppler_secret` → runtime **env, never argv** (#5560). `terraform.tfstate` (R2)
  holds the TLS private keys in plaintext → treat tfstate as secret-bearing; R2
  credential scope is the control (ADR-068 §7 posture).

### Apply path
Cloud-init + idempotent bootstrap for the 2nd host (default for existing infra). The
`placement_group` attach on the **running** web host forces a power-off — apply in a
**maintenance window** (or bring the group up with the 2nd host and stop-add the
existing host deliberately). Expected downtime: one web-host reboot; the 2nd host
absorbs traffic if 3.B/3.E are live, otherwise a brief single-host blip. `moved` blocks
verified `0 to destroy` before apply.

### Distinctness / drift safeguards
`dev != prd` (distinct Supabase + Doppler configs). `moved` blocks are a single-apply
guarantee — **never rename `for_each` keys post-migration** (forces replace). Enumerate
+ replace every positional Terraform reader (`.rules[0]`-style) touched by the
`for_each` refactor via `terraform providers schema -json` (learning
`2026-06-30-…positional-rule-readers`). `receive.advertisePushOptions` already set.

### Vendor-tier reality check
No new vendor / sub-processor (self-hosted on Hetzner EU — the deciding GDPR reason).
`hcloud_placement_group` is free (max 10 servers/group; 2 used). 2nd `hcloud_server`
≈ €15/mo — record in `expenses.md` before PR-ready (`wg-record-recurring-vendor-expense-before-ready`). Verify current Hetzner pricing at the provider page before the 3.A budget line.

## Observability

```yaml
liveness_signal:
  what: coordinator route decisions + lease reads (op slug control_plane_route) and worktree_lease acquire/reclaim; per-host heartbeat
  cadence: per control-op + per lease heartbeat (25s)
  alert_target: Better Stack monitor on coordinator route-error rate; Sentry alert on control_plane_route failures
  configured_in: apps/web-platform/infra/sentry/*.tf (op contract) + Better Stack monitor TF
error_reporting:
  destination: Sentry (feature tags control_plane_route, worktree_lease)
  fail_loud: yes — fence rejects, mTLS handshake failures, cross-tenant cred denials all captureException fail-loud (never silent)
failure_modes:
  - mode: control op arrives at non-owning host and forward fails (owner down / mTLS reject)
    detection: control_plane_route Sentry event with {source_host, owner_host, op, forward_result} — an IN-SURFACE structured field set discriminating local-resolve vs forward-fail vs owner-not-found (blind-surface probe; learning 2026-07-01-blind-surface-needs-structured-probe)
    alert_route: Sentry alert + Better Stack
  - mode: cross-tenant git-data cred denial (non-member RPC → NULL)
    detection: worktree_lease/git-data Sentry event {workspace_id_hash, member:false}
    alert_route: Sentry (security-relevant)
  - mode: mTLS cert expiry (silent cascade risk)
    detection: log cert notAfter at startup; Sentry on socket.authorizationError
    alert_route: Better Stack cert-expiry monitor + Sentry
  - mode: fence false-reject after cutover (lease-gen non-monotonic)
    detection: git-data pre-receive reject → Sentry worktree_lease event {stored_max, pushed_gen}
    alert_route: Sentry alert (GA-gating during soak)
logs:
  where: Sentry breadcrumbs + structured JSON logs shipped to Better Stack; no host-local-only logs on the control path
  retention: per existing Better Stack retention (≤ conversation retention for any user-content-adjacent field)
discoverability_test:
  command: "gh api /repos/jikig-ai/soleur/... OR the Sentry API query for op:control_plane_route events on the affected workspace (documented in the runbook) — NO ssh"
  expected_output: control_plane_route events present with discriminating fields; zero events on a changed forward path after deploy ⇒ wrong layer (learning 2026-06-30-verify-the-fixed-code-path-executes)
```

**Affected-surface (§2.9.2):** the coordinator, the Cloudflare tunnel connector, and
the in-sandbox agent are surfaces the operator cannot directly inspect. Every new
failure mode's `detection` names an **in-surface** structured probe whose fields
discriminate all competing hypotheses in one event (source_host / owner_host /
forward_result; member:bool; stored_max/pushed_gen) — not a single boolean. No SSH in
any runbook (`hr-no-ssh-fallback-in-runbooks`).

**Soak follow-through (§2.9.1):** GA close is soak-gated — the cutover ACs require
**≥7 days of a ~50/50 two-host split with zero fence false-rejects and zero
cross-tenant denials** before ADR-068 flips `accepted` and #5274's Phase-3 milestone
closes. Enroll a `scripts/followthroughs/phase3-ga-soak-5274.sh` probe (Sentry-rate,
`start=` pinned after cutover) + the tracker `<!-- soleur:followthrough … -->` directive
+ `follow-through` label, wired into `scheduled-followthrough-sweeper.yml`.

## Architecture Decision (ADR/C4)

- **ADR:** **Amend ADR-068** in the Phase-3 PR(s) (`wg-architecture-decision-is-a-plan-deliverable`; learning `2026-05-16-adr-amendment-required-when-reversing`): record the
  concrete coordinator (stateless mTLS control-forward + `isConversationLiveHere`
  two-registry predicate), the mTLS model (static self-signed CA), the per-workspace
  **fetch**-boundary cred + **push-key trust** rationale (Research-Reconciliation row),
  and flip **status `adopting`→`accepted`** when GA lands in prod. Do not create a new
  ADR — Phase 3 executes ADR-068's decision, it does not make a new one.
- **C4 views:** **No new authoring** — verified all three `.c4` files: `coordinator`
  (`model.c4:185`), `gitDataStore` (193), `sessionStore` (197), `scheduler` (189),
  `tunnel -> coordinator` (282), `coordinator -> claude/supabase` (299–300), all in
  `views.c4:34–35`. External actors/systems (Cloudflare tunnel, git-data host, 2nd
  Hetzner host) are already modeled. Phase 3 **verifies render** and refines the
  `coordinator` element **description** if the implementation adds detail; re-run
  `c4-code-syntax.test.ts` + `c4-render.test.ts` after any edit.
- **Sequencing:** the ADR is already authored (Phase 0); Phase 3 amends + flips status.
  Grep-sweep every phase-moved substrate label across plan+spec+ADR in one pass before
  `/work` (learning `2026-06-30-deepen-remap-leaves-stale-phase-labels`).

## Acceptance Criteria

### Pre-merge (per sub-PR)
- **AC1 (3.A)** — `terraform plan` shows **0 to destroy** for the `for_each`+`moved`
  refactor (jq assertion on `resource_changes`); `terraform validate` green; `SOLEUR_HOST_ID`
  injected in both `ci-deploy.sh` docker-run blocks.
- **AC2 (3.B)** — `isConversationLiveHere` detects BOTH a legacy-registry turn and a
  cc-only (`activeQueries`) turn (unit); a control op at a non-owning host forwards to
  the lease-holder and resolves there (integration); a forged/cross-tenant forwarded op
  is **rejected** at the owning host (negative); mTLS handshake with a bad client cert
  is refused (negative).
- **AC3 (3.C)** — host-A with tenant-A cred **cannot** fetch tenant-B git-data
  (negative, the §6 / AC4-epic invariant); non-member `resolve_workspace_installation_id`
  → NULL → fetch denied; in-sandbox push carries `lease-gen`; fence accepts equal-gen retry.
- **AC4 (3.D)** — reconnect after a lease move lands on the new lease-holder; grace-abort
  cancel stays host-local; a cross-host migration emits a non-transient close code and the
  client tears down + reconnects with **no fresh-session greeting**.
- **AC5 (3.E)** — tombstone-release preserves `lease_generation` across a real cross-host
  takeover (no fence false-reject); the 2-host `for_each` deploy delivers to both hosts.

### Post-merge (operator / soak — automate all that are automatable)
- **AC6** — Cutover executed: `git rev-list --all` count-match between old volume and
  git-data store **verified** before the flag flip (scripted; captured in PR/runbook).
- **AC7** — With the flag on, **two users on one workspace served by two different hosts
  each operate their own worktree without git-index corruption** (AC2-epic / G1 — the GA
  headline), observed live.
- **AC8** — A drain/deploy is invisible to an active user (AC5-epic / planned-move
  seamlessness), observed on the first 2-host deploy.
- **AC9** — Soak: ≥7 days ~50/50 host split, **zero** fence false-rejects, **zero**
  cross-tenant denials → then ADR-068 `accepted`, NFR-019 register flipped, #5274
  Phase-3 milestone closed. Enforced by the follow-through probe, not human memory.

## Test Scenarios (RED→GREEN)

Woven per sub-PR (3.6a–3.6e above). Deterministic-invocation discipline: security
invariants (cross-tenant fetch, forged control op) are asserted at the **tool/RPC entry
or captured-argv**, never through an LLM prompt (learning `2026-04-19-llm-sdk-security-tests-need-deterministic-invocation`). Integration tests run **DEV-only** (never synthetic
users against prod — `hr-dev-prd-distinct-supabase-projects`); prod verification is
read-only (Sentry queries, `pg_policy` shape, `rev-list` count).

## Risks & Mitigations

- **mTLS cert expiry = silent cascade** (external research). → log `notAfter` at startup;
  Sentry on `socket.authorizationError`; Better Stack cert-expiry monitor; long-lived
  (1yr) certs rotated via deploy.
- **Placement-group attach reboots the running host.** → maintenance-window apply;
  documented in Apply path; 2nd host absorbs if brought up first.
- **Cutover data loss / silent truncation.** → `rev-list --all` count-match gate before
  flip; rollback = flag off + re-drain; GitHub rehydration is the durable backstop.
- **Wrong-layer fix on a recurring cross-host symptom.** → before shipping any Phase-3
  fix, prove the changed path executes on the affected surface via Sentry breadcrumb
  (learning `2026-06-30-verify-the-fixed-code-path-executes`); zero events ⇒ re-trace.
- **Per-workspace cred design fork** (push-key trust vs fetch-boundary scoping) — the
  one genuinely open architectural sub-decision; resolve at deepen-plan with
  data-integrity-guardian + security-sentinel, record in the ADR amendment.
- **Coordinator as a new SPOF.** → stateless + N replicas behind the one tunnel (lease
  in Postgres); it is a router, not a state owner. Health-check + auto-restart the
  cloudflared + coordinator (single ingress point).

## Domain Review

_Populated after the Phase-2.5 domain leaders + GDPR gate run against this draft (next
step). Carry-forward from brainstorm §Domain Assessments: Engineering (CTO), Product
(CPO), Legal (CLO), platform-strategist all assessed at framing time._

## Open Code-Review Overlap

Two open `code-review` issues touch files Phase 3 edits (substring match; dispositions):
- **#3243** (arch: decompose `cc-dispatcher.ts` into focused modules) — **Acknowledge.**
  Phase 3 adds forward hooks to `cc-dispatcher.ts` but a decomposition refactor is out of
  scope and independent; note the added surface in the issue if it materially grows the file.
- **#2191** (refactor(ws): `clearSessionTimers` helper + timer jitter) — **Acknowledge.**
  Phase 3 touches `ws-handler.ts` reconnect/timer paths; if the reconnect-routing edit
  naturally passes through the disconnect timer, fold the helper extraction; else leave open.

## Open Questions (resolve at deepen-plan / /work Phase 0)

1. **App WS ingress location** — where does user WS traffic enter today (proxied DNS vs
   a tunnel config not in `tunnel.tf`)? Confirm before the tunnel→coordinator rewire.
2. **Per-workspace cred fork** — push-key trust boundary vs fetch-boundary scoping
   (Research-Reconciliation); resolve with security-sentinel + data-integrity-guardian.
3. **Coordinator topology** — distinct process/host vs co-located stateless replica on
   each web host; and replica count behind the tunnel.
4. **mTLS provisioning path** — cloud-init-delivered static CA + per-host certs via
   Doppler; confirm rotation story.
5. **`resolve_workspace_installation_id` reuse** — does it already return a usable
   per-workspace token for the git-data cred, or does Phase 3 define the first git-data
   call-site of that shape?

## Sharp Edges

- A plan whose `## User-Brand Impact` is empty/placeholder fails `deepen-plan` Phase 4.6
  — it is filled above (carried from brainstorm).
- The lease is used **unchanged** but exercised **live under contention for the first
  time** here — the tombstone-release monotonicity AC is not optional.
- `abortSession`'s count is legacy-only; the coordinator MUST OR it with
  `hasActiveCcQuery` or it silently mis-routes the dominant `cc-soleur-go` path.
- `moved`-block keys are immutable post-migration; picking the `for_each` map keys is a
  one-way decision.
