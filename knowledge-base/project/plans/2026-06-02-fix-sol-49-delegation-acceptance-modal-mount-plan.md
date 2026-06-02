---
feature: fix-sol-49-delegation-acceptance-modal-mount
issue: SOL-49
linear_url: https://linear.app/jikigai/issue/SOL-49/la-fenetre-de-confirmation-ne-se-ferme-pas
parents:
  - 4232
  - 4625
status: draft
lane: single-domain
type: bug
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
created: 2026-06-02
brainstorm: knowledge-base/project/brainstorms/2026-05-29-byok-delegation-consent-enforcement-brainstorm.md
---

# fix: SOL-49 — Delegation acceptance modal never mounts (so it can't close on accept)

## Enhancement Summary

**Deepened on:** 2026-06-02
**Sections enhanced:** Phase 0 (preconditions), Phase 1 (RED tests), Phase 2 (GREEN edits), Risks, Sharp Edges, Acceptance Criteria
**Research agents / queries used:** WebSearch (Next.js 15 router.refresh regression), Context7 `/vercel/next.js` (router.refresh API contract), repo grep (router.refresh precedents — 14+ sites including `scope-grant-row.tsx`, `pending-invite-banner.tsx`, `key-rotation-form.tsx`, `dsar-export-job-list.tsx`), learning `2026-05-19-optimistic-local-state-and-server-prop-conjunction-needs-router-refresh.md` (exact-pattern match — PR-G shipped the same defect class, fix landed in PR #4059)

### Key Improvements

1. **Pattern carry-forward from PR-G #4059.** The `scope-grant-row.tsx` precedent is the canonical Next 15 App Router optimistic-mutation pattern in this codebase: `useTransition` + `useRouter().refresh()` inside the success branch of a `fetch()` mutation. The deepened plan mirrors that shape verbatim (including the **success-only** refresh placement — error/catch branches must NOT call `refresh()` because that would clobber pessimistic revert with stale server state).
2. **`vi.hoisted` mock requirement made explicit.** Vitest hoists `vi.mock("next/navigation", ...)` factories above all imports; a bare top-level `const mockRefresh = vi.fn()` is undefined inside the factory at hoist time. The new test must use `vi.hoisted` (precedent: `apps/web-platform/test/api-usage-retry-button.test.tsx:4-26`). RED tests that hand-roll the mock will throw `ReferenceError: Cannot access 'mockRefresh' before initialization` and look like a test-setup bug rather than the actual mock-hoisting trap.
3. **`AcceptanceStatus` is 3-state, not 2.** Verified the live shape: `{ accepted: boolean, withdrawn: boolean, ... }` at `byok-delegation-ui-resolver.ts:30-41`. Three legal combinations carry distinct UI semantics: never-accepted (CTA: "Review & accept"), active (banner only, optional "Manage" → withdraw modal), withdrawn (CTA: "Re-accept" — same as never-accepted, because the SQL gate at mig 075 closes-out on `withdrawn=true`). Phase 2 must enumerate all 3 explicitly per the 3-value-enum sharp edge.
4. **`delegation-banner.tsx` already has `"use client"`** — original plan Phase 2.1 task said "add `'use client'`" but it's already there since the banner was always a client component (text + Link). Corrected to "extend the existing client component with state and modal mount".
5. **Next 15 known `router.refresh()` regression flagged.** Web search surfaced `vercel/next.js#77504` reporting `router.refresh()` regressions in Next 15. The project is on `next@^15.5.18`; canonical precedents in the codebase still work (14+ refresh sites function correctly per recent PRs). Risk: low (mitigated by the multi-site precedent), but documented in Sharp Edges so PM1's Playwright dogfood specifically verifies the post-accept render swap, not just a 200 response.
6. **Mount-conditional pattern reaffirmed over `open`-prop pattern.** The modal's existing implementation has no `open` prop — the parent's conditional `{open && <Modal/>}` is the unmount semantic. The TypedConfirmModal sibling uses an `open` prop; the asymmetry is intentional (TypedConfirm is owned by long-lived dashboard cards that mount once; DelegationAcceptanceModal is gated on transient state). DO NOT refactor the modal to take `open` during this fix — it would expand blast radius without benefit.

### New Considerations Discovered

- **`router.refresh()` inside `useTransition`/`startTransition` is intentional** — it extends `isPending` until the refreshed server payload arrives. The action button stays disabled across the round-trip. Reviewers may flag "the button feels slow"; document in PR body. (Source: `2026-05-19` learning Sharp Edges.)
- **`reportSilentFallback` is client-only on the banner side** — the chat layout is a server component and would use `@/lib/observability` (server-side). The original plan's Phase 3.1 conflated them. Corrected to specify the server-side `reportSilentFallback` import path AND the existence-check before edit (the symbol may live elsewhere).
- **No `revalidatePath`/`revalidateTag` needed.** `router.refresh()` is sufficient because `resolveGranteeAcceptanceStatus` reads with `createServiceClient()` and does NOT use `unstable_cache` or fetch-level caching. If a future PR wraps the resolver in `unstable_cache`, this fix regresses silently — the new Sharp Edge documents this.
- **`startTransition` precedent — adopt or skip?** `scope-grant-row.tsx` uses `useTransition`; `pending-invite-banner.tsx` does NOT (just `useState` + local `loading` flag). Both patterns are valid. The modal has its own `loading` state already, so the simpler `pending-invite-banner.tsx` shape (banner-level open/closed `useState`, no transition) is sufficient — no `useTransition` required at the banner level.
- **Linear "Ref" syntax.** Linear does NOT have GitHub's `Closes #N` auto-close syntax. The PR body should include `Ref SOL-49` for searchability + the full Linear URL; the Linear status transition to Done happens via Linear MCP (PM3).

## Overview

**Reporter symptom (FR):** « Le thème est un peu bugué. La fenêtre pour accepter ou décliner ne part pas quand on accepte. »
**English:** "The theme is a bit buggy. The window to accept or decline doesn't go away when you accept."
**Reporter context (Jean Deruelle comment):** « j'ai aussi ajouté la délégation de clé API Anthropic » — "I also added the Anthropic API key delegation" — anchors the bug surface to the BYOK delegation acceptance flow shipped in PR #4508 / PR #4627.

**Root cause:** `apps/web-platform/components/settings/delegation-acceptance-modal.tsx` was created in PR #4508 and modified in PR #4627 (server-owned version + withdraw branch), but **no parent component ever mounts it**. The PR-B plan's task 5.3 ("Update DelegationBanner for pending-acceptance state") was implemented only as a text-only banner — there is no "Accept" button on `components/chat/delegation-banner.tsx`, no entry point on the chat layout, and no mount site in any settings page. A `grep -rn DelegationAcceptanceModal apps/web-platform` outside `test/` returns only the file's own definition.

This produces TWO related defects, both rolled up under SOL-49's user-facing wording:

1. **No accept path.** A grantee with a pending delegation sees the "Pending acceptance" text in the chat banner and the "Accept access" CTA in `NoApiKeyBanner` → `/dashboard/chat/new`, but there is no clickable surface to actually accept. The legal grantee-consent gate (#4625 / mig 075) refuses to lease the key until acceptance is recorded; without a UI accept path the keyless grantee is stuck.
2. **"The window doesn't close on accept."** Whatever ad-hoc mount the reporter exercised (Jean's local dogfood, a forgotten dev surface, or a hand-crafted route) calls `onAccepted()`, but the parent that mounted the modal doesn't unmount it — the server-rendered delegation state hasn't been re-fetched (no `router.refresh()`), so on the next render the parent still believes acceptance is pending and re-mounts the modal. The modal itself has no internal `isOpen` state — it relies entirely on the parent to remove it from the tree (see `delegation-acceptance-modal.tsx:93-189`, which always renders the backdrop unconditionally).

**Fix:** Wire `DelegationAcceptanceModal` into the chat layout as the *only* canonical mount surface, gated on `acceptance.accepted === false`, with an explicit `useRouter().refresh()` invocation inside the `onAccepted` / `onDeclined` / `onWithdrawn` callbacks so the server-component re-fetch resolves the modal's unmount condition. Re-purpose the existing text-only `DelegationBanner` "Pending acceptance" state into a 2-state machine: text banner when pending, clickable banner that opens the (already-existing) modal. This is the minimum-blast-radius landing for the orphaned modal — no new pages, no new routes, no new RPC.

This is a **regression fix for a missing-writer-path defect** introduced by PR #4508 (mount step dropped during /work) — sharp-edge class `wg-zero-agents-until-user-confirms` adjacent — and a **silent-fallback fix** for the `onAccepted` callback (callback fires, view doesn't reflect the new state).

## Research Reconciliation — Spec vs. Codebase

| Spec / brainstorm / PR claim | Codebase reality (2026-06-02) | Plan response |
|---|---|---|
| PR #4508 task 5.3: "Update DelegationBanner for pending-acceptance state" | `components/chat/delegation-banner.tsx` renders text-only "Pending acceptance" — no button, no modal open-state, no callback wire-up | Phase 2 extends the banner to mount the modal (toggle on/off via banner click). |
| PR #4508 task 5.2 says modal "shown to grantee when they have a pending (unaccepted) delegation" + "After accept: banner becomes active; delegation resolver starts resolving" | `grep -rn DelegationAcceptanceModal apps/web-platform` returns ZERO mounts outside `test/`. The post-accept "banner becomes active" transition is impossible without a `router.refresh()`. | Phase 2 mounts the modal in `chat/layout.tsx` mount-chain (via banner); Phase 3 wires `router.refresh()` into `onAccepted` / `onDeclined` / `onWithdrawn`. |
| PR #4627 (Phase 5 plan §242): "`components/settings/delegation-acceptance-modal.tsx` (drop client version, add ack + withdraw)" | Server-owned version + ack + withdraw all implemented IN the modal; but parent UI for `alreadyAccepted=true` (withdraw entry point) also never mounted | Phase 4 adds the withdraw entry point to the chat layout (re-uses same banner+modal pair, parameterized by `alreadyAccepted`). |
| Side Letter version stamping is server-owned at the accept route | Confirmed at `app/api/workspace/delegations/accept/route.ts` (route stamps `BYOK_SIDE_LETTER_VERSION`, body only carries `delegationId`) | No change needed to the route — modal already POSTs the minimal body. |
| `resolveGranteeDelegation` + `resolveGranteeAcceptanceStatus` both used in `chat/layout.tsx` | Confirmed (`chat/layout.tsx:34-36`) — the server component already fetches both pieces of data on each render, so a `router.refresh()` is the canonical unmount trigger | Phase 3 wires `router.refresh()`; no new resolver needed. |
| `chat/layout.tsx` is a Server Component (no `"use client"` directive) | Confirmed — `grep -E '"use client"' apps/web-platform/app/(dashboard)/dashboard/chat/layout.tsx` returns 0. (Sibling `apps/web-platform/app/(dashboard)/layout.tsx` IS client-marked, which is irrelevant — segment layouts are independently classified.) | `router.refresh()` semantics are valid because the segment layout re-executes server-side on refresh. |
| `delegation-banner.tsx` is already `"use client"`-marked | Confirmed — line 1 of the file. The original plan's Phase 2.1 task "mark `'use client'`" is a no-op; corrected below. | Phase 2.1 task is "extend the existing client component", not "convert". |
| `AcceptanceStatus` has 2 booleans (`accepted`, `withdrawn`) — 3 effective states | Confirmed at `byok-delegation-ui-resolver.ts:30-41` AND the resolver logic at `:204-205` (`withdrawn := withdrawnAt !== null && (acceptedAt === null || withdrawnAt >= acceptedAt)`). | Phase 2.1 enumerates all 3 states explicitly per the 3-value-enum sharp edge (`2026-05-12-plan-precondition-and-3-value-enum-gate-drift.md`). |
| `BYOK_SIDE_LETTER_VERSION` exported from `@/server/byok-side-letter` | Confirmed — `apps/web-platform/server/byok-side-letter.ts:23` exports `"1.0.0" as const`. | Phase 2.2's `BYOK_SIDE_LETTER_VERSION` import lands safely. |
| `DelegationBannerProps` is internal to `delegation-banner.tsx` (no cross-file consumers) | Confirmed via `grep -rn 'DelegationBannerProps' apps/web-platform` — 1 hit (definition); no Storybook, no shared types file. | Risk R1 (type widening) lowered from medium to negligible. |
| Next.js version: `next@^15.5.18` | Confirmed at `apps/web-platform/package.json`. Web search surfaced `vercel/next.js#77504` reporting Next 15 `router.refresh()` regressions for specific layout shapes. | New Sharp Edge added; PM1 Playwright dogfood specifically verifies the post-accept RSC re-render. |
| 14+ existing `router.refresh()` sites in the codebase function correctly | Confirmed via `grep -rn 'router\.refresh\(\)' apps/web-platform` — including the load-bearing `scope-grant-row.tsx:91,118` shipped 2026-05-19 (PR #4059) and `pending-invite-banner.tsx:33,52`. | Pattern is field-proven in the same Next 15 deployment; carry forward verbatim. |

## User-Brand Impact

**If this lands broken, the user experiences:** a perpetually-open modal that visually obstructs the chat surface after they click "I accept" — the same modal re-opens on every render until they hard-refresh the page. The post-acceptance view (cap remaining, today's spend, "Running on Jean's key") never appears. The grantee believes acceptance failed and either repeatedly clicks "I accept" (each click is a no-op on the WORM acceptance table after the first, but generates POST traffic and may log spurious `409 already accepted` to Sentry) or abandons the workspace entirely.

**If this leaks, the user's data/workflow/money is exposed via:** N/A — this is a UI-visibility regression on a defense that already shipped at the SQL gate (`resolve_byok_key_owner` per mig 075 refuses to lease without an acceptance row). The lawful-basis gate is intact; only the UX entry to *create* the acceptance row is missing. No PII leak, no over-charging, no cross-tenant trust breach.

**Brand-survival threshold: `single-user incident`.** The brand promise of the BYOK delegation feature ("your grantor funds your runs; you opt in once") collapses for any first-time grantee who lands on a workspace where their owner has shared a key. Every workspace-owner who delegates to a new member encounters this defect on the grantee's first session. The Jikigai-team dogfood (Jean → Harry) is the *typical* invocation path — exactly the path the reporter exercised. CPO sign-off required at plan time (carried forward from the parent brainstorm `2026-05-29-byok-delegation-consent-enforcement-brainstorm.md` which declared `brand_survival_threshold: single-user incident` and got CPO+CLO+CTO brainstorm-phase sign-off).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1.** `grep -rn 'DelegationAcceptanceModal' apps/web-platform/components apps/web-platform/app | grep -v test | grep -v node_modules | grep -v '/components/settings/delegation-acceptance-modal.tsx'` returns **≥ 1 match** — proves the modal is actually mounted somewhere in the route tree.
- [ ] **AC2.** `apps/web-platform/components/chat/delegation-banner.tsx` exports a client component that takes a `pending: boolean` AND a `delegationId: string` (when pending) AND a `grantorDisplayName`, `dailyCapCents`, `hourlyCapCents`, `sideLetterVersion` set of props — verified by `tsc --noEmit` over the file.
- [ ] **AC3.** When `pending === true`, the banner renders a button (`role="button"`, accessible name matches `/review|accept|consent/i`) whose `onClick` toggles modal visibility. Verified by the new RTL test `delegation-banner.test.tsx` (Phase 1.1 RED → 1.3 GREEN).
- [ ] **AC4.** Modal's `onAccepted` callback in the new mount calls `router.refresh()` AND closes the local open-state. Verified by:
  - `grep -nE 'router\.refresh\(\)' apps/web-platform/components/chat/delegation-banner.tsx` returns ≥ 1.
  - RTL test asserts the modal disappears after `fetch` mock resolves OK AND `router.refresh` mock fires.
- [ ] **AC5.** Same for `onDeclined` and `onWithdrawn`: both wire `router.refresh()`. Three callback sites total — verified by `grep -cE 'router\.refresh\(\)' apps/web-platform/components/chat/delegation-banner.tsx` returns **3** (not 1, not 2 — exactly 3, matching `onAccepted` + `onDeclined` + `onWithdrawn`).
- [ ] **AC5b. Success-only refresh invariant** (per learning `2026-05-19`): the test suite in `delegation-banner.test.tsx` includes a negative assertion that `mockRefresh` is NOT called when the modal's POST returns non-2xx (1.1.g) AND when fetch throws (1.1.h). This locks the placement against future refactors hoisting `router.refresh()` into a shared helper or `finally` block.
- [ ] **AC6.** Banner mount in `app/(dashboard)/dashboard/chat/layout.tsx` now passes the delegation `id`, `hourlyCapCents`, and the server-canonical `sideLetterVersion` (imported from `@/server/byok-side-letter`) — verified by:
  - `grep -nE 'BYOK_SIDE_LETTER_VERSION|side[Ll]etterVersion' apps/web-platform/app/(dashboard)/dashboard/chat/layout.tsx` returns ≥ 1.
  - `grep -nE "import .* from '@/server/byok-side-letter'" apps/web-platform/app/(dashboard)/dashboard/chat/layout.tsx` returns 1.
- [ ] **AC7.** A grantee who has ALREADY accepted (i.e. `acceptance.accepted === true` AND no withdrawal) sees the existing "Running on X's key" copy, AND a discreet "Manage / withdraw" affordance that opens the modal in its `alreadyAccepted=true` variant — verified by RTL test `delegation-banner.test.tsx` "withdraw entry point" group.
- [ ] **AC8.** `bun run typecheck` exits 0.
- [ ] **AC9.** `bun test apps/web-platform/test/delegation-acceptance-modal.test.tsx apps/web-platform/test/delegation-banner.test.tsx` exits 0.
- [ ] **AC10.** No new vendor dependencies: `git diff main -- apps/web-platform/package.json apps/web-platform/package-lock.json` is empty.
- [ ] **AC11.** No new API routes, no new RPC, no schema change — verified by `git diff main -- apps/web-platform/app/api apps/web-platform/supabase/migrations` is empty.
- [ ] **AC12.** Flag gating preserved: when `isByokDelegationsEnabled(orgId, identity) === false`, the banner does not render and the modal is never mounted (the chat layout's existing `bannerProps = null` short-circuit). Verified by RTL test "delegations-disabled" group asserting `screen.queryByRole('dialog')` is null.
- [ ] **AC13.** PR body uses `Ref SOL-49` (Linear issue, not a GitHub issue — the `Closes` magic doesn't apply; closing happens manually in Linear after dogfood verification).
- [ ] **AC14.** Compliance-posture changelog entry added noting that "the in-product consent capture surface (`delegation-acceptance-modal.tsx`) is now reachable; the SQL gate (mig 075) was always intact — this fix closes the UX entry-point gap only".

### Post-merge (operator)

- [ ] **PM1.** Verify on dev: Jean creates a grant to Harry's dev account → Harry's chat surface shows the actionable banner → Harry clicks "Review & accept" → modal opens → Harry checks the telemetry ack → "I accept" → modal disappears within one render → banner switches to "Running on Jean's key — $0.00 of $20 today". Automation: Playwright MCP (`mcp__playwright__browser_navigate` + `mcp__playwright__browser_snapshot` + `mcp__playwright__browser_click`). Capture screenshots before/after.
- [ ] **PM2.** Verify withdraw on dev: Harry clicks "Manage / withdraw" → modal opens in `alreadyAccepted` variant → "Withdraw consent" → modal disappears → banner returns to "Pending acceptance" or hides (whichever the resolver returns post-withdrawal). Automation: Playwright MCP.
- [ ] **PM3.** Re-resolve SOL-49 in Linear with screenshots of the before/after dogfood run + a one-line reproduction note. Automation: Linear MCP `mcp__linear-server__save_comment` + `save_issue` (status → Done).
- [ ] **PM4.** Search Sentry for `delegations/accept` 4xx events created during the bug window (PR #4508 merge → this PR merge) so the operator can confirm no spurious `409 already_accepted` floods need cleanup. Automation: Sentry MCP (`mcp__plugin_soleur_sentry__events`) — if not installed, `gh api` against Sentry's events endpoint per `hr-no-dashboard-eyeball-pull-data-yourself`.

## Files to Edit

| File | Change |
|---|---|
| `apps/web-platform/components/chat/delegation-banner.tsx` | **Major edit** — convert text-only banner to client-component with modal mount, open-state toggle, `router.refresh()` wiring on all 3 callbacks. Accepts `delegationId`, `hourlyCapCents`, `sideLetterVersion` as new props. Renders both pending and already-accepted variants. |
| `apps/web-platform/app/(dashboard)/dashboard/chat/layout.tsx` | **Edit** — pass the additional banner props (`delegationId`, `hourlyCapCents`, server-canonical `sideLetterVersion`). Import `BYOK_SIDE_LETTER_VERSION` from `@/server/byok-side-letter` so the modal POST body matches what the route stamps. Also gates `bannerProps` to expose the `acceptance.accepted` boolean (not just `pending` derived from it) so the banner can branch internally. |
| `apps/web-platform/test/delegation-banner.test.tsx` | **Create** — RTL/Vitest suite covering: (a) text-only render when flag off, (b) actionable banner when `pending=true`, (c) modal open-on-click, (d) modal close after `onAccepted` + `router.refresh` fires, (e) `alreadyAccepted` withdraw entry point. |
| `knowledge-base/legal/compliance-posture.md` | **Edit** — one-line changelog entry: "2026-06-02 — fix(byok): delegation acceptance modal mount surface restored (SOL-49); SQL gate (mig 075) was intact throughout — fix is UX-only." |

## Files to Create

None (re-uses the orphaned `delegation-acceptance-modal.tsx`; no new routes, no new components beyond the test file).

## Open Code-Review Overlap

Ran `gh issue list --label code-review --state open --limit 200 --json number,title,body > /tmp/open-review-issues.json` then for each file in the table above:

```bash
for path in \
  "apps/web-platform/components/chat/delegation-banner.tsx" \
  "apps/web-platform/app/(dashboard)/dashboard/chat/layout.tsx" \
  "apps/web-platform/components/settings/delegation-acceptance-modal.tsx" \
  "knowledge-base/legal/compliance-posture.md"; do
  jq -r --arg path "$path" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
done
```

None at plan-write time — record present so the next planner can see the check ran.

## Implementation Phases

### Phase 0 — Preconditions (read-only)

- [ ] 0.1 `gh issue view 4232` and `gh pr view 4508 --json title,mergedAt` to confirm PR-B merged and #4232 is OPEN (the parent BYOK-delegations rollup is still open pending flag flip — verified at brainstorm time).
- [ ] 0.2 Re-confirm the orphan: `grep -rn 'DelegationAcceptanceModal' apps/web-platform/components apps/web-platform/app | grep -v test | grep -v '/components/settings/delegation-acceptance-modal.tsx'` returns 0. If it returns ≥1, abort and re-research — someone may have wired it up in a sibling branch that landed since 2026-06-02.
- [ ] 0.3 Confirm `BYOK_SIDE_LETTER_VERSION` export at `apps/web-platform/server/byok-side-letter.ts`: `grep -nE 'export const BYOK_SIDE_LETTER_VERSION' apps/web-platform/server/byok-side-letter.ts` returns 1. If absent, abort — server-canonical version landing is a precondition of this fix and a P0 review-blocker.
- [ ] 0.4 Confirm `useRouter` is the canonical client-side refresh hook by reading 2 sibling patterns: `apps/web-platform/components/dashboard/pending-invite-banner.tsx:17,32-33` (uses `useRouter().push + .refresh()`) and `apps/web-platform/app/(public)/invite/[token]/invite-actions.tsx:28,108` (same pattern). Plan-time grep-for-precedent per sharp edge `2026-05-12-plan-time-parsing-pattern-needs-codebase-precedent-grep.md`.
- [ ] 0.5 Confirm the modal's three callback signatures: `onAccepted: () => void`, `onDeclined: () => void`, `onWithdrawn?: () => void`. Verified by `grep -n 'on(Accepted\|Declined\|Withdrawn)' apps/web-platform/components/settings/delegation-acceptance-modal.tsx`.

### Phase 1 — RED (tests fail by construction)

- [ ] 1.1 Create `apps/web-platform/test/delegation-banner.test.tsx`. **Use `vi.hoisted` for the mock** (precedent: `apps/web-platform/test/api-usage-retry-button.test.tsx:4-26`); a bare top-level `const mockRefresh = vi.fn()` will throw `ReferenceError: Cannot access 'mockRefresh' before initialization` because `vi.mock` is hoisted above all imports.

  ```tsx
  const { mockRefresh } = vi.hoisted(() => ({ mockRefresh: vi.fn() }));
  vi.mock("next/navigation", () => ({
    useRouter: () => ({ refresh: mockRefresh, push: vi.fn() }),
  }));
  ```

  Suite — none of these tests should pass against the current text-only banner:
  - 1.1.a Render `<DelegationBanner grantorDisplayName="jean" todaySpentCents={0} dailyCapCents={2000} hourlyCapCents={500} pending={true} delegationId="d-1" sideLetterVersion="1.0.0" alreadyAccepted={false} withdrawn={false} />` → `screen.getByRole('button', { name: /review.+accept/i })` exists.
  - 1.1.b Click that button → `screen.getByRole('dialog')` becomes visible AND contains `screen.getByRole('button', { name: /i accept/i })`.
  - 1.1.c Stub `global.fetch` to return `{ ok: true, status: 200 }`. After ack + I accept → `mockRefresh` called exactly once AND modal unmounts (`screen.queryByRole('dialog')` is null). Use `beforeEach(() => { mockRefresh.mockClear(); fetchMock = vi.fn(...); vi.stubGlobal('fetch', fetchMock); })` per the existing modal test precedent at `delegation-acceptance-modal.test.tsx:22-31`.
  - 1.1.d Same for Decline: stub fetch OK → modal unmounts → `mockRefresh` called once.
  - 1.1.e `alreadyAccepted={true}, withdrawn={false}` variant: banner shows "Running on jean's key" + a `Manage` button → click → modal opens in withdraw variant → click withdraw → `mockRefresh` once → modal unmounts.
  - 1.1.f `withdrawn={true}` variant: banner shows the re-accept entry point (not the withdraw entry point) regardless of `alreadyAccepted` value — covers the 3rd enum state.
  - 1.1.g **Success-only refresh invariant** (per learning `2026-05-19`): stub fetch to return `{ ok: false, status: 500 }` → click accept → `mockRefresh` NOT called. Required to lock the success-branch placement against future refactors that hoist into a `finally`.
  - 1.1.h **Catch-branch invariant**: `fetchMock.mockRejectedValueOnce(new Error("network"))` → click accept → `mockRefresh` NOT called.
  - 1.1.i Flag-off shape: `bannerProps = null` in chat layout means the banner never renders at all (no test needed at banner level; AC12 covers via the layout-side gate).
- [ ] 1.2 `bun test apps/web-platform/test/delegation-banner.test.tsx` — should error on missing exports / structure. Capture the failures.

### Phase 2 — GREEN: banner rewrite

- [ ] 2.1 Read `components/chat/delegation-banner.tsx` (already `"use client"` since line 1 — extend, do not convert):
  - Add imports: `useState`, `useRouter` from `next/navigation`, `DelegationAcceptanceModal` from `@/components/settings/delegation-acceptance-modal`.
  - Props extend to include: `delegationId: string`, `hourlyCapCents: number | null`, `sideLetterVersion: string`, `alreadyAccepted: boolean`, `withdrawn: boolean` (3-state enum — see Research Reconciliation row 4 + deepen Key Improvement 3).
  - State: `const [open, setOpen] = useState(false)`; `const router = useRouter();`.
  - **Branch enumeration (3-state, NOT 2):**
    - `!alreadyAccepted && !withdrawn` (never-accepted): existing "Pending acceptance" copy + button "Review & accept" → `onClick={() => setOpen(true)}`.
    - `alreadyAccepted && !withdrawn` (active): existing "Running on X's key" copy + discreet `Manage` text-button → `onClick={() => setOpen(true)}` (opens modal in `alreadyAccepted` variant for withdraw).
    - `withdrawn` (regardless of `alreadyAccepted`): same UI as never-accepted ("Pending re-acceptance" or "Re-accept access") — the SQL gate (mig 075) closes-out on withdrawn=true, so this state behaves identically to never-accepted for the UX entry point.
  - Modal mount: gated `{open && <DelegationAcceptanceModal alreadyAccepted={alreadyAccepted && !withdrawn} ... onAccepted={handleAccepted} onDeclined={handleDeclined} onWithdrawn={handleWithdrawn} />}` — the conditional mount IS the load-bearing close semantic (the modal has no `open` prop). Note: the modal's `alreadyAccepted` prop drives the withdraw vs. accept variant inside the modal; pass `alreadyAccepted && !withdrawn` to avoid showing the withdraw branch for a row that was withdrawn-then-not-yet-re-accepted.
  - Callbacks (precedent: `scope-grant-row.tsx:60-105`; success-only refresh per learning `2026-05-19`):
    ```tsx
    const handleAccepted = () => { setOpen(false); router.refresh(); };
    const handleDeclined = () => { setOpen(false); router.refresh(); };
    const handleWithdrawn = () => { setOpen(false); router.refresh(); };
    ```
  - **3 distinct `router.refresh()` call-sites** to satisfy AC5. Do NOT factor to a shared helper (the success-only invariant must be visible at each callback per learning `2026-05-19`; sharing risks a future refactor that hoists into a finally and clobbers pessimistic revert in the modal's catch branch).
- [ ] 2.2 Read `app/(dashboard)/dashboard/chat/layout.tsx` then extend the `bannerProps` build:
  - Import `BYOK_SIDE_LETTER_VERSION` from `@/server/byok-side-letter`.
  - Add to `bannerProps`: `delegationId: delegation.id`, `hourlyCapCents: delegation.hourlyCapCents`, `sideLetterVersion: BYOK_SIDE_LETTER_VERSION`, `alreadyAccepted: acceptance.accepted`.
  - Replace the current `pending: !acceptance.accepted` derivation with explicit pass-through: keep `pending` for backward compat in the type but let the banner derive its own state from `alreadyAccepted` (a Sharp-Edge: do NOT use a derived `pending = !alreadyAccepted` — fold to a single source).
  - In the JSX, replace `bannerProps && <DelegationBanner {...bannerProps} />` with the new shape (unchanged spread).
- [ ] 2.3 `bun test apps/web-platform/test/delegation-banner.test.tsx` — should now pass all 6 sub-cases.
- [ ] 2.4 `bun test apps/web-platform/test/delegation-acceptance-modal.test.tsx` — existing tests must still pass unchanged (no modal-internal change).

### Phase 3 — Wire integration into chat layout's data flow

- [ ] 3.1 In `chat/layout.tsx`, broaden the existing `try { ... } catch {}` so a missing `sideLetterVersion` export does NOT silently null the banner — instead it falls through to a typed-narrow Sentry mirror via `reportSilentFallback` (per `cq-silent-fallback-must-mirror-to-sentry`). Use `import { reportSilentFallback } from "@/lib/client-observability"` only if the chat-layout is client-side; otherwise use the server-side `reportSilentFallback` from `@/lib/observability` — verify at task-time.
- [ ] 3.2 `bun run typecheck` — should exit 0. If the `DelegationBannerProps` type is defined inline, broaden it; if it lives in a shared file, update both call sites in lockstep (`cq-union-widening-grep-three-patterns`).

### Phase 4 — Verification

- [ ] 4.1 `bun run typecheck` exits 0.
- [ ] 4.2 `bun test` exits 0 (full suite — the change touches a single banner; broader regression is unlikely but confirm).
- [ ] 4.3 AC1 grep: `grep -rn 'DelegationAcceptanceModal' apps/web-platform/components apps/web-platform/app | grep -v test | grep -v node_modules | grep -v '/components/settings/delegation-acceptance-modal.tsx'` returns ≥ 1.
- [ ] 4.4 AC4-AC5 grep: `grep -cE 'router\.refresh\(\)' apps/web-platform/components/chat/delegation-banner.tsx` returns exactly 3.
- [ ] 4.5 AC6 grep: `grep -nE "BYOK_SIDE_LETTER_VERSION|side[Ll]etterVersion" apps/web-platform/app/(dashboard)/dashboard/chat/layout.tsx` returns ≥ 1.
- [ ] 4.6 No new dependencies: `git diff main -- apps/web-platform/package.json apps/web-platform/package-lock.json` is empty.
- [ ] 4.7 No new API routes / RPC / schema: `git diff main -- apps/web-platform/app/api apps/web-platform/supabase/migrations` is empty.

### Phase 5 — Compliance changelog + PR body

- [ ] 5.1 Append to `knowledge-base/legal/compliance-posture.md` (Changelog section): `2026-06-02 — fix(byok): SOL-49 delegation acceptance modal mount surface restored. SQL gate (mig 075) was intact throughout — the fix is UX-only and does not alter the lawful-basis chain.`
- [ ] 5.2 PR body uses `Ref SOL-49` (Linear); links the Linear issue URL. NOT `Closes` — Linear status is updated post-merge by PM3.

## Risks

- **R1 — Type widening across consumers of `DelegationBannerProps`.** The current props are 4-field; the new shape adds 3. If `DelegationBannerProps` is imported by any other file (e.g. Storybook fixtures, OG image generators), those break. **Mitigation:** Phase 0.5-adjacent grep `grep -rn 'DelegationBannerProps\|DelegationBanner\b' apps/web-platform --include='*.tsx' --include='*.ts'` BEFORE Phase 2 — applies hr `hr-type-widening-cross-consumer-grep`.
- **R2 — Server-component → client-component conversion of `DelegationBanner`.** The banner was server-renderable (text-only); it becomes a client component (state, hooks). The chat layout currently imports it without `"use client"` — verify that pattern still works (Next.js allows client children inside server parents). **Mitigation:** Phase 2.1 explicitly marks the banner `"use client"`; Phase 2.2 leaves the chat layout server-rendered (no `"use client"` directive added).
- **R3 — `acceptance.accepted` plumbing.** The chat layout currently derives `pending: !acceptance.accepted` and the banner branches on `pending`. The new shape passes `alreadyAccepted` separately. **Mitigation:** during Phase 2.2, replace the derivation in a single edit; do NOT introduce a transient state where both `pending` and `alreadyAccepted` exist as redundant sources of truth (sharp-edge: single source of truth per AC5 of #4627 plan).
- **R4 — `router.refresh()` is a client-only hook.** A server-component banner could not call it. **Mitigation:** Phase 2.1 adds `"use client"` first (load-bearing), Phase 2.3 verifies. The chat layout's existing server-side data resolution will re-fire on `router.refresh()` because the layout is a Server Component and Next.js re-runs `ChatLayout` on refresh, re-reading `resolveGranteeAcceptanceStatus`.
- **R5 — The fix uses the existing `pending-invite-banner.tsx` pattern (banner-with-action), not a separate dialog mount surface.** A reviewer may argue for a settings-page-only mount, but the brainstorm and PR #4508 spec both name the chat banner as the entry surface. **Mitigation:** explicit Research Reconciliation row above and a Sharp Edges note that the chat banner is the canonical entry, not Settings.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`.
- The modal's existing implementation has `if (!open) return null` semantics inverted — there is NO `open` prop, the modal renders unconditionally. The close-on-unmount semantics rely entirely on the parent's conditional render `{open && <DelegationAcceptanceModal ... />}`. If a future reviewer suggests "add an `open` prop to the modal," resist — the parent-conditional mount is the canonical Next.js + React pattern (cheaper than adding a prop that duplicates state).
- When wiring `router.refresh()` after a POST that mutates server-component-rendered state, ensure the server resolver's read is NOT cached. `resolveGranteeAcceptanceStatus` uses `createServiceClient()` (Phase 1 read), which Supabase does not cache cross-request — but if a future PR adds `unstable_cache` around it, the modal will look like it doesn't close again. Document this in Phase 3.1's `reportSilentFallback` site so the operator sees the cache hit if it ever happens.
- The `DelegationAcceptanceModal` POST body is `{ delegationId }` only (server stamps the version). DO NOT add `sideLetterVersion` to the body in Phase 2 — it would re-introduce the stale-version vector closed by PR #4627. The `sideLetterVersion` prop is *display-only* on the modal copy ("version 1.0.0").
- Phase 1 RED tests must mock BOTH `next/navigation` AND `global.fetch`. A test that mocks only fetch will fail because `useRouter` returns `null` in jsdom by default → `router.refresh()` throws → `setOpen(false)` never runs → modal "doesn't close" in the test too. The bug class is the same as the production class — the test would falsely pass the production behavior even though it failed.
- Per sharp-edge `2026-05-12-plan-precondition-and-3-value-enum-gate-drift.md`: the `acceptance.accepted` field on `AcceptanceStatus` is boolean today, but the resolver also returns `withdrawn_at` (mig 076 / #4627). The pending-acceptance derivation must classify ALL three states: never-accepted, accepted-and-active, accepted-then-withdrawn. The third state's banner copy should match the never-accepted case (re-prompt to accept anew). Verify the resolver's return shape in Phase 0.3 and enumerate all 3 explicitly in Phase 2.1's `alreadyAccepted` ↔ `pending` branch.
- The chat banner is rendered in `chat/layout.tsx`, which wraps `chat/new/page.tsx` AND `chat/[conversationId]/page.tsx`. Verify in Phase 4 that the banner renders correctly on both routes — the modal portal could clip if the conversation page has its own scroll container.
- **Next 15 `router.refresh()` known regression class.** Web search surfaced `vercel/next.js#77504` ("router.refresh() not working properly in Next.js 15"). The project is on `next@^15.5.18` and 14+ existing call sites (notably `scope-grant-row.tsx` shipped 2026-05-19) work correctly, so the field evidence is positive — but the canonical regression-shape is "refresh fires but server data is stale". PM1 Playwright dogfood MUST verify the BANNER COPY swaps to "Running on Jean's key" (not just that the modal disappears) within one render. If the modal disappears but the banner still says "Pending acceptance", we're hitting the upstream regression and the fix is either `revalidatePath('/dashboard/chat')` from inside the modal's POST handler (server-action variant) OR a Server Action–based refactor of the accept route. Track-only — do NOT preemptively switch architectures.
- **`vi.hoisted` is load-bearing for the test mock.** The PR-G learning (`2026-05-19`) explicitly calls out this trap. The new `delegation-banner.test.tsx` MUST use the `vi.hoisted` form (`const { mockRefresh } = vi.hoisted(() => ({ mockRefresh: vi.fn() }))`) before `vi.mock("next/navigation", ...)`. A test that uses a bare top-level `const mockRefresh = vi.fn()` will throw `ReferenceError` at module load and look like a setup bug rather than the actual mock-hoisting trap.
- **`useTransition` is intentionally NOT used at the banner level.** The modal owns its own `loading` state (`delegation-acceptance-modal.tsx:34`); wrapping `setOpen(false); router.refresh();` in a transition would extend `isPending` past the modal's own gate without benefit. Sibling pattern: `pending-invite-banner.tsx` (no transition) — adopt verbatim. The `scope-grant-row.tsx` transition exists because that component owns the form submission and the `isPending` is the disabled-state for its own button.

## Domain Review

**Domains relevant:** Engineering, Product (UI surface change), Legal (consent-capture entry point), Privacy.

### Engineering (CTO)

**Status:** carried forward from brainstorm `2026-05-29-byok-delegation-consent-enforcement-brainstorm.md` Decision #11.
**Assessment:** Single-file banner edit + 1-line layout pass-through edit + 1 test file create. No new dependencies, no new routes, no schema change. Blast radius: localized to the chat layout's banner sub-tree. The `router.refresh()` wiring is the canonical Next.js pattern for server-component re-fetch and is already used at 2 sibling sites (`pending-invite-banner.tsx`, `invite-actions.tsx`).

### Legal (CLO)

**Status:** carried forward from brainstorm Decision #8 (consent text embodies Art. 26 arrangement; in-product consent is the bilateral / evidentiary layer).
**Assessment:** This PR does NOT alter the consent text, the consent-capture route, the WORM acceptance table, or any legal disclosure. It restores the UX entry point to the already-shipped consent capture surface. Compliance-posture changelog entry (Phase 5.1) is the audit-trail bread crumb.

### Product (CPO) — Product/UX Gate

**Tier:** advisory (modifies an existing UI surface — does not add a new page; mechanical escalation check: no new file under `components/**/*.tsx` or `app/**/page.tsx` — only edits an existing file + creates a test file. Test file does not trigger BLOCKING.)
**Decision:** auto-accepted (pipeline) — single-user incident threshold elevates this to require CPO awareness, which the brainstorm carry-forward provides. UX delta is "convert a text-only banner sentence into a banner with a primary button"; pencil/ux-design-lead not invoked at this size of delta.
**Agents invoked:** none (carry-forward).
**Skipped specialists:** ux-design-lead (delta below wireframe threshold; sibling-banner pattern reused verbatim), copywriter (no new copy introduced — the modal's existing strings ship as-is).
**Pencil available:** N/A.

#### Findings

The primary brand-survival risk is that the grantee EVER lands in a state where the modal can't close. The fix's `router.refresh()` + conditional mount pattern is the minimum-blast-radius landing; no settings-page redesign, no new copy, no flag changes. Carry-forward CPO sign-off (brainstorm) is sufficient.

### Privacy (DPO)

**Status:** unchanged from brainstorm — no new processing activity, no new data flow, no new data-export allowlist entry.
**Assessment:** N/A — the fix re-establishes the UX path to an existing PA-23 / Art. 30 processing activity (BYOK delegation consent capture). No new disclosure or update to PA-23 required.

## Infrastructure (IaC)

Not applicable — pure-code fix touching client components and a test file. No new infrastructure surface (per Phase 2.8 trigger set in plan/SKILL.md: no new server, no new secret, no new vendor, no new persistent runtime). Skip silently.

## Observability

Not applicable — no new emit surface. The fix re-uses `reportSilentFallback` per `cq-silent-fallback-must-mirror-to-sentry` in Phase 3.1 if a server-canonical version import fails; the existing observability schema is unchanged.

The downstream `/api/workspace/delegations/accept` + `/withdraw` routes already emit via existing observability (per #4627). PM4 (post-merge) verifies no event-spam regression from prior bug-window unobserved 4xxs.

## Test Strategy

- **Vitest + React Testing Library** for `delegation-banner.test.tsx` (matches sibling `delegation-acceptance-modal.test.tsx` runner conventions — Phase 0.4 grep-for-precedent).
- **Mock surface:** `next/navigation` (`useRouter`), `global.fetch`. No new mocks vs. sibling tests.
- **No E2E pre-merge.** Playwright integration is post-merge (PM1/PM2) per `hr-dev-prd-distinct-supabase-projects` — synthetic users / WORM acceptance rows are dev-only. Pre-merge surface is unit + RTL.

## CLI Verification Gate

This plan prescribes no CLI invocations that land in user-facing docs. The bash snippets in Phase 4 are operator-only ACs verified at run-time. No CLI-token verification needed per #2566.

## Open Questions

- None. The brainstorm (#4625) + PR-B plan (#4232) provide all the consent-text, threshold, and surface decisions; this plan re-uses them verbatim.
