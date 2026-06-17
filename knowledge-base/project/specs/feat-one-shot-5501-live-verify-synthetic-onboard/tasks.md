---
title: "Tasks — fix(live-verify): seed user_session_state.current_workspace_id for the synthetic principal"
issue: "#5501"
branch: feat-one-shot-5501-live-verify-synthetic-onboard
lane: single-domain
plan: knowledge-base/project/plans/2026-06-17-fix-live-verify-synthetic-onboard-workspace-binding-plan.md
---

# Tasks: onboard the synthetic principal's active-workspace binding

Derived from `2026-06-17-fix-live-verify-synthetic-onboard-workspace-binding-plan.md`.
Root cause: the synthetic principal has no `user_session_state` row, so the deployed
`createConversation` fail-loud workspace resolver throws and no conversation persists →
harness emits `CANT-RUN:forURL`.

## Phase 1 — Seed the active-workspace binding (TDD)

- [x] 1.1 (RED) Add static-grep assertions to
  `apps/web-platform/scripts/seed-live-verify-user.test.sh`:
  - [x] 1.1.1 seed body contains `/rest/v1/user_session_state` upsert call
  - [x] 1.1.2 body writes `current_workspace_id` AND `current_organization_id`
  - [x] 1.1.3 body uses `resolution=merge-duplicates` (POST-upsert, not no-op PATCH)
  - [x] 1.1.4 upsert line number > `workspace_members` owner-lookup line number (write order)
  - [x] 1.1.5 run the test → confirm it FAILS against the current seed; capture the red
- [x] 1.2 (GREEN) Edit `apps/web-platform/scripts/seed-live-verify-user.sh`, after the
  `workspaces` PATCH (`:200-205`) and before the `api_keys` block (`:210`):
  - [x] 1.2.1 `GET /rest/v1/workspaces?id=eq.$workspace_id&select=organization_id` → `org_id`
  - [x] 1.2.2 fail closed (`::error::` + `exit 1`) when `org_id` is empty
  - [x] 1.2.3 `POST /rest/v1/user_session_state?on_conflict=user_id` with
    `Prefer: resolution=merge-duplicates,return=minimal` and a jq body of
    `{user_id, current_workspace_id, current_organization_id, updated_at}`
  - [x] 1.2.4 update the header-comment provisioned-state inventory (`:17-30`) to list the
    new `user_session_state` row
  - [x] 1.2.5 re-run the test → confirm PASS (AC5)
- [x] 1.3 (REFACTOR) match the sibling `curl … | jq` write style; no `set -x`; no echoed
  response body (AC6). One call site — no extraction.

## Phase 2 — ADR-064 amendment (in-PR deliverable)

- [x] 2.1 Append `### Amendment 2026-06-17 — seed must bind active workspace` to
  `knowledge-base/engineering/architecture/decisions/ADR-064-live-production-verification-harness.md`:
  - [x] 2.1.1 record the new `user_session_state` seed-table contract
  - [x] 2.1.2 cite the fail-loud resolver path (`ws-handler.ts:892` → `agent-session-registry.ts:316`)
  - [x] 2.1.3 record the RPC-needs-`auth.uid()` → seed-writes-table-directly rationale
  - [x] 2.1.4 Status stays Accepted (extension, not reversal); satisfies AC7

## Phase 3 — Verify (AC sweep)

- [x] 3.1 Run all Pre-merge ACs (AC1–AC9) — grep gates + `seed-live-verify-user.test.sh` exit 0
- [x] 3.2 Confirm negative AC8: `grep -rlE 'seed-live-verify' .github/workflows/` returns nothing
- [x] 3.3 PR body uses `Ref #5501` (NOT `Closes`) per AC9

## Phase 4 — Post-merge live confirmation (de-risk #5463 item 4)

- [ ] 4.1 Re-seed prod locally (idempotent):
  `doppler run -p soleur -c prd -- bash apps/web-platform/scripts/seed-live-verify-user.sh`
- [ ] 4.2 Attempt the FULL harness path in-session; assert stdout `RESULT: PASS` (AC10).
  If in-session chromium cannot launch, read the #5488 report-only job's emitted `RESULT:`
  via `gh run view --log` on the next qualifying merge (NOT dashboard eyeballing).
  `automation-status: UNVERIFIED — attempt Playwright/harness before any handoff.`
- [ ] 4.3 On PASS, `gh issue close 5501` with a comment linking the PASS evidence (AC11)
