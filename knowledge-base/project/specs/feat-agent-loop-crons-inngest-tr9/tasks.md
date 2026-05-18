---
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-05-18-feat-pr-1-migrate-scheduled-daily-triage-to-inngest-cron-tr9-plan.md
issue: "#3948"
draft_pr: "#3985"
---

# Tasks — TR9 PR-1 (scheduled-daily-triage → Inngest)

Derived from `knowledge-base/project/plans/2026-05-18-feat-pr-1-migrate-scheduled-daily-triage-to-inngest-cron-tr9-plan.md` v2 (post 5-agent plan-review reconciliation).

## 0 — Preconditions

- [ ] **0.1** `npm view @anthropic-ai/claude-code dist-tags.latest` → record `<version>` for 1.1.
- [ ] **0.2** Verify CLI flags + binary-resolution under esbuild bundling: `bun add @anthropic-ai/claude-code@<version>` in `apps/web-platform/`, then throwaway probe `apps/web-platform/server/__probe.ts` exec'ing `spawn("claude-code", ["--version"])`; expect exit 0. Discard the probe.
- [ ] **0.3** Verify `detached: true` + process-group SIGTERM propagates to grandchildren: `bash -c 'claude-code --prompt "Run: bash -c \"sleep 300\"" --max-turns 1 & PID=$!; sleep 2; kill -TERM -- -$PID; wait $PID; pgrep -P $PID || echo "no orphans"'`. Confirm zero orphans within ~5s.
- [ ] **0.4** `/soleur:gdpr-gate` against this plan; expect bucket (i), no Article 30 amendment. Halt only on Critical findings.

## 1 — Add claude-code dependency

- [ ] **1.1** `cd apps/web-platform && bun add @anthropic-ai/claude-code@<version-from-0.1>`. Commit `package.json` + `bun.lock` (+ `package-lock.json` if regenerated).

## 2 — Inngest cron function

- [ ] **2.1** Create `apps/web-platform/server/inngest/functions/cron-daily-triage.ts`. Inline `DAILY_TRIAGE_PROMPT` as TS template literal (full prompt verbatim from `.github/workflows/scheduled-daily-triage.yml:86-141` with one diff: prompt step 3d enforces IDEMPOTENT search-before-add via `gh issue view --json comments`).
- [ ] **2.2** Handler: `step.run("claude-eval", ...)` spawns `claude-code` with `detached: true`, `signal: ac.signal` (`AbortController` 60-min timeout), captures `{ok, exitCode, signal, abortedByTimeout, durationMs}`. Manual SIGTERM→SIGKILL escalation on abort: `process.kill(-child.pid, "SIGTERM")` then SIGKILL at +5s.
- [ ] **2.3** Handler: `step.run("sentry-heartbeat", ...)` POSTs to slug `scheduled-daily-triage` (continuity — NOT `cron-daily-triage`) with `?status=ok|error`. Skips if Sentry env unset.
- [ ] **2.4** Register `cronDailyTriage` via `inngest.createFunction(opts, [{cron:"0 4 * * *"}, {event:"cron/daily-triage.manual-trigger"}], handler)`. `concurrency: [{scope:"fn",limit:1}, {scope:"account",key:'"cron-platform"',limit:1}]`, `retries: 1`.

## 3 — Wire into route.ts

- [ ] **3.1** Edit `apps/web-platform/app/api/inngest/route.ts`: `import { cronDailyTriage }` + append to `functions: [...]`.

## 4 — Sentinel sweep (inverse-assertion, hardened)

- [ ] **4.1** Edit `apps/web-platform/test/server/byok-audit-writer-sweep.test.ts`: `export` `LEASE_CALL_RE` + `ALIAS_IMPORT_RE`; add new `export const BARE_IMPORT_RE = /import\s*\{[^}]*\brunWithByokLease\b[^}]*\}/`. Existing tests in same file continue to work via module-local references.
- [ ] **4.2** Create `apps/web-platform/test/server/cron-no-byok-lease-sweep.test.ts`: imports the three regexes; globs `server/inngest/functions/cron-*.ts`; asserts NO match across all three regexes per file. `expect.soft` reports which shape caught any violation. Sanity check: `cronFiles.length > 0`. Fixture proofs: direct-call, aliased import, bare named import (new), compliant cron-* file.

## 5 — Sentry monitor margin adjustment

- [ ] **5.1** Edit `apps/web-platform/infra/sentry/cron-monitors.tf`: `scheduled_daily_triage` `checkin_margin_minutes` `180` → `30`. Resource id, `name`, slug UNCHANGED.

## 6 — Tests

- [ ] **6.1** Create `apps/web-platform/test/server/inngest/cron-daily-triage.test.ts` covering T1-T5 (happy path, spawn error, AbortSignal SIGKILL escalation, missing Sentry env, event-trigger path). Mocks: `child_process.spawn`, `fetch`, `step.run` (eager-callback like `cfo-on-payment-failed.test.ts`).

## 7 — GHA YAML deletions

- [ ] **7.1** `git rm .github/workflows/scheduled-daily-triage.yml`.
- [ ] **7.2** `git rm .github/workflows/scheduled-dogfood-once-3049.yml`.
- [ ] **7.3** `git rm .github/workflows/scheduled-dogfood-once-3049-v2.yml`.

## 8 — Umbrella body + ADR amend + principles entry + spec retract

- [ ] **8.1** `gh issue edit 3948 --body-file -` appending `## Umbrella Children` section with 11 markdown checkboxes (10 recurring + 1 gdpr-gate-50d conversion). Each line: workflow name + cron schedule + side-effect class + CLO bucket.
- [ ] **8.2** Edit `knowledge-base/engineering/architecture/decisions/ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md`: I3 → "AbortSignal aborts at 60 min (matches GHA timeout; preserves 0.75 peer ratio for 80-turn budget). `[Refined 2026-05-18 post PR-1 plan review]`." I4 → "claude-code installed as `apps/web-platform/package.json` dependency; ships via existing deploy pipeline. `[Refined 2026-05-18 post PR-1 plan review]`."
- [ ] **8.3** Edit `knowledge-base/engineering/architecture/principles-register.md`: add AP-014 row "Platform-loop / per-founder cohabitation boundary" sourced to ADR-033 I2 + I6. Enforcement: build-time sentinel.
- [ ] **8.4** Edit `knowledge-base/project/specs/feat-agent-loop-crons-inngest-tr9/spec.md`: prepend `[Revised post plan-review 2026-05-18]` retract block to FRs section explaining FR1/FR2/FR7/TR4/TR8 (ledger) retraction. Update FR3 to reflect prompt-inlined-as-template-literal. Update FR8 to reflect Sentry slug continuity. Update claude-code-install FR to reflect package.json dep.

## 9 — Pre-merge verification

- [ ] **9.1** `cd apps/web-platform && bun run typecheck` — clean.
- [ ] **9.2** `cd apps/web-platform && bun run test:ci` — all suites pass.
- [ ] **9.3** `terraform fmt -check apps/web-platform/infra/sentry/` — clean.
- [ ] **9.4** Update PR #3985 body: summary, `Refs #3948` (NOT `Closes`), user-impact threshold + three vectors enumerated, v1→v2 reconciliation note.

## 10 — Post-merge (automation; runbook reference only)

- [ ] **10.1** Deploy pipeline ships claude-code via `npm install` on Hetzner; Inngest worker restarts auto-registers `cronDailyTriage`.
- [ ] **10.2** `apply-sentry-infra.yml` auto-applies margin adjustment.
- [ ] **10.3** Within ~5 min of deploy: `inngest send cron/daily-triage.manual-trigger` to validate end-to-end before waiting for next 04:00 fire. Verify: Sentry `status=ok` heartbeat + ≥1 newly-labeled issue via `gh issue list`.
