---
name: feat-flagsmith-adoption
title: Adopt Flagsmith SaaS for runtime feature flags (Phase 4 follow-on)
date: 2026-05-21
branch: feat-flagsmith-adoption
predecessor: knowledge-base/project/specs/feat-feature-flag-provider/spec.md
predecessor-brainstorm: knowledge-base/project/brainstorms/2026-04-16-runtime-feature-flags-brainstorm.md
status: draft (awaiting user approval before code)
---

# Plan: Adopt Flagsmith SaaS for runtime feature flags

## Context

The runtime feature-flag system shipped in PR #2408 (issue #2409, now CLOSED) intentionally
deferred third-party provider adoption to a later phase. That phase is this plan.

Today's state in `main`:
- `apps/web-platform/lib/feature-flags/server.ts` — env-var-backed `getFlag()` / `getFeatureFlags()` reading `process.env.FLAG_*` at request time.
- `apps/web-platform/app/api/flags/route.ts` — public `GET /api/flags` exposing all flag states.
- Two flags in production: `kb-chat-sidebar` (FLAG_KB_CHAT_SIDEBAR) and `command-center-soleur-go` (FLAG_CC_SOLEUR_GO).
- Real server-side consumer: `apps/web-platform/server/ws-handler.ts:604` reads `command-center-soleur-go` via `getFlag()`.
- Client-side React Context provider + `useFeatureFlag()` hook from the original spec were **never implemented** (no consumers in the client tree today). This plan finishes that work.

## Setup state already in place (completed pre-plan, 2026-05-21)

Pre-plan operations (outside the code diff) finished before this plan was approved, to unblock the rest of the work:

| What | Result |
|---|---|
| Flagsmith organisation | `Soleur` (id 29821) |
| Flagsmith project | `web-platform` (id 39082) |
| Flagsmith environments | `Development`, `Production` (auto-created) |
| Flagsmith feature: `kb-chat-sidebar` | Created. dev=ON, prd=ON. Description references `FLAG_KB_CHAT_SIDEBAR` Doppler fallback. |
| Flagsmith feature: `command-center-soleur-go` | Created. dev=ON, prd=ON. Description references `FLAG_CC_SOLEUR_GO` Doppler fallback. |
| Doppler `dev.FLAGSMITH_ENVIRONMENT_KEY` | Set to dev env's server-side SDK key. |
| Doppler `prd.FLAGSMITH_ENVIRONMENT_KEY` | Set to prd env's server-side SDK key. |
| Doppler existing `FLAG_*` vars | UNCHANGED. Both `=1` in dev and prd (confirmed via `doppler secrets get`). Stay as env-var fallback. |

**Important**: Flagsmith Production was deliberately set to mirror **current Doppler `prd` state** (both flags ON), not the ADR-022 documented state. See "Findings" below.

## Findings (need user awareness, not blocking)

1. **ADR-022 drift.** ADR-022-sdk-as-router.md:72 and `2026-04-23-feat-cc-route-via-soleur-go-plan.md:359` both state `FLAG_CC_SOLEUR_GO=false` in Doppler `prd`. Actual current value is `=1`. Either the 14-day dev soak passed and the flag was flipped without an ADR amendment, or there is drift. Flagsmith was configured to match current Doppler reality, not the stale ADR. **Action item (separate PR)**: amend ADR-022 with the soak-completion date and current production state.
2. **`.env.example` mismatch.** `apps/web-platform/.env.example:79,86` show `FLAG_KB_CHAT_SIDEBAR=0` / `FLAG_CC_SOLEUR_GO=0` (the safer documentation defaults). Doppler reality differs. The `.env.example` defaults are appropriate for a fresh local checkout, so they stay as-is — the example file is the local-dev fallback, not the prod truth.

## Goals

- **G1**: Source of truth for flag state becomes Flagsmith SaaS, with `process.env.FLAG_*` as a graceful fallback when the SDK is unreachable.
- **G2**: Public Server API of `lib/feature-flags/server.ts` (`getFlag(name)`, `getFeatureFlags()`) is **unchanged** — zero changes at call sites (`ws-handler.ts`, `/api/flags`).
- **G3**: Ship the client `FeatureFlagProvider` + `useFeatureFlag(name)` hook deferred in the original spec, hydrating from `/api/flags` (no client-side Flagsmith SDK; server-side SDK only).
- **G4**: Flagsmith outage cannot dark-launch features. Behavior on SDK failure mirrors today's env-var-only behavior exactly.

## Non-goals (out of scope)

- Per-user targeting, segments, identity rules (no traits passed; we still resolve global booleans).
- A/B testing or experiment framework.
- Migrating Flagsmith from SaaS to self-hosted (env-driven base URL is included so this can be done later without a code change).
- Backfilling Flagsmith into CI/dev_scheduled/prd_scheduled/prd_terraform/prd_cla/prd_kb_drift_walker Doppler configs. Only `dev` + `prd` get `FLAGSMITH_ENVIRONMENT_KEY` in V1; other configs continue to use env-var fallback. (See Out-of-scope §2 below.)

## Implementation plan

### Stage 1 — Install SDK

- Add `flagsmith-nodejs` to `apps/web-platform/package.json` dependencies (latest stable).
- `bun install` from the worktree root (per existing workspace pattern).

### Stage 2 — Rewrite `lib/feature-flags/server.ts` internals (public API unchanged)

New module shape:

```ts
import Flagsmith from "flagsmith-nodejs";

const FLAG_VARS = {
  "kb-chat-sidebar": "FLAG_KB_CHAT_SIDEBAR",
  "command-center-soleur-go": "FLAG_CC_SOLEUR_GO",
} as const;

type FlagName = keyof typeof FLAG_VARS;

// Single module-scoped client; lazy init on first call so tests can stub.
let _client: Flagsmith | null = null;
function client(): Flagsmith | null {
  if (_client) return _client;
  const key = process.env.FLAGSMITH_ENVIRONMENT_KEY;
  if (!key) return null;                                  // no key → fall back to env vars
  _client = new Flagsmith({
    environmentKey: key,
    apiUrl: process.env.FLAGSMITH_API_URL ?? "https://edge.api.flagsmith.com/api/v1/",
    enableLocalEvaluation: false,                         // remote eval keeps memory + cold-start small
    requestTimeoutSeconds: 0.2,                           // 200ms ceiling — never block request path
  });
  return _client;
}

// Short TTL cache so /api/flags and ws-handler aren't independent calls.
const CACHE_TTL_MS = 30_000;
let _cache: { at: number; flags: Record<FlagName, boolean> } | null = null;

async function fetchFlagsFromFlagsmith(): Promise<Record<FlagName, boolean> | null> {
  const c = client();
  if (!c) return null;
  try {
    const env = await c.getEnvironmentFlags();
    const out = {} as Record<FlagName, boolean>;
    for (const name of Object.keys(FLAG_VARS) as FlagName[]) {
      out[name] = env.isFeatureEnabled(name);
    }
    return out;
  } catch (_err) {
    return null;                                          // any failure → fallback path
  }
}

function envFallback(): Record<FlagName, boolean> {
  const out = {} as Record<FlagName, boolean>;
  for (const [name, envVar] of Object.entries(FLAG_VARS) as [FlagName, string][]) {
    out[name] = process.env[envVar] === "1";
  }
  return out;
}

export async function getFeatureFlags(): Promise<Record<FlagName, boolean>> {
  const now = Date.now();
  if (_cache && now - _cache.at < CACHE_TTL_MS) return _cache.flags;
  const flags = (await fetchFlagsFromFlagsmith()) ?? envFallback();
  _cache = { at: now, flags };
  return flags;
}

export async function getFlag(name: FlagName): Promise<boolean> {
  return (await getFeatureFlags())[name];
}
```

**Critical**: this changes both `getFlag` and `getFeatureFlags` from synchronous to async. There is exactly one call site for `getFlag()` outside the module (`ws-handler.ts:604`) and one for `getFeatureFlags()` (`/api/flags/route.ts`). Both will be updated to `await` (see Stage 3).

### Stage 3 — Update consumers for async API

- `apps/web-platform/server/ws-handler.ts:604` — wrap `getFlag("command-center-soleur-go")` in `await`. The enclosing context (`start_session` handler) is already async, so no shape change.
- `apps/web-platform/app/api/flags/route.ts` — change `return NextResponse.json(getFeatureFlags())` to `return NextResponse.json(await getFeatureFlags())`. Route is `async function GET()` already.
- Sweep: `rg "getFlag\\(|getFeatureFlags\\(" apps/web-platform --type ts --type tsx` to confirm only the above two call sites exist. If any others surface, they get the same `await` treatment.

### Stage 4 — Client `FeatureFlagProvider` + `useFeatureFlag` hook

New files (closing the gap left by the original spec):

- `apps/web-platform/components/feature-flags/provider.tsx` — Client Component. Server Component reads `getFeatureFlags()` at request time, passes them as a `flags` prop to a Client Provider. The provider exposes them via React Context. No client-side Flagsmith SDK, no extra round-trip after initial hydration.
- `apps/web-platform/components/feature-flags/use-feature-flag.ts` — `useFeatureFlag(name): boolean` hook reading the context.
- `apps/web-platform/app/layout.tsx` — wrap `<body>` children in the provider (after fetching flags server-side in the root layout). This is the FIRST React Context provider in the app tree, so the existing layout structure may need a thin extra wrapper component.

This means client components that want to feature-flag UI can do `const enabled = useFeatureFlag("kb-chat-sidebar")` and react accordingly — closing the open AC from the original spec.

### Stage 5 — Tests

- `lib/feature-flags/server.test.ts` — rewrite. Three new test scenarios:
  - SDK returns flags → cache populates → second call serves from cache (no second SDK call).
  - SDK throws → `envFallback()` is used → `getFlag("command-center-soleur-go")` returns the expected boolean from `FLAG_CC_SOLEUR_GO`.
  - `FLAGSMITH_ENVIRONMENT_KEY` unset → no SDK construction, env-var path immediately.
- `components/feature-flags/provider.test.tsx` — render provider with stubbed flags, assert `useFeatureFlag` returns correct values.
- Update `server/ws-handler.test.ts` if it currently mocks `getFlag` — change to `vi.fn().mockResolvedValue(...)`.

### Stage 6 — ADR

Write `knowledge-base/engineering/architecture/decisions/ADR-XXX-feature-flags-flagsmith.md`:

- Decision: adopt Flagsmith SaaS (EU/edge region) for flag evaluation; keep `FLAG_*` env vars as fallback.
- Tradeoffs section captures: vendor lock-in vs build-time velocity gain; SaaS data-residency note (no user traits passed currently — boolean global flags only, so GDPR-trait concern is N/A for V1).
- Operational note: SDK keys are server-side only (live in Doppler, never NEXT_PUBLIC). Flagsmith management API token NOT used in runtime.
- Cross-link the ADR-022 amendment action item.

### Stage 7 — Docs

- Update `.env.example` to add `FLAGSMITH_ENVIRONMENT_KEY=` (empty) and `FLAGSMITH_API_URL=` (commented, optional override).
- Update existing spec `knowledge-base/project/specs/feat-feature-flag-provider/spec.md` with a "Phase 4 follow-on" pointer to this plan.
- Operator runbook entry: how to add a new flag (1: create in Flagsmith UI, 2: add to `FLAG_VARS` const, 3: add corresponding `FLAG_*` env var to Doppler dev + prd as fallback).

## Acceptance criteria

- [ ] **AC1**: With `FLAGSMITH_ENVIRONMENT_KEY` set + Flagsmith reachable, `GET /api/flags` returns the Flagsmith-resolved values. Verified by manual curl against dev container after Doppler restart.
- [ ] **AC2**: With `FLAGSMITH_ENVIRONMENT_KEY` set but Flagsmith unreachable (simulate by blocking outbound to `edge.api.flagsmith.com`), `GET /api/flags` returns `process.env.FLAG_*`-derived values. Verified by integration test.
- [ ] **AC3**: With `FLAGSMITH_ENVIRONMENT_KEY` UNSET (current state for ci/dev_personal/etc.), `getFlag()` returns env-var values without attempting Flagsmith. Verified by unit test.
- [ ] **AC4**: `useFeatureFlag("kb-chat-sidebar")` hook returns the correct boolean in a client component. Verified by component test.
- [ ] **AC5**: `ws-handler.ts` start_session path returns the same routing decision as before for the same Doppler config (no behavior delta in prd from this PR alone — the cutover is purely an internal implementation swap).
- [ ] **AC6**: `bun run typecheck` and `bun run test` pass in `apps/web-platform`.
- [ ] **AC7**: Doppler `dev` and `prd` are the only configs holding `FLAGSMITH_ENVIRONMENT_KEY`; other configs fall through to env-var path (intentional — V1 scope).

## Rollback strategy

- Single revert PR will roll back code; Doppler `FLAGSMITH_ENVIRONMENT_KEY` can stay (orphan secret is harmless).
- If only the SDK call path is broken (not the env-var fallback), removing `FLAGSMITH_ENVIRONMENT_KEY` from Doppler immediately reverts every flag to env-var behavior with no code change.

## Post-merge verification (PM)

- [ ] PM1: After deploy to dev, `curl https://dev.../api/flags` returns `{"kb-chat-sidebar":true,"command-center-soleur-go":true}` (matches current state).
- [ ] PM2: Flip `kb-chat-sidebar` OFF in Flagsmith dev UI. Wait ≤30s (cache TTL). `curl` again — should now be `false`. Flip back ON.
- [ ] PM3: In Sentry, filter `tag:feature=flagsmith` over the next 24h. Zero unhandled errors expected (SDK failures are caught and fall back to env vars).

## Out-of-scope (deferred follow-ons)

1. ADR-022 amendment for the `FLAG_CC_SOLEUR_GO=true` prd flip (separate small PR).
2. CI / dev_scheduled / prd_scheduled / prd_terraform / prd_cla / prd_kb_drift_walker Doppler configs do not get `FLAGSMITH_ENVIRONMENT_KEY`. They continue to read flag state from `FLAG_*` env vars. Decision: not needed until one of those configs runs the web-platform request path against real users.
3. Per-user / per-cohort targeting (Flagsmith identities/traits) — deferred to V2.
4. Local-evaluation mode (`enableLocalEvaluation: true`) — defer until we measure latency on the remote-evaluation path. Local mode requires a server-side environment key with elevated perms and adds a periodic polling thread; not worth it for 2 flags.
