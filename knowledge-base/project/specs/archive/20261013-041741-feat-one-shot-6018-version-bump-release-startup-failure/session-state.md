# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-04-fix-version-bump-release-startup-failure-plan.md
- Status: complete

### Errors
None. (One transient hook block on first write — prose contained literal `doppler secrets set` token while stating it was NOT used; rephrased and added `iac-routing-ack` comment; re-write succeeded.)

### Decisions
- Root cause: PR #5977 (60f203c50, 2026-07-04 11:25 UTC) added `id-token: write` to the reusable `release` job for cosign signing; a reusable workflow can only use permissions its caller grants, so the plugin caller (`version-bump-and-release.yml`, only `contents`+`packages`) fails at dispatch with `startup_failure`. This replaces the issue's parse-error/moved-ref/org-secret hypothesis.
- Sibling-precedent fix: PR #5981 (08555a944) already applied the same fix (job-level `id-token: write`) to `web-platform-release.yml` but missed the plugin caller — the plan is a verbatim application of an established pattern (both verified live via `gh pr view`).
- Added drift-guard test (`plugins/soleur/test/reusable-release-caller-permissions.test.sh`) asserting every `reusable-release.yml` caller grants `id-token: write`, to catch the next caller regression.
- Self-verifying merge: the test file lands under `plugins/soleur/**`, matching the caller's path filter, so merging the PR re-triggers the workflow — post-merge verification needs no operator step.
- Scope: confirmed only 2 real callers (`web-platform-release.yml` already fixed, `version-bump-and-release.yml` broken); `apply-deploy-pipeline-fix.yml` references the reusable workflow only in a comment.

### Components Invoked
- Skill: soleur:plan
- Skill: soleur:deepen-plan
- Deepen-plan halt gates (4.4 precedent-diff, 4.6 User-Brand Impact, 4.7 Observability, 4.8 PAT-shaped, 4.9 UI-wireframe) — all PASS
