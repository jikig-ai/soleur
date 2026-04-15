---
title: Plausible Goals Registry
category: analytics
tags: [plausible, goals, analytics-registry]
---

# Plausible Goals Registry

Canonical list of conversion goals provisioned in Plausible Analytics for
`soleur.ai`. Every goal here is upserted by
`scripts/provision-plausible-goals.sh` (PUT `/api/v1/sites/goals`, idempotent).

Provisioning runs in CI via the script; manual dashboard edits will drift on
the next CI run, so add/remove goals via the script, not the UI.

## Goals

| Goal                        | Type  | Emitted from                                                    | Purpose                                                                |
| :-------------------------- | :---- | :-------------------------------------------------------------- | :--------------------------------------------------------------------- |
| `Newsletter Signup`         | event | marketing site form                                             | Tracks newsletter conversions from eleventy pages.                     |
| `Waitlist Signup`           | event | marketing site form                                             | Tracks waitlist conversions pre-launch.                                |
| `Outbound Link: Click`      | event | marketing site (Plausible outbound-links plugin)                | Measures clicks to partner / external pages.                           |
| `/pages/getting-started.html` | page | marketing site route hit                                        | Funnel step: hit the getting-started page.                             |
| `/blog/*`                   | page  | marketing site route hit                                        | Funnel step: any blog article view.                                    |
| `kb.chat.opened`            | event | web-platform — `components/chat/kb-chat-sidebar.tsx` (on first mount w/ ready session) | Did the user open the KB chat sidebar at least once on a given doc?    |
| `kb.chat.selection_sent`    | event | web-platform — `components/chat/kb-chat-sidebar.tsx` (`onBeforeSend` when content begins with `>`) | Did the user send a quoted passage as the first block of a message?    |
| `kb.chat.thread_resumed`    | event | web-platform — `components/chat/kb-chat-sidebar.tsx` (on `resumedFrom` WS event) | Was an existing per-doc thread resumed when the sidebar opened?        |

## Emit path (web-platform)

1. Client calls `track(goal, props?)` from `lib/analytics-client.ts`.
2. Request hits `POST /api/analytics/track` (origin-gated, per-IP rate
   limited at `ANALYTICS_TRACK_RATE_PER_MIN` req/min, defaulting to 120).
3. Route forwards to `PLAUSIBLE_EVENTS_URL` (defaulting to
   `https://plausible.io/api/event`) with the site-id from
   `PLAUSIBLE_SITE_ID`. `user_id` / `userId` are stripped from props
   before forwarding.
4. HTTP 402 from Plausible is a graceful 204 skip (free plans reject
   custom props). Non-JSON bodies are tolerated — the client is fail-soft
   either way.

## Invariants

- No PII. Props may contain `path` (e.g. `knowledge-base/...`) but never
  user identifiers or email addresses.
- Goal names are immutable once provisioned — renaming breaks historical
  funnels. Only append new goals, never rename.
- The provisioning script is idempotent (PUT upsert). Running twice is safe.
