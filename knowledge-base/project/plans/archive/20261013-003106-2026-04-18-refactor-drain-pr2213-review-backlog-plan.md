# Refactor: drain PR #2213 review backlog (10 issues, one PR)

**Branch:** `feat-one-shot-drain-pr2213-review-backlog`
**Worktree:** `.worktrees/feat-one-shot-drain-pr2213-review-backlog/`
**Closes:** #2253, #2254, #2255, #2256, #2257, #2259, #2260, #2261, #2262, #2263
**Pattern:** one-PR-many-closures (see PR #2486 — closed #2467 + #2468 + #2469 in a single cleanup PR)
**Estimated effort:** Medium (1 session). Most hunks are small, independently verifiable, and touch the same 7 source files.

## Enhancement Summary

**Deepened on:** 2026-04-18
**Sections enhanced:** reconciliation table, phase implementation details, test scenarios, sharp edges
**Research sources used:** 6 load-bearing learnings from `knowledge-base/project/learnings/` (rule-utility telemetry patterns, guardrails grep bypasses, bash parameter expansion quoting, GIT_CEILING_DIRECTORIES test isolation, hook CLAUDE_PROJECT_DIR resolution, negative-space test extraction).

### Key Improvements from Deepen Pass

1. **Locked in 4 reusable telemetry patterns** from the existing rule-utility-scoring learning (flock-guarded append, side-effect telemetry without contract change, tolerant JSONL parse, orphan bucket) — the plan now cites them verbatim rather than re-inventing them.
2. **Flagged test-isolation risk for the new guardrails test cases** — new `git init` fixtures in `test_hook_emissions.sh` MUST strip `GIT_DIR`/`GIT_INDEX_FILE`/`GIT_WORK_TREE` and set `GIT_CEILING_DIRECTORIES=$WORK` or the fixture's git commands will escape to the parent worktree.
3. **Added explicit chained-command guardrail check** — the new commit-on-main test case in Phase 4 must include a chained-command scenario (`git add foo && git commit -m x`) per learning 2026-02-24 (guardrails chained-commit bypass).
4. **Hardened heredoc strategy for rule-prune.sh body** — plan now uses a **single quote-nested heredoc with variable substitution via `sed` post-expand**, avoiding the `'"'"'` pitfall from learning 2026-04-07. Alternative: build the body with multiple `printf` calls if backtick escaping becomes brittle.
5. **Explicit "proof of delegation" regression test** — for the `resolve_command_cwd` helper, the test must both (a) prove the guard still fires on a valid CWD, AND (b) prove the guard uses the new helper's fallback chain. Mirrors the negative-space-test learning (substring-presence is not proof).
6. **Rotation flock re-entrancy clarified** — plan documents that `flock -x 9 … 9>>"$INCIDENTS"` is safe to stack with the hook-writer's `flock -x 9 … 9>>"$file"` because they acquire the same file-backed lock and both respect the `-x` exclusive contract. No TOCTOU.

### New Considerations Discovered

- **Rule-metrics-aggregate workflow already uses a synthetic-check-run bot-PR pattern** (PR #2270). Adding a `schema: 1` field does NOT require workflow changes — the aggregator script writes the file, the workflow auto-PRs it. Shape validation can stay local to the script.
- **PR #2270 already deleted `backfill-rule-ids.py`.** Four of the ten issues reference it. The reconciliation table in the plan dispatches those items as already-resolved; verify each during implementation by grepping the tree (`rg backfill-rule-ids` should return zero).
- **Helper extraction target** — putting `resolve_command_cwd` in `lib/incidents.sh` (existing sourced library) avoids adding `lib/cmd-parse.sh` as a new file. Smaller surface, same benefit.

## Overview

All ten open issues filed against PR #2213 review target the same code area: the rule-utility telemetry stack shipped in `.claude/hooks/*`, `scripts/rule-metrics-*.sh`, `scripts/rule-prune.sh`, `scripts/lint-rule-ids.py`, their tests, and one-line consumers in `plugins/soleur/skills/compound/SKILL.md` and `plugins/soleur/commands/sync.md`. Folding them into a single refactor PR avoids ten re-reviews of the same files and mirrors the net-negative-backlog pattern PR #2486 established.

## Research Reconciliation — Spec vs. Codebase

Issue bodies reference artifacts that no longer exist or differ from what is committed. Every claim below is reconciled to worktree reality before the plan proceeds.

| Spec claim (issue body) | Codebase reality (verified in worktree) | Plan response |
|---|---|---|
| `scripts/backfill-rule-ids.py` exists (#2259 §2a, #2260 §3b, #2263 §6a/§6c/§6d) | **Deleted in PR #2270** (follow-up to #2213). Confirmed via `git log --all -- scripts/backfill-rule-ids.py`. | Drop every backfill-specific bullet as **already-resolved**: 2a, 3b, 6c (uniformity across Python scripts), 6d backfill side. Record these closures in the PR body with `Resolved by #2270` per item. |
| CI has a `rule-metrics-shape` gate (#2261 §4a) that asserts `schema == 1` | **No such gate exists.** `.github/workflows/rule-metrics-aggregate.yml` has no shape assertion step; it just runs the aggregator and opens a PR. | Schema versioning still lands in the aggregator + incidents.sh. The "CI shape gate validates schema" acceptance criterion becomes a **local `jq empty + schema check` inside the aggregator** (`exit 4` on mismatch), not a new workflow. Tracked explicitly in AC to avoid scope creep. |
| `summary.orphan_rule_ids[]` is missing (#2261 §4b) | **Already present** in `rule-metrics-aggregate.sh:121-133`. #2252 (the original orphan-ids issue) is closed. | Drop 4b sub-bullet. Acceptance check: verify orphan_rule_ids emits expected entries in the existing test; add a positive-case assertion if missing. |
| `guardrails.sh:23-24` runs two `jq` invocations (#2253) | Confirmed — lines 22-23 run `jq -r '.tool_input.command'` then `jq -r '.tool_name'`. | Fold into one `jq @sh` call as proposed. |
| `guardrails.sh:28-45, 90-102, 132-146` has 3× ladder (#2255) | Confirmed lines 40-56 (commit-on-main), 106-117 (conflict-markers), and the stash block (lines 150-163) is unconditional and has NO ladder today. | Extract helper for the **two** remaining ladder sites (commit-on-main, conflict-markers). Update the AC in the PR body to "two guards use the helper" rather than the issue's claim of three. The stash block is already simplified and does not need the helper. |
| Stash block uses `RESOLVE_DIR="${STASH_GUARD_DIR:-.}"` (#2255 §drift) | Not present in current file — block is now unconditional (line 154 onward). | Already-resolved drift. |
| `jq -s`-reduce (`#2261 §4b silent-drop`) drops orphan IDs | Aggregator already emits `orphan_rule_ids` via `$rules | map(.id)` diff against `$counts | keys`. | Add TEST asserting orphan IDs are surfaced (regression guard). |
| `scripts/rule-metrics-aggregate.sh:152-156` string-compares JSON (#2259 §2b) | Confirmed. Fix with `jq -S`. | As-proposed. |
| `scripts/rule-metrics-aggregate.sh:160-167` rotate block (#2254) | Actual lines are 175-183; logic otherwise matches. | Apply flock + archive-uniquify fix. |
| `scripts/lint-rule-ids.py:60-67` soft-warns on removed id (#2259 §2c) | Confirmed — `errors.append(...)` is stored but the path returns `1` anyway because errors list is non-empty. **This makes the "hard-fail" claim almost true.** BUT the comment says "warn only — not a hard fail"; the code in fact hard-fails because it writes to the `errors` list that triggers exit 1 at line 78. The comment lies; the behavior is already correct. | Update the code comment to match reality; add a test for "removed-id diff → exit 1". No behavior change needed. |
| `.claude/hooks/lib/incidents.sh:43-56` silently swallows write failures (#2259 §2d) | Confirmed. | Add one-time stderr warning, guarded by `/tmp/rule-incidents-warned-$$`. |

**Why this section matters:** issues were filed against a snapshot that has since shifted. Implementing every "proposed fix" verbatim would create dead code or re-invent logic already present. This reconciliation is the plan's core deliverable; the edit list below is the mechanical execution of it.

## Goal

Close all ten review-backlog issues with one PR that:

1. Applies every still-relevant fix from the ten issue bodies.
2. Documents already-resolved items (backfill.py deletions, orphan_rule_ids already present, stash ladder already simplified) with a single PR-body note so re-triage is avoided.
3. Extends tests to guard every new behavior (no silent passes).
4. Leaves the AGENTS.md no-heredocs-in-Actions rule untouched (heredoc allowed in shell scripts per #2263 §6b).

## Non-Goals

- Schema v2 (additional bypass detectors, session IDs, branch context) — tracked for a future PR, NOT in scope.
- New CI shape-check workflow — rejected; local `jq empty` + schema field check in-aggregator is enough.
- Renaming `rules_unused_over_8w` → `rules_unused_over_threshold` (#2263 §6a) — schema-breaking, requires coordination with downstream consumers; kept but documented as permanent for now. Compound SKILL.md step 8 already reads `rules_unused_over_8w`.
- Touching AGENTS.md rule IDs (cq-rule-ids-are-immutable).

## Files to Edit

- `.claude/hooks/guardrails.sh` — double-jq collapse (#2253), helper extraction call-sites (#2255).
- `.claude/hooks/lib/incidents.sh` — schema versioning on emitted lines (#2261 §4a), one-time warning on flock/write failure (#2259 §2d), new `resolve_command_cwd` helper (#2255).
- `scripts/rule-metrics-aggregate.sh` — flock rotation + archive uniquification (#2254), jq pipeline split into named stages (#2260 §3a), try/catch `fromdateiso8601` (#2260 §3c), `jq -S` on diff comparison (#2259 §2b), TSV materialization to `$TMPDIR` (#2260 §3d), schema field on output (#2261 §4a), magic-number extraction (#2263 §6a).
- `scripts/rule-prune.sh` — rule_id regex validation before `gh issue list --search` (#2257), try/catch `fromdateiso8601` (#2260 §3c), heredoc body (#2263 §6b), `### Verify` block with paste-ready jq + `generated_at` (#2262 §5a), magic-number sourced from shared lib (#2263 §6a).
- `scripts/lint-rule-ids.py` — update stale code comment to match actual hard-fail behavior (#2259 §2c reconciliation).
- `plugins/soleur/skills/compound/SKILL.md` — replace silent-swallow with explicit executable + error surface (#2261 §4c).
- `plugins/soleur/commands/sync.md` — mention `.claude/.rule-incidents.jsonl` path + `--dry-run` flag (#2262 §5b, §5c).
- `tests/hooks/test_hook_emissions.sh` — add cases for `pencil-open-guard.sh`, `worktree-write-guard.sh`, `guardrails-block-commit-on-main`, `guardrails-block-conflict-markers`, `guardrails-block-delete-branch` (#2256). Add one regression case per guard that exercises the new `resolve_command_cwd` helper (#2255 §AC).
- `tests/scripts/test-rule-metrics-aggregate.sh` — add "rotate twice same month" case (#2254 §AC), orphan_rule_ids positive assertion (#2261 §4b reconciliation), schema field presence (#2261 §4a), malformed `first_seen` tolerance (#2260 §3c).
- `tests/scripts/test_lint_rule_ids.py` — add removed-id → exit 1 case (#2259 §2c).

## Files to Create

- `scripts/lib/rule-metrics-constants.sh` — shared constants sourced by `rule-metrics-aggregate.sh` and `rule-prune.sh`. Exports: `RULE_PREFIX_LEN=50`, `UNUSED_WEEKS_DEFAULT=8`, `SCHEMA_VERSION=1`. (#2263 §6a, #2261 §4a).
- `tests/commands/test-sync-rule-prune.sh` — already exists per `scripts/test-all.sh`; confirm and extend with "invalid rule_id format rejected" case (#2257 §AC).

## Files to Delete

None. No rename, no reorg.

## Dependencies and Ordering

The edits are mostly independent. A safe topological order for commits, each fully tested:

1. **Constants + schema scaffolding.** Create `scripts/lib/rule-metrics-constants.sh`. Add `SCHEMA_VERSION` to incidents.sh emitter and to aggregator output top level. Update tests to assert `schema == 1`. Nothing downstream relies on this yet.
2. **Aggregator hygiene.** jq pipeline split, try/catch `fromdateiso8601`, `jq -S` diff, TSV materialization, flock+uniquify rotation. Extend tests: rotate-twice, malformed-timestamp tolerance, orphan_rule_ids positive-case.
3. **Hook hot-path + helper.** Collapse double-jq in guardrails.sh. Add `resolve_command_cwd` to `lib/incidents.sh` (or a new `lib/cmd-parse.sh` — keep it co-located in incidents.sh to avoid a new source file). Wire commit-on-main and conflict-markers guards through the helper. Add one-time-warn on incident write failure.
4. **Test expansion.** Extend `test_hook_emissions.sh` to cover all six deny sites + pencil + worktree-write-guard. Extend `test_lint_rule_ids.py` removed-id case.
5. **rule-prune.sh + docs.** Regex validation, heredoc body, `### Verify` block with `generated_at`, try/catch `fromdateiso8601`. Add invalid-ID test case. Update sync.md + compound SKILL.md.
6. **Commit compound SKILL.md explicit-path check** (#2261 §4c) last so no step 8 warning fires mid-session.

Each numbered commit runs `bash scripts/test-all.sh` before push. If any commit goes red, fix in the same commit (do NOT defer).

## Implementation Phases

### Phase 1 — Constants and schema field (15 min)

1. Write `scripts/lib/rule-metrics-constants.sh`:
   ```bash
   #!/usr/bin/env bash
   # Shared constants for rule-metrics scripts.
   # shellcheck disable=SC2034  # sourced by other scripts
   RULE_PREFIX_LEN=50
   UNUSED_WEEKS_DEFAULT=8
   SCHEMA_VERSION=1
   ```
2. Source it from `rule-metrics-aggregate.sh` (after `SCRIPT_DIR=...` line) and from `rule-prune.sh`.
3. Replace `UNUSED_WEEKS=8` with `UNUSED_WEEKS=$UNUSED_WEEKS_DEFAULT` in the aggregator and `WEEKS=8` with `WEEKS=$UNUSED_WEEKS_DEFAULT` in rule-prune.sh.
4. Replace `substr(line, 1, 50)` in aggregator awk with `substr(line, 1, '"$RULE_PREFIX_LEN"')` (awk inline-substitution pattern).
5. Aggregator top-level JSON gains `schema: $SCHEMA_VERSION` (jq --argjson).
6. `emit_incident` in `incidents.sh` passes `--argjson s $SCHEMA_VERSION` and `.schema = $s` to the jq builder.
7. Extend `tests/scripts/test-rule-metrics-aggregate.sh` T1 to assert `jq -e '.schema == 1'` on the output.
8. Extend `tests/hooks/test_hook_emissions.sh` `_check` to assert `.schema == 1` on every captured line.

### Phase 2 — Aggregator hygiene (30 min)

1. Split the 35-line jq pipeline into three sequential `--argjson` stages. Each stage produces a jq expression fed into a shell variable, and each is validated with `jq empty <<<"$var"` before the next uses it:
   - `_parse_rules_tsv` — `$rules` array from TSV.
   - `_enrich_with_counts` — `$enriched` (rules left-joined with $counts).
   - `_build_summary` — final top-level object.
2. Swap `fromdateiso8601` for `(try (.first_seen | fromdateiso8601) catch 0)` in both aggregator summary and rule-prune filter.
3. Change `jq 'del(.generated_at)'` comparison to `jq -S 'del(.generated_at)'` on both sides.
4. Replace `<(printf '%s' "$rules_tsv")` with `$tmp_tsv=$TMPDIR/rule-metrics-rules.tsv` written once, then `--rawfile rules_tsv "$tmp_tsv"` — matches `scripts/rule-audit.sh` idiom.
5. Wrap rotation block in flock on `$INCIDENTS`, then uniquify archive name:
   ```bash
   (
     flock -x 9
     if [[ -f "${archive}.gz" ]]; then
       # Second run in same month → fall back to a run-id suffix.
       archive="${REPO_ROOT}/.claude/.rule-incidents-${ts}-$(date -u +%H%M%S).jsonl"
     fi
     cat "$INCIDENTS" >> "$archive"
     : > "$INCIDENTS"
   ) 9>>"$INCIDENTS"
   gzip -f "$archive" 2>/dev/null || true
   ```
6. Extend `tests/scripts/test-rule-metrics-aggregate.sh`:
   - `t_rotate_twice_same_month` — run the aggregator twice with `AGGREGATOR_ROTATE=1`, assert both archive files exist (`.claude/.rule-incidents-<YYYY-MM>.jsonl.gz` AND the suffixed second).
   - `t_malformed_first_seen` — write a valid jsonl line with `first_seen` manipulated to an invalid date, run aggregator, assert exit 0 and the row is counted as "seen long ago" (i.e., in `rules_unused_over_8w`).
   - `t_orphan_ids_surfaced` — emit one line with `rule_id: "ghost-id-not-in-agents-md"`, assert `summary.orphan_rule_ids == ["ghost-id-not-in-agents-md"]`.

### Phase 3 — Hook hot-path and helper (30 min)

1. Collapse the double `jq` at `guardrails.sh:22-23` into one `jq @sh` eval:
   ```bash
   eval "$(echo "$INPUT" | jq -r '@sh "COMMAND=\(.tool_input.command // "") TOOL_NAME=\(.tool_name // "")"')"
   ```
   Rationale: single fork, shell-escaped values, exact existing variable names.

   **Research insight (learning 2026-04-15-rule-utility-scoring-telemetry-patterns, Pattern 2):** The PreToolUse hook contract is stable on the output side only; input extraction is internal. Collapsing two `jq` forks into one is safe because both extractions produce the same string values the rest of the script already expects. Verify via existing `t_stash_in_worktree` (no behavior change expected).
2. Add `resolve_command_cwd` helper to `.claude/hooks/lib/incidents.sh` (bottom of file so `source` ordering is unchanged):
   ```bash
   # resolve_command_cwd "<command>" "<hook_input_json>" → echoes resolved CWD or empty.
   resolve_command_cwd() {
     local cmd="$1" input="$2" dir=""
     if echo "$cmd" | grep -qE '^\s*cd\s+'; then
       dir=$(echo "$cmd" | sed -nE 's/^\s*cd\s+"?([^"&;]+)"?.*/\1/p' | xargs)
     elif echo "$cmd" | grep -qoE 'git\s+-C\s+\S+'; then
       dir=$(echo "$cmd" | grep -oE 'git\s+-C\s+\S+' | head -1 | sed -nE 's/git\s+-C\s+(\S+)/\1/p')
     fi
     if [[ -z "$dir" || ! -d "$dir" ]]; then
       dir=$(echo "$input" | jq -r '.cwd // ""' 2>/dev/null || echo "")
     fi
     echo "$dir"
   }
   ```
3. Rewrite the commit-on-main block (lines 36-67 current) to call the helper and only keep the branch-check logic local.
4. Rewrite the conflict-markers block (lines 105-133 current) to call the helper and keep the `git diff --cached` logic local.
5. Leave the unconditional stash block (lines 154-163 current) as-is — already simplified per reconciliation.
6. Add one-time write-failure warn to `emit_incident`:
   ```bash
   local marker="/tmp/rule-incidents-warned-$$"
   (
     flock -x 9
     printf '%s\n' "$line" >&9
   ) 9>>"$file" 2>/dev/null || {
     [[ -f "$marker" ]] || {
       echo "[rule-incidents] warning: failed to write $file (permissions? disk?)" >&2
       : > "$marker" 2>/dev/null || true
     }
   }
   ```

### Phase 4 — Test expansion (30 min)

**Research insight (learning 2026-03-24-git-ceiling-directories-test-isolation):** Any fixture running `git init` inside `$WORK` will escape to the parent worktree unless the test explicitly strips git env-vars AND sets `GIT_CEILING_DIRECTORIES`. The existing `t_stash_in_worktree` case avoids this because it only manipulates paths, never runs `git` inside the fixture. The new cases below DO run `git` (init, branch, commit, worktree list) and MUST include this preamble at the top of each case:

```bash
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE
export GIT_CEILING_DIRECTORIES="$WORK"
```

Add this once at the top of each new case (before `git init`), or hoist into `_check` setup.

**Research insight (learning 2026-02-24-guardrails-chained-commit-bypass):** The existing `guardrails.sh` commit-on-main pattern matches `(^|&&|\|\||;)\s*git\s+commit` after PR #2213's fix. The new test case MUST include a **chained-command variant** (`git add foo && git commit -m x`) to regression-guard against an accidental revert to the `^`-anchored pattern. One invocation with anchor-only, one with chain.

1. `tests/hooks/test_hook_emissions.sh` — add:
   - `guardrails: block-commit-on-main (direct)` — build a fake git repo on branch `main`, set `.cwd`, pipe `git commit -m x` command, assert emitted `guardrails-block-commit-on-main`.
   - `guardrails: block-commit-on-main (chained)` — same repo, pipe `git add foo && git commit -m x`, assert same rule_id fires (regression guard for the chained-command bypass).
   - `guardrails: block-conflict-markers` — stage a file with `<<<<<<< HEAD` content in the fake repo (use `printf '<<<<<<< HEAD\n'` to avoid the test file itself tripping the conflict-markers grep on commit), pipe `git commit` command, assert emitted `guardrails-block-conflict-markers`.
   - `guardrails: block-delete-branch` — set up a fake repo with a second worktree so `git worktree list | wc -l > 1`, pipe `gh pr merge 1 --delete-branch`, assert emitted `guardrails-block-delete-branch`.
   - `pencil-open-guard` — fake repo with an untracked `foo.pen`, pipe `{"tool_input":{"filePath":"<abs>/foo.pen"}}` into `pencil-open-guard.sh`, assert emitted `cq-before-calling-mcp-pencil-open-document`.
   - `worktree-write-guard` — fake repo with `.worktrees/active/` populated, pipe write to `<GIT_ROOT>/file.txt`, assert emitted `guardrails-worktree-write-guard`.

   All cases use `git init` inside `$WORK` with the GIT_CEILING_DIRECTORIES preamble above. The `worktree-write-guard` case also needs `git worktree add "$WORK/.worktrees/active" HEAD` (or a stub directory under `.worktrees/` since the guard uses `ls -A` presence, not a real worktree).
2. `tests/scripts/test_lint_rule_ids.py` — add `test_removed_id_exits_1`: write two AGENTS.md snapshots (HEAD + current) via two committed revisions in a tempdir-backed git repo, run the lint against the second, assert exit code 1 and the error string contains `removed id(s) detected`.
3. `tests/commands/test-sync-rule-prune.sh` (confirm exists; extend) — add `t_invalid_rule_id_skipped`: craft a `rule-metrics.json` fixture with one id `valid-id` and one id `has space` (manually injected), run `rule-prune.sh --dry-run`, assert stderr contains `Skipping invalid rule_id` and no issue-file line for the bad id.

### Phase 5 — rule-prune.sh + docs (20 min)

1. `scripts/rule-prune.sh`:
   - Source `scripts/lib/rule-metrics-constants.sh`.
   - At top of the `while IFS=$'\t'` loop body, add:
     ```bash
     if ! [[ "$id" =~ ^(hr|wg|cq|rf|pdr|cm)-[a-z0-9-]{3,60}$ ]]; then
       echo "::warning::Skipping invalid rule_id: $id" >&2
       skipped=$((skipped + 1))
       continue
     fi
     ```
     Regex mirrors `lint-rule-ids.py` ID_RE (identical scoping).
   - Replace 15 `echo` lines with a heredoc. **Escaping strategy (per learning 2026-04-07):** use an unquoted heredoc (`<<BODY`) so `$id`, `$prefix`, `$first_seen`, `$generated_at`, `$WEEKS` interpolate. Every backtick inside the body must be escaped `\``; every `$` that must remain literal (none in this body) would need `\$`. Markdown triple-backtick fences (```` ``` ````) are each written as `\`\`\``:

     ```bash
     generated_at=$(jq -r '.generated_at' "$METRICS")
     cat > "$body_file" <<BODY
     - **Rule:** \`$id\`
     - **Text (first 50 chars):** $prefix
     - **Section:** $section
     - **hit_count:** 0 over >=${WEEKS} weeks
     - **First seen:** $first_seen

     ### Verify

     \`\`\`
     jq '.rules[] | select(.id=="$id")' knowledge-base/project/rule-metrics.json
     \`\`\`

     Based on metrics generated at: \`$generated_at\`

     ### Reassessment criteria

     Re-run \`/soleur:sync rule-prune\` in 4 weeks. If \`hit_count\` is still 0 and
     no bypasses were recorded, propose removal in \`AGENTS.md\` via a normal PR.

     ### This issue does NOT authorize removal

     A human must edit \`AGENTS.md\` and open a PR. Rules protecting rare but
     catastrophic failures (e.g., \`hr-never-git-stash-in-worktrees\`) may have
     zero hits and still be load-bearing.

     _Filed by \`scripts/rule-prune.sh --weeks=${WEEKS}\`. See plan #2210._
     BODY
     ```

     **Fallback if backtick escaping proves brittle:** split the body into two heredocs (one for fixed sections, one for the Verify block) and `cat` them into `$body_file` sequentially. The issue's original 15 `echo` calls worked fine — the heredoc is a readability improvement, not a correctness fix. If the heredoc introduces a regression, revert to `echo`/`printf` style with constants extracted.
   - Swap `fromdateiso8601` to the try/catch variant (same as aggregator).
2. `plugins/soleur/commands/sync.md` Rule Prune Analysis section:
   - Step 2: append "Local telemetry source: `.claude/.rule-incidents.jsonl` (gitignored, written by hooks)."
   - Step 3: mention `--dry-run` explicitly on the aggregator invocation example.
3. `plugins/soleur/skills/compound/SKILL.md:210` — replace the current silent-swallow line with:
   ```bash
   if [[ -x scripts/rule-metrics-aggregate.sh ]]; then
     if unused=$(bash scripts/rule-metrics-aggregate.sh --dry-run 2>&1 | jq -r '.summary.rules_unused_over_8w // "unknown"' 2>/dev/null); then
       [[ "$unused" != "0" && "$unused" != "unknown" ]] && echo "[INFO] $unused rules have zero hits over 8 weeks."
     else
       echo "[WARN] rule-metrics-aggregate.sh --dry-run failed; skipping unused-rules hint." >&2
     fi
   fi
   ```
4. `scripts/lint-rule-ids.py` — correct stale `# Removed-id diff check (warn only — not a hard fail...)` comment to reflect that it IS a hard fail (errors list feeds exit 1).

### Phase 6 — Run full suite, ship (20 min)

1. `bash scripts/test-all.sh` — all 12 suites green.
2. `bash scripts/rule-metrics-aggregate.sh --dry-run` — exit 0, JSON carries `schema: 1` and valid `summary.rules_unused_over_8w`.
3. `bash .claude/hooks/guardrails.sh < <(echo '{"tool_name":"Bash","tool_input":{"command":"git status"}}')` — exit 0, no telemetry emitted.
4. Push branch, run `/soleur:compound`, then `/ship` with `semver:patch` label (bug-fix cleanup).

## Test Scenarios

### Unit (per-guard, per-script)

- Aggregator: empty jsonl, synthetic denies, idempotent rerun, `--dry-run` never writes, malformed line tolerance, malformed first_seen tolerance, orphan ids surfaced, schema field present, rotate-twice-same-month, jq -S diff comparison.
- rule-prune: invalid rule_id rejected (regex), Verify block present in body fixture, try/catch first_seen handles bad timestamp.
- lint-rule-ids: removed id in diff exits 1.
- Hook emissions: all 6 guardrail deny sites + pencil + worktree-write-guard all emit correct rule_id and schema field.
- incidents.sh: one-time stderr warn on unwritable file (simulate by chmod 000 on the incidents file).

### Integration

- Run the full weekly aggregator against a synthetic INCIDENTS_REPO_ROOT with 10 rules in AGENTS.md + 30 events in jsonl (mix of denies, bypasses, unknown ids); assert the produced `rule-metrics.json` is schema-1-valid, `jq empty` passes, and all four summary counters resolve to non-negative integers.
- Run rule-prune.sh --dry-run against the same fixture; assert it emits one line per candidate AND gracefully skips any fabricated invalid-id rows.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `bash scripts/test-all.sh` passes all 12 suites on the PR branch.
- [ ] `.claude/hooks/guardrails.sh` contains exactly one `jq -r` invocation on `$INPUT` at the top of the file.
- [ ] `.claude/hooks/guardrails.sh` has two guards using `resolve_command_cwd` (commit-on-main, conflict-markers); the stash block remains unconditional.
- [ ] `grep -c "cd\\\\s+" .claude/hooks/guardrails.sh` matches only the helper's usage site (≤1 remaining occurrence).
- [ ] `scripts/rule-metrics-aggregate.sh --dry-run` emits `schema: 1` at the top level.
- [ ] `.claude/.rule-incidents.jsonl` lines emitted by `emit_incident` carry `schema: 1`.
- [ ] `scripts/rule-metrics-aggregate.sh` rotation is wrapped in `flock -x`.
- [ ] Re-running the aggregator within the same calendar month produces a second, non-overwriting archive file.
- [ ] `scripts/rule-prune.sh` rejects rule_ids not matching `^(hr|wg|cq|rf|pdr|cm)-[a-z0-9-]{3,60}$` with a stderr warning and `continue`.
- [ ] `scripts/rule-prune.sh` body template has a `### Verify` block with the jq query and the `generated_at` timestamp.
- [ ] `scripts/rule-prune.sh` body is built via a heredoc (no `echo` stream).
- [ ] `scripts/lint-rule-ids.py` removed-id diff check is covered by `test_lint_rule_ids.py::test_removed_id_exits_1`.
- [ ] `tests/hooks/test_hook_emissions.sh` covers 8 total cases: 6 guardrails denies + pencil + worktree-write.
- [ ] `tests/scripts/test-rule-metrics-aggregate.sh` has new `t_rotate_twice_same_month`, `t_malformed_first_seen`, `t_orphan_ids_surfaced`, `t_schema_field`.
- [ ] `plugins/soleur/skills/compound/SKILL.md` step 8 rule-metrics hint uses an explicit `[[ -x ... ]]` + `|| echo WARN` pattern (no silent swallow).
- [ ] `plugins/soleur/commands/sync.md` Rule Prune Analysis mentions `.claude/.rule-incidents.jsonl` path and the aggregator's `--dry-run` flag.
- [ ] `scripts/lib/rule-metrics-constants.sh` exists and is sourced by `rule-metrics-aggregate.sh` and `rule-prune.sh`.
- [ ] PR body contains `Closes #2253`, `Closes #2254`, `Closes #2255`, `Closes #2256`, `Closes #2257`, `Closes #2259`, `Closes #2260`, `Closes #2261`, `Closes #2262`, `Closes #2263`.
- [ ] PR body's "Reconciliation" section lists items dropped because they were resolved elsewhere (#2270, #2252).

### Post-merge (operator)

- [ ] After merge, the next scheduled `rule-metrics-aggregate.yml` Sunday run creates a PR whose committed `rule-metrics.json` contains `"schema": 1`. Verify via `gh run list -w rule-metrics-aggregate.yml --limit 1`.
- [ ] `/soleur:compound` run after merge emits no `[WARN] rule-metrics-aggregate.sh --dry-run failed` line on clean repos.

## Risks and Mitigations

- **Risk: jq pipeline split introduces an off-by-one or dropped field.** Mitigation: `jq empty` gate after each stage; full existing `t_counts` test must still pass before shipping any stage.
- **Risk: flock on `$INCIDENTS` deadlocks when the rotator holds fd 9 during a concurrent emit.** Mitigation: rotate runs in CI only (`AGGREGATOR_ROTATE=1`); no production hook emits during the rotate window; the flock acquire is bounded by the single `cat … : > "$INCIDENTS"` block which completes in milliseconds.
- **Risk: `resolve_command_cwd` subtly changes behavior of commit-on-main when `.cwd` is provided but not a dir.** Mitigation: helper preserves the existing short-circuit (`[[ -d "$dir" ]]`) and falls back to `jq -r '.cwd'`. Test `guardrails: block-commit-on-main` case with no `.cwd` exercises the final fallback.
- **Risk: `@sh` eval in the hot-path is one jq fork but vulnerable to embedded single quotes.** Mitigation: `@sh` already shell-escapes; values are captured into named vars and never re-interpreted. Existing t_counts and t_empty tests assert no regression.
- **Risk: schema field breaks downstream consumers that `jq empty` only.** Mitigation: consumers (compound step 8, rule-prune.sh) read only specific fields; `schema` is additive.
- **Risk: test_hook_emissions.sh new cases flake under worker contention.** Mitigation: each case uses its own `$WORK` tempdir with `git init`; no cross-test sharing.

## Open Code-Review Overlap

All 10 overlapping open code-review issues ARE this PR's scope. No secondary overlap exists.

| File | Open review issues | Disposition |
|---|---|---|
| `.claude/hooks/guardrails.sh` | #2253, #2255, #2256 | Fold in (this PR's core scope). |
| `.claude/hooks/lib/incidents.sh` | #2253, #2255, #2259, #2261 | Fold in. |
| `scripts/rule-metrics-aggregate.sh` | #2254, #2259, #2260, #2261, #2262, #2263 | Fold in. |
| `scripts/rule-prune.sh` | #2257, #2260, #2262, #2263 | Fold in. |
| `scripts/lint-rule-ids.py` | #2259, #2263 | Fold in (comment fix + test add; no code behavior change). |
| `tests/hooks/test_hook_emissions.sh` | #2253, #2255, #2256 | Fold in. |
| `tests/scripts/test-rule-metrics-aggregate.sh` | #2254 | Fold in. |
| `plugins/soleur/skills/compound/SKILL.md` | #2261 | Fold in. |
| `plugins/soleur/commands/sync.md` | #2262 | Fold in. |

**No additional `code-review` label open issues touch these files.** The scope is exactly ten closures.

## Domain Review

**Domains relevant:** none

Infrastructure/tooling refactor — no user-facing UI, no pricing, no marketing surface, no legal copy, no new external integrations. The changes harden a telemetry system consumed by one skill (`compound`) and one command (`sync`), both already gated by existing CI tests.

## Applied Learnings

These existing learnings directly informed the plan; cite them in the PR body so reviewers don't re-derive.

- `knowledge-base/project/learnings/best-practices/2026-04-15-rule-utility-scoring-telemetry-patterns.md` — Four reusable patterns used wholesale in this refactor: flock-guarded append, tolerant JSONL parse, orphan bucket, side-effect telemetry without contract change.
- `knowledge-base/project/learnings/2026-04-15-rule-metrics-aggregator-pr-pattern-session-gotchas.md` — Confirms PR #2270 already deleted `backfill-rule-ids.py`; drives the reconciliation table.
- `knowledge-base/project/learnings/2026-02-24-guardrails-chained-commit-bypass.md` — Drives the chained-command regression test for commit-on-main.
- `knowledge-base/project/learnings/2026-02-24-guardrails-grep-false-positive-worktree-text.md` — Reminds us that compound greps must enforce proximity, not just substring presence. Current `guardrails.sh` rm-rf pattern already satisfies this; no change needed, but test_hook_emissions.sh delete-branch test must avoid false positives from similar `.worktrees/` mentions in the command body.
- `knowledge-base/project/learnings/2026-03-24-git-ceiling-directories-test-isolation.md` — Drives the `unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE` + `GIT_CEILING_DIRECTORIES` preamble in new test cases.
- `knowledge-base/project/learnings/2026-04-07-bash-single-quote-in-parameter-expansion.md` — Drives the heredoc escaping strategy in Phase 5 and the fallback plan.
- `knowledge-base/project/learnings/best-practices/2026-04-15-negative-space-tests-must-follow-extracted-logic.md` — The `resolve_command_cwd` extraction must be paired with a test that proves the helper is invoked AND the fallback chain works, not just that the helper identifier appears in guardrails.sh.

## Sharp Edges

- `@sh` in jq strips the trailing newline on `@tsv`-adjacent output; keep the one-shot eval form and verify via `echo "$TOOL_NAME"` debug line during dry-run.
- `try (.first_seen | fromdateiso8601) catch 0` returns literal 0 — which compares `< $cutoff` truthy, i.e., it pushes the rule into `rules_unused_over_8w`. This is the desired "seen long ago" behavior but verify in `t_malformed_first_seen`.
- `scripts/lib/rule-metrics-constants.sh` is SOURCED, not executed. shellcheck disable `SC2034` on unused-variable hits. Do NOT add a `main` function.
- The new `test_hook_emissions.sh` cases must use `git init` in `$WORK`, not in the real worktree. Calling `git -C "$WORK/fake/repo" commit -m …` from the test fixture does NOT trigger the real guardrails.sh on the host (the fixture pipes JSON directly to the hook; `guardrails.sh` re-shells out to `git -C` only against the fixture path).
- `rule-prune.sh` regex must match lint-rule-ids.py's `ID_RE` scope (`^(hr|wg|cq|rf|pdr|cm)-[a-z0-9-]{3,60}$`). A drift between these two regex definitions resurrects the validation gap #2257 describes. The constants file does NOT own the regex (bash vs python syntax differ) — comments in both files cite each other.
- heredoc body in rule-prune.sh must escape backticks (`\``) inside the jq query block so bash does not try to command-substitute them. Use a `<<'BODY'` quoted heredoc for the whole body and interpolate `$id`, `$prefix`, `$generated_at` via a prior `envsubst` or a fresh unquoted `<<BODY` with explicit `\$` guards elsewhere. Quoted `<<'BODY'` is simpler but then no interpolation — the plan uses unquoted `<<BODY` with backticks as literals and variables interpolated normally.
- `.claude/.rule-incidents.jsonl` is gitignored. The one-time warn marker uses `/tmp/rule-incidents-warned-$$` — `$$` is the shell PID, so each hook invocation gets its own marker. This is correct: we want one warn PER hook fork, not once globally.
- When the rotation flock re-uses fd 9 (same as the emitter's flock), the two block structures are compatible: both use `9>>"$file"` and request `-x` (exclusive). The OS-level lock is per-file-inode; both callers line up behind the same queue. Do NOT move the rotation flock to a different fd (e.g., `9>>` vs `10>>`) — that would actually create two separate locks on the same inode and reintroduce the race.
- The `@sh` jq filter produces `'escaped-value'` — bash's `eval` interprets the surrounding single quotes as literal-string delimiters. If `tool_input.command` contains a literal newline, `@sh` emits `$'\n'` (ANSI-C quoting) which bash does interpret. Verified via:
  ```bash
  echo '{"tool_input":{"command":"git\nstatus"},"tool_name":"Bash"}' \
    | jq -r '@sh "COMMAND=\(.tool_input.command) TOOL_NAME=\(.tool_name)"'
  # → COMMAND=$'git\nstatus' TOOL_NAME='Bash'
  ```
  This is exactly the behavior `jq -r '.tool_input.command'` produces for the existing `echo "$COMMAND" | grep -qE …` pattern — no regression.
- When the aggregator runs under `AGGREGATOR_ROTATE=1`, the rotate block follows the material-change write. If the write is skipped (idempotent no-op) but `$INCIDENTS` has events from new rule IDs that didn't change the committed JSON shape, those events WILL be rotated out. Acceptable: the jsonl is the truth, the committed JSON is the roll-up. If you want rotation to only happen on material-change, guard the rotate block with `[[ "$write" == "1" ]]`. Plan keeps rotation unconditional on `AGGREGATOR_ROTATE=1` to match the current behavior.
- `scripts/lib/rule-metrics-constants.sh` is sourced by bash scripts. Do NOT export the variables (`export` is unnecessary and makes them inherited by child processes). Plain assignment + `# shellcheck disable=SC2034` is correct.
- Hook invocations use `$CLAUDE_PROJECT_DIR` to resolve the hook path in `.claude/settings.json` (per learning 2026-04-12). The helper function `resolve_command_cwd` added to `lib/incidents.sh` lives inside a sourced file, so its own resolution uses `${BASH_SOURCE[0]}` — no dependency on `CLAUDE_PROJECT_DIR` inside the helper. Do NOT add `$CLAUDE_PROJECT_DIR` references inside the helper; that env-var is only guaranteed in hook execution context, not in general bash.
- The `test_removed_id_exits_1` test must commit AGENTS.md with ids `hr-a` + `hr-b` at HEAD **before** running the lint against the working copy. Use a fresh `git init` temp repo, not the real repo's HEAD. Otherwise, the test depends on the current AGENTS.md snapshot and breaks whenever real rule IDs are added or removed.

## Rollback

Single revert commit reverts all phases. Each numbered commit in the implementation order is self-contained and green on its own, so a partial revert to any intermediate commit leaves the stack working.
