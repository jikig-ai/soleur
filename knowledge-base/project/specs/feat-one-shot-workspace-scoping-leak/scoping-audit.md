# Workspace-scoping audit — knowledge-drift leak + feature sweep

**Date:** 2026-06-02 · **Branch:** feat-one-shot-workspace-scoping-leak
**Trigger:** owner of two workspaces saw a knowledge-drift notification belonging to one
workspace ("Soleur") on the other ("Chatte").

## Root cause (corrected vs. plan, validated by code-trace + read-only prod probe)

The plan's Decision D2/D3 assumed the KB-drift walker scans a **per-workspace** KB at
`<WORKSPACES_ROOT>/<workspace_id>/knowledge-base` and that a scanned `workspace_id` should be
threaded into the card. **This is false.** `scripts/kb-drift-walker.sh:27-28` +
`.github/workflows/kb-drift-walker.yml` show the walker is a nightly GitHub Actions cron that
checks out **Soleur's own dev repo** and scans `$REPO_ROOT/knowledge-base` + `AGENTS.*.md` +
learnings — **one global company KB**. There is no per-workspace scan and no `workspace_id` to
thread. (The plan-author conflated the KB-drift walker with the unrelated
`resolveActiveWorkspaceKbRoot` per-user-workspace-KB subsystem.)

**Read-only prod probe** (`ifsccnjhymdmidffkzhl`, `DATABASE_URL_POOLER`, SELECT-only):
- Founder owns TWO workspaces (both literally named "My Workspace"): `52af49c2…` (= founderId,
  **solo**) and `754ee124…` (second). "Soleur"/"Chatte" are the user's informal labels.
- All **4** kb-drift draft cards are pinned to the **solo** workspace (`52af49c2…`); previews
  describe Soleur's company-repo docs ("174 KB-drift findings — Broken link in knowledge-ba…").
  The solo-pin write is **correct** — the cards are about Soleur's company KB, owned by the
  operator. They leak onto the second workspace ONLY because the Today read was `user_id`-scoped
  with no `workspace_id` filter, and `messages` RLS (`is_workspace_member`) passes for an owner
  across ALL their workspaces.

**Conclusion:** the bug is **purely the read leak**. Plan Phase 2 (walker-threading +
`insertDraftCard` override) and Phase 3 (migration 093) rest on the false premise and were
**dropped** — the write is already correct; the 4 existing cards correctly belong to solo.

## Fixes applied

| # | Surface | Change |
|---|---------|--------|
| F1 | `app/api/dashboard/today/route.ts` | Scope the Today read to the active workspace: `.eq("workspace_id", resolveCurrentWorkspaceId(userId, supabase))`. The real + complete fix for the reported leak. RLS is defense-in-depth only. |
| F2 | `server/conversations-tools.ts` (conversation_list) | Add `.eq("workspace_id", activeWorkspaceId)` alongside the existing `repo_url` scope — closes the one residual cross-workspace mix (same repo connected to two of the owner's workspaces). |

## Audit dispositions (the "verify" answer)

### Knowledge-drift notification — **FIXED** (F1)
Read now scopes to the active workspace. Card shows on its owning (solo) workspace, absent on
the second. Write unchanged (solo-pin is correct for global company-KB drift).

### today/[id]/* mutation routes (AC3) — **safe with rationale** (no change)
All six (`send/edit/discard/cancel/cost/undo`) scope by `.eq("id", messageId).eq("user_id",
user.id)` (+ RLS, + `status=draft` on some). Id is an unguessable UUID; the card is the owner's
own row; both workspaces belong to the same human; a non-owner member can never load a
user-attributed card. After F1 a wrong-workspace card id is never surfaced to act on. Adding an
active-workspace guard would risk regressing legitimate cross-session undo/cost flows for zero
tenant-isolation gain.

### Conversations (AC4) — **already workspace-scoped; one edge hardened** (F2)
- Schema: `conversations.workspace_id` NOT NULL (mig 059); RLS `conversations_owner_or_shared`
  (own + workspace-shared); `visibility` default `'private'` (mig 075).
- List tool scoped by active-workspace `repo_url` (`getCurrentRepoUrl`, active-workspace-aware).
- Residual gap: two of the owner's workspaces connecting the SAME repo share `repo_url`, so the
  proxy alone could mix them → **hardened** with the explicit `workspace_id` filter (F2).
- archive/unarchive pin by unique conversation `id` → already precise, no change.
- Dashboard orphaned-count (`dashboard/page.tsx`): intentionally cross-workspace (fires only
  when the active workspace has no repo; it's a "reconnect a repo connected elsewhere" nudge over
  the user's own non-sensitive row count). Documented in-place; no change.

### Conversations rate limiting (AC5) — **keep per-user** (invariant comment added)
`sessionThrottle.isAllowed(userId)` (`ws-handler.ts`) + `user_concurrency_slots` (mig 029) are
per-user. MUST stay per-user: the cap is coupled to the per-user `plan_tier`/`concurrency_override`
model and the per-user Stripe subscription. Per-workspace keying would let one user multiply paid
capacity by creating workspaces. Per-workspace caps require a per-workspace billing model first
(deferred). Invariant comment added at the call site.

### Billing (AC5) — **correctly per-user** (rationale comments added)
Subscription is per-user by schema (one `stripe_customer_id` + `subscription_status` per `users`
row). The cancel-retention conversation count is intentionally per-user/cross-workspace — the
subscription covers all the user's workspaces, so the total reflects full investment under one
plan. `const workspaceId = user.id` (solo-pin for the delegation pane) is correct for per-user
billing. Per-workspace/org billing is a product/pricing decision (CPO), deferred.

## Intended behavior after the read fix (explicit tradeoff)

KB-drift cards describe **Soleur's global company-repo KB** and are attributed to the operator
founder's **solo/home workspace** (the walker has no per-workspace concept — confirmed). After
F1, these cards render **only when the operator's home (solo) workspace is active**, not on other
workspaces the operator owns. This is the **intended, user-requested** outcome ("should not show
up on Chatte Workspace"). The prod probe confirms the operator's `current_workspace_id` = solo, so
the cards correctly show on their primary workspace today.

Review note (user-impact-reviewer flagged this as a "false-negative on workspace switch"): the
concern presumes the plan's original Phase-2 premise (thread a per-workspace `workspace_id` from
the walker). That premise is false — the walker scans one global KB, so there is no per-workspace
attribution to thread, and the security/data-integrity/architecture reviewers independently
confirmed the read-only fix is **complete and correct**. Whether company-infra-drift cards should
ALSO surface in a non-solo/team workspace is a **product decision** (operator-global notifications),
not a regression this PR introduces — and the opposite of what the user asked for here. Not filed
as a tracking issue (speculative, net-negative per the cost-of-filing gate); recorded here so the
behavior is documented rather than silent.

## Deferred (product decisions, not bugs)
- **Per-workspace / per-org billing** — a subscription model change, needs CPO input. Only file a
  tracking issue if it is on `knowledge-base/product/roadmap.md` (not implemented here).
- **Per-workspace rate-limit caps** — coupled to the above; do not implement without it.
