---
title: "feat: Runtime feature flags via server-side env vars"
type: feat
date: 2026-04-16
---

# Runtime Feature Flags via Server-Side Env Vars

## Overview

Add a runtime feature flag system that reads server-side env vars at request
time and passes boolean values as props to client components. This decouples
feature visibility from Docker rebuilds — flags toggle with a Doppler change +
container restart (~30s) instead of a full rebuild (~5-10 min).

**Issue:** #2409
**Brainstorm:** `knowledge-base/project/brainstorms/2026-04-16-runtime-feature-flags-brainstorm.md`
**Spec:** `knowledge-base/project/specs/feat-feature-flag-provider/spec.md`

## Research Reconciliation — Spec vs. Codebase

| Spec Claim | Codebase Reality | Plan Response |
|---|---|---|
| "Zero React Context providers" | `hooks/use-team-names.tsx` exports `TeamNamesProvider` | Irrelevant — this plan uses server-side props, not Context. |
| "Three `NEXT_PUBLIC_*` vars" | Dockerfile declares 6 build-time ARGs | None are flags. All stay as build-args. |
| "KB chat sidebar has no flag gate" | Confirmed — PR #2347 merged unconditionally. `NEXT_PUBLIC_KB_CHAT_SIDEBAR` in Doppler but not in code. | Phase 2 wires the first flag gate. |

## Proposed Solution

One new file, one layout/page edit, one `.env.example` update:

```text
apps/web-platform/
  lib/feature-flags/
    server.ts         -- getFeatureFlags() reads process.env at runtime
  app/
    (dashboard)/kb/
      layout.tsx      -- Read flag, conditionally render sidebar (or page that renders it)
```

**Why not an API route + React Context?** Plan review (DHH, Kieran, Simplicity)
identified that App Router renders server-first. Reading `process.env` in a
server component and passing a boolean prop is simpler, avoids hydration
mismatch (client hook starts `false` then flips to `true`), and eliminates an
unnecessary HTTP round-trip. When we need 5+ flags or client-only consumers,
add the Context then.

## Technical Considerations

### Critical constraints from institutional learnings

1. **No `NEXT_PUBLIC_` prefix** (learning `2026-03-17`): `NEXT_PUBLIC_*` vars
   are baked at build time. Runtime flags use plain `FLAG_*` env vars read via
   `process.env` in server components.

2. **Dev-mode guard** (learning `2026-04-13`): If flag env vars are missing
   (local dev without Doppler), use `process.env.NODE_ENV === "development"`
   guard, NOT `!== "production"` (latter fires in test env too).

3. **Env var isolation** (learning `2026-03-20`, CWE-526): Flag env vars are
   automatically excluded from agent subprocesses by the existing
   `buildAgentEnv()` allowlist in `server/agent-env.ts`. Do NOT add flag vars
   to the allowlist.

4. **No Dockerfile changes needed**: `FLAG_*` vars are runtime-only (read from
   container environment via `--env-file`). No `ARG` directive needed. State
   this explicitly in `.env.example` to prevent cargo-culting a build arg.

### Naming convention

Use `FLAG_` prefix: `FLAG_KB_CHAT_SIDEBAR=1` (or `0`). Clear intent,
distinguishes from infrastructure vars and secrets.

## Implementation Phases

### Phase 1: Server-side flag reader

**Files to create:**

- `apps/web-platform/lib/feature-flags/server.ts`

  ```typescript
  const FLAG_VARS = {
    "kb-chat-sidebar": "FLAG_KB_CHAT_SIDEBAR",
  } as const;

  type FlagName = keyof typeof FLAG_VARS;

  export function getFeatureFlags(): Record<FlagName, boolean> {
    const flags = {} as Record<FlagName, boolean>;
    for (const [name, envVar] of Object.entries(FLAG_VARS) as [FlagName, string][]) {
      flags[name] = process.env[envVar] === "1";
    }
    return flags;
  }

  export function getFlag(name: FlagName): boolean {
    return process.env[FLAG_VARS[name]] === "1";
  }
  ```

  Adding a new flag = add one line to `FLAG_VARS`. Type safety comes from the
  `as const` assertion — `getFlag("typo")` is a compile error.

### Phase 2: Wire first flag — KB Chat Sidebar

**Files to modify:**

- Locate the server component (layout or page) that renders the KB chat
  sidebar trigger component (from PR #2347). Call `getFlag("kb-chat-sidebar")`
  and conditionally render:

  ```typescript
  import { getFlag } from "@/lib/feature-flags/server";

  // In the server component:
  const showChatSidebar = getFlag("kb-chat-sidebar");

  // In JSX:
  {showChatSidebar && <KbChatTrigger />}
  ```

  If the sidebar trigger is rendered inside a client component that has no
  server parent in the render path, pass the boolean as a prop from the
  nearest server component ancestor.

**Env var setup:**

- Add `FLAG_KB_CHAT_SIDEBAR=0` to `apps/web-platform/.env.example` under a
  new `# --- Runtime Feature Flags ---` section with a comment:
  "Runtime flags (NOT NEXT_PUBLIC_ — read at request time, not build time.
  No Dockerfile ARG needed. Toggle via Doppler + container restart.)"
- Set in Doppler: `doppler secrets set FLAG_KB_CHAT_SIDEBAR=1 -p soleur -c dev`
- Set in Doppler prd: `doppler secrets set FLAG_KB_CHAT_SIDEBAR=0 -p soleur -c prd`

### Phase 3: Tests

**Files to create:**

- `apps/web-platform/lib/feature-flags/server.test.ts`

  ```typescript
  // Test getFeatureFlags() reads env vars correctly
  // Test getFlag() returns false for missing vars
  // Test getFlag() returns true when var is "1"
  // Test getFlag() returns false when var is "0" or any other value
  ```

**Verification:**

- Run `node node_modules/vitest/vitest.mjs run lib/feature-flags/` (worktree vitest rule)
- Run `next build` locally to verify no route export violations

## Acceptance Criteria

- [ ] `getFlag("kb-chat-sidebar")` returns `true` when `FLAG_KB_CHAT_SIDEBAR=1`
- [ ] `getFlag("kb-chat-sidebar")` returns `false` when var is unset or `0`
- [ ] Changing `FLAG_KB_CHAT_SIDEBAR` in Doppler `prd` + `docker restart`
      toggles sidebar visibility without Docker rebuild
- [ ] TypeScript catches `getFlag("typo")` at compile time
- [ ] Existing `NEXT_PUBLIC_*` build-args pipeline unchanged
- [ ] All existing tests pass
- [ ] `next build` succeeds

## Test Scenarios

- Given `FLAG_KB_CHAT_SIDEBAR=1` in env, when `getFlag("kb-chat-sidebar")`
  is called, then returns `true`
- Given `FLAG_KB_CHAT_SIDEBAR` is unset, when `getFlag("kb-chat-sidebar")`
  is called, then returns `false`
- Given `FLAG_KB_CHAT_SIDEBAR=0` in env, when `getFlag("kb-chat-sidebar")`
  is called, then returns `false`
- Given `FLAG_KB_CHAT_SIDEBAR=yes` in env, when `getFlag("kb-chat-sidebar")`
  is called, then returns `false` (only `"1"` is truthy)
- Given flag is off, when KB page loads, then chat sidebar trigger is not
  rendered
- Given flag is on, when KB page loads, then chat sidebar trigger is rendered
- **Browser:** Navigate to `/kb`, verify sidebar trigger visibility matches
  flag state
- **API verify:** `doppler run -c dev -- curl -s http://localhost:3000/api/flags 2>/dev/null`
  — endpoint does not exist (expected, no API route in this plan)

## Domain Review

**Domains relevant:** Engineering, Operations, Product

Carried forward from brainstorm domain assessments (2026-04-16). No specialists
recommended by name.

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Server-side prop passing is the simplest approach for App Router.
Avoids hydration mismatch, no client-side fetch latency. Upgrade to Context when
client-only consumers appear.

### Operations (COO)

**Status:** reviewed
**Assessment:** Zero new vendor cost. Stays within existing Doppler workflow.
Container restart toggles flags without rebuild.

### Product (CPO)

**Status:** reviewed
**Assessment:** Adequate for 0 users, 1-2 flags. Defer third-party provider to
Phase 4.

## Alternative Approaches Considered

| Approach | Why Not |
|---|---|
| API route + React Context + hook | Over-engineered for 1 flag. Hydration mismatch. Unnecessary HTTP round-trip. Add when 5+ flags or client-only consumers. |
| Supabase-backed flag table | Adds latency, needs migration. Revisit at 5+ flags. |
| Third-party provider | New vendor, cost, SDK. Deferred to Phase 4. |
| `publicRuntimeConfig` | Deprecated in App Router. Not available. |

## Plan Review Applied

| Reviewer | Finding | Action |
|---|---|---|
| DHH | "150 lines solving a 10-line problem" — use server-side props, not API + Context | Applied: rewrote entire plan to server-side approach |
| Kieran | Hydration mismatch between server-read flag and client hook starting at `false` | Applied: eliminated by using server-side props only |
| Kieran | Type mismatch between `server.ts` return and `types.ts` | Applied: single `FLAG_VARS` const drives both names and types |
| Simplicity | `types.ts` is YAGNI for 1 flag | Applied: removed, types inline in `server.ts` |
| Simplicity | `useMemo` on useState value is no-op | Applied: no Context in plan, irrelevant |
| Simplicity | `FLAG_ENV_MAP` indirection unnecessary | Applied: `FLAG_VARS` is the single source of truth, not an indirection layer |

## References

- Learning — route exports: `knowledge-base/project/learnings/runtime-errors/2026-04-15-nextjs-15-route-file-non-http-exports.md`
- Learning — env var baking: `knowledge-base/project/learnings/2026-03-17-nextjs-docker-public-env-vars.md`
- Learning — subprocess isolation: `knowledge-base/project/learnings/2026-03-20-process-env-spread-leaks-secrets-to-subprocess-cwe-526.md`
- Learning — dev-mode guard: `knowledge-base/project/learnings/runtime-errors/2026-04-13-supabase-env-var-dev-mode-graceful-degradation.md`
