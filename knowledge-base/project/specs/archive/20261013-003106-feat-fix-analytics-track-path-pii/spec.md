---
title: Fix analytics-track `path` prop PII leak
issue: 2462
brainstorm: knowledge-base/project/brainstorms/2026-04-17-analytics-track-path-pii-brainstorm.md
branch: fix-analytics-track-path-pii
status: draft
---

# Spec: Fix analytics-track `path` prop PII leak (#2462)

## Problem Statement

The `/api/analytics/track` allowlist (`apps/web-platform/app/api/analytics/track/sanitize.ts`)
permits `path` as the sole forwardable prop but only length-caps the string at
200 chars. A URL path can still carry PII — emails, UUIDs, long numeric
customer IDs — which then flows verbatim to Plausible and any downstream
dashboard or export consumer. This defeats the PII-denial purpose of the
allowlist.

## Goals

1. Guarantee — at the server chokepoint — that the `path` prop value forwarded
   to Plausible cannot contain literal email addresses, UUID v4 tokens, or
   runs of 6+ consecutive digits.
2. Preserve dashboard value for legitimate KB, blog, and marketing paths
   (slugs, dates, locale prefixes, version numbers).
3. Document the caller contract in `lib/analytics-client.ts` so normalized
   paths are the normal-operation case and the scrubber is a safety net.

## Non-Goals

- Adding more allowlisted prop keys (separate security review).
- Scrubbing query strings (Plausible strips them).
- Altering throttle, CSRF, rate-limiting.
- Remediating PII already collected in Plausible (operator concern).

## Functional Requirements

- **FR1:** `sanitizeProps` replaces any substring matching an email pattern
  (`\S+@\S+\.\S+`) in the `path` value with the sentinel `[email]`.
- **FR2:** `sanitizeProps` replaces any UUID v4 pattern
  (`[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}`,
  case-insensitive) in the `path` value with the sentinel `[uuid]`.
- **FR3:** `sanitizeProps` replaces any run of 6+ consecutive decimal digits
  in the `path` value with the sentinel `[id]`.
- **FR4:** Scrub order is: email → uuid → id. Runs after length-cap slice is
  irrelevant (scrub first, then slice to 200 chars — emails can be >200 chars
  so scrubbing before slicing prevents truncation from splitting a pattern).
- **FR5:** Scrubbing only applies to the `path` key; other allowlisted keys
  (future) get per-key security review.
- **FR6:** When any pattern matches, `sanitizeProps` emits a debug log via
  the existing route-level logger reporting the pattern name(s) only
  (never the original value or the scrubbed value).
- **FR7:** `lib/analytics-client.ts#track` carries a JSDoc block documenting
  the caller contract with a concrete example of a normalized path.

## Technical Requirements

- **TR1:** Implementation lives in
  `apps/web-platform/app/api/analytics/track/sanitize.ts` (existing sibling
  module — no new files needed for the scrub logic itself).
- **TR2:** Scrub is pure-function (no I/O, no async). Tests run without
  network or Plausible fixture.
- **TR3:** RED-first tests live in
  `apps/web-platform/app/api/analytics/track/__tests__/sanitize.test.ts`
  (or whichever path matches existing convention — verify at plan time).
- **TR4:** Logger integration uses `createChildLogger("analytics-track")`
  via the existing route-level `log`. If scrub signal needs to live in
  `sanitize.ts` (pure module, no logger in scope), return the matched
  pattern names alongside `{ clean, dropped }` and let the route log them.
  Decision: extend the return type — `{ clean, dropped, scrubbed: string[] }`
  where `scrubbed` lists pattern names that fired. Route logs them.
- **TR5:** No behavior change for paths that contain none of the three
  patterns — byte-identical output for the normal case.
- **TR6:** No new dependencies; use native RegExp.

## Acceptance Criteria

See brainstorm document "Acceptance Criteria" section — spec-level criteria
repeated here for self-containment:

- Email in path → `[email]` sentinel.
- UUID v4 in path → `[uuid]` sentinel.
- 6+ digit run in path → `[id]` sentinel.
- `/blog/2026-04-17-foo` unchanged (date hyphens break long runs).
- `/docs/v12.4.1/install` unchanged (version numbers with dots).
- Query strings pass through (out of scope).
- Scrub-pattern names logged at debug; raw values never logged.
- JSDoc on client documents the contract.
- Existing tests pass; new tests added RED-first.

## Test Scenarios

| # | Input `path` | Expected clean `path` | Expected `scrubbed` |
|---|---|---|---|
| 1 | `/users/alice@example.com/settings` | `/users/[email]/settings` | `["email"]` |
| 2 | `/u/550e8400-e29b-41d4-a716-446655440000/settings` | `/u/[uuid]/settings` | `["uuid"]` |
| 3 | `/billing/customer/123456/invoices` | `/billing/customer/[id]/invoices` | `["id"]` |
| 4 | `/blog/2026-04-17-foo` | `/blog/2026-04-17-foo` | `[]` |
| 5 | `/docs/v12.4.1/install` | `/docs/v12.4.1/install` | `[]` |
| 6 | `/?q=hello` | `/?q=hello` | `[]` |
| 7 | `/u/alice@example.com/550e8400-e29b-41d4-a716-446655440000` | `/u/[email]/[uuid]` | `["email","uuid"]` |
| 8 | `/kb/docs/getting-started` | `/kb/docs/getting-started` | `[]` (regression: current happy path) |
| 9 | non-string `path` (number) | passes through untouched | `[]` |
| 10 | `path` longer than 200 chars, no PII | truncated to 200 | `[]` |

## Out of Scope / Future

- Scrubbing query strings if Plausible ever starts retaining them.
- Applying the scrubber to future allowlisted keys — decided per-key.
- Automated dashboard cleanup of previously-collected PII.

## PR Requirements

- Title: `fix(analytics-track): scrub PII from path prop (#2462)`
- Body must include `Closes #2462`.
- Label `type/security`.
- Label `priority/p3-low` (matches issue).
