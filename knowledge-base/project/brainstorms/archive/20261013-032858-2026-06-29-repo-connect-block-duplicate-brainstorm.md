---
date: 2026-06-29
topic: repo-connect block duplicate solo workspace + offer switch/join
status: brainstorm-complete
lane: cross-domain
brand_survival_threshold: single-user incident
related_issues:
  - "#5591"   # sibling investigation: operator account owns TWO connected workspaces
related_incidents:
  - WEB-PLATFORM-3M  # ambiguous founder for installation (>1 solo workspaces)
related_adrs:
  - ADR-044  # workspace repo ownership (non-unique github_installation_id)
  - ADR-038  # team workspaces / workspace_members
---

# Brainstorm — Block duplicate repo connection (same install + repo) and offer switch/join

## What We're Building

A guard at the **repo-connect boundary** that prevents a *second solo workspace* from
binding a GitHub repo already owned by another solo workspace **under the same GitHub-App
installation**. Today two solo workspaces sharing `(github_installation_id, repo_url)` make the
non-push webhook founder resolver fail-closed (`>1 solo workspaces` → 404-drop), which silently
kills PR-review / CI-failure / issue-triage drafts for that repo. That is the production
incident **WEB-PLATFORM-3M** (≈734×/day at peak; collapsed ~99% after the #5546 repo-scoping
fix but still firing daily until the operator manually re-pointed the duplicate on 2026-06-29).

**v1 scope (operator decision — smallest safe fix):**

1. **Block** the duplicate connect with a TOCTOU-safe atomic check at the bind point.
2. **Switch** redirect: if the connecting user is *already a member* of the workspace that owns
   the repo, offer "switch to that workspace" instead of failing.
3. **Generic decline** for everyone else — never reveal that another workspace exists.
4. **Backfill** detection + remediation for any existing duplicate-solo pairs.
5. **ADR-044 amendment** documenting the scoped solo-uniqueness constraint.

**Deferred to a fast-follow issue:** the collaborator **request-to-join + owner-nudge**
subsystem (member-initiated access request, owner notification, pending marker). This is the
net-new medium/large piece; v1 deliberately avoids it.

## Why This Approach

- **Prevent at connect, not fail at webhook.** A non-push GitHub webhook carries only
  `(install, repo)` — no per-user routing data. Two solo workspaces claiming that key are
  genuinely unattributable, so the resolver can only fail-closed (drop + page). Blocking the
  *creation* of the ambiguity turns a recurring runtime incident into an impossible state.
- **Reconciles with ADR-044 (does not reverse it).** ADR-044 *deliberately rejected* a global
  `UNIQUE(repo_url)` because two users may each legitimately connect the same public repo/fork
  to **their own personal installs**. Our constraint is scoped to `(github_installation_id,
  normalizeRepoUrl)` **and solo-only** — so cross-install connections of the same public repo
  stay allowed; only the same-install duplicate (the actual webhook-attribution breaker) is
  blocked. The supported multi-user-same-repo path remains the ADR-038 **team/shared
  workspace**, which is exactly what the block nudges users toward.
- **Cheap now, honest later.** The block + switch is small/medium. The expensive
  request-to-join subsystem is deferred without leaving the incident class open.

## Key Decisions

| # | Decision | Rationale / source |
|---|----------|--------------------|
| 1 | Enforce at **`apps/web-platform/app/api/repo/setup/route.ts:~206`**, NOT `install/route.ts` | `install` writes only `github_installation_id`; the full `(install, repo_url)` tuple first exists at the `setup` cloning-flip (`:106` normalizes, `:206-208` writes both + `repo_status='cloning'`). Verified by direct read. (CTO; repo-research's `install:162` anchor was wrong.) |
| 2 | Atomic via new **`claim_repo_for_workspace` SECURITY DEFINER RPC** with `pg_advisory_xact_lock(hashtext(install_id‖repo_url))` | Solo is NOT a column (it's the `m.user_id = w.id AND role='owner'` self-join) so a partial-unique index can't express it. Advisory-lock + RPC is TOCTOU-safe. Pattern exists at mig-093. (CTO + repo-research) |
| 3 | Match on **case-insensitive** `(install, normalizeRepoUrl)` | `normalizeRepoUrl` (lib/repo-url.ts) preserves owner/repo **path case**, so `Foo/Bar` vs `foo/bar` would evade the block though GitHub treats them as the same repo. HIGH-severity gap. (CTO + repo-research) |
| 4 | **Three-way branch**, not two: member→**switch**; collaborator-not-member→**(deferred)**; neither→**generic decline** | The already-a-member "switch" case is the operator's own verified situation (personal *chatte* workspace + member of 4-person *soleur* workspace). Switch reuses the existing `current_workspace_id` RPC. (CPO) |
| 5 | **Owner-approval** is the only acceptable join model | Auto-join = cross-tenant exposure (violates ADR re-consent); pure invite-link = dormant-owner dead-end. (CPO + CLO) — but the join path itself is deferred in v1. |
| 6 | **Collaborator-gate** any existence reveal on a live GitHub collaborator check with **B's own token** | If B can already see the repo's collaborators on GitHub, confirming "a workspace exists" tells B nothing new. Non-collaborators get a generic decline with no side channels (same response/shape/timing as "no access"). Fail-closed if the API errors. (CLO) — net-new GitHub collaborator-API integration; only needed when the deferred collaborator path ships. |
| 7 | Keep the resolver's `>1` fail-closed branch as **defense-in-depth** | Becomes unreachable for new connects once enforcement lands; guard against rot with a reachability test + Sentry alert + a "post-enforcement backstop (legacy/raced rows)" comment. (CTO) |
| 8 | **Backfill:** keep oldest (`created_at`), null `github_installation_id`+`repo_url` on the rest — never delete a workspace | Mirrors the disconnect path (route.ts:139-140). Detection query captured in spec. (CTO) |
| 9 | Visual design: wireframe the **decline** + **switch** states | `wg-ui-feature-requires-pen-wireframe`. Wireframe: `knowledge-base/product/design/workspace-connection/repo-connect-block-states.pen` (screenshots `03-…switch-workspace.png`, `04-…generic-decline.png`). Matches existing `components/connect-repo/failed-state.tsx`. Operator-approved 2026-06-29. |

## Open Questions

- **OQ1 — Switch RPC reuse.** Confirm the existing `current_workspace_id`/`resolveActiveWorkspace`
  machinery exposes a safe membership-verified "switch active workspace" write the block can call
  directly, or whether a thin wrapper is needed.
- **OQ2 — Repo-rename staleness (out of v1 scope, document).** A repo rename produces a new
  normalized URL, leaving the old row stale and matchable; not a v1 blocker but note in the ADR.
- **OQ3 — Backfill timing.** Run the dedup backfill in the same PR as the constraint, or as a
  separate verified migration step before the RPC starts rejecting? (Deployment-verification call.)

## User-Brand Impact

- **Artifact:** the repo-connect block + switch flow at `repo/setup` (the `claim_repo_for_workspace`
  guard and its two user-facing states).
- **Vector:** a privacy leak (revealing to a non-collaborator that another user has connected a
  private repo) or a false block that strands a legitimate solo user from connecting their own repo.
- **Threshold:** single-user incident.

## Domain Assessments

**Assessed:** Engineering, Product, Legal (triad, user-brand-critical per #5175). Marketing,
Operations, Sales, Finance, Support — not relevant.

### Engineering (CTO)
Enforce at `setup/route.ts` (not `install`); atomic via advisory-lock RPC (solo isn't a column);
fix the path-case evasion; keep the resolver `>1` branch as a rot-guarded backstop. Block =
small/medium; request-to-join = net-new medium/large subsystem (deferred).

### Product (CPO)
Three-way branch (switch / request-join / decline). Owner-approval only. Leaning on existing
invites is acceptable for v1 *if* paired with a request nudge — but operator deferred the whole
collaborator path, so v1 = block + switch + generic decline. Agent-native contract defined for
when connect becomes agent-exposed (not yet): `{ok:false, code, canRequestJoin, existingWorkspaceId}`,
never a bare 404.

### Legal (CLO)
GUARDRAILED-PERMITTED. Collaborator-gate is the threshold control (fail-closed). Keep owner A
pseudonymous until A consents by accepting. Sharing B's GitHub handle with A on a join request is
permitted+necessary with prior notice — relevant only when the deferred path ships. Doc impact
(when join ships): Privacy Policy + Data Protection Disclosure + **Art. 30 register** (the
commonly-missed one).

## Capability Gaps

- **Member-initiated "request to join" does not exist.** Only owner-initiated invites ship today
  (`create_workspace_invitation` / `accept_workspace_invitation`, mig-075; `app/api/workspace/invite-member/route.ts`).
  Evidence: repo-research grep of `workspace_invitations`, `invite`, `accept`, `request` found
  owner-initiated only. → Deferred to fast-follow.
- **No GitHub collaborator-permission API usage anywhere.** Evidence: grep for `collaborator`,
  `getCollaboratorPermissionLevel`, octokit permission calls = zero hits. The CLO collaborator-gate
  is net-new integration. → Needed only when the deferred collaborator path ships.

## Sibling work

- **#5591** (open) — "operator account owns TWO connected 'My Workspace' rows" — same incident,
  investigation framing; its item 3 ("guard the creation path") is exactly this v1's block. This
  brainstorm is the prevention half. Bundle/reference at issue time.
