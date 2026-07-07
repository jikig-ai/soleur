---
type: feat
issue: 6178
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-07-07-inngest-dedicated-host-brainstorm.md
spec: knowledge-base/project/specs/feat-inngest-dedicated-host/spec.md
branch: feat-inngest-dedicated-host
pr: 6180
deferred_ha_tracker: 6185
supersedes: 5450
plan_review: 6-agent panel applied 2026-07-07 (shape=dedicated-host confirmed by operator)
---

# Plan: Extract Inngest to Its Own Dedicated Host (#6178)

## Overview

Extract the self-hosted Inngest server (Soleur's durable trigger / cron-scheduler
control plane) off the co-located web backends onto its **own dedicated
private-network Hetzner host** (`hcloud_server.inngest` at `10.0.1.40`, modeled on
`git-data.tf` / `zot-registry.tf`). Inngest becomes a **network-reachable
singleton**: web backends reach it over the `10.0.1.0/24` private subnet, and the
Inngest server is **removed from web `cloud-init`** so exactly-one-instance is
enforced by topology.

**Why now (mandatory under the active-active goal):** the target is
**active-active-N** web (web-1 + web-2 both serving, more backends later). OSS
Inngest v1.x is **single-writer** (multi-server HA is an unreleased roadmap item),
and two inngest servers on the *same* prd Supabase Postgres both fire every cron's
schedule **regardless of local `--sdk-url` sync** (the shared Postgres tables drive
scheduling, not local registration). So N co-located servers ⇒ guaranteed N-times
double-fire. Today this is masked only by web-2 being pinned at Cloudflare LB
weight 0 (`server.tf:186`). A dedicated singleton is the prerequisite that lets
web-2 be pooled. (Plan-review confirmed the operator chose the dedicated host over
a single-host role-guard for failure-domain isolation + post-rollout structural
impossibility + all-web-hosts cold-boot decoupling + a clean HA path.)

**Current mechanism (precise):** inngest binds `--host 0.0.0.0 --port 8288`
(`inngest-bootstrap.sh:339`) and the app reaches it via the Docker host-gateway
`host.docker.internal:8288` (`cloud-init.yml:716`) — isolated by **firewall**, not
by loopback binding. Post-extraction the app reaches `10.0.1.40:8288` over the
private subnet.

**Scope:** single dedicated host now. Failover-pair HA **deferred** (#6185).
Managed Inngest Cloud **declined** (residency). Both couplings the issue cited
dissolve: the `/var/lib/inngest` hard mount is removed from web hosts, and the
private-net-only inngest host needs no public tunnel (retiring the
`deploy.soleur.ai` coupling for inngest — see the hook-placement constraint below).

**Structure (4 phases, mirroring the #5450 spike→provision→cutover precedent):**
**Phase 0** resolves the fan-out unknown + rehearses the cutover locally; **Phase 1**
provisions the host on a **non-prod dark backend**; **Phase 2** is the operator
cutover (one gated orchestration, reversible); **Phase 3** decommissions web inngest
+ extends observability, **gated on the Phase-4 soak**.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality (verified in review) | Plan response |
|---|---|---|
| Dark state via SQLite fail-safe | **Unreachable** — `inngest-bootstrap.sh:381-388` only unsets `INNGEST_POSTGRES_URI` when `REDIS_READY=0`; the dedicated host needs healthy Redis. Reusing prod `INNGEST_POSTGRES_URI` ⇒ **double-fire at provision time**. | Dark state = a **distinct non-prod Postgres backend** on the `prd_inngest` config, repointed to prod only at cutover (Phase 1.3, AC-DARK). |
| Rearm can run at "start dedicated" (2.3) | Rearm posts to the **local app** (`inngest-rearm-reminders.sh:29`), which forwards via `INNGEST_BASE_URL`. Must run **after** app-repoint. | Cutover re-sequenced: rearm is step 2.5, after app-repoint (2.4). |
| Hook placement is an open ADR toss-up | **Forced** — the dedicated host has no app (rearm's `/api/internal/schedule-reminder` route) and no public ingress (GH-runner reaches only `deploy.soleur.ai`). Hooks **stay on the web host**. | Resolved in ADR before Phase 1; §3.1 keeps the capture subpath writable. |
| `--sdk-url` set via ADR line | Hard-coded literal in shared `inngest-bootstrap.sh:339` (only `@@BACKEND_*@@` are substituted). | Templating it is a real cross-consumer code task (web + Vector `vector.tf:3`). |
| `prd_inngest` (branch config) isolates secrets | A **branch config** inherits all ~116 `soleur/prd` secrets (`model.c4:361`). Zot isolation used a separate **project**. | Use a separate Doppler **project** (mirror `soleur-registry`) or drop the isolation claim. |
| ADR-097 | **Taken** (`ADR-097-github-project-board-...`). | Use **ADR-098**. |
| git-data durable-volume rationale "does NOT transfer" | Partly false — Redis AOF **does** live on a local block volume. | Dedicated `hcloud_volume.inngest_redis` (TR2). |

## User-Brand Impact

**If this lands broken, the user experiences:** scheduled agent runs / crons fire
**zero times** (a cutover gap or the singleton down) or **N times** (two inngest
servers on prod Postgres) — silently dropped or duplicated autonomous work with no
error surfaced. A botched web-cloud-init removal can also cold-boot-brick a fresh
backend (226/NAMESPACE).

**Explicit accepted regression (SPOF):** extraction **reduces durable-trigger
availability from potentially-2 (co-located on web-1 and web-2) to definitely-1**
(the single dedicated host) to buy exactly-once. The single box down = zero crons
fire until it recovers (Postgres-durable state means delayed, not lost). Redundancy
is deferred to #6185. This is a stated, accepted tradeoff, not a reliability win.

**If this leaks:** N/A — no new data surface; state stays in the dedicated EU
Supabase project + host-local Redis (CLO cleared; no new sub-processor/residency).

**Brand-survival threshold:** single-user incident.
_CPO sign-off carried forward from brainstorm Phase 0.1; `user-impact-reviewer`
invoked at review-time._

## The Fan-Out Decision (resolved in Phase 0, fixed in the ADR)

Once inngest is on its own host, the inngest→app function-invocation path crosses
the private subnet to reach N web backends. **Reachability prerequisite (load-bearing
for EVERY option):** today inngest→app is host-gateway-local, so web `/api/inngest`
has never accepted a remote caller — the app must **bind the private interface**
(not host-gateway-only) and `hcloud_firewall.web` needs an **inbound rule for
`10.0.1.40`** on the app port. Both are Phase-1 tasks (arch-strategist MED).

Mechanism candidates:
1. **Multiple `--sdk-url`** (one per web backend private IP) — simplest, no LB.
   **Safe only if** inngest routes each invocation to *one* URL; **unsafe if** it
   POSTs to *all* (duplicate execution — broader than cron double-fire).
2. **Single private VIP** (Hetzner LB) → one `--sdk-url`. Safe regardless; costs
   one LB. **Default/fallback.**
3. **Connect** (`:8289`) — deferred (least-confirmed on self-hosted v1.19.4);
   recorded as the scale-forward with an adoption trigger. **Not spiked** (the plan
   has already decided not to adopt it now — spiking a decided-against option is
   ceremony).

**Resolution (Phase 0.2):** read inngest's invocation routing in
`node_modules/inngest` **first**; stand up the two-instance local harness only if
the source is genuinely ambiguous. If route-once is confirmed, adopt multi-`--sdk-url`
**and re-confirm on the dark host in Phase 1 before app wiring** (M2 — local
fidelity ≠ prod); otherwise ship the VIP. The ADR fixes the choice.

## Implementation Phases

### Phase 0 — Resolve the fan-out unknown + rehearse the cutover (local/read-only)

- [ ] **0.1 Detect current prod web-inngest backend** (SQLite vs Postgres) via
  `GET https://deploy.soleur.ai/hooks/inngest-inventory` + the dedicated-project
  pool probe (`scheduled-inngest-health.yml:118-251`). Drives the Phase-1
  dark-backend design and the Phase-2 capture/rearm shape. **Re-detected at cutover
  start** (M3) since #5450 may run in the interim. Branch if web-1/web-2 report
  different backends (heterogeneous fleet).
- [ ] **0.2 Resolve invocation semantics (route-once vs invoke-all)** by reading
  `node_modules/inngest` routing source; local two-instance harness only if
  ambiguous. Record the finding in `## Research Insights`. (Connect probe **cut** —
  Connect is deferred.)
- [ ] **0.3 Rehearse the dangerous sequences locally** (M5): quiesce→outage→register
  timing (to size the H1 window) **and** the rollback path (T5). The riskiest
  transitions must be exercised before the real maintenance window.
- [ ] **0.4 Output → ADR-098** (see Architecture Decision) fixing: the fan-out
  mechanism, hooks-stay-web-host, the dark→live datastore-flip mechanism, and the
  #5450 supersession. Authored before Phase-1 IaC.

### Phase 1 — Provision the host on a NON-PROD dark backend (IaC; mergeable; inert on merge)

- [ ] **1.1 `apps/web-platform/infra/inngest-host.tf`** — `hcloud_server.inngest`
  (`server_type=var.inngest_server_type` default `cax11` **ARM64 — a singleton
  scheduler, not throughput-bound**; `location=var.location`; `image=ubuntu-24.04`;
  `ssh_keys=[hcloud_ssh_key.default.id]`; `public_net` egress-only;
  `user_data=base64gzip(templatefile("cloud-init-inngest.yml",{...}))`; **no**
  `lifecycle.ignore_changes=[user_data]` — see the outage note below) +
  `hcloud_volume.inngest_redis` + attachment (ext4, `var.inngest_redis_volume_size`
  default 10) + `hcloud_server_network.inngest` at `10.0.1.40` (separate resource,
  `network.tf:9-15`) + `hcloud_firewall.inngest` + attachment (deny-all-public) +
  **inbound rule on `hcloud_firewall.web` for `10.0.1.40`** (the inngest→app path)
  + app **private-interface bind** for `/api/inngest`. New vars **both defaulted**
  (no operator mint). **Force-replace note:** with no `ignore_changes[user_data]`,
  every cloud-init edit destroys+recreates the sole scheduler → a cron-outage
  window; gate all cloud-init edits to the maintenance-window dispatch; the AOF
  volume is a separate resource (survives replace — verify re-attach, git-data
  precedent).
- [ ] **1.2 `cloud-init-inngest.yml`** — bake GHCR read-creds (#6179/#6161) so the
  cold-boot `soleur-inngest-bootstrap` OCI pull + cosign-verify succeeds (else
  226/NAMESPACE); extract + run `inngest-bootstrap.sh`; Redis on the attached
  volume; heartbeat timer; Vector shipper. **< 32 KB `user_data`** — bake bodies,
  terse comments, `set +e` at block ends (2026-07-03/2026-07-06 learnings).
  **Template the `--sdk-url`** in `inngest-bootstrap.sh:339` (currently hard-coded
  `http://127.0.0.1:3000/api/inngest`) — a cross-consumer edit; grep-sweep web +
  Vector consumers and preserve web's host-gateway behavior until Phase 3
  (`hr-type-widening-cross-consumer-grep`).
- [ ] **1.3 Dark state = distinct NON-PROD Postgres backend.** The host's
  `INNGEST_POSTGRES_URI` at provision points at a **fresh empty database/schema**
  (a distinct value on the `prd_inngest` config), NOT prod — so it fires zero prod
  crons at boot. **Drop the SQLite fail-safe** (unreachable on a Redis-healthy
  host). Provision the non-prod backend as a concrete resource **before** the host.
- [ ] **1.4 Secrets on a separate Doppler PROJECT** (not a `prd` branch config —
  which inherits all ~116 secrets): mirror `soleur-registry`'s dedicated project
  holding only inngest secrets (Redis pw, signing/event keys, the non-prod-until-
  cutover Postgres URI). **Explicitly provision** `INNGEST_POSTGRES_URI`,
  signing/event keys, Redis pw into this project (M4 — else cold-boot bricks).
  Note: `INNGEST_POSTGRES_URI` is the one operator-provided secret (`inngest.tf:179`),
  not TF-minted.
- [ ] **1.5 Dedicated apply dispatch job** in `apply-web-platform-infra.yml`
  (modeled on `web-2-recreate`/`warm-standby`), `-target`-ing the host set. **Not**
  in the per-merge `-target` set (registry precedent — net-new `.tf` is inert on
  merge). Singleton (no for_each) + net-new (no `moved`) ⇒ no prior landmines.

### Phase 2 — Cutover (operator, maintenance window; ONE gated orchestration; reversible)

Bake the sequence into a single `cutover-inngest.yml op=execute` that chains the
steps with the quiesce gate built in (CTO #2 — fewer human decision points). Pick a
**low-traffic window** and **mute the Better Stack heartbeat** for the window (M6).

- [ ] **2.0 Pre-flight:** re-detect the web backend (M3); confirm the dedicated host
  is firing **zero** prod crons (still on the non-prod backend).
- [ ] **2.1 Capture** reminders from web inngest (`op=backup` then `op=capture` →
  web host `/var/lib/inngest/cutover-capture.json`).
- [ ] **2.2 Quiesce + stop + `systemctl disable` inngest on EVERY web host that can
  run a scheduler against prod Postgres — INCLUDING weight-0 web-2** (H4; LB weight
  gates HTTP traffic, not the co-located scheduler). **Freeze `web-2-recreate` /
  `warm-standby` for the window** (C2). Confirm quiesced via inventory.
- [ ] **2.3 Repoint the dedicated host to prod Postgres + start** (first-class
  verifiable datastore-flip step, H2: confirm web is quiesced immediately before;
  the flip is a Doppler value edit on the inngest project + restart, since inngest
  secrets carry `ignore_changes[value]`). Sole writer — no double-fire window.
- [ ] **2.4 Repoint app** `INNGEST_BASE_URL` → `http://10.0.1.40:8288` at **both**
  `ci-deploy.sh:1341` **and** `:1574` (source edit — see the parity coupling in
  3.3; rollback = code revert, not an env knob) and redeploy web app containers.
- [ ] **2.5 Rearm** (`op=rearm`) — **after** app-repoint so it flows web-app →
  dedicated inngest. Reconcile: **capture count == rearm count == pre-cutover armed
  count**; explicit **partial-rearm branch** if they differ (M1).
- [ ] **2.6 Verify** exactly-once (per-`(fn,tick)`, see AC12); health green.
  **Rollback:** `op=quiesce+stop the DEDICATED host` → confirm via inventory →
  repoint app → loopback → re-enable+restart web inngest (C1 — rollback MUST stop
  the dedicated host first, mirroring the forward gate; capture file retained).
- [ ] **Bounded outage window (H1):** between 2.2 and functions registering after
  2.4, no scheduler runs — ticks in this window are missed (not backfilled) and
  reminders created in-window are lost. Document the window bound, the low-traffic
  choice, and the list of crons needing manual `trigger-cron` re-fire.

### Phase 3 — Decommission web inngest + extend observability (SOAK-GATED)

- [ ] **3.1 (SOAK-GATED — lands only after Phase 4.1 is green, C4) Complete web
  decommission:** remove from `cloud-init.yml` the bootstrap extraction block
  (header `624`, runs to **`681`** incl. the `bash …inngest-bootstrap.sh`
  invocation), the `INNGEST_BASE_URL` host-gateway env (`716`), the
  `/etc/sudoers.d/deploy-inngest-bootstrap` dropfile (`74-81`) + its mirror
  `deploy-inngest-bootstrap.sudoers` + the `terraform_data.deploy_pipeline_fix`
  refresh, and `/var/lib/inngest` from `webhook.service` `ReadWritePaths` (`245` +
  `webhook.service:45`, lockstep) — **but keep the capture subpath writable** on the
  web host (hooks stay web-host-resident, so `op=capture` still needs it; do NOT
  blanket-remove). Until soak-green, keep co-located inngest **stopped+disabled but
  present** so rollback survives.
- [ ] **3.2 Repoint on-host reminder/inventory scripts** to `10.0.1.40`:
  `INNGEST_GQL_URL` default (`inngest-enumerate-reminders.sh:32`, and inventory +
  rearm) → `http://10.0.1.40:8288/v0/gql`. Hooks **stay on the web host** (reach the
  inngest host over private net) — the dedicated host has no app + no ingress.
- [ ] **3.3 One-commit parity change:** fold `ci-deploy.sh` **both** sites +
  `cron-inngest-cron-watchdog.ts:73` `INNGEST_HOST_FALLBACK` + its parity test
  (`cron-inngest-cron-watchdog.test.ts:281`) into a **single commit** (the test
  asserts `ci-deploy.sh` value == fallback const in the same build; a split fails
  CI). Update **both** ci-deploy sites (the test `.match()` only sees the first).
- [ ] **3.4 Extend observability to the new host** (see Observability): heartbeat
  pushed FROM the inngest host; health workflow reaches the new host; Vector on the
  new host; retire the `deploy.soleur.ai` tunnel for inngest.

### Phase 4 — Soak gate (not a phase — a gate feeding Phase 3)

- [ ] **4.1 Soak (7 days): zero double-fire** by the **per-`(function_id,
  scheduled_tick)`** invariant (C3): `COUNT(runs) GROUP BY (function_id,
  scheduled_tick)` has **no group > 1**. Follow-Through Enrollment (Observability
  §soak). This gates §3.1 (decommission).
- [ ] **4.2 (separate work, not this plan) Pool web-2** at LB weight > 0 — now safe.
- [ ] **4.3 Single ADR lifecycle:** flip **ADR-098** `adopting → accepted` on soak
  success (do NOT split the lifecycle across ADR-098 + ADR-030 — code-simplicity);
  `gh issue close 6178`.

## Architecture Decision (ADR/C4)

### ADR
New **ADR-098** (ADR-097 taken) — **"Inngest as a dedicated single-host singleton
control plane"** — amending **ADR-030**. `## Decision`: extract to one dedicated
private-net host on a distinct Postgres backend until cutover; hooks stay
web-host-resident; fan-out mechanism per Phase-0. `## Alternatives Considered`:
dedicated-host (chosen) vs. single-host role-guard (rejected: correlated web-1
failure; operator chose structural impossibility) vs. in-place-every-host (rejected:
double-fire) vs. HA-pair (deferred #6185) vs. managed Cloud (declined: residency).
`status: adopting` until 4.1; the single lifecycle lives on ADR-098.

### C4 views
Read all three of `.../diagrams/{model.c4,views.c4,spec.c4}`. Enumerated: no new
external human actor; external systems (Hetzner, Supabase, Redis, GHCR, Doppler)
already modeled (`model.c4:166-180`); no new data store; the changed relationship
is `api → inngest`. Edits (Container view): (1) `inngest` container technology
`model.c4:173` → `"Dedicated Hetzner host, private-net 10.0.1.40:8288/:8289"`
(remove the inaccurate `loopback 127.0.0.1` string — AC5 grep target); (2)
`api -> inngest` **line 345 only** → `"HTTP private-net :8288"`; (3) review the
adjacent inngest edges `:349-351,359` (`inngest→inngestPostgres/Redis`,
`hetzner→inngest`, `doppler→inngest`) and update `hetzner -> inngest "Hosts"` to a
dedicated `inngestHost -> inngest` relationship if the model distinguishes
deployment nodes. Run `c4-code-syntax.test.ts` + `c4-render.test.ts`.

### Sequencing
ADR-098 authored in Phase 0.4 (`status: adopting`); fan-out line filled from 0.2.
Not deferred.

## Infrastructure (IaC)

### Terraform changes
New `apps/web-platform/infra/inngest-host.tf` (host/volume/attachment/server_network/
firewall + `hcloud_firewall.web` inbound for `10.0.1.40`). Secrets on a **separate
Doppler project** (not a `prd` branch config). New vars `inngest_server_type`
(default `cax11`) + `inngest_redis_volume_size` (default `10`) — defaulted, no mint.

### Apply path
Pure CREATE → cloud-init-only (no `remote-exec`). **Not** in the per-merge `-target`
set — a dedicated `apply_target=inngest-host` dispatch creates the set
(maintenance-window). No web resource force-replaced. **Plan-time hazard (arch
MED-Q3):** HCL evaluates `templatefile()` at plan-time on **every** shared per-merge
apply regardless of `-target` — a malformed `cloud-init-inngest.yml`/`inngest-host.tf`
breaks the shared apply for all resources. Gate with AC-VALIDATE below.

### Distinctness / drift safeguards
No dev inngest host (prd-only). Secrets land in `terraform.tfstate` (R2 backend).
`inngest-host.tf` is in the **existing web-platform root** → **no new attestation**.
`no ignore_changes[user_data]` on a singleton = control-plane outage per cloud-init
edit → maintenance-window dispatch only (documented in 1.1).

### Vendor-tier reality check
`cax11` ARM64, EU `hel1` (GDPR); inngest CLI pin must be the **ARM64** build. Reuse
free-tier `betteruptime_heartbeat.inngest_prd`; `betteruptime_policy` stays gated on
`var.betterstack_paid_tier`. _Prices reflect training data — verify at Hetzner._

### #5450 supersession
Make **#5450 a formal `superseded-by` #6178** in the tracker (not manual
coordination on a single-user-incident path). Frame `cutover-inngest.yml`
capture/rearm as **adapted** for the cross-host move (via app `INNGEST_BASE_URL`
indirection), not reused as-is.

## Observability

```yaml
liveness_signal:
  what: inngest-server up + functions registered + heartbeat pushed FROM the inngest host
  cadence: heartbeat 60s; health workflow 15m
  alert_target: Better Stack (email) + scheduled-inngest-health.yml P1 issue
  configured_in: cloud-init-inngest.yml (heartbeat timer) + scheduled-inngest-health.yml
error_reporting:
  destination: Sentry (Vector journal sink) + health-workflow heartbeat
  fail_loud: yes
failure_modes:
  - mode: inngest host down
    detection: missed heartbeat (60s/30s grace) + inventory 200-fail
    alert_route: Better Stack + P1 issue
    remediation_no_ssh: apply_target=inngest-host dispatch (reboot/re-provision)   # CTO #1
  - mode: Redis AOF volume full / write-rejection (noeviction)
    detection: inngest error log → Vector → Sentry
    alert_route: Sentry
    remediation_no_ssh: volume resize via inngest-host.tf var + dispatch
  - mode: cron DOUBLE-FIRE (two servers on prod Postgres)
    detection: per-(function_id, scheduled_tick) group count > 1 in run history   # C3
    alert_route: Sentry + soak follow-through (fail-closed)
    remediation_no_ssh: rollback op (quiesce dedicated → repoint app → restart web)
  - mode: function-registry desync
    detection: inventory functions[] < expected
    alert_route: P1 issue
    remediation_no_ssh: restart-inngest-server.yml dispatch
  - mode: fresh inngest-host 226/NAMESPACE (GHCR/cosign fail)
    detection: soleur-boot-emit fatal; heartbeat never arrives
    alert_route: Better Stack (heartbeat absence) + boot telemetry
    remediation_no_ssh: re-apply cloud-init via apply_target=inngest-host dispatch
logs:
  where: Vector → Better Stack Logs (journald) on the inngest host
  retention: Better Stack default
discoverability_test:
  command: "curl -fsS https://deploy.soleur.ai/hooks/inngest-inventory  # web-host hook → private-net 10.0.1.40; NO ssh"
  expected_output: "JSON with .functions non-empty"
```

**Soak follow-through (4.1):** `scripts/followthroughs/inngest-double-fire-6178.sh`
exits 0 when **no `(function_id, scheduled_tick)` group has > 1 run** across the soak
(`start=` pinned strictly after cutover); tracker directive
`<!-- soleur:followthrough script=… earliest=<cutover+7d> secrets=… -->` +
`follow-through` label; wire `secrets=` into `scheduled-followthrough-sweeper.yml`.
**Note:** exactly-once confirmation lags window-close by ≥24h — the operator closes
the maintenance window on a **provisional** signal and retains the capture file for
rollback (CTO #4).

## Domain Review
**Domains relevant:** Engineering, Product, Legal (carry-forward from brainstorm).
### Engineering (CTO + platform-strategist)
Reviewed. Dedicated host confirmed by operator over the role-guard alternative;
B2 HA deferred (#6185), B3 rejected (single-writer). Plan-review 6-agent panel
applied 2026-07-07 (all CRITICAL/HIGH cutover findings folded).
### Legal (CLO)
Reviewed. No residency/sub-processor/Article-30 obligation (topological EU-host
move; state in the EU Supabase project). GDPR gate satisfied by carry-forward.
### Product/UX Gate
**Tier:** none. No UI surface. Product relevance = agent-run substrate reliability
(single-user-incident), in User-Brand Impact.

## Acceptance Criteria

### Pre-merge (PR — Phase 1 IaC + Phase 3 code; sequenced per soak-gate)
- [ ] **AC1** `terraform plan` (dispatch `-target` set) shows create of the inngest
  set and **no create/replace** of any `web*`/`git_data`/`registry` resource.
- [ ] **AC2** `hcloud_server.inngest` is not in the per-merge `-target` set
  (appears only under the `apply_target=inngest-host` dispatch job).
- [ ] **AC-VALIDATE** `terraform validate` **and** a **no-`-target` `terraform plan`**
  succeed with the new files present (proves the shared per-merge apply still plans
  clean despite plan-time `templatefile()` eval).
- [ ] **AC-DARK** provision-time `INNGEST_POSTGRES_URI` on the inngest project **≠**
  the prod inngest Postgres URI (verified in Doppler + `terraform plan`).
- [ ] **AC3** New TF vars declare `default`; secrets live on a separate Doppler
  **project** (not a `prd` branch config).
- [ ] **AC4** `cloud-init-inngest.yml` rendered `user_data` < 32768 bytes.
- [ ] **AC-SDKURL** `--sdk-url` is templated in `inngest-bootstrap.sh` (no hard-coded
  `127.0.0.1:3000`); both consumers (web cloud-init + Vector) grep-swept and web
  host-gateway behavior preserved pre-Phase-3.
- [ ] **AC-FW** `hcloud_firewall.web` has an inbound rule for `10.0.1.40` and the app
  binds the private interface for `/api/inngest`.
- [ ] **AC5** `model.c4:173` no longer contains `loopback 127.0.0.1`; C4 render +
  syntax tests pass.
- [ ] **AC6** **ADR-098** file exists, `status: adopting`, all 5 alternatives named.
- [ ] **AC8** Web decommission complete: `sed -n '624,681p' cloud-init.yml | grep -c
  'inngest-bootstrap'` == 0 (range-scoped, not whole-file); no
  `/etc/sudoers.d/deploy-inngest-bootstrap` grant, no `.sudoers` mirror, no
  `deploy_pipeline_fix` refresh for inngest remain; `/var/lib/inngest` absent from
  `cloud-init.yml:245` + `webhook.service:45` **except** the preserved capture
  subpath; `INNGEST_HOST_FALLBACK` = `10.0.1.40` and its parity test updated in the
  **same commit** as both `ci-deploy.sh` sites.
- [ ] **AC9** No `ssh ` in any new runbook/discoverability command.

### Post-merge / cutover (operator, maintenance window — `Ref #6178`, not `Closes`)
- [ ] **AC10** `apply_target=inngest-host` provisions the host; heartbeat arrives;
  inventory returns the new host over private net.
- [ ] **AC11** Cutover completes with web inngest **quiesced+disabled on ALL web
  hosts** (incl web-2) BEFORE 2.3; **capture count == rearm count == pre-cutover
  armed count** (three-way, not `0==0`); partial-rearm branch defined; app
  `INNGEST_BASE_URL` = `10.0.1.40` at both `ci-deploy.sh` sites.
- [ ] **AC12** Exactly-once by the **per-`(function_id, scheduled_tick)`** invariant
  (no group > 1) over 24h; T4 confirms no web host boots inngest after Phase-3
  recreate (the structural check for the port-bind claim, which is not directly
  observable via the allowed no-SSH tooling).
- [ ] **AC13** Soak probe `inngest-double-fire-6178.sh` (per-`(fn,tick)`) exits 0
  across 7 days → **then** §3.1 decommission lands → ADR-098 `adopting → accepted`
  → `gh issue close 6178`.

## Risks & Mitigations
- **Double-fire at provision (arch HIGH):** dark backend is a distinct non-prod
  Postgres (AC-DARK), not prod; the SQLite fail-safe is dropped.
- **Double-fire at cutover / rollback (spec-flow C1, arch Q1):** quiesce+disable ALL
  web hosts gates the prod-Postgres repoint; rollback stops the dedicated host first.
- **Recreate-during-window (spec-flow C2):** freeze recreate workflows for the
  window + T6 recreate-during-window test.
- **Multi-`--sdk-url` invoke-all:** spike 0.2 + dark-host re-confirm (M2); VIP safe fallback.
- **Cold-boot 226/NAMESPACE:** GHCR creds baked; heartbeat-absence alert.
- **Datastore-cutover collision (#5450):** re-detect at cutover start; formal
  supersedes relationship.

## Test Scenarios
- **T1 (double-fire, deterministic):** run history, per-`(fn,tick)` group count == 1.
- **T2 (reminder preservation):** capture == rearm == pre-cutover armed count.
- **T3 (cold-boot):** fresh dispatch from empty → heartbeat + functions[], no 226.
- **T4 (web independence, post-Phase-3):** recreate web from empty → boots, binds
  `:9000`, does NOT start inngest / bind `:8288`.
- **T5 (rollback):** quiesce+stop dedicated → repoint app → loopback → re-enable web
  inngest → crons resume, no double-fire.
- **T6 (recreate-during-window):** recreate a web host in the Phase 2→3 window with
  recreate-freeze active → does NOT boot a co-located scheduler.

## Sharp Edges / Open (carry to deepen-plan)
- User-Brand Impact filled (single-user incident) — passes deepen-plan 4.6.
- Fan-out mechanism DECIDED in 0.2 before Phase-1 wiring.
- The dark→live datastore flip (2.3) and quiesce-ALL-hosts (2.2) are the two most
  dangerous steps — deepen-plan should pressure-test their gating.
