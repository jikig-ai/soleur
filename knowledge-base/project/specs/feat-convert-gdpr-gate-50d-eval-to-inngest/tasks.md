---
title: "Tasks: convert gdpr-gate 50d eval to Inngest one-shot"
date: 2026-05-25
plan: knowledge-base/project/plans/2026-05-25-feat-convert-gdpr-gate-50d-eval-to-inngest-plan.md
lane: cross-domain
---

# Tasks: Convert gdpr-gate 50d eval to Inngest one-shot (TR9 PR-G)

## Phase 0: Inngest `ts` Scheduling Verification (GATE)

- [ ] 0.1 Verify Inngest tier supports `ts` delays ≥60 days
- [ ] 0.2 Verify future `ts` = "schedule delivery at this time" (not "event occurred at this time")
- [ ] 0.3 Document resolution in PR #4461 body
- [ ] 0.4 If either fails: implement hybrid GHA T-7d fallback, then delete this fallback prose from plan

## Phase 1: Implement + Register + Delete

- [ ] 1.1 Create `apps/web-platform/server/inngest/functions/oneshot-gdpr-gate-50d-eval.ts`
  - [ ] 1.1.1 step.run `mint-installation-token` (copy from cron-strategy-review.ts:127-136)
  - [ ] 1.1.2 step.run `eval-and-post`
    - [ ] 1.1.2.1 D3 date guard: `today === event.data.expected_date` (parameterized, not hardcoded)
    - [ ] 1.1.2.2 Author check: `user.login === "deruelle"` via Octokit comment fetch
    - [ ] 1.1.2.3 Telemetry count: Octokit Contents API for `.claude/hooks/incidents.log`
    - [ ] 1.1.2.4 Escaped PR count: Octokit `GET /pulls` with pagination (10-page cap) + client-side `merged_at` date filter + label filter
    - [ ] 1.1.2.5 Outcome matrix: 0 / 1-2 / ≥3 escapes → recommendation
    - [ ] 1.1.2.6 Post structured comment on #3516 via Octokit
  - [ ] 1.1.3 step.run `sentry-heartbeat` (single POST, same as cron-strategy-review.ts:559-605)
  - [ ] 1.1.4 Conditional 90-day re-arm via `inngest.send({ ts: 1785402000000, expected_date: "2026-08-10" })`
  - [ ] 1.1.5 `reportSilentFallback` on every error path
- [ ] 1.2 Registration: createFunction with `{ event: "oneshot/gdpr-gate-50d-eval.fire" }` only (no cron)
- [ ] 1.3 Add import + array entry to `apps/web-platform/app/api/inngest/route.ts`
- [ ] 1.4 `git rm .github/workflows/scheduled-gdpr-gate-preflight-eval-50d.yml` (same commit)

## Phase 2: Testing

- [ ] 2.1 Widen `cron-no-byok-lease-sweep.test.ts` glob to `{cron,oneshot}-*.ts`; update test description
- [ ] 2.2 D3 date guard unit test: mock today ≠ expected_date → assert `{ ok: false, reason: "date-guard" }`
- [ ] 2.3 Author check unit test: mock `user.login = "attacker"` → assert abort
- [ ] 2.4 `tsc --noEmit` passes

## Post-merge

- [ ] PM.1 Run arming command: `pnpm exec inngest send oneshot/gdpr-gate-50d-eval.fire --ts 1782723600000 --id gdpr-gate-50d-eval-2026-06-29-v1 --data '{"issue":3516,"comment_id":4415647777,"expected_date":"2026-06-29","expectedAuthor":"deruelle"}'`
- [ ] PM.2 Paste returned `event_id` into PR #4461 description
- [ ] PM.3 After 2026-06-29: verify structured comment on #3516
