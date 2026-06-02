---
feature: fix-sol-49-delegation-acceptance-modal-mount
issue: SOL-49
linear_url: https://linear.app/jikigai/issue/SOL-49/la-fenetre-de-confirmation-ne-se-ferme-pas
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
plan: knowledge-base/project/plans/2026-06-02-fix-sol-49-delegation-acceptance-modal-mount-plan.md
---

# Tasks — fix: SOL-49 — Delegation acceptance modal never mounts

Derived from `knowledge-base/project/plans/2026-06-02-fix-sol-49-delegation-acceptance-modal-mount-plan.md`. Execute with `skill: soleur:work`.

## Phase 0 — Preconditions (read-only)

- [ ] 0.1 `gh issue view 4232` and `gh pr view 4508 --json title,mergedAt` — confirm PR-B merged and #4232 is OPEN (parent BYOK rollup still open pending flag flip).
- [ ] 0.2 Re-confirm the orphan: `grep -rn 'DelegationAcceptanceModal' apps/web-platform/components apps/web-platform/app | grep -v test | grep -v '/components/settings/delegation-acceptance-modal.tsx'` returns 0. If ≥1, abort and re-research.
- [ ] 0.3 Confirm `BYOK_SIDE_LETTER_VERSION` export: `grep -nE 'export const BYOK_SIDE_LETTER_VERSION' apps/web-platform/server/byok-side-letter.ts` returns 1. (Verified at plan time: line 23, `"1.0.0" as const`.)
- [ ] 0.4 Verify `router.refresh()` precedent: read `apps/web-platform/components/scope-grants/scope-grant-row.tsx:60-118` (canonical Next 15 App Router optimistic-mutation pattern shipped 2026-05-19, PR #4059, learning `2026-05-19-optimistic-local-state-and-server-prop-conjunction-needs-router-refresh.md`).
- [ ] 0.5 Confirm the modal's three callback signatures: `grep -n 'on(Accepted\|Declined\|Withdrawn)' apps/web-platform/components/settings/delegation-acceptance-modal.tsx` matches `onAccepted: () => void`, `onDeclined: () => void`, `onWithdrawn?: () => void`.
- [ ] 0.6 Confirm `AcceptanceStatus` shape — 3-state enum (`accepted`, `withdrawn` booleans): `grep -nE 'accepted|withdrawn' apps/web-platform/server/byok-delegation-ui-resolver.ts:30-41`.
- [ ] 0.7 Confirm `chat/layout.tsx` is a Server Component: `grep -E '"use client"' apps/web-platform/app/(dashboard)/dashboard/chat/layout.tsx` returns 0.
- [ ] 0.8 Confirm `delegation-banner.tsx` already has `"use client"`: line 1.

## Phase 1 — RED (failing tests first)

- [ ] 1.1 Create `apps/web-platform/test/delegation-banner.test.tsx` using `vi.hoisted` for the `useRouter` mock (precedent: `apps/web-platform/test/api-usage-retry-button.test.tsx:4-26`). Sub-cases:
  - [ ] 1.1.a Pending banner shows "Review & accept" button (`screen.getByRole('button', { name: /review.+accept/i })`).
  - [ ] 1.1.b Click "Review & accept" → modal opens (`screen.getByRole('dialog')`).
  - [ ] 1.1.c Accept happy path: ack + I accept → fetch OK → modal unmounts AND `mockRefresh` called exactly once.
  - [ ] 1.1.d Decline path: fetch OK → modal unmounts → `mockRefresh` called once.
  - [ ] 1.1.e `alreadyAccepted=true, withdrawn=false` variant: "Running on jean's key" + Manage → modal opens in withdraw variant → withdraw → `mockRefresh` once → modal unmounts.
  - [ ] 1.1.f `withdrawn=true` variant: banner shows re-accept entry point (not withdraw), covers state 3 of the 3-value enum.
  - [ ] 1.1.g Success-only refresh invariant: fetch returns 500 → `mockRefresh` NOT called.
  - [ ] 1.1.h Catch-branch invariant: `fetchMock.mockRejectedValueOnce(...)` → `mockRefresh` NOT called.
- [ ] 1.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/delegation-banner.test.tsx` — capture failures (RED).

## Phase 2 — GREEN: banner rewrite

- [ ] 2.1 Edit `apps/web-platform/components/chat/delegation-banner.tsx` (already `"use client"` — extend, do not convert):
  - [ ] 2.1.a Add imports: `useState`, `useRouter` from `next/navigation`, `DelegationAcceptanceModal` from `@/components/settings/delegation-acceptance-modal`.
  - [ ] 2.1.b Extend `DelegationBannerProps`: add `delegationId: string`, `hourlyCapCents: number | null`, `sideLetterVersion: string`, `alreadyAccepted: boolean`, `withdrawn: boolean`.
  - [ ] 2.1.c Add state: `const [open, setOpen] = useState(false)`; `const router = useRouter();`.
  - [ ] 2.1.d Implement 3 branches (never-accepted, active, withdrawn) — withdrawn presents the same UX as never-accepted (re-accept entry point) since mig 075's SQL gate closes-out on `withdrawn=true`.
  - [ ] 2.1.e Mount modal conditionally: `{open && <DelegationAcceptanceModal alreadyAccepted={alreadyAccepted && !withdrawn} ... onAccepted={handleAccepted} onDeclined={handleDeclined} onWithdrawn={handleWithdrawn} />}`. Conditional mount IS the close semantic.
  - [ ] 2.1.f Add 3 distinct callbacks: each sets `open=false` AND calls `router.refresh()` — **success-only**, do NOT factor to a shared helper.
- [ ] 2.2 Edit `apps/web-platform/app/(dashboard)/dashboard/chat/layout.tsx`:
  - [ ] 2.2.a Import `BYOK_SIDE_LETTER_VERSION` from `@/server/byok-side-letter`.
  - [ ] 2.2.b Extend `bannerProps`: add `delegationId: delegation.id`, `hourlyCapCents: delegation.hourlyCapCents`, `sideLetterVersion: BYOK_SIDE_LETTER_VERSION`, `alreadyAccepted: acceptance.accepted`, `withdrawn: acceptance.withdrawn`.
  - [ ] 2.2.c Keep existing `pending` field if used by banner copy; drop only if the banner derives state from `alreadyAccepted` + `withdrawn` exclusively (avoid redundant sources of truth — sharp-edge from PR #4627 Decision #11).
- [ ] 2.3 `cd apps/web-platform && ./node_modules/.bin/vitest run test/delegation-banner.test.tsx` — all 6+ sub-cases pass (GREEN).
- [ ] 2.4 `cd apps/web-platform && ./node_modules/.bin/vitest run test/delegation-acceptance-modal.test.tsx` — existing tests still pass unchanged.

## Phase 3 — Integration wiring

- [ ] 3.1 If chat layout's existing `try/catch` could silently null the banner on a missing `BYOK_SIDE_LETTER_VERSION` import (it won't because the import is static, but verify), broaden the catch to mirror via `reportSilentFallback` from `@/lib/observability` (server-side) per `cq-silent-fallback-must-mirror-to-sentry`. If symbol absent, grep for the closest equivalent — do NOT skip.
- [ ] 3.2 `cd apps/web-platform && bun run typecheck` exits 0. If `DelegationBannerProps` is widened cross-consumer, audit per `hr-type-widening-cross-consumer-grep` (verified at plan time: 0 cross-consumers).

## Phase 4 — Verification

- [ ] 4.1 `cd apps/web-platform && bun run typecheck` exits 0.
- [ ] 4.2 `cd apps/web-platform && ./node_modules/.bin/vitest run` exits 0 (full suite).
- [ ] 4.3 AC1: `grep -rn 'DelegationAcceptanceModal' apps/web-platform/components apps/web-platform/app | grep -v test | grep -v node_modules | grep -v '/components/settings/delegation-acceptance-modal.tsx'` returns ≥ 1.
- [ ] 4.4 AC4-AC5: `grep -cE 'router\.refresh\(\)' apps/web-platform/components/chat/delegation-banner.tsx` returns exactly 3.
- [ ] 4.5 AC6: `grep -nE "BYOK_SIDE_LETTER_VERSION|side[Ll]etterVersion" apps/web-platform/app/(dashboard)/dashboard/chat/layout.tsx` returns ≥ 1.
- [ ] 4.6 No new dependencies: `git diff main -- apps/web-platform/package.json apps/web-platform/package-lock.json` is empty.
- [ ] 4.7 No new API routes / RPC / schema: `git diff main -- apps/web-platform/app/api apps/web-platform/supabase/migrations` is empty.

## Phase 5 — Compliance changelog + PR body

- [ ] 5.1 Append to `knowledge-base/legal/compliance-posture.md` (Changelog section): `2026-06-02 — fix(byok): SOL-49 delegation acceptance modal mount surface restored. SQL gate (mig 075) was intact throughout — the fix is UX-only and does not alter the lawful-basis chain.`
- [ ] 5.2 PR body uses `Ref SOL-49` + full Linear URL (no `Closes` keyword — Linear doesn't use GitHub close magic; status transition lives in PM3).

## Post-merge (operator)

- [ ] PM1. Playwright MCP dogfood on dev: Jean creates grant → Harry's chat shows actionable banner → click "Review & accept" → modal opens → ack + "I accept" → modal disappears within one render AND banner copy swaps to "Running on Jean's key — $0.00 of $20 today". Capture before/after screenshots. **Critical:** if the modal disappears but the banner copy is stale, we hit `vercel/next.js#77504` — diagnose at that point, do NOT preemptively switch architectures.
- [ ] PM2. Playwright MCP dogfood withdraw: Harry → Manage → withdraw → modal disappears → banner returns to pending or hides.
- [ ] PM3. Linear MCP: update SOL-49 status to Done with screenshots from PM1/PM2 + one-line reproduction note. Use `mcp__linear-server__save_comment` + `save_issue`.
- [ ] PM4. Sentry MCP: search `delegations/accept` 4xx events in the bug window (PR #4508 merge → this PR merge) to confirm no `409 already_accepted` flood needs cleanup. If MCP missing, `gh api` Sentry events endpoint per `hr-no-dashboard-eyeball-pull-data-yourself`.

## References

- Plan: `knowledge-base/project/plans/2026-06-02-fix-sol-49-delegation-acceptance-modal-mount-plan.md`
- Brainstorm carry-forward: `knowledge-base/project/brainstorms/2026-05-29-byok-delegation-consent-enforcement-brainstorm.md`
- Canonical precedent: `apps/web-platform/components/scope-grants/scope-grant-row.tsx` (PR #4059, 2026-05-19)
- Learning (load-bearing): `knowledge-base/project/learnings/ui-bugs/2026-05-19-optimistic-local-state-and-server-prop-conjunction-needs-router-refresh.md`
- Parent PRs: #4508 (mount task dropped), #4627 (consent enforcement, modal extended with withdraw branch)
- Linear: https://linear.app/jikigai/issue/SOL-49/la-fenetre-de-confirmation-ne-se-ferme-pas
