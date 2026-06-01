---
date: 2026-06-01
type: fix
branch: feat-one-shot-member-view-404-and-kb-empty
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
related_adrs: [ADR-044, ADR-038]
related_issues: [4543, 4715, 4641]
related_prs: [4745]
related_brainstorms:
  - knowledge-base/project/brainstorms/2026-05-31-invite-accept-membership-byok-brainstorm.md
---

# Fix: post-invite member-view 404 + empty Knowledge Base (member-role data scoping)

## Enhancement Summary

**Deepened on:** 2026-06-01
**Sections enhanced:** Overview (precedent diff), Hypotheses, Risks & Mitigations (new)
**Gates run:** 4.4 precedent-diff, 4.45 verify-the-negative + post-edit self-audit, 4.6
User-Brand Impact (PASS), 4.7 Observability (PASS, 5/5 fields, no SSH), 4.8 PAT-shaped (PASS,
no match). 4.5 network-outage: not triggered (the `503`/`404` references are HTTP-status
contract values, not connectivity symptoms).

### Key Improvements
1. **Verify-the-negative (4.45) confirmed all three security claims against code:**
   (a) `active-repo`/`workspace-resolver` read no `req.body`/`req.query` → workspace id is
   claim-derived (IDOR-safe); (b) `resolveCurrentWorkspaceId` returns `userId` (solo) on null
   claim / error — `workspace-resolver.ts:215,217` — never a sibling; (c)
   `set_current_workspace_id` is `is_workspace_member`-gated (`mig 079:114,276`).
2. **Precedent-diff (4.4):** the canonical active-workspace resolution is
   `active-repo/route.ts:37-71`; the KB read path must mirror it exactly. Diff added to
   Risks & Mitigations.
3. **Verified the load-bearing facts:** `resolve_workspace_installation_id` exists (mig 079);
   vitest `include: ["test/**/*.test.ts", "lib/**/*.test.ts"]` (prescribed path matches);
   `bunfig.toml pathIgnorePatterns=["**"]` (bun test blocked — Sharp Edge correct);
   `chat/page.tsx` confirmed absent (symptom-1 hypothesis (a) is real);
   `organizations.owner_user_id` reachable for Q1 readiness.

### New Considerations Discovered
- `workspace_status` and `workspace_path` did NOT move to `workspaces` in ADR-044 (only the
  5 repo columns). The fs dir is derived purely from the workspace id
  (`workspacePathForWorkspaceId`); readiness must come from the owner's `users` row (Q1).
- The bug spans **four** KB read routes plus the shared helper — a partial sweep leaves a
  member 404ing on file-open while the tree loads.

🐛 **Bug fix** — follow-up to PR #4745 (invite-accept `attestation_id` P0001, merged
into main 2026-06-01). After a member accepts a workspace invite and signs in, the
invited (member-role) workspace renders broken: (1) the default/landing route shows a
404 in the content area below the correct member banner, and (2) Knowledge Base renders
the "No Project Connected" empty state even though the workspace's repo is connected.

## Overview

Both symptoms share **one root cause**: ADR-044 (#4543, active 2026-05-28) relocated
repo-connection state from `users` → `workspaces` and added active-workspace resolution
(`current_workspace_id` in `user_session_state`, JWT claim, `set_current_workspace_id`
RPC, and the `resolveCurrentWorkspaceId` / `workspacePathForWorkspaceId` server helpers).
The `/api/workspace/active-repo` route was cut over correctly (it reads `workspaces`,
never `users.repo_url`). **But the KB read path and the dashboard landing repo-hint were
never cut over** — they still read `users.workspace_path` / `users.repo_status` /
`users.repo_url` keyed to the *caller's own* `user.id`. For a member viewing a workspace
they do not own, those reads resolve to the member's empty **solo** row, producing 404s
and empty states.

This is precisely the un-swept-consumer class ADR-044's decommission drift-gate warns
about, and the "scope-by-new-column: audit EVERY query, not just the helper" hard rule
(`hr-write-boundary-sentinel-sweep-all-write-sites` / learning
`2026-04-22-scope-by-new-column-audit-every-query-not-just-the-helper.md`).

The fix: make the KB read path active-workspace-aware (resolve `current_workspace_id`,
read the KB from `workspacePathForWorkspaceId(activeWorkspaceId)`, gate connectivity on
the **active workspace's** `workspaces.repo_status`), and make the dashboard landing
repo-hint read the active workspace's repo. **No migration. No new schema.** The
membership-checked read-access already exists (a member is a `workspace_members` row in
the active workspace; the filesystem dir is `<WORKSPACES_ROOT>/<workspace_id>`). The
existing "tasks need an API key" read-only constraint for members is **untouched** — it
is enforced at chat-time via BYOK key resolution, orthogonal to KB *viewing*.

### Confirmed evidence (read at plan time)

| File:line | Current (buggy) read | Effect for a member |
|---|---|---|
| `apps/web-platform/app/api/kb/tree/route.ts:13-20` | `users.workspace_path, repo_status` for `user.id`; `repo_status === "not_connected"` → **404** | KB layout → `NoProjectState` (symptom 2) |
| `apps/web-platform/app/api/kb/content/[...path]/route.ts:34-54, 108-113` | `users.workspace_path` for `user.id` → 404 / wrong dir | opening any file 404s |
| `apps/web-platform/app/api/kb/file/[...path]/route.ts:~60-68, ~300-310` | `users.workspace_path` for `user.id` | raw file fetch wrong dir |
| `apps/web-platform/app/api/kb/search/route.ts:12-36` | `users.workspace_path` for `user.id` → 404 | search empty/404 |
| `apps/web-platform/server/kb-route-helpers.ts:90-131, 207-274` | `authenticateAndResolveKbPath` / `resolveUserKbRoot` read `users.workspace_path,repo_url` for `user.id` | shared resolver; all its consumers |
| `apps/web-platform/app/(dashboard)/dashboard/page.tsx:223-238` | `users.repo_url` for `auth.user.id` + `conversations.user_id` (repo-disconnected hint) | "No repo connected" landing (symptom 1) |
| `apps/web-platform/app/api/kb/sync/route.ts:77-121` | `users.workspace_path, github_installation_id` for `userId` | member cannot sync the shared repo (#4543 residual) |

Correct precedent (already cut over): `apps/web-platform/app/api/workspace/active-repo/route.ts:37-71`
— resolves `user_session_state.current_workspace_id` (→ solo fallback) then reads
`workspaces.repo_url, repo_status`. The fix replicates this pattern into the KB path.

Available helpers (already shipped, `apps/web-platform/server/workspace-resolver.ts`):
- `resolveCurrentWorkspaceId(userId, supabase)` (line 190) → active workspace id; null claim → solo (`= userId`); never a sibling.
- `workspacePathForWorkspaceId(workspaceId)` (line 361) → `<WORKSPACES_ROOT>/<workspace_id>` (filesystem dir; for solo == legacy `<root>/<userId>`). Doc explicitly: "no `users.workspace_path` lookup."
- `getCurrentWorkspaceId` (client-safe, re-exported) for the dashboard client page.

## Research Reconciliation — Spec vs. Codebase

| Claim (from ARGUMENTS / mental model) | Reality (verified) | Plan response |
|---|---|---|
| "Likely RLS policies that only match the owner" | Not RLS-on-`workspaces`. The KB read path is a **filesystem** read gated by an *application-layer* `users.*`-for-caller query, not a Postgres RLS predicate. `conversations` IS workspace-keyed RLS (mig 059) and works. | Fix the application-layer query scoping, not RLS. |
| "members get no project/KB rows" | KB is not a DB row set — it's files under `<WORKSPACES_ROOT>/<workspace_id>/knowledge-base`. The 404 is the route's `users.repo_status='not_connected'` gate + wrong `workspace_path`. | Resolve active workspace id; read fs at `workspacePathForWorkspaceId(activeWsId)`; gate on `workspaces.repo_status`. |
| "post-invite redirect target 404s" | `(auth)/callback/route.ts` + `accept-terms/route.ts` already land the member on `/dashboard` (or `/invite/<token>`), NOT a 404 route (redirect-precedence fix already in main, #4715). | Symptom-1 404 is the *content rendered* on `/dashboard` for a member with the **solo** workspace active (claim unset → "No repo connected"), not a redirect bug. See Hypotheses + AC-Repro. |
| `workspace_path` moved to `workspaces` | **No.** ADR-044 moved only repo columns (`repo_url, repo_provider, github_installation_id, repo_status, repo_last_synced_at`). `workspace_path` + `workspace_status` remain on `users`. | Do NOT read a member's `users.workspace_path`. Derive the fs dir from the active workspace id via `workspacePathForWorkspaceId`. `workspace_status` readiness: see Open Question Q1. |

## User-Brand Impact

**If this lands broken, the user experiences:** an invited collaborator (the literal
scenario the team-workspace feature exists for) signs in, switches to the shared
workspace, and the product is non-functional — a 404 on the home screen and an empty
Knowledge Base for a repo that is visibly connected. The invitation promise ("All members
share the same workspace data, agents, and billing") is broken on first use.

**If this leaks, the user's data/workflow is exposed via:** the fix widens a member's
**read** access to a workspace they belong to. The exposure vector to guard is reading the
**wrong** workspace (a sibling the user is NOT a member of). Mitigation: workspace id is
**claim-derived** (`current_workspace_id` from `user_session_state`, never from
`req.body`/`req.query`) and falls back to the caller's solo workspace on a null/absent
claim — never an arbitrary sibling (ADR-044 §Decision.3, IDOR guard). The member is
verified as a `workspace_members` row before the claim can be set (`set_current_workspace_id`
RPC is membership-checked). No credential (`github_installation_id`) is read on the KB
*view* path — that stays behind the `resolve_workspace_installation_id` definer RPC.

**Brand-survival threshold:** single-user incident.

> Carried forward from `2026-05-31-invite-accept-membership-byok-brainstorm.md`
> (`user_brand_critical: true`, `requires_cpo_signoff: true`). CPO sign-off required at
> plan time before `/work`; `user-impact-reviewer` runs at review-time.

## Hypotheses

**Symptom 2 (KB empty) — HIGH confidence, fully traced:**
`useKbLayoutState` (`hooks/use-kb-layout-state.tsx:71`) → `GET /api/kb/tree` →
route reads `users.repo_status` for the member's own id = `'not_connected'` →
**404** → hook sets `error = "not-found"` (`use-kb-layout-state.tsx:82-85`) →
`kb/layout.tsx:53` renders `<NoProjectState />`. Confirmed by direct file reads. The
`live-repo-badge` shows the repo because `active-repo` is already active-workspace-aware;
the tree route is not. Single root cause.

**Symptom 1 (landing 404 + "No repo connected") — HIGH confidence on cause class,
MEDIUM on exact 404'd route element:**
The member-role workspace is active (or, immediately post-accept, the solo workspace is
active because `current_workspace_id` is unset → "No repo connected"). `dashboard/page.tsx`
fetches `/api/kb/tree`; a 404 is swallowed ("fall through to Command Center", line 153-155)
so the *page itself* does not `notFound()`. Candidate exact sources of the literal "This
page could not be found":
  (a) member lands/navigates to `/dashboard/chat` — there is **no `chat/page.tsx`** (only
      `chat/layout.tsx` + `chat/[conversationId]/page.tsx`), so the bare segment 404s in
      App Router. The `NoApiKeyBanner` `pending` CTA links to bare `/dashboard/chat`
      (`no-api-key-banner.tsx:92`, asserted by `test/components/no-api-key-banner.test.tsx:54`).
  (b) the dashboard landing renders the solo/empty experience (data scoped to the empty
      member row), which reads as "broken/404-like" below the banner.
**Phase 0 MUST reproduce with Playwright to pin (a) vs (b) before writing the fix for
symptom 1.** If (a), add a `chat/page.tsx` redirect-stub (or fix the CTA target); if (b),
the active-workspace data-scoping fix resolves it. Do not guess — see AC5 + Phase 0.

## Risks & Mitigations

### Precedent diff (Phase 4.4) — active-workspace resolution is NOT novel

The fix adopts an **already-canonical** pattern. Side-by-side:

```ts
// PRECEDENT (correct): app/api/workspace/active-repo/route.ts:37-71
const { data: sessionState } = await service
  .from("user_session_state").select("current_workspace_id")
  .eq("user_id", userId).maybeSingle();
let activeWorkspaceId = (sessionState?.current_workspace_id ?? null) ?? soloWorkspaceId; // soloWorkspaceId = userId
// J5 self-heal: if non-solo claim but no membership → reset to solo
const { data: ws } = await service.from("workspaces")
  .select("repo_url, repo_status").eq("id", activeWorkspaceId).maybeSingle();

// CURRENT (buggy): app/api/kb/tree/route.ts:13-20
const { data: userData } = await serviceClient.from("users")
  .select("workspace_path, workspace_status, repo_status, ...").eq("id", user.id).single();
if (... userData.repo_status === "not_connected") return 404;  // member's own row → always 404
```

The KB path should resolve `activeWsId` via the shared `resolveCurrentWorkspaceId(userId, tenant)`
helper (which already encapsulates the claim→solo fallback at `workspace-resolver.ts:190-218`),
then read the fs at `workspacePathForWorkspaceId(activeWsId)` and gate on `workspaces.repo_status`.
**No novel pattern.** The only net-new logic is the Q1 readiness resolution (owner's
`users.workspace_status`).

### Risk: partial sweep

`kb-route-helpers.ts` is the shared resolver, but `tree`/`content`/`search` query `users`
**inline** (not via the helper). Fixing only the helper leaves them broken. Mitigation: AC2
grep gate over `apps/web-platform/app/api/kb/` + Playwright file-open on all four routes.

### Risk: cross-tenant read

A wrong fallback (sibling instead of solo) is a cross-tenant read at `single-user incident`
threshold. Mitigation: verified the resolver fails to `userId` (solo), never a sibling
(workspace-resolver.ts:215,217); unit-tested in AC3.

### Risk: readiness signal for a member (Q1)

A member has no `workspace_status` for the owner's workspace on their own row. Mitigation:
resolve owner via `organizations.owner_user_id` (reachable: `workspaces.organization_id →
organizations.owner_user_id`, mig 053:51,70) and read the owner's `users.workspace_status`,
OR treat fs existence as readiness. Decide in Phase 0. Either preserves the existing
503-provisioning UX contract the client hook discriminates.

## Files to Edit

- `apps/web-platform/app/api/kb/tree/route.ts` — resolve active workspace; read fs at
  `workspacePathForWorkspaceId(activeWsId)`; gate connectivity on the active workspace's
  `workspaces.repo_status` (not `users.repo_status`).
- `apps/web-platform/app/api/kb/content/[...path]/route.ts` — same active-workspace resolution (both handlers; lines ~34 and ~108).
- `apps/web-platform/app/api/kb/file/[...path]/route.ts` — same (both read sites, ~60-68 and ~300-310).
- `apps/web-platform/app/api/kb/search/route.ts` — same (~12-36).
- `apps/web-platform/server/kb-route-helpers.ts` — make `authenticateAndResolveKbPath` +
  `resolveUserKbRoot` active-workspace-aware (the shared locus; the inline-querying routes
  above should ideally be refactored to call the helper, but at minimum each must adopt the
  same resolution — sweep, do not assume the helper covers them).
- `apps/web-platform/app/(dashboard)/dashboard/page.tsx` — repo-disconnected hint
  (lines 217-243) reads the **active workspace's** repo via `/api/workspace/active-repo`
  (already exists) instead of `users.repo_url` for `auth.user.id`; reconcile the
  KB-tree-404 "fall through" branch (line 153-155) so a member with a connected active
  workspace is NOT mis-routed to the first-run/solo experience.
- `apps/web-platform/app/api/kb/sync/route.ts` — member-initiated sync must target the
  active workspace's repo (resolve installation via the active workspace, fs path via
  `workspacePathForWorkspaceId`). **Scope decision in Q2 below** — sync is a *write/refresh*
  path with the `github_installation_id` credential boundary; may be split to a follow-up.

## Files to Create

- (conditional) `apps/web-platform/app/(dashboard)/dashboard/chat/page.tsx` — route stub
  (redirect to `/dashboard` or first/most-recent conversation) so bare `/dashboard/chat`
  does not 404. **Only if Phase 0 repro confirms hypothesis (a).** New file under
  `app/**/page.tsx` would mechanically escalate the UX gate to BLOCKING — but a pure
  redirect stub (no rendered surface) is not a designed page; if added, note it as a
  redirect stub in the PR and re-confirm tier.
- `apps/web-platform/test/server/kb-active-workspace-scoping.test.ts` — RED→GREEN unit
  tests for the active-workspace resolution in the KB read path (member resolves the
  owner's workspace dir; null claim → solo; non-member sibling claim → solo fallback, never
  the sibling).
- Learning file at GREEN: `knowledge-base/project/learnings/bug-fixes/<topic>.md`
  (date chosen at write-time per Sharp Edges).

## Open Questions (resolve in Phase 0)

- **Q1 — `workspace_status` readiness for a member.** `workspace_status` ("ready") lives on
  `users` keyed to the owner. A member has no readiness signal for the *owner's* workspace.
  Options: (i) resolve the owner via `organizations.owner_user_id` (the workspace's org)
  and read the owner's `users.workspace_status`; (ii) treat filesystem existence of
  `<WORKSPACES_ROOT>/<workspace_id>/knowledge-base` as readiness (the dir is provisioned at
  workspace creation). Prefer (i) for parity with the existing 503 "provisioning" UX;
  confirmed reachable: `workspaces.organization_id → organizations.owner_user_id`
  (mig 053:51,70).
- **Q2 — KB sync (write/refresh) scope.** The brainstorm Decision #3 says "do NOT steer
  invitees through connect-repo / repo repoint." Member-initiated *manual sync* of an
  already-connected shared repo is a different action (refresh, not repoint), but it crosses
  the `github_installation_id` credential boundary (must use
  `resolve_workspace_installation_id` definer RPC, ADR-044 §Decision.2). Decide in Phase 0
  whether sync ships in this PR or as an immediate follow-up issue. KB *viewing* (this PR's
  core) does not touch the credential and ships regardless.
- **Q3 — symptom-1 exact 404 element** (see Hypotheses) — Playwright repro.

## Implementation Phases

1. **Phase 0 — Reproduce & resolve open questions (no code).**
   - Playwright: sign in as a member of a shared workspace (or synthesize the session
     state), switch to the member workspace, capture the landing-route 404 element and the
     KB `NoProjectState`. Pin symptom-1 hypothesis (a) vs (b). Capture network: confirm
     `/api/kb/tree` returns 404 and `/api/workspace/active-repo` returns the repo.
   - Resolve Q1 (readiness source) and Q2 (sync scope) by reading
     `resolve_workspace_installation_id` RPC signature + `organizations.owner_user_id` join.
   - **Precedent diff:** `git show` the `active-repo` route as the canonical active-workspace
     resolution; the KB routes must mirror it (claim → solo fallback; never sibling).
   - **Run `/soleur:gdpr-gate`** against this plan + the route diffs (see GDPR gate below).
2. **Phase 1 — RED.** Write `kb-active-workspace-scoping.test.ts`: member-with-claim resolves
   owner's workspace dir; null claim → solo; sibling-claim-without-membership → solo (J5
   self-heal parity). Tests fail against current `users`-scoped reads.
3. **Phase 2 — GREEN (KB read path).** Cut over `kb/tree`, `kb/content`, `kb/file`,
   `kb/search`, and `kb-route-helpers` to: `activeWsId = resolveCurrentWorkspaceId(userId, tenant)`
   → fs root `path.join(workspacePathForWorkspaceId(activeWsId), "knowledge-base")` → gate on
   the active workspace's `workspaces.repo_status` + readiness (Q1). Preserve the 503/404/200
   status contract the client hook (`use-kb-layout-state.tsx:73-91`) already discriminates.
4. **Phase 3 — GREEN (dashboard landing).** Repoint the repo-disconnected hint to
   `/api/workspace/active-repo`; ensure a member whose active workspace has a connected repo
   does not get the solo first-run experience. If Phase 0 = hypothesis (a), add the
   `chat/page.tsx` stub.
5. **Phase 4 — (conditional) KB sync** per Q2, or file follow-up issue.
6. **Phase 5 — Verify.** Playwright re-run: member lands on a valid page (no 404) and sees
   the shared KB tree + opens a file. Owner unaffected (regression check). Solo user
   unaffected (claim-absent → solo path == legacy path).

## Acceptance Criteria

### Pre-merge (PR)

- AC1: `GET /api/kb/tree` for a member of a shared workspace whose active
  `current_workspace_id` is the shared workspace returns **200** with the shared
  workspace's tree (not 404). Verified by `kb-active-workspace-scoping.test.ts` and
  Playwright network capture.
- AC2: `GET /api/kb/content/[...path]` (+HEAD) and `/api/kb/search` for the same member
  return the shared workspace's content (not 404). The **read** routes (`tree`, `content`,
  `search`) are swept via `resolveActiveWorkspaceKbRoot`. **SCOPE RECONCILIATION (review
  finding):** `kb/file/[...path]` is **write-only** (PATCH/DELETE, no GET) and resolves via
  the shared `kb-route-helpers` (`authenticateAndResolveKbPath`); together with `kb/upload`,
  `kb/share`, and `kb/sync` it crosses the `github_installation_id` credential boundary and
  is **deferred to #4755** (Q2) — NOT swept in this PR. So `git grep -n 'from("users")'
  apps/web-platform/app/api/kb/` intentionally still returns caller-id-scoped reads in
  `kb/tree` (solo-only `kb_sync_history`/`github_installation_id`, guarded by
  `activeWorkspaceId === user.id`) and `kb/sync` (deferred write path). Member KB *viewing*
  is fully fixed; member *write/share/sync* fails closed (400/503) until #4755.
- AC3: A null/absent `current_workspace_id` claim resolves to the caller's solo workspace
  (`= userId`); a claim pointing at a workspace the caller is NOT a member of resolves to
  solo (never the sibling). Unit-tested (IDOR / cross-tenant guard).
- AC4: KB layout renders the tree (not `<NoProjectState />`) for the member case;
  `kb/layout.tsx` error branch unchanged.
- AC5: The member landing route renders a valid page (no "This page could not be found")
  with the member banner intact. Playwright screenshot in PR body. (Exact mechanism per
  Phase 0 repro.)
- AC6: **Owner regression:** an owner viewing their own workspace sees the identical KB and
  landing behavior as before (claim == solo or owned-ws id; fs path unchanged).
- AC7: **Solo regression:** a solo user (no membership beyond N2) is unaffected — active
  workspace id == `userId`, fs path == legacy path.
- AC8: The "tasks need an API key" read-only constraint for members is preserved — the
  `NoApiKeyBanner` joiner branch still renders; KB *viewing* is ungated; chat-time BYOK
  enforcement is untouched (no edits to the key-resolution path).
- AC9: No migration added (`git diff --stat apps/web-platform/supabase/migrations/` empty).

### Post-merge (operator)

- (none — pure code change against already-provisioned surfaces; `web-platform-release.yml`
  restarts the container on merge to `apps/web-platform/**`, which IS the deploy. Automation:
  not feasible to add operator steps because none are needed.)

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO), Legal (CLO) — carried forward from
`2026-05-31-invite-accept-membership-byok-brainstorm.md` `## Domain Assessments` (same
feature family, member-view data access).

### Engineering (CTO)

**Status:** reviewed (brainstorm carry-forward + plan-time code reads)
**Assessment:** GO. The active-workspace resolvers (`resolveCurrentWorkspaceId`,
`workspacePathForWorkspaceId`) already exist and are the canonical pattern (`active-repo`
route proves it). The fix is a read-path cutover with no schema change. Load-bearing risk:
sweeping ALL KB read sites (4 routes + shared helper) — partial sweep leaves a member
404ing on file-open while the tree loads. Mirror the `active-repo` claim→solo fallback
exactly (never a sibling). Owner/solo paths must be byte-identical post-fix.

### Product (CPO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Member lands in the shared workspace with full read access (KB/repo/agents
visible; tasks gated at chat-time) — the correct experience per Decision #5. Do not repoint
the repo for members (Decision #3). Member empty-state copy already correct via
`no-api-key-banner.tsx` joiner branch.

### Legal (CLO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** GO. KB *viewing* does not touch the BYOK key path (SQL-gated at
`resolve_byok_key_owner`) nor the `github_installation_id` credential (definer-RPC-gated).
Widening member read access to shared workspace data is consistent with the Art. 13
shared-data disclosure rendered at accept-time. No new Art. 33 exposure. Guardrail: the KB
sync path (Q2), if included, must read the installation via
`resolve_workspace_installation_id` (membership-checked), never `users.github_installation_id`.

### Product/UX Gate

**Tier:** advisory (modifies existing landing + KB surfaces; no new designed user-facing
page — the conditional `chat/page.tsx` is a redirect stub, not a rendered surface)
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (pipeline auto-accept)
**Skipped specialists:** none
**Pencil available:** N/A

#### Findings

If Phase 0 confirms hypothesis (a) and a `chat/page.tsx` stub is created, re-confirm tier:
a pure redirect stub stays advisory; any rendered content would escalate to BLOCKING.

## GDPR / Compliance Gate

The plan touches an API-route data-access boundary (member read scoping) and the
`single-user incident` threshold is declared — both fire the gate triggers. Invoke
`/soleur:gdpr-gate` at `/work` Phase 0 against this plan + the route diffs. Expected lens:
cross-tenant read confinement (claim-derived workspace id, solo fallback, no credential on
the view path). Advisory-only; Critical findings → operator-acked write to
compliance-posture.md + `compliance/critical` issue.

## Infrastructure (IaC)

Skipped — pure code change against already-provisioned surfaces (no new server, service,
secret, vendor, or persistent process).

## Observability

```yaml
liveness_signal:
  what: "GET /api/kb/tree 200-rate for shared-workspace members (vs 404-rate)"
  cadence: "per-request (existing route)"
  alert_target: "Sentry — existing reportSilentFallback on kb-tree fetch error"
  configured_in: "apps/web-platform/app/api/kb/tree/route.ts (logger.error + 500 path); hooks/use-kb-layout-state.tsx:107 client mirror"
error_reporting:
  destination: "Sentry via reportSilentFallback (server) + client-observability (hook)"
  fail_loud: "true — a malformed/again-404 tree response mirrors to Sentry before degrading; 404 is now an expected miss only for genuinely repo-less active workspaces"
failure_modes:
  - mode: "active-workspace resolution returns wrong dir (sibling)"
    detection: "kb-active-workspace-scoping.test.ts IDOR assertion; J5 solo-fallback parity"
    alert_route: "test gate (pre-merge); no runtime alert needed — fail-closed to solo"
  - mode: "member still 404s after cutover (un-swept route)"
    detection: "AC2 grep gate + Playwright file-open on each of tree/content/file/search"
    alert_route: "Sentry kb-tree/kb-content error mirror"
  - mode: "owner/solo regression (fs path drift)"
    detection: "AC6/AC7 + existing kb-route-helpers tests"
    alert_route: "CI test suite"
logs:
  where: "pino structured logs (server routes) + Sentry breadcrumbs"
  retention: "existing platform retention (unchanged)"
discoverability_test:
  command: "curl -s -o /dev/null -w '%{http_code}' https://<host>/api/kb/tree -H 'Cookie: <member-session>' # expect 200, was 404"
  expected_output: "200"
```

## Test Scenarios

Runner: `apps/web-platform` uses **vitest** (NOT bun test — `bunfig.toml` ignores; per
Sharp Edges). Test path MUST satisfy `vitest.config.ts` `include:` globs
(`test/**/*.test.ts`) — place at `apps/web-platform/test/server/kb-active-workspace-scoping.test.ts`.
Verify with `./node_modules/.bin/vitest run test/server/kb-active-workspace-scoping.test.ts`.

1. Member + claim=shared-ws → tree route returns owner's workspace dir tree (200).
2. Member + claim=null → solo workspace dir (no cross-tenant read).
3. Member + claim=sibling-ws-not-a-member → solo fallback (J5 parity), never the sibling.
4. Owner + own workspace → unchanged (byte-identical path).
5. Each of content/file/search mirrors scenarios 1-3.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/placeholder, or
  omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is filled.)
- **Do NOT read `users.workspace_path` for a member.** The fs dir is
  `workspacePathForWorkspaceId(activeWsId)` = `<WORKSPACES_ROOT>/<workspace_id>` — no
  `users` lookup. Reading `users.workspace_path` for a member is the exact #4543 bug.
- **Sweep all four KB read routes + the shared helper.** `kb-route-helpers` is the shared
  locus, but `tree`/`content`/`search` query `users` inline rather than via the helper —
  fixing only the helper leaves them broken (scope-by-new-column / audit-every-query).
- **vitest, not bun test**, and the test path must match `test/**/*.test.ts`; a co-located
  `*.test.ts` under `app/` or `server/` is silently never run.
- **Date the learning file at write-time** — do not prescribe a dated filename in tasks.md.
- **`workspace_status` is NOT on `workspaces`** — resolve readiness via the owner
  (`organizations.owner_user_id`) or fs existence (Q1); do not assume a `workspaces.workspace_status` column exists.
- **Claim → solo fallback, never sibling** — replicate `active-repo` (`resolveCurrentWorkspaceId`)
  exactly; a wrong fallback is a cross-tenant read at `single-user incident` threshold.

## Open Code-Review Overlap

Four open `code-review` scope-outs touch files adjacent to this plan's edit set; none
target the active-workspace data-scoping concern. Dispositions:

- **#2244** refactor(kb): migrate upload route to `syncWorkspace` — **Acknowledge.**
  Different concern (upload→helper consolidation). This plan does not edit `kb/upload`;
  if Q2 folds in sync, revisit whether upload should ride along. Stays open.
- **#2246** refactor(kb): low-severity polish from PR #2235 — **Acknowledge.** Cosmetic
  (types/dead-props/banner components); orthogonal to the scoping fix. Stays open.
- **#2590** refactor(dashboard): extract `useFirstRunAttachments` + `FirstRunComposer` from
  `DashboardPage` — **Acknowledge.** This plan touches only the repo-hint query block
  (lines 217-243), not the first-run composer. Extracting it now would balloon scope and
  collide with the brand-survival fix; keep the change surgical. Stays open.
- **#3334** review: consolidate gold-gradient CTA — **Acknowledge.** Visual consolidation,
  unrelated. Stays open.

(Re-run `gh issue list --label code-review --state open` at `/work` Phase 0 to confirm
against current backlog.)
