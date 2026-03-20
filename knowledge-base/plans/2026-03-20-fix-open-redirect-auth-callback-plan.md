---
title: "fix: validate redirect origin in auth callback against allowlist"
type: fix
date: 2026-03-20
---

# fix: open redirect via x-forwarded-host in auth callback

## Overview

The auth callback route (`apps/web-platform/app/(auth)/callback/route.ts`) constructs redirect URLs from attacker-controlled `x-forwarded-host` and `x-forwarded-proto` request headers. An attacker can send `GET /callback?code=...` with `X-Forwarded-Host: evil.com` to redirect authenticated users to a malicious domain, enabling phishing or session token theft.

The vulnerability is **trivially exploitable** because:

1. The container is exposed directly on ports 80 and 3000 (`-p 0.0.0.0:80:3000 -p 0.0.0.0:3000:3000`)
2. The Hetzner firewall allows port 80 and 3000 from `0.0.0.0/0`
3. Direct requests bypass Cloudflare, so no trusted proxy overwrites the forwarded headers

## Problem Statement

Lines 8-11 of `apps/web-platform/app/(auth)/callback/route.ts`:

```typescript
const forwardedHost = request.headers.get("x-forwarded-host");
const forwardedProto = request.headers.get("x-forwarded-proto") ?? "https";
const host = forwardedHost ?? request.headers.get("host") ?? "app.soleur.ai";
const origin = `${forwardedProto}://${host}`;
```

This `origin` is used in three `NextResponse.redirect()` calls (lines 44, 46, 53) without any validation. The attacker controls both the protocol and host components of the redirect target.

## Proposed Solution

**Validate `origin` against an allowlist of known domains.** Fall back to the canonical production URL when the computed origin is not in the allowlist.

```typescript
// apps/web-platform/app/(auth)/callback/route.ts
const ALLOWED_ORIGINS = new Set([
  "https://app.soleur.ai",
  "http://localhost:3000",
]);

const forwardedHost = request.headers.get("x-forwarded-host");
const forwardedProto = request.headers.get("x-forwarded-proto") ?? "https";
const host = forwardedHost ?? request.headers.get("host") ?? "app.soleur.ai";
const computedOrigin = `${forwardedProto}://${host}`;
const origin = ALLOWED_ORIGINS.has(computedOrigin)
  ? computedOrigin
  : "https://app.soleur.ai";
```

### Why not remove forwarded headers entirely?

Cloudflare (`proxied = true` in `dns.tf`) sets `X-Forwarded-Host` and `X-Forwarded-Proto` on legitimate requests. The `host` header behind Cloudflare is the origin server IP, not `app.soleur.ai`. Removing forwarded header support would break redirects for all Cloudflare-proxied traffic. The allowlist approach preserves correct behavior for legitimate proxied requests while blocking malicious values.

### Why not use an environment variable?

The allowlist is a security boundary. Hardcoding it prevents misconfiguration via environment variables and makes the boundary auditable in code review. The values are stable: `app.soleur.ai` (production) and `localhost:3000` (development). If staging is added later, a single line addition is required.

## Technical Considerations

### Attack Surface Enumeration

All code paths that use `origin` for redirects in the auth callback:

| Line | Redirect Target | Checked by Fix? |
|------|----------------|-----------------|
| 44 | `${origin}/setup-key` | Yes -- `origin` is validated |
| 46 | `${origin}/dashboard` | Yes -- `origin` is validated |
| 53 | `${origin}/login?error=auth_failed` | Yes -- `origin` is validated |

**Other redirect paths in the app:**

| File | Mechanism | Safe? |
|------|-----------|-------|
| `middleware.ts:59` | `request.nextUrl.clone()` with `url.pathname = "/login"` | Yes -- uses `nextUrl` which preserves the original request URL, not forwarded headers |

No other `NextResponse.redirect()` calls use attacker-controlled origins.

### Supabase Redirect Configuration

The Supabase auth config (`supabase/scripts/configure-auth.sh`) defines:
- `site_url`: `https://app.soleur.ai`
- `uri_allow_list`: `http://localhost:3000/**,https://app.soleur.ai/**`

The `ALLOWED_ORIGINS` set should mirror the Supabase `uri_allow_list` domains. This is currently consistent.

### Infrastructure Note

The firewall (`infra/firewall.tf`) exposes ports 80 and 3000 to `0.0.0.0/0`. Restricting these to Cloudflare IPs would be defense-in-depth but is out of scope for this fix and should be tracked separately.

## Acceptance Criteria

- [ ] `origin` used in `NextResponse.redirect()` calls is validated against a hardcoded allowlist of known domains
- [ ] Requests with `X-Forwarded-Host: evil.com` redirect to `https://app.soleur.ai/*` (not `evil.com`)
- [ ] Requests with `X-Forwarded-Proto: http` + `X-Forwarded-Host: evil.com` redirect to `https://app.soleur.ai/*`
- [ ] Requests via Cloudflare (legitimate `X-Forwarded-Host: app.soleur.ai`) still redirect correctly
- [ ] Local development (`localhost:3000`) redirects still work
- [ ] Requests with no forwarded headers (direct `host: app.soleur.ai`) redirect correctly
- [ ] Unit tests cover all validation branches in `apps/web-platform/test/callback.test.ts`

## Test Scenarios

### Security Tests

- Given a request with `X-Forwarded-Host: evil.com`, when the callback processes it, then all redirects use `https://app.soleur.ai` as origin
- Given a request with `X-Forwarded-Proto: http` and `X-Forwarded-Host: evil.com`, when the callback processes it, then `http://evil.com` is rejected and `https://app.soleur.ai` is used
- Given a request with `X-Forwarded-Host: evil.com:3000`, when the callback processes it, then the origin is rejected (port variants are not in the allowlist)

### Functional Tests

- Given a request with `X-Forwarded-Host: app.soleur.ai` and `X-Forwarded-Proto: https`, when the callback processes it, then `https://app.soleur.ai` is used (legitimate Cloudflare traffic)
- Given a request with `Host: localhost:3000` and no forwarded headers, when the callback processes it, then `http://localhost:3000` is used (local dev)
- Given a request with no `Host` and no forwarded headers, when the callback processes it, then `https://app.soleur.ai` is used (fallback)

## MVP

### apps/web-platform/app/(auth)/callback/route.ts (lines 1-11)

```typescript
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { provisionWorkspace } from "@/server/workspace";
import { NextResponse } from "next/server";

const ALLOWED_ORIGINS = new Set([
  "https://app.soleur.ai",
  "http://localhost:3000",
]);

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const code = searchParams.get("code");
  const forwardedHost = request.headers.get("x-forwarded-host");
  const forwardedProto = request.headers.get("x-forwarded-proto") ?? "https";
  const host = forwardedHost ?? request.headers.get("host") ?? "app.soleur.ai";
  const computedOrigin = `${forwardedProto}://${host}`;
  const origin = ALLOWED_ORIGINS.has(computedOrigin)
    ? computedOrigin
    : "https://app.soleur.ai";

  // ... rest of file unchanged
```

### apps/web-platform/test/callback.test.ts

```typescript
import { describe, test, expect } from "vitest";

const ALLOWED_ORIGINS = new Set([
  "https://app.soleur.ai",
  "http://localhost:3000",
]);

function resolveOrigin(
  forwardedHost: string | null,
  forwardedProto: string | null,
  host: string | null,
): string {
  const proto = forwardedProto ?? "https";
  const resolvedHost = forwardedHost ?? host ?? "app.soleur.ai";
  const computed = `${proto}://${resolvedHost}`;
  return ALLOWED_ORIGINS.has(computed) ? computed : "https://app.soleur.ai";
}

describe("auth callback origin validation", () => {
  test("rejects malicious x-forwarded-host", () => {
    expect(resolveOrigin("evil.com", "https", "app.soleur.ai")).toBe(
      "https://app.soleur.ai",
    );
  });

  test("rejects malicious proto + host combination", () => {
    expect(resolveOrigin("evil.com", "http", "app.soleur.ai")).toBe(
      "https://app.soleur.ai",
    );
  });

  test("accepts legitimate Cloudflare-proxied request", () => {
    expect(resolveOrigin("app.soleur.ai", "https", null)).toBe(
      "https://app.soleur.ai",
    );
  });

  test("accepts localhost for development", () => {
    expect(resolveOrigin(null, "http", "localhost:3000")).toBe(
      "http://localhost:3000",
    );
  });

  test("falls back to production when no headers present", () => {
    expect(resolveOrigin(null, null, null)).toBe("https://app.soleur.ai");
  });

  test("rejects port variants not in allowlist", () => {
    expect(resolveOrigin("evil.com:3000", null, null)).toBe(
      "https://app.soleur.ai",
    );
  });
});
```

## References

- Issue: #932
- Related: #925 (security review that found this)
- Vulnerable file: `apps/web-platform/app/(auth)/callback/route.ts:8-11`
- Supabase auth config: `apps/web-platform/supabase/scripts/configure-auth.sh:40-41`
- Infrastructure: `apps/web-platform/infra/firewall.tf` (ports 80/3000 open to 0.0.0.0/0)
- Infrastructure: `apps/web-platform/infra/dns.tf:7` (`proxied = true`)
- Deployment: `apps/web-platform/infra/cloud-init.yml:125-126` (container port mapping)
