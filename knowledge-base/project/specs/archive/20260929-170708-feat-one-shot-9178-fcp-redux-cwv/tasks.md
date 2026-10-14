# Tasks — perf(webapp): dashboard FCP redux + CWV observability (#9178)

Plan: `knowledge-base/project/plans/2026-09-28-perf-dashboard-fcp-redux-cwv-observability-plan.md`
Issue: #9178 (closes #8985's deferral)

## Phase 0 — Pre-work gates

- [x] 0.1 Confirm the committed wireframe `knowledge-base/product/design/dashboard/dashboard-load-states.pen` covers the deferred-set depiction; extend it with a "deferred (post-FCP) section" annotation ONLY if the fixed deferred set introduces a state it doesn't already depict (UX-gate artifact; see plan Domain Review).
- [x] 0.2 Claim the next-free ADR ordinal from `knowledge-base/engineering/architecture/decisions/`; if it differs from the plan's provisional reference, sweep `grep -rn 'ADR-<old>' knowledge-base/project/{plans,specs}/` and update this plan + tasks + ACs in the same edit.

## Phase 1 — Probe census + mount dedup (Workstream A)

- [x] 1.1 Extend `apps/web-platform/scripts/live-verify/perf-probe.ts`: per-sample `duplicates` table (same method+path GETs counted >1 within a navigation); add `ttfb`/`fcp`/`lcp`/`cls` to `NavSample` where `PerformanceObserver` supports them in the headless shell. Verify units before asserting (the ADR-253 amendment records a `timing()` unit misread).
- [x] 1.2 Add `swrKeys` entries to `apps/web-platform/lib/swr-config.ts`: `listMemberships()`, `byokEffectiveStatus()`, `pendingInvites()`, `teamNames()`; review `dedupingInterval`/`revalidateOnFocus` against the census findings.
- [x] 1.3 Migrate `apps/web-platform/hooks/use-active-repo.ts` to `useSWR(swrKeys.workspaceActiveRepo())`: keep-last-known on transient error, `refreshInterval` 2 s while `repoStatus === "cloning"`, `fellBackToSolo` signal, focus revalidation, test-reset equivalent.
- [x] 1.4 Migrate raw-fetch mount consumers: `components/dashboard/org-switcher-container.tsx` (memberships + `WORKSPACE_LOGO_CHANGED_EVENT` → `mutate`), `no-api-key-banner.tsx` (byok/effective-status), `pending-invite-banner-recovery.tsx`, `hooks/use-team-names.tsx`; normalize `/api/inbox` consumers onto `swrKeys.inbox(status)`.
- [x] 1.5 New `apps/web-platform/hooks/use-post-fcp.ts` (`requestIdleCallback` + `setTimeout` fallback); gate the non-critical key set (nav-badge counts, releases, team-names; final set fixed by census + `.pen` state list) via `null` keys.
- [x] 1.6 New `apps/web-platform/test/dashboard-mount-fetch-dedup.test.tsx` census guard per the plan's Guard Contract (baseline: 17 raw `fetch("/api/` sites in the mount-surface set → drive to 0); run the full mutation matrix.
- [x] 1.7 Update `apps/web-platform/test/use-active-repo-poll.test.tsx` and any SWR-consumer tests; `swr-cache-clear-on-signout.test.tsx` still covers the new keys.

## Phase 2 — Field RUM (Workstream B, web platform)

- [x] 2.1 `apps/web-platform/sentry.client.config.ts`: add `Sentry.browserTracingIntegration()` (auto-registers `webVitalsIntegration`); replace `tracesSampleRate: 0` with a `tracesSampler` — `1.0` when `localStorage.getItem("soleur.perf-probe") === "1"`, `0.1` otherwise; `sendDefaultPii` stays unset. (Standalone `webVitalsIntegration` is a documented reject: CLS/LCP/INP only under `traceLifecycle: 'stream'`; FCP/TTFB ride pageload transactions — see plan Research Insights.)
- [x] 2.2 Extend the scrub boundary: `beforeSendTransaction` + `beforeSendSpan` reusing `scrubJwtFromEvent`/`stripUserContextFromEvent`/`stripPiiFromRecord` (transaction events and span payloads bypass `beforeSend`).
- [x] 2.3 `perf-probe.ts`: set the client-side probe marker (`page.addInitScript`/context storage `soleur.perf-probe=1`) before navigations so probe sessions sample at 1.0.
- [x] 2.4 New `apps/web-platform/test/sentry-client-webvitals.test.ts`: integration + sampler arms (1.0 marker / 0.1 otherwise); transaction/span payloads contain no `user` fields and no JWT/email substrings after scrub.
- [x] 2.5 Confirm Sentry project ingest quota headroom for ~10% client pageload+navigation transactions (NFR4); if tight, lower the default rate — the sampler is the single tuning point.
- [x] 2.6 New `scripts/followthroughs/cwv-field-rum-9178.sh` mirroring `dashboard-cold-tiers-8978.sh`/`reconcile-ff-only-sentry-4977.sh`; verify `secrets=` names against `.github/workflows/scheduled-followthrough-sweeper.yml`; add the tracker directive + `follow-through` label at ship.

## Phase 3 — Skill encoding + ADR/C4

- [x] 3.1 New `plugins/soleur/skills/plan/references/webapp-cwv-observability.md` recipe (Sentry-first: `browserTracingIntegration` + probe-armed `tracesSampler` + transaction/span scrub reuse; document the standalone-`webVitalsIntegration` caveat; beacon-endpoint fallback spec with PII constraints; sampling/quota notes; verification command).
- [x] 3.2 Pointer lines: `plugins/soleur/skills/plan/SKILL.md` Phase 2.9 body + `plugins/soleur/skills/spec-templates/SKILL.md`. No `description:` edits (Phase 1.8 budget check skipped — no candidates).
- [x] 3.3 Amend `ADR-067-adopt-swr-client-cache.md` (mount-fetch contract + post-FCP deferral primitive); author the new field-RUM ADR at the ordinal claimed in 0.2.
- [x] 3.4 Update `model.c4` `webapp -> sentry` edge prose to name the vitals/transaction payload class; run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` if `.c4` touched.

## Phase 4 — Verification

- [x] 4.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` green; touched vitest suites green.
- [ ] 4.2 Post-deploy probe re-run: `LIVE_VERIFY_BROWSER_PATH=~/.cache/ms-playwright/chromium_headless_shell-1232/chrome-headless-shell-linux64/chrome-headless-shell doppler run -c prd -p soleur -- bun run apps/web-platform/scripts/live-verify/perf-probe.ts` — `duplicates` empty, warm FCP ≤500 ms, cold p50 <2 s; comment the table on #9178 (and #8978's AC arm).
- [ ] 4.3 `cwv-field-rum-9178.sh` confirms vital-bearing transactions in Sentry within 24 h of deploy; `dashboard-cold-tiers-8978.sh` stays armed.
