---
title: "Shared-live-DB integration tests comparing a GoTrue-clock JWT iat against a Postgres-clock timestamp flake under concurrent load"
date: 2026-05-30
category: test-failures
tags: [tenant-isolation, integration-tests, clock-skew, supabase, gotrue, postgres, flaky-test, check_my_revocation]
pr: 4664
---

# Cross-service clock-skew flake in shared-live-DB integration tests

## Problem

`tenant-integration.yml` ran `*.tenant-isolation.test.ts` against live dev-Supabase, all files concurrently (vitest default file parallelism). `workspace-member-revocation.tenant-isolation.test.ts` (#4307) passed in isolation and on every prior main run, but flaked red (`expected false to be true`, `revoked:false`) on the post-merge run for the #4660 fix — the moment the byok integration test started passing (running to completion, adding concurrent DB load) instead of failing fast.

## Root Cause

Tests 3.2.1/3.2.2 mint user B's JWT (`iat` set by **Supabase GoTrue**, the Auth server, **second-precision**), remove B (writing `workspace_member_removals.revoked_after = now()`, set by the **Postgres** clock), then call `check_my_revocation(p_jwt_iat)` whose predicate is `revoked_after > p_jwt_iat` (strict, mig 067:87). GoTrue and Postgres are independently-NTP'd Supabase services. Under concurrent load the Postgres clock can lag GoTrue's by more than the ~1-2s mint→remove gap, making `revoked_after <= floor(iat)` → the RPC's `NOT FOUND` branch fires → `revoked:false`. The removal row provably exists (the `toHaveLength(1)` assertion passes first), so the only failure path is the cross-clock timestamp comparison.

The suite's *own* clock-skew test (3.2.3) was already robust: it derives both iat probes from the DB-written `revoked_after` — staying on **one clock** — and so has no cross-service skew to absorb. Only the positive-control tests used the raw GoTrue-minted iat against the DB clock.

## Solution

Backdate the iat the positive-control probes pass by a 30s `PROBE_IAT_BACKDATE_SEC` buffer (test-only). This models the realistic "JWT issued well before removal" case and absorbs cross-service skew. The production `check_my_revocation` RPC and its deliberate strict-`>` fail-safe design are untouched; the boundary stays covered by 3.2.3. The backdate is provably safe: `revoked_after > iat` is monotone in the backdate direction, so a smaller iat can only flip a row toward `revoked=true` (the asserted direction) — it can never manufacture a false pass, and the same-iat negative control (owner A → `revoked=false`) proves the RPC still discriminates.

## Key Insight

**Live-DB integration tests that share one database and run concurrently must not compare a value stamped by one service's clock against a value stamped by another's with a strict, near-now boundary.** The two canonical fixes: (1) derive both sides of the comparison from a single clock (read the DB-written timestamp, probe relative to it — what 3.2.3 does), or (2) widen the gap with a deliberate buffer so sub-second / ±N-second cross-service skew can't cross the boundary (what the positive-control fix does). A test that's green in isolation but red under the full concurrent suite is the signature — the load doesn't change the logic, it widens the skew window. Relatedly: such a flake can stay *hidden* behind an unrelated failing test in the same suite (here byok failed fast, masking the latent skew flake) and surface only when the masking failure is fixed. See [[2026-05-30-rpc-precondition-gate-drifts-live-db-integration-fixtures]] for the byok fix that exposed this.
