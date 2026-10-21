---
branch: feat-one-shot-10402-feature-map-convention
---

# Decision Challenges — feat-one-shot-10402-feature-map-convention

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Skill-vs-convention (issue defers it to plan time): standalone `feature-map` scaffold skill vs test-browser-embedded convention | technical | Ruled by CTO agent, 2026-10-20: test-browser-embedded convention — `test-browser/references/feature-map.md` + SKILL.md producer/consumer edits - a scaffold skill's producer (route-file scan → skeleton) is framework-bound across arbitrary user stacks while the agent inside test-browser enumerates routes by reading the repo; a new skill also costs `docs/_data/skills.js` registration + `SKILL_DESCRIPTION_WORD_BUDGET` + component-table churn for zero added property — the identical shape the #10401 ruling took for "reference doc vs slim skill". The issue's own "~1 file + SKILL.md edits (~150 lines)" sizing agrees. |
| Canonical map path: `docs/feature-map.md` vs `test/feature-map.md` vs repo root | technical | Ruled by CTO agent, 2026-10-20: `docs/feature-map.md` - the issue names it verbatim, `test/` is not a universal repo shape, and a fixed root-relative path keeps every consumer's presence-check trivial; the `docs/`-publishes-a-site collision is handled by a note in the convention doc, not a second path. |
| Producer scope on first run: seed of exercised routes vs full-repo route enumeration | technical | Ruled by CTO agent, 2026-10-20: exercised-routes seed only - map entries carry observed selectors/expects/gotchas; an entry written for a route the agent never navigated fabricates the exact fields that make the map trustworthy (the presence-not-conformance class the #10399 battery caught). Unvisited discovered routes are not written; the update contract + optional lint keep the gap visible. |
| Refresh semantics: field-scoped update vs wholesale regenerate | technical | Ruled by CTO agent, 2026-10-20: field-scoped - update only fields a run contradicted, append entries for newly-exercised routes, leave untouched entries and the header byte-identical; a wholesale regenerate destroys operator annotations and produces noisy diffs on every run. |
| ux-audit/reproduce-bug pointer generalization (not named in the AC) | operator (scope) | inferred — justification recorded in plan Scope Check: #10726 wired all four consumers to the same citation shape; generalizing only the AC-named two leaves half the convention teaching a soleur-only path. |
| Plan-review taste finding: the five-arm lint sketch inside the convention doc could be trimmed (the AC's "regenerate-on-run or lint hint" is already satisfied by refresh-on-run alone) | taste | kept — the sketch is ~15 lines of the doc and is the "lint hint" arm's only concrete content; without it the drift story rests entirely on agent-run cadence. Surface for ship's action-required render; no rework applied. |
