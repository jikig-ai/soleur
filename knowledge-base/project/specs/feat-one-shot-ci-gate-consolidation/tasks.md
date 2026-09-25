# Tasks: ci(workflows) consolidate five single-job PR gates into pr-quality-guards.yml

Plan: `knowledge-base/project/plans/2026-09-25-feat-ci-gate-consolidation-plan.md`
PR: #8902 (draft) · Branch: `feat-one-shot-ci-gate-consolidation`

Invariant checks before starting:

- `gh api repos/jikig-ai/soleur/rulesets/14145388` — snapshot the 24 contexts
  (must be identical after; contexts are job `name:`/id, not workflow names).
- Check open PR #8878 status — it touches `skill-security-scan-pr-trailer.yml`.
  If merged since planning, port its diff into the folded job.

## Phase 1: Fold the five jobs into pr-quality-guards.yml (ONE commit)

- [ ] 1.1 Append `dependency-review:` job verbatim (id + steps, incl. in-job
      `id: detect` and both event-branched action steps). ADD job-level
      `permissions: {contents: read, pull-requests: write}`. NO job `if:`.
- [ ] 1.2 Append `enforce:` job verbatim (job id is the required context —
      no `name:`). NO job `if:`; merge_group base-sha logic untouched.
- [ ] 1.3 Append skill-scan job as id `skill-security-scan` (was `scan` —
      collides with scanner's id). Keep `name: skill-security-scan PR gate`
      byte-identical. NO job `if:`.
- [ ] 1.4 Append `constraint-gates:` job (name `L1 import-boundary gate`)
      with `if: github.event_name == 'pull_request'` added. Carry a condensed
      version of its dogfood/monorepo header comment.
- [ ] 1.5 Append scanner job as id `auto-close-scan` (was `scan`) with
      `if: github.event_name == 'pull_request'` and job-level
      `permissions: {contents: read, pull-requests: write}`.
- [ ] 1.6 Delete `.github/workflows/{dependency-review,legal-doc-cross-document-gate,skill-security-scan-pr-trailer,constraint-gates,pr-auto-close-scanner}.yml`.
- [ ] 1.7 Verify merged file: workflow `on:`/`permissions:`/`concurrency:`
      unchanged; `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/pr-quality-guards.yml'))"` parses; folded step bodies byte-identical to sources.

## Phase 2: Ledger + enumerating tests/lints

- [ ] 2.1 `scripts/pr-fanout-ledger.txt`: delete the five rows; raise
      `pr-quality-guards.yml` jobs 11→16 with a consequence sentence naming
      the fold (ceiling raise requires the named consequence).
- [ ] 2.2 `plugins/soleur/test/ci-path-gating.test.sh`: retarget `DEP=` to
      `pr-quality-guards.yml`; confirm A1/A3/A5/A6 assertions still hold
      against the merged file (adjust extraction if they assumed a
      single-job file).
- [ ] 2.3 `scripts/skill-security-scan-step-body.test.sh`: retarget `WF_PR`;
      adjust extraction if it assumed a dedicated file.
- [ ] 2.4 `scripts/lint-bot-synthetic-statuses.sh` +
      `scripts/lint-bot-synthetic-completeness.sh`: rename the basename
      exemption to `pr-quality-guards.yml` (update the comment to say the
      skill-scan step body moved into it).
- [ ] 2.5 `plugins/soleur/test/lint-bot-synthetic-{statuses,completeness}.test.sh`:
      rename fixture basenames (Tests 9/10, (e)) to `pr-quality-guards.yml` /
      `evil-pr-quality-guards.yml`.
- [ ] 2.6 `scripts/audit-bot-codeql-coverage.sh` ~L85: skip pattern →
      `*pr-quality-guards*`.
- [ ] 2.7 `scripts/lib/test-affected-paths.sh`: repoint edges
      (~L668–721 for skill-scan/dep-review, ~L918 constraint-gates) at
      `pr-quality-guards.yml`; add edges so editing the merged file also
      triggers `ci-path-gating.test.sh` + `parity.test.sh`.
- [ ] 2.8 `plugins/soleur/skills/constraint-scaffold/test/parity.test.sh`:
      replace the `ROOT_BODY` file read with a `yaml.safe_load` extraction of
      `jobs.constraint-gates` from `pr-quality-guards.yml`, compared to the
      template's jobs subtree modulo `__TARGET_DIR__`.
- [ ] 2.9 Run: `pr-fanout-ledger.test.sh`, `ci-path-gating.test.sh`,
      `skill-security-scan-step-body.test.sh`,
      `lint-bot-synthetic-*.test.sh`, `parity.test.sh` — all green.

## Phase 3: Reference sweep + ship

- [ ] 3.1 Update load-bearing filename mentions:
      `skill-security-scan/references/override-mechanism.md` L134,
      `ship/SKILL.md`, `constraint-scaffold/SKILL.md` + test comments,
      `lint-workflow-install-sites.sh` L17, `lint-workflow-issue-write-scope.py`
      L88, `grok-pre-push-gate.sh` L13, `runbooks/lint-bot-statuses.md`,
      ADR-071/ADR-216 operational mentions. Leave historical spec/tasks files.
- [ ] 3.2 Final guard: `rg -l
      'dependency-review\.yml|legal-doc-cross-document-gate\.yml|skill-security-scan-pr-trailer\.yml|constraint-gates\.yml|pr-auto-close-scanner\.yml'`
      — every remaining hit annotated historical or updated.
- [ ] 3.3 `git diff origin/main -- .github/workflows/` = five deletions +
      one modification only. No `infra/github/` diff.
- [ ] 3.4 Dogfood on this PR: confirm `dependency-review`, `enforce`,
      `skill-security-scan PR gate` contexts report from the
      `pr-quality-guards.yml` run (pull_request workflows execute from the
      merge ref, so this PR exercises the merge).
- [ ] 3.5 PR body: `## Changelog`, the before/after fan-out table
      (23→18/push, 4→1/merge_group, 2→1/edited), the rejected-merge list with
      one-line reasons, and a note that no ruleset/TF change was needed.
