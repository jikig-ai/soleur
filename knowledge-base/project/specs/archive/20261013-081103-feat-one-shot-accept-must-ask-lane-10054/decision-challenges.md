# Decision challenges - feat-one-shot-accept-must-ask-lane-10054

Taste and scope items raised by the plan-review panel (2026-10-12) that the plan did not silently apply. Recorded per ADR-084;
`ship` renders this into the PR body.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| DC-1 Release-level bisect (Tier 2) | operator (scope) | Operator asked to "bisect the @anthropic-ai/claude-agent-sdk 0.3.x versions"; DHH, simplicity, CTO and spec-flow asked to cut it because the notice date depends only on the pinned versions. The plan keeps it conditional (only between two adjacent pins that disagree) and capped (6 versions x 2 runs); it never gates the notice. Operator may cut it entirely. |
| DC-2 ADR-277 numbers sequenced after the windows | operator (scope) | Operator asked to "record measured numbers in the ADR-277 addendum"; the plan writes a dated soak-open pointer now and the numbers in the flip PR, because the 24 h and 7 d windows cannot elapse in this run and interim n=0 counts carry no information (simplicity, DHH). Operator may instead want interim counts recorded now. |
| DC-3 One PR versus two | taste | DHH suggested Guard 2 + Phase 0 now and probe, bisect and records after; the plan keeps one PR because the Guard 2 fix and the re-timed directives must land before 2026-10-13T18:00Z while the probe and records need no deadline - a split is reasonable if the operator prefers a smaller first merge. |
| DC-4 Live `gh` case count | taste | CPO wants the destroy families exercised; simplicity wants zero live `gh` cases. The plan keeps one (`gh repo delete`) and covers the rest by corpus and unit rows. |
| DC-5 Plan ceremony | taste | DHH and CTO read about two-thirds of the plan as ceremony (Scope Check, Guard Contract, Cut List). Those sections are gate-mandated (`plan` Phases 2.4, 2.12, 0.6b); not trimmed beyond duplicates. |
| DC-6 Equivalence for the dev-hosted C9 observation | operator (legal-risk) | CLO advisory (internal) accepts real-SDK probe plus production lane telemetry as a substitute; CPO asks that it be worded "proposed, pending operator ratification". The plan words it that way; ratification is the operator's. |

## Review round (2026-10-12, PR #10101) — deviations from the plan, recorded

- **DECODABLE stays unisolated** (plan Guard 2 (i) said all three counts). The stored-row check asks whether the body is stored rows at all; isolating it makes the measured contamination shape (only another service's rows) exit 3 "none is a stored row", which contradicts the plan's own M6. The plan's isolation applies to MENTIONS and ROWS.
- **MENTIONS isolation is by POSITIVE exclusion**, not by positive inclusion (user-impact P1): a marker-mentioning row is dropped only when its `raw` decodes to an object whose CONTAINER_NAME is another container or absent; an undecodable row still counts toward SHAPE_DRIFT.
- **Liveness strengthened** beyond "any row" (architecture, security, user-impact, structural seats converged): one app-container WARN row in the last 3 hours, and for 7d rows on at least 6 calendar days. The performance seat's `LIMIT 1` existence probe was declined: the 7d read measured 2 s against the query script's 60 s cap, and the recency and day columns need the aggregate.
- **Declined, recorded:** exact small counts in the public sweeper comment (pre-existing since #9977; the CLO under-5 rule scopes to recorded artifacts; operator decision); hosted-container sandbox witness (not obtainable from the dev host; stated in the probe header and ADR-284); the probe's `\bmain\b`-style leak regex narrowing (fails closed; flush added).
- **Operator decisions surfaced by review (not decided):** public-repo disclosure ordering of the inert-window records before the notice decision; the T&C 3a.7 "always blocks" sentence (CLO); the criterion-4 / limb (b) ratification.
- **Declined (verification pass, P3):** the soak script raises SHAPE_DRIFT only when no lane row decodes (`TOTAL == 0`), so one decodable row plus undecodable marker rows reads `asks=1`. A row that decodes means the lane fires and the ask thresholds are evaluated on it; changing the drift rule after the mutation batteries would reopen them for a notify-only sweeper. Revisit if the stored shape changes. The same pass found the PR body lacked the operator gates; they go in at ship.
