# Tasks: Apply Compound Route-to-Definition Proposals (Batch 2)

## Phase 1: Apply Edits

- [ ] 1.1 Edit `plugins/soleur/skills/work/SKILL.md` -- add `vi.hoisted()` bullet after line 241 (existing `vi.mock()` bullet in TDD Gate section)
- [ ] 1.2 Edit `plugins/soleur/skills/work/SKILL.md` -- add `replace_all` grep verification bullet in Common Pitfalls to Avoid section
- [ ] 1.3 Edit `plugins/soleur/skills/ship/SKILL.md` -- add terraform resource enumeration instruction after line 684 in Phase 7 Step 3.5
- [ ] 1.4 Edit `plugins/soleur/skills/one-shot/SKILL.md` -- expand subagent return contract at line 62 with CRITICAL format compliance instruction

## Phase 2: Update Learning Frontmatter

- [ ] 2.1 Update `knowledge-base/project/learnings/test-failures/2026-04-06-vitest-mock-hoisting-requires-vi-hoisted.md` -- add `synced_to: [work]` after `tags` field
- [ ] 2.2 Update `knowledge-base/project/learnings/security-issues/canary-crash-leaks-env-file-ci-deploy-20260406.md` -- add `synced_to: [work]` after `tags` field
- [ ] 2.3 Update `knowledge-base/project/learnings/2026-04-06-terraform-data-connection-block-no-auto-replace.md` -- change `synced_to: []` to `synced_to: [ship]`
- [ ] 2.4 Update `knowledge-base/project/learnings/2026-04-06-doppler-cli-checksum-cloud-init.md` -- add `synced_to: [one-shot]` after `tags` field

## Phase 3: Close Stale Issue

- [ ] 3.1 Close #1597 with comment explaining the fix is already present in one-shot/SKILL.md

## Phase 4: Verify

- [ ] 4.1 Run `npx markdownlint-cli2` on all three modified SKILL.md files -- exit code must be 0
- [ ] 4.2 Grep each target file for key phrases to confirm edits are present
