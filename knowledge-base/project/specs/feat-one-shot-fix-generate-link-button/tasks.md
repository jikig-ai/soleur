# Tasks — Fix Generate-link button regression (tenant-mint dead-ends share-create)

Plan: `knowledge-base/project/plans/2026-06-04-fix-share-link-tenant-mint-regression-plan.md`
Lane: cross-domain | Brand-survival threshold: single-user incident (requires CPO sign-off)

## 1. Setup / Preconditions

- 1.1 Confirm regression locus unchanged on branch base: `git show abcb3765 -- apps/web-platform/app/api/kb/share/route.ts` shows the `resolveUserKbRoot(serviceClient, user.id)` → `resolveUserKbRoot(user.id)` change.
- 1.2 Re-read `apps/web-platform/server/kb-route-helpers.ts:225-301` (current `resolveUserKbRoot`) and the existing mock harness in `apps/web-platform/test/kb-route-helpers.test.ts` (`getFreshTenantClient`, `RuntimeAuthError`, `createServiceClient`→`mockFrom`, `mockReportSilentFallback` are all already mocked).
- 1.3 Confirm the pre-#3854 service-role read shape for column parity: `git show abcb3765~1:apps/web-platform/server/kb-route-helpers.ts` (columns `workspace_path, workspace_status[, extras]`).

## 2. Core Implementation (RED → GREEN)

- 2.1 **RED** — add failing tests in `kb-route-helpers.test.ts`:
  - 2.1.1 `getFreshTenantClient` throws `RuntimeAuthError` + service-role row has `ready` workspace → expect `{ ok: true, kbRoot }` (currently 503).
  - 2.1.2 Same, with `extras: ["repo_url", "github_installation_id"]` → expect extras populated from the fallback row.
  - 2.1.3 Mint throws + service-role row NOT ready → expect the 503 "Workspace not ready" response preserved.
  - 2.1.4 Mint throws → expect exactly one `mockReportSilentFallback` call carrying the error.
  - 2.1.5 Mint succeeds (no throw) → tenant read path unchanged, no service-role fallback, no `reportSilentFallback`.
- 2.2 **GREEN** — in `resolveUserKbRoot` (`kb-route-helpers.ts`), replace the `RuntimeAuthError` → 503 branch with: emit `reportSilentFallback` (feature `kb-route-helpers`, op `resolveUserKbRoot.tenant-mint`), then read the same `users` row via `createServiceClient()` (`.from("users").select(selectCols).eq("id", userId).single()`), and run the existing `workspace_path`/`workspace_status === "ready"`/`extras` validation against the fallback result. Keep the happy path and the non-`RuntimeAuthError` rethrow unchanged.
- 2.3 Verify NO change to `app/api/kb/share/route.ts` GET handler, `kb-share.ts`, or `share-popover.tsx`.

## 3. Testing & Verification

- 3.1 Run the edited suite: `cd apps/web-platform && ./node_modules/.bin/vitest run test/kb-route-helpers.test.ts` — all pass (node-project include glob `test/**/*.test.ts`).
- 3.2 Typecheck `apps/web-platform`.
- 3.3 (Post-merge / operator) Playwright MCP: open a KB doc → Share → "Generate link"; assert the popover transitions to the active state (`/shared/<token>` URL + Copy/Revoke), not back to idle.

## 4. Follow-ups (file as issues — do NOT silently defer)

- 4.1 File a follow-up issue: apply the same mint-failure resilience to `authenticateAndResolveKbPath` (`kb-route-helpers.ts:95`, used by `/api/kb/file/*`), or lift the fallback into a shared sub-helper both functions call. Re-eval criterion: "next time a KB file route 503s on mint failure." Milestone from `knowledge-base/product/roadmap.md`.
- 4.2 (Optional, separate PR) UX: surface an error toast in `share-popover.tsx` on a genuine 503 instead of silently bouncing to idle.

## 5. PR

- 5.1 PR body: reference regression source PR #3854 and umbrella #3244 with `Ref` (not `Closes` — #3244 is already CLOSED). If a tracking issue is created for this regression, use `Closes #<N>` for that.
- 5.2 Acceptance Criteria split into Pre-merge (PR) and Post-merge (operator) per plan.
