---
title: "obs: route account-delete.ts anonymise failure paths through Sentry.captureException"
issue: 4390
related: [4356, 4357, 3638, 3685, 3698]
pr: null
branch: feat-one-shot-4390-account-delete-sentry
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
classification: observability-hygiene
last_updated: 2026-05-25
---

# Plan: feat-one-shot-4390-account-delete-sentry

## Overview

`apps/web-platform/server/account-delete.ts` is the GDPR Article 17 erasure cascade. Every FATAL anonymise step (`3.82 anonymise_action_sends`, `3.83 anonymise_template_authorizations`, `3.84 anonymise_scope_grants`, `3.85 anonymise_tc_acceptances`, `3.90 anonymise_workspace_member_attestations`, `3.905 anonymise_workspace_member_removals`, `3.91 anonymise_workspace_members`, `3.92 anonymise_organization_membership`, `3.93 anonymise_workspace_member_actions`, and the terminal `auth.admin.deleteUser` at line 553) currently emits `log.error({userId, err}, "<msg>")` and returns a 500 to the user — **without** mirroring to Sentry. Pino routes the line to container stdout and (in prd) to Better Stack via the transport in `apps/web-platform/server/logger.ts`. Sentry stays silent.

Migrations 064/065/066 (PR #4357, closing #4356) made the cascade idempotent end-to-end so re-running is safe, but the observability gap remains: a future regression that broke any single anonymise RPC would page the on-call only via Better Stack — which is configured for uptime alerting, not Pino error severity. The fix is small and well-bounded: route every FATAL emit through `reportSilentFallback` (which writes pino AND `Sentry.captureException`, with `userId`→`userIdHash` pseudonymisation at the boundary per ADR-029 / #3685), and add Sentry breadcrumbs per stage so dashboard slicing keys off `feature` + `op` rather than free-text message strings.

**Approach selected:** Migrate the 10 FATAL `log.error` sites + the terminal `auth.admin.deleteUser` failure to `reportSilentFallback({ feature: "account-delete", op: "<stage-slug>", extra: { userId, ... }, message: "<original literal>" })`. The helper already exists at `apps/web-platform/server/observability.ts:138` and is the canonical primitive (40+ call-sites repo-wide). The `userId` field stays raw in the call-site arg (pino formatter rename hook + `hashExtraUserId` at the helper boundary together cover the pseudonymisation contract per ADR-029) — no new `hashUserId(userId)` calls are required.

**Why not direct `Sentry.captureException`:** The repo's canonical primitive is `reportSilentFallback`. Direct `Sentry.captureException` calls bypass `hashExtraUserId` (ADR-029 boundary) and force every caller to remember pseudonymisation. The two existing direct-`Sentry.captureException` sites in `apps/web-platform/server/` (`ws-handler.ts:693, 719`) are tracked as cleanup debt per learning `2026-05-12-plan-time-api-contract-verification-and-pipeline-via-package-json.md`; adding more would compound that debt.

**Why a brand-survival `single-user incident` threshold applies:** A regression in the cascade that breaks one anonymise RPC silently (Better Stack swallows it, no Sentry page) leaves PII residue past the Article 17 deadline (72-hour notifiability clock under Art. 33). That is a single-user incident class — one regulator complaint suffices. The framing matches PR #3685 (`single-user incident` for PA8 Sentry/pino residue after Art. 17 erasure) and PR #4213 PR-I (`single-user incident` for cascade ordering). CPO sign-off applies at plan time; `user-impact-reviewer` invoked at PR review time.

## User-Brand Impact

- **If this lands broken, the user experiences:** A user who requested Art. 17 erasure gets a generic 500 ("Account deletion failed. Please try again."), no Sentry alert fires, and the on-call does not see the failure until a Better Stack alarm hits a noisy threshold hours later. Erasure SLA breached invisibly.
- **If this leaks, the user's identity is exposed via:** Sentry `extra.userId` carrying the raw UUID. The pino formatter `formatters.log` hook (`apps/web-platform/server/logger.ts`) covers the pino mirror; `observability.ts:hashExtraUserId` covers the Sentry mirror. Both boundaries already shipped (#3685 / #3698); this plan only adds new emit sites that route through both — it does not bypass either.
- **Brand-survival threshold:** `single-user incident`

CPO sign-off required at plan time before `/work` begins. `user-impact-reviewer` will be invoked at PR review.

## Research Reconciliation — Spec vs. Codebase

| Spec / issue claim | Reality | Plan response |
|---|---|---|
| Issue lists steps 3.82 / 3.83 / 3.84 / 3.85 / **3.86** / 3.90 / 3.905 / 3.91 / 3.92 / 3.93 as FATAL | Step 3.86 (`anonymise_audit_github_token_use`) uses `log.warn` — the FK is `ON DELETE SET NULL`, so this step is **non-fatal by design** (header comment §3.86 explicitly says "the SET-NULL cascade will run anyway"). Lines 358, 364. | Mirror to Sentry at `warning` level via `warnSilentFallback` (not `reportSilentFallback`). Treat as a degraded-but-expected observation, not an error page. |
| Issue: "final auth-delete at line 519" | The terminal `auth.admin.deleteUser` failure is at **line 553** (line 519 in the issue body was a paraphrase; the file is 559 LoC). | Migrate `log.error({userId, err: deleteAuthError}, "Failed to delete auth record")` at line 553. |
| Issue: "No new direct `userId` emissions (lint #3698)" | #3698 is a CLOSED issue (PR landed); the pino `formatters.log` rename hook at `apps/web-platform/server/logger.ts:formatters.log` covers all top-level `userId` keys in pino emit, AND `observability.ts:hashExtraUserId` covers the Sentry mirror. **No new lint exists** — the contract is "use `reportSilentFallback` / `warnSilentFallback`, which pseudonymise at the boundary." | Keep `{ userId, err }` shape verbatim in the migrated calls; both pino and Sentry boundaries already strip `userId`→`userIdHash`. Do NOT add ad-hoc `hashUserId(userId)` calls at the new emit sites — that would duplicate the boundary transform and confuse future readers. The only site that already uses `hashUserId` explicitly (line 491, the orphan-org probe `log.info`) stays as-is. |
| Issue: "One Sentry breadcrumb + tag per stage" | The helper takes `feature` + `op` tags; Sentry has no separate "breadcrumb per emit" requirement beyond the tags. Breadcrumbs in `@sentry/nextjs` are typically auto-collected; explicit `Sentry.addBreadcrumb` calls in this file would be redundant. | Treat the "breadcrumb" language as semantic — use `op: "<stage-slug>"` per emit. The 11 distinct `op` values give the dashboard the slicing the issue asks for. |
| Issue: scope-out reference from PR #4357 plan §Risks | PR #4357 is MERGED (`gh pr view 4357` → MERGED 2026-05-25). The §Risks scope-out is the canonical pointer; no upstream-pending dependency. | Verified — this plan is the fold-in. |

## Research Insights

- **Canonical helper:** `apps/web-platform/server/observability.ts:138` (`reportSilentFallback`) + `:185` (`warnSilentFallback`). Both pseudonymise `extra.userId` → `userIdHash` at the emit boundary (`hashExtraUserId` → `renameUserIdToHash`). Wrapped in try/catch so a Sentry SDK failure cannot kill the cascade.
- **`message` carry-forward is load-bearing.** Learning `knowledge-base/project/learnings/2026-05-13-helper-migration-must-preserve-operator-dashboard-message-strings.md` documents that migrations to `reportSilentFallback` without an explicit `message: "<original literal>"` cause the helper to substitute `"account-delete silent fallback"` for every site — collapsing 11 distinct dashboard-keyed strings into one. **Every migrated emit MUST pass `message: "<original log.error/log.warn message verbatim>"`.**
- **Per-file inventory sweep already done.** All `log.error` (10 FATAL sites) + the auth-delete error site + the issue-cited `log.warn` at 3.86 are enumerated below. Co-located `log.warn` sites at 104 / 128 / 134 / 144 / 156 / 182 / 196 / 214 / 220 (the head-of-cascade non-fatal sites) are **explicitly scoped OUT** — they represent best-effort degraded paths where the cascade continues regardless; Sentry alerts on these would generate noise without actionability. Documented as a Scope-out below.
- **Existing `feature` tag namespaces** (grep of `apps/web-platform/server/*.ts`): `"accept-terms"`, `"agent-runner"`, `"cc-dispatcher"`, `"kb-share"`, `"stripe-webhook"`, etc. The natural slug for this file is `"account-delete"` (matches the `createChildLogger("account-delete")` value at line 8 — same vocabulary, no drift).
- **`op` slug list (11 distinct values, one per migrated site):**
  - `anonymise-action-sends` (line 241, 248)
  - `anonymise-template-authorizations` (line 272, 282)
  - `anonymise-scope-grants` (line 305, 312)
  - `anonymise-tc-acceptances` (line 331, 338)
  - `anonymise-audit-github-token-use` (line 358, 364 — `warnSilentFallback`)
  - `anonymise-workspace-member-attestations` (line 385, 392)
  - `anonymise-workspace-member-removals` (line 415, 422)
  - `anonymise-workspace-members` (line 441, 448)
  - `anonymise-organization-membership` (line 470, 505)
  - `anonymise-workspace-member-actions` (line 529, 536)
  - `auth-delete` (line 553)
- **Test mock pattern:** Existing account-delete cascade tests at `apps/web-platform/test/server/account-delete-*.test.ts` mock `@/server/logger`. They will need extension to mock `@sentry/nextjs` (`captureException`, `captureMessage`) — pattern from `apps/web-platform/test/api-accept-terms-ledger.test.ts:56` (`vi.mock("@sentry/nextjs", () => ({ withIsolationScope: (fn) => fn(), getCurrentScope: () => ({ setUser: vi.fn() }), captureException: vi.fn(), captureMessage: vi.fn() }))`).
- **All cited PR/issue numbers verified live.** #4356 CLOSED (parent issue); #4357 MERGED; #3638 CLOSED; #3685 MERGED; #3698 CLOSED; #4390 OPEN. No fabricated citations.
- **All cited AGENTS.md rule IDs verified ACTIVE in `AGENTS.core.md`.** `hr-observability-as-plan-quality-gate`, `hr-no-dashboard-eyeball-pull-data-yourself`, `hr-weigh-every-decision-against-target-user-impact`, `hr-write-boundary-sentinel-sweep-all-write-sites`. No retired-rule citations.
- **All cited learning files exist on disk.**
  - `knowledge-base/project/learnings/2026-05-13-helper-migration-must-preserve-operator-dashboard-message-strings.md` ✓ (helper migration `message:` carry-forward)
  - `knowledge-base/project/learnings/2026-05-12-centralized-at-helper-boundary-transforms-overclaim-in-acs-and-disclosures.md` ✓ (centralization scope-claim discipline)
  - `knowledge-base/project/plans/2026-05-12-feat-pseudonymize-client-userid-sentry-plan.md` ✓ (sibling pseudonymisation plan, pattern parity)

## Implementation Phases

### Phase 0 — Preconditions

- [ ] **0.1 Verify Sentry helper signatures.** `grep -nE "^export function (reportSilentFallback|warnSilentFallback)" apps/web-platform/server/observability.ts` returns the two function definitions. Confirms helper API is `(err, { feature, op, extra, message })` (no signature change since #3685).
- [ ] **0.2 Verify Sentry mock pattern exists in test fixtures.** `grep -l 'vi.mock("@sentry/nextjs"' apps/web-platform/test/ -r` returns ≥1 match (currently 5 — `api-accept-terms-ledger.test.ts`, `ws-handler.tc-mid-session.test.ts`, `ws-handler-cc-session-id-wiring.test.ts`, `context-injection.test.ts`, `agent-runner-kb-share-tools.test.ts`). Pattern is reusable.
- [ ] **0.3 Verify the issue-cited "step 3.86 FATAL" claim against source.** `sed -n '345,368p' apps/web-platform/server/account-delete.ts` shows `log.warn` (not `log.error`) at lines 358/364, and the header comment §3.86 explicitly states the step is non-fatal because the FK is `ON DELETE SET NULL`. The Research Reconciliation table above captures the divergence; this phase records the verification.
- [ ] **0.4 Verify pino formatter rename hook still covers `extra.userId`.** `grep -n "formatters\|renameUserIdToHash" apps/web-platform/server/logger.ts` returns the formatter wiring. Confirms the migrated `extra: { userId }` keys auto-pseudonymise on the pino side (ADR-029).

### Phase 1 — Tests First (TDD RED)

- [ ] **1.1 Extend each existing cascade test to assert Sentry mirror.** Three files:
  - `apps/web-platform/test/server/account-delete-template-authorizations-cascade.test.ts`
  - `apps/web-platform/test/server/account-delete-workspace-member-actions-cascade.test.ts`
  - `apps/web-platform/test/server/account-delete.cascade.integration.test.ts`

  For each test that simulates an RPC failure (an `mockRpc.mockResolvedValueOnce({ error: { ... } })` arm), add an assertion that `Sentry.captureException` was called once with:
  - First arg: an `Error` instance whose `.message` includes the RPC error message OR an object passed through the helper.
  - Second arg `.tags.feature === "account-delete"` and `.tags.op === "<stage-slug>"`.
  - Second arg `.extra` contains `userIdHash` (not `userId`) — proves the ADR-029 boundary is engaged.

- [ ] **1.2 Add Sentry mock to each of the three test files** following the pattern at `test/api-accept-terms-ledger.test.ts:56`:

  ```ts
  vi.mock("@sentry/nextjs", () => ({
    withIsolationScope: (fn: () => unknown) => fn(),
    getCurrentScope: () => ({ setUser: vi.fn() }),
    captureException: vi.fn(),
    captureMessage: vi.fn(),
  }));
  ```

- [ ] **1.3 Add a focused unit test** at `apps/web-platform/test/server/account-delete-sentry-mirror.test.ts` that exercises ALL 11 emit sites via parametrised cases:

  ```ts
  test.each([
    { stage: "anonymise-action-sends",                 rpc: "anonymise_action_sends" },
    { stage: "anonymise-template-authorizations",      rpc: "anonymise_template_authorizations" },
    { stage: "anonymise-scope-grants",                 rpc: "anonymise_scope_grants" },
    { stage: "anonymise-tc-acceptances",               rpc: "anonymise_tc_acceptances" },
    { stage: "anonymise-audit-github-token-use",       rpc: "anonymise_audit_github_token_use", warn: true },
    { stage: "anonymise-workspace-member-attestations", rpc: "anonymise_workspace_member_attestations" },
    { stage: "anonymise-workspace-member-removals",    rpc: "anonymise_workspace_member_removals" },
    { stage: "anonymise-workspace-members",            rpc: "anonymise_workspace_members" },
    { stage: "anonymise-organization-membership",      rpc: "anonymise_organization_membership" },
    { stage: "anonymise-workspace-member-actions",     rpc: "anonymise_workspace_member_actions" },
    { stage: "auth-delete",                            rpc: null /* failure on auth.admin.deleteUser */ },
  ])("emits Sentry capture at $stage with tag op=$stage and userIdHash in extra", async ({ stage, rpc, warn }) => { ... })
  ```

  Assertions: `Sentry.captureException` called exactly once, `.tags.feature === "account-delete"`, `.tags.op === stage`, `.extra.userIdHash` present, `.extra.userId` absent. For `warn: true` row, assert `.level === "warning"` and that the FATAL path does NOT short-circuit (cascade continues to auth-delete).

- [ ] **1.4 Confirm RED.** `cd apps/web-platform && bun test test/server/account-delete-sentry-mirror.test.ts` fails because `account-delete.ts` is not yet wired through the helper.

### Phase 2 — Implementation (GREEN)

- [ ] **2.1 Add helper imports** to `apps/web-platform/server/account-delete.ts`:

  ```ts
  import { hashUserId, reportSilentFallback, warnSilentFallback } from "@/server/observability";
  ```

  (Existing `hashUserId` import on line 6 widens to a multi-name import; no new file.)

- [ ] **2.2 Migrate each FATAL `log.error` pair** (the `if (anonXxxErr) {...} ` arm AND the `catch (err) {...}` arm) to `reportSilentFallback`. Carry forward the original message verbatim per the helper-migration learning. The `return { success: false, error: "Account deletion failed. Please try again." }` line stays untouched — only the emit changes.

  **Pattern (illustrative — exact strings preserved from existing source):**

  ```ts
  // 3.82 — FATAL on RPC error
  if (anonAsErr) {
    reportSilentFallback(
      anonAsErr instanceof Error ? anonAsErr : new Error(String(anonAsErr.message ?? anonAsErr)),
      {
        feature: "account-delete",
        op: "anonymise-action-sends",
        extra: { userId, err: anonAsErr },
        message: "anonymise_action_sends failed — aborting deletion to avoid FK-block",
      },
    );
    return { success: false, error: "Account deletion failed. Please try again." };
  }
  // 3.82 — FATAL on throw
  } catch (err) {
    reportSilentFallback(err, {
      feature: "account-delete",
      op: "anonymise-action-sends",
      extra: { userId },
      message: "anonymise_action_sends threw — aborting deletion to avoid FK-block",
    });
    return { success: false, error: "Account deletion failed. Please try again." };
  }
  ```

  Apply the same shape to:
  - 3.83 `anonymise-template-authorizations` (lines 272, 282)
  - 3.84 `anonymise-scope-grants` (lines 305, 312)
  - 3.85 `anonymise-tc-acceptances` (lines 331, 338)
  - 3.90 `anonymise-workspace-member-attestations` (lines 385, 392)
  - 3.905 `anonymise-workspace-member-removals` (lines 415, 422)
  - 3.91 `anonymise-workspace-members` (lines 441, 448)
  - 3.92 `anonymise-organization-membership` (lines 470, 505)
  - 3.93 `anonymise-workspace-member-actions` (lines 529, 536)

- [ ] **2.3 Migrate 3.86 `log.warn` pair** (non-FATAL — the FK is `ON DELETE SET NULL`) to `warnSilentFallback`:

  ```ts
  if (anonGhErr) {
    warnSilentFallback(
      anonGhErr instanceof Error ? anonGhErr : new Error(String(anonGhErr.message ?? anonGhErr)),
      {
        feature: "account-delete",
        op: "anonymise-audit-github-token-use",
        extra: { userId, err: anonGhErr },
        message: "anonymise_audit_github_token_use failed — relying on ON DELETE SET NULL cascade (non-fatal)",
      },
    );
  }
  ```

  Apply same shape to the catch arm at line 364. The cascade continues regardless.

- [ ] **2.4 Migrate the terminal `auth-delete` failure** at line 553:

  ```ts
  if (deleteAuthError) {
    reportSilentFallback(deleteAuthError, {
      feature: "account-delete",
      op: "auth-delete",
      extra: { userId, err: deleteAuthError },
      message: "Failed to delete auth record",
    });
    return { success: false, error: "Account deletion failed. Please try again." };
  }
  ```

- [ ] **2.5 Confirm GREEN.** `cd apps/web-platform && bun test test/server/account-delete*` — all four files pass. Plus `bun run typecheck` clean.

### Phase 3 — Cross-check & GREEN sweep

- [ ] **3.1 Grep-verify NO `log.error(` calls remain at FATAL sites.** `grep -n "log\.error" apps/web-platform/server/account-delete.ts` should return zero hits inside the migrated stages (3.82–3.93 + auth-delete). The head-of-cascade `log.warn` sites (104, 128, 134, 144, 156, 182, 196) stay — they are explicitly scoped out (best-effort, non-fatal).
- [ ] **3.2 Grep-verify NO direct `Sentry.captureException(` in account-delete.ts.** All Sentry routing must flow through the helper to preserve the ADR-029 boundary. Result: 0 hits.
- [ ] **3.3 Full test suite.** `cd apps/web-platform && bun run test` — no regressions.
- [ ] **3.4 Lint clean.** `cd apps/web-platform && bun run lint apps/web-platform/server/account-delete.ts apps/web-platform/test/server/account-delete*.ts`.

## Files to Edit

- `apps/web-platform/server/account-delete.ts` (single file change — 10 FATAL emit pairs + 1 non-fatal pair + 1 auth-delete = 21 emit lines total, plus import widening on line 6)
- `apps/web-platform/test/server/account-delete-template-authorizations-cascade.test.ts` (extend with Sentry mock + assertion)
- `apps/web-platform/test/server/account-delete-workspace-member-actions-cascade.test.ts` (extend with Sentry mock + assertion)
- `apps/web-platform/test/server/account-delete.cascade.integration.test.ts` (extend with Sentry mock + assertion)

## Files to Create

- `apps/web-platform/test/server/account-delete-sentry-mirror.test.ts` — new focused test with parametrised cases for ALL 11 stages

## Open Code-Review Overlap

None.

`gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json && jq -r --arg path "account-delete" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json` returns no matches as of plan-write time (verified during plan generation; `/work` will re-run for currency).

## Domain Review

**Domains relevant:** engineering (CTO)

### Engineering / Observability (CTO)

**Status:** reviewed (in-skill, single-domain plan)
**Assessment:** Pure observability migration of an existing GDPR-critical surface to the canonical helper. No new vendor, no new IaC surface, no new schema, no new public API. Risk surface is bounded to: (a) message-string drift (mitigated by explicit `message:` carry-forward per the 2026-05-13 learning), (b) ADR-029 boundary engagement (verified — helper engages `hashExtraUserId` on every `extra`), (c) test mock parity with existing patterns (5 prior `vi.mock("@sentry/nextjs", ...)` precedents). No CMO / CRO / CPO / CLO domain implications beyond the brand-survival threshold framing already captured. The `single-user incident` framing carries over from the parent cascade plan PR #4357 / PR #4213; CPO sign-off applies at plan time, `user-impact-reviewer` at PR review time.

Product/UX Gate: not relevant — zero user-facing surface change. The 500-on-erasure-failure response copy stays verbatim.

## Infrastructure (IaC)

**Domains relevant:** none

This is a pure-code change against an already-provisioned surface (web-platform server runtime). Sentry DSN is already wired via `SENTRY_DSN` (consumed by `@sentry/nextjs` at runtime). No new Terraform, no new Doppler keys, no new cron, no new vendor account. Skip silently per plan Phase 2.8.

## Observability

```yaml
liveness_signal:
  what: Sentry event count under tag feature=account-delete grouped by op
  cadence: per-erasure failure (event-driven, not periodic)
  alert_target: Sentry web-platform project — existing P0/P1 alert rules on captureException severity
  configured_in: apps/web-platform/server/observability.ts (reportSilentFallback / warnSilentFallback helpers, already wired to Sentry DSN env)

error_reporting:
  destination: Sentry web-platform via SENTRY_DSN (already configured); pino mirror to container stdout + Better Stack (existing logger.ts transport)
  fail_loud: Sentry captureException emits at level=error (or level=warning for the 3.86 step). HTTP response is 500 with body {success:false, error:"Account deletion failed. Please try again."} (unchanged from pre-PR baseline).

failure_modes:
  - mode: anonymise RPC failure (any of 3.82, 3.83, 3.84, 3.85, 3.90, 3.905, 3.91, 3.92, 3.93)
    detection: Sentry event with tag feature=account-delete + op=<stage-slug>, level=error
    alert_route: on-call via Sentry alert rule
  - mode: auth-delete failure after all anonymise steps succeeded
    detection: Sentry event with tag feature=account-delete + op=auth-delete, level=error
    alert_route: on-call via Sentry alert rule (high severity — user has half-deleted state requiring manual cascade rerun)
  - mode: anonymise_audit_github_token_use failure (non-fatal — FK is SET NULL, cascade continues)
    detection: Sentry event with tag feature=account-delete + op=anonymise-audit-github-token-use, level=warning
    alert_route: Sentry warning channel; no page (cascade continues to auth-delete; SET-NULL handles the FK)

logs:
  where: container stdout + Better Stack (existing pino transport in apps/web-platform/server/logger.ts)
  retention: Better Stack default (3-30 days depending on plan tier); Sentry default 30-90 days

discoverability_test:
  command: cd apps/web-platform && bun test test/server/account-delete-sentry-mirror.test.ts
  expected_output: "11 passed" — one passing parametrised case per migrated stage; assertion that Sentry.captureException was invoked with feature=account-delete and op=<stage-slug>, and that extra.userIdHash is present (extra.userId absent) on every case.
```

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** — `grep -nE "log\.(error|warn)" apps/web-platform/server/account-delete.ts | grep -cE "anonymise|auth-delete|Failed to delete auth"` returns 0. Every FATAL emit and the auth-delete emit routes through the helper. (Head-of-cascade `log.warn` at lines 104/128/134/144/156/182/196/220 stays — scope-out per Research Insights.)
- [ ] **AC2** — `grep -n "reportSilentFallback\|warnSilentFallback" apps/web-platform/server/account-delete.ts | wc -l` returns 21 (10 FATAL RPC arms × 2 [if-error + catch] + 1 non-fatal × 2 + 1 auth-delete = 21).
- [ ] **AC3** — `grep -n "feature: \"account-delete\"" apps/web-platform/server/account-delete.ts | wc -l` returns 21. Single feature tag across every emit.
- [ ] **AC4** — Each of the 11 `op` slugs appears at least once: `for op in anonymise-action-sends anonymise-template-authorizations anonymise-scope-grants anonymise-tc-acceptances anonymise-audit-github-token-use anonymise-workspace-member-attestations anonymise-workspace-member-removals anonymise-workspace-members anonymise-organization-membership anonymise-workspace-member-actions auth-delete; do grep -q "op: \"$op\"" apps/web-platform/server/account-delete.ts || echo "MISSING: $op"; done` returns no MISSING lines.
- [ ] **AC5** — `grep -n "message:" apps/web-platform/server/account-delete.ts` returns 21 lines — every emit carries an explicit `message:` string (no helper-default fallback, per the 2026-05-13 helper-migration learning).
- [ ] **AC6** — `grep -nE "Sentry\.(captureException|captureMessage)" apps/web-platform/server/account-delete.ts` returns 0. All Sentry routing flows through the helper (ADR-029 boundary preserved).
- [ ] **AC7** — `cd apps/web-platform && bun test test/server/account-delete-sentry-mirror.test.ts` passes (11 parametrised cases).
- [ ] **AC8** — `cd apps/web-platform && bun test test/server/account-delete*` passes (all four cascade test files green, no regressions).
- [ ] **AC9** — `cd apps/web-platform && bun run typecheck` clean.
- [ ] **AC10** — `cd apps/web-platform && bun run lint apps/web-platform/server/account-delete.ts apps/web-platform/test/server/account-delete*.ts` clean.
- [ ] **AC11** — PR body contains `Closes #4390` (auto-closes the observability gap issue at merge — no post-merge operator action is required to make the AC true).

### Post-merge (operator)

(None — no migration apply, no Doppler write, no infra change. The deploy completes on merge via the existing `web-platform-release.yml` pipeline.)

## Test Scenarios

Derived from acceptance criteria:

- **Given** an erasure request, **when** `anonymise_action_sends` RPC returns `{error: {...}}`, **then** `Sentry.captureException` is called once with `tags.feature="account-delete"`, `tags.op="anonymise-action-sends"`, `extra.userIdHash` present, `extra.userId` absent, and the cascade short-circuits with `{success:false, error:"Account deletion failed. Please try again."}`.
- **Given** an erasure request, **when** `anonymise_audit_github_token_use` RPC returns `{error: {...}}`, **then** `Sentry.captureException` is called once at `level: "warning"` (not `"error"`) and the cascade **continues** to step 3.90 (RESTRICT FK is satisfied by SET NULL cascade).
- **Given** an erasure request where every anonymise step succeeds, **when** `auth.admin.deleteUser` returns `{error: {...}}`, **then** `Sentry.captureException` is called once with `tags.op="auth-delete"` and the response is the same 500 the pre-PR baseline produced.
- **Given** an erasure request where every step succeeds, **when** `deleteAccount` returns `{success:true}`, **then** `Sentry.captureException` was **never** called and `Sentry.captureMessage` was **never** called (no false-positive emissions on the happy path).

## Non-Goals / Out of Scope

- **Head-of-cascade non-fatal `log.warn` sites** (lines 104, 128, 134, 144, 156, 182, 196 — the `getUserById` warn, `abort-dsar-jobs`, `abortAllUserSessions`, `deleteWorkspace`, attachment-purge, dsar-exports-purge, `anonymise_dsar_export_audit_pii`). These are best-effort steps whose failure does NOT block the cascade and does NOT block GDPR Art. 17. Mirroring them to Sentry would produce noise without actionability (e.g., `deleteWorkspace` failing on a workspace that was already cleaned up by a janitor is normal). If a future PR proves operational value of mirroring any of these, it can be added incrementally — out of scope here.
- **Backfilling Sentry alerts.** The deploy pipeline already ships Sentry config; no new alert rule needs creation in this PR. Operator may add an alert rule in the Sentry UI keyed off `feature:account-delete` after merge — this is not an AC of this PR.
- **`hashUserId(userId)`-on-the-call-site refactor.** ADR-029 explicitly says rename-at-boundary. The helper layer is the boundary. Adding `hashUserId()` to every `extra:` arg would duplicate the transform and confuse future readers (which is the canonical site — call vs helper?). The orphan-org probe at line 491 stays as the single exception (it's a `log.info` not routed through `reportSilentFallback` because it's not an error path).
- **Direct-bypass sentinel sweep.** Per learning `2026-05-12-centralized-at-helper-boundary-transforms-overclaim-in-acs-and-disclosures.md` the centralization claim must not over-scope. This plan asserts the new emits route through the helper boundary, NOT that all Sentry emissions repo-wide do. The pre-existing direct `Sentry.captureException` sites in `ws-handler.ts:693, 719` remain as known debt tracked outside this scope.

## Risks

1. **Sentry SDK mock parity drift.** If a test mock omits one of the four Sentry primitives (`captureException`, `captureMessage`, `withIsolationScope`, `getCurrentScope`) the helper's defensive `typeof Sentry.captureException === "function"` check will skip the Sentry path silently and the test assertion will fail with "called 0 times". Mitigation: copy the canonical mock pattern from `test/api-accept-terms-ledger.test.ts:56` verbatim — all four primitives present.
2. **Helper `message:` default substitution.** If any of the 21 migrated emits drops the `message:` field, the helper substitutes `"account-delete silent fallback"` and collapses 11 distinct dashboard-keyed strings into one. Mitigation: AC5 grep-asserts `message:` count = 21.
3. **`level: "warning"` for step 3.86.** The non-fatal step must use `warnSilentFallback` (level=warning), not `reportSilentFallback` (level=error). A drift here would page on-call for a non-actionable cascade. Mitigation: explicit Phase 2.3 + the parametrised test in Phase 1.3 (`warn: true` row asserts `.level === "warning"`).
4. **Sentry retention vs Art. 33 notifiability.** Sentry default retention (30-90d) is shorter than the indefinite Art. 33(5) breach-documentation requirement. This is the existing PA8 / D-durable-audit-log gap, NOT introduced by this PR. The Better Stack pino mirror retains for the configured pino transport window. Out of scope.
5. **Cascade re-run safety.** All 10 anonymise RPCs are idempotent (header comments §3.82–§3.93 explicitly assert this; migrations 064/065/066 made the cascade idempotent end-to-end). A Sentry alert that pages on-call → operator re-runs the cascade → safe. Risk is "operator forgets the cascade is idempotent and treats the 500 as terminal." Mitigation: the `message:` strings (carried forward verbatim) all explicitly say "aborting deletion" and the cascade-comment block at line 49-93 documents recoverability. No new wording introduced.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Self-check at plan-write time: section present, threshold `single-user incident`, both vector lines populated, CPO sign-off declared via frontmatter `requires_cpo_signoff: true`. ✓)
- The `op` slug list MUST match the test parametrisation list 1:1. If a future PR adds a new cascade step (e.g., a new anonymise RPC at step 3.94), the parametrised test in `account-delete-sentry-mirror.test.ts` is the single source of truth — extend it OR the new step will ship without Sentry coverage. Add a Phase 0 task to that future plan: `grep -c "test.each" apps/web-platform/test/server/account-delete-sentry-mirror.test.ts` → should equal `grep -cE "(reportSilentFallback|warnSilentFallback)" apps/web-platform/server/account-delete.ts / 2`. Mismatch = drift.
- `bun test` filter behavior: `bun test test/server/account-delete-sentry-mirror.test.ts` works because `apps/web-platform/bunfig.toml` does NOT set `pathIgnorePatterns = ["**"]` (verified at plan-write — `cat apps/web-platform/bunfig.toml | grep -c pathIgnorePatterns` returned 0). If a future bunfig change introduces the pattern, the AC7 verification command must switch to `vitest run` per the bunfig defense-in-depth Sharp Edge.

## References

- Issue: #4390
- Parent cascade PR: #4357 (MERGED) — landed mig 064/065/066 + cascade hardening; this issue is the residual observability gap
- Parent cascade issue: #4356 (CLOSED)
- ADR-029: `knowledge-base/engineering/architecture/decisions/ADR-029-rename-at-boundary-userid-pseudonymisation.md` (rename-at-boundary contract)
- Sibling pseudonymisation plan: `knowledge-base/project/plans/2026-05-12-feat-pseudonymize-client-userid-sentry-plan.md` (#3696)
- Helper-migration learning: `knowledge-base/project/learnings/2026-05-13-helper-migration-must-preserve-operator-dashboard-message-strings.md`
- Centralization-scope learning: `knowledge-base/project/learnings/2026-05-12-centralized-at-helper-boundary-transforms-overclaim-in-acs-and-disclosures.md`
- AGENTS.md rules applied: `hr-observability-as-plan-quality-gate`, `hr-no-dashboard-eyeball-pull-data-yourself`, `hr-weigh-every-decision-against-target-user-impact`, `hr-write-boundary-sentinel-sweep-all-write-sites`
