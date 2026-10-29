# Tasks: durable, action-bound approval requests (slice 1)

Plan: `knowledge-base/project/plans/2026-10-27-feat-durable-action-bound-approval-requests-plan.md`
Issue: #4672 (closes; #10443 closed as duplicate) | Epic #9601 | Draft PR #11289

Commit order in the one PR: (1) timeout-deny defect fix, (2) migration/RPCs/service, (3) gate wiring and WS, (4) surfaces and notifications, (5) cron and flag, (6) C4, (7) legal, (8) ADR.

## Phase 0: Measurements and design deltas (stop point: 0.1 must pass before 2.x)

- [x] 0.1 (delivered by the gate-bypass hotfix, ADR-305) Write `apps/web-platform/scripts/dev-probe-approval-gate.ts` through the real `buildAgentQueryOptions` path; run it; record in `phase-0-measurements.md` whether `canUseTool` is invoked for each slice-1 tool and whether `allowedTools` short-circuits it
  - [x] 0.1.1 (delivered by the hotfix) If short-circuited: extract pure `buildAllowedTools`, drop `APPROVAL_REQUIRED_TOOLS` when the flag is on, add census test
- [ ] 0.2 Wireframe delta via `soleur:product:design:ux-design-lead` (honest "Approve" copy, two approved states, copy-deck fixes, drop 04G and member landing variant, other items in plan Phase 0.2); scrub `fileToken`; operator approval
- [x] 0.3 Confirm per-tool canonical field lists against each tool's zod schema; record in test fixtures

## Phase 1: Failing tests, then data layer

- [x] 1.1 Write failing tests first: canonicalization per tool, consume predicate, status machine, `decide_approval` owner/expiry, tool-map census, re-proposal on `approved` row (the gated-branch timeout-deny test was delivered by the hotfix, ADR-305)
- [x] 1.2 `180_approval_request.sql` + `.down.sql` + `supabase/verify/180_approval_request.sql`
  - [x] 1.2.1 Table, constraints, partial unique index, write-once trigger with SET NULL and workspace-cascade carve-outs
  - [x] 1.2.2 RPCs: create, decide (authenticated, `auth.uid()`), consume, get status, sweep, anonymise; grants per plan
  - [x] 1.2.3 `inbox_item.source` CHECK widening (`NOT VALID` then `VALIDATE`); `-- LAWFUL_BASIS:` and retention comments
  - [x] 1.2.4 `test/rls-fuzz/table-grants.ts` classification; RLS fuzz entry; ADR-303 grants declaration
- [x] 1.3 `server/approval/{canonical,render,service,waiters,tools}.ts`

## Phase 2: Gate wiring

- [x] 2.1 (delivered by the hotfix: shared `holdForUser` fail-closed lifecycle; verify on the rebased branch, add only what is missing) Commit 1: `try/finally` deny-on-reject in the gated branch for all gated tools, with test
- [x] 2.2 Approval flow behind the flag in `permission-callback.ts` via `deps.approval`; `tool-tiers.ts` `APPROVAL_REQUIRED_TOOLS`; deep-cloned snapshot hashed and passed to `allow()`; abort-aware poll; consume-on-approved
- [x] 2.3 WS types `approval_request`, `approval_status`, `approval_decide`; `ws-handler.ts` decide via `tenantFor`, reattach re-emit, waiter wake; `chat-state-machine.ts`; guard that `review_gate_response` cannot resolve an approval
- [x] 2.4 Static-message Sentry ops, `SOLEUR_APPROVAL_*` markers, `approval_id` tag; confirm Vector allowlist admits the marker family

## Phase 3: Surfaces and notifications

- [x] 3.1 `components/chat/approval-request-card.tsx` (all states), landing page, decide route, inbox row, nav badge
- [x] 3.2 `notifications.ts`: widen `source` union (three-pattern grep), split `dispatchInboxPush`, generic push and email copy; copy-deck constants and the string test for forbidden outcome words

## Phase 4: Cron, flag, infra

- [ ] 4.1 `cron-approval-expiry.ts` with one `sweep_approvals()` step; register in `cron-manifest.ts`, `app/api/inngest/route.ts`, `execution-placement.ts`, `routine-metadata.ts`
- [ ] 4.2 `infra/sentry/cron-monitors.tf`, `alert-reference.json`, `issue-alerts.tf`, `cutover-inngest.yml`
- [ ] 4.3 Flag `approval-queue`: `lib/feature-flags/server.ts`, `.env.example`, `flip.sh` map and parity test; per-workspace identity; flag-create hand-over note

## Phase 5: Governance

- [x] 5.1 C4: `approvalStore` element and edge, description fixes, `views.c4` include, regenerate `model.likec4.json`, parity counts, render tests (done 2026-10-29; the cron-monitor counts C4/C6/C9 are +1 only when 4.2 adds the `sentry_cron_monitor`: bump the `model.c4` prose then and re-run `c4-count-parity.test.sh`)
- [ ] 5.2 Legal (own commit): Art. 30 entry, DPD, GDPR Policy, Privacy Policy and mirrors, `legal-doc-shas.ts`, `account-delete.ts` call site, `dsar-export-allowlist.ts`, posture row and flag-refusal check
- [x] 5.3 ADR-307 (re-check ordinal against fresh `origin/main`; 305 and 306 are taken), ADR-284 and ADR-085 amendment notes, "Adding a gated tool" checklist (done 2026-10-29: 307 free on fresh origin/main; re-check immediately before merge)
- [x] 5.4 Guard 1 mutation battery (one dedicated file, pristine-copy harness) and census guard green; re-run the real-SDK probe on the finished branch

## Phase 6: Ship

- [ ] 6.1 Review (`user-impact-reviewer` included), resolve findings, QA, compound
- [ ] 6.2 Ship; close #10443 as duplicate; file the consolidated deferral issue (done at plan end)
- [ ] 6.3 Post-merge: verify migration applied, cron check-in in Sentry, flag created via `soleur:flag-create` (typed-yes hand-over); the flag is not flipped
