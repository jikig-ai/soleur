---
title: "Tasks — fix CLA digest bot identity"
branch: feat-one-shot-cla-digest-bot-identity
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-03-fix-cla-digest-bot-identity-plan.md
---

# Tasks — fix CLA Assistant CI failure on community-digest PRs

Derived from `knowledge-base/project/plans/2026-06-03-fix-cla-digest-bot-identity-plan.md`.

## Phase 1 — Primary fix (Dockerfile global identity)

- [ ] 1.1 Edit `apps/web-platform/Dockerfile:137`: replace `user.name "Soleur"` / `user.email "soleur@localhost"` with `user.name "github-actions[bot]"` / `user.email "41898282+github-actions[bot]@users.noreply.github.com"` (static-string swap, no shell interpolation). [AC1, AC4]
- [ ] 1.2 Confirm `grep -c 'soleur@localhost' apps/web-platform/Dockerfile` returns 0 and the github-actions[bot] name/email lines are present. [AC1]
- [ ] 1.3 Confirm no other git-identity site references `soleur@localhost` (only Dockerfile + plan/learnings prose).

## Phase 2 — Defense-in-depth + non-regression (no code change beyond Phase 1)

- [ ] 2.1 Verify the prompt-level local `git config` at `cron-community-monitor.ts:181-182` is RETAINED unchanged. [AC2]
- [ ] 2.2 Verify `push-branch.ts` still sets `AGENT_AUTHOR_NAME`/`AGENT_AUTHOR_EMAIL` locally (Concierge non-regression; no edit). [AC3]

## Phase 3 — Ship discipline

- [ ] 3.1 PR body uses `Ref #4907` (NOT `Closes #4907`) — closure is gated on deploy, not merge. [AC5]
- [ ] 3.2 Run pre-merge AC greps (AC1, AC2, AC3) on the branch; all pass.

## Phase 4 — Post-merge / immediate unblock (operator-gated on deploy)

- [ ] 4.1 After merge, confirm `web-platform-release.yml` rebuilt + deployed the new image (deploy-status webhook or release-workflow success). [AC6]
- [ ] 4.2 Resolve PR #4907 per chosen path — RECOMMENDED: `gh pr close 4907` with superseded-by comment; let next digest regenerate. (Alternative: amend digest-commit author + force-push + re-trigger cla-check.) [AC8]
- [ ] 4.3 On the next community-digest PR (natural 0 8 * * * UTC or `cron/community-monitor.manual-trigger`), confirm `cla-check` = SUCCESS. This is the real validation (pull_request_target runs base-branch workflow). [AC7]

## Notes

- Single code change: `apps/web-platform/Dockerfile` line 137.
- The merge does NOT immediately fix #4907 (old image carries the old commit). Future digest commits inherit the new identity once deployed.
- Keep the seven sibling crons' local `git config` steps untouched; cohort-wide retirement is a separate follow-up if desired.
