# Tasks — chore(inngest): consolidate 9 bot commit pipelines onto safeCommitAndPr (#5111)

Plan: `knowledge-base/project/plans/2026-06-10-chore-safe-commit-consolidation-9-pipelines-plan.md`
Lane: cross-domain (fail-closed default — no spec.md `lane:` for this branch)

## Phase 1 — Helper option surface (tests first)

- [x] 1.1 RED: add new-option scenarios to `apps/web-platform/test/server/inngest/cron-safe-commit.test.ts` (branchName override + refname rejection; commitBody second paragraph; prTitle/prBody/prDraft/prLabels pass-through; syntheticChecks check-run POSTs on head SHA; mergeMode "direct" happy / direct-fail→arm-auto-merge / both-fail→failed("auto-merge"); mergeMode "none" never merges; defaults-unchanged regression block)
- [x] 1.2 GREEN: widen `SafeCommitConfig` in `_cron-safe-commit.ts` (branchName, commitBody, prTitle, prBody, prDraft, prLabels, syntheticChecks, mergeMode) — all optional, defaults preserve current behavior; do NOT widen the `stage` union
- [x] 1.3 Consolidate `SYNTHETIC_CHECK_NAMES` into `_cron-safe-commit.ts` (drift check done at deepen time: all 5 copies byte-identical — plain consolidation, update 5 imports + test imports)
- [x] 1.4 Cross-consumer grep per hr-type-widening: `git grep -n "safeCommitAndPr({" apps/web-platform/` — existing 3 callers compile unchanged

## Phase 2 — 4 prompt-level crons (Tier-2 dormant)

For each of campaign-calendar, growth-audit, community-monitor, competitive-analysis:

- [x] 2.1 Update anchor tests RED (PERSISTENCE anchor present, MANDATORY FINAL STEP absent, no git/gh-pr verbs in prompt, gated safe-commit-pr step present — mirror cron-seo-aeo-audit.test.ts:93 pattern; competitive-analysis test currently preserves the block verbatim — replace those anchors)
- [x] 2.2 `cron-campaign-calendar.ts`: remove prompt commit block (:100-110) + preamble ref (:74); add PERSISTENCE directive; `CAMPAIGN_CALENDAR_ALLOWED_PATHS = ["knowledge-base/marketing/campaign-calendar.md", "knowledge-base/marketing/content-strategy.md"]`; wire step 4.5 `safe-commit-pr` gated `heartbeatOk && !spawnResult.abortedByTimeout`; commitMessage "ci: update campaign calendar and content-strategy review"
- [x] 2.3 `cron-growth-audit.ts`: remove block (:101-111) + ref (:76); `GROWTH_AUDIT_ALLOWED_PATHS = ["knowledge-base/marketing/audits/soleur-ai/", "knowledge-base/product/roadmap.md"]`; commitMessage "docs: weekly growth audit"
- [x] 2.4 `cron-community-monitor.ts`: remove instruction 5 "Persist via PR" (:185-203) + preamble ref (:137); renumber instruction 6→5; `COMMUNITY_MONITOR_ALLOWED_PATHS = ["knowledge-base/support/community/"]`; commitMessage "docs: daily community digest"
- [x] 2.5 `cron-competitive-analysis.ts`: remove block (:136-153) + ref (:127); `COMPETITIVE_ANALYSIS_ALLOWED_PATHS = [competitive-intelligence.md, marketing/content-strategy.md, product/pricing-strategy.md, sales/battlecards/, marketing/seo-refresh-queue.md]` (cascade-table audit, comment cites the agent's Cascade Delegation Table + CASCADE LIMIT-4); commitMessage "docs: update competitive intelligence report"

## Phase 3 — 5 legacy handler-side pipelines (live; per-cron config table in plan Phase 3)

- [ ] 3.1 Update each cron's test file RED: mocked-`safeCommitAndPr` config-shape assertions replace spawn-argv git assertions; non-persistence coverage untouched (check `cron-compound-promote-graymatter.test.ts` for pipeline coupling)
- [ ] 3.2 `cron-weekly-analytics.ts`: replace create-bot-pr staging→merge internals with safeCommitAndPr (allowedPaths `["knowledge-base/marketing/analytics/"]`, syntheticChecks, mergeMode "direct", prBody preserved); keep PLAUSIBLE gate, cascade dispatch, Discord notify; delete unused spawnGitChecked/spawnGitCapture
- [ ] 3.3 `cron-content-publisher.ts`: allowedPaths `["knowledge-base/marketing/distribution-content/"]` (trailing slash ADDED), prBody preserved, syntheticChecks, mergeMode "direct"
- [ ] 3.4 `cron-content-vendor-drift.ts`: allowedPaths from SKILL_PREFIX (`NOTICE` + `references/`), prBody runbook-pointer preserved, prLabels detectResult.labels, syntheticChecks, mergeMode "direct"
- [ ] 3.5 `cron-rule-prune.ts`: allowedPaths `["scripts/retired-rule-ids.txt"]`, prTitle dynamic (`${pruneResult.prTitle} ${date}`), syntheticChecks, mergeMode "direct"
- [ ] 3.6 `cron-compound-promote.ts`: per-cluster safeCommitAndPr (branchName `self-healing/auto-<hash>-<date>`, allowedPaths [target_path, promotion-log.md], commitMessage titleLine, commitBody trailer, prTitle/prBody preserved, prDraft true, prLabels ["self-healing/auto"], syntheticChecks, mergeMode "none"); keep all cluster guards + checkout-main caller-side

## Phase 4 — Parity test restructure

- [x] 4.1 `cron-safe-commit-parity.test.ts`: split `MIGRATED` → `MIGRATED_PROMPT` (7: seo-aeo-audit, content-generator, growth-execution, campaign-calendar, growth-audit, community-monitor, competitive-analysis) and `MIGRATED_HANDLER` (5: weekly-analytics, compound-promote, content-publisher, content-vendor-drift, rule-prune); EXEMPT = exactly {roadmap-review, bug-fixer}; invariant 2 full assertions on PROMPT cohort, import+call+no-spawnGitChecked on HANDLER cohort; invariants 1/3/4 over the union

## Phase 5 — ADR

- [x] 5.1 Create `knowledge-base/engineering/architecture/decisions/ADR-054-safe-commit-and-pr-sole-write-path-for-bot-cron-prs.md` per architecture-skill template (content contract in plan Phase 5: lineage ADR-033, three merge modes, two permanent exemptions, parity test enforcement, Tier-2 restoration constraint, watchdog tracking-issue link)

## Phase 6 — Decisions, tracking issues, hygiene

- [x] 6.1 File tracking issue: stale `ci/*` bot-PR watchdog (gates Tier-2 restoration; labels type/chore, domain/engineering, priority/p3-low; milestone "Post-MVP / Later")
- [x] 6.2 File tracking issue: tri-state output-verify gate; update stale "#5111 consolidation" comment in cron-seo-aeo-audit.ts (:279-281) — verified sole site at deepen time
- [x] 6.3 Runbook `cloud-scheduled-tasks.md` §"PR Withheld by safe-commit": 12 callers, three merge modes, stage auto-merge covers direct-merge failures, vendor-drift deletion-guard expectation

## Phase 7 — Verification (ACs in plan)

- [ ] 7.1 AC1-AC2 greps (no spawnGitChecked, no MANDATORY FINAL STEP in functions/)
- [ ] 7.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/` green
- [ ] 7.3 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` green
- [ ] 7.4 PR body: Closes #5111 + documented behavior changes (branch-name cosmetics, campaign-calendar title wording, competitive-analysis allowedPaths widening)
- [ ] 7.5 Post-merge: `/soleur:trigger-cron` cron-rule-prune + `gh pr list --search "head:ci/"` / Sentry safe-commit-failed-empty verdict
