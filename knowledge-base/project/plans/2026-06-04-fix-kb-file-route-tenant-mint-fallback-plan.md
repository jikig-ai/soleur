---
title: "fix(kb): per-cause tenant-mint fallback for authenticateAndResolveKbPath (file routes)"
type: fix
issue: 4914
branch: feat-one-shot-4914-kb-tenant-mint-fallback
date: 2026-06-04
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: planned
---

# fix(kb): per-cause tenant-mint fallback for `authenticateAndResolveKbPath` 🐛

## Enhancement Summary

**Deepened on:** 2026-06-04
**Sections enhanced:** Overview, FRs, Risks, Test Scenarios (Research Insights added)
**Deepen passes run:** Phase 4.4 precedent-diff, Phase 4.45 verify-the-negative + post-edit self-audit, Phase 4.6/4.7/4.8/4.9 halt gates (all PASS), framework-docs verification of `RuntimeAuthError` semantics against installed source.

### Key Improvements

1. **Branch shape pinned to fail-CLOSED-on-unknown-cause.** Verified the `RuntimeAuthError.cause` union has a `: never` exhaustiveness rail at `tenant.ts:131` (`mapRuntimeAuthCauseToErrorCode`). FR1/FR2 are pinned to the `if (cause === "jwt_mint" || cause === "rotation") { fallback } else { 403 }` shape so a hypothetical future 4th cause fails CLOSED on a mutation route (safe default), NOT open. This is the load-bearing precedent-DIVERGENCE from `resolveUserKbRoot`'s all-causes shape.
2. **Re-throw → uncontrolled-500 hazard confirmed and gated.** Read both route handlers (`route.ts:22` DELETE, `route.ts:135` PATCH): the helper is called OUTSIDE the `try` block in both. A thrown `RuntimeAuthError` on `denied_jti` would escape to Next.js → 500. FR2/AC3/Test 4 mandate a returned `err(403, …)`, never a throw.
3. **Zero-infra-change verified.** `createServiceClient` is already imported (`kb-route-helpers.ts:4`); `kb-route-helpers.ts` is already on `.service-role-allowlist` (count == 1, PR #4913). No new import, no new allowlist path line, no migration, no infra.

### New Considerations Discovered

- The `denied_jti` 403 must fire `reportSilentFallback` BEFORE returning (FR3/AC4) — a revocation-hit on a mutation route is operationally interesting (a revoked founder retrying), so it must stay Sentry-visible, not silently dropped on the early-return.
- `rotation`'s 60/hr ceiling "won't clear in seconds, no retry" (`tenant.ts:169`) — confirms a client-retry alternative is wrong; server-side fallback is the only correct fix for that cause.

## Overview

`authenticateAndResolveKbPath` (`apps/web-platform/server/kb-route-helpers.ts:65-202`) mints a
tenant-scoped JWT (`getFreshTenantClient(user.id)`) just to read the caller's **own** `users` row,
and returns **503 "Workspace not ready"** when the mint throws `RuntimeAuthError`
(`:104-110`). This is the same regression class fixed for `resolveUserKbRoot` in **PR #4913** (the
"Generate link" dead-end). A transient mint failure (`jwt_mint`) or a per-founder mint-ceiling trip
(`rotation`) dead-ends the KB **file mutation** routes — `PATCH/DELETE /api/kb/file/[...path]` — the
same way the share POST was dead-ended.

PR #4913 deliberately scoped `authenticateAndResolveKbPath` **out** as a Non-Goal and left a NOTE
comment (`:94-99`) because this helper serves **mutation** routes (PATCH = rename, DELETE = delete),
where the `denied_jti` `RuntimeAuthError` cause is a *deliberate token revocation*. Blindly copying
the all-causes fallback PR #4913 applied to the read/share path would let a revoked tenant fall
through to a service-role read and proceed to mutate — defeating the revocation's intent.

**This fix applies a *per-cause* fallback** (the adjudication the issue and the PR #4913 learning
both demand):

- **`jwt_mint` | `rotation`** (availability failures — signing/RPC failure, or the 60/hr per-founder
  ceiling tripped): fall back to a **service-role read of the caller's own row**, exactly as
  `resolveUserKbRoot` does. The mutation then proceeds — these causes are transient infrastructure
  failures, not authorization signals.
- **`denied_jti`** (the cached JWT's jti landed in `public.denied_jti` — a deliberate revocation):
  **fail closed**. Do NOT fall back. Return a clean `403 "Access denied"` response so the mutation is
  blocked, honoring the revocation.

This is a single-file behavioral change to one helper (~15 LOC + the err-helper) plus a new test
block. `kb-route-helpers.ts` is **already on the service-role allowlist** (re-introduced by PR #4913
for `resolveUserKbRoot`'s fallback — see `.service-role-allowlist` "#4913" section), and
`createServiceClient` is **already imported** at `kb-route-helpers.ts:4`. **No allowlist edit and no
new import is required.**

### Why per-cause here but all-causes for `resolveUserKbRoot`

The asymmetry is load-bearing and is the entire point of the issue (per
`knowledge-base/project/learnings/2026-05-05-defense-relaxation-must-name-new-ceiling.md`):

| | `resolveUserKbRoot` (PR #4913) | `authenticateAndResolveKbPath` (this fix) |
|---|---|---|
| Routes served | share POST (read self-row), upload | file **PATCH/DELETE** (mutation) |
| Privileged write on the path | `createShare` — **service-role at the route** (`app/api/kb/share/route.ts:36,40`); never tenant-scoped | the GitHub mutation (`githubApiPost`/`githubApiDelete`) + `syncWorkspace`, gated on this helper resolving |
| Does the deny-list gate a privileged action here? | **No** — `denied_jti` only ever blocked a self-read; the write was already service-role | **Yes** — `denied_jti` is meant to block the *mutation* |
| Correct `denied_jti` behavior | fall back (read-only, self-scoped — see PR #4913 ceiling) | **fail closed (403)** — honor the revocation |

For `jwt_mint`/`rotation` the *same* ceiling that makes PR #4913 safe applies verbatim: the fallback
read is hard-scoped `.eq("id", user.id)` where `user.id` comes from `supabase.auth.getUser()`
(server-derived, never request-controlled), so even under fallback the read touches only the caller's
OWN row. The availability fallback does not weaken cross-tenant isolation — it only restores
availability when the tenant-JWT *minting infrastructure* (not the authorization decision) is down.

## Premise Validation

Checked the four cited references; all held, none stale:

- **PR #4913** — `gh pr view 4913` → `MERGED 2026-06-03`; on `origin/main` as `7c868015`. The NOTE
  comment `// … tracked in #4914.` is live at `kb-route-helpers.ts:99` on main. Premise (this is the
  scoped-out sibling) confirmed.
- **`kb-route-helpers.ts:95` / `:96-104`** — confirmed: `getFreshTenantClient(user.id)` at `:102`,
  `RuntimeAuthError` catch returning `err(503, "Workspace not ready")` at `:104-110` (issue's
  line numbers are off-by-a-few post-#4913 but the code is exactly as described). `Read` verified.
- **`RuntimeAuthError.cause`** — `apps/web-platform/lib/supabase/tenant.ts:91` declares
  `public readonly cause: "jwt_mint" | "rotation" | "denied_jti"`. The discriminant is a clean
  3-member string union, so the per-cause branch is a simple `if (mintErr.cause === "denied_jti")`.
  `mapRuntimeAuthCauseToErrorCode` (`tenant.ts:121`) confirms the same union. **No widening risk** —
  the union is the source of truth and TS will break if a 4th cause is added (the `: never` rail at
  `tenant.ts:131`).
- **Route try-boundary** — both `DELETE` (`route.ts:22`) and `PATCH` (`route.ts:135`) call
  `authenticateAndResolveKbPath` **outside** their `try` blocks (the `try` starts at `:27` / after
  the JSON parse). So a *thrown* `RuntimeAuthError` would escape to Next.js's framework error
  boundary → an uncontrolled 500. **Therefore the `denied_jti` fail-closed path MUST return a clean
  `{ ok: false, response: err(403, …) }`, NOT re-throw.** This is the single most important
  implementation detail and is reflected in FR2 below.

## Research Reconciliation — Spec vs. Codebase

| Issue/PR claim | Codebase reality | Plan response |
|---|---|---|
| "fall back to service-role read … OR lift into a shared sub-helper both call" | The two helpers differ structurally: `authenticateAndResolveKbPath` does CSRF + auth + path-validation + installation-id fallback + symlink check inline and returns a rich `KbRouteContext`; `resolveUserKbRoot` is the simpler body-path building block. The shared portion is only the ~8-line mint+catch+read. | **Do NOT extract a shared sub-helper.** A shared helper would have to carry the per-cause *policy* (all-causes vs deny-on-`denied_jti`) as a parameter, re-introducing the coupling the two call sites deliberately keep separate. Inline the per-cause branch in `authenticateAndResolveKbPath`, mirroring `resolveUserKbRoot`'s inline shape. DHH/simplicity-aligned: ~15 LOC inline beats a parameterized policy helper. (If plan-review disagrees, the fold-in is trivial — but default to inline.) |
| Issue says line `:95-104` | Post-#4913 the block is `:100-113` (NOTE comment added 6 lines). | Cosmetic; FRs reference the *code shape*, not line numbers. |
| "service-role fallback … more aggressive than read-only share-link generation" | Correct. The mutation routes' privileged action (GitHub write + `syncWorkspace`) IS gated on this helper. | Per-cause split: availability causes fall back, `denied_jti` fails closed. |

## User-Brand Impact

**If this lands broken, the user experiences:** a founder editing or deleting a KB file (rename via
PATCH, delete via DELETE in the dashboard file viewer) gets a silent **503 "Workspace not ready"**
during a transient tenant-JWT mint blip or after tripping the 60/hr mint ceiling — the file
operation appears to fail for no visible reason, even though their workspace is perfectly ready. This
is the identical brand-survival dead-end PR #4913 fixed for the share button, on the mutation routes.

**If this leaks, the user's workflow is exposed via:** N/A for the `jwt_mint`/`rotation` fallback —
the service-role read is hard-scoped `.eq("id", user.id)` where `user.id` is the already-authenticated
session user (`supabase.auth.getUser()`), so even under fallback a caller reads only its OWN
`workspace_path`/`repo_url`/`github_installation_id` — never another tenant's. The privileged
mutation downstream still requires the resolved installation-id to belong to that same row. The
`denied_jti` path is the *opposite* of a leak: it **tightens** behavior (a revoked token is now
blocked with 403 instead of silently 503'd, but it never falls back to service-role on revocation).

**Brand-survival threshold:** `single-user incident` — a single founder hitting a dead rename/delete
button is a brand-survival-class user-facing failure, identical to the #4913 share-button class.

> **CPO sign-off required at plan time before `/work` begins.** Threshold is `single-user incident`.
> CPO domain leader (Product/UX gate below) reviews the *availability-restore vs revocation-honor*
> trade-off. `user-impact-reviewer` will be invoked at review-time (handled by the review skill's
> conditional-agent block). Recommend ultrathink/`deepen-plan` (already invoked by this pipeline) so
> the security-sentinel + data-integrity-guardian lens lands on the per-cause adjudication — per the
> learning that plan-review (DHH/Kieran/simplicity) is structurally blind to security-primitive
> findings at this threshold.

## Functional Requirements

**FR1 — Availability fallback (`jwt_mint` | `rotation`).** In the `catch (mintErr instanceof
RuntimeAuthError)` branch at `kb-route-helpers.ts:104`, branch on **the named availability causes
explicitly** — `if (mintErr.cause === "jwt_mint" || mintErr.cause === "rotation")` — and in that arm
reassign `tenant = createServiceClient()` and let the existing `.from("users").select(...)
.eq("id", user.id).single()` read + the existing `workspace_status === "ready"` / installation-id /
repo validation run unchanged against the service-role client. **Branch on the allow-list of
availability causes, NOT `cause !== "denied_jti"`** — the negated form falls OPEN for any future 4th
cause, which on a mutation route is the unsafe default. The positive allow-list form makes FR2 the
`else` arm, so an unknown cause fails closed (403). Implementation location:
`kb-route-helpers.ts:104-113` (the existing catch branch, edited).

**FR2 — Revocation (and any unknown cause) fail-closed.** The `else` arm of FR1's branch (i.e.
`denied_jti` today, plus any future un-named cause): do **NOT** fall back. Return
`err(403, "Access denied")` (the helper's existing `err()` factory at `:196`, reused — same
403/"Access denied" shape the symlink guard already returns at `:163`). This MUST be a returned
`{ ok: false, response }` — **never a re-throw** — because both route handlers call this helper
outside their try block (`route.ts:22` DELETE, `route.ts:135` PATCH; verified — a throw escapes to
Next.js → uncontrolled 500). Implementation location: `kb-route-helpers.ts:104` catch branch, the
`else` arm after the availability-causes `if`.

**FR3 — Observability preserved for ALL causes.** `reportSilentFallback(mintErr, { feature:
"kb-route-helpers", op: "authenticateAndResolveKbPath.tenant-mint", extra: { userId: user.id } })`
MUST still fire on every `RuntimeAuthError` — including `denied_jti` — so a chronically-failing mint
(ceiling trip / GoTrue outage) AND a revocation-hit both stay visible to the operator in Sentry. The
existing call at `:105-109` already does this; keep it firing *before* the per-cause branch so it is
not skipped on the `denied_jti` return. (`cq-silent-fallback-must-mirror-to-sentry`.)

**FR4 — Non-`RuntimeAuthError` still re-thrown.** The existing `throw mintErr` at `:112` for a
non-`RuntimeAuthError` mint failure is unchanged — an unexpected (non-auth) error must not be
swallowed by the fallback.

**FR5 — NOTE comment updated.** Replace the `:94-99` NOTE comment (which says this helper
"intentionally 503s … tracked in #4914") with a comment naming the **new ceiling** explicitly per
`2026-05-05-defense-relaxation-must-name-new-ceiling.md`: which causes fall back, which fails closed,
and *why* (the deny-list gates the mutation here, unlike the share path). Mirror the prose style of
`resolveUserKbRoot`'s ceiling comment (`:251-263`).

**FR6 — `.service-role-allowlist` rationale updated (comment-only).** `kb-route-helpers.ts` is
already on the allowlist (PR #4913). Extend the "#4913" rationale block in
`apps/web-platform/.service-role-allowlist` with a sentence noting that
`authenticateAndResolveKbPath` now *also* uses the service-role client as an availability fallback
(for `jwt_mint`/`rotation` only) per #4914, and that `denied_jti` fails closed. **No new path line**
— the file is already allowlisted; this is a documentation update to keep the rationale honest.
(CODEOWNERS pins this file; a comment-only edit does not add a path, so it does not require the
`@jeanderuelle` path-add approval — but flag for reviewer awareness.)

## Non-Goals

- **No shared sub-helper extraction** (see Research Reconciliation). Default to inline; fold in only
  if plan-review explicitly prefers it.
- **No change to `resolveUserKbRoot`** — PR #4913's all-causes fallback there is correct and stays.
- **No change to the GET file route** — GET uses service-role directly and was never affected (same
  as the #4913 analysis).
- **No new client-facing UX copy** — the 403 reuses the existing "Access denied" message; the file
  viewer already surfaces 4xx/5xx as a generic failure. (A per-cause "your session was revoked" toast
  is out of scope; `mapRuntimeAuthCauseToErrorCode` exists for a future UX pass — not this fix.)

## Files to Edit

- `apps/web-platform/server/kb-route-helpers.ts` — FR1–FR5: per-cause branch in the
  `authenticateAndResolveKbPath` mint-failure catch (`:104-113`) + NOTE comment rewrite (`:94-99`).
- `apps/web-platform/test/kb-route-helpers.test.ts` — new test block (see Test Scenarios); extend the
  `authenticateAndResolveKbPath` describe or add a sibling `authenticateAndResolveKbPath — tenant-mint
  fallback` describe mirroring the `resolveUserKbRoot — tenant-mint fallback` block at `:748-870`.
- `apps/web-platform/.service-role-allowlist` — FR6: comment-only rationale extension under the
  "#4913" section.

## Files to Create

- None. (Learning capture happens at ship time via `/soleur:compound` into
  `knowledge-base/project/learnings/bug-fixes/`; do not pre-create with a hardcoded dated filename.)

## Test Scenarios

New test block mirroring `resolveUserKbRoot — tenant-mint fallback` (`:748-870`). The scaffolding
already exists: `mockServiceFrom` (distinct service-role `.from`), `setupServiceUserData()`,
`setupHappyPath()`, and the two-arg mock `RuntimeAuthError(cause, message)` with a public `cause`
field (`:52-62`). Use `setupServiceUserData()` in `beforeEach` so the fallback has a ready row, and
the distinct `mockServiceFrom`/`mockFrom` assertions to keep every fallback assertion **non-vacuous**
(prove the SERVICE-ROLE client — not the thrown tenant client — produced the row).

1. **`jwt_mint` → service-role fallback resolves OK (NOT 503).** Mint rejects with
   `RuntimeAuthError("jwt_mint", …)`; `setupHappyPath()` + `setupServiceUserData()`.
   Assert `result.ok === true`, populated `ctx`, `mockServiceFrom` called with `"users"`,
   `mockFrom` (tenant) **not** called. *(RED against pre-fix code — currently 503.)*
2. **`rotation` (ceiling trip) → service-role fallback resolves OK (NOT 503).** Same as (1) with
   `cause: "rotation"`. *(RED.)*
3. **`denied_jti` → fail closed with 403, NO fallback read.** Mint rejects with
   `RuntimeAuthError("denied_jti", …)`. Assert `result.ok === false`, `result.response.status === 403`,
   body error matches `/access denied/i`, **`mockServiceFrom` NOT called** (no fallback read happened),
   `mockFrom` NOT called. *(RED — currently 503, not 403, and would silently 503 rather than block.)*
4. **`denied_jti` does NOT re-throw (returns a Response).** Assert the call **resolves** (does not
   reject) — `await expect(authenticateAndResolveKbPath(...)).resolves.toMatchObject({ ok: false })`.
   This is the load-bearing guard against the uncontrolled-500 escape (Premise Validation). *(RED.)*
5. **All three causes emit exactly one `reportSilentFallback` carrying the `RuntimeAuthError`** (FR3).
   Parametrize over `["jwt_mint", "rotation", "denied_jti"]`; assert
   `mockReportSilentFallback` called exactly once with `{ feature: "kb-route-helpers", op:
   "authenticateAndResolveKbPath.tenant-mint", extra: { userId: TEST_USER_ID } }`. Critically asserts
   the `denied_jti` arm still mirrors to Sentry *before* returning 403.
6. **Fallback still 503s when the SERVICE-ROLE read yields a not-ready workspace** (no false-positive
   resolution). `jwt_mint` mint failure + `setupServiceUserData({ workspace_status: "provisioning" })`.
   Assert 503 derives from the *service* read (`mockServiceFrom` called; result 503).
7. **A non-`RuntimeAuthError` mint failure is re-thrown** (FR4). Mint rejects with `new Error("boom")`;
   `await expect(...).rejects.toThrow("boom")`; `mockServiceFrom` NOT called.
8. **Happy path unchanged: mint succeeds → tenant read, no fallback, no `reportSilentFallback`**
   (regression guard for FR1 not firing on success).

**Runner:** `apps/web-platform` uses **vitest** (not bun test — `apps/web-platform/bunfig.toml`
ignores `**`). Run from inside the app dir:
`cd apps/web-platform && ./node_modules/.bin/vitest run test/kb-route-helpers.test.ts`.
Test path `test/kb-route-helpers.test.ts` matches the node `test/**/*.test.ts` include glob
(`apps/web-platform/vitest.config.ts`) — confirmed by the existing file living there. RED-verify the
4 new-behavior cases (1,2,3,4) fail against pre-fix code before implementing (`cq-write-failing-tests-before`).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (FR1):** `jwt_mint` and `rotation` mint failures resolve via the service-role fallback —
  `authenticateAndResolveKbPath` returns `{ ok: true, ctx }`, NOT 503. Verified by Test 1 + 2 green
  (and RED against pre-fix `kb-route-helpers.ts`).
- [ ] **AC2 (FR2):** `denied_jti` returns `{ ok: false, response }` with `response.status === 403` and
  body `{ error: "Access denied" }`; `mockServiceFrom` is **not** called (no service-role fallback on
  revocation). Verified by Test 3 green.
- [ ] **AC3 (FR2, fail-closed shape):** the `denied_jti` path **resolves to a Response object, never
  rejects** — `.resolves.toMatchObject({ ok: false })`. Verified by Test 4 green. (Guards the
  out-of-try-block uncontrolled-500 escape.)
- [ ] **AC4 (FR3):** `reportSilentFallback` fires exactly once for each of all three causes with
  `op: "authenticateAndResolveKbPath.tenant-mint"` and `extra: { userId }`. Verified by Test 5 green.
- [ ] **AC5 (FR1, no false-positive):** a service-role read returning a not-ready workspace still
  503s under fallback. Verified by Test 6 green.
- [ ] **AC6 (FR4):** a non-`RuntimeAuthError` mint failure is re-thrown unchanged. Verified by Test 7.
- [ ] **AC7 (FR5):** the NOTE comment at `kb-route-helpers.ts` no longer says "intentionally 503s …
  tracked in #4914"; it names the per-cause ceiling (`jwt_mint`/`rotation` fall back; `denied_jti`
  fails closed) and the rationale. Verified by `grep -n "denied_jti" apps/web-platform/server/kb-route-helpers.ts`
  returning a match inside the `authenticateAndResolveKbPath` comment block + manual read.
- [ ] **AC8 (FR6):** `apps/web-platform/.service-role-allowlist` "#4913" block mentions
  `authenticateAndResolveKbPath`'s availability-only fallback (#4914). No new path line added (the
  file is already allowlisted). Verified by `grep -c "apps/web-platform/server/kb-route-helpers.ts"
  apps/web-platform/.service-role-allowlist` returning exactly `1` (unchanged count).
- [ ] **AC9 (gate):** the `service-role-allowlist-gate` CI job stays green — no new disallowed
  service-role importer (the file is already allowlisted; no new `createServiceClient` *file* added).
- [ ] **AC10:** `apps/web-platform` typechecks (`cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`)
  and the `kb-route-helpers.test.ts` vitest file is fully green.

### Post-merge (operator)

- None. This is a pure code change against an already-provisioned surface; no migration, no infra, no
  external-service config. The fix deploys via the standard `web-platform-release.yml` pipeline on
  merge to main (path-filtered `apps/web-platform/**`).

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO — Product/UX Gate, single-user-incident threshold)

### Engineering (CTO)

**Status:** reviewed (plan-author assessment; deepen-plan will spawn data-integrity-guardian +
security-sentinel + architecture-strategist for the per-cause adjudication)
**Assessment:** Single-file behavioral change mirroring an established, security-reviewed sibling
pattern (PR #4913). The novel surface is the per-cause split on `RuntimeAuthError.cause`. Two
load-bearing facts make it safe: (1) the `cause` union is the source of truth with a `: never`
exhaustiveness rail (`tenant.ts:131`), so the branch cannot silently miss a future cause; (2) the
fail-closed path MUST return a Response (not throw) because the call sites are outside their try
blocks — encoded as FR2 + AC3. No SQL, no schema, no migration. Defense-relaxation discipline applied
(FR5 names the new ceiling per `2026-05-05-defense-relaxation-must-name-new-ceiling.md`).

### Product/UX Gate

**Tier:** none (no UI-surface file touched — `## Files to Edit`/`## Files to Create` contain only
`server/*.ts`, `test/*.ts`, and `.service-role-allowlist`; the mechanical UI-surface override does
not fire). Product domain is flagged relevant only for the **CPO sign-off** required by the
`single-user incident` threshold (User-Brand Impact, FR-policy adjudication), not for a wireframe.
**Decision:** auto-accepted (pipeline) for the UX-producer steps (no UI surface → no `.pen`). CPO
sign-off on the availability-vs-revocation trade-off is requested at plan time per the threshold.
**Agents invoked:** none (no UI surface; spec-flow/ux-design-lead/copywriter not applicable — no
user flow, no page, no copy beyond the reused "Access denied" string).
**Skipped specialists:** none — `ux-design-lead` is N/A (no UI surface).
**Pencil available:** N/A (no UI surface).

#### Findings

No new user-facing surface. The only user-observable behavioral deltas: (a) rename/delete now
*succeed* during a transient mint blip instead of failing with 503 (strict improvement), and (b) a
deny-listed/revoked session now gets a 403 instead of a silent 503 on a mutation route (correct
tightening — the revocation is now honored). Both are positive or neutral for the founder; neither
introduces a new screen, flow, or copy.

## Observability

```yaml
liveness_signal:
  what: Sentry events tagged op:"authenticateAndResolveKbPath.tenant-mint" (existing reportSilentFallback)
  cadence: per mint-failure occurrence (event-driven, no fixed cadence)
  alert_target: Sentry issue grouping on feature:"kb-route-helpers" + op:"authenticateAndResolveKbPath.tenant-mint"
  configured_in: apps/web-platform/server/kb-route-helpers.ts (reportSilentFallback call, FR3) + Sentry project rules
error_reporting:
  destination: Sentry (via reportSilentFallback → server/observability.ts)
  fail_loud: true — fires for ALL three causes including the denied_jti fail-closed path (FR3); a chronically failing mint OR a revocation-hit both surface
failure_modes:
  - mode: tenant-JWT mint availability failure (jwt_mint signing/RPC, or rotation 60/hr ceiling)
    detection: Sentry event op:authenticateAndResolveKbPath.tenant-mint with RuntimeAuthError.cause in {jwt_mint, rotation}; user-invisible (mutation now succeeds via fallback)
    alert_route: Sentry — a SPIKE indicates a GoTrue outage or a founder repeatedly tripping the mint ceiling
  - mode: deliberate token revocation hit on a mutation route (denied_jti)
    detection: Sentry event op:authenticateAndResolveKbPath.tenant-mint with cause denied_jti + the caller receiving 403; expected/intended when a jti is on the deny-list
    alert_route: Sentry — a denied_jti hit is informational (the revocation is working); a SPIKE could indicate a revoked founder repeatedly retrying
  - mode: service-role read returns not-ready workspace under fallback
    detection: 503 returned to caller after a successful fallback read (FR1/AC5); same as the non-fallback not-ready 503
    alert_route: existing 503 client handling; no new alert
logs:
  where: Sentry (structured event); no new pino log line added (reportSilentFallback already routes to Sentry + structured logger per server/observability.ts)
  retention: Sentry project default retention
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/kb-route-helpers.test.ts -t 'tenant-mint' (asserts reportSilentFallback fires for all 3 causes — Test 5)"
  expected_output: vitest reports the 'reportSilentFallback fires exactly once for each cause' test green, proving the Sentry-mirror path is exercised for jwt_mint, rotation, AND denied_jti
```

## Risks & Mitigations

### Precedent-Diff (Phase 4.4) — vs `resolveUserKbRoot` (PR #4913)

`git grep` precedent: the canonical mint-failure catch shape lives in the SAME file at
`kb-route-helpers.ts:264-278` (`resolveUserKbRoot`). Side-by-side:

```
resolveUserKbRoot (PR #4913, ALL causes)        authenticateAndResolveKbPath (this fix, PER-cause)
------------------------------------------       --------------------------------------------------
catch (mintErr) {                                catch (mintErr) {
  if (mintErr instanceof RuntimeAuthError) {       if (mintErr instanceof RuntimeAuthError) {
    reportSilentFallback(mintErr, {...});            reportSilentFallback(mintErr, {...});   // FR3: ALL causes
    tenant = createServiceClient();    // ALL        if (mintErr.cause === "jwt_mint" ||
  } else {                                               mintErr.cause === "rotation") {
    throw mintErr;                                       tenant = createServiceClient();    // FR1
  }                                                  } else {
}                                                      return err(403, "Access denied");  // FR2 (denied_jti + unknown)
                                                     }
                                                   } else {
                                                     throw mintErr;                       // FR4
                                                   }
                                                 }
```

The divergence (per-cause `else`-403 vs all-causes fallback) is intentional and is the entire point
of #4914: `resolveUserKbRoot`'s downstream write was already service-role (deny-list gated nothing),
whereas this helper's downstream GitHub mutation IS gated on it resolving. **Not novel** — the catch
skeleton is copied verbatim from the precedent; only the cause-branch is added.

### Risk register

- **Risk: future 4th `RuntimeAuthError.cause` falls OPEN (silently falls back on a mutation route).**
  *Mitigation:* FR1 branches on the **positive allow-list** `cause === "jwt_mint" || cause ===
  "rotation"`, so the `else` (FR2) catches `denied_jti` AND any future cause → 403 (fail-closed).
  Verified the `cause` union has a `: never` exhaustiveness rail at `tenant.ts:120-134`
  (`mapRuntimeAuthCauseToErrorCode`) — a 4th cause is a TS build break there, a compile-time signal to
  revisit this branch. (The branch itself does not need the rail; the allow-list form is safe
  regardless.)
- **Risk: re-throw on `denied_jti` escapes to an uncontrolled 500.** *Mitigation:* FR2 + AC3 mandate a
  returned `err(403, …)`, never a throw; Test 4 asserts `.resolves`. The call sites are outside their
  try blocks (Premise Validation), so this is load-bearing.
- **Risk: vacuous fallback test (tenant + service client wired to the same mock).** *Mitigation:* the
  test scaffold already separates `mockFrom` (tenant) from `mockServiceFrom` (service-role); every
  fallback AC asserts `mockServiceFrom` called AND `mockFrom` not called (the PR #4913 deepen-plan P1
  lesson, already encoded in the sibling block).
- **Risk: `reportSilentFallback` skipped on the `denied_jti` early-return.** *Mitigation:* FR3 + AC4
  require the `reportSilentFallback` call to fire *before* the per-cause branch returns, so the
  `denied_jti` 403 path still mirrors to Sentry.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text,
  or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is filled with a
  concrete artifact (dead rename/delete button), a concrete exposure analysis (N/A — self-scoped
  read), and the `single-user incident` threshold.
- **The fail-closed branch must RETURN a Response, not throw** — both route handlers call this helper
  outside their `try` blocks, so a thrown `RuntimeAuthError` becomes an uncontrolled Next.js 500
  instead of a clean 403. (FR2/AC3.)
- **Do not extend `.service-role-allowlist` with a new path line** — `kb-route-helpers.ts` is already
  on it (PR #4913). The edit is comment-only; a new path line would trip CODEOWNERS path-add review
  for no reason.
- **Prefer the explicit-availability-causes branch shape** (`if jwt_mint||rotation → fallback; else →
  403`) over `if denied_jti → 403; else → fallback`, so a future unknown 4th cause fails CLOSED on a
  mutation route rather than silently falling back.

## Alternative Approaches Considered

| Approach | Verdict | Rationale |
|---|---|---|
| Extract a shared `resolveSelfRowWithMintFallback(userId, policy)` helper both entry points call | **Rejected (default)** | The policy parameter (all-causes vs deny-on-`denied_jti`) re-couples the two deliberately-divergent call sites; the shared body is only ~8 lines. Inline mirrors `resolveUserKbRoot` and keeps each helper's policy local + readable. Trivial to fold in if plan-review prefers. |
| Apply all-causes fallback (copy PR #4913 verbatim) | **Rejected** | Defeats the `denied_jti` revocation on a *mutation* route — the exact "more aggressive than read-only share" hazard the issue flags. |
| Fail closed on ALL three causes (no availability fallback) | **Rejected** | Leaves the `jwt_mint`/`rotation` brand-survival dead-end unfixed — the whole point of the issue. Availability failures are not authorization signals. |
| Return 503 (current) but add a client retry | **Rejected** | Treats a deterministic ceiling-trip (`rotation`) as transient; the 60/hr ceiling won't clear in retry-seconds (`tenant.ts:169`). Server-side fallback is the correct fix, matching #4913. |

---

Follow-up from PR #4913 (`fix(kb): service-role fallback when tenant-mint dead-ends Generate-link
button`). See that PR's body §"Safety ceiling (denied_jti)" and the learning at
`knowledge-base/project/learnings/bug-fixes/2026-06-04-tenant-mint-failure-needs-self-row-service-role-fallback.md`
§"Caveat — mutation paths differ". PR body should use `Closes #4914`.
