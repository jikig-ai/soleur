---
category: best-practices
module: dsar, audit-log, pagination
date: 2026-05-22
pr: 4287
issue: 4231
tags:
  - multi-agent-review
  - dsar
  - audit-log
  - pagination
  - or-semantics
  - lint-symmetry
related:
  - 2026-04-15-multi-agent-review-catches-bugs-tests-miss.md
  - 2026-05-04-telemetry-join-format-mismatch-caught-by-orphan-counter.md
  - 2026-05-10-handshake-schema-drift-and-stale-precondition-budgets.md
---

# Multi-agent review catches DSAR OR-semantics lint asymmetry + audit-log keyset cursor tiebreak

## Problem

PR #4287 (feat-workspace-member-actions-audit) introduced an append-only audit log for workspace membership mutations. The plan was reviewed by 4 agents pre-implementation (12 P0/P1 corrections folded in) and the implementation was a tight verbatim execution. Post-implementation multi-agent review (12 agents) surfaced TWO defect-classes that plan-time review had missed — both in the same conceptual neighborhood ("symmetry invariants that the forward-direction-only check satisfies trivially").

### Defect 1 — `additionalOwnerFields` forward-lint is one-directional

The PR introduced `additionalOwnerFields?: string[]` on `DsarTableSpec` to handle audit tables where a user can be the **actor** OR the **target** of a row (`workspace_member_actions.actor_user_id` OR `workspace_member_actions.target_user_id`). The DSAR worker writes two separate `.from().select().eq()` chains — one per column — and merges/dedupes by row id.

The per-row-where lint (`test/dsar-worker-per-row-where.test.ts`) was extended to accept `.eq()` on ANY declared owner column:

```ts
const ownerFields = [spec.ownerField, ...(spec.additionalOwnerFields ?? [])];
const matched = ownerFields.some((col) =>
  new RegExp(`\\.eq\\(\\s*["']${col}["']`).test(c.chain),
);
expect(matched).toBe(true);  // forward lint: every chain has .eq() on AT LEAST ONE column
```

**The asymmetry:** there was no inverse check that every declared column has at least one chain. A future refactor dropping the `target_user_id` chain (e.g., "factor out the duplicate boilerplate") would leave the `actor_user_id` chain satisfying the forward lint alone — Art. 15 export would silently lose every row where the user appears only as the target. Same failure class as the FAQ HTML/JSON-LD parity drift documented at `2026-04-18-faq-html-jsonld-parity.md`: a one-directional consistency check passes trivially after a regression that breaks the inverse direction.

Both `data-integrity-guardian` (P1-A) and `pattern-recognition-specialist` (P1-1) flagged this independently in post-implementation review. Plan-time review did not — the lint extension was tested in the forward direction, and absence-of-inverse-test is hard to spot without enumerating "what could a future refactor break."

### Defect 2 — Plain timestamp cursor drops same-tick rows at page boundaries

The reader RPC `list_workspace_member_actions(p_workspace_id uuid, p_limit int DEFAULT 50, p_cursor timestamptz DEFAULT NULL)` originally paginated with `WHERE created_at < p_cursor ORDER BY created_at DESC, id DESC`. The ORDER BY carries `id DESC` for in-page determinism, but the cursor predicate is timestamp-only.

**The hazard:** an `AFTER INSERT OR UPDATE OR DELETE` trigger on `workspace_members` fires once per affected row. A bulk-write of N membership rows in one statement (e.g., a future batch invite) writes N audit rows whose `created_at = now()` resolves to **microsecond resolution** — all N rows share the same timestamp. When such rows straddle a page boundary, the cursor predicate `created_at < p_cursor` skips every same-tick row from the prior page that sorted after the cursor row by `id DESC`. The client paginates past actual rows without seeing them. Silent data loss in the owner's audit view.

`performance-oracle` caught this (P2-1) by reading the cursor predicate against the ORDER BY shape.

## Solution

### Fix 1 — inverse lint

Add a second `it()` block to `test/dsar-worker-per-row-where.test.ts`:

```ts
it("every declared owner column has at least one .eq(<col>, ...) chain in the worker (inverse lint)", () => {
  for (const [tableName, spec] of Object.entries(DSAR_TABLE_ALLOWLIST)) {
    if (spec.joinVia) continue;  // join-via tables have their own scope check
    const ownerFields = [spec.ownerField, ...(spec.additionalOwnerFields ?? [])];
    if (ownerFields.length < 2) continue;  // single-column tables covered by forward test
    const tableChains = chains.filter((c) => c.table === tableName);
    for (const col of ownerFields) {
      const covered = tableChains.some((c) =>
        new RegExp(`\\.eq\\(\\s*["']${col}["']`).test(c.chain),
      );
      expect(covered, `Allowlisted "${tableName}" declares "${col}" but no chain reads it`).toBe(true);
    }
  }
});
```

The new test runs only when `additionalOwnerFields` is non-empty (single-column tables are already covered by the chain-presence test). For each declared column, asserts at least one chain in `dsar-export.ts` carries `.eq("<col>", expectedUserId)`. Future refactors that drop a per-column chain fail at CI.

### Fix 2 — keyset cursor

Extend the RPC signature with `p_cursor_id uuid DEFAULT NULL` (backward-compatible — defaults preserve first-page callers):

```sql
CREATE OR REPLACE FUNCTION public.list_workspace_member_actions(
  p_workspace_id uuid,
  p_limit        int          DEFAULT 50,
  p_cursor       timestamptz  DEFAULT NULL,
  p_cursor_id    uuid         DEFAULT NULL
) RETURNS SETOF public.workspace_member_actions
...
  RETURN QUERY
    SELECT *
    FROM public.workspace_member_actions
    WHERE workspace_id = p_workspace_id
      AND (
        p_cursor IS NULL
        OR (p_cursor_id IS NULL AND created_at < p_cursor)
        OR (p_cursor_id IS NOT NULL AND (created_at, id) < (p_cursor, p_cursor_id))
      )
    ORDER BY created_at DESC, id DESC
    LIMIT GREATEST(1, LEAST(p_limit, 500));
```

Three predicate branches:
- `p_cursor IS NULL` — first page, no cursor.
- `p_cursor_id IS NULL AND created_at < p_cursor` — back-compat with first-cursor-only callers (still vulnerable to ties, but the surface area is bounded).
- `p_cursor_id IS NOT NULL AND (created_at, id) < (p_cursor, p_cursor_id)` — keyset tiebreak; correct for all cases.

Clients should pass the oldest returned `(created_at, id)` of page N as `(p_cursor, p_cursor_id)` for page N+1.

## Key Insight

**One-directional lints satisfy themselves trivially after the inverse direction regresses.** When introducing a new "OR-semantic" / "multi-value" / "list-of-N-things" shape into an existing allowlist or contract, audit the consumer side for symmetric coverage:

- If the producer declares N columns/values, does the consumer read all N?
- If the consumer iterates N chains, does the lint verify all N producer entries are covered?
- If a future refactor drops one chain, does any test fail?

The cheapest gate is to write the inverse-direction assertion at the same time as the forward one. The cost of catching this in CI is ~5 lines of test code; the cost of catching it after a refactor regression is an Art. 15 incomplete-disclosure that may not be detected for months.

**Cursor pagination on a timestamp column without a tiebreak silently drops same-tick rows.** Any audit/log/event table whose rows are populated via triggers, bulk-writes, or batch jobs will eventually produce N rows sharing one microsecond of `created_at`. The keyset cursor `(created_at, id) < (cursor_ts, cursor_id)` is the canonical fix; the cost is one extra parameter and three predicate branches. Caller signatures stay backward-compatible via NULL defaults.

**Multi-agent post-implementation review is the gate where these defect classes surface.** Plan-time review approved both shapes (forward lint, plain-timestamp cursor) because they were locally correct and the reviewer prompts didn't enumerate "what could regress this." Implementation-time review with agents that specialize in symmetry (`data-integrity-guardian`, `pattern-recognition-specialist`) and pagination (`performance-oracle`) raised both defects in the same review cycle. This validates the cost of the 8-agent gate even on a verbatim-from-plan implementation.

## Session Errors

1. **Initial git probe from bare-repo root** — exit 128 "this operation must be run in a work tree" because the session started in `/home/jean/git-repositories/jikig-ai/soleur` (bare) before resolving to the worktree path. **Recovery:** absolute path to `.worktrees/feat-workspace-member-actions-audit-4231`. **Prevention:** any session-start probe in a bare-repo project should resolve the worktree path first; `git rev-parse --show-toplevel` is the canonical resolver but fails identically in bare repos, so the worktree manager's `--print-worktree-path` would be more robust.

2. **Bash CWD non-persistence** — relative `cd .worktrees/...` from a non-root CWD failed; subsequent `git add` invoked from the worktree's `apps/web-platform/` cwd produced a doubled `apps/web-platform/apps/web-platform/` path. **Recovery:** chain `cd <abs-path> && <command>` in one Bash call. **Prevention:** already a documented pattern (cited at multiple skill SharpEdges); the violation here was inattention, not absence of rule.

3. **Migration shape regex too strict on `RAISE EXCEPTION ... USING`** — `\s+[^;]*USING` failed because the real SQL has `', TG_OP\n    USING` (comma directly after the closing quote). **Recovery:** loosened to `[\s\S]*?USING`. **Prevention:** default to `[\s\S]*?` between the message-string literal and the `USING ERRCODE` clause when matching `RAISE EXCEPTION` shapes; comma + variable substitution + newline are the common forms.

4. **Plan-specified runbook path was wrong** — plan §6.2 named `knowledge-base/engineering/runbooks/...` but actual repo convention is `engineering/operations/runbooks/`. I landed the runbook in the correct location BUT later cited the plan's wrong path in the PA-20 Article 30 register entry. Caught at post-implementation review by `git-history-analyzer`. **Recovery:** `replace_all` to fix the citation. **Prevention:** when correcting a plan-specified path during implementation, immediately grep+fix every secondary citation of that path in the same edit cycle. The plan is authoritative for intent, never for paths (`hr-when-a-plan-specifies-relative-paths-e-g`); when discovering a path drift, treat ALL plan-derived path references in the diff as suspect.

## Tags

category: best-practices
module: dsar, audit-log, pagination, lint-symmetry
