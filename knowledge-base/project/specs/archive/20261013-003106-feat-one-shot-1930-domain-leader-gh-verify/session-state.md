# Session State

## Plan Phase

- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-1930-domain-leader-gh-verify/knowledge-base/project/plans/2026-04-10-fix-domain-leader-gh-verify-task-prompt-plan.md
- Status: complete

### Errors

None

### Decisions

- The issue #1930 misattributes the problem: all 8 domain leader agent files already have the `gh issue view` instruction (commit a558001a). The actual gap is in the Task Prompts in `brainstorm-domain-config.md` used to spawn domain leaders, which lack the verification instruction.
- Root cause has two layers: (1) Task Prompts lack `gh issue view`, and (2) spawning uses anonymous Tasks instead of named agent Tasks (`Task cto(...)`) so agent file instructions never load.
- Approach A (add `gh issue view` to Task Prompts) chosen for this PR as the minimal, low-risk fix. Approach B (change to named agent spawning) deferred as a separate issue due to larger scope and spawning semantics change.
- The 2026-02-22 learning ("domain-leader-extension-simplification-pattern") contains a contradicted assumption -- it claims `Task cto:` loads full agent instructions during brainstorm, but the actual brainstorm SKILL.md never uses that syntax.
- Minor CCO wording normalization ("a specific GitHub issue" to "a GitHub issue") included for consistency.

### Components Invoked

- `skill: soleur:plan` -- created initial plan
- `skill: soleur:deepen-plan` -- enhanced plan with root cause analysis, alternative approaches, learnings research, and edge case documentation
- `gh issue view 1930` -- verified issue state
- `git show a558001a` -- analyzed original fix commit
- `npx markdownlint-cli2 --fix` -- validated Markdown formatting
- `git commit` + `git push` -- committed and pushed plan artifacts (2 commits)
