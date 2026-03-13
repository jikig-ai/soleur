---
title: Update outdated Claude 3 model IDs to Claude 4.x
type: fix
date: 2026-02-22
issue: "#219"
---

# Update Outdated Claude 3 Model IDs to Claude 4.x

## Overview

Multiple reference files contain hardcoded Claude 3/3.5 model IDs that are now outdated. Users copying code examples get deprecation warnings or failures. Update all 8 affected files (~32 references) to current Claude 4.x identifiers.

## Acceptance Criteria

- [ ] Zero occurrences of `claude-3-haiku-20240307`, `claude-3-sonnet-20240229`, `claude-3-opus-20240229`, `claude-3-5-sonnet-20241022` remain in the codebase
- [ ] Zero occurrences of shorthand `claude-3-haiku`, `claude-3-sonnet`, `claude-3-opus`, `claude-3-5-sonnet`, `claude-3.5-sonnet` remain
- [ ] All replacements use correct current model IDs
- [ ] Stale pricing comments updated where present
- [ ] Stale Claude 4.0 IDs (`claude-sonnet-4-20250514`, `claude-opus-4-20250514`) on lines 238-239 of `agent-execution-patterns.md` updated to latest 4.6

## Research Enhancement (2026-02-22)

Verified model IDs against official Anthropic documentation at https://platform.claude.com/docs/en/about-claude/models/overview

**Key correction:** Lines 238-239 of `agent-execution-patterns.md` were flagged as "already updated" but use old Claude 4.0 IDs (`claude-sonnet-4-20250514`, `claude-opus-4-20250514`). These must also be updated to the latest 4.6 aliases.

## Test Scenarios

- Given a full `grep -r "claude-3"` across the repo, when run after changes, then zero matches in `plugins/soleur/skills/` directories
- Given a full `grep -r "claude-.*-4-20250514"` across the repo, when run after changes, then zero matches (old 4.0 IDs removed)

## Model ID Mapping

Source: https://platform.claude.com/docs/en/about-claude/models/overview

### Code examples (where exact model ID is used in API calls)

Use the latest model aliases. These are the current production IDs.

| Old ID | New ID (latest alias) |
|--------|--------|
| `claude-3-haiku-20240307` | `claude-haiku-4-5` |
| `claude-3-sonnet-20240229` | `claude-sonnet-4-6` |
| `claude-3-opus-20240229` | `claude-opus-4-6` |
| `claude-3-5-sonnet-20241022` | `claude-sonnet-4-6` |
| `claude-sonnet-4-20250514` | `claude-sonnet-4-6` |
| `claude-opus-4-20250514` | `claude-opus-4-6` |
| `claude-3.5-sonnet` (OpenRouter format) | `claude-sonnet-4-6` |

### Comments and descriptive text (use generic tier names)

| Old Reference | New Reference |
|---------------|---------------|
| `claude-3-haiku: Quick, cheap...` | `claude-haiku-4-5: Quick, cheap...` |
| `claude-3-sonnet: Good balance...` | `claude-sonnet-4-6: Good balance...` |
| `claude-3-opus: Complex reasoning...` | `claude-opus-4-6: Complex reasoning...` |
| `claude-3-5-sonnet` (in prose) | `claude-sonnet-4-6` |

### Pricing updates (where pricing is mentioned)

| Tier | Old Price | Current Price (Feb 2026) |
|------|-----------|---------------|
| Fast (Haiku 4.5) | ~$0.25/1M tokens | $1/1M input, $5/1M output |
| Balanced (Sonnet 4.6) | ~$3/1M tokens | $3/1M input, $15/1M output |
| Powerful (Opus 4.6) | ~$15/1M tokens | $5/1M input, $25/1M output |

## MVP

### File-by-file changes

#### 1. `plugins/soleur/skills/agent-native-architecture/references/agent-execution-patterns.md`

- Line 231: `claude-3-haiku` -> `claude-haiku-4-5` (comment)
- Line 237: `claude-3-haiku-20240307` -> `claude-haiku-4-5` (code)
- Line 238: `claude-sonnet-4-20250514` -> `claude-sonnet-4-6` (stale 4.0 ID)
- Line 239: `claude-opus-4-20250514` -> `claude-opus-4-6` (stale 4.0 ID)

#### 2. `plugins/soleur/skills/agent-native-architecture/references/mobile-patterns.md`

- Lines 465-467: Update all three tier comments to 4.x names and pricing
- Lines 471-473: Update all three `return` string values to 4.x dated IDs

#### 3. `plugins/soleur/skills/agent-native-architecture/references/agent-native-testing.md`

- Line 487: `claude-3-haiku` -> `claude-haiku-4-5`, `claude-3-opus` -> `claude-opus-4-6`
- Line 518: `claude-3-haiku` -> `claude-haiku-4-5`

#### 4. `plugins/soleur/skills/agent-native-architecture/references/architecture-patterns.md`

- Lines 426-428: Update three tier comment references to 4.x names

#### 5. `plugins/soleur/skills/dspy-ruby/SKILL.md`

- Line 164: `claude-3-5-sonnet-20241022` -> `claude-sonnet-4-6`
- Lines 200-201: Update model names in prose list

#### 6. `plugins/soleur/skills/dspy-ruby/references/providers.md`

- Lines 53, 57, 61, 65: Update all four Anthropic `DSPy::LM.new` calls
- Line 115: Update OpenRouter Anthropic reference
- Line 183: Update powerful_lm reference
- Lines 225, 227: Update prose model name references
- Line 245: Update config example

#### 7. `plugins/soleur/skills/dspy-ruby/assets/config-template.rb`

- Lines 24, 42, 66, 99, 219: Update all `DSPy::LM.new` Anthropic model IDs
- Line 309: Update comment model reference

#### 8. `plugins/soleur/skills/dspy-ruby/assets/module-template.rb`

- Line 230: Update Anthropic model ID

## Verification

After all changes:

```bash
# Must return zero results in plugins/soleur/skills/
grep -rn "claude-3" plugins/soleur/skills/ | grep -v "claude-3\." | head -20
grep -rn "claude-3-" plugins/soleur/skills/
grep -rn "claude-3\." plugins/soleur/skills/

# Verify correct new IDs are present
grep -rn "claude-haiku-4-5" plugins/soleur/skills/
grep -rn "claude-sonnet-4" plugins/soleur/skills/
grep -rn "claude-opus-4" plugins/soleur/skills/
```

## References

- Issue: #219
- Existing 4.x convention: `apps/telegram-bridge/` uses `claude-opus-4-6`
- Official model docs: https://platform.claude.com/docs/en/about-claude/models/overview
- Lines 238-239 of `agent-execution-patterns.md` had stale Claude 4.0 IDs -- updated to 4.6
