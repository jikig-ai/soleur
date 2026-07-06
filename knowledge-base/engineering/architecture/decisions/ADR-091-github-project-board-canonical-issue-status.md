# ADR-091: GitHub Project v2 board is the canonical issue-Status store

- **Status:** adopting (Phase 0 + Phase 2 app changes ship; the board writer +
  the `organization_projects` App grant complete adoption)
- **Date:** 2026-07-02
- **Deciders:** Operator; drafted via `/soleur:go` → plan → this ADR
- **Related:** ADR-044 (workspace-repo ownership / installation-token chain),
  ADR-036 (GitHub App webhook ingress), PR #5659 (Workstream tab shipped)

## Context

The operator manages work on the org GitHub Project v2 board **"Soleur Kanban"**
(`jikig-ai/projects/2`), whose Status single-select has 7 columns: Backlog,
Ready, In progress, In review, Blocked, Pending, Done (Blocked + Pending added
by the operator).

Two independent "kanbans" existed and were unlinked:

1. **The GitHub Project board** — had *no* repo-side automation. 497/512 cards sat
   in Backlog because the only mover was GitHub's built-in "Auto-add → Backlog";
   nothing advanced a card afterward. Blocked/Pending were unhandled.
2. **The in-app Workstream tab** (`/dashboard/workstream`, PR #5659) — read the
   connected repo's *issues* via REST and **derived** its own columns from
   `state`/`labels` in `lib/workstream.ts`. It never read the board, its column
   set differed (`todo`/`cancelled` vs `ready`/`pending`), and the labels it
   derived from were never applied by any skill — so every open issue collapsed
   to Backlog.

A single source of truth was needed. Making the app's derived labels
authoritative would keep two writers and perpetuate the divergence.

## Decision

The **GitHub Project v2 board is the single source of truth** for issue
processing Status. Concretely:

- **Repo-side automation writes the board.** A GitHub Actions workflow
  (`board-status-sync.yml`) moves the *linked issue's* card on issue/PR/label
  lifecycle events via the Soleur GitHub App (`organization_projects`). It is the
  single writer of board Status. `issue closed → Done` is left to GitHub's
  built-in. (PR→issue linkage = `closingIssuesReferences` ∪ `Ref #N`, since
  Soleur bot PRs use `Ref #N`, not `Closes`.)
- **The app reads the board and prefers it.** `get-workstream-issues.ts` reads
  each issue's board Status via GraphQL (`fetchBoardStatusMap`) and
  `deriveColumn` **prefers** the mapped board Status; the label/state derivation
  remains a **fallback** for issues not on a board or when the board read
  degrades (which is Sentry-mirrored, never thrown). The app's 7 columns are
  aligned 1:1 with the board's.
- **Auth is the GitHub App, not a PAT** (`hr-github-app-auth-not-pat`). The
  default `GITHUB_TOKEN` cannot write an org Project v2. The App must be granted
  `organization_projects: Read and write` (org-owner consent) — until then the
  writer fails loud (403) and the reader degrades to derivation.

## Consequences

- Cards advance as issues are processed, and the Workstream tab mirrors exactly
  what the operator sees on the board — closing the two-kanban divergence.
- A single new operator prerequisite (the App permission grant) gates the write
  + read paths; both surfaces degrade honestly until it lands.
- Two GraphQL surfaces touch the board (a CI writer, a web-app reader). Accepted:
  the CI writer keeps production-server write-code out of the request path. The
  webhook-ingress alternative (below) would collapse them but adds a prod write
  surface.
- The board has no Cancelled column, so closed `not_planned`/`duplicate` issues
  render under **Done** (the app's `cancelled` status was removed).

## Alternatives Considered

- **App webhook ingress (ADR-036) writes the board from the web server** instead
  of a CI workflow — generalizes to per-workspace boards and reuses the ADR-044
  installation token, but adds a production write surface for a
  currently-Soleur-only board. **Deferred** as the multi-workspace generalization
  path (revisit when non-Soleur users maintain their own boards).
- **Make the app's derived labels canonical** and push them to the board —
  rejected: keeps two writers and re-creates the divergence this ADR resolves.
- **Classic / fine-grained PAT** for the board writes — rejected per
  `hr-github-app-auth-not-pat`.
