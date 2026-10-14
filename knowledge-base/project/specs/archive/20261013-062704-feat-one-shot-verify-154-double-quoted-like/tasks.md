# Tasks: fix verify/154 double-quoted LIKE literal

Plan: knowledge-base/project/plans/2026-10-04-fix-verify-154-double-quoted-like-literal-plan.md
Refs #8609 (never `Closes #8211`). Draft PR #9467. No workflow dispatch; do not touch verify/155 (#9456).

## Phase 1: Guard first (TDD RED)

- 1.1 Create apps/web-platform/test/supabase-migrations/verify-sql-string-literals.test.ts
  - 1.1.1 Helper: strip `--` comments, `/* */` comments, `'...'` literals (`''` escapes), `$$...$$` bodies
  - 1.1.2 Directory case: resolve `join(__dirname, "../../supabase/verify")`; assert files.length > 0; assert no `"` remains per file; report file:line
  - 1.1.3 Inline RED fixtures: original defect; compliant-first + defective-second `ILIKE "..."`
  - 1.1.4 Inline must-PASS fixtures: `LIKE '%"x"%'`, `-- = "x"`, `/* LIKE "x" */`, `$$ "x" $$` body, `'it''s'`
  - 1.1.5 Comment documenting limits (E'' strings, nested block comments; fail loud, not silent)
- 1.2 Run `cd apps/web-platform && npx vitest run test/supabase-migrations/verify-sql-string-literals.test.ts` against UNFIXED 154; confirm RED naming 154...sql:14

## Phase 2: Fix

- 2.1 Edit apps/web-platform/supabase/verify/154_inbox_item_idempotent_rearchive.sql line 14 to `LIKE '%status = ''archived'' THEN RETURN%'`
- 2.2 Re-run the targeted vitest file; confirm GREEN
- 2.3 Run AC1 sweep (`grep -n '"' verify/*.sql` minus comment lines) and confirm empty

## Phase 3: Prove the fixed file executes (scratch Postgres, no prod)

- 3.1 `docker run --rm -d postgres:16-alpine`; `SET check_function_bodies = off`; apply 154's CREATE OR REPLACE FUNCTION
- 3.2 Run fixed verify/154 with `psql -tAF $'\t'`; expect `0` and `0`
- 3.3 Apply 122's function statement; expect `idempotent_rearchive 1` (discrimination)
- 3.4 Remove the container; paste recipe + outputs in the PR body

## Phase 4: Follow-up + PR

- 4.1 File the issue "verify-migrations skipped on the workflow_run arm" (milestone, priority label; unproven-hypothesis + dry-run + structural-option notes)
- 4.2 PR body: `Refs #8609`, link the follow-up, Phase 3 output; confirm diff touches only the 154 verify file, the new test, plan/spec artifacts
