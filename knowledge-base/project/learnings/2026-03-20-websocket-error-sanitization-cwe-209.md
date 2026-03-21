# Learning: WebSocket error message sanitization prevents CWE-209 information disclosure

## Problem

Five locations in `agent-runner.ts` and `ws-handler.ts` forwarded raw `err.message` from internal errors (Anthropic SDK, Supabase client, Node crypto, filesystem) verbatim to WebSocket clients via `sendToClient()`. This violated CWE-209 (Generation of Error Message Containing Sensitive Information). Concrete leak vectors included:

- Supabase errors exposing schema details: `relation "public.conversations" does not exist`
- BYOK config errors exposing env requirements: `BYOK_ENCRYPTION_KEY must be a 64-character hex string`
- Node crypto errors exposing implementation: `Unsupported state or unable to authenticate data`
- Interpolated errors embedding raw Supabase messages: `Failed to create conversation: permission denied for table conversations`
- Reflected input in default/server-only-type case branches interpolating `msg.type` into error responses

Two catch blocks (`chat` and `review_gate_response` in `ws-handler.ts`) also lacked `console.error` calls, silently swallowing errors.

## Solution

Created `apps/web-platform/server/error-sanitizer.ts` with an allowlist-based `sanitizeErrorForClient()` function:

1. `KeyInvalidError` returns a fixed string (defense-in-depth, not `err.message`)
2. `KNOWN_SAFE_MESSAGES` record maps known operational errors to user-facing messages
3. `"Unknown leader:"` prefix check handles interpolated errors with a fixed response
4. Generic fallback for all unrecognized errors

Replaced all raw `err.message` patterns, added missing `console.error` calls, and fixed reflected input strings.

## Key Insight

Allowlist-with-fallback is the correct security posture for error sanitization. Unknown errors automatically get the safe generic message. A denylist approach (regex-filtering) would be fragile. The `createConversation` error path validates this: it uses string interpolation, so exact matching can't catch it, but the generic fallback does automatically.

For errors needing client-side UX routing (like `KeyInvalidError` -> `/setup-key`), create typed error classes with `instanceof` checks rather than adding string entries.

## Session Errors

1. **Vitest `@/` path alias not resolvable** -- used relative import `"../lib/types"` instead of `"@/lib/types"` in the sanitizer module because vitest can't resolve the `@/` alias without explicit config. Matches existing test file conventions.
2. **`npm install` required in worktree** -- worktree didn't have `node_modules`. Tests failed until dependencies were installed.

## Tags

category: security-issues
module: web-platform
