---
title: "Tasks: Upgrade Claude Opus 4.6 to 4.7"
status: pending
created: 2026-04-16
plan: knowledge-base/project/plans/2026-04-16-chore-upgrade-opus-4-6-to-4-7-plan.md
---

# Tasks: Upgrade Claude Opus 4.6 to 4.7

## 1. Edit All Files

- [ ] 1.1 Replace `claude-opus-4-6` → `claude-opus-4-7` in `.github/workflows/scheduled-competitive-analysis.yml:49`
- [ ] 1.2 Replace `claude-opus-4-6` → `claude-opus-4-7` in `.github/workflows/scheduled-growth-audit.yml:57`
- [ ] 1.3 Replace `claude-opus-4-6` → `claude-opus-4-7` in `.github/workflows/scheduled-ux-audit.yml:134`
- [ ] 1.4 Replace `claude-opus-4-6` → `claude-opus-4-7` in `agent-execution-patterns.md:233,239`
- [ ] 1.5 Replace `claude-opus-4-6` → `claude-opus-4-7` in `mobile-patterns.md:467,473`
- [ ] 1.6 Replace `claude-opus-4-6` → `claude-opus-4-7` in `architecture-patterns.md:428`
- [ ] 1.7 Replace `claude-opus-4-6` → `claude-opus-4-7` in `agent-native-testing.md:487`
- [ ] 1.8 Replace `claude-opus-4-6` → `claude-opus-4-7` and `Opus 4.6` → `Opus 4.7` in `providers.md:10,52,53,259`

## 2. Update Learning File

- [ ] 2.1 Add Opus 4.7 row to model ID table in `2026-02-22-model-id-update-patterns.md`
- [ ] 2.2 Add thinking API format change note (adaptive + output_config.effort)

## 3. Verify

- [ ] 3.1 `grep -rn "claude-opus-4-6" .github/ plugins/` returns zero
- [ ] 3.2 `grep -rn "claude-opus-4-7" .github/ plugins/` returns 13+ results
- [ ] 3.3 `grep -rn "Opus 4\.7" plugins/soleur/skills/` confirms human-readable updates
