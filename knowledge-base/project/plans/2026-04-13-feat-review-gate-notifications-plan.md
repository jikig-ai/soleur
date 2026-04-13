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
Resend to the user's email (`auth.users.email` via Supabase admin client).

**Notification hierarchy:** WS (existing) > Push (new) > Email (new, fallback)

**Duplicate tolerance:** If a user reconnects between the offline check and push delivery,
they may receive both WS and push notifications. This is acceptable — a double notification
is better than no notification.

## Technical Approach

### Architecture

```text
Review gate fires (agent-runner.ts:876)
        │
        ▼
sendToClient() returns boolean     [MODIFY: return true if delivered]
        │
        ├── true: WS delivered (done)
        │
        └── false: user offline
                │
                ▼
         notifyOfflineUser(userId, payload)     [NEW, fire-and-forget]
                │
                ▼
         Query push_subscriptions for userId
                │
                ├── Has subscriptions ──► web-push.sendNotification() per device
                │                              │
                │                         On 410 Gone: DELETE that subscription
                │
                └── Zero subscriptions ──► Send email via Resend API
                                                │
                                           Inline HTML: agent name, question, deep link
```

### Implementation Phases

#### Phase 1: Core Implementation

**Infrastructure:**

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

**Server-side dispatch:**

6. Modify `sendToClient()` in `server/ws-handler.ts:112` to return `boolean` (true if
   delivered, false if no-op). Currently returns `void`.
7. Create `server/notifications.ts`:
   - `notifyOfflineUser(userId, payload)` — orchestrator: query subscriptions, push or email
   - `sendPushNotifications(subscriptions, payload)` — Web Push via `web-push`. On HTTP 410
     Gone response, delete the dead subscription from Supabase immediately.
   - `sendEmailNotification(userEmail, payload)` — Resend fallback. Email HTML inline in
     this module (no separate template file). Looks up email via Supabase admin client
     `auth.admin.getUserById(userId)`.
8. Create push subscription API route `app/api/push-subscription/route.ts`:
   - `POST` — subscribe (save subscription to Supabase)
   - `DELETE` — unsubscribe (remove subscription)
   - Auth via Supabase JWT middleware
9. Integrate at review gate trigger points in `server/agent-runner.ts`:
   - After `sendToClient()` at line 876: if returns false, call `notifyOfflineUser()` (no await — fire-and-forget)
   - Same pattern at line 950 (platform tool gates)
10. Update CSP `connect-src` in `lib/csp.ts:56` to add push service domains:
    - `https://fcm.googleapis.com` (Chrome)
    - `https://updates.push.services.mozilla.com` (Firefox)
    - `https://*.push.apple.com` (Safari)

**Client-side push + service worker:**

11. Extend `public/sw.js` with two new event handlers:
    - `push` — show notification with title, body, icon, deep link data
    - `notificationclick` — open/focus the app at `/dashboard/chat/{conversationId}`
12. Create `lib/push-subscription.ts`:
    - `subscribeToPush(registration)` — calls `registration.pushManager.subscribe()` with
      VAPID public key, POSTs to `/api/push-subscription`
    - `unsubscribeFromPush()` — removes subscription
13. Extend `app/sw-register.tsx` to chain push subscription after SW registration:
    - After `register()` resolves, check if user has push permission
    - If permitted and not yet subscribed, subscribe silently
14. Create `components/notification-prompt.tsx` (CPO-reviewed design):
    - Inline dismissible banner (not modal), neutral/blue border, visually distinct from
      review gate cards (amber)
    - Shown AFTER the first review gate resolves (not alongside — avoid dual-ask)
    - Copy: heading "Agents need you even when you're away." body "Enable notifications
      so you never miss a decision that blocks progress." CTA "Enable notifications",
      dismiss "Not now" (text link)
    - On "Enable": trigger `Notification.requestPermission()`, subscribe, set localStorage
      flag `notification-prompt-seen`
    - On dismiss: set flag, do not show again on this device
    - On ignore (scroll past): treat as not-seen, show again on next gate resolution
    - Maximum 2 shows total per device, then set flag permanently
    - On iOS Safari (not PWA): adjust copy to "Install Soleur to your home screen for
      push notifications" — do not trigger a permission request that will fail
    - After permission granted, subscribe immediately via `subscribeToPush()`
15. Integrate prompt into review gate flow in `lib/ws-client.ts`:
    - On `review_gate_response` (gate resolved), check localStorage flag + push state
    - If flag not set and shows < 2: render notification-prompt below resolved gate card

**Files to create/modify:**

- `apps/web-platform/supabase/migrations/020_push_subscriptions.sql` (create)
- `apps/web-platform/package.json` (modify — add dependencies)
- `apps/web-platform/server/ws-handler.ts` (modify — sendToClient returns boolean)
- `apps/web-platform/server/notifications.ts` (create)
- `apps/web-platform/app/api/push-subscription/route.ts` (create)
- `apps/web-platform/server/agent-runner.ts` (modify — add notification dispatch)
- `apps/web-platform/lib/csp.ts` (modify — add push domains to connect-src)
- `apps/web-platform/public/sw.js` (modify — add push + notificationclick handlers)
- `apps/web-platform/lib/push-subscription.ts` (create)
- `apps/web-platform/app/sw-register.tsx` (modify — chain push subscription)
- `apps/web-platform/components/notification-prompt.tsx` (create)
- `apps/web-platform/lib/ws-client.ts` (modify — show prompt on first review gate)

**Success criteria:** Full notification pipeline works end-to-end. Push or email delivered
when user is offline. Clicking notification opens correct conversation.

#### Phase 2: Legal + Compliance + Tests

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
   - `test/notifications.test.ts` — notification dispatch logic + 410 cleanup
   - `test/push-subscription-api.test.ts` — API route (subscribe, unsubscribe, auth)
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
| Separate email template module | Rejected | One email, one caller. Inline in notifications.ts. |
| Onboarding info card (soft ask) | Cut | YAGNI. Prompt after first gate resolution is sufficient. Browser manages permissions natively. |
| Show prompt alongside review gate | Rejected (CPO) | Dual-ask problem — user is already making a time-sensitive decision. Show after gate resolves instead. |
| Notification settings toggle | Cut | YAGNI. Browser provides notification settings. Build when a settings page exists with other content. |
| `isUserOnline()` function | Cut | Redundant with `sendToClient()` return value. Avoid parallel state checks that can drift. |
| Notification batching | Deferred to P4 | Premature with 0-1 users. |

## Acceptance Criteria

### Functional Requirements

- [x] Offline user receives push notification when review gate fires
- [x] Push notification includes agent name and decision summary
- [x] Clicking push notification opens `/dashboard/chat/{conversationId}`
- [x] User with zero push subscriptions receives email via Resend
- [x] Email includes actionable summary and deep link to conversation
- [x] First review gate resolution shows contextual push permission prompt (after gate, not during)
- [x] Notification prompt shown max 2 times per device, then stops
- [x] Multiple devices can subscribe to push for same user
- [x] Push notifications are fire-and-forget (do not block review gate timeout)
- [x] Dead push subscriptions (410 Gone) are deleted immediately

### Non-Functional Requirements

- [x] CSP `connect-src` updated with push service endpoints
- [x] VAPID keys stored in Doppler (not hardcoded)
- [x] Push subscriptions protected by RLS (users access own rows only)
- [x] Resend DPA verified/signed before merge

### Quality Gates

- [x] All existing tests pass (no regressions)
- [x] New tests for notification dispatch, 410 cleanup, API route, and CSP
- [x] Privacy Policy, DPD updated with new processing activities
- [x] Compliance posture updated for Resend

## Test Scenarios

### Acceptance Tests

- Given a user with an active WS connection, when a review gate fires, then the notification is delivered via WS only (no push or email)
- Given a user with no active WS and push subscriptions, when a review gate fires, then push notifications are sent to all registered devices
- Given a user with no active WS and zero push subscriptions, when a review gate fires, then an email is sent via Resend to the user's auth.users.email
- Given a user clicking a push notification, when the app opens, then it navigates to `/dashboard/chat/{conversationId}`
- Given the first review gate for a user without push, when the gate resolves, then a notification permission prompt appears below the resolved gate card

### Edge Cases

- Given a push endpoint returning HTTP 410 Gone, when push delivery fails, then that subscription is deleted from the database
- Given a user who denied browser push permission, when a review gate fires, then email is sent (zero subscriptions)
- Given a review gate that times out (5 min), when the user was offline the entire time, then the agent times out normally (notification does not extend timeout)
- Given multiple review gates firing in quick succession, when user is offline, then each gate sends its own notification (no batching for P3)
- Given a user reconnecting while push is in-flight, when both WS and push deliver, then duplicate notifications are acceptable

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
| User email lookup | `auth.users.email` via Supabase admin client | For email fallback |
| Test runner | Vitest | Use for new tests |

## Risk Analysis and Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| iOS push requires PWA home-screen install | High | Medium | Email fallback covers all iOS users. Most will start with email. |
| Browser permission denial | Medium | Low | Contextual prompt at first review gate. Denied users get email. |
| Push subscription endpoint rot | Medium | Low | Delete on 410 Gone. `last_used_at` column for future bulk cleanup. |
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

**Tier:** blocking (mechanical escalation: `components/notification-prompt.tsx` is a new component file)
**Decision:** reviewed
**Agents invoked:** cpo, ux-design-lead
**Skipped specialists:** none
**Pencil available:** yes

#### Findings

**CPO (post-plan review):** Show notification prompt AFTER the review gate resolves, not alongside it. Dual-ask (gate question + permission request) splits attention on a time-sensitive decision. "You almost missed this" framing after resolution is a natural contextual hook. Inline dismissible banner (not modal), neutral/blue border. Max 2 shows per device, then stop. On iOS Safari without PWA: adjust copy to explain home-screen install requirement. Copy: "Agents need you even when you're away." / "Enable notifications so you never miss a decision that blocks progress." / CTA "Enable notifications" / dismiss "Not now" (text link).

**UX design lead:** 4 wireframes delivered to `knowledge-base/product/design/notifications/screenshots/`. Design file: `notification-permission-prompt.pen`. Key decisions: inline blue banner below amber review gate card (color differentiation), 3 states (default, granted with auto-dismiss, denied with "We'll email you instead" fallback message), mobile-responsive with stacked buttons. Dismissible via X button and "Not now" text link.

## References and Research

### Internal References

- Review gate trigger: `apps/web-platform/server/agent-runner.ts:876-885`
- Platform tool gate: `apps/web-platform/server/agent-runner.ts:950`
- WS send function: `apps/web-platform/server/ws-handler.ts:112-116`
- Service worker: `apps/web-platform/public/sw.js`
- SW registration: `apps/web-platform/app/sw-register.tsx`
- CSP config: `apps/web-platform/lib/csp.ts:56`
- Manifest: `apps/web-platform/app/manifest.ts`
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

[Updated 2026-04-13] Plan simplified after 3-reviewer feedback: merged 5 phases to 2,
cut onboarding info card and settings toggle (YAGNI), inlined email template, removed
isUserOnline() in favor of sendToClient() return value, added 410 Gone handling for dead
subscriptions, documented email lookup path and duplicate notification tolerance.
