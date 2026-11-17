# Session State: feat-one-shot-12332-sibling-changed-path-readers

## Plan Phase

- Plan: `knowledge-base/project/plans/2026-11-07-fix-sibling-changed-path-readers-plan.md`
- Decisions: `knowledge-base/project/specs/feat-one-shot-12332-sibling-changed-path-readers/decision-challenges.md`
- Draft PR: #12357. Issue: #12332 (PR closes it). Arc tracker: Ref #12246 only.

## Operator Constraints

- constraint: Rely on CI's required checks (test, lockfile-sync, markdown-lint, tenant-integration-required); read infra-validation and sandbox-canary-capture-gate by hand when they appear; do not run the local affected battery to completion.
- ci-is-the-gate: Rely on CI's required checks (test, lockfile-sync, markdown-lint, tenant-integration-required); do NOT run the local affected battery to completion.
- constraint: Never push to a PR in the merge queue (bash plugins/soleur/scripts/sync-pr-behind.sh <PR> --queue-state); never --admin merge; never touch the ruleset; if the queue dequeues a PR a second time, stop and report before re-arming.
- constraint: Technical forks go to the CTO agent, legal wording to the CLO agent, never the operator. Poll with Monitor, never Bash run_in_background. No SSH, no pgrep -f, no bare pipe into grep -q. git add and git commit in separate calls; check a push's real exit code.
- constraint: Do not touch apps/web-platform/test/claude-pin-lockstep.test.ts; leave the stale-accept row for real-sdk-ask-probe-workflow.test.sh alone; do not create or edit plugins/soleur/skills/cve-exposure/ or its go.md routing (draft PR 12343 owns it).
- constraint: Done = PR merged with required checks green, then deploy-arm.sh find --wait <full-sha>, deploy-arm.sh served <full-sha> = CONTAINS, and /health on app.soleur.ai with supabase connected.
