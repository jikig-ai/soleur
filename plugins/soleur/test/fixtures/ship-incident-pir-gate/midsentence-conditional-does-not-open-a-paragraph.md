<!-- The report sentence MUST stay on the line AFTER the one carrying `if this lands`.
     On one physical line `DROP_RE` deletes the whole line, the fixture reads `no` under
     both scripts, and mutation M8 cannot redden. (`DROP_RE` is the merged awk rule that
     replaced the separate `grep -vaiE` stage.) This comment carries no report vocabulary:
     fixture prose is matched too. -->

# fix: apex ordering

## Rollout

The cutover is safe even if this lands out of order, because the 2026-08-16 apex
outage took the production site down for ~8h15m and we reordered the calls so it
cannot recur.
