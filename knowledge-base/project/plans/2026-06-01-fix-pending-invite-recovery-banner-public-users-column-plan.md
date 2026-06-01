---
title: "fix: pending-invite recovery banner renders null — raw_user_meta_data on public.users (42703)"
date: 2026-06-01
type: fix
status: planned
branch: feat-one-shot-multi-user-workspace-invites-pending
issue: 4715
prior_pr: 4713
lane: single-domain
requires_cpo_signoff: false
brand_survival_threshold: single-user incident
---

## Enhancement Summary

**Deepened on:** 2026-06-01
**Sections enhanced:** Implementation (Phase 1 test sketch), Research Reconciliation, Risks (precedent-diff), Files to Edit
**Gates run:** 4.4 precedent-diff (test-mock pattern), 4.45 verify-the-negative, 4.6 User-Brand Impact halt (PASS), 4.7 Observability gate (PASS — all 5 fields, no SSH), 4.8 PAT-shaped halt (PASS — no match)

### Key Improvements
1. **Test now uses the canonical `mockQueryChain` helper** (`test/helpers/mock-supabase.ts`) which exposes `.select` as a vitest `Mock` — the regression test captures `chain.select.mock.calls[0][0]` directly, matching the `workspace-resolver.test.ts` / `byok-resolver-fail-closed.test.ts` precedent rather than hand-rolling a mock.
2. **Verified the negative claim "only one production file changes":** `inviter_name` has three downstream consumers (recovery banner, public invite page, chat layout) but they consume the *output* field `inviter_name: string`, whose type is UNCHANGED. The fix changes only the internal derivation, not the interface — confirmed no consumer edit needed.
3. **Precedent-diff:** the bug-class precedent (mock that ignores the select arg) is the existing `chainableMock` in `workspace-invitation-identity.test.ts`; the FIX-pattern precedent (arg-capturing mock) is `mockQueryChain` + `mockFrom.mock.calls` assertions. Both cited inline.

### New Considerations Discovered
- The `unit` vitest project pins `isolate: true` (`vitest.config.ts`) for module-init env-var safety — the new test must not rely on cross-file module-graph state (it doesn't; it's self-contained).
- `getPendingInvitesForUser` imports `@/server/observability` (`reportSilentFallback`) and `@/server/logger` at module scope — the test MUST mock both, or the import chain pulls in `SENTRY_USERID_PEPPER` env reads.

# 🐛 fix: pending-invite recovery banner renders null — `raw_user_meta_data` on `public.users` (Postgres 42703)

## Overview

PR #4713 (closing issue #4715) added an in-app **recovery banner** so a keyless invitee who abandoned the `/invite` flow and landed on `/dashboard` can still accept their workspace membership in-app. The banner self-fetches `GET /api/workspace/pending-invites`, which calls `getPendingInvitesForUser(userId, email)` in `apps/web-platform/server/workspace-invitations.ts`.

That function's embedded `select` references `raw_user_meta_data` on the `users` relationship. PostgREST/supabase-js resolves the `users` FK target to **`public.users`**, which has **no `raw_user_meta_data` column** — that column exists only on **`auth.users`**. Both query branches (`byUserId` and `byEmail`) therefore fail with Postgres error **42703** `column users_1.raw_user_meta_data does not exist`, `allRows` is empty, the function returns `[]`, the API returns `{invites: []}`, and the banner renders `null` **every time**.

Net effect: the invitee never sees an in-app way to accept, the invite stays `Pending` forever, and they remain stranded in their own empty solo workspace — the exact deadlock #4715/#4713 was meant to resolve. The root cause was **confirmed against the live prod database** (re-running the identical query WITHOUT `raw_user_meta_data` returns the invitee's valid pending invite); this plan re-verified every file/line reference against the worktree.

**The fix is minimal and single-file:** remove `raw_user_meta_data` from the embedded `select`, remove the field from the inviter type, and derive `inviter_name` from the columns that actually exist on `public.users`.

**Why the regression shipped green:** the existing unit/route tests mock the supabase client with a `chainableMock` whose `.select()` is `vi.fn(() => chain)` — it **ignores the select argument entirely** and returns canned data regardless of column names. The broken column was never exercised. This plan adds a regression test that asserts on the **actual select string** passed to `.select(...)`, which is the cheapest check that would have caught this class.

**Scope discipline:** this is a targeted bug fix, NOT a refactor. Explicitly out of scope: the redirect-precedence / accept-first reorder logic and the owner-delegation prompt (both shipped by #4713 and unrelated to the column bug).

## Research Reconciliation — Spec vs. Codebase

All premise claims in the task arguments were re-verified against the worktree at plan time. No divergences found.

| Premise claim | Verified reality | Plan response |
|---|---|---|
| Bug lives in `apps/web-platform/server/workspace-invitations.ts` lines ~74, ~128, ~136 | Confirmed: `raw_user_meta_data` at lines **74** (select), **128** (type), **136** (derivation). `inviter:users!...fkey(email, raw_user_meta_data)` at 72-75. | Fix all three lines. |
| `public.users` has no `raw_user_meta_data` / `full_name` column | Confirmed via migrations. `public.users` columns: `id, email, workspace_path, workspace_status, created_at` (`001_initial_schema.sql:6-13`), `tc_accepted_at` (`005:3-4`), `github_username` (`016_github_username.sql:5`). No `full_name`, no `raw_user_meta_data`. | Derive `inviter_name` from `email`. |
| `raw_user_meta_data->>'full_name'` only valid on `auth.users` | Confirmed: `075_workspace_invitations.sql:469-471` selects `COALESCE(raw_user_meta_data->>'full_name', email) FROM auth.users` — proving the column is auth-only. | N/A — confirms the diagnosis. |
| `github_username` IS selectable on `public.users` | Confirmed: `016_github_username.sql:5`. Consumed at `server/github-login.ts:36,69`. | **Decision below**: optional richer fallback. |
| Only 3 non-test `raw_user_meta_data` refs in `apps/web-platform` source, all in this function | Confirmed via `grep -rn raw_user_meta_data apps/web-platform --include=*.ts --include=*.tsx` excluding test dirs → exactly the 3 lines in `workspace-invitations.ts`. | Single-file fix is complete. |
| `getPendingInvitesForUser` also used server-side by chat layout | Confirmed: two callers — `app/api/workspace/pending-invites/route.ts:14` (recovery banner) and `app/(dashboard)/dashboard/chat/layout.tsx:47` (server-mounted `PendingInviteBanner`). | Single fix repairs both surfaces. |
| Issue #4715 status | CLOSED, closed by merged PR #4713 (merged 2026-05-31). Premise (shipped-but-not-resolved) holds — the recovery path is dead code. | Re-open path is the fix, not a re-scope. |
| Test runner | **vitest** (`apps/web-platform/package.json` `scripts.test: "vitest"`, `test:ci: "vitest run"`). `bunfig.toml` `[test] pathIgnorePatterns = ["**"]` blocks ALL bun test discovery. Node tests must match `test/**/*.test.ts` (`vitest.config.ts:44`). | New test goes in `apps/web-platform/test/server/`, runs via `./node_modules/.bin/vitest run`. |

## User-Brand Impact

**If this lands broken, the user experiences:** an invitee who clicks an invite, abandons mid-flow, and reaches `/dashboard` sees **no banner and no path to accept** — they are silently stranded in an empty solo workspace while the inviter sees the invite stuck on "Pending" indefinitely. This is the first multi-user collaboration touchpoint; a broken one reads as "Soleur can't even do team invites."

**If this leaks, the user's data / workflow / money is exposed via:** N/A — no data exposure vector. This is a read-path availability bug (a query that errors and returns empty), not a confidentiality or integrity issue. No new columns are read; the fix removes a non-existent column from a `select`.

**Brand-survival threshold:** `single-user incident` — a single invitee hitting this deadlock at the multi-user onboarding moment is a brand-credibility incident for the team-workspaces capability (roadmap MU4). Note: the bug is a missing-feature/availability regression, not a security or data-leak surface, so no CPO sign-off is gated (`requires_cpo_signoff: false`); the threshold drives review-time `user-impact-reviewer` coverage of the recovery-path availability invariant.

## Decision: `inviter_name` fallback source

`public.users` exposes both `email` and `github_username` (both selectable). The arguments state email is sufficient. Two options:

- **Option A (minimal, recommended):** `select(email)` only; `inviter_name = inviter?.email ?? "A team member"`.
- **Option B (richer):** `select(email, github_username)`; `inviter_name = inviter?.github_username ?? inviter?.email ?? "A team member"`.

**Recommendation: Option A.** It is the smallest correct change, matches the arguments' "email is sufficient," and avoids surfacing a GitHub handle as a display name where the banner copy reads "<name> invited you." Option B is a one-line, schema-valid extension if product later wants a friendlier label; it is noted as a deferral, not built here. (The deepen-plan / plan-review pass may revisit; either is schema-correct and 42703-free.)

## Implementation Phases

### Phase 1 — RED: regression test that exercises the real select string

The defect class is "the mock ignores the select argument." The regression test must assert on the **string passed to `.select(...)`**.

1. **New test file:** `apps/web-platform/test/server/workspace-invitations-pending-select.test.ts` (matches `vitest.config.ts:44` node-project glob `test/**/*.test.ts`).
2. Use the canonical shared helper `mockQueryChain` from `test/helpers/mock-supabase.ts` (it exposes `.select`, `.eq`, `.is`, `.gt` as vitest `Mock`s and is PromiseLike — `await chain.select().eq()...` resolves `{ data, error }`). Wire it via `vi.hoisted()` + `vi.mock("@/lib/supabase/service", ...)` exactly as the helper's docstring and `workspace-resolver.test.ts` show. Also mock `@/server/logger` and `@/server/observability` (`reportSilentFallback: vi.fn()`) — the SUT imports both at module scope (the `@/server/observability` mock also avoids the module-init `SENTRY_USERID_PEPPER` env read).
   ```ts
   import { mockQueryChain } from "../helpers/mock-supabase";
   const { mockFrom } = vi.hoisted(() => ({ mockFrom: vi.fn() }));
   vi.mock("@/lib/supabase/service", () => ({
     createServiceClient: vi.fn(() => ({ from: mockFrom })),
   }));
   vi.mock("@/server/observability", () => ({ reportSilentFallback: vi.fn() }));
   vi.mock("@/server/logger", () => ({ createChildLogger: () => ({ error: vi.fn(), info: vi.fn() }) }));
   ```
3. In the test, `mockFrom.mockReturnValue(mockQueryChain([], null))` (both Promise.all branches share the same chain shape; empty data is fine — we assert on the SELECT STRING, not the result). Call `await getPendingInvitesForUser("11111111-2222-3333-4444-555555555555", "alice@example.com")`.
4. **Assertions (the gate):**
   - `expect(mockFrom).toHaveBeenCalledWith("workspace_invitations")`.
   - Capture the select string from the chain returned by `mockFrom`: `const chain = mockFrom.mock.results[0].value; const selectArg = chain.select.mock.calls[0][0] as string;`.
   - Assert it does **NOT** reference auth.users-only columns: `expect(selectArg).not.toMatch(/\b(raw_user_meta_data|raw_app_meta_data|encrypted_password|email_confirmed_at|last_sign_in_at)\b/);`.
   - Assert the select **DOES** still embed the inviter relationship and `email` (so a future "fix" that drops the embed entirely also fails): `expect(selectArg).toMatch(/inviter:users!workspace_invitations_inviter_user_id_fkey/)` and `expect(selectArg).toMatch(/email/)`.
   - **Output-shape assertion** (so the mapped result is also covered, not just the select string): feed one well-formed row through `mockQueryChain([{ id: "i1", workspace_id: "w1", role: "member", expires_at: "...", created_at: "...", workspaces: { name: "Acme" }, inviter: { email: "boss@acme.com" } }])` in a second test case and assert the returned `PendingInvite.inviter_name === "boss@acme.com"`, and that a row with `inviter: { email: null }` yields `inviter_name === "A team member"`.
5. Run `./node_modules/.bin/vitest run test/server/workspace-invitations-pending-select.test.ts` from `apps/web-platform/`. Confirm it **FAILS** against current code (select still contains `raw_user_meta_data`). This is the RED proof the test catches the real bug.

> **Precedent (deepen-plan Phase 4.4):** the bug-class precedent — a mock that *ignores* the select arg — is `chainableMock` in `test/server/workspace-invitation-identity.test.ts` (`select: vi.fn(() => chain)`), which is exactly why the regression shipped green. The fix-pattern precedent — an *arg-capturing* mock asserted via `mock.calls` / `toHaveBeenCalledWith` — is `test/server/workspace-resolver.test.ts` (`expect(supabase.from).toHaveBeenCalledWith("workspace_members")`) and `test/server/byok-resolver-fail-closed.test.ts`. The new test adopts the fix-pattern verbatim via the shared `mockQueryChain` helper. No novel test infrastructure is introduced.

> Note: a full integration test against live schema is NOT feasible in CI (no prod DB, `hr-dev-prd-distinct-supabase-projects`). The select-string assertion is the deterministic substitute that removes the mock's blind spot.

### Phase 2 — GREEN: the single-file fix

Edit `apps/web-platform/server/workspace-invitations.ts` only.

1. **Embedded select (lines 72-75):** remove `raw_user_meta_data` from the `inviter:users!...fkey(...)` embed, keeping `email`:
   ```ts
   inviter:users!workspace_invitations_inviter_user_id_fkey(
     email
   )
   ```
2. **Inviter type (lines 126-129):** drop the `raw_user_meta_data` field:
   ```ts
   const inviter = row.inviter as {
     email: string | null;
   } | null;
   ```
3. **Derivation (lines 135-136):** derive from email:
   ```ts
   inviter_name: inviter?.email ?? "A team member",
   ```
4. Run `./node_modules/.bin/vitest run test/server/workspace-invitations-pending-select.test.ts` → must now **PASS**.

### Phase 3 — Regression-proof the full suite + types

1. `./node_modules/.bin/vitest run test/server/` (and any test importing `workspace-invitations`) — confirm the existing 5 tests (`workspace-invitations-revoke.test.ts`, `workspace-invitations-revoke.integration.test.ts`, `cancel-invite-route.test.ts`, `workspace-invitation-identity.test.ts`, `invite-page.test.tsx`) still pass.
2. `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — confirm the type removal produces no TS2322/TS2339 elsewhere (the `inviter` shape is local to this function; no cross-consumer widening expected, but verify per `hr-type-widening-cross-consumer-grep`).
3. Full package test gate per the package's own runner: `npm run -w apps/web-platform test:ci` (= `vitest run`).

## Files to Edit

- `apps/web-platform/server/workspace-invitations.ts` — remove `raw_user_meta_data` from embedded select (L72-75), inviter type (L126-129), and `inviter_name` derivation (L135-136). **The only production file changed.**

> **Verify-the-negative (deepen-plan Phase 4.45):** `inviter_name` has three downstream consumers — `components/dashboard/pending-invite-banner-recovery.tsx:24,58`, `app/(public)/invite/[token]/page.tsx:79`, `app/(dashboard)/dashboard/chat/layout.tsx:51`. None require editing: the public `PendingInvite.inviter_name` / `InvitationDetails.inviter_name` field type is and remains `string` (lines 23, 53 of `workspace-invitations.ts`). The fix changes only the *internal derivation* of that string (from a never-resolved `full_name` lookup to `email`), not the interface contract. Confirmed via grep: the only edits to `inviter_name`'s producer-side type are inside `workspace-invitations.ts`.

## Files to Create

- `apps/web-platform/test/server/workspace-invitations-pending-select.test.ts` — regression test asserting the select string passed to `.from("workspace_invitations").select(...)` does not reference `raw_user_meta_data` (or other auth.users-only columns) and still embeds the inviter `email`.

> No `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` files are created → no mechanical UX-gate escalation.

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` queried; no open scope-out references `workspace-invitations.ts` or `pending-invites`.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `grep -c raw_user_meta_data apps/web-platform/server/workspace-invitations.ts` returns **0**.
- [ ] `grep -rn raw_user_meta_data apps/web-platform --include=*.ts --include=*.tsx` returns **no matches** outside `knowledge-base/` (i.e., zero in `apps/web-platform` source AND test).
- [ ] New test `test/server/workspace-invitations-pending-select.test.ts` exists and, when temporarily reverted against the broken column, **fails** (RED proven in Phase 1); against the fix, **passes**.
- [ ] The new test asserts the captured `.select()` string does not match `/raw_user_meta_data/` AND still matches `/inviter:users!workspace_invitations_inviter_user_id_fkey/` and `/email/`.
- [ ] `./node_modules/.bin/vitest run test/server/` (run from `apps/web-platform/`) — all tests pass, including the pre-existing 5 invitation tests.
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — clean (no new type errors from the `inviter` type removal).
- [ ] `inviter_name` still resolves to a non-empty display value for every row (`email` when present, `"A team member"` otherwise) — verified by a unit assertion on the mapped output, not just the select string.
- [ ] PR body uses `Ref #4715` (the issue is already CLOSED by #4713; do NOT use `Closes` — the closure already happened, this PR repairs the dead recovery path under the same issue).

### Post-merge (operator)

- [ ] **Automation: post-merge container restart is automatic** — `web-platform-release.yml` path-filtered `on.push` restarts the Docker container on any merge to `main` touching `apps/web-platform/**`. No separate operator step. (No DB migration in this PR, so no migration apply needed.)
- [ ] QA verification per Test Scenarios below.

## Test Scenarios (QA)

Primary recovery surface (`/dashboard`) and the chat surface both feed off `getPendingInvitesForUser`; verify both.

1. **API returns the invite (the core bug):** As an authenticated invitee with a valid, non-expired, non-accepted, non-declined, non-revoked pending invite (matched by `invitee_user_id` OR lowercased `invitee_email`), `GET /api/workspace/pending-invites` returns `{ invites: [ { id, workspace_name, inviter_name, role, expires_at, created_at } ] }` — **NOT** `{ invites: [] }`. `inviter_name` is the inviter's email (or `"A team member"` if the inviter row has no email).
   - Automatable read-only via the Supabase MCP: confirm a pending row exists for the test invitee, then exercise the route. Use a DEV project / synthesized fixture — never create synthetic users against prod (`hr-dev-prd-distinct-supabase-projects`).
2. **Recovery banner renders on `/dashboard`:** the invitee from scenario 1, sitting on `/dashboard` (a non-`/dashboard/chat` route), sees the `PendingInviteBanner` (Playwright MCP: navigate, assert banner text "invited you to <workspace_name>", assert Accept control present).
3. **No double-render on `/dashboard/chat`:** on a `/dashboard/chat` route the client recovery banner backs off (renders null) and the server-mounted `PendingInviteBanner` (from `chat/layout.tsx`) is the single banner shown.
4. **Graceful empty state:** a user with NO pending invite gets `{ invites: [] }` and no banner — no 500, no Sentry `reportSilentFallback` fired for `get-pending-by-userid` / `get-pending-by-email`.
5. **Accept completes the loop:** clicking Accept calls the existing accept-invite path and the invite transitions to accepted; the banner disappears on reload. (Acceptance flow itself is unchanged by this PR — verify it is no longer unreachable.)

## Observability

```yaml
liveness_signal:
  what: GET /api/workspace/pending-invites returns 200 with the invite array; recovery banner mount issues the fetch on every non-chat /dashboard load
  cadence: on every invitee dashboard page load (event-driven, not scheduled)
  alert_target: Sentry (reportSilentFallback feature="pending-invite-banner-recovery" and feature="workspace-invitations")
  configured_in: apps/web-platform/server/workspace-invitations.ts (reportSilentFallback on query error), apps/web-platform/components/dashboard/pending-invite-banner-recovery.tsx (non-ok + fetch-catch mirrors)
error_reporting:
  destination: Sentry via reportSilentFallback (server) and lib/client-observability reportSilentFallback (client banner)
  fail_loud: true — the 42703 query error is ALREADY mirrored to Sentry at workspace-invitations.ts:99-112 (op=get-pending-by-userid / get-pending-by-email). The bug was a silent EMPTY RESULT downstream of a mirrored error, not an unreported error. Post-fix, those two Sentry ops should stop firing for the 42703 class entirely — their disappearance is the fix's liveness confirmation.
failure_modes:
  - mode: embedded select references a non-existent column (this bug class)
    detection: new vitest select-string regression test (CI) + Sentry op=get-pending-by-* error volume
    alert_route: CI red on PR; Sentry alert on sustained get-pending-by-* errors
  - mode: API returns 500 (banner fetch non-ok)
    detection: reportSilentFallback op=pending-invites-non-ok with status code
    alert_route: Sentry
  - mode: fetch throws (network/parse)
    detection: reportSilentFallback op=pending-invites-fetch
    alert_route: Sentry
logs:
  where: pino childLogger("workspace-invitations") log.error on query failure (stdout → container logs); Sentry for aggregation
  retention: per existing Sentry + container log retention (unchanged)
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/server/workspace-invitations-pending-select.test.ts"
  expected_output: "test passes; select string contains no auth.users-only column and still embeds inviter email"
```

## Domain Review

**Domains relevant:** Product (advisory)

This is a bug fix that restores an existing, already-designed user-facing surface (the recovery banner shipped in #4713) to working order. It creates no new pages, flows, or components — it only makes an existing banner appear when it should. Per the mechanical-escalation rule, no new `components/**/*.tsx` / `page.tsx` / `layout.tsx` files are created → tier is **ADVISORY**, not BLOCKING.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A

#### Findings

The banner's copy, layout, and accept flow already exist and are unchanged. The only behavioral change is that the banner now renders for invitees who previously saw nothing. No copy or wireframe review needed; the user-facing artifact is pre-existing and validated by #4713's design.

## Infrastructure (IaC)

Skipped — no new infrastructure. Pure code change against the already-provisioned `apps/web-platform/server/` surface; no server, service, cron, secret, vendor, or DNS change. No DB migration (the fix removes a column from a query; it does not alter schema).

## GDPR / Compliance

Skipped — no regulated-data surface change. The fix removes a (non-existent) column from a read query and changes the displayed `inviter_name` from a never-resolved value to the inviter's email. The inviter's email is already processed and displayed in the existing invite flow (`075_workspace_invitations.sql:469` derives `COALESCE(raw_user_meta_data->>'full_name', email)` for the same display purpose); no new processing activity, no new data category, no schema/auth/API-contract change. Brand-survival threshold is `single-user incident` but the surface is availability, not data-movement — none of the (a)-(d) expansion triggers fire.

## Risks & Mitigations

- **Risk:** removing the column changes `inviter_name` from (previously-unresolved) `full_name` to `email`. **Mitigation:** `full_name` was never resolvable (the column doesn't exist; the query errored before any row returned), so there is no behavioral regression — only a move from "no banner at all" to "banner with email as the name." Acceptable and intended per the arguments.
- **Risk:** a future edit re-introduces an auth.users-only column into the embedded select. **Mitigation:** the new select-string regression test fails CI on `raw_user_meta_data` (and 4 sibling auth-only columns).
- **Risk:** PostgREST embedded-resource select syntax is finicky. **Mitigation:** the change only REMOVES a field from an already-working embed shape (`inviter:users!fkey(...)`); it does not introduce new embed syntax. The `email`-only embed is the minimal valid form.
- **Risk (out of scope):** redirect-precedence / accept-first reorder and owner-delegation prompt from #4713 are untouched and remain as shipped.

## Sharp Edges

- The existing tests pass because `chainableMock` (`test/server/workspace-invitation-identity.test.ts`) sets `.select = vi.fn(() => chain)` — the select argument is discarded. Any test that mocks supabase this way is BLIND to column-name bugs. The new test must capture and assert the select argument, not just mock-resolve a result.
- Test file MUST live under `apps/web-platform/test/` and match `test/**/*.test.ts` (`vitest.config.ts:44`). A co-located `server/*.test.ts` would be silently skipped by vitest's include globs. Run with `./node_modules/.bin/vitest run <path>` from `apps/web-platform/` — `bun test` is blocked by `bunfig.toml` `pathIgnorePatterns = ["**"]` and will report "filter did not match."
- Issue #4715 is already CLOSED by #4713. Use `Ref #4715` in the PR body, NOT `Closes #4715` — the issue cannot be re-closed and the intent is "repairs the dead recovery path under the original issue."
- A plan whose `## User-Brand Impact` section is empty, contains only TBD/TODO/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is filled with a concrete artifact, exposure-vector N/A rationale, and an explicit threshold.)

## Alternative Approaches Considered

| Approach | Why not chosen |
|---|---|
| Switch the embed FK to `auth.users` to keep `full_name` | supabase-js anon/service embeds resolve through PostgREST against the `public` schema relationship; `auth.users` is not a PostgREST-exposed embeddable relationship here, and `075:469` already shows the codebase reads `full_name` only via a SECURITY DEFINER SQL function against `auth.users`, not via client embeds. Out of scope and higher-risk than the minimal column removal. |
| Add `full_name` to `public.users` via migration + backfill | Scope explosion (migration, backfill, RLS, identity-sync) for a display-label nicety. Email is a correct graceful value. Deferred. |
| Option B: also select `github_username` as a richer fallback | One-line, schema-valid, but surfaces a GitHub handle where copy reads "<name> invited you." Noted as a low-priority product deferral; not built here. |
