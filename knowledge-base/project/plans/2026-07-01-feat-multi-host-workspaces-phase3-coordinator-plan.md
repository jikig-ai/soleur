---
title: "Multi-host /workspaces — Phase 3: 2nd host + user-sticky router (GA line)"
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
status: ready
revision: v4 (2026-07-01 — deepen-plan resolved D0-ref/D1/D2; v3 chose user-sticky + folded CTO/CLO/DHH/Kieran/simplicity)
---

# ✨ Multi-host `/workspaces` — Phase 3: 2nd host + user-sticky router (GA line)

> **Resumed epic.** #5274 anchors the staged multi-host `/workspaces` layer
> (ADR-068, Approach A). Phases 0/1/2 merged, dark-launched behind
> `isGitDataStoreEnabled()`. Phase 3 is the **GA line** (ADR-068 §8). PR bodies use
> **`Ref #5274`** until Phase 4 completes the epic.

> **Architecture chosen (operator, 2026-07-01): USER-STICKY routing.** A session is
> routed to its owning host via a **per-user worktree lease** (`worktree_id` becomes
> per-user; stop hardcoding `"primary"`). Two users of one workspace **can** span two
> hosts (ADR-068 G1 satisfied) — but each conversation's control ops (abort/gate/grace)
> are **sticky to one host**, so there is **no cross-host control-op forwarding plane,
> no two-registry union-forward, no mTLS-RPC.** This resolves the CTO's D0 fork and is
> recorded as an **ADR-068 amendment**. (Alternatives considered: workspace-sticky —
> re-scopes G1; coordinator-forwarding — the drafted plane, rejected as over-built for
> the goal by CTO/DHH/simplicity.)

## Enhancement Summary (deepen-plan, 2026-07-01)

Deepened after the operator chose user-sticky routing. Four focused agents (data-integrity,
security, infra-precedent, ingress/L3) + the mandatory gates (User-Brand Impact ✓,
Observability ✓, PAT-var ✓). **All three open decisions are now RESOLVED** (see §Resolved
Decisions) and the load-bearing findings are folded in:

1. **D0-ref → distinct per-user refs**, and the *current* replication refspec is proven to
   **silently clobber commits under a 2nd writer** — the namespaced-refspec change is now a
   hard 3.B prerequisite, not a "nice to have."
2. **D1 → the app ingress is `dns.tf` (proxied A record), not the tunnel** — the rewire target
   is corrected across §3.D + IaC.
3. **D2 → app-side write sentinel gates the flip; host-compromise write is an accepted,
   tracked GA residual** (proportionate to the mTLS downgrade).
4. **Precedent-diffs:** LUKS + one-way-TLS are novel (idempotent guard; CA-pinning), and the
   `for_each` refactor needs cloud-init for `web-2` (SSH-provisioner reachability).

Migration 116 supports per-user `worktree_id` with **zero schema change** — the entire D0
mechanism is app-layer. No new blocking decisions remain; the plan is `/work`-ready.

## Overview

Phase 3 makes the backend a **2-host cluster** and adds a **stateless, co-located
sticky router**: each host proxies an inbound session to the host that owns the
conversation's per-user worktree lease, over the private net. It ships the two ADR-068
§6 security boundaries (per-`workspace_id` git-data fetch authorization + one-way TLS
on the host↔host proxy), lease-derived reconnect affinity, and flips
`isGitDataStoreEnabled()` on for the first time via a hardened git-data cutover. It
implements ADR-068 **§4** (routing — now user-sticky, no forwarding), **§5** (affinity
+ ingress→router rewire), and **§6** (cross-tenant isolation), plus the 2nd-host IaC
(`for_each` + `hcloud_placement_group type=spread` + `moved` → 0-destroy).

**Not in Phase 3** (deferred per ADR-068 §8): Nomad, lease-expiry reclaim cron, EU
session-Redis replay buffer → **Phase 4a**; continuous worktree checkpoint → **Phase
4b**. The shared-git-data-host SPOF is an **accepted GA-line residual** (honest
reconnect + GitHub rehydration; #5723 closes it post-GA). **No Redis in this phase.**

**Design authority.** ADR-068 is authoritative; this plan adds two amendments (D0
routing = user-sticky; the TLS/cred concretization). Phase-0–2 foundations are reused;
the one foundational change is **per-user `worktree_id`** (the lease PK already supports
it). The router + host↔host proxy + per-workspace fetch authorization are new.

## Research Reconciliation — Spec vs. Codebase

Verified against `origin/main` @ `02a206ad1` (2026-07-01); all plan anchors confirmed
accurate by Kieran review. Paths are `apps/web-platform/server/*`.

| Claim (ADR / spec) | Codebase reality | Plan response |
|---|---|---|
| §4 the `(workspace_id,"primary")` lease routes the session. | `worktree_id` hardcoded `"primary"` (`worktree-write-lease.ts:23`); one host holds it (acquire = `gen+1` takeover) → routing by it pins a whole workspace to one host (CTO P0-1). | **Resolved (user-sticky):** `worktree_id` becomes **per-user**; each user's session routes to the host holding **their** worktree lease. Two users → two leases → two hosts. The router is sticky, not a forwarder. |
| §4 `abortSession` found-count distinguishes finished vs. lives-elsewhere; §4 forwards control ops cross-host. | `abortSession` (`agent-session-registry.ts:208`) is LEGACY-ONLY (docblock 193–206); cc turns live in `activeQueries` (`hasActiveCcQuery`, `cc-dispatcher.ts:2759`). | **No cross-host forwarding needed** under user-sticky: a conversation's control frames route to its owning host by sticky routing, so abort/gate/grace resolve **locally** on arrival. The union predicate is a **local** lookup (which of my host's registries owns this conv), not a cross-host forward. |
| §6 "reuse `resolve_workspace_installation_id`" as a per-workspace git-data credential. | `resolve-installation-id.ts:39` returns a GitHub App **installation id** (number|null), not a git-data cred; git-data transport is one cluster-wide SSH key. | It is a **membership shape** to reuse (NULL→deny). 3.C adds a **membership-gated fetch authorization** on the existing transport — not a new per-workspace secret (simplicity de-inflation). Host-compromise enforcement locus is **D2** (open). |
| §6 in-sandbox `GIT_PUSH_OPTION_*` deferred to Phase 3. | In-sandbox agent pushes to GitHub `origin` (ignores push-options); git-data replication is app-server-side (Phase 2). | **Removed as dead config** (CTO P1-8). |
| Encryption-at-rest = `.tf` edit. | `hcloud_volume` has no at-rest attribute; needs guest-side **LUKS**; Phase-2 volume holds live repos. | **3.D cutover:** fresh **LUKS** volume as rsync target; Doppler-env key at boot (CLO TS-2 / CTO P1-7). |
| §6 mTLS coordinator↔host. | No host↔host channel exists. Under user-sticky the only host↔host traffic is the **WS proxy** to the owning host (carries user content → needs in-transit encryption, CLO NFR-026). | **One-way TLS** (server cert on each host) for the proxy — encryption in transit satisfied. **Mutual/client certs dropped** (over-built for 2 owned hosts; DHH/simplicity). Long-lived self-signed server cert → no rotation cron. |
| Migration 116 fence = `reject gen<max`, per-`(workspace,worktree)`. | Confirmed; fence is **already per-worktree** (ADR §3), so per-user `worktree_id` aligns natively. Fence enforces generation, not tenant identity. | Per-user worktree → per-user fence stream. Cross-tenant **write** identity boundary is a separate control (D2 / CLO TS-1). |
| C4 models coordinator/gitDataStore/tunnel→coordinator (Phase 0). | Confirmed (`model.c4:185/193/197/282`, `views.c4:34–35`). | Verify render; refine the `coordinator` description to "sticky router (co-located, N)"; **amend ADR-068**. |
| Tunnel `service` = coordinator. | `tunnel.tf` fronts only `deploy.`/`ssh.`/404. **App/WS ingress is not in this file.** | **D1 (blocks 3.D):** confirm app WS ingress before the rewire. |
| ADR-068 number is unique. | **Collision:** `ADR-068-graceful-cron-drain-before-container-swap.md` also exists (Kieran P2-8). | **Fix task in 3.A:** renumber the cron-drain ADR (later/smaller) to the next free ordinal; sweep references. |

## User-Brand Impact

_Carried from the brainstorm (threshold set with CPO/CLO/CTO)._
- **If broken:** fresh-session greeting mid-work; a silent abort (turn survives on the
  wrong host); "workspace unavailable" on reconnect — the #5240 regressions.
- **If it leaks:** cross-tenant git-data **read** or **write** (D2), or cleartext
  host↔host proxy traffic.
- **Threshold: single-user incident.** `requires_cpo_signoff: true` (CPO approved the
  approach at brainstorm; `user-impact-reviewer` runs each PR review).

## Architecture Decision (ADR/C4)

Two ADR-068 amendments, authored in-PR (`wg-architecture-decision-is-a-plan-deliverable`).

### D0 — RESOLVED: user-sticky placement via per-user worktree lease
The session router places a session on the host holding that **user's** worktree lease
(`worktree_id` per-user; the migration-116 PK `(workspace_id, worktree_id)` already
supports it — stop hardcoding `"primary"`). Placement authority = per-user lease; the
same lease is that user's git-data write fence. **No decoupling, no cross-host control
forwarding.** The router is a co-located stateless reverse-proxy: inbound WS on any host
→ look up the conversation's owning host from the lease → local ⇒ serve; remote ⇒ proxy
over one-way-TLS private net. Cold session → the placing host acquires the user's lease
and becomes owner.

**Open sub-question (deepen-plan, `data-integrity-guardian`):** with per-user worktrees
on shared git-data, do users push **distinct per-user refs** (fence per-ref, both visible
via refs) or **serialize onto a shared ref**? The fence is already per-`(workspace,
worktree)`; the ref-namespacing choice determines cross-user visibility semantics.
Record with the D0 amendment.

### D-TLS/cred amendment
Record the co-located sticky router, the **one-way TLS** host↔host proxy (server cert,
long-lived self-signed, no mutual cert), the per-workspace git-data **fetch
authorization** (membership-gated), the **push-key trust decision** (D2), and flip
ADR-068 **status `adopting`→`accepted`** when GA lands.

### C4
**No new authoring** (all three `.c4` read): `coordinator` (`model.c4:185`),
`gitDataStore` (193), `sessionStore` (197), `tunnel -> coordinator` (282), in
`views.c4:34–35`. Refine the `coordinator` description to "co-located sticky router";
re-run `c4-code-syntax.test.ts` + `c4-render.test.ts`. Grep-sweep phase-label drift
before `/work`.

## Implementation Phases

**Four** sequenced sub-PRs (3.D affinity merged into 3.B per simplicity), each
independently mergeable and **inert until 3.D flips the flag**. RED→GREEN woven per
sub-PR. Every body uses `Ref #5274`.

### Sub-PR 3.A — Infra foundations: 2nd host + placement group + host_id + proxy TLS + erasure wrapper (dark)

Maps task **3.1** (+ the Art. 17 host wrapper foundation + ADR renumber).

- **`for_each` refactor** (`server.tf:21`): `hcloud_server "web"` → indexed by
  `var.web_hosts`; `ignore_changes=[user_data,ssh_keys,image]` covers force-replace.
  `moved` blocks for the server, `hcloud_volume`+`hcloud_volume_attachment`
  (`server.tf:926–940`), and **all 8 sibling `terraform_data` provisioners**. Every
  remote-exec inline starts `set -e` (learning `2026-06-10`). Replace positional
  Terraform readers via `terraform providers schema -json` (learning `2026-06-30-…positional-rule-readers`).
- **EU residency pin (CLO T-1, GA-blocking):** `var.web_hosts` constrains
  `location ∈ {nbg1,fsn1,hel1}`, EU default; a `terraform check` / `infra-validation.yml`
  assertion **rejects any non-EU** web host + placement group. Enforced before `web-2` serves (AC1).
- **`hcloud_placement_group "spread"`** on both web hosts. **Gotcha:** attaching to the
  *running* host forces a power-off → maintenance-window apply.
- **2nd host private-net attach** (`network.tf`, reserved IP e.g. `10.0.1.11`).
- **Host↔host proxy TLS material (contract before consumer):** long-lived self-signed
  **server** cert per host via `tls_private_key`/`tls_self_signed_cert`, cloud-init +
  Doppler. One-way (no client cert). Ships in 3.A so the proxy server exists before 3.B.
- **`SOLEUR_HOST_ID` injection** in `ci-deploy.sh` (canary + prod `docker run`):
  metadata-resolved (`169.254.169.254/hetzner/v1/metadata/instance-id` || `/etc/machine-id`); else `resolveHostId()` (`host-identity.ts:30`) fail-loud throws when flagged on.
  `ci-deploy.sh` is a `deploy_pipeline_fix` trigger → Phase-5.5 drift gate auto-applies.
- **2-host deploy fan-out (Kieran P1-3):** `ci-deploy.sh` / `apply-web-platform-infra.yml`
  deploys the container to **both** hosts (drain-both, deliver-both) — AC5 depends on it.
- **Art. 17 host wrapper (Kieran P0-1, CLO DL-1 — must pre-exist for 3.D):** a cloud-init
  `git-data-remove` **forced-command** wrapper on the git-data host (sibling to
  `git-data-provision.sh`; same CWE-22 validation; `rm -rf` the validated
  `<workspace_id>.git` under the repo root). Cloud-init ONLY (ADR provisioning-amendment
  mandate). The app-side call lands in 3.D.
- **ADR renumber (Kieran P2-8):** renumber `ADR-068-graceful-cron-drain…` to the next
  free ordinal; grep-sweep references.
- **RED→GREEN (3.6a):** `terraform plan -json | jq` 0-destroy; **non-EU location rejected**
  (negative, T-1); `host-identity` metadata-resolve test; server-cert chain validates.

**Files:** edit `server.tf`, `network.tf`, `variables.tf`, `ci-deploy.sh`,
`infra-validation.yml`, `apply-web-platform-infra.yml`, `expenses.md`, the cron-drain ADR
(renumber). Create `placement-group.tf`, proxy-TLS cert TF, `git-data-remove.sh` +
its cloud-init wiring.

### Sub-PR 3.B — User-sticky router + per-user lease + reconnect affinity (gated on D0-amendment)

Maps tasks **3.2 + 3.4 + 3.5**.

- **Per-user `worktree_id`** — stop hardcoding `"primary"` (`worktree-write-lease.ts:23`;
  migration-116 PK already supports it, **zero schema change**); thread a CWE-22-validated
  per-user worktree id through the lease acquire/heartbeat/release + the worktree path
  (`workspace-resolver.ts`) + `git-data-replication.ts:203`. Each user's worktree gets its
  own lease + fence stream.
- **Namespaced git-data refspec (D0-ref):** change `replicateToGitData`
  (`git-data-replication.ts:195-207`) to push `refs/heads/*:refs/soleur/worktrees/<worktree_id>/heads/*`
  (+ tags), replacing the current option-(b)-shaped `refs/heads/*:refs/heads/*` `--force`
  that **silently clobbers a peer user's commits under a 2nd writer**. GitHub `origin` push
  untouched (canonical `refs/heads/main` → rehydration). Add a namespace-ownership check to
  `git-data-pre-receive.sh`.
- **`server/session-router.ts` (new):** co-located, stateless. Inbound WS → resolve the
  conversation's owning host from the per-user lease → **local ⇒ serve; remote ⇒ proxy**
  over one-way-TLS private net. **Placement decided at first-message auth** — before
  `auth_ok`, gated on `isGitDataStoreEnabled()` (inert until 3.D) — and the peer-owned
  socket is **transparently relayed** to the owner with NO client reconnect (ADR-068 b2
  hook-point amendment supersedes the original "WS-upgrade handshake" wording, which is
  impossible under first-message auth; the preserved invariant is *never upgrade-then-
  REDIRECT*). Owning host re-verifies the requester owns the conversation by
  **membership** (CLO AP-2) before serving a proxied session.
- **Local liveness lookup** `isConversationLiveHere` = `abortSession()>0 ||
  hasActiveCcQuery(convId)` — a **local** ownership check (no cross-host union-forward).
- **Reconnect affinity (was 3.D):** reconnect routes back to the owning host (sticky),
  grace-abort cancel stays host-local (Phase-1 `sessions.get(uid)` guard stays correct).
  A forced cross-host migration (drain) emits a **non-transient WS close code** the client
  routes on (teardown + reconnect via the new owner), gating on **materialization proof**
  not a session-origin proxy (learnings `2026-03-27-websocket-close-code-routing`,
  `2026-06-15-materialization-proof`).
- **RED→GREEN (3.6b):** two users on one workspace acquire **distinct** per-user leases
  on **distinct** hosts (the D0 mechanism); a control op for conv X always resolves on X's
  owning host (sticky, no forward); placement decided pre-upgrade (negative: an upgrade
  that would land off-owner is proxied pre-upgrade — Kieran P2-10); reconnect lands on the
  owner; grace cancel stays host-local; membership re-verify rejects a cross-tenant proxied
  session (negative, AP-2).

**Files:** create `session-router.ts`, proxy-TLS load helper; edit `worktree-write-lease.ts`,
`workspace-resolver.ts` (per-user worktree id + path), `ws-handler.ts` (route at ingress +
reconnect + close-code), `ws-client.ts` (close-code), `agent-runner.ts`/`cc-dispatcher.ts`
(pass per-user worktree id at lease acquire).

### Sub-PR 3.C — Cross-tenant isolation: membership-gated git-data fetch authorization

Maps task **3.3** + §6 fetch boundary + D2.

- **`server/git-data-client.ts` (new):** a **membership-gated fetch authorization** (NOT a
  new per-workspace secret) on the git-data **fetch/clone** path — the boundary bwrap can't
  cover (`agent-runner-sandbox-config.ts:106`). Authorized via the
  `resolve_workspace_installation_id` membership shape (NULL→deny).
- **D2 write-boundary sentinel (RESOLVED — gates the 3.D flip):** add a **fail-closed
  membership check on the PUSH path** in `git-data-replication.ts` before the push (mirror
  of 3.C's fetch check; `hr-write-boundary-sentinel-sweep-all-write-sites`) — make the
  optional `userId` (`:176`) mandatory + authorizing, keyed on the exact `workspaceId` that
  builds the push URL. Closes the realistic logic-bug cross-tenant write. **Host-compromise**
  cross-tenant write is an **accepted GA residual** (per-workspace push keys deferred post-GA
  + tripwire — see Resolved Decisions D2); cheap non-gating host-side hardening: a
  receive/upload-pack allowlist wrapper on the transport key.
- **Clone-from-git-data when flag on:** `ensure-workspace-repo.ts` clones from `git-data`,
  retaining `origin`→GitHub (never orphan — rehydration backstop).
- **RED→GREEN (3.6c):** host-A + tenant-A cred **cannot read** tenant-B git-data
  (negative); **cannot write** tenant-B git-data (negative — TS-1); non-member RPC→NULL→deny.

**Files:** create `git-data-client.ts`; edit `ensure-workspace-repo.ts`,
`git-data-replication.ts`; if D2→host-side, a `git-data` `receive-pack` authz wrapper.

### Sub-PR 3.D — Cutover + GA flip (LUKS volume, freeze-rsync, coordinated flip, erasure, legal lockstep)

Maps **cutover** + **3.1 tunnel** + GA. **Gated on D1 + D2.**

- **Owner-side relay completion (from 3.B, b2 amendment):** boot the private-net TLS
  proxy listener (`session-proxy.ts` `createProxyServer`) in `server/index.ts` and wire
  its `onProxiedSession` to a native-session **attach** (bind a proxied socket into the
  ws-handler session lifecycle — register/bind/idle/heartbeat + `handleMessage`). 3.B
  landed the router decision, the b2 transport, the proxying-side hook, and the AP-2
  acceptor (all inert); this is the owner-side half, exercisable only once the 2nd host +
  roster (`SOLEUR_HOST_ROSTER`) exist — soak-validated by AC7/AC8.
- **Ingress→router rewire (D1 resolved):** edit **`dns.tf`** (`cloudflare_record.app`) +
  **`firewall.tf`** — a Cloudflare Load Balancer (or two proxied A records) across both
  hosts' co-located routers, CF-IP firewall rule extended to `web-2`. **Not `tunnel.tf`**
  (deploy/ssh only). Keeps CF edge-TLS termination + the proxied-DNS model.
- **Hardened cutover (CTO P1-4, CLO DL-2):**
  1. **Fresh LUKS git-data volume (TF)** as the rsync target (TS-2/P1-7); Doppler-env key at
     boot, never argv.
  2. **git-data write-freeze** around the copy (two-pass rsync: bulk, then delta under
     freeze) — the real writers are per-turn `syncPush`, not just crons.
  3. **Set-identity verify, not count-match:** `git for-each-ref` diff **and**
     `git rev-list --all | sort | sha256sum` equal on both sources.
  4. **Coordinated cross-host flag flip:** Doppler propagation to two containers is not
     atomic → both hosts drain+reload together (or a brief both-quiesced flip).
  5. If scheduled, **Inngest-dispatches-GHA** (cloud-admin creds off the app host — learning
     `2026-06-02`), never in-process terraform.
  6. **Rollback = flag off + re-drain**, losing post-flip git-data writes — works only
     because pushed refs are also on GitHub `origin` (rehydration). State the dependency.
  7. **Old-volume decommission/wipe** (CLO DL-2); during dual-existence, Art. 17 erasure
     hits **both**.
- **Art. 17 app-side erasure (CLO DL-1, Kieran P0-1):** `account-delete.ts` /
  workspace-delete calls the 3.A `git-data-remove` wrapper over the private net (mirror the
  attachments purge `account-delete.ts:152`). **Erasure-reach AC.**
- **Legal-doc lockstep (CLO AP-3, mandatory pre-merge):** amend `article-30-register.md`
  (PA-1(e)/PA-2(e) recipients += `web-2`+router EU-pinned; PA-1(g)/PA-2(g) TOMs += one-way
  TLS, per-workspace fetch authz, LUKS-at-rest, membership re-verify); `privacy-policy.md`
  + `gdpr-policy.md` + `data-protection-disclosure.md` Last-Updated + repin
  `LEGAL_DOC_SHAS` + Eleventy mirrors; `compliance-posture.md` Hetzner DPA row += `web-2`
  + git-data. **No `TC_VERSION` bump.**
- **NFR register:** NFR-019 N/A→achieved (repoint ADR-027→ADR-068); NFR-026 "achieved"
  **only after LUKS + one-way-TLS verified**. **ADR-068** `adopting`→`accepted`.
- **Review set:** add **`deployment-verification-agent`** (CTO gap) + security-sentinel,
  data-integrity-guardian, observability-coverage-reviewer, user-impact-reviewer.
- **RED→GREEN (3.6d):** AC7 (two users/two hosts/one workspace, **2nd user's committed work
  reaches shared git-data and is visible** — Kieran P1-5); drain/deploy no-fresh-greeting
  (AC8); tombstone-release preserves fence token across a takeover; reclaim→first-push
  ordering (P2-9).

**Files:** edit `tunnel.tf` (or real ingress), `account-delete.ts`, `nfr-register.md`,
ADR-068, the 4 legal docs + `compliance-posture.md`, cutover script, `expenses.md`. Create
LUKS volume TF, `scripts/followthroughs/phase3-ga-soak-5274.sh`.

## Infrastructure (IaC)

Fires Phase-2.8. Lands in `apps/web-platform/infra/` (AP-001; `infra-validation.yml`
covers `terraform validate`).

### Terraform changes
- **Edit:** `server.tf` (`for_each`+`moved`), `network.tf` (2nd-host attach + placement
  group), `tunnel.tf` (ingress→router), `variables.tf` (`var.web_hosts` w/ EU location,
  proxy-TLS vars), `ci-deploy.sh` (`SOLEUR_HOST_ID` + 2-host fan-out), `infra-validation.yml`
  (EU-location check).
- **Create:** `placement-group.tf`, proxy-TLS server-cert TF, **LUKS** git-data volume TF
  (3.D target), `git-data-remove.sh` + cloud-init. **No `coordinator.tf`/cloud-init** — the
  router is co-located in the web-host process (resolves Kieran P0-2; simplest, inherits the
  EU pin, no new SPOF box).
- **Sensitive vars:** proxy-TLS key + LUKS key via `tls`/`random` → `doppler_secret` →
  runtime **env, never argv** (#5560). `terraform.tfstate` (R2) holds keys plaintext → treat
  as secret-bearing; R2 credential scope is the control (ADR §7).

### Apply path
Cloud-init + idempotent bootstrap for `web-2`. `placement_group` attach on the **running**
host forces a power-off → **maintenance-window apply**. `moved` verified `0 to destroy`.
**Never rename `for_each` keys post-migration.**

### Distinctness / drift safeguards
`dev != prd`. EU-location `check`/CI gate (T-1). `receive.advertisePushOptions` already set.

### Vendor-tier reality check
No new sub-processor (self-hosted Hetzner EU). `hcloud_placement_group` free (max 10/group,
2 used). 2nd `hcloud_server` ≈ €15/mo + LUKS volume — record in `expenses.md` before
PR-ready (`wg-record-recurring-vendor-expense-before-ready`); verify Hetzner pricing first.

## Observability

```yaml
liveness_signal:
  what: router placement decisions (op control_plane_route) + worktree_lease acquire/reclaim; per-host heartbeat
  cadence: per placement + per lease heartbeat (25s)
  alert_target: Better Stack monitor on router proxy-error rate; Sentry alert on control_plane_route failures
  configured_in: apps/web-platform/infra/sentry/*.tf (op contract) + Better Stack monitor TF
error_reporting:
  destination: Sentry (feature tags control_plane_route, worktree_lease)
  fail_loud: yes — fence rejects, proxy-TLS handshake failures, cross-tenant fetch denials captureException fail-loud
failure_modes:
  - mode: inbound WS lands on non-owning host and the proxy to the owner fails (owner down / TLS reject)
    detection: control_plane_route event {ingress_host, owner_host, decision, proxy_result} — in-surface structured fields discriminating local-serve vs proxy-fail vs owner-unresolved (blind-surface probe, learning 2026-07-01)
    alert_route: Sentry + Better Stack
  - mode: cross-tenant git-data fetch denial (non-member RPC → NULL)
    detection: git-data event {workspace_id_hash, member:false}
    alert_route: Sentry (security)
  - mode: proxy-TLS server-cert expiry
    detection: startup notAfter log + Sentry on TLS handshake error; long-lived cert (multi-year) → single expiry monitor
    alert_route: Better Stack cert-expiry monitor + Sentry
  - mode: fence false-reject after cutover (non-monotonic gen)
    detection: pre-receive reject → Sentry worktree_lease event {stored_max, pushed_gen}
    alert_route: Sentry (GA-gating during soak)
logs:
  where: Sentry breadcrumbs + structured JSON to Better Stack; no host-local-only logs on the routing path
  retention: per Better Stack retention (≤ conversation retention for user-content-adjacent fields)
discoverability_test:
  command: "Sentry API query for op:control_plane_route on the affected workspace (documented in runbook) — NO ssh"
  expected_output: control_plane_route events with discriminating fields; zero events on a changed routing path after deploy ⇒ wrong layer (learning 2026-06-30-verify-fixed-code-path-executes)
```

**Affected-surface (§2.9.2):** the co-located router, the ingress connector, and the
in-sandbox agent are blind surfaces — each `detection` names an in-surface structured probe
discriminating all hypotheses in one event. No SSH in any runbook (`hr-no-ssh-fallback-in-runbooks`).

**Soak follow-through (§2.9.1):** GA close is soak-gated — **≥7 days with both hosts owning
live per-user leases, zero fence false-rejects, zero cross-tenant denials** before ADR-068
`accepted` / #5274 Phase-3 milestone closes. Enroll
`scripts/followthroughs/phase3-ga-soak-5274.sh` (Sentry-rate, `start=` post-cutover) +
tracker directive + `follow-through` label in `scheduled-followthrough-sweeper.yml`.

## Acceptance Criteria

### Pre-merge (per sub-PR)
- **AC1 (3.A)** — `terraform plan` **0 to destroy** (jq); `validate` green; **non-EU
  `web_hosts` location rejected** (T-1); `SOLEUR_HOST_ID` in both docker-run blocks +
  2-host fan-out present; server-cert chain validates; `git-data-remove` wrapper installed
  via cloud-init; cron-drain ADR renumbered (no ADR-068 collision).
- **AC2 (3.B)** — two users on one workspace acquire **distinct per-user leases on distinct
  hosts** (D0); a control op for conv X **always resolves on X's owning host** (sticky, no
  cross-host forward); placement decided **at first-message auth, before `auth_ok`** (b2
  amendment — negative: an off-owner session is proxied transparently BEFORE `auth_ok`,
  asserting NO `ROUTING_MIGRATED`/reconnect close on the initial placement path, P2-10);
  reconnect lands on the owner + grace cancel host-local; membership re-verify **rejects**
  a cross-tenant proxied session (negative, AP-2).
- **AC3 (3.C)** — a non-member session **cannot read** tenant-B git-data (negative);
  the **app-side write sentinel** rejects a push for a workspace the session-user isn't a
  member of (negative, fail-closed — D2 logic-bug boundary); non-member RPC→NULL→deny. (The
  host-compromise cross-tenant write is a documented GA residual, NOT asserted here.)
- **AC4 (3.D-pre)** — LUKS volume TF present + validates; `git-data-remove` app call wired.

### Post-merge (operator / soak — automate all automatable; verify read-only)
- **AC5** — the 2-host `for_each` deploy delivers the container to **both** hosts (fan-out).
- **AC6** — Cutover: **set-identity** verify (`for-each-ref` diff + `rev-list|sort|sha256sum`)
  old→fresh **LUKS** volume before the flip; write-freeze held around copy+verify+flip;
  coordinated cross-host flip; **old volume decommissioned/wiped**; rollback dependency
  (GitHub rehydration) documented.
- **AC7** — Flag on: **two users on one workspace served by two different hosts, each on
  their own per-user worktree; each user's committed work reaches shared git-data under its
  own `refs/soleur/worktrees/<id>/` namespace and is FETCHABLE by the peer** (G1 — sharpened
  per Kieran P1-5 + D0-ref: "visible" = fetchable distinct refs, NOT an auto-merged shared
  branch; the negative test proves the current shared-ref `--force` refspec is gone).
- **AC8** — A drain/deploy → **no fresh-session greeting**; a brief stream re-render on the
  migrated turn is acceptable at GA (the ADR-059 replay buffer is Phase 4a — CTO P1-5). Do
  NOT assert "invisible" beyond this.
- **AC9 (Art. 17)** — deleting a workspace/account **removes the per-workspace git-data bare
  repo** on the git-data host (erasure-reach test, DL-1).
- **AC10 (legal lockstep)** — Article 30 + 3 privacy docs + `compliance-posture.md` updated;
  `LEGAL_DOC_SHAS` repinned; Eleventy mirrors synced (AP-3).
- **AC11 (soak)** — ≥7 days both hosts owning live leases, zero fence false-rejects, zero
  cross-tenant denials → ADR-068 `accepted`, NFR-019/026 flipped (026 only after LUKS +
  TLS verified), #5274 Phase-3 milestone closed. Enforced by the follow-through probe.

## Test Scenarios (RED→GREEN)

Per sub-PR (3.6a–3.6d). Security invariants (cross-tenant read/write, cross-tenant proxied
session) asserted at the **tool/RPC entry or captured-argv**, never via an LLM prompt
(learning `2026-04-19`). Integration tests **DEV-only** (`hr-dev-prd-distinct-supabase-projects`); prod verification read-only.

## Risks & Mitigations

- **Per-user `worktree_id` is a foundational change** touching every lease call site + the
  worktree path. → thread it explicitly; the migration-116 PK already supports it; DEV
  integration test for two concurrent per-user leases.
- **Cross-tenant WRITE via cluster-wide push key** (TS-1/D2). → resolve threat-model +
  enforcement before the flip.
- **Proxy-TLS cert expiry.** → long-lived (multi-year) self-signed server cert → no rotation
  cron; startup `notAfter` log + Sentry handshake-error + one Better Stack monitor. (Downgraded
  from mutual-cert per DHH/simplicity; still satisfies NFR-026 in-transit.)
- **Cutover data loss / split-store** (CTO P1-4). → LUKS fresh target, freeze-rsync,
  set-identity verify, coordinated flip, GitHub-rehydration rollback, old-volume wipe.
- **Art. 17 gap on bare repos** (DL-1). → 3.A cloud-init remove wrapper + 3.D app call;
  erasure-reach AC.
- **Placement-group attach reboots the running host.** → maintenance-window apply.
- **Wrong-layer fix on a recurring cross-host symptom.** → Sentry breadcrumb exec-path proof
  before shipping any Phase-3 fix (learning `2026-06-30`).
- **Precedent-diff — LUKS is NOVEL** (no cryptsetup anywhere; scrutinize). Boot-secret-via-Doppler
  exists (`git-data.tf:60-77`). Needs an idempotent `cryptsetup isLuks` guard (luksFormat fails
  on 2nd cloud-init run) + the `git-data-bootstrap.sh` mount switched to `/dev/mapper/git-data`.
- **Precedent-diff — one-way TLS Node proxy is NOVEL** (server is HTTP-only, `index.ts:6`). The
  client MUST **pin our self-signed CA (`rejectUnauthorized:true`)**, never `false` (MITM-able);
  WS-over-TLS needs `wss://` + CSP (`test/csp.test.ts`) + `WebSocketServer noServer` on `https.createServer`.
- **`for_each` web-host refactor is not purely mechanical:** `web-1` provisions via 10
  `remote-exec`/SSH `terraform_data` blocks; prefer **cloud-init for `web-2`** (mirror git-data)
  to avoid an SSH-reachability dependency that would hang the merge-triggered auto-apply.
- **Host-compromise cross-tenant write = accepted GA residual** (D2) — tracked with a
  per-workspace-keys post-GA closer + tripwire, mirroring the §8 SPOF acceptance.

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO), Operations/Finance (cost, ADR-sized),
Product (NONE — no user-facing UI surface; reconnect UX preserved).

### Engineering (CTO) — reviewed. Verdict: REVISE → resolved.
P0-1 (D0 routing) → **operator chose user-sticky**; the coordinator-forwarding plane is
dropped, D0 resolved via per-user `worktree_id`. P1-2 (cred/threat-model) → D2. P1-3
(mTLS rotation) → moot (one-way long-lived TLS). P1-4 (cutover) → 3.D. P1-5 (AC8) → AC8.
P1-6 (certs) → 3.A. P1-7 (at-rest = migration) → 3.D LUKS. P1-8 (in-sandbox push-option) →
removed. P2-9 (reclaim→first-push) → AC (soak). `deployment-verification-agent` → 3.D set.

### Legal (CLO)/GDPR — reviewed (advisory, not legal advice). Verdict: conditional → folded.
T-1 (EU pin+CI) → 3.A/AC1. TS-1 (cross-tenant write) → D2/AC3. TS-2 (LUKS) → 3.D/AC6. DL-1
(Art.17 bare-repo erasure) → 3.A wrapper + 3.D call/AC9. DL-2 (old-volume) → 3.D/AC6. AP-2
(membership re-verify) → 3.B/AC2. AP-3 (Article 30 + 3-doc lockstep) → 3.D/AC10.
**Operator-acknowledged Criticals** (→ `compliance-posture.md` Active Items +
`compliance/critical` issue, gating the 3.D flip): **TS-1, T-1, DL-1.**

### Plan-review panel (simplicity / Kieran / DHH) — folded.
DHH/CTO/Kieran-P1-5 convergence → **user-sticky** chosen (this revision). Simplicity: mTLS→
one-way TLS + membership re-verify (done); merge 3.D→3.B (done); de-inflate 3.C cred (done);
co-located coordinator (done). Kieran: P0-1 Art.17 file/sequence (done), P0-2 coordinator
infra→co-located (done), P1-3 deploy fan-out (done), P1-6 LUKS in Files (done), P2-7 task
mapping (3.1→3.A/3.D tunnel; 3.2/3.4/3.5→3.B; 3.3→3.C; 3.6→woven — noted), P2-8 ADR
renumber (3.A), P2-9/P2-10 ACs (done). P2-9 ADR stale anchors → reconcile in the amendment.

### Product/UX Gate — Tier: NONE (no UI-surface file created/modified; #5240 contract preserved).

## Open Code-Review Overlap
- **#3243** (decompose `cc-dispatcher.ts`) — Acknowledge (independent; note added surface).
- **#2191** (`clearSessionTimers` in `ws-handler.ts`) — Acknowledge (fold the helper if the
  reconnect edit passes the disconnect timer; else leave open).

## Resolved Decisions (deepen-plan, 2026-07-01)

**D0-ref → RESOLVED: distinct per-user refs.** Each worktree pushes ONLY to
`refs/soleur/worktrees/<worktree_id>/heads/*` (+ `/tags/*`), sole writer of its
namespace, `--force` stays safe, the per-`(workspace,worktree)` fence aligns 1:1 with
the namespace (unchanged). Cross-user visibility = `git fetch` the peer namespace;
reconciliation = explicit user merge; **GitHub `origin/main` stays canonical** (rehydration
intact). **⚠ Load-bearing:** the *current* `replicateToGitData` refspec
(`refs/heads/*:refs/heads/*` `--force`, `worktree-id=primary`, `git-data-replication.ts:195-207`)
is safe only at replicas=1 — under a 2nd writer it **silently clobbers one user's commits**
(the per-worktree fence guards monotonicity within a gen-stream, not last-writer-wins
across streams). So 3.B MUST land the namespaced refspec + per-user `worktree_id` before
the flip. Add a **namespace-ownership check** to `git-data-pre-receive.sh` (`worktree-id=W`
may only write `refs/soleur/worktrees/W/`) — also a down-payment on D2. CWE-22-validate
`worktree_id` app-side (symmetric to `assertSafeWorkspaceId`). Fold into the ADR-068 D0 amendment.

**D1 → RESOLVED: the app WS ingress is NOT the tunnel.** It is `dns.tf`
`cloudflare_record.app` (proxied A → `hcloud_server.web.ipv4_address`) → `firewall.tf`
(443 from Cloudflare IPs only) → host:80 → container:3000. So the Phase-3 ingress→router
rewire edits **`dns.tf` + `firewall.tf`** — multi-host via a Cloudflare Load Balancer (or
two proxied A records) across both hosts' co-located routers, with the CF-IP firewall rule
extended to `web-2` via the `for_each`. **Not `tunnel.tf`** (that fronts only deploy/ssh).
L3: the 2nd-host apply has **no firewall-allowlist prerequisite** (cloud-init-only per the
git-data precedent).

**D2 → RESOLVED: split by threat case.**
- **Logic-bug cross-tenant write → CLOSE, gates the 3.D flip.** Add a **write-boundary
  membership sentinel** on the push path (`hr-write-boundary-sentinel-sweep-all-write-sites`):
  in `git-data-replication.ts` before the push, assert `resolve_workspace_installation_id`-shape
  membership for `(userId, workspaceId)` **fail-closed**, keyed on the exact `workspaceId`
  that builds the push URL (no re-derivation). Make the already-present optional `userId`
  (`:176`) **mandatory + authorizing** when `isGitDataStoreEnabled()`.
- **Host-compromise (transport-key abuse) write → ACCEPTED GA residual**, mirroring the §8
  shared-git-data-host SPOF acceptance: per-workspace push keys (the only true control) are
  disproportionate for a 2-host GA line (a full web-host breach dominates via the DB
  service-role + GitHub App key anyway — same proportionality bar that downgraded mTLS).
  Name **per-workspace keys** as the post-GA closer + file a tracking issue + a promotion
  tripwire (any key-leak/host-compromise incident, or workspace count crossing a blast-radius
  threshold). The read side (3.C fetch check) is app-side too → same residual acceptance.
- **Cheap host-side hardening (non-gating):** replace the transport key's bare
  `git-shell -c` (`cloud-init-git-data.yml:52`) with a receive/upload-pack allowlist wrapper
  + CWE-22 path canonicalization (closes traversal outside the repo root; NOT same-store
  cross-tenant).

## Sharp Edges
- `## User-Brand Impact` is filled (carried from brainstorm) — do not empty it.
- Per-user `worktree_id` is a cross-cutting change: every `worktree-write-lease` call site +
  the worktree path must thread it; a lingering hardcoded `"primary"` re-pins the workspace.
- `abortSession`'s count is legacy-only; the **local** ownership lookup ORs `hasActiveCcQuery`.
- `moved`-block `for_each` keys are immutable post-migration.
- "Encryption-at-rest" is guest-side LUKS, not an `hcloud_volume` attribute.
- The CAS fence guards generation, not tenant identity — the cross-tenant write boundary is a
  separate control (D2).
- The `git-data-remove` wrapper MUST ship in 3.A (cloud-init only) to pre-exist for the 3.D
  app call — it cannot be introduced by the 3.D app PR.
