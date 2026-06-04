---
title: "Tasks — Revert #4913 fallback + KB db-error alert"
plan: knowledge-base/project/plans/2026-06-04-fix-revert-4913-fallback-and-kb-db-error-alert-plan.md
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Tasks

## Phase 0 — Preconditions

- [ ] 0.1 Grep `createServiceClient` call-sites + import in `kb-route-helpers.ts`.
- [ ] 0.2 Confirm `kb-route-helpers.ts` line present in `.service-role-allowlist`.
- [ ] 0.3 Read `sentry-kb-tenant-mint-alert-op-contract.test.ts:53-70` (OP_SLUGS rows).
- [ ] 0.4 Enumerate taken `frequency` set; pick next free (13) for the new rule.
- [ ] 0.5 Record CPO sign-off (single-user-incident threshold).
- [ ] 0.6 Resolve scope decision (whole-family vs `resolveUserKbRoot`-only; default whole-family).

## Phase 1 — Revert the service-role fallback

- [ ] 1.1 `resolveUserKbRoot`: replace service-role fallback with pre-#4913 503; PRESERVE
        `reportSilentFallback(op:"resolveUserKbRoot.tenant-mint")`.
- [ ] 1.2 (whole-family) `authenticateAndResolveKbPath`: revert jwt_mint/rotation branch to 503,
        keep denied_jti→403, preserve the emit.
- [ ] 1.3 Remove `createServiceClient` import iff both call-sites gone (`grep -c` == 0).
- [ ] 1.4 Update in-file comments to tenant-only + misdiagnosis rationale.
- [ ] 1.5 `.service-role-allowlist`: remove the #4913 block + line (same commit as import removal;
        CODEOWNERS @deruelle) — iff `createServiceClient` fully removed.
- [ ] 1.6 Revert #4913 fallback tests in `kb-route-helpers.test.ts` (RED first); assert 503 + emit.

## Phase 2 — Reconcile #4920 alert + op-contract test

- [ ] 2.1 Confirm the 3 `…tenant-mint` emits survive Phase 1; drop a slug from
        `issue-alerts.tf` `kb_tenant_mint_silent_fallback` IS_IN ONLY if its emit was removed.
- [ ] 2.2 Update `sentry-kb-tenant-mint-alert-op-contract.test.ts` OP_SLUGS 1:1 with any
        removed emit (else no-op; run suite to confirm green).

## Phase 3 — Wire the KB db-error alert

- [ ] 3.1 Add `sentry_issue_alert.kb_db_error` to `issue-alerts.tf` (feature==kb-share,
        op IS_IN db-error slugs verified by grep, frequency=next free, action_match=any,
        lifecycle ignore_changes=[environment]).
- [ ] 3.2 Add `-target=sentry_issue_alert.kb_db_error` to `apply-sentry-infra.yml` plan step.
- [ ] 3.3 Create `sentry-kb-db-error-alert-op-contract.test.ts` (block-scoped, mirrors #4920 test).

## Phase 4 — Close out

- [ ] 4.1 PR body: `Ref` PIR follow-ups + alert-to-file note; confirm #4914 closed as misdiagnosis.

## Acceptance gate

- [ ] Pre-merge AC checklist (plan `## Acceptance Criteria → Pre-merge`).
- [ ] Post-merge: apply-sentry-infra fires, creates kb_db_error rule.
