# Learning: Typed Error Codes for WebSocket Key Invalidation

## Problem

When the BYOK migration invalidated existing API keys, users with active browser sessions saw a dead-end error message in chat with no way to recover. The WebSocket error handler rendered all errors as plain text with no distinction between recoverable and unrecoverable errors.

## Solution

Added a typed `WSErrorCode` discriminated union to the WebSocket protocol and a `KeyInvalidError` class for server-side error classification:

1. **Protocol layer** (`types.ts`): `WSErrorCode = "key_invalid"` union type on the error message variant, plus a `KeyInvalidError` class for `instanceof` detection
2. **Server layer** (`agent-runner.ts`): Catch block uses `err instanceof KeyInvalidError` to attach `errorCode: "key_invalid"` to the WebSocket error message
3. **Client layer** (`ws-client.ts`): Error handler checks `msg.errorCode === "key_invalid"`, tears down the reconnect loop (mountedRef, timer, onclose), and redirects to `/setup-key`

## Key Insight

When adding error classification to a message protocol, use typed error classes (`instanceof`) instead of string matching (`message.includes()`). String matching is fragile — a message rewording silently breaks detection. Typed classes provide compile-time enforcement and survive refactoring. Also, keep type unions to only values that are actually produced and consumed — speculative members create false API contracts.

## Session Errors

1. **Worktree dependency isolation**: New worktrees don't inherit `node_modules`. Always run `npm install` after creating a worktree for a project with native dependencies.
2. **Module-level side effects block test imports**: Importing from a module that calls `createClient()` at the top level fails without env vars. Place shared types/classes in side-effect-free modules (`types.ts`), not in modules with initialization code (`agent-runner.ts`).
3. **Bare repo git operations**: `git pull` requires a work tree. In bare repos, use `git fetch` + `git worktree add ... origin/main`.

## Tags

category: integration-issues
module: web-platform
