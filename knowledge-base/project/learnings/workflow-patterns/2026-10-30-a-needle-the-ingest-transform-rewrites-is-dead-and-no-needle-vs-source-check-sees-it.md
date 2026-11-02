---
title: A needle the ingest transform rewrites is dead, and no needle-vs-source check sees it
date: 2026-10-30
category: workflow-patterns
tags: [betterstack-alerts, vector, pii-scrub, drift-guards, needle-derivation, inngest-luks]
---

# Learning: a needle the ingest transform rewrites is dead, and no needle-vs-source check sees it

## Problem

Every marker/needle guard in the alert family compares the SQL predicate to the *emitted* row shape
(source-derived literals, mutation proofs) — but journald rows pass through
`vector.toml`'s `pii_scrub_string` before ingest, which rewrites `token=<v>` to `token=[redacted]` on
every row (Art-9 credential alternation). A predicate conjunct `position(message,'token=fail_')>0` is
therefore **dead for real rows** — every verdict (ok/fail_*/indeterminate) collapses to
`token=[redacted]`, indistinguishable. The `#11527` leg-A conjunct and the pre-#11527 predicate were
both unfirable, latent only because the probe is inert pre-#11266.

No presence or mutation row could catch this: needle-to-source agreement was perfect; the defect
lives between the emit and the warehouse, in a transform neither side names.

## Solution

Two-layer fix, shipped in the #11527 fix round:

1. **Immunity by vocabulary, not regex luck.** Rename the emit key to `verdict=` — a word that shares
   zero vocabulary with the scrub alternation (`user_?id|api_?key|apiKey|token|password|secret|passwd|
   credentials?`). `probe_token=`/`token_class=` survive today's regex only on a `\b` technicality and
   keep the credential word that caused the collision — a standing invitation for a future scrub
   widening. The scrub is the Art-9 boundary: the format adapts, never the redaction (no carve-outs).
2. **Scrub-immunity presence row + mutation in the guard.** Assert the needle key is absent from
   `vector.toml`'s `replace(msg …)` rewrites, with a mutation that inserts the key into the
   alternation and must go RED. Limitation recorded in-comment: the check pins the `replace(msg`
   idiom; a `del(`/`map_values` rewrite evades it — proportionate today.

Do not substitute `at=`/`rc=` semantics for a verdict key — `at=key` is shared by
`fail_key_absent` and `indeterminate`, `at=uuid` by `fail_header` and `indeterminate`; no
`at`/`rc` disjunction expresses the fail set.

## Key Insight

The verification surface is THREE points, not two: emit contract, ingest transform, warehouse
predicate. Any review or guard that checks only emit↔predicate agreement misses the middle — the
pipeline stage whose whole job is rewriting rows. When a needle dies there, synthetic evals still
pass (they inject `raw` rows pre-scrub — proven in Phase-2 control E, which scored 1 on a needle
that could never match a real row).

Second-order: window-cost asymmetry favors fixing format defects *while a system is inert* — the
rename was free pre-#11266 (zero live rows, no consumer contract) and would be load-bearing forever
after bundle delivery. The "defer until live" instinct is exactly wrong here.

## Tags

category: workflow-patterns
module: betterstack-alerts
symptoms: needle-dead-before-ingest, synthetic-eval-passes-on-unfirable-predicate
