# Decision Challenges — feat-one-shot-12015-replay-a-pacer

No open challenge rows. The sole technical fork posed by the brief — 4th `--rows`
leg vs fixture-corpus bound for #12015 — was resolved by measurement inside this
pipeline, not by a judgment call needing a ruling: PR #12296 (merged
2026-11-07T13:45Z, after the Nov-3 report's five sampled runs) retired the 129
`row_ow_*` gated sites (~993s of arm `-a`'s gated work), and post-retirement
`merge_group` medians put `-a` at ~160s — the fastest arm — against `-b` ~226s
and `-c` ~166s. Neither remedy is warranted; the ruling evidence lives in
`measurements.md` in this directory and in the plan's Research Insights.
