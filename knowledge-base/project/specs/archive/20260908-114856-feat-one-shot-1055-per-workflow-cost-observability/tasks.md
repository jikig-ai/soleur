# Tasks — feat: per-workflow LLM cost observability (#1055)

Plan: `knowledge-base/project/plans/2026-09-07-feat-per-workflow-agent-cost-observability-plan.md`
Branch: `feat-one-shot-1055-per-workflow-cost-observability` · Issue: **Ref** #1055 (not `Closes` — see 6.2)
Lane: `cross-domain` — no `spec.md` exists for this branch, so the lane defaulted fail-closed (TR2).

> **Read the plan's `## Sharp Edges` before starting.** Three premises were falsified during
> review, and two of this plan's own acceptance criteria were unsatisfiable as first written.
> The corrections are in the plan; this file assumes them.
>
> **Phase order is load-bearing.** Phase 1 declares the SQL contract; Phase 2 consumes it;
> Phase 3 renders it. Phase 2 also *breaks* four existing test files — they are Phase 2 tasks,
> not cleanup.

---

## Phase 0 — Preconditions (no edits; each has a stated branch)

- [ ] **0.1** Bucket distribution against **dev**, read-only:
      `SELECT COALESCE(active_workflow,'<null-legacy>') AS bucket, count(*), sum(total_cost_usd) FROM conversations WHERE total_cost_usd > 0 GROUP BY 1 ORDER BY 3 DESC;`
  - [ ] **0.1.1** Record the numbers. **Branch:** if `<null-legacy>` + `__unrouted__` hold a
        majority of dev MTD spend, Phase 3's copy leads with that rather than burying it.
  - [ ] **0.1.2** Re-run grouped by `domain_leader`. This settles the CPO-vs-CTO
        primary-cut disagreement recorded in `decision-challenges.md` (UC-2).
- [ ] **0.2** Re-verify write-once attribution: `soleur-go-runner.ts:2162`
      (`state.currentWorkflow === null` guard), `ws-handler.ts:1231-1276`, `ws-handler.ts:1084`
      ("first-writer-wins"), and that `onSwitchWorkflow` is still not passed to
      `<WorkflowLifecycleBar>` from `chat-surface.tsx`.
      **Branch:** if any path overwrites a non-null `active_workflow`, R2 changes shape and
      the Phase 3 copy changes with it.
- [ ] **0.3** Measure the R4 skew: how much in-month spend belongs to conversations *created*
      in a prior month. **Branch:** the size decides how far the Phase 3 footnote can scope the
      Console-reconciliation claim. Do **not** change the window — that changes the headline
      number users already see.

## Phase 1 — Migration (RED first)

- [ ] **1.0** Confirm the ordinal: `ls apps/web-platform/supabase/migrations/ | grep -c '^136_'` → `0`.
      If not, take the next free integer and sweep the plan, this file, and the ADR reference
      in one edit.
- [ ] **1.1** Read 027's live grants — `SELECT proname, proacl FROM pg_proc WHERE proname='sum_user_mtd_cost';`
      — and record the **owner name**. AC5's expected `proacl` literal needs it.
- [ ] **1.2** Write `test/supabase-migrations/136-workflow-cost-rollup.test.ts` **first**
      (file-parse only, mirroring `032-workflow-state.test.ts`):
  - [ ] **1.2.1** The `CASE`'s `THEN '<literal>'` arms are exactly `{'legacy','unrouted'}`, and
        the `ELSE` arm passes `active_workflow` through unmodified. **Do not** assert output
        values — this is a file-parse test (AC15b).
  - [ ] **1.2.2** Exactly one `SELECT` in the function body, using `ROLLUP` (AC3).
  - [ ] **1.2.3** No table DDL; `search_path = public, pg_temp` appears for **both** functions.
  - [ ] **1.2.4** `date_trunc('month', now())` does not appear **in the function body** — scope
        the grep to `sed -n '/^CREATE OR REPLACE FUNCTION public\.sum_user_mtd_cost_by_workflow/,/^\$\$;/p'`,
        because the header comment legitimately contains the forbidden literal.
  - [ ] **1.2.5** The sentinel pin: the migration's `'__unrouted__'` literal equals
        `SENTINEL_UNROUTED`'s value in `server/conversation-routing.ts`, and exactly one such
        literal exists (Guard 1 / AC15).
- [ ] **1.3** Write `136_workflow_cost_rollup.sql` per the plan's Phase 1 block: the
      `sum_user_mtd_cost_by_workflow` function (derived table → `GROUP BY ROLLUP`,
      `ORDER BY GROUPING(b.bucket) DESC, 2 DESC, 1 ASC`), its `COMMENT ON FUNCTION`, the three
      `REVOKE`s + one `GRANT`, and the `sum_user_mtd_cost` `search_path` repin.
- [ ] **1.4** Write `136_workflow_cost_rollup.down.sql` — **drops the new function only.** Do
      **not** "restore" `sum_user_mtd_cost` to its 027 shape; that would re-introduce the
      missing `pg_temp` this migration exists to fix.
- [ ] **1.5** Remove `"sum_user_mtd_cost"` from `LEGACY_SEARCH_PATH_NO_PG_TEMP`
      (`test/migration-rpc-grants.test.ts:76-79`) and its rationale comment (`:70`).
      **Without this the repin in 1.3 is unenforceable** — the gate short-circuits on set
      membership.
- [ ] **1.6** Apply to **dev** and verify (`hr-dev-prd-distinct-supabase-projects`). Capture
      AC1 (Σ buckets = `is_total`, both totals and counts) and AC5 (`proacl`) outputs for the
      PR body. Wrap AC2's cross-function parity in one `BEGIN; … ROLLBACK;`.

## Phase 2 — Loader (RED first)

- [ ] **2.1** `lib/messages/workflow-copy.ts` — the editorial map, closing with
      `as const satisfies Record<WorkflowBucket, WorkflowCopy>`. **`import type` only**:
      `server/conversation-routing.ts` is not on `.dependency-cruiser.cjs`'s `VALUE_SAFE_PATH`
      allowlist (`:68-69`), and `WORKFLOW_NAMES` is not exported. Strings come from the copy
      spec §12, never invented here.
- [ ] **2.2** `test/messages/workflow-copy.test.ts` — content-shape gates mirroring
      `test/messages/action-class-copy.test.ts` (char caps, no raw slugs, no dotted ids).
      Completeness is the `satisfies` rail's job, not a runtime loop.
- [ ] **2.3** `test/server/api-usage-workflow-rollup.test.ts` (RED) — T1-T3, T6-T10 from the
      plan. Note these mock the Supabase client and therefore cannot prove `Σ = total`; they
      prove the loader's behaviour over fixtures.
- [ ] **2.4** `server/api-usage.ts`:
  - [ ] **2.4.1** Add `WorkflowCostRow` and `byWorkflow: WorkflowCostRow[] | null` to
        `ApiUsage`. `null` = failed, `[]` = no buckets — never collapse them.
  - [ ] **2.4.2** Add the new RPC to the parallel batch alongside the existing conversation-list
        SELECT. Use **`Promise.allSettled`**, not `Promise.all` — a *rejecting* promise would
        throw past the existing `.error` handling and turn the intended degradation into
        fail-whole.
  - [ ] **2.4.3** Derive `mtdTotalUsd`/`mtdCount` from the **`is_total` row**.
  - [ ] **2.4.4** Call `sum_user_mtd_cost` **only in the rejection arm, sequentially.** A
        parallel "safety net" reintroduces the two-snapshot race one layer up (this is the
        Phase 4.5 advisor's finding and the single subtlest point in the plan).
  - [ ] **2.4.5** `reportSilentFallback` with `op: "mtd-by-workflow"` — a tag value that exists
        nowhere else. Do not fold it into `op: "loadApiUsageForUser"`.
  - [ ] **2.4.6** Coerce NUMERIC-as-string with `Number(...)` at the boundary. **Never sum in JS.**
  - [ ] **2.4.6a** Sort the returned rows **defensively in TS** before rendering, and compute
        `avgUsd = totalUsd / count` per row. The function emits an `ORDER BY` and
        `SECURITY DEFINER` blocks planner inlining (so the order does hold), but PostgREST
        issues `SELECT * FROM fn(...)` with no outer `ORDER BY` — emission order is a
        convention, not a contract. Sorting ≤ 8 coerced rows and dividing per row accumulate
        nothing, so neither violates 2.4.6.
  - [ ] **2.4.7** Do **not** add `active_workflow` to the list SELECT and do **not** add
        `workflowLabel` to `ApiUsageRow` — cut at review: it buys no listed property and would
        put the raw `__unrouted__` sentinel into TS, breaking the containment invariant.
- [ ] **2.5** Fix the four consumers Phase 2.4 breaks — these are tasks, not cleanup:
  - [ ] **2.5.1** `test/api-usage.test.ts` — `toHaveBeenCalledTimes(1)` at `:189` and `:230`,
        plus eleven `mockReturnValueOnce` seeds, all assume one RPC returning `{total,n}`.
        Update to the `{bucket,total,n,is_total}` shape and the new call pattern.
  - [ ] **2.5.2** `test/api-usage-parity.test.ts` — same `mockRpc` hoist, same fix.
  - [ ] **2.5.3** `test/server/api-usage.tenant-isolation.test.ts` — add a sibling to the
        existing `sum_user_mtd_cost` 42501 case (`:159-163`) for the new function (AC5b).
  - [ ] **2.5.4** `server/api-usage.ts` comments `:4-5` and `:130-131` cite "migration 027:68"
        as the service-role authority; name both functions.
- [ ] **2.6** `.service-role-allowlist` — amend the `api-usage.ts` comment to name both RPCs.
      **No new path** (the file is CODEOWNERS-pinned).

## Phase 3 — UI

- [x] **3.1** Extend the copy spec if any string is still missing; every user-facing string
      comes from `knowledge-base/project/specs/feat-restore-byok-usage-dashboard/copy.md`
      §§11-17. Nothing authored inline in the TSX.
- [x] **3.2** `test/components/settings/api-usage-breakdown.test.tsx` (RED) — the four
      suppression states, the no-raw-slug assertion, the disclosure-always-renders assertion,
      and the rendered-text footnote assertions.
- [x] **3.3** `components/settings/api-usage-section.tsx`:
  - [x] **3.3.1** The breakdown block between the MTD summary and the conversation list, per
        `workflow-cost-breakdown.pen`: proportional bars **scaled to the largest bucket**, not
        the total; rows show label, total, count, and average per conversation.
  - [x] **3.3.2** The four-state suppression matrix. Legacy-only gets its own explanatory line
        (a *different* message from "only one workflow"); every other single-bucket or
        zero-MTD-with-history case renders **nothing**; `null` renders one unavailable line in
        a muted inset — **red stays reserved** for the section-wide failure.
  - [x] **3.3.3** Largest-remainder allocation so displayed parts sum to the displayed whole; a
        non-zero amount below display precision renders `<$0.0001`, never `$0.0000`.
  - [x] **3.3.4** The attribution disclosure, rendering whenever the breakdown renders — not
        behind a tooltip, not conditional on bucket count. Mechanism with a worked
        `plan → work` example; no hedge words.
  - [x] **3.3.5** Scope the cross-check footnote: `match to the cent` stays **byte-unchanged**;
        add the sentence enumerating what the Console can confirm; and fix the existing hedge
        to `under-report`. Assert on rendered output — a source grep for `may under-reflect` is
        vacuous because the JSX splits it across `:142-143`.
  - [x] **3.3.6** The "what is a workflow?" tooltip attaches to the **breakdown block header**,
        not the section header (which already carries three of a different family).

## Phase 4 — Verify

- [ ] **4.1** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (never `npm run -w`).
- [ ] **4.2** `cd apps/web-platform && ./node_modules/.bin/vitest run` (never `bun test`).
- [ ] **4.3** `bash scripts/test-all.sh` — the full battery, where orphan suites outside the
      touched shards surface.
- [ ] **4.4** `bash plugins/soleur/test/c4-count-parity.test.sh` (under `plugins/`, not
      `apps/web-platform/test/`) — record green in the PR body.
- [ ] **4.5** Walk the plan's `## Acceptance Criteria` and record each result. Every `0`-expecting
      grep uses `[ "$(grep -c … || true)" = "0" ]`.

## Phase 5 — Operator surface + deferrals

- [ ] **5.1** Document the fleet-wide query in
      `knowledge-base/engineering/operations/runbooks/supabase-log-query.md` — one SQL block,
      run via `doppler run -c prd -- psql "$DATABASE_URL"`. No SSH.
- [ ] **5.2** File the eight tracking issues from the plan's Phase 5.2 table, each with a
      re-evaluation criterion. Verify every label with `gh label list --limit 200` first.

## Phase 6 — ADR + ship

- [ ] **6.1** Re-verify the ADR ordinal across **every** `origin/*` ref (not just
      `origin/main` — 205 and 206 are claimed on pushed branches), then write
      `ADR-209-conversation-grain-cost-attribution.md` per the plan's §ADR. If the ordinal
      moves, sweep the plan, this file, and AC19 in the same edit.
      **ADR-108 is not amended** — the marker widening was cut.
- [ ] **6.2** PR body uses **`Ref #1055`**, not `Closes`, and states plainly that per-agent
      attribution is not delivered. `/ship` renders `decision-challenges.md` into the body and
      files it as an `action-required` issue.
