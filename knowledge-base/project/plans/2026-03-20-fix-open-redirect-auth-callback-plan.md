---
title: "fix: validate redirect origin in auth callback against allowlist"
type: fix
date: 2026-03-20
---

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 6
**Research sources used:** OWASP Cheat Sheet Series, Next.js security documentation, Supabase auth redirect docs, CVE-2025-29927 analysis, project learnings (allowlist audit patterns)

### Key Improvements

1. Added OWASP-aligned bypass technique coverage (URL encoding, userinfo abuse, protocol-relative URLs) -- the `Set.has()` exact-match approach inherently resists these
2. Added security logging for rejected origins (detect active exploitation attempts)
3. Added additional test scenarios for URL encoding bypass attempts and subdomain spoofing
4. Identified related CVE-2025-29927 (middleware bypass via `x-middleware-subrequest`) as a separate concern to verify patching status
5. Clarified that `resolveOrigin` should be extracted as a named export for direct testability rather than duplicating logic in tests

# fix: open redirect via x-forwarded-host in auth callback

## Overview

The auth callback route (`apps/web-platform/app/(auth)/callback/route.ts`) constructs redirect URLs from attacker-controlled `x-forwarded-host` and `x-forwarded-proto` request headers. An attacker can send `GET /callback?code=...` with `X-Forwarded-Host: evil.com` to redirect authenticated users to a malicious domain, enabling phishing or session token theft.

The vulnerability is **trivially exploitable** because:

1. The container is exposed directly on ports 80 and 3000 (`-p 0.0.0.0:80:3000 -p 0.0.0.0:3000:3000`)
2. The Hetzner firewall allows port 80 and 3000 from `0.0.0.0/0`
3. Direct requests bypass Cloudflare, so no trusted proxy overwrites the forwarded headers

### Research Insights

**OWASP Classification:** Open Redirect falls under [Broken Access Control (A01:2021)](https://owasp.org/Top10/A01_2021-Broken_Access_Control/) in the OWASP Top 10. The [OWASP Unvalidated Redirects and Forwards Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Unvalidated_Redirects_and_Forwards_Cheat_Sheet.html) recommends allowlist-based validation as the primary mitigation -- which is exactly the approach in this plan.

**Related Next.js Vulnerability:** [CVE-2025-29927](https://projectdiscovery.io/blog/nextjs-middleware-authorization-bypass) (disclosed March 2025) demonstrated that Next.js middleware can be bypassed via the `x-middleware-subrequest` header. While this is a separate vulnerability from the open redirect, it reinforces that header-based security in Next.js requires explicit validation -- the framework does not provide implicit protection. Verify the app is running Next.js >= 15.2.3 or >= 14.2.25 to be patched against CVE-2025-29927.

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

**Validate `origin` against an allowlist of known domains.** Fall back to the canonical production URL when the computed origin is not in the allowlist. Extract the validation logic as a named export for direct testability.

```typescript
// apps/web-platform/app/(auth)/callback/route.ts

const ALLOWED_ORIGINS = new Set([
  "https://app.soleur.ai",
  "http://localhost:3000",
]);

export function resolveOrigin(
  forwardedHost: string | null,
  forwardedProto: string | null,
  host: string | null,
): string {
  const proto = forwardedProto ?? "https";
  const resolvedHost = forwardedHost ?? host ?? "app.soleur.ai";
  const computed = `${proto}://${resolvedHost}`;
  return ALLOWED_ORIGINS.has(computed) ? computed : "https://app.soleur.ai";
}

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const code = searchParams.get("code");
  const origin = resolveOrigin(
    request.headers.get("x-forwarded-host"),
    request.headers.get("x-forwarded-proto"),
    request.headers.get("host"),
  );
  // ... rest unchanged
```

### Research Insights

**Why `Set.has()` exact-match is robust against bypass techniques:**

The OWASP cheat sheet documents several [common bypass techniques](https://owasp.org/www-community/attacks/open_redirect) attackers use against naive redirect validation (e.g., `startsWith()`, regex, or substring matching):

| Bypass Technique | Example | Defeated by `Set.has()`? |
|-----------------|---------|--------------------------|
| URL encoding | `%68%74%74%70%73%3A%2F%2Fevil.com` | Yes -- headers are not URL-decoded by `request.headers.get()` |
| Userinfo abuse | `https://app.soleur.ai@evil.com` | Yes -- the full string does not match any allowlist entry |
| Protocol-relative URL | `//evil.com` | Yes -- `${proto}://evil.com` would produce `https:////evil.com` which is not in the allowlist |
| Subdomain spoofing | `app.soleur.ai.evil.com` | Yes -- exact match fails |
| Port injection | `app.soleur.ai:8080` | Yes -- exact match fails |
| Null byte injection | `app.soleur.ai%00.evil.com` | Yes -- exact match fails |

**`Set.has()` is the strongest possible validation** because it requires an exact match against a finite, hardcoded list. No parsing, no regex, no substring matching -- all common sources of bypass vulnerabilities in redirect validation. This aligns with OWASP's highest-assurance recommendation: "Have the user provide short name, ID or token which is mapped server-side to a full target URL."

### Why not remove forwarded headers entirely?

Cloudflare (`proxied = true` in `dns.tf`) sets `X-Forwarded-Host` and `X-Forwarded-Proto` on legitimate requests. The `host` header behind Cloudflare is the origin server IP, not `app.soleur.ai`. Removing forwarded header support would break redirects for all Cloudflare-proxied traffic. The allowlist approach preserves correct behavior for legitimate proxied requests while blocking malicious values.

### Why not use an environment variable?

The allowlist is a security boundary. Hardcoding it prevents misconfiguration via environment variables and makes the boundary auditable in code review. The values are stable: `app.soleur.ai` (production) and `localhost:3000` (development). If staging is added later, a single line addition is required.

This is consistent with the project's existing security patterns: the `SAFE_TOOLS` array in `tool-path-checker.ts` and the `ALLOWED_IMAGES` map in `ci-deploy.sh` are both hardcoded allowlists for security boundaries (see learnings: `2026-03-20-safe-tools-allowlist-bypass-audit.md`).

### Why not use Next.js `serverActions.allowedOrigins`?

[`serverActions.allowedOrigins`](https://nextjs.org/docs/app/api-reference/config/next-config-js/serverActions) only protects Server Actions (POST requests with Origin/Host comparison). The auth callback is a GET route handler -- `allowedOrigins` does not apply. The allowlist must be implemented at the route handler level.

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

### Research Insights

**Security logging:** Add a `console.warn` when a computed origin is rejected. This provides detection signal for active exploitation attempts without adding complexity. The log should include the rejected origin value (truncated to prevent log injection) but never include the auth code.

```typescript
if (!ALLOWED_ORIGINS.has(computed)) {
  console.warn(
    `[callback] Rejected origin: ${computed.slice(0, 100)}`,
  );
}
```

**Supabase redirect alignment:** The [Supabase redirect URL docs](https://supabase.com/docs/guides/auth/redirect-urls) recommend setting exact redirect URLs in production (not globstar patterns). The Supabase config already uses `http://localhost:3000/**,https://app.soleur.ai/**` which is consistent with the `ALLOWED_ORIGINS` domains. The Supabase-side configuration validates the initial OAuth redirect (browser to Supabase to provider), while `ALLOWED_ORIGINS` validates the post-authentication callback redirect (server-side redirect after code exchange).

### Supabase Redirect Configuration

The Supabase auth config (`supabase/scripts/configure-auth.sh`) defines:

- `site_url`: `https://app.soleur.ai`
- `uri_allow_list`: `http://localhost:3000/**,https://app.soleur.ai/**`

The `ALLOWED_ORIGINS` set should mirror the Supabase `uri_allow_list` domains. This is currently consistent.

### Infrastructure Note

The firewall (`infra/firewall.tf`) exposes ports 80 and 3000 to `0.0.0.0/0`. Restricting these to Cloudflare IPs would be defense-in-depth but is out of scope for this fix and should be tracked separately. File a GitHub issue to track: "infra: restrict port 80/3000 source IPs to Cloudflare ranges."

## Acceptance Criteria

- [x] `origin` used in `NextResponse.redirect()` calls is validated against a hardcoded allowlist of known domains
- [x] `resolveOrigin` is exported as a named function for direct unit testing (no logic duplication in tests)
- [x] Requests with `X-Forwarded-Host: evil.com` redirect to `https://app.soleur.ai/*` (not `evil.com`)
- [x] Requests with `X-Forwarded-Proto: http` + `X-Forwarded-Host: evil.com` redirect to `https://app.soleur.ai/*`
- [x] Requests via Cloudflare (legitimate `X-Forwarded-Host: app.soleur.ai`) still redirect correctly
- [x] Local development (`localhost:3000`) redirects still work
- [x] Requests with no forwarded headers (direct `host: app.soleur.ai`) redirect correctly
- [x] Rejected origins are logged with `console.warn` (truncated, no auth code)
- [x] Unit tests cover all validation branches in `apps/web-platform/test/callback.test.ts`

## Test Scenarios

### Security Tests

- Given a request with `X-Forwarded-Host: evil.com`, when the callback processes it, then all redirects use `https://app.soleur.ai` as origin
- Given a request with `X-Forwarded-Proto: http` and `X-Forwarded-Host: evil.com`, when the callback processes it, then `http://evil.com` is rejected and `https://app.soleur.ai` is used
- Given a request with `X-Forwarded-Host: evil.com:3000`, when the callback processes it, then the origin is rejected (port variants are not in the allowlist)

### Research Insights: Additional Bypass Test Scenarios

- Given a request with `X-Forwarded-Host: app.soleur.ai.evil.com` (subdomain spoofing), when the callback processes it, then the origin is rejected
- Given a request with `X-Forwarded-Host: app.soleur.ai@evil.com` (userinfo abuse), when the callback processes it, then the origin is rejected
- Given a request with `X-Forwarded-Host: APP.SOLEUR.AI` (case variation), when the callback processes it, then the origin is rejected (HTTP headers preserve case; `Set.has()` is case-sensitive)

### Functional Tests

- Given a request with `X-Forwarded-Host: app.soleur.ai` and `X-Forwarded-Proto: https`, when the callback processes it, then `https://app.soleur.ai` is used (legitimate Cloudflare traffic)
- Given a request with `Host: localhost:3000` and no forwarded headers, when the callback processes it, then `http://localhost:3000` is used (local dev)
- Given a request with no `Host` and no forwarded headers, when the callback processes it, then `https://app.soleur.ai` is used (fallback)

## MVP

### apps/web-platform/app/(auth)/callback/route.ts (lines 1-22)

```typescript
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { provisionWorkspace } from "@/server/workspace";
import { NextResponse } from "next/server";

const ALLOWED_ORIGINS = new Set([
  "https://app.soleur.ai",
  "http://localhost:3000",
]);

export function resolveOrigin(
  forwardedHost: string | null,
  forwardedProto: string | null,
  host: string | null,
): string {
  const proto = forwardedProto ?? "https";
  const resolvedHost = forwardedHost ?? host ?? "app.soleur.ai";
  const computed = `${proto}://${resolvedHost}`;
  if (!ALLOWED_ORIGINS.has(computed)) {
    console.warn(`[callback] Rejected origin: ${computed.slice(0, 100)}`);
    return "https://app.soleur.ai";
  }
  return computed;
}

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const code = searchParams.get("code");
  const origin = resolveOrigin(
    request.headers.get("x-forwarded-host"),
    request.headers.get("x-forwarded-proto"),
    request.headers.get("host"),
  );

  // ... rest of file unchanged
```

### apps/web-platform/test/callback.test.ts

```typescript
import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { resolveOrigin } from "../app/(auth)/callback/route";

describe("auth callback origin validation", () => {
  let warnSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});
  });

  afterEach(() => {
    warnSpy.mockRestore();
  });

  // --- Security: malicious origins are rejected ---

  test("rejects malicious x-forwarded-host", () => {
    expect(resolveOrigin("evil.com", "https", "app.soleur.ai")).toBe(
      "https://app.soleur.ai",
    );
    expect(warnSpy).toHaveBeenCalledWith(
      "[callback] Rejected origin: https://evil.com",
    );
  });

  test("rejects malicious proto + host combination", () => {
    expect(resolveOrigin("evil.com", "http", "app.soleur.ai")).toBe(
      "https://app.soleur.ai",
    );
  });

  test("rejects port variants not in allowlist", () => {
    expect(resolveOrigin("evil.com:3000", null, null)).toBe(
      "https://app.soleur.ai",
    );
  });

  test("rejects subdomain spoofing", () => {
    expect(resolveOrigin("app.soleur.ai.evil.com", "https", null)).toBe(
      "https://app.soleur.ai",
    );
  });

  test("rejects userinfo abuse", () => {
    expect(resolveOrigin("app.soleur.ai@evil.com", "https", null)).toBe(
      "https://app.soleur.ai",
    );
  });

  test("rejects case variation (headers preserve case)", () => {
    expect(resolveOrigin("APP.SOLEUR.AI", "https", null)).toBe(
      "https://app.soleur.ai",
    );
  });

  // --- Functional: legitimate origins are accepted ---

  test("accepts legitimate Cloudflare-proxied request", () => {
    expect(resolveOrigin("app.soleur.ai", "https", null)).toBe(
      "https://app.soleur.ai",
    );
    expect(warnSpy).not.toHaveBeenCalled();
  });

  test("accepts localhost for development", () => {
    expect(resolveOrigin(null, "http", "localhost:3000")).toBe(
      "http://localhost:3000",
    );
  });

  test("falls back to production when no headers present", () => {
    expect(resolveOrigin(null, null, null)).toBe("https://app.soleur.ai");
  });
});
```

## References

- Issue: [#932](https://github.com/jikig-ai/soleur/issues/932)
- Related: [#925](https://github.com/jikig-ai/soleur/issues/925) (security review that found this)
- Vulnerable file: `apps/web-platform/app/(auth)/callback/route.ts:8-11`
- Supabase auth config: `apps/web-platform/supabase/scripts/configure-auth.sh:40-41`
- Infrastructure: `apps/web-platform/infra/firewall.tf` (ports 80/3000 open to 0.0.0.0/0)
- Infrastructure: `apps/web-platform/infra/dns.tf:7` (`proxied = true`)
- Deployment: `apps/web-platform/infra/cloud-init.yml:125-126` (container port mapping)
- OWASP: [Unvalidated Redirects and Forwards Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Unvalidated_Redirects_and_Forwards_Cheat_Sheet.html)
- OWASP: [Open Redirect Attack](https://owasp.org/www-community/attacks/open_redirect)
- Next.js: [serverActions.allowedOrigins](https://nextjs.org/docs/app/api-reference/config/next-config-js/serverActions) (not applicable to GET route handlers)
- Supabase: [Redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls)
- Related CVE: [CVE-2025-29927](https://projectdiscovery.io/blog/nextjs-middleware-authorization-bypass) (Next.js middleware bypass -- separate concern, verify patch status)
- Learning: `knowledge-base/project/learnings/2026-03-20-safe-tools-allowlist-bypass-audit.md` (allowlist audit patterns)
