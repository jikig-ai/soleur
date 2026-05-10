---
feature: feat-token-efficiency-analysis
plan: knowledge-base/project/plans/2026-05-09-feat-token-efficiency-compound-phase-plan.md
spec: knowledge-base/project/specs/feat-token-efficiency-analysis/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-09-token-efficiency-analysis-brainstorm.md
issue: 3494
last_updated: 2026-05-09
---

# Tasks: Token-Efficiency Analysis as Compound Phase 1.6

## Phase 1: Setup & Empirical Verification

- [x] **1.1** Resolve `CLAUDE_SESSION_ID` env var name. Run `env | grep -i session` in a Claude Code session; document the actual variable name. Cross-reference with `skill-invocation-logger.sh:55` (which uses `SESSION_ID` extracted from stdin JSON, not env). If session_id is only available via stdin, the hook implementation extracts it; the Phase 1.6 script reads it differently. Document both paths.
- [x] **1.2** Verify hook input shape for `PostToolUse` on `Task` matcher. Wire a logging-only stub hook that writes raw stdin to `/tmp/task-hook-stdin.json`. Capture two scenarios: (a) flat Task invocation, (b) nested Task (Task spawning Task). Document the verified shape — including `tool_response` field name, `total_tokens`/`tool_uses`/`duration_ms` field paths — in the new hook's header comment.
- [x] **1.3** Cross-reference Claude Code's bundled hook documentation (`claude --help`, docs site, or settings schema) for the documented shape. If any field name differs from the empirical capture, document the divergence in a learning file before writing the production hook.
- [x] **1.4** Confirm `.gitignore` does not currently ignore the planned new files (sanity check); confirm `.claude/.session-tokens.jsonl` and `.claude/.skill-invocations.jsonl` patterns will be handled correctly.

## Phase 2: PostToolUse Hook Tee

- [x] **2.1** Create `.claude/hooks/agent-token-tee.sh` modeled after `.claude/hooks/skill-invocation-logger.sh`. Header comment must include the Phase 1.2 verified shape with date stamp.
- [x] **2.2** Implement field extraction with defensive `// 0` jq fallbacks for `tool_uses` and `duration_ms` (graceful degradation if Claude Code release omits them).
- [x] **2.3** Implement `flock -w 5` timeout fallback: on contention timeout, log to stderr and exit 0 (never block tool dispatch).
- [x] **2.4** Add kill-switch env var `SOLEUR_DISABLE_AGENT_TOKEN_TEE=1`.
- [x] **2.5** Wire the matcher in `.claude/settings.json` PostToolUse → `Task` → `agent-token-tee.sh`.
- [x] **2.6** Add `.gitignore` entries: `.claude/.session-tokens.jsonl` and `.claude/.session-tokens-*.jsonl.gz`.

## Phase 3: Aggregator Orphan-Gate Extension

- [x] **3.1** Edit `scripts/rule-metrics-aggregate.sh` lines ~180-185: add `| map(select(startswith("te-") | not))` to the orphan-detection jq filter.
- [x] **3.2** Add inline comment next to the new line referencing issue #3494 and confirming `te-` cannot collide with AGENTS.md section prefixes.
- [x] **3.3** Existing aggregator tests must still pass.

## Phase 4: token-efficiency-report.sh Script

- [x] **4.1** Create `plugins/soleur/skills/compound/scripts/token-efficiency-report.sh` with structure from plan Step 3.1.
- [x] **4.2** Implement skip rule with `git merge-base` fallback for first-commit-on-branch (R7 regression).
- [x] **4.3** Implement recursive-self-exclusion via `compound_entry_ts` filter (R6 regression).
- [x] **4.4** Implement namespace-aware skill-path resolution (case statement for `soleur:`, other `plugin:`, and unscoped fallback).
- [x] **4.5** Implement all three trigger code paths: `te-subagent-overshoot` (active), `te-skill-payload-floor` (active), `te-agents-md-turn-cost` (gated off via `RATIO_EMIT_ENABLED=0`).
- [x] **4.6** Implement top-3 cost table render (≤600 tokens of generated text).
- [x] **4.7** Implement `--fixture-mode` flag for unit tests with env-var fixture-path injection.

## Phase 5: Compound SKILL.md Insertion

- [x] **5.1** Edit `plugins/soleur/skills/compound/SKILL.md`: insert Phase 1.6 section between line ~236 (Phase 1.5 empty-case) and Constitution Promotion. Use `<!-- phase-1.6-start -->` and `<!-- phase-1.6-end -->` sentinels.
- [x] **5.2** Section content: thin script invocation + cost-breakdown rubric (≤25 lines, operator reference) + Sharp Edge.
- [x] **5.3** Verify section budget: `awk '/phase-1.6-start/,/phase-1.6-end/' compound/SKILL.md | wc -c` ≤ 1200 chars.

## Phase 6: Tests

- [x] **6.1** Create `.claude/hooks/agent-token-tee.test.sh` with hook scenarios 1-3 from plan Phase 4.
- [x] **6.2** Edit `scripts/rule-metrics-aggregate.test.sh` to add aggregator scenarios 4-5.
- [x] **6.3** Create `plugins/soleur/skills/compound/test/phase-16.test.sh` with all `token-efficiency-report.sh` scenarios (6-13) including R6/R7 regression tests.
- [x] **6.4** Implement scenario 14: budget assertion via sentinel-delimited `wc -c`.
- [x] **6.5** Run all test files locally; confirm pass.

## Phase 7: Live Integration & Verification

- [x] **7.&** Run `bash plugins/soleur/skills/compound/test/phase-16.test.sh` — all tests pass.
- [x] **7.&** Run `bash .claude/hooks/agent-token-tee.test.sh` — all tests pass.
- [x] **7.&** Run `bash scripts/rule-metrics-aggregate.test.sh` — all tests pass.
- [x] **7.&** Run `bash scripts/rule-metrics-aggregate.sh --dry-run` against fixture session with planted `te-*` events; verify exit 0, no orphan failure.
- [x] **7.&** Live integration: invoke `skill: soleur:compound` against a real >50-line-diff branch with the hook tee active. Verify Phase 1.6 output block appears.
- [x] **7.&** Plant 120k envelope using exact printf command from plan Phase 5 step 5; re-run compound; verify `te-subagent-overshoot` line in `.claude/.rule-incidents.jsonl`.
- [x] **7.&** Confirm AGENTS.md not modified: `git diff main...HEAD -- AGENTS.md` returns empty.

## Phase 8: PR & Post-merge

- [ ] **8.1** PR body includes `## Changelog` section per plugin AGENTS.md.
- [ ] **8.2** PR body uses `Closes #3494` on its own line; `Ref #3493` and `Ref #3497`.
- [ ] **8.3** Set `semver:minor` label (new compound phase = new user-facing capability).
- [ ] **8.4** After merge: `gh workflow run rule-metrics-aggregate.yml` (per `wg-after-merging-a-pr-that-adds-or-modifies`); poll until complete; verify exit 0.
- [ ] **8.5** After 7 days: spot-check `.claude/.rule-incidents.jsonl` for any `te-*` events; if any, confirm they appear in `knowledge-base/project/rule-metrics.json`'s `counts` map without orphan failure.
