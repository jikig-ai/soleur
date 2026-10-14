---
title: Analytics track `path` prop PII hardening
date: 2026-04-17
topic: analytics-track-path-pii
issue: 2462
related:
  - knowledge-base/project/specs/feat-analytics-track-hardening/
  - knowledge-base/project/brainstorms/2026-04-10-product-analytics-instrumentation-brainstorm.md
---

# Brainstorm: analytics-track `path` prop PII hardening

## What We're Building

Defense-in-depth for `/api/analytics/track` so the allowlisted `path` prop cannot
carry PII (email addresses, UUIDs, long numeric IDs) through to Plausible and
any downstream dashboard/export consumers.

Two-layer fix:

1. **Server-side PII scrub** inside `sanitizeProps` — replace matched tokens
   with fixed placeholder sentinels (`[email]`, `[uuid]`, `[id]`) before the
   value is forwarded to Plausible.
2. **Client-side contract** — JSDoc on `lib/analytics-client.ts#track` that
   explicitly requires callers to pass normalized paths
   (`/users/[uid]/settings`, not `/users/alice@example.com/settings`).

## Why This Approach

The issue (#2462) flagged three alternatives, all contested. Reasoning:

### Rejected: approach 1 (strict regex `^/[A-Za-z0-9/_-]*$`)

Breaks every legitimate path that contains a dot (`/blog/2026-04-17-foo`), a
tilde, a query string, or a locale prefix. A known-failing allowlist is not a
security control — callers would work around it by stripping characters before
sending, losing dashboard fidelity.

### Rejected: approach 3 alone (pure client responsibility)

A single careless caller defeats the entire server guarantee. The security PR's
purpose is to enforce PII-denial at the chokepoint, not to produce a runbook.
"Document that callers must behave" is not a server-side security property.

### Chosen: approach 2 + approach 3 (hybrid)

Server scrub as defense-in-depth + client doc as the primary path. This gives:

- **Real server guarantee:** after scrubbing, the claim "the allowlist protects
  PII" is actually true, not conditional on caller behavior.
- **Dashboard fidelity preserved:** the three scrub patterns (literal email,
  UUID v4 format, 6+ consecutive digits) do not appear in any legitimate KB,
  blog, or marketing path slug. The scrubber is essentially never expected to
  fire in normal operation.
- **Low blast radius:** only 3 call sites exist today
  (`kb-chat-content.tsx:63, 93, 94`), all passing KB content paths. Zero risk
  of existing callers hitting the scrubber.

### Dashboard-value tradeoff, concretely

The issue raised a concern that scrubbing "loses dashboard value when path
legitimately contains those tokens." Walking through each pattern:

- **Email (`user@host.tld`):** a legitimate path containing a literal email is
  always PII. There is no goal-measurement reason to group pageviews by the
  email in the URL.
- **UUID v4 (`xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx`):** a literal UUID in a
  slug is always an opaque ID. `/docs/uuid-explainer` (human-readable slug) is
  not affected; only `/users/550e8400-e29b-41d4-a716-446655440000` is.
- **6+ consecutive digits:** covers customer IDs and similar. Dates
  (`2026-04-17`) are split by hyphens into ≤4-digit runs and pass through.
  Version numbers `v12.4.1` pass through. Pricing `$9900` (4 digits) passes.
  A legitimate 6-digit-consecutive token in a path slug is exceptional.

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| Server scrub is mandatory, not optional | Defense-in-depth — the security PR must ship a real server guarantee, not a doc. |
| Scrub patterns: email, UUID v4, 6+ digit runs | Narrow set that covers the three PII vectors named in #2462 without touching legitimate path semantics. |
| Replacement tokens are fixed sentinels (`[email]`, `[uuid]`, `[id]`) | Preserves path structure; Plausible groups scrubbed paths together, which is the correct aggregation for PII-bearing paths. |
| Length cap of 200 chars remains | Independent control; scrub runs before the slice. |
| Apply scrubber only to `path` prop, not to all string values | `path` is the only allowlisted key today. If future keys are added, they get a security review that decides per-key scrubbing. |
| Client doc via JSDoc on `track()` | Callers see the contract in their IDE at the call site. |
| Log when scrubber fires (structured, no PII in log) | Operator signal that a caller is misbehaving; log the scrub-pattern name, not the original value. |
| Close #2462 on merge | Single-issue close. PR body includes `Closes #2462`. |

## Open Questions

None — design is scoped. Implementation order and file-level details go in
the plan.

## Acceptance Criteria

- `sanitizeProps({ path: "/users/alice@example.com/settings" }).clean.path` →
  `/users/[email]/settings`
- `sanitizeProps({ path: "/u/550e8400-e29b-41d4-a716-446655440000/settings" }).clean.path` →
  `/u/[uuid]/settings`
- `sanitizeProps({ path: "/billing/customer/123456/invoices" }).clean.path` →
  `/billing/customer/[id]/invoices`
- `sanitizeProps({ path: "/blog/2026-04-17-foo" }).clean.path` →
  `/blog/2026-04-17-foo` (date digits preserved — max 4 consecutive)
- `sanitizeProps({ path: "/docs/v12.4.1/install" }).clean.path` →
  `/docs/v12.4.1/install` (version numbers preserved)
- `sanitizeProps({ path: "/?q=hello" }).clean.path` → `/?q=hello` (query
  strings pass through unchanged; they are out of scope — Plausible strips
  query strings on its side anyway, and the field is still length-capped)
- JSDoc on `lib/analytics-client.ts#track` documents the caller contract with
  a concrete example.
- Structured debug log fires when a pattern is matched, reporting the
  pattern name (`email` / `uuid` / `id`) — not the raw value.
- Existing test suite for `sanitize.ts` continues to pass; new tests lock in
  scrub behavior with RED-first assertions.

## Non-Goals

- Adding more allowlisted prop keys — that remains a separate security review.
- Scrubbing log-injection vectors (already handled by `sanitizeForLog`).
- Modifying throttle, CSRF, or rate-limiting layers.
- Dashboard-side remediation of already-collected PII (Plausible data
  retention and scrubbing are out of scope; operator concern).
- Stripping query strings at the server — Plausible's own pipeline handles this.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

No domain leaders spawned. Rationale: this is an internal server-side
security hardening fix with zero user-visible surface, no marketing or product
implications, no change to legal/privacy posture (in fact, strictly improves
it). The AGENTS.md rule `hr-new-skills-agents-or-user-facing` applies only to
new user-facing capabilities; this change tightens an existing chokepoint
without adding capability.
