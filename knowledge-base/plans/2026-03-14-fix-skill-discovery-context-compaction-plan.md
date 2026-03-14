---
title: "fix: skill discovery fails after context compaction"
type: fix
date: 2026-03-14
---

# fix: skill discovery fails after context compaction

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

## Proposed Solution

A two-pronged approach that reduces the description metadata baseline and adds a diagnostic mechanism for detection when skills go missing.

### Prong 1: Reduce cumulative skill description token budget

Trim all 58 skill descriptions to be concise while retaining routing accuracy. The official spec allows up to 1024 characters per description, but shorter descriptions are better for the system prompt budget. Target: reduce from ~2,729 words to under ~1,800 words (34% reduction).

**Strategy:**
- Remove trigger phrases from descriptions (e.g., `Triggers on "ready to ship", "create PR", "ship it"`) -- the model infers these from the skill name and core description
- Shorten verbose descriptions that restate what the skill name already communicates
- Keep descriptions in third person per convention ("This skill should be used when...")
- Preserve routing-critical keywords that distinguish similar skills

### Prong 2: Add a skill-count validation diagnostic

Create a lightweight diagnostic that can be run to verify all skills are discoverable. This surfaces the problem immediately rather than failing silently mid-pipeline.

**Implementation:**
- Add a `verify-skills.sh` script in `plugins/soleur/scripts/` that:
  1. Counts SKILL.md files on disk
  2. Extracts `name:` from each frontmatter
  3. Validates no duplicates, no missing names, no descriptions > 1024 chars
  4. Outputs a summary: `[ok] 58 skills verified, 0 issues`
- Integrate into `bun test` via `components.test.ts` -- add a test that validates cumulative description word count stays under a budget ceiling (e.g., 2,000 words)

## Technical Considerations

### Why descriptions are the lever, not file structure

The Claude Code plugin loader uses a flat `skills/*/SKILL.md` scan pattern. The loader already works correctly (confirmed by test suite and file verification). The issue is not discovery on disk -- it is discovery in the model's context window after compaction.

The only metadata the loader injects per-turn is `name` + `description`. Reducing description size directly reduces the compaction pressure.

### Why not reduce skill count

Removing skills is higher cost than trimming descriptions. Each skill serves a purpose and removing them breaks existing workflows. Description trimming achieves the same token savings without functionality loss.

### Context compaction is a Claude Code platform behavior

This is not a bug the plugin can "fix" -- the loader injects metadata, and the platform compacts when context exceeds threshold. The fix is to ensure the metadata stays small enough that compaction pressure is minimized.

### Agent descriptions are a separate budget

Agent descriptions (2,501 words) are under their 2,500-word guideline. They contribute to total context but are not the primary issue. Skill descriptions (2,729 words) have no enforced budget today.

## Acceptance Criteria

- [ ] All 58 skill descriptions trimmed to reduce cumulative word count by 25-35% (target: under 2,000 words)
- [ ] No skill description exceeds 1024 characters
- [ ] All descriptions retain third-person voice ("This skill should be used when...")
- [ ] All descriptions retain routing-critical keywords for accurate skill matching
- [ ] `components.test.ts` includes a cumulative description word budget test (ceiling: 2,000 words)
- [ ] `verify-skills.sh` script created and validates all skills on disk
- [ ] Full pipeline test: invoke `brainstorm` then `plan` then `work` then `compound` then `ship` in sequence without "Unknown skill" errors
- [ ] `bun test` passes with no regressions

## Test Scenarios

- Given a fresh session with 58 skills loaded, when all skill descriptions are under the 2,000-word budget, then the cumulative metadata fits within the compaction-safe threshold
- Given a skill with a description over 1024 characters, when the validation script runs, then it flags the violation
- Given duplicate skill names across different directories, when `verify-skills.sh` runs, then it detects and reports the conflict
- Given a multi-phase pipeline (brainstorm -- plan -- work -- compound -- ship), when invoked in a single session with reduced descriptions, then no "Unknown skill" errors occur
- Given the cumulative description word count exceeds 2,000 words, when `bun test` runs, then the budget test fails with a clear message

## Success Metrics

- Cumulative skill description word count reduced from 2,729 to under 2,000 (25-35% reduction)
- Zero "Unknown skill" errors in full pipeline runs
- Test suite validates budget automatically on every commit

## Dependencies & Risks

- **Risk:** Over-trimming descriptions may reduce routing accuracy (model fails to match user intent to the right skill). **Mitigation:** Preserve core routing keywords; test that skill invocations still resolve correctly.
- **Risk:** Description budget ceiling may need adjustment as new skills are added. **Mitigation:** The test makes the constraint visible and forces conscious decisions when adding skills.
- **Dependency:** Context compaction behavior is a Claude Code platform feature outside plugin control. The fix reduces pressure but cannot guarantee zero compaction.

## References & Research

### Internal References

- Prior learning: `knowledge-base/project/learnings/2026-02-22-context-compaction-command-optimization.md` -- documents the same class of problem for commands (13,292 words reduced to 9,794)
- Prior learning: `knowledge-base/project/learnings/2026-02-25-plugin-command-double-namespace.md` -- documents plugin loader namespace behavior
- Prior learning: `knowledge-base/project/learnings/2026-02-22-simplify-workflow-thin-router-over-migration.md` -- documents plugin loader constraints
- Test infrastructure: `plugins/soleur/test/components.test.ts` and `plugins/soleur/test/helpers.ts`
- Official spec reference: `plugins/soleur/skills/skill-creator/references/official-spec.md`
- Constitution: `knowledge-base/project/constitution.md` -- "Heavy, conditionally-used content in command/skill bodies must be extracted to reference files"

### External References

- Claude Code plugin skill discovery: auto-discovers from `skills/*/SKILL.md`, loads name+description at startup
- Claude Code skill spec: description max 1024 characters, name max 64 characters
- GitHub issue: #618

## MVP

### `plugins/soleur/scripts/verify-skills.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

# --- Skill Verification ---

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="$PLUGIN_ROOT/skills"

errors=0
skill_count=0
total_words=0
names=()

for skill_dir in "$SKILLS_DIR"/*/; do
  skill_file="$skill_dir/SKILL.md"
  [ -f "$skill_file" ] || continue
  skill_count=$((skill_count + 1))
  dir_name=$(basename "$skill_dir")

  # Extract name from frontmatter
  name=$(sed -n '/^---$/,/^---$/{ /^---$/d; p }' "$skill_file" | grep '^name:' | head -1 | sed 's/^name: *//' | tr -d '"')
  if [ -z "$name" ]; then
    echo "[error] $dir_name: missing name in frontmatter" >&2
    errors=$((errors + 1))
    continue
  fi

  # Check name matches directory
  if [ "$name" != "$dir_name" ]; then
    echo "[error] $dir_name: name '$name' does not match directory" >&2
    errors=$((errors + 1))
  fi

  # Extract description
  desc=$(sed -n '/^---$/,/^---$/{ /^---$/d; p }' "$skill_file" | grep '^description:' | head -1 | sed 's/^description: *//' | tr -d '"')
  desc_len=${#desc}
  if [ "$desc_len" -gt 1024 ]; then
    echo "[error] $dir_name: description exceeds 1024 chars ($desc_len)" >&2
    errors=$((errors + 1))
  fi

  # Word count
  wc=$(echo "$desc" | wc -w)
  total_words=$((total_words + wc))

  names+=("$name")
done

# Check duplicates
dupes=$(printf '%s\n' "${names[@]}" | sort | uniq -d)
if [ -n "$dupes" ]; then
  echo "[error] duplicate skill names: $dupes" >&2
  errors=$((errors + 1))
fi

echo "[info] $skill_count skills, $total_words description words, $errors errors"
if [ "$errors" -gt 0 ]; then
  exit 1
fi
echo "[ok] all skills verified"
```

### `plugins/soleur/test/components.test.ts` (addition)

```typescript
// Add to existing Skill frontmatter describe block:

test("cumulative description word count under budget", () => {
  const skills = discoverSkills();
  let totalWords = 0;
  for (const skillPath of skills) {
    const { frontmatter } = parseComponent(skillPath);
    const desc = String(frontmatter.description || "");
    totalWords += desc.split(/\s+/).filter(Boolean).length;
  }
  expect(totalWords).toBeLessThanOrEqual(2000);
});
```
