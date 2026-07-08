---
title: "Lock-free TS git-config writer (#6191) + deepened-plan-vs-tasks.md scope drift"
date: 2026-07-08
category: workflow-patterns
module: apps/web-platform/server/git-config-atomic.ts
issues: [6191, 5934]
pr: 6211
tags: [git-config, atomic-write, observability, silent-fallback, one-shot, tasks-drift, review]
---

# Learning: lock-free TS git-config writer + deepened-plan-vs-tasks.md drift

## Problem

`/soleur:go #5934 / #6191` → one-shot bundled two ADR-099-named git-surface-hardening
items: (#6191) route `workspace.ts`'s raw host-side `git config user.name/email` owner-seed
writes through a lock-free writer immune to a stale/masked `.git/config.lock`; (#5934, docs
only) consolidate the already-answered single-path mask-scope finding. Clean execution, but
three friction points recurred that are worth compounding.

## Solution

- **`atomicGitConfig(cwd, args)`** (`apps/web-platform/server/git-config-atomic.ts`):
  resolve `.git/config` → `cp -p` (copyFileSync) into a same-dir temp → `git config --file
  <tmp> <args>` (git's own INI writer — never hand-serialize INI) → `renameSync(tmp, config)`.
  Lock-free BY CONSTRUCTION: rename(2) is atomic and never touches `config.lock`. **cp-first
  is load-bearing** — `git config --file` starts from an EMPTY file, so without seeding the
  temp with the current config every other key is dropped (the strongest mutation-catching
  test pins exactly this).
- **Best-effort, never throws** (preserves the non-stranding provision path). Because it never
  throws, the caller can't tell "seeded" from "aborted unseeded" → BOTH failure branches must
  emit a CAPTURED `reportSilentFallback` event, not a `log.warn` (which is only a droppable
  Sentry breadcrumb). Review (silent-failure-hunter) caught that the generic write-failure
  catch was `log.warn`-only while the masked-target branch got a captured event — an asymmetric
  silent fallback for the SAME unseeded-identity outcome (`cq-silent-fallback-must-mirror-to-sentry`).
  Fix: route the generic catch through `reportSilentFallback(err, {feature, op:"write"})`. A
  captured event ≠ a page — no alert rule is added, so transient disk/perms blips stay
  queryable, not paging.
- **Concurrency safety is synchronous + single-worker-per-container, NOT "lock-free ⇒ safe
  under >1 caller"** — rename(2) prevents a torn write but does NOT serialize a read-modify-write.
  State that caveat in the module doc (mirror `workspace-permission-lock.ts:1-10`).
- **Durability window**: the forgone fsync window is POST-rename / pre-flush (git owns the temp
  fd, so we can't fdatasync). The PRE-rename window is safe regardless. Name the correct window
  in any precedent-diff — "a crash before rename is safe" argues the wrong (trivially-safe) window.

## Key Insight

Two reusable workflow lessons beyond the code:

1. **The deepened plan is authoritative over `tasks.md` when they disagree.** `/soleur:plan`'s
   deepen pass dropped a task (route `seedWorktreeConfig` through the helper — manufactured
   scope per simplicity + architecture review) via the plan's Enhancement Summary, but the
   scope reduction never propagated to `tasks.md` task 2.2. `/work` must treat the plan body as
   the source of truth and flag the drift, not blindly execute a stale task. (Same class as
   "plan-quoted numbers are preconditions to verify.")

2. **Scrub closed contextual `#N` citations to date-anchored prose BEFORE invoking one-shot.**
   Passing lineage cites (`#5912 → #6184`, both CLOSED) in `#N` form made the one-shot
   collision gate treat them as candidate work targets; discriminating them required extra
   `gh pr view --json closingIssuesReferences` probes. The `/soleur:go` sharp edge already
   prescribes date-anchored phrasing for closed citations — apply it at arg-construction time.

## Session Errors

1. **Write-failure test used an invalid-but-git-ACCEPTED key.** `git config --file <tmp>
   invalid..key x` returns rc=0 (git tolerates empty subsections), so the test asserting the
   write-catch fired `reportSilentFallback` saw 0 calls and failed. **Recovery:** switched to a
   section-less key `nosectionkey`, which git rejects ("key does not contain a section", rc=2).
   **Prevention:** to force `git config --file` to fail in a test, use a key with NO section
   (bare `foo`), not a double-dot key — git accepts `a..b`. One-off (self-corrected).
2. **One-shot args carried closed lineage citations `#5912`/`#6184` in `#N` form.** Tripped the
   collision gate's closed-issue discrimination. **Recovery:** `gh pr view <PR> --json
   closingIssuesReferences` confirmed each PR closes the cited predecessor, not the work target
   → treated as citations, proceeded. **Prevention:** already covered by the `/soleur:go` sharp
   edge + `2026-05-25-one-shot-closed-issue-gate-fires-on-contextual-refs.md` — scrub closed
   `#N` to date-anchored prose before invoking one-shot. Recurring; no new rule needed.
3. **`tasks.md` task 2.2 contradicted the deepened plan.** **Recovery:** followed the plan
   (authoritative), marked 2.2 `[~] SKIPPED per deepened plan` with rationale. **Prevention:**
   see Key Insight #1 — deepen scope reductions should propagate to tasks.md; /work flags drift.
