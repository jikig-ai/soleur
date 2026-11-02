# Decision challenges — feat-one-shot-11831-11820-flip-token-gate-alert

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| #11820 alert design: ship a query alert now (no replace-window suppression) vs defer until the feeder dead-man | technical | Ruled by CTO agent, 2026-11-02: Option A. Ship `inngest_cutover_flip_silent` (email-only, check 300 s, query 900 s, `lower_than 1`, treat-as-zero), keyed on `JSONType(raw,'message')='Object'` for host `soleur-inngest-prd`; suppression stays with the #11266 feeder dead-man, so the PR says `Ref #11820`, not `Closes`. |
| Query discriminator for the flip row | technical | Ruled by CTO agent, 2026-11-02: `JSONType(raw,'message')='Object'`, not a string pattern and not a `startsWith` on the raw text (Better Stack re-serializes keys alphabetically); measured 1,891 object rows in 7 days, no gap over 900 s. |
| Pin `access` only on plan entries that create the token | technical | Ruled by CTO agent, 2026-11-02 (batch A ruling) and issue #11831 text: pin on create, create+delete and delete+create; a no-op token is not judged; a missing `after.access` fails closed. |
| Accept row for the non-required `affected-index-ratchet` finding | taste | Ruled by the owner's resume brief, 2026-11-02: include the accept row in this PR (it was deliberately left out of the flip-token PR). |
