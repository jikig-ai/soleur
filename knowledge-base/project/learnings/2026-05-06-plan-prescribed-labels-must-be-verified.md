# Learning: Plan-prescribed GitHub labels must be verified against the repo's label set

## Problem

The plan for PR #3378 (`knowledge-base/project/plans/2026-05-06-fix-x-robots-tag-api-noop-comment-plan.md`) prescribed GitHub labels `infrastructure` and `seo` in its Acceptance Criteria for the post-merge re-evaluation tracking issue. At issue-creation time, neither label existed in the `jikig-ai/soleur` repo. `gh label list --limit 200` showed the closest available labels were `domain/engineering`, `chore`, and `priority/p3-low`.

If the plan's AC had been applied verbatim, `gh issue create --label "infrastructure" --label "seo"` would have failed with "label not found" and forced a recovery substitution at issue-creation time — exactly what happened.

The plan's deepen-plan phase did not verify the prescribed labels against the repo's actual label set.

## Solution

1. Ran `gh label list --limit 200` to enumerate the actual label set.
2. Substituted the prescribed labels with the closest existing labels: `domain/engineering`, `chore`, `priority/p3-low`.
3. Recorded the substitution rationale in the plan's AC line in the same commit.
4. Created issue #3379 with the substituted labels.

## Key Insight

The existing rule `cq-gh-issue-label-verify-name` covers `/soleur:drain-labeled-backlog` (which queries by label and would silently match zero issues if a label is misnamed). It does NOT cover the plan and deepen-plan skills, which prescribe labels in Acceptance Criteria for tracking issues to be created post-merge. The verification surface is different (plan-time, not query-time) but the underlying class — "claim about labels not verified against the repo's actual label set" — is the same.

The fix routes a Sharp Edges bullet to `plugins/soleur/skills/plan/SKILL.md` and the Quality Checks list of `plugins/soleur/skills/deepen-plan/SKILL.md` so the verification step is enforced at plan-time, not deferred to issue-creation-time recovery.

## Session Errors

**Error 1: Plan-prescribed labels not verified at plan time.**

- What happened: Plan AC named `infrastructure` and `seo` labels; neither existed in the repo. Substituted at issue-creation time.
- Recovery: `gh label list --limit 200` to enumerate, substitute closest matches, document substitution in the plan AC.
- **Prevention:** When the plan or deepen-plan skill prescribes GitHub labels in Acceptance Criteria (e.g., for tracking issues created post-merge), verify each label exists via `gh label list --limit 200 | grep -E "^<label>\b"` BEFORE writing the AC. If a label doesn't exist, either (a) substitute the closest existing label and document the choice in the AC, or (b) add a Phase 0 step "create the label first" with `gh label create`.

This error was discoverable (would have surfaced as `gh issue create --label "infrastructure"` → "label not found" at issue-creation time), so per the discoverability exit in `wg-every-session-error-must-produce-either`, a learning file alone (plus skill edits) suffices — no AGENTS.md rule is added.

## Tags

- category: workflow
- module: plan, deepen-plan
- related: cq-gh-issue-label-verify-name
- related-prs: #3378
