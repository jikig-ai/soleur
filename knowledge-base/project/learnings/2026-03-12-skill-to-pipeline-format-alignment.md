# Learning: Skill-to-pipeline format alignment requires verification against existing files

## Problem

When updating a skill to write output files that feed into an existing automated pipeline, the content file template did not match the format of existing files in the target directory. Specifically:

- IndieHackers sections in existing files used `**Title:**` and `**Body:**` labels; the new template omitted them
- Reddit sections used `**Body:**` labels; the template omitted it
- Existing files used `NN-<slug>.md` naming; the skill generated `<slug>.md` without detecting the mismatch
- The skill had no `--headless` bypass for interactive gates, blocking pipeline invocation

## Solution

1. Read at least one existing file in the target directory before writing the template -- compare section heading structure, label format, and naming conventions
2. Update overwrite detection to glob for `*<slug>.md` (catches both `slug.md` and `06-slug.md`)
3. Add `--headless` mode following the established pattern from ship/compound/work skills
4. Preserve existing filenames when a match is found (don't impose a new convention on existing files)

## Key Insight

When a skill writes files consumed by another system (cron pipeline, publisher script), verify the output contract against existing files in the target directory, not just the consumer's parsing logic. The consumer may parse correctly, but inconsistent file formats create confusion and duplicate-detection failures.

## Tags

category: integration-issues
module: social-distribute, content-publisher
