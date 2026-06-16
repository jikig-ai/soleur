---
date: 2026-06-16
topic: Finish ADR-044 — workspace-owned connection & always-enforce-workspace
status: complete
lane: cross-domain
brand_survival_threshold: single-user incident
branch: feat-adr-044-workspace-connection
pr: 5435
---

# Finish the ADR-044 Migration — Workspace-Owned Connection (and Always-Enforce-Workspace)

## What We're Building

Finish the ADR-044 users→workspaces migration so the Concierge **always** operates from
the active workspace, never a per-user/solo sentinel. Two shipped slices plus a north-star
principle:

- **PR-1 (incident-stopping, non-destructive):** unify the resolver so repo, install, and
  agent CWD/clone path all key on ONE membership-verified active-workspace id; role-branch
  the not-ready copy (members get a workspace-switcher deep link, not a useless "reconnect");
  owner-gate the repo card + disconnect/setup routes; add a `repo_resolver_divergence`
  Sentry hook so the next stranded member is visible.
- **PR-2 (soak-gated, destructive):** relocate connect-time writers to `workspaces.*`,
  reconcile the co-membered backfill gap, run the ADR-044 drift gate (`COUNT(*)=0`), then
  drop legacy `users.repo_url` / `users.workspace_path` / `users.github_installation_id`.
- **North star (codified, sequenced as follow-ups):** *every user always operates inside a
  real workspace.* A solo user is the owner of a 1-member "personal" workspace that owns the
  connection, billing, and integrations. Solo→team upgrade becomes "add a `workspace_members`
  row" — zero data relocation.

## Why This Approach

The production incident: invited members of a team workspace can't dispatch **any** Concierge
work. The `soleur:go` Step 0.0 gate says "workspace isn't ready — reconnect your repository,"
but reconnecting can't fix it and members don't own the connection. Root cause (diagnosed,
not re-derived): two resolver paths diverge inside one `Promise.all`.

- **Confirmed divergence** (`cc-dispatcher.ts:1533-1556`): `fetchUserWorkspacePath` resolves the
  CWD/clone path through the membership self-heal (`workspace-resolver.ts:344` →
  `resolveActiveWorkspaceIdWithMembership`, which rewrites a non-member/error claim to `userId`
  at lines 380-382), while `resolveInstallationId` / `getCurrentRepoUrl` / `getCurrentRepoStatus`
  call `resolveCurrentWorkspaceId` (`workspace-resolver.ts:198`) **directly** with no membership
  probe. On any membership miss/error the clone lands in the solo `/workspaces/<userId>` dir
  (no `.git`) while repo+install still resolve the shared workspace. Zero Sentry on the clean
  miss branch → invisible.

The "always enforce a workspace" reframing (operator decision, 2026-06-16) is the *clean* fix
rather than a patch: it dissolves the `userId`-as-solo-sentinel duality. Migration 080 already
keys solo workspaces `id = userId`, so the data layer is half-there; the gap is that the resolver
doesn't *guarantee* the personal-workspace row + membership exist. Guarantee them
(provision-at-signup + backfill), and the resolver can trust the invariant — `{ok:false}`
collapses to genuine db-error only, and **owners never strand** because their personal workspace
always exists.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Split into PR-1 (resolver+UX+authz+Sentry) and PR-2 (soak-gated drop) | Drop is irreversible-by-revert; a stranded member stays one revert away from recovery (CPO+CTO+CLO unanimous) |
| 2 | Unified resolver: resolve membership-verified active id ONCE before the `Promise.all`; thread into all 4 consumers via existing `workspaceId?` override params | Single id → path, repo, install key identically; smallest safe shape (CTO) |
| 3 | Fail-closed returns explicit `{ok:false, reason: unbound\|not-member\|db-error}` on the dispatch path; still returns the user's personal workspace for genuine solo | Cross-tenant invariant preserved by construction — only non-error return is membership-verified; owners (who rely on the personal workspace) never strand |
| 4 | **Always-enforce-workspace** is the north star: every user has a guaranteed personal workspace owning connection/billing/integrations | Frictionless solo→team upgrade; eliminates the userId sentinel branch entirely |
| 5 | Provision personal workspace at signup + backfill existing users; make personal-workspace membership a hard invariant | Resolver trusts the invariant; backfill must be proven complete before the resolver stops any fallback. Verify coverage against 080's `w.id=u.id` solo rows |
| 6 | Connect-time write relocation deferred to PR-2 (read-path already on `workspaces.*`) | Keeps the incident-stopping PR-1 small and non-destructive |
| 7 | Owner-gate the repo card + disconnect/setup routes; members see read-only "Connected: <repo>, managed by <owner>" | Today `ProjectSetupCard` has no `isOwner` prop and `disconnect/route.ts` has no role check — any authenticated user can disconnect |
| 8 | Member not-ready recovery = prompt + workspace-switcher deep link (no auto-switch, no "reconnect" CTA) | Member CAN switch; never silently changes active context; names the team + flags the owner |
| 9 | Billing stays user-keyed short-term; workspace-keyed/seat billing is a dedicated revenue-risk-gated follow-up | Solo subscriber pays for their personal workspace — frictionless path needs no relocation (CFO) |
| 10 | Add `repo_resolver_divergence` Sentry breadcrumb on the member-divergence branch (hashed user id + both workspace ids) | Today zero-Sentry/invisible; `cq-silent-fallback-must-mirror-to-sentry` + `hr-observability-as-plan-quality-gate` |
| 11 | Visual design: member/owner repo states wireframed | `knowledge-base/product/design/workspace-connection/member-owner-repo-states.pen` |
| 12 | Codify always-workspace as an ADR-044 amendment + C4 connection-owner edge — **a plan deliverable, NOT a deferred issue** (per new plan Phase 2.10 gate). C4 edits route through `/soleur:architecture` (c4-edit-flag gated, Concierge-only) | Operator correction 2026-06-16: ADR/C4 always ships with the architectural change it documents. Drove the `wg-architecture-decision-is-a-plan-deliverable` workflow fix |

## User → Workspace Relocation Matrix

| Concern | Keyed today | Should move? | Status / sequencing |
|---------|-------------|--------------|---------------------|
| Repo connection (`repo_url`, `repo_status`) | Read-path already `workspaces.*`; legacy `users.repo_url` retained | **Yes — finish** | PR-1 read unify · PR-2 write relocate + drop |
| Workspace path (CWD/clone) | `users.workspace_path` + `resolveActiveWorkspacePath` | **Yes** | PR-1 unify resolver · PR-2 drop column |
| GitHub App install | `users.github_installation_id` (read cut over; connect-time writers still write `users.*`) | **Yes** | PR-1 read unify · PR-2 relocate writers (`repo/setup`, `repo/create`, `detect-installation`) + drop |
| BYOK delegations | Already workspace-keyed (#4767 / `resolveCurrentWorkspaceId`, mig 064) | Done | No action; mirror this pattern |
| `scope_grants` (action tiers) | Workspace-keyed (mig 059) with WORM + paired-NULL CHECK | Done | Preserve Class-H anonymise contract on any re-key |
| Role grants (`workspace_members.role`) | Workspace-keyed | Done | Owner-transfer-on-erasure (mig 081) preserved |
| Billing / subscription (`stripe_customer_id`, `subscription_status`, `stripe_subscription_id`, `plan_tier`) | **100% user-keyed** (`users.*`, migs 002/020/021/029) | Future (north star) | **Follow-up issue** — revenue-risk-gated, role-gated visibility, CLO consent before exposing solo subscriber history to co-members |
| Flagsmith role/flag targeting | User identity traits | Maybe | **Follow-up** — only the trait-visibility implication if moved to workspace identity |
| Personal-workspace guarantee | Implicit (`w.id=u.id` solo rows from mig 080) | **Make explicit** | Provision-at-signup + backfill + hard invariant (Decision 5) |

## Open Questions

1. **Incident user diagnostic** (pull directly, don't eyeball per `hr-no-dashboard-eyeball`):
   does `user_session_state.current_workspace_id` for `52af49c2` point at team `754ee124`, and is
   there a `workspace_members` row for them on it? Confirms error-branch vs missing-row.
2. **Backfill coverage:** how many existing users lack a personal-workspace row / membership? The
   resolver can't drop its fallback until this is provably zero. 080 covered solo `w.id=u.id` only;
   co-membered SKIPs from 080's audit NOTICE must be drained — where is that tracked?
3. **DSAR export:** the three dropped columns currently appear in the subject export
   (`dsar-export.ts`). Confirm the relocated `workspaces.*` repo metadata appears (or is documented
   as connection-config out of scope) so the drop isn't a silent export regression.
4. **Erasure path:** `account-delete.ts` must not reference the dropped columns post-drop (avoid the
   mig-064 23514 saga-abort class).
5. **Divergence message** names "<Team Name>" — always resolvable at gate time when the member is in
   the solo workspace? Needs a fallback that omits the name if not.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Divergence confirmed at `cc-dispatcher.ts:1533-1556`. Recommended a single
membership-verified `resolveActiveWorkspace(userId)` returning `{ok}|{ok:false,reason}`, resolved
once and threaded into all four consumers via existing `workspaceId?` overrides; cold-dispatch
self-heal already precedes the gate once path and repo/install share the unified id. Route the PR-2
migration through `data-migration-expert` + `data-integrity-guardian`.

### Product (CPO)

**Summary:** Member-facing failure is total product-value loss with an actively-wrong CTA. Role-branch
the copy (owner = reconnect; member = switcher deep link), owner-gate the repo card (today it has no
`isOwner` prop), and add a non-benign `repo_resolver_divergence` Sentry hook. Ship resolver fix first,
drop last after soak.

### Legal (CLO)

**Summary:** Current solo fallback does NOT create cross-tenant exposure (always `userId`, never a
sibling); removing it strengthens isolation provided no fallback becomes an unscoped membership scan
(the #4767 bug class — forbid `MIN(created_at)`/first-membership lookups). The three columns are in the
Art.15/30 DSAR surface; gate the drop on: zero live readers, backfill reconciliation, prod soak, updated
erasure+DSAR paths, `.down.sql`, and `/soleur:gdpr-gate` on the decommission diff.

### Finance (CFO)

**Summary:** Billing is 100% user-keyed (`users.*`, migs 002/020/021/029). Keep it user-keyed
short-term — the solo subscriber pays for their personal workspace, satisfying frictionless solo→team
with no relocation. Workspace-keyed/seat billing is a dedicated follow-up with revenue-risk gating,
role-gated invoice visibility, and CLO consent before exposing a solo subscriber's history to co-members.

## Visual Design

Member vs owner repo states (read-only member card · not-ready/wrong-workspace recovery with switcher
deep link · owner error state) wireframed side-by-side:
`knowledge-base/product/design/workspace-connection/member-owner-repo-states.pen`
(screenshots: `knowledge-base/product/design/workspace-connection/screenshots/`).
