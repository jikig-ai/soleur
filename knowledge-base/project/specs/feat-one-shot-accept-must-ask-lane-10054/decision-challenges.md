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
