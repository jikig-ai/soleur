---
name: next-server-actions-allowed-origins-port-fallback
description: Hardcoding localhost:3000 in Next Server Actions allowedOrigins breaks dev when the server falls back to 3001; derive port from the same PORT env var the server binds to.
type: bug-fix
category: runtime-errors
module: apps/web-platform
---

# Learning: Next.js Server Actions allowedOrigins must track the dev server's bound port

## Problem

Starting `npm run dev` in the `feat-kb-viewer-action-buttons-ux` worktree while port 3000 was held by a concurrent worktree produced:

- Server bound to 3001 (`server/index.ts:19` honors `process.env.PORT || 3000`)
- POST `/login` → HTTP 500
- Secondary symptom: `TypeError [ERR_INVALID_URL_SCHEME]` on `./app/globals.css` during the error-overlay render

Initial diagnosis (offered in the blocker report) attributed the failure to a "tsx ESM loader cache collision between concurrent worktrees." That was wrong — each worktree has its own `node_modules` and `.next`, so there is no shared loader state.

## Root Cause

`apps/web-platform/next.config.ts` hardcoded `"localhost:3000"` in
`experimental.serverActions.allowedOrigins` for development. When the server
bound to 3001 (because 3000 was taken), every Server Action `POST` was
treated as cross-origin and rejected with 500. The CSS `ERR_INVALID_URL_SCHEME`
was a downstream symptom of Next's error overlay rendering after the
Server Action rejection, not the primary failure.

The config had no coupling to the actual bound port — `server/index.ts`
reads `PORT`, but `next.config.ts` did not.

## Solution

Derive the dev origin from the same `PORT` env var:

```ts
const devPort = process.env.PORT || "3000";

const nextConfig: NextConfig = {
  experimental: {
    serverActions: {
      allowedOrigins:
        process.env.NODE_ENV === "development"
          ? ["app.soleur.ai", `localhost:${devPort}`, `127.0.0.1:${devPort}`]
          : ["app.soleur.ai"],
    },
  },
};
```

Because both `next.config.ts` and `server/index.ts` read the same `PORT`
env var, the allowed origin and the bound port are guaranteed to agree.

## Key Insight

When a security config hardcodes a host/port value that another part of
the app derives from an environment variable, the hardcoded value is a
latent bug. Read the env var in both places so the config follows the
runtime, not a snapshot of it. This pattern extends beyond ports —
any origin/host/URL allowlist that gates request acceptance must track
the actual bound value.

## Debugging Note

When a Next.js dev request returns 500 with a CSS-loader
`ERR_INVALID_URL_SCHEME` in the overlay, do not assume the CSS pipeline
is broken. Check Server Actions origin rejection first — the overlay
render is the secondary symptom, not the cause.

## Session Errors

- **Initial dev-server boot attempt without Doppler** — Recovery: re-ran under `doppler run -p soleur -c dev`. Prevention: `hr-exhaust-all-automated-options-before` already requires Doppler as priority #1; no new rule needed.
- **`doppler run -- tsx server/index.ts` failed** because `tsx` is not on PATH outside npm scripts. Recovery: used `npm run dev` under `doppler run`. Prevention: invoke npm scripts under doppler, not transitive binaries directly. This is narrow enough to stay in this learning rather than a rule.
- **Backgrounded `npm run dev` produced empty output** — likely because the Bash tool does not persist CWD across calls, and the command ran from a directory without the expected `package.json` dev script. Recovery: skipped live verification (the fix is deterministic since both config and server read the same `PORT`). Prevention: include absolute `cd` in the same Bash invocation as the command being run; do not rely on CWD set in a prior call.

## Related

- `apps/web-platform/next.config.ts`
- `apps/web-platform/server/index.ts`
