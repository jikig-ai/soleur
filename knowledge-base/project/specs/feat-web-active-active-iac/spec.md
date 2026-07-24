---
feature: web-active-active-iac
title: Active-Active Web Cluster via IaC (re-add web-2, health-gated ingress, blue-green host lifecycle, de-pet web-1)
status: draft
lane: cross-domain
brand_survival_threshold: single-user incident
tracking_issue: 6459
related_issues: [6608, 6538, 6459, 5274, 6416]
adr: needed (host-lifecycle + ingress-drain; amends hr-prod-host-config-change-immutable-redeploy + ADR-103; extends ADR-068)
brainstorm: knowledge-base/project/brainstorms/2026-07-24-web-active-active-cluster-iac-brainstorm.md
approach: A — phased cluster-first, flip-last
date: 2026-07-24
---

# Spec: Active-Active Web Cluster via IaC

## Problem Statement

Soleur's web tier is a single host (web-1), and web-1 is a **pet**: `ignore_changes=[user_data]`, ~11
`web-1`-scoped SSH provisioners, frozen cloud-init. There is no redundancy and web-1 is not
IaC-reproducible. The prior web-2 was a broken `fsn1` orphan (unrebuildable, dark, outside the HA
placement group) and was destroyed 2026-07-17 (#6538). We want a **full active-active cluster** where
every host is disposable cattle, proven by destroying web-1 and rebuilding it purely from IaC.

## Goals

- G1: Re-add a **fresh cattle web-2** (cloud-init-only) in an EU Hetzner DC as a **health-gated warm
  standby**, holding `replicas=1`.
- G2: Build a **health-gated ingress/drain layer** (Cloudflare Load Balancer and/or multi-connector CF
  Tunnel) replacing the singleton `dns.tf` app record — the missing drain primitive.
- G3: Establish **fresh-boot readiness assertions** so a fresh host provably boots to parity unattended.
- G4: **De-pet web-1** into cattle via a blue-green rebuild (fold provisioners → cloud-init; drop
  `ignore_changes=[user_data]`).
- G5: Prove host disposability by **destroy + IaC-rebuild** — on **web-2 first**, then web-1.
- G6: Author the **host-lifecycle + ingress-drain ADR** (resolves #6459).

## Non-Goals

- NG1: **Flipping to concurrent active-active serving (`replicas>1`)** — gated on ADR-068 Phase-3 GA
  (external dependency: #6416 + ADR-115 `luksOpen` → git-data host → coordinator). This spec builds up to
  the flip; the flip is a follow-up.
- NG2: Building concurrent-serving orchestration (session affinity, distributed locking) while
  `replicas=1` (YAGNI per CPO).
- NG3: The #6608 inngest allowlist derivation as part of a web-2-add PR (sequenced as its own
  maintenance-window inngest recreate — `user_data` ForceNew).

## Functional Requirements

- FR1: `var.web_hosts` gains a `web-2` entry; all `for_each` consumers fan out (server, network,
  proxy-tls, web-probe). Rewrite the retirement/"do-not-re-add" comments.
- FR2: Health-gated ingress: per-host serving with health checks; a dead/unhealthy host is failed out
  faster than DNS TTL. LB must terminate/route in-EU.
- FR3: Deploy fan-out reaches all hosts — populate the release-workflow `WEB_HOST_PRIVATE_IPS` roster
  literal; `fan_out_to_peers` (already present) dispatches to peers.
- FR4: Fresh-boot readiness assertions gate any de-pet/destroy (cloud-init `runcmd` full-bootstrap parity;
  no Doppler/systemd env-file silent fallbacks; user_data cap measured on gzipped render).
- FR5: Blue-green host lifecycle: add cattle sibling → drain (LB weight→0 / connector stop) → remove map
  key → destroy. Never `-replace` the sole live host.
- FR6: Precondition guard before any host destroy: **drain complete + zero un-pushed user work** asserted.

## Technical Requirements

- TR1: EU Hetzner DC only (`var.web_hosts` validation). DC placement (hel1 vs cross-DC) resolved in the
  ADR with a live Hetzner stock probe (Open Question #1).
- TR2: Parity guards updated in lockstep: `inngest-host.test.sh §6b`, `web-hosts-fanout-parity.test.sh`,
  `web-1-swap-concurrency-parity.test.sh`, `terraform-target-parity`.
- TR3: Add `create_before_destroy` where add/drain/remove needs it; guard on **effect not action**
  (reboot-forcing in-place `update` is destructive — route to operator maintenance-window apply).
- TR4: `proxy-tls` SAN change regenerates the shared cert — coordinate CA reload.
- TR5: New ADR amends `hr-prod-host-config-change-immutable-redeploy` + ADR-103; extends ADR-068.
- TR6: Cross-host replication → add an Art. 30 register entry (CLO); Art. 34 disclosure path if a cutover
  loses user work.

## Acceptance Criteria (phased, Approach A)

1. Fresh-boot readiness assertions land and pass on a fresh host (G3/FR4).
2. Health-gated ingress/LB live; draining a host removes it from rotation within health-check interval (G2/FR2).
3. Fresh cattle web-2 serving as health-gated warm standby; parity guards green; deploy fan-out reaches it (G1/FR1/FR3).
4. Disposability proven on **web-2** (destroy + IaC-rebuild, zero data loss) (G5).
5. web-1 de-petted to cattle; `ignore_changes=[user_data]` + web-1-scoped provisioners removed (G4/FR5).
6. web-1 destroyed + rebuilt from IaC (drain + zero-un-pushed precondition asserted) (G5/FR6).
7. Host-lifecycle + ingress-drain ADR merged (G6/TR5).

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-07-24-web-active-active-cluster-iac-brainstorm.md`
- ADR-068 (multi-host `/workspaces`); #6459 (blue-green ADR ask); #6608 (inngest allowlist); #6538 (web-2 retirement)
- Prior art: `knowledge-base/project/brainstorms/2026-07-15-hetzner-cap-headroom-brainstorm.md`
