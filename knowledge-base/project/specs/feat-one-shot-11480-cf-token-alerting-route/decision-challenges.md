# Decision Challenges — feat-one-shot-11480-cf-token-alerting-route

Headless one-shot planning run for issue #11480. This harness has no Agent/Task
spawn capability, so the `soleur:plan-review` panel, SpecFlow analyzer, domain
leaders, and scoped advisor consult could not be spawned. Technical rows carry
`pending - assumed: <default>` placeholders per the technical-ruling-delegation
contract until the parent pipeline's batched `soleur:engineering:cto` consult
lands; the Ruling column then records each verdict verbatim.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Live duplicate: PR #11456 (`feat-one-shot-11181-cf-notification-route`, draft WIP) implements this same fix on the same three files and is mid-pipeline — proceed with this branch's fix or defer | technical | pending - assumed: proceed — issue #11480 is OPEN and #11456 is an unmerged draft; whichever lands first wins and the other rebases to a no-op diff. The plan's implementation step 0 (`git grep notification_policies origin/main`) closes #11480 as duplicate if the corrected route already landed |
| `?per_page=1` kept on the corrected route (issue prescribes `alerting/v3/policies?per_page=1`) vs the sibling PR's bare path (its deepen pass found the API reference documents no query params) | technical | pending - assumed: keep `?per_page=1` — the issue prescribes it explicitly, every sibling `DT_ROWS` URL carries it (uniform print/run parity), and an unsupported param is ignored while a supported one bounds the payload |
| Brand-survival threshold `none` | taste | pending - assumed: none — read-only URL correction on an existing authenticated GET; worst outcome is a probe that keeps failing closed, matching the sibling plan's classification for the identical fix |
| No Agent/Task spawn capability — plan-review panel, SpecFlow analyzer, domain leaders, and scoped advisor consult all skipped; does the plan need a panel re-run before `soleur:work`? | technical | pending - assumed: no — every feasible gate ran in-process (premise validation incl. collision report, ADR corpus check, scope check, guard-contract lint rc=0, sharp-edges pass, live API-doc verification, prescribed commands executed); `soleur:plan-review` may still run at review stage but is not a blocking precondition |
| Added `src_lacks 'notification_policies'` and `d_has 'alerting/v3/policies'` pins beyond the issue's literal three-site ask | technical | pending - assumed: include — one line each in a file already being edited; they encode the cited learning's prevention (pin the live route in tests) and keep the phantom route from silently returning through the script or the doc |
