---
title: "feat: convert gdpr-gate 50d eval to Inngest one-shot (TR9 PR-G)"
date: 2026-05-25
type: enhancement
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
parent_issue: 3948
tracking_issue: 3948
pr: 4461
brainstorm: knowledge-base/project/brainstorms/2026-05-25-convert-gdpr-gate-50d-eval-to-inngest-brainstorm.md
spec: knowledge-base/project/specs/feat-convert-gdpr-gate-50d-eval-to-inngest/spec.md
---

# feat: convert gdpr-gate 50d eval to Inngest one-shot (TR9 PR-G)

## Overview

Convert `.github/workflows/scheduled-gdpr-gate-preflight-eval-50d.yml` to an Inngest event-triggered one-shot function. Final child of TR9 umbrella #3948 — the only "CONVERT to inngest.send-triggered one-shot" (all other children were cron-to-cron ports).

The handler fires once on 2026-06-29 09:00 UTC, counts escaped gdpr-gate Critical findings over the 50-day post-#3501 window, and posts a structured comment on #3516. Three outcomes: (a) 0 escapes → re-arm 90-day checkpoint, (b) 1–2 → re-arm + note, (c) ≥3 → recommend wiring Check 10 now.

**Handler template:** PR-6 `cron-strategy-review.ts` (pure-TS Octokit, no clone, no claude-eval spawn). **Sender:** manual `inngest send` CLI at merge time.

[Updated 2026-05-25 — post 5-agent plan review. Applied 3 P0 fixes (wrong timestamp, ts units, hardcoded D3) + 4 structural simplifications (kill ephemeral workspace, kill Sentry TF monitor, simplify D5, collapse phases).]

## Research Reconciliation — Spec vs. Codebase

| Spec/Brainstorm Claim | Reality | Plan Response |
|---|---|---|
| `cron_run_ledger` UNIQUE constraint for arming idempotency | Table DELETED from PR-1; 4-of-5 reviewers flagged it redundant. Zero references in codebase. | **Drop.** Use Inngest event `id` dedupe + handler D3 date guard. |
| `gh pr list --search` in handler eval step | `gh` CLI absent from production Docker image. | **Port to Octokit:** `GET /repos/{owner}/{repo}/pulls` with `state=closed` + client-side `merged_at` date filter + label filter. Explicit pagination with 10-page defensive cap. |
| Two Sentry monitors (arming + handler) | `sentry_cron_monitor` requires recurring `schedule.crontab`; annual false-miss in 2027 requires manual TF resource deletion. | **Drop both TF monitors.** Use inline `reportSilentFallback` + Sentry heartbeat POST only. The handler's error paths emit to Sentry without a dedicated monitor. |
| Ephemeral workspace (`git clone --depth=1`) for `incidents.log` | Only reads one file. Clone + tmpdir + teardown = ~40 LOC overhead. | **Drop.** Use Octokit `GET /repos/{owner}/{repo}/contents/.claude/hooks/incidents.log`. One API call. |
| D5 immutability pin (3 assertions: author + created_at + updated_at) | Over-defense for an internal governance comment the operator authored. Unresolved re-arm wiring problem. | **Simplify to author-login check only.** Drop `created_at === updated_at` and `expectedCreatedAt` assertions. Dissolves the re-arm D5 wiring problem. |
| D3 hardcodes `"2026-06-29"` | 90-day re-arm fires handler on 2026-08-10 → D3 rejects immediately because `today !== "2026-06-29"`. | **Parameterize.** D3 reads `event.data.expected_date` instead of compile-time constant. |
| `ts: 1751187600000` = 2026-06-29 | **WRONG.** `1751187600000` ms = **2025-06-29** (past). Correct: `1782723600000` ms. | **Fix.** All `ts` values updated to `1782723600000`. |

## User-Brand Impact

**If this lands broken, the user experiences:** Compliance-gate wire/skip decision made without empirical data. Operator discovers the miss weeks later when manually checking #3516.

**If this leaks, the user's workflow is exposed via:** Wrong-target eval (event payload addresses wrong repo/comment) or self-rearm loop (duplicate noisy comments on #3516 corrupting the 90-day chain).

**Brand-survival threshold:** single-user incident

CLO softening: No statutory clock (Art. 33 72h does not apply). Internal governance milestone. "Re-arm if missed" is acceptable degradation. Disclosure on miss: internal-only.

## Implementation Phases

### Phase 0: Inngest `ts` Scheduling Verification (GATE)

**Blocks all subsequent phases.** Two questions to resolve:

1. Does our Inngest tier support `ts` delays of ≥60 days? (TTL concern from CTO)
2. Does Inngest treat a future `ts` as "schedule delivery at this time" or "event occurred at this time"? (SDK docs say "occurred" — architecture-strategist flagged semantic ambiguity)

Verify via Inngest dashboard, support, or test send. If either answer is "no" → fall back: keep a minimal GHA workflow with cron `0 9 22 6 *` (T-7d) that sends the event with a 7-day delay. Handler shape is identical. Document the resolution in the PR body.

After Phase 0 resolves, **delete the losing path from this plan** before implementation begins.

### Phase 1: Implement + Register + Delete

**File to create:** `apps/web-platform/server/inngest/functions/oneshot-gdpr-gate-50d-eval.ts`

Pure-TS Octokit handler. ADR-033 invariants: I1 (Octokit reads inside step.run), I2 (operator-only, no BYOK), I3-I4 (N/A, no claude spawn), I5 (deterministic returns), I6 (`actor: "platform"` on re-arm event).

**step.run blocks (3):**

1. **`mint-installation-token`** — `generateInstallationToken(installationId, { minRemainingMs: 15 * 60 * 1000 })`. Same as `cron-strategy-review.ts:127-136`.

2. **`eval-and-post`** — the core eval logic:
   - **D3 date guard:** `new Date().toISOString().slice(0, 10) === event.data.expected_date`. Abort with `{ ok: false, reason: "date-guard" }` if false. Supports `event.data.date_override` for testing.
   - **Author check:** Octokit `GET /repos/{owner}/{repo}/issues/comments/{comment_id}` → assert `user.login === "deruelle"`. Abort if mismatch.
   - **Step (a) — telemetry count:** Octokit `GET /repos/{owner}/{repo}/contents/.claude/hooks/incidents.log` → Base64 decode → count occurrences of `cq-gdpr-gate-critical-finding`. If 404 → `telemetryCount = -1`.
   - **Step (b) — escaped PR count:** Octokit `GET /repos/{owner}/{repo}/pulls` with `state=closed`, paginate (10-page cap, 100/page), client-side filter: `merged_at >= "2026-05-10"` AND `merged_at <= event.data.expected_date`, then label filter `/compliance|gdpr|pii/i`. Count = `escapedCount`.
   - **Step (c) — outcome matrix:**
     - 0 escapes → `recommendation = "re-schedule-90d"`
     - 1–2 escapes → `recommendation = "re-schedule-90d-with-cases"`
     - ≥3 escapes → `recommendation = "wire-check-10-now"`
   - **Step (d) — post comment:** Octokit `POST /repos/{owner}/{repo}/issues/{issue_number}/comments` on #3516 with structured body.
   - Return `{ ok: true, telemetryCount, escapedCount, recommendation }`.

3. **`sentry-heartbeat`** — single POST to `https://${SENTRY_INGEST_DOMAIN}/api/${SENTRY_PROJECT_ID}/cron/oneshot-gdpr-gate-50d-eval/${SENTRY_PUBLIC_KEY}/?status=ok|error`. Same pattern as `cron-strategy-review.ts:559-605`. `reportSilentFallback` on every error path throughout the handler.

**After step 2, conditionally re-arm 90-day checkpoint** (outside step.run — direct `inngest.send`):

```ts
if (result.recommendation.startsWith("re-schedule")) {
  await inngest.send({
    name: "oneshot/gdpr-gate-50d-eval.fire",
    id: "gdpr-gate-90d-eval-2026-08-10-v1",
    ts: new Date("2026-08-10T09:00:00Z").getTime(),
    data: {
      issue: 3516,
      comment_id: 4415647777,
      expected_date: "2026-08-10",
      expectedAuthor: "deruelle",
    },
  });
}
```

**Registration shape:**

```ts
export const oneshotGdprGate50dEval = inngest.createFunction(
  {
    id: "oneshot-gdpr-gate-50d-eval",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  { event: "oneshot/gdpr-gate-50d-eval.fire" },
  handler,
);
```

**Files to edit in this phase:**

1. **`apps/web-platform/app/api/inngest/route.ts`** — add import + array entry (16th function).
2. **`.github/workflows/scheduled-gdpr-gate-preflight-eval-50d.yml`** — DELETE (`git rm`). Same commit per TR9 I-13 hygiene.

### Phase 2: Testing

1. **I2 auto-assertion:** Widen `cron-no-byok-lease-sweep.test.ts` glob from `"server/inngest/functions/cron-*.ts"` to `"server/inngest/functions/{cron,oneshot}-*.ts"`. Update test description to reflect widened scope.

2. **D3 date guard test:** Export handler. Call with mocked `step` and `event.data.expected_date = "2027-01-01"` (today ≠ expected) → assert `{ ok: false, reason: "date-guard" }`. Second case: `event.data.date_override = "2026-06-29"` + `event.data.expected_date = "2026-06-29"` → assert proceeds past D3.

3. **Author check test:** Mock Octokit returning comment with `user.login = "attacker"` → assert abort.

4. **Type-check:** `tsc --noEmit` passes.

## Files to Create

| File | Purpose |
|---|---|
| `apps/web-platform/server/inngest/functions/oneshot-gdpr-gate-50d-eval.ts` | Event-triggered one-shot handler (~200 LOC) |

## Files to Edit

| File | Change |
|---|---|
| `apps/web-platform/app/api/inngest/route.ts` | Add import + array entry |
| `apps/web-platform/test/server/cron-no-byok-lease-sweep.test.ts` | Widen glob to `{cron,oneshot}-*.ts` |

## Files to Delete

| File | Reason |
|---|---|
| `.github/workflows/scheduled-gdpr-gate-preflight-eval-50d.yml` | Replaced by Inngest function (TR9 I-13) |

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `tsc --noEmit` passes with no new errors
- [ ] AC2: `oneshot-gdpr-gate-50d-eval.ts` registered on `{ event: "oneshot/gdpr-gate-50d-eval.fire" }` — no `{ cron }` trigger
- [ ] AC3: `route.ts` imports and lists the function
- [ ] AC4: `.github/workflows/scheduled-gdpr-gate-preflight-eval-50d.yml` deleted
- [ ] AC5: D3 reads `event.data.expected_date`, not a hardcoded string. Unit test asserts abort on date mismatch.
- [ ] AC6: Author check asserts `user.login === "deruelle"`. Unit test asserts abort on mismatch.
- [ ] AC7: `cron-no-byok-lease-sweep.test.ts` glob widened to `{cron,oneshot}-*.ts` and passes
- [ ] AC8: `reportSilentFallback` called on every error path (D3 abort, author-check abort, Octokit failures)
- [ ] AC9: PR body contains arming runbook with `ts: 1782723600000` (2026-06-29T09:00Z) and Phase 0 resolution

### Post-merge (operator)

- [ ] AC10: Run arming command. Paste returned `event_id` into PR description. Automation: not feasible — one-time CLI invocation against prd Inngest.

## Open Code-Review Overlap

None.

## Domain Review

**Domains relevant:** Engineering, Legal, Product

### Engineering (CTO) — carry-forward from brainstorm

**Status:** reviewed
**Assessment:** Option (d) with manual CLI dispatch. `ts?: number` verified in SDK types. 50-day TTL as Phase 0 gate. No capability gaps.

### Legal (CLO) — carry-forward from brainstorm

**Status:** reviewed
**Assessment:** D5 simplified to author-check per plan review. No statutory deadline. GDPR-quiescent. Internal-only disclosure on miss.

### Product (CPO) — carry-forward from brainstorm

**Status:** reviewed
**Assessment:** Productize deferred (N=1). CPO sign-off covered by brainstorm triad (2026-05-25).

## Observability

```yaml
liveness_signal:
  what: Sentry heartbeat POST at end of handler
  cadence: once (2026-06-29 09:00 UTC)
  alert_target: Sentry breadcrumbs + reportSilentFallback on error
  configured_in: inline in oneshot-gdpr-gate-50d-eval.ts

error_reporting:
  destination: Sentry via reportSilentFallback on every error path
  fail_loud: yes (heartbeat status=error on any failure)

failure_modes:
  - mode: Event never fires (Inngest TTL expiry / arming failure)
    detection: Operator discovers via manual check of #3516 by July 7
    alert_route: No automated alert — acceptable degradation per CLO (internal governance, no statutory clock)
  - mode: D3 date guard rejects (wrong date)
    detection: reportSilentFallback with reason="date-guard"
    alert_route: Sentry → operator
  - mode: Author check rejects (unexpected comment author)
    detection: reportSilentFallback with reason="author-mismatch"
    alert_route: Sentry → operator
  - mode: Octokit failure (API rate limit, auth failure)
    detection: reportSilentFallback
    alert_route: Sentry → operator

logs:
  where: Inngest function logs + Sentry breadcrumbs
  retention: Inngest dashboard retention (account tier)

discoverability_test:
  command: "curl -sI https://api.github.com/repos/jikig-ai/soleur/issues/3516/comments | head -1"
  expected_output: "HTTP/2 200 (issue exists and accepts comments)"
```

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Inngest does not support 50-day `ts` delays | Phase 0 gate. Hybrid fallback: GHA T-7d → 7-day Inngest delay. |
| Event `id` dedupe window expires before fire | D3 date guard catches any re-fire at handler time. |
| `gh` CLI absent from production Docker | All GH ops use Octokit REST API. |
| No automated alert if event never fires | CLO: internal governance, no statutory clock. Operator checks #3516 by July 7. |

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| (a) GHA workflow curls `inn.gs/e` | Violates TR9 "no GHA cron". Kept as hybrid fallback only. |
| (b) Inngest recurring sender | Self-rearm on every cron tick. |
| (c) Cloudflare Worker | New infra. |
| Boot-time `inngest.send({ ts })` | Re-arms every deploy; dedupe window expires. |
| `cron_run_ledger` | Table deleted. Rejected by 4-of-5 reviewers. |
| Sentry TF cron monitor | Annual false-miss in 2027; manual cleanup. Heartbeat POST suffices. |
| Full D5 immutability pin | Over-defense for internal comment. Author check sufficient. |
| Ephemeral workspace (git clone) | ~40 LOC overhead for one `readFile`. Contents API is one call. |

## Sharp Edges

- Inngest `ts` field uses Unix timestamp in **milliseconds**. `new Date("2026-06-29T09:00:00Z").getTime()` = `1782723600000`. Verify before arming.
- D3 reads `event.data.expected_date` — arming payload MUST include this field. The 90-day re-arm sets `expected_date: "2026-08-10"`.
- `oneshot-*.ts` naming is new. The `{cron,oneshot}-*.ts` glob establishes the convention.
- `gh` CLI is absent from production Dockerfile. All handler GH operations use Octokit.
- Octokit `GET /pulls` does not support `merged_at` range filtering server-side. Must paginate + client-side filter. 10-page cap (1000 PRs) is defensive.
- At `brand_survival_threshold: single-user incident`, recommend `deepen-plan` or ultrathink before `/work` if not already invoked.

## Plan Review Applied [2026-05-25]

5-agent panel (DHH + Kieran + Code Simplicity + Architecture Strategist + Spec-Flow Analyzer).

**P0 fixes:** (1) Timestamp corrected `1751187600000` → `1782723600000`. (2) Re-arm `ts` no longer divides by 1000. (3) D3 parameterized via `event.data.expected_date`.

**Simplifications (both panels converged):** (4) Ephemeral workspace deleted → Contents API. (5) Sentry TF monitor deleted → heartbeat POST only. (6) D5 reduced to author-login check. (7) 90-day re-arm simplified: no recursive D5 pins, handler reuses original `comment_id`. (8) 5 phases collapsed to 3. (9) ACs cut from 17 to 10. (10) Hybrid fallback prose deferred to Phase 0 resolution.
