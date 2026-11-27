# Decision Challenges — feat-one-shot-mq-battery-shards

Headless pipeline record (plan phase, 2026-11-19). Reviewed-Coverage: **sequential-fallback** — no Task/agent spawn was available in this Devin context; research and ruling were performed inline by the planning orchestrator, not by independent review agents.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Light matrix K: 10 vs 12 vs 14+ | technical | Ruled by CTO agent, 2026-11-19: **K=12, chosen by the smallest-K-above-heavy rule** — pick the smallest K whose predicted worst light leg stays ≥ the heavy matrix's fresh median wall (~19–20 min); below it, added legs buy nothing because heavy binds. At ~233 min of light suite work, K=12 predicts ~19.4 min mean + ~0.8 min overhead ≈ 20–21 min wall, matching epic #11556's 20-min goal; K=10 (~24 min) is the documented fallback if the fresh medians mispredict. |
| Generator source hardening (`--event` selector + zero-measured-input refusal) | technical | Ruled by CTO agent, 2026-11-19: **include as scoped Phase 2** — the documented `--runs N --write` samples `--branch main` (push events) where push-dedupe elides `test-scripts`; an all-artifactless sample produces an all-floor count-balanced manifest behind only a WARN, destroying the balance this arc exists to protect. ~15 lines + fixture rows; proportionate to the hazard. |
| Split `registry-gate-mutation-battery` via `--rows` | technical | Ruled by CTO agent, 2026-11-19: **defer** — the battery has no row-range CLI support today (adding it is a suite-internals change), and its ~19-min leg stays under the post-bump light bound. Re-evaluate if its fresh merge_group median crosses ~20 min or heavy becomes the recurring tail after this PR. |
| Tighten `watch-shard-balance-11564.sh` leg-ratio bound below 1.30× | taste | Left for the operator: the observed leg-5 ratio was 1.27× — just under the flag — so this exact failure shape nearly alerted. Lowering the bound trades rebalance cadence for churn on a checked-in derived artifact (ADR-240 deliberately minimizes churn). Recommended disposition: leave unchanged this PR; revisit if the next drift window produces another sub-threshold outlier. |
| `test-all-pr-battery-gate` stale path in the brief | technical | Ruled by CTO agent, 2026-11-19: record the stale path, plan against the real artifact - `scripts/test-all-pr-battery-gate` does not exist on branch or main; the real artifact is `scripts/test-all-pr-battery-gate.test.sh` (suite label `scripts/test-all-pr-battery-gate`), already reflected in the plan's sentinel sweep. |

## Not Yet Specified

None — the ask's open questions were resolved from generator source and measured artifacts (see plan Premise Validation).
