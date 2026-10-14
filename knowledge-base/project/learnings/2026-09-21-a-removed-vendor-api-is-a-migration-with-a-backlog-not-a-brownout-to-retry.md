---
module: Sentry infra
date: 2026-09-21
problem_type: integration_issue
component: tooling
symptoms:
  - "`apply-sentry-infra.yml` `plan_pr` and post-merge `apply` both red on main: two `sentry_issue_alert` resources refreshed through `projects/{org}/{proj}/rules/{id}/`, which answered `410 {\"detail\":\"This API no longer exists.\"}` on every attempt"
  - "The workflow's brownout retry ladder spent three attempts per run on a 410 that no retry could clear, and its message framed a removal as a brownout"
  - "Blocks merged during the wedge (`art17_erasure_incomplete`, `scheduled_devin_docs_drift`) appeared in no single PR or merge diff, so a create-gate scoped to 'this diff' could not see the creates the first green apply would perform"
root_cause: wrong_api
resolution_type: migration
severity: high
synced_to: []
tags: [sentry, terraform, removed-block, import-block, ignore-changes, provider-pin, 410, brownout, wedged-root, backlog, last-applied-sha, tripwire]
---

# A removed vendor API is a migration with a backlog, not a brownout to retry

## Problem

Sentry removed the legacy alert-rule endpoint that `sentry_issue_alert` refreshes through. Every
full-root `terraform plan` of `apps/web-platform/infra/sentry/` failed with a 410, so `plan_pr`
(a required check) blocked every Sentry-infra PR and the post-merge apply never ran (#8451, #8282).
The pinned provider (v0.15.7) has no cross-type `MoveState`, so a `moved {}` block to
`sentry_alert` is impossible, and it cannot express these two rules' trigger natively.

## Solution

1. **Adopt, don't recreate.** `removed { lifecycle { destroy = false } }` forgets the old
   addresses without refreshing them (a forgotten address is never read, so the 410 endpoint is
   never hit), and `import {}` adopts the same live ids (`566671`, `669246`) at `sentry_alert`
   addresses. Ids and history survive.
2. **Freeze what the provider cannot express.** The trigger rides in `legacy_trigger_conditions`
   and each block carries `lifecycle { ignore_changes = all }`, so Update is structurally
   impossible. The remaining write paths (Create after a UI delete, rename or `-replace`; Update
   after someone narrows `ignore_changes`) are refused before apply by the extended
   `sentry-issue-alert-create-tripwire.sh`, which now rejects any `sentry_alert` write carrying a
   legacy trigger in `before`, `after` or `after_unknown`.
3. **Report a 410 as measured, once.** The retry ladder is gone. A 410 fails on the first attempt
   with a message naming the addresses and stating only what was measured: a 410 that persists
   across runs is a removal; one that clears on re-run was a brownout.
4. **Anchor gate windows on the last APPLIED commit, not the PR diff.** A wedged root accumulates
   merged-but-unapplied blocks. `scripts/sentry-last-applied-sha.sh` keys on the `Terraform apply (cron + uptime monitors)`
   *step* of the last successful run (not the job or run, so a post-apply probe failure does not
   stall and widen the window), and the adoption assert checks inertness at the adopted rows plus
   no delete/replace anywhere, printing the backlog creates/updates as delegated.
5. **Let the filer close its own issue.** #8282 is the apply-failure filer's issue; the workflow's
   success step closes it with the green run URL. The PR carries `Ref #8282`, not `Closes`, so
   resolution is recorded only after evidence exists.

## Key Insight

When a vendor answers 410 "no longer exists", the retry ladder built for brownouts becomes a
liability: it delays the signal and names the wrong cause. Treat it as a migration, and expect
that the outage has already **wedged** the apply root. Every gate that reasons about "what this
change applies" must then be anchored on the last commit that actually applied, because the first
green apply will also carry everything merged during the wedge.

## Session Errors

1. **The reviewed head was `DIRTY`/`CONFLICTING` on GitHub although `git merge-tree --write-tree HEAD origin/main` was clean, so no `pull_request` workflow (including `plan_pr`) had run on `94fcc7b19`. Only CLA checks were queued.** The resume handoff said "confirm plan_pr green on the head", which could not be observed.
   Recovery: merged `origin/main` (1 commit behind) as `ceeb2d8cd` and pushed; GitHub recomputed to `MERGEABLE` and CI started.
   **Prevention:** already enforced. `soleur:ship` Phase 7 auto-syncs a `DIRTY` PR when `merge-tree` is clean. A resume should read `mergeStateStatus` before waiting on any check, because a conflicting PR runs no `pull_request` workflows at all.
2. **The resume handoff gave only a repo-relative worktree path, so four `find` calls went into locating the checkout.**
   Recovery: located it at `~/git-repositories/jikig-ai/soleur`.
   **Prevention:** resume prompts should carry the absolute worktree path. This was a one-off with no gate owner.
3. **The Step 0a.5 collision probe surfaced merged PR #8442 as linked to #8451.**
   Recovery: `gh pr view 8442 --json closingIssuesReferences` showed it closes #8094, so it is a citation.
   **Prevention:** already covered by the cited-predecessor discriminator in `one-shot/SKILL.md` Step 0a.5.

## Related

- `knowledge-base/project/plans/archive/20260921-114348-2026-09-21-fix-sentry-alert-410-removed-api-migration-plan.md`
- `knowledge-base/project/specs/archive/20260921-114348-feat-one-shot-8451-sentry-alert-410-migration/pre-merge-live-baseline.md`
- `ADR-031-sentry-as-iac.md` (#8451 amendment)
- #8451, #8282, #7985
