---
module: web-platform
date: 2026-04-22
problem_type: integration_issue
component: data_migration
symptoms:
  - "SQL migration regex chain diverges from TS normalizer for trailing-slash inputs"
  - "TS+SQL normalizer both non-idempotent on repeated suffixes (.git.git)"
  - "Plan's file-path and site-count assumptions stale against current working tree"
  - "Agent-native parity audit missed a UI action (updateStatus)"
root_cause: ts_sql_regex_chain_drift_plus_incomplete_plan_reconciliation
severity: high
tags: [normalizer, backfill-migration, sql-ts-parity, idempotence, agent-native-parity, drain-pr]
synced_to: [plan, work]
---

# TS/SQL Normalizer Parity Is a First-Class Concern When Shipping a Backfill Migration Alongside a Write-Boundary Normalizer

## Problem

PR #2817 (drain batch closing #2775 + #2776 + #2777) introduced `normalizeRepoUrl` in TypeScript at `apps/web-platform/lib/repo-url.ts` and a parallel Postgres regex chain in `apps/web-platform/supabase/migrations/031_normalize_repo_url.sql` to backfill existing rows to the canonical form.

Two independent review agents (data-integrity-guardian, data-migration-expert) each caught a P1 operator-precedence bug: the SQL stripped `.git$` BEFORE trailing `/+$`, so `https://github.com/Owner/Repo.git/` normalized to `https://github.com/Owner/Repo.git` (left `.git` behind) while the TS normalizer correctly produced `https://github.com/Owner/Repo`. The backfill migration would have written divergent values to the DB, breaking the contract the whole PR was designed to establish — write-boundary and read-boundary agreeing on equality.

A third reviewer (security-sentinel) caught a non-idempotency bug in **both** TS and SQL: `\.git$/i` strips only one trailing `.git`, so `bar.git.git` normalizes to `bar.git`, gets stored, re-read, re-normalized to `bar`, and scope-drifts across the application.

A fourth reviewer (agent-native-reviewer) caught a parity gap: the plan scoped "list + archive + unarchive" MCP tools but missed `updateStatus` — the Command Center's most common user action had no agent equivalent.

## Solution

Three inline fixes applied on the PR branch (commit `83ddf964`):

### 1. SQL order-of-operations: mirror TS three-pass order

Before (migration 031):

```sql
regexp_replace(
  regexp_replace(
    LOWER(...) || COALESCE(..., ''),
    '\.git$', '', 'i'),   -- strip .git FIRST
  '/+$', '', 'g')         -- then trailing /
```

After:

```sql
regexp_replace(
  regexp_replace(
    regexp_replace(
      LOWER(...) || COALESCE(..., ''),
      '/+$', '', 'g'),      -- strip trailing / FIRST
    '(\.git)+$', '', 'i'),  -- then .git (one or more)
  '/+$', '', 'g')           -- then any / the .git strip exposed
```

TypeScript already did this order correctly (three passes: `/+$` → `.git$` → `/+$`).

### 2. Idempotent `.git` strip: `(\.git)+$` not `\.git$`

Both TS and SQL changed `\.git$/i` → `(\.git)+$/i`. Now `bar.git.git` collapses to `bar` in one pass. Added regression test cases for `bar.git.git` and `bar.git.git/` plus the idempotence fixture table. Still suffix-anchored: `bar.git.bak` is untouched.

### 3. Missing `conversation_update_status` MCP tool

Added the fourth mutation tool in `apps/web-platform/server/conversations-tools.ts`. Same three-column WHERE backstop (`id`, `user_id`, `repo_url`) as `conversation_archive`. Reuses `STATUS_VALUES` from the canonical `STATUS_LABELS` type so MCP-side validation cannot drift from the UI's `updateStatus` hook.

## Key Insight

**When a PR ships a backfill migration alongside a new normalizer, the SQL and the TS are TWO implementations of the same function — and they WILL drift.** The WHERE-clause idempotence guard (`repo_url <> <normalized-expr>`) is necessary but not sufficient — it only catches drift on re-runs, not on first apply. The cheap way to catch drift pre-merge: run every fixture from the TS unit test through the SQL expression via a `WITH fixtures AS (VALUES ...)` SELECT and assert equality. The expensive way: ship the migration to prod, discover the bug when users' conversations silently go dark, then roll back a lossy migration that has no recovery path.

**Corollary for idempotence:** a normalizer's idempotence contract must hold for **repeated suffixes**, not just single ones. An input like `bar.git.git` is a real possibility (user pastes a URL twice, tooling double-suffixes, etc.). The idempotence test table must include at least one repeated-suffix fixture per strip-class.

**Corollary for agent-native parity:** "list + archive" is the lazy parity audit. The exhaustive one is `grep -E "^\s*(const|function|async function)" <hook-file> | head` — enumerate every public surface of the UI hook and map each to an MCP tool or an explicit deferral. Missing `updateStatus` on an audit aimed at parity is a process bug, not a planning bug.

## Prevention

1. **SQL/TS normalizer parity probe during work phase.** When a work plan prescribes porting a TS regex chain to SQL for a backfill, run every fixture from the TS unit test file through the SQL expression before committing the migration. Two sample shapes: (a) inline `psql -c "SELECT <expr>"` for each fixture, (b) a `WITH fixtures AS (VALUES (<input>, <expected>), ...)` CTE that asserts equality. Document the parity check result in the migration commit message.

2. **Idempotence tests must include repeated-suffix fixtures.** Every strip-class in a normalizer needs at least one doubled fixture (`.git.git`, `//`, trailing-whitespace-squeezed, etc.). Single-instance fixtures are a single-point-of-failure pass criterion.

3. **Plan-to-codebase reconciliation during plan phase.** Three plan errors this session all had the same class: the plan paraphrased the issue body instead of verifying against the working tree.
   - #2777 claimed 4 `createQueryBuilder` sites; actual is 3.
   - #2776 claimed the MCP tools live at `lib/mcp/conversations-tools.ts`; actual is `server/conversations-tools.ts`.
   - #2776 claimed the existing test had a negative assertion to invert; actual test was simpler.
   Fix: plan skill Phase 1 should grep/Read EVERY file path and symbol the issue body names and surface divergences in a §Research Reconciliation table (this session's plan DID do this during deepen-plan — move the gate earlier).

4. **Agent-native parity audit enumerates hook surface.** When adding MCP tool parity for a UI action set, read the UI hook's exported surface (`grep -E "^\s*(const|function|async function)"`) and map every public function to a tool or an explicit deferral. Don't trust the issue body's enumeration.

5. **Second-reviewer CONCUR gate worked.** `code-simplicity-reviewer` co-signed the `pre-existing-unrelated` claim for the scope-out filing (#2825) with advisory notes that escalated `/api/repo/status` as a client-facing leak for #2244's implementer. Keep using this gate — it caught context the primary reviewer missed.

## Session Errors

1. **Work subagent ran `git stash --include-untracked` in a worktree during Phase 1** to inspect a baseline. Violates `hr-never-git-stash-in-worktrees`. Recovery: `git stash pop` restored state. **Prevention:** work-skill Phase 2 could remind "use `git show HEAD:<path>` to inspect old code instead of stashing." A PreToolUse hook blocking `git stash` inside `.worktrees/` would be stricter (the existing hook already does this for `guardrails:block-stash-in-worktrees` — the subagent may have hit a context where the hook wasn't in effect).

2. **Plan's "4 createQueryBuilder sites" was stale — actual count is 3.** The 4th file (`ws-deferred-creation.test.ts`) uses a different predicate-aware chain mock shape, not the same helper. Deepen-plan caught and documented this in plan §Research Reconciliation. **Prevention:** plan skill Phase 1 should grep every symbol the issue body names (`rg '^function <symbol>\b' <dir>`) and verify the count before writing the plan.

3. **Plan prescribed `lib/mcp/conversations-tools.ts`; actual path is `server/conversations-tools.ts`.** Caught at deepen-plan. **Prevention:** plan skill Phase 1 should Read every file path the issue body names before prescribing edits — a single `ls` on the claimed path would have caught it.

4. **Original SQL migration 031 had an operator-precedence bug** — stripped `.git` before trailing `/`. Caught only at review. **Prevention:** work-skill Phase 2 "SQL/code normalizer parity" step (see Prevention #1 above) — run fixtures through the SQL before committing.

5. **TS+SQL normalizer non-idempotent on `bar.git.git`.** Caught at review. **Prevention:** test-design gate requiring repeated-suffix fixtures in idempotence tables (see Prevention #2).

6. **Plan's agent-native parity audit missed `updateStatus`.** Caught at review. **Prevention:** enumerate UI hook exports during plan phase (see Prevention #4).

7. **Full-suite vitest concurrency flake (16 tests failed in full sweep, all pass in isolation).** Pre-existing on main; not a regression. No action.

## References

- PR #2817 — the drain batch
- Issues closed: #2775, #2776, #2777
- Related deferred: #2825 (inline .replace sites in kb-route-helpers + repo/status), #2244 (syncWorkspace migration that will fold them in), #2778 (projects-table architectural pivot, left deferred)
- Origin PR: #2766 (`conversations.repo_url` scoping work)
- Drain pattern reference: PR #2486 (one PR, three closures)
- Migration 029 coupling invariant comment: `apps/web-platform/supabase/migrations/029_conversations_repo_url.sql` — "any future normalization of users.repo_url MUST also rewrite this column in the same migration"
