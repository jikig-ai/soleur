# Learning: Silent RLS failures make empty results indistinguishable from auth errors

## Problem

The `@mention` autocomplete dropdown showed "No matches" for custom team names even though names were configured in Settings > Team. The filter logic in `AtMentionDropdown` was correct, but `customNames` was always `{}`.

## Solution

Two bugs fixed:

1. **Client-side loading race:** Added `loading` prop to `AtMentionDropdown`. When team names are still fetching, the dropdown shows "Loading team..." instead of "No matches". Wired `loading` from `useTeamNames()` through `page.tsx`.

2. **Server-side routing gap:** `routeMessage` in `domain-router.ts` never received custom names. Added optional `customNames` parameter and fetched them in `agent-runner.ts` using the service client with explicit `user_id` filter (service client bypasses RLS).

## Key Insight

Supabase RLS policies that filter rows (e.g., `auth.uid() = user_id`) return zero rows on auth failure rather than an error. The API route returns `{ names: {} }` — indistinguishable from "no custom names configured." When building features that depend on RLS-protected data, always surface loading and error states to prevent silent degradation.

## Session Errors

1. **setup-ralph-loop.sh not found** — The one-shot skill referenced `./plugins/soleur/skills/one-shot/scripts/setup-ralph-loop.sh` which does not exist. Recovery: Continued pipeline without it. **Prevention:** Fix the script path in the one-shot skill or create the script.

2. **Dev server crash during QA** — Doppler dev config missing `SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_URL`, causing `service.ts` to throw on import. Recovery: Skipped browser QA, relied on unit test coverage. **Prevention:** QA skill already handles this gracefully; the Doppler dev config needs the Supabase vars added.

## Tags

category: ui-bugs
module: chat/at-mention-dropdown, server/domain-router, server/agent-runner
