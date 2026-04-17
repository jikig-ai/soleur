---
branch: feat-review-backlog-workflow-improvements
plan: ../../../plans/2026-04-17-feat-review-backlog-workflow-improvements-plan.md
date: 2026-04-17
---

# Tasks: Review Backlog Workflow Improvements

Derived from `knowledge-base/project/plans/2026-04-17-feat-review-backlog-workflow-improvements-plan.md`.

## Phase 0 — Preflight

- 0.1 Verify `gh`, `jq`, `grep`, `awk` available in the worktree shell
- 0.2 Confirm `deferred-scope-out`, `code-review`, `synthetic-test` labels exist: `gh label list | grep -E '^(deferred-scope-out|code-review|synthetic-test)\b'`
- 0.3 Sanity-check line counts of `plugins/soleur/skills/review/SKILL.md` and `plugins/soleur/skills/plan/SKILL.md` against research snapshot (detect drift before editing)

## Phase 1 — RED Tests (TDD gate)

- 1.1 Create `plugins/soleur/skills/cleanup-scope-outs/scripts/group-by-area.test.sh`
  - 1.1.1 Fixture: clustered (3 issues, same top-level dir) → asserts single cluster of 3
  - 1.1.2 Fixture: dispersed (5 issues, 5 different top-level dirs) → asserts zero cluster meets `--min-cluster-size 3`
  - 1.1.3 Fixture: empty (0 issues) → asserts empty output, exit 0
- 1.2 Run the test → must fail (helper doesn't exist yet) — this is the RED state
- 1.3 Add shell smoke-test fixtures for T4 (pr-introduced → fix-inline) if practical; otherwise document verification steps inline in skill files
- 1.4 Skip fixture work for T1/T2/T3/T5/T8 — those are instruction-file behaviors verified by grep, not code

## Phase 2 — Implement Improvements 1, 2, 3 (skill instruction edits)

### 2.1 `plugins/soleur/skills/review/SKILL.md` — Improvement 2

- 2.1.1 Tighten `cross-cutting-refactor` to require ≥3 unrelated files (with "core change" defined)
- 2.1.2 Tighten `contested-design` to require agent-surfaced tradeoff (not author preference)
- 2.1.3 Add Second-Reviewer Confirmation Gate paragraph at end of `<critical_requirement>` block
- 2.1.4 Verify AGENTS.md rule `rf-review-finding-default-fix-inline` still accurate (criteria count still four)

### 2.2 `plugins/soleur/skills/review/SKILL.md` — Improvement 3

- 2.2.1 Add provenance-tagging bullet to Step 1 Synthesize All Findings
- 2.2.2 Add `Disposition by provenance` block immediately after
- 2.2.3 Update Step 3 Summary Report template to include provenance counts

### 2.3 `plugins/soleur/skills/review/references/review-todo-structure.md` — Improvement 3

- 2.3.1 Add `Provenance:` field to the issue body template
- 2.3.2 Add conditional `Re-eval by:` field (appears only when `Provenance: pre-existing`)

### 2.4 `plugins/soleur/skills/plan/SKILL.md` — Improvement 1

- 2.4.1 Insert `### 1.7.5. Code-Review Overlap Check` after Phase 1.7 and before Phase 2
- 2.4.2 Include the `gh issue list --label code-review --state open` query
- 2.4.3 Include the `jq ... contains($path)` grep pattern
- 2.4.4 Require `## Open Code-Review Overlap` section in every plan output (with `None` when no matches)
- 2.4.5 Specify the three explicit dispositions: fold-in / acknowledge / defer

## Phase 3 — Implement Improvement 5 (new skill + helper)

### 3.1 Create skill directory

- 3.1.1 `mkdir -p plugins/soleur/skills/cleanup-scope-outs/scripts`
- 3.1.2 Create `plugins/soleur/skills/cleanup-scope-outs/SKILL.md` with frontmatter (name, third-person description per plugins/soleur/AGENTS.md compliance)

### 3.2 SKILL.md content

- 3.2.1 Prerequisites section (gh auth, jq, git worktree)
- 3.2.2 Determine-target-milestone section (**default `Post-MVP / Later`** — 15+ of 22 open scope-outs live there at plan time)
- 3.2.3 Query-scope-outs section (invokes helper script)
- 3.2.4 Pick-cluster section (interactive + headless modes)
- 3.2.5 Build-one-shot-scope-argument section
- 3.2.6 Delegate-to-one-shot section
- 3.2.7 Post-delegation backlog-delta reporting
- 3.2.8 Reference PR #2486 as the pattern example
- 3.2.9 Pipeline-detection note (skip interactive if RETURN CONTRACT present)
- 3.2.10 Cross-reference `/soleur:schedule` as post-merge follow-up for programmatic cadence

### 3.3 Helper script `group-by-area.sh`

- 3.3.1 Accept `--milestone`, `--top-n`, `--min-cluster-size` args with defaults (milestone default: `Post-MVP / Later`)
- 3.3.2 Validate milestone title exists before use: `gh api repos/:owner/:repo/milestones --jq '.[] | .title' | grep -Fxq "$MILESTONE"` — fail fast with clear error
- 3.3.3 Query `gh issue list --label deferred-scope-out --state open --milestone "$MILESTONE" --json number,title,body,labels --limit 200` (milestone TITLE, not numeric ID — rule `cq-gh-issue-create-milestone-takes-title`)
- 3.3.4 File-path regex over extensions: ts/tsx/js/jsx/py/rb/go/md/sh/yml/yaml/sql/tf. Use standalone `jq --arg path ...` for safety against regex metacharacters in paths
- 3.3.5 Group by top-level directory ONLY (no second-level sub-grouping — YAGNI, deferred until any single area exceeds 10 issues)
- 3.3.6 Output ALL clusters as JSON to stdout, sorted by cluster size desc (not just the top one — calling skill picks)
- 3.3.7 Skip issues with zero file paths (can't be grouped)
- 3.3.8 Keep under 120 lines of bash, no new deps

### 3.4 Verify tests pass

- 3.4.1 Run `bash plugins/soleur/skills/cleanup-scope-outs/scripts/group-by-area.test.sh` → must pass (GREEN)
- 3.4.2 Run `bun test plugins/soleur/test/components.test.ts` → must pass (skill compliance)

## Phase 4 — Dogfood Verification

- 4.1 Run `/soleur:plan` with a synthetic feature description naming a file in an open code-review issue body → verify `## Open Code-Review Overlap` section in output (T1)
- 4.2 Run `/soleur:plan` with a synthetic feature description naming a non-referenced file → verify `## Open Code-Review Overlap` with `None` (T2)
- 4.3 Invoke `cleanup-scope-outs` in dry-run mode against current backlog → verify sensible cluster selection; do NOT delegate to one-shot during verification

## Phase 5 — Learning + Documentation

- 5.1 Write `knowledge-base/project/learnings/best-practices/2026-04-17-review-backlog-net-positive-filing.md`
  - 5.1.1 Frontmatter: module, date, problem_type=workflow_gap, component=pipeline_skills, symptoms, root_cause, severity=medium, tags=[workflow, code-review, scope-out, backlog]
  - 5.1.2 Body: problem → investigation → solution (with links to the three skill edits and new skill) → regression signal → references
- 5.2 Confirm no AGENTS.md edit needed (existing rule already covers policy)
- 5.3 Confirm no README/plugin.json version bump needed (CI handles via label)

## Phase 6 — Defer-Tracking

- 6.1 File issue: Rolling cap / throttle (brainstorm proposal #4) — label `deferred-scope-out`, milestone Phase 3 or Post-MVP, with Scope-Out Justification
- 6.2 File issue: Telemetry / auto-detection of backlog growth — label `deferred-scope-out`, milestone Phase 3 or Post-MVP
- 6.3 File issue: Analogous tightening of compound's route-to-definition criteria — label `deferred-scope-out`, milestone Post-MVP / Later
- 6.4 File issue: Schedule `cleanup-scope-outs` weekly via `/soleur:schedule` after this PR lands — milestone Phase 3 or later
- 6.5 File issue: Sub-grouping by second-level directory in `group-by-area.sh` — milestone Post-MVP / Later, trigger "any single code area exceeds 10 open scope-outs"

## Phase 7 — Ship

- 7.1 Pre-ship checks (via `/soleur:ship`)
- 7.2 Ensure PR body has `## Changelog` section and `semver:minor` label
- 7.3 PR body uses `Closes #<N>` for any backlog issues directly addressed, `Ref #<N>` for related PRs (#2463, #2477, #2486, #2374)
- 7.4 Monitor Phase 5.5 Review-Findings Exit Gate result (should pass — we produced no new scope-outs on THIS branch)
- 7.5 After merge: run `/soleur:postmerge` to verify release workflow succeeds
