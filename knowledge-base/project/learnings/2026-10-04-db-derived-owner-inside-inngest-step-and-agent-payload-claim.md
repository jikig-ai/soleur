# Learning: resolve a DB-derived owner inside the Inngest step, and re-derive "the payload lacks field X" claims

## Problem

Planning an address→workspace routing table for the email-triage pipeline surfaced two traps:

1. The first draft resolved the owner at the top of the Inngest handler, copying the existing env read (`EMAIL_TRIAGE_OWNER_USER_ID`). An env value is static across step replays; a DB lookup is not. Three reviewers independently found that a retry could then notify a different owner than the row's `user_id` (a route edited or deleted mid-run).
2. A research agent reported the Resend `email.received` webhook "does NOT expose `to`/`cc`" because the route's local `ResendInboundBody` type does not declare them. That was false: the SDK type `ReceivedEmailEventData` lists `to`, `bcc`, `cc`, Resend's published example adds `received_for`, and the live receiving API returned `to` on every row.

## Solution

1. Resolve inside the `claim-insert` step, return `{ownerId, workspaceId}` in the step output, read them from `claim` in later steps, take them from the adopted row on the 23505 path, and fall back to the env owner for claims memoized before the deploy.
2. Check a local type's silence against the vendor SDK type and one live read-only call before accepting "the vendor doesn't send X".

## Key Insight

Code outside `step.run` in an Inngest handler re-executes on every replay, so any value that can change between attempts (a DB read) must be pinned inside a step and carried forward. A local interface that omits a field is evidence about the interface, not about the wire payload.

## Session Errors

1. **Research agent asserted the webhook payload lacks `to`/`cc`.** Recovery: read the SDK type, Resend's example payload and the live receiving API. Prevention: covered by the brainstorm skill's "a subagent's claim is a claim to re-derive" paragraph; no new rule.
2. **Two `Write` calls to the plan failed with "file modified since read".** Recovery: re-read, rewrite. Prevention: none needed (tool guard worked as designed).
3. **A `gh issue list` research call timed out and GitHub GraphQL returned 503 once.** Recovery: re-ran the query; used `gh issue view`. Prevention: none (transient).

## Tags

category: workflow-issues
module: plan
