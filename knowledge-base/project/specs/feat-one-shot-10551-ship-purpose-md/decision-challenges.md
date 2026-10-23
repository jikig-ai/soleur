# Decision challenges - feat-one-shot-10551-ship-purpose-md

Recorded at plan time (headless pipeline). Every row below is a technical ruling made by the CTO
agent with the verified evidence in the plan's `## Research Insights`; none overrides a direction
the operator stated, so no operator row is needed. The operator's own instruction (stop after the
capability finding if the harness cannot clear `ship`) is followed, not challenged. T2 was ruled
twice: the first ruling proposed a neutral-refactor mode, and plan review showed the existing
`--target-task` flag already covers it, so the second ruling withdrew that part.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| T1 does the eval harness clear the gate for ship today | technical | Ruled by CTO agent, 2026-10-23: no, stop and do not shorten ship - ship is not a gated target (--check returns gated:false, --dry-run --target ship dies with no promptfoo resources) and the harness scores one closed-enum token per task, so it can only speak for a wrapped slice |
| T2 smallest change that closes the gap | technical | Ruled by CTO agent, 2026-10-23: sentinel-wrap one closed-enum ship decision with its Why paragraphs, add a ship-decision target in the per-target places, and run the gate with a retention case through the existing --target-task flag and without --append-on-accept; no change to verdict.cjs or eval-gate.cjs and no neutral-refactor mode, which would be a shared-gate bypass - the code already accepts any synthesized target row |
| T2b discrimination bar before the gate may be called able | technical | Ruled by CTO agent, 2026-10-23: a degraded candidate returns accept:false while a rationale-removed one returns accept:true, the skill-arm rate beats the baseline-arm rate by at least one task-equivalent, a one-task flip is reported per task or checked with an explicit epsilon below one task-equivalent, the 0.5 trust floor stays only a floor, and every decision-bearing rule in the slice has a case; no corpus-size number is set because the code does not justify one |
| T3 may a rationale-only-diff lint replace the harness criterion | technical | Ruled by CTO agent, 2026-10-23: no, the issue criterion names the harness; the lint is a recommended complement scoped by the capability PR's own plan, and relaxing the criterion would be a scope change that is not asked because stopping needs no answer |
| T4 where the capability gap is recorded | technical | Ruled by CTO agent, 2026-10-23: one comment on #10551 naming the missing pieces, no new issue, and no comment on any other WikiSkills issue |
