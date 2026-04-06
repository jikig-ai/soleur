# Tasks: Apply Compound Route-to-Definition Proposals (Batch 2)

## Phase 1: Apply Edits

- [x] 1.1 Edit `plugins/soleur/skills/work/SKILL.md` -- add `vi.hoisted()` bullet after line 241 (existing `vi.mock()` bullet in TDD Gate section)
- [x] 1.2 Edit `plugins/soleur/skills/work/SKILL.md` -- add `replace_all` grep verification bullet in Common Pitfalls to Avoid section
- [x] 1.3 Edit `plugins/soleur/skills/ship/SKILL.md` -- add terraform resource enumeration instruction after line 684 in Phase 7 Step 3.5
- [x] 1.4 Edit `plugins/soleur/skills/one-shot/SKILL.md` -- expand subagent return contract at line 62 with CRITICAL format compliance instruction
- [x] 1.5 Edit `AGENTS.md` -- add terraform + doppler name-transformer bullet to Code Quality section

## Phase 2: Update Learning Frontmatter

- [x] 2.1 Update `knowledge-base/project/learnings/test-failures/2026-04-06-vitest-mock-hoisting-requires-vi-hoisted.md` -- add `synced_to: [work]` after `tags` field
- [x] 2.2 Update `knowledge-base/project/learnings/security-issues/canary-crash-leaks-env-file-ci-deploy-20260406.md` -- add `synced_to: [work]` after `tags` field
- [x] 2.3 Update `knowledge-base/project/learnings/2026-04-06-terraform-data-connection-block-no-auto-replace.md` -- change `synced_to: []` to `synced_to: [ship]`
- [x] 2.4 Update `knowledge-base/project/learnings/2026-04-06-doppler-cli-checksum-cloud-init.md` -- add `synced_to: [one-shot]` after `tags` field
- [x] 2.5 ~~Update `knowledge-base/project/learnings/integration-issues/2026-04-06-doppler-stderr-contaminates-docker-env-file.md`~~ -- skipped, file does not exist yet

## Phase 3: Close Stale Issue

- [x] 3.1 Close #1597 with comment explaining the fix is already present in one-shot/SKILL.md

## Phase 4: Verify

- [x] 4.1 Run `npx markdownlint-cli2` on all four modified files -- exit code 0
- [x] 4.2 Grep each target file for key phrases to confirm edits are present
