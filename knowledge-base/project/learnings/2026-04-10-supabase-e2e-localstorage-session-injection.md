# Learning: Supabase E2E tests need localStorage session injection

## Problem

E2E tests for the command center empty state failed in CI. The dashboard page
checks `conversations.length === 0 && !hasActiveFilter && !error` to render the
command center. The `useConversations` hook calls `supabase.auth.getUser()`,
which checks localStorage for an existing session before making any HTTP call.
With no stored session, the Supabase JS client returns an auth error locally
without hitting the network, so `page.route("**/auth/v1/user")` mocks never
fire. This sets `error: "Authentication required"`, and the command center never
renders.

## Solution

Add `page.addInitScript()` in `setupDashboardMocks()` to inject a fake Supabase
session into localStorage under the key `sb-localhost-auth-token` before page
navigation. This ensures the Supabase JS client finds a valid session on
initialisation, uses the access token in HTTP headers, and the `page.route()`
mocks intercept the requests as expected.

The storage key format is `sb-{ref}-auth-token` where `{ref}` is extracted from
the Supabase URL. For `http://localhost:54399`, the ref is `localhost`.

## Key Insight

When mocking Supabase in Playwright E2E tests, HTTP-level mocks (`page.route`)
are necessary but not sufficient. The `@supabase/ssr` browser client checks
localStorage first and can short-circuit auth flows without making any HTTP
request. Both the cookie (for server-side middleware auth via `storageState`)
and localStorage (for client-side JS SDK auth via `addInitScript`) must be
seeded for the full auth chain to work.

## Tags

category: test-failures
module: web-platform/e2e
