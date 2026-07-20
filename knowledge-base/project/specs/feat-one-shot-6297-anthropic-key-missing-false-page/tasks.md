# Tasks — fix: stop the daily false page from the Anthropic cost-report cron

Plan: `knowledge-base/project/plans/2026-07-20-fix-anthropic-key-missing-false-page-plan.md`
Issue: #6297 · Branch: `feat-one-shot-6297-anthropic-key-missing-false-page` · Lane: `cross-domain`

> Phase numbering intentionally skips 3 — the day-31 severity escalation was cut at plan-review.
> See `decision-challenges.md` DC-1.

## Phase 0 — Preconditions (read before editing)

- [ ] 0.1 Read `apps/web-platform/server/inngest/functions/cron-anthropic-cost-report.ts` in full.
- [ ] 0.2 Read `apps/web-platform/server/observability.ts` — confirm `warnSilentFallback` logs via
      `logger.warn` (pino 40) and emits `Sentry.captureMessage(..., { level: "warning" })`.
- [ ] 0.3 Read `apps/web-platform/test/server/inngest/cron-anthropic-cost-report.test.ts` — note the
      `vi.mock("@/server/observability", …)` factory exports **only** `reportSilentFallback`.
- [ ] 0.4 Read `apps/web-platform/server/claude-cost-marker.ts` — note the dedicated pino instance and
      its `base: { component: "claude-cost" }`.
- [ ] 0.5 Read `scripts/followthroughs/cert-reissue-markers-6698.sh` (the probe model) and
      `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` lines 17-25.

## Phase 1 — D1: make the key-missing branch non-paging

- [ ] 1.1 **RED.** Add `warnSilentFallbackSpy` to the `vi.hoisted` block **and** to the
      `vi.mock("@/server/observability")` factory. *(Skipping the factory yields a `TypeError`
      instead of a clean assertion failure.)*
- [ ] 1.2 **RED.** key-missing test: assert `warnSilentFallback` called with `null` +
      `op: "anthropic-admin-key-missing"`, `reportSilentFallback` **not** called, and the message
      carries the content anchor `daily cost report is dark`.
- [ ] 1.3 **RED.** 401 and 403 tests: assert `reportSilentFallback` called with an `Error` +
      `op: "anthropic-admin-key-invalid"`, and `warnSilentFallback` **not** called.
- [ ] 1.4 Confirm the new tests FAIL. Capture output for the PR body (AC1).
- [ ] 1.5 **GREEN.** Add `warnSilentFallback` to the `@/server/observability` import in the cron; swap
      the key-missing branch's `reportSilentFallback(null, …)` → `warnSilentFallback(null, …)`.
      Leave `feature` / `op` / `message` / `extra` values unchanged.
- [ ] 1.6 Verify no change to schedule, concurrency, retries, 401/403 arm, 429/5xx rethrow,
      `isFinalAttempt`, or the success path (AC5).

## Phase 2 — D2a: carry the dark-window age

- [ ] 2.1 `claude-cost-marker.ts`: add optional `days_since_first_dark?: number` to
      `ClaudeCostDailyMarker`, with the comment documenting that it does **not** reset across a
      mint-then-rotate cycle.
- [ ] 2.2 Cron: add `const FIRST_DARK_FIRE = "2026-07-10"` and exported
      `daysSinceFirstDark(now: Date = new Date()): number` (whole UTC days, floored at 0).
- [ ] 2.3 Pass `days_since_first_dark` on the key-missing marker call and in the
      `warnSilentFallback` `extra`.
- [ ] 2.4 Unit-test `daysSinceFirstDark` with explicit `Date` args (pre-date → 0; 2026-07-20 → 10).
- [ ] 2.5 Assert the `status:"ok"` payload does **not** carry the field (AC9).

## Phase 4 — D2b: self-closing follow-through tracker

- [ ] 4.1 Create `scripts/followthroughs/anthropic-admin-key-6297.sh` (mode 0775), modelled on
      `cert-reissue-markers-6698.sh`. `#!/usr/bin/env bash`, `set -uo pipefail` (**not** `-e`).
- [ ] 4.2 **P0 — field isolation.** PASS requires **both** `"SOLEUR_CLAUDE_COST_DAILY":true` **and**
      `"component":"claude-cost"`. A marker-name-only match can be satisfied by the webhook echo of
      this PR/issue body and would false-close the tracker.
- [ ] 4.3 Pin `--since 48h` (Better Stack retention is 3 days).
- [ ] 4.4 Exit contract: `0` = field-isolated `"status":"ok"` row; `1` = genuine regression only;
      `2` = still key-missing / query or auth failure / missing `betterstack-query.sh` / zero
      producer rows.
- [ ] 4.5 Secret guard must use `if [[ -z "${VAR:-}" ]]; then …; exit 2; fi` — **never**
      `: "${VAR:?msg}"` (aborts with status 1 = FAIL). Do not copy `ghcr-minter-live-6031.sh:28`.
- [ ] 4.6 Zero-row path: cross-check Sentry (independent Layer-2 transport) and print the divergence;
      emit `STALLED:` after 7 consecutive zero-row runs, still exiting 2.
- [ ] 4.7 Update #6297: remove `priority/p3-low`; add `priority/p2-medium` + `follow-through`; keep
      `deferred-automation` label **and** the literal body string.
- [ ] 4.8 Add the `<!-- soleur:followthrough … -->` directive with
      `secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD` and
      `earliest=2026-07-20T00:00:00Z`.
- [ ] 4.9 **Playwright-first (blocking).** Attempt the Console mint at `console.anthropic.com` →
      Settings → API keys. Record a `playwright-attempt:` evidence line. Only if a *named* human gate
      (CAPTCHA/OTP/TOTP/passkey/push-MFA/payment-card/hardware-token) is reached may the operator
      text ship. Do **not** assert operator-only from the docs FAQ alone.
- [ ] 4.10 Rewrite the #6297 operator section in plain language (§Operator Action).

## Phase 5 — Records

- [ ] 5.1 Amend ADR-108: add `days_since_first_dark` to `## Decision`; note the non-reset semantics in
      `## Consequences`. Do **not** create a new ADR ordinal.
- [ ] 5.2 Update `betterstack-log-query.md` §"Querying Anthropic cost markers": document
      `days_since_first_dark` and the `"component":"claude-cost"` field-isolation requirement.
- [ ] 5.3 File a tracking issue for the 19 pre-existing probes using the banned `${VAR:?}` form,
      proposing the AC10 grep as a CI guard (`wg-when-an-audit-identifies-pre-existing`).

## Phase 6 — Verification

- [ ] 6.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0.
- [ ] 6.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-anthropic-cost-report.test.ts`
      exits 0.
- [ ] 6.3 Full-suite exit gate.
- [ ] 6.4 Walk AC1–AC19 (pre-merge). Confirm AC6 and AC10 use the `if … grep -q` / `if grep …` forms,
      not `grep -c` (exit-status inversion).
- [ ] 6.5 `bash -n` the probe; run the AC12 negative control (probe must not exit 0 against a window
      whose only matches are the webhook echo).
- [ ] 6.6 PR body uses **`Ref #6297`**, not `Closes #6297`.
- [ ] 6.7 Confirm zero `.tf` files in the diff.
