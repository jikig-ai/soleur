---
title: "Multi-host /workspaces — Phase 3: 2nd host + stateless coordinator (GA line)"
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
revision: v2 (2026-07-01, folded CTO + CLO/GDPR domain review)
---

# ✨ Multi-host `/workspaces` — Phase 3: 2nd host + stateless coordinator (GA line)

> **Resumed epic.** #5274 anchors the staged multi-host `/workspaces` layer
> (ADR-068, Approach A). Phases 0/1/2 merged and are **dark-launched behind
> `isGitDataStoreEnabled()`**. Phase 3 is the **GA line** (ADR-068 §8, OQ3 resolved
> by operator 2026-06-30). PR bodies use **`Ref #5274`** (never `Closes`) until
> Phase 4 completes the epic.

> **⚠ BLOCKING DESIGN DECISION (D0) — must resolve before Sub-PR 3.B is executable.**
> CTO domain review found the GA headline (AC7 — two users of one workspace served by
> two different hosts) is **structurally unreachable** with the substrate as drafted,
> because the single `worktree_write_lease (workspace_id, "primary")` lease cannot be
> both the session router and the write fence. See **§Architecture Decision → D0** and
> **§Open Decisions**. This plan carries a recommendation but the fork is an
> operator/deepen-plan call recorded as an **ADR-068 amendment**.

## Overview

Phase 3 makes the backend a **2-host cluster** and adds a **stateless coordinator**
that places/routes a session to the correct host and forwards cross-host control ops
(abort / gate-resolve / grace). It ships the two ADR-068 §6 security boundaries
(per-`workspace_id` git-data credential + coordinator↔host mTLS), lease-derived
affinity, and flips `isGitDataStoreEnabled()` on for the first time under real
contention via a hardened git-data cutover. It implements ADR-068 **§4** (coordinator
routing), **§5** (affinity + tunnel→coordinator rewire), and **§6** (cross-tenant
isolation), plus the 2nd-host IaC (`for_each` + `hcloud_placement_group type=spread`
+ `moved` blocks → 0-destroy).

**Not in Phase 3** (deferred per ADR-068 §8): Nomad, lease-expiry reclaim cron, and the
EU session-Redis replay buffer are **Phase 4a**; continuous worktree checkpoint of
*uncommitted* work is **Phase 4b**. The shared-git-data-host SPOF is an **accepted
GA-line residual** (honest reconnect + GitHub rehydration; #5723/Garage closes it
post-GA). **Do not introduce Redis in this phase.**

**Design authority.** ADR-068 is authoritative; this plan concretizes §4/§5/§6 and adds
two ADR-068 amendments (D0 routing authority; the mTLS/cred concretization). Phase-0–2
foundations are reused unchanged (`worktree-write-lease.ts`, `git-data-replication.ts`,
`host-identity.ts`, `git-auth.ts`, the pre-receive CAS fence, migration 116). The
coordinator + mTLS + per-workspace git-data cred are **built from scratch**.

## Research Reconciliation — Spec vs. Codebase

Verified against `origin/main` @ `02a206ad1` (2026-07-01) via four research agents +
CTO/CLO domain review. File paths are `apps/web-platform/server/*`.

| Claim (ADR / spec) | Codebase reality | Plan response |
|---|---|---|
| §4 "`abortSession` found-count" distinguishes "finished" vs "lives on another host." | Returns `number` (`agent-session-registry.ts:208`) but its docblock (193–206) warns it is **LEGACY-ONLY** — `cc-soleur-go` turns live in `activeQueries`, silent to this count. | Routing liveness predicate = `abortSession()>0 **OR** hasActiveCcQuery(convId)` (`cc-dispatcher.ts:2759`, exported). Build `isConversationLiveHere(userId, convId)`, call **before** any forward. |
| §4 the `(workspace_id,"primary")` lease routes the session. | **`worktree_id` is hardcoded `"primary"`** (`worktree-write-lease.ts:23`; every call site). One host holds it at a time (acquire = `gen+1` takeover). Routing by it pins a whole workspace to ONE host. | **D0 (blocking):** the `primary` lease is the **git-data write fence**, NOT the session router. Placement = per-conversation liveness + load. See §Architecture Decision. |
| §6 git-data access carries a per-`workspace_id` credential; "reuse `resolve_workspace_installation_id`." | `resolve-installation-id.ts:39` returns `Promise<number|null>` — a **GitHub App installation id**, not a git-data credential. git-data transport today is **one cluster-wide** SSH key (`gitWithPrivateKeyAuth`). | The RPC is a **shape** to reuse (membership-gated, NULL-for-non-member), not a token to pass. Phase 3 defines a **new per-workspace git-data cred primitive**. Threat-model scope (logic-bug vs host-compromise) stated in §Open Decisions (D2). |
| §6 the in-sandbox `GIT_PUSH_OPTION_*` injection is DEFERRED to Phase 3. | The in-sandbox agent pushes to **GitHub `origin`** (no fence hook, ignores push-options); git-data replication is **app-server-side** (`git-data-replication.ts`, Phase 2). | **Removed as dead config.** App-server replication already delivers to git-data with `lease-gen`. In-sandbox injection is only needed if a future design moves the git-data push into the sandbox — not this phase. (Resolves CTO P1-8.) |
| Encryption-at-rest on the git-data volume is a `.tf` edit (drafted in 3.C). | `hcloud_volume` has **no at-rest attribute** — Hetzner volumes aren't hypervisor-encrypted. Requires guest-side **LUKS** + key at boot; the Phase-2 volume already holds live bare repos. | Moved to **3.E cutover**: provision a **fresh LUKS volume** as the rsync target (avoids reformat-with-live-data + cleartext window). Key via Doppler env, never argv. (CLO TS-2 + CTO P1-7.) |
| Migration 116 release tombstones (not DELETE); fence = `reject gen<max`. | Confirmed (ADR amendment 2026-06-30). Fence enforces **generation** monotonicity, **not tenant identity**. | First **live** exercise under contention here. Fence does not authorize the pusher → cross-tenant **write** boundary is a separate control (D2 / CLO TS-1). |
| C4 models coordinator/gitDataStore/tunnel→coordinator (Phase 0). | Confirmed rendered: `model.c4:185/193/197/282`, `views.c4:34–35`. | **No new C4 authoring** — verify render + refine `coordinator` description; **amend ADR-068**. |
| Tunnel `service` target "becomes the coordinator." | `tunnel.tf` fronts only `deploy.`(:9000) + `ssh.`(:22) + 404 catch-all. **The app/WS ingress is NOT in this file.** | **D1 (blocking 3.E):** confirm where user WS traffic ingresses before the rewire. Do not assume `tunnel.tf` is the app front door. |
| No coordinator / cross-host RPC exists. | Confirmed. | Built from scratch. |

## User-Brand Impact

_Carried from the brainstorm §User-Brand Impact (threshold set with CPO/CLO/CTO)._

- **If broken:** a chat that greets fresh mid-work; an abort/stop that silently does
  nothing (turn runs on another host); "workspace unavailable" on reconnect — the #5240
  regressions this epic exists to prevent.
- **If it leaks:** cross-tenant git-data **read** (host A serving tenant B's repo),
  cross-tenant **write** (poisoning tenant B's history — arguably graver; see D2), a
  forged control op honored by an owning host, or cleartext coordinator↔host traffic.
- **Brand-survival threshold: single-user incident.** `requires_cpo_signoff: true`
  (CPO approved the approach at brainstorm; `user-impact-reviewer` runs each PR review).

## Architecture Decision (ADR/C4)

Phase 3 executes ADR-068 and adds **two amendments** (both authored in-PR, not deferred —
`wg-architecture-decision-is-a-plan-deliverable`).

### D0 — Placement authority ≠ write-fence authority (BLOCKING; CTO P0-1)

**Problem:** the single `(workspace_id,"primary")` lease cannot be both the session
router and the git-data fence; routing by it makes AC7 (concurrent two-host serving of
one workspace) unreachable.

**Recommendation (Option A — minimal, matches AC7 wording):** the coordinator routes by
**conversation liveness** for existing turns (`isConversationLiveHere` across hosts) and
by **load** for cold placement; the `primary` lease is reserved purely as the **git-data
push fence**. Two users → two hosts → each on own NVMe worktree (no shared index → AC7's
"no git-index corruption") → pushes serialize/namespace through the fence.
**Alternative (Option B):** make `worktree_id` **per-user/per-session** (the PK already
supports it; stop hardcoding `"primary"`) → independent lease + placement + fence stream
per user. Cleaner concurrency, larger change (fence is currently per-`(workspace,primary)`).

**Open sub-question folded into D0:** with per-user worktrees on shared git-data, do users
push **distinct refs** (per-user branches, fence per-ref) or serialize onto shared refs?
This determines whether the fence key is `(workspace, worktree)` or `(workspace, ref)`.
**Resolve at deepen-plan with `data-integrity-guardian` + `architecture-strategist`;
record the choice as an ADR-068 amendment before 3.B.**

### D-mTLS/cred amendment

Record the concrete coordinator (stateless mTLS control-forward + two-registry
`isConversationLiveHere` predicate), the mTLS model (static self-signed CA, **automated
rotation** — see 3.A/Risks), the per-workspace git-data **fetch** cred primitive + the
**push-key trust decision** (D2), and flip **status `adopting`→`accepted`** when GA lands.

### C4

**No new authoring** (all three `.c4` files read): `coordinator` (`model.c4:185`),
`gitDataStore` (193), `sessionStore` (197), `scheduler` (189), `tunnel -> coordinator`
(282), included in `views.c4:34–35`. External actors/systems (Cloudflare tunnel, git-data
host, 2nd host) already modeled. Phase 3 verifies render + refines the `coordinator`
description; re-run `c4-code-syntax.test.ts` + `c4-render.test.ts` after any edit.
Grep-sweep phase-label drift across plan+spec+ADR in one pass before `/work`.

## Implementation Phases

Five sequenced sub-PRs, each independently mergeable and **inert until 3.E flips the
flag**. RED→GREEN tests (task 3.6) woven per sub-PR. Every body uses `Ref #5274`.

### Sub-PR 3.A — Infra foundations: 2nd host + placement group + host_id + mTLS certs (dark)

Maps task **3.1**.

- **`for_each` refactor** (`server.tf:21`): `hcloud_server "web"` → indexed by
  `var.web_hosts`. `ignore_changes=[user_data,ssh_keys,image]` covers the force-replace
  attrs. `moved` blocks for the server, `hcloud_volume`+`hcloud_volume_attachment`
  (`server.tf:926–940`), **and all 8 sibling `terraform_data` provisioners**. Every
  remote-exec inline block starts `set -e` (learning `2026-06-10-terraform-remote-exec-gating`). Enumerate + replace positional Terraform readers via `terraform providers
  schema -json` (learning `2026-06-30-…positional-rule-readers`).
- **EU residency pin (CLO T-1, GA-blocking):** `var.web_hosts` entries constrain
  `location ∈ {nbg1,fsn1,hel1}` with an EU default; add a `terraform` `check` (or CI
  assertion in `infra-validation.yml`) that **rejects any non-EU location** for web hosts
  + coordinator + placement group. Enforced before `web-2` serves traffic (AC1 gate).
- **`hcloud_placement_group "spread"`** attached to both web hosts. **Gotcha:** attaching
  it to the *running* web host forces a power-off → maintenance-window apply (or bring the
  group up with `web-2` and stop-add the existing host). Max 10/group.
- **2nd host private-net attach** (`network.tf`, reserved IP e.g. `10.0.1.11`).
- **mTLS cert material (CTO P1-6 — contract before consumer):** static self-signed CA +
  per-host server cert + coordinator client cert via `tls_private_key` /
  `tls_self_signed_cert` / `tls_locally_signed_cert`, delivered by cloud-init + Doppler.
  Ships in **3.A** so certs exist before 3.B's `tls` server consumes them.
- **`SOLEUR_HOST_ID` injection** in `ci-deploy.sh` (canary + prod `docker run`):
  metadata-resolved (`169.254.169.254/hetzner/v1/metadata/instance-id` || `/etc/machine-id`).
  Without it `resolveHostId()` (`host-identity.ts:30`) fail-loud throws once flagged on.
  `ci-deploy.sh` is a `deploy_pipeline_fix` trigger → ship Phase-5.5 drift gate auto-applies.
- **RED→GREEN (3.6a):** `terraform plan -json | jq` 0-destroy assertion; **non-EU location
  rejected** (negative, T-1); `host-identity` metadata-resolve test; mTLS cert chain validates.

**Files:** edit `server.tf`, `network.tf`, `variables.tf`, `ci-deploy.sh`,
`infra-validation.yml`, `apply-web-platform-infra.yml`, `expenses.md`. Create
`placement-group.tf`, mTLS cert TF.

### Sub-PR 3.B — Coordinator: placement + control forwarding (gated on D0)

Maps task **3.2** + §4. **Do not start until D0 is resolved + ADR-amended.**

- **`server/session-coordinator.ts` (new):** stateless (lease in Postgres → N replicas
  safe). Placement per D0 (liveness + load, NOT the raw `primary` lease). Forwards control
  ops to the owning host: local resolve → not-found → **mTLS RPC-forward** → same resolver.
  Composes with the intra-host prefix broadcast (`agent-session-registry.ts:225`).
- **Unified liveness** `isConversationLiveHere(userId, convId)` = `abortSession(...)>0 ||
  hasActiveCcQuery(convId)`. Routes: **abort**, **gate-resolve** (`resolveCcBashGate`,
  `cc-dispatcher.ts:1414`), **grace** (stays host-local via affinity, 3.D).
- **Placement at the WS-upgrade handshake, not after** (fly-replay lesson): decide the
  owning host *before* upgrade; never upgrade-then-redirect.
- **mTLS coordinator↔host** (§6): Node `tls` server `requestCert:true,rejectUnauthorized:true`; control ports private-subnet only. **Owning host re-verifies the requester owns the
  target conversation/workspace by MEMBERSHIP** (not merely `assertHostIdNotUserId` shape —
  CLO AP-2) before honoring a forwarded op.
- **RED→GREEN (3.6b):** two-registry liveness (legacy-only turn AND cc-only turn detected);
  forward-on-not-found resolves at owner; **cross-tenant forge** (host A forwards an op for
  tenant B's conversation) rejected at owner (negative, AP-2); bad-cert mTLS refused (negative).

**Files:** create `session-coordinator.ts`, mTLS load helper; edit `ws-handler.ts`,
`cc-dispatcher.ts` (gate-resolve forward), `agent-runner.ts` (abort forward).

### Sub-PR 3.C — Cross-tenant isolation: per-workspace git-data fetch credential

Maps task **3.3** + the §6 fetch boundary + D2.

- **`server/git-data-client.ts` (new):** a **new per-`workspace_id` git-data credential
  primitive** gating the **fetch/clone** path (2nd host reading shared git-data — the
  boundary bwrap cannot cover, `agent-runner-sandbox-config.ts:106`). Authorized via the
  `resolve_workspace_installation_id` **membership shape** (NULL→deny), NOT by passing the
  installation id as the credential.
- **D2 threat-model statement (CLO TS-1 + CTO P1-2):** the **push** path retains the
  cluster-wide transport key; the fence enforces gen-monotonicity, **not pusher identity**.
  State scope: the app-side membership check closes the **logic-bug** cross-tenant case; it
  does **not** close **host-compromise**. If host-compromise is in scope (single-user leak
  threshold suggests it is), enforcement must move to the git-data host — per-workspace
  forced-command authz on `upload-pack`/`receive-pack` (mirroring the provisioning wrapper,
  ADR amendment 2026-07-01) or per-workspace push keys. **Resolve before the 3.E flip;
  do not carry as an unmanaged "open."**
- **Clone-from-git-data when flag on:** `ensure-workspace-repo.ts` clones from `git-data`,
  retaining `origin`→GitHub (never orphan — rehydration backstop).
- **RED→GREEN (3.6c):** host-A + tenant-A cred **cannot read** tenant-B git-data
  (negative, AC4-epic); **cannot write** tenant-B git-data (negative — CLO TS-1, the push
  boundary); non-member RPC→NULL→fetch denied.

**Files:** create `git-data-client.ts`; edit `ensure-workspace-repo.ts`,
`git-data-replication.ts` (cred plumbing), + (if D2 → host-side) `git-data-provision.sh`
sibling authz wrapper.

### Sub-PR 3.D — Affinity + reconnect routing

Maps task **3.5** + §5.

- **Reconnect routes to the owning host** (coordinator), keeping grace-abort cancel
  **host-local** (the Phase-1 `sessions.get(uid)` guard stays correct because affinity
  lands the reconnect on the owner — no cross-host poll, no TOCTOU).
- **WS close-code for cross-host migration** (learning `2026-03-27-websocket-close-code-routing`): a session that must move emits a **non-transient** close code the client routes on
  (quiet teardown + reconnect via the new owner), never retry-in-place. Client gates on
  **materialization proof**, not a session-origin proxy (learning `2026-06-15-…materialization-proof`).
- **RED→GREEN (3.6d):** reconnect after a move lands on the new owner; grace cancel stays
  host-local; migration close-code tears down + reconnects with no fresh greeting.

**Files:** edit `ws-handler.ts`, `ws-client.ts`, `session-coordinator.ts`.

### Sub-PR 3.E — Cutover + GA flip (LUKS volume, freeze-rsync, coordinated flip, legal lockstep)

Maps **cutover** (carried from Phase 2 per operator) + **3.1 tunnel** + GA.

- **Confirm the app WS ingress (D1)** before the `tunnel.tf` `service`→coordinator rewire.
- **Hardened cutover (CTO P1-4, CLO DL-2):**
  1. **Fresh LUKS-encrypted git-data volume** as the rsync target (CLO TS-2 / CTO P1-7);
     key from Doppler env at boot, never argv.
  2. **git-data write-freeze** around the copy: two-pass rsync (bulk, then final delta
     under freeze) — the real writers are per-turn `syncPush`, not just crons.
  3. **Set-identity verify, not count-match:** `git for-each-ref` diff **and**
     `git rev-list --all | sort | sha256sum` equal on both sources (count-match is weak).
  4. **Coordinated cross-host flag flip:** Doppler propagation to two containers is not
     atomic → both hosts drain+reload together (or a brief both-quiesced flip). The "one
     switch flips atomically" claim is false across a fleet.
  5. If automated as a scheduled apply, **Inngest-dispatches-GHA** (cloud-admin creds off
     the app host — learning `2026-06-02-inngest-dispatches-gha`), never in-process terraform.
  6. **Rollback = flag off + re-drain**, which loses post-flip git-data writes — it works
     only because pushed refs are also on GitHub `origin` (rehydration). State this dependency.
  7. **Old-volume decommission/wipe** step (CLO DL-2); during the dual-existence window,
     Art. 17 erasure targets **both** locations.
- **Art. 17 bare-repo erasure (CLO DL-1, Critical):** add a workspace/account-delete step
  that removes the per-workspace bare repo on the git-data host over the private-net
  provisioning path (mirror the attachments purge `account-delete.ts:152`; a `remove`
  forced-command counterpart to `git-data-provision.sh`). FK cascade does NOT reach the
  filesystem. **Erasure-reach AC required.**
- **Legal-doc lockstep (CLO AP-3, mandatory pre-merge):** amend `article-30-register.md`
  (PA-1(e)/PA-2(e) recipients += `web-2`+coordinator EU-pinned; PA-1(g)/PA-2(g) TOMs +=
  mTLS, per-workspace fetch cred, at-rest encryption, owning-host re-verify);
  `privacy-policy.md` + `gdpr-policy.md` + `data-protection-disclosure.md` Last-Updated +
  repin `LEGAL_DOC_SHAS`; `compliance-posture.md` Hetzner DPA row += `web-2`+git-data.
  **No `TC_VERSION` bump** (no new purpose/data-category/sub-processor).
- **NFR register:** NFR-019 N/A→achieved + repoint ADR-027→ADR-068; NFR-026 flips
  "achieved" **only after LUKS mechanism verified** (not intent). **ADR-068** `adopting`→`accepted`.
- **Review set:** add **`deployment-verification-agent`** (CTO gap) for the pre/post-deploy
  checklist + verification queries + rollback, alongside security-sentinel,
  data-integrity-guardian, observability-coverage-reviewer, user-impact-reviewer.
- **RED→GREEN (3.6e):** AC7 headline (two users/two hosts/one workspace, no index
  corruption); drain/deploy invisible-modulo-stream-re-render (AC8, reconciled below);
  tombstone-release preserves fence token across a real takeover; reclaim→first-push
  ordering (P2-9).

**Files:** edit `tunnel.tf`, `nfr-register.md`, ADR-068, the 4 legal docs +
`compliance-posture.md`, cutover script, `expenses.md`.

## Infrastructure (IaC)

Fires Phase-2.8 (2nd host, placement group, coordinator, tunnel rewire, mTLS, LUKS,
`SOLEUR_HOST_ID`). Lands in `apps/web-platform/infra/` (AP-001; `infra-validation.yml`
covers `terraform validate`).

### Terraform changes
- **Edit:** `server.tf` (`for_each`+`moved`), `network.tf` (2nd-host attach + placement
  group), `tunnel.tf` (service→coordinator), `variables.tf` (`var.web_hosts` map w/ EU
  location, coordinator + mTLS vars), `ci-deploy.sh` (`SOLEUR_HOST_ID`), `infra-validation.yml` (EU-location check).
- **Create:** `placement-group.tf`, `coordinator.tf` (+ `cloud-init-coordinator.yml` if
  distinct process), mTLS CA/cert TF, fresh **LUKS** git-data volume TF (3.E target).
- **Sensitive vars:** mTLS keys + LUKS key via `tls`/`random` → `doppler_secret` → runtime
  **env, never argv** (#5560). `terraform.tfstate` (R2) holds TLS + LUKS keys plaintext →
  treat as secret-bearing; R2 credential scope is the control (ADR §7).

### Apply path
Cloud-init + idempotent bootstrap for `web-2`. The `placement_group` attach on the
**running** web host forces a power-off → **maintenance-window apply** (or bring the group
up with `web-2` and stop-add the existing host). `moved` verified `0 to destroy` before
apply. **Never rename `for_each` keys post-migration** (forces replace).

### Distinctness / drift safeguards
`dev != prd`. EU-location `check`/CI gate (T-1). `receive.advertisePushOptions` already set.

### Vendor-tier reality check
No new sub-processor (self-hosted Hetzner EU). `hcloud_placement_group` free (max 10/group,
2 used). 2nd `hcloud_server` ≈ €15/mo + LUKS volume — record in `expenses.md` before
PR-ready (`wg-record-recurring-vendor-expense-before-ready`); verify Hetzner pricing at the
provider page before the 3.A budget line.

## Observability

```yaml
liveness_signal:
  what: coordinator route decisions (op control_plane_route) + worktree_lease acquire/reclaim; per-host heartbeat
  cadence: per control-op + per lease heartbeat (25s)
  alert_target: Better Stack monitor on coordinator route-error rate; Sentry alert on control_plane_route failures
  configured_in: apps/web-platform/infra/sentry/*.tf (op contract) + Better Stack monitor TF
error_reporting:
  destination: Sentry (feature tags control_plane_route, worktree_lease)
  fail_loud: yes — fence rejects, mTLS handshake failures, cross-tenant cred denials captureException fail-loud
failure_modes:
  - mode: control op at non-owning host and forward fails (owner down / mTLS reject)
    detection: control_plane_route event {source_host, owner_host, op, forward_result} — in-surface structured fields discriminating local-resolve vs forward-fail vs owner-not-found (blind-surface probe, learning 2026-07-01)
    alert_route: Sentry + Better Stack
  - mode: cross-tenant git-data cred denial (non-member RPC → NULL)
    detection: git-data event {workspace_id_hash, member:false}
    alert_route: Sentry (security)
  - mode: mTLS cert expiry (silent cascade)
    detection: startup notAfter log + Sentry socket.authorizationError; auto-rotation liveness
    alert_route: Better Stack cert-expiry monitor + Sentry
  - mode: fence false-reject after cutover (non-monotonic gen)
    detection: pre-receive reject → Sentry worktree_lease event {stored_max, pushed_gen}
    alert_route: Sentry (GA-gating during soak)
logs:
  where: Sentry breadcrumbs + structured JSON to Better Stack; no host-local-only logs on the control path
  retention: per Better Stack retention (≤ conversation retention for any user-content-adjacent field)
discoverability_test:
  command: "Sentry API query for op:control_plane_route on the affected workspace (documented in runbook) — NO ssh"
  expected_output: control_plane_route events present with discriminating fields; zero events on a changed forward path after deploy ⇒ wrong layer (learning 2026-06-30-verify-fixed-code-path-executes)
```

**Affected-surface (§2.9.2):** coordinator, Cloudflare tunnel connector, and in-sandbox
agent are blind surfaces — each failure mode's `detection` names an in-surface structured
probe whose fields discriminate all hypotheses in one event, not a boolean. No SSH in any
runbook (`hr-no-ssh-fallback-in-runbooks`).

**Soak follow-through (§2.9.1):** GA close is soak-gated — **≥7 days ~50/50 two-host split,
zero fence false-rejects, zero cross-tenant denials** before ADR-068 flips `accepted` /
#5274 Phase-3 milestone closes. Enroll `scripts/followthroughs/phase3-ga-soak-5274.sh`
(Sentry-rate, `start=` pinned after cutover) + tracker directive + `follow-through` label
in `scheduled-followthrough-sweeper.yml`.

## Acceptance Criteria

### Pre-merge (per sub-PR)
- **AC1 (3.A)** — `terraform plan` shows **0 to destroy** (jq on `resource_changes`);
  `terraform validate` green; a **non-EU `web_hosts`/coordinator location is rejected** by
  the check/CI gate (T-1); `SOLEUR_HOST_ID` injected in both docker-run blocks; mTLS cert
  chain validates.
- **AC2 (3.B, gated on D0)** — `isConversationLiveHere` detects BOTH a legacy-registry and
  a cc-only turn; a control op at a non-owning host forwards + resolves at the owner; a
  **cross-tenant forged** forwarded op is rejected at the owner (membership re-verify, AP-2);
  bad-cert mTLS refused.
- **AC3 (3.C)** — host-A + tenant-A cred **cannot read** tenant-B git-data (negative); **cannot
  write** tenant-B git-data (negative — TS-1 push boundary); non-member RPC→NULL→fetch denied.
- **AC4 (3.D)** — reconnect after a lease move lands on the new owner; grace cancel stays
  host-local; cross-host migration close-code → teardown+reconnect, **no fresh greeting**.
- **AC5 (3.E)** — tombstone-release preserves `lease_generation` across a real cross-host
  takeover (no fence false-reject); reclaim→first-push ordering holds under contention (P2-9);
  the 2-host `for_each` deploy delivers to both hosts.

### Post-merge (operator / soak — automate all automatable; verify read-only)
- **AC6** — Cutover executed: **set-identity** verify (`for-each-ref` diff + `rev-list|sort|sha256sum`) between old volume and the fresh **LUKS** git-data volume before the flip; git-data
  write-freeze held around copy+verify+flip; coordinated cross-host flip; **old volume
  decommissioned/wiped**; rollback dependency (GitHub rehydration) documented.
- **AC7** — Flag on: **two users on one workspace served by two different hosts each operate
  their own worktree without git-index corruption** (G1 — the GA headline; requires D0
  resolved).
- **AC8** — A drain/deploy causes **no fresh-session greeting**; a brief stream re-render on
  the migrated turn is acceptable at GA (the ADR-059 replay buffer that would make it fully
  seamless is Phase 4a — CTO P1-5). Do NOT assert "invisible" beyond this.
- **AC9 (Art. 17)** — deleting a workspace/account **removes the per-workspace git-data bare
  repo** on the git-data host (erasure-reach test; DL-1).
- **AC10 (legal lockstep)** — Article 30 register + 3 privacy docs + `compliance-posture.md`
  updated; `LEGAL_DOC_SHAS` repinned; Eleventy mirrors synced (AP-3).
- **AC11 (soak)** — ≥7 days ~50/50 split, zero fence false-rejects, zero cross-tenant
  denials → ADR-068 `accepted`, NFR-019/NFR-026 register flipped (NFR-026 only after LUKS
  verified), #5274 Phase-3 milestone closed. Enforced by the follow-through probe.

## Test Scenarios (RED→GREEN)

Per sub-PR (3.6a–3.6e). Security invariants (cross-tenant read/write, forged control op)
asserted at the **tool/RPC entry or captured-argv**, never through an LLM prompt (learning
`2026-04-19-llm-sdk-security-tests-need-deterministic-invocation`). Integration tests
**DEV-only** (`hr-dev-prd-distinct-supabase-projects`); prod verification read-only (Sentry
queries, `pg_policy`, `rev-list`).

## Risks & Mitigations

- **D0 unresolved ⇒ AC7 unreachable.** Blocking; resolve + ADR-amend before 3.B.
- **Cross-tenant WRITE via cluster-wide push key** (TS-1/D2). Fence guards gen, not identity;
  resolve the threat-model + enforcement before the flip.
- **mTLS cert expiry = control-plane outage = silent-abort regression** (CTO P1-3). →
  **automated** scheduled regen+redeploy inside validity (Inngest-dispatches-GHA), not
  "rotated via deploy"; startup `notAfter` log + Sentry `authorizationError` + Better Stack;
  record the no-CRL revocation residual (private-net, no-public-ingress control port).
- **Cutover data loss / split-store** (CTO P1-4). → LUKS fresh target, freeze-rsync,
  set-identity verify, coordinated flip, GitHub-rehydration rollback backstop, old-volume wipe.
- **Encryption-at-rest is a data-migration** (TS-2/P1-7). → fresh LUKS volume as rsync target
  in 3.E, not an in-place edit in 3.C.
- **Art. 17 gap on bare repos** (DL-1). → private-net remove step; erasure-reach AC.
- **Placement-group attach reboots the running host.** → maintenance-window apply.
- **Coordinator as new SPOF.** → stateless + N replicas behind the tunnel; health-check +
  auto-restart cloudflared + coordinator.
- **Wrong-layer fix on a recurring cross-host symptom.** → Sentry breadcrumb exec-path proof
  before shipping any Phase-3 fix (learning `2026-06-30-verify-fixed-code-path-executes`).

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO), Operations/Finance (cost — ADR-sized),
Product (NONE — no user-facing UI surface; reconnect UX preserved, backend routing only).

### Engineering (CTO)
**Status:** reviewed. **Verdict: REVISE → conditions folded above.**
P0-1 (D0 routing authority) — folded as the blocking §Architecture Decision D0. P1-2
(fetch cred / threat model) → D2 + Research Reconciliation. P1-3 (mTLS auto-rotation) →
Risks + 3.A. P1-4 (cutover hardening) → 3.E. P1-5 (AC8 reconcile) → AC8. P1-6 (mTLS certs
→ 3.A) → 3.A. P1-7 (at-rest = data-migration) → 3.E LUKS. P1-8 (in-sandbox push-option dead
config) → removed. P2-9 (reclaim→first-push ordering) → AC5. Capability gap
(`deployment-verification-agent` on 3.E) → 3.E review set.

### Legal (CLO) / GDPR
**Status:** reviewed (advisory, not legal advice). **Verdict: NOT GA-ready as drafted;
conditional on four closures — folded.** T-1 (EU pin + CI gate) → 3.A/AC1. TS-1 (cross-tenant
write) → D2/AC3. TS-2 (LUKS mechanism) → 3.E/AC6. DL-1 (Art. 17 bare-repo erasure) → 3.E/AC9.
DL-2 (old-volume decommission) → 3.E/AC6. AP-2 (membership re-verify) → 3.B/AC2. AP-3 (Article
30 + 3-doc + posture lockstep) → 3.E/AC10. **Operator-acknowledged Criticals** (→
`compliance-posture.md` Active Items + `compliance/critical` issue): **TS-1, T-1, DL-1** —
all must gate the 3.E flag flip.

### Product/UX Gate
**Tier:** NONE. No user-facing page/flow/component created or modified (Files lists contain
no UI-surface path); the #5240 reconnect contract is preserved, not redesigned.

## Open Code-Review Overlap
- **#3243** (decompose `cc-dispatcher.ts`) — **Acknowledge** (independent refactor; note added surface).
- **#2191** (`clearSessionTimers` helper in `ws-handler.ts`) — **Acknowledge** (fold the
  helper if the reconnect-routing edit passes through the disconnect timer; else leave open).

## Open Decisions (resolve at deepen-plan / architecture, BEFORE the gated sub-PR)
1. **D0 (blocks 3.B)** — placement authority vs write fence (Option A recommended); + the
   per-user-ref-vs-serialized-ref sub-question. Record as an ADR-068 amendment.
2. **D1 (blocks 3.E)** — where the app WS ingress enters today (before the tunnel rewire).
3. **D2 (blocks 3.E flip)** — cross-tenant **write** threat-model scope (logic-bug vs
   host-compromise) + enforcement locus (app-side vs git-data-host forced-command authz).
4. **Coordinator topology + replica count** (distinct host vs co-located stateless replica —
   co-located inherits the EU pin and is simplest).
5. **mTLS provisioning + automated rotation** path (cloud-init CA + Doppler; Inngest-GHA rotation).

## Sharp Edges
- The `## User-Brand Impact` section is filled (carried from brainstorm) — do not empty it.
- The lease is used **unchanged** but exercised **live under contention for the first
  time**; the tombstone-release monotonicity AC is not optional.
- `abortSession`'s count is legacy-only; the coordinator MUST OR it with `hasActiveCcQuery`.
- `moved`-block `for_each` keys are immutable post-migration (one-way decision).
- "Encryption-at-rest" is guest-side LUKS, not an `hcloud_volume` attribute.
- The CAS fence guards generation, not tenant identity — the cross-tenant write boundary is
  a separate control (D2).
