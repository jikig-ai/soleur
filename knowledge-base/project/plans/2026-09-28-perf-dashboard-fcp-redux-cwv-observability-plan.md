---
title: "perf(webapp): dashboard FCP redux — mount fan-out dedup + Core Web Vitals observability (field RUM + skill encoding)"
date: 2026-09-28
slug: perf-dashboard-fcp-redux-cwv-observability
branch: feat-one-shot-9178-fcp-redux-cwv
issue: 9178
closes: [9178, 8985]
lane: cross-domain
type: perf
priority: high
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: false
---

# perf(webapp): dashboard FCP redux — mount fan-out dedup + Core Web Vitals observability

**Research agents used:** sequential-fallback — this planning run executes inside a Task subagent with no Task fan-out available; repo research, learnings sweep, premise validation, functional-overlap and external-docs checks applied inline (precedent: `knowledge-base/project/plans/2026-09-25-perf-dashboard-section-load-latency-plan.md`, `2026-09-26-perf-dashboard-cold-load-first-paint-plan.md`).

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-09-28 (same session as authoring — sequential-fallback deepen pass, no Task fan-out in this runtime)
**Sections enhanced:** Proposed Solution, Technical Approach, Implementation Phases, Alternatives, Research Insights, Acceptance Criteria, Risks
**Passes applied inline:** halt gates 4.5 (network-outage — Hypotheses cover all four layers with artifacts), 4.6 (user-brand — `single-user incident`), 4.7 (observability — 5-field schema, allowlisted probe verb `grep`, literal expected output `"1"`), 4.8 (PAT — zero hits), 4.9 (UI-wireframe — committed `dashboard-load-states.pen` referenced), 4.10 (encryption posture — existing Sentry edge, no new store), 4.11 (guard contract — `lint-guard-contract.py` green, structural assembly, 6-row matrix); 4.4 precedent-diff (follow-through script mirrors `dashboard-cold-tiers-8978.sh`/`reconcile-ff-only-sentry-4977.sh`; no new scheduled job — consumed by the existing sweeper); 4.45 verify-the-negative (`sendDefaultPii` confirmed unset in both Sentry configs; raw-fetch census = 17 sites measured, not asserted); quality checks (issue/PR states verified live: #9178 OPEN, #9034 MERGED, #8794 MERGED, #8719 CLOSED; squash `36272b43ed` confirmed ancestor of `origin/main`; `follow-through` label exists).

### Key Improvements

1. **Field-RUM mechanism corrected by installed-SDK source, not docs.** The docs-suggested `webVitalsIntegration()` standalone emits CLS/LCP/INP spans ONLY under `traceLifecycle: 'stream'` or `_experiments.enableStandalone{Cls,Lcp}Spans`, and FCP/TTFB — the metrics this issue exists to measure — have no standalone path at all (`WebVitalName = 'cls' | 'inp' | 'lcp'`). Required mechanism is `browserTracingIntegration()` + `tracesSampler` (probe marker → 1.0, real sessions → 0.1). Source: `node_modules/@sentry/browser@10.59.0` `webVitals.js` `setup()` + `options.d.ts`.
2. **Middleware-auth leg closed by prior art.** ADR-253's 2026-09-26 amendment already rejected a `getUser` verdict cache by measurement — the plan documents this as verify-only and keeps `middleware.ts` out of the diff entirely.
3. **Dedup is migration, not new machinery.** SWR + `swrKeys` + `dedupingInterval` already exist (ADR-067); the duplicate fan-out is a parallel raw-`fetch` channel (`use-active-repo.ts`'s module latch can't join SWR flights). Plan-time census: 17 raw `fetch("/api/` sites in the mount-surface set → guard baseline.

### New Considerations Discovered

- Client-side `tracesSampler` cannot see `x-perf-probe` headers — the probe arms a `localStorage` marker instead (`soleur.perf-probe`), set via `page.addInitScript` before navigation.
- New event classes (transactions, spans) bypass the existing `beforeSend` scrub — `beforeSendTransaction` + `beforeSendSpan` must reuse the same helpers, asserted across all three sinks.
- UX gate satisfied by the committed `dashboard-load-states.pen` (Phase 4.9 verifier passes: the file is tracked and referenced) — this change adds no new visual state; the work phase extends that `.pen` only if the fixed deferred set needs a depicted state it lacks.

## Overview

Issue #9178 carries two coupled workstreams.

**Workstream A — dashboard FCP redux.** Post-#9034 (squash `36272b43ed`, deployed 2026-09-28) every remote Supabase/Auth/PostgREST leg is `Promise.race`-bounded at ≤10 s, yet the dashboard mount still fires ~15–18 `/api/*` fetches per navigation with observed same-mount duplicates (`workspace/active-repo` ×3–4, `dashboard/foundation-status` ×3, `dashboard/today` ×2, `inbox` ×2, `list-memberships` ×2, `byok/effective-status` ×2). The plan migrates every mount-time raw-`fetch` consumer onto the shared SWR key space (ADR-067), adds a post-first-paint deferral primitive for below-the-fold/non-critical keys, and re-examines middleware-auth caching against the ADR-253 amendment — which already rejected a `getUser` verdict cache by measurement and therefore bounds what is permissible there.

**Workstream B — Core Web Vitals observability.** Field RUM lands via `Sentry.browserTracingIntegration()` in the already-installed `@sentry/nextjs@^10.59.0`: pageload/navigation transactions carry LCP/CLS/INP/FCP/TTFB as measurements (verified against the installed SDK — the standalone `webVitalsIntegration` only emits without tracing under `traceLifecycle: 'stream'`, and covers CLS/LCP/INP only; FCP/TTFB ride pageload transactions, which this issue needs). `tracesSampler` returns `1.0` when the perf probe's client-side marker is armed and a low rate otherwise. The pattern is then encoded into the Soleur plugin so any Soleur-built webapp ships CWV observability by default: a `webapp-cwv-observability` recipe reference under `plugins/soleur/skills/plan/references/`, a pointer in the plan Phase 2.9 Observability gate, and the live-verify `perf-probe.ts` extended to emit a per-mount duplicate census and capture paint/vitals entries.

**Targets (issue-stated):** warm FCP ≤500 ms (closes #8978's unmet AC arm); cold FCP p50 <2 s; zero same-mount duplicate GETs in the probe census; field vitals (LCP/INP/CLS/FCP/TTFB) landing in Sentry.

## Problem Statement

`app.soleur.ai/dashboard` — every authenticated user experiences 0.9–9 s cold first-paint and a mount-fan-out waterfall on every navigation. Evidence: #8978 post-deploy probe comment (2026-09-28, comment-5873784966) — warm FCP 572 ms vs the ≲500 ms AC; cold p50 ~2.0 s, worst 9.08 s; #8985 re-evaluation comment (2026-09-28, comment-5873791940) — the duplicate-fetch census. PIR: `knowledge-base/engineering/operations/post-mortems/2026-09-28-dashboard-cold-tiers-unbounded-supabase-legs-postmortem.md`.

The duplication is *structural*, not incidental: `hooks/use-active-repo.ts` keeps its own module-level `inFlight` latch and raw `fetch("/api/workspace/active-repo")` while `useConversations`, `dashboard/page.tsx`, and `conversations-nav-badge.tsx` read `swrKeys.workspaceActiveRepo()` — two parallel channels for the same endpoint; a raw-fetch consumer's poll cannot join an SWR flight and vice versa. `org-switcher-container.tsx`, `no-api-key-banner.tsx`, `pending-invite-banner-recovery.tsx`, and `use-team-names.tsx` likewise raw-fetch endpoints that have no `swrKeys` entry at all.

Meanwhile every perf claim is backed only by the synthetic `perf-probe.ts` (lab, one machine, `x-perf-probe`-armed). No field RUM exists: `sentry.client.config.ts` sets `tracesSampleRate: 0` and ships no vitals integration, so LCP/INP/CLS/FCP/TTFB from real sessions are entirely dark.

## Proposed Solution

1. **Mount-fetch contract (amends ADR-067).** Every mount-time `/api/*` GET in the dashboard shell goes through `useSWR` with a `swrKeys.*` tuple — raw `fetch()` GETs on the mount path are the defect class. SWR's per-key in-flight coalescing + `dedupingInterval` collapse duplicates *across* consumers, which the per-hook `inFlight` latch cannot do (it is blind to the SWR channel and to sequential mounts after the latch clears).
2. **Post-FCP deferral primitive.** A new `hooks/use-post-fcp.ts` (boolean that flips after first paint via `requestIdleCallback` with a `setTimeout` fallback) gates non-critical SWR keys to `null` until after paint — applied to nav-badge counts, releases, team-names, and other non-above-the-fold fetches. Above-fold content keys (today, conversations, inbox badge on the inbox route) stay ungated.
3. **Middleware-auth: verify-only.** ADR-253's 2026-09-26 amendment already rejected a `getUser` verdict cache by measurement; revocation/T&C positive-verdict caches (30 s, allow-direction-only) are already live, and the in-flight joiner already dedupes concurrent misses. This plan adds NO auth caching — it asserts the existing joiner covers every `/api/*` mount request and records the constraint.
4. **Field RUM.** `Sentry.browserTracingIntegration()` in `sentry.client.config.ts` (it auto-registers `webVitalsIntegration`) with a `tracesSampler`: `1.0` when the probe marker is present (the probe arms it via `localStorage`/`sessionStorage` before navigation — `tracesSampler` receives no request headers client-side), `0.1` otherwise. `sendDefaultPii` stays unset; the existing scrub chain extends to `beforeSendTransaction` and `beforeSendSpan` (both exist on the installed SDK — `options.d.ts`), asserted by a test that a transaction/vital payload carries no user identifier — the same boundary the `no-raw-id` learning (#8719/PR #8794) prescribes.
5. **Skill encoding.** `plugins/soleur/skills/plan/references/webapp-cwv-observability.md` recipe + pointer lines at plan Phase 2.9 and in `spec-templates`, so the next Soleur-generated webapp gets the wiring in its plan rather than as a retrofit.

## Technical Approach

### Architecture

- **Dedup channel:** `swrKeys` gains `listMemberships()`, `byokEffectiveStatus()`, `pendingInvites()`, `teamNames()`; `useActiveRepo()` re-implements on `useSWR(swrKeys.workspaceActiveRepo(), …)` preserving (a) keep-last-known on transient failure (SWR retains `data` across revalidation errors — map `error` to a no-op when `data` is set), (b) focus revalidation (`revalidateOnFocus` already `true` globally), (c) the 2 s `cloning` poll → `refreshInterval: (d) => d?.repoStatus === "cloning" ? 2000 : 0` (self-stopping equivalent), (d) the `fellBackToSolo` J5 signal.
- **Census, not enumeration:** the perf probe gains a per-mount same-key duplicate count and the dedup guard asserts no mount-time raw-`fetch` GET remains on the enumerated consumer set — the population is "every GET fired during a `/dashboard` navigation", derived from the probe's `requests[]`, not a hand-listed component set (a hand list is a snapshot, not an assembly).
- **Deferral:** `usePostFcp()` returns `false` until `requestIdleCallback` (or `setTimeout(0)` fallback) fires post-first-paint; consumers pass `null` keys until then so deferred surfaces still render their last-known/cached state instantly.
- **RUM:** `browserTracingIntegration()` + `tracesSampler` (probe marker → `1.0`, else `0.1`). SDK-source-verified mechanism (`apps/web-platform/node_modules/@sentry/browser/build/npm/esm/dev/integrations/webVitals.js`, `setup()`): standalone `webVitalsIntegration` emits CLS/LCP/INP spans ONLY when `traceLifecycle: 'stream'` is set (or the `_experiments.enableStandaloneCls/LcpSpans` flags), and pageload-span measurement attachment requires a pageload span to exist — i.e., `browserTracingIntegration`. FCP/TTFB have no standalone-span path at all (vital name set is `cls|inp|lcp`), so the pageload-transaction arm is required for the FCP field data this issue exists to measure. Surface: Sentry Web Vitals dashboard + a follow-through Sentry-scan script.
- **Middleware:** untouched. `middleware.ts` is deliberately NOT in Files to Edit — the getUser verdict-cache question is settled by the ADR-253 amendment's measured rejection, and keeping the auth surface byte-identical shrinks the review blast radius.

### Implementation Phases

#### Phase 1: Probe census + dedup migration

- Extend `scripts/live-verify/perf-probe.ts`: emit a per-sample `duplicates` table (same path+method GETs counted >1 within one navigation) and capture `paint`/`layout-shift`/LCP entries already partially present — add `ttfb`/`fcp`/`lcp`/`cls` fields to `NavSample` where the headless shell's `PerformanceObserver` supports them.
- Migrate the raw-fetch mount consumers to shared keys: `use-active-repo.ts`, `org-switcher-container.tsx` (list-memberships; keep `WORKSPACE_LOGO_CHANGED_EVENT` re-poll via `mutate`), `no-api-key-banner.tsx` (byok/effective-status), `pending-invite-banner-recovery.tsx`, `use-team-names.tsx`; normalize any `/api/inbox` consumer not on `swrKeys.inbox(status)`.
- New `hooks/use-post-fcp.ts` + gate the non-critical keys (nav-badge counts, releases, team-names; foundation-status decision driven by the census — if it sits above the fold on the desktop layout it stays ungated).
- Success: probe `duplicates` table is empty on a warm dashboard navigation; mount GET count drops from ~15–18 to ≤~10.
- Estimated effort: medium — the hook migrations are mechanical; the J5/cloning-poll parity is the care point.

#### Phase 2: Field RUM + verification

- `sentry.client.config.ts`: add `Sentry.browserTracingIntegration()` to `integrations` and a `tracesSampler` — `1.0` when `localStorage.getItem("soleur.perf-probe") === "1"` (the probe sets it before navigation, client-side equivalent of the server `x-perf-probe` arm), `0.1` otherwise; `tracesSampleRate` is removed in favor of the sampler; `sendDefaultPii` stays unset.
- Extend the scrub boundary: `beforeSendTransaction` + `beforeSendSpan` reusing `scrubJwtFromEvent`/`stripUserContextFromEvent`/`stripPiiFromRecord` (transaction events and span payloads are new classes that bypass `beforeSend`).
- `perf-probe.ts`: set the probe marker (`page.addInitScript` / context storage) before navigations so probe runs sample at 1.0.
- Unit test: client config wires `browserTracingIntegration` + sampler arms at 1.0 under the marker and 0.1 otherwise; a captured transaction/vital payload contains no `user`/PII fields after the scrub chain.
- Post-deploy follow-through script `scripts/followthroughs/cwv-field-rum-9178.sh` (mirrors `dashboard-cold-tiers-8978.sh`): verifies vital-bearing pageload transactions land in Sentry for `GET /dashboard` sessions within 24 h of deploy.
- Success: vitals visible in Sentry; probe warm FCP ≤500 ms, cold p50 <2 s on re-measurement.
- Estimated effort: small-medium; quota/volume check (transaction rate at 0.1 on the real session population) is the open variable — confirm project ingest headroom during work.

#### Phase 3: Skill encoding + ADR/C4

- `plugins/soleur/skills/plan/references/webapp-cwv-observability.md` — the recipe: when `@sentry/nextjs` (or `@sentry/browser`) is present prefer `browserTracingIntegration` + a probe-armed `tracesSampler` + `beforeSendTransaction`/`beforeSendSpan` scrub reuse (with the standalone-`webVitalsIntegration`/`traceLifecycle: 'stream'` caveat documented — it covers CLS/LCP/INP only, never FCP/TTFB); else a `web-vitals`-package beacon endpoint spec with PII constraints; sampling/quota notes, verification commands, scrub-boundary requirement, dashboard/alert pointers.
- Pointer lines in `plugins/soleur/skills/plan/SKILL.md` Phase 2.9 and `plugins/soleur/skills/spec-templates/SKILL.md` so new-webapp plans emit CWV wiring by default.
- ADR-067 amendment (mount-fetch contract: mount-time GETs go through `swrKeys`, raw `fetch` GET on the mount path is a defect; post-FCP deferral primitive) + new ADR for the field-RUM choice (provisional ordinal — renumber sweep per Phase 2.10 rules if a sibling claims it).
- C4: verify `webapp -> sentry` edge description covers the vitals payload class (model.c4:780 edge); update the edge prose if it enumerates payload types.
- Success: recipe file exists and is referenced; ADR(s) committed; `c4-code-syntax`/`c4-render` tests green if `.c4` touched.

## Alternative Approaches Considered

| Approach | Disposition |
|---|---|
| `GET /api/dashboard/bootstrap` aggregator route (from #8985) | Rejected as primary: re-serializes what SWR already coalesces in parallel, adds a new endpoint + auth surface, and does nothing for the *deferral* half. Reconsidered only if post-migration count still dominates — recorded, not built. |
| Per-request `getUser` verdict cache | REJECTED — ADR-253 amendment (2026-09-26) rejected it by measurement; re-opening requires re-running the probe showing `mw-auth` dominating, which current data contradicts. |
| First-party beacon endpoint (`useReportWebVitals` → `/api/vitals` → internal store) | Rejected: new API route + new persistent store (GDPR/encryption-posture/RLS surface) to duplicate what the installed Sentry SDK already ships; Sentry is the established telemetry vendor (ADR-031). |
| Standalone `webVitalsIntegration()` (no transaction tracing) | Rejected by SDK-source verification: standalone emission of CLS/LCP/INP spans requires `traceLifecycle: 'stream'`, and FCP/TTFB exist only as pageload-transaction measurements — the metric this issue is about has no standalone path (`webVitals.js` `setup()`, installed `@sentry/browser` 10.59.0). |
| `traceLifecycle: 'stream'` + standalone vital spans | Rejected for now: experimental surface (`_experiments` flags + stream lifecycle) for the CLS/LCP/INP subset only; revisit if sampled pageload transactions prove quota-expensive. |
| TanStack Query replacing SWR | Rejected — ADR-067 already considered and rejected it; the defect is consumers bypassing SWR, not SWR itself. |
| Next.js Router `staleTimes.dynamic` for repeat-nav document caching | Deferred — a repeat-nav warm win but changes RSC revalidation semantics; evaluate only if post-change warm FCP still >500 ms. |

## Hypotheses

(Plan Phase 1.4 network-outage checklist fired on the `timeout` token — the timeouts here are bounded `Promise.race` auth legs, not a connectivity incident.)

1. **L3 firewall allow-list** — [opted out: the perf-probe's post-deploy table (comment-5873784966) shows every request reaching L7 with `Server-Timing` headers returned; packets demonstrably traverse the network path].
2. **L3 DNS/routing** — [opted out: same probe resolves and connects on every sample; cold-vs-warm spread is per-leg latency, not resolution failure].
3. **L7 TLS/proxy** — [opted out: `Server-Timing` values are emitted by the app middleware and observed intact in the probe, proving the proxy chain delivers the app response].
4. **L7 application** — [verified: the GoTrue `mw-auth` 7 s tail and `check_my_revocation` cold misses are app/upstream latency inside measured legs, per the same table].

## Research Insights

**Premise validation (Phase 0.6):** #8978 OPEN (residual), #8985 OPEN — premises hold. `scripts/live-verify/perf-probe.ts`, `middleware.ts`, `server/request-auth.ts`, the PIR file, and `sentry.client.config.ts` all exist on `origin/main`. ADR corpus check on the proposed mechanisms: ADR-253's amendment already **rejected** a `getUser` auth-verdict cache by measurement ("a per-request verdict cache could never accelerate the first cold request … the measured win would have been warm tail-only") — the issue's "re-examine mw-auth caching" ask is therefore a *verify-the-existing-caches-cover-the-burst* task, not a new cache. ADR-067 already adopted SWR with `dedupingInterval: 2000` and shared keys — the "shared query cache" the issue asks for **already exists**; the defect is a parallel raw-fetch channel bypassing it. No mechanism sits in an ADR's rejected-alternatives table except the aggregator route and the verdict cache, both dispositioned above.

**Property List (Phase 0.6b):**

- P1: One flight per endpoint per mount — same-mount duplicate GETs collapse to zero (observable: probe `duplicates` table empty).
- P2: Non-critical data does not contend with first paint (observable: deferred keys' fetches start after FCP in the probe waterfall).
- P3: Fail-closed auth unchanged — revocation/T&C reads may get faster but never skip (observable: no `middleware.ts` diff; deny paths re-verify per request).
- P4: Real-user LCP/INP/CLS/FCP/TTFB telemetry exists and is queryable (observable: vital envelopes land in Sentry).
- P5: The pattern reaches future Soleur-built webapps by default (observable: recipe file + gate pointer committed).

**Cut List (Phase 0.6b):**

- New shared cache/dedup *mechanism* → P1 → already covered by SWR + `swrKeys` (ADR-067); the work is *migration onto it*, not building it.
- `mw-auth` verdict cache → warm-tail only → rejected by ADR-253 amendment measurement.
- Bootstrap aggregator route → P1+P2 partially → SWR coalescing covers P1 without a new endpoint; deferral is orthogonal.
- New webapp scaffold/gate generator for CWV → P5 → recipe + plan-gate pointer is sufficient; a generator (constraint-scaffold-style) buys nothing a checklist doesn't at this cardinality.

**Value-proposition measurement (Phase 0.6c):** the saving is client fetch count and cold-leg latency. Measured baseline (command: `LIVE_VERIFY_BROWSER_PATH=… doppler run -c prd -p soleur -- bun run apps/web-platform/scripts/live-verify/perf-probe.ts`, run post-deploy 2026-09-28): warm FCP 572 ms, cold p50 ~2.0 s, worst 9.08 s; ~15–18 `/api/*` per mount at 0.12–3.2 s each; duplicates remove ~6–10 requests/mount per the #8985 census comment.

**Relevant file paths (worktree-verified):**

- `apps/web-platform/lib/swr-config.ts` — `swrConfig` (`dedupingInterval: 2000`, `revalidateOnFocus: true`), `swrKeys`, `jsonFetcher`, `clearSwrCache`.
- `apps/web-platform/hooks/use-active-repo.ts` — raw fetch + module `inFlight` latch; consumers: `use-nav-resume.ts`, `chat-surface.tsx`, `live-repo-badge.tsx`, `org-switcher-container.tsx`.
- `apps/web-platform/components/dashboard/org-switcher-container.tsx` — raw `fetch("/api/workspace/list-memberships")` on mount + `WORKSPACE_LOGO_CHANGED_EVENT` re-poll.
- `apps/web-platform/components/dashboard/no-api-key-banner.tsx` — raw `fetch("/api/byok/effective-status")`.
- `apps/web-platform/components/dashboard/pending-invite-banner-recovery.tsx` — raw `fetch("/api/workspace/pending-invites")` (chat-layout arm only).
- `apps/web-platform/hooks/use-team-names.tsx` — raw `fetch("/api/team-names")`.
- `apps/web-platform/app/(dashboard)/dashboard/page.tsx` — `DASHBOARD_FOUNDATION_STATUS_KEY` + `swrKeys.dashboardToday()` + `swrKeys.workspaceActiveRepo()` consumers; `/api/vision` POST.
- `apps/web-platform/components/dashboard/{inbox-nav-badge,conversations-nav-badge,releases-nav-badge}.tsx` — already SWR; deferral-gate candidates.
- `apps/web-platform/sentry.client.config.ts` — `tracesSampleRate: 0`; scrub helpers `scrubJwtFromEvent`/`stripUserContextFromEvent`/`stripPiiFromRecord`; `PII_KEY_RE` from `lib/client-observability.ts`.
- `apps/web-platform/sentry.server.config.ts` — `tracesSampler` arms 1.0 on `x-perf-probe: 1`.
- `apps/web-platform/middleware.ts` — in-flight dedup joiner for revocation misses; concurrent getUser; `Server-Timing` `mw-auth`/`mw-revoke`/`mw-tc` on docs AND `/api/*` (ADR-253 amendment).
- `apps/web-platform/scripts/live-verify/perf-probe.ts` — probe (`RequestSample`/`NavSample`/`ProbeSummary`; `x-perf-probe` arming; `safePath` emit allowlist).
- `scripts/followthroughs/dashboard-cold-tiers-8978.sh` — follow-through pattern to mirror.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — `webapp -> sentry` edge exists (`model.c4` Sentry section); `sentry` external element exists (EU/DE cluster, `de.sentry.io` ingest).

**Institutional learnings applied:**

- `cq-cite-content-anchor-not-line-number` — citations above name anchors/symbols, not bare lines.
- Sentry-event no-raw-PII enforcement at the boundary, not call args (#8719/PR #8794 learning) → vital-payload scrub assertion.
- `2026-09-25-perf-dashboard-section-load-latency-plan.md` precedent — sequential-fallback research + directly-authored `.pen` for a mechanical-override BLOCKING perf plan.
- Probe `timing()` unit-convention misread (ADR-253 amendment) → probe assertions live on counts and header descriptors, not browser `timing()` fields, unless the field's unit is verified.

**External research + installed-SDK verification:** Sentry docs — `browserTracingIntegration` auto-registers `webVitalsIntegration` and adds pageload/navigation transactions whose measurements carry LCP/CLS/TTFB (FCP rides the same span), plus fetch/XHR child spans and INP (<https://docs.sentry.io/platforms/javascript/guides/nextjs/tracing/instrumentation/automatic-instrumentation/>). Installed-SDK source check (`@sentry/browser@10.59.0` `build/npm/esm/dev/integrations/webVitals.js` + `types/integrations/webVitals.d.ts`): the standalone `webVitalsIntegration` emits CLS/LCP/INP spans ONLY under `traceLifecycle: 'stream'` (`hasSpanStreamingEnabled` — `@sentry/core` `options.d.ts`, `traceLifecycle?: 'static' | 'stream'`, default `'static'`) or `_experiments.enableStandalone{Cls,Lcp}Spans`; its pageload-span measurement attachment is a no-op without `browserTracingIntegration` creating pageload spans; the `WebVitalName` union is `'cls' | 'inp' | 'lcp'` — FCP/TTFB have no standalone path. Therefore `browserTracingIntegration` + `tracesSampler` is the required mechanism, not a fallback. `beforeSendTransaction` and `beforeSendSpan` exist on `options.d.ts` (streamed-span callback wraps with `withStreamedSpan` only under `traceLifecycle: 'stream'` — not our arm). `web-vitals` npm package not in dep tree.

**Skill description budget (Phase 1.8):** no `description:` edits to any `SKILL.md` are proposed — the plugin encoding is a body-level pointer + a new reference file. Budget check skipped (no candidate).

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Codebase reality | Plan response |
|---|---|---|
| "shared query cache / dedup window" needed | SWR + `swrKeys` + `dedupingInterval` already exist (ADR-067) | Migrate the bypassing raw-fetch consumers onto it; no new cache mechanism |
| "re-examine mw-auth caching for repeat navs" | Revocation+T&C positive-verdict caches live (30 s); getUser verdict cache rejected by measurement in the ADR-253 amendment | Verify-only: assert the existing joiner covers the mount burst; no middleware diff |
| "evaluate Sentry web-vitals vs first-party beacon" | `@sentry/nextjs@^10.59.0` installed; client tracing off (`tracesSampleRate: 0`); no vitals wired; standalone vitals-only emission requires `traceLifecycle: 'stream'` and never covers FCP/TTFB | Sentry `browserTracingIntegration` + probe-armed `tracesSampler`; beacon as documented reject |
| "probe surface exists" | `perf-probe.ts` committed and armed via `x-perf-probe` | Extend it (duplicate census + vitals capture) rather than a second harness |

## Open Code-Review Overlap

- **#3829** (`review: CI gate enforcing 'new Sentry monitor type → sentry-scrub.ts must change'`) — names `apps/web-platform/sentry.client.config.ts`. **Acknowledge:** different concern (CI gate for monitor types vs client wiring), but this plan's scrub-boundary assertion for the new vitals payload aligns with its intent; do NOT fold — the gate is a CI artifact, not this diff's concern.
- **#2590** (`refactor(dashboard): extract useFirstRunAttachments + FirstRunComposer from DashboardPage`) — names `dashboard/page.tsx`. **Acknowledge:** component-extraction refactor; our edits are fetch-layer. Possible minor merge friction on `page.tsx` — whoever lands second rebases; no scope fold.
- No other open code-review issue body names a file this plan touches (`middleware.ts` match #2591 is CSP-docs scope and this plan makes no middleware diff — overlap vacuous).

## User-Brand Impact

- **If this lands broken, the user experiences:** the `/dashboard` first paint — either a missing/deduped-away section (a shared SWR key colliding two *different* payloads serves one user another section's data shape) or, worse, the SWR cache carrying a prior principal's data if the `clearSwrCache` boundary is disturbed — that is the exact single-user trust breach ADR-067's C1/FR4 exists to prevent.
- **If this leaks, the user's data is exposed via:** a shared-key collision or a cache-clear regression surfacing workspace-A content (repo URLs, inbox subjects, membership lists) to workspace-B or a signed-out successor session; secondarily, Sentry vital envelopes carrying a user identifier to the telemetry vendor.
- **Brand-survival threshold:** `single-user incident`

- Artifact/vector pair 1: dashboard content sections ↔ SWR key collision / missed `clearSwrCache` call site.
- Artifact/vector pair 2: telemetry payloads ↔ vital span carrying `user`/PII fields to Sentry.

`soleur:engineering:review:user-impact-reviewer` will be invoked at review time.

## Observability

```yaml
liveness_signal:
  what: Sentry Web Vitals ingestion for app.soleur.ai sessions (sampled pageload/navigation transactions carrying LCP/INP/CLS/FCP/TTFB measurements) + the armed dashboard-cold-tiers follow-through's >15 s GET /dashboard scan
  cadence: continuous ingestion; follow-through scan daily
  alert_target: Sentry issue → operator email (existing sentry->founder route, model.c4)
  configured_in: apps/web-platform/sentry.client.config.ts (integration wiring); scripts/followthroughs/cwv-field-rum-9178.sh (post-deploy verification scan)

error_reporting:
  destination: Sentry web-platform project via NEXT_PUBLIC_SENTRY_DSN (client) / SENTRY_DSN (server) — unchanged destination, new measurement class
  fail_loud: reportSilentFallback mirrors into Sentry on dedup/fetch failures (existing boundary); a dedup-guard CI failure blocks merge

failure_modes:
  - mode: same-mount duplicate GET regresses (new raw-fetch consumer added)
    detection: apps/web-platform/test mount-fetch dedup census test (static grep over the mount-surface set) + probe duplicates table non-empty
    alert_route: CI failure / probe output
  - mode: field vitals silently stop landing (SDK config regression, DSN change, sampler regression to 0)
    detection: scripts/followthroughs/cwv-field-rum-9178.sh finds zero vital-bearing transactions in the post-deploy window
    alert_route: follow-through issue → operator
  - mode: a transaction or span payload carries a user identifier
    detection: vitest asserting scrubbed transaction/span payloads across all three beforeSend* sinks + code review
    alert_route: CI failure
  - mode: mw-auth/remote legs regress past bound
    detection: existing Server-Timing mw-* descriptors on every authenticated response + dashboard-cold-tiers-8978.sh (already armed)
    alert_route: follow-through issue → operator

logs:
  where: Sentry (vitals + errors); probe stdout (repo-run, not retained); Server-Timing response headers
  retention: Sentry project retention; probe output ephemeral to the invoking session

discoverability_test:
  command: grep -c browserTracingIntegration apps/web-platform/sentry.client.config.ts
  expected_output: "1"
```

### Follow-Through Enrollment

- `scripts/followthroughs/cwv-field-rum-9178.sh` — exit 0 when Sentry shows ≥1 web-vitals event for `/dashboard` sessions in the post-deploy window; `start=` pinned strictly after deploy; mirrors `scripts/followthroughs/reconcile-ff-only-sentry-4977.sh` shape.
- Tracker: `<!-- soleur:followthrough script=scripts/followthroughs/cwv-field-rum-9178.sh earliest=<deploy+1d> secrets=SENTRY_AUTH_TOKEN,SENTRY_ORG -->` + `follow-through` label on the ship PR's tracking surface; confirm `secrets=` names already wired in `.github/workflows/scheduled-followthrough-sweeper.yml` (the existing dashboard-cold-tiers script's token set is the reference).
- The pre-existing `scripts/followthroughs/dashboard-cold-tiers-8978.sh` stays armed unchanged — this plan does not retire it.

## Encryption Posture

No new persistent store and no new cross-component connection — the browser→`de.sentry.io` ingest edge already carries error envelopes (model.c4 `webapp -> sentry`); vitals are a new *payload class* on the existing connection.

```yaml
at_rest: []    # no new store; vitals persist inside Sentry under its existing posture
in_transit:
  - connection: browser -> Sentry ingest (de.sentry.io, EU residency)
    enforced_at: apps/web-platform/sentry.client.config.ts (Sentry.init SDK envelope transport)
    tls: HTTPS/TLS ≥1.2 (SDK transport, vendor-enforced)
    cert_verification: on
    does_not_defend: payload content is readable by the vendor; user identifiers must never reach the payload — enforced by the scrub boundary + the vitals-payload test, not by TLS
    disclosed_as: not-publicly-claimed (DPA already covers Sentry as processor)
```

## Guard Contract

### Guard 1 — dashboard mount-fetch dedup census

**Property.** No mount-time code path on the `/dashboard` shell issues a `fetch(` GET to `/api/*` outside the shared SWR key space — every mount GET flows through `useSWR`+`swrKeys` so SWR's coalescing owns dedup.

**Assembly.** The chokepoint is the mount-surface set itself: `app/(dashboard)/layout.tsx`, `app/(dashboard)/dashboard-shell.tsx`, `app/(dashboard)/dashboard/page.tsx`, every `components/dashboard/**` and `hooks/**` module reachable from them at mount, plus `swr-config.ts` as the key registry. The guard enumerates that import closure (or a maintained manifest it asserts against `git grep` hits for `fetch("/api/`) — two enumeration styles are named so the work phase picks the one that can actually be driven red; a hand-maintained path list WITHOUT the `git grep` cross-check is the snapshot-not-assembly defect. **Plan-time baseline (per the sharp-edge census rule):** `grep -rn 'fetch("/api/'` over `components/dashboard/`, `hooks/`, `app/(dashboard)/` currently returns **17** candidate sites (the guard's pre-change violation count to drive to zero).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add a raw `fetch("/api/x")` GET to `use-active-repo.ts` mount path | RED |
| 2 | Neuter the guard's own census (make its grep pattern match nothing / empty manifest) | RED |
| 3 | Add a SECOND raw-fetch consumer after a compliant first (e.g., one raw fetch already present in a new `components/dashboard/foo.tsx`) | RED |
| 4 | Move a `fetch(` call inside a `useEffect` gated on post-FCP deferral but still raw | RED (deferral is not an exemption — dedup applies to deferred fetches too) |
| 5 | Harness: delete the assertion loop so the suite body runs zero checks and exits 0 | RED |
| 6 | Must-PASS variant: a `fetch(` POST (mutation, non-GET) inside the enumerated set | PASS — the property quantifies over GETs only |

**Anchor.** If the guard asserts a manifest, the manifest's expected consumer list must be derivable from `git grep` at test time — both the list and the code can change in one diff, so the check that survives is set-membership (every `fetch("/api/` hit outside `swrKeys`-routed modules is flagged), not a count floor.

## Architecture Decision (ADR/C4)

Two decisions ship with this plan as plan tasks (not follow-ups):

### ADR

- **Amend ADR-067** (`ADR-067-adopt-swr-client-cache.md`): add the mount-fetch contract — mount-time `/api/*` GETs in the dashboard shell route through `swrKeys`+`useSWR`; raw `fetch` GETs on the mount path are the defect class the census guard enforces; document the post-FCP deferral primitive (`usePostFcp`/`null`-key gating) as the sanctioned way to defer a fetch.
- **New ADR (provisional ordinal — claim next-free at work time, sweep `ADR-<old>` across this plan + tasks + ACs on renumber per Phase 2.10):** *Field Core Web Vitals via Sentry `webVitalsIntegration`* — records the vendor choice (existing Sentry edge vs a first-party beacon + new store), the no-transaction sampling posture, and the EU-residency/PII constraints. Amend ADR-031 only if the wiring lands as Terraform-managed Sentry resources (it does not — this is SDK config).

### C4 views

- **Enumeration performed (per the completeness mandate):** external human actors — none new (the dashboard user is already modeled); external systems/vendors — Sentry already modeled (`model.c4` Sentry element + `webapp -> sentry` edge carrying "Exceptions + debounced warns via the @sentry/nextjs SDK"); containers/data-stores — none new; access relationships — unchanged.
- **Task:** update the `webapp -> sentry` edge description in `knowledge-base/engineering/architecture/diagrams/model.c4` to name the web-vitals RUM payload class alongside exceptions/warns (the edge prose enumerates payload classes — leaving vitals out makes the recorded architecture under-describe the real one). Verify no `views.c4` change is needed (the edge already renders); run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` if `.c4` files are touched.

### Sequencing

The ADR-067 amendment describes the contract as-merged (all consumers migrated); no adopting-state needed. The RUM ADR is authored in the same PR.

## Domain Review

**Domains relevant:** Engineering, Product (forced by the mechanical UI-surface override — `app/(dashboard)/dashboard/page.tsx` and `components/dashboard/*.tsx` appear in Files to Edit).

### Engineering

**Status:** reviewed (sequential-fallback — this planning run executes inline; no Task fan-out in this runtime)
**Assessment:** Load-bearing risks are (a) SWR key collision across different payload shapes — mitigated by one key per endpoint and the tuple-key convention already in `swr-config.ts`; (b) breaking `useActiveRepo`'s J5 `fellBackToSolo` semantics and the `cloning` 2 s poll during the SWR migration — mitigated by the `refreshInterval` equivalent and the existing `use-active-repo-poll.test.tsx` suite; (c) `clearSwrCache` coverage — the migration widens what the cache holds (memberships, team-names), so sign-out/workspace-switch clear must still precede navigation (existing call sites, asserted); (d) vital-envelope PII — mitigated by the boundary-scrub extension and its test.

### Product/UX Gate

**Tier:** blocking (mechanical UI-surface override — `app/**/page.tsx` + `components/**/*.tsx` in Files to Edit)
**Decision:** auto-accepted (pipeline) — headless subagent run; no per-phase approval gate
**Agents invoked:** none — Task fan-out unavailable in this runtime; spec-flow and CPO lenses applied inline: the only user-facing delta is *when* deferred sections' data arrives (below-the-fold content populates post-first-paint instead of during it); no screen, copy, component, or flow changes. Flow check: no dead ends introduced — every existing state (loading shimmer, empty, error, provisioning, redirect-hold) is preserved; deferred surfaces still render cached/instant state on return navs.
**Skipped specialists:** none (inline equivalent applied)
**Pencil available:** yes — the committed wireframe is `knowledge-base/product/design/dashboard/dashboard-load-states.pen` (authored for the sibling perf plan `2026-09-25-perf-dashboard-section-load-latency-plan.md`, on `origin/main`). It already encodes exactly the states this change exercises — chrome + section-level skeletons while fetches resolve, then resolved sections — and the deferral work is *another timing variant of those same states*, not a new visual surface. The work phase EXTENDS it with a "deferred (post-FCP) section" annotation only if implementation fixes a deferred set whose depiction isn't already covered — amending the committed `.pen` keeps the artifact truthful rather than spawning a second file describing the same states.

#### Findings

- The deferral changes *timing*, not pixels — the committed wireframe's section-skeleton state IS the deferred appearance; the spec/work task is to fix WHICH sections populate post-FCP (the census + `.pen` state list gate in FR4), not to design anything new.

## Acceptance Criteria

### Functional Requirements

- [ ] FR1. Every mount-time `/api/*` GET in the dashboard shell flows through `useSWR` + a `swrKeys.*` tuple; `swrKeys` gains entries for `list-memberships`, `byok/effective-status`, `pending-invites`, `team-names`; the dedup-census guard (QG1) drives the plan-time baseline of 17 raw-`fetch("/api/` sites in the mount-surface set to zero.
- [ ] FR2. `useActiveRepo()` reads `swrKeys.workspaceActiveRepo()` — same key as `useConversations`/page/nav-badge — preserving keep-last-known-on-error, focus revalidation, the `cloning` 2 s poll (as `refreshInterval`), and the `fellBackToSolo` signal; `use-active-repo-poll.test.tsx` updated and green.
- [ ] FR3. `WORKSPACE_LOGO_CHANGED_EVENT` still re-fetches memberships after the SWR migration (via `mutate` on the shared key); org-switcher subtitle updates without reload.
- [ ] FR4. `usePostFcp()` (or equivalent `null`-key gate) defers the non-critical key set (nav-badge counts, releases, team-names — final set fixed by the probe census + the `.pen` state list) until after first paint; above-fold keys (today, conversations, route-primary inbox) are never gated.
- [ ] FR5. `sentry.client.config.ts` wires `Sentry.browserTracingIntegration()` and replaces `tracesSampleRate: 0` with a `tracesSampler` returning `1.0` under the probe marker and `0.1` otherwise; `sendDefaultPii` unset; `beforeSendTransaction` + `beforeSendSpan` reuse the existing scrub helpers.
- [ ] FR6. Transaction/span envelopes carry no `user` id/email/username/ip and no JWT/email substrings — enforced at the config boundary and asserted by a vitest on the scrub path (`beforeSend`, `beforeSendTransaction`, `beforeSendSpan` — all three sinks, per the whole-event learning).
- [ ] FR7. `perf-probe.ts` emits a per-sample `duplicates` table (same method+path GETs >1 within a navigation) and extends `NavSample` with TTFB/FCP/LCP/CLS fields where `PerformanceObserver` supports them in the headless shell.
- [ ] FR8. `plugins/soleur/skills/plan/references/webapp-cwv-observability.md` exists covering: Sentry-first recipe (`browserTracingIntegration` + probe-armed `tracesSampler` + transaction/span scrub boundary when `@sentry/nextjs` or `@sentry/browser` is installed; the `webVitalsIntegration`-standalone caveat — CLS/LCP/INP only, `traceLifecycle: 'stream'` required, never FCP/TTFB), beacon-endpoint fallback spec (PII constraints), sampling/quota notes, verification command, scrub-boundary requirement; pointer lines land in `plan/SKILL.md` Phase 2.9 and `spec-templates/SKILL.md`.
- [ ] FR9. ADR-067 amendment + the new field-RUM ADR are committed in the same PR; the `model.c4` `webapp -> sentry` edge prose names the vitals payload class (or records the checked-and-modeled conclusion).

### Non-Functional Requirements

- [ ] NFR1. `middleware.ts` is byte-identical post-change — no auth semantics touched (revocation/T&C fail-closed per ADR-253); any deviation re-opens the measured-rejection conversation explicitly.
- [ ] NFR2. Warm FCP ≤500 ms and cold p50 <2 s on the post-deploy probe re-run (5 cold + 1 warm, `x-perf-probe` armed) — closes #8978's unmet arm.
- [ ] NFR3. `duplicates` table empty and mount GET count ≤~10 on a warm `/dashboard` navigation.
- [ ] NFR4. Client transaction sampling is bounded: `1.0` only under the probe marker, `0.1` for real sessions — the work phase confirms project ingest quota headroom before merge (a `tracesSampler` cannot exceed these rates; no `tracesSampleRate` fallback value may exceed `0.1`).

### Quality Gates

- [ ] QG1. Dedup-census guard test (`apps/web-platform/test/`) red-drivable per the Guard Contract matrix; full matrix executed during work.
- [ ] QG2. `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` green; touched vitest suites green (`use-active-repo-poll`, dedup census, sentry client config, swr-config consumers).
- [ ] QG3. Committed `.pen` wireframe `knowledge-base/product/design/dashboard/dashboard-load-states.pen` governs the loading-state semantics (exists + referenced here per `wg-ui-feature-requires-pen-wireframe`); work extends it only if the fixed deferred set introduces a state it doesn't depict.
- [ ] QG4. `scripts/followthroughs/cwv-field-rum-9178.sh` committed with the tracker directive + `follow-through` label wired.

### Post-merge (verification — automatable)

- [ ] PM1. Probe re-run post-deploy: `duplicates` empty; warm FCP ≤500 ms; cold p50 <2 s; comment the table onto #9178 (and #8978 for the AC arm).
- [ ] PM2. `cwv-field-rum-9178.sh` reports vital events landing in Sentry within 24 h of deploy.
- [ ] PM3. `dashboard-cold-tiers-8978.sh` remains armed — no >15 s `GET /dashboard` regression.

## Test Scenarios

### Acceptance Tests (RED phase targets)

- Given two components mounting `useActiveRepo()` plus a `swrKeys.workspaceActiveRepo()` SWR consumer in the same render pass, when mount completes, then exactly one `/api/workspace/active-repo` GET is issued (fetch-mock count assertion).
- Given `repoStatus === "cloning"`, when the SWR-migrated hook polls, then `refreshInterval` fires at 2 s and self-stops on `ready`/`error` (port of the existing poll test).
- Given a deferred key's consumer, when first paint has not completed, then no fetch fires; when the idle callback fires, then exactly one fetch fires.
- Given a new raw `fetch("/api/…")` GET added inside the mount-surface set, when the census guard runs, then it fails naming the file (mutation matrix row 1).
- Given `sentry.client.config.ts`, when a vital span/envelope is constructed with `user`/`email` fields present, when `beforeSend*` runs, then the fields are stripped (boundary test per FR6).

### Regression Tests

- Given a sign-out or workspace switch, when `clearSwrCache` runs, then all newly-added keys (memberships, team-names, byok status, pending invites) are evicted before navigation — cross-principal staleness cannot appear (ADR-067 FR4 regression).
- Given `WORKSPACE_LOGO_CHANGED_EVENT`, when dispatched post-migration, then the memberships key revalidates (FR3).
- Given a `401`/302→login response on a deduped fetch, when `isRevocationBounce` triggers, then the hard-nav behavior is unchanged.

### Edge Cases

- Given `requestIdleCallback` absent (Safari headless), when `usePostFcp` mounts, then the `setTimeout` fallback still defers past paint.
- Given a mount where a deferred fetch is interrupted by navigation away, when the key unmounts, then no orphaned fetch updates state (SWR abort/unmount semantics).
- Given Sentry DSN unset (local/dev), when the vitals integration initializes, then no crash and no emission.

### Integration Verification (for `soleur:qa`)

- **Probe:** `LIVE_VERIFY_BROWSER_PATH=~/.cache/ms-playwright/chromium_headless_shell-1232/chrome-headless-shell-linux64/chrome-headless-shell doppler run -c prd -p soleur -- bun run apps/web-platform/scripts/live-verify/perf-probe.ts` → `duplicates` table empty; warm FCP ≤500 ms.
- **Sentry verify:** post-deploy, Sentry Web Vitals dashboard (or `events` API) shows vitals for `transaction`/`route` `/dashboard` within 24 h — automated via the follow-through script, not a dashboard eyeball.

## Success Metrics

- Warm FCP ≤500 ms (issue AC; #8978 arm closure).
- Cold FCP p50 <2 s (issue AC).
- Same-mount duplicate `/api/*` GETs: 0 (probe census).
- Mount GET count: ~15–18 → ≤~10.
- Field vitals present in Sentry for ≥1 real session within 24 h of deploy.

## Dependencies & Prerequisites

- `@sentry/nextjs@^10.59.0` already installed — no dependency change required for the primary arm.
- `x-perf-probe` arming + `SENTRY_*` Doppler secrets already exist (follow-through reuses them; verify `secrets=` names against `scheduled-followthrough-sweeper.yml`).
- The `.pen` authoring (pre-work) requires Pencil headless path or direct-JSON authoring per the `dashboard-load-states.pen` precedent.

## Risk Analysis & Mitigation

| Risk | Mitigation |
|---|---|
| SWR migration changes `useActiveRepo` timing semantics (J5 fallback, cloning poll) | Port the existing poll test first (RED), preserve `refreshInterval` + keep-last-known; review by diff, not vibes |
| `dedupingInterval`/focus settings interact with StrictMode or dual (mobile+rail) mounts to re-fire | Census table makes each residual duplicate attributable; remedies land per-cause (key shape vs interval vs mount count) |
| Vital envelopes carry a user identifier to Sentry | Boundary scrub + FR6 test; `sendDefaultPii` stays unset |
| Sentry client transaction volume exceeds quota headroom | `tracesSampler` caps real-session sampling at 0.1; work phase confirms project ingest headroom before merge; the sampler is the single tuning point |
| Deferral gates a fetch that is actually above-fold on some viewport | The deferred set is fixed by the `.pen` state list + census, not guessed; the conservative default is ungated |

## Resource Requirements

Single engineer/agent session; no new vendors, secrets, or infra. Sentry ingest volume increases by sampled pageload/navigation transactions (~10% of sessions) — quota check is a Phase 2 task.

## Future Considerations

- If the census shows residual duplicates from *different* keys hitting one endpoint (e.g., parameterized query strings), normalize key construction in `swrKeys` rather than adding fetch-time dedup.
- `staleTimes.dynamic` / Router Cache for repeat-nav document caching is the next warm-nav lever if NFR2 still misses.
- Multi-replica revisit of ADR-253's in-process caches stays out of scope (single Node isolate today).

## Documentation Plan

- ADR-067 amendment + new field-RUM ADR (Phase 3).
- `model.c4` edge-prose update (Phase 3).
- `webapp-cwv-observability.md` recipe + skill pointers (Phase 3).
- No legal-doc, DPA, or compliance-posture changes — Sentry is an existing processor and vitals carry no new data class (no `user` fields by construction + scrub assertion).

## Sharp Edges

- A plan whose `## User-Brand Impact` is empty or omits the threshold fails deepen-plan Phase 4.6 — filled above.
- `middleware.ts` deliberately absent from Files to Edit: the ADR-253 amendment's measured rejection of a `getUser` verdict cache is the recorded answer to the issue's third bullet; treat "re-examine" as "verify coverage", not "add a cache".
- The mount-fetch census guard must enumerate the mount-surface set structurally (grep/import closure), not from a hand list — hand lists drift while the suite stays green.
- Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (no root `workspaces` — `-w` form fails).
- Sentry test mocks need `addBreadcrumb: vi.fn()` where a route calls `verifiedUserId` without the header (pipeline note).
- `e2e nav-states-nav-pending` is timing-flaky under load — check artifacts before assuming regression (pipeline note).
- Verify `secrets=` names on the new follow-through against `scheduled-followthrough-sweeper.yml` before wiring — a script emitting markers CI cannot grade reproduces the #7159 class.
- The dedup guard's own dispatch needs a non-vacuous check (guard matrix row 2): an empty grep match set that exits 0 is the #7493 stub class.
- Legal-doc edits are NOT in scope (pipeline note) — none of the Files to Edit/Create touch `docs/legal/**`, `compliance-posture.md`, or `LEGAL_DOC_SHAS`.

## Files to Edit

- `apps/web-platform/lib/swr-config.ts` — new `swrKeys` entries (`listMemberships`, `byokEffectiveStatus`, `pendingInvites`, `teamNames`); dedup/deferral option review.
- `apps/web-platform/hooks/use-active-repo.ts` — re-implement on `useSWR(swrKeys.workspaceActiveRepo())`; preserve poll/fallback semantics; keep `__resetActiveRepoCoalesceForTests` equivalent.
- `apps/web-platform/components/dashboard/org-switcher-container.tsx` — memberships via shared key + `mutate` on `WORKSPACE_LOGO_CHANGED_EVENT`.
- `apps/web-platform/components/dashboard/no-api-key-banner.tsx` — byok effective-status via shared key.
- `apps/web-platform/components/dashboard/pending-invite-banner-recovery.tsx` — pending-invites via shared key.
- `apps/web-platform/hooks/use-team-names.tsx` — team-names via shared key.
- `apps/web-platform/app/(dashboard)/dashboard/page.tsx` — census-driven dedup/deferral adjustments to `DASHBOARD_FOUNDATION_STATUS_KEY`/`dashboardToday` consumers.
- `apps/web-platform/app/(dashboard)/dashboard-shell.tsx` — deferral gating for nav-badge mounts if census requires.
- `apps/web-platform/components/dashboard/{inbox-nav-badge,conversations-nav-badge,workstream-nav-badge,releases-nav-badge}.tsx` — deferral gating (as needed per census).
- `apps/web-platform/sentry.client.config.ts` — `webVitalsIntegration`; span-level scrub boundary if exposed.
- `apps/web-platform/scripts/live-verify/perf-probe.ts` — duplicate census + vitals capture.
- `apps/web-platform/test/use-active-repo-poll.test.tsx` — port to SWR implementation.
- `plugins/soleur/skills/plan/SKILL.md` — one pointer line at Phase 2.9 (body, not `description:`).
- `plugins/soleur/skills/spec-templates/SKILL.md` — pointer to the recipe for webapp specs.
- `knowledge-base/engineering/architecture/decisions/ADR-067-adopt-swr-client-cache.md` — mount-fetch contract amendment.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — `webapp -> sentry` edge prose (vitals payload class).
- `knowledge-base/product/design/dashboard/dashboard-load-states.pen` — extend with a deferred-section annotation ONLY if the fixed deferred set introduces a state it doesn't already depict (conditional; see Product/UX Gate).

## Files to Create

- `apps/web-platform/hooks/use-post-fcp.ts` — post-first-paint gate primitive (`.ts`, outside the UI-surface glob by design).
- `apps/web-platform/test/dashboard-mount-fetch-dedup.test.tsx` (or `.ts`) — the census guard.
- `apps/web-platform/test/sentry-client-webvitals.test.ts` — integration wiring + payload scrub assertions.
- `apps/web-platform/scripts/live-verify/` — no new file; probe extension lands in `perf-probe.ts`.
- `plugins/soleur/skills/plan/references/webapp-cwv-observability.md` — the recipe.
- `scripts/followthroughs/cwv-field-rum-9178.sh` — post-deploy vitals-landing scan.
- `knowledge-base/engineering/architecture/decisions/ADR-<next>-field-rum-cwv-via-sentry-webvitals.md` — provisional ordinal; claim next-free at work time and sweep this plan + tasks.md + ACs for the old ordinal on renumber.

## References & Research

### Internal References

- ADR-067 `knowledge-base/engineering/architecture/decisions/ADR-067-adopt-swr-client-cache.md` — SWR adoption + clear-on-principal-boundary contract.
- ADR-253 `knowledge-base/engineering/architecture/decisions/ADR-253-bounded-freshness-verdict-caching-and-middleware-verified-identity.md` — bounded caches, header mint, the auth-verdict-cache measured rejection (Amendment 2026-09-26).
- ADR-031 `ADR-031-sentry-as-iac.md` — Sentry vendor/IaC posture.
- `apps/web-platform/lib/swr-config.ts` §`swrKeys`/`jsonFetcher`/`clearSwrCache`; `hooks/use-active-repo.ts` §`fetchActiveRepoCoalesced`; `middleware.ts` §in-flight dedup joiner.
- Prior plans: `knowledge-base/project/plans/2026-09-25-perf-dashboard-section-load-latency-plan.md`, `2026-09-26-perf-dashboard-cold-load-first-paint-plan.md`.
- PIR: `knowledge-base/engineering/operations/post-mortems/2026-09-28-dashboard-cold-tiers-unbounded-supabase-legs-postmortem.md`.

### External References

- Sentry Next.js WebVitals integration: <https://docs.sentry.io/platforms/javascript/guides/nextjs/configuration/integrations/webvitals/>
- Sentry Next.js automatic instrumentation (tracing): <https://docs.sentry.io/platforms/javascript/guides/nextjs/tracing/instrumentation/automatic-instrumentation/>

### Related Work

- Issues: #9178 (this), #8978 (residual cold-tier parent), #8985 (mount-fan-out deferral — closed by this plan), #9034 (bounding PR).
- Comments: #8978 comment-5873784966 (post-deploy measurement), #8985 comment-5873791940 (duplicate census).
