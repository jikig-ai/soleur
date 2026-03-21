# Learning: Middleware DB queries must handle errors explicitly — fail-open vs fail-closed

## Problem

When adding a database query to Next.js middleware (e.g., checking `tc_accepted_at` for T&C enforcement), destructuring only `{ data }` without checking `error` causes the middleware to silently treat Supabase outages as "user has not accepted T&C." This redirects all authenticated users to `/accept-terms` during any Supabase connectivity issue, even users who have already accepted.

## Solution

Always destructure `{ data, error }` from Supabase queries in middleware and handle the error path explicitly:

```typescript
const { data: userRow, error: tcError } = await supabase
  .from("users")
  .select("tc_accepted_at")
  .eq("id", user.id)
  .single();

if (tcError) {
  // Fail open: auth is already verified by getUser()
  console.error(`[middleware] tc_accepted_at query failed: ${tcError.message}`);
  return response;
}
```

For compliance checks (not security boundaries), fail-open is correct — the user is already authenticated. For security-critical checks, fail-closed (503) may be appropriate.

## Key Insight

Every `await` in middleware is a potential failure point. When destructuring Supabase responses, always handle the `error` field. The choice between fail-open and fail-closed should be explicit and documented, not implicit via missing error handling. In this case, a T&C compliance check should fail open because the auth boundary (`getUser()`) is the security gate, not the T&C check.

## Tags

category: runtime-errors
module: web-platform/middleware
