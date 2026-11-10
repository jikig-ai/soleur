# Decision Challenges — feat-one-shot-12017-soak-read-window

Planning-phase rulings for #12017 (Epic #11556 Lever A). Technical rows carry `pending - assumed:`
rulings per the technical-ruling delegation contract (no agent tool in this harness); the parent
batches a CTO spawn.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Bound the three `ALL_ROWS` harness controls (identity / nolink / always-PASS) to a 12-row `CONTROL_ROWS` subset vs. keep the full 70-row census | technical | pending - assumed: subset — the controls are ~50% of all probe invocations (~210 of ~420); the subset covers every verdict class (rc 0/1/2/3, voucher, mean, marker, trust, ADR, registration, lib) and the always-PASS floor recomputes honestly (≥10 of 12; `r_pass`/`r_needcomplete` red-immune by construction). Alternative measured: keep full sets → suite lands ~105s vs ~75s. |
| Probe cost cut via merged-jq batching (verbatim subexpressions, ~2.5× loop speedup) vs. worker-model parallel fan-out (mirroring `pr-battery-gate-saving-9323.sh`, ~4–6×) | technical | pending - assumed: merged-jq batching — ~20 lines, zero semantic drift, nearly all mutant anchors preserved verbatim; the worker model rewrites the safety-critical loop into wlog/replay machinery (~120 lines) and breaks far more anchors. Held as fallback if Phase 2 misses the wall-time target. |
| `MG_MAX_PAGES=10` (≈1000 merge_group runs ≈ ~40 days of merges) with cap-exhaustion → exit 3 CANNOT ESTABLISH, vs. keeping implicit window anchoring | technical | pending - assumed: cap at 10 + rc-3-on-full-last-page — the window is volume-correlated to the ≤100-run push sample (~2 pages typical), so the cap is a pure bound with near-zero behavioral risk; rc 3 (retryable) chosen over FAIL because a truncated voucher set must never degrade into a wrong-elision verdict. |
| Emit `created_epoch` via `fromdateiso8601` in the runs slice (per-run `date` removed): an unparseable `created_at` now fails the whole slice (`fail_api "ci.yml push runs"`) instead of the per-run read | technical | pending - assumed: accept — verdict stays rc 3 either way; message changes from `run <id> created_at` to the slice label. No row asserts the per-run variant; a fixture edge row is added to pin it. |
| Brand-survival threshold `none` (internal CI-cost tooling, no user-facing surface) | taste | none — diff is `scripts/followthroughs/*` + generated `suite-durations.tsv`; the preflight sensitive-path regex does not match, so no scope-out bullet required. |
