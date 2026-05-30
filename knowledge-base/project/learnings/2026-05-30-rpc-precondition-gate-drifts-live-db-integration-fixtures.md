---
title: "A new RPC precondition gate drifts live-DB integration fixtures, not just migration unit tests; and webplat exit-gate under doppler-dev surfaces env-injected-flag false-positives"
date: 2026-05-30
category: test-failures
tags: [byok-delegations, integration-tests, schema-drift, consent-gate, doppler, env-leak, vitest]
issue: 4660
pr: 4661
---

# RPC precondition-gate change drifts live-DB integration fixtures

## Problem

`tenant-integration.yml` (`Tenant integration (dev-Supabase)`) failed on every main run for ≥6 consecutive commits (2026-05-29 → 2026-05-30). Two of 14 ACs in `apps/web-platform/test/server/byok-delegations.tenant-isolation.test.ts` failed: the live dev-Supabase `resolve_byok_key_owner` RPC returned **0 rows** where the test asserted 1.

The issue body hypothesized a "dev-Supabase seeding/expiry defect." That was wrong — the test self-seeds every fixture in `beforeAll`/per-test; there is no external seed to expire.

## Root Cause

**Test-vs-schema drift introduced by a sibling PR.** PR #4627 (commit `da8b06bd`) redefined `resolve_byok_key_owner` across migrations 083 + 084 to add a **consent gate (Gate 1)**: a delegation only resolves if a current-version row exists in `byok_delegation_acceptances` for the *grantee* (`a.user_id = bd.grantee_user_id AND a.side_letter_version = current_byok_side_letter_version()`). PR #4627 updated the **migration-level** resolver unit tests but did **not** sweep the **live-DB integration test** that grants a delegation and then resolves it — it never inserted an acceptance row. After the gate landed, the two grant→resolve ACs returned 0 rows.

The sibling `AC-cross-tenant` AC kept passing because it only asserts the trigger raises `P0001` — it never resolves, so it never hits Gate 1. That masked the regression's scope.

## Solution

Add a `seedAcceptance(service, delegationId, granteeUserId)` service-role helper that inserts into `byok_delegation_acceptances`, mirroring the canonical production insert at `app/api/workspace/delegations/accept/route.ts:65-74`. Key on the **grantee** (matching the gate clause). Use `side_letter_version: BYOK_SIDE_LETTER_VERSION` **imported** from `@/server/byok-side-letter` (not hardcoded) so a future deliberate version bump can't silently re-break with the same 0-rows signature. Call it in exactly the 2 resolving ACs (3 grants total). Test-only — no schema, resolver, or app code touched. Live run: 14/14 pass.

## Key Insight

**When a migration adds a precondition gate to an RPC (a required sibling-table row, a new NOT NULL dependency, a consent/withdrawal check), the sweep target is every *live-DB integration test* that exercises that RPC's happy path — not just the migration-level unit tests.** Migration unit tests and integration fixtures drift independently; the introducing PR's author naturally updates the former and forgets the latter, especially when the integration test is opt-in (gated behind an env flag like `TENANT_INTEGRATION_TEST=1`) and not in the default CI required-check set. Cheapest gate at the introducing PR: `git grep -l '<rpc_name>' apps/web-platform/test/` and confirm every test that calls the RPC's resolving path seeds the new precondition.

## Session Errors

1. **`gh issue create` blocked: missing `--milestone`.** A PreToolUse hook (`guardrails:require-milestone`) denied the first follow-up filing. — Recovery: re-ran with `--milestone "Post-MVP / Later"`. — Prevention: already hook-enforced; the hook worked as designed. One-off, no workflow change.

2. **Webplat full-suite exit gate under `doppler run -c dev` produced 3 false failures.** `bash scripts/test-all.sh` with `TEST_GROUP=webplat` under Doppler dev reported `team-membership-resolver.test.ts` (×2, `Error: unmocked table: byok_delegations`) and `mu1-integration.test.ts` (×1, GitHub installation token 401) as failures. Neither file was touched by this PR; CI on main is green. — Recovery: re-ran both files **without** Doppler — both pass; confirmed `gh run list --workflow=ci.yml --branch main` is `success`; filed #4663. — Root cause: Doppler dev injects a BYOK-delegation feature flag that flips `server/team-membership-resolver.ts:160` into a `byok_delegations` query the unit mock doesn't cover (the documented `vi.unstubAllEnvs()`-can't-clear-process-inherited-env-var class, see [[2026-05-20-vitest-unstub-does-not-clear-process-inherited-env-vars]]), and makes mu1 attempt a live GitHub App token call. — Prevention: the work skill's Full-Suite Exit Gate should note that running the webplat shard under `doppler run -c dev` can surface env-injected-flag false-positives; the CI-equivalent run is **without** Doppler (or with CI secrets, not full dev config). Routed below.
