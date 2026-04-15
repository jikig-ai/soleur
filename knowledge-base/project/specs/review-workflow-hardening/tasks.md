---
title: Tasks — Review Workflow Hardening
plan: knowledge-base/project/plans/2026-04-15-refactor-review-workflow-hardening-plan.md
spec: knowledge-base/project/specs/review-workflow-hardening/spec.md
branch: review-workflow-hardening
pr: 2375
issue: 2374
---

# Tasks — Review Workflow Hardening

Derived from the plan. Phases map 1:1 to the plan's Implementation Phases. Each task includes a success-check command from the plan so `/soleur:work` can verify completion.

## Phase 1: Foundation

### 1.1 Create `deferred-scope-out` GitHub label

- [x] Run: `gh label create deferred-scope-out --description "Review-origin issue that meets a scope-out criterion — does not block ship Phase 5.5" --color ededed || true`
- [x] Verify: `gh label list --json name --jq '.[] | select(.name == "deferred-scope-out") | .name'` returns `deferred-scope-out`.

### 1.2 Append new AGENTS.md rule

- [x] Read `AGENTS.md` at the `## Review & Feedback` section.
- [x] Append the new bullet with ID `[id: rf-review-finding-default-fix-inline]` per plan Phase 1.2 (exact text in plan).
- [x] Verify: `grep -c '\[id: rf-review-finding-default-fix-inline\]' AGENTS.md` returns 1.
- [x] Verify: `python3 scripts/lint-rule-ids.py` exits 0.

## Phase 2: Behavior Edits

### 2.1 Rewrite `/review` SKILL.md Section 5

- [x] Read `plugins/soleur/skills/review/SKILL.md:287-358`.
- [x] Replace `<critical_requirement>` at line 289 with the block in plan Phase 2.1 (inlines four scope-out criteria + body-template rules).
- [x] Update `<critical_instruction>` at line 312 to "Fix inline or, where a scope-out criterion applies, create a `deferred-scope-out` issue."
- [x] Update Step 3 Summary Report headings (lines 332-347): split `### Created GitHub Issues` into `**Fixed Inline:**` and `**Filed as Deferred Scope-Out:**` sub-sections.
- [x] Update coupling note at line 308: append the Phase 5.5 Review-Findings Exit Gate cross-reference per plan.
- [x] Verify: `grep -c 'default action is to FIX IT INLINE' plugins/soleur/skills/review/SKILL.md` returns 1.

### 2.2 Rewrite `/compound` SKILL.md Route Learning to Definition

- [x] Read `plugins/soleur/skills/compound/SKILL.md:255-270`.
- [x] Replace step 3 at line 265 with the default-edit block in plan Phase 2.2 (direct bullet-append, bounded surface).
- [x] Add step 4 (file-issue exception for cross-skill / contested / agents-md-semantic-change cases) per plan.
- [x] Add step 5 (interactive confirmation for direct edits) per plan.
- [x] Keep "Graceful degradation" line (270) unchanged.
- [x] Verify: `grep -c 'Default action (interactive and headless): Apply the edit directly' plugins/soleur/skills/compound/SKILL.md` returns 1.

### 2.3 Add `/ship` Phase 5.5 Review-Findings Exit Gate

- [x] Read `plugins/soleur/skills/ship/SKILL.md:268-284`.
- [x] Insert new `### Review-Findings Exit Gate (mandatory)` subsection between line 282 (end of Code Review Completion Gate) and line 284 (Pre-Ship Domain Review intro).
- [x] Use the exact detection block from plan Phase 2.3 (jq regex filter, synthetic-test + deferred-scope-out label exclusions, single abort path, retry-once on 5xx).
- [x] Verify: `grep -c '### Review-Findings Exit Gate (mandatory)' plugins/soleur/skills/ship/SKILL.md` returns 1.

### 2.4 Markdown lint

- [x] Run: `npx markdownlint-cli2 --fix plugins/soleur/skills/review/SKILL.md plugins/soleur/skills/compound/SKILL.md plugins/soleur/skills/ship/SKILL.md AGENTS.md`.
- [x] Re-read each file after fix (per `cq-always-run-npx-markdownlint-cli2-fix-on`).

## Phase 3: Validation

### 3.1 Gate detection test on live repo

- [x] Create synthetic issue with `synthetic-test` label + body `Ref #2375` per plan Phase 3.1.
- [x] Run all four detection-query variants (with/without synthetic-test exclusion; with/without deferred-scope-out). Capture expected-vs-actual COUNT values.
- [x] Close synthetic issue with documented rationale.
- [x] Capture evidence in PR description.

### 3.2 Regex boundary test

- [x] Create second synthetic issue with body `Ref #23750`. Run detection for PR 2375. Expect 0 matches.
- [x] Close after verification.

### 3.3 Self-dogfood `/review` on this PR

- [ ] Run `skill: soleur:review` on PR #2375.
- [ ] Each finding must either be fixed inline (commit on branch) or filed with `deferred-scope-out` + `## Scope-Out Justification`.
- [ ] Re-run Phase 5.5 gate query — expect COUNT == 0.

### 3.4 Final lint

- [x] `python3 scripts/lint-rule-ids.py` exits 0.
- [x] `npx markdownlint-cli2 --fix` on all edited `.md` files passes.

## Phase 4: Deferral Tracking (Workflow-Gate Compliance)

### 4.1 Create Follow-up A — Backlog Triage

- [x] `gh issue create --title "Backlog triage: classify 53 review-origin issues against rf-review-finding-default-fix-inline" --milestone "Post-MVP / Later" --body-file /tmp/followup-a.md` with body covering:
  - What: classify 53 open issues (2026-04-13→2026-04-15) as fix-now / valid-defer / invalid.
  - Why: retroactive application of the new rule to the case that exposed the gap.
  - Re-evaluation criteria: run within 7 days after this PR merges.
  - Methodology: invoke `ticket-triage` agent against the exact corpus query pinned here.

### 4.2 Create Follow-up B — Regression Telemetry

- [x] `gh issue create --title "Regression telemetry: per-PR review_issues_per_merged_pr metric + email alert" --milestone "Post-MVP / Later" --body-file /tmp/followup-b.md` with body covering:
  - What: extend `scripts/rule-metrics-aggregate.sh` + `.github/workflows/rule-metrics-aggregate.yml` with per-PR review-issue ratio + notify-ops-email alert (threshold 3).
  - Why: regression detection if the Phase 5.5 gate is ever bypassed or weakened.
  - Re-evaluation criteria: **build only if a second spike (>3 review-origin issues on any single PR) occurs in the 2 weeks after this PR merges.** Until then, the hard merge-block is sufficient.

### 4.3 Record follow-up issue numbers in PR description

- [x] After both follow-ups are filed, update the PR description to list them under a `## Follow-ups` section.

## Phase 5: Ship

- [ ] Run `skill: soleur:compound` (per `wg-before-every-commit-run-compound-skill`).
- [ ] Mark PR #2375 ready via `skill: soleur:ship` — the new Phase 5.5 Review-Findings Exit Gate self-dogfoods here.
- [ ] Queue auto-merge: `gh pr merge 2375 --squash --auto`.
- [ ] Poll `gh pr view 2375 --json state --jq .state` via Monitor tool until MERGED.
- [ ] Run `cleanup-merged` to clean the worktree.
- [ ] Post-merge: verify workflows succeed per `wg-after-a-pr-merges-to-main-verify-all`.

## Dependency Graph

```text
Phase 1 (Foundation)
  ├── 1.1 label
  └── 1.2 AGENTS.md rule  ──┐
                            │
Phase 2 (Behavior Edits) ◄──┤
  ├── 2.1 /review SKILL.md
  ├── 2.2 /compound SKILL.md
  ├── 2.3 /ship SKILL.md (new gate)
  └── 2.4 markdownlint
                            │
Phase 3 (Validation) ◄──────┤
  ├── 3.1 gate detection test
  ├── 3.2 regex boundary test
  ├── 3.3 self-dogfood /review
  └── 3.4 final lint
                            │
Phase 4 (Deferral Tracking) ◄── (can run in parallel with Phase 3)
  ├── 4.1 Follow-up A issue
  ├── 4.2 Follow-up B issue
  └── 4.3 PR description update
                            │
Phase 5 (Ship) ◄────────────┘
  (requires Phases 1-4 complete)
```

Phase 1 is strictly sequential before Phase 2 (rule ID is referenced in skill edits). Phase 3 and Phase 4 are independent and can run in parallel. Phase 5 requires all prior phases.
