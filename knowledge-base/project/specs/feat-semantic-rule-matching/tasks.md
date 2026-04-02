# Tasks: Jaccard Rule Duplication Detection

**Feature:** feat-semantic-rule-matching
**Plan:** `knowledge-base/project/plans/2026-03-30-feat-jaccard-rule-duplication-detection-plan.md`
**Issue:** #1304

## Phase 1: Tests (TDD — write failing tests first)

### 1.1 Write `scripts/test-jaccard-duplicates.sh`

- [ ] Create test harness with temp directory setup/teardown
- [ ] Test: known duplicate pair ("Never commit directly to main" vs "Do not commit to main branch") produces Jaccard >= 0.6
- [ ] Test: unrelated pair produces Jaccard < 0.6 (true negative)
- [ ] Test: rule with colons in text ("Priority chain: (1) MCP tools") is parsed correctly without truncation

### 1.2 Verify tests fail (RED phase)

- [ ] Run `bash scripts/test-jaccard-duplicates.sh` — all tests should fail (function doesn't exist yet)

## Phase 2: Implementation

### 2.1 Add `detect_duplicates()` function to `rule-audit.sh`

- [ ] Extract `^-` lines from AGENTS.md and constitution.md with `grep -Hn`
- [ ] Preprocess to TAB-delimited format with relativized paths
- [ ] Tokenize: lowercase, strip punctuation, remove stopwords (~20 words — articles, prepositions, pronouns, conjunctions; NOT modals)
- [ ] Skip rules with < 4 content words after filtering
- [ ] Compute pairwise Jaccard via `comm -12` on sorted word lists
- [ ] Collect pairs with score >= 0.6, sorted by score descending
- [ ] Format as markdown table: Score, File A, Line, File B, Line, Rule A (truncated), Rule B (truncated)
- [ ] Handle `grep` exit code under `set -euo pipefail` (append `|| true`)

### 2.2 Add Phase 2.5 to `rule-audit.sh`

- [ ] Insert after Phase 2 (line ~106), before Phase 3 (line ~108)
- [ ] Call `detect_duplicates`
- [ ] Insert "Suspected Duplicates" section into issue body (after broken hooks, before Tier Model)
- [ ] Add duplicate count to budget summary stats
- [ ] Ensure dry-run mode (no `GH_TOKEN`) prints table to stdout

### 2.3 Verify tests pass (GREEN phase)

- [ ] Run `bash scripts/test-jaccard-duplicates.sh` — all tests pass
- [ ] Manual dry-run: `bash scripts/rule-audit.sh` with no `GH_TOKEN`
- [ ] Verify output contains plausible duplicate pairs

## Phase 3: Ship

### 3.1 Final checks

- [ ] `npx markdownlint-cli2 --fix` on changed `.md` files
- [ ] `shellcheck scripts/rule-audit.sh scripts/test-jaccard-duplicates.sh`
- [ ] Run `/soleur:compound`
- [ ] Run `/soleur:ship`
