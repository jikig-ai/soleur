# Tasks: Non-Technical Founder Voice

**Issue:** #1004
**Plan:** [2026-03-29-feat-non-technical-founder-voice-plan.md](../../plans/2026-03-29-feat-non-technical-founder-voice-plan.md)

## Phase 1: Brand Guide Updates

- [x] 1.1 Add `### Audience Voice Profiles` subsection under `## Voice` with technical and general register definitions
- [x] 1.2 Add "Non-technical founders" row to Tone Spectrum table
- [x] 1.3 Add `**General thesis:**` after existing thesis in `### Positioning`
- [x] 1.4 Add `### Who Is Soleur For?` section under `## Identity`
- [x] 1.5 Add non-technical founder guidance bullet to Do's list

## Phase 2: Content-Writer Skill Update

- [x] 2.1 Add `--audience` to argument format string (SKILL.md line 14)
- [x] 2.2 Add parse entry for `--audience` in Phase 1
- [x] 2.3 Add audience-specific brand guide reading step in Phase 2

## Phase 3: Marketing Strategy ICP Rewrite

- [x] 3.1 Apply `[INVALIDATED]` annotation: replace Claude Code criterion
- [x] 3.2 Apply `[SOFTEN]` annotation: replace technical background criterion
- [x] 3.3 Update Beachhead Segment to align with rewritten ICP
- [x] 3.4 Update Channels to Reach Them table

## Phase 4: Validation

- [x] 4.1 Run `npx markdownlint-cli2 --fix` on all changed `.md` files
- [x] 4.2 Run `bun test plugins/soleur/test/components.test.ts` to verify skill description budget
- [x] 4.3 Review final diff for consistency across all three files
