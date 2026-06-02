---
title: "fix: Share-a-key BYOK delegation — persistence, revoke arg-mismatch, and owner-side workspace resolution"
date: 2026-06-02
type: fix
branch: feat-one-shot-key-delegation-state-persistence
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issues: []
related_prs: [4767, 4761]
---

# 🐛 fix: "Share a key" delegation — persistence + cannot-disable + owner-side workspace resolution

## Overview

The "Share a key" (BYOK key delegation) control on **Settings → Members → Team**
has three reported symptoms against `app.soleur.ai`:

1. **PERSISTENCE** — after a login/logout cycle the toggle does not reload its
   on/off state correctly (appears to reset).
2. **SHARE-KEY FAILURE** — toggling on for some members raises
   *"Couldn't share a key with this member. Please try again."*
3. **CANNOT DISABLE** — once on, the toggle cannot be turned off; it snaps back
   on (revoke path appears broken).

Two recent merges are the immediate context and **are already on `origin/main`**
(premise validated — see Research Reconciliation):

- **#4761** (merged 2026-06-01) — aligned `grant_byok_delegation` RPC named args
  (`p_daily_usd_cap_cents` / `p_hourly_usd_cap_cents` / `p_actor_user_id` +
  `p_expires_at`) so the **grant** POST resolves. Also stopped the toggle's
  silent `if (res.ok)` swallow → now surfaces a `window.alert` on non-OK.
- **#4767** (merged 2026-06-02) — swapped the **member-consumption** resolvers in
  `byok-resolver.ts` from `getDefaultWorkspaceForUser` (= `MIN(created_at)`, the
  member's oldest/solo workspace) to `resolveCurrentWorkspaceId` (the canonical
  ADR-044 active-workspace resolver), so an accepted member reads the delegation
  in the **shared** workspace the owner granted into.

**Root-cause synthesis — all three are facets of one workspace-resolution /
state-sync defect, plus an RPC-arg parallel to #4761 that #4761 did not touch:**

- The **owner-side** Settings page resolver (`server/team-membership-resolver.ts`)
  derives its `workspaceId` via a **third, distinct** mechanism:
  `workspaces.organization_id = orgId` then unordered `[0]` (`team-membership-resolver.ts:128`).
  This id is threaded into `DelegationToggle.workspaceId` (used as the **grant
  POST body** `workspaceId`) **and** used to read `byok_delegations.workspace_id`
  for the persisted toggle state (`delegationFromMe`). It is neither
  `getDefaultWorkspaceForUser` nor `resolveCurrentWorkspaceId`. When an owner's
  org has more than one workspace (or the unordered `[0]` is non-deterministic
  across sessions), the workspace the grant is **written to** and the workspace
  the page **reads back** can diverge → persisted delegation invisible on reload
  (**symptom 1**) and grants landing in a workspace the member's
  `resolveCurrentWorkspaceId` does not read (residual **symptom 2**, even after
  #4767 fixed the member read).
- The **revoke** path (`DELETE /api/workspace/delegations`,
  `app/api/workspace/delegations/route.ts:142-146`) calls
  `revoke_byok_delegation` with **wrong named args**:
  `p_revoked_by_user_id` / `p_revocation_reason`. Migration 064's signature is
  `revoke_byok_delegation(p_delegation_id uuid, p_actor_user_id uuid, p_reason text)`
  (064:495-498) — proven by the working CLI `scripts/byok-revoke.ts:154-158`.
  PostgREST resolves `rpc()` by argument-name set → mismatch → PGRST202 → HTTP
  400 → the toggle's `if (res.ok)` never flips `active=false` and now raises
  *"Couldn't stop sharing the key."* This is the **identical defect class #4761
  fixed for grant, left unfixed on revoke** (**symptom 3**).

**Fix shape (caller-only; no migration / schema / RPC change):**

- **A — Revoke arg alignment** (symptom 3): change the DELETE route's `.rpc()`
  args to the canonical `{ p_delegation_id, p_actor_user_id, p_reason }`. Pin
  with a `toHaveBeenCalledWith` test mirroring #4761's grant test.
- **B — Owner-side workspace resolution** (symptoms 1 & 2): converge the
  owner-side page on the canonical `resolveCurrentWorkspaceId` so the workspace
  the grant is written to, the workspace the page reads delegations from, and
  the workspace the member consumes from (#4767) are **the same id**. This makes
  the persisted toggle state reload-stable and ensures grants land where the
  member reads them.

`service_role` already holds `EXECUTE` on `revoke_byok_delegation` (064:572), so
the arg fix alone makes the revoke path functional.

## Enhancement Summary

**Deepened on:** 2026-06-02
**Gates run:** 4.4 precedent-diff, 4.45 verify-the-negative, 4.6 User-Brand Impact
(pass), 4.7 Observability (pass), 4.8 PAT-shaped (pass, no match), 4.5 network
(skipped, no triggers). Live citation + attribution verification.

### Key verifications (all confirmed against `origin/main`)

1. **Cited PRs are MERGED and touch the claimed files.** `#4761` (MERGED) changed
   `delegations/route.ts` (12 lines) + `delegation-toggle.tsx` — confirms it fixed
   the **grant** args and silent-swallow, leaving the **revoke** args at the old
   names. `#4767` (MERGED) swapped `getDefaultWorkspaceForUser →
   resolveCurrentWorkspaceId` in `byok-resolver.ts` + `chat/layout.tsx`.
2. **Revoke precedent-diff (4.4):** the prescribed fix
   `{ p_delegation_id, p_actor_user_id, p_reason }` is byte-identical to migration
   064's signature (`064:495-498`) and the working CLI `scripts/byok-revoke.ts:154-158`.
   The broken route uses `p_revoked_by_user_id` / `p_revocation_reason`. Not novel —
   this is the canonical revoke arg set.
3. **Owner-resolver precedent (Fix B):** #4767's member-side diff is the exact
   pattern Fix B applies to the owner page (`getDefaultWorkspaceForUser` /
   unordered-`[0]` → `resolveCurrentWorkspaceId`). Not novel.
4. **Verify-the-negative (4.45):** the "fail closed to the caller's own solo
   workspace, never a sibling" claim is **confirmed** by
   `workspace-resolver.ts:215` (`return userId; // fail to solo workspace, never a
   sibling`) and the doc comments at `:234,:275`. The fix preserves the
   cross-tenant invariant.

### New consideration surfaced

- `resolveCurrentWorkspaceId` returns `userId` (the owner's solo workspace) when
  `current_workspace_id` is NULL. For an owner who created the org solo and never
  switched, this is the shared workspace (N2: `workspace_id === user_id`), so the
  read is correct. But an owner whose org workspace id ≠ `user_id` (e.g., ownership
  transferred to them, or a future multi-workspace org) MUST have a
  `current_workspace_id` row pointing at the org workspace, else the solo fallback
  reads the wrong workspace. /work MUST trace the owner's `current_workspace_id`
  lifecycle (set by `accept-invite` / `set_current_workspace_id` / active-repo
  badge self-heal) and add a resolver test for the NULL-claim owner case (already
  captured as task 2.5 and the third Sharp Edge).

## Research Reconciliation — Spec vs. Codebase

| Premise (from task framing) | Codebase reality (verified) | Plan response |
| --- | --- | --- |
| #4767 + #4761 are "recent related merges to study first" | Both MERGED on `origin/main` (#4761 2026-06-01, #4767 2026-06-02). `git log`: `9f1d8333` (#4761), `ffc2e35f` (#4767). | Premise valid. Build ON these, not around them. |
| Symptom 2 (share failure) "the grant_byok_delegation RPC or its caller is failing" | #4761 already aligned the **grant** POST args (`route.ts:84-92`) and they match 064 (`p_daily_usd_cap_cents`, etc.). Grant POST is contract-correct. | Residual symptom-2 cause is **workspace-mismatch**, not grant args. Addressed by Fix B. The error dialog can also fire on a legit `not_owner`/wrong-workspace 403. |
| Symptom 3 (cannot disable) "revoke path appears broken" | DELETE route calls `revoke_byok_delegation` with `p_revoked_by_user_id`/`p_revocation_reason` (`route.ts:143-145`); 064 signature is `p_actor_user_id`/`p_reason` (`064:496-498`). Mismatch → PGRST202 → 400. **Live bug.** | Fix A. Pin args in a new test (none exists today — grant-route test covers 0 DELETE cases). |
| Symptom 1 (persistence) "toggle does not reload state" | Toggle `active` seeds from `delegation?.active` (`delegation-toggle.tsx:89`); `delegation` comes from SSR `member.delegationFromMe`, read against the owner-page `workspaceId` = unordered `workspaces.organization_id=orgId [0]` (`team-membership-resolver.ts:120-128`). Not the canonical active workspace. | Fix B — converge owner-side page on `resolveCurrentWorkspaceId`. |
| "Fix likely lives in web-platform Members/Team settings UI and the Supabase RPCs for grant/revoke" | UI + route are the fix surface. **RPCs are correct as-is** — the bug is caller args (revoke) and caller workspace resolution (page). | No SQL migration. Caller-only. |

## User-Brand Impact

- **If this lands broken, the user experiences:** an org owner cannot reliably
  fund a teammate's agent runs — sharing silently fails for multi-workspace
  owners, the on/off state does not survive a re-login, and once on it can never
  be turned off. The single highest-value team action is unusable, with the
  user's only signal being an error dialog that re-appears every attempt.
- **If this leaks, the user's money is exposed via:** the revoke fix re-enables
  turning OFF a spend delegation. While broken, an owner who grants a daily cap
  **cannot stop the spend** through the UI — the funded member keeps drawing on
  the owner's key indefinitely. The workspace-resolution fix must continue to
  **fail closed to the caller's own solo workspace, never a sibling** (preserve
  the #4767 cross-tenant invariant); a regression here could read/write a
  delegation in the wrong tenant's workspace.
- **Brand-survival threshold:** single-user incident — a single owner who cannot
  stop a spend delegation, or whose share silently no-ops, is a brand-survival
  event for a small-team product.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (revoke args):** `DELETE /api/workspace/delegations` calls
  `service.rpc("revoke_byok_delegation", {...})` with exactly
  `{ p_delegation_id, p_actor_user_id, p_reason }` and **no** `p_revoked_by_user_id`
  / `p_revocation_reason` keys. Verified by a new vitest `toHaveBeenCalledWith`
  assertion + negative `not.toHaveProperty` on the two legacy names. Test is RED
  against current `route.ts`, GREEN after the fix.
- [ ] **AC2 (revoke success flips state):** with the mocked RPC returning
  `{ error: null }`, the route returns `{ ok: true }` (200) and the toggle's
  `setActive(false)` branch runs (component test: after a successful DELETE the
  `role="switch"` reads `aria-checked="false"`).
- [ ] **AC3 (owner workspace convergence):** `resolveTeamMembershipPageData`
  resolves the page `workspaceId` via `resolveCurrentWorkspaceId(user.id, …)`
  (the ADR-044 canonical resolver), not via unordered
  `workspaces.organization_id=orgId [0]`. Verified in
  `test/team-membership-resolver.test.ts`: given a user whose
  `current_workspace_id` = shared workspace W but whose org also contains an
  older workspace V, the resolver returns `workspaceId === W`, and
  `delegationFromMe` is read against W.
- [ ] **AC4 (fail-closed invariant preserved):** when `current_workspace_id`
  resolution errors or the caller is not a member of the claimed workspace, the
  resolver falls back to the caller's **own solo** workspace (`user.id`), never a
  sibling — mirrors #4767 / `resolveActiveWorkspaceKbRoot` J5 self-heal. Covered
  by a resolver test asserting the solo fallback id.
- [ ] **AC5 (grant↔read↔consume same id):** the workspace id passed to
  `DelegationToggle.workspaceId` (→ grant POST body) equals the id the page reads
  `byok_delegations` from equals the id `resolveCurrentWorkspaceId` returns for
  the owner — asserted via the resolver test returning a single id used for all
  three. (Closes the symptom-1/symptom-2 divergence.)
- [ ] **AC6 (no schema change):** `git diff --name-only origin/main...HEAD` shows
  **zero** files under `apps/web-platform/supabase/migrations/`.
- [ ] **AC7 (no regression in grant):** existing `api-delegation-grant-route.test.ts`
  and `delegation-toggle.test.tsx` continue to pass unchanged.
- [ ] **AC8 (typecheck + lint):** `npm run --prefix apps/web-platform typecheck`
  (= `tsc --noEmit`) and `npm run --prefix apps/web-platform lint` pass. NOTE:
  the repo has **no root `workspaces:` field**, so `-w apps/web-platform` does
  NOT work — CI uses `--prefix apps/web-platform` (verified against
  `.github/workflows`).

### Post-merge (operator)

- [ ] **AC9 (prod smoke — automatable via Playwright MCP):** on `app.soleur.ai`
  as an org owner with ≥1 member: toggle Share-a-key ON (no error dialog), reload
  the page (state persists ON), toggle OFF (state persists OFF). Drive via
  `mcp__playwright__*` against the live owner session; capture the toggle
  `aria-checked` transitions. Not operator-manual — Playwright-first per work
  Phase 4. *Automation: feasible via Playwright MCP.*

## Implementation Phases

> TDD per `cq-write-failing-tests-before`: write the RED test, then the fix.
> Runner is **vitest** (`apps/web-platform/package.json scripts.test = "vitest"`;
> `bunfig.toml` blocks bun test discovery). Test files MUST live under
> `test/**/*.test.ts` / `test/**/*.test.tsx` (vitest `include` globs at
> `vitest.config.ts:44,60`) — co-located tests are silently skipped.

### Phase 1 — Revoke arg alignment (symptom 3)

1. **RED:** add `test/api-delegation-revoke-route.test.ts` (or extend the grant
   test file) asserting the DELETE handler calls
   `revoke_byok_delegation` with `{ p_delegation_id, p_actor_user_id, p_reason }`
   and `not.toHaveProperty('p_revoked_by_user_id')` /
   `not.toHaveProperty('p_revocation_reason')`. Mirror the mock shape in
   `api-delegation-grant-route.test.ts` (service-client `.rpc` spy,
   `validateOrigin`/`isByokDelegationsEnabled`/`auth.getUser` mocks, the
   `byok_delegations` ownership-probe `.maybeSingle()` mock). Confirm RED.
2. **GREEN:** in `app/api/workspace/delegations/route.ts` DELETE handler, change
   the `.rpc("revoke_byok_delegation", …)` arg object to
   `{ p_delegation_id: body.delegationId, p_actor_user_id: user.id, p_reason: reason }`.
   Add a comment pinning the contract to `064:496-498` + `scripts/byok-revoke.ts`
   (same explanatory comment style as the grant block at `route.ts:79-83`).
3. **Component test:** in `test/delegation-toggle.test.tsx`, add a case: mounted
   with `delegation={{…, active:true}}`, click the switch, mock DELETE → 200,
   assert `aria-checked` flips to `false` and **no** `window.alert` fired. (AC2.)

### Phase 2 — Owner-side workspace resolution convergence (symptoms 1 & 2)

1. **RED:** extend `test/team-membership-resolver.test.ts` with a fixture where
   the owner's org has two workspaces (older V, current shared W) and
   `user_session_state.current_workspace_id = W`. Assert the resolver returns
   `data.workspaceId === W` and reads delegations from W. Confirm RED against the
   current unordered-`[0]` code (it returns V or is order-dependent).
2. **GREEN:** in `server/team-membership-resolver.ts`, replace the
   `workspaces.organization_id=orgId → [0]` derivation of `workspaceId` with a
   call to `resolveCurrentWorkspaceId(user.id, service)` (import from
   `@/server/workspace-resolver`). Keep the existing membership/role checks. The
   resolver already fails closed to `user.id` (solo), preserving the cross-tenant
   invariant.
   - **Sweep sibling readers in this resolver:** the `byok_delegations`,
     `workspace_members`, `workspace_invitations` (in `team/page.tsx`), and
     `users` queries that filter on `workspaceId` must all consume the converged
     id. They already read the resolver's `workspaceId`, so converging the source
     converges them — but verify each by grep (`rg "workspaceId" team/page.tsx
     server/team-membership-resolver.ts`) and confirm none re-derives the id
     independently.
3. **Fail-closed test:** add the resolver test for the membership-mismatch /
   error → `user.id` solo fallback (AC4).

### Phase 3 — Verification

1. Run `apps/web-platform` vitest for the touched files + the full delegation
   suite; confirm GREEN and no regression (AC7).
2. Run typecheck + lint (AC8).
3. Confirm AC6 (no migration files changed).

## Files to Edit

- `apps/web-platform/app/api/workspace/delegations/route.ts` — DELETE handler
  revoke `.rpc()` arg alignment (Phase 1).
- `apps/web-platform/server/team-membership-resolver.ts` — converge `workspaceId`
  onto `resolveCurrentWorkspaceId` (Phase 2).
- `apps/web-platform/test/delegation-toggle.test.tsx` — add revoke-success +
  revoke-failure-alert cases (Phase 1.3).
- `apps/web-platform/test/team-membership-resolver.test.ts` — add multi-workspace
  convergence + fail-closed cases (Phase 2).

## Files to Create

- `apps/web-platform/test/api-delegation-revoke-route.test.ts` — pins the revoke
  RPC arg contract (Phase 1.1). *(If the maintainer prefers, this can instead be
  added to `api-delegation-grant-route.test.ts`; create-vs-extend is the author's
  call at /work time — keep the contract-pinning assertions either way.)*

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` returned no issue whose
body names `delegations/route.ts`, `team-membership-resolver.ts`, or
`delegation-toggle.tsx`. (Open BYOK issues #4628/#4656/#3934/#3929/#3928 etc. are
consent-UX, Art.33 hardening, and WORM-sweeper scope — disjoint from this fix.)

## Hypotheses

- **H1 (revoke args):** confirmed by code read — `route.ts:143-145` vs `064:496-498`.
  Highest confidence; deterministic 400 on every revoke.
- **H2 (owner workspace divergence):** confirmed structurally — three resolution
  mechanisms coexist (`getDefaultWorkspaceForUser`, `resolveCurrentWorkspaceId`,
  unordered `[0]`); the owner page uses the third. Symptom severity scales with
  how many workspaces an owner's org has; for a single-workspace org the `[0]`
  happens to coincide, which is why the bug is intermittent ("some members").
- **H3 (residual share-failure surface):** after #4761 + Fix B, a remaining
  *"Couldn't share a key"* dialog would be a genuine `not_owner`/403 (caller is
  not the owner of the resolved workspace) — which is correct behavior, not a
  bug. Worth noting in the PR so QA does not chase a non-bug.

## Domain Review

**Domains relevant:** Engineering, Product (Members UI), Legal/Compliance (BYOK
spend authorization + GDPR consent surface touched indirectly).

### Engineering

**Status:** reviewed
**Assessment:** Caller-only fix; no SQL/RPC/schema change. Two well-precedented
patterns: (a) #4761's RPC-arg-pin-by-test for the revoke path; (b) #4767's
"converge on `resolveCurrentWorkspaceId`" for the owner page. Both keep the
cross-tenant fail-closed-to-solo invariant. Risk is low and localized; the main
correctness lever is the multi-workspace resolver test (AC3/AC5).

### Legal/Compliance

**Status:** reviewed (advisory)
**Assessment:** The revoke fix restores the data subject's / owner's ability to
**stop** a spend authorization through the UI — relevant to Art. 7(3)
withdraw-ability of consent and to spend-control. The fix does NOT touch the
mig-083/084 consent-acceptance gate or the withdraw RPC; it only corrects the
grantor-revoke arg names. No new processing activity, no new data field. The
GDPR gate (Phase 2.7) is satisfied advisory-only — see GDPR note below.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (pipeline/subagent context — plan file path provided as
argument)
**Skipped specialists:** none
**Pencil available:** N/A

#### Findings

No new user-facing surface, page, or component is created — the change is to the
behavior of an existing toggle (it now turns off and persists). The existing
copy ("Couldn't share a key…", "Couldn't stop sharing the key…") is unchanged and
already brand-reviewed in #4761. ADVISORY auto-accepted per pipeline rule.

## GDPR / Compliance Gate

The plan touches an auth/spend-authorization surface (BYOK delegation revoke) and
an API route, which trips the `hr-gdpr-gate-on-regulated-data-surfaces` regex.
**Advisory finding:** the change is corrective (a broken revoke now works) and
restores — rather than weakens — the owner's ability to withdraw a spend
authorization (Art. 7(3) consent-withdrawability posture improves). No new
lawful-basis question, no special-category data, no new Article 30 processing
activity. No Critical findings; no `compliance/critical` issue required. Disclaimer:
advisory only — not legal advice.

## Infrastructure (IaC)

Not applicable — pure application-code change against already-provisioned
surfaces (`apps/web-platform/app/**`, `apps/web-platform/server/**`,
`apps/web-platform/test/**`). No new server, secret, vendor, cron, or persistent
runtime process. Skipped per Phase 2.8.

## Observability

```yaml
liveness_signal:
  what: "DELETE /api/workspace/delegations returns 200 on a valid grantor revoke; revoke_byok_delegation RPC executes without PGRST202"
  cadence: "per user action (owner toggles off)"
  alert_target: "Sentry (existing route error path: route returns 400 with error.message on RPC failure)"
  configured_in: "apps/web-platform/app/api/workspace/delegations/route.ts (DELETE error branch, line ~148)"
error_reporting:
  destination: "Sentry — the toggle's console.error + window.alert surfaces client-side; the route returns the RPC error.message in the 400 body (delegation-toggle.tsx logs res.status)"
  fail_loud: true
failure_modes:
  - mode: "revoke RPC arg-name mismatch (the bug being fixed)"
    detection: "vitest contract test (AC1) asserts the exact arg set; PGRST202 surfaces as 400 in the route"
    alert_route: "CI test gate (pre-merge); Sentry on the live 400 (post-merge)"
  - mode: "owner-page workspace divergence (grant lands where read does not)"
    detection: "resolver test (AC3/AC5) asserting grant/read/consume share one id"
    alert_route: "CI test gate (pre-merge); Playwright prod smoke (AC9, post-merge)"
  - mode: "wrong-workspace read regression (cross-tenant)"
    detection: "fail-closed resolver test (AC4) asserting solo fallback never a sibling"
    alert_route: "CI test gate; #4767 cross-tenant invariant tests remain green"
logs:
  where: "Vercel/Next server logs for the route; client console.error in delegation-toggle.tsx"
  retention: "per existing platform log retention (unchanged)"
discoverability_test:
  command: "npm run --prefix apps/web-platform test:ci -- test/api-delegation-revoke-route.test.ts test/team-membership-resolver.test.ts test/delegation-toggle.test.tsx"
  expected_output: "all suites pass; revoke contract test asserts p_actor_user_id/p_reason and rejects the two legacy arg names"
```

## Test Scenarios

| # | Scenario | Expected |
| --- | --- | --- |
| T1 | DELETE handler invoked with a valid grantor-owned delegation | `.rpc("revoke_byok_delegation", { p_delegation_id, p_actor_user_id, p_reason })`; no legacy keys; route returns `{ ok: true }` |
| T2 | Toggle ON, user clicks off, DELETE → 200 | `aria-checked` flips to `false`, no alert |
| T3 | Toggle ON, user clicks off, DELETE → 400 | toggle stays ON, `window.alert("Couldn't stop sharing the key…")` (existing AC5 behavior, must remain) |
| T4 | Owner org has workspaces V (older) + W (current_workspace_id) | resolver `workspaceId === W`; delegations read from W |
| T5 | current_workspace_id resolution errors / caller not a member of claimed ws | resolver falls back to `user.id` (solo), never a sibling |
| T6 | Grant then reload (integration intent, covered by Playwright AC9 post-merge) | toggle persists ON across reload/re-login |

## Alternative Approaches Considered

| Approach | Why not |
| --- | --- |
| Change migration 064 revoke signature to accept `p_revoked_by_user_id`/`p_revocation_reason` | Wrong direction — the CLI `byok-revoke.ts` and the SECURITY DEFINER body already use the canonical names; the caller is the only wrong party. A migration would be a needless schema churn and would diverge the two callers. |
| Make `delegation-toggle.tsx` re-fetch its own state on mount (client GET) instead of fixing SSR persistence | Adds a client round-trip and a second resolution path; the SSR `delegationFromMe` is already the source of truth — the bug is which workspace it reads, not when. Fixing the resolver fixes both SSR and any future client read. |
| Add `set_current_workspace_id` write for the owner on page load to normalize `[0]` | A GET with a side-effect write violates the read-only-GET convention (#4767 J5 self-heal note); `resolveCurrentWorkspaceId` already returns the right id read-only. |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan`
  Phase 4.6. (This plan's section is filled; threshold = single-user incident →
  `requires_cpo_signoff: true`.)
- **Revoke arg fix is the same class as #4761 — verify against the SAME source of
  truth #4761 used.** Pin args to migration `064:496-498` and the working
  `scripts/byok-revoke.ts:154-158`, NOT to the grant block's names (grant uses
  `p_grantor_user_id`/`p_grantee_user_id`/`p_workspace_id`/`p_daily_usd_cap_cents`
  /`p_hourly_usd_cap_cents`/`p_expires_at`/`p_actor_user_id` — a DIFFERENT 7-arg
  set; the revoke set is the 3-arg `p_delegation_id`/`p_actor_user_id`/`p_reason`).
- **`resolveCurrentWorkspaceId` reads `user_session_state.current_workspace_id`
  and falls back to `userId` (solo) on null/error.** For an owner who has never
  switched workspaces, `current_workspace_id` may be NULL → falls back to
  `user.id` (the owner's solo workspace = the shared workspace when the owner
  created the org solo, since N2 invariant: solo `workspace_id === user_id`).
  Confirm in the resolver test that this NULL→solo case still reads the right
  delegations; if an owner's org workspace id differs from `user.id`, the owner
  must have a `current_workspace_id` row pointing at it (set by `accept-invite`
  or `set_current_workspace_id`). Trace this for the owner path at /work time —
  do NOT assume the owner always has a non-null `current_workspace_id`.
- **Test runner is vitest, files under `test/**`.** A co-located
  `*.test.tsx` next to the component is silently never run (`vitest.config.ts`
  include globs are `test/**/*.test.ts(x)` only). Put new tests under `test/`.
- **No `Closes #N`** — there is no GitHub issue for this work item; use the PR
  body to reference #4761/#4767 as context (`Ref #4761, #4767`), not `Closes`.

## Notes for /work

- Per `brand_survival_threshold: single-user incident`, the exit gate should
  recommend `deepen-plan` (already the next pipeline step) — the
  data-integrity/security/architecture triad catches workspace-resolution and
  cross-tenant subtleties that style-only plan-review misses (see learning
  `2026-05-22-plan-review-and-deepen-plan-catch-different-issue-classes.md`,
  which was authored against the original byok-delegations PR-A #4232).
- CPO sign-off is required at plan time before `/work` (threshold = single-user
  incident). Either invoke CPO or confirm CPO has reviewed; record in this plan.
