---
feature: repo-connect-block-offer-join
date: 2026-06-29
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
brainstorm: knowledge-base/project/brainstorms/2026-06-29-repo-connect-block-duplicate-brainstorm.md
plan: knowledge-base/project/plans/2026-06-29-feat-repo-connect-block-duplicate-plan.md
related_issues: ["#5673", "#5591"]
related_adrs: [ADR-044, ADR-038]
related_incidents: [WEB-PLATFORM-3M]
---

# Spec — Block duplicate repo connection (same install + repo) + switch redirect

## Problem Statement

Two **solo** workspaces sharing `(github_installation_id, normalizeRepoUrl(repo_url))` make the
non-push GitHub webhook founder resolver fail-closed (`>1 solo workspaces` → `{kind:"ambiguous"}`
→ 404-drop + Sentry page), silently dropping every non-push event (PR review, CI-failure,
issue-triage) for that repo. This is production incident **WEB-PLATFORM-3M**. The #5546
repo-scoping fix narrowed the storm but left this residual reachable: any time a second solo
workspace connects an already-connected repo under the same installation, the ambiguity returns.
There is no guard at the connect boundary — the duplicate is created, then fails at webhook time.

## Goals

- **G1** Prevent a second solo workspace from binding `(github_installation_id, normalizeRepoUrl)`
  already owned by a *different* solo workspace, via a connect-time check (check-then-write; the
  retained resolver `>1` backstop is the safety net for the rare concurrent race — see Non-Goals).
- **G2** When the owning solo workspace is the **caller's own** (reached while connecting from a
  different active workspace) and it is `ready`, redirect them to **switch** to it instead of failing.
- **G3** Never disclose to a non-owner that another workspace owns the repo; the decline carries a
  non-disclosing forward CTA.
- **G4** Detect existing duplicate-solo pairs at deploy and surface them for the operator's
  keep-which intent decision (no automated remediation).
- **G5** Amend ADR-044 to record the application-enforced scoped solo-uniqueness invariant and the
  preserved cross-install fan-out.

## Non-Goals

- **NG1** Member-initiated **request-to-join** + owner-nudge subsystem (deferred fast-follow).
- **NG2** GitHub collaborator-permission API integration (deferred path only).
- **NG3** A DB uniqueness constraint or new RPC/advisory lock — the check is application-level TS
  reusing the existing resolver; hard atomicity is explicitly NOT a goal (sequential incident; the
  resolver `>1` backstop covers the rare race, degrading to today's behavior).
- **NG4** Case-normalization of `repo_url` — the resolver matches case-sensitively and GitHub sends
  one canonical casing, so case differences never yield `>1`. Match case-sensitively (consistent
  with the resolver). Mis-cased-row-gets-no-webhooks is a separate hardening issue.
- **NG5** Reversing ADR-044's rejection of global `UNIQUE(repo_url)` — cross-install duplicates of
  the same public repo remain allowed.
- **NG6** Repo-rename stale-row reconciliation (document as known limitation in the ADR).

## Functional Requirements

- **FR1** In `apps/web-platform/app/api/repo/setup/route.ts`, before the `:202-215` cloning-flip
  write, call `resolveSoloFounderForInstallation(installationId, repoUrl, serviceClient)` (the route
  already holds `serviceClient`; `repoUrl` is normalized at `:106`).
- **FR2** Branch: `none` → proceed; `found && founderId == activeWorkspaceId` → proceed (re-connect);
  `found && founderId == user.id && that workspace ready` → **switch** (`existingWorkspaceId = founderId`);
  `found && founderId == user.id && not ready` → **decline**; `found && founderId != user.id` →
  **decline**; `ambiguous`/`db-error` → **decline** + `reportSilentFallback`.
- **FR3** Switch outcome drives the "switch to that workspace" UI (STATE 1) via the existing
  `set_current_workspace_id(existingWorkspaceId)`; after success redirect to that workspace's
  dashboard; on failure (membership revoked / workspace deleted between read and click) fall back to
  the generic decline + refresh.
- **FR4** Decline outcome returns a **fixed** `{status:409, body:{error:"This repository can't be
  connected."}}` (named baseline) — no workspace/user reference, identical regardless of whether a
  different-user owner exists. UI STATE 2 shows it plus a non-disclosing CTA: "If you should have
  access, ask the repository's workspace owner to invite you" + "Pick a different repository".
- **FR5** Agent contract for the structured outcome: `{outcome: 'ok'|'switch'|'decline', code,
  existingWorkspaceId, canRequestJoin: false}` (`code`/`canRequestJoin` forward-compatible for the
  deferred join path); switch mirrors the existing `workspace_switch_required` shape. Never a bare 404.
- **FR6** Detection query (TR1) runs at deploy; remaining duplicate-solo groups are surfaced to the
  operator with per-row detail for the keep-which intent decision. No automated remediation.

## Technical Requirements

- **TR1** Detection query:
  ```sql
  SELECT w.github_installation_id, lower(w.repo_url) AS repo, count(*), array_agg(w.id)
  FROM workspaces w
  JOIN workspace_members m ON m.workspace_id = w.id AND m.user_id = w.id AND m.role='owner'
  WHERE w.github_installation_id IS NOT NULL AND w.repo_url IS NOT NULL
  GROUP BY 1,2 HAVING count(*) > 1;
  ```
- **TR2** The connect check matches case-sensitively (reuses the resolver's `.eq("repo_url", …)`),
  consistent with the case-sensitive resolver.
- **TR3** Keep `resolve-founder-for-installation.ts:131` `>1` branch; comment it as the post-block
  backstop (now the primary race safety net); reachability unit test; existing `op:founder-ambiguous`
  Sentry alert must still fire.
- **TR4** The check runs before the optimistic clone lock (`:213`) → no partial provisioning to roll
  back on a declined/switched connect. Same read on every path → no decline-only latency side channel.
- **TR5** No new migration (no RPC, lock, GRANT, or `search_path`-pinned function).

## Acceptance Criteria

### Pre-merge (PR)
- **AC1** Route test (end-to-end through `setup/route.ts`): a different user's solo owner of
  `(install, repo)` → second connect declines, never reaches the cloning flip.
- **AC2** Switch: active = team workspace the caller is in, caller's own solo owns `(install, repo)`
  and is `ready` → `{outcome:'switch', existingWorkspaceId == user.id}`.
- **AC3** Caller's own solo owns the repo but `repo_status != 'ready'` → decline (no switch into a
  not-ready workspace).
- **AC4** Decline returns the fixed `{409, body}`; assert identical shape regardless of owner
  existence (no information disclosure / side channel).
- **AC5** Cross-install same `repo_url` → resolver `none` → proceed (ADR-044 fan-out preserved).
- **AC6** Detection query returns the seeded duplicate set (synthesized fixtures; verified read-only
  against a prod snapshot). No remediation asserted.
- **AC7** ADR-044 amendment merged; resolver `:131` reachability test green; switch success +
  switch-failure fallback covered.
- **AC8 (Post-merge soak)** WEB-PLATFORM-3M (`op:founder-ambiguous`) trends to and stays at ~0 over
  7 days post-deploy.

### Post-merge (operator / automated)
- `Ref #5673` in PR body (NOT `Closes`); `gh issue close 5673` after AC8 holds.
- Run TR1 detection post-deploy (Supabase MCP); surface remaining duplicates to operator for the
  keep-which intent decision.

## Deferred (fast-follow issue)
Collaborator **request-to-join**: member-initiated access request, owner-approval notification
deep-linking into the existing `create_workspace_invitation` modal, pending marker, CLO
collaborator-gate via GitHub API with the requester's token, and the doc updates (Privacy Policy,
Data Protection Disclosure, Art. 30 register).
