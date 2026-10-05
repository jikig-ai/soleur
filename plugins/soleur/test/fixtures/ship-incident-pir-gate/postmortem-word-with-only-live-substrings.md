# Plan — move the parser out of prose and into a real file

Synthesized fixture, the `live`-substring twin of the `produce*` one. It carries
outage vocabulary (`post-mortem`) alongside ONLY `live` SUBSTRINGS — `lives` on
the right, `delivery`/`delivered`/`deliverables` on the left — and no other member
of the alternation. Every excluded token named in this paragraph is backticked,
which the gate strips before matching.

The 2026-01-02 test-pipeline post-mortem listed six items. Three of its
deliverables were descoped and the reasons were delivered as one tracker rather
than three.

## Where the logic belongs

The gate lives in a real script that owns its own regexes, so a parity harness can
execute it rather than scrape literals out of Markdown. The allowlist lives beside
it. Neither lives in prose any more, which is the whole point of the change.

Delivery of the remaining three items is unblocked once the interference bug on
the parallel runner is diagnosed.
