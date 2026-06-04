---
title: "Tasks — Revert #4913 fallback + KB db-error alert"
plan: knowledge-base/project/plans/2026-06-04-fix-revert-4913-fallback-and-kb-db-error-alert-plan.md
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Tasks

## Phase 0 — Preconditions

- [x] 0.1 Grep `createServiceClient` call-sites + import in `kb-route-helpers.ts`. (4 import / 114 / 283)
- [x] 0.2 Confirm `kb-route-helpers.ts` line present in `.service-role-allowlist`. (line 301)
- [x] 0.3 Read `sentry-kb-tenant-mint-alert-op-contract.test.ts:53-70` (OP_SLUGS rows). (3 slugs)
- [x] 0.4 Enumerate taken `frequency` set; pick next free (13). (taken 5,10,11,12,15,30,60,61,62 → 13)
- [~] 0.5 CPO sign-off (single-user-incident threshold). Autonomous run — surfaced for founder
        in PR body; review-phase `user-impact-reviewer` enforces the threshold.
- [x] 0.6 Scope decision: WHOLE-FAMILY (revert both resolveUserKbRoot + authenticateAndResolveKbPath),
        per plan default + PIR line 109. Only scope that drops the import + allowlist line cleanly.

## Phase 1 — Revert the service-role fallback

- [x] 1.1 `resolveUserKbRoot`: service-role fallback → 503; PRESERVED
        `reportSilentFallback(op:"resolveUserKbRoot.tenant-mint")`.
- [x] 1.2 `authenticateAndResolveKbPath`: jwt_mint/rotation → 503, denied_jti → 403, emit preserved.
- [x] 1.3 Removed `createServiceClient` import (both call-sites gone, `grep -c` == 0).
- [x] 1.4 Updated in-file comments to tenant-only + misdiagnosis rationale.
- [x] 1.5 `.service-role-allowlist`: removed the #4913 block + line; gate exits 0.
- [x] 1.6 Reverted fallback tests in `kb-route-helpers.test.ts` (RED first → GREEN); assert 503/403 + emit.

## Phase 2 — Reconcile #4920 alert + op-contract test

- [x] 2.1 Confirmed all 3 `…tenant-mint` emits survive Phase 1 → no IS_IN slug removed.
- [x] 2.2 `sentry-kb-tenant-mint-alert-op-contract.test.ts` unchanged → 6 passed (no-op confirmed).

## Phase 3 — Wire the KB db-error alert

- [x] 3.1 Added `sentry_issue_alert.kb_db_error` (feature==kb-share, op IS_IN
        create,list,revoke,preview,preview-invariant; frequency=13; action_match=any;
        lifecycle ignore_changes=[environment]).
- [x] 3.2 Added `-target=sentry_issue_alert.kb_db_error` to `apply-sentry-infra.yml` plan step.
- [x] 3.3 Created `sentry-kb-db-error-alert-op-contract.test.ts` (block-scoped) → 9 passed.

## Phase 4 — Close out

- [x] 4.1 PR body: `Ref` PIR follow-ups + alert-to-file note; #4914 already CLOSED (misdiagnosis). (at ship)

## Acceptance gate

- [x] Pre-merge AC checklist (plan `## Acceptance Criteria → Pre-merge`) — all satisfied;
      tsc green, vitest 56 green, terraform fmt/validate green, allowlist gate exit 0.
- [~] Post-merge: apply-sentry-infra fires on merge, creates kb_db_error rule (automated workflow apply).
