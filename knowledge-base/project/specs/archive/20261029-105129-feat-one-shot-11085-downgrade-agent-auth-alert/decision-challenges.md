# Decision Challenges — feat-one-shot-11085-downgrade-agent-auth-alert

Headless plan run (2026-10-29). Every technical fork was ruled by the `soleur:engineering:cto` agent; none was put
to the operator. `soleur:ship` renders this table into the PR body.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| How to "drop the email action" when the pinned provider (jianyuan/sentry 0.15.7) rejects `actions = []` ("list must contain at least 1 elements", measured with `terraform validate` on 2026-10-29): A) keep one email action with `fallthrough_type = "NoOne"`, B) `enabled = false` with the email action kept dormant, C) delete the rule now, D) another action kind | technical | Ruled by CTO agent, 2026-10-29: Option A. Keep the rule enabled with exactly one `email = { target_type = "issue_owners", fallthrough_type = "NoOne" }` action; leave `frequency_minutes = 40`, trigger, filters, tags and emit unchanged; the only `alert-reference.json` diff is `fallthroughType` ActiveMembers -> NoOne. Provider forces at least one action; three live rules already use this idiom as "lands in the issue stream, not pushed"; B leaves paging config one flag-flip from re-paging, C contradicts the operator's scope, D notifies elsewhere or needs integration ids. Safeguards in the PR: flip the guard test to REQUIRE NoOne and ban ActiveMembers; comment above the resource that delivery depends on the project having no Sentry ownership rule. Flip condition: if the ownership endpoint returns a non-null `raw` before merge, use B instead. |
