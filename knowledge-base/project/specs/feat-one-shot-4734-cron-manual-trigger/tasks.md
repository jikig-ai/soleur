---
issue: 4734
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-01-feat-cron-manual-trigger-route-plan.md
---

# Tasks — on-demand cron trigger route (#4734)

## Phase 1 — Manifest leaf + allowlist module + drift test (contract first)

- [x] 1.1 Create client-free leaf `apps/web-platform/server/inngest/cron-manifest.ts`:
      move `EXPECTED_CRON_FUNCTIONS` + `manualTriggerEventFor` out of
      `cron-inngest-cron-watchdog.ts` (which statically imports the Inngest client →
      throws outside `NEXT_PHASE=phase-production-build`). Re-export from the watchdog so
      `function-registry-count.test.ts (e)` + `cron-inngest-cron-watchdog.test.ts` stay green.
- [x] 1.2 Create `apps/web-platform/lib/inngest/manual-trigger-allowlist.ts`
      (`MANUAL_TRIGGER_EVENTS` Set + `isAllowlistedManualTrigger`), importing the manifest
      from `cron-manifest.ts` (NOT the watchdog).
- [x] 1.3 RED→GREEN `test/lib/inngest/manual-trigger-allowlist.test.ts`: allowlist equals
      `EXPECTED_CRON_FUNCTIONS.map(manualTriggerEventFor)`; known event allowlisted,
      non-cron / `evil` rejected.

## Phase 2 — Route handler (RED→GREEN per branch)

- [x] 2.1 (Signature confirmed at deepen-plan: `sendInngestWithRetry(fn: () => Promise<unknown>,
      context)` — arg #1 is a THUNK. Dispatch as
      `sendInngestWithRetry(() => inngest.send({name, data}), { feature: "trigger-cron" })`
      with a dynamic `const { inngest } = await import("@/server/inngest/client")` inside
      the handler — mirror `app/api/webhooks/github/route.ts:285-286`.)
- [x] 2.2 Create `apps/web-platform/app/api/internal/trigger-cron/route.ts` (`POST` only).
- [x] 2.3 RED→GREEN `test/server/internal/trigger-cron-route.test.ts` (mirror
      `kb-drift-ingest-route.test.ts` mock harness):
  - [x] 2.3.1 secret unset → 503 (no dispatch).
  - [x] 2.3.2 valid secret + allowlisted event → 202 + `sendInngestWithRetry` called once.
  - [x] 2.3.3 missing / wrong / wrong-length Bearer → 401 (no dispatch).
  - [x] 2.3.4 malformed JSON → 400.
  - [x] 2.3.5 non-allowlisted event → 400 (no dispatch).
  - [x] 2.3.6 `sendInngestWithRetry` throws → 502 + `reportSilentFallback`.
- [x] 2.4 Confirm route file exports only `POST` (`cq-nextjs-route-files-http-only-exports`).

## Phase 3 — IaC (Doppler secret, dev + prd)

- [x] 3.1 `inngest.tf`: add 2 `random_id` + 2 `doppler_secret`
      (`INNGEST_MANUAL_TRIGGER_SECRET`, byte_length 32, `ignore_changes = [value]`);
      update header comment totals (4→6 random_id, 5→7 doppler_secret).
- [x] 3.2 `inngest.test.sh`: bump count comments + add 4 per-resource asserts;
      `bash apps/web-platform/infra/inngest.test.sh` exits 0.
- [x] 3.3 `apply-web-platform-infra.yml`: add 4 `-target=` lines next to inngest targets.
- [x] 3.4 `.env.example`: add documented commented `INNGEST_MANUAL_TRIGGER_SECRET` entry.

## Phase 4 — Review + ship gates

- [ ] 4.1 security-sentinel review (auth strength + allowlist scope — Open Questions 1-3).
- [ ] 4.2 CPO sign-off (`requires_cpo_signoff: true`, single-user-incident threshold).
- [ ] 4.3 PR body uses `Closes #4734`.

## Phase 5 — Post-merge (operator)

- [ ] 5.1 After Doppler apply + container restart, fire
      `cron/workspace-sync-health.manual-trigger` (expect 202); confirm went-quiet
      detector (#4717) ran via Sentry API (not dashboard eyeballing).
