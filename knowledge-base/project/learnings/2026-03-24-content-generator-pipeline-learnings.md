# Learning: Content Generator Pipeline — Skill Invocation and Blog Date Formats

## Problem

The automated content generator pipeline invoked `soleur:content-writer`, `soleur:social-distribute`, and `soleur:compound` via the `Skill tool`, receiving `Unknown skill` errors for all three. Additionally, the Eleventy build failed on the first attempt due to a quoted date string in blog post frontmatter.

## Solution

1. **Skill invocation:** Read the SKILL.md file at `plugins/soleur/skills/<skill-name>/SKILL.md` and execute the instructions directly. The `Skill tool` only resolves skills registered with the Claude Code harness — plugin skills defined as markdown instruction files must be executed inline.
2. **Blog date format:** Use unquoted YAML date literals in frontmatter: `date: 2026-03-24`, not `date: "2026-03-24"`. Eleventy's `dateToRfc3339` filter requires a JavaScript Date object, which YAML produces for unquoted ISO dates but not for quoted strings.
3. **Worktree from bare repo:** After creating a worktree with `git worktree add`, run `git fetch origin main && git merge origin/main` to ensure the worktree is at the latest commit. The local `master` branch may be stale if only `origin/main` has been updated.

## Key Insight

Plugin skills (SKILL.md files) are instruction documents for the agent, not registered CLI commands. The Skill tool only works for skills registered in the harness (like built-in Soleur skills). For plugin-level skills, the agent must read the file and follow it directly.

## Session Errors

1. **`Unknown skill: soleur:content-writer`** — Recovery: Read SKILL.md directly and followed instructions. Prevention: In automated pipelines, never invoke plugin skills via `Skill tool`; read and execute SKILL.md inline.
2. **`Unknown skill: soleur:social-distribute`** — Same as above.
3. **`Unknown skill: soleur:compound`** — Same as above.
4. **Eleventy build failure: `dateObj.toISOString is not a function`** — Recovery: Removed quotes from `date` frontmatter field. Prevention: Blog post frontmatter must use unquoted YAML date literals for `date` fields.
5. **Worktree at stale commit** — Recovery: `git fetch origin main && git merge origin/main`. Prevention: After creating worktree from bare repo, always fetch and merge origin/main before writing files.

## Tags

category: pipeline
module: content-generator, skills, eleventy
