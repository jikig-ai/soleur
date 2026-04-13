# Tasks: Review Gate Notifications

**Plan:** `knowledge-base/project/plans/2026-04-13-feat-review-gate-notifications-plan.md`
**Issue:** [#1049](https://github.com/jikig-ai/soleur/issues/1049)

## Phase 1: Infrastructure

- [ ] 1.1 Generate VAPID key pair (`npx web-push generate-vapid-keys`)
- [ ] 1.2 Store `VAPID_PUBLIC_KEY` and `VAPID_PRIVATE_KEY` in Doppler `dev` and `prd` configs
- [ ] 1.3 Add `RESEND_API_KEY` to Doppler `dev` config (already in `prd`)
- [ ] 1.4 Install `web-push`, `@types/web-push`, and `resend` in `apps/web-platform/`
- [ ] 1.5 Regenerate `package-lock.json` and `bun.lock`
- [ ] 1.6 Create migration `supabase/migrations/020_push_subscriptions.sql`
  - [ ] 1.6.1 `push_subscriptions` table (id, user_id, endpoint, p256dh, auth, created_at, last_used_at)
  - [ ] 1.6.2 RLS policies (SELECT, INSERT, DELETE, UPDATE — own rows only)
  - [ ] 1.6.3 UNIQUE constraint on (user_id, endpoint)

## Phase 2: Server-Side Dispatch

- [ ] 2.1 Create `server/notifications.ts`
  - [ ] 2.1.1 `isUserOnline(userId)` — check WS session state
  - [ ] 2.1.2 `sendPushNotifications(subscriptions, payload)` — Web Push via `web-push`
  - [ ] 2.1.3 `sendEmailNotification(userId, payload)` — Resend fallback
  - [ ] 2.1.4 `notifyOfflineUser(userId, payload)` — orchestrator (push or email)
- [ ] 2.2 Create `server/email-templates.ts` — review gate email HTML
- [ ] 2.3 Create `app/api/push-subscription/route.ts`
  - [ ] 2.3.1 POST handler (subscribe)
  - [ ] 2.3.2 DELETE handler (unsubscribe)
  - [ ] 2.3.3 Auth middleware (Supabase JWT)
- [ ] 2.4 Integrate notification dispatch in `server/agent-runner.ts`
  - [ ] 2.4.1 After `sendToClient()` at line 876 (AskUserQuestion gates)
  - [ ] 2.4.2 After `sendToClient()` at line 950 (platform tool gates)
- [ ] 2.5 Update CSP `connect-src` in `lib/csp.ts:56`
  - [ ] 2.5.1 Add `https://fcm.googleapis.com`
  - [ ] 2.5.2 Add `https://updates.push.services.mozilla.com`
  - [ ] 2.5.3 Add `https://*.push.apple.com`

## Phase 3: Client-Side Push + Service Worker

- [ ] 3.1 Extend `public/sw.js`
  - [ ] 3.1.1 Add `push` event handler (show notification with title, body, icon, data)
  - [ ] 3.1.2 Add `notificationclick` handler (open/focus at `/dashboard/chat/{id}`)
- [ ] 3.2 Create `lib/push-subscription.ts`
  - [ ] 3.2.1 `subscribeToPush(registration)` — PushManager.subscribe + POST to API
  - [ ] 3.2.2 `unsubscribeFromPush()` — remove subscription
  - [ ] 3.2.3 `getPushPermissionState()` — return current state
- [ ] 3.3 Extend `app/sw-register.tsx` — chain push subscription after SW registration
- [ ] 3.4 Create `components/notification-prompt.tsx`
  - [ ] 3.4.1 Contextual prompt UI ("Enable notifications so you don't miss agent decisions")
  - [ ] 3.4.2 Handle granted/denied/default states
  - [ ] 3.4.3 Trigger browser permission request on user action

## Phase 4: Onboarding + UX Integration

- [ ] 4.1 Add notification info card to `app/(auth)/setup-key/page.tsx`
  - [ ] 4.1.1 Non-blocking card after BYOK setup
  - [ ] 4.1.2 "Got it" dismiss button
- [ ] 4.2 Integrate prompt into review gate flow
  - [ ] 4.2.1 Show `notification-prompt.tsx` on first review gate (localStorage flag)
  - [ ] 4.2.2 Subscribe after permission granted

## Phase 5: Legal + Compliance + Tests

- [ ] 5.1 Verify/sign Resend DPA
- [ ] 5.2 Update `knowledge-base/legal/compliance-posture.md` (Resend row)
- [ ] 5.3 Update Privacy Policy — add push subscription + email processing activities
- [ ] 5.4 Update DPD — add processing activity entries
- [ ] 5.5 Write tests
  - [ ] 5.5.1 `test/notifications.test.ts` — notification dispatch logic
  - [ ] 5.5.2 `test/push-subscription-api.test.ts` — API route (subscribe, unsubscribe, auth)
  - [ ] 5.5.3 Update `test/csp.test.ts` — new connect-src domains
  - [ ] 5.5.4 Update `test/security-headers.test.ts` — push domains
