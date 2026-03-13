# Tasks: rename knowledge-base/overview/ to knowledge-base/project/

## Phase 1: Directory Rename

- [ ] 1.1 Stage any untracked files in `knowledge-base/overview/` with `git add`
- [ ] 1.2 Run `git mv knowledge-base/overview/ knowledge-base/project/`
- [ ] 1.3 Verify `knowledge-base/project/` contains constitution.md, README.md, components/

## Phase 2: Update File Path References

- [ ] 2.1 Update `AGENTS.md` line 3: `knowledge-base/overview/constitution.md` -> `knowledge-base/project/constitution.md`
- [ ] 2.2 Update `plugins/soleur/skills/work/SKILL.md`: 1 path reference (line 49)
- [ ] 2.3 Update `plugins/soleur/skills/compound/SKILL.md`: 4 path references (lines 172, 226, 259, 261)
- [ ] 2.4 Update `plugins/soleur/skills/compound-capture/SKILL.md`: 4 path references (lines 377, 378, 379, 394)
- [ ] 2.5 Update `plugins/soleur/skills/plan/SKILL.md`: 1 path reference (line 45)
- [ ] 2.6 Update `plugins/soleur/skills/spec-templates/SKILL.md`: 2 path references (lines 99, 163)
- [ ] 2.7 Update `plugins/soleur/commands/sync.md`: 9 path references (lines 41, 131, 132, 160, 244, 391, 393, 395, 396)
  - [ ] 2.7.1 Line 41: `mkdir -p` brace expansion `overview/components` -> `project/components`

## Phase 2b: Update Sync Area Name and Prose References

- [ ] 2b.1 `plugins/soleur/commands/sync.md` line 4: argument-hint area list `overview` -> `project`
- [ ] 2b.2 `plugins/soleur/commands/sync.md` line 20: valid areas text `overview` -> `project`
- [ ] 2b.3 `plugins/soleur/commands/sync.md` line 326: area conditional `overview` -> `project`
- [ ] 2b.4 `plugins/soleur/commands/sync.md` line 441: example text update
- [ ] 2b.5 `plugins/soleur/commands/sync.md` line 444: `/sync overview` -> `/sync project`
- [ ] 2b.6 `plugins/soleur/skills/compound-capture/SKILL.md` line 383: "overview file" -> "project file"
- [ ] 2b.7 `plugins/soleur/skills/compound-capture/SKILL.md` line 450: "overview updates" -> "project updates"
- [ ] 2b.8 `plugins/soleur/skills/compound-capture/SKILL.md` line 455: "overview edits" -> "project edits"

## Phase 3: Update Self-References

- [ ] 3.1 Update `knowledge-base/project/constitution.md` lines 146-147: relative `overview/` -> `project/`
- [ ] 3.2 Update `knowledge-base/project/components/knowledge-base.md` lines 170, 184

## Phase 4: Verification

- [ ] 4.1 Verify `knowledge-base/overview/` no longer exists
- [ ] 4.2 Run `grep -r 'knowledge-base/overview/' plugins/ scripts/ .github/ AGENTS.md` -- expect zero matches
- [ ] 4.3 Verify sync area name updated (no bare `overview` as area name in sync.md)
- [ ] 4.4 Verify constitution.md self-references use `project/`
- [ ] 4.5 Verify compound-capture.md prose references use `project/`
- [ ] 4.6 Run compound before committing
