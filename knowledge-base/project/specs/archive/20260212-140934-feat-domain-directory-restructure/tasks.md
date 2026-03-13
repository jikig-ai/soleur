# Tasks: Domain-First Directory Restructure

## Phase 0: Verify Plugin Loader

- [ ] 0.1 Move one agent into nested `engineering/` dir, verify Claude Code discovers it by name
- [ ] 0.2 Move one skill into nested `engineering/` dir, verify it loads correctly
- [ ] 0.3 If loader fails: abort plan, investigate flat alternatives

## Phase 1: Move Files (30 moves)

- [ ] 1.1 Move 14 remaining review agents to `agents/engineering/review/`
- [ ] 1.2 Move 1 design agent to `agents/engineering/design/`
- [ ] 1.3 Remove empty old directories (`agents/review/`, `agents/design/`)
- [ ] 1.4 Move 15 engineering skills to `skills/engineering/`

## Phase 2: Fix References

- [ ] 2.1 Update agent category references in review.md, deepen-plan SKILL.md (review/ → engineering/review/)
- [ ] 2.2 Update skill path references in deepen-plan SKILL.md (dhh-rails-style, frontend-design, etc.)
- [ ] 2.3 Update counting globs in deploy-docs, release-docs, help.md (recursive find)
- [ ] 2.4 Update AGENTS.md validation globs
- [ ] 2.5 Run comprehensive stale-path grep to catch anything missed

## Phase 3: Docs + Version + Verify

- [ ] 3.1 Update AGENTS.md directory structure + "Adding a new domain" section
- [ ] 3.2 Reorganize README.md tables by domain
- [ ] 3.3 Update constitution.md agent organization convention
- [ ] 3.4 Version bump: plugin.json, CHANGELOG, root README badge, bug report template
- [ ] 3.5 Run verification suite (file counts, stale paths, old dirs, relative paths)
