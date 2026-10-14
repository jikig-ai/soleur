---
feature: app-releases-page
issue: 5958
lane: cross-domain
brand_survival_threshold: single-user incident
status: specced
date: 2026-07-03
brainstorm: knowledge-base/project/brainstorms/2026-07-03-app-releases-page-brainstorm.md
wireframe: knowledge-base/product/design/releases/releases-page.pen
---

# Spec: In-App Releases Page

## Problem Statement

Soleur ships continuously (multiple releases/day) but users have no in-app way to see what
changed. Release history exists only as `web-v*` GitHub Releases — invisible to the people using
the product. Users lack a "what's new since I last looked" surface, which both hides shipped value
and reads as an unmaintained product.

## Goals

- Give authenticated users a reverse-chronological, readable history of Soleur app releases inside
  the dashboard.
- Stay current automatically from the canonical source (`web-v*` GitHub Releases) with zero
  per-release maintenance.
- Present releases as trustworthy product updates, not raw developer churn.

## Non-Goals

- LLM-curated brand-voice "What's New" entries (v2 fast-follow — reuse `cron-weekly-release-digest`
  Anthropic step + persist to DB).
- Public/unauthenticated `/releases` marketing page (later, additive).
- Per-release detail pages, RSS, email digest, search/filtering.
- "New/unread" badges or per-user last-seen tracking.
- Per-entry screenshots/media.
- Plugin (`v3.x`) release stream — web-platform `web-v*` only.

## Functional Requirements

- **FR1** — A new dashboard page at `/dashboard/releases`: server component → `<Suspense>` →
  client SWR surface, auth-gated (redirect `/login` if no user), `max-w-5xl px-6 py-8` layout,
  `<header>` with title "Releases" + one-line description. Matches Inbox/Routines. (Wireframe frame 01.)
- **FR2** — A reverse-chronological feed of release cards. Each card: version tag (mono,
  e.g. `web-v0.184.6`), formatted date, "Latest" badge on the first/newest card, and release notes
  rendered as markdown bullets. (Wireframe frame 01.)
- **FR3** — Server route `/api/dashboard/releases` fetches GitHub Releases, filters to `/^web-v\d/`,
  excludes `draft` and `prerelease`, returns normalized `{ tag, name, date, bodyMarkdown }[]`.
- **FR4** — Server-side content hygiene before returning: drop chore/revert/bump/deps-only lines,
  strip `Co-Authored-By` trailers, and redact security-exploit detail
  (`\b(xss|rce|injection)\b`-class), reusing `feat-weekly-release-digest` sanitization patterns.
  Escape-then-truncate order.
- **FR5** — Notes render through existing `components/ui/markdown-renderer.tsx` unchanged (react-
  markdown, no `rehype-raw` — HTML escaped by default). Do NOT add `rehype-raw`.
- **FR6** — Loading skeleton (shimmer cards), empty state ("No releases yet"), and error state
  ("Couldn't load releases — we're on it.", Sentry-tagged `surface: releases-list`). (Wireframe
  frames 02–04.)
- **FR7** — Register the page in `components/command-palette/nav-items.ts` (sidebar nav + palette +
  `?` overlay derive automatically). `g`-leader sequence (candidate `g l`; `g r` is taken by
  routines). No browser-reserved `accel`.

## Technical Requirements

- **TR1** — Fetch via the existing authenticated GitHub client (`server/github-api.ts` +
  `github-retry.ts`), using the app token (5000 req/hr). Never anonymous (60/hr). Paginate
  `releases?per_page=100` as needed.
- **TR2** — Freshness: runtime fetch with short SWR/ISR revalidate; no redeploy-on-release, no
  manual step. Client uses SWR per ADR-067 (`feat-tab-content-cache`): distinct cache key, gate
  skeleton on `!data` (never `isValidating`), cache-cleared on sign-out/workspace-switch.
- **TR3** — Tag filtering anchored on a digit (`/^web-v\d/`) to exclude interleaved plugin `v3.x`
  tags (2244 tags across namespaces). Filter server-side.
- **TR4** — Use Soleur Tailwind v4 tokens (`soleur-text-primary`, `soleur-text-secondary`,
  `soleur-bg-*`, `soleur-border-default`). Card treatment matches existing dashboard cards.
- **TR5** — Tests: mock GitHub API via `page.route()`; SWR test isolation (fresh `SWRConfig` +
  `new Map()` per test); assert cache-clear on sign-out; cover empty/error states.

## Brand-Survival Threshold

`single-user incident`. The page renders CI/PR-authored content to authenticated users; a single
user seeing stale/wrong/internal/exploit-detail release content is a trust breach. Enforced by
FR4/FR5 (server-side hygiene + escaped markdown) and FR6 (graceful empty/error states).

## Open Questions (resolve at plan time)

1. Shortcut key: `g l` vs `g e`.
2. Grouping: flat reverse-chron (default) vs. grouped by month/semver.
3. Exact hygiene drop-list + whether the sanitizer is shared with the digest cron or duplicated.
