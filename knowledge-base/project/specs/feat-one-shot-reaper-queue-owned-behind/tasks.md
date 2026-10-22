# Tasks: reaper defers armed BEHIND bot PRs to the merge queue

Plan: `knowledge-base/project/plans/2026-10-22-fix-reaper-skip-queue-owned-behind-prs-plan.md`
Ref #9454. Deferral tracked in #10832.

## Phase 1: RED (tests first)

- 1.1 Re-run the armed-BEHIND bot PR count (`gh pr list --state open --json ...`); record it in the work log (plan measured 0 on 2026-10-22).
- 1.2 In `apps/web-platform/test/server/inngest/cron-bot-pr-reaper.test.ts`: give `octokitStub` a `rules` option (default synthesized non-queue list), the `GET /repos/{owner}/{repo}/rules/branches/{branch}` route, and params recorded in `calls`.
- 1.3 Add the rules route to the four existing handler `mockImplementation`s; add `queueRule: "none"` and an old `createdAt` to existing direct `reapBotPr` calls.
- 1.4 Add `reapBotPr` tests: queue/unreadable within 6 h (no update, no check-runs), queue + cap reached, none path unchanged, 7 h terminal -> stuck-alerted, 7 h in-flight -> skipped, 25 h in-flight -> stuck-alerted, garbage `createdAt`, dirty/blocked/unstable x three verdicts.
- 1.5 Add `readMergeQueueRule` tests: merge_queue second of five, five unrelated, index 99 of 100, 100 unrelated, 403/500 plain errors, non-list body, request params (`branch: "main"`, `per_page: 100`).
- 1.6 Add handler tests: queue sweep (0 updates, 1 rules call), no-queue sweep (updates oldest-first, cap 5, 1 rules call), unreadable sweep (0 updates, one Sentry call, redacted, heartbeat posted), no bot PRs (0 rules calls), stalled-queue issue body/`prs[].reason`/`issueNumber`, dirty PR under a queue verdict, replay-simulating memoizing `step.run` (1 rules call across two invocations).
- 1.7 Run the reaper test file; confirm the new tests fail on behaviour; commit tests only.

## Phase 2: GREEN core

- 2.1 `cron-bot-pr-reaper.ts`: constants, `QueueRuleVerdict`, exported `readMergeQueueRule` (never throws; by `.type`; truncation = unreadable).
- 2.2 `reapBotPr`: new required args `queueRule`, `createdAt`, optional `nowMs`; queue/unknown branch first in the `behind` arm; new actions and `reason`; single-writer comment at the PUT.

## Phase 3: GREEN handler wiring

- 3.1 `list-open-bot-prs` returns `{ number, created_at }`.
- 3.2 `read-merge-queue-rule` step (skipped when no armed bot PR); one `reportSilentFallback` (`merge-queue-rule-unreadable`) with `redactErr`.
- 3.3 Pass the verdict and `createdAt` into `reapBotPr`; stuck-issue body intro and per-line neutral reasons; `reason` in the Sentry `prs` extra; `queueRule` in the final log.
- 3.4 Header comment; `routine-metadata.ts` description (158 chars).

## Phase 4: ADR

- 4.1 ADR-270 addendum 2026-10-22 (four bullets). No AGENTS rule line, `AGENTS.rules.md` or `.claude/rule-weakening-acks.txt` edits.

## Phase 5: Verify and ship

- 5.1 Reaper test, `routine-metadata-parity`, `function-registry-count`, `execution-placement`, `cron-safe-commit-parity`, `tsc --noEmit`, type-widening `rg`, `c4-count-parity.test.sh`, `technical-ruling-gate.sh` on `decision-challenges.md`.
- 5.2 Commit with explicit paths (never `git add -A`), trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; PR body `Ref #9454` / `Ref #10832`, Changelog, `Reviewed-Coverage:` disclosure.
- 5.3 Merge: `plugins/soleur/scripts/lib/session-state.sh with_lock merge-main 600 -- gh pr merge <N> --squash --auto`; wait for this PR's post-merge push run on main.
- 5.4 `soleur:postmerge` (deploy-arm served == CONTAINS, /health supabase connected); then the AC14 Sentry check after the first sweep.
