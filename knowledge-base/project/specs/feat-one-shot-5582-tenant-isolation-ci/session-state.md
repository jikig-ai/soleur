# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-19-fix-tenant-integration-ci-red-5582-plan.md
- Status: complete

### Errors
None. (Two dependabot vulnerability notices on push are pre-existing on the default branch, unrelated to this plan.)

### Decisions
- Two confirmed root causes: (1) migration 112 / PR #5508 dropped `users.{workspace_path, repo_url, github_installation_id}` (ADR-044 PR-2b; moved to `workspaces`) → suites' seed `UPDATE users` throws `42703`; (2) teardown helper's `anonymiseSequence` missing ~13 anonymise RPCs that `account-delete.ts` calls (notably `anonymise_email_triage_items`, `email_triage_items.user_id ... ON DELETE RESTRICT`) → GoTrue `deleteUser` 500s, masked by `withGoTrueRetry`. Premise-refined: issue named #5494/mig 111, but `42703` cause is mig 112/#5508.
- SpecFlow corrected "4 suites" into 10 suites across 3 repair classes; surfaced `github_installation_id` grant-trap (use `resolve_workspace_installation_id` RPC → NULL), membership-scoped-vs-`auth.uid()=id` deny distinction, and `conversations.repo_url` false-positive.
- Scoped as test-code-only: no production code, no migration, no infra. Domain review = engineering only; Product/UX, IaC, GDPR, ADR/C4 gates skipped.
- Deepen pass verified 10/10 load-bearing premises CONFIRMED; folded in P1 scope gap (3 dormant `test/*.integration.test.ts` files with same drift — Phase 7) plus P2s (PGRST202 fatal for RESTRICT-class RPCs, fatality class from FK migrations, synthetic-email literal, source-grep drift guard).
- Scoped out making `tenant-integration.yml` a required check → tracking issue.

### Components Invoked
- Skill: soleur:plan, soleur:deepen-plan
- Agents: repo-research-analyst, learnings-researcher, spec-flow-analyzer, architecture-strategist, general-purpose (verify-the-negative)
