---
feature: app-releases-page
issue: 5958
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-07-03-feat-app-releases-page-plan.md
status: ready
---

# Tasks: In-App Releases Page

## Phase 0 — Preconditions (verify, no code)
- [ ] 0.1 Confirm `mintInstallationToken` + `REPO_OWNER`/`REPO_NAME` are exported from `server/inngest/functions/_cron-shared.ts` and that module has no Inngest-client import (clean to import from a route path).
- [ ] 0.2 Confirm `generateInstallationToken(id, { permissions, repositories })` scope works (`github-app.ts`).
- [ ] 0.3 Confirm vitest include globs (`vitest.config.ts`): `test/**/*.test.ts` (node) + `test/**/*.test.tsx` (jsdom) — place tests under `apps/web-platform/test/`.

## Phase 1 — Shared server module (build FIRST — contract before consumers)
- [ ] 1.1 Create `apps/web-platform/server/release-notes.ts`. **Move** from `cron-weekly-release-digest.ts`: `sanitizeReleases`, `stripPii`, `deriveTitle`, `RawGithubRelease`, `SanitizedRelease`, and the regex/byte-cap constants (`CO_AUTHORED_RE`, `EMAIL_RE`, `HANDLE_RE`, `SECURITY_DOWN_DETAIL_RE`, `VERSION_ONLY_TITLE_RE`, `MAX_RAW_BODY_CHARS`, `MAX_RELEASE_BODY_CHARS`, `MAX_DERIVED_TITLE_CHARS`).
- [ ] 1.2 Add `interface ReleaseCard { tag; title; bodyMarkdown; publishedAt; htmlUrl; securitySensitive }` and `async function fetchWebReleases(opts?: { limit?: number }): Promise<ReleaseCard[]>`.
- [ ] 1.3 In `fetchWebReleases`: mint via `mintInstallationToken({ tokenMinLifetimeMs, permissions: { contents: "read" }, repositories: [REPO_NAME] })` (import from `_cron-shared`).
- [ ] 1.4 **Paginate** `GET /repos/${REPO_OWNER}/${REPO_NAME}/releases?per_page=100&page=N` (Bearer token, `Accept: application/vnd.github+json`; non-200 → throw) until `limit` `web-v*` cards collected OR 5-page cap; on cap, `reportSilentFallback` op `releases-page-undercount`.
- [ ] 1.5 Filter each page: `/^web-v\d/.test(tag_name)` && `!draft` && `!prerelease`.
- [ ] 1.6 Sanitize via `sanitizeReleases`; map `published_at→publishedAt`, `html_url→htmlUrl`; per-card fallback body when `body===""` (security → "Security and stability improvements."; else "Behind-the-scenes improvements and fixes."); slice to `limit ?? 50`. **No server-side cache.**
- [ ] 1.7 Edit `cron-weekly-release-digest.ts`: replace local sanitize defs with `import { sanitizeReleases, type RawGithubRelease, type SanitizedRelease } from "@/server/release-notes"`. Keep `isHighlightEligible`. Run the cron digest suite → green.

## Phase 2 — API route
- [ ] 2.1 Create `apps/web-platform/app/api/dashboard/releases/route.ts` mirroring `api/dashboard/routines/route.ts`: `dynamic="force-dynamic"`, `getUser()` → 401, `try { NextResponse.json({ releases: await fetchWebReleases() }) } catch { Sentry.captureException(e, { tags: { surface: "releases-list" } }); 502 }`. HTTP handlers only.

## Phase 3 — Page + client surface
- [ ] 3.1 Create `apps/web-platform/app/(dashboard)/dashboard/releases/page.tsx` (mirror `dashboard/routines/page.tsx`): server component, auth gate → `/login`, `max-w-5xl px-6 py-8`, `<header>` "Releases" + "Everything we've shipped to Soleur, newest first.", `<Suspense>`.
- [ ] 3.2 Create `apps/web-platform/components/releases/releases-surface.tsx` (mirror `routines-surface.tsx`): `"use client"`, `useSWR(swrKeys.releasesList(), jsonFetcher)`, skeleton gated on `!data`.
- [ ] 3.3 Populated cards (Soleur tokens): mono tag, formatted `publishedAt`, gold "Latest" pill on first, `bodyMarkdown` via `<MarkdownRenderer>`, low-emphasis "View on GitHub" → `htmlUrl`.
- [ ] 3.4 States: `RefreshShimmer` while revalidating warm cache; `StaleRefreshBar onRetry={mutate}` when `error && data`; empty ("No releases yet") when `!error && releases.length===0`; cold error (`!data && error`) "Couldn't load releases — we're on it." + "Try again" = `mutate()`.

## Phase 4 — Registrations
- [ ] 4.1 `components/command-palette/nav-items.ts`: append `{ href: "/dashboard/releases", label: "Releases", seq: "g l" }` (no accel).
- [ ] 4.2 `app/(dashboard)/layout.tsx`: add `NAV_ICONS["/dashboard/releases"]` = rocket icon.
- [ ] 4.3 `lib/swr-config.ts`: add `releasesList: () => ["/api/dashboard/releases"] as const`.

## Phase 5 — Architecture (C4)
- [ ] 5.1 `knowledge-base/engineering/architecture/diagrams/model.c4`: add `webapp -> github "Reads release notes for the in-app Releases page" { technology "HTTPS (GitHub REST API)" }`. No `views.c4` change.
- [ ] 5.2 Run `test/c4-code-syntax.test.ts` + `c4-render.test.ts` → pass.

## Phase 6 — Tests (under `apps/web-platform/test/`)
- [ ] 6.1 `test/release-notes.test.ts`: `sanitizeReleases` (PII strip, security title-only, derive title); `fetchWebReleases` `web-v*`-only + draft/prerelease exclusion + `publishedAt` map; per-card fallback (never `""`); **pagination** (needed cards on page 2 → full `limit`); page-cap → `releases-page-undercount`.
- [ ] 6.2 `test/releases-route.test.ts`: 200 `{ releases }`; 401 unauth; 502 + Sentry tag `releases-list` on throw.
- [ ] 6.3 `test/components/releases-surface.test.tsx`: SWR-isolated — skeleton on `!data`, populated (+ View-on-GitHub, non-empty body), empty, cold error + Try again, stale chip does NOT replace feed. Add `releasesList` to the sign-out cache-clear suite if it enumerates keys.

## Phase 7 — Verify
- [ ] 7.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] 7.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/release-notes.test.ts test/releases-route.test.ts test/components/releases-surface.test.tsx` + the cron digest suite (Phase 1 regression) → green.
- [ ] 7.3 PR body uses `Closes #5958`.
