# Brainstorm: KB-Sync Diverged-Clone Trigger Root-Cause Fix

**Date:** 2026-06-16
**Issue:** #5426
**Lane:** cross-domain
**Brand-survival threshold:** single-user incident

## What We're Building

The root-cause fix for the Concierge kb-sync "divergence treadmill". PR #5423 (merged
2026-06-16, closing #5425) added *downstream* recovery: `selfHealNonFastForward`
(`apps/web-platform/server/workspace-sync.ts:185`) branches un-pushed default-branch
commits aside to `soleur/recovered-kb-sync-<ts>` then `reset --hard origin/<default>`.
That heals each occurrence but does not stop the *trigger* from re-stranding a commit
every session. This brainstorm fixes the trigger (item A) and scopes the recovery-branch
retention cleanup (item B).

**Verified trigger mechanism (read on `main`):** `syncPush`
(`apps/web-platform/server/session-sync.ts:551`) runs `git add -- <knowledge-base/**
allowlist>` → `git commit -m "Auto-commit after session"` onto the **checked-out default
branch**, then a **bare `git push`** (line 601, no refspec). If the user's default branch
is protected, the push is rejected and the auto-commit is stranded as an un-pushable
orphan — the exact divergence #5423 now recovers from.

**Chosen approach (A — Conditional fallback + PR):** Keep the current direct-push-to-default
behaviour for the working majority (unprotected default). On a **protected-branch push
rejection**, move the auto-commit onto a durable `soleur/kb-sync` side branch, reset the
default branch back to `origin/<default>` (so nothing strands → treadmill stops), and
open/update a PR into the default branch via the existing `safeCommitAndPr` path (ADR-054).
Visibility to the user is delivered by that PR (a native artifact in their own repo).

## Why This Approach

- **Doesn't regress the working majority.** Unprotected-default users (the common case)
  see no behavioural change — direct push to default is preserved.
- **Delivers the user's KB writes visibly.** Rejected by CPO: a *silent* side branch
  (Approach B) re-creates the stranding bug as invisible drift — the worst outcome for a
  non-technical founder who can't recover from invisible state but *can* click "merge" on a
  clearly-labelled PR.
- **The PR path is cheap.** ADR-054's `safeCommitAndPr` already commits to a side branch
  and opens a PR (used by `_cron-safe-commit.ts`); we reuse a tested helper rather than
  building bespoke PR-opening.
- **`selfHealNonFastForward` goes cold.** In the protected path we never commit onto the
  default branch, so the clone's default stays `== origin/<default>` and the downstream
  recovery becomes defensive-only.
- **No pre-flight detection cost.** Discovery-via-rejection: try the normal push, classify
  the protected-branch rejection from stderr, and only then fall back. The common case pays
  zero overhead. (`classifyGitSyncError`, `workspace-sync.ts:34`, is the existing seam;
  it currently classifies non-fast-forward but not protected-rejection — net-new string.)

**Rejected:** B (uniform side branch) — simplest invariant but changes the common case and
leaves writes undelivered (silent drift). C (stop-the-bleed) — smallest, but drops the
user's KB writes entirely on a protected repo.

## Key Decisions

| Decision | Choice |
|---|---|
| Trigger-fix shape (A) | Conditional: direct-to-default normally; on protected rejection → `soleur/kb-sync` side branch + PR via `safeCommitAndPr` |
| Protection detection | Discovery-via-rejection (classify protected-push stderr), not pre-flight API or static allowlist |
| No-stranding invariant | On fallback, reset default back to `origin/<default>` so no orphan commit remains (treadmill stops) |
| Failure classification | Per fail-safe-on-ambiguity learnings: distinguish protected-rejection vs auth vs network; only auto-retry transient errors |
| Observability | Distinct Sentry ops (e.g. `kb-sync.push-protected-fallback`, `kb-sync.pr-opened`) reachable without SSH |
| In-product status surface | **Deferred** to its own UI issue (own brainstorm + wireframe). PR is the load-bearing visibility for A. |
| Retention sweep (B) | **Deferred** to follow-up: one-time `git branch -D` sweep of `soleur/recovered-kb-sync-*`. No cron, no cap (CONCUR ordering: once A lands, the set stops growing). |

## Open Questions (for plan/spec)

1. **`syncPull` reconciliation** (`session-sync.ts:477`): once writes can live on `soleur/kb-sync`,
   how does the next session's pull reconcile? Does it fast-forward default from origin and
   leave `soleur/kb-sync` as the pending-PR head, or merge it back? Define the source-of-truth branch.
2. **GitHub App PR-write scope:** does the installation token already carry `pull_requests:write`?
   If not, this is a scope addition (CTO/spec gate).
3. **PR idempotency across sessions:** repeated protected-rejections must *update* the existing
   `soleur/kb-sync` → default PR, not open a new one each session. Confirm `safeCommitAndPr` upserts.
4. **Migration of already-stranded clones:** existing clones carry orphan commits + `soleur/recovered-kb-sync-*`
   refs. Does the first post-fix session replay those onto `soleur/kb-sync`, or are they abandoned?
   Risk of silent KB data loss — needs an explicit decision.
5. **Density guard interaction:** `.github/scripts/check-auto-commit-density.sh` (50% threshold)
   keys on the auto-commit headlines — confirm the side-branch commits don't trip it.

## Domain Assessments

**Assessed:** Engineering (CTO), Product (CPO). Legal (CLO) assessed inline as **not relevant**
(pure git-branch-target mechanics; auto-commit content is the user's own `knowledge-base/**`
going to their own connected repo — no third-party data flow, no contract/PII surface). Operations,
Sales, Finance, Support, Marketing: not relevant to an internal sync-trigger fix.

### Engineering (CTO)

**Summary:** Favoured a uniform durable side branch (`soleur/kb-sync`, explicit refspec) for the
cleanest invariant, but flagged that whatever the destination, the default branch must stay
`== origin` so `selfHealNonFastForward` goes cold. Key risk: migration of already-stranded clones
(silent KB data loss). Endorsed deferring B as a one-time `git branch -D` sweep. Suggested an ADR
capturing the branch-as-source-of-truth / migration decision.

### Product (CPO)

**Summary:** Rejected a *silent* side branch as re-creating the stranding bug as invisible drift —
the worst outcome for non-technical founders. Recommended the conditional protected-only fallback
with a **visible** delivery (PR), plus an in-product KB-sync status surface so a protected-default
user isn't left wondering why their KB looks stale. Flagged "Soleur opens PRs in user repos" as a
GitHub App write-scope decision for the spec.

## Research Notes (grounding)

- **Side-branch push precedent:** `_cron-safe-commit.ts` (`git push -u origin <branch>`, explicit
  refspec) and ADR-054 `safeCommitAndPr` (commit + PR pipeline). Reuse, don't rebuild.
- **No protection API check** anywhere; `push-branch.ts:54` has a static `PROTECTED_BRANCHES =
  ["main","master"]`; `classifyGitSyncError` matches non-fast-forward but not protected-rejection.
- **No branch-pruning cron:** `cron-workspace-gc.ts` sweeps directories, not refs — confirms B has
  zero existing sweeper.
- **Invariant learnings:** best-effort/never-blocking sync (2026-03-29); destructive ops gate on
  runtime state + fail-safe on ambiguity (2026-06-03 ×2); bare clones need explicit refspec (2026-05-14).
