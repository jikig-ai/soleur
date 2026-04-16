# Brainstorm: Runtime Feature Flags

**Date:** 2026-04-16
**Status:** Complete
**Participants:** Founder, CTO, COO, CPO

## What We're Building

A runtime feature flag system that decouples feature visibility from Docker
rebuilds. Replace build-time `NEXT_PUBLIC_*` env var flags with a server-side
`/api/flags` endpoint that reads regular `process.env` vars at request time,
served to the client via a React Context provider.

## Why This Approach

The current pattern uses `NEXT_PUBLIC_*` env vars managed in Doppler. Next.js
inlines these into the client JS bundle at build time (`next build`). Toggling a
flag requires a full Docker rebuild and redeploy (5-10 minutes). The founder
wants to:

1. **Toggle feature visibility without rebuilding Docker** -- change a Doppler
   value and restart the container (30 seconds)
2. **Hide unfinished UI from users** -- ship code to prod but gate visibility
   behind flags so only the founder (or specific users) see work-in-progress
   features

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Runtime env vars via `/api/flags` endpoint** over Supabase table or third-party provider | Zero new infrastructure, hours of work, $0 cost. Adequate for 1-2 boolean flags with 0 external users. |
| 2 | **Server-side env var reads, not `NEXT_PUBLIC_*`** | Regular `process.env.*` vars are read at runtime from the container environment. `NEXT_PUBLIC_*` vars are baked into the bundle at build time. |
| 3 | **React Context provider for client consumption** | The app currently has zero React Context providers. This establishes the pattern. The Context becomes the injection point if we later upgrade to a provider SDK. |
| 4 | **Toggle via Doppler + container restart** | Changing a Doppler `prd` value + `docker restart` takes ~30 seconds. Not instant, but eliminates the 5-10 minute Docker rebuild. |
| 5 | **Defer third-party provider to Phase 4** | Per-user targeting and percentage rollouts are needed when beta users arrive (~10 founders). Until then, boolean flags suffice. Competitive analysis deferred. |
| 6 | **Keep existing `NEXT_PUBLIC_*` vars as build-args** | `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` are infrastructure constants, not feature flags. They belong at build time. |

## Considered Alternatives

### Supabase-backed flag table

- Instant toggling via SQL update (no restart)
- Adds a Supabase query to every page load
- More infrastructure than needed for 1-2 flags
- **Verdict:** Revisit when flag count exceeds ~5 or instant toggling becomes a
  real need

### Third-party provider (PostHog, LaunchDarkly, Statsig)

- Full SDK with dashboard, user targeting, percentage rollouts, A/B testing
- New vendor dependency ($0-100/mo), SDK bundle size (8-30KB), CSP changes,
  DPA review required per Phase 2 security posture
- Overkill for 0 external users and 1-2 boolean flags
- **Verdict:** Defer competitive analysis to Phase 4 prep when per-user targeting
  is actually needed

## Open Questions

1. Should the `/api/flags` endpoint require authentication, or is it public
   (flag names are non-sensitive, values are booleans)?
2. Should flags be cached on the client (localStorage/sessionStorage) or
   fetched fresh on every page navigation?
3. Naming convention for flag env vars -- `FLAG_KB_CHAT_SIDEBAR` vs
   `FF_KB_CHAT_SIDEBAR` vs `FEATURE_KB_CHAT_SIDEBAR`?

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance,
Support

### Engineering (CTO)

**Summary:** Zero React Context providers exist in the app. SSR hydration
mismatch is the biggest risk with runtime flags (server render vs client
first-render). Recommended starting with a `/api/flags` endpoint reading runtime
env vars -- the React Context it introduces becomes the injection point for a
provider SDK later. The existing `NEXT_PUBLIC_*` infrastructure constants must
stay as build-args.

### Operations (COO)

**Summary:** Current spend is ~$32-41/mo. Adding a paid flag provider is a
20-25% cost increase for pre-revenue. Zero feature flags exist today -- all
three `NEXT_PUBLIC_*` vars are infrastructure constants. Recommended building
the first use case with zero new dependencies before evaluating vendors. A
documented learning already captures the exact Docker/NEXT_PUBLIC baking pain
point.

### Product (CPO)

**Summary:** Phase 3 has 37 open issues remaining. Phase 4 is where gradual
rollout to 10 founders actually needs per-user flag targeting. The pain is
anticipated rather than experienced -- `git revert` + deploy is an adequate
kill switch with 0 users. Recommended deferring third-party evaluation to
Phase 4 prep and building the lightweight solution now.
