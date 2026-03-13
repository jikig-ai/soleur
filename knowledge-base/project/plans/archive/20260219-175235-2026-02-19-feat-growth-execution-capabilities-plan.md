---
title: "feat: Add execution capabilities to growth-strategist (fix + content writer)"
type: feat
date: 2026-02-19
---

# Add Execution Capabilities to Growth-Strategist

## Overview

Close the gap between growth-strategist analysis and applied changes by adding two execution capabilities: a `growth fix` sub-command that applies audit findings to existing pages, and a standalone `content-writer` skill that generates full article drafts with brand-consistent voice.

## Problem Statement

The growth-strategist agent (v2.16.0) produces high-quality analysis but stops at recommendations. Live testing on soleur.ai (PR #152) showed 10 audit issues, 9 rewrite suggestions, a 14-article content plan, and an AEO score of 1.6/10 -- all requiring manual execution of every recommendation.

## Proposed Solution

Two components following established patterns:

1. **`growth fix` sub-command** -- Follows the `seo-aeo fix` pattern. Same agent, mode-switched via Task prompt. Self-contained audit + fix in one pass.
2. **`content-writer` skill** -- Follows the `discord-content` brand pipeline pattern. Independent skill, not coupled to growth-strategist output.

## Technical Approach

No new agents. Growth-strategist gets a "Step: Execute" section (like seo-aeo-analyst Step 4). Content-writer is a skill that generates content directly (no agent delegation needed). Both components wrap Claude's native capabilities with enforced prerequisites, validation, and approval gates that ad-hoc prompts skip.

### Implementation Phases

#### Phase 1: Growth-Strategist Agent -- Add Execution Step

**File:** `plugins/soleur/agents/marketing/growth-strategist.md`

Add a new section after the existing capabilities:

```markdown
## Execution (when requested)

When asked to fix issues rather than just report:

1. Read the current state of each file that needs changes
2. For each audit finding, apply the fix using the Edit tool:
   - Keyword injection: add target keywords to headings and body where natural
   - FAQ sections: generate and insert FAQ blocks for pages with AEO gaps
   - Definition paragraphs: add clear, quotable definitions near first usage of key terms
   - Meta description rewrites: update frontmatter description for keyword alignment
3. If brand guide exists, validate each rewrite against the Voice section before applying
4. Build the site (e.g., `npx @11ty/eleventy`) to verify changes compile
5. Report what was changed per file: which fixes were applied, what text was modified

Important:
- Only modify existing page content. Do not create new pages.
- Local file paths only. If given a URL, report: "growth fix works on local files only. Use a local path."
- Apply fixes incrementally. If one edit fails, continue with remaining fixes and report the failure.
- Do not over-optimize. Keyword injection must read naturally. Avoid repetition within 200 words.
```

**Effort:** Small. Add ~30 lines to existing agent file.

#### Phase 2: Growth Skill -- Add `fix` Sub-command

**File:** `plugins/soleur/skills/growth/SKILL.md`

Changes:
1. Add `growth fix` row to sub-commands table
2. Add `## Sub-command: fix` section following the existing pattern
3. Update Important Guidelines to remove "no files written" constraint (line 119)

New sub-command section:

```markdown
## Sub-command: fix

Audit existing content and apply fixes to source files. Combines analysis and execution in one pass.

### Steps

1. Parse the argument as a local file or directory path. URLs are not supported for fix -- display: "growth fix works on local files only. For URL analysis, use `growth audit`."

2. Check for brand guide:
   ```bash
   if [[ -f "knowledge-base/overview/brand-guide.md" ]]; then
     echo "Brand guide found. Will validate rewrites against brand voice."
   fi
   ```

3. Launch the growth-strategist agent via the Task tool:
   ```
   Task growth-strategist: "Audit the content at <path> for keyword alignment,
   search intent match, readability, and AEO gaps. For each issue found, apply
   a fix to the source files. Read each file before editing.
   <if brand guide exists: Read knowledge-base/overview/brand-guide.md and
   validate all rewrites against the brand voice before applying.>
   After all fixes, build the site to verify changes compile.
   Report what was changed per file."
   ```

4. Present the agent's report showing changes made.
5. If build failed, show the error and suggest: "Run `git checkout -- <file>` to revert changes, or fix the build error manually."
```

**Effort:** Medium. ~40 lines of new content, update existing guidelines.

#### Phase 3: Content-Writer Skill (New)

**File:** `plugins/soleur/skills/content-writer/SKILL.md`

New standalone skill. Follows the discord-content brand pipeline pattern.

```yaml
---
name: content-writer
description: "This skill should be used when generating full article drafts with
  brand-consistent voice, Eleventy frontmatter, and structured data. It requires
  a brand guide and existing blog infrastructure. Triggers on 'write article',
  'content writer', 'draft blog post', 'generate article', 'write content'."
---
```

**Phases:**

Phase 0: Prerequisites
- Check brand guide exists at `knowledge-base/overview/brand-guide.md`. Hard fail if missing.
- Check blog infrastructure exists (Eleventy config file). If missing, display: "No Eleventy config found. Run the docs-site skill to scaffold blog infrastructure first."

Phase 1: Parse Input
- `<topic>` (required): article topic
- `--outline "..."`: article outline as inline text (Markdown list format)
- `--keywords "kw1, kw2, kw3"`: target keywords (comma-separated)
- `--path <output-path>`: where to write the file. Default: auto-generate from topic slug as `blog/posts/YYYY-MM-DD-<slug>.md`

Phase 2: Generate Draft
- Read brand guide `## Voice` section (tone, do's and don'ts)
- Read brand guide `## Channel Notes > ### Blog` section if it exists
- Generate full article with:
  - Eleventy frontmatter: title, date, description, tags, layout
  - Article body following outline or generated structure
  - JSON-LD Article structured data in frontmatter or template
  - FAQ section with FAQPage schema if topic warrants it (2+ natural questions)

Phase 3: User Approval
- Present draft with word count displayed
- Use AskUserQuestion with three options:
  - **Accept** -- Write article to disk
  - **Edit** -- Provide feedback to revise (return to Phase 2 with feedback)
  - **Reject** -- Discard and exit

Phase 4: Write to Disk
- On Accept, write to the output path
- Report: "Article written to `<path>`. Review and commit when ready."

**Important Guidelines:**
- All content requires explicit user approval before writing -- no auto-write
- Brand guide is a hard prerequisite. Without it, skill cannot generate brand-consistent content.
- Read brand guide Voice section during draft generation, not as a separate validation pass
- If outline is provided, follow it. If not, generate a reasonable article structure.
- Do not scaffold blog infrastructure. If missing, direct user to docs-site skill.
- JSON-LD should use schema.org/Article type (or BlogPosting for blog directory content)
- Frontmatter fields should match existing posts in the target directory when possible

**Effort:** Medium. ~100 lines. New file, follows established pattern.

#### Phase 4: Version Bump + Docs Registration

1. **`plugins/soleur/.claude-plugin/plugin.json`**: Bump 2.18.0 -> 2.19.0 (MINOR -- new skill). Update description count: 42 skills.
2. **`plugins/soleur/CHANGELOG.md`**: Add v2.19.0 entry with both changes.
3. **`plugins/soleur/README.md`**: Update skill count, add content-writer to skills table, note growth fix sub-command.
4. **`plugins/soleur/docs/_data/skills.js`**: Register `"content-writer": "Content & Release"` in SKILL_CATEGORIES.
5. **Root `README.md`**: Update version badge and skill count.
6. **`.github/ISSUE_TEMPLATE/bug_report.yml`**: Update version placeholder.

**Version bump intent:** MINOR (new skill added).

**Effort:** Small. Mechanical updates across 6 files.

## Acceptance Criteria

- [ ] `growth fix <path>` audits and applies keyword/copy/AEO fixes to existing pages
- [ ] Growth fix applies: keyword injection, FAQ sections, definition paragraphs, meta description rewrites
- [ ] Growth fix validates rewrites against brand guide when present
- [ ] Growth fix builds site after changes to verify compilation
- [ ] Growth fix reports all changes made per file
- [ ] `content-writer <topic>` generates a full article draft with Eleventy frontmatter and JSON-LD
- [ ] Content-writer reads brand guide Voice section during generation for tone consistency
- [ ] Content-writer presents draft for user approval before writing to disk
- [ ] Content-writer generates FAQ schema when topic warrants it
- [ ] Content-writer fails with clear message when brand guide is missing
- [ ] Content-writer directs to docs-site when blog infrastructure is missing

## Test Scenarios

- Given a local Markdown file with no target keywords, when `growth fix` is run, then keywords are injected into headings and body text naturally
- Given a page with no FAQ section, when `growth fix` is run, then a FAQ section is generated and inserted
- Given a brand guide exists, when `growth fix` applies rewrites, then each rewrite matches the brand voice
- Given applied fixes break the build, when build fails, then the error is reported with revert instructions
- Given a URL instead of local path, when `growth fix` is run, then an error message explains local paths only
- Given a brand guide exists, when `content-writer` is run with a topic, then a full article draft is generated matching the brand voice
- Given no brand guide exists, when `content-writer` is run, then execution stops with a message to create one
- Given no Eleventy config exists, when `content-writer` is run, then execution stops with a message to run docs-site
- Given user chooses Edit in content-writer, when feedback is provided, then the draft is regenerated incorporating feedback
- Given user chooses Reject in content-writer, then no file is written and skill exits

## Non-Goals

- No `growth validate` sub-command
- No parallel article generation
- No growth-plan-aware content writer
- No blog scaffolding in content-writer
- No dry-run mode for growth fix (use git to revert)
- No glob/batch support for growth fix (single path per invocation)

## Dependencies & Risks

- **Low risk:** Growth-strategist agent modification is additive (new section, existing capabilities unchanged)
- **Low risk:** Growth skill modification follows exact seo-aeo pattern
- **Medium risk:** Content-writer quality depends on brand guide completeness. If brand guide Voice section is thin, output quality suffers.
- **Dependency:** Brand guide must exist for content-writer. No brand guide = skill is unusable.

## References

- Issue: #153
- Growth strategist PR: #152
- Pattern: `plugins/soleur/skills/seo-aeo/SKILL.md` (audit/fix/validate flow)
- Pattern: `plugins/soleur/agents/marketing/seo-aeo-analyst.md` (Step 4: Fix when requested)
- Pattern: `plugins/soleur/skills/discord-content/SKILL.md` (brand pipeline + approval gate)
- Brainstorm: `knowledge-base/brainstorms/2026-02-19-growth-execution-brainstorm.md`
- Spec: `knowledge-base/specs/feat-growth-execution/spec.md`
