---
title: KB-Sync Diverged-Clone Trigger Root-Cause Fix
status: draft
owner: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-06-16-kb-sync-trigger-fix-brainstorm.md
closes: 5426
created: 2026-06-16
---

# Spec: KB-Sync Diverged-Clone Trigger Root-Cause Fix

## Problem Statement

Concierge keeps a server-side clone of each user's connected repo and auto-commits the
user's `knowledge-base/**` back to it after every session. `syncPush`
(`apps/web-platform/server/session-sync.ts:551`) runs `git add` → `git commit` onto the
**checked-out default branch**, then a **bare `git push`** (line 601). When the user's
default branch is protected, the push is rejected and the auto-commit is stranded as an
un-pushable orphan on the default branch — a "divergence treadmill" where each session
re-strands a commit and PR #5423's downstream `selfHealNonFastForward` recovery
(`workspace-sync.ts:185`) re-heals it, leaving a permanent `soleur/recovered-kb-sync-<ts>`
ref each time. #5423 recovered the symptom; this spec fixes the trigger so the divergence
never forms, and scopes the cleanup of the accumulated recovery branches.

## Goals

- **G1.** A protected default branch never strands an auto-commit: after the fix, the clone's
  default branch stays `== origin/<default>` and no orphan commit is left behind (the treadmill stops).
- **G2.** The user's KB writes are still **delivered and visible** when the default is protected —
  routed to a durable `soleur/kb-sync` side branch and surfaced via a PR into the default branch.
- **G3.** The common case (unprotected default) is **behaviourally unchanged** — direct push to default.
- **G4.** Push failures are **classified** (protected-rejection vs auth vs network); only transient
  failures auto-retry; sync remains best-effort and never blocks the session.
- **G5.** Every new failure/fallback path is reachable from Sentry without SSH (distinct queryable ops).

## Non-Goals

- **NG1.** Recovery-branch retention cleanup (item B) — **deferred** to a follow-up issue (one-time
  `git branch -D` sweep; no cron, no cap). Tracked separately.
- **NG2.** In-product KB-sync status surface UI — **deferred** to its own UI issue with its own
  brainstorm + wireframe cycle. The PR is the load-bearing visibility for this spec.
- **NG3.** No pre-flight GitHub-API branch-protection check — detection is discovery-via-rejection.
- **NG4.** No change to the `knowledge-base/**` auto-commit allowlist or the density guard.
- **NG5.** No change to `selfHealNonFastForward`'s recovery logic beyond confirming it goes cold.

## Functional Requirements

- **FR1.** `syncPush` attempts the existing direct push to the default branch first.
- **FR2.** On a push rejection classified as **protected-branch**, `syncPush` moves the pending
  auto-commit onto `soleur/kb-sync`, resets the local default branch to `origin/<default>`, and
  pushes `soleur/kb-sync` with an explicit refspec.
- **FR3.** After pushing `soleur/kb-sync`, open or **update** a PR into the default branch via the
  ADR-054 `safeCommitAndPr` path (idempotent across sessions — one PR, updated, never duplicated).
- **FR4.** `classifyGitSyncError` (`workspace-sync.ts:34`) gains a `protected_branch` classification
  distinct from `non_fast_forward`, auth, and network errors.
- **FR5.** Non-protected, transient failures (auth/network) retain best-effort retry-next-session
  behaviour; no orphan commit is left on default in any failure branch.
- **FR6.** `syncPull` reconciliation is defined for the side-branch state (see OQ1) — the next
  session must not re-strand or duplicate writes.

## Technical Requirements

- **TR1.** Reuse existing primitives: `gitWithInstallationAuth`, the `_cron-safe-commit.ts` /
  `safeCommitAndPr` (ADR-054) side-branch + PR pattern. No bespoke PR-opening.
- **TR2.** Explicit refspec for all side-branch pushes (bare Concierge clones have no remote-tracking
  refspec — learning 2026-05-14).
- **TR3.** Distinct Sentry ops for each new path (e.g. `kb-sync.push-protected-fallback`,
  `kb-sync.pr-opened`, `kb-sync.push-auth-failed`) — observability-as-quality-gate, no SSH fallback.
- **TR4.** New error-string matching for protected-branch rejection must be covered by tests
  alongside the existing `kb-route-helpers.test.ts` / `workspace-sync-*.test.ts` guards.
- **TR5.** Verify the GitHub App installation token carries `pull_requests:write`; if not, document
  the scope addition as a prerequisite.

## Open Questions

- **OQ1.** `syncPull` source-of-truth branch when writes live on `soleur/kb-sync` (FR6).
- **OQ2.** Migration of already-stranded clones (orphan commits + existing `soleur/recovered-kb-sync-*`):
  replay onto `soleur/kb-sync` or abandon? Decide explicitly to avoid silent KB data loss.
- **OQ3.** Confirm `safeCommitAndPr` upserts an existing PR rather than opening duplicates.
- **OQ4.** Consider an ADR capturing the "KB writes route to `soleur/kb-sync` on protected default"
  branch-topology decision.

## User-Brand Impact

- **Artifact:** the Concierge `syncPush` KB write-back path (`session-sync.ts:551`).
- **Vector:** a protected-default user's knowledge-base writes silently never reach their repo
  (stranded or dropped), making the product look broken while their work appears lost.
- **Threshold:** single-user incident.
