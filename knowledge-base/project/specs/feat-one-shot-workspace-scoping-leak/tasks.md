---
feature: feat-one-shot-workspace-scoping-leak
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-02-fix-workspace-scoping-leak-knowledge-drift-and-feature-audit-plan.md
status: ready
---

# Tasks: Workspace-scoping leak fix + feature scoping audit

Derived from the deepened plan. Implement with TDD (RED → GREEN) where noted.
Plan is the source of truth; this file is the executable breakdown.

## Phase 0 — Preconditions (verify, no edits)

- [x] 0.1 Confirmed `insert-draft-card.ts:66` solo-pin (`workspace_id = input.founderId`).
- [x] 0.2 Confirmed `today/route.ts` had no workspace filter (only `.eq("user_id")`).
- [x] 0.3 Confirmed `resolveCurrentWorkspaceId(userId, supabase)` signature (`workspace-resolver.ts:190`).
- [x] 0.4 Read kb-drift-ingest payload validator + walker — **CORRECTION:** the walker
      (`scripts/kb-drift-walker.sh`) scans Soleur's OWN repo KB (one global company KB), NOT a
      per-workspace KB. No `workspace_id` to thread. Plan D2 premise is false. See scoping-audit.md.
- [x] 0.5 Read-only prod probe (`DATABASE_URL_POOLER`, SELECT-only): 4 `kb-drift` draft cards,
      ALL pinned to the SOLO workspace (`52af49c2…` = founderId). Write is correct → no migration.
- [x] 0.6 Walker producer located (`.github/workflows/kb-drift-walker.yml`) — global-repo scan,
      no per-workspace concept (confirms 0.4).

## Phase 1 — Fix the read leak (active-workspace scoping) [TDD] — DONE

- [x] 1.1 RED: added two-workspace assertions to `test/server/dashboard/today-route.test.ts`
      (resolver mocked; asserts `.eq("workspace_id", activeWorkspaceId)`).
- [x] 1.2 GREEN: `today/route.ts` resolves `activeWorkspaceId = await resolveCurrentWorkspaceId(userId, supabase)`
      and adds `.eq("workspace_id", activeWorkspaceId)`.
- [x] 1.3 Updated the `today/route.ts` docblock with the active-workspace scoping invariant.
- [x] 1.4 Audited `today/[id]/{send,edit,discard,cancel,cost,undo}`: id+user_id+RLS scoping is
      sufficient (AC3) — rationale recorded in scoping-audit.md. No guard added (regression risk, zero gain).

## Phase 2 — Write attribution — DROPPED (false premise)

- [x] 2.x The walker scans Soleur's global company-repo KB; the card correctly belongs to the
      operator's solo workspace (prod probe: all 4 cards solo-pinned). No walker-threading, no
      `insertDraftCard` override, no `:208` change needed. The write was already correct.

## Phase 3 — Migration 093 — DROPPED (not needed)

- [x] 3.1 No re-attribution required — the 4 existing `kb-drift` cards correctly belong to solo.
      No migration. Rationale in PR body + scoping-audit.md.

## Phase 4 — Audit: conversations — DONE

- [x] 4.1 `dashboard/page.tsx` orphaned-count: documented as intentionally cross-workspace (fires
      only when active workspace has no repo; user's own non-sensitive count). Comment added.
- [x] 4.2 `conversations-tools.ts` list tool: HARDENED — added `.eq("workspace_id", activeWorkspaceId)`
      alongside `repo_url` to separate same-repo-two-workspace mixing (TDD; mig 059 workspace_id).
- [x] 4.3 Swept all `from("conversations")` sites: list/count reads classified (see scoping-audit.md);
      writes/DSAR/account-delete are user-scoped by design (GDPR export/delete must span all workspaces).

## Phase 5 — Audit: rate limiting + billing — DONE

- [x] 5.1 Rate limiting: KEEP per-user (coupled to per-user plan_tier; per-workspace would multiply
      paid capacity). Invariant comment added at `ws-handler.ts` start_session throttle site.
- [x] 5.2 Billing: correctly per-user by schema (one stripe_customer_id/user). Cross-workspace
      conversation count is correct for a per-user subscription retention nudge. Rationale comments
      added. Per-workspace/org billing NOT on roadmap (closest: CP5 #4670) → no tracking issue filed.

## Phase 6 — Verify

- [x] 6.1 Affected vitest suites green (RED→GREEN for read-scoping + conversations list).
- [ ] 6.2 `tsc --noEmit` clean for web-platform (run in Phase 6 below).
- [ ] 6.3 Optional Playwright: two-workspace owner, drift card on solo, switch to second, confirm absence.

## Post-merge (operator)

- [ ] PM.1 If migration 093 created: applied via `web-platform-release.yml#migrate` (runs on merge — no separate SSH apply). Verify via Supabase MCP read-only that `kb_drift` rows carry the correct `workspace_id`. Use `Ref #<issue>` in PR body; `gh issue close` after verification.

## Gate reminders

- GDPR gate (`/soleur:gdpr-gate`) — `messages` RLS + possible migration; run at review if not already.
- CPO sign-off required (single-user-incident threshold) before `/work`.
- `user-impact-reviewer` invoked at review-time.
- Place tests under `apps/web-platform/test/` (vitest `include:` skips co-located).
