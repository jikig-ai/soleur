---
lane: single-domain
---

# Feature: Correct the Cloudflare Notifications probe route

## Problem Statement

The `cf-token-scope` `default-token` profile's retained Notifications probe queries
`/accounts/{account_id}/notification_policies` — a route Cloudflare does not serve (HTTP 404 /
error 10404, `No route for that URI`) — so the retained-scope baseline exits 3 (fail-closed) on
every run and the skill's widen precondition can never be met, even though the token's
Notifications permission is intact. Issue #11480.

## Goals

- Dispatch the Notifications probe to Cloudflare's documented
  `GET /accounts/{account_id}/alerting/v3/policies` endpoint (keep `?per_page=1` per the issue's
  explicit prescription and the `DT_ROWS` print/run-parity convention).
- Update the SKILL.md controls-table row and the URL-dispatch test expectations together.
- Exercise the corrected endpoint in the post-widen assert (`--expect-lb-scopes`).
- Keep the change read-only and preserve the fail-closed classifier.

## Non-Goals

- No widening or other mutation of Cloudflare permissions or tokens; no Doppler writes, no
  infrastructure change.
- No classifier relaxation — a 404 on the corrected route still fails closed (exit 3).
- No profile additions or unrelated route/permission coverage expansion.
