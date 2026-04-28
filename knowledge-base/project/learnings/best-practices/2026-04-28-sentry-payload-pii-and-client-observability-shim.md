---
date: 2026-04-28
category: best-practices
module: apps/web-platform/auth
tags: [sentry, observability, pii, client-server-split, oauth, auth]
related_pr: 2994
related_issue: 2979
---

# Sentry payloads must drop `error.message`; client mirrors via `lib/client-observability` shim

## Problem

PR #2994's first iteration mirrored Supabase auth errors to Sentry from four sites
(server callback + three client handlers) and forwarded `error.message?.slice(0, 200)`
in the `extra` payload. Multi-agent review (user-impact-reviewer, pattern-recognition,
code-quality) flagged two distinct issues:

1. **PII / cross-tenant exposure.** `error.message` from `@supabase/auth-js` can embed
   user-supplied input — the email passed to `signInWithOtp` appears in some error
   messages, and rate-limit messages can include addresses. The 200-char `slice` is a
   length cap, not a PII filter. Sentry is a shared-tenant project (`org=jikigai`), so
   forwarding `error.message` is an operator-side cross-tenant exposure vector. The
   plan's `## User-Brand Impact` section explicitly claimed "no data leakage path on
   the failure side" — adding `error.message` forwarding contradicted that without
   updating the section.

2. **Client used `Sentry.captureException` directly instead of the project shim.**
   `apps/web-platform/lib/client-observability.ts` already exists as the client-safe
   `reportSilentFallback` mirror (server's version transitively pulls pino into the
   browser bundle). Two sibling client modules (`message-bubble.tsx`, `ws-client.ts`)
   already use the shim. New code in `oauth-buttons.tsx` and `login/page.tsx` bypassed
   it.

## Solution

**Sentry payload rule for auth-class errors:** forward only typed enum fields:

```ts
reportSilentFallback(error, {
  feature: "auth",
  op: "<verb>",
  extra: {
    errorCode: (error as { code?: string }).code,
    errorName: error.name,
    errorStatus: error.status, // server only — clients don't have HTTP status here
    // DO NOT forward error.message — Supabase auth-js can embed user-supplied input.
  },
});
```

The typed `errorCode` (Supabase ErrorCode union member) is sufficient for triage; if
the discriminator isn't enough, that's a sign the upstream library should expose more
typed metadata, not that we should forward free-text.

**Client-server import split:**

- Server (`server/`, route handlers, server components): `import { reportSilentFallback } from "@/server/observability"` — pulls pino.
- Client (`"use client"` modules): `import { reportSilentFallback } from "@/lib/client-observability"` — Sentry-only, no pino.

The two helpers have identical signatures so call sites are mirror images.

## Key Insight

When a plan declares Brand-survival threshold = `single-user incident` and the
`## User-Brand Impact` section claims "no data leakage", a Sentry mirror added
in implementation that forwards untyped `error.message` silently breaks the claim.
The plan's section becomes stale. Rule of thumb: when adding a Sentry call site,
audit the `extra` payload against the same standard you'd apply to a log line
that gets shipped to a third party — because that's exactly what Sentry is.

## Prevention

- **Typed-only extras for auth/payments/PII-adjacent features.** When mirroring an
  error from a library that produces messages from user-supplied input
  (`@supabase/auth-js`, Stripe, mailers), forward only enum fields, never the
  free-text message. The `cq-silent-fallback-must-mirror-to-sentry` rule covers
  *that* mirroring is required; it does not constrain the payload shape.
- **Cross-check `## User-Brand Impact` against the diff.** When implementation adds
  observability call sites that the plan didn't anticipate, the plan section is the
  source of truth — update it or change the implementation. user-impact-reviewer
  catches this when the brand-survival threshold is `single-user incident`.
- **Grep for client-observability.ts before adding `Sentry.captureException` to a
  client module.** The pattern-recognition agent found this; baking it into the
  client-side cq-silent-fallback rule's body would make it discoverable up front.
- **Drift-guard tests for upstream enum unions.** When a feature hardcodes a
  subset of an external library's typed union (e.g., `VERIFIER_CLASS_CODES ⊆
  ErrorCode`), add a runtime test that reads the upstream `.d.ts` and asserts
  membership. This is cheaper than a CI grep and self-updates on dep bump.
  Pattern in `apps/web-platform/test/lib/auth/error-classifier-supabase-drift.test.ts`.
- **Negative-space tests that grep source must include semantic equivalents.**
  A regex for `error.message?.includes("code verifier")` misses
  `.toLowerCase().includes()`, `regex.test()`, and `.indexOf() >= 0`. Pattern:
  combine the literal-string regex with a windowed regex
  (`/error\.message[\s\S]{0,80}code\s*verifier/i`) to catch the broader class.

## Session Errors

None new in this resume session. Forwarded from preceding session-state.md
(captured in the original work-phase commit):

- `gh pr view 2979` failed because 2979 was an issue, not a PR — recovered via
  `gh issue view`. **Prevention:** none needed (already a clear, recoverable error).
- Supabase Management API returned 401 with `prd.SUPABASE_ACCESS_TOKEN`.
  **Prevention:** the plan deferred this to operator probe (correct decision).
- Sentry showed zero auth events in 24h. Cause was H4 (client-side `console.error`
  not mirrored) — exactly the gap this PR closes. **Prevention:** this PR.

## Related

- AGENTS.md `cq-silent-fallback-must-mirror-to-sentry` (mirroring requirement, says
  nothing about payload shape)
- AGENTS.md `hr-weigh-every-decision-against-target-user-impact` (single-user
  incident threshold)
- Learning: `2026-04-15-multi-agent-review-catches-bugs-tests-miss.md` (review
  pattern that surfaced this)
- PR #2994 (this fix)
- PR #2975 (root env-var leak fix)
- Issue #2979 (original prod outage)
