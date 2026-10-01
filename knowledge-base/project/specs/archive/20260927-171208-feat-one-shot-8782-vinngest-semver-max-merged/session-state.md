# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-27-ci-vinngest-semver-max-merged-into-main-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None (a blocked scratch `rm -rf` and an invalid `gh` JSON field were retried).

### Decisions
- Precondition verified: main pins vinngest-v1.1.40 at all four sites; that tag is on main and is both merged-max and overall max, so the switch causes no downgrade.
- No workflow edits for checkout depth: all consuming jobs use `fetch-depth: 0` + `fetch-tags: true`.
- Shallow refusal moves ahead of target resolution; an empty merged-tag set fails loudly (new row B9b).
- Off-main tags are excluded by construction rather than refused; legacy-pin and deleted-tag refusals merge into one downgrade refusal. Parity check becomes byte-equality between the two selector blocks.
- Anchor stays `HEAD` (not `origin/main`); taste decisions recorded in `decision-challenges.md`.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; learnings-researcher, dhh/kieran/simplicity reviewers, cto, test-design-reviewer, prototype + claims-verification subagents.
