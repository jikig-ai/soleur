---
feature: off-host-l3-probe
issues: [6438, 6548]
parent_vehicle: 5274
branch: feat-off-host-l3-probe-6438
pr: 6654
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-07-18-off-host-l3-probe-brainstorm.md
status: brainstorm-complete
date: 2026-07-18
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- All delivery in this spec is Terraform + cloud-init + the automated ci-deploy.sh re-seed
     (docker create → docker cp from the running web-platform container on every app deploy).
     There is NO manual/operator install step. The plan's Phase 2.8 will invoke terraform-architect
     and turn each item below into concrete .tf resources + a baked bootstrap script. -->

# Spec: Web-host private-net probe primitive (off-host "L3" + §3 NIC guard)

## Problem Statement

The shipped private-NIC convergence work (L1 on-host converger + L2 emit→alarm, #6415/ADR-115; registry self-ping, #6540) monitors each dedicated host's **own** NIC. None of it can detect "the private net is broken from a **consumer's** perspective while the target host thinks its own NIC is fine" — e.g. a web host silently loses its private-NIC path to the zot registry (`10.0.1.30`) or git-data (`10.0.1.20`), falls back to GHCR / degrades, and every health signal stays green (the #6400 shape: ~14 days silent). Three tracked gaps — #6438 §1 (zot consumer probe), #6548 (git-data consumer probe), #6438 §3 (web-host NIC self-guard) — all block on the same unbuilt vehicle, the **web-host private-net probe cron** (`#5274 PR C`).

## Goals

- **G1.** Deliver a host-resident probe substrate to the web hosts (`10.0.1.10`/`.11`) that survives the `ignore_changes=[user_data]` constraint on **both** rebuildable (web-2) and unrebuildable (web-1) hosts, entirely through IaC/CI (no operator step).
- **G2.** Detect a consumer-side private-net break to zot (`10.0.1.30`) — #6438 §1.
- **G3.** Detect a consumer-side private-net break to git-data (`10.0.1.20`) — #6548.
- **G4.** Deliver the ADR-115 on-host NIC self-convergence guard to the web hosts — #6438 §3.
- **G5.** Every new monitor is **honestly armed** — a real beat measured from each feeding host before unpause; no inert/GREEN-but-unfed monitor (ADR-117 CI guard stays green legitimately).

## Non-Goals

- **NG1.** Paid-tier escalation / webhook policies — owned by #6549 item 1; L3 inherits email-only.
- **NG2.** Extending the reboot primitive to git-data/inngest — blocked by the ADR-115 LUKS normative blocker (#6438 §2, out of scope).
- **NG3.** A fallback-usage alarm (sustained GHCR-fallback ⇒ zot down) — a complementary signal, filed separately if wanted.
- **NG4.** Any change to the #6540 registry self-ping monitor beyond disposition of the stale reserved `zot_heartbeat_url_prd` secret.

## Infrastructure (IaC)

Everything here is provisioned as code — no manual host mutation (`hr-all-infrastructure-provisioning-servers`):

- **Terraform:** new `betteruptime_heartbeat` resources (one per Open-Q1 cardinality decision) + new `doppler_secret` URL secrets; disposition of the reserved `zot_heartbeat_url_prd`; the one-time arm PATCH runs inside the existing `apply-web-platform-infra.yml` job (Better Stack API pattern already at `~:1968`).
- **cloud-init (baked image):** the probe systemd timer + unit + script, and the §3 NIC guard, baked into `var.image_name` (ADR-080 bake-and-extract) — arms web-2 and every fresh create.
- **Automated CI re-seed (no SSH-by-hand):** `ci-deploy.sh` already re-seeds baked content onto the running web hosts via `docker create` → `docker cp` on every app deploy; web-1 (unrebuildable) is armed through this existing automated path, gated on a measured real beat.
- **CI guard:** the executable `feeder` rows in `heartbeat-manifest.ts` are the enforcement surface (ADR-117).

The plan's Phase 2.8 invokes `terraform-architect` to turn each of the above into concrete `.tf` + bootstrap-script diffs.

## Functional Requirements

- **FR1.** A host-resident **systemd timer** on each web host probes its private-net targets; `OnUnitActiveSec≈60s`, `AccuracySec=1s`; **no `curl -f`** — status-code discrimination (`200|401` alive, `5xx` wedged, `000` unreachable), reusing #6540's contract (`cloud-init-registry.yml:335-361`).
- **FR2.** Each consumer probe pings a **new, dedicated** `betteruptime_heartbeat` + **new URL secret** — never the reserved `ZOT_HEARTBEAT_URL` (= #6540 self-ping; sharing masks consumer-only breaks). Heartbeat cardinality resolves the per-(host,target) vs per-target masking question (Open Q1) before Terraform.
- **FR3.** Delivery is dual-path, both automated: **bake** into the image/cloud-init (web-2 + all fresh creates) **and** the automated `ci-deploy.sh` re-seed onto **web-1** (`docker cp`, the `luks-monitor.timer` precedent), with a **measured real beat from web-1** as the arming gate.
- **FR4.** Arming replays #6540/ADR-117: heartbeat created `paused=true` + `ignore_changes=[paused]`; an **executable `feeder` row** per probe in `plugins/soleur/lib/heartbeat-manifest.ts`; a one-time Better Stack API PATCH under the bounded arm-and-watch inside the apply workflow.
- **FR5.** The §3 web-host NIC self-convergence guard (ADR-115 L1 pattern) is delivered via the same substrate as a separate script.
- **FR6.** git-data probe uses a git-data-appropriate health contract at `10.0.1.20` (Open Q2).

## Technical Requirements

- **TR1.** `betterstack_paid_tier` stays `false`; heartbeats inherit `policy_id = var.betterstack_paid_tier ? ... : null` (email-only), consistent with every sibling infra beat.
- **TR2.** New heartbeat parity: each new beat adds its own row to the ADR-103 parity manifest (`heartbeat-reprovision-parity.test.ts`); do not perturb `registry_prd`'s existing `60/30` assertion.
- **TR3.** The `feeder` evidence file+pattern for each probe must be `grep -F`-verifiable on every CI run (the ADR-117 forcing function); the no-green-AC gate is satisfied by the guard, not by prose.
- **TR4.** Immutable-redeploy safety (ADR-103/#6122): any web-host `-replace` used to arm baked content must include dependents (`hcloud_server_network`, firewall/volume attachments), and must account for the first-boot NIC race (ADR-115). All `-replace` runs are Terraform-driven in CI.
- **TR5.** Reconcile the stale reserved `zot_heartbeat_url_prd` secret + its `zot-registry.tf:508` comment in the same PR (repoint vs delete — Open Q3).

## Acceptance Criteria

- **AC1.** A simulated private-net break from web-1 to `10.0.1.30` (and to `10.0.1.20`) causes the corresponding heartbeat to go **down** and alarm — verified from a real measured beat, not a passing unit test alone.
- **AC2.** `heartbeat-manifest.ts` CI guard is green **because** every new row is honestly fed (executable feeder) or honestly declared unfed with an owning issue — never GREEN-but-inert.
- **AC3.** web-1's probe is demonstrably armed (measured beat) — the delivery does not leave web-1 dark behind a green manifest.
- **AC4.** No shared-heartbeat masking: a per-host consumer break is not hidden by a sibling host's healthy ping (per the Q1 cardinality decision).

## Open Questions

See the brainstorm's Open Questions Q1–Q7 (heartbeat cardinality, git-data contract, reserved-secret disposition, arming enum, web-1 re-seed mechanics, §3 reboot/lease interaction, bundle sequencing). Resolve in `/plan`.

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-07-18-off-host-l3-probe-brainstorm.md`
- ADR-115 (private-NIC boot convergence), ADR-117 (executable heartbeat arming), ADR-103 (guarded reprovision)
- #6540 (registry self-ping arming; the `curl -f` 401 trap), #6415 (L1+L2, closed), #6400 (root incident), #6122 (prior race)
- `plugins/soleur/lib/heartbeat-manifest.ts`, `apps/web-platform/infra/{zot-registry,git-data,server,variables}.tf`, `apps/web-platform/infra/cloud-init-registry.yml`, `.github/workflows/apply-web-platform-infra.yml`
