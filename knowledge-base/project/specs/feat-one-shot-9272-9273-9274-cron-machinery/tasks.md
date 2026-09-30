# Tasks: fix: cron machinery — verify-list race, queue-health scheduler deferral, stale bot-PR merge stall

Plan: `knowledge-base/project/plans/2026-09-30-fix-cron-machinery-monitoring-integrity-plan.md`

## Phase 0: Pre-conditions

- [ ] 0.1 Verify the update-branch endpoint permission class against the GitHub REST docs ("Update a pull request branch") — confirm whether `contents:write` or `pull_requests:write` suffices before pinning the reaper's token grant
- [ ] 0.2 Confirm `Octokit` accepts an arbitrary `"METHOD /repos/{owner}/{repo}/…"` route string (grep `client.request(` in `apps/web-platform/server/` for the route-string convention already in use)
- [ ] 0.3 Re-run `git log --oneline origin/main..HEAD` diff-scope check against `knowledge-base/project/plans/…-plan.md` `## Files to Edit`/`## Files to Create` before implementation begins (merge-base may have moved)

## Phase 1: #9272 — bounded retry in verifyScheduledIssueCreated

- [ ] 1.1 RED: add regression tests in `apps/web-platform/test/server/inngest/cron-shared.test.ts` — (a) empty first read + populated second read → `true` + `scheduled-output-late-visible` warn fired once; (b) all-empty reads → `false` + exactly `maxAttempts` requests + no warn; (c) populated first read → `true` + exactly 1 request + no warn; (d) throwing request → propagates with no further reads. Inject `retryDelayMs: 0` in every case
- [ ] 1.2 Confirm the new tests FAIL against the current implementation
- [ ] 1.3 Implement in `apps/web-platform/server/inngest/functions/_cron-shared.ts`: extend `verifyScheduledIssueCreated` args with `maxAttempts?: number` (default 3), `retryDelayMs?: number` (default `12_000`), `feature?: string`; wrap the list read in the bounded loop using the file's existing `sleep` helper; emit `warnSilentFallback` with `op: "scheduled-output-late-visible"` only on attempt >1 success
- [ ] 1.4 Pass `feature: cronName` from `resolveOutputAwareOk` (~line 1376)
- [ ] 1.5 GREEN: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-shared.test.ts`

## Phase 2: #9273 — dispatch-primary queue-health

- [ ] 2.1 Create `apps/web-platform/server/inngest/functions/cron-actions-queue-health-dispatch.ts` mirroring `cron-supabase-watchdog-dispatch.ts`: `{ cron: "*/30 * * * *" }` + manual-trigger event, `actions: "write"` scoped mint, dispatch POST with `ref: "main"`, `fn`+`"cron-dispatch"` concurrency lanes, `retries: 1`, redacted `reportSilentFallback`; header comment records the ADR-248 eligibility argument (dispatch path is runner-queue-independent; executor still lands in the measured runner pool)
- [ ] 2.2 Register: `app/api/inngest/route.ts` (import + functions array), `server/inngest/cron-manifest.ts`, `server/inngest/execution-placement.ts` (`portable`), `server/inngest/routine-metadata.ts`
- [ ] 2.3 RED: create `apps/web-platform/test/server/inngest/cron-actions-queue-health-dispatch.test.ts` mirroring `cron-supabase-watchdog-dispatch.test.ts` (dispatch POST shape, narrowed-token assertion via mintSpy, failure → `reportSilentFallback` + `{ok:false}`); confirm it fails
- [ ] 2.4 Rewrite the design comment in `.github/workflows/scheduled-actions-queue-health.yml` (lines ~1-8): dispatch-primary + `schedule:`-as-fallback; the `on:` block stays byte-identical
- [ ] 2.5 In `apps/web-platform/infra/sentry/cron-monitors.tf`: `checkin_margin_minutes 30 → 60` for `scheduled_actions_queue_health` + rewrite the margin/design comment (deferral-as-confounder; what still pages)
- [ ] 2.6 GREEN: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-actions-queue-health-dispatch.test.ts`

## Phase 3: #9274 — cron-bot-pr-reaper

- [ ] 3.1 Create `apps/web-platform/server/inngest/functions/cron-bot-pr-reaper.ts`: `{ cron: "17 */2 * * *" }` + manual-trigger event; mint `{ contents: write, pull_requests: write, issues: write }` repo-scoped; steps `mint-installation-token` → `list-open-bot-prs` (`user.login === "soleur-ai[bot]"` AND `auto_merge != null`, exclude drafts) → per-PR `read-state` (fresh `GET /pulls/{n}`; `"unknown"` gets one re-read ~15 s then skip) → act per `mergeable_state` (behind+terminal-checks → update-branch with settle-guard via check-runs; dirty/blocked/unstable → alert arm; clean/draft/has_hooks → skip)
- [ ] 3.2 Terminal step posts `postSentryHeartbeat` for `SENTRY_MONITOR_SLUG = "scheduled-bot-pr-reaper"` (use `crypto.randomUUID()` for checkInId per file convention)
- [ ] 3.3 Alert vehicle: dedup-by-title issue `[ci/bot-pr-reaper] …` with labels `action-required` + `domain/engineering` (both verified to exist); comment-update while non-empty, self-close when the set drains; only bot-generated fields (PR number, head ref, state) in body/extra
- [ ] 3.4 Register in the same four files as Phase 2
- [ ] 3.5 Add `sentry_cron_monitor.scheduled_bot_pr_reaper` to `cron-monitors.tf` (crontab `17 */2 * * *`, margin 30, max_runtime 10, failure_issue_threshold 1, UTC)
- [ ] 3.6 RED→GREEN: `apps/web-platform/test/server/inngest/cron-bot-pr-reaper.test.ts` — fixture set covering every mergeable_state arm; update-branch called only for behind+terminal-checks; alert for dirty/blocked/unstable; skip clean/draft/unknown-reread; non-bot/unarmed ignored; issue dedup create/update/close

## Phase 4: Records & registration counts

- [ ] 4.1 Copy the untracked post-mortem from the main checkout (`/data/git-repositories/jikig-ai/soleur/knowledge-base/engineering/operations/post-mortems/cron-monitors-paged-falsely-community-monitor-verify-race-queue-health-scheduler-deferral-2026-09-30-postmortem.md`) into the same path in the worktree; update `status: resolved`, `incident_pr`, `recovery_at`/incident_window end, Resolution + 5-Whys + Lessons, and the three action-item rows → discharged by this PR; keep the Actor-keyed timeline table byte-shape intact
- [ ] 4.2 Update `knowledge-base/engineering/architecture/diagrams/model.c4` `github -> sentry` edge: rewrite the `-actions-queue-health` clause (dispatch-primary, mirroring the `scheduled-supabase-watchdog` sub-clause) + counts `Of 60 cron monitors` → `Of 61`, `44 from webapp` → `45`
- [ ] 4.3 Update `function-registry-count.test.ts` count 70 → 72 + comment ledger entries
- [ ] 4.4 Create `scripts/followthroughs/cron-machinery-soak-9272.sh` (mirror `reconcile-ff-only-sentry-4977.sh` shape): `start=` pinned strictly after deploy; exits 0 when (a) zero `scheduled-output-missing` for community-monitor while ≥1 digest/day landed, (b) no queue-health missed check-ins, (c) no `soleur-ai[bot]` PR `behind` >24 h; file the tracker issue with the `<!-- soleur:followthrough … -->` directive + `follow-through` label

## Phase 5: Full battery

- [ ] 5.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean
- [ ] 5.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/` green
- [ ] 5.3 `bash plugins/soleur/test/c4-count-parity.test.sh` green
- [ ] 5.4 `terraform validate` + `terraform fmt -check` on the sentry root clean
- [ ] 5.5 `bash scripts/test-all.sh` (or the shards the diff touches per the work Phase 2 exit gate)
- [ ] 5.6 `npx markdownlint-cli2` on the plan + post-mortem clean
- [ ] 5.7 Learning capture at `knowledge-base/project/learnings/<topic>.md` (directory + topic only; pick the filename at write-time) covering the trigger-substrate/delivery-vs-execution conflation lesson
