---
title: "Client-side PII strip when the server pepper cannot ship to the browser"
date: 2026-05-12
category: security-issues
module: apps/web-platform/observability
related: [3638, 3685, 3696, 3700]
tags: [sentry, pii, gdpr, client-bundle, observability]
---

# Client-side PII strip when the server pepper cannot ship to the browser

## Problem

Server-side PII pseudonymization (PR #3685) uses HMAC-SHA256 with a Doppler-held `SENTRY_USERID_PEPPER` to hash `userId` before emitting to Sentry. The client-side equivalent (`apps/web-platform/lib/client-observability.ts`) cannot reuse this approach — a pepper in `NEXT_PUBLIC_*` is not a pepper (every reader can recompute the hash). Issue #3696 asked: how do we get the same regulatory posture without shipping the pepper?

## Solution

**Strip-and-tag, in three independent layers:**

1. **TypeScript brand** — `ClientExtra = Record<string, unknown> & { [K in PiiKey]?: never }` types `userId`/`user_id`/`email` as `never`. Literal-object call sites fail at compile time with TS2322.
2. **Runtime strip at the helper boundary** — `stripPiiKeys(extra)` removes any key matching `/^user_?id$|^email$/i` and emits a `piiStripped: string[]` sentinel so operators searching Sentry for `piiStripped` find every regression-caught event.
3. **Sentry `beforeSend` backstop** — `stripUserContextFromEvent` mutates `event.user.{id,email,username,ip_address}`, `event.extra`, `event.contexts.*`, and `event.breadcrumbs[*].data`. Covers direct `Sentry.captureException` callers that bypass the helper module entirely.

Each layer covers a distinct misuse class: literal call sites (Layer 1) → untyped spread (Layer 2) → helper-bypass (Layer 3). The `PII_KEY_RE` regex is exported from the helper module and imported by the Sentry config — one source of truth, structurally locked by a unit-test parity assertion.

Net result: **the client surface structurally rejects raw `userId` in Sentry without needing a browser-shippable secret.** The regulatory framing (GDPR Recital 26 pseudonymization) is replaced by structural strip + tagged sentinel, with the boundary disclosure narrowed in PA8 §(c)(i) of the Article 30 register to claim only what the layered defense actually delivers.

## Key Insight

**When a server-side fix uses a secret (pepper, key, signing) and the same fix is requested on the client, the answer is rarely "ship the secret to the client" or "introduce server-injection plumbing" — it's "drop the secret-dependent transform and substitute a structural defense that covers the same regulatory class."** Pseudonymization gives you an identifier you can correlate; strip gives you no identifier at all. Trade-off: client and server events from the same user session are no longer correlatable in Sentry. If correlation becomes a real ops need later, a server-issued ephemeral session UUID is a separate feature that doesn't compromise the strip.

**On the `delete` vs `= undefined` choice for Sentry event mutation:** prefer `delete event.user.id` over `event.user.id = undefined`. Both are correct against `@sentry/nextjs@^10.46.0` types, but `delete` is symmetric with `stripPiiFromRecord`'s loop, defensible against future SDK serializer changes that might stringify `undefined` as `"undefined"`, and matches the precedent in the same file.

**On regex anchoring policy:** narrow anchors (`/^user_?id$|^email$/i`) over preemptive widening. False-positive risk (stripping legitimate non-PII keys) is asymmetric — a false-strip is a debugging context loss that a real user feels on a real error, whereas a false-pass (regex misses a PII variant) only matters if a call site explicitly tries to ship that variant, which the per-field-addition-at-introducing-PR policy catches. Reviewers will reliably ask to broaden the regex; cite the plan's Sharp Edges and the trade-off above.

## Session Errors

1. **TypeScript readonly `NODE_ENV` assignment in vitest test** — `process.env.NODE_ENV = "development"` failed with TS2540 because `@types/node` types `NODE_ENV` as `"production" | "development" | "test"` (readonly literal union). **Recovery:** switched to `vi.stubEnv("NODE_ENV", "development")` + `vi.unstubAllEnvs()` in `beforeEach`/`afterAll`. **Prevention:** when a vitest test needs to mutate `process.env.NODE_ENV` (or any env var typed as a readonly literal union), use `vi.stubEnv` from the start. Adds a one-line `vi.unstubAllEnvs()` in `beforeEach` to restore between tests. The SUT must read `process.env.NODE_ENV` at call time (not module-init); if it reads at module-init, `vi.stubEnv` after import has no effect — restructure the SUT or use `vi.resetModules()` between cases.

2. **Unused `@ts-expect-error` directive after widening cast** — directive on a literal that included `as Record<string, unknown>` was flagged TS2578 because the cast already widened the type past the `ClientExtra` brand. **Recovery:** removed the directive and replaced with an explanatory comment. **Prevention:** when a cast widens past the type the brand denies, the `@ts-expect-error` is doing nothing — drop it. If the test means to verify the brand at compile time, the literal must hit the brand directly (no widening cast).

3. **Plan file modified between Read and Edit** — Edit failed with "File has been modified since read". A linter (or another tool) touched the plan file in the same pipeline turn. **Recovery:** re-read, re-Edit. **Prevention:** harness already enforces this; the re-read pattern is correct.

## Prevention Strategies

- **Test environment for `process.env` mutation in vitest:** always `vi.stubEnv` + `vi.unstubAllEnvs`. Document this in any new test file's header.
- **Multi-layer PII defense pattern:** when porting a server-side hashing transform to a client that can't hold the secret, default to (compile-time brand + runtime strip at helper boundary + framework-hook backstop). Each layer covers a distinct misuse class; collapsing to a single layer hides regressions.
- **Sentry event mutation:** use `delete` not `= undefined` for symmetry with the loop helper and SDK-future-proofing.
- **Regex anchoring policy:** prefer narrow anchors; widen the regex only at the PR that introduces the specific PII-key variant that needs it.

## Related

- PR #3685 — server-side `hashUserId` pseudonymization (the predecessor whose pattern the client diverges from).
- Issue #3638 — original Sentry/pino pseudonymization framing.
- Issue #3703 — deferred-scope-out follow-up: add `client-pii-grep` CI + lefthook gate for PR-time signal-quality.
- Learning `2026-05-12-centralized-at-helper-boundary-transforms-overclaim-in-acs-and-disclosures.md` — used to scope the PA8 disclosure narrowly.

## Tags

category: security-issues
module: apps/web-platform/lib/client-observability.ts
