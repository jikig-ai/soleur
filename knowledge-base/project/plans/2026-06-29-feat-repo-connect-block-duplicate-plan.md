---
title: "feat(workspace): block duplicate solo repo-connect (same install+repo) + switch redirect"
date: 2026-06-29
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issue: "#5673"
related_issues: ["#5591"]
branch: feat-repo-connect-block-offer-join
pr: "#5671"
brainstorm: knowledge-base/project/brainstorms/2026-06-29-repo-connect-block-duplicate-brainstorm.md
spec: knowledge-base/project/specs/feat-repo-connect-block-offer-join/spec.md
related_adrs: [ADR-044, ADR-038]
related_incidents: [WEB-PLATFORM-3M]
plan_review: applied (spec-flow + Kieran + DHH + code-simplicity; RPC deleted in favor of TS resolver-reuse)
---

# feat(workspace): block duplicate solo repo-connect + switch redirect

## Overview

Stop a **second solo workspace** from binding a GitHub repo already owned by a *different solo
workspace under the same installation* — the condition that makes the non-push webhook founder
resolver fail-closed (`>1 solo workspaces` → 404-drop), i.e. production incident **WEB-PLATFORM-3M**.

**Approach (post-review):** a **TypeScript connect-time check** in `repo/setup/route.ts` that reuses
the existing `resolveSoloFounderForInstallation` query via the service-role client the route
already holds. No new migration, RPC, or advisory lock — plan-review (DHH + Simplicity) showed the
incident is sequential (one operator, two sessions), the double-click race is already covered by the
optimistic `.neq("repo_status","cloning")` lock at `setup/route.ts:213`, and the rare true race
degrades to *today's behavior* via the retained `>1` resolver backstop at
`resolve-founder-for-installation.ts:131`. Reusing the resolver keeps **one** source of truth for
the solo invariant (an RPC would be a second, drift-prone SQL copy).

**v1 (this plan):** the TS block; a **switch** redirect when the owning solo workspace is the
caller's own (reached while connecting from a different active workspace) and it is `ready`; a
**generic, non-disclosing decline** with a forward CTA for everyone else; a **detection-only**
duplicate-pair query at deploy; the ADR-044 amendment (application-enforced scoped uniqueness).

**Deferred (fast-follow, NOT this plan):** member-initiated request-to-join, owner-nudge
notification, GitHub collaborator-gate, and the legal doc updates (Privacy Policy / Data Protection
Disclosure / Art. 30). Tracked under #5673's "Deferred" section.

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Codebase reality (verified) | Plan response |
|---|---|---|
| Enforce at `repo/install/route.ts` | `install:165` writes only `github_installation_id`; the `(install, repo_url)` tuple is first complete at `setup:106`+`:206-208`. | Enforce in **`setup/route.ts` just before the `:202-215` cloning flip**. |
| Need a new RPC + advisory lock for atomicity | Route already holds `createServiceClient()` (`:114`) + does cross-workspace service-role reads (`:168-172`); collision query already exists (`resolveSoloFounderForInstallation`, `:88-103`); double-click covered by optimistic lock (`:213`); rare race backstopped by resolver `:131`. | **Drop the RPC/lock.** TS check reusing the resolver. No migration. |
| Switch = "caller is a member of the owning workspace" + a `workspace_members` SELECT | Owning workspace is always **solo** (owner == its id), so "member" ⟺ `founderId == user.id`. No membership query needed. | Switch iff `founderId == user.id` AND that workspace's `repo_status == 'ready'`. |
| Case-insensitive `(install, repo_url)` match (TR2/AC2) | Resolver matches `repo_url` **case-sensitively** (`:102`); GitHub sends one canonical casing, so `Foo/Bar` vs `foo/bar` never yields `>1`. A case-insensitive block over-rejects pairs the resolver never collides on. | **Drop TR2/AC2.** Match case-sensitively (consistent with resolver). File case-normalization (resolver+storage+block) as a separate issue. |
| `set_current_workspace_id` exists for switch | Yes — `accept-invite:78`, `active-repo:59`; `workspace_switch_required`+`switchToWorkspaceId` agent signal at `cc-dispatcher:3651`. | Reuse for the switch action + agent contract shape. |
| Backfill remediation (keep-oldest, null the rest) | "Keep oldest" is the wrong heuristic — the operator's real re-point chose by *intent* (chatte vs soleur), not age; auto-null could disconnect the wrong workspace. Operator already resolved the live dup. | **Detection-only** deploy query; surface remaining dups for the operator's intent call (a genuine judgment, not a deferrable mechanical step). No remediation migration. |

## Implementation Phases

### Phase 1 — TS connect-time check in `setup/route.ts`
- After the owner gate and install resolution, **before** the `:202-215` cloning-flip write, call the existing `resolveSoloFounderForInstallation(installationId, repoUrl, serviceClient)` (`repoUrl` is already normalized at `:106`).
- Branch on the result:
  - `none` → proceed (unchanged happy path).
  - `found` with `founderId == activeWorkspaceId` → proceed (caller's active workspace already owns it; re-connect/no-op).
  - `found` with `founderId == user.id` (≠ activeWorkspaceId) AND that workspace's `repo_status == 'ready'` → **switch** outcome carrying `existingWorkspaceId = founderId` (the caller's own solo).
  - `found` with `founderId == user.id` but `repo_status != 'ready'` → **decline** (don't switch into a not-ready workspace — GAP-2).
  - `found` with `founderId != user.id` → **decline** (a different user's solo owns it).
  - `ambiguous`/`db-error` → **decline** + `reportSilentFallback` (fail-closed; never silent write-through).
- The check runs on every connect, so `ok`/`switch`/`decline` pay the **same** resolver read — no decline-only latency side channel (GAP-4).

### Phase 2 — UI: decline + switch states (no new component)
- Extend `components/connect-repo/failed-state.tsx` (copy table `:30-87`, CTA dispatch `:95-107`) — no new file:
  - **STATE 1 (switch):** new copy entry + `primaryCta.action:'switch'` wired to `set_current_workspace_id(existingWorkspaceId)`. Copy: "You're already in a workspace for this project" → "Switch to that workspace". After switch, redirect to that workspace's dashboard; if `set_current_workspace_id` fails (membership revoked / workspace deleted between read and click), fall back to the generic decline + refresh (GAP-3).
  - **STATE 2 (generic decline):** new copy entry. "This repository can't be connected." + a **non-disclosing forward CTA**: "If you should have access, ask the repository's workspace owner to invite you." (true for strangers too — no existence reveal) + "Pick a different repository" (GAP-1). No mention of another workspace/user/"taken".

### Phase 3 — Detection-only duplicate query (deploy verification)
- Ship the read-only detection query (TR5) as a deploy-verification step (Supabase MCP / read-only). If it returns duplicate-solo `(install, lower(repo_url))` groups, surface them to the operator with per-row detail (id, repo, created_at, members) for the **intent** decision of which to keep — mirroring the operator's chatte-vs-soleur re-point. No automated remediation (wrong-keep risk; the live dup is already resolved).

### Phase 4 — ADR-044 amendment + resolver backstop + C4
- Amend `ADR-044-workspace-repo-ownership.md` `## Decision` + `## Alternatives Considered`: record the **application-enforced** scoped solo-uniqueness invariant (at most one solo workspace per `(github_installation_id, normalizeRepoUrl)`), enforced at the `repo/setup` connect boundary — **not** a DB constraint, and explicitly **not** the rejected global `UNIQUE(repo_url)` (Option C, lines 26-34); cross-install fan-out preserved; supported multi-user-same-repo path remains the ADR-038 team workspace.
- Resolver backstop (now the primary safety net for the dropped atomicity): comment `resolve-founder-for-installation.ts:131` as the post-block backstop; reachability unit test; confirm the `op:founder-ambiguous` Sentry alert still fires.
- **C4: no element/edge change.** Verified against all three `.c4` files: (a) connecting user is the existing `founder` Owner actor (description already models multiple Owners, ADR-038) — no new actor; (b) GitHub already modeled, v1 makes **no** collaborator-API call (that edge belongs to the deferred path); (c) `api` + `supabase` already modeled; the new logic is TS inside `api`, reached via the existing `api -> supabase` edge; (d) no access-relationship edge added or falsified. A future `api -> github "collaborator check"` edge is noted for the deferred path. No `.c4` edit → render tests unchanged.

## Files to Edit
- `apps/web-platform/app/api/repo/setup/route.ts` — resolver-reuse check + 3-way branch (Phase 1).
- `apps/web-platform/components/connect-repo/failed-state.tsx` (+ caller) — switch/decline states (Phase 2).
- `apps/web-platform/server/resolve-founder-for-installation.ts` — backstop comment + reachability test (Phase 4).
- `knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md` — amendment (Phase 4).
- Test files (see Test Scenarios).

## Files to Create
- None. (No migration; UI states fit `failed-state.tsx`.)

## Acceptance Criteria

### Pre-merge (PR)
- **AC1** Route test through `setup/route.ts`: when a *different user's* solo workspace owns `(install, repo)`, the second connect returns **decline**, never proceeds to the cloning flip. (Tested end-to-end through the route, not a resolver unit alone.)
- **AC2** Switch reachability: with `activeWorkspaceId` = a team workspace the caller is in, and the caller's **own solo** owning `(install, repo)` and `ready`, the connect returns `{outcome:'switch', existingWorkspaceId == user.id}`. Fixture constructs exactly that topology.
- **AC3** Switch is NOT offered when the caller's own solo owns the repo but its `repo_status != 'ready'` → decline (GAP-2).
- **AC4** Non-owner decline returns a fixed `{status:409, body:{error:"This repository can't be connected."}}` (baseline named explicitly), carrying no workspace/user reference; identical shape regardless of whether a different-user owner exists (no information disclosure / side channel).
- **AC5** Cross-install connection of the same `repo_url` is NOT blocked (different `github_installation_id` → resolver `none` → proceed).
- **AC6** Detection query returns the duplicate-solo set; verified read-only against a prod snapshot. (No remediation migration; result is surfaced for operator intent decision.)
- **AC7** ADR-044 amendment merged; `resolve-founder-for-installation.ts:131` reachability test green; `set_current_workspace_id` switch path + switch-failure fallback covered.
- **AC8 (Post-merge soak)** WEB-PLATFORM-3M (`op:founder-ambiguous`) trends to and stays at ~0 over 7 days post-deploy (the residual can no longer be *created*; AC1 carries the direct proof).

### Post-merge (operator / automated)
- `Ref #5673` in PR body (NOT `Closes` — AC8 soak closes it). `gh issue close 5673` after AC8 holds.
- Run the detection query post-deploy (Supabase MCP); if duplicates remain, surface to operator for the keep-which intent decision.

## User-Brand Impact
- **If this lands broken, the user experiences:** a false block that strands a legitimate solo user from connecting their own repo, OR the duplicate keeps getting created and PR-review/CI/triage drafts silently stop for that repo (the WEB-PLATFORM-3M symptom).
- **If this leaks, the user's workflow is exposed via:** revealing to a non-collaborator that another user connected a (private) repo — mitigated by the generic decline (no existence reveal; collaborator-gate is in the deferred path).
- **Brand-survival threshold:** single-user incident. → `requires_cpo_signoff: true`; `user-impact-reviewer` runs at PR review.

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carried forward from brainstorm `## Domain Assessments`; triad spawned under `USER_BRAND_CRITICAL`).

### Engineering (CTO) — Status: reviewed (carry-forward + plan-review revision)
Enforce at `setup`; **reuse the resolver in TS** (RPC/lock deleted on plan-review — sequential incident, retained backstop covers the rare race); keep resolver `>1` backstop; case-insensitivity dropped as incoherent with the case-sensitive resolver.

### Legal (CLO) — Status: reviewed (carry-forward)
GUARDRAILED-PERMITTED at single-user-incident. v1 generic decline carries no disclosure surface. Collaborator-gate + Art. 30 obligations attach to the **deferred** path, not v1.

### Product/UX Gate
- **Tier:** blocking (UI-surface override — `components/connect-repo/*`).
- **Decision:** reviewed.
- **Agents invoked:** ux-design-lead (brainstorm 3.55 — wireframes committed + operator-approved), spec-flow-analyzer (this plan; 6 gaps folded), cpo (brainstorm carry-forward).
- **Skipped specialists:** none.
- **Pencil available:** yes (`.pen` at `knowledge-base/product/design/workspace-connection/repo-connect-block-states.pen`).
- **Findings:** three-way branch (switch / deferred-request / decline); spec-flow GAP-1..5 folded (decline CTA, switch-ready gate, post-switch landing, named decline baseline, agent `code`/`canRequestJoin`).

## Architecture Decision (ADR/C4)
### ADR
**Amend ADR-044** via `/soleur:architecture`: add the **application-enforced** scoped solo-uniqueness Decision clause + an `## Alternatives Considered` row distinguishing it from the rejected global `UNIQUE(repo_url)` (Option C). In-scope task (Phase 4), not a deferred issue (`wg-architecture-decision-is-a-plan-deliverable`). Status `adopting` → `accepted` after AC8 soak.
### C4 views
**No C4 element or edge change** — enumeration cited in Phase 4 (checked all three `.c4` files: existing `founder` actor models multi-Owner; no new external actor/system; logic is TS inside `api` over the existing `api → supabase` edge). Future `api → github "collaborator check"` edge noted for the deferred path.

## Observability
```yaml
liveness_signal:
  what: WEB-PLATFORM-3M (op:founder-ambiguous) event rate
  cadence: continuous (Sentry)
  alert_target: existing Sentry issue alert on op:founder-ambiguous
  configured_in: apps/web-platform/infra/sentry/*.tf
error_reporting:
  destination: Sentry via reportSilentFallback on resolver ambiguous/db-error in the connect check
  fail_loud: true (ambiguous/db-error → decline + Sentry, never silent write-through)
failure_modes:
  - mode: duplicate slips past block (legacy/raced row)
    detection: resolver :131 >1 branch fires
    alert_route: existing op:founder-ambiguous Sentry alert (the retained backstop canary)
  - mode: false block of a legitimate solo connect
    detection: decline outcome logged with workspace+install ids + resolver kind
    alert_route: Sentry warning on unexpected decline-rate increase
logs:
  where: structured server log on each non-proceed outcome (workspace_id, install_id, normalized repo_url, resolver kind, outcome)
  retention: Better Stack default
discoverability_test:
  command: "doppler run -p soleur -c prd -- scripts/sentry-issue.sh WEB-PLATFORM-3M"
  expected_output: 24h count trending to 0 post-deploy (no ssh)
```

## Open Code-Review Overlap
- **#3739** (extract `reportSilentFallbackWithUser` across 11 sites) touches `setup/route.ts`. **Disposition: Acknowledge** — cross-cutting helper extraction, distinct concern; this PR adds a branch + one `reportSilentFallback` call (which #3739's refactor will later absorb). Leave #3739 open.

## GDPR / Compliance (Phase 2.7 disposition)
v1 adds **no new personal-data processing** — it's an internal ownership check reusing an existing read; the generic decline reveals nothing. The regulated surface (sharing requester GitHub identity with an owner; collaborator-API processing; Art. 30 entry) attaches to the **deferred** collaborator path; `/soleur:gdpr-gate` runs at /work for that PR, not v1. CLO carry-forward (guardrailed-permitted) satisfies the gate for v1.

## Test Scenarios
- Route unit (through `setup/route.ts`): `none`→proceed; same-active-workspace owner→proceed; caller's-own-solo + ready→switch; caller's-own-solo + not-ready→decline; different-user solo→decline; `ambiguous`/`db-error`→decline + Sentry.
- Switch path: `set_current_workspace_id` success → redirect; failure (revoked/deleted) → decline + refresh.
- Decline shape: assert fixed `{409, body}` identical regardless of whether a different-user owner exists (no side channel).
- Resolver `:131` reachability unit test (the backstop is now the primary race safety net).
- Detection query: finds seeded duplicate-solo group (synthesized fixtures only, `cq-test-fixtures-synthesized-only`; never prod). No remediation asserted.

## Risks & Mitigations
- **Dropped hard-atomic guarantee** — a sub-ms concurrent double-connect by two *different* users on the same `(install, repo)` (never observed; same install ≈ same account/org) would create one duplicate, fail-closed by the retained resolver `:131` backstop (today's behavior) until the operator re-points. Accepted tradeoff (plan-review consensus). Escape hatch if it ever materializes: the `claim_repo_clone_lock` (mig-108) SECURITY-DEFINER+advisory-lock shape, folding the write into the lock.
- **Switch into not-ready workspace** — gated on `repo_status=='ready'` (AC3).
- **Decline information disclosure** — fixed baseline response + uniform read cost; no side channel (AC4).
- **Resolver backstop rot** — reachability test + Sentry alert keep `:131` honest (it is now load-bearing, not merely defense-in-depth).

## Sharp Edges
- Phase order is load-bearing only in that the resolver-reuse check (Phase 1) precedes the UI wiring (Phase 2); both ship in one atomic PR.
- The deferred collaborator path (request-to-join + collaborator-gate + Art. 30) is NOT in this plan — do not let /work scope-creep it in; it carries its own PII brand-survival framing.
- `## User-Brand Impact` is filled (carried from brainstorm) — required by `deepen-plan` Phase 4.6.
