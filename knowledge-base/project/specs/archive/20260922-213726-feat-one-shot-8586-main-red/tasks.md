# Tasks: fix main red after #8578 — bound queue-health probes, regen fixture baseline, register monitor (#8586, #8587)

Source plan: `knowledge-base/project/plans/2026-09-22-fix-main-red-queue-health-monitor-drift-plan.md`

## Phase 1: Bound the issue probes

- [ ] 1.1 Add `-L 200` (space-separated — `HAS_LIMIT` does not match `-L200`) to the auto-resolve
  enumeration probe in `.github/workflows/scheduled-actions-queue-health.yml` (~line 190, the
  `for n in $(gh issue list --repo "$GH_REPO" --state open --search 'in:title "[ci/actions-queue-health]"' ...)`
  loop).
- [ ] 1.2 Add `-L 1` to the two existence-drill probes (~lines 121 and 168, both
  `--jq '.[0].number // empty'` shapes) — defensive hardening per #8587's sibling-review directive.
- [ ] 1.3 Verify: `bun test plugins/soleur/test/components.test.ts` exits 0 (full gate file —
  CI `test-bun` runs `bun test plugins/soleur/` via `bash scripts/test-all.sh bun`).

## Phase 2: Regenerate the fixture-relative-assert baseline

- [ ] 2.1 Run `bash plugins/soleur/test/fixture-relative-assert.test.sh --write-baseline`.
- [ ] 2.2 Inspect `git diff plugins/soleur/test/fixture-relative-assert.baseline.txt` — expect
  exactly one new data row (`2\tscripts/actions-queue-health.test.sh`) plus header-count updates;
  abort and investigate any other drift (AC7).
- [ ] 2.3 Verify: `bash plugins/soleur/test/fixture-relative-assert.test.sh` exits 0 (arm A
  row-equality + arm B independent totals both pass at SITES=1569/FILES=296).
- [ ] 2.4 Sibling control: `bash plugins/soleur/test/fixture-dir-operand-assert.test.sh` stays
  71/71 green.

## Phase 3: Register the monitor and repair the prose counts

- [ ] 3.1 Add `"scheduled-actions-queue-health"` to `NON_INNGEST_MONITORS` in
  `apps/web-platform/test/server/inngest/function-registry-count.test.ts` (~line 83) with a
  class-convention comment (GHA-fired `scheduled-actions-queue-health.yml`, no `cron-*.ts`
  counterpart, no `SENTRY_MONITOR_SLUG`; terminal `sentry-heartbeat` step posts the check-in;
  same class as `scheduled-inngest-health` / `scheduled-prod-version-drift`).
- [ ] 3.2 `apps/web-platform/infra/sentry/README.md` ~line 35: `**58 cron monitors**` →
  `**59 cron monitors**`.
- [ ] 3.3 `apps/web-platform/scripts/sentry-monitors-audit.sh` Class D addendum (~lines
  1107-1114): `58 \`resource "sentry_cron_monitor"\` blocks` → `59` on the declaration-count line
  (keep it on ONE line — T25 greps that shape), name `scheduled-actions-queue-health` as the
  third post-verification addition, and update the trailing "silently promoted to 58" clause to
  59. Leave the dated 2026-08-19 "56 … live" sentence standing.
- [ ] 3.4 Verify: `cd apps/web-platform && npx vitest run test/server/inngest/function-registry-count.test.ts`
  exits 0 ((c2) phantom set empty; (d) untouched — the slug is not a `SENTRY_MONITOR_SLUG`).

## Phase 4: Verify all four gates green locally

- [ ] 4.1 `bun test plugins/soleur/test/components.test.ts` — exits 0.
- [ ] 4.2 `bash plugins/soleur/test/fixture-relative-assert.test.sh` — exits 0 (only the
  deliberate retracted self-test line in the ledger).
- [ ] 4.3 `bash apps/web-platform/scripts/sentry-monitors-audit.test.sh` — 52/52 pass.
- [ ] 4.4 `cd apps/web-platform && npx vitest run test/server/inngest/function-registry-count.test.ts`
  — 9/9 pass.
- [ ] 4.5 Sibling control: `npx vitest run test/server/inngest/sentry-monitor-iac-parity.test.ts`
  stays 18/18.
- [ ] 4.6 Confirm `git diff --name-only origin/main...HEAD` lists only the five Files-to-Edit rows
  plus `knowledge-base/` planning artifacts (AC5).
- [ ] 4.7 PR body carries `Closes #8586` and `Closes #8587`, each on its own body line (AC8).

## Out of scope

- `tenant-integration` red on the same commits — dev-Supabase migration-138 drift, tracked by
  #8583. Do not gate this PR on it.
- Re-homing `scheduled-actions-queue-health.yml` to an Inngest cron function — flagged by the
  deepen pass as a candidate follow-up (ADR-033 disposition recorded in the plan); not this PR.
