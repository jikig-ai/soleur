# Live probe — soleur-bwrap-probe-rollback-prd (#9342)

Run 2026-10-01 against the FINAL SQL extracted from the `bwrap_probe_rollback_sql` heredoc in
`apps/web-platform/infra/betterstack-logs-alerts.tf` (whitespace collapsed exactly as the resource does),
via `scripts/betterstack-query.sh` raw mode under `doppler run -p soleur -c prd_terraform`.
Source: hot `remote()` UNION ALL `s3Cluster` archive, 14-day window, daily buckets. Counts only; no row bodies.

| Control | Predicate | Result |
| --- | --- | --- |
| Positive | exact alert predicate | 19 rows across 8 UTC days (query exit 0, empty stderr) |
| Negative | same predicate, needle changed to `…non-functionalX` | 0 rows (query exit 0, empty stderr) |

The rc=137 / ms 73-104 shape of those 19 rows comes from the plan-time decode (plan §Live probe) and is not reproduced here, because this file is counts only.

The positive control shows the predicate shape matches live rows (the pre-fix PDEATHSIG flake); the negative
control shows the needle is the discriminator, so the predicate is not vacuously true.
