---
title: A new authz gate that reads a DB row silently depends on that row's universal existence — the backfill is a hard, ordered prerequisite
date: 2026-06-17
category: best-practices
tags: [authorization, migration, backfill, rls, deploy-ordering, deep-link, workspace, adr-044]
modules: [apps/web-platform/app/api/repo, apps/web-platform/supabase/migrations, apps/web-platform/server]
related_prs: [5435]
related_issues: [5437]
related_adrs: [ADR-044]
---

# Learning: an authz gate reading a DB row depends on that row's universal existence (backfill = ordered prerequisite); and a deep link to a non-member resource dead-ends

## Problem

ADR-044 PR-1 added an owner-gate to `/api/repo/setup` + `/api/repo/disconnect`:

```ts
const ownerRes = await supabase.rpc("is_workspace_owner", {
  p_workspace_id: user.id, p_user_id: user.id,
});
if (ownerRes.data !== true) return 403;
```

The plan called this "a no-op for solo users **by construction**" — a solo user is
always the owner of `workspace_id=user.id`. But `is_workspace_owner` (mig 098) returns
TRUE **only if a `workspace_members` row with `role='owner'` exists**. A read-only count
at `/work` time found **18,287 of 62,746 dev users (vs 0 of 15 prd)** lacked that
owner-membership canary. For every one of them the gate would return `data=false` →
**403 on connecting/disconnecting their OWN repo**. "No-op by construction" was actually
"no-op only once the canary is universal" — a *data* precondition, not a structural one.

Two compounding traps:
1. The plan expected the backfill count to be "~0 or a tiny trigger-failure residue."
   The real dev number was 18k (synthetic seed accounts). **Plan-quoted counts are
   preconditions to verify, not facts** — re-run the count at `/work` time.
2. A separate Phase-3 surface offered a "switch to your team workspace" **deep link
   carrying the discarded `resetFromClaim` team id, via `set_current_workspace_id`**.
   But a `resetFromClaim` user is *by definition* a non-member of that team (the resolver
   only sets `resetFromClaim` on a clean non-member probe), and `set_current_workspace_id`
   is membership-checked — so the deep link is a **guaranteed dead-end** (the RPC rejects).

## Solution

1. **Ship the backfill as a documented HARD PREREQUISITE, and rely on deploy ordering.**
   mig 109 backfills the owner-membership canary (mirrors the `handle_new_user` trigger).
   The release pipeline runs `run-migrations.sh` **before** code cutover, so the canary is
   universal by the time the gate code is live. The migration header states the dependency
   explicitly so a future reader doesn't decouple them. Verified the backfill in a
   **rolled-back dev transaction** (`BEGIN; <body>; <count>; <re-run>; ROLLBACK`) — 18,287→0,
   re-run inserts nothing (idempotent) — proving correctness with zero `_schema_migrations`
   drift, leaving the real apply to the pipeline.
2. **The deep link opens the general switcher, not a direct membership-checked switch.**
   The frame still carries `switchToWorkspaceId` (satisfies the "carry the target id" AC and
   is multi-team-safe), but the client action navigates to `/dashboard` (the switcher lists
   only *joinable* workspaces) rather than calling `set_current_workspace_id(targetTeamId)`.
   This diverges from the plan's literal "via RPC" wording — correctly, because the literal
   reading produces a dead-end.

## Key Insight

**When a PR adds an authz/feature gate that reads a per-subject DB row (`is_*_owner`,
`is_*_member`, a flag row, an entitlement row), the gate silently depends on that row
existing for EVERY subject. Before shipping the gate, run the read-only count of subjects
missing the row across every environment the gate runs in (`SELECT count(*) ... LEFT JOIN
... WHERE <row> IS NULL`). If non-zero, a backfill is a HARD, ORDER-DEPENDENT prerequisite —
the data must land before the code, and the dependency must be stated where a future reader
can't decouple it. "No-op by construction" claims that rest on a DB row are "no-op by data"
— verify the data.**

Corollary: **a deep link / CTA pointing at a resource the user provably cannot access
(a non-member team, a revoked grant, a deleted row) is a dead-end. Trace the access check
the target action runs; if the user fails it by construction, route to a chooser that lists
only reachable targets, not a direct deep link.** The spec's literal "link via <RPC>"
wording is intent, not authority — when the RPC's own gate rejects the user, follow the
intent (let them switch) without the dead-end (don't pre-bind the unreachable id).

## Session Errors

- **AGENTS.md always-loaded budget overflow (28 B over 23,000).** A plan-phase commit added
  a rule index line (+64 B) to `AGENTS.md`; main was already at 99.8%. `test-all.sh`'s
  `lint-agents-rule-budget` caught it. **Recovery:** trimmed the redundant header spec-path
  (rule-neutral, recovered budget to 22,991). **Prevention:** already covered by
  `2026-05-20-rebase-before-applying-agents-md-plan-edits` — a plan that adds an AGENTS.md
  rule should check `B_ALWAYS` headroom at plan time and rebase before the rule lands.
- **Plan-quoted backfill count stale (expected ~0, dev had 18,287).** **Recovery:** re-ran the
  count via the Doppler `DATABASE_URL_POOLER` at `/work` time (prd=0). **Prevention:** the
  existing "plan-quoted numbers are preconditions to verify" rule — applied here to a row count.
- **Owner-gate hidden DB-row dependency** (the main learning above). **Prevention:** count
  subjects-missing-the-row before shipping any row-reading authz gate.
- **Plan's literal switcher-via-RPC wording produced a dead-end** (the corollary above).
  **Prevention:** trace the target action's own access check before emitting a deep link.
- **Bash-tool CWD reset across calls (one-off recurrence).** Greps failed against
  worktree-relative paths after CWD reset to repo root. **Recovery:** full paths / `cd` in the
  same call. **Prevention:** already documented; chain `cd <abs> && <cmd>` in one Bash call.
- **gdpr-gate diagnostic SQL `created_at` ambiguous in a JOIN** (one-off, throwaway query). No
  prevention needed.
