---
title: "feat: Active-Active Web Cluster via IaC (cluster-first, flip-last)"
type: feat
date: 2026-07-24
branch: feat-web-active-active-iac
worktree: .worktrees/feat-web-active-active-iac
pr: 6919
tracking_issue: 6459
related_issues: [6608, 6570, 6575, 6441, 6538, 5274]
adr: ADR-142 (provisional — active-active web ingress + drain-gated blue-green host lifecycle)
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
spec: knowledge-base/project/specs/feat-web-active-active-iac/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-07-24-web-active-active-cluster-iac-brainstorm.md
approach: "A — phased: cluster-first, flip-last"
pr_split: "PR-1 = Phases 0-4 (cluster + out-of-band web-2 standby + populated-volume disposability proof + rebuilt anti-pooling gate). PR-2 = Phase 5 (de-pet web-1), gated on the PR-1 soak."
plan_review: "6-agent panel applied 2026-07-24 (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer + fable advisor). See ## Plan Review Reconciliation."
---

# feat: Active-Active Web Cluster via IaC (cluster-first, flip-last)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- All infra routes through Terraform + cloud-init + gated workflow_dispatch (required-reviewer
     environments, DP-11 F8) — see ## Infrastructure (IaC). "Operator maintenance-window" = a gated
     dispatch, NOT SSH/manual provisioning. No `ssh root@`, no dashboard steps. -->

## Overview

Evolve Soleur's web tier from a single pet host (`web-1`) toward a **full active-active cluster** built
entirely via Terraform, where hosts are disposable cattle and the **workspace volume is the protected
asset**. Operator-confirmed **Approach A**: build the cluster + a fresh cattle `web-2` as an
**out-of-band, health-monitored standby now** (web-1 remains the sole ingress; `replicas=1` held); flip to
*concurrent* active-active serving only when the external ADR-068 Phase-3 GA chain lands.

**Two axes, kept separate (arch C1):** `replicas=1` (single app process) and **LB pool weight** are
different. web-2 must sit at **weight 0 / out of the serving rotation** — health-monitored, not
request-serving — until the Phase-3 flip. A request routed to web-2 before shared git-data exists hits an
**empty workspace** (the sole copy is web-1's volume) = the "workspace-gone" single-user incident. The
programmatic anti-pooling gate that enforced this was **deleted 2026-07-20 (#6575, CLOSED)** and
`server.tf:278-287` says it "MUST be rebuilt before any second web host is pooled" — **rebuilding it is a
deliverable here.**

The multi-host `for_each` machinery + dormant `fan_out_to_peers` already exist. The real deliverables are:
(1) a fresh **cattle web-2** born from a **complete cloud-init parity artifact**; (2) **proven fresh-boot
readiness** (3 silent-boot postmortems — #6459's re-eval trigger); (3) the **rebuilt anti-pooling gate**;
(4) a **volume-preserving host-reprovision contract** (the disposability proof). Concurrent serving, the
LB, and the DNS multi-host rewire are **out of scope** (Phase 6 / external gates).

## Plan Review Reconciliation (6-agent panel + advisor, 2026-07-24)

| Finding | Source | Applied |
|---|---|---|
| Phase 2 ingress-flip / LB-pool IS the "flip"; web-2 must stay out of rotation; rebuild #6575 anti-pooling gate | arch C1, DHH P0, spec-flow P0-3 | Yes — no ingress change; web-2 out-of-band; gate rebuilt (Phase 3.5) |
| Cut `cloudflare_load_balancer` (multi-connector tunnel + out-of-band probe suffice at replicas=1) | simplicity F1, DHH P1 | Yes — LB deferred to Phase 6 |
| Data-safety = volume snapshot + `prevent_destroy` + luksOpen-not-reformat; Phase 4 must rebuild a POPULATED volume; "un-pushed" is the wrong predicate (no-remote workspaces) | advisor, spec-flow P0-1/P0-2/P1-9, arch M5 | Yes — reframed (Phases 4, 5.2) |
| web-1 `for_each` key RETAINED (29 refs/6 files); de-pet = lifecycle not identity; drop `placement_group_id` from ignore_changes as first diff | arch H4/M6, spec-flow P1-4 | Yes (Phase 5) |
| Fold cloud-init parity FORWARD (web-2 born from the rebuild artifact) | advisor Change 1 | Yes (Phase 2) |
| Split de-pet web-1 into PR-2 after soak | DHH P2, simplicity F2 | Yes (pr_split) |
| #6416 CLOSED → use #6441/ADR-115; #6570 is ROOT blocker (cax11 orderable 0/3 EU DCs) — extend stock probe | arch H2/H3 | Yes |
| `scripts/betterstack-query.sh` (not infra/scripts); only 2 roster-coupled parity guards; reconcile provisioner count | Kieran, arch M7 | Yes |
| Runtime ACs → post-merge; AC dry-run; pin soak N=7d; Art. 30 "drafted, not-active"; deep `/health` + boot-window timeout | DHH, spec-flow P1-6/P1-7/P1-8 | Yes |
| proxy-tls cert-regen is latent (Phase-3 consumer only) → Phase 6 coordination | arch L8 | Yes |

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality (grep-verified) | Plan response |
|---|---|---|
| Re-add web-2 → it serves | `dns.tf:16` app record is a **web-1 singleton**; multi-host rewire is an operator maintenance-window full-apply (`dns.tf:4-13`); anti-pooling gate deleted (#6575). | web-2 is out-of-band standby; no ingress change; gate rebuilt. |
| web-2/web-1 rebuildable as `cx33` | model.c4:182: `cx33` unorderable in all 3 EU DCs. `git_data_server_type=cax11` (`variables.tf:130`) orderable in **0/3** EU DCs (#6570 root blocker). | Live stock probe (Phase 0.2) covers **both** cx33 (web) and cax11 (git-data). Orderable type only. |
| Warm standby = redundancy | Workspace volume is the **SOLE COPY** (model.c4:186 — no refspec pushes `refs/checkpoints/*`, signup workspaces have no remote). | Pre-flip, web-2 gives disposability + fresh-boot proof, NOT workspace-serving redundancy (needs #6570 + Phase-3). Stated in Non-Goals. |
| ADR-068 Phase-2 blocked behind #6416 | #6416 is **CLOSED** (web-2 subnet defect, closed at retirement; model.c4:413 "closed"). | Cite #6441/ADR-115 (first-boot NIC gate + #6497 luksOpen boot-unlock) instead. |
| Deploy reaches all hosts | `fan_out_to_peers` dormant; `WEB_HOST_PRIVATE_IPS="10.0.1.10"`. | Populate roster on web-2 birth (Phase 3). |

## User-Brand Impact

**If this lands broken:** a request reaches web-2 before shared git-data exists → **empty workspace**
("workspace-gone"); or a host reprovision reformats the LUKS volume → permanent loss.

**If this loses data:** destroying/reformatting `hcloud_volume.workspaces` (the **SOLE COPY**,
model.c4:186) — permanent, unrecoverable. The volume, not the host, is the protected asset.

**Brand-survival threshold:** single-user incident. `requires_cpo_signoff: true`; `user-impact-reviewer` at PR review.

## Apply-Preflight Hypotheses (SSH/network — `hr-ssh-diagnosis-verify-firewall`)

Applies that run web-1's SSH `provisioner`/`connection` blocks (Phase 5 de-pet transition) need L3→L7 order:
(1) operator egress IP in Doppler `ADMIN_IPS` + `firewall.tf` (`/soleur:admin-ip-refresh` on drift — never
diagnose sshd/fail2ban first); (2) DNS/routing; (3) sshd/service. De-petting removes these provisioners,
shrinking the surface.

## Implementation Phases — PR-1 (Phases 0-4): the cluster + out-of-band standby

### Phase 0 — ADR + live-stock decision + data-layer contract (no infra change)

- **0.1 Author ADR-142** ("Active-active web ingress + drain-gated host lifecycle") — status `adopting`.
  Amends `hr-prod-host-config-change-immutable-redeploy` + ADR-103; extends ADR-068. **Must decide the
  /workspaces failover data mechanism** (advisor 2a): detach/reattach vs replication vs off-host sync —
  this determines whether an eventual multi-serving topology is even valid, so it is decided before any
  ingress/LB architecture is committed.
- **0.2 Live Hetzner stock probe** — enumerate currently-orderable types in hel1/fsn1/nbg1 for **both** the
  web host (cx33 unorderable) **and** git-data (`cax11`, orderable 0/3 EU DCs — #6570 root blocker). Record
  web-2 `server_type`/DC verdict in ADR-142. Same-DC hel1 keeps `web_spread` (`server.tf:134`); cross-DC
  gets `null` placement. No assumed stock.
- **0.3 C4 update** (deliverable): edit `model.c4` (single-host reality at **:178, :186, :413** — NOT :182,
  which already says "Cluster") + `views.c4` — `hetzner` becomes a 2-host cluster (1 serving, 1 out-of-band
  standby). **Do NOT add a load-balancer element** (LB is Phase 6). Run `c4-code-syntax.test.ts` +
  `c4-render.test.ts`.

### Phase 1 — Fresh-boot readiness gate (#6459 precondition)

- **1.1** Fresh-boot readiness assertions: cloud-init `runcmd` full-bootstrap; no Doppler/systemd-env-file
  silent fallbacks (`2026-04-03-doppler-not-installed-env-fallback-outage`); user_data cap on the
  **gzipped** render (`2026-07-07-cloud-init-user-data-cap...`). Extend the in-flight coherence-preflight
  work (`feat-one-shot-6712-...`).
- **1.2 In-surface probe:** fresh host emits `SOLEUR_FRESH_BOOT_READY` (fields: cloud-init stage /
  Vector-installed / token-present / volume-mounted+luksOpen) to Better Stack. **Boot-window timeout**
  quantified (absence-detection deadline — spec-flow P1-8). No SSH in the discoverability test.

### Phase 2 — Complete cattle cloud-init parity artifact (moved FORWARD — advisor Change 1)

- **2.1 Reconcile the exact provisioner set** (Kieran, arch M7): `grep` web-1's SSH provisioners /
  `connection{}` inlines / targeted `terraform_data` siblings — plan prose said "11", model.c4:413 says
  "12", `terraform-target-parity.test.ts` counts "7 siblings". Pin the enumeration; a missed one is the
  #6459 silent-boot class. Gate on ADR-136 preapply-entrypoint-enumeration.
- **2.2** Author the **complete cattle cloud-init** encoding every reconciled provisioner's behavior + the
  Phase-1 readiness assertions. web-2 (Phase 3) is born from **this exact artifact**, so Phase 4's
  disposability proof genuinely de-risks the Phase-5 web-1 rebuild.

### Phase 3 — Birth fresh cattle web-2 (out-of-band standby, weight 0, `replicas=1` held)

- **3.1** Add `web-2` to `var.web_hosts` (DC + orderable type from 0.2). Rewrite the retirement comments
  (`variables.tf:100-108`, `server.tf:115`, `inngest-host.tf:11`). Auto-fans-out: `server.tf:119` (cattle
  host, from the Phase-2 artifact), `network.tf:40`, `web-probe.tf` (2 heartbeats + 2 Doppler URLs), volume
  + attachment (`server.tf:1571/1582`) — **LUKS-backed** (Encryption Posture). `proxy-tls.tf:38-39`
  regenerates the shared cert but it is **latent** (only the Phase-3 session-router consumes
  `PROXY_TLS_CERT`; nothing loads it at `replicas=1` — arch L8) → coordinate CA reload as a **Phase-6** item.
- **3.2 Out-of-band health only:** web-2 is **not** in any serving rotation. Its `/health` probe
  (`web-2.app.soleur.ai/health`, direct — `web-probe.tf`) asserts **app-readiness + Vector-shipping**, not
  port-open/200-from-proxy (spec-flow P1-7 — a shallow check re-admits the #6538 dark host).
- **3.3 #6608 (sequenced SEPARATELY, own maintenance window):** derive `inngest-host.tf`
  `web_host_private_ips` from `var.web_hosts` via the `inngest-host-replace` dispatch (`user_data` ForceNew
  → force-replaces the prod Inngest host). Must land **before** the Phase-4 soak so the soak validates a
  fully-integrated host (spec-flow P1-10), or the soak's claims are scoped to exclude inngest.
- **3.4** Populate `WEB_HOST_PRIVATE_IPS` in `web-platform-release.yml`; confirm `fan_out_to_peers` reaches
  web-2 (`ci-deploy.sh:201`).
- **3.5 Rebuild the deleted anti-pooling gate (#6575)** — the C1 deliverable. A gate asserting web-2's LB
  weight / serving membership is **0** (health-monitored only) until the Phase-3 flip. Fail-closed.
- **3.6 Parity guards (only the 2 roster-coupled ones go RED here** — Kieran): `inngest-host.test.sh §6b`
  and `web-hosts-fanout-parity.test.sh`. (`web-1-swap-concurrency-parity.test.sh` is a workflow-membership
  guard, not roster; `plugins/soleur/test/terraform-target-parity.test.ts` only couples in **Phase 5** when
  provisioners drop.)

### Phase 4 — Disposability proof: volume-preserving host reprovision (on non-prod data)

- **4.1** Rebuild a host **with a populated LUKS volume attached** (spec-flow P0-1) — the path that
  actually matters, never exercised if you only rebuild empty web-2. Prove: detach → recreate host
  (same key) → reattach → **`luksOpen` (never `luksFormat`)** guarded by a **LUKS-header-presence check** →
  data intact. This exercises the exact Phase-5 mechanism on throwaway data.
- **4.2 `prevent_destroy`** on `hcloud_volume.workspaces` + an **off-host snapshot** taken and
  **restore-tested** before any reprovision (advisor 2b, arch M5).
- **4.3 Soak:** web-2 out-of-band healthy for **N=7 days** (follow-through-enrolled) before PR-2.

## Implementation Phases — PR-2 (Phase 5): de-pet web-1 (gated on PR-1 soak)

### Phase 5 — De-pet web-1 = maintenance-window volume-preserving reprovision (NOT zero-downtime)

The SOLE-COPY volume can live on one host, and web-2 cannot serve it pre-Phase-3, so this is a **brief
maintenance-window operation with downtime**, not zero-downtime blue-green (which needs Phase-3 shared
git-data). The **`web-1` `for_each` key is RETAINED** (29 refs across 6 files — `dns.tf:16`,
`tunnel.tf:54/71`, `server.tf:134` placement predicate, `outputs.tf`, `ci-ssh-key.tf:73`,
`workspaces-luks.tf`); de-pet changes web-1's **lifecycle**, not its **identity** (arch H4).

- **5.1** Confirm the Phase-2 cattle cloud-init reaches full parity for web-1 (verify each `file`
  provisioner's target dir exists — `2026-06-02-cloned-ssh-file-provisioner...`).
- **5.2 Precondition gate (load-bearing, redefined):** enter a **write-quiesce / read-only** window (closes
  the TOCTOU — spec-flow P1-9) → take + restore-verify the **off-host volume snapshot** → assert
  `hcloud_volume.workspaces["web-1"]` is **preserved** (fires on volume-destroy, not server-reprovision;
  the predicate is snapshot-verified, NOT "count un-pushed" which is meaningless for no-remote workspaces —
  spec-flow P0-2). **Failure path defined:** abort, exit the read-only window, resume serving on the
  un-reprovisioned web-1 (no degraded holding state).
- **5.3 Ordered diffs:** (a) **drop `placement_group_id` from `ignore_changes` FIRST** (drained-host
  reboot — `server.tf:267-274` mandates this as the first GA-window diff, guarded by
  `terraform-target-parity.test.ts`); (b) reprovision `hcloud_server.web["web-1"]` as a fresh cattle create
  (volume detached → reattached → `luksOpen`); (c) **then** drop `[user_data]` from `ignore_changes` +
  the provisioners **together** (dropping `user_data` alone force-replaces prematurely — order is
  load-bearing; verified `server.tf:265/289`). Guard on **effect not action** (reboot-forcing in-place
  `update` → operator maintenance-window apply, not `[ack-destroy]`).

### Phase 6 — Concurrent active-active serving — NON-GOAL (external gate, documented)

Requires ADR-068 Phase-3 GA: **#6570** (git-data — the ROOT blocker, `cax11` unorderable), #6441/ADR-115
(NIC + boot-unlock), coordinator routing. Also lands here: the multi-host DNS rewire, the multi-connector
tunnel flip + `cloudflare_load_balancer` (weighted drain — only useful once hosts serve concurrently), and
the proxy-tls CA-reload coordination. Not in scope.

## Non-Goals

- **NG1:** `replicas>1` / concurrent serving — external gate (#6570, ADR-068 Phase-3).
- **NG2:** web-2 in the serving rotation / LB pool at weight>0 — the anti-pooling gate (3.5) forbids it pre-flip.
- **NG3:** `cloudflare_load_balancer` + multi-host DNS rewire + multi-connector tunnel flip — Phase 6.
- **NG4:** Zero-downtime blue-green de-pet — needs Phase-3 shared git-data; Phase 5 is a maintenance window.
- **NG5:** Concurrent-serving orchestration (session affinity, distributed locks) while `replicas=1` (YAGNI).

## Infrastructure (IaC)

### Terraform changes
`variables.tf` (web-2 entry), `server.tf` (cattle cloud-init artifact; Phase-5 de-pet: `ignore_changes` +
provisioner drops), `network.tf`, `web-probe.tf` (out-of-band /health depth), `workspaces-luks.tf`
(`prevent_destroy` + luksOpen contract + snapshot), `inngest-host.tf` (#6608 — separate window),
`placement-group.tf`. **No `load-balancer.tf`** (Phase 6). Providers: `hcloud` (+ snapshot resource).
Sensitive vars: existing `cf_*`, `doppler_token`, R2 backend AWS creds (Doppler `prd_terraform`). **No new
no-default `TF_VAR_*`.**

### Apply path
- **(b) cloud-init + gated dispatch** for web-2 birth (fresh cattle).
- **(c) operator maintenance-window full-apply** for #6608 `inngest-host-replace` and (PR-2) the web-1
  reprovision — via gated `workflow_dispatch` with a **non-empty required-reviewer environment** (DP-11 F8),
  never an SSH runbook.

### Distinctness / drift safeguards
`var.web_hosts` EU-DC + subnet validations; parity guards (3.6, 5.3). `dev != prd` (prd-only root).
`prevent_destroy` on the workspace volume. LUKS binding verified via `workspaces-luks-verify` (measure, ADR-140).

### Vendor-tier reality check
No new paid vendor in this increment (LB deferred). Phase 6's `cloudflare_load_balancer` is a paid add-on +
Data Localization Suite for EU-only termination (spec-flow P1-12) — recorded then.

## Observability

```yaml
liveness_signal:
  what: per-host web heartbeats (web_zot_consumer, web_nic_guard) + per-host origin-absence probe (web-N.app.soleur.ai/health, app-ready depth) + SOLEUR_FRESH_BOOT_READY marker
  cadence: existing web-probe cadence; boot-window timeout quantified for the readiness marker
  alert_target: Better Stack (per-host attribution, #5933 Item 1) + Sentry
  configured_in: web-probe.tf (for_each var.web_hosts), uptime-alerts.tf
error_reporting:
  destination: Sentry (host-tagged, distinct Logs sources per server.tf:232) + Better Stack Logs (Vector)
  fail_loud: true (fresh web-2 MUST ship Vector logs — the #6538 dark-host defect is what we fix)
failure_modes:
  - mode: fresh host boots silently unhealthy
    detection: SOLEUR_FRESH_BOOT_READY absent past the boot-window timeout (in-surface, 2.9.2)
    alert_route: Better Stack absence alert
  - mode: request reaches web-2 before the Phase-3 flip (anti-pooling regression)
    detection: rebuilt anti-pooling gate (3.5) asserts web-2 serving-weight == 0, fail-closed
    alert_route: CI gate blocks; Sentry on violation
  - mode: host reprovision reformats the SOLE-COPY volume
    detection: LUKS-header-presence check before luksOpen (Phase 4.1/5.3); prevent_destroy on the volume
    alert_route: apply aborts; Sentry
  - mode: web-2 ships zero telemetry (the #6538 regression)
    detection: Better Stack per-host log count == 0 over window
    alert_route: betterstack-query.sh recurrence poller
logs: {where: Better Stack Logs source 2457081 (per-host) + Sentry, retention: existing}
discoverability_test:
  command: bash scripts/betterstack-query.sh "host:soleur-web-2 | count"   # NO ssh (repo-root scripts/)
  expected_output: non-zero within the boot window (web-2 is NOT dark)
```

#### Soak Follow-Through Enrollment
Phase 4.3 soak (web-2 out-of-band healthy **N=7 days** before PR-2). Add
`scripts/followthroughs/web2-standby-soak-6459.sh` (exit 0 when the soak holds), the
`<!-- soleur:followthrough script=… earliest=<deploy+7d> secrets=BETTERSTACK_* -->` directive + `follow-through`
label on #6459, and wire secrets into `scheduled-followthrough-sweeper.yml`.

## Architecture Decision (ADR/C4)

### ADR
**ADR-142** (provisional; re-verify next-free at ship, sweep planning docs if renumbered): "Active-active
web ingress + drain-gated host lifecycle." Records the /workspaces failover data mechanism (0.1), the
anti-pooling invariant (two axes: replicas vs serving-weight), the web-1 key-retention invariant, and the
volume-preserving reprovision contract. Amends `hr-prod-host-config-change-immutable-redeploy` + ADR-103;
extends ADR-068. Status `adopting`.

### C4 views
Container view: `hetzner` becomes a 2-host cluster (1 serving web-1 + 1 out-of-band standby web-2). Correct
the single-host notes at **model.c4:178, :186, :413** (NOT :182 — arch L9). **No load-balancer element**
(Phase 6). External-actor enumeration checked against all three `.c4`: end-user (modeled), Cloudflare
(modeled), Hetzner (modeled) — **no new external element** this increment (web-2 is an internal cluster
member). Run `c4-code-syntax.test.ts` + `c4-render.test.ts`.

### Sequencing
ADR-142 `adopting` now (target state); flips `accepted` when the cluster + de-pet land. Concurrent serving
+ LB element = Phase 6.

## Encryption Posture

```yaml
at_rest:
  - store: web-2 /workspaces block volume (hcloud_volume.workspaces["web-2"])
    mechanism: guest-side LUKS2, /dev/mapper/workspaces (mirror web-1's 2026-07-23 cutover)
    evidence: workspaces-luks-verify reports SOLEUR_WORKSPACES_READYZ against /dev/mapper/workspaces (measure — ADR-140)
    defends_against: seized/snapshot disk at rest
    does_not_defend: live host with volume unlocked (host compromise); a reformat of the header
    disclosed_as: privacy-policy LUKS-at-rest claim (published)
    live_verification: workspaces-luks-verify on web-2 post-boot
  - store: off-host volume snapshot (Phase 4.2 / 5.2 backup)
    mechanism: Hetzner volume snapshot of the LUKS ciphertext (snapshot is of the encrypted device; plaintext never leaves the guest)
    evidence: Hetzner snapshot (named at-rest attestation); restore-test verifies luksOpen succeeds
    defends_against: permanent loss on a botched reprovision
    does_not_defend: LUKS passphrase compromise (same key domain as the volume)
    disclosed_as: internal DR control
    live_verification: restore-test before any reprovision
in_transit:
  - connection: CF edge → web-1 origin (unchanged this increment)
    tls: yes (CF edge terminates; origin firewall gates 443 to CF IPs)
    cert_verification: on
    does_not_defend: compromised CF account
    disclosed_as: existing CF-proxied posture
# cross-host replication (Phase-3) is NG1 — no in-transit row here; its Art. 30 entry is drafted-not-active.
# No plaintext-exception rows: web-2 volume is LUKS from birth.
```

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carry-forward from brainstorm `## Domain Assessments`).

### Engineering
**Status:** reviewed (carry-forward + 6-agent plan panel). CTO/platform/terraform-architect assessments +
the panel corrections (anti-pooling gate, volume contract, key-retention) are integrated above.

### Product
**Status:** reviewed (carry-forward). CPO — decouple build from flip; gate on fresh-boot; prove on web-2
first; destroy-web-1 is a confidence milestone (now PR-2); YAGNI on concurrent-serving orchestration.

### Legal
**Status:** reviewed (carry-forward). CLO — both hosts hel1/EU; lost SOLE-COPY work = availability breach
(Art. 33 72h); threshold single-user incident. **Art. 30 register entry for cross-host replication is
DRAFTED, NOT-YET-ACTIVE** (no inter-host transfer occurs at `replicas=1` — DHH AC9). Activated at Phase 6.

### Product/UX Gate
**Tier:** N/A — no UI surface (all `.tf`/`.sh`/`.yml`/`.c4`). **Pencil available:** N/A.

## Acceptance Criteria

### Pre-merge (PR-1) — merge-time checkable (gate logic present + unit-tested failing case)
1. ADR-142 authored (`adopting`, decides failover data mechanism + key-retention + anti-pooling invariants);
   C4 `model.c4`+`views.c4` updated (:178/:186/:413, no LB element); `c4-code-syntax`+`c4-render` green.
2. Live stock probe output for **both** cx33 (web) and cax11 (git-data) + web-2 type/DC verdict recorded in ADR-142.
3. Fresh-boot readiness assertion **code present** + unit-tested; `SOLEUR_FRESH_BOOT_READY` emit-code present with a quantified boot-window timeout.
4. Complete cattle cloud-init artifact present; the reconciled provisioner enumeration is pinned (grep-verified count, ADR-136 gated).
5. web-2 entry added; the **2 roster-coupled** parity guards green (`inngest-host.test.sh §6b`, `web-hosts-fanout-parity`); web-2 volume is LUKS-backed in HCL.
6. `terraform plan` shows **no create/replace** of the prod Inngest host from the web-2 add (#6608 is separate).
7. **Anti-pooling gate rebuilt** (#6575) — unit-tested to FAIL when web-2 serving-weight > 0 pre-flip.
8. `prevent_destroy` on `hcloud_volume.workspaces` present; LUKS-header-presence check + luksOpen-not-reformat logic present and unit-tested.
9. web-2 `/health` probe asserts app-readiness + Vector-shipping depth (not port-open).
10. Art. 30 register entry **drafted (not-active)** for cross-host replication.

### Post-merge (operator, gated dispatch) — runtime proofs
11. #6608 `inngest-host-replace` applied (own window) before the soak.
12. **Disposability proof:** rebuild a host with a **populated** LUKS volume; `luksOpen` succeeds, data intact, zero loss (Phase 4.1).
13. Off-host snapshot taken + **restore-tested** (Phase 4.2).
14. web-2 out-of-band soak **N=7 days** passes via the enrolled follow-through probe (Phase 4.3).
15. web-2 ships non-zero telemetry to Better Stack (`scripts/betterstack-query.sh`) — #6538 does not recur.

### PR-2 (Phase 5, gated on PR-1 soak)
16. Pre-destroy gate **dry-run**: inject a synthetic populated volume + un-replicated state, prove the reprovision is **refused** until snapshot verified (DHH AC7).
17. `placement_group_id` dropped from `ignore_changes` as the **first** diff (drained-host reboot); `terraform-target-parity.test.ts` green.
18. web-1 reprovisioned as fresh cattle (key retained); volume re-adopted via luksOpen; then `[user_data]` + provisioners dropped together.

## Open Code-Review Overlap
Check at /work once `## Files to Edit` is frozen: `gh issue list --label code-review --state open` against
the final `apps/web-platform/infra/*.tf` path list (likely infra scope-out overlap).

## Risks & Mitigations
- **Request reaches web-2 pre-flip → workspace-gone** → rebuilt anti-pooling gate (3.5); web-2 out of rotation; AC7.
- **Reformat the SOLE-COPY volume** → luksOpen-not-reformat + header-presence check + `prevent_destroy` + off-host snapshot.
- **web-1 key rename breaks 29 refs** → key-retention invariant stated + parity guard.
- **`cx33`/`cax11` unorderable** → live stock probe (0.2), orderable type only.
- **Inngest ForceNew double-fire** → #6608 separate `inngest-host-replace` window.
- **Silent-boot gap from a missed provisioner** → reconciled enumeration (2.1), ADR-136 gate.

## Sharp Edges
- `## User-Brand Impact` is filled (threshold single-user incident) — passes deepen-plan Phase 4.6.
- web-2 at LB weight>0 pre-flip is the workspace-gone incident — **rebuild the deleted #6575 gate**.
- The **volume**, not the host, is the SOLE COPY — luksOpen-not-reformat + snapshot + `prevent_destroy` are load-bearing.
- The web-1 `for_each` **key is retained** — de-pet is a lifecycle change, never a key rename.
- The `dns.tf` rewrite + #6608 each force-replace a live prod resource — maintenance-window full-apply, never `-target` CI.
