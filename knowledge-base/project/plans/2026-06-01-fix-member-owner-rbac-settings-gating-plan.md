---
title: "fix: Member vs Owner RBAC — gate owner-only actions in Settings UI"
date: 2026-06-01
type: fix
status: draft
branch: feat-one-shot-member-owner-rbac-permissions
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
labels: [bug, type/security, domain/engineering, priority/p1-high]
---

# 🐛 fix: Member vs Owner RBAC — gate owner-only actions in the Settings UI

## Enhancement Summary

**Deepened on:** 2026-06-01
**Sections enhanced:** Overview, Research Reconciliation, Acceptance Criteria (AC5/AC6 tightened), Implementation Phases, Precedent Diff (new)
**Research method:** Direct grep/Read verification (Task subagents unavailable in this
environment; per-section research agents and multi-agent review substituted with
deterministic codebase probes).

### Key Improvements

1. **All cited file:line references verified live** against the worktree
   (`team/page.tsx:34-36/:68`, `team-membership-list.tsx:195/:207-213`,
   `invite-member/route.ts:63-66`, `remove-member/route.ts:54-57`,
   `delegation-toggle.tsx:52`, `vitest.config.ts:60`) — all accurate.
2. **AC6 negative claim proven:** `git grep -nw inviteWorkspaceMember` (excl. tests +
   definition) returns **zero** production callers → the legacy direct-RPC invite path
   is confirmed dead code; the real path is `createWorkspaceInvitation` (which DOES pass
   `p_caller_user_id`). Recorded as a confirmed finding, not a hypothesis.
3. **AC5 tightened** to avoid a brittle aggregate: `invite-member/route.ts` legitimately
   contains TWO `role !== "owner"` occurrences (caller-owner gate at `:64` + body role
   validation `role !== "owner" && role !== "member"` at `:52`). AC5 now asserts the
   caller-owner gate line in each route is unchanged, not a raw count.
4. **Precedent-diff added** — the `isOwner` gating convention has 3 in-repo precedents to
   copy verbatim.

### New Considerations Discovered

- The 403 client UX is poor (`window.alert("Failed …")` / `console.error`) — but since
  Members will no longer reach those buttons after this fix, improving the alert copy is
  explicitly out of scope (no Member path reaches it).
- The empty-state CTA ("Invite a teammate …", `team/page.tsx:87-92`) is shown to solo
  Members too — folded into Phase 2 as an optional `isOwner` gate.

## Overview

**Reported symptom:** Member `jean.deruelle@gmail.com` appears to have the same
access as Owner `ops@jikigai.com`. Roles should differ, especially in Settings —
a Member must not be able to perform owner-only actions (invite/remove members,
change roles, transfer/own billing, delete the workspace).

**Investigation result (what is actually true in the codebase):**

The server/API and database layers **already enforce owner-only gating** for every
workspace-scoped mutation. The defect is **UI-only**: two owner-only controls in the
Team settings page are rendered to **all** members regardless of role, contradicting
the established `isOwner` gating convention the rest of the page already follows. The
API rejects a Member's attempt with `403 not_owner`, so this is **not** a privilege-
escalation hole — it is a confusing, broken UX that surfaces buttons a Member cannot
use, which reads to the operator as "Member has Owner access."

Two concrete UI gaps:

1. **`InviteMemberAction` ("+ Invite member" button)** is rendered unconditionally in
   `app/(dashboard)/dashboard/settings/team/page.tsx:68` — shown to Members. (The
   `invite-member` API route gates on owner at `route.ts:63-66`, and the
   `create_workspace_invitation` RPC re-checks `caller_not_owner`.)
2. **"Remove member" menu item** in `components/settings/team-membership-list.tsx:207-213`
   is rendered for every non-self row whenever the kebab menu is open — it is **not**
   wrapped in `isOwner`, unlike the sibling "Transfer ownership" item at `:195`. (The
   `remove-member` API route gates on owner at `route.ts:54-57`, and the
   `remove_workspace_member` RPC re-checks ownership.)

Everything else the report worries about is already correct:

- **Billing** (`settings/billing/page.tsx`), **Integrations/services**
  (`settings/services/page.tsx`), **Scope Grants** (`settings/scope-grants/page.tsx`),
  and **account delete** (`api/account/delete/route.ts`) are all keyed to the
  individual `user.id` / `founder_id` — they are **personal-scoped**, not
  workspace-scoped. A Member managing *their own* billing/integrations/grants and
  deleting *their own* account is correct behavior, not an RBAC bug. (See Research
  Reconciliation for the billing copy-vs-implementation conflict.)
- **Transfer ownership** (UI + route + RPC), **Cancel pending invite** (UI + route),
  **BYOK delegation toggle** (UI + route), and **remove/invite API routes** are all
  owner-gated correctly today.
- **"Delete the workspace"** as a distinct destructive action **does not exist** today
  — there is only personal account delete. There is nothing to gate; building a
  workspace-delete action is out of scope (see Non-Goals).
- **"Change roles"** UI **does not exist** today: `updateWorkspaceMemberRole`
  (`server/workspace-membership.ts:179`) is implemented and the
  `update_workspace_member_role` RPC (migration 067) is owner-gated, but **no API
  route and no UI wires it**. Adding role-change UI is out of scope (see Non-Goals);
  this plan only ensures no *unguarded* role-change surface is introduced.

**Fix shape:** thread `isOwner` (already resolved in `team/page.tsx:34-36`) to the two
ungated controls and short-circuit-hide them for Members, matching the existing
convention used by `PendingInvitesList`, `DelegationToggle`, and the "Transfer
ownership" item. Add the missing `isOwner={false}` test coverage that would have
caught this. Keep the server 403s as defense-in-depth (do not remove them).

This is a **single-domain UI fix on a flag-gated surface** (Team settings only renders
when `TEAM_WORKSPACE_INVITE` is enabled). It is **not** the multi-player RBAC system
tracked at roadmap CP5 / #4670 (P3, not started) and must not expand into it.

## Research Reconciliation — Spec vs. Codebase

| Claim (from report / surrounding code) | Reality in codebase | Plan response |
| --- | --- | --- |
| "Member has the same *access* as Owner" | Server/API/RLS gate every workspace mutation on `role='owner'`; Member gets `403 not_owner`. Access is NOT equal — the **UI** mistakenly *shows* two owner-only buttons. | Fix the two UI surfaces; keep server gates. Frame as UX/visibility fix, not escalation. |
| "Member can perform billing actions" (owner-only) | `settings/billing/page.tsx:30` sets `workspaceId = user.id` and reads `subscription_status` from the caller's **own** `users` row — billing is **per-user/personal**. | No billing gating change. Billing is not workspace-owned today. |
| Team page copy: "All members share the same … **billing**" (`team/page.tsx:56-58`, `:90`) | Contradicts the per-user billing implementation above. Copy implies workspace-shared billing that the code does not implement. | **Surface as a key decision / open question** (see Decisions). Default: treat billing as personal (matches code); flag the misleading copy as a 1-line copy fix candidate, but DO NOT change billing scoping. |
| "Member can delete the workspace" | No workspace-delete action exists; only `api/account/delete` (personal, self-scoped). | Nothing to gate. Out of scope to build. |
| "Member can change roles" | `updateWorkspaceMemberRole` + RPC exist and are owner-gated, but **no route/UI invokes them** (dead-ish code). | Out of scope to wire up. Verify no unguarded role-change surface is added. |
| `inviteWorkspaceMember` (`workspace-membership.ts:79`) calls `invite_workspace_member` RPC **without** a caller param under service role (auth.uid()=NULL) | This function is **not the path the API uses** — the route calls `createWorkspaceInvitation` (`workspace-invitations.ts:153`) which **does** pass `p_caller_user_id` and the RPC enforces `caller_not_owner`. `inviteWorkspaceMember` appears to be a legacy/unused direct-RPC path. | **Verify via grep** whether `inviteWorkspaceMember` has any production caller; if it is unused, note it as a latent gap (a future caller would bypass owner-check) and add a scope-out/follow-up. Do NOT silently rely on it. |

## User-Brand Impact

**User roles this diff touches** (per learning `2026-05-06-user-impact-section-by-role-not-surface.md`):

- **Authenticated app user — Member role** (primary): sees owner-only buttons they
  cannot use.
- **Authenticated app user — Owner role**: must retain full control (regression risk —
  do not over-gate and hide controls from owners).

**If this lands broken, the user experiences:** a Member clicks "+ Invite member" or
"Remove member", the request 403s, and they see a generic `window.alert("Failed …")`
or a silently-failing modal — eroding trust that roles mean anything. Conversely, an
over-gating regression would hide invite/remove from a legitimate **Owner**, breaking
team management entirely.

**If this leaks, the user's workflow/data is exposed via:** no new data-exposure vector
is introduced — the server already rejects the mutation. The brand exposure is
*perceived* unequal access (a teammate believing they can remove a colleague), which at
the solo-founder-with-one-collaborator ICP is a **single-user incident** class trust
breach (the operator's first teammate experience).

**Brand-survival threshold:** single-user incident.

`requires_cpo_signoff: true` — CPO sign-off required at plan time before `/work` begins
(Phase 2.5 carry-forward or confirm CPO reviewed). `user-impact-reviewer` runs at
review time per the review skill's conditional-agent block.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (invite gate):** In `team/page.tsx`, the `<InviteMemberAction>` trigger is
  rendered only when the current user `isOwner`. Verified: render the Team page server
  component path / component with a Member identity → "+ Invite member" button absent;
  with Owner → present. (`grep -n "InviteMemberAction" app/(dashboard)/dashboard/settings/team/page.tsx` shows it wrapped in an `isOwner &&` guard or receives an `isOwner` prop that self-hides.)
- [ ] **AC2 (remove gate):** In `team-membership-list.tsx`, the "Remove member" `<button>`
  (`:207-213`) is wrapped in `{isOwner && (...)}`, matching the sibling "Transfer
  ownership" guard. Verified by a new RTL test: `render(<TeamMembershipList ... isOwner={false} />)` then open a non-self row's kebab → **no** "Remove member" and **no** "Transfer ownership" item present; with `isOwner={true}` both present (preserve existing `:78` test).
- [ ] **AC3 (kebab empty-for-member):** When `isOwner={false}`, a non-self member row's
  kebab menu, if it renders at all, contains zero owner-only actions. Decision in
  Decisions: hide the kebab trigger entirely for Members (cleaner) — assert the
  `aria-label="Row actions for …"` button is absent when `isOwner={false}` and the row
  is non-self.
- [ ] **AC4 (no over-gating regression — Owner):** Existing `isOwner={true}` tests in
  `test/team-membership-list.test.tsx` (`:78` "non-self row exposes kebab menu with
  Remove action", `:64` AC-FLOW4 self-row no-kebab) still pass unchanged; Owner sees
  invite + remove + transfer.
- [ ] **AC5 (server gates intact):** The caller-owner gate
  (`if (!callerRow || callerRow.role !== "owner") return 403`) is preserved verbatim in
  `invite-member/route.ts:63-66`, `remove-member/route.ts:54-57`,
  `transfer-ownership/route.ts:61-63`, `cancel-invite/route.ts:56-58`, and the
  membership gate in `delegations/route.ts:75-76`. **Note:** `invite-member/route.ts`
  contains TWO `role !== "owner"` matches (the caller gate AND the body validation
  `role !== "owner" && role !== "member"` at `:52`) — assert the *caller gate line*
  is intact, do NOT rely on a raw `grep -c` count (verified at deepen time). No server
  gate is removed on the theory that the UI now hides the control.
- [ ] **AC6 (latent-path audit — VERIFIED at deepen):** `git grep -nw "inviteWorkspaceMember" apps/web-platform` (excluding `*.test.*` and the `workspace-membership.ts:79` definition) returns **zero** production callers — confirmed dead code at deepen time. Record this finding in the PR body. If `/work` re-runs the grep and finds a NEW caller (introduced since), add the owner-check at that caller (in scope) OR file the follow-up in Non-Goals.
- [ ] **AC7 (tests run under the right runner + path):** New/changed tests live under
  `apps/web-platform/test/**/*.test.tsx` (vitest jsdom project; `vitest.config.ts:60`
  `include: ["test/**/*.test.tsx"]`) — NOT co-located. Run with
  `./node_modules/.bin/vitest run test/team-membership-list.test.tsx` (the package uses
  vitest; `bun test` is blocked by `bunfig.toml`).
- [ ] **AC8 (typecheck):** `npx tsc --noEmit` (or the repo's typecheck script) passes;
  the new `isOwner` prop threading introduces no type errors.

### Post-merge (operator)

- [ ] **AC9:** None required. This is a pure client-component + page change under
  `apps/web-platform/**`; the `web-platform-release.yml` pipeline restarts the container
  on merge to main. No migration, no infra, no Doppler/vendor change.

## Implementation Phases

### Phase 0 — Preconditions (verify before coding)

1. `git grep -n "InviteMemberAction" apps/web-platform/app` — confirm the only render
   site is `team/page.tsx:68` and it currently receives no `isOwner`.
2. `git grep -n "Remove member" apps/web-platform/components/settings/team-membership-list.tsx`
   — confirm the button at `:207-213` is outside any `isOwner` guard.
3. `git grep -n "inviteWorkspaceMember\b" apps/web-platform -- ':!*test*'` — enumerate
   production callers of the legacy direct-RPC invite path (AC6).
4. Read `test/team-membership-list.test.tsx` — confirm all current cases pass
   `isOwner={true}`; identify the insertion point for `isOwner={false}` cases.
5. Confirm vitest jsdom include glob covers `test/team-membership-list.test.tsx`
   (`vitest.config.ts:60`).

### Phase 1 — RED: failing tests for Member gating

In `apps/web-platform/test/team-membership-list.test.tsx`:

- Add `it("Member (isOwner=false): non-self row exposes NO Remove member action")` —
  render with `isOwner={false}`, open the non-self kebab (or assert the kebab trigger is
  absent per AC3), assert no "Remove member" text.
- Add `it("Member (isOwner=false): non-self row exposes NO Transfer ownership action")`
  — already implicitly gated, but lock it.
- (Invite trigger) Add a test for the Team page's invite-button gating. If testing the
  RSC page is awkward, instead make `InviteMemberAction` accept an `isOwner` prop and
  return `null` when false, and unit-test that component directly
  (`test/invite-member-action.test.tsx`, new file under `test/`).

Run: `./node_modules/.bin/vitest run test/team-membership-list.test.tsx test/invite-member-action.test.tsx` → these new cases FAIL (Remove button currently renders for Members; invite button currently always renders).

### Phase 2 — GREEN: gate the two controls

1. **`components/settings/team-membership-list.tsx`** — wrap the "Remove member"
   `<button>` (`:207-213`) in `{isOwner && ( … )}`. Reconsider AC3: if `isOwner` is
   false and the row is non-self, the only remaining menu content is the (already
   owner-gated) transfer + remove — both now gated → the kebab would be empty. Change
   `showActions` to `const showActions = !isCurrentUser && isOwner;` so Members get no
   kebab trigger at all on any row. (This is the cleanest fix and satisfies AC2+AC3
   together.)
2. **`components/settings/invite-member-action.tsx`** — add `isOwner: boolean` to props;
   `if (!isOwner) return null;` at the top (mirrors `delegation-toggle.tsx:52` pattern).
3. **`app/(dashboard)/dashboard/settings/team/page.tsx`** — pass `isOwner={isOwner}` to
   `<InviteMemberAction>` (`isOwner` already computed at `:34-36`). Optionally also gate
   the empty-state "Invite a teammate" CTA copy (`:87-92`) behind `isOwner` so a solo
   Member isn't told to invite (low priority; include if trivial).

Run the full changed-file test set → GREEN. Run `npx tsc --noEmit` → clean.

### Phase 3 — Defense-in-depth verification (no code change expected)

- Re-grep AC5 server gates — confirm untouched.
- Confirm AC6 finding recorded (legacy `inviteWorkspaceMember` caller audit).

### Phase 4 — Optional copy reconciliation (gated by Decision)

- If the team adopts "billing is personal" (default), file/fix the misleading
  "share the same … billing" copy in `team/page.tsx:56-58` and `:90` in the same PR
  (1-line copy edit) OR defer with a tracking issue. Do NOT change billing scoping.

## Files to Edit

- `apps/web-platform/components/settings/team-membership-list.tsx` — gate Remove button / kebab trigger on `isOwner`.
- `apps/web-platform/components/settings/invite-member-action.tsx` — add `isOwner` prop + early `return null`.
- `apps/web-platform/app/(dashboard)/dashboard/settings/team/page.tsx` — pass `isOwner` to `InviteMemberAction`; optional empty-state copy gate.
- `apps/web-platform/test/team-membership-list.test.tsx` — add `isOwner={false}` cases.

## Files to Create

- `apps/web-platform/test/invite-member-action.test.tsx` — unit test that the invite trigger returns `null` for Members and renders for Owners. (Path under `test/` to match the vitest jsdom `*.test.tsx` glob.)

## Open Code-Review Overlap

None. (Run `gh issue list --label code-review --state open --json number,title,body` and grep the edited file paths at /work time; if any match, fold-in or acknowledge per the plan-skill overlap procedure.)

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Pure client-component + RSC page change on a flag-gated surface. No
schema, infra, or new runtime process. The existing `isOwner` convention
(`PendingInvitesList`, `DelegationToggle`, transfer item) is the precedent to follow —
the fix is consistency, not new architecture. Server gates are correct and must remain
as defense-in-depth (do not remove on the theory that "the UI hides it now"). Watch for
the over-gating regression (hiding controls from Owners) — AC4 guards this.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (pipeline / no Task subagents available in this environment)
**Skipped specialists:** ux-design-lead (pipeline — no new page/flow; modifies existing
component visibility only), copywriter (no domain leader recommended one)
**Pencil available:** N/A

#### Findings

Modifies an existing surface (hides two controls for Members); adds no new page,
modal, or flow → ADVISORY, not BLOCKING. The mechanical-escalation check does not fire
(no new file under `components/**/*.tsx` that is a *page/layout* surface; the one new
file is a test). The product question worth a human ack: **should billing be
workspace-shared or personal?** — surfaced as a Decision below for CPO. `requires_cpo_signoff: true` is set because the brand-survival threshold is `single-user incident`.

## Infrastructure (IaC)

Skip — no new infrastructure. Pure code change under `apps/web-platform/**` against an
already-provisioned surface. No server, secret, vendor, cron, or persistent runtime
process introduced.

## Observability

```yaml
liveness_signal:
  what: Existing 403 rate on /api/workspace/{invite-member,remove-member} (server gate already fires)
  cadence: on-request
  alert_target: Sentry (existing reportSilentFallback paths in workspace-membership.ts)
  configured_in: apps/web-platform/server/observability.ts (existing)
error_reporting:
  destination: Sentry via existing reportSilentFallback / route 403 responses
  fail_loud: true (route returns 403 not_owner; client surfaces alert)
failure_modes:
  - mode: Over-gating regression hides invite/remove from a legitimate Owner
    detection: AC4 RTL test (isOwner=true must still show controls) + manual QA as Owner
    alert_route: CI test failure (pre-merge) — no prod telemetry needed
  - mode: Member still sees a control (gate not applied to a surface)
    detection: AC1/AC2/AC3 RTL tests (isOwner=false hides controls)
    alert_route: CI test failure (pre-merge)
logs:
  where: No new logs. Existing route logs/Sentry on 403 unchanged.
  retention: existing
discoverability_test:
  command: ./node_modules/.bin/vitest run test/team-membership-list.test.tsx test/invite-member-action.test.tsx
  expected_output: All tests pass, including new isOwner=false hide-control cases
```

## Non-Goals / Out of Scope (with deferral tracking)

- **Building multi-player RBAC** (per-seat scopes, role matrix, audit trail) — that is
  roadmap CP5 / #4670 (P3, not started). This plan does NOT touch it. No new deferral
  issue needed (already tracked).
- **Wiring a role-change (Member ↔ Owner) UI/route** for `updateWorkspaceMemberRole`.
  The RPC is owner-gated; no unguarded surface exists. **Deferral:** file a follow-up
  issue "Expose owner-gated change-role UI for workspace members" (re-eval when
  TEAM_WORKSPACE_INVITE graduates from flag; milestone Multi-User Readiness) if the
  team wants it; otherwise leave the server fn as-is. Re-eval criteria: a customer asks
  to demote/promote a member.
- **Building a workspace-delete action.** None exists; out of scope.
- **Changing billing scoping** (personal → workspace-shared). The implementation is
  personal today; only a copy mismatch exists. **Deferral:** if billing should become
  workspace-owned + owner-only, that is a product+finance decision (CPO+CFO) and a
  separate plan. File a follow-up "Resolve billing scope: personal vs workspace-shared
  + reconcile Team-page copy" if the Decision below lands as "workspace-shared".
- **Hardening the legacy `inviteWorkspaceMember` direct-RPC path** beyond the AC6 audit.
  If AC6 finds it unused, optionally delete it in this PR (trivial) or file a follow-up
  "Remove unused inviteWorkspaceMember legacy path or pass p_caller_user_id".

## Decisions (need confirmation — see Open Questions)

1. **Billing scope (KEY, needs CPO/CFO):** Is workspace billing intended to be
   **personal-per-user** (matches current code) or **workspace-shared, owner-only**
   (matches the Team-page copy)? **Default for this plan: personal** (no code change;
   fix the copy). If "workspace-shared, owner-only" is the intent, this becomes a
   separate, larger plan.
2. **Member kebab menu:** Hide the kebab trigger entirely for Members (chosen — AC3) vs.
   render an empty/disabled menu. Hiding is cleaner and matches "Members see no
   owner-only affordances."
3. **Empty-state invite CTA copy** for a solo Member — gate behind `isOwner` (low
   priority; include only if trivial).

## Test Scenarios

| Scenario | Role | Expected |
| --- | --- | --- |
| Open Team settings | Owner | "+ Invite member" visible; non-self rows show kebab → Remove + (for non-owner targets) Transfer |
| Open Team settings | Member | "+ Invite member" hidden; non-self rows show NO kebab trigger |
| Pending invites list | Member | Revoke button hidden (already correct — regression-lock) |
| Delegation toggle | Member | Toggle hidden (already correct — regression-lock) |
| API: POST invite-member as Member | Member | 403 `not_owner` (server gate retained) |
| API: POST remove-member as Member | Member | 403 `not_owner` (server gate retained) |

## Precedent Diff (isOwner UI-gating convention)

This fix is **not novel** — it copies an established in-repo convention. The gap exists
only because two controls escaped it. Precedents to mirror verbatim (verified at deepen):

| Precedent (correct today) | Pattern | Apply to (this fix) |
| --- | --- | --- |
| `pending-invites-list.tsx:116` | `{isOwner && (<button>Revoke…</button>)}` — wrap the owner-only button in an `isOwner &&` guard | "Remove member" button (`team-membership-list.tsx:207`) |
| `delegation-toggle.tsx:52` | `if (!isOwner || isSelf) return <span className="w-20" />;` — early-return null/spacer for non-owners | `invite-member-action.tsx` (`if (!isOwner) return null;`) |
| `team-membership-list.tsx:195` | `{isOwner && member.role !== "owner" && (...)}` — "Transfer ownership" already gated (sibling of the ungated Remove button in the SAME menu) | direct sibling — the cleanest fix gates `showActions` so the whole kebab is owner-only |

**Risk if not mirrored:** divergent gating styles (some `return null`, some `&&` wrap,
some spacer) make future audits harder. Mirror the closest sibling per control.

## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| Over-gating hides controls from a legitimate Owner | AC4 pins existing `isOwner={true}` tests; manual QA as Owner |
| Removing server 403 gate "because UI hides it now" | AC5 asserts caller-owner gate lines preserved verbatim |
| New test co-located under `components/**` → silently never run | AC7 + Sharp Edges: tests under `test/**/*.test.tsx` only |
| Future caller of dead `inviteWorkspaceMember` bypasses owner-check | AC6 re-runs the grep at `/work`; follow-up to delete or fix the legacy fn |
| Gating `billing` (report's literal ask) would lock a Member out of their OWN subscription | Decision #1: billing is personal today; do NOT gate without CPO/CFO sign-off |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, placeholder, or omits the
  threshold will fail `deepen-plan` Phase 4.6. (Filled above.)
- **Do NOT remove the server-side `role !== "owner"` 403 checks** when adding UI gating.
  UI gating is cosmetic/UX; the server gate is the real boundary. AC5 locks this.
- **Over-gating is the regression to fear most**, not under-gating: the bug is Members
  *seeing* controls; the worse failure is hiding controls from a legitimate Owner. AC4
  pins the Owner-still-sees-controls invariant against the existing `isOwner={true}`
  tests.
- Tests must live under `test/**/*.test.tsx` (vitest jsdom glob, `vitest.config.ts:60`),
  NOT co-located next to the component — a `components/**/*.test.tsx` file is silently
  never collected. Run via `./node_modules/.bin/vitest run`, never `bun test` (blocked
  by `bunfig.toml`).
- The report says "billing" is an owner-only action; in this codebase billing is
  personal-per-user. Do not gate billing without resolving Decision #1 — gating
  personal billing behind owner would lock a Member out of *their own* subscription.
