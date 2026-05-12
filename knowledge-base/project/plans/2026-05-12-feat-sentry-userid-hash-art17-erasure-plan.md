---
title: "feat: pepper-hash userId in Sentry emit + Art. 30 PA8 update"
issue: 3638
related: [3603, 3623, 3649, 3686]
pr: 3685
branch: feat-sentry-userid-hash-art17-3638
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
classification: security-hygiene
last_updated: 2026-05-12
---

# Plan: feat-sentry-userid-hash-art17-3638

## Overview

`reportSilentFallback`, `warnSilentFallback`, `mirrorWithDebounce`, and `mirrorP0Deduped` (in `apps/web-platform/server/observability.ts`) forward raw `userId` (and sometimes `conversationId`) to Sentry `extra` AND to pino structured log output. Under GDPR Art. 4(1) these are personal-data identifiers. The PR-A2 #3603 security-sentinel review flagged this as H6/H7. Two additional `Sentry.captureMessage` sites in `ws-handler.ts` (lines 693, 719) bypass the observability helper and also forward raw `userId`.

This plan pseudonymizes `userId` at the emit boundary (HMAC-SHA256 + Doppler pepper, fail-closed `"pepper_unset"` sentinel if pepper missing), keeps raw `userId` only in the in-process dedup map, updates Art. 30(1) PA8 to disclose the pseudonymization posture, and migrates the two ws-handler direct-Sentry sites to `warnSilentFallback`.

**Approach selected during brainstorm + plan-time pivot:** Track A (pepper-hash) + retention-only Art. 17 posture. Active purge dropped after API verification: Sentry bulk-DELETE accepts only `id` lists (no tag query); Better Stack has no documented log-deletion API. Better Stack is **only** an uptime monitor on `/health` (no pino transport in `package.json` — verified). Pseudonymous identifiers + documented retention is the CLO-defensible posture under Recital 26.

**Deferred (separate issue):** #3686 — `security_events` durable audit-log table for Art. 33(5) 6y retention.

## Research Insights

- **HMAC pattern to adopt** (`apps/web-platform/lib/supabase/tenant.ts:33,179`): `createHmac("sha256", secret).update(input).digest("hex")`. Full 64-char hex digest fits well within Sentry's 200-char tag-value limit; no truncation needed.
- **No prior server-side Sentry REST in TS.** Only bash scripts (`apps/web-platform/scripts/configure-sentry-alerts.sh`). Retention-only posture means no new Sentry REST client needed in this PR.
- **pino does NOT ship to Better Stack.** `apps/web-platform/package.json` has only `pino` + `pino-pretty` — no `pino-better-stack`, `pino-logtail`, or `@logtail/*` dependencies. PA8 already correctly states "pino stdout never leaves Hetzner Finland." Better Stack is the uptime monitor on `/health` (no PII in that surface). This PR makes NO Better Stack changes; the brainstorm's "pino → Better Stack pipeline" framing was a wrong assumption.
- **Doppler secret naming** (`apps/web-platform/next.config.ts:56-58`): `SENTRY_*` UPPER_SNAKE. New secret: `SENTRY_USERID_PEPPER`. `SENTRY_USERID_PEPPER_PREVIOUS` is **not** added in this PR (no rotation scheduled yet — defer to the future rotation PR).
- **Test runner**: `vitest` (`test: "vitest"`, `test:ci: "vitest run"`). Co-locate new tests under `apps/web-platform/test/`.
- **Sensitive-keys allowlist** (`apps/web-platform/server/sensitive-keys.ts`): `userId` is not redacted (correctly — it's an identifier, not a credential). Do not add it. Pseudonymization handles the disclosure concern directly.
- **PA8 already exists** (`knowledge-base/legal/article-30-register.md:151-163`). This PR updates the `(c) Categories of personal data` and `(f) Retention` rows only. Recipients and vendor table are unchanged — Sentry is already listed; Better Stack is correctly absent from the data-recipient surface.

### Verifying-claims-against-codebase findings

- **Sentry bulk-DELETE endpoint** (verified via Sentry docs `bulk-remove-a-list-of-issues`): only accepts `id=N&id=N&…`. **"Only queries by 'id' are accepted."** Active purge-by-tag is impossible in one call. Retention-only posture is correct.
- **Better Stack log-delete API** (verified via Better Stack docs `/docs/logs/api/`): not documented. Even if it existed, no pino-Better Stack pipeline exists in this codebase.
- **`reportSilentFallback` call sites**: 40+ production sites. Centralizing the hash transform inside the helper avoids touching 40 call sites.
- **`warnSilentFallback` call sites**: exists at `observability.ts:123`. Identical shape. Plan must apply identical transform (originally missed in plan v1 — `warnSilentFallback`, not `reportSilentInfoFallback`).
- **Direct `Sentry.captureMessage` with `userId` in `extra`**: `ws-handler.ts:693` (createConversation 23505 fallback — active_workflow divergence) and `ws-handler.ts:719` (createConversation 23505 fallback — context_path divergence). Both bypass `reportSilentFallback`. Migrate to `warnSilentFallback` in Phase 2.6.
- **`Sentry.captureException(err)` no-extras sites**: `agent-runner.ts:2147, 2322` and multiple `ws-handler.ts` lines pass only an error, no extras. Safe — nothing to hash.
- **`lib/client-observability.ts`**: parallel client-side helper. Cannot share a server-only pepper (client bundles must never contain peppers). Out of scope for this PR — file follow-up.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (from spec.md) | Codebase reality (verified at plan time) | Plan response |
|---|---|---|
| Spec FR4: `DELETE /api/0/organizations/{slug}/issues/?query=userIdHash:<hash>` | Sentry bulk-DELETE accepts only `id=N` list; no tag-query parameter. | **Drop FR4.** Retention-only posture documented in PA8 (Recital 26). |
| Spec FR5: Better Stack log-purge job on `userId` | (a) No documented Better Stack log-delete API. (b) No pino-Better Stack transport in the codebase. | **Drop FR5.** Better Stack is uptime-monitor only; not a data recipient for PA8. |
| Spec TR3: `SENTRY_ERASURE_TOKEN` Doppler secret | No active erasure → no token needed. | **Drop TR3.** |
| Spec TR4: research Better Stack purge API | Verified at plan time: API doesn't exist AND we don't ship logs there. | **Resolved.** |
| Spec FR6: PA8 covers Sentry pseudonymous + Better Stack purge | Better Stack is not a PA8 recipient. PA8 update narrows to Sentry-only pseudonymization disclosure + pino-on-Hetzner clarification. | **Narrow FR6.** |
| Plan v1: pepper rotation runbook + `PEPPER_PREVIOUS` env var | YAGNI — no rotation scheduled; helper can take an optional pepper arg so operator-side lookup works without env-var ceremony. | **Drop runbook + env var. Parameterize helper.** |
| Plan v1: Better Stack to vendor table | Better Stack is not a data processor for PA8. | **Drop vendor row.** |
| Plan v1: missed `warnSilentFallback` + 2 direct ws-handler Sentry sites | Plan-review caught both. | **Add Phase 2.1.5 + 2.6.** |
| All other spec FRs (FR1, FR2, FR3, FR7) and TRs (TR1, TR2, TR5, TR6) | Confirmed implementable. | Carry forward. |

## Files to Edit

- `apps/web-platform/server/observability.ts` — add `hashUserId(userId, pepper?)` exported helper + boot-time pepper-missing warning; apply transform inside `reportSilentFallback` (line 82-117) AND `warnSilentFallback` (line 123-149); hash explicitly in `mirrorP0Deduped` (line 322-357). `mirrorWithDebounce` inherits via `reportSilentFallback`.
- `apps/web-platform/server/ws-handler.ts` — migrate two direct `Sentry.captureMessage` sites (lines ~693 and ~719) to `warnSilentFallback({ feature: "ws-handler", op: "create-conversation-23505-fallback-<variant>", extra: { conversationId, ..., userId }, message: <existing message> })`. The helper will hash `userId` on emit.
- `apps/web-platform/test/observability.test.ts` — update existing tests (lines 35, 52, 72, 96-100) that assert raw `userId` in Sentry extras to assert `userIdHash`. Add new tests per Phase 3.
- `knowledge-base/legal/article-30-register.md` — update PA8 row `(c) Categories of personal data` (line 157) to document HMAC-SHA256 pseudonymization with server-side pepper (Recital 26); update PA8 row `(f) Retention` (line 162) to clarify pseudonymous + retention satisfies Art. 17 for both Sentry and pino-on-Hetzner; bump `last_reviewed` frontmatter to merge date.

## Files to Create

None.

## Open Code-Review Overlap

3 open code-review issues touch files in this plan:

- **#3638** (this work) — closes.
- **#3243** — *arch: decompose cc-dispatcher.ts into focused modules*. Disposition: **acknowledge.** No structural cc-dispatcher refactor here.
- **#3242** — *review: tool_use WS event lacks raw name field*. Disposition: **acknowledge.** Unrelated concern.

Zero overlap on `observability.ts` (beyond #3638) or `article-30-register.md`. The two ws-handler.ts edits at lines 693/719 are unique to this PR.

## User-Brand Impact

**If this lands broken, the user experiences:** silent Sentry emit failure on a breach-attempt event when their pepper is misconfigured at boot. Mitigation: fail-closed emits the `"pepper_unset"` sentinel + Sentry fatal-tagged event, so operator visibility never drops below the pre-PR baseline.

**If this leaks, the user's data is exposed via:** raw `userId` in pino on Hetzner stdout (EU-only) + Sentry `extra` (DE region, 30-90d retention). A user invoking GDPR Art. 17 erasure today gets DB cascade but their identifier persists in both surfaces until retention expires. This PR converts those identifiers to HMAC-SHA256 pseudonymous hashes (Recital 26): the controller cannot re-identify from a hash alone without the Doppler-held pepper, satisfying Art. 17's erasure obligation when combined with retention expiry.

**Brand-survival threshold:** `single-user incident` (carried forward from brainstorm Phase 0.1).

**Why:** Single-user PII residual in Sentry/Hetzner after account deletion is a documented compliance failure with ICO/CNIL complaint risk and brand-trust breach for that one user.

**How to apply:** plan-time CPO sign-off recorded in Domain Review; `user-impact-reviewer` runs at PR-review time to enumerate failure modes against the diff.

## Implementation Phases

### Phase 1 — HMAC helper

In `apps/web-platform/server/observability.ts`, immediately after the existing imports (after `import { createChildLogger } from "./logger"`), add:

```ts
import { createHmac } from "node:crypto";

const SENTRY_USERID_PEPPER = process.env.SENTRY_USERID_PEPPER;

// One-shot boot warning so operators can spot misconfigured pepper.
if (!SENTRY_USERID_PEPPER) {
  // eslint-disable-next-line no-console -- intentional one-shot boot warning
  console.warn(
    "[observability] SENTRY_USERID_PEPPER not set — userId will emit as 'pepper_unset' sentinel (fail-closed pseudonymization).",
  );
}

/**
 * Pseudonymize a user identifier for Sentry / pino emission.
 *
 * - HMAC-SHA256, full 64-hex digest (fits Sentry's ~200-char tag-value limit).
 * - Returns `"pepper_unset"` sentinel when pepper is absent: pre-PR baseline
 *   shipped raw userId; fail-closed sentinel preserves operator visibility
 *   without leaking PII. The sentinel collides across all users by design
 *   (surfaced via boot warning above) so a real degraded mode is detectable.
 * - Optional `pepper` arg lets operator-side hash-lookup scripts compute
 *   prior-pepper hashes during a future rotation without re-engineering
 *   this module (no `SENTRY_USERID_PEPPER_PREVIOUS` env var loaded here —
 *   that env var will be added the day a rotation is scheduled).
 */
export function hashUserId(userId: string, pepper = SENTRY_USERID_PEPPER): string {
  if (!pepper) return "pepper_unset";
  return createHmac("sha256", pepper).update(userId).digest("hex");
}
```

### Phase 2 — Apply transform at emit boundaries

**2.1 — `reportSilentFallback` (line 82-117).** Inside the function, before any `logger.error` / `Sentry.captureException` / `Sentry.captureMessage` call, transform `extra`:

```ts
// Renames `userId` → `userIdHash` so operators reading Sentry/Better Stack/pino
// see explicit pseudonymization signal, not a value-only swap. Centralized
// here so 40+ call sites continue to pass raw `userId` unchanged.
const transformedExtra =
  extra && typeof extra === "object" && "userId" in extra
    ? (() => {
        const { userId: rawUserId, ...rest } = extra as { userId?: unknown } & Record<string, unknown>;
        return { ...rest, userIdHash: hashUserId(String(rawUserId ?? "")) };
      })()
    : extra;
```

Replace every `extra`/`...extra` reference inside the function body with `transformedExtra` (logger call, Sentry calls).

**2.1.5 — `warnSilentFallback` (line 123-149).** Apply the identical `transformedExtra` transformation. Same shape as 2.1; same replacement of `extra` references inside the function body.

**2.2 — `mirrorWithDebounce` (line 265-273).** No change required. Delegates to `reportSilentFallback`, which now hashes internally. Dedup key at line 271 stays raw (`${userId}:${errorClass}`) — in-process, no PII at rest.

**2.3 — `mirrorP0Deduped` (line 322-357).** Hash once, apply to both pino and Sentry emit, preserving the existing typeof-guard + try/catch envelope:

```ts
const userIdHash = hashUserId(ctx.userId);

logger.error(
  { err, op: ctx.op, userIdHash, conversationId: ctx.conversationId },
  `p0 deduped mirror: ${ctx.op}`,
);

try {
  if (typeof Sentry.captureException === "function") {
    Sentry.captureException(err, {
      level: "fatal",
      tags: { op: ctx.op, scope: "p0_deduped", userIdHash },
      extra: {
        op: ctx.op,
        userIdHash,
        conversationId: ctx.conversationId,
        severity: "breach_attempt",
        first_seen_at: new Date(now).toISOString(),
      },
    });
  }
} catch {
  // Sentry namespace partially shimmed (dev-server bundle) — pino is the
  // durable signal regardless.
}
```

Dedup-map key at line 326 stays raw — in-process, no PII at rest.

**2.6 — Migrate direct ws-handler Sentry sites.** In `apps/web-platform/server/ws-handler.ts`:

- Line ~693 (`Sentry.captureMessage("createConversation 23505 fallback: activeWorkflow diverged …", { level: "warning", extra: { conversationId, existingWorkflow, intendedWorkflow, userId } })`) → migrate to:

  ```ts
  warnSilentFallback(new Error("createConversation 23505 fallback: activeWorkflow diverged — first-writer-wins"), {
    feature: "create-conversation",
    op: "23505-fallback-active-workflow",
    extra: { conversationId, existingWorkflow, intendedWorkflow, userId },
  });
  ```

- Line ~719 (`Sentry.captureMessage("createConversation 23505 fallback: context_path diverged …", { level: "warning", extra: { conversationId, existingContextPath, intendedContextPath, userId } })`) → migrate to:

  ```ts
  warnSilentFallback(new Error("createConversation 23505 fallback: context_path diverged — invariant assumed unreachable today"), {
    feature: "create-conversation",
    op: "23505-fallback-context-path",
    extra: { conversationId, existingContextPath, intendedContextPath, userId },
  });
  ```

Both now flow through the hash transform in 2.1.5. Add `import { warnSilentFallback } from "@/server/observability";` if not already present.

**2.7 — Out-of-scope: `lib/client-observability.ts`.** This client-side helper cannot share the server pepper (no peppers in client bundles). Filing a follow-up issue is part of AC5; the actual change ships in a separate PR (likely strips `userId` client-side or computes a per-session ephemeral identifier).

### Phase 3 — Tests

In `apps/web-platform/test/observability.test.ts`:

**3.1 — Update existing tests** (lines 35, 52, 72, 96-100) to assert `userIdHash` in emitted Sentry payloads and **not** `userId`. Use `vi.stubEnv("SENTRY_USERID_PEPPER", "test-pepper")` for determinism.

**3.2 — Helper-level tests** for `hashUserId`:
- Deterministic for fixed pepper + input.
- Distinct inputs → distinct hashes (1000-iteration smoke).
- Returns `"pepper_unset"` when `SENTRY_USERID_PEPPER` is unset AND no `pepper` arg is passed.
- Returns the prior hash when `pepper` arg is passed explicitly (operator-side lookup contract).

**3.3 — Emit-shape tests** for `reportSilentFallback`, `warnSilentFallback`, and `mirrorP0Deduped`:
- No raw `userId` key appears in Sentry `extra` or `tags`.
- `userIdHash` is present and matches `hashUserId(rawUserId, "test-pepper")`.
- Pino mock receives `{ userIdHash, ... }`, never `{ userId, ... }`.

**3.4 — Pepper-unset fail-closed** — assert all three functions emit `userIdHash: "pepper_unset"` and continue firing without throw when the pepper is unset.

**3.5 — Dedup invariance** — two `mirrorP0Deduped` calls with the same raw `userId` still dedupe even if the in-process pepper differs across the calls (sanity: dedup keys raw `userId`, not the hash).

**3.6 — ws-handler regression** — if `cc-dispatcher.test.ts` or `ws-handler.test.ts` has a covering test for the 23505 fallback paths, update its assertions to expect `userIdHash`. If no test covers those code paths, file a follow-up rather than expanding scope.

Run with `pnpm --filter web-platform vitest run` (or the project's canonical CI form).

### Phase 4 — Article 30 PA8 update

In `knowledge-base/legal/article-30-register.md`:

**4.1 — PA8 `(c) Categories of personal data`** (line 157). Replace the existing line text with:

> (i) **Sentry:** error messages and stack traces — may incidentally include `user_id`-derived fields; user identifiers are HMAC-SHA256-pseudonymized at the emit boundary (Recital 26 — controller cannot re-identify from the hash without the server-side pepper held in Doppler, not shared with the processor). (ii) **pino stdout (Hetzner-resident, EU-only):** structured app logs — `user_id` likewise emitted as HMAC-SHA256-pseudonymized `userIdHash`. (iii) **cc-dispatcher P0 mirrors (`mirrorP0Deduped` cross-tenant + W4-orphan paths) and `reportSilentFallback`/`warnSilentFallback`:** `userIdHash` (pseudonymous identifier), `conversationId`, `first_observed_at` ISO timestamp — minimised to identifiers + clock anchor.

**4.2 — PA8 `(f) Retention`** (line 162). Append a sentence:

> Note on Art. 17 (erasure): the cc-dispatcher mirror and silent-fallback emissions carry `userIdHash` (pseudonymous under GDPR Recital 26). Sentry and Hetzner cannot re-identify the data subject without the Doppler-held server pepper. On user-account deletion, the hashed identifier is allowed to age out per processor retention; no active processor-side erasure call is required.

**4.3 — `last_reviewed` frontmatter** — bump to today's date when the edit lands.

No recipient list change. No vendor table change. (Better Stack remains correctly absent from PA8 — uptime-only.)

### Phase 5 — Doppler secret provisioning

**5.1 — Add `SENTRY_USERID_PEPPER` to Doppler.** Distinct values per environment (`dev`, `prd`) per `hr-dev-prd-distinct-supabase-projects` spirit. Generate via `openssl rand -hex 32` and `doppler secrets set SENTRY_USERID_PEPPER -p soleur -c <config>`. Do NOT paste via the conversation `!`-prefix mechanism (`hr-never-paste-secrets-via-bang-prefix`).

No `_PREVIOUS` slot in this PR — added the day a rotation is scheduled.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1.** `hashUserId(userId, pepper?)` is exported from `apps/web-platform/server/observability.ts` with the Phase 1 contract (deterministic, fail-closed sentinel, optional pepper arg).
- [ ] **AC2.** All four mirror functions (`reportSilentFallback`, `warnSilentFallback`, `mirrorWithDebounce` via inheritance, `mirrorP0Deduped`) AND the two migrated `ws-handler.ts` sites emit `userIdHash` (never raw `userId`) in Sentry `extra`/`tags` AND pino structured log shapes. Grep gate: `rg "(extra|tags):\s*\{[^}]*\buserId\b" apps/web-platform/server/` returns no production-code matches (test fixtures excluded).
- [ ] **AC3.** Fail-closed: with `SENTRY_USERID_PEPPER` unset, every emit replaces userId with `"pepper_unset"` sentinel and continues firing. Boot-time `console.warn` fires exactly once at module init.
- [ ] **AC4.** Vitest suite for `apps/web-platform/test/observability.test.ts` passes including the new Phase 3 tests. `cc-dispatcher.test.ts` T-W4-orphan regression still passes against the new emit shape.
- [ ] **AC5.** PA8 in `article-30-register.md` is updated per Phase 4.1-4.3 with `last_reviewed` bumped. A follow-up issue is filed for `lib/client-observability.ts` pseudonymization (out-of-scope here; client cannot share server pepper).
- [ ] **AC6.** CPO sign-off recorded in PR body (`requires_cpo_signoff: true` in frontmatter). `user-impact-reviewer` runs at PR review and verifies User-Brand Impact section against the diff.
- [ ] **AC7.** `dev` Doppler `SENTRY_USERID_PEPPER` set to a non-empty value (verified via `doppler secrets get SENTRY_USERID_PEPPER -p soleur -c dev --plain`). `prd` may be set at merge or as an operator follow-through (see AC-PM1).

### Post-merge (operator)

- [ ] **AC-PM1.** `prd` Doppler `SENTRY_USERID_PEPPER` set + Vercel deployment rolled. Verify by tailing prd container logs for the absence of the `pepper_unset` warning line.

## Risks & Open Questions

- **R1 — Hidden behavior in `reportSilentFallback` transform.** The `userId → userIdHash` rename is centralized to avoid touching 40+ call sites, but it's invisible to call-site readers. Mitigation: inline body comment in Phase 2.1 explains the rename next to the transform (operators reading the function definition see it before they need it).
- **R2 — Future pepper rotation.** When the first rotation is scheduled, add `SENTRY_USERID_PEPPER_PREVIOUS` env var + an operator-side hash-lookup script using `hashUserId(uid, prevPepper)`. No work needed in this PR — the parameterized helper supports it.
- **R3 — `lib/client-observability.ts` out-of-scope.** Client-side `userId` in Sentry remains raw until a separate PR addresses it (cannot share server pepper). Follow-up issue filed in AC5.
- **OQ1 — `conversationId` pseudonymization.** Out of scope; brainstorm scoped to `userId` only. File follow-up if compliance review identifies it as a gap.

## Domain Review

**Domains relevant:** Legal, Engineering, Product (user-brand-critical triad carried forward from brainstorm).

### Legal (CLO)

**Status:** reviewed (carry-forward).
**Assessment:** Pseudonymization under Recital 26 closes H6. Active Art. 17 erasure dropped from scope after plan-time API verification — retention-only is CLO-defensible: pseudonymous data + documented retention satisfies Art. 17 for both Sentry and pino-on-Hetzner. PA8 update is the load-bearing legal artifact.

### Engineering (CTO)

**Status:** reviewed (carry-forward with plan-time correction).
**Assessment:** Hash on emit, not in dedup key. Doppler pepper. Initial single-call Sentry DELETE-by-tag recommendation was a docs misread; plan-time verification dropped that. Centralizing hash inside `reportSilentFallback` + `warnSilentFallback` is drift-resilient. Two direct-Sentry sites in `ws-handler.ts` migrate to `warnSilentFallback` for consistent coverage.

### Product (CPO)

**Status:** reviewed (carry-forward).
**Assessment:** No user-visible surface. Sentry/Better Stack already disclosed via #1048. Ship #3638 before any PR-C that consumes the updated PA8. CPO sign-off honoured (`requires_cpo_signoff: true`).

### Product/UX Gate

**Tier:** none.

## Test Strategy

- **Unit/integration via vitest** (`vitest run` from `apps/web-platform/`).
- **Co-located tests:** `apps/web-platform/test/observability.test.ts`. Extend with Phase 3 cases.
- **Coverage focus:** the four contract branches of `hashUserId` + each of the four mirror-function transforms + each of the two migrated ws-handler sites.
- **Regression guard:** `cc-dispatcher.test.ts` T-W4-orphan test updates its assertion from `userId` to `userIdHash`.
- **Negative-space grep gate** (AC2): the regex `(extra|tags):\s*\{[^}]*\buserId\b` returns no production matches under `apps/web-platform/server/`.

## Sharp Edges (plan-specific)

- The `## User-Brand Impact` section is non-empty and threshold is `single-user incident`. Empty/`TBD` would fail `deepen-plan` Phase 4.6.
- AC2's grep gate covers code at merge time; it does NOT cover Sentry events captured before merge (those age out per retention). PR body must say "events emitted after merge are pseudonymized," not "all Sentry events are pseudonymized."
- `SENTRY_USERID_PEPPER` must be distinct across dev/prd Doppler configs. Sharing the pepper across envs is a contamination vector.
- The `"pepper_unset"` sentinel collides across all users by design (degraded-mode signal). Do NOT add per-user salting to the fallback.
- Do NOT paste pepper values via the conversation `!`-prefix mechanism (`hr-never-paste-secrets-via-bang-prefix`).
- PR body uses `Closes #3638` (closure is at-merge — AC-PM1 is operator follow-through, not a closure gate). `Refs #3686` for the deferred D-durable-audit-log.

## Plan Status

- Brainstorm: 2026-05-12 (`knowledge-base/project/brainstorms/2026-05-12-sentry-userid-hash-art17-erasure-brainstorm.md`)
- Spec: 2026-05-12 (`knowledge-base/project/specs/feat-sentry-userid-hash-art17-3638/spec.md`)
- Plan v1: 2026-05-12 — initial scope (active Sentry purge proposed)
- Plan v2: 2026-05-12 — retention-only after Sentry+Better Stack API verification; dropped purge code, kept PA8 update; corrected Better Stack pipeline misassumption (uptime-only, not log recipient)
- Deferred follow-up: #3686 (`security_events` durable audit-log)
