# Tasks: founder approval cards, PR-D (#12011)

Plan: `knowledge-base/project/plans/2026-11-05-feat-legal-acceptance-verify-endpoint-and-hold-gate-plan.md` (Phases D1 to D8, AC1 to AC19). PR-A to PR-C are merged. This PR references #12011 and does not close it.

Scope: the check endpoint, its own bearer token, the `web-acceptance` hold gate, the pull-only note delivery, the ack table that gives `row_without_event` an emitter. The Terraform secrets are a plan only (Operator Holds, #12196); no file under `apps/web-platform/infra/` changes.

## 1. Setup

- [ ] 1.1 Re-verify migration number 185 against `origin/main` and open PR heads; re-verify ADR ordinals are not needed (amendment only)
- [ ] 1.2 Read all three C4 files before any edit (completeness mandate)

## 2. Failing tests first

- [ ] 2.1 `migration-185-legal-acceptance-ack.test.ts` (static shape, mirrors 184) and the tenant-isolation extension
- [ ] 2.2 `verify-service.test.ts` (strict payload, every status, `bad_payload`)
- [ ] 2.3 `verify-route.test.ts` (Guard 2 rows 1 to 9, closed status set, middleware predicate for `PUBLIC_PATHS`, no note in any payload)
- [ ] 2.4 `ack-reconciliation.test.ts` (Guard 3: flush true/false/throws/never resolves, ack error, `already_recorded`, grace, two hashes)
- [ ] 2.5 `cross-layer-limits.test.ts` (key and hash shapes extracted from source; fails on empty extraction)
- [ ] 2.6 `canonical.ts` `read_failed` versus `unknown_key` unit test
- [ ] 2.7 `hold-gate-eval.test.sh` additions with `doppler` and `curl` PATH stubs (Guard 1 rows 1 to 11 and the closed reason table) and `plugins/soleur/scripts/lib/bearer-curl.sh` test

## 3. Core implementation

- [ ] 3.1 Migration 185 (+ down, + `verify/185`), annotations, `DSAR_TABLE_EXCLUSIONS` entry (Phase D1)
- [ ] 3.2 `canonical.ts` split; `internal-auth.ts` closed-union name; `lib/routes.ts` narrow entry; `.env.example` comments (Phase D2)
- [ ] 3.3 `service.ts` `verifyAcceptance`, `ackAcceptance`, `ackState`; the endpoint route (Phase D2)
- [ ] 3.4 `ops.ts` `record_invalid`, `store_failed`; `decideLegal` injected flush and off-path ack; contract test exempt list naming #12195 (Phase D4)
- [ ] 3.5 `bearer-curl.sh` helper; `hold-gate-eval.sh` kind, `PERSON` result, no-delegation classification, closed reason table; `trigger.sh` adopts the helper only if its suite is unchanged (Phase D3)
- [ ] 3.6 `operator-holds.md` and `standing-delegation.md` section 3 (Phase D3)

## 4. Records and docs

- [ ] 4.1 Runbook `legal-acceptance-note-read.md` (Phase D5)
- [ ] 4.2 PA-40 addendum (merge-conditioned wording) and attestation narrowing with `Superseded` marker (Phase D6)
- [ ] 4.3 ADR-319 amendment, ADR-320 scope note, `legal-acceptance/README.md` (Phase D7)
- [ ] 4.4 C4 edits, `scripts/regenerate-c4-model.sh`, C4 tests including freshness and count parity (Phase D7)

## 5. Gate and ship

- [ ] 5.1 File-selected test runs; census tests; markdown lint; no path under `apps/web-platform/infra/` in the diff (AC13)
- [ ] 5.2 Full-coverage review (single-user incident), compound, ship with `Ref #12011`; Operator Holds item linked to #12196
- [ ] 5.3 Post-merge: `deploy-arm.sh`, the dark probe (503, not 307), `verify/185` result; then the operator items in the plan's enabling conditions
