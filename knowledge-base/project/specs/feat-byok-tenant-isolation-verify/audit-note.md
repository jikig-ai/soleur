# BYOK Per-Tenant Isolation — Audit Note

**Issue:** [#1449](https://github.com/jikig-ai/soleur/issues/1449) — Multi-User Readiness Gate MU2
**Status:** verified
**Date:** 2026-04-18
**Scope:** coverage verification only — no production code changes

---

## Summary

**Tenant isolation is verified. Key-management hardening (envelope encryption, rotation, KMS) is intentionally deferred and tracked in follow-up issues.** Each user's Anthropic API key is encrypted with an HKDF-derived per-user DEK (AES-256-GCM), stored in `public.api_keys` with RLS `auth.uid() = user_id`, and decrypted server-side only with the requesting user's auth context. Cross-tenant access is blocked at two independent layers: Postgres RLS (rows are invisible to other tenants) and cryptographic key derivation (even leaked ciphertext bytes cannot be decrypted with a different userId). This audit does NOT claim key-management is production-hardened — that work is separate (see risks 1–2).

## Verified invariants

| # | Invariant | Layer | Evidence |
|---|---|---|---|
| 1 | Per-user HKDF DEK derivation is RFC 5869 compliant | crypto | `apps/web-platform/server/byok.ts:34-39` + unit tests `test/byok.test.ts:9-63` |
| 2 | `api_keys` RLS silently filters cross-tenant SELECTs to `[]` | DB | integration test `AC 3.b SELECT` |
| 3 | `api_keys` RLS rejects cross-tenant INSERTs — `FOR ALL USING` applies to write row validity too | DB | integration test `AC 3.b INSERT` |
| 4 | Leaked ciphertext cannot be decrypted with a different userId (HKDF mismatch → GCM tag failure) | crypto | integration test `AC 3.c` + unit test `test/byok.test.ts:47-52` |
| 5 | Self-decryption round-trip succeeds (guards against ALL-decrypt-broken tautology) | crypto + DB | integration test `AC 3.d` |
| 6 | `encrypted_key` / `iv` / `auth_tag` are `text` base64 (migration 003), column-type drift would fail fast | storage shape | integration test `AC 3.c` typeof + `\\x` prefix guard |
| 7 | Production write path uses `user.id` from server-side `supabase.auth.getUser()`, not untrusted input | auth flow | `apps/web-platform/app/api/keys/route.ts:14-58` |
| 8 | Production read path fetches with `.eq("user_id", userId)` from authenticated session | auth flow | `apps/web-platform/server/agent-runner.ts:154-190` |
| 9 | `on_auth_user_created` trigger auto-creates `public.users` row (canary via beforeAll SELECT) | DB | integration test `beforeAll` profile check |

## Crypto invariants worth stating explicitly

These are not tests — they are preconditions the current implementation relies on. Stating them here blocks a well-intentioned future refactor from silently weakening the crypto surface.

- **(key, IV) uniqueness under AES-GCM.** A repeated (DEK, IV) pair is catastrophic for GCM. The current design uses a 12-byte random IV per encryption and per-user DEKs, giving ~2^32 safe encryptions per user before birthday risk — effectively unbounded at Soleur scale. A future scheme that narrows the DEK scope (e.g., per-provider DEK) must re-evaluate IV entropy.
- **Constant-time tag comparison.** Node's `decipher.final()` performs constant-time GCM tag verification. A future "friendlier error message" refactor that distinguishes HKDF-mismatch from tag-mismatch would leak timing information; the current generic throw is deliberate.

## What the tests do NOT prove (residual risks)

Each risk is out-of-scope for this PR and tracked in a concrete follow-up issue.

1. **Master-key loss is catastrophic and unrecoverable.** `BYOK_ENCRYPTION_KEY` is a single master secret (Doppler `prd`; deterministic dev-fallback in `byok.ts:27-31` for non-production). HKDF derivation is deterministic but master-dependent — losing or rotating the master without re-encryption bricks every row. Supabase Vault was rejected for per-user key storage on 2026-03-20 (see `knowledge-base/project/brainstorms/2026-03-20-byok-key-storage-evaluation-brainstorm.md`), but the brainstorm's second recommendation — envelope-wrap the master key via Vault or external KMS — was never implemented. **Tracked:** [#2612](https://github.com/jikig-ai/soleur/issues/2612).

2. **No documented master-key rotation runbook.** See the stub sequence in the plan (`knowledge-base/project/plans/2026-04-18-sec-byok-tenant-isolation-verify-plan.md` → "Master-key rotation runbook"). Reuses the existing v1→v2 lazy-migration pattern at `apps/web-platform/server/agent-runner.ts:172-186`. **Tracked:** rolled into [#2612](https://github.com/jikig-ai/soleur/issues/2612) (same follow-up owns the rotation story).

3. **Subprocess env leak (CWE-526).** Spreading `process.env` into a child process hands the master key to the subprocess. Out-of-scope for this PR (no subprocess spawning in the code under test). Relevant surface: `apps/web-platform/server/bash-sandbox.ts`, `apps/web-platform/server/sandbox.ts`, `agent-runner.ts` child-process paths. **Tracked:** [#2614](https://github.com/jikig-ai/soleur/issues/2614).

4. **Service-role key bypasses RLS by design.** Inherent to Supabase, not a BYOK weakness. BYOK write path only uses the service client after `supabase.auth.getUser()` establishes the user id from the cookie-bound session.

5. **Dev-fallback master key is a hardcoded constant.** `byok.ts:28-31` ships `"0123…ef"` for non-production. Dev is not a security boundary.

6. **Integration test is opt-in, not in mainline CI.** Runs only with `BYOK_INTEGRATION_TEST=1` under Doppler. A regression that silently disabled RLS on `api_keys` would not be caught in mainline CI until a nightly job or ephemeral-project harness lands. **Tracked:** [#2613](https://github.com/jikig-ai/soleur/issues/2613).

## How to re-run the test

```bash
cd apps/web-platform
doppler run -p soleur -c dev -- \
  env BYOK_INTEGRATION_TEST=1 \
  ./node_modules/.bin/vitest run test/byok.integration.test.ts
```

Expected: 5 tests pass in ~4s against the dev Supabase project. Expected test names:

- `AC 3.a — user A's seeded ciphertext is visible to the service client`
- `AC 3.b SELECT — user B cannot read user A's encrypted key via RLS`
- `AC 3.b INSERT — user B cannot INSERT a row claiming user A's user_id`
- `AC 3.c — leaked ciphertext cannot be decrypted with user B's userId`
- `AC 3.d — user A can decrypt their own ciphertext (round-trip sanity)`

Common failure modes:

- `[byok.integration] NEXT_PUBLIC_SUPABASE_URL is required` — you forgot `doppler run -p soleur -c dev`.
- `createUser(...) failed` with rate-limit message — you ran the suite many times in quick succession; Supabase GoTrue rate-limits sign-ins per-IP. Wait a few minutes.
- `public.users row missing for ...` — the `on_auth_user_created` trigger did not fire. Investigate migration 001 regression before treating this as a test bug.

The test self-cleans (`afterAll` deletes the two synthetic users). Cleanup is gated on `SYNTHETIC_EMAIL_PATTERN = /^byok-isolation-[a-f0-9]{16}@soleur\.test$/` and a round-trip check against `auth.users.email` — non-synthetic emails cannot be touched even if an attacker mutates the in-memory `user` record.

## Follow-up items

Tracked as separate GitHub issues:

- [#2612](https://github.com/jikig-ai/soleur/issues/2612) — Implement master-key envelope encryption (addresses risks 1 & 2).
- [#2613](https://github.com/jikig-ai/soleur/issues/2613) — Wire BYOK integration test into nightly CI (addresses risk 6).
- [#2614](https://github.com/jikig-ai/soleur/issues/2614) — Periodic subprocess-env audit (addresses risk 3).
