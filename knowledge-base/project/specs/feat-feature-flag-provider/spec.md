# Spec: Runtime Feature Flags

**Issue:** #2409
**Branch:** `feat-feature-flag-provider`
**Status:** Draft
**Brainstorm:** `knowledge-base/project/brainstorms/2026-04-16-runtime-feature-flags-brainstorm.md`

## Problem Statement

Feature visibility toggles use `NEXT_PUBLIC_*` env vars which Next.js inlines
into the client JS bundle at build time. Changing a flag requires a full Docker
rebuild and redeploy (5-10 minutes). The founder needs to toggle feature
visibility with a container restart (~30 seconds), not a rebuild.

## Goals

- G1: Toggle feature flags without rebuilding Docker images
- G2: Provide a React Context-based flag system for client components
- G3: Establish a pattern that can be upgraded to a third-party provider later

## Non-Goals

- Per-user targeting or percentage rollouts (deferred to Phase 4)
- Third-party feature flag provider integration (deferred)
- A/B testing or experiment framework
- Migrating existing `NEXT_PUBLIC_SUPABASE_URL`/`NEXT_PUBLIC_SUPABASE_ANON_KEY`
  (these are infrastructure constants, not flags)
- Admin UI for managing flags (Doppler dashboard suffices)

## Functional Requirements

- **FR1:** Server-side `/api/flags` endpoint that reads flag env vars from
  `process.env` at request time and returns a JSON object of flag states
- **FR2:** React Context provider wrapping the app root that makes flag values
  available to all client components via a `useFeatureFlag(name)` hook
- **FR3:** Server Component support -- flags readable in Server Components via
  a direct `process.env` read (no Context needed server-side)
- **FR4:** Type-safe flag names -- TypeScript enum or const object defining all
  valid flag keys

## Technical Requirements

- **TR1:** The `/api/flags` route must export only HTTP method handlers per
  rule `cq-nextjs-route-files-http-only-exports`
- **TR2:** Flag env vars must NOT use the `NEXT_PUBLIC_` prefix (those are
  baked at build time)
- **TR3:** The endpoint must not leak server-side secrets -- return only flag
  boolean values, not env var names or other config
- **TR4:** CSP policy (`lib/csp.ts`) requires no changes (endpoint is
  same-origin)
- **TR5:** Flag env vars must be added to `.env.example` with documentation
- **TR6:** Agent subprocess env allowlist (`server/agent-env.ts`) must NOT
  include flag vars (they are not needed by agent processes)

## Acceptance Criteria

- [ ] Changing a flag value in Doppler `prd` + `docker restart` toggles the
      feature in production without a Docker rebuild
- [ ] A `useFeatureFlag("kb-chat-sidebar")` hook returns the correct boolean
      in client components
- [ ] Server Components can read flags via `process.env.FLAG_KB_CHAT_SIDEBAR`
- [ ] The existing `NEXT_PUBLIC_*` build-args pipeline is unchanged
- [ ] TypeScript compilation catches invalid flag names at build time
