# Tasks: Review Gate Notifications

**Plan:** `knowledge-base/project/plans/2026-04-13-feat-review-gate-notifications-plan.md`
**Issue:** [#1049](https://github.com/jikig-ai/soleur/issues/1049)

## Phase 1: Core Implementation

### Infrastructure

- [ ] 1.1 Generate VAPID key pair (`npx web-push generate-vapid-keys`)
- [ ] 1.2 Store `VAPID_PUBLIC_KEY` and `VAPID_PRIVATE_KEY` in Doppler `dev` and `prd`
- [ ] 1.3 Add `RESEND_API_KEY` to Doppler `dev` config
- [ ] 1.4 Install `web-push`, `@types/web-push`, `resend` in `apps/web-platform/`
- [ ] 1.5 Regenerate `package-lock.json` and `bun.lock`
- [ ] 1.6 Create migration `supabase/migrations/020_push_subscriptions.sql`

### Server-Side Dispatch

- [ ] 1.7 Modify `sendToClient()` to return `boolean` (true = delivered, false = no-op)
- [ ] 1.8 Create `server/notifications.ts`
  - [ ] 1.8.1 `notifyOfflineUser(userId, payload)` — orchestrator
  - [ ] 1.8.2 `sendPushNotifications(subscriptions, payload)` — Web Push + 410 cleanup
  - [ ] 1.8.3 `sendEmailNotification(userEmail, payload)` — Resend with inline HTML
- [ ] 1.9 Create `app/api/push-subscription/route.ts` (POST subscribe, DELETE unsubscribe)
- [ ] 1.10 Integrate in `server/agent-runner.ts` (line 876 + line 950)
- [ ] 1.11 Update CSP `connect-src` in `lib/csp.ts`

### Client-Side Push + Service Worker

- [ ] 1.12 Extend `public/sw.js` (push + notificationclick handlers)
- [ ] 1.13 Create `lib/push-subscription.ts` (subscribeToPush, unsubscribeFromPush)
- [ ] 1.14 Extend `app/sw-register.tsx` (chain push subscription after registration)
- [ ] 1.15 Create `components/notification-prompt.tsx` (contextual prompt at first gate)
- [ ] 1.16 Integrate prompt in `lib/ws-client.ts` (show on first review_gate message)

## Phase 2: Legal + Compliance + Tests

- [ ] 2.1 Verify/sign Resend DPA
- [ ] 2.2 Update `knowledge-base/legal/compliance-posture.md` (Resend row)
- [ ] 2.3 Update Privacy Policy — push subscription + email processing activities
- [ ] 2.4 Update DPD — processing activity entries
- [ ] 2.5 `test/notifications.test.ts` — dispatch logic + 410 cleanup
- [ ] 2.6 `test/push-subscription-api.test.ts` — API route (subscribe, unsubscribe, auth)
- [ ] 2.7 Update `test/csp.test.ts` — new connect-src domains
- [ ] 2.8 Update `test/security-headers.test.ts` — push domains
