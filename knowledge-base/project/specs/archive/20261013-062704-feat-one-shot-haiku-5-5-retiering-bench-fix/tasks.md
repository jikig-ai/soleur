# Tasks: Haiku 5.5 re-tiering verdicts (#9790), design questions, bench self-test hardening

Plan: `knowledge-base/project/plans/2026-10-09-chore-haiku-5-5-retiering-verdicts-and-bench-self-test-plan.md`
Evidence: `knowledge-base/project/specs/feat-one-shot-haiku-5-5-retiering-bench-fix/plan-time-evidence.md`

Rules for every task: synthesized inputs only; the `soleur-ci-eval` key only via
`doppler run -p soleur -c ci --silent --` (env, never argv, never printed, no `set -x`); no raw payloads
or credentials in committed files; a cap or limit error is a non-result, never a pass.

## 1. Gate 0 re-measurement and verdicts (no model spend)

- 1.1 Re-run the Better Stack pull and the `jq` recipe (evidence file section 2) for the post-cutover window (2026-10-01 onward); fill S, null/zero marker count and missing days per cron.
- 1.2 Re-check `claude-code-review.yml` state with `gh api repos/jikig-ai/soleur/actions/workflows`. The workflow-transcript count is informational only.
- 1.3 Apply the Gate 0 table mechanically (threshold $12.50/month at factor 0.65). Record a verdict per class. A qualifying class gets its own PR (plan Phase 3b); do not move it here.

## 2. Alert on the `no-text-block` mirrors (tests first)

- 2.1 Write `apps/web-platform/test/sentry-no-text-block-alert-op-contract.test.ts` (RED): scan `server/` for emit sites, assert filter match, site-count floor of 2, rate trigger.
- 2.2 Add `sentry_alert.haiku_no_text_block_rate` to `apps/web-platform/infra/sentry/issue-alerts.tf` (1 h interval, value 4, `op eq no-text-block`, `feature in domain-router,email-triage`, `frequency_minutes = 37` after re-checking it is unused).
- 2.3 Add the `alert-reference.json` entry and the README count per `apps/web-platform/infra/sentry/README.md`.
- 2.4 Run the contract test, `bash scripts/sentry-alert-reference-gate.sh`, `bash plugins/soleur/test/c4-count-parity.test.sh`.

## 3. Bench self-test guard and hermeticity (tests first)

- 3.1 Write `scripts/learning-retrieval-bench.test.sh` (RED): one run under a constructed hostile environment (`env -i` plus allowlist; `NO_PARAPHRASE=1`, synthetic `ANTHROPIC_API_KEY`, `CURL_BIN` = wrapper-owned recorder); recorder positive control first; assert `FAIL=0`, TOTAL at or above the bench floor, named rows present, recorder empty afterwards.
- 3.2 In `scripts/learning-retrieval-bench.sh` `self_test()`: `NO_PARAPHRASE=0`, `unset ANTHROPIC_API_KEY`, fail-closed `CURL_BIN`, before the first fixture. Delete the `LIVE_API=1` lines (29 and 125).
- 3.3 Run the five Guard 1 mutations and the harness rows; each must turn the wrapper RED.
- 3.4 Measure the wrapper's weight. At or under 10 s: an `ALWAYS_ON_SUITES` entry; over: an `AFFECTED_*_PATHS` block only (edge-selected). Add the `scripts/suite-durations.tsv` row and the `scripts/lib/test-affected-paths.sh` edge; confirm with `bash scripts/test-all.sh --print-selection --paths=scripts/learning-retrieval-bench.sh`.

## 4. ADR-053 addendum and disposition

- 4.1 Append "Addendum — 2026-10-09 (#9790)" to ADR-053: Gate 0 method, assumptions and table; per-class verdicts; the CLI internal-model table (evidence file section 3); leader-effort and refusal-retry rules with their `spawn-agent-dead-letter` triggers; the cost-marker first-key attribution limit; the alert and its recalibration step; the re-open trigger ($19.23/month); supersession blockquotes for "fires per PR" and "tracked as #9790".
- 4.2 PR body: `Closes #9790` only if AC1-AC7 are all delivered, else `Ref #9790` with the list. State the stale-base finding, no tracking issue filed, and the measurement spend incurred.
- 4.3 Run `python3 scripts/lint-guard-contract.py`, the lints, and `bash scripts/test-all.sh --affected` once at the end (ship Phase 4).
