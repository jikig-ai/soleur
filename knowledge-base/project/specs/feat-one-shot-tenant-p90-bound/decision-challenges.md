# Decision Challenges — feat-one-shot-tenant-p90-bound

Headless one-shot planning run for standing tracker #12755. This harness
has no Agent/Task tool, so the `soleur:plan-review` panel and CTO rulings
could not be spawned in-process. Technical rows carry
`pending - assumed: <default>` placeholders per the
technical-ruling-delegation contract; the parent pipeline's batched
`soleur:engineering:cto` consult rewrites the cells before `soleur:work`
(`technical-ruling-gate.sh --branch`).

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Breach disposition: (a) bound mis-seed re-seed vs (b) transient tail leave-and-document vs (c) systemic regression file-issue | technical | pending - assumed: (a) re-seed PR bound to 960s — the timeline is bimodal (23/26 samples at 11-76s; 3 at 915-970s), the slow mode tracks the heavy `tenant-integration` suite's legal duration (~835-910s inside `timeout-minutes: 19`) on the same runs where sibling checks stayed ≤478s, so it is a needs-chain wait the single bound must cover, not queue congestion and not an execution regression (duration_p90=21s); the 2026-11-13 ~900s breach was the same mode rolling through the window, refuting (b); the check is healthy, refuting (c) |
| Seed value: 960s (next-minute of p90 915s) vs max-derived (next-minute of max 970s → 1020s) | technical | pending - assumed: 960s — the TSV header's documented method is measured p90 → next minute; the 0.30 margin is the designed absorber for the max (960×1.3=1248 > 970), and seeding on the max would double-count margin against the file's own contract |
| `merge_group` bound: leave 180s vs tighten to next-minute(p90=70s)=120s | technical | pending - assumed: leave 180s — minimal diff per the ask (the breach is PR-surface only; MQ is healthy and a tighten is a separate loosen/tighten measurement decision nobody asked for) |
| FR-3 drift arm: commit-time PR p90 lands above 960 | technical | pending - assumed: re-seed in the same commit to the next-minute ceiling of the re-measured p90 — mirrors the binding 2026-11-17 CTO ruling on the oracle slice (the TSV header mandates every bound ≥ commit-time re-measured p90, loosen legal only with the measurement recorded); abort/re-plan applies only on cannot-establish or a real regression |
| PR-body closing keyword vs standing tracker #12755 | technical | Ruled by CTO agent, 2026-11-17: Omit the closing keyword for #12755 — the tracker is the watch's standing report home that never auto-closes, and auto-close keywords fire anywhere in PR title or body; reference it as `Ref #12755`. (Binding ruling carried verbatim from the oracle slice, feat-one-shot-oracle-bound-row; not re-ruled.) |
| Eviction event (2026-11-18T11:45Z suite `cancelled` → gate fail-closed): file a new issue vs record-only | technical | pending - assumed: record-only in the runbook bullet — the workflow documents the third-arrival eviction arm as "accepted, NOT greened" (`tenant-integration.yml` mutex comment); one event in 30 runs is the documented residual, not an unowned defect |
| Brand-survival threshold `none` | taste | assumed: none — a CI-observability data row plus knowledge-base docs; the worst outcome is a red or quiet weekly watch run, no user-facing surface or regulated data |
