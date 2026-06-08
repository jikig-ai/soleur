---
title: "Fix workspace logo persistence + switcher refresh + relocate workspace-identity to General"
type: fix
status: draft
branch: feat-one-shot-workspace-logo-persist
created: 2026-06-07
lane: cross-domain
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
---

# 🐛 Fix workspace logo persistence + switcher refresh, and relocate workspace-identity settings to General

## Enhancement Summary

**Deepened on:** 2026-06-07

### Key Improvements
1. Localized the bug to two confirmed/suspected causes — H1 switcher-staleness (confirmed by code reading: `OrgSwitcherContainer` fetches once on mount) and H2 persistence (200 toast = no `update` error ⇒ 0-rows-matched OR read-side proxy failure). Plan now mandates a live repro to disambiguate before coding.
2. Added precedent-diff grounding: the same-tab refresh uses the `kb-sidebar-shell.tsx` CustomEvent pattern; the persist guard uses the `.update().select()` row-match pattern (precedent in `account-delete.ts`, `ws-handler.ts`).
3. Surfaced a reachability defect: the Team page is flag-gated (`resolveMembersTab` → null when `isTeamWorkspaceInviteEnabled` is OFF), so the logo/rename controls are currently UNREACHABLE for flag-off users — making the General relocation a functional fix, not just aesthetic.
4. Generated a committed wireframe of the relocated General layout (`general-workspace-identity-relocation.pen`).

### New Considerations Discovered
- Screenshot #1's logo is the optimistic blob preview, not the proxy/DB — it cannot evidence persistence.
- The 0-rows-matched silent-success class is currently untested (`workspace-logo-route.test.ts:207` mock always succeeds).

## Overview

Two related changes to the already-shipped workspace-logo feature (merged via PR #4930 / issue #4916, both CLOSED):

1. **BUG (primary):** After uploading a workspace logo on the Team settings page, (a) the top-left workspace switcher does not reflect the new logo, and (b) after navigating away and back the logo reverts to the monogram — i.e. the upload is not durably persisted despite a "Logo updated." success toast.

2. **UX (secondary):** Move the "Workspace logo" + "Rename workspace" controls from the **Team** section (described as "People who can act in this workspace") to the **General** section, since both are workspace-*identity* concerns. This also fixes a reachability defect (see Research Reconciliation).

This plan is a **fix to already-merged code** — the entire logo flow exists on `origin/main` and this branch has zero diff against main for the logo files. The premise "the upload does not actually save" is therefore a *runtime behavioral* claim, not a "never built" gap. Because the write path and the team-page read path are internally consistent under static analysis, **the plan MUST begin with a live reproduction** (browser + direct DB read) to capture the actual failure before prescribing the persistence fix (per Sharp Edge `2026-06-01-write-path-internally-consistent-claim-misses-trigger-vs-rpc-contradiction`). The switcher-staleness defect (item 1a) is independently confirmed by code reading and is fixed regardless of repro outcome.

No new dependencies. No new migrations expected (the `workspaces.logo_path` column, the `workspace-logos` bucket, the `is_workspace_owner` RPC, and the storage RLS already exist in migration 098).

## Premise Validation

- **Issue #4916** (`feat(ux): workspace logo UPLOAD capability`) — CLOSED. **PR #4930** — merged (confirmed via `git log origin/main`). The feature is shipped, so this is a fix not a build.
- **Cited files all exist and were read on `origin/main`/branch:**
  - `apps/web-platform/app/api/workspace/logo/route.ts` (POST upload + DELETE)
  - `apps/web-platform/app/api/workspace/[id]/logo/route.ts` (GET stable proxy → 302 signed URL, `Cache-Control: private, max-age=300`)
  - `apps/web-platform/components/settings/workspace-logo-settings.tsx` (the upload control; optimistic blob preview)
  - `apps/web-platform/components/dashboard/workspace-identity-tile.tsx` (renders `<img src=/api/workspace/<id>/logo>` or monogram, `onError` → monogram)
  - `apps/web-platform/app/(dashboard)/dashboard/settings/team/page.tsx` (reads `logo_path` for `initialHasLogo`)
  - `apps/web-platform/server/org-memberships-resolver.ts` (`resolveOrgMemberships` → `hasLogo` per workspace)
  - `apps/web-platform/components/dashboard/org-switcher-container.tsx` (fetches `list-memberships` **once on mount**, no refetch after upload)
  - `apps/web-platform/hooks/use-active-workspace.ts` (collapsed-rail identity; re-polls only on `window.focus`)
  - `apps/web-platform/supabase/migrations/098_workspace_logos.sql` (column + bucket + RPC + RLS)
- **No open follow-up issue** for logo persistence/switcher (`gh issue list --search "workspace logo" --state open` → empty).
- **Self-capability claims to verify at /work Phase 0 (not assert from this plan):** whether `service.from("workspaces").update({logo_path}).eq("id", workspaceId)` matched ≥1 row in the failing env (supabase-js returns NO error on 0-rows-matched); whether migration 098 is applied in the env where the bug was observed.

## 🔎 Root-Cause Hypotheses (to confirm at /work Phase 1 via live repro)

The screenshots are consistent with the DB write never landing **and** the switcher never refreshing. Note that **screenshot #1 proves nothing about persistence**: the "Logo updated." preview uses the client-side optimistic blob (`setPreview(URL.createObjectURL(file))`, `workspace-logo-settings.tsx:88`), NOT the proxy or the DB. The monogram in screenshot #2 means the server read returned `logo_path = NULL` after navigation.

### H1 — Switcher does not refresh after upload (CONFIRMED by code reading)
`OrgSwitcherContainer` fetches `/api/workspace/list-memberships` exactly once in a `useEffect([])` (`org-switcher-container.tsx:62-77`); `useActiveWorkspace` re-polls only on `window.focus` (`use-active-workspace.ts:75`). The upload component (`workspace-logo-settings.tsx`) sets only its OWN local state — it never signals the switcher to refetch. So even with correct persistence, the top-left identity will not update until a full reload / refocus. **This is a real defect and is fixed regardless of H2.**

### H2 — Upload does not persist `logo_path` (PRIMARY — confirm at repro)
The POST returns 200 (success toast shows), which means: owner-check passed, storage upload succeeded, and `service.from("workspaces").update({logo_path: key}).eq("id", workspaceId)` returned **no error**. supabase-js `.update().eq()` does NOT error when **0 rows match**. Candidate causes, in priority order:
1. **0-rows-matched, silently succeeding.** The `update` targets a `workspaces.id` that does not equal the resolved `workspaceId` in the failing env. For solo users the N2 invariant (`workspaces.id === users.id === current_workspace_id`, migration 053) should hold — confirm it does in the failing env, and confirm `resolveCurrentWorkspaceId` returns the workspaces.id (not an organization_id).
2. **Proxy GET failure path** masquerading as "reverted." If `logo_path` IS persisted but `GET /api/workspace/[id]/logo` returns 404/502 (e.g. signed-URL mint failure, bucket/RLS misconfig, or migration 098 storage policies absent), the `<img onError>` silently falls back to the monogram (`workspace-identity-tile.tsx:84`) — looking identical to "not persisted" on the chrome, though the Team page's server-side `initialHasLogo` would still be `true`. **Disambiguate at repro:** read `workspaces.logo_path` directly via the Supabase MCP after upload; if non-NULL, the defect is read-side (proxy), not write-side.
3. **Migration 098 not applied in the observed env** — would normally 500 at the owner-check or the update (missing RPC/column), which contradicts the success toast. Rule in/out by confirming the column/bucket/RPC exist in the env where the bug was reproduced.

The 0-rows-matched class is presently **untested**: `test/workspace-logo-route.test.ts:207` ("uploads object FIRST then UPDATEs logo_path") uses a mock `update().eq()` that always succeeds and never asserts a row was matched.

## Research Reconciliation — Spec vs. Codebase

| Claim (from task) | Codebase reality | Plan response |
| --- | --- | --- |
| "The upload does not actually save" | Write path (`logo/route.ts`) and Team-page read both use `resolveCurrentWorkspaceId` → same workspace id; code is internally consistent. 200 toast ⇒ no `update` error ⇒ either 0-rows-matched or read-side proxy failure. | Live repro at /work Phase 1 with direct DB read to localize write-side vs read-side BEFORE coding the fix. |
| "Switcher doesn't update after upload" | Confirmed: `OrgSwitcherContainer` fetches memberships once on mount; `useActiveWorkspace` re-polls only on focus; upload never triggers a refetch. | Add a same-tab refresh signal from the upload control to the switcher (event/`router.refresh()` + targeted refetch). H1 fix. |
| "Move logo + rename to General because Team = members/roles" | The Team/Members tab is **conditionally rendered**: `resolveMembersTab()` returns null unless `isTeamWorkspaceInviteEnabled(orgId, identity)` AND a non-null `current_organization_id` (`server/members-tab.ts:52,56`). When the flag is OFF, the Team page (and thus logo + rename) is **unreachable**. General (`/dashboard/settings`, root `page.tsx`) is always present. | Move is not merely aesthetic — it fixes a **reachability defect** for users without the Members tab. Implement the move into the General page (`SettingsContent`). |
| "General section" | `/dashboard/settings` root `page.tsx` → renders `components/settings/settings-content.tsx` (API key + project/repo setup). Nav label "General" defined in `components/settings/settings-shell.tsx:13`. | Relocate `WorkspaceLogoSettings` + `RenameWorkspaceAction` into `SettingsContent`; remove from `team/page.tsx`. |

## User-Brand Impact

**If this lands broken, the user experiences:** a workspace logo that appears to save ("Logo updated.") but silently reverts to the "S" monogram on every navigation — the exact reported defect, eroding trust in whether ANY setting persists. Or, if the section move regresses, the only control to set a workspace logo / rename becomes unreachable for solo/flag-off users.

**If this leaks, the user's data is exposed via:** N/A for the move; for the logo proxy, a cross-tenant signed-URL or a missing membership gate would expose one workspace's logo to another. The existing proxy already membership-gates (`is_workspace_member`) and resolves the workspace server-side — the fix MUST NOT widen this (no client-supplied workspace id on the write path; keep `resolveCurrentWorkspaceId`).

**Brand-survival threshold:** single-user incident — a non-persisting "saved" confirmation is a credibility failure visible to any single user on first use. CPO sign-off required at plan time; `user-impact-reviewer` invoked at review time.

## ✅ Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (repro):** A live reproduction (Playwright + Supabase MCP direct read of `workspaces.logo_path`) is captured in the PR body, localizing the persistence failure to write-side (0-rows / wrong id) OR read-side (proxy 404/502) OR env (mig 098 unapplied). The fix targets the confirmed cause.
- [ ] **AC2 (persistence):** After a successful upload, `workspaces.logo_path` for the active workspace is non-NULL and equals `<workspaceId>/logo.webp` (verified by direct DB read, not the toast).
- [ ] **AC3 (survives nav):** Navigating away from the settings page and back renders the uploaded logo (not the monogram) — `initialHasLogo`/`hasLogo` resolves `true` from the persisted row, and the proxy `GET /api/workspace/<id>/logo` returns 302 → a loadable image.
- [ ] **AC4 (switcher live update):** After a successful upload, the top-left workspace switcher reflects the new logo **without a full page reload** (same-tab signal triggers a memberships/active-workspace refetch). After removal, it reverts to the monogram likewise.
- [ ] **AC5 (0-rows regression test):** `test/workspace-logo-route.test.ts` gains a test asserting that when the `update` matches 0 rows the route does NOT return a bare 200 success — it surfaces the failure (the chosen guard: e.g. supabase-js `count` / returning representation, or a post-write read-back). RED before GREEN.
- [ ] **AC6 (section move):** `WorkspaceLogoSettings` and `RenameWorkspaceAction` render on the General page (`/dashboard/settings`) and are REMOVED from the Team page (`/dashboard/settings/team`). Verified by Playwright snapshot of both routes.
- [ ] **AC7 (reachability):** With the Members/Team tab flag OFF (`resolveMembersTab` → null), workspace logo + rename are still reachable on General. (Verify via the flag-off render path / test.)
- [ ] **AC8 (owner gate preserved):** A non-owner sees the disabled control with the owners-only tooltip on General (same behavior the Team page had) — no visible control that 403s on click.
- [ ] **AC9 (no security widening):** The write path still resolves the workspace server-side (`resolveCurrentWorkspaceId`); no client-supplied workspace id is introduced. The proxy still membership-gates. Confirmed by reading the diff.
- [ ] **AC10 (tests green):** `vitest run` for `workspace-logo-settings.test.tsx`, `workspace-logo-route.test.ts`, `workspace-logo-proxy-route.test.ts`, `workspace-identity-tile.test.tsx`, and any new General-page test pass; `tsc --noEmit` clean.

### Post-merge (operator)

- [ ] **AC11 (env verify):** If AC1 localizes the cause to "migration 098 unapplied in the observed env", confirm migration 098 is applied in that env via the Supabase MCP (read `information_schema.columns` for `workspaces.logo_path` + `storage.buckets` for `workspace-logos`). `Automation:` Supabase MCP read-only. (Skip if AC1 localizes to a code defect.)

## Implementation Phases

### Phase 0 — Preconditions (no code)
- Read every cited file (done in plan research). Confirm N2 invariant assumption and `resolveCurrentWorkspaceId` return semantics against the failing env.
- Confirm migration 098 is applied in the dev env used for repro (Supabase MCP).

### Phase 1 — Live reproduction (no code yet)
- Use Playwright MCP to upload a logo on the current Team page; capture the success toast.
- Immediately read `workspaces.logo_path` for the active workspace via Supabase MCP.
- Navigate away and back; capture whether the monogram returns.
- Hit `GET /api/workspace/<id>/logo` and record the status (302 vs 404/502).
- Record the localization (write-side / read-side / env) in the PR body. This decides the Phase 2 fix.

### Phase 2 — Persistence fix (RED → GREEN), driven by Phase 1 localization
- **If write-side (0-rows / wrong id):** add a row-match guard to the POST `update` (e.g. request a returning representation or `count`, or a read-back of `logo_path`) so a 0-rows write returns a 500 + Sentry breadcrumb instead of a false 200. Write the failing test (AC5) first.
- **If read-side (proxy):** fix the proxy/signed-URL/RLS path; ensure the env has the storage policies; keep the optimistic preview but ensure the persisted path is loadable post-nav.
- Files (write-side path): `apps/web-platform/app/api/workspace/logo/route.ts`, `apps/web-platform/test/workspace-logo-route.test.ts`.

### Phase 3 — Switcher live-update fix (H1, independent of Phase 2)
- On a successful upload/removal in `WorkspaceLogoSettings`, broadcast a same-tab refresh signal (a custom `window` event, or a shared store, or `router.refresh()` + a re-poll trigger) that causes `OrgSwitcherContainer` and `useActiveWorkspace` to refetch `list-memberships`.
- Prefer the minimal mechanism that matches existing patterns (the `use-active-workspace` coalesced fetch already exists — add a manual re-poll trigger rather than inventing infrastructure).
- Files: `apps/web-platform/components/settings/workspace-logo-settings.tsx`, `apps/web-platform/hooks/use-active-workspace.ts` and/or `apps/web-platform/components/dashboard/org-switcher-container.tsx`; plus test updates.

### Phase 4 — Relocate workspace-identity to General
- **Wireframe (committed):** `knowledge-base/product/design/settings/general-workspace-identity-relocation.pen` shows the target General-page layout — WORKSPACE rename card + Workspace logo card at the top, above the existing Anthropic API key + Project connection controls. Implement to match.
- Move `RenameWorkspaceAction` + `WorkspaceLogoSettings` rendering from `team/page.tsx` into `components/settings/settings-content.tsx` (General). Thread the required props (`workspaceId`, `organizationId`, `organizationName`, `isOwner`, `initialHasLogo`) — General's `page.tsx` must resolve these (it currently resolves user/repo data; add the workspace + ownership + `logo_path` resolution, mirroring the team page's derivation: `resolveTeamMembershipPageData` or the narrower `resolveCurrentWorkspaceId` + `is_workspace_owner` + `logo_path` read).
- Remove both controls from `team/page.tsx` (keep members/roles/invites there).
- Files: `apps/web-platform/app/(dashboard)/dashboard/settings/page.tsx`, `apps/web-platform/components/settings/settings-content.tsx`, `apps/web-platform/app/(dashboard)/dashboard/settings/team/page.tsx`. Test: a General-page test asserting both controls render + owner gate + flag-off reachability.

### Phase 5 — Verification
- Run the affected vitest files + `tsc --noEmit`.
- Playwright: full round-trip (upload on General → DB read → nav away/back → logo persists → switcher reflects).

## Files to Edit

- `apps/web-platform/app/api/workspace/logo/route.ts` — row-match guard on the persist `update` (if write-side).
- `apps/web-platform/app/api/workspace/[id]/logo/route.ts` — only if Phase 1 localizes to read-side proxy failure.
- `apps/web-platform/components/settings/workspace-logo-settings.tsx` — broadcast refresh signal on success/removal.
- `apps/web-platform/hooks/use-active-workspace.ts` and/or `apps/web-platform/components/dashboard/org-switcher-container.tsx` — receive the refresh signal and refetch.
- `apps/web-platform/components/settings/settings-content.tsx` — render the relocated identity controls.
- `apps/web-platform/app/(dashboard)/dashboard/settings/page.tsx` — resolve workspace + ownership + `logo_path` and pass to `SettingsContent`.
- `apps/web-platform/app/(dashboard)/dashboard/settings/team/page.tsx` — remove the relocated controls.
- `apps/web-platform/test/workspace-logo-route.test.ts` — 0-rows-matched regression test (AC5).
- `apps/web-platform/test/workspace-logo-settings.test.tsx` — refresh-signal-on-success test.
- (new) `apps/web-platform/test/components/settings/` — General-page identity-controls test (owner gate + flag-off reachability). Confirm the vitest `include:` glob covers the chosen path before placing (`apps/web-platform/vitest.config.ts` collects `test/**/*.test.tsx`, not co-located component tests).

## Files to Create

- One test file under `apps/web-platform/test/...` for the General-page relocation (path must match the vitest include glob).

## Open Code-Review Overlap

None — no open `code-review`-labeled issues touch the listed files (no open logo follow-ups; verified `gh issue list --search "workspace logo" --state open` → empty). The /work phase should re-run the overlap query against the finalized file list.

## Observability

```yaml
liveness_signal:
  what: workspace-logo persist failures (0-rows / proxy mint) via reportSilentFallback → Sentry
  cadence: per upload attempt
  alert_target: Sentry (feature=workspace-logo)
  configured_in: app/api/workspace/logo/route.ts, app/api/workspace/[id]/logo/route.ts
error_reporting:
  destination: Sentry via reportSilentFallback / Sentry.captureMessage
  fail_loud: true  # a 0-rows persist now returns 500 + breadcrumb instead of a silent false 200
failure_modes:
  - mode: persist update matched 0 rows
    detection: row-match guard (count/returning/read-back) in POST handler
    alert_route: Sentry breadcrumb op=persist-logo-path-zero-rows + 500
  - mode: proxy signed-URL mint failure
    detection: existing 502 path in [id]/logo route (op=sign-url)
    alert_route: Sentry
  - mode: img load failure on chrome
    detection: WorkspaceIdentityTile onError → Sentry warning op=render-onerror
    alert_route: Sentry
logs:
  where: pino (server routes) + Sentry
  retention: per existing platform retention
discoverability_test:
  command: "curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/api/workspace/<id>/logo (authenticated)  # expect 302 after upload, 404 before"
  expected_output: "302 after a successful upload; 404 when no logo"
```

## Domain Review

**Domains relevant:** Product/UX, Engineering (covered by plan body)

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (pipeline auto-accept; deepen-plan will run substance agents at single-user-incident threshold)
**Skipped specialists:** none — this modifies EXISTING UI surfaces (no new page/component file is created under `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`; the relocation reuses existing `WorkspaceLogoSettings`/`RenameWorkspaceAction` components). ADVISORY, not BLOCKING.
**Pencil available:** yes — wireframe committed at `knowledge-base/product/design/settings/general-workspace-identity-relocation.pen` (the relocation is a structural layout change to the General page, so a `.pen` is produced per `wg-ui-feature-requires-pen-wireframe`).

#### Findings

The section move is a low-risk relocation of two existing controls between two existing pages; it does not introduce new interactive surfaces. The reachability argument (Team tab is flag-gated; General is always present) makes the move a net UX/functional improvement, not just a re-org.

## Test Scenarios

- Upload on General → DB `logo_path` non-NULL → nav away/back → logo persists (AC2/AC3).
- Upload → switcher updates same-tab (AC4).
- 0-rows-matched update → 500 + breadcrumb (AC5).
- Non-owner → disabled control + tooltip on General (AC8).
- Flag-off (`resolveMembersTab` null) → identity controls still reachable on General (AC7).
- Team page no longer renders logo/rename (AC6).

## Sharp Edges

- **The "Logo updated." toast is not evidence of persistence** — it reflects the optimistic blob preview + a 200 that can be a 0-rows no-op. Always confirm via a direct DB read.
- Screenshot #1 (post-upload) renders the local blob, not the proxy — it cannot distinguish write-side from read-side failure. Localize via DB read + proxy status at repro.
- A plan whose `## User-Brand Impact` section is empty, contains only TBD/TODO/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Section is filled above.)
- When placing the new General-page test, confirm the path matches `apps/web-platform/vitest.config.ts` `include:` globs (`test/**/*.test.tsx`) — a co-located `components/**/*.test.tsx` is silently never run.
- Do not introduce a client-supplied workspace id on the write path to "fix" persistence — that would be a cross-tenant write vector. The server-side `resolveCurrentWorkspaceId` resolution is load-bearing security.

## Research Insights (deepen-plan)

### Precedent-Diff — same-tab refresh signal (Phase 3)
**No precedent for a logo-specific signal, but two canonical refresh patterns exist — adopt one, do not invent:**
- `components/kb/kb-sidebar-shell.tsx:51` — `window.dispatchEvent(new CustomEvent(RAIL_EXPAND_EVENT))` with a paired `addEventListener(RAIL_EXPAND_EVENT, …)` consumer. This is the exact shape for a `WORKSPACE_LOGO_CHANGED` custom event that `useActiveWorkspace` / `OrgSwitcherContainer` listen for and re-poll on.
- `router.refresh()` is used pervasively in settings after a mutation (`key-rotation-form.tsx:70`, `dsar-export-job-list.tsx:97,139`, `project-setup-card.tsx:59`). `router.refresh()` re-runs server components (so a server-resolved `hasLogo` updates) but does NOT by itself re-fire the client `useActiveWorkspace` fetch — the collapsed rail still needs the custom-event nudge. **Recommendation:** emit a `WORKSPACE_LOGO_CHANGED` CustomEvent on success/removal; have `useActiveWorkspace` add a listener that calls its `poll()`, and `OrgSwitcherContainer` add a listener that re-runs its memberships fetch. This is the minimal, precedent-matching mechanism (no polling interval).

### Precedent-Diff — update row-match guard (Phase 2, write-side)
**Precedent:** supabase-js `.select(col, { count: "exact", head: true })` for existence/count is used at `server/account-delete.ts:520,720`, `server/ws-handler.ts:699,1430`, `app/api/push-subscription/route.ts:46`. For the persist guard, the simplest correct form is `service.from("workspaces").update({ logo_path: key }).eq("id", workspaceId).select("id")` and assert `data.length === 1` — a 0-length result is the silent no-op the bug class hinges on, now turned into a 500 + `op=persist-logo-path-zero-rows` breadcrumb. (supabase-js returns the updated rows from `.select()` after `.update()`; confirm the chained `.select()` shape against the installed `@supabase/postgrest-js` version at /work Phase 0, per the PostgREST Sharp Edge.)

### Verify-the-negative pass
- Claim "no client-supplied workspace id on the write path" → CONFIRMS: `app/api/workspace/logo/route.ts:44` resolves `workspaceId` via `resolveCurrentWorkspaceId(user.id, supabase)`; the request body carries only `file`. The fix must preserve this (AC9).
- Claim "proxy membership-gates" → CONFIRMS: `app/api/workspace/[id]/logo/route.ts:55` calls `is_workspace_member` before signing. No widening needed.

## Alternative Approaches Considered

| Approach | Why not chosen |
| --- | --- |
| Keep logo/rename on Team, only fix persistence | Leaves the reachability defect (flag-off users can't reach the controls) and the section-semantics mismatch the task flags. |
| Move logo/rename to a new dedicated "Workspace" section | Adds a nav tab + new page surface (BLOCKING UX tier, new file) for two controls; General already exists and is always present. YAGNI. |
| Fix switcher staleness via polling interval | Wasteful re-fetch; the upload is a discrete event — a same-tab signal is the minimal correct mechanism. |
