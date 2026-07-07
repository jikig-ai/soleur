---
feature: inngest-dedicated-host
issue: 6178
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-07-07-inngest-dedicated-host-brainstorm.md
status: draft
---

# Feature: Extract Inngest to Its Own Dedicated Host

## Problem Statement

Inngest — Soleur's self-hosted durable trigger / cron-scheduler control plane —
runs **co-located and loopback-bound (`127.0.0.1:8288`) on every web backend**,
started by web `cloud-init`. This coupling is a correctness and reliability
defect under the target **active-active-N** web topology (web-1 + web-2 both
serving traffic, more backends later):

- **Cron double-fire (correctness defect).** Every web host boots its own Inngest
  against the *same* prd-scoped external Supabase Postgres backend with **no
  leader gate and no cross-instance cron dedup** (self-hosted OSS Inngest is
  single-writer). N active backends ⇒ every scheduled function fires N times.
  Today this is masked only by web-2 being pinned at Cloudflare LB weight 0
  (`server.tf:186`) — a temporary bootstrap state, not the design.
- **Cold-boot brick.** `webhook.service:45` hard-mounts `/var/lib/inngest`
  (no optional `-` prefix, unlike the vector paths); a fresh host that fails to
  create the dir dies `226/NAMESPACE`, `:9000` never binds, the host is
  un-provisionable (observed on the #6090 web-2 recreate).
- **Deploy-tunnel pollution.** Inngest has no cloudflared of its own; it rides the
  shared `deploy.soleur.ai` tunnel (id `6410c1ec`). A half-provisioned web-2
  (Inngest up, app dead) registered on the tunnel and Cloudflare round-robined
  the deploy control-plane to the dead backend → 502s on web-1's deploy plane.

## Goals

- Extract Inngest onto its **own dedicated private-network Hetzner host** as a
  **network-reachable singleton**, modelled on `git-data.tf` / `registry.tf`.
- **Enforce exactly-one Inngest by topology** — remove the Inngest server from
  web `cloud-init` so a new backend cannot re-introduce the double-fire.
- **Eliminate the two couplings**: fix the `/var/lib/inngest` hard mount and
  retire the shared `deploy.soleur.ai` tunnel dependency (private-net-only host
  needs no public tunnel).
- **Unblock active-active web** (web-2 poolable to LB weight > 0) without a cron
  double-fire.
- Bootstrap the new host **purely from `terraform apply` + cloud-init**
  (`hr-fresh-host-provisioning-reachable-from-terraform-apply`), with the new TF
  carrying an attestation (`hr-every-new-terraform-root`), no SSH runbook steps
  (`hr-no-ssh-fallback-in-runbooks`).
- Record an **ADR** superseding #6178's premise, fixing the single-host +
  fan-out-mechanism decisions.

## Non-Goals

- **Inngest failover / HA pair (B2).** Deferred to a follow-up ADR increment,
  gated on a measured need. Self-hosted OSS Inngest cannot be active-active; a
  primary/standby pair needs shared/HA Redis and is materially larger scope.
- **Managed Inngest Cloud.** Declined — it reverses the deliberate EU-residency
  posture (new sub-processor + residency change vs. the #5450 EU-Supabase move).
- **The Phase-2 datastore cutover (SQLite→Supabase Postgres + Redis).** Separate
  in-flight work (ADR-030 `status: adopting`); this feature must coordinate host
  sequencing with it but does not modify the storage backend.
- **Multi-region / geo-distributed Inngest.**

## Functional Requirements

### FR1: Dedicated Inngest host, private-network reachable

A single `hcloud_server.inngest` on the same private subnet as the web hosts;
web backends reach it over the private IP (not loopback). No public ingress
required for app↔Inngest traffic.

### FR2: Singleton enforced by removing Inngest from web cloud-init

Web `cloud-init` no longer installs/starts `inngest-server`. The only running
Inngest is on the dedicated host. Fresh/additional web backends never start an
Inngest.

### FR3: Both couplings removed

`/var/lib/inngest` no longer bricks a fresh web host (mount fix in both
`webhook.service:45` and `cloud-init.yml:245`); Inngest no longer registers on
the `deploy.soleur.ai` tunnel. The 226/NAMESPACE and 502 failure classes are
eliminated (not merely mitigated).

### FR4: App→Inngest and Inngest→app wiring over the private subnet

App container `INNGEST_BASE_URL` points at the Inngest host's private IP
(replacing `host.docker.internal:8288`). Inngest reaches all N app backends for
function invocation via the fan-out mechanism chosen in TR3.

### FR5: Deferred-HA tracking

A GitHub issue captures the failover-pair HA (B2) with an explicit
re-evaluation trigger, linked to the ADR.

## Technical Requirements

### TR1: IaC modelled on git-data.tf / registry.tf, with attestation

New `inngest.tf` host resource(s) + `hcloud_volume` for local Redis AOF +
`hcloud_server_network` private-subnet attach (`network.tf`) + `firewall.tf`
rules for the private app↔Inngest ports (8288 events, 8289 connect if used).
Include the mandatory Terraform-root attestation. Bootstrappable end-to-end from
`terraform apply` (no manual/SSH steps). Note: `git-data.tf` is the right
*provisioning* precedent but its durable-volume *rationale* does not transfer —
Inngest is stateless compute (state in external Postgres + local Redis AOF).

### TR2: Redis local to the Inngest host

Redis (`inngest-redis.{conf,service}`, AOF on the host's own `/mnt/data`-style
volume) moves onto the dedicated host. Single-server local Redis is sufficient
(shared/HA Redis is only needed for the deferred B2 failover topology).

### TR3: Fan-out mechanism — DECIDE IN ADR (VIP vs Connect)

Choose **before implementation** (wrong choice = two migrations of every
backend's wiring):
- **VIP (lean / lowest-risk):** `--sdk-url` → a single private LB VIP fronting
  all N web backends. Clearly documented for self-hosting.
- **Connect (scale-forward):** app SDK uses Inngest Connect (`:8289`, already
  compiled into the running binary); backends dial *out*, no VIP/registration
  drift as hosts join. Requires a plan-time spike to confirm stability on
  self-hosted v1.19.4.

### TR4: Restart-gap acceptance + durability check

Single host implies a ~seconds availability gap on Inngest restart/host-recreate.
Verify Inngest re-derives pending work from Postgres on restart (run history is
Postgres-durable; cron catch-up + retries cover the gap). Use the existing
Phase-2 `verify-wiped-volume` op as the test harness. Document the Redis-volume
backup/attach requirement this implies.

### TR5: Observability without SSH

New host's boot + Inngest health must be observable from Sentry / Better Stack
(the existing `scheduled-inngest-health.yml`, `betteruptime_heartbeat`, and boot
`soleur-boot-emit` telemetry) — extended to the dedicated host, no SSH-only
diagnosis (`hr-no-ssh-fallback-in-runbooks`, `hr-observability-as-plan-quality-gate`).

### TR6: Cutover sequencing + rollback

Coordinate with the in-flight Phase-2 datastore cutover (must not interleave on
the host state slot). Define a rollback path (re-enable Inngest on web-1) if the
dedicated host fails health verification. Migrate/re-arm any in-flight reminders
using the existing `cutover-inngest.yml` enumerate/capture/rearm ops.

## Open Questions (carry to plan)

1. VIP vs Connect (TR3) — needs the plan-time Connect stability spike.
2. Redis continuity on host-recreate (TR4).
3. Exact private-subnet firewall ports + `INNGEST_BASE_URL` cutover mechanics (FR4).
4. B2 failover deferral trigger definition (FR5).
