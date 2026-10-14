# Review Gate Notifications Brainstorm

**Date:** 2026-04-13
**Issue:** [#1049](https://github.com/jikig-ai/soleur/issues/1049)
**Branch:** `feat-review-gate-notifications`
**Status:** Decided

## What We're Building

Push notifications (Web Push API) and email fallback (Resend) for review gate events. When an agent hits a review gate and the user is offline (no active WebSocket), they receive a push notification or email with enough context to decide whether to open the app.

### Notification hierarchy

1. **WebSocket** (active session) -- existing, works today
2. **Push notification** (browser/PWA) -- new, requires subscription
3. **Email** (Resend) -- fallback when user has zero push subscriptions

## Why This Approach

Server-side dispatch from `agent-runner.ts` (Approach A). When the review gate fires, the server already knows whether the user has an active WS connection (`sendToClient()` no-ops if not). Adding push/email dispatch at the same point is a minimal, fire-and-forget addition.

Rejected alternatives:

- **Queue-based service (BullMQ/Redis):** YAGNI for P3 with 0-1 users. Introduce if needed in P4.
- **Supabase Edge Function + DB trigger:** Adds latency (cold start), splits logic across runtimes, harder to debug.
- **FCM (Firebase Cloud Messaging):** Adds vendor dependency with no benefit -- all browsers accept standard Web Push via `web-push` library.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Push protocol | Web Push (not FCM) | No vendor lock-in. `web-push` npm handles VAPID signing + payload encryption. |
| Service worker | Extend existing `sw.js` | Already has app-shell caching. Add `push` + `notificationclick` handlers. |
| VAPID key storage | Doppler (`dev`/`prd`) | Follows existing secrets pattern. Public key embedded client-side. |
| Push subscription storage | Supabase `push_subscriptions` table | `(id, user_id, endpoint, p256dh, auth, created_at, last_used_at)`. RLS: own rows only. |
| Permission prompt timing | Soft ask (onboarding) + hard ask (first review gate) | Info card during onboarding educates without triggering browser prompt. First review gate triggers the actual permission request with contextual motivation. |
| Notification content | Actionable summary | Push: agent name + decision needed. Email: same + deep link. Enough context to decide without opening the app. |
| Email fallback trigger | Zero push subscriptions | If user has no subscriptions, send email immediately. No delivery-failure tracking for P3. |
| Email provider | Resend (direct API) | DNS already configured (SPF/DKIM/DMARC). API key in Doppler `prd`. Need to add to `dev`. |
| CSP updates | `connect-src` in `lib/csp.ts` | Add push service endpoints. `worker-src 'self'` already present. |
| Notification preferences | Simple on/off toggle | No full preferences page for P3. Email default-on for users without push. |
| Batching | None for P3 | With 0-1 users, batching is premature. Track as P4 consideration if needed. |

## Open Questions

1. **Resend DPA:** Currently "NOT IN SCOPE" in compliance posture. Need to verify/sign before go-live. Check if accepted via Resend ToS.
2. **Email template design:** What does the review gate email look like? Minimal HTML or branded template?
3. **Deep link structure:** What URL pattern for linking directly to a conversation's review gate? Likely `/chat/<conversation_id>`.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Medium complexity (3-4 days). Use Web Push directly, extend existing SW, VAPID in Doppler. Key risk: iOS push only works with home-screen PWA installation -- cannot detect server-side. First email-sending capability in the web platform. Recommends an ADR for the push/email notification infrastructure pattern.

### Product (CPO)

**Summary:** Necessary for Phase 3 exit criteria. Email may be the de facto primary channel initially since most iOS users won't have PWA installed on day one. Permission prompt timing is critical UX -- contextual prompt at first review gate preferred over onboarding to avoid reflexive denials. Deep linking to specific conversation is a quality differentiator.

### Marketing (CMO)

**Summary:** Not announcement-worthy standalone -- bundle into Phase 3 rollup. Marketing value is retention framing (commitment + consistency): founders who set up review gates have committed to human-in-the-loop, notifications reduce friction to honoring that commitment. No capability gaps.

### Legal (CLO)

**Summary:** Two new processing activities require disclosure: push subscriptions (consent via browser prompt, GDPR Art. 6(1)(a)) and transactional email via Resend (legitimate interest, Art. 6(1)(b)). Resend DPA must be signed (Art. 28). Privacy Policy, DPD, and GDPR register need updates. Push subscription endpoints are personal data under GDPR.

## Capability Gaps

None reported. All required tools and infrastructure patterns exist or can be added with standard npm packages (`web-push`, `resend`).
