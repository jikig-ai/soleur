---
branch: feat-one-shot-11832-9782-probe-hygiene
date: 2026-11-03
---

# Decision Challenges — feat-one-shot-11832-9782-probe-hygiene

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| #11893 paused `inngest_cutover_flip_silent` alert — fold a re-enable into this PR, file a tracking issue, or leave for the epic? | taste | Ruled by planner, 2026-11-03: leave for epic #10390, no fold-in - PR #11893's body states re-arming "is one line, to be made together with a measured evaluator fix on a live alert"; the pause is gated on an unvalidated Better Stack evaluator (observable only through a live incident), not on #11869's closure. A bare `paused` flip without the evaluator fix re-arms an alert the incident showed cannot evaluate, and it carries a guard-row change (mutation row A13 pins the pause) on a convention-suite surface this batch does not otherwise touch. Recommend an epic-tracked follow-up bundling re-arm + measured evaluator fix. |
| #9659 (gh issue-dedupe residuals — 14 bare/silent sites across ~11 `.github/workflows/*` files) as optional third seat? | taste | Ruled by planner, 2026-11-03: ruled OUT - the batch brief scopes "same scripts/followthroughs/ + loader surface"; #9659 touches zero followthrough files and is its own mechanical sweep over a different convention family (workflow dedupe sites vs. probe verdict semantics). Folding it triples the diff and mixes defect classes. Same `meta/machinery` theme, different files — epic material, not this PR. |
| Epic #10390 stale checklist rows (#8595, #8841, #9139, #8874, #8316, #9705 — plus #8764 and #10136 found stale on the same lines) — tracked file or post-merge action? | taste | Ruled by planner, 2026-11-03: post-merge comment/edit action - verified `git grep -n '10390' knowledge-base/` returns only citations (runbooks, ADRs, archived specs); no tracked file carries the epic body. All eight issues confirmed CLOSED via `gh issue view`. Ship posts a checklist-refresh comment or body edit ticking them (plus #11832/#9782 on closure). |
| #5150 `<!-- soleur:followthrough -->` directive strip — diff item or post-merge? | taste | Ruled by planner, 2026-11-03: post-merge `gh issue edit` action - the directive lives in #5150's GitHub body (line 9, confirmed 2026-11-03); no repo edit can remove it. Timing: strip alongside/after merge so the sweeper's closed-set pass stops resolving a deleted script path. |
| Add a verdict-matrix `.test.sh` for the 7463 probe — beyond the issue's stated fix ("one jq guard + one failure arm")? | taste | Ruled by planner, 2026-11-03: include - recorded in the plan's Scope Check as `inferred`: the 7463 probe is the only `scripts/followthroughs/` probe found without a suite, and the never-PASS defect class is exactly what the registered exit-code harness convention exists to pin. |
| Brand-survival threshold for the batch | taste | Ruled by planner, 2026-11-03: `none` - internal CI verification tooling; worst case is an operator-visible sweeper/CI signal, no user artifact or data surface. |
