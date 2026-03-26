# Learning: Scheduled Content Generation — Soleur vs. Polsia

## Problem

Automated content generation pipeline (content-writer + social-distribute + build/validate) was executed for the "Soleur vs. Polsia" comparison article from the SEO refresh queue. Several friction points arose during execution that are worth capturing for future content generation runs.

## Solution

Content successfully generated, built, validated, and queued for PR:
- Article: `plugins/soleur/docs/blog/2026-03-26-soleur-vs-polsia.md`
- Distribution: `knowledge-base/marketing/distribution-content/soleur-vs-polsia.md`
- SEO queue updated with `generated_date: 2026-03-26`
- Audit issue: jikig-ai/soleur#1167

## Key Insight

Skills invocable via Claude Code's `Skill` tool in normal sessions are **not available** in automated/scheduled agent contexts. The Skill tool only surfaces skills registered in the Claude Code harness at session start — not all skills present on disk. In scheduled pipeline runs, the agent must read `SKILL.md` files and execute them step-by-step manually.

## Session Errors

1. **`soleur:content-writer` Skill tool invocation failed** — "Unknown skill: soleur:content-writer". The skill exists at `plugins/soleur/skills/content-writer/SKILL.md` but is not registered in the harness for this session context.
   - Recovery: Read `SKILL.md` manually and executed each phase directly.
   - Prevention: Scheduled content-generator agent prompt should explicitly say "read `plugins/soleur/skills/content-writer/SKILL.md` and execute the phases directly" rather than invoking via `Skill` tool.

2. **`soleur:compound` Skill tool invocation failed** — same cause as above.
   - Recovery: Read `SKILL.md` manually and executed compound phases inline.
   - Prevention: Same as above — pipeline prompts should use manual skill execution, not Skill tool invocation.

3. **Eleventy build failed: quoted YAML date** — `date: "2026-03-26"` (quoted string) caused `dateToRfc3339` TypeError because Eleventy's RSS plugin expects a Date object, not a string.
   - Recovery: Removed quotes from date field: `date: 2026-03-26`.
   - Prevention: content-writer skill should note that `date:` in frontmatter must be unquoted for Eleventy date filters to work. Add to `## Important Guidelines` section.

4. **`git worktree add` via worktree-manager.sh failed** — the script references `main` branch but the repo uses `master`.
   - Recovery: Used `git worktree add .worktrees/... -b feat/...` directly.
   - Prevention: `worktree-manager.sh` should detect default branch dynamically (`git symbolic-ref refs/remotes/origin/HEAD`) rather than hardcoding `main`.

5. **`gh` CLI not available** — milestone lookup and issue creation via `gh` CLI failed.
   - Recovery: Used `mcp__github__issue_write` MCP tool for issue creation. Milestone omitted (MCP tool constraint — no milestone listing tool available).
   - Prevention: Pipeline design should default to MCP tools for GitHub operations, not `gh` CLI.

## Tags

category: content-generation
module: content-writer, social-distribute, seo-queue
