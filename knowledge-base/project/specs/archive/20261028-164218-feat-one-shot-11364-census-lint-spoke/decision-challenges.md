---
title: "Decision challenges — feat-one-shot-11364-census-lint-spoke"
branch: feat-one-shot-11364-census-lint-spoke
plan: knowledge-base/project/plans/2026-10-28-content-census-lint-spoke-plan.md
issue: 11364
---

# Decision Challenges

Recorded during the planning phase of the one-shot pipeline. Technical and taste rows were ruled by a
single batched `soleur:engineering:cto` spawn in Rule mode on 2026-10-28 (evidence-checked against the repository).

| Item | Class | Ruling |
|------|-------|--------|
| Exact publish date (brief says "~Dec", after the hub's Nov 19–26 window) | operator (schedule) | 2026-12-03 proposed — Thursday, two weeks after the hub's social wave, clear of US Thanksgiving week; AC10 keeps filename, frontmatter, redirect key, `publish_date`, and strategy row coherent if the operator moves the slot |
| Distribution hold mechanism / follow-through probe | technical | Ruled by CTO agent, 2026-10-28: `status: scheduled` + `publish_date: 2026-12-03`, no probe, no new test, no `test-all.sh`/`test-affected-paths.sh` registration - `scripts/content-publisher.sh:884-896` fires a scheduled file on its date and flips a missed one to `stale` with an event; the hub was parked only because its prescribed window needed an operator lever; the Nov 17 spoke shipped `scheduled` with no probe; flip to parked+probe only if the date becomes a window |
| Closing technical link target | technical | Ruled by CTO agent, 2026-10-28: `https://github.com/jikig-ai/soleur/pull/11278` - merged, sole commit introducing the script (`git log --follow`), immutable, permitted by the brand guide's Blog note; the hub already links epic #10971, so this is distinct proof |
| Edit the already-merged hub with a retro-link sentence | technical | Ruled by CTO agent, 2026-10-28: yes - one facts-only sentence in the hub's census paragraph, no title/slug/meta change, no date promise; precedent is the 2026-10-23 arc hub edited by the hub PR; Eleventy has no future-date filter so the link cannot 404 |
| OG image generator | technical | Ruled by CTO agent, 2026-10-28: deterministic PIL, 1200x630, textless, `#1a1a1a` + gold, 3x supersample + LANCZOS; generate inline from `/tmp`, commit only the PNG (zero `.py` in the images dir); add an on-disk existence check because `seo-aeo-drift-guard` asserts key presence only |
| Post title — issue title vs founder-problem headline | taste | Ruled by CTO agent, 2026-10-28: primary "Your Alarm Passed Every Rehearsal. In Real Life It Never Rings."; fallback "Your Error Alerts Can Pass Every Test and Still Never Fire." - `brand-guide.md` `### Blog` requires the title/SEO title/description to name the founder's problem, not the mechanism; the issue title stays as the working title in notes and the PR body |
