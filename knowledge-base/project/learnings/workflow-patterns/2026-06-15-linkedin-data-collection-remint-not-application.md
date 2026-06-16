---
title: LinkedIn org data collection needed a token re-mint, not a Marketing API application
category: workflow-patterns
tags: [linkedin, oauth, community-monitor, scopes, playwright, vendor-api]
issue: 4049
date: 2026-06-15
---

## Problem

The community monitor's LinkedIn `fetch-metrics`/`fetch-activity` were hardcoded stubs that
exited 1, citing "requires Marketing API (MDP partner approval)." Issue #4049 was filed to
track applying for the LinkedIn Marketing Developer Platform. That premise was **wrong**, and
it would have triggered a needless partner-approval application (with real rejection risk —
a rejected app can foreclose access for the app's lifetime).

## Solution

Verified live (2026-06-15) via the LinkedIn Developer Portal token generator
(`https://www.linkedin.com/developers/tools/oauth/token-generator?clientId=<id>`): the org's
developer app (Soleur Community, `229658411`) was **already authorized** for the org-read
scopes — `r_organization_social`, `rw_organization_admin`, `r_organization_followers`. The
org token simply hadn't been minted with them (it carried `w_organization_social` only, which
is why posting worked but reads 403'd).

The fix was a **token re-mint** with the read scopes added, then implementing the fetch
functions against the LinkedIn REST API — no application, no new product, no MDP. `fetch-metrics`
uses `organizationalEntityShareStatistics` (aggregate engagement) + `networkSizes` (single
follower total); `fetch-activity` uses the Posts author-finder. Aggregate-only (no per-member
data, no follower-list, no demographic facets) — within the DPD/Article-30/LIA-disclosed
joint-controller Art. 6(1)(f) scope.

## Key Insight

**Before filing a vendor "apply for access" tracker, check what the app is already authorized
for.** A capability stub citing a vendor approval is a claim to verify, not a fact. For LinkedIn,
the developer-app token generator lists exactly the scopes the app may request — that list is
the authoritative re-mint-vs-apply discriminator. Token introspection
(`/oauth/v2/introspectToken` with client_id+secret) shows what scopes a token *currently*
carries; the generator shows what it *could* carry. The gap between the two is a re-mint, not
an application.

## Session Errors

1. **Initially treated #4049's "file MDP access request" framing as accurate** — would have
   driven a needless partner-approval cycle. Recovery: probed the token generator + introspection,
   found the read scopes already authorized. Prevention: this learning + the corrected #4049.

2. **LinkedIn token generator does not complete under Playwright automation** — the mint step
   opens an embedded LinkedIn "Sign in" / password re-auth screen (screenshot-confirmed) that
   headless automation cannot clear (credential entry — a true operator-only gate). The
   credential *reads* (client_id/secret extraction, scope list) automate fine; the *mint* needs
   the operator's authenticated browser. Prevention: for LinkedIn token re-mints, hand the
   3-click generate to the operator (they're already signed in), then automate everything
   downstream (introspect → store in Doppler → sync GH secret → implement).

## Tags

linkedin, oauth, community-monitor, scopes, playwright, vendor-api, remint-not-application
