# Learning: mechanical `ctx.`-qualification breaks object-literal shorthand

## Problem

During a review fix I extracted a ~190-line catch body into
`reportDispatchSoleurGoError(err, ctx)` and qualified the five locals
with a word-boundary regex (`(?<![.\w])name\b` → `ctx.name`). The regex
is correct for *references* but blind to **object-literal shorthand**:
`{ conversationId, userId }` became `{ ctx.conversationId, ctx.userId }` —
invalid syntax — and `sendToClient(userId, { type: "session_ended",
reason: "session_revoked", conversationId })` gained an unparseable
`ctx.conversationId,` member. `tsc` caught it on the next check, plus a
second miss where `op: "dispatch"` → `op: mirrorOp` (not `ctx.mirrorOp`)
became a `TS2304`.

## Solution

Post-extraction, grep the moved body for `ctx\.` inside `{}` literals
and fix each shorthand to `name: ctx.name`; run `tsc --noEmit`
immediately after any regex-driven bulk rewrite, before writing more
edits on top. In review-fix context, prefer per-block `edit` calls over
regex rewrites for extractions >50 lines — the failure modes are
mechanical and invisible to a skim.

## Key Insight

**A rename that is sound for expressions is unsound for syntax sugar.**
Shorthand properties, destructuring patterns, label statements, and
`${name}` template interpolations are the four places a
word-boundary-qualified rename produces non-parseable output. The check
is one grep (`{[^}]*ctx\.`) plus an immediate `tsc` — cheap compared to
shipping a broken extraction into a fix commit.

## Tags
category: refactoring
module: server/cc-dispatcher.ts
