# Tasks: rename knowledge-base/overview/ to knowledge-base/project/

## Phase 1: Directory Rename

- [ ] 1.1 Stage any untracked files in `knowledge-base/overview/` with `git add`
- [ ] 1.2 Run `git mv knowledge-base/overview/ knowledge-base/project/`
- [ ] 1.3 Verify `knowledge-base/project/` contains constitution.md, README.md, components/

## Phase 2: Update Plugin References

- [ ] 2.1 Update `AGENTS.md` line 3: `knowledge-base/overview/constitution.md` -> `knowledge-base/project/constitution.md`
- [ ] 2.2 Update `plugins/soleur/skills/work/SKILL.md`: 1 reference
- [ ] 2.3 Update `plugins/soleur/skills/compound/SKILL.md`: 4 references
- [ ] 2.4 Update `plugins/soleur/skills/compound-capture/SKILL.md`: 4 references
- [ ] 2.5 Update `plugins/soleur/skills/plan/SKILL.md`: 1 reference
- [ ] 2.6 Update `plugins/soleur/skills/spec-templates/SKILL.md`: 2 references
- [ ] 2.7 Update `plugins/soleur/commands/sync.md`: 7 references

## Phase 3: Update Self-References

- [ ] 3.1 Update `knowledge-base/project/constitution.md` lines 146-147: relative `overview/` -> `project/`
- [ ] 3.2 Update `knowledge-base/project/components/knowledge-base.md` lines 170, 184

## Phase 4: Verification

- [ ] 4.1 Verify `knowledge-base/overview/` no longer exists
- [ ] 4.2 Run `grep -r 'knowledge-base/overview/' plugins/ scripts/ .github/ AGENTS.md` -- expect zero matches
- [ ] 4.3 Verify constitution.md self-references use `project/`
- [ ] 4.4 Run compound before committing
