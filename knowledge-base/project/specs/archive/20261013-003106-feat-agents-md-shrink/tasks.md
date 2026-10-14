# Tasks: feat-agents-md-shrink

**Plan:** `knowledge-base/project/plans/2026-04-23-chore-agents-md-shrink-via-allowlist-plan.md`
**Spec:** `knowledge-base/project/specs/feat-agents-md-shrink/spec.md`
**Brainstorm:** `knowledge-base/project/brainstorms/2026-04-23-agents-md-budget-revisit-brainstorm.md`
**Issue:** #2865 (Closes #2762)
**Draft PR:** #2862

## Phase 0: Spec Reconciliation

- [ ] 0.1 Edit `knowledge-base/project/specs/feat-agents-md-shrink/spec.md` FR4: replace "Target: ≤ 32,000 bytes" with "Target: ≤ 37,000 bytes" + TR5 advisory note.
- [ ] 0.2 Commit: `docs(spec): adjust FR4 target 32k→37k per TR5 advisory`.

## Phase 1: Mechanism (allowlist + amendments + compound sync)

### 1.1 RED — Failing tests

- [ ] 1.1.1 Extend `tests/scripts/test_lint_rule_ids.py` with `test_retired_id_passes_when_in_allowlist`.
- [ ] 1.1.2 Add `test_missing_retired_file_backward_compat`.
- [ ] 1.1.3 Add `test_reintroduced_retired_id_fails`.
- [ ] 1.1.4 Update `_run()` helper to accept `--retired-file` arg (or add a new `_run_with_retired()` helper).
- [ ] 1.1.5 Run `python3 -m unittest tests.scripts.test_lint_rule_ids` — all 3 new tests FAIL (RED).
- [ ] 1.1.6 Commit: `test(lint-rule-ids): RED for retired-ids allowlist`.

### 1.2 GREEN — Linter amendment

- [ ] 1.2.1 Add `--retired-file <path>` CLI flag to `scripts/lint-rule-ids.py` (via argparse or sys.argv split).
- [ ] 1.2.2 Parse allowlist file: read lines, skip comments + blanks, extract `id` from `id | date | pr | breadcrumb`.
- [ ] 1.2.3 Compute `reintroduced = retired_ids & current_ids`; append error if non-empty.
- [ ] 1.2.4 Modify removed-id check: `removed = head_ids - current_ids - retired_ids`.
- [ ] 1.2.5 Update error message to cite `scripts/retired-rule-ids.txt` as the retirement mechanism.
- [ ] 1.2.6 Run `python3 -m unittest tests.scripts.test_lint_rule_ids` — all 8 tests pass (GREEN).
- [ ] 1.2.7 Commit: `fix(lint-rule-ids): GREEN — parse retired-ids allowlist via --retired-file`.

### 1.3 Create allowlist file (header only)

- [ ] 1.3.1 Create `scripts/retired-rule-ids.txt` with header comment block (format, purpose, enforcement reference).
- [ ] 1.3.2 No entries yet — appended during Phase 2.

### 1.4 Amend AGENTS.md rules

- [ ] 1.4.1 Amend `cq-agents-md-why-single-line`: bytes-first target (≤37k warn, 40k hard), keep `<!-- rule-threshold: 115 -->` sentinel, update `**Why:**` citation to #2865.
- [ ] 1.4.2 Amend `wg-every-session-error-must-produce-either`: add "Discoverability exit" clause with definition.
- [ ] 1.4.3 Amend `cq-rule-ids-are-immutable`: add sentence about `scripts/retired-rule-ids.txt` mechanism + reintroduction rejection.
- [ ] 1.4.4 Verify all three amended rules stay ≤ 600 bytes: `grep '^- ' AGENTS.md | awk '{print length, $0}' | sort -rn | head -5`.

### 1.5 Update compound/SKILL.md step 8

- [ ] 1.5.1 Replace step 8 warn messages to use hardcoded `37000` threshold + `40000` critical threshold.
- [ ] 1.5.2 Keep existing `<!-- rule-threshold: 115 -->` sentinel (sync-script unchanged).
- [ ] 1.5.3 Add discoverability-litmus reference to the 37k warn message.

### 1.6 Phase 1 verification

- [ ] 1.6.1 `python3 -m unittest tests.scripts.test_lint_rule_ids` — 8/8 green.
- [ ] 1.6.2 `bash scripts/lint-agents-compound-sync.sh` — green (rule-threshold matches).
- [ ] 1.6.3 `wc -c AGENTS.md` — measure new baseline (should be ~40,800–41,000 bytes; amendment adds ~300–400).
- [ ] 1.6.4 Commit: `docs(agents-md): amend threshold + inflow-litmus + immutability; compound warn to 37k`.

## Phase 2: Delete Pass (judgment + audit trail)

### 2.1 Litmus application procedure

For each of 113 rules, top-to-bottom:

- [ ] 2.1.1 Read rule text + `**Why:**` annotation.
- [ ] 2.1.2 Apply primary question: "Discoverable via clear error, visible diff, or command failure on first attempt?"
- [ ] 2.1.3 If AMBIGUOUS, apply tiebreaker: "Blast-radius class (silent failure, data loss, cross-session waste)?"
- [ ] 2.1.4 Bias toward KEEP when uncertain (TR5).

### 2.2 Execute pre-sample deletes (13 litmus + 3 pointer)

Pre-sample from plan Phase 2.2. Work-phase MAY re-judge per 2.1.

- [ ] 2.2.1 Delete `hr-before-running-git-commands-on-a` (213 bytes) — git errors clearly.
- [ ] 2.2.2 Delete `hr-never-use-sleep-2-seconds-in-foreground` (381 bytes) — tool blocks explicitly.
- [ ] 2.2.3 Delete `cq-always-run-npx-markdownlint-cli2-fix-on` (204 bytes).
- [ ] 2.2.4 Delete `cq-ensure-dependencies-are-installed-at-the` (216 bytes).
- [ ] 2.2.5 Delete `cq-gh-issue-create-milestone-takes-title` (379 bytes).
- [ ] 2.2.6 Delete `cq-gh-issue-label-verify-name` (371 bytes).
- [ ] 2.2.7 Delete `cq-vite-test-files-esm-only` (280 bytes).
- [ ] 2.2.8 Delete `cq-markdownlint-fix-target-specific-paths` (392 bytes).
- [ ] 2.2.9 Delete `cq-when-running-terraform-commands-locally` (285 bytes).
- [ ] 2.2.10 Delete `cq-for-production-debugging-use` (266 bytes).
- [ ] 2.2.11 Delete `wg-use-ship-to-automate-the-full-commit` (144 bytes).
- [ ] 2.2.12 Delete `rf-never-skip-qa-review-before-merging` (158 bytes).
- [ ] 2.2.13 Delete `rf-after-merging-read-files-from-the-merged` (163 bytes).
- [ ] 2.2.14 Pointer-delete `cq-after-completing-a-playwright-task-call` — hook always-invoked.
- [ ] 2.2.15 Pointer-delete `cq-before-calling-mcp-pencil-open-document` — hook always-invoked.
- [ ] 2.2.16 Pointer-delete `wg-when-a-research-sprint-produces` — skill always-invoked.

### 2.3 Re-audit (explicit KEEPs from plan review)

- [ ] 2.3.1 Confirm `hr-mcp-tools-playwright-etc-resolve-paths` KEPT (Playwright errors aren't clean "wrong cwd").
- [ ] 2.3.2 Confirm `hr-always-read-a-file-before-editing-it` KEPT (compaction invariant not discoverable).
- [ ] 2.3.3 Confirm `hr-the-bash-tool-runs-in-a-non-interactive` KEPT (cross-session retry waste).

### 2.4 Populate allowlist + execute deletions

- [ ] 2.4.1 For each rule in 2.2, append entry to `scripts/retired-rule-ids.txt`: `<id> | 2026-04-23 | #2865 | <breadcrumb>`.
- [ ] 2.4.2 Breadcrumb selection: link existing learning file if one exists; else write one-line self-contained rationale (e.g., `"gh rejects invalid labels — agent discovers via clear error"`).
- [ ] 2.4.3 Delete the `- ...` line for each retired rule from AGENTS.md.
- [ ] 2.4.4 Run `python3 scripts/lint-rule-ids.py --retired-file scripts/retired-rule-ids.txt AGENTS.md` — green.

### 2.5 Byte margin gate

- [ ] 2.5.1 `wc -c AGENTS.md` — must be < 37,000.
- [ ] 2.5.2 If margin < 200 bytes (36,800–36,999): identify one additional delete candidate from keep list OR compress one oversized rule.
- [ ] 2.5.3 If >= 37,000: BLOCKING — must resolve before Phase 3. Apply litmus more broadly or compress `hr-never-fake-git-author` (756 → ~500 bytes) as spillover scope.
- [ ] 2.5.4 Commit: `chore(agents-md): delete N rules via discoverability litmus; retire via allowlist`.

### 2.6 PR body audit trail (touched rules only)

- [ ] 2.6.1 Build per-rule decision table with format `| rule-id | action | rationale | breadcrumb |`.
- [ ] 2.6.2 Include ONLY touched rules (deleted + pointer-migrated). Do NOT row untouched rules.
- [ ] 2.6.3 Update PR #2862 body (`gh pr edit 2862 --body-file -` with heredoc).

## Phase 3: Ship

### 3.1 Pre-ship verification

- [ ] 3.1.1 `npx markdownlint-cli2 --fix` on `AGENTS.md`, brainstorm, spec, plan files.
- [ ] 3.1.2 `bash scripts/lint-agents-compound-sync.sh` — green.
- [ ] 3.1.3 `python3 -m unittest tests.scripts.test_lint_rule_ids` — 8/8 green.
- [ ] 3.1.4 `wc -c AGENTS.md` < 37,000 (final gate).
- [ ] 3.1.5 Verify Issue #2762 referenced via `Closes #2762` in PR body.

### 3.2 Ship

- [ ] 3.2.1 `skill: soleur:ship` (runs compound + review + mark ready + auto-merge + polling).

### 3.3 Post-merge operator verification

- [ ] 3.3.1 Open fresh Claude Code session on `main`; confirm `⚠ Large AGENTS.md` warning does NOT fire.
- [ ] 3.3.2 `bash scripts/rule-metrics-aggregate.sh --dry-run` — runs without crash (output still shows `hit_count=0` per #2866; expected).
- [ ] 3.3.3 `bash scripts/rule-prune.sh --dry-run` — runs without crash.
- [ ] 3.3.4 Verify #2762 auto-closed by the merge.
- [ ] 3.3.5 Verify #2865 auto-closed by the merge.

## Exit criteria (all must be true)

- [ ] AGENTS.md < 37,000 bytes
- [ ] All linters green
- [ ] Tests green (8/8)
- [ ] PR body has per-rule audit table
- [ ] Fresh-session warn no longer fires
- [ ] No learning file content destroyed
- [ ] #2762 closed
- [ ] Spec FR4 reflects 37k advisory split
