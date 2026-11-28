---
title: The Cloudflare dashboard edge refuses in-page writes, so the stub must too
date: 2026-11-28
category: integration-issues
module: cloudflare-old-login-token-remint (Phase 5 browser bodies)
tags: [playwright, cloudflare, dashboard, test-harness, sha-pin]
issue: 12931
pr: 13125
---

# Learning: the dashboard edge refuses in-page writes, and my stub let them through

## What happened

`p5-mint.js` created tokens with an in-page `fetch` POST to `dash.cloudflare.com/api/v4/accounts/<acct>/tokens`.
In a signed-in session on 2026-11-28 it got `403 text/html` twice, while the same run's in-page GETs answered JSON.
An in-page DELETE had already been refused the same way on 2026-11-26, which is why the body's cleanup DELETE was
Node-side (`page.request.delete`). Nobody applied that to the POST, because an in-page POST to `/user/tokens`
had worked once. The browser suite was green because its stub page answered an in-page DELETE with `html(403)`
and an in-page POST with success.

## Rule

- Send every dashboard API **write** (POST, PUT, PATCH, DELETE) through `page.request.*`. Read the atok and origin
  from the page just before the call, and send `x-atok`, `x-cross-site-security: dash`, `maxRedirects: 0` and
  `failOnStatusCode: false`. In-page GETs work and can stay in-page.
- When one HTTP method is measured refused, the stub refuses that whole class of request (every write method),
  not only the method that was measured. A stub that refuses only the observed method passes the next method's
  failure.
- An HTML 403 after a POST is not a reason to retry. Stop and read it: re-minting in a loop burned a sink and an
  attempt on each of two keys.

## See also

- `knowledge-base/engineering/operations/runbooks/cloudflare-account-migration.md`, `## Revoke recipe` step 3
- `2026-11-28-my-late-atok-stub-could-not-see-a-wait-placed-before-the-goto.md`: the same lesson for the atok race
