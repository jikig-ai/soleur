---
feature: skip-api-key-onboarding
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-05-29-feat-skip-api-key-onboarding-plan.md
issue: 4642
pr: 4640
---

# Tasks: Skippable API-key onboarding (delegation-aware)

## Phase 0 — Preconditions (verify before editing)
- [ ] 0.1 Grep exact current `api_keys` redirect queries in `callback/route.ts` + `accept-terms/route.ts` (line drift). Confirm no THIRD redirect surface gates on the key (`git grep "is_valid" + "provider" + "anthropic" + "limit(1)"`).
- [ ] 0.2 Grep exact `key_invalid` handler + teardown sequence in `lib/ws-client.ts`.
- [ ] 0.3 Verify `/connect-repo` performs NO key-gated action (clone/agent run). Decides skip landing: keyless-safe → `/connect-repo`, else `/dashboard`.
- [ ] 0.4 Locate #4627's delegation-acceptance surface (login interstitial?) for the `pendingDelegation` banner CTA target.

## Phase 1 — Migration (contract)
- [ ] 1.1 `085_setup_key_skipped_state.sql`: `-- LAWFUL_BASIS: contract (Art. 6(1)(b))` annotation + `ADD COLUMN IF NOT EXISTS setup_key_skipped_at timestamptz NULL` + `COMMENT ON COLUMN`. No GRANT.
- [ ] 1.2 `085_setup_key_skipped_state.down.sql`: `DROP COLUMN IF EXISTS` (mirror 084).

## Phase 2 — Effective-key helper (contract)
- [ ] 2.1 Add `userHasEffectiveByokKey(callerUserId, { onErrorReturn })` to `server/byok-resolver.ts`: (1) valid-own-anthropic-key check → true; (2) flag-gated workspace/org resolution; (3) RPC, true only if `delegation_id != null`; (4) error → `onErrorReturn`, Sentry mirror. Inline comment citing `resolveKeyOwnerThenLease` parity lines.

## Phase 3 — Redirect gates (consumers; surface parity)
- [ ] 3.1 `callback/route.ts`: replace inline `api_keys` query with `userHasEffectiveByokKey(user.id, {onErrorReturn:true})`; read `setup_key_skipped_at` alongside `repo_status`; `(!hasKey && !skipped) → /setup-key; else → repo check`.
- [ ] 3.2 `accept-terms/route.ts` `getRedirectDestination`: `(hasKey || skipped) ? /dashboard : /setup-key`, fail-open.

## Phase 4 — Skip action (writer + UI)
- [ ] 4.1 `app/api/setup-key/skip/route.ts`: POST, CSRF (validateOrigin/rejectCsrf), service-client `update({setup_key_skipped_at: now}).eq("id", user.id)`, assert affected rows `=== 1` (else 500 + Sentry).
- [ ] 4.2 `setup-key/page.tsx`: "Set up later" action → POST skip → route per 0.3; add FR4 warning copy.

## Phase 5 — Break redirect loop
- [ ] 5.1 `lib/ws-client.ts`: in `key_invalid`, drop only `window.location.href`; render in-chat CTA; PRESERVE teardown (`mountedRef=false`, `clearTimeout`, `onclose=null`, `close()`).

## Phase 6 — Degraded banner
- [ ] 6.1 `app/api/byok/effective-status/route.ts`: GET, session-only userId (IDOR guard), `{ hasEffectiveKey (onErrorReturn:false), pendingDelegation }`.
- [ ] 6.2 `components/dashboard/no-api-key-banner.tsx`: self-fetch; render iff `!hasEffectiveKey`; copy branches on `pendingDelegation` (accept-grant vs add-key → settings/services); non-dismissible.
- [ ] 6.3 Mount `<NoApiKeyBanner />` in `app/(dashboard)/layout.tsx`.

## Phase 7 — Tests
- [ ] 7.1 Effective-key unit tests: valid-own / invalid-own / accepted-delegation / granted-not-accepted / keyless / error(both directions) / workspace-parity.
- [ ] 7.2 Redirect-decision tests over all states + skip flag (extract framework-free `lib/` helper if needed; tests under `test/` per vitest `include:` globs).
- [ ] 7.3 ws-client teardown + no-reconnect assertion; effective-status IDOR test; banner copy-branch test; delegation-withdrawn-after-skip scenario.
- [ ] 7.4 `tsc --noEmit`, lint, `vitest run` green.

## Post-merge (operator)
- [ ] P.1 Migration 085 auto-applies via `web-platform-release.yml#migrate`; verify column via Supabase MCP read-only query.
- [ ] P.2 DEV-only Playwright smoke of the keyless skip flow (never prod).
