# Learning: trace a reported symptom to its ACTUAL code path before trusting the plan's hypothesis

**Date:** 2026-06-01
**Branch:** feat-one-shot-member-view-404-and-kb-empty
**Issue context:** post-invite member-view 404 + empty Knowledge Base (#4543 follow-up; predecessor invite-accept fix merged 2026-06-01)
**Category:** bug-fixes

## Problem

After accepting a workspace invite, a member saw two symptoms: (1) a 404 "This page could not be found" on the post-accept landing, and (2) an empty "No Project Connected" Knowledge Base for a workspace whose repo was visibly connected.

The deepened plan correctly traced **symptom 2** (KB empty) to the un-cut-over read path (kb/tree/content/search read the caller's own `users` row → a member's empty solo row → 404 → `NoProjectState`). But for **symptom 1** (the 404) the plan offered two hypotheses — (a) bare `/dashboard/chat` 404, (b) solo-scoped landing — and its reconciliation table asserted the post-accept redirect "lands the member on `/dashboard`, NOT a 404 route." It instructed: "Phase 0 MUST reproduce with Playwright to pin (a) vs (b). Do not guess."

## Solution

Instead of Playwright (which needed a live member session that was impractical to synthesize), I traced the **actual** redirect chain in code:

- `invite/[token]/invite-actions.tsx:108` — after a successful accept, `router.push("/dashboard/settings/team")` (NOT `/dashboard` as the plan assumed).
- `dashboard/settings/team/page.tsx:23-30` — calls `notFound()` (renders the 404) when `resolveTeamMembershipPageData` returns `!ok`.
- `team-membership-resolver.ts:86-87` — returns `{ ok: false, reason: "no-org" }` when `resolveCurrentOrganizationId` is null.
- `accept-invite/route.ts` — **never set the member's active workspace/org**, so post-accept their `current_organization_id` was still null/solo → team page 404s. (Matches the screenshots: the "Owner / 1 member" solo workspace was active, not the invited one.)

The real root cause was a **third** mechanism the plan's (a)/(b) hypotheses missed. Fix: call the membership-checked `set_current_workspace_id` RPC in the accept route (lands the member in the shared workspace, sets both claims). The `chat/page.tsx` redirect stub still shipped (hypothesis (a) is also real — the *pending* `NoApiKeyBanner` CTA links to bare `/dashboard/chat`), but it was not Jean's actual 404.

## Key Insight

**A plan's hypothesis about a symptom's mechanism is a starting point, not the work-list. When a bug report names a symptom (a 404, an empty state), trace the ACTUAL code path that produces it — the redirect target, the exact `notFound()`/`throw` condition, the query that returns empty — before writing the fix.** Code-tracing is a valid (often superior) substitute for the plan's prescribed live repro when the repro needs hard-to-synthesize state. Here the plan's reconciliation table contained a factually wrong assumption ("redirect lands on /dashboard") that a 4-file trace (`invite-actions` → `settings/team/page` → `team-membership-resolver` → `accept-invite/route`) falsified in minutes. Anchoring on the plan's two hypotheses would have produced a `chat/page.tsx` stub that left the real 404 in place.

Corollary: **the plan's file classification can be wrong too.** The plan listed `kb/file/[...path]` as one of "four KB read routes" to sweep, but it is **write-only** (PATCH/DELETE) — there is no GET. Reading the route confirmed the member VIEW bug lives only in tree/content/search; the file/upload/share/sync paths are credential-bound writes, correctly deferred (#4755).

## Prevention

- When implementing a symptom-named bug whose plan hypothesizes the mechanism, open the actual producer of the symptom (grep for the literal `notFound()` / `404` / empty-state component) and walk the redirect/call chain to the determining condition BEFORE coding. Confirm or falsify each plan hypothesis against code.
- Verify the plan's route/file classifications by reading the route's exported HTTP methods (a "read route" with no GET is a write route).

## Session Errors

1. **CWD drift across Bash calls.** A `cd <worktree-root>` inside an AC2-grep/semgrep/anti-slop command changed the persistent shell CWD, so a later `./node_modules/.bin/vitest` returned `EXIT=127` and `grep` failed with `No such file or directory`. — Recovery: re-prefixed commands with `cd <abs>/apps/web-platform &&`. — Prevention: always chain `cd <abs-path> && <cmd>` in worktree pipelines (already covered by `knowledge-base/project/learnings/bug-fixes/2026-04-19-admin-ip-drift-misdiagnosed-as-fail2ban.md` + work-skill "chain cd && cmd" guidance; already-enforced, no new rule).
2. **Planning subagent: Task tool unavailable** (forwarded from session-state.md). — Recovery: deepen-plan ran its research/review gates inline. — Prevention: none needed; graceful degradation, not a defect.

## Tags
category: bug-fixes
module: web-platform / workspace-invitations / kb-routes
related: [[2026-04-19-admin-ip-drift-misdiagnosed-as-fail2ban]]
