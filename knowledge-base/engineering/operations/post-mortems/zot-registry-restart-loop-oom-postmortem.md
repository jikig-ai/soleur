---
title: "zot registry container restart-loop (~4/min) — disk-independent OOM residual of the disk-full incident, hidden by a memory-blind reporter"
date: 2026-07-09
incident_pr: 6288
incident_window: "2026-07-09 ~16:55–18:00 UTC (zot_restarts climbed 0→261 on the freshly-replaced host, ~4/min, disk at 58–63% — non-ENOSPC)"
recovery_at: "2026-07-09 (telemetry + cx32 + ADR-062 memory cap merged in #6288; full recovery verified by the post-merge registry-host-replace redeploy + the ≥2h soak follow-through)"
suspected_change: "Latent since the registry host was introduced (#6122): the `docker run --name zot` carried no `--memory` limit, and the cx23 host had only 4 GB. zot's boot scan of the preserved ~35 GB store exceeded available RAM → host OOM-kill → `--restart unless-stopped` → loop. Surfaced now because the disk-full fix (#6284) replaced the host onto the preserved (large) store, and the fresh boot re-scanned it."
brand_survival_threshold: none
status: resolved
triggers:
  - availability (deploy pipeline / self-hosted zot registry-mirror step)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
# Classification rationale: availability-only reliability degradation of a REDUNDANT path.
# Every pull path has an atomic GHCR fallback (ADR-096); prod /health stayed 200 and the
# post-merge zot-mirror push succeeded throughout, so there was NO user-facing outage and NO
# SLA breach — brand_survival_threshold is `none`. The zot host holds only OCI image blobs
# (no customer PII, no auth material, no schema). No confidentiality or integrity loss —
# GDPR Art. 33/34 do not apply (availability-only, personal-data non-event).
---

# zot registry restart-loop (OOM) — the disk-independent residual of the disk-full incident

## Summary

After the zot disk-full was definitively fixed (volume grown 30→60 GB, retention tightened; #6284,
merged 2026-07-09 16:50 UTC), the zot **container kept restart-looping ~4/min** on the
freshly-replaced host — with the disk at **58–63%, NOT ENOSPC**. `SOLEUR_ZOT_DISK zot_restarts`
climbed 0→261 across 16:55–18:00 UTC and kept climbing **straight through the ~17:53 first-gc
window**, falsifying the "self-resolves as gc reclaims" hypothesis. This was a **separate,
disk-independent cause**: OOM during zot's boot scan of the preserved ~35 GB store on the 4 GB cx23
host, whose `docker run` had no `--memory` cap.

**No user impact.** The registry is GHCR-fallback-covered on every pull path (ADR-096); prod
`/health` stayed 200 and the post-merge CI zot-mirror push succeeded throughout. This was reliability
degradation of a redundant path, not an outage.

## Root cause

- **Undersized host + uncapped container.** cx23 = 2 vCPU / **4 GB**; `docker run --name zot`
  carried no `--memory`/`--memory-swap` limit. zot's startup scan of the ~35 GB store working-set
  exceeded free RAM → the kernel OOM-killer reaped zot → `--restart unless-stopped` restarted it →
  it re-scanned → OOM again. The ~15 s crash cycle never let a scan/gc complete.
- **The reporter was memory-blind, so the cause was un-diagnosable from telemetry.** The
  `SOLEUR_ZOT_DISK` self-report carried only disk/restart fields — no memory, no exit reason, no
  OOM signal — on a deny-all-ingress, no-SSH host. "restarts climbing at 58% disk" was all the
  operator could see; OOM could not be confirmed without SSH (which the surface forbids).

## What went well

- The disk-fix telemetry (`SOLEUR_ZOT_DISK zot_restarts`) surfaced the residual loop immediately and
  distinguished it from the disk-full (restarts climbing while pcent stable → not ENOSPC).
- GHCR atomic fallback fully masked the registry self-outage — zero user-facing impact.

## Resolution (shipped in #6288)

1. **Closed the telemetry gap (load-bearing).** Enriched the reporter with `mem_total_mb`
   (context; `mem_used_mb` was added here too but subsequently dropped, #6292 —
   page-cache-confounded), **`zot_oom_kills`** (monotonic `memory.events oom_kill` counter — the
   real cgroup-OOM confirmation, survives point-sampling), `zot_anon_mb` (anon-RSS context),
   `state_status`/`oom_killed`/`exit_code`, `oom_kills_5m` (journald backstop), `zot_last_err`
   (non-OOM escape), and `boot_id` (old/new-host discriminator). The next crash self-reports
   OOM-vs-not from Better Stack with no SSH.
2. **Remediated the sizing.** cx23→**cx32 (8 GB)** + an **ADR-062 `--memory=7168m --memory-swap=7168m`**
   cap so a host-level OOM cannot restart-loop the box (it becomes a contained, observable
   cgroup-OOM instead). Applied via the guarded `registry-host-replace` dispatch (store volume
   preserved).

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur.

The telemetry enrichment, the cx32 bump, the memory cap, the ledger correction, and the ADR/C4
updates all shipped in the source PR (#6288). Post-merge verification (dispatch
registry-host-replace → the ≥2h `SOLEUR_ZOT_DISK` soak confirms `zot_restarts` plateaus,
`zot_oom_kills`=0, `zot_anon_mb` below the cap) is mechanized by the enrolled follow-through probe
`scripts/followthroughs/zot-restart-plateau-6288.sh`, so it is NOT a manual row. The only residual
items are tracked:

| Issue | Action | Status |
|---|---|---|
| #6288 | Soak the post-replace host ≥2h; the enrolled follow-through auto-closes on plateau (`zot_restarts` flat, `zot_oom_kills`=0, `exit_code≠137`, `zot_anon_mb` below cap) or reopens with the decode-table pointer. | post-merge (follow-through enrolled) |
| #6291 | Provision a DURABLE Better Stack Logs recurrence alarm (`exit_code=137` / climbing `zot_restarts` / `oom_kills_5m>0`) to cover restart-loop liveness after the soak probe closes #6288 — not Terraform-expressible with the current `betteruptime` provider, so deferred. | deferred (tracked) |
