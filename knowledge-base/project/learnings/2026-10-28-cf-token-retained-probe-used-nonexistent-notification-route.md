---
title: A retained-scope probe must use Cloudflare's versioned Alerting API route
date: 2026-10-28
category: infrastructure
tags: [cloudflare, api-tokens, retained-scope, fail-closed]
---

# Learning: A retained-scope probe must use Cloudflare's versioned Alerting API route

## Problem

The `cf-token-scope` default-token baseline queried `/accounts/{account_id}/notification_policies`. Cloudflare returned HTTP 404 with error 10404 (`No route for that URI`), so the retained-scope check failed closed even though this was not evidence of a dropped Notifications permission. Treating that 404 as permission loss would misdiagnose the token; treating it as success would weaken the safety gate.

## Solution

Cloudflare's official List Notification Policies endpoint is `GET /accounts/{account_id}/alerting/v3/policies` (https://developers.cloudflare.com/api/resources/alerting/subresources/policies/methods/list/). A read-only call to that documented route with the same profile credential returned an authorized 200 response. Update the profile's probe URL and its URL-dispatch tests together, then require the complete baseline to pass before widening; the corrected endpoint must also be exercised by the post-widen assert.

## Key Insight

A 404 is only meaningful to a permission classifier after the route itself is established. Pin endpoint URLs to the provider's current official API reference and use live authorized responses to distinguish a missing route from a missing scope. Keep the gate fail-closed until its retained control is corrected; do not bypass it by editing the token first.

## Session Errors

1. The first default-token baseline exited 3 because the Notifications control used the nonexistent route. The API reference and a direct read-only call established the correct route; no token permissions were changed. — **Prevention:** verify every profile endpoint against the official API reference and pin the live route in tests before using the profile as a production mutation precondition.
2. A credential could not be confidently matched to a dashboard record, so no dashboard edit was made. — **Prevention:** positively match the exact credential to its profile through an approved source before editing permissions; stop if the match is ambiguous.

## Tags

category: infrastructure
module: plugins/soleur/skills/cf-token-scope
