---
title: "Monitor liveness must separate trigger delivery from execution substrate — and a list read is not a create-verify oracle"
date: 2026-09-30
feature: feat-one-shot-9272-9273-9274-cron-machinery
pr: 9280
tags: [cron, sentry, monitors, github-actions, inngest, update-branch, auto-merge]
---

# Monitor liveness must separate trigger delivery from execution substrate — and a list read is not a create-verify oracle

## Problem

Three latent defects paged/discarded in one morning (post-mortem
`cron-monitors-paged-falsely-…-2026-09-30-postmortem.md`):

1. `verifyScheduledIssueCreated` verified "did the producer file its issue?"
   with ONE point-in-time `GET /issues` list read ~6 s after `gh issue create`
   returned. The label-filtered list view is eventually consistent — the row
   was created at 08:02:28Z and invisible to the read at 08:02:34Z. The false
   negative flipped `heartbeatOk=false` AND skipped artifact persistence: a
   healthy run paged red and its digest was discarded.
2. `scheduled-actions-queue-health` treated a `missed` check-in as runner
   starvation, but GitHub defers `on.schedule` workflows under org load BEFORE
   a runner is requested — measured ~4 fires/day vs `*/30` → ~47 missed-checkin
   pages/day while the probe read HEALTHY whenever it landed.
3. Armed-auto-merge `soleur-ai[bot]` PRs sat `mergeable_state: "behind"` —
   GitHub cannot auto-merge a stale head and no actor ran update-branch, so
   four consecutive daily digests never reached `main` while every monitor
   stayed green.

## Solution

- **List reads are not create-verify oracles.** Retry the list read on a
  bounded budget (3 × 12 s) and emit a non-paging `scheduled-output-late-visible`
  warn when a retry recovers — the warn is the measurement that tells you the
  lag persists, while the retry is the fix that keeps real work.
- **Delivery ≠ execution.** The "a monitor measuring the GHA queue must not be
  Inngest-dispatched" premise conflated the trigger's delivery path with the
  executor's substrate. A dispatch cron only POSTs `workflow_dispatch` — it
  needs no runner to FIRE — while the executor still lands in the measured
  queue, so the self-referential starvation signal survives the move. Keep the
  `schedule:` byte-identical as the fallback clock (the #8450 parity guard keys
  on it) and widen the check-in margin to cover the measured dispatch delivery
  (p90 ~20 min queue wait + runtime + jitter).
- **Auto-merge needs a "behind" actor.** A sweep (every 2 h) re-bases armed bot
  PRs with `PUT /pulls/{n}/update-branch`. Bound it: settle-guard (never update
  while check runs are in flight), `expected_head_sha` CAS (422 head-moved →
  quiet skip), ≤5 updates/sweep oldest-first (each merge re-`behind`s the rest
  under strict up-to-date rules — an uncapped sweep is O(N²) merge commits
  flooding the pool a sibling monitor measures), and states update-branch
  cannot fix (`dirty`/`blocked`/`unstable`) go LOUD via a dedup action-required
  issue.
- **Guard taxonomy note for update-branch:** `contents:write` on the HEAD repo
  is the grant GitHub checks for the update; the settle-guard's check-runs read
  additionally needs `checks:read` (an App token 403s without it). REST
  `user.login` is `soleur-ai[bot]` while GraphQL `author.login` is
  `app/soleur-ai` — pick the predicate for the API you're actually calling.

## Reference

- Plan: `knowledge-base/project/plans/2026-09-30-fix-cron-machinery-monitoring-integrity-plan.md`
- Issues: #9272, #9273, #9274 — soak: `scripts/followthroughs/cron-machinery-soak-9272.sh`

## Session Errors

1. **Review fix round assumed `VERIFY_MAX_ATTEMPTS`/`VERIFY_RETRY_DELAY_MS`
   constants existed** — they were literals; the clamp referenced names that
   never landed. Caught by typecheck immediately.
   - **Prevention:** grep the symbol before referencing it; when a fix round
     introduces clamp constants, define them first.

2. **`findDedupIssue` extraction changed `per_page` 10→30 and broke a pinned
   assertion** — intended unification; the test's `toBe(10)` had to move too.
   - **Prevention:** when consolidating a duplicated call shape, grep the
     *asserted* parameters in the test file — the pin, not just the call.

3. **Exporting `sleep` from `_cron-shared.ts` tripped Guard-2's chokepoint-iii**
   — an allowlisted helper (`postSentryHeartbeat`) suddenly "reached" a
   non-allowlisted *export* it had always used privately.
   - **Prevention:** `_cron-shared` exports are allowlist-audited by reach —
     check `PORTABLE_SAFE_SHARED_EXPORTS` before exporting anything new. The
     guard caught it in seconds; this is an informational note, not a defect
     in the guard.

4. **`dedup` scope bug in the redaction wrap** — hoisted the variable into a
     `try` but left a downstream reference outside it → `ReferenceError`.
   - **Prevention:** after restructuring a block around try/catch, run the
     focused test before moving on (it caught this in <6s).

5. **`gh issue create` refused twice** (missing `--milestone`, then a filing
   exit) filing the deferred dispatch-extraction issue.
   - **Prevention:** operational filings take `--label meta/machinery
     --milestone "Post-MVP / Later"` by default — the gate's refusal text
     said both on the first attempt.

6. **Tracker-directive `secrets=` field was space-separated** — the
   follow-through parser reads comma grammar, so `GH_TOKEN` would have been
   silently dropped from #9326's directive. Caught by the agent-native review
   seat, corrected on the issue and in the plan.
   - **Prevention:** the file-enrollment gate validates the directive shape;
     the *issue-comment* arm has no gate. Parse-check directives before
     posting: `secrets=A,B` not `A B`.

7. **`mktemp` inside the soak-script pagination loop lacked an owning `trap`**
   — `lint-trap-tempfile-ownership` FAILed the first post-review battery.
   - **Prevention:** any temp allocation in `scripts/` needs
     `trap 'rm -f "${_TMPFILES[@]:-}"' EXIT` up front; the lint walks the
     whole repo so new files count immediately.

8. **Two full ~85-min commit batteries** — the first invalidated by (7), the
   second clean (195/195). Environmental cost, not diff-related.
   - **Prevention:** run the lint the diff plausibly trips *before* invoking
     the battery (`bash scripts/lint-trap-tempfile-ownership.test.sh` takes
     seconds); never assume a clean tree is a clean diff.

9. **New 5 s dedup re-read collided with vitest's 5 s default timeout** in the
   handler-level "stuck" test — bumped that test to `{ timeout: 15_000 }`.
   - **Prevention:** when adding a deliberate production delay inside a
     `step.run` body, audit handler-level tests that execute the step
     synchronously — inject the delay where the seam allows, or widen the
     test's timeout explicitly with a comment saying why.

## Recurring-vs-one-off triage (continuation)

| Item | Recurring? | Disposition |
|---|---|---|
| Constants assumed before definition | one-off | caught by typecheck |
| Asserted-param pin after consolidation | recurring (class) | captured here — grep assertions too |
| Guard-2 export-reachability surprise | one-off (guard worked) | informational note |
| `dedup` scope slip | one-off | test caught it |
| Issue-filing gate refusals | one-off (first-use) | procedural |
| `secrets=` comma grammar on tracker issues | recurring (any follow-through) | captured here; parse-check before posting |
| mktemp-owning-trap in scripts/ | recurring (rule already exists) | fix-now-inline (done) — the lint enforces it |
| Slow commit battery on contended host | recurring (env) | pre-run the diff-plausible lint; document, no infra fix |
| Dedup-delay vs vitest 5s timeout | recurring (any delayed step) | captured here — audit handler tests when adding delay |
