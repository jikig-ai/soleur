# Tasks: workspace egress audit log, PR1 (dark ingest pipeline plus legal commits)

Plan: `knowledge-base/project/plans/2026-10-15-feat-workspace-egress-audit-log-plan.md`. Issue #9545 (stays open; PR2 is tracked on it). Every code task is test-first: write the failing test, then the code.

## Phase 0: Gates before code

- [ ] 0.1 Draft the DPIA screening addendum with trigger t7 (CLO) under `knowledge-base/legal/audits/` and add the t6/t7 rows to `compliance-posture.md`
- [ ] 0.2 Measure real daily CONNECT volume from Better Stack (self-pull, 7-day window if retained); record rows/day and the resulting WAL estimate in the plan
- [ ] 0.3 Read the account-erasure saga to learn whether it deletes or anonymises the workspace row (decides the Art. 17 case 2 shape)
- [ ] 0.4 Confirm with the IaC architect the delivery path for the `egress-gateway-squid.conf` logformat change (the Vector change is the single shared `vector.toml`; the unit loads one file, so there is no fragment)
- [ ] 0.5 Verify whether `/api/internal/*` is blocked at the ingress; add the block if not
- [ ] 0.6 Measure before freezing the ACs: on the pinned Squid image whether `%un` logs the presented username on a failed login and whether `%>Hs` renders 407; with `vector test` the `reduce` window and `throttle` behaviour under a 100,000-unique-host flood (memory); that Vector 0.43.1 accepts `${VAR:-}` default interpolation

## Phase 1: Migration and database tests

- [ ] 1.1 RED: live-database harness cases (`RLS_FUZZ_LOCAL`): service-role write positive control, member reads denied, cascade on workspace delete, sweep deletes a 31-day row and keeps a 29-day row, per-column `GREATEST`/`LEAST`, toggle join drops `web_egress=false` rows
- [ ] 1.2 RED: offline text lints in `test/supabase-migrations/162-*.test.ts` (grants, search_path pin, comment, cron wrapper)
- [ ] 1.3 `162_workspace_egress_audit_rollup.sql`: table, composite key incl. `source_host`, FK `ON DELETE CASCADE`, RLS on, `REVOKE` all from anon/authenticated, `LAWFUL_BASIS` annotation, `COMMENT ON TABLE` with retention
- [ ] 1.4 `ingest_egress_audit_rollup(rows jsonb)`: `SECURITY DEFINER`, pinned `search_path` incl. `pg_temp`, service-role only, skips and counts unknown/toggle-off workspaces, never raises
- [ ] 1.5 `purge_egress_audit_rollup(retention interval)` plus daily `pg_cron` job in a `DO`/`EXCEPTION duplicate_object` block
- [ ] 1.6 `.down.sql` (unschedule, drop both functions) and `supabase/verify/162_*.sql` in the migration-158 `bad=1` row format
- [ ] 1.7 Register the table in `test/rls-fuzz/targets.ts`

## Phase 2: Ingest route and server module

- [ ] 2.1 RED: `test/egress-audit-ingest.test.ts` (token current/previous/unrelated, constant-time, body cap, zod, bucket bounds, flag-off 2xx before secret check, unknown workspace skipped, Sentry mirror debounced)
- [ ] 2.2 `server/egress-audit-ingest.ts` and `app/api/internal/egress-audit-ingest/route.ts` (HTTP-method exports only; loopback `Host`, reject forwarding headers)
- [ ] 2.3 `PUBLIC_PATHS` exact entry in `lib/routes.ts` and the csrf-coverage exemption
- [ ] 2.4 Runtime flag created with `soleur:flag-create` (the typed-`yes` step is handed to the operator); `.env.example` and `lib/feature-flags/server.ts`

## Phase 3: Gateway log and Vector config

- [ ] 3.1 RED: `egress-gateway.test.sh` case: a failed-authentication attempt naming a victim id yields a 407 row
- [ ] 3.2 Add `%>Hs` to the `soleur_json` logformat in `egress-gateway-squid.conf`
- [ ] 3.3 RED: `vector-egress-rollup.test.sh` plus synthesized fixtures (UUID filter, drop 407, `probe` heartbeat with no write, `bucket_start` floor, host cap with `(other)`, 100k-unique-host flood, restart re-emit)
- [ ] 3.4 Rollup transform, `throttle` per-workspace cap, `requested_host` length bound, and bearer sink (token through `${EGRESS_AUDIT_INGEST_TOKEN:-}`) with a disk buffer (`drop_newest`) in the shared `vector.toml`; `vector validate` passes with the variable unset and set
- [ ] 3.5 Extend the admission-test model; keep `validate-vector-config.yml` green

## Phase 4: Secret and delivery

- [ ] 4.1 Terraform `random_id` plus `doppler_secret` (`soleur`/`prd`, masked) following `github-app.tf`; no variable, no default
- [ ] 4.2 Order: secret exists, app route deployed, then Vector redelivery via the push apply of `journald_persistent{,_web2}`

## Phase 5: Records

- [ ] 5.1 New ADR (next free ordinal at the merge base) with alternatives and does-not-defend list
- [ ] 5.2 C4: read `model.c4`, `views.c4`, `spec.c4`; add the Vector-to-app edge; `bash scripts/regenerate-c4-model.sh`; run the C4 tests and `c4-count-parity`
- [ ] 5.3 ADR-281 one-line correction ("workflow fired with email action; receipt unobserved") and the runbook sentence
- [ ] 5.4 `scripts/egress-audit-retention-check.sh` (freshness compared with observed gateway activity, plus retention; non-zero on failure)
- [ ] 5.5 Bump the `BASELINE_DECLARED_PROBES` ratchet in `plugins/soleur/test/preflight-discoverability-test.test.ts` (66 to 67) with the required comment
- [ ] 5.6 CI proof that the live-database cases executed (non-zero executed count in `rls-authz-fuzz.yml`)
- [ ] 5.7 First line of the PR body states the merge effect: Vector is redelivered to the web hosts on merge

## Phase 6: Legal commits (last commits of the PR)

- [ ] 6.1 CLO-reviewed wording in the privacy policy, acceptable-use policy, data-protection disclosure and GDPR policy, each mirrored under `plugins/soleur/docs/pages/legal/`
- [ ] 6.2 Article 30 rows (PA-2, PA-8, processor capacity) and `compliance-posture.md` rows

## Not in this PR

- [ ] Enabling collection in production (operator-authorized; not before PR2 ships and the owner notice has been out 7 days; canary workspace excepted)
- [ ] PR2: member `SELECT` policy, read route, card, wireframe, DPIA t6 re-screen (planned after volume is measured)
