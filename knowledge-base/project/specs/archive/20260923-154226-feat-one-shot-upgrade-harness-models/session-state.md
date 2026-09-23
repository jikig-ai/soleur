# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-23-feat-upgrade-harness-models-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None (three hook-blocked writes fixed on retry: plan-write wording, gh issue body-file literal path, Mandated-By line).

### Decisions
- Anthropic: Opus 5.5 `claude-opus-5-5` (2026-09-22). Deferred to Phase B (#7773): pinned claude-code 2.1.219 lacks the ID; 2.1.280 (first with it) clears the 3-day package-age floor 2026-09-25T15:44:39Z.
- xAI: Grok 4.7 `grok-4.7` (2026-09-21). Phase A in this PR: harness-model-map.ts standard/strong/advisor -> grok-4.7, workflow copies + tests, ADR-110 addendum, model-launch-review Grok row. Cheap stays grok-4.5.
- OpenAI: GPT-6 Sol/Luna (2026-09-22). No code change: repo pins no Codex model; default is already gpt-6-sol.
- Out of scope: Grok dogfood host baseline, claude-code-action pin bump, Codex tier map.
- Deferred issues filed: #8603 (CI CLI-knows-model check), #8604 (.grok/agents model: haiku).

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; repo-research-analyst, learnings-researcher, best-practices-researcher, git-history-analyzer, cto, dhh/kieran/simplicity reviewers, architecture-strategist.
