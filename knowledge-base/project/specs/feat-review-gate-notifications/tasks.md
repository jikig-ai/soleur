# Tasks: Review Gate Notifications

**Plan:** `knowledge-base/project/plans/2026-04-13-feat-review-gate-notifications-plan.md`
**Issue:** [#1049](https://github.com/jikig-ai/soleur/issues/1049)

## Phase 1: Core Implementation

### Infrastructure

- [x] 1.1 Generate VAPID key pair (`npx web-push generate-vapid-keys`)
- [x] 1.2 Store `VAPID_PUBLIC_KEY` and `VAPID_PRIVATE_KEY` in Doppler `dev` and `prd`
- [x] 1.3 Add `RESEND_API_KEY` to Doppler `dev` config
- [x] 1.4 Install `web-push`, `@types/web-push`, `resend` in `apps/web-platform/`
- [x] 1.5 Regenerate `package-lock.json` and `bun.lock`
- [x] 1.6 Create migration `supabase/migrations/020_push_subscriptions.sql`

### Server-Side Dispatch

- [x] 1.7 Modify `sendToClient()` to return `boolean` (true = delivered, false = no-op)
- [x] 1.8 Create `server/notifications.ts`
  - [x] 1.8.1 `notifyOfflineUser(userId, payload)` — orchestrator
  - [x] 1.8.2 `sendPushNotifications(subscriptions, payload)` — Web Push + 410 cleanup
  - [x] 1.8.3 `sendEmailNotification(userEmail, payload)` — Resend with inline HTML
- [x] 1.9 Create `app/api/push-subscription/route.ts` (POST subscribe, DELETE unsubscribe)
- [x] 1.10 Integrate in `server/agent-runner.ts` (line 876 + line 950)
- [x] 1.11 Update CSP `connect-src` in `lib/csp.ts`

### Client-Side Push + Service Worker

- [x] 1.12 Extend `public/sw.js` (push + notificationclick handlers)
- [x] 1.13 Create `lib/push-subscription.ts` (subscribeToPush, unsubscribeFromPush)
- [x] 1.14 Extend `app/sw-register.tsx` (chain push subscription after registration)
- [x] 1.15 Create `components/notification-prompt.tsx` (CPO-reviewed: inline banner after gate resolves, max 2 shows, iOS copy variant)
- [x] 1.16 Integrate prompt in `lib/ws-client.ts` (show after review_gate_response, not during gate)

## Phase 2: Legal + Compliance + Tests

- [x] 2.1 Verify/sign Resend DPA
- [x] 2.2 Update `knowledge-base/legal/compliance-posture.md` (Resend row)
- [x] 2.3 Update Privacy Policy — push subscription + email processing activities
- [x] 2.4 Update DPD — processing activity entries
- [x] 2.5 `test/notifications.test.ts` — dispatch logic + 410 cleanup
- [x] 2.6 `test/push-subscription-api.test.ts` — API route (subscribe, unsubscribe, auth)
- [x] 2.7 Update `test/csp.test.ts` — new connect-src domains
- [x] 2.8 Update `test/security-headers.test.ts` — push domains
