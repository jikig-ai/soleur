# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-05-fix-ci-claude-cli-pins-bun-1-4-4-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- cto_spawns=2 (planner: rulings F1-F6 (F5 ruled with F1; F6 plan default); review round: F7)

### Errors
None blocking. collision-precheck exit 10 was this branch's own draft PR.

### Decisions
- CLI_VERSION -> exactly 2.1.311; no pin-table row edit (value-agnostic).
- claude-code-action -> v1.0.263 (tag-object SHA 3b7e1a45ca6f231c62605aabcf79e6a41b08c7da) in 4 workflows + constraint-scaffold template; no claude_code_version input exists.
- pen-cli lock: exact overrides entry for agent-sdk 0.3.311, gated on engine-contract-probe.sh.
- operator-digest pin: deferred by F4, then folded in by F7 (review round); one follow-up issue remains.

### Components Invoked
soleur:plan, soleur:deepen-plan, learnings-researcher, cto

## Review Phase (panel SHA 8283f95517)

Tier: aggregate pattern (source: plan). Class: non-code at panel time (the fix round then added a vitest suite and a shell probe). Seats (7): git-history, pattern, security, code-quality, user-impact, code-simplicity, architecture. Coverage consult: 3 leads, all already covered by seats.
dedup: 40 raw findings across the 7 seat reports -> 11 canonical defect keys (P3 notes folded into the key they belong to). No P1.

| raw finding | canonical defect key | reporting seat(s) | planned fix |
|---|---|---|---|
| PR body is the draft stub; ACs claim "in the PR body" | claim outran check: PR body evidence | git-history, quality, impact | ship writes the body; ACs reworded (this round) |
| branch dispatch of test-pretooluse-hooks is skip-masked | verification that cannot verify | quality, impact, lead | plan 2.6, F2 note, tasks, post-merge AC on main |
| article-30-register.md:712 states v1.0.236 as current | stale present-tense legal claim | git-history, architecture, quality, pattern | dated update in the register |
| operator-digest pin v1.0.101 and already-scaffolded customers unfiled | deferred scope with no tracker | git-history, impact, security, pattern | digest pin folded in (CTO F7); issue 12146 tracks the post-merge run and the scaffold refresh path |
| ADR-182 / runbook cite 2.1.228 with no note on the 2.1.311 canary re-run | dated measurement not superseded | architecture | dated addenda |
| model-launch-review says bump only with a --model swap | governing text contradicts this PR | architecture, pattern | one-sentence carve-out in SKILL.md |
| no lockstep guard across action SHAs, CLI_VERSION, override | pre-existing gap | architecture | built inline: apps/web-platform/test/claude-pin-lockstep.test.ts (CONCUR ruled it fix-inline) |
| transcript refresh has no reader, records npm 11.20.0 | churn | simplicity, git-history | reverted to origin/main |
| no ADR-191 note or drop condition for the SDK override | undocumented pin | pattern, architecture, security, simplicity | ADR-191 addendum |
| over-long comment line fix-constraints-stage-a.yml:103 | cosmetic | pattern, simplicity, architecture, quality | reflowed to "verified at v1.0.263" |
| plan wording: tag-object convention, dead learning path, F1-F4 vs F1-F6, existing scaffold customers | plan accuracy | git-history, quality, impact | plan/spec edits |

Not acted on (pre-existing, wontfix): follow-through probe header text (retires with the tracker), spike/package.json SDK range, stale open issue for a deleted workflow, unsigned upstream tag.

## Fix round 1 (fix range 8283f95517..7d3b8d019a)

Seats (4, report-only): test-design, security, architecture, code-quality. Coverage consult earlier: none plausible beyond seat coverage. No P1.
dedup: 4 reports -> 7 canonical keys, all fixed in a68610cc47 or this commit:

| canonical defect key | reporting seat(s) | fix |
|---|---|---|
| digest allowlist still split on v1.0.263 (space-bearing rules), CTO parse claim half right | security | quote the `--allowedTools` value; pin the quoting in operator-digest-workflow.test.sh; lead note on F7 |
| ADR-191 addendum claims SDK 0.3.310 embeds a Bun below the fix (false; measured Bun 1.4.4) | security, code-quality | addendum reworded to pair alignment; plan and F3 lead note |
| guard population hardcoded; guard enforces one pair not the fixed pair; case/subpath/Dockerfile/lock gaps | test-design | discovery scan vs explicit carriers, tag floor, regex hardening, install-line and lock-sibling assertions; 8 new mutation rows reddened |
| skill, script and carve-out disagree on the bump rule | architecture, code-quality | one rule in SKILL.md row, carve-out and audit-models.sh; advisory link or measured version required |
| probe tracker lookup capped at 200 of 312 open issues; box regex column-0 only | security, code-quality | probe reads issue 12146 by number; indented and star boxes counted |
| stale scope sentences (plan, session-state, tasks), ledger count, ADR-182 form | architecture, code-quality | plan/spec edits; ADR-182 addendum as a heading |
| evidence only in history (probe 145 PASS on npm 11.20.0, canary 2084) | code-quality | copied into the PR body at ship |

Not acted on (pre-existing or recorded): Art. 30 register lines 700 and 719 (v1.0.161 text predating this PR), ADR-074:171 (dated verification), digest-scrub.sh has no GitHub-token pattern and the checkout token sits in .git/config readable by the agent (pre-existing, outside this PR; mentioned in the final report).
