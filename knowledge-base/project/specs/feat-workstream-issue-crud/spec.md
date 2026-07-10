---
title: Workstream Issue CRUD (Create / Update / Close)
feature: feat-workstream-issue-crud
date: 2026-07-10
status: draft
lane: cross-domain
brand_survival_threshold: single-user incident
branch: feat-workstream-issue-crud
pr: 6301
brainstorm: knowledge-base/project/brainstorms/2026-07-10-workstream-issue-crud-brainstorm.md
design: knowledge-base/product/design/workstream/workstream-issue-crud.pen
closes: [5677]
relates: [6267]
---

# Spec: Workstream Issue CRUD

## Problem Statement

The Workstream tab reads real GitHub issues (PR #5659) but every write is a fake,
local-only optimistic stub that resets on reload: the New Issue dialog doesn't persist,
the "Create with Concierge" field is disabled, and the drawer's status `<select>` doesn't
save. The agent has read-only parity (`workstream_issues_list`) but cannot create or
advance issues (gap tracked in #5677). A founder using Soleur as their work surface cannot
actually manage work from the board — they must drop to GitHub.

## Goals

- Persist real GitHub issue **Create**, **Update** (title + status), and **Close/Reopen**
  from the Workstream board, authed via the ADR-044 GitHub-App installation-token seam.
- Ship agent-native parity: matching gated MCP write tools against the same server helper
  (closes #5677).
- Guarantee write-integrity: no optimistic UI state is committed unless GitHub confirms
  the write; failures roll back with an explicit, retryable error.

## Non-Goals

- True issue deletion (GraphQL `deleteIssue` / admin) — Close covers the need; deletion
  destroys the number-keyed board and is irreversible.
- Direct GitHub Project v2 board Status writes from the web app (blocked on the pending
  `organization_projects: write` grant) — status changes mutate the issue and the existing
  `board-status-sync.yml` webhook mirrors to the board.
- In-app editing of labels, assignees, milestone, or issue body (follow-up slice).
- Comments; cross-repo / multi-repo writes.

## Functional Requirements

- **FR1 — Manual quick-add create.** New Issue dialog persists title (required) + optional
  body to a real GitHub issue on the active workspace's connected repo. Card appears in
  Backlog and survives reload. Wireframe: frames 08–10.
- **FR2 — Create with Concierge.** The (now-enabled) Concierge field takes a natural-language
  description; an agent drafts title/body/labels; the user confirms/edits before the real
  issue is created (nothing is created pre-confirmation). Wireframe: frames 11–13.
- **FR3 — Inline title edit.** The detail drawer allows editing an issue's title with
  save/cancel; the change persists to GitHub. Wireframe: frames 14–16.
- **FR4 — Persisted status change.** Moving an issue's status/column persists (via label
  mutation on the issue); the UI shows an async "Syncing to Project board…" state because
  the board mirror is eventually-consistent. Wireframe: frame 17.
- **FR5 — Close / reopen.** A "Close issue" action with a reason (Completed → Done /
  Not planned → Cancelled) closes the issue; a closed issue offers "Reopen". Wireframe:
  frames 18–19.
- **FR6 — Creator attribution (ADR-104).** Every create funnels through `createIssue()`
  with `initiatorLogin` resolved server-side from the session (never request body),
  stamping `<!-- soleur:initiated-by <login> -->`.
- **FR7 — Agent-native parity.** Every UI write verb ships as a gated in-process MCP tool
  (`workstream_issue_create`, `workstream_issue_set_status`, and title/close equivalents)
  delegating to the same server helper. No UI-only write; no `gh` shell-out. Closes #5677.

## Technical Requirements

- **TR1 — Auth seam.** All writes route through the audited `createGitHubAppClient(
  installationId, founderId)` (`server/github/app-client.ts`) so each call writes an
  `audit_github_token_use` row (GDPR Art. 5(2)/Art. 30 PA-16). GitHub App only, never a
  PAT (`hr-github-app-auth-not-pat`).
- **TR2 — Server helpers.** Add `updateIssue()` / `setIssueState()` to `github-app.ts`
  (currently only `createIssue()` exists). Add write API surface: `POST /api/workstream/issues`
  and `PATCH /api/workstream/issues/:number` (route currently `GET`-only), session-gated,
  502-on-failure, mirrored to Sentry.
- **TR3 — Per-workspace scope.** owner/repo/installation resolve ONLY from the server-side
  active workspace (ADR-044) — never request input — preserving the no-cross-tenant
  invariant. Cross-account installs with only `issues: read` must surface the 403 honestly.
- **TR4 — Write-integrity / optimistic reconcile.** Optimistic UI commits only after the
  mutation's GitHub response; `router.refresh()` on success only; roll back + retryable
  error on failure; gate any chained effect on server-ack, not the optimistic flag.
  SWR list key distinct from per-issue keys; revalidate list key on success.
- **TR5 — Rate limiting.** Per-user throttle on the write endpoints (authenticated user is
  the key), with an endpoint-level throttle as a DoS defense.
- **TR6 — Board mirror.** Status label taxonomy must match what `board-status-sync.yml`
  consumes for the 7 columns; the web app never calls the Project v2 GraphQL write path.
- **TR7 — ADR.** Capture an ADR for "Workstream issue writes: close-not-delete + label-driven
  board sync" (`wg-architecture-decision-is-a-plan-deliverable`).
- **TR8 — Review.** Run `agent-native-reviewer` (read/write parity) + `security-sentinel`
  (write-boundary, anti-spoof on initiatorLogin) at code review.

## Open Questions (resolve at plan time)

- Concierge draft path: reuse the agent-runner Concierge session vs a lighter one-shot draft call.
- Exact status→label mapping per column (confirm against `board-status-sync.yml`).
- "Confirm against GitHub" semantics for drag-to-column specifically (issue PATCH returns
  before the board webhook fires).
