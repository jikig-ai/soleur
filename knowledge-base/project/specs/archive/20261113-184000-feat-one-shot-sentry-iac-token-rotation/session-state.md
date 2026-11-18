# Session State

## Plan Phase

- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-sentry-iac-token-rotation/knowledge-base/project/plans/2026-11-13-feat-sentry-iac-token-rotation-profile-plan.md
- Status: complete

### Errors

- The brief's existing test for the rotation script does not exist; the plan creates one.
- postmerge issue reads already use SENTRY_ISSUE_RO_TOKEN; plan fixes the actual stale pointers.
- First plan write blocked by IaC write guard; cleared after terraform-architect review.
- technical-ruling-gate failed on first decision table; fixed, now passes 14 rows.

### Decisions

- CTO ruling 2026-11-13: issue reads keep SENTRY_ISSUE_RO_TOKEN first, SENTRY_IAC_AUTH_TOKEN last-resort read, monitors stay on SENTRY_AUTH_TOKEN.
- iac profile: org-subdomain host, exact ADR-031 scope set, four probes (project, alert rules, monitors, org issues search).
- Stores in order: GitHub repo secret, Doppler prd, Doppler prd_terraform, all stdin; digest readback; partial failure prints HOLD NEW / UNVERIFIED / STILL HOLD OLD and do NOT revoke the old token yet.
- Doppler has no no-store mode; dry run checks login and configs read-only; test pins the exact store command and input.
- Stdin store chosen over a doppler_secret Terraform resource (would place value in state).

### Components Invoked

- soleur:plan, soleur:plan-review, soleur:deepen-plan; cto, terraform-architect, dhh/kieran/simplicity reviewers.

## Operator Constraints

- constraint: Create a worktree off fresh origin/main under .worktrees. Never git stash.
- constraint: The machine is saturated, do NOT run test-all.sh, run-registered-suites.sh or the full or affected battery locally. Single test files only. Scratch and logs under /var/tmp.
- constraint: No secrets on command lines, never print a secret value. Do NOT mint, rotate, or store any real token.
- constraint: Run prepush-secret-scan.sh, verdict CLEAN, before every push.
- constraint: Merge only via session-state.sh with_lock merge-main 600 -- gh pr merge n --squash --auto, one per Bash call.
- ci-is-the-gate: The machine is saturated, do NOT run test-all.sh, run-registered-suites.sh or the full or affected battery locally. Single test files only.
