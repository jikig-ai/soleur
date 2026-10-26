# Tasks: feat-one-shot-10550-wikiskill-phase-2-new-skill-creation

Plan: `knowledge-base/project/plans/2026-10-26-feat-wikiskill-phase-2-gated-new-skill-creation-plan.md`
Issue: #10550 (`Ref` only). Do not touch or comment on #10551, #10552, #8443. Do not start Phase 3.

## Phase 0 - Preconditions (no commit)

- 0.1 Rebase on `origin/main`; re-measure total, cap, headroom; record the numbers in the PR body
- 0.2 If a sibling merged a new skill, re-derive the trim set against the new total
- 0.3 Prove the runner image has bash, jq, sha256sum, awk, sed, grep, find, mktemp, tr, timeout
- 0.4 Confirm vitest in `apps/web-platform` resolves `plugins/soleur/scripts/sync-cursor-name-map.ts` and `yaml`
- 0.5 Find how the existing `input: patterns` model call is bounded; bind `create-propose` to it; check the manual-fire throttle
- 0.7 Runner-image command output: tool set and whether the unmodified Cursor generator runs (decides CTO G3); `trigger-cron` allowlist passes `allow_create`; enumerate holders of the internal trigger secret (flag-in-this-PR if non-operator); bun in the vitest job; orphan-suite and affected-suite registration
- 0.6 Measure index + skill list against the 12k-token ceiling; calibrate `OVERLAP_REFUSE_THRESHOLD` on the two evidence fixtures and four synthetic negatives

## Phase 1 - Free the budget (commit 1)

- 1.1 Apply the five description trims verbatim from the plan table
- 1.2 Run `bun plugins/soleur/scripts/sync-cursor-name-map.ts`; commit the five regenerated stubs
- 1.3 Lower `SKILL_DESCRIPTION_WORD_BUDGET` to the pre-trim measured total; extend its history comment
- 1.4 Run components and cursor-name-map tests; assert headroom >= 30
- 1.5 Bump `BASELINE_DECLARED_PROBES` (re-read at work time; the plan's `credentials_required` moves it)

## Phase 2 - Contracts (commit 2)

- 2.1 ADR-092 create-only amendment; ADR-300 addendum (wording-pinned)
- 2.2 `plugins/soleur/skills/skill-creator/templates/purpose.md` and `plugins/soleur/test/purpose-template.test.ts`
- 2.3 Dated conditional legal notes (PA-31, DPIA addendum, compliance-posture); run `soleur:gdpr-gate`
- 2.4 Runbook scaffolding rows

## Phase 3 - Pure module (commit 3; RED then GREEN)

- 3.1 Write Guard 1-4 mutation rows as failing tests first
- 3.2 `compound-promote-create.ts`: schema, shape allowlist, claim words, PII/credential, slug, overlap rank, word counter, cap reader, renderers, `checkCreate`
- 3.3 Parity tests: stub over every skill, Grok md5, counter vs real tree

## Phase 4 - Spawn gates (commit 4; RED then GREEN)

- 4.1 `compound-promote-create-gates.ts`: shared scrubbed-env `spawnRepoScript`, `runSkillScan` (offline env), `syncReadmeCounts`, content collector; exclude `skill-security-scan PR gate` and `test` from synthetic checks
- 4.2 Gate tests: HIGH-RISK, REVIEW, empty, non-zero, timeout, missing tool, LOW-RISK

## Phase 5 - Handler wiring (commit 5)

- 5.1 `readRunOptions` `allow_create` (manual + patterns only; return type grows); Step A `create-propose` (memoized, never throws), Step B `create-persist` (one step), edit loop first, `create-open` and `week-cap` checks
- 5.2 `exactPaths` + `expectedContent` persistence; PR body `CREATE (new skill)` + fixed checklist
- 5.3 Marker fields `kind`, `create_requested`, `create_arm` (only when ran), `create_outcome`, reason `create-refused` with `class`; one Sentry op
- 5.4 `scanOpenPrSkillPaths` create variant; update the ~L480 comment
- 5.5 Census, marker, allowlist, invariance and dry-render tests

## Phase 6 - Registration (commit 6)

- 6.1 Runbook and `betterstack-log-query.md` rows
- 6.2 Re-verify suite registration with `lint-orphan-test-suites.sh` and the affected-suite census
- 6.3 `c4-count-parity`, `sync-readme-counts --check`, `lint-skill-body-budget`, guard-contract lint

## Phase 7 - Trackers, ship, verify

- 7.1 File the single deferral issue: live-fire (operator-held ACTION with preconditions)
- 7.2 PR body `Ref #10550`; list the five regenerated stub paths
- 7.3 Merge (one `gh pr merge` per call); `deploy-arm.sh find --wait`; served `build_sha` equals merge SHA
- 7.4 `soleur:postmerge` must print `postmerge verification complete!`
