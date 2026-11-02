# Decision Challenges — feat-one-shot-11720-mut-skip-batch3

Planning ran inline (Devin depth-1 — subagents cannot spawn subagents, so no CTO spawn was possible this session; prior rulings are carried forward from the batch-2 record and new technical items carry `pending - assumed:` rulings per the technical-ruling-delegation fallback).

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| env -u vs seam-check for the six ports (issue item 3) | technical | Ruled by CTO agent, 2026-11-02 (batch-2, recorded in archive/20261102-113422-*/decision-challenges.md context + shipped convention): seam-check inside each suite supersedes `env -u` run lines — `env -u` self-reds `registry-clientip`'s `suite-seam-in-workflow` pin and the byte-exact run-line pins in web-nic/ghcr; batch-3 ports the shipped convention |
| Uniform promotion of all six ported files (vs selective) | technical | Ruled by CTO agent, 2026-11-02 (batch-2 ruling A extended): registering only a subset of identical cases is arbitrary — every ported file whose floor scores FIRES gets a live-site PROMOTED_FILES entry + MIN_FIRING_SUITES +6 (65→71) |
| inngest-524 `mutate_red` signature widening (add $4 fragment + $5 want) vs keep fragment-less grading | technical | pending - assumed: widen — the WRONG-reason class is otherwise uncovered and every sibling carries the fragment arg |
| ghcr/web-nic `MUT_ROWS_EXPECTED`→`MUT_ROWS` rename vs keep name | technical | pending - assumed: rename for convention uniformity while keeping the stronger MUT_ROWS_RUN conservation ledger intact |
| sandbox-alerts DISP/CLS (.ts) canon surface — param-shaped whole-line pins vs extend res_block canon to .ts | technical | pending - assumed: keep whole-line pins on .ts (no HCL blocks to block-scope; canon/block machinery applies to the .tf surface) |
| PR-body issue linkage at ship (`Closes #11720` vs `Ref #11720`) | technical | pending - assumed: `Ref #11720` with a closing comment — the remainder list is exhausted after this batch except the deliberate registry-clientip descope, so the operator confirms the descope before the issue auto-closes |

## Operator Holds (epic #10390 — carried forward verbatim from batch-2 record)

Delegation: https://github.com/jikig-ai/soleur/issues/10390#issuecomment-6361717901 (valid to 2026-11-20)

- Hold: the deferred carrier batch (#8525 + #8013 + the RestartSec=300 half of #8080 + advisory #10290) waits for the next vinngest-v* bake / host-replace window
- Hold: #8839 (stuck-on-Working spawn backstop) waits for the Sentry spawn-agent dead-letter evidence and the 35-day lifecycle check
- Hold: Operator-reserved: #9943 — the owner's decision on a new Better Stack read credential in the cutover dispatch
- Hold: Operator-reserved: op=backup dispatch
- Hold: Operator-reserved: DOPPLER_TOKEN_INFRA_PRIVILEGED seed
