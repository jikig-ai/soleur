# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-jti-revoke-rls-3930-3932/knowledge-base/project/plans/2026-05-25-feat-jti-revoke-rls-3930-3932-plan.md
- Status: complete

### Errors
None. CWD verified at start. All three mandatory deepen-plan gates passed: 4.6 (User-Brand Impact present + threshold `single-user incident`), 4.7 (Observability 5-field schema present, no SSH in discoverability_test), 4.8 (no PAT-shaped variables). Phase 4.5 (network outage) did not trigger. Phase 4.45 (verify-the-negative + post-edit self-audit) caught and corrected 6 drift points before commit.

### Decisions
- Bundle as one PR, not split. Same migration, same JWT-deny semantics, same disclosure surface. Plan treats both #3930 (admin RPC + founder reader) and #3932 (PostgREST RLS predicate) as one feature with co-located implementation in `068_jti_deny_rls_predicate_and_revoke_rpc.sql`.
- v1 writer is service-role-only, NOT a new admin role. `users.role` is `{prd, dev}` per mig 054; introducing an `admin` role would require touching the JWT-mint hook + a new auth-tier surface. v1 scopes `revoke_jti` to service_role + an operator CLI mirroring sibling `byok-revoke.ts`. Future admin role/UI filed as a Tracked Deferral at PR close.
- Use RESTRICTIVE policies stacked on existing PERMISSIVE policies for 19 tenant tables. RESTRICTIVE policies are AND-combined; the new `<table>_jti_not_denied` denial layer is additive to mig 059's workspace-keyed and legacy `auth.uid()=user_id` policies. 9 service-role-only tables excluded explicitly.
- `request.jwt.claims` RLS predicate is novel. Phase 4.4 precedent-diff confirmed zero matches in `apps/web-platform/supabase/migrations/*.sql`. Flagged for scrutiny at multi-agent review by `architecture-strategist` + `data-integrity-guardian`.
- Operator CLI mirrors `byok-revoke.ts` exactly (sibling at PR #4232): `#!/usr/bin/env bun`, named flags, `createChildLogger`, `::error::` stderr, `createInterface(readline/promises)` confirm, NO Sentry breadcrumb (denied_jti row IS the WORM audit trail). NOT `npx tsx`, NOT `@/lib/sentry` (which doesn't exist).
- Brand-survival threshold: `single-user incident` carried forward from PR-B/C/D/E. `requires_cpo_signoff: true` in frontmatter. Phase 6 mandatory agents include `user-impact-reviewer`, `data-integrity-guardian`, `security-sentinel`, `gdpr-gate`.

### Components Invoked
- `soleur:plan` (skill) — produced initial plan + tasks.md, committed at SHA b4695546
- `soleur:deepen-plan` (skill) — Phase 4.4 precedent-diff, Phase 4.45 verify-the-negative + post-edit self-audit, Phase 4.6 + 4.7 + 4.8 mandatory gates. Deepened plan committed at SHA 6cf0ac83.
- Plan-Review was NOT auto-invoked (deepen-plan does not call plan-review; that's a separate step).
