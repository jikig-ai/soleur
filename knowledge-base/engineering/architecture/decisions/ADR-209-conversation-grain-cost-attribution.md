# ADR-209 — Conversation-grain attribution for LLM cost observability

- **Status:** Accepted
- **Date:** 2026-09-07
- **PR:** #7916
- **Issue:** #1055
- **Related:** [ADR-041](./ADR-041-byok-cap-enforcement-model.md) (the BYOK cap this
  partitions but does not touch), [ADR-108](./ADR-108-anthropic-cost-attribution-markers.md)
  (**not amended** — see Alternatives), [ADR-151](./ADR-151-agents-rule-corpus-is-unconditionally-loaded.md)
  (the "appears enforced, is absent" failure class this ADR's grants section guards against)

## Context

`conversations` already carries both halves of a per-workflow cost breakdown: `total_cost_usd`
(column added by `017_conversation_cost_tracking.sql`, incremented per turn by
`042_increment_conversation_cost_v2.sql`; migration 027 adds the per-user SUM RPC this ADR
repins, and also recreates `idx_conversations_user_cost` — 017, 027 and 041 each DROP and
CREATE that index, so the LIVE definition is 041's, verified on dev) and `active_workflow`
(migration 032, written once by the routing layer). They sit **on the same row**. Nothing consumed them together.

Issue #1055 asked for "per-workflow, per-agent, per-user cost observability" and was filed
against a codebase that has since shipped most of the capture layer. Of its three motivating
questions, only "per-user breakdown over time" was answerable. This ADR records the grain the
answer to the other two is computed at, and why it is not finer.

## Decision

**Cost is attributed at conversation grain, using the write-once `active_workflow` the routing
layer already persists — not at turn grain.**

Two consequences follow directly, and both are disclosed in the UI rather than hidden:

1. **First-Skill-wins.** `active_workflow` is set once, on the first workflow a conversation
   enters, and is not overwritten (`soleur-go-runner.ts`, guarded on
   `state.currentWorkflow === null`). A session that begins in `plan` and continues into
   `work` is attributed entirely to `plan`.
2. **The window is `created_at`, not spend time.** A conversation created last month that
   accrues cost this month counts against last month. This is pre-existing behaviour of the
   MTD headline, not something this change introduces.

The aggregate is one `GROUP BY ROLLUP` statement returning the per-bucket rows **and** the
grand total together, so the parts always sum to the whole under a UI that asks the reader to
reconcile them. Two RPCs would be two MVCC snapshots, and `increment_conversation_cost` fires
on every turn — an increment landing between them makes the parts genuinely not sum.

**One durable surface serves both audiences.** The same two columns answer the per-user
settings question (via `sum_user_mtd_cost_by_workflow`) and the operator's fleet-wide question
(via a documented SQL query, `runbooks/workflow-cost-query.md`). The operator half is a query,
not a second telemetry substrate.

## Alternatives Considered

| Alternative | Why rejected |
|---|---|
| **A per-turn `usage_events` table** | Reopens NG3 from the 2026-05-12 plan. Migration 132 exists *because* this instance cannot afford another per-turn write path; adding one to improve a per-page-render read inverts that trade. |
| **A `workflow` column on `audit_byok_use`** | That table is a WORM ledger — appending a column means a carve-out in its immutability posture, six INSERT sites, and DSAR Art. 15 consequences. Its cost is also cent-rounded, so it is the wrong source for a figure the UI promises matches to the cent. |
| **A workflow-span table** (start/end per workflow within a conversation) | Real machinery for a limitation that is *disclosable*. The first-Skill-wins caveat costs one sentence of UI copy; the span table costs a write path, a migration, and a new consistency question. |
| **Widening the ADR-108 log marker with a workflow field** | Drafted for the operator half, then cut. It is a 90-day lossy copy of a source Postgres holds exactly and forever, and it would have added a type-widening obligation across every marker consumer. Recorded here so the idea is not re-proposed — **ADR-108 is not amended**, because the marker is untouched. |
| **Turn-grain attribution** | See NG3 above; this ADR extends that non-goal from accounting into attribution. |

## The accepted limitation, and what bounds it

First-Skill-wins mis-attributes any conversation that spans workflows. The bound is empirical:
Phase 0.1 measured the live bucket distribution before the UI was designed.

On dev at 2026-09-07 that measurement returned **100% `legacy`** — every costed conversation
has `active_workflow IS NULL`. That is a statement about a synthetic seed corpus, not about
production, and it is recorded here for one reason: it fired the plan's own copy branch. The
breakdown UI **leads** with the legacy explanation rather than treating it as a footnote,
because on today's real data a design that buried it would render a panel in which every row
is the footnote.

The re-evaluation trigger for turn-grain is therefore *measured* materiality of
mis-attribution, not intuition about it.

## On `SECURITY DEFINER`

`sum_user_mtd_cost_by_workflow` is `SECURITY DEFINER`, and that is **strictly redundant**
here: only `service_role` may execute it, and `service_role` already bypasses RLS. It is
retained for symmetry with the adjacent `sum_user_mtd_cost` it sits beside and repins.

This is stated explicitly so a future reader does not infer the definer bit is load-bearing
and build a policy on it. The load-bearing part is the grant: `REVOKE` from `PUBLIC`,
`authenticated` and `anon`, `GRANT` to `service_role` only — verified live on dev after
migration 136 applied, for **both** functions (`{postgres=X/postgres,service_role=X/postgres}`
with `search_path=public, pg_temp`), not merely asserted in migration text.

**"Redundant" describes the BENEFIT, not the RISK, and the distinction is the whole reason
the grant matters.** Because the function is `SECURITY DEFINER`, a future `GRANT EXECUTE …
TO authenticated` converts a parameterised `uid` into a full cross-tenant read — any
authenticated caller could pass any user id. Under `SECURITY INVOKER` the same mistake would
be contained by RLS. So the grant is not defence-in-depth here; it is the **only**
containment, which is why migration 136 ships the REVOKE trio for both functions and why
`test/server/api-usage.tenant-isolation.test.ts` carries a committed regression test that
reddens when the grant widens (mutation-verified against live dev: granting to
`authenticated` fails the suite, revoking restores it).

Do not cite the "strictly redundant" sentence when relaxing the grant. It says the definer
bit buys nothing extra; it does not say the grant is optional.

The same migration repins `sum_user_mtd_cost` to `search_path = public, pg_temp`, which
migration 027 predates. That repin was **unenforceable on its own**: `migration-rpc-grants`
short-circuits on a legacy-exemption set that still named the function, so the exemption entry
had to be removed in the same change. A guard that cannot fail is the ADR-151 "appears
enforced, is absent" class, one layer down.

## Consequences

- Per-agent attribution is **not** delivered. `SDKResultMessage` carries no agent identity,
  and leader grain is a constant on the dominant path. #1055 stays open for it; this PR uses
  `Ref`, not `Closes`.
- The breakdown is a read-only partition of an existing number. It cannot disagree with the
  headline, because both come from one statement. Note the narrower scope of that guarantee:
  the conversation LIST is fetched by a separate query in the same `Promise.allSettled` batch,
  so list-vs-headline consistency is unchanged by this work and was never snapshot-guaranteed.
  The "match to the cent" copy governs the breakdown against the headline, which is exactly
  the pair this design makes atomic.
- Adding a workflow now has a second consumer — but the compile break comes from widening
  **`WorkflowName`** (`server/conversation-routing.ts`), not from the CHECK enum. Those are
  three hand-maintained lists (the SQL CHECK, the TS union, and the file-parse test that pins
  the SQL side), and widening the SQL alone compiles clean and lands the raw slug in the UI
  via `workflowLabel`'s fallback. The `satisfies Record<WorkflowBucket, WorkflowCopy>` rail
  fires only once `WorkflowName` moves. That is still the intended direction — a new bucket
  should not reach a user as a raw slug — but the rail is one hop further away than a reader
  would assume, and the fallback path is mirrored to Sentry (`op:
  "workflow-bucket-unmapped"`) precisely because the compile break is not guaranteed to
  happen first.
