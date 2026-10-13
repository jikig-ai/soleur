# Brainstorm: Workstream Issue CRUD (Create / Update / Close)

**Date:** 2026-07-10
**Branch:** feat-workstream-issue-crud
**PR:** #6301 (draft)
**Lane:** cross-domain
**Brand-survival threshold:** single-user incident (user-brand-critical, auto per #5175)

## What We're Building

Wire real write operations into the Workstream tab so a founder can Create, Update,
and "Delete" (= Close) GitHub issues directly from the board — replacing the current
fake, local-only, reset-on-reload optimistic stubs with persisted, GitHub-App-authed
mutations. Every write ships with agent-native parity (a matching gated MCP tool) and
write-integrity (confirm against GitHub before committing the optimistic UI).

This is the explicitly-deferred "Part B" of PR #5659 (which shipped the read side + the
disabled "Create with Concierge" stub). The write tools `workstream_issue_create` and
`workstream_issue_set_status` are already named as deferred in
`server/workstream/workstream-tools.ts:6-7`.

## Why This Approach

- **Writes are not greenfield.** `createIssue()` already exists (`github-app.ts:1344`)
  and is wired as the gated `create_issue` MCP tool. The org GitHub App install already
  grants `issues: write` — CREATE/UPDATE/CLOSE need **no broader scope than reads**.
- **Same auth seam as reads.** All writes go through the ADR-044 installation-token
  chain via the audited `createGitHubAppClient(installationId, founderId)` factory
  (`server/github/app-client.ts`) — never a PAT (`hr-github-app-auth-not-pat`), and
  every call auto-writes an `audit_github_token_use` row (GDPR Art. 5(2)/Art. 30 PA-16).
- **Close, not delete.** GitHub REST cannot delete an issue; `githubApiPost` hard-blocks
  DELETE. True `deleteIssue` (GraphQL) needs admin, is irreversible, and destroys the
  issue number that the board's Status map is keyed on. Close (`PATCH state=closed` +
  `state_reason`) is the real founder need and is fully reversible via reopen.
- **Board grant avoidance.** Direct Project v2 board writes need `organization_projects:
  write`, still pending (feat-kanban-board-workstream-sync / ADR-097). So an in-app
  status change mutates the **issue** (labels/close/reopen) and lets the existing
  `board-status-sync.yml` webhook mirror it to the canonical board — the web app never
  needs the org grant. Accepted tradeoff: label-derivation and board Status can
  transiently disagree until the workflow fires.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | "Delete" = **Close/reopen only** | GitHub can't truly delete; true delete breaks the number-keyed board. Reversible. (operator-confirmed) |
| 2 | Create = **Concierge-first + manual quick-add fallback** | Agent-native capture matches how a founder thinks; the disabled stub was the right intuition. Quick-add avoids blocking on an agent round-trip. (operator-confirmed) |
| 3 | Update v1 = **status + inline title edit + close/reopen** | Minimum that flips the board from read-only to live. Labels/assignee/milestone/body-edit deferred. (operator-confirmed) |
| 4 | Status change writes the **issue** (labels/close), board mirrors via `board-status-sync.yml` | Avoids the pending `organization_projects: write` grant entirely. |
| 5 | Every write = a gated in-process **MCP tool** against the same server helper | Agent-native parity is a product constraint, not a nicety. No UI-only mutations; no `gh` shell-out. |
| 6 | **Write-integrity**: confirm against GitHub response before committing optimistic UI; `router.refresh()` on success only; rollback + explicit retryable error on failure | Single-user threshold — a board that silently lies costs founder trust irrecoverably. |
| 7 | All creates funnel through `createIssue()` with server-resolved `initiatorLogin` (ADR-104), stamping `<!-- soleur:initiated-by <login> -->` | Attribution single-sourced; `initiatorLogin` never sourced from request body (anti-spoof). |
| 8 | Writes are **per-workspace** (server-resolved owner/repo/installation), never request-input | Preserves the ADR-044 no-cross-tenant invariant the read path already enforces. |
| 9 | Per-user **rate-limit** on write endpoints | Authenticated user is the rate-limit key; abuse/DoS defense on issue-create. |
| 10 | Capture an **ADR** (close-not-delete + label-driven board sync) | CTO flagged this as architecture-worthy; it's a plan deliverable (`wg-architecture-decision-is-a-plan-deliverable`). |

## Non-Goals (v1)

- True issue deletion (GraphQL `deleteIssue` / admin) — explicitly out; Close covers it.
- Direct Project v2 board Status writes from the web app (blocked on org grant; use webhook mirror).
- Editing labels, assignees, milestone, or issue body in-app — follow-up slice.
- Comment create/edit/delete from the board — out of scope.
- Cross-repo / multi-repo writes — writes are single connected-repo, per-workspace only.

## Open Questions

- **Concierge create wiring**: does the "Create with Concierge" path reuse the existing
  agent-runner Concierge session, or a lighter one-shot draft call? (HOW — plan-time; the
  `CONCIERGE_ONLINE` flag currently gates it off.)
- **Status→label mapping**: exact label taxonomy the webhook consumes for each of the 7
  columns (Backlog/Ready/In progress/In review/Blocked/Pending/Done) — confirm against
  `board-status-sync.yml` mapping before implementation.
- **Optimistic reconcile for drag-to-column**: define precisely what "confirm against
  GitHub" means for the highest-frequency gesture (the PATCH returns 200 before the board
  webhook fires — reconcile on the issue mutation, show a subtle "syncing" state until the
  board read agrees).

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Build Create + Update, drop true Delete (close is the real verb). Create
should be Concierge-first with a minimal manual fallback (the disabled stub was right).
Update v1 = column/title/close. Parity and write-integrity are must-haves, not
enhancements; a silently-failed write is catastrophic at the single-user threshold.

### Engineering (CTO)

**Summary:** Writes are not greenfield — `createIssue()` exists, org install already
grants `issues: write`, all auth via ADR-044 installation tokens. Recommend close (PATCH
state) over any GraphQL delete (irreversible, breaks number-keyed board). Status change
should mutate the issue and let `board-status-sync.yml` mirror to the board, sidestepping
the pending `organization_projects: write` grant. Every UI write must land as a sibling
gated MCP tool. This is ADR-worthy.

## Capability Gaps

- **`updateIssue()` / `setIssueState()` server helper** — MISSING. `github-app.ts` has
  `createIssue()` (1344) and `createPullRequest()` but no issue-update/close helper.
  Evidence: repo-research grep of `server/github-app.ts` exported fns; `github-read-tools.ts`
  is read-only; `grep -nE 'updateIssue|setIssueState|closeIssue' server/` returns nothing.
  Needed for Update (title) + Close. Must route through the audited app-client Octokit.
- **Workstream write MCP tools** — DEFERRED-not-built. `workstream_issue_create` +
  `workstream_issue_set_status` named as deferred at `workstream-tools.ts:6-7`; no impl.
- **Write API routes / server actions** — MISSING. `/api/workstream/issues` is `GET` only;
  no `POST`/`PATCH`. Evidence: `app/api/workstream/issues/route.ts` exports `GET` only.

## User-Brand Impact

- **Artifact:** the Workstream issue-write path (create/update/close server actions + MCP tools).
- **Vector:** a silently-failed write — the board shows a create/move/close that GitHub
  never persisted — so the founder trusts a lying board, drops real work, and loses faith
  in Soleur as their work surface.
- **Threshold:** single-user incident.
