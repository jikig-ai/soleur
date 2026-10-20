# Tasks: fix Stripe webhook Inngest send failure (#10542)

Plan: knowledge-base/project/plans/2026-10-20-fix-stripe-webhook-inngest-send-failure-plan.md

## Phase 1: RED tests (apps/web-platform/test/server/webhooks/stripe-payment-failed-inngest.test.ts)

- 1.1 Model `processed_stripe_events` with a `claimed` Set in `beforeEach` (stateful `mockInsert` 23505, `mockDeleteEq` removes id and resolves `{ error: null }`)
- 1.2 Rewrite the "Inngest unreachable" test as T1 (500, `{error:"Dispatch failed"}`, release called with `("event_id","evt_pf_001")`, report with `stripe-webhook` / `inngest-send-payment-failed`, `extra.userId`, no "will retry")
- 1.3 Rewrite the "retries exhaust" test as T2 (3 attempts, real timers, 500, one release, one report)
- 1.4 Add T3 (failure then redelivery re-sends; two `inngest.send` calls)
- 1.5 Add T4 (release fails: still 500, release failure logged with eventId, redelivery short-circuits with no send)
- 1.6 Strengthen the existing success test (no release, no failure report)
- 1.7 Update the header contract comment and drop stale line-number references
- 1.8 Run the suite alone with stdin from /dev/null; confirm T1-T4 RED

## Phase 2: GREEN (apps/web-platform/app/api/webhooks/stripe/route.ts)

- 2.1 Catch block: `reportSilentFallback` (new tags, `userId: founderId`, no email hash) then `await releaseDedupRow()` then 500 `{ error: "Dispatch failed" }`
- 2.2 Two comment lines: Inngest 24 h event-id idempotency basis; 500-on-all with the `SOLEUR_FR5_ENABLED=false` escape
- 2.3 Replace stale comments (redelivery covers the gap; line 116/126 references); add the #10657 pointer above the ignored founder-lookup error
- 2.4 Re-run the target suite, then the three sibling Stripe suites one at a time (stdin /dev/null), then `./node_modules/.bin/tsc --noEmit`
- 2.5 `rg -n "will retry|upstream covers the gap"` on route.ts returns nothing

## Phase 3: Ship (stop before merge)

- 3.1 PR body: `Ref #10542`, `Ref #10136`, `Ref #10657`, `Closes #10542` in the body only, replay-check note, residual-risk note
- 3.2 `git grep -n "inngest-emit" -- knowledge-base` (runbooks) at ship; gdpr-gate advisory at work Phase 2 exit
- 3.3 Review, QA, push, mark ready, poll CI with Monitor until green
- 3.4 Do NOT run `gh pr merge`, do NOT arm auto-merge; report PR number and CI state and pause
