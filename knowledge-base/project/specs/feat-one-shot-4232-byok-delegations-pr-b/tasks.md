---
title: "BYOK Delegations PR-B — Tasks"
plan: knowledge-base/project/plans/2026-05-26-feat-byok-delegations-pr-b-ui-legal-plan.md
spec: knowledge-base/project/specs/feat-byok-delegations-4232/spec.md
issue: 4232
branch: feat-one-shot-4232-byok-delegations-pr-b
date: 2026-05-26
lane: cross-domain
brand_survival_threshold: single-user incident
estimate_days: "2-3"
---

# Tasks: BYOK Delegations PR-B (v1)

Derived from `2026-05-26-feat-byok-delegations-pr-b-ui-legal-plan.md` v1. 7 phases; TDD per phase (RED -> GREEN -> REFACTOR).

## Phase 0 — Preconditions

- [ ] 0.1 Worktree clean; branch is `feat-one-shot-4232-byok-delegations-pr-b`
- [ ] 0.2 PR-A (#4290) merged: `gh pr view 4290 --json state` = MERGED
- [ ] 0.3 Migration 064 applied in dev
- [ ] 0.4 Read existing components: team-membership-list.tsx, billing-section.tsx, chat/layout.tsx, ws-client.ts, ws-handler.ts
- [ ] 0.5 Read legal doc insertion points: AUP 5.5, DPD 2.3(v), side-letter-template, article-30-register PA-22
- [ ] 0.6 Verify `FLAG_BYOK_DELEGATIONS=0` in prd
- [ ] 0.7 Verify migration slot 074 is free
- [ ] 0.8 `bun run typecheck` exits 0; baseline test count
- [ ] 0.9 Read tc_acceptances_ledger pattern (mig 044)
- [ ] 0.10 Read byok-resolver.ts error hierarchy
- [ ] 0.11 Check roadmap for #4232 listing

## Phase 1 — Migration 074: byok_delegation_acceptances

- [ ] 1.1 RED: migration test skeleton
- [ ] 1.2 Create 074_byok_delegation_acceptances.sql: table + WORM trigger + RLS + index + anonymise RPC
- [ ] 1.3 Create down migration
- [ ] 1.4 GREEN: apply + down + re-apply passes
- [ ] 1.5 Update account-delete.ts: phase 5.95 anonymise_byok_delegation_acceptances
- [ ] 1.6 Update dsar-export-allowlist.ts: add acceptance table entry
- [ ] 1.7 `bun run typecheck` exits 0

## Phase 2 — API Routes + Server Resolvers

- [ ] 2.1 RED: resolver test skeleton
- [ ] 2.2 Create byok-delegation-ui-resolver.ts: resolveGrantorDelegations, resolveGranteeDelegation, resolveGranteeAcceptanceStatus
- [ ] 2.3 Create /api/workspace/delegations/route.ts: GET (list), POST (create), DELETE (revoke)
- [ ] 2.4 Create /api/workspace/delegations/accept/route.ts: POST (accept)
- [ ] 2.5 GREEN: resolver + route tests pass
- [ ] 2.6 `bun run typecheck` exits 0

## Phase 3 — UI Components

### 3.A — Team Settings: Member Row Delegation Toggle

- [ ] 3.1 RED: toggle test skeleton
- [ ] 3.2 Extend TeamMembershipRow type with delegation fields
- [ ] 3.3 Update resolveTeamMembershipPageData with delegation join (flag-gated)
- [ ] 3.4 Create delegation-toggle.tsx: toggle + cap input + revoke
- [ ] 3.5 Update team-membership-list.tsx: add Funded column + DelegationToggle
- [ ] 3.6 GREEN: toggle tests pass

### 3.B — Billing Settings: Funded Pane

- [ ] 3.7 RED: funded pane test skeleton
- [ ] 3.8 Create delegation-funded-pane.tsx: per-grantee table + revoke button
- [ ] 3.9 Update billing/page.tsx: mount DelegationFundedPane
- [ ] 3.10 GREEN: funded pane tests pass

### 3.C — Chat Layout: Grantee Banner

- [ ] 3.11 RED: banner test skeleton
- [ ] 3.12 Create delegation-banner.tsx: persistent banner with grantor name + spend/cap
- [ ] 3.13 Update chat/layout.tsx: mount DelegationBanner
- [ ] 3.14 GREEN: banner tests pass

### 3.D — Error Cards

- [ ] 3.15 RED: error card test skeleton
- [ ] 3.16 Extend ws-handler.ts: map ByokDelegationError to error codes
- [ ] 3.17 Extend ws-client.ts: handle delegation error codes
- [ ] 3.18 Create delegation-error-card.tsx: styled error with CTA
- [ ] 3.19 Update chat-surface.tsx: render DelegationErrorCard
- [ ] 3.20 GREEN: error card tests pass
- [ ] 3.21 `bun run typecheck` exits 0

## Phase 4 — Legal Documents

- [ ] 4.1 Create delegation-consent-side-letter-template.md
- [ ] 4.2 Edit DPD: add section 2.3(w)
- [ ] 4.3 Edit AUP: add section 5.6
- [ ] 4.4 Edit Article 30 register: add PA-23
- [ ] 4.5 Edit compliance-posture.md: add changelog entry
- [ ] 4.6 Edit side-letter-register.md: add delegation reference note

## Phase 5 — Acceptance Flow

- [ ] 5.1 RED: acceptance flow test skeleton
- [ ] 5.2 Create delegation-acceptance-modal.tsx
- [ ] 5.3 Update DelegationBanner for pending-acceptance state
- [ ] 5.4 GREEN: acceptance flow tests pass
- [ ] 5.5 `bun run typecheck` exits 0

## Phase 6 — Roadmap + Flag Documentation

- [ ] 6.1 Update roadmap.md: add #4232 listing
- [ ] 6.2 Verify feature flag documentation
- [ ] 6.3 Update .env.example if needed

## Phase 7 — Tests + Verification

- [ ] 7.1 Full test suite: `bun run typecheck` + `bun test` — all pass
- [ ] 7.2 Verify flag-gating: all new components render nothing when flag OFF
- [ ] 7.3 Verify no key residue in UI: grep for api_key/anthropic_key/key_prefix/last_four
- [ ] 7.4 Verify grantor display name only in all delegation UI
- [ ] 7.5 Verify DSAR coverage: byok_delegation_acceptances in allowlist

## Post-merge (operator)

- [ ] PM1. Migration 074 applied to prd (auto via web-platform-release.yml)
- [ ] PM2. Harry signs Delegation Consent Side Letter (manual — legal consent act)
- [ ] PM3. Operator grants delegation via CLI
- [ ] PM4. Flip BYOK_DELEGATIONS_ENABLED ON for jikigai org (Flagsmith)
- [ ] PM5. Verify banner for Harry (Playwright MCP)
- [ ] PM6. Verify funded pane for Jean (Playwright MCP)
- [ ] PM7. Update side-letter-register.md with Harry's acceptance
- [ ] PM8. Close #4232
