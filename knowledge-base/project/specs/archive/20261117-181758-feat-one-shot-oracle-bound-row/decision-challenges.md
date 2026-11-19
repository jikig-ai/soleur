# Decision Challenges — feat-one-shot-oracle-bound-row

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
| PR-body closing keyword vs standing tracker #12755 | technical | Ruled by CTO agent, 2026-11-17: Omit the closing keyword for #12755 — the tracker is the watch's standing report home that never auto-closes, and auto-close keywords fire anywhere in PR title or body; reference it as `Ref #12755`. |
| FR-4 drift arm: commit-time p90 lands above a seed | technical | Ruled by CTO agent, 2026-11-17: Re-seed in the same commit to the next-minute ceiling of the re-measured p90 — the TSV header mandates every bound >= the commit-time re-measured p90 with loosen only when the measurement is recorded; abort/re-plan applies only on cannot-establish or a real regression. |
| No file-vs-file parity test binds the bounds TSV to `required-checks.txt` — the unbound-finding class recurs when the next check goes required without a row | technical | Ruled by CTO agent, 2026-11-17: Deferral with a filed `action-required` follow-up is correct — the watch already enforces the unbound class within <=7 days with a named offender, and the ask's scope constraint forbids script/test changes here. |
| Brand-survival threshold `none` | taste | assumed: none — a CI-observability data row plus knowledge-base docs; the worst outcome is a red or quiet weekly watch run, no user-facing surface or regulated data |
