# Decision Challenges — feat-one-shot-10741-followthrough-datetime64

| Item | Class | Ruling |
|---|---|---|
| Absence-query fix mechanism: `toDateTime64('${first_marker_dt}', 6)` vs bash fraction-strip (`${first_marker_dt%%.*}`) vs `parseDateTime64BestEffort` | technical | pending - assumed: `toDateTime64('${first_marker_dt}', 6)` — the issue's named fix; fraction-strip floors the boundary to the second and can false-FAIL on a same-second pre-marker fchmodat2 row; BestEffort is looser than needed for a known-shape literal |
| Timezone argument on `toDateTime64`: implicit (2-arg) vs explicit `'UTC'` (3-arg, matching the column's `DateTime64(6,'UTC')` decl) | technical | pending - assumed: 2-arg implicit, consistent with the neighboring `toDateTime('${SINCE_SQL}')` call at probe:151 which runs the same way in production today |
| Brand-survival threshold `none` | operator (brand) | pending - assumed: none — the only touched surface is a repo-local verification probe and its fixture suite; no user data path, credential scope, or payment/auth surface changes |
