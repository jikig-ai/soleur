---
title: "Fix KB share-link failure + resolver consolidation + C4 Concierge UX consistency"
date: 2026-06-04
type: fix
branch: feat-one-shot-kb-share-resolver-consolidation-ux
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: planned
related:
  - PR #4947 (merged 2026-06-04 — surfaced share error, did NOT fix create failure)
  - PR #4922 (merged 2026-06-04 — added kb_share_links.workspace_id to insert)
  - ADR-044 (workspace read-path cutover; users → workspaces state relocation)
  - postmortem knowledge-base/engineering/operations/post-mortems/kb-share-link-silent-failure-postmortem.md
---

# Fix KB share-link failure + resolver consolidation + C4 Concierge UX consistency

🐛 + ♻️ + ✨ — Three coupled workstreams on the KB document viewer:

- **A (Observability, ships first):** instrument the share path's silent failure branches so the exact failing code path surfaces in Sentry on the next "Generate link" click. This is the diagnostic — independently shippable and verifiable.
- **B (Resolver consolidation):** migrate `share` + `upload` routes off the legacy `resolveUserKbRoot` onto the membership-scoped ADR-044 `resolveActiveWorkspaceKbRoot`, then remove `resolveUserKbRoot`. This is the structural fix the operator requested and (per the hypothesis) the actual cure for the share failure.
- **C (C4 Concierge UX):** make the C4 diagram's Concierge trigger + close affordance consistent with the markdown viewer (top-bar "Ask about this document" next to Share), keeping the C4-specific Code tab, without re-introducing the double-mount.

## Overview

Clicking "Generate link" (SharePopover) on `engineering/architecture/diagrams/c4-model.md` returns the new error state from PR #4947 ("Couldn't generate a link. Please try again.") — the error-surfacing UX works, but the underlying `createShare` (or the resolver feeding it) still fails. The prior cycle believed PR #4922 (adding `workspace_id` to the insert) was the dominant root cause; the failure persisting post-#4947 proves a *second* failure surface exists. The strong hypothesis (verified against live code below) is that the **share route's resolver (`resolveUserKbRoot`) has a failure surface the other KB read routes do not**, and that surface emits no Sentry signal — so the failing branch is invisible.

This plan refuses to ship a guessed fix. Workstream A lands the instrumentation first, makes the failing branch observable, and the resolver consolidation (B) is then validated against that signal. No new dependencies. No new infrastructure. Pure code change against already-provisioned surfaces.

## Premise Validation (Phase 0.6)

All cited references checked against live code on this branch. **Every file/line below was read, not paraphrased.**

| Cited claim | Verified? | Evidence |
|---|---|---|
| PR #4947 merged 2026-06-04, shipped error-surfacing + collapsible C4 panel | ✅ HELD | `gh pr view 4947` → state MERGED, title "fix(kb): surface share-link errors + collapsible C4 Concierge panel", mergedAt 2026-06-04T20:12:36Z |
| PR #4922 added `workspace_id` to `createShare` insert | ✅ HELD | `kb-share.ts:306-318` insert sets `workspace_id: workspaceId`; comment cites #4922 |
| share route uses `resolveUserKbRoot` | ✅ HELD | `app/api/kb/share/route.ts:9,38` — `resolveUserKbRoot(user.id)` (no client passed) |
| `resolveUserKbRoot` mints a fresh tenant client + reads `users` under RLS | ✅ HELD | `kb-route-helpers.ts:258-282` — `getFreshTenantClient(userId)` then `.from("users").select(...).eq("id",userId).single()` |
| content/tree/search/c4-project use `resolveActiveWorkspaceKbRoot` (service-role, membership-scoped) | ✅ HELD | content `[...path]/route.ts:36`, tree `route.ts:18`, search `route.ts:13`, c4/project `route.ts:42` — all pass `serviceClient` |
| createShare pre-insert validation returns do NOT mirror to Sentry | ✅ HELD | `kb-share.ts` — `invalid-path`(203,212), `symlink-rejected`(225), `not-found`(232), `not-a-file`(245), `too-large`(253) all return with NO `reportSilentFallback`. Only INSERT branches (23503@349, db-error@361) mirror |
| share route resolver-error response does not mirror | ✅ HELD | `share/route.ts:39` — `if (!workspace.ok) return workspace.response;` returns the 503/403 untouched; `resolveUserKbRoot` mirrors only the tenant-mint `RuntimeAuthError` branch (264-267), NOT the `workspace_status !== "ready"` 503 (284-295) |
| both resolvers compute the same path for a solo owner | ✅ HELD | both join `<workspacePath>/knowledge-base`; for solo, active workspace id === user.id === legacy `users.workspace_path` basename. Divergence is in **read credential + failure surface**, not the path |
| upload needs repo_url + github_installation_id (not returned by active resolver) | ✅ HELD | `upload/route.ts:71-78` passes `extras: ["repo_url","github_installation_id"]`; `resolveActiveWorkspaceKbRoot` returns `{activeWorkspaceId, workspacePath, kbRoot, repoStatus}` only |
| `authenticateAndResolveKbPath` reads `users.workspace_path` directly | ✅ HELD | `kb-route-helpers.ts:116-158` — tenant read of `users`, `path.join(userData.workspace_path,"knowledge-base")` |
| `resolveUserKbRoot` callers = share + upload only | ✅ HELD | grep of `app/api/**` — only `share/route.ts` and `upload/route.ts` import it |
| `resolveActiveWorkspaceKbRoot` self-scopes via user_session_state/workspace_members | ✅ HELD | `workspace-resolver.ts:286-327` — `.eq("user_id", userId)` on every probe; non-member claim falls back to solo (`userId`), never a sibling |
| c4-workspace has bespoke floating "Open Concierge" pill + collapse chevron | ✅ HELD | `c4-workspace.tsx:66-78` (pill), `145-156` (chevron), local `conciergeCollapsed` state (56) |
| KbChatTrigger suppressed on C4 via `suppressSidebar` | ✅ HELD | `kb-chat-trigger.tsx:53` returns null; `page.tsx:74-79` sets `setSuppressSidebar(!!c4Embed)` |
| KbChatContent already has its own filename + X close header | ✅ HELD | `kb-chat-content.tsx:147-169` |
| Test runner = vitest (NOT bun) | ✅ HELD | `package.json:15` `"test":"vitest"`; `bunfig.toml` blocks bun test; `vitest.config.ts:44,60` globs `test/**/*.test.ts` (node) + `test/**/*.test.tsx` (jsdom) |
| reportSilentFallback signature | ✅ HELD | `server/observability.ts:183` `(err, { feature, op, extra, message, art33Breach })`; `null` err + explicit `message` pattern already used at `kb-share.ts:784` (preview-invariant) |

**No stale premises.** PR #4947 is exactly the prior-cycle fix described; the failure persisting is the documented residual the parent's diagnosis targets.

## Research Reconciliation — Hypothesis vs. Codebase Reality

The parent's hypothesis is correct in shape but the *mechanism* is sharper than "validation logic divergence":

| Parent's framing | Codebase reality | Plan response |
|---|---|---|
| "divergence is in VALIDATION LOGIC, not the path" | Both resolvers ultimately gate readiness on `users.workspace_status === "ready"` (resolveUserKbRoot:286; resolveActiveWorkspaceKbRoot:427). The divergence is the **read CREDENTIAL** (tenant/RLS vs service-role) plus an extra failure surface: `resolveUserKbRoot` can fail at `getFreshTenantClient` with a `RuntimeAuthError` → 503 "Workspace not ready" (or 403 in `authenticateAndResolveKbPath`), a branch the service-role resolver has no analogue for. | Workstream A instruments BOTH the tenant-mint branch (already mirrored) AND the `workspace_status !== "ready"` 503 (NOT mirrored) so we learn which fires. Workstream B eliminates the divergence by switching to the service-role membership-scoped resolver. |
| "createShare's pre-insert validation returns are invisible" | Confirmed exactly — 5 returns with no mirror. | Workstream A adds a mirror to each (null-err + message + reason=code). |
| failure "likely affects ALL docs now, not just c4-model.md" | Plausible: if the failing branch is resolver-level (503 before createShare runs), it is doc-independent. If it is a createShare validation return (e.g. `not-found`), it is doc/path-specific. **A disambiguates this.** | Test scenarios capture both a c4 doc AND a fresh md doc to disambiguate resolver-level vs path-level. |

**Why instrumentation must precede the fix:** if we ship B and the failure was actually a `createShare` validation return (path resolution mismatch between the two resolvers' `kbRoot`), B would not fix it and we would have shipped a green-looking change over a still-broken state. A makes the branch observable so B is *confirmed*, not assumed.

## User-Brand Impact

**If this lands broken, the user experiences:** clicking "Generate link" on any KB doc (md or c4 diagram) continues to return "Couldn't generate a link. Please try again." — the public-sharing feature stays silently non-functional for the operator (tenant-zero) and every other user. A regression in Workstream B's resolver swap could *additionally* break the working KB read paths (content/tree/search) or, worst case, widen the tenant boundary so one user resolves another workspace's KB root.

**If this leaks, the user's workspace data is exposed via:** Workstream B changes a tenant-boundary resolver. An IDOR regression (resolving a sibling workspace's `kbRoot` for the wrong caller) would let one user mint a share link to — or read — another tenant's KB documents. This is the brand-survival vector.

**Brand-survival threshold:** single-user incident. One cross-tenant KB read or a single shared-link minted against the wrong workspace is a brand-survival event for a product whose core promise is private per-tenant knowledge bases. CPO sign-off required at plan time; `security-sentinel` (R1–R6) + `user-impact-reviewer` run at review time.

## Hypotheses (ranked, to be confirmed by Workstream A)

1. **(strongest) Resolver-level 503 before createShare runs.** `resolveUserKbRoot` returns `{ok:false, 503 "Workspace not ready"}` because the tenant/RLS read of `users.workspace_status` returns a row whose `workspace_status` is null/not-"ready" — even though `workspaces.repo_status` (read by the service-role resolver) IS ready. ADR-044 relocated repo/readiness state to `workspaces`; `users.workspace_status` is documented as "stale/empty for users provisioned after the ADR-044 relocation" (`workspace-resolver.ts:333-337`). The operator's `users.workspace_status` may be empty/stale while `workspaces.repo_status` is ready. → A's mirror on the `workspace_status !== "ready"` branch confirms this; B fixes it by reading `workspaces` via service-role.
2. **Tenant-mint `RuntimeAuthError` → 503/403.** `getFreshTenantClient` throws (JWT mint ceiling / GoTrue hiccup / rotation). Already mirrored — but the parent saw ZERO Sentry events, which argues *against* this (it would already be visible). Kept as a ranked possibility; A confirms by absence.
3. **createShare validation return (path-specific).** `not-found` because the two resolvers' `kbRoot` differs for this user (path mismatch). Less likely for a solo owner (paths converge) but A's per-branch mirror disambiguates definitively.

## Workstream A — Observability (ships first, independently verifiable)

**Goal:** every silent failure branch on the share path emits a Sentry signal carrying the failing `code`/`reason` + `documentPath`, per `cq-silent-fallback-must-mirror-to-sentry`. After this lands, the next "Generate link" click on a failing doc surfaces the exact branch.

### Files to Edit (A)

- **`apps/web-platform/server/kb-share.ts`** — add `reportSilentFallback(null, { feature:"kb-share", op:"create", message:"<branch>", extra:{ userId, documentPath, reason:"<code>" } })` to each of the 5 pre-insert validation returns:
  - `invalid-path` (lines 203 + 212) — null-byte and path-escape
  - `symlink-rejected` (line 225)
  - `not-found` (line 232)
  - `not-a-file` (line 245)
  - `too-large` (line 253)
  - Follow the exact `null`-err + explicit-`message` shape already used at `kb-share.ts:784` (preview-invariant). `reason` MUST equal the `code` literal so Sentry queries can pivot on `reason:<code>`. Do NOT change the HTTP status/body shape (the client contract from PR #4947 must stay stable).
  - **Sharp edge:** `invalid-path` / `too-large` are partly attacker-reachable (a crafted documentPath). These are *expected* low-frequency events, not errors — mirror at the same `reportSilentFallback` level (it routes to Sentry + pino) but tag `reason` so on-call can distinguish a probe from a genuine regression. Do not escalate to `art33Breach`.
- **`apps/web-platform/app/api/kb/share/route.ts`** — mirror the resolver-error response before returning it. At line 39 (`if (!workspace.ok) return workspace.response;`), the resolver already returns a Response — we cannot read its status cleanly post-construction. Instead: have the route capture the resolver's failure *code* by switching the resolver call to surface a discriminated `{ok:false, status, code}` BEFORE building the Response, OR (simpler, and the path Workstream B takes anyway) migrate the route to `resolveActiveWorkspaceKbRoot` which already returns `{ok:false, status: 404|503}` — then mirror with the status. **Sequencing note:** A's route-level mirror is cleanest to land *together with* B's route migration (the discriminated `{ok,status}` shape is what enables a clean mirror). If A must ship strictly before B, add a minimal inline mirror in `resolveUserKbRoot`'s `workspace_status !== "ready"` branch (lines 284-295) carrying `op:"resolveUserKbRoot.workspace-not-ready"`, `extra:{ userId }`. (This is the single highest-value A change for confirming hypothesis 1.)

### Tests (A) — `apps/web-platform/test/kb-share.test.ts` (vitest, node project)

Write failing tests first (cq-write-failing-tests-before). For each of the 5 validation returns, assert `reportSilentFallback` was called once with the matching `reason`/`code`. Mock `reportSilentFallback` (vi.mock the observability module) and drive `createShare` with a synthesized fixture per branch:
- null-byte documentPath → `reason:"invalid-path"`
- path-escape (`../../etc/passwd`) → `reason:"invalid-path"`
- a symlink fixture (or mock `fs.promises.open` to throw ELOOP) → `reason:"symlink-rejected"`
- missing file (ENOENT) → `reason:"not-found"`
- a directory path (stat.isFile()===false) → `reason:"not-a-file"`
- oversized stat (> MAX_BINARY_SIZE, mock stat.size) → `reason:"too-large"`

Add one test in `apps/web-platform/test/kb-route-helpers.test.ts` asserting the `workspace_status !== "ready"` branch of `resolveUserKbRoot` mirrors (if the inline-A path is taken). All fixtures synthesized (cq-test-fixtures-synthesized-only).

### A — Acceptance (independently shippable)

- AC-A1: All 6 validation-return tests assert exactly one `reportSilentFallback` call with the matching `reason`. (verifiable: `./node_modules/.bin/vitest run test/kb-share.test.ts`)
- AC-A2: `grep -c "reportSilentFallback" apps/web-platform/server/kb-share.ts` ≥ 9 (5 new validation + 4 pre-existing INSERT/preview branches).
- AC-A3 (post-merge signal, operator-automatable via Sentry MCP): after A deploys, a single "Generate link" click on the failing doc produces ≥1 Sentry event in `web-platform` with a `reason`/`op` tag identifying the branch. Query via `mcp__plugin_supabase_supabase__*` is N/A — use the Sentry org `jikigai-eu` / project `web-platform` event search for `feature:kb-share` in the 1h window.

## Workstream B — Resolver consolidation (the structural fix)

**Goal:** migrate `share` + `upload` off `resolveUserKbRoot` onto the membership-scoped service-role `resolveActiveWorkspaceKbRoot` (ADR-044 parity with content/tree/search/c4-project), then remove `resolveUserKbRoot`. Eliminates the divergent failure surface that (per hypothesis 1) breaks share.

### Files to Edit (B)

- **`apps/web-platform/app/api/kb/share/route.ts`** — replace `resolveUserKbRoot(user.id)` with `resolveActiveWorkspaceKbRoot(user.id, serviceClient)` (the route already constructs `serviceClient` at line 37). Mirror the content route's branch (`content/[...path]/route.ts:36-41`): on `!access.ok`, return 404/503 per `access.status`. Pass `access.kbRoot` to `createShare`. Keep `resolveCurrentWorkspaceId(user.id, serviceClient)` for the insert's `workspace_id` — OR reuse `access.activeWorkspaceId` (they resolve identically; prefer `access.activeWorkspaceId` to drop the second DB round-trip — **simplification, confirm equality in a test**). This is also where A's resolver-error mirror lands cleanly (status is now in scope).
- **`apps/web-platform/app/api/kb/upload/route.ts`** — the hard caveat. Upload needs `repo_url` + `github_installation_id` (lines 71-78, 171, 189, 218, 237) which `resolveActiveWorkspaceKbRoot` does NOT return. **Decision (REVISED after precedent-diff — see below): add a sibling helper `resolveActiveWorkspaceRepoMeta(userId, serviceClient)` in `workspace-resolver.ts` that reads repo metadata from `workspaces`, NOT from any `users` row.** ADR-044 (migrations 079/080/081) RELOCATED `repo_url` + `github_installation_id` from `users` to `workspaces`; the canonical read is the `active-repo` route (`app/api/workspace/active-repo/route.ts:67-71`): `service.from("workspaces").select("repo_url, repo_status").eq("id", activeWorkspaceId)`. The new helper:
  - resolves the active workspace id via `resolveActiveWorkspaceIdWithMembership(userId, serviceClient)` (already extracted, lines 286-327; claim → solo fallback, never a sibling);
  - reads `workspaces.repo_url` by active id (service-role, mirroring active-repo);
  - resolves the installation id via the EXISTING `resolveInstallationId(userId, activeWorkspaceId)` (`server/resolve-installation-id.ts`) — which goes through the membership-checked `resolve_workspace_installation_id` SECURITY DEFINER RPC because `workspaces.github_installation_id` is REVOKED from the `authenticated` grant (migration 079:73). Do NOT read `github_installation_id` via a direct tenant SELECT — it will return null.
  - Returns `{ ok:false, status:400|404|503 } | { ok:true, repoUrl, githubInstallationId }`. Mirror any query error via `reportSilentFallback`.
  - Rationale for a sibling (not extending `resolveActiveWorkspaceKbRoot`'s return): read-path routes (content/tree/search) do NOT need repo metadata; widening their resolver surfaces an unused field + an extra read on every render. Upload composes `resolveActiveWorkspaceKbRoot` (kbRoot + readiness/connectivity gate) + `resolveActiveWorkspaceRepoMeta` (git-push metadata).
  - **Do NOT regress upload's git push** — `syncWorkspace`'s second arg (`workspace_path`) MUST be `access.workspacePath` (active workspace path from `resolveActiveWorkspaceKbRoot`); owner/repo parsing uses the helper's `repoUrl`; GitHub API calls use the helper's `githubInstallationId`.
  - **Sharp edge (upload owner vs caller):** today upload reads the *caller's* `users.repo_url`/`installation_id` (via `resolveUserKbRoot` extras). For a solo owner this equals `workspaces.<solo>` (backfilled by migration 080). For an invited member uploading to a shared workspace, the legacy `users`-row read returns the *member's empty* row → "No repository connected" (the #4543 dual-ownership bug — the EXACT class the active-repo route's doc-comment at lines 8-11 warns against). Migrating to the `workspaces`-source helper FIXES this latent bug. It is a behavior change: assert a solo owner's upload path is byte-identical AND add a shared-member test (member uploads → resolves the WORKSPACE's repo + installation via the RPC). In-scope; call out in the PR body.
- **`apps/web-platform/server/workspace-resolver.ts`** — add `resolveActiveWorkspaceRepoMeta` per the `workspaces`-source pattern above. Reuse `resolveActiveWorkspaceIdWithMembership` (lines 286-327) for the active-id + membership self-heal, the `active-repo` route's `workspaces.repo_url` read shape (lines 67-71), and `resolveInstallationId` for the credential. Self-scope all probes. Mirror errors via `reportSilentFallback`.
- **`apps/web-platform/server/kb-route-helpers.ts`** — remove `resolveUserKbRoot` (lines 206-320) and its types (`ResolveUserKbRootExtras`, `ResolveUserKbRootResult`) once no caller remains. **Decision on `authenticateAndResolveKbPath`:** KEEP IN SCOPE — migrate it too, OR scope out with rationale (see Decisions below). Recommended: **scope `authenticateAndResolveKbPath` OUT of this PR** (it serves `kb/file` + `kb/c4/[...path]` PATCH/DELETE — different surface, different validation contract incl. owner/repo parsing + symlink + markdown-block; migrating it is a larger blast radius and is NOT on the share failure path). File a tracking issue for full ADR-044 consistency. The tenant-mint alert (`kb_tenant_mint_silent_fallback`, op `authenticateAndResolveKbPath.tenant-mint`) survives via `authenticateAndResolveKbPath`'s retained tenant path, so removing `resolveUserKbRoot`'s tenant-mint op does NOT dark the alert.

### Tests (B)

- **`apps/web-platform/test/kb-share.test.ts`** — already-present share tests must pass with the resolver swap; add a test asserting share route returns 404 when `resolveActiveWorkspaceKbRoot` returns `{ok:false,404}` and 503 on `{ok:false,503}`.
- **New: `apps/web-platform/test/server/workspace-resolver-repo-meta.test.ts`** (node) — unit-test `resolveActiveWorkspaceRepoMeta`: solo owner (own-row read), shared member (owner-row read via organizations hop), missing repo_url → 404/connected-gate, missing installation → fallback then 400-equivalent. Synthesized supabase mocks (mirror the `MaybeSingleChain` mock convention already in `workspace-resolver` tests).
- **`apps/web-platform/test/kb-upload.test.ts` + `kb-upload-route-delegation.test.ts`** — update mocks: replace `resolveUserKbRoot` mock with `resolveActiveWorkspaceKbRoot` + `resolveActiveWorkspaceRepoMeta`. Assert git push (`syncWorkspace`) still receives the active workspace path + installation id. Add the shared-member upload test.
- **Remove/Update tests referencing `resolveUserKbRoot`** (5 files): `test/kb-security.test.ts` (5 refs), `test/kb-route-helpers.test.ts` (8 refs), `test/sentry-kb-tenant-mint-alert-op-contract.test.ts` (1 ref — the `resolveUserKbRoot.tenant-mint` op contract; remove that op assertion, keep `authenticateAndResolveKbPath.tenant-mint`), `test/kb-delete.test.ts` (1 ref — likely incidental, verify), `test/server/kb-route-helpers.tenant-isolation.test.ts` (2 refs). For each, determine whether the ref is to the removed function (remove the case) or incidental (leave). Run `grep -rn resolveUserKbRoot apps/web-platform` post-edit; expected residual = 0.

### B — Security review mandate (BLOCKING, review phase)

This is a tenant-boundary change. `security-sentinel` R1–R6 MUST run at review:
- **R1 workspace boundary integrity:** confirm `share` + `upload` resolve only the caller's active workspace (claim → solo fallback, never a sibling).
- **R2 IDOR:** confirm `resolveActiveWorkspaceRepoMeta` self-scopes via `.eq` on session-derived `userId`; the owner hop reads `organizations.owner_user_id` of a workspace the caller is a confirmed member of (membership self-heal at 297-325 guarantees this).
- **R3 membership scoping:** non-member claim → solo fallback, verified by test.
- **R4–R6:** no privilege widening (service-role read was already the pattern for read routes; share already used `serviceClient` for the insert — this does not widen the *write* credential, only aligns the *read* credential), no new injection surface, fail-closed on probe error.

### B — Acceptance

- AC-B1: `grep -rn "resolveUserKbRoot" apps/web-platform --include="*.ts" | grep -v "\.test\."` returns 0 (function + all non-test callers removed).
- AC-B2: `grep -rn "resolveUserKbRoot" apps/web-platform/test` returns 0 (all test refs cleaned).
- AC-B3: full web-platform suite green: `cd apps/web-platform && ./node_modules/.bin/vitest run` (note: tsc + suite, not bun).
- AC-B4: solo-owner upload path byte-identical (test asserts `syncWorkspace` + GitHub PUT receive the same args as pre-migration for a solo user).
- AC-B5: shared-member upload resolves OWNER repo metadata (new test).
- AC-B6 (security): `security-sentinel` R1–R6 PASS at review; no IDOR / boundary-widening finding.

## Workstream C — C4 Concierge UX consistency

**Goal:** the C4 diagram uses the SAME top-bar trigger ("Ask about this document" next to Share, via `KbChatTrigger` in `KbContentHeader`) and the SAME close affordance (the X in `KbChatContent`'s own header) as the markdown viewer, while KEEPING the C4-specific Code tab. Remove the bespoke floating "Open Concierge" pill. Do NOT re-introduce the double-mount.

### Current state (verified)

- C4 page (`page.tsx:195-214`) already renders `KbContentHeader` (with `SharePopover` + a *suppressed* `KbChatTrigger`) AND `C4Workspace`.
- `KbChatTrigger` is suppressed on C4 (`kb-chat-trigger.tsx:53` returns null when `ctx.suppressSidebar`, set by `page.tsx:74-79`).
- `C4Workspace` owns a LOCAL `conciergeCollapsed` state (`c4-workspace.tsx:56`), a floating gold "Open Concierge" pill (66-78), and an in-panel collapse chevron (145-156). `KbChatContent` (nested in the right panel) already renders its own filename + X close header.

### Reconciliation design

Lift the C4 collapse/reveal control to the shared `KbChatContext` so the header `KbChatTrigger` drives it — exactly the lever the context already exposes (`open`/`openSidebar`/`closeSidebar`/`suppressSidebar`/`setSuppressSidebar`, `kb-chat-context.tsx:11-30`).

- **Stop suppressing the trigger on C4, but keep suppressing the desktop SIDE PANEL.** Today `suppressSidebar` does double duty: it hides the trigger AND the side panel. Split the concern: the C4 page should suppress the *side panel mount* (so `KbChatContent` is not double-mounted) but NOT the *trigger* — the trigger should reveal the C4 workspace's OWN Concierge. Cleanest: introduce a distinct context signal (e.g. `embeddedConcierge: boolean` + `revealEmbeddedConcierge: ()=>void` / `embeddedConciergeOpen`) so the page-header `KbChatTrigger` toggles the C4 workspace's reveal state, while the side-panel mount (`kb-desktop-layout` / `kb-sidebar-shell`) continues to honor `suppressSidebar` to avoid double-mount. (Confirm exact wiring during /work by reading `kb-desktop-layout.tsx` + `kb-sidebar-shell.tsx` — they consume `suppressSidebar`.)
- **Lift `conciergeCollapsed` to context.** `C4Workspace` reads `embeddedConciergeOpen` from context (instead of local `useState`) and renders the right panel when open. The header `KbChatTrigger` calls `revealEmbeddedConcierge()`; the panel's close (X in `KbChatContent` + the existing chevron) calls the context collapse.
- **Remove the floating "Open Concierge" pill** (`c4-workspace.tsx:66-78`) — reveal now lives in the top bar, consistent with md.
- **Keep the Concierge/Code tab bar** (C4-specific, `c4-workspace.tsx:122-157`) but the close affordance is the X in `KbChatContent`'s header (already present) + the chevron — confirm both call the lifted collapse. Match the md X visual (KbChatContent already has it; nothing to change there).
- **No double-mount:** because the side panel stays suppressed on C4 (only the trigger is un-suppressed), only the C4 workspace's Concierge mounts. Add a test asserting exactly one `[data-kb-chat]` mounts on a C4 doc.

### Files to Edit (C)

- `apps/web-platform/components/kb/kb-chat-context.tsx` — add the embedded-Concierge signal(s) to the context value + type (keep optional for test-mock back-compat, matching `suppressSidebar`'s pattern at 28-29).
- `apps/web-platform/app/(dashboard)/dashboard/kb/[...path]/page.tsx` — set the embedded-Concierge wiring on the C4 branch; keep `setSuppressSidebar(true)` for the side-panel mount, stop using it to hide the trigger.
- `apps/web-platform/components/kb/kb-chat-trigger.tsx` — when an embedded Concierge is present, the trigger reveals it (call the context reveal) instead of returning null. Keep the side-panel `openSidebar` path for md docs. Label stays "Ask about this document" / "Continue thread" (existing logic at 70-71).
- `apps/web-platform/components/kb/c4-workspace.tsx` — read reveal/collapse from context; remove the floating pill (66-78); wire the chevron (148) + `KbChatContent.onClose` (165) to context collapse.
- (read-only confirm during /work) `kb-desktop-layout.tsx`, `kb-sidebar-shell.tsx` — verify they gate the side-panel mount on `suppressSidebar`.

### Tests (C) — `apps/web-platform/test/c4-workspace.test.tsx` (vitest, jsdom)

(Per Sharp Edge: jsdom component tests live under `test/**/*.test.tsx`, NOT co-located.) Mock `next/navigation` incl. `useSearchParams` (per prior session-state note). Assert:
- C4-C1: exactly one `[data-kb-chat]` mounts on a C4 doc (no double-mount).
- C4-C2: the floating "Open Concierge" pill is gone (`queryByLabelText("Open Concierge")` is null).
- C4-C3: header trigger ("Ask about this document") reveals the collapsed Concierge.
- C4-C4: the X / chevron collapses it; Concierge stays mounted across tab toggle (thread persistence preserved).
- C4-C5 (no-regression): md viewer still opens the side panel via the trigger (existing behavior unchanged). Verify the md path's `onClose` (`closeSidebar`) is untouched.

### C — Wireframe (wg-ui-feature-requires-pen-wireframe, BLOCKING) — DONE

Committed: `knowledge-base/product/design/kb-viewer/c4-concierge-header-consistency.pen` (v2.9, two comparison frames). Frame 1 = markdown doc header (reference): Share + gold "Ask about this document" in the top bar opening the right side panel. Frame 2 = NEW C4 diagram header: SAME top-bar component, SAME "Ask about this document" gold trigger next to Share, SAME placement; trigger reveals the embedded Concierge; floating "Open Concierge" pill REMOVED; Concierge/Code tab bar KEPT with the X close affordance (same as md's KbChatContent X). JSON-validated and committed; live screenshot verification was blocked by the planning-env Pencil adapter (the artifact — a committed, non-empty, schema-valid `.pen` — is the load-bearing deliverable and is present). At /work, `ux-design-lead` may refine fidelity.

### C — Acceptance

- AC-C1..C5 map to tests C4-C1..C5 (all green via `./node_modules/.bin/vitest run test/c4-workspace.test.tsx`).
- AC-C6: `.pen` wireframe committed + non-empty under `knowledge-base/product/design/kb-viewer/c4-concierge-header-consistency.pen` (DONE — committed this cycle), referenced in the plan/spec.

## Acceptance Criteria (consolidated)

### Pre-merge (PR)
- [x] AC-A1/A2: all share validation returns mirror to Sentry; tests green (6 mirror tests; `grep -c reportSilentFallback server/kb-share.ts` = 19 ≥ 9).
- [x] AC-B1/B2/B3: `resolveUserKbRoot` fully removed (`grep -rn resolveUserKbRoot apps/web-platform --include="*.ts"` → 0, incl. tests); full vitest suite green (723 files, 8729 tests).
- [x] AC-B4/B5: upload git push preserved for solo (test #11 asserts cwd + installation id byte-identical); shared-member resolves WORKSPACE metadata via the RPC (AC-B5 test).
- [ ] AC-B6: security-sentinel R1–R6 PASS (no IDOR / boundary widening). — DEFERRED to review phase (parent orchestrator).
- [x] AC-C1..C6: single `[data-kb-chat]` on C4; pill removed; header trigger reveals; X/chevron collapse; md unregressed (6 c4-workspace tests); `.pen` committed.
- [ ] **Local repro captured BEFORE+AFTER:** — see Validation strategy fallback; faithful authed local repro of the operator's stale-workspace_status prod state is infeasible offline. Confidence via the unit/component suite + tsc. using the qa local-auth recipe (offline mock-Supabase `authenticated` Playwright project, `e2e/global-setup.ts`) OR the MCP local-auth recipe (`ux-audit/scripts/bot-signin.ts` + `NEXT_PUBLIC_DEV_EXTRA_ORIGINS`, per learning `2026-06-02-playwright-mcp-local-auth-dashboard-verification.md`), click "Generate link" on (a) a fresh md doc and (b) `c4-model.md`; capture the `/api/kb/share` POST status + body before the fix and after. "Done" = link minted (200/201 with token) for BOTH.

### Post-merge (operator, Sentry-automatable)
- [ ] AC-A3: after A deploys (if shipped separately), one "Generate link" click on the failing doc surfaces a Sentry event in `jikigai-eu`/`web-platform` carrying the failing `reason`/`op` — confirming the branch before B is claimed as the fix. If A+B ship together, instead verify the prod "Generate link" succeeds (link minted) for the operator on both doc types.

## Validation strategy — if faithful local repro is infeasible

The failure is prod-state-specific (hypothesis 1 depends on the operator's `users.workspace_status` being stale, which the offline mock storageState may not reproduce). Sequencing fallback (per the mandate):
1. **Ship A first** (independently verifiable: tests assert each branch mirrors).
2. **Confirm the failing branch from the instrumented Sentry signal** on the next prod "Generate link" click.
3. **Then ship B** matched to the confirmed branch, and verify prod "Generate link" succeeds end-to-end.
If local repro DOES reproduce (e.g. by seeding a mock user with empty `workspace_status` + ready `workspaces.repo_status`), prefer the local BEFORE/AFTER capture and ship A+B together.

## Files to Edit (master list)

- `apps/web-platform/server/kb-share.ts` (A)
- `apps/web-platform/app/api/kb/share/route.ts` (A + B)
- `apps/web-platform/app/api/kb/upload/route.ts` (B)
- `apps/web-platform/server/workspace-resolver.ts` (B — add `resolveActiveWorkspaceRepoMeta`)
- `apps/web-platform/server/kb-route-helpers.ts` (B — remove `resolveUserKbRoot` + types)
- `apps/web-platform/components/kb/kb-chat-context.tsx` (C)
- `apps/web-platform/app/(dashboard)/dashboard/kb/[...path]/page.tsx` (C)
- `apps/web-platform/components/kb/kb-chat-trigger.tsx` (C)
- `apps/web-platform/components/kb/c4-workspace.tsx` (C)
- Tests: `test/kb-share.test.ts`, `test/kb-route-helpers.test.ts`, `test/server/workspace-resolver-repo-meta.test.ts` (new), `test/kb-upload.test.ts`, `test/kb-upload-route-delegation.test.ts`, `test/kb-security.test.ts`, `test/sentry-kb-tenant-mint-alert-op-contract.test.ts`, `test/kb-delete.test.ts`, `test/server/kb-route-helpers.tenant-isolation.test.ts`, `test/c4-workspace.test.tsx`
- Wireframe: `knowledge-base/product/design/kb-viewer/c4-concierge-header-consistency.pen` (C — committed this cycle)

## Files to Create

- `apps/web-platform/test/server/workspace-resolver-repo-meta.test.ts`
- `knowledge-base/product/design/kb-viewer/c4-concierge-header-consistency.pen` (DONE — committed this cycle)

## Open Code-Review Overlap

None found (checked at plan time — to be re-run against the final Files-to-Edit list in deepen-plan).

## Observability

```yaml
liveness_signal:
  what: "share-create success rate (share_created pino event) + per-branch failure mirror"
  cadence: "per user action (Generate link click)"
  alert_target: "existing kb_tenant_mint_silent_fallback Sentry alert + (new) reason-tagged kb-share failure events"
  configured_in: "apps/web-platform/server/observability.ts (reportSilentFallback) + Sentry alert rules (terraform sentry infra)"
error_reporting:
  destination: "Sentry project web-platform (jikigai-eu) + pino stdout → Better Stack"
  fail_loud: "every share validation/resolver failure now emits reportSilentFallback (Workstream A) — no silent branch remains"
failure_modes:
  - mode: "resolver 503 (workspace_status not ready)"
    detection: "Sentry event op=resolveUserKbRoot.workspace-not-ready (pre-B) / share route 503 mirror (post-B)"
    alert_route: "Sentry feature:kb-share search; existing tenant-mint alert covers mint branch"
  - mode: "createShare validation return (invalid-path/not-found/not-a-file/symlink/too-large)"
    detection: "Sentry event feature:kb-share op:create reason:<code>"
    alert_route: "Sentry reason:<code> pivot"
  - mode: "IDOR / cross-tenant resolution regression (Workstream B)"
    detection: "security-sentinel R1-R6 at review; no runtime detector (boundary is structural)"
    alert_route: "review-time gate (pre-merge)"
logs:
  where: "container stdout (pino) → Better Stack; Sentry events"
  retention: "Sentry default (90d) / Better Stack plan retention"
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/kb-share.test.ts"
  expected_output: "all validation-return mirror tests pass (each branch asserts one reportSilentFallback with matching reason)"
```

## Domain Review

(Populated by Phase 2.5 — Product/UX is BLOCKING via the C4 header UI surface; Security relevant via Workstream B tenant boundary; Engineering relevant.)

## Test Scenarios

1. **Share on fresh md doc (happy path):** authenticated session, click Generate link → 201 + token; clicking again on unchanged content → 200 + same token (idempotent).
2. **Share on c4-model.md:** click Generate link → 201 + token (the reproduction target — must succeed AFTER B).
3. **Share resolver failure (instrumented):** simulate `resolveActiveWorkspaceKbRoot` → `{ok:false,503}` → route returns 503 AND mirrors to Sentry with status.
4. **Each createShare validation branch** → correct HTTP status (unchanged) + a Sentry mirror with `reason:<code>`.
5. **Upload solo owner:** byte-identical git push + GitHub PUT args (no regression).
6. **Upload shared member:** resolves OWNER repo + installation (fixes latent #4543-class bug).
7. **C4 Concierge:** header trigger reveals; X/chevron collapses; single `[data-kb-chat]`; pill gone; thread persists across tab toggle.
8. **md Concierge no-regression:** trigger opens side panel; `closeSidebar` untouched.
9. **Cross-tenant (security):** caller A cannot resolve caller B's kbRoot / repo metadata (security-sentinel + test on the solo-fallback path).

## Risks & Mitigations (deepen-plan Phase 4.4 precedent-diff + 4.45 verify-the-negative)

### Precedent-diff: `resolveActiveWorkspaceRepoMeta` (repo metadata read)

| Aspect | Precedent (`app/api/workspace/active-repo/route.ts`) | New helper plan | Match? |
|---|---|---|---|
| repo_url source | `service.from("workspaces").select("repo_url, repo_status").eq("id", activeWorkspaceId)` (lines 67-71) | same | ✅ |
| installation source | n/a (active-repo doesn't push) — but `resolveInstallationId` is the canonical credential reader (`resolve-installation-id.ts:38-41`, RPC `resolve_workspace_installation_id`) | reuse `resolveInstallationId(userId, activeWorkspaceId)` | ✅ aligned to ADR-044 |
| active id + membership self-heal | inline (lines 44-65) | reuse extracted `resolveActiveWorkspaceIdWithMembership` (workspace-resolver.ts:286-327) | ✅ shared, no drift |
| read credential | service-role | service-role | ✅ |

**Drift caught at deepen-plan:** the plan's first draft assumed repo metadata lives on the OWNER's `users` row (legacy). Migrations 079/080/081 relocated it to `workspaces`; `github_installation_id` is revoked from the `authenticated` grant (079:73) → MUST use the SECURITY DEFINER RPC via `resolveInstallationId`. Corrected above.

### Verify-the-negative (4.45) — load-bearing negative claims confirmed against live code

- **"never a sibling" (IDOR self-scope):** `resolveActiveWorkspaceIdWithMembership` (workspace-resolver.ts:286-327) — `.eq("user_id", userId)` on every probe; non-member claim unconditionally `activeWorkspaceId = userId`. CONFIRMED. The new helper inherits this.
- **"no double-mount":** `showChat = kbChatFlag && !!contextPath && sidebarOpen && !suppressSidebar` (`hooks/use-kb-layout-state.tsx:288`). `suppressSidebar` genuinely gates the side-panel mount of `KbChatContent` (`kb-desktop-layout.tsx:66`). `data-kb-chat` (`kb-chat-content.tsx:148`) is the UNIQUE mount marker. CONFIRMED — Workstream C keeps `setSuppressSidebar(true)` on C4 (side panel stays unmounted) while a DISTINCT signal lets the header trigger reveal the embedded Concierge. The C4-C1 test (one `[data-kb-chat]`) is the runtime guard.
- **"does not widen the write credential":** share already passed `serviceClient` for the insert (`share/route.ts:37,44-52`); B aligns only the READ credential (tenant→service-role), matching content/tree/search. CONFIRMED — no new write-privilege surface.

## Research Insights

**Implementation detail — A's resolver-error mirror (highest-value single change):** ship A's route-level mirror together with B's resolver swap. Post-B, `share/route.ts` calls `resolveActiveWorkspaceKbRoot` which returns `{ok:false, status:404|503}`; mirror at the route with `reportSilentFallback(null, { feature:"kb-share", op:"resolve", message:"share resolver failed", extra:{ userId, documentPath, reason: access.status } })`. If A must ship strictly before B, add the inline mirror at `resolveUserKbRoot:284-295` (`op:"resolveUserKbRoot.workspace-not-ready"`).

**Validation literal alignment (deepen quality check):** the `reason` value MUST equal the `CreateShareErrorCode` literal across kb-share.ts mirrors + the test assertions + the Sentry query. Canonical set: `invalid-path`, `not-found`, `not-a-file`, `symlink-rejected`, `too-large`. (Verified against `kb-share.ts:60-72`.)

**No new dependency / framework / infra.** Pure code change against already-provisioned surfaces; vitest already installed. Context7 not consulted — the change is internal to the codebase's own resolver/observability conventions, which are the authoritative source here (per the plan-skill "strong local context → skip external research").

## Enhancement Summary

**Deepened on:** 2026-06-04
**Hard gates:** 4.6 User-Brand Impact ✅ · 4.7 Observability ✅ · 4.8 PAT-shaped vars ✅ (none) · 4.9 UI-wireframe ✅ (committed `.pen`).

### Key improvements over the first draft
1. **Repo-metadata source corrected** (precedent-diff): `resolveActiveWorkspaceRepoMeta` reads `workspaces` (ADR-044), not the owner's `users` row; installation via the existing `resolveInstallationId` SECURITY DEFINER RPC. Avoids a guaranteed null `github_installation_id` on a direct tenant SELECT.
2. **"No double-mount" verified at the source** (`showChat` formula, `hooks/use-kb-layout-state.tsx:288`) — Workstream C's split-signal design is sound.
3. **IDOR self-scope confirmed** at `workspace-resolver.ts:286-327`.
4. **`.pen` wireframe authored + committed** (`c4-concierge-header-consistency.pen`) — the BLOCKING UI artifact.

### New considerations discovered
- The upload migration FIXES a latent #4543-class dual-ownership bug for shared members (legacy reads the member's empty `users` row). Now in-scope with a dedicated test.
- The `kb_tenant_mint_silent_fallback` alert survives `resolveUserKbRoot` removal via `authenticateAndResolveKbPath`'s retained tenant-mint op (scoped OUT). Verify before deleting the share-side op-contract test.

## Decisions

1. **A ships first / is independently verifiable.** Instrumentation is the diagnostic; it makes the failing branch observable so B is confirmed, not guessed.
2. **Sharper root-cause framing:** divergence is read-credential (tenant/RLS vs service-role) + the tenant-mint failure surface, not the path or the readiness column (both resolvers gate on `users.workspace_status`). Hypothesis 1 (stale `users.workspace_status` while `workspaces.repo_status` ready) is the strongest; A disambiguates.
3. **Upload repo metadata via a NEW sibling helper `resolveActiveWorkspaceRepoMeta`**, not by widening `resolveActiveWorkspaceKbRoot`'s return — keeps read-path resolvers lean and avoids an unused field + extra owner read on every content/tree/search call.
4. **`authenticateAndResolveKbPath` scoped OUT** (different surface: kb/file + kb/c4 PATCH/DELETE; larger blast radius; not on the share failure path). File a tracking issue for full ADR-044 consistency. The tenant-mint alert survives via its retained tenant path.
5. **Workstream C lifts the collapse/reveal state to KbChatContext** so the header trigger controls it; split `suppressSidebar`'s double duty (hide trigger vs hide side-panel) so the trigger can reveal the C4 embedded Concierge without re-mounting a second one.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is filled; threshold = single-user incident.)
- Test runner is **vitest**, not bun. Use `./node_modules/.bin/vitest run <path>`. jsdom component tests MUST live under `test/**/*.test.tsx` (NOT co-located) — `vitest.config.ts` only collects `test/**` for the jsdom project.
- Removing `resolveUserKbRoot` touches 5 test files (some refs incidental) + the `resolveUserKbRoot.tenant-mint` op-contract test. Verify the `kb_tenant_mint_silent_fallback` alert keeps a live op via `authenticateAndResolveKbPath` before deleting the share-side op assertion.
- Upload migration is a behavior change for shared members (fixes latent #4543 dual-ownership bug) — assert solo path byte-identical AND add a shared-member test; call it out in the PR body.
- Do NOT change the share route's HTTP status/body shape — the client error-state from PR #4947 contracts on `{ error, code }`.

## Alternative Approaches Considered

| Approach | Why not chosen |
|---|---|
| Ship B (resolver swap) without A | Violates the mandate — if the failure was a createShare validation return, B is a green-looking no-fix. A confirms the branch first. |
| Extend `resolveActiveWorkspaceKbRoot` to return repo metadata (instead of sibling helper) | Adds an unused field + owner-row read to every read-path route (content/tree/search/c4-project). Sibling helper keeps read resolvers lean. |
| Migrate `authenticateAndResolveKbPath` in-scope | Larger blast radius (kb/file + kb/c4 PATCH/DELETE, owner/repo parsing, markdown-block gate); not on the share failure path. Deferred to a tracking issue. |
| Keep the floating "Open Concierge" pill, just restyle | Inconsistent with md; the operator explicitly asked for parity with the md top-bar trigger. |
