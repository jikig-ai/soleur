# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-20-fix-one-shot-collision-gate-body-probe-plan.md
- Status: complete

### Errors
None blocking. Two self-inflicted issues were caught and corrected in-session, both recorded in the plan:

- The first violation-sweep used `grep -v 'knowledge-base/project/learnings/'`, which matched that path cited in the offending line's own prose and filtered out the one real violation, reporting a false-clean sweep. Corrected to a filename-anchored `awk -F:` exclusion.
- The v1 lint design was disarmed by the Phase 1 output itself (the mechanism note puts `--state` in the same line's prose, so a line-based filter excluded it unconditionally). Reproduced empirically and redesigned onto extracted command spans.

### Decisions
- **The issue's stated root cause is falsified.** GitHub does NOT strip the leading `#` — `gh search prs` returns byte-identical results with and without it (independently re-verified by the pipeline runner: T3 == T4). The real defect is that `gh pr list` defaults to `--state open` and appends an open-state filter unless it detects an in-query state qualifier; a leading `#` defeats that detection, so `is:merged` + the appended open filter is a contradiction returning zero rows for every input. Verified: `gh pr list --search "#6608 in:body is:merged"` -> `[]`, while `gh pr list --state merged --search "#6608 in:body"` -> `[6664, 6639]`.
- **Fix is `--state merged`, not the issue's proposed bare number.** Both work, but dropping `#` works only via `gh`'s undocumented client-side qualifier sniffing — the same fragility class that caused the bug. `--state` is a documented public flag and mirrors the sibling probe.
- **Item 2 resolved: the `linked:issue` probe is NOT dead.** Verified against two genuinely formally-linked pairs (#6737 -> #6743, #6724 -> #6727), identical with and without `#`. No change needed; to be recorded in the PR body so it is not re-litigated.
- **Item 3: form-lint over live-API test, and the invariant is a `--state` check, not a `#`-prefix check.** A `#`-prefix lint would guard the wrong thing. Live-API rejected on measured evidence — the plugin suite is hermetic by codified rule (`cq-test-fixtures-synthesized-only`), the repo already engineered network out of this exact shard, the search index has documented lag, and it would gate every repo PR on network health.
- **Scope grew on review evidence.** Plan-review proved fixing the query alone leaves the blind spot open: the probe's hits had no consumer on the path it fires on, and the nearest discriminator (`closingIssuesReferences`) is empty by construction for body-probe hits — measured `[]` for all four `#6197` hits including the true positive #6209, so it would wave through the real collision. Plus a live third instance of the same defect class in `triage/SKILL.md:32`.
- **One deferral filed as in-scope work:** extending the `--state` lint beyond `skills/*/SKILL.md` to the ~19 repo-wide call sites needs prose-vs-command context restriction — deliberately narrowed with a tracking issue rather than left as an unmentioned gap.

### Components Invoked
- `Skill: soleur:plan`
- `Skill: soleur:plan-review` — 6 parallel agents: `dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplifier`, `architecture-strategist`, `spec-flow-analyzer`, `engineering:cto`
- `Agent: Explore` (test/CI convention research)
- `Skill: soleur:deepen-plan` — gates 4.5/4.6/4.7/4.8/4.9 executed; 4.7 filled fail-closed
- `gh` CLI (live premise validation, ~30 measured queries), `bun test` (lint design pre-verified red/green), `markdownlint-cli`, `git`
