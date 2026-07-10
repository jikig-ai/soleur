---
feature: feat-workstream-issue-crud
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-07-10-feat-workstream-issue-crud-plan.md
---

# Tasks: Workstream Issue CRUD

## Phase 0 — Preconditions (no code)
- [x] 0.1 Confirm `createGitHubAppClient(installationId, founderId)` (`server/github/app-client.ts:80`) is the audited write seam; confirm `resolveGithubLogin(userId)` (`server/github-login.ts:41`) + session `founderId` threading pattern (`undo/route.ts:175`).
- [x] 0.2 Confirm `deriveColumn` status vocabulary + `INITIATED_BY_MARKER` contract (`lib/workstream.ts`).
- [x] 0.3 Confirm `board-status-sync.yml` `issues: [labeled,unlabeled]` trigger + `organization_projects:write` grant is still ungranted (drives AC11).

## Phase 1 — Shared write accessor (audited seam)
- [x] 1.1 Export single-sourced status-label vocabulary (read set + write-label-per-column) from `lib/workstream.ts` next to `deriveColumn`.
- [x] 1.2 Create `server/workstream/mutate-workstream-issue.ts`: routes create/update/status/close through `createGitHubAppClient(installationId, founderId).rest.issues.*`; per-workspace owner/repo/installation resolution (ADR-044); returns canonical `WorkstreamIssue`.
- [x] 1.3 `setIssueStatus(number, column, state_reason?)`: RMW label set (GET → `setLabels` full computed set); `done`→close, reopen→`state=open`; folds in close/reopen (no separate `setIssueState`).
- [x] 1.4 `create`: stamp `appendInitiatorMarker(body, initiatorLogin)` with server-resolved login; throw on non-2xx.

## Phase 2 — API routes (session-gated, per-workspace)
- [x] 2.1 `POST /api/workstream/issues` → `mutateWorkstreamIssue` create; returns canonical issue; per-user throttle; 422 on empty title.
- [x] 2.2 `POST /app/api/workstream/issues/[number]` → `PATCH` `{title?, status?, state_reason?}`; dispatch to accessor; 502 + Sentry on failure; never accept request owner/repo.

## Phase 3 — Agent parity: MCP write tools
- [x] 3.1 `workstream_issue_create` / `_set_status` / `_update_title` / `_close` in `workstream-tools.ts`, delegating to the accessor.
- [x] 3.2 Register tier `gated` in `tool-tiers.ts`; update the "deferred" header note (closes #5677).

## Phase 4 — Create UI
- [x] 4.1 Manual quick-add → `POST`; submit-disable + idempotency guard; replace optimistic card with returned issue + `mutate(list)`; inline error/retry; empty-title block. (frames 08–10)
- [ ] 4.2 Concierge draft: describe → drafting → confirm/edit → `POST`; cover draft-fail, cancel, edit-preservation; title+body only (no label drafting). (frames 11–13)

## Phase 5 — Update/Close UI
- [x] 5.1 Inline title edit → `PATCH {title}`; save/rollback/retry. (frames 14–16)
- [x] 5.2 Status control + drag → `PATCH {status}` reconciling from returned issue; drag-disable intermediate columns when `owner === SOLEUR_KANBAN_ORG` && grant ungranted; conditional "Syncing to Project board…". (frame 17)
- [x] 5.3 Close-reason menu (Completed/Not planned → Done) + reopen (`state=open` leaves Done). (frames 18–19)
- [x] 5.4 Read-only-install pre-check disables write affordances; 429 "slow down" state; board-level retry toast for non-dialog failures.

## Phase 6 — Write-integrity + ADR/C4 + tests
- [x] 6.1 Indeterminate-response reconcile (re-read GitHub); SWR list/per-issue keys; `mutate` on success (not `router.refresh()` alone).
- [x] 6.2 Author `ADR-109-workstream-issue-writes.md`; amend `model.c4:368` (read+write) + confirm/add `audit_github_token_use` write edge; `bash scripts/regenerate-c4-model.sh`; commit `model.likec4.json`.
- [x] 6.3 Tests: accessor (label-set, marker, canonical return, audit-row), write-set≡read-set, route (auth/502/anti-spoof/no-owner-repo), tool passthrough, UI optimistic/rollback/no-snap-back, deriveColumn round-trip, reopen-leaves-Done, create-retry-no-dupe. Verify vitest `include:` globs.
- [x] 6.4 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`; full suite green.

## Review (at PR)
- [ ] R.1 Run `agent-native-reviewer` (read/write parity) + `security-sentinel` (write-boundary, anti-spoof) per TR8.

## Implementation deviations (from plan)
- **4.2 Concierge draft — NOT shipped (deferred).** "Create with Concierge" stays gated behind the existing `CONCIERGE_ONLINE=false` flag (offline). Wiring the draft backend needs a one-shot draft endpoint that does not yet exist; the manual quick-add (FR1) is fully live and is the primary path. Going live is a one-flag flip + composer wiring (tracked follow-up), unchanged from the pre-existing gate.
- **"Drag-to-column" realized as the persisted status control (`<select>`), not HTML5 drag-and-drop.** The board never had a DnD system; the status control + Close/Reopen carry the identical `PATCH {status}` semantics (optimistic + reconcile + rollback, board-precedence disable). Literal drag is a follow-up affordance over the same write path.
- **5.4 read-only handling is REACTIVE, not a pre-check probe.** A first 403 flips the board read-only (disables New Issue / status / close, shows the honest hint) — this delivers AC14's "no 403 retry loop" without an extra installation-permissions probe on every load. A proactive permissions pre-check is a possible follow-up.
- **6.1 indeterminate-response reconcile.** Success reconciles from the returned canonical issue (mutate SWR key, not router.refresh — ADR-067); failure rolls back + retryable toast; create is single-flight + submit-disabled (no double-fire dupe). An explicit re-read-GitHub on a dropped-ack/504 and server-side lost-ack marker dedup are deferred (ADR-109 "Accepted skew / limits").
