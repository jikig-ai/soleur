# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-03-feat-adopt-merge-queue-advisory-codeql-plan.md
- Status: complete

### Errors
None blocking. Research gap on four GitHub merge-queue behaviors (squash message, pull_request-mode admin bypass, mergeStateStatus for behind-but-queued PR, check_response_timeout exceeded) — recorded in the plan as post-apply canary measurements with fallbacks.

### Decisions
- CLA Required ruleset (cla-check, cla-evidence) lacks merge_group coverage (workflows deleted earlier) — plan restores both and hardens the CLA synthetic; coverage guard spans both rulesets.
- ADR-032 previously rejected queue+advisory-CodeQL; new ADR-269 supersedes; check_response_timeout_minutes=60, SQUASH, ALLGREEN, merge 1 / build 2.
- Alert gate: "new" = no bot-authored open tracking issue; page-and-continue; wait on Analyze (*) check-runs.
- Single PR where merge is the apply (destroy-guard needs [ack-destroy] in merge body); per-command go-ahead before merge; PR body uses Ref not Closes for 9454/4856; 5840 stays open.
- User-Challenge persisted in decision-challenges.md (advisory removes pre-merge blocking of a PR's own findings); brief's direction stays default.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; research/review agents (repo-research, learnings, cto, clo, dhh, kieran, simplicity, best-practices, architecture, security, spec-flow, observability, terraform-architect).
