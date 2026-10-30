## What was deferred

Follow-up to #11591 (the Authentication mode setting selects the Concierge credential). The operator-only `oauth_unusable` / `oauth_token` friendly sign-in messages in `apps/web-platform/server/agent-auth-user-message.ts` could gain one recovery sentence: choose "My API key" in Settings, then start a new conversation. A failing conversation keeps the mode it started with, so the owner cannot recover inside it.

## Why deferred

The #11591 brief says not to touch the friendly sign-in error merged on 2026-10-29, and `agent-auth-user-message.ts` is import-boundary pinned with a pinned copy test. Discoverability rides on the dropdown helper line ("Applies to new conversations") for now. It is a one-cell edit plus its pinned copy test.

## Re-evaluation criteria

Revisit once #11591 has shipped and the owner (or telemetry for the `auth-mode-unresolved` / `oauth_unusable` paths) shows a failing conversation that did not lead to a mode change within a day.

Mandated-By: wg-when-deferring-a-capability-create-a

User-Impact: operator-only copy, aggregate pattern; a failing conversation shows the existing message without a recovery step.

Ref #11591
