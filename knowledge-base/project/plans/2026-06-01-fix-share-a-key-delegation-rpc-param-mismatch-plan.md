---
type: fix
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# 🐛 fix: "Share a key" toggle no-ops — POST /api/workspace/delegations sends wrong RPC param names

## Overview

On **Settings → Members → Team**, an org owner clicking the **"Share a key"** toggle next to a
keyless member (e.g. `jean.deruelle@gmail.com`, role "Member", "No API key yet") does nothing —
the toggle flips back to off and no delegation is created.

**Root cause (verified, not hypothesized):** the POST branch of
`apps/web-platform/app/api/workspace/delegations/route.ts` invokes the Postgres RPC
`grant_byok_delegation` with **named arguments that do not match the function's signature**, and
**omits a required argument**. PostgREST resolves `rpc()` calls by argument *name*; a name set that
doesn't match any function overload fails to resolve (PGRST202 "Could not find the function … in
the schema cache"). The route maps that error to HTTP 400, and the client's
`if (res.ok) setActive(true)` silently swallows the non-OK response — so the toggle reverts with
no visible error. That is precisely the "click does nothing" symptom.

### The mismatch

Canonical RPC signature — `apps/web-platform/supabase/migrations/064_byok_delegations.sql:412-417`
(the **only** definition; never redefined by a later migration). **No parameter has a DEFAULT**, so
all seven are mandatory:

```sql
grant_byok_delegation(
  p_grantor_user_id      uuid,
  p_grantee_user_id      uuid,
  p_workspace_id         uuid,
  p_daily_usd_cap_cents  int,
  p_hourly_usd_cap_cents int,
  p_expires_at           timestamptz,
  p_actor_user_id        uuid
) RETURNS uuid
```

What the route currently sends — `route.ts:79-86`:

```ts
service.rpc("grant_byok_delegation", {
  p_grantor_user_id: user.id,
  p_grantee_user_id: body.granteeUserId,
  p_workspace_id: body.workspaceId,
  p_daily_cap_cents: body.dailyCapCents,        // ✗ RPC expects p_daily_usd_cap_cents
  p_hourly_cap_cents: body.hourlyCapCents ?? null, // ✗ RPC expects p_hourly_usd_cap_cents
  p_created_by_user_id: user.id,                // ✗ RPC expects p_actor_user_id
  // ✗ MISSING: p_expires_at (required, no DEFAULT)
});
```

Three names are wrong (`p_daily_cap_cents`, `p_hourly_cap_cents`, `p_created_by_user_id`) and
`p_expires_at` is absent entirely. **Any one** of these breaks PostgREST function resolution.

### Working precedent (the correct contract already exists)

The CLI script `apps/web-platform/scripts/byok-grant.ts:173-180` calls the same RPC correctly:

```ts
supabase.rpc("grant_byok_delegation", {
  p_grantor_user_id: grantorId,
  p_grantee_user_id: granteeId,
  p_workspace_id: workspaceId,
  p_daily_usd_cap_cents: args.capCents,
  p_hourly_usd_cap_cents: args.hourlyCapCents,
  p_expires_at: expiresAt,          // null = never expires (column is nullable)
  p_actor_user_id: actorId,
});
```

The route is the **sole outlier**. The fix is to align the route's named arguments to this
canonical 7-parameter contract. No migration, no schema change, no new infrastructure.

### Why it shipped broken

The POST route was added in PR #4508 (BYOK PR-B — UI surfaces) but never got a route-level test
that asserts the RPC call shape. The only delegation-route test today is
`api-delegation-withdraw-route.test.ts` (covers DELETE/withdraw, not POST). The resolver tests mock
the DB, so the named-arg mismatch was invisible to CI. `tsc` cannot catch it because supabase-js
`rpc()` accepts an untyped params object.

## Research Reconciliation — Spec vs. Codebase

| Claim (from feature description / inferred) | Reality (verified in repo) | Plan response |
| --- | --- | --- |
| Toggle UI is broken / never wired | UI is fully wired: `delegation-toggle.tsx` → `team-membership-list.tsx` → POST `/api/workspace/delegations`. This is broken *behavior*, not never-built. | Behavioral fix in the route handler, not a build. |
| The bug is a precondition ("grantor must have a key") | No grantor-key precondition exists in `grant_byok_delegation` (064) — only cap-range + cross-tenant/WORM trigger checks. The RPC is reached with a malformed param set and fails to resolve. | Fix is the RPC param-name alignment; no precondition logic involved. |
| A recent migration may have changed the RPC signature | `grant_byok_delegation` is defined exactly once (064) and never `CREATE OR REPLACE`-d again (grep across all migrations). | Align route to the 064 signature. |
| `p_expires_at` might be optional | RPC has zero DEFAULTs; all 7 params mandatory. `byok-grant.ts` passes `expiresAt` (nullable → "never"). | Pass `p_expires_at: null` from the route (delegations created via the UI never expire — matches CLI default behavior). |

## User-Brand Impact

- **If this lands broken, the user experiences:** an org owner who wants to fund a teammate's
  agent runs clicks the "Share a key" toggle and it silently does nothing — the single highest-value
  team action (paying for a keyless member so they can run tasks) is 100% non-functional with no
  error shown. The owner concludes the product is broken.
- **If this leaks, the user's data / workflow / money is exposed via:** N/A for the leak axis — this
  fix corrects a failed write, it does not widen any read/exposure surface. The corrected path still
  routes through the existing owner-only authz check (`route.ts:75-77`) and the RPC's cross-tenant +
  WORM triggers.
- **Brand-survival threshold:** `single-user incident` — a single owner hitting a dead core team
  feature on their first real attempt is a brand-survival event for a small-team product.

> CPO sign-off required at plan time before `/work` begins (`requires_cpo_signoff: true`). `user-impact-reviewer` runs at review time.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — RPC param alignment.** `route.ts` POST calls `grant_byok_delegation` with exactly the
  064 named args: `p_grantor_user_id`, `p_grantee_user_id`, `p_workspace_id`,
  `p_daily_usd_cap_cents`, `p_hourly_usd_cap_cents`, `p_expires_at`, `p_actor_user_id`. Verify:
  `grep -nE 'p_daily_cap_cents|p_hourly_cap_cents|p_created_by_user_id' apps/web-platform/app/api/workspace/delegations/route.ts` returns **zero** matches.
- [ ] **AC2 — hourly cap supplied.** Because `p_hourly_usd_cap_cents` is mandatory (no DEFAULT) and
  the 064 RPC rejects `NULL` (`ERRCODE 22003`, range `[1, daily]`), the route MUST send a non-null
  hourly cap. Default to the daily cap when the client omits `hourlyCapCents`
  (`p_hourly_usd_cap_cents: body.hourlyCapCents ?? body.dailyCapCents`). Verify via AC4 test asserting
  the value passed.
- [ ] **AC3 — expiry supplied.** Route sends `p_expires_at: null` (UI-created delegations never
  expire, matching `byok-grant.ts` "never" default).
- [ ] **AC4 — route POST test (RED→GREEN).** New test
  `apps/web-platform/test/api-delegation-grant-route.test.ts` (mirrors the
  `api-delegation-withdraw-route.test.ts` mock pattern: `mockServiceRpc`, `mockGetUser`,
  `mockValidateOrigin`, `mockIsByokDelegationsEnabled`, `mockResolveCurrentOrganizationId`).
  Asserts `mockServiceRpc` is called with the exact 7-key canonical arg object via
  `toHaveBeenCalledWith("grant_byok_delegation", { p_grantor_user_id: …, p_grantee_user_id: …,
  p_workspace_id: …, p_daily_usd_cap_cents: …, p_hourly_usd_cap_cents: …, p_expires_at: null,
  p_actor_user_id: … })`. The test MUST fail against the current route and pass after the fix.
  Covers: happy path (200 + `delegationId`), non-owner (403 `not_owner`), missing fields (400),
  flag-off (404). Runner: `cd apps/web-platform && ./node_modules/.bin/vitest run test/api-delegation-grant-route.test.ts`
  (file lives under `test/**/*.test.ts` per `vitest.config.ts:44` node-project include glob).
- [ ] **AC5 — client surfaces failures.** `delegation-toggle.tsx` `handleToggle` no longer silently
  drops a non-OK POST/DELETE response. On `!res.ok`, surface a visible error (inline message or
  `window.alert`, matching the existing `team-membership-list.tsx` remove-member pattern at line 114)
  so a future RPC/authz failure is operator-visible rather than a silent no-op. The toggle's `active`
  state is only set on success (already true; keep it).
- [ ] **AC6 — no other miscalls.** `grep -rn 'grant_byok_delegation' apps/web-platform --include=*.ts | grep -v migrations | grep -v test`
  shows only `route.ts` and `byok-grant.ts`, both using the canonical names.
- [ ] **AC7 — full suite green.** `cd apps/web-platform && <package.json test script>` passes
  (use the script in `apps/web-platform/package.json`, not a hardcoded runner; check
  `apps/web-platform/bunfig.toml` does not block discovery).

## Files to Edit

- `apps/web-platform/app/api/workspace/delegations/route.ts` — fix the POST `rpc()` call: rename
  `p_daily_cap_cents`→`p_daily_usd_cap_cents`, `p_hourly_cap_cents`→`p_hourly_usd_cap_cents`,
  `p_created_by_user_id`→`p_actor_user_id`; add `p_expires_at: null`; default hourly to daily when
  omitted. Update the `body` type to reflect the cap field names the client actually sends
  (`dailyCapCents`, `hourlyCapCents?`) — already correct; no client contract change needed.
- `apps/web-platform/components/settings/delegation-toggle.tsx` — surface non-OK fetch responses in
  `handleToggle` (AC5) instead of silently swallowing them.

## Files to Create

- `apps/web-platform/test/api-delegation-grant-route.test.ts` — POST route test (AC4).

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` checked against `route.ts` and
`delegation-toggle.tsx` — no open scope-outs touch these files.)

## Test Scenarios

1. **RED:** run the new grant-route test against the unmodified route → fails because
   `mockServiceRpc` receives `{p_daily_cap_cents, p_hourly_cap_cents, p_created_by_user_id}` not the
   canonical names (and no `p_expires_at`).
2. **GREEN:** apply the route fix → test passes; `toHaveBeenCalledWith` matches the 7-key object.
3. **Non-owner POST** → 403 `not_owner` (authz unchanged).
4. **Flag-off POST** → 404 `not_found`.
5. **Client UX:** simulate `res.ok === false` → AC5 surfaces a visible error; toggle stays off but
   the user is informed (no silent no-op).

## Domain Review

**Domains relevant:** Product, Engineering

### Engineering

**Status:** reviewed
**Assessment:** Pure bug fix in an already-provisioned API route + a client UX guard. No schema
change, no new infra, no new dependency. Risk is low and bounded to the delegation POST path; the
fix copies a contract already proven by `byok-grant.ts`. The one judgment call (hourly cap default =
daily cap) is forced by the RPC's non-null `[1, daily]` constraint and matches the toggle's
single-input UX (operator sets only a daily cap via the numeric stepper).

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A

#### Findings

Modifies behavior of an existing control (no new page/component/flow; `delegation-toggle.tsx` and
`team-membership-list.tsx` already exist). Mechanical escalation check: no new file under
`components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` (the one new file is a test). Tier
is ADVISORY; pipeline auto-accept. CPO sign-off still required at plan time per the single-user-incident
threshold (frontmatter `requires_cpo_signoff: true`).

## Observability

```yaml
liveness_signal:
  what: "grant_byok_delegation RPC success rate on POST /api/workspace/delegations (delegationId returned, HTTP 200)"
  cadence: "per owner toggle-on action"
  alert_target: "Sentry — route catch path already reports RPC errors via NextResponse 400; add explicit Sentry mirror on the error branch"
  configured_in: "apps/web-platform/app/api/workspace/delegations/route.ts (POST error branch)"
error_reporting:
  destination: "Sentry (existing web-platform integration)"
  fail_loud: true   # AC5 surfaces non-OK to the operator; server error branch mirrors RPC error.message to Sentry
failure_modes:
  - mode: "RPC param-name regression reintroduced"
    detection: "api-delegation-grant-route.test.ts toHaveBeenCalledWith assertion fails in CI"
    alert_route: "CI red on PR"
  - mode: "RPC returns error (cap out of range, cross-tenant trigger, WORM)"
    detection: "route POST returns 400 with error.message; client shows visible error (AC5)"
    alert_route: "Sentry mirror on the route error branch + operator-visible UI error"
logs:
  where: "Next.js server logs (Vercel/container stdout) + Sentry breadcrumbs on the POST route"
  retention: "per existing platform log retention"
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/api-delegation-grant-route.test.ts"
  expected_output: "test passes; mockServiceRpc called with the 7-key canonical arg object incl. p_expires_at"
```

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text,
  or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above.)
- **Hourly cap default is a design choice, not a copy from `byok-grant.ts`.** The CLI takes an
  explicit `hourlyCapCents`; the UI toggle exposes only a daily stepper. The RPC requires a non-null
  hourly cap in `[1, daily]`. Defaulting hourly = daily is the safe interpretation (hourly cap never
  more restrictive than what the owner set as daily). If a different default is desired, it must be a
  conscious decision — do not pass `null` (RPC raises `22003`).
- **Verify the route's `body` type vs. client payload.** The client (`delegation-toggle.tsx:104-109`)
  sends `{ workspaceId, granteeUserId, dailyCapCents }` (no `hourlyCapCents`). The route `body` type
  already lists `hourlyCapCents?` as optional — confirm the `?? body.dailyCapCents` fallback at the
  RPC boundary, not a non-null assertion.
- **Do not change the RPC.** Migration 064 is the source of truth and is consumed correctly by
  `byok-grant.ts`. Changing the RPC signature to match the route would break the working CLI and the
  `064-byok-delegations.test.ts` / tenant-isolation tests. Fix the caller, not the callee.
