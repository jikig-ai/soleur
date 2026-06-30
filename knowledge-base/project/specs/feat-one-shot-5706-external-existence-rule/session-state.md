# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-29-docs-extend-verify-rule-external-existence-plan.md
- Status: complete

### Errors
None. (Two items investigated and resolved during deepen: the `cq-rule-ids-are-immutable` retired-registry hit was a comment-line false positive — rule is active; #4599/#4819 do not resolve as PRs but resolve as CLOSED issues, since GitHub numbers are unified.)

### Decisions
- Premise correction (stale threshold): issue states budget is over 22,000, but the real `lint-agents-rule-budget.py` reject cap is 23000 (raised in #4599). Current B_ALWAYS = 22979 → 21 B headroom.
- Byte feasibility proven: measured 480 B fold-in candidate fits (B_ALWAYS → 22986 ≤ 23000); paired trim not strictly required, net ≤ 0 preferred.
- Fold into existing rule body, no new rule; reword the now-contradictory "Scope: this-repo artifacts, not general facts." clause; rule id stays immutable.
- Test/lint constraints pinned as ACs: keep "subagent" before the id within 400 chars; per-rule ≤ 600 B; budget/rule-id/enforcement-tag linters green.
- Scoped minimal: SKILL.md prose mirrors, rule-metrics.json, and the source learning are explicit Non-Goals.

### Components Invoked
- Skill: soleur:plan (#5706)
- Skill: soleur:deepen-plan (plan file path)
- gh CLI, Bash/Read/Edit/Write for inline research
- No Task/research/review sub-agents spawned
