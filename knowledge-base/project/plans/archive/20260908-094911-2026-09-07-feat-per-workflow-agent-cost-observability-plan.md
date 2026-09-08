---
title: "feat: per-workflow LLM cost observability"
date: 2026-09-07
slug: feat-per-workflow-agent-cost-observability
branch: feat-one-shot-1055-per-workflow-cost-observability
issue: 1055
refs: 1055
lane: cross-domain
type: enhancement
priority: p3-low
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Enhancement Summary

**Deepened on:** 2026-09-07 · **Halt gates:** 4.6, 4.7, 4.8, 4.9, 4.10, 4.11 all pass
(`lint-guard-contract.py` exit 0; every cited AGENTS rule id resolves active; every cited
`knowledge-base/` path resolves; `lint-infra-no-human-steps.py` clean).

This plan was written, then reviewed by twelve independent passes — CTO, CFO, CLO, CPO,
spec-flow-analyzer, ux-design-lead, copywriter, the GDPR gate, a `model: fable` scoped
advisor, code-simplicity, architecture-strategist and Kieran. The review did not decorate
it; it **changed the design three times and shrank the deliverable by two thirds**.

### What the review changed

1. **Three premises were falsified and corrected**, each by more than one reviewer
   independently: `active_workflow` is write-once (not last-write-wins), exporting
   `SENTINEL_UNROUTED` would break a pinned test, and — the largest — the ADR-108 log
   marker was a 90-day lossy copy of a source Postgres already holds exactly and forever.
2. **The marker half was cut in full**, taking 12 of 17 edited files with it. The operator's
   fleet-wide question is one documented SQL query over the same two columns. The Cut List
   records that this survived the Phase 0.6b minimality gate and seven domain reviews
   because the gate was applied to the *issue's* proposed mechanisms and not to the plan's
   own.
3. **The single-snapshot guarantee was scoped to the wrong pair of numbers.** The draft
   still called `sum_user_mtd_cost` in parallel, so headline and buckets would have arrived
   from two transactions — reintroducing, one layer up, the exact race the finance review
   had blocked. The fallback is now sequential.
4. **Two acceptance criteria were unsatisfiable as written** and one was vacuous: `proacl`
   always lists the function owner; a source grep for the footnote hedge returns `0` on the
   *unfixed* file because JSX splits it across a line break; and an absence-grep over a spec
   section hits the section's own rationale.
5. **Four existing test files break** on the loader change and are now tasks, not cleanup —
   none appeared in any earlier draft's file list.

### What was verified by execution rather than inspection

The `ROLLUP` aggregate was run on live Postgres 17.6 and on PG16: `GROUPING()` over a
`CASE` is legal, the bucket expression can never be NULL (so it cannot collide with the
super-aggregate row), the zero-row case returns exactly one `is_total` row, and the parts
summed to the whole exactly on a fixture spanning two months. The `sum_user_mtd_cost`
signature was diffed against migration 027 so `CREATE OR REPLACE` provably creates no
overload.

### Reviewer corrections that were themselves wrong

Three were rejected after checking: `apps/web-platform/bunfig.toml` really does carry
`pathIgnorePatterns = ["**"]` (the reviewer read the *root* bunfig, a different file), and
two line citations this plan already had right. Reviewer output was verified before
acceptance, not merged on trust.

### Open items carried to the operator

Five User-Challenges are recorded in `decision-challenges.md` rather than silently applied —
most importantly that this PR should **not** close #1055, because per-agent attribution is
not delivered and is not derivable from the SDK frame that carries the money.

## Overview

Per-turn LLM cost capture, per-conversation aggregation, and a per-user month-to-date
rollup all ship today. The dimension named in issue #1055's title does not: cost is not
attributable to the **workflow** that spent it.

Research established that the workflow dimension is **already captured and already
persisted**. `conversations.active_workflow` (migration 032) is CHECK-constrained to the
six workflow names plus an `__unrouted__` sentinel, and `soleur-go-runner.ts` writes it
on the first `Skill(skill=<name>)` tool call of a conversation. It sits in the same row
as the exact cost figure (`conversations.total_cost_usd NUMERIC(12,6)`) that the existing
month-to-date headline already sums.

So this plan adds **no capture, no storage, and no new observability substrate**. It adds
the aggregation and the exposure that were never built: **one** read-only Postgres
function that returns the per-workflow partition and the month-to-date grand total from a
single statement, a loader that calls it, and a settings breakdown that renders it. The
operator's fleet-wide view is one documented SQL query over the same two columns — no
code at all.

**Per-agent is NOT delivered**, and the PR must not claim otherwise — see `## Scope`.

## Scope: what #1055 asks for vs what this delivers

| #1055's question | Status after this plan |
|---|---|
| "What's the per-user cost breakdown over time?" | **Already shipped** before this plan — `sum_user_mtd_cost` (mig 027). |
| "How much does a brainstorm session cost vs. a code review session?" | **Delivered**, with a named attribution bound (R2) and a per-conversation average so the answer is not dominated by frequency. |
| "Which agents/workflows consume the most tokens?" | **Workflows: delivered. Agents: NOT delivered.** |

Per-agent is not merely unbuilt — at subagent grain it is **not derivable from the frame
that carries the money**. `SDKResultMessage` (the only frame with `total_cost_usd`) has no
agent identity and no `parent_tool_use_id`:

```
awk '/^export declare type SDKResultSuccess = \{/,/^\};/' \
  apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/sdk.d.ts \
  | grep -ciE 'agent|subagent|parent_tool_use_id' || true
→ 0
```

Anchored on the type declaration rather than a line window: an earlier draft used
`NR>=3949 && NR<=4000`, which starts inside `SDKRateLimitInfo` and is pinned to one SDK
version. The conclusion is unchanged — re-run on the honest window, still `0`.

At *leader* grain the dimension is degenerate on the dominant path: `cc-dispatcher.ts:4108`
passes the constant `CC_ROUTER_LEADER_ID` (`"cc_router"`), so a GROUP BY yields one
non-trivial group.

**Consequence: `Ref #1055`, not `Closes #1055`.** Closing would assert the per-agent
question was answered. #1055 stays open pending the successor issue (Phase 5). Recorded in
`knowledge-base/project/specs/feat-one-shot-1055-per-workflow-cost-observability/decision-challenges.md`.

## Research Reconciliation — Spec vs. Codebase

Issue #1055 was filed 2026-03-23. Six of its claims are stale; three of this plan's own
drafting premises were falsified during review and are recorded here rather than quietly
corrected.

| Claim | Reality (2026-09-07) | Response |
|---|---|---|
| "No token usage logging" | `server/cost-writer.ts` captures `total_cost_usd` + 4 token axes per turn from 3 call sites | Build nothing. |
| "No cost aggregation" | `increment_conversation_cost` (mig 042); `sum_user_mtd_cost` (mig 027) | Build nothing. Mirror 027's predicate. |
| "No workflow-level breakdown" | **Half true.** `conversations.active_workflow` (mig 032) stores it, and per-workflow cost *caps* already enforce against it (`cc-cost-caps.ts`, `soleur-go-runner.ts:1840`). Nothing aggregates or displays it. | The real gap. Aggregation + exposure only. |
| "Web Platform hardcodes `claude-sonnet-4-6`" | Stale id; the runner reads the model from `SDKResultMessage.modelUsage` | Ignore. |
| "Telegram Bridge defaults to `claude-opus-4-6`" | Bridge removed entirely (`dccc56dee`). Zero live references. | Ignore in full. |
| "Optional — smart routing: Haiku for simple lookups" | ADR-053 pins `model: inherit`; the 2026-04-13 brainstorm records "No model downgrades — quality is non-negotiable" | Explicit non-goal. |
| *Draft premise:* "a conversation whose workflow is reset mid-life re-attributes its spend" | **FALSE.** `active_workflow` is **write-once, monotonic**: the lock at `soleur-go-runner.ts:2162` is guarded by `state.currentWorkflow === null`, seeded from the DB across restarts; `persistActiveWorkflow` (`ws-handler.ts:1231`) refuses to regress; `ws-handler.ts:1084` names the rule "first-writer-wins"; and `onSwitchWorkflow` is never passed to `<WorkflowLifecycleBar>`, so no switch UI renders. | R2 rewritten to **first-Skill-wins**. Caught independently by CTO, spec-flow, and copywriter. |
| *Draft premise:* "export `SENTINEL_UNROUTED` so the label map shares one literal" | **Would break a pinned test.** `test/conversation-routing.test.ts:138` asserts `Object.keys(mod)` does not contain `SENTINEL_UNROUTED`; `:57-68` asserts the string never appears in stringified ADT output. | Removed. The function normalises sentinels in SQL so no `__`-prefixed string crosses into TS. |
| *Draft premise:* "the log marker is the operator surface and the Postgres aggregate the user's; neither substitutes for the other" | **FALSE, and it was the plan's largest unjustified cost.** The operator's fleet-wide question is `SELECT active_workflow, sum(total_cost_usd) FROM conversations WHERE created_at >= … GROUP BY 1` — the same two columns, exact, durable, no retention window. The marker would have been a 90-day lossy copy of a source Postgres holds forever, needing `source`-scoping because 2 of its 3 choke points have no workflow concept at all. | **Phase 2 (marker widening) cut in full** — 12 of 17 edited files. P3 is met by one documented query. |
| *Not in the issue:* the MTD window's meaning | `sum_user_mtd_cost` filters `conversations.created_at >= since`, while `total_cost_usd` is a **lifetime** accumulator on the row (mig 042:44). So "MTD" means *lifetime spend of conversations created this month* — a conversation created 28 Aug that spends in September contributes nothing to September. | Pre-existing; **not fixed here** (fixing it changes the headline number). Named as R4 with a Phase 0 measurement, so the footnote rewrite does not newly assert something false. |

The issue body says "Why Phase 4", but the milestone is **Post-MVP / Later** (#6) and
`#1055` is absent from `knowledge-base/product/roadmap.md`. The CPO's re-milestone
recommendation is in `decision-challenges.md` rather than actioned here.

## Research Insights

### Premise Validation (Phase 0.6)

- `gh issue view 1055` → `OPEN`, milestone `Post-MVP / Later`, labels `enhancement`,
  `priority/p3-low`, `type/feature`, `domain/engineering`. Not closed by any merged PR.
- Every cited file exists: `server/agent-runner.ts` (3186), `server/cost-writer.ts` (418),
  `server/api-usage.ts` (192), `components/settings/api-usage-section.tsx` (203),
  `server/claude-cost-marker.ts`.
- **Mechanism-vs-ADR grep.** `ADR-108-anthropic-cost-attribution-markers.md` governs cost
  attribution. It does not reject a per-workflow dimension; it blocks only the *daily
  Admin cost-report* half on an un-mintable `ANTHROPIC_ADMIN_KEY` (#6297). Since Phase 2
  is cut, ADR-108 is **not amended** by this plan and its choke-point decision (§Decision
  item 3) is untouched.
- **ADR ordinal.** `ADR-204` is highest on `origin/main`; `ADR-205` and `ADR-206` are
  claimed on pushed branches. Next free is **ADR-209 — provisional**.

### Property List (Phase 0.6b)

- **P1** — A BYOK user can see how much of their month's Anthropic spend each Soleur
  workflow accounted for.
- **P2** — The parts sum exactly to the month-to-date headline on the same surface.
- **P3** — The operator can compare workflow costs fleet-wide.
- **P4** — A reader can tell attributable spend from non-attributable.
- **P5** — Cost attributable to an *agent* is visible.
- **P6** — No regression of the existing exact-cost invariants: the R8 input total, the
  atomic increment, the WORM audit surface, RLS tenancy, or the "matches the Console to
  the cent" promise.
- **P7** — The answer is actionable: the issue's question is comparative (cost *per
  session*), not a total dominated by frequency.

### Cut List (Phase 0.6b, extended at review)

| Mechanism | Property | Cut because |
|---|---|---|
| "Instrument: log token usage per agent session" | P1 input | Shipped — `cost-writer.ts:127`, `:140`, `:275`, all 3 call sites. |
| "Aggregate: store per-user cost data" | P3 (per-user) | Shipped — `sum_user_mtd_cost`, mig `027:42`. |
| New per-turn `usage_events` table | P1/P2 at turn grain | The 2026-05-12 undercount plan declares per-turn persistence an explicit **non-goal (NG3)** and records the table as "Rejected as out-of-scope". Migration 132 exists because this instance cannot afford another per-turn write path. |
| New `workflow` column on `audit_byok_use` | P1 durable | Mig-066 Art. 17 WORM carve-out (066:37 warns about exactly this), 6 INSERT sites across migs 084/121, DSAR Art. 15 payload widening (`dsar-export.ts:762`), RLS review — and `unit_cost_cents = Math.round(cost*100)` rounds sub-cent turns to **0** by design (R7), so it is the wrong cost source regardless. |
| Widen the `usage_update` WS event | live badge | 8 client-side contract files; buys no listed property — this is a server-rendered settings read. |
| Group the existing 50-row list client-side | P1 | Commit `638034307` (#2501) removed exactly this pattern, **and the list is a different population**: no month filter, `LIMIT 50`. |
| Two separate RPCs (headline + breakdown) | P2 | Two statements are two MVCC snapshots; `increment_conversation_cost` fires every turn. One statement instead (CFO **F2**, blocking). |
| **`workflow` field on the ADR-108 cost marker** *(cut at review)* | P3 | **The durable source already answers it.** A `GROUP BY active_workflow` over `conversations` is exact, has no retention window, and needs no `source` scoping — whereas the marker is 90-day, needs `source IN (…)` because 2 of 3 choke points emit `null`, carries the same first-Skill-wins grain, and cannot add workflow × model because the cc path's `model` is `null` and fixing that is a separate PR. Cost avoided: 12 of 17 edited files, ~40 LOC prod + ~120 LOC tests, the whole `hr-type-widening-cross-consumer-grep` obligation, and an ADR-108 amendment. |
| **Per-row `workflowLabel` in the conversation list** *(cut at review)* | none of P1-P7 | The breakdown *is* the answer. It also drags in a `ConversationListRow` widening plus its untyped-`.select()` obligation, and — decisively — it would put the **raw** `'__unrouted__'` and `NULL` into TS from a plain `conversations` SELECT, breaking the sentinel-containment invariant this whole design rests on and giving `WORKFLOW_COPY` two key-spaces when the Guard Contract asserts there is exactly one (Kieran P0-3). Pure "while we're here". *(An earlier draft justified the cut partly on losing an Index-Only Scan; that reason was wrong and is withdrawn — the list SELECT already reads `id`, which is neither a key nor an INCLUDE column of `idx_conversations_user_cost`, so it already requires a heap fetch. The sentinel-containment reason is the load-bearing one.)* |
| **A runtime guard parsing the SQL for workflow names** *(cut at review)* | label completeness | The migration's `CASE` literals are only `'legacy'` and `'unrouted'`; the six workflow names arrive through the `ELSE` branch, which a regex cannot see. And the cited precedent (`lib/messages/action-class-copy.ts:160`) enforces completeness at **compile time** via `as const satisfies Record<…>`. Building a SQL parser to enumerate an exhaustiveness rail inverts this plan's own binding learning (`2026-05-07-tsc-not-source-grep-enumerates-exhaustiveness-rails.md`). |
| **A per-commit gate coupling the footnote to the breakdown** *(cut at review)* | "no build ships one without the other" | `ship/SKILL.md:1793,1798,2062` and `merge-pr/SKILL.md:266` all merge with `gh pr merge --squash`, and the release deploys on push to `main`. No released build can contain one without the other. The risk is real; the gate defends an unreachable state. |
| **A turns/day vs page-renders/day measurement** *(cut at review)* | "the index decision is measured" | The decision (no index) is fixed in this Cut List and cannot change on the outcome, so the measurement is ceremony wearing `hr-no-dashboard-eyeball-pull-data-yourself` as a costume. With the list-SELECT widening also cut, only the aggregate does a heap fetch. |
| Per-**subagent** cost attribution | P5 | Not derivable from the money-carrying frame (grep-proven). Tracking issue. |
| cc-path `model: null` fix | per-model analysis | `modelUsage` is `Record<string, ModelUsage>` and the marker field is a **scalar**; the three paths already disagree about what `model` means (`agent-runner.ts:2383` takes `Object.keys()[0]`; `agent-on-spawn-requested.ts:699` passes the *declared* model). Fixing it is a design decision needing its own ADR-108 amendment. Separate PR. |
| Adding `active_workflow` to `idx_conversations_user_cost` | read speed | Permanent per-turn index write to accelerate a per-page-render read. |
| Task-complexity model routing | cost reduction | Not an observability property. ADR-053 + the 2026-04-13 brainstorm. |
| Admin cost-report cron; spend-vs-budget alert | fleet totals | Un-mintable `ANTHROPIC_ADMIN_KEY` (ADR-108, #6297). |

**Survives:** one aggregate returning buckets + total + count (P1, P2, P4, P7), a loader,
a UI block, one documented operator query (P3), and one inline correctness fix.

**Honest note on the process.** The marker half survived the Phase 0.6b gate and seven
domain reviews before the simplicity pass cut it. The gate asks "does a mechanism already
on `origin/main` buy this property?" — and the answer for P3 was always "yes, the same two
columns". The gate was applied to the *issue's* proposed mechanisms and not to the plan's
own, which is precisely the failure mode Phase 0.6b step 2 warns about.

### Value-Proposition Measurement (Phase 0.6c)

The justification is observability, not a cost saving, so 0.6c's quantification of a
saving does not bind. The downstream value ("prerequisite for every future token-cost
decision") is **unquantifiable at plan time by construction** — the baseline does not exist
yet, which is the point. Recorded rather than asserted. What *is* measured is the bucket
distribution (Phase 0.1), which changes the UI copy.

### Institutional learnings that bind

| Learning | What it imposes |
|---|---|
| `2026-07-30-one-blocked-mechanism-is-not-a-blocked-capability.md` | The ADR-108 block is the *daily* marker only. Both siblings enumerated before scoping. |
| `2026-06-11-verify-billing-model-before-scoping-cost-capture-feature.md` | A cost feature inherits the billing model of what it measures. Metered BYOK web path **only**. The 2026-06-11 loop-token-cost-ledger brainstorm (Decision 6) rejected per-loop dollars for the operator's flat-subscription local loops. Nothing here re-opens it — but the bucket names are namespace-identical, so §Non-Goals states that extending this to operator loops or CI spend re-opens Decision 6. |
| `2026-06-01-write-path-internally-consistent-claim-misses-trigger-vs-rpc-contradictions.md` | Read every BEFORE trigger on any table an RPC writes. **This function writes nothing** — `STABLE`, read-only — the cheapest discharge, and why the design avoids `audit_byok_use`. |
| `2026-05-07-tsc-not-source-grep-enumerates-exhaustiveness-rails.md` | `tsc`, not grep, enumerates exhaustiveness. Applied twice: it is why the label map uses a `satisfies` rail, and why the SQL-parsing guard was cut. |
| `2026-05-13-helper-migration-must-preserve-operator-dashboard-message-strings.md` | A new failure mode gets its own Sentry `op`, never folded into an existing dashboard-keyed tag. |
| `2026-04-18-supabase-migration-concurrently-forbidden.md` | No `CREATE INDEX CONCURRENTLY` — the runner wraps each file in a transaction (SQLSTATE 25001). This plan creates no index, so it is satisfied vacuously. *(Sibling migrations cite this as `cq-supabase-migration-no-concurrently`. That id is a local convention used in ~10 migration tests — it is **not** in `AGENTS.rules.md` and not in `scripts/retired-rule-ids.txt`, so do not cite it as a registered rule.)* |
| `cq-pg-security-definer-search-path-pin-pg-temp` | Pin `public, pg_temp`. Mig 027 pins only `public` — **fixed inline** (CTO R6, `rf-review-finding-default-fix-inline`). |
| `2026-05-21-dev-supabase-drift-…`, `hr-dev-prd-distinct-supabase-projects` | Dev first, verify, then the prd `migrate` job on merge. |
| `cq-ac-must-not-depend-on-concurrent-sessions` | Killed a proposed "cost incremented between reads" test scenario: an interleaved `increment_conversation_cost` is exactly a process the plan never mentions flipping the result. The property is **structural** (one statement) and is asserted as such. |

### Repo conventions confirmed

- **Test runner:** vitest. `vitest.config.ts` collects `test/**/*.test.ts` (`unit`, node)
  and `test/**/*.test.tsx` (`component`, jsdom). Co-located `components/**/*.test.tsx` is
  **never** collected. `bun test` is blocked for this package by **`apps/web-platform/bunfig.toml`**, whose
  `pathIgnorePatterns = ["**"]` ignores everything (#1469). Note there are **two** bunfig
  files and they differ: the repo-root one carries
  `pathIgnorePatterns = [".worktrees/**", "apps/web-platform/**"]`. Cite the package file
  by path, not "repo-wide". `test/messages/`, `test/supabase-migrations/`,
  `test/components/settings/` and `test/server/` all exist and are collected.
- **Typecheck:** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`. The repo root
  `package.json` declares no `workspaces`, so `npm run -w …` aborts.
- **Migrations:** highest is `135_statutory_repin_send.sql`; `136_` is free. Prefix
  collisions exist in-tree.
- **An existing corpus-wide lint already covers the new function.**
  `apps/web-platform/test/migration-lint/definer-grants.ts` (#6328, ADR-112) sweeps
  **every** forward migration, detects each `CREATE … SECURITY DEFINER`, and enforces
  `REQUIRED_REVOKE_ROLES = ["public","anon","authenticated"]` as a revoke-union across the
  corpus. Two consequences: the new function must satisfy it or CI reds, and re-issuing
  `sum_user_mtd_cost` via `CREATE OR REPLACE` without re-REVOKEing is safe because 027's
  REVOKEs are already in the union.
- **`.service-role-allowlist`** is CODEOWNERS-pinned; `server/api-usage.ts` is already
  listed PERMANENT. **No new path.** The list SELECT stays on the **tenant** client under
  RLS (`getFreshTenantClient`); only the aggregate is service-role (CTO R5).
- **`conversations` has no `FORCE ROW LEVEL SECURITY`**, so the `SECURITY DEFINER` read
  behaves as `sum_user_mtd_cost` already proves it does on this exact table.
- **Editorial-layer precedent:** `lib/messages/action-class-copy.ts` maps internal
  identifiers to founder-facing copy, closing with
  `as const satisfies Record<ActionClass, ActionClassCopy>` (`:160`), with its parity test
  at `test/messages/action-class-copy.test.ts`.
- Design anchor: `knowledge-base/product/design/byok-cost-tracking/` (existing
  `cost-tracking-wireframes.pen`; this feature's `workflow-cost-breakdown.pen`).
- Copy spec: `knowledge-base/project/specs/feat-restore-byok-usage-dashboard/copy.md` —
  char-budgeted; extended, never replaced. Copy is never authored inline in TSX.
- **Operator prd read path, no SSH:** `doppler run -c prd -- psql "$DATABASE_URL"`, the
  same mechanism `apps/web-platform/scripts/run-migrations.sh:8-10` documents.

### Skill description budget

No `plugins/soleur/skills/*/SKILL.md` `description:` is edited, at Phase 1 or after the
Files-to-Edit list was finalized. `cq-skill-description-budget-headroom` does not fire.

### Functional overlap (1.5b) / Community discovery (1.5)

Three registries searched. **No functional overlap** — the community corpus meters
developer-laptop CLI sessions from `~/.claude/projects` transcripts; this is server-side
telemetry over the app's own Postgres. Stack (Next.js/TS/Supabase) fully covered by
built-in agents; no `agent-finder` spawn.

## Open Code-Review Overlap

`gh issue list --label code-review --state open --limit 200` (63 open), matched against
each planned path with a standalone `jq --arg`.

| Planned file | Match | Disposition |
|---|---|---|
| `server/api-usage.ts`, `components/settings/api-usage-section.tsx` | none | — |
| `server/agent-runner.ts`, `server/cc-dispatcher.ts`, `server/cost-writer.ts` | #3242, #3243 | **Moot.** These files left the edit list when Phase 2 was cut. No overlap remains. |

## User-Brand Impact

**If this lands broken, the user experiences:** a per-workflow cost breakdown in
Settings → API Usage whose rows do not sum to the month-to-date headline directly above
them, or that attributes their spend to the wrong workflow. On a surface whose own copy
reads "No markup, no middle layer" and "the numbers will match to the cent", a visible
arithmetic contradiction is read as Soleur mishandling their money. The specific
reachable-by-ordinary-use failure the CPO and CFO both identified: the headline is
month-scoped and uncapped while the conversation list is all-time and capped at 50, so a
breakdown derived from the wrong population silently fails to reconcile for any user with
more than 50 costed conversations.

**If this leaks, the user's spend data is exposed via:** the new aggregate. It is
`SECURITY DEFINER` and its `uid` parameter is the sole access control — a caller passing an
attacker-supplied `uid` would return another tenant's per-workflow spend profile. The
mitigating chain is the one already load-bearing for `sum_user_mtd_cost`: `REVOKE EXECUTE
… FROM PUBLIC, anon, authenticated`; `GRANT … TO service_role` only; the single caller
validates `userId` against a UUID regex (`api-usage.ts:94`) and is reached only from a
server component holding the authenticated session's own id.

**Brand-survival threshold:** `single-user incident`.

The threshold is **not uniform across the change** (CPO): the grouped arithmetic and the
sum-to-headline consistency are at threshold; workflow naming is confusion-class, below
it. Consequences: `requires_cpo_signoff: true`; `user-impact-reviewer` at review time;
`plan-review` escalated to the 5-agent panel (done — see `## Domain Review`);
`deepen-plan` runs, because plan-review is structurally blind to the SQL and
security-primitive class the deepen triad catches.

## Implementation Phases

### Phase 0 — Preconditions (two, each with a stated branch)

Only checks whose *outcome changes the plan* live here. "Run the tests first" and "pick
the next free migration number" are Phase 1 lines, not gates.

**0.1 Bucket distribution (read-only, dev).**
`SELECT COALESCE(active_workflow,'<null-legacy>') AS bucket, count(*), sum(total_cost_usd) FROM conversations WHERE total_cost_usd > 0 GROUP BY 1 ORDER BY 3 DESC;`
**Branch:** if `<null-legacy>` + `__unrouted__` together hold a **majority** of dev MTD
spend, the breakdown mostly answers "don't know", and Phase 3's copy leads with that
rather than burying it. Run the same query grouped by `domain_leader` — that result
settles the CPO/CTO disagreement in `decision-challenges.md` about which cut is primary.
*(The earlier draft named a 60% threshold with no derivation; "majority" is the honest
form of the same judgment, and the number that matters is recorded, not invented.)*

**0.2 Attribution grain — confirm write-once.**
Re-verify the corrected premise: `soleur-go-runner.ts:2162` (`state.currentWorkflow === null`
guard), `ws-handler.ts:1231-1276` (`persistActiveWorkflow` refuses to regress),
`ws-handler.ts:1084` ("first-writer-wins"), and that `onSwitchWorkflow` is still not
passed to `<WorkflowLifecycleBar>`. **Branch:** if any path overwrites a non-null
`active_workflow`, R2 changes shape and the Phase 3 copy changes with it.

**0.3 MTD window semantics (R4).**
Confirm against dev that `sum_user_mtd_cost`'s window is `conversations.created_at`, not a
spend date, and measure how much in-month spend belongs to conversations created in a
prior month. **Branch:** the size of that skew decides whether the Phase 3 footnote can
say the Console confirms "the total", or must scope that claim further. This plan does
**not** change the window — that would change the headline number users already see.

### Phase 1 — Migration `136_workflow_cost_rollup.sql` (RED first)

Written first: `test/supabase-migrations/136-workflow-cost-rollup.test.ts`, parsing the
migration's text-level contract, mirroring `032-workflow-state.test.ts`.

First line of this phase: confirm `136_` is still free
(`ls apps/web-platform/supabase/migrations/ | grep -c '^136_'` → `0`); if not, take the
next free integer and sweep this plan, `tasks.md`, and the ADR reference in one edit. Then
read 027's live grants (`SELECT proname, proacl FROM pg_proc WHERE proname='sum_user_mtd_cost';`)
so the new grants mirror reality rather than the migration text.

The migration creates **one function**, performs **zero table DDL**, and applies **one
inline correctness fix** to a sibling.

```sql
-- 136_workflow_cost_rollup.sql
-- Per-workflow partition of the SAME month-to-date predicate `sum_user_mtd_cost`
-- (mig 027) sums, PLUS the grand total, from ONE statement.
--
-- SINGLE-SNAPSHOT INVARIANT (load-bearing). ROLLUP returns the per-bucket rows and
-- the grand-total row from one statement, therefore one MVCC snapshot. Two RPCs
-- would be two snapshots, and `increment_conversation_cost` fires on every turn —
-- an increment landing between them makes the parts genuinely not sum, under a UI
-- that promises the numbers match to the cent. This is why the total is returned
-- here rather than read alongside from `sum_user_mtd_cost`.
--
-- `since` is a PARAMETER, never `date_trunc('month', now())` in the body: a request
-- crossing the month rollover must not get two different windows.
--
-- The bucket expression is named ONCE in the derived table. An earlier draft
-- inlined it in four places (select list, two GROUPING() calls, the grouping
-- clause); that is where a later edit silently misbuckets real money, because one
-- copy drifts and GROUPING() over a non-identical expression errors or groups
-- differently.
--
-- `bucket IS NULL` on the super-aggregate row is produced by ROLLUP itself. That is
-- unambiguous ONLY because the CASE can never return NULL — its `IS NULL` arm is
-- first and returns 'legacy'. `is_total` is returned as the EXPLICIT signal anyway,
-- so no caller has to rely on that reasoning.
--
-- SENTINEL NORMALISATION. `__unrouted__` is a storage-layer detail that
-- `server/conversation-routing.ts` documents as "must never leak past this module",
-- with `test/conversation-routing.test.ts:138` pinning that its constant is not
-- exported. This function emits neutral keys — 'legacy' and 'unrouted' — so no
-- `__`-prefixed sentinel crosses into TS. The literal below is the one controlled
-- violation of that rule and is pinned by the guard in the plan's Guard Contract.
--
-- No index is created, so the no-CONCURRENTLY convention is satisfied vacuously. For
-- context, `idx_conversations_user_cost` is defined at
-- `041_conversation_cache_tokens.sql:35-45` as `(user_id, created_at DESC)` with a
-- SIX-COLUMN INCLUDE list and `WHERE total_cost_usd > 0` — the INCLUDE list is the whole
-- point of that migration (an Index-Only Scan for the list query). `active_workflow` is
-- not in it, so this aggregate takes a heap fetch over one user's costed conversations
-- for one month. That trade is deliberate: the index write would land on every turn
-- forever to speed a per-page-render read. NOTE there are TWO migrations numbered 041 —
-- cite the filename, not the number. FORWARD-ONLY; rollback in the paired .down.sql.

CREATE OR REPLACE FUNCTION public.sum_user_mtd_cost_by_workflow(
  uid   UUID,
  since TIMESTAMPTZ
) RETURNS TABLE(bucket TEXT, total NUMERIC, n INTEGER, is_total BOOLEAN)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
STABLE
AS $$
  SELECT b.bucket::TEXT                    AS bucket,
         COALESCE(SUM(b.cost), 0)::NUMERIC AS total,
         COUNT(*)::INTEGER                 AS n,
         GROUPING(b.bucket) = 1            AS is_total
    FROM (
      SELECT CASE
               WHEN c.active_workflow IS NULL          THEN 'legacy'
               WHEN c.active_workflow = '__unrouted__' THEN 'unrouted'
               ELSE c.active_workflow
             END              AS bucket,
             c.total_cost_usd AS cost
        FROM public.conversations c
       WHERE c.user_id = uid
         AND c.total_cost_usd > 0
         AND c.created_at >= since
    ) b
   GROUP BY ROLLUP (b.bucket)
   ORDER BY GROUPING(b.bucket) DESC, 2 DESC, 1 ASC;
$$;

COMMENT ON FUNCTION public.sum_user_mtd_cost_by_workflow(UUID, TIMESTAMPTZ) IS
  'Service-role-only per-workflow MTD cost partition for the BYOK usage dashboard. '
  'The is_total row is the grand total from the SAME statement — do not read the '
  'headline from a second query. End users MUST NOT call this directly; '
  'see server/api-usage.ts. Issue #1055.';

REVOKE EXECUTE ON FUNCTION public.sum_user_mtd_cost_by_workflow(UUID, TIMESTAMPTZ) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sum_user_mtd_cost_by_workflow(UUID, TIMESTAMPTZ) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.sum_user_mtd_cost_by_workflow(UUID, TIMESTAMPTZ) FROM anon;
GRANT  EXECUTE ON FUNCTION public.sum_user_mtd_cost_by_workflow(UUID, TIMESTAMPTZ) TO   service_role;

-- Inline correctness fix (CTO R6, rf-review-finding-default-fix-inline). NOTE: this
-- repin is UNENFORCEABLE on its own — `test/migration-rpc-grants.test.ts`'s
-- LEGACY_SEARCH_PATH_NO_PG_TEMP set still names `sum_user_mtd_cost`, and the gate
-- short-circuits on membership. That entry is removed in the same PR (see Files to
-- Edit); without it a future migration could silently un-pin pg_temp again. Migration
-- 027 predates cq-pg-security-definer-search-path-pin-pg-temp and pins
-- `SET search_path = public` with no `pg_temp`. Shipping a correct sibling beside an
-- incorrect original reads as intentional to the next reviewer. Signature and return
-- type are IDENTICAL to 027:42-47 (verified) so CREATE OR REPLACE is valid and
-- preserves the existing ACL; body verbatim, search_path only.
CREATE OR REPLACE FUNCTION public.sum_user_mtd_cost(uid UUID, since TIMESTAMPTZ)
RETURNS TABLE(total NUMERIC, n INTEGER)
LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp STABLE
AS $$
  SELECT COALESCE(SUM(total_cost_usd), 0)::NUMERIC AS total,
         COUNT(*)::INTEGER                          AS n
    FROM public.conversations
   WHERE user_id = uid AND total_cost_usd > 0 AND created_at >= since;
$$;
```

Plus `136_workflow_cost_rollup.down.sql`, which **drops the new function only**:
`DROP FUNCTION IF EXISTS public.sum_user_mtd_cost_by_workflow(UUID, TIMESTAMPTZ);`

It deliberately does **not** restore `sum_user_mtd_cost` to its 027 shape. The repin is
body-identical — only `search_path` changes — so there is nothing to roll back, and a
"027-shaped restore" would silently re-introduce the missing `pg_temp` that this migration
exists to fix. `loadForwardCorpus` excludes `.down.sql`, so nothing would have reddened
(architecture P2-3, Kieran P2).

**Ordering is emitted in SQL and re-asserted in TS.** `GROUPING(b.bucket) DESC` puts the
total row first, then total descending, then bucket name ascending as the tiebreak.

The SQL ordering is *reliable here but not formally guaranteed to the caller*, and the plan
should not pretend otherwise. A `LANGUAGE sql` set-returning function whose body the planner
**inlines** loses its internal `ORDER BY`; inlining is what would break this. It cannot
happen for this function — Postgres does not inline `SECURITY DEFINER` functions — so the
emitted order is preserved in practice, and the in-function `ORDER BY` also makes the
operator's direct `psql` use (Phase 5.1) pleasant. But PostgREST issues
`SELECT * FROM fn(...)` with no outer `ORDER BY`, and relying on a set-returning function's
emission order is a convention, not a contract.

So the loader **sorts the returned rows defensively** before rendering. This is not the
"never sum in JS" prohibition (2.6): that rule is about float accumulation across NUMERIC
values, and sorting ≤ 8 already-coerced rows accumulates nothing. Same reasoning licenses
computing `avgUsd = totalUsd / count` in TS — a single per-row division of server-computed
exact values, never a running total.

`ROLLUP(x)` is exactly `GROUPING SETS ((x), ())`; the shorter form is used because it lets
the bucket be named once and drops the outer `CASE … GROUPING(CASE …)` wrapper. **Verified
by execution, not inspection:** the architecture reviewer ran this function on a live
Postgres 17.6 and on PG16 — `GROUPING()` over a `CASE` is legal and matches the grouped
expression; the zero-row case returns exactly one `is_total` row (`total=0, n=0`), so the
headline is always derivable and `byWorkflow: []` is well-defined; and on a fixture
spanning two months the parts summed to the whole exactly.
The name is **new**, so there is no overload hazard — mig 027:18-25's `function is not
unique` warning applies to signature changes on an existing name, and is the reason a new
name was chosen over an overload.

### Phase 2 — Loader: `server/api-usage.ts` (RED first)

2.1 Types:

```ts
export interface WorkflowCostRow {
  bucket: string;      // 'brainstorm' | … | 'unrouted' | 'legacy'
  label: string;       // founder-facing, from the editorial map
  totalUsd: number;
  count: number;
  avgUsd: number;      // totalUsd / count
}

export interface ApiUsage {
  mtdTotalUsd: number;
  mtdCount: number;
  rows: ApiUsageRow[];
  byWorkflow: WorkflowCostRow[] | null;   // null == FAILED; [] == no buckets
}
```

`null` vs `[]` is load-bearing (spec-flow): collapsing them is how a partial failure
becomes a wrong number. `ApiUsageRow` is **unchanged** — the per-row workflow label was
cut (see Cut List).

2.2 **Editorial label map** at `lib/messages/workflow-copy.ts`, following
`lib/messages/action-class-copy.ts` and closing with
`as const satisfies Record<WorkflowBucket, WorkflowCopy>`. That rail makes a missing or
extra key a **compile error**, which is the whole completeness guarantee. Raw wire values
never reach the DOM.

**It must be `import type`, not a value import.** `action-class-copy.ts` can value-import
its authority only because `server/scope-grants/action-class-map.ts` is one of exactly four
modules on the `VALUE_SAFE_PATH` allowlist at
`apps/web-platform/.dependency-cruiser.cjs:68-69`
(`domain-leaders|providers|team-names-validation|scope-grants/action-class-map`).
`server/conversation-routing.ts` is **not** on that list, and its `WORKFLOW_NAMES` set is
`const` without `export` anyway. So `WorkflowBucket` is derived type-only — which is
sufficient, because the `satisfies` rail is a type-level check. A value import here would
trip the client/server import-boundary gate (architecture P2-5).

2.3 The parallel batch is the existing conversation-list SELECT **plus the new aggregate
only**. Use `Promise.allSettled`, not `Promise.all`: the existing loader returns `null` on
either `.error`, and a promise that *rejects* would throw past that handling and silently
convert the intended degradation into fail-whole.

2.4 **The headline comes from the aggregate's `is_total` row, and the fallback is
SEQUENTIAL.** This is the correction the Phase 4.5 advisor forced and it is the subtlest
thing in the plan. Calling `sum_user_mtd_cost` *in parallel* as a safety net would
reintroduce the race CFO F2 blocked, one layer up: the headline would come from a second
transaction, so headline-vs-buckets could disagree exactly as headline-vs-two-RPCs would
have. The single-snapshot guarantee must be scoped to the pair the UI asks the reader to
reconcile, and that pair is *headline and buckets*. Therefore `sum_user_mtd_cost` is
called **only** in the rejection arm, sequentially, restoring today's exact behaviour. In
the happy path it is not called at all — which also removes a permanent extra round trip.
It stays in the codebase because it is the fallback, full stop. *(An earlier draft also
claimed "migration 125 also references it". That is false and was removed:
`125_list_conversations_enriched.sql:21` mentions `sum_user_mtd_cost` only in a **prose
comment** describing the security model of two other RPCs — there is no call and no
dependency. A reader would have gone looking for a SQL dependency that does not exist.)*
Its real consumers, which the plan must edit, are enumerated in `## Files to Edit`.

2.5 **Partial failure.** If the aggregate fails while the list succeeds, the section
renders as today with `byWorkflow: null` plus one user-visible line, so "broken" is
distinguishable from "you only have one workflow". Mirrored with its own tag, never folded
into an existing dashboard-keyed one:

```ts
reportSilentFallback(err, { feature: "api-usage", op: "mtd-by-workflow",
                            extra: { code: err?.code ?? null } });
```

2.6 **PostgREST NUMERIC is a JS string** (`api-usage.ts:181-186`). Coerce with `Number(...)`
at the boundary. **Never sum in JS** (CFO C4) — the sum invariant is asserted SQL-side on
NUMERIC; TS only renders server-computed values.

2.7 `.service-role-allowlist`: comment amended to name both RPCs. **No new path.**

### Phase 3 — UI: `components/settings/api-usage-section.tsx`

Renders between the MTD summary line and the conversation list, per
`knowledge-base/product/design/byok-cost-tracking/workflow-cost-breakdown.pen`. Copy comes
from the char-budgeted spec, never inline.

Each row shows label, total, count, and **average per conversation** — the issue's question
is comparative, and a bare total is dominated by frequency (spec-flow §4, P7). The copy
must not let "average" read as "what a brainstorm costs": `n` counts **conversations**, and
one conversation can span days of work.

**Suppression matrix** (4 states):

| State | Render |
|---|---|
| ≥ 2 buckets with non-zero spend | The breakdown, ordered by total descending, tie-broken by bucket name |
| every bucket is `legacy` | One explanatory line, no bars — a *different* message from "only one workflow": tracking started recently and the split will appear |
| any other single-bucket or zero-MTD-with-history case | **Nothing.** Silence is what makes the failed state legible: on this surface absence means "only one workflow" and a line means "something failed" |
| `byWorkflow === null` | Section renders as today **plus** one unavailable line. No error banner — the headline and list are correct and complete |

*(The simplicity review proposed collapsing legacy-only into the silent arm on the grounds
that it is a single-bucket case. It is set-wise, but the copywriter wrote §16(b)
deliberately: a new user seeing nothing learns nothing, whereas "tracking started
recently" is actionable. The carve-out is ordered ahead of the generic rule so the
§16(a) distinction still holds.)*

**Display precision.** `formatUsd` renders `< $0.01` at 4dp and everything else at 2dp, so
rounded parts do not visibly add to a rounded whole — potentially ~$0.045 of visible
discrepancy across 8 buckets, beneath a "match to the cent" promise. **This is a real
failure on data with no race at all**, so a correct single-snapshot query does not fix it.
In order of preference: (1) **largest-remainder allocation** — round each bucket, then
allocate the residue to the largest fractional remainders one cent at a time, so the
displayed parts sum to the displayed whole; (2) uniform precision across the column and
its subtotal; (3) the copy spec's rounding sentence. In every case a non-zero amount below
display precision renders the literal `<$0.0001` rather than `$0.0000`.

**Scoping the cross-check footnote** (CPO B3, blocking). The Anthropic Console has no
workflow dimension, so the breakdown cannot be cross-checked there. The `match to the cent`
clause stays byte-unchanged and stays true for the headline and the conversation rows; one
sentence is added enumerating what the Console **can** confirm. The same edit corrects the
existing hedge — pre-2026-05-12 conversations **under-report** cache-read tokens; they do
not "may under-reflect" them, and a hedge describing a deterministic condition on the one
surface built on exactness is its own defect (copy spec §15b).

**Attribution disclosure** (CFO F7). Renders whenever the breakdown renders — not behind a
tooltip, not conditional on bucket count. States the mechanism (attribution to the workflow
a conversation **first** dispatched into) with a worked `plan → work` example, not a hedge;
the copy spec bans `estimated / approximate / around / roughly / ~`.

The breakdown lives **inside** `api-usage-section.tsx` as a local component alongside
`UsageBody` / `UsageList` / `EmptyState` / `ErrorState`. If review prefers extraction, its
test must land in `test/components/settings/` — vitest never collects co-located tests.

### Phase 4 — Tests

See `## Test Scenarios`. Test files land under `apps/web-platform/test/**` only.

### Phase 5 — Operator surface + deferral tracking issues

**5.1 The operator's fleet-wide query.** Document in
`knowledge-base/engineering/operations/runbooks/supabase-log-query.md` (or a sibling), one
block, no code:

```sql
-- Per-workflow spend, all users, any window. Exact and durable — this is the
-- source the per-user settings breakdown partitions, not a copy of it.
SELECT COALESCE(active_workflow, 'legacy') AS bucket,
       count(*) AS conversations, sum(total_cost_usd) AS usd
  FROM conversations
 WHERE total_cost_usd > 0 AND created_at >= '<since>'
 GROUP BY 1 ORDER BY 3 DESC;
```

Run with `doppler run -c prd -- psql "$DATABASE_URL"` — the mechanism
`apps/web-platform/scripts/run-migrations.sh:8-10` already documents. No SSH
(`hr-no-ssh-fallback-in-runbooks`).

**5.2 Tracking issues**, each with what, why, and a re-evaluation criterion. Labels
verified present via `gh label list --limit 200`.

| Deferred | Why | Re-evaluate when |
|---|---|---|
| **Per-agent cost attribution** (what #1055 stays open for) | Not derivable from the money-carrying frame; leader grain is a constant on the dominant path | The SDK exposes agent identity on the result frame, **or** a token-only per-agent surface is judged sufficient — `SDKTaskProgressMessage.usage.total_tokens` + `subagent_type` exists today and answers the token question without a dollar figure |
| cc-path `model: null` | `modelUsage` is a `Record`, the marker field a scalar, and the three paths already disagree about what `model` means | Any change that already opens the `onResult` contract |
| Turn-grain workflow attribution | Reopens NG3; mig 132 exists because this instance cannot afford another per-turn write path | Phase 0.1's measurement or a user report shows first-Skill-wins mis-attribution is material |
| MTD window means *created-this-month*, not *spent-this-month* (R4) | Pre-existing; changing it changes the headline number users already see | Phase 0.3's skew measurement is material, or a user reports a reconciliation mismatch |
| `drain-prs` absent from the mig-032 CHECK enum | Real workflow, not enumerated, so those sessions land in `unrouted` | The `unrouted` bucket is measured to be materially drain-prs |
| Linking each usage row to its conversation | spec-flow calls it "the single highest-value flow fix on this surface"; a different feature on the same component | Operator decides — raised in `decision-challenges.md` |
| Art. 13 routing-disclosure gap + stale PA-9 status (CLO) | Pre-existing; **not widened** — mig 125's `list_conversations_enriched` already returns `active_workflow` to `authenticated` | Next legal-doc cycle |
| `plugins/soleur/docs/pages/legal/gdpr-policy.md` mirror drift (~11 KB, CLO) | Pre-existing, unrelated to #1055 | Its own cycle; must not be absorbed here |

### Phase 6 — ADR

Per `wg-architecture-decision-is-a-plan-deliverable` — see `## Architecture Decision (ADR/C4)`.
With Phase 2's marker widening cut, ADR-209 is the **only** architecture deliverable and
ADR-108 is not amended.

## Files to Create

| Path | Purpose |
|---|---|
| `apps/web-platform/supabase/migrations/136_workflow_cost_rollup.sql` | The aggregate + the 027 search-path repin |
| `apps/web-platform/supabase/migrations/136_workflow_cost_rollup.down.sql` | Rollback |
| `apps/web-platform/lib/messages/workflow-copy.ts` | Editorial label map with the `satisfies` rail |
| `apps/web-platform/test/supabase-migrations/136-workflow-cost-rollup.test.ts` | Migration-text contract: grants, `pg_temp` pin ×2, single statement, no table DDL, sentinel-literal pin |
| `apps/web-platform/test/server/api-usage-workflow-rollup.test.ts` | Sum invariant, sequential-fallback degradation, `null` vs `[]`, NUMERIC-string coercion |
| `apps/web-platform/test/messages/workflow-copy.test.ts` | Content-shape gates, mirroring `test/messages/action-class-copy.test.ts` |
| `apps/web-platform/test/components/settings/api-usage-breakdown.test.tsx` | The four render states |
| `knowledge-base/engineering/architecture/decisions/ADR-209-conversation-grain-cost-attribution.md` | Ordinal **provisional** |
| `knowledge-base/project/specs/feat-one-shot-1055-per-workflow-cost-observability/decision-challenges.md` | Headless User-Challenge record (written at plan time) |

## Files to Edit

| Path | Change |
|---|---|
| `apps/web-platform/server/api-usage.ts` | `WorkflowCostRow`; `byWorkflow`; `allSettled`; headline from `is_total`; sequential `sum_user_mtd_cost` fallback; `op: "mtd-by-workflow"` |
| `apps/web-platform/components/settings/api-usage-section.tsx` | The breakdown, the scoped footnote, the hedge fix, the disclosure |
| `apps/web-platform/.service-role-allowlist` | Comment-only: rationale names both RPCs. **No new path** |
| `apps/web-platform/test/api-usage.test.ts` | **Breaks without this edit.** Asserts `expect(mockRpc).toHaveBeenCalledTimes(1)` (`:189`, `:230`) and queues exactly one RPC return per setup (`:77,95,134,167,182,201,218,250,265,276,289`). Phase 2.4 changes both the call count *and* the row shape — the headline now reads the `is_total` row, not `[0]`. Update the mocks to the `{bucket,total,n,is_total}` shape |
| `apps/web-platform/test/api-usage-parity.test.ts` | Same `mockRpc` hoist; same fix |
| `apps/web-platform/test/server/api-usage.tenant-isolation.test.ts` | Extend the existing `sum_user_mtd_cost` 42501 case (`:159-163`) with a sibling for the new function — a committed regression test, not a PR-body psql transcript |
| `apps/web-platform/test/migration-rpc-grants.test.ts` | Remove `"sum_user_mtd_cost"` from `LEGACY_SEARCH_PATH_NO_PG_TEMP` (`:76-79`) and its rationale comment (`:70`). Without this the repin is unenforceable — the gate short-circuits on set membership |
| `apps/web-platform/server/api-usage.ts` *(comments)* | `:4-5` and `:130-131` cite "migration 027:68" as the service-role authority; after 136 they name both functions |
| `knowledge-base/project/specs/feat-restore-byok-usage-dashboard/copy.md` | Char-budgeted breakdown copy (§§11-17, written at plan time) |
| `knowledge-base/product/design/byok-cost-tracking/workflow-cost-breakdown.pen` | The committed wireframe |
| `knowledge-base/engineering/operations/runbooks/supabase-log-query.md` | The operator fleet-wide query (Phase 5.1) |

**Deliberately NOT edited:** `server/cost-writer.ts`, `server/claude-cost-marker.ts`,
`server/cc-dispatcher.ts`, `server/agent-runner.ts`,
`server/inngest/functions/agent-on-spawn-requested.ts`, `_cron-shared.ts`,
`_cron-claude-eval-substrate.ts`, `ADR-108`, `betterstack-log-query.md` — all left the list
when the marker widening was cut. And `docs/legal/**` +
`plugins/soleur/docs/pages/legal/**`: the CLO found no disclosure edit owed, and the mirror
is already ~11 KB adrift under a ratchet lint, so an optional prose edit is pure downside
and would additionally fire the ship Phase 5.5 CLO-attestation gate.

## Acceptance Criteria

Every AC below asserts a post-condition that could silently be false. Criteria that
grepped for text this same diff authors — or that restate a CI check every PR already
runs — were cut at review; `tsc --noEmit`, `vitest run`, `test-all.sh` and the
`definer-grants` corpus lint are CI gates, not acceptance criteria.

**The sum invariant.**

- **AC1** — Against dev, for a user with ≥ 2 buckets in-month, `SUM(total) WHERE NOT is_total`
  equals `total WHERE is_total` **exactly**, and `SUM(n) WHERE NOT is_total` equals
  `n WHERE is_total`. Asserted in SQL on NUMERIC — not a JS float comparison, not an epsilon
  tolerance (CFO F3/F4). Both outputs recorded in the PR body.
- **AC2** — The aggregate's `is_total` row equals `sum_user_mtd_cost(uid, since)` for the
  same arguments. This is the behavioural form of "the predicates match" and cannot be
  fooled by formatting, which is why the earlier textual "byte-identical modulo alias"
  assertion was cut in its favour. **Both calls run inside one
  `BEGIN; … ROLLBACK;`** (or against a fixture user with no live traffic): they are two
  statements, so by this plan's own F2 reasoning an `increment_conversation_cost` landing
  between them would make a correct implementation fail the check —
  `cq-ac-must-not-depend-on-concurrent-sessions` (architecture P2-2).
- **AC3** — Exactly one statement produces both: the migration test asserts a single
  `SELECT` with `ROLLUP` and no second query in the function body (CFO F2). This is also
  the *only* assertion of the concurrency property — a test that interleaves a real
  `increment_conversation_cost` would violate `cq-ac-must-not-depend-on-concurrent-sessions`.
- **AC4** — A fixture with **more than `MAX_USAGE_ROWS` costed conversations spanning two
  months** returns a breakdown that sums to the headline, proving the aggregate is not
  derived from the capped, un-month-filtered list population (CPO B1, CFO C1). The AC cites
  the constant, not the literal `50`, so it keeps testing the boundary if the cap moves.

**Security.**

- **AC5** — `SELECT proacl FROM pg_proc WHERE proname = 'sum_user_mtd_cost_by_workflow'`
  against dev shows EXECUTE for `service_role` **and the function owner**, with **no entry
  for `PUBLIC`, `anon`, or `authenticated`**. Expected literal shape:
  `{<owner>=X/<owner>,service_role=X/<owner>}`, owner taken from Phase 1's baseline read of
  `sum_user_mtd_cost`. *(An earlier draft said "and no other role" — that is literally
  false: the owner always retains EXECUTE, verified by executing this plan's exact
  REVOKE/GRANT block on PG16. An AC that cannot pass gets "fixed" later by loosening it,
  which is worse than never having written it — Kieran P0-2.)* The live `proacl` read is
  the point: the static grant text is already covered by the `definer-grants` corpus lint.
- **AC5b** — The tenant-JWT denial is a **committed regression test**, not a hand-run psql
  transcript: extend `test/server/api-usage.tenant-isolation.test.ts` (which already
  asserts `42501` for `sum_user_mtd_cost` at `:159-163`) with a sibling case. The probe
  itself is confirmed working — the architecture reviewer got
  `permission denied for function sum_user_mtd_cost_by_workflow` under this plan's exact
  grant block. Note the ADR-112 rls-fuzz coverage gate does **not** reach this function:
  `test/rls-fuzz/rpc-cases.ts` enumerates only authenticated-executable RPCs.

**Behaviour.**

- **AC6** — A test drives the aggregate to **reject** (not merely `.error`) while the list
  succeeds, and asserts: a non-null return with `byWorkflow === null`; `mtdTotalUsd` and
  `rows` intact via the sequential `sum_user_mtd_cost` fallback; exactly one
  `reportSilentFallback` with `op: "mtd-by-workflow"`. The rejection case is what proves
  `allSettled` is actually in place, and the `op` assertion is what makes the failure
  discoverable in Sentry.
- **AC7** — `byWorkflow` distinguishes `null` (failed) from `[]` (no buckets), asserted on
  both arms independently.
- **AC8** — In the happy path `sum_user_mtd_cost` is **not called** (the fallback is
  sequential, not parallel), asserted by call-count on the mocked client.

**UI.**

- **AC9** — No raw wire value reaches the DOM: the rendered text contains none of
  `drain-labeled-backlog`, `one-shot`, `__unrouted__`, `unrouted`, `legacy`. Scoped to
  rendered output, not the source file, which legitimately contains them as map keys.
- **AC10** — Each of the four suppression states has a passing component test in
  `test/components/settings/`, collected by the `component` project's `test/**/*.test.tsx`
  glob.
- **AC11** — The attribution disclosure renders whenever the breakdown renders — not behind
  a tooltip, not conditional on bucket count (CFO F7) — and contains none of the banned
  hedges. **Scoped to the copy STRINGS, not the spec section**: the spec's rationale prose
  legitimately names the banned words as documentation, so a section-wide absence-grep
  returns a false failure (verified: it returns `1` on a correct spec). Correct form, with
  the coverage count that keeps the `0` from being vacuous:

  ```
  awk '/^## 1[1-7]\./{f=1} f' <copy.md> | grep -oE '^`[^`]+`' \
    | grep -icE 'estimated|approximate|roughly|around|~'      # → 0
  awk '/^## 1[1-7]\./{f=1} f' <copy.md> | grep -coE '^`[^`]+`' # → ≥ 6, scope non-empty
  ```

- **AC12** — Displayed breakdown values and their subtotal visibly sum; a non-zero amount
  below display precision renders `<$0.0001`, never `$0.0000` (CFO F6).
- **AC13** — The `match to the cent` clause is **byte-unchanged** (a diff of that clause
  shows zero modifications) and the added sentence scopes the claim away from the breakdown
  (CPO B3). The hedge fix is asserted on **rendered** component output, not on source text,
  and asserts the **positive** replacement: the rendered footnote contains `under-report`
  and does not contain `under-reflect`. *(A source grep for `may under-reflect` is vacuous —
  the current JSX splits it across a line break at
  `components/settings/api-usage-section.tsx:142-143`, so the grep returns `0` today, on the
  unfixed file. That is precisely the proxy-vs-invariant failure R2 warns about, found in
  this plan's own AC by Kieran P1-3.)* JSX collapses whitespace, so the rendered assertion
  is stable.
- **AC14** — `legacy` and `unrouted` render as distinct, plainly-labelled rows: not merged
  into a single "Other", no warning colour class, no alert icon, and never a bare `—`
  heading a dollar figure (CFO F8). Asserted on the testable predicates only.

**Guard.**

- **AC15** — The sentinel-literal pin (Guard Contract G1) reds when the migration's
  `'__unrouted__'` literal and `SENTINEL_UNROUTED` in `server/conversation-routing.ts`
  disagree, and its dispatch count is asserted non-zero.
- **AC15b** — The migration test asserts, **at text level**, that the set of
  `THEN '<literal>'` arms in the `CASE` equals `{'legacy','unrouted'}` and that the `ELSE`
  arm passes `active_workflow` through unmodified. It does **not** claim to assert the
  function's output *values*: `032-workflow-state.test.ts:6-10` states the category
  explicitly — *"a file-parse test, not a live-DB test"* — and a text parser cannot observe
  output. The value-level claim is discharged by AC1's dev query (Kieran P1-5).
- **AC15c** — Every AC in this plan whose expected output is a count of `0` is written so a
  zero-match `grep` cannot read as a command failure: `[ "$(grep -c … || true)" = "0" ]`,
  never a bare `grep -c … → 0`. `grep` exits 1 on zero matches, and under
  `hr-when-a-command-exits-non-zero-or-prints` that reads as a failed step in the
  transcript (architecture P2-7, Kieran P2).

**Process.**

- **AC16** — Migration applied to **dev** and verified before merge; the prd path runs from
  the `migrate` job in `web-platform-release.yml` on push to main. No separate post-merge
  step (`hr-ship-message-no-operator-checklist`).
- **AC17** — `## Domain Review` names the committed `.pen`, which exists and is non-empty;
  and the copy spec carries char-budgeted entries for every new string, with no new
  user-facing string authored inline in the TSX.
- **AC18** — The eight Phase 5.2 tracking issues exist with re-evaluation criteria, and
  every label used is present in `gh label list --limit 200`.
- **AC19** — `ADR-209` (or its re-verified ordinal) exists, and no artifact for this branch
  cites a stale ordinal. The grep must be **decision-bearing**, not `ADR-2[0-9][0-9]`: this
  plan legitimately names ADR-204, 205, 206 and 207 in Research Insights, §ADR and Sharp
  Edges, so a broad pattern can never "resolve to the committed filename" (Kieran P1-4).
  Anchor on `ADR-209-conversation-grain` and assert it equals the committed ADR's filename
  stem.
- **AC20** — The PR body uses **`Ref #1055`**, not `Closes #1055`, and states plainly that
  per-agent attribution is not delivered. `wg-use-closes-n-in-pr-body-not-title-to` is
  satisfied by the successor issue's `Closes`, not this PR's.

## Test Scenarios

| # | Scenario | Expected |
|---|---|---|
| T1 | 3 workflows + 1 legacy conversation, in-month | 4 bucket rows + 1 total row; `Σ total === is_total.total`; `Σ n === is_total.n` |
| T2 | More than `MAX_USAGE_ROWS` costed conversations across two months, some spanning the boundary | Breakdown sums to the headline; prior-month rows excluded from both identically |
| T3 | One conversation at `$0.004200` | Its bucket total is `0.0042`, not `0` — the cent-rounded `audit_byok_use` path is not involved |
| T4 | Only legacy conversations | The legacy-only explanatory line renders; no bars |
| T5 | Exactly one non-legacy bucket | Nothing renders; headline unchanged |
| T6 | Aggregate **rejects**; list succeeds | Non-null return, `byWorkflow === null`, headline via the sequential fallback, one `op: "mtd-by-workflow"` report, unavailable line renders |
| T7 | Aggregate returns zero buckets | `byWorkflow === []`, distinct from `null` |
| T8 | Conversations SELECT errors | Existing whole-section `null` behaviour preserved |
| T9 | NUMERIC totals arrive as JS strings; `active_workflow = '__unrouted__'` present | Coerced with `Number(...)`, no JS-side summation; emitted as `unrouted`, rendered under its label, neither string in the DOM |
| T10 | 8 buckets rendered | Ordered by total descending, tie-broken by bucket name; ordering asserted |
| **G1** | *Mutation:* change the migration's `'__unrouted__'` literal so it no longer equals `SENTINEL_UNROUTED` | Guard **reds** |
| **G2** | *Mutation:* make the guard's enumeration return zero members | Guard **reds** on its dispatch floor — never a silent 0-checked pass |
| **H1** | *Harness:* delete the guard's assertion body, leaving the loop | Suite **reds** via the dispatch floor |
| **H2** | *Must-pass non-canonical:* the label map reordered, with the same key set | Suite **passes** — the guard is not a `diff` against one canonical fixture |

*(Completeness of the label map is not a test row: `as const satisfies Record<WorkflowBucket, WorkflowCopy>`
makes a missing or extra key a compile error, which is strictly stronger than a runtime
loop and is the convention `action-class-copy.ts:160` already sets.)*

## Observability

```yaml
liveness_signal:
  what: >
    `loadApiUsageForUser` returning a non-null `ApiUsage` whose `byWorkflow` is not
    `null` for a user with in-month spend. The negative signal is the
    `api-usage` / `mtd-by-workflow` Sentry event.
  cadence: per settings-page render (user-driven; no cron)
  alert_target: >
    Sentry — existing `feature: "api-usage"` tag stream. No new alert rule: this is a
    degraded supplementary read that falls back to today's exact behaviour.
  configured_in: >
    `apps/web-platform/server/api-usage.ts` (emit); `reportSilentFallback` routes to
    Sentry per `cq-silent-fallback-must-mirror-to-sentry`. Observability layer 3
    (application/server) per `hr-observability-layer-citation`.

error_reporting:
  destination: Sentry via `reportSilentFallback` (`server/observability.ts`)
  fail_loud: >
    Loud in Sentry; in the UI, one explicit unavailable-line rather than an error
    banner. A missing block with no explanation is its own dead end, and a full banner
    would blank a working money display over a supplementary read.

failure_modes:
  - mode: The aggregate errors or rejects (grant drift, migration not applied, timeout)
    detection: Sentry event `feature: "api-usage"`, `op: "mtd-by-workflow"` — a tag value
      that exists nowhere else in the codebase; asserted by AC6
    alert_route: Sentry issue stream; no paging rule
  - mode: Grant drift — the aggregate becomes callable by `authenticated`
    detection: AC5's live `pg_proc.proacl` read pre-merge; ongoing, the `definer-grants`
      corpus lint (`test/migration-lint/definer-grants.ts`, #6328/ADR-112) which sweeps
      every forward migration for the REVOKE union
    alert_route: CI `test` check (blocking)
  - mode: Sum divergence — a future edit changes one predicate and not the other
    detection: AC2's behavioural cross-function parity assertion
    alert_route: CI `test` check (blocking)
  - mode: Two-snapshot regression — someone splits the aggregate into two queries, or
      restores the parallel `sum_user_mtd_cost` call
    detection: AC3 (single-statement) + AC8 (not-called-in-happy-path)
    alert_route: CI `test` check (blocking)
  - mode: Sentinel drift — the migration's `__unrouted__` literal and the TS constant
      diverge, silently giving every unrouted conversation its own raw-slug bucket
    detection: the Guard Contract's literal pin (G1)
    alert_route: CI `test` check (blocking)
  - mode: Label-map drift — a new workflow ships with no label
    detection: `tsc` — the `satisfies Record<…>` rail makes it a compile error
    alert_route: CI `typecheck` check (blocking)

logs: >
  where: no new log surface. The operator's fleet-wide view is the SQL query documented
  in Phase 5.1, run against prd Postgres via `doppler run -c prd -- psql` — exact,
  durable, and not subject to any log-retention window. An earlier draft added a field to
  the ADR-108 Better Stack marker for this; it was cut because that surface would have
  been a 90-day lossy copy of this one.
  retention: n/a — Postgres is the source of record.

discoverability_test:
  command: rg -c 'op: "mtd-by-workflow"' apps/web-platform/server/api-usage.ts
  expected_output: "1"
```

## Encryption Posture

This plan introduces **no persistent store and no cross-component connection**. The posture
is stated for the existing store the read-only aggregate reads, because the Phase 2.11
detection regex fires on `supabase/migrations/.*\.sql`.

```yaml
at_rest:
  - store: public.conversations (existing; Supabase Postgres, prd project)
    mechanism: >
      Supabase-managed volume encryption on the managed Postgres instance — not a
      Soleur-operated key. No new store, no new column, no change to how any byte is
      written: the migration adds a STABLE function and repins a sibling's search_path.
    evidence: >
      The same platform encryption every prior migration touching this table relies on
      (017, 027, 032, 041). No new attestation is obtained, and none is claimed.
    defends_against: physical media compromise of the managed instance's storage
    does_not_defend: >
      A compromised service_role key, SQL injection reaching the function, or an
      application-layer IDOR passing an attacker-chosen `uid`. Those are defended by the
      REVOKE/GRANT chain (AC5) and the UUID validation at `api-usage.ts:94` — NOT by
      encryption at rest.
    disclosed_as: >
      No change. Cost telemetry over `public.conversations` is already disclosed at
      Privacy Policy §4.7, DPD §2.3(i), GDPR Policy §3.7 and §10 item 10, and registered
      as Article 30 PA-2.
    live_verification: AC5's `pg_proc.proacl` read against dev

in_transit:
  - connection: web-platform server → Supabase Postgres (existing PostgREST/HTTPS)
    tls: yes (existing supabase-js client; no new client, no new endpoint)
    cert_verification: on (platform default; not disabled anywhere in this change)
    does_not_defend: an attacker already holding the service-role key
    disclosed_as: no change

exception: none — no plaintext-exception store and no `cert_verification: off` connection
  is introduced.
```

## Guard Contract

### Guard 1 — sentinel-literal pin

**Property.** The `__unrouted__` literal in migration 136 is the same string as
`SENTINEL_UNROUTED` in `server/conversation-routing.ts`.

**Why this guard and not a bigger one.** The design deliberately puts the magic string into
the migration so the sentinel can be normalised away in SQL and never cross into TS. That
is the right trade, but it means the module's "must never leak past this module" rule is
violated *by design* in one controlled place — and a controlled violation with no tripwire
is just a violation. A rename on either side would silently give every unrouted
conversation its own raw-slug bucket: no error, no test failure, wrong money on screen.

**Assembly.** Two authorities, each read at its source, not enumerated as a snapshot:
the private constant's *value* parsed out of `server/conversation-routing.ts`, and the
`CASE WHEN … = '<literal>'` string parsed out of
`supabase/migrations/136_workflow_cost_rollup.sql`. There is exactly one such literal in
the migration and the guard asserts that count too, so adding a second normalisation arm
without updating the guard reds rather than being half-checked.

**Deliberately NOT in this guard:** label-map completeness. That is enforced at compile
time by `as const satisfies Record<WorkflowBucket, WorkflowCopy>` in
`lib/messages/workflow-copy.ts`, mirroring `action-class-copy.ts:160`. An earlier draft
proposed a runtime guard parsing the SQL for workflow names — but the migration's `CASE`
literals are only `'legacy'` and `'unrouted'`; the six workflow names arrive through the
`ELSE` branch, which no regex over the SQL can see. Building a parser to enumerate an
exhaustiveness rail inverts this plan's own binding learning that `tsc`, not grep, is the
enumerator.

**Mutation matrix.**

| # | Mutation | Guard must |
|---|---|---|
| G1 | Change the migration's `'__unrouted__'` literal (or rename the TS constant's value) so the two disagree | RED |
| G2 | Add a second `CASE WHEN … = '<literal>'` normalisation arm to the migration | RED — the literal count is asserted, so a second arm cannot be silently half-checked |
| G3 | Make the guard's enumeration return zero members (either authority parses empty) | RED on a dispatch floor — a guard reporting "0 checked" and exiting 0 is vacuous |

**Harness rows.**

| # | Edit | Suite must |
|---|---|---|
| H1 | Delete the guard's assertion body, leaving the parse | RED — the dispatch floor catches a harness that asserts nothing |
| H2 | Feed a non-canonical but permitted input: the migration reformatted (whitespace, quoting style) with the same literal | PASS — the guard compares values, not file bytes |

## Architecture Decision (ADR/C4)

### ADR

**ADR-209 — Conversation-grain attribution for LLM cost observability** *(ordinal
provisional; ADR-205/206 are claimed on pushed branches; `/ship` re-verifies against
`origin/main` before merge)*.

Decision: **cost is attributed at conversation grain, using the write-once
`active_workflow` the routing layer already persists — not at turn grain.**

It is a real architectural decision because it confirms and extends the 2026-05-12 plan's
NG3 non-goal into a new domain (attribution, not just accounting), and because a future
engineer reading only the existing ADRs would be misled about why cost observability has no
per-turn event table. The ADR records:

- the decision and its grain, and the **first-Skill-wins** semantics that follow;
- `## Alternatives Considered` — the per-turn `usage_events` table (NG3 + mig 132's
  write-amplification posture), a `workflow` column on `audit_byok_use` (WORM carve-out,
  DSAR Art. 15, six INSERT sites, cent-rounded cost), and a workflow-span table (machinery
  for a limitation that is disclosable);
- the accepted limitation (R2) and the measurement (Phase 0.1) that bounds it;
- that **one durable surface serves both audiences** — the same two columns answer the
  per-user settings question and the operator's fleet-wide question, the latter as a
  documented query rather than a second telemetry substrate. A draft of this plan added a
  workflow field to the ADR-108 log marker for the operator half; it was cut, and the ADR
  records why so the idea is not re-proposed;
- that `SECURITY DEFINER` is strictly **redundant** here — only `service_role` may execute
  and `service_role` already bypasses RLS — retained for symmetry with the adjacent
  `sum_user_mtd_cost` it repins, stated explicitly so a future reader does not infer the
  definer bit is load-bearing.

**ADR-108 is not amended**, because the marker is untouched.

### C4 views

**No C4 model change is required.** Per the C4 completeness mandate this is backed by
reading all three of `model.c4`, `views.c4` and `spec.c4` — not a feature-noun grep — and by
enumerating:

- **External human actors.** None added; the only actor is the existing `founder`.
- **External systems / vendors.** None added. `anthropic` ("Claude LLM for agent reasoning
  and tool use") is modelled and unchanged — this plan makes no new call to it. `sentry` is
  modelled and already receives the fallback events. With the marker cut, `betterstack`
  receives nothing new either.
- **Containers / data stores.** None added. `platform.infra.supabase` ("Supabase
  PostgreSQL — Users, BYOK-encrypted API keys, conversation sessions") already covers the
  `conversations` table; the description stays true because no new category of data is
  stored.
- **Actor↔surface access relationships.** Unchanged. Owner-scoped per-user read through the
  same RLS-enforced tenant client and the same service-role RPC posture the existing MTD
  rollup uses. No single-owner → shared transition; no new grant to any role.

**Count parity.** `model.c4`'s edge prose embeds derived cardinalities the
actor/system/relationship rubric does not reach. This change adds no cron, monitor, Resend
emitter or heartbeat workflow, and the conclusion is backed by a green run of
`bash plugins/soleur/test/c4-count-parity.test.sh` (note: under `plugins/`, not
`apps/web-platform/test/`), recorded in the PR body.

### Sequencing

The ADR describes the state as of this merge. No soak gate, no `adopting → accepted`
transition.

## Domain Review

**Domains relevant:** Engineering (CTO), Finance (CFO), Legal (CLO), Product (CPO).
Marketing, Sales, Operations, Support: assessed, not relevant.

### Engineering (CTO)

**Status:** reviewed

Two stated premises were falsified. (A1) `active_workflow` is **write-once and monotonic** —
no mid-life reset; the real defect is first-Skill-wins, worst for a conversation routed
directly to `plan` that continues into `work`, where the expensive phase bills to the cheap
one. For `one-shot` the nesting is arguably correct. (A2) `domain_leader` is degenerate on
the dominant path (`cc_router`). (A3) Widening `ClaudeCostMarker` would extend an adopted
ADR whose field set is test-pinned, making an ADR-108 amendment a deliverable — **moot, the
widening was cut**. (A4) `wg-ui-feature-requires-pen-wireframe` fires, with an existing
anchor to extend. (A5) The marker PII boundary permits a closed enum but must be cited —
moot. Risks: (R1) the closure-cell mechanism was sound and survived an attempt to break it —
moot with the cut. (R2) the marker's operator value is bounded because 2 of 3 choke points
have no workflow concept — this became the decisive argument for cutting it. (R3) the
widening was 4 emit sites, not 3. (R4) two new `__`-sentinels would trip
`hr-write-boundary-sentinel-sweep-all-write-sites` — resolved by normalising to plain keys.
(R5) the list SELECT is tenant-scoped under RLS, not service-role. (R6) fix
`sum_user_mtd_cost`'s missing `pg_temp` inline — **folded into the migration**.

**Verdicts:** (Q1) conversation-grain is defensible, but the stated limitation was the wrong
one — do not build turn-grain; fix the text. (Q2) cutting subagent grain is right, but do
not let the PR close #1055. (Q3) do **not** bundle the `model` fix — `modelUsage` is a
`Record` and the marker field a scalar, so all three paths already disagree about what
`model` means; it needs its own ADR-108 amendment. (Q4) **accept the heap fetch, do not
touch the index** — and the write-amplification argument is weaker than assumed
(`total_cost_usd` is already an INCLUDE column); what disqualifies the index is the
write/read ratio.

### Finance (CFO)

**Status:** reviewed

The sum invariant is the right criterion but is **not free by construction**. (C1) The
headline RPC and the 50-row list have **different predicates** — no month filter, `LIMIT 50`
— so a breakdown derived from the list would not sum for any user with >50 costed
conversations. (C2) Two RPCs are two MVCC snapshots and `increment_conversation_cost` fires
every turn. (C3) Month-boundary skew if the aggregate computes its own window. (C4) Display
rounding: ~$0.045 of visible discrepancy across 8 buckets beneath a "match to the cent"
promise; mixed 2dp/4dp makes the column unaddable; `toFixed(4)` renders a non-zero
sub-$0.0001 charge as `$0.0000`; and JS-side summation of `Number()`-coerced NUMERIC strings
reintroduces float drift.

On attribution: "how much your brainstorms cost" is **not acceptable** — it asserts a
per-activity cost the data cannot support. The risk is *precision-halo transfer*: a
breakdown inside the same bordered section inherits the to-the-cent guarantee. On buckets:
neither `legacy` nor `unrouted` is an error or a hidden charge; no warning colour, no alert
icon, no merging them. On billing model: the boundary is correct and nothing re-opens
Decision 6 — but the bucket names are namespace-identical to the operator's local loops, so
extending this breakdown to those must be treated as re-opening it. On expenses: no new or
changed recurring vendor expense; `wg-record-recurring-vendor-expense-before-ready` does not
apply. Product COGS stays $121.08/mo, re-derived from the ledger.

**Blocking: F1, F2, F3, F7** — folded as AC4/AC2, the single-statement design + AC3, AC1's
SQL-side NUMERIC assertion, and AC11. F4/F6/F8/F9 folded as AC1, AC12, AC14, AC13.

### Legal (CLO)

**Status:** reviewed

**No blocking items.** Falls under existing **Article 30 PA-2 — Conversation Data**; no new
processing activity, personal-data category, recipient, or sub-processor. On purpose
limitation: Privacy Policy §4.7 uses closed-list framing and names purpose (ii) as
"per-user usage observability via the in-product `/api/usage` aggregator" — a per-workflow
breakdown through that exact aggregator changes the *granularity* of a disclosed purpose,
not the purpose. The closed-list reading is the strongest available objection and is
recorded so the reviewer sees it; the verdict holds. On DSAR: derived from already-exported
data; the design's avoidance of `audit_byok_use` keeps the Art. 15 payload untouched.

**Disclosure surfaces: none required** — and actively **do not touch them**.
`plugins/soleur/docs/pages/legal/gdpr-policy.md` is already ~11 KB adrift from canonical and
`lint-legal-mirror-drift-baseline.sh` is a ratchet in which in-place edits of an
already-drifting line fail. Two advisory follow-ups, both pre-existing and not widened here:
the Art. 13 routing-disclosure gap with PA-9's stale "not exposed" status, and the mirror
drift itself.

### Product/UX Gate

**Tier:** blocking — the mechanical UI-surface override fires on
`components/settings/api-usage-section.tsx`.
**Decision:** reviewed
**Agents invoked:** spec-flow-analyzer, cpo, ux-design-lead, copywriter
**Skipped specialists:** none
**Pencil available:** yes — `.pen` committed at
`knowledge-base/product/design/byok-cost-tracking/workflow-cost-breakdown.pen`
(117,871 bytes; commits `b23b7b7ba`, `b6fa9d916`), with frames 06-12 continuing the existing
01-05 numbering.
**Wireframe review:** headless arm — this plan runs inside a one-shot Task subagent, so per
`plan/SKILL.md` §Product/UX Gate step 4b the review pause is suppressed and the wireframes
are ready for async review at the exported screenshots directory.
**Brainstorm-recommended specialists:** none — no brainstorm preceded this plan.

#### Findings

**spec-flow-analyzer.** Independently caught the first-write-wins premise error, and drew
the sharper consequence: a conversation opening in `brainstorm` that then does the expensive
`plan` and `work` phases bills 100% to `brainstorm`, so the bucket capturing the money is
systematically the *earliest, cheapest* phase — a user reading "Brainstorm $61.20 / Work
$0.00" changes exactly the wrong behaviour. Also: the three populations on screen do not
describe the same thing; rounding breaks the *visible* sum even when the DB sum holds;
`__unrouted__` must not reach the UI; the zero-MTD-with-history state was undefined; and
`Promise.all` plus a *rejecting* third promise turns the intended degradation into
fail-whole. On value: a month-to-date **total** is dominated by frequency, so adding `n` and
`avg` "flips the feature from a vanity total into the thing the issue actually asked for".

**CPO.** **Sign off with conditions** (B1-B5), all folded: B1 → AC4; B2 → the
`lib/messages/workflow-copy.ts` map + AC9; B3 → AC13; B4 → AC17; B5 → this plan's
`## User-Brand Impact` + the review-time agent. Confirmed the `single-user incident`
threshold as correctly declared while noting it is not uniform across the change. Two
recommendations are **not** folded and are recorded as challenges rather than silently
applied: making `domain_leader` the *primary* cut (contradicted by CTO A2 — Phase 0.1
measures and settles it), and re-milestoning #1055.

**copywriter.** Char-budgeted §§11-17 appended to the existing copy spec. **`copy.md` is the
authority for user-facing strings; the `.pen` is the authority for layout.** §11's subhead
states the attribution rule before the reader sees a number and says "Nothing is left out"
rather than "the parts add up" — the latter would invite hand-addition of rounded rows. §14
carries a worked `plan → work` example, because "first workflow it started" alone reads as a
harmless implementation detail. §15 changes two words and adds one sentence, leaving
`match to the cent` in the same clause and position, framing the addition as what the
Console **can** confirm rather than as a disclaimer. §16(a) gives a single-bucket breakdown
**no copy at all**, because on this surface absence means "only one workflow" and a line
means "something failed". §17's tooltip attaches to the **breakdown block header**, not the
section header, which already carries three tooltips of a different family. Two objections
folded: the footnote rewrite must ship with the breakdown (AC13, and the squash-merge
finding below makes it structurally guaranteed), and the existing `may under-reflect` hedge
is corrected in the same edit.

**ux-design-lead.** Design decisions carried into Phase 3: the breakdown is a **proportional
comparison, not a table**, with bars **scaled to the largest bucket rather than the total**
(scaling to the total renders a $0.0004 bucket as zero pixels beside an $8.12 one); **three
distinct degradation treatments**, with **red reserved** for the section-wide failure where
the founder has no numbers at all; an unrecognised bucket key falls back to a label rather
than a raw slug, as defense-in-depth behind the compile-time rail; and frame 06 demonstrates
the arithmetic on real figures. Note the wireframe's label map uses the raw stored values as
its left column; the keys the UI receives are the SQL-normalised `unrouted` and `legacy`.

### Plan Review Panel (single-user-incident roster)

**code-simplicity-reviewer** returned the largest structural finding in the review cycle and
it was adopted nearly in full: the marker half was "while we're here" — the operator's
fleet-wide question is answered exactly and durably by a `GROUP BY` over the same two
columns, so the plan was shipping a 90-day lossy copy of its own source for 12 of 17 edited
files. Also adopted: `ROLLUP` over a derived table (4 CASE copies → 1); cutting the
SQL-parsing guard authority in favour of the `satisfies` rail; cutting the per-commit
footnote gate as provably vacuous under `--squash` merge; cutting the per-row
`workflowLabel` (no property needs it, and it permanently drops the list query's Index-Only
Scan); cutting the turns/day measurement (a measurement whose outcome cannot change the
decision); Phase 0 from seven preconditions to three; 37 ACs to 20; and the `created_at`
window finding now recorded as R4. Its diagnosis of *why* the plan had grown is recorded
above the Cut List: the growth was reviewer-shaped rather than property-shaped, with seven
reviews each adding a gate and none removing one another review had made redundant.

One recommendation was **partially declined**: collapsing legacy-only into the silent
suppression arm. It is a single-bucket case set-wise, but the copywriter wrote §16(b)
deliberately and the two states carry different messages; the carve-out is ordered ahead of
the generic rule so the §16(a) distinction survives.

**architecture-strategist** verified the design **by execution rather than inspection** —
running the function on a live Postgres 17.6 and confirming `GROUPING()` over a `CASE` is
legal, that the bucket expression can never be NULL (the `IS NULL` arm is first, so the
`ELSE` arm is unreachable for NULL) and therefore cannot collide with the super-aggregate
row, that no enum member is literally `legacy` or `unrouted` so normalisation cannot merge
a real workflow into a sentinel bucket, that the zero-row case returns exactly one
`is_total` row, and that the `sum_user_mtd_cost` repin matches 027's signature and return
type exactly so `CREATE OR REPLACE` is valid and preserves the ACL. **No P0.** Its P1s were
folded: the false migration-125 justification is removed, the real consumers are enumerated
in Files to Edit, and the parity AC is now transaction-wrapped. Its P1-3 (the marker and the
aggregate would attribute the same dollars differently — conversation-grain vs turn-grain —
while the plan claimed they answered "the same question") is **moot**: the marker was cut,
which removed that whole divergence class rather than documenting it.

**kieran-rails-reviewer** ran every verification command and tested the SQL on PG16.
**Its most valuable findings were defects in this plan's own gates, not in its design.**
Folded: the `proacl` expectation was literally unsatisfiable because the owner always
retains EXECUTE; the footnote hedge-grep was vacuous because the current JSX splits
`may under-reflect` across a line break, so it returns `0` on the *unfixed* file; the ADR
grep could never resolve to one ordinal because the plan names four; the migration test
cannot assert output values because it is a file-parse test; the `pg_temp` repin buys
nothing while `LEGACY_SEARCH_PATH_NO_PG_TEMP` still exempts the function; and `grep -c`
expecting `0` exits 1. Its P0-3 (the list-SELECT widening would break sentinel containment)
had already been resolved by cutting `workflowLabel`. **Three of its "corrections" were
themselves wrong and were not applied** — `apps/web-platform/bunfig.toml` really does carry
`pathIgnorePatterns = ["**"]` (it read the *root* bunfig, a different file), and the
`workspace_cost_aggregate` and `capFor` line citations in this plan were already correct.
Reviewer corrections were verified before acceptance, not taken on trust.

**Scoped advisor consult (Phase 4.5, `model: fable`).** Found that the single-snapshot
guarantee was scoped to the wrong pair of numbers — the draft still called
`sum_user_mtd_cost` in parallel, so the headline and breakdown would have arrived from two
transactions and reintroduced the exact race CFO F2 blocked, one layer up. Folded as Phase
2.4's sequential fallback plus AC8. Also: hoist the bucket expression so it appears once
(folded, via `ROLLUP`), pin the `__unrouted__` literal to the module constant because the
no-leak rule is now violated by design in one controlled place (folded as Guard 1), allocate
display residue by largest remainder (folded into Phase 3), and note in the ADR that
`SECURITY DEFINER` is redundant here (folded).

## GDPR / Compliance Gate (Phase 2.7)

**This is not legal review. Findings are heuristic. Consult `clo` +
`legal-compliance-auditor` before merging.**

Invoked inline. `gdpr-gate: path scan complete — 5 examined, 1 matched` (only
`supabase/migrations/136_workflow_cost_rollup.sql` matches the canonical regulated-path
regex).

**Findings: zero Critical, zero Important.** All five mandatory v1 checks are inapplicable
by construction, because the plan adds **no column, no table, no foreign key, and no
vendor**:

| `check_id` | Result |
|---|---|
| `GDPR-Art-9` (special-category) | N/A — 0 new columns |
| `GDPR-Art-6` (lawful basis annotation) | N/A — 0 new columns |
| `GDPR-Art-5e` (retention metadata) | N/A — 0 new PII tables |
| `GDPR-Art-17` / `-caller` (erasure) | N/A — 0 new FKs to `users`, 0 new `anonymise_*` RPCs |
| `GDPR-Chapter-V` (cross-border) | N/A — 0 new non-EEA vendor env vars or SDKs |

The Art. 32 pseudonymization concern on the un-redacted `claude-cost-marker` pino instance
is **moot**: the marker is no longer touched. The design's avoidance of `audit_byok_use`
keeps the DSAR Art. 15 payload untouched.

**Corpus staleness:** `notice-frontmatter.sh days-stale` → **120**, so the >90d
`POSTURE_FAIL` line fires. Per the skill's own operator chain this does **not** pause the
PR, and per `hr-when-triaging-a-batch-of-issues-never` no duplicate issue is filed: the
condition is already tracked by **#7255** (the `cron_run_stale` binding is inert because its
workflow became an Inngest cron, so the freshness probe returns 999 unconditionally),
**#7857** and **#7852**. Recorded here as evidence the gate ran; no new compliance-posture
row.

## Risks & Mitigations

- **R1 (HIGH) — the breakdown stops summing to the headline.** Three distinct causes:
  drifting predicates, two MVCC snapshots, and display rounding. *Mitigations:* both
  figures come from one statement (AC3) with a sequential-only fallback (AC8); the display
  side is largest-remainder allocation (AC12) plus copy that never invites hand-addition.

  **Be honest about which of these CI actually enforces.** AC1/AC2/AC4 are *dev queries
  recorded in the PR body* — a human paste, not a gate. The suites in `test/server/` mock
  the Supabase client, and **a mock cannot prove `Σ buckets = total`**; it can only prove
  the loader arithmetic over a fixture. What CI genuinely protects is the *structural*
  cause: AC3 (single statement) and AC8 (no parallel second read) are text- and
  call-count-assertable, and they catch the dominant regression path — someone splitting
  the query or restoring the parallel call. The value-level invariant is protected
  pre-merge by the recorded dev query and post-merge by nothing. If a runtime gate is
  wanted later, the repo already has the shape in
  `test/server/api-usage.tenant-isolation.test.ts` and `test/rls-fuzz/*.integration.test.ts`,
  both of which hit a live DB. Recorded rather than papered over (Kieran P1-6).

- **R2 (MEDIUM) — first-Skill-wins mis-attribution.** `active_workflow` is write-once and
  monotonic, so a conversation is attributed to the workflow it **first** dispatched into,
  forever. A `one-shot` conversation correctly absorbs its nested plan/work/review; a
  conversation routed directly to `plan` that continues into `work` bills the expensive
  phase to the cheap one, and the bias is systematic toward the *earliest* workflow.
  *Mitigation:* Phase 0.2 re-verifies the write-once property; Phase 0.1 measures the
  distribution; the mechanism is disclosed in the UI whenever the breakdown renders (AC11),
  with a worked example rather than a hedge; it is recorded in ADR-209; turn-grain is a
  filed tracking issue. **A declared limitation, not a hidden one** — the proxy-vs-invariant
  failure the Sharp Edges warn about is a check that *silently* passes on a broken state,
  and here the state is named on the surface itself.

- **R3 (MEDIUM) — unattributed spend dominates at launch.** Every conversation predating
  migration 032 is `legacy`, so for existing users the breakdown could be a single
  "100% legacy" row (CPO G2). *Mitigation:* Phase 0.1 measures it before code is written;
  the suppression matrix gives legacy-only its own explanatory state rather than a bar
  chart of one; buckets are explicit and labelled rather than dropped or merged.

- **R4 (MEDIUM, pre-existing, made more visible) — "month-to-date" means *conversations
  created this month*, not *spend incurred this month*.** `sum_user_mtd_cost` filters
  `conversations.created_at >= since` while `total_cost_usd` is a lifetime accumulator on
  the row (mig 042:44). A conversation created 28 Aug that spends in September contributes
  nothing to September's figure. The sum invariant is unaffected (both sides share the
  predicate), but the *label* is imprecise, and this plan is simultaneously rewriting the
  footnote that tells users to reconcile against the Anthropic Console — which reports by
  date. *Mitigation:* Phase 0.3 measures the skew; the footnote's added sentence is written
  against that measurement; the window itself is **not changed** (that would change the
  headline number users already see) and is a filed tracking issue. Surfaced by the
  simplicity review; no earlier reviewer named it.

- **R5 (LOW) — dev/prd schema drift.** *Mitigation:* dev first and verified (AC16); the prd
  path runs from the `migrate` job on push to main.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Per-turn `usage_events` table | Rejected as out-of-scope by the 2026-05-12 plan (NG3); mig 132 exists because this instance cannot afford another per-turn write path. |
| `workflow` column on `audit_byok_use` | WORM Art. 17 carve-out (066:37), 6 INSERT sites across migs 084/121, DSAR Art. 15 payload, RLS review — and `unit_cost_cents` is cent-rounded, so it is the wrong cost source. |
| Two RPCs (buckets + existing headline) | Two MVCC snapshots. CFO F2, blocking. |
| A parallel `sum_user_mtd_cost` "safety net" | Same defect one layer up — the headline would come from a second transaction. Sequential fallback instead. |
| `GROUPING SETS ((x), ())` written out | `ROLLUP(x)` is identical and lets the bucket be named once, dropping the outer `CASE … GROUPING(CASE …)` wrapper. |
| Overload `sum_user_mtd_cost` with a `group_by` parameter | Mig 027:18-25 warns a signature change needs `DROP FUNCTION IF EXISTS` and a stale overload yields `function is not unique`. |
| Client-side grouping of the 50-row list | Commit `638034307` (#2501) removed exactly this pattern, and the list is a different population. |
| Export `SENTINEL_UNROUTED` and share the literal | Breaks `test/conversation-routing.test.ts:138`. Normalise in SQL and pin the literal instead. |
| A `workflow` field on the ADR-108 marker | A 90-day lossy copy of a durable exact source; 2 of 3 choke points emit `null`. One documented SQL query instead. |
| A runtime guard parsing the SQL for label completeness | The SQL cannot see the six workflow names (they arrive via `ELSE`); `satisfies Record<…>` does it at compile time. |
| Making `domain_leader` the primary cut (CPO R1) | Degenerate on the dominant path (CTO A2). Phase 0.1 measures; the disagreement is in `decision-challenges.md`. |
| Adding `active_workflow` to `idx_conversations_user_cost` | Permanent per-turn index write to accelerate a per-page-render read. |
| Langfuse or another observability vendor | Re-homes cost data into a second source of truth to answer a question two existing columns already contain. |

## Non-Goals

- **Task-complexity model routing / Haiku tiering.** Forbidden by ADR-053 and the
  2026-04-13 brainstorm's unanimous "No model downgrades — quality is non-negotiable".
- **The Anthropic Admin cost-report cron and the pre-exhaustion spend-vs-budget alert.**
  Both need an org-level `ANTHROPIC_ADMIN_KEY`, un-mintable on an individual-tier account
  (ADR-108, #6297).
- **Per-loop dollar figures for the operator's own local Claude Code loops.** Flat
  subscription, $0 marginal; the 2026-06-11 loop-token-cost-ledger brainstorm (Decision 6)
  rejected them. This plan covers only the metered BYOK web-platform path. **Extending this
  breakdown to operator loops, CI runs, or `claude-code-action` spend re-opens Decision 6
  and requires a fresh decision — it is not an incremental follow-up.**
- **Per-turn / per-message cost persistence** (NG3, carried forward).
- **Changing the MTD window's semantics** (R4).
- **Per-agent cost attribution**, **the cc-path `model: null` fix**, **turn-grain
  attribution**, **adding `drain-prs` to the workflow enum**, and **linking usage rows to
  their conversations** — each a filed tracking issue (Phase 5.2).
- **Any change to `workspace_cost_aggregate`.** That view (mig 059:458) computes
  `SUM(unit_cost_cents * token_count)` — a per-call cost times a token count. Whatever its
  intent, it is not the exact-dollar surface; this plan does not read, extend, or fix it.
- **Any edit to `docs/legal/**` or `plugins/soleur/docs/pages/legal/**`** — see CLO.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/
  placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.
- **`active_workflow` is write-once, not last-write-wins.** Three independent reviewers had
  to correct this plan's author on it. The lock is guarded by `state.currentWorkflow === null`;
  `persistActiveWorkflow` refuses to regress; `ws-handler.ts:1084` names the rule
  "first-writer-wins"; and the "Switch workflow" control does not render because
  `onSwitchWorkflow` is never passed to `<WorkflowLifecycleBar>`. Any reasoning that begins
  "when the user switches workflows" is about a path that does not exist.
- **`__unrouted__` must not cross into TS.** `conversation-routing.ts` documents it as a
  storage-layer detail that "must never leak past this module", and
  `test/conversation-routing.test.ts` pins both that the string never appears in stringified
  ADT output (`:57-68`) and that `SENTINEL_UNROUTED` is not exported (`:138`). Normalise in
  SQL; do not export the constant; pin the migration's literal.
- **`audit_byok_use` is a trap for this feature, not a home for it.**
  `unit_cost_cents = Math.round(cost * 100)` renders every sub-cent turn as `0` (R7 of the
  2026-05-12 plan, intentional). Anyone who later "unifies" the cost rollup onto that table
  silently zeroes the long tail.
- **The headline and the conversation list are different populations.** The headline is
  month-scoped and uncapped; the list has **no** month filter and `LIMIT 50`. Any new figure
  between them will be reconciled by a user against both.
- **"Month-to-date" is scoped by conversation *creation* date, not spend date** (R4). The
  headline already means "lifetime spend of conversations created this month". Do not assume
  it reconciles date-for-date against the Anthropic Console.
- **Two statements are two snapshots** — including a "harmless" parallel safety-net call.
  `increment_conversation_cost` fires on every turn, so a headline and a breakdown read in
  separate statements can genuinely fail to sum while both are individually correct.
- **An absence-grep over a spec section hits the section's own rationale.** Verified on this
  plan: the banned-hedge grep returns `1` on a *correct* copy spec because the rationale
  names the banned words as documentation. Scope such greps to the quoted strings, and pair
  the `0` with a non-zero coverage count so it cannot pass vacuously.
- **`sum_user_mtd_cost` pins `SET search_path = public` without `pg_temp`** (`027_mtd_cost_aggregate.sql:48`).
  This plan repins it inline; mirror its grant block, never its search-path line. And note
  `CREATE OR REPLACE` preserves the existing ACL, so no re-GRANT is needed — the
  `definer-grants` corpus lint reads the revoke-union across all migrations, and 027's
  REVOKEs already count.
- **`drain-prs` is a real workflow absent from the migration-032 CHECK enum.** Those sessions
  never lock and land in `unrouted`. Do not read `unrouted` as "the user did nothing".
- **vitest never collects co-located component tests.** The `component` project includes
  `test/**/*.test.tsx`; a `components/settings/*.test.tsx` file is silently never run. And
  `bun test` is blocked repo-wide by `bunfig.toml` (#1469) — the runner is
  `./node_modules/.bin/vitest`. Parity tests live in `test/messages/`, not `test/lib/`.
- **`npm run -w apps/web-platform <script>` aborts** — the repo root `package.json` declares
  no `workspaces`. Typecheck is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- **`plugins/soleur/test/c4-count-parity.test.sh` lives under `plugins/`**, not beside the
  sibling C4 suites in `apps/web-platform/test/`.
- **The ADR ordinal is provisional.** ADR-205 and ADR-206 are claimed on pushed branches but
  not on `origin/main`, so an `origin/main`-only probe reports a free ordinal that is not.
  Re-verify across every `origin/*` ref immediately before merge, and when renumbering sweep
  this plan, `tasks.md`, and AC19 in the same edit.
- **There are TWO `bunfig.toml` files and they say different things.**
  `apps/web-platform/bunfig.toml` is `pathIgnorePatterns = ["**"]` (blocks all bun-test
  discovery for the package); the repo root's is
  `[".worktrees/**", "apps/web-platform/**"]`. Cite by path — a reviewer reading the wrong
  one will "correct" you.
- **There are TWO migrations numbered `041`.** Cite migration filenames, not numbers.
- **`grep -c` exits 1 when it matches nothing.** Any AC whose expected output is `0` must
  be written `[ "$(grep -c … || true)" = "0" ]`, or a correct result reads as a failed
  command under `hr-when-a-command-exits-non-zero-or-prints`.
- **An absence-grep against JSX can be vacuous because of line breaks.** The footnote's
  `may under-reflect` is split across `api-usage-section.tsx:142-143`, so
  `grep -c 'may under-reflect'` returns `0` on the **unfixed** file. Assert on rendered
  output (JSX collapses whitespace) and assert the positive replacement, not only the
  absence of the old string.
- **`proacl` always lists the function owner.** An AC asserting "EXECUTE for `service_role`
  and no other role" cannot pass. Expect `{<owner>=X/<owner>,service_role=X/<owner>}`.
- **A `pg_temp` repin is unenforceable while its exemption stands.**
  `test/migration-rpc-grants.test.ts`'s `LEGACY_SEARCH_PATH_NO_PG_TEMP` short-circuits the
  gate on set membership, so fixing the function without removing the entry leaves CI green
  either way and lets a future migration silently un-pin it again.
- **`lib/` may only value-import four server modules.**
  `.dependency-cruiser.cjs:68-69`'s `VALUE_SAFE_PATH` allowlists
  `domain-leaders|providers|team-names-validation|scope-grants/action-class-map`.
  Anything else — including `server/conversation-routing.ts` — must be `import type`.
- **Mocked `test/server/` suites cannot prove a SQL aggregate's arithmetic.** They mock the
  Supabase client, so they verify loader behaviour over a fixture, not `Σ buckets = total`.
  Do not present a dev-query-recorded-in-the-PR-body as a suite-enforced invariant.
- **Do not touch the legal mirrors.** `plugins/soleur/docs/pages/legal/gdpr-policy.md` is
  ~11 KB adrift and `lint-legal-mirror-drift-baseline.sh` is a ratchet: in-place edits of an
  already-drifting line fail.

---

## Addendum — 2026-09-08 (#7916 review)

This plan was archived unamended while five of its statements had been
deliberately superseded during implementation. The shipped code is what it is on
purpose in every case below; what was missing was the reconciliation. Recorded
here rather than edited in place, because a plan is a dated record of what was
intended and the divergence is the interesting part.

**AC12 / task 3.3.3 — the floor marker is grain-relative, not the literal
`<$0.0001`.** The AC required that literal "in every case". Shipped
`api-usage-section.tsx` renders `<$0.01` at cents grain and `<$0.0001` only at
the finer grain, chosen by `displayGrain()`. The AC as written is not satisfiable
by the shipped design and should be read as superseded: `<$0.0001` next to a
column rendered in cents asserts a precision the column does not have, so the
literal would have been *false on the page*. The invariant the AC was protecting —
a non-zero amount never renders as `$0.00`/`$0.0000` — holds, and is what the
component tests assert.

**AC11 / task 3.3.4 — "not conditional on bucket count" described intent, not
control flow.** The disclosure sits below `if (buckets.length < 2) return null;`,
so it is conditional on exactly that. It is unconditional on the thing that
matters: wherever per-bucket figures render, so does the sentence explaining how
they are attributed — as prose, not behind a tooltip. The suppressed states show
no figures to misattribute. The component comment and the component test were
corrected to say this; the plan and `tasks.md` were not, until now.

**AC18 / task 5.2 — three consolidated trackers, not eight issues.** The eight
rows in the Phase 5.2 table were discharged as: #7928 (drain-prs enum, usage-row
linking), #7929 (the R4 created-vs-spent window, filed standalone because a
headline money figure that means something other than what it says is a defect,
not a follow-up), #7930 (both legal-corpus items). Per-agent attribution stays
on #1055 itself, which is why the PR says `Ref` and not `Closes`. Turn-grain
attribution and the cc-path `model: null` shape were deliberately NOT filed —
both are plan Non-Goals with no observable re-evaluation trigger, and filing them
would have parked them indefinitely. Eight rows, eight dispositions, three new
issues: this is the net-issue-flow gate working, not a shortfall. AC18's literal
count is superseded; its intent (every deferral has a home and a trigger) is met.

**Task 5.1 — the fleet query went to a new sibling runbook.** The task named
`supabase-log-query.md`. Shipped created
`knowledge-base/engineering/operations/runbooks/workflow-cost-query.md` instead,
because the two answer different questions through different mechanisms (platform
logs via the Management API vs. application tables via `psql`), and folding a cost
query into the log-query runbook would have invited exactly the wrong tool. Each
runbook now cross-references the other and says why they are separate. Neither
file appears in this plan's Files-to-Create or Files-to-Edit.

**Sharp Edge H1 — the dispatch floor did not do what this plan predicted.** The
plan claims at §H1 that a `BUCKETS.length >= 8` member-count floor reds an
emptied assertion body. Driven, it did not: 53 tests passed with the body
deleted. A member count and an assertion body are different axes, and the plan
asserted one mechanism covered both. Closed in code with `expect.assertions(n)`
in `test/messages/workflow-copy.test.ts`. Written up in
`knowledge-base/project/learnings/2026-09-08-my-live-verification-could-only-run-where-the-defect-was-invisible.md`.

**On the checkbox state below.** `tasks.md` was archived with most boxes
unticked, including tasks whose output is demonstrably in the tree (the
migration, the loader, the ADR). The tick state was not maintained during
implementation and is not evidence of anything. The authoritative record of what
was verified is `ac-evidence.md` in the archived spec directory, which carries
the measured result for each acceptance criterion.
