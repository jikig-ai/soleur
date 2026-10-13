---
title: "feat: Workstream Issue CRUD (Create / Update / Close from the board)"
type: feat
date: 2026-07-10
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
branch: feat-workstream-issue-crud
worktree: .worktrees/feat-workstream-issue-crud
pr: 6301
issue: 6304
closes: [5677]
relates: [6267]
brainstorm: knowledge-base/project/brainstorms/2026-07-10-workstream-issue-crud-brainstorm.md
spec: knowledge-base/project/specs/feat-workstream-issue-crud/spec.md
design: knowledge-base/product/design/workstream/workstream-issue-crud.pen
adr: ADR-109 (provisional)
---

# feat: Workstream Issue CRUD (Create / Update / Close from the board)

## Overview

Wire real GitHub-issue **Create / Update (title + status) / Close-reopen** into the
Workstream tab, replacing the fake local-only optimistic stubs from PR #5659. Every write
authenticates via the ADR-044 GitHub-App installation-token seam, confirms against GitHub's
response before committing optimistic UI, and ships a matching gated MCP tool (agent-user
parity, closing #5677). "Delete" is realized as **Close/reopen** — GitHub cannot truly delete
an issue without irreversible admin GraphQL that destroys the board's number key.

**Scope is locked (operator-confirmed at brainstorm):** Create = Concierge-first + manual
quick-add fallback; Update v1 = status + inline title + close/reopen; true delete, label/
assignee/milestone/body editing, and comments are out.

## Research Reconciliation — Spec vs. Codebase

Spec was authored directly from same-session code reading; all claims verified against
`origin/main` at plan time. No fiction inherited. Key confirmations:

| Spec/plan claim | Reality (verified) | Plan response |
|---|---|---|
| `createIssue()` exists | `github-app.ts:1344` — `createIssue(installationId, owner, repo, title, body?, labels?)`, POSTs `/repos/{o}/{r}/issues` | Reuse; add `initiatorLogin` marker (ADR-104) |
| No issue-update/close helper | Confirmed absent (`grep updateIssue\|setIssueState` → 0) | Build `updateIssue()` + `setIssueState()` in `github-app.ts` |
| Status derives from labels | `lib/workstream.ts:340 deriveColumn` — open: `blocked>pending>in-progress>review\|needs-review>ready\|todo>backlog`; closed→done | Status-write = swap sibling status labels; close = state |
| Board consulted only for org repo | `get-workstream-issues.ts:67-71` — `readBoardStatuses` returns null unless `owner === SOLEUR_KANBAN_ORG` | For a user's own repo, labels ARE the source of truth — no board grant needed. Board-precedence concern is jikig-ai dogfood only |
| `board-status-sync.yml` DOES listen to labels | `issues: types: [reopened, labeled, unlabeled]` (`:22-25`); `set-board-status.sh:108 recompute_issue()` derives Status FROM labels | A status-label write DOES fire the sync + move the card — the earlier "no `labeled` trigger" premise was WRONG (quoted the `pull_request:` block) |
| Snap-back cause is GRANT-gated, not trigger-gated | Workflow needs `organization_projects: write` (still pending) → 403 FAIL-LOUD; until then board Status unchanged, org read overrides label | AC11 drag-disable is conditioned on the **grant STATE**, not a missing trigger; lifts automatically when the grant lands |
| App vs board derivation DIVERGE | app `deriveColumn` (`lib/workstream.ts:340`): `in-progress > ready/todo`; board `recompute_issue`: `ready/todo > in-progress`, open-PR cross-ref overrides labels | Durable skew even after the grant → explicit risk; single-source the two precedence tables or document accepted skew |
| Only `createGitHubAppClient` audits | `github/app-client.ts:80` writes `audit_github_token_use` via octokit hooks; `createIssue`/`github-api.ts` use `generateInstallationToken()` directly → NO audit row | Route ALL writes through `createGitHubAppClient(installationId, founderId).rest.issues.*`, thread `founderId` (session) — writes are a higher-value PA-16 audit target than reads |
| Write route absent | `app/api/workstream/issues/route.ts` = `GET` only | Add `POST` + a `[number]/route.ts` `PATCH` |
| MCP write tools deferred | `workstream-tools.ts:6-7` names them deferred | Build `workstream_issue_create` + `workstream_issue_set_status` (+ title/close), tier `gated` (`tool-tiers.ts:52` precedent) |
| Audited App client | `github/app-client.ts` `createGitHubAppClient(installationId, founderId)` writes `audit_github_token_use` per call | Route all writes through it (or the existing `github-app.ts` helpers that use the same token seam) |

## User-Brand Impact

**If this lands broken, the user experiences:** the Workstream board shows a create / column-move /
close that GitHub never persisted — a board that silently lies about their real work.
**If this leaks, the user's workflow is exposed via:** a spoofable `initiatorLogin` letting one
user attribute an issue to another, or a write path that accepts request-supplied owner/repo and
writes cross-tenant.
**Brand-survival threshold:** single-user incident.

## Architecture Decision (ADR/C4)

### ADR
Create **ADR-109** (provisional ordinal — re-verify at ship): *"Workstream issue writes:
close-not-delete + label-driven status + audited App-token write seam."* Records: (1) Close/reopen
is the delete verb (no GraphQL `deleteIssue`); (2) status persists via issue labels — canonical for
a user's own repo, with the org Project board as an eventual mirror (grant-gated, dogfood-only);
(3) all writes route through the audited `createGitHubAppClient` seam, per-workspace-resolved, never
request-input owner/repo. This is an authored deliverable of THIS plan, not a follow-up.

### C4 views
All actors/systems already modeled — enumeration checked against all three `.c4` files:
- **External human actor:** the founder (`founder` in `model.c4`) — already modeled; no new actor.
- **External system:** GitHub (`github` system) — already modeled. Concierge draft uses the in-repo
  agent (`claude -> github` git ops modeled); issue writes are `api -> github` REST.
- **Data store:** `audit_github_token_use` — already exists (Art. 30 PA-16); no new store.
- **Access relationship (CHANGES):** `model.c4:368` `api -> github` currently reads *"reads
  connected-repo issues (REST) + Project v2 board Status (GraphQL)"* — this edge becomes read**+write**
  (create/update/close via REST). Amend its description accordingly.
- **NEW audit-write edge (arch review P2 — coupled to the audited-seam decision).** Because writes route
  through `createGitHubAppClient` (which the read path did NOT use), they establish an `api -> supabase`
  (or `api -> <db container>`) **`audit_github_token_use` write** edge that does not exist today. Confirm
  against the model whether this edge is already present (from another audited caller); if not, add it
  (`#external`-scoped as appropriate). This is the one place "no new edge" was wrong — resolve the audit
  decision (P1) first, which we did (audited seam), so this edge is in scope.
- Run `bash scripts/regenerate-c4-model.sh` + commit `model.likec4.json`; validate via
  `c4-code-syntax.test.ts` + `c4-render.test.ts`.

### Sequencing
The ADR describes the target state now (`status: accepted`); the org-board GraphQL mirror for
intermediate columns is noted as grant-gated future work, not a blocker for v1 (labels are canonical
for a user's own repo).

## Implementation Phases

### Phase 0 — Preconditions (no code)
- Confirm `createGitHubAppClient` / `createIssue` token seam + `INITIATED_BY_MARKER` contract
  (`lib/workstream.ts:389`). Confirm `resolveGithubLogin(userId)` exists for server-side
  `initiatorLogin` (grep; if absent, thread from session — never request body).
- Confirm the status-label taxonomy in `deriveColumn` is the write target set.

### Phase 1 — Server write helpers (audited seam)
**All writes route through `createGitHubAppClient(installationId, founderId).rest.issues.*`** (`github/app-client.ts:80`) — the ONLY seam that writes the `audit_github_token_use` row (Art. 30 PA-16). Do NOT add naked `github-app.ts` helpers on `generateInstallationToken()` (that path is unaudited — the arch review's P1 catch). Thread `founderId` (session user id, as `undo/route.ts:175` + `agent-on-spawn-requested.ts:762` do) through `mutateWorkstreamIssue`.
- `updateIssue(number, { title?, body? })` → `rest.issues.update`.
- **`setIssueStatus(number, targetColumn, state_reason?)` — ONE primitive** (advisor #1). No remove-then-add delta (a remove-2xx-then-add-fail leaves a wrong `backlog` the rollback can't see). Instead:
  - Non-terminal columns → **read-modify-write**: `GET` current labels, then `rest.issues.setLabels` with the full computed set `(currentLabels − ALL status labels) + targetStatusLabel` in one atomic PUT (non-status labels survive; GitHub auto-creates a missing label). `backlog` = set minus all status labels. NB: "atomic" is the PUT only — the surrounding RMW has a TOCTOU last-write-wins window (accepted at single-user threshold, P1-4); it eliminates the half-fail, not the race.
  - `done` spans TWO fields → orchestrate `rest.issues.update state=closed, state_reason` here; reopen → `state=open`. This one primitive owns the state+label orchestration; `setIssueState` is folded in (simplicity #1 — nothing else called it).
  - Returns the **canonical resulting `WorkstreamIssue`** (re-derive from GitHub's response) so the client reconciles from stored truth, not a bare 2xx.
- **Single-source the status-label vocabulary (arch review P1).** The "ALL status labels" removal set MUST exactly equal `deriveColumn`'s read set (`blocked, pending, in-progress, review, needs-review, ready, todo`) + one canonical write-label-per-column — export both from `lib/workstream.ts` next to `deriveColumn` (mirroring the `INITIATED_BY_MARKER` single-source pattern) so read-derive and write can't drift. AC8 round-trip covers it.
- Create → `rest.issues.create`, stamping `appendInitiatorMarker(body, initiatorLogin)` (ADR-104); `initiatorLogin`/`founderId` from `resolveGithubLogin(userId)` / session (`server/github-login.ts:41` — both exist; Phase 0 hedge moot).
- All helpers throw on non-2xx (route → 502).

### Phase 2 — API routes (session-gated, per-workspace)
- `POST /api/workstream/issues` — body `{ title, body?, status? }`; resolve owner/repo/installation
  from the active workspace (ADR-044, mirror `getWorkstreamIssues`), resolve `initiatorLogin` server-side,
  call `createIssue`. Returns the created `WorkstreamIssue` (real number). Per-user rate-limit.
- `PATCH /api/workstream/issues/[number]` — body `{ title?, status?, state_reason? }`; same
  resolution; a `status` value dispatches to the ONE `setIssueStatus` primitive (server orchestrates
  state+labels — the client never sends separate label/state calls). Returns the **canonical resulting
  `WorkstreamIssue`** so the client reconciles from stored truth. 502-on-failure, mirror to Sentry.
  Never accept owner/repo from the request.
- Shared server helper `mutateWorkstreamIssue()` so the route AND the MCP tools call one accessor
  (mirror the `getWorkstreamIssues` "single shared fn" seam); it returns the canonical issue.

### Phase 3 — Agent parity: MCP write tools (`workstream-tools.ts`)
- `workstream_issue_create` (title, body?, status?) and `workstream_issue_set_status` (id, targetColumn),
  plus `workstream_issue_update_title` and `workstream_issue_close` (id, reason) / reopen. Each validates +
  delegates to `mutateWorkstreamIssue` (no `gh` shell-out). Register tier `gated` in `tool-tiers.ts`
  (precedent: `create_issue` = gated). Update the file-header "deferred" note (now shipped).

### Phase 4 — Create UI (`new-issue-dialog.tsx`, `workstream-board.tsx`)
- Manual quick-add → `POST`; on success replace the optimistic card with the returned issue (real number)
  + `mutate` the SWR list key; on failure roll back + inline retry (frames 08–10). Remove the "resets on
  reload" note.
- **Idempotency + submit-disable (spec-flow P0-3):** disable the Create button while a create is in flight
  and carry a client idempotency guard so a double-click / slow-network double-fire cannot create two real
  issues. Empty/whitespace title blocked client-side + server 422 (P1-7).
- Enable "Create with Concierge" (append `CONCIERGE_ONLINE` wiring): describe → **drafting…** (frame 12) →
  draft-preview/confirm/edit (frame 13) → `POST`. Nothing created before confirm. Cover the draft-phase
  states (spec-flow P1-1): draft-call failure → inline error + retry (no dead-end); cancel mid-draft →
  stop the draft (no orphan agent cost); user edits then create fails → **edits preserved** for retry.
  For v1 Concierge drafts **title + body only** (drop label drafting — labels are a Non-Goal, and drafting
  a *status* label would collide with the Backlog default; spec-flow P2-4).

### Phase 5 — Update/Close UI (`issue-detail-sheet.tsx`, `workstream-board.tsx`)
- Inline title edit → `PATCH {title}` (frames 14–16); persisted status control + drag-to-column →
  `PATCH {status}` reconciling from the **returned canonical issue** (frame 17); close-reason menu + reopen
  → `PATCH {status:"done"|prev, state_reason}` (frames 18–19). Optimistic commit only after the returned
  issue confirms the stored column; rollback + retry on failure.
- **Close / reopen taxonomy — single coherent state machine (spec-flow P0-4; corrects the spec).** The real
  board model has **NO Cancelled column** (`lib/workstream.ts:16` — all closed issues fold to `done`). So:
  the close-reason (Completed / Not planned) is recorded on GitHub (`state_reason`) and shown in the drawer,
  but BOTH reasons land the card in **Done**. Drag-to-Done = close; a drag gesture carries no reason menu, so
  it defaults `state_reason=completed` (the explicit "Close issue" menu is where the user picks Completed vs
  Not planned). **Drag OUT of Done, or Reopen, must `PATCH state=open`** (not merely relabel — a closed card
  is closed; removing labels leaves it in Done on reload). A reopened card lands in the column its surviving
  labels derive (else Backlog; spec-flow P2-3). Closing an already-closed issue from a stale sheet must not
  silently overwrite `state_reason` (P2-5). ⚠️ Spec FR5 "Not planned → Cancelled" is corrected to "→ Done
  (reason recorded)".
- **Conditional "Syncing to Project board…" (spec-flow P1-8).** Frame 17's syncing note renders ONLY for the
  org-board case (`owner === SOLEUR_KANBAN_ORG`). A user's own repo has no Project board — showing "syncing
  to a Project board" there is technically false; suppress it.
- **Read-only-install pre-check (spec-flow P1-2).** For an install with only `issues:read`, disable the write
  affordances (New Issue, drag, close) with a "read-only access" hint rather than letting every write
  dead-end into a 403 retry loop (`hr-verify-repo-capability-claim-before-assert`).
- **Retry surface for non-dialog flows (spec-flow P1-3):** a drag/inline-edit/close failure surfaces a
  persistent board-level toast (or re-opens the sheet) with retry — never a bare snap-back.
- **429 rate-limit → distinct "slow down" state (spec-flow P1-6)**, not a generic retryable error that
  immediately re-trips.
- **Drag-disable on board-precedence repos while the org grant is absent (advisor #2 + arch review P0 — the gating single-user incident).**
  For `owner === SOLEUR_KANBAN_ORG` (jikig-ai dogfood), board Status wins over labels on read. A status-label
  write DOES fire `board-status-sync.yml` (`issues: [labeled]`), but that workflow needs
  `organization_projects:write` — **still pending** — so it 403s FAIL-LOUD, the board Status stays unchanged,
  and the next read overrides the optimistic label → the card snaps back after a "successful" write. So gate
  intermediate-column drag **on the grant STATE**: drag-disabled while the grant is absent; it lifts
  automatically once granted (NOT "until a board-sync extension lands" — the label→board recompute already
  exists in `set-board-status.sh:108`). Close/reopen still work. For a user's OWN repo (board never read)
  drag is fully live. Degrade honestly.
- **Derivation skew risk (arch review P0, durable — survives the grant).** `deriveColumn` (app) ranks
  `in-progress > ready/todo`; `recompute_issue` (board) ranks `ready/todo > in-progress` and lets an open
  (draft) PR cross-reference override labels. So an issue with competing signals settles to a DIFFERENT board
  column than the app's optimistic label-derived column even after the grant. Mitigation: single-source the
  two precedence orderings, or document the accepted skew in ADR-109; add an AC asserting the two orderings
  agree (or the skew is explicitly listed).
- **SWR reconcile (ADR-067):** on success, `mutate` the board's SWR key with the returned canonical issue —
  do NOT rely on `router.refresh()` alone (it revalidates the RSC shell, not the SWR data cache), or a
  background revalidation races the user's next drag.

### Phase 6 — Write-integrity + tests + ADR/C4
- **Indeterminate-response resolution (spec-flow P0-1 — the core silent-lie/duplicate vector).** A request
  that neither cleanly 2xx's nor cleanly fails (dropped ack, 504, nav-abort) must NOT roll back blindly:
  reconcile by RE-READING GitHub before declaring success or failure. For create, the server dedups on the
  in-flight idempotency guard (Phase 4) + the `initiatorLogin` marker so a lost-ack create is not duplicated
  on retry; for update/status/close, re-read the issue and reconcile the card to stored truth.
- SWR: distinct list vs per-issue keys; `mutate(list)` with the returned canonical issue on success. Gate
  chained effects on server-ack, never the optimistic flag.
- Author ADR-109; amend `model.c4:368` (`api -> github` read+write) + confirm/add the `api -> supabase`
  `audit_github_token_use` write edge; regenerate `model.likec4.json`.
- Tests: accessor unit (label-set computation, marker stamp, canonical-issue return, **audit-row written**),
  status write-set ≡ read-set (single-source), route (auth, 502, anti-spoof initiatorLogin, no request
  owner/repo), MCP tool passthrough, UI optimistic/rollback + no-snap-back, `deriveColumn` round-trip,
  reopen-leaves-Done, create-retry-no-dupe.

## Files to Edit
- `apps/web-platform/lib/workstream.ts` — export the single-sourced status-label vocabulary (read set + canonical write-label-per-column) next to `deriveColumn`.
- `apps/web-platform/app/api/workstream/issues/route.ts` — add `POST`.
- `apps/web-platform/server/workstream/workstream-tools.ts` — add write tools; update header note.
- `apps/web-platform/server/tool-tiers.ts` — register new tool tiers.
- `apps/web-platform/components/workstream/new-issue-dialog.tsx` — real create + Concierge draft.
- `apps/web-platform/components/workstream/issue-detail-sheet.tsx` — inline title, status, close/reopen.
- `apps/web-platform/components/workstream/workstream-board.tsx` — persisted mutate handlers + reconcile.
- `apps/web-platform/lib/swr-keys.ts` (or equivalent) — per-issue mutation key if needed.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — amend `api -> github` edge.
- `knowledge-base/engineering/architecture/diagrams/model.likec4.json` — regenerated.

## Files to Create
- `apps/web-platform/app/api/workstream/issues/[number]/route.ts` — `PATCH`.
- `apps/web-platform/server/workstream/mutate-workstream-issue.ts` — shared write accessor; threads `founderId`; routes ALL writes (create/update/status/close) through the audited `createGitHubAppClient(installationId, founderId).rest.issues.*`; owns the atomic `setIssueStatus` state+label orchestration; stamps the initiator marker on create.
- `knowledge-base/engineering/architecture/decisions/ADR-109-workstream-issue-writes.md`.
- Tests under `apps/web-platform/test/…` (accessor unit, route, tool, component — verify vitest `include:` globs).

(Note: `github-app.ts` needs NO new helpers — writes route through the audited App client in the new accessor, not naked `generateInstallationToken()` helpers.)

## Open Code-Review Overlap
Only #2246 (`refactor(kb): low-severity polish from PR #2235 review`) mentioned `github-app.ts` — and after
the audited-seam revision this plan no longer edits `github-app.ts` at all, so there is **no overlap**.
**Acknowledge**; #2246 remains open (different concern).

## Observability

```yaml
liveness_signal:
  what: "workstream write success log (op=workstream-issue-write, verb=create|update|status|close) per mutation"
  cadence: per-request
  alert_target: none (cosmetic volume; parity with get-workstream-issues board-read log)
  configured_in: apps/web-platform/server/workstream/mutate-workstream-issue.ts
error_reporting:
  destination: Sentry via reportSilentFallback / route 502
  fail_loud: true (write failure THROWS → route 502 + isError tool; never masquerades as success)
failure_modes:
  - mode: "installation lacks issues:write (collaborator/user install → 403)"
    detection: "GitHubApiError 403 mirrored to Sentry op=workstream-write-403"
    alert_route: Sentry issue alert (new)
  - mode: "optimistic UI commit without GitHub confirmation"
    detection: "UI reconcile step asserts 2xx before commit; failed writes emit op=workstream-write-rollback"
    alert_route: Sentry
  - mode: "initiatorLogin spoof attempt (request body carries a login)"
    detection: "route ignores body login; server-resolved only — no detection needed, tested"
    alert_route: n/a (structurally prevented)
logs:
  where: pino structured (server) + Sentry
  retention: per existing web-platform config
discoverability_test:
  command: "gh api repos/{owner}/{repo}/issues -X POST via the route in dev, then assert the issue exists (NO ssh)"
  expected_output: "created issue number returned; audit_github_token_use row written"
```

## Acceptance Criteria

### Pre-merge (PR)
- AC1 — `POST /api/workstream/issues` creates a real GitHub issue on the active workspace repo; response carries the real number; card survives reload (no local-only state).
- AC2 — `PATCH …/[number]` persists title and status via the ONE `setIssueStatus` primitive (atomic `setLabels` PUT of the full computed set; state+labels orchestrated server-side for done/reopen); returns the canonical resulting issue; the client reconciles from it, not a bare 2xx. Test the remove-then-add-can't-half-fail invariant.
- AC3 — All writes go through `createGitHubAppClient(installationId, founderId)` and write an `audit_github_token_use` row (Art. 30 PA-16); a naked `generateInstallationToken()` write path is absent (test asserts the audit row on a write).
- AC4 — Every create stamps `<!-- soleur:initiated-by <login> -->` with a **server-resolved** login; a login supplied in the request body is ignored (test asserts anti-spoof).
- AC5 — owner/repo/installation resolve ONLY from the active workspace; no route/tool accepts request-input owner/repo (test).
- AC6 — MCP tools `workstream_issue_create` / `_set_status` / `_update_title` / `_close` exist, tier `gated` in `tool-tiers.ts`, delegate to `mutateWorkstreamIssue` (no `gh` shell-out); `workstream-tools.ts` header no longer says "deferred". Closes #5677.
- AC7 — Success reconciles via `mutate(list)` with the returned canonical issue (ADR-067 — SWR data cache, not `router.refresh()` alone), so a successful status write does not snap back on the next render; failure rolls back + surfaces a retryable error (test both).
- AC8 — Indeterminate response (dropped ack / 504) reconciles by re-reading GitHub before declaring success/failure; a lost-ack create does not duplicate on retry (idempotency guard + marker). Test the create-retry-no-dupe path.
- AC9 — Create button is submit-disabled while in flight; empty/whitespace title is blocked client-side and 422'd server-side (test).
- AC10 — Close/reopen state machine: drag-to-Done closes (`state_reason=completed`); the close menu records Completed/Not planned (both → Done column, reason shown in drawer, **no Cancelled column**); drag-out-of-Done / reopen `PATCH state=open` and the card leaves Done (test reopen leaves Done).
- AC11 — Board-precedence repos (`owner === SOLEUR_KANBAN_ORG`) render intermediate columns drag-disabled **while `organization_projects:write` is ungranted** (gated on grant state, not a trigger gap); a user's own repo is fully draggable (test both branches). Close/reopen work in both. (AC1 "survives reload" + AC13 round-trip are asserted for the org repo only on create/title/close, which mirror — intermediate status is drag-disabled, so no confirmed-write-then-revert.)
- AC12 — The status-label removal vocabulary is **single-sourced** with `deriveColumn`'s read set (exported from `lib/workstream.ts`); a test asserts write-set ≡ read-set (no alias drift). The app-`deriveColumn` vs board-`recompute_issue` precedence skew (`in-progress`↔`ready/todo`, open-PR override) is either reconciled or explicitly documented in ADR-109 (test/asserts the two orderings, or lists the accepted skew).
- AC13 — `deriveColumn` round-trip: writing a target column's label yields that column on the next read (unit test over the taxonomy).
- AC14 — Read-only install (`issues:read` only) disables write affordances with a hint (no 403 retry loop); "Syncing to Project board…" renders only for the org-board repo (test both).
- AC15 — Write endpoints carry a per-user throttle to protect against GitHub **secondary** rate limits and a runaway-MCP-agent write loop (NOT duplicate-create — that's AC8/AC9); a 429 surfaces a distinct "slow down" state, not a generic retry (test).
- AC16 — ADR-109 authored; `model.c4` `api -> github` edge amended to read+write + the `api -> supabase` `audit_github_token_use` write edge confirmed/added; `model.likec4.json` regenerated; `c4-code-syntax.test.ts` + `c4-render.test.ts` green.
- AC17 — Typecheck (`cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`) + full test suite green.

### Post-merge (operator)
- None. (No infra/secret/migration; `GITHUB_APP_*` already provisioned; container restart is automatic on merge via `web-platform-release.yml`.)

## Domain Review

**Domains relevant:** Product, Engineering (carry-forward from brainstorm `## Domain Assessments`).

### Engineering (CTO)
**Status:** reviewed (brainstorm carry-forward). **Assessment:** Writes not greenfield; org install already grants `issues:write`; close-not-delete preserves the number-keyed board; status via labels sidesteps the pending `organization_projects:write` grant; every UI write must land as a sibling gated MCP tool. ADR-worthy — captured as ADR-109.

### Product/UX Gate
**Tier:** blocking
**Decision:** reviewed (wireframes produced + operator-approved in brainstorm Phase 3.55/3.55b)
**Agents invoked:** ux-design-lead (brainstorm), cpo (brainstorm), spec-flow-analyzer (this plan)
**Skipped specialists:** none
**Pencil available:** yes (`workstream-issue-crud.pen`, frames 08–20, committed + approved)

#### Findings
CPO: build Create + Update, drop true Delete; Create Concierge-first + manual fallback; write-integrity (confirm-before-commit) is non-negotiable at single-user threshold. Wireframes cover create success/error, Concierge draft-confirm, inline-title save/rollback, async board-sync, close/reopen, and the optimistic→confirmed→failed lifecycle.

## Risks & Mitigations / Sharp Edges

- **Board-Status-wins (dogfood only).** For the jikig-ai org repo, board GraphQL Status wins over labels, and `board-status-sync.yml` doesn't listen to `labeled` — so an intermediate column move on an on-board issue may not reflect until the org grant + a board-sync extension land. For a **user's own repo the board is never read**, so labels are canonical and the write is immediately live. Mitigation: the "Syncing to Project board…" UI state (frame 17) is honest; the gap is tracked and dogfood-scoped, not user-facing.
- **initiatorLogin spoof.** Never source from request body — resolve from session (`resolveGithubLogin(userId)`); test the anti-spoof path (AC3).
- **Optimistic silent-lie.** Commit only on 2xx; rollback + retry on failure; `router.refresh()` success-only (learning: `2026-05-19-optimistic-local-state-and-server-prop-conjunction-needs-router-refresh.md`).
- **Collaborator/user install = `issues:read` only.** Writes 403 on such installs — surface honestly, don't swallow (learning: `2026-05-07-github-app-user-installation-cannot-post-user-repos.md`).
- **Vitest discovery.** Place tests where `apps/web-platform/vitest.config.ts` `include:` globs collect them (`test/**`, not co-located); typecheck via in-package `tsc`, not `npm run -w`.
- **User-Brand Impact empty-section gate:** a plan whose `## User-Brand Impact` is empty/placeholder fails deepen-plan Phase 4.6 — this one is filled.
- **ADR ordinal is provisional** (ADR-109) — re-verify next-free against `origin/main` at ship; sweep plan+tasks+ACs if renumbered.

## Spec-Flow Reconciliation (P0/P1 folded)
P0-1 indeterminate reconcile → Phase 6 + AC13. P0-2 org-repo snap-back → drag-disable (AC11/AC16). P0-3
create idempotency/submit-disable → Phase 4 + AC14. P0-4 Done/Cancelled/reopen taxonomy → Phase 5 (no
Cancelled column; corrects spec FR5) + AC15. P1-1 Concierge draft states → Phase 4. P1-2 read-only disable
+ P1-8 conditional syncing → Phase 5 + AC17. P1-3 retry surface, P1-6 429 state, P1-7 title validation →
Phase 4/5. **Acknowledged as v1 limits (not folded):** P1-4 optimistic concurrency — last-write-wins is
acceptable at single-user threshold (one operator + their agent); P1-5 agent-write→open-board staleness —
no realtime push in v1; the board reflects agent writes on next load/SWR revalidation. Both tracked for a
realtime/conflict follow-up.

## Deferred (tracked)
- True issue delete, label/assignee/milestone/body editing, comments → follow-up (Non-Goals).
- Org-board GraphQL Status mirror for intermediate columns → gated on `organization_projects:write` (feat-kanban-board-workstream-sync).
- Optimistic concurrency (If-Match/ETag) + realtime agent-write board push → follow-up (spec-flow P1-4/P1-5).
