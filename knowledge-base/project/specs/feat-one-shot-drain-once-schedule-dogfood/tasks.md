# Tasks: Drain `--once` / dogfood-schedule scope-out backlog (#3403 + #3404 + #3407)

Plan: `knowledge-base/project/plans/2026-05-07-feat-drain-once-schedule-dogfood-backlog-plan.md`

## Phase 0 — Preflight setup

- 0.1 Create sandbox tracking issue `[Sandbox] Verify D4 abort-path neutralization with show_full_output (Ref #3403)` via `gh issue create --label deferred-scope-out`. Capture `<SANDBOX_ISSUE_NUMBER>`.
- 0.2 Post task-spec comment on sandbox issue. Capture `<SANDBOX_COMMENT_ID>`, `<EXPECTED_AUTHOR>`, `<EXPECTED_CREATED_AT>`.
- 0.3 Verify `git rev-parse --abbrev-ref HEAD` is `feat-one-shot-drain-once-schedule-dogfood`. Verify `claude-code-action@v1` and `actions/checkout@v4` SHAs match what `plugins/soleur/skills/schedule/SKILL.md` Step 3b currently references.

## Phase 1 — TDD: Write failing tests (RED)

- 1.1 Create `plugins/soleur/test/fixtures/auto-close-scanner/checkbox-trigger.txt` containing `- [ ] Post-merge: close #3185 with a final comment.`.
- 1.2 Create `plugins/soleur/test/fixtures/auto-close-scanner/prose-trigger.txt` containing `This will fix #1234 once the upstream PR lands.`.
- 1.3 Create `plugins/soleur/test/fixtures/auto-close-scanner/safe-ref.txt` with `Ref #999`, bare `Closes`, and the word `Closes-style` (none should trigger).
- 1.4 Create `plugins/soleur/test/auto-close-scanner.test.sh` asserting expected match counts (1, 1, 0) per fixture; include a case-insensitive uppercase fixture and a `GH-N` fixture.
- 1.5 Append two `assert_contains` blocks to `plugins/soleur/test/schedule-skill-once.test.sh` checking `show_full_output: true` and `Post-fire verification` are inside the `--once` template.
- 1.6 Run all tests; confirm RED (auto-close-scan.sh missing; new schedule assertions failing).

## Phase 2 — Implement (GREEN)

- 2.1 Create `plugins/soleur/skills/ship/scripts/auto-close-scan.sh` (10-line `grep -niE` helper, fail-soft).
- 2.2 Edit `plugins/soleur/skills/schedule/SKILL.md` Step 3b template:
  - 2.2a Add `show_full_output: true` to the `with:` block of the `claude-code-action@v1` step.
  - 2.2b Add a new section `## Post-fire verification (mandatory after Final step)` to the prompt body containing the contents-API verification recipe + follow-up-comment-on-failure logic.
  - 2.2c Add a paragraph to the long permissions-comment block warning operators not to flip `show_full_output: false` unless they hand-inject `secrets.*` into the prompt body.
  - 2.2d Update Known Limitations: extend `--once D3 + D4-failure` bullet with #3403 reference and AC2 banner about pre-PR `--once` schedules being not-self-cleaning.
- 2.3 Edit `plugins/soleur/skills/schedule/SKILL.md` Step 3a template: add `show_full_output: true` to recurring template's `with:` block.
- 2.4 Create `.github/workflows/pr-auto-close-scanner.yml` triggering on `pull_request: opened, edited`. Calls `auto-close-scan.sh` against title and body. Emits `::warning::` and idempotent `gh pr comment`. Honors `<!-- auto-close-scanner: confirm -->` opt-out marker.
- 2.5 Edit `plugins/soleur/skills/ship/SKILL.md` Phase 6: insert pre-creation scanner call before the existing `gh pr create` invocation. Surface matches via `AskUserQuestion` (interactive) or `WARNING:` log (`HEADLESS_MODE=true`).
- 2.6 Edit `AGENTS.md` rule `wg-use-closes-n-in-pr-body-not-title-to`: generalize wording per AC7. Verify final byte length < 600 via `awk '/wg-use-closes-n-in-pr-body-not-title-to/ {print length($0)}' AGENTS.md`.
- 2.7 Generate `.github/workflows/scheduled-dogfood-3403.yml` using the now-fixed `--once` template. Substitute sandbox issue/comment/author/created_at from Phase 0. FIRE_DATE = today + 5 days minimum. Append a sandbox-only `gh issue close` step BEFORE the `claude-code-action` step to force the abort path.

## Phase 3 — Verify GREEN

- 3.1 Run `bash plugins/soleur/test/auto-close-scanner.test.sh`; expect all assertions pass.
- 3.2 Run `bash plugins/soleur/test/schedule-skill-once.test.sh`; expect all assertions pass.
- 3.3 YAML-validate `.github/workflows/pr-auto-close-scanner.yml` via `python3 -c "import yaml; yaml.safe_load(open('...'))"`.
- 3.4 YAML-validate `.github/workflows/scheduled-dogfood-3403.yml` via the same.
- 3.5 Verify AGENTS.md rule byte length < 600.
- 3.6 Run `lefthook run pre-commit` to catch retired-rule-id and other lint gates.

## Phase 4 — Pre-merge gates

- 4.1 Self-scan THIS PR: `bash plugins/soleur/skills/ship/scripts/auto-close-scan.sh <(gh pr view --json title -q .title) <(gh pr view --json body -q .body)`. Expect exactly 3 matches (`Closes #3403`, `Closes #3404`, `Closes #3407`).
- 4.2 Verify PR body contains all three `Closes #N` lines on their own lines, no qualifiers.
- 4.3 Verify PR title does NOT contain any auto-close-keyword + #N pattern.
- 4.4 If sandbox dogfood has already fired pre-merge (rare; FIRE_DATE > merge target by design), apply Phase 4.2 split contract from the plan.

## Phase 5 — Post-merge (operator)

- 5.1 On FIRE_DATE, manually trigger `gh workflow run scheduled-dogfood-3403.yml` (per `wg-after-merging-a-pr-that-adds-or-modifies`).
- 5.2 Capture full SDK transcript (visible due to `show_full_output: true`).
- 5.3 Identify denied tool call; categorize as Branch A (template-fixable) or Branch B (architectural App-token gap).
- 5.4 Branch A: close #3403 with forensic comment. Branch B: file `#3403-followup` with the architectural finding; reopen #3403 if auto-closed by PR body; post forensic comment to #3403.
- 5.5 Migration sweep: `gh workflow list --all | grep 'Scheduled (once):'`; for each `--once` workflow with a live `schedule:` trigger, post a migration notice on its tracking issue per AC15.

## Phase 6 — Compound + ship

- 6.1 Run `skill: soleur:compound` to capture session learnings into `knowledge-base/project/learnings/2026-05-07-once-schedule-dogfood-drain-and-auto-close-scanner.md`.
- 6.2 Run `skill: soleur:ship` to mark PR ready, set semver label (`semver:patch` — bug fix + small additions), trigger merge.
- 6.3 After merge, verify `version-bump-and-release.yml` succeeds (per `wg-after-a-pr-merges-to-main-verify-all`).

## Acceptance gate map

| AC | Phase/Task |
|---|---|
| AC1 (template `show_full_output`) | 2.2a, 2.3 |
| AC2 (not-self-cleaning banner) | 2.2d |
| AC3 (side-effect verification) | 2.2b |
| AC4 (sandbox workflow) | 0.1, 0.2, 2.7 |
| AC5 (CI scanner workflow) | 2.4 |
| AC6 (ship-skill scan parity) | 2.5 |
| AC7 (AGENTS.md rule) | 2.6 |
| AC8 (test fixtures) | 1.1, 1.2, 1.3 |
| AC9 (test runner) | 1.4 |
| AC10 (schedule test extension) | 1.5 |
| AC11 (tasks.md) | This file |
| AC12 (PR body Closes lines) | 4.2 |
| AC13 (self-scan) | 4.1 |
| AC14 (sandbox fire) | 5.1, 5.2, 5.3, 5.4 |
| AC15 (migration sweep) | 5.5 |
