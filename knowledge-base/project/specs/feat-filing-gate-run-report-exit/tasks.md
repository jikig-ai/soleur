# Tasks: feat-filing-gate-run-report-exit

Plan: `knowledge-base/project/plans/2026-09-11-feat-filing-gate-run-report-exit-plan.md`
Issue: #8076 · PR: #8074 · Lane: cross-domain · Threshold: single-user incident

Every phase is RED → GREEN (`cq-write-failing-tests-before`). Typecheck:
`cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`. Runner: vitest
(`./node_modules/.bin/vitest run <path>`), shell suites via `bash`.

## Phase 1 — Directive contract (FR1, FR2, TR1, TR2)

- [x] 1.1 Create `apps/web-platform/server/inngest/functions/_cron-run-reports.ts`: `RUN_REPORT_TITLE_PREFIX`, `RUN_REPORT_CRONS` (ten rows: nine `resolveOutputAwareOk` callers + legal-audit; literal `closeAfterDays`; `null` for campaign-calendar and legal-audit)
- [x] 1.2 RED: `test/server/inngest/cron-run-report-labels-parity.test.ts` — (i) call-site grep ⇔ rows (regex excludes comments), (ii) `CRON_BASH_ALLOWLISTS` has `gh issue create` for every `fn`, (iii) `closeAfterDays === 3 × maxGapDays` for `TASK_INVENTORY` rows
- [x] 1.3 RED: hook rows in `cron-bash-allowlist-hook.test.ts` (`describe("Bash — run-report exit (class 3)")`): Guard-1 matrix #1–#8, H1 floor, H2 (comma-joined, `-l`, campaign-calendar `[Content] Overdue:`), H3 (`&&` chain)
- [x] 1.4 GREEN hook: `parseAllowlist` `run-report-label` directive; extract `labelTokenEquals` from `hasMachineryLabel`; exit 0 (label-only) first in `filingJustificationReason(tokens, readTaxonomy, runReportLabel)`; `decide()` threads `allow.runReportLabel`; deny text suffix when a directive exists
- [x] 1.5 RED: substrate rows in `cron-claude-eval-substrate.test.ts` — directive delivered per mapped cron; absent for `cron-ux-audit`; self-test probes (a)/(b)/(c)
- [x] 1.6 GREEN substrate: derive `CRON_RUN_REPORT_LABELS` from the leaf; push `run-report-label <label>` in `allowlistLines`; `runHookSelfTest(…, runReportLabel)` with probes (a) allow, (b) prose-mention deny, (c) suffix deny
- [x] 1.7 AC1, AC2, AC3, AC14 green

## Phase 2 — Denial observability (FR5, TR5)

- [x] 2.1 RED: `parseClaudeResultLine` rows — two filing-shaped `permission_denials` + one non-filing → `filingDenials: 2`; empty → 0; marker emitted once with `count: 2`, never at 0
- [x] 2.2 GREEN: `ParsedEvalResult.filingDenials` (filter on the two filing shapes from `filingJustificationReason` L89-101); in `finish()` beside `emitClaudeCostMarker`, `log.warn({ SOLEUR_CRON_FILING_DENY: true, fn, runId, runStartedAt, count, commands })` via a module-level `pino({ base: { component: "cron-filing-deny" } })`
- [x] 2.3 Runbook row in `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`: marker → Sentry `scheduled-output-missing` filtered on `fn` + `runStartedAt`
- [x] 2.4 AC4, AC13 green

## Phase 3 — Measurement and records (FR3, FR6)

- [x] 3.1 RED: `plugins/soleur/test/issue-flow-measure.test.sh` (stub `gh`): lines `1c.`/`1d.` from stubbed counts, headline unchanged, label array ≡ `_cron-run-reports.ts` by grep, 1d query carries `-label:keep-open`
- [x] 3.2 GREEN: `scripts/issue-flow-measure.sh` lines 1c (author:app/soleur-ai + OR-joined run-report labels) and 1d (`meta/machinery -label:keep-open`)
- [x] 3.3 RED row in `plugins/soleur/test/machinery-drain-floor.test.sh`: both pool queries carry `-label:keep-open`
- [x] 3.4 GREEN: `scheduled-machinery-drain.yml` — `-label:keep-open` on pool count (L58-62) and post-count (~L96-99); `keep-open` on the create path (L173-174); `group-by-area.sh:116-117` applies the kill-switch exclusion for the machinery label too
- [x] 3.5 One-time: `gh issue edit 8068 --add-label keep-open`
- [x] 3.6 ADR-216 addendum `## Addendum 2026-09-11 — the fourth population` (population key, D1 include, title-half cut, rejected alternatives incl. jsonl deny log, exits list → four, class-3 row); ADR-058 one-line cross-reference
- [x] 3.7 `AGENTS.rules.md:89` body edit (adds "or carry its cron's substrate-issued run-report label (ADR-216)") → `python3 scripts/lint-rule-bodies.py --write` → ack line in `.claude/rule-weakening-acks.txt` (`wg-defer-only-after-inline-triage|<hash>|2026-09-1x|8076|<narrowing recorded honestly>`)
- [x] 3.8 AC5, AC6, AC11, AC12 green; `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md 2>&1` exits 0

## Phase 4 — Run-report lifecycle (FR4)

- [x] 4.1 RED row in `cron-shared.test.ts`: a closed issue updated in-window is NOT credited; an open comment-bumped one is; a created-in-window one is
- [x] 4.2 GREEN: `verifyScheduledIssueCreated` client guard `created_at ≥ since || (updated_at ≥ since && state === "open")`; update the L797-812 comment
- [x] 4.3 RED rows in `cron-stale-deferred-scope-outs.test.ts`: Guard-2 matrix #1–#14, H1, H2 (#8027 label set minus action-required IS closed), plus the daily-triage jq row in `cron-daily-triage.test.ts`
- [x] 4.4 GREEN: `sweepRunReports` in its own `step.run("sweep-run-reports")` with own catch + `SweepResult.runReports`; per-row query (`author:app/soleur-ai`, `created:<cutoff`); `SweepCandidate` + `body`, `created_at`; guard order (title shape → kill-switch → `action-required` → FAILED body/title → human comment → marker-present skips POST only); `state_reason: "completed"`; `MAX_RUN_REPORT_CLOSES_PER_RUN = 25`; `__TESTING__` exports
- [x] 4.5 GREEN: `cron-daily-triage.ts:69` jq predicate excludes `scheduled-*`
- [x] 4.6 AC7, AC8 green

## Phase 5 — Interactive-gate false denies (FR7)

- [x] 5.1 RED rows in `.claude/hooks/guardrails.test.sh`: Guard-3 matrix #1–#5, H2 (heredoc apostrophe passes; `--title` apostrophe denies with the tokenizer message), regression pin (heredoc-only `gh issue create` does not trigger); `MIN_ASSERTIONS` restated as `106 + <rows>`
- [x] 5.2 GREEN: `lib/incidents.sh` — shared heredoc regex + `strip_heredocs` (first substitution only); `guardrails.sh` L451 tokenizes the stripped corpus, denies on `xargs` failure with the unbalanced-quoting message; L616-628 body-file deny wrapped in `if [[ "$_fj_pass" == 0 ]]`
- [x] 5.3 AC9 (from worktree AND a tmp CWD), AC10 green

## Phase 6 — Ship gates

- [x] 6.1 AC15 `bash plugins/soleur/test/c4-count-parity.test.sh` green
- [x] 6.2 Follow-through: `scripts/followthroughs/run-report-exit-first-contact-8076.sh` (AC18 + AC19 assertions), directive + `follow-through` label on #8076, secrets wired in `scheduled-followthrough-sweeper.yml` if absent
- [x] 6.3 PR body: `Closes #8076`; no `ADR-217` anywhere in plan/spec/tasks (`grep -rn ADR-217 knowledge-base/project/{plans,specs}/*8076* knowledge-base/project/specs/feat-filing-gate-run-report-exit/` empty)
- [ ] 6.4 Merge before Sat 2026-09-12 night (architecture-diagram-sync fires Sun 02:00Z)
