# Learning: a routing change is "declared" until the apply runs, and the prose around it must say so

## Problem

PR #12293 moved the `scheduled_approval_expiry` Sentry cron monitor into the `cron_monitor_failure` alert (ADR-309 flip checklist item 3, Ref #9601). The Terraform edit was four lines. The review findings were all in the prose around it: the first draft wrote an unapplied state in the tense of the settled state ("Routed 2026-11-07", "emails the org once"), and three of four panel seats converged on it. No P1 or P2 was found; two fix rounds were spent on wording.

## Solution

- State the change as **declared** and make the item's confirmation a list of read-only checks that can be re-run at flip time, each naming its endpoint: the apply workflow is green for the merge commit, the live workflow's `detectorIds` contains the id (a membership test, `index("<id>")` non-null, not a count), and no existing issue group would suppress the first-seen email.
- Write the delivery claim from the alert resource, not from memory: `sentry_alert.cron_monitor_failure` emails `issue_owners` with fallthrough `ActiveMembers` (cron issues have no owners, so the active members), triggers on `first_seen_event`, `regression_event`, `reappeared_event`, and `frequency_minutes = 1441` throttles per issue group. That is "at the start of a failure, at most once per 24 hours per monitor", not "once per episode".
- Measured, not assumed: `GET .../workflows/?query=cron-monitor-failure` honours `query` (1 of 58 workflows) and returned 24 detectors without the new id before merge; the detectors endpoint with `query=scheduled-approval-expiry` returns id `2557403`.
- A brief's file list is a hypothesis: it omitted `apps/web-platform/infra/sentry/alert-reference.json`, which the `plan_pr` reference gate requires to gain the detector id in the same change. The precedent routing PRs (git history) all touched it.
- Run the plan's negative controls, do not trust them: in an allocated sandbox, listing the id in both `monitor_ids` and the unrouted map, and removing it from `monitor_ids` without a home, each turn Guard 1 (`sentry-cron-monitor-routing-parity.test.ts`) RED (1 failed, 23 passed) against a 24/24 control.

## Key Insight

When a PR changes configuration that only takes effect on a later apply, every sentence it adds about the result is a claim about a state that does not exist yet. Name the state ("declared"), put the confirmation in a read-only checklist, and derive each delivery claim from the resource that implements it. Four reviewers will otherwise each find a different tense slip in the same paragraph.

## Session Errors

1. **`deploy-arm` from the bare repo root printed `bad_input` / `not_applicable` with no hint** — Recovery: `git merge-base --is-ancestor` against the served build sha — Prevention: run `deploy-arm find|served` from the worktree with the full 40-hex sha; the cause string should say "needs a work tree". Noted only; no tracker filed (net issue flow 0).
2. **Bash calls without `cd <worktree>` drifted the cwd to the bare root** — Recovery: re-entered the worktree; nothing was written at the root — Prevention: chain `cd <worktree-abs> && ...` in every call.
3. **Stop hook blocked the turn twice for a forward-looking closing sentence** — Recovery: ended with a `Paused:` sentence naming the external event — Prevention: already hook-enforced (`unkept-promise-hook.sh`); end waiting turns with `Paused:` and one reason.
4. **Item 3 and the dated ADR sentence drafted in settled tense** — Recovery: two fix rounds (declared tense, recipients, frequency bound, check commands) — Prevention: already covered by the review sharp edge on comments a fix PR adds; apply it at write time.
5. **A seat diffed against the stale local `main` in a bare-repo worktree** — Recovery: re-diffed against `origin/main` — Prevention: brief seats to use `origin/main...HEAD` after `git fetch origin main`.

## Tags

category: workflow-patterns
module: sentry-infra
