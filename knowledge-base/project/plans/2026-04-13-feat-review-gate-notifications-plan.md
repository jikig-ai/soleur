---
title: "feat: Review Gate Notifications (PWA Push + Email Fallback)"
type: feat
date: 2026-04-13
---

# feat: Review Gate Notifications (PWA Push + Email Fallback)

## Overview

When a review gate fires and the user is offline (no active WebSocket), the gate silently
blocks agent progress. This feature adds push notifications (Web Push API) and email fallback
(Resend) so offline users know immediately when an agent needs their input.

**Issue:** [#1049](https://github.com/jikig-ai/soleur/issues/1049)
**Brainstorm:** `knowledge-base/project/brainstorms/2026-04-13-review-gate-notifications-brainstorm.md`
**Spec:** `knowledge-base/project/specs/feat-review-gate-notifications/spec.md`

## Problem Statement

`sendToClient()` in `server/ws-handler.ts:112-116` silently no-ops when the user has no
active WebSocket connection. Review gate messages (`type: "review_gate"`) are dropped entirely.
The agent blocks on `abortableReviewGate()` for 5 minutes, then times out. The user never
knows a gate fired unless they happen to check the conversation inbox.

## Proposed Solution

Server-side fire-and-forget notification dispatch. When the review gate fires in
`server/agent-runner.ts:876-885`, if the user has no active WS connection, dispatch push
notification to all registered devices. If zero push subscriptions exist, send email via
Resend. The notification includes an actionable summary (agent name + decision needed) with
a deep link to `/dashboard/chat/{conversationId}`.

**Notification hierarchy:** WS (existing) > Push (new) > Email (new, fallback)

## Technical Approach

### Architecture

```text
Review gate fires (agent-runner.ts:876)
        │
        ▼
sendToClient() ──► WS open? ──► Yes: deliver via WS (existing)
        │                              │
        No                             ▼
        │                        User sees gate in UI
        ▼
notifyOfflineUser(userId, payload)     [NEW]
        │
        ▼
Query push_subscriptions for userId
        │
        ├── Has subscriptions ──► web-push.sendNotification() to each device
        │                              │
        │                         Fire-and-forget (don't await delivery)
        │
        └── Zero subscriptions ──► Send email via Resend API
                                        │
                                   Template: agent name, question, deep link
```

### Implementation Phases

#### Phase 1: Infrastructure (VAPID + Migration + Dependencies)

**Tasks:**

1. Generate VAPID key pair: `npx web-push generate-vapid-keys`
2. Store in Doppler: `VAPID_PUBLIC_KEY` and `VAPID_PRIVATE_KEY` in both `dev` and `prd` configs
3. Add `RESEND_API_KEY` to Doppler `dev` config (already in `prd`)
4. Install dependencies in `apps/web-platform/`:
   - `web-push` (server-side push sending + VAPID signing)
   - `resend` (email API client)
   - `@types/web-push` (TypeScript definitions)
5. Create Supabase migration `020_push_subscriptions.sql`:

```sql
-- Push notification subscriptions for review gate notifications
CREATE TABLE public.push_subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  endpoint TEXT NOT NULL,
  p256dh TEXT NOT NULL,
  auth TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_used_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, endpoint)
);

-- RLS: users can only manage their own subscriptions
ALTER TABLE public.push_subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own subscriptions"
  ON public.push_subscriptions FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own subscriptions"
  ON public.push_subscriptions FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own subscriptions"
  ON public.push_subscriptions FOR DELETE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can update own subscriptions"
  ON public.push_subscriptions FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
```

**Files to create/modify:**

- `apps/web-platform/supabase/migrations/020_push_subscriptions.sql` (create)
- `apps/web-platform/package.json` (add dependencies)
- `apps/web-platform/package-lock.json` (regenerate)
- `bun.lock` (regenerate)

**Success criteria:** Dependencies installed, VAPID keys in Doppler, migration file ready.

#### Phase 2: Server-Side Push + Email Dispatch

**Tasks:**

1. Create `server/notifications.ts` — notification dispatch module:
   - `notifyOfflineUser(userId, payload)` — main entry point
   - `sendPushNotifications(subscriptions, payload)` — Web Push via `web-push`
   - `sendEmailNotification(userId, payload)` — Resend fallback
   - `isUserOnline(userId)` — checks WS session state
2. Create `server/email-templates.ts` — review gate email HTML template
3. Create push subscription API route `app/api/push-subscription/route.ts`:
   - `POST` — subscribe (save subscription to Supabase)
   - `DELETE` — unsubscribe (remove subscription)
   - Auth via Supabase JWT middleware
4. Integrate at review gate trigger points in `server/agent-runner.ts`:
   - After `sendToClient()` at line 876, add: if user is offline, call `notifyOfflineUser()`
   - Same pattern at line 950 (platform tool gates)
5. Update CSP `connect-src` in `lib/csp.ts:56` to add push service domains:
   - `https://fcm.googleapis.com` (Chrome)
   - `https://updates.push.services.mozilla.com` (Firefox)
   - `https://*.push.apple.com` (Safari)

**Files to create/modify:**

- `apps/web-platform/server/notifications.ts` (create)
- `apps/web-platform/server/email-templates.ts` (create)
- `apps/web-platform/app/api/push-subscription/route.ts` (create)
- `apps/web-platform/server/agent-runner.ts` (modify — add notification dispatch)
- `apps/web-platform/lib/csp.ts` (modify — add push domains to connect-src)
- `apps/web-platform/lib/types.ts` (modify — add PushSubscription type if needed)

**Success criteria:** Server can send push notifications and emails. API route accepts subscriptions.

#### Phase 3: Client-Side Push Subscription + Service Worker

**Tasks:**

1. Extend `public/sw.js` with two new event handlers:
   - `push` — show notification with title, body, icon, deep link data
   - `notificationclick` — open/focus the app at `/dashboard/chat/{conversationId}`
2. Create `lib/push-subscription.ts` — client-side subscription logic:
   - `subscribeToPush(registration)` — calls `registration.pushManager.subscribe()` with VAPID public key, POSTs to `/api/push-subscription`
   - `unsubscribeFromPush()` — removes subscription
   - `getPushPermissionState()` — returns current permission state
3. Extend `app/sw-register.tsx` to chain push subscription after SW registration:
   - After `register()` resolves, check if user has push permission
   - If permitted and not yet subscribed, subscribe silently
4. Create notification prompt component `components/notification-prompt.tsx`:
   - Contextual in-app prompt shown when first review gate fires
   - "Enable notifications so you don't miss agent decisions"
   - Triggers browser permission request on user action
   - Handles denied/granted/default states

**Files to create/modify:**

- `apps/web-platform/public/sw.js` (modify — add push + notificationclick handlers)
- `apps/web-platform/lib/push-subscription.ts` (create)
- `apps/web-platform/app/sw-register.tsx` (modify — chain push subscription)
- `apps/web-platform/components/notification-prompt.tsx` (create)

**Success criteria:** User can subscribe to push, SW shows notifications, clicking opens correct conversation.

#### Phase 4: Onboarding Info Card + Review Gate Integration

**Tasks:**

1. Create onboarding notification info card for `app/(auth)/setup-key/page.tsx`:
   - Non-blocking info card shown after BYOK setup
   - Explains push notifications without triggering browser prompt
   - "You'll be notified when agents need your input" messaging
   - Dismissed via "Got it" button, continues to `/connect-repo`
2. Integrate notification prompt into review gate UI:
   - When first review gate fires and user has no push subscription, show `notification-prompt.tsx` alongside the review gate question
   - Track "first gate shown" state (localStorage flag)
   - After permission granted, subscribe immediately
3. Add notification toggle to user settings (if settings page exists):
   - Simple on/off toggle for push notifications
   - Shows current permission state
   - Unsubscribe removes all push subscriptions for this device

**Files to create/modify:**

- `apps/web-platform/app/(auth)/setup-key/page.tsx` (modify — add info card)
- `apps/web-platform/lib/ws-client.ts` (modify — show prompt on first review gate)
- `apps/web-platform/components/notification-prompt.tsx` (modify — integrate with gate)

**Success criteria:** Onboarding shows notification info. First review gate triggers permission prompt.

#### Phase 5: Legal + Compliance + Tests

**Tasks:**

1. Verify Resend DPA status (check ToS for standard DPA acceptance)
2. Update `knowledge-base/legal/compliance-posture.md`:
   - Move Resend from "NOT IN SCOPE" to active with DPA status
3. Update Privacy Policy (`docs/legal/privacy-policy.md`):
   - Add push subscription data processing (Section 4.7 or new subsection)
   - Add Resend email processing activity
4. Update DPD and GDPR register:
   - Two new processing activities (push subscriptions + transactional email)
5. Write tests:
   - `test/notifications.test.ts` — unit tests for notification dispatch logic
   - `test/push-subscription-api.test.ts` — API route tests (subscribe, unsubscribe, auth)
   - `test/csp.test.ts` — update existing CSP tests for new connect-src domains
   - `test/security-headers.test.ts` — verify push domains in security headers

**Files to create/modify:**

- `knowledge-base/legal/compliance-posture.md` (modify)
- `docs/legal/privacy-policy.md` (modify)
- `docs/legal/data-protection-disclosure.md` (modify)
- `apps/web-platform/test/notifications.test.ts` (create)
- `apps/web-platform/test/push-subscription-api.test.ts` (create)
- `apps/web-platform/test/csp.test.ts` (modify)
- `apps/web-platform/test/security-headers.test.ts` (modify)

**Success criteria:** Legal docs updated, DPA verified, all tests pass.

## Alternative Approaches Considered

| Approach | Decision | Rationale |
|----------|----------|-----------|
| FCM (Firebase Cloud Messaging) | Rejected | Vendor lock-in. All browsers accept standard Web Push. |
| Queue-based dispatch (BullMQ/Redis) | Rejected | YAGNI for P3 with 0-1 users. |
| Supabase Edge Function + DB trigger | Rejected | Adds latency, splits logic across runtimes. |
| Ask permission during signup | Rejected | Reflexive denial. Contextual prompt at first review gate is better. |
| Notification batching | Deferred to P4 | Premature with 0-1 users. |

## Acceptance Criteria

### Functional Requirements

- [ ] Offline user receives push notification when review gate fires
- [ ] Push notification includes agent name and decision summary
- [ ] Clicking push notification opens `/dashboard/chat/{conversationId}`
- [ ] User with zero push subscriptions receives email via Resend
- [ ] Email includes actionable summary and deep link to conversation
- [ ] Onboarding shows notification info card (soft ask, no browser prompt)
- [ ] First review gate triggers contextual push permission prompt
- [ ] Multiple devices can subscribe to push for same user
- [ ] Push notifications are fire-and-forget (do not block review gate timeout)

### Non-Functional Requirements

- [ ] CSP `connect-src` updated with push service endpoints
- [ ] VAPID keys stored in Doppler (not hardcoded)
- [ ] Push subscriptions protected by RLS (users access own rows only)
- [ ] Resend DPA verified/signed before merge

### Quality Gates

- [ ] All existing tests pass (no regressions)
- [ ] New tests for notification dispatch, API route, and CSP
- [ ] Privacy Policy, DPD updated with new processing activities
- [ ] Compliance posture updated for Resend

## Test Scenarios

### Acceptance Tests

- Given a user with an active WS connection, when a review gate fires, then the notification is delivered via WS only (no push or email)
- Given a user with no active WS and push subscriptions, when a review gate fires, then push notifications are sent to all registered devices
- Given a user with no active WS and zero push subscriptions, when a review gate fires, then an email is sent via Resend
- Given a user clicking a push notification, when the app opens, then it navigates to `/dashboard/chat/{conversationId}`
- Given a new user completing BYOK setup, when they see the info card, then no browser permission prompt is shown
- Given the first review gate for a user without push, when the gate fires, then a contextual permission prompt appears alongside the gate question

### Edge Cases

- Given a user with expired push subscriptions, when push fails, then the failure is silent (no crash, no email fallback for P3)
- Given a user who denied browser push permission, when a review gate fires, then email is sent (zero subscriptions)
- Given a review gate that times out (5 min), when the user was offline the entire time, then the agent times out normally (notification does not extend timeout)
- Given multiple review gates firing in quick succession, when user is offline, then each gate sends its own notification (no batching for P3)

### Integration Verification

- **API verify (subscribe):** `curl -s -X POST http://localhost:3000/api/push-subscription -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{"endpoint":"https://test.push.example","keys":{"p256dh":"test","auth":"test"}}' | jq .` expects `{"success": true}`
- **API verify (list):** `curl -s http://localhost:3000/api/push-subscription -H "Authorization: Bearer $TOKEN" | jq '. | length'` expects >= 1
- **CSP verify:** `curl -sI http://localhost:3000 | grep -i content-security-policy | grep fcm.googleapis.com`

## Dependencies and Prerequisites

| Dependency | Status | Action Required |
|------------|--------|-----------------|
| Service worker (`public/sw.js`) | Exists | Extend with push + notificationclick |
| PWA manifest (`app/manifest.ts`) | Exists | No changes needed |
| SW registration (`app/sw-register.tsx`) | Exists | Extend with push subscription chain |
| Resend DNS (SPF/DKIM/DMARC) | Configured | None |
| `RESEND_API_KEY` in Doppler `prd` | Exists | Also add to `dev` |
| `RESEND_API_KEY` in Doppler `dev` | Missing | Generate/copy from prd |
| Resend DPA | NOT IN SCOPE | Verify/sign before merge |
| `web-push` npm package | Not installed | Install in Phase 1 |
| `resend` npm package | Not installed | Install in Phase 1 |
| Supabase migration pattern | Established (019 latest) | New migration 020 |
| Review gate mechanism | Implemented | Integration point at agent-runner.ts:876 |
| CSP infrastructure (`lib/csp.ts`) | Implemented | Add push domains to connect-src |
| Conversation URL routing | `/dashboard/chat/[conversationId]` | Use for deep links |
| Test runner | Vitest | Use for new tests |

## Risk Analysis and Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| iOS push requires PWA home-screen install | High | Medium | Email fallback covers all iOS users. Most will start with email. |
| Browser permission denial | Medium | Low | Contextual prompt at first review gate. Denied users get email. |
| Push subscription endpoint rot | Medium | Low | `last_used_at` column for future cleanup. Silent failure for P3. |
| Resend DPA not signed | Low | High | Check ToS for standard DPA. Escalate to founder if manual signing needed. |
| Lockfile conflicts (bun.lock + package-lock.json) | Medium | Low | Regenerate both after dependency install. Dockerfile uses `npm ci`. |

## Domain Review

**Domains relevant:** Engineering, Product, Marketing, Legal

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Medium complexity, 3-4 days. Web Push directly (not FCM). Extend existing SW. VAPID in Doppler. First email-sending capability in web platform. Recommends ADR for notification infrastructure pattern.

### Marketing (CMO)

**Status:** reviewed
**Assessment:** Not announcement-worthy standalone. Bundle into Phase 3 rollup. Marketing value is retention framing — notifications reduce friction for founders who committed to human-in-the-loop review gates.

### Legal (CLO)

**Status:** reviewed
**Assessment:** Two new processing activities. Push subscriptions = consent (Art. 6(1)(a)). Transactional email = legitimate interest (Art. 6(1)(b)). Resend DPA required (Art. 28). Update Privacy Policy, DPD, GDPR register.

### Product/UX Gate

**Tier:** advisory
**Decision:** reviewed (carry-forward from brainstorm)
**Agents invoked:** none (brainstorm carried forward CPO assessment)
**Skipped specialists:** ux-design-lead (advisory tier — notification prompt is a single component, not a multi-page flow)
**Pencil available:** N/A

#### Findings

CPO assessed: necessary for Phase 3 exit criteria. Permission prompt timing settled (soft ask + hard ask). Notification content settled (actionable summary). Deep linking to `/dashboard/chat/{conversationId}`. Simple on/off toggle for preferences. No full preferences UI for P3.

## References and Research

### Internal References

- Review gate trigger: `apps/web-platform/server/agent-runner.ts:876-885`
- WS send function: `apps/web-platform/server/ws-handler.ts:112-116`
- Service worker: `apps/web-platform/public/sw.js`
- SW registration: `apps/web-platform/app/sw-register.tsx`
- CSP config: `apps/web-platform/lib/csp.ts:56`
- Manifest: `apps/web-platform/app/manifest.ts`
- Onboarding redirect: `apps/web-platform/app/(auth)/setup-key/page.tsx`
- Conversation routing: `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`
- Review gate types: `apps/web-platform/lib/types.ts:62`
- Latest migration: `apps/web-platform/supabase/migrations/019_chat_attachments.sql`
- CSP tests: `apps/web-platform/test/csp.test.ts`

### Learnings Applied

- CSP is nonce-based via `lib/csp.ts`, not `next.config.ts` (`2026-03-20-nonce-based-csp-nextjs-middleware.md`)
- Review gate abort/timeout: use manual setTimeout, not AbortSignal.timeout() (`2026-03-20-review-gate-promise-leak-abort-timeout.md`)
- Resend DNS already configured for `soleur.ai` (`2026-03-18-supabase-resend-email-configuration.md`)
- Notification dispatch must be fire-and-forget to avoid coupling with abort pattern

### Related Issues

- #1042 — PWA manifest + service worker (closed, provides sw.js foundation)
- #1077 — Guided instructions fallback (also uses review gates)
- #2035 — Draft PR for this feature
