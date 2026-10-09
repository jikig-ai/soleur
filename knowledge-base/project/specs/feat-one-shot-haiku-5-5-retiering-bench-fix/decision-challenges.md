# Decision challenges (plan-review, 2026-10-09)

Persisted for `ship` Phase 6 (taste calls the headless run did not stop to ask about).

1. **Taste — Gate 0 threshold.** The plan fixes the qualify line at a $12.50/month saving (12-month saving at least 3x an assumed $50 one-time cost, $10 minimum) at a 0.65 saving factor. Every candidate falls below it on the post-cutover window, so no eval arm is built. A different line (for example a $5/month minimum) would send `cron-community-monitor` ($7.90 at the 0.87 ceiling) to the pre-registered eval path. The operator's brief says "drop candidates whose measured spend is negligible" without a number; the number is the plan's.
2. **Taste — dropped inferred measurement.** The first draft had N=60 synthetic Haiku probes for leader-loop truncation and refusal. Review cut them (synthetic payloads, existing pages, the issue says to decide with production data). The dispositions are rules with armed triggers instead. Reinstate if the operator wants measured numbers before the first production page.
3. **Taste — eval arms not built up front.** The brief says "Build the eval arms". The plan builds none for classes the issue's own drop rule removes, and keeps a short pointer for a qualifying class. If the operator wants an arm anyway, `cron-community-monitor` is the nearest candidate.
