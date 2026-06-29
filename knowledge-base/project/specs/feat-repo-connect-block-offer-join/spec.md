---
feature: repo-connect-block-offer-join
date: 2026-06-29
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
brainstorm: knowledge-base/project/brainstorms/2026-06-29-repo-connect-block-duplicate-brainstorm.md
related_issues:
  - "#5591"
related_adrs:
  - ADR-044
  - ADR-038
related_incidents:
  - WEB-PLATFORM-3M
---

# Spec — Block duplicate repo connection (same install + repo) + switch redirect

## Problem Statement

Two **solo** workspaces sharing the same `(github_installation_id, normalizeRepoUrl(repo_url))`
make the non-push GitHub webhook founder resolver fail-closed (`>1 solo workspaces` →
`{kind:"ambiguous"}` → 404-drop + Sentry page). Every non-push event (PR review, CI-failure,
issue-triage) for that repo is silently dropped. This is production incident **WEB-PLATFORM-3M**.
The #5546 repo-scoping fix narrowed the storm but left this residual reachable: any time a second
solo workspace connects an already-connected repo under the same installation, the ambiguity
returns. There is currently **no guard at the connect boundary** — the duplicate is created, then
fails at webhook time.

## Goals

- **G1** Prevent a second solo workspace from binding `(github_installation_id, normalizeRepoUrl)`
  already owned by a *different* solo workspace, atomically (no check-then-insert race).
- **G2** When the connecting user is already a member of the owning workspace, redirect them to
  **switch** to it instead of failing.
- **G3** Never disclose to a non-member/non-collaborator that another workspace owns the repo.
- **G4** Detect and remediate existing duplicate-solo pairs in prod without deleting workspaces.
- **G5** Amend ADR-044 to record the scoped solo-uniqueness constraint and the preserved
  cross-install fan-out invariant.

## Non-Goals

- **NG1** Member-initiated **request-to-join** + owner-nudge subsystem (deferred fast-follow).
- **NG2** GitHub collaborator-permission API integration (only needed for the deferred path).
- **NG3** Reversing ADR-044's rejection of global `UNIQUE(repo_url)` — cross-install duplicates of
  the same public repo remain allowed.
- **NG4** Repo-rename stale-row reconciliation (document as known limitation in the ADR).
- **NG5** Agent-exposed connect contract build-out (connect is not agent-exposed yet; define the
  shape in the ADR for when Phase-N exposes it).

## Functional Requirements

- **FR1** At `apps/web-platform/app/api/repo/setup/route.ts` (~line 206, the `repo_status='cloning'`
  bind), before/at the write, call a new `claim_repo_for_workspace(p_workspace_id, p_install_id,
  p_repo_url)` RPC that atomically rejects the bind if a *different* solo workspace already owns
  `(p_install_id, p_repo_url)`.
- **FR2** The owner detection inside the RPC reuses the resolver's solo self-join semantics
  (`m.user_id = w.id AND m.role='owner'`), scoped by `github_installation_id` AND
  case-insensitive `repo_url` match.
- **FR3** If the connecting user is already a `workspace_members` row of the owning workspace,
  the route returns a **switch** outcome (no block error) that drives the "switch to that
  workspace" UI state. _(wireframe: STATE 1)_
- **FR4** Otherwise the route returns a **generic decline** — no mention of another workspace,
  another user, or "taken." Response code/shape/latency identical to a plain no-access failure.
  _(wireframe: STATE 2)_
- **FR5** A backfill detection query identifies existing duplicate-solo `(install, repo_url)`
  groups; remediation keeps the oldest by `created_at` and nulls `github_installation_id` +
  `repo_url` on the rest (mirrors disconnect), never deleting a workspace.

## Technical Requirements

- **TR1** RPC takes `pg_advisory_xact_lock(hashtext(p_install_id::text ‖ lower(p_repo_url)))` to
  serialize concurrent connects on the same key; lock auto-releases on commit. (Pattern: mig-093.)
- **TR2** Matching uses the mig-031 normalized form with **case-insensitive** owner/repo path
  comparison (closes the `Foo/Bar` vs `foo/bar` evasion in `lib/repo-url.ts`).
- **TR3** Keep `resolve-founder-for-installation.ts` `>1` fail-closed branch as defense-in-depth;
  add a reachability test + comment marking it the post-enforcement backstop for legacy/raced rows;
  ensure a Sentry alert still fires if it triggers.
- **TR4** Block fires before the optimistic clone lock — no partial workspace provisioning to roll
  back on a rejected connect.
- **TR5** Backfill detection query:
  ```sql
  SELECT w.github_installation_id, lower(w.repo_url) AS repo, count(*), array_agg(w.id)
  FROM workspaces w
  JOIN workspace_members m ON m.workspace_id = w.id AND m.user_id = w.id AND m.role='owner'
  WHERE w.github_installation_id IS NOT NULL AND w.repo_url IS NOT NULL
  GROUP BY 1,2 HAVING count(*) > 1;
  ```

## Acceptance Criteria

- **AC1** Two solo workspaces under the same install cannot both bind the same repo; the second
  connect is atomically rejected (verified with a concurrent-connect test).
- **AC2** `Foo/Bar` and `foo/bar` under the same install are treated as the same repo (block fires).
- **AC3** A user who is already a member of the owning workspace gets the switch outcome, not an error.
- **AC4** A non-member receives a generic decline with no information disclosure (no workspace/user
  reference; identical response shape to a no-access failure).
- **AC5** Cross-install connections of the same public repo are NOT blocked (ADR-044 fan-out preserved).
- **AC6** Backfill query + remediation verified against prod copy; no workspace rows deleted.
- **AC7** ADR-044 amendment merged; resolver `>1` reachability test green.
- **AC8** WEB-PLATFORM-3M trends to and stays at ~0 post-deploy (the residual can no longer be created).

## Deferred (fast-follow issue)

Collaborator **request-to-join**: member-initiated access request, owner-approval notification
deep-linking into the existing `create_workspace_invitation` modal, pending marker, CLO
collaborator-gate via GitHub API with the requester's token, and the doc updates (Privacy Policy,
Data Protection Disclosure, Art. 30 register).
