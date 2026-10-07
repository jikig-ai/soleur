---
title: Worktree cleanup — Docker builder cache and /var/tmp scratch drain
status: draft
owner: engineering
issue: 9677
brainstorm: knowledge-base/project/brainstorms/2026-10-07-worktree-cleanup-docker-and-scratch-brainstorm.md
lane: cross-domain
brand_survival_threshold: single-user incident
created: 2026-10-07
---

# Spec: Worktree cleanup — Docker builder cache and /var/tmp scratch drain

## Problem Statement

`worktree-manager.sh cleanup-merged` removes merged worktrees but leaves disk behind: undrained quarantine and leaked marker-bearing scratch in `/var/tmp`, and Docker build cache. On a btrfs host with snapper, freed space also stays pinned by snapshots, so a "reclaimed N GB" message overstates what the operator sees. The plugin runs on customer machines, so any destructive behaviour must be conservative.

## Goals

- **G1.** Opt-in Docker builder-cache prune that cannot touch volumes, containers or non-dangling images.
- **G2.** Session-start sweep drains expired quarantine entries, with no installed timer required.
- **G3.** Leaking marker producers (`gdboot.*` first) clean up at exit.
- **G4.** The root cause of surviving marked dirs is named with a measurement.
- **G5.** Cleanup prints logical bytes reclaimed beside the measured `df` delta, and names snapper/btrfs pinning when detectable.

## Non-Goals

- **NG1.** Worktree/branch stamp in `.soleur-owned` and reaping scratch with its worktree (deferred issue).
- **NG2.** Report-only listing of unmarked `/var/tmp` dirs (deferred issue).
- **NG3.** Label-scoped Docker prune or global `image prune -a` (no local build stamps a label; shared daemon).
- **NG4.** Any deletion of snapshots, volumes or containers; any telemetry egress from customer machines.

## Functional Requirements

- **FR1.** `SOLEUR_DOCKER_PRUNE=1` runs `docker builder prune` + dangling-image prune in dry-run; `=apply` executes. Emits one `SOLEUR_DOCKER_PRUNE ...` stdout line with bytes. No `docker` → clean skip.
- **FR2.** `sweep_orphan_scratch_dirs` drains quarantine entries past TTL (7 d scratch, 30 d worktrees) within the existing timebox and `flock`.
- **FR3.** `scripts/lib/git-data-boot-signal-poll.sh` and other marker writers use the ADR-250 allocator or an EXIT cleanup.
- **FR4.** PR body records survivors classified as age-gate-held / quarantined / stuck, with counts re-derived two ways.
- **FR5.** Cleanup output shows `df` before/after for `/` and one line naming btrfs+snapper pinning when `findmnt -no FSTYPE /` is btrfs and `/etc/snapper/configs/root` exists (read-only; no root needed).
- **FR6.** Operator action (not plugin code): install `tmpfs-guard.timer` on this host per the runbook.

## Technical Requirements

- **TR1.** Amend ADR-250 (drain trigger, producer cleanup) via `soleur:architecture`.
- **TR2.** Tests with a fake `docker` shim and fixture `/var/tmp`; fixture `findmnt`/snapper config; assert volumes/containers never invoked.
- **TR3.** Sweep every marker writer before changing producers (`scratch-root.sh`, `git-data-boot-signal-poll.sh`, `credential-persist-home-guard.bench.sh`, `plugins/soleur/test/lib/scratch-session.ts`).
- **TR4.** New markers are stdout-only (Privacy Policy "does not phone home"); observability layer-7 citation required in the plan.
- **TR5.** Opt-in value exactly `"1"` per repo convention.
