## What was deferred

Follow-up to #11591 (the Authentication mode setting selects the Concierge credential). Copy work that was deliberately kept out of that PR:

1. **Recovery sentence.** The operator-only `oauth_unusable` / `oauth_token` friendly sign-in messages in `apps/web-platform/server/agent-auth-user-message.ts` could gain one recovery sentence: choose "My API key" in Settings, then start a new conversation. A failing conversation keeps the mode it started with, so the owner cannot recover inside it.
2. **Unresolved-mode copy.** A mode that cannot be resolved throws `ByokLeaseError("fetch_failed")`, which the client renders with the `key_invalid` "Your API key is invalid or expired / Update key" copy and tears the socket down. That is wrong for a missing binding or a failed read. It needs its own copy (the error carries a closed `reason`), which also lets the generic call-site Sentry mirror skip the event the lease already reported.
3. **Non-owner viewers.** The mode is the workspace owner's setting; the helper line ("your saved API key") and the amber provider disclosure are inexact for delegated members and non-owners. Tune or hide for them.

## Why deferred

The #11591 brief says not to touch the friendly sign-in error merged on 2026-10-29, and `agent-auth-user-message.ts` is import-boundary pinned with a pinned copy test. A distinct unresolved-mode copy touches the exhaustive `never` rail, the WS code enum, the zod schema and the UI. CTO rulings are recorded in `knowledge-base/project/specs/feat-one-shot-auth-mode-selects-credential/decision-challenges.md`.

## Re-evaluation criteria

Revisit once #11591 has shipped and the owner (or telemetry for the `auth-mode-unresolved` / `oauth_unusable` paths) shows a failing conversation that did not lead to a mode change within a day, or when a non-operator reports confusion at the helper line.

Mandated-By: wg-when-deferring-a-capability-create-a

User-Impact: operator-only copy, aggregate pattern; a failing conversation shows existing wording without a recovery step.

Ref #11591
