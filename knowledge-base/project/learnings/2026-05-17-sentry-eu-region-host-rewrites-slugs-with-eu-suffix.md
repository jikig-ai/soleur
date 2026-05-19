---
date: 2026-05-17
classification: bug-fixes
sources:
  - "PR-β #3945 §7.4 verify probe"
  - "ADR-031 glossary line 54 (needs update)"
  - "plan task 8.9 (needs update)"
related:
  - "[[2026-05-16-brainstorm-premise-cascade-and-playwright-handoff-discipline]]"
tags:
  - sentry
  - api-routing
  - org-subdomain
  - branch-c
title: "Sentry eu.sentry.io rewrites org-slugs ending in -eu to the literal 'eu' org via activeorg-cookie hijack"
---

# Sentry `eu.sentry.io` rewrites org-slugs ending in `-eu` to the literal `eu` org via `activeorg`-cookie hijack

## The bug

When an unauthenticated request hits `https://eu.sentry.io/api/0/organizations/jikigai-eu/`
with only `Authorization: Bearer <token>` (no `Cookie:` header), Sentry's auth
middleware returns:

```http
HTTP/2 302
location: /api/0/organizations/eu/
set-cookie: session=eyJhY3RpdmVvcmciOiJldSJ9:...; Domain=.sentry.io
```

The base64-decoded cookie is `{"activeorg":"eu"}`. The server silently
rewrites the URL path's org-slug from `jikigai-eu` to `eu` (which is either
a Sentry-internal default or an existing org owned by another tenant), then
the follow-up request fails with `401 Invalid token` because the token isn't
scoped to that other org.

Reproduced for every org-scoped path tested:

| Path                                                       | http (post-redirect) | rewritten to                                |
|------------------------------------------------------------|---------------------|---------------------------------------------|
| `/api/0/organizations/jikigai-eu/`                         | 401                 | `/api/0/organizations/eu/`                  |
| `/api/0/organizations/jikigai-eu/projects/`                | 401                 | `/api/0/organizations/eu/projects/`         |
| `/api/0/projects/jikigai-eu/web-platform/`                 | 401                 | `/api/0/projects/eu/web-platform/`          |
| `/api/0/projects/jikigai-eu/web-platform/keys/`            | 401                 | `/api/0/projects/eu/web-platform/keys/`     |

The cookie's `Domain=.sentry.io` shape means the rewrite would *spread* to
any subsequent same-session request if cookies were honored. With `Cookie:`
suppressed, the rewrite still happens server-side via path-pattern matching.

## The fix: use the per-org subdomain as `SENTRY_API_HOST`

Sentry exposes every org at `https://<org-slug>.sentry.io/...` as a stable,
slug-explicit subdomain. Org-scoped probes work cleanly there:

| Path on `jikigai-eu.sentry.io`                             | http (direct, no redirect) |
|------------------------------------------------------------|----------------------------|
| `/api/0/organizations/jikigai-eu/`                         | **200**                    |
| `/api/0/projects/jikigai-eu/web-platform/`                 | **200**                    |
| `POST /api/0/organizations/jikigai-eu/releases/` (with `{"version":"...","projects":["web-platform"]}` body) | **201**                    |

The org-subdomain bypasses the `eu.sentry.io` slug parser entirely.

## Plan impact (PR-β scope)

ADR-031 documents `EU-region API base_url is eu.sentry.io/api/` as canonical
(L54 of `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md`).
That's correct only for region-wide / slug-less endpoints (`/users/me/`,
`/auth/*`); it's **wrong for org-scoped paths** when the org's slug ends in
`-eu`. The PR-β plan task 8.9 (atomic Terraform `main.tf:30` flip) and the
audit-gate workflow default (`SENTRY_API_HOST: ${{ secrets.SENTRY_API_HOST
|| 'eu.sentry.io' }}`) need adjusting:

- **`SENTRY_API_HOST=jikigai-eu.sentry.io`** (Doppler `prd`, GH repo secret).
- **`SENTRY_URL=https://jikigai-eu.sentry.io/`** for sentry-cli source-map
  upload target.
- **Terraform `apps/web-platform/infra/sentry/main.tf:30`** `base_url` flip
  target: `"https://jikigai-eu.sentry.io/api/"` (NOT `https://eu.sentry.io/api/`).
- **Audit-gate workflow** (`.github/workflows/sentry-audit-gate.yml`) default
  should be derived from `SENTRY_ORG`, not a hardcoded regional host:
  `SENTRY_API_HOST: ${{ secrets.SENTRY_API_HOST || format('{0}.sentry.io', secrets.SENTRY_ORG) }}`
  — or simpler, drop the `||` default and require the secret to be set
  (fail-loud if absent, matching the Kieran P0-1 fail-loud pattern).
- **Audit-script region-probe loop** (`apps/web-platform/scripts/sentry-monitors-audit.sh`
  L46) candidates list: currently planned as `eu.sentry.io de.sentry.io
  sentry.io`. Should include `${SENTRY_ORG}.sentry.io` as the FIRST candidate,
  with the regional hosts as fall-throughs only for the slug-less probes
  (`/users/me/`). For org-scoped probes (Gates 1-4) the only correct host is
  `${SENTRY_ORG}.sentry.io`.

## Why the regional-base-url framing is wrong

The plan was anchored on "the EU API base_url is `eu.sentry.io/api/`" because
Sentry's docs and the `jianyuan/sentry` Terraform provider examples document
that pattern. But the provider's documented base_url is a region-routing
*default*; for org-scoped operations the provider should use the org-subdomain
shape, OR the regional host with a session-cookie that pins activeorg
correctly. Neither is feasible from CI (no browser session), so the
org-subdomain is the only stable shape.

Anchoring on the regional host was a premise-cascade failure of the same shape
as `2026-05-16-brainstorm-premise-cascade-and-playwright-handoff-discipline.md`
— ADR-031 documents the regional-host convention, the plan cited the ADR,
PR-α landed the ADR update — but no probe was ever run from `eu.sentry.io`
against a real org slug to verify the documented convention actually worked
for slug-scoped endpoints. The slug-rewrite was only caught at PR-β §7.4
verify probe, AFTER the new DE org provisioning was complete.

## Prevention

Before declaring an external host the canonical base for a documented
convention in an ADR, run at least one slug-scoped probe (not just `/users/me/`
or `/auth/login/`) and confirm the path returns 200 without redirect. Cookie
behavior matters: an `activeorg` cookie redirect that looks like a routing
nicety can silently zero out a downstream Terraform integration.

## Re-evaluation triggers

- Sentry may fix the `eu.sentry.io` slug-parser to honor `Authorization:`
  bearer-token's actual org scope instead of falling back to inferred-from-
  hostname `activeorg`. If so, the canonical `eu.sentry.io/api/` base_url
  becomes usable again. Re-probe with `curl -H "Authorization: Bearer X"
  https://eu.sentry.io/api/0/organizations/jikigai-eu/` — if HTTP is 200
  directly (no 302), the bug is fixed and ADR-031 can revert to the regional
  pattern.
- If the org is ever renamed to a slug NOT ending in `-eu`/`-us`/`-de`/etc.,
  re-test whether the slug-rewrite still fires. The current hypothesis is
  that the rewrite is region-code-suffix-triggered; an unrelated slug
  (`jikigai-prod`, say) may not hit the parser.
