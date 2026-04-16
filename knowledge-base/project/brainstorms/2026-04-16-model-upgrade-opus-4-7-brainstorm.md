---
title: Model Upgrade - Claude Opus 4.7
date: 2026-04-16
status: complete
---

# Model Upgrade: Claude Opus 4.6 to Opus 4.7

## What We're Building

Migrate all active `claude-opus-4-6` references to `claude-opus-4-7` across CI workflows, skill reference docs, and example code. Document the new thinking API format introduced in Opus 4.7 for future development.

## Why This Approach

Opus 4.7 is a direct upgrade to Opus 4.6 with same pricing ($5/$25 per M tokens), improved instruction following, better software engineering performance, and higher-resolution vision. The model is fully rolled out (verified via API on 2026-04-16). No fallback needed.

Sonnet 4.6 and Haiku 4.5 remain unchanged — only Opus references are affected.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Fallback strategy | None | Model is live and stable; simple swap like 4.0 to 4.6 migration |
| Scope | ID swap + skill refs + API docs | Minimal runtime risk, maximum documentation value |
| New features to adopt | Document only | xhigh effort, adaptive thinking, task budgets documented but not wired into runtime code |
| Historical files | Preserve as-is | Archived plans and existing learning entries are accurate historical records |

## Files to Update

### CI Workflows (3 files)

- `.github/workflows/scheduled-competitive-analysis.yml:49`
- `.github/workflows/scheduled-growth-audit.yml:57`
- `.github/workflows/scheduled-ux-audit.yml:134`

### Skill Reference Docs (5 files)

- `plugins/soleur/skills/agent-native-architecture/references/agent-execution-patterns.md:233,239`
- `plugins/soleur/skills/agent-native-architecture/references/mobile-patterns.md:467,473`
- `plugins/soleur/skills/agent-native-architecture/references/agent-native-testing.md:487`
- `plugins/soleur/skills/agent-native-architecture/references/architecture-patterns.md:428`
- `plugins/soleur/skills/dspy-ruby/references/providers.md:53`

### Learning File (1 file — update, not replace)

- `knowledge-base/project/learnings/2026-02-22-model-id-update-patterns.md` — add Opus 4.7 row

### New Learning File (1 file — create)

- `knowledge-base/project/learnings/2026-04-16-opus-4-7-thinking-api-change.md` — document API format change

## API Change: Thinking Format

Opus 4.7 introduces a new thinking API format:

```text
Old (Opus 4.6):  thinking.type: "enabled", thinking.budget_tokens: N
New (Opus 4.7):  thinking.type: "adaptive", output_config.effort: "low"|"medium"|"high"|"xhigh"
```

The `xhigh` effort level is new to Opus 4.7. Sonnet 4.6 still uses the old format.

## Open Questions

None — scope is well-defined and all decisions are made.
