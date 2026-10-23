---
module: web-platform
date: 2026-10-23
problem_type: logic_error
component: database
symptoms:
  - "A backfill that applies the SQL twin of a TS normalizer to stored rows would rewrite some rows to a value normalizeRepoUrl never returns, hiding the conversations stored in the TS form"
  - "The migration's canonical expression cost about 13 regexp_replace calls per row because the planner inlined each LATERAL step into every reference"
  - "Review fixes to an already-pushed migration broke the dev-ledger byte-identity gate"
root_cause: logic_error
resolution_type: code_fix
severity: medium
tags: [migration, backfill, sql-ts-parity, dev-ledger, postgres-planner, review-panel]
---

# Learning: a SQL-twin backfill needs an eligibility guard, and a migration pushed before review is expensive to correct

## Problem

Migration 031 (merged, immutable) normalised `repo_url` with a chain that lacked the re-trim the TS `normalizeRepoUrl` gained. The fix (#10633) is a new migration, 163, that rewrites `conversations.repo_url` and `workspaces.repo_url`. Three things cost more than they should have.

## Solution and findings

1. **Rewrite a stored row only when SQL is expected to equal the TS result.** Readers compare a conversation's stored value to `normalizeRepoUrl(workspaces.repo_url)`, so a SQL-only rewrite that differs from TS (path-position whitespace is `%20` in TS) hides that user's conversations. An eligibility guard (ASCII only, no internal whitespace, bounded length, a clean http(s) shape) leaves every other row as stored. "Provably equals" was too strong a word: the evidence is a Postgres-generated golden table plus a fuzz of the JS port against TS, so the header now says empirical. A case-folding clause was the gap: `lower()` of a non-ASCII host is engine- and locale-dependent, and one engine happened to keep U+0130 ineligible while another folds it to ASCII. The locale-independent clause `octet_length(a.t) = char_length(a.t)` removes the dependence.
2. **A chain of `CROSS JOIN LATERAL (SELECT ... AS t) a` is not computed once.** The planner pulls simple subqueries up and pastes the expression at every reference. `OFFSET 0` in each LATERAL stops that: 13 `regexp_replace` calls per row became 2, which measured about 2x on read-only probes and about 8x on the UPDATE. An earlier unreproduced "25x" was written into the migration header; do not quote a figure into an immutable file until a second run reproduces it.
3. **Push a migration only after the review panel, or accept the reconcile cost.** `tenant-integration` applies an unmerged migration to shared dev on the first push and records its byte hash, so any later edit, even a comment, fails "Assert unmerged migrations match the dev ledger". The sanctioned route is `dev-ledger-reconcile.yml` (author only, paired `.down.sql`), then pushing the edited bytes. Batch every migration-text change into one edit, and put wording corrections in the plan, ADR or PR body instead.
4. **Make the parity oracle depend on the SQL text.** A pasted golden table and local JS ports are only tied to the expression by convention. A pinned hash of the canon-expr block, assertions that the port regex constants equal the SQL literals, and an ordered check of the golden rows against the generator script turn "someone edited all seven copies consistently" into a red test. The eligibility signal needs its own column (`canon_ok`) in the golden table, because "ineligible" and "eligible but unchanged" look identical in the backfill column.
5. **Check that a post-merge acceptance criterion is achievable.** The plan required `verify-migrations` to conclude `success` after the merge, but that job is skipped on the `workflow_run` deploy arm (#9471), so the criterion could not be met.

## Key Insight

When a guard's claim is "this equals the reference", name the evidence (a real engine, a fuzz) and tie every copy of the expression to a pinned artifact; and do the review before the first push of any migration that a shared-environment CI will apply.

## Session Errors

- **Pushed 163 before the review panel, then needed a dev-ledger discard to apply correct fixes** — Recovery: `dev-ledger-reconcile.yml` dry run then execute, then push — Prevention: runbook paragraph added in this PR; batch migration edits and review before the first push when the change is not time-critical.
- **Edited 163's header a second time, against the runbook's own rule** — Recovery: restored the committed bytes with `git restore --source=HEAD`; the correction lives in the plan addendum — Prevention: the same runbook paragraph states that wording corrections do not qualify for the reconcile route.
- **Treated one engine's `lower(U+0130)` result as refuting a data-migration lead** — Recovery: the data-integrity seat's locale-independent clause was adopted anyway — Prevention: a case-folding or locale claim needs two engines or no claim.
- **A multi-file edit script aborted midway and left earlier writes applied** — Recovery: detected from the traceback, re-applied the remainder — Prevention: assert every anchor before writing any file, or write files last.
- **An off-by-one in the 2048 boundary fixture rows** — Recovery: caught on golden regeneration — Prevention: derive boundary rows from the constant, not by hand.
- **An unreproduced "25x" speedup written into a migration header** — Recovery: measured 2–8x, recorded in the plan addendum — Prevention: reproduce a figure before putting it in an immutable file.
- **Bare `pgrep -f` blocked by the hook** — Recovery: `proc.sh list_runs` — Prevention: already hook-enforced.
