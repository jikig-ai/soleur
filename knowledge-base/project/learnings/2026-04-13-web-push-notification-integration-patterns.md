---
title: Web Push notification integration patterns
category: integration-issues
module: web-platform/notifications
date: 2026-04-13
tags: [web-push, vapid, service-worker, resend, email, xss, csp]
---

# Learning: Web Push notification integration patterns

## Problem

Implementing Web Push API notifications with email fallback for offline users required coordinating multiple layers: VAPID key management, service worker push handlers, CSP updates for push service endpoints, client-side subscription management, and HTML email with XSS prevention.

## Solution

### VAPID keys

Generate with `npx web-push generate-vapid-keys --json`. Store in Doppler (both dev and prd). Server reads from `process.env.VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY`. Client needs `NEXT_PUBLIC_VAPID_PUBLIC_KEY` for `pushManager.subscribe()`.

### Service worker push handlers

Add `push` and `notificationclick` handlers to `public/sw.js`. The `notificationclick` handler must validate the URL origin before calling `client.navigate(url)` — push payloads are encrypted, but defense-in-depth prevents open redirect if VAPID key is ever compromised.

### CSP for push services

Browser push services require CSP `connect-src` entries even though the browser initiates the connection, not your page JS. Required domains: `https://fcm.googleapis.com` (Chrome — uses FCM as underlying transport, not a Firebase dependency), `https://updates.push.services.mozilla.com` (Firefox), `https://*.push.apple.com` (Safari).

### Email HTML escaping

All interpolated values in email HTML must go through `escapeHtml()`, not just user-generated content. Even "safe" values like agent names should be escaped for defense-in-depth — the type system (`agentName: string`) doesn't prevent future callers from passing uncontrolled input. The `escapeHtml` function must cover all 5 HTML entities: `&`, `<`, `>`, `"`, `'`.

### Push subscription endpoint validation

The push subscription endpoint URL stored in the database should be validated as HTTPS. Without this, an authenticated user could register an arbitrary URL (including internal network addresses) as their push endpoint, creating a low-severity SSRF vector when `web-push.sendNotification()` sends HTTP requests to it.

### sendToClient return type change

Changing `sendToClient()` from `void` to `boolean` is backward-compatible — all existing callers that ignored the return value continue to work. The boolean enables the "if not delivered via WS, try push/email" pattern without adding a separate `isUserOnline()` function.

## Session Errors

1. **vi.mock factory referencing const before initialization** — `vi.mock()` is hoisted by Vitest above `const` declarations. Fix: use `vi.hoisted()` for all mock functions referenced inside `vi.mock()` factories. **Prevention:** AGENTS.md already documents this pattern — follow it from the start.

2. **Dynamic import bypasses vi.mock** — `await import("@/lib/supabase/service")` in the API route wasn't caught by `vi.mock("@/lib/supabase/service")`. Fix: use static imports matching the existing codebase pattern (`createServiceClient` re-exported from `@/lib/supabase/server`). **Prevention:** Follow existing import patterns in the codebase rather than introducing dynamic imports.

3. **Notification API undefined in test environment** — `Notification.permission` throws `ReferenceError` in happy-dom. Fix: guard with `typeof Notification !== "undefined"`. **Prevention:** When using browser-only APIs in React components, always guard with typeof checks for test environment compatibility.

4. **CWD-sensitive tool calls** — Multiple commands failed because CWD was `apps/web-platform/` when the target files were at repo root (or vice versa). Fix: use absolute paths or navigate explicitly. **Prevention:** Always verify CWD before running path-relative commands.

## Key Insight

Web Push integration is mostly plumbing — the hard part isn't any single piece but coordinating: VAPID keys (Doppler), service worker (vanilla JS in public/), subscription API (Next.js route), CSP (all 3 browser push services), and the notification prompt UX (after gate resolves, not during). The email fallback adds a second notification channel with its own security surface (HTML injection). Escape everything in email HTML, validate push endpoints, and validate notification click URLs — the push payload is encrypted but defense-in-depth catches future regressions.

## Tags

category: integration-issues
module: web-platform/notifications
