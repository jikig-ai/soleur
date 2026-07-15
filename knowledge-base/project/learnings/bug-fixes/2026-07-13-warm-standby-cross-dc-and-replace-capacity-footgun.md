---
title: HA hosts must span different DCs; `-replace` recreate during a capacity outage is a self-inflicted deploy-wide outage
date: 2026-07-13
category: bug-fixes
tags: [infra, terraform, hetzner, high-availability, placement-group, warm-standby, capacity]
severity: high
related: [6374]
---

## What happened

While investigating a false-positive inngest health alarm (#6374), the weight-0 warm-standby web host **web-2** was found wedged after a fresh-boot, so it was recreated via the sanctioned `apply-web-platform-infra` **`web-2-recreate`** path (terraform `-replace` of `hcloud_server.web["web-2"]`). web-2 was pinned to **hel1 — the SAME DC as prod web-1**. Hetzner hel1 was capacity-starved at the time, so terraform **destroyed web-2, then could not re-place it** (`error during placement (resource_unavailable)`), and it **retried destroy→create-fail four times**.

Two compounding failures resulted:

1. **web-2 gone** — no warm-standby / failover coverage.
2. **Every `terraform apply` wedged** — web-2 was still in config (`var.web_hosts`) but no longer in state, so *each* apply-on-merge (routine `Apply web-platform infra` **and** the auto-firing `Apply deploy-pipeline-fix`) tried to recreate it and failed on the same capacity wall. A single failed recreate became a **repo-wide deploy blocker**: an unrelated PR's on-host scripts could not be delivered.

Prod itself stayed healthy throughout (web-1 untouched), which is exactly why this was easy to miss — the damage was to the *deploy pipeline*, not the running app.

## Root causes

- **Same-DC standby.** A warm standby in the same DC as prod protects against a single-host failure but NOT a DC-level outage or a DC-level capacity shortage — and the capacity shortage is precisely when you most need to (re)provision.
- **`-replace` is destroy-then-create.** For a singleton host, if the create cannot place, you are left strictly worse off than before (host gone + wedged state). There is no automatic rollback.
- **A destroyed-but-in-config resource poisons all applies.** Terraform reconciles the whole config on every apply; a resource that can't be created blocks every future apply until it's resolved.

## Fixes applied

- **Relocate web-2 hel1 → fsn1** (a different EU DC, eu-central network zone so `10.0.1.11` still attaches; EU per CLO T-1). Cross-DC placement is *stronger* HA than same-DC spread and stays placeable when web-1's DC is capacity-starved. (`variables.tf`)
- **Gate placement-group membership on co-location with web-1.** Hetzner placement groups are location-scoped, so a cross-DC host can't join `web_spread` — it now gets `null` instead of failing the apply. (`server.tf`)

## Prevent next time

- **Default HA/standby hosts to distinct DCs** (within the same EU network zone for private-net + GDPR). Same-DC redundancy is not redundancy against the failure modes that matter (DC outage, DC capacity).
- **Treat a host `-replace` during a suspected capacity window as high-risk.** Prefer capacity-check-first or create-before-destroy for a singleton; at minimum, know that a failed create leaves the host gone AND wedges applies.
- **Workflow improvement (follow-on):** the `apply-web-platform-infra` `web-2-recreate` path should surface the destroy-then-can't-recreate risk (and ideally pre-check target-DC capacity or offer a relocate-instead option) rather than silently destroying first. Tracked for the recreate-path hardening.
