# Tasks: workspace egress audit log, PR2 read path and view (#9545)

Plan: `knowledge-base/project/plans/2026-10-26-feat-egress-audit-read-path-plan.md`. Spec: `spec.md` in this directory. Tests come first in every phase. Phases 4.3 and 5 start on day one in parallel with 1-3.

## Phase 0: Preflight

- [ ] 0.1 `git fetch origin`; pick migration number `NNN` = highest on any `origin/*` ref + 1 (plan Phase 0 command); re-check before merge and after every rebase
- [ ] 0.2 Place #9545 in a roadmap phase (or record why it ships out of phase) and move its milestone off "Post-MVP / Later"
- [ ] 0.3 Open the CLO review now (legal docs, DPIA t6, dialog and view copy); it is the long pole

## Phase 1: Database (red, then green)

- [ ] 1.1 Failing live-DB cases in `test/rls-fuzz/egress-audit-rollup.integration.test.ts` (member reads; other tenant, pending invitee, removed member get exactly `42501` in a SAVEPOINT with schema-valid args; anon and service_role cannot execute; direct SELECT denied; service-role positive control; co-member C passes and non-member D denied; aggregation, truncation, overflow, `p_limit = 0`, window edges, web-access-off history)
  - [ ] 1.1.1 Add pending-invitee and removed-member seeds to `test/rls-fuzz/harness-fixture.ts`
  - [ ] 1.1.2 Add the `ATTACK_SQL` entry in `test/rls-fuzz/rpc-cases.ts`; fix the stale comment in `test/rls-fuzz/targets.ts`
  - [ ] 1.1.3 Raise the egress step floor in `.github/workflows/rls-authz-fuzz.yml` to `>= (21 + N_new)`
- [ ] 1.2 Shape test `test/supabase-migrations/NNN-egress-audit-summary-rpc.test.ts` (definer, search_path, `42501`, grants, no table grant or policy, no timeout clause)
- [ ] 1.3 Migration `NNN_egress_audit_summary_rpc.sql` + `.down.sql` + `supabase/verify/NNN_*.sql` (records `authenticated` rolconfig)
- [ ] 1.4 Run `bun run test:rls-fuzz` and `cd apps/web-platform && ./node_modules/.bin/vitest run test/migration-rpc-grants.test.ts`
- [ ] 1.5 Measure per plan AC3a: `EXPLAIN (ANALYZE, BUFFERS)` cold and warm on three seeds (unique hosts; 100 repeating hosts at 500 rows per bucket; same with ~50 interleaved tenants), after `ANALYZE`/`VACUUM`, 6+ calls; budgets hint probe <= 20 ms, page warm p95 < 500 ms; record `authenticated` `rolconfig`. The hint uses the latest-bucket probe from the start
- [ ] 1.6 Tenant-boundary mutants: seed tenant B with distinct data and assert A sees none of it in every branch; membership check is the first statement (order oracle with an invalid `p_decision`); constant in-body message distinct from the grant-denial text; seed aggregation cases through `ingest_egress_audit_rollup`

## Phase 2: Loader and shared helper

- [ ] 2.1 Failing tests `test/egress-audit-read-loader.test.ts` (null workspace -> unbound; reader throw -> unavailable; RPC not called in either; 42501 -> forbidden and not mirrored; other errors and abort -> unavailable with one mirror; forged query params ignored; collection tri-state incl. unknown; webAccess null)
- [ ] 2.2 `server/egress-audit-collection.ts` (`isEgressAuditCollectionOn`); swap the inline call in `server/egress-audit-ingest.ts`; amend the flag comment in `lib/feature-flags/server.ts`
- [ ] 2.3 `server/egress-audit-read.ts` and `lib/egress-audit/summary.ts`
- [ ] 2.4 Sentry rule `egress-audit-read-failure` (`infra/sentry/issue-alerts.tf`, `alert-reference.json`; filter `feature eq egress-audit-read` and `op in rpc_error,rpc_timeout,workspace_read_error`) plus the op-contract test; reasons go in `op` with `err = null` and a static message per reason; hint mirror uses `mirrorWarnWithDebounce` with a stated key and distinct `errorClass`, registered in `server/observability.ts`

## Phase 3: UI

- [ ] 3.1 Failing component tests: `test/egress-audit-view.test.tsx` (every kind and precedence branch, error is never empty, filtered-empty, truncation wording, overflow label, "at least" everywhere, banner rule, no date or forbidden word in rendered text, chips as `NavLink` with `aria-current`) and `test/web-egress-toggle.test.tsx` (link in both states, hint shown/hidden, dialog copy by prop)
- [ ] 3.2 `app/(dashboard)/dashboard/settings/scope-grants/egress-audit/page.tsx` (force-dynamic, awaited `searchParams`) and `components/settings/egress-audit-view.tsx` plus the retry/refresh client island
- [ ] 3.3 Scope Grants page: concurrent bounded `p_limit = 0` read, collection check, debounced mirror, props to the toggle; remove the stale comment
- [ ] 3.4 `components/settings/web-egress-toggle.tsx`: link in both states, client-rendered "Last recorded request: X ago" (clamped at zero), Off status retention sentence when a last request exists, one-line recording notice for non-owners when collection is on, dialog notice tri-state (generic sentence on "unknown"); remove the stale comment
- [ ] 3.4a Page: workspace name in the subtitle, "(all outcomes)" summary label under a filter, footer erasure statement and link, banner text about pre-join visibility, `Cache-Control: private, no-store` verified in a browser or integration fetch
- [ ] 3.5 `tsc`, unit and component projects (vitest, not `bun test`)

## Phase 4: Records and documents

- [ ] 4.1 ADR-288 amendment; fix `dsar-export-allowlist.ts`, the runbook line and the archived-plan note
- [ ] 4.2 C4: read all three `.c4` files; fix the falsified text; add read edges; regenerate `model.likec4.json`; run the four C4 tests
- [ ] 4.3 Legal: CLO-led edits to the four `docs/legal` files and mirrors, Art. 30 rows, DPIA t6 section (verify CNIL Art. 35(4) wording), `compliance-posture.md`, DSAR runbook line; run the plan's grep sweep and decide every hit; SHA re-pin and date mirrors once, after the last rebase
- [ ] 4.4 CLO sign-off recorded for the view copy and the dialog notice

## Phase 5: Wireframe deltas (parallel, copy freeze at the end)

- [ ] 5.1 Subtitle, summary line, truncation wording, web-off notice, e2/e3 copy (no dates), banner hidden only on "Recording isn't on", filled selected chip
- [ ] 5.2 New frames 403 and filtered-empty, desktop and mobile (`07-22`..`07-25`); re-export changed frames
- [ ] 5.3 Verify `agent-web-access.pen` is 88861 bytes and `egress-audit-log.pen` has no `fileToken`; open the `.pen` only while tracked

## Gates before ready

- [ ] G1 Migration number re-verified against all `origin/*` refs
- [ ] G2 PR body: `Closes #9545`, `Ref #11237`, `Ref #11238`; states the flag flip is not in this PR
- [ ] G3 Review: `user-impact-reviewer`, `gdpr-gate`, security and data-integrity reviewers
