# Decision Challenges — feat-one-shot-11774-p90-wallclock-ratchet (#11774)

Rulings rendered inline by the planning process acting in the CTO rule role (sequential-fallback — Devin subagent has no nested-spawn tool; soleur:engineering:cto definition read at PLUGIN_ROOT/agents/engineering/cto.md, BINDING interface). Re-rule on review dissent.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Wall-clock definition: completed_at minus run.created_at (queue+runner+exec, PR-experienced) vs started→completed (execution only) | technical | Ruled by CTO agent, 2026-11-02: primary bound metric is latency (completed_at - run.created_at); duration kept as diagnostic column - the epic's "wall-clock" is what a PR/queue entry experiences and the runbook cohort model counts queue; execution-only would hide queue drift behind a green ratchet (inline ruling, sequential-fallback) |
| Bound seeding: measured-baseline + margin vs epic targets (1200s/900s) | technical | Ruled by CTO agent, 2026-11-02: seed bounds.tsv from measured p90 at implementation time, NOT the epic target - current test latency ~38-39 min so epic-target bounds fire on first run and stay red, training operators to ignore the ratchet; epic-goal columns still shown in the weekly table so progress tracks (inline ruling, sequential-fallback) |
| Report home: standing tracker issue body rewritten weekly vs committed report file / bot PR | technical | Ruled by CTO agent, 2026-11-02: standing tracker body - zero new write machinery, matches the watch-owned find-or-file precedent, and the digest allowlist already permits gh issue list; a committed file would need a bot-PR path for marginal gain (inline ruling, sequential-fallback) |
| Non-ci required contexts (cla-check, gitleaks, etc.) coverage | technical | Ruled by CTO agent, 2026-11-02: cover all required-checks.txt rows via the uniform commits/{sha}/check-runs read on sampled ci run heads - non-ci contexts trigger on the same push so the shared anchor is honest; unmeasurable/zero-sample contexts are reported, not dropped (inline ruling, sequential-fallback) |
| Missing-data arm exit semantics: report+exit 0 vs sibling exit 3 | technical | Ruled by CTO agent, 2026-11-02: exit 0 for zero qualifying samples per the issue's "missing data -> report, never fail"; exit 3 reserved for probe-health failures (gh API down) - a broken probe must not read as green, which the issue's wording does not cover (inline ruling, sequential-fallback) |
