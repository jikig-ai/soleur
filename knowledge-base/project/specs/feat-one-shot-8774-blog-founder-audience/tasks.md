# Tasks: blog posts target non-technical founders (#8774)

Plan: `knowledge-base/project/plans/2026-09-25-chore-blog-posts-target-non-technical-founders-plan.md`

## Phase 1: Tests first (RED)

- [ ] 1.1 Write `plugins/soleur/test/blog-audience-contract.test.ts` from the Guard Contract.
  - [ ] 1.1.1 Guard 1: pure-function validators over a string, run on the real files and on inline synthesized fixtures. It checks four things:
    - exactly one `### Blog` heading in the guide;
    - that heading sits inside the `## Channel Notes` slice;
    - no `technical blog` in brand-guide.md or vision.md;
    - the content-writer `--audience` bullet names `## Channel Notes > ### Blog`.
  - [ ] 1.1.2 Guard 2: three fixtures for `blog-jargon-scan.sh`:
    - RED: exit 1, all three hit lines printed;
    - must-PASS: exit 0;
    - usage: exit 2.
  - [ ] 1.1.3 Every assertion message names the file and heading to edit.
- [ ] 1.2 Run `bun test plugins/soleur/test/blog-audience-contract.test.ts` and confirm it is RED for the expected reasons.

## Phase 2: Brand guide and sibling documents

- [ ] 2.1 brand-guide.md, A1: move the blog to the Non-technical founders row, and add the one-line routing sentence under the table.
- [ ] 2.2 brand-guide.md, A2: in the register lines, take the blog out of the Technical register and add it to the General register.
- [ ] 2.3 brand-guide.md, A3: append `### Blog` after `### Website / Landing Page`.
  - Put the pinning HTML comment directly above the heading.
  - Copy the target text verbatim from the plan.
- [ ] 2.4 brand-guide.md, A4: set `last_updated: 2026-09-25`.
- [ ] 2.5 vision.md: update the two channel lines and bump `last_updated` if the key is present.
- [ ] 2.6 content-strategy.md: add one dated Pillar 2 line and bump `last_updated`.

## Phase 3: content-writer, scan script, ship sentence

- [ ] 3.1 content-writer SKILL.md, B1: the `--audience` default resolves through the Blog note, falling back to `technical` only when there is no note.
- [ ] 3.2 content-writer SKILL.md, B2: Phase 2 step 2 applies every rule in the note. Step 4 resolves the register, then always reads the Audience Voice Profiles.
- [ ] 3.3 content-writer SKILL.md, B3: add `## Phase 2.4: Blog Note Scan`.
  - It runs only when the note contains the literal `**Jargon limits.**` label.
  - The draft goes to a `mktemp` file.
  - The script is called with the `${CLAUDE_PLUGIN_ROOT:-plugins/soleur}` fallback and linked as a markdown link.
  - Exit 1 gets 2 fix cycles; any other non-zero exit is warned and reported.
- [ ] 3.4 content-writer SKILL.md, B4: add the Important Guidelines line for the no-note behavior.
- [ ] 3.5 Create `plugins/soleur/skills/content-writer/scripts/blog-jargon-scan.sh` (C). It has no `soleur:` pattern, and it is added with `git add --chmod=+x`.
- [ ] 3.6 ship SKILL.md, D: append the roughly 70-byte pointer sentence inside the CMO prompt. Anchor on `Assess content and distribution opportunities from this PR`.
- [ ] 3.7 Run `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base origin/main HEAD)"`.
- [ ] 3.8 The new test is GREEN. Drive each Guard Contract mutation row RED once locally.

## Phase 4: #8548 handoff

- [ ] 4.1 Idempotency check: count comments on #8548 that carry `8774-handoff`. If there is one, skip posting.
- [ ] 4.2 Write the body to a `mktemp` file and post it with `gh issue comment 8548 --body-file "$F"`. The body is the marker plus about three sentences:
  - the guide landed;
  - the recommendation, re-angle on "I lose track of what I decided and what I just forgot";
  - a link to the plan's handoff notes.

## Phase 5: Verify

- [ ] 5.1 Run AC1–AC11 commands from the plan.
- [ ] 5.2 Run `bun test plugins/soleur/` in full, plus the Release Digest lockstep test.
- [ ] 5.3 Before creating the PR, the PR body must carry:
  - `Closes #8774` and `Ref #8548`, never `Closes #8548`;
  - the expected CMO Website Framing no-op;
  - a `## Changelog` section and a `semver:patch` label.
