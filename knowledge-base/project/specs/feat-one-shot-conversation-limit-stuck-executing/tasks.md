# Tasks: fix concurrent-conversation cap tripped by stuck-Executing dashboard conversation

Plan: `knowledge-base/project/plans/2026-05-06-fix-one-shot-conversation-limit-stuck-executing-plan.md`

## Phase 0 — Pre-flight (no code)

1.1 Verify `STUCK_ACTIVE_THRESHOLD_SECONDS = 120` and cadence `60_000` are unchanged on `main` (`apps/web-platform/server/agent-runner.ts:519-520`).
1.2 Verify migration 037 RPC default `p_threshold_seconds = 120`.
1.3 Verify migration 036 archive-trigger present on prod (no rollback needed).
1.4 Confirm migration 029 lazy-sweep predicate at line ~131 still uses `interval '120 seconds'`.

## Phase 1 — Server: extend `tryLedgerDivergenceRecovery`

2.1 Add `STALE_HEARTBEAT_THRESHOLD_MS = 120_000` constant + THRESHOLD-COUPLING comment block referencing the four sibling sites.
2.2 Add stale-heartbeat SELECT after the existing slot-rows query in `ws-handler.ts:271-284`.
2.3 Compute deduplicated union of `orphans ∪ stale` keyed by `conversation_id`.
2.4 Reap union: `releaseSlot` + `updateConversationFor(...status: 'failed', expectMatch: false)` for each.
2.5 Update Sentry mirror at line 331-340 to include `staleHeartbeatCount`.
2.6 Update `didRecover` semantic: returns `true` if EITHER set non-empty.

## Phase 2 — Client: error-copy clarity

3.1 Update `apps/web-platform/lib/ws-client.ts:124-126` CONCURRENCY_CAP reason copy.
3.2 Verify `apps/web-platform/components/concurrency/upgrade-at-capacity-modal.tsx` doesn't duplicate the old "completed" wording; sync if needed.

## Phase 3 — Tests (TDD: RED before GREEN per cq-write-failing-tests-before)

4.1 RED — stale-heartbeat reap path (extends `ws-handler-cap-hit-self-heal.test.ts`).
4.2 RED — fresh-heartbeat slot is NOT reaped (gate-presence vs gate-absence).
4.3 RED — orphan + stale-heartbeat coexistence (both reaped, Sentry payload shows both counts).
4.4 RED — copy-anchor regression in `ws-close-helper.test.ts`.
4.5 Integration — extend `conversation-archive-release-slot.integration.test.ts` with a stale-heartbeat seed + ws-handler call-site invocation.
4.6 GREEN — implement Phase 1 + Phase 2; tests pass.
4.7 REFACTOR — extract magic-number 120000 if used in 2+ places within Phase 1 changes; otherwise leave as a single named constant.

## Phase 4 — Observability

5.1 Sanity-grep for the new Sentry tag wiring after deploy.
5.2 No new logger entries needed (existing `log.info` at ws-handler line 472-475 covers the new branch).

## Phase 5 — Domain & review gates

6.1 Push branch (`rf-before-spawning-review-agents-push-the`).
6.2 Invoke CPO sign-off at PR (per `requires_cpo_signoff: true`).
6.3 Invoke `user-impact-reviewer` at PR (per `single-user incident` threshold).
6.4 Run `skill: soleur:review` on the branch.
6.5 Address all review findings inline (default fix-inline per `rf-review-finding-default-fix-inline`).

## Phase 6 — QA

7.1 Run `skill: soleur:qa` if applicable (the bug surface is not visually re-renderable without a stuck-active fixture).
7.2 Manual QA path described in plan §Test Strategy.
7.3 Capture the dashboard "Active conversations" rail post-fix (no `active`+`>3 min old` rows for free-tier).

## Phase 7 — Ship

8.1 Run `skill: soleur:compound` to capture session learnings.
8.2 Run `skill: soleur:preflight` (Check 6 will validate User-Brand Impact section).
8.3 Run `skill: soleur:ship` with `patch` semver label (no API/contract changes; copy + recovery path widening only).
8.4 Verify auto-merge succeeds and post-merge release workflow is green.

## Phase 8 — Post-merge verification

9.1 Sentry: confirm `feature: "concurrency-ledger-divergence"` events post-deploy include `staleHeartbeatCount` field.
9.2 Spot-check production dashboard for accumulating stuck-active rows (should be near zero).
9.3 Capture telemetry baseline for the new path's fire rate. File a follow-up issue if non-zero (a non-zero rate means a NEW slot-leak class crept in — investigate).
