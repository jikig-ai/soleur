---
date: 2026-06-02
category: bug-fixes
module: apps/web-platform (workspace scoping / messages / conversations)
tags: [tenant-isolation, workspace-scoping, plan-premise, prod-probe, kb-drift, rls]
branch: feat-one-shot-workspace-scoping-leak
---

# Learning: A deepened plan's central premise can be false — trace the actual producer + prod-probe before coding

## Problem

Reported bug: an owner of two workspaces saw a knowledge-drift notification "belonging to
Soleur Workspace" appear on "Chatte Workspace". The deepened plan (plan + deepen-plan, CPO
framing) diagnosed this as a **coupled write+read** defect and prescribed:
- Phase 2: thread the scanned `workspace_id` from the KB-drift **walker** through the
  HMAC-signed ingest payload into an `insertDraftCard` override.
- Phase 3: an optional migration 093 to re-attribute existing solo-pinned cards.

## Root cause of the *plan's* error

The plan asserted (even after deepening) that the KB-drift walker scans a **per-workspace** KB
at `<WORKSPACES_ROOT>/<workspace_id>/knowledge-base`. It does **not**. `scripts/kb-drift-walker.sh:27-28`
scans `$REPO_ROOT/knowledge-base` of the **checked-out Soleur repo** — one global company KB
(the nightly GitHub Actions cron `kb-drift-walker.yml` checks out Soleur's own repo). The
plan-author conflated two unrelated subsystems that both say "knowledge-base":
1. the **KB-drift walker** (CI cron over Soleur's company docs), and
2. `resolveActiveWorkspaceKbRoot` (per-user workspace KB on the app server disk).

Because the walker has no per-workspace concept, there is **no `workspace_id` to thread** — the
card correctly belongs to the operator-founder's solo workspace. The leak was **purely the read**:
`app/api/dashboard/today/route.ts` filtered by `user_id` only, and `messages` RLS
(`is_workspace_member(workspace_id, auth.uid())`, mig 059) passes for an OWNER across **all**
their owned workspaces — so RLS was never the cross-workspace guard.

## Solution

1. **Read scoping (the real, complete fix):** add `.eq("workspace_id", resolveCurrentWorkspaceId(userId, supabase))`
   to the Today read (claim → solo fallback, never a sibling; RLS is defense-in-depth only).
2. **Dropped Phase 2 + Phase 3** as false-premise work (the write was already correct; a
   read-only prod probe showed all 4 existing `kb-drift` cards correctly solo-pinned).
3. Audit the named features: conversations (already workspace-keyed; hardened the list tool with
   an explicit `workspace_id` filter to separate two workspaces sharing one repo), rate-limit
   (keep per-user — coupled to per-user plan_tier), billing (correctly per-user by schema).

## Key Insight

A plan that has been through `deepen-plan` and a domain-leader framing is **still a hypothesis**,
not ground truth — its *mechanism* claims (which producer writes the row, which KB gets scanned)
are exactly the part most likely to be wrong, because deepening re-states the author's mental
model rather than re-deriving it from code. The `/work` skill already says "trace the ACTUAL
producer before coding." Here that meant reading the walker script + the cron YAML (5 minutes),
which falsified the entire write-side half of the plan and a migration. A **read-only prod probe**
(via Doppler `DATABASE_URL_POOLER` + `pg`, SELECT-only) then *confirmed* the corrected model
empirically (all cards solo-pinned; operator's `current_workspace_id` = solo) before any code
changed — turning a risky write-path + migration change into a safe read-only scoping change.

When a plan's premise and the code disagree, the code wins — and a prod probe settles "what is
the data actually doing" cheaper than implementing the plan's guess.

## Session Errors

1. **Prod probe queried wrong enum value** (`source='kb_drift'` vs the real `'kb-drift'`) → 0 rows,
   briefly suggesting "no cards exist". Recovery: read `lib/messages/tiers.ts` constant, re-probed.
   **Prevention:** read the literal constant value before composing SQL against an enum column —
   `_`/`-` drift between TS identifier and DB value is silent.
2. **Prod probe queried non-existent column** (`workspaces.owner_user_id`). Ownership is via
   `organizations.owner_user_id` (mig 053; `workspaces` has only `organization_id`). Recovery:
   read the CREATE TABLE migration, joined through `organizations`. **Prevention:** read the
   table's CREATE migration before assuming column names.
3. **Review-agent inline edit introduced a TS2556** (security-sentinel changed a `vi.fn()` mock to
   forward `...args: unknown[]` into a no-arg factory). Recovery: typed the rest arg
   `(..._args: unknown[])`. **Prevention:** already covered — run `tsc --noEmit` after any agent
   inline edit to test mocks; the post-review tsc gate caught it before ship.

## Tags
category: bug-fixes
module: apps/web-platform
