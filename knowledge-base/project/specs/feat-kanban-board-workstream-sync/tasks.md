# Tasks — Kanban board ↔ Workstream tab sync

Plan: `knowledge-base/project/plans/2026-07-02-feat-kanban-board-workstream-sync-plan.md`
Branch: `feat-kanban-board-workstream-sync` · Lane: cross-domain

## Phase 0 — Align app column vocabulary (PR 1, no external dep)
- [ ] 0.1 `lib/workstream.ts`: `WorkstreamStatus` → `backlog|ready|in_progress|in_review|blocked|pending|done` (rename `todo`→`ready`, add `pending`, remove `cancelled`)
- [ ] 0.2 `lib/workstream.ts`: update `COLUMNS` (Todo→Ready, add Pending before Done, drop Cancelled), `statusPillClass`, `CLOSED_STATUSES` → `{done}`, `deriveColumn` (closed→done; add `pending` branch; `todo`→`ready`)
- [ ] 0.3 `server/workstream/workstream-tools.ts:44-45`: update the tool description string to the 7 new statuses (Kieran P1-4 — string literal `tsc` can't catch)
- [ ] 0.4 `components/workstream/issue-detail-sheet.tsx` + `workstream-board.tsx`: update any `WorkstreamStatus` reference / optimistic-move code
- [ ] 0.5 Cross-consumer sweep: `grep -rlnE 'WorkstreamStatus|CLOSED_STATUSES'` AND unquoted `grep -rnE 'backlog\|todo\||\|cancelled\)'`; EXCLUDE stripe/billing files
- [ ] 0.6 Update tests: `workstream-helpers`, `workstream-filters`, `components/workstream/issue-card`
- [ ] 0.7 `tsc --noEmit` clean; `vitest run` the workstream tests green

## Phase 1 — Board writer: lifecycle → Status automation (PR 2)
- [ ] 1.1 `scripts/board/set-board-status.sh`: `set-board-status <issue> <Status>` + `recompute <issue>` + `resolve-linked-issues <pr>` (`closingIssuesReferences` ∪ `Ref #N`); two-phase GraphQL (cache field/option ids), add-item-if-missing, mutate, **re-read + exit non-zero on mismatch**; sanitize node ids + `$GITHUB_OUTPUT`
- [ ] 1.2 `.github/workflows/board-status-sync.yml`: `issues:[reopened,labeled,unlabeled]` + `pull_request:[opened,reopened,ready_for_review,converted_to_draft,closed]`; minimal permissions; per-node concurrency; inline-JWT App-token mint (Doppler `prd_terraform` `GITHUB_APP_*`); fail-loud (no auto-issue); match `auto-label-security.yml` style
- [ ] 1.3 `scripts/board/set-board-status.test.sh`: mocked-`gh` fixtures for blocked add/remove, pending, reopened recompute, PR ready vs draft, PR closed-unmerged, `Ref #N` resolution
- [ ] 1.4 `actionlint` the workflow; `bash -n` the extracted script; assert no `GITHUB_TOKEN` on the mutation step

## Phase 2 — App reads the real board Status (PR 3)
- [ ] 2.1 Config: `SOLEUR_KANBAN_PROJECT_NUMBER` (=2) + `SOLEUR_KANBAN_ORG` (=jikig-ai) in `.env.example` + Doppler (NO migration)
- [ ] 2.2 `server/github-read-tools.ts`: bounded GraphQL board-Status read (Octokit `.graphql()`), return Status name for the configured project number
- [ ] 2.3 `server/workstream/get-workstream-issues.ts`: fetch board Status when configured; degrade to label derivation + `reportSilentFallback` on failure (never throw)
- [ ] 2.4 `lib/workstream.ts`: `BoardIssueInput.boardStatus?`; `deriveColumn` prefers board Status; add `boardStatusToWorkstreamStatus`
- [ ] 2.5 `components/workstream/workstream-board.tsx`: refresh-failure via `error && data`
- [ ] 2.6 `model.c4`: add `api -> github` edge; run `c4-code-syntax.test.ts` + `c4-render.test.ts`
- [ ] 2.7 Tests: board-prefers + fallback

## ADR / C4 (deliverable, lands with Phase 2)
- [ ] A.1 Create ADR-080 (re-confirm next free number; main max ADR-074) — board-canonical Decision + Alternatives (webhook-ingress deferred, app-labels rejected, PAT rejected)
- [ ] A.2 C4 `api -> github` edge + note Phase-1 write path is github-internal (no cross-boundary edge)

## Deferred — create tracking issues
- [ ] D.1 Per-workspace board column + accessor (multi-board)
- [ ] D.2 Skill auto-labeling (one-shot/fix/ship apply `blocked`/`pending`/`ready`)
- [ ] D.3 `ready`-column automation (plan-approved → Ready)
- [ ] D.4 `ci/board-sync-broken` auto-issue (if fail-loud proves insufficient)

## Operator (post-merge, consent-gated)
- [ ] O.1 Grant Soleur GitHub App `organization_projects: Read and write` + org approval; /work Playwright-attempts the request, operator approves; validate a live ProjectV2 mutation succeeds (not classic-Projects-only)
- [ ] O.2 Real-event smoke: close/blocked/draft-PR-`Ref #N` moves the issue card; `gh run list` success
