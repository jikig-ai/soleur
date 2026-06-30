# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-18-feat-adr-044-pr2b-drop-legacy-users-columns-plan.md
- Status: complete

### Errors
None. (IaC-routing gate required an opt-out ack — zero infra; worktree-write guard required absolute path; one deepen 4.7 false-positive on literal "ssh" in a comment, reworded.)

### Decisions
- Confirmed against source: index `users_github_installation_id_unique_idx` = partial-UNIQUE ON users(github_installation_id) WHERE NOT NULL (mig 052:159-161); workspace_path `text NOT NULL DEFAULT ''` (mig 001:9), repo_url `text` (mig 011:6), github_installation_id `bigint` (mig 011:8).
- Migration number = **112** (collision-checked vs local + origin/main; 110 is highest; AC0.6 re-checks at work-start).
- down.sql = ADD COLUMN IF NOT EXISTS ×3 (original types) + CREATE UNIQUE INDEX IF NOT EXISTS + verbatim mig-052 COMMENT. Schema-only; column DATA not recoverable (stated in header). No bare BEGIN/COMMIT (run-migrations.sh wraps in --single-transaction; mirror mig 110).
- DB-types: NO generated database.types.ts — hand-written lib/types.ts. `interface User` carries only `workspace_path` of the three (repo_url at :594 is Conversation.repo_url, out of scope). Removing User.workspace_path is a SAFE straight delete (synthesized objects use KbRouteContext.userData shape); tsc is the backstop.
- Drop is safe: mig-052 UNIQUE's cross-tenant guarantee replaced live by the `{found|none|ambiguous|db-error}` resolver (>1 fail-closed) + github_webhook_founder_ambiguous Sentry rule (issue-alerts.tf:576). Precise reader sweep = 0 live users.* readers; gdpr-gate no Critical (data-minimisation-positive). ADR-044 adopting→accepted flip + closure amendment in scope; no .c4 edit.
- Work-start ACs: re-run multi-line reader sweep (0 live readers) AND re-run drift gate (COUNT=0) BEFORE applying.

### Components Invoked
Skills: soleur:plan, soleur:gdpr-gate, soleur:deepen-plan. Agents: repo-research-analyst, learnings-researcher, data-migration-expert, data-integrity-guardian, deployment-verification-agent, user-impact-reviewer, verify-the-negative.
