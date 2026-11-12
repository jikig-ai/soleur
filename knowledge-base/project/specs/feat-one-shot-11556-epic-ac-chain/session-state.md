# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-12-ci-epic-11556-ac-chain-followthrough-plan.md
- Status: complete

### Errors
- `mechanical` is not a valid decision-challenge class → reclassed `taste` (fixed in-subagent)
- `gh issue view --jq` number+string concat error → fixed jq shape (fixed in-subagent)
- 4 `pending - assumed` technical rows remain in decision-challenges.md → parent carries ONE batched soleur:engineering:cto spawn before work (technical-ruling-gate)

### Decisions
- Probe `main-health-monitor-mutations-12626.sh` discriminates scheduled runs by `actor.login == "soleur-ai[bot]"` + `created_at >= 2026-11-12T19:46:34Z`, cancelled excluded, per-run mut-leg assertion, exit vocabulary 0/1/2/3/78
- Classifier follow-up issue: in-job detect step modeled on verified ci.yml:2137–2168, fail-closed, v1 markdown-only allowlist, `--rows` lever folded in (binding CTO carry), refs #11556/#12626/#9729
- Lever-A re-rank via merge_group `suite-timings-scripts-*` + `regenerate-shard-manifest.py --timings-dir/--runs`; stale 185400ms row at suite-durations.tsv:429 to be reconciled against regenerated table
- Lever-F/p90 measured via watch-wallclock-p90-11774.sh --dry-run (goals 1200s PR / 900s merge_queue); critical path now `test-scripts (6/8)` 2483s
- #12269 soak untouched; #12647/#12651 verified OPEN; trackers #12455/#12618 CLOSED — 18:00Z run 43275349911 failed on PRE-merge code (sha 2f8e28a164), not a regression

### Components Invoked
- soleur:plan (full execution incl. plan-sharp-edges.md)
- soleur:deepen-plan (all phases; Reviewed-Coverage: sequential-fallback — no nested-spawn in this harness)
- scripts/lint-guard-contract.py, plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh, markdownlint-cli2, gh

## Operator Constraints
None present in the resume brief — the brief carries no `## Operator Constraints` section, no HOLDS list, and epic #11556's body carries none (verified live at Step 1.5: zero holds-list markers).

## Work Phase
- Status: pending (gate: batched CTO spawn over 4 pending technical rows, then soleur:work)

## Technical-ruling gate
- cto_spawns=1 (batched, 4 rows): all four pending technical rows ruled `Ruled by CTO agent, 2026-11-12` — each confirmed its assumed default (N=2 close threshold; actor.login discriminator; cancelled excluded; per-run leg assertion). No plan/tasks amendment needed (rulings == assumed defaults).
- technical-ruling-gate.sh --branch: PASS (8 rows)
