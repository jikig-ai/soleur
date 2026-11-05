# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-05-fix-ci-claude-cli-pins-bun-1-4-4-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- cto_spawns=1 (planner; rulings F1-F6 (F5 ruled with F1; F6 plan default))

### Errors
None blocking. collision-precheck exit 10 was this branch's own draft PR.

### Decisions
- CLI_VERSION -> exactly 2.1.311; no pin-table row edit (value-agnostic).
- claude-code-action -> v1.0.263 (tag-object SHA 3b7e1a45ca6f231c62605aabcf79e6a41b08c7da) in 4 workflows + constraint-scaffold template; no claude_code_version input exists.
- pen-cli lock: exact overrides entry for agent-sdk 0.3.311, gated on engine-contract-probe.sh.
- operator-digest pin v1.0.101 left out; follow-up issue.

### Components Invoked
soleur:plan, soleur:deepen-plan, learnings-researcher, cto

## Review Phase (panel SHA 8283f95517)

Tier: aggregate pattern (source: plan). Class: non-code. Seats (7): git-history, pattern, security, code-quality, user-impact, code-simplicity, architecture. Coverage consult: 3 leads, all already covered by seats.
dedup: 31 raw -> 11 unique. No P1.

| raw finding | canonical defect key | reporting seat(s) | planned fix |
|---|---|---|---|
| PR body is the draft stub; ACs claim "in the PR body" | claim outran check: PR body evidence | git-history, quality, impact | ship writes the body; ACs reworded (this round) |
| branch dispatch of test-pretooluse-hooks is skip-masked | verification that cannot verify | quality, impact, lead | plan 2.6, F2 note, tasks, post-merge AC on main |
| article-30-register.md:712 states v1.0.236 as current | stale present-tense legal claim | git-history, architecture, quality, pattern | dated update in the register |
| operator-digest pin v1.0.101 and already-scaffolded customers unfiled | deferred scope with no tracker | git-history, impact, security, pattern | one consolidated follow-up issue |
| ADR-182 / runbook cite 2.1.228 with no note on the 2.1.311 canary re-run | dated measurement not superseded | architecture | dated addenda |
| model-launch-review says bump only with a --model swap | governing text contradicts this PR | architecture, pattern | one-sentence carve-out in SKILL.md |
| no lockstep guard across action SHAs, CLI_VERSION, override | pre-existing gap | architecture | follow-up issue checklist item |
| transcript refresh has no reader, records npm 11.20.0 | churn | simplicity, git-history | reverted to origin/main |
| no ADR-191 note or drop condition for the SDK override | undocumented pin | pattern, architecture, security, simplicity | ADR-191 addendum |
| over-long comment line fix-constraints-stage-a.yml:103 | cosmetic | pattern, simplicity, architecture, quality | reflowed to "verified at v1.0.263" |
| plan wording: tag-object convention, dead learning path, F1-F4 vs F1-F6, existing scaffold customers | plan accuracy | git-history, quality, impact | plan/spec edits |

Not acted on (pre-existing, wontfix): follow-through probe header text (retires with the tracker), spike/package.json SDK range, stale open issue for a deleted workflow, unsigned upstream tag.
