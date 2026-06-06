---
title: Tasks — fix content-generator cron silence hole (#4960)
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-05-fix-content-generator-cron-silence-hole-plan.md
issue: 4960
created: 2026-06-05
---

# Tasks — content-generator cron silence hole (#4960)

Scope: `apps/web-platform/server/inngest/functions/cron-content-generator.ts` ONLY.
Do NOT touch the bwrap/sysctl path (PR #4932), roadmap-review, or community-monitor.
Do NOT bump `--max-turns` — Sentry evidence (2026-06-05) shows an Anthropic API 500
mid-eval, not a turn-kill.

## Phase 0 — Preconditions (verify at /work)
- [ ] 0.1 Confirm `cron-content-generator.ts` still mints `runStartedAt` and calls
      `resolveOutputAwareOk` via the `verify-output` step (handler post-run check exists).
- [ ] 0.2 Confirm the probe octokit (`createProbeOctokit`, `probe-octokit.ts:116`) has
      issue-write — sibling handlers (`cron-skill-freshness.ts:267`, `cron-oauth-probe.ts:510`)
      already `POST /issues` through it. If confirmed, use it; else use the already-minted
      `installationToken`. Never a PAT (`hr-github-app-auth-not-pat`).
- [ ] 0.3 Re-run open code-review overlap (two-stage `gh issue list --json` + standalone
      `jq --arg`) for the 3 touched files; expect None.

## Phase 1 — RED (failing tests)
- [ ] 1.1 Add source-shape anchors to
      `apps/web-platform/test/server/inngest/cron-content-generator.test.ts`:
      `ensure-audit-issue` step, `[Scheduled] Content Generator -` title literal,
      `scheduled-content-generator` label literal, `try/catch` → `reportSilentFallback` guard,
      gate on the output-aware boolean.
- [ ] 1.2 Add a regression anchor asserting `--max-turns` is STILL `"50"` (this PR does NOT bump).
- [ ] 1.3 (Preferred) Extract `ensureContentGeneratorAuditIssue({ octokit?, runStartedAt,
      spawnResult })` into the handler module (NOT `_cron-shared.ts` — scope is content-gen only)
      with an injectable `octokit?` seam (mirror `resolveOutputAwareOk`). Add a behavioral unit
      test: stubbed `verify-output=false` + stub octokit → exactly one `POST /issues`;
      `verify-output=true` → zero creates; octokit rejects → `reportSilentFallback` called, no throw.

## Phase 2 — GREEN (handler-level fallback guard)
- [ ] 2.1 Add `ensure-audit-issue` step AFTER `verify-output`, gated on `heartbeatOk === false`.
- [ ] 2.2 Title: `` `[Scheduled] Content Generator - ${runStartedAt.slice(0,10)}` `` (replay-stable UTC date).
- [ ] 2.3 Body: `fn`, `runStartedAt`, `exitCode`, `signal`, `abortedByTimeout`, `durationMs`,
      bounded redacted `stdoutTail`/`stderrTail` tail + a one-line H2-runbook pointer (self-diagnosing).
- [ ] 2.4 Label `["scheduled-content-generator"]`. OMIT `do-not-autoclose` (let the watchdog
      auto-close #4960 on recovery) unless a reason surfaces — note the decision in the PR.
- [ ] 2.5 Wrap in `try/catch` → `reportSilentFallback({ feature:"cron-content-generator",
      op:"ensure-audit-issue-failed", ... })`; never throw (teardown `finally` must still run).
- [ ] 2.6 Idempotency: search open `scheduled-content-generator` issues for today's title prefix
      BEFORE creating (mirror `searchExistingFreshnessIssue`); dedup logic lives INSIDE the step
      (a thrown step is re-run on `retries:1`, so memoization alone is insufficient).
- [ ] 2.7 Leave `CLAUDE_CODE_FLAGS` `--max-turns 50` and `MAX_TURN_DURATION_MS = 55*60*1000` unchanged.

## Phase 3 — Runbook + cohort regression
- [ ] 3.1 Update `knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md` H2
      Restore: note the new handler-level fallback (survives mid-eval crash / API-500 / max-turns
      kill); cross-reference the `ensure-audit-issue` step.
- [ ] 3.2 Confirm `cron-producer-output-wiring.test.ts` still green (content-generator remains a
      wired always-create producer — this PR adds a fallback, not a rewiring).

## Phase 4 — Verify + ship
- [ ] 4.1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-content-generator.test.ts test/server/inngest/cron-producer-output-wiring.test.ts test/server/inngest/cron-shared.test.ts` (vitest; bun test blocked by bunfig.toml).
- [ ] 4.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] 4.3 PR body uses **`Closes #4960`** (body, not title).
- [ ] 4.4 File the deferred cohort-generalization follow-up issue (7 sibling always-create
      producers share the hole) referencing this PR as proof-of-pattern; milestone from
      `knowledge-base/product/roadmap.md`.
- [ ] 4.5 (Post-merge, automatable) After deploy, fire `cron/content-generator.manual-trigger`
      via `/soleur:trigger-cron`; confirm a `scheduled-content-generator` issue (success OR FAILED
      self-report) appears, and that the watchdog auto-closes #4960 on its next fire.
