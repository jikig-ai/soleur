---
name: feat-adr-044-workspace-connection
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-06-16-adr-044-workspace-owned-connection-brainstorm.md
branch: feat-adr-044-workspace-connection
pr: 5435
---

# Feature: Finish ADR-044 — Workspace-Owned Connection & Always-Enforce-Workspace

## Problem Statement

Invited members of a team workspace cannot dispatch any Concierge work. The `soleur:go`
Step 0.0 readiness gate reports "workspace isn't ready — reconnect your repository," but
reconnecting can't fix it and members don't own the connection. Root cause: two resolver
paths diverge inside one `Promise.all` (`cc-dispatcher.ts:1533-1556`). The agent CWD/clone
path resolves through `resolveActiveWorkspaceIdWithMembership` (which rewrites a
non-member/error claim to `userId`), while repo + install resolve via
`resolveCurrentWorkspaceId` directly (always the active workspace). On any membership
miss/error the clone lands in the solo `/workspaces/<userId>` dir (no `.git`) while repo +
install resolve the shared workspace. The failure is zero-Sentry and invisible. Owners are
unaffected; only invited members strand.

## Goals

- Unify resolution so repo, install, and agent CWD/clone path all key on ONE
  membership-verified active-workspace id.
- Replace the silent fail-closed-to-solo branch with explicit, role-correct not-ready states.
- Make the next stranded member visible via Sentry.
- Establish the **always-enforce-workspace** invariant: every user has a guaranteed personal
  workspace (1-member) owning connection/billing/integrations, so solo→team is "add a member."
- Finish dropping legacy `users.repo_url` / `users.workspace_path` / `users.github_installation_id`
  after a prod soak + drift gate.

## Non-Goals

- Workspace-keyed / seat-based **billing** — stays user-keyed; dedicated follow-up issue
  (revenue-risk-gated, role-gated visibility, CLO consent). The solo subscriber pays for their
  personal workspace, which already satisfies frictionless solo→team.
- Flagsmith role/flag targeting relocation — follow-up; only the trait-visibility implication.
- Re-keying already-migrated concerns (BYOK delegations #4767, `scope_grants` mig 059,
  `workspace_members.role`).

## Functional Requirements

### FR1: Unified active-workspace resolution (PR-1)

A single membership-verified resolution computed once in `cc-dispatcher.ts` before the
`Promise.all`, threaded into `fetchUserWorkspacePath`, `resolveInstallationId`,
`getCurrentRepoUrl`, `getCurrentRepoStatus` via their existing `workspaceId?` overrides.
Repo, install, and CWD/clone path always agree on the same workspace.

### FR2: Explicit, role-branched not-ready state (PR-1)

Dispatch resolution returns `{ok:false, reason: unbound|not-member|db-error}` instead of
silently dispatching to solo. Owners see an actionable "reconnect" message; members see
"you're in your personal workspace instead of <Team>; switch workspaces" with a
workspace-switcher deep link and NO reconnect CTA. Copy + wireframes:
`knowledge-base/product/design/workspace-connection/member-owner-repo-states.pen`.

### FR3: Owner-gated repo card + routes (PR-1)

`ProjectSetupCard` gates connect/disconnect/reconnect behind `isOwner`; members see read-only
"Connected: <repo>, managed by <owner>." The `repo/disconnect` and `repo/setup` routes add an
owner/admin membership-role check (today they authorize by `auth.getUser()` only).

### FR4: Divergence observability (PR-1)

A deduped `repo_resolver_divergence` Sentry breadcrumb fires on the member-divergence branch,
keyed on hashed user id + both resolved workspace ids. Not fired on normal `cloning`.

### FR5: Personal-workspace guarantee (PR-1 / its own migration)

Provision a personal workspace + `workspace_members` row at signup; backfill existing users
missing one (verify coverage vs migration 080's `w.id=u.id` solo rows). Make
personal-workspace membership a hard invariant; the resolver trusts it and reserves
`{ok:false}` for genuine db-error.

### FR6: Connect-time write relocation + legacy column drop (PR-2, soak-gated)

Relocate `repo/setup`, `repo/create`, `detect-installation`, and `cron-workspace-sync-health.ts`
writes to `workspaces.*`; reconcile the co-membered backfill gap from migration 080's audit
NOTICE; run the ADR-044 drift gate (`COUNT(*)=0` on `repo_url` AND `github_installation_id`);
then drop the three legacy `users.*` columns with a `.down.sql`.

### FR7: Architecture Decision record + C4 (plan deliverable, per plan Phase 2.10)

Amend ADR-044 to record the always-enforce-workspace decision (every user owns a guaranteed
1-member personal workspace; connection/billing/integrations key on workspace; the `userId`
solo sentinel is retired) — authored with the always-workspace target state and a
`status: adopting` note since it fully holds only after the follow-ups. Update the C4 view(s)
so the repo-connection edge moves from User to Workspace. C4 edits route through
`/soleur:architecture` (Concierge-only, `c4-edit` flag, per commit `3c8849655`). This is an
in-scope deliverable of this feature, NOT a deferred issue.

## Technical Requirements

### TR1: Cross-tenant containment invariant

The unified resolver's only non-error return is a membership-verified id OR the user's own
personal workspace. NEVER a claim id that failed/skipped the probe; NEVER an unscoped
membership scan (`MIN(created_at)`/first-membership — the #4767 bug class). Test: a probe
db-error returns `{ok:false}`, not the claim id.

### TR2: Cold-dispatch self-heal ordering

`ensureWorkspaceDirExists` + `ensureWorkspaceRepoCloned` run against the unified id BEFORE the
readiness gate (`evaluateRepoReadiness`) and the in-agent Step 0.0 gate fire — gate-after-recovery
(#5240). Once unified, the clone target and the gate's CWD are the same dir.

### TR3: Migration safety (PR-2)

Reads-first-then-drop (expand/contract). Gating conditions before drop: zero live readers of the
three columns (full grep across apps + Inngest + scripts, not just `server/`); backfill
reconciliation proven (no `users.repo_url IS NOT NULL AND workspaces.repo_url IS NULL` for the
active workspace); prod soak elapsed; `account-delete.ts` + `dsar-export.ts` updated for the new
location (avoid mig-064 23514 saga-abort; avoid silent DSAR export regression); `.down.sql`
provided; `/soleur:gdpr-gate` run on the decommission diff. Route through `data-migration-expert`
+ `data-integrity-guardian`.

### TR4: Route the PR-2 migration through the never-downgrade review set

`data-migration-expert`, `data-integrity-guardian`, `gdpr-gate` (per ADR-053 exemption list).
