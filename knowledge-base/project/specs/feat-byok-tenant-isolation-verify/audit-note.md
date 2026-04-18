# BYOK Per-Tenant Isolation — Audit Note

**Issue:** [#1449](https://github.com/jikig-ai/soleur/issues/1449) — Multi-User Readiness Gate MU2
**Status:** verified
**Date:** 2026-04-18
**Scope:** coverage verification only — no production code changes

---

## Summary

BYOK per-tenant isolation is correctly implemented and now verified end-to-end. Each user's Anthropic API key is encrypted with an HKDF-derived per-user DEK (AES-256-GCM), stored in `public.api_keys` with RLS `auth.uid() = user_id`, and decrypted server-side only with the requesting user's auth context. Cross-tenant access is blocked at two independent layers: Postgres RLS (rows are invisible to other tenants) and cryptographic key derivation (even leaked ciphertext bytes cannot be decrypted with a different userId).

## Verified invariants

| # | Invariant | Layer | Evidence |
|---|---|---|---|
| 1 | Per-user HKDF DEK derivation is RFC 5869 compliant | crypto | `apps/web-platform/server/byok.ts:34-39` + unit tests `test/byok.test.ts:9-63` |
| 2 | `api_keys` RLS silently filters cross-tenant SELECTs to `[]` | DB | integration test `AC 3.b SELECT` |
| 3 | `api_keys` RLS rejects cross-tenant INSERTs (WITH CHECK falls back to USING) | DB | integration test `AC 3.b INSERT` |
| 4 | Leaked ciphertext cannot be decrypted with a different userId (HKDF mismatch → GCM tag failure) | crypto | integration test `AC 3.c` + unit test `test/byok.test.ts:47-52` |
| 5 | Self-decryption round-trip succeeds (guards against ALL-decrypt-broken tautology) | crypto + DB | integration test `AC 3.d` |
| 6 | `encrypted_key` / `iv` / `auth_tag` are `text` base64 (migration 003), column-type drift would fail fast | storage shape | integration test `AC 3.c` typeof + `\\x` prefix guard |
| 7 | Production write path uses `user.id` from server-side `supabase.auth.getUser()`, not untrusted input | auth flow | `apps/web-platform/app/api/keys/route.ts:14-58` |
| 8 | Production read path fetches with `.eq("user_id", userId)` from authenticated session | auth flow | `apps/web-platform/server/agent-runner.ts:154-190` |

## What the tests do NOT prove (residual risks)

These are explicit out-of-scope items. None is a regression from this audit; each has a mitigation path.

1. **Master-key loss is catastrophic and unrecoverable.** `BYOK_ENCRYPTION_KEY` is a single master secret (Doppler `prd`; deterministic dev-fallback in `byok.ts:27-31` for non-production). HKDF derivation is deterministic but master-dependent — losing or rotating the master without re-encryption bricks every row. Supabase Vault was rejected for per-user key storage on 2026-03-20 (see `knowledge-base/project/brainstorms/2026-03-20-byok-key-storage-evaluation-brainstorm.md`), but the brainstorm's second recommendation — envelope-wrap the master key via Vault — was never implemented. **Mitigation:** file a follow-up issue to implement master-key envelope encryption; milestone Post-MVP / Later.

2. **No documented master-key rotation runbook.** See the stub sequence in the plan (`knowledge-base/project/plans/2026-04-18-sec-byok-tenant-isolation-verify-plan.md` → "Master-key rotation runbook"). Reuses the existing v1→v2 lazy-migration pattern at `apps/web-platform/server/agent-runner.ts:172-186`. Not implemented.

3. **Subprocess env leak (CWE-526).** Per `knowledge-base/project/learnings/2026-03-20-process-env-spread-leaks-secrets-to-subprocess-cwe-526.md`, spreading `process.env` into a child process hands the master key to the subprocess. Out-of-scope for this PR (no subprocess spawning). Surface to re-audit periodically: `apps/web-platform/server/bash-sandbox.ts`, `apps/web-platform/server/sandbox.ts`, any `child_process.spawn` / `execa` in `agent-runner.ts`.

4. **Service-role key is omnipotent.** `SUPABASE_SERVICE_ROLE_KEY` bypasses RLS by design. This is inherent to Supabase, not a BYOK weakness. Relevant learning: `2026-04-11-service-role-idor-untrusted-ws-attachments.md`. The BYOK write path uses the service client only after authenticating via cookie-bound `supabase.auth.getUser()` — user id is never taken from untrusted input.

5. **Dev-fallback master key is a hardcoded constant.** `byok.ts:28-31` ships `"0123…ef"` for non-production. Anyone with access to the shared Supabase dev project can decrypt dev-seeded ciphertext. Intentional — dev is not a security boundary.

6. **Integration test is opt-in, not in mainline CI.** Runs only with `BYOK_INTEGRATION_TEST=1` under Doppler. A regression that silently disabled RLS on `api_keys` would not be caught in mainline CI until a nightly CI job or ephemeral-project harness lands. **Decision:** deferred to a follow-up issue — scope-expanding CI wiring does not belong in this PR.

## How to re-run the test

```bash
cd apps/web-platform
doppler run -p soleur -c dev -- \
  env BYOK_INTEGRATION_TEST=1 \
  ./node_modules/.bin/vitest run test/byok.integration.test.ts
```

Expected: 5 tests pass in ~4s against the dev Supabase project. The test self-cleans (deletes the two synthetic users in `afterAll`). Synthetic-email allowlist gate (`SYNTHETIC_EMAIL_PATTERN = /^byok-isolation-[a-f0-9]{16}@soleur\.test$/`) blocks any non-synthetic email from being touched.

## Follow-up items

Tracked as separate GitHub issues (not this PR):

- **Implement master-key envelope encryption** (wrap `BYOK_ENCRYPTION_KEY` via Supabase Vault or equivalent KMS). Addresses risks 1 and 2.
- **Wire BYOK integration test into nightly CI** (dedicated ephemeral project or guarded dev-project run). Addresses risk 6.
- **Periodic subprocess-env audit** of sandbox surfaces. Addresses risk 3.
