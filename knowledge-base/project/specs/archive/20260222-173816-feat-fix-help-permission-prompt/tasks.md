# Tasks: Fix Help Command Permission Prompt

## Phase 1: Implementation

- [ ] 1.1 Rewrite `plugins/soleur/commands/soleur/help.md` Step 1 to use Read tool prose instead of `cat` bash block
- [ ] 1.2 Rewrite `plugins/soleur/commands/soleur/help.md` Step 2 to use Glob tool prose instructions instead of `find | wc` bash blocks
- [ ] 1.3 Verify help.md contains zero bash code blocks and zero shell expansion patterns

## Phase 2: Verification

- [ ] 2.1 Run `/soleur:help` and confirm no permission prompts appear
- [ ] 2.2 Verify component counts in help output match actual file counts
- [ ] 2.3 Grep `plugins/soleur/commands/soleur/help.md` for `$()`, `${`, `find`, `wc`, `cat` -- should return nothing

## Phase 3: Ship

- [ ] 3.1 Run code review on changes
- [ ] 3.2 Run compound to capture learnings
- [ ] 3.3 Version bump (PATCH: 3.0.5 -> 3.0.6) -- update plugin.json, CHANGELOG.md, README.md
- [ ] 3.4 Commit, push, create PR
- [ ] 3.5 Wait for CI, merge, cleanup worktree
