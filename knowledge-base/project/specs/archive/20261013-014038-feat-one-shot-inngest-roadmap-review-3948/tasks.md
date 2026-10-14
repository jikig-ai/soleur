---
lane: cross-domain
plan: knowledge-base/project/plans/2026-05-25-feat-tr9-pr7-roadmap-review-inngest-migration-plan.md
issue: 4425
umbrella: 3948
pr: 4423
---

# Tasks — TR9 PR-7 roadmap-review Inngest migration

## Phase 0 — Preconditions (verify-before-code)

- [x] 0.1 `wc -l apps/web-platform/server/inngest/functions/cron-bug-fixer.ts` returns 1226
- [x] 0.2 `grep -nE 'claude|npm install.*@anthropic' apps/web-platform/Dockerfile` includes claude-code@2.1.79
- [x] 0.3 `grep -cE '^\s*-target=sentry_cron_monitor' .github/workflows/apply-sentry-infra.yml` returns 11 (baseline)
- [x] 0.4 `gh issue view 4425` resolves to filed child issue
- [x] 0.5 `ls apps/web-platform/test/server/inngest/cron-bug-fixer.test.ts` exists (reference test)
- [x] 0.6 `command -v claude` and vitest runner available

## Phase 1 — Handler skeleton (cron-roadmap-review.ts)

- [x] 1.1 Copy `cron-bug-fixer.ts` as starting template; save as `cron-roadmap-review.ts`
- [x] 1.2 Strip auto-merge gate (`runAutoMergeGate`, `detectBotFixPr`, `listOpenBotFixIssueNumbers`, `BOT_FIX_LABELS`, `PRIORITY_CASCADE`, `SKIP_LABELS`, `TITLE_SKIP_RE`, `precreateLabels`, `selectIssue`)
- [x] 1.3 Strip ops-email notification (`notifyOpsEmail`, `RESEND_API_KEY` usage)
- [x] 1.4 Strip manual-trigger override parsing
- [x] 1.5 Rename SENTRY_MONITOR_SLUG, mkdtemp prefix, feature tag, handler/function exports, function id, cron trigger, manual-trigger event
- [x] 1.6 Update `CLAUDE_CODE_FLAGS`: `--max-turns 40` + `--allowedTools Bash,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch`
- [x] 1.7 Inline `ROADMAP_REVIEW_PROMPT` template literal — extract verbatim from `.github/workflows/scheduled-roadmap-review.yml` lines 61-108 (12-space YAML dedent)

## Phase 2 — Ephemeral workspace (reuse PR-5 shape)

- [x] 2.1 `setupEphemeralWorkspace(installationToken)` — verbatim with mkdtemp prefix rename
- [x] 2.2 `teardownEphemeralWorkspace(ephemeralRoot)` — verbatim with feature-tag rename
- [x] 2.3 `buildAuthenticatedCloneUrl(token)`, `redactToken(s, token)`, `mintInstallationToken()` — verbatim

## Phase 3 — Spawn + Sentry heartbeat

- [x] 3.1 `spawnClaudeEval({ spawnCwd, installationToken, logger })` — drop `issueNumber` arg
- [x] 3.2 Prompt arg = `ROADMAP_REVIEW_PROMPT`
- [x] 3.3 `postSentryHeartbeat({ ok, logger })` — verbatim with SENTRY_MONITOR_SLUG rename
- [x] 3.4 Handler shape: mint-token → setup-workspace → claude-eval → sentry-heartbeat (4 step.run)
- [x] 3.5 Return `{ ok: boolean }`

## Phase 4 — Inngest registration + route binding

- [x] 4.1 `cronRoadmapReview` registered with concurrency + retries:1 + cron + manual-trigger
- [x] 4.2 `apps/web-platform/app/api/inngest/route.ts` — add import + register in functions array

## Phase 5 — Sentry cron monitor (TF + apply gate)

- [x] 5.1 `apps/web-platform/infra/sentry/cron-monitors.tf` — append `sentry_cron_monitor.scheduled_roadmap_review`
- [x] 5.2 `.github/workflows/apply-sentry-infra.yml` — append `-target=sentry_cron_monitor.scheduled_roadmap_review` (count 11 → 12)

## Phase 6 — Delete GHA workflow

- [x] 6.1 `git rm .github/workflows/scheduled-roadmap-review.yml` (same commit as handler)

## Phase 7 — Unit tests

- [ ] 7.1 Create `apps/web-platform/test/server/inngest/cron-roadmap-review.test.ts`
- [ ] 7.2 (a) spawn argv shape test
- [ ] 7.3 (b) Sentry URL ok/err tests (2)
- [ ] 7.4 (c) manual-trigger no-payload test
- [ ] 7.5 (d) ephemeral workspace teardown test
- [ ] 7.6 (e) prompt-canary test (Part 1/Part 2/MILESTONE RULE/BIDIRECTIONAL RULE)
- [ ] 7.7 Verify `cron-no-byok-lease-sweep.test.ts` glob picks new file (auto)

## Acceptance Criteria (pre-merge)

- [ ] AC1-AC15 per plan §5 Pre-merge section

## Acceptance Criteria (post-merge)

- [ ] AC16 — auto-apply via apply-sentry-infra.yml creates Sentry monitor
- [ ] AC17 — first natural Monday 09:00 UTC fire produces (a) Sentry heartbeat, (b) ≤1 weekly issue (verify within 24h)
