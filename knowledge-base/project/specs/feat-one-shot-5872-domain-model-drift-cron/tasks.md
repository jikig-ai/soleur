---
feature: feat-one-shot-5872-domain-model-drift-cron
issue: 5872
lane: single-domain
plan: knowledge-base/project/plans/2026-07-02-feat-scheduled-domain-model-drift-cron-plan.md
---

# Tasks — scheduled domain-model drift-check cron (#5872)

Derived from the plan. Phase order is dependency-directed (contract → consumer). All paths absolute to repo root.

## Phase 0 — Preconditions
- [ ] 0.1 Run `bash scripts/domain-model-drift.sh drift --repo . --register knowledge-base/engineering/architecture/domain-model.md`; confirm `## Stale register citations (N)` prints at column 0 and note rc (expect rc=1, stale=0, undoc=35 on main).
- [ ] 0.2 Confirm `jq` is on `ubuntu-latest` and the analyzer needs only checkout + bash + GH token (no Doppler/vendor cred).
- [ ] 0.3 Read `apps/web-platform/test/server/inngest/cron-dev-migration-drift.test.ts` (test template) and `.github/workflows/scheduled-terraform-drift.yml` (executor template).

## Phase 1 — Executor workflow (create)
- [ ] 1.1 Create `.github/workflows/scheduled-domain-model-drift.yml`: `on: workflow_dispatch: {}` ONLY (no `schedule:`); concurrency group `scheduled-domain-model-drift`; `permissions: {contents: read, issues: write}`; `timeout-minutes: 10`; SHA-pinned `actions/checkout` (fetch-depth 1).
- [ ] 1.2 Add "Run drift analyzer" step (id `drift`, `set +e`): run analyzer to `$RUNNER_TEMP`, capture `rc`, parse `stale` with the **Check 11 Step 11.2 parser verbatim** (`grep -oE '^## Stale register citations \([0-9]+\)' | head -1 | grep -oE '[0-9]+'`) and `undoc`; write `rc/stale/undoc` to `$GITHUB_OUTPUT` + `$GITHUB_STEP_SUMMARY`. On `rc==2`/`rc==3`: `::error::` + `exit 1`.
- [ ] 1.3 Add "Ensure label" step (`if: stale>0`): `gh label create "domain-model-drift" --color FBCA04 ... || true`.
- [ ] 1.4 Add "Create or update drift issue" step (`if: steps.drift.outputs.stale > 0`): idempotent `gh issue list --label domain-model-drift --state open --json number,title --jq select(.title==$T).number` → comment if found else `gh issue create --label domain-model-drift --milestone "Post-MVP / Later"`. Body = stale section verbatim + run link + Next Steps (`/soleur:sync domain-model`, unbacktick-filename note) + advisory footer (undoc expected-nonzero).
- [ ] 1.5 Add "Sentry check-in (final)" step (`if: always()`, `continue-on-error: true`): `./.github/actions/sentry-heartbeat`, slug `scheduled-domain-model-drift`, `status` ok when rc∈{0,1} else error, forward `secrets.SENTRY_*`.

## Phase 2 — Dispatcher (create)
- [ ] 2.1 Create `apps/web-platform/server/inngest/functions/cron-domain-model-drift.ts` by copying `cron-dev-migration-drift.ts`: `FUNCTION_NAME`/`id`=`cron-domain-model-drift`, `WORKFLOW_FILE`=`scheduled-domain-model-drift.yml`, cron `0 8 * * 1`, event `cron/domain-model-drift.manual-trigger`; keep dispatch-only HARD NON-GOAL comment, `redactToken`, `reportSilentFallback`, concurrency + `retries: 1`.

## Phase 3 — Registration + parity
- [ ] 3.1 `apps/web-platform/app/api/inngest/route.ts` — add import + `cronDomainModelDrift,` in `functions:[…]`.
- [ ] 3.2 `apps/web-platform/server/inngest/cron-manifest.ts` — add `"cron-domain-model-drift",` to `EXPECTED_CRON_FUNCTIONS` (alphabetical).
- [ ] 3.3 `apps/web-platform/server/inngest/routine-metadata.ts` — add `"cron-domain-model-drift"` entry (`domain: engineering`, `scheduleLabel: "Weekly (Mon 08:00 UTC)"`, `manualTrigger: "allowed"`).

## Phase 4 — Sentry monitor IaC
- [ ] 4.1 `apps/web-platform/infra/sentry/cron-monitors.tf` — add `sentry_cron_monitor "scheduled_domain_model_drift"` (name `scheduled-domain-model-drift`, crontab `0 8 * * 1`, margin 120, max_runtime 15) modeled on `scheduled_terraform_drift`.
- [ ] 4.2 `.github/workflows/apply-sentry-infra.yml` — add `-target=sentry_cron_monitor.scheduled_domain_model_drift` to the `-target=` allowlist.

## Phase 5 — Tests
- [ ] 5.1 Create `apps/web-platform/test/server/inngest/cron-domain-model-drift.test.ts` mirroring `cron-dev-migration-drift.test.ts` (registration anchors, dispatch anchors, NON-GOAL negative anchors, behaviour + token-redaction).
- [ ] 5.2 `apps/web-platform/test/server/inngest/function-registry-count.test.ts` — bump route count `58`→`59`; add `"scheduled-domain-model-drift"` to `NON_INNGEST_MONITORS`.
- [ ] 5.3 Verify auto-green parity tests still pass (routine-metadata-parity, manual-trigger-allowlist, trigger-cron-allowlist-parity, list-routines, sentry-monitor-iac-parity).

## Phase 6 — ADR-076 + C4
- [ ] 6.1 Amend `ADR-076-domain-model-drift-extraction.md` enforcement section (one line: scheduled cron built; consumes stale-count contract).
- [ ] 6.2 Read the three `.c4` files; cite the "no C4 impact" enumeration (external actor/system/relationship). Only run c4 tests if a `.c4` edit is made (expected: none).

## Phase 7 — Verify
- [ ] 7.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [ ] 7.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-domain-model-drift.test.ts test/server/inngest/function-registry-count.test.ts test/server/inngest/routine-metadata-parity.test.ts test/lib/inngest/manual-trigger-allowlist.test.ts test/server/inngest/sentry-monitor-iac-parity.test.ts`.
- [ ] 7.3 `actionlint .github/workflows/scheduled-domain-model-drift.yml`.
- [ ] 7.4 Dry-run the executor parse block against `main` → expect `stale=0`, no issue filed.
