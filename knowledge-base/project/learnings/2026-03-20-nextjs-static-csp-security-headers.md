# Learning: Static CSP Security Headers via Pure Function in Next.js Config

## Problem

The web platform (`apps/web-platform`) returned no security headers on any response -- no Content-Security-Policy, no X-Frame-Options, no Strict-Transport-Security, no X-Content-Type-Options. Every page was vulnerable to clickjacking, MIME-sniffing attacks, and had no CSP to constrain script/style/connect sources. Issue #946.

## Solution

Created `apps/web-platform/lib/security-headers.ts` as a pure function that returns the `headers()` array consumed by `next.config.ts`. The function builds a static Content-Security-Policy string from a structured config object, then returns it alongside X-Frame-Options, HSTS, X-Content-Type-Options, Referrer-Policy, Permissions-Policy, Cross-Origin-Opener-Policy, and Cross-Origin-Resource-Policy.

Key design choices:

- **Static CSP via `next.config.ts` `headers()`** -- No middleware, no per-request nonce generation. The CSP is computed once at build time and served as a static header on all matching routes. This is sufficient when no third-party scripts require nonces (the platform uses only first-party code and Supabase).
- **Pure function extraction** -- `getSecurityHeaders()` takes no arguments and has no framework dependencies. Vitest can import and test it directly without mocking Next.js internals. The function returns the exact `{ source, headers }` structure that `next.config.ts` `headers()` expects.
- **Structured CSP config object** -- Directives are defined as `Record<string, string[]>` and serialized into a policy string. This makes it easy to audit which origins are allowed per directive, and to add/remove sources without string surgery.
- **Supabase `connect-src` with build-time guard** -- The Supabase JS client makes browser-side requests from 5 files (auth, realtime, storage, REST, functions). These need both `https://` and `wss://` (for realtime subscriptions) in `connect-src`. The Supabase project URL comes from `NEXT_PUBLIC_SUPABASE_URL`. A production guard (`if (!supabaseUrl) throw`) prevents deploying with an undefined Supabase URL, which would silently break all browser-side Supabase calls. In development, the guard is relaxed to allow `next dev` without the env var set.

Headers applied:

| Header | Value |
|--------|-------|
| Content-Security-Policy | `default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self' https://*.supabase.co wss://*.supabase.co; frame-src 'self'; worker-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'` |
| X-Frame-Options | `DENY` |
| Strict-Transport-Security | `max-age=63072000; includeSubDomains; preload` |
| X-Content-Type-Options | `nosniff` |
| Referrer-Policy | `strict-origin-when-cross-origin` |
| Permissions-Policy | `camera=(), microphone=(), geolocation=()` |
| Cross-Origin-Opener-Policy | `same-origin` |
| Cross-Origin-Resource-Policy | `same-origin` |

Follow-up issues filed: #953 (nonce-based CSP for future third-party scripts), #954 (HSTS preload list submission confirmation).

## Key Insight

When a Next.js app serves only first-party code (no Google Analytics, no third-party widgets, no inline scripts requiring nonces), static CSP via `next.config.ts` `headers()` is strictly simpler than middleware-based nonce injection. The middleware approach adds per-request overhead, requires `<meta>` tag or header injection for the nonce, and complicates caching -- all for a capability (per-request nonces) that is unnecessary when `script-src 'self'` suffices.

The pure function extraction pattern (`lib/security-headers.ts` returning the `headers()` array) enables direct vitest testing of the security configuration without needing to spin up a Next.js server or mock `next/server`. This pattern generalizes: any Next.js config section that accepts a function (`headers()`, `redirects()`, `rewrites()`) can be extracted into a testable pure function.

For Supabase specifically: audit browser-side usage to find all connection patterns. The JS client uses HTTPS for REST/auth/storage/functions and WSS for realtime subscriptions. Both protocols must appear in `connect-src`, and using `*.supabase.co` wildcards avoids hardcoding the project ID while still constraining the origin.

## Session Errors

1. **Stale vitest/rolldown native binary via npx cache** -- Running `npx vitest` before `npm install` in the web-platform app caused a native module crash (`Error: Cannot find module @rolldown/binding-linux-x64-gnu`). The npx cache had a mismatched binary from a previous session. Fix: always run `npm install` in the app directory before the first test run in a new worktree. This is the same error documented in the open-redirect learning -- it is a recurring footgun when working across worktrees.
2. **`git add` from wrong CWD** -- Ran `git add` from `apps/web-platform/` instead of the worktree root, causing git to fail to find the expected paths. Fix: always `cd` back to the worktree root before staging files. The guardrail is to run `pwd` before any git command, as specified in AGENTS.md.

## Tags

category: security
module: apps/web-platform
