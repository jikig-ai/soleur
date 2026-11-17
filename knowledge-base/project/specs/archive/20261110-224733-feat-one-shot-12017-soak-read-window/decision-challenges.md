# Decision Challenges — feat-one-shot-12017-soak-read-window

Planning-phase rulings for #12017 (Epic #11556 Lever A). Technical rows carry `pending - assumed:`
rulings per the technical-ruling delegation contract (no agent tool in this harness); the parent
batches a CTO spawn.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Bound the three `ALL_ROWS` harness controls (identity / nolink / always-PASS) to a 12-row `CONTROL_ROWS` subset vs. keep the full 70-row census | technical | Ruled by CTO agent, 2026-11-10: APPROVE the named 12-row CONTROL_ROWS subset - the controls test harness integrity (tree resolution, verdict plumbing, red-reporting), not probe coverage, and the subset still spans every verdict class while cutting ~40% of total invocations. |
| Probe cost cut via merged-jq batching (verbatim subexpressions, ~2.5× loop speedup) vs. worker-model parallel fan-out (mirroring `pr-battery-gate-saving-9323.sh`, ~4–6×) | technical | Ruled by CTO agent, 2026-11-10: APPROVE merged-jq batching (worker model held as fallback) - 4 jq + 1 date per run collapse to 1 jq + epoch-in-slice for ~2.5x loop speedup at ~20 lines with all mutant anchors preserved byte-identical, vs ~120 lines of wlog/replay machinery on a live safety gate. |
| `MG_MAX_PAGES=10` (≈1000 merge_group runs ≈ ~40 days of merges) with cap-exhaustion → exit 3 CANNOT ESTABLISH, vs. keeping implicit window anchoring | technical | Ruled by CTO agent, 2026-11-10: APPROVE MG_MAX_PAGES=10 with rc-3-on-full-last-page - the window is volume-correlated to the <=100-run push sample (~2 pages typical, 10 pages ~=40 days of headroom), and a possibly-truncated voucher set must degrade to retryable CANNOT ESTABLISH, never to a wrong-elision verdict. |
| Emit `created_epoch` via `fromdateiso8601` in the runs slice (per-run `date` removed): an unparseable `created_at` now fails the whole slice (`fail_api "ci.yml push runs"`) instead of the per-run read | technical | Ruled by CTO agent, 2026-11-10: APPROVE epoch-in-slice - removing the per-run date subprocess keeps rc 3 for unparseable input (verdict class unchanged; only the message label shifts to the slice) and all real GitHub created_at values are ISO8601 that fromdateiso8601 accepts. |
| Brand-survival threshold `none` (internal CI-cost tooling, no user-facing surface) | taste | none — diff is `scripts/followthroughs/*` + generated `suite-durations.tsv`; the preflight sensitive-path regex does not match, so no scope-out bullet required. |
