---
feature: attachments-rls-bundle-pr2-4318
plan: knowledge-base/project/plans/2026-05-25-feat-attachments-workspace-shared-pr2-plan.md
spec: knowledge-base/project/specs/feat-attachments-rls-bundle-pr2-4318/spec.md
issue: "#4318"
pr: "#4417 (draft)"
brand_survival_threshold: single-user incident
lane: cross-domain
requires_cpo_signoff: true
status: ready-for-work
---

# Tasks — PR-2 attachments workspace-shared

Hierarchical task breakdown derived from the plan. Phase numbers match plan headings.

## Phase 0 — Preconditions

- **0.1** Verify worktree state and `vitest` availability
  - 0.1.1 `git rev-parse --abbrev-ref HEAD` returns `feat-attachments-rls-bundle-pr2-4318`
  - 0.1.2 `bun install` clean; `vitest --version` resolves
- **0.2** Resolve brainstorm Open Questions (OQ1–OQ5)
  - 0.2.1 OQ1: prd `chat-attachments` object count via Supabase MCP — record in worklog
  - 0.2.2 OQ2: confirm "JWT claim not needed" (plan-design resolution)
  - 0.2.3 OQ3: file `compliance/blocker` issue for workspace-deletion orphan; link to PR-2 body AND Flagsmith flag description
  - 0.2.4 OQ4: CLO sign-off on DSAR co-uploader byte-redaction (manifest 1.2.0 forward-compat)
  - 0.2.5 OQ5: orphan-path query pinned (already in plan)
- **0.2b** Critical data-integrity probes
  - 0.2b.1 PROBE-A: `SELECT COUNT(*) FROM messages WHERE workspace_id IS NULL` returns 0 on prd
  - 0.2b.2 PROBE-B: segment-2 conversation-id-shape audit returns 0 on prd
  - 0.2b.3 PROBE-C: no slot collision at `068_*.sql`
  - 0.2b.4 PROBE-D: grep `messages` WORM trigger; document carve-out if found
- **0.3** R-9 spike — apply DRAFT mig 068 locally; prove SECURITY DEFINER helper resolves from storage policy context (abort/inline-fallback if not)
- **0.4** Verify `messages.user_id` column type (uuid vs text) to validate pseudonym cast in the cascade RPC
- **0.5** `storage.foldername` edge-case spike (empty, single-segment, `..`, multi-segment) — record exact behaviour
- **0.6** CPO sign-off captured on Reconciliation R-1/R-3/R-5 + OQ#3 deferral

## Phase 2 — Migration 068 (storage RLS predicate widening + policy split)

- **2.1** Author `apps/web-platform/supabase/migrations/068_attachments_workspace_shared.sql`
  - 2.1.1 `BEGIN; ... COMMIT;` boundaries
  - 2.1.2 `LAWFUL_BASIS` SQL preamble comment
  - 2.1.3 `is_attachment_path_workspace_member(p_conversation_id, p_user_id)` SECURITY DEFINER plpgsql; `search_path = public, pg_temp`
  - 2.1.4 REVOKE ALL FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE TO authenticated (helper)
  - 2.1.5 DROP `Users can write own attachment objects` (mig 045 FOR ALL policy)
  - 2.1.6 CREATE policy `Users read own + co-member attachment objects` FOR SELECT
  - 2.1.7 CREATE policy `Users write own attachment objects only` FOR INSERT (own-folder WITH CHECK)
  - 2.1.8 CREATE policies for UPDATE + DELETE (own-folder USING + WITH CHECK)
  - 2.1.9 COMMENT block citing `2026-04-18-rls-for-all-using-applies-to-writes.md`
- **2.2** Author `068_attachments_workspace_shared.down.sql` (restores mig 045 policy + mig 067 RPC + drops helper/RPCs)

## Phase 3 — API-layer co-membership widening

- **3.1** Edit `apps/web-platform/app/api/attachments/presign/route.ts:76-83` — inline conv lookup + `is_workspace_member` check; `reportSilentFallback` on cutover-deny; distinguished error codes
- **3.2** Edit `apps/web-platform/app/api/attachments/url/route.ts:14-30` — parse segments; inline conv lookup; same reportSilentFallback shape

## Phase 3.5 — Service-role surface inventory + assert

- **3.5.1** Run `rg -n "storage\.from\(['\"]chat-attachments['\"]\)" apps/web-platform/` — pin every callsite in worklog
- **3.5.2** Insert reader-may-access assertion at `apps/web-platform/server/attachment-pipeline.ts:149`
- **3.5.3** Document/insert byte-fetch assertion site at `apps/web-platform/server/agent-runner.ts:569`
- **3.5.4** Add pre-download seam re-assertion in `dsar-export.ts:1198+`

## Phase 4 — Cascade RPCs + amended `remove_workspace_member`

- **4.1** Add to mig 068 body: `_anonymise_authored_messages_internal(p_user_id, p_workspace_id)` private internal helper (with WORM carve-out per PROBE-D)
- **4.2** Add to mig 068 body: `public.anonymise_departed_user_across_workspaces(p_user_id)` public RPC; GRANT EXECUTE TO service_role
- **4.3** Add to mig 068 body: re-CREATE `public.remove_workspace_member(p_workspace_id, p_user_id)` with the internal helper call inserted BEFORE the workspace_members DELETE; verbatim reproduction of mig 067:117-203 elsewhere
- **4.4** Edit `apps/web-platform/server/account-delete.ts` — insert step **3.901** between 3.90 and 3.905; call `anonymise_departed_user_across_workspaces`; runtime ordering guard (workspace_members count > 0)
- **4.5** Update JSDoc on `apps/web-platform/server/workspace-membership.ts:238` documenting that the cascade now lives inside `remove_workspace_member`

## Phase 5 — Storage list widening

- **5.1** Edit `account-delete.ts:160-193` Storage list — enumerate via `message_attachments` ⨝ `conversations.user_id = departing_user`; retain shared-workspace objects (Art. 17 carve-out)
- **5.2** Edit `dsar-export.ts:1193-1253` `enumerateChatAttachments` — workspace-scoped enumeration
- **5.3** Bump DSAR manifest schema 1.1.0 → 1.2.0 with forward-compat invariant documented in comment; add `redacted` + `redaction_reason` + `uploader_pseudonym` fields for co-uploader entries
- **5.4** Add pre-download seam re-assertion (architecture P1-5)

## Phase 6 — Tests + migration-shape lint

- **6.1** Create `apps/web-platform/test/supabase-migrations/068-attachments-workspace-shared.test.ts` — adopt structure from `067-workspace-member-revocation-lookup.test.ts`; assert AC1(a)-(g)
- **6.2** Extend `attachment-pipeline.tenant-isolation.test.ts` with: workspace co-member positive control; cross-workspace dual-shape deny; NULL-foldername deny; corrupt-UUID fail-closed
- **6.3** Extend `account-delete.integration.test.ts` with `describe("attachment cascade", ...)` — AC5(a)-(e)
- **6.4** Extend `workspace-membership.integration.test.ts` with cascade-on-removal describe block — AC6
- **6.5** All fixtures use `crypto.randomUUID()`; sentinel-grep `__[A-Za-z]+__` returns 0 in new files

## Phase 6.5 — Article 30 PA-2 amendment (moved here from Phase 1)

- **6.5.1** Edit `knowledge-base/legal/article-30-register.md` PA-2: §(c) + §(d) + §(g)(10) + new §(g) TOM
- **6.5.2** Lockstep edit `docs/legal/data-protection-disclosure.md`
- **6.5.3** Re-publish Eleventy mirror `plugins/soleur/docs/pages/legal/*`; diff-clean check
- **6.5.4** PA-2-vs-mig-068-body grep validation (AC10)

## Phase 7 — Ack-gated apply

- **7.1** Single PR; squash-merge (PR body uses `Ref #4318`, not `Closes`)
- **7.2** Auto-apply to dev via `web-platform-release.yml#migrate` on push to main
- **7.3** Ack-gated prd apply per `hr-menu-option-ack-not-prod-write-auth` with full SQL text in ack prompt
- **7.4** Post-apply: OQ5 orphan audit + PROBE-A + PROBE-B return 0 on prd
- **7.5** `gh issue close 4318` with the AC17 comment after AC16 passes
- **7.6** UX uploader-attribution follow-up filed; OQ#3 follow-up filed (label `compliance/blocker`); ADR-051 candidate filed (P3); rls-cascade-to-direct skill candidate filed (P3)

## Cross-cutting

- **X.1** 5-agent `/soleur:review` panel pre-merge (DHH + Kieran + code-simplicity + architecture-strategist + `user-impact-reviewer` + `spec-flow-analyzer`)
- **X.2** `/soleur:gdpr-gate` re-run on final diff (advisory clean)
- **X.3** CCPA "sharing" disclosure CLO check (AC18) — does NOT block PR-2 merge but blocks flag flip if gap found
