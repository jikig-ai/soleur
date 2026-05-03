---
title: "Rule audit issue remediation — worked example (#2327 → PR #3095)"
date: 2026-05-03
category: best-practices
tags: [governance, agents-md, rule-audit, pr-process]
related:
  - knowledge-base/project/learnings/2026-04-23-agents-md-governance-measure-before-asserting.md
  - knowledge-base/project/learnings/2026-04-21-agents-md-rule-retirement-deprecation-pattern.md
  - knowledge-base/project/learnings/2026-04-07-rule-budget-false-alarm-fix.md
issue: 2327
pr: 3095
---

# Learning: Rule audit issue remediation — worked example

## Problem

`scripts/rule-audit.sh` runs on a cron and files GitHub issues when its
heuristics trip. The audit report from 2026-04-15 (#2327) cited four
remediation classes against AGENTS.md: 4 broken hook references, 1
suspected duplicate, 1 migration candidate, and a "combined budget
over by 34" claim. Eighteen days passed before remediation began.

## Solution

Re-run the audit **before** reading the stale issue body. On 2026-05-03
the actual state was:

- 3 of 4 broken hook refs already removed by intervening PRs (#2865 +
  2026-04-23/24 retirements). Remaining ref (`lint-rule-ids.py`) is a
  false positive from the audit script's `.claude/hooks/`-only
  existence check; the script lives at `scripts/lint-rule-ids.py`
  wired into `lefthook.yml:32`.
- The "migrate `hr-never-git-stash-in-worktrees`" candidate was
  rejected per `cq-agents-md-tier-gate` and the prior measurement of
  pointer-migration savings (+21 bytes net, not the estimated -800).
- The "over by 34" claim was based on a combined-rule-count metric
  that isn't the actual budget — only AGENTS.md is `@`-imported by
  CLAUDE.md, so it alone is always-loaded (22682/37000 bytes = 61%).
- 1 cross-layer duplicate was real and fixed by deleting
  `constitution.md:81`.

Net scope: two surgical text edits + one Phase 5 deferral issue
(#3098) for widening the audit script's path heuristic. Plan at
`knowledge-base/project/plans/2026-05-03-chore-rule-audit-2327-remediation-plan.md`.

## Key Insight

When an audit-cron-filed issue is more than 7 days old, three of its
most common findings classes (broken hook refs, rule counts, duplicate
flags) are likely to be partially or fully stale. Re-run the audit
locally as the first triage action, then build the remediation plan
against the **current** state — not against the issue body. The cost
of one `bash scripts/rule-audit.sh` call is trivial compared to the
cost of editing files based on stale findings.

This is the same pattern documented in
`knowledge-base/project/learnings/2026-04-23-agents-md-governance-measure-before-asserting.md`
("measure, don't estimate"). This PR is a worked example of applying
that framework end-to-end on a multi-finding audit issue.

## Session Errors

- **Triaged the audit findings without re-running the audit first** —
  Recovery: the plan's Phase 0 Research Reconciliation re-measured
  everything against current state. Prevention: when an audit-cron
  issue is >7 days old, run `bash scripts/rule-audit.sh` once before
  reading the issue body.
- **PR body left at auto-generated draft text after `worktree-manager.sh draft-pr`** —
  The `Closes #N` reference landed only in the commit message, which
  is brittle for non-squash merges. Caught by `code-quality-analyst`
  reviewer, fixed inline before merge. Prevention: work-skill or
  ship-skill could backfill PR body with `Closes #N` at push time;
  domain-scoped to those skills, not an AGENTS.md rule.
- **Sub-agent filed deferral issue #3098 without `--milestone`** —
  `wg-when-deferring-a-capability-create-a` requires a milestone on
  deferred-capability issues. Caught by `gh issue view` inspection,
  fixed inline via `gh issue edit --milestone "Post-MVP / Later"`.
  Prevention: `code-quality-analyst` agent's issue-creation prompt
  should require a `--milestone` flag for any issue that closes out a
  Phase N deferral; domain-scoped to that agent.

## Tags

category: best-practices
module: governance
