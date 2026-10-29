---
lane: single-domain
---

# Feature: Correct the Cloudflare Notifications probe route

## Problem Statement

The `cf-token-scope` `default-token` profile sends its retained Notifications probe to the nonexistent `/accounts/{account_id}/notification_policies` route. That produces a 404 and fails the profile even though Cloudflare's documented `/accounts/{account_id}/alerting/v3/policies` endpoint is available to the existing token.

## Goals

- Dispatch the Notifications probe to Cloudflare's official Alerting API list endpoint.
- Test URL dispatch, authorized Notification response classification, fail-closed 404 handling, and unchanged neighboring profile routes.
- Keep the change read-only and preserve the current fail-closed classifier.
- Include the already-authored route-correction learning byte-identically in the corrective PR.

## Non-Goals

- Do not widen Cloudflare permissions, rotate or otherwise mutate tokens, write Doppler values, or change infrastructure.
- Do not dispatch workflows or perform any cutover action.
- Keep web-2 at weight 0 and structurally excluded until the cutover soak marker.
- Do not relax 404 handling or alter the rulesets profile.

## Functional Requirements

### FR1: Use the documented Notifications endpoint

The `default-token` retained Notifications row dispatches `GET /accounts/{account_id}/alerting/v3/policies` using the existing account identifier and account-list response contract.

### FR2: Preserve fail-closed classification

A Notification response is authorized only for HTTP 200 with Cloudflare `success == true` and an array-valued `result`. A 404, degraded 200, malformed response, or other non-authorized status remains a hard probe failure.

### FR3: Preserve existing profile behavior

The Tunnel, Access, DNS, and two Load Balancer routes remain unchanged. The default-token profile's two LB 403 rows remain neutral only in baseline mode, and the rulesets profile keeps its existing URLs and exit behavior.

### FR4: Preserve the learning artifact

The corrective PR includes `knowledge-base/project/learnings/2026-10-28-cf-token-retained-probe-used-nonexistent-notification-route.md` byte-identically, SHA-256 `871e2785b041342a0c4e9180c39b01545e7883d7646e5d6117f686d6ccd9e250`; retain the source copy in the main checkout.

## Technical Requirements

### TR1: Reuse the existing table and classifier

Update the `DT_ROWS` Notifications URL and the shell test's curl mock dispatch. Do not add a new profile, special-case 404 exception, permission change, or alternate classifier path.

### TR2: Pin behavior with the existing shell suite

Extend `plugins/soleur/test/cf-token-scope.test.sh` to verify the full Notifications URL, successful array-shaped 200 classification, hard failure on Notification 404, and regression coverage for all existing profile routes.
