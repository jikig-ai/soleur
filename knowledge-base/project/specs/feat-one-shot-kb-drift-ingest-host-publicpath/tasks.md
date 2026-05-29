# Tasks — fix: KB-drift walker ingest (host + PUBLIC_PATHS)

Plan: `knowledge-base/project/plans/2026-05-29-fix-kb-drift-ingest-host-and-public-path-plan.md`
Lane: single-domain

## Phase 1 — Tests first (RED)

- [ ] 1.1 Add to `apps/web-platform/test/middleware.test.ts`:
  - [ ] 1.1.1 In "public paths" describe: `expect(isPublicPath("/api/internal/kb-drift-ingest")).toBe(true)` with a comment citing #4017 (HMAC-authed, no session cookie).
  - [ ] 1.1.2 In "prefix collision prevention" describe: `expect(isPublicPath("/api/internal")).toBe(false)` and `expect(isPublicPath("/api/internal/other-future-route")).toBe(false)`.
- [ ] 1.2 Run `./node_modules/.bin/vitest run test/middleware.test.ts` from `apps/web-platform/` — confirm 1.1.1 FAILS (route not yet public), 1.1.2 PASSES.

## Phase 2 — Core fix (GREEN)

- [ ] 2.1 `apps/web-platform/lib/routes.ts` — add exact path `"/api/internal/kb-drift-ingest"` to `PUBLIC_PATHS` next to `/api/inngest`, with sibling-style comment (HMAC gate is load-bearing; do NOT broaden to `/api/internal`).
- [ ] 2.2 `apps/web-platform/infra/kb-drift.tf` — change `doppler_secret.kb_drift_ingest_url.value` from `https://soleur.ai/...` to `https://app.soleur.ai/api/internal/kb-drift-ingest`. KEEP `lifecycle { ignore_changes = [value] }`.
- [ ] 2.3 (optional) Add a cross-reference comment to `apps/web-platform/test/server/internal/kb-drift-ingest-route.test.ts` pointing at the new PUBLIC_PATHS entry.

## Phase 3 — Verify

- [ ] 3.1 `./node_modules/.bin/vitest run test/middleware.test.ts test/server/internal/kb-drift-ingest-route.test.ts` — all pass.
- [ ] 3.2 `tsc --noEmit` clean.
- [ ] 3.3 `terraform fmt -check apps/web-platform/infra/kb-drift.tf` passes.
- [ ] 3.4 Verify greps: `grep -n "api/internal/kb-drift-ingest" apps/web-platform/lib/routes.ts` → 1 entry; `grep -nE '"/api/internal"' apps/web-platform/lib/routes.ts` → none.

## Phase 4 — Post-merge (CI-automatable, not operator-punt)

- [ ] 4.1 `gh workflow run "KB-drift walker"` after deploy; poll `gh run list --workflow "KB-drift walker" --limit 1 --json conclusion` → `success`.
- [ ] 4.2 `curl -sS -o /dev/null -w '%{http_code}' -X POST https://app.soleur.ai/api/internal/kb-drift-ingest -H 'Content-Type: application/json' --data '{}'` → `401` (not 307/405).
