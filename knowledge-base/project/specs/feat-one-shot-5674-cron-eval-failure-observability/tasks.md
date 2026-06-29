# Tasks — fix: make claude-eval cron failures observable (#5674)

Plan: `knowledge-base/project/plans/2026-06-29-fix-claude-eval-cron-failure-observability-plan.md`
Lane: cross-domain · Threshold: single-user incident · requires_cpo_signoff: true

> Deepened 2026-06-29 (8 review agents). Key corrections folded in: run-log gates
> ONLY the thrown path (returned `ok:false` is terminal → must write); Part-2 is
> **classify-fatal**, not flip-all (reconciles #4730 precedent, CPO sign-off on
> issue-letter departure); canary needs the widened `postAnthropicMessage` body;
> spend-trend admin path cut to follow-up; output-aware cohort is **8** crons.

## Phase 0 — Setup & preconditions
- [ ] 0.1 Read the 4 masked cron handlers + `_cron-shared.ts` (incl. `postAnthropicMessage` L277-318, `resolveOutputAwareOk` L573-576) + `run-log.ts` end-to-end before editing.
- [ ] 0.2 Pull Better Stack history for the 4 masked crons; record BENIGN healthy-non-zero-exit frequency (justifies the classify-fatal carve-out) AND validate the fatal-marker set against real tails (R1 input).
- [ ] 0.3 Read all three `.c4` model files; determine Anthropic-API / Sentry / routine_runs element coverage.
- [ ] 0.4 Obtain CPO / issue-author sign-off on classify-fatal (departs from issue's literal "non-zero must not post green"). Record in PR body (AC11).

## Phase 1 — Capture failure reason + unify run-log
- [ ] 1.1 Add `formatTailForSentry()` (multi-secret `redactGithubSourcedText` scrub + slice) to `_cron-shared.ts`.
- [ ] 1.2 **F1 retrofit:** route `resolveOutputAwareOk`'s `scheduled-output-missing` extra (L573-576, currently `redactToken`-only) through `formatTailForSentry` — closes the pre-existing `sk-ant` Sentry leak.
- [ ] 1.3 Define shared `EvalHeartbeatDecision = { ok; errorSummary?; sentryExtra }`; extend `resolveOutputAwareOk` to also emit scrubbed `errorSummary` (so the 8 output-aware crons populate `routine_runs.error_summary`).
- [ ] 1.4 Add `resolveBestEffortEvalOk(spawnResult): EvalHeartbeatDecision` doing classify-fatal (Phase 2) + scrubbed tails via `formatTailForSentry`.
- [ ] 1.5 **CRITICAL — `run-log.ts` gate ONLY the thrown path:** `if (threw && !isFinalAttempt) return;` where `failed = threw || data?.ok === false`. A returned `{ok:false}` is terminal → MUST write now (do NOT ride the final-attempt gate — that was the P0 regression in the first draft).
- [ ] 1.6 Derive `error_summary` via one `firstLine→redact→truncate` helper for both thrown and returned paths.
- [ ] 1.7 Document the widened `ROUTINE_METADATA` `ok:false`=failed contract at the write site; cross-consumer grep `return { ok:` to confirm no benign `ok:false` sentinel exists (`hr-type-widening-cross-consumer-grep`).
- [ ] 1.8 Unit tests: AC1 (fatal reason→sentryExtra+ok:false), AC2 (`formatTailForSentry` redaction incl. retrofitted output-aware extra), AC3 (returned ok:false on attempt 0 of maxAttempts:2 WRITES; thrown non-final = no write), AC6 (reason survives scrub+slice).

## Phase 2 — Classify-fatal heartbeat policy (4 masked crons)
- [ ] 2.0 Define the shared fatal-marker constant (credit `/credit balance is too low/i`, auth/401, spawn-fault) in `_cron-shared.ts`; import in both resolver and canary (single source).
- [ ] 2.1 `cron-agent-native-audit.ts`: route non-zero through `resolveBestEffortEvalOk`; `postSentryHeartbeat({ok:decision.ok})`; return `{ok,errorSummary}`; update stale "stays green" comment to cite classify-fatal + #4730.
- [ ] 2.2 `cron-legal-audit.ts`: same.
- [ ] 2.3 `cron-ux-audit.ts`: same.
- [ ] 2.4 `cron-bug-fixer.ts`: same — **audit EVERY return/heartbeat site (~L819/L860/L901)**, not just the first; benign no-PR path MUST stay green (highest healthy-non-zero frequency).
- [ ] 2.5 Fold `abortedByTimeout` into the fatal class (single signal; drop the old strict early-return double-signal).
- [ ] 2.6 Handler tests (AC4): fatal tail → `postSentryHeartbeat ok:false` + `{ok:false,errorSummary}`; BENIGN max-turns non-zero → `ok:true` (green) + reason recorded (named test — the #4730 carve-out).

## Phase 3 — Anthropic credit canary probe
- [ ] 3.0 **Widen `postAnthropicMessage`** to surface a bounded, `formatTailForSentry`-scrubbed body on non-ok (typed `AnthropicApiError{status,bodyExcerpt}`); update the L306-307 shape comment.
- [ ] 3.1 Sweep the 2 existing callers (`cron-compound-promote.ts:438`, `cron-weekly-release-digest.ts:328`) + their tests for backward-compat (AC8).
- [ ] 3.2 Create `cron-anthropic-credit-probe.ts` (hourly; canary via widened transport; model from `lib/ai/model-tiers.ts` not a literal). Branch: credit-marker→page `anthropic-credit-exhausted`; 401→`anthropic-key-invalid`; **transient/unclassified (429/500/529/network)→re-throw** (Inngest retry, no false page); clean→`ok:true`. **No admin/spend branch** (follow-up).
- [ ] 3.3 Register in `app/api/inngest/route.ts` functions array.
- [ ] 3.4 Add to `EXPECTED_CRON_FUNCTIONS` (`cron-manifest.ts`).
- [ ] 3.5 Add canary-only `ROUTINE_METADATA` entry (`routine-metadata.ts`, 10–160 chars).
- [ ] 3.6 Add `scheduled_anthropic_credit_probe` monitor (30-min margin, small-cron tier) to `cron-monitors.tf`.
- [ ] 3.7 Bump `function-registry-count.test.ts` (`toBe(56)`→57) + fix slug/tf-monitor assertions; pass `routine-metadata-parity.test.ts` (AC7).
- [ ] 3.8 Probe tests (AC5): credit-400→page; 401→key-invalid; 529/429/unclassified→re-throw; clean→ok.
- [ ] 3.9 Confirm no `runWithByokLease` import (ADR-033 I2 sweep test passes, AC10).

## Phase 4 — Docs / ADR / C4
- [ ] 4.1 Amend ADR-033: classify-fatal heartbeat invariant (supersede/reconcile #4730); widened `routine_runs` ok:false=failed + thrown-only gate; Alternatives (liveness-green superseded, flip-all rejected, two-phase unneeded); no-balance-endpoint (canary now, spend-trend follow-up).
- [ ] 4.2 C4: add missing Anthropic-API / Sentry / routine_runs elements+edges+view-include if absent; run c4 tests. Else cite checked-and-modeled.
- [ ] 4.3 Update `runbooks/cloud-scheduled-tasks.md`: new `anthropic-credit-exhausted` / `anthropic-key-invalid` ops + triage; note classify-fatal (benign non-zero stays green) so operators don't expect every non-zero to page; note `postSentryHeartbeat` red flip is margin-backed.

## Phase 5 — Verify
- [ ] 5.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (AC9).
- [ ] 5.2 Run inngest + run-log + c4 test suites green (check `vitest.config.ts` include globs; tests under `test/server/inngest/`).
- [ ] 5.3 Pre-merge AC 1–11 checked; CPO sign-off + R1 evidence recorded in PR body.

## Follow-up (tracked, NOT this PR)
- [ ] F.1 File `Ref #5674` follow-up: pre-exhaustion spend-vs-budget alert via Admin `cost_report` (needs new `sk-ant-admin` secret + operator `ANTHROPIC_MONTHLY_BUDGET_USD`); records no-balance-endpoint constraint, CFO review, `x-api-key`+`anthropic-version` header, Playwright-first admin-key mint (automation-status UNVERIFIED). File before PR-ready (defer-only-after-inline-triage).

## Post-merge (automated, no operator step)
- [ ] P.1 `/soleur:ship` post-merge: verify `scheduled-anthropic-credit-probe` monitor exists via Sentry API (read-only, Doppler-sourced token; no SSH, no dashboard eyeball). No new secret to provision — canary reuses `ANTHROPIC_API_KEY`.
