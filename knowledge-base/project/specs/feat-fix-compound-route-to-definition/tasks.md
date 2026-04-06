# Tasks: fix apply compound route-to-definition proposals

## Phase 1: Apply Edits to work/SKILL.md

- [ ] 1.1 Read `plugins/soleur/skills/work/SKILL.md` and locate the Infrastructure Validation section (step 6)
- [ ] 1.2 Grep for key phrases ("seccomp", "includes.caps", "triggers_replace") to verify no duplicate content exists
- [ ] 1.3 Add bwrap/seccomp bullet (#1572) after the existing cloud-init/lifecycle bullet (line 321)
  - [ ] 1.3.1 Match existing 3-space indentation under the numbered list item
- [ ] 1.4 Add Terraform triggers_replace bullet (#1564) after the bwrap/seccomp bullet
  - [ ] 1.4.1 Match existing 3-space indentation under the numbered list item

## Phase 2: Apply Edit to one-shot/SKILL.md

- [ ] 2.1 Read `plugins/soleur/skills/one-shot/SKILL.md` and locate Step 0c
- [ ] 2.2 Grep for "No commits between" to verify no duplicate content exists
- [ ] 2.3 Expand the failure handling text on line 28 to cover "No commits between branches" error

## Phase 3: Update synced_to Frontmatter

- [ ] 3.1 Read `knowledge-base/project/learnings/security-issues/bwrap-sandbox-three-layer-docker-fix-20260405.md` frontmatter
- [ ] 3.2 Add or update `synced_to` field to include `work`
- [ ] 3.3 Read `knowledge-base/project/learnings/integration-issues/stale-env-deploy-pipeline-terraform-bridge-20260405.md` frontmatter
- [ ] 3.4 Add or update `synced_to` field to include `work`
- [ ] 3.5 Read `knowledge-base/project/learnings/2026-04-05-graceful-sigterm-shutdown-node-patterns.md` frontmatter
- [ ] 3.6 Add or update `synced_to` field to include `one-shot`

## Phase 4: Validation

- [ ] 4.1 Run `npx markdownlint-cli2 --fix` on both modified SKILL.md files
- [ ] 4.2 Re-read work/SKILL.md to verify both new bullets exist in correct position with correct indentation
- [ ] 4.3 Re-read one-shot/SKILL.md to verify Step 0c failure text covers the new error case
- [ ] 4.4 Verify all three learning files have updated `synced_to` frontmatter
