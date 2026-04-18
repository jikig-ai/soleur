# Tasks: Drain PR #2213 review backlog (10 issues → 1 PR)

Plan: [`2026-04-18-refactor-drain-pr2213-review-backlog-plan.md`](../../plans/2026-04-18-refactor-drain-pr2213-review-backlog-plan.md)
Branch: `feat-one-shot-drain-pr2213-review-backlog`
Worktree: `.worktrees/feat-one-shot-drain-pr2213-review-backlog/`

## 1. Setup

- 1.1 Read plan + every issue body (#2253, #2254, #2255, #2256, #2257, #2259, #2260, #2261, #2262, #2263) into /tmp for cross-reference during work.
- 1.2 Confirm branch is not `main`. Confirm cwd is the worktree, not the bare root.
- 1.3 Run baseline `bash scripts/test-all.sh` to confirm all 12 suites green before editing. Record any pre-existing reds.

## 2. Constants and schema scaffolding (Phase 1)

- 2.1 Create `scripts/lib/rule-metrics-constants.sh` with `RULE_PREFIX_LEN=50`, `UNUSED_WEEKS_DEFAULT=8`, `SCHEMA_VERSION=1` and `# shellcheck disable=SC2034` header.
- 2.2 Source it from `scripts/rule-metrics-aggregate.sh` (after `SCRIPT_DIR` resolution).
- 2.3 Source it from `scripts/rule-prune.sh` (after `SCRIPT_DIR` resolution).
- 2.4 Replace hardcoded `UNUSED_WEEKS=8` / `WEEKS=8` with defaults from constants file.
- 2.5 Replace awk literal `50` in aggregator with `'"$RULE_PREFIX_LEN"'` inline-substitution.
- 2.6 Add `schema: $SCHEMA_VERSION` top-level to aggregator output (new `--argjson schema_version "$SCHEMA_VERSION"`).
- 2.7 Add `.schema = $s` field to `emit_incident` jq construction in `.claude/hooks/lib/incidents.sh`.
- 2.8 TEST (RED): add `t_schema_field` in `test-rule-metrics-aggregate.sh` asserting `jq -e '.schema == 1'` on output.
- 2.9 TEST (RED): extend `_check` in `test_hook_emissions.sh` to assert `.schema == 1` on every captured line.
- 2.10 Run Phase-1 tests → all green.

## 3. Aggregator hygiene (Phase 2)

- 3.1 Split the 35-line jq pipeline (lines 96-136) into 3 stages with intermediate shell variables and per-stage `jq empty` gate: `_rules_json`, `_enriched_json`, `_summary_json`.
- 3.2 Replace `.first_seen | fromdateiso8601` with `(try (.first_seen | fromdateiso8601) catch 0)` in aggregator (both occurrences).
- 3.3 Replace `.first_seen | fromdateiso8601` with the try/catch variant in `scripts/rule-prune.sh`.
- 3.4 Change material-change diff from `jq 'del(.generated_at)'` to `jq -S 'del(.generated_at)'` on both sides.
- 3.5 Write `$rules_tsv` to `$TMPDIR/rule-metrics-rules.tsv` (or `${TMPDIR:-/tmp}`) and feed `--rawfile rules_tsv "$tmp_tsv"`.
- 3.6 Wrap the rotate block (current lines 175-183) in `flock -x 9 … 9>>"$INCIDENTS"`; inside the flock, check `[[ -f "${archive}.gz" ]]` and fall back to `archive-${run_id}.jsonl` name.
- 3.7 TEST (RED): `t_rotate_twice_same_month` — two `AGGREGATOR_ROTATE=1` invocations produce two distinct archive files.
- 3.8 TEST (RED): `t_malformed_first_seen` — invalid `first_seen` timestamp counts the rule as "seen long ago", aggregator exits 0.
- 3.9 TEST (RED): `t_orphan_ids_surfaced` — emit `rule_id: "ghost-id-xyz"` not in AGENTS.md; assert `summary.orphan_rule_ids` contains it.
- 3.10 Run full aggregator test suite → all green.

## 4. Hook hot-path and helper (Phase 3)

- 4.1 Replace `guardrails.sh:22-23` two `jq` calls with single `eval "$(echo "$INPUT" | jq -r '@sh "COMMAND=\(.tool_input.command // "") TOOL_NAME=\(.tool_name // "")"')"`.
- 4.2 Append `resolve_command_cwd` helper function to `.claude/hooks/lib/incidents.sh` (below `detect_bypass`).
- 4.3 Rewrite the commit-on-main CWD-resolution ladder (current lines 40-56) to one `GIT_DIR=$(resolve_command_cwd "$COMMAND" "$INPUT")` call + `[[ -d "$GIT_DIR" ]] || GIT_DIR="$(pwd)"`.
- 4.4 Rewrite the conflict-markers CWD-resolution ladder (current lines 106-117) to the same pattern.
- 4.5 Leave the stash block unconditional (no helper call needed).
- 4.6 Add one-time `/tmp/rule-incidents-warned-$$` marker + stderr warn to `emit_incident` on flock/write failure.
- 4.7 TEST: confirm existing `t_stash_in_worktree`, `t_no_verify_bypass`, `t_LEFTHOOK_bypass`, `t_rm_rf_worktrees`, `t_require_milestone` still pass.

## 5. Test expansion (Phase 4)

- 5.1 Add case `guardrails: block-commit-on-main`: spin up temp git repo on branch `main`, pipe `git commit -m x` command with `.cwd` set, assert emitted `guardrails-block-commit-on-main` with `schema: 1`.
- 5.2 Add case `guardrails: block-conflict-markers`: stage a file with `<<<<<<< HEAD` content in the temp repo, pipe `git commit`, assert emitted `guardrails-block-conflict-markers`.
- 5.3 Add case `guardrails: block-delete-branch`: set up a secondary worktree so `git worktree list` returns >1 line, pipe `gh pr merge 1 --delete-branch`, assert emitted `guardrails-block-delete-branch`.
- 5.4 Add case `pencil-open-guard`: temp repo with untracked `foo.pen`, pipe `{"tool_input":{"filePath":"<abs>/foo.pen"}}` to `pencil-open-guard.sh`, assert emitted `cq-before-calling-mcp-pencil-open-document`.
- 5.5 Add case `worktree-write-guard`: temp repo with `.worktrees/active/`, pipe write to `<GIT_ROOT>/file.txt` to `worktree-write-guard.sh`, assert emitted `guardrails-worktree-write-guard`.
- 5.6 Add `test_removed_id_exits_1` to `test_lint_rule_ids.py`: commit AGENTS.md with ids `[hr-a, hr-b]` at HEAD, remove `hr-b` in working copy, run lint → exit 1 + stderr contains `removed id(s) detected`.
- 5.7 Add `t_invalid_rule_id_skipped` to `test-sync-rule-prune.sh`: fixture with one `valid-id` and one `has space` id, run `rule-prune.sh --dry-run`, assert stderr `Skipping invalid rule_id` and the valid id still listed.

## 6. rule-prune.sh and docs (Phase 5)

- 6.1 Source `scripts/lib/rule-metrics-constants.sh` from `scripts/rule-prune.sh`.
- 6.2 Add `if ! [[ "$id" =~ ^(hr|wg|cq|rf|pdr|cm)-[a-z0-9-]{3,60}$ ]]; then ... continue; fi` at the top of the `while IFS=$'\t'` body.
- 6.3 Replace 15 `echo` body-building lines with one heredoc (unquoted `<<BODY` so `$id`, `$prefix`, `$first_seen`, `$generated_at` interpolate).
- 6.4 Add `generated_at=$(jq -r '.generated_at' "$METRICS")` just before the loop.
- 6.5 Extend body heredoc with `### Verify` section containing the `jq '.rules[] | select(.id=="$id")' …` query and `Based on metrics generated at: \`$generated_at\``.
- 6.6 Update sync.md Rule Prune Analysis step 2: append "Local telemetry source: `.claude/.rule-incidents.jsonl` (gitignored, written by hooks)."
- 6.7 Update sync.md step 3: document `--dry-run` on the aggregator.
- 6.8 Rewrite `plugins/soleur/skills/compound/SKILL.md:210` from silent-swallow to explicit `[[ -x ... ]]` + error surface (pattern in plan Phase 5.3).
- 6.9 Correct the stale `# warn only — not a hard fail` comment in `scripts/lint-rule-ids.py` to reflect that removed-id actually exits 1.

## 7. Verification and ship (Phase 6)

- 7.1 `bash scripts/test-all.sh` — all 12 suites green.
- 7.2 Run `scripts/rule-metrics-aggregate.sh --dry-run` — emits `schema: 1`, exits 0.
- 7.3 Fire a synthetic `git stash` command through `.claude/hooks/guardrails.sh` locally, grep `.claude/.rule-incidents.jsonl` to confirm `"schema": 1` in the new line. Delete the test line before commit.
- 7.4 `git add` all touched files. Commit with messages per phase (6 commits max). Run `/soleur:compound`.
- 7.5 `git push -u origin feat-one-shot-drain-pr2213-review-backlog`.
- 7.6 Open PR with body containing all 10 `Closes #NNNN` lines + a "Reconciliation" subsection noting #2270 already resolved backfill-specific items from #2259, #2260, #2263, and #2252 already landed orphan_rule_ids for #2261 §4b. Reference PR #2486 as the one-PR-many-closures prior art.
- 7.7 `/ship` with `semver:patch` label (bug-fix cleanup, no new agents/commands/skills).
- 7.8 After merge, verify next scheduled `rule-metrics-aggregate.yml` run succeeds and the resulting `rule-metrics.json` has `"schema": 1`.

## 8. Post-merge cleanup

- 8.1 Confirm all 10 issues auto-close via `Closes #NNNN` in PR body.
- 8.2 Run `/soleur:compound` post-merge to capture the "many-closures via reconciliation table" pattern as a learning in `knowledge-base/project/learnings/best-practices/` — topic `review-backlog-reconciliation-before-implementation`.
