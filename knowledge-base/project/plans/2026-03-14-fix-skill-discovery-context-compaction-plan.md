---
title: "fix: skill discovery fails after context compaction"
type: fix
date: 2026-03-14
---

# fix: skill discovery fails after context compaction

## Enhancement Summary

**Deepened on:** 2026-03-14
**Sections enhanced:** 6
**Research sources:** Context7 Claude Code docs, 4 institutional learnings, shell script patterns, agent description budget precedent

### Key Improvements
1. Tightened budget ceiling from 2,000 to 1,800 words based on agent budget precedent (agents at 2,501/2,500 -- already at ceiling)
2. Added concrete trimming examples with before/after for the three worst offenders
3. Hardened verify-skills.sh with defensive patterns from institutional learnings (pipefail vectors, uniq -d empty array, local variables)
4. Added word budget test for agents alongside skills to prevent cross-budget drift

### New Considerations Discovered
- The agent description budget (2,501 words) is already at its 2,500 ceiling -- total metadata is ~5,230 words, not ~2,729
- The "Triggers on..." pattern accounts for ~30% of skill description word count across affected skills and can be removed wholesale
- Multi-line descriptions (YAML block scalars) may cause parsing issues with the sed-based extractor in verify-skills.sh
- The existing `components.test.ts` already has the test infrastructure needed -- add one test, not a new test file

## Overview

During implementation of #593, multiple `soleur:` skills failed to resolve via the Skill tool:
- `soleur:work` -- Unknown skill
- `soleur:compound` -- Unknown skill
- `soleur:ship` -- Unknown skill

Skills `soleur:brainstorm` and `soleur:plan` worked earlier in the same session. All 58 SKILL.md files exist on disk with correct frontmatter. This breaks the full slash command pipeline (`/soleur:go` -- brainstorm -- plan -- work -- compound -- ship`).

## Problem Statement / Motivation

The Soleur plugin has grown to 58 skills (2,729 description words / ~3.6k tokens) plus 40+ agents (2,501 description words / ~3.3k tokens). The Claude Code plugin loader injects **all** skill and agent name+description metadata into the system prompt on every turn. At ~7k tokens of metadata baseline, plus CLAUDE.md, AGENTS.md, constitution.md, and user context, sessions hit the context compaction threshold during multi-phase pipelines.

When compaction triggers, the skill metadata table can be silently truncated -- skills referenced earlier in the session remain accessible (cached in the model's compacted context), but skills not yet referenced become "Unknown." This explains why `brainstorm` and `plan` (invoked early) worked, while `work`, `compound`, and `ship` (invoked later) failed.

This is a systemic risk: as the plugin grows, compaction-induced skill loss will happen more frequently and earlier in sessions.

### Research Insights

**Precedent -- agent description budget optimization (2026-02-20):**
The identical class of problem was solved for agent descriptions: cumulative descriptions were ~15.8k tokens from verbose `<example>` blocks. Stripping examples and adding disambiguation sentences reduced to ~2.9k tokens (82% reduction). The same principle applies to skills: descriptions are for **routing**, not **instruction**. Trigger phrase lists are the skill equivalent of agent `<example>` blocks.

**Current budget state:**
- Agent descriptions: 2,501 words (at the 2,500 ceiling -- zero headroom)
- Skill descriptions: 2,729 words (no enforced ceiling)
- Combined metadata: ~5,230 words (~7k tokens) injected on every turn
- Adding the ~3k tokens from CLAUDE.md + AGENTS.md + constitution brings baseline to ~10k+ tokens before any user context

**Trigger phrase analysis:**
Of the 58 skills, 29 include `Triggers on "..."` phrases in their descriptions. These phrases average ~15 words each, totaling ~435 words. Removing them alone would reduce skill descriptions by 16% (2,729 to ~2,294 words) -- and the model does not need explicit trigger keywords because it infers intent from the skill name and core description.

## Proposed Solution

A two-pronged approach that reduces the description metadata baseline and adds a diagnostic mechanism for detection when skills go missing.

### Prong 1: Reduce cumulative skill description token budget

Trim all 58 skill descriptions to be concise while retaining routing accuracy. Target: reduce from ~2,729 words to under ~1,800 words (34% reduction).

**Strategy:**
- Remove trigger phrases from descriptions (e.g., `Triggers on "ready to ship", "create PR", "ship it"`) -- the model infers these from the skill name and core description
- Shorten verbose descriptions that restate what the skill name already communicates
- Keep descriptions in third person per convention ("This skill should be used when...")
- Preserve routing-critical keywords that distinguish similar skills

**Concrete trimming examples (top 3 offenders by word count):**

**gemini-imagegen (84 words to ~30 words):**
```yaml
# Before:
description: This skill should be used when generating and editing images using the Gemini API (Nano Banana Pro). It applies when creating images from text prompts, editing existing images, applying style transfers, generating logos with text, creating stickers, product mockups, or any image generation/manipulation task. Supports text-to-image, image editing, multi-turn refinement, and composition from multiple reference images. Triggers on "generate an image", "create a logo", "edit this image", "Gemini image", "text-to-image", "make a sticker", "product mockup photo".

# After:
description: "This skill should be used when generating or editing images using the Gemini API. Supports text-to-image, image editing, style transfer, logos, and multi-image composition."
```

**triage (79 words to ~30 words):**
```yaml
# Before:
description: "This skill should be used when triaging and categorizing findings for the CLI todo system. It presents code review findings, security audit results, or performance analysis items one by one for approval, skip, or customization, then creates structured todo files. Use ticket-triage agent for classifying user-reported GitHub issues by severity and domain. For automated daily triage via GitHub Actions, see scheduled-daily-triage.yml. Triggers on \"triage findings\", \"categorize issues\", \"review todos\", \"process audit results\", \"triage\"."

# After:
description: "This skill should be used when triaging and categorizing findings for the CLI todo system. Presents items one by one for approval, skip, or customization, then creates structured todo files."
```

**skill-creator (77 words to ~25 words):**
```yaml
# Before:
description: This skill should be used when creating, writing, refining, or auditing Claude Code Skills. It provides expert guidance on SKILL.md files, creating new skills from scratch, improving existing skills, packaging skills for distribution, and understanding skill structure and best practices. Triggers on "create a new skill", "build a skill", "package a skill", "init skill", "skill creation guide", "update this skill", "audit skill", "improve this skill", "skill best practices", "write a SKILL.md", "how to write skills".

# After:
description: "This skill should be used when creating, refining, or auditing Claude Code Skills and SKILL.md files."
```

### Prong 2: Add a skill-count validation diagnostic

Create a lightweight diagnostic that can be run to verify all skills are discoverable. This surfaces the problem immediately rather than failing silently mid-pipeline.

**Implementation:**
- Add a `verify-skills.sh` script in `plugins/soleur/scripts/` that:
  1. Counts SKILL.md files on disk
  2. Extracts `name:` from each frontmatter
  3. Validates no duplicates, no missing names, no descriptions > 1024 chars
  4. Reports cumulative word count
  5. Outputs a summary: `[ok] 58 skills verified, 0 issues`
- Integrate into `bun test` via `components.test.ts` -- add a test that validates cumulative description word count stays under a budget ceiling (1,800 words)

## Technical Considerations

### Why descriptions are the lever, not file structure

The Claude Code plugin loader uses a flat `skills/*/SKILL.md` scan pattern. The loader already works correctly (confirmed by test suite and file verification). The issue is not discovery on disk -- it is discovery in the model's context window after compaction.

The only metadata the loader injects per-turn is `name` + `description`. Reducing description size directly reduces the compaction pressure.

### Why not reduce skill count

Removing skills is higher cost than trimming descriptions. Each skill serves a purpose and removing them breaks existing workflows. Description trimming achieves the same token savings without functionality loss.

### Context compaction is a Claude Code platform behavior

This is not a bug the plugin can "fix" -- the loader injects metadata, and the platform compacts when context exceeds threshold. The fix is to ensure the metadata stays small enough that compaction pressure is minimized.

### Agent descriptions are a separate budget

Agent descriptions (2,501 words) are at their 2,500-word guideline ceiling. They contribute to total context but are not the primary issue for this PR. Skill descriptions (2,729 words) have no enforced budget today -- this PR establishes one.

### Research Insights

**Shell script defensive patterns (from learnings):**
- The `uniq -d` command for duplicate detection returns empty string when no duplicates exist, which is fine with `[ -n "$dupes" ]`
- All variables in loop bodies must be declared with `local` -- but since verify-skills.sh uses a flat loop (not functions), this manifests as declaring loop variables at script scope (acceptable for scripts)
- The `wc` variable name in the MVP shadows the `wc` command -- rename to `word_count` to avoid confusion
- The sed-based frontmatter extractor handles single-line `description:` values correctly but may fail on multi-line YAML block scalars; the existing components.test.ts uses a proper YAML parser and is the source of truth

**Budget ceiling rationale:**
The agent budget ceiling is 2,500 words (currently at 2,501). The prior learning on context compaction optimization reduced command bodies from 13,292 to 9,794 words (26% reduction). Applying a similar proportional ceiling to skills: 2,729 * 0.66 = 1,801 -- rounded to 1,800 words. This provides ~33% headroom below the current count and aligns with the agent budget pattern.

## Acceptance Criteria

- [x] All 58 skill descriptions trimmed to reduce cumulative word count by 25-35% (target: under 1,800 words)
- [x] No skill description exceeds 1024 characters
- [x] All descriptions retain third-person voice ("This skill should be used when...")
- [x] All descriptions retain routing-critical keywords for accurate skill matching
- [x] `components.test.ts` includes a cumulative description word budget test (ceiling: 1,800 words)
- [x] `verify-skills.sh` script created and validates all skills on disk
- [x] `bun test` passes with no regressions

## Test Scenarios

- Given a fresh session with 58 skills loaded, when all skill descriptions are under the 1,800-word budget, then the cumulative metadata fits within the compaction-safe threshold
- Given a skill with a description over 1024 characters, when the validation script runs, then it flags the violation
- Given duplicate skill names across different directories, when `verify-skills.sh` runs, then it detects and reports the conflict
- Given a multi-phase pipeline (brainstorm -- plan -- work -- compound -- ship), when invoked in a single session with reduced descriptions, then no "Unknown skill" errors occur
- Given the cumulative description word count exceeds 1,800 words, when `bun test` runs, then the budget test fails with a clear message
- Given a newly added skill with a 50-word description, when `bun test` runs, then the budget test enforces that the new description fits within the remaining headroom

## Success Metrics

- Cumulative skill description word count reduced from 2,729 to under 1,800 (34% reduction)
- Zero "Unknown skill" errors in full pipeline runs
- Test suite validates budget automatically on every commit

## Dependencies & Risks

- **Risk:** Over-trimming descriptions may reduce routing accuracy (model fails to match user intent to the right skill). **Mitigation:** Preserve core routing keywords; the model relies on skill name + description together, so a concise description paired with a descriptive name (e.g., `gemini-imagegen`) is sufficient.
- **Risk:** Description budget ceiling may need adjustment as new skills are added. **Mitigation:** The test makes the constraint visible and forces conscious decisions when adding skills. When the ceiling is reached, the adding developer must either trim existing descriptions or justify raising the ceiling.
- **Risk:** Multi-line YAML descriptions in verify-skills.sh may parse incorrectly with sed. **Mitigation:** The shell script is a supplementary diagnostic; the TypeScript test suite (components.test.ts) uses a proper YAML parser and is the authoritative validator.
- **Dependency:** Context compaction behavior is a Claude Code platform feature outside plugin control. The fix reduces pressure but cannot guarantee zero compaction.

## References & Research

### Internal References

- Prior learning: `knowledge-base/project/learnings/performance-issues/2026-02-20-agent-description-token-budget-optimization.md` -- identical pattern: agent descriptions trimmed from ~15.8k to ~2.9k tokens by removing `<example>` blocks
- Prior learning: `knowledge-base/project/learnings/2026-03-06-disambiguation-budget-compounds-with-domain-size.md` -- agent budget at ceiling (2,501/2,500), demonstrates word-level budget management
- Prior learning: `knowledge-base/project/learnings/2026-02-22-context-compaction-command-optimization.md` -- commands reduced from 13,292 to 9,794 words (26%)
- Prior learning: `knowledge-base/project/learnings/2026-02-25-plugin-command-double-namespace.md` -- plugin loader namespace behavior
- Prior learning: `knowledge-base/project/learnings/2026-03-13-shell-script-defensive-patterns.md` -- defensive shell patterns for verify-skills.sh
- Prior learning: `knowledge-base/project/learnings/2026-03-13-bash-arithmetic-and-test-sourcing-patterns.md` -- bash arithmetic pitfalls
- Test infrastructure: `plugins/soleur/test/components.test.ts` and `plugins/soleur/test/helpers.ts`
- Official spec reference: `plugins/soleur/skills/skill-creator/references/official-spec.md`
- Constitution: `knowledge-base/project/constitution.md` -- "Heavy, conditionally-used content in command/skill bodies must be extracted to reference files"

### External References

- Claude Code plugin skill discovery: auto-discovers from `skills/*/SKILL.md`, loads name+description at startup (confirmed via Context7 docs)
- Claude Code skill spec: description max 1024 characters, name max 64 characters
- Claude Code plugin-dev docs: skills do not require registration -- auto-discovery scans `skills/` subdirectories for SKILL.md files
- GitHub issue: #618

## MVP

### `plugins/soleur/scripts/verify-skills.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

# --- Skill Verification ---
# Validates all SKILL.md files: name match, description length, duplicates, word count.
# Run from any directory -- resolves plugin root from script location.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="$PLUGIN_ROOT/skills"

errors=0
skill_count=0
total_words=0
names=()

for skill_dir in "$SKILLS_DIR"/*/; do
  skill_file="$skill_dir/SKILL.md"
  [[ -f "$skill_file" ]] || continue
  skill_count=$((skill_count + 1))
  dir_name=$(basename "$skill_dir")

  # Extract name from frontmatter
  name=$(sed -n '/^---$/,/^---$/{ /^---$/d; p }' "$skill_file" | grep '^name:' | head -1 | sed 's/^name: *//' | tr -d '"')
  if [[ -z "$name" ]]; then
    echo "[error] $dir_name: missing name in frontmatter" >&2
    errors=$((errors + 1))
    continue
  fi

  # Check name matches directory
  if [[ "$name" != "$dir_name" ]]; then
    echo "[error] $dir_name: name '$name' does not match directory" >&2
    errors=$((errors + 1))
  fi

  # Extract description
  desc=$(sed -n '/^---$/,/^---$/{ /^---$/d; p }' "$skill_file" | grep '^description:' | head -1 | sed 's/^description: *//' | tr -d '"')
  desc_len=${#desc}
  if [[ "$desc_len" -gt 1024 ]]; then
    echo "[error] $dir_name: description exceeds 1024 chars ($desc_len)" >&2
    errors=$((errors + 1))
  fi

  # Word count
  word_count=$(echo "$desc" | wc -w | tr -d ' ')
  total_words=$((total_words + word_count))

  names+=("$name")
done

# Check duplicates (uniq -d returns empty if no dupes -- safe with -n test)
dupes=$(printf '%s\n' "${names[@]}" | sort | uniq -d || true)
if [[ -n "$dupes" ]]; then
  echo "[error] duplicate skill names: $dupes" >&2
  errors=$((errors + 1))
fi

echo "[info] $skill_count skills, $total_words description words, $errors errors"
if [[ "$errors" -gt 0 ]]; then
  exit 1
fi
echo "[ok] all skills verified"
```

### `plugins/soleur/test/components.test.ts` (addition)

```typescript
// Add to existing "Skill frontmatter" describe block:

test("cumulative description word count under budget", () => {
  const skills = discoverSkills();
  let totalWords = 0;
  for (const skillPath of skills) {
    const { frontmatter } = parseComponent(skillPath);
    const desc = String(frontmatter.description || "");
    totalWords += desc.split(/\s+/).filter(Boolean).length;
  }
  // Budget ceiling: 1800 words across all skill descriptions
  // Rationale: 58 skills at ~31 words avg; prevents context compaction from
  // dropping skills mid-session (see #618)
  expect(totalWords).toBeLessThanOrEqual(1800);
});
```
