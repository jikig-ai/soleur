---
title: "chore: migrate the docs site to Cloudflare Pages"
brand_survival_threshold: single-user incident
---

# chore: migrate the docs site

## User-Brand Impact

**If this lands broken, the user experiences:** the apex serving a Cloudflare
error page, a stale build, or NXDOMAIN — the only surface a prospective user
meets before signing up, dark or wrong. The 2026-08-16 precedent (#6691) was an
~8h15m apex outage from the same host, and it is the reason this plan exists.

**Brand-survival threshold:** `single-user incident`

## Rollout

The cutover is ordered so the new address exists before the old one is removed.
Deployed behind a two-call sequence with a rollback at every step.
