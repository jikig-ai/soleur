# Learning: a fail-closed gate on a mutating call fails open on the degraded 200, and an alert that goes quiet flaps its own tracker

## Problem

PR #10830 made the bot-PR reaper (Inngest cron, every 2 h) stop calling
`PUT .../update-branch` on armed BEHIND `soleur-ai[bot]` PRs when `main` has a
`merge_queue` rule, reading the rule fail-closed once per sweep. The
implementation was green on 62 tests and a six-row mutation battery. A ten-seat
panel still found six defects, all in the gate's edges rather than its core:

1. **Degraded 200 read as "no queue".** The rules read treated a non-list body
   as unreadable but an empty list, or entries without a string `type`, fell
   through to `none`, which is the update-branch path. `main` always carries
   rules, so `[]` is a degraded response, never "no queue".
2. **A secondary read swallowed with `.catch(() => false)`** (check-runs past the
   grace) left no log and no Sentry trace; a revoked `checks:read` grant would
   have shown as "checks still running" for a day.
3. **The stuck-issue self-close flapped.** Making a queue PR "quiet while its
   checks run" (between 6 h and 24 h) removed it from the stuck set, so a sweep
   with no other stuck PR took the drained branch, closed the tracking issue,
   and reopened it under a new number once the checks finished.
4. **Replay compatibility.** A step result memoized by a pre-deploy run lacks the
   new `created_at` field; `Date.parse(undefined)` is NaN, which the age math
   treats as "past every bound", so every fresh PR would have looked stalled.
5. **Alert text claimed what the code could not know** ("rule unreadable for
   over 6h" was only "this sweep's read failed and the PR is old"), and the
   hours were literals duplicated from the bound constants.
6. **Companion docs still said the opposite** (`drain-prs` step (c) told agents
   to `update-branch` stale bot PRs unconditionally).

## Solution

- A list endpoint that always returns at least one element is validated for
  *shape* (non-empty, every entry an object with a string `type`), not just
  "is an array"; every other outcome is `unreadable`.
- Never swallow a secondary read into a state value without a mirror: log the
  status (not the message, which can carry the token) and report to Sentry.
- The self-close predicate must ask "is anything unresolved", not "is the alert
  set empty": hold the tracking issue open while a PR is held-but-aged or an
  evaluation errored.
- New fields on memoized step results need a fallback to the authoritative read
  just made in the same step.
- Derive alert wording from the bound constants and state only what the code
  measured.

## Key Insight

Every gate that withholds a mutation has a *quiet* state, and the quiet state
has two consumers nobody fixtured: the **dedup/tracking artifact** (does it
close, flap, or go stale?) and the **replayed state** (what does a pre-deploy
memo look like?). The author's mutation battery and the panel's first pass both
exercised the alerting branch; the survivors were all on the reassuring branch
(`holdIssueOpen` dropped, fallback equal to "now", `every`→`some`). Ask of each
new guard: "name the reassuring-branch mutant and say which test reds."

## Session Errors

1. **`cd ..` out of the worktree root inside a compound command** landed in
   `apps/`, `git add` aborted on the missing pathspec, no commit was made.
   Recovery: read `COMMIT_RC`, re-ran from the root. **Prevention:** already in
   `review/SKILL.md` ("never `cd ..` inside a compound command in a worktree");
   use `cd <abs-root> && ...` per command. Recurred with the rule in view, so a
   candidate for a hook if it recurs again.
2. **Local affected-test gate queued ~28 min** behind a sibling session's full
   run. Recovery: pushed and let CI be the backstop; did not edit under the
   queued run. **Prevention:** run `test-all.sh --capacity` before launching.
3. **Brief's open-state claims were stale** (#10762 / PR #10763 listed open,
   both closed). Recovery: `gh` read at session start. **Prevention:** already
   the documented rule that a resume brief's "state at hand-off" is a
   precondition to verify.
4. **Planning subagent filed a tracker (#10832)** against a brief that said to
   file nothing new unless a real defect showed. Recovery: kept it as the
   single consolidated tracker for the deferred bash residuals (net +1, `Ref`
   only). **Prevention:** put "do not file issues" in the planning subagent
   prompt when the brief says so.
5. **A "never green" assertion collided with the recipe section title** added to
   the same body (bare-token class). Recovery: scoped the assertion to the
   reason line. **Prevention:** already `cq-assert-anchor-not-bare-token`.
6. **Stop hook flagged a first-person commitment in a closing line.** Recovery:
   ended with a `Paused:` sentence naming the one wait. **Prevention:** end a
   waiting turn with the `Paused:`/`Blocked:` form.

## Tags
category: logic-errors
module: apps/web-platform/server/inngest/functions/cron-bot-pr-reaper.ts
