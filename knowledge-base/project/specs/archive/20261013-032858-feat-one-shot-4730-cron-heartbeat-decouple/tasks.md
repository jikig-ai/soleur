---
title: "Tasks — decouple cron claude-eval heartbeats from claude exit code"
date: 2026-06-01
lane: single-domain
plan: knowledge-base/project/plans/2026-06-01-fix-cron-claude-eval-heartbeat-decouple-plan.md
related_issues:
  - 4730
---

# Tasks — cron claude-eval heartbeat decouple (8 siblings)

Derived from `2026-06-01-fix-cron-claude-eval-heartbeat-decouple-plan.md`.
Classification (precedent-diff complete): **4 Pattern-B** (output-aware) +
**4 Pattern-A** (best-effort). Re-grep `ok: spawnResult.ok` before editing;
do NOT trust the issue's line numbers.

## Phase 0 — Preconditions

- [ ] 0.1 Re-run `git grep -nE "ok: spawnResult\.ok" apps/web-platform/server/inngest/functions/cron-*.ts` — confirm 9 sites (8 in-scope + bug-fixer already done).
- [ ] 0.2 Re-read each in-scope cron's prompt to confirm the 4B/4A split has no counter-evidence (a producer with an also-conditional path, or vice-versa).
- [ ] 0.3 Read each cron's existing infra-fault `reportSilentFallback` early-returns; they must remain strict (`ok:false`/`status=error`) and untouched.
- [ ] 0.4 Read the bug-fixer Pattern-A precedent (`cron-bug-fixer.ts:744-788, 839-846`) and the Pattern-B precedent (`cron-roadmap-review.ts:287-297`, `_cron-shared.ts:186`).

## Phase 1 — RED (failing tests, per cron)

Mirror `cron-bug-fixer.test.ts:809-856`. Test FILE PATHS already live under
`apps/web-platform/test/server/inngest/` (vitest `test/**/*.test.ts` include).

Pattern-A crons (clean run with non-zero exit stays green + breadcrumb):
- [ ] 1.1 `cron-agent-native-audit.test.ts` — non-zero exit → `status=ok` + `warnSilentFallback` op; no infra breadcrumb.
- [ ] 1.2 `cron-legal-audit.test.ts` — same.
- [ ] 1.3 `cron-campaign-calendar.test.ts` — same.
- [ ] 1.4 `cron-ux-audit.test.ts` — same.

Pattern-B crons (spawn-ok but no `scheduled-<slug>` issue → `status=error`):
- [ ] 1.5 `cron-growth-audit.test.ts` — spawn-ok + no issue in window → `status=error` (`scheduled-output-missing`); spawn-ok + issue present → `status=ok`.
- [ ] 1.6 `cron-growth-execution.test.ts` — same.
- [ ] 1.7 `cron-seo-aeo-audit.test.ts` — same.
- [ ] 1.8 `cron-community-monitor.test.ts` — same.

- [ ] 1.9 Per cron: keep/confirm one existing infra-fault test asserting `status=error` (setup-workspace / parse-event / token mint).

## Phase 2 — GREEN (implementation, per cron)

Pattern-A (mirror bug-fixer): add `else if (!spawnResult.ok) { warnSilentFallback(... op=claude-eval-nonzero-noop ...) }` + success-path `postSentryHeartbeat({ ok: true, ... })`; inline liveness-contract comment.
- [ ] 2.1 `cron-agent-native-audit.ts` (`:246`)
- [ ] 2.2 `cron-legal-audit.ts` (`:263`)
- [ ] 2.3 `cron-campaign-calendar.ts` (`:196`)
- [ ] 2.4 `cron-ux-audit.ts` (`:329`)

Pattern-B (copy the 3 wired producers): capture `runStartedAt` before spawn; `const heartbeatOk = await step.run("verify-output", () => resolveOutputAwareOk({ spawnOk: spawnResult.ok, label: SENTRY_MONITOR_SLUG, runStartedAt, cronName }))`; feed `ok: heartbeatOk`; return `{ ok: heartbeatOk }`.
- [ ] 2.5 `cron-growth-audit.ts` (`:197`)
- [ ] 2.6 `cron-growth-execution.ts` (`:234`)
- [ ] 2.7 `cron-seo-aeo-audit.ts` (`:226`)
- [ ] 2.8 `cron-community-monitor.ts` (`:292`)

## Phase 3 — Enforcement + suite

- [ ] 3.1 Extend `cron-producer-output-wiring.test.ts`: add the 4 Pattern-B crons to `ALWAYS_CREATE_PRODUCERS` (assert `resolveOutputAwareOk(` present, `ok: spawnResult.ok` absent).
- [ ] 3.2 Add a sibling guard for the 4 Pattern-A crons: no `ok: spawnResult.ok`, no `resolveOutputAwareOk`, has `postSentryHeartbeat({ ok: true` + a `warnSilentFallback` op.
- [ ] 3.3 `git grep -nE "ok: spawnResult\.ok" apps/web-platform/server/inngest/functions/cron-*.ts` returns 0 hits.
- [ ] 3.4 `tsc --noEmit` clean (run via the package's configured command).
- [ ] 3.5 Run the changed cron test files + the cron suite via the package's configured runner (vitest per `package.json scripts.test` + `vitest.config.ts include` — do NOT hardcode `bun test`).

## Verification

- [ ] AC: each cron's heartbeat semantic decided + documented inline.
- [ ] AC: tests RED→GREEN per cron (4A + 4B shapes).
- [ ] AC: infra-fault early-returns remain strict (`status=error`).
- [ ] AC: producer-wiring test extended; Pattern-A guard added.
