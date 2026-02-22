---
title: Update Outdated Model IDs - Tasks
feature: feat-update-model-ids
date: 2026-02-22
---

# Tasks

## Phase 1: Agent-Native Architecture References

- [ ] 1.1 Update `agent-execution-patterns.md` (2 changes: line 231 comment, line 237 code)
- [ ] 1.2 Update `mobile-patterns.md` (6 changes: 3 comments + pricing, 3 return values)
- [ ] 1.3 Update `agent-native-testing.md` (2 changes: lines 487, 518)
- [ ] 1.4 Update `architecture-patterns.md` (3 changes: comment-only tier names)

## Phase 2: DSPy Ruby References

- [ ] 2.1 Update `SKILL.md` (3 changes: code example + prose references)
- [ ] 2.2 Update `references/providers.md` (9 changes: code examples + prose)
- [ ] 2.3 Update `assets/config-template.rb` (6 changes: all LM.new calls + comment)
- [ ] 2.4 Update `assets/module-template.rb` (1 change: model ID)

## Phase 3: Verification

- [ ] 3.1 Run grep verification: zero `claude-3` references remain in `plugins/soleur/skills/`
- [ ] 3.2 Run grep verification: correct 4.x IDs are present
- [ ] 3.3 Version bump (patch) for plugin.json, CHANGELOG.md, README.md
