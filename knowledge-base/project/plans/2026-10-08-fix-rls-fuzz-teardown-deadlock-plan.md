---
title: "ci: rls-fuzz deadlocks in conversation-engine-binding teardown (40P01, recurring)"
type: fix
date: 2026-10-08
slug: fix-rls-fuzz-teardown-deadlock
branch: feat-one-shot-9779-rls-fuzz-deadlock
issue: 9779
closes: 9779
priority: p2
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# ci: rls-fuzz deadlocks in conversation-engine-binding teardown (40P01, recurring)

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-10-08 (deepen-plan, sequential-fallback — no Task tool in
subagent context; all passes ran inline)
**Sections enhanced:** Observability (5-field schema), Dependencies & Risks
(precedent-diff), Technical Considerations (verbatim doc/type evidence),
Research Insights (second in-repo precedent + gate evaluations)

### Key Improvements

1. Second in-repo precedent found: `server/worktree-write-lease.ts:156-158`
   carries an identical `TRANSIENT_SQLSTATES` + 3-attempt/80–120 ms retry —
   the pattern is established twice, not once.
2. postgres.js transactional semantics now pinned to the version-pinned
   vendored README (`node_modules/postgres/README.md:619-623`), and the
   `TransactionSql ⊄ Sql` structural claim is verified against the pinned
   `types/index.d.ts` (`Sql` adds `begin`/`reserve`; `TransactionSql` does not
   extend it).
3. Observability upgraded from a skip-note to the 5-field schema (the
   deepen-plan 4.7 gate fires for any non-pure-docs Files-to-Edit).
4. All five issue/PR citations verified live via `gh` (#7376/#7432/#9529/#9740/
   #9779 — titles match the roles the plan assigns them).
5. Census-B self-review defect fixed pre-freeze: wrapped call sites still
   match `\w+\(sql`, and a `=>` exclusion would have false-negatived
   `.map(t => t.seed(sql, ctx))` shapes — the AC6 command was corrected.

### New Considerations Discovered

- `catalog.ts` + `Sql|Txn`-helper call sites widened the wrap census (33
  `await sql` sites + 13 bare-`sql` handle-passing sites on the pre-fix tree).
- The network-outage trigger (4.5) fired on the literal `timeout-minutes: 25`
  — evaluated and dismissed: the symptom is a Postgres lock error, not an
  L3/L7 connectivity failure.
- Context7 MCP was denied in background mode; vendored `node_modules` docs
  supplied equivalent (version-pinned, hence stronger) evidence.

## Overview

The RLS/authz-fuzz merge gate (#9779) intermittently red-lights on a Postgres
40P01 deadlock: `conversation-engine-binding.integration.test.ts` issues
`drop trigger conversations_engine_binding_state_insert on public.conversations`
(AccessExclusiveLock) inside a rolled-back transaction while sibling spec-file
workers hold or request locks on the same shared disposable database — a
lock-ordering inversion between parallel vitest workers, not a product defect.
The probe results are already recorded when it fires, so the failure is pure
flake. This plan eliminates the flake class by making the harness's transaction
primitive retry on transient lock SQLSTATEs, scoped and bounded so genuine
failures still fail loudly.

## Research Insights

### Premise Validation (plan Phase 0.6)

- Issue #9779 verified OPEN via `gh issue view` — title matches, label
  `meta/machinery`, no `closedByPullRequestsReferences`. Premise is live.
- Cited path `test/rls-fuzz/conversation-engine-binding.integration.test.ts`
  resolves under the app root: `apps/web-platform/test/rls-fuzz/…`. The issue
  body elides the `apps/web-platform/` prefix; the file exists on
  `origin/main` (verified via `git show`).
- The `drop trigger` sits at `…/conversation-engine-binding.integration.test.ts`
  inside the first `test()` body, wrapped in `rolledBackRaw` — the issue calls
  it "teardown" but it is an in-transaction DDL statement; the fix target is
  unchanged either way.
- ADR-corpus grep (`deadlock|retry|parallel|serializ|worker`) over
  `knowledge-base/engineering/architecture/decisions/` returns no ADR governing
  rls-fuzz worker parallelism or lock retry — no rejected-alternative collision.
  ADR-111 (the harness ADR) prescribes the *substrate* (local Supabase stack,
  canonical migration applier), not intra-run concurrency policy.
- Prior-art verification (per `hr-verify-repo-capability-claim-before-assert`):
  the codebase already carries the retry idiom —
  `apps/web-platform/server/concurrency.ts` holds `TRANSIENT_SQLSTATES =
  {"40P01","55P03"}` + bounded jittered retry (3 attempts, 80–120 ms) around the
  `acquire_conversation_slot` RPC, and `apps/web-platform/lib/postgres-errors.ts`
  exports `sqlStateFromError` (5-char `[0-9A-Z]` SQLSTATE shape guard) that test
  code can import via `@/lib/postgres-errors` or `../../lib/postgres-errors`.

### Property List (plan Phase 0.6b)

- P1: `bun run test:rls-fuzz` does not red-light on a 40P01/55P03 lock wait
  between parallel spec-file workers against the shared disposable Postgres.
- P2: The fix covers the *class* (any fuzz transaction can be elected deadlock
  victim — Postgres picks the victim nondeterministically), not only the
  observed `drop trigger` call site; the issue records "the same failure shape
  … on unrelated heads".
- P3: No fuzz assertion is weakened — every SELECT/denial probe the suite
  performs today still runs (a fix that masks real `42501` denials defeats the
  harness's purpose).
- P4: A persistent (non-transient or repeatedly transient) failure still fails
  the test loudly — bounded attempts, then propagate.

### Mechanism assessment (0.6b) — issue-proposed options vs. repo reality

| Issue option | Property | Verdict |
|---|---|---|
| "serialize the trigger drop (retry on 40P01)" | P1+P2 | Adopt — generalized: retry lives at the `rolledBackRaw` chokepoint so the *victim* (whichever side Postgres kills) retries, not just the DDL issuer. Reuses the `TRANSIENT_SQLSTATES` shape already proven in `server/concurrency.ts`. |
| "take the lock earlier" (`LOCK TABLE … ACCESS EXCLUSIVE` first) | P1, this site only | Rejected for scope — protects one call site, leaves sibling-victim cycles and the `alter table … disable rls` site (`rls-authz-fuzz` AC5) open, and implicit catalog locks (pg_trigger/pg_proc) still escape a named table lock. |
| "run that spec single-worker" | P1 fully | Retained as documented fallback only — serializes all 7 DB-touching specs for a two-statement window; the repo's own `JOBS:1` history (#7376 → removal tracker #7432) treats forced serialization as a stopgap to retire, not a fix. |

### Cut List (0.6b)

- `pg_advisory_xact_lock` mutex between DDL call sites → property P1 → CUT.
  The deadlock cycle's second party is a plain `SELECT`/`INSERT` transaction
  that never takes the advisory lock, so cooperating-writer serialization
  cannot break the cycle. (The 2026-09-21 fixture-contention plan adopted the
  advisory mutex for a different problem — serializing *writer* CI jobs against
  a shared dev project — and itself records the cooperativeness caveat.)
- Vitest `retry: N` test-level config → property P1 → CUT. Retries on *any*
  assertion failure (indiscriminate — collides with the constitution rule that
  retry-on-flake must not swallow first-attempt assertion failures), and a
  failing `beforeAll` seed is not retried by per-test retry at all.
- Per-file separate Postgres schemas/databases → P1 → CUT. New substrate for a
  disposable-stack flake; violates mechanism minimality.

### Relevant files

- `apps/web-platform/test/rls-fuzz/harness-fixture.ts` — `connect` (`max: 1`
  pinned, `assertLocalDsn`), `rolledBackRaw` (THE transaction chokepoint —
  `attackAs`/`attackAsAnon`/`asTenant` all layer on it), `seedTwoTenant`,
  `seedRpcCtx`, `seedEmailTriageItem`, `assertTwoTenant`.
- `apps/web-platform/test/rls-fuzz/catalog.ts` — 8 exported live-catalog query
  functions on the raw `Sql` handle (5 bare `await sql` sites), called from
  spec-file `beforeAll`s and mid-test AC checks.
- `apps/web-platform/test/rls-fuzz/conversation-engine-binding.integration.test.ts:35`
  — the `drop trigger` (AccessExclusiveLock on `public.conversations`).
- `apps/web-platform/test/rls-fuzz/rls-authz-fuzz.integration.test.ts:198` —
  second DDL site: `alter table "workspace_activity" disable row level security`
  (already lock-first-shaped; still a deadlock-victim candidate).
- `apps/web-platform/test/rls-fuzz/rls-authz-fuzz.integration.test.ts:184` —
  bare `insert into denied_jti` outside any txn helper.
- `apps/web-platform/test/rls-fuzz/rls-excluded-deepened.integration.test.ts`
  `beforeAll` — ~6 bare `await sql` seed statements.
- `apps/web-platform/test/rls-fuzz/rls-storage.integration.test.ts` `beforeAll`
  — 4 bare `await sql` seed statements.
- `apps/web-platform/lib/postgres-errors.ts` — `sqlStateFromError` (reuse).
- `apps/web-platform/server/concurrency.ts` — `TRANSIENT_SQLSTATES` +
  jittered-retry precedent (lines ~83–120).
- `apps/web-platform/test/rls-fuzz/local-dsn-guard.test.ts` — unit-test
  convention in this directory (pure vitest, no DB).
- `.github/workflows/rls-authz-fuzz.yml` — the merge gate; single
  `bun run test:rls-fuzz` invocation, `timeout-minutes: 25`, parallelism
  unspecified → vitest default workers (one fork per spec file), all on the ONE
  local stack at `127.0.0.1:54322`.

### Institutional learnings applied

- `2026-07-11-rls-migration-verify-savepoint-and-signature-scope.md` — a raise
  aborts the enclosing txn (`25P02`); re-running a rolled-back txn wholesale is
  safe and the `ROLLBACK` sentinel contract must survive the retry wrapper.
- `2026-09-21-fix-tenant-integration-shared-fixture-contention-plan.md` —
  advisory-lock precedent + its pooler caveat; not applicable here (direct
  `postgres.js` `max: 1` connection, non-cooperating readers).
- Constitution (Testing/Always): retry-on-flake must not swallow first-attempt
  assertion failures — the retry predicate is SQLSTATE-scoped (`40P01`,
  `55P03`), so assertion failures propagate on first raise.

### Research decision (Phase 1.6)

External research skipped — strong local context: the codebase already
implements the exact remedy pattern (`server/concurrency.ts`), the harness is
ADR-111-documented, and the defect is a well-understood Postgres lock-ordering
inversion. Community-discovery stack check: no uncovered stacks (TypeScript/
Postgres/vitest all covered). Functional-overlap check: repo-internal harness
fix; no community artifact replaces it — skipped in subagent context.

### Fan-out disclosure

`soleur:engineering:research:repo-research-analyst` and
`soleur:engineering:research:learnings-researcher` could not be spawned (this
plan ran inside a subagent without a Task tool); the equivalent codebase
search, learnings sweep, ADR corpus grep, and prior-art verification were
executed inline above.

**Reviewed-Coverage: sequential-fallback** — the `/plan_review` panel
(DHH/Kieran/Simplicity + relevance-gated named panel) and the Phase 4.5
scoped advisor could not be spawned in this subagent context; an inline lens
pass ran instead and produced two material changes: the bare-`sql` census was
widened beyond `await sql` to include `Sql|Txn`-parameterized helper call
sites (`catalog.ts`, `t.seed`/`h.seed`, `countRows`/`countById`/`countObject`),
and census-B's exclusion filter was corrected (a `withTransientRetry`-wrapped
call still matches `\w+\(sql` — and a `=>`-filter stage would have
false-negatived `.map(t => t.seed(sql, ctx))` shapes).

## Problem Statement / Motivation

`bun run test:rls-fuzz` (`.github/workflows/rls-authz-fuzz.yml`, a merge gate on
migration/RLS-harness diffs) runs its spec files in parallel vitest workers —
each worker its own `postgres.js` connection (`connect()` pins `max: 1`) —
against ONE disposable local Postgres (`127.0.0.1:54322`). Two spec files take
DDL-class locks inside rolled-back transactions:

- `conversation-engine-binding.integration.test.ts` — `drop trigger
  conversations_engine_binding_state_insert on public.conversations`
  (AccessExclusiveLock on `conversations`, taken *after* an earlier SELECT in
  the same txn already holds AccessShareLock — the classic lock-upgrade shape),
- `rls-authz-fuzz.integration.test.ts` AC5 — `alter table "workspace_activity"
  disable row level security` (AccessExclusiveLock).

Against those, every other spec file's `SELECT`/`INSERT` txns hold
AccessShare/RowExclusive locks. The issue's two captured deadlocks are the
symmetric cycle: one process waits AccessExclusive on a relation the other
reads, while the other waits on a relation the first already holds.
**Postgres elects the deadlock victim nondeterministically** — either party can
be killed — so a fix confined to the DDL call site only repairs half the
failure shape.

Observed twice on 2026-10-08 within hours on unrelated diffs (#9529 runs
`ef7319c820`, `42c42657cb`) — a recurring merge-gate flake that re-runs
silently absorb, costing a full `rls-fuzz` job cycle each time.

## Proposed Solution

One exported helper in `harness-fixture.ts`, applied at every database call
that can be elected deadlock victim:

```ts
// harness-fixture.ts
import { sqlStateFromError } from "../../lib/postgres-errors";

/** Transient Postgres SQLSTATES that warrant a bounded retry of the whole
 *  unit of work: 40P01 deadlock_detected, 55P03 lock_not_available.
 *  Mirrors apps/web-platform/server/concurrency.ts's TRANSIENT_SQLSTATES. */
const TRANSIENT_SQLSTATES = new Set(["40P01", "55P03"]);
const TRANSIENT_MAX_ATTEMPTS = 3;

export async function withTransientRetry<T>(
  fn: () => Promise<T>,
  opts?: { sleep?: (ms: number) => Promise<void> }, // injectable for unit tests
): Promise<T> {
  const sleep =
    opts?.sleep ?? ((ms: number) => new Promise<void>((r) => setTimeout(r, ms)));
  for (let attempt = 1; ; attempt++) {
    try {
      return await fn();
    } catch (e) {
      const code = sqlStateFromError(e);
      if (code === undefined || !TRANSIENT_SQLSTATES.has(code) || attempt >= TRANSIENT_MAX_ATTEMPTS) {
        throw e;
      }
      await sleep(80 + Math.random() * 40); // 80–120 ms jitter, same as concurrency.ts
    }
  }
}
```

Application rules:

1. **`rolledBackRaw` wraps its whole `sql.begin`** in `withTransientRetry`.
   Retrying a rolled-back txn is always safe: a 40P01 aborts and discards the
   txn, so the retry replays `fn` on a clean transaction. The `ROLLBACK`
   sentinel is consumed inside the wrapped closure, so the wrapper only ever
   sees real errors. Because `attackAs`/`attackAsAnon`/`asTenant` all layer on
   `rolledBackRaw`, this one edit covers every fuzz txn — including whichever
   side Postgres elects as victim.
2. **`Sql`-only helpers self-wrap.** `seedTwoTenant`/`seedRpcCtx` run their
   bodies inside ONE committed `sql.begin` under `withTransientRetry` (extract
   `seedTwoTenantTx(t)`/`seedRpcCtxTx(t)` internals; `assertTwoTenant` rides
   the same txn). Atomicity makes whole-txn replay safe — a mid-seed deadlock
   rolls back everything, so retry restarts clean — and multi-statement seeds
   stop leaving half-provisioned fixtures on abort. `catalog.ts` functions all
   take the raw `Sql` handle, so each wraps its query internally.
3. **`Sql|Txn` helpers are wrapped at the bare-`sql` call site** — they cannot
   self-wrap (rule 4 forbids wrapping a `t` handle). The call-site set is
   exactly the 13 hits the census-B command in AC6 returns today:
   `t.seed(sql, ctx)` / `h.seed(sql, ctx)` registry seeds in the
   rls-authz-fuzz / rls-row-hijack / rls-user-isolation `beforeAll`s,
   `countRows(sql,…)` in rls-authz-fuzz and rls-user-isolation,
   `countById(sql,…)` and `seedEmailTriageItem(sql,…)` in
   rls-excluded-deepened, `countObject(sql)` in rls-storage, and
   `seedEmailTriageItem(sql,…)` inside `seedRpcCtx` (which moves onto the `t`
   handle when rule 2 lands, so the call itself stays unwrapped). Bare
   multi-statement seed clusters in spec-file `beforeAll`s
   (rls-excluded-deepened, rls-storage) take the committed-`sql.begin` form;
   lone bare statements (the `denied_jti` insert, the AC10
   information_schema loop) take the single-expression wrap.
4. **Never wrap a transaction-scoped handle `t`** — an aborted txn cannot be
   retried from inside itself (a second statement on the dead txn raises
   `25P02`, which is *not* transient and would mask the original `40P01` from
   the outer retry). Retry lives at the `sql`-handle level only.

No workflow, vitest-config, or package.json changes; parallelism is retained.

## Technical Considerations

- **Victim nondeterminism drives the chokepoint choice.** If only the
  `drop trigger` txn retried, a run where Postgres kills the *reader* txn
  still flakes. `rolledBackRaw` is the single chokepoint every fuzz txn flows
  through, which is also why this fix covers the AC5 `alter table` site and any
  future rolled-back DDL with no further edits.
- **`postgres.js` error shape.** `PostgresError.code` carries the SQLSTATE;
  `sqlStateFromError` (`lib/postgres-errors.ts`) shape-guards it
  (`/^[0-9A-Z]{5}$/`), so a Node `ENOENT`-class code can never be mistagged as
  transient.
- **Assertion failures are never retried.** `expect()` failures throw
  non-SQLSTATE errors → `sqlStateFromError` returns `undefined` → propagate on
  first raise (constitution: retry-on-flake must not swallow first-attempt
  assertion failures).
- **Exhaustion stays loud.** After 3 transient failures the last error
  propagates and the test fails — a persistent structural deadlock is a real
  signal, not something to absorb.
- **NFR note:** bounded jitter adds ≤ ~240 ms worst-case per deadlock event;
  no steady-state cost. `timeout-minutes: 25` unchanged.
- **Constitution (worktrees):** verification commands for this change run
  vitest via `./node_modules/.bin/vitest run`, never `npx vitest run`.
- **`sql.begin` semantics, verbatim from the version-pinned vendored README**
  (`apps/web-platform/node_modules/postgres/README.md:619-623`):
  > "Use `sql.begin` to start a new transaction. … `sql.begin` will resolve
  > with the returned value from the callback function. `BEGIN` is
  > automatically sent with the optional options, and if anything fails
  > `ROLLBACK` will be called so the connection can be released and execution
  > can continue."

  Resolve→commit, throw→rollback — exactly the semantics the
  committed-seed-txn restructure (rule 2) and the sentinel rollback in
  `rolledBackRaw` rely on.
- **`TransactionSql` is not assignable to `Sql`** (verified against the pinned
  `node_modules/postgres/types/index.d.ts`): `interface Sql extends ISql` adds
  `begin`, `reserve`, `end`, `listen`, `subscribe`, `options`, `parameters`,
  `CLOSE`, `PostgresError`; `interface TransactionSql extends ISql` adds only
  `savepoint`/`prepare`. A `t` handle therefore fails type-check at every
  `Sql`-typed parameter — the catalog functions' signatures make the
  "never wrap `t`" rule structural, not conventional.
- **PostgreSQL's own guidance is the authority for whole-transaction retry**
  (docs §13.5, current): "It is important to retry the complete transaction,
  including all logic that decides which SQL to issue and/or which values to
  use." — i.e. the `sql.begin` boundary, not a statement inside the aborted
  txn, is the canonical retry unit. Jitter is likewise documented practice
  (tight-loop retry can recreate the same cycle).

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Reality | Plan response |
|---|---|---|
| "teardown deadlocks on `drop trigger`" | The statement runs inside the first `test()` body under `rolledBackRaw`, after probe seeds but before assertions finish | Fix targets the txn primitive, which covers teardown-adjacent and in-body paths identically |
| "`test/rls-fuzz/conversation-engine-binding.integration.test.ts`" | Path lives at `apps/web-platform/test/rls-fuzz/…` | Corrected path used throughout |

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — worst
  case is the `RLS authz fuzz` merge gate red-lighting again on the same flake
  class, or (if the retry predicate were wrong) a genuine RLS-denial failure
  being masked into a false green that lets a real isolation break merge. The
  predicate is SQLSTATE-scoped precisely to prevent the masking arm.
- **If this leaks, the user's [data / workflow / money] is exposed via:**
  no exposure vector — the change touches test-only machinery against a
  disposable local stack (`assertLocalDsn` fail-closed); no production surface,
  credential, or data path changes.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** internal CI harness reliability —
  no user-facing artifact ships in this diff; the blast radius is a flaky or
  (worst case) falsely-green merge gate, both confined to this repo's CI.

## Observability

Test-only change; the affected "surface" is the CI check itself, so the block
below declares its observability in those terms (deepen-plan 4.7 requires the
schema for any non-pure-docs Files-to-Edit):

- **liveness_signal:**
  what: the `RLS authz fuzz` PR check reporting green on a diff that touches
        `apps/web-platform/test/rls-fuzz/**` — the workflow is paths-gated, so
        this PR's own diff arms the probe
  where: GitHub Actions `.github/workflows/rls-authz-fuzz.yml` (PR check)
  probe: `discoverability_test`
- **error_reporting:**
  channel: red CI check with the failing vitest spec + SQLSTATE in the run
           log — vitest's reporter is the existing mechanism; no Sentry
           (test-only code)
  aggregation: none (per-run)
- **failure_modes:**
  - `40P01`/`55P03` persists past 3 attempts → red check carrying the SQLSTATE
    in vitest output (signal preserved, slower red)
  - non-transient SQLSTATE (e.g. `42501` outside an expected-denial arm) →
    propagates on attempt 1, no retry
  - RLS assertion failure → propagates on attempt 1, unchanged signal — the
    `sqlStateFromError` shape guard (`/^[0-9A-Z]{5}$/`) is what keeps Node
    `ENOENT`-class codes and assertion errors out of the transient set
- **logs:**
  emit: none new — failures surface through vitest's existing test output
- **discoverability_test:**
  command: rg -l TRANSIENT_SQLSTATES apps/web-platform
  expected_output: harness-fixture.ts and verdict.ts (the set lives in verdict.ts › TRANSIENT_SQLSTATES alongside rethrowIfTransient; server/concurrency.ts and server/worktree-write-lease.ts are the pre-existing mirrored copies)

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` (88 issues) contains no
body reference to `test/rls-fuzz`, `harness-fixture.ts`, or any edited file.

## Files to Edit

- `apps/web-platform/test/rls-fuzz/harness-fixture.ts` — add
  `sqlStateFromError` import, `TRANSIENT_SQLSTATES`, `TRANSIENT_MAX_ATTEMPTS`,
  exported `withTransientRetry`; wrap `rolledBackRaw`'s `sql.begin`; restructure
  `seedTwoTenant`/`seedRpcCtx` as `withTransientRetry(() => sql.begin(t =>
  seed…Tx(t)))` over extracted txn-scoped internals (committed txn — atomic
  seeds; `assertTwoTenant` runs inside it).
- `apps/web-platform/test/rls-fuzz/catalog.ts` — each exported catalog function
  wraps its `await sql` query in `withTransientRetry` (signatures take `Sql`
  only, so the no-`t`-handle rule is structural).
- `apps/web-platform/test/rls-fuzz/rls-authz-fuzz.integration.test.ts` — wrap
  the `t.seed(sql, ctx)` loop (line ~45), `countRows(sql,…)` sites (~88, ~152),
  the `denied_jti` insert (~184), and the AC10 `information_schema` query
  (~228).
- `apps/web-platform/test/rls-fuzz/rls-excluded-deepened.integration.test.ts` —
  `seedEmailTriageItem(sql, ctx)` (~33) and `countById(sql,…)` (~68, ~73) take
  single-expression wraps; the ~6-statement `beforeAll` seed cluster takes the
  committed-`sql.begin` + retry form.
- `apps/web-platform/test/rls-fuzz/rls-row-hijack.integration.test.ts` — wrap
  `h.seed(sql, ctx)` (~102).
- `apps/web-platform/test/rls-fuzz/rls-storage.integration.test.ts` — the 4
  `beforeAll` seed statements take the committed-`sql.begin` + retry form;
  `countObject(sql)` (~46, ~83) takes single-expression wraps.
- `apps/web-platform/test/rls-fuzz/rls-user-isolation.integration.test.ts` —
  wrap `t.seed(sql, ctx)` (~38) and `countRows(sql,…)` (~71, ~120).

Wrap convention (what AC6's census asserts): a wrapped call keeps `sql` on the
SAME line as `withTransientRetry` — the single-expression arrow form:

```ts
await withTransientRetry(() => sql`insert into denied_jti … `);
const rows = await withTransientRetry(() => sql<{ n: number }[]>`select … `);
await withTransientRetry(() => countRows(sql, table, loc));
```

Multi-statement seed clusters use the committed-txn form instead:

```ts
await withTransientRetry(() =>
  sql.begin(async (t) => {
    const [row] = await t`insert into … `; // statements ride `t`, never `sql`
    …
  }),
);
```

Inside the `sql.begin` callback every statement uses the `t` handle, so no bare
`await sql` line ever appears — and a bare `await sql` nested inside a
`withTransientRetry(async …)` block (which WOULD read as unwrapped to the
census while sitting on the wrong handle) is forbidden by rule 4 anyway.

## Files to Create

- `apps/web-platform/test/rls-fuzz/harness-fixture.test.ts` — pure vitest unit
  test of `withTransientRetry`/`rolledBackRaw` retry behavior against a stubbed
  `sql` object (`{ begin: vi.fn() }`), matching `local-dsn-guard.test.ts`
  conventions (no DB, runs in the `unit` project — the filename matches the
  `test/**/*.test.ts` include glob in `vitest.config.ts`).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "`test/rls-fuzz/conversation-engine-binding.integration.test.ts` teardown deadlocks on `drop trigger conversations_engine_binding_state_insert on public.conversations`" [issue #9779] | FR-1 / `harness-fixture.ts` edit / Files-to-Edit | mapped |
| 2 | "serialize the trigger drop (retry on 40P01)" [issue #9779] | FR-1 — `withTransientRetry` on `{40P01, 55P03}` at `rolledBackRaw` + bare-statement wraps | mapped |
| 3 | "take the lock earlier" [issue #9779] | — | descoped — justification: covers one call site only; cannot break cycles where Postgres elects the reader txn as victim; superseded by FR-1 which covers the class |
| 4 | "run that spec single-worker" [issue #9779] | — | descoped — justification: serializes all 7 DB-touching specs for a two-statement window; retained as documented fallback in Alternatives; repo precedent (#7376/#7432) treats forced serialization as a stopgap to retire |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `withTransientRetry` + `rolledBackRaw` wrap (FR-1) | "serialize the trigger drop (retry on 40P01)" | asked |
| Seed/catalog/bare-statement coverage: `seedTwoTenant`/`seedRpcCtx` committed-txn restructure, `catalog.ts` self-wraps, and the six spec files' bare `await sql` + bare-`sql`-handle call sites (FR-2) | — | inferred — justification: Postgres elects the deadlock victim nondeterministically; a bare seed/catalog/precondition statement is a legal victim, so leaving them unwrapped re-opens the same flake class under a different signature |
| `harness-fixture.test.ts` unit test (FR-3) | — | inferred — justification: constitution "new modules and source files must have corresponding test files" + `cq-write-failing-tests-before`; the retry predicate must be proven to pass non-transient errors through |
| 55P03 in the transient set | — | inferred — justification: identical lock-wait failure class (`lock_not_available` is the lock_timeout/deadlock-adjacent sibling); matches the repo's own `TRANSIENT_SQLSTATES` in `server/concurrency.ts` |

### Split Assessment

- Subsystems touched: 1 — `apps/web-platform` (test-only)
- Planned files: 8 | Estimated changed lines: ~260
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [x] AC1 — `withTransientRetry` re-invokes `fn` on a thrown error whose
  SQLSTATE ∈ {`40P01`, `55P03`}, up to 3 total attempts; a stubbed `begin`
  rejecting `{code:"40P01"}` once then succeeding makes `rolledBackRaw` resolve
  with `fn`'s value.
- [x] AC2 — Non-transient errors propagate without retry: `{code:"42501"}` (and
  any non-SQLSTATE error) throws on the first attempt and the call count stays
  1 — assertion failures are never replayed.
- [x] AC3 — Bounded exhaustion: a `begin` that always rejects `40P01` propagates
  the error after exactly 3 attempts (spy-call count = 3).
- [x] AC4 — The `ROLLBACK` sentinel contract is unchanged: a `fn` that completes
  normally still returns its value and the sentinel never escapes or triggers a
  retry.
- [x] AC5 — Retry cadence is jittered, not hot: an injected `sleep` spy observes
  delays in [80, 120) ms per attempt.
- [x] AC6 — Census, two greps (both verified at plan time):

  ```bash
  # A — bare `await sql` statements: 33 sites on the pre-fix tree, 0 post-fix
  git grep -nE 'await sql\b' -- apps/web-platform/test/rls-fuzz \
    | grep -vE 'withTransientRetry|await sql\.(begin|end|savepoint)\b' \
    | grep -v 'harness-fixture\.test\.ts'
  # expected: no output

  # B — bare `sql` handle passed to a helper: 13 sites pre-fix, 0 post-fix.
  # The allowlist is the closed set of helpers that self-wrap (catalog fns,
  # seeds) or route into rolledBackRaw (attackAs/asTenant/attackAsAnon);
  # `withTransientRetry` lines are dropped first so a wrapped call site
  # (e.g. `withTransientRetry(() => seedEmailTriageItem(sql, ctx))`, where the
  # inner name still matches the `\w+\(sql` shape) is never a false positive.
  git grep -nE '\w+\(sql[),]' -- apps/web-platform/test/rls-fuzz \
    | grep -v 'withTransientRetry' \
    | grep -vE '(asTenant|attackAs|attackAsAnon|rolledBackRaw|seedTwoTenant|seedRpcCtx|assertTwoTenant|connect|assertLocalDsn|isolationSet|workspaceTenancyTables|userIsolationTables|rowHijackTables|jtiDenySet|securityDefinerAuthenticatedFns|allSecurityDefinerFns|securityDefinerAnonFns)\(sql'
  # expected: no output
  ```

  `connect()`/`sql.end()` lifecycle calls are exempt by construction (not
  retry-relevant); `sql.begin` lines inside `rolledBackRaw`/seed txns are
  covered by the enclosing `withTransientRetry` and exempted via the
  `sql\.(begin|…)` filter. The allowlist in census B is the contract: adding a
  new `Sql|Txn`-typed helper requires either wrapping its bare-`sql` call sites
  or a deliberate allowlist addition in review.
- [x] AC7 — `cd apps/web-platform && ./node_modules/.bin/vitest run test/rls-fuzz/harness-fixture.test.ts`
  passes in the unit project (no DB needed — `RLS_FUZZ_LOCAL` unset).
- [ ] AC8 — The PR's own `RLS authz fuzz` check runs green AND the run log
  shows the suite actually executed (the workflow's `paths:` filter includes
  `apps/web-platform/test/rls-fuzz/**`, so the PR exercises the fixed gate
  end-to-end on the real parallel suite — not a skipped/dark check).
- [x] AC9 — `git diff --name-only origin/main...HEAD` touches only paths under
  `apps/web-platform/test/rls-fuzz/` plus the plan/specs artifacts — no diff
  under `apps/web-platform/server/`, `apps/web-platform/supabase/`,
  `.github/workflows/`, or `apps/web-platform/package.json`. (Merge-base form
  `origin/main...HEAD`, not the moving tip.)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — test-machinery change. All eight
Assessment Questions return negative (no user-facing surface, no vendor/infra
procurement, no legal doc, no regulated-data path per the canonical GDPR
regex). The mechanical UI-surface override does not fire: every Files-to-Edit
entry is `test/**/*.ts` — none match `components/**`, `app/**/page.tsx`, or
`app/**/layout.tsx`, so the Product/UX gate is `NONE` by file shape, not just
by subjective sweep. Agent fan-out unavailable in this subagent context; the
sweep was applied inline.

## Test Scenarios

- Given a `rolledBackRaw` txn whose first `sql.begin` attempt dies to `40P01`,
  when the helper retries, then `fn` replays on a fresh transaction and the
  caller sees `fn`'s return value.
- Given a `rolledBackRaw` txn raising `42501` (the fuzz suite's expected-denial
  code), when the error reaches the retry wrapper, then it propagates
  immediately — `begin` is called exactly once and `.rejects.toMatchObject`
  denial assertions keep working.
- Given a `begin` that raises `40P01` on every attempt, when the attempt cap is
  reached, then the third `40P01` propagates and the test reds — no silent
  absorption.
- Given a multi-statement `beforeAll` seed cluster where statement N dies to
  `55P03` inside its committed `sql.begin`, when `withTransientRetry` replays
  the whole txn, then statements 1..N-1 ARE re-executed — safely, because the
  abort rolled back their writes, so no half-provisioned fixture persists and
  no PK-violation can result. Single bare statements outside a txn take the
  single-expression wrap (statement-atomic by construction).
- Given a txn aborted mid-flight, when a caller mistakenly wraps a `t`-handle
  call, then `25P02` is not in `TRANSIENT_SQLSTATES` and propagates — documented
  in the helper's docstring (never wrap a transaction-scoped handle).
- Regression: the #9779 shape — parallel `RLS_FUZZ_LOCAL=1 vitest run
  test/rls-fuzz` with one worker inside the `drop trigger` txn and siblings
  SELECTing `conversations` — completes without an unhandled `40P01` (observed
  via the PR's own gate run, AC8).

## Alternative Approaches Considered

| Option | Why not |
|---|---|
| `LOCK TABLE public.conversations IN ACCESS EXCLUSIVE MODE` as the txn's first statement (issue option 2) | Site-local: does not cover the reader-as-victim half of the cycle, the AC5 `alter table` site, or future rolled-back DDL; implicit catalog locks (pg_trigger) escape a named table lock. The retry covers all of these at one chokepoint. |
| Whole-suite single worker (`--maxWorkers=1` / `fileParallelism: false`) | Eliminates the class but serializes 7 DB specs for a two-statement window; the repo treats forced serialization (`JOBS:1`, #7376) as a stopgap with an open removal tracker (#7432), not a fix. Retained as fallback if a soak shows residual 40P01s. |
| `pg_advisory_xact_lock` between DDL sites | Only serializes cooperating writers; the deadlock's second party is a non-cooperating reader txn (2026-09-21 fixture-contention plan's own caveat). |
| Vitest `retry: N` | Retries assertion failures too (masking risk vs. the constitution's retry-on-flake rule) and does not cover `beforeAll` seed failures. |
| Per-file isolated Postgres schema | New substrate for a disposable-stack flake — mechanism minimality. |

## Success Metrics

- `RLS authz fuzz` check runs green on this PR and stops producing `40P01`
  failures on unrelated PRs (the issue's recurrence signal disappears).
- Zero fuzz-assertion regressions: identical test count, identical verdict
  semantics; the new unit file adds coverage, not changes it.

## Dependencies & Risks

- **Residual:** an N-way pathological deadlock could exhaust 3 attempts; the
  suite then fails loudly with the real error — accepted (surfaces a structural
  problem rather than hiding it). If recurrence is observed post-merge, the
  documented fallback is single-worker for the suite.
- **Risk — retry masking:** mitigated by SQLSTATE-scoped predicate + AC2/AC3;
  worst case is a slower red, never a false green.
- **Risk — double-wrap drift:** a future contributor wrapping a `t`-handle call
  would mask `40P01` as `25P02`; the helper docstring + a code comment at
  `rolledBackRaw` pin the rule (retry wraps `sql`-handle calls only).
- **Dependency:** none — no new packages; reuses `lib/postgres-errors.ts`.

### Precedent diff (deepen-plan 4.4)

The plan's pattern — `TRANSIENT_SQLSTATES` + bounded jittered retry — has TWO
in-repo precedents, both in `apps/web-platform/server/`:

| Element | `concurrency.ts` `acquireSlot` (:83-143) | `worktree-write-lease.ts` `acquireWorktreeLease` (:156-184+) | `withTransientRetry` (this plan) |
|---|---|---|---|
| Transient set | `{40P01, 55P03}` | `{40P01, 55P03}` (comment: "Mirror concurrency.ts") | identical |
| SQLSTATE extraction | `(err as {code?}).code` inline | same inline | `sqlStateFromError` — adds `/^[0-9A-Z]{5}$/` shape guard |
| Attempts | 3 (`attempt < 3`, delay only `attempt < 2`) | 3 | 3, delay between attempts only |
| Jitter | `80 + Math.random() * 40` ms | same | identical |
| Terminal behavior | fail-closed `status:"error"` + `reportSilentFallback` (server semantics: never throw) | fail-closed `null` + Sentry | **rethrow** — test semantics: exhausted transient = red check |
| Retried unit | one RPC call | one RPC call | the whole `sql.begin` / bare statement |

Deviations from precedent, both deliberate: (a) the SQLSTATE extractor is the
tighter shared helper (the precedents predate `sqlStateFromError`'s guard;
adopting it here is consistent with `lib/` being the canonical parser);
(b) exhaustion rethrows rather than fail-closes — in test code a swallowed
error is a false green, the opposite of the server-side "lease lost" sentinel.
Note the precedents' own drift wrinkle: `worktree-write-lease.ts:157`'s
comment says "Mirror concurrency.ts:62" but the set lives at :85 today —
comment-coupled cross-references drift; this plan pins by symbol name in
prose, not line numbers in code comments.

No precedent for the *shape* `withTransientRetry(fn, {sleep})` itself (the
in-repo copies are per-call-site loops); the helper is a lift of the shared
shape, and the `sleep` seam is what makes the jitter testable in the `unit`
project without a fake timer.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold
  fails `deepen-plan` Phase 4.6 — this plan's section is filled above
  (`none`, with rationale).
- `withTransientRetry` MUST NOT be applied around transaction-scoped `t`
  handles — see Technical Considerations; an aborted txn re-raises `25P02`,
  which is deliberately absent from `TRANSIENT_SQLSTATES` so the real `40P01`
  reaches the outer wrapper.
- The AC6 census grep is the drift sentinel: any future bare `await sql` in
  `test/rls-fuzz/**` is a new unretried deadlock victim — the work phase should
  note it in the file's header comment.

## References & Research

- Issue: #9779 (open, `meta/machinery`) — verified live
- Precedents: `apps/web-platform/server/concurrency.ts` `acquireSlot` and
  `apps/web-platform/server/worktree-write-lease.ts` `acquireWorktreeLease`
  (identical `TRANSIENT_SQLSTATES` + 3-attempt/80–120 ms jitter — diffed
  side-by-side in Dependencies & Risks); `apps/web-platform/lib/postgres-errors.ts`
  (`sqlStateFromError`)
- External authority: PostgreSQL docs §13.5 (Serialization Failure Handling) —
  "retry the complete transaction"; postgres.js vendored
  `node_modules/postgres/README.md` §Transactions (:619-623)
- ADR-111 (rls-fuzz harness substrate); ADR-153 (loopback-bound local stack)
- Prior plan: `2026-09-21-fix-tenant-integration-shared-fixture-contention-plan.md`
  (advisory-lock precedent + pooler caveat)
- Learning: `2026-07-11-rls-migration-verify-savepoint-and-signature-scope.md`
  (txn-abort `25P02` semantics)
- Related, all verified live via `gh`: #7376/#7432 (`JOBS:1`
  serialization-as-stopgap precedent — #7432 is the open removal tracker),
  #9529 (one of the observed-failure diff heads), #9740 (separate rls-fuzz
  flake — psql install timeout, untouched by this fix)
- Deepen-pass notes: Context7 MCP denied in background mode (vendored docs
  used instead); the learning
  `learnings/best-practices/2026-07-05-cross-pipeline-serialization-via-shared-job-level-concurrency-group.md`
  was evaluated for the serialization alternative — it serializes across
  workflow RUNS, not within one run's parallel vitest workers, so it does not
  apply here; `learnings/best-practices/2026-07-12-config-gate-half-fix-and-unmasked-deterministic-deadlock.md`
  is systemd-scoped (`ReadWritePaths`), not Postgres — not-applicable.
