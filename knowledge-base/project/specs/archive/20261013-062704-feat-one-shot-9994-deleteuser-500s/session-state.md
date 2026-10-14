# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-12-fix-integration-deleteuser-500s-teardown-plan.md
- Status: complete
- cto_spawns=1

### Errors
markdownlint violations in plan draft (fixed); sentinel-census estimate corrected (~13 -> 32 census / 12 scoped); AC6 verification command over-match tightened in deepen; no fatal errors.

### Decisions
- Fix is suite-side only: no production code, no migration, no workflow change. Root cause confirmed live: workspace_members_user_id_fkey ON DELETE RESTRICT + handle_new_user trigger.
- Widen tearDownTenantUser sentinel to prefix allowlist; adopt in 5 defective suites (beta-crm-dsar, byok, cc-dispatcher, conversations-rail, dsar-export).
- Fold-ins: workspace_id repairs on conversations + messages inserts (mig 059 NOT NULL); dsar-export strict helper path.
- Sentinel scoped to test/*.integration.test.ts + test/helpers/; test/server/** deferred to #10096.
- All six technical rulings confirmed by batched CTO spawn 2026-10-12.
- brand_survival_threshold: single-user incident; requires_cpo_signoff: true (helper mirrors Art-17 cascade).

### Components Invoked
soleur:plan, soleur:deepen-plan (via planning subagent); soleur:engineering:cto (batched ruling spawn); follow-ups filed: #10094, #10095, #10096. #9993 referenced only; #9995 owned by sibling session.

## Review+Ship Phase (post-summary continuation)
- Review: 13-seat panel + 12-seat targeted fix-round + fresh-eyes verifier = SHIP.
- Trailers: Reviewed-Coverage full 13/13 + Reviewed-Fix-Round emitted on-branch.
- Compound: 3 learnings captured (WORM-cascade carve-out pattern; chokepoint audits; vacuous GC checks).
- CI: tenant-integration failed once on dev-ledger-parity (pre-hardening 160 blob ledgered by an earlier CI apply) — resolved via `dev-ledger-reconcile.yml` execute=true (row discarded + down.sql applied); subsequent apply restores current body + fresh sha on each run.
- test aggregator red on draft is ADR-276 "full battery owed at ready" — PR marked ready, full battery in progress.
- Errors this phase: git-checkout wiped uncommitted sentinel edits (reapplied); docblock `.js*/` terminated early (esbuild); tally missing-file (re-init); down.sql `$$` claim by one seat disproven (uses `$fn$`).

### Forwarded
- Next: merge per ship Phase 7 once battery green → postmerge skill → release/post-merge verification.
- Scope preserved: #9995 sibling, #10017 tmp-leak, #7004 deferred — all OUT of this PR.
