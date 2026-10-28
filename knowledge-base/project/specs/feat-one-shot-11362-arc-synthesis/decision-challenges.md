---
title: "Decision challenges — feat-one-shot-11362-arc-synthesis"
branch: feat-one-shot-11362-arc-synthesis
plan: knowledge-base/project/plans/2026-10-28-content-testsuite-arc-synthesis-plan.md
issue: 11362
---

# Decision Challenges

Recorded during the planning phase of the one-shot pipeline (headless — no
Agent/Task tool available in this subagent context, so technical rows carry
`pending - assumed:` rulings per the pipeline's delegation rule rather than a
`Ruled by CTO agent` line).

| Item | Class | Ruling |
|------|-------|--------|
| Exact publish date inside the brief's Nov 19–26 window | operator (priority/schedule) | pending - assumed: 2026-11-19 (first open Thursday slot after the Nov 17 committed item; AC12 keeps filename, frontmatter, redirect key and publish_date coherent if the slot moves) |
| Distribution hold mechanism for the window | technical | pending - assumed: `status: parked` + `publish_date: 2026-11-19` (the documented hold lever — measured against `content-promotion.ts`: a `status: draft` file would promote to the earliest free Tue/Thu slot ~Oct 29) plus notify-only follow-through probe `scripts/followthroughs/parked-green-synthesis-11362.sh` to wake the `parked → scheduled` flip inside the window |
| Post title — issue headline #4 vs the brief's marked-lead #1 | taste | pending - assumed: "First We Made 'Green' Mean Something. Then We Made It Fast." (the issue's own title and the proposed pipeline-row name); the lead alternative "A Skipped Test Counted as a Pass. So We Rebuilt the Scoreboard." is recorded in the Draft Spec as the writer's re-angle option |
| LinkedIn Personal T+4–7d stagger vs single publish_date per file | technical | pending - assumed: all four channels publish on the window date — the distribution contract carries one `publish_date` per file and the #10902 hub's file made the same simplification; a two-file stagger would double the parked/flip surface |
| Closing technical link target | taste | pending - assumed: `https://github.com/jikig-ai/soleur/issues/10971` (the public epic whose close comment enumerates all twelve children and their PRs — the richest public write-up) |
| OG image generator — PIL vs gemini-imagegen | technical | pending - assumed: deterministic PIL (1200×630, `#1a1a1a` + gold geometry, textless) — `soleur:gemini-imagegen` unavailable, #10940 OPEN; PIL shipped the sibling card in #10939 and is the documented convention |
