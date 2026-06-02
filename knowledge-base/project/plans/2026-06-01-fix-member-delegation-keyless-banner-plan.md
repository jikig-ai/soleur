---
title: "fix: member-side delegation consumption resolves wrong workspace, keeping keyless banner up"
type: bug
date: 2026-06-01
branch: feat-one-shot-member-delegation-keyless-banner
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# 🐛 fix: member sees "tasks need an API key" banner after owner shares a key (wrong-workspace delegation lookup)

## Enhancement Summary

**Deepened on:** 2026-06-01
**Sections enhanced:** Files to Edit, Acceptance Criteria, + new Research Insights
**Gates run:** 4.4 precedent-diff, 4.45 verify-negative + post-edit self-audit, 4.6 User-Brand
Impact (pass), 4.7 Observability (pass — 5/5 fields), 4.8 PAT-shaped (pass — no matches), 4.5
network (no trigger).

### Key Improvements

1. **Precedent confirmed:** `resolveCurrentWorkspaceId` is the canonical active-workspace
   resolver (`current-repo-url.ts:49`, `resolve-installation-id.ts:37`, `insert-draft-card`,
   `resolveActiveWorkspaceKbRoot`); the fix de-orphans BYOK from a stale N2 assumption — not a
   novel pattern.
2. **Security claims verified-negative:** the swap fails closed to the caller's own solo
   workspace (`workspace-resolver.ts:215,217`), never a sibling — no widened/cross-tenant read.
3. **Test compatibility enumerated (not sampled):** two server tests pin the old derivation and
   are now in Files to Edit + AC9 — `byok-effective-key.test.ts` (has a literal "uses the SAME
   getDefaultWorkspaceForUser" parity test at line 168) and `byok-resolver-fail-closed.test.ts`
   (the no-throw vs throw semantic shift is the Sharp Edge made concrete).
4. **Orphan import pinned:** `getDefaultWorkspaceForUser` has exactly two uses in
   `byok-resolver.ts` (lines 128, 318), both replaced → import is fully replaced, `tsc` catches
   residuals.

### New Considerations Discovered

- A **third consumer** of `userHasEffectiveByokKey` — the onboarding redirect gates (callback,
  accept-terms, `onErrorReturn:true`, fail-OPEN) — is insulated (mocks the helper directly) but
  must be sanity-checked at /work: an accepted member must NOT be trapped at /setup-key.
- `resolveCurrentWorkspaceId` works under the service client byok-resolver uses (explicit
  `.eq("user_id", userId)` self-scope; no `auth.uid()` dependency).


## Overview

After an org owner successfully shares a key with a member (PR #4761 fixed the owner-side
`grant_byok_delegation` write, so a `byok_delegations` row now exists with
`grantee_user_id = member`, `workspace_id = the owner's shared workspace`,
`revoked_at = NULL`), the member **still** sees the dashboard keyless banner
("You're in — tasks need an API key. … Ask your workspace owner to share one, or add your own.")
with an "Add your own key" CTA. This is the **downstream / grantee-side consumption** half of
#4761 — distinct, new scope.

**Root cause (traced, not assumed):** the member-side effective-key and pending-delegation
resolvers derive the **wrong workspace** when they look up the delegation. Both
`userHasEffectiveByokKey` (step 3) and `userHasPendingByokDelegation` in
`apps/web-platform/server/byok-resolver.ts` derive their `workspaceId` via
`resolveByokDelegationContext` → `getDefaultWorkspaceForUser(callerUserId)`, which returns the
member's **oldest workspace by `workspaces.created_at`** (`MIN(created_at)`,
`apps/web-platform/server/workspace-resolver.ts:403-456`). An invited member who already had a
solo account holds **two** `workspace_members` rows: their own solo workspace (created at the
member's signup — older) and the shared workspace they were invited into (created later, when
the owner set up the org). The delegation lives in the **shared** workspace, but
`MIN(created_at)` resolves the **solo** workspace, so:

- `resolve_byok_key_owner(member, member's_solo_workspace)` (mig 084) filters
  `bd.workspace_id = p_workspace_id` and finds **no** delegation → `delegation_id` is `null` →
  `userHasEffectiveByokKey` returns `false`.
- `userHasPendingByokDelegation` filters `byok_delegations` by
  `workspace_id = member's_solo_workspace` → finds **no** row → returns `false`.

`hasEffectiveKey:false` + `pendingDelegation:false` + `isSharedWorkspaceMember:true` is exactly
the `joiner` branch in `apps/web-platform/components/dashboard/no-api-key-banner.tsx:75,82-85`,
which is the reported banner.

**The fix surface is `byok-resolver.ts`** — switch the delegation workspace context from
`getDefaultWorkspaceForUser` (oldest) to the user's **current/active** workspace, which is the
shared workspace (`accept-invite` sets `current_workspace_id = shared workspace` via
`set_current_workspace_id`, `apps/web-platform/app/api/workspace/accept-invite/route.ts:78-80`).
The canonical "which workspace is this user acting in" resolver already exists and is used by
every other ADR-044 read path: `resolveCurrentWorkspaceId(userId, supabase)`
(`workspace-resolver.ts:190-218`) reads `user_session_state.current_workspace_id` and
fails closed to the solo workspace (never a sibling). The BYOK resolver is the lone outlier
still using `getDefaultWorkspaceForUser` under the now-stale N2 solo assumption (the inline
comments at `byok-resolver.ts` and the runtime call sites literally say "team workspaces will
diverge when Phase 4 invite flow ships" — Phase 4 has shipped).

**Scope is two consumers of the same wrong derivation, and they must move together** so the fix
is real, not cosmetic:

1. **Banner / effective-status (UX):** `userHasEffectiveByokKey` + `userHasPendingByokDelegation`
   via `resolveByokDelegationContext`. Fixing only this makes the banner disappear.
2. **Runtime lease (the actual capability):** `resolveKeyOwnerThenLease`
   (`byok-resolver.ts:119-183`) ALSO derives its workspace via
   `getDefaultWorkspaceForUser(workspaceContextUserId)`. If we fix only #1, the banner vanishes
   but the member's task runs would STILL look in the solo workspace, fail to find the
   delegation, and hit `MissingByokKeyError`/`KeyInvalidError` at chat time — a worse state
   (the banner now lies in the opposite direction). The runtime path is in-scope.

This is a `single-user incident` brand-survival fix (the highest-value team action — funding a
teammate's runs — is non-functional on the consumption side for every invited member who had a
prior solo account).

## Premise Validation

- **PR #4761 (owner-side grant write):** `gh pr view 4761` → `merged: 2026-06-01T16:34:30Z`,
  title "fix(delegations): align grant_byok_delegation RPC args so 'Share a key' toggle works".
  Confirmed merged; the owner-side write now produces a real `byok_delegations` row. The cited
  "downstream half" framing holds.
- **`grantee_user_id` / `delegationToMe` / grantee-delegation resolution path:** confirmed
  present and traced end-to-end (banner → `/api/byok/effective-status` route →
  `byok-resolver.ts` helpers → `resolve_byok_key_owner` RPC mig 084 / direct
  `byok_delegations` SELECT). Not a "never-built" case — this is a behavioral bug in shipped
  code.
- **Banner string producer:** `git grep` of the literal copy resolves to exactly one producer,
  `apps/web-platform/components/dashboard/no-api-key-banner.tsx:83-85` (no duplicate/stale copy).
- **Live repro corroboration:** member `jean.deruelle@gmail.com` sees the joiner banner after the
  owner shared — consistent with the wrong-workspace hypothesis (a pre-existing solo account →
  older solo workspace wins `MIN(created_at)`).

No stale premises. The bug is a workspace-derivation mismatch in `byok-resolver.ts`.

## Research Reconciliation — Spec vs. Codebase

| Claim (from the bug report) | Codebase reality | Plan response |
| --- | --- | --- |
| "member-side effective-key resolution does not recognize the active delegation granted TO them" | True, but the mechanism is **wrong workspace**, not a missing `grantee_user_id` predicate. The RPC (mig 084) and the pending query DO filter `grantee_user_id = caller`; they additionally filter `workspace_id`, and the workspace handed in is the member's *solo* workspace (`getDefaultWorkspaceForUser` = `MIN(created_at)`), not the shared workspace the delegation lives in. | Fix = swap the workspace derivation to `resolveCurrentWorkspaceId` (active workspace), not add/relax the grantee predicate (which already exists). |
| "their session resolves an effective key via that delegation and the keyless banner disappears" | Requires acceptance state too: `resolve_byok_key_owner` (mig 084 Gate 1) only returns a delegation row when a **current-version acceptance** exists. A *shared-but-unaccepted* grant correctly resolves `hasEffectiveKey:false` AND (once the right workspace is queried) `pendingDelegation:true` → the banner shows the one-click **"Accept your grant"** branch, not the keyless joiner branch. | Plan must verify BOTH outcomes: (a) shared+unaccepted → pending "Accept" branch; (b) shared+accepted → banner gone. Do NOT broaden the effective-key gate past the acceptance gate. |
| Banner producer / hasEffectiveKey flag | `no-api-key-banner.tsx` self-fetches `/api/byok/effective-status`; flag = `!hasEffectiveKey`. Resolvers fail-closed (`onErrorReturn:false`). | No change to the component or the route — both are correct; the wrong value comes from `byok-resolver.ts`. |
| `byok-delegation-ui-resolver` queries `grantee_user_id = current user AND active` | `resolveGranteeDelegation` (ui-resolver:117-133) ALSO filters `.eq("workspace_id", workspaceId)` with a caller-passed workspace. It has the SAME latent wrong-workspace exposure when fed `getDefaultWorkspaceForUser`. Its callers pass `workspaceId` from their own context — verify each caller passes the active/shared workspace, not the solo default. | Audit `resolveGranteeDelegation` callers (Files to Edit task) — fold in if any pass the solo-default workspace. |

## User-Brand Impact

- **If this lands broken, the user experiences:** an invited teammate is told their owner-funded
  key does not exist — they see "tasks need an API key / add your own" forever, and (worse, on the
  runtime side) every task they start fails with a missing/invalid-key error despite the owner
  having paid to share a key. The core team value proposition is dead on the consumption side.
- **If this leaks, the user's data / workflow / money is exposed via:** this fix must NOT widen
  the read surface. The risk vector is resolving the **wrong** workspace in the *other*
  direction (a sibling/cross-tenant workspace) and surfacing a delegation that was never granted
  to this member, or leasing a grantor's key for an unauthorized workspace. The chosen resolver
  (`resolveCurrentWorkspaceId`) fails closed to the caller's **own solo** workspace — never an
  arbitrary sibling — preserving the IDOR/cross-tenant invariant (SS F3 in `byok-resolver.ts`).
- **Brand-survival threshold:** single-user incident — a single owner+member pair hitting a dead
  core feature on first use is a brand-survival event for a small-team product.

CPO sign-off required at plan time before `/work` begins (threshold = single-user incident).
Invoke CPO domain leader if not already covered by Phase 2.5 carry-forward.
`user-impact-reviewer` will be invoked at review-time.

## Root-Cause Call Graph (traced)

```
NoApiKeyBanner (no-api-key-banner.tsx)
  └─ fetch GET /api/byok/effective-status            (route.ts:23)
       ├─ userHasEffectiveByokKey(user.id, {onErrorReturn:false})   (byok-resolver.ts:215)
       │    1. own VALID anthropic key? → false for keyless member
       │    2. resolveByokDelegationContext(callerUserId)           (byok-resolver.ts:314)
       │         └─ getDefaultWorkspaceForUser(callerUserId)   ← WRONG: MIN(created_at) = solo ws
       │    3. resolve_byok_key_owner(caller, SOLO_ws)  → no row → delegation_id null → FALSE
       ├─ userHasPendingByokDelegation(user.id)                     (byok-resolver.ts:268)
       │    └─ resolveByokDelegationContext → getDefaultWorkspaceForUser → SOLO_ws
       │       byok_delegations WHERE grantee=caller AND workspace_id=SOLO_ws → no row → FALSE
       └─ userIsSharedWorkspaceMember(user.id)  → TRUE  (workspace-resolver.ts:140)
  ⇒ {hasEffectiveKey:false, pendingDelegation:false, isSharedWorkspaceMember:true}
  ⇒ joiner branch → "You're in — tasks need an API key"  (no-api-key-banner.tsx:75,82)

Runtime (same wrong derivation — must also fix):
agent-runner.ts:906 / :2522, cc-dispatcher.ts:908, cfo-on-payment-failed.ts:203,
github-on-event.ts:210
  └─ resolveKeyOwnerThenLease(userId, userId, fn)                   (byok-resolver.ts:119)
       └─ getDefaultWorkspaceForUser(workspaceContextUserId)  ← WRONG: SOLO ws
       └─ resolve_byok_key_owner(caller, SOLO_ws) → no delegation → MissingByokKeyError at chat
```

## The Fix (intent — not code)

Replace `getDefaultWorkspaceForUser(...)` with `resolveCurrentWorkspaceId(...)` as the BYOK
workspace-context source, in the **single shared helper** where it is derived, so all three
consumers (effective-key, pending, runtime lease) move atomically:

- `resolveByokDelegationContext` (`byok-resolver.ts:314`) — the chokepoint for
  `userHasEffectiveByokKey` step 2 and `userHasPendingByokDelegation`. Swap its
  `getDefaultWorkspaceForUser(callerUserId, supabase)` to `resolveCurrentWorkspaceId(callerUserId, supabase)`.
- `resolveKeyOwnerThenLease` (`byok-resolver.ts:128`) — swap its
  `getDefaultWorkspaceForUser(workspaceContextUserId, supabase)` to
  `resolveCurrentWorkspaceId(workspaceContextUserId, supabase)`.

**Why `resolveCurrentWorkspaceId` is the correct replacement (not a new query):**
1. It is the canonical ADR-044 active-workspace resolver, already the source of truth for
   `current-repo-url.ts`, `resolve-installation-id.ts`, `insert-draft-card.ts`, and
   `resolveActiveWorkspaceKbRoot`. Using it makes BYOK consistent with the rest of the member
   read path.
2. `accept-invite` sets `current_workspace_id` to the shared workspace, so for an accepted
   member it resolves the workspace the delegation lives in.
3. It fails closed to the caller's **own solo** workspace (`workspace-resolver.ts:215,217`),
   never a sibling — preserving the cross-tenant invariant. A solo user with no shared
   membership still resolves their own workspace bit-for-bit (own-key path is unaffected; the
   own-key short-circuit in `resolve_byok_key_owner` and `userHasEffectiveByokKey` step 1 runs
   before workspace derivation matters for solo).

**DELIBERATE NON-CHANGE:** do not relax mig 084 Gate 1 (current-version acceptance). A
shared-but-unaccepted grant must NOT resolve `hasEffectiveKey:true`; instead, with the correct
workspace, `userHasPendingByokDelegation` returns `true` and the banner shows the one-click
**"Accept your grant"** branch (`no-api-key-banner.tsx:79-81`). That is the intended UX, not a
bug to paper over.

## Sharp Edges (for the implementer)

- **`resolveCurrentWorkspaceId` returns `Promise<string>` (never null/throws);
  `getDefaultWorkspaceForUser` returns `Promise<string>` (throws on integrity violation).** The
  current `resolveByokDelegationContext` is `async` and lets `getDefaultWorkspaceForUser` throw
  up to each caller's outer try/catch (fail-direction picked per caller). After the swap,
  `resolveCurrentWorkspaceId` mirrors-to-Sentry-then-returns-solo-fallback on a query error — it
  will NOT throw. Verify each caller's fail posture still holds: the status endpoint stays
  fail-closed (a degraded resolve now yields the solo workspace → likely no delegation → banner
  shows, which is the safe direction). `resolveKeyOwnerThenLease`'s existing
  `getDefaultWorkspaceForUser` try/catch fallback-to-direct-lease block (`byok-resolver.ts:127-135`)
  becomes effectively unreachable for the workspace step; keep the structure but confirm it does
  not mask the new semantics. Read both functions fully before editing.
- **A plan whose `## User-Brand Impact` section is empty / TBD will fail `deepen-plan` Phase 4.6.**
  This plan's section is filled.
- **Runtime vs UX consistency is load-bearing.** If only `resolveByokDelegationContext` is fixed,
  the banner disappears but `resolveKeyOwnerThenLease` still looks in the solo workspace and tasks
  fail. Both swaps ship in the same PR.
- **Acceptance-state, not just presence.** The effective-key path depends on the mig-084
  acceptance gate. Tests must cover shared+unaccepted (→ pending) AND shared+accepted (→ key) so
  the workspace fix is not conflated with the acceptance gate.
- **Test runner is vitest, not bun.** Server resolver tests live under
  `apps/web-platform/test/**/*.test.ts` (the vitest `include` glob; `bun test` is blocked by
  `apps/web-platform/bunfig.toml [test] pathIgnorePatterns`). Run with
  `./node_modules/.bin/vitest run test/<file>` from `apps/web-platform`.
- **N2 solo invariant comments are now stale.** The inline comments at the three runtime call
  sites ("team workspaces will diverge when Phase 4 invite flow ships") describe a future that
  has arrived; update them to reflect current-workspace resolution so the next reader is not
  misled.

## Files to Edit

- `apps/web-platform/server/byok-resolver.ts`
  - `resolveByokDelegationContext` (line ~314): swap `getDefaultWorkspaceForUser` →
    `resolveCurrentWorkspaceId`; update the docstring (it currently claims "the SAME default
    workspace the runtime uses").
  - `resolveKeyOwnerThenLease` (line ~128): swap `getDefaultWorkspaceForUser` →
    `resolveCurrentWorkspaceId`; reconcile the try/catch fallback block with the no-throw
    semantics of the new resolver; update the module docstring + the N2 comment.
  - **Import (line 36):** `getDefaultWorkspaceForUser` is used at EXACTLY lines 128 and 318
    (verified by grep — the only two uses in the file, both of which this fix replaces). So the
    import becomes fully orphaned: **replace** `import { getDefaultWorkspaceForUser }` with
    `import { resolveCurrentWorkspaceId }` from `./workspace-resolver`. `tsc --noEmit` (AC8) will
    catch any residual reference.
- `apps/web-platform/server/agent-runner.ts` (lines ~895-906, ~2515-2522): update the stale N2
  "team workspaces will diverge" comments to describe current-workspace resolution. No logic
  change (args stay `userId, userId`); the workspace derivation moved inside the resolver.
- `apps/web-platform/server/cc-dispatcher.ts` (line ~900-908): same comment update.
- `apps/web-platform/server/byok-delegation-ui-resolver.ts` — **audit only, fold in if needed**:
  confirm `resolveGranteeDelegation` (line 117) callers pass the active/shared workspace, not a
  solo default. If any caller derives the workspace via `getDefaultWorkspaceForUser`, fix at that
  caller. (`resolveGrantorDelegations` is owner-side and receives an explicit workspaceId from the
  route — verify it is unaffected.)
- `apps/web-platform/test/server/byok-effective-key.test.ts` — switch the workspace-source mock
  from `getDefaultWorkspaceForUser` to `resolveCurrentWorkspaceId`; rename the line-168 parity
  test (see Research Insights → Test Compatibility).
- `apps/web-platform/test/server/byok-resolver-fail-closed.test.ts` — switch both mock paths
  (lines 42-46) to `resolveCurrentWorkspaceId` and re-express the fail-closed scenario as a
  degrade-to-solo (no-throw), not an injected throw (see Research Insights → Test Compatibility).

### Files to verify the runtime grant-funded path (read, likely no edit)

- `apps/web-platform/server/byok-lease.ts` — `runWithByokLease` carries `delegationId`; confirm
  no second workspace derivation there.
- `apps/web-platform/server/inngest/functions/cfo-on-payment-failed.ts:203`,
  `github-on-event.ts:210` — same `resolveKeyOwnerThenLease` call shape; the inside-resolver swap
  covers them. Add comment-update only if they carry the stale N2 note.

## Files to Create

- `apps/web-platform/test/byok-resolver-delegation-workspace.test.ts` — new vitest unit test
  (node env) for the resolver workspace derivation. Mocks the service client + `workspace-resolver`
  helpers. Asserts:
  - `userHasEffectiveByokKey` resolves the **current** workspace (mock
    `resolveCurrentWorkspaceId` → shared ws; mock `getDefaultWorkspaceForUser` → solo ws and
    assert it is NOT the one used / not called).
  - shared+accepted delegation in current ws → `hasEffectiveKey:true`.
  - shared+UNaccepted delegation in current ws → `hasEffectiveKey:false` AND
    `userHasPendingByokDelegation:true` (acceptance gate intact; pending branch correct).
  - solo user (no shared membership) → current ws = own ws → own-key path unaffected.
  - `resolveKeyOwnerThenLease` opens the lease with the grantor's `keyOwnerUserId` +
    `delegationId` when the active workspace carries an accepted delegation.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 (root cause):** `apps/web-platform/server/byok-resolver.ts` no longer calls
  `getDefaultWorkspaceForUser` for the delegation workspace context in either
  `resolveByokDelegationContext` or `resolveKeyOwnerThenLease`; both derive the workspace via
  `resolveCurrentWorkspaceId`. Verify:
  `grep -n "getDefaultWorkspaceForUser\|resolveCurrentWorkspaceId" apps/web-platform/server/byok-resolver.ts`
  shows zero `getDefaultWorkspaceForUser` uses in those two functions (and the import is updated
  accordingly).
- [x] **AC2 (banner disappears — accepted):** with a current-version-accepted delegation in the
  member's active (shared) workspace, `userHasEffectiveByokKey(member, {onErrorReturn:false})`
  returns `true` → `/api/byok/effective-status` returns `hasEffectiveKey:true` → banner returns
  `null`. Asserted by new test + existing `api-byok-effective-status-route.test.ts` stays green.
- [x] **AC3 (pending branch — shared but unaccepted):** with a shared-but-unaccepted delegation
  in the active workspace, `userHasEffectiveByokKey` returns `false` AND
  `userHasPendingByokDelegation` returns `true` → banner shows the "Accept your grant" branch
  (NOT the joiner "add your own key" branch). New test asserts both booleans.
- [x] **AC4 (runtime parity):** `resolveKeyOwnerThenLease` opens the lease with
  `keyOwnerUserId = grantor` + `delegationId` set when the member's active workspace carries an
  accepted delegation (new test asserts the `runWithByokLease` args).
- [x] **AC5 (solo unaffected):** a solo user (no shared membership; own valid anthropic key)
  still resolves `hasEffectiveKey:true` via the own-key short-circuit, and a keyless solo user
  still gets the original solo banner (`isSharedWorkspaceMember:false`). No regression in
  `byok.test.ts` / `byok.integration.test.ts` / `agent-runner-byok-migration.test.ts`.
- [x] **AC6 (no widened read surface):** the workspace resolver fails closed to the caller's own
  solo workspace on error (inherited from `resolveCurrentWorkspaceId`); no path resolves a
  sibling/cross-tenant workspace. Asserted by a test feeding a resolver error and confirming the
  solo-fallback workspace (not a sibling) is queried.
- [x] **AC7 (stale comments):** the N2 "team workspaces will diverge when Phase 4 invite flow
  ships" comments at the runtime call sites are updated to reflect current-workspace resolution.
- [x] **AC8:** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [x] **AC9:** `cd apps/web-platform && ./node_modules/.bin/vitest run test/byok-resolver-delegation-workspace.test.ts test/api-byok-effective-status-route.test.ts test/server/byok-effective-key.test.ts test/server/byok-resolver-fail-closed.test.ts test/byok.test.ts` all green (the two `test/server/byok-*` files are UPDATED to the current-workspace resolver per Research Insights → Test Compatibility); full web-platform vitest suite green.

### Post-merge (operator)

- [ ] **AC10 (live confirm):** re-run the live repro — owner shares a key with
  `jean.deruelle@gmail.com`; member logs in; member accepts the grant (if pending); the keyless
  banner is gone and a task run succeeds funded by the owner's shared key.
  Automation: Playwright MCP can drive the UI up to the point of two distinct authenticated
  sessions (owner + member); the two-account orchestration may require operator setup — keep as
  operator step with `Automation: partial (Playwright for single-session steps)`.

## Test Scenarios

| Scenario | Active (current) ws | Delegation row | Acceptance | Expected hasEffectiveKey | pendingDelegation | Banner |
| --- | --- | --- | --- | --- | --- | --- |
| Member, shared+accepted | shared | grantee=member, ws=shared | current-version | true | false | none |
| Member, shared+unaccepted | shared | grantee=member, ws=shared | none | false | true | "Accept your grant" |
| Member, shared, withdrawn | shared | grantee=member, ws=shared | accepted then withdrawn | false | true | "Accept your grant" |
| Member, no delegation | shared | none | — | false | false | joiner "add your own" |
| Solo, own valid key | solo (= userId) | none | — | true | false | none |
| Solo, keyless | solo (= userId) | none | — | false | false | solo "buy account" |
| Resolver error | solo fallback | n/a | — | false (fail-closed) | false | joiner/solo (degraded, safe) |

## Domain Review

**Domains relevant:** Engineering (Security), Product

### Engineering / Security

**Status:** reviewed
**Assessment:** Change narrows nothing and widens nothing on the read surface: it swaps an
oldest-workspace derivation for the canonical active-workspace resolver that fails closed to the
caller's own solo workspace. The IDOR/cross-tenant invariant (SS F3) is preserved because
`resolveCurrentWorkspaceId` never returns a sibling. The mig-084 acceptance gate (consent,
Art. 7) is deliberately untouched. Primary risk is the no-throw-vs-throw semantic difference of
the new resolver vs the old; addressed in Sharp Edges + AC6.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (pipeline context)
**Skipped specialists:** none
**Pencil available:** N/A

#### Findings

No new user-facing surface is created. The banner component and its copy are unchanged; the fix
flips which copy branch the member sees (joiner → either "gone" or one-click "Accept your grant").
The "Accept your grant" branch is the intended, higher-value UX for a shared-but-unaccepted grant.
CPO sign-off is required by the single-user-incident threshold (frontmatter
`requires_cpo_signoff: true`).

## Infrastructure (IaC)

Skip — pure code change against already-provisioned surfaces (`apps/web-platform/server/**` +
test). No new server, secret, vendor, cron, DNS, or persistent runtime process. No migration
(the RPC + tables already exist; this is a TS-layer workspace-derivation fix).

## Observability

```yaml
liveness_signal:
  what: "byok-resolver userHasEffectiveByokKey / userHasPendingByokDelegation invocation rate on the effective-status route"
  cadence: "per dashboard load by a keyless/shared member"
  alert_target: "Sentry (existing reportSilentFallback mirror, feature: byok-resolver)"
  configured_in: "apps/web-platform/server/byok-resolver.ts reportSilentFallback calls (already present)"
error_reporting:
  destination: "Sentry via reportSilentFallback (feature: byok-resolver / workspace-resolver)"
  fail_loud: "resolver errors are Sentry-mirrored AND fail closed (banner shows / lease falls back); never silent-swallowed"
failure_modes:
  - mode: "resolveCurrentWorkspaceId query error"
    detection: "Sentry op=resolveCurrentWorkspaceId (workspace-resolver.ts:212)"
    alert_route: "Sentry feature=workspace-resolver"
  - mode: "resolve_byok_key_owner RPC error in userHasEffectiveByokKey"
    detection: "Sentry op=userHasEffectiveByokKey (byok-resolver.ts:250)"
    alert_route: "Sentry feature=byok-resolver"
  - mode: "effective-status route non-200 (banner hidden from keyless user)"
    detection: "client reportSilentFallback op=effective-status-non-ok (no-api-key-banner.tsx:34)"
    alert_route: "Sentry feature=no-api-key-banner"
logs:
  where: "Sentry breadcrumbs + pino child logger 'byok-resolver' (stdout, shipped via existing pipeline)"
  retention: "per existing Sentry retention"
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/byok-resolver-delegation-workspace.test.ts"
  expected_output: "all assertions pass — current-workspace derivation + accepted→true + unaccepted→pending"
```

## Open Code-Review Overlap

2 open code-review issues touch `cc-dispatcher.ts`, which this plan only edits to update a
stale N2 comment (no logic change):

- **#3242** (review: tool_use WS event lacks raw name field for agent consumers) — **Acknowledge.**
  Different concern (WS `tool_use` event shape), unrelated to BYOK workspace derivation. Not folded in.
- **#3243** (arch: decompose cc-dispatcher.ts into focused modules) — **Acknowledge.** A large
  standalone refactor; this fix's only `cc-dispatcher.ts` touch is a comment update, which does not
  conflict with or pre-empt the decomposition. Not folded in.

No overlap with `byok-resolver.ts` / `workspace-resolver.ts` / `no-api-key-banner.tsx` /
`byok-delegation-ui-resolver.ts` (the files carrying the actual fix).

## Research Insights (deepen-plan 2026-06-01)

### Precedent-Diff Gate (Phase 4.4) — pattern is NOT novel

`resolveCurrentWorkspaceId` is the established canonical active-workspace resolver. Verified
sibling call sites use the identical shape:

- `apps/web-platform/server/current-repo-url.ts:49`: `workspaceId ?? (await resolveCurrentWorkspaceId(userId, tenant))`
- `apps/web-platform/server/resolve-installation-id.ts:37`: same shape.
- `apps/web-platform/server/messages/insert-draft-card.ts:14`: comment documents it as "the
  session-SELECTED workspace".
- `resolveActiveWorkspaceKbRoot` (`workspace-resolver.ts:276`) uses it as the entry resolver.

The BYOK resolver (`byok-resolver.ts`) is the documented outlier still on
`getDefaultWorkspaceForUser` (`MIN(created_at)`) under the stale N2 solo assumption. The fix
brings it in line with the precedent — no novel pattern.

### Verify-the-Negative Pass (Phase 4.45) — security claims CONFIRMED

- Plan claim: "`resolveCurrentWorkspaceId` fails closed to the caller's own solo workspace — never
  a sibling." **Confirmed** at `workspace-resolver.ts:215` (`return userId; // fail to solo
  workspace, never a sibling`) and `:217` (`?? userId`). The IDOR/cross-tenant invariant holds.
- Plan claim: "this fix must NOT widen the read surface." **Confirmed** — the swap changes only
  *which* of the caller's own workspaces is used (active vs oldest); both are the caller's own,
  scoped by `.eq("user_id", userId)`. No new table/row class is read.

### Service-client compatibility (no auth.uid() dependency)

`byok-resolver.ts` uses `createServiceClient()` (lines 124/220/272/327), whereas the precedent
callers (`current-repo-url`, `resolve-installation-id`) pass a **tenant** client.
`resolveCurrentWorkspaceId` reads `user_session_state` filtered by an explicit
`.eq("user_id", userId)` — it does NOT rely on RLS `auth.uid()` for correctness (RLS is an
additional gate, not the scope source). It therefore behaves identically under a service client
(RLS bypassed, but the explicit self-scope still pins the row). **No regression** from the
client-type difference; pass the existing `supabase` service client through unchanged.

### Test Compatibility — MUST update these (enumerated, not sampled)

Two existing server tests directly pin the OLD `getDefaultWorkspaceForUser` derivation and WILL
break at GREEN; both must be updated in the same PR (they assert the behavior being changed):

- **`apps/web-platform/test/server/byok-effective-key.test.ts`** — mocks
  `getDefaultWorkspaceForUser` (lines 55-56, default at 117) and has an explicit test
  **"uses the SAME getDefaultWorkspaceForUser the lease uses (parity)"** (line 168). Rewrite to
  mock + assert `resolveCurrentWorkspaceId`; rename the parity test to assert current-workspace
  parity between the effective-key check and the lease. The shared+accepted / shared+unaccepted /
  pending assertions (lines 199-221, via `mockResolveGranteeAcceptanceStatus`) stay — only the
  workspace-source mock changes.
- **`apps/web-platform/test/server/byok-resolver-fail-closed.test.ts`** — mocks
  `getDefaultWorkspaceForUser` on BOTH the relative and `@/`-aliased module paths (lines 42-46).
  Switch both to `resolveCurrentWorkspaceId`. **Note the semantic shift:** the old fail-closed
  test injected a `getDefaultWorkspaceForUser` *throw* (integrity violation) to exercise the
  outer catch; `resolveCurrentWorkspaceId` never throws (it Sentry-mirrors then returns the solo
  `userId`). The fail-closed scenario must be re-expressed as "resolver degrades to the solo
  workspace → no delegation found → `onErrorReturn` direction is honored" (status endpoint:
  `false`; redirect gate: `true`). This is the Sharp Edge made concrete.

Insulated (NO change needed — they mock `userHasEffectiveByokKey` directly, not the workspace fn):

- `apps/web-platform/test/app/auth/callback-setup-key-gate.test.ts:36`
- `apps/web-platform/test/accept-terms-redirect-to.test.ts:24`
- `apps/web-platform/test/api-byok-effective-status-route.test.ts` (mocks the resolver helpers).

These confirm a **third consumer** of `userHasEffectiveByokKey`: the onboarding redirect gates
(callback, accept-terms) call it with `onErrorReturn:true` (fail-OPEN — never trap a possibly-
delegated user at /setup-key). Sanity check at /work: with the workspace fix, an accepted member
correctly resolves `true` and is NOT redirected to /setup-key; a degraded resolve still
fail-opens (safe). No behavior change required there beyond confirming the gate still passes.

### Post-edit self-audit (Phase 4.45) — no dropped-symbol references

This fix drops no tables/columns/modules (pure derivation swap). Grep of the plan body for
`getDefaultWorkspaceForUser` shows it now appears only in: the call-graph (as the WRONG value),
Files-to-Edit (as the symbol to replace), AC1 (as the symbol that must be absent), and this
Research Insights section (as the test mock to switch) — all intentional. No stale references.

## Alternative Approaches Considered

| Approach | Why not |
| --- | --- |
| Relax/remove the mig-084 acceptance gate so a shared grant counts as effective immediately | Wrong — defeats the consent gate (Art. 7 / #4232 / #083). The correct UX for shared-but-unaccepted is the one-click "Accept" branch, which already exists. |
| Add a workspace-agnostic `byok_delegations WHERE grantee = caller` lookup (drop `workspace_id` filter) | Widens the read surface and breaks tenant scoping — a member in multiple orgs could resolve a delegation from a workspace they are not currently acting in. Rejected for cross-tenant safety. |
| Fix only the banner (`resolveByokDelegationContext`), leave the runtime lease on `getDefaultWorkspaceForUser` | Cosmetic only — banner disappears but task runs still fail to find the delegation. Both consumers must move together (in-scope). |
| Introduce a brand-new "resolve workspace where a delegation to this user lives" query | Reinventing `resolveCurrentWorkspaceId`, which is the canonical active-workspace resolver already used by every other ADR-044 read path. Prefer reuse. |
