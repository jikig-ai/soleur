# Decision challenges: feat-one-shot-p5-atok-wait

Plan: `knowledge-base/project/plans/2026-11-28-fix-p5-browser-bodies-wait-for-atok-plan.md`. Ref #12931.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| F1 Polling mode of the atok wait | technical | Ruled by CTO agent, 2026-11-28: the operator's snippet plus `polling: 100` - Chrome pauses requestAnimationFrame in a background or covered tab of an operator's own Chrome, which would reproduce the same `{atok:false}` false negative; interval timers are throttled, not stopped. |
| F2 Wait in `p5-mint.js` `cleanup()` atok re-read | technical | Ruled by CTO agent, 2026-11-28: leave `cleanup()` untouched - it re-reads on the same page after a POST that already needed the atok; there is no second navigation to race, failing closed is safer, and a wait would delay row M16f by 15 s. |
| F3 Test design for "the wait exists before the first atok read" | technical | Ruled by CTO agent, 2026-11-28: a `waitForFunction` stub plus one late-atok row per body and mutants deleting each wait; no text-position check (brittle, proves nothing the mutants do not); late-atok rows assert a finite timeout <= 30000; floors set from a real run. |
| F4 Wait timeout | technical | Ruled by CTO agent, 2026-11-28: 15000 ms - about 50x the measured 283 ms, room for a slow network and background-tab timer throttling; longer only slows signed-out runs. |
| F5 Archived plan hold-line equality check vs re-pinned runbook holds | technical | Ruled by CTO agent, 2026-11-28: normalize exactly `sha256=<64 lowercase hex>` on hold lines of both files before the compare, keep the line-count equality, add a hold-wording mutant - wording drift stays guarded; hash freshness is already enforced by the per-citation check and `sha256sum -c`. |
