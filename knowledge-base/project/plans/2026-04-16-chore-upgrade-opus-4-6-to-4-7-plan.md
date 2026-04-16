---
title: "chore: Upgrade Claude Opus 4.6 to 4.7"
type: chore
date: 2026-04-16
---

# chore: Upgrade Claude Opus 4.6 to 4.7

Migrate all active `claude-opus-4-6` references to `claude-opus-4-7`. Opus 4.7 is a
direct upgrade — same pricing, improved capabilities, confirmed live via API on
2026-04-16.

Ref #2439

## Acceptance Criteria

- [x] `grep -rn "claude-opus-4-6" .github/ plugins/` returns zero results
- [x] `grep -rn "Opus 4\.6" plugins/soleur/skills/` returns zero in non-archived files
- [x] No changes to archived/historical files
- [x] Model ID learning file updated with Opus 4.7 row and thinking API format note

## Implementation

### Edit All Files (8 files, 13 occurrences)

Replace `claude-opus-4-6` with `claude-opus-4-7` (and human-readable "Opus 4.6" with
"Opus 4.7") in all active files:

| File | Lines | Notes |
|------|-------|-------|
| `.github/workflows/scheduled-competitive-analysis.yml` | 49 | `--model` flag |
| `.github/workflows/scheduled-growth-audit.yml` | 57 | `--model` flag |
| `.github/workflows/scheduled-ux-audit.yml` | 134 | `--model` flag |
| `plugins/soleur/skills/agent-native-architecture/references/agent-execution-patterns.md` | 233, 239 | Swift example |
| `plugins/soleur/skills/agent-native-architecture/references/mobile-patterns.md` | 467, 473 | Swift example |
| `plugins/soleur/skills/agent-native-architecture/references/architecture-patterns.md` | 428 | Swift example |
| `plugins/soleur/skills/agent-native-architecture/references/agent-native-testing.md` | 487 | JS example |
| `plugins/soleur/skills/dspy-ruby/references/providers.md` | 10, 52, 53, 259 | API ID (`anthropic/claude-opus-4-6` prefixed format on line 53) + human-readable name |

### Update Learning File (1 file)

Update `knowledge-base/project/learnings/2026-02-22-model-id-update-patterns.md`:

- Add Opus 4.7 row to the "Current Claude model IDs" table (keep Opus 4.6 as historical)
- Add a note documenting the thinking API format change: Opus 4.7 uses `thinking.type: "adaptive"` + `output_config.effort` instead of `thinking.type: "enabled"` + `budget_tokens`

### Post-Edit Verification

Run these greps to confirm completeness:

1. `grep -rn "claude-opus-4-6" .github/ plugins/` — expect zero
2. `grep -rn "claude-opus-4-7" .github/ plugins/` — expect 13+ results
3. `grep -rn "Opus 4\.7" plugins/soleur/skills/` — expect hits in providers.md

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change.

## Context

- Prior migration documented: `knowledge-base/project/learnings/2026-02-22-model-id-update-patterns.md`
- Key lesson: always grep independently (inventories undercount) and run post-edit verification
- The `anthropic/` prefix variant exists in `dspy-ruby/references/providers.md:53` — a naive `claude-opus-4-6` → `claude-opus-4-7` replacement handles it correctly
- Competitive intelligence files mention "Opus 4.6" for Polsia's stack — leave unchanged (describes their technology)
- All archived brainstorms/plans/learning entries are historical records — preserve

## References

- Anthropic announcement: <https://www.anthropic.com/news/claude-opus-4-7>
- API verification: model responds to `claude-opus-4-7` ID, `output_config.effort: "xhigh"` works
- Prior migration: #219, learning file `2026-02-22-model-id-update-patterns.md`
- Issue: #2439
- Branch: `feat-model-upgrade-opus-4-7`
