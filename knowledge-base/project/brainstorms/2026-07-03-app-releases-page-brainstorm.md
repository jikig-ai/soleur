---
date: 2026-07-03
topic: app-releases-page
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstormed
issue: 5958
---

# Brainstorm: In-App Releases Page

## What We're Building

A new authenticated dashboard page at `/dashboard/releases` that shows Soleur users the
history of app releases — "what changed since I last looked." It fetches the canonical
`web-v*` GitHub Releases at runtime through the app's existing authenticated GitHub client,
filters/groups them server-side for readability (drop chore/revert noise), and renders each
release's notes through the existing XSS-safe markdown renderer. The feed is reverse-chronological,
SWR-cached (ADR-067 tab-content-cache pattern), and registered in the sidebar nav + command
palette with a `g`-leader shortcut.

No new data store, no CHANGELOG.md, no manual per-release step — the page stays current on its
own because GitHub Releases (tagged `web-vX.Y.Z` by `reusable-release.yml`) are the source of truth.

## Why This Approach

- **GitHub Releases are already canonical.** There is no root `CHANGELOG.md`; `reusable-release.yml`
  cuts `web-vX.Y.Z` tags + GitHub Releases on merge (latest `web-v0.184.6`). Reading them at
  runtime means the page is definitionally in sync with what shipped — zero drift, zero maintenance.
- **All infrastructure already exists.** Authenticated octokit client (`server/github-api.ts`,
  5000 req/hr) + retry (`github-retry.ts`); XSS-safe markdown renderer
  (`components/ui/markdown-renderer.tsx` — react-markdown v10, no `rehype-raw`, HTML escaped by
  default); SWR dashboard caching (ADR-067); nav + palette wiring driven by `nav-items.ts`.
  A live precedent already fetches these releases: `cron-weekly-release-digest.ts`.
- **"Auto feed, cleaned up" resolves the curation tension.** CPO/CLO warned against a raw PR
  dump (internal churn, security-fix wording, unreleased signals). Rather than build a human/LLM
  curation store (bigger v1), v1 does server-side hygiene: filter to `web-v*`, drop chore/revert/
  bump entries, strip `Co-Authored-By` and security-exploit keywords, present clean cards.
  Full LLM curation (reusing the shipped digest cron's Anthropic step, persisted to DB) is an
  explicit v2 fast-follow if the cleaned feed still reads too developer-y.
- **In-app is the audience that cares.** Authenticated users asking "what's new?" are the readers;
  a public marketing `/releases` page is a different (acquisition/SEO) job, deferred.

## User-Brand Impact

- **Artifact:** the in-app Releases page (`/dashboard/releases` + its `/api/dashboard/releases`
  route) and the release-note content it renders.
- **Vector:** the page renders stale, wrong, or internal/unreleased release content to an
  authenticated user — breaching trust in what actually shipped, or leaking internal churn /
  security-fix detail.
- **Threshold:** `single-user incident`.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Content source | Runtime GitHub Releases API, `web-v*` only | Canonical, always fresh, zero maintenance |
| Curation posture (v1) | Auto feed + server-side hygiene (filter/sanitize/group) | Balances freshness vs. brand polish; avoids a curation store |
| Home / audience | In-app dashboard tab `/dashboard/releases` | Authenticated users are the audience that cares |
| Rendering | Reuse `markdown-renderer.tsx` as-is (no `rehype-raw`) | Already XSS-safe for CI/PR-authored content |
| Data fetch | Server route → SWR client surface (ADR-067) | Matches Inbox/Routines pattern; cache-clear on sign-out/workspace-switch |
| Freshness | Runtime fetch + short ISR/SWR revalidate | No redeploy-on-release, no manual step |
| Auth for GitHub | Existing app token (5000 req/hr), never anonymous | Rate-limit safe |
| Tag filtering | Anchor on a digit: `/^web-v\d/` | Excludes plugin `v3.x` tags (2244 tags interleave namespaces) |
| Nav + palette | Add to `nav-items.ts` with `g`-leader seq (candidate `g l`) | Nav drives palette + `?` overlay automatically |
| Visual design | Wireframe: `knowledge-base/product/design/releases/releases-page.pen` (+ screenshots/) | Approved by operator 2026-07-03 |

## Non-Goals (v1 — deferred)

- LLM-curated "What's New" brand-voice entries (v2 — reuse `cron-weekly-release-digest`'s
  Anthropic step + persist to DB).
- Public/unauthenticated `/releases` marketing page (acquisition/SEO — later, additive).
- Per-release detail pages, RSS feed, email digest, search/filtering.
- "New/unread" badges and per-user last-seen tracking.
- Per-entry screenshots/media.
- Plugin (`v3.x`) release stream (web-platform `web-v*` only for v1).

## Open Questions

1. **Shortcut key.** `g r` is taken (routines). Candidates: `g l` (reLeases) or `g e`. Decide at plan time.
2. **Grouping granularity.** Flat reverse-chron list vs. grouped by month or by semver major/minor.
   Lean flat for v1.
3. **How much hygiene is "enough"?** Exact drop-list (chore/revert/bump/deps) and whether to hide
   `prerelease`/`draft` releases (yes, hide). Confirm the sanitization regex set at plan time
   (reuse `feat-weekly-release-digest` patterns: strip `Co-Authored-By`, `\b(xss|rce|injection)\b`).
4. **Empty/error state.** What renders if the GitHub fetch fails or returns zero `web-v*` releases
   (graceful "couldn't load / no releases yet", Sentry-tagged).

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Reader is the end user seeking reassurance + discovery; ship a curated in-app "What's
New" feed for v1, defer public page and auto-generation extras. Chosen posture = "auto feed cleaned
up" as the YAGNI middle ground, with full curation as v2.

### Engineering (CTO)

**Summary:** Winner is runtime GitHub Releases REST API filtered to `web-v*`, reusing the existing
authenticated client + `markdown-renderer` (XSS-safe, do NOT add `rehype-raw`) with ISR/SWR caching
— Small (hours). Biggest risk: tag-namespace pollution (plugin `v3.x` vs app `web-v*`); filter
server-side on `/^web-v\d/`.

### Legal (CLO)

**Summary:** No material legal concern. Only genuine risks are auto-dumping raw commit/PR titles
(internal codenames, unreleased signals) and exploit-grade security-fix wording. Guardrail:
server-side hygiene before render — no raw dump, sanitize security wording. No specialist dispatch.

## Prior Art Leveraged

- `cron-weekly-release-digest.ts` (#5080) — live precedent for enumerating `web-v*` GitHub
  Releases + sanitization patterns (`/^web-v\d/`, strip `Co-Authored-By`, security-keyword regex).
- ADR-067 `feat-tab-content-cache` (PR #5639) — SWR dashboard-tab caching pattern (gate on `!data`,
  cache-clear on sign-out/workspace-switch).
- `feat-weekly-release-digest/tasks.md` Phase 2 — GitHub release fetch + escape-then-truncate order.
- `2026-03-19-app-versioning-brainstorm.md` — establishes `web-vX.Y.Z` + GitHub Releases as SoT.
- Nav/palette: `nav-items.ts` (`seq` single source of truth), `use-shortcuts.tsx` resolver.
