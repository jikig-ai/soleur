# Decision Challenges — feat-one-shot-10094-slot-trigger-lease-legs

Planning ran on a harness with no Agent/Task tool, so `pending - assumed`
placeholders were written per the technical-ruling-delegation contract and then
ruled by the parent pipeline: the technical row carries the batched
`soleur:engineering:cto` consult's verdict verbatim (2026-10-13), and the two
`operator (scope)` rows name the actions the operator authorised. All rows are
ruled — none pending. `soleur:ship` renders this table into the PR body.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Re-scope #10094 from "fix the red legs" to "verify + close" — fix already merged via #10001 five hours after the observed failing run | operator (scope) | Operator authorises: close #10094 as verify-and-closeout — legs verified green on five consecutive post-#10001 runs including the 2026-10-12 `schedule` run 38248356757; no product code change ships in this PR |
| Fold in closure of #3373 and #3221 (open code-review scope-outs whose re-evaluation criteria are verifiably met) alongside #10094 | operator (scope) | Operator authorises: also close #3373 and #3221 in this closeout with evidence comments — both carry `do-not-autoclose`, so closure is a deliberate evidence-based act with mechanism citations |
| Dev function-body drift hypothesis — is `pg_proc.prosrc` probe required before closing? | technical | Ruled by CTO agent, 2026-10-13: optional non-blocking corroboration, not a close gate - the red signature (cap_hit on 200s-aged slot, undefined on 121s-aged lease) is only producible with live thresholds >200s/>121s, consistent with mig-133's 240s bodies, and post-#10001 green legs bound the exercised constants inside ~(60s, 300s); drift inside that window or in unexercised objects remains possible but is a separate hygiene issue, not a blocker |
