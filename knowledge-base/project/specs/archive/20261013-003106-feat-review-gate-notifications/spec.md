# Spec: Review Gate Notifications

**Issue:** [#1049](https://github.com/jikig-ai/soleur/issues/1049)
**Phase:** 3 (Make it Sticky)
**Priority:** P2
**Branch:** `feat-review-gate-notifications`

## Problem Statement

When a review gate fires and the user has no active WebSocket connection (app backgrounded, browser closed), the gate silently blocks agent progress. The user has no way to know an agent needs their input unless they actively check the conversation inbox. This breaks the core CaaS async workflow: trigger agents, step away, return when needed.

## Goals

1. Notify offline users when a review gate fires within seconds
2. Support all platforms: Android (push), desktop Chrome/Firefox/Edge (push), iOS (push if PWA installed, email if not)
3. Provide enough context in the notification for the founder to decide whether to act immediately
4. Maintain a simple notification hierarchy: WS > Push > Email

## Non-Goals

- Full notification preferences UI (simple on/off toggle only for P3)
- Notification batching (premature with 0-1 users)
- Queue-based notification infrastructure (YAGNI for P3)
- Offline agent execution or offline mode
- SMS or other notification channels

## Functional Requirements

| ID | Requirement |
|----|-------------|
| FR1 | When a review gate fires and the user has no active WS connection, the server dispatches a push notification to all registered devices |
| FR2 | If the user has zero push subscriptions, the server sends a transactional email via Resend |
| FR3 | Push notification includes: agent/domain leader name, summary of what decision is needed |
| FR4 | Email includes the same content as push plus a deep link to the conversation |
| FR5 | Clicking a push notification opens the app at the relevant conversation |
| FR6 | Users see an informational card about notifications during onboarding (soft ask, no browser prompt) |
| FR7 | The first time a review gate fires, users without push enabled see a contextual permission prompt |
| FR8 | Users can subscribe to push from multiple devices |
| FR9 | Push notifications are fire-and-forget -- they do not block the review gate timeout |

## Technical Requirements

| ID | Requirement |
|----|-------------|
| TR1 | Use Web Push protocol directly via `web-push` npm library (not FCM) |
| TR2 | VAPID key pair stored in Doppler (`dev` and `prd` configs) |
| TR3 | Push subscriptions stored in Supabase `push_subscriptions` table with RLS (own rows only) |
| TR4 | Extend existing `public/sw.js` with `push` and `notificationclick` event handlers |
| TR5 | CSP `connect-src` in `lib/csp.ts` updated with push service endpoints |
| TR6 | Email sent via Resend API (not SMTP). `RESEND_API_KEY` in Doppler `dev` and `prd` |
| TR7 | Notification dispatch integrated at `agent-runner.ts` review gate trigger point (around line 297) |
| TR8 | Privacy Policy, DPD, and GDPR register updated with two new processing activities |
| TR9 | Resend DPA verified/signed and compliance posture updated |

## Integration Points

| System | Integration |
|--------|-------------|
| `server/agent-runner.ts:297-302` | Trigger point: `sendToClient()` with `type: "review_gate"`. Add push/email dispatch when WS is not connected |
| `server/ws-handler.ts:49` | WS connection check: `if (!session \|\| session.ws.readyState !== WebSocket.OPEN) return` -- this is where we detect offline |
| `public/sw.js` | Add `push` event listener and `notificationclick` handler |
| `lib/csp.ts` | Add push service domains to `connect-src` directive |
| `middleware.ts` | CSP middleware already applies `withCspHeaders()` -- no changes needed |
| `supabase/migrations/` | New migration for `push_subscriptions` table |

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| iOS push unreliable without PWA install | High | Medium | Email fallback is the primary channel for iOS until PWA adoption grows |
| Push subscription rot (expired endpoints) | Medium | Low | `last_used_at` column enables future cleanup. For P3, stale subscriptions just fail silently |
| Resend DPA not yet signed | Low | High | Verify before merge. Resend likely has standard DPA via ToS |
| Browser permission denial rate | Medium | Low | Contextual first-review-gate prompt reduces reflexive denials. Email fallback covers denied users |
