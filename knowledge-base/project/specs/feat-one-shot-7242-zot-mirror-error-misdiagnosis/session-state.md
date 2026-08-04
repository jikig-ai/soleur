# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-08-03-fix-zot-mirror-error-must-consume-in-job-token-verification-plan.md
- Status: complete

### Errors
Three substantive errors in the planning subagent's first draft, all caught by the review panel and corrected in the plan rather than silently fixed:

- **A2 duplicated an existing probe.** The proposed Cloudflare Access curl is already run against the same hostname by `check-cloudflare-token-drift.sh`, and it graded on the HTTP status code — the exact instrument a prior fix deleted as "the wrong instrument". A2 was cut entirely.
- **`rc=1 → stale` collapsed DEAD into UNVERIFIABLE**, so a transient fault would have printed "the token is STALE, rotate it" about a token nothing measured — this plan's own thesis violated in its primary deliverable. Now four-valued and parsed from JSON.
- **Unmeasured claim about the alarm's Sentry check-in** ("falsely reported ok") was asserted without measurement, caught by the CTO agent, and withdrawn. The corrected mechanism (implicit `success()` skip) is what the plan now states.

### Decisions
- **Cut A2 and the 2x2 matrix** — both simplification reviewers fired on the same scope, so the cut won over the fix, dissolving five ACs, three unreachable arms, two risk rows and two test scenarios.
- **Extract the diagnosis to `scripts/zot-mirror-diagnosis.sh`** — makes "both message sites tell the same story" true by construction rather than by assertion, and turns per-arm tests into direct function calls instead of driving a 270-line extracted YAML block.
- **Pull the alarm fix in scope** — all seven of the alarm's issue-filing steps lack `always()`, so they skip whenever the checker step fails, including on the FIRE verdict. One word across seven steps; the sibling detector already uses that exact form.
- **Add `scripts/lint-diagnosis-claims.sh`** — two prior iterations were each fixed by rewriting the message and neither generalized; prose is not an enforcement mechanism. Flagged that it lands in an advisory CI job, so it must be promoted or the plan must stop claiming enforcement.
- **Amend, not delete, the `model.c4` record** — reversed the CTO's delete recommendation on architecture-strategist's stronger evidence that it is a deliberate record preventing an older finding from being re-derived.
- **Dropped the unsatisfiable ACs** ("drafts re-run", "`build_sha` advances") — three reviewers converged that both require the crash-loop to stop, which this plan does not fix.

### Live diagnosis carried forward (refutes the issue's own hypotheses)
- **Real cause: `zot` is crash-looping at ~4 restarts/min since ~17:08 UTC** (0 restarts at 17:05 -> 2 at 17:10 -> 1032 by 21:25, `oom_kills=0`). First release failure was 17:11:50. A `docker login` plus three-tag `crane copy` takes tens of seconds and is near-certain to straddle a restart — producing exactly the observed `websocket: bad handshake` and `connection reset by peer`.
- **Access policy is intact** — token in the allow policy, `client_id` matches Doppler byte-for-byte, expires 2027-07-29, live probe grants.
- **The connector never re-registered because it never dropped** — its 4 connections opened 2026-07-31/08-01, and there is no `cloudflared` on the registry host at all.
- **The registry host never rebooted** (18.2 days uptime); the self-heal advisory misread a *cumulative* `reboot_count`.

### Components Invoked
`soleur:plan`, `soleur:plan-review`, `soleur:deepen-plan`; agents `dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplicity-reviewer`, `architecture-strategist`, `spec-flow-analyzer`, `cto`, `learnings-researcher`, `Explore` x3; live diagnosis via `gh run view/list`, Cloudflare API (Access apps/policies/service tokens, tunnel connectors), `cloudflared access tcp` bridge reproduction, `scripts/betterstack-query.sh`, and Doppler `prd`/`prd_terraform`.

## Work Phase

Status: implementation complete; full-suite exit gate pending (queued behind a sibling
worktree's `test-all.sh` on the advisory lock).

### Deviations from the plan, and why

1. **CONCUR overruled the plan on the inngest sibling defect.** The plan filed it
   (`tasks.md` 1.2b). The cost-of-filing gate forced it INLINE (6 lines, 1 file), and the
   proposed deferral target did not exist — Deliverable E's lint checks message TEXT, not
   `if:` conditions, so deferring would have parked it forever. Net issue flow: closing
   #7242, filing #7247 + #7248 = **net +1** (it would have been +2).

2. **The inngest fix is NOT the plan's "one word x N steps".** Two of the eight cited lines
   are not issue-filing steps; one dispatches a production server restart. And `:574` gates
   on `failure_mode == ''` — satisfied by a CRASHED producer — so a bare `always()` there
   would auto-close P1 `[ci/inngest-down]` on a gh API blip. It got a producer-liveness
   guard; the restart-dispatch chain was left untouched as a separate decision.

3. **B4 re-aimed.** The plan called the reboot claim FALSE. It is not: `reboot_count` is
   carried across the reboot, so on the resulting boot it genuinely means "this boot exists
   because the guard rebooted me". The defect is that it carries no TIME and is re-emitted
   verbatim every poll, so an 18-day-old convergence reads as news. Fixed by DATING the
   claim, not suppressing it — which is why N5 still asserts "H2 confirmed" and needed no
   fixture edit. The plan's "<2 in-window samples -> no claim" was an over-application (a
   point-in-time boot fact needs one row with `uptime_s`, not a trend); replaced with an
   explicit undatable-boot arm.

4. **0.6c resolved better than either offered option.** The plan offered (a) promote
   `lint-bot-statuses` to required, or (b) accept advisory. (a) trips the auto-fabrication
   guard on the CODEOWNERS-gated `required-checks.txt` and changes merge behaviour
   repo-wide. Instead the lint's suite is registered in `test-all.sh`, whose `scripts` shard
   feeds the aggregate `test` job — which IS in the CI Required ruleset. Blocking, no
   ruleset change.

5. **AC13 contradicts Deliverable D.** AC13 says `model.c4`'s heuristic "is deleted";
   Deliverable D and the Sharp Edges say AMEND, because deleting re-opens the #6416
   re-derivation the record exists to prevent. Followed AMEND.

6. **Two gates added that the plan did not have.** T18 (structural wiring assertion) exists
   because T17 is BLIND to the `env:` mapping — measured: hardcoding `TOKEN_VERDICT:
   unmeasured` left T17 fully green. `alarm-issue-filing-guard.test.sh` covers both alarm
   workflows because a step condition is evaluated by GitHub, so the YAML is the only
   testable artifact.

### Self-inflicted errors caught in-session

- Introduced a re-entry of the **#6416 silent-mirror defect**: an unguarded `source` of the
  helper aborts under `set -e`, so `degraded()` would never run and a bridge failure would
  report NOTHING. Caught by T4. Every load site is now guarded with a short-form fallback.
- First T9 rewrite grepped for the helper's own FILENAME, which the could-not-load fallback
  also prints — so it passed whether or not the helper loaded. Re-anchored on text only the
  real helper emits.
- First `lint-diagnosis-claims` regex flagged two false positives (a gate describing what it
  prevents; prose explaining this very anti-pattern). Baselining them would have made the
  ratchet unable to reach zero. Tightened instead; census is 0.
- ADR-166's `Extends:` links were four fabricated filenames. Verified against disk and
  corrected; unverified clause numbers ("cl.4", "§2") dropped rather than restated.
- Wrote the follow-through directive into an issue COMMENT first; the sweeper reads
  `.body` (`sweep-followthroughs.sh:477`). Moved, dry-run-verified, comment deleted.
- A mutation battery timed out mid-run and left `RECENT_BOOT_S=99999999` in the tree.
  Restored and re-verified. (Batches now sized under the timeout.)

### Mutation coverage

24 mutations run, 24 killed: 7 arm/ladder, 5 verdict-wiring, 7 alarm-condition (incl. an
anti-vacuity scanner-break control), 5 B4 recency/dating.
