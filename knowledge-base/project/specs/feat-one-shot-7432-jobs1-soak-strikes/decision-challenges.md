---
title: "Decision challenges — #7432 soak-strike disposition"
branch: feat-one-shot-7432-jobs1-soak-strikes
date: 2026-10-20
---

# Decision challenges

| Item | Class | Ruling |
|---|---|---|
| Do the two rc=124 bound-kill REDs on `git-data-wipe-assert.test.sh` (monitor runs 39378082716, 39446197504) satisfy the soak probe's "reproduces" intent — clearing them via `JUDGED_REPRODUCING_RUNS` — or do they stand as non-reproducing strikes and fire the pin-revert trigger? Evidence for reproducing-in-intent: rc=124 at 363 s vs the 360 s default bound is H4, a CONFIRMED deterministic capacity-defect class owned by `_SUITE_BOUNDS` (ATTRIBUTION block, `run-registered-suites.sh`); it struck on 2/2 counted runs in the window on the monitor's unsharded ~181-suite -P 4 pool. Evidence for letter-stands: the probe's two literal tests both fail — infra-validation run 39370876316 at the same sha (1cb50078e0) PASSED the suite in a 65-suite shard (different contention pool), and a -P 1 run would pass (serial 162 s measured on dev host, est. ~240 s on the 4-core CI runner, both < 360 s). The reproduction clause was written to separate real defects from the -P 4 flake; an H4 bound-kill is a real defect with a tracked fix (#10654, CTO-ruled), not flake evidence. | technical | pending - assumed: reproducing-in-intent — judge the runs via `JUDGED_REPRODUCING_RUNS`, ship the bound entry either way; reverting the infra pin over a suite-bound defect is the misattribution the ATTRIBUTION block exists to prevent |
| Fold #10654's bound fix into this PR vs a separate small PR | technical | Ruled by CTO agent on #10654, 2026-10-20: "Small separate PR, or fold into the next PR that already touches the runner" — this PR touches `run-registered-suites.sh`, so folding is sanctioned |
| Bound value 720 s (vs 2.5x local-serial ~445 s or other) | technical | pending - assumed: 720 — #10654's named value; ~2x the observed kill point (363 s); matches sibling entries' 2.5-3x serial-plus-headroom precedent; ATTRIBUTION rule is ≥1.5x worst observed |
| grep -q linter: build or stay deferred | technical | Ruled by measurement 2026-10-20: zero of ~1267 `| grep -q` sites streams a >64 KiB file; no captured PIPESTATUS[0]==141 — mechanism unreachable, output is a documented measurement comment on #7432, not code |
