# Learning: Next.js NEXT_PUBLIC_ vars require Docker build args

## Problem
After deploying the web platform Docker image, the BYOK setup page showed "Something went wrong" and magic link signup was stuck on "Sending...". Server logs showed `Failed to find Server Action "x"`. The Supabase client on the client side had empty URL and API key.

## Solution
Next.js inlines `NEXT_PUBLIC_` environment variables into the client-side JavaScript bundle at build time (`npm run build`). They are NOT read from the environment at runtime. When the Dockerfile runs `npm run build` without these vars set, the client bundle has empty values — even though the container receives them via `--env-file` at runtime.

**Fix:**
1. Add `ARG` directives to Dockerfile before the build step:
   ```dockerfile
   ARG NEXT_PUBLIC_SUPABASE_URL
   ARG NEXT_PUBLIC_SUPABASE_ANON_KEY
   RUN npm run build
   ```
2. Pass values via `build-args` in CI:
   ```yaml
   - uses: docker/build-push-action@v6
     with:
       build-args: |
         NEXT_PUBLIC_SUPABASE_URL=${{ secrets.NEXT_PUBLIC_SUPABASE_URL }}
         NEXT_PUBLIC_SUPABASE_ANON_KEY=${{ secrets.NEXT_PUBLIC_SUPABASE_ANON_KEY }}
   ```
3. Store the values as GitHub secrets (they're public keys, but secrets keep CI config clean).

## Key Insight
Any `NEXT_PUBLIC_` var used in client-side code MUST be present at `npm run build` time — not just at container runtime. This is the #1 Next.js + Docker gotcha. The symptom is silent: no build error, no runtime error on the server, just empty values in the browser bundle causing client-side failures.

## Secondary Learning: Cloudflare per-hostname SSL override
When a Cloudflare zone has "strict" SSL (e.g., for GitHub Pages) but a subdomain needs "flexible" SSL (HTTP origin), use a Configuration Rule via the rulesets phase entrypoint API rather than changing the zone-wide setting. This keeps the main site secure while allowing HTTP origin for specific subdomains.

## Session Errors
- Cloudflare MCP failed to connect — used Playwright browser API as workaround
- Cloudflare ruleset PUT failed with stale ID — used phase entrypoint endpoint instead
- Supabase admin `generate_link` uses implicit flow (hash fragment), not PKCE — incompatible with SSR callback route expecting `code` param
- WebSocket flipping between Connected/Reconnecting — missing ping keepalive for Cloudflare's 100s idle timeout

## Tags
category: build-errors
module: web-platform
