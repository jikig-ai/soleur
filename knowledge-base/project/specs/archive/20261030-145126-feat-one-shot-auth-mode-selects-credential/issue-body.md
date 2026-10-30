## Problem

Settings > Agent engine has an "Authentication mode" dropdown (`managed` / `api-key`). For the Claude engine it is stored (workspace default `default_auth_mode`, snapshotted into each conversation's engine binding) but nothing reads it when the agent picks its secret. The secret is chosen only in `apps/web-platform/server/byok-lease.ts` `fetchAgentCredentialIntoSlot`: with `CC_OAUTH_ENABLED` on and a saved subscription token, the token wins and the owner's API key is never read; otherwise the API key is used. So an owner whose saved subscription token is unusable has no way to say "use my API key instead" short of deleting the token.

## Scope

Make the BYOK lease honour the conversation's authentication mode, fail-closed, with the owner-only, date and kill-switch gates unchanged, plus the dropdown copy so it tells the truth. Plan: see draft PR #11590.

## Out of scope

The friendly sign-in error, the subscription-token shape allowlist at `POST /api/keys`, and the `oauth_unusable` lease refusal (all merged 2026-10-29 under #11086 / #11523), and the owner re-saving the token (#11541). Neither of those issues is closed or edited by this work.

User-Impact: Settings page component components/settings/agent-engine-settings.tsx (Authentication mode dropdown) and the Concierge chat sign-in path
Fix-Size: 750 lines / 23 files

Ref #11086
Ref #11541
