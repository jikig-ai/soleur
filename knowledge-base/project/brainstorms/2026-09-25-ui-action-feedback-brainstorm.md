---
date: 2026-09-25
topic: ui-action-feedback
status: captured
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Brainstorm: Click/Loading Feedback for the Webapp

## What We're Building

Every interactive element in `apps/web-platform` gets a visible pending contract:

1. **Navigation feedback** — a global route-pending indicator (2px gold top bar in the `RefreshShimmer` idiom, mounted in `app/(dashboard)/layout.tsx` outside the ADR-047 swap region) that fires on `<Link>` clicks, raw internal anchors, `router.push`/`router.replace`, ⌘K-palette and `g`-key navigation. ~150–200ms entry delay + minimum-visible duration so warm `staleTimes.dynamic: 30` navs don't strobe.
2. **Button feedback** — operator chose **Approach B: full primitive migration**. All ~310 native `<button>` sites migrate to a shared button family (gold / outlined / ghost variants) carrying a built-in `loading?: boolean` contract: `disabled` + `aria-busy` + trailing `SpinnerIcon`, stable accessible name, no label-swap unless copy adds meaning ("Sending…" on irreversible sends).
3. **P0 fix — typed-confirm send flow:** the confirm modal stays open showing "Sending…" until the send resolves, instead of vanishing while the POST is in flight (`hooks/use-action-send.ts:195-233`).
4. **Press affordance:** global `:active` press style inside the migrated primitives (tokens only, `var(--soleur-*)`).

## Why This Approach

The app is slow (latency handled by a parallel session — out of scope here); without feedback, clicks look dead. For the non-technical-founder target segment, "slow but working" is indistinguishable from "broken" — users re-click, producing real duplicate-action incidents on unguarded mutation routes (~30 of ~60 mutation sites have no pending guard today).

Full primitive migration (B) was chosen over a layered intercept (A) despite a larger diff (~120+ files vs ~75) because it permanently closes the design-system drift: today only ~6% of button sites use the primitives, so any intercept layer would still leave a forked convention. Migration makes `loading` the only path.

## User-Brand Impact

- **Artifact:** the click/loading feedback layer across all `apps/web-platform` interactive surfaces.
- **Vector:** a pending state that hangs permanently disabled (hung request) or swallows a failure silently leaves a user's action neither done nor visibly failed — on billing/consent paths that is a trust breach; a missing guard is a duplicate-submission incident.
- **Threshold:** single-user incident.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Scope | Navigation + action feedback | Matches complaint; two mechanisms, both needed |
| Button strategy | Full primitive migration (B) | Ends the 94% bypass; `loading` becomes the only convention |
| Nav indicator | Gold 2px top bar, ~150–200ms delay, min-visible duration | RefreshShimmer idiom; avoids flicker on warm cache navs |
| Keyboard nav | Covered | `usePendingRouter()` wrapper covers push/replace + ⌘K + g-keys |
| Typed-confirm send | Modal stays open "Sending…" | Highest-stakes action gets the strongest in-flight signal |
| Double-submit | `disabled` during pending is mandatory everywhere; pending must always terminate (success or visible `role="alert"` error + re-enable) | Billing/consent paths: permanently-disabled button after a hung request is the exact single-user incident |
| Checkout race | **Deferred** — file issue for server-side `/api/checkout` idempotency | Keeps this PR frontend-only, outside the gdpr-gate regex |
| Hard navs | Excluded — `window.location.assign` sites (sign-out, org-switch, delete-account) keep hard-nav semantics | ADR-067 Router-Cache isolation invariant is load-bearing |
| A11y | `aria-busy` + stable accessible name; respect `prefers-reduced-motion` sweep | Existing precedent (`sign-out-confirm-modal.tsx:111`, `review-gate-card.tsx:52`) |
| Same-path query navs | Indicator fires — watcher keys on `usePathname` AND `useSearchParams` | `workstream?issue=`, `crm?contact=` are real navs |
| Visual design | `.pen` wireframes committed: `design/dashboard/action-feedback-variant-{a,b,c}-*.pen` + 12 screenshots; **approved: Variant B (Instrumented Spec)**, adopting A's quiet visuals for production | `wg-ui-feature-requires-pen-wireframe` mandatory; taste recorded (`dashboard/aesthetic-direction = instrumented-spec`) |
| Visual gate | Headless Playwright spec in `authenticated` project for the nav chrome | ADR-049 |
| Observability | Nav-duration `performance.now()` signal alongside the provider | `hr-observability-as-plan-quality-gate`; feeds the parallel perf work |
| Productize candidate | `constraint-scaffold`-style lint rule steering new code to the button primitives | Prevents the 94%-bypass regrowing post-migration |

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

Feedback is a mitigation for slowness, not a fix — must not substitute for the perf investigation (tracked by parallel session). P0 surface is the typed-confirm send flow (`use-action-send.ts` closes the modal before the POST). Navigation pending is the primary "clicked and nothing happened" complaint; one canonical pending visual language is required (today: label-swap, dim-only, step list, SpinnerIcon all coexist).

### Legal (CLO)

Net legal risk *reduction*. Constraints: pending states on cancel/consent paths must always terminate to success or visible error (ROSCA/dark-pattern exposure); disabled-during-pending covers all billing triggers (Reactivate + Update Payment Method currently lack it — real gap); `aria-busy` standardization; `soleur:gdpr-gate` mandatory **iff** any `app/api/**` file enters the diff — the checkout-idempotency deferral keeps this PR outside it.

### Engineering (CTO)

No App Router router-events API. Full migration chosen by operator; primitives gain `loading` prop + `usePendingAction()` hook. Hard-nav principal boundaries must not convert to soft nav. `useLinkStatus` alone can't drive a global bar (descendant-scoped); completion watcher needs `useSearchParams` for same-path query navs. Playwright e2e is the honest verification path; vitest heavily mocks `next/navigation`.

### Marketing (CMO)

Table-stakes trust floor for non-technical founders; dead-click footage would poison demo/validation sessions. Ship as quiet `web-v*` polish release note ("clearer, more responsive feedback") — no dedicated announcement. Warning: feedback ≠ speed; this must not close out the performance story.

## Open Questions

- Global bar during TourProvider-driven nav: show (truthful) or suppress? Plan-time decision — default show.
- Pending-state escalation copy after N seconds ("still working…") on cancel/consent paths — exact threshold at plan time.
- Whether primitive family needs a determinate-progress variant (UploadProgress `-1`-sentinel precedent exists) — only if a sweep surface needs it.

## Non-Goals

- Server-side `/api/checkout` idempotency (deferred issue to be filed at Phase 3.6)
- `loading.tsx` skeleton expansion to missing routes (belongs to the parallel perf session)
- App latency fixes themselves (parallel session owns)
- Converting hard navs to soft navs (forbidden — ADR-067)
- New UI primitive library / shadcn migration (pre-existing non-goal convention)
