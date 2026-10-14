---
feature: skip-api-key-onboarding
type: feat
date: 2026-05-29
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issue: 4642
pr: 4640
branch: feat-skip-api-key-onboarding
brainstorm: knowledge-base/project/brainstorms/2026-05-29-skip-api-key-onboarding-brainstorm.md
spec: knowledge-base/project/specs/feat-skip-api-key-onboarding/spec.md
---

# Plan: Skippable "Connect your API key" onboarding (delegation-aware)

## Overview

Make the mandatory `/setup-key` onboarding gate skippable. A user can choose
"Set up later", land in the app, and is told (factually) that Soleur requires a
key and can set it anytime in **Settings → Connected services** (which already
exists). Every gate becomes **effective-key-aware** — own valid key **OR** an
active, consented BYOK delegation — which both enables the skip and fixes a
pre-existing bug where delegated-but-keyless users are wrongly force-redirected
to `/setup-key`. Enforcement (`agent-runner.getUserApiKey` → `KeyInvalidError`
before any Anthropic call) is untouched; this is routing + UX only.

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Codebase reality | Plan response |
|---|---|---|
| D6: persist skip via `useOnboarding.updateUserField` (client-side) | Migration 006 did `REVOKE UPDATE ON public.users FROM authenticated; GRANT UPDATE (email)`. Migrations 012 & 049 add onboarding dismissal columns but **never GRANT UPDATE** on them — so client-side `updateUserField` writes to those columns silently fail (data-integrity-guardian confirmed via grep; learnings #10/#11). **Note:** mig 049's own comment claims `runtime_explainer_dismissed_at` is "Set via useOnboarding.updateUserField" — that write is itself silently failing in prod today (the dismissals don't persist across sessions). Do NOT trust that comment as precedent. Pre-existing bug → filed as a separate tracking issue (`wg-when-an-audit-identifies-pre-existing`); out of scope here. | Persist the skip via a **server route** (`POST /api/setup-key/skip`, service client, asserts affected-row count `=== 1`) — learning #2's recommended pattern for redirect-gating state. Do NOT use the client `updateUserField` path. Migration adds the column only (no grant needed — service role bypasses; `authenticated` keeps the table-level SELECT default for reads). |
| Brainstorm implied server-side layout gating for the banner | `app/(dashboard)/layout.tsx` is `"use client"` — cannot run the service-role `resolve_byok_key_owner` RPC. | Add `GET /api/byok/effective-status` → `{ hasEffectiveKey }`; the `NoApiKeyBanner` self-fetches its gating state. |
| TR2: helper takes `(userId, workspaceId)` | `resolve_byok_key_owner` is `REVOKE`d from `authenticated` (service-role only); the TS path derives workspace via `getDefaultWorkspaceForUser` → `resolveOrgIdForWorkspace` → `isByokDelegationsEnabled(orgId)` **before** the RPC and falls back to a caller-bound lease when the flag is off. | Helper signature is `userHasEffectiveByokKey(callerUserId)`; it internally mirrors `resolveKeyOwnerThenLease`'s own-key-first + flag-gated-delegation sequence using a service client. |
| Migration needs a `.down.sql` (CTO) | 049 has none; 084 (most recent BYOK migration) does. | Include `085_*.down.sql` mirroring 084. |

## User-Brand Impact

**If this lands broken, the user experiences:** a skipped (or delegated) user
trapped in a `/setup-key` ↔ chat redirect loop, or a silent dead-end where
actions do nothing with no explanation — for a non-technical founder this reads
as "the product is broken."

**If this leaks, the user's credentials are exposed via:** any skip path that
weakened the chat-time key gate so a keyless session could reach paid Anthropic
calls. Mitigated by NG1 (enforcement path untouched; skip is routing-only).

**Brand-survival threshold:** single-user incident. `requires_cpo_signoff: true`
— CPO reviewed at brainstorm (carry-forward below); `user-impact-reviewer` runs
at PR review.

## Implementation Phases

Phases are ordered contract-before-consumer; the whole feature merges atomically.

### Phase 1 — Migration (contract)
- Create `apps/web-platform/supabase/migrations/085_setup_key_skipped_state.sql`:
  a `-- LAWFUL_BASIS: contract (Art. 6(1)(b)) — operational onboarding-state flag` annotation (gdpr-gate Art-6),
  `ALTER TABLE public.users ADD COLUMN IF NOT EXISTS setup_key_skipped_at timestamptz NULL;`
  + `COMMENT ON COLUMN` (mirror 049's comment shape: "NULL = not skipped; non-NULL
  = user chose 'Set up later'. Set via POST /api/setup-key/skip. #4642").
- Create `085_setup_key_skipped_state.down.sql`: `ALTER TABLE public.users DROP COLUMN IF EXISTS setup_key_skipped_at;` (mirror 084's down).
- No GRANT: the column is written only by the service-role skip route; `authenticated` keeps SELECT (already granted) for the onboarding fetch.

### Phase 2 — Effective-key helper (contract)
- Add `userHasEffectiveByokKey(callerUserId: string, opts: { onErrorReturn: boolean }): Promise<boolean>` to
  `apps/web-platform/server/byok-resolver.ts`. **Do NOT reimplement the RPC's own-key short-circuit** — that short-circuit is UNFILTERED (`EXISTS(api_keys WHERE user_id=caller)`, mig 083), so a user with only an *invalid* anthropic key would make `resolve_byok_key_owner` return `(caller, null)` and the helper would wrongly report a key. Instead:
  1. Service client. Query own valid key: `api_keys` `provider='anthropic'`, `is_valid=true`, `limit 1` → if present, `return true`. This matches the **lease's** actual success requirement and preserves the existing callback/accept-terms gate behavior (invalid-key users still routed to `/setup-key`). Inline-comment citing `resolveKeyOwnerThenLease` lines for the parity assumption.
  2. Else derive workspace (`getDefaultWorkspaceForUser` — the SAME default-workspace the runtime uses; do NOT broaden to "any workspace with a delegation", which would make the gate more permissive than enforcement and recreate the chat dead-end) → `resolveOrgIdForWorkspace` → `isByokDelegationsEnabled(orgId, identity)`. Flag off → `return false`.
  3. Flag on → `.rpc("resolve_byok_key_owner", { p_caller_user_id, p_workspace_id }).maybeSingle()`. Return `true` **only when `data?.delegation_id != null`** (a real delegation row); own-key rows (`delegation_id === null`) were already handled in step 1, and `null` data → `false`.
  4. On any thrown/`error` path: log via `reportSilentFallback` and `return opts.onErrorReturn`. Callers choose direction: **redirect gates pass `onErrorReturn: true`** (fail-open — do NOT trap a possibly-delegated user at `/setup-key`; chat-time enforcement is authoritative and the loop is broken in Phase 5); the **status endpoint passes `onErrorReturn: false`** (fail-closed — show the banner rather than hide it and lie to a keyless user). The route maps any thrown error to the bare boolean; never serialize a `ByokDelegationError` subtype (no `workspaceIdHash`/`delegationId` leak).

### Phase 3 — Redirect gates (consumers; enforcement-surface parity, learning #7)
- `app/(auth)/callback/route.ts`: in the `tcAcceptedVersion === TC_VERSION` branch, replace the inline `api_keys` query with `hasKey = await userHasEffectiveByokKey(user.id)`. Fetch `setup_key_skipped_at` alongside the existing `repo_status` service-client read. Logic: `if (!hasKey && !setup_key_skipped_at) → "/setup-key"; else → repo check → "/connect-repo" | "/dashboard"`.
- `app/api/accept-terms/route.ts` `getRedirectDestination`: `hasKey = await userHasEffectiveByokKey(userId)`; read `setup_key_skipped_at`; `return (hasKey || skipped) ? "/dashboard" : "/setup-key"`. (Keeps accept-terms' existing `/dashboard` target shape; the pre-existing accept-terms-skips-connect-repo inconsistency is out of scope — noted in Risks.)

### Phase 4 — Skip action (writer + UI)
- Create `app/api/setup-key/skip/route.ts`: POST, `validateOrigin`/`rejectCsrf` (mirror accept-terms), service client `update({ setup_key_skipped_at: now })` `.eq("id", user.id)`, check affected-row count (learning #2) → 500 + `reportSilentFallback` on miss; return `{ ok: true }`.
- `app/(auth)/setup-key/page.tsx`: add a "Set up later" secondary action below "Save key". On click: POST to the skip route, then route the user onward. **Phase 0 task:** verify `/connect-repo` performs NO key-gated action (clone/agent run) — it lives in the `(auth)` group with NO `NoApiKeyBanner`, so a keyless user stuck there is an invisible dead-end (spec-flow P0). If `/connect-repo` is keyless-safe → `router.push("/connect-repo")`; if it is key-gated → `router.push("/dashboard")` instead. Add the warning copy (CLO-approved, FR4): *"Soleur requires your own Anthropic API key to function. You can add it anytime in Settings. Until then, tasks are disabled. Getting a key requires a separate, paid Anthropic account."*

### Phase 5 — Break the redirect loop (in-chat CTA)
- `lib/ws-client.ts`: in the `errorCode === "key_invalid"` handler (currently
  `window.location.href = "/setup-key"`), **drop ONLY the `window.location.href` line** and render an in-chat actionable error + CTA ("Add your API key to run Soleur" linking to `/setup-key`). **Critically, PRESERVE the existing teardown sequence** (`mountedRef.current = false`, `clearTimeout(...)`, `onclose = null`, `ws.close()`) — if `onclose` is left attached, the backoff reconnect (`ws-client.ts:~228-240`) fires → `/ws` re-auth storm → repeated `getUserApiKey` → `key_invalid` loop (security P1). The CTA copy is client-side static text, so it does NOT pass `msg.message` through and needs no `sanitizeErrorForClient` (that lives server-side in `ws-handler.ts`). Reuse the typed `WSErrorCode` union (learnings #5/#6).
  **Phase 0 precondition:** grep the exact current handler + teardown shape before editing.

### Phase 6 — Degraded banner
- Create `app/api/byok/effective-status/route.ts`: GET, authed, **userId strictly from `supabase.auth.getUser()` — reject/ignore any query or body param** (IDOR guard; mirror accept-terms). Returns `{ hasEffectiveKey, pendingDelegation }` where `hasEffectiveKey = await userHasEffectiveByokKey(user.id, { onErrorReturn: false })` (fail-closed) and `pendingDelegation` = true iff the user has a granted-but-not-yet-accepted inbound delegation (a `byok_delegations` row for them with no current-version acceptance — query via service client). Map any thrown error to a bare boolean (no error serialization).
- Create `components/dashboard/no-api-key-banner.tsx` mirroring `runtime-explainer-banner.tsx`: self-fetches `/api/byok/effective-status`; renders only when `hasEffectiveKey === false`. **Branch the copy/CTA on `pendingDelegation`** (spec-flow P0 — otherwise a grant-holder is told to buy a separate Anthropic account when one click would unblock them): `pendingDelegation` → "You've been granted shared access — accept it to start running tasks" linking to the #4627 acceptance surface; else → "Tasks are disabled until you add a key" + CTA → `/dashboard/settings/services`. Non-dismissible while keyless (the capability is genuinely blocked). **Phase 0 task:** locate #4627's delegation-acceptance surface (likely a login interstitial); if it always prompts before dashboard, the `pendingDelegation` banner branch is belt-and-suspenders but ship it defensively.
- Mount `<NoApiKeyBanner />` in `app/(dashboard)/layout.tsx` near the existing banner region. (Keep `/ws` in PUBLIC_PATHS — learning #8 — no routes.ts change needed; skip is NOT a public path, it's an authed server-written flag per learning #2.)
- **Kept despite a simplicity dissent** (code-simplicity-reviewer P1 argued the banner is redundant with the Phase-5 in-chat CTA + FR4 warning, recommending Phase 6 be cut). Rejected: CPO ruled the persistent banner load-bearing at brainstorm — the chat CTA fires only if the user opens chat and types; a non-technical founder who skips and lands on an empty dashboard has no other signal. Dissent recorded; not folded.

### Phase 7 — Tests
- Unit-test the four effective-key states (own key / active delegation / granted-not-accepted / truly keyless) against the redirect decision + skip flag. Extract the redirect-decision logic into a framework-free `lib/` helper if needed for Vitest (learning #4: `@/` aliases don't resolve in Vitest). Place tests under `test/` per the runner's `include:` globs (NOT co-located).

## Files to Create
- `apps/web-platform/supabase/migrations/085_setup_key_skipped_state.sql` (+ `.down.sql`)
- `apps/web-platform/app/api/setup-key/skip/route.ts`
- `apps/web-platform/app/api/byok/effective-status/route.ts`
- `apps/web-platform/components/dashboard/no-api-key-banner.tsx`
- `apps/web-platform/test/...` effective-key + redirect-decision tests

## Files to Edit
- `apps/web-platform/server/byok-resolver.ts` — add `userHasEffectiveByokKey`
- `apps/web-platform/app/(auth)/callback/route.ts` — delegation+skip-aware redirect
- `apps/web-platform/app/api/accept-terms/route.ts` — delegation+skip-aware `getRedirectDestination`
- `apps/web-platform/app/(auth)/setup-key/page.tsx` — "Set up later" + warning copy
- `apps/web-platform/lib/ws-client.ts` — `key_invalid` → in-chat CTA
- `apps/web-platform/app/(dashboard)/layout.tsx` — mount `NoApiKeyBanner`

## Open Code-Review Overlap
- #2193 (unify billing past_due/unpaid banners + extract `useDismissiblePersistent`) — **Acknowledge.** Distinct concern; the keyless banner is non-dismissible while keyless, unlike billing banners. Not folded in.
- #3739 (extract `reportSilentFallbackWithUser` helper across callback/accept-terms) — **Acknowledge.** New redirect logic uses the existing `reportSilentFallback` pattern; the helper-extraction refactor stays separate.
- #3184 (useOtpFlow), #3374 / #3280 (ws-client refactors) — **Acknowledge.** Incidental substring matches; this plan changes only the `key_invalid` behavior, not those structures.

## Acceptance Criteria

### Pre-merge (PR)
- AC1: `pg_dump`/migration shows `setup_key_skipped_at timestamptz` nullable on `public.users`; `085_*.down.sql` drops it. No GRANT change.
- AC2: `userHasEffectiveByokKey` returns: `true` for own **valid** anthropic key (flag on or off); `false` for own **invalid**/non-anthropic key only (→ routed to /setup-key, preserving existing behavior); `true` for active accepted delegation (flag on, via `delegation_id != null`); `false` for granted-not-accepted delegation; `false` for truly keyless (flag on); and `opts.onErrorReturn` on resolution error, with a Sentry mirror. A workspace-parity test asserts the helper uses the SAME `getDefaultWorkspaceForUser` as `resolveKeyOwnerThenLease`. Covered by Phase-7 unit tests.
- AC3: callback + accept-terms redirect to `/setup-key` ONLY when `!hasEffectiveKey && setup_key_skipped_at IS NULL`; both pass `onErrorReturn: true` (fail-open). A delegated (no-own-key, accepted) user is NEVER sent to `/setup-key`. Verified by unit tests over all states.
- AC4: "Set up later" on `/setup-key` POSTs the CSRF-guarded skip route, which persists `setup_key_skipped_at` and asserts the update affected **exactly 1 row** (≠1 → 500 + Sentry mirror); the page then routes onward per the Phase-0 `/connect-repo` keyless-safe determination.
- AC5: chat-time `key_invalid` renders an in-chat CTA — `grep -n "location.href" lib/ws-client.ts` shows no redirect in the `key_invalid` branch, AND a test asserts the teardown (`mountedRef=false`, `onclose=null`, socket closed, no reconnect) still runs (no reconnect storm).
- AC6: `NoApiKeyBanner` renders iff `/api/byok/effective-status` returns `hasEffectiveKey:false`; hidden for own-valid-key and accepted-delegation users; copy branches on `pendingDelegation` (accept-grant CTA vs add-key CTA → `/dashboard/settings/services`). The endpoint computes `hasEffectiveKey` fail-closed (`onErrorReturn:false`) and ignores any client-supplied user/workspace param (IDOR test: `?userId=<other>` is ignored).
- AC7: `tsc --noEmit` clean; lint clean; `./node_modules/.bin/vitest run <new tests>` green.

### Post-merge (operator)
- AC8: Migration 085 applies via `web-platform-release.yml#migrate` on merge (automated; no operator step). Verify column exists via Supabase MCP read-only query post-deploy.
- AC9: Smoke: a keyless test user (DEV project only) sees skip → dashboard → banner → chat CTA, no redirect loop. Playwright on DEV; never against prod (`hr-dev-prd-distinct-supabase-projects`).

## Observability
```yaml
liveness_signal:
  what: skip-route 2xx rate + effective-status endpoint 2xx rate
  cadence: per-request
  alert_target: Better Stack (existing web-platform log drain)
  configured_in: existing pino logger + Sentry
error_reporting:
  destination: Sentry via reportSilentFallback (same pattern as accept-terms)
  fail_loud: skip-route 0-row update → 500 + Sentry; helper resolution error → Sentry mirror (then fail-open)
failure_modes:
  - mode: skip write silently no-ops (grant/RLS) → user re-trapped on next login
    detection: skip-route affected-row-count check → 500 + Sentry
    alert_route: Sentry issue
  - mode: effective-key helper errors → wrong banner/redirect
    detection: reportSilentFallback mirror on the catch path
    alert_route: Sentry issue
  - mode: redirect loop regression
    detection: AC5 grep gate + Phase-7 test + DEV Playwright smoke
    alert_route: CI / pre-merge
logs:
  where: pino → Better Stack; Sentry for errors
  retention: existing web-platform retention
discoverability_test:
  command: "curl -s -H 'cookie: <dev-session>' https://<dev-host>/api/byok/effective-status | jq .hasEffectiveKey"
  expected_output: "true|false (no ssh required)"
```

## Domain Review (carry-forward from brainstorm)

**Domains relevant:** Product, Engineering, Legal

### Engineering (CTO)
**Status:** reviewed (carry-forward). Persist as nullable timestamptz; central hazard is the chat→/setup-key loop (Phase 5 fix); enforcement path untouched (NG1). Plan-time research refined the persistence mechanism to a server route (Research Reconciliation row 1).

### Legal (CLO)
**Status:** reviewed (carry-forward). Near no-op; no new processing activity, no three-doc privacy change. Copy strengthened to factual "requires / separate, paid Anthropic account / Settings" (FR4). gdpr-gate (Phase 2.7) run at plan time — see below.

### Product/UX Gate
**Tier:** advisory (modifies existing onboarding screen + adds one banner; reuses existing component/token patterns — no new multi-step flow). **Decision:** auto-accepted (pipeline carry-forward). **Agents invoked:** CPO (brainstorm carry-forward). **Skipped specialists:** ux-design-lead (brainstorm D12: surfaces are minor modifications mirroring runtime-explainer-banner; no new screens). **Pencil available:** N/A.

## Risks & Mitigations
- **Redirect loop** (skip→chat→/setup-key): broken in Phase 5 (in-chat CTA, no hard redirect). Highest-priority invariant; AC5 + test + smoke.
- **Fail-open helper** could send a fresh keyless user to dashboard during a transient error: acceptable — not a trap (banner + CTA present), and chat-time enforcement is authoritative. Documented inline + Sentry-mirrored.
- **Enforcement-surface parity** (learning #7): exactly two redirect surfaces gate on the key (callback, accept-terms); both updated. Middleware does not gate on key. `git grep` for other `api_keys`+`is_valid`+`provider='anthropic'`+`limit(1)` redirect queries at Phase 0 to confirm no third surface.
- **Granted-not-accepted delegation** (brainstorm Open Q1): such users have no effective key → currently routed to `/setup-key`/banner. Whether to branch them to a "accept the delegation" CTA depends on whether #4627's consent flow already prompts on login. **Phase 0 task:** confirm; if it does, no extra work; if not, file a fast-follow issue (do not expand scope).
- **accept-terms vs callback target inconsistency** (accept-terms sends has-key users to `/dashboard`, callback to `/connect-repo`): pre-existing; out of scope. Noted only.

## Test Scenarios
1. Own valid key → no /setup-key redirect, no banner (flag on and off).
2. Active accepted delegation, no own key → no /setup-key redirect, no banner (regression test for the pre-existing bug).
3. Granted-not-accepted delegation → /setup-key (or delegation-accept CTA per Phase-0 finding).
4. Truly keyless, not skipped → /setup-key.
5. Truly keyless, skipped → onward dest (Phase-0 connect-repo determination) / /dashboard (accept-terms); banner shows; chat shows in-chat CTA (no loop).
6. Skip-route update affecting ≠1 row → 500 + Sentry.
7. Delegation-withdrawn-after-skip: user skipped, relied on a delegation, delegation later withdrawn (#4627) → now keyless. Assert: no force-redirect at next login (`skipped` honored, no loop), banner re-appears (keys off effective-key, not the skip flag).
8. Granted-not-accepted + skipped → dashboard banner shows the **accept-grant** copy (not "buy a key").

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty or placeholder-only fails `deepen-plan` Phase 4.6 — this one is filled (threshold: single-user incident).
- Phase 0 (work): grep the exact `ws-client.ts` `key_invalid` handler and the exact callback/accept-terms `api_keys` queries before editing — line numbers drift.
- Verify `(dashboard)/layout.tsx` banner mount region renders above `children`; it is a client component, so banner gating MUST come from the `/api/byok/effective-status` fetch, never a server-side compute in the layout.
