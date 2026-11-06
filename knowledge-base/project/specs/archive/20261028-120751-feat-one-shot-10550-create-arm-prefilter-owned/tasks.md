# Tasks: create-arm ledger pre-filter (Ref #10550)

Plan: `knowledge-base/project/plans/2026-10-28-fix-create-arm-prefilter-ledger-owned-patterns-plan.md`

## Phase 0: Failing-first tests (RED)

- 0.1 Write T1 in `apps/web-platform/test/server/compound-promote-create-arm.test.ts` (ledger owns one of two patterns: prompt omits the owned slug, the other pattern reaches create). Run it against the unchanged source and record the first failure line.
- 0.2 Write H2 and H3 in `apps/web-platform/test/server/inngest/cron-compound-promote-create-handler.test.ts`. Confirm both fail on the unchanged source.

## Phase 1: Code (GREEN)

- 1.1 In `proposeInner` (`apps/web-platform/server/compound-promote-create-arm.ts`) hoist `runNow`, filter same-run hashes first (empty returns `other`), then filter `decideSuppression` hits (empty returns `all-owned`); both before `existsSync`.
- 1.2 Delete the later duplicate `runNow`; update the `sameRunHashes` doc comment and the comment above the filter.
- 1.3 Leave `checkCreate`, `isHashSuppressed`, the handler, the marker and `CREATE_STAGE_ORDER` untouched.

## Phase 2: Remaining tests

- 2.1 T2 (all owned by ledger with a NONEXISTENT `repoRoot`: `all-owned`, no I/O, no model call). Hoist one shared `OTHER` pattern const.
- 2.2 T3 (mixed same-run plus ledger: `all-owned`; a pattern owned by both same-run and ledger: `other`).
- 2.3 T4 (one test: clock is `runStartedAt`, set far from the wall clock; TTL edges and invalid clock are already covered by `compound-promote-ledger.test.ts`).
- 2.4 T5 (backstop: model names an unoffered owned pattern, verdict `suppressed`).
- 2.5 Retitle the handler test "a pattern already proposed ... is SUPPRESSED" as a backstop test and add the prompt-omits-owned-slug assertion; leave the "recorded once and counted once" test untouched.
- 2.6 Run arm, handler, create-parity and runbook-parity suites and `./node_modules/.bin/tsc --noEmit` in `apps/web-platform`.

## Phase 3: Docs and learning

- 3.1 ADR-092: dated clause after the pinned phrase in the gate list plus a SHORT dated tail amendment containing no `STAGE_PHRASES` anchor; run the create-parity test after each ADR edit.
- 3.2 Runbook: "Same-run collision" bullet, `create_no_action_reason` row, `create_outcome` row sentence (same-run includes the edit loop's own ledger refusals; a model may return `all-owned` itself).
- 3.3 Learning under `knowledge-base/project/learnings/` (filter after the single decision cannot protect the decision).
- 3.4 `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch` exits 0; G1 baseline test green (87); markdownlint clean.

## Phase 4: Ship

- 4.1 PR body: `Ref #10550` (never `Closes`), states the structural cause is removed, does not claim a PR will open (unmeasured until a live-fire).
- 4.2 Merge, `deploy-arm.sh find --wait`, then served, then `soleur:postmerge`. Do not fire any cron; leave PR #11291 and the other listed issues alone.
