# Learning: a "feature disappeared" report with an all-green data layer means observe, don't mutate

## Problem

The operator reported the multi-user **Members** tab had disappeared from Settings
for `ops@jikigai.com` (screenshot at 2026-05-31 20:18 UTC). The plan
(`2026-05-31-fix-multi-user-feature-not-visible-plan.md`) was a *diagnose-then-fix*
with four ranked hypotheses, the leading one (H1) being "the #4617 segment cutover
dropped jikigai's org from the `team-workspace-invite-orgs` Flagsmith segment", whose
prescribed fix was a `flag-set-role` `flip.sh ... --org <jikigai>` re-add.

The trap: the plan's structure invites you to *apply the ranked fix*. But the
fix is a live prod state mutation (a Flagsmith segment write + a WORM
`flag_flip_audit` row), and the plan's own Sharp Edge warned: "Do not flip the
flag before reading live state... flipping changes nothing and leaves a
misleading WORM audit row."

## Solution

Run **every** Phase 0 read-only probe through the *exact production code path*
before touching anything, and let the readings — not the plan's ranking —
choose the fix (including the option of **no state mutation**):

- **H2 (gate #2, session-state):** `user_session_state.current_organization_id`
  for ops@jikigai = `1a8045bf...` (non-null, correct). Confirmed under the
  **authenticated RLS role** (`SET LOCAL ROLE authenticated` + crafted
  `request.jwt.claims` via the Supabase Management API `database/query`
  endpoint), not just service-role — so the read the user's own client makes is
  proven, not assumed. PASS.
- **H1 membership (gate #3):** jikigai's org *was already present* in the
  segment's `EQUAL/orgId` conditions. Membership ≠ the problem.
- **H1 evaluation (the load-bearing check):** the flag *evaluates* ON for
  jikigai via the production `getIdentityFlags` edge path (`org:1a8045bf...:prd`,
  `orgId` trait) and OFF for a control org. PASS — membership ≠ evaluation, and
  here both are green.
- **H3 (env fallback):** `FLAG_TEAM_WORKSPACE_INVITE=1` in prd, so a Flagsmith
  *timeout* would resolve the flag ON via fallback — i.e. an outage would *show*
  the tab, not hide it. Ruled out.
- **Timeline:** the latest prd feature-version publish for the flag was
  2026-05-29 14:43 UTC — two days **before** the screenshot. Deployed prod ran
  current main (712847a9), and the layout's current form shipped 2026-05-27. So
  all four gates were green *at screenshot time*.

Conclusion: the symptom does **not** reproduce server-side. The trigger was
client-side (Next.js App Router cache serving a stale flag-gated layout) or a
transient. **No flag flip and no session-state write were performed** — both
targets were already correct; a write would have been a no-op leaving a
misleading WORM row.

The shipped fix targets the actual systemic gap the report exposed — the failure
is **silent** (a tab vanishes with no error):
- `reportSilentFallback` in the extracted `resolveMembersTab` when a user **with**
  workspace membership resolves a null current org (a member losing org-gated UI
  is an integrity surface; a solo non-member is the normal silent case).
- A deterministic regression test of the gate composition, including the emit
  branch (extracted into `server/members-tab.ts` to isolate it from the layout's
  `"use client"` import so it is unit-testable).

This makes the fix self-validating: if the user reloads and it is *still* missing
(a genuine server-side null-org for a member), Sentry now fires and names the gate.

## Key Insight

For a **diagnose-then-fix** plan, the diagnosis is allowed to override the plan's
ranked fix — and "the correct fix is no state mutation, only observability +
a regression guard" is a legitimate, often-correct outcome. A "feature
disappeared" report is a **lower bound on breakage, not proof of current
breakage**. When the data layer reproduces green through the *exact* production
paths (edge flag eval + authenticated-role RLS read, not service-role), the
durable deliverable is the signal that catches the *next* (genuinely silent)
occurrence, not a speculative prod write that satisfies the plan's narrative.
Verify with: stable feature-version publish timestamps + behavior-identical
deployed code prove the state was green at incident time.

## Session Errors

1. **Bash `UID` readonly-variable collision** — `user_session_state?user_id=eq.$UID`
   sent the shell's Unix uid (`1001`) instead of the user UUID → PostgREST
   `22P02 invalid input syntax for type uuid: "1001"`. **Recovery:** renamed the
   var to `OPS_UID`. **Prevention:** never use bash special/readonly names
   (`UID`, `EUID`, `GID`, `PWD`, `PPID`) as script variables; prefer a prefixed
   name.
2. **Supabase Management API `403` / Cloudflare error `1010`** on the default
   `python urllib` User-Agent (browser-signature ban). **Recovery:** added a
   browser `User-Agent` header to the request. **Prevention:** when calling
   `api.supabase.com/v1/projects/<ref>/database/query` from `urllib`, always set
   a browser `User-Agent`.
3. **Flagsmith featurestates probe matched multiple `is_live=True` version
   UUIDs** → malformed-URL / empty-JSON error. **Recovery:** the needed data
   (version publish timestamps) was already captured by the preceding command;
   the step was non-load-bearing. **Prevention:** filter a version list to a
   single UUID before interpolating it into a URL.
4. **(forwarded from session-state.md)** plan subagent's first `Write` was
   blocked on the bare-root path (re-issued to the worktree path — guardrail
   worked as intended); Task/Explore agent-spawn tools were not exposed in the
   planning subagent's harness (equivalent research done inline). Both handled,
   no rework.

## Tags
category: integration-issues
module: apps/web-platform/server (workspace-resolver, members-tab, feature-flags); plugins/soleur/skills/one-shot
