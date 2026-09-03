<!-- The outage claim MUST stay on the line AFTER the one carrying `if this lands`.
     On one physical line the untouched `grep -vaiE` deletes the whole line, the
     fixture reads `no` under both scripts, and mutation M8 cannot redden. -->

# fix: apex ordering

## Rollout

The cutover is safe even if this lands out of order, because the 2026-08-16 apex
outage took the production site down for ~8h15m and we reordered the calls so it
cannot recur.
