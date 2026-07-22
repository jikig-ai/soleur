# Learning: Scope the shared delivery substrate once; a reused reserved heartbeat URL masks the very break it was meant to catch

**Date:** 2026-07-18
**Context:** Brainstorm design pass for #6438 §1 (off-host "L3" consumer-perspective private-net probe), which surfaced #6548 and #6438 §3 as substrate-siblings.
**Related:** ADR-115 (private-NIC boot convergence), ADR-117 (executable heartbeat arming), #6540 (registry self-ping; the `curl -f` 401 trap), #6400 (14-day silent image-pull outage).

## Problem

An issue framed #6438 §1 as a single greenfield probe with "4 hard blockers." Three separate traps were only visible after verifying the framing against live `main`.

## Key Insights

### 1. Before scoping a single infra tracker item, check for siblings that block on the SAME delivery substrate.

#6438 §1 (zot consumer probe), #6548 (git-data consumer probe), and #6438 §3 (web-host NIC guard) were filed as three items, but all three block on the *same* unbuilt vehicle — the web-host private-net probe cron (`#5274 PR C`). The expensive, risky part (host-resident delivery to running web hosts + honestly arming an unrebuildable host) is **identical** for all three. A one-off §1-only probe pays the full delivery cost for ⅓ the coverage.

**Check:** when a tracker item's delivery target is a host/substrate, grep the heartbeat/monitor manifest and sibling issues for other items whose `tracking_issue` or "unbuilt probe" comment names the same vehicle. Scope the primitive once.

### 2. A heartbeat URL *reserved* for probe A but now *pointing at* monitor B gives OR-masking — a new probe needs its OWN heartbeat.

`ZOT_HEARTBEAT_URL` (`zot-registry.tf:508`) was reserved for the L3 consumer probe. But #6540 (merged in between) repurposed it to feed the registry **self-ping** monitor. Feeding an L3 consumer beat into the same heartbeat means either feeder keeps it `up` (OR-semantics) — so a consumer-only break (web-host→registry private path down) is **masked** by the still-arriving self-ping. The probe would exist, pass CI, and never alarm on the thing it was built to catch.

**Corollary (cardinality):** the same masking recurs one level up. If N feeding hosts share one per-target heartbeat, a per-host break is hidden by a sibling host's healthy ping. Honest per-host detection needs per-(host,target) heartbeats.

**Check:** before reusing any reserved monitor URL, resolve what it points at *now* (`git grep` the secret → the `betteruptime_heartbeat.<name>` it maps to). A monitor with more than one feeder can only alarm when ALL feeders stop.

### 3. Baking a monitor feeder onto an unrebuildable host leaves it dark behind a GREEN manifest.

Web hosts carry `ignore_changes=[user_data]` (`server.tf:266`), so bake-and-extract via cloud-init arms only **fresh creates**. web-1 is unrebuildable — baking alone leaves web-1's probe uninstalled while the executable-arming CI guard (`heartbeat-manifest.ts`, ADR-117) reads GREEN because the *evidence file* exists. That is exactly #6537's inert-monitor shape reproduced one host over. Honest delivery = bake (fresh creates) **+** the automated `ci-deploy.sh` re-seed onto existing hosts (`docker cp`, the `luks-monitor.timer` precedent), gated on a **measured real beat** from the host that can't be rebuilt.

## Session Errors

- **#6438 cites ADR-113 for private-NIC convergence; the real ADR is ADR-115** (ADR-113 is an unrelated concierge ADR); line numbers drifted (`ignore_changes[paused]` at `zot-registry.tf:494/544`, not `:355`). Recovery: located the real ADR by content grep before threading into leader prompts. Prevention: already covered by `2026-07-04-verify-adr-citation-numbers-before-threading-into-subagent-prompts.md` — the premise-check caught it.
- **Spec write blocked by the IaC-routing hook** (`hr-all-infrastructure-provisioning-servers`) on "out-of-band arm" / "SSH provisioner" wording. Recovery: reframed delivery as explicitly automated (Terraform + cloud-init + `ci-deploy.sh` re-seed), added an `## Infrastructure (IaC)` section + `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->`. Prevention: infra brainstorm specs should frame *any* host-delivery step as automated IaC/CI from the first draft — the words "out-of-band" and "SSH provisioner" read as manual even when the mechanism (`docker cp` re-seed in CI) is not. The hook is correct; the fix is author-side framing.
- Roadmap `validate` reported drift on an unrelated **phase 4** milestone. One-off / orthogonal to this topic; not fixed here (belongs to the roadmap-review cron).

## Tags
category: infrastructure-observability
module: web-platform/infra, heartbeat-manifest
