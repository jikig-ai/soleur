# Learning: tightening gc/retention TIMING can't reclaim below the keep-SET — and a telemetry-gated contingency firing on schedule

**Date:** 2026-07-09
**Feature:** `feat-one-shot-zot-disk-full-capacity-retention` (PR #6284, Ref #6247)
**Context:** LIVE INCIDENT — the self-hosted zot OCI registry (Hetzner, deny-all, no-SSH) 30 GB `/var/lib/zot` volume was 100% full and zot was crash-looping on ENOSPC. A recurrence of the 2026-07-08 disk-full incident (#6240/#6246) whose primary fix HELD.
**Rules served:** `hr-no-dashboard-eyeball-pull-data-yourself`, `hr-observability-as-plan-quality-gate`.

## Problem

The 2026-07-08 remediation (#6246) fixed a silently-swallowed `resize2fs` (the fs was never grown to the 30 GB device) AND, as defense-in-depth, tightened gc/retention **timing**: `gcInterval` 24h→1h, `retention.delay` 24h→2h. It explicitly left the retention **keep-set unchanged**. Days later the same `SOLEUR_ZOT_DISK` alert fired again: `pcent=100 fs_size_gb=30 block_size_gb=30 resize_ok=true zot_restarts=908`.

## Key Insight — gc/retention TIMING and the keep-SET are orthogonal levers; faster gc cannot reclaim a blob the policy says to KEEP

`resize_ok=true` + `fs_size_gb=30=block_size_gb` positively proved this was **NOT** a resize regression — the ext4 fs was fully grown and the 30 GB was **genuinely full of retention-KEEP blobs**. The keep-set (`latest` + **unbounded** `sha256-.*` cosign sig referrers + **10** `v*` + **10** commit-sha tags, **per repo across 2 platform-image repos**, each image ~1.5–2 GB) legitimately exceeds 30 GB. gc reclaims only DANGLING blobs; it never touches a blob a `keepTags` policy retains. So the #6246 timing tightening — no matter how aggressive — could never reclaim below a KEEP set that is itself larger than the volume.

**Diagnostic discriminator (no SSH):** the `SOLEUR_ZOT_DISK` fields alone separate the three post-fix hypotheses in ONE event — resize-not-applied (`resize_ok=false` OR `fs_size_gb << block_size_gb`), **gc-can't-keep-up / keep-set-too-big** (`resize_ok=true`, `fs≈block`, `pcent≥85`), and mid-write-crash (`pcent<85`, `zot_restarts>0`). Reading the block-device size (the 2026-07-08 mistake) would again have looked "healthy"; the guest `df%` marker is the truth.

**Fix = the OTHER two levers, not more timing:** (1) grow the volume 30→60 GB (headroom); (2) tighten the keep-SET (`mostRecentlyPushedCount` 10→5 for v*/commit-sha; bound the unbounded `sha256-.*` at 50). Growing alone delays the refill; tightening alone leaves near-zero margin — both give a durable bound.

## Key Insight — a telemetry-gated contingency that fires exactly as pre-registered is the payoff of "observability as a plan deliverable"

The 2026-07-08 postmortem did NOT just fix-and-forget. It pre-registered issue **#6247** with a precise, telemetry-keyed trigger: "grow the volume ONLY IF, post-redeploy, `SOLEUR_ZOT_DISK` shows `resize_ok=true` AND `fs≈full` AND `pcent≥85` after the tightened gc has run — NOT if the resize simply hadn't applied." Days later that exact condition was met. The recurrence was resolved in one pass: pull the marker → the fields matched the pre-written trigger → apply the pre-decided fix. No re-diagnosis, no re-litigation of "is the disk really full." That is the compounding value of writing the discriminating telemetry AND the contingency's decision rule into the postmortem, not just the symptom.

Corollary caution: #6247 had been CLOSED-COMPLETED prematurely ("not-yet-needed") even though the postmortem still listed it open. Reopen a telemetry-gated contingency on trigger; don't let a premature close hide a pre-registered fix.

## Session Errors

1. **Plan subagent: transient "modified since read" linter race + duplicate Downtime/Research-Insights sections from auto plan-review.** De-duplicated via heading-count grep; final file verified clean. One-off. **Prevention:** already handled inline by the plan skill's dedup pass.
2. **Full-suite exit gate (`test-all.sh`) exited 1 on 6 webplat tests (pdf/email-triage/inngest) under the Doppler-dev run.** Confirmed pre-existing env-flake class (files not in diff; main CI green; passed 57/57 CI-equivalent without Doppler). Correctly diagnosed, not a regression. **Prevention:** already codified — work skill Phase 2 exit-gate caveat ("re-run the failing file WITHOUT Doppler before treating a webplat failure as a regression").
3. **Self-introduced doc imprecisions caught at review (2 P3):** `variables.tf` attributed the 30 GB overflow to the post-tighten (5+5) keep-set instead of the prior (10+10+unbounded) set; and the ADR-087 consequence note used the correct enforce-flip issue #6129 while the pre-existing line-22 reference still said #5933, making the ADR self-contradict. Both fixed inline. **Prevention:** when a PR edits a doc that carries a sibling stale cross-reference to the same fact you're updating, reconcile the sibling in the same edit (the doc-self-consistency check the architecture reviewer applied).

## Tags
category: best-practices
module: apps/web-platform/infra (zot registry, storage.retention, SOLEUR_ZOT_DISK)
related: ADR-096, ADR-087, #6247, #6246, #6240, #6244, #6129, hr-no-dashboard-eyeball-pull-data-yourself, hr-observability-as-plan-quality-gate
tags: [zot, oci-registry, disk-full, gc, retention, keep-set, capacity, cosign, telemetry-gated-contingency, deny-all-host, no-ssh, betterstack]
