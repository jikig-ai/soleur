# Tasks: Content-Vendoring Pin Policy (#3517)

Plan: `knowledge-base/project/plans/2026-05-10-feat-content-vendoring-pin-policy-plan.md`
Scope-outs: #3526, #3527, #3528, #3529

## Phase 0: Setup

- [ ] 0.1 (operator) Create 6 GH labels in a separate terminal: `compliance/critical`, `vendor/pin-drift`, `vendor/license-changed`, `vendor/upstream-archived`, `vendor/upstream-rollback`, `vendor/cron-failure`. Workflow's `Ensure labels exist` step idempotently re-creates them on first run, so this is belt-and-suspenders for pre-merge testing.
- [x] 0.2 Add YAML frontmatter to `plugins/soleur/skills/gdpr-gate/NOTICE` (upstream, pinned-commit, last-verified=2026-05-10, registry path, lifted-files array of 5 entries)
- [x] 0.3 Append body sentence to NOTICE: "The frontmatter above is the canonical machine-readable form; the table below is the human-readable form. Drift between them is a bug."

## Phase 1: Helper scripts (TDD — write tests first per `cq-write-failing-tests-before`)

- [x] 1.1 Write failing test `plugins/soleur/test/notice-frontmatter.test.sh` — happy / missing-frontmatter / malformed-YAML / future-date / p95 <50ms
- [x] 1.2 Implement `plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh` with subcommands: `field <name>`, `days-stale`, `lifted-files`. Future-date and parse-failure return `999`.
- [x] 1.3 Confirm 1.1 tests pass (RED→GREEN)
- [x] 1.4 Write failing test `plugins/soleur/test/vendor-pin-integrity.test.sh` — SHA mismatch fixture + lefthook-glob⊇NOTICE-paths parity assertion (AC5b)
- [x] 1.5 Implement `plugins/soleur/skills/gdpr-gate/scripts/vendor-pin-integrity.sh` using `git hash-object --no-filters`
- [x] 1.6 Confirm 1.4 tests pass
- [x] 1.7 Write failing test `plugins/soleur/test/vendor-drift-classify.test.sh` covering all 7 exit codes (0/10/11/12/13/15/16)
- [x] 1.8 Implement `plugins/soleur/skills/gdpr-gate/scripts/vendor-drift-classify.sh` with regex set + `git merge-base --is-ancestor` rollback check
- [x] 1.9 Confirm 1.7 tests pass

## Phase 2: Drift workflow

- [x] 2.1 Write failing integration test `plugins/soleur/test/vendor-drift-workflow.test.sh` (`SKIP_PR_CREATE=1` dry-run mode)
- [x] 2.2 Author `.github/workflows/scheduled-content-vendor-drift.yml` modeled on `scheduled-skill-freshness.yml` with header trap dossier
  - [x] 2.2.1 `on.schedule.cron: '17 11 * * MON'` + `workflow_dispatch`
  - [x] 2.2.2 `concurrency` group; minimal `permissions:` with inline justification per role
  - [x] 2.2.3 `actions/checkout` pinned to 40-char SHA with `# v4.3.1` comment
  - [x] 2.2.4 `Ensure labels exist` step idempotently re-creates 6 labels
  - [x] 2.2.5 `CAP_PER_RUN: '3'` + idempotent issue search by title
  - [x] 2.2.6 Drift-detection step: `gh api ...contents/<path>?ref=main`; on 404, `gh api repos/<o>/<r>` to disambiguate rename/archived/deleted
  - [x] 2.2.7 Inline 3-way merge: `git merge-file --diff3` per lifted file; conflict-marker grep gate
  - [x] 2.2.8 NOTICE bump step: update `pinned-commit`, `blob-sha[]`, `last-verified` to today's date in same commit
  - [x] 2.2.9 `bot-pr-with-synthetic-checks` composite invoked with all 7 documented inputs
  - [x] 2.2.10 Label-apply per classifier exit code
  - [x] 2.2.11 `if: failure()` step opens `vendor/cron-failure` issue (idempotent search)
- [x] 2.3 Confirm 2.1 tests pass

## Phase 3: Lefthook integrity gate

- [x] 3.1 Add `vendor-pin-integrity` stanza to `lefthook.yml` directly after `gdpr-gate-advisory` (priority: 6, path-array glob, `run: bash plugins/soleur/skills/gdpr-gate/scripts/vendor-pin-integrity.sh {staged_files}`)
- [x] 3.2 Manual smoke test: stage a single-byte modification to `references/leakage-vectors.md`; `git commit` fails with integrity script's stderr; revert

## Phase 4: Runtime staleness check

- [x] 4.1 Extend `plugins/soleur/test/gdpr-gate.test.ts` (vitest) with mocked-stale cases: 35d (banner only), 95d (banner + POSTURE_FAIL), parser-deleted (days_stale=999 → banner). Assertions read captured **stdout** (not stderr) per AC6d.
- [x] 4.2 Insert ~10-line runtime staleness check into `plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh` after INCIDENTS_LIB block, before CANONICAL_REGEX. Subshell-exec parser; banner + POSTURE_FAIL to **stdout**; gate exits 0 in all paths.
- [x] 4.3 Confirm 4.1 tests pass
- [x] 4.4 Update `plugins/soleur/skills/gdpr-gate/SKILL.md` to document the staleness banner contract; cross-link to policy doc

## Phase 5: Compliance-posture + policy doc

- [x] 5.1 Add "Vendored Code Provenance" section to `knowledge-base/legal/compliance-posture.md` (between "Vendor DPA Status" and "Active Compliance Items"); add gosprinto row
- [x] 5.2 Author `knowledge-base/engineering/policies/content-vendoring.md` with 9 sections (Scope, NOTICE schema, Lifting procedure, Drift detection, Severity classification, Re-vendor procedure, Runtime staleness contract, POSTURE_FAIL operator chain, Registry)
- [x] 5.3 Add cross-links: NOTICE → policy doc; policy doc → compliance-posture.md; gdpr-gate SKILL.md → policy doc

## Phase 6: Operator runbook

- [x] 6.1 Author `knowledge-base/engineering/ops/runbooks/vendor-pin-drift-resolution.md` with 6 sections: synthetic-drift test, conflict-marker resolution, rollback case, rename case, archived case, cron-failure case, POSTURE_FAIL operator chain (cross-link to policy doc)
- [x] 6.2 Cross-link runbook from policy doc and `compliance-posture.md`

## Phase 7: Test fixtures

- [x] 7.1 Author `plugins/soleur/test/fixtures/vendor-drift/upstream-fields-art9-add.diff` (security-relevant; classifier exit 10)
- [x] 7.2 Author `plugins/soleur/test/fixtures/vendor-drift/upstream-prose-typo.diff` (batched; classifier exit 13)
- [x] 7.3 Author `plugins/soleur/test/fixtures/vendor-drift/upstream-rollback.diff` (rollback; classifier exit 15)
- [x] 7.4 Author `plugins/soleur/test/fixtures/vendor-drift/notice-future-dated.frontmatter` (future-dated NOTICE; parser returns 999)

## Phase 8: Final verification + PR

- [x] 8.1 Run full test suite: `bash plugins/soleur/test/notice-frontmatter.test.sh && bash plugins/soleur/test/vendor-pin-integrity.test.sh && bash plugins/soleur/test/vendor-drift-classify.test.sh && bash plugins/soleur/test/vendor-drift-workflow.test.sh`
- [x] 8.2 Run TS test: `cd plugins/soleur && bun test test/gdpr-gate.test.ts`
- [x] 8.3 Manual lefthook smoke test (Phase 3.2)
- [x] 8.4 `/soleur:gdpr-gate` Phase 2 exit invocation against the diff (recursive but valid per spec TR9)
- [ ] 8.5 (ship) PR body audit: every checkbox uses `Ref #3517` form; only one `Closes #3517` line outside checkboxes (AC11)
- [ ] 8.6 (ship) PR body has `## Changelog` section
- [ ] 8.7 (ship) Apply `compliance/critical` label to PR (single-user incident threshold)
- [ ] 8.8 (ship) Trigger plan-review round 2 if any Phase 1-7 changes diverged from the post-round-1 plan
- [ ] 8.9 (ship) Run `/soleur:review` for multi-agent code review

## Phase 9: Post-merge (operator)

- [ ] 9.1 (post-merge) Operator runs `gh workflow run scheduled-content-vendor-drift.yml --ref main`; polls `gh run view <id>` until SUCCESS (AC12 — `wg-after-merging-a-pr-that-adds-or-modifies`)
- [ ] 9.2 (post-merge) Operator confirms 6 labels exist (workflow re-creates idempotently)
- [ ] 9.3 (post-merge) Operator runs synthetic-drift test per runbook §1 (AC13): branch with mutated NOTICE pinned-commit; dispatches workflow; asserts auto-PR with `vendor/pin-drift` label and bumped `last-verified`
