# Learning: startsWith path matching in Next.js middleware allows unintended bypasses

## Problem

Next.js middleware using `PUBLIC_PATHS.some(p => pathname.startsWith(p))` to skip auth on public routes creates a security gap. Any path that shares a prefix with a public path (e.g., `/accept-terms-evil`, `/api/webhooks-internal`, `/login-admin`) bypasses authentication and all downstream middleware checks silently.

## Solution

Use exact-or-prefix-with-slash matching instead:

```typescript
PUBLIC_PATHS.some((p) => pathname === p || pathname.startsWith(p + "/"));
```

This ensures `/accept-terms` matches but `/accept-terms-evil` does not, while still allowing sub-routes like `/api/webhooks/stripe`.

## Key Insight

Prefix-based routing checks (`startsWith`) are a common source of auth bypasses in web frameworks. The fix is a one-line change but the vulnerability is invisible until a route is added that collides with a public prefix. Always test with adversarial path names (e.g., append `-evil` to each public path) in routing tests.

## Tags

category: security-issues
module: web-platform/middleware
