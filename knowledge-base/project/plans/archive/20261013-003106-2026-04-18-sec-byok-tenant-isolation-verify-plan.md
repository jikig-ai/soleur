# Plan: Verify BYOK encryption is per-tenant isolated (#1449)

**Branch:** `feat-byok-tenant-isolation-verify`
**Worktree:** `.worktrees/feat-byok-tenant-isolation-verify/`
**Issue:** [#1449](https://github.com/jikig-ai/soleur/issues/1449) — "sec: verify BYOK encryption is per-tenant isolated (Multi-User Readiness MU2)"
**Milestone:** Phase 4: Validate + Scale (blocking Phase 4 recruitment outreach)
**Labels:** `priority/p1-high`, `type/chore`, `type/security`, `domain/engineering`
**Type:** verification + test-writing (no production code changes)

---

## Enhancement Summary

**Deepened on:** 2026-04-18
**Sections enhanced:** Overview, Test Scenarios, Phase 4 (RLS), Phase 5 (crypto), Residual Risks, Research Insights
**Research sources:** project constitution, 10+ institutional learnings (see Research Insights), Supabase RLS + PostgREST docs (codified in learnings), live Doppler-config verification

### Key Improvements

1. **Added a fifth test (AC 3.b-insert variant): user B cannot INSERT a row with `user_id = userA.id`.** The `api_keys` RLS policy is `for all using (auth.uid() = user_id)` — without an explicit `with check`, PostgreSQL falls back to USING for INSERT. Verifying INSERT denial closes a gap the original plan missed: RLS denies reads but also denies writes to another tenant's user_id, preventing a hypothetical "spoof your user_id and read-your-own-row" attack.
2. **Pinned the empty-set assertion shape precisely.** Per `2026-04-07-supabase-postgrest-anon-key-schema-listing-401.md`, RLS returns `200 OK` with `[]` (never 401 for table queries with anon key). Plan assertions pin `.toEqual([])`, never `.toHaveLength(0)` (which passes on `undefined`) — and explicitly assert `error === null`.
3. **Added silent-error guard on all Supabase calls in the test.** Per `2026-03-20-supabase-silent-error-return-values.md`, Supabase JS v2 returns `{ data, error }` and does NOT throw. Every `{ error }` in the test must be destructured and asserted — otherwise a failure at setup time (e.g., service-role insert rejected by column type drift) silently passes and the whole test proves nothing.
4. **Documented the `bytea` → `text` hazard for any future columns.** Per `2026-03-17-postgrest-bytea-base64-mismatch.md`, `encrypted_key` is `text` (stores base64 literally). Plan confirms test writes base64 strings matching the production write path in `app/api/keys/route.ts:41-58`. Adding a byte-shape assertion (`typeof data.encrypted_key === "string"`) catches column-type drift at the test boundary.
5. **Escalated service-role IDOR as a test-scope-adjacent risk.** Per `2026-04-11-service-role-idor-untrusted-ws-attachments.md`, service-role bypasses RLS anywhere it's used. Audit note now lists specific call-sites (`server/agent-runner.ts:154-190`, `app/api/keys/route.ts:43-58`) that already pass `user.id` from auth context — NOT from untrusted input. This is not a gap this PR needs to close, but it IS a surface to re-verify periodically.
6. **Formalized the master-key rotation runbook stub** (moved from "someday" bullet to a numbered sequence with explicit `key_version` gating + dual-read window).
7. **Resolved `gh` query for code-review overlap live** (confirmed `None`).

### New Considerations Discovered

- **Auth rate-limit on `admin.createUser`:** Supabase Admin API can throttle aggressive user creation. Two users per test run is well under any known limit, but `beforeAll` should use unique randomized suffixes so flakes don't accumulate orphan users.
- **RLS `WITH CHECK` defaults to USING when omitted** (Postgres docs + `001_initial_schema.sql`). Plan now tests both SELECT denial AND INSERT denial to cover this.
- **Supabase JS v2 `single()` returns error when zero or multiple rows match** — but the test uses `.select()` without `.single()` for the RLS check, so empty result is `{ data: [], error: null }` not an error. This is intentional and pinned.

---

## Overview

Per-tenant BYOK isolation is **already implemented**. Issue #1449 asks us to **verify** it — not rewrite it. Two of the three acceptance criteria are already met in merged code:

- **AC 1 (per-user encryption key):** `apps/web-platform/server/byok.ts:34-39` — `deriveUserKey(masterKey, userId)` via `hkdfSync("sha256", masterKey, Buffer.alloc(0), "soleur:byok:"+userId, 32)`. RFC 5869 compliant (see learning `2026-03-20-hkdf-salt-info-parameter-semantics.md`).
- **AC 2 (cross-user access impossible at crypto layer):** proved by existing unit test `apps/web-platform/test/byok.test.ts:47-52` — `decryptKey(…, USER_B)` on USER_A ciphertext throws GCM auth-tag failure.
- **AC 3 (integration test confirms isolation holds):** **NOT YET MET.** Existing tests are in-memory only — they exercise the crypto primitives but never touch the `api_keys` DB table, so they cannot prove the RLS layer (`auth.uid() = user_id`) actually denies cross-tenant SELECTs in production Supabase.

This plan closes AC 3 by adding **one integration test file** that exercises both layers end-to-end against real Supabase:

1. Seed ciphertext for user A via the service-role client (mirrors `app/api/keys/route.ts:41-58`).
2. Assert user B's authenticated Supabase client (anon JWT for user B) receives 0 rows on `SELECT … WHERE user_id = <userA>` — RLS denial.
3. Assert that even if ciphertext bytes leaked, calling `decryptKey(…, userB.id)` throws — HKDF derivation mismatch → GCM auth-tag failure.

No production code changes. No schema changes. No new dependencies.

---

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue + pipeline brief) | Reality (verified in repo/Doppler) | Plan response |
|---|---|---|
| "Integration test must use real Supabase harness, not mocks" | `apps/web-platform/test/` has no existing integration tests against live Supabase. `vitest.config.ts` has a single `unit` project (`environment: node`) that already has access to `process.env` from the shell — if `doppler run` sets the env, tests can connect to live Supabase. No harness work required beyond an opt-in flag. | Gate the new test with `describe.skipIf(!process.env.BYOK_INTEGRATION)` — CI without secrets skips, Doppler run enables. |
| "Supabase test harness" | No such harness exists in the repo. `scripts/seed-qa-user.sh` uses raw `curl` against the Admin API. Playwright E2E tests (`apps/web-platform/e2e/`) use the QA user. | Use `@supabase/supabase-js` admin API (`auth.admin.createUser`) + service-role client directly in the test — same pattern as `seed-qa-user.sh` but in TS. No new harness abstraction. |
| "BYOK_ENCRYPTION_KEY in Doppler dev" | `doppler secrets get BYOK_ENCRYPTION_KEY -p soleur -c dev` → `Could not find requested secret`. Secret exists in `prd` only. `byok.ts:27-31` has a deterministic dev-only fallback when `NODE_ENV !== "production"`. | Test runs with `NODE_ENV=test` (vitest default) → hits dev-fallback master key. Document this in the test header. Master-key rotation risk documented in audit note (below). |
| "Supabase dev project is safe to write to" | `NEXT_PUBLIC_SUPABASE_URL` in dev points to real project `ifsccnjhymdmidffkzhl.supabase.co` — shared with Playwright QA and local dev sessions. | Hard-allowlist synthetic emails (`byok-isolation-<suffix>@soleur.test`). `beforeAll`/`afterAll` cleanup throws if email not on allowlist (`hr-destructive-prod-tests-allowlist`). |
| "Existing unit tests are in-memory only" | Confirmed. `apps/web-platform/test/byok.test.ts` imports directly from `server/byok` and never touches Supabase. | Keep the unit file unchanged. Add a sibling `byok.integration.test.ts` for the DB-layer assertions. |

---

## Implementation Phases

### Phase 1 — Test scaffolding (RED)

Create `apps/web-platform/test/byok.integration.test.ts` with all tests starting as failing (`.skipIf` off, but without the DB seed logic in place). Confirm the suite runs and fails with expected errors. This satisfies `cq-write-failing-tests-before`.

**Gating:** `describe.skipIf(!process.env.BYOK_INTEGRATION_TEST)` so the test only runs when explicitly opted in via `doppler run -p soleur -c dev -- BYOK_INTEGRATION_TEST=1 npm test -- byok.integration`.

**Environment preconditions checked at `beforeAll`:**

```text
- NEXT_PUBLIC_SUPABASE_URL     (from dev Doppler, required)
- NEXT_PUBLIC_SUPABASE_ANON_KEY (from dev Doppler, required)
- SUPABASE_SERVICE_ROLE_KEY    (from dev Doppler, required)
- BYOK_ENCRYPTION_KEY           (optional — falls through to byok.ts dev fallback)
```

If any required secret is missing, fail fast with a message pointing at `cq-for-local-verification-of-apps-doppler`. Do not silently skip — skipping hides coverage regressions.

**Files to create:**

- `apps/web-platform/test/byok.integration.test.ts`

### Phase 2 — Synthetic-tenant allowlist + lifecycle (GREEN scaffolding)

Implement the cleanup safety gate per `hr-destructive-prod-tests-allowlist`:

```ts
// In byok.integration.test.ts (illustrative — actual impl written during work phase)
const SYNTHETIC_EMAIL_PATTERN = /^byok-isolation-[a-f0-9]{16}@soleur\.test$/;

function assertSynthetic(email: string) {
  if (!SYNTHETIC_EMAIL_PATTERN.test(email)) {
    throw new Error(
      `Refusing to touch non-synthetic email "${email}" — ` +
      `this test only manipulates byok-isolation-*@soleur.test`,
    );
  }
}
```

**Lifecycle:**

- `beforeAll`: create user A + user B with `supabase.auth.admin.createUser({ email, password, email_confirm: true })`. Each email is `byok-isolation-<crypto.randomBytes(8).toString("hex")>@soleur.test`. Store IDs in closure-scoped variables.
- `afterAll`: for each ID, call `assertSynthetic(email)` then `supabase.auth.admin.deleteUser(id)` — cascade drops the `api_keys` row via the existing `on delete cascade` FK. Swallow "user not found" errors (idempotent).
- No `.only` / `.skip` left in committed code.

### Phase 3 — AC 3.a: seed ciphertext for user A (GREEN)

```ts
test("user A's encrypted BYOK key is stored via service client", async () => {
  const plaintext = "sk-ant-api03-test-" + crypto.randomBytes(8).toString("hex");
  const { encrypted, iv, tag } = encryptKey(plaintext, userA.id);

  const { error } = await service.from("api_keys").upsert({
    user_id: userA.id,
    provider: "anthropic",
    encrypted_key: encrypted.toString("base64"),
    iv: iv.toString("base64"),
    auth_tag: tag.toString("base64"),
    is_valid: true,
    key_version: 2,
  }, { onConflict: "user_id,provider" });

  expect(error).toBeNull();
});
```

### Phase 4 — AC 3.b: RLS denies user B SELECT of user A's row (GREEN)

Sign in as user B via `signInWithPassword` to get an anon JWT bound to `auth.uid() = userB.id`. Issue an authenticated `SELECT * FROM api_keys WHERE user_id = userA.id`. Assert the result set is **empty** (not an error — RLS silently filters rows, it does not raise).

```ts
test("user B cannot SELECT user A's encrypted key via RLS", async () => {
  const userBClient = createClient(supabaseUrl, anonKey);
  const { error: signInErr } = await userBClient.auth.signInWithPassword({
    email: userB.email, password: userB.password,
  });
  expect(signInErr).toBeNull();

  const { data, error } = await userBClient
    .from("api_keys")
    .select("id, encrypted_key, iv, auth_tag, user_id")
    .eq("user_id", userA.id);

  expect(error).toBeNull();            // RLS does not raise
  expect(data).toEqual([]);            // it returns zero rows
});
```

This is the DB-layer invariant the unit tests cannot prove.

**Pin the post-state exactly** (`cq-mutation-assertions-pin-exact-post-state`): use `.toEqual([])`, not `.toHaveLength(0)` — the former is strictly empty, the latter passes on `undefined`.

### Research Insights — Why empty-array, not 401

Per learning `2026-04-07-supabase-postgrest-anon-key-schema-listing-401.md`:

> PostgREST treats schema listing and table queries differently for authorization. Schema listing (`/rest/v1/`) requires the service role key (returns 401 with anon key). Table queries (`/rest/v1/<table>?...`) work with the anon key — RLS filters rows at the database level, but the HTTP response is always 200 (with empty results if no rows pass RLS).

If the test asserts `error.code === "401"` or any non-null `error`, it will fail **even when RLS is working correctly**. The canonical shape is `{ data: [], error: null }`.

Also, per learning `2026-03-20-supabase-silent-error-return-values.md`, Supabase JS v2 never throws — always destructure `{ data, error }` and assert both. A missed `error` assertion in a `beforeAll` setup step silently masks failures: the test appears to pass but proves nothing.

### Phase 4.5 — AC 3.b-write: user B cannot INSERT with user A's user_id (GREEN)

The RLS policy in `001_initial_schema.sql` is `for all using (auth.uid() = user_id)` — no explicit `with check`. Per PostgreSQL semantics, `WITH CHECK` falls back to `USING` when omitted, which means INSERT by user B with `user_id = userA.id` is rejected by RLS.

This closes a gap the read-only test misses: a hypothetical attacker who compromises user B's session and tries to plant a row **claiming** to be user A's key (spoofing to later read it back via their own SELECT) is blocked at the INSERT too.

```ts
test("user B cannot INSERT a row claiming user A's user_id", async () => {
  // userBClient is already signed in as user B from Phase 4
  const { error } = await userBClient
    .from("api_keys")
    .insert({
      user_id: userA.id,                   // the spoof attempt
      provider: "anthropic",
      encrypted_key: "ZmFrZQ==",           // harmless base64
      iv: "ZmFrZQ==",
      auth_tag: "ZmFrZQ==",
      is_valid: false,
      key_version: 2,
    });

  // Supabase JS v2: RLS INSERT denial returns PostgREST error code 42501
  // (permission denied) or 401/403. Do NOT assert a specific message string
  // (fragile across PostgREST versions) — just assert error is non-null.
  expect(error).not.toBeNull();
});
```

**Why not assert a specific error code:** PostgREST version changes shift the exact code/message. The invariant is "the insert does not succeed" — `error !== null` captures that durably.

### Phase 5 — AC 3.c: even leaked ciphertext cannot be decrypted by user B (GREEN)

Simulate a hypothetical ciphertext leak: service client fetches user A's row bytes (bypassing RLS), then we attempt `decryptKey(encrypted, iv, tag, userB.id)`. GCM auth-tag mismatch must throw — this is the crypto-layer defense-in-depth invariant.

```ts
test("leaked ciphertext cannot be decrypted with user B's userId", async () => {
  const { data, error } = await service
    .from("api_keys")
    .select("encrypted_key, iv, auth_tag")
    .eq("user_id", userA.id)
    .eq("provider", "anthropic")
    .single();
  expect(error).toBeNull();

  // Column-type drift guard: encrypted_key/iv/auth_tag are TEXT columns
  // storing base64 strings. If a future migration flips them back to
  // bytea (as in pre-migration-003), Buffer.from(hexString, "base64")
  // would silently produce garbage and decryptKey would throw for the
  // WRONG reason (not RLS/HKDF isolation). See learning:
  // 2026-03-17-postgrest-bytea-base64-mismatch.md
  expect(typeof data!.encrypted_key).toBe("string");
  expect(data!.encrypted_key.startsWith("\\x")).toBe(false);

  const encrypted = Buffer.from(data!.encrypted_key, "base64");
  const iv = Buffer.from(data!.iv, "base64");
  const tag = Buffer.from(data!.auth_tag, "base64");

  expect(() => decryptKey(encrypted, iv, tag, userB.id)).toThrow();
});
```

### Phase 6 — AC 3.d: self-decrypt sanity (GREEN)

Complete the round-trip: same byte sequence decrypts successfully with user A's id. Without this, a bug that breaks ALL decryption (not just cross-tenant) would pass the other tests tautologically.

```ts
test("user A can decrypt their own ciphertext", async () => {
  // ...same fetch as Phase 5...
  const decrypted = decryptKey(encrypted, iv, tag, userA.id);
  expect(decrypted).toBe(seededPlaintext);  // pinned from Phase 3 closure
});
```

### Phase 7 — Audit note

Create `knowledge-base/project/specs/feat-byok-tenant-isolation-verify/audit-note.md` documenting:

- **Verified invariants:** 3 AC mapped to specific test names and source lines.
- **Non-invariants (what the test does NOT prove):** subprocess env leak (CWE-526 per `2026-03-20-process-env-spread-leaks-secrets-to-subprocess-cwe-526.md`), key rotation story, service-role-key handling, master-key loss recovery.
- **Residual risks + mitigations** (see section below).
- **How to re-run the test.**

**Files to create:**

- `knowledge-base/project/specs/feat-byok-tenant-isolation-verify/audit-note.md`

### Phase 8 — Run, verify, commit

Run the new test under Doppler dev (expects the real Supabase dev project):

```bash
cd apps/web-platform && \
  doppler run -p soleur -c dev -- \
  BYOK_INTEGRATION_TEST=1 ./node_modules/.bin/vitest run test/byok.integration.test.ts
```

(Per `cq-in-worktrees-run-vitest-via-node-node` — app-level binary, not npx.)

Expect: 5 tests pass, ~3-10s total (network round trips to Supabase dev). After first green, run the full unit suite to confirm no regression.

---

## Files to Edit

**None.** This is a test-only PR. No production code changes.

## Files to Create

- `apps/web-platform/test/byok.integration.test.ts` — the 5-test integration file (Phases 3-6 + 4.5).
- `knowledge-base/project/specs/feat-byok-tenant-isolation-verify/audit-note.md` — invariant + risk documentation (Phase 7).
- `knowledge-base/project/specs/feat-byok-tenant-isolation-verify/spec.md` — optional one-page spec summary (auto-generated by `soleur:spec-templates` if desired during work phase).

---

## Open Code-Review Overlap

Query: `gh issue list --label code-review --state open --json number,title,body --limit 200` filtered for any body containing `apps/web-platform/server/byok.ts`, `apps/web-platform/test/byok.test.ts`, `app/api/keys/route.ts`, or `server/agent-runner.ts`.

**None.** No open code-review scope-outs touch the BYOK encryption surface. (Validated at planning time via `gh issue list`.)

If the `gh` query returns matches at work-skill time, re-run the overlap check and record disposition here before opening the PR.

---

## Test Scenarios (mapped to Acceptance Criteria)

| # | Scenario | AC | Layer | Assertion |
|---|---|---|---|---|
| 1 | user A's ciphertext inserts successfully via service client | AC 1 | DB | `error === null` on upsert |
| 2 | user B authed client sees 0 rows for user A's user_id | AC 2 | DB (RLS SELECT) | `data.toEqual([])` + `error === null` |
| 3 | user B authed client cannot INSERT row with user_id = userA.id | AC 2 | DB (RLS INSERT) | `error !== null` (WITH CHECK falls back to USING) |
| 4 | `decryptKey(…A's bytes…, userB.id)` throws GCM tag failure | AC 2 | crypto | `expect(...).toThrow()` + column-shape guard |
| 5 | `decryptKey(…A's bytes…, userA.id)` returns original plaintext | AC 1 | crypto | `toBe(seededPlaintext)` |

Unit test coverage (pre-existing, unchanged): encrypt/decrypt round-trip, base64 round-trip, deterministic HKDF derivation, wrong-userId throws, legacy v1 decrypt + v1-cannot-be-decrypted-with-HKDF. Those 6 tests already cover AC 1 + AC 2 at the in-memory layer.

---

## Acceptance Criteria

### Pre-merge (PR)

- [x] `apps/web-platform/test/byok.integration.test.ts` exists and contains 5 tests mapped above.
- [x] All 5 integration tests pass locally under `doppler run -p soleur -c dev -- BYOK_INTEGRATION_TEST=1`.
- [x] Full `apps/web-platform` vitest run (unit + component projects) still passes; no regression in the 6 existing BYOK unit tests.
- [x] `beforeAll`/`afterAll` cleanup gates on `SYNTHETIC_EMAIL_PATTERN` and throws on non-matching emails. Verify by temporarily constructing a non-matching email in the cleanup path → test must throw.
- [x] Audit note committed to `knowledge-base/project/specs/feat-byok-tenant-isolation-verify/audit-note.md`.
- [ ] PR body includes `Closes #1449`.
- [ ] Review run passes (no new security findings).
- [x] No production code changes under `apps/web-platform/server/` or `apps/web-platform/app/`.

### Post-merge (operator)

- [ ] Issue #1449 auto-closes (verify via `gh issue view 1449 --json state`).
- [ ] Phase 4: Validate + Scale milestone has MU2 struck through in the gate checklist.
- [ ] **Opt-in CI coverage decision:** the integration test runs only with `BYOK_INTEGRATION_TEST=1`. Decide at merge time whether to also wire a nightly CI job (`doppler run -c ci -- ... BYOK_INTEGRATION_TEST=1 ...`). If yes, file a follow-up issue; if no, document in audit note that coverage is developer-local only. **Default: defer to follow-up issue — do not expand scope of this PR.**

---

## Residual Risks (carried into audit note)

These are **known gaps the AC explicitly do not cover**. Listing them here so the plan is honest about the ceiling of what this verification proves.

1. **Master-key loss is catastrophic and unrecoverable.** `BYOK_ENCRYPTION_KEY` is a single master secret in Doppler `prd` + fallback in dev. If rotated or lost, every per-user ciphertext is undecryptable (HKDF derivation is deterministic but depends on the master). No envelope encryption yet (Supabase Vault was rejected 2026-03-20 per `knowledge-base/project/brainstorms/2026-03-20-byok-key-storage-evaluation-brainstorm.md` for per-user keys, but the brainstorm's *second* recommendation — Vault-wrap the master key — was not implemented). **Mitigation:** file a P2 follow-up issue "Implement master-key envelope encryption via Supabase Vault" and milestone to Post-MVP / Later. **Not this PR.**
2. **Master-key rotation has no documented runbook.** Rotating `BYOK_ENCRYPTION_KEY` without simultaneously re-encrypting every row would brick all users. **Mitigation:** audit note documents the 5-step sequence (see "Master-key rotation runbook (stub for follow-up issue)" under Research Insights). Cross-links to the envelope-encryption follow-up. The lazy-migration machinery at `server/agent-runner.ts:172-186` (v1→v2) is the proven pattern to reuse for v2→v3.
3. **Subprocess env leak (CWE-526):** per learning `2026-03-20-process-env-spread-leaks-secrets-to-subprocess-cwe-526.md`, spreading `process.env` into a child process passes the master key. Not in scope here (no subprocess spawning in this test), but audit note lists the surface to review: `server/bash-sandbox.ts`, `server/sandbox.ts`, `server/agent-runner.ts` child process invocations. Confirm each strips `BYOK_ENCRYPTION_KEY` from env before spawn.
4. **Service-role key is omnipotent.** Anyone with `SUPABASE_SERVICE_ROLE_KEY` bypasses RLS. This is inherent to Supabase design, not a BYOK-specific weakness. Audit note notes this and points to how the server uses it (narrowly, only in `createServiceClient` paths).
5. **Dev-fallback master key is hardcoded.** `byok.ts:28-31` has `"0123456789abcdef…"`. Anyone running tests locally against Supabase dev can decrypt anyone else's dev-seeded ciphertext. This is expected — dev is shared and not a security boundary. Audit note flags explicitly.
6. **Integration test does not run in CI by default.** Without `BYOK_INTEGRATION_TEST=1`, the suite skips silently. This is intentional (opt-in) but means a regression that breaks RLS on `api_keys` would not be caught in mainline CI. Audit note documents the trade-off and the opt-in CI follow-up.

---

## Non-Goals

- **Do NOT rewrite `byok.ts` or `deriveUserKey`.** The code is correct per RFC 5869.
- **Do NOT migrate to Supabase Vault for per-user keys.** Decided 2026-03-20 (brainstorm link above).
- **Do NOT add envelope encryption for master key in this PR.** File a follow-up issue, milestone to Post-MVP / Later.
- **Do NOT add nightly CI for this test in this PR.** File a follow-up issue.
- **Do NOT introduce a shared "Supabase integration test harness" helper.** This is the first such test — extract when we have 3+ candidates, not on spec.
- **Do NOT touch `apps/web-platform/e2e/`** (Playwright suite). This is a Node-level integration test, not a browser test.

---

## Domain Review

**Domains relevant:** Engineering (CTO)

This is a test-writing task on an existing, reviewed security primitive. No CPO / CMO / CRO / CLO / COO / CFO / CCO implications — no user-facing change, no copy, no pricing, no legal surface, no recruitment workflow change (the Phase 4 gate itself is product, but the gate mechanics are not the subject of this plan).

### Engineering (CTO)

**Status:** reviewed (inline — this is CTO-domain work)

**Assessment:** The existing HKDF implementation is correct. The gap is coverage, not correctness. Writing an integration test that exercises RLS + crypto in one flow is standard test hygiene; the only real design decision is the opt-in gating (`BYOK_INTEGRATION_TEST=1`) vs. always-on CI. Opt-in is the right call for this PR — it avoids making Supabase dev a shared-mutable prerequisite for every CI run, and follow-up work can wire CI with a dedicated ephemeral project or the existing dev project behind a retry + cleanup-verify step.

### Product/UX Gate

**Tier:** none — no user-facing change.

---

## Research Insights

### Repo patterns confirmed

- `server/byok.ts:34-39` — `deriveUserKey` uses empty salt + `"soleur:byok:"+userId` in `info`. Compliant with RFC 5869 per learning `2026-03-20-hkdf-salt-info-parameter-semantics.md`.
- `app/api/keys/route.ts:41-58` — production encrypt path uses `user.id` from `supabase.auth.getUser()`, passes to `encryptKey`, upserts on `user_id,provider`. Integration test mirrors this exactly.
- `server/agent-runner.ts:154-190` — production decrypt path with v1→v2 lazy migration. Test does not exercise lazy migration (already unit-tested in `byok.test.ts:86-102`).
- `supabase/migrations/001_initial_schema.sql` — `api_keys` has RLS enabled + single `"Users can manage own API keys"` policy with `auth.uid() = user_id`. This is the invariant AC 3.b verifies.
- `supabase/migrations/009_byok_hkdf_per_user_keys.sql` — adds `key_version` column (1=legacy, 2=HKDF). Test uses `key_version: 2` for new inserts.
- `lib/supabase/service.ts:25-36` — `createServiceClient()` pattern with `persistSession: false`. Test will use this directly (it's already exported via `lib/supabase/server.ts`).
- `scripts/seed-qa-user.sh` — demonstrates how to use the Admin API for synthetic user creation + cleanup. Integration test uses the TS equivalent (`auth.admin.createUser` / `auth.admin.deleteUser`).

### Doppler secret reality (verified at plan time)

- `BYOK_ENCRYPTION_KEY`: present in `prd`, **missing** in `dev` and `ci`. Dev-fallback in `byok.ts:28-31` activates when `NODE_ENV !== "production"`.
- `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`: all present in `dev`. Test runs against real Supabase dev project `ifsccnjhymdmidffkzhl.supabase.co`.

### Institutional learnings applied

- `2026-03-20-hkdf-salt-info-parameter-semantics.md` — HKDF param order is correct (`salt=Buffer.alloc(0)`, `info="soleur:byok:"+userId`). Do not revisit in this plan.
- `2026-03-20-process-env-spread-leaks-secrets-to-subprocess-cwe-526.md` — listed in audit-note residual risks. Not in scope for this test.
- `2026-04-07-supabase-postgrest-anon-key-schema-listing-401.md` — RLS returns `200 OK` with empty array for table queries, not 401. Test asserts `error === null` AND `data.toEqual([])`.
- `2026-03-20-supabase-silent-error-return-values.md` — Supabase JS v2 returns `{ data, error }` and does not throw. Every call in the test destructures and asserts both.
- `2026-03-17-postgrest-bytea-base64-mismatch.md` — `encrypted_key/iv/auth_tag` are `text` columns (migration 003). Column-type drift guard in Phase 5.
- `2026-04-11-service-role-idor-untrusted-ws-attachments.md` — service-role bypasses RLS; any user-controlled path to service client is a bypass. Audit note references for surface review.
- `2026-04-07-rls-column-takeover-github-username-20260407.md` — permissive RLS on `for all` policies inherits to new columns. Not triggered here (we're not adding columns), but audit note flags this for future BYOK schema changes.
- `2026-03-20-supabase-column-level-grant-override.md` — table-level grants override column-level revokes. Not in scope (no column-level restriction added).
- `cq-destructive-prod-tests-allowlist` / `hr-destructive-prod-tests-allowlist` — enforced via `SYNTHETIC_EMAIL_PATTERN` guard in `beforeAll`/`afterAll`.
- `cq-mutation-assertions-pin-exact-post-state` — enforced via `.toEqual([])` (not `.toHaveLength(0)`) and `.toBe(seededPlaintext)` (not `.toContain`).
- `cq-in-worktrees-run-vitest-via-node-node` — integration test command uses `./node_modules/.bin/vitest` (app-level), not `npx vitest`.
- `cq-for-local-verification-of-apps-doppler` — all verification commands use `cd apps/web-platform && doppler run -p soleur -c dev -- ...` form.
- `wg-when-a-pr-includes-database-migrations` — not applicable (no migrations in this PR). Noted so reviewers don't ask.

### Master-key rotation runbook (stub for follow-up issue)

Not in scope for this PR, but the audit note references this sequence so the operator has a starting point when the follow-up "Implement master-key envelope encryption" issue is picked up:

1. Generate new master key: `openssl rand -hex 32` → `NEW_KEY`.
2. Set `BYOK_ENCRYPTION_KEY_NEXT=NEW_KEY` in Doppler `prd` alongside existing `BYOK_ENCRYPTION_KEY`.
3. Deploy `byok.ts` change that adds `key_version = 3` path: `encryptKey` uses `NEXT`, `decryptKey` tries `version 3 → next`, `version 2 → current`, `version 1 → legacy`. Dual-read window.
4. Background job re-encrypts all `key_version = 2` rows with NEXT master: read → decrypt-with-current → encrypt-with-next → write with `key_version = 3`. Same pattern as existing v1→v2 lazy migration in `server/agent-runner.ts:172-186`.
5. After 100% migrated: promote `BYOK_ENCRYPTION_KEY_NEXT` to `BYOK_ENCRYPTION_KEY`, remove dual-read code, remove `key_version = 2` support.

This is **not** the work of #1449. It's captured so the residual risk list in the audit note points to a concrete path, not a vague "someday."

---

## Implementation Detail Level

**MORE** (mid-detail). The task is a single test file plus an audit note; the risk surface is in the test mechanics (RLS semantics, synthetic-allowlist safety, Doppler config reality) rather than in a sprawling architectural change. A-LOT-level detail would be theater; MINIMAL would underspecify the safety gates that prevent a regression from deleting real users.

---

## PR Body Reminder

```text
Closes #1449

Verifies BYOK per-tenant isolation at the DB (RLS) and crypto (HKDF/GCM) layers
via a new integration test: apps/web-platform/test/byok.integration.test.ts.

- No production code changes.
- 5 new tests, opt-in via BYOK_INTEGRATION_TEST=1.
- Synthetic-email allowlist gates cleanup (hr-destructive-prod-tests-allowlist).
- Audit note at knowledge-base/project/specs/feat-byok-tenant-isolation-verify/audit-note.md
  documents verified invariants + residual risks (master-key rotation, CWE-526 subprocess leak).

Part of Phase 4 Multi-User Readiness Gate MU2.
```

Labels to apply: `type/chore`, `type/security`, `priority/p1-high`, `domain/engineering` (all already on #1449).
