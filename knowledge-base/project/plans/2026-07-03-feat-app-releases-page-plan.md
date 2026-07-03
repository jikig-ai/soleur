---
title: "feat: In-App Releases Page (/dashboard/releases)"
type: feat
issue: 5958
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
date: 2026-07-03
branch: feat-app-releases-page
pr: 5956
brainstorm: knowledge-base/project/brainstorms/2026-07-03-app-releases-page-brainstorm.md
spec: knowledge-base/project/specs/feat-app-releases-page/spec.md
wireframe: knowledge-base/product/design/releases/releases-page.pen
---

# ✨ feat: In-App Releases Page (`/dashboard/releases`)

## Overview

Add an authenticated dashboard page showing users a reverse-chronological feed of Soleur's
`web-v*` GitHub Releases — "what changed since I last looked." It reuses the app's existing
GitHub App auth (least-privilege `contents: read` installation token) to fetch releases at
runtime, cleans them server-side (drop chore/revert noise, PII strip, security fixes rendered
title-only), and renders each release's notes through the existing XSS-safe markdown renderer.
Reached via sidebar nav + command palette `g l`. SWR-cached on the client (ADR-067).

**Effort: Small (hours).** All infrastructure exists — the only net-new artifacts are one shared
server module, one route, one page, one client surface, and thin registrations.

## Premise Validation

All references in the feature description are artifacts created earlier this same session:
issue **#5958** (OPEN, created 2026-07-03), draft PR **#5956** (OPEN), spec + brainstorm + wireframe
(all committed on `feat-app-releases-page`). No external/stale premises to validate. Mechanism
("runtime GitHub Releases fetch + new dashboard page") checked against the ADR corpus: **ADR-067**
(SWR client cache) is the relevant precedent to follow; no ADR rejects or conflicts with this
mechanism. Branch safety: on `feat-app-releases-page` (not main). ✅

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Codebase reality (verified) | Plan response |
|---|---|---|
| "existing authenticated GitHub client `server/github-api.ts`" | Canonical release-read path is `mintInstallationToken` (`_cron-shared.ts`) → `generateInstallationToken` (`github-app.ts`), scoped `contents:read`, used live by `cron-weekly-release-digest.ts`. `github-api.ts` is a generic REST wrapper. | Reuse the **installation-token** path (App auth, `hr-github-app-auth-not-pat`), inlined in the new shared module via the 3 clean primitives — NOT a PAT, NOT `github-api.ts`. |
| Sanitization "reuse `feat-weekly-release-digest` patterns" | `sanitizeReleases` + security/PII regexes live **inside** `cron-weekly-release-digest.ts`; importing them pulls the Inngest client. | **Extract** the pure sanitize family into `server/release-notes.ts` (single source of truth for the brand-critical `SECURITY_DOWN_DETAIL_RE`); cron imports them back. |
| Shortcut "candidate `g l`" (open question) | `g r` is taken by Routines (`nav-items.ts`). `g l` is free; ⌘L is browser-reserved → no `accel`. | **Resolved: `g l`, no accel** (mirrors Workstream/KB). |
| Markdown render "no `rehype-raw`" | `markdown-renderer.tsx` uses react-markdown + remark-gfm + rehype-highlight, no `rehype-raw`/`skipHtml` → HTML escaped by default. | Reuse as-is; **do NOT add `rehype-raw`**. |
| C4: GitHub external system | `github` system already modeled (`model.c4:210`, description includes "releases"); but there is **no `webapp → github` edge** (github edges come from engine/claude/contributor). | Add one `webapp -> github` "reads release notes" edge to `model.c4` (renders automatically — both views already include `github`). No ADR (reuses existing integration + credential boundary). |

## User-Brand Impact

**If this lands broken, the user experiences:** the Releases page shows nothing, an error, or a
blank feed where product updates should be — reading as an abandoned product.

**If this leaks, the user's trust is exposed via:** the feed rendering internal churn, an
unreleased/flagged feature, exploit-grade security-fix detail, or PII from a commit trailer — a
trust breach in what "shipped." Mitigated by the single-source `sanitizeReleases` (PII strip +
security fixes title-only + `web-v*`-only filter + draft/prerelease exclusion) and the escaped
markdown renderer.

**Brand-survival threshold:** `single-user incident`.

CPO sign-off: **carried forward from brainstorm Phase 0.5** (CPO assessed the feature; recommended
the "auto feed cleaned up" posture adopted here). `user-impact-reviewer` will run at PR review.

## Implementation Phases

### Phase 0 — Preconditions (verify, no code)
- Confirm `generateInstallationToken(installationId, { permissions, repositories })` accepts the
  least-privilege scope (verified: `github-app.ts:749`, `_cron-shared.ts:mintInstallationToken`).
- Confirm `createProbeOctokit` (`@/server/github/probe-octokit`) + the `GET /repos/{owner}/{repo}/installation`
  resolution are importable without cron/Inngest deps (verified: `_cron-shared.ts` imports them from
  clean modules).
- Confirm vitest include globs collect `test/**/*.test.ts(x)` (place tests under `apps/web-platform/test/`, not co-located).

### Phase 1 — Shared server module (the contract; build FIRST)
**Create `apps/web-platform/server/release-notes.ts`:**
- **Move** from `cron-weekly-release-digest.ts` (pure, no Inngest deps): `sanitizeReleases`, `stripPii`,
  `deriveTitle`, `RawGithubRelease`, `SanitizedRelease`, and the regex/byte-cap constants
  (`CO_AUTHORED_RE`, `EMAIL_RE`, `HANDLE_RE`, `SECURITY_DOWN_DETAIL_RE`, `VERSION_ONLY_TITLE_RE`,
  `MAX_RAW_BODY_CHARS`, `MAX_RELEASE_BODY_CHARS`, `MAX_DERIVED_TITLE_CHARS`).
- Add:
  ```ts
  export interface ReleaseCard {
    tag: string;           // "web-v0.184.6"
    title: string;         // sanitized/derived; never a bare version
    bodyMarkdown: string;  // sanitized markdown; ALWAYS non-empty (fallback applied) — see below
    publishedAt: string;   // ISO-8601
    htmlUrl: string;       // release.html_url — "View on GitHub" escape hatch for truncated notes (spec-flow Gap 7)
    securitySensitive: boolean;
  }
  export async function fetchWebReleases(opts?: { limit?: number }): Promise<ReleaseCard[]>
  ```
  - **Per-card fallback (spec-flow Gap 1+3 — a card must NEVER render blank):** after sanitize, if
    `body === ""`, set `bodyMarkdown` to `securitySensitive ? "Security and stability improvements." : "Behind-the-scenes improvements and fixes."`. (Empty-vs-error is already disambiguated by fetch failures
    throwing → 502; the fallback just keeps every card legible — no vanished cards.)
  - Mint via the **existing helper** (Kieran plan-review verified `_cron-shared.ts` has NO Inngest-client
    import — only node fs / probe-octokit / github-app / observability / redaction / a type-only import —
    so this is a clean reuse, NOT a third inline copy of a security-path recipe):
    `import { mintInstallationToken, REPO_OWNER, REPO_NAME } from "@/server/inngest/functions/_cron-shared"`
    then `mintInstallationToken({ tokenMinLifetimeMs, permissions: { contents: "read" }, repositories: [REPO_NAME] })`.
    (If a product module importing from `inngest/functions/` bothers review, extract those 3 symbols into a
    neutral `server/github/installation-token.ts` re-exported to existing callers — but do NOT re-inline.)
  - **Paginate** `GET /repos/${REPO_OWNER}/${REPO_NAME}/releases?per_page=100&page=N` (`Authorization: Bearer <token>`,
    `Accept: application/vnd.github+json`; non-200 → throw), collecting matching releases until `limit`
    `web-v*` cards are gathered OR a page cap (5 pages) is hit — mirror the cron's loop
    (`cron-weekly-release-digest.ts:397-420`). **This is load-bearing (DHH plan-review):** the repo cuts
    ~100 releases/week interleaving plugin `v3.x`; a single page filtered to `web-v*` can silently
    under-fill the feed to a handful of cards with no error. If the page cap is hit before `limit`, emit
    `reportSilentFallback` (op `releases-page-undercount`) — the same undercount signal the cron emits.
  - Filter each page: `/^web-v\d/.test(tag_name)` **AND** `!draft` **AND** `!prerelease` (anchor on the
    digit — plugin `v3.x` interleaves).
  - Sanitize via `sanitizeReleases`; map `published_at → publishedAt`, `html_url → htmlUrl`; apply the
    per-card fallback above; slice to `opts.limit ?? 50`.
  - **No server-side cache** (DHH/simplicity): `generateInstallationToken` already caches the token and
    the client SWR-caches the response (ADR-067); a per-instance module memo would not help under
    multi-instance load. Fetch on request; revisit only if GitHub rate-limit becomes a real ceiling.

**Edit `apps/web-platform/server/inngest/functions/cron-weekly-release-digest.ts`:**
- Replace the local sanitize definitions with `import { sanitizeReleases, type RawGithubRelease, type SanitizedRelease } from "@/server/release-notes";`.
- Keep the cron's own `isHighlightEligible` (plugin **or** web) — that's digest-specific and stays.
- Run the cron's existing tests to confirm green (`test/**release-digest**`).

### Phase 2 — API route
**Create `apps/web-platform/app/api/dashboard/releases/route.ts`** (mirror `api/dashboard/routines/route.ts`):
- `export const dynamic = "force-dynamic";`
- `createClient()` → `supabase.auth.getUser()`; `401 { error: "unauthorized" }` if no user (data is
  user-independent, but the surface stays authenticated — matches sibling routes).
- `try { return NextResponse.json({ releases: await fetchWebReleases() }) }`
- `catch (e) { Sentry.captureException(e, { tags: { surface: "releases-list" } }); return NextResponse.json({ error: "releases_query_error" }, { status: 502 }); }`
- Route file exports HTTP handlers only (`cq-nextjs-route-files-http-only-exports`).

### Phase 3 — Page + client surface
**Create `apps/web-platform/app/(dashboard)/dashboard/releases/page.tsx`** (mirror `dashboard/routines/page.tsx`):
- Server component, auth gate (redirect `/login` if no user), `max-w-5xl px-6 py-8`, `<header>` with
  title "Releases" + description "Everything we've shipped to Soleur, newest first." Wrap the client
  surface in `<Suspense>`.

**Create `apps/web-platform/components/releases/releases-surface.tsx`** (mirror `routines-surface.tsx`):
- `"use client"`; `useSWR(swrKeys.releasesList(), jsonFetcher)`.
- Skeleton gated on `!data` (never `isValidating`) — ADR-067; shimmer cards per wireframe frame 02.
- Populated: reverse-chron `ReleaseCard[]` → cards using Soleur tokens
  (`bg-soleur-bg-surface-1`, `border-soleur-border-default`, `text-soleur-text-primary/secondary`):
  mono version tag, right-aligned formatted `publishedAt`, gold "Latest" pill on the first card,
  `bodyMarkdown` via `<MarkdownRenderer>` (always non-empty per Phase 1 fallback), and a low-emphasis
  "View on GitHub" link → `htmlUrl` (spec-flow Gap 7 — escape hatch for truncated notes).
- **Stale-revalidation affordance (spec-flow Gap 2):** REUSE the existing canonical components — render
  `<StaleRefreshBar>` (`components/ui/stale-refresh-bar.tsx`) when `error && data` (calls `mutate()`, does
  NOT drop to the full-screen error state) and `<RefreshShimmer>` (`components/ui/refresh-shimmer.tsx`)
  while revalidating a warm cache — exactly as `inbox-surface.tsx` (:68, :84) and `routines-surface.tsx`
  do. Do not hand-roll a chip.
- Empty (`!error && data.releases.length === 0`): "No releases yet." (frame 03). Reachable only when
  GitHub genuinely returns zero `web-v*` releases (cards never vanish — Phase 1 fallback).
- Error, cold (`!data && error`): "Couldn't load releases — we're on it." + a "Try again" button
  calling SWR `mutate()` (NOT a full reload) (frame 04) — no dead end. Sentry fires server-side once
  per failed fetch (route), not per retry tap.

### Phase 4 — Registrations
- **`components/command-palette/nav-items.ts`:** append `{ href: "/dashboard/releases", label: "Releases", seq: "g l" }` (no `accel` — ⌘L browser-reserved). Nav rail + palette + `?` overlay derive automatically.
- **`app/(dashboard)/layout.tsx`:** add a `NAV_ICONS` entry keyed by `/dashboard/releases` (rocket icon, per wireframe).
- **`lib/swr-config.ts`:** add `releasesList: () => ["/api/dashboard/releases"] as const` to the `swrKeys` builder object (mirrors `routinesList`/`workstreamIssues` naming).

### Phase 5 — Architecture (C4)
- **`knowledge-base/engineering/architecture/diagrams/model.c4`:** add `webapp -> github "Reads release notes for the in-app Releases page" { technology "HTTPS (GitHub REST API)" }`. `github` is already included in the `context` and `containers` views, so the edge renders with no `views.c4` change.
- Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` to confirm the model still parses/renders.

### Phase 6 — Tests (place under `apps/web-platform/test/`)
- **`test/release-notes.test.ts`:** unit — `sanitizeReleases` (PII strip, security title-only, derive
  title from body); `fetchWebReleases` filters to `web-v*`, excludes draft/prerelease, maps
  `publishedAt` (mock `fetch` + token mint; no LLM, no network).
- **`test/release-notes.test.ts` (pagination):** a 2-page mock where page 1 is mostly plugin `v3.x` tags
  and the `web-v*` cards needed to reach `limit` are on page 2 → assert `fetchWebReleases` paginates and
  returns the full `limit`; and a page-cap case → assert `reportSilentFallback` (`releases-page-undercount`)
  fires.
- **`test/releases-route.test.ts`:** route returns `{ releases }` on success; 401 unauthenticated; 502
  + Sentry tag `releases-list` on fetch throw (mock `fetchWebReleases`).
- **`test/components/releases-surface.test.tsx`:** SWR-isolated (fresh `SWRConfig` + `new Map()`) —
  loading skeleton on `!data`; populated cards (incl. "View on GitHub" link + non-empty body); genuine
  empty state; cold error + "Try again"; **stale-revalidation chip** (`error && data`) does NOT replace
  the feed. Assert cache-clear on sign-out is covered by the existing `swr-cache-clear-on-signout` suite
  (add `releases` key if that suite enumerates keys).
- **`test/release-notes.test.ts` (extend):** assert the per-card fallback — a release with an empty body
  yields "Behind-the-scenes improvements and fixes."; a security-sensitive release yields "Security and
  stability improvements." and `bodyMarkdown` is never `""`.

### Phase 7 — Verify
- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
- `cd apps/web-platform && ./node_modules/.bin/vitest run test/release-notes.test.ts test/releases-route.test.ts test/components/releases-surface.test.tsx` + the cron digest suite (regression from Phase 1).

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `server/release-notes.ts` exists; `sanitizeReleases` + `SECURITY_DOWN_DETAIL_RE` are defined **only** there (`git grep -l "SECURITY_DOWN_DETAIL_RE" apps/web-platform` → exactly one file, `release-notes.ts`; the cron re-imports only `sanitizeReleases` + the 2 types, so it carries zero `SECURITY_DOWN_DETAIL_RE` references).
- [ ] `fetchWebReleases` returns only tags matching `/^web-v\d/`, excludes `draft`/`prerelease` (unit test asserts a mixed fixture: `web-v0.1.0`, plugin `v3.1.0`, a draft `web-v9.9.9`, a `prerelease` → returns 1).
- [ ] `fetchWebReleases` **paginates** to reach `limit` when early pages are mostly plugin tags (fixture with needed `web-v*` on page 2 → full `limit` returned); page-cap-before-`limit` emits `reportSilentFallback` op `releases-page-undercount`.
- [ ] `/api/dashboard/releases` returns `{ releases: ReleaseCard[] }` (200), `401` unauthenticated, `502` + `Sentry` tag `surface: releases-list` on fetch throw.
- [ ] `/dashboard/releases` renders reverse-chron cards; unauthenticated access redirects to `/login` (reuses the dashboard auth guard — confirm it preserves `returnTo` like Inbox/Routines; if the shared guard lacks it, that is a pre-existing cross-page gap, scope-out).
- [ ] Loading skeleton gates on `!data`; **cold error** (`!data && error`) shows full-screen "Try again" (calls `mutate()`, no reload); **stale-revalidation** (`error && data`) shows a non-blocking "Couldn't refresh" chip, not the full-screen error.
- [ ] Empty state ("No releases yet") renders ONLY when the list is genuinely empty (`!error && releases.length === 0`); a card is never dropped for an empty/stripped body.
- [ ] Every card `bodyMarkdown` is non-empty: security-withheld → "Security and stability improvements."; otherwise-empty → "Behind-the-scenes improvements and fixes." (unit test on `fetchWebReleases`).
- [ ] Each card has a "View on GitHub" link → the release `htmlUrl`.
- [ ] `nav-items.ts` has `{ href:"/dashboard/releases", label:"Releases", seq:"g l" }` (no accel); `g l` navigates; palette lists "Releases" with the `g l` hint; `?` overlay shows the row.
- [ ] `markdown-renderer.tsx` unchanged (no `rehype-raw` added).
- [ ] `model.c4` has the `webapp -> github` releases edge; `c4-code-syntax` + `c4-render` tests pass.
- [ ] `tsc --noEmit` clean; new tests + cron digest regression suite green.
- [ ] PR body uses `Closes #5958`.

## Domain Review

**Domains relevant:** Product, Engineering, Legal (carried forward from brainstorm Phase 0.5 `## Domain Assessments`).

### Engineering (CTO)
**Status:** reviewed (carry-forward). **Assessment:** Runtime GitHub Releases via existing App-auth
client + reuse `markdown-renderer` (no `rehype-raw`) + SWR/ISR — Small. Biggest risk: tag-namespace
pollution (plugin `v3.x` vs `web-v*`) → server-side `/^web-v\d/` filter (encoded in Phase 1 + AC).

### Legal (CLO)
**Status:** reviewed (carry-forward). **Assessment:** No material legal concern. Only risks: raw
commit/PR dump (internal codenames/unreleased signals) + exploit-grade security-fix wording →
mitigated by single-source `sanitizeReleases` (curate-before-render; security fixes title-only). No
specialist dispatch.

### Product/UX Gate
**Tier:** blocking (new `app/**/page.tsx` + `components/**/*.tsx` — mechanical override).
**Decision:** reviewed.
**Agents invoked:** cpo (brainstorm carry-forward), ux-design-lead (brainstorm Phase 3.55 — `.pen`
produced + operator-approved 2026-07-03), spec-flow-analyzer (this plan phase).
**Skipped specialists:** copywriter — none recommended by a leader; the only original microcopy is the
page header/description + state strings, all fixed in the wireframe + spec.
**Pencil available:** yes — `knowledge-base/product/design/releases/releases-page.pen` (+ 4 screenshots) committed.

#### Findings
Wireframe (4 frames: populated-in-shell, loading, empty, error) approved by operator. spec-flow-analyzer
run on the flows; its P0/P1 gaps are folded into Phase 1/3 + ACs:
- **Gap 1+3 (P0/P1):** per-card fallback body (cards never blank) → disambiguates empty (⟺ zero `web-v*`) from error (fetch throws → 502).
- **Gap 2 (P1):** stale-revalidation "Couldn't refresh" chip instead of a silently-stale feed.
- **Gap 4 (P1):** unauth → `/login`; reuse dashboard guard's `returnTo` (Inbox/Routines) or scope-out as a pre-existing cross-page gap.
- **Gap 5 (P1):** "Try again" = SWR `mutate()`; Sentry fires once per server-side failure, not per tap.
- **Gap 7 (P2):** per-card "View on GitHub" link (`htmlUrl`) as the truncation escape hatch.
- **Gap 6 (P2):** `g l` resolved + asserted in nav/palette/overlay tests.

## Observability

```yaml
liveness_signal:
  what: error-rate on Sentry surface tag `releases-list` (user-triggered read route; no background job / SLA)
  cadence: on request
  alert_target: Sentry issues (surface:releases-list) — same posture as sibling read routes (routines-list); no new alert rule/uptime monitor (YAGNI, non-critical page)
  configured_in: apps/web-platform/app/api/dashboard/releases/route.ts (Sentry.captureException tag)
error_reporting:
  destination: Sentry (existing @sentry/nextjs)
  fail_loud: true — route returns 502 + captureException; UI shows error state, never a silent blank
failure_modes:
  - mode: GitHub API 5xx / rate-limit / token-mint failure
    detection: Sentry.captureException tag surface:releases-list
    alert_route: Sentry issues
  - mode: zero web-v* releases returned
    detection: not an error — UI empty state ("No releases yet")
    alert_route: n/a (expected state)
  - mode: page cap hit before `limit` web-v* cards collected (feed under-fills)
    detection: reportSilentFallback op `releases-page-undercount` → Sentry
    alert_route: Sentry issues
logs:
  where: Sentry (exception + tags); no new log sink
  retention: Sentry default
discoverability_test:
  command: "curl -s -H 'Cookie: <session>' https://<host>/api/dashboard/releases | jq '.releases | length'  # NO ssh"
  expected_output: ">=1 for a healthy prod; {\"error\":\"releases_query_error\"} with a matching Sentry issue on failure"
```

Not a blind execution surface (normal Next.js route, inspectable) → Phase 2.9.2 N/A. No soak/time-gated
close criterion → Phase 2.9.1 N/A.

## Architecture Decision (ADR/C4)

**ADR:** none. This reuses the existing GitHub App integration + credential boundary + the SWR page
pattern (ADR-067); it introduces no new substrate, tenancy, or trust boundary. A future engineer
reading the existing ADRs + C4 would not be misled — the data-source decision is documented in the
spec + this plan, and the C4 edge below.

### C4 views
Enumeration checked against all three `.c4` files:
- **External human actor:** none new — the reader is the existing `founder` actor (`model.c4:8`), already modeled with a `founder -> dashboard` browse edge.
- **External system:** `github` — already modeled (`model.c4:210`, description already includes "releases").
- **Container / data store:** none new (no DB; reads GitHub at runtime).
- **Access relationship:** **NEW** — `webapp` reads release notes from `github`. No `webapp -> github` edge exists today (github edges come from `engine`, `claude`, `contributor`, and `github -> webapp`). **In-scope task (Phase 5):** add `webapp -> github "Reads release notes for the in-app Releases page" { technology "HTTPS (GitHub REST API)" }` to `model.c4`. Both `context` and `containers` views already `include github` + `webapp`, so it renders with no `views.c4` edit.

### Sequencing
Single PR; the C4 edge ships with the feature.

## Open Code-Review Overlap

1 open scope-out touches a planned file: **#2193** (unify billing past_due/unpaid banners + extract
`useDismissiblePersistent`) references `app/(dashboard)/layout.tsx`. **Disposition: Acknowledge** —
different concern (billing banners vs. adding a `NAV_ICONS` entry); this plan only appends one icon
mapping and does not touch the banner code. #2193 remains open.

## GDPR / IaC Gates
- **GDPR (2.7):** trigger (b) fired (threshold = single-user incident), but assessed as **no
  regulated-data surface** — reads public GitHub release notes; the only personal-data touch is the
  reused Supabase `getUser()` auth gate (no new processing, no schema/migration, no new PII). The one
  content risk (leaking internal/security detail) is a brand risk handled by `sanitizeReleases`, not a
  GDPR gap. No findings.
- **IaC (2.8):** skip — no new infra. Reuses the already-provisioned GitHub App private key (same
  credential the ~10 crons use); no new Doppler secret, server, cron, or DNS.

## Plan Review (applied)

Reviewed by DHH + Kieran + code-simplicity + spec-flow-analyzer. Applied:
- **Pagination (DHH):** fetch pages until `limit` `web-v*` cards or a 5-page cap; emit `releases-page-undercount` on cap — fixes silent under-fill (~100 releases/week interleave plugin tags).
- **Cut the TTL memo cache (DHH + Kieran):** token already cached, SWR caches client-side; per-instance memo doesn't help under load.
- **Reuse `mintInstallationToken` (Kieran):** `_cron-shared.ts` has no Inngest-client import → clean reuse, avoids a third inline copy of the security-path mint recipe.
- **`releasesList` swr key + single-file `SECURITY_DOWN_DETAIL_RE` grep AC (Kieran):** naming + AC accuracy.
- **Trimmed the empty-vs-error "epistemology" prose (DHH).**
- **Reuse `StaleRefreshBar`/`RefreshShimmer` (grep):** Gap-2 affordance is an existing component used by Inbox + Routines.

Reasoned partial-accept: kept the stale-revalidation affordance (DHH suggested cutting) — it is a 1-line reuse of `StaleRefreshBar`, and omitting it would make Releases the only dashboard sibling that silently goes stale. code-simplicity-reviewer returned a degenerate response (no usable findings); its concern set overlaps DHH's, which was applied.

## Risks & Sharp Edges
- **Tag-namespace pollution + under-fill (DHH plan-review):** 2244 tags interleave plugin `v3.x` and app
  `web-v*` at ~100 releases/week. Filter must anchor on the digit (`/^web-v\d/`) **AND** paginate until
  `limit` `web-v*` cards are collected (a single `per_page=100` page can be almost all plugin tags →
  silent under-fill to a handful of cards). Encoded in Phase 1 + AC + the `releases-page-undercount` signal.
- **Do NOT add `rehype-raw`** to `markdown-renderer.tsx` — it is XSS-safe today precisely because HTML
  is escaped by default; adding raw HTML support would render CI/PR-authored content unsafely.
- **Security-regex single source:** `SECURITY_DOWN_DETAIL_RE` must be defined once (in
  `release-notes.ts`) — duplicating it into the route risks drift on a brand-critical filter.
- **Installation resolution:** `fetchWebReleases` mints against `GET /repos/jikig-ai/soleur/installation`
  (the app's own repo installation), NOT a user's connected-repo installation — releases are identical
  for all users.
- **Cron regression:** Phase 1 moves sanitize out of the cron; run the cron digest suite in Phase 7 to
  confirm the import swap kept it green.
- **`## User-Brand Impact` completeness:** the section above is filled (artifact/vector/threshold) — a
  placeholder/empty section would fail `deepen-plan` Phase 4.6.
