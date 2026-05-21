---
title: "Sentry Internal Integration tokens look like legacy User Auth Tokens — disambiguate via /api/0/ identity surface"
date: 2026-05-21
category: integration-issues
module: observability
component: apps/web-platform/scripts/sentry-monitors-audit.sh
related_issues: [3861, 3849, 3958, 3962]
related_pr: 4209
related_audit: knowledge-base/legal/audits/2026-05-21-sentry-token-t3-resolution.md
---

## TL;DR

Sentry's legacy 64-hex token format (no `sntryu_` / `sntrys_` prefix) is
shared by **two auth classes** with very different behavior:

- **User Auth Tokens** (Personal Tokens), minted at `/settings/account/api/auth-tokens/`
- **Internal Integration tokens** (`SentryApp status: internal`), minted when an
  Internal Integration is created on an org at `/settings/<org>/developer-settings/`

The token bytes look identical (64 hex chars). The behavior at API surfaces
is not. **Do not infer auth class from token shape alone.** Disambiguate by
hitting `/api/0/` (always works) and reading `user.email` + `auth.scopes`.

## Disambiguation table

| Surface | User Auth Token | Internal Integration Token |
|---|---|---|
| `GET /api/0/` `.user.email` domain | real user email (`@<real-domain>`) | `<integration-slug>-<uuid>@proxy-user.sentry.io` |
| `GET /api/0/users/me/` | HTTP 200 with real user record | **HTTP 403** "no permission" |
| `GET /api/0/organizations/` (any host) | orgs the user is a member of (≥1 typical) | **`[]`** — cannot enumerate orgs |
| `GET /api/0/organizations/<bound-slug>/` | 200 for member orgs, 403/401 otherwise | 200 for installation org, 403 for any other slug |
| `GET /api/0/organizations/<bound-slug>/sentry-apps/` | lists integrations on the org (if `org:read` scope) | lists integrations including the token's own (slug + scopes match the token's `auth.scopes` byte-for-byte) |
| `auth.scopes` shape | user-selected at mint time | inherited from integration definition (standard CI set: `org:ci`, `org:read`, `project:read`, `project:releases`, `project:write`) |
| Audit-log surface | `<org>/audit-log` records mint + revoke | `<org>/audit-log` records integration install + remove (NOT token mint) |

## Why the disambiguation matters

When auditing a 401/403 surface on a Sentry org slug, the natural inference
is "the token holder is not a member of that org." For User Auth Tokens
that's actionable advice (add the user to the org). For Internal Integration
tokens it's a category error — the proxy-user identity is by-design bound to
exactly one org (the integration's installation org), and "adding it to
another org" is not a thing Sentry exposes. The fix-path is to either (a)
install the integration on the second org and use that token, or (b) use a
User Auth Token if cross-org access is actually needed.

The 2026-05-17 → 2026-05-21 Sentry residency incident (#3861) burned a lot
of investigation cycles on "the token-holder is not a member of `jikigai`"
because the auth-class label was assumed to be User Auth ("Personal Token"
in the spec — the public-facing dashboard-mint affordance everyone sees
first). The token was actually an Internal Integration token, and the
disambiguation step that would have resolved the question instantly was a
single `curl /api/0/` call to read `user.email`. Full audit:
`knowledge-base/legal/audits/2026-05-21-sentry-token-t3-resolution.md`.

## Pattern: disambiguate first, debug second

Future Sentry-token investigations should run this 30-second probe FIRST,
before any membership / scope / region-routing theorizing:

```bash
doppler run -p soleur -c prd --command \
  'curl -s -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
       "https://sentry.io/api/0/" \
   | jq "{
       user_email: .user.email,
       scopes: .auth.scopes,
       date_joined: .user.dateJoined
     }"'
```

- `user.email` ending in `@proxy-user.sentry.io` → Internal Integration. Stop guessing about user membership; check `sentry-apps/` on the bound org.
- `user.email` is a real domain → User Auth Token. Check `/users/me/` for membership inventory.

## Sentry's overlapping token taxonomy (for the record)

Per Sentry's docs as of 2026-05:

| Token type | Prefix | Mint surface | Auth class |
|---|---|---|---|
| User Auth Token (Personal) | `sntryu_<32-hex>` (post-2024) OR `<64-hex>` (legacy) | `/settings/account/api/auth-tokens/` | user-scoped |
| Org Auth Token | `sntrys_<32-hex>` (post-2024) | `/settings/<org>/auth-tokens/` | org-scoped, no user identity |
| Internal Integration Token | `<64-hex>` (no prefix) | `/settings/<org>/developer-settings/<integration>/dashboard/` | integration-scoped via proxy-user |
| Public Integration Token | varies by integration | OAuth-like grant flow | per-grant |
| DSN secret | path-segment of DSN URL | per-project | ingest-only, no API surface |

The 64-hex format collision between (legacy) User Auth and Internal
Integration is the load-bearing source of the disambiguation problem.

## Tags

category: integration-issues
module: observability
component: apps/web-platform/scripts/sentry-monitors-audit.sh
