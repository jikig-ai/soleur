---
title: Verify storage topology before accepting an issue's "durability" framing
date: 2026-06-14
category: integration-issues
tags: [brainstorm, premise-validation, infra-topology, agent-sessions, terraform, web-platform]
module: apps/web-platform/server
issue: 5240
---

# Learning: a "physical durability" symptom can be a binding-resolution bug — verify the storage topology first

## Problem

Issue #5240 framed a backend agent-session failure ("continue where you left off" → "no git
repository, no worktrees… nothing to resume from") as a **physical workspace durability** problem,
with the leading hypothesis that the workspace filesystem is **ephemeral per backend
container/sandbox**. Accepting that framing would have scoped an expensive feature: workspace
snapshot/restore, persistent-volume re-attach, or deterministic re-clone (design point #2).

## Solution

Before accepting the durability framing, verify the actual storage topology in the deploy/IaC
config — not the issue body. Two independent agents (an Explore pass + the CTO) read the Terraform
and confirmed:

- `/workspaces` → `/mnt/data/workspaces` is a **persistent Hetzner block volume**
  (`apps/web-platform/infra/server.tf:847-861`; corroborated by `cron-workspace-gc.ts`). It
  survives process restarts, redeploys, and crashes.
- **Single backend instance, no horizontal scaling** (`hcloud_server.web`, no replicas/LB) — a
  reconnect cannot land on a different process/host.

This **inverted the issue's hypothesis**: the cloned repo + in-flight worktree were almost
certainly still on disk. The real bug is **binding-resolution drift** — on resume,
`resolveActiveWorkspacePath` "never returns null" and silently falls back to the *solo* workspace
(`workspace-resolver.ts:339`), a different `workspace_id` where the repo was never cloned. The
expensive durability work (#2) collapsed; the fix became cheap: verified deterministic rebind +
honest UX.

## Key Insight

A "fresh filesystem / data gone" symptom on a **persistent-volume, single-instance** backend is
evidence of **wrong-resource resolution (a silent fallback)**, not lost data. Issue bodies are
written from a mental model of the failure, and "the data is gone" is the natural (but often
wrong) read of an empty resolved path. Before letting a durability/persistence framing scope a
feature, grep the IaC for the actual storage tier (`hcloud_volume`, mount points, replica counts)
and decide which of two very different bugs you have:

- **Ephemeral storage** → durability is real, scope is large.
- **Persistent storage + a never-null resolver fallback** → the data is intact; you have a
  resolution/binding bug, scope is small.

The silent fallback that "never returns null" is the tell: it converts a missing-binding error
into a confident wrong answer, which then *reports* as data loss.

## Session Errors

Session error inventory: none detected. Clean brainstorm — the premise correction was a research
finding, not a backtrack. The persistent-volume verification was done in parallel with the
domain-leader triad, so the corrected framing was available before any approach was authored.

## Tags

category: integration-issues
module: apps/web-platform/server
