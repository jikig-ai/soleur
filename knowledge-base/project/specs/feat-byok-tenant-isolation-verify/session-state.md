# Session State

## Plan Phase

- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-byok-tenant-isolation-verify/knowledge-base/project/plans/2026-04-18-sec-byok-tenant-isolation-verify-plan.md
- Status: complete

### Errors

None. Markdownlint clean. Test-count drift (4 → 5) detected in 3 spots after adding INSERT-denial test; all fixed before finalizing.

### Decisions

- **Scope is test-only**, no production code changes. Existing HKDF implementation at `apps/web-platform/server/byok.ts:34-39` is correct per RFC 5869 and prior brainstorm decisions; AC 1 + AC 2 are already met by merged code. This PR closes AC 3 by adding integration tests.
- **Single test file**: `apps/web-platform/test/byok.integration.test.ts` with 5 opt-in tests gated by `BYOK_INTEGRATION_TEST=1`. Uses existing `vitest` unit project (no new harness), runs against real Supabase dev via `doppler run -p soleur -c dev`.
- **Expanded from 4 to 5 tests during deepen-pass** by adding RLS-INSERT denial (Phase 4.5): user B attempting to INSERT with `user_id = userA.id` must fail because the `for all using` policy falls back to USING for WITH CHECK. Closes a spoof-write gap the read-only assertion missed.
- **Synthetic-email allowlist enforced** via `SYNTHETIC_EMAIL_PATTERN = /^byok-isolation-[a-f0-9]{16}@soleur\.test$/`. `beforeAll`/`afterAll` cleanup throws on non-matching emails (`hr-destructive-prod-tests-allowlist`). No risk of hitting real QA/prod accounts.
- **Research reconciliation table** flagged three spec-vs-reality mismatches: (a) no existing Supabase integration-test harness in the repo, (b) `BYOK_ENCRYPTION_KEY` missing from Doppler `dev` (dev-fallback in `byok.ts:27-31` activates), (c) Supabase dev project is shared mutable — allowlist gate is the mitigation.
- **Residual-risk master-key rotation runbook** captured as a 5-step stub (generate → dual-read `key_version=3` → lazy re-encrypt → promote → retire). Not in scope; lands in a Post-MVP follow-up issue.
- **Column-type drift guard** added to Phase 5 after learning `2026-03-17-postgrest-bytea-base64-mismatch.md` surfaced: asserts `typeof encrypted_key === "string"` and not `\x`-prefixed so a future bytea regression fails the test for the right reason.
- **Code-review overlap** verified live via `gh issue list --label code-review` + body grep against the 4 BYOK-touching files — no open scope-outs.

### Components Invoked

- `skill: soleur:plan`
- `skill: soleur:deepen-plan`
- Direct file reads, Doppler CLI, `gh issue view 1449`, `markdownlint-cli2 --fix`
