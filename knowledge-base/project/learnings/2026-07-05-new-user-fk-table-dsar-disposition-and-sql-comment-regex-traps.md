# Learning: A new user-FK table's DSAR disposition is Art. 15 access by default; SQL column-comment `);` breaks the table-parse test regex

- **Date:** 2026-07-05
- **Feature:** feat-severity-ranked-inbox (#6007, ADR-085) — new `inbox_item` operational-notification table
- **Category:** database-issues / security-issues

## Problem

Shipping a new `user_id`-FK table (`inbox_item`) surfaced two recurring traps that the inline test loop missed and only later gates / multi-agent review caught:

1. **DSAR disposition mis-classified.** The first cut EXCLUDED `inbox_item` from the DSAR export (`DSAR_TABLE_EXCLUSIONS`) reasoning "server-generated pointers; the referenced data is exported via its own table." `data-integrity-guardian` flagged this as a P2: the reasoning conflated the **Art. 20 portability** test ("is it user-*provided*?") with the **Art. 15 access** test ("is it personal data the controller processes about the subject?"). The row's `created_at`/`read_at`/`acted_at`/`archived_at` are the subject's *notification-interaction history* — controller-generated personal data held in **no other allowlisted table**. The sibling `email_triage_items` is allowlisted on exactly this basis.

2. **SQL column-comment `);` truncated a test's table parser.** `test/dsar-allowlist-completeness.test.ts` parses each migration's `CREATE TABLE (...)` body with a non-greedy regex `\(([\s\S]*?)\)\s*;` and then checks `\b<ownerField>\b\s+uuid`. An inline column comment `-- NULL = a workspace-broadcast (visible to every Owner); set = …` contained `)` immediately followed by `;`, which the non-greedy parser mistook for the table's closing `);` — truncating the captured columns before `user_id uuid`. The `ownerField` check then failed against a correct migration.

## Solution

1. **Allowlist the table for Art. 15 access**, not exclude it:
   ```ts
   inbox_item: { ownerField: "user_id", article: "15" },
   ```
   `ownerField: "user_id"` naturally scopes the export to TARGETED rows and excludes `user_id IS NULL` broadcasts (workspace-level, not personal to a subject). Allowlisting is not free — the completeness + `dsar-worker-per-row-where` tests require an explicit `service.from("inbox_item").select("*").eq("user_id", …)` + `assertReadScope` block in `server/dsar-export.ts`. Wire it in the same PR.

2. **Reword the comment to drop `);`**: `(visible to every Owner);` → `a workspace-broadcast visible to every Owner;`. Verify with a quick node harness that the parser captures the full body: `sql.matchAll(/create table … \(([\s\S]*?)\)\s*;/gi)` → assert the captured group contains `archived_at` (the last column).

## Key Insight

- **For any new `public.*` table with a `user_id`/user FK, the DSAR default is Art. 15 ACCESS inclusion (`DSAR_TABLE_ALLOWLIST`), not exclusion — even for "derivative"/content-minimized rows.** Ask the Art. 15 question ("is this personal data the controller *processes about* the subject?"), not the Art. 20 question ("did the user *provide* it?"). Row lifecycle timestamps (created/read/acted/archived) are Art. 15 data held nowhere else. Exclusion is reserved for genuinely non-personal operational state (concurrency slots, rate windows) or PII already covered by an Art. 17 cascade (dsar meta). The `dsar-allowlist-completeness` full-suite test enforces that *some* disposition exists — but it cannot tell you the disposition is *correct*; that judgment is the reviewer's (`data-integrity-guardian`).
- **Never write `)` immediately followed by `;` inside a SQL column-body comment.** Test/lint regexes that parse `CREATE TABLE (...)` non-greedily to `)\s*;` will treat the comment's `);` as the table terminator and silently truncate the parsed columns — a green migration then fails a shape/column test for a bogus reason. Same class as the grep-over-script-body comment-collision traps: comments are inside the parsed body.

## Session Errors

1. **Stray worktree created** — ran the work SKILL's literal example `worktree-manager.sh --yes create feature-branch-name` while already inside the target worktree. Recovery: `git worktree remove --force` + `git branch -D`. **Prevention:** the worktree-create step is conditional on being on the default branch; when already on a feature-branch worktree, skip it — the SKILL's command is a placeholder example, not a step to run verbatim.
2. **Bash CWD drift** (repeated) — the Bash tool's CWD did not persist; `cd apps/web-platform` failed and relative `sed`/`ls`/`vitest` broke. Recovery: cd-chained every call. **Prevention:** always `cd <abs> && <cmd>` in one call or use absolute paths (existing learning; reinforced).
3. **ADR ordinal collision (ADR-075 taken)** — the plan's provisional ADR number was already assigned (agent-sandbox isolation) on origin/main; wrote ADR-075 refs then fixed to ADR-085. **Prevention:** re-derive next-free ADR ordinal via `git ls-tree origin/main …/decisions | grep -oE 'ADR-[0-9]+'` BEFORE writing any reference — the plan's provisional number is stale by ship time (existing learning; reinforced).
4. **ADR-035 filename/frontmatter mismatch** — cited a fabricated `ADR-035-dashboard-today-feed.md`; the real dedup ADR is *filename* `ADR-037-…` with *frontmatter* `adr: 035` (repo has a filename↔ordinal drift). **Prevention:** `ls` + read the actual ADR file before citing; never invent a filename from the number, and when the filename ordinal ≠ frontmatter ordinal, cite the real filename explicitly.
5. **DSAR disposition initially wrong** — see Problem #1. **Prevention:** the Art. 15-not-20 rule above.
6. **Two P1 correctness bugs in the first cut** (caught by multi-agent review, not inline tests): (a) `task_completed` wired only into the legacy `startAgentSession` terminal, missing the dominant cc-soleur-go (`cc-dispatcher.ts`) lineage; (b) acknowledged-statutory fetch cap — the pinned email query was ported verbatim from the legacy `/api/inbox/emails` route (pins `status='new'` only) while the NEW merge pins ALL non-archived statutory, so an acknowledged statutory clock could drop past `LIST_LIMIT`. **Prevention:** (a) a new producer/turn-boundary hook must cover BOTH agent-run lineages (existing learning — added a `task-completed-both-lineages` source-parity gate); (b) when porting a precedent query whose DOWNSTREAM contract changed (pin-all vs pin-unacknowledged), re-derive the filter against the new contract — a verbatim copy inherits the old contract's assumption.
7. **SQL comment `);` broke the DSAR table-parse regex** — see Problem #2. **Prevention:** the no-`);`-in-column-comments rule above.
8. **Migration shape-test regex `FOR (INSERT|UPDATE|DELETE)` matched `SELECT … FOR UPDATE`** — the RPC's row-lock. Recovery: anchored the "no write policy" assertion on `CREATE POLICY` + a policy count. **Prevention:** anchor RLS-write-policy assertions on the `CREATE POLICY` construct, never a bare `FOR UPDATE|INSERT|DELETE` (row locks + policies share the keyword).
9. **RTL exact-name collision** — regex `getByRole("button", {name:/mark done/i})` matched BOTH the inner button and the outer `role="button"` row (whose accessible name concatenates child text). Recovery: exact string names. **Prevention:** for a navigable row rendered as `role="button"`, query inner action buttons by exact `name:` (the row's a11y name is the concatenation of all child text).
10. **DSAR completeness surfaced only at the full-suite exit gate** — the new user-FK table's missing disposition wasn't caught by the touched-file test loop. **Prevention:** when a migration adds a `user_id`/user-FK table, add its `DSAR_TABLE_ALLOWLIST`/`EXCLUSIONS` entry in the same change (the completeness gate is full-suite-only).

## Tags
category: database-issues
module: apps/web-platform/server/dsar-export, supabase/migrations
