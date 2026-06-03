---
title: "Fix Generate-link button regression (tenant-mint dead-ends share-create)"
type: fix
date: 2026-06-04
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# 🐛 Fix: "Generate link" button silently fails — tenant-mint dead-ends share-create POST

## Summary

The "Generate link" button in the Share popover (top of the document/canvas view) no
longer generates a public share link. Clicking it returns to the identical idle panel
("Generate a public link to share this document with anyone.") instead of showing the
link + Copy/Revoke UI. This is a **regression** introduced by PR #3854
(`feat(runtime): PR-C sibling-query tenant migration (#3244 §2)`, MERGED 2026-05-16).

The fix restores reliable share-link generation by making the user's-own-`workspace_path`
read in `resolveUserKbRoot` resilient to tenant-JWT-mint failure — falling back to the
service-role read that the route already uses for the actual share write.

## Root Cause (confirmed)

PR #3854 changed the `POST /api/kb/share` handler at
`apps/web-platform/app/api/kb/share/route.ts:37`:

```diff
- const workspace = await resolveUserKbRoot(serviceClient, user.id);
+ const workspace = await resolveUserKbRoot(user.id);
```

- **Before #3854**, `resolveUserKbRoot(serviceClient, userId)` read
  `users.workspace_path` via the **service-role** client (RLS-bypass, always succeeds).
- **After #3854**, `resolveUserKbRoot(userId)`
  (`apps/web-platform/server/kb-route-helpers.ts:225`) mints a **tenant-scoped** client
  internally via `getFreshTenantClient` (`apps/web-platform/lib/supabase/tenant.ts:766`
  → `mintFounderJwt`), which performs a full GoTrue `generateLink + verifyOtp` JWT mint
  gated by a per-founder rate ceiling (`precheck_jwt_mint`, 60/hr, migration 048). On any
  mint failure it throws `RuntimeAuthError`; `resolveUserKbRoot` catches it and returns
  `{ ok: false, response: NextResponse.json({ error: "Workspace not ready" }, { status: 503 }) }`
  (`kb-route-helpers.ts:242-256`).

The POST then returns 503. The client `generateLink` callback
(`apps/web-platform/components/kb/share-popover.tsx:84-86`) treats **any** non-ok
response by resetting state to `status: "idle"`, re-rendering the identical idle panel —
exactly the reported "returns to the same box" symptom.

**Asymmetry confirming a POST-only regression:** `GET /api/kb/share`
(`route.ts:56`) does **not** call `resolveUserKbRoot` — it uses `createServiceClient()`
directly — so the popover still opens and `checkShare` still works; only the POST
generate path is broken.

**Important context:** the actual privileged write (`createShare`) still uses the
**service-role** client (`route.ts:40`; comment `route.ts:34-35`: "kb_shares writer is
allowlisted PERMANENT for now — see PR-D scope"). So the tenant-scoped client introduced
by #3854 is used **only** to read the user's own `users.workspace_path` (RLS predicate
`auth.uid() = id`, `001_initial_schema.sql:17-19`) — a read the service-role client
performed fine before #3854. The tenant scoping bought no isolation benefit on this path
(the write is still service-role) while introducing a heavyweight, rate-limited,
failure-prone JWT-mint dependency into a user-facing button.

### Ruled out

- **Deterministic RLS block:** the `users` SELECT policy is `auth.uid() = id` and the
  tenant JWT sets `role='authenticated'` + `auth.uid()=userId`, so the self-SELECT is
  permitted under a *successful* mint. The failure is in the **mint**, not in RLS.
- **Field rename:** both old and new `resolveUserKbRoot` return `kbRoot`; the route reads
  `workspace.kbRoot`. No drift.

## User-Brand Impact

- **If this lands broken, the user experiences:** the Share popover's "Generate link"
  button does nothing on click (silently bounces back to the idle panel); the user cannot
  produce a public share link for any KB document.
- **If this leaks, the user's workflow is exposed via:** N/A for the read fallback — the
  fallback reads only the *requesting user's own* `workspace_path` keyed on the
  already-authenticated `user.id` (the service-role read is scoped by
  `.eq("id", userId)`), and the share-link write surface is unchanged. No new data is
  exposed; the change restores prior (pre-#3854) read behavior.
- **Brand-survival threshold:** `single-user incident` (carried forward from #3244 / PR-C;
  a single founder hitting a dead "Generate link" button is a brand-survival-class
  user-facing failure). `requires_cpo_signoff: true`.

## Research Reconciliation — Spec vs. Codebase

| Claim (feature description) | Codebase reality | Plan response |
| --- | --- | --- |
| Regression at `route.ts:37` from `resolveUserKbRoot(serviceClient, user.id)` → `resolveUserKbRoot(user.id)` | Confirmed via `git show abcb3765 -- apps/web-platform/app/api/kb/share/route.ts` (PR #3854) | Fix targets `resolveUserKbRoot` mint-failure path |
| `createShare` still uses service-role | Confirmed `route.ts:40` + comment `route.ts:34-35` | Fallback read uses the same service-role client; no new privilege |
| GET path unaffected (uses `createServiceClient` directly) | Confirmed `route.ts:56-73` | No GET change |
| Upload route has the same migrated call | Confirmed `apps/web-platform/app/api/kb/upload/route.ts:70` (`resolveUserKbRoot(user.id, {extras})`) | Same helper fix covers it; upload's `extras` (`repo_url`, `github_installation_id`) read from the same `users` row must be carried through the fallback |
| Sibling helper `authenticateAndResolveKbPath` also mints tenant | Confirmed `kb-route-helpers.ts:95` | **Out of scope** (file GET/PATCH/DELETE routes; not the reported bug) — note as a follow-up, see Non-Goals |
| Issue #3244 state | CLOSED (umbrella, "Command Center server-side agentic runtime") | Do not reopen; reference only |
| PR #3854 state | MERGED 2026-05-16 | Regression source; reference in PR body |

## Chosen Approach

**Direction B — service-role fallback on mint failure (recommended).**

Keep the tenant-scoped `users.workspace_path` read as the **primary** path (honoring the
#3244 gate-zero isolation intent), but when `getFreshTenantClient` throws
`RuntimeAuthError`, fall back to a **service-role** read of the same row
(`.from("users").select(selectCols).eq("id", userId).single()`) instead of returning 503.
The fallback is scoped to the requesting user's own id, reads the same columns, and the
route already uses service-role for the share write — so no new privilege or exposure is
introduced. A transient mint failure or a per-founder mint-ceiling trip no longer
dead-ends a user-facing button.

Rationale for B over A (full revert to service-role-only read):

- B preserves the tenant-scoped read as the default, so the #3244 isolation posture is
  retained whenever the mint succeeds (the common case).
- B is a strictly additive fallback — smaller blast radius than re-threading a
  `serviceClient` argument back through both call sites and reverting the helper signature.
- A (revert) would re-introduce the exact service-role read #3854 deliberately removed,
  with no path to ever exercising the tenant-scoped read; B keeps the migration's intent
  while closing the availability hole.

The mint-failure fallback MUST emit a `reportSilentFallback` / structured-log signal so
the operator sees that the tenant mint is failing (the underlying mint problem — e.g.
ceiling trip — is still worth surfacing even though the user flow now recovers).

`plan-review` and `deepen-plan` should adjudicate B vs A; if review prefers A, the
`## Files to Edit` set changes (revert helper signature + re-thread `serviceClient` at both
call sites) but the test strategy and observability section are unchanged in spirit.

## Files to Edit

- `apps/web-platform/server/kb-route-helpers.ts` — in `resolveUserKbRoot`, on
  `getFreshTenantClient` throwing `RuntimeAuthError`, fall back to a service-role read of
  the same `users` row (same `selectCols`, same `.eq("id", userId).single()`), apply the
  identical `workspace_path` / `workspace_status` / `extras` validation to the fallback
  result, and emit `reportSilentFallback` so the mint failure is still observable. Only the
  503-on-mint-failure branch (`:242-256`) changes; the RLS-permitted happy path and the
  `extras`-missing 400 path are unchanged.
- `apps/web-platform/test/kb-route-helpers.test.ts` — add RED→GREEN coverage:
  (1) `getFreshTenantClient` throws `RuntimeAuthError` → `resolveUserKbRoot` returns
  `{ ok: true, kbRoot }` from the service-role fallback (NOT 503);
  (2) the fallback honors `extras` (`repo_url`, `github_installation_id`) so the upload
  route's call still resolves;
  (3) fallback still returns the 503-equivalent only when the *service-role* read also
  yields no `workspace_path` / non-`ready` status;
  (4) `reportSilentFallback` is invoked on the mint-failure fallback. The existing
  `vi.mock("@/lib/supabase/tenant", …)` already exposes a mockable `getFreshTenantClient`
  and `RuntimeAuthError`, and `createServiceClient` is already mocked to `mockFrom` — reuse
  both.

## Files to Create

None.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `resolveUserKbRoot` returns `{ ok: true, kbRoot, workspacePath, extras }` (not a 503
      response) when `getFreshTenantClient` throws `RuntimeAuthError`, provided the
      service-role read of the user's own row yields a `ready` workspace — asserted by a
      new test in `kb-route-helpers.test.ts`.
- [ ] The mint-failure fallback emits exactly one `reportSilentFallback` call carrying the
      `RuntimeAuthError` (so the operator still sees the mint failure) — asserted via
      `mockReportSilentFallback`.
- [ ] The `extras` path (`repo_url`, `github_installation_id`) resolves through the
      fallback (covers the `POST /api/kb/upload` call site) — asserted by a test passing
      `{ extras: ["repo_url", "github_installation_id"] as const }`.
- [ ] When BOTH the tenant mint fails AND the service-role read yields no
      `workspace_path` / non-`ready` status, the helper still returns the 503 "Workspace
      not ready" response (no false-positive resolution) — asserted by a test.
- [ ] `GET /api/kb/share` and `createShare` are unchanged (no diff to `route.ts` GET
      handler or to `kb-share.ts`).
- [ ] `apps/web-platform` typechecks and the vitest suite for the edited file passes via
      the package runner: `cd apps/web-platform && ./node_modules/.bin/vitest run test/kb-route-helpers.test.ts`
      (package `scripts.test` is `vitest`; node-project include glob is `test/**/*.test.ts`).

### Post-merge (operator)

- [ ] After the `web-platform-release.yml` pipeline restarts the container on merge to
      main (path-filtered `on.push` over `apps/web-platform/**` — a PR merge IS the
      remediation), verify the live "Generate link" button via Playwright MCP: open a KB
      document, click Share → "Generate link", assert the popover transitions to the
      active state showing a `/shared/<token>` URL and the Copy/Revoke controls.
      `Automation: feasible via mcp__playwright__*` — runs against the authenticated app.

## Test Scenarios

- Given a user with a `ready` workspace, when `getFreshTenantClient` throws
  `RuntimeAuthError("jwt_mint")`, then `resolveUserKbRoot(userId)` returns
  `{ ok: true, kbRoot: "<workspace>/knowledge-base" }` via the service-role fallback and
  emits one `reportSilentFallback`.
- Given the same, when called with `extras: ["repo_url", "github_installation_id"]`, then
  the fallback returns those extras populated from the same row.
- Given a user whose service-role row has `workspace_status !== "ready"`, when the mint
  throws, then the helper returns the 503 "Workspace not ready" response (fallback does not
  paper over a genuinely-not-ready workspace).
- Given a successful mint (no throw), then the tenant-scoped read path is taken unchanged
  (no service-role fallback, no `reportSilentFallback`).
- **Browser (post-merge):** open KB doc → Share → "Generate link"; expect the popover to
  render the `/shared/<token>` input + Copy button (active state), not bounce to idle.

## Observability

```yaml
liveness_signal:
  what: "Sentry breadcrumb/event via reportSilentFallback on tenant-mint fallback in resolveUserKbRoot"
  cadence: "per share/upload POST when the tenant mint fails"
  alert_target: "Sentry web-platform project (operator dashboard)"
  configured_in: "apps/web-platform/server/kb-route-helpers.ts (resolveUserKbRoot mint-failure branch)"
error_reporting:
  destination: "Sentry web-platform via SENTRY_DSN, routed through server/observability.ts reportSilentFallback"
  fail_loud: "POST /api/kb/share now succeeds (200/201) on mint failure; the Sentry event records that the tenant mint failed even though the user flow recovered"
failure_modes:
  - mode: "tenant JWT mint failing on every share/upload POST (ceiling trip or GoTrue outage)"
    detection: "reportSilentFallback events accumulating with feature=kb-route-helpers op=resolveUserKbRoot.tenant-mint"
    alert_route: "Sentry issue to operator"
  - mode: "service-role fallback ALSO failing (user genuinely not ready)"
    detection: "POST returns 503 'Workspace not ready'; client stays idle (pre-fix behavior preserved for the genuinely-not-ready case)"
    alert_route: "Sentry (existing resolveUserKbRoot.tenant-mint reportSilentFallback) + user sees no link"
logs:
  where: "pino structured logs (server/logger.ts child loggers) + Sentry; container stdout via docker logs on the web-platform host"
  retention: "Sentry default project retention; container logs ephemeral per deploy"
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/kb-route-helpers.test.ts"
  expected_output: "all tests pass, including the new mint-failure-fallback cases (no ssh required)"
```

## Domain Review

**Domains relevant:** Product (UI surface), Engineering (auth/runtime)

### Engineering

**Status:** reviewed (plan-author assessment; CTO carry-forward from #3244 PR-C lives in
the original brainstorm/spec for that umbrella)
**Assessment:** The change is a localized availability fix on an auth-adjacent read path.
It does NOT relax a security boundary: the share *write* remains service-role (unchanged),
the fallback read is scoped to the authenticated user's own id, and the tenant-scoped read
stays the default. The mint-failure path is the only branch modified. CTO probe (mirroring
a sibling-layer predicate): this is not a new recovery primitive duplicating a SQL/scheduler
predicate — it is a fallback within a single read helper, so the
"name-the-load-bearing-sub-value" gate does not apply. No infra surface.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (no NEW user-facing surface; the fix restores an EXISTING
button's behavior — no new pages/components/flows, no copy change). The mechanical
UI-surface override does not fire: `## Files to Edit` contains no `components/**`,
`app/**/page.tsx`, or `app/**/layout.tsx` path (the only UI file, `share-popover.tsx`, is
referenced for diagnosis but is NOT edited — the bug is server-side).
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface created or modified)

#### Findings

Restores prior behavior of an existing control; no design or copy decisions required.

## Open Code-Review Overlap

1 open code-review scope-out touches an edited file:

- **#2246** (`refactor(kb): low-severity polish from PR #2235 review`) names
  `kb-route-helpers.ts` (P3: helper return type is `Response` not `NextResponse`; callers
  can't add cookies/headers without casting). **Disposition: Acknowledge.** Different
  concern — this plan only modifies the mint-failure branch of `resolveUserKbRoot` to add a
  service-role fallback; it does not touch the helper's return-type union. The P3 polish
  remains open and is not coupled to the availability fix. Folding it in would broaden the
  diff beyond the regression and risk the `single-user incident` brand-survival scope.

## GDPR / Compliance Gate (advisory)

The fix touches an auth-adjacent API-route read path (canonical regex fires on
`apps/*/app/api/**` + auth-flow), so this gate is recorded rather than skipped. **No
Critical findings.** The service-role fallback reads only the *requesting user's own*
`users` row (`.eq("id", userId)`, columns `workspace_path, workspace_status[, repo_url,
github_installation_id]`) — no new personal-data field, no new processing activity, no
LLM/external-API data movement, and no new distribution surface. The change *reduces* the
broken-state footprint (it restores a previously-working read) rather than expanding data
movement. No new lawful-basis question, no Art. 9 special-category data, no Art. 30 register
entry required. Advisory-only; mandatory disclaimer: this is not legal advice.

## Risks & Mitigations

- **Fallback masks a persistent mint outage.** Mitigated: the fallback emits
  `reportSilentFallback`, so a chronically-failing mint is still visible to the operator in
  Sentry even though users recover. The fallback restores *availability*, not silence.
- **Fallback over-resolves a genuinely-not-ready workspace.** Mitigated: the fallback
  applies the *same* `workspace_path` + `workspace_status === "ready"` + `extras`
  validation to the service-role read; a non-ready user still gets the 503.
- **Precedent check (deepen-plan Phase 4.4):** the service-role read shape already exists
  in this very helper's pre-#3854 form (`git show abcb3765~1:apps/web-platform/server/kb-route-helpers.ts`)
  and in `createServiceClient()` consumers; no novel pattern. deepen-plan should diff the
  fallback read against the pre-#3854 service-role read to confirm column parity
  (`workspace_path, workspace_status[, extras…]`).
- **supabase-js query-shape:** the fallback uses
  `.from("users").select(selectCols).eq("id", userId).single<Record<string, unknown>>()` —
  identical to the existing tenant read in the same function; confirm against the installed
  supabase-js before implementing (it is a copy of the adjacent call, so risk is minimal).

## Non-Goals

- **Not fixing `authenticateAndResolveKbPath`** (the sibling helper at
  `kb-route-helpers.ts:95` used by `/api/kb/file/*` GET/PATCH/DELETE), which also mints a
  tenant client and would 503 the same way on mint failure. The reported bug is share-create
  only. **Deferral:** file a follow-up issue to apply the same mint-failure resilience to
  `authenticateAndResolveKbPath` (or to lift the fallback into a shared sub-helper both
  call), with re-evaluation criterion "next time a KB file route 503s on mint failure," and
  milestone from `knowledge-base/product/roadmap.md`. Do NOT silently leave it
  unaddressed — a deferral without a tracking issue is invisible.
- **Not changing the client `share-popover.tsx`** error handling (it correctly falls back
  to idle on non-ok; the fix is to stop the server returning non-ok on transient mint
  failure). A separate UX improvement — surfacing an error toast on genuine 503 — is out of
  scope.
- **Not touching the tenant-mint internals** (`mintFounderJwt`, the 60/hr ceiling). The
  ceiling is a deliberate auth-domain control; this plan only stops it from dead-ending a
  read that has a safe service-role fallback.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/
  placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's
  section is filled with a `single-user incident` threshold.)
- When verifying the fix, exercise the **POST** path specifically — the GET path was never
  broken, so a popover that "opens fine" is not evidence the fix works. The active-state
  transition (link URL + Copy/Revoke) after clicking "Generate link" is the load-bearing
  assertion.
- Test FILE PATH must satisfy the vitest node-project include glob
  (`test/**/*.test.ts`); `kb-route-helpers.test.ts` already lives under `test/` so it is
  collected — do not co-locate the new cases next to the helper.
- The fallback must carry `extras` through, or the upload route (`extras: ["repo_url",
  "github_installation_id"]`) regresses to "No repository connected" 400 on mint failure.
  Test the `extras` path explicitly.

## References

- Regression source: PR #3854 (`feat(runtime): PR-C sibling-query tenant migration (#3244 §2)`), MERGED 2026-05-16.
- Umbrella: #3244 (CLOSED).
- `apps/web-platform/app/api/kb/share/route.ts:37` (regression locus), `:40` (service-role write), `:56` (GET, unaffected).
- `apps/web-platform/server/kb-route-helpers.ts:225` (`resolveUserKbRoot`), `:242-256` (mint-failure 503 branch).
- `apps/web-platform/lib/supabase/tenant.ts:766` (`getFreshTenantClient`), `mintFounderJwt` + `RuntimeAuthError`.
- `apps/web-platform/components/kb/share-popover.tsx:76-99` (client `generateLink`; resets to idle on non-ok).
- `apps/web-platform/test/kb-route-helpers.test.ts` (existing mock harness reused for the new cases).
- Premise-validation scratch: `/tmp/plan-scratch/premise-validation.md`.
