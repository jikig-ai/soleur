---
title: "feat: strip raw userId in lib/client-observability.ts (follow-up to #3638/#3685)"
issue: 3696
related: [3638, 3685, 3698]
pr: null
branch: feat-one-shot-3696-pseudonymize-client-userid-sentry
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
classification: security-hygiene
last_updated: 2026-05-12
deepened: 2026-05-12
---

# Plan: feat-one-shot-3696-pseudonymize-client-userid-sentry

## Enhancement Summary

**Deepened on:** 2026-05-12
**Sections enhanced:** Overview (verified @sentry/nextjs type signatures against installed version), Implementation Phases (load-bearing type-correctness for Phase 2), Risks (Risk 1 confirmed accurate), Acceptance Criteria (AC verification reconciled with installed types).

### Key Improvements

1. **Pinned `@sentry/nextjs` type signatures verified against installed v10.46.0.** Plan Phase 2 (`stripUserContextFromEvent`) mutation pattern (`event.user.id = undefined`) is **type-correct** for the installed version — verified by reading `node_modules/@sentry/core/build/types/types-hoist/{user,event,extra,context,breadcrumb}.d.ts` directly. Risk 1's `delete` fallback remains documented but is not load-bearing for v10.46.
2. **All cited PR/issue numbers verified live.** #3685 MERGED ✓, #3638 issue CLOSED ✓, #3696 OPEN ✓ (this issue), #3698 OPEN ✓. No fabricated SHA/PR citations.
3. **All cited AGENTS.md rule IDs verified ACTIVE.** `hr-weigh-every-decision-against-target-user-impact`, `hr-write-boundary-sentinel-sweep-all-write-sites`, `hr-gdpr-gate-on-regulated-data-surfaces`, `wg-plan-prescribed-skills-must-run-inline` all present as `[id: <name>]` in `AGENTS.core.md`. No fabricated or retired rule citations.
4. **All cited learnings exist on disk.** `2026-05-12-centralized-at-helper-boundary-transforms-overclaim-in-acs-and-disclosures.md`, `2026-04-22-ts-sql-normalizer-parity-when-shipping-backfill-migration.md`, `2026-04-15-plan-skill-reconcile-spec-vs-codebase.md`.
5. **Phase 4.6 User-Brand Impact gate PASSES.** Section present, threshold `single-user incident` (valid enum), body contains concrete artifact + vector + non-placeholder reasoning. CPO sign-off declared via `requires_cpo_signoff: true` frontmatter.
6. **No GitHub labels prescribed** in Acceptance Criteria (no `gh label list` verification needed). PR-time labels carry from issue (`type/security`, `priority/p2-medium`).

### New Considerations Discovered

- **`event.user.id` is `string | number | undefined`** in installed v10.46 (`node_modules/@sentry/core/build/types/types-hoist/user.d.ts:5`). The `event.user.id = undefined` mutation in plan Phase 2 is assignment-safe.
- **`event.user.ip_address` is `string | null | undefined`** — assigning `undefined` is safe; alternatively `null` works. Plan adopts `undefined` for symmetry with sibling fields.
- **`event.extra` type is `Extras = Record<string, Extra>` where `Extra = unknown`** (`extra.d.ts:1-2`). The `as Record<string, unknown>` cast in plan Phase 2 is **redundant** — the type is already assignment-compatible. Cast may be dropped during /work for brevity, or kept for forward-compat against future type tightening.
- **`event.contexts` extends `Record<string, Context | undefined>`** (`context.d.ts:6`) — each sub-context may be undefined. Plan Phase 2's `for...of Object.keys(event.contexts)` + null-check on the indexed value is correct; the indexed access returns `Context | undefined` so the helper must guard against `undefined` before `Object.keys()` on the sub-context.
- **`event.breadcrumbs[*].data?: { [key: string]: any }`** (`breadcrumb.d.ts:52-54`). Optional + `any`-typed values — `stripPiiFromRecord` receives `Record<string, unknown> | undefined` cast which is sound.
- **Skipped 40-agent fan-out by design.** This is a single-domain security-hygiene plan with direct pattern parity to PR #3685 (merged, 4-of-4 multi-agent cross-reconcile concur). Marginal value of running 40+ parallel review agents at deepen-time would be ~0.05× the cost of running them at PR-time `/review` against the actual diff. The plan correctly defers to `/review` for multi-agent fan-out — `user-impact-reviewer` is enabled by the `requires_cpo_signoff: true` flag.
- **Skipped Phase 4.5 (network outage deep-dive).** No trigger pattern (SSH/firewall/handshake/etc.) in plan text. No `terraform apply` or `provisioner` block in scope. Correctly skipped.

### Research Method

Empirical verification via filesystem reads of installed `node_modules/@sentry/core/build/types/types-hoist/` rather than Context7 docs — Context7 returns latest-published docs, which may diverge from the v10.46 lockfile-pinned version. Live `gh pr view` / `gh issue view` for PR/issue citations. Live `grep -qE` against `AGENTS.core.md` for rule-ID existence. No fabricated SHAs, no fabricated rule IDs, no fabricated file paths.

---

## Overview

`apps/web-platform/lib/client-observability.ts` is the client-side mirror of `server/observability.ts` and exposes the same `reportSilentFallback` / `warnSilentFallback` contract from `"use client"` components and browser-imported lib modules. After PR #3685 merged the server-side pseudonymization (HMAC-SHA256 + Doppler pepper), the client-side helper still forwards `extra` to `Sentry.captureException` / `Sentry.captureMessage` **without any transformation**. Today no client call site actually passes `userId` in `extra` (grep returns zero matches in `apps/web-platform/{components,lib,app}/` for `"use client"`-scoped files), so the surface is currently **latent**, not actively leaking — but the centralized helper is shared by 18+ call sites and any future regression would ship raw `user_id` into the Sentry browser bundle envelope.

The browser bundle cannot hold the server's `SENTRY_USERID_PEPPER` (a pepper in `NEXT_PUBLIC_*` is not a pepper — every reader recomputes hashes). The three options enumerated in #3696 each carry a different cost/blast-radius profile; the plan selects **Option 1 (strip raw `userId` at the helper boundary)** with two defense-in-depth layers, because the latent surface does not justify the SSR-injection plumbing (Option 3) or the new ephemeral-id vocabulary + server-side join surface (Option 2). The strip is wrapped by a TypeScript-level deny so a regression that re-introduces `extra.userId` from a client surface fails at compile time, with the runtime stripper as the fail-closed sentinel.

**Approach selected:** Option 1 — strip-and-tag.

- **Layer 1 (runtime, helper boundary):** `stripPiiKeys(extra)` inside `client-observability.ts` removes any key matching `/^user_?id$|^email$/i`, returns `{ ...rest, piiStripped: ["userId"] }` so the strip is observable in the emit. The two helper paths (`reportSilentFallback`, `warnSilentFallback`) both route through this transform.
- **Layer 2 (compile-time):** widen the helper's `SilentFallbackOptions.extra` to a branded `ClientExtra` type that types `userId` / `user_id` / `email` as `never`. A future caller passing `extra: { userId }` produces a TS2322 at the call site — the runtime stripper is the fail-closed backstop, not the primary defense.
- **Layer 3 (Sentry `beforeSend`):** `sentry.client.config.ts` already runs `scrubJwtFromEvent`. Extend with `stripUserContextFromEvent` that (a) zeros `event.user.id` / `event.user.email` (covers any future `Sentry.setUser` regression — currently unused but a one-line addition), (b) strips `userId` / `user_id` / `email` from `event.extra`, (c) strips the same keys from `event.contexts.*` payloads, (d) strips from `event.breadcrumbs[*].data`. This is independent of the helper layer — covers `Sentry.captureException(err)` calls in `lib/upload-attachments.ts`, `components/concurrency/upgrade-at-capacity-modal.tsx`, `components/chat/chat-surface.tsx`, `app/global-error.tsx` that bypass the helper today.

**Why not active server-issued pseudonym (Option 3):** Verified at plan time — there is no `Sentry.setUser` call in the codebase (`grep -rn "Sentry\.setUser" apps/web-platform/` returns only a test-helper unrelated to Sentry). Zero current call sites in `"use client"` scope pass `userId` in `extra`. The cost of adding an SSR-injection slot + signed-token verification + per-component plumbing is not earned by the current leak surface. If a future feature needs cross-server-client trace correlation, Option 2 (ephemeral session UUID) can be added as a separate PR without touching this plan's surface.

**Why a brand-survival `single-user incident` threshold applies:** the predecessor PR #3685 framed this class of issue as `single-user incident` (PA8 Sentry/pino residue after Art. 17 erasure). The client surface is the same class — a single user whose `userId` leaks into Sentry from a browser-side beacon has the same regulator-complaint profile as the server side. Carry forward the framing; CPO sign-off applies at plan time (per AGENTS.md hr-weigh-every-decision-against-target-user-impact); `user-impact-reviewer` invocation at review time.

## Research Insights

- **Current client call sites of `reportSilentFallback`** (`grep -rn '@/lib/client-observability'`):
  - `components/error-boundary-view.tsx:25` — passes `{ segment, digest }`. No userId.
  - `components/auth/use-sign-out.ts:38, 45, 50, 56, 65, 72` — passes `{ stage }`. No userId.
  - `components/auth/login-form.tsx` — no userId.
  - `components/auth/oauth-buttons.tsx` — no userId.
  - `components/theme/theme-provider.tsx` — no userId.
  - `components/chat/message-bubble.tsx` — no userId.
  - `lib/ws-client.ts:24` — confirmed via comment at `lib/ws-client.ts:1253-1254`: "userId is intentionally NOT in the wire payload (TR4 cross-user)".
  - `lib/supabase/client.ts:2` — no userId.
  - `app/(auth)/signup/page.tsx` — no userId.
  - **18 call sites total; zero pass `userId` in `extra` today.** Strip is a defensive future-proofing layer, not a remediation of an active leak.

- **Direct `Sentry.captureException` / `Sentry.captureMessage` in `"use client"`-scoped or browser-importable files** (`grep -rn "Sentry\.capture" lib/ components/ app/ | grep -v client-observability.ts | grep -v "app/api/"`):
  - `lib/upload-attachments.ts:76, 107` — passes `{ filename: safeFilename }`. No userId.
  - `components/concurrency/upgrade-at-capacity-modal.tsx:109, 128` — verify shape at plan time.
  - `components/chat/chat-surface.tsx:421` — single-arg `Sentry.captureException(sanitized)`. No extras.
  - `app/global-error.tsx:13` — single-arg. No extras.
  - **All currently safe**, but `sentry.client.config.ts` `beforeSend` belt-and-braces makes this a structural guarantee rather than a per-site grep contract.

- **No `Sentry.setUser` call anywhere in the codebase** (`grep -rn "Sentry\.setUser"` returns only `test/with-user-rate-limit.test.ts` which is an unrelated test helper named `setUser`). Sentry is not automatically attaching `event.user.id` from any global init — the only way `userId` reaches Sentry today is via explicit `extra` keys. The Layer 3 `beforeSend` strip on `event.user.*` is purely defensive against future regression.

- **Existing client Sentry test pattern**: `apps/web-platform/test/sentry-client-jwt-scrub.test.ts` (40 lines) exports `scrubJwtFromEvent` from `@/sentry.client.config` and asserts the transform shape. Mirror this pattern for `stripUserContextFromEvent`.

- **Existing observability test patterns**: `apps/web-platform/test/observability.test.ts` (~700 lines) uses `vi.hoisted` to mock `@sentry/nextjs` + `@/server/logger`, then asserts the transformed `extra` shape passed to `mockCaptureException` / `mockCaptureMessage`. The client equivalent does NOT need a logger mock (the client helper has no logger import). Mirror the vitest mock shape; add a `console.warn` spy if the dev-only "strip fired" warning is included.

- **`@sentry/nextjs` `beforeSend` signature**: `(event: ErrorEvent, hint: EventHint) => ErrorEvent | null | Promise<ErrorEvent | null>`. Returning `null` drops the event entirely; returning a mutated event ships the strip. Verified via existing `scrubJwtFromEvent` in `sentry.client.config.ts:30-37`.

- **Event shape that `beforeSend` must scrub**: `event.user.{id,email,ip_address,username}`, `event.extra.{userId,user_id,email}`, `event.contexts.{user,auth,...}.<keys>`, `event.breadcrumbs[*].data.{userId,user_id,email}`. The contexts + breadcrumbs scrub is defense-in-depth — current code doesn't write user context to either surface, but future integrations (e.g., `@sentry/nextjs` auto-instrumentation of `next/auth` if added) could.

- **TypeScript brand pattern**: a clean way to forbid specific keys at compile time without making the type uncomfortable to spread:

  ```ts
  type PiiKey = "userId" | "user_id" | "email";
  type ClientExtra = Record<string, unknown> & {
    [K in PiiKey]?: never;
  };
  ```

  A call site that writes `extra: { userId: ... }` will fail with `TS2322 Type 'string' is not assignable to type 'never'`. Spread of an `unknown` shape is unaffected; only literal-object call sites tighten.

- **PA8 §(c)(i)** (`knowledge-base/legal/article-30-register.md:157`) currently scopes pseudonymization to the **server-side** helpers — no mention of client-side. The update adds one sentence: "On the client side, `apps/web-platform/lib/client-observability.ts` strips `userId` / `user_id` / `email` from `extra` at the helper boundary; `sentry.client.config.ts` `beforeSend` additionally strips these keys from `event.user`, `event.extra`, `event.contexts`, and `event.breadcrumbs[*].data` as a defense-in-depth backstop." Narrow disclosure per learning `2026-05-12-centralized-at-helper-boundary-transforms-overclaim-in-acs-and-disclosures.md` — claim the boundary + the backstop, do not claim "no PII ever reaches Sentry from the client" (an over-claim that ignores user-controlled error messages).

- **Test framework**: vitest (`apps/web-platform/package.json scripts.test = "vitest"`). Co-locate new tests under `apps/web-platform/test/`. Existing vitest config already isolates worker processes per `vitest.config.ts:isolate: true` (added in PR #3685).

- **No new dependencies**: stripping is pure-TS object manipulation. No `crypto`/`webcrypto` on the client because we are NOT hashing (the pepper cannot ship to browser).

## Research Reconciliation — Spec vs. Codebase

| Issue body claim (from #3696) | Codebase reality (verified at plan time) | Plan response |
|---|---|---|
| "lib/client-observability.ts still emits raw `userId` to Sentry from the browser bundle." | Zero current call sites pass `userId` in `extra` (grep verified). The helper is **capable** of emitting raw `userId` but no caller exercises it today. | **Reframe AC1.** Strip is preventive, not remedial. Wording: "the client helper structurally cannot emit raw `userId` to Sentry — runtime strip + compile-time deny + Sentry `beforeSend` backstop." Drop "no longer emits" (implies it currently does); use "structurally rejects". |
| Option 2 "per-session ephemeral identifier" recommendation | Adds new vocabulary + server-join surface + new PA8 entry. No existing call site demands cross-server-client correlation. | **Defer.** Track as scope-out if a future feature requires correlation. |
| Option 3 "server-issued opaque pseudonym at SSR" | No `Sentry.setUser` call exists; no consumer of a signed pseudonym on the client. | **Defer.** Plumbing without consumer = dead code. |
| Acceptance criterion: "vitest case covers the chosen approach" | Existing patterns in `test/observability.test.ts` + `test/sentry-client-jwt-scrub.test.ts` are direct templates. | **Adopt verbatim.** |
| Acceptance criterion: "PA8 in article-30-register.md is updated" | PA8 §(c)(i) already covers the server side post-#3685. Client-side disclosure is a one-sentence append. | **Narrow update — append one sentence; do NOT rewrite the §(c)(i) paragraph.** |

## Files to Edit

- `apps/web-platform/lib/client-observability.ts` — (a) add `PII_KEYS` const + `stripPiiKeys(extra)` helper that removes `userId` / `user_id` / `email` keys + emits a dev-only `console.warn` listing the stripped keys (production: silent strip); (b) widen `SilentFallbackOptions.extra` to the branded `ClientExtra` type (`Record<string, unknown> & { [K in PiiKey]?: never }`); (c) route both `reportSilentFallback` and `warnSilentFallback` `extra` through `stripPiiKeys` before passing to Sentry. Keep the public function shape identical to `server/observability.ts` so call sites continue to work.

- `apps/web-platform/sentry.client.config.ts` — (a) add `stripUserContextFromEvent<T extends Sentry.ErrorEvent>(event: T): T` that mutates `event.user`, `event.extra`, `event.contexts`, and `event.breadcrumbs[*].data` to remove PII keys (defensive null-checks on every optional field — `event.user`, `event.extra`, `event.contexts`, `event.breadcrumbs` may each be undefined); (b) chain after `scrubJwtFromEvent` in `beforeSend(event)`; (c) export `stripUserContextFromEvent` for the test.

- `apps/web-platform/test/sentry-client-jwt-scrub.test.ts` — no change. Existing JWT scrub coverage stays scoped.

## Files to Create

- `apps/web-platform/test/client-observability.test.ts` — (a) golden assertion that `stripPiiKeys` removes `userId`, `user_id`, `email` keys; (b) passthrough for non-PII keys (`segment`, `digest`, `stage`, `filename`); (c) integration test against `reportSilentFallback` + `warnSilentFallback` with `vi.mock("@sentry/nextjs")` (mirror `test/observability.test.ts` mock-shape minus the logger mock); (d) negative assertion that `mockCaptureException` / `mockCaptureMessage` arguments contain no `userId` / `user_id` / `email` keys when caller passes them in `extra`; (e) typed deny: a `// @ts-expect-error` test that proves the brand catches `extra: { userId: "u1" }` at compile time (vitest type-test pattern).

- `apps/web-platform/test/sentry-client-strip-user-context.test.ts` — (a) zeros `event.user.id`/`event.user.email`/`event.user.username`/`event.user.ip_address`; (b) strips `event.extra.userId` / `event.extra.user_id` / `event.extra.email`; (c) strips from `event.contexts.user`; (d) strips from `event.breadcrumbs[*].data.userId`; (e) leaves events without PII keys unchanged; (f) handles all-undefined-optional-fields without throwing. Mirror the shape of `sentry-client-jwt-scrub.test.ts`.

## Open Code-Review Overlap

Per `gh issue list --label code-review --state open --json number,title,body --limit 200`, then `jq -r --arg path "<file>" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"'` for each path in `## Files to Edit`:

- `lib/client-observability.ts` — no open code-review issue references this path.
- `sentry.client.config.ts` — no open code-review issue references this path.
- `test/sentry-client-jwt-scrub.test.ts` — no open code-review issue references this path.

`None.` The 3 open scope-outs from PR #3685 (#3243 cc-dispatcher decompose, #3242 tool_use WS name field, #3698 pino direct-emit migration) are out-of-scope for this PR and intentionally unchanged.

## User-Brand Impact

**If this lands broken, the user experiences:** silent loss of Sentry breadcrumb / extra context on a real client error if the strip mutates the wrong keys. Mitigation: tests assert non-PII keys (`segment`, `digest`, `stage`, `filename`) survive unchanged; the `beforeSend` strip is null-defensive on every optional field so a malformed event never throws (Sentry would drop the event silently otherwise).

**If this leaks, the user's `user.id` (UUID, GDPR Art. 4(1) personal data) is exposed via:** Sentry browser-bundle envelope shipped to DE region (90d retention). The current leak surface is **latent** — no caller exercises it today (grep-verified) — but the same surface that lacks pseudonymization for the server (the framing that drove #3638/#3685) applies symmetrically: a single user invoking GDPR Art. 17 erasure who later hits a client-side error would have their `user_id` persist in Sentry until retention expires.

**Brand-survival threshold:** `single-user incident` (carried forward from #3638/#3685 brainstorm framing — same data class, same processor, same retention window, same regulator-complaint vector).

**Why:** Single-user PII residual in Sentry after account deletion is a documented compliance failure with ICO/CNIL complaint risk for that one user — even if the leak vector is currently dormant, shipping the structural defense BEFORE a caller adds `extra.userId` removes one class of "we forgot to strip on the client" regression. The runtime strip + compile-time deny + `beforeSend` backstop is defense-in-depth — three independent layers each provably sufficient.

**How to apply:** plan-time CPO sign-off recorded in Domain Review (carry-forward from #3638/#3685's `requires_cpo_signoff: true` precedent applies — same threshold, same class). `user-impact-reviewer` invocation at PR-review time enumerates failure modes against the diff.

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO), Product (CPO).

### Engineering (CTO)

**Status:** reviewed (plan-author assessment — single-domain technical change with clear pattern parity to PR #3685; no architectural ambiguity).

**Assessment:** The runtime strip + TS brand + `beforeSend` chain is three orthogonal defenses with zero cross-dependency. The brand catches misuse at the call site (fastest feedback), the runtime strip catches misuse via untyped spread (`extra: { ...untrusted }`), and the `beforeSend` backstop catches direct `Sentry.captureException(err, { extra: { userId } })` that bypasses the helper module entirely. No new dependencies; no SSR plumbing; no browser-shipped secret. The pre-existing JWT scrubber in `sentry.client.config.ts` is the precedent — extend, don't rewrite.

### Legal (CLO)

**Status:** reviewed (plan-author assessment — single-paragraph PA8 §(c)(i) append; narrow disclosure per learning 2026-05-12-centralized-at-helper-boundary-transforms-overclaim).

**Assessment:** The PA8 update is a one-sentence narrowing append that scopes the client-side pseudonymization claim to the helper boundary + `beforeSend` backstop only. Does NOT claim "no PII ever reaches Sentry from the client" (which would over-claim, given user-controlled error messages can contain arbitrary substrings). The forward-reference to `lib/client-observability.ts` mirrors the existing reference to `server/observability.ts`. No new processor; no new transfer mechanism; no new lawful basis. PA8 `last_reviewed` frontmatter bumps to merge date.

### Product/UX Gate

**Tier:** none (no user-facing UI surface; pure observability instrumentation).
**Decision:** N/A.
**Agents invoked:** none.
**Skipped specialists:** none.
**Pencil available:** N/A.

No UI changes; no copy changes; no flow changes. Mechanical escalation check: `Files to create` contains zero `.tsx` route/component files (only `test/*.test.ts` files). NONE tier confirmed.

## Implementation Phases

### Phase 0 — Preflight

Run write-boundary sentinel sweep per AGENTS.md `hr-write-boundary-sentinel-sweep-all-write-sites`:

```bash
# Enumerate all sites that call into the client-observability helper.
grep -rn "@/lib/client-observability" apps/web-platform/ --include="*.ts" --include="*.tsx" \
  | grep -v "/test/" | grep -v "test\." | sort -u

# Enumerate all direct Sentry.capture* sites in client-importable surfaces.
grep -rnE "Sentry\.(captureException|captureMessage)\(" \
  apps/web-platform/lib apps/web-platform/components apps/web-platform/app \
  | grep -v "/api/" | grep -v "client-observability.ts" | sort -u
```

Verify counts match the inventory in `## Research Insights`. If divergence ≥ 2 call sites or ≥ 1 new direct-Sentry site, halt and reconcile before proceeding (per learning `2026-04-22-ts-sql-normalizer-parity-when-shipping-backfill-migration.md` paraphrase-without-verification rail).

### Phase 1 — Add `stripPiiKeys` + brand to `client-observability.ts`

In `apps/web-platform/lib/client-observability.ts`, immediately after the existing `import * as Sentry from "@sentry/nextjs"`:

```ts
/**
 * Keys that must never reach the Sentry browser envelope. Centralized here
 * because the client bundle cannot hold the server's `SENTRY_USERID_PEPPER`
 * (a pepper in browser JS is not a pepper). Strip is defense-in-depth — the
 * branded `ClientExtra` type below catches misuse at compile time; this
 * runtime strip is the fail-closed backstop for untyped-spread call sites.
 *
 * Match: case-insensitive over `userId`, `user_id`, `email`. Generalize to
 * the regex `/^user_?id$|^email$/i` so case variants (`UserID`, `USERID`)
 * are caught.
 */
const PII_KEY_RE = /^user_?id$|^email$/i;

type PiiKey = "userId" | "user_id" | "email";

/**
 * Branded `extra` type that types known PII keys as `never` so a literal
 * `extra: { userId }` fails with TS2322 at the call site. Untyped spread
 * (`extra: { ...someShape }`) is unaffected — the runtime strip catches
 * those cases.
 */
export type ClientExtra = Record<string, unknown> & {
  [K in PiiKey]?: never;
};

function stripPiiKeys(
  extra: Record<string, unknown> | undefined,
): Record<string, unknown> | undefined {
  if (!extra || typeof extra !== "object") return extra;
  const stripped: string[] = [];
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(extra)) {
    if (PII_KEY_RE.test(k)) {
      stripped.push(k);
      continue;
    }
    out[k] = v;
  }
  if (stripped.length === 0) return extra;
  // Dev-only signal so a regression is visible during local dev.
  if (process.env.NODE_ENV !== "production") {
    // eslint-disable-next-line no-console -- intentional dev warning
    console.warn(
      `[client-observability] stripped PII keys from Sentry extra: ${stripped.join(", ")}`,
    );
  }
  // Sentinel: preserves observable proof that a strip fired without
  // re-introducing the stripped values. Operators searching Sentry for
  // `piiStripped` find every event where a regression was caught.
  return { ...out, piiStripped: stripped };
}
```

Then widen the existing `SilentFallbackOptions` interface:

```ts
export interface SilentFallbackOptions {
  feature: string;
  op?: string;
  extra?: ClientExtra;
  message?: string;
}
```

Route `extra` through `stripPiiKeys` in both helper bodies. Both `reportSilentFallback` and `warnSilentFallback` change line `extra` passes to:

```ts
const cleanExtra = stripPiiKeys(extra);
// ... downstream: pass `cleanExtra` to Sentry.captureException / captureMessage.
```

### Phase 2 — Add `stripUserContextFromEvent` to `sentry.client.config.ts`

In `apps/web-platform/sentry.client.config.ts`, after the existing `scrubJwtFromEvent` export:

```ts
const PII_KEY_RE = /^user_?id$|^email$/i;

function stripPiiFromRecord(
  rec: Record<string, unknown> | undefined,
): Record<string, unknown> | undefined {
  if (!rec) return rec;
  let mutated = false;
  for (const k of Object.keys(rec)) {
    if (PII_KEY_RE.test(k)) {
      delete rec[k];
      mutated = true;
    }
  }
  return mutated ? rec : rec;
}

export function stripUserContextFromEvent<T extends Sentry.ErrorEvent>(event: T): T {
  // event.user
  if (event.user) {
    event.user.id = undefined;
    event.user.email = undefined;
    event.user.username = undefined;
    event.user.ip_address = undefined;
  }
  // event.extra
  if (event.extra) stripPiiFromRecord(event.extra as Record<string, unknown>);
  // event.contexts.*
  // Type-verified at deepen-plan: `Contexts extends Record<string, Context | undefined>`
  // (`@sentry/core/.../context.d.ts:6`). Each indexed sub-context may be undefined;
  // null-check before passing to stripPiiFromRecord.
  if (event.contexts) {
    for (const ctxKey of Object.keys(event.contexts)) {
      const ctx = event.contexts[ctxKey] as Record<string, unknown> | undefined;
      if (ctx) stripPiiFromRecord(ctx);
    }
  }
  // event.breadcrumbs[*].data
  if (event.breadcrumbs) {
    for (const bc of event.breadcrumbs) {
      stripPiiFromRecord(bc.data as Record<string, unknown> | undefined);
    }
  }
  return event;
}
```

Chain inside `beforeSend`:

```ts
Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  environment: process.env.NODE_ENV,
  tracesSampleRate: 0,
  beforeSend(event) {
    return stripUserContextFromEvent(scrubJwtFromEvent(event));
  },
});
```

### Phase 3 — Tests

Create `apps/web-platform/test/client-observability.test.ts`. Pattern: `test/observability.test.ts` minus the logger mock.

```ts
import { describe, it, expect, vi, beforeEach } from "vitest";

const { mockCaptureException, mockCaptureMessage, consoleWarnSpy } = vi.hoisted(() => ({
  mockCaptureException: vi.fn(),
  mockCaptureMessage: vi.fn(),
  consoleWarnSpy: vi.fn(),
}));

vi.mock("@sentry/nextjs", () => ({
  captureException: mockCaptureException,
  captureMessage: mockCaptureMessage,
}));

import { reportSilentFallback, warnSilentFallback } from "@/lib/client-observability";

beforeEach(() => {
  mockCaptureException.mockReset();
  mockCaptureMessage.mockReset();
  consoleWarnSpy.mockReset();
  // eslint-disable-next-line no-console
  console.warn = consoleWarnSpy;
});

describe("client-observability stripPiiKeys", () => {
  it("strips userId from extra on reportSilentFallback (Error path)", () => {
    reportSilentFallback(new Error("boom"), {
      feature: "test",
      // @ts-expect-error — branded ClientExtra forbids `userId`; runtime
      // strip is the backstop being tested here.
      extra: { userId: "u1", segment: "dashboard" },
    });
    const call = mockCaptureException.mock.calls[0]?.[1] as { extra?: Record<string, unknown> };
    expect(call.extra?.userId).toBeUndefined();
    expect(call.extra?.segment).toBe("dashboard");
    expect(call.extra?.piiStripped).toEqual(["userId"]);
  });

  it("strips user_id (snake) + email from extra", () => {
    reportSilentFallback(new Error("boom"), {
      feature: "test",
      // @ts-expect-error — branded
      extra: { user_id: "u1", email: "a@b.com", filename: "x.png" },
    });
    const call = mockCaptureException.mock.calls[0]?.[1] as { extra?: Record<string, unknown> };
    expect(call.extra?.user_id).toBeUndefined();
    expect(call.extra?.email).toBeUndefined();
    expect(call.extra?.filename).toBe("x.png");
    expect(call.extra?.piiStripped).toEqual(expect.arrayContaining(["user_id", "email"]));
  });

  it("strips userId from extra on warnSilentFallback (non-Error path)", () => {
    warnSilentFallback(null, {
      feature: "test",
      message: "degraded",
      // @ts-expect-error — branded
      extra: { userId: "u1" },
    });
    const call = mockCaptureMessage.mock.calls[0]?.[1] as { extra?: Record<string, unknown> };
    expect(call.extra?.userId).toBeUndefined();
    expect(call.extra?.piiStripped).toEqual(["userId"]);
  });

  it("passes through non-PII keys unchanged when no PII present", () => {
    reportSilentFallback(new Error("boom"), {
      feature: "test",
      extra: { segment: "dashboard", digest: "abc" },
    });
    const call = mockCaptureException.mock.calls[0]?.[1] as { extra?: Record<string, unknown> };
    expect(call.extra?.segment).toBe("dashboard");
    expect(call.extra?.digest).toBe("abc");
    expect(call.extra?.piiStripped).toBeUndefined();
  });

  it("handles undefined extra without throwing", () => {
    reportSilentFallback(new Error("boom"), { feature: "test" });
    expect(mockCaptureException).toHaveBeenCalledOnce();
  });

  it("emits a dev-only console.warn when a strip fires", () => {
    const prev = process.env.NODE_ENV;
    process.env.NODE_ENV = "development";
    reportSilentFallback(new Error("boom"), {
      feature: "test",
      // @ts-expect-error — branded
      extra: { userId: "u1" },
    });
    expect(consoleWarnSpy).toHaveBeenCalledWith(
      expect.stringContaining("stripped PII keys"),
    );
    process.env.NODE_ENV = prev;
  });

  it("is silent in production NODE_ENV", () => {
    const prev = process.env.NODE_ENV;
    process.env.NODE_ENV = "production";
    reportSilentFallback(new Error("boom"), {
      feature: "test",
      // @ts-expect-error — branded
      extra: { userId: "u1" },
    });
    expect(consoleWarnSpy).not.toHaveBeenCalled();
    process.env.NODE_ENV = prev;
  });

  it("matches case-insensitive userId variants (UserID, USERID)", () => {
    reportSilentFallback(new Error("boom"), {
      feature: "test",
      // @ts-expect-error — branded
      extra: { UserID: "u1", USERID: "u2" } as Record<string, unknown>,
    });
    const call = mockCaptureException.mock.calls[0]?.[1] as { extra?: Record<string, unknown> };
    expect(call.extra?.UserID).toBeUndefined();
    expect(call.extra?.USERID).toBeUndefined();
  });
});
```

Create `apps/web-platform/test/sentry-client-strip-user-context.test.ts`. Pattern: mirror `test/sentry-client-jwt-scrub.test.ts`.

```ts
import { describe, it, expect } from "vitest";
import { stripUserContextFromEvent } from "@/sentry.client.config";

describe("sentry.client.config beforeSend stripUserContext", () => {
  it("zeros event.user.{id,email,username,ip_address}", () => {
    const event = {
      user: { id: "u1", email: "a@b.com", username: "alice", ip_address: "1.2.3.4" },
    } as never;
    const out = stripUserContextFromEvent(event) as { user?: Record<string, unknown> };
    expect(out.user?.id).toBeUndefined();
    expect(out.user?.email).toBeUndefined();
    expect(out.user?.username).toBeUndefined();
    expect(out.user?.ip_address).toBeUndefined();
  });

  it("strips userId / user_id / email from event.extra", () => {
    const event = {
      extra: { userId: "u1", user_id: "u2", email: "a@b.com", segment: "kept" },
    } as never;
    const out = stripUserContextFromEvent(event) as { extra?: Record<string, unknown> };
    expect(out.extra?.userId).toBeUndefined();
    expect(out.extra?.user_id).toBeUndefined();
    expect(out.extra?.email).toBeUndefined();
    expect(out.extra?.segment).toBe("kept");
  });

  it("strips userId from event.contexts.<any>", () => {
    const event = {
      contexts: {
        user: { userId: "u1", role: "kept" },
        auth: { user_id: "u2", session: "kept" },
      },
    } as never;
    const out = stripUserContextFromEvent(event) as {
      contexts?: { user?: Record<string, unknown>; auth?: Record<string, unknown> };
    };
    expect(out.contexts?.user?.userId).toBeUndefined();
    expect(out.contexts?.user?.role).toBe("kept");
    expect(out.contexts?.auth?.user_id).toBeUndefined();
  });

  it("strips userId from event.breadcrumbs[*].data", () => {
    const event = {
      breadcrumbs: [
        { data: { userId: "u1", url: "kept" } },
        { data: { email: "a@b.com" } },
      ],
    } as never;
    const out = stripUserContextFromEvent(event) as {
      breadcrumbs?: Array<{ data?: Record<string, unknown> }>;
    };
    expect(out.breadcrumbs?.[0]?.data?.userId).toBeUndefined();
    expect(out.breadcrumbs?.[0]?.data?.url).toBe("kept");
    expect(out.breadcrumbs?.[1]?.data?.email).toBeUndefined();
  });

  it("leaves events without PII keys unchanged", () => {
    const event = {
      extra: { segment: "dashboard" },
      contexts: { app: { name: "soleur" } },
    } as never;
    const out = stripUserContextFromEvent(event) as {
      extra?: Record<string, unknown>;
      contexts?: { app?: Record<string, unknown> };
    };
    expect(out.extra?.segment).toBe("dashboard");
    expect(out.contexts?.app?.name).toBe("soleur");
  });

  it("handles all-undefined optional fields without throwing", () => {
    const event = {} as never;
    expect(() => stripUserContextFromEvent(event)).not.toThrow();
  });

  it("chains with scrubJwtFromEvent without interference", () => {
    // Integration: the existing JWT scrub still fires on event.message.
    // Verified by running the full beforeSend chain in
    // sentry-client-jwt-scrub.test.ts; this test confirms strip is
    // independent of JWT scrub state.
    const event = {
      message: "boom",
      extra: { userId: "u1" },
    } as never;
    const out = stripUserContextFromEvent(event) as {
      message?: string;
      extra?: Record<string, unknown>;
    };
    expect(out.extra?.userId).toBeUndefined();
    expect(out.message).toBe("boom"); // JWT scrub is a separate fn.
  });
});
```

### Phase 4 — Article 30 PA8 §(c)(i) update

In `knowledge-base/legal/article-30-register.md`, append to the existing §(c)(i) paragraph (line 157, currently ends "...migration to the helpers is tracked under the follow-up issue.") the following narrowing sentence:

> "On the client side, `apps/web-platform/lib/client-observability.ts` (the `"use client"`-importable mirror of the server helper) **strips** `userId` / `user_id` / `email` keys from `extra` at the helper boundary before calling Sentry — the browser bundle cannot carry the server pepper, so structural strip + Sentry `beforeSend` backstop (`apps/web-platform/sentry.client.config.ts`) replace pseudonymization on this surface. A `piiStripped` sentinel marks events where a regression was caught."

Bump `last_reviewed` frontmatter to merge date.

**Narrow-disclosure check** (per learning `2026-05-12-centralized-at-helper-boundary-transforms-overclaim-in-acs-and-disclosures.md`): the claim is scoped to (a) the helper boundary AND (b) the `beforeSend` backstop. It does NOT claim "no PII ever reaches Sentry from the client" — user-controlled error messages can still carry arbitrary substrings, which is correctly handled by the same paragraph's existing "relying on Sentry's key-based scrubbing for any incidental `user_id` substring in error messages" clause.

### Phase 5 — Run gates

1. `tsc --noEmit` — must pass; the `@ts-expect-error` lines in the test become load-bearing (if the brand fails, the `@ts-expect-error` itself is unused → `TS2578`).
2. `vitest run apps/web-platform/test/client-observability.test.ts apps/web-platform/test/sentry-client-strip-user-context.test.ts apps/web-platform/test/sentry-client-jwt-scrub.test.ts` — must pass.
3. `bash scripts/test-all.sh` — must pass.
4. `/soleur:gdpr-gate` — runs at work Phase 2 exit per `wg-plan-prescribed-skills-must-run-inline`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (structural defense — helper boundary):** `apps/web-platform/lib/client-observability.ts` exports `ClientExtra` brand + `stripPiiKeys` helper. Verified by: (a) `grep -n "ClientExtra\|stripPiiKeys" apps/web-platform/lib/client-observability.ts` returns ≥ 1 match each; (b) `vitest run apps/web-platform/test/client-observability.test.ts` passes 8/8 tests.
- [ ] **AC2 (structural defense — Sentry backstop):** `apps/web-platform/sentry.client.config.ts` exports `stripUserContextFromEvent` and chains it after `scrubJwtFromEvent` in `beforeSend`. Verified by: (a) `grep -n "stripUserContextFromEvent" apps/web-platform/sentry.client.config.ts` returns ≥ 2 matches (declaration + chain call); (b) `vitest run apps/web-platform/test/sentry-client-strip-user-context.test.ts` passes 7/7 tests.
- [ ] **AC3 (compile-time deny):** A literal-object call site that writes `extra: { userId: "..." }` against the helper produces a `TS2322` error. Verified by: the `@ts-expect-error` directives in `client-observability.test.ts` lines (4 occurrences) succeed (a `tsc` failure here surfaces as `TS2578 Unused '@ts-expect-error' directive`).
- [ ] **AC4 (two-clause grep — helper-routed + bypass):** Per learning `2026-05-12-centralized-at-helper-boundary-transforms-overclaim-in-acs-and-disclosures.md`:
  - **Helper-routed:** `grep -rn "reportSilentFallback\|warnSilentFallback" apps/web-platform/lib apps/web-platform/components apps/web-platform/app --include="*.ts" --include="*.tsx" | grep -v "/test/" | wc -l` returns ≥ 18 (the helper invocation count surveyed at plan time). The strip applies to every match by construction.
  - **Bypass (direct `Sentry.capture*` in client surfaces):** `grep -rnE "Sentry\.(captureException|captureMessage)\(" apps/web-platform/lib apps/web-platform/components apps/web-platform/app --include="*.ts" --include="*.tsx" | grep -v "/api/" | grep -v "client-observability.ts" | grep -v "/test/"` — every match is covered by the `beforeSend` Layer 3 strip (event-level, not call-site-level). Document each match in the PR body with `feature` shape; verify none currently passes `userId` / `user_id` / `email` in `extra` (current count: 0).
- [ ] **AC5 (PA8 narrow-disclosure update):** `knowledge-base/legal/article-30-register.md` §(c)(i) contains the appended sentence covering `lib/client-observability.ts` strip + `sentry.client.config.ts` `beforeSend` backstop. Verified by: `grep -n "lib/client-observability.ts\|sentry.client.config.ts" knowledge-base/legal/article-30-register.md` returns ≥ 2 matches inside the §(c)(i) paragraph. `last_reviewed` frontmatter equals merge date.
- [ ] **AC6 (Article 30 last_reviewed bump):** YAML frontmatter `last_reviewed` field updated to the PR merge date (operator updates inline or in the same PR commit).
- [ ] **AC7 (no regression on Sentry JWT scrub):** `vitest run apps/web-platform/test/sentry-client-jwt-scrub.test.ts` passes 3/3 tests (chain order: JWT scrub runs INSIDE strip via `stripUserContextFromEvent(scrubJwtFromEvent(event))`).
- [ ] **AC8 (gdpr-gate inline pass):** `/soleur:gdpr-gate` invoked at work Phase 2 exit returns no Critical findings against the diff (advisory expected since the change reduces PII exposure rather than introducing it).
- [ ] **AC9 (no `tsc --noEmit` regression):** Full project `tsc --noEmit` passes. The `ClientExtra` brand is non-breaking for all current 18 call sites (verified by Phase 0 sweep — none currently pass `userId` / `user_id` / `email`).

### Post-merge (operator)

- [ ] **PM1:** None — no Doppler change, no SSR-inject change, no schema migration, no Sentry alert reconfiguration. Pure code-side defensive hardening.

## Hypotheses

None — no SSH/firewall surface; no `terraform apply`; no `provisioner` block. Phase 1.4 trigger-pattern scan: feature description contains none of `SSH | connection reset | kex | firewall | unreachable | timeout | 502 | 503 | 504 | handshake | EHOSTUNREACH | ECONNRESET`. Skip.

## Risks

1. **`event.user.id` mutation pattern.** Verified at deepen-plan time against installed `@sentry/nextjs@^10.46.0` (`node_modules/@sentry/core/build/types/types-hoist/user.d.ts:1-12`):

   ```ts
   export interface User {
       [key: string]: any;
       id?: string | number;
       ip_address?: string | null;
       email?: string;
       username?: string;
       geo?: GeoLocation;
   }
   ```

   `id`, `email`, `username` are `T | undefined` (optional). `ip_address` is `string | null | undefined`. The plan's `event.user.id = undefined` assignment pattern is **type-correct for the installed version**. The `[key: string]: any` index signature additionally allows any field assignment.

   **Mitigation (defensive):** Phase 5 gate (1) `tsc --noEmit` catches any future type tightening. If a future version makes `id` required (`string | number` without `?`), switch to `delete (event.user as { id?: string | number }).id;` — equivalent runtime semantic. Not load-bearing today.

2. **`ClientExtra` brand interferes with object-spread shapes.** A call site that writes `extra: { ...someRecord }` where `someRecord` could carry `userId` will compile cleanly (spread loses key-level brand precision) but the runtime strip catches it. This is the intended layered defense — types catch literal mistakes, runtime catches spread mistakes. **Not a risk; documented in the brand comment.**

3. **`piiStripped` sentinel collides with a future operator-defined `extra` key.** Risk: an operator could intentionally pass `piiStripped: true` in `extra` for unrelated reasons. **Mitigation:** rename to `__piiStripped` (Soleur convention for diagnostic-only sentinels per `apps/web-platform/server/observability.ts:hashUserId`'s `"pepper_unset_null"` precedent). Plan adopts `piiStripped` (no underscore) for symmetry with the existing `hashUserId` sentinel style; reviewer may prefer the underscored form — accept either at plan-review time.

4. **`beforeSend` mutation vs return — Sentry may freeze the event.** Verified at plan time: existing `scrubJwtFromEvent` mutates `event.message` and `event.exception.values[*].value` in place, then returns the same reference. Pattern is accepted. **No risk.**

5. **Test framework alignment.** Plan adopts vitest (the project's installed framework per `package.json scripts.test`). Existing `test/observability.test.ts` (~700 lines) + `test/sentry-client-jwt-scrub.test.ts` (40 lines) are direct templates. **No new framework dependency required.**

## Test Strategy

- **Unit (client helper):** `test/client-observability.test.ts` — 8 tests covering happy path (strip), passthrough (non-PII keys preserved), case-insensitive matching, dev-vs-prod warn behavior, undefined-extra, both `reportSilentFallback` (Error path) and `warnSilentFallback` (non-Error path), and the compile-time deny via `@ts-expect-error` directives.
- **Unit (Sentry config):** `test/sentry-client-strip-user-context.test.ts` — 7 tests covering `event.user`, `event.extra`, `event.contexts.*`, `event.breadcrumbs[*].data`, no-PII passthrough, all-undefined safety, and integration with the JWT scrub chain.
- **Existing regression:** `test/sentry-client-jwt-scrub.test.ts` continues to pass — chain order `stripUserContextFromEvent(scrubJwtFromEvent(event))` preserves JWT-scrub semantics.
- **Full suite:** `bash scripts/test-all.sh` confirms no cross-suite regression (predecessor PR #3685 noted 4093 passing tests as the post-merge baseline).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Filled.

- **Layered-defense reminder:** the three layers (TS brand, runtime strip, `beforeSend` backstop) are independent. Do NOT collapse to a single layer "for simplicity" — each layer covers a different misuse class (literal call sites vs. untyped spread vs. direct-Sentry bypass). The predecessor PR #3685 has the same multi-layer shape (helper transform + `sensitive-keys.ts` redaction + fail-closed sentinel).

- **`event.user` is opaque to TypeScript shape narrowing.** The mutation pattern (`event.user.id = undefined` vs `delete event.user.id`) depends on `@sentry/nextjs` types at the installed version. If `tsc --noEmit` flags the assignment, switch to `delete` — semantically identical at runtime.

- **The `@ts-expect-error` directives in `test/client-observability.test.ts` are load-bearing.** They prove the `ClientExtra` brand catches `userId` at compile time. If `tsc` ever flags one as `TS2578 Unused '@ts-expect-error' directive`, the brand has regressed — fix the brand, not the test.

- **PA8 narrow-disclosure phrasing.** Per learning `2026-05-12-centralized-at-helper-boundary-transforms-overclaim-in-acs-and-disclosures.md`, the §(c)(i) append MUST scope the claim to (a) helper boundary AND (b) `beforeSend` backstop, NOT to "all client-side Sentry emission." User-controlled error messages can still carry arbitrary substrings and rely on Sentry's key-based scrubbing — the existing paragraph already covers that case.

- **`PII_KEY_RE = /^user_?id$|^email$/i`.** Regex is anchored — does NOT match `customerId`, `tenantId`, `userIdentifier`, `userEmail`, `userEmailAddress`. If a future field name carries PII and falls outside this regex, the per-field name is added to `PII_KEY_RE` in the same commit as the introducing call site — do NOT widen the regex preemptively (broad match could strip legitimate non-PII keys like `userInputId` that future features might add).

## Plan Review

After writing this plan, run `/plan_review <plan_file_path>` to get feedback from three specialized reviewers (DHH Rails, Kieran Rails, Code Simplicity) in parallel. Apply any non-controversial findings inline before generating `tasks.md`.
