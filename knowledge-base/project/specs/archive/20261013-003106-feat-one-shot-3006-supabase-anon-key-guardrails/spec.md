---
title: "fix: extend Supabase env-var guardrails to NEXT_PUBLIC_SUPABASE_ANON_KEY"
type: fix
issue: 3006
pr: 3007
date: 2026-04-28
status: implemented
---

# Spec — anon-key build-arg guardrails (issue #3006)

## Problem

`secrets.NEXT_PUBLIC_SUPABASE_ANON_KEY` (a GitHub repo secret feeding the Docker build via `reusable-release.yml`) silently drifted to a test-fixture JWT during a credentials rotation on 2026-04-28. The placeholder JWT was inlined into the production bundle, breaking sign-in for every OAuth/email-OTP/email-password user. Identical class to the URL incident PR #2975 fixed; the URL-only fix was structurally insufficient because each `NEXT_PUBLIC_*` build-arg has its own shape contract.

## Functional Requirements

- **FR1** Pre-build CI assertion in `reusable-release.yml` rejects placeholder/non-canonical JWTs before `docker/build-push-action`.
- **FR2** Doppler-side shape check in `verify-required-secrets.sh` rejects placeholder JWTs at Doppler write time.
- **FR3** Runtime guard in `client.ts` throws on module load if a placeholder JWT slipped through.
- **FR4** Preflight Check 5 black-box-tests the deployed bundle's inlined JWT post-deploy.
- **FR5** All four gates assert the same claims contract: `iss=="supabase"`, `role=="anon"`, `ref` matches `^[a-z0-9]{20}$` and is not in the placeholder set, `ref` matches the URL's canonical first label.

## Acceptance Criteria

See the implementation plan: `knowledge-base/project/plans/2026-04-28-fix-supabase-anon-key-guardrails-plan.md` (AC1–AC16).

Summary:
- 18 unit tests in `apps/web-platform/test/lib/supabase/anon-key-prod-guard.test.ts` (RED → GREEN cycle complete, 18/18 passing).
- 4 anon-key-fixture test files (`byok.integration.test.ts`, `agent-env.test.ts`, `fixtures/qa-auth.ts`, `server/health-supabase.test.ts`) remain green (test-suite blast-radius gate held by `NODE_ENV !== "production"` in the validator).
- All four mirrored sites updated with edit-together comment blocks.
- PR body uses `Closes #3006` and `Ref #2980` (only the `_ANON_KEY` portion of #2980 ships here).

## NFR Impact

- **Auth availability**: defense-in-depth gates reduce MTTR for the anon-key class from "hours of operator-driven diagnosis" to "build-time hard-fail" (AC1) plus "post-deploy black-box probe" (AC8).
- **Security**: `role == "anon"` assertion is load-bearing — rejects service-role-key paste, which would silently bypass RLS for every browser visitor (worse failure mode than the test-fixture leak).
- **No new dependencies**: reuses `jq`, `dig`, `base64`, `cut` from existing CI runner toolchain.

## Test Scenarios

See the plan's `## Test Scenarios` section. QA verification: `/soleur:qa` runs the post-deploy bundle probe and the browser-OAuth smoke flow.

## Out of Scope

- Generalizing to the other 4 `NEXT_PUBLIC_*` build-args (#2980 — `Ref` not `Closes`).
- Doppler-only build-args migration (#2981 — Option B, deferred).
- JWT signature verification (anon keys are public; signatures are not the appropriate gate).

## References

- Issue: #3006
- Plan: `knowledge-base/project/plans/2026-04-28-fix-supabase-anon-key-guardrails-plan.md`
- Predecessor learning: `knowledge-base/project/learnings/bug-fixes/2026-04-28-oauth-supabase-url-test-fixture-leaked-into-prod-build.md`
- New learning: `knowledge-base/project/learnings/bug-fixes/2026-04-28-anon-key-test-fixture-leaked-into-prod-build.md`
- Predecessor PR: #2975 (URL guardrails)
- Sentry mirror: PR #2994
- Generalization: #2980, #2981
