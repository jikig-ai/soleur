# Tasks: automate the real-SDK ask probe (Part 1 of #10111)

Plan: `knowledge-base/project/plans/2026-11-01-chore-scheduled-real-sdk-ask-probe-plan.md`
Branch: `feat-one-shot-10111-sdk-probe-schedule` | Draft PR: #11784 | Issue: `Ref #10111` (never `Closes`) | Epic: #9601
Rulings: `knowledge-base/project/specs/feat-one-shot-10111-sdk-probe-schedule/decision-challenges.md`

Holds that apply to every task: no feature flag created or flipped (#11237 untouched); no production-sink emission; #9543 not re-opened;
no agent records the operator's acceptance of ADR-284 Flip criterion 4; no "verified in production" wording anywhere; preflight Check 4
(reads Doppler) is skipped and the PR body says so; CI is the test gate.

## Phase 0 - measure before building

- 0.1 Re-check the CTO's unverified items: labels exist (`type/security`, `priority/p1-high`, `priority/p2-medium`, `domain/engineering`); `plugins/soleur/hooks/**` belongs in the push filter (the probe loads `plugins/soleur` as an SDK plugin).
- 0.2 Write the Guard 1 import extractor (static, multi-line and dynamic imports), run it on `dev-probe-destroy-ask.ts` and `permission-callback.ts`, record the counts and set the floors to them.

## Phase 1 - RED tests first

- 1.1 `apps/web-platform/test/probe-budget.test.ts` (Guard 5 rows) against absent `scripts/lib/probe-budget.ts`.
- 1.2 `apps/web-platform/scripts/real-sdk-ask-probe.test.sh` (Guard 3 and 4 rows, `should-run` fixtures, redaction, xtrace refusal) against absent runner.
- 1.3 `plugins/soleur/test/real-sdk-ask-probe-workflow.test.sh` (Guard 1 and 2 rows, AC6 string assertions, AC10 production-sink grep, cron literal once, required-checks absence).
- 1.4 Confirm each fails for the right reason.

## Phase 2 - probe changes (`apps/web-platform/scripts/dev-probe-destroy-ask.ts`)

- 2.1 `scripts/lib/probe-budget.ts`: `RUN_BUDGET_USD = 4`, `perCaseBudgetUsd(n)`, ledger, `costFromResult` (latest `total_cost_usd`, not a sum).
- 2.2 Probe: honour `PROBE_RUN_BUDGET_USD` downward only; per-case `maxBudgetUsd` (harness-only, not in the production option builder), `costUsd=` on each `PROBE` line, cumulative stop with `CANT-RUN:budget-exceeded`, `error_max_budget_usd` mapping, `TOTAL costUsd=` line before `RESULT`.
- 2.3 Header comment: the re-run is now automated by #10111 Part 1; PROBE_DECODE_ONLY untouched.

## Phase 3 - runner (`apps/web-platform/scripts/real-sdk-ask-probe.sh`)

- 3.1 xtrace refusal preamble (lint Rule A), `set -uo pipefail`.
- 3.2 `should-run`: baseline = head SHA of the last completed non-cancelled run of this workflow (needs `actions: read`); allowlist + lockfile SDK-version compare; zero `before`, unfetchable baseline or any error -> run.
- 3.3 `run`: single `classify()`, redaction, one whole-probe rerun on the REMAINING budget (not for budget-exceeded / no key), summary lines (host-only residual, production arrival not observed), `$GITHUB_OUTPUT`.
- 3.4 `file-issue`: empty outcome from a failed/cancelled probe job -> blind / `no-outcome`; `reason` enum and numeric `cost` validated in `classify()`; duplicate open blind issues handled (comment on oldest, PASS closes all blind, never regression); exact-title dedupe, regression (p1, human-closed, "subsequently passed" note), blind (p2, self-closing), skipped = no writes; bodies via `printf` + `--body-file`, linking the ADR-284 C9 result and the 2026-10-11 post-mortem.

## Phase 4 - workflow (`.github/workflows/scheduled-real-sdk-ask-probe.yml`)

- 4.1 Override marker + justification, `# Task design:` header, triggers, concurrency, permissions.
- 4.2 Job `probe`: SHA-pinned steps, same-repo guard, should-run, bun/node, `npm ci --ignore-scripts`, bubblewrap + socat + userns sysctl, `anthropic-preflight`, probe step (only step with the key), SKIPPED summary, artifact upload.
- 4.3 Job `file-issue`: main only, `issues: write`, no key.
- 4.4 Timeouts provisional (job 65 / probe step 50), `permissions: contents: read, actions: read` on the probe job, `pull_request` paths = the four files that execute with the key, job `if:` excludes forks and `dependabot[bot]`; the header carries no cron literal;  re-derived from the self-test's measured elapsed.

## Phase 5 - self-test evidence (pre-merge)

- 5.1 Push; the own-file `pull_request` trigger runs it. Quote PROVENANCE, 8 `PROBE` lines, `RESULT`, `TOTAL costUsd`, elapsed in the PR body.
- 5.2 Apply the CTO triggers before merge: first cost above $2.50/run or projected 30-day spend above $25 -> shape (c).
- 5.3 Record the negative control (AC5). If CANT-RUN or flaky, record the pass rate and claim no guard proof.

## Phase 6 - docs, ADR, C4, compliance

- 6.1 ADR-284 amendment (Runtime proof sentence, Flip criterion 5 wording + closing sentence, new Amendment section with caps and residuals, re-evaluation verdict).
- 6.2 `model.c4` `github -> anthropic` edge description; `scripts/regenerate-c4-model.sh` (commit `model.likec4.json` and `c4-model.md` if changed); run c4-count-parity, c4-code-syntax, c4-render, c4-model-freshness.
- 6.3 `article-30-register.md` PA-33 (member (9), machinery-drain member (8), counts, fields (a)(c)(d)(f)(g)), LIA Arm C line, DPIA screening `Superseded` marker (`knowledge-base/legal/audits/2026-07-31-dpia-screening-claude-eval-fleet-and-ci.md`), `compliance-posture.md` row; CLO reviews the wording.
- 6.4 `expenses.md` "Anthropic API (CI)" row and `api-spend-reconciliation.md` note.

## Phase 7 - registry, lints, #10111, PR

- 7.1 `scripts/lib/test-affected-paths.sh` flat-array entries (one per file the plugin suite reads, with evidence comments); `scripts/pr-fanout-ledger.txt` row; `bash scripts/lint-orphan-test-suites.sh`; `scripts/suite-shard-legs.tsv` and `scripts/suite-durations.tsv` rows for the runner suite.
- 7.2 Lints: `lint-shell-trace-credential-refusal.py`, `lint-guard-contract.py`, `lint-legal-registers.sh`, `lint-art30-reverification.sh`, `lint-infra-no-human-steps.py`.
- 7.3 Edit #10111 in place (`gh issue edit`, body via `--body-file` with a literal absolute path written in a separate call): retitle, Part 1 delivered, Part 2 under `Operator-reserved:` with the design sketch, re-evaluation criteria kept, milestone and labels unchanged.
- 7.4 PR body: `Ref #10111`, API-budget disclosure, self-test evidence, Check 4 skipped, no gate-override needed (0 filed / 0 closed).
